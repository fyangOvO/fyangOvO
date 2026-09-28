from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math
import random

ROOT = Path(r"D:\七傳說")
ASSETS = ROOT / "game" / "assets"
OUT = ROOT / "deliverables" / "gstack" / "策划案" / "character_attack_preview_v1.gif"


def frames(path: Path):
    im = Image.open(path)
    result = []
    for i in range(getattr(im, "n_frames", 1)):
        im.seek(i)
        fr = im.convert("RGBA")
        key = fr.getpixel((0, 0))[:3]
        px = fr.load()
        for y in range(fr.height):
            for x in range(fr.width):
                r, g, b, a = px[x, y]
                if abs(r-key[0]) <= 9 and abs(g-key[1]) <= 9 and abs(b-key[2]) <= 9:
                    px[x, y] = (r, g, b, 0)
        result.append(fr)
    return result


def draw_pixel_sprite(dst, src, x, y, size, white_flash=False):
    sprite = src.resize((size, size), Image.Resampling.NEAREST)
    if white_flash:
        sprite = Image.eval(sprite, lambda c: c)
        p = sprite.load()
        for yy in range(sprite.height):
            for xx in range(sprite.width):
                r, g, b, a = p[xx, yy]
                if a:
                    p[xx, yy] = (min(255, max(r, g, b)+75), min(255, max(r, g, b)+75), min(255, max(r, g, b)+75), a)
    dst.alpha_composite(sprite, (x, y))


bg = Image.open(ASSETS / "backgrounds" / "backdrop_forest_640x360.png").convert("RGBA")
warriors = frames(ASSETS / "previews" / "warrior_attack_s.gif")
enemies = frames(ASSETS / "previews" / "skeleton_attack.gif")
slashes = frames(ASSETS / "anim" / "slash.gif")
bursts = frames(ASSETS / "anim" / "fireburst.gif")
font_path = Path(r"C:\Windows\Fonts\msyh.ttc")
title_font = ImageFont.truetype(str(font_path), 18)
label_font = ImageFont.truetype(str(font_path), 12)
result = []

for i in range(16):
    canvas = bg.copy()
    shade = Image.new("RGBA", canvas.size, (7, 10, 17, 48))
    canvas.alpha_composite(shade)
    draw = ImageDraw.Draw(canvas, "RGBA")

    # The warrior advances into a four-frame sword swing.
    widx = min(len(warriors)-1, (i * len(warriors)) // 16)
    draw_pixel_sprite(canvas, warriors[widx], 190, 88, 174)
    # The skeleton recoils and flashes on impact.
    eidx = (i // 4) % len(enemies)
    recoil = 10 if 7 <= i <= 10 else (4 if 11 <= i <= 12 else 0)
    draw_pixel_sprite(canvas, enemies[eidx], 346 + recoil, 112, 145, 7 <= i <= 9)

    if 4 <= i <= 12:
        sx = 279 + max(0, i-7)*4
        draw_pixel_sprite(canvas, slashes[(i-4) % len(slashes)], sx, 116, 112)
    if 7 <= i <= 9:
        draw_pixel_sprite(canvas, bursts[(i-7) % len(bursts)], 365, 146, 72)

    # Expanding dust and crisp pixel sparks sell the contact and weight.
    draw = ImageDraw.Draw(canvas, "RGBA")
    if 3 <= i <= 13:
        radius = 12 + (i-3)*4
        alpha = max(0, 145 - (i-3)*13)
        draw.ellipse((370-radius, 244-radius//3, 370+radius, 244+radius//3), outline=(142, 193, 213, alpha), width=2)
    if 6 <= i <= 11:
        rng = random.Random(551 + i)
        for _ in range(24):
            x = rng.randint(354, 432)
            y = rng.randint(139, 214)
            length = rng.randint(3, 10)
            color = rng.choice([(255, 240, 164, 255), (181, 226, 255, 255), (255, 255, 232, 255)])
            draw.line((x, y, x+length, y-rng.randint(-5, 5)), fill=color, width=2)
    for p in range(6):
        phase = (i + p*2) % 16
        r = 3 + min(8, phase)
        alpha = max(0, 105 - phase*7)
        if alpha:
            x = 211 + p*7
            draw.ellipse((x-r//2, 254-r//4, x+r//2, 254+r//4), fill=(172, 178, 154, alpha))

    draw.rectangle((18, 18, 621, 341), outline=(212, 192, 126, 225), width=2)
    draw.text((32, 28), "戰士攻擊  ·  揮劍命中", font=title_font, fill=(250, 248, 238, 255), stroke_width=1, stroke_fill=(15, 20, 29, 255))
    draw.text((32, 316), f"攻擊動作 / 斬擊弧光 / 命中閃白 / 火花回饋   {i+1}/16", font=label_font, fill=(225, 230, 233, 255), stroke_width=1, stroke_fill=(15, 20, 29, 255))
    result.append(canvas.convert("RGB"))

result[0].save(OUT, save_all=True, append_images=result[1:], duration=90, loop=0, optimize=True, disposal=2)
print(OUT)
