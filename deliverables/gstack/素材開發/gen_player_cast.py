# -*- coding: utf-8 -*-
"""
A2 批次：玩家 cast 8 方向（一般方案，4 幀）。

依 策划案 01-技能体系.md 附錄A §A.3：
  ① 起手（武器/手抬至胸前）→ ② 蓄力（後傾）→ ③ **釋放（前傾、武器前送）** → ④ 收勢
  §A.3 明確指出：「③ 是關鍵 —— attack 是橫向劈砍，cast 是**向前推**」

素材來源（不重畫）：既有 `char_<class>_attack_<dir>_<NN>.png`
  為什麼用 attack 當基準：實測三職業的 attack 序列本質就是「蓄力 → 釋放」
    · 法師：聚能 → 舉杖 → **魔法彈前飛** → 收招（本身就是施法）
    · 弓手：持弓 → 拉弓 → **放箭帶箭矢** → 收弓（本身也是蓄力釋放）
    · 戰士：舉劍 → 前指 → **橫斬帶白色刀弧** → 收招 ← 只有這職業是「劈砍」

逐職業差異（關鍵）：
  · 弓手 / 法師：③ 直接用 attack_03（那幀就是釋放，帶投射物表現）
  · 戰士：③ 改用 attack_02（持劍**前指**，無刀弧），避開「cast 播劈砍」的老問題

三種變換：
  · lean：把「胸線以上」垂直位移（蓄力上升 / 釋放前傾下壓）
  · push：整張精靈依朝向水平前移（前送），腳底 y 不變
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

PACK = r"D:/七傳說/game/assets/pack/creatures"
CLASSES = ["warrior", "archer", "mage"]
DIRS8 = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
CHEST_FRAC = 0.33

# 朝向向量（螢幕座標：+x 右、+y 下）
VEC = {"n": (0, -1), "ne": (1, -1), "e": (1, 0), "se": (1, 1),
       "s": (0, 1), "sw": (-1, 1), "w": (-1, 0), "nw": (-1, -1)}

# ③ 釋放幀的來源：戰士避開帶刀弧的 03，改用前指的 02
RELEASE_SRC = {"warrior": 2, "archer": 3, "mage": 3}

# 每幀 (來源幀, lean倍率, push倍率) —— 倍率乘上 --lean / --push
FRAME_PLAN = [
    (1, 0, 0),        # ① 起手
    (2, -1, 0),       # ② 蓄力：胸線以上上升（後傾蓄勢）
    (None, 1, 1),     # ③ 釋放：前傾下壓 + 前送
    (4, 0, 0),        # ④ 收勢
]


def shift_above(img, split_y, dy):
    if dy == 0:
        return img.copy()
    a = np.array(img)
    out = a.copy()
    if dy < 0:
        d = -dy
        out[0:split_y - d] = a[d:split_y]
        out[split_y - d:split_y] = a[split_y]
    else:
        out[dy:split_y] = a[0:split_y - dy]
        out[0:dy] = 0
    return Image.fromarray(out, "RGBA")


def push_x(img, dx):
    if dx == 0:
        return img.copy()
    a = np.array(img)
    out = np.zeros_like(a)
    w = a.shape[1]
    if dx > 0:
        out[:, dx:w] = a[:, 0:w - dx]
    else:
        out[:, 0:w + dx] = a[:, -dx:w]
    return Image.fromarray(out, "RGBA")


def bbox_alpha(img):
    ys, xs = np.nonzero(np.array(img)[:, :, 3] > 8)
    return ys.min(), ys.max()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--push", type=int, default=3, help="釋放幀前送 px")
    ap.add_argument("--lean", type=int, default=2, help="蓄力/釋放的上身位移 px")
    ap.add_argument("--force", action="store_true",
                    help="覆寫既有檔（⚠️ WorkBuddy 會鎖住本 session 產生過的檔案，通常會 PermissionError）")
    args = ap.parse_args()

    total = skipped = 0
    print(f"釋放幀前送 = {args.push}px ｜ 上身位移 = ±{args.lean}px")
    print(f"③ 釋放來源：warrior→attack_02（去刀弧）  archer/mage→attack_03（帶投射物表現）\n")

    for cls in CLASSES:
        d_out = os.path.join(PACK, cls)
        for dr in DIRS8:
            vx, vy = VEC[dr]
            made = 0
            for idx, (src, lean_mul, push_mul) in enumerate(FRAME_PLAN, start=1):
                s = RELEASE_SRC[cls] if src is None else src
                p = os.path.join(d_out, f"char_{cls}_attack_{dr}_{s:02d}.png")
                if not os.path.exists(p):
                    print(f"  [MISS] {p}")
                    continue
                im = Image.open(p).convert("RGBA")
                top, bottom = bbox_alpha(im)
                h = bottom - top + 1
                split_y = top + int(round(h * CHEST_FRAC))

                out = shift_above(im, split_y, lean_mul * args.lean)
                out = push_x(out, int(round(vx * push_mul * args.push)))

                f = os.path.join(d_out, f"char_{cls}_cast_{dr}_{idx:02d}.png")
                if os.path.exists(f) and not args.force:
                    skipped += 1
                    continue
                out.save(f)
                made += 1
                total += 1
            print(f"  {cls:>8} cast_{dr:<2} 新增 {made} 幀  (源 attack_{dr}_0{FRAME_PLAN[0][0]}/{FRAME_PLAN[1][0]}/"
                  f"{RELEASE_SRC[cls]}/{FRAME_PLAN[3][0]})")
    print(f"\n合計新增 {total} 個 PNG（跳過既有 {skipped} 個）")


if __name__ == "__main__":
    sys.exit(main())
