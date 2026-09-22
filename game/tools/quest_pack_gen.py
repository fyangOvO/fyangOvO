# -*- coding: utf-8 -*-
"""任務背景場景 UI + 裝備圖標 像素素材生成器（七傳說美術規範合規）。

设计原则（与 tools/tiles_quantize.py 同一血统）：
1. **色板从 game_constants.gd 现读**，不硬编码 —— 唯一色源铁律。
2. 所有像素构造性合规：只使用 PALETTE_ALL 内颜色，alpha 二值（0/255）。
3. 整数像素绘制，无平滑缩放；图标 24×24 手绘网格 ×2 → 48×48（对齐 UI_SLOT_SIZE_BAG）。

产出
----
  game/assets/ui/quest/           任务面板 UI（9-slice / 横幅 / 按钮 / 槽位 / 星级 / 分隔线 / 标记）
  game/assets/ui/quest/backdrops/ 三生态任务背景（640×360，对齐视口）
  game/assets/icons/equipment/    48×48 装备图标 ×12
  deliverables/quest_ui_equipment_pack_2026-09-21/  预览合成图 + 本说明

用法
----
    python game/tools/quest_pack_gen.py            # 生成 + 自校验
    python game/tools/quest_pack_gen.py --dry-run  # 只校验已有产物，不重绘
"""
from __future__ import annotations

import argparse
import os
import re
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("需要 Pillow：pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONSTANTS = os.path.join(ROOT, "game", "scripts", "core", "game_constants.gd")
OUT_UI = os.path.join(ROOT, "game", "assets", "ui", "quest")
OUT_BG = os.path.join(OUT_UI, "backdrops")
OUT_ICON = os.path.join(ROOT, "game", "assets", "icons", "equipment")
OUT_PREVIEW = os.path.join(ROOT, "deliverables", "quest_ui_equipment_pack_2026-09-21")

# ---------------------------------------------------------------- 色板现读
def load_palette() -> dict[str, tuple[int, int, int]]:
    """只取 PALETTE_NEUTRAL/ACCENT/RARITY_SEMANTIC 三数组（= PALETTE_ALL 44 色），不碰 UI 常量。"""
    text = open(CONSTANTS, encoding="utf-8").read()
    blob = "\n".join(re.findall(
        r"const PALETTE_(?:NEUTRAL|ACCENT|RARITY_SEMANTIC): Array\[Color\] = \[(.*?)\]",
        text, re.S))
    hexes = re.findall(r'Color\("([0-9A-Fa-f]{6})"\)', blob)
    return {h.upper(): tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in hexes}


PAL = load_palette()
ALPHA_ON = (PAL["0B0D10"][0], PAL["0B0D10"][1], PAL["0B0D10"][2], 255)
TRANS = (0, 0, 0, 0)


def C(key: str) -> tuple[int, ...]:
    return PAL[key.upper()]


# ---------------------------------------------------------------- 绘制助手
def new(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), TRANS)


def px(d: ImageDraw.ImageDraw, x: int, y: int, c) -> None:
    d.point((x, y), fill=c)


def rect(d, x0, y0, x1, y1, c) -> None:  # 闭区间填充
    d.rectangle([x0, y0, x1, y1], fill=c)


def frame(d, x0, y0, x1, y1, c) -> None:  # 闭区间 1px 描边
    d.rectangle([x0, y0, x1, y1], outline=c)


def dither_row(d, y, x0, x1, c) -> None:  # 2px 棋盘抖动行（带间过渡）
    for x in range(x0, x1 + 1):
        if (x // 2 + y // 2) % 2 == 0:
            px(d, x, y, c)


# ================================================================ 任务 UI
def quest_panel(size: int = 120) -> Image.Image:
    """9-slice 任务面板底：外 1px 近黑硬描边 → 1px 边框 → 面板底；金铆钉四角。9-slice 边距 8。"""
    img = new(size, size)
    d = ImageDraw.Draw(img)
    rect(d, 0, 0, size - 1, size - 1, C("0B0D10"))          # 硬描边
    rect(d, 1, 1, size - 2, size - 2, C("14171C"))          # 面板底
    frame(d, 1, 1, size - 2, size - 2, C("3A424F"))         # 边框
    px_rect = d
    # 顶部 1px 高光（面板顶线规范）
    rect(d, 2, 2, size - 3, 2, C("4E5866"))
    # 内圈微渐变：靠边一圈压深，制造厚度（仍在中性基底内）
    frame(d, 3, 3, size - 4, size - 4, C("1E232B"))
    # 四角金铆钉（2×2，含 1px 描边）
    for cx, cy in ((4, 4), (size - 7, 4), (4, size - 7), (size - 7, size - 7)):
        rect(d, cx, cy, cx + 2, cy + 2, C("8C6510"))
        px(d, cx + 1, cy, C("D9A521"))
        px(d, cx, cy + 1, C("D9A521"))
    # 角部 45° 切角（像素风硬切）
    px(d, 0, 0, TRANS); px(d, size - 1, 0, TRANS)
    px(d, 0, size - 1, TRANS); px(d, size - 1, size - 1, TRANS)
    return img


def quest_banner(w: int = 256, h: int = 48) -> Image.Image:
    """标题横幅：暗底 + 上下金饰线 + 两端菱形饰件，中段留白给字体。"""
    img = new(w, h)
    d = ImageDraw.Draw(img)
    rect(d, 0, 4, w - 1, h - 5, C("0B0D10"))                # 硬描边底
    rect(d, 1, 5, w - 2, h - 6, C("14171C"))                # 横幅底
    rect(d, 2, 6, w - 3, 6, C("D9A521"))                    # 上金线
    rect(d, 2, 6, w - 3, 6, C("D9A521"))
    px(d, 2, 6, C("F5D77A")); px(d, w - 3, 6, C("F5D77A"))
    rect(d, 2, h - 7, w - 3, h - 7, C("8C6510"))            # 下金线（暗）
    rect(d, 2, 7, w - 3, 7, C("F5D77A"))                    # 金线上侧高光
    frame(d, 1, 5, w - 2, h - 6, C("3A424F"))
    rect(d, 2, 8, w - 3, h - 8, C("14171C"))
    # 两端菱形饰件（中心 h/2）
    cy = h // 2
    for cx in (10, w - 11):
        r = 6
        for i in range(r + 1):
            rect(d, cx - (r - i), cy - i, cx + (r - i), cy - i, C("0B0D10"))
        for i in range(r):
            col = C("D9A521") if i < 3 else C("8C6510")
            rect(d, cx - (r - 1 - i), cy - i, cx + (r - 1 - i), cy - i, col)
            if i < r - 1 - i:
                rect(d, cx - (r - 1 - i), cy + i + 1, cx + (r - 1 - i), cy + i + 1, col)
        px(d, cx, cy - r + 1, C("F5D77A"))
    return img


def quest_button(w: int, h: int, style: str, state: str) -> Image.Image:
    """按钮三态。style: gold(主)/dark(次)；state: normal/hover/pressed。像素铁律：1px 深描边。

    ⚠️ 显示尺寸 **128×24**（规范 §3 C6）：旧版 96×24 在 2× 下只有 192px 宽，
    在 296px 的内容区里左右各空 52px（读成「按钮太窄」）。改 128 ⇒ 2× = 256px，
    左右各留 20px。**高度仍 24**（2× = 48），内容总高不变。
    """
    img = new(w, h)
    d = ImageDraw.Draw(img)
    if style == "gold":
        fill = {"normal": "D9A521", "hover": "F5D77A", "pressed": "8C6510"}[state]
        hi = {"normal": "F5D77A", "hover": "F5D77A", "pressed": "D9A521"}[state]
        lo = {"normal": "8C6510", "hover": "D9A521", "pressed": "4A3208"}[state]
        border = "0B0D10" if state != "pressed" else "4A3208"
    else:
        fill = {"normal": "1E232B", "hover": "2A313B", "pressed": "14171C"}[state]
        hi = {"normal": "4E5866", "hover": "6B7688", "pressed": "3A424F"}[state]
        lo = {"normal": "14171C", "hover": "1E232B", "pressed": "0B0D10"}[state]
        border = "0B0D10"
    b = 2 if state == "pressed" else 1  # pressed 2px 描边（与 UI_CHOICE_BTN 规范一致）
    rect(d, 0, 0, w - 1, h - 1, C(border))
    rect(d, b, b, w - 1 - b, h - 1 - b, C(fill))
    rect(d, b, b, w - 1 - b, b + 1, C(hi))                  # 顶部 2px 高光
    rect(d, b, h - 2 - b, w - 1 - b, h - 1 - b, C(lo))      # 底部压暗
    # pressed 时内容区整体下沉 1px（像素按压感）
    if state == "pressed":
        rect(d, b, b, w - 1 - b, b, C(fill))
        px(d, b, b, C(fill)); px(d, w - 1 - b, b, C(fill))
    return img


def slot_frame(kind: str = "normal") -> Image.Image:
    """48×48 物品格。normal/selected/rarity×5。"""
    s = 48
    img = new(s, s)
    d = ImageDraw.Draw(img)
    border = {
        "normal": "3A424F", "selected": "D9A521",
        "common": "C9D1D9", "rare": "4C8BF5", "epic": "F5C542",
        "legend": "A96BFF", "orange": "FF8A2B",
    }[kind]
    hi = "F5D77A" if kind in ("selected",) else ("6B7688" if kind == "normal" else border)
    rect(d, 0, 0, s - 1, s - 1, C("14171C"))
    frame(d, 0, 0, s - 1, s - 1, C(border))
    rect(d, 1, 1, s - 2, 1, C(hi))                          # 顶 1px 高光
    rect(d, 1, 1, 1, s - 2, C(hi))                          # 左 1px 高光
    rect(d, 1, s - 2, s - 2, s - 2, C("0B0D10"))            # 底压暗
    rect(d, s - 2, 1, s - 2, s - 2, C("0B0D10"))
    if kind != "normal":
        frame(d, 2, 2, s - 3, s - 3, C("0B0D10"))           # 彩框内 1px 硬描边（辉光感隔离）
    px(d, 0, 0, TRANS); px(d, s - 1, 0, TRANS)
    px(d, 0, s - 1, TRANS); px(d, s - 1, s - 1, TRANS)
    return img


def star(lit: bool = True) -> Image.Image:
    """16×16 難度星（**真五角星**）。

    ⚠️ 舊版畫的是**四角十字**（檔名 `star_*` 在說謊，見規範 §5 L3）。
    本版用五角星多邊形逐像素內外判定（even-odd 射線法），再對「星體」做 1px 8 鄰域
    膨脹得到外描邊 —— 保證輪廓連續、無斷點。

    尺寸仍是 16×16（`verify_ui_assets.gd` 斷言）；亮 = 主體 `D9A521` + 描邊 `0B0D10`，
    暗 = 主體 `3A424F` + 描邊 `0B0D10`。**檔名不變** ⇒ 消費者 `UISkin.star_texture()`
    零改動。
    """
    import math
    s = 16
    img = new(s, s)
    d = ImageDraw.Draw(img)
    main = C("D9A521") if lit else C("3A424F")
    hi = C("F5D77A") if lit else C("4E5866")
    # 外接半徑 6.8 / 內接半徑 2.9（外接 6.8 保證「星體 + 1px 描邊」完整落在 16×16 內）；
    # 圓心 (7.5, 8.6)：五角星 bbox 高 1.809·r，垂直置中 ⇒ 星體 y∈[1.9, 14.2]。
    cx, cy = 7.5, 8.6
    r_out, r_in = 6.8, 2.9
    pts: list[tuple[float, float]] = []
    for i in range(10):
        ang = -math.pi / 2.0 + i * math.pi / 5.0
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))

    def inside(x: float, y: float) -> bool:
        odd = False
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > y) != (yj > y):
                if x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                    odd = not odd
            j = i
        return odd

    body = [[inside(x + 0.5, y + 0.5) for x in range(s)] for y in range(s)]
    neighbors = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
    for y in range(s):
        for x in range(s):
            if body[y][x]:
                px(d, x, y, main)
            elif any(0 <= x + dx < s and 0 <= y + dy < s and body[y + dy][x + dx]
                     for dx, dy in neighbors):
                px(d, x, y, C("0B0D10"))                    # 外描邊 1px（8 鄰域膨脹）
    if lit:
        # 左上受光：星體最上方的兩個像素提亮（僅亮星，暗星不發光）
        for x in (7, 8):
            col = [y for y in range(s) if body[y][x]]
            if col:
                px(d, x, col[0], hi)
    return img


def divider(w: int = 160, h: int = 8) -> Image.Image:
    """分隔線：中灰線 + 中心金菱。

    ⚠️ 線色由 `2A313B`/`3A424F` 改為 **`6B7688`**（規範 §3 C5）：舊線色壓在面板底
    `14171C` 上對比度只有 **1.37:1 / 1.77:1**，形同虛設；`6B7688` 是色板內**唯一**
    能在 `14171C` 上過 3:1 的深色檔（**3.91:1**）。
    **`modulate` 修不了**（乘法只會更暗），必須重導素材。

    尺寸仍是 **160×8**（`verify_ui_assets.gd:32` 斷言）、**檔名不變**
    （消費者 `main_menu_panel.gd` 的 `UISkin.texture("divider")`）。
    """
    img = new(w, h)
    d = ImageDraw.Draw(img)
    rect(d, 0, 3, w - 1, 3, C("6B7688"))
    rect(d, 0, 4, w - 1, 4, C("6B7688"))
    cx, cy = w // 2, 3
    for i in range(4):
        rect(d, cx - (3 - i), cy - i, cx + (3 - i), cy - i, C("D9A521") if i < 2 else C("8C6510"))
        if i < 3 - i:
            rect(d, cx - (3 - i), cy + i + 1, cx + (3 - i), cy + i + 1, C("D9A521") if i < 2 else C("8C6510"))
    px(d, cx, cy - 3, C("F5D77A"))
    for x in (cx - 12, cx + 12):
        px(d, x, 3, C("F5D77A")); px(d, x, 4, C("8C6510"))
    return img


def quest_marker() -> Image.Image:
    """24×24 任务标记：金菱形 + 感叹号身（无字体依赖）。"""
    s = 24
    img = new(s, s)
    d = ImageDraw.Draw(img)
    cx, cy, r = 12, 12, 10
    for i in range(r + 1):
        col = C("0B0D10") if i > r - 2 else (C("D9A521") if i < 4 else C("8C6510"))
        rect(d, cx - (r - i), cy - i, cx + (r - i), cy - i, C("0B0D10"))
        if i < r - i:
            rect(d, cx - (r - i), cy + i, cx + (r - i), cy + i, C("0B0D10"))
    for i in range(r - 2):
        col = C("F5D77A") if i < 3 else C("D9A521")
        rect(d, cx - (r - 2 - i), cy - i, cx + (r - 2 - i), cy - i, col)
        if i < r - 2 - i:
            rect(d, cx - (r - 2 - i), cy + i + 1, cx + (r - 2 - i), cy + i + 1, col)
    # 感叹号（深色，压在金底上）
    rect(d, 10, 6, 13, 13, C("4A3208"))
    rect(d, 10, 6, 13, 7, C("0B0D10"))
    rect(d, 10, 15, 13, 18, C("4A3208"))
    px(d, 10, 6, C("0B0D10")); px(d, 13, 6, C("0B0D10"))
    px(d, 10, 18, C("0B0D10")); px(d, 13, 18, C("0B0D10"))
    return img


# ================================================================ 生态背景
BIOMES = {
    "forest": {
        "sky": ["0F2417", "1E4A2B", "3B7A44", "6FB35C"],
        "ridge_far": "0F2417", "ridge_near": "1E4A2B",
        "mid": "3B7A44", "mid_hi": "6FB35C",
        "ground": "14171C", "ground_lo": "0B0D10", "ground_edge": "1E4A2B",
        "moon": None, "stars": False,
    },
    "frost": {
        "sky": ["101A3A", "1F3468", "3A5FB0", "6E9BE8"],
        "ridge_far": "101A3A", "ridge_near": "1F3468",
        "mid": "3A5FB0", "mid_hi": "6E9BE8",
        "ground": "14171C", "ground_lo": "0B0D10", "ground_edge": "3A5FB0",
        "moon": "DCE2E8", "stars": True,
    },
    "volcanic": {
        "sky": ["4A0E12", "8C1A1F", "C42B2B", "E8573F"],
        "ridge_far": "4A0E12", "ridge_near": "8C1A1F",
        "mid": "C42B2B", "mid_hi": "F5D77A",
        "ground": "14171C", "ground_lo": "0B0D10", "ground_edge": "8C1A1F",
        "moon": "F5D77A", "stars": False,
    },
}

W, H = 640, 360
GROUND_Y = 288


def backdrop(name: str, seed: int = 42) -> Image.Image:
    import random
    rng = random.Random(seed)
    b = BIOMES[name]
    img = new(W, H)
    d = ImageDraw.Draw(img)
    sky = b["sky"]
    # --- 天空 4 段 + 抖动过渡
    band = (GROUND_Y) // 4
    for i, col in enumerate(sky):
        y0 = i * band
        rect(d, 0, y0, W - 1, y0 + band - 1, C(col))
        if i > 0:
            dither_row(d, y0, 0, W - 1, C(sky[i - 1]))
            dither_row(d, y0 + 1, 0, W - 1, C(col))
    # --- 星 / 月
    if b["stars"]:
        for _ in range(40):
            x, y = rng.randrange(0, W), rng.randrange(0, 170)
            px(d, x, y, C("DCE2E8") if rng.random() < 0.7 else C("8C97A8"))
    if b["moon"]:
        mx, my, mr = (W - 96, 64, 26) if name != "volcanic" else (W // 2, 200, 34)
        mcol = C(b["moon"])
        hi = C("DCE2E8") if name != "volcanic" else C("F5D77A")
        lo = C("8C97A8") if name != "volcanic" else C("D9A521")
        for yy in range(-mr, mr + 1):
            half = int((mr * mr - yy * yy) ** 0.5)
            rect(d, mx - half, my + yy, mx + half, my + yy, hi)
        if name == "frost":  # 仅月面画陨坑（太阳无坑）
            for _ in range(6):
                cx2 = mx + rng.randrange(-mr // 2, mr // 2)
                cy2 = my + rng.randrange(-mr // 2, mr // 2)
                r2 = rng.randrange(2, 5)
                rect(d, cx2 - r2, cy2 - r2, cx2 + r2, cy2 + r2, lo)
                rect(d, cx2 - r2 + 1, cy2 - r2 + 1, cx2 + r2 - 1, cy2 + r2 - 1, hi)
        if name == "volcanic":  # 落日光晕带
            dither_row(d, my + mr + 2, 0, W - 1, C("F5D77A"))
            dither_row(d, my + mr + 4, 0, W - 1, C("D9A521"))
    # --- 远山脊（多层三角）
    def ridge(y_base, amp, col, step):
        x = -step
        prev_y = y_base - rng.randrange(amp // 2, amp)
        while x < W + step:
            nx = x + step
            ny = y_base - rng.randrange(amp // 2, amp)
            for i in range(step):
                t = i / step
                ytop = int(prev_y + (ny - prev_y) * t)
                xx = max(0, min(W - 1, x + i))
                rect(d, xx, ytop, xx, y_base, col)
            x, prev_y = nx, ny
    ridge(GROUND_Y + 8, 90, C(b["ridge_far"]), 64)
    ridge(GROUND_Y + 8, 60, C(b["ridge_near"]), 40)
    # --- 中景剪影（生态特征）
    if name == "forest":
        # 整株针叶树剪影（窄三角 + 树干，最小间距防连墙）
        xs_used: list[int] = []
        for _ in range(60):
            if len(xs_used) >= 22:
                break
            x = rng.randrange(4, W - 4)
            if any(abs(x - u) < 16 for u in xs_used):
                continue
            xs_used.append(x)
            hgt = rng.randrange(34, 92)
            base = GROUND_Y + rng.randrange(0, 4)
            wmax = max(2, hgt // 5)
            rect(d, x - 1, base - hgt // 5, x + 1, base, C(b["ridge_far"]))  # 树干
            for yy in range(hgt):
                hw = max(1, int(wmax * ((hgt - yy) / hgt) ** 1.25))  # 底宽顶尖
                rect(d, x - hw, base - yy, x + hw, base - yy, C(b["ridge_near"]))
                if yy % 4 == 0 and hw > 1 and yy < hgt * 0.55:
                    px(d, x + hw - 1, base - yy, C(b["mid"]))
            px(d, x, base - hgt, C(b["mid_hi"]))
    elif name == "frost":
        for _ in range(30):
            x = rng.randrange(4, W - 4)
            hgt = rng.randrange(24, 70)
            base = GROUND_Y + rng.randrange(0, 6)
            for yy in range(hgt):
                half = max(0, int((1 - yy / hgt) * hgt * 0.16))
                rect(d, x - half, base - yy, x + half, base - yy, C(b["mid"] if yy > hgt * 0.4 else b["ridge_near"]))
            px(d, x, base - hgt + 1, C(b["mid_hi"]))
            px(d, x - 1, base - hgt + 3, C("DCE2E8"))
    else:  # volcanic
        for _ in range(22):
            x = rng.randrange(6, W - 6)
            hgt = rng.randrange(18, 56)
            wdt = rng.randrange(10, 26)
            base = GROUND_Y + rng.randrange(0, 6)
            for yy in range(hgt):
                half = int(wdt * (1 - yy / hgt) / 2)
                rect(d, x - half, base - yy, x + half, base - yy, C(b["ridge_near"] if yy > 4 else b["ridge_far"]))
            if rng.random() < 0.6:  # 岩缝辉光
                gy = base - rng.randrange(4, hgt)
                rect(d, x - wdt // 4, gy, x + wdt // 4, gy, C(b["mid_hi"]))
    # --- 地面
    rect(d, 0, GROUND_Y, W - 1, H - 1, C(b["ground"]))
    rect(d, 0, GROUND_Y, W - 1, GROUND_Y, C(b["ground_edge"]))
    rect(d, 0, GROUND_Y + 1, W - 1, GROUND_Y + 1, C(b["ground_lo"]))
    for _ in range(240):
        x, y = rng.randrange(0, W), rng.randrange(GROUND_Y + 2, H)
        px(d, x, y, C(b["ground_lo"] if rng.random() < 0.75 else b["ground_edge"]))
    # --- 顶部/底部暗角（中性基底，8px 内渐变带）
    for i in range(8):
        col = C("0B0D10")
        if i % 2 == 0:
            dither_row(d, i, 0, W - 1, col)
            dither_row(d, H - 1 - i, 0, W - 1, col)
    return img


# ================================================================ 装备图标
GRID = 24
SCALE = 2  # 24 → 48


def icon_from_map(rows: list[str], legend: dict[str, str]) -> Image.Image:
    assert len(rows) <= GRID, f"行数 {len(rows)} 超出 {GRID}"
    rows = rows + [""] * (GRID - len(rows))  # 底部自动补透明
    img = new(GRID, GRID)
    d = ImageDraw.Draw(img)
    for y, row in enumerate(rows):
        assert len(row) <= GRID, f"第 {y} 行超宽（{len(row)}）"
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            px(d, x, y, C(legend[ch]))
    return img.resize((GRID * SCALE, GRID * SCALE), Image.NEAREST)


O = "0B0D10"
STEEL = {"o": O, "e": "6B7688", "s": "B3BCC9", "w": "DCE2E8"}
GOLD = {"g": "8C6510", "G": "D9A521", "y": "F5D77A"}
WOOD = {"b": "4A3208"}
BLUE = {"d": "1F3468", "m": "3A5FB0", "l": "6E9BE8"}
PURP = {"p": "4E2478", "P": "7E44B8", "Q": "B07DE0"}
RED = {"r": "8C1A1F", "R": "C42B2B", "F": "E8573F"}

ICONS: dict[str, tuple[list[str], dict[str, str]]] = {}

ICONS["sword"] = ({**STEEL, **GOLD, **WOOD}, [
    "............oo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    ".........oesswo",
    "....oooooooooooo",
    "....oGGGGyyGGGGo",
    "..........obbo",
    "..........obgo",
    "..........ogbo",
    "..........obgo",
    ".........oGyyGo",
    "..........oggo",
    "...........oo",
])

ICONS["dagger"] = ({**STEEL, **GOLD, **WOOD}, [
    "............oo",
    "...........owso",
    "...........owso",
    "...........owso",
    "...........owso",
    "...........owso",
    "...........owso",
    "...........owso",
    "......oooooooooooo",
    "......oGGGGGGGGGGGo",
    "..........obbo",
    "..........obgo",
    "..........ogbo",
    "..........obbo",
    ".........oGyyGo",
    "..........oggo",
    "...........oo",
])

ICONS["axe"] = ({**STEEL, **GOLD, **WOOD}, [
    "......oooooooooooo",
    ".....ossweeeeewsso",
    "....osswweeeeewssso",
    "...osswwweeeewwwssso",
    "...osswweeeeeewssso",
    "...ossweeeeeeeewsso",
    "....osweeeeeeeeswo",
    ".....ooeeeeeeeeoo",
    ".......ooooooo" + "o",
    "..........obbo",
    "..........obgo",
    "..........ogbo",
    "..........obgo",
    "..........obgo",
    "..........ogbo",
    "..........obgo",
    ".........oGyyGo",
    "..........oggo",
    "...........oo",
])

ICONS["bow"] = ({**STEEL, **WOOD, **GOLD}, [
    "...........obbbbs",
    "........obbo..s",
    ".......obo....s",
    "......obo.....s",
    ".....obo......s",
    ".....obo......s",
    "....obo.......s",
    "....obo.......s",
    "....obo.......s",
    "....obo.......s",
    "....oGGo......s",
    "....oGGo......s",
    "....oGGo......s",
    "....oGGo......s",
    "....obo.......s",
    "....obo.......s",
    "....obo.......s",
    ".....obo......s",
    ".....obo......s",
    "......obo.....s",
    ".......obo....s",
    "........obbo..s",
    "...........obbbs",
])

ICONS["staff"] = ({**BLUE, **WOOD, **GOLD, **STEEL}, [
    "..........ollo",
    ".........olmmmo",
    "........odmwmlo",
    "........odmmmlo",
    "........odmmllo",
    ".........odmllo",
    "..........odmo",
    ".........oGGyyGo",
    "..........obbo",
    "..........obgo",
    "..........ogbo",
    "..........obgo",
    "..........obgo",
    "..........ogbo",
    "..........obgo",
    "..........obgo",
    "..........ogbo",
    "..........obgo",
    "..........obgo",
    "..........ogbo",
    "..........obgo",
    "...........oo",
])

ICONS["shield"] = ({**STEEL, **BLUE, **GOLD}, [
    ".....oooooooooooooo",
    "....oswwwwwwwwwwwwo",
    "....osdddddddddddso",
    "....osddddddddddmso",
    "....osddddddddmmmso",
    "....osdddddddmmmmso",
    "....osddddddmmmmmso",
    ".....osddddGGGGmso",
    ".....osdddGyyGGmso",
    "......osddGyGGGso",
    "......osddGyyGso",
    ".......osdGyyso",
    ".......osdGGso",
    "........osGso",
    "........ossso",
    ".........oso",
    ".........oo",
])

ICONS["helmet"] = ({**STEEL, **GOLD, "d": "14171C"}, [
    "........oooooooo",
    "......ooswwwwwwsoo",
    ".....oswwwwwwwwwso",
    "....oswwwwwwwwwwwso",
    "....ossssssssssssso",
    "....ossssssssssssso",
    "....ossssssssssssso",
    "....ossssssssssssso",
    "....oodddddddddddoo",
    "....oodddddddddddoo",
    "....ossssssssssssso",
    "....ossssssssssssso",
    "....osossssosssssso",
    "....osossssosssssso",
    "....ossssssssssssso",
    "....oGGGGGGGGGGGGGo",
    ".....oGyGGGGGGyGo",
    ".....oGyyyyyyyGo",
    "......oooooooooo",
])

ICONS["chest"] = ({**STEEL, **GOLD, **BLUE}, [
    "....oooooooooooooo",
    "...oswwwooooowwwso",
    "...oswwo..oo..owso",
    "...oswo......owso",
    "...oswwwwwwwwwwso",
    "...osssssssssssso",
    "...osswsssssswsso",
    "...osswsssssswsso",
    "...osswsssssswsso",
    "...osswsssssswsso",
    "....osssssssssso",
    "....oessssssseso",
    "....oessssssseso",
    ".....oessssseso",
    ".....oGyGGGGyGo",
    "......oggggggo",
    ".......oooooo",
])

ICONS["boots"] = ({**WOOD, **GOLD, **STEEL}, [
    "...oooooo...oooooo",
    "...oGyGGo...oGyGGo",
    "...obbbbo...obbbbo",
    "...obbbgo...obbbgo",
    "...obbbgo...obbbgo",
    "...obbbgo...obbbgo",
    "...obbbgo...obbbgo",
    "...obbbgo...obbbgo",
    "...obbbgo...obbbgo",
    "...obbbgo...obbbgo",
    "...obbbgo...obbbgo",
    "...obbbgoo.obbbgoo",
    "...obbbbbbobbbbbbo",
    "...obbbbbbbbbbbbo",
    "...oggggggggggggo",
    "...oooooooooooooo",
])

ICONS["gauntlet"] = ({**STEEL, **GOLD}, [
    "......oooooooo",
    ".....oswwwwwwso",
    "....osswssswsso",
    "....osessssesso",
    "....osessssesso",
    "....osessssesso",
    "...ooosssssssoo",
    "..owososssssoso",
    "..owwossssssswo",
    "..owwossssssowo",
    "...oossssssoo",
    "....osssssso",
    "....oGGGGGGo",
    "...oGyGGGyGGo",
    "...oGyGGGGyGo",
    "...oGyGGGGyGo",
    "...oGyGGGyGGo",
    "...oGGGGGGGo",
    "....ooooooo",
])


def icon_ring() -> Image.Image:
    """戒指：数学圆环 + 顶嵌红宝石。"""
    img = new(GRID, GRID)
    d = ImageDraw.Draw(img)
    import math
    cx, cy = 12, 15
    for y in range(GRID):
        for x in range(GRID):
            dist = math.hypot(x - cx, y - cy)
            if 5.0 <= dist <= 7.2:
                # 描边：环外 1px
                if 6.8 <= dist <= 7.2 or dist <= 5.2:
                    px(d, x, y, C(O))
                else:
                    ang = math.degrees(math.atan2(cy - y, x - cx)) % 360
                    col = "F5D77A" if 20 <= ang <= 140 else ("D9A521" if -60 <= ang < 200 else "8C6510")
                    if ang > 180 + 40 and ang < 320:
                        col = "8C6510"
                    px(d, x, y, C(col))
    # 内孔压暗
    for y in range(GRID):
        for x in range(GRID):
            dist = math.hypot(x - cx, y - cy)
            if 5.4 <= dist <= 5.9:
                px(d, x, y, C(O))
    # 红宝石（菱形）
    gem = [
        (11, 6, "F"), (12, 6, "F"),
        (10, 7, "R"), (11, 7, "F"), (12, 7, "R"), (13, 7, "R"),
        (9, 8, "R"), (10, 8, "F"), (11, 8, "R"), (12, 8, "R"), (13, 8, "R"), (14, 8, "R"),
        (10, 9, "r"), (11, 9, "R"), (12, 9, "R"), (13, 9, "r"),
        (11, 10, "r"), (12, 10, "r"),
    ]
    for x, y, ch in gem:
        px(d, x, y, C(RED[ch]))
    for x, y in ((10, 6), (13, 6), (9, 7), (14, 7), (9, 9), (14, 9), (10, 10), (13, 10), (11, 11), (12, 11)):
        px(d, x, y, C(O))
    rect(d, 10, 11, 13, 12, C("D9A521"))  # 爪座
    rect(d, 10, 12, 13, 12, C("8C6510"))
    return img.resize((GRID * SCALE, GRID * SCALE), Image.NEAREST)


def icon_amulet() -> Image.Image:
    """护符：链 + 金圆框 + 紫宝石。"""
    img = new(GRID, GRID)
    d = ImageDraw.Draw(img)
    # 链（V 形）
    for i in range(8):
        px(d, 4 + i, 2 + i, C("B3BCC9"))
        px(d, 19 - i, 2 + i, C("B3BCC9"))
        px(d, 4 + i, 3 + i, C("6B7688"))
        px(d, 19 - i, 3 + i, C("6B7688"))
    rect(d, 11, 9, 12, 10, C("D9A521"))  # 挂扣
    # 金圆框
    import math
    cx, cy = 12, 16
    for y in range(GRID):
        for x in range(GRID):
            dist = math.hypot(x - cx, y - cy)
            if 5.0 <= dist <= 7.2:
                if 6.8 <= dist <= 7.2:
                    px(d, x, y, C(O))
                else:
                    ang = math.degrees(math.atan2(cy - y, x - cx)) % 360
                    col = "F5D77A" if 20 <= ang <= 140 else "D9A521"
                    if 200 < ang < 340:
                        col = "8C6510"
                    px(d, x, y, C(col))
            elif dist < 5.0:
                px(d, x, y, C(O))  # 框内硬描边
    # 紫宝石圆
    for y in range(GRID):
        for x in range(GRID):
            dist = math.hypot(x - cx, y - cy)
            if dist <= 4.0:
                ang = math.degrees(math.atan2(cy - y, x - cx)) % 360
                col = "Q" if 20 <= ang <= 140 else "P"
                if 200 < ang < 340:
                    col = "p"
                px(d, x, y, C(PURP[col]))
    px(d, 11, 13, C("DCE2E8")); px(d, 12, 13, C("DCE2E8"))
    rect(d, 10, 19, 13, 19, C("4A3208"))
    return img.resize((GRID * SCALE, GRID * SCALE), Image.NEAREST)


# ================================================================ 自校验
def verify_image(path: str) -> tuple[bool, str]:
    img = Image.open(path).convert("RGBA")
    pal = {tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in PAL}
    bad = set()
    for px_ in img.getdata():
        r, g, b, a = px_
        if a == 0:
            continue
        if a != 255 or (r, g, b) not in pal:
            bad.add(px_)
    if bad:
        return False, f"{len(bad)} 个违规像素，例：{sorted(bad)[:3]}"
    return True, "OK"


# ================================================================ 预览合成
def build_preview(panel: Image.Image, banner: Image.Image, icons: dict, out_dir: str) -> None:
    # ① 任务 UI 场景预览：forest 背景 + 面板组装
    bg = backdrop("forest", seed=7)
    comp = bg.copy()
    d = ImageDraw.Draw(comp)
    # 右侧任务面板（9-slice 拉伸到 300×216）
    pw, ph = 300, 216
    p = nine_slice(panel, pw, ph, 8)
    comp.alpha_composite(p, (322, 24))
    comp.alpha_composite(banner.resize((260, 40), Image.NEAREST), (342, 10))
    # 面板内容：星级 / 分隔线 / 槽位 / 按钮
    lit, dim = star(True), star(False)
    for i in range(3):
        comp.alpha_composite(lit, (344 + i * 20, 60))
    for i in range(2):
        comp.alpha_composite(dim, (404 + i * 20, 60))
    comp.alpha_composite(divider(200), (344, 84))
    slot_n, slot_sel = slot_frame("normal"), slot_frame("selected")
    order = ["sword", "staff", "shield", "ring", "amulet", "axe"]
    for i, key in enumerate(order):
        sx = 344 + (i % 3) * 76
        sy = 96 + (i // 3) * 56
        comp.alpha_composite(slot_sel if i == 0 else slot_n, (sx, sy))
        comp.alpha_composite(icons[key], (sx, sy))
    comp.alpha_composite(divider(200), (344, 214))
    btn_gold = quest_button(88, 24, "gold", "normal")
    btn_dark = quest_button(88, 24, "dark", "normal")
    comp.alpha_composite(btn_gold, (344, 224))
    comp.alpha_composite(btn_dark, (444, 224))
    comp.alpha_composite(quest_marker(), (300, 220))
    safe_save(comp.resize((1280, 720), Image.NEAREST), os.path.join(out_dir, "preview_quest_ui.png"))
    # ② 三生态背景预览条
    strip = new(640, 360 * 3 + 8)
    for i, name in enumerate(("forest", "frost", "volcanic")):
        strip.alpha_composite(backdrop(name), (0, i * (360 + 4)))
    safe_save(strip.resize((960, int(strip.height * 1.5)), Image.NEAREST), os.path.join(out_dir, "preview_backdrops.png"))
    # ③ 装备图标预览：暗底 + 槽位陈列
    board = new(8 * 76 + 16, 2 * 76 + 80)
    bd = ImageDraw.Draw(board)
    rect(bd, 0, 0, board.width - 1, board.height - 1, C("0B0D10"))
    rect(bd, 1, 1, board.width - 2, board.height - 2, C("14171C"))
    names = ["sword", "dagger", "axe", "bow", "staff", "shield", "helmet", "chest", "boots", "gauntlet", "ring", "amulet"]
    rarities = ["common", "rare", "epic", "legend", "orange"]
    for i, key in enumerate(names):
        sx = 12 + (i % 8) * 76
        sy = 12 + (i // 8) * 76
        board.alpha_composite(slot_frame(rarities[i % 5] if i >= 8 else "normal"), (sx, sy))
        board.alpha_composite(icons[key], (sx, sy))
    safe_save(board.resize((board.width * 2, board.height * 2), Image.NEAREST), os.path.join(out_dir, "preview_equipment.png"))


# ---------------------------------------------------------------- 保存助手
def safe_save(img: Image.Image, path: str) -> str:
    """原子写盘；目标被预览器锁死时自动顺延文件名（preview_x_2.png …）。"""
    tmp = path + f".tmp{os.getpid()}.png"
    img.save(tmp)
    target = path
    for attempt in range(2, 10):
        try:
            os.replace(tmp, target)
            return target
        except PermissionError:
            try:
                os.remove(target)
                os.replace(tmp, target)
                return target
            except OSError:
                root, ext = os.path.splitext(path)
                target = f"{root}_{attempt}{ext}"
    raise PermissionError(f"无法写入 {path}（连续被占用）")


def nine_slice(src: Image.Image, w: int, h: int, margin: int) -> Image.Image:
    """极简 9-slice：四角原样、边缘拉伸、中心拉伸。"""
    out = new(w, h)
    sw, sh = src.size
    m = margin
    corners = {
        "tl": (0, 0, m, m), "tr": (sw - m, 0, sw, m),
        "bl": (0, sh - m, m, sh), "br": (sw - m, sh - m, sw, sh),
    }
    out.alpha_composite(src.crop(corners["tl"]), (0, 0))
    out.alpha_composite(src.crop(corners["tr"]), (w - m, 0))
    out.alpha_composite(src.crop(corners["bl"]), (0, h - m))
    out.alpha_composite(src.crop(corners["br"]), (w - m, h - m))
    for (sx0, sy0, sx1, sy1), (dx, dy, dw, dh) in (
        ((m, 0, sw - m, m), (m, 0, w - 2 * m, m)),
        ((m, sh - m, sw - m, sh), (m, h - m, w - 2 * m, m)),
        ((0, m, m, sh - m), (0, m, m, h - 2 * m)),
        ((sw - m, m, sw, sh - m), (w - m, m, m, h - 2 * m)),
    ):
        out.alpha_composite(src.crop((sx0, sy0, sx1, sy1)).resize((dw, dh), Image.NEAREST), (dx, dy))
    out.alpha_composite(src.crop((m, m, sw - m, sh - m)).resize((w - 2 * m, h - 2 * m), Image.NEAREST), (m, m))
    return out


# ================================================================ 主流程
def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for p in (OUT_UI, OUT_BG, OUT_ICON, OUT_PREVIEW):
        os.makedirs(p, exist_ok=True)

    if not args.dry_run:
        quest_panel().save(os.path.join(OUT_UI, "quest_panel_9slice.png"))
        quest_banner().save(os.path.join(OUT_UI, "quest_banner_256x48.png"))
        for style in ("gold", "dark"):
            for state in ("normal", "hover", "pressed"):
                quest_button(128, 24, style, state).save(
                    os.path.join(OUT_UI, f"btn_{style}_{state}_128x24.png"))
        for kind in ("normal", "selected", "common", "rare", "epic", "legend", "orange"):
            slot_frame(kind).save(os.path.join(OUT_UI, f"slot_{kind}_48.png"))
        star(True).save(os.path.join(OUT_UI, "star_lit_16.png"))
        star(False).save(os.path.join(OUT_UI, "star_dim_16.png"))
        divider().save(os.path.join(OUT_UI, "divider_160x8.png"))
        quest_marker().save(os.path.join(OUT_UI, "quest_marker_24.png"))
        for name in BIOMES:
            backdrop(name).save(os.path.join(OUT_BG, f"backdrop_{name}_640x360.png"))
        icons = {}
        for key, (legend, rows) in ICONS.items():
            icons[key] = icon_from_map(rows, legend)
            icons[key].save(os.path.join(OUT_ICON, f"equip_{key}_48.png"))
        icons["ring"] = icon_ring()
        icons["ring"].save(os.path.join(OUT_ICON, "equip_ring_48.png"))
        icons["amulet"] = icon_amulet()
        icons["amulet"].save(os.path.join(OUT_ICON, "equip_amulet_48.png"))
        panel = Image.open(os.path.join(OUT_UI, "quest_panel_9slice.png"))
        banner = Image.open(os.path.join(OUT_UI, "quest_banner_256x48.png"))
        build_preview(panel, banner, icons, OUT_PREVIEW)

    # 自校验：全部产物像素必须落在 PALETTE_ALL
    all_ok = True
    for root in (OUT_UI, OUT_BG, OUT_ICON, OUT_PREVIEW):
        for dirpath, _, files in os.walk(root):
            for f in sorted(files):
                if not f.endswith(".png"):
                    continue
                p = os.path.join(dirpath, f)
                ok, msg = verify_image(p)
                rel = os.path.relpath(p, ROOT)
                print(f"[{'PASS' if ok else 'FAIL'}] {rel}  {msg if not ok else ''}")
                all_ok &= ok
    print(("全部产物色板合规 ✅" if all_ok else "存在色板违规 ❌") + f"（色板 {len(PAL)} 色）")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
