## -*- coding: utf-8 -*-
## 覺醒立繪產線（2026-10-08）
##
## 用途：把 image_gen 產出的 1024×1536 厚涂原圖，統一下採樣為 **512×768**（2:3 豎版）
##       並落盤到 `game/assets/ui/awaken/awaken_<id>.png`，供片頭 `intro_screen.gd` 消費。
##
## 為何 512×768：與既有 `assets/ui/boss/awaken_ember_lord.png` 同尺寸同規格，
##       2:3 是 DNF 覺醒立繪的標準豎版比例；1024×1536 → 512×768 恰為 **0.5× 整數縮放**。
##
## 用法：
##   python gen_awaken_heroes.py                 # 依 RAW 映射處理全部四張
##   python gen_awaken_heroes.py --only warrior  # 只處理一張
##   python gen_awaken_heroes.py --check         # 只校驗落盤結果（不寫檔）
import argparse
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", "..", ".."))          # D:/七傳說
RAW_DIR = os.path.join(HERE, "_awaken_src")
DST_DIR = os.path.join(PROJ, "game", "assets", "ui", "awaken")

TARGET = (512, 768)

## 原圖 → 角色 id（原圖由 image_gen 生成，時間戳即身分）
RAW_MAP = {
    "warrior":    "raw_warrior_1024x1536.png",
    "archer":     "raw_archer_1024x1536.png",
    "mage":       "raw_mage_1024x1536.png",
    "ember_lord": "raw_ember_lord_1024x1536.png",
}

## 權威色板（角色主題色，供未來著色校驗用；本產線只做縮放不著色）
THEME_COLOR = {
    "warrior":    (0xD9, 0xA4, 0x41),   # 金
    "archer":     (0x8F, 0xBF, 0x5F),   # 綠
    "mage":       (0x7F, 0xA8, 0xE8),   # 藍
    "ember_lord": (0xE0, 0x5A, 0x1E),   # 熔岩橙
}


def process_one(cid: str) -> str:
    src = os.path.join(RAW_DIR, RAW_MAP[cid])
    if not os.path.exists(src):
        raise FileNotFoundError("缺原圖：%s" % src)
    im = Image.open(src).convert("RGB")
    if im.size != (1024, 1536):
        print("  ⚠️ %s 原圖尺寸 %s，非預期 1024×1536" % (cid, im.size))
    out = im.resize(TARGET, Image.LANCZOS)
    os.makedirs(DST_DIR, exist_ok=True)
    dst = os.path.join(DST_DIR, "awaken_%s.png" % cid)
    out.save(dst, "PNG", optimize=True)
    print("  ✅ %-11s %s -> %s  (%.2f MB)" % (
        cid, im.size, out.size, os.path.getsize(dst) / 1048576.0))
    return dst


def check() -> int:
    bad = 0
    for cid in RAW_MAP:
        dst = os.path.join(DST_DIR, "awaken_%s.png" % cid)
        if not os.path.exists(dst):
            print("  [FAIL] %s 未落盤" % cid)
            bad += 1
            continue
        im = Image.open(dst)
        ok = im.size == TARGET and im.mode == "RGB"
        print("  [%s] %-11s %s %s" % ("OK" if ok else "FAIL", cid, im.size, im.mode))
        if not ok:
            bad += 1
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    if args.check:
        bad = check()
        print("===== 校驗：%d 項失敗 =====" % bad)
        return 1 if bad else 0

    ids = [args.only] if args.only else list(RAW_MAP.keys())
    for cid in ids:
        if cid not in RAW_MAP:
            print("未知角色 id：%s" % cid)
            return 2
    print("覺醒立繪產線 → %s" % DST_DIR)
    for cid in ids:
        process_one(cid)
    print("===== 完成 %d 張 =====" % len(ids))
    return 0


if __name__ == "__main__":
    sys.exit(main())
