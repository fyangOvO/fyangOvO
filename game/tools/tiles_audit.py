"""Audit the existing tilesets/<biome>/atlas.{png,json} against tile-renderer's contract.

Checks:
  - atlas.json has tile_size + tiles with keys ground/wall/obstacle, each >=1 variant
  - every coord is inside the atlas grid
  - alpha coverage per tile, to catch transparent sprites wrongly filed as `ground`
  - duplicate coords across categories
Writes a report to stdout (redirect to a file; stdout capture is broken this session).
"""
import os
import json
import sys
from collections import Counter

ROOT = r"D:\七傳說\game\assets\tilesets"
BIOMES = ["forest", "volcanic", "frost"]
REQUIRED = ["ground", "wall", "obstacle"]

try:
    from PIL import Image
except ImportError:
    Image = None


def alpha_frac(im, cx, cy, ts):
    tile = im.crop((cx * ts, cy * ts, (cx + 1) * ts, (cy + 1) * ts)).convert("RGBA")
    px = tile.load()
    opaque = 0
    for y in range(tile.height):
        for x in range(tile.width):
            if px[x, y][3] > 8:
                opaque += 1
    return opaque / float(tile.width * tile.height)


def main():
    out = []
    for b in BIOMES:
        d = os.path.join(ROOT, b)
        out.append(f"===== {b} =====")
        jp, ip = os.path.join(d, "atlas.json"), os.path.join(d, "atlas.png")
        if not (os.path.isfile(jp) and os.path.isfile(ip)):
            out.append(f"  MISSING: json={os.path.isfile(jp)} png={os.path.isfile(ip)}")
            continue
        with open(jp, encoding="utf-8") as f:
            j = json.load(f)
        ts = j.get("tile_size", 32)
        tiles = j.get("tiles", {})
        im = Image.open(ip)
        cols, rows = im.size[0] // ts, im.size[1] // ts
        out.append(f"  atlas.png {im.size} mode={im.mode}  tile_size={ts}  grid={cols}x{rows}")

        # contract: required keys, >=1 variant
        for k in REQUIRED:
            v = tiles.get(k)
            if not v:
                out.append(f"  !! CONTRACT VIOLATION: '{k}' missing or empty -> renderer falls back to placeholder")
            else:
                out.append(f"  {k:<9} {len(v):>3} variants")
        extra = [k for k in tiles if k not in REQUIRED]
        if extra:
            out.append(f"  (extra keys: {extra})")

        # coordinate validity + duplicates
        seen = {}
        oob = []
        for k, v in tiles.items():
            for c in v:
                c = tuple(c)
                if not (0 <= c[0] < cols and 0 <= c[1] < rows):
                    oob.append((k, c))
                if c in seen:
                    out.append(f"  !! DUPLICATE coord {c}: in '{seen[c]}' and '{k}'")
                seen[c] = k
        out.append(f"  out-of-range coords: {len(oob)}")
        used = len(seen)
        out.append(f"  cells used: {used} / {cols * rows}  ({used / float(cols * rows) * 100:.0f}% fill)")

        # alpha audit: ground must be opaque, obstacle usually sparse
        if Image is not None:
            for k in REQUIRED:
                v = tiles.get(k, [])
                if not v:
                    continue
                fr = [(tuple(c), alpha_frac(im, c[0], c[1], ts)) for c in v]
                low = [(c, f) for c, f in fr if f < 0.6]
                avg = sum(f for _, f in fr) / len(fr)
                out.append(f"  {k:<9} alpha: avg={avg:.2f}  tiles_with_<60%_coverage={len(low)}")
                if k == "ground" and low:
                    out.append(f"     !! transparent tiles filed as GROUND (would show void behind floor):")
                    for c, f in low[:12]:
                        out.append(f"        coord {c} coverage={f:.2f}")
                if k == "obstacle" and len(low) == 0 and v:
                    out.append(f"     note: obstacle tiles are fully opaque (full-bleed tiles, not cut-out sprites)")
        out.append("")

    txt = "\n".join(out)
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_audit_report.txt"), "w", encoding="utf-8") as f:
        f.write(txt)
    print(txt)


if __name__ == "__main__":
    main()
