"""Generate CREDITS.md for the staged tiles in game/assets/_incoming/."""
import os
import glob
from PIL import Image

ROOT = r"D:\七傳說\game\assets\_incoming"
BIOMES = ["forest", "volcanic", "frost"]

SOURCE = {
    "pack": "Dungeon Crawl Stone Soup — 32x32 tiles (full package)",
    "author": "Dungeon Crawl Stone Soup team + contributors (rltiles lineage)",
    "license": "CC0 1.0 Universal (Public Domain Dedication)",
    "commercial": "YES — CC0 permits any use including commercial, no attribution required",
    "urls": [
        "https://opengameart.org/content/dungeon-crawl-32x32-tiles",
        "https://opengameart.org/content/dungeon-crawl-32x32-tiles-supplemental",
        "https://github.com/crawl/tiles",
    ],
    "local_zip": "_src_dcss/dcss_full_cc0.zip",
}

ROLE_DESC = {
    "ground": "floor / terrain base tile",
    "wall": "wall / structure block",
    "prop": "obstacle or prop (blocks movement / decorates)",
    "deco": "decoration overlay (non-blocking)",
}

BIOME_DESC = {
    "forest": "幽林 — dark mossy forest (ch1_l01–ch1_l06)",
    "volcanic": "灰烬堡 — ash fortress / foundry (ch2_l07–ch2_l13)",
    "frost": "霜渊 — frozen abyss / ice cavern / giant's graveyard (ch3_l14–ch3_l20)",
}


def rows():
    out = []
    for b in BIOMES:
        for role in ["ground", "wall", "prop", "deco"]:
            for p in sorted(glob.glob(os.path.join(ROOT, b, f"{b}_{role}_*.png"))):
                with Image.open(p) as im:
                    w, h = im.size
                out.append({
                    "path": f"game/assets/_incoming/{b}/{os.path.basename(p)}",
                    "dim": f"{w}x{h}",
                    "biome": b,
                    "role": role,
                    "desc": ROLE_DESC[role] + " — " + os.path.basename(p)[:-4].replace(f"{b}_{role}_", ""),
                })
    return out


def main():
    data = rows()
    L = []
    L.append("# 七傳說 — 瓦片素材来源与授权 (Tile asset provenance & license)\n")
    L.append("> 本目录为**待接入**的暂存素材（staging），尚未被 `game/assets/tilesets/` 引用。\n")
    L.append("## 来源\n")
    L.append(f"- **素材包**：{SOURCE['pack']}")
    L.append(f"- **作者**：{SOURCE['author']}")
    L.append(f"- **授权**：**{SOURCE['license']}**")
    L.append(f"- **可否商用**：**{SOURCE['commercial']}**")
    L.append(f"- **本地原始包**：`{SOURCE['local_zip']}`（5.7 MB，含 6029 张 32×32 图）")
    L.append("- **来源页面**：")
    for u in SOURCE["urls"]:
        L.append(f"  - {u}")
    L.append("")
    L.append("CC0 原文摘要（包内 `LICENSE.txt`）：")
    L.append("> “The person who associated a work with this document has dedicated the work to the")
    L.append("> Commons by waiving all of his or her rights ... Works under CC0 do not require")
    L.append("> attribution.” 并明确许可 “commercial purposes”。")
    L.append("")
    L.append("## 生物群系\n")
    for b in BIOMES:
        L.append(f"- **{b}** — {BIOME_DESC[b]}")
    L.append("")
    L.append("## 重新提取原始包\n")
    L.append("```bash")
    L.append("cd game/assets/_incoming/_src_dcss")
    L.append('unzip -q -o dcss_full_cc0.zip -d .    # 还原 6029 张原始 32x32 图')
    L.append("```\n")
    L.append(f"## 文件清单（{len(data)} 个）\n")
    L.append("| 本地路径 | 像素 | 群系 | 角色 | 内容 | 来源 | 授权 |")
    L.append("|---|---|---|---|---|---|---|")
    for r in data:
        L.append(f"| `{r['path']}` | {r['dim']} | {r['biome']} | {r['role']} | {r['desc']} | "
                 f"OpenGameArt DCSS | CC0 / 可商用 |")
    L.append("")
    L.append("## 预览\n")
    L.append("- `_preview/<biome>_tiles.png` — 该群系全部瓦片接触表（4× 放大）")
    L.append("- `_preview/<biome>_mockmap.png` — 合成 22×14 示意地图，验证地面/墙体/道具可读性")
    L.append("")
    out = os.path.join(ROOT, "CREDITS.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print(f"wrote {out}  ({len(data)} rows)")


if __name__ == "__main__":
    main()
