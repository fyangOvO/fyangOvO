# -*- coding: utf-8 -*-
"""合成 640×360 实战游戏画面：三职业 vs 怪物 + 技能特效 + HUD。"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).parent
SCALE = 2  # 输出 2x 便于查看


def L(rel, h=None):
    im = Image.open(ROOT / rel).convert("RGBA")
    if h:
        w = round(im.width * h / im.height)
        im = im.resize((w, h), Image.NEAREST)
    return im


def build():
    bg = L("backgrounds/backdrop_forest_640x360.png").convert("RGBA")
    W, H = 640, 360
    scene = bg.copy()

    def place(rel, x, baseline, h):
        im = L(rel, h)
        scene.alpha_composite(im, (x - im.width // 2, baseline - im.height))

    # 怪物（前方=画面上方一排）
    place("monsters/imp_volcanic/mon_imp_volcanic_attack_s_03.png", 95, 205, 72)
    place("monsters/slime_forest/mon_slime_forest_idle_s_02.png", 215, 218, 52)
    place("monsters/skeleton/mon_skeleton_attack_s_02.png", 330, 210, 84)
    place("monsters/slime_frost/mon_slime_frost_idle_s_01.png", 445, 220, 52)
    place("monsters/slime_forest/mon_slime_forest_idle_s_03.png", 555, 215, 50)

    # 技能特效（命中怪物位置，画面中部）
    fx_fire = L("anim/fireburst/fx_fireburst_06.png", 56)
    scene.alpha_composite(fx_fire, (67, 158))
    fx_slash = L("anim/slash/fx_slash_05.png", 72)
    scene.alpha_composite(fx_slash, (294, 130))
    fx_frost = L("anim/frostnova/fx_frostnova_06.png", 60)
    scene.alpha_composite(fx_frost, (415, 150))

    # 三职业（玩家，画面下方，避开底部技能栏 y=304）
    place("characters/char_mage_idle_s_01.png", 140, 296, 96)
    place("characters/char_warrior_idle_s_01.png", 320, 300, 102)
    place("characters/char_archer_idle_s_01.png", 500, 296, 96)

    # ---- HUD ----
    # 顶部血蓝条（两条）
    hp = L("ui/pixel/bar_hp_160x16.png", 16)
    mp = L("ui/pixel/bar_mp_160x16.png", 16)
    scene.alpha_composite(hp, (12, 12))
    scene.alpha_composite(mp, (12, 32))
    # 玩家头像（用战士 idle 缩小）
    face = L("characters/char_warrior_idle_s_01.png", 48)
    slot = L("ui/pixel/slot_normal_48.png", 48)
    scene.alpha_composite(slot, (14, 54))
    scene.alpha_composite(face, (14, 54))

    # 底部技能栏（4 技能图标 + 普通攻击槽）
    skills = ["skill_slash_48.png", "skill_fireburst_48.png",
              "skill_frostnova_48.png", "skill_shadowdash_48.png"]
    bx = 640 // 2 - (48 * 4 + 6 * 3) // 2
    for i, s in enumerate(skills):
        icon = L(f"ui/skill_icons/{s}", 48)
        scene.alpha_composite(icon, (bx + i * 54, 360 - 48 - 8))

    # 右上小面板（任务/数值占位）
    panel = L("ui/pixel/panel_9slice_120.png", 110)
    panel = panel.resize((150, 70), Image.NEAREST)
    scene.alpha_composite(panel, (640 - 158, 10))

    # 稀有度槽（右下装备占位）
    for i, r in enumerate(["rarity_common_48.png", "rarity_rare_48.png",
                           "rarity_epic_48.png", "rarity_legend_48.png"]):
        rs = L(f"ui/pixel/{r}", 34)
        scene.alpha_composite(rs, (640 - 150 + i * 36, 88))

    # 输出 1x 与 2x
    scene.convert("RGB").save(ROOT / "scene_preview_640x360.png")
    big = scene.resize((W * SCALE, H * SCALE), Image.NEAREST)
    big.convert("RGB").save(ROOT / "scene_preview_2x.png")
    print("scene_preview 640x360 + 2x 已生成")


if __name__ == "__main__":
    build()
