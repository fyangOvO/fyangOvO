# -*- coding: utf-8 -*-
"""符文圖標 v2 · 高精細像素畫（48×48，嚴格 44 色，alpha 二值）

沿用 `gen_icons.py` 的「索引畫布 → 自動描邊 → 色系映射」合規機制
（索引 0=透明 1=描邊 2=暗 3=中 4=亮 5=輝光；最後才映射到 44 色板 ⇒ 天生合規），
把每個符文從原本的 1–2 階平塗，升級為：

  · 4–5 階明暗（暗 / 中 / 亮 / 輝光）帶立體感
  · 邊緣高光（左上受光）+ 底部陰影
  · 內核輝光（中心亮點）
  · 微裝飾（分叉、氣泡、餘燼、放射線、刻度）

尺寸由 32×32 提升到 **48×48 原生**：與圖鑑格子 `rune_codex_panel.CELL=48` 1:1，
同時修掉原本 32→48 的 **1.5× 非整數縮放**（違反「整數倍 + 最近鄰」像素鐵律）。

用法：
  python gen_rune_icons_v2.py --sample   # 只出樣張 preview（**不覆蓋**遊戲素材）
  python gen_rune_icons_v2.py            # 出全部 24 張並落盤 assets/ui/quest/
  python gen_rune_icons_v2.py --only fire,cold   # 只出指定幾張（迭代用）
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icons import (Idx, SERIES, NEUTRAL, scale_pts,         # noqa: E402
                       IDX_T, IDX_O, IDX_D, IDX_M, IDX_B, IDX_G)

GAME = r"D:/七傳說/game"
QUEST = os.path.join(GAME, "assets/ui/quest")
HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 48

# ---- 符文石底座用的 5 級中性石色（全部取自 44 色板的 NEUTRAL 段）----
IDX_S_DEEP, IDX_S_BODY, IDX_S_LIGHT, IDX_S_RIM, IDX_S_HI = 6, 7, 8, 9, 10
STONE_COLS = {
    IDX_S_DEEP:  (0x1E, 0x23, 0x2B),   # 1E232B 凹槽
    IDX_S_BODY:  (0x2A, 0x31, 0x3B),   # 2A313B 石面
    IDX_S_LIGHT: (0x3A, 0x42, 0x4F),   # 3A424F 斜面
    IDX_S_RIM:   (0x4E, 0x58, 0x66),   # 4E5866 倒角高光
    IDX_S_HI:    (0x6B, 0x76, 0x88),   # 6B7688 鉚釘
}
OUTLINE_RGB = (11, 13, 16)             # 0B0D10


# ============================ 繪圖輔助 ============================
def P(pts, n, pad=3):
    """0..1 正規化座標 → 像素（保留 pad 邊距給描邊）。"""
    return scale_pts(pts, n, pad)


def disc(c, cx, cy, r, v):
    c.ell(cx - r, cy - r, cx + r, cy + r, v)


def ring(c, cx, cy, r, v, w=1):
    steps = max(24, int(2 * math.pi * r * 2))
    for i in range(steps):
        a = 2 * math.pi * i / steps
        for k in range(w):
            c.px(cx + (r - k) * math.cos(a), cy + (r - k) * math.sin(a), v)


def arc(c, cx, cy, r, a0, a1, v, w=1):
    steps = max(8, int(abs(a1 - a0) / 360.0 * 2 * math.pi * r * 2))
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        for k in range(w):
            c.px(cx + (r - k) * math.cos(a), cy + (r - k) * math.sin(a), v)


def spark(c, x, y, v, arm=1):
    """十字星芒（微裝飾）。"""
    for k in range(-arm, arm + 1):
        c.px(x + k, y, v)
        c.px(x, y + k, v)


def oct_pts(x0, y0, x1, y1, cut):
    """切角矩形（八邊形）。"""
    return [(x0 + cut, y0), (x1 - cut, y0), (x1, y0 + cut), (x1, y1 - cut),
            (x1 - cut, y1), (x0 + cut, y1), (x0, y1 - cut), (x0, y0 + cut)]


# 底座幾何：三層同 cut（6）⇒ 四角留出可放鉚釘的石塊
CUT = 6


def _stone_shell(c, n, hollow_idx):
    """畫三層八邊形石殼；hollow_idx 給 IDX_T 則鏤空成框，給石色則成實心凹槽。"""
    o = oct_pts(1, 1, n - 2, n - 2, CUT)      # 外斜面
    m = oct_pts(3, 3, n - 4, n - 4, CUT)      # 石面
    i = oct_pts(7, 7, n - 8, n - 8, CUT)      # 凹槽 / 鏤空
    c.poly(o, IDX_S_LIGHT)
    c.poly(m, IDX_S_BODY)
    c.poly(i, hollow_idx)
    loop_o = [o[6], o[7], o[0], o[1], o[2], o[3], o[4], o[5], o[6]]
    c.line(loop_o, IDX_S_RIM, 1)                       # 全周先鋪受光色
    c.line([o[2], o[3], o[4], o[5], o[6]], IDX_S_DEEP, 1)   # 右/下背光
    loop_i = [i[6], i[7], i[0], i[1], i[2], i[3], i[4], i[5], i[6]]
    c.line(loop_i, IDX_S_RIM, 1)                       # 內緣受光唇邊
    c.line([i[2], i[3], i[4], i[5], i[6]], IDX_S_DEEP, 1)   # 內緣背光唇邊
    for (x, y) in [(8, 8), (n - 10, 8), (8, n - 10), (n - 10, n - 10)]:
        c.rect(x, y, x + 1, y + 1, IDX_S_HI)           # 四角鉚釘（2×2）


def draw_stone_slab(c, n):
    """實心符文石板：外斜面 → 石面 → 內凹槽（符文浮雕其上）。"""
    _stone_shell(c, n, IDX_S_DEEP)


def draw_stone_frame(c, n):
    """雕花石框：只留外圈石環（內部鏤空），符文浮於環中。"""
    _stone_shell(c, n, IDX_T)


def compose_v2(idx_arr, series):
    """索引 → RGBA。索引 2–5 走元素色系，6–10 走中性石色。"""
    pal = {IDX_T: None, IDX_O: OUTLINE_RGB}
    cols = SERIES[series] if isinstance(series, str) else series
    for i, k in enumerate([IDX_D, IDX_M, IDX_B, IDX_G]):
        pal[k] = hex2rgb(cols[i])
    pal.update(STONE_COLS)
    h, w = idx_arr.shape
    out = np.zeros((h, w, 4), np.uint8)
    for k, col in pal.items():
        if col is None:
            continue
        out[idx_arr == k] = (*col, 255)
    return Image.fromarray(out, "RGBA")


def hex2rgb(h):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# ============================ 24 符文基元 ============================
# form 形態
def r_projectile(c, n):
    for i, y in enumerate([0.32, 0.50, 0.68]):
        c.line(P([(0.04, y), (0.38, y)], n), IDX_D if i != 1 else IDX_M, 1)
    c.poly(P([(0.44, 0.12), (0.94, 0.50), (0.44, 0.88)], n), IDX_M)
    c.poly(P([(0.44, 0.12), (0.70, 0.30), (0.44, 0.48)], n), IDX_B)
    c.poly(P([(0.44, 0.88), (0.70, 0.70), (0.44, 0.52)], n), IDX_D)
    c.poly(P([(0.60, 0.38), (0.80, 0.50), (0.60, 0.62)], n), IDX_G)


def r_chain(c, n):
    c.line([(int(.24 * n), int(.34 * n)), (int(.38 * n), int(.48 * n)),
            (int(.30 * n), int(.62 * n)), (int(.50 * n), int(.74 * n))], IDX_B, 1)
    c.line([(int(.76 * n), int(.34 * n)), (int(.62 * n), int(.48 * n)),
            (int(.70 * n), int(.62 * n)), (int(.50 * n), int(.74 * n))], IDX_B, 1)
    for x, y in [(0.22, 0.28), (0.78, 0.28), (0.50, 0.80)]:
        cx, cy = int(x * n), int(y * n)
        disc(c, cx, cy, int(.14 * n), IDX_M)
        disc(c, cx, cy, int(.08 * n), IDX_B)
        c.px(cx, cy, IDX_G)


def r_split(c, n):
    c.poly(P([(0.50, 0.05), (0.63, 0.25), (0.37, 0.25)], n), IDX_M)
    c.poly(P([(0.50, 0.05), (0.56, 0.17), (0.44, 0.17)], n), IDX_B)
    c.rect(int(.47 * n), int(.23 * n), int(.53 * n), int(.40 * n), IDX_M)
    c.line([(int(.50 * n), int(.40 * n)), (int(.24 * n), int(.60 * n))], IDX_D, 1)
    c.line([(int(.50 * n), int(.40 * n)), (int(.76 * n), int(.60 * n))], IDX_D, 1)
    c.line([(int(.50 * n), int(.40 * n)), (int(.50 * n), int(.62 * n))], IDX_D, 1)
    for x in (0.24, 0.50, 0.76):
        c.poly(P([(x, 0.62), (x + 0.09, 0.80), (x - 0.09, 0.80)], n),
               IDX_B if x == 0.50 else IDX_M)
    c.px(int(.50 * n), int(.88 * n), IDX_G)


def r_pierce(c, n):
    c.poly(P([(0.50, 0.06), (0.90, 0.22), (0.86, 0.70), (0.50, 0.94),
              (0.14, 0.70), (0.10, 0.22)], n), IDX_M)
    c.poly(P([(0.50, 0.16), (0.80, 0.28), (0.77, 0.64), (0.50, 0.82),
              (0.23, 0.64), (0.20, 0.28)], n), IDX_D)
    c.poly(P([(0.40, 0.44), (0.60, 0.44), (0.60, 0.60), (0.40, 0.60)], n), IDX_T)
    c.rect(int(.06 * n), int(.47 * n), int(.40 * n), int(.55 * n), IDX_B)
    c.poly(P([(0.40, 0.38), (0.62, 0.51), (0.40, 0.64)], n), IDX_B)
    c.rect(int(.62 * n), int(.47 * n), int(.94 * n), int(.55 * n), IDX_M)
    c.px(int(.92 * n), int(.51 * n), IDX_G)


def r_ground(c, n):
    # 龜裂地面 + 上方持續傷害區域（半圓虛線）+ 上浮粒子
    c.rect(int(.04 * n), int(.72 * n), int(.96 * n), int(.90 * n), IDX_D)
    c.rect(int(.04 * n), int(.72 * n), int(.96 * n), int(.78 * n), IDX_M)
    c.rect(int(.04 * n), int(.74 * n), int(.96 * n), int(.76 * n), IDX_B)
    for x in (0.28, 0.50, 0.72):
        c.line([(int(x * n), int(.79 * n)), (int((x - 0.06) * n), int(.94 * n))], IDX_T, 1)
    for a in range(180, 361, 20):                    # 持續區域弧（虛線）
        r = math.radians(a)
        c.px(int(.5 * n + .32 * n * math.cos(r)), int(.62 * n + .32 * n * math.sin(r)), IDX_G)
    for x, y in [(0.36, 0.40), (0.50, 0.26), (0.64, 0.40)]:
        c.px(int(x * n), int(y * n), IDX_G)


def r_echo(c, n):
    for r, v, w in [(0.20, IDX_G, 2), (0.33, IDX_B, 2), (0.45, IDX_M, 2)]:
        arc(c, int(.5 * n), int(.5 * n), int(r * n), -72, 72, v, w)
        arc(c, int(.5 * n), int(.5 * n), int(r * n), 108, 252, v, w)
    c.px(int(.5 * n), int(.5 * n), IDX_G)


# element 元素
def r_fire(c, n):
    c.poly(P([(0.50, 0.04), (0.68, 0.22), (0.62, 0.36), (0.80, 0.44),
              (0.82, 0.66), (0.50, 0.94), (0.18, 0.66), (0.20, 0.44),
              (0.38, 0.36), (0.32, 0.22)], n), IDX_M)
    c.poly(P([(0.50, 0.34), (0.64, 0.52), (0.60, 0.74), (0.50, 0.86),
              (0.40, 0.74), (0.36, 0.52)], n), IDX_B)
    c.poly(P([(0.50, 0.54), (0.57, 0.66), (0.50, 0.80), (0.43, 0.66)], n), IDX_G)


def r_cold(c, n):
    # 六角雪花：主幹 + 側陰影 + 分叉枝 + 中心冰晶
    cx, cy = int(.5 * n), int(.5 * n)
    for k in range(6):
        a = math.radians(60 * k)
        dx, dy = int(.44 * n * math.cos(a)), int(.44 * n * math.sin(a))
        c.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], IDX_M, 1)
        ox, oy = int(math.cos(a + math.pi / 2)), int(math.sin(a + math.pi / 2))
        c.line([(cx - dx + ox, cy - dy + oy), (cx + dx + ox, cy + dy + oy)], IDX_D, 1)
        for s in (0.55, 0.82):
            bx, by = int(s * dx), int(s * dy)
            for da in (1.05, -1.05):
                c.line([(cx + bx, cy + by),
                        (cx + bx + int(.12 * n * math.cos(a + da)),
                         cy + by + int(.12 * n * math.sin(a + da)))], IDX_B, 1)
    c.poly(P([(0.50, 0.32), (0.66, 0.50), (0.50, 0.68), (0.34, 0.50)], n), IDX_B)
    c.poly(P([(0.50, 0.40), (0.58, 0.50), (0.50, 0.60), (0.42, 0.50)], n), IDX_G)


def r_lightning(c, n):
    c.poly(P([(0.62, 0.04), (0.26, 0.50), (0.46, 0.50), (0.36, 0.96),
              (0.76, 0.44), (0.54, 0.44)], n), IDX_M)
    c.poly(P([(0.60, 0.12), (0.36, 0.46), (0.48, 0.46), (0.42, 0.82),
              (0.68, 0.48), (0.56, 0.48)], n), IDX_B)
    c.line([(int(.42 * n), int(.56 * n)), (int(.24 * n), int(.74 * n))], IDX_B, 1)
    c.line([(int(.54 * n), int(.44 * n)), (int(.76 * n), int(.26 * n))], IDX_B, 1)
    c.px(int(.50 * n), int(.36 * n), IDX_G)


def r_poison(c, n):
    c.poly(P([(0.50, 0.04), (0.80, 0.46), (0.50, 0.92), (0.20, 0.46)], n), IDX_M)
    disc(c, int(.5 * n), int(.62 * n), int(.28 * n), IDX_M)
    disc(c, int(.5 * n), int(.62 * n), int(.20 * n), IDX_D)
    c.rect(int(.35 * n), int(.52 * n), int(.43 * n), int(.60 * n), IDX_T)
    c.rect(int(.57 * n), int(.52 * n), int(.65 * n), int(.60 * n), IDX_T)
    c.px(int(.50 * n), int(.67 * n), IDX_T)
    c.px(int(.30 * n), int(.30 * n), IDX_G)
    c.px(int(.70 * n), int(.24 * n), IDX_G)


def r_shadow(c, n):
    c.ell(int(.10 * n), int(.10 * n), int(.90 * n), int(.90 * n), IDX_M)
    c.ell(int(.30 * n), int(.04 * n), int(1.16 * n), int(.86 * n), IDX_T)
    c.ell(int(.42 * n), int(.34 * n), int(.54 * n), int(.46 * n), IDX_B)
    spark(c, int(.80 * n), int(.28 * n), IDX_G, 1)
    spark(c, int(.66 * n), int(.74 * n), IDX_G, 1)


# amp 增幅
def r_wider(c, n):
    cx, cy = int(.5 * n), int(.5 * n)
    ring(c, cx, cy, int(.22 * n), IDX_D, 1)
    disc(c, cx, cy, int(.11 * n), IDX_M)
    disc(c, cx, cy, int(.05 * n), IDX_G)
    for a in (0, 90, 180, 270):
        r = math.radians(a)
        dx, dy = math.cos(r), math.sin(r)
        c.poly(P([(0.5 + 0.45 * dx, 0.5 + 0.45 * dy),
                  (0.5 + 0.30 * dx - 0.11 * dy, 0.5 + 0.30 * dy + 0.11 * dx),
                  (0.5 + 0.30 * dx + 0.11 * dy, 0.5 + 0.30 * dy - 0.11 * dx)], n), IDX_B)


def r_swift(c, n):
    for y in (0.26, 0.50, 0.74):
        c.line(P([(0.06, y), (0.40, y)], n), IDX_D, 1)
    c.poly(P([(0.30, 0.16), (0.62, 0.50), (0.30, 0.84), (0.42, 0.50)], n), IDX_M)
    c.poly(P([(0.52, 0.16), (0.86, 0.50), (0.52, 0.84), (0.64, 0.50)], n), IDX_B)
    c.px(int(.80 * n), int(.50 * n), IDX_G)


def r_thrifty(c, n):
    cx, cy = int(.5 * n), int(.5 * n)
    disc(c, cx, cy, int(.42 * n), IDX_M)
    disc(c, cx, cy, int(.30 * n), IDX_D)
    ring(c, cx, cy, int(.42 * n), IDX_B, 1)
    # 向下箭頭（節流 = 藍耗下降）
    c.poly(P([(0.50, 0.70), (0.63, 0.52), (0.55, 0.52), (0.55, 0.32),
              (0.45, 0.32), (0.45, 0.52), (0.37, 0.52)], n), IDX_G)


def r_heavy(c, n):
    c.rect(int(.14 * n), int(.20 * n), int(.86 * n), int(.48 * n), IDX_M)
    c.rect(int(.14 * n), int(.20 * n), int(.86 * n), int(.27 * n), IDX_B)
    c.rect(int(.14 * n), int(.41 * n), int(.86 * n), int(.48 * n), IDX_D)
    c.rect(int(.43 * n), int(.46 * n), int(.57 * n), int(.92 * n), IDX_M)
    c.rect(int(.43 * n), int(.46 * n), int(.48 * n), int(.92 * n), IDX_B)
    for a in (35, 90, 145):
        r = math.radians(a)
        c.line([(int(.5 * n + .26 * n * math.cos(r)), int(.34 * n - .26 * n * math.sin(r))),
                (int(.5 * n + .44 * n * math.cos(r)), int(.34 * n - .44 * n * math.sin(r)))],
               IDX_G, 1)


# util 效用
def r_leech(c, n):
    # 尖牙（左上）→ 滴入血珠（右下），加吸取連線
    c.poly(P([(0.26, 0.10), (0.54, 0.42), (0.26, 0.74)], n), IDX_M)
    c.poly(P([(0.26, 0.10), (0.40, 0.42), (0.26, 0.74)], n), IDX_B)
    c.poly(P([(0.72, 0.40), (0.86, 0.64), (0.72, 0.88), (0.58, 0.64)], n), IDX_M)
    c.poly(P([(0.72, 0.48), (0.80, 0.64), (0.72, 0.80), (0.64, 0.64)], n), IDX_B)
    disc(c, int(.72 * n), int(.66 * n), int(.05 * n), IDX_G)
    c.line([(int(.50 * n), int(.50 * n)), (int(.60 * n), int(.58 * n))], IDX_G, 1)


def r_stun(c, n):
    cx, cy = int(.5 * n), int(.5 * n)
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = 0.46 if i % 2 == 0 else 0.21
        pts.append((0.5 + rr * math.cos(a), 0.5 + rr * math.sin(a)))
    c.poly(P(pts, n), IDX_M)
    c.poly(P([(0.5, 0.16), (0.58, 0.40), (0.5, 0.50), (0.42, 0.40)], n), IDX_B)
    disc(c, cx, cy, int(.09 * n), IDX_B)
    c.px(cx, cy, IDX_G)
    for a in (0, 90, 180, 270):
        r = math.radians(a)
        c.line([(int(cx + .34 * n * math.cos(r)), int(cy + .34 * n * math.sin(r))),
                (int(cx + .46 * n * math.cos(r)), int(cy + .46 * n * math.sin(r)))], IDX_G, 1)


def r_freeze(c, n):
    # 沙漏（冰封 = 減速）+ 上下蓋 + 霜枝，避免讀成蝴蝶結
    c.rect(int(.12 * n), int(.06 * n), int(.88 * n), int(.15 * n), IDX_M)
    c.rect(int(.12 * n), int(.85 * n), int(.88 * n), int(.94 * n), IDX_M)
    c.rect(int(.12 * n), int(.06 * n), int(.88 * n), int(.10 * n), IDX_B)
    c.rect(int(.12 * n), int(.90 * n), int(.88 * n), int(.94 * n), IDX_D)
    c.poly(P([(0.22, 0.15), (0.78, 0.15), (0.54, 0.50), (0.78, 0.85),
              (0.22, 0.85), (0.46, 0.50)], n), IDX_M)
    c.poly(P([(0.30, 0.20), (0.70, 0.20), (0.50, 0.44)], n), IDX_B)
    c.poly(P([(0.44, 0.60), (0.50, 0.80), (0.56, 0.60)], n), IDX_G)
    for y in (0.26, 0.36):
        c.px(int(.05 * n), int(y * n), IDX_B)
        c.px(int(.95 * n), int(y * n), IDX_B)


def r_burn(c, n):
    # 較矮圓的火焰（與 element 的細長火區分）+ 持續傷害刻度環 + 上升餘燼
    c.poly(P([(0.50, 0.20), (0.64, 0.36), (0.58, 0.48), (0.74, 0.56),
              (0.76, 0.72), (0.50, 0.92), (0.24, 0.72), (0.26, 0.56),
              (0.42, 0.48), (0.36, 0.36)], n), IDX_M)
    c.poly(P([(0.50, 0.42), (0.61, 0.58), (0.58, 0.74), (0.50, 0.84),
              (0.42, 0.74), (0.39, 0.58)], n), IDX_B)
    c.poly(P([(0.50, 0.60), (0.56, 0.70), (0.50, 0.80), (0.44, 0.70)], n), IDX_G)
    for a in range(0, 360, 30):                      # 刻度環（缺口朝上）
        if 210 <= a <= 330:
            continue
        r = math.radians(a)
        c.line([(int(.5 * n + .42 * n * math.cos(r)), int(.5 * n + .42 * n * math.sin(r))),
                (int(.5 * n + .48 * n * math.cos(r)), int(.5 * n + .48 * n * math.sin(r)))],
               IDX_D, 1)
    for x, y in [(0.28, 0.22), (0.74, 0.28)]:        # 餘燼
        c.px(int(x * n), int(y * n), IDX_G)


def r_execute(c, n):
    c.ell(int(.18 * n), int(.08 * n), int(.82 * n), int(.64 * n), IDX_M)
    c.rect(int(.36 * n), int(.58 * n), int(.64 * n), int(.82 * n), IDX_M)
    c.ell(int(.24 * n), int(.12 * n), int(.76 * n), int(.40 * n), IDX_B)
    c.rect(int(.29 * n), int(.30 * n), int(.43 * n), int(.46 * n), IDX_T)
    c.rect(int(.57 * n), int(.30 * n), int(.71 * n), int(.46 * n), IDX_T)
    c.px(int(.50 * n), int(.52 * n), IDX_D)
    c.line([(int(.08 * n), int(.94 * n)), (int(.92 * n), int(.06 * n))], IDX_B, 2)


def r_opener(c, n):
    # 杏仁眼（破陣 = 看穿破綻 / 對滿血目標增傷）+ 上方放射
    c.poly(P([(0.04, 0.50), (0.24, 0.30), (0.50, 0.24), (0.76, 0.30), (0.96, 0.50),
              (0.76, 0.70), (0.50, 0.76), (0.24, 0.70)], n), IDX_M)
    c.poly(P([(0.10, 0.50), (0.30, 0.33), (0.50, 0.30), (0.50, 0.44), (0.28, 0.46)], n), IDX_B)
    c.ell(int(.38 * n), int(.37 * n), int(.62 * n), int(.63 * n), IDX_B)
    c.ell(int(.45 * n), int(.44 * n), int(.55 * n), int(.56 * n), IDX_G)
    for a in (65, 90, 115):
        r = math.radians(a)
        c.line([(int(.5 * n + .32 * n * math.cos(r)), int(.5 * n - .32 * n * math.sin(r))),
                (int(.5 * n + .47 * n * math.cos(r)), int(.5 * n - .47 * n * math.sin(r)))],
               IDX_G, 1)


def r_barrier(c, n):
    c.poly(P([(0.50, 0.06), (0.88, 0.22), (0.82, 0.64), (0.50, 0.94),
              (0.18, 0.64), (0.12, 0.22)], n), IDX_M)
    c.poly(P([(0.50, 0.16), (0.78, 0.28), (0.74, 0.60), (0.50, 0.82),
              (0.26, 0.60), (0.22, 0.28)], n), IDX_D)
    for rr in (0.13, 0.21):
        arc(c, int(.5 * n), int(.48 * n), int(rr * n), 200, 340, IDX_B, 1)
    c.px(int(.50 * n), int(.46 * n), IDX_G)


def r_mana(c, n):
    c.poly(P([(0.50, 0.28), (0.68, 0.58), (0.50, 0.88), (0.32, 0.58)], n), IDX_M)
    disc(c, int(.5 * n), int(.68 * n), int(.17 * n), IDX_M)
    disc(c, int(.5 * n), int(.68 * n), int(.09 * n), IDX_G)
    for i, rr in enumerate([0.15, 0.25, 0.35]):
        arc(c, int(.5 * n), int(.62 * n), int(rr * n), 200, 340,
            IDX_B if i == 0 else IDX_D, 1)


def r_amplify(c, n):
    # 寶石核心 + 外擴衝擊弧（AoE 增傷），與 wider 的四向箭頭區分
    cx, cy = int(.5 * n), int(.5 * n)
    c.poly(P([(0.50, 0.20), (0.78, 0.50), (0.50, 0.80), (0.22, 0.50)], n), IDX_M)
    c.poly(P([(0.50, 0.30), (0.67, 0.50), (0.50, 0.70), (0.33, 0.50)], n), IDX_B)
    c.poly(P([(0.50, 0.39), (0.59, 0.50), (0.50, 0.61), (0.41, 0.50)], n), IDX_G)
    for rr in (0.34, 0.44):
        arc(c, cx, cy, int(rr * n), -55, 55, IDX_D, 1)
        arc(c, cx, cy, int(rr * n), 125, 235, IDX_D, 1)


# ============================ 映射 ============================
RUNE_DESIGN = {
    # form（形態）— 金
    "projectile": (r_projectile, "gold"),
    "chain": (r_chain, "gold"),
    "split": (r_split, "gold"),
    "pierce": (r_pierce, "ice"),
    "ground": (r_ground, "ice"),
    "echo": (r_echo, "void"),
    # element（元素）
    "fire": (r_fire, "blood"),
    "cold": (r_cold, "ice"),
    "lightning": (r_lightning, "gold"),
    "poison": (r_poison, "poison"),
    "shadow": (r_shadow, "void"),
    # amp（增幅）
    "wider": (r_wider, "teal"),
    "swift": (r_swift, "teal"),
    "thrifty": (r_thrifty, "gold"),
    "heavy": (r_heavy, "blood"),
    # util（效用）
    "leech": (r_leech, "mythic"),
    "stun": (r_stun, "gold"),
    "freeze": (r_freeze, "ice"),
    "burn": (r_burn, "mythic"),
    "execute": (r_execute, "blood"),
    "opener": (r_opener, "mythic"),
    "barrier": (r_barrier, "ice"),
    "mana": (r_mana, "ice"),
    "amplify": (r_amplify, "gold"),
}


# 底座變體：(符文子畫布邊長, 居中偏移)。石板凹槽較大 ⇒ 符文可放大到 34
BASE_SPEC = {"slab": (34, 7), "frame": (32, 8)}


def render_rune(short, size=SIZE, base="vector"):
    """base: "vector"（純符號）/ "slab"（石板底座）/ "frame"（石框底座）。"""
    prim, series = RUNE_DESIGN[short]
    if base == "vector":
        c = Idx(size)
        prim(c, size)
        return compose_v2(c.outline(), series)

    inner, off = BASE_SPEC[base]
    b = Idx(size)
    (draw_stone_slab if base == "slab" else draw_stone_frame)(b, size)
    img = compose_v2(b.outline(), series)
    s = Idx(inner)
    prim(s, inner)
    img.alpha_composite(compose_v2(s.outline(), series), (off, off))
    return img


# ============================ 預覽 ============================
def preview_sheet(items, scale=3, cols=8):
    """放大圖 + 底部追加「1:1 實際大小」列（判斷遊戲內真實觀感）。"""
    from PIL import Image, ImageDraw
    cell = SIZE * scale
    pad = 8
    rows = (len(items) + cols - 1) // cols
    W = max(cols * (cell + pad) + pad, len(items) * (SIZE + 2) + pad * 2)
    H = rows * (cell + pad + 16) + pad + SIZE + 26
    sheet = Image.new("RGBA", (W, H), (16, 18, 24, 255))
    d = ImageDraw.Draw(sheet)
    for i, (key, img) in enumerate(items):
        r, cc = divmod(i, cols)
        x = pad + cc * (cell + pad)
        y = pad + r * (cell + pad + 16)
        sheet.alpha_composite(img.resize((cell, cell), Image.NEAREST), (x, y))
        d.text((x, y + cell + 2), key, fill=(190, 200, 214, 255))
    y0 = rows * (cell + pad + 16) + pad
    d.text((pad, y0), "1:1 actual size (in-game 48px cell)", fill=(240, 200, 120, 255))
    y0 += 16
    for i, (key, img) in enumerate(items):
        sheet.alpha_composite(img, (pad + i * (SIZE + 2), y0))
    return sheet


## 權威色板（逐字抄自 gen_icons.py，非本檔自算）——合規自檢的比對基準
PALETTE_ALL = {hex2rgb(h) for h in NEUTRAL}
for _v in SERIES.values():
    PALETTE_ALL |= {hex2rgb(h) for h in _v}
PALETTE_ALL.add(OUTLINE_RGB)


def check_compliance(keys):
    """對照權威色板檢查落盤檔：尺寸 / alpha 二值 / 無色板外顏色。"""
    bad, allcols = [], set()
    for k in keys:
        p = os.path.join(QUEST, "rune_icon_%s_48.png" % k)
        im = Image.open(p).convert("RGBA")
        if im.size != (SIZE, SIZE):
            bad.append("%s 尺寸 %s" % (k, im.size))
        a = np.array(im)
        al = np.unique(a[..., 3])
        if not set(int(v) for v in al).issubset({0, 255}):
            bad.append("%s alpha 非二值 %s" % (k, sorted(int(v) for v in al)))
        cols = {tuple(int(v) for v in c) for c in a[a[..., 3] == 255][:, :3]}
        allcols |= cols
        off = cols - PALETTE_ALL
        if off:
            bad.append("%s 色板外 %s" % (k, sorted(off)))
    print("[合規] %d 張：%s" % (len(keys), "全部通過" if not bad else "；".join(bad)))
    print("[合規] 全體用色 %d 色（色板上限 %d）" % (len(allcols), len(PALETTE_ALL)))
    return not bad


def main():
    args = sys.argv[1:]
    only = None
    if "--only" in args:
        only = set(args[args.index("--only") + 1].split(","))
    base = "vector"
    if "--base" in args:
        base = args[args.index("--base") + 1]
    keys = sorted(RUNE_DESIGN) if not only else sorted(only)

    items = [(k, render_rune(k, base=base)) for k in keys]

    if "--sample" in args:
        tag = "" if base == "vector" else "_" + base
        out = os.path.join(HERE, "preview_D2_rune_v2%s_sample.png" % tag)
        preview_sheet(items).save(out)
        print("樣張（未覆蓋遊戲素材）-> %s  （%d 張 / base=%s）"
              % (out, len(items), base))
        return 0

    os.makedirs(QUEST, exist_ok=True)
    for k, img in items:
        img.save(os.path.join(QUEST, "rune_icon_%s_48.png" % k))
    preview_sheet([(k, render_rune(k, base=base)) for k in sorted(RUNE_DESIGN)]).save(
        os.path.join(HERE, "preview_D2_rune_v2.png"))
    print("已落盤 %d 張 48×48（base=%s）-> %s" % (len(items), base, QUEST))
    ok = check_compliance([k for k, _ in items])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
