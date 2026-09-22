# -*- coding: utf-8 -*-
"""严谨像素化管线（AI 像素风设计稿 -> 可直接进游戏的 sprite）。

步骤：
  1. 色键抠底（默认洋红 #FF00FF，边界泛洪可选）
  2. 探测像素网格周期 N（AI 图是低分辨率网格被整数放大，N 为放大倍数）
  3. 按 N 网格取每块主色 -> 还原"原生像素图"
  4. 求 bbox 裁切，最近邻缩放到目标画布（角色脚底对齐底边）
  5. 量化到项目 44 色板 PALETTE_ALL（最近色映射）
  6. alpha 二值化（硬阈值）
  7. 输出 sprite + 最近邻放大预览（默认 x4）
"""
from __future__ import annotations

import argparse
import math
from collections import deque
from pathlib import Path

from PIL import Image

# ── 项目 44 色板（game_constants.gd PALETTE_ALL）──────────────────────
PALETTE = [
    # A 中性 11
    "0B0D10", "14171C", "1E232B", "2A313B", "3A424F", "4E5866", "6B7688",
    "8C97A8", "B3BCC9", "DCE2E8", "DBCC85",
    # B 强调 7x4
    "4A0E12", "8C1A1F", "C42B2B", "E8573F",          # 血
    "0F2417", "1E4A2B", "3B7A44", "6FB35C",          # 毒
    "101A3A", "1F3468", "3A5FB0", "6E9BE8",          # 冰
    "4A3208", "8C6510", "D9A521", "F5D77A",          # 金
    "2A1440", "4E2478", "7E44B8", "B07DE0",          # 紫
    "4A0816", "B01038", "FF2D55", "FF7A96",          # 猩红
    "0A2B22", "1B6B52", "2FA37A", "6FE0B4",          # 套装青绿
    # C 稀有度 5
    "C9D1D9", "4C8BF5", "F5C542", "A96BFF", "FF8A2B",
]
PALETTE_RGB = [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in PALETTE]


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def detect_border_bg(img: Image.Image) -> tuple[int, int, int]:
    """采样边界主色（众数），作为抠底基准。"""
    from collections import Counter
    w, h = img.size
    px = img.load()
    c = Counter()
    for x in range(0, w, 3):
        c[px[x, 1][:3]] += 1
        c[px[x, h - 2][:3]] += 1
    for y in range(0, h, 3):
        c[px[1, y][:3]] += 1
        c[px[w - 2, y][:3]] += 1
    return c.most_common(1)[0][0]


def flood_remove_bg(img: Image.Image, bg_hint=None, tol=70) -> Image.Image:
    """从边界泛洪抠底：只删与边界连通的背景，不把角色身上同色打出洞。"""
    img = img.convert("RGBA")
    w, h = img.size
    if bg_hint is None:
        bg_hint = detect_border_bg(img)
    px = img.load()
    visited = bytearray(w * h)
    q = deque()

    def idx(x, y):
        return y * w + x

    # 边界种子点（四条边，步长 2 加速）
    for x in range(0, w, 2):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(0, h, 2):
        q.append((0, y)); q.append((w - 1, y))

    def close(c, b):
        return math.sqrt(sum((c[i] - b[i]) ** 2 for i in range(3))) <= tol

    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or visited[idx(x, y)]:
            continue
        visited[idx(x, y)] = 1
        if close(px[x, y][:3], bg_hint):
            px[x, y] = (0, 0, 0, 0)
            q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])

    # 二次清扫：边缘残留的背景色半透明像素（抗锯齿边）。
    # 仅处理"邻接透明边"的像素，避免误删角色内部同色区域。
    def near_bg(c, mult):
        return math.sqrt(sum((c[i] - bg_hint[i]) ** 2 for i in range(3))) <= tol * mult

    def is_border(x, y):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0:
                return True
        return False

    # 绿幕专用：清掉角色轮廓内"封闭"的绿色缝隙（泛洪够不到的内部绿）。
    # 角色无绿色，判定 G 通道显著主导即可安全删除。
    is_green = (bg_hint[1] > bg_hint[0] + 60 and bg_hint[1] > bg_hint[2] + 60)

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            # 封闭绿幕缝隙：G 主导 -> 直接透明（角色本体无绿色）
            if is_green and g > r + 35 and g > b + 35 and g > 110:
                px[x, y] = (0, 0, 0, 0)
                continue
            # 很接近背景色且在边缘 -> 透明
            if near_bg((r, g, b), 0.5) and is_border(x, y):
                px[x, y] = (0, 0, 0, 0)
            # 中等接近背景色且在边缘 -> 去背景污染（un-mix），压暗边缘
            elif near_bg((r, g, b), 0.85) and is_border(x, y):
                rr = min(255, int(r * 0.75))
                gg = min(255, int(g * 0.75))
                bb = min(255, int(b * 0.75))
                px[x, y] = (rr, gg, bb, 255)
    return img


def detect_grid_n(img: Image.Image, max_n=40) -> int:
    """探测像素网格周期：对水平/垂直差分做自相关，取第一个显著峰。"""
    g = img.convert("L")
    w, h = g.size
    px = g.load()

    def period(profile):
        # 归一化自相关
        m = len(profile)
        mean = sum(profile) / m
        v = [p - mean for p in profile]
        scores = {}
        for lag in range(4, max_n + 1):
            s = sum(v[i] * v[i + lag] for i in range(m - lag))
            scores[lag] = s
        best = max(scores, key=scores.get)
        return best

    # 水平方向：取中间若干行，列方向亮度变化
    rows = [h // 4, h // 2, 3 * h // 4]
    col_profile = []
    for x in range(w):
        col_profile.append(sum(abs(px[x, r] - px[x - 1, r]) if x > 0 else 0 for r in rows))
    n_x = period(col_profile)
    return n_x


def downsample_grid(img: Image.Image, n: int) -> Image.Image:
    """按像素网格 N 取每块主色（众数），还原原生像素图；比中心像素更抗锯齿。"""
    from collections import Counter
    w, h = img.size
    nw, nh = w // n, h // n
    out = Image.new("RGBA", (nw, nh))
    op = out.load()
    px = img.load()
    half = n // 2
    for oy in range(nh):
        for ox in range(nw):
            x0, y0 = ox * n, oy * n
            cnt = Counter()
            # 采样块内部（去掉边缘 1px 抗锯齿带）
            for sy in range(max(0, y0 + 1), min(h, y0 + n - 1)):
                for sx in range(max(0, x0 + 1), min(w, x0 + n - 1)):
                    p = px[sx, sy]
                    cnt[p] += 1
            # 若透明像素占多数 -> 透明；否则取最常见不透明色
            total = sum(cnt.values())
            trans = sum(v for k, v in cnt.items() if k[3] < 128)
            if trans > total * 0.6:
                op[ox, oy] = (0, 0, 0, 0)
            else:
                opaque = Counter({k: v for k, v in cnt.items() if k[3] >= 128})
                op[ox, oy] = opaque.most_common(1)[0][0] if opaque else (0, 0, 0, 0)
    return out


def crop_bbox(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def quantize_palette(img: Image.Image) -> Image.Image:
    """量化到 44 色板（alpha 保留）。"""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                op[x, y] = (0, 0, 0, 0)
                continue
            best, bd = None, 1 << 30
            for (pr, pg, pb) in PALETTE_RGB:
                d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
                if d < bd:
                    bd, best = d, (pr, pg, pb)
            op[x, y] = (best[0], best[1], best[2], 255)
    return out


def fit_canvas(img: Image.Image, canvas: int, max_h_ratio=0.92,
               baseline_align=True) -> Image.Image:
    """最近邻缩放到画布（角色占画布高度比例），脚底对齐底边居中。"""
    w, h = img.size
    target_h = int(canvas * max_h_ratio)
    scale = target_h / h
    nw, nh = max(1, round(w * scale)), target_h
    img = img.resize((nw, nh), Image.NEAREST)
    sheet = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ox = (canvas - nw) // 2
    oy = canvas - nh if baseline_align else (canvas - nh) // 2
    sheet.paste(img, (ox, oy), img)
    return sheet


def nearest_scale(img: Image.Image, factor: int) -> Image.Image:
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def downsample_to_size(img: Image.Image, target_w: int, target_h: int) -> Image.Image:
    """按目标尺寸做块主色降采样（每块取众数色），消除 AI 抗锯齿，还原硬像素。"""
    from collections import Counter
    w, h = img.size
    sx, sy = w / target_w, h / target_h
    out = Image.new("RGBA", (target_w, target_h))
    op = out.load()
    px = img.load()
    for oy in range(target_h):
        y0, y1 = int(oy * sy), int((oy + 1) * sy)
        for ox in range(target_w):
            x0, x1 = int(ox * sx), int((ox + 1) * sx)
            cnt = Counter()
            for yy in range(max(0, y0), min(h, y1)):
                for xx in range(max(0, x0), min(w, x1)):
                    cnt[px[xx, yy]] += 1
            total = sum(cnt.values())
            trans = sum(v for k, v in cnt.items() if k[3] < 128)
            if trans > total * 0.6:
                op[ox, oy] = (0, 0, 0, 0)
            else:
                opaque = Counter({k: v for k, v in cnt.items() if k[3] >= 128})
                op[ox, oy] = opaque.most_common(1)[0][0] if opaque else (0, 0, 0, 0)
    return out


def adaptive_quantize(img: Image.Image, colors=48, thresh=128) -> Image.Image:
    """自适应量化到 N 色（保留 alpha，角色用：含肉色，DNF 角色约 46 色）。
    只对不透明像素做中位切分量化，透明像素保持全透。"""
    img = img.convert("RGBA")
    w, h = img.size
    rgba = img.split()
    # 用不透明像素建立量化调色板
    rgb = Image.merge("RGB", rgba[:3])
    # 遮罩：不透明区参与量化
    mask = rgba[3].point(lambda a: 255 if a >= thresh else 0)
    quant = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                         dither=Image.Dither.NONE)
    qrgb = quant.convert("RGB")
    out = Image.new("RGBA", (w, h))
    op = out.load()
    qp = qrgb.load()
    mp = mask.load()
    for y in range(h):
        for x in range(w):
            if mp[x, y] > 0:
                r, g, b = qp[x, y]
                op[x, y] = (r, g, b, 255)
            else:
                op[x, y] = (0, 0, 0, 0)
    return out


def binarize_alpha(img: Image.Image, thresh=128) -> Image.Image:
    """仅做 alpha 二值化，保留原色（调试/无损参考用）。"""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < thresh:
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = (r, g, b, 255)
    return img


def process(src, out_dir, canvas=192, char_h=156, bg=None, tol=70,
            preview=4, grid_n=None, palette="char", center_baseline=True):
    """单角色/单物品 -> 固定画布 sprite。
    palette: 'char' 保留原色仅二值alpha（角色/立绘/武器）；'44' 量化到项目44色板（UI/特效）。
    """
    src = Path(src)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGBA")
    print(f"[1] 原图 {img.size}")
    img = flood_remove_bg(img, bg, tol)
    print(f"[2] 边界泛洪抠底完成（bg={'auto' if bg is None else bg}）")

    crop = crop_bbox(img)
    bw, bh = crop.size
    print(f"[3] bbox 裁切 {bw}x{bh}")

    s = bh / char_h
    tw = max(1, round(bw / s))
    native = downsample_to_size(crop, tw, char_h)
    print(f"[4] 块主色降采样 -> {native.size}（{s:.2f}x 网格）")

    sheet = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ox = (canvas - native.width) // 2
    oy = canvas - native.height if center_baseline else (canvas - native.height) // 2
    sheet.paste(native, (ox, oy), native)
    print(f"[5] 放入画布 {canvas}x{canvas}")

    if palette == "44":
        sheet = quantize_palette(sheet)
        print("[6] 量化到 44 色板 + alpha 二值化")
    elif palette == "char":
        sheet = adaptive_quantize(sheet, colors=48)
        ncol = len(set(c for c in sheet.getdata() if c[3] > 0))
        print(f"[6] 自适应量化到 ~48 色 + alpha 二值化（实测 {ncol} 色，保留肉色）")
    else:
        sheet = binarize_alpha(sheet)
        ncol = len(set(c for c in sheet.getdata() if c[3] > 0))
        print(f"[6] 保留原色 + alpha 二值化（{ncol} 色）")

    stem = src.stem
    out_path = out_dir / f"{stem}_px{canvas}.png"
    sheet.save(out_path)
    print(f"[7] 输出 sprite: {out_path}")

    if preview > 0:
        prev = nearest_scale(sheet, preview)
        prev_path = out_dir / f"{stem}_px{canvas}_x{preview}preview.png"
        prev.save(prev_path)
        print(f"    放大预览 x{preview}: {prev_path}")
    return out_path


def process_background(src, out_path, target_w=640, target_h=360, palette="44"):
    """满版背景/场景：不抠图，块主色降采样到目标尺寸，再量化。"""
    src = Path(src)
    img = Image.open(src).convert("RGBA")
    print(f"[BG1] 原图 {img.size}")
    # 先最近邻粗降到接近目标，再块主色精确到目标像素
    native = downsample_to_size(img, target_w, target_h)
    print(f"[BG2] 块主色降采样 -> {native.size}")
    if palette == "44":
        native = quantize_palette(native)
        print("[BG3] 量化到 44 色板")
    else:
        native = adaptive_quantize(native, colors=48)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    native.save(out_path)
    print(f"[BG4] 输出背景: {out_path}")
    return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--out", default=None)
    ap.add_argument("--mode", default="sprite", choices=["sprite", "background"])
    ap.add_argument("--canvas", type=int, default=192)
    ap.add_argument("--char-h", type=int, default=156)
    ap.add_argument("--tol", type=float, default=70)
    ap.add_argument("--grid", type=int, default=None)
    ap.add_argument("--preview", type=int, default=4)
    ap.add_argument("--bg", default="auto")
    ap.add_argument("--palette", default="char", choices=["char", "44", "raw"])
    ap.add_argument("--bw", type=int, default=640)
    ap.add_argument("--bh", type=int, default=360)
    ap.add_argument("--center", action="store_true", help="垂直居中而非脚底对齐")
    args = ap.parse_args()

    if args.mode == "background":
        out = args.out or (Path(args.src).parent / "sprites" /
                           (Path(args.src).stem + f"_{args.bw}x{args.bh}.png"))
        process_background(args.src, out, args.bw, args.bh, args.palette)
        return

    bg = None if args.bg == "auto" else tuple(int(x) for x in args.bg.split(","))
    out = args.out or Path(args.src).parent / "sprites"
    process(args.src, out, args.canvas, args.char_h, bg, args.tol,
            args.preview, args.grid, args.palette, not args.center)


if __name__ == "__main__":
    main()
