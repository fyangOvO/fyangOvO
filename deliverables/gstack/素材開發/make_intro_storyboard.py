## -*- coding: utf-8 -*-
## 片頭分鏡拼圖產線（2026-10-08）
##
## 用途：把 `--write-movie` 錄下的確定性幀序列（30fps），按分鏡時刻抽幀拼成
##       3×3 分鏡圖，用來**目視驗收**「某一段真的演出來了」。
##
## 為什麼不直接看即時抓圖（`capture_intro`）：即時抓圖走真實時間，機器一卡
## 就會抓到與分鏡對不上的畫面（實測 Intel UHD 上偏差可達 0.5s+）。Movie Maker
## 是固定步長渲染，第 N 幀就**必然**對應 N/30 秒 —— 抽幀位置可精確指定。
##
## 用法：
##   python make_intro_storyboard.py                     # 產生全部三張分鏡圖
##   python make_intro_storyboard.py --sheet A           # 只產生 A 表
import argparse
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", "..", ".."))            # D:/七傳說
FRAMES = os.path.join(PROJ, "deliverables", "gstack", "intro_movie", "frames")
OUT_DIR = os.path.join(PROJ, "deliverables", "gstack", "intro_movie")

FPS = 30
CELL = (320, 180)          # 每格縮圖尺寸（原幀 640×360 的 0.5×）
COLS = 3
ROWS = 3

## 分鏡表：每張 9 格，元素 = (秒, 標籤)
SHEETS = {
    "A": [
        (0.6, "①背景淡入"),
        (2.2, "②標題落下"),
        (3.6, "③副標題1"),
        (5.4, "④勇者入場中"),
        (6.4, "⑤勇者列隊"),
        (7.6, "⑥魔王顯形"),
        (9.3, "⑦副標題2"),
        (10.7, "⑧勇者前壓"),
        (11.7, "⑨劍士斬擊"),
    ],
    "B": [
        (13.2, "⑩遊俠連射"),
        (15.8, "⑪法師火球"),
        (17.4, "⑫魔王反擊"),
        (19.8, "⑬三勇者合擊"),
        (20.9, "⑭合擊餘韻"),
        (22.9, "⑮魔王覺醒"),
        (25.0, "⑯劍士覺醒"),
        (26.4, "⑰遊俠覺醒"),
        (27.8, "⑱法師覺醒"),
    ],
    "C": [
        (28.8, "⑲覺醒收束"),
        (29.3, "⑳定版"),
        (29.8, "㉑完整畫面"),
    ],
}


def frame_path(sec: float) -> str:
    idx = int(round(sec * FPS))
    return os.path.join(FRAMES, "intro%08d.png" % idx)


def build_sheet(key: str, cells) -> str:
    rows = (len(cells) + COLS - 1) // COLS
    sheet = Image.new("RGB", (CELL[0] * COLS, CELL[1] * rows), (12, 12, 16))
    missing = []
    for i, (sec, label) in enumerate(cells):
        p = frame_path(sec)
        if not os.path.exists(p):
            missing.append("%s(%.1fs)" % (label, sec))
            continue
        im = Image.open(p).convert("RGB").resize(CELL, Image.LANCZOS)
        x = (i % COLS) * CELL[0]
        y = (i // COLS) * CELL[1]
        sheet.paste(im, (x, y))
    out = os.path.join(OUT_DIR, "分镜_%s.png" % key)
    sheet.save(out, "PNG", optimize=True)
    print("  ✅ %s  %s  %d 格%s" % (key, os.path.basename(out), len(cells),
                                  ("  缺幀：" + ", ".join(missing)) if missing else ""))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default="")
    args = ap.parse_args()

    if not os.path.isdir(FRAMES):
        print("找不到幀目錄：%s（先跑 intro_movie 錄影）" % FRAMES)
        return 2
    keys = [args.sheet] if args.sheet else list(SHEETS.keys())
    print("片頭分鏡拼圖 → %s" % OUT_DIR)
    for k in keys:
        if k not in SHEETS:
            print("未知分鏡表：%s" % k)
            return 2
        build_sheet(k, SHEETS[k])
    return 0


if __name__ == "__main__":
    sys.exit(main())
