# -*- coding: utf-8 -*-
"""
A3 + A4 批次：玩家 hurt / death 8 方向（一般方案）

依 策划案 01-技能体系.md 附錄A §A.3：
  hurt  ① 後仰（位移、頭後傾）→ ② 回復中；**位移方向必須與受擊方向一致**
  death ① 後仰 → ② 跪倒（身高減半）→ ③ 側倒 → ④ 靜止躺地；**躺地方向要對**

素材來源（不重畫）：既有 `char_<class>_walk_<dir>_02.png`（並腳中立幀）
  · s 方向 hurt 已有既有 2 幀、death 已有既有 4 幀 ⇒ 依 §A.3「保留現有」**不覆蓋**

三種變換：
  · lean(dy)     胸線以上垂直位移（後仰 / 頭後傾）
  · shift(dx)    整張精靈水平位移（受擊位移；腳底 y 不變，故不做垂直位移）
  · squash(f)    以腳底為錨點垂直壓縮（跪倒 / 倒地的身高衰減）
  · rot90        躺地幀用**精確 90° 旋轉**（np.rot90，無插值）⇒ 不會糊像素

⚠️ 品質定位：這是**衍生 placeholder**，不是手繪死亡演出。它能修掉「所有方向都播正面死亡」
   的硬傷，但演出細節（膝蓋彎曲、手撐地）仍建議後期手繪。
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
BASELINE_Y = 191
VEC = {"n": (0, -1), "ne": (1, -1), "e": (1, 0), "se": (1, 1),
       "s": (0, 1), "sw": (-1, 1), "w": (-1, 0), "nw": (-1, -1)}


def bbox(img):
    ys, xs = np.nonzero(np.array(img)[:, :, 3] > 8)
    return ys.min(), ys.max()


def lean_above(img, dy):
    if dy == 0:
        return img.copy()
    top, _ = bbox(img)
    h = bbox(img)[1] - top + 1
    split = top + int(round(h * CHEST_FRAC))
    a = np.array(img)
    out = a.copy()
    if dy < 0:
        d = -dy
        out[0:split - d] = a[d:split]
        out[split - d:split] = a[split]
    else:
        out[dy:split] = a[0:split - dy]
        out[0:dy] = 0
    return Image.fromarray(out, "RGBA")


def shift_x(img, dx):
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


def squash(img, f):
    """以腳底為錨點垂直壓縮；NEAREST 保持硬邊。"""
    ys, _ = np.nonzero(np.array(img)[:, :, 3] > 8)
    feet = ys.max()
    nh = max(1, int(round((bbox(img)[1] - ys.min() + 1) * f)))
    a = np.array(img.crop((0, ys.min(), 192, ys.max() + 1)))
    small = Image.fromarray(a, "RGBA").resize((192, nh), Image.NEAREST)
    canvas = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    canvas.alpha_composite(small, (0, max(0, BASELINE_Y - nh + 1)))
    return canvas


def rot90_fall(img, vx):
    """躺地幀：朝 vx 方向倒下 ⇒ 精確 90° 旋轉（無插值）。"""
    a = np.array(img)
    ys, xs = np.nonzero(a[:, :, 3] > 8)
    body = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    k = 3 if vx > 0 else 1          # vx>0 往右倒（頭在右）
    r = np.rot90(body, k)
    out = Image.fromarray(np.ascontiguousarray(r), "RGBA")
    canvas = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    w, h = out.size
    if w > 192:                      # 橫躺可能超出畫布寬 ⇒ 等比縮到畫布內（NEAREST）
        s = 192.0 / w
        out = out.resize((192, max(1, int(h * s))), Image.NEAREST)
        w, h = out.size
    x = int(round(96 + (-vx) * 6 - w / 2))
    canvas.alpha_composite(out, (max(0, min(192 - w, x)), BASELINE_Y - h + 1))
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hurt-shift", type=int, default=2, help="受擊水平位移 px")
    ap.add_argument("--hurt-lean", type=int, default=2, help="受擊頭後傾 px")
    args = ap.parse_args()

    hs, hl = args.hurt_shift, args.hurt_lean
    total = skipped = 0
    print(f"受擊位移 = {hs}px  ｜ 頭後傾 = {hl}px")
    print("hurt 幀序: ① 後仰 → ② 回復中   |   death 幀序: ① 後仰 → ② 跪倒 → ③ 側倒 → ④ 躺地\n")

    for cls in CLASSES:
        d = os.path.join(PACK, cls)
        for dr in DIRS8:
            vx, vy = VEC[dr]
            base_p = os.path.join(d, f"char_{cls}_walk_{dr}_02.png")
            if not os.path.exists(base_p):
                print("  [MISS]", base_p)
                continue
            base = Image.open(base_p).convert("RGBA")

            plans = []
            # ---- hurt：s 既有，跳過 ----
            if dr != "s":
                plans += [
                    (f"char_{cls}_hurt_{dr}_01.png",
                     shift_x(lean_above(base, -hl), int(round(-vx * hs)))),
                    (f"char_{cls}_hurt_{dr}_02.png",
                     shift_x(lean_above(base, -max(1, hl // 2)), int(round(-vx * hs / 2)))),
                ]
            # ---- death：s 既有，跳過 ----
            if dr != "s":
                plans += [
                    (f"char_{cls}_death_{dr}_01.png",
                     shift_x(lean_above(base, -3), int(round(-vx * 1)))),          # ① 後仰
                    (f"char_{cls}_death_{dr}_02.png",
                     shift_x(lean_above(squash(base, 0.58), -1), int(round(-vx * 2)))),  # ② 跪倒
                    (f"char_{cls}_death_{dr}_03.png",
                     shift_x(squash(base, 0.38), int(round(-vx * 4)))),             # ③ 側倒
                ]
                # ④ 躺地：有水平分量 → 90° 旋轉；純 n/s → 前縮壓扁（正面/背面趴倒）
                if vx != 0:
                    plans.append((f"char_{cls}_death_{dr}_04.png", rot90_fall(base, vx)))
                else:
                    plans.append((f"char_{cls}_death_{dr}_04.png", squash(base, 0.30)))

            made = 0
            for fn, im in plans:
                p = os.path.join(d, fn)
                if os.path.exists(p):
                    skipped += 1
                    continue
                im.save(p)
                made += 1
                total += 1
            print(f"  {cls:>8} {dr:<2}  新增 {made:>2} 幀（hurt {'skip(s 既有)' if dr=='s' else 2} / death {'skip(s 既有)' if dr=='s' else 4}）")
    print(f"\n合計新增 {total} 個 PNG（跳過既有 {skipped} 個）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
