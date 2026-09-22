# -*- coding: utf-8 -*-
"""严谨像素 UI 组件生成（DNF 暗黑金属风，全部 44 色板，alpha 二值）。

输出到 ui/pixel/：
  panel_9slice_120.png        面板 9-slice（边距 8，暗金双层边框+铆钉+顶三角）
  btn_gold_{normal,hover,pressed}_96x24.png   金色主按钮三态
  btn_dark_{normal,hover,pressed}_96x24.png   暗色次按钮三态
  bar_hp_160x16.png / bar_mp_160x16.png        血/蓝条（凹槽+端帽，可横向拉伸）
  slot_normal_48.png / slot_selected_48.png    物品槽
  rarity_{common,rare,epic,legend,myth}_48.png 稀有度框
  skill_slot_48.png           技能栏槽
"""
from pathlib import Path
from PIL import Image

OUT = Path(__file__).parent / "ui" / "pixel"
OUT.mkdir(parents=True, exist_ok=True)


def C(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ── 44 色板 ────────────────────────────────────────────────────────────
INK = C("0B0D10")      # 近黑
WELL = C("14171C")     # 深槽
SLATE = C("1E232B")    # 中灰蓝
SLATE_H = C("2A313B")  # 亮灰蓝
EDGE = C("3A424F")     # 边框
EDGE_H = C("4E5866")   # 高光
GREY = C("6B7688")
LGREY = C("8C97A8")
TEXT = C("B3BCC9")
WHITE = C("DCE2E8")
WARM = C("DBCC85")

RED_D, RED_M, RED, RED_H = C("4A0E12"), C("8C1A1F"), C("C42B2B"), C("E8573F")
BLU_D, BLU_M, BLU, BLU_H = C("101A3A"), C("1F3468"), C("3A5FB0"), C("6E9BE8")
GOLD_D, GOLD_M, GOLD, GOLD_H = C("4A3208"), C("8C6510"), C("D9A521"), C("F5D77A")
PUR_D, PUR_M, PUR, PUR_H = C("2A1440"), C("4E2478"), C("7E44B8"), C("B07DE0")

R_COMMON, R_RARE, R_EPIC, R_LEGEND, R_MYTH = (
    C("C9D1D9"), C("4C8BF5"), C("F5C542"), C("A96BFF"), C("FF8A2B"))


def img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c + (255,))


def rect(im, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(im, x, y, c)


def frame(im, x0, y0, x1, y1, c, t=1):
    """t px 描边矩形。"""
    for k in range(t):
        for x in range(x0 + k, x1 - k + 1):
            px(im, x, y0 + k, c); px(im, x, y1 - k, c)
        for y in range(y0 + k, y1 - k + 1):
            px(im, x0 + k, y, c); px(im, x1 - k, y, c)


def rivet(im, cx, cy, c=GOLD_H, d=GOLD_D):
    """金属铆钉（3x3）。"""
    px(im, cx, cy, c); px(im, cx - 1, cy, d); px(im, cx + 1, cy, d)
    px(im, cx, cy - 1, d); px(im, cx, cy + 1, d)


def beveled_panel(im, x0, y0, x1, y1, fill, edge, hi, cut=0):
    """带斜切角的矩形面板（左上/右下切角）。"""
    pts = []
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            # 切角：左上/右下切 cut 像素
            if cut and ((x - x0) + (y - y0) < cut):
                continue
            if cut and ((x1 - x) + (y1 - y) < cut):
                continue
            pts.append((x, y))
    for x, y in pts:
        px(im, x, y, fill)
    # 描边
    for x, y in pts:
        border = (x in (x0, x1) or y in (y0, y1))
        if not border:
            continue
        # 顶/左为高光，底/右为暗影
        if y == y0 or x == x0:
            px(im, x, y, hi)
        else:
            px(im, x, y, edge)


# ===========================================================================
# 1. 面板 9-slice（120×120，边距 8）
# ===========================================================================
def make_panel():
    S = 120
    M = 8          # 9-slice 边距
    im = img(S, S)
    # 主体底（中心区深槽，边缘一圈暗金）
    rect(im, 0, 0, S - 1, S - 1, INK)
    # 外暗金框（双层）
    frame(im, 0, 0, S - 1, S - 1, GOLD_D, 1)
    frame(im, 2, 2, S - 3, S - 3, GOLD_M, 1)
    # 内侧深色金属框
    frame(im, 4, 4, S - 5, S - 5, INK, 1)
    frame(im, 5, 5, S - 6, S - 6, EDGE, 1)
    # 中心区纯深槽
    rect(im, 6, 6, S - 7, S - 7, WELL)
    # 四角金铆钉（在 9-slice 角内，边距区）
    for cx, cy in ((6, 6), (S - 7, 6), (6, S - 7), (S - 7, S - 7)):
        rivet(im, cx, cy)
    # 顶部居中金菱形（在 9-slice 边距外，仅装饰，实际横幅另出）
    cx = S // 2
    for k in range(3):
        px(im, cx, 2 + k, GOLD_H); px(im, cx - 1, 2 + k, GOLD); px(im, cx + 1, 2 + k, GOLD)
    px(im, cx - 2, 3, GOLD); px(im, cx + 2, 3, GOLD)
    im.save(OUT / "panel_9slice_120.png")


# ===========================================================================
# 2. 按钮（96×24，斜切角金属，三态）
# ===========================================================================
def make_buttons():
    W, H = 96, 24

    def one(scheme, state):
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
        # 主体（斜切角）
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
        # 描边
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if im.getpixel((x, y))[3] == 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and im.getpixel((nx, ny))[3] == 0:
                        px(im, x, y, edge)
                        break
        # 悬停态：加一圈亮边（在按钮内侧加亮线）
        if state == "hover":
            for x in range(x0 + cut, x1 - cut + 1):
                px(im, x, y0 + 3, WHITE if scheme == "gold" else EDGE_H)
        return im

    for scheme in ("gold", "dark"):
        for state in ("normal", "hover", "pressed"):
            one(scheme, state).save(OUT / f"btn_{scheme}_{state}_96x24.png")


# ===========================================================================
# 3. 血条 / 蓝条（160×16，凹槽+端帽，可整体当底，填充用代码裁）
# ===========================================================================
def make_bar(name, fill, fill_hi, deep):
    W, H = 160, 16
    im = img(W, H)
    y0, y1 = 2, H - 3
    # 凹槽底
    rect(im, 2, y0, W - 3, y1, WELL)
    # 填充区（留 2px 内边距）
    fx0, fx1, fy0, fy1 = 5, W - 6, y0 + 2, y1 - 2
    rect(im, fx0, fy0, fx1, fy1, deep)
    # 填充上半部加亮，模拟金属/液体光泽
    for x in range(fx0, fx1 + 1):
        px(im, x, fy0, fill_hi)
        px(im, x, fy0 + 1, fill)
    # 凹槽金属边框
    frame(im, 2, y0, W - 3, y1, EDGE, 1)
    # 顶/左高光
    for x in range(3, W - 3):
        px(im, x, y0, EDGE_H)
    # 两端金属端帽（3px）
    for x in (2, 3, 4, W - 5, W - 4, W - 3):
        for y in range(y0, y1 + 1):
            px(im, x, y, SLATE_H if x in (4, W - 5) else EDGE)
    im.save(OUT / f"bar_{name}_160x16.png")


# ===========================================================================
# 4. 物品槽（48×48）普通/选中
# ===========================================================================
def make_slot(selected=False):
    S = 48
    im = img(S, S)
    rect(im, 1, 1, S - 2, S - 2, WELL)
    # 内凹框
    frame(im, 1, 1, S - 2, S - 2, EDGE, 1)
    # 内圈
    frame(im, 3, 3, S - 4, S - 4, SLATE, 1)
    # 内底再压暗
    rect(im, 5, 5, S - 6, S - 6, INK)
    if selected:
        # 选中：亮金双层框 + 四角
        frame(im, 1, 1, S - 2, S - 2, GOLD, 1)
        frame(im, 2, 2, S - 3, S - 3, GOLD_H, 1)
        for cx, cy in ((2, 2), (S - 3, 2), (2, S - 3), (S - 3, S - 3)):
            px(im, cx, cy, WHITE)
    return im


# ===========================================================================
# 5. 稀有度框（48×48）：透明底 + 对应颜色边框
# ===========================================================================
def make_rarity(col):
    S = 48
    im = img(S, S)
    # 深色槽底（保持可读，物品框一般有底）
    rect(im, 1, 1, S - 2, S - 2, WELL)
    # 外发光框（2px 彩色）
    frame(im, 1, 1, S - 2, S - 2, col, 2)
    # 四角小亮点
    for cx, cy in ((2, 2), (S - 3, 2), (2, S - 3), (S - 3, S - 3)):
        px(im, cx, cy, WHITE)
    return im


# ===========================================================================
# 6. 技能栏槽（48×48，带斜切角与金属铆钉）
# ===========================================================================
def make_skill_slot():
    S = 48
    im = img(S, S)
    # 斜切角深底
    for y in range(1, S - 1):
        for x in range(1, S - 1):
            if x + y < 5 or (S - 1 - x) + (S - 1 - y) < 5:
                continue
            px(im, x, y, WELL)
    # 金属边框
    for y in range(1, S - 1):
        for x in range(1, S - 1):
            if im.getpixel((x, y))[3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if im.getpixel((nx, ny))[3] == 0:
                    px(im, x, y, EDGE_H)
    # 四角铆钉
    for cx, cy in ((4, 4), (S - 5, 4), (4, S - 5), (S - 5, S - 5)):
        rivet(im, cx, cy)
    im.save(OUT / "skill_slot_48.png")


def main():
    make_panel()
    make_buttons()
    make_bar("hp", RED, RED_H, RED_D)
    make_bar("mp", BLU, BLU_H, BLU_D)
    make_slot(False).save(OUT / "slot_normal_48.png")
    make_slot(True).save(OUT / "slot_selected_48.png")
    for name, col in (("common", R_COMMON), ("rare", R_RARE), ("epic", R_EPIC),
                      ("legend", R_LEGEND), ("myth", R_MYTH)):
        make_rarity(col).save(OUT / f"rarity_{name}_48.png")
    make_skill_slot()
    print("UI 组件输出到:", OUT)
    for p in sorted(OUT.glob("*.png")):
        im = Image.open(p)
        ncol = len(set(c for c in im.getdata() if c[3] > 0))
        print(f"  {p.name:36s} {im.size}  {ncol}色")


if __name__ == "__main__":
    main()
