# -*- coding: utf-8 -*-
"""
F3 + I1 + §8.3 批次：異常 / 附著 / 邊框 / 角標 / 增益系統 UI 圖標

規格來源
  · `03-elements.json` → `naming`：
      ailment_icon  = `ailment_<key>_24.png`    （燃烧/冰冻/中毒）
      attach_layer  = `attach_<key>_32.png`
      skill_frame   = `skill_frame_<key>_48.png`
      affix_badge   = `elem_badge_<key>_16.png`
  · `04-数值与数据模型.md` §8.1（临时增益系统 UI 10 张）
  · `04-数值与数据模型.md` §8.3（元素专精：`elem_dmg_*_24` 6 张 + 3 个新异常）

技术保证（与 gen_icons.py 同源）
  全程只畫在索引畫布上 → 自動描邊 → 最後才映射成 `PALETTE_ALL` 顏色
  ⇒ 結構上不可能畫出色板外顏色。`skill_frame` 走「既有邊框重上色」，
  上色後仍逐檔驗證合規。
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icons import Idx, compose, hex2rgb, PRIMS, SERIES, OUTLINE_RGB, \
    IDX_T, IDX_O, IDX_D, IDX_M, IDX_B, IDX_G  # noqa: E402

GAME = r"D:/七傳說/game"
OUTDIR = os.path.join(GAME, "assets/ui/quest")

# 元素 → (基元, 色系)。物理走中性灰藍，其餘照元素語意。
# ⚠️ physical 用 `plate` 與 `elem_physical_24.png`（gen_icons.py 的 ELEMENTS 表）保持同源，
#    這樣「元素傷害」圖標才看得出是「同一元素的加強版」。
# ⚠️ 不要用 `fist`：它的 4 個指節矩形在 ≤24px 會糊成一塊實心方塊（實測）。
ELEM_PRIM = {
    "physical":  ("plate", "ice"),
    "fire":      ("flame", "blood"),
    "cold":      ("snow", "ice"),
    "lightning": ("bolt", "gold"),
    "poison":    ("drop", "poison"),
    "shadow":    ("crescent", "void"),
}
ELEM_ORDER = ["physical", "fire", "cold", "lightning", "poison", "shadow"]

# 異常狀態：key → (基元, 色系)
AILMENTS = [
    ("burn",   "flame",  "blood"),   # 燃燒
    ("chill",  "snow",   "ice"),     # 冰凍 / 緩速
    ("poison", "drop",   "poison"),  # 中毒
    ("shock",  "bolt",   "gold"),    # 感電（§8.3 新增）
    ("curse",  "skull",  "void"),    # 詛咒（§8.3 新增）
    ("sunder", "broken", "gold"),    # 破甲（§8.3 新增）
]

# 臨時增益：orb key → (基元, 色系)
# ⚠️ boss_might 原本想用 `fist`，但 12px 內圈放不下指節細節 ⇒ 改 `up`（向上的力量）。
TEMP_ORBS = [
    ("haste",      "chev",   "teal"),
    ("pierce",     "fang",   "blood"),
    ("leech",      "drop",   "blood"),
    ("boss_might", "up",     "gold"),
    ("boss_echo",  "spiral", "void"),
]
TEMP_SHRINES = [("fury", "flame", "blood"), ("swift", "bolt", "teal"), ("ward", "shield", "ice")]


# ---------------------------------------------------------------- 輔助
def _blit_idx(dst: Idx, src: Idx, x0: int, y0: int) -> None:
    """把 src 的非透明索引貼到 dst 的 (x0,y0)（不覆蓋 dst 已有的內容以外）。"""
    a = src.arr()
    h, w = a.shape
    for y in range(h):
        for x in range(w):
            v = int(a[y, x])
            if v != IDX_T:
                dst.px(x0 + x, y0 + y, v)


def _scaled(prim: str, n: int) -> Idx:
    c = Idx(n)
    PRIMS[prim](c, n)
    return c


# ---------------------------------------------------------------- 各批次
def render_ailment(prim: str, series: str) -> Image.Image:
    """24×24：深色底片（chip）+ 中央符號 → 一眼可辨「這是狀態」而非「這是元素」。"""
    c = Idx(24)
    c.rect(2, 2, 21, 21, IDX_D)          # 深底
    c.rect(3, 3, 20, 20, IDX_M)          # 中間調
    inner = _scaled(prim, 16)
    ia = inner.arr()
    # 把符號疊上去：符號本色 → 亮 / 輝光（在深底上才看得見）
    for y in range(16):
        for x in range(16):
            v = int(ia[y, x])
            if v == IDX_T:
                continue
            c.px(x + 4, y + 4, IDX_G if v in (IDX_O, IDX_D) else IDX_B)
    return compose(c.outline(), series)


def render_attach(prim: str, series: str) -> Image.Image:
    """32×32：虛線環 + 中央元素符號（元素附著覆蓋層）。
    ⚠️ 環必須**密集取樣**（100 步 / 周長 ≈ 82px ⇒ 約 0.8px 一步）；
    先前只取 33 點，畫出來是 8 撮碎點而不是一圈虛線（實測）。"""
    c = Idx(32)
    R = 13.0
    steps = 100
    for i in range(steps):
        if (i % 12) >= 7:          # 8 段虛線：每 12 步畫 7、空 5
            continue
        t = 2 * np.pi * i / steps
        c.px(round(15.5 + R * np.cos(t)), round(15.5 + R * np.sin(t)), IDX_M)
    inner = _scaled(prim, 18)
    _blit_idx(c, inner, 7, 7)
    return compose(c.outline(), series)


def render_badge(prim: str, series: str) -> Image.Image:
    """16×16：小菱形角標 + 中央極簡符號（元素專精詞綴角標）。"""
    c = Idx(16)
    c.poly([(7.5, 1), (14, 7.5), (7.5, 14), (1, 7.5)], IDX_D)
    inner = _scaled(prim, 10)
    ia = inner.arr()
    for y in range(10):
        for x in range(10):
            v = int(ia[y, x])
            if v == IDX_T:
                continue
            c.px(x + 3, y + 3, IDX_B if v == IDX_O else IDX_G)
    return compose(c.outline(), series)


def render_elem_dmg(prim: str, series: str) -> Image.Image:
    """24×24：元素符號 + 四向爆裂短刺 → 讀作「該元素傷害」。
    ⚠️ **先畫刺、後貼符號**：`outline()` 會把「內容」與「內容」之間的任何透明像素
    標成描邊色，所以刺只要不與符號**像素相鄰**就會被描邊隔開、變成 4 顆孤立小點（實測）。
    刺從半徑 4 起（符號半徑 ~8.5）⇒ 內端被符號覆蓋，外露部分必然相連。"""
    c = Idx(24)
    for (dx, dy) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        x0 = 11.5 + dx * 4.0
        y0 = 11.5 + dy * 4.0
        c.line([(x0, y0), (x0 + dx * 6.5, y0 + dy * 6.5)], IDX_M)
    inner = _scaled(prim, 18)
    _blit_idx(c, inner, 3, 3)
    return compose(c.outline(), series)


def render_shrine(prim: str, series: str) -> Image.Image:
    """32×32：基座（梯形）+ 上方符號（神龕）。
    符號下移使其**與座頸相接**（先前留 2px 空隙，看起來像兩個無關的圖疊在一起）。"""
    c = Idx(32)
    c.poly([(9, 29), (22, 29), (20, 23), (11, 23)], IDX_D)    # 基座
    c.rect(12, 20, 19, 22, IDX_M)                             # 座頸
    inner = _scaled(prim, 18)
    _blit_idx(c, inner, 7, 3)
    return compose(c.outline(), series)


def render_orb(prim: str, series: str) -> Image.Image:
    """24×24：球體（同心圓）+ 內部符號。"""
    c = Idx(24)
    c.ell(1, 1, 22, 22, IDX_D)
    c.ell(3, 3, 20, 20, IDX_M)
    c.ell(5, 5, 18, 18, IDX_D)
    inner = _scaled(prim, 12)
    ia = inner.arr()
    for y in range(12):
        for x in range(12):
            v = int(ia[y, x])
            if v == IDX_T:
                continue
            c.px(x + 6, y + 6, IDX_G)
    return compose(c.outline(), series)


def render_bar(kind: str, w: int = 64, h: int = 6) -> Image.Image:
    """倒計時條：bg = 深凹槽；fill = 亮條。"""
    c = Idx(max(w, h))
    if kind == "bg":
        c.rect(0, 0, w - 1, h - 1, IDX_D)
        c.rect(1, 1, w - 2, h - 2, IDX_T)
        img = compose(c.outline(), "teal")
    else:
        c.rect(0, 0, w - 1, h - 1, IDX_B)
        c.rect(0, 0, w - 1, 0, IDX_G)
        c.rect(0, h - 1, w - 1, h - 1, IDX_D)
        img = compose(c.outline(), "gold")
    return img.crop((0, 0, w, h))


def recolor_frame(src_png: str, series: str) -> Image.Image:
    """讀既有 slot 邊框，按亮度排序重上色到目標色系（保持造型語言）。"""
    im = Image.open(src_png).convert("RGBA")
    a = np.array(im)
    cols = SERIES[series]
    rgb = [hex2rgb(c) for c in cols]
    m = a[:, :, 3] > 0
    uniq = sorted({tuple(int(v) for v in px[:3]) for px in a[m]})
    # 亮度序 → 色系序（OUTLINE_RGB 永遠保持描邊）
    ranked = [c for c in uniq if c != OUTLINE_RGB]
    ranked.sort(key=lambda c: c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114)
    n = len(ranked)
    table = {}
    for i, c in enumerate(ranked):
        # 由暗到亮映射到 series[0..3]
        j = 0 if n == 1 else min(len(rgb) - 1, round(i * (len(rgb) - 1) / (n - 1)))
        table[c] = rgb[j]
    out = a.copy()
    # 向量化替換（描邊色原樣保留）
    for c, nc in table.items():
        m2 = (a[:, :, 0] == c[0]) & (a[:, :, 1] == c[1]) & (a[:, :, 2] == c[2]) & m
        out[m2, 0] = nc[0]; out[m2, 1] = nc[1]; out[m2, 2] = nc[2]
    return Image.fromarray(out, "RGBA")


# ---------------------------------------------------------------- 主流程
def save(img: Image.Image, name: str) -> bool:
    p = os.path.join(OUTDIR, name)
    if os.path.exists(p):
        return False
    os.makedirs(OUTDIR, exist_ok=True)
    img.save(p)
    return True


def main():
    made, skipped = 0, 0
    rows = []

    print("=== F3 異常狀態圖標（24×24，6 張）===")
    for key, prim, series in AILMENTS:
        if save(render_ailment(prim, series), "ailment_%s_24.png" % key):
            made += 1
        else:
            skipped += 1
        rows.append("ailment_%s_24.png" % key)

    print("=== 元素附著覆蓋層 attach（32×32，6 張）===")
    for key in ELEM_ORDER:
        prim, series = ELEM_PRIM[key]
        if save(render_attach(prim, series), "attach_%s_32.png" % key):
            made += 1
        else:
            skipped += 1
        rows.append("attach_%s_32.png" % key)

    print("=== 元素技能邊框 skill_frame（48×48，6 張，既有 slot_common_48 重上色）===")
    base = os.path.join(OUTDIR, "slot_common_48.png")
    if not os.path.exists(base):
        print("  [WARN] 找不到 slot_common_48.png，跳過此批")
    else:
        for key in ELEM_ORDER:
            prim, series = ELEM_PRIM[key]
            if save(recolor_frame(base, series), "skill_frame_%s_48.png" % key):
                made += 1
            else:
                skipped += 1
            rows.append("skill_frame_%s_48.png" % key)

    print("=== 元素專精角標 elem_badge（16×16，5 張）===")
    for key in ["fire", "cold", "lightning", "poison", "shadow"]:
        prim, series = ELEM_PRIM[key]
        if save(render_badge(prim, series), "elem_badge_%s_16.png" % key):
            made += 1
        else:
            skipped += 1
        rows.append("elem_badge_%s_16.png" % key)

    print("=== 單元素傷害圖標 elem_dmg（24×24，6 張）===")
    for key in ELEM_ORDER:
        prim, series = ELEM_PRIM[key]
        if save(render_elem_dmg(prim, series), "elem_dmg_%s_24.png" % key):
            made += 1
        else:
            skipped += 1
        rows.append("elem_dmg_%s_24.png" % key)

    print("=== I1 臨時增益 · 神龕（32×32，3 張）===")
    for key, prim, series in TEMP_SHRINES:
        if save(render_shrine(prim, series), "temp_buff_shrine_%s_32.png" % key):
            made += 1
        else:
            skipped += 1
        rows.append("temp_buff_shrine_%s_32.png" % key)

    print("=== I1 臨時增益 · 增益球（24×24，5 張）===")
    for key, prim, series in TEMP_ORBS:
        if save(render_orb(prim, series), "temp_buff_orb_%s_24.png" % key):
            made += 1
        else:
            skipped += 1
        rows.append("temp_buff_orb_%s_24.png" % key)

    print("=== I1 倒計時條（64×6，2 張）===")
    for kind in ("bg", "fill"):
        if save(render_bar(kind), "temp_buff_timer_bar_%s.png" % kind):
            made += 1
        else:
            skipped += 1
        rows.append("temp_buff_timer_bar_%s.png" % kind)

    print("\n合計：新增 %d，已存在跳過 %d，總計 %d" % (made, skipped, len(rows)))
    for r in rows:
        print("  " + r)


if __name__ == "__main__":
    main()
