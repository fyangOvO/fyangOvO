#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""XP 曲线自洽性复核工具（GDD 0.5）。

用途：给定「单关经验产出」与「内容量（关/轮）」，复核 `XP_ToNext(L)` 是否满足
GDD 0.5 自述的升级节奏意图（前期约 3–5 关升 1 级，后期约 8–12 关升 1 级），
并反解候选曲线族的系数。

口径来源：
  - 单关经验 4,500–7,200：269 杂兵下的产出（= 150 杂兵基准 2,500–4,000 线性缩放）
  - 内容量 100 关/轮 = 20 关 × 5 难度层级
  - GDD 0.5 意图：前期 3–5 关/级，后期 8–12 关/级

用法：
    python xp_curve_check.py
输出：
    out/xp-check.txt（同时打印到 stdout）
"""

from __future__ import annotations

import math
import os
import sys

# ---------------------------------------------------------------------------
# 口径常量
# ---------------------------------------------------------------------------
XP_LO, XP_HI = 4500.0, 7200.0          # 单关经验区间（269 杂兵）
XP_RUN = (XP_LO + XP_HI) / 2.0         # 取中点 5,850
LMAX = 60                              # 账号等级上限
CONTENT = 20 * 5                       # 20 关 × 5 难度层级 = 100 关/轮
BAND_EARLY = (3.0, 5.0)                # 前期 关/级
BAND_LATE = (8.0, 12.0)                # 后期 关/级
NODE_EARLY, NODE_LATE = 20, 50         # 前期 / 后期的代表节点


def cum_xp(fn, upto: int) -> float:
    """从 L1 升到 L`upto` 所需的累计经验（不含 upto 本身）。"""
    return sum(fn(i) for i in range(1, upto))


def rpl(fn, L: int) -> float:
    """某等级升下一级需要打多少关。"""
    return fn(L) / XP_RUN


def total_runs(fn) -> float:
    """1→60 总共需要打多少关。"""
    return cum_xp(fn, LMAX) / XP_RUN


def level_after_runs(fn, runs: float):
    """打完 runs 关之后大概到几级（返回 (等级, 该级进度)）。"""
    xp = runs * XP_RUN
    c = 0.0
    for L in range(1, 300):
        if c + fn(L) > xp:
            return L, (xp - c) / fn(L)
        c += fn(L)
    return None, None


def runs_to_level(fn, L: int) -> float:
    return cum_xp(fn, L) / XP_RUN


def band_judge(r: float) -> str:
    if r < BAND_EARLY[0]:
        return "过快 ✗"
    if r <= BAND_EARLY[1]:
        return "前期带内 ✓"
    if r <= BAND_LATE[1]:
        return "中间带"
    return "过慢 ✗"


CANDIDATES = [
    ("GDD 现行  180·L^1.6", lambda L: 180.0 * L ** 1.6),
    ("仅降基值  111·L^1.6", lambda L: 111.0 * L ** 1.6),
    ("仅降基值  100·L^1.6", lambda L: 100.0 * L ** 1.6),
    ("线性 1000·L", lambda L: 1000.0 * L),
    ("线性 1100·L", lambda L: 1100.0 * L),
    ("线性 1170·L（意图精确解）", lambda L: 1170.0 * L),
    ("平底+线性 max(23400,1170·L)", lambda L: max(23400.0, 1170.0 * L)),
    ("L^1.2 基值 900", lambda L: 900.0 * L ** 1.2),
    ("L^1.3 基值 700", lambda L: 700.0 * L ** 1.3),
]


def main() -> int:
    out: list[str] = []
    P = out.append

    P("=" * 100)
    P("XP 曲线复核 · 单关经验 = %.0f（%.0f–%.0f 中点）  内容量 = %d 关/轮"
      "  目标 = 前期 %g–%g 关/级，后期 %g–%g 关/级"
      % (XP_RUN, XP_LO, XP_HI, CONTENT, *BAND_EARLY, *BAND_LATE))
    P("=" * 100)

    # ---- 1. 复核 GDD 现行曲线 ----
    gdd = CANDIDATES[0][1]
    P("")
    P("【1】GDD 现行曲线 `XP_ToNext(L) = 180 × L^1.6` 逐级核对")
    P("%-12s %-12s %-14s %-10s" % ("升级", "需经验", "折算关卡数", "判定"))
    for L in (1, 9, 10, 19, 20, 29, 30, 34, 35, 44, 45, 59, 60):
        need = gdd(L)
        r = need / XP_RUN
        P("L%-3d→%-3d  %-12.0f %-14.1f %-10s" % (L, L + 1, need, r, band_judge(r)))
    P("")
    P("1→60 总经验 = %.0f  →  总关数 = %.1f 关  →  内容轮数 = %.2f 轮"
      % (cum_xp(gdd, LMAX), total_runs(gdd), total_runs(gdd) / CONTENT))
    P("打完 1 轮内容（%d 关）时的等级 ≈ L%d" % (CONTENT, level_after_runs(gdd, CONTENT)[0]))
    P("到 L15（守护分支）= %.1f 关   到 L30（秘法分支）= %.1f 关   到 L60 = %.1f 关"
      % (runs_to_level(gdd, 15), runs_to_level(gdd, 30), runs_to_level(gdd, 60)))
    P("折算墙钟：%.0f 小时（按 17.5 分钟/关）" % (total_runs(gdd) * 17.5 / 60.0))

    # ---- 2. 候选横向对比 ----
    P("")
    P("【2】候选曲线横向对比（R(L) = 该级需要打多少关）")
    hdr = "%-30s" % "曲线"
    for L in (1, 5, 10, 15, 20, 30, 40, 50, 60):
        hdr += "%7s" % ("R(%d)" % L)
    hdr += "%10s%8s" % ("总关数", "轮数")
    P(hdr)
    for name, fn in CANDIDATES:
        row = "%-30s" % name
        for L in (1, 5, 10, 15, 20, 30, 40, 50, 60):
            row += "%7.1f" % rpl(fn, L)
        row += "%10.0f%8.2f" % (total_runs(fn), total_runs(fn) / CONTENT)
        P(row)

    # ---- 3. 锚点合规性 ----
    P("")
    P("【3】锚点合规性（R(20) 应落在 %g–%g，R(50) 应落在 %g–%g）" % (*BAND_EARLY, *BAND_LATE))
    P("%-30s %8s %8s %8s %8s %8s %10s %8s"
      % ("曲线", "R(20)", "R(50)", "R(60)", "到L15", "到L30", "1轮后等级", "总轮数"))
    for name, fn in CANDIDATES:
        r20, r50, r60 = rpl(fn, 20), rpl(fn, 50), rpl(fn, 60)
        ok20 = "✓" if BAND_EARLY[0] <= r20 <= BAND_EARLY[1] else "✗"
        ok50 = "✓" if BAND_LATE[0] <= r50 <= BAND_LATE[1] else "✗"
        lv, _ = level_after_runs(fn, CONTENT)
        P("%-30s %7.1f%s %7.1f%s %8.1f %8.1f %8.1f %10d %8.2f"
          % (name, r20, ok20, r50, ok50, r60, runs_to_level(fn, 15),
             runs_to_level(fn, 30), lv, total_runs(fn) / CONTENT))

    # ---- 4. 两锚点反解 A·L^b ----
    P("")
    P("【4】按 GDD 意图中点反解 `A·L^b`（锚点：R(20)=%g，R(50)=%g）"
      % ((BAND_EARLY[0] + BAND_EARLY[1]) / 2, (BAND_LATE[0] + BAND_LATE[1]) / 2))
    tgt_e = (BAND_EARLY[0] + BAND_EARLY[1]) / 2.0
    tgt_l = (BAND_LATE[0] + BAND_LATE[1]) / 2.0
    b = math.log(tgt_l / tgt_e) / math.log(NODE_LATE / NODE_EARLY)
    a = tgt_e * XP_RUN / NODE_EARLY ** b
    fn = lambda L: a * L ** b  # noqa: E731
    P("两锚点解的指数 b = ln(%g/%g) / ln(%d/%d) = %.4f" % (tgt_l, tgt_e, NODE_LATE, NODE_EARLY, b))
    P("对应基值 A = %.1f  ⇒  曲线 = %.0f · L^%.2f" % (a, a, b))
    P("校验：R(20)=%.2f  R(50)=%.2f  R(60)=%.2f  总关数=%.0f  轮数=%.2f  到L15=%.1f  到L30=%.1f"
      % (rpl(fn, 20), rpl(fn, 50), rpl(fn, 60), total_runs(fn),
         total_runs(fn) / CONTENT, runs_to_level(fn, 15), runs_to_level(fn, 30)))
    P("边界校验：R(15)=%.2f  R(25)=%.2f  R(45)=%.2f  R(55)=%.2f"
      % (rpl(fn, 15), rpl(fn, 25), rpl(fn, 45), rpl(fn, 55)))

    # ---- 5. 若坚持 L^1.6 形态，反解基值 ----
    P("")
    P("【5】若坚持 `A·L^1.6` 形态，按「总关数」反解 A（看它能否同时满足锚点）")
    s16 = sum(i ** 1.6 for i in range(1, LMAX))
    for tr in (300.0, 354.0, 400.0, 486.0):
        aa = tr * XP_RUN / s16
        f2 = lambda L, aa=aa: aa * L ** 1.6  # noqa: E731
        P("总关数 %3.0f → A = %6.1f   此时 R(20)=%.1f  R(50)=%.1f  R(60)=%.1f"
          "  到L15=%.1f 关  到L30=%.1f 关"
          % (tr, aa, rpl(f2, 20), rpl(f2, 50), rpl(f2, 60),
             runs_to_level(f2, 15), runs_to_level(f2, 30)))

    # ---- 6. 推荐候选逐级明细 ----
    P("")
    P("【6】推荐候选逐级明细（线性 1100·L）")
    rec = CANDIDATES[4][1]
    P("%-12s %-12s %-14s %-10s" % ("等级", "需经验", "折算关卡数", "累计关数"))
    cum = 0.0
    for L in list(range(1, 11)) + [15, 20, 25, 30, 35, 40, 45, 50, 55, 59]:
        P("L%-3d→%-3d  %-12.0f %-14.2f %-10.1f" % (L, L + 1, rec(L), rpl(rec, L), cum))
        cum += rec(L)
    P("总关数 = %.1f（%.2f 轮）  墙钟 ≈ %.0f 小时"
      % (total_runs(rec), total_runs(rec) / CONTENT, total_runs(rec) * 17.5 / 60.0))
    P("打完 1 轮内容（%d 关）时的等级 ≈ L%d" % (CONTENT, level_after_runs(rec, CONTENT)[0]))

    # ---- 7. 灵敏度 ----
    P("")
    P("【7】灵敏度：单关经验取区间上下界时的总关数")
    for name, fn2 in (("GDD 180·L^1.6", gdd), ("线性 1100·L", rec)):
        for xp, tag in ((XP_LO, "下界 4500"), (XP_RUN, "中点 5850"), (XP_HI, "上界 7200")):
            tr = cum_xp(fn2, LMAX) / xp
            P("%-18s %-12s 总关数 = %6.1f 关（%.2f 轮）" % (name, tag, tr, tr / CONTENT))

    # ---- 8. 反证：「前期」若包含 L1–10，会付出什么代价 ----
    P("")
    P("【8】反证：若强行要求 R(10)=4（即「前期」包含 L1–10），反解 `A·L^b`（锚点 R(10)=4，R(60)=12）")
    b2 = math.log(BAND_LATE[1] / 4.0) / math.log(60.0 / 10.0)
    a2 = 4.0 * XP_RUN / 10.0 ** b2
    f3 = lambda L: a2 * L ** b2  # noqa: E731
    P("b = ln(%g/4) / ln(60/10) = %.4f    A = %.1f  ⇒  曲线 = %.0f · L^%.2f"
      % (BAND_LATE[1], b2, a2, a2, b2))
    P("校验：R(10)=%.2f  R(15)=%.2f  R(20)=%.2f  R(30)=%.2f  R(50)=%.2f  R(60)=%.2f"
      % (rpl(f3, 10), rpl(f3, 15), rpl(f3, 20), rpl(f3, 30), rpl(f3, 50), rpl(f3, 60)))
    P("总关数 = %.0f（%.2f 轮）  →  代价：R(20) 从 4.0 抬到 %.2f，总量从 3.5 轮涨到 %.2f 轮"
      % (total_runs(f3), total_runs(f3) / CONTENT, rpl(f3, 20), total_runs(f3) / CONTENT))

    # ---- 8. 模型空白：单关经验 × 难度层级加成 ----
    # 现行口径把「单关经验」当成与难度层级无关的常数（4,500–7,200/关）。
    # 但 ARPG 惯例是「难度越高经验越多」。本段评估：加上层级加成后，
    # 1→60 能不能落进 2–3 轮，从而不必大改曲线形态。
    P("")
    P("【8】模型空白评估：单关经验加「难度层级加成」后，1→60 需要几轮？")
    P("假设：玩家在已解锁的最高层级刷；层级按等级解锁（每 step 级上一层）。")

    def tier_idx(L: int, step: int) -> int:
        """层级索引：L1..step → 0（梦魇 I），…，封顶 4（梦魇 V）。"""
        return min(4, (L - 1) // step)

    def total_runs_tier(fn, mult, step: int) -> float:
        return sum(fn(L) / (XP_RUN * mult[tier_idx(L, step)]) for L in range(1, LMAX))

    def runs_to_level_tier(fn, mult, step: int, target: int) -> float:
        return sum(fn(L) / (XP_RUN * mult[tier_idx(L, step)]) for L in range(1, target))

    def level_after_content(fn, mult, step: int) -> int:
        """打完 1 轮内容（CONTENT 关）时到几级。"""
        budget = CONTENT * XP_RUN
        c, lv = 0.0, 1
        for L in range(1, 300):
            cost = fn(L) / mult[tier_idx(L, step)]
            if c + cost > budget:
                break
            c += cost
            lv = L + 1
        return lv

    SCHEMES = [
        ("无加成（现行口径）", (1.0, 1.0, 1.0, 1.0, 1.0)),
        ("线性 1.0/1.5/2.0/2.5/3.0", (1.0, 1.5, 2.0, 2.5, 3.0)),
        ("几何 ×1.25", tuple(1.25 ** i for i in range(5))),
        ("几何 ×1.4", tuple(1.4 ** i for i in range(5))),
        ("同款 tierDMG 1.23^n", tuple(1.23 ** i for i in range(5))),
    ]
    for step in (12, 15, 20):
        P("")
        P("  ── 层级解锁节奏：每 %d 级上一层（梦魇 V 在 L%d 解锁）──" % (step, 4 * step + 1))
        P("  %-40s %10s %8s %10s %10s %12s" %
          ("曲线 + 层级加成方案", "总关数", "轮数", "到L15", "到L30", "1轮后等级"))
        for cname, fn in (("180·L^1.6", gdd), ("1100·L", rec)):
            for sname, mult in SCHEMES:
                tr = total_runs_tier(fn, mult, step)
                P("  %-40s %10.0f %8.2f %10.1f %10.1f %12d" %
                  (cname + " + " + sname, tr, tr / CONTENT,
                   runs_to_level_tier(fn, mult, step, 15),
                   runs_to_level_tier(fn, mult, step, 30),
                   level_after_content(fn, mult, step)))

    P("")
    P("  墙钟换算（按 17.5 分钟/关）：")
    for cname, fn in (("180·L^1.6", gdd), ("1100·L", rec)):
        for sname, mult in (("无加成", SCHEMES[0][1]), ("几何 ×1.4", SCHEMES[3][1])):
            tr = total_runs_tier(fn, mult, 15)
            P("    %-12s + %-10s → %6.0f 关 → %6.0f 小时" %
              (cname, sname, tr, tr * 17.5 / 60.0))

    text = "\n".join(out) + "\n"
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "xp-check.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
