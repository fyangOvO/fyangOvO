# -*- coding: utf-8 -*-
"""
E1 + F1/F2 批次：詞綴圖標 48 張（32×32）+ 元素圖標 6 + 抗性圖標 5（24×24）

規格來源
  · 詞綴：02-装备属性.md 附錄B §B.5 ／ naming `affix_<stat_key>_32.png`（44 色嚴格）
  · 元素：03-elements.json → `naming.element_icon` = `elem_<key>_24.png`、`resist_<key>_24.png`
    ⚠️ 24×24，不是 48×48（清單 v2 寫錯了，本檔已修正）

技術保證（為什麼不可能畫出色板外顏色）
  1. 全程只畫在「索引畫布」上：0=透明 1=描邊 2=暗 3=中 4=亮 5=輝光
  2. 畫完自動描邊（4 鄰接膨脹 1px → 索引 1）⇒ 風格統一、免手繪輪廓
  3. 最後才用色系把索引映射成 `PALETTE_ALL` 的實際顏色 ⇒ 天生合規
  4. alpha 二值（0/255）、無抗鋸齒（PIL 的 L 模式繪圖無 AA）
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

GAME = r"D:/七傳說/game"
OUTDIR = os.path.join(GAME, "assets/ui/quest")
PLAN = r"D:/七傳說/deliverables/gstack/策划案"

# ---- 44 色 PALETTE_ALL（逐字抄自 scripts/core/game_constants.gd）----
NEUTRAL = ["0B0D10", "14171C", "1E232B", "2A313B", "3A424F", "4E5866",
           "6B7688", "8C97A8", "B3BCC9", "DCE2E8", "DBCC85"]
SERIES = {
    "blood":   ["4A0E12", "8C1A1F", "C42B2B", "E8573F"],
    "poison":  ["0F2417", "1E4A2B", "3B7A44", "6FB35C"],
    "ice":     ["101A3A", "1F3468", "3A5FB0", "6E9BE8"],
    "gold":    ["4A3208", "8C6510", "D9A521", "F5D77A"],
    "void":    ["2A1440", "4E2478", "7E44B8", "B07DE0"],
    "mythic":  ["4A0816", "B01038", "FF2D55", "FF7A96"],
    "teal":    ["0A2B22", "1B6B52", "2FA37A", "6FE0B4"],
}
OUTLINE_RGB = (11, 13, 16)          # 0B0D10

IDX_T, IDX_O, IDX_D, IDX_M, IDX_B, IDX_G = 0, 1, 2, 3, 4, 5


def hex2rgb(h):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# ============================ 索引畫布 ============================
class Idx:
    def __init__(self, size):
        self.n = size
        self.im = Image.new("L", (size, size), IDX_T)
        self.d = ImageDraw.Draw(self.im)

    def px(self, x, y, v):
        if 0 <= x < self.n and 0 <= y < self.n:
            self.im.putpixel((int(x), int(y)), v)

    def rect(self, x0, y0, x1, y1, v):
        self.d.rectangle([int(x0), int(y0), int(x1), int(y1)], fill=v)

    def ell(self, x0, y0, x1, y1, v):
        self.d.ellipse([int(x0), int(y0), int(x1), int(y1)], fill=v)

    def poly(self, pts, v):
        self.d.polygon([(int(a), int(b)) for a, b in pts], fill=v)

    def line(self, pts, v, w=1):
        self.d.line([(int(a), int(b)) for a, b in pts], fill=v, width=int(w))

    def vline(self, x, y0, y1, v):
        self.line([(x, y0), (x, y1)], v)

    def hline(self, y, x0, x1, v):
        self.line([(x0, y), (x1, y)], v)

    def arr(self):
        return np.array(self.im)

    def outline(self):
        """把透明像素中 4 鄰接有內容的，標成描邊色。回傳新索引陣列。"""
        a = self.arr()
        solid = a != IDX_T
        pad = np.pad(solid, 1)
        nb = (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:])
        out = a.copy()
        out[(a == IDX_T) & nb] = IDX_O
        return out


def compose(idx_arr, series):
    """索引 → RGBA。series 是 SERIES 的鍵名或自訂 4 色清單。"""
    pal = {IDX_T: None, IDX_O: OUTLINE_RGB}
    cols = SERIES[series] if isinstance(series, str) else series
    for i, k in enumerate([IDX_D, IDX_M, IDX_B, IDX_G]):
        pal[k] = hex2rgb(cols[i])
    h, w = idx_arr.shape
    out = np.zeros((h, w, 4), np.uint8)
    for k, c in pal.items():
        if c is None:
            continue
        m = idx_arr == k
        out[m] = (*c, 255)
    return Image.fromarray(out, "RGBA")


# ============================ 圖形基元 ============================
def scale_pts(pts, n, pad=2):
    """把 0..1 正規化座標映射到像素（可用區域 n-2*pad）。"""
    return [(pad + x * (n - 2 * pad - 1), pad + y * (n - 2 * pad - 1)) for x, y in pts]


def g_sword(c, n):
    c.poly(scale_pts([(.5, .02), (.62, .18), (.62, .58), (.38, .58), (.38, .18)], n), IDX_B)
    c.rect(*[v for p in [(.24, .58), (.76, .66)] for v in (p[0] * n, p[1] * n)], fill=IDX_M) if False else None
    c.hline(int(.62 * n), int(.22 * n), int(.78 * n), IDX_M)
    c.vline(int(.5 * n), int(.66 * n), int(.92 * n), IDX_M)


def g_shield(c, n):
    c.poly(scale_pts([(.5, .04), (.88, .2), (.82, .62), (.5, .94), (.18, .62), (.12, .2)], n), IDX_M)
    c.poly(scale_pts([(.5, .16), (.76, .27), (.72, .58), (.5, .8), (.28, .58), (.24, .27)], n), IDX_D)


def g_boot(c, n):
    c.poly(scale_pts([(.3, .08), (.62, .08), (.66, .52), (.86, .62), (.86, .86), (.3, .86)], n), IDX_M)
    c.hline(int(.86 * n), int(.3 * n), int(.86 * n), IDX_B)


def g_heart(c, n):
    c.ell(int(.10 * n), int(.16 * n), int(.56 * n), int(.60 * n), IDX_M)
    c.ell(int(.44 * n), int(.16 * n), int(.90 * n), int(.60 * n), IDX_M)
    c.poly(scale_pts([(.10, .42), (.90, .42), (.5, .94)], n), IDX_M)
    c.ell(int(.24 * n), int(.26 * n), int(.40 * n), int(.42 * n), IDX_B)


def g_drop(c, n):
    c.poly(scale_pts([(.5, .04), (.82, .52), (.5, .94), (.18, .52)], n), IDX_M)
    c.ell(int(.18 * n), int(.42 * n), int(.82 * n), int(.94 * n), IDX_M)
    c.ell(int(.30 * n), int(.56 * n), int(.46 * n), int(.72 * n), IDX_B)


def g_star(c, n):
    import math
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        r = .48 if i % 2 == 0 else .20
        pts.append((.5 + r * math.cos(ang), .5 + r * math.sin(ang)))
    c.poly(scale_pts(pts, n), IDX_B)
    c.ell(int(.40 * n), int(.40 * n), int(.52 * n), int(.52 * n), IDX_G)


def g_clock(c, n):
    c.ell(int(.06 * n), int(.06 * n), int(.94 * n), int(.94 * n), IDX_M)
    c.ell(int(.20 * n), int(.20 * n), int(.80 * n), int(.80 * n), IDX_D)
    c.vline(int(.5 * n), int(.5 * n), int(.24 * n), IDX_B)
    c.line([(int(.5 * n), int(.5 * n)), (int(.72 * n), int(.62 * n))], IDX_B)


def g_bolt(c, n):
    c.poly(scale_pts([(.62, .02), (.24, .54), (.46, .54), (.36, .96), (.78, .42), (.54, .42)], n), IDX_B)
    c.poly(scale_pts([(.60, .10), (.34, .50), (.48, .50), (.42, .82), (.70, .46), (.56, .46)], n), IDX_G)


def g_flame(c, n):
    import math
    pts = [(.5, .02), (.72, .28), (.68, .42), (.84, .48), (.82, .72), (.5, .96), (.18, .72), (.16, .48), (.32, .42), (.28, .28)]
    c.poly(scale_pts(pts, n), IDX_M)
    c.poly(scale_pts([(.5, .40), (.64, .58), (.60, .80), (.5, .90), (.40, .80), (.36, .58)], n), IDX_B)
    c.poly(scale_pts([(.5, .62), (.56, .74), (.5, .86), (.44, .74)], n), IDX_G)


def g_snow(c, n):
    cx, cy, r = int(.5 * n), int(.5 * n), int(.44 * n)
    for k in range(3):
        import math
        ang = k * math.pi / 3
        dx, dy = int(r * math.cos(ang)), int(r * math.sin(ang))
        c.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], IDX_B)
    for k in range(6):
        import math
        ang = k * math.pi / 3
        bx, by = int(.26 * n * math.cos(ang)), int(.26 * n * math.sin(ang))
        c.line([(cx + bx, cy + by), (cx + int(bx * 1.9), cy + int(by * 1.9) - int(.22 * n * abs(math.cos(ang))))], IDX_B)
    c.ell(cx - 2, cy - 2, cx + 2, cy + 2, IDX_G)


def g_crescent(c, n):
    c.ell(int(.06 * n), int(.06 * n), int(.94 * n), int(.94 * n), IDX_M)
    c.ell(int(.26 * n), int(.02 * n), int(1.14 * n), int(.90 * n), IDX_T)
    c.ell(int(.44 * n), int(.34 * n), int(.56 * n), int(.46 * n), IDX_B)


def g_coin(c, n):
    c.ell(int(.08 * n), int(.08 * n), int(.92 * n), int(.92 * n), IDX_B)
    c.ell(int(.20 * n), int(.20 * n), int(.80 * n), int(.80 * n), IDX_M)
    c.rect(int(.42 * n), int(.26 * n), int(.58 * n), int(.74 * n), IDX_B)


def g_eye(c, n):
    c.poly(scale_pts([(.04, .5), (.5, .18), (.96, .5), (.5, .82)], n), IDX_M)
    c.ell(int(.38 * n), int(.38 * n), int(.62 * n), int(.62 * n), IDX_B)
    c.px(int(.5 * n), int(.5 * n), IDX_G)


def g_fist(c, n):
    c.rect(int(.12 * n), int(.34 * n), int(.88 * n), int(.82 * n), IDX_M)
    for i in range(4):
        c.rect(int((.16 + i * .18) * n), int(.20 * n), int((.30 + i * .18) * n), int(.40 * n), IDX_B)
    c.rect(int(.12 * n), int(.70 * n), int(.88 * n), int(.82 * n), IDX_D)


def g_plate(c, n):
    c.poly(scale_pts([(.5, .04), (.9, .2), (.9, .72), (.5, .96), (.1, .72), (.1, .2)], n), IDX_M)
    c.hline(int(.42 * n), int(.22 * n), int(.78 * n), IDX_D)
    c.vline(int(.5 * n), int(.24 * n), int(.72 * n), IDX_D)


def g_up(c, n):
    c.poly(scale_pts([(.5, .06), (.86, .50), (.64, .50), (.64, .94), (.36, .94), (.36, .50), (.14, .50)], n), IDX_B)


def g_chev(c, n):
    c.poly(scale_pts([(.22, .10), (.5, .38), (.78, .10), (.78, .34), (.5, .62), (.22, .34)], n), IDX_B)
    c.poly(scale_pts([(.22, .46), (.5, .74), (.78, .46), (.78, .70), (.5, .98), (.22, .70)], n), IDX_G)


def g_cross(c, n):
    c.rect(int(.36 * n), int(.10 * n), int(.64 * n), int(.90 * n), IDX_B)
    c.rect(int(.10 * n), int(.36 * n), int(.90 * n), int(.64 * n), IDX_B)


def g_spiral(c, n):
    import math
    pts = []
    for i in range(46):
        t = i / 45.0
        ang = t * 3.4 * math.pi
        r = t * .46
        pts.append((.5 + r * math.cos(ang), .5 + r * math.sin(ang)))
    c.line(scale_pts(pts, n), IDX_B, w=max(1, n // 12))


def g_thorn(c, n):
    import math
    c.ell(int(.26 * n), int(.26 * n), int(.74 * n), int(.74 * n), IDX_M)
    for k in range(8):
        ang = k * math.pi / 4
        c.line([(int(.5 * n + .28 * n * math.cos(ang)), int(.5 * n + .28 * n * math.sin(ang))),
                (int(.5 * n + .50 * n * math.cos(ang)), int(.5 * n + .50 * n * math.sin(ang)))], IDX_B)
    c.ell(int(.44 * n), int(.44 * n), int(.56 * n), int(.56 * n), IDX_G)


def g_magnet(c, n):
    c.ell(int(.12 * n), int(.10 * n), int(.88 * n), int(.90 * n), IDX_M)
    c.rect(int(.30 * n), int(.34 * n), int(.70 * n), int(.96 * n), IDX_T)
    c.rect(int(.12 * n), int(.76 * n), int(.30 * n), int(.94 * n), IDX_B)
    c.rect(int(.70 * n), int(.76 * n), int(.88 * n), int(.94 * n), IDX_B)


def g_book(c, n):
    c.rect(int(.08 * n), int(.18 * n), int(.92 * n), int(.86 * n), IDX_M)
    c.hline(int(.40 * n), int(.18 * n), int(.82 * n), IDX_D)
    c.hline(int(.58 * n), int(.18 * n), int(.82 * n), IDX_D)
    c.rect(int(.44 * n), int(.18 * n), int(.56 * n), int(.86 * n), IDX_D)


def g_hourglass(c, n):
    c.poly(scale_pts([(.16, .08), (.84, .08), (.52, .50), (.84, .92), (.16, .92), (.48, .50)], n), IDX_M)
    c.poly(scale_pts([(.34, .48), (.66, .48), (.52, .60)], n), IDX_B)


def g_wing(c, n):
    c.poly(scale_pts([(.5, .50), (.14, .16), (.20, .52), (.10, .56), (.30, .74), (.5, .84)], n), IDX_M)
    c.poly(scale_pts([(.5, .50), (.86, .16), (.80, .52), (.90, .56), (.70, .74), (.5, .84)], n), IDX_B)


def g_gem(c, n):
    c.poly(scale_pts([(.5, .04), (.92, .38), (.5, .96), (.08, .38)], n), IDX_B)
    c.poly(scale_pts([(.5, .18), (.74, .40), (.5, .74), (.26, .40)], n), IDX_G)


def g_ring(c, n):
    c.ell(int(.08 * n), int(.08 * n), int(.92 * n), int(.92 * n), IDX_M)
    c.ell(int(.30 * n), int(.30 * n), int(.70 * n), int(.70 * n), IDX_T)
    c.ell(int(.08 * n), int(.08 * n), int(.92 * n), int(.92 * n), IDX_M)
    c.ell(int(.26 * n), int(.26 * n), int(.74 * n), int(.74 * n), IDX_T)


def g_broken(c, n):
    c.poly(scale_pts([(.5, .04), (.88, .2), (.8, .64), (.5, .94), (.2, .64), (.12, .2)], n), IDX_M)
    c.line(scale_pts([(.34, .12), (.62, .40), (.40, .56), (.66, .86)], n), IDX_T, w=max(2, n // 12))


def g_banner(c, n):
    c.vline(int(.24 * n), int(.08 * n), int(.94 * n), IDX_M)
    c.poly(scale_pts([(.28, .10), (.92, .22), (.28, .48)], n), IDX_B)


def g_skull(c, n):
    c.ell(int(.16 * n), int(.08 * n), int(.84 * n), int(.66 * n), IDX_M)
    c.rect(int(.34 * n), int(.60 * n), int(.66 * n), int(.80 * n), IDX_M)
    c.rect(int(.28 * n), int(.30 * n), int(.44 * n), int(.46 * n), IDX_T)
    c.rect(int(.56 * n), int(.30 * n), int(.72 * n), int(.46 * n), IDX_T)
    c.px(int(.5 * n), int(.52 * n), IDX_D)


def g_fang(c, n):
    c.poly(scale_pts([(.5, .06), (.88, .34), (.5, .96), (.12, .34)], n), IDX_M)
    c.poly(scale_pts([(.5, .26), (.72, .42), (.5, .82), (.28, .42)], n), IDX_T)


def g_diamond(c, n):
    c.poly(scale_pts([(.5, .04), (.94, .5), (.5, .96), (.06, .5)], n), IDX_M)
    c.poly(scale_pts([(.5, .26), (.72, .5), (.5, .74), (.28, .5)], n), IDX_B)


def g_dotring(c, n):
    c.ell(int(.10 * n), int(.10 * n), int(.90 * n), int(.90 * n), IDX_D)
    c.ell(int(.34 * n), int(.34 * n), int(.66 * n), int(.66 * n), IDX_B)
    c.ell(int(.44 * n), int(.44 * n), int(.56 * n), int(.56 * n), IDX_G)


PRIMS = {
    "sword": g_sword, "shield": g_shield, "boot": g_boot, "heart": g_heart, "drop": g_drop,
    "star": g_star, "clock": g_clock, "bolt": g_bolt, "flame": g_flame, "snow": g_snow,
    "crescent": g_crescent, "coin": g_coin, "eye": g_eye, "fist": g_fist, "plate": g_plate,
    "up": g_up, "chev": g_chev, "cross": g_cross, "spiral": g_spiral, "thorn": g_thorn,
    "magnet": g_magnet, "book": g_book, "hourglass": g_hourglass, "wing": g_wing,
    "gem": g_gem, "ring": g_ring, "broken": g_broken, "banner": g_banner, "skull": g_skull,
    "fang": g_fang, "diamond": g_diamond, "dotring": g_dotring,
}


# ============================ 映射表 ============================
# 詞綴：stat_key -> (基元, 色系)。色系按「檔案」分組，讓玩家能靠顏色辨類。
AFFIX_MAP = {
    # attack.json（進攻）→ 血紅 / 金
    "flat_attack": ("sword", "blood"), "pct_attack": ("sword", "blood"),
    "crit_chance": ("star", "gold"), "crit_damage": ("star", "mythic"),
    "attack_speed": ("bolt", "gold"), "elemental_damage": ("gem", "void"),
    "armor_penetration": ("broken", "blood"), "magic_find": ("eye", "void"),
    "elemental_penetration": ("broken", "void"), "resist_penetration": ("broken", "ice"),
    "all_element_damage": ("gem", "gold"), "damage_vs_ailment": ("fang", "poison"),
    # defense.json（防禦）→ 冰藍 / 青
    "flat_hp": ("heart", "blood"), "pct_hp": ("heart", "blood"),
    "flat_armor": ("plate", "ice"), "pct_armor": ("plate", "ice"),
    "dodge": ("wing", "ice"), "block_chance": ("shield", "ice"),
    "thorns": ("thorn", "ice"), "life_regen": ("cross", "teal"),
    "fire_resist": ("flame", "blood"), "cold_resist": ("snow", "ice"),
    "lightning_resist": ("bolt", "gold"), "poison_resist": ("drop", "poison"),
    "shadow_resist": ("crescent", "void"), "physical_resist": ("shield", "ice"),
    "all_resist": ("shield", "teal"),
    # resource.json（資源）→ 青綠
    "max_resource": ("drop", "teal"), "resource_regen": ("drop", "teal"),
    "cooldown_reduction": ("clock", "teal"), "skill_cost_reduction": ("clock", "ice"),
    "pickup_radius": ("magnet", "teal"), "gold_gain": ("coin", "gold"),
    "xp_gain": ("banner", "teal"), "move_speed": ("boot", "teal"),
    "life_on_hit": ("drop", "blood"), "kill_heal": ("cross", "blood"),
    # special.json（特殊 / 異常）→ 毒綠 / 紫
    "skill_level": ("book", "gold"), "all_attributes": ("gem", "teal"),
    "echo_strike": ("spiral", "void"),
    "burn_damage": ("flame", "blood"), "chill_damage": ("snow", "ice"),
    "poison_damage": ("drop", "poison"), "shock_damage": ("bolt", "gold"),
    "curse_damage": ("skull", "void"),
    "ailment_duration": ("hourglass", "poison"), "ailment_chance": ("dotring", "poison"),
    "ailment_effect": ("fang", "mythic"),
}

ELEMENTS = [
    ("physical", "箭頭/盾", "plate", "ice"),
    ("fire", "火", "flame", "blood"),
    ("cold", "冰", "snow", "ice"),
    ("lightning", "雷", "bolt", "gold"),
    ("poison", "毒", "drop", "poison"),
    ("shadow", "暗影", "crescent", "void"),
]
RESISTS = [e for e in ELEMENTS if e[0] != "physical"]


def render(prim, series, size):
    c = Idx(size)
    PRIMS[prim](c, size)
    return compose(c.outline(), series)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    made = 0
    print("=== E1 詞綴圖標（32×32）===")
    missing = []
    for key, (prim, series) in sorted(AFFIX_MAP.items()):
        img = render(prim, series, 32)
        p = os.path.join(OUTDIR, "affix_%s_32.png" % key)
        img.save(p)
        made += 1
    print("  產出 %d 張（映射表 %d 條）" % (made, len(AFFIX_MAP)))

    print("=== F1 元素屬性圖標（24×24）===")
    for key, cn, prim, series in ELEMENTS:
        render(prim, series, 24).save(os.path.join(OUTDIR, "elem_%s_24.png" % key))
        print("  elem_%-10s %s" % (key, cn))
        made += 1

    print("=== F2 元素抗性圖標（24×24）===")
    for key, cn, prim, series in RESISTS:
        # 抗性版 = 基元縮小 + 外框（盾環），以示區別
        c = Idx(24)
        c.ell(1, 1, 22, 22, IDX_D)
        c.ell(3, 3, 20, 20, IDX_T)
        inner = Idx(13)
        PRIMS[prim](inner, 13)
        ia = inner.outline()
        rgba = np.array(compose(ia, series))
        big = Image.fromarray(rgba, "RGBA").resize((16, 16), Image.NEAREST)
        base = Image.fromarray(np.array(compose(c.outline(), series)), "RGBA")
        base.alpha_composite(big, (4, 4))
        base.save(os.path.join(OUTDIR, "resist_%s_24.png" % key))
        print("  resist_%-10s %s" % (key, cn))
        made += 1

    print("\n合計 %d 張 -> %s" % (made, OUTDIR))
    # 覆蓋率檢查
    allkeys = set()
    for f in ["attack.json", "defense.json", "resource.json", "special.json"]:
        d = json.load(open(os.path.join(GAME, "data/affixes", f), encoding="utf-8"))
        for a in d:
            if isinstance(a, dict) and "stat_key" in a:
                allkeys.add(a["stat_key"])
    plan_f = os.path.join(PLAN, "02-affixes.json")
    for a in json.load(open(plan_f, encoding="utf-8"))["affixes"]:
        allkeys.add(a["stat_key"])
    miss = sorted(allkeys - set(AFFIX_MAP))
    print("遊戲+策劃案 stat_key 共 %d 條；未映射 %d 條 %s" % (len(allkeys), len(miss), miss if miss else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
