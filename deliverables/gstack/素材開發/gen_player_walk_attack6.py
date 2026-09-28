# -*- coding: utf-8 -*-
"""
A5 批次：玩家 walk / attack 4 幀 → 6 幀（附錄 A §A.4 細化方案）

產出：3 職業 × 8 方向 × 2 動作 × 6 幀 = 288 檔（其中 96 檔為本批**新增**幀，
      其餘為原 4 幀搬移位置後重寫；實際磁碟淨增 = 96）。

檔名契約（`enemy_base.gd`）：`char_<class>_<action>_<dir>_<NN>.png`，
NN 自 01 起、**遇缺即停** ⇒ 必須連續寫 01..06，不可只補 05/06。

幀序規劃
--------
walk  4 幀的來源語意是「跨步 ↔ 過渡」交替：w1=跨步, w2=過渡, w3=跨步(另一足), w4=過渡。
  ⇒ 6 幀 = [w1, w2, **抬升(w2)**, w3, w4, **抬升(w4)**]
  在每個過渡姿之後插入一幀「上身抬升」⇒ 步態有上下起伏（bob），不再是機械平移。

attack  4 幀語意：a1=起手(舉劍過頭), a2=發力(前指), a3=命中(橫斬+刀弧), a4=中立。
  ⇒ 6 幀 = [a1, **後拉(a1)**, a2, a3, **前傾(a4)**, a4]
  依 §A.4「起手 → 預備（後拉，蓄勢）→ 發力 → 命中 → 收勢 → 中立」。

切分線的選擇（**兩個動作不同，不能共用**）
------------------------------------------
  · walk 用 **胸線**（0.33）：劍垂在身側，切腰線會把劍身切成兩段（斷劍，見 A1 的教訓）。
  · attack 用 **腰線**（0.55）：a1 的劍高舉過頭，必須與軀幹一起後拉；切胸線會切斷劍。
  · attack 的 a4（中立）劍同樣垂在身側 ⇒ 該幀退回 **胸線**。

⚠️ **本批的天花板（必讀）**
  從既有 4 幀衍生，只能改出「上身起伏 / 蓄勢 / 慣性」——
  **做不出真正的新抬腳姿**（那是新的腳部造型，屬手繪或 AI 重畫的範圍）。
  故 §A.4 描述的「抬腳–過渡–落地三段式」在本批只達成「落–起伏」兩段。
  要完整三段式：需為 walk 每方向新增 2 張手繪/AI 腳部造型。
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

GAME = r"D:/七傳說/game"
PACK = os.path.join(GAME, "assets/pack/creatures")
CLASSES = ["warrior", "archer", "mage"]
DIRS = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
VEC = {"n": (0, -1), "ne": (1, -1), "e": (1, 0), "se": (1, 1),
       "s": (0, 1), "sw": (-1, 1), "w": (-1, 0), "nw": (-1, -1)}

CHEST_FRAC = 0.33   # 胸線（與 gen_player_cast.py 同值）
HIP_FRAC = 0.55     # 腰線

# (來源幀號, 位移規格) —— None = 原樣
# 位移規格 = (切分線, 沿面朝方向的倍率)；dx/dy 由 VEC × 倍率算出
WALK_PLAN = [
    (1, None),
    (2, None),
    (2, ("chest", "up")),      # 抬腳·過渡：上身抬升（胸口以上，避開劍）
    (3, None),
    (4, None),
    (4, ("chest", "up")),
]
ATTACK_PLAN = [
    (1, None),                  # 起手
    (1, ("hip", "back")),       # 預備：上身往面朝反向後拉（腰線切分，劍跟軀幹一起走）
    (2, None),                  # 發力
    (3, None),                  # 命中（含刀弧）
    (4, ("chest", "fwd")),      # 收勢：慣性朝面朝方向前傾（胸線切分，避開垂劍）
    (4, None),                  # 中立
]


def bbox_alpha(img):
    ys, _ = np.nonzero(np.array(img)[:, :, 3] > 8)
    return int(ys.min()), int(ys.max())


def lean(img, frac, dx, dy):
    """把 `[0, split)` 的上半身整體平移 (dx, dy)，下半身不動。

    ⚠️ 位移後**必須填補**：只是 numpy 滾動會在切分線留一條透明縫（垂直位移時
    最底下 d 列會被丟掉）。這裡用「區域內貼近切分線的那一列」填充，等效於
    `gen_player_cast.py::shift_above` 的做法，接縫不可見。
    """
    if dx == 0 and dy == 0:
        return img.copy()
    a = np.array(img)
    top, bottom = bbox_alpha(img)
    split_y = top + int(round((bottom - top + 1) * frac))
    split_y = max(1, min(a.shape[0] - 1, split_y))
    h, w = split_y, a.shape[1]
    up = a[0:split_y]
    out = a.copy()

    shifted = up.copy()
    if dy < 0:
        d = -dy
        shifted = np.empty_like(up)
        shifted[0:h - d] = up[d:h]
        shifted[h - d:h] = up[h - 1]          # 填縫
    elif dy > 0:
        shifted = np.empty_like(up)
        shifted[dy:h] = up[0:h - dy]
        shifted[0:dy] = up[0]                 # 填縫（通常為透明列）

    if dx != 0:
        s2 = np.empty_like(shifted)
        if dx > 0:
            s2[:, dx:w] = shifted[:, 0:w - dx]
            s2[:, 0:dx] = shifted[:, 0:1]
        else:
            s2[:, 0:w + dx] = shifted[:, -dx:w]
            s2[:, w + dx:w] = shifted[:, w - 1:w]
        shifted = s2

    out[0:split_y] = shifted
    return Image.fromarray(out, "RGBA")


def shift_whole(img, dx, dy):
    """整張平移（**只用於 attack 的預備/收勢**）。
    為什麼不用 `lean` 切上半身：attack 的 a1 是「劍斜舉過頭」，**任何水平切分線都會切斷劍**
    （實測 hip 切分把劍尾切平、留下明顯斷口）。整張位移不會產生任何斷口。
    代價：位移會讓腳暫時離地 |dy| px。
      · 玩家顯示是 `centered + offset.y=-canvas/2` + `scale=48/canvas` ⇒ **尺寸由畫布決定、不吃 bbox**，
        故 2px 位移 = 0.5 螢幕像素的接地差，實機不可見；
      · 因此**永不使用 dy > 0**（往下會把腳切出畫布底邊）。
    """
    if dx == 0 and dy == 0:
        return img.copy()
    a = np.array(img)
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    ys = slice(max(0, -dy), h - max(0, dy))
    yd = slice(max(0, dy), h - max(0, -dy))
    xs = slice(max(0, -dx), w - max(0, dx))
    xd = slice(max(0, dx), w - max(0, -dx))
    out[yd, xd] = a[ys, xs]
    return Image.fromarray(out, "RGBA")


def build_frame(src_img, spec, vx, vy, lift, prep, follow):
    im = src_img
    if spec is None:
        return im.copy()
    frac_name, mode = spec
    frac = CHEST_FRAC if frac_name == "chest" else HIP_FRAC
    if mode == "up":          # 抬升（walk 過渡）
        return lean(im, frac, 0, -lift)
    if mode == "back":        # 後拉（attack 預備）：整張沿面朝反向後退，且**一律上抬**
        return shift_whole(im, -vx * prep, -prep)
    if mode == "fwd":         # 前傾（attack 收勢）：整張沿面朝方向前送（n/s 用 1px 上抬做微分）
        return shift_whole(im, vx * follow, 0 if vx != 0 else -1)
    return im.copy()


def backup_originals(dst_root):
    """先備份原始 4 幀（可回復；本專案慣例：不直接刪/覆蓋而不留退路）。
    ⚠️ 必須在寫入前跑：本批的輸出路徑與來源路徑**重疊**
    （idx4 會覆蓋原始第 4 幀，若不先備份，原始第 4 幀會被第 3 幀的內容取代）。
    ⚠️ **已存在則跳過**：本腳本可重複執行（改參數重跑），若每次都覆蓋備份，
       第二次就會把「已改成 6 幀」的檔當成原始檔備份掉，備份即失效。
    """
    import shutil
    n = skip = 0
    for cls in CLASSES:
        for dr in DIRS:
            for act in ("walk", "attack"):
                for i in range(1, 5):
                    src = os.path.join(PACK, cls, "char_%s_%s_%s_%02d.png" % (cls, act, dr, i))
                    if not os.path.exists(src):
                        continue
                    d = os.path.join(dst_root, cls)
                    os.makedirs(d, exist_ok=True)
                    dstf = os.path.join(d, os.path.basename(src))
                    if os.path.exists(dstf):
                        skip += 1
                        continue
                    shutil.copy2(src, dstf)
                    n += 1
    if skip:
        print("（備份已存在，跳過 %d 檔）" % skip)
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lift", type=int, default=3, help="walk 過渡幀上身抬升 px")
    ap.add_argument("--prep", type=int, default=2, help="attack 預備幀後拉 px")
    ap.add_argument("--follow", type=int, default=2, help="attack 收勢幀前傾 px")
    ap.add_argument("--backup-dir", default=r"D:/七傳說/deliverables/_quarantine_2026-09-24/walk_attack_4f_originals")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.dry_run:
        nb = backup_originals(args.backup_dir)
        print("已備份原始 4 幀：%d 檔 → %s" % (nb, args.backup_dir))

    made = 0
    for cls in CLASSES:
        for dr in DIRS:
            vx, vy = VEC[dr]
            for act, plan in (("walk", WALK_PLAN), ("attack", ATTACK_PLAN)):
                # ⚠️ 先把 4 張來源**全部讀進記憶體**再寫 —— 輸出路徑與來源路徑重疊，
                #    邊讀邊寫會讓 idx5 讀到「已被 idx4 覆蓋」的檔（實測會靜默污染）。
                srcs = {}
                for i in range(1, 5):
                    p = os.path.join(PACK, cls, "char_%s_%s_%s_%02d.png" % (cls, act, dr, i))
                    if os.path.exists(p):
                        srcs[i] = Image.open(p).convert("RGBA")
                for idx, (src_i, spec) in enumerate(plan, start=1):
                    if args.dry_run:
                        continue
                    if src_i not in srcs:
                        print("  [MISS] %s %s %s 來源 %02d" % (cls, act, dr, src_i))
                        continue
                    out = build_frame(srcs[src_i], spec, vx, vy, args.lift, args.prep, args.follow)
                    dst = os.path.join(PACK, cls, "char_%s_%s_%s_%02d.png" % (cls, act, dr, idx))
                    if out.size != (192, 192):
                        print("  [BAD] %s 尺寸 %s" % (dst, out.size))
                        continue
                    out.save(dst)
                    made += 1
        print("  %-8s walk/attack 6 幀完成" % cls)

    print("\n寫入 %d 檔（3 職業 × 8 方向 × 2 動作 × 6 幀 = 288）" % made)

    # ---- 驗證 ----
    problems = []
    for cls in CLASSES:
        for dr in DIRS:
            for act in ("walk", "attack"):
                for i in range(1, 7):
                    p = os.path.join(PACK, cls, "char_%s_%s_%s_%02d.png" % (cls, act, dr, i))
                    if not os.path.exists(p):
                        problems.append("缺 " + os.path.basename(p)); continue
                    im = Image.open(p).convert("RGBA")
                    a = np.array(im)
                    if im.size != (192, 192):
                        problems.append("%s 尺寸 %s" % (os.path.basename(p), im.size))
                    al = set(np.unique(a[:, :, 3]).tolist())
                    if not al <= {0, 255}:
                        problems.append("%s alpha %s" % (os.path.basename(p), sorted(al)))
                    ys, _ = np.nonzero(a[:, :, 3] > 8)
                    if len(ys) == 0 or ys.max() != 191:
                        problems.append("%s 腳底 y=%s（應 191）" % (os.path.basename(p), ys.max() if len(ys) else "空"))
    print("驗證：問題 %d %s" % (len(problems), problems[:6]))


if __name__ == "__main__":
    main()
