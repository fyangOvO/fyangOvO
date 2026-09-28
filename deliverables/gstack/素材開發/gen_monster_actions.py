# -*- coding: utf-8 -*-
"""
G1 動作衍生：由 4 方向的 idle 立姿 → 每隻 84 幀（idle4 / walk4 / attack4 / hurt3 / die6）

為什麼要衍生：AI 一張圖 = 一個方向的一個立姿（32 張的預算）。其餘 80 幀
用「上半身位移 / 精確 90° 旋轉」產生 —— 與玩家 cast / hurt / death / walk6 同一套技術。

硬規格（`05-monsters.json:asset_orders` + 實測既有怪）
  · 畫布 128×128、站立**腳底 y=127**、`char_<id>_<action>_<dir>_<NN>.png`
  · `NN` 自 01 起、**遇缺即停** ⇒ 每個動作必須連續寫滿
  · 只有 4 方向 n/e/s/w；動作是 `die`（不是 `death`）
  · alpha 二值；用色保持 ≤48（位移/旋轉不會增加相異色）

⚠️ 兩個關鍵決策
  1. **切分線一律取胸線**：AI 畫的權杖/尾巴多半垂在身側，切腰線會把它切成兩段。
  2. **躺地幀只用精確 90° 旋轉**（NEAREST）：非 90° 的插值旋轉會把像素網格攪爛。
"""
import argparse
import os

import numpy as np
from PIL import Image

SRC = r"D:/七傳說/deliverables/gstack/素材開發/_g1_ai/out2"
DST = r"D:/七傳說/deliverables/gstack/素材開發/_g1_ai/mon"
CANVAS, FEET = 128, 127
CHEST_FRAC = 0.42          # AI 出圖是大頭 Q 版 ⇒ 胸線比玩家的 0.33 低一些，避免把頭切了
DIRS = ["n", "e", "s", "w"]

# (模式, 參數…)   lean=上半身位移 / rot90=精確旋轉後置於指定高度
PLANS = {
    "idle":   [("lean", 0, 0), ("lean", 0, -2), ("lean", 0, -3), ("lean", 0, -1)],
    "walk":   [("lean", 0, 0), ("lean", 2, -2), ("lean", 0, 0), ("lean", -2, -2)],
    "attack": [("lean", 0, 0), ("lean", -3, -2), ("lean", 4, 1), ("lean", 1, 0)],
    "hurt":   [("lean", 0, -3), ("lean", 0, -3), ("lean", 0, -1)],
    "die":    [("lean", 0, -2), ("lean", 0, -4),
               ("rot", 8), ("rot", 3), ("rot", 0), ("rot", 0)],
}


def bbox(img):
    ys, xs = np.nonzero(np.array(img)[:, :, 3] > 8)
    return (int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())) if len(ys) else None


def lean(img, dx, dy):
    """上半身（[0,split)）整體位移，下半身不動；位移後用邊界列/行填縫避免透明裂縫。"""
    if dx == 0 and dy == 0:
        return img.copy()
    a = np.array(img)
    b = bbox(img)
    if b is None:
        return img.copy()
    top, bottom = b[0], b[1]
    split = top + int(round((bottom - top + 1) * CHEST_FRAC))
    split = max(1, min(a.shape[0] - 1, split))
    h, w = split, a.shape[1]
    up = a[0:split]
    sh = up.copy()
    if dy < 0:
        d = -dy
        sh = np.empty_like(up)
        sh[0:h - d] = up[d:h]
        sh[h - d:h] = up[h - 1]
    elif dy > 0:
        sh = np.empty_like(up)
        sh[dy:h] = up[0:h - dy]
        sh[0:dy] = up[0]
    if dx != 0:
        s2 = np.empty_like(sh)
        if dx > 0:
            s2[:, dx:w] = sh[:, 0:w - dx]
            s2[:, 0:dx] = sh[:, 0:1]
        else:
            s2[:, 0:w + dx] = sh[:, -dx:w]
            s2[:, w + dx:w] = sh[:, w - 1:w]
        sh = s2
    out = a.copy()
    out[0:split] = sh
    return Image.fromarray(out, "RGBA")


def place(img, bottom=FEET):
    """水平置中、底部對齊 bottom（裁掉畫布外部分 —— 永不往下超出底邊）。"""
    b = bbox(img)
    if b is None:
        return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    y0, y1, x0, x1 = b
    crop = img.crop((x0, y0, x1 + 1, y1 + 1))
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    out.alpha_composite(crop, ((CANVAS - crop.width) // 2, bottom - crop.height + 1))
    return out


def lie_down(img, gap):
    """精確 90° 旋轉（NEAREST，不插值）→ 躺地；gap = 離地高度（越大越還沒落地）。"""
    rot = img.rotate(-90, resample=Image.NEAREST, expand=True)
    if rot.width > CANVAS:                     # 躺下會變寬 ⇒ 超框時只做整數縮
        k = max(1, rot.width // CANVAS + (1 if rot.width % CANVAS else 0))
        rot = rot.resize((rot.width // k, rot.height // k), Image.NEAREST)
    return place(rot, FEET - gap)


def darken(img, f):
    a = np.array(img).astype(np.int16)
    m = a[:, :, 3] > 0
    for c in range(3):
        a[:, :, c][m] = np.clip(a[:, :, c][m] * f, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--install", action="store_true")
    args = ap.parse_args()
    dst_root = r"D:/七傳說/game/assets/pack/creatures" if args.install else DST

    # ⚠️ 原本這兩行是「先給 ids 又無條件覆蓋」⇒ `--only` 完全失效
    #    （跑 --only rat_swarm 會重跑全部怪，冪等無害但浪費時間）。合併成一行。
    ids = (sorted(set(args.only)) if args.only else
           sorted({f.rsplit("_", 1)[0] for f in os.listdir(SRC) if f.endswith(".png")}))
    for mid in ids:
        bases = {}
        for d in DIRS:
            p = os.path.join(SRC, "%s_%s.png" % (mid, d))
            if os.path.exists(p):
                bases[d] = Image.open(p).convert("RGBA")
        if len(bases) < 4:
            print("[skip] %s 只有 %d 個方向" % (mid, len(bases))); continue
        out_dir = os.path.join(dst_root, mid)
        os.makedirs(out_dir, exist_ok=True)
        made = 0
        for act, plan in PLANS.items():
            for d in DIRS:
                base = bases[d]
                for i, step in enumerate(plan, start=1):
                    if step[0] == "lean":
                        img = place(lean(base, step[1], step[2]))
                    else:
                        img = lie_down(base, step[1])
                        if act == "die" and i == len(plan):
                            img = darken(img, 0.78)      # 最後一幀壓暗＝沉下去
                    img.save(os.path.join(out_dir, "char_%s_%s_%s_%02d.png" % (mid, act, d, i)))
                    made += 1
        print("  %-16s 產出 %d 幀（4 方向 × 21）→ %s" % (mid, made, out_dir))

    # 驗證
    bad = []
    for mid in ids:
        out_dir = os.path.join(dst_root, mid)
        if not os.path.isdir(out_dir):
            continue
        for act, fr in (("idle", 4), ("walk", 4), ("attack", 4), ("hurt", 3), ("die", 6)):
            for d in DIRS:
                for i in range(1, fr + 1):
                    p = os.path.join(out_dir, "char_%s_%s_%s_%02d.png" % (mid, act, d, i))
                    if not os.path.exists(p):
                        bad.append("缺 " + os.path.basename(p)); continue
                    im = Image.open(p).convert("RGBA")
                    a = np.array(im)
                    if im.size != (CANVAS, CANVAS):
                        bad.append("%s 尺寸 %s" % (os.path.basename(p), im.size))
                    if not set(np.unique(a[:, :, 3]).tolist()) <= {0, 255}:
                        bad.append("%s alpha" % os.path.basename(p))
                    n = len({tuple(int(v) for v in px) for px in a[a[:, :, 3] > 0][:, :3]})
                    if n > 48:
                        bad.append("%s 用色 %d >48" % (os.path.basename(p), n))
    print("驗證：問題 %d %s" % (len(bad), bad[:6]))


if __name__ == "__main__":
    main()
