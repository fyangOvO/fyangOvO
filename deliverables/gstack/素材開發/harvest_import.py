# -*- coding: utf-8 -*-
"""
從已匯入的複製區「收成」——`import_assets.py` 的備援路徑。

用途：Godot 匯入有時**把活幹完但程序不退出**（實測 900s 逾時，但產物齊全）。
此時不必重跑，直接收成即可。複製區位置：%TEMP%/qcs_import
"""
import glob
import os
import shutil
import sys
import tempfile

GAME = r"D:/七傳說/game"
TMP = os.path.join(tempfile.gettempdir(), "qcs_import")


def main():
    if not os.path.isdir(TMP):
        print("找不到複製區：%s（請先跑 import_assets.py）" % TMP)
        return 1

    imp = 0
    for png in glob.glob(os.path.join(TMP, "assets", "**", "*.png"), recursive=True):
        rel = os.path.relpath(png, TMP)
        if not os.path.exists(os.path.join(GAME, rel)):
            continue
        dst_imp = os.path.join(GAME, rel + ".import")
        src_imp = os.path.join(TMP, rel + ".import")
        if not os.path.exists(dst_imp) and os.path.exists(src_imp):
            os.makedirs(os.path.dirname(dst_imp), exist_ok=True)
            shutil.copy2(src_imp, dst_imp)
            imp += 1
    print("收成 .import：%d" % imp)

    si = os.path.join(TMP, ".godot", "imported")
    di = os.path.join(GAME, ".godot", "imported")
    os.makedirs(di, exist_ok=True)
    todo = [f for f in os.listdir(si) if f not in set(os.listdir(di))]
    got = 0
    for f in todo:
        try:
            shutil.copy2(os.path.join(si, f), os.path.join(di, f))
            got += 1
        except Exception as e:
            print("  skip %s (%s)" % (f, type(e).__name__))
    print("收成 .godot/imported：%d / %d" % (got, len(todo)))

    for f in ["global_script_class_cache.cfg", "uid_cache.bin"]:
        s, d = os.path.join(TMP, ".godot", f), os.path.join(GAME, ".godot", f)
        if os.path.exists(s):
            try:
                shutil.copy2(s, d)
                print("  覆蓋 .godot/%s" % f)
            except Exception as e:
                print("  無法覆蓋 .godot/%s (%s)" % (f, type(e).__name__))

    bad = []
    for root, _, files in os.walk(os.path.join(GAME, "assets")):
        for f in files:
            p = os.path.join(root, f)
            if f.endswith(".import") and os.path.getsize(p) < 50:
                bad.append(os.path.relpath(p, GAME))
    png = sum(1 for r, _, fs in os.walk(os.path.join(GAME, "assets")) for f in fs if f.endswith(".png"))
    imp2 = sum(1 for r, _, fs in os.walk(os.path.join(GAME, "assets")) for f in fs if f.endswith(".png.import"))
    print("驗證：0 byte / 過小 .import = %d %s" % (len(bad), bad if bad else ""))
    print("      assets：png=%d  png.import=%d  差=%d" % (png, imp2, png - imp2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
