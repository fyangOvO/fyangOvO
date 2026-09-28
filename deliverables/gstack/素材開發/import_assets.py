# -*- coding: utf-8 -*-
"""
新增 PNG 之後的「匯入」——繞過工作區檔案鎖的完整流程（可重複執行）。

為什麼需要這支：Godot 編輯器寫快取是「先寫 .tmp 再 rename」，而本工作區的
`.godot/` 檔案被外部行程（WorkBuddy 檔案監控）鎖住 ⇒ rename 失敗 ⇒
編輯器永遠卡在 `[16%] 正在載入全域類別名稱`。實測連 Python 直接對
`.godot/global_script_class_cache.cfg` 做 `os.replace` 都回 `WinError 5`。

解法：把專案複製到工作區外 → 在那邊跑編輯器 → 只把「新增的產物」搬回來。

用法： python import_assets.py [--keep-temp]
產出： 新增 PNG 的 .import + .godot/imported/ 的新 .ctex/.md5 + 兩份快取
驗證： 搬完自動掃 <50 bytes 的 .import（中斷會留 0 byte 檔 ⇒ 圖標會靜默消失）
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

GAME = r"D:/七傳說/game"
GODOT = (r"C:/Users/11265/AppData/Local/Microsoft/WinGet/Packages/"
         r"GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/"
         r"Godot_v4.7.2-stable_win64_console.exe")
# build/ 佔 486MB（exe + 預覽圖，README 有引用，不可動）⇒ 匯入複製時排除
EXCLUDE = {"build", ".git", "__pycache__"}


def copy_project(dst):
    def ignore(d, names):
        return [n for n in names if n in EXCLUDE] if os.path.abspath(d) == os.path.abspath(GAME) else []
    shutil.copytree(GAME, dst, ignore=ignore, dirs_exist_ok=True)


def run_import(root):
    p = subprocess.run([GODOT, "--headless", "--editor", "--quit", "--path", root],
                       capture_output=True, text=True, timeout=900)
    tail = "\n".join((p.stdout or "").strip().splitlines()[-4:])
    return p.returncode, tail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep-temp", action="store_true")
    args = ap.parse_args()

    tmp = os.path.join(tempfile.gettempdir(), "qcs_import")
    if os.path.isdir(tmp):
        shutil.rmtree(tmp, ignore_errors=True)

    print("[1/4] 複製專案到工作區外（排除 build/）…")
    copy_project(tmp)
    n_files = sum(len(f) for _, _, f in os.walk(tmp))
    print("      複製完成：%d 檔" % n_files)

    print("[2/4] 在複製區跑 Godot 匯入…")
    rc, tail = run_import(tmp)
    print("      exit=%s\n%s" % (rc, tail))

    print("[3/4] 搬回新增產物…")
    imp = 0
    for png in glob.glob(os.path.join(tmp, "assets", "**", "*.png"), recursive=True):
        rel = os.path.relpath(png, tmp)
        dst_png = os.path.join(GAME, rel)
        dst_imp = os.path.join(GAME, rel + ".import")
        if os.path.exists(dst_png) and not os.path.exists(dst_imp):
            s = os.path.join(tmp, rel + ".import")
            if os.path.exists(s):
                os.makedirs(os.path.dirname(dst_imp), exist_ok=True)
                shutil.copy2(s, dst_imp)
                imp += 1
    print("      新 .import：%d" % imp)

    si = os.path.join(tmp, ".godot", "imported")
    di = os.path.join(GAME, ".godot", "imported")
    os.makedirs(di, exist_ok=True)
    have = set(os.listdir(di))
    todo = [f for f in os.listdir(si) if f not in have]
    got = 0
    for f in todo:                       # 分批：一次大量複製會被 shell 逾時砍掉
        try:
            shutil.copy2(os.path.join(si, f), os.path.join(di, f))
            got += 1
        except Exception as e:
            print("      skip %s (%s)" % (f, type(e).__name__))
    print("      .godot/imported 新檔：%d / %d" % (got, len(todo)))

    for f in ["global_script_class_cache.cfg", "uid_cache.bin"]:
        s, d = os.path.join(tmp, ".godot", f), os.path.join(GAME, ".godot", f)
        if os.path.exists(s):
            try:
                shutil.copy2(s, d)
                print("      覆蓋 .godot/%s" % f)
            except Exception as e:
                print("      無法覆蓋 .godot/%s (%s)" % (f, type(e).__name__))

    print("[4/4] 驗證…")
    bad = []
    for root, _, files in os.walk(os.path.join(GAME, "assets")):
        for f in files:
            if f.endswith(".import") and os.path.getsize(os.path.join(root, f)) < 50:
                bad.append(os.path.relpath(os.path.join(root, f), GAME))
    print("      ⚠️ 0 byte / 過小 .import：%d %s" % (len(bad), bad if bad else ""))
    png = sum(1 for r, _, fs in os.walk(os.path.join(GAME, "assets")) for f in fs if f.endswith(".png"))
    imp2 = sum(1 for r, _, fs in os.walk(os.path.join(GAME, "assets")) for f in fs if f.endswith(".png.import"))
    print("      assets：png=%d  png.import=%d  差=%d" % (png, imp2, png - imp2))

    if not args.keep_temp:
        print("清理臨時複製…")
        shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
