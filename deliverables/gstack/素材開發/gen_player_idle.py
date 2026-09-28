# -*- coding: utf-8 -*-
"""
A1 批次：玩家 idle 8 方向（一般方案，4 幀）。

依 策划案 01-技能体系.md 附錄A §A.3：
  ① 中立 → ② 吸氣 → ③ 中立 → ④ 吐氣；「上下 1–2px 起伏即可，不要左右晃」

兩個關鍵工程決策（與策劃案的差異，已記於清單）：
  1. 切分線用「胸線以上」而非腰線。
     原因：這套素材的劍垂到地面，若按腰線切分，劍身會被切成兩段 ⇒ 斷劍或拉長。
     切在胸線以上只動「頭 + 肩」，劍與下半身完全不動。
  2. 幅度預設 2px（可用 --amp 調）。
     原因：遊戲內 DNF_GAME_SCALE=0.25 ⇒ 4:1 降採樣，1px 起伏只有 0.25 螢幕像素。
     策劃案的「1–2px」若指 192 畫布，實機等於沒動 ⇒ 這裡取 2px 並標明。

素材來源（**不重畫**）：
  · s 方向：保留既有 char_<class>_idle_s_01.png 為第 1 幀，02–04 由它衍生
  · 其餘 7 方向：以 char_<class>_walk_<dir>_02.png（並腳幀）為基準
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

PACK = r"D:/七傳說/game/assets/pack/creatures"
CLASSES = ["warrior", "archer", "mage"]
DIRS8 = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
CHEST_FRAC = 0.33          # 切分線位置（自角色頂端往下 33% 高）


def shift_above(img: Image.Image, split_y: int, dy: int) -> Image.Image:
    """把 split_y 以上的區域垂直位移 dy px；split_y 以下不動。
    dy<0（上移）：用 split_y 那一列填補空隙（延伸頸部）
    dy>0（下移）：上方區域下移，與下方重疊，無縫
    """
    if dy == 0:
        return img.copy()
    a = np.array(img)
    out = a.copy()
    if dy < 0:
        d = -dy
        out[0:split_y - d] = a[d:split_y]
        out[split_y - d:split_y] = a[split_y]        # 以頸線列延伸填補
    else:
        out[dy:split_y] = a[0:split_y - dy]
        out[0:dy] = 0                                 # 頂端讓出透明
    return Image.fromarray(out, "RGBA")


def bbox_alpha(img: Image.Image):
    ys, xs = np.nonzero(np.array(img)[:, :, 3] > 8)
    return ys.min(), ys.max(), xs.min(), xs.max()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--amp", type=int, default=2, help="呼吸幅度 px（192 畫布）")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    A = args.amp
    seq = [0, -A, 0, A]          # 中立 / 吸氣(上) / 中立 / 吐氣(下)
    total_new = 0
    print(f"呼吸幅度 = ±{A}px（192 畫布）｜ 切分線 = 角色頂端往下 {CHEST_FRAC:.0%}")
    print(f"幀序 dy = {seq}\n")

    for cls in CLASSES:
        d_out = os.path.join(PACK, cls)
        if not os.path.isdir(d_out):
            print(f"  [skip] {d_out} 不存在")
            continue
        for dr in DIRS8:
            if dr == "s":
                base_p = os.path.join(d_out, f"char_{cls}_idle_s_01.png")
                first = 2                    # 既有 01 保留
            else:
                base_p = os.path.join(d_out, f"char_{cls}_walk_{dr}_02.png")
                first = 1
            if not os.path.exists(base_p):
                print(f"  [MISS] 基準幀不存在：{base_p}")
                continue
            base = Image.open(base_p).convert("RGBA")
            top, bottom, x0, x1 = bbox_alpha(base)
            h = bottom - top + 1
            split_y = top + int(round(h * CHEST_FRAC))

            made = []
            for idx in range(1, 5):
                if idx < first:
                    continue
                f = os.path.join(d_out, f"char_{cls}_idle_{dr}_{idx:02d}.png")
                if os.path.exists(f):
                    print(f"  [skip 既有] {os.path.basename(f)}")
                    continue
                if args.dry_run:
                    made.append(f"DRY {os.path.basename(f)}")
                    continue
                frame = shift_above(base, split_y, seq[idx - 1])
                frame.save(f)
                made.append(os.path.basename(f))
                total_new += 1
            print(f"  {cls:>8} idle_{dr:<2}  基準={os.path.basename(base_p):<38} "
                  f"bbox=({x0},{top},{x1},{bottom}) 切分y={split_y}  產出 {len(made)}")

    print(f"\n合計新增 {total_new} 個 PNG")
    return 0


if __name__ == "__main__":
    sys.exit(main())
