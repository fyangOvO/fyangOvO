# -*- coding: utf-8 -*-
"""生成素材包总览图 PACK_OVERVIEW.png：分区展示职业/8方向/动作/怪物/装备/UI/背景/特效。"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).parent
BG = (18, 21, 26)
PANEL = (28, 32, 39)
FG = (220, 226, 232)
GOLD = (245, 215, 122)
W = 1680
PAD = 16

sections = []

def load(p, scale=1):
    im = Image.open(p).convert("RGBA")
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    return im

def strip(files, cell, scale, bgscale=1, gap=4):
    """把一组 PNG 放进等宽单元格，底部对齐；背景按整宽缩放。"""
    tiles = []
    for p in files:
        im = Image.open(p).convert("RGBA")
        if im.size == (640, 360):
            bw = 400
            im = im.resize((bw, bw * 360 // 640), Image.NEAREST)
            tile = im
        else:
            im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
            tile = Image.new("RGBA", (cell, cell), PANEL + (255,))
            ox = (cell - im.width) // 2
            oy = cell - im.height - 4
            tile.alpha_composite(im, (max(0, ox), max(0, oy)))
        tiles.append(tile)
    total_w = sum(t.width for t in tiles) + gap * (len(tiles) - 1)
    h = max(t.height for t in tiles)
    strip_img = Image.new("RGBA", (total_w, h), (0, 0, 0, 0))
    x = 0
    for t in tiles:
        strip_img.alpha_composite(t, (x, h - t.height))
        x += t.width + gap
    return strip_img

# 内容定义 (标题, 文件列表, 单元格, 放大倍数)
dirs = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
content = [
    ("CLASSES  職業 idle（戰士 / 法師 / 弓手）",
     ["characters/char_warrior_idle_s_01.png",
      "characters/char_mage_idle_s_01.png",
      "characters/char_archer_idle_s_01.png"], 220, 1),
    ("WARRIOR  8方向行走 n·ne·e·se·s·sw·w·nw",
     [f"characters/walk_{d}/char_warrior_walk_{d}_01.png" for d in dirs], 200, 1),
    ("WARRIOR ACTIONS  攻擊4幀 → 受擊2幀 → 死亡4幀（朝南）",
     [f"characters/attack_s/char_warrior_attack_s_{i:02d}.png" for i in range(1, 5)]
     + [f"characters/hurt_s/char_warrior_hurt_s_{i:02d}.png" for i in range(1, 3)]
     + [f"characters/death_s/char_warrior_death_s_{i:02d}.png" for i in range(1, 5)], 200, 1),
    ("MAGE 施法 4幀  |  ARCHER 射箭 4幀（朝南）",
     [f"characters/attack_s/char_mage_attack_s_{i:02d}.png" for i in range(1, 5)]
     + [f"characters/attack_s/char_archer_attack_s_{i:02d}.png" for i in range(1, 5)], 200, 1),
    ("MONSTERS  毒史萊姆彈跳4幀·冰史萊姆·骷髏攻擊·小鬼攻擊",
     [f"monsters/slime_forest/mon_slime_forest_idle_s_{i:02d}.png" for i in range(1, 5)]
     + [f"monsters/slime_frost/mon_slime_frost_idle_s_{i:02d}.png" for i in (1, 3)]
     + [f"monsters/skeleton/mon_skeleton_attack_s_{i:02d}.png" for i in (1, 3)]
     + [f"monsters/imp_volcanic/mon_imp_volcanic_attack_s_{i:02d}.png" for i in (1, 3)], 200, 1),
    ("BOSS  魔王·惡魔領主（256）",
     ["monsters/mon_boss_demon_lord_idle_s_01.png"], 260, 1),
    ("WEAPONS 10（主手6 + 副手4）",
     ["weapons/" + p.name for p in sorted((ROOT / "weapons").glob("*.png"))], 64, 1),
    ("EQUIPMENT 6（頭/胸/手/鞋/項鏈/戒指）",
     ["armor/" + p.name for p in sorted((ROOT / "armor").glob("*.png"))], 64, 1),
    ("SKILL ICONS  |  FX  |  UI 面板·按鈕·血藍條·槽位·稀有度",
     [f"ui/skill_icons/{p.name}" for p in sorted((ROOT / "ui/skill_icons").glob("*.png"))]
     + [f"fx/{p.name}" for p in sorted((ROOT / "fx").glob("*.png"))]
     + ["ui/pixel/bar_hp_160x16.png", "ui/pixel/bar_mp_160x16.png",
        "ui/pixel/panel_9slice_120.png", "ui/pixel/btn_gold_normal_96x24.png",
        "ui/pixel/skill_slot_48.png", "ui/pixel/rarity_epic_48.png"], 60, 1),
    ("BACKGROUNDS  森林 / 寒霜 / 火山 / 主菜單（640x360）",
     [f"backgrounds/{p.name}" for p in sorted((ROOT / "backgrounds").glob("*.png"))], 180, 1),
]

# 渲染（超过宽度换行）
from PIL import ImageFont
try:
    font = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 22)
    font_s = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
except Exception:
    font = font_s = None

# 计算高度
sections_render = []
for title, files, cell, scale in content:
    strips = []
    cur = []
    for f in files:
        cur.append(f)
        # 简单按宽度估算
    # 直接整条，宽度超了就缩小 cell
    s = strip([ROOT / f for f in files], cell, scale)
    if s.width > W - 2 * PAD:
        # 换行
        lines = []
        line = []
        line_w = 0
        # 重建：逐个加
        tiles = []
        for f in files:
            im = Image.open(ROOT / f).convert("RGBA")
            im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
            tile = Image.new("RGBA", (cell, cell), PANEL + (255,))
            ox = (cell - im.width) // 2; oy = cell - im.height - 4
            tile.alpha_composite(im, (max(0, ox), max(0, oy)))
            tiles.append(tile)
        for t in tiles:
            if line_w + t.width > W - 2 * PAD and line:
                lines.append(line); line = []; line_w = 0
            line.append(t); line_w += t.width + 4
        if line: lines.append(line)
        for ln in lines:
            lw = sum(t.width for t in ln) + 4 * (len(ln) - 1)
            ls = Image.new("RGBA", (lw, cell), (0, 0, 0, 0))
            x = 0
            for t in ln:
                ls.alpha_composite(t, (x, 0)); x += t.width + 4
            strips.append(ls)
    else:
        strips.append(s)
    sh = sum(s.height for s in strips) + 4 * (len(strips) - 1)
    sections_render.append((title, strips, sh))

H = PAD + sum(34 + sh + 14 for _, _, sh in sections_render)
out = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(out)
y = PAD
for title, strips, sh in sections_render:
    d.text((PAD, y), title, fill=GOLD, font=font)
    y += 32
    for s in strips:
        out.paste(s.convert("RGB"), (PAD, y), s)
        y += s.height + 4
    y += 12
out.save(ROOT / "PACK_OVERVIEW.png")
print("PACK_OVERVIEW.png", out.size)
