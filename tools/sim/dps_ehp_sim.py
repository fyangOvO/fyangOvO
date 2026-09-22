#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
「七傳說」期望 DPS / 有效生命值 双曲线仿真器
================================================

对应 GDD 阶段 0 第 6.6 节「期望 DPS / 有效生命值双曲线对齐校验」。
本脚本是阶段 1 的数值基础设施：任何 6.2 / 6.3 / 6.4 的系数改动，
都必须先跑本脚本确认 TTK / SurvT / 成长斜率比三项不越界。

核心公式（严格取自 GDD 6.6）
------------------------------------------------
    DPS_exp(L) = [AD_base(L) + AD_gear(L)] × (1 + CR × (CD - 1)) × AS × SkillMult
    EHP(L)     = HP_total(L) / (1 - DR(L))
    DR(L)      = ARM_total(L) / (ARM_total(L) + 50 × L)

校验项与目标区间（GDD 6.6 表）
------------------------------------------------
    TTK(L,tier)   = MonsterHP(L) × tierHP^n / DPS_exp(L)          目标 2.0 – 4.0 秒
    SurvT(L,tier) = EHP(L) / (MonsterDMG(L) × tierDMG^n × N)      目标 8 – 12 秒（N=4）
    成长斜率比    = (dDPS/dL)/(dMonsterHP/dL)                      目标 1.00 ± 0.15

关于「成长斜率比」的口径说明（重要）
------------------------------------------------
GDD 原式 (dDPS/dL)/(dMonsterHP/dL) 用的是**原始导数**，量纲不一致
（DPS 与 HP 单位不同），其数值随绝对刻度漂移（本模型下仅约 0.002），
不具备可比性，也无法用「1.00 ± 0.15」这种阈值判定。

因此本脚本同时输出两个口径：
  * slope_raw  = 原始导数比（GDD 字面口径，仅作记录）
  * slope_norm = 相对增长率之比 = (ΔDPS/DPS) / (ΔMHP/MHP)
                即对数斜率之比，量纲无关，**这才是「1.00 ± 0.15」真正
                想表达的「玩家成长速度 vs 怪物成长速度是否同步」**。
本脚本所有越界判定均以 slope_norm 为准。

用法示例
------------------------------------------------
  # 默认：跑 GDD 原方案（tier ×1.8^n）并输出三张表
  python dps_ehp_sim.py

  # 跑全部三个方案（原方案 / GDD 建议方案 / 仿真推荐方案）并对比
  python dps_ehp_sim.py --scenario all

  # 调参：把怪物 HP 成长从 1.28 改到 1.20，tier HP 从 1.8 改到 1.25
  python dps_ehp_sim.py --monster-hp-g 1.20 --tier-hp 1.25

  # 反解：由玩家曲线反推怪物系数与难度层级系数应该取多少
  python dps_ehp_sim.py --solve

  # 导出 CSV 到指定目录
  python dps_ehp_sim.py --scenario all --csv-dir out
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import sys
from dataclasses import dataclass, field, replace

# Windows 控制台中文输出
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

LMAX = 20                 # 关卡等级上限 L1–L20
TIER_NAMES = ["梦魇 I", "梦魇 II", "梦魇 III", "梦魇 IV", "梦魇 V"]
N_TIER = len(TIER_NAMES)


# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------

@dataclass
class Config:
    """全部可调系数。默认值 = GDD 6.2 / 6.3 / 6.4 的「暂定」原方案。"""

    # ---- 6.2 角色裸装基础属性： Base(L) = Base1 × (1+g)^(L-1) ----
    hp_base: float = 150.0
    hp_g: float = 0.11
    ad_base: float = 12.0
    ad_g: float = 0.10
    arm_base: float = 6.0
    arm_g: float = 0.10

    # ---- 6.2 装备贡献系数（满装相对裸装的加成倍数，L1 / L20 两个锚点） ----
    # 取值依据见 sim-report 报告「装备贡献系数取值依据」一节：
    #   L20 = 7.0  ← GDD 明写「满装 AD ≈ 裸装 × 6–8 倍」，取中高值以覆盖 +10 强化
    #   L1  = 0.5  ← L1 玩家约 3–4 件白装（无词缀），仅主属性贡献少量攻击力
    # 曲线默认 linear：GDD 3.3/6.2 的词缀与主属性均为 iLvl 线性缩放
    gear_ad_1: float = 0.5
    gear_ad_20: float = 7.0
    gear_hp_1: float = 0.5
    gear_hp_20: float = 7.0
    gear_arm_1: float = 0.5
    gear_arm_20: float = 7.0
    gear_curve: str = "expshift"        # expshift | linear | exp

    # ---- 6.6 DPS 公式的 CR / CD / AS / SkillMult ----
    # 注意：GDD 公式把这些符号写成常数，但它们实际由装备词缀驱动、
    # 随关卡成长。脚本按 L1→L20 线性插值（这是斜率比能否达标的关键）。
    cr_1: float = 0.05                  # 暴击率 L1
    cr_20: float = 0.40                 # 暴击率 L20
    cd_1: float = 1.50                  # 暴击伤害倍率 L1
    cd_20: float = 2.20                 # 暴击伤害倍率 L20
    as_1: float = 1.00                  # 攻击速度（次/秒）L1
    as_20: float = 1.60                 # 攻击速度 L20
    sm_1: float = 1.80                  # 技能倍率 L1
    sm_20: float = 2.80                 # 技能倍率 L20

    # ---- 6.3 怪物数值 ----
    monster_hp_base: float = 60.0
    monster_hp_g: float = 1.28
    monster_dmg_base: float = 8.0
    monster_dmg_g: float = 1.24
    elite_hp_mult: float = 4.5
    boss_hp_mult: float = 28.0

    # ---- 6.4 难度层级系数（梦魇 I = 指数 0） ----
    tier_hp: float = 1.80               # 原方案 ×1.8^n
    tier_dmg: float = 1.80

    # ---- 6.6 护甲减伤常数与同时受击数 ----
    armor_k: float = 50.0
    surv_n: int = 4

    # ---- 6.6 目标区间 ----
    ttk_min: float = 2.0
    ttk_max: float = 4.0
    survt_min: float = 8.0
    survt_max: float = 12.0
    slope_tol: float = 0.15

    # 分层目标窗口（可选）。为 None 时所有层级共用上面的单一窗口。
    # 用于「读法 B」：把 2–4s / 8–12s 定为梦魇 I–II 的目标，
    # III–V 定位为挑战内容，允许 TTK 递增 / SurvT 递减。
    ttk_tier_windows: tuple | None = None
    survt_tier_windows: tuple | None = None

    # ---- 单局时长模型（GDD 0.2 / 3.4：单局 10 分钟，普通关 150 杂兵 + 5 精英 + 1 BOSS）----
    # 注意：TTK 是**单体**口径，杂兵清怪实际受 AoE 影响，
    # 故引入 aoe_factor = 平均每单位 TTK 时间清掉的怪物数。
    mob_count: int = 150
    elite_count: int = 5
    boss_count: int = 1
    density_by_tier: tuple = (1.0, 0.9, 0.8, 0.7, 0.6)   # 层级越高怪物越少
    aoe_factor: float = 3.0        # 1.0 = 纯单体；3.0 = 一次挥砍平均命中 3 只
    elite_ttk_s: float = 12.0
    boss_ttk_s: float = 90.0
    overhead_frac: float = 0.30    # 跑图 / 拾取 / 结算占总时长比例
    run_budget_s: float = 600.0    # 单局时长预算（10 分钟）

    lmax: int = LMAX
    name: str = "GDD 原方案"


# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------

def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def gear_mult(level: int, m1: float, m20: float, curve: str, lmax: int = LMAX) -> float:
    """装备贡献系数：L1 锚点 m1 → L20 锚点 m20。

    三种曲线（`1+gm` 才是进入总属性的实际乘子）：

    * ``expshift``（默认，推荐）：对 ``1+gm`` 做指数插值，
      ``1+gm(L) = (1+m1) × ((1+m20)/(1+m1))^t``。
      此时 ``总属性 = Base(L) × (1+gm(L))`` 是**严格指数曲线**，
      对数斜率恒定 ⇒ TTK / SurvT 在 L1–L20 上保持水平，
      成长斜率比自然落在 1.00 附近。这是满足 GDD 6.6 斜率比目标的正确形态。

    * ``linear``：对 ``gm`` 做线性插值，对应 GDD 3.3/6.2 的字面「iLvl 线性缩放」。
      但 ``d ln(1+gm)/dL`` 会随 gm 增大而衰减（L1 ≈ 0.228 → L20 ≈ 0.043），
      导致玩家成长前快后慢，斜率比从 1.61 单调跌到 0.83 —— **不达标**。
      保留此选项用于对照，证明「字面线性缩放」是斜率比失衡的根因之一。

    * ``exp``：对 ``gm`` 做指数插值。斜率前慢后快（0.14 → 0.22），亦不平。
    """
    t = (level - 1) / (lmax - 1)
    if curve == "expshift":
        if m1 <= -1 or m20 <= -1:
            raise ValueError("expshift 要求 gear_*_1 / gear_*_20 > -1")
        return (1 + m1) * ((1 + m20) / (1 + m1)) ** t - 1
    if curve == "exp":
        if m1 <= 0:
            raise ValueError("exp 曲线要求 gear_*_1 > 0")
        return m1 * (m20 / m1) ** t
    return lerp(m1, m20, t)


def log_slope(xs: list[float]) -> float:
    """整段对数斜率 = ln(x_end/x_start) / (n-1)，即平均每级相对增长率。"""
    if len(xs) < 2 or xs[0] <= 0 or xs[-1] <= 0:
        return float("nan")
    return math.log(xs[-1] / xs[0]) / (len(xs) - 1)


# ---------------------------------------------------------------------------
# 角色侧曲线
# ---------------------------------------------------------------------------

def player_stats(level: int, c: Config) -> dict:
    """返回该关卡等级下的玩家期望面板与 DPS / EHP。"""
    hp_base = c.hp_base * (1 + c.hp_g) ** (level - 1)
    ad_base = c.ad_base * (1 + c.ad_g) ** (level - 1)
    arm_base = c.arm_base * (1 + c.arm_g) ** (level - 1)

    gm_ad = gear_mult(level, c.gear_ad_1, c.gear_ad_20, c.gear_curve, c.lmax)
    gm_hp = gear_mult(level, c.gear_hp_1, c.gear_hp_20, c.gear_curve, c.lmax)
    gm_arm = gear_mult(level, c.gear_arm_1, c.gear_arm_20, c.gear_curve, c.lmax)

    ad_total = ad_base * (1 + gm_ad)
    hp_total = hp_base * (1 + gm_hp)
    arm_total = arm_base * (1 + gm_arm)

    t = (level - 1) / (c.lmax - 1)
    cr = lerp(c.cr_1, c.cr_20, t)
    cd = lerp(c.cd_1, c.cd_20, t)
    aspd = lerp(c.as_1, c.as_20, t)
    sm = lerp(c.sm_1, c.sm_20, t)

    crit_mult = 1 + cr * (cd - 1)
    k = crit_mult * aspd * sm          # 综合输出乘子
    dps = ad_total * k

    dr = arm_total / (arm_total + c.armor_k * level)
    ehp = hp_total / (1 - dr)

    return {
        "level": level,
        "hp_base": hp_base, "ad_base": ad_base, "arm_base": arm_base,
        "gm_ad": gm_ad, "gm_hp": gm_hp, "gm_arm": gm_arm,
        "ad_total": ad_total, "hp_total": hp_total, "arm_total": arm_total,
        "cr": cr, "cd": cd, "as": aspd, "sm": sm,
        "crit_mult": crit_mult, "k": k,
        "dps": dps, "dr": dr, "ehp": ehp,
        "gear_share_ad": gm_ad / (1 + gm_ad),   # 装备占最终 AD 的比例
    }


def player_curves(c: Config) -> list[dict]:
    return [player_stats(L, c) for L in range(1, c.lmax + 1)]


# ---------------------------------------------------------------------------
# 怪物侧曲线
# ---------------------------------------------------------------------------

def monster_stats(level: int, c: Config) -> dict:
    hp = c.monster_hp_base * c.monster_hp_g ** (level - 1)
    dmg = c.monster_dmg_base * c.monster_dmg_g ** (level - 1)
    return {
        "level": level,
        "hp": hp, "dmg": dmg,
        "elite_hp": hp * c.elite_hp_mult,
        "boss_hp": hp * c.boss_hp_mult,
    }


def monster_curves(c: Config) -> list[dict]:
    return [monster_stats(L, c) for L in range(1, c.lmax + 1)]


def tier_hp_mult(tier_idx: int, c: Config) -> float:
    return c.tier_hp ** tier_idx


def tier_dmg_mult(tier_idx: int, c: Config) -> float:
    return c.tier_dmg ** tier_idx


# ---------------------------------------------------------------------------
# 三张校验表
# ---------------------------------------------------------------------------

def ttk_matrix(c: Config) -> list[list[float]]:
    """TTK[L-1][tier] = MonsterHP(L) × tierHP^n / DPS(L)，单位秒。"""
    players = player_curves(c)
    monsters = monster_curves(c)
    return [
        [monsters[i]["hp"] * tier_hp_mult(t, c) / players[i]["dps"] for t in range(N_TIER)]
        for i in range(c.lmax)
    ]


def survt_matrix(c: Config) -> list[list[float]]:
    """SurvT[L-1][tier] = EHP(L) / (MonsterDMG(L) × tierDMG^n × N)，单位秒。"""
    players = player_curves(c)
    monsters = monster_curves(c)
    return [
        [
            players[i]["ehp"] / (monsters[i]["dmg"] * tier_dmg_mult(t, c) * c.surv_n)
            for t in range(N_TIER)
        ]
        for i in range(c.lmax)
    ]


def slope_rows(c: Config) -> list[dict]:
    """逐关成长斜率。tier 系数是常数倍率，不改变斜率，故斜率与层级无关。"""
    players = player_curves(c)
    monsters = monster_curves(c)
    dps = [p["dps"] for p in players]
    mhp = [m["hp"] for m in monsters]

    rows = []
    for i in range(c.lmax):
        L = i + 1
        if 0 < i < c.lmax - 1:
            d_dps = (dps[i + 1] - dps[i - 1]) / 2.0
            d_mhp = (mhp[i + 1] - mhp[i - 1]) / 2.0
        elif i == 0:
            d_dps = dps[1] - dps[0]
            d_mhp = mhp[1] - mhp[0]
        else:
            d_dps = dps[i] - dps[i - 1]
            d_mhp = mhp[i] - mhp[i - 1]

        raw = d_dps / d_mhp if d_mhp else float("nan")
        norm = (d_dps / dps[i]) / (d_mhp / mhp[i]) if d_mhp else float("nan")
        rows.append({
            "level": L, "dps": dps[i], "mhp": mhp[i],
            "d_dps": d_dps, "d_mhp": d_mhp,
            "slope_raw": raw, "slope_norm": norm,
        })
    return rows


# ---------------------------------------------------------------------------
# 越界判定
# ---------------------------------------------------------------------------

def ttk_window(c: Config, tier: int) -> tuple[float, float]:
    if c.ttk_tier_windows:
        return c.ttk_tier_windows[tier]
    return (c.ttk_min, c.ttk_max)


def survt_window(c: Config, tier: int) -> tuple[float, float]:
    if c.survt_tier_windows:
        return c.survt_tier_windows[tier]
    return (c.survt_min, c.survt_max)


def ttk_ok(v: float, c: Config, tier: int = 0) -> bool:
    lo, hi = ttk_window(c, tier)
    return lo <= v <= hi


def survt_ok(v: float, c: Config, tier: int = 0) -> bool:
    lo, hi = survt_window(c, tier)
    return lo <= v <= hi


def slope_ok(v: float, c: Config) -> bool:
    return abs(v - 1.0) <= c.slope_tol


def collect_violations(c: Config) -> dict:
    """汇总越界单元格清单。"""
    ttk = ttk_matrix(c)
    sv = survt_matrix(c)
    sl = slope_rows(c)

    ttk_bad, survt_bad, slope_bad = [], [], []

    for i in range(c.lmax):
        L = i + 1
        for t in range(N_TIER):
            if not ttk_ok(ttk[i][t], c, t):
                ttk_bad.append((L, TIER_NAMES[t], ttk[i][t]))
            if not survt_ok(sv[i][t], c, t):
                survt_bad.append((L, TIER_NAMES[t], sv[i][t]))
        if not slope_ok(sl[i]["slope_norm"], c):
            slope_bad.append((L, sl[i]["slope_norm"]))

    return {
        "ttk_bad": ttk_bad, "survt_bad": survt_bad, "slope_bad": slope_bad,
        "ttk_total": c.lmax * N_TIER, "survt_total": c.lmax * N_TIER,
        "slope_total": c.lmax,
    }


def classify(v: float, lo: float, hi: float) -> str:
    if v < lo:
        return "偏低"
    if v > hi:
        return "偏高"
    return "达标"


def fmt_cell(v: float, ok: bool, width: int = 7, dec: int = 2) -> str:
    s = f"{v:.{dec}f}"
    return f"**{s}**" if not ok else s


# ---------------------------------------------------------------------------
# Markdown 渲染
# ---------------------------------------------------------------------------

def md_matrix(c: Config, matrix: list[list[float]], ok_fn, title: str,
              unit: str, window_fn, dec: int = 2) -> str:
    lines = []
    lines.append(f"### {title}")
    lines.append("")
    win_desc = "；".join(
        f"{TIER_NAMES[t]} {window_fn(c, t)[0]:g}–{window_fn(c, t)[1]:g}"
        for t in range(N_TIER)
    )
    lines.append(f"目标区间（{unit}）：{win_desc}；粗体 = 越界。")
    lines.append("")
    header = "| 关卡 | " + " | ".join(TIER_NAMES) + " |"
    sep = "|---|" + "---|" * N_TIER
    lines.append(header)
    lines.append(sep)
    for i in range(c.lmax):
        cells = [fmt_cell(matrix[i][t], ok_fn(matrix[i][t], c, t), dec=dec)
                 for t in range(N_TIER)]
        lines.append(f"| L{i+1} | " + " | ".join(cells) + " |")
    lines.append("")
    return "\n".join(lines)


def md_slope(c: Config, rows: list[dict]) -> str:
    lines = []
    lines.append("### 表 3 · 成长斜率比（逐关）")
    lines.append("")
    lines.append(f"目标 **1.00 ± {c.slope_tol:g}**，即 [1.00 - {c.slope_tol:g}, "
                 f"1.00 + {c.slope_tol:g}]。粗体 = 越界。")
    lines.append("")
    lines.append("> 口径：`slope_norm = (ΔDPS/DPS) / (ΔMonsterHP/MonsterHP)`（中心差分），"
                 "即相对增长率之比。")
    lines.append("> 难度层级为常数倍率，不改变斜率，故本表与层级无关。")
    lines.append("")
    lines.append("| 关卡 | DPS_exp | 普通怪 HP | dDPS/dL | dHP/dL | "
                 "slope_raw（GDD 字面口径） | **slope_norm（判定口径）** | 判定 |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for r in rows:
        ok = slope_ok(r["slope_norm"], c)
        s = f"{r['slope_norm']:.3f}"
        if not ok:
            s = f"**{s}**"
        verdict = "达标" if ok else classify(r["slope_norm"], 1 - c.slope_tol, 1 + c.slope_tol)
        lines.append(
            f"| L{r['level']} | {r['dps']:.1f} | {r['mhp']:.1f} | "
            f"{r['d_dps']:.2f} | {r['d_mhp']:.2f} | {r['slope_raw']:.4f} | {s} | {verdict} |"
        )
    lines.append("")
    return "\n".join(lines)


def md_violations(c: Config, vio: dict) -> str:
    lines = []
    lines.append("### 越界清单")
    lines.append("")

    tb = vio["ttk_bad"]
    sb = vio["survt_bad"]
    lb = vio["slope_bad"]

    lines.append(f"**TTK 越界：{len(tb)} / {vio['ttk_total']} 格**")
    lines.append("")
    if tb:
        under = [x for x in tb if x[2] < ttk_window(c, TIER_NAMES.index(x[1]))[0]]
        over = [x for x in tb if x[2] > ttk_window(c, TIER_NAMES.index(x[1]))[1]]
        if under:
            lines.append(f"- 偏低（怪物过脆，无击杀成就感）：{len(under)} 格")
            lines.append("  - " + "；".join(f"L{L}·{t} = {v:.2f}s" for L, t, v in under))
        if over:
            lines.append(f"- 偏高（手感粘滞，劝退）：{len(over)} 格")
            lines.append("  - " + "；".join(f"L{L}·{t} = {v:.2f}s" for L, t, v in over))
    else:
        lines.append("- 无")
    lines.append("")

    lines.append(f"**SurvT 越界：{len(sb)} / {vio['survt_total']} 格**")
    lines.append("")
    if sb:
        under = [x for x in sb if x[2] < survt_window(c, TIER_NAMES.index(x[1]))[0]]
        over = [x for x in sb if x[2] > survt_window(c, TIER_NAMES.index(x[1]))[1]]
        if under:
            lines.append(f"- 偏低（容易被秒）：{len(under)} 格")
            lines.append("  - " + "；".join(f"L{L}·{t} = {v:.2f}s" for L, t, v in under))
        if over:
            lines.append(f"- 偏高（毫无威胁）：{len(over)} 格")
            lines.append("  - " + "；".join(f"L{L}·{t} = {v:.2f}s" for L, t, v in over))
    else:
        lines.append("- 无")
    lines.append("")

    lines.append(f"**成长斜率比越界：{len(lb)} / {vio['slope_total']} 关**")
    lines.append("")
    if lb:
        lines.append("- " + "；".join(f"L{L} = {v:.3f}" for L, v in lb))
    else:
        lines.append("- 无")
    lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CSV 导出
# ---------------------------------------------------------------------------

def write_csv(path: str, header: list[str], rows: list[list]) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def export_csv(c: Config, out_dir: str, slug: str) -> list[str]:
    ttk = ttk_matrix(c)
    sv = survt_matrix(c)
    sl = slope_rows(c)
    players = player_curves(c)
    monsters = monster_curves(c)

    files = []

    p = os.path.join(out_dir, f"{slug}_ttk.csv")
    write_csv(p, ["关卡"] + TIER_NAMES,
              [[f"L{L}"] + [f"{ttk[L-1][t]:.3f}" for t in range(N_TIER)]
               for L in range(1, c.lmax + 1)])
    files.append(p)

    p = os.path.join(out_dir, f"{slug}_survt.csv")
    write_csv(p, ["关卡"] + TIER_NAMES,
              [[f"L{L}"] + [f"{sv[L-1][t]:.3f}" for t in range(N_TIER)]
               for L in range(1, c.lmax + 1)])
    files.append(p)

    p = os.path.join(out_dir, f"{slug}_slope.csv")
    write_csv(p, ["关卡", "DPS_exp", "MonsterHP", "dDPS_dL", "dHP_dL",
                  "slope_raw", "slope_norm"],
              [[f"L{r['level']}", f"{r['dps']:.2f}", f"{r['mhp']:.2f}",
                f"{r['d_dps']:.4f}", f"{r['d_mhp']:.4f}",
                f"{r['slope_raw']:.6f}", f"{r['slope_norm']:.4f}"] for r in sl])
    files.append(p)

    p = os.path.join(out_dir, f"{slug}_stats.csv")
    write_csv(
        p,
        ["关卡", "HP_base", "AD_base", "ARM_base",
         "AD_gear_mult", "HP_gear_mult", "ARM_gear_mult",
         "AD_total", "HP_total", "ARM_total",
         "CR", "CD", "AS", "SkillMult", "K",
         "DPS_exp", "DR", "EHP",
         "MonsterHP", "MonsterDMG", "精英HP", "BOSS_HP",
         "装备AD占比"],
        [[f"L{i+1}",
          f"{players[i]['hp_base']:.2f}", f"{players[i]['ad_base']:.2f}",
          f"{players[i]['arm_base']:.2f}",
          f"{players[i]['gm_ad']:.3f}", f"{players[i]['gm_hp']:.3f}",
          f"{players[i]['gm_arm']:.3f}",
          f"{players[i]['ad_total']:.2f}", f"{players[i]['hp_total']:.2f}",
          f"{players[i]['arm_total']:.2f}",
          f"{players[i]['cr']:.4f}", f"{players[i]['cd']:.4f}",
          f"{players[i]['as']:.4f}", f"{players[i]['sm']:.4f}",
          f"{players[i]['k']:.4f}",
          f"{players[i]['dps']:.2f}", f"{players[i]['dr']:.4f}",
          f"{players[i]['ehp']:.2f}",
          f"{monsters[i]['hp']:.2f}", f"{monsters[i]['dmg']:.2f}",
          f"{monsters[i]['elite_hp']:.2f}", f"{monsters[i]['boss_hp']:.2f}",
          f"{players[i]['gear_share_ad']:.4f}"]
         for i in range(c.lmax)])
    files.append(p)

    return files


# ---------------------------------------------------------------------------
# 单方案报告
# ---------------------------------------------------------------------------

def scenario_report(c: Config) -> str:
    players = player_curves(c)
    monsters = monster_curves(c)
    ttk = ttk_matrix(c)
    sv = survt_matrix(c)
    sl = slope_rows(c)
    vio = collect_violations(c)

    out = []
    out.append(f"## 方案：{c.name}")
    out.append("")
    out.append(f"- 难度层级：HP ×**{c.tier_hp:g}^n** / DMG ×**{c.tier_dmg:g}^n**")
    out.append(f"- 怪物：HP = {c.monster_hp_base:g} × **{c.monster_hp_g:g}^(L-1)**，"
               f"DMG = {c.monster_dmg_base:g} × **{c.monster_dmg_g:g}^(L-1)**")
    out.append(f"- 装备贡献系数（AD）：L1 ×{c.gear_ad_1:g} → L20 ×{c.gear_ad_20:g}"
               f"（{c.gear_curve}）")
    out.append("")
    out.append("**关键刻度**")
    out.append("")
    out.append("| 关卡 | AD_base | AD_total | 装备AD占比 | DPS_exp | 普通怪HP | 普通怪DMG | EHP | DR |")
    out.append("|---|---|---|---|---|---|---|---|---|")
    for i in [0, 4, 9, 14, 19]:
        p, m = players[i], monsters[i]
        out.append(
            f"| L{i+1} | {p['ad_base']:.1f} | {p['ad_total']:.1f} | "
            f"{p['gear_share_ad']*100:.1f}% | {p['dps']:.0f} | {m['hp']:.0f} | "
            f"{m['dmg']:.1f} | {p['ehp']:.0f} | {p['dr']*100:.1f}% |"
        )
    out.append("")

    # 汇总统计
    all_ttk = [ttk[i][t] for i in range(c.lmax) for t in range(N_TIER)]
    all_sv = [sv[i][t] for i in range(c.lmax) for t in range(N_TIER)]
    out.append("**全表统计**")
    out.append("")
    out.append(f"- TTK：min {min(all_ttk):.2f}s / 均值 {sum(all_ttk)/len(all_ttk):.2f}s / "
               f"max {max(all_ttk):.2f}s；越界 **{len(vio['ttk_bad'])}/{vio['ttk_total']}**")
    out.append(f"- SurvT：min {min(all_sv):.2f}s / 均值 {sum(all_sv)/len(all_sv):.2f}s / "
               f"max {max(all_sv):.2f}s；越界 **{len(vio['survt_bad'])}/{vio['survt_total']}**")
    norm = [r["slope_norm"] for r in sl]
    out.append(f"- 成长斜率比：min {min(norm):.3f} / 均值 {sum(norm)/len(norm):.3f} / "
               f"max {max(norm):.3f}；越界 **{len(vio['slope_bad'])}/{vio['slope_total']}**")
    out.append("")
    out.append(f"- 整段对数斜率：DPS **{log_slope([p['dps'] for p in players]):.4f}**/级 "
               f"vs 怪物HP **{log_slope([m['hp'] for m in monsters]):.4f}**/级 "
               f"→ 比值 **{log_slope([p['dps'] for p in players]) / log_slope([m['hp'] for m in monsters]):.3f}**")
    out.append("")

    out.append(md_matrix(c, ttk, ttk_ok, "表 1 · 击杀时间 TTK（秒）", "秒",
                         ttk_window, dec=2))
    out.append(md_matrix(c, sv, survt_ok, "表 2 · 存活时间 SurvT（秒）", "秒",
                         survt_window, dec=2))
    out.append(md_slope(c, sl))
    out.append(md_violations(c, vio))

    return "\n".join(out)


# ---------------------------------------------------------------------------
# 反解推荐系数
# ---------------------------------------------------------------------------

def geo_mean(xs: list[float]) -> float:
    if not xs:
        return float("nan")
    s = sum(math.log(x) for x in xs if x > 0)
    return math.exp(s / len(xs))


# ---------------------------------------------------------------------------
# 单局时长模型（回答「TTK 上限该卡在哪」）
# ---------------------------------------------------------------------------

def run_time_table(c: Config, level: int | None = None) -> list[dict]:
    """逐层级的单局时长估算（秒）。

    关键口径修正：GDD 6.6 的 TTK 是**单体**击杀时间。用「150 × TTK」直接估
    单局时长会高估 aoe_factor 倍 —— ARPG 的杂兵是成片清的，不是一只只砍。
    故本模型引入 `aoe_factor`：每单位 TTK 时间实际清掉的怪物数。

    单局总时长 = (杂兵 + 精英 + BOSS 战斗时长) / (1 - 跑图拾取开销占比)
    """
    L = level if level is not None else c.lmax
    ttk = ttk_matrix(c)
    idx = L - 1
    rows = []
    for t in range(N_TIER):
        d = c.density_by_tier[t] if c.density_by_tier else 1.0
        n_mob = c.mob_count * d
        mob_s = n_mob * ttk[idx][t] / c.aoe_factor
        elite_s = c.elite_count * c.elite_ttk_s
        boss_s = c.boss_count * c.boss_ttk_s
        combat_s = mob_s + elite_s + boss_s
        total_s = combat_s / (1 - c.overhead_frac)
        rows.append({
            "tier": t, "density": d, "n_mob": n_mob,
            "ttk": ttk[idx][t], "mob_s": mob_s, "elite_s": elite_s,
            "boss_s": boss_s, "combat_s": combat_s, "total_s": total_s,
            "total_min": total_s / 60.0,
            "over_budget": total_s > c.run_budget_s,
        })
    return rows


def ttk_cap_from_budget(c: Config, tier: int, aoe: float | None = None,
                        level: int | None = None) -> float:
    """反解：在单局时长预算下，某层级的 TTK 上限是多少秒。"""
    a = aoe if aoe is not None else c.aoe_factor
    d = c.density_by_tier[tier] if c.density_by_tier else 1.0
    n_mob = c.mob_count * d
    fixed = c.elite_count * c.elite_ttk_s + c.boss_count * c.boss_ttk_s
    mob_budget = c.run_budget_s * (1 - c.overhead_frac) - fixed
    if n_mob <= 0:
        return float("inf")
    return mob_budget * a / n_mob


def avg_ttk(c: Config, level: int | None = None, tier: int | None = None) -> float:
    """平均 TTK（秒）。tier=None 时取全层级算术平均。"""
    L = level if level is not None else c.lmax
    ttk = ttk_matrix(c)[L - 1]
    if tier is not None:
        return ttk[tier]
    return sum(ttk) / len(ttk)


def mob_count_for_duration(c: Config, target_min: float, aoe: float,
                           level: int | None = None,
                           tier: int | None = None,
                           elite_count: float | None = None,
                           boss_ttk_s: float | None = None,
                           overhead_frac: float | None = None) -> float:
    """反解：达到目标单局时长所需的杂兵数。

    由 `单局时长 = (杂兵数 × TTK / AoE + 固定战斗) / (1 - 开销占比)` 反解：

        杂兵数 = (目标秒数 × (1 - 开销) - 固定战斗) × AoE / TTK
    """
    oh = c.overhead_frac if overhead_frac is None else overhead_frac
    ne = c.elite_count if elite_count is None else elite_count
    nb = c.boss_ttk_s if boss_ttk_s is None else boss_ttk_s
    fixed = ne * c.elite_ttk_s + c.boss_count * nb
    ttk = avg_ttk(c, level=level, tier=tier)
    mob_budget = target_min * 60.0 * (1 - oh) - fixed
    if ttk <= 0:
        return float("inf")
    return mob_budget * aoe / ttk


# ---------------------------------------------------------------------------
# 内容产出模型（GDD 6.1 掉落表 / 6.5 经济 / 0.5 经验）
# ---------------------------------------------------------------------------

RARITY_NAMES = ("白", "蓝", "黄", "紫", "橙", "红", "绿", "彩")

# GDD 6.1 逐档概率（% → 小数）
DROP_MOB = (0.7802, 0.1755, 0.0350, 0.0045, 0.0005, 0.0002, 0.0040, 0.0001)
DROP_ELITE = (0.4030, 0.3400, 0.1600, 0.0500, 0.0100, 0.0060, 0.0300, 0.0010)
DROP_BOSS = (0.0600, 0.3000, 0.3500, 0.1500, 0.0500, 0.0180, 0.0700, 0.0020)

DROP_TRIGGER_MOB = 0.08        # 普通怪掉落触发概率
DROP_TRIGGER_ELITE = 0.60      # 精英掉落触发概率
BOSS_ITEM_COUNT = 3.0          # BOSS 掉 2–4 件，取均值 3

GOLD_MOB = 10.0                # 5–15 取均值
GOLD_ELITE = 60.0              # 40–80 取均值
GOLD_BOSS = 350.0              # 200–500 取均值

MAT_MOB = 0.08                 # 8% 掉 1
MAT_ELITE = 3.0                # 掉 2–4 取均值
MAT_BOSS = 10.0                # 掉 8–12 取均值

# 6.5：单件满强化（+10）所需魔石
MATS_PER_FULL_ENHANCE = 64.0
# 0.5：基准（150 杂兵）下的单关经验产出区间
XP_PER_RUN_BASE = (2500.0, 4000.0)
# 6.1 基准局：150 杂兵 + 5 精英 + 1 BOSS
BASELINE_MOB = 150.0


def content_yield(n_mob: float, n_elite: float = 5.0, n_boss: float = 1.0,
                  level: int = 20) -> dict:
    """按 GDD 6.1 / 6.5 / 0.5 计算单局产出（绝对量）。

    返回各稀有度期望件数、魔石、金币、经验。
    """
    items_mob = n_mob * DROP_TRIGGER_MOB
    items_elite = n_elite * DROP_TRIGGER_ELITE
    items_boss = n_boss * BOSS_ITEM_COUNT

    rarity = {}
    for i, name in enumerate(RARITY_NAMES):
        rarity[name] = (items_mob * DROP_MOB[i]
                        + items_elite * DROP_ELITE[i]
                        + items_boss * DROP_BOSS[i])

    gold_mult = 1 + 0.10 * level
    gold = (n_mob * GOLD_MOB + n_elite * GOLD_ELITE + n_boss * GOLD_BOSS) * gold_mult
    mats = n_mob * MAT_MOB + n_elite * MAT_ELITE + n_boss * MAT_BOSS

    # 经验按杂兵数线性缩放（GDD 0.5 的 2500–4000 是 150 杂兵基准）
    xp_lo, xp_hi = XP_PER_RUN_BASE
    scale = n_mob / BASELINE_MOB
    xp = (xp_lo * scale, xp_hi * scale)

    return {
        "n_mob": n_mob, "n_elite": n_elite, "n_boss": n_boss,
        "items_mob": items_mob, "items_elite": items_elite, "items_boss": items_boss,
        "items_total": items_mob + items_elite + items_boss,
        "rarity": rarity,
        "gold": gold, "mats": mats, "xp": xp,
        "runs_per_full_enhance": MATS_PER_FULL_ENHANCE / mats if mats > 0 else float("inf"),
    }


def baseline_yield() -> dict:
    """GDD 基准局产出（150 杂兵 + 5 精英 + 1 BOSS），作为不变量参照。"""
    return content_yield(BASELINE_MOB, 5.0, 1.0, level=20)


# ---------------------------------------------------------------------------
# 反解（product-reviewer 口径：tierHP 卡 TTK 上限，tierDMG 放开到 SurvT 窗口）
# ---------------------------------------------------------------------------

def solve_capped(base: Config, ttk_cap: float,
                 survt_lo: float | None = None,
                 survt_hi: float | None = None,
                 dmg_headroom: float = 0.985) -> dict:
    """按「tierHP 卡 TTK 上限 / tierDMG 吃满 SurvT 窗口」反解。

    * tierHP ：让梦魇 V 的最大 TTK 恰好等于 ttk_cap
    * DMG base：下调，使层级 I 的 SurvT 曲线整体上移到窗口顶部，
      把余量全留给 tierDMG（否则 tierDMG 无空间可涨）
    * tierDMG ：吃满 SurvT 窗口，即 `tierDMG^4 = minSurvT_I / survt_lo`
    """
    survt_lo = base.survt_min if survt_lo is None else survt_lo
    survt_hi = base.survt_max if survt_hi is None else survt_hi

    players = player_curves(base)
    dps = [p["dps"] for p in players]
    ehp = [p["ehp"] for p in players]
    n = base.lmax

    # --- 玩家曲线 ---
    hp_mult = math.exp(log_slope(dps))
    dmg_mult = math.exp(log_slope(ehp))

    # --- 怪物 HP base：维持 TTK(层级I) 几何均值 = 区间中点 ---
    ttk_unit = [hp_mult ** (L - 1) / dps[L - 1] for L in range(1, n + 1)]
    hp_base = ((base.ttk_min + base.ttk_max) / 2.0) / geo_mean(ttk_unit)
    ttk_t1 = [hp_base * hp_mult ** (L - 1) / dps[L - 1] for L in range(1, n + 1)]

    # --- tierHP：梦魇 V 的最大 TTK 压在 ttk_cap 上 ---
    exp_n = N_TIER - 1
    tier_hp = (ttk_cap / max(ttk_t1)) ** (1.0 / exp_n)

    # --- 怪物 DMG base：把层级 I 的 SurvT 曲线顶到窗口上沿 ---
    # 先按 dmg_base = 1 求曲线形状，再整体缩放
    survt_unit = [ehp[L - 1] / (dmg_mult ** (L - 1) * base.surv_n)
                  for L in range(1, n + 1)]
    # 希望 max(survt_t1) = survt_hi × dmg_headroom（留一点取整余量）
    target_max = survt_hi * dmg_headroom
    dmg_base = max(survt_unit) / target_max
    survt_t1 = [ehp[L - 1] / (dmg_base * dmg_mult ** (L - 1) * base.surv_n)
                for L in range(1, n + 1)]

    # --- tierDMG：吃满 SurvT 窗口（梦魇 V 的最小 SurvT 压在 survt_lo 上）---
    tier_dmg = (min(survt_t1) / survt_lo) ** (1.0 / exp_n)

    return {
        "hp_mult": hp_mult, "dmg_mult": dmg_mult,
        "monster_hp_base": hp_base, "tier_hp": tier_hp,
        "monster_dmg_base": dmg_base, "tier_dmg": tier_dmg,
        "ttk_t1": ttk_t1, "survt_t1": survt_t1,
        "ttk_cap": ttk_cap,
    }


def build_capped(base: Config, name: str = "仿真推荐方案 C（TTK≤5s 硬约束 · HP 主导）",
                 ttk_cap: float = 5.0, **kw) -> tuple[Config, dict]:
    """方案 C：product-reviewer 口径的字面实现 —— TTK 上限抬到 5s（保单局时长），
    SurvT 仍守全局 [8,12] 窗口。"""
    sol = solve_capped(base, ttk_cap, **kw)
    cfg = replace(
        base, name=name,
        ttk_max=ttk_cap,                      # 硬约束写进目标窗口
        monster_hp_base=floor_to(sol["monster_hp_base"], 1),
        monster_hp_g=floor_to(sol["hp_mult"], 3),
        monster_dmg_base=floor_to(sol["monster_dmg_base"], 2),
        monster_dmg_g=floor_to(sol["dmg_mult"], 3),
        tier_hp=floor_to(sol["tier_hp"], 2),
        tier_dmg=floor_to(sol["tier_dmg"], 2),
    )
    return cfg, sol


def floor_to(x: float, digits: int) -> float:
    """向下取整到指定小数位。

    反解出的系数要落盘成「设计文档里能写下的数字」，四舍五入可能把结果
    推回越界（例如 tier_dmg 1.0478 → 1.05 会让梦魇 V 的 SurvT 掉到 7.93s）。
    统一向下取整 = 始终朝安全侧取整，保证取整后不新增越界。
    """
    f = 10.0 ** digits
    return math.floor(x * f) / f


def solve_recommended(c: Config, target_ttk: float, target_survt: float) -> dict:
    """由玩家曲线反推怪物系数与难度层级系数。

    原理：要让 TTK / SurvT 在 L1–L20 上保持恒定（即斜率比 = 1.00），
    怪物曲线的对数斜率必须等于玩家曲线的对数斜率：
        g_monster = exp(dln(player)/dL) - 1
    再由「全 20 关的几何平均」反解 base —— 用几何平均而非端点，
    可让整条曲线居中落在目标区间内（端点标定会让另一侧越界）。

    难度层级系数则由「层级 I 时 L1–L20 的实际极值」反解，
    保证梦魇 V 恰好压在上/下界上，不产生新的越界。
    """
    players = player_curves(c)
    dps = [p["dps"] for p in players]
    ehp = [p["ehp"] for p in players]
    n = c.lmax

    dps_ls = log_slope(dps)
    ehp_ls = log_slope(ehp)

    # 成长倍率（Config 中 monster_*_g 存的是倍率，不是增量）
    hp_mult = math.exp(dps_ls)
    dmg_mult = math.exp(ehp_ls)

    # 单位 base 下的 TTK / SurvT 序列（对 base 线性齐次）
    ttk_unit = [hp_mult ** (L - 1) / dps[L - 1] for L in range(1, n + 1)]
    survt_unit = [ehp[L - 1] / (dmg_mult ** (L - 1) * c.surv_n) for L in range(1, n + 1)]

    # TTK 与 hp_base 成正比；SurvT 与 dmg_base 成反比 —— 反解方向不同
    hp_base = target_ttk / geo_mean(ttk_unit)
    dmg_base = geo_mean(survt_unit) / target_survt

    # 层级 I 的实际曲线
    ttk_t1 = [hp_base * hp_mult ** (L - 1) / dps[L - 1] for L in range(1, n + 1)]
    survt_t1 = [ehp[L - 1] / (dmg_base * dmg_mult ** (L - 1) * c.surv_n)
                for L in range(1, n + 1)]

    exp_n = N_TIER - 1
    # 梦魇 V 的 TTK 上界压在 ttk_max：按最坏关卡（TTK 最大者）反解
    tier_hp = (c.ttk_max / max(ttk_t1)) ** (1.0 / exp_n)
    # 梦魇 V 的 SurvT 下界压在 survt_min：按最坏关卡（SurvT 最小者）反解
    tier_dmg = (min(survt_t1) / c.survt_min) ** (1.0 / exp_n)

    return {
        "dps_log_slope": dps_ls, "ehp_log_slope": ehp_ls,
        "monster_hp_g": hp_mult, "monster_hp_base": hp_base,
        "monster_dmg_g": dmg_mult, "monster_dmg_base": dmg_base,
        "ttk_t1": ttk_t1, "survt_t1": survt_t1,
        "ttk_l20_t1": ttk_t1[-1], "survt_l20_t1": survt_t1[-1],
        "tier_hp": tier_hp, "tier_dmg": tier_dmg,
        "target_ttk": target_ttk, "target_survt": target_survt,
    }


# ---------------------------------------------------------------------------
# 方案预设
# ---------------------------------------------------------------------------

def make_scenarios(base: Config) -> dict:
    sc = {}

    sc["gdd-original"] = replace(
        base, name="GDD 原方案（难度层级 ×1.8^n）",
        tier_hp=1.80, tier_dmg=1.80,
    )

    sc["gdd-proposed"] = replace(
        base, name="GDD 6.4 建议方案（HP ×1.6^n / DMG ×1.45^n）",
        tier_hp=1.60, tier_dmg=1.45,
    )

    # 仿真推荐：由 --solve 的实际结果填入（见 run_all 动态构建）
    sc["sim-recommended"] = replace(
        base, name="仿真推荐方案（待反解）",
        tier_hp=1.25, tier_dmg=1.20,
    )

    return sc


def build_recommended(base: Config) -> tuple[Config, dict]:
    """用 --solve 的结果构造「仿真推荐方案」（读法 A：全 100 格共用同一窗口）。"""
    sol = solve_recommended(base, target_ttk=(base.ttk_min + base.ttk_max) / 2.0,
                            target_survt=(base.survt_min + base.survt_max) / 2.0)
    rec = replace(
        base,
        name="仿真推荐方案 A（全格统一窗口）",
        monster_hp_base=floor_to(sol["monster_hp_base"], 1),
        monster_hp_g=floor_to(sol["monster_hp_g"], 3),
        monster_dmg_base=floor_to(sol["monster_dmg_base"], 2),
        monster_dmg_g=floor_to(sol["monster_dmg_g"], 3),
        tier_hp=floor_to(sol["tier_hp"], 2),
        tier_dmg=floor_to(sol["tier_dmg"], 2),
    )
    return rec, sol


# 读法 B：把 2–4s / 8–12s 定为梦魇 I–II 的目标，III–V 定位为挑战内容。
# 每层 TTK 目标递增、SurvT 目标递减，形成真正的「难度阶梯」。
LADDER_TTK_WINDOWS = (
    (2.5, 3.5),      # 梦魇 I   —— 舒适区
    (3.0, 4.5),      # 梦魇 II  —— 略紧
    (3.5, 5.5),      # 梦魇 III —— 挑战
    (4.0, 7.0),      # 梦魇 IV  —— 高压
    (5.0, 9.0),      # 梦魇 V   —— 极限
)
LADDER_SURVT_WINDOWS = (
    (9.0, 12.0),
    (7.5, 11.0),
    (6.0, 10.0),
    (5.0, 9.0),
    (4.0, 8.0),
)

# 方案 D：让 DMG 成为难度主导轴，必须给 SurvT 也配阶梯窗口。
# 理由：全局 [8,12] 窗口只有 1.5 倍跨度 ⇒ tierDMG ≤ 1.5^(1/4) = 1.107，
# 而 TTK 窗口放到 [2,5] 有 2.5 倍跨度 ⇒ tierHP 可达 1.257。
# 即「全局 SurvT 窗口」下 HP 必然是主导轴，想让 DMG 主导就必须放开 SurvT 下沿。
# 窗口按 tier_dmg ≈ 1.23 的逐层递减设计（每层带宽 ±20%）。
LADDER_SURVT_DMG_WINDOWS = (
    (10.0, 13.0),
    (8.0, 11.0),
    (6.3, 9.0),
    (5.0, 7.5),
    (4.0, 6.2),
)


def build_dmg_dominant(base: Config,
                       name: str = "仿真推荐方案 D（DMG 主导 · SurvT 阶梯）",
                       ttk_cap: float = 5.0) -> tuple[Config, dict]:
    """方案 D：难度主要由「致命性」体现，HP 轴主动放缓。

    与方案 C 的唯一差别是 **SurvT 改为阶梯窗口** —— 这是让 DMG 成为主导轴的前提，
    因为全局 [8,12] 窗口只允许 tierDMG ≤ 1.107，而 TTK 窗口放到 [2,5] 后
    tierHP 可达 1.257。不放开 SurvT 下沿，「难度放 DMG」在数学上无法成立。
    """
    sol = solve_capped(base, ttk_cap, survt_lo=4.5, survt_hi=12.0)
    cfg = replace(
        base, name=name,
        ttk_max=ttk_cap,
        monster_hp_base=floor_to(sol["monster_hp_base"], 1),
        monster_hp_g=floor_to(sol["hp_mult"], 3),
        monster_dmg_base=floor_to(sol["monster_dmg_base"], 2),
        monster_dmg_g=floor_to(sol["dmg_mult"], 3),
        tier_hp=1.08,                     # HP 轴主动放缓，把难度让给 DMG
        tier_dmg=floor_to(sol["tier_dmg"], 2),
        survt_tier_windows=LADDER_SURVT_DMG_WINDOWS,
    )
    return cfg, sol


def build_tier_ladder(base: Config) -> Config:
    """读法 B：保留难度层级的威胁梯度，但为每层单独设定目标窗口。"""
    sol = solve_recommended(base, target_ttk=3.0, target_survt=10.0)
    # 让梦魇 V 的 TTK 落在阶梯上沿 9.0s、SurvT 落在下沿 4.0s 反解层级系数
    exp_n = N_TIER - 1
    ttk_v_target = LADDER_TTK_WINDOWS[-1][1]      # 9.0
    survt_v_target = LADDER_SURVT_WINDOWS[-1][0]  # 4.0
    tier_hp = (ttk_v_target / max(sol["ttk_t1"])) ** (1.0 / exp_n)
    tier_dmg = (min(sol["survt_t1"]) / survt_v_target) ** (1.0 / exp_n)

    return replace(
        base,
        name="仿真推荐方案 B（分层目标窗口 · 难度阶梯）",
        monster_hp_base=floor_to(sol["monster_hp_base"], 1),
        monster_hp_g=floor_to(sol["monster_hp_g"], 3),
        monster_dmg_base=floor_to(sol["monster_dmg_base"], 2),
        monster_dmg_g=floor_to(sol["monster_dmg_g"], 3),
        tier_hp=floor_to(tier_hp, 2),
        tier_dmg=floor_to(tier_dmg, 2),
        ttk_tier_windows=LADDER_TTK_WINDOWS,
        survt_tier_windows=LADDER_SURVT_WINDOWS,
    )


# ---------------------------------------------------------------------------
# 对比汇总
# ---------------------------------------------------------------------------

def comparison_table(scenarios: list[Config]) -> str:
    out = []
    out.append("## 方案横向对比")
    out.append("")
    out.append("| 方案 | tier HP^n | tier DMG^n | 怪物HP base | 怪物HP g | "
               "怪物DMG base | 怪物DMG g | TTK 越界 | SurvT 越界 | 斜率越界 | "
               "L20·梦魇I TTK | L20·梦魇V TTK |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for c in scenarios:
        vio = collect_violations(c)
        ttk = ttk_matrix(c)
        out.append(
            f"| {c.name} | {c.tier_hp:g} | {c.tier_dmg:g} | "
            f"{c.monster_hp_base:g} | {c.monster_hp_g:g} | "
            f"{c.monster_dmg_base:g} | {c.monster_dmg_g:g} | "
            f"{len(vio['ttk_bad'])}/{vio['ttk_total']} | "
            f"{len(vio['survt_bad'])}/{vio['survt_total']} | "
            f"{len(vio['slope_bad'])}/{vio['slope_total']} | "
            f"{ttk[19][0]:.2f}s | {ttk[19][4]:.2f}s |"
        )
    out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def parse_args(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="七傳說 · 期望 DPS / EHP 双曲线仿真器（GDD 6.6）",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--scenario", default="gdd-original",
                   choices=["gdd-original", "gdd-proposed", "sim-recommended",
                            "tier-ladder", "capped", "dmg-dominant", "all"],
                   help="要运行的方案")
    p.add_argument("--solve", action="store_true",
                   help="反解推荐的怪物系数与难度层级系数")
    p.add_argument("--csv-dir", default="out", help="CSV 输出目录")

    g = p.add_argument_group("角色裸装基础属性")
    g.add_argument("--hp-base", type=float, default=150.0)
    g.add_argument("--hp-g", type=float, default=0.11)
    g.add_argument("--ad-base", type=float, default=12.0)
    g.add_argument("--ad-g", type=float, default=0.10)
    g.add_argument("--arm-base", type=float, default=6.0)
    g.add_argument("--arm-g", type=float, default=0.10)

    g = p.add_argument_group("装备贡献系数")
    g.add_argument("--gear-ad-1", type=float, default=0.5)
    g.add_argument("--gear-ad-20", type=float, default=7.0)
    g.add_argument("--gear-hp-1", type=float, default=0.5)
    g.add_argument("--gear-hp-20", type=float, default=7.0)
    g.add_argument("--gear-arm-1", type=float, default=0.5)
    g.add_argument("--gear-arm-20", type=float, default=7.0)
    g.add_argument("--gear-curve", default="expshift",
                   choices=["expshift", "linear", "exp"])

    g = p.add_argument_group("DPS 公式乘子（L1 → L20 线性插值）")
    g.add_argument("--cr-1", type=float, default=0.05)
    g.add_argument("--cr-20", type=float, default=0.40)
    g.add_argument("--cd-1", type=float, default=1.50)
    g.add_argument("--cd-20", type=float, default=2.20)
    g.add_argument("--as-1", type=float, default=1.00)
    g.add_argument("--as-20", type=float, default=1.60)
    g.add_argument("--sm-1", type=float, default=1.80)
    g.add_argument("--sm-20", type=float, default=2.80)

    g = p.add_argument_group("怪物系数")
    g.add_argument("--monster-hp-base", type=float, default=60.0)
    g.add_argument("--monster-hp-g", type=float, default=1.28)
    g.add_argument("--monster-dmg-base", type=float, default=8.0)
    g.add_argument("--monster-dmg-g", type=float, default=1.24)
    g.add_argument("--elite-hp-mult", type=float, default=4.5)
    g.add_argument("--boss-hp-mult", type=float, default=28.0)

    g = p.add_argument_group("难度层级系数")
    g.add_argument("--tier-hp", type=float, default=1.80)
    g.add_argument("--tier-dmg", type=float, default=1.80)

    g = p.add_argument_group("护甲与生存")
    g.add_argument("--armor-k", type=float, default=50.0)
    g.add_argument("--surv-n", type=int, default=4)

    g = p.add_argument_group("目标区间")
    g.add_argument("--ttk-min", type=float, default=2.0)
    g.add_argument("--ttk-max", type=float, default=4.0)
    g.add_argument("--survt-min", type=float, default=8.0)
    g.add_argument("--survt-max", type=float, default=12.0)
    g.add_argument("--slope-tol", type=float, default=0.15)

    g = p.add_argument_group("单局时长模型")
    g.add_argument("--mob-count", type=int, default=150, help="普通关杂兵数")
    g.add_argument("--elite-count", type=int, default=5)
    g.add_argument("--boss-count", type=int, default=1)
    g.add_argument("--density", default="1.0,0.9,0.8,0.7,0.6",
                   help="各层级怪物密度系数，逗号分隔 5 个值")
    g.add_argument("--aoe-factor", type=float, default=3.0,
                   help="每单位 TTK 时间清掉的怪物数（1.0=纯单体）")
    g.add_argument("--elite-ttk", type=float, default=12.0)
    g.add_argument("--boss-ttk", type=float, default=90.0)
    g.add_argument("--overhead-frac", type=float, default=0.30)
    g.add_argument("--run-budget", type=float, default=600.0, help="单局时长预算（秒）")
    g.add_argument("--ttk-cap", type=float, default=5.0,
                   help="梦魇 V 的 TTK 硬上限（用于 capped / dmg-dominant 方案）")

    return p.parse_args(argv)


def config_from_args(a: argparse.Namespace) -> Config:
    return Config(
        hp_base=a.hp_base, hp_g=a.hp_g,
        ad_base=a.ad_base, ad_g=a.ad_g,
        arm_base=a.arm_base, arm_g=a.arm_g,
        gear_ad_1=a.gear_ad_1, gear_ad_20=a.gear_ad_20,
        gear_hp_1=a.gear_hp_1, gear_hp_20=a.gear_hp_20,
        gear_arm_1=a.gear_arm_1, gear_arm_20=a.gear_arm_20,
        gear_curve=a.gear_curve,
        cr_1=a.cr_1, cr_20=a.cr_20, cd_1=a.cd_1, cd_20=a.cd_20,
        as_1=a.as_1, as_20=a.as_20, sm_1=a.sm_1, sm_20=a.sm_20,
        monster_hp_base=a.monster_hp_base, monster_hp_g=a.monster_hp_g,
        monster_dmg_base=a.monster_dmg_base, monster_dmg_g=a.monster_dmg_g,
        elite_hp_mult=a.elite_hp_mult, boss_hp_mult=a.boss_hp_mult,
        tier_hp=a.tier_hp, tier_dmg=a.tier_dmg,
        armor_k=a.armor_k, surv_n=a.surv_n,
        ttk_min=a.ttk_min, ttk_max=a.ttk_max,
        survt_min=a.survt_min, survt_max=a.survt_max,
        slope_tol=a.slope_tol,
        mob_count=a.mob_count, elite_count=a.elite_count, boss_count=a.boss_count,
        density_by_tier=tuple(float(x) for x in a.density.split(",")),
        aoe_factor=a.aoe_factor, elite_ttk_s=a.elite_ttk,
        boss_ttk_s=a.boss_ttk, overhead_frac=a.overhead_frac,
        run_budget_s=a.run_budget,
    )


def print_console_summary(c: Config) -> None:
    vio = collect_violations(c)
    ttk = ttk_matrix(c)
    rt = run_time_table(c)
    print(f"[{c.name}]")
    print(f"  tier HP ×{c.tier_hp:g}^n / DMG ×{c.tier_dmg:g}^n ｜ "
          f"MonsterHP {c.monster_hp_base:g}×{c.monster_hp_g:g}^(L-1) ｜ "
          f"MonsterDMG {c.monster_dmg_base:g}×{c.monster_dmg_g:g}^(L-1)")
    print(f"  TTK    越界 {len(vio['ttk_bad']):2d}/{vio['ttk_total']}")
    print(f"  SurvT  越界 {len(vio['survt_bad']):2d}/{vio['survt_total']}")
    print(f"  斜率比 越界 {len(vio['slope_bad']):2d}/{vio['slope_total']}")
    print(f"  L20 各层级 TTK: " + " ".join(f"{ttk[19][t]:.2f}s" for t in range(N_TIER)))
    print(f"  L20 单局时长(AoE×{c.aoe_factor:g}): "
          + " ".join(f"{r['total_min']:.1f}m" for r in rt)
          + f"   [预算 {c.run_budget_s/60:.0f}m]")
    print()


def main(argv=None) -> int:
    args = parse_args(argv)
    base = config_from_args(args)

    print("=" * 78)
    print("七傳說 · 期望 DPS / EHP 双曲线仿真器（GDD 6.6）")
    print("=" * 78)
    print()

    # ---- 反解 ----
    if args.solve:
        sol = solve_recommended(base, target_ttk=(base.ttk_min + base.ttk_max) / 2.0,
                                target_survt=(base.survt_min + base.survt_max) / 2.0)
        print("【反解结果】由玩家成长曲线反推怪物系数与难度层级系数")
        print(f"  玩家 DPS 对数斜率 = {sol['dps_log_slope']:.5f} /级 "
              f"→ 等价成长倍率 {sol['monster_hp_g']:.4f}^L")
        print(f"  玩家 EHP 对数斜率 = {sol['ehp_log_slope']:.5f} /级 "
              f"→ 等价成长倍率 {sol['monster_dmg_g']:.4f}^L")
        print(f"  ⇒ 怪物 HP 成长应为 {sol['monster_hp_g']:.4f}^(L-1) "
              f"(当前 {base.monster_hp_g:g})")
        print(f"  ⇒ 怪物 DMG 成长应为 {sol['monster_dmg_g']:.4f}^(L-1) "
              f"(当前 {base.monster_dmg_g:g})")
        print(f"  ⇒ 怪物 HP base 应为 {sol['monster_hp_base']:.1f} "
              f"(当前 {base.monster_hp_base:g})")
        print(f"  ⇒ 怪物 DMG base 应为 {sol['monster_dmg_base']:.2f} "
              f"(当前 {base.monster_dmg_base:g})")
        print(f"  ⇒ 难度层级 HP 系数应为 {sol['tier_hp']:.4f}^n "
              f"(GDD 原 1.8 / 建议 1.6)")
        print(f"  ⇒ 难度层级 DMG 系数应为 {sol['tier_dmg']:.4f}^n "
              f"(GDD 原 1.8 / 建议 1.45)")
        print()

    # ---- 选方案 ----
    if args.scenario == "all":
        rec, sol = build_recommended(base)
        cfg_c, _ = build_capped(base, ttk_cap=args.ttk_cap)
        cfg_d, _ = build_dmg_dominant(base, ttk_cap=args.ttk_cap)
        sc_list = [
            replace(base, name="GDD 原方案（难度层级 ×1.8^n）", tier_hp=1.80, tier_dmg=1.80),
            replace(base, name="GDD 6.4 建议方案（HP ×1.6^n / DMG ×1.45^n）",
                    tier_hp=1.60, tier_dmg=1.45),
            rec,
            build_tier_ladder(base),
            cfg_c,
            cfg_d,
        ]
    else:
        if args.scenario == "sim-recommended":
            c, _ = build_recommended(base)
        elif args.scenario == "tier-ladder":
            c = build_tier_ladder(base)
        elif args.scenario == "capped":
            c, _ = build_capped(base, ttk_cap=args.ttk_cap)
        elif args.scenario == "dmg-dominant":
            c, _ = build_dmg_dominant(base, ttk_cap=args.ttk_cap)
        else:
            c = make_scenarios(base)[args.scenario]
        sc_list = [c]

    # ---- 控制台摘要 ----
    for c in sc_list:
        print_console_summary(c)

    # ---- CSV ----
    if args.csv_dir:
        slugs = {"GDD 原方案（难度层级 ×1.8^n）": "gdd_original",
                 "GDD 6.4 建议方案（HP ×1.6^n / DMG ×1.45^n）": "gdd_proposed",
                 "仿真推荐方案 A（全格统一窗口）": "sim_recommended_a",
                 "仿真推荐方案 B（分层目标窗口 · 难度阶梯）": "sim_recommended_b",
                 "仿真推荐方案 C（TTK≤5s 硬约束 · HP 主导）": "sim_recommended_c",
                 "仿真推荐方案 D（DMG 主导 · SurvT 阶梯）": "sim_recommended_d"}
        all_files = []
        for c in sc_list:
            slug = slugs.get(c.name, "custom")
            all_files += export_csv(c, args.csv_dir, slug)
        print(f"CSV 已导出 {len(all_files)} 个文件到 {os.path.abspath(args.csv_dir)}")
        for f in all_files:
            print(f"  {f}")
        print()

    # ---- Markdown 报告到 stdout ----
    print("<!-- ===== MARKDOWN REPORT BEGIN ===== -->")
    print()
    print(comparison_table(sc_list))
    for c in sc_list:
        print(scenario_report(c))
        print("---")
        print()
    print("<!-- ===== MARKDOWN REPORT END ===== -->")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
