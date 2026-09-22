# -*- coding: utf-8 -*-
"""全量回归驱动：跑 `game/tools/` 下全部 `verify_*.tscn`，收集 `[FAIL]` 计数。

另含 `EXTRA_CHECKS` 里的非 `verify_*` 入口（当前是 `self_check` —— 最大的一套断言，
111 项）。判定口径：`[FAIL] == 0` **且** `exit == 0` **且** 输出了结果行；
任一不满足即判失败。退出码：全绿 0，否则 1。

用法
----
    python game/tools/run_regression.py                     # 默认：自动隔离 APPDATA（推荐）
    python game/tools/run_regression.py --use-real-appdata  # 用真实 %APPDATA% 再验一遍
    python game/tools/run_regression.py --only fix93        # 只跑名字含 "fix93" 的
    python game/tools/run_regression.py --exclude e2e       # 排除名字含 "e2e" 的
    python game/tools/run_regression.py --list              # 只列出将要跑的脚本
    python game/tools/run_regression.py --no-preflight      # 跳过开跑前的全项目解析预检

--------------------------------------------------------------------------------
为什么默认要**隔离 APPDATA**（2026-09-18 事故，必读）
--------------------------------------------------------------------------------
Windows 上 Godot 的 `user://` 由 `%APPDATA%` 推导，落在
`%APPDATA%\\Godot\\app_userdata\\七傳說\\`，其中 `saves\\` 是所有 verify 脚本
**共享**的存档目录。

两个人（或两个 CI job）**同时**跑回归时，就会有两个 Godot 进程抢同一批
`slot_*.json`。Windows 的文件锁会让 `DirAccess.rename()` 失败，于是
`SaveManager._atomic_write()` 报「无法将临时文件重命名为 'user://saves/slot_06.json'」，
测试表现为**随机变红**甚至**挂死**：

    verify_save → subprocess.TimeoutExpired: timed out after 120 seconds

这不是代码 bug，是**测试环境互相踩踏**。实测对照：同一份代码、同样的并发进程数，
只把 `APPDATA` 换成独立目录，结果立刻从「2 个脚本后挂死」变成「全部全绿」。

所以本脚本默认给**每次运行**分配一个独立临时目录：
    %TEMP%\\ge_regress_<pid>_<时间戳>\\
并在跑完后删除。这样并行跑多个 Godot 也不会互相锁，且不再需要人工记得设环境变量。

需要验证「真实用户目录下也对」时，加 `--use-real-appdata` 单独跑一次
（**此时不要与他人并发**，否则会复现上面的假红）。

--------------------------------------------------------------------------------
解析错误：为什么会「挂死」而不是「报错」（2026-09-20 事故，必读）
--------------------------------------------------------------------------------
队友在编辑 `tools/verify_level_gen.gd` 中途被中断，留下 4 处解析错误。表现不是
「测试红了」，而是**静默挂死 120 秒后 exit=124**，很容易被误读成基础设施问题：

  1. 主场景脚本解析失败 ⇒ 场景根本不会实例化；
  2. `VerifyWatchdog.arm()` 写在 `_ready()` 里 ⇒ 永远到不了 `_ready()`，
     **看门狗对解析错误结构性失明**（它兜的是运行时异常，不是加载失败）；
  3. 进程既不报错也不退出，只能耗到本脚本的 120s 墙钟兜底。

实测：解析错误在**进程启动的头 0.1 秒**就打印完了，剩下 119.9 秒纯属空转。
所以本脚本做了两件事：

  * **开跑前预检**（`tools/parse_all.tscn`）：把全部 .gd 加载一遍（183 个约 5 秒），
    有解析失败就**直接中止**，不让回归白等。覆盖范围含游戏代码，不只是 verify 脚本。
    加 `--no-preflight` 可跳过。
  * **逐个脚本流式判定**：一边读输出一边找 `Parse Error`，命中后给 2.5 秒收尾就杀掉，
    并把 `文件:行` 直接打在回归输出里 —— 不用再去翻日志。

另外把「跑了但一条断言都没报」（NO-RESULT）也判为失败：空转的测试比失败的测试
更危险，因为它看起来是绿的。
"""

import argparse
import glob
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

# Godot 4.7.2（WinGet 安装）。如换机器，改这一行或用环境变量 GODOT_BIN 覆盖。
DEFAULT_GODOT = (
    r"C:\Users\11265\AppData\Local\Microsoft\WinGet\Packages"
    r"\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
    r"\Godot_v4.7.2-stable_win64_console.exe"
)

# 看门狗（verify_watchdog.gd）会在 60s 时自杀并 exit 1；这里留 2 倍余量做最后兜底。
PER_SCRIPT_TIMEOUT = 120

# 不是测试脚本，别当成 verify 跑（它没有 .tscn，这里显式排除以防将来补上）。
NOT_A_TEST = {"verify_watchdog"}

# 除 `verify_*.tscn` 之外，还要跑的东西。值是附加在 Godot 之后的 argv。
#
# `self_check` 是**最大的一套断言（111 项）**，也是 README 里主推的验证入口，
# 却因为文件名不匹配 `verify_*` 而长期游离在全量回归之外。它的「无头下不退出」
# ——打印完报告后挂死到超时、退出码 124——就是这样藏了下来的（2026-09-20 发现并修复）。
EXTRA_CHECKS = [
    ("self_check", ["--", "--verify"]),
]

# 解析/加载期致命错误。出现这些字样的脚本**根本不会执行**，看门狗也就永远不会被
# 武装（它写在 `_ready()` 里），进程只会静默挂死 —— 见文件头「解析错误」一节。
PARSE_ERR_PAT = re.compile(r"Parse Error|with error \"Parse error\"")

# 从 `at: GDScript::reload (res://tools/x.gd:356)` 里抠出「文件:行」。
PARSE_AT_PAT = re.compile(r"at:\s*\S*\s*\((res://[^:)]+):(\d+)\)")

# 看到解析错误后再等这么久收尾（把 `Parse Error` / `at:` / `Failed to load` 收全）再杀。
# 实测解析错误在启动头 0.1 秒就打印完了，2.5 秒绰绰有余。
PARSE_GRACE = 2.5

# 解析预检自身的超时。183 个 .gd 实测约 5 秒；30 秒意味着「预检自己挂住了」。
PREFLIGHT_TIMEOUT = 30


def find_godot() -> str:
    return os.environ.get("GODOT_BIN", DEFAULT_GODOT)


def discover_scripts(tools_dir: str) -> list:
    """自动发现全部 verify_*.tscn —— 不再维护硬编码清单，新增脚本自动纳入。"""
    found = []
    for path in sorted(glob.glob(os.path.join(tools_dir, "verify_*.tscn"))):
        name = os.path.splitext(os.path.basename(path))[0]
        if name in NOT_A_TEST:
            continue
        found.append(name)
    return found


def make_isolated_appdata() -> str:
    """每次运行独立的 user:// 落点，避免与他人共享 saves 目录而互相锁文件。"""
    stamp = time.strftime("%Y%m%d_%H%M%S")
    path = os.path.join(tempfile.gettempdir(),
                        "ge_regress_%d_%s" % (os.getpid(), stamp))
    os.makedirs(path, exist_ok=True)
    return path


def resolve_real_appdata(env: dict) -> tuple:
    """`--use-real-appdata` 要用的「真实」用户数据目录。

    ⚠️ **不能**直接用继承来的 `APPDATA` —— 无头 / 精简 shell 里它可能是**空串**
    （本项目已实测踩到过），那样 `user://` 会退化成相对路径，跑出来的是
    「已知会坏的那条路径」，而不是「真实用户目录」。空的时候按 Windows 标准
    从 `USERPROFILE` 推出来。

    返回 `(路径, 是否是推导出来的)`；两者都拿不到时返回 `("", True)`。
    """
    cur = (env.get("APPDATA") or "").strip()
    if cur:
        return cur, False
    profile = (env.get("USERPROFILE") or "").strip()
    if profile:
        return os.path.join(profile, "AppData", "Roaming"), True
    return "", True


def _result_line(out: str) -> str:
    """从输出里找「结果行」，找不到返回 `NO-RESULT`。

    前缀不统一，所以按**内容**找而不是按固定前缀切分：
        `===== 结果：0 项失败 =====`
        `===== 端到端结果：0 项失败 =====`
        `[Main] 结果：全部通过（111 项）。骨架就绪，可以进入阶段 2。`
    """
    for line in out.splitlines():
        if "项失败" in line or "全部通过（" in line or "项未通过" in line:
            txt = line.strip().strip("=").strip()
            for pref in ("[Main] ", "[Verify] "):
                if txt.startswith(pref):
                    txt = txt[len(pref):]
            # 只取到第一个句号：`全部通过（111 项）。骨架就绪，可以进入阶段 2。`
            # 后半句是给人看的说明，塞进状态列只会把表格撑坏。
            cut = txt.find("。")
            if cut > 0:
                txt = txt[:cut]
            return txt
    return "NO-RESULT"


def _extract_location(out: str) -> str:
    """从 Godot 输出里抠出 `at: GDScript::reload (res://tools/x.gd:356)` 的位置。"""
    m = PARSE_AT_PAT.search(out)
    if not m:
        return ""
    return "%s:%s" % (m.group(1), m.group(2))


def _summarize_preflight(out: str) -> str:
    """把预检输出过滤成「只有信号」的几行。

    Godot 对每个失败脚本会打一大坨 `GDScript backtrace` + `Failed to load script`，
    直接倒出来会把真正有用的 `[parse_all] x <文件>` 和 `at: <文件>:<行>` 淹掉。
    """
    keep = []
    for ln in out.splitlines():
        if (ln.startswith("[parse_all]")
                or "Parse Error" in ln
                or "Compile Error" in ln
                or "Failed to load script" in ln
                or "at: GDScript::reload" in ln):
            keep.append(ln)
    return "\n".join(keep)


def preflight_parse_all(godot: str, game_dir: str, env: dict) -> tuple:
    """开跑前把全部 .gd 解析一遍，返回 `(退出码, 输出)`。

    解析失败的脚本「静默挂死」而不是「报错」—— 因为 `VerifyWatchdog.arm()` 写在
    `_ready()` 里，而解析失败的脚本根本到不了 `_ready()`。与其让每个坏脚本各挂满
    120 秒、再从日志里捞 `Parse Error`，不如开跑前一次性问完。

    没有 `tools/parse_all.tscn` 时不拦截（回归照跑），免得工具缺失反而卡住回归。
    """
    if not os.path.isfile(os.path.join(game_dir, "tools", "parse_all.tscn")):
        return 0, ""
    cmd = [godot, "--headless", "--path", game_dir, "res://tools/parse_all.tscn"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True,
                           encoding="utf-8", errors="replace",
                           timeout=PREFLIGHT_TIMEOUT, env=env)
    except subprocess.TimeoutExpired:
        return 1, ("!! 解析预检自身超时（%ds）—— 大概率是加载某个脚本时挂住了。"
                   % PREFLIGHT_TIMEOUT)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def run_streaming(cmd: list, env: dict, timeout: float, parse_grace: float) -> tuple:
    """跑一个 verify 场景，**边读输出边判定**，返回 `(输出, 退出码, 是否超时, 解析错误行)`。

    为什么不用 `subprocess.run`：解析失败的脚本会**静默挂死** —— 主场景脚本加载失败
    ⇒ 场景不实例化 ⇒ `_ready()` 里的看门狗没被武装 ⇒ 进程既不报错也不退出。
    而解析错误在**启动头 0.1 秒**就打印完了，剩下 119.9 秒纯属空转。
    所以一看到解析错误、给 `parse_grace` 秒收尾，立刻杀掉：
    全量回归里每个坏脚本从 120 秒降到约 2 秒。

    读用线程 + 队列，不用 `readline()`：`readline()` 在进程无输出时会**永久阻塞**，
    那样墙钟超时就永远检查不到 —— 这正是「看门狗兜不住时连 timeout 也一起失效」的成因。
    """
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, encoding="utf-8", errors="replace", env=env)
    q = queue.Queue()

    def _pump() -> None:
        try:
            for line in p.stdout:
                q.put(line)
        finally:
            q.put(None)          # 哨兵：stdout 已关闭（进程结束）

    threading.Thread(target=_pump, daemon=True).start()

    lines = []
    parse_hits = []
    kill_deadline = None
    timed_out = False
    start = time.time()
    while True:
        if time.time() - start > timeout:
            timed_out = True
            p.kill()
            break
        try:
            line = q.get(timeout=0.1)
        except queue.Empty:
            line = ""
        if line is None:
            break
        if line:
            lines.append(line)
            if PARSE_ERR_PAT.search(line):
                parse_hits.append(line.rstrip())
                if kill_deadline is None:
                    kill_deadline = time.time() + parse_grace
        if kill_deadline is not None and time.time() >= kill_deadline:
            p.kill()
            break

    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait(timeout=5)
    code = p.returncode if p.returncode is not None else -1
    return "".join(lines), code, timed_out, parse_hits


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    game_dir = os.path.normpath(os.path.join(here, ".."))
    tools_dir = os.path.join(game_dir, "tools")

    ap = argparse.ArgumentParser(description="七傳說 · 全量 verify 回归")
    ap.add_argument("--use-real-appdata", action="store_true",
                    help="用真实 %%APPDATA%%（验真实路径；不要与他人并发跑）")
    ap.add_argument("--only", action="append", default=[],
                    help="只跑名字含该子串的脚本（可重复）")
    ap.add_argument("--exclude", action="append", default=[],
                    help="排除名字含该子串的脚本（可重复）")
    ap.add_argument("--list", action="store_true", help="只列出将要跑的脚本")
    ap.add_argument("--no-preflight", action="store_true",
                    help="跳过开跑前的全项目解析预检（tools/parse_all.tscn）")
    args = ap.parse_args()

    scripts = discover_scripts(tools_dir)
    if args.only:
        scripts = [s for s in scripts if any(k in s for k in args.only)]
    if args.exclude:
        scripts = [s for s in scripts if not any(k in s for k in args.exclude)]

    # 统一成 `(名字, 附加 argv)`：普通 verify 脚本跑自己的场景，额外的入口跑各自的命令。
    jobs = [(s, ["res://tools/%s.tscn" % s]) for s in scripts]
    for nm, argv in EXTRA_CHECKS:
        if args.only and not any(k in nm for k in args.only):
            continue
        if args.exclude and any(k in nm for k in args.exclude):
            continue
        jobs.append((nm, argv))

    if args.list:
        print("共 %d 个：" % len(jobs))
        for nm, _ in jobs:
            print("  " + nm)
        return 0

    godot = find_godot()
    if not os.path.isfile(godot):
        print("!! 找不到 Godot：%s" % godot)
        print("   可用环境变量 GODOT_BIN 指定。")
        return 2

    env = dict(os.environ)
    isolated = None
    if args.use_real_appdata:
        real, derived = resolve_real_appdata(env)
        if not real:
            print("!! --use-real-appdata 但 APPDATA 与 USERPROFILE 都拿不到，无法确定真实目录。")
            return 2
        env["APPDATA"] = real
        print("APPDATA = 真实环境 %s%s"
              % (real, "（继承到的 APPDATA 为空，已按 USERPROFILE 推出）"
                 if derived else ""))
        print("  ⚠️ 请确保没有其他人并发跑回归，"
              "否则会复现「共享 saves 目录互相锁文件」的假红。")
    else:
        isolated = make_isolated_appdata()
        env["APPDATA"] = isolated
        print("APPDATA = 隔离目录 %s" % isolated)
    print("将跑 %d 个脚本：%s\n" % (len(jobs), ", ".join(nm for nm, _ in jobs)))

    # ---- 预检：全项目 GDScript 解析 ----
    # 解析失败的脚本**根本不会执行**，看门狗（写在 `_ready()` 里）永远不会被武装，
    # 于是表现为「静默挂死到超时」而不是「报错」。与其让每个坏脚本各挂满 120 秒、
    # 再从日志里捞 `Parse Error`，不如开跑前一次性问完（183 个 .gd 实测约 5 秒）。
    if not args.no_preflight:
        pf_rc, pf_out = preflight_parse_all(godot, game_dir, env)
        if pf_rc != 0:
            print(_summarize_preflight(pf_out).rstrip())
            print("\n!! 预检未通过：存在解析失败的文件，已中止回归。")
            print("   （解析失败的脚本连 `_ready()` 都到不了，跑下去只会白等超时；"
                  "加 --no-preflight 可强行跑。）")
            return 1
        print("解析预检：全部 .gd 可解析\n")

    all_ok = True
    parse_broken = []       # [(脚本名, "文件:行", 错误行)]
    no_result = []          # 跑了但没输出结果行的脚本
    started = time.time()
    try:
        for name, extra_argv in jobs:
            cmd = [godot, "--headless", "--path", game_dir] + extra_argv
            out, code, timed_out, parse_hits = run_streaming(
                cmd, env, PER_SCRIPT_TIMEOUT, PARSE_GRACE)
            fails = out.count("[FAIL]")
            status = _result_line(out)

            bad = fails > 0 or code != 0
            if parse_hits:
                status = "PARSE-ERROR"
                parse_broken.append((name, _extract_location(out), parse_hits[0]))
                bad = True
            elif timed_out:
                status = "TIMEOUT(%ds)" % PER_SCRIPT_TIMEOUT
                bad = True
            elif status == "NO-RESULT":
                # 跑了、退了、但**一条断言都没报**。空转的测试比失败的测试更危险：
                # 它看起来是绿的。本项目原则「非空即非空转」。
                no_result.append(name)
                bad = True

            print("%-28s %-24s FAIL=%d exit=%d" % (name, status, fails, code))
            if bad:
                all_ok = False
                # 失败时把该脚本的输出落到临时文件，便于定位
                dump = os.path.join(tempfile.gettempdir(), "ge_regress_fail_%s.log" % name)
                with open(dump, "w", encoding="utf-8") as f:
                    f.write(out)
                if parse_hits:
                    print("%-28s 解析错误 → %s" % ("", parse_hits[0]))
                    print("%-28s 出错位置 → %s" % ("", _extract_location(out) or "(见明细)"))
                elif timed_out:
                    print("%-28s !! 超时（%ds）—— 看门狗没兜住"
                          % ("", PER_SCRIPT_TIMEOUT))
                elif status == "NO-RESULT":
                    print("%-28s !! 没输出结果行（跑了但没断言，等于空转）" % "")
                print("%-28s 明细 → %s" % ("", dump))
    finally:
        if isolated:
            shutil.rmtree(isolated, ignore_errors=True)

    print("\n耗时 %.1fs，%d 个脚本，%s"
          % (time.time() - started, len(jobs),
             "全部全绿" if all_ok else "有失败项"))

    if parse_broken:
        print("\n!! %d 个脚本**解析失败**（脚本没能运行，看门狗对解析错误结构性失明）："
              % len(parse_broken))
        for nm, loc, msg in parse_broken:
            print("   %-24s %s" % (nm, loc or "(位置未解析出来)"))
            print("   %-24s %s" % ("", msg))
    if no_result:
        print("\n!! %d 个脚本没有输出结果行（跑了但一条断言都没报，等于空转）：%s"
              % (len(no_result), ", ".join(no_result)))

    if not all_ok:
        print("\n提示：`--only <子串>` 只跑关心的脚本；`--no-preflight` 跳过解析预检。")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
