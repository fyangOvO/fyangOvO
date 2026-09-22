# -*- coding: utf-8 -*-
"""
七傳說 · 地磚 v2 生成器 (staging only)
========================================
目的：在 v1（192x96, ground6/wall3/obstacle3，材質層次缺失）基礎上，
      產出 v2（256x128, ground8/wall6/obstacle4），核心是讓 ground 變體之間
      有「可量測的明度/色相層次」（3 個明度層 x 2-3 種地表特徵）。

硬約束（見 team-lead TASK-TILE-V2）：
  - atlas 256x128（8x4, tile_size=32）；schema 沿用 {"tile_size","tiles":{ground/wall/obstacle:[[x,y]..]}}
  - ground>=8, wall>=6, obstacle>=4
  - 各 ground 變體均色「通道離散」>=6；>=3 個變體明度差>=8；wall 離散>=6、>=2 明度層
  - ground 不透明均色維持 v1 量級 ±15（forest~(75,91,57) / frost~(111,136,167) / volcanic~(81,70,64)），不得退回近黑
  - 16-bit 像素風；有限色板（盡量落 PALETTE_ALL，額外色記錄於報告）
  - 可無縫平鋪（toroidal，左右/上下邊界可接）；alpha 二值
  - obstacle 保留透明像素

僅寫入 deliverables/tileset-v2-2026-09-22/，不碰 game/。
"""
import json
import math
import os
from PIL import Image

ROOT = r"D:\七傳說"
OUT_DIR = os.path.join(ROOT, "deliverables", "tileset-v2-2026-09-22")
PREVIEW_DIR = os.path.join(ROOT, "deliverables", "gstack")
TS = 32
ATLAS_COLS = 8
ATLAS_ROWS = 4
ATLAS_W = ATLAS_COLS * TS   # 256
ATLAS_H = ATLAS_ROWS * TS   # 128

# ---------------------------------------------------------------------------
# PALETTE_ALL（game_constants.gd 八·五）—— 44 已定義色，供合規統計
# ---------------------------------------------------------------------------
PALETTE_HEX = [
    "0B0D10", "14171C", "1E232B", "2A313B", "3A424F", "4E5866",
    "6B7688", "8C97A8", "B3BCC9", "DCE2E8", "DBCC85",
    "4A0E12", "8C1A1F", "C42B2B", "E8573F",
    "0F2417", "1E4A2B", "3B7A44", "6FB35C",
    "101A3A", "1F3468", "3A5FB0", "6E9BE8",
    "4A3208", "8C6510", "D9A521", "F5D77A",
    "2A1440", "4E2478", "7E44B8", "B07DE0",
    "4A0816", "B01038", "FF2D55", "FF7A96",
    "0A2B22", "1B6B52", "2FA37A", "6FE0B4",
    "C9D1D9", "4C8BF5", "F5C542", "A96BFF", "FF8A2B",
]


def hex2rgb(h):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


PALETTE_RGB = set(hex2rgb(h) for h in PALETTE_HEX)

# ---------------------------------------------------------------------------
# 地形 ramp：每 biome 3 個明度層（dark/mid/light）。
# 這 3 色是 44 色 UI 色板所缺的「中明度低飽和地表色」——為達成 ±15 亮度帶 + 明度層次
# 而新增，將在報告中逐色列出。（mid 對齊 v1 實測均色）
# ---------------------------------------------------------------------------
GROUND_RAMP = {
    "forest":   {"dark": (48, 66, 40),   "mid": (76, 92, 58),   "light": (108, 128, 78)},
    "frost":    {"dark": (84, 108, 138), "mid": (112, 137, 167),"light": (148, 172, 200)},
    "volcanic": {"dark": (56, 48, 44),   "mid": (81, 71, 65),   "light": (112, 98, 88)},
}
# 牆體 ramp：2 明度層（dark/mid），比地面更暗、去飽和（石/岩）
WALL_RAMP = {
    "forest":   {"dark": (38, 48, 32),   "mid": (52, 64, 44)},
    "frost":    {"dark": (66, 86, 112),  "mid": (88, 110, 136)},
    "volcanic": {"dark": (44, 40, 38),   "mid": (60, 54, 48)},
}

# 色板常用色（obstacle 大量復用）
P = {h: hex2rgb(h) for h in PALETTE_HEX}


# ---------------------------------------------------------------------------
# 確定性雜湊 / toroidal 值雜訊（period 整除 32 ⇒ 真正可無縫）
# ---------------------------------------------------------------------------
def h2(x, y, seed):
    n = (int(x) * 374761393 + int(y) * 668265263 + int(seed) * 1442695040) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n ^= (n >> 16)
    return (n & 0xFFFFFF) / float(0x1000000)


def vnoise(x, y, period, seed):
    P_ = period
    gx = x / 32.0 * P_
    gy = y / 32.0 * P_
    x0 = int(math.floor(gx)); y0 = int(math.floor(gy))
    fx = gx - x0; fy = gy - y0
    sx = fx * fx * (3 - 2 * fx); sy = fy * fy * (3 - 2 * fy)

    def val(i, j):
        return h2(i % P_, j % P_, seed)

    v00 = val(x0, y0); v10 = val(x0 + 1, y0)
    v01 = val(x0, y0 + 1); v11 = val(x0 + 1, y0 + 1)
    a = v00 + (v10 - v00) * sx
    b = v01 + (v11 - v01) * sx
    return a + (b - a) * sy


def lerp(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(3))


def new_tile():
    return [[(0, 0, 0, 0) for _ in range(32)] for _ in range(32)]


def setp(px, x, y, c, a=255):
    px[y % 32][x % 32] = (c[0], c[1], c[2], a)


# ---------------------------------------------------------------------------
# ground tile
# ---------------------------------------------------------------------------
def build_ground(biome, layer, feature, seed):
    R = GROUND_RAMP[biome]
    base = R[layer]
    dark = R["dark"]; light = R["light"]
    px = new_tile()
    for y in range(32):
        for x in range(32):
            n_hi = vnoise(x, y, 8, seed)
            n_lo = vnoise(x, y, 3, seed + 101)
            t = (n_hi - 0.5) * 0.55 + (n_lo - 0.5) * 0.75   # -0.65..0.65
            if t >= 0:
                c = lerp(base, light, min(1.0, t / 0.55) * 0.5)
            else:
                c = lerp(base, dark, min(1.0, -t / 0.55) * 0.5)
            px[y][x] = (c[0], c[1], c[2], 255)

    # 地表特徵（用 ramp 內其他成員當斑點，維持 3 色 ramp）
    speck_light = light if layer != "light" else base
    speck_dark = dark if layer != "dark" else base

    if feature == "pebble":
        # 散落 2x2 碎石（在暗層用亮斑、在亮層用暗斑）
        col = speck_light if layer == "dark" else speck_dark
        for i in range(18):
            rx = int(h2(i, 0, seed + 7) * 32)
            ry = int(h2(i, 1, seed + 7) * 32)
            s = 2 if h2(i, 2, seed + 7) > 0.4 else 1
            for dy in range(s):
                for dx in range(s):
                    if h2(i * 5 + dx, dy, seed + 9) > 0.15:
                        setp(px, rx + dx, ry + dy, col)
    elif feature == "patch":
        # 大片亮色土斑（低頻塊面）
        for y in range(32):
            for x in range(32):
                if vnoise(x, y, 2, seed + 55) > 0.72:
                    c = px[y][x]
                    px[y][x] = (lerp(c[:3], light, 0.55) + (255,))
    elif feature == "crack":
        # 2 條 1px 暗裂縫（水平/對角，wrap）
        for i in range(2):
            y0 = int(h2(i, 0, seed + 31) * 32)
            amp = 2 + int(h2(i, 1, seed + 31) * 3)
            for x in range(32):
                y = (y0 + int(amp * math.sin(x / 32.0 * 2 * math.pi * (1 + i))))
                yy = y % 32
                c = px[yy][x]
                px[yy][x] = (lerp(c[:3], dark, 0.62) + (255,))
    # else plain：只靠雜訊
    return px


# ---------------------------------------------------------------------------
# wall tile
# ---------------------------------------------------------------------------
def build_wall(biome, layer, feature, seed):
    R = WALL_RAMP[biome]
    base = R[layer]; dark = R["dark"]; mid = R["mid"]
    light = tuple(min(255, int(v * 1.28 + 14)) for v in base)  # 每層自身的高光
    px = new_tile()
    bh = 8
    for y in range(32):
        for x in range(32):
            n = vnoise(x, y, 6, seed)
            t = (n - 0.5) * 0.6
            c = lerp(base, light, t * 1.1) if t >= 0 else lerp(base, dark, -t * 1.1)
            row = y // bh
            off = (row % 2) * 8
            if (y % bh == 0) or (((x + off) % 16) == 0):
                c = lerp(c, dark, 0.72)          # 灰漿縫
            elif (y % bh == 1):
                c = lerp(c, light, 0.30)         # 縫下高光（2.5D bevel）
            px[y][x] = (c[0], c[1], c[2], 255)

    if feature == "moss":
        col = GROUND_RAMP[biome]["mid"] if biome != "forest" else GROUND_RAMP["forest"]["mid"]
        for i in range(26):
            rx = int(h2(i, 0, seed + 61) * 32)
            ry = int(h2(i, 3, seed + 61) * 32)
            if h2(i, 1, seed + 62) > 0.35:
                setp(px, rx, ry, col)
                if h2(i, 2, seed + 63) > 0.5:
                    setp(px, rx + 1, ry, col)
    elif feature == "crack":
        for i in range(3):
            x0 = int(h2(i, 0, seed + 41) * 32)
            for y in range(32):
                x = (x0 + int(2.5 * math.sin(y / 32.0 * 2 * math.pi * (1 + i)))) % 32
                c = px[y][x]
                px[y][x] = (lerp(c[:3], dark, 0.75) + (255,))
    return px


# ---------------------------------------------------------------------------
# obstacle tiles（props；保留透明像素）
# ---------------------------------------------------------------------------
def ellipse(cx, cy, rx, ry):
    pts = set()
    for y in range(32):
        for x in range(32):
            if ((x - cx) / float(rx)) ** 2 + ((y - cy) / float(ry)) ** 2 <= 1.0:
                pts.add((x, y))
    return pts


def rect(x0, y0, x1, y1):
    return set((x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1))


def tri(x0, ymid, x1, ybase, apex_y):
    pts = set()
    for y in range(apex_y, ybase + 1):
        f = (y - apex_y) / float(max(1, ybase - apex_y))
        xl = int(round(x0 + (x0 - x0) * f))
        half = int(round((x1 - x0) / 2.0 * f))
        cx = (x0 + x1) // 2
        for x in range(cx - half, cx + half + 1):
            pts.add((x, y))
    return pts


def fill(px, pts, col, a=255):
    for (x, y) in pts:
        if 0 <= x < 32 and 0 <= y < 32:
            px[y][x] = (col[0], col[1], col[2], a)


def outline(px, pts, col):
    for (x, y) in pts:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < 32 and 0 <= ny < 32 and px[ny][nx][3] == 0:
                px[ny][nx] = (col[0], col[1], col[2], 255)


def build_obstacle(biome, idx):
    px = new_tile()
    R = GROUND_RAMP[biome]
    if biome == "forest":
        wood_d = P["4A3208"]; wood_m = P["8C6510"]; wood_l = P["D9A521"]
        green_m = R["mid"]; green_l = R["light"]; green_d = R["dark"]
        rock_d = R["dark"]; rock_m = R["mid"]
        if idx == 0:      # 樹樁
            t = rect(12, 15, 19, 28); fill(px, t, wood_d)
            fill(px, ellipse(15, 15, 6, 3), wood_m)
            fill(px, ellipse(15, 15, 3, 1), wood_l)
            fill(px, ellipse(15, 28, 6, 2), green_d)
            outline(px, t | ellipse(15, 15, 6, 3) | ellipse(15, 28, 6, 2), (24, 32, 20))
        elif idx == 1:    # 灌木
            b = ellipse(16, 19, 9, 8) | ellipse(11, 17, 5, 5) | ellipse(21, 17, 5, 5)
            fill(px, b, green_m)
            fill(px, ellipse(13, 16, 3, 3) | ellipse(20, 16, 2, 2), green_l)
            outline(px, b, green_d)
        elif idx == 2:    # 岩石
            b = ellipse(16, 20, 10, 7) | ellipse(12, 17, 6, 5)
            fill(px, b, rock_d)
            fill(px, ellipse(13, 17, 3, 2), rock_m)
            outline(px, b, (30, 40, 26))
        else:             # 倒木
            t = rect(6, 17, 26, 22)
            fill(px, t, wood_d)
            fill(px, ellipse(26, 19, 2, 3), wood_m)
            fill(px, rect(8, 18, 24, 19), wood_m)
            outline(px, t | ellipse(26, 19, 2, 3), (30, 20, 4))
    elif biome == "frost":
        ice_m = R["mid"]; ice_l = R["light"]; ice_d = R["dark"]
        blue = P["6E9BE8"]; blue_d = P["3A5FB0"]; white = P["DCE2E8"]; gray = P["8C97A8"]
        if idx == 0:      # 冰晶
            b = tri(11, 21, 21, 28, 4) | rect(14, 20, 17, 28)
            fill(px, b, ice_l)
            fill(px, rect(15, 8, 16, 27), white)
            fill(px, rect(12, 22, 13, 27), blue)
            outline(px, b, blue_d)
        elif idx == 1:    # 雪岩
            b = ellipse(16, 21, 10, 7)
            fill(px, b, gray)
            fill(px, ellipse(14, 17, 7, 3), white)
            outline(px, b, ice_d)
        elif idx == 2:    # 凍灌木
            b = ellipse(16, 20, 9, 7) | ellipse(11, 18, 5, 5) | ellipse(21, 18, 5, 5)
            fill(px, b, ice_m)
            fill(px, ellipse(13, 17, 3, 2) | ellipse(20, 17, 2, 2), white)
            outline(px, b, blue_d)
        else:             # 冰塊
            b = rect(9, 12, 23, 28)
            fill(px, b, ice_l)
            fill(px, rect(9, 12, 23, 13), white)
            fill(px, rect(9, 27, 23, 28), ice_d)
            for y in range(14, 27, 4):
                fill(px, rect(11, y, 21, y), blue)
            outline(px, b, blue_d)
    else:  # volcanic
        rock_d = P["2A313B"]; rock_m = P["4E5866"]; rock_l = P["6B7688"]
        brown_d = P["4A3208"]; brown_m = P["8C6510"]; gold = P["D9A521"]
        ember = P["E8573F"]; ember_d = P["8C1A1F"]; near_black = P["14171C"]
        ash_m = P["8C97A8"]
        if idx == 0:      # 熔岩岩
            b = ellipse(16, 20, 10, 7) | ellipse(12, 17, 6, 5)
            fill(px, b, brown_d)
            fill(px, ellipse(13, 17, 3, 2), brown_m)
            for (x, y) in [(11, 22), (19, 20), (15, 24), (22, 23)]:
                fill(px, rect(x, y, x + 1, y), ember)
                fill(px, rect(x, y + 1, x, y + 1), ember_d)
            outline(px, b, (20, 12, 6))
        elif idx == 1:    # 黑曜石
            b = tri(9, 22, 23, 29, 6) | rect(12, 22, 20, 29)
            fill(px, b, near_black)
            fill(px, rect(15, 10, 16, 28), rock_m)
            fill(px, rect(12, 23, 13, 28), rock_l)
            outline(px, b, (8, 9, 12))
        elif idx == 2:    # 餘燼石
            b = ellipse(16, 20, 10, 7)
            fill(px, b, rock_m)
            fill(px, ellipse(14, 17, 5, 2), rock_l)
            for (x, y) in [(12, 21), (20, 22), (16, 24), (24, 20)]:
                fill(px, rect(x, y, x + 1, y), gold)
            outline(px, b, rock_d)
        else:             # 灰燼堆
            b = ellipse(16, 22, 11, 6) | ellipse(16, 18, 7, 5)
            fill(px, b, ash_m)
            fill(px, ellipse(14, 18, 4, 3), rock_l)
            for i in range(10):
                rx = 8 + int(h2(i, 0, 777) * 16)
                ry = 16 + int(h2(i, 1, 777) * 10)
                setp(px, rx, ry, rock_d)
            outline(px, b, rock_d)
    return px


# ---------------------------------------------------------------------------
# 組裝
# ---------------------------------------------------------------------------
GROUND_PLAN = [
    ("dark", "plain"), ("dark", "pebble"),
    ("mid", "plain"), ("mid", "pebble"), ("mid", "patch"),
    ("light", "plain"), ("light", "pebble"), ("light", "crack"),
]
WALL_PLAN = [
    ("dark", "plain"), ("dark", "moss"), ("dark", "crack"),
    ("mid", "plain"), ("mid", "moss"), ("mid", "crack"),
]


def paste(atlas, tile, cx, cy):
    for y in range(32):
        for x in range(32):
            atlas[cy * TS + y][cx * TS + x] = tile[y][x]


def gen_biome(biome):
    atlas = [[(0, 0, 0, 0) for _ in range(ATLAS_W)] for _ in range(ATLAS_H)]
    tiles = {"ground": [], "wall": [], "obstacle": []}
    seed0 = {"forest": 1000, "frost": 2000, "volcanic": 3000}[biome]

    for i, (layer, feat) in enumerate(GROUND_PLAN):
        tile = build_ground(biome, layer, feat, seed0 + i * 17)
        paste(atlas, tile, i, 0)
        tiles["ground"].append([i, 0])
    for i, (layer, feat) in enumerate(WALL_PLAN):
        tile = build_wall(biome, layer, feat, seed0 + 500 + i * 23)
        paste(atlas, tile, i, 1)
        tiles["wall"].append([i, 1])
    for i in range(4):
        tile = build_obstacle(biome, i)
        paste(atlas, tile, i, 2)
        tiles["obstacle"].append([i, 2])

    img = Image.new("RGBA", (ATLAS_W, ATLAS_H))
    img.putdata([p for row in atlas for p in row])
    out = os.path.join(OUT_DIR, biome)
    os.makedirs(out, exist_ok=True)
    img.save(os.path.join(out, "atlas.png"))
    with open(os.path.join(out, "atlas.json"), "w", encoding="utf-8") as f:
        json.dump({"tile_size": TS, "tiles": tiles}, f, ensure_ascii=False, indent=1)
    return img, tiles


# ---------------------------------------------------------------------------
# 自檢：逐變體均色 + 通道離散 + 亮度
# ---------------------------------------------------------------------------
def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def measure(img, tiles):
    res = {}
    for kind in ("ground", "wall", "obstacle"):
        means = []
        for (cx, cy) in tiles[kind]:
            px = img.crop((cx * TS, cy * TS, cx * TS + TS, cy * TS + TS)).getdata()
            op = [p for p in px if p[3] > 0]
            if op:
                m = tuple(sum(p[i] for p in op) / float(len(op)) for i in range(3))
            else:
                m = (0.0, 0.0, 0.0)
            means.append(m)
        disp = [max(m[i] for m in means) - min(m[i] for m in means) for i in range(3)]
        lums = [lum(m) for m in means]
        res[kind] = {
            "n": len(means),
            "means": [tuple(round(v, 1) for v in m) for m in means],
            "disp": [round(d, 1) for d in disp],
            "lum_disp": round(max(lums) - min(lums), 1),
            "lum_layers_ge8": sum(1 for i in range(len(lums)) for j in range(i + 1, len(lums)) if abs(lums[i] - lums[j]) >= 8),
        }
        if kind == "ground":
            n = len(means)
            res["ground"]["overall_mean"] = tuple(round(sum(m[i] for m in means) / n, 1) for i in range(3))
    return res


def palette_stats(img, tiles):
    from collections import Counter
    c = Counter()
    for kind in ("ground", "wall", "obstacle"):
        for (cx, cy) in tiles[kind]:
            c.update(img.crop((cx * TS, cy * TS, cx * TS + TS, cy * TS + TS)).getdata())
    total_op = sum(v for k, v in c.items() if k[3] > 0)
    inpal = sum(v for k, v in c.items() if k[3] > 0 and (k[0], k[1], k[2]) in PALETTE_RGB)
    uniq = sorted(set((k[0], k[1], k[2]) for k in c if k[3] > 0))
    off = [u for u in uniq if u not in PALETTE_RGB]
    return {
        "opaque_px": total_op,
        "in_palette_px": inpal,
        "in_palette_pct": round(100.0 * inpal / max(1, total_op), 2),
        "unique_colors": len(uniq),
        "off_palette_unique": len(off),
    }


# ---------------------------------------------------------------------------
# 預覽：8x4 地面輪播 + 牆體帶，3x NEAREST
# ---------------------------------------------------------------------------
def make_preview(biome, img, tiles):
    SCALE = 3
    gw, gh = 8, 4
    wallh = 2
    pad = 6
    W = gw * TS
    H = gh * TS + pad + wallh * TS
    canvas = Image.new("RGBA", (W, H), (11, 13, 16, 255))
    gts = tiles["ground"]; wts = tiles["wall"]
    for r in range(gh):
        for c in range(gw):
            (cx, cy) = gts[(c + r) % len(gts)]
            canvas.paste(img.crop((cx * TS, cy * TS, cx * TS + TS, cy * TS + TS)), (c * TS, r * TS))
    y0 = gh * TS + pad
    for c in range(gw):
        (cx, cy) = wts[c % len(wts)]
        canvas.paste(img.crop((cx * TS, cy * TS, cx * TS + TS, cy * TS + TS)), (c * TS, y0))
        (cx, cy) = wts[(c + 3) % len(wts)]
        canvas.paste(img.crop((cx * TS, cy * TS, cx * TS + TS, cy * TS + TS)), (c * TS, y0 + TS))
    canvas = canvas.resize((W * SCALE, H * SCALE), Image.NEAREST)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    p = os.path.join(PREVIEW_DIR, "tileset-v2-preview-%s.png" % biome)
    canvas.save(p)
    return p


def main():
    report = {}
    for biome in ("forest", "frost", "volcanic"):
        img, tiles = gen_biome(biome)
        m = measure(img, tiles)
        ps = palette_stats(img, tiles)
        pv = make_preview(biome, img, tiles)
        report[biome] = {"measure": m, "palette": ps, "preview": pv,
                         "counts": {k: len(v) for k, v in tiles.items()}}
    print(json.dumps(report, ensure_ascii=False, indent=1))
    with open(os.path.join(OUT_DIR, "_selfcheck.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
