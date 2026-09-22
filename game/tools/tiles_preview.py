"""Verify assembled tiles are 32x32 and render contact sheets + mock maps.

Outputs into D:/七傳說/game/assets/_incoming/_preview/
  <biome>_tiles.png    contact sheet of every tile (4x scale, labelled rows)
  <biome>_mockmap.png  synthetic 22x14 map proving ground/wall/prop read together
"""
import os
import glob
import random
from collections import Counter
from PIL import Image, ImageDraw

ROOT = r"D:\七傳說\game\assets\_incoming"
PREV = os.path.join(ROOT, "_preview")
BIOMES = ["forest", "volcanic", "frost"]
SCALE = 4
LABEL_H = 16


def check_dims():
    bad = []
    stats = {}
    for b in BIOMES:
        c = Counter()
        for p in sorted(glob.glob(os.path.join(ROOT, b, "*.png"))):
            with Image.open(p) as im:
                c[im.size] += 1
                if im.size != (32, 32):
                    bad.append((p, im.size))
        stats[b] = c
    return stats, bad


def contact_sheet(biome, roles):
    """roles: dict role -> list of paths. Draws one labelled row per role."""
    per_row = 16
    cell = 32 * SCALE
    pad = 4
    maxn = max(len(v) for v in roles.values())
    cols = min(per_row, maxn)
    rows = sum((len(v) + per_row - 1) // per_row for v in roles.values())
    W = cols * (cell + pad) + pad
    H = rows * (cell + pad + LABEL_H) + pad
    sheet = Image.new("RGBA", (W, H), (24, 24, 28, 255))
    dr = ImageDraw.Draw(sheet)
    y = pad
    for role, paths in roles.items():
        n = len(paths)
        r = (n + per_row - 1) // per_row
        for i, p in enumerate(paths):
            cx = pad + (i % per_row) * (cell + pad)
            cy = y + (i // per_row) * (cell + pad + LABEL_H)
            with Image.open(p) as im:
                big = im.convert("RGBA").resize((cell, cell), Image.NEAREST)
            sheet.alpha_composite(big, (cx, cy))
            dr.rectangle([cx, cy, cx + cell, cy + cell], outline=(70, 70, 80, 255))
            dr.text((cx + 2, cy + cell + 2), os.path.basename(p)[:26], fill=(200, 200, 210, 255))
        y += r * (cell + pad + LABEL_H)
    out = os.path.join(PREV, f"{biome}_tiles.png")
    sheet.save(out)
    return out, sheet.size


def mock_map(biome):
    ground = sorted(glob.glob(os.path.join(ROOT, biome, f"{biome}_ground_*.png")))
    wall = sorted(glob.glob(os.path.join(ROOT, biome, f"{biome}_wall_*.png")))
    prop = sorted(glob.glob(os.path.join(ROOT, biome, f"{biome}_prop_*.png")))
    deco = sorted(glob.glob(os.path.join(ROOT, biome, f"{biome}_deco_*.png")))
    if not (ground and wall):
        return None, (0, 0)
    random.seed(7)
    COLS, ROWS = 22, 14
    T = 32
    canvas = Image.new("RGBA", (COLS * T, ROWS * T), (0, 0, 0, 255))
    for gy in range(ROWS):
        for gx in range(COLS):
            edge = gx in (0, COLS - 1) or gy in (0, ROWS - 1)
            if edge:
                src = random.choice(wall)
            else:
                # occasional interior wall block for structure
                if (gx, gy) in {(6, 5), (7, 5), (6, 6), (15, 8), (15, 9)}:
                    src = random.choice(wall)
                else:
                    src = random.choice(ground)
            with Image.open(src) as im:
                canvas.alpha_composite(im.convert("RGBA"), (gx * T, gy * T))
    # scatter props/deco on floor cells
    free = [(x, y) for y in range(2, ROWS - 2) for x in range(2, COLS - 2)]
    random.shuffle(free)
    for p in prop[:8]:
        x, y = free.pop()
        with Image.open(p) as im:
            canvas.alpha_composite(im.convert("RGBA"), (x * T, y * T))
    for d in deco[:6]:
        x, y = free.pop()
        with Image.open(d) as im:
            canvas.alpha_composite(im.convert("RGBA"), (x * T, y * T))
    big = canvas.resize((COLS * T * 2, ROWS * T * 2), Image.NEAREST)
    out = os.path.join(PREV, f"{biome}_mockmap.png")
    big.save(out)
    return out, big.size


def main():
    os.makedirs(PREV, exist_ok=True)
    stats, bad = check_dims()
    print("=== dimension check (assembled tiles) ===")
    for b, c in stats.items():
        print(f"  {b:<10} {dict(c)}")
    if bad:
        print(f"  !! {len(bad)} non-32x32 files:")
        for p, s in bad[:20]:
            print(f"     {p} {s}")
    else:
        print("  ALL TILES ARE 32x32  ✓")

    print("\n=== contact sheets ===")
    for b in BIOMES:
        roles = {}
        for role in ["ground", "wall", "prop", "deco"]:
            ps = sorted(glob.glob(os.path.join(ROOT, b, f"{b}_{role}_*.png")))
            if ps:
                roles[role] = ps
        out, size = contact_sheet(b, roles)
        n = sum(len(v) for v in roles.values())
        print(f"  {b:<10} {n:>3} tiles -> {out}  ({size[0]}x{size[1]})")

    print("\n=== mock maps ===")
    for b in BIOMES:
        out, size = mock_map(b)
        print(f"  {b:<10} -> {out}  ({size[0]}x{size[1]})" if out else f"  {b}: SKIPPED (missing ground/wall)")


if __name__ == "__main__":
    main()
