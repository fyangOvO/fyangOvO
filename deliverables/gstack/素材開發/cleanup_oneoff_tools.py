# -*- coding: utf-8 -*-
"""
清理 game/tools/ 下的「除錯殘骸 / 一次性腳本」。

⚠️ 執行時機：**請在 WorkBuddy 之外的終端機執行**。
   原因：本工作區內 `game/` 的個別檔案被外部行程（WorkBuddy 檔案監控）鎖住，
   `os.rename` / `os.remove` 一律回 `WinError 5`（與 `.godot` 的 .tmp 改名失敗同源）。
   WorkBuddy 關掉或改用一般 cmd/PowerShell 執行本腳本即可。

判定方式（不是憑檔名猜）：對每個檔名 grep `scripts/` `scenes/` `data/` 與 `tools/` 自身，
命中 **0** 才列入；命中 ≥1 的一律保留（例如 `fake_mana_target` / `fake_skill_ctrl`
被 `verify_skill_panel` 引用，故不動）。

用法：
  python cleanup_oneoff_tools.py --dry-run     # 只列出，不動
  python cleanup_oneoff_tools.py              # 移到隔離區（可回復）
  python cleanup_oneoff_tools.py --delete      # 直接刪除（不可回復）
"""
import argparse
import os
import shutil

TOOLS = r"D:/七傳說/game/tools"
QDIR = r"D:/七傳說/deliverables/_quarantine_2026-09-24/game__tools__oneoff"

# 零外部引用的除錯 / 一次性腳本（2026-09-24 逐檔 grep 驗證）
STEMS = [
    "_diag_kb", "debug_screenshot", "debug_skill", "diag_aoe",
    "diag_player_children", "sample_pixels",
    "tiles_diag", "tiles_search", "tiles_credits", "tiles_preview",
]
EXTS = [".gd", ".gd.uid", ".tscn", ".py", ".py.uid"]
EXTRA = ["_audit_report.txt"]
DIRS = ["__pycache__"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--delete", action="store_true",
                    help="直接刪除（預設是移到隔離區，可回復）")
    args = ap.parse_args()

    targets = []
    for s in STEMS:
        for e in EXTS:
            p = os.path.join(TOOLS, s + e)
            if os.path.exists(p):
                targets.append(p)
    for n in EXTRA:
        p = os.path.join(TOOLS, n)
        if os.path.exists(p):
            targets.append(p)

    print("命中 %d 個檔案 / %d 個目錄" % (len(targets), len(DIRS)))
    for p in targets:
        print("  ", os.path.relpath(p, TOOLS))
    for d in DIRS:
        print("   %s/ (整個目錄)" % d)

    if args.dry_run:
        print("\n--dry-run：未變更任何檔案")
        return 0

    if not args.delete:
        os.makedirs(QDIR, exist_ok=True)
    ok = fail = 0
    for p in targets:
        try:
            if args.delete:
                os.remove(p)
            else:
                shutil.move(p, os.path.join(QDIR, os.path.basename(p)))
            ok += 1
        except Exception as e:
            fail += 1
            print("  失敗 %s (%s)" % (os.path.basename(p), type(e).__name__))
    for d in DIRS:
        p = os.path.join(TOOLS, d)
        if not os.path.isdir(p):
            continue
        try:
            shutil.rmtree(p) if args.delete else shutil.move(p, os.path.join(QDIR, d))
            ok += 1
        except Exception as e:
            fail += 1
            print("  失敗 %s/ (%s)" % (d, type(e).__name__))
    print("\n成功 %d / 失敗 %d" % (ok, fail))
    if not args.delete and ok:
        print("隔離區：%s（回復＝移回 tools/）" % QDIR)
    if fail:
        print("⚠️ 有失敗：多半是被 WorkBuddy 檔案監控鎖住 ⇒ 請在 WorkBuddy 之外重跑。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
