#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全量回歸：一條命令串起所有 Godot 頭無 verify + Python 策劃校驗器。

用法（在 D:\\七傳說 下）：
    <python> tools/run_regression.py
退出碼 0 = 全綠；1 = 有失敗。

每個測試超時 120s；失敗即記錄並繼續（不中止後續），最後打印匯總。
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
PLAN = os.path.join(ROOT, "deliverables", "gstack", "策划案")

PY = r"C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe"
GODOT = r"C:\Users\11265\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"

TIMEOUT = 120


def run_godot(scene: str) -> tuple[bool, str]:
    cmd = [GODOT, "--headless", "--path", GAME, f"res://tools/{scene}.tscn"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT, encoding="utf-8", errors="replace")
        out = (p.stdout or "") + (p.stderr or "")
        # 成功口徑：結果行印「0 项失败」或「全部通过」；出現 [FAIL] 或非零失敗數即掛。
        ok = (("0 项失败" in out or "0 項失敗" in out or "/ 0 失败" in out
               or "全部通过" in out or "全部通過" in out or "全部可解析" in out)
              and "[FAIL]" not in out)
        return ok, out[-400:]
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"


def run_py(script: str) -> tuple[bool, str]:
    # 01-05 校驗器硬編碼相對路徑、不接 --repo；06/07 接 --repo。
    if script.startswith(("06", "07")):
        cmd = [PY, os.path.join(PLAN, script), "--repo", ROOT]
    else:
        cmd = [PY, script]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT,
                           encoding="utf-8", errors="replace", cwd=PLAN)
        out = (p.stdout or "") + (p.stderr or "")
        # 口徑：01「落在设计区间」；02/04/05「N 通过 / 0 失败」；06/07「失败 0」。
        ok = p.returncode == 0 and (
            "落在设计区间" in out
            or "/ 0 失败" in out
            or "失败 0" in out
            or "失敗 0" in out)
        return ok, out[-400:]
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"


def main() -> int:
    t0 = time.time()
    fails = []

    # 1. parse 全量
    ok, tail = run_godot("parse_all")
    print(("[PASS] " if ok else "[FAIL] ") + "parse_all")
    if not ok:
        fails.append("parse_all")

    # 2. 所有 verify_*.tscn
    tools = os.path.join(GAME, "tools")
    scenes = sorted(f[:-5] for f in os.listdir(tools) if f.startswith("verify_") and f.endswith(".tscn"))
    for sc in scenes:
        ok, tail = run_godot(sc)
        print(("[PASS] " if ok else "[FAIL] ") + sc)
        if not ok:
            fails.append(sc)

    # 3. Python 校驗器 01-07
    pys = sorted(f for f in os.listdir(PLAN) if f.startswith(("0", "1")) and f.endswith(".py"))
    for s in pys:
        ok, tail = run_py(s)
        print(("[PASS] " if ok else "[FAIL] ") + s)
        if not ok:
            fails.append(s)

    print("=" * 60)
    print("耗時 %.1fs；失敗 %d 項" % (time.time() - t0, len(fails)))
    if fails:
        print("失敗清單：")
        for f in fails:
            print("  - " + f)
        return 1
    print("全綠")
    return 0


if __name__ == "__main__":
    sys.exit(main())
