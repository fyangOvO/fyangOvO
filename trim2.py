from PIL import Image
import os
d = r'D:/七傳說/game/assets/ui/npc'
mapping = {
    'npc_merchant_raw': 'merchant_small',
    'npc_quest_raw': 'quest_small',
    'npc_guard_raw': 'guard_small',
    'npc_abyss_raw': 'abyss_small',
}
for src, out in mapping.items():
    im = Image.open(os.path.join(d, src + '.png')).convert('RGBA')
    px = im.load()
    w, h = im.size
    corners = [px[2, 2], px[w-3, 2], px[2, h-3], px[w-3, h-3]]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            br = sum(c[0] for c in corners) / 4
            bg = sum(c[1] for c in corners) / 4
            bb = sum(c[2] for c in corners) / 4
            dist = ((r-br)**2 + (g-bg)**2 + (b-bb)**2) ** 0.5
            if dist < 50:
                px[x, y] = (r, g, b, 0)
    bbox = im.getbbox()
    im = im.crop(bbox)
    im.thumbnail((120, 160), Image.NEAREST)
    im.save(os.path.join(d, out + '.png'))
    print(out, im.size)
