#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把素材包的武器/护甲图标量化进 `PALETTE_ALL`（44 色）。

为什么需要这个
--------------
`ui/{weapons,armor}/*.png` 是**未量化**的 AI 出图：
逐张实测 43~47 个出板色。而本仓库的**唯一色源铁律**（`game_constants.gd:607`）要求
烘焙图像资产的每个像素都落在 `PALETTE_ALL`（44 色，`:654`）。

包的 `ui/pixel/`、`ui/skill_icons/`、`backgrounds/`、`fx/`、`anim/` 都过了包的
`verify_pack.py`，但**那份校验没覆盖 `weapons/` 与 `armor/`** —— 于是这两类成了漏网。

做法
----
复用 `tiles_quantize.py` 的 `parse_palette()` / `nearest()`（同一份口径，避免两套实现漂移），
对每个不透明像素取 `PALETTE_ALL` 里的最近色（加权 RGB 欧氏距离），alpha 二值化。
**源文件不动** —— 只写 `game/assets/icons/equipment/` 下的目标。

用法
----
    python game/tools/icons_quantize.py --dry-run   # 只报告，不写盘
    python game/tools/icons_quantize.py             # 执行
"""
from __future__ import annotations

import argparse
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tiles_quantize import parse_palette, nearest  # noqa: E402

GAME_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 素材包唯一來源：專案根下的 `ui/`（2026-09-22 由 `deliverables/pixel_pack_2026-09-21/` 更名歸位，內容逐位元組相同）
PACK_DIR = os.path.join(os.path.dirname(GAME_DIR), "ui")
DST_DIR = os.path.join(GAME_DIR, "assets", "icons", "equipment")

# 包源 → 游戏目标（**同名同尺寸直替**，只有色板需要修）
JOBS = [
    ("weapons/weapon_axe_48.png", "equip_axe_48.png"),
    ("weapons/weapon_bow_48.png", "equip_bow_48.png"),
    ("weapons/weapon_dagger_48.png", "equip_dagger_48.png"),
    ("weapons/weapon_shield_48.png", "equip_shield_48.png"),
    ("weapons/weapon_staff_48.png", "equip_staff_48.png"),
    ("weapons/weapon_sword_48.png", "equip_sword_48.png"),
    ("armor/equip_helmet_48.png", "equip_helmet_48.png"),
    ("armor/equip_chest_48.png", "equip_chest_48.png"),
    ("armor/equip_gauntlet_48.png", "equip_gauntlet_48.png"),
    ("armor/equip_boots_48.png", "equip_boots_48.png"),
]


def out_of_palette(im: Image.Image, pal: set) -> set:
    """返回该图**出板**的颜色集合（十六进制串，不含 #）。"""
    return {
        "%02X%02X%02X" % px[:3]
        for px in im.getdata() if px[3] > 0
    } - {"%02X%02X%02X" % c for c in pal}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # `parse_palette()` 返回 (NEUTRAL, ACCENT, RARITY_SEMANTIC) 三段 ——
    # 自校验口径是**三段合并后的完整 PALETTE_ALL**（与 `palette_contains()` 对齐）。
    neutral, accent, rarity = parse_palette()
    full_palette = list(dict.fromkeys(list(neutral) + list(accent) + list(rarity)))
    pal_set = set(full_palette)
    print("PALETTE_ALL = %d 色（中性 %d + 强调 %d + 稀有度 %d）"
          % (len(pal_set), len(neutral), len(accent), len(rarity)))

    total_before = total_after = 0
    for rel_src, dst_name in JOBS:
        src = os.path.join(PACK_DIR, rel_src.replace("/", os.sep))
        dst = os.path.join(DST_DIR, dst_name)
        if not os.path.isfile(src):
            print("  !! 源缺失: %s" % src)
            return 1
        im = Image.open(src).convert("RGBA")
        before = out_of_palette(im, pal_set)
        total_before += len(before)

        # 量化：逐像素取最近色；alpha 二值（与 tiles_quantize 同口径）
        out = Image.new("RGBA", im.size, (0, 0, 0, 0))
        cache: dict = {}
        src_px = im.load()
        dst_px = out.load()
        for y in range(im.height):
            for x in range(im.width):
                r, g, b, a = src_px[x, y]
                if a < 128:
                    continue
                key = (r, g, b)
                nc = cache.get(key)
                if nc is None:
                    nc = nearest(key, full_palette)
                    cache[key] = nc
                dst_px[x, y] = (nc[0], nc[1], nc[2], 255)
        after = out_of_palette(out, pal_set)
        total_after += len(after)

        if not args.dry_run:
            out.save(dst)
        print("  %-26s 出板 %2d -> %d   唯一色 %4d -> %3d%s"
              % (dst_name, len(before), len(after),
                 len(set(im.getdata())), len(set(out.getdata())),
                 "  [dry-run]" if args.dry_run else ""))

    print()
    print("出板色合计：%d -> %d （必须归零）" % (total_before, total_after))
    return 0 if total_after == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
