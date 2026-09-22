# -*- coding: utf-8 -*-
"""生成多帧动作预览 GIF（s 方向，深色底，NEAREST 放大）。"""
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from creature_anim_gen import gen_one, contact_sheet, ALL_IDS  # noqa: E402

OUT = Path(r"D:\七傳說\deliverables\pixel_pack_2026-09-21\previews")
OUT.mkdir(parents=True, exist_ok=True)
BG = (24, 26, 34, 255)


def to_gif(eid: str, acts, name: str, scale: int = 3, fps: int = 12, hold_last=0):
    sf, motion = gen_one(eid, write=False)
    frames = []
    for a in acts:
        for fr in sf[a]:
            bg = Image.new("RGBA", fr.size, BG)
            bg.alpha_composite(fr)
            bg = bg.resize((fr.width * scale, fr.height * scale), Image.NEAREST)
            frames.append(bg.convert("P", palette=Image.ADAPTIVE, colors=128))
    if hold_last and frames:
        frames += [frames[-1]] * hold_last
    p = OUT / name
    frames[0].save(p, save_all=True, append_images=frames[1:],
                   duration=int(1000 / fps), loop=0, disposal=1, optimize=True)
    print(p, len(frames), "帧")


# 静态总览
contact_sheet(ALL_IDS, OUT / "creatures_anim_overview.png")

# 4 类运动的 walk 循环
to_gif("slime_acid", ["walk"], "anim_walk_slime.gif")
to_gif("skeleton_warrior", ["walk"], "anim_walk_skeleton.gif")
to_gif("bat_swarm", ["idle", "walk"], "anim_float_bat.gif")
to_gif("warg_dark", ["walk"], "anim_walk_warg.gif")
# 完整战斗序列（攻击→受击→死亡）
to_gif("skeleton_warrior", ["attack", "hurt", "die"], "anim_combat_skeleton.gif", hold_last=6)
to_gif("boss_bone_tyrant", ["attack", "die"], "anim_combat_boss.gif", scale=2, hold_last=6)
