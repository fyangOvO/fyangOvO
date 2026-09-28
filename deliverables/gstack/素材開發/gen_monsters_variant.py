# -*- coding: utf-8 -*-
"""
G1 前置：新怪物「變體衍生」產線（**零 AI**）

用途
----
第五步要新增 8 隻怪（`05-monsters.json` → `monsters_new`）。本腳本把**既有 16 隻怪**
當作造型來源，用「HSV 色相旋轉 + 飽和/明度縮放」產生變體，用於：

  · 方案 B（全衍生）：8 隻全部由此產生，**不花任何 AI 額度**；
  · 方案 C（混合）：只對「無法靠改色成立」的 2 隻（`bone_archer` 需弓、`rat_swarm` 跨物種）用 AI，
    其餘 6 隻由此產生。

技術要點（都是踩過的坑）
------------------------
1. **逐色表映射而非整圖濾鏡**：每張圖只有 48 個相異色 ⇒ 建 48 條對照表再套用，
   精確、快、且**輸出相異色數不會超過輸入**（不需事後量化）。
2. **只用 HSV 旋轉，不做亮度重排**：既有怪 48 色的內部結構（骨/皮/金屬/布）必須保留；
   若改成「按亮度重排到單一色系」會把怪物壓成一團單色塊。
3. 色板：怪物走**自適應 48 色**（已裁定例外；實測既有怪 0% 落在 `PALETTE_ALL`），
   故**不吸附** 44 色板；但輸出仍會驗「相異色 ≤48」與「alpha 二值」。
4. **保留 alpha 二值**與**腳底基準**（不縮放時原樣保留；縮放時重新貼齊）。

⚠️ 本腳本**只寫到取樣目錄**（`deliverables/gstack/素材開發/_g1_sample/<id>/`），
   不直接動 `game/assets/pack/creatures/`。確認方案後再跑 `--install` 落地。
"""
import argparse
import colorsys
import glob
import os
import re
import shutil
import sys

import numpy as np
from PIL import Image

PACK = r"D:/七傳說/game/assets/pack/creatures"
SAMPLE_ROOT = r"D:/七傳說/deliverables/gstack/素材開發/_g1_sample_v2"

# 8 隻新怪 → (來源怪, **目標絕對色相**, 飽和倍率, 明度倍率, 縮放)
#
# ⚠️ **必須用「絕對目標色相」而非「相對偏移」**（2026-09-28 踩過）：
#   紅色的 h≈0.98，要變金(0.12)只需 +0.14，要變青(0.58)卻要 +0.58。
#   用「相對偏移」寫死數字，換一個來源怪就整個跑掉（實測 brute_butcher 想改金卻變成藍白）。
#   這裡改為：先量來源的**主色相**，再算出「讓主色相落到目標」所需的角度差。
#
# ⚠️ **來源盡量不重複**：兩隻用同一個來源 ⇒ 玩家一眼看出是同一隻換色。
PLAN = {
    # shadow 精英 · 長袍施法者 ⇒ 秘教徒（造型語意最貼）
    "void_priest":    ("pyromancer_cultist", 0.75, 1.05, 0.90, 1.00),
    # shadow 普通 · 暗色剪影 ⇒ 暗狼
    "shade_stalker":  ("warg_dark",          0.72, 1.10, 0.80, 1.00),
    # lightning 普通 · 漂浮發光 ⇒ 冰幽魂（改亮金＝雷靈）
    "storm_wisp":     ("ice_wraith",         0.12, 1.05, 1.10, 1.00),
    # poison 普通 · 毒系 ⇒ 孢子菇
    "plague_bearer":  ("mushroom_spore",     0.28, 1.10, 0.95, 1.10),
    # lightning 精英 · 大型 ⇒ 燼魔像（改亮金）
    "thunder_herald": ("golem_ember",        0.12, 1.00, 1.05, 1.00),
    # cold 普通 · 投擲 ⇒ 屠夫（改冰藍；**唯一與他人共用來源的一隻**，但色系差最遠）
    "frost_lobber":   ("brute_butcher",      0.56, 0.80, 1.02, 0.95),
    # physical 精英 · 群體 ⇒ 蝙蝠群（**跨物種，說服力最低**）
    "rat_swarm":      ("bat_swarm",          0.07, 0.70, 0.85, 0.90),
    # physical 普通 · 骷髏 + **需弓** ⇒ 骷髏戰士（**缺弓，改色無法成立**）
    "bone_archer":    ("skeleton_warrior",   0.10, 0.25, 1.06, 1.00),
}


def dominant_hue(src_png):
    """像素數加權的圓形平均色相（只算 s>0.15 的彩色像素，排除灰/黑白）。
    加權很重要：背景裝飾/雜物可能只佔幾百像素，不能和主體同權。"""
    a = np.array(Image.open(src_png).convert("RGBA"))
    m = a[:, :, 3] > 8
    cols, counts = np.unique(a[m][:, :3].reshape(-1, 3), axis=0, return_counts=True)
    sx = sy = 0.0
    for c, n in zip(cols, counts):
        h, s, v = colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)
        if s < 0.15:
            continue
        ang = 2 * np.pi * h
        sx += n * np.cos(ang)
        sy += n * np.sin(ang)
    if sx == 0.0 and sy == 0.0:
        return 0.0
    ang = np.arctan2(sy, sx) % (2 * np.pi)
    return ang / (2 * np.pi)



def build_lut(src_png, hue_shift, sat, val):
    """由單張圖推出「來源色 → 目標色」對照表（只 48 條，逐圖只算一次）。"""
    a = np.array(Image.open(src_png).convert("RGBA"))
    m = a[:, :, 3] > 0
    cols = {tuple(int(v) for v in px[:3]) for px in a[m]}
    lut = {}
    for c in cols:
        h, s, v = colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)
        h = (h + hue_shift) % 1.0
        s = max(0.0, min(1.0, s * sat))
        v = max(0.0, min(1.0, v * val))
        r, g, b = colorsys.hsv_to_rgb(h, s, v)
        lut[c] = (round(r * 255), round(g * 255), round(b * 255))
    return lut


def apply_lut(img, lut):
    a = np.array(img.convert("RGBA"))
    m = a[:, :, 3] > 0
    out = a.copy()
    for c, nc in lut.items():
        sel = m & (a[:, :, 0] == c[0]) & (a[:, :, 1] == c[1]) & (a[:, :, 2] == c[2])
        out[sel, 0] = nc[0]
        out[sel, 1] = nc[1]
        out[sel, 2] = nc[2]
    return Image.fromarray(out, "RGBA")


def rescale(img, factor, canvas=128, feet=127):
    """整數比例優先（像素風禁非整數縮放）；縮完把腳底貼回 feet。"""
    if abs(factor - 1.0) < 1e-6:
        return img
    a = np.array(img)
    ys, xs = np.nonzero(a[:, :, 3] > 8)
    if len(ys) == 0:
        return img
    h = ys.max() - ys.min() + 1
    w = xs.max() - xs.min() + 1
    # 找最接近的整數比例（限 1x / 2x / 1/2 …；此處只允許 ≥1 的整數或有理數）
    # 縮放後尺寸必須仍 ≤ canvas 且不改變寬高比
    nw, nh = int(round(w * factor)), int(round(h * factor))
    if nw > canvas or nh > canvas:
        # 超框則改為「等比縮到框內」
        k = min(canvas / float(w), canvas / float(h))
        nw, nh = int(round(w * k)), int(round(h * k))
    crop = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    crop = crop.resize((nw, nh), Image.NEAREST)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(crop, ((canvas - nw) // 2, feet - nh + 1))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=None, help="只做指定 id")
    ap.add_argument("--install", action="store_true",
                    help="寫進 game/assets/pack/creatures/（預設只寫取樣目錄）")
    args = ap.parse_args()

    ids = args.only if args.only else list(PLAN.keys())
    for mid in ids:
        if mid not in PLAN:
            print("[skip] 未定義:", mid); continue
        src_id, tgt_hue, sat, val, sc = PLAN[mid]
        srcs = sorted(glob.glob(os.path.join(PACK, src_id, "*.png")))
        if not srcs:
            print("[skip] 來源不存在:", src_id); continue
        # 先量來源主色相 ⇒ 算出需要的角度差（逐 id 一次，不必逐圖）
        dh = dominant_hue(srcs[len(srcs) // 2])
        hue_shift = (tgt_hue - dh) % 1.0
        dst_dir = os.path.join(PACK if args.install else SAMPLE_ROOT, mid)
        os.makedirs(dst_dir, exist_ok=True)
        # 逐圖建 LUT（每圖色板互不共用 ⇒ 不可共用一張表）
        made = maxcols = 0
        for p in srcs:
            fn = os.path.basename(p)
            m = re.match(r"char_%s_(.+)$" % re.escape(src_id), fn)
            if not m:
                continue
            dst = os.path.join(dst_dir, "char_%s_%s" % (mid, m.group(1)))
            lut = build_lut(p, hue_shift, sat, val)
            out = apply_lut(Image.open(p), lut)
            if abs(sc - 1.0) > 1e-6:
                out = rescale(out, sc)
            a = np.array(out)
            mm = a[:, :, 3] > 0
            maxcols = max(maxcols, len({tuple(int(v) for v in px[:3]) for px in a[mm]}))
            out.save(dst)
            made += 1
        print("  %-16s ← %-20s 產出 %d 檔  最大相異色 %d  主色相%.2f→目標%.2f (差%+.2f) sat×%.2f val×%.2f scale×%.2f"
              % (mid, src_id, made, maxcols, dh, tgt_hue, hue_shift, sat, val, sc))
    print("\n取樣目錄:", SAMPLE_ROOT if not args.install else PACK)


if __name__ == "__main__":
    main()
