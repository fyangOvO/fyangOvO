#!/usr/bin/env python3
"""ui_screen_probe.py — deterministic pixel forensics for UI screenshots.

Purpose
-------
Measure, from a *rendered* screenshot (not from code coordinates), where each
UI element actually landed, whether elements overlap, how much of the screen a
tile class covers, and what the contrast of key colours is. Output is stable
and byte-comparable across runs (no timestamps, no randomness, fixed rounding)
so the same screenshot name can be re-probed after a fix and diffed.

Usage
-----
  python game/tools/ui_screen_probe.py <png> [--mode cover|level1|generic]
                                             [--atlas <atlas.json>]
                                             [--tileset-png <atlas.png>]
                                             [--json <out.json>]

Notes
-----
* All colour tests are `abs(channel - target) <= tol` in 8-bit space.
* "other" pixels = pixels that belong to neither the UI palette nor the
  background-art palette; used to isolate baked sprites (hero / weapons).
* Contrast uses the WCAG 2.x relative-luminance formula.
"""
import argparse
import json
import os
import sys
from collections import Counter, deque

from PIL import Image

Image.MAX_IMAGE_PIXELS = None

# ---------------------------------------------------------------- palette ---
# game/scripts/core/game_constants.gd :: PALETTE_ALL (44 colours)
PALETTE_ALL = [
    "0B0D10", "14171C", "1E232B", "2A313B", "3A424F", "4E5866", "6B7688",
    "8C97A8", "B3BCC9", "DCE2E8", "DBCC85",
    "4A0E12", "8C1A1F", "C42B2B", "E8573F",
    "0F2417", "1E4A2B", "3B7A44", "6FB35C",
    "101A3A", "1F3468", "3A5FB0", "6E9BE8",
    "4A3208", "8C6510", "D9A521", "F5D77A",
    "2A1440", "4E2478", "7E44B8", "B07DE0",
    "4A0816", "B01038", "FF2D55", "FF7A96",
    "0A2B22", "1B6B52", "2FA37A", "6FE0B4",
    "C9D1D9", "4C8BF5", "F5C542", "A96BFF", "FF8A2B",
]
PAL_RGB = [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in PALETTE_ALL]

# background-art tones observed on the cover backdrop (mauve/purple painting)
COVER_BG = [
    (0x5B, 0x3B, 0x4E), (0x49, 0x35, 0x49), (0x1D, 0x17, 0x24),
    (0x10, 0x0A, 0x0A), (0x24, 0x1B, 0x24), (0x61, 0x40, 0x4E),
    (0x2D, 0x1D, 0x2C), (0x48, 0x37, 0x4B), (0x27, 0x18, 0x16),
    (0x25, 0x1C, 0x25), (0x22, 0x19, 0x22), (0x20, 0x17, 0x20),
    (0x21, 0x18, 0x21), (0x0A, 0x0A, 0x0A), (0x00, 0x00, 0x00),
    (0x85, 0x82, 0x79), (0x35, 0x2B, 0x33), (0x2B, 0x22, 0x2B),
]

# UI colours that legitimately appear on the cover chrome
COVER_UI = [
    (0x14, 0x17, 0x1C), (0x1E, 0x23, 0x2B), (0x0B, 0x0D, 0x10),
    (0xD9, 0xA5, 0x21), (0xF5, 0xD7, 0x7A), (0x8C, 0x65, 0x10),
    (0x4A, 0x32, 0x08), (0x3A, 0x42, 0x4F), (0x4E, 0x58, 0x66),
    (0xDC, 0xE2, 0xE8), (0x8C, 0x97, 0xA8), (0xB3, 0xBC, 0xC9),
    (0x2A, 0x31, 0x3B), (0x6B, 0x76, 0x88),
]


# ------------------------------------------------------------- primitives ---
def near(p, t, tol):
    return abs(p[0] - t[0]) <= tol and abs(p[1] - t[1]) <= tol and abs(p[2] - t[2]) <= tol


def near_any(p, targets, tol):
    for t in targets:
        if near(p, t, tol):
            return True
    return False


def mask_from(px, w, h, pred):
    m = [[False] * w for _ in range(h)]
    for y in range(h):
        row = m[y]
        for x in range(w):
            row[x] = pred(px[x, y])
    return m


def components(mask, w, h, min_area=1):
    """4-connected components; returns list of dicts sorted by (-area, y, x)."""
    seen = [[False] * w for _ in range(h)]
    out = []
    for y0 in range(h):
        for x0 in range(w):
            if not mask[y0][x0] or seen[y0][x0]:
                continue
            q = deque([(x0, y0)])
            seen[y0][x0] = True
            n = 0
            minx = maxx = x0
            miny = maxy = y0
            while q:
                x, y = q.popleft()
                n += 1
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and mask[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if n >= min_area:
                out.append({"bbox": [minx, miny, maxx, maxy], "area": n,
                            "w": maxx - minx + 1, "h": maxy - miny + 1,
                            "cx": (minx + maxx) / 2.0, "cy": (miny + maxy) / 2.0})
    out.sort(key=lambda r: (-r["area"], r["bbox"][1], r["bbox"][0]))
    return out


def bbox_of(mask, w, h):
    minx, miny, maxx, maxy, n = w, h, -1, -1, 0
    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                n += 1
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
    if n == 0:
        return None
    return [minx, miny, maxx, maxy, n]


def overlap(a, b):
    if not a or not b:
        return 0
    x0 = max(a[0], b[0]); y0 = max(a[1], b[1])
    x1 = min(a[2], b[2]); y1 = min(a[3], b[3])
    if x1 < x0 or y1 < y0:
        return 0
    return (x1 - x0 + 1) * (y1 - y0 + 1)


def rect(hx, hy, w, h):
    return [hx, hy, hx + w - 1, hy + h - 1]


# ----------------------------------------------------------------- colour ---
def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rel_luminance(rgb):
    r, g, b = (srgb_to_lin(v) for v in rgb[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(c1, c2):
    l1, l2 = rel_luminance(c1), rel_luminance(c2)
    if l1 < l2:
        l1, l2 = l2, l1
    return (l1 + 0.05) / (l2 + 0.05)


def perceptual_luma(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def saturation(rgb):
    mx, mn = max(rgb[:3]), min(rgb[:3])
    return 0.0 if mx == 0 else (mx - mn) / mx


def hexs(c):
    return "#%02X%02X%02X" % (c[0], c[1], c[2])


# ------------------------------------------------------------------ tiles ---
def tile_stats(tileset_png, atlas_json, tile_size):
    im = Image.open(tileset_png).convert("RGBA")
    px = im.load()
    atlas = json.load(open(atlas_json, encoding="utf-8"))
    ts = atlas.get("tile_size", tile_size)
    res = {}
    for cls, cells in atlas.get("tiles", {}).items():
        rows = []
        for cell in cells:
            cx, cy = cell[0], cell[1]
            vals = []
            for y in range(cy * ts, (cy + 1) * ts):
                for x in range(cx * ts, (cx + 1) * ts):
                    p = px[x, y]
                    if p[3] < 8:
                        continue
                    vals.append((perceptual_luma(p), saturation(p)))
            if vals:
                rows.append({
                    "cell": [cx, cy],
                    "luma": sum(v[0] for v in vals) / len(vals),
                    "sat": sum(v[1] for v in vals) / len(vals),
                })
        if rows:
            ls = [r["luma"] for r in rows]
            ss = [r["sat"] for r in rows]
            res[cls] = {
                "tiles": rows,
                "count": len(rows),
                "luma_mean": sum(ls) / len(ls),
                "luma_min": min(ls),
                "luma_max": max(ls),
                "sat_mean": sum(ss) / len(ss),
            }
    return res


# ------------------------------------------------------------------ probes --
def probe_cover(im):
    w, h = im.size
    px = im.load()
    out = {}

    # background-art / UI masks
    bgm = mask_from(px, w, h, lambda p: near_any(p, COVER_BG, 14))
    uim = mask_from(px, w, h, lambda p: near_any(p, COVER_UI, 10))
    other = [[(not bgm[y][x]) and (not uim[y][x]) for x in range(w)] for y in range(h)]

    # --- banner: the big #14171C block in the top band (interior), then grown
    #     by the gold/black border rows above and below it.
    bm = [[near(px[x, y], (0x14, 0x17, 0x1C), 8) and y < 130 for x in range(w)] for y in range(h)]
    bc = components(bm, w, h, min_area=2000)
    banner = None
    if bc:
        b = bc[0]["bbox"]
        # grow upward/downward while a gold border row or dark edge row exists
        x0, x1 = b[0], b[2]
        top = b[1]
        while top > 0:
            row = [px[x, top - 1] for x in range(x0, x1 + 1, 4)]
            goldish = sum(1 for p in row if near_any(p, [(0xF5, 0xD7, 0x7A), (0xD9, 0xA5, 0x21), (0x8C, 0x65, 0x10), (0x4A, 0x32, 0x08)], 40))
            if goldish > len(row) * 0.5:
                top -= 1
            else:
                break
        bot = b[3]
        while bot < 129:
            row = [px[x, bot + 1] for x in range(x0, x1 + 1, 4)]
            darkish = sum(1 for p in row if near_any(p, [(0x0B, 0x0D, 0x10), (0x14, 0x17, 0x1C), (0x8C, 0x65, 0x10)], 30))
            if darkish > len(row) * 0.5:
                bot += 1
            else:
                break
        banner = [b[0], top, b[2], bot, bc[0]["area"]]
    out["title_banner"] = banner
    out["title_banner_interior"] = bc[0]["bbox"] + [bc[0]["area"]] if bc else None

    # --- title text / ornaments: gold blobs inside the banner box
    gold_bright = mask_from(px, w, h, lambda p: near(p, (0xF5, 0xD7, 0x7A), 55))
    out["title_gold_blobs"] = []
    out["title_text"] = None
    if banner:
        m = [[gold_bright[y][x] for x in range(banner[0], banner[2] + 1)]
             for y in range(banner[1], banner[3] + 1)]
        bw, bh = banner[2] - banner[0] + 1, banner[3] - banner[1] + 1
        gc = components(m, bw, bh, min_area=60)
        blobs = [[c["bbox"][0] + banner[0], c["bbox"][1] + banner[1],
                  c["bbox"][2] + banner[0], c["bbox"][3] + banner[1], c["area"]] for c in gc]
        out["title_gold_blobs"] = blobs
        if blobs:
            # the glyphs are the cluster nearest the horizontal centre
            cx = (banner[0] + banner[2]) / 2.0
            best = min(blobs, key=lambda b: abs((b[0] + b[2]) / 2.0 - cx))
            # merge every blob whose centre is within 120px of the best centre
            bcx = (best[0] + best[2]) / 2.0
            grp = [b for b in blobs if abs((b[0] + b[2]) / 2.0 - bcx) <= 120]
            out["title_text"] = [min(b[0] for b in grp), min(b[1] for b in grp),
                                 max(b[2] for b in grp), max(b[3] for b in grp),
                                 sum(b[4] for b in grp)]

    # --- subtitle: grey-blue text just under the banner
    sub = mask_from(px, w, h, lambda p: near_any(p, [(0xB3, 0xBC, 0xC9), (0x8C, 0x97, 0xA8), (0xDC, 0xE2, 0xE8)], 16))
    ylo = (banner[3] + 1) if banner else 100
    m = [[sub[y][x] and ylo <= y <= ylo + 30 for x in range(w)] for y in range(h)]
    out["subtitle"] = bbox_of(m, w, h)

    # --- main panel: #14171C component that begins below the banner
    pm = mask_from(px, w, h, lambda p: near(p, (0x14, 0x17, 0x1C), 6))
    comps = [c for c in components(pm, w, h, min_area=400) if c["bbox"][1] > 118]
    out["main_panel"] = comps[0]["bbox"] + [comps[0]["area"]] if comps else None
    panel = out["main_panel"]

    # --- account bar: thin border colours inside the panel header band
    ab = mask_from(px, w, h, lambda p: near_any(p, [(0x4E, 0x58, 0x66), (0x3A, 0x42, 0x4F)], 8))
    if panel:
        m = [[ab[y][x] and panel[1] + 2 <= y <= panel[1] + 42 and panel[0] <= x <= panel[2]
              for x in range(w)] for y in range(h)]
        out["account_bar"] = bbox_of(m, w, h)
    else:
        out["account_bar"] = None

    # --- divider: gold in the panel, between account bar and first button
    if panel:
        m = [[gold_bright[y][x] and panel[1] + 40 <= y <= panel[1] + 60 and panel[0] <= x <= panel[2]
              for x in range(w)] for y in range(h)]
        out["divider"] = bbox_of(m, w, h)
    else:
        out["divider"] = None

    # --- gold button
    gb = mask_from(px, w, h, lambda p: near(p, (0xD9, 0xA5, 0x21), 30))
    gc = components(gb, w, h, min_area=300)
    out["button_gold"] = gc[0]["bbox"] + [gc[0]["area"]] if gc else None

    # --- dark buttons (#1E232B)
    db = mask_from(px, w, h, lambda p: near(p, (0x1E, 0x23, 0x2B), 6))
    dc = components(db, w, h, min_area=300)
    out["buttons_dark"] = [c["bbox"] + [c["area"]] for c in dc[:4]]

    # --- gold rivets on the panel corners
    if panel:
        m = [[gb[y][x] and panel[0] - 6 <= x <= panel[2] + 6 and panel[1] - 6 <= y <= panel[3] + 6
              for x in range(w)] for y in range(h)]
        rc = components(m, w, h, min_area=4)
        out["panel_rivets"] = [c["bbox"] + [c["area"]] for c in rc[:6]]
    else:
        out["panel_rivets"] = []

    # --- hero sprite (right of x=430)
    m = [[other[y][x] and x >= 430 for x in range(w)] for y in range(h)]
    out["hero"] = bbox_of(m, w, h)

    # --- left weapon column (left of x=200)
    m = [[other[y][x] and x < 200 for x in range(w)] for y in range(h)]
    out["weapon_col"] = bbox_of(m, w, h)

    # --- the three showcase swords, separated by hue
    def hue_bbox(pred):
        mm = [[pred(px[x, y]) and x < 200 for x in range(w)] for y in range(h)]
        return bbox_of(mm, w, h)

    out["sword_blue"] = hue_bbox(lambda p: p[2] > 150 and p[2] - p[0] > 60 and p[2] - p[1] > 30)
    out["sword_grey"] = hue_bbox(lambda p: abs(p[0] - p[1]) < 22 and abs(p[1] - p[2]) < 22
                                 and 110 < p[0] < 220 and p[2] >= p[0] - 6)
    out["sword_green"] = hue_bbox(lambda p: p[1] > p[0] + 25 and p[1] > p[2] + 25 and p[1] > 90)

    # --- overlaps
    code_banner = rect(64, 8, 512, 96)          # code: x 64..575, y 8..103
    code_content = rect(160, 104, 320, 250)     # code: content block x 160..479
    # ⚠️ 2026-09-21 封面定稿后更新（**只改了这一个常量**，其余逻辑未动）：
    #    `HERO_RECT` 由 (446,104,180,250) 移到 **(460,104,180,236)**，且底部裁 14px。
    #    这里用**可见内容** bbox 而不是 rect —— 因为下面 `C2_hero_vs_code_hero_rect`
    #    比的是**实测的不透明像素**（`out["hero"]`），拿 rect 比会把素材左侧 32px 的
    #    透明边也算进重叠区（规范 §6 陷阱 13：立绘 rect ≠ 立绘可见范围）。
    #    可见内容 = rect ∩ 不透明 bbox：左缘 460+32=492、右缘 460+162-1=621、
    #    顶 104、底 104+236-1=339（原素材不透明 bbox y∈[0,250]，裁到 236 后仍到边）。
    code_hero = [492, 104, 621, 339]            # 可见内容 bbox（x0,y0,x1,y1 含端点）
    sw, bn, hp = out["sword_blue"], out["title_banner"], out["hero"]
    out["_overlap"] = {
        "C1_sword_blue_vs_code_banner_rect": overlap(sw, code_banner),
        "C1_sword_blue_vs_measured_banner": overlap(sw, bn),
        "C2_hero_vs_code_content_rect": overlap(hp, code_content),
        "C2_hero_vs_code_hero_rect": overlap(hp, code_hero),
        "C2_hero_vs_measured_panel": overlap(hp, panel),
        "C2_hero_left_vs_panel_right_gap_px": (hp[0] - panel[2] - 1) if (hp and panel) else None,
        "banner_vs_panel": overlap(bn, panel),
    }
    out["_code_rects"] = {"banner": code_banner, "content": code_content, "hero": code_hero}
    return out


def classify_tiles(sp, W, H, tileset_png, atlas_json, ts=32, ui_rects=(), phase=None):
    """Match every 32x32 screen block against the atlas tiles (4x4 mean-colour
    signature) and report the class share.  Returns (counts, rows, phase)."""
    aim = Image.open(tileset_png).convert("RGBA")
    apx = aim.load()
    atlas = json.load(open(atlas_json, encoding="utf-8"))
    ts = atlas.get("tile_size", ts)

    def sig(get, x0, y0):
        s = []
        for by in range(4):
            for bx in range(4):
                r = g = b = n = 0
                for y in range(y0 + by * ts // 4, y0 + (by + 1) * ts // 4):
                    for x in range(x0 + bx * ts // 4, x0 + (bx + 1) * ts // 4):
                        c = get(x, y)
                        if len(c) > 3 and c[3] < 8:
                            continue
                        r += c[0]; g += c[1]; b += c[2]; n += 1
                s.append((r // n, g // n, b // n) if n else None)
        return s

    tiles = []
    for cls, cells in atlas["tiles"].items():
        for (cx, cy) in cells:
            tiles.append((cls, (cx, cy), sig(lambda x, y: apx[x, y], cx * ts, cy * ts)))

    if phase is None:
        sx = [0.0] * ts
        sy = [0.0] * ts
        for r in range(1, W):
            e = 0
            for y in range(0, H, 3):
                a = sp[r, y]; b = sp[r - 1, y]
                e += abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
            sx[r % ts] += e
        for r in range(1, H):
            e = 0
            for x in range(0, W, 3):
                a = sp[x, r]; b = sp[x, r - 1]
                e += abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
            sy[r % ts] += e
        phase = (max(range(ts), key=lambda i: sx[i]), max(range(ts), key=lambda i: sy[i]))
    ox, oy = phase

    def dist(a, b):
        s = 0
        for i in range(16):
            if a[i] is None or b[i] is None:
                continue
            s += (a[i][0] - b[i][0]) ** 2 + (a[i][1] - b[i][1]) ** 2 + (a[i][2] - b[i][2]) ** 2
        return s

    def in_ui(x, y):
        for (a, b, c, d) in ui_rects:
            if a <= x < c and b <= y < d:
                return True
        return False

    counts, counts_map, rows = Counter(), Counter(), []
    for by in range(0, H // ts + 1):
        for bx in range(0, W // ts + 1):
            x0 = ox + bx * ts
            y0 = oy + by * ts
            if x0 < 0 or y0 < 0 or x0 + ts > W or y0 + ts > H:
                continue
            s = sig(lambda x, y: sp[x, y], x0, y0)
            best, bd = None, 1 << 60
            for cls, cell, tsig in tiles:
                d = dist(s, tsig)
                if d < bd:
                    bd, best = d, (cls, cell)
            counts[best[0]] += 1
            rows.append((bx, by, best[0], best[1], int((bd / 16) ** 0.5)))
            if not in_ui(x0 + ts // 2, y0 + ts // 2):
                counts_map[best[0]] += 1
    return counts, counts_map, rows, (ox, oy)


def probe_level1(im, tileset_png=None, atlas_json=None):
    w, h = im.size
    px = im.load()
    out = {}
    counts = Counter()
    for y in range(h):
        for x in range(w):
            counts[px[x, y]] += 1
    out["total_px"] = w * h

    # --- tile-class screen share, by template match (preferred) or colour ---
    if tileset_png and atlas_json:
        UI = [(188, 8, 452, 54), (8, 56, 308, 196)]
        c_all, c_map, rows, phase = classify_tiles(px, w, h, tileset_png, atlas_json, ui_rects=UI)
        out["tile_phase"] = list(phase)
        out["tile_blocks_total"] = sum(c_all.values())
        out["tile_blocks_map"] = sum(c_map.values())
        out["tile_share_all"] = {k: v / max(1, sum(c_all.values())) for k, v in c_all.items()}
        out["tile_share_map"] = {k: v / max(1, sum(c_map.values())) for k, v in c_map.items()}
        errs = sorted(r[4] for r in rows)
        out["tile_match_err"] = {"median": errs[len(errs) // 2], "p90": errs[int(len(errs) * 0.9)], "max": errs[-1]}

    # --- HUD element bboxes -------------------------------------------------
    def near_any(p, ts_, tol):
        return near_any_(p, ts_, tol)

    def near_any_(p, ts_, tol):
        for t in ts_:
            if near(p, t, tol):
                return True
        return False

    def bb(pred, x0=0, y0=0, x1=None, y1=None):
        x1 = w if x1 is None else x1
        y1 = h if y1 is None else y1
        minx, miny, maxx, maxy, n = w, h, -1, -1, 0
        for y in range(y0, y1):
            for x in range(x0, x1):
                if pred(px[x, y]):
                    n += 1
                    minx = min(minx, x); maxx = max(maxx, x)
                    miny = min(miny, y); maxy = max(maxy, y)
        return [minx, miny, maxx, maxy, n] if n else None

    def panel_bbox(pred, x0, x1, y0, y1, min_run=150):
        """bbox of rows that contain a contiguous run of `pred` >= min_run px.
        Robust against the same colour appearing in the map behind the HUD."""
        rows = []
        for y in range(y0, y1):
            best = cur = 0
            for x in range(x0, x1):
                cur = cur + 1 if pred(px[x, y]) else 0
                best = max(best, cur)
            if best >= min_run:
                rows.append(y)
        if not rows:
            return None
        ytop, ybot = min(rows), max(rows)
        xs = [x for y in rows for x in range(x0, x1) if pred(px[x, y])]
        return [min(xs), ytop, max(xs), ybot, len(xs)]

    GOLD = lambda p: near_any_(p, [(0xD9, 0xA5, 0x21), (0xF5, 0xD7, 0x7A)], 55)
    RED = lambda p: p[0] > 90 and p[0] > p[1] + 40 and p[0] > p[2] + 40
    PANEL = lambda p: near(p, (0x14, 0x17, 0x1C), 5)
    BORDER = lambda p: near_any_(p, [(0x4E, 0x58, 0x66), (0x3A, 0x42, 0x4F)], 12)
    BUFF = lambda p: near(p, (0xDB, 0xCC, 0x85), 40)

    out["hud"] = {
        "quest_banner_panel": panel_bbox(PANEL, 150, 500, 0, 55, 150),
        "quest_banner_gold": bb(GOLD, 150, 0, 500, 55),
        "quest_banner_text": bb(lambda p: near(p, (0xB3, 0xBC, 0xC9), 20), 180, 0, 470, 55),
        "quest_panel": panel_bbox(PANEL, 0, 320, 58, 120, 150),
        "quest_panel_border": bb(BORDER, 0, 58, 320, 120),
        "stars_all": bb(lambda p: not PANEL(p) and not near_any_(p, [(0x1E, 0x4A, 0x2B), (0x0F, 0x24, 0x17), (0x3B, 0x7A, 0x44)], 4),
                         205, 76, 300, 100),
        "star_lit": bb(lambda p: near_any_(p, [(0xD9, 0xA5, 0x21), (0xF5, 0xD7, 0x7A)], 55), 205, 76, 300, 100),
        "hp_frame_border": panel_bbox(BORDER, 0, 320, 115, 158, 150),
        "hp_bar_red": bb(RED, 0, 118, 300, 152),
        "buff_text": bb(BUFF, 0, 152, 200, 200),
    }
    # star pitch
    runs = []
    s = None
    for x in range(205, 300):
        n = sum(1 for y in range(76, 100)
                if not PANEL(px[x, y]) and not near_any_(px[x, y], [(0x1E, 0x4A, 0x2B), (0x0F, 0x24, 0x17), (0x3B, 0x7A, 0x44)], 4))
        if n > 0 and s is None:
            s = x
        elif n == 0 and s is not None:
            runs.append([s, x - 1]); s = None
    out["star_runs"] = [r for r in runs if r[1] - r[0] >= 3]
    if len(out["star_runs"]) >= 2:
        out["star_pitch_px"] = out["star_runs"][1][0] - out["star_runs"][0][0]

    # gap between the HP frame bottom and the buff text top
    hp, bf = out["hud"]["hp_frame_border"], out["hud"]["buff_text"]
    out["gap_hpframe_bottom_to_bufftext_top_px"] = (bf[1] - hp[3] - 1) if (hp and bf) else None

    out["top_colors"] = [
        {"hex": hexs(c), "count": n, "share": n / (w * h)}
        for c, n in counts.most_common(20)
    ]
    return out


def probe_generic(im):
    w, h = im.size
    px = im.load()
    counts = Counter()
    for y in range(h):
        for x in range(w):
            counts[px[x, y]] += 1
    return {
        "total_px": w * h,
        "top_colors": [{"hex": hexs(c), "count": n, "share": n / (w * h)}
                       for c, n in counts.most_common(20)],
    }


# -------------------------------------------------------------------- main --
def probe_hud_assets(dirpath):
    """Colour inventory + contrast for the baked HUD PNGs (stars / divider)."""
    res = {}
    for name in sorted(os.listdir(dirpath)):
        if not name.lower().endswith(".png"):
            continue
        fp = os.path.join(dirpath, name)
        im = Image.open(fp)
        rgba = im.convert("RGBA")
        c = Counter()
        transparent = 0
        for p in rgba.getdata():
            if p[3] < 8:
                transparent += 1
            else:
                c[(p[0], p[1], p[2])] += 1
        entry = {"size": list(im.size), "mode": im.mode, "transparent_px": transparent,
                 "colours": []}
        for col, n in c.most_common(8):
            entry["colours"].append({
                "hex": hexs(col), "count": n,
                "contrast_vs_panel_14171C": round(contrast_ratio(col, (0x14, 0x17, 0x1C)), 3),
            })
        if name.startswith("star") and im.width <= 32:
            rows = []
            for y in range(rgba.height):
                line = ""
                for x in range(rgba.width):
                    a = rgba.getpixel((x, y))[3]
                    line += "#" if a > 200 else ("+" if a > 60 else ".")
                rows.append(line)
            entry["shape_ascii"] = rows
        res[name] = entry
    return res


def fmt_bbox(b):
    if not b:
        return "none"
    if len(b) >= 5:
        return f"x {b[0]}..{b[2]}  y {b[1]}..{b[3]}  ({b[2]-b[0]+1}x{b[3]-b[1]+1}px, {b[4]} px)"
    return f"x {b[0]}..{b[2]}  y {b[1]}..{b[3]}  ({b[2]-b[0]+1}x{b[3]-b[1]+1}px)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("png")
    ap.add_argument("--mode", default="auto", choices=["auto", "cover", "level1", "generic"])
    ap.add_argument("--atlas")
    ap.add_argument("--tileset-png")
    ap.add_argument("--hud-assets")
    ap.add_argument("--tile-size", type=int, default=32)
    ap.add_argument("--json")
    a = ap.parse_args()

    im = Image.open(a.png).convert("RGB")
    w, h = im.size
    mode = a.mode
    if mode == "auto":
        mode = "cover" if "cover" in os.path.basename(a.png).lower() else (
            "level1" if "level1" in os.path.basename(a.png).lower() else "generic")

    print(f"# ui_screen_probe  file={os.path.basename(a.png)}  mode={mode}  size={w}x{h}")
    result = {"file": os.path.basename(a.png), "mode": mode, "size": [w, h]}

    if mode == "cover":
        r = probe_cover(im)
        result["cover"] = r
        print("\n## element bboxes (measured)")
        for k in ["title_banner", "title_banner_interior", "title_text", "subtitle",
                  "main_panel", "account_bar", "divider", "button_gold",
                  "hero", "weapon_col", "sword_blue", "sword_grey", "sword_green"]:
            print(f"  {k:<22} {fmt_bbox(r.get(k))}")
        print("  buttons_dark:")
        for b in r.get("buttons_dark", []):
            print(f"    {fmt_bbox(b)}")
        print("  title_gold_blobs:")
        for b in r.get("title_gold_blobs", []):
            print(f"    {fmt_bbox(b)}")
        print("  panel_rivets:")
        for b in r.get("panel_rivets", []):
            print(f"    {fmt_bbox(b)}")
        print("\n## code rects vs measured (overlap in px^2)")
        for k, v in sorted(r["_overlap"].items()):
            print(f"  {k:<44} {v}")
        print("\n## code rects used")
        for k, v in sorted(r["_code_rects"].items()):
            print(f"  {k:<12} {fmt_bbox(v)}")

    elif mode == "level1":
        r = probe_level1(im, tileset_png=a.tileset_png, atlas_json=a.atlas)
        result["level1"] = r
        if "tile_share_all" in r:
            print(f"\n## tile-class share (32px grid template match, phase ox={r['tile_phase'][0]} oy={r['tile_phase'][1]})")
            print(f"  whole screen ({r['tile_blocks_total']} blocks):")
            for k, v in sorted(r["tile_share_all"].items()):
                print(f"    {k:<10} {v*100:6.2f}%")
            print(f"  map area only ({r['tile_blocks_map']} blocks, HUD rects excluded):")
            for k, v in sorted(r["tile_share_map"].items()):
                print(f"    {k:<10} {v*100:6.2f}%")
            e = r["tile_match_err"]
            print(f"  match error (RMS/8x8 subcell): median={e['median']} p90={e['p90']} max={e['max']}")
        else:
            print("\n## tile-class share: skipped (pass --tileset-png <atlas.png> --atlas <atlas.json>)")
        print("\n## HUD element bboxes")
        for k, v in r["hud"].items():
            print(f"  {k:<22} {fmt_bbox(v)}")
        print(f"  star x-runs              {r.get('star_runs')}")
        print(f"  star pitch               {r.get('star_pitch_px')} px")
        print(f"  HPframe_bottom -> bufftext_top gap = {r.get('gap_hpframe_bottom_to_bufftext_top_px')} px")
        print("\n## top colours")
        for c in r["top_colors"][:14]:
            print(f"  {c['hex']}  {c['count']:>7}  {c['share']*100:5.2f}%")

    else:
        r = probe_generic(im)
        result["generic"] = r
        print("\n## top colours")
        for c in r["top_colors"]:
            print(f"  {c['hex']}  {c['count']:>7}  {c['share']*100:5.2f}%")

    if a.atlas and a.tileset_png:
        ts = tile_stats(a.tileset_png, a.atlas, a.tile_size)
        result["atlas"] = ts
        print(f"\n## atlas tile stats  {os.path.basename(a.tileset_png)}")
        for cls, d in sorted(ts.items()):
            print(f"  {cls:<10} n={d['count']:<3} luma mean={d['luma_mean']:6.2f} "
                  f"min={d['luma_min']:6.2f} max={d['luma_max']:6.2f}  sat={d['sat_mean']:.3f}")
        if "ground" in ts and "wall" in ts:
            g, wl = ts["ground"]["luma_mean"], ts["wall"]["luma_mean"]
            print(f"  -> wall/ground luma ratio = {wl/g:.3f}  (delta {wl-g:+.2f})")

    if a.hud_assets:
        ha = probe_hud_assets(a.hud_assets)
        result["hud_assets"] = ha
        print(f"\n## HUD assets  {a.hud_assets}")
        for name, d in sorted(ha.items()):
            print(f"  {name}  {d['size'][0]}x{d['size'][1]} {d['mode']}  transparent={d['transparent_px']}")
            for col in d["colours"]:
                print(f"     {col['hex']}  x{col['count']:<5} contrast vs #14171C = {col['contrast_vs_panel_14171C']}")
            for line in d.get("shape_ascii", []):
                print(f"     |{line}|")

    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=1, sort_keys=True)
        print(f"\n# json -> {a.json}")


if __name__ == "__main__":
    main()
