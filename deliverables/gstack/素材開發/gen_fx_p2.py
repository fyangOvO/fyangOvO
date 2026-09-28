# -*- coding: utf-8 -*-
"""
C1–C6 批次：特效序列幀 sheet（26 張）

規格來源
  · `01-技能体系.md` 附錄 A §A.7（一般方案 20 張）
      元素命中 5 × 32×32 × 6 幀 / 投射物 5 × 16×16 × 4 幀（循環）/
      地面區域 5 × 32×32 × 6 幀（循環）/ 增益光環 4 × 32×32 × 6 幀（循環）/
      召喚法陣 1 × 32×32 × 8 幀
  · `05-monsters.json` → `asset_orders.new_fx`（6 張，檔名由該表指定）

落點：`game/assets/fx/`（`fx.json` 的 `texture` 欄位為相對此目錄的檔名）
契約：**橫向序列幀 sheet**，`貼圖寬 == frame_w × frames`。

命名決策（與既有慣例一致）
  既有 runtime sheet 是 `hit_spark.png` / `slash_arc.png` —— **特效 id ≡ 檔名 stem**，
  沒有 `_pxNN` 後綴（`fx_*_px96` 那 4 張是**產線中間素材**，不是 runtime sheet，見 §A.7 的警告）。
  故本批沿用「id ≡ 檔名」，C6 則一字不改照用 05 表指定的檔名。

技術保證：全程只畫在索引畫布 → 自動描邊 → 映射 `PALETTE_ALL` ⇒ 不可能畫出色板外顏色。
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icons import Idx, compose, SERIES, IDX_T, IDX_O, IDX_D, IDX_M, IDX_B, IDX_G  # noqa: E402

GAME = r"D:/七傳說/game"
OUTDIR = os.path.join(GAME, "assets/fx")

# 自訂色系（PALETTE_ALL 內的 4 階；compose 接受 list）
BONE = ["4E5866", "8C97A8", "B3BCC9", "DCE2E8"]      # 骨白（骸骨/衝擊）
EMBER = ["4A3208", "8C1A1F", "E8573F", "F5D77A"]     # 燼火（隕石/狂暴）
CURSE = ["4A0816", "4E2478", "7E44B8", "B07DE0"]     # 詛咒紫
HOLY = ["4A3208", "8C6510", "D9A521", "DBCC85"]      # 金

SERIES_MAP = dict(SERIES)
SERIES_MAP.update({"bone": BONE, "ember": EMBER, "curse": CURSE, "holy": HOLY})

FRAMES = {}   # name -> (list[Image], spec)


# ============================== 繪圖小工具 ==============================
def cp(n):
    """畫布中心（浮點）。"""
    return (n - 1) / 2.0


def disc(c, cx, cy, r, v):
    if r < 0.5:
        c.px(round(cx), round(cy), v)
        return
    c.ell(cx - r, cy - r, cx + r, cy + r, v)


def ring(c, cx, cy, r, v, dash=(0, 1), steps=None, phase=0.0):
    """虛線環。dash=(畫幾步, 空幾步)；預設全畫。"""
    if steps is None:
        steps = max(12, int(2 * np.pi * r * 1.3))
    on, off = dash
    for i in range(steps):
        if (i + int(phase)) % (on + off) >= on:
            continue
        t = 2 * np.pi * i / steps
        c.px(round(cx + r * np.cos(t)), round(cy + r * np.sin(t)), v)


def rays(c, cx, cy, r0, r1, count, v, phase=0.0, w=1, jitter=0.0, seed=0):
    import math
    rng = np.random.RandomState(seed)
    for i in range(count):
        a = 2 * np.pi * i / count + phase
        rr1 = r1 * (1.0 + (rng.uniform(-jitter, jitter) if jitter else 0.0))
        c.line([(cx + r0 * np.cos(a), cy + r0 * np.sin(a)),
                (cx + rr1 * np.cos(a), cy + rr1 * np.sin(a))], v, w=w)


def blob(c, cx, cy, r, v):
    disc(c, cx, cy, r, v)
    disc(c, cx - r * 0.5, cy - r * 0.4, r * 0.6, v)


# ============================== C1 元素命中 ==============================
def fx_elem_hit(n, t, T, style, series):
    """32×32 × 6 幀：擴散爆裂 + 收縮核心。"""
    p = t / float(T - 1)
    c = Idx(n)
    cx = cy = cp(n)
    R = n * 0.46
    # 收縮核心（最亮）
    rc = max(0.8, n * 0.20 * (1.0 - p * 0.9))
    disc(c, cx, cy, rc + 1.6, IDX_B)
    disc(c, cx, cy, rc, IDX_G)
    # 擴散刺：長度先增後減，讓「炸開」有節奏
    grow = min(1.0, p * 2.2)
    fade = max(0.0, 1.0 - max(0.0, (p - 0.45) / 0.55))
    r_out = R * (0.30 + 0.70 * grow)
    if fade > 0.05:
        if style == "lick":          # 火：向上偏移的火舌
            rays(c, cx, cy - 1.0, rc + 1.0, r_out, 7, IDX_B, phase=0.15, w=1, jitter=0.25, seed=t)
            rays(c, cx, cy - 0.5, rc, r_out * 0.8, 5, IDX_G, phase=-0.3, seed=t + 9)
        elif style == "shard":       # 冰：銳利直刺
            rays(c, cx, cy, rc + 0.5, r_out, 8, IDX_B, phase=np.pi / 8, w=1)
            rays(c, cx, cy, rc, r_out * 0.72, 6, IDX_G, phase=0.0, w=1)
        elif style == "arc":         # 雷：鋸齒
            rays(c, cx, cy, rc, r_out, 6, IDX_B, phase=0.2, w=1, jitter=0.35, seed=t + 3)
        elif style == "bubble":      # 毒：氣泡環
            ring(c, cx, cy, r_out, IDX_B, dash=(1, 1), phase=t)
            ring(c, cx, cy, r_out * 0.68, IDX_M, dash=(1, 2), phase=t + 2)
        else:                        # 暗影：扭轉
            rays(c, cx, cy, rc, r_out, 5, IDX_B, phase=p * 2.4, w=1)
            ring(c, cx, cy, r_out * 0.8, IDX_M, dash=(1, 1), phase=t * 2)
    return c


# ============================== C2 投射物 ==============================
def fx_bolt(n, t, T, style, series):
    """16×16 × 4 幀（循環）：朝右飛行。"""
    c = Idx(n)
    ph = 2 * np.pi * t / float(T)
    cx, cy = cp(n), cp(n)
    if style == "arrow":
        c.poly([(n - 2.0, cy), (n - 7.0, cy - 3.0), (n - 7.0, cy + 3.0)], IDX_B)
        c.line([(2.5, cy), (n - 7.5, cy)], IDX_M, w=1)
        c.px(n - 8, cy - 1, IDX_G); c.px(n - 8, cy + 1, IDX_G)
    elif style == "fire":
        r = 3.6 + 0.9 * np.sin(ph)
        disc(c, n * 0.60, cy, r, IDX_B)
        disc(c, n * 0.62, cy, r * 0.55, IDX_G)
        # 尾巴火舌
        for k in range(3):
            yy = cy + (k - 1) * 1.6
            c.line([(n * 0.42, yy), (2.0 + k, yy + 0.6 * np.sin(ph + k))], IDX_M, w=1)
    elif style == "frost":
        c.poly([(n - 2.0, cy), (n * 0.42, cy - 3.4), (n * 0.34, cy), (n * 0.42, cy + 3.4)], IDX_B)
        c.poly([(n - 4.0, cy), (n * 0.46, cy - 1.4), (n * 0.40, cy), (n * 0.46, cy + 1.4)], IDX_G)
    elif style == "thunder":
        r = 3.4
        disc(c, n * 0.58, cy, r, IDX_M)
        disc(c, n * 0.58, cy, r * 0.5, IDX_G)
        # 環繞電弧（用相位讓它轉）
        a = ph
        c.line([(n * 0.58 + r * np.cos(a), cy + r * np.sin(a)),
                (n * 0.58 + r * np.cos(a + 2.4), cy + r * np.sin(a + 2.4))], IDX_B, w=1)
    else:  # shadow
        r = 3.5
        disc(c, n * 0.58, cy, r, IDX_D)
        ring(c, n * 0.58, cy, r, IDX_B, dash=(1, 1), phase=int(ph * 3))
        disc(c, n * 0.58, cy, 1.2, IDX_G)
    return c


# ============================== C3 地面區域 ==============================
def fx_ground(n, t, T, style, series):
    """32×32 × 6 幀（循環）：貼地，不要畫到上緣（上方要留給角色）。"""
    c = Idx(n)
    cx, cy = cp(n), n * 0.62
    ph = 2 * np.pi * t / float(T)
    R = n * 0.42
    if style == "crack":
        disc(c, cx, cy, R, IDX_D)
        for k in range(5):
            a = 2 * np.pi * k / 5 + ph * 0.25
            c.line([(cx, cy), (cx + R * np.cos(a), cy + R * np.sin(a) * 0.55)], IDX_M, w=1)
        ring(c, cx, cy, R * 0.9, IDX_B, dash=(2, 2), phase=int(t))
    elif style == "poison":
        disc(c, cx, cy, R, IDX_D)
        for k in range(4):
            a = ph + 2 * np.pi * k / 4
            blob(c, cx + R * 0.45 * np.cos(a), cy + R * 0.30 * np.sin(a), 2.2, IDX_M)
        ring(c, cx, cy, R, IDX_B, dash=(1, 2), phase=int(t * 2))
    elif style == "thunder":
        disc(c, cx, cy, R, IDX_D)
        ring(c, cx, cy, R * 0.95, IDX_B, dash=(1, 1), phase=int(t))
        for k in range(3):
            a = ph + 2 * np.pi * k / 3
            x0 = cx + R * 0.5 * np.cos(a); y0 = cy + R * 0.32 * np.sin(a)
            c.line([(x0, y0 - 6), (x0 + 1, y0 - 2), (x0 - 1, y0)], IDX_G, w=1)
    elif style == "meteor":
        disc(c, cx, cy, R, IDX_D)
        disc(c, cx, cy, R * 0.6, IDX_M)
        for k in range(6):
            a = ph * 0.6 + 2 * np.pi * k / 6
            c.px(round(cx + R * 0.75 * np.cos(a)), round(cy + R * 0.45 * np.sin(a)), IDX_G)
        ring(c, cx, cy, R * 0.85, IDX_B, dash=(1, 1), phase=int(t * 2))
    else:  # void
        disc(c, cx, cy, R, IDX_D)
        disc(c, cx, cy, R * 0.55, IDX_T)          # 中心挖空 → 深淵感
        ring(c, cx, cy, R * 0.75, IDX_B, dash=(1, 1), phase=int(-t * 2))
        ring(c, cx, cy, R * 0.95, IDX_M, dash=(1, 2), phase=int(t))
    return c


# ============================== C4 增益光環 ==============================
def fx_aura(n, t, T, style, series):
    """32×32 × 6 幀（循環）：角色腳下一圈。"""
    c = Idx(n)
    cx, cy = cp(n), n * 0.62
    R = n * 0.40
    ph = 2 * np.pi * t / float(T)
    ring(c, cx, cy, R, IDX_B, dash=(2, 2), phase=int(t))
    ring(c, cx, cy, R * 0.72, IDX_M, dash=(1, 3), phase=int(-t))
    if style == "warcry":
        for k in range(4):
            a = ph + 2 * np.pi * k / 4
            c.line([(cx + R * 0.55 * np.cos(a), cy + R * 0.4 * np.sin(a)),
                    (cx + R * 0.95 * np.cos(a), cy + R * 0.7 * np.sin(a))], IDX_G, w=1)
    elif style == "blood_rage":
        for k in range(5):
            a = -ph + 2 * np.pi * k / 5
            c.px(round(cx + R * 0.95 * np.cos(a)), round(cy + R * 0.7 * np.sin(a)), IDX_G)
    elif style == "iron_bulwark":
        for k in range(6):
            a = 2 * np.pi * k / 6
            x0 = cx + R * 0.85 * np.cos(a); y0 = cy + R * 0.6 * np.sin(a)
            c.rect(x0 - 0.8, y0 - 1.2, x0 + 0.8, y0 + 1.2, IDX_G)
    else:  # hawk_eye
        for k in range(3):
            a = ph * 1.4 + 2 * np.pi * k / 3
            disc(c, cx + R * 0.8 * np.cos(a), cy + R * 0.58 * np.sin(a), 1.4, IDX_G)
    return c


# ============================== C5 召喚法陣 ==============================
def fx_summon(n, t, T, style, series):
    """32×32 × 8 幀（一次性）：生成 → 轉 → 收束。"""
    c = Idx(n)
    cx, cy = cp(n), n * 0.55
    p = t / float(T - 1)
    R = n * 0.44
    grow = min(1.0, p * 3.0)                 # 前 1/3 長大
    shrink = max(0.15, 1.0 - max(0.0, (p - 0.62) / 0.38))
    r = R * grow * shrink
    ring(c, cx, cy * 0.72 + cy * 0.28, r, IDX_B, dash=(2, 2), phase=int(t * 2))
    ring(c, cx, cy, r * 0.78, IDX_M, dash=(1, 2), phase=int(-t * 3))
    ring(c, cx, cy, r * 0.5, IDX_B, dash=(1, 1), phase=int(t * 4))
    # 符文點（繞圈）
    for k in range(8):
        a = 2 * np.pi * k / 8 + t * 0.5
        c.px(round(cx + r * 1.05 * np.cos(a) * 0.96), round(cy + r * 1.05 * np.sin(a) * 0.62), IDX_G)
    # 中央光柱
    if p > 0.2:
        c.rect(cx - 1, cy - r * 0.9, cx + 1, cy + r * 0.9, IDX_B)
    return c


# ============================== C6 第五步新增 ==============================
def fx_c6(n, t, T, style, series):
    """依 05-monsters.json 指定的 6 個特效。"""
    c = Idx(n)
    cx, cy = cp(n), cp(n)
    p = t / float(T - 1)
    if style == "lightning_spark":
        disc(c, cx, cy, 3.0 - 2.0 * p, IDX_G)
        for k in range(6):
            a = 2 * np.pi * k / 6 + p * 0.8
            L = (n * 0.44) * (0.4 + 0.6 * (1 - p))
            mid = (cx + L * 0.55 * np.cos(a) + 1.2, cy + L * 0.55 * np.sin(a))
            c.line([(cx, cy), mid], IDX_B, w=1)
            c.line([mid, (cx + L * np.cos(a), cy + L * np.sin(a))], IDX_B, w=1)
    elif style == "shadow_curse":
        ring(c, cx, cy, n * 0.16 + n * 0.26 * p, IDX_B, dash=(1, 1), phase=int(t * 3))
        ring(c, cx, cy, n * 0.10 + n * 0.20 * p, IDX_M, dash=(2, 2), phase=int(-t * 2))
        for k in range(4):
            a = np.pi / 4 + np.pi / 2 * k
            c.line([(cx + 3 * np.cos(a), cy + 3 * np.sin(a)),
                    (cx + (n * 0.42) * np.cos(a), cy + (n * 0.42) * np.sin(a))], IDX_G, w=1)
    elif style == "bone_slam":
        # 扇形重擊：**從上方落點往下炸開的裂扇** + 外擴衝擊弧。
        # ⚠️ 先前用「垂直長條 x4」畫成白色柵欄，完全讀不出重擊（實測）。
        ix, iy = cx, n * 0.20
        L = n * 0.30 * (0.45 + 0.55 * p)
        for k in range(7):
            a = np.pi * (0.15 + 0.70 * k / 6.0)
            ex = ix + L * np.cos(a)
            ey = iy + L * np.sin(a)
            c.line([(ix, iy), (ex, ey)], IDX_B, w=1)
            c.px(round(ex), round(ey), IDX_G)
        # 衝擊弧（半圓，往下掃）
        r = n * 0.20 * (0.55 + 0.65 * p)
        for a in np.linspace(np.pi * 0.16, np.pi * 0.84, 26):
            c.px(round(ix + r * np.cos(a)), round(iy + r * np.sin(a) * 0.72), IDX_M)
    elif style == "lob_impact":
        r = n * (0.16 + 0.30 * p)
        ring(c, cx, cy, r, IDX_B, dash=(2, 1), phase=int(t * 2))
        disc(c, cx, cy, max(1.0, n * 0.13 * (1 - p)), IDX_G)
        for k in range(6):
            a = 2 * np.pi * k / 6 + p
            c.px(round(cx + r * 1.25 * np.cos(a)), round(cy + r * 0.75 * np.sin(a)), IDX_M)
    else:  # exit_portal
        r = n * 0.40
        ring(c, cx, cy, r, IDX_B, dash=(1, 1), phase=int(t * 3))
        ring(c, cx, cy, r * 0.7, IDX_G, dash=(2, 2), phase=int(-t * 4))
        ring(c, cx, cy, r * 0.42, IDX_B, dash=(1, 2), phase=int(t * 5))
    return c


# ============================== 狂暴全屏疊加 ==============================
def enrage_frame(w, h, t, T):
    """全屏紅色暗角疊加（4 幀，強度遞增）。
    ⚠️ 用 numpy 直接算「到邊框的距離」而不是畫圓：
    160×90 的畫面，中心到角落距離 91.8 > 半寬 80 ⇒ **圓形暗角在這個畫布上畫不出來**，
    先前做法會把頂部整片裁掉、只剩底下幾道弧（實測）。矩形暗角才覆蓋得滿。
    """
    p = (t + 1) / float(T)
    ys, xs = np.mgrid[0:h, 0:w]
    # 到最近邊框的正規化距離：0 = 貼邊, 1 = 畫面正中
    dx = np.minimum(xs, w - 1 - xs) / (w / 2.0)
    dy = np.minimum(ys, h - 1 - ys) / (h / 2.0)
    d = np.minimum(dx, dy)
    idx = np.zeros((h, w), np.uint8)
    idx[d < (0.42 + 0.30 * p)] = IDX_D
    idx[d < (0.26 + 0.30 * p)] = IDX_M
    idx[d < (0.12 + 0.30 * p)] = IDX_B
    # 不做 outline（暗角是連續面，描邊會出現格格不入的硬線）
    return compose(idx, resolve("ember"))


# ============================== 產線 ==============================
def resolve(series):
    """色系名 → 實際 4 色清單。
    ⚠️ `gen_icons.compose()` 只認 `SERIES`（7 個內建名）；
    本檔新增的 bone / ember / curse / holy 必須**先解析成清單**再傳進去，否則 KeyError。"""
    if isinstance(series, str):
        return SERIES_MAP[series]
    return series


def build(name, n, T, painter, style, series):
    cols = resolve(series)
    frames = [compose(painter(n, t, T, style, cols).outline(), cols) for t in range(T)]
    FRAMES[name] = (frames, (n, n, T))
    return name


def build_sheet_frames(frames, fw, fh):
    sheet = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * fw, 0))
    return sheet


def save(name, _ignored=None):
    frames, (fw, fh, T) = FRAMES[name]
    sheet = build_sheet_frames(frames, fw, fh)
    p = os.path.join(OUTDIR, name + ".png")
    if os.path.exists(p):
        return False
    os.makedirs(OUTDIR, exist_ok=True)
    sheet.save(p)
    return True


C1 = [("elem_hit_fire", "lick", "blood"), ("elem_hit_frost", "shard", "ice"),
      ("elem_hit_thunder", "arc", "gold"), ("elem_hit_poison", "bubble", "poison"),
      ("elem_hit_shadow", "swirl", "void")]
C2 = [("bolt_arrow", "arrow", "bone"), ("bolt_fire", "fire", "blood"),
      ("bolt_frost", "frost", "ice"), ("bolt_thunder", "thunder", "gold"),
      ("bolt_shadow", "shadow", "void")]
C3 = [("ground_crack", "crack", "ember"), ("ground_poison", "poison", "poison"),
      ("ground_thunder", "thunder", "gold"), ("ground_meteor", "meteor", "ember"),
      ("ground_void", "void", "void")]
C4 = [("aura_warcry", "warcry", "blood"), ("aura_blood_rage", "blood_rage", "blood"),
      ("aura_iron_bulwark", "iron_bulwark", "ice"), ("aura_hawk_eye", "hawk_eye", "holy")]

# C6 檔名一字不改照用 05-monsters.json 的 asset_orders.new_fx
C6 = [("fx_lightning_spark", 32, 4, "lightning_spark", "gold"),
      ("fx_shadow_curse", 32, 4, "shadow_curse", "curse"),
      ("fx_bone_slam", 64, 4, "bone_slam", "bone"),
      ("fx_lob_impact", 48, 4, "lob_impact", "ember"),
      ("tile_exit_portal", 32, 4, "exit_portal", "teal")]


def main():
    made = skipped = 0
    rows = []

    print("=== C1 元素命中（32×32 × 6 幀）===")
    for name, style, series in C1:
        if save(name, build(name, 32, 6, fx_elem_hit, style, series)):
            made += 1
        else:
            skipped += 1
        rows.append(name)
    print("=== C2 投射物（16×16 × 4 幀，循環）===")
    for name, style, series in C2:
        if save(name, build(name, 16, 4, fx_bolt, style, series)):
            made += 1
        else:
            skipped += 1
        rows.append(name)
    print("=== C3 地面區域（32×32 × 6 幀，循環）===")
    for name, style, series in C3:
        if save(name, build(name, 32, 6, fx_ground, style, series)):
            made += 1
        else:
            skipped += 1
        rows.append(name)
    print("=== C4 增益光環（32×32 × 6 幀，循環）===")
    for name, style, series in C4:
        if save(name, build(name, 32, 6, fx_aura, style, series)):
            made += 1
        else:
            skipped += 1
        rows.append(name)
    print("=== C5 召喚法陣（32×32 × 8 幀，一次性）===")
    if save("summon_circle", build("summon_circle", 32, 8, fx_summon, "circle", "void")):
        made += 1
    else:
        skipped += 1
    rows.append("summon_circle")

    print("=== C6 第五步新增 6 張 ===")
    for name, n, T, style, series in C6:
        if save(name, build(name, n, T, fx_c6, style, series)):
            made += 1
        else:
            skipped += 1
        rows.append(name)
    # enrage 全屏疊加：單獨處理（尺寸非方形）
    p = os.path.join(OUTDIR, "fx_enrage_flash.png")
    if os.path.exists(p):
        skipped += 1
    else:
        frames = [enrage_frame(160, 90, t, 4) for t in range(4)]
        build_sheet_frames(frames, 160, 90).save(p)
        made += 1
    rows.append("fx_enrage_flash")

    print("\n合計：新增 %d，已存在跳過 %d，總計 %d 張 sheet" % (made, skipped, len(rows)))

    # ---- 自校驗：色板（現讀 game_constants.gd，保持唯一真源）+ sheet 寬度契約 ----
    # ⚠️ `PALETTE_ALL = PALETTE_NEUTRAL + PALETTE_ACCENT + PALETTE_RARITY_SEMANTIC`
    #    —— 不能只抓 `PALETTE_ALL = [...]`（它是三個常量的串接，regex 只會抓到 11 色而誤報）。
    import re
    src = open(os.path.join(GAME, "scripts/core/game_constants.gd"), encoding="utf-8").read()
    pal = set()
    for cname in ("PALETTE_NEUTRAL", "PALETTE_ACCENT", "PALETTE_RARITY_SEMANTIC"):
        mm = re.search(r"const %s[^=]*=\s*\[(.*?)\]" % cname, src, re.S)
        if not mm:
            raise SystemExit("找不到色板常量 %s" % cname)
        for h in re.findall(r'"([0-9A-Fa-f]{6})"', mm.group(1)):
            pal.add((int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
    bad = []
    for name in rows:
        fp = os.path.join(OUTDIR, name + ".png")
        if not os.path.exists(fp):
            bad.append((name, "MISSING")); continue
        im = Image.open(fp).convert("RGBA")
        a = np.array(im)
        if name in FRAMES:
            fw, fh, T = FRAMES[name][1]
            if im.size != (fw * T, fh):
                bad.append((name, "size %s != %s" % (im.size, (fw * T, fh))))
        else:  # enrage 非方形
            if im.size[1] != 90 or im.size[0] != 160 * 4:
                bad.append((name, "size %s" % (im.size,)))
        mm = a[:, :, 3] > 0
        out = set(map(tuple, a[mm][:, :3])) - pal
        if out:
            bad.append((name, "%d 色在色板外 %s" % (len(out), sorted(out)[:2])))
        al = sorted(set(np.unique(a[:, :, 3]).tolist()))
        if not set(al) <= {0, 255}:
            bad.append((name, "alpha %s" % al))
    print("自校驗（PALETTE_ALL %d 色）：異常 %d %s" % (len(pal), len(bad), bad[:5]))
    for r in rows:
        print("  " + r)


if __name__ == "__main__":
    main()
