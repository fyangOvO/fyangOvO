# -*- coding: utf-8 -*-
"""特效贴图构建：生成**可见的**特效序列帧 PNG（用户可直接打开文件夹替换）。

为什么是「构建期生成 PNG」而不是「运行时程序化生成」
----------------------------------------------------
运行时程序化生成的贴图对用户是**不可见**的 —— 用户无法打开、无法替换、无法预览。
用户诉求原文是「能做一些特效貼圖…我可以自己換」，所以主路径必须是
`game/assets/fx/*.png` 这些**真实落在磁盘上的文件**：
    · 用户可以打开 `game/assets/fx/` 直接看到 `hit_spark.png`；
    · 覆盖同名文件即可替换（或放到 `user://content/fx/` 优先覆盖）。
运行时程序化占位（`FxSprite` 在贴图缺失时的兜底）只是安全网，不是主路径。

同时消费掉既有死资产
--------------------
`game/assets/dnf/fx/` 下 9 张帧（熔心之主 idle FX 7 帧 236×212、焰术信徒攻击 FX 2 帧 85×56）
此前**没有任何脚本加载**（只被 `.import` 与 Python 工具引用）—— 本项目第 10 个
「生成了但没人消费」的资产。本脚本把它们量化后拼成横向序列帧，正式接入 `fx.json`。

唯一色源铁律
------------
`game_constants.gd:607` 点名「烘焙图像资产（PNG 精灵 / 图标 / tile）全部像素必须落在
`PALETTE_ALL`」。所以：
  · 色板**从 game_constants.gd 现读**（不硬编码，保持唯一真源）；
  · Alpha **二值化**（阈值 128 → 0 或 255）—— 铁律的 `palette_contains()` 连 alpha 一起比，
    色板色 alpha 恒为 1.0，半透明像素必然判不合规；
  · 末尾**自校验**：不透明像素中色板外像素数必须 == 0，否则退出码 1。

用法
----
    python game/tools/fx_build_sheets.py            # 生成 + 自校验
    python game/tools/fx_build_sheets.py --dry-run  # 只报告，不写文件
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONSTANTS = os.path.join(ROOT, "game", "scripts", "core", "game_constants.gd")
DNF_FX = os.path.join(ROOT, "game", "assets", "dnf", "fx")
OUT_ROOT = os.path.join(ROOT, "game", "assets", "fx")

ALPHA_THRESHOLD = 128

# 色板别名（全部 ∈ PALETTE_ALL，见 game_constants.gd:614-649）。
# 只列本脚本实际用到的色 —— 多列未用色会让「到底用了哪些色」变模糊。
N5 = (0x4E, 0x58, 0x66)   # 中性·灰
N6 = (0x6B, 0x76, 0x88)   # 中性·浅灰
N7 = (0x8C, 0x97, 0xA8)   # 中性·更浅
N8 = (0xB3, 0xBC, 0xC9)   # 中性·正文亮
N9 = (0xDC, 0xE2, 0xE8)   # 中性·亮白
G1 = (0x8C, 0x65, 0x10)   # 金/光·暗
G2 = (0xD9, 0xA5, 0x21)   # 金/光·中
G3 = (0xF5, 0xD7, 0x7A)   # 金/光·辉光


def parse_palette() -> set:
    """从 game_constants.gd 现读完整 PALETTE_ALL（三段合并）。"""
    src = open(CONSTANTS, encoding="utf-8").read()

    def grab(name: str):
        m = re.search(rf"const {name}: Array\[Color\] = \[(.*?)\n\]", src, re.S)
        if not m:
            sys.exit(f"找不到 {name} —— 色板定义可能改了，请检查 {CONSTANTS}")
        return [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
                for h in re.findall(r'Color\("([0-9A-Fa-f]{6})"\)', m.group(1))]

    pal = set(grab("PALETTE_NEUTRAL")) | set(grab("PALETTE_ACCENT")) \
        | set(grab("PALETTE_RARITY_SEMANTIC"))
    if not pal:
        sys.exit("色板解析结果为空")
    return pal


# ---------------------------------------------------------------------------
# 画布工具（所有写入的像素都必须是色板色；未写入 = 全透明）
# ---------------------------------------------------------------------------

class Sheet:
    def __init__(self, fw: int, fh: int, n: int):
        self.fw, self.fh, self.n = fw, fh, n
        self.img = Image.new("RGBA", (fw * n, fh), (0, 0, 0, 0))
        self.px = self.img.load()

    def set(self, frame: int, x: int, y: int, c) -> None:
        if 0 <= x < self.fw and 0 <= y < self.fh:
            self.px[frame * self.fw + x, y] = (c[0], c[1], c[2], 255)

    def dot(self, frame: int, cx: float, cy: float, c, r: float = 1.0) -> None:
        """画一个半径 r 的实心圆点（r=1 ⇒ 单像素）。"""
        if r <= 1.0:
            self.set(frame, int(round(cx)), int(round(cy)), c)
            return
        ir = int(math.ceil(r))
        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                if dx * dx + dy * dy <= r * r:
                    self.set(frame, int(round(cx)) + dx, int(round(cy)) + dy, c)


def _ring(sh: Sheet, frame: int, cx: float, cy: float, radius: float, c,
          thickness: float = 1.0, steps: int = 360) -> None:
    """画一圈圆环（按角度步进描点，避免依赖绘图库的抗锯齿 ⇒ alpha 恒为二值）。"""
    for i in range(steps):
        a = 2.0 * math.pi * i / steps
        sh.dot(frame, cx + math.cos(a) * radius, cy + math.sin(a) * radius, c, thickness)


def _arc(sh: Sheet, frame: int, cx: float, cy: float, radius: float,
         a0_deg: float, a1_deg: float, c, thickness: float = 1.0) -> None:
    span = abs(a1_deg - a0_deg)
    steps = max(8, int(span))
    for i in range(steps + 1):
        a = math.radians(a0_deg + (a1_deg - a0_deg) * i / steps)
        sh.dot(frame, cx + math.cos(a) * radius, cy + math.sin(a) * radius, c, thickness)


def _line(sh: Sheet, frame: int, x0: float, y0: float, x1: float, y1: float, c,
          thickness: float = 1.0) -> None:
    n = max(2, int(max(abs(x1 - x0), abs(y1 - y0))) + 1)
    for i in range(n + 1):
        t = i / n
        sh.dot(frame, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c, thickness)


# ---------------------------------------------------------------------------
# 五个占位特效（每个都肉眼可辨、且逐帧有变化）
# ---------------------------------------------------------------------------

def build_hit_spark() -> Sheet:
    """命中火花：四向十字尖刺，中段最长，末帧碎裂成点。"""
    fw = fh = 32
    n = 6
    sh = Sheet(fw, fh, n)
    cx = cy = 16.0
    for f in range(n):
        t = f / (n - 1)
        # 长度先增后减（sin 曲线），末帧几乎消失
        arm = 2.0 + 13.0 * math.sin(math.pi * min(1.0, t * 1.15))
        th = 2.0 if t < 0.5 else 1.0
        col = G3 if t < 0.45 else (G2 if t < 0.8 else G1)
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            _line(sh, f, cx, cy, cx + dx * arm, cy + dy * arm, col, th)
        # 斜向短刺（只在峰值附近出现，制造"爆开"感）
        if 0.25 < t < 0.8:
            diag = arm * 0.55
            for (dx, dy) in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
                _line(sh, f, cx, cy, cx + dx * diag, cy + dy * diag, G2, 1.0)
        # 核心亮点：前 2 帧最亮
        sh.dot(f, cx, cy, N9 if t < 0.35 else G3, 2.0 if t < 0.5 else 1.0)
    return sh


def build_slash_arc() -> Sheet:
    """斩击弧：一道弧从左上扫到右下，逐帧变细变淡。"""
    fw = fh = 48
    n = 6
    sh = Sheet(fw, fh, n)
    cx = cy = 24.0
    for f in range(n):
        t = f / (n - 1)
        start = -150.0 + 180.0 * t
        span = 130.0 - 40.0 * t
        radius = 19.0 - 2.0 * t
        th = 3.0 if t < 0.4 else (2.0 if t < 0.75 else 1.0)
        col = N9 if t < 0.4 else (N8 if t < 0.75 else N7)
        _arc(sh, f, cx, cy, radius, start, start + span, col, th)
        # 内圈留一道更亮的细弧，读作"刃口"
        if t < 0.75:
            _arc(sh, f, cx, cy, radius - th, start + 8, start + span - 8, N9, 1.0)
    return sh


def build_level_up_burst() -> Sheet:
    """升级爆光：扩散金环 + 上升光柱。"""
    fw = fh = 48
    n = 8
    sh = Sheet(fw, fh, n)
    cx = cy = 28.0
    for f in range(n):
        t = f / (n - 1)
        r = 3.0 + 20.0 * t
        ring_col = G3 if t < 0.35 else (G2 if t < 0.7 else G1)
        _ring(sh, f, cx, cy, r, ring_col, 2.0 if t < 0.5 else 1.0, 240)
        # 上升光柱：宽度随帧收窄、顶端抬升
        col_top = cy - 14.0 - 20.0 * t
        half_w = 4.0 - 3.0 * t
        for dx in range(-int(half_w), int(half_w) + 1):
            _line(sh, f, cx + dx, cy + 6.0, cx + dx, col_top,
                  G3 if abs(dx) <= 1 else G2, 1.0)
        # 三颗上飘火花
        for k, ang in enumerate((90.0, 60.0, 120.0)):
            a = math.radians(ang)
            d = 8.0 + (14.0 + k * 3.0) * t
            sh.dot(f, cx + math.cos(a) * d, cy - math.sin(a) * d - 8.0 * t, G3, 1.0)
    return sh


def build_pickup_glow() -> Sheet:
    """拾取光晕：呼吸式金环 + 四向星芒。"""
    fw = fh = 24
    n = 6
    sh = Sheet(fw, fh, n)
    cx = cy = 12.0
    for f in range(n):
        t = f / (n - 1)
        pulse = math.sin(math.pi * t)          # 0 → 1 → 0
        r = 4.0 + 5.0 * pulse
        _ring(sh, f, cx, cy, r, G2, 1.0, 160)
        _ring(sh, f, cx, cy, r - 2.0, G3, 1.0, 160)
        star = 2.0 + 4.0 * pulse
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            _line(sh, f, cx, cy, cx + dx * star, cy + dy * star, G3, 1.0)
        sh.dot(f, cx, cy, N9, 1.0)
    return sh


def build_death_puff() -> Sheet:
    """死亡烟尘：中性灰碎片径向散开 + 淡环，逐帧变暗变小。

    对照 `pixel_burst.gd`（代码绘制的死亡粒子：8 个 3×3 色块 + 白色扩散环）——
    贴图版必须**至少同样醒目**，否则「有贴图反而更弱」。所以碎片给到 10 个、
    起始 4×4，环压到 1px 细线，避免环抢戏。
    """
    fw = fh = 32
    n = 6
    sh = Sheet(fw, fh, n)
    cx = cy = 16.0
    angles = [i * 36.0 for i in range(10)]
    for f in range(n):
        t = f / (n - 1)
        # 环：细，且比碎片暗一档
        _ring(sh, f, cx, cy, 3.0 + 12.0 * t, N5, 1.0, 120)
        # 碎片：外扩 + 变暗 + 变小（4 → 2 → 1）
        col = N8 if t < 0.34 else (N6 if t < 0.67 else N5)
        size = 4.0 if t < 0.34 else (2.0 if t < 0.67 else 1.0)
        d = 2.0 + 12.0 * t
        for k, ang in enumerate(angles):
            a = math.radians(ang + 12.0 * (k % 3))
            sh.dot(f, cx + math.cos(a) * d, cy + math.sin(a) * d, col, size)
        # 起手两帧的中心亮核（读作"刚炸开"）
        if t < 0.34:
            sh.dot(f, cx, cy, N9, 4.0 - 6.0 * t)
    return sh


PLACEHOLDERS = {
    "hit_spark": build_hit_spark,
    "slash_arc": build_slash_arc,
    "level_up_burst": build_level_up_burst,
    "pickup_glow": build_pickup_glow,
    "death_puff": build_death_puff,
}

# 既有死资产 → 横向序列帧。消费 `assets/dnf/fx/` 里 9 张从未被加载的帧。
DNF_STRIPS = {
    # 输出名             源文件（按帧序）                                    fps
    "ember_lord_aura": [
        "boss_ember_lord_idle_03_fx.png", "boss_ember_lord_idle_04_fx.png",
        "boss_ember_lord_idle_05_fx.png", "boss_ember_lord_idle_06_fx.png",
        "boss_ember_lord_idle_07_fx.png", "boss_ember_lord_idle_08_fx.png",
        "boss_ember_lord_idle_15_fx.png",
    ],
    "pyromancer_cast": [
        "pyromancer_cultist_attack_06_fx.png",
        "pyromancer_cultist_attack_08_fx.png",
    ],
}


def nearest(c, pal):
    r, g, b = c
    best, bd = None, 1 << 30
    for (pr, pg, pb) in pal:
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if d < bd:
            bd, best = d, (pr, pg, pb)
    return best


def quantize_frame(im: Image.Image, pal, cache: dict) -> Image.Image:
    """量化到色板 + alpha 二值化（与 tiles_quantize.py 同口径）。"""
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < ALPHA_THRESHOLD:
                px[x, y] = (0, 0, 0, 0)
                continue
            key = (r, g, b)
            nc = cache.get(key)
            if nc is None:
                nc = nearest(key, pal)
                cache[key] = nc
            px[x, y] = (nc[0], nc[1], nc[2], 255)
    return im


def build_dnf_strip(name: str, files: list, pal) -> Image.Image:
    frames = []
    cache = {}
    for fn in files:
        p = os.path.join(DNF_FX, fn)
        if not os.path.isfile(p):
            sys.exit(f"!! 找不到源帧 {p}（DNF 素材被移动了？）")
        frames.append(quantize_frame(Image.open(p), pal, cache))
    fw, fh = frames[0].size
    for im in frames:
        if im.size != (fw, fh):
            sys.exit(f"!! {name}: 帧尺寸不一致 {im.size} vs {(fw, fh)}")
    strip = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        strip.paste(im, (i * fw, 0))
    return strip


def off_palette_count(img: Image.Image, pal: set) -> int:
    """不透明像素中「不在色板内」的个数。

    用 `tobytes()` 而不是 `getdata()`：后者在 Pillow 14 起被弃用，且逐像素
    Python 对象开销大（ember_lord 图集有 35 万像素）。tobytes 一次拿整块 buffer。
    """
    raw = img.convert("RGBA").tobytes()
    bad = 0
    for i in range(0, len(raw), 4):
        if raw[i + 3] == 0:
            continue
        if (raw[i], raw[i + 1], raw[i + 2]) not in pal:
            bad += 1
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    pal = parse_palette()
    print(f"色板：PALETTE_ALL = {len(pal)} 色（现读自 {os.path.relpath(CONSTANTS, ROOT)}）")
    print(f"输出目录：{os.path.relpath(OUT_ROOT, ROOT)}\n")

    results = []          # (name, size, frames, off_palette)
    sheets = {}           # name -> Image

    for name, fn in PLACEHOLDERS.items():
        sh = fn()
        sheets[name] = sh.img
        results.append((name, (sh.fw, sh.fh), sh.n, off_palette_count(sh.img, pal)))

    for name, files in DNF_STRIPS.items():
        strip = build_dnf_strip(name, files, pal)
        sheets[name] = strip
        fw = strip.width // len(files)
        results.append((name, (fw, strip.height), len(files),
                        off_palette_count(strip, pal)))

    worst = 0
    for name, (fw, fh), n, bad in results:
        worst = max(worst, bad)
        tag = "✓ 合规" if bad == 0 else "✗ 违规！"
        print(f"  {name:<18} {n} 帧 × {fw}×{fh}  图集 {fw * n}×{fh}px  色板外像素 {bad}  {tag}")

    if not args.dry_run:
        os.makedirs(OUT_ROOT, exist_ok=True)
        for name, img in sheets.items():
            p = os.path.join(OUT_ROOT, f"{name}.png")
            img.save(p)
        print(f"\n已写出 {len(sheets)} 张：{os.path.relpath(OUT_ROOT, ROOT)}/*.png")

    print("=" * 62)
    if worst == 0:
        print(f"自校验：{len(results)} 张特效图集全部不透明像素 ∈ PALETTE_ALL ✓")
    else:
        print(f"自校验：存在 {worst} 个色板外像素 ✗")
    return 0 if worst == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
