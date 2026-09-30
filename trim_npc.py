from PIL import Image
import os
d = r'D:/七傳說/game/assets/ui/npc'
for f in ['smith', 'tailor', 'gem', 'master']:
    src = os.path.join(d, f + '_raw.png')
    if not os.path.exists(src):
        src = os.path.join(d, f + '.png')
    im = Image.open(src).convert('RGBA')
    px = im.load()
    w, h = im.size
    # 採角邊色當背景色
    corners = [px[2, 2], px[w-3, 2], px[2, h-3], px[w-3, h-3]]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            # 與四角平均色距離近 → 透明
            br = sum(c[0] for c in corners) / 4
            bg = sum(c[1] for c in corners) / 4
            bb = sum(c[2] for c in corners) / 4
            dist = ((r-br)**2 + (g-bg)**2 + (b-bb)**2) ** 0.5
            if dist < 60:
                px[x, y] = (r, g, b, 0)
    bbox = im.getbbox()
    im = im.crop(bbox)
    im.thumbnail((120, 160), Image.NEAREST)
    im.save(os.path.join(d, f + '_small.png'))
    print(f, im.size)
