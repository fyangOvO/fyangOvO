# -*- coding: utf-8 -*-
"""
G1 後處理：AI 出圖 → 專案規格的精靈 PNG

把 `_g1_ai/raw/*.png` 轉成 `char_<id>_<action>_<dir>_<NN>.png`。

處理鏈（每一步都是踩過的坑）
----------------------------
1. **泛洪摳底**（不用「距離門檻」）：AI 給的洋紅底是**漸層**，不是純色
   ⇒ 用四角當種子做連通泛洪，只把「與邊界相連」的底色挖掉，
   **不會誤殺怪物身上同色系的紫／洋紅像素**（本專案既有管線也是泛洪摳底）。
2. **只保留最大連通塊**：平台會在右下角壓「AI生成」浮水印，
   它是一塊獨立的非底色區域 ⇒ 會跟著 alpha 留下來。從身體內部再泛洪一次，只留主體。
3. **despill**：邊緣抗鋸齒像素會被底色染色（洋紅：R-G>22 且 B-G>22），
   只靠門檻會留粉紅光暈 ⇒ 把邊緣像素的 R/B 拉回 G 值。
4. **整數倍 NEAREST 降採樣**：AI 的原生像素塊很大（1024 上約 14px），
   用 LANCZOS 會糊成次像素、失去像素感（實測）。取整數 k 讓主體高度落在 ~110px。
5. **貼齊基準**：怪物站立腳底 **y=127**（128×128 畫布），水平置中。
6. **量化到 ≤48 色**（怪物走自適應色板，已裁定例外），**alpha 二值化**。
"""
import os
import re
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

RAW = r"D:/七傳說/deliverables/gstack/素材開發/_g1_ai/raw2"
OUT_ROOT = r"D:/七傳說/deliverables/gstack/素材開發/_g1_ai/out2"
CANVAS = 128
FEET = 127
TARGET_H = 112          # 主體目標高度（像素）
SENT_BG = (1, 2, 3)
SENT_FG = (4, 5, 6)


def _flood_from_border(colors, th=60, block=4, max_iter=3000):
    """從畫面邊緣做「**相鄰差**泛洪」，回傳 full-size 的底色遮罩。

    在 /`block` 的 **NEAREST** 縮圖上做（不是 any-pool：any-pool 會把細結構
    併進候選，NEAREST 保留邊界銳利度）；迭代用 numpy 的 roll 做，一次 4 鄰域。

    為什麼是「相鄰差」而不是「與底色的距離」：底色的漸層**平滑**（相鄰色差極小）
    ⇒ 泛洪一路擴散到整片底；角色與底的邊界是**突變**（實測灰鼠 vs 中亮洋紅
    L1 = 150）⇒ 泛洪在此止步。
    """
    h, w = colors.shape[:2]
    sh, sw = (h + block - 1) // block, (w + block - 1) // block
    pad = np.zeros((sh * block, sw * block, 3), np.int16)
    pad[:h, :w] = colors
    small = pad[::block, ::block][:sh, :sw]

    border = np.concatenate([small[0], small[-1], small[:, 0], small[:, -1]])
    ref = np.median(border, axis=0)
    d_b = np.sqrt(((border.astype(np.float32) - ref) ** 2).sum(axis=1))
    seed_tol = max(30.0, float(np.percentile(d_b, 98)) * 1.5)
    d_s = np.sqrt(((small.astype(np.float32) - ref) ** 2).sum(axis=2))

    bg = np.zeros((sh, sw), bool)
    bg[0, :] = bg[-1, :] = True
    bg[:, 0] = bg[:, -1] = True
    bg &= d_s < seed_tol                     # 邊緣上「不像底」的像素不當種子
    if not bg.any():                         # 保險：種子全被濾掉就整條邊都當底
        bg[0, :] = bg[-1, :] = True

    for _ in range(max_iter):
        prev = bg.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nb = np.roll(bg, (dy, dx), axis=(0, 1))
            diff = np.abs(small - np.roll(small, (dy, dx), axis=(0, 1))).sum(axis=2)
            bg |= nb & (diff < th)
        if np.array_equal(bg, prev):
            break
    return np.repeat(np.repeat(bg, block, axis=0), block, axis=1)[:h, :w]


def key_bg(img, th=30, ref_tol=50):
    """摳底 → 回 (RGB ndarray, fg_mask)。

    ⚠️ 這條路踩過**三個**坑，每一次都是「換一個更聰明的門檻」，全都失敗：
      1. **Pillow `ImageDraw.floodfill`（單點種子）**：AI 在角色下方多畫的
         **黑色地面陰影**會把洋紅底**隔斷**，單點泛洪只填得到外圈 ——
         實測 `thunder_herald_w` 只填 **9%**（despill 1788 → 27685 是這個訊號）。
      2. **「絕對洋紅色相」**（`R-G>40 且 B-G>40`）：底是漸層，暗端會偏成
         **深紫紅**（B 不夠高）而漏判 —— 實測 `rat_swarm_s` 整張底沒摳掉。
      3. **「與邊緣中位色的距離」**（tol 自適應也一樣）：底色是中亮洋紅
         `(175,47,111)` 時，灰鼠 `#929483` 與它只差 **99.4** ⇒
         能覆蓋漸層的門檻（105）必然咬掉整隻老鼠（輸出變灰色剪影）；
         門檻壓到 40 又摳不掉漸層內側。**距離門檻無法同時滿足兩者。**

    ⇒ 最終解＝**兩層互補**：
      ① **連通性 + 局部差分**（`_flood_from_border`）：底色靠「相鄰色差小」自己串起來，
         角色靠「邊界色差大」自然斷開。這是主力。
      ② **純底色補挖**（`ref_tol`=50，與邊緣中位色的距離）：
         處理泛洪**進不去**的底色 —— 角色用弓弦／手臂／尾巴圍出的**封閉洞**
         （實測 `bone_archer` 弓的內側）、腳下的殘帶（`frost_lobber_w`）、
         以及 AI 直接畫在角色上的洋紅塊。門檻壓到 50 才不會咬到角色的紫
         （`void_priest` 紫袍距底色 ≈223、權杖亮紫球 ≈85，都在安全區）。
    """
    rgb = np.array(img.convert("RGB")).astype(np.int16)
    bg = _flood_from_border(rgb, th=th)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    ref = np.median(border, axis=0)
    d = np.sqrt(((rgb.astype(np.float32) - ref) ** 2).sum(axis=2))
    bg = bg | (d < ref_tol)
    return rgb.astype(np.uint8), ~bg


def strip_stray_magenta(rgb, fg):
    """去掉角色**內部**殘留的亮品紅塊（AI 誤畫，不連邊緣所以躲過摳底）。

    條件必須同時滿足「**接近純洋紅**」＋「亮」：
      · `R-G > 100 且 B-G > 100` ⇒ 幾乎就是底色洋紅（不是「泛品紅」）
      · `V > 180` ⇒ 亮
    為什麼門檻要拉到 100：第一版用 40 時，`void_priest` 的紫袍
    （#4E2478 系：R-G=42、B-G=84）與 `thunder_herald` 的亮色反光全被誤殺
    —— 實測 `void_priest_s` 被挖掉 40507 px（用色 40 → 29）。拉到 100 後
    紫袍（B-G 只有 84）安全，而 AI 誤畫的洋紅 `#E518FB`（R-G=205、B-G=227）仍抓得到。
    """
    a = rgb.astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    stray = fg & (r - g > 100) & (b - g > 100) & (a.max(axis=2) > 180)
    out = fg.copy()
    out[stray] = False
    return out, int(stray.sum())


def keep_largest_blob(fg, block=4):
    """只保留最大連通塊（去掉平台壓在角落的「AI生成」浮水印等孤立塊）。

    ⚠️ 兩個踩過的坑：
    1. 第一版在 **RGB** 圖上用 `thresh=0` 泛洪 ⇒ 只填「與種子同色」的相鄰像素，
       主體只剩 12×4（實測）。
    2. 第二版改用 Pillow 在 **'L'** 二值圖上泛洪 ⇒ **完全沒生效**（回 0 命中），
       而我的 fallback `if keep.sum() > 0 else fg` 於是把整個前景原封不動還原，
       **浮水印因此安然存活**（實測殘留 33 px）。
    ⇒ 改為**自己做 BFS 連通標記**：先在 /block 的 max-pool 縮圖上標記（快，且
      `max` pooling 保證細長結構不會斷開），再把標記放大回原尺寸、與原前景取交集。
    """
    h, w = fg.shape
    bh, bw = (h + block - 1) // block, (w + block - 1) // block
    pad = np.zeros((bh * block, bw * block), bool)
    pad[:h, :w] = fg
    small = pad.reshape(bh, block, bw, block).any(axis=(1, 3))
    seen = np.zeros_like(small, bool)
    best, best_seed = 0, None
    starts = []
    for sy in range(bh):
        for sx in range(bw):
            if not small[sy, sx] or seen[sy, sx]:
                continue
            q = [(sy, sx)]
            seen[sy, sx] = True
            n = 0
            while q:
                cy, cx = q.pop()
                n += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < bh and 0 <= nx < bw and small[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            if n > best:
                best, best_seed = n, (sy, sx)
    if best_seed is None:
        return fg
    comp = np.zeros_like(small, bool)
    q = [best_seed]
    comp[best_seed] = True
    while q:
        cy, cx = q.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < bh and 0 <= nx < bw and small[ny, nx] and not comp[ny, nx]:
                comp[ny, nx] = True
                q.append((ny, nx))
    up = np.repeat(np.repeat(comp, block, axis=0), block, axis=1)[:h, :w]
    return fg & up


def despill(rgb, fg):
    """邊緣洋紅殘留：R 與 B 同時明顯高於 G ⇒ 把 R/B 拉回 G。"""
    a = rgb.astype(np.int16).copy()
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    edge = fg & ~_erode(fg)
    bad = edge & (r - g > 22) & (b - g > 22)
    a[bad, 0] = g[bad]
    a[bad, 2] = g[bad]
    return a.astype(np.uint8), int(bad.sum())


def _erode(m):
    p = np.pad(m, 1)
    return (p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])


def trim_shadow_small(img, min_rows=6, max_rows=16, dark=0.22, drop=1.6):
    """裁掉 AI **多畫出來的地面陰影／底台**。**在降採樣後的 128px 尺度上做**。

    怎麼判斷（實測 `void_priest_e` 的逐列平均亮度，128px 尺度）
    ----------------------------------------------------------
      · 有假陰影：列 101–115 ≈0.32（長袍），**列 116 驟降到 0.17**，之後 12 列都 ≈0.16
      · 正常腳底（`void_priest_s`）：只有最底 **2 列** ≈0.18–0.20 的真實接觸陰影
    ⇒ 三個條件缺一就會誤裁（第一版只用「亮度比」，誤裁了 12/16 張）：
      ① **絕對暗**：帶平均亮度 < `dark`
      ② **驟降**：帶上方那一列 > `drop` × 帶平均 ⇒ 假陰影與身體之間是硬邊界
      ③ **高度窗**：`min_rows` ≤ 帶高 ≤ `max_rows` ⇒ 保護 1–2 列的真實接觸陰影，
         也避免一路往上吃掉整條腿

    回傳 (新圖, 裁掉列數)。找不到就原樣返回 (img, 0)。
    """
    a = np.array(img)
    m = a[:, :, 3] > 0
    ys, _ = np.nonzero(m)
    if len(ys) == 0:
        return img, 0
    y1 = int(ys.max())

    def rowval(y):
        if y < 0:
            return None
        r = np.nonzero(m[y])[0]
        if len(r) == 0:
            return None
        return float(a[y, r][:, :3].astype(float).mean() / 255.0)

    for yt in range(max(0, y1 - max_rows) + 1, y1 + 1):
        height = y1 - yt + 1
        if height < min_rows:
            continue
        band = [v for v in (rowval(y) for y in range(yt, y1 + 1)) if v is not None]
        if not band:
            continue
        bm = float(np.mean(band))
        if bm >= dark:                      # ① 不夠暗
            continue
        up = rowval(yt - 1)
        if up is None or up <= drop * bm:   # ② 上方沒有明顯斷差
            continue
        out = a.copy()
        out[yt:, :] = 0
        return Image.fromarray(out, "RGBA"), height
    return img, 0


def to_sprite(rgb, fg):
    """裁 bbox → 整數倍 NEAREST 降採樣 → 貼到 128 畫布、腳底 127、量化 ≤48 色、alpha 二值。"""
    ys, xs = np.nonzero(fg)
    if len(ys) == 0:
        raise RuntimeError("空前景")
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    h, w = y1 - y0 + 1, x1 - x0 + 1
    rgba = np.zeros((h, w, 4), np.uint8)
    rgba[:, :, :3] = rgb[y0:y1 + 1, x0:x1 + 1]
    rgba[:, :, 3] = np.where(fg[y0:y1 + 1, x0:x1 + 1], 255, 0)
    crop = Image.fromarray(rgba, "RGBA")

    k = max(1, int(round(h / float(TARGET_H))))       # 整數倍
    nw, nh = max(1, w // k), max(1, h // k)
    if nh > CANVAS or nw > CANVAS:                    # 保險：超框再縮
        f = min(CANVAS / float(nh), CANVAS / float(nw))
        nh, nw = int(nh * f), int(nw * f)
    small = crop.resize((nw, nh), Image.NEAREST)

    # ⚠️ 裁陰影**必須在降採樣後做**：門檻（幾列）是在 128px 尺度量的，
    #    直接套在 1024×1536 原圖上會嚴重不符（原圖的陰影有 ~96 列，遠超上限），
    #    第一版就是這樣在 16 張裡誤裁了 12 張。
    small, trimmed_rows = trim_shadow_small(small)
    if trimmed_rows:
        # ⚠️ 裁完**必須重算 bbox 與尺寸**：否則下面用舊 `nh` 去置中，
        #    腳底會落在 FEET-(被裁列數) 而不是 FEET（第一版就是這樣把腳底弄到 105–123）。
        b = np.array(small)
        yy, _ = np.nonzero(b[:, :, 3] > 0)
        if len(yy) == 0:
            raise RuntimeError("裁陰影後前景為空")
        small = small.crop((0, int(yy.min()), small.width, int(yy.max()) + 1))
        nw, nh = small.size

    # 量化（保留 alpha）：只對不透明像素做中位切分
    arr = np.array(small)
    m = arr[:, :, 3] > 0
    px = arr[m][:, :3]
    uniq = np.unique(px.reshape(-1, 3), axis=0)
    if len(uniq) > 48:
        q = small.convert("RGB").quantize(colors=48, method=Image.MEDIANCUT)
        pal = np.array(q.getpalette()[: 48 * 3]).reshape(-1, 3)
        idx = np.array(q)
        rgb2 = pal[idx]
        arr[m, :3] = rgb2[m]
        small = Image.fromarray(arr, "RGBA")

    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    out.alpha_composite(small, ((CANVAS - nw) // 2, FEET - nh + 1))
    a = np.array(out)
    a[:, :, 3] = np.where(a[:, :, 3] > 127, 255, 0)     # alpha 二值
    return Image.fromarray(a, "RGBA"), trimmed_rows


def main():
    only = sys.argv[1:] or None
    raws = sorted(f for f in os.listdir(RAW) if f.lower().endswith(".png"))
    os.makedirs(OUT_ROOT, exist_ok=True)
    n = 0
    for f in raws:
        if only and not any(o in f for o in only):
            continue
        p = os.path.join(RAW, f)
        img = Image.open(p)
        rgb, fg = key_bg(img)
        fg = keep_largest_blob(fg)
        fg, stray = strip_stray_magenta(rgb, fg)
        rgb, sp = despill(rgb, fg)
        try:
            sprite, trimmed = to_sprite(rgb, fg)
        except RuntimeError as e:
            print("  [FAIL] %s %s" % (f, e)); continue
        dst = os.path.join(OUT_ROOT, f)
        sprite.save(dst)
        ys, xs = np.nonzero(np.array(sprite)[:, :, 3] > 0)
        print("  %-58s %d×%d 主體 %d×%d 腳底 y=%d 用色 %d despill=%d 裁陰影=%d 雜品紅=%d"
              % (f[:56], img.size[0], img.size[1], xs.max() - xs.min() + 1,
                 ys.max() - ys.min() + 1, ys.max(),
                 len({tuple(int(v) for v in px) for px in np.array(sprite)[np.array(sprite)[:, :, 3] > 0][:, :3]}), sp, trimmed, stray))
        n += 1
    print("\n後處理完成 %d 張 → %s" % (n, OUT_ROOT))


if __name__ == "__main__":
    main()
