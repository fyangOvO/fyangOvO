# -*- coding: utf-8 -*-
"""
creature_anim_gen.py —— 以已有的自有单张立绘（assets/sprites/enemies/<id>.png）为基准，
用「程序化形变」生成严格 2D 像素风的多帧动作集，落到游戏**无需改代码**即可优先读取的
`assets/pack/creatures/<id>/`，命名 char_<id>_<action>_<dir>_NN.png。

为什么这么做：
  - AI 逐帧生成无法保证同一怪物跨帧造型一致（轮廓/配色/锚点逐帧漂移），会得到抖动鬼影。
  - 以单张立绘为唯一基准做整数像素 bob / squash / 镜像 / 闪白 / 压扁淡出，
    可保证 100% 同源、像素网格对齐、版权安全。
  - 这与第三方 normalized 金标准里「立绘型」怪物（史莱姆/小鬼/蜘蛛/飞行/魔像）的做法一致：
    s 正面，e≈s，n≈s，w=镜像；人形侧身/背面不做（代码怪物侧仅请求 n/e/s/w 四方向）。

动作（每只，四方向 n/e/s/w）：idle 4 / walk 4 / attack 4 / hurt 3 / die 6 = 21 帧 × 4 方向。
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

GAME = Path(r"D:\七傳說\game")
SRC = GAME / "assets" / "sprites" / "enemies"
OUT = GAME / "assets" / "pack" / "creatures"

# 运动类型
SLIME = {"slime_acid"}
FLOAT = {"bat_swarm", "wraith_frost", "ice_wraith"}
ALL_IDS = [
    "spider_cave", "bat_swarm", "slime_acid", "skeleton_warrior",
    "mushroom_spore", "warg_dark", "imp_hellfire", "golem_ember",
    "brute_butcher", "frozen_husk", "pyromancer_cultist", "hound_ash",
    "wraith_frost", "ice_wraith", "boss_bone_tyrant", "boss_ember_lord",
]


def bbox_of(im: Image.Image):
    b = im.getbbox()
    cx = (b[0] + b[2] - 1) / 2.0
    by = b[3] - 1  # 脚底（含）
    return b, cx, by


def whiten(crop: Image.Image, k: float) -> Image.Image:
    """非透明像素朝白色混合 k（受击闪白）。"""
    if k <= 0:
        return crop
    crop = crop.copy()
    px = crop.load()
    for y in range(crop.height):
        for x in range(crop.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (
                    r + round((255 - r) * k),
                    g + round((255 - g) * k),
                    b + round((255 - b) * k),
                    a,
                )
    return crop


def morph(base: Image.Image, bbox, cx, by, sx=1.0, sy=1.0, dx=0, dy=0,
          tint=0.0, alpha=1.0, flip=False) -> Image.Image:
    """以脚底中心 (cx,by) 为锚做缩放/平移/镜像/闪白/淡入，返回与 base 同尺寸新画布。"""
    l, t, r, b = bbox
    crop = base.crop((l, t, r, b))
    if flip:
        crop = crop.transpose(Image.FLIP_LEFT_RIGHT)
    w, h = crop.size
    nw, nh = max(1, round(w * sx)), max(1, round(h * sy))
    crop = crop.resize((nw, nh), Image.NEAREST)
    crop = whiten(crop, tint)
    if alpha < 1.0:
        a = crop.split()[3].point(lambda v: int(v * alpha))
        crop.putalpha(a)
    canvas = Image.new("RGBA", base.size, (0, 0, 0, 0))
    px = round(cx - nw / 2.0 + dx)
    py = round(by + dy - nh + 1)
    canvas.alpha_composite(crop, (px, py))
    return canvas


# ---------------- 各动作帧（s 方向），返回 morph 的 kwargs 列表 ----------------
def frames_for(action: str, motion: str):
    if action == "idle":
        if motion == "float":
            return [dict(dy=0), dict(dy=-3), dict(dy=-5), dict(dy=-2)]
        if motion == "slime":
            return [dict(sx=1.0, sy=1.0, dy=0),
                    dict(sx=1.03, sy=0.95, dy=1),
                    dict(sx=1.0, sy=1.03, dy=-1),
                    dict(sx=1.0, sy=1.0, dy=0)]
        return [dict(sx=1.0, sy=1.0, dy=0),
                dict(sx=1.0, sy=1.02, dy=-1),
                dict(sx=1.0, sy=1.0, dy=0),
                dict(sx=1.0, sy=0.99, dy=1)]
    if action == "walk":
        if motion == "float":
            return [dict(dy=-1), dict(dy=-4), dict(dy=-6), dict(dy=-3)]
        if motion == "slime":
            return [dict(sx=1.08, sy=0.9, dy=2),
                    dict(sx=0.96, sy=1.07, dy=-2),
                    dict(sx=1.08, sy=0.9, dy=2),
                    dict(sx=0.96, sy=1.07, dy=-2)]
        return [dict(sx=1.0, sy=1.0, dy=0),
                dict(sx=1.02, sy=0.95, dy=-2, dx=1),
                dict(sx=1.0, sy=1.0, dy=0),
                dict(sx=1.02, sy=0.95, dy=-2, dx=-1)]
    if action == "attack":
        return [dict(sx=1.0, sy=0.96, dy=1),      # 蓄力下蹲
                dict(sx=1.05, sy=1.06, dy=-2),   # 发力上挺
                dict(sx=1.08, sy=1.04, dy=-1),   # 发力顶点
                dict(sx=1.0, sy=1.0, dy=0)]      # 回位
    if action == "hurt":
        return [dict(sy=1.02, dy=-2, tint=0.8),
                dict(sy=1.0, dy=-1, tint=0.45),
                dict(sy=1.0, dy=0, tint=0.15)]
    if action == "die":
        return [dict(sx=1.0, sy=1.0, alpha=1.0),
                dict(sx=1.04, sy=0.88, alpha=1.0),
                dict(sx=1.09, sy=0.66, alpha=0.95),
                dict(sx=1.14, sy=0.44, alpha=0.8),
                dict(sx=1.18, sy=0.24, alpha=0.55),
                dict(sx=1.2, sy=0.1, alpha=0.2)]
    raise ValueError(action)


ACTIONS = [("idle", 4), ("walk", 4), ("attack", 4), ("hurt", 3), ("die", 6)]
DIRS = ["s", "e", "w", "n"]


def gen_one(eid: str, write=True):
    if eid in SLIME:
        motion = "slime"
    elif eid in FLOAT:
        motion = "float"
    else:
        motion = "biped"
    base = Image.open(SRC / f"{eid}.png").convert("RGBA")
    bbox, cx, by = bbox_of(base)
    s_frames = {}  # action -> list[PIL]
    for action, _n in ACTIONS:
        s_frames[action] = [morph(base, bbox, cx, by, **kw) for kw in frames_for(action, motion)]

    outdir = OUT / eid
    if write:
        outdir.mkdir(parents=True, exist_ok=True)
    count = 0
    for action, _n in ACTIONS:
        seq = s_frames[action]
        for d in DIRS:
            for i, frame in enumerate(seq, start=1):
                if d == "w":
                    # 西向 = 东向（正面）水平镜像
                    im = frame.transpose(Image.FLIP_LEFT_RIGHT)
                else:
                    im = frame  # e/n 均用正面 s（与金标准立绘型一致）
                fn = f"char_{eid}_{action}_{d}_{i:02d}.png"
                if write:
                    im.save(outdir / fn)
                count += 1
    return s_frames, motion


def contact_sheet(ids, path: Path):
    """生成 s 方向动作联系表（每只一行：idle/walk/attack/hurt/die）。"""
    rows = []
    cell = 96
    for eid in ids:
        s_frames, motion = gen_one(eid, write=False)
        n = sum(n for _a, n in ACTIONS)
        rows.append((eid, motion, s_frames, n))
    ncols = max(n for _, _, _, n in rows) + 2
    W = 40 + ncols * cell
    H = 24 + len(rows) * (cell + 8)
    sheet = Image.new("RGBA", (W, H), (22, 24, 32, 255))
    dr = ImageDraw.Draw(sheet)
    for r, (eid, motion, s_frames, _n) in enumerate(rows):
        y = 24 + r * (cell + 8)
        dr.text((6, y + cell // 2 - 6), f"{eid}({motion})", fill=(210, 218, 224, 255))
        x = 8
        for action, _n in ACTIONS:
            for fr in s_frames[action]:
                z = min(cell / fr.width, cell / fr.height)
                th = max(1, round(fr.width * z))
                tv = max(1, round(fr.height * z))
                im = fr.resize((th, tv), Image.NEAREST)
                sheet.alpha_composite(im, (x + (cell - th) // 2, y + (cell - tv)))
                x += cell
    sheet.save(path)
    print("联系表", path)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "sheet":
        ids = args[1:] if len(args) > 1 else ALL_IDS
        contact_sheet(ids, Path(r"D:\七傳說\deliverables\pixel_pack_2026-09-21\previews\creatures_anim_overview.png"))
    else:
        ids = args if args else ALL_IDS
        for eid in ids:
            _f, motion = gen_one(eid)
            print(f"{eid:20s} {motion:6s} -> {OUT/eid}  ({21*4} 帧)")
