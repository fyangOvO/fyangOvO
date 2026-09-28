# -*- coding: utf-8 -*-
"""
D4 批次：狀態欄圖標 `status_<id>_24.png` × 12（buff 6 + debuff 6）

規格來源
  · `03-装备特色玩法.md` §11.1.1：異常鍵 `AILMENT_BURN / AILMENT_SLOW / AILMENT_POISON`
    ＋ 建議新鍵「麻痺（雷）/ 虛弱（暗影）」
  · `01-技能体系.md` 附錄 A §A.8：狀態圖標 **12 張（buff / debuff）**、24×24、`assets/ui/quest/`

與 F3（`ailment_*`，gen_icons_p2.py）的分工 —— **不是重複**：
  · `ailment_*`  = 元素異常圖標（飄字 / 命中提示用），按**元素色**區分
  · `status_*`   = **狀態欄**圖標（角色頭上那排長駐圖標），按 **buff/debuff 語意**區分：
      buff   → `teal`  系（青綠＝增益）
      debuff → `blood` 系（暗紅＝減益）
    狀態欄一眼要分「敵我」，元素色在 24px 狀態欄裡是次要資訊 ⇒ 故意壓掉。
    符號本體沿用 F3 同一批基元 ⇒ 兩套圖標同一語言、不衝突。

技術保證（與 gen_icons.py 同源）：索引畫布 → 自動描邊 → 最後才映射 `PALETTE_ALL`
⇒ 結構上不可能畫出色板外顏色。
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icons import Idx, compose, PRIMS, IDX_D, IDX_M, IDX_B, IDX_G  # noqa: E402

OUT = r"D:/七傳說/game/assets/ui/quest"
GAME = r"D:/七傳說/game"

# ── buff 6（增益）── 基元取自 PRIMS 既有鍵，符號語意對應遊戲機制
#    （warcry=戰吼攻↑ / blood_rage=血怒攻速 / iron_bulwark=鐵壁防↑ /
#      hawk_eye=鷹眼暴擊 / regen=回血 / shield=護盾格擋）
BUFFS = [
    ("warcry",       "up"),     # 戰吼：向上的力量（C4 光環 aura_warcry 同源）
    ("blood_rage",   "wing"),   # 血怒：攻速（翅膀＝速度；C4 aura_blood_rage）
    ("iron_bulwark", "plate"),  # 鐵壁：護甲（C4 aura_iron_bulwark）
    ("hawk_eye",     "eye"),    # 鷹眼：暴擊（C4 aura_hawk_eye）
    ("regen",        "heart"),  # 回復：命中回血（既有詞綴機制）
    ("shield",       "shield"), # 護盾：格擋
]

# ── debuff 6（減益）── 與 F3 的 AILMENTS **同鍵同基元**（保持項目內一致），
#    但走 blood 系 + 角標向下 ⇒ 狀態欄語意。
DEBUFFS = [
    ("burn",   "flame"),   # 燃燒（AILMENT_BURN）
    ("chill",  "snow"),    # 冰凍/緩速（AILMENT_SLOW）
    ("poison", "drop"),    # 中毒（AILMENT_POISON）
    ("shock",  "bolt"),    # 麻痺/感電（§11 建議：雷異常）
    ("curse",  "skull"),   # 詛咒/虛弱（§11 建議：暗影異常）
    ("sunder", "broken"),  # 破甲
]


def _scaled(prim: str, n: int) -> Idx:
    c = Idx(n)
    PRIMS[prim](c, n)
    return c


def _stamp(inner: Idx, c: Idx, ox: int, oy: int, hi: int, glow: int) -> None:
    """把 16px 符號疊上 24px 畫布：符號本色 → 亮 / 輝光（在深底上才看得見）。
    （與 gen_icons_p2.render_ailment 同一手法）"""
    ia = inner.arr()
    for y in range(inner.n):
        for x in range(inner.n):
            v = int(ia[y, x])
            if v == 0:
                continue
            c.px(ox + x, oy + y, glow if v >= 4 else hi)


def render_status(prim: str, is_buff: bool) -> Image.Image:
    """24×24 狀態欄圖標：圓形深底 + 中央符號 + 右下角 buff/debuff 角標。

    角標放**右下**（不是右上）：中央符號多半偏上（基元的視覺重心），
    右下 5×5 是全圖最空的角落 ⇒ 角標不會蓋到符號。
    buff = 向上箭頭（IDX_G 輝光）；debuff = 向下箭頭（IDX_B 亮）。
    """
    c = Idx(24)
    # 圓形深底（radius 10，中心 11.5）⇒ 狀態欄圖標的標準外形（有別於 ailment 的方 chip）
    c.ell(2, 2, 21, 21, IDX_D)
    # 內圈中間調，讓符號與底有層次
    c.ell(4, 4, 19, 19, IDX_M)

    inner = _scaled(prim, 15)
    # ⚠️ 細節與主體**都用 IDX_G（該色系最亮階）**：
    #    `_stamp` 的分工是「基元細節(idx_M)→hi、主體(idx_B)→glow」，
    #    但 `teal` 系的 hi(2FA37A) 與內圈(1B6B52) 亮度差只有 0x14 ⇒ 細節糊掉
    #    （實測 iron_bulwark / shield 變成一團綠）。blood 系差 0x38 才看得清。
    #    ⇒ 狀態欄 24px 本就該是單色剪影，統一壓到最亮階最穩。
    _stamp(inner, c, 4, 4, IDX_G, IDX_G)

    # ── 角標：右下 5×5 箭頭（三角形）──
    if is_buff:
        # 向上 ▲：(19,22) (21,22) (20,19)
        c.poly([(18, 22), (22, 22), (20, 18)], IDX_G)
    else:
        # 向下 ▼：(18,19) (22,19) (20,23)
        c.poly([(18, 18), (22, 18), (20, 22)], IDX_B)

    return compose(c.outline(), "teal" if is_buff else "blood")


def save(img: Image.Image, name: str) -> bool:
    p = os.path.join(OUT, name)
    if os.path.exists(p):
        return False
    img.save(p)
    return True


def main() -> None:
    made = rows = 0
    for key, prim in BUFFS:
        if save(render_status(prim, True), "status_%s_24.png" % key):
            made += 1
        rows += 1
        print("  status_%s_24.png  (buff, %s)" % (key, prim))
    for key, prim in DEBUFFS:
        if save(render_status(prim, False), "status_%s_24.png" % key):
            made += 1
        rows += 1
        print("  status_%s_24.png  (debuff, %s)" % (key, prim))

    # ── 自校驗：色板合規（PALETTE_ALL 44 色）+ alpha 二值 + 尺寸 ──
    import re
    src = open(os.path.join(GAME, "scripts/core/game_constants.gd"), encoding="utf-8").read()
    pal = set()
    for cst in ("PALETTE_NEUTRAL", "PALETTE_ACCENT", "PALETTE_RARITY_SEMANTIC"):
        m = re.search(r"const %s[^=]*=\s*\[(.*?)\]" % cst, src, re.S)
        for h in re.findall(r'"([0-9A-Fa-f]{6})"', m.group(1)):
            pal.add((int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
    bad = []
    files = sorted(f for f in os.listdir(OUT) if f.startswith("status_") and f.endswith(".png"))
    for f in files:
        a = np.array(Image.open(os.path.join(OUT, f)).convert("RGBA"))
        m = a[:, :, 3] > 0
        out = {tuple(int(v) for v in px[:3]) for px in a[m]} - pal
        al = set(np.unique(a[:, :, 3]).tolist())
        if out or not al <= {0, 255} or a.shape[0] != 24 or a.shape[1] != 24:
            bad.append((f, len(out), sorted(al)[:3], a.shape[:2]))
    print("\n合計 %d 張（本次新產 %d）｜自校驗：異常 %d %s"
          % (len(files), made, len(bad), bad[:4]))


if __name__ == "__main__":
    main()
