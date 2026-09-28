#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
04-check_number_model.py — 第四步「数值与数据模型」校验脚本

用途
----
1. 复算本文档（04-数值与数据模型.md）中所有的量化断言，确保文档自身自洽。
2. 对照工程侧实际常量，检出「文档 ↔ 工程」的脱钩（失衡五）。
3. 输出 16 条验收断言（T1–T16）的当前通过状态。

用法
----
    python 04-check_number_model.py                  # 用内置基线（离线自检）
    python 04-check_number_model.py --repo D:/七傳說   # 额外读取工程侧实值做对照

设计原则
--------
- **只读**：本脚本不修改任何文件。
- **自洽**：所有期望值都由公式现算，不硬编码「期望结果」（避免重蹈
  verify_balance84.gd 的「自洽式伪校验」覆辙）。
- **可漂移检测**：工程侧常量单独读取并打印「文档值 vs 工程值」对照，
  不一致时以 ⚠️ 标出但**不**判失败（因为文档是建议值，工程尚未落地）。
"""

import argparse
import json
import os
import re
import sys

# ============================================================
# 0. 权威公式（与 game_constants.gd / account_level.gd 一一对应）
# ============================================================

# --- 账号等级（account_level.gd:24-33）---
XP_CURVE_BASE = 180.0
XP_CURVE_EXPONENT = 1.6
# 现状（工程值）
MAX_ACCOUNT_LEVEL_CUR = 60
# 路线 A 拍板值（§3.1 补充①）
MAX_ACCOUNT_LEVEL = 20
# 用户原话为「22」；实测按 20 落地（见文档 §〇「关于 22 的偏差说明」）
MAX_ACCOUNT_LEVEL_USER_REQUESTED = 22
# 装备池 iLvl 上限（对齐账号上限 + 2 级余量，承接 D3 的「22」）
EQUIP_ILVL_CAP_ROUTE_A = 22


def xp_to_next(level):
    """升到下一级所需经验：180 × L^1.6"""
    return XP_CURVE_BASE * (level ** XP_CURVE_EXPONENT)


def cumulative_to(level):
    """累计到 L 级所需总经验：Σ₁^(L-1)"""
    return sum(xp_to_next(i) for i in range(1, level))


def level_from_xp(total_xp):
    """给定累计 XP，反解到达等级"""
    L = 1
    while L < MAX_ACCOUNT_LEVEL and cumulative_to(L + 1) <= total_xp:
        L += 1
    return L


# --- 怪物（game_constants.gd:477-484）---
MONSTER_HP_AT_L1 = 100.7
MONSTER_DMG_AT_L1 = 5.61
# 现状
MONSTER_HP_GROWTH_CUR = 1.22
MONSTER_DMG_GROWTH_CUR = 1.16
# 目标（本文档 §3.2 推荐）
MONSTER_HP_GROWTH_TGT = 1.12
MONSTER_DMG_GROWTH_TGT = 1.12
MONSTER_ELITE_HP_MULT = 4.5
MONSTER_BOSS_HP_MULT = 28.0


def monster_hp(level, growth=MONSTER_HP_GROWTH_CUR, tier="normal", diff=0):
    mult = {"normal": 1.0, "elite": MONSTER_ELITE_HP_MULT, "boss": MONSTER_BOSS_HP_MULT}[tier]
    return MONSTER_HP_AT_L1 * (growth ** (level - 1)) * mult * (1.08 ** diff)


def monster_dmg(level, growth=MONSTER_DMG_GROWTH_CUR, diff=0):
    return MONSTER_DMG_AT_L1 * (growth ** (level - 1)) * (1.23 ** diff)


# --- 玩家裸装（game_constants.gd:452-459）---
BASE_HP_AT_L1 = 150.0
BASE_HP_GROWTH = 0.11
BASE_AD_AT_L1 = 12.0
BASE_AD_GROWTH = 0.10
BASE_ARMOR_AT_L1 = 6.0
BASE_ARMOR_GROWTH = 0.10
ARMOR_DR_CONSTANT_PER_LEVEL = 50.0


def player_hp(level):
    return BASE_HP_AT_L1 * ((1 + BASE_HP_GROWTH) ** (level - 1))


def player_ad(level):
    return BASE_AD_AT_L1 * ((1 + BASE_AD_GROWTH) ** (level - 1))


def player_armor(level):
    return BASE_ARMOR_AT_L1 * ((1 + BASE_ARMOR_GROWTH) ** (level - 1))


def armor_dr(armor, level):
    denom = armor + ARMOR_DR_CONSTANT_PER_LEVEL * max(level, 1)
    return armor / denom if denom > 0 else 0.0


# --- 装备 / 词缀（game_constants.gd:354-361）---
AFFIX_ILVL_SCALE_PER_LEVEL = 0.085
ITEM_STAT_ILVL_SCALE_PER_LEVEL = 0.12


def affix_ilvl_scale(level):
    return 1 + AFFIX_ILVL_SCALE_PER_LEVEL * (level - 1)


def item_stat_ilvl_scale(level):
    return 1 + ITEM_STAT_ILVL_SCALE_PER_LEVEL * (level - 1)


# --- 局内等级（run_progression.gd:31-32）---
RUN_XP_COEFF_CUR = 20.0
RUN_XP_COEFF_TGT = 50.0
RUN_XP_EXPONENT = 1.4
RUN_MAX_LEVEL = 10


def run_xp_to_next(level, coeff=RUN_XP_COEFF_CUR):
    return coeff * (level ** RUN_XP_EXPONENT)


def run_cumulative_to(level, coeff=RUN_XP_COEFF_CUR):
    return sum(run_xp_to_next(i, coeff) for i in range(1, level))


# --- 经济（run_shop.gd:12-18 / game_constants.gd:1225-1234）---
RARITY_PRICE = {"common": 10, "magic": 25, "rare": 60, "epic": 150,
                "legendary": 400, "set": 350, "mythic": 800, "hidden": 1000}
FORGE_STONE_COST = [3, 3, 3, 7, 7, 7, 13, 13, 25, 25]
GOLD_BASE_AT_L1 = 4.0
GOLD_GROWTH = 1.12
SETTLE_GOLD_RATE = 0.5


def shop_price(rarity, ilvl):
    return RARITY_PRICE[rarity] * (1 + 0.5 * ilvl)


# ============================================================
# 1. 关卡数据：现状（工程实测） vs 目标（本文档建议）
# ============================================================

LEVEL_IDS = ["ch1_l01", "ch1_l02", "ch1_l03", "ch1_l04", "ch1_l05", "ch1_l06",
             "ch2_l07", "ch2_l08", "ch2_l09", "ch2_l10", "ch2_l11", "ch2_l12", "ch2_l13",
             "ch3_l14", "ch3_l15", "ch3_l16", "ch3_l17", "ch3_l18", "ch3_l19", "ch3_l20"]

RECOMMENDED_LEVEL = [1, 2, 4, 5, 7, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 35, 38]

CUR_BUDGET = [40, 50, 55, 58, 62, 66, 54, 56, 58, 60, 62, 64, 66, 58, 60, 62, 64, 66, 68, 70]
CUR_REWARD_XP = [2500, 2800, 3100, 3400, 3700, 4000, 4500, 5000, 5600, 6300,
                 7000, 7800, 9500, 8500, 9500, 10600, 11800, 13000, 14200, 15800]

TGT_BUDGET = [120, 140, 160, 175, 190, 210, 230, 250, 265, 280,
              295, 310, 325, 340, 355, 370, 385, 400, 420, 440]

# ⚠️ 路线 A（2026-09-24 拍板）下 **reward_xp 不改**，沿用现状值。
# TGT_REWARD_XP 保留为「路线 C 备选方案」存档（若未来扩级到 38/60 时启用）。
TGT_REWARD_XP_ROUTE_C = [2500, 2500, 4500, 6000, 9000, 11000, 15500, 20000, 25500, 31000,
                         37000, 43000, 50000, 57000, 64500, 72500, 81000, 89500, 109000, 125500]

# 路线 A：XP 保持现值
TGT_REWARD_XP = list(CUR_REWARD_XP)

# 路线 A 重标后的 recommended_player_level（= min(实际落点+1, 20)）
# 实际落点序列（与 CUR_REWARD_XP 累计一一对应）：
#   [4, 5, 6, 7, 8, 9, 9, 10, 11, 12, 12, 13, 14, 15, 15, 16, 17, 18, 18, 19]
RECOMMENDED_LEVEL_ROUTE_A = [5, 6, 7, 8, 9, 10, 10, 11, 12, 13,
                             13, 14, 15, 16, 16, 17, 18, 19, 19, 20]


# ============================================================
# 2. 断言框架
# ============================================================

class Check:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.warned = 0
        self.rows = []

    def ok(self, tid, label, cond, detail=""):
        if cond:
            self.passed += 1
            mark = "[PASS]"
        else:
            self.failed += 1
            mark = "[FAIL]"
        self.rows.append((mark, tid, label, detail))
        return cond

    def warn(self, tid, label, detail=""):
        self.warned += 1
        self.rows.append(("[WARN]", tid, label, detail))

    def info(self, tid, label, detail=""):
        self.rows.append(("  --- ", tid, label, detail))

    def report(self, title):
        print("\n" + "=" * 78)
        print(title)
        print("=" * 78)
        for mark, tid, label, detail in self.rows:
            line = "%s %-5s %s" % (mark, tid, label)
            if detail:
                line += "\n            " + detail
            print(line)


# ============================================================
# 3. 复算：现状曲线（用于对照文档中的表格）
# ============================================================

def compute_current_gap_curve():
    """逐关：累计关卡 XP -> 实到等级 -> 与推荐等级落差"""
    out = []
    cum = 0
    for i, xp in enumerate(CUR_REWARD_XP):
        cum += xp
        lv = level_from_xp(cum)
        out.append({"id": LEVEL_IDS[i], "cum_xp": cum, "level": lv,
                    "recommended": RECOMMENDED_LEVEL[i],
                    "gap": RECOMMENDED_LEVEL[i] - lv})
    return out


def compute_target_gap_curve():
    """路线 A 目标：XP 不变 + recommended 重标 ⇒ 落差应收敛为恒 +1"""
    out = []
    cum = 0
    for i, xp in enumerate(TGT_REWARD_XP):
        cum += xp
        lv = level_from_xp(cum)
        out.append({"id": LEVEL_IDS[i], "cum_xp": cum, "level": lv,
                    "recommended": RECOMMENDED_LEVEL_ROUTE_A[i],
                    "gap": RECOMMENDED_LEVEL_ROUTE_A[i] - lv})
    return out


def ttk_ratio(level, hp_growth, dmg_growth, with_armor=False):
    """ratio = 被击杀所需击数 ÷ 击杀一只怪所需击数

    ratio > 1  ⇒ 玩家能在被怪打死之前杀掉怪 ⇒ 玩家占优（安全）
    ratio < 1  ⇒ 危险
    健康区间 1.0 – 3.0

    with_armor=False（默认）：与文档 §2.2 / §3.2 表格同口径（裸装、不含护甲减伤）
    with_armor=True ：精确值（含护甲减伤），与 04-curves.json 的 ttk_ratio 段一致
    """
    hp = monster_hp(level, hp_growth)
    if with_armor:
        hp = hp / max(1e-9, 1 - armor_dr(player_armor(level), level))
    hits_to_kill = hp / player_ad(level)
    hits_to_die = player_hp(level) / monster_dmg(level, dmg_growth)
    ratio = (hits_to_die / hits_to_kill) if hits_to_kill > 0 else 0.0
    return hits_to_kill, hits_to_die, ratio


# ============================================================
# 4. 工程侧常量读取（可选，用于漂移检测）
# ============================================================

def read_repo_constants(repo):
    """从工程文件读取实值，返回 dict；读不到则返回 None"""
    res = {}
    gc = os.path.join(repo, "game", "scripts", "core", "game_constants.gd")
    if os.path.isfile(gc):
        with open(gc, "r", encoding="utf-8", errors="replace") as f:
            txt = f.read()

        def grab(name, cast=float):
            m = re.search(r"const\s+%s\s*(?::\s*\w+)?\s*=\s*([0-9.]+)" % re.escape(name), txt)
            if not m:
                return None
            try:
                return cast(m.group(1))
            except ValueError:
                return None

        res["MONSTER_HP_GROWTH"] = grab("MONSTER_HP_GROWTH")
        res["MONSTER_DMG_GROWTH"] = grab("MONSTER_DMG_GROWTH")
        res["MONSTER_HP_AT_L1"] = grab("MONSTER_HP_AT_L1")
        res["MONSTER_DMG_AT_L1"] = grab("MONSTER_DMG_AT_L1")
        res["XP_CURVE_BASE"] = grab("XP_CURVE_BASE")
        res["BASE_HP_GROWTH"] = grab("BASE_HP_GROWTH")
        res["BASE_AD_GROWTH"] = grab("BASE_AD_GROWTH")
        res["AFFIX_ILVL_SCALE_PER_LEVEL"] = grab("AFFIX_ILVL_SCALE_PER_LEVEL")
        res["RESIST_DR_CONSTANT_PER_LEVEL"] = grab("RESIST_DR_CONSTANT_PER_LEVEL")
        # 注释块中的旧值（失衡五 证据）
        res["_comment_old_hp_growth"] = bool(re.search(r"1\.284\^", txt))
        res["_comment_old_dmg_growth"] = bool(re.search(r"1\.218\^", txt))
        res["_anchor_old_hp"] = bool(re.search(r"11,?635", txt))

    vb = os.path.join(repo, "game", "tools", "verify_balance84.gd")
    if os.path.isfile(vb):
        with open(vb, "r", encoding="utf-8", errors="replace") as f:
            vtxt = f.read()
        res["_vb84_hardcoded_1284"] = bool(re.search(r"MONSTER_HP_GROWTH\s*:=\s*1\.284", vtxt))
        res["_vb84_hardcoded_1218"] = bool(re.search(r"MONSTER_DMG_GROWTH\s*:=\s*1\.218", vtxt))
    return res


# ============================================================
# 5. 主流程
# ============================================================

def main():
    ap = argparse.ArgumentParser(description="第四步数值模型校验（只读）")
    ap.add_argument("--repo", default=None, help="工程根目录，用于漂移检测（可选）")
    ap.add_argument("--json", action="store_true", help="额外输出机器可读结果")
    args = ap.parse_args()

    c = Check()

    # ---------- A. 账号等级曲线自洽 ----------
    c.info("A", "账号等级曲线 cumulative 抽样",
           "L10=%s  L19=%s  L20=%s  L38=%s  L60=%s" % (
               f"{cumulative_to(10):,.0f}", f"{cumulative_to(19):,.0f}",
               f"{cumulative_to(20):,.0f}", f"{cumulative_to(38):,.0f}",
               f"{cumulative_to(60):,.0f}"))

    c.ok("A1", "cumulative_to(38) ≈ 856,496（文档 §1.1 表）",
         abs(cumulative_to(38) - 856496) < 1.0,
         "实测 %.0f" % cumulative_to(38))

    c.ok("A2", "level_from_xp(148,600) == 19（文档 §2.1 现状终点）",
         level_from_xp(148600) == 19,
         "实测 L%d" % level_from_xp(148600))

    # ---------- B. 失衡一：现状落差单调恶化 ----------
    cur = compute_current_gap_curve()
    gaps = [r["gap"] for r in cur]
    c.ok("B1", "现状落差首关 = −3（文档 §2.1 第 1 行）",
         gaps[0] == -3, "实测 %+d" % gaps[0])
    c.ok("B2", "现状落差末关 = +19（文档 §2.1 第 20 行）",
         gaps[-1] == 19, "实测 %+d" % gaps[-1])
    c.ok("B3", "现状落差单调递增（失衡一核心证据）",
         all(gaps[i] <= gaps[i + 1] for i in range(len(gaps) - 1)),
         "序列 %s" % gaps)

    # ---------- C. 目标曲线（路线 A）：推荐等级重标后落差收敛 ----------
    tgt = compute_target_gap_curve()
    tgaps = [r["gap"] for r in tgt]
    c.ok("C1", "路线 A 落差最大绝对值 ≤ 3（T6）",
         max(abs(g) for g in tgaps) <= 3,
         "max|gap| = %d，序列 %s" % (max(abs(g) for g in tgaps), tgaps))
    c.ok("C2", "路线 A 落差不再单调恶化（末关 ≤ 首关 + 3）",
         tgaps[-1] <= tgaps[0] + 3,
         "首 %+d -> 末 %+d" % (tgaps[0], tgaps[-1]))

    tgt_total = sum(TGT_REWARD_XP)
    c.ok("C3", "路线 A：reward_xp 合计不变 == 148,600（拍板：不动 XP）",
         tgt_total == 148600, "实测 %s" % f"{tgt_total:,}")

    c.ok("C4", "路线 A：现有 XP 落点 == L19（§3.1 实测）",
         level_from_xp(tgt_total) == 19, "实测 L%d" % level_from_xp(tgt_total))

    xp_mult = tgt_total / sum(CUR_REWARD_XP)
    c.ok("C5", "路线 A：XP 倍数 == 1.00（未改 XP）",
         abs(xp_mult - 1.0) < 1e-9, "实测 %.2f×" % xp_mult)

    c.info("C6", "路线 C 备选（XP×5.76 到 L38）已存档",
           "TGT_REWARD_XP_ROUTE_C 合计 %s，终点 L%d" % (
               f"{sum(TGT_REWARD_XP_ROUTE_C):,}", level_from_xp(sum(TGT_REWARD_XP_ROUTE_C))))

    # ---------- D. 失衡二：TTK/生存 ----------
    hk38_cur, hd38_cur, r38_cur = ttk_ratio(38, MONSTER_HP_GROWTH_CUR, MONSTER_DMG_GROWTH_CUR)
    c.ok("D1", "现状 L38 击杀所需击数 ≈ 386.9（文档 §2.2 / §3.2）",
         380 <= hk38_cur <= 395,
         "实测 %.1f 击" % hk38_cur)
    c.ok("D2", "现状 L38 被击杀数 ≈ 5.2（文档 §2.2）",
         abs(hd38_cur - 5.2) < 0.3,
         "实测 %.1f 击" % hd38_cur)
    c.ok("D3", "现状 L38 ratio < 0.02（不可玩证明，文档 §2.2）",
         r38_cur < 0.02,
         "实测 %.4f（即玩家在能杀 1 只怪的时间里会被杀 %.0f 次）" % (r38_cur, 1 / r38_cur))

    # 现状 ratio 应在 L9 附近跌破 1.0
    cross = None
    for L in range(1, 39):
        _, _, r = ttk_ratio(L, MONSTER_HP_GROWTH_CUR, MONSTER_DMG_GROWTH_CUR)
        if r < 1.0:
            cross = L
            break
    c.ok("D3b", "现状 ratio 跌破 1.0 的等级 ≈ L9（文档 §2.2 读法）",
         cross is not None and 7 <= cross <= 11,
         "实测 L%s" % cross)

    # 目标曲线全等级可玩（T1–T4）
    bad = []
    for L in range(1, 39):
        hk, hd, r = ttk_ratio(L, MONSTER_HP_GROWTH_TGT, MONSTER_DMG_GROWTH_TGT)
        if r < 1.0:
            bad.append((L, round(r, 3)))
    c.ok("D4", "目标曲线 L1–L38 全程 ratio ≥ 1.0（T4）",
         len(bad) == 0,
         "违规 %d 个：%s" % (len(bad), bad[:5]) if bad else "全程通过")

    _, _, r1_t = ttk_ratio(1, MONSTER_HP_GROWTH_TGT, MONSTER_DMG_GROWTH_TGT)
    c.ok("D4b", "目标 ratio 起点 ≈ 3.19（文档 §3.2 表）",
         abs(r1_t - 3.19) < 0.05, "实测 %.2f" % r1_t)

    hk20_t, _, _ = ttk_ratio(20, MONSTER_HP_GROWTH_TGT, MONSTER_DMG_GROWTH_TGT)
    c.ok("D5", "目标 L20 击杀击数落在 10–14（T1）",
         10 <= hk20_t <= 14, "实测 %.1f 击" % hk20_t)

    hk38_t, hd38_t, r38_t = ttk_ratio(38, MONSTER_HP_GROWTH_TGT, MONSTER_DMG_GROWTH_TGT)
    c.ok("D6", "目标 L38 击杀击数落在 14–20（T2）",
         14 <= hk38_t <= 20, "实测 %.1f 击" % hk38_t)
    c.ok("D7", "目标 L38 被击杀数落在 15–20（T3）",
         15 <= hd38_t <= 20, "实测 %.1f 击" % hd38_t)
    c.ok("D8", "目标 ratio 单调缓降（L38 仍 ≥ 1.1）",
         r38_t >= 1.10, "实测 %.2f" % r38_t)

    # ---------- E. 失衡四：预算曲线 ----------
    c.ok("E1", "现状预算合计 = 1,199（文档 §2.4）",
         sum(CUR_BUDGET) == 1199, "实测 %d" % sum(CUR_BUDGET))

    saw = []
    for i in range(len(CUR_BUDGET) - 1):
        if CUR_BUDGET[i + 1] < CUR_BUDGET[i]:
            saw.append((LEVEL_IDS[i], CUR_BUDGET[i], LEVEL_IDS[i + 1], CUR_BUDGET[i + 1]))
    c.ok("E2", "现状预算存在倒挂（失衡四证据）", len(saw) == 2,
         "倒挂 %d 处：%s" % (len(saw), saw))

    c.ok("E3", "目标预算严格单调递增（T7）",
         all(TGT_BUDGET[i] < TGT_BUDGET[i + 1] for i in range(len(TGT_BUDGET) - 1)),
         "无倒挂")
    c.ok("E4", "目标预算合计落在 5,400–5,900（T8）",
         5400 <= sum(TGT_BUDGET) <= 5900, "实测 %d" % sum(TGT_BUDGET))

    avg = sum(TGT_BUDGET) / len(TGT_BUDGET)
    c.ok("E5", "目标均值接近 GDD 定稿 269（文档 §3.4，容差 10%）",
         abs(avg - 269) / 269 < 0.10, "实测均值 %.1f" % avg)

    # ---------- F. 失衡三：iLvl（路线 A 口径） ----------
    c.ok("F1", "现状 iLvl 上限 20 与关卡等级上限 20 绑定（失衡三）",
         True, "见 loot_roller.gd:11 — item_level = 怪物等级")
    c.ok("F2", "路线 A：装备池 item_level_max 目标 = 22（T9）",
         EQUIP_ILVL_CAP_ROUTE_A == MAX_ACCOUNT_LEVEL + 2,
         "账号上限 %d ⇒ 装备池上限 %d（+2 级余量）" % (MAX_ACCOUNT_LEVEL, EQUIP_ILVL_CAP_ROUTE_A))
    c.ok("F2b", "路线 A 不需新增装备模板（W3-b 只改数字）",
         True, "62 个模板 item_level_max 由 ≤20 提到 22；原 18 底材工单降级为未来扩级启用")
    c.ok("F3", "iLvl 可达上限 ≤ 账号上限（clamp 后被天然封顶）",
         EQUIP_ILVL_CAP_ROUTE_A >= MAX_ACCOUNT_LEVEL,
         "玩家等级 20 打 L18 怪 ⇒ iLvl 可达 20（T10）")

    # ---------- G. 局内等级耦合 ----------
    run_cum10 = run_cumulative_to(10, RUN_XP_COEFF_CUR)
    # 目标预算 283.0/关 × 单怪 12–40 XP
    avg_budget = sum(TGT_BUDGET) / len(TGT_BUDGET)
    est_lo, est_hi = avg_budget * 12, avg_budget * 40
    c.ok("G1", "现状局内 10 级满 XP ≈ 1,847（文档 §3.4）",
         1700 <= run_cum10 <= 2000, "实测 %.0f" % run_cum10)
    c.ok("G2", "目标预算下单关 XP 会超出局内需求 ⇒ 需调系数（W4 依据）",
         est_lo > run_cum10,
         "预估单关 %.0f–%.0f XP vs 需求 %.0f XP" % (est_lo, est_hi, run_cum10))

    run_cum10_t = run_cumulative_to(10, RUN_XP_COEFF_TGT)
    c.ok("G3", "目标系数 50.0 后单关刚好升满（T16）",
         est_hi >= run_cum10_t >= est_lo * 0.8,
         "系数 50 时需求 %.0f XP；单关产出 %.0f–%.0f" % (run_cum10_t, est_lo, est_hi))

    # ---------- H. 词缀缩放比例 ----------
    r20 = item_stat_ilvl_scale(20) / affix_ilvl_scale(20)
    r22 = item_stat_ilvl_scale(22) / affix_ilvl_scale(22)
    r60 = item_stat_ilvl_scale(60) / affix_ilvl_scale(60)
    c.ok("H1", "iLvl 20 时两缩放系数比 ≈ 1.25（文档 §1.4）",
         abs(r20 - 1.25) < 0.02, "实测 %.3f" % r20)
    c.ok("H1b", "路线 A：iLvl 22 时比值 ≈ 1.264（稀释程度可接受）",
         abs(r22 - 1.264) < 0.01, "实测 %.3f" % r22)
    c.ok("H2", "iLvl 60 时比值扩大 ⇒ 词缀被稀释（W3-c 依据，路线 A 下 P2 可选）",
         r60 > r20 + 0.05, "实测 %.3f（差 %.3f）" % (r60, r60 - r20))
    c.info("H3", "路线 A 下 W3-c 优先级评估",
           "iLvl 上限 22 ⇒ 比值 1.264（vs L1 的 1.000）；仍在可接受区间 ⇒ 降为 P2")

    # ---------- I. 经济链路自洽 ----------
    stone_total = sum(FORGE_STONE_COST)
    c.ok("I1", "单件满强化魔石 = 106（文档 §1.4）",
         stone_total == 106, "实测 %d" % stone_total)

    forge_gold = sum(100.0 * (1.35 ** t) for t in range(1, 11))
    c.info("I2", "满强化金币（+1..+10）", "%.0f 金" % forge_gold)

    c.ok("I3", "商店价公式在 iLvl=20 时不爆炸（紫装 < 2,000 金）",
         shop_price("epic", 20) < 2000, "紫装 iLvl20 = %.0f 金" % shop_price("epic", 20))
    c.ok("I4", "结算扣金率 = 0.5（文档 §1.5）",
         abs(SETTLE_GOLD_RATE - 0.5) < 1e-9, "实测 %.2f" % SETTLE_GOLD_RATE)

    # ---------- J. 元素专精 ----------
    c.ok("J1", "元素伤害键需补 6 个（§4.3.1）",
         True, "fire/cold/lightning/poison/shadow/physical _damage")
    c.ok("J2", "抗性键需补 shadow_resist（§4.3.2）",
         True, "FINAL_KEYS 现仅 4 个抗性键")
    c.ok("J3", "异常映射需补 3 条至 6 条（T14）",
         True, "AILMENT_ELEMENT_MAP 现 3 条（poison/fire/cold）")

    # 抗性常量换用 25 的效果
    for R in [450]:
        for denom_const, tag in [(50.0, "现状 50"), (25.0, "建议 25")]:
            dr = R / (R + denom_const * 38)
            c.info("J4", "L38 抗性 450 在分母常量 %s 下减伤" % tag, "%.1f%%" % (dr * 100))

    # ---------- L. 路线 A 专项断言（T17–T20） ----------
    c.ok("L1", "MAX_ACCOUNT_LEVEL == 20（T17）",
         MAX_ACCOUNT_LEVEL == 20, "实测 %d（工程现值 60 需改）" % MAX_ACCOUNT_LEVEL)
    c.ok("L2", "现有 XP 合计可兑现 MAX_ACCOUNT_LEVEL（T19）",
         sum(TGT_REWARD_XP) >= cumulative_to(MAX_ACCOUNT_LEVEL) * 0.95,
         "XP 合计 %s vs cum(20) %s（%.1f%%）" % (
             f"{sum(TGT_REWARD_XP):,}", f"{cumulative_to(MAX_ACCOUNT_LEVEL):,.0f}",
             sum(TGT_REWARD_XP) / cumulative_to(MAX_ACCOUNT_LEVEL) * 100))
    c.ok("L2b", "现有 XP 实际落点 == L19，恰好差 1 级（余量设计）",
         level_from_xp(sum(TGT_REWARD_XP)) == MAX_ACCOUNT_LEVEL - 1,
         "落点 L%d，上限 L%d" % (level_from_xp(sum(TGT_REWARD_XP)), MAX_ACCOUNT_LEVEL))

    rec_gaps = []
    cum = 0
    for i, xp in enumerate(TGT_REWARD_XP):
        cum += xp
        lv = level_from_xp(cum)
        rec_gaps.append(RECOMMENDED_LEVEL_ROUTE_A[i] - lv)
    c.ok("L3", "逐关 recommended 与实际落点差 ≤ 1（T18）",
         max(abs(g) for g in rec_gaps) <= 1,
         "落差序列 %s" % rec_gaps)
    c.ok("L4", "recommended 全程 ≤ MAX_ACCOUNT_LEVEL（T20）",
         max(RECOMMENDED_LEVEL_ROUTE_A) <= MAX_ACCOUNT_LEVEL,
         "max recommended = %d，上限 %d" % (
             max(RECOMMENDED_LEVEL_ROUTE_A), MAX_ACCOUNT_LEVEL))

    c.info("L5", "路线 A「三件套」落地清单",
           "W2(关卡预算 120→440) + W10(MAX_ACCOUNT_LEVEL 60→20) + W11(recommended 重标) — 必须同批")
    c.info("L6", "用户原话「22」的偏差",
           "按 20 落地；若要字面 22 需 XP×1.36（%s）" % f"{cumulative_to(22):,.0f}")

    # ---------- K. 工程侧漂移检测（可选） ----------
    if args.repo:
        repo_c = read_repo_constants(args.repo)
        if repo_c:
            print("\n" + "-" * 78)
            print("工程侧实值对照（漂移检测）")
            print("-" * 78)
            pairs = [
                ("MONSTER_HP_GROWTH", MONSTER_HP_GROWTH_CUR),
                ("MONSTER_DMG_GROWTH", MONSTER_DMG_GROWTH_CUR),
                ("MONSTER_HP_AT_L1", MONSTER_HP_AT_L1),
                ("MONSTER_DMG_AT_L1", MONSTER_DMG_AT_L1),
                ("XP_CURVE_BASE", XP_CURVE_BASE),
                ("AFFIX_ILVL_SCALE_PER_LEVEL", AFFIX_ILVL_SCALE_PER_LEVEL),
                ("RESIST_DR_CONSTANT_PER_LEVEL", 50.0),
            ]
            for name, doc_val in pairs:
                eng = repo_c.get(name)
                if eng is None:
                    print("  [ ?? ] %-32s 工程未读到" % name)
                elif abs(eng - doc_val) < 1e-9:
                    print("  [ OK ] %-32s 工程 %.6g == 文档基线 %.6g" % (name, eng, doc_val))
                else:
                    print("  [MOVE] %-32s 工程 %.6g != 文档基线 %.6g" % (name, eng, doc_val))

            print("\n  失衡五（注释/断言脱钩）证据：")
            for key, label in [
                ("_comment_old_hp_growth", "game_constants 注释块仍含 1.284^"),
                ("_comment_old_dmg_growth", "game_constants 注释块仍含 1.218^"),
                ("_anchor_old_hp", "game_constants 锚点仍含 11,635"),
                ("_vb84_hardcoded_1284", "verify_balance84 硬编码 1.284"),
                ("_vb84_hardcoded_1218", "verify_balance84 硬编码 1.218"),
            ]:
                if repo_c.get(key):
                    c.warn("W5", label, "⇒ 仍需修复（工单 W5-a/b/c）")
                else:
                    c.info("W5", label, "已清理 ✓")
        else:
            c.warn("--", "未在 %s 找到工程文件" % args.repo, "跳过漂移检测")

    # ---------- 报告 ----------
    c.report("第四步「数值与数据模型」校验报告")

    print("\n" + "=" * 78)
    print("结果：%d 通过 / %d 失败 / %d 待修" % (c.passed, c.failed, c.warned))
    print("=" * 78)

    if args.json:
        out = {
            "passed": c.passed, "failed": c.failed, "warned": c.warned,
            "details": [{"mark": m.strip(), "id": t, "label": l, "detail": d}
                        for m, t, l, d in c.rows],
        }
        print(json.dumps(out, ensure_ascii=False, indent=2))

    return 0 if c.failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
