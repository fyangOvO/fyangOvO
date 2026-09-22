# -*- coding: utf-8 -*-
"""战斗指标聚合：把 `user://metrics/combat_metrics.jsonl` 读成**回填能用的数**。

用法
----
    python game/tools/metrics_report.py                      # 读默认位置
    python game/tools/metrics_report.py <路径.jsonl>          # 读指定文件
    python game/tools/metrics_report.py --appdata <目录>      # 从指定 APPDATA 推路径

--------------------------------------------------------------------------------
这份报告要回答的唯一问题
--------------------------------------------------------------------------------
「20 关的 `total_monster_budget` 该回填成多少，才能让单局落在 D5 的 14–21 分钟？」

回填卡在一个**鸡生蛋**上：`sim-report §10.5.6` 的 269/关 建立在 **AoE = 2.0 设计基准**
上，而 §10.5.7 自承 AoE 未实测，且 §10.5.4 说「杂兵数 ∝ AoE」。

所以本报告**不猜**，只从实测数据里算三件事：

  1. **实测 AoE**（每 AoE 施放平均命中几只）—— 用来替换那个 2.0 设计基准。
  2. **AoE(密度) 曲线** —— 因为「杂兵数 ∝ AoE」是**双向**的：密度决定 AoE，
     AoE 又决定清怪速度。只给一个标量解不了不动点，必须看**命中数随场上敌人数怎么变**。
  3. **清怪速率**（只算交火时间）—— 单局时长 = 怪数 / 清怪速率，这是回填的换算系数。

--------------------------------------------------------------------------------
⚠️ 口径纪律
--------------------------------------------------------------------------------
* **只用交火时间算清怪速率**，不用总时长。总时长里含跑图 / 拾取 / 看面板，
  拿它换算会把「跑得慢」误算成「怪太少」。
* 数据量不足时**如实说不足**，不给外推值。样本 < 30 次 AoE 施放时明确标注。
* 本脚本只读文件，不写任何东西。
"""

import argparse
import json
import os
import sys

DEFAULT_REL = os.path.join("Godot", "app_userdata", "七傳說", "metrics",
                           "combat_metrics.jsonl")

## 样本少于这个数就不给结论（避免拿三局数据「实测」出一个数去回填）
MIN_AOE_CASTS = 30


def default_paths() -> list:
    """按可能性列出候选路径（真实 APPDATA / 便携模式落在项目内 / 直接给文件）。"""
    out = []
    appdata = (os.environ.get("APPDATA") or "").strip()
    if appdata:
        out.append(os.path.join(appdata, DEFAULT_REL))
    profile = (os.environ.get("USERPROFILE") or "").strip()
    if profile:
        out.append(os.path.join(profile, "AppData", "Roaming", DEFAULT_REL))
    # 无头 / 便携模式：user:// 会落到项目目录下（实测过，见 ContentPaths 的注释）
    here = os.path.dirname(os.path.abspath(__file__))
    game_dir = os.path.normpath(os.path.join(here, ".."))
    out.append(os.path.join(game_dir, "Godot", "app_userdata", "七傳說", "metrics",
                            "combat_metrics.jsonl"))
    return out


def load(path: str) -> tuple:
    """返回 (记录列表, 跳过的坏行数)。坏行不抛异常 —— 半截写入不该让整份报告读不出来。"""
    recs = []
    bad = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                bad += 1
                continue
            if isinstance(d, dict):
                recs.append(d)
            else:
                bad += 1
    return recs, bad


def _num(d: dict, k: str, default: float = 0.0) -> float:
    v = d.get(k, default)
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def aoe_curve(recs: list) -> list:
    """把所有 AoE 施放采样按「施放时场上敌人数」分桶，返回 [(桶, 次数, 平均命中)]。

    分桶边界按实际密度分布取，不预设「怪多怪少」的绝对含义 ——
    现数据均值 58.7 只，回填目标是 269，密度会整体上移一个量级，
    所以桶要能覆盖到很高的密度，否则回填后曲线就用不上了。
    """
    buckets = [(0, 3), (4, 7), (8, 15), (16, 31), (32, 63), (64, 127), (128, 10**9)]
    acc = {i: [0, 0] for i in range(len(buckets))}
    for r in recs:
        for s in r.get("aoe_samples", []) or []:
            if not isinstance(s, list) or len(s) < 2:
                continue
            try:
                alive, hits = int(s[0]), int(s[1])
            except (TypeError, ValueError):
                continue
            for i, (lo, hi) in enumerate(buckets):
                if lo <= alive <= hi:
                    acc[i][0] += 1
                    acc[i][1] += hits
                    break
    out = []
    for i, (lo, hi) in enumerate(buckets):
        n, hits = acc[i]
        if n == 0:
            continue
        label = "%d+" % lo if hi >= 10**9 else ("%d-%d" % (lo, hi) if lo != hi else str(lo))
        out.append((label, n, hits / n))
    return out


def report(recs: list, bad: int, path: str) -> str:
    L = []
    L.append("=" * 78)
    L.append("七傳說 · 战斗指标报告（任务 11.9 · AoE 实测埋点）")
    L.append("=" * 78)
    L.append("数据文件：%s" % path)
    L.append("记录数：%d 局%s" % (len(recs), "（跳过坏行 %d）" % bad if bad else ""))
    if not recs:
        L.append("")
        L.append("没有可用记录。先玩一局（进关卡 → 打怪 → 结算/放弃），再跑本报告。")
        return "\n".join(L)

    total_kills = sum(int(_num(r, "kills")) for r in recs)
    total_dur = sum(_num(r, "duration_s") for r in recs)
    total_combat = sum(_num(r, "combat_s") for r in recs)
    total_eng = sum(int(_num(r, "engagements")) for r in recs)
    aoe_casts = sum(int(_num(r, "aoe_casts")) for r in recs)
    aoe_hits = sum(int(_num(r, "aoe_hits")) for r in recs)

    L.append("")
    L.append("-- 总量 --")
    L.append("  总时长        %.1f 分钟（%d 局）" % (total_dur / 60.0, len(recs)))
    L.append("  交火时长      %.1f 分钟（占 %.0f%%）"
             % (total_combat / 60.0,
                (total_combat / total_dur * 100.0) if total_dur > 0 else 0.0))
    L.append("  总击杀        %d（交火 %d 次）" % (total_kills, total_eng))

    L.append("")
    L.append("-- 清怪速率（回填的换算系数）--")
    if total_combat > 0:
        L.append("  交火内清怪    %.2f 杀/分钟   ← **用这个换算单局时长**"
                 % (total_kills * 60.0 / total_combat))
    else:
        L.append("  交火内清怪    —— 无交火时间（数据不足）")
    if total_dur > 0:
        L.append("  含跑图总速率  %.2f 杀/分钟   ← 别用这个换算（含跑图/拾取/看面板）"
                 % (total_kills * 60.0 / total_dur))
    if total_eng > 0:
        L.append("  每次交火清怪  %.2f 只" % (total_kills / total_eng))

    L.append("")
    L.append("-- 实测 AoE（替换 sim 的 2.0 设计基准）--")
    if aoe_casts == 0:
        L.append("  没有 AoE 施放记录 —— 要么没打出 AoE 技能，要么技能表里没有 AOE 类型。")
    else:
        L.append("  AoE 施放 %d 次 / 命中 %d 次 ⇒ **平均 %.2f 命中/施放**"
                 % (aoe_casts, aoe_hits, aoe_hits / aoe_casts))
        if aoe_casts < MIN_AOE_CASTS:
            L.append("  ⚠️ 样本只有 %d 次（< %d）—— **不足以回填**，多打几局再回来看。"
                     % (aoe_casts, MIN_AOE_CASTS))
        else:
            L.append("  样本量 %d 次，够用。" % aoe_casts)

    L.append("")
    L.append("-- AoE(密度) 曲线（回填真正要的东西）--")
    L.append("  为什么需要曲线而不是一个数：「杂兵数 ∝ AoE」是**双向**的 ——")
    L.append("  密度决定 AoE，AoE 又决定清怪速度。只给标量解不了不动点。")
    curve = aoe_curve(recs)
    if not curve:
        L.append("  无采样。")
    else:
        L.append("  %-12s %8s %10s" % ["场上敌人数", "施放次数", "平均命中"])
        for label, n, avg in curve:
            L.append("  %-12s %8d %10.2f" % [label, n, avg])

    L.append("")
    L.append("-- 各技能 --")
    agg = {}
    for r in recs:
        for sid, s in (r.get("skills", {}) or {}).items():
            if not isinstance(s, dict):
                continue
            a = agg.setdefault(sid, {"casts": 0, "hits": 0, "whiffs": 0, "aoe": bool(s.get("aoe"))})
            a["casts"] += int(_num(s, "casts"))
            a["hits"] += int(_num(s, "hits"))
            a["whiffs"] += int(_num(s, "whiffs"))
    if not agg:
        L.append("  无技能施放记录。")
    else:
        L.append("  %-16s %6s %6s %8s %10s %8s"
                 % ["技能", "类型", "施放", "命中", "命中/施放", "放空率"])
        for sid in sorted(agg):
            a = agg[sid]
            casts = a["casts"] or 1
            L.append("  %-16s %6s %6d %6d %10.2f %7.0f%%"
                     % [sid, "AoE" if a["aoe"] else "单体", a["casts"], a["hits"],
                        a["hits"] / casts, a["whiffs"] * 100.0 / casts])

    L.append("")
    L.append("-- 分关 --")
    L.append("  %-12s %4s %6s %8s %9s %10s"
             % ["关卡", "难度", "击杀", "总时长", "交火时长", "交火内杀/分"])
    for r in recs:
        combat = _num(r, "combat_s")
        rate = (int(_num(r, "kills")) * 60.0 / combat) if combat > 0 else 0.0
        L.append("  %-12s %4d %6d %7.1f分 %8.1f分 %10.2f"
                 % [str(r.get("level_id", "?")), int(_num(r, "tier")),
                    int(_num(r, "kills")), _num(r, "duration_s") / 60.0,
                    combat / 60.0, rate])

    L.append("")
    L.append("-- 下一步（回填怎么做）--")
    L.append("  1. 用上面的「交火内清怪 杀/分钟」当作换算系数 R。")
    L.append("  2. 目标单局 14–21 分钟，其中交火占比按上面实测的「交火占 X%%」取。")
    L.append("  3. 需要击杀数 = R × 目标交火分钟数 ⇒ 得到每关应有的怪数。")
    L.append("  4. ⚠️ 但 AoE 会随密度上升 ⇒ R 也会上升，所以第 3 步算完要回到")
    L.append("     「AoE(密度) 曲线」迭代一次，直到 R 稳定。这就是为什么必须先有曲线。")
    return "\n".join(L)


def main() -> int:
    ap = argparse.ArgumentParser(description="七傳說 · 战斗指标聚合（任务 11.9）")
    ap.add_argument("path", nargs="?", help="combat_metrics.jsonl 路径")
    ap.add_argument("--appdata", help="从这个 APPDATA 推默认路径")
    args = ap.parse_args()

    path = args.path
    if not path and args.appdata:
        path = os.path.join(args.appdata, DEFAULT_REL)
    if not path:
        for cand in default_paths():
            if os.path.isfile(cand):
                path = cand
                break
    if not path or not os.path.isfile(path):
        print("找不到指标文件。试过：")
        for cand in default_paths():
            print("  " + cand)
        print("\n也可以直接给路径：python game/tools/metrics_report.py <路径>")
        return 2

    recs, bad = load(path)
    print(report(recs, bad, path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
