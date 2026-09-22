# -*- coding: utf-8 -*-
"""sprite sheet 切割管线：横向多帧动作表 -> 对齐稳定的逐帧角色 sprite。

流程：
  1. 整表绿幕抠底
  2. 列投影找每帧角色的非空区间（比等宽切更鲁棒，兼容 AI 帧间距漂移）
  3. 统一缩放比例（所有帧同一比例，避免忽大忽小）+ 脚底对齐同一基线 + 水平居中
  4. 自适应 ~48 色（角色，保留肉色）+ alpha 二值
输出固定 192×192 画布、角色高约 156。

用法：
  python sprite_sheet_cut.py <sheet.png> <out_dir> <prefix> [--n 4] [--tol 80] [--char-h 156]
例：
  python sprite_sheet_cut.py _dl/walk_s.png characters/walk_s char_warrior_walk_s
  -> characters/walk_s/char_warrior_walk_s_01.png ... _04.png
"""
import argparse
import sys
from collections import deque
from pathlib import Path
from PIL import Image

import pixel_pipeline as P


def clean_edge_fragments(frame, edge_frac=0.02, area_frac=0.015):
    """删除贴在切分边界的孤立小碎片（相邻帧越界的剑尖/剑气尖）。

    4-连通域：保留角色主体（最大组件）与较大组件（如横斩剑气弧）；
    只删除"贴边且面积很小"的组件。
    """
    w, h = frame.size
    px = frame.load()
    seen = bytearray(w * h)
    comps = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or px[sx, sy][3] == 0:
                continue
            q = deque([(sx, sy)]); seen[sy * w + sx] = 1; cells = []
            while q:
                x, y = q.popleft(); cells.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny][3] > 0:
                        seen[ny * w + nx] = 1; q.append((nx, ny))
            comps.append(cells)
    if not comps:
        return frame
    comps.sort(key=len, reverse=True)
    big_set = set(map(tuple, comps[0]))
    min_area = w * h * area_frac
    edge = int(w * edge_frac)
    keep = set(big_set)
    for cells in comps[1:]:
        xs = [c[0] for c in cells]
        xmin, xmax = min(xs), max(xs)
        touches_edge = xmin <= edge or xmax >= w - 1 - edge
        # 大组件（剑气弧）保留；贴边的小碎片删除
        if len(cells) >= min_area or not touches_edge:
            keep.update(cells)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for (x, y) in keep:
        op[x, y] = px[x, y]
    return out


def find_frame_columns(alpha, n, equal=False):
    """找 n 个角色的横向区间。返回 [(x0,x1), ...]。

    用「头部带」（高度 12%-42%）做列投影：头部之间一定有绿缝，
    不受腰部横斩剑气、底部基线/地面、倒地帧等干扰。
    找到 n 个头部段中心后，以相邻中心中点为边界向两侧扩展包含全身。
    """
    w, h = alpha.size
    px = alpha.load()

    if equal:
        fw = w // n
        return [(i * fw, (i + 1) * fw - 1) for i in range(n)]

    y0, y1 = int(h * 0.12), int(h * 0.42)
    col = [0] * w
    for x in range(w):
        c = 0
        for y in range(y0, y1):
            if px[x, y][3] > 0:
                c += 1
        col[x] = c
    occupied = [c > 1 for c in col]
    runs = []
    x = 0
    while x < w:
        if occupied[x]:
            x0 = x
            while x < w and occupied[x]:
                x += 1
            runs.append((x0, x - 1))
        else:
            x += 1

    if len(runs) != n:
        print(f"[警告] 头部带投影得到 {len(runs)} 段（期望 {n}），退化为等宽切分")
        fw = w // n
        return [(i * fw, (i + 1) * fw - 1) for i in range(n)]

    centers = [(a + b) // 2 for a, b in runs]
    # 相邻中心中点为界
    bounds = [0]
    for i in range(len(centers) - 1):
        bounds.append((centers[i] + centers[i + 1]) // 2)
    bounds.append(w - 1)
    cols = [(bounds[i], bounds[i + 1]) for i in range(n)]
    return cols


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("out_dir")
    ap.add_argument("prefix")
    ap.add_argument("--n", type=int, default=4)
    ap.add_argument("--tol", type=float, default=80)
    ap.add_argument("--char-h", type=int, default=156)
    ap.add_argument("--canvas", type=int, default=192)
    ap.add_argument("--equal", action="store_true", help="强制等宽切分")
    ap.add_argument("--cuts", type=int, nargs="*", default=None,
                    help="手动帧分界点（n-1 个 x 坐标），如 --cuts 840")
    args = ap.parse_args()

    sheet = Image.open(args.sheet).convert("RGBA")
    print(f"[sheet] {sheet.size}，抠绿中...")
    cut = P.flood_remove_bg(sheet, tol=args.tol)

    if args.cuts:
        bounds = [0] + args.cuts + [sheet.width]
        cols = [(bounds[i], bounds[i + 1] - 1) for i in range(len(bounds) - 1)]
    else:
        cols = find_frame_columns(cut, args.n, args.equal)
    print(f"[sheet] 帧列区间: {cols}")

    # 先裁出每帧 bbox（含上下），清理边缘碎片，并统一缩放
    frames = []
    for i, (x0, x1) in enumerate(cols):
        frame = cut.crop((x0, 0, x1 + 1, cut.height))
        frame = clean_edge_fragments(frame)
        bbox = frame.getbbox()
        if bbox:
            frame = frame.crop(bbox)
        frames.append(frame)

    # 统一缩放：取所有帧高度的最大值对齐 char_h，保证脚不漂移
    max_h = max(f.height for f in frames)
    s = args.char_h / max_h
    canvas = args.canvas
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for i, frame in enumerate(frames):
        nh = max(1, round(frame.height * s))
        nw = max(1, round(frame.width * s))
        small = P.downsample_to_size(frame, nw, nh)
        # 水平居中、脚底对齐
        box = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        ox = (canvas - nw) // 2
        oy = canvas - nh
        box.paste(small, (ox, oy), small)
        box = P.adaptive_quantize(box, colors=48)
        ncol = len(set(c for c in box.getdata() if c[3] > 0))
        out = out_dir / f"{args.prefix}_{i + 1:02d}.png"
        box.save(out)
        print(f"  帧{i+1}: bbox={frame.size} -> {nw}x{nh}  {ncol}色  {out.name}")
    print(f"[完成] {len(frames)} 帧 -> {out_dir}")


if __name__ == "__main__":
    main()
