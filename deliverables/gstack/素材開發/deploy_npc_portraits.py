# -*- coding: utf-8 -*-
"""七傳說 營地 NPC 對話立繪補產（4 個缺失：技能師/守塔人/深淵使者/套裝師）
輸出：game/assets/ui/quest/npc/portrait_{quest,guard,abyss,merchant}_48.png（48×48 RGBA）
風格：像素頭肩像，深色描邊 + 兩三調皮膚/衣色，與既有 portrait_*_48 同構。
鐵律：NEAREST、不旋轉、透明底。
"""
import os
from PIL import Image

OUT_DIR = r"D:\七傳說\game\assets\ui\quest\npc"
S = 48

# 通用配色
SKIN = (242, 200, 160)
SKIN_D = (200, 156, 120)
OUTLINE = (36, 24, 18)
HAIR_D = (70, 52, 38)
HAIR_L = (110, 84, 58)


def new() -> Image.Image:
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def px(im, x, y, c):
    if 0 <= x < S and 0 <= y < S:
        im.putpixel((int(x), int(y)), c)


def rect(im, x, y, w, h, c):
    for j in range(int(h)):
        for i in range(int(w)):
            px(im, x + i, y + j, c)


def ellipse(im, cx, cy, rx, ry, c):
    for j in range(-ry, ry + 1):
        for i in range(-rx, rx + 1):
            if (i * i) / (rx * rx) + (j * j) / (ry * ry) <= 1.0:
                px(im, cx + i, cy + j, c)


def _base_head(im):
    """共通：臉 + 頸 + 肩底。頭中心 (24,20)，肩 (24,36)。"""
    # 肩（寬 34×8）
    rect(im, 7, 34, 34, 8, (86, 74, 62))       # 深色基底
    rect(im, 9, 36, 30, 5, (124, 108, 90))     # 亮色肩
    # 頸
    rect(im, 21, 27, 6, 6, SKIN_D)
    # 臉（橢圓 16×14）
    ellipse(im, 24, 19, 8, 7, SKIN)
    # 臉高光左
    ellipse(im, 22, 17, 3, 3, (252, 222, 184))
    # 眼睛（兩顆暗點）+ 眉毛
    px(im, 21, 18, OUTLINE)
    px(im, 26, 18, OUTLINE)


def _frame(im):
    """外框深描邊：掃一圈非透明邊緣像素旁的透明位置補 1px 描邊"""
    for y in range(S):
        for x in range(S):
            if im.getpixel((x, y))[3] > 0:
                continue
            hit = False
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < S and 0 <= ny < S and im.getpixel((nx, ny))[3] > 0:
                        hit = True
                        break
                if hit:
                    break
            if hit:
                px(im, x, y, OUTLINE)


def draw_quest():
    """技能師：綠色兜帽 + 露臉 + 弓手肩飾（綠）"""
    im = new()
    _base_head(im)
    # 綠色兜帽（帽頂圓弧覆蓋頭上部）
    ellipse(im, 24, 14, 9, 7, (58, 118, 76))
    rect(im, 15, 14, 18, 5, (58, 118, 76))
    # 帽檐（前額暗帶）
    rect(im, 16, 18, 16, 2, (38, 84, 54))
    # 兜帽兩側垂布
    rect(im, 13, 20, 3, 10, (48, 96, 64))
    rect(im, 32, 20, 3, 10, (48, 96, 64))
    # 肩飾（弓尾/綠披）
    rect(im, 6, 32, 5, 10, (70, 130, 86))
    rect(im, 37, 32, 5, 10, (70, 130, 86))
    # 眼睛 + 眉毛（綠帽下）
    px(im, 21, 21, OUTLINE)
    px(im, 26, 21, OUTLINE)
    rect(im, 20, 19, 2, 1, (30, 60, 40))
    rect(im, 26, 19, 2, 1, (30, 60, 40))
    _frame(im)
    return im


def draw_guard():
    """守塔人：金色全罩盔（只露眼縫）+ 金肩甲"""
    im = new()
    _base_head(im)
    # 金頭盔（覆蓋整個頭，圓頂）
    ellipse(im, 24, 17, 9, 8, (198, 156, 84))
    rect(im, 15, 17, 18, 6, (198, 156, 84))
    # 盔沿
    rect(im, 14, 22, 20, 2, (150, 116, 58))
    # 眼縫（暗紫）
    rect(im, 19, 19, 10, 2, (70, 60, 46))
    px(im, 21, 19, (220, 190, 110))
    px(im, 26, 19, (220, 190, 110))
    # 盔頂羽飾（紅）
    rect(im, 23, 6, 3, 6, (180, 74, 66))
    rect(im, 22, 5, 5, 2, (210, 100, 84))
    # 金肩甲
    ellipse(im, 13, 35, 8, 4, (198, 156, 84))
    ellipse(im, 35, 35, 8, 4, (198, 156, 84))
    rect(im, 7, 34, 34, 2, (150, 116, 58))
    _frame(im)
    return im


def draw_abyss():
    """深淵使者：暗紫兜帽遮臉（僅眼縫幽光）+ 暗紫斗篷肩"""
    im = new()
    _base_head(im)
    # 覆蓋臉的暗紫兜帽
    ellipse(im, 24, 16, 10, 9, (74, 56, 104))
    rect(im, 14, 16, 20, 8, (74, 56, 104))
    # 兜帽內緣（黑）
    rect(im, 16, 20, 16, 4, (22, 16, 34))
    # 眼縫幽光（青紫）
    rect(im, 19, 20, 10, 2, (150, 120, 220))
    px(im, 22, 21, (210, 190, 255))
    px(im, 25, 21, (210, 190, 255))
    # 斗篷肩（大）
    ellipse(im, 13, 36, 9, 5, (60, 44, 88))
    ellipse(im, 35, 36, 9, 5, (60, 44, 88))
    rect(im, 6, 34, 36, 3, (74, 56, 104))
    _frame(im)
    return im


def draw_merchant():
    """套裝師（商人）：卷髮 + 頭巾/帽 + 金幣肩飾（黃）"""
    im = new()
    _base_head(im)
    # 髮（棕色卷髮，蓋頭上半）
    ellipse(im, 24, 15, 9, 7, HAIR_D)
    rect(im, 15, 15, 18, 4, HAIR_D)
    rect(im, 13, 18, 4, 6, HAIR_L)
    rect(im, 31, 18, 4, 6, HAIR_L)
    # 頭巾帶（前額金帶）
    rect(im, 14, 19, 20, 2, (208, 170, 90))
    # 腮幫（絡腮鬍）
    rect(im, 15, 22, 4, 4, HAIR_D)
    rect(im, 29, 22, 4, 4, HAIR_D)
    # 眼睛
    px(im, 21, 20, OUTLINE)
    px(im, 26, 20, OUTLINE)
    # 金幣肩飾（兩側黃圓）
    ellipse(im, 10, 35, 4, 4, (216, 176, 92))
    ellipse(im, 38, 35, 4, 4, (216, 176, 92))
    rect(im, 9, 34, 3, 1, (240, 210, 130))
    rect(im, 37, 34, 3, 1, (240, 210, 130))
    _frame(im)
    return im


def main():
    makers = {
        "portrait_quest_48": draw_quest,
        "portrait_guard_48": draw_guard,
        "portrait_abyss_48": draw_abyss,
        "portrait_merchant_48": draw_merchant,
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, maker in makers.items():
        maker().save(os.path.join(OUT_DIR, "%s.png" % name))
        print(name, "done")


if __name__ == "__main__":
    main()
