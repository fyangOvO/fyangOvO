# -*- coding: utf-8 -*-
"""按钮三态生成（**包风格 × 游戏尺寸**）。

## 为什么有这个脚本
用户的像素素材包 `ui/`（原 `deliverables/pixel_pack_2026-09-21/`，2026-09-22 更名歸位，內容逐位元組相同）里按钮是 **96×24**，
但本游戏的封面内容区宽 296px，96×24 @2× = 192×48 会在左右各空 52px，读成「按钮太窄」
（2026-09-21 设计顾问实测裁定，见 `deliverables/gstack/design-cover-level1-final-2026-09-21.md` §3 C6）。
本游戏用的是 **128×24 @2× = 256×48**。

⇒ 这里**逐行照搬**包内 `ui_pixel_gen.py` 的 `make_buttons()` 几何与配色，
只把宽度由 96 改成 128。**不是重新设计，是同一个设计换个宽度。**
包里其余 UI 件（面板 / 血蓝条 / 槽位 / 稀有度 / 技能槽）尺寸与游戏一致，
由 `apply_pack_ui.py` 直接同名拷贝，**不由本脚本生成**。

## 输出
`game/assets/ui/quest/btn_{gold,dark}_{normal,hover,pressed}_128x24.png`

## 铁律
配色全部取自 `game_constants.gd` 的 44 色 `PALETTE_ALL`（包内硬编码常量与本项目色板同源）。
alpha 二值（0/255），无半透明、无抗锯齿。
"""
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "assets", "ui", "quest")

## 游戏尺寸（包内为 96）。改这个值必须同步改：
##   · `game/scripts/ui/main_menu_panel.gd` 的 `BTN_SIZE`
##   · `game/tools/verify_ui_assets.gd` 的 `EXPECT_TEX` 与 `BTN_SIZE` 断言
BTN_W = 128
BTN_H = 24


def C(h: str):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ── 44 色板（与包内 ui_pixel_gen.py 逐字相同，亦与 game_constants.gd 同源）────────
INK = C("0B0D10")
WELL = C("14171C")
SLATE = C("1E232B")
SLATE_H = C("2A313B")
EDGE = C("3A424F")
EDGE_H = C("4E5866")
GREY = C("6B7688")
LGREY = C("8C97A8")
TEXT = C("B3BCC9")
WHITE = C("DCE2E8")
WARM = C("DBCC85")

GOLD_D, GOLD_M, GOLD, GOLD_H = C("4A3208"), C("8C6510"), C("D9A521"), C("F5D77A")


def img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c + (255,))


def make_button(scheme: str, state: str) -> Image.Image:
    """逐行照搬包内 make_buttons().one()，仅 W 由 96 → 128。"""
    W, H = BTN_W, BTN_H
    im = img(W, H)
    if scheme == "gold":
        base, hi, lo, edge = GOLD_M, GOLD_H, GOLD_D, GOLD_D
    else:
        base, hi, lo, edge = SLATE, SLATE_H, INK, EDGE
    # 按下态整体压暗 + 下移高光
    if state == "pressed":
        base = lo if scheme == "gold" else SLATE
        hi = GOLD_M if scheme == "gold" else EDGE

    x0, y0, x1, y1 = 2, 3, W - 3, H - 4
    cut = 5
    # 主体（斜切角：左上 / 右下各切 cut 像素）
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x - x0) + (y - y0) < cut:
                continue
            if (x1 - x) + (y1 - y) < cut:
                continue
            px(im, x, y, base)
    # 顶部高光条（2px）
    for x in range(x0 + cut, x1 - cut + 1):
        px(im, x, y0 + 1, hi)
        if state != "pressed":
            px(im, x, y0 + 2, hi)
    # 底部暗影条
    for x in range(x0 + cut, x1 - cut + 1):
        px(im, x, y1, lo)
    # 描边（对每个不透明像素检查四邻，贴透明边者上描边色）
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if im.getpixel((x, y))[3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and im.getpixel((nx, ny))[3] == 0:
                    px(im, x, y, edge)
                    break
    # 悬停态：内侧加一圈亮边
    if state == "hover":
        for x in range(x0 + cut, x1 - cut + 1):
            px(im, x, y0 + 3, WHITE if scheme == "gold" else EDGE_H)
    return im


def palette() -> set:
    src = open(os.path.join(ROOT, "game", "scripts", "core", "game_constants.gd"),
               encoding="utf-8").read()
    pal = set()
    for n in ("PALETTE_NEUTRAL", "PALETTE_ACCENT", "PALETTE_RARITY_SEMANTIC"):
        m = re.search(re.escape(n) + r"\s*:\s*Array\[Color\]\s*=\s*\[(.*?)\n\]", src, re.S)
        if m:
            pal |= {c.upper() for c in re.findall(r'Color\("([0-9A-Fa-f]{6})"\)', m.group(1))}
    return pal


def main() -> int:
    pal = palette()
    print("PALETTE_ALL = %d 色" % len(pal))
    os.makedirs(OUT, exist_ok=True)
    bad_total = 0
    for scheme in ("gold", "dark"):
        for state in ("normal", "hover", "pressed"):
            im = make_button(scheme, state)
            name = "btn_%s_%s_%dx%d.png" % (scheme, state, BTN_W, BTN_H)
            im.save(os.path.join(OUT, name))
            # ⚠️ 色板集合里的条目**不带** `#` 前缀 —— 必须同样不带 `#` 比较
            bad = sorted({"%02X%02X%02X" % c[:3] for c in im.getdata()
                          if c[3] > 0 and "%02X%02X%02X" % c[:3] not in pal})
            bad_total += len(bad)
            print("  %-32s %-9s 出板色 %s" % (name, str(im.size), bad if bad else "无"))
    print()
    print("出板色总数 = %d（必须为 0）" % bad_total)
    return 0 if bad_total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
