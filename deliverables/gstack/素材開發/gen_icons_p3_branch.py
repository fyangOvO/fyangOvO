# -*- coding: utf-8 -*-
"""
D3 批次：技能分支圖標 28 張（32×32）

規格來源
  · `01-技能体系.md` 附錄 A §A.8：分支圖標 28 張 = **14 模板 × 2**（一般態 + 選中態）
  · id 來源：`01-branches.json` → `templates[].branches[].id`（14 個，已核對）
  · 命名：`branch_icon_<tpl>_{normal,sel}_32.png`，落點 `game/assets/ui/quest/`

⚠️ **消費端尚未存在**：`skill_controller.gd` 目前只實作 `SINGLE/AOE/DASH` 三種形態
   （缺 `projectile/ground/summon/buff`），分支系統本身也還沒落地。
   本批屬「素材先行」——id 有明確定義，先備好，系統落地即可直接接。
   對照：D4（狀態圖標 12 張）**不做**，因為策劃案沒有給 id 清單，
   憑空造 id 只會製造對不上代碼的垃圾檔。
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icons import Idx, compose, PRIMS, SERIES, IDX_T, IDX_D, IDX_M, IDX_B, IDX_G  # noqa: E402

OUTDIR = r"D:/七傳說/game/assets/ui/quest"

# 14 個分支（依 01-branches.json 順序；形/義對映）
BRANCHES = [
    # (id, 基元, 色系)
    ("single_focus",    "star",      "gold"),    # 专注：倍率 +40%
    ("single_combo",    "chev",      "gold"),    # 连击：追加一段 60%
    ("aoe_expand",      "spiral",    "blood"),   # 扩张：半径 +40%
    ("aoe_linger",      "hourglass", "blood"),   # 滞留：留 3 秒区域
    ("dash_pierce",     "bolt",      "ice"),     # 贯穿：距离 +50% / 路径伤害 +30%
    ("dash_afterimage", "wing",      "ice"),     # 余像：冲刺后残影
    ("proj_sharp",      "fang",      "poison"),  # 锐锋：穿透 +2
    ("proj_scatter",    "thorn",     "poison"),  # 散射：3 枚扇形
    ("ground_deep",     "drop",      "poison"),  # 深潭：持续 +50%
    ("ground_pulse",    "dotring",   "poison"),  # 涌动：每秒脉冲
    ("summon_legion",   "banner",    "void"),    # 军团：召唤数 +1
    ("summon_elite",    "skull",     "void"),    # 精锐：召唤物伤害 +60%
    ("buff_lasting",    "ring",      "teal"),    # 持久：持续 +50%
    ("buff_empower",    "up",        "teal"),    # 强化：效果 +40%
]


def base_canvas(prim: str, n: int = 32) -> Idx:
    """一般態：深底圓片 + 符號。"""
    c = Idx(n)
    c.ell(2, 2, n - 3, n - 3, IDX_D)
    inner = Idx(18)
    PRIMS[prim](inner, 18)
    ia = inner.arr()
    for y in range(18):
        for x in range(18):
            v = int(ia[y, x])
            if v == IDX_T:
                continue
            c.px(x + 7, y + 7, IDX_G if v in (IDX_D, IDX_B) else IDX_M)
    return c


def brighten(idx_arr) -> np.ndarray:
    """選中態用：整體提亮一階（暗→中、中→亮）。"""
    a = idx_arr.copy()
    a[a == IDX_D] = IDX_M
    a[a == IDX_M] = IDX_B
    a[a == IDX_B] = IDX_G
    return a


def render(prim: str, series: str, selected: bool) -> Image.Image:
    c = base_canvas(prim)
    arr = c.outline()
    if selected:
        arr = brighten(arr)
        # 外環（只在選中態出現，且用亮色）—— 同時充當「發光邊」
        ring = Idx(32)
        steps = max(20, int(2 * np.pi * 14.5 * 1.3))
        for i in range(steps):
            t = 2 * np.pi * i / steps
            ring.px(round(15.5 + 14.5 * np.cos(t)), round(15.5 + 14.5 * np.sin(t)), IDX_G)
        r2 = ring.outline()
        m = (r2 != IDX_T) & (arr == IDX_T)
        arr[m] = r2[m]
    return compose(arr, series)


def save(img: Image.Image, name: str) -> bool:
    p = os.path.join(OUTDIR, name)
    if os.path.exists(p):
        return False
    os.makedirs(OUTDIR, exist_ok=True)
    img.save(p)
    return True


def main():
    made = skipped = 0
    for tpl, prim, series in BRANCHES:
        for state, sel in (("normal", False), ("sel", True)):
            if save(render(prim, series, sel), "branch_icon_%s_%s_32.png" % (tpl, state)):
                made += 1
            else:
                skipped += 1
    print("D3 分支圖標：新增 %d，已存在跳過 %d，合計 %d 張（14 模板 × 2 態）"
          % (made, skipped, len(BRANCHES) * 2))

    # 自校驗：色板（現讀 game_constants.gd）+ 尺寸 + alpha
    import re
    src = open(r"D:/七傳說/game/scripts/core/game_constants.gd", encoding="utf-8").read()
    pal = set()
    for cname in ("PALETTE_NEUTRAL", "PALETTE_ACCENT", "PALETTE_RARITY_SEMANTIC"):
        mm = re.search(r"const %s[^=]*=\s*\[(.*?)\]" % cname, src, re.S)
        for h in re.findall(r'"([0-9A-Fa-f]{6})"', mm.group(1)):
            pal.add((int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
    bad = []
    for tpl, _, _ in BRANCHES:
        for state in ("normal", "sel"):
            p = os.path.join(OUTDIR, "branch_icon_%s_%s_32.png" % (tpl, state))
            if not os.path.exists(p):
                bad.append((tpl + "_" + state, "MISSING")); continue
            im = Image.open(p).convert("RGBA")
            a = np.array(im)
            if im.size != (32, 32):
                bad.append((tpl, im.size))
            m = a[:, :, 3] > 0
            out = set(map(tuple, a[m][:, :3])) - pal
            if out:
                bad.append((tpl + "_" + state, "%d 色超板" % len(out)))
            if not set(np.unique(a[:, :, 3]).tolist()) <= {0, 255}:
                bad.append((tpl + "_" + state, "alpha"))
    print("自校驗（PALETTE_ALL %d 色）：異常 %d %s" % (len(pal), len(bad), bad[:5]))


if __name__ == "__main__":
    main()
