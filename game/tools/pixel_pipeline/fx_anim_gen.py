# -*- coding: utf-8 -*-
"""像素技能特效序列帧动画生成器。

基于静态 96×96 特效帧，用整数像素变换（NEAREST 缩放/位移/裁剪）生成
严谨像素风的序列帧动画，输出：
  anim/<skill>/fx_<skill>_NN.png   透明底序列帧（游戏用，alpha 二值）
  anim/<skill>.gif                  深色底预览 GIF（循环）
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).parent
FX = ROOT / "fx"
ANIM = ROOT / "anim"
ANIM.mkdir(parents=True, exist_ok=True)
CANVAS = 96


def load(name):
    return Image.open(FX / name).convert("RGBA")


def blank():
    return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))


def place_scaled(base, sprite, cx, cy, scale, alpha=255):
    """以 (cx,cy) 为中心整数倍/比例缩放（NEAREST）后贴到 base，scale 按 1/4 粒度。"""
    if scale <= 0:
        return
    # 量化到 0.25 倍数，保持像素网格稳定
    scale = round(scale * 4) / 4
    w = max(1, round(sprite.width * scale))
    h = max(1, round(sprite.height * scale))
    sp = sprite.resize((w, h), Image.NEAREST)
    if alpha < 255:
        a = sp.split()[3].point(lambda v: int(v * alpha / 255))
        sp.putalpha(a)
    base.alpha_composite(sp, (int(cx - w / 2), int(cy - h / 2)))


def binarize(im, thresh=96):
    """alpha 二值化（游戏序列帧：硬边）。"""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255 if a >= thresh else 0)
    return im


def save_frames(name, frames, loop=True):
    d = ANIM / name
    d.mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(frames):
        binarize(f.copy()).save(d / f"fx_{name}_{i:02d}.png")
    # 深色底预览 GIF
    bg = Image.new("RGBA", (CANVAS, CANVAS), (16, 18, 22, 255))
    gifs = []
    for f in frames:
        c = bg.copy(); c.alpha_composite(f); gifs.append(c.convert("P", palette=Image.ADAPTIVE))
    gif = ANIM / f"{name}.gif"
    gifs[0].save(gif, save_all=True, append_images=gifs[1:], duration=70,
                 loop=0 if loop else 1, disposal=2)
    print(f"{name}: {len(frames)} 帧 -> {d}  + {gif.name}")


# ── 1. 剑气斩：月牙向右飞出（9帧）───────────────────────────────────────
def anim_slash():
    src = load("fx_slash_px96.png")
    frames = []
    for i in range(9):
        b = blank()
        # 前 3 帧：在左侧展开（scale 0.5→1）；后 6 帧：向右飞 + 淡出
        if i < 3:
            sc = 0.5 + i * 0.25
            x = 30 + i * 6
            a = 255
        else:
            sc = 1.0
            x = 30 + 18 + (i - 3) * 12
            a = max(0, 255 - (i - 3) * 45)
        place_scaled(b, src, x, 48, sc, a)
        frames.append(b)
    save_frames("slash", frames)


# ── 2. 火焰爆发：中心放大→消散（10帧）──────────────────────────────────
def anim_fire():
    src = load("fx_fire_px96.png")
    frames = []
    for i in range(10):
        b = blank()
        if i < 4:           # 爆起：0.3→1.15，中心略下移（地面）
            sc = 0.3 + i * 0.28
            a = 255
        elif i < 7:         # 全盛：1.15，轻微上抬
            sc = 1.15
            a = 255
        else:               # 消散：缩小上升 + 淡出
            sc = 1.15 - (i - 6) * 0.15
            a = max(0, 255 - (i - 6) * 80)
        y = 52 + (i - 6) * 2 if i >= 7 else 52
        place_scaled(b, src, 48, y, sc, a)
        frames.append(b)
    save_frames("fireburst", frames)


# ── 3. 冰霜新星：冰环向外扩散（10帧）──────────────────────────────────
def anim_frost():
    src = load("fx_frost_px96.png")
    frames = []
    for i in range(10):
        b = blank()
        if i < 2:           # 中心亮点
            sc = 0.3 + i * 0.2
            a = 255
        else:               # 环扩散：0.7→1.9 + 淡出
            sc = 0.7 + (i - 2) * 0.15
            a = max(0, 255 - (i - 2) * 30)
        place_scaled(b, src, 48, 48, sc, a)
        frames.append(b)
    save_frames("frostnova", frames)


# ── 4. 落雷：自顶劈下 + 命中闪光（9帧）─────────────────────────────────
def anim_thunder():
    src = load("fx_thunder_px96.png")
    frames = []
    W, H = src.size
    for i in range(9):
        b = blank()
        if i < 4:           # 闪电从上到下揭示（裁剪高度）
            reveal = int(H * (i + 1) / 4)
            clip = src.crop((0, 0, W, reveal))
            b.alpha_composite(clip, (0, 0))
            a = 255
        elif i < 6:         # 命中全亮 + 白光
            b.alpha_composite(src, (0, 0))
            # 中心加白闪
            for y in range(40, 58):
                for x in range(40, 58):
                    if (x - 48) ** 2 + (y - 48) ** 2 < 80:
                        b.putpixel((x, y), (220, 236, 248, 255))
        else:               # 快速消散
            a = max(0, 255 - (i - 5) * 90)
            sp = src.copy()
            sp.putalpha(src.split()[3].point(lambda v: int(v * a / 255)))
            b.alpha_composite(sp, (0, 0))
        frames.append(b)
    save_frames("thunder", frames)


def main():
    anim_slash()
    anim_fire()
    anim_frost()
    anim_thunder()
    print("全部序列帧动画完成。")


if __name__ == "__main__":
    main()
