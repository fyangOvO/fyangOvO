# -*- coding: utf-8 -*-
"""瓦片量化 + 图集打包（把外部 CC0 素材规整成项目可直接消费的图集）。

为什么需要
----------
`game/scripts/core/game_constants.gd:607` 的**唯一色源铁律**原文点名 tile：

    烘焙图像资产（PNG 精灵 / 图标 / tile）全部像素必须落在 `PALETTE_ALL`

外部下载的素材（DCSS 32×32，单张 4–986 色）**不能直接入库**，必须先量化。

做法（三个刻意的设计决策）
--------------------------
1. **色板从 `game_constants.gd` 现读**，不硬编码 —— 保持色板唯一真源。
   若将来色板改了，重跑本脚本即可，不会与代码脱节。
2. **按生态限定子色板**，而不是全局 44 色最近邻。理由：全局最近邻会把
   森林的绿错配到「血/危险」红阶上（DCSS 绿偏灰时尤其容易），破坏生态辨识度。
   子色板 = 中性基底 + 该生态的强调色族，**天然 ⊂ PALETTE_ALL ⇒ 合规是构造性保证**。
3. **Alpha 二值化**（阈值 128 → 0 或 255）。两个原因：
   · 铁律的 `palette_contains()` 会连 alpha 一起比（色板色 alpha 恒为 1.0），
     半透明像素必然判不合规；
   · 美术规范要求 1px 硬描边，半透明软边本来就不该有。

输出（与 `tile_atlas.gd` 的契约严格一致）
-----------------------------------------
  game/assets/tilesets/<biome>/atlas.png
  game/assets/tilesets/<biome>/atlas.json
    {"tile_size":32,"tiles":{"ground":[[x,y],...],"wall":[[x,y],...],
                             "obstacle":[[x,y],...]}}
    [x,y] 是**图集格坐标**（非像素），与 `TileAtlas._try_load_real()` 一致。

用法
----
    python game/tools/tiles_quantize.py            # 量化 + 打包 + 自校验
    python game/tools/tiles_quantize.py --dry-run  # 只报告，不写文件
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONSTANTS = os.path.join(ROOT, "game", "scripts", "core", "game_constants.gd")
INCOMING = os.path.join(ROOT, "game", "assets", "_incoming")
OUT_ROOT = os.path.join(ROOT, "game", "assets", "tilesets")

TILE = 32
COLS = 8
ALPHA_THRESHOLD = 128

# 生态 → (强调色族索引, 说明)。ACCENT 每 4 色一族，顺序见 game_constants.gd:629。
#   0=血/危险 1=毒/自然 2=魔法/冰 3=金/光 4=虚空紫 5=神话猩红 6=套装青绿
BIOME_FAMILIES = {
    "forest":   ([1, 6], "毒/自然 绿阶 + 套装 青绿（承接 DCSS 深青地砖）"),
    "volcanic": ([0, 3], "血/危险 红阶 + 金/光（承接熔岩与余烬）"),
    "frost":    ([2, 6], "魔法/冰 蓝阶 + 套装 青绿（承接冰晶与青玉）"),
}

# 文件名角色 → 引擎消费的角色。prop 即"立在地面上的物件"= obstacle。
# deco（骸骨/花/酸液/深渊纹）本身是**地面细节**，并入 ground 变体，
# 避免出现"生成了但没人消费"的资产（本项目已踩过 9 次）。
ROLE_MAP = {"ground": "ground", "wall": "wall", "prop": "obstacle", "deco": "ground"}

# ---------------------------------------------------------------------------
# 美术挑选（**关键**）：显式指定每个生态每个角色用哪些"材质族"。
#
# 为什么不能"把某角色下的瓦片全塞进一个变体池"
# ------------------------------------------------
# 第一版就是这么干的，结果实测渲出的地图**读不出墙和地的边界**：
#   · volcanic 的墙池混了「红肉 / 黑石带金符 / 铁板带橙纹 / 灰大理石」四种材质，
#     随机取变体 ⇒ 一片花斑，墙地不分；
#   · frost 的墙池混入灰大理石，在地板上像一个个"洞"。
# 变体池的语义是「**同一材质的多个变体**」，不是「任意能当墙的东西」。
# 混材质 = 把纹理噪声当成丰富度。
#
# 依据：`deliverables/gstack/_contact/walls_all.png` 与 `ground_all.png` 逐族目视，
# 判据是「该族内部是否同一材质」+「能否与地面拉开亮度/饱和度差」。
# ---------------------------------------------------------------------------
SELECTION: dict[str, dict[str, list[str]]] = {
    "forest": {
        # 亮度实测（0–255）：moss 17.0 / roots 24.6 / lair 24.6 / bones 29.0
        # ⇒ 带宽 17–29，**族间亮度一致**。
        # ⚠️ 刻意排除 grassmix(100.5) 与 grass(56.8)：与 moss 差 6 倍 / 3 倍，
        #    混入后地面呈「黑洞里插亮绿方块」的明暗棋盘格（实测 mock_forest 即如此）。
        "ground":   ["ground/moss", "ground/roots", "ground/lair", "deco/bones"],
        # 灰砖+苔痕：唯一真正"像墙"的族（lair 是金黄颗粒、vines 半数为亮绿 93.8）
        "wall":     ["wall/brickvines"],
        "obstacle": ["prop/boulder", "prop/broken_pillar", "prop/stump",
                     "prop/tree_mangrove", "prop/mold"],
    },
    "volcanic": {
        # 亮度实测：ash 5.9 / infernal 8.6 / rough 12.7 ⇒ 带宽 5.9–12.7，极紧。
        # ⚠️ 刻意排除 cobble(36.0)：与 ash 差 6 倍，是 mock 里"灰底上冒红块"的来源。
        "ground":   ["ground/ash", "ground/infernal", "ground/rough"],
        # 黑石 36.1：与地面 5.9–12.7 拉开 ~25 ⇒ 墙地边界清晰。
        # 金符在整面墙重复时读作"刻纹"（ash/hell 是红肉 24.6/16.0，作墙会与地抢眼）
        "wall":     ["wall/blackstone"],
        "obstacle": ["prop/boulder", "prop/broken_pillar", "prop/torch",
                     "prop/zot_pillar", "prop/iron_golem"],
    },
    "frost": {
        # 亮度实测：frozen 39.6 / ice 54.0 ⇒ 带宽 39.6–54.0。
        # ⚠️ 排除 abyss(28.1) 以免再拉宽；排除 marble(162.0，灰白，在地上像"洞"）。
        "ground":   ["ground/frozen", "ground/ice"],
        # 冰晶 109.4：与地面 39.6–54.0 拉开 ~55 ⇒ 最清晰的墙地分离。
        # （cobalt 50.8 / permafrost 53.7 与地面亮度几乎重合，实测会"墙地不分"）
        "wall":     ["wall/crystal"],
        "obstacle": ["prop/boulder", "prop/broken_pillar", "prop/tomb",
                     "prop/statue_evil", "prop/statue_hero", "prop/ice_portal",
                     "prop/sarcophagus_sealed"],
    },
}


def parse_palette() -> tuple[list[tuple[int, int, int]], list[tuple[int, int, int]], list[tuple[int, int, int]]]:
    """从 game_constants.gd 现读 NEUTRAL / ACCENT / RARITY_SEMANTIC 三段色板。

    第三段（稀有度语义色）**不进子色板** —— 它们是 UI 语义色（普通/魔法/稀有/
    史诗/传说），不该出现在地砖上。但**必须进自校验集合**，否则「量化结果恰好等于
    某个稀有度色」会被误判为违规。自校验口径 = 完整 PALETTE_ALL，与
    `GameConstants.palette_contains()` 对齐。
    """
    src = open(CONSTANTS, encoding="utf-8").read()

    def grab(name: str) -> list[tuple[int, int, int]]:
        m = re.search(rf"const {name}: Array\[Color\] = \[(.*?)\n\]", src, re.S)
        if not m:
            sys.exit(f"找不到 {name} —— 色板定义可能改了，请检查 {CONSTANTS}")
        return [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
                for h in re.findall(r'Color\("([0-9A-Fa-f]{6})"\)', m.group(1))]

    neutral, accent = grab("PALETTE_NEUTRAL"), grab("PALETTE_ACCENT")
    rarity = grab("PALETTE_RARITY_SEMANTIC")
    if len(accent) % 4 != 0:
        sys.exit(f"ACCENT 色数 {len(accent)} 不是 4 的倍数，色族划分假设不成立")
    return neutral, accent, rarity


def build_sub_palette(biome: str, neutral, accent) -> list[tuple[int, int, int]]:
    fams, _ = BIOME_FAMILIES[biome]
    pal = list(neutral)
    for f in fams:
        pal += accent[f * 4: f * 4 + 4]
    # 去重（中性色与强调色理论无交集，防御性处理）
    seen, out = set(), []
    for c in pal:
        if c not in seen:
            seen.add(c)
            out.append(c)
    return out


def nearest(c, pal):
    """欧氏距离最近邻。用整数避免浮点开销（213 张 × 1024 px × 19 色）。"""
    r, g, b = c
    best, bd = pal[0], 1 << 30
    for (pr, pg, pb) in pal:
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if d < bd:
            bd, best = d, (pr, pg, pb)
    return best


def tile_luminance(path: str) -> float:
    """瓦片平均亮度（只算不透明像素，0–255）。"""
    im = Image.open(path).convert("RGBA")
    px = im.load()
    tot = n = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < ALPHA_THRESHOLD:
                continue
            tot += 0.2126 * r + 0.7152 * g + 0.0722 * b
            n += 1
    return tot / n if n else 0.0


def drop_unlit(files: list[str], keep_ratio: float = 0.72) -> tuple[list[str], list[str]]:
    """剔除「无光照/视野外」暗变体。

    为什么需要：DCSS 这类 tileset 会为**同一材质**同时提供「亮（在视野内）」与
    「极暗（视野外/未探索）」两套瓦片。二者外观差异极大（实测森林地面亮/暗两档
    亮度差近 3 倍）。若把两套都当变体随机取用，地面会呈现**明暗棋盘格**——
    实测 `mock_forest` 就是「一片黑洞里插着亮绿方块」，且墙比地亮、明暗关系倒置。
    变体池的语义是「同一外观的多个变体」，不是「同一材质的多个亮度档」。

    判据：族内亮度中位数为基准，低于 `keep_ratio × 中位数` 的判为暗变体。
    """
    if len(files) < 3:
        return files, []          # 样本太少，分不出档位，不冒险剔除
    lums = [(tile_luminance(f), f) for f in files]
    med = sorted(l for l, _ in lums)[len(lums) // 2]
    if med <= 0:
        return files, []
    kept = [f for l, f in lums if l >= keep_ratio * med]
    dropped = [f for l, f in lums if l < keep_ratio * med]
    return (kept or files), dropped


def quantize_image(img: Image.Image, pal, cache: dict):
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < ALPHA_THRESHOLD:
                px[x, y] = (0, 0, 0, 0)          # 二值化：透明
                continue
            key = (r, g, b)
            nc = cache.get(key)
            if nc is None:
                nc = nearest(key, pal)
                cache[key] = nc
            px[x, y] = (nc[0], nc[1], nc[2], 255)  # 二值化：不透明
    return img


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    neutral, accent, rarity = parse_palette()
    full_palette = set(neutral) | set(accent) | set(rarity)
    print(f"色板：中性 {len(neutral)} + 强调 {len(accent)} + 稀有度 {len(rarity)} "
          f"= PALETTE_ALL {len(full_palette)} 色")
    print(f"子色板只取 中性 + 该生态强调色族；自校验口径 = 完整 PALETTE_ALL\n")

    grand_before = grand_after = 0
    summary = []

    for biome in ("forest", "volcanic", "frost"):
        pal = build_sub_palette(biome, neutral, accent)
        src_dir = os.path.join(INCOMING, biome)
        files = sorted(glob.glob(os.path.join(src_dir, "*.png")))
        if not files:
            print(f"!! {biome}: 找不到素材，跳过")
            continue

        # 按 "角色/材质族" 建索引（材质族 = 文件名去掉角色前缀与结尾序号）
        families: dict[str, list[str]] = defaultdict(list)
        for f in files:
            base = os.path.basename(f)[len(biome) + 1:-4]     # 去掉 "<biome>_" 与 ".png"
            parts = base.split("_")
            role = parts[0]
            mat = "_".join(p for p in parts[1:] if not p.isdigit()) or "single"
            families[f"{role}/{mat}"].append(f)

        # 按 SELECTION 挑选；同时把**没被选中的材质族**列出来
        sel = SELECTION[biome]
        buckets: dict[str, list[str]] = defaultdict(list)
        unlit_dropped: list[str] = []
        for engine_role, keys in sel.items():
            for k in keys:
                if k not in families:
                    sys.exit(f"!! {biome}: SELECTION 指定的 '{k}' 不存在于素材中")
                kept, dropped = drop_unlit(families[k])
                buckets[engine_role] += kept
                unlit_dropped += dropped
        used = {k for keys in sel.values() for k in keys}
        unused = sorted(set(families) - used)

        # 打包：按 ground / wall / obstacle 顺序逐行填充
        order = [("ground", buckets["ground"]), ("wall", buckets["wall"]),
                 ("obstacle", buckets["obstacle"])]
        total = sum(len(v) for _, v in order)
        rows = (total + COLS - 1) // COLS
        atlas = Image.new("RGBA", (COLS * TILE, rows * TILE), (0, 0, 0, 0))

        tiles_json: dict[str, list[list[int]]] = {"ground": [], "wall": [], "obstacle": []}
        cache: dict = {}
        before = after = 0
        idx = 0
        for role, flist in order:
            for f in flist:
                im = Image.open(f).convert("RGBA")
                if im.size != (TILE, TILE):
                    im = im.resize((TILE, TILE), Image.NEAREST)
                before += len(set(im.getdata()))
                q = quantize_image(im, pal, cache)
                after += len(set(q.getdata()))
                cx, cy = idx % COLS, idx // COLS
                atlas.paste(q, (cx * TILE, cy * TILE))
                tiles_json[role].append([cx, cy])
                idx += 1

        # 自校验：逐像素确认全部落在完整 PALETTE_ALL 内（或完全透明）
        bad = 0
        for (r, g, b, a) in atlas.getdata():
            if a == 0:
                continue
            if (r, g, b) not in full_palette:
                bad += 1

        grand_before += before
        grand_after += after
        summary.append((biome, total, len(pal), before, after, bad))

        print(f"[{biome}] {total} 张 → 图集 {COLS}×{rows} 格 ({atlas.width}×{atlas.height}px)")
        print(f"   子色板 {len(pal)} 色 · ground={len(tiles_json['ground'])} "
              f"wall={len(tiles_json['wall'])} obstacle={len(tiles_json['obstacle'])}")
        print(f"   色数合计 {before} → {after} · 色板外像素 {bad} "
              f"{'✓ 合规' if bad == 0 else '✗ 违规！'}")
        if unused:
            print(f"   未选用 {len(unused)} 族（留待后续用途，非丢弃）：")
            for u in unused:
                print(f"      - {u}  x{len(families[u])}")
        if unlit_dropped:
            print(f"   剔除 {len(unlit_dropped)} 张「无光照」暗变体（防地面明暗棋盘格）")

        if not args.dry_run:
            out = os.path.join(OUT_ROOT, biome)
            os.makedirs(out, exist_ok=True)
            atlas.save(os.path.join(out, "atlas.png"))
            with open(os.path.join(out, "atlas.json"), "w", encoding="utf-8") as fh:
                json.dump({"tile_size": TILE, "tiles": tiles_json}, fh,
                          ensure_ascii=False, indent=1)
            print(f"   → {out}/atlas.png + atlas.json")
        print()

    print("=" * 62)
    print(f"总计 色数 {grand_before} → {grand_after} "
          f"（压缩到 {grand_after / max(grand_before, 1) * 100:.1f}%）")
    worst = max((s[5] for s in summary), default=0)
    if worst == 0:
        print("自校验：三张图集全部像素 ∈ PALETTE_ALL ✓")
    else:
        print(f"自校验：存在 {worst} 个色板外像素 ✗")
    return 0 if worst == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
