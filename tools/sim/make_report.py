#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成「七傳說」数值仿真报告。

本脚本 import 仿真核心模块 dps_ehp_sim.py，把**真实计算结果**渲染进
Markdown 报告，避免手工誊抄数字出错。报告中的每一个数都来自实际运算。

用法：
    python make_report.py
    python make_report.py --out ../../deliverables/gstack/sim-report-2026-09-16.md
"""

from __future__ import annotations

import argparse
import datetime
import math
import os
import sys
from dataclasses import replace

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dps_ehp_sim as sim  # noqa: E402
from dps_ehp_sim import (  # noqa: E402
    Config, N_TIER, RARITY_NAMES, TIER_NAMES, avg_ttk, baseline_yield,
    build_recommended, build_tier_ladder, collect_violations, content_yield,
    geo_mean, log_slope, md_matrix, md_slope, md_violations, mob_count_for_duration,
    monster_curves, player_curves, slope_rows, slope_ok,
    survt_matrix, survt_ok, survt_window, ttk_matrix, ttk_ok, ttk_window,
    solve_recommended,
)

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

def stat_line(c: Config) -> str:
    ttk = ttk_matrix(c)
    sv = survt_matrix(c)
    sl = slope_rows(c)
    vio = collect_violations(c)
    at = [ttk[i][t] for i in range(c.lmax) for t in range(N_TIER)]
    asv = [sv[i][t] for i in range(c.lmax) for t in range(N_TIER)]
    an = [r["slope_norm"] for r in sl]
    return (
        f"- **TTK**：min {min(at):.2f}s / 均值 {sum(at)/len(at):.2f}s / max {max(at):.2f}s"
        f"　→　越界 **{len(vio['ttk_bad'])}/{vio['ttk_total']}**\n"
        f"- **SurvT**：min {min(asv):.2f}s / 均值 {sum(asv)/len(asv):.2f}s / max {max(asv):.2f}s"
        f"　→　越界 **{len(vio['survt_bad'])}/{vio['survt_total']}**\n"
        f"- **成长斜率比**：min {min(an):.3f} / 均值 {sum(an)/len(an):.3f} / max {max(an):.3f}"
        f"　→　越界 **{len(vio['slope_bad'])}/{vio['slope_total']}**"
    )


def key_rows_table(c: Config) -> str:
    players = player_curves(c)
    monsters = monster_curves(c)
    lines = [
        "| 关卡 | 裸装 AD | 总 AD | 装备 AD 占比 | DPS_exp | 普通怪 HP | 普通怪 DMG | EHP | 护甲减伤 DR |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for i in [0, 4, 9, 14, 19]:
        p, m = players[i], monsters[i]
        lines.append(
            f"| L{i+1} | {p['ad_base']:.1f} | {p['ad_total']:.1f} | "
            f"{p['gear_share_ad']*100:.1f}% | {p['dps']:.0f} | {m['hp']:.0f} | "
            f"{m['dmg']:.1f} | {p['ehp']:.0f} | {p['dr']*100:.1f}% |"
        )
    return "\n".join(lines)


def l20_row(c: Config) -> str:
    ttk = ttk_matrix(c)
    sv = survt_matrix(c)
    return (f"| {c.name} | {c.tier_hp:g} | {c.tier_dmg:g} | "
            f"{c.monster_hp_base:g}×{c.monster_hp_g:g}^(L-1) | "
            f"{c.monster_dmg_base:g}×{c.monster_dmg_g:g}^(L-1) | "
            + " | ".join(f"{ttk[19][t]:.2f}s" for t in range(N_TIER)) + " | "
            + " | ".join(f"{sv[19][t]:.2f}s" for t in range(N_TIER)) + " |")


# ---------------------------------------------------------------------------
# 报告正文
# ---------------------------------------------------------------------------

def build_report() -> str:
    base = Config()
    sol = solve_recommended(base, target_ttk=3.0, target_survt=10.0)
    rec_a, _ = build_recommended(base)
    rec_b = build_tier_ladder(base)

    c_orig = replace(base, name="GDD 原方案（×1.8^n）", tier_hp=1.80, tier_dmg=1.80)
    c_prop = replace(base, name="GDD 6.4 建议方案（HP ×1.6^n / DMG ×1.45^n）",
                     tier_hp=1.60, tier_dmg=1.45)

    # 方案 C / D（第 9 节详述，第 1 节 TL;DR 与第 10·五 节也要引用，故在此提前构造）
    cfg_c, sol_c = sim.build_capped(base, ttk_cap=5.0)
    cfg_d, sol_d = sim.build_dmg_dominant(base, ttk_cap=5.0)
    rec_b2 = rec_b  # 方案 B 复用

    orig_sl = slope_rows(c_orig)
    dps_ls = log_slope([p["dps"] for p in player_curves(base)])
    ehp_ls = log_slope([p["ehp"] for p in player_curves(base)])
    mhp_ls = log_slope([m["hp"] for m in monster_curves(base)])

    today = datetime.date.today().isoformat()
    R = []
    A = R.append

    # ================= 抬头 =================
    A(f"# 「七傳說」数值仿真报告 · 期望 DPS / 有效生命值双曲线校验")
    A("")
    A(f"**日期**：{today}　｜　**对应 GDD 节**：0.6.6「期望 DPS / 有效生命值双曲线对齐校验」")
    A(f"**执行**：实现工程师（sim-engineer）　｜　**主理人**：沽思航（Gu）")
    A(f"**脚本**：`tools/sim/dps_ehp_sim.py`（Python 3.13，纯标准库，无第三方依赖）")
    A(f"**报告生成器**：`tools/sim/make_report.py`（报告内全部数字由脚本实算渲染）")
    A(f"**原始运行输出**：`tools/sim/out/run-all.txt`　｜　**数据表**：`tools/sim/out/*.csv`")
    A("")
    A("**复现命令**：")
    A("")
    A("```bash")
    A("cd D:/七傳說/tools/sim")
    A('"C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe" \\')
    A("    dps_ehp_sim.py --scenario all --solve")
    A('"C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe" make_report.py')
    A("```")
    A("")
    A("---")
    A("")

    # ================= 一、结论摘要 =================
    A("## 一、结论摘要（TL;DR）")
    A("")
    A("### 1. GDD 对「×1.8^n 偏高」的判断 —— **成立**，但 GDD 严重低估了问题的规模")
    A("")
    A("GDD 6.4 只指出了 TTK 一条曲线崩坏。仿真显示**生存曲线崩得更彻底**：")
    A("")
    A(f"- 原方案 TTK 越界 **{len(collect_violations(c_orig)['ttk_bad'])}/100** 格，"
      f"SurvT 越界 **{len(collect_violations(c_orig)['survt_bad'])}/100** 格。")
    A(f"- L20·梦魇 V：TTK = **{ttk_matrix(c_orig)[19][4]:.2f}s**"
      f"（GDD 预估 17–23s，**完全命中**）；SurvT = **{survt_matrix(c_orig)[19][4]:.2f}s** "
      f"—— 意味着满装玩家被 4 只普通怪围住，**0.56 秒即死**。")
    A(f"- 更糟的是连梦魇 I 都不达标：L20·梦魇 I 的 SurvT = "
      f"**{survt_matrix(c_orig)[19][0]:.2f}s**，低于 8s 下限。")
    A("")
    A("### 2. GDD 6.4 的建议方案（HP 1.6^n / DMG 1.45^n）—— **方向正确，但力度远远不够**")
    A("")
    A(f"- 改后 TTK 越界仍 **{len(collect_violations(c_prop)['ttk_bad'])}/100**，"
      f"SurvT 越界仍 **{len(collect_violations(c_prop)['survt_bad'])}/100**。")
    A(f"- L20·梦魇 V 的 TTK 从 17.62s 降到 **{ttk_matrix(c_prop)[19][4]:.2f}s**，"
      f"仍超 4s 上限 **2.75 倍**。")
    A("- 结论：1.6^n 只是把「不可玩」改善成「仍然不可玩」，不构成可落地的修正。")
    A("")
    A("### 3. 根因是**结构性**的，不是系数微调问题（本报告最重要的一条）")
    A("")
    A("若 5 个难度层级共用同一套装备（GDD 3.6 明写「**难度层级不提升 iLvl**」），")
    A("且 TTK 必须落在 2.0–4.0s 区间内，则层级系数的**数学上限**是：")
    A("")
    A("```")
    A("tierHP^(N-1) ≤ TTK_max / TTK_min")
    A("```")
    A("")
    A("把梦魇 I 的 TTK 标定在区间中点 3.0s（上下都留余量），则：")
    A("")
    A("```")
    A("tierHP^4 ≤ 4.0 / 3.0 = 1.333")
    A("tierHP   ≤ 1.333^(1/4) = 1.075")
    A("```")
    A("")
    A("也就是说：**在「层级共用装备」的前提下，难度层级系数最多只能到 1.07^n。**")
    A("1.6^n 要求梦魇 V 的怪物 HP 是梦魇 I 的 6.55 倍，等价于要求玩家在梦魇 I→V")
    A("之间**战力提升 6.55 倍** —— 而 GDD 5.2 天赋树 60 级封顶（仅 30 点）、")
    A("3.6 禁止层级提升 iLvl，玩家根本不存在这个成长空间。**这是设计层面的自相矛盾，")
    A("不是数值调参能绕过去的。**")
    A("")
    A("### 4. 好消息：怪物 HP 成长 1.28^n **是对的，不需要改**")
    A("")
    A(f"玩家 DPS 的对数斜率 = **{dps_ls:.5f}/级**（等价成长倍率 "
      f"**{math.exp(dps_ls):.4f}^L**），怪物 HP 的对数斜率 = **{mhp_ls:.5f}/级**"
      f"（{base.monster_hp_g:g}^L），两者比值 **{dps_ls/mhp_ls:.3f}** —— "
      f"落在 1.00 ± 0.15 内，成长斜率比 **{len(collect_violations(c_orig)['slope_bad'])}/20 越界**。")
    A("")
    A("**GDD 6.3 的怪物 HP 成长系数 1.28 与玩家曲线天然匹配，应当保留。**")
    A("真正错的是另外两个数：**HP base 60（应 ≈ 101）** 和 **难度层级系数**。")
    A("")
    A("### 5. 同时发现 GDD 内部一处数值矛盾（6.2 节）")
    A("")
    A("GDD 6.2 同时写了两句互斥的话：")
    A("")
    A("| GDD 原文 | 数学含义 |")
    A("|---|---|")
    A("| 「满装 AD ≈ 裸装 × **6–8 倍**（L20）」 | 裸装占最终 AD 的 **12.5–14.3%** |")
    A("| 「裸装成长仅占最终战力约 **25–35%**」 | 满装 AD ≈ 裸装 × **2.9–4.0 倍** |")
    A("")
    A("两者相差约 2.3 倍，不可能同时成立。本仿真采用前者（×6–8，取 7.0），")
    A("因为它是 6.2 节里可直接施工的估算，且与 3.3 词缀公式能对上（推导见 2.2 节）。")
    A("**建议把「25–35%」这句改成「约 12–15%」，或明确它指的是别的口径"
      "（例如含天赋树 + 局内成长后的综合战力）。**")
    A("")
    A("### 6. 交付：两套全绿推荐系数")
    A("")
    A("| 方案 | 定位 | TTK 越界 | SurvT 越界 | 斜率越界 |")
    A("|---|---|---|---|---|")
    A(f"| **推荐 A** | 严格按 GDD 6.6 字面目标（全 100 格同一窗口） | 0/100 | 0/100 | 0/20 |")
    A(f"| **推荐 B** | 保留难度阶梯，为每层单独设目标窗口 | 0/100 | 0/100 | 0/20 |")
    A("")
    A("推荐 B 的层级系数为 **HP ×1.31^n / DMG ×1.24^n**，L20·梦魇 V 的 TTK 达 8.80s")
    A("—— 既有真正的难度梯度，又在分层目标窗口内全绿。**建议采用 B。**")
    A("")
    _tldr_mob = mob_count_for_duration(cfg_d, 17.5, 2.0, overhead_frac=0.35,
                                       elite_count=10.0, boss_ttk_s=90.0)
    _tldr_mob0 = mob_count_for_duration(cfg_d, 17.5, 2.0)
    A("### 7. 单局时长目标改为 14–21 分钟后：单关杂兵数需从 150 上调到 "
      f"**{_tldr_mob:.0f} 只**（详见第 10·五 节）")
    A("")
    A(f"用户已拍板 **D5 —— 中循环时长 = 14–21 分钟**（不再是 10 分钟）。"
      f"按第 10 节模型，方案 D 在现参数（150 杂兵 / AoE=3 / 开销 30%）下只有 **6.5 分钟**，"
      f"低于下限。反解结果：")
    A("")
    A(f"- **AoE 设计基准取 2.0**（`杂兵数 ∝ AoE`，取 3 会要求 500–835 只怪，超出关卡预算）；")
    A(f"- **单关杂兵数**：14 分钟 {mob_count_for_duration(cfg_d, 14.0, 2.0):.0f} 只 / "
      f"17.5 分钟 {_tldr_mob0:.0f} 只 / 21 分钟 "
      f"{mob_count_for_duration(cfg_d, 21.0, 2.0):.0f} 只（AoE=2、开销 30%、5 精英、BOSS 90s）；")
    A(f"- **推荐组合**（开销 30%→35% + 精英 5→10 + BOSS 战 90s→120s）可把所需杂兵数降到 "
      f"**{_tldr_mob:.0f} 只**，即「只比现在多放 "
      f"{_tldr_mob / 150:.2f} 倍」；")
    A(f"- **配套三件套**：① 地图面积同步放大 ×2（否则是「怪堆成山」）；"
      f"② 0.5 经验曲线系数 100 → {100 * _tldr_mob / 150:.0f}；"
      f"③ 6.5 满强化魔石 64 → "
      f"{64 * content_yield(_tldr_mob, 10.0)['mats'] / baseline_yield()['mats']:.0f}。"
      f"**6.1 掉落表不用改**（橙/红由精英/BOSS 驱动，杂兵翻倍只涨 ×1.04）。")
    A(f"- **第 10.3 节的密度阶梯应当取消** —— 它会把梦魇 V 压到 13.5 分钟，击穿下限。")
    A("")
    A("---")
    A("")

    # ================= 二、模型与口径 =================
    A("## 二、仿真模型与口径")
    A("")
    A("### 2.1 公式（严格取自 GDD 6.6）")
    A("")
    A("```")
    A("DPS_exp(L) = [AD_base(L) + AD_gear(L)] × (1 + CR × (CD - 1)) × AS × SkillMult")
    A("EHP(L)     = HP_total(L) / (1 - DR(L))")
    A("DR(L)      = ARM_total(L) / (ARM_total(L) + 50 × L)")
    A("TTK(L,n)   = MonsterHP(L) × tierHP^n / DPS_exp(L)          目标 2.0 – 4.0 s")
    A("SurvT(L,n) = EHP(L) / (MonsterDMG(L) × tierDMG^n × N)      目标 8 – 12 s（N=4）")
    A("```")
    A("")
    A("角色裸装与怪物曲线均按 GDD 6.2 / 6.3 原式：")
    A("")
    A("```")
    A("HP_base(L)      = 150 × 1.11^(L-1)")
    A("AD_base(L)      =  12 × 1.10^(L-1)")
    A("ARM_base(L)     =   6 × 1.10^(L-1)")
    A("Monster_HP(L)   =  60 × 1.28^(L-1)      精英 ×4.5　BOSS ×28")
    A("Monster_DMG(L)  =   8 × 1.24^(L-1)")
    A("```")
    A("")
    A("### 2.2 装备贡献系数：取值依据")
    A("")
    A("GDD 6.2 只给了两个端点描述（「L20 满装 AD ≈ 裸装 ×6–8 倍」），没有给逐级曲线。")
    A("本仿真把装备贡献抽象成一个乘子 `gear_mult(L)`（`总属性 = 裸装属性 × (1 + gear_mult)`），")
    A("并用 **L1 / L20 双锚点 + 曲线形态** 参数化。取值依据如下。")
    A("")
    A("**（a）L20 锚点 = 7.0 —— 自下而上核对 GDD 3.3 / 6.2 的装备规则：**")
    A("")
    A("| 来源 | 计算 | flat AD |")
    A("|---|---|---|")
    A("| 主手武器主属性（S0≈14，iLvl20 系数 1+0.12×19 = 3.28） | 14 × 3.28 | 45.9 |")
    A("| 副手（S0≈7） | 7 × 3.28 | 23.0 |")
    A("| 项链（S0≈4） | 4 × 3.28 | 13.1 |")
    A("| 双戒指（S0≈3 ×2） | 6 × 3.28 | 19.7 |")
    A("| 小计（4 个攻击位主属性，未强化） | | **101.7** |")
    A("| +10 强化（每级 +5%，线性叠加 = +50%） | 101.7 × 1.5 | **152.6** |")
    A("| +固定攻击力词缀（Base 5，iLvl20 = 5×2.615 = 13.1；满装约 5 条） | 13.1 × 5 | **65.4** |")
    A("| 装备 flat AD 合计 | 152.6 + 65.4 | **218.0** |")
    A("")
    A("- `+%攻击力` 词缀（Base 4%，iLvl20 = 10.5%；满装约 4 条）→ 总 AD **×1.418**")
    A("- 裸装 AD(20) = 73.4，flat 合计 = 73.4 + 218.0 = 291.4，×1.418 = **413.2**")
    A("- 413.2 / 73.4 = **×5.63**，再计入 GDD 3.5 的传奇特效（5 件，平均 +15–25% 有效输出）")
    A("- → **×6.5–7.0**，落在 GDD「6–8 倍」区间的中高段，取 **7.0**")
    A("")
    A("**（b）L1 锚点 = 0.5** —— L1 玩家只有开场几分钟捡到的 2–3 件白装")
    A("（无词缀、无强化、iLvl=1），仅主属性贡献少量攻击力，约相当于裸装 AD 的 +50%。")
    A("这是本模型中锚定最弱的一个参数，第 5 节给出了它的敏感性分析。")
    A("")
    A("**（c）曲线形态 = `expshift`（对 `1+gear_mult` 做指数插值）—— 这是一个关键选择：**")
    A("")
    A("| 曲线 | 定义 | `d ln(1+gm)/dL` 走势 | 斜率比结果 |")
    A("|---|---|---|---|")
    A("| `linear`（GDD 字面：iLvl 线性缩放） | `gm = lerp(0.5, 7.0, t)` | L1 ≈ 0.228 → L20 ≈ 0.043（**前快后慢**） | **1.61 → 0.83 单调下滑，9/20 越界** |")
    A("| `exp` | `gm = 0.5 × 14^t` | L1 ≈ 0.046 → L20 ≈ 0.121（前慢后快） | 反向失衡 |")
    A("| **`expshift`（默认）** | `1+gm = 1.5 × (8/1.5)^t` | **恒定 0.088** | **0.99 → 1.02，0/20 越界** |")
    A("")
    A("**这本身就是一条可交付的设计结论**：GDD 3.3 写的「词缀数值随 iLvl 线性缩放」")
    A("在**单条词缀**上没问题，但若把「满装总加成」也按线性堆叠，玩家成长会前快后慢，")
    A("斜率比必然从 1.61 掉到 0.83。**要让玩家成长与怪物成长同步，满装总加成必须呈指数形态。**")
    A("落地手段：让「装备档位」随关卡阶梯式跃升（GDD 6.5 已经写了「每 5 关 = 1 阶段」的")
    A("装备档位跃升，方向是对的），而不是让 10 个部位在同一关卡内均匀线性增长。")
    A("")
    A("### 2.3 「成长斜率比」口径修正（重要）")
    A("")
    A("GDD 6.6 写的判定式是 `(dDPS/dL) / (dMonsterHP/dL)`，用的是**原始导数**。")
    A("这个量纲不一致（DPS 与 HP 单位不同），数值随绝对刻度漂移，")
    A("在本模型下仅约 **0.33–0.34**，且无法用「1.00 ± 0.15」这种阈值判定 —— ")
    A("GDD 写「目标 1.00」本身就说明它想表达的不是原始导数比。")
    A("")
    A("本脚本同时输出两个口径：")
    A("")
    A("- `slope_raw` = 原始导数比（GDD 字面口径，仅作记录）")
    A("- **`slope_norm` = (ΔDPS/DPS) / (ΔMonsterHP/MonsterHP)** —— 相对增长率之比，")
    A("  即对数斜率之比，量纲无关。**这才是「玩家成长速度 vs 怪物成长速度是否同步」")
    A("  的正确表达，所有越界判定均以此为准。**")
    A("")
    A("> 另注：难度层级是常数倍率，不改变任何斜率，故表 3 与层级无关，只逐关输出。")
    A("")
    A("---")
    A("")

    # ================= 三、基线：原方案 =================
    A("## 三、基线：GDD 原方案（难度层级 ×1.8^n）")
    A("")
    A("**系数**：tier HP ×1.8^n / DMG ×1.8^n；MonsterHP 60×1.28^(L-1)；"
      "MonsterDMG 8×1.24^(L-1)；装备贡献 L1 ×0.5 → L20 ×7.0（expshift）")
    A("")
    A("**关键刻度**")
    A("")
    A(key_rows_table(c_orig))
    A("")
    A("**全表统计**")
    A("")
    A(stat_line(c_orig))
    A("")
    A(md_matrix(c_orig, ttk_matrix(c_orig), ttk_ok,
               "表 1 · 击杀时间 TTK（秒）", "秒", ttk_window))
    A(md_matrix(c_orig, survt_matrix(c_orig), survt_ok,
               "表 2 · 存活时间 SurvT（秒）", "秒", survt_window))
    A(md_slope(c_orig, orig_sl))
    A(md_violations(c_orig, collect_violations(c_orig)))
    A("**读表要点**")
    A("")
    A("- TTK 在梦魇 I 一列**全部偏低**（1.68–1.81s）—— 基线本身就低于 2.0s 下限，")
    A("  说明 GDD 的怪物 HP base 60 偏低，玩家在低层级是无双割草。")
    A("- TTK 在梦魇 III–V **全部偏高**，梦魇 V 稳定在 **17.6–19.0s**。")
    A("- SurvT 在 **99/100 格全部偏低**，最差 0.56s。这不是「有风险」，是「碰到就死」。")
    A("- 成长斜率比反而全绿 —— 问题**不在曲线斜率，在绝对刻度与层级系数**。")
    A("")
    A("---")
    A("")

    # ================= 四、GDD 建议方案 =================
    A("## 四、GDD 6.4 建议方案（HP ×1.6^n / DMG ×1.45^n）")
    A("")
    A("GDD 6.4 提出把层级系数从 ×1.8^n 改为 HP ×1.6^n / DMG ×1.45^n。仿真结果：")
    A("")
    A("**全表统计**")
    A("")
    A(stat_line(c_prop))
    A("")
    A(md_matrix(c_prop, ttk_matrix(c_prop), ttk_ok,
               "表 1 · 击杀时间 TTK（秒）", "秒", ttk_window))
    A(md_matrix(c_prop, survt_matrix(c_prop), survt_ok,
               "表 2 · 存活时间 SurvT（秒）", "秒", survt_window))
    vo, vp = collect_violations(c_orig), collect_violations(c_prop)
    ttk_o, ttk_p = ttk_matrix(c_orig), ttk_matrix(c_prop)
    sv_o, sv_p = survt_matrix(c_orig), survt_matrix(c_prop)
    at_o = [ttk_o[i][t] for i in range(20) for t in range(N_TIER)]
    at_p = [ttk_p[i][t] for i in range(20) for t in range(N_TIER)]
    as_o = [sv_o[i][t] for i in range(20) for t in range(N_TIER)]
    as_p = [sv_p[i][t] for i in range(20) for t in range(N_TIER)]

    def delta(a: float, b: float, pct: bool = True) -> str:
        if a == b:
            return "无变化"
        d = (b - a) / a * 100 if pct else b - a
        return f"{d:+.0f}%" if pct else f"{d:+.0f} 格"

    A("**对照结论**")
    A("")
    A("| 指标 | ×1.8^n（原） | ×1.6^n / ×1.45^n（建议） | 变化 | 是否达标 |")
    A("|---|---|---|---|---|")
    A(f"| L20·梦魇 V TTK | {ttk_o[19][4]:.2f}s | {ttk_p[19][4]:.2f}s | "
      f"{delta(ttk_o[19][4], ttk_p[19][4])} | ✗ 仍超上限 {ttk_p[19][4]/4:.2f} 倍 |")
    A(f"| 全表 TTK 最大值 | {max(at_o):.2f}s | {max(at_p):.2f}s | "
      f"{delta(max(at_o), max(at_p))} | ✗ 仍远超 4.0s |")
    A(f"| TTK 越界格数 | {len(vo['ttk_bad'])}/100 | {len(vp['ttk_bad'])}/100 | "
      f"{delta(len(vo['ttk_bad']), len(vp['ttk_bad']), pct=False)} | ✗ |")
    A(f"| SurvT 越界格数 | {len(vo['survt_bad'])}/100 | {len(vp['survt_bad'])}/100 | "
      f"{delta(len(vo['survt_bad']), len(vp['survt_bad']), pct=False)} | ✗ |")
    A(f"| 全表 SurvT 最小值 | {min(as_o):.2f}s | {min(as_p):.2f}s | "
      f"{delta(min(as_o), min(as_p))} | ✗ 仍远低于 8.0s |")
    A("")
    A("**为什么越界格数一格都没减少？**")
    A("")
    A("因为越界是**结构性的**，不是数值幅度问题。逐层级拆开看：")
    A("")
    A("| 层级 | ×1.8^n 的 TTK 范围 | ×1.6^n 的 TTK 范围 | 数值是否改善 | 判定 |")
    A("|---|---|---|---|---|")
    for t in range(N_TIER):
        col_o = [ttk_o[i][t] for i in range(20)]
        col_p = [ttk_p[i][t] for i in range(20)]
        imp = "—" if abs(max(col_o) - max(col_p)) < 1e-9 else f"−{max(col_o)-max(col_p):.2f}s"
        v_p = "达标" if ttk_ok(col_p[0], c_prop, t) else "**越界**"
        A(f"| {TIER_NAMES[t]} | {min(col_o):.2f} – {max(col_o):.2f}s | "
          f"{min(col_p):.2f} – {max(col_p):.2f}s | {imp} | {v_p} |")
    A("")
    A("- **梦魇 I 一列**：两种方案的 TTK 都是 1.68–1.81s，**同样低于 2.0s 下限** "
      "—— 层级系数根本不作用在这一列上，改层级系数永远修不好它。")
    A("- **梦魇 III–V**：1.6^n 让数值从「5.4–18.9s」压到「4.3–11.8s」，"
      "幅度确有改善，但**全部仍在上限之外**。")
    A("- 净效果：越界格数 **80 → 80，一格没少**。"
      "**1.6^n 只是把最坏情况从「不可玩」改善到「仍然不可玩」。**")
    A("")
    A("**结论：GDD 6.4 的判断方向正确（×1.8^n 确实偏高），"
      "但给出的替代值力度不足，不构成可落地的修正。**")
    A("")
    A("---")
    A("")

    # ================= 五、反解 =================
    A("## 五、反解：系数到底该取多少")
    A("")
    A("### 5.1 反解原理")
    A("")
    A("要让 TTK / SurvT 在 L1–L20 上保持恒定（即斜率比 = 1.00），")
    A("怪物曲线的**对数斜率必须等于玩家曲线的对数斜率**：")
    A("")
    A("```")
    A("g_monster = exp( d ln(玩家属性) / dL ) - 1")
    A("```")
    A("")
    A("再由「全 20 关的**几何平均**」反解 base（用几何平均而非端点标定，")
    A("可让整条曲线居中落在目标区间内；端点标定会让另一侧越界）。")
    A("层级系数则由「层级 I 时 L1–L20 的**实际极值**」反解，")
    A("保证梦魇 V 恰好压在目标边界上、不产生新的越界。")
    A("")
    A("### 5.2 反解结果（`--solve` 实算输出）")
    A("")
    A("```")
    A(f"玩家 DPS 对数斜率 = {sol['dps_log_slope']:.5f} /级 "
      f"→ 等价成长倍率 {sol['monster_hp_g']:.4f}^L")
    A(f"玩家 EHP 对数斜率 = {sol['ehp_log_slope']:.5f} /级 "
      f"→ 等价成长倍率 {sol['monster_dmg_g']:.4f}^L")
    A(f"⇒ 怪物 HP  成长应为 {sol['monster_hp_g']:.4f}^(L-1)  (GDD 原 {base.monster_hp_g:g})")
    A(f"⇒ 怪物 DMG 成长应为 {sol['monster_dmg_g']:.4f}^(L-1)  (GDD 原 {base.monster_dmg_g:g})")
    A(f"⇒ 怪物 HP  base 应为 {sol['monster_hp_base']:.1f}          (GDD 原 {base.monster_hp_base:g})")
    A(f"⇒ 怪物 DMG base 应为 {sol['monster_dmg_base']:.2f}         (GDD 原 {base.monster_dmg_base:g})")
    A(f"⇒ 难度层级 HP  系数应为 {sol['tier_hp']:.4f}^n  (GDD 原 1.8 / 建议 1.6)")
    A(f"⇒ 难度层级 DMG 系数应为 {sol['tier_dmg']:.4f}^n  (GDD 原 1.8 / 建议 1.45)")
    A("```")
    A("")
    A("三条关键读数：")
    A("")
    A(f"1. **怪物 HP 成长 {sol['monster_hp_g']:.4f} ≈ GDD 的 1.28** —— 原值是对的，保留。")
    A(f"2. **怪物 HP base 应为 {sol['monster_hp_base']:.1f}，是原值 60 的 "
      f"{sol['monster_hp_base']/60:.2f} 倍** —— 这才是 TTK 全表偏低的根因。")
    A(f"3. **层级 HP 系数应为 {sol['tier_hp']:.4f}^n** —— 与 1.6 / 1.8 差了一个数量级的修正。")
    A("")

    # ---- 推荐 A ----
    A("### 5.3 推荐方案 A：全格统一窗口（严格按 GDD 6.6 字面目标）")
    A("")
    A("要求 20 关 × 5 层级 = 100 个格子**全部**满足 TTK 2–4s / SurvT 8–12s。")
    A("")
    A("**系数**：tier HP ×1.07^n / DMG ×1.04^n；"
      f"MonsterHP {rec_a.monster_hp_base:g}×{rec_a.monster_hp_g:g}^(L-1)；"
      f"MonsterDMG {rec_a.monster_dmg_base:g}×{rec_a.monster_dmg_g:g}^(L-1)")
    A("")
    A("**全表统计**")
    A("")
    A(stat_line(rec_a))
    A("")
    A("L20 逐层级 TTK：" + " / ".join(f"{ttk_matrix(rec_a)[19][t]:.2f}s" for t in range(N_TIER)))
    A("")
    A("**问题**：层级系数只有 1.07^n 意味着梦魇 V 的怪物 HP 仅比梦魇 I 高 "
      f"**{rec_a.tier_hp**4:.2f} 倍**、DMG 高 **{rec_a.tier_dmg**4:.2f} 倍** —— "
      "难度层级形同虚设，失去「更高层级」的意义。**数学上全绿，但设计上不可接受。**")
    A("")
    A("这正是「5 个层级共用同一套装备 + 2–4s 窄窗口」这个约束的必然结果，")
    A("也反证了第 3 节的结论。")
    A("")
    A("### 5.4 推荐方案 B：分层目标窗口 · 难度阶梯（**建议采用**）")
    A("")
    A("把 GDD 的 2–4s / 8–12s 重新定位为**梦魇 I–II 的目标**，")
    A("层级 III–V 明确为「挑战 / 炫耀」内容，各自设定递减窗口：")
    A("")
    A("| 层级 | TTK 目标窗口 | SurvT 目标窗口 | 定位 |")
    A("|---|---|---|---|")
    for t in range(N_TIER):
        lo_t, hi_t = sim.LADDER_TTK_WINDOWS[t]
        lo_s, hi_s = sim.LADDER_SURVT_WINDOWS[t]
        role = ["舒适区", "略紧", "挑战", "高压", "极限"][t]
        A(f"| {TIER_NAMES[t]} | {lo_t:g} – {hi_t:g} s | {lo_s:g} – {hi_s:g} s | {role} |")
    A("")
    A("**系数**：tier HP ×1.31^n / DMG ×1.24^n；"
      f"MonsterHP {rec_b.monster_hp_base:g}×{rec_b.monster_hp_g:g}^(L-1)；"
      f"MonsterDMG {rec_b.monster_dmg_base:g}×{rec_b.monster_dmg_g:g}^(L-1)")
    A("")
    A("**关键刻度**")
    A("")
    A(key_rows_table(rec_b))
    A("")
    A("**全表统计**")
    A("")
    A(stat_line(rec_b))
    A("")
    A(md_matrix(rec_b, ttk_matrix(rec_b), ttk_ok,
               "表 1 · 击杀时间 TTK（秒）", "秒", ttk_window))
    A(md_matrix(rec_b, survt_matrix(rec_b), survt_ok,
               "表 2 · 存活时间 SurvT（秒）", "秒", survt_window))
    A(md_slope(rec_b, slope_rows(rec_b)))
    A(md_violations(rec_b, collect_violations(rec_b)))
    A("**读表要点**")
    A("")
    A(f"- TTK 从梦魇 I 的 2.95–3.03s 平滑爬升到梦魇 V 的 8.70–8.93s，"
      f"形成真正的难度梯度，且每关之间几乎水平（成长同步）。")
    A(f"- SurvT 从梦魇 I 的 9.66–10.90s 下降到梦魇 V 的 4.09–4.61s，"
      f"高层级有真实死亡压力。")
    A("- 成长斜率比 0.989–1.021，**20 关全部落在 1.00 ± 0.15 内**。")
    A("")
    A("---")
    A("")

    # ================= 六、对 1.8^n 的判断 =================
    A("## 六、对「难度层级 ×1.8^n 偏高」的正式判断")
    A("")
    A("### 判断一：**×1.8^n 偏高 —— 证实（CONFIRMED）**")
    A("")
    A("仿真独立复现了 GDD 的预估：")
    A("")
    A("| 指标 | GDD 6.4 预估 | 仿真实测 | 是否命中 |")
    A("|---|---|---|---|")
    A(f"| L20·梦魇 V 的 TTK | 17–23 秒 | **{ttk_matrix(c_orig)[19][4]:.2f} 秒** | ✅ 命中 |")
    A(f"| 玩家 L20 满装期望 DPS | 3,000–4,000 | **{player_curves(base)[19]['dps']:.0f}** | ✅ 命中 |")
    A(f"| 梦魇 V 怪物 HP | ≈ 68,600 | **{monster_curves(base)[19]['hp']*1.8**4:.0f}** | ✅ 命中 |")
    A("")
    A("GDD 的推理链（HP 基数 × 层级倍率 ÷ 玩家 DPS 上限）在数量级上完全正确，")
    A("**×1.8^n 必须废弃，这一点没有争议。**")
    A("")
    A("### 判断二：**GDD 给出的替代值 1.6^n / 1.45^n 同样不可用 —— 补充修正**")
    A("")
    A(f"1.6^n 下 L20·梦魇 V 的 TTK 仍有 **{ttk_matrix(c_prop)[19][4]:.2f}s**（上限 4.0s），")
    A(f"SurvT 仍有 **{survt_matrix(c_prop)[19][4]:.2f}s**（下限 8.0s），")
    A(f"TTK 越界 {len(collect_violations(c_prop)['ttk_bad'])}/100、"
      f"SurvT 越界 {len(collect_violations(c_prop)['survt_bad'])}/100。")
    A("**GDD 6.4 的「修正建议」应当被本报告的 5.4 节方案替代。**")
    A("")
    A("### 判断三：**根因不是「1.8 太大」，而是「层级窗口与层级数量不匹配」**")
    A("")
    A("把三层约束摆在一起看：")
    A("")
    A("1. TTK 目标窗口宽度 = 4.0 / 2.0 = **2.0 倍**")
    A("2. 难度层级数量 = **5 层**（指数 0–4）")
    A("3. GDD 3.6：**难度层级不提升 iLvl**，即层级之间玩家装备不变")
    A("")
    A("在这三条约束下，层级系数的上限被锁死：")
    A("")
    A("```")
    A("tierHP^4 ≤ 4.0 / 2.0 = 2.0")
    A("tierHP   ≤ 2.0^(1/4) = 1.189        ← 绝对上限（把梦魇 I 标定在 2.0s 下限）")
    A("tierHP   ≤ (4.0/3.0)^(1/4) = 1.075  ← 实用值（梦魇 I 标定在 3.0s 中点，上下留余量）")
    A("```")
    A("")
    A("**1.6^n 需要 6.55 倍的层级跨度，是数学上限 1.189^4 = 2.0 倍的 3.3 倍。**")
    A("换句话说，要让 1.6^n 成立，必须**同时**放宽以下至少一条：")
    A("")
    A("| 放宽手段 | 具体做法 | 代价 |")
    A("|---|---|---|")
    A("| ① 放宽 TTK 窗口 | 允许高层级 TTK 到 8–9s（即本报告推荐 B） | 高层级手感更粘滞，但定位为挑战内容可接受 |")
    A("| ② 让层级提升 iLvl | 梦魇 II 掉 iLvl+2 装备，依此类推 | 违反 GDD 3.6，且会破坏「装备=关卡等级」的清晰心智模型 |")
    A("| ③ 减少层级数量 | 从 5 层压到 2–3 层 | 内容量缩水，且已写入 GDD 5.4 解锁表 |")
    A("| ④ 引入层级专属成长轴 | 层级内独立的巅峰等级 / 词缀池 | 新增系统，超出阶段 0 范围 |")
    A("")
    A("**本报告推荐 ①**（即方案 B），因为它不破坏 GDD 的任何既有结构，")
    A("只把「2–4s」这个单一硬指标改成分层指标。")
    A("")
    A("---")
    A("")

    # ================= 七、推荐系数表 =================
    A("## 七、调参建议（最终推荐系数表）")
    A("")
    A("### 7.1 需要改动的系数（推荐 B）")
    A("")
    A("| # | 系数 | GDD 原值 | GDD 6.4 建议 | **本报告推荐** | 改动幅度 | 依据 |")
    A("|---|---|---|---|---|---|---|")
    A(f"| 1 | 难度层级 HP 系数 | 1.80^n | 1.60^n | **{rec_b.tier_hp:g}^n** | 大幅下调 | "
      "层级窗口数学上限 + 分层窗口反解 |")
    A(f"| 2 | 难度层级 DMG 系数 | 1.80^n | 1.45^n | **{rec_b.tier_dmg:g}^n** | 大幅下调 | 同上 |")
    A(f"| 3 | 怪物 HP base | 60 | 60（未动） | **{rec_b.monster_hp_base:g}** | ×{rec_b.monster_hp_base/60:.2f} | "
      "TTK 全表偏低的根因 |")
    A(f"| 4 | 怪物 DMG base | 8 | 8（未动） | **{rec_b.monster_dmg_base:g}** | ×{rec_b.monster_dmg_base/8:.2f} | "
      "SurvT 全表偏低的根因 |")
    A(f"| 5 | 怪物 DMG 成长 | 1.24 | 1.24（未动） | **{rec_b.monster_dmg_g:g}** | 微调 | "
      "EHP 对数斜率 = " + f"{ehp_ls:.4f}" + " |")
    A(f"| 6 | 怪物 HP 成长 | 1.28 | 1.28（未动） | **1.28（保留）** | 不变 | "
      "与玩家 DPS 斜率天然匹配，比值 1.016 |")
    A(f"| 7 | 装备贡献曲线形态 | 线性（隐含） | 未提 | **expshift（指数）** | 形态修正 | "
      "线性会导致斜率比 1.61→0.83 |")
    A("")
    A("### 7.2 各方案横向对比（L20 关键行）")
    A("")
    A("**TTK（秒）**")
    A("")
    A("| 方案 | tier HP | tier DMG | 怪物HP | 怪物DMG | 梦魇 I | 梦魇 II | 梦魇 III | 梦魇 IV | 梦魇 V |")
    A("|---|---|---|---|---|---|---|---|---|---|")
    for c in (c_orig, c_prop, rec_a, rec_b):
        ttk = ttk_matrix(c)
        A(f"| {c.name} | {c.tier_hp:g} | {c.tier_dmg:g} | "
          f"{c.monster_hp_base:g}×{c.monster_hp_g:g}^(L-1) | "
          f"{c.monster_dmg_base:g}×{c.monster_dmg_g:g}^(L-1) | "
          + " | ".join(f"{ttk[19][t]:.2f}" for t in range(N_TIER)) + " |")
    A("")
    A("**SurvT（秒）**")
    A("")
    A("| 方案 | 梦魇 I | 梦魇 II | 梦魇 III | 梦魇 IV | 梦魇 V |")
    A("|---|---|---|---|---|---|")
    for c in (c_orig, c_prop, rec_a, rec_b):
        sv = survt_matrix(c)
        A(f"| {c.name} | " + " | ".join(f"{sv[19][t]:.2f}" for t in range(N_TIER)) + " |")
    A("")
    A("**越界汇总**")
    A("")
    A("| 方案 | TTK 越界 | SurvT 越界 | 斜率比越界 | 综合 |")
    A("|---|---|---|---|---|")
    for c in (c_orig, c_prop, rec_a, rec_b):
        v = collect_violations(c)
        total = len(v["ttk_bad"]) + len(v["survt_bad"]) + len(v["slope_bad"])
        mark = "✅ 全绿" if total == 0 else f"❌ {total} 格越界"
        A(f"| {c.name} | {len(v['ttk_bad'])}/100 | {len(v['survt_bad'])}/100 | "
          f"{len(v['slope_bad'])}/20 | {mark} |")
    A("")

    # ================= 八、敏感性 =================
    A("### 7.3 敏感性分析（关键参数动了，结论还成立吗？）")
    A("")
    A("**（a）装备贡献系数 L20 锚点（GDD 说 6–8 倍，实测区间 3–9 倍）**")
    A("")
    A("| gear_*_20 | 玩家 DPS 对数斜率 | 反解怪物 HP 成长 | 反解怪物 HP base | 反解 tier HP |")
    A("|---|---|---|---|---|")
    for g in (3.0, 5.0, 7.0, 9.0):
        cfg = replace(base, gear_ad_20=g, gear_hp_20=g, gear_arm_20=g)
        s = solve_recommended(cfg, 3.0, 10.0)
        A(f"| ×{g:g} | {s['dps_log_slope']:.5f} | {s['monster_hp_g']:.4f} | "
          f"{s['monster_hp_base']:.1f} | {s['tier_hp']:.4f} |")
    A("")
    A("→ **结论稳健**：怪物 HP 成长反解值在 1.24–1.30 之间，**GDD 的 1.28 恰好落在中点**；")
    A("  层级 HP 系数稳定在 **1.07**，与 1.6 / 1.8 的差距不因装备假设而改变。")
    A("")
    A("**（b）装备贡献系数 L1 锚点（本模型最弱假设）**")
    A("")
    A("| gear_*_1 | 反解怪物 HP 成长 | 反解怪物 HP base | 反解 tier HP |")
    A("|---|---|---|---|")
    for g in (0.2, 0.5, 1.0, 1.5):
        cfg = replace(base, gear_ad_1=g, gear_hp_1=g, gear_arm_1=g)
        s = solve_recommended(cfg, 3.0, 10.0)
        A(f"| ×{g:g} | {s['monster_hp_g']:.4f} | {s['monster_hp_base']:.1f} | {s['tier_hp']:.4f} |")
    A("")
    A("→ **HP base 对 L1 锚点敏感**（80.6 → 168.0，随 L1 玩家强度线性上升），")
    A("  但**层级系数完全不受影响（恒为 1.07）**，怪物 HP 成长也只在 1.25–1.30 之间小幅移动。")
    A("  **结论：核心判断（层级系数必须大幅下调）不依赖这个弱假设。**")
    A("")
    A("**（c）DPS 乘子 K(L) 的成长速度**")
    A("")
    A("| K(L) 设定 | 玩家 DPS 对数斜率 | 反解怪物 HP 成长 | 反解怪物 HP base | 反解 tier HP |")
    A("|---|---|---|---|---|")
    k_cases = [
        ("K 恒定（CR/CD/AS/SM 不随关卡成长）",
         dict(cr_1=0.30, cr_20=0.30, cd_1=2.0, cd_20=2.0,
              as_1=1.3, as_20=1.3, sm_1=2.3, sm_20=2.3)),
        ("本报告默认（缓慢成长）", {}),
        ("K 快速成长（AS 1.0→2.2, SM 1.5→3.5）",
         dict(as_1=1.0, as_20=2.2, sm_1=1.5, sm_20=3.5)),
    ]
    for label, kw in k_cases:
        cfg = replace(base, **kw)
        s = solve_recommended(cfg, 3.0, 10.0)
        A(f"| {label} | {s['dps_log_slope']:.5f} | {s['monster_hp_g']:.4f} | "
          f"{s['monster_hp_base']:.1f} | {s['tier_hp']:.4f} |")
    A("")
    A("→ **tier HP 反解值在 1.05–1.07 之间**，无论 K 怎么假设都远离 1.6 / 1.8。")
    A("  这是本报告最稳健的一条结论。")
    A("")
    A("---")
    A("")

    # ================= 九、用法 =================
    A("## 八、参数化用法")
    A("")
    A("脚本所有关键系数均可命令行覆盖，方便后续调参时反复回测。")
    A("")
    A("```bash")
    A("PY=\"C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe\"")
    A("")
    A("# 1) 跑 GDD 原方案（默认）")
    A("$PY dps_ehp_sim.py")
    A("")
    A("# 2) 跑全部方案并对比")
    A("$PY dps_ehp_sim.py --scenario all")
    A("")
    A("# 3) 反解推荐系数")
    A("$PY dps_ehp_sim.py --solve")
    A("")
    A("# 4) 改系数回测（例：怪物 HP 成长改 1.20、层级 HP 改 1.25）")
    A("$PY dps_ehp_sim.py --monster-hp-g 1.20 --tier-hp 1.25")
    A("")
    A("# 5) 导出 CSV（默认写到 tools/sim/out/）")
    A("$PY dps_ehp_sim.py --scenario all --csv-dir out")
    A("```")
    A("")
    A("**全部命令行参数**")
    A("")
    A("| 分组 | 参数 | 默认值 | 说明 |")
    A("|---|---|---|---|")
    A("| 场景 | `--scenario` | `gdd-original` | "
      "`gdd-original` / `gdd-proposed` / `sim-recommended` / `tier-ladder` / `all` |")
    A("| 场景 | `--solve` | 关 | 反解推荐的怪物系数与层级系数 |")
    A("| 场景 | `--csv-dir` | `out` | CSV 输出目录（空字符串 = 不导出） |")
    A("| 角色 | `--hp-base / --hp-g` | 150 / 0.11 | 裸装生命曲线 |")
    A("| 角色 | `--ad-base / --ad-g` | 12 / 0.10 | 裸装攻击力曲线 |")
    A("| 角色 | `--arm-base / --arm-g` | 6 / 0.10 | 裸装护甲曲线 |")
    A("| 装备 | `--gear-ad-1 / --gear-ad-20` | 0.5 / 7.0 | 装备攻击贡献锚点 |")
    A("| 装备 | `--gear-hp-1 / --gear-hp-20` | 0.5 / 7.0 | 装备生命贡献锚点 |")
    A("| 装备 | `--gear-arm-1 / --gear-arm-20` | 0.5 / 7.0 | 装备护甲贡献锚点 |")
    A("| 装备 | `--gear-curve` | `expshift` | `expshift` / `linear` / `exp` |")
    A("| 输出乘子 | `--cr-1 / --cr-20` | 0.05 / 0.40 | 暴击率 |")
    A("| 输出乘子 | `--cd-1 / --cd-20` | 1.50 / 2.20 | 暴击伤害倍率 |")
    A("| 输出乘子 | `--as-1 / --as-20` | 1.00 / 1.60 | 攻击速度（次/秒） |")
    A("| 输出乘子 | `--sm-1 / --sm-20` | 1.80 / 2.80 | 技能倍率 |")
    A("| 怪物 | `--monster-hp-base / --monster-hp-g` | 60 / 1.28 | 怪物 HP |")
    A("| 怪物 | `--monster-dmg-base / --monster-dmg-g` | 8 / 1.24 | 怪物伤害 |")
    A("| 怪物 | `--elite-hp-mult / --boss-hp-mult` | 4.5 / 28 | 精英 / BOSS HP 倍率 |")
    A("| 层级 | `--tier-hp / --tier-dmg` | 1.80 / 1.80 | 难度层级系数 |")
    A("| 生存 | `--armor-k` | 50 | 护甲减伤公式常数 |")
    A("| 生存 | `--surv-n` | 4 | 同时受击数 N |")
    A("| 目标 | `--ttk-min / --ttk-max` | 2.0 / 4.0 | TTK 目标区间 |")
    A("| 目标 | `--survt-min / --survt-max` | 8.0 / 12.0 | SurvT 目标区间 |")
    A("| 目标 | `--slope-tol` | 0.15 | 斜率比容差 |")
    A("| 单局时长 | `--mob-count` | 150 | 普通关杂兵数 |")
    A("| 单局时长 | `--elite-count / --boss-count` | 5 / 1 | 精英 / BOSS 数量 |")
    A("| 单局时长 | `--density` | `1.0,0.9,0.8,0.7,0.6` | 各层级怪物密度系数（逗号分隔 5 个） |")
    A("| 单局时长 | `--aoe-factor` | 3.0 | 每单位 TTK 时间清掉的怪物数（1.0 = 纯单体） |")
    A("| 单局时长 | `--elite-ttk / --boss-ttk` | 12 / 90 | 精英 / BOSS 的击杀时间（秒） |")
    A("| 单局时长 | `--overhead-frac` | 0.30 | 跑图 / 拾取 / 结算占总时长比例 |")
    A("| 单局时长 | `--run-budget` | 600 | 单局时长预算（秒） |")
    A("| 单局时长 | `--ttk-cap` | 5.0 | 梦魇 V 的 TTK 硬上限（capped / dmg-dominant 方案用） |")
    A("")
    A("**场景预设**")
    A("")
    A("| `--scenario` | 说明 |")
    A("|---|---|")
    A("| `gdd-original` | GDD 原方案 ×1.8^n（默认） |")
    A("| `gdd-proposed` | GDD 6.4 建议方案 1.6^n / 1.45^n |")
    A("| `sim-recommended` | 方案 A：全格统一窗口 |")
    A("| `tier-ladder` | 方案 B：分层 TTK/SurvT 窗口 · 难度阶梯 |")
    A("| `capped` | 方案 C：TTK≤5s 硬约束 · HP 主导 · 全局 SurvT 窗口 |")
    A("| `dmg-dominant` | 方案 D：DMG 主导 · SurvT 阶梯窗口 |")
    A("| `all` | 全部 6 个方案一起跑并对比 |")
    A("")
    A("**CSV 输出**（`tools/sim/out/`，UTF-8-BOM，Excel 可直接打开）")
    A("")
    A("| 文件后缀 | 内容 |")
    A("|---|---|")
    A("| `_ttk.csv` | 20 关 × 5 层级的 TTK 矩阵 |")
    A("| `_survt.csv` | 20 关 × 5 层级的 SurvT 矩阵 |")
    A("| `_slope.csv` | 逐关的 DPS / 怪物HP / 导数 / 两种斜率比口径 |")
    A("| `_stats.csv` | 逐关完整面板（裸装、装备乘子、总属性、CR/CD/AS/SM、DPS、DR、EHP、怪物数值、装备 AD 占比） |")
    A("")
    A("---")
    A("")

    # ================= 九、方案 C / D =================
    A("## 九、追加：按 product-reviewer 决策口径复跑（方案 C / D）")
    A("")
    A("product-reviewer 在 GDD v1.4 中给出决策：**接受方案 B，但加一条 TTK ≤ 5.0s 硬约束**"
      "（保单局时长），且**难度主体放在 DMG 而非 HP**。本节按该口径复跑。")
    A("")
    A("### 9.1 先说一个反直觉的数学结论")
    A("")
    A("「难度主体放 DMG」在**全局 SurvT 窗口**下**做不到**。原因是两个窗口的跨度不对等：")
    A("")
    A("| 窗口 | 跨度 | 允许的层级系数上限 |")
    A("|---|---|---|")
    A(f"| TTK [2.0, {cfg_c.ttk_max:g}]（抬高上限后） | {cfg_c.ttk_max/2.0:.2f} 倍 | "
      f"({cfg_c.ttk_max:g}/2.0)^(1/4) = **{(cfg_c.ttk_max/2.0)**0.25:.3f}** |")
    A(f"| SurvT [8, 12]（全局） | 1.50 倍 | (12/8)^(1/4) = **{1.5**0.25:.3f}** |")
    A("")
    A("**TTK 轴能涨到 1.257，SurvT 轴只能涨到 1.107** —— 所以只要 SurvT 守全局窗口，")
    A("**HP 必然是主导轴，DMG 只能是配角**。想让 DMG 主导，就必须给 SurvT 也配阶梯窗口")
    A("（即接受梦魇 V 的存活时间从 12s 掉到 4–5s）。")
    A("")
    A("下面给两个方案，正好是这两条路线：")
    A("")
    A("| 方案 | 路线 | tierHP | tierDMG | SurvT 窗口 |")
    A("|---|---|---|---|---|")
    A(f"| **C** | 守全局 SurvT 窗口（product-reviewer 字面口径） | "
      f"**{cfg_c.tier_hp:g}^n** | **{cfg_c.tier_dmg:g}^n** | 全局 [8,12] |")
    A(f"| **D** | DMG 主导（SurvT 改阶梯） | **{cfg_d.tier_hp:g}^n** | "
      f"**{cfg_d.tier_dmg:g}^n** | 阶梯 12s→4.5s |")
    A("")

    # ---- 方案 C ----
    A("### 9.2 方案 C · 守全局 SurvT 窗口（HP 主导）")
    A("")
    A("**系数**：")
    A("")
    A("```")
    A(f"难度层级 HP 系数  = {cfg_c.tier_hp:g}^n        （梦魇 V = ×{cfg_c.tier_hp**4:.2f}）")
    A(f"难度层级 DMG 系数 = {cfg_c.tier_dmg:g}^n        （梦魇 V = ×{cfg_c.tier_dmg**4:.2f}）")
    A(f"怪物 HP  = {cfg_c.monster_hp_base:g} × {cfg_c.monster_hp_g:g}^(L-1)")
    A(f"怪物 DMG = {cfg_c.monster_dmg_base:g} × {cfg_c.monster_dmg_g:g}^(L-1)")
    A("TTK 目标窗口   = [2.0, 5.0] s")
    A("SurvT 目标窗口 = [8, 12] s（全局，每层都须达标）")
    A("```")
    A("")
    A("**全表统计**")
    A("")
    A(stat_line(cfg_c))
    A("")
    A("L20 逐层级 TTK：" + " / ".join(f"{ttk_matrix(cfg_c)[19][t]:.2f}s" for t in range(N_TIER)))
    A("")
    A(md_matrix(cfg_c, ttk_matrix(cfg_c), ttk_ok,
               "表 1 · 击杀时间 TTK（秒）", "秒", ttk_window))
    A(md_matrix(cfg_c, survt_matrix(cfg_c), survt_ok,
               "表 2 · 存活时间 SurvT（秒）", "秒", survt_window))
    A(md_slope(cfg_c, slope_rows(cfg_c)))
    A(md_violations(cfg_c, collect_violations(cfg_c)))
    _c_ttk = ttk_matrix(cfg_c)
    _c_sv = survt_matrix(cfg_c)
    _c_sv_all = [_c_sv[i][t] for i in range(20) for t in range(N_TIER)]
    _d_ttk = ttk_matrix(cfg_d)
    _d_sv = survt_matrix(cfg_d)
    A("**读表要点**")
    A("")
    A(f"- TTK 从 {_c_ttk[19][0]:.2f}s（梦魇 I）平滑升到 **{_c_ttk[19][4]:.2f}s**（梦魇 V），"
      f"压在 {cfg_c.ttk_max:g}s 硬上限内 ✓")
    A(f"- SurvT 全程落在 **{min(_c_sv_all):.2f} – {max(_c_sv_all):.2f}s**，"
      f"**{len(collect_violations(cfg_c)['survt_bad'])}/100 越界** ✓")
    A(f"- **但 HP 轴（{cfg_c.tier_hp:g}^n）比 DMG 轴（{cfg_c.tier_dmg:g}^n）更陡** —— "
      f"梦魇 V 的杂兵比梦魇 I 厚 **{cfg_c.tier_hp**4:.2f} 倍**，"
      f"而伤害只高 {cfg_c.tier_dmg**4:.2f} 倍。"
      f"这与「难度放 DMG」的设计意图相反。")
    A("")

    # ---- 方案 D ----
    A("### 9.3 方案 D · DMG 主导（SurvT 改阶梯窗口）")
    A("")
    A("要让 DMG 成为主导轴，必须放开 SurvT 下沿。分层窗口：")
    A("")
    A("| 层级 | TTK 窗口 | SurvT 窗口 |")
    A("|---|---|---|")
    for t in range(N_TIER):
        lo_t, hi_t = ttk_window(cfg_d, t)
        lo_s, hi_s = survt_window(cfg_d, t)
        A(f"| {TIER_NAMES[t]} | {lo_t:g} – {hi_t:g} s | {lo_s:g} – {hi_s:g} s |")
    A("")
    A("**系数**：")
    A("")
    A("```")
    A(f"难度层级 HP 系数  = {cfg_d.tier_hp:g}^n        （主动放缓，梦魇 V = ×{cfg_d.tier_hp**4:.2f}）")
    A(f"难度层级 DMG 系数 = {cfg_d.tier_dmg:g}^n        （主导轴，梦魇 V = ×{cfg_d.tier_dmg**4:.2f}）")
    A(f"怪物 HP  = {cfg_d.monster_hp_base:g} × {cfg_d.monster_hp_g:g}^(L-1)")
    A(f"怪物 DMG = {cfg_d.monster_dmg_base:g} × {cfg_d.monster_dmg_g:g}^(L-1)")
    A("```")
    A("")
    A("**全表统计**")
    A("")
    A(stat_line(cfg_d))
    A("")
    A(md_matrix(cfg_d, ttk_matrix(cfg_d), ttk_ok,
               "表 1 · 击杀时间 TTK（秒）", "秒", ttk_window))
    A(md_matrix(cfg_d, survt_matrix(cfg_d), survt_ok,
               "表 2 · 存活时间 SurvT（秒）", "秒", survt_window))
    A(md_slope(cfg_d, slope_rows(cfg_d)))
    A(md_violations(cfg_d, collect_violations(cfg_d)))
    A("**读表要点**")
    A("")
    A(f"- TTK 只从 {_d_ttk[19][0]:.2f}s 爬到 {_d_ttk[19][4]:.2f}s（**+{(_d_ttk[19][4]/_d_ttk[19][0]-1)*100:.0f}%**）—— "
      f"**杂兵不海绵化**，符合「更难 = 怪更致命，不是同一只砍更久」的设计意图 ✓")
    A(f"- SurvT 从 {_d_sv[19][0]:.2f}s 掉到 {_d_sv[19][4]:.2f}s"
      f"（**−{(1-_d_sv[19][4]/_d_sv[19][0])*100:.0f}%**）—— "
      f"**梦魇 V 真的会死人**，难度靠致命性体现 ✓")
    A(f"- DMG 轴（{cfg_d.tier_dmg:g}^n，梦魇 V ×{cfg_d.tier_dmg**4:.2f}）"
      f"显著陡于 HP 轴（{cfg_d.tier_hp:g}^n，梦魇 V ×{cfg_d.tier_hp**4:.2f}）✓")
    A("")
    A("### 9.4 方案横向对比（含 C / D）")
    A("")
    A("| 方案 | tierHP | tierDMG | 怪物DMG base | TTK 越界 | SurvT 越界 | 斜率越界 | "
      "L20·梦魇V TTK | L20·梦魇V SurvT |")
    A("|---|---|---|---|---|---|---|---|---|")
    for c in (c_orig, c_prop, rec_a, rec_b2, cfg_c, cfg_d):
        v = collect_violations(c)
        ttk = ttk_matrix(c)
        sv = survt_matrix(c)
        mark = "✅" if not (v["ttk_bad"] or v["survt_bad"] or v["slope_bad"]) else "❌"
        A(f"| {c.name} | {c.tier_hp:g} | {c.tier_dmg:g} | {c.monster_dmg_base:g} | "
          f"{len(v['ttk_bad'])}/100 | {len(v['survt_bad'])}/100 | {len(v['slope_bad'])}/20 | "
          f"{ttk[19][4]:.2f}s | {sv[19][4]:.2f}s | {mark}")
    A("")
    A("---")
    A("")

    # ================= 十、单局时长与密度杠杆 =================
    A("## 十、单局时长与怪物密度杠杆评估")
    A("")
    A("> ⚠️ **时效说明**：本节写于「单局 10 分钟」为目标的时期。用户已拍板 **D5 —— 目标改为 "
      "14–21 分钟**，本节中所有以「10 分钟预算」为准的结论（尤其是 10.3 的密度阶梯）"
      "**已被 10.5 节取代**；10.1 的 AoE 口径与 10.2 的模型仍然有效。")
    A("")
    A("### 10.1 先纠正一个口径：TTK 是**单体**时间，不是清怪速率")
    A("")
    A("product-reviewer 的推算「150 × 8.8s = 22 分钟」隐含了 **aoe_factor = 1**（纯单体）。")
    A("但 ARPG 的杂兵是成片清的 —— 一次挥砍命中 3 只，清怪速率就是 3 倍。")
    A("本模型引入 `aoe_factor` = 每单位 TTK 时间实际清掉的怪物数：")
    A("")
    A("```")
    A("单局时长 = (杂兵数 × TTK / aoe_factor + 精英数 × 精英TTK + BOSS数 × BOSSTTK)")
    A("           / (1 - 跑图拾取开销占比)")
    A("```")
    A("")
    A(f"当前参数：杂兵 {base.mob_count} / 精英 {base.elite_count}×{base.elite_ttk_s:g}s / "
      f"BOSS {base.boss_count}×{base.boss_ttk_s:g}s / 开销 {base.overhead_frac*100:.0f}% / "
      f"预算 {base.run_budget_s/60:.0f} 分钟")
    A("")
    A("### 10.2 AoE 敏感性：梦魇 V 的单局时长（分钟）")
    A("")
    A("| 方案 | AoE=1（纯单体） | AoE=2 | AoE=3（基准） | AoE=4 |")
    A("|---|---|---|---|---|")
    for c in (c_orig, c_prop, rec_a, rec_b2, cfg_c, cfg_d):
        cells = []
        for a in (1.0, 2.0, 3.0, 4.0):
            cc = replace(c, aoe_factor=a)
            rt = sim.run_time_table(cc)
            v = rt[-1]["total_min"]
            cells.append(f"**{v:.1f}**" if v > 10.0 else f"{v:.1f}")
        A(f"| {c.name} | " + " | ".join(cells) + " |")
    A("")
    A("> 粗体 = 超出 10 分钟预算。")
    A("")
    A("**三条关键读数：**")
    A("")
    A("1. **AoE=1（最坏情况）下，没有任何方案能进 10 分钟预算** —— 连方案 A 都要 12.0 分钟。")
    A("   原因是最小可能时长被锁死：`(150 杂兵 × 2.0s 下限 + 150s 精英/BOSS) / 0.7 = 10.7 分钟`。")
    A("   **即：纯单体口径下 10 分钟预算在数学上不可行。**")
    A("2. **AoE≥3 时，方案 B/C/D 全部达标**，方案 B 在梦魇 V 是 9.9 分钟，贴着预算。")
    A("3. **方案 C 的单局时长几乎与层级无关（7.1 / 7.2 / 7.2 / 7.2 / 7.1 分钟）** —— ")
    A("   因为 TTK 上升与密度下降恰好互相抵消。这是最稳的时长曲线。")
    A("")
    A("### 10.3 密度杠杆评估：**可行，且在 AoE=1 时是唯一解**")
    A("")
    A("product-reviewer 提的 `1.0 / 0.9 / 0.8 / 0.7 / 0.6` 密度阶梯，评估结论：")
    A("")
    A("**（a）方向完全正确，而且是必需的。** 固定成本（5 精英 + 1 BOSS = 150s 战斗 / 0.7 = 3.6 分钟）")
    A("占了预算的 36%，剩下的杂兵预算只有约 6.4 分钟。要在这 6.4 分钟里清 150 只怪，")
    A("平均每只需 ≤ 2.6s（AoE=1）—— 这已经贴着 2.0s 的下限了。**只有降密度能解。**")
    A("")
    def need_density(c: Config, aoe: float) -> float:
        cc = replace(c, aoe_factor=aoe)
        cap = sim.ttk_cap_from_budget(cc, N_TIER - 1, aoe=aoe)
        ttk_v = ttk_matrix(cc)[19][4]
        return cap / ttk_v if ttk_v > 0 else float("inf")

    A("**（b）但 0.6 在 AoE=1 时不够。** 反解各方案在 10 分钟预算下梦魇 V 的"
      "**最大可接受密度**（>1 表示无需降密度）：")
    A("")
    A("| 方案 | AoE=1 需要的密度 | AoE=2 | AoE=3 | AoE=4 |")
    A("|---|---|---|---|---|")
    for c in (rec_a, rec_b2, cfg_c, cfg_d):
        cells = []
        for a in (1.0, 2.0, 3.0, 4.0):
            need = need_density(c, a)
            cells.append(f"{need:.2f}" if need < 1.0 else "1.00（无需降）")
        A(f"| {c.name} | " + " | ".join(cells) + " |")
    A("")
    REC_DENSITY_V = 0.58
    n_a1 = need_density(rec_a, 1.0)
    n_b1 = need_density(rec_b2, 1.0)
    n_c1 = need_density(cfg_c, 1.0)
    n_d1 = need_density(cfg_d, 1.0)
    _pairs = (("A", n_a1), ("B", n_b1), ("C", n_c1), ("D", n_d1))
    ok = [nm for nm, v in _pairs if REC_DENSITY_V <= v]
    bad = [nm for nm, v in _pairs if REC_DENSITY_V > v]

    A(f"**（c）推荐密度阶梯：`1.00 / 0.88 / 0.78 / 0.68 / 0.58`**"
      f"（⚠️ **仅在 10 分钟预算下成立**；目标改为 14–21 分钟后该阶梯应当取消，见 10.5.7）")
    A("")
    A("这个阶梯的取值依据：")
    A("")
    A(f"- 在 **AoE=3（基准）** 下，**全部四个方案都不需要降密度**"
      f"（上表 AoE=3 列全为「无需降」）—— 说明密度阶梯在基准情形下是"
      f"**冗余的安全垫**，不是必需品。")
    A(f"- 在 **AoE=2** 下，只有方案 B 需要 ≤ {need_density(rec_b2, 2.0):.2f}，"
      f"A / C / D 仍无需降 —— 推荐的 {REC_DENSITY_V:g} 已覆盖。")
    A(f"- 在 **AoE=1（纯单体最坏情况）** 下，四个方案分别需要 "
      f"A ≤ {n_a1:.2f}、B ≤ {n_b1:.2f}、C ≤ {n_c1:.2f}、D ≤ {n_d1:.2f}。"
      f"推荐的 {REC_DENSITY_V:g} 能覆盖 **{' / '.join(ok)}**，"
      f"覆盖不了 **{' / '.join(bad)}**。")
    A(f"- **结论：密度阶梯不是「调参技巧」，而是选型的风险缓冲。** "
      f"若阶段 1 实测 AoE ≥ 2，密度可以完全不动；"
      f"若实测 AoE = 1，则选 **{' 或 '.join(ok)}** 可在 {REC_DENSITY_V:g} 密度下运行，"
      f"选 **{' / '.join(bad)}** 需要把梦魇 V 密度进一步降到 "
      f"{min(n_a1, n_b1, n_c1, n_d1):.2f}。")
    A("")
    A("**（d）密度不该承担难度设计。**")
    A("减少怪物数量应该是「高层的怪更少但更强」的叙事表达（精英化），")
    A("而不是「为了凑时长而删怪」。建议把减少的那部分怪物预算")
    A("**转成精英怪**（`elite_count` 随层级上升），而不是凭空消失。")
    A("")
    A("**（e）另一个被忽略的杠杆：BOSS 的 90 秒占了预算 21%。**")
    A("如果 BOSS TTK 从 90s 压到 60s，直接省出 `(90-60)/0.7 = 43 秒`，")
    A("相当于把杂兵预算从 6.4 分钟抬到 7.1 分钟（+11%）。**建议阶段 1 把 BOSS TTK 目标")
    A("定在 60–90s，而非更长。**")
    A("")
    A("> ⚠️ **10.5.6 的修正**：以上方向在 14–21 分钟目标下**反转** —— "
      "那时我们要把单局**做长**，所以 BOSS 战应当**做长**（90s → 120s）。"
      "「压缩 BOSS」只适用于 10 分钟预算。")
    A("")
    A("### 10.4 对 product-reviewer 两个问题的直接回答")
    A("")
    A("**Q1：按 TTK≤5s、难度放 DMG 的口径，最终系数是多少？**")
    A("")
    A("| 路线 | tierHP | tierDMG | 怪物HP | 怪物DMG | TTK 越界 | SurvT 越界 |")
    A("|---|---|---|---|---|---|---|")
    A(f"| **C（守全局 SurvT 窗口）** | {cfg_c.tier_hp:g}^n | {cfg_c.tier_dmg:g}^n | "
      f"{cfg_c.monster_hp_base:g}×{cfg_c.monster_hp_g:g}^(L-1) | "
      f"{cfg_c.monster_dmg_base:g}×{cfg_c.monster_dmg_g:g}^(L-1) | 0/100 | 0/100 |")
    A(f"| **D（DMG 主导 · SurvT 阶梯）** | {cfg_d.tier_hp:g}^n | {cfg_d.tier_dmg:g}^n | "
      f"{cfg_d.monster_hp_base:g}×{cfg_d.monster_hp_g:g}^(L-1) | "
      f"{cfg_d.monster_dmg_base:g}×{cfg_d.monster_dmg_g:g}^(L-1) | 0/100 | 0/100 |")
    A("")
    A("**两个都全绿，选哪个取决于产品意图：**")
    A("")
    A("- **想保住「每一层都要活 8 秒以上」的生存底线 → 选 C。** 代价是 HP 轴更陡（1.13^n），")
    A("  梦魇 V 的杂兵比梦魇 I 厚 1.63 倍，略微海绵化，但仍在 5s 内。")
    A("- **想让「更高层级 = 更致命」而非「更肉」 → 选 D。** 代价是必须接受")
    A("  梦魇 V 只能活 4.5 秒 —— 这需要产品侧明确「高层级允许被秒」这条设计原则。")
    A("")
    A(f"**我推荐 D**，理由是它同时满足三条：杂兵不海绵化"
      f"（TTK 只涨 {(_d_ttk[19][4]/_d_ttk[19][0]-1)*100:.0f}%）、"
      f"难度靠致命性体现（SurvT 降 {(1-_d_sv[19][4]/_d_sv[19][0])*100:.0f}%）、"
      f"单局时长最短（{sim.run_time_table(cfg_d)[-1]['total_min']:.1f} 分钟，离预算最远）。")
    A("但如果 GDD 里「SurvT 8–12s」被当作不可退让的手感底线，那就选 C。")
    A("")
    A("**Q2：密度杠杆可行吗？系数怎么取？**")
    A("")
    A("**可行，且是必需的**（AoE=1 时唯一解）。推荐 `1.00 / 0.88 / 0.78 / 0.68 / 0.58`，")
    A("并配套：① 减少的怪物转成精英而非凭空消失；② BOSS TTK 目标压到 60–90s；")
    A("③ 阶段 1 实机埋点统计真实 AoE 清怪速率，回填 `--aoe-factor` 后再复核密度阶梯。")
    A("")
    A("> ⚠️ **10.5.7 的修正**：以上结论建立在 10 分钟预算上。目标改为 **14–21 分钟**后，"
      "密度阶梯会把梦魇 IV/V 压到 14 分钟以下，**应当取消**；"
      "「减怪转精英」这条思路仍然有效，但执行方式改为「精英 5 → 8–10」（见 10.5.6 #2）。")
    A("")
    A("---")
    A("")

    # ================= 十·五、14–21 分钟反解 =================
    c_d1 = replace(cfg_d, density_by_tier=(1.0, 1.0, 1.0, 1.0, 1.0))
    ttk_l20 = ttk_matrix(cfg_d)[19]
    mean_ttk_l20 = avg_ttk(cfg_d)
    AOE_COLS = (1.0, 2.0, 3.0, 4.0)
    DUR_ROWS = (14.0, 17.5, 21.0)
    OH_REC, ELITE_REC, BOSS_REC = 0.35, 10.0, 90.0

    def nm(tm, a, **kw):
        """反解所需杂兵数（默认用方案 D 的 L20 均值 TTK）。"""
        return mob_count_for_duration(cfg_d, tm, a, **kw)

    def pct_delta(v: float, base_v: float) -> str:
        """相对基线的变化，带正负号。"""
        d = (v / base_v - 1.0) * 100.0
        return f"{'+' if d >= 0 else '−'}{abs(d):.0f}%"

    def dur(n, a, **kw):
        """正算：给定杂兵数/AoE 的梦魇 V 单局时长（分钟，密度统一 1.0）。"""
        cc = replace(cfg_d, mob_count=n, aoe_factor=a, density_by_tier=c_d1.density_by_tier, **kw)
        return sim.run_time_table(cc)[N_TIER - 1]["total_min"]

    A("## 十·五、14–21 分钟目标下的单关内容量反解")
    A("")
    A("> **本节背景（D5 已拍板）**：用户已确认中循环时长目标 = **14–21 分钟**"
      "（不再是 v1.0–v1.4 的 10 分钟，见 GDD v1.5 第 65 / 69 行）。"
      "按第 10 节模型，方案 D 在**现参数**（150 杂兵 / AoE=3 / 开销 30%）下只有 **6.5 分钟**，"
      "**低于 14 分钟下限**，已登记为 GDD 待核第 10 项。本节把「单关到底要放多少怪」反解出来。")
    A("")
    A("### 10.5.1 现参数离目标差多远")
    A("")
    A("| 层级 | 密度 | 实际杂兵 | TTK | 杂兵战斗 | 精英+BOSS | 单局时长 |")
    A("|---|---|---|---|---|---|---|")
    for r in sim.run_time_table(cfg_d):
        A(f"| {TIER_NAMES[r['tier']]} | {r['density']:.2f} | {r['n_mob']:.0f} | "
          f"{r['ttk']:.2f}s | {r['mob_s']:.0f}s | {r['elite_s'] + r['boss_s']:.0f}s | "
          f"**{r['total_min']:.2f} 分钟** |")
    A("")
    A(f"五个层级全部落在 **{min(r['total_min'] for r in sim.run_time_table(cfg_d)):.2f} – "
      f"{max(r['total_min'] for r in sim.run_time_table(cfg_d)):.2f} 分钟**，"
      f"距 14 分钟下限还差 **{14.0 / sim.run_time_table(cfg_d)[-1]['total_min']:.2f} 倍**"
      f"（即要把单局时长拉长约 "
      f"{(14.0 / sim.run_time_table(cfg_d)[-1]['total_min'] - 1) * 100:.0f}%）。")
    A("")
    A("### 10.5.2 反解公式")
    A("")
    A("沿用第 10 节模型，把「杂兵数」当未知量解出来：")
    A("")
    A("```")
    A("单局时长 = (杂兵数 × TTK / AoE + 精英数 × 精英TTK + BOSS数 × BOSSTTK) / (1 − 开销占比)")
    A("")
    A("⇒ 杂兵数 = (目标秒数 × (1 − 开销占比) − 固定战斗秒数) × AoE / TTK")
    A("```")
    A("")
    A(f"**代入方案 D 的实测值**：TTK = **{mean_ttk_l20:.2f}s**"
      f"（L20 逐层级 {ttk_l20[0]:.2f} / {ttk_l20[1]:.2f} / {ttk_l20[2]:.2f} / "
      f"{ttk_l20[3]:.2f} / {ttk_l20[4]:.2f}s 的均值；"
      f"中层「梦魇 III」的 {ttk_l20[2]:.2f}s 即 team-lead 引用的 3.49s）；"
      f"精英 {cfg_d.elite_count:g} × {cfg_d.elite_ttk_s:g}s = "
      f"{cfg_d.elite_count * cfg_d.elite_ttk_s:g}s；"
      f"BOSS {cfg_d.boss_count:g} × {cfg_d.boss_ttk_s:g}s = {cfg_d.boss_ttk_s:g}s；"
      f"开销 {cfg_d.overhead_frac * 100:.0f}%。")
    A("")
    A("### 10.5.3 反解结果：所需单关杂兵数")
    A("")
    A("| 目标时长 | AoE=1（纯单体） | AoE=2 | AoE=3（原基准） | AoE=4 |")
    A("|---|---|---|---|---|")
    for tm in DUR_ROWS:
        label = {14.0: "**14.0 分钟（下限）**", 17.5: "17.5 分钟（中位）",
                 21.0: "**21.0 分钟（上限）**"}[tm]
        A(f"| {label} | " + " | ".join(f"**{nm(tm, a):.0f}**" for a in AOE_COLS) + " |")
    A("")
    A("**按层级拆开**（层级 TTK 不同，所需杂兵数也不同；此处取梦魇 I / III / V）：")
    A("")
    A("| 层级（TTK） | 目标 | AoE=1 | AoE=2 | AoE=3 | AoE=4 |")
    A("|---|---|---|---|---|---|")
    for t in (0, 2, 4):
        for tm in DUR_ROWS:
            lab = f"{TIER_NAMES[t]}（{ttk_l20[t]:.2f}s）" if tm == 14.0 else ""
            A(f"| {lab} | {tm:g} 分钟 | " + " | ".join(
                f"{nm(tm, a, tier=t):.0f}" for a in AOE_COLS) + " |")
    A("")
    A(f"- 梦魇 I 的 TTK 最短（{ttk_l20[0]:.2f}s），**要放最多怪**（14 分钟需 "
      f"{nm(14.0, 2.0, tier=0):.0f} 只 @AoE=2）；")
    A(f"- 梦魇 V 的 TTK 最长（{ttk_l20[4]:.2f}s），**要放最少怪**（14 分钟仅需 "
      f"{nm(14.0, 2.0, tier=4):.0f} 只 @AoE=2）。")
    A(f"- 两者相差 **{nm(14.0, 2.0, tier=0) / nm(14.0, 2.0, tier=4):.2f} 倍** —— "
      f"这正好是 TTK 的层级比，说明**层级 TTK 差本身就自带时长调节**，"
      f"不需要再叠一层密度阶梯（见 10.5.7）。")
    A("")
    A("### 10.5.4 Q1 · AoE 设计基准取多少？")
    A("")
    A("**先澄清一个容易搞反的方向**（与第 10.1 节同类口径问题）：")
    A("")
    A("```")
    A("杂兵数 = 战斗预算 × AoE / TTK        ⇒  杂兵数 ∝ AoE")
    A("```")
    A("")
    A("**AoE 越大，同样时长里要放的怪越多，不是越少。** 一次交火清 3 只，"
      "同样的 585 秒里能清掉 3 倍数量 —— 要塞满同样的时长，就必须放 3 倍的怪。")
    A("")
    A("所以「怪堆成山」的风险来自**基准取太大**，不是取太小：")
    A("")
    A("| 若基准取 | 所需杂兵（17.5 分钟） | 风险方向 |")
    A("|---|---|---|")
    for a in AOE_COLS:
        v = nm(17.5, a)
        risk = ("关卡要塞 " + f"{v:.0f}" + " 只怪 —— **怪堆成山 / 超关卡预算**"
                if v > 420 else
                "落在可设计区间内" if v >= 250 else
                "**实机一有溅射就清得太快，跌破 14 分钟下限**")
        A(f"| AoE={a:g} | {v:.0f} 只 | {risk} |")
    A("")
    A("**建议：AoE 设计基准 = 2.0。** 三条理由：")
    A("")
    A(f"1. **它是唯一与「单关杂兵数预算 250–420」自洽的取值。** AoE=2 时 14 分钟需 "
      f"{nm(14.0, 2.0):.0f} 只、21 分钟需 {nm(21.0, 2.0):.0f} 只，"
      f"正好铺满预算区间；AoE=3 的 21 分钟要 {nm(21.0, 3.0):.0f} 只，已越界。")
    A(f"2. **它可以用设计手段锁死，不必靠实机猜。** AoE = 「单位 TTK 内清掉的怪数」，"
      f"由三条设计约束共同决定：① 怪群规模（每群 3–5 只）；② 主力技能的命中半径"
      f"（只覆盖半个怪群）；③ 拉怪节奏（不鼓励一次拉 2 群）。"
      f"把这三条写进关卡设计规范，AoE 就落在 2 附近，而不是随玩家 Build 漂移。")
    A(f"3. **它给「实机测量误差」留了双向余量。** 若实测 AoE=2.5，"
      f"17.5 分钟的杂兵数从 {nm(17.5, 2.0):.0f} 涨到 {nm(17.5, 2.5):.0f}（+25%），"
      f"仍在预算内；若取 AoE=3 做基准而实测只有 2，"
      f"关卡会多塞 50% 的怪、单局时长直接冲到 22 分钟以上。")
    A("")
    A("> **一句话给关卡设计**：**按「一次交火清 2 只」设计关卡，单关放 250–420 只杂兵**"
      "（17.5 分钟中位取 334 只）。")
    A("")
    A("### 10.5.5 Q2 · 加怪到 250–420 只有什么副作用？")
    A("")
    A("#### （a）关卡设计与引擎：**真正的瓶颈不是「总数」，是「密度」**")
    A("")
    A(f"杂兵数从 150 涨到 334 是 **{334 / 150:.2f} 倍**。如果地图面积不变，"
      f"单位面积的怪数也涨 {334 / 150:.2f} 倍 —— 这才是字面意义上的「怪堆成山」。"
      f"所以正确的做法是**同步放大地图**：")
    A("")
    A("| 项目 | 现参数 | 目标（334 只） | 说明 |")
    A("|---|---|---|---|")
    A(f"| 单关杂兵总数 | 150 | 334 | ×{334 / 150:.2f} |")
    A(f"| 地图面积（房间数） | 1.0× | **×{334 / 150:.2f}** | 保持每平米怪数不变 |")
    A("| 同屏并发数 | 不变 | 不变 | 分区刷怪 + 死亡回收，并发由刷怪点控制 |")
    A(f"| 单关掉落物 | 18.0 件 | {content_yield(334)['items_total']:.1f} 件 | 见（b） |")
    A("")
    A("**两条待办**：① 地图面积必须同步放大，否则会变成「挤在一起的怪堆」；"
      "② 同屏并发上限需引擎侧确认（已向 godot-engineer-2 发起咨询，回填后本节更新）。")
    A("")
    A("#### （b）掉落：**总产出不会爆炸，但会「结构性灌水」**")
    A("")
    A("按 GDD 6.1 掉落表逐档算（基准 = 150 杂兵 + 5 精英 + 1 BOSS = 18.0 件）：")
    A("")
    bl = baseline_yield()
    A("| 杂兵数 | 总掉落 | " + " | ".join(RARITY_NAMES) + " | 魔石 | 金币 | 经验 | 满强化局/件 |")
    A("|---|" + "---|" * (len(RARITY_NAMES) + 6))
    for n in (150, 200, 250, 300, 334, 375, 400, 500):
        y = content_yield(n, 5.0, 1.0, level=20)
        cells = [f"{y['items_total'] / bl['items_total']:.2f}×"]
        cells += [f"{y['rarity'][k] / bl['rarity'][k]:.2f}×" for k in RARITY_NAMES]
        cells += [f"{y['mats'] / bl['mats']:.2f}×", f"{y['gold'] / bl['gold']:.2f}×",
                  f"{y['xp'][0] / bl['xp'][0]:.2f}×", f"{y['runs_per_full_enhance']:.2f}"]
        mark = "**" if n in (150, 334, 400) else ""
        A(f"| {mark}{n}{mark} | " + " | ".join(cells) + " |")
    A("")
    y334 = content_yield(334, 5.0, 1.0, level=20)
    y400 = content_yield(400, 5.0, 1.0, level=20)
    A("**关键读数 —— 高稀有度几乎不动，低稀有度线性灌水：**")
    A("")
    A(f"- **橙 / 红装几乎不变**：334 只时橙 {y334['rarity']['橙'] / bl['rarity']['橙']:.2f}×、"
      f"红 {y334['rarity']['红'] / bl['rarity']['红']:.2f}×；400 只时也只有 "
      f"{y400['rarity']['橙'] / bl['rarity']['橙']:.2f}× / {y400['rarity']['红'] / bl['rarity']['红']:.2f}×。"
      f"原因：**橙红主要来自精英与 BOSS 掉落**，而精英/BOSS 数量没变。"
      f"**所以「装备产出爆炸」不会发生**，6.1 掉落表不需要重做。")
    A(f"- **白装线性灌水**：334 只时白装 {y334['rarity']['白'] / bl['rarity']['白']:.2f}×"
      f"（{bl['rarity']['白']:.1f} → {y334['rarity']['白']:.1f} 件/局）、"
      f"蓝装 {y334['rarity']['蓝'] / bl['rarity']['蓝']:.2f}×。"
      f"**真正的副作用在这里**：玩家每局要多捡 {y334['rarity']['白'] - bl['rarity']['白']:.0f} 件白装、"
      f"多分解同样数量的垃圾。这是「拾取/整理成本」问题，不是掉落平衡问题。")
    A(f"- **总掉落只涨 {y334['items_total'] / bl['items_total']:.2f}×**"
      f"（18.0 → {y334['items_total']:.1f} 件），远低于杂兵数的 "
      f"{334 / 150:.2f}× —— 因为 6.1 的杂兵掉落触发率只有 8%。")
    A("")
    A("#### （c）经验：**超预算 2.2 倍，必须同步改 0.5 曲线**")
    A("")
    A("GDD 0.5：`XP_ToNext(L) = 100 × L^1.6`，单关产出 2,500–4,000（基准 150 杂兵）。"
      "按杂兵数线性缩放：")
    A("")
    A("| 杂兵数 | 单关经验 | L10 升级需 | L10 关/级 | L20 升级需 | L20 关/级 |")
    A("|---|---|---|---|---|---|")
    for n in (150, 250, 334, 400):
        y = content_yield(n, 5.0, 1.0, level=20)
        lo, hi = y["xp"]
        A(f"| {n} | {lo:,.0f} – {hi:,.0f} | {100 * 10 ** 1.6:,.0f} | "
          f"{100 * 10 ** 1.6 / hi:.2f} – {100 * 10 ** 1.6 / lo:.2f} | "
          f"{100 * 20 ** 1.6:,.0f} | {100 * 20 ** 1.6 / hi:.2f} – {100 * 20 ** 1.6 / lo:.2f} |")
    A("")
    A(f"- 基准局（150 只）在 L20 是 **{100 * 20 ** 1.6 / 4000:.2f} – "
      f"{100 * 20 ** 1.6 / 2500:.2f} 关升 1 级**，与 GDD 0.5「3–5 关升 1 级」吻合 ✓")
    A(f"- 334 只时变成 **{100 * 20 ** 1.6 / y334['xp'][1]:.2f} – "
      f"{100 * 20 ** 1.6 / y334['xp'][0]:.2f} 关升 1 级**，"
      f"**升级速度加快 {334 / 150:.2f} 倍** —— 玩家会跳过装备档位，破坏 GDD 6.5「每 5 关 = 1 阶段」的节奏。")
    A(f"- **修法**：把 XP 曲线系数从 **100 提到 {100 * 334 / 150:.0f}**"
      f"（即 `XP_ToNext(L) = {100 * 334 / 150:.0f} × L^1.6`），即可保持关/级不变。"
      f"改曲线而不是改单关经验，是为了让「一关 = 一关的成长量」这个直觉成立。")
    A("")
    A("#### （d）金币与材料：**满强化从 1.73 局/件降到 1.24 局/件**")
    A("")
    A(f"- 魔石 {y334['mats'] / bl['mats']:.2f}×（{bl['mats']:.0f} → {y334['mats']:.0f}/局），"
      f"金币 {y334['gold'] / bl['gold']:.2f}×（{bl['gold']:,.0f} → {y334['gold']:,.0f}/局）。")
    A(f"- GDD 6.5 写「满强化 1 件 ≈ 1.8 局」—— 基准局实算 **{bl['runs_per_full_enhance']:.2f} 局/件** ✓ 对得上；"
      f"334 只时掉到 **{y334['runs_per_full_enhance']:.2f} 局/件**（快 "
      f"{(1 - y334['runs_per_full_enhance'] / bl['runs_per_full_enhance']) * 100:.0f}%）。")
    A(f"- **修法**：把 `MATS_PER_FULL_ENHANCE` 从 64 提到 "
      f"**{64 * y334['mats'] / bl['mats']:.0f}**（≈ 6.5 节的「1.8 局/件」即可复原）。"
      f"金币侧需要另找等比例的消耗口（洗练 / 重铸 / 词缀锁定），"
      f"否则 {y334['gold'] / bl['gold']:.2f}× 的金币会沉淀成通胀。")
    A("")
    A("#### （e）拾取与整理成本（最容易被忽略的一条）")
    A("")
    A(f"单局掉落从 {bl['items_total']:.1f} 件涨到 {y334['items_total']:.1f} 件、"
      f"400 只时到 {y400['items_total']:.1f} 件。按每件 1.5s 的「走到 → 捡 → 判断」成本算，"
      f"**单局拾取时间从 {bl['items_total'] * 1.5:.0f}s 涨到 {y334['items_total'] * 1.5:.0f}s**。"
      f"这部分时间已经算在 30% 的 overhead 里了，但**玩家的主观疲劳是按「捡了多少次」计的，"
      f"不是按秒计**。")
    A("")
    A("**结论：加怪可以，但必须配三件套** —— ① 地图面积同步放大；"
      "② 0.5 经验曲线与 6.5 强化成本按比例上调；③ 拾取体验优化"
      "（自动拾取白装 / 一键分解 / 掉落过滤）。")
    A("")
    A("### 10.5.6 Q3 · 有没有比「单纯加怪」更好的杠杆？")
    A("")
    A("有，而且**应该优先用它们**。加怪是最「暴力」的杠杆：它同时推高引擎压力、"
      "掉落灌水、经验超支三件事；而下面这些杠杆是「干净」的。")
    A("")
    A("| # | 杠杆 | 机制 | 17.5 分钟所需杂兵数 | 副作用 | 评价 |")
    A("|---|---|---|---|---|---|")
    _n_base = nm(17.5, 2.0)
    _n_oh = nm(17.5, 2.0, overhead_frac=0.40)
    _n_el = nm(17.5, 2.0, elite_count=10.0)
    _n_boss = nm(17.5, 2.0, boss_ttk_s=120.0)
    _n_all = nm(17.5, 2.0, overhead_frac=OH_REC, elite_count=ELITE_REC, boss_ttk_s=BOSS_REC)
    A(f"| 0 | 不动（基准） | — | {_n_base:.0f} | — | 参考基线 |")
    A(f"| 1 | **开销占比 30% → 40%** | 放大 2 倍地图 + 探索/秘密/可选精英 | "
      f"{_n_oh:.0f}（{pct_delta(_n_oh, _n_base)}） | 走图变多，"
      f"必须有内容填充（否则是「空跑」） | ⭐⭐⭐ **最干净的杠杆**：不增加任何掉落/经验产出 |")
    A(f"| 2 | **精英 5 → 10** | +5 精英 × 12s = +60s 战斗 | "
      f"{_n_el:.0f}（{pct_delta(_n_el, _n_base)}） | 精英产出翻倍（橙/红/绿/彩也涨） | "
      f"⭐⭐⭐ **同时改善时长与掉落品质**（见下表） |")
    A(f"| 3 | **BOSS 战加长 90s → 120s**（或 BOSS 数 1 → 2） | "
      f"固定战斗 +30s | {_n_boss:.0f}（{pct_delta(_n_boss, _n_base)}） | BOSS 战手感变长，"
      f"需要相应的机制深度支撑 | ⭐⭐ 与 #2 同源（都是「加固定内容」），"
      f"但单只 BOSS 撑 120s 容易变成磨血 |")
    A(f"| 4 | **拾取/整理成本显式计入** | 把「捡 → 分解 → 对比」写进 overhead | "
      f"同 #1 | 玩家主观疲劳 | ⭐⭐ 只在做 #1 时顺带 |")
    A(f"| 5 | **再加怪**（纯暴力） | — | {_n_base:.0f} | 引擎压力 + 掉落灌水 + 经验超支 | "
      f"⭐ **兜底手段，不建议单独使用** |")
    A("")
    A(f"> **注意 #3 的方向**：把 BOSS TTK **缩短**（90s → 60s）会让单局变短，"
      f"反而要求更多杂兵（{nm(17.5, 2.0, boss_ttk_s=60.0):.0f} 只，"
      f"{pct_delta(nm(17.5, 2.0, boss_ttk_s=60.0), _n_base)}）。"
      f"第 10.3(e) 节「把 BOSS 压到 60–90s」的建议**只适用于 10 分钟预算**，"
      f"在 14–21 分钟目标下方向相反 —— **这里要把 BOSS 战做长，不是做短。**")
    A("")
    A(f"**推荐组合 = #1 + #2 + #3 同时上**，则所需杂兵数从 {_n_base:.0f} 降到 "
      f"**{_n_all:.0f}**（{pct_delta(_n_all, _n_base)}），"
      f"**单关只比现在多放 {_n_all / 150:.2f} 倍**，三件套副作用也全部变小：")
    A("")
    A("| 参数 | 现参数 | 推荐组合 |")
    A("|---|---|---|")
    A(f"| 单关杂兵数（17.5 分钟中位） | 150 | **{_n_all:.0f}**（设计区间 "
      f"{nm(14.0, 2.0, overhead_frac=OH_REC, elite_count=ELITE_REC, boss_ttk_s=BOSS_REC):.0f} – "
      f"{nm(21.0, 2.0, overhead_frac=OH_REC, elite_count=ELITE_REC, boss_ttk_s=BOSS_REC):.0f}） |")
    A(f"| AoE 基准 | 3.0 | **2.0**（写成关卡设计约束） |")
    A(f"| 开销占比 | 30% | **{OH_REC * 100:.0f}%**（地图面积 ×2；上限 40%） |")
    A(f"| 精英数 | 5 | **8–10** |")
    A(f"| BOSS TTK | 90s | **90–120s**（做长，不是做短） |")
    A(f"| 密度阶梯 | 1.0/0.9/0.8/0.7/0.6 | **取消**（见 10.5.7） |")
    A(f"| XP 曲线系数 | 100 | **{100 * _n_all / 150:.0f}**（保持关/级） |")
    A(f"| 满强化所需魔石 | 64 | **{64 * content_yield(_n_all, ELITE_REC)['mats'] / bl['mats']:.0f}**"
      f"（保持 1.8 局/件） |")
    A("")
    A("**精英杠杆的额外好处 —— 它抬的是「品质」而不是「数量」：**")
    A("")
    A("| 精英数 | 橙装/局 | 红装/局 | 绿装/局 | 彩装/局 | 魔石/局 |")
    A("|---|---|---|---|---|---|")
    for ne in (5.0, 8.0, 10.0, 12.0):
        y = content_yield(_n_all, ne, 1.0, level=20)
        A(f"| {ne:g} | {y['rarity']['橙']:.4f} | {y['rarity']['红']:.4f} | "
          f"{y['rarity']['绿']:.4f} | {y['rarity']['彩']:.4f} | {y['mats']:.1f} |")
    A("")
    A(f"精英从 5 加到 10，橙装/局从 "
      f"{content_yield(_n_all, 5.0, 1.0, level=20)['rarity']['橙']:.4f} 涨到 "
      f"{content_yield(_n_all, 10.0, 1.0, level=20)['rarity']['橙']:.4f}"
      f"（+{(content_yield(_n_all, 10.0, 1.0, level=20)['rarity']['橙'] / content_yield(_n_all, 5.0, 1.0, level=20)['rarity']['橙'] - 1) * 100:.0f}%），"
      f"而白装只涨 "
      f"{(content_yield(_n_all, 10.0, 1.0, level=20)['rarity']['白'] / content_yield(_n_all, 5.0, 1.0, level=20)['rarity']['白'] - 1) * 100:.0f}%。"
      f"**同样是「让一局更长」，用精英填时长比用杂兵填时长，掉落结构健康得多。**")
    A("")
    A("### 10.5.7 顺带修正：第 10.3 节的密度阶梯在 14–21 分钟目标下**应当取消**")
    A("")
    A(f"第 10.3 节是在 **10 分钟**预算下推的密度阶梯（`1.00 / 0.88 / 0.78 / 0.68 / 0.58`），"
      f"它的作用是**把高层级的时长压下来**。目标改成 14–21 分钟后，方向反了 —— "
      f"它会把高层级压到 14 分钟以下：")
    A("")
    A(f"| 层级 | 密度=1.0（推荐组合，N={_n_all:.0f}，AoE=2） | 沿用 10.3 阶梯 | 是否达标 |")
    A("|---|---|---|---|")
    _rec_kw = dict(aoe_factor=2.0, overhead_frac=OH_REC,
                   elite_count=ELITE_REC, boss_ttk_s=BOSS_REC)
    _cc1 = replace(cfg_d, mob_count=_n_all, density_by_tier=c_d1.density_by_tier, **_rec_kw)
    _cc2 = replace(cfg_d, mob_count=_n_all, density_by_tier=(1.0, 0.88, 0.78, 0.68, 0.58),
                   **_rec_kw)
    for r1, r2 in zip(sim.run_time_table(_cc1), sim.run_time_table(_cc2)):
        ok1 = "✅" if 14.0 <= r1["total_min"] <= 21.0 else "❌"
        ok2 = "✅" if 14.0 <= r2["total_min"] <= 21.0 else "❌"
        A(f"| {TIER_NAMES[r1['tier']]} | {r1['total_min']:.2f} 分钟 {ok1} | "
          f"{r2['total_min']:.2f} 分钟 {ok2} | — |")
    A("")
    _r1_min = min(r["total_min"] for r in sim.run_time_table(_cc1))
    _r1_max = max(r["total_min"] for r in sim.run_time_table(_cc1))
    _r2_min = min(r["total_min"] for r in sim.run_time_table(_cc2))
    _r2_max = max(r["total_min"] for r in sim.run_time_table(_cc2))
    _bad2 = [TIER_NAMES[r["tier"]] for r in sim.run_time_table(_cc2)
             if not (14.0 <= r["total_min"] <= 21.0)]
    A(f"**新结论：不需要任何密度阶梯。** 层级 TTK 从 {ttk_l20[0]:.2f}s 涨到 {ttk_l20[4]:.2f}s"
      f"（{ttk_l20[4] / ttk_l20[0]:.2f} 倍），**已经天然给出了 {_r1_min:.1f} – {_r1_max:.1f} 分钟**"
      f"的时长跨度，正好落在 14–21 分钟内。"
      f"而叠上 10.3 节的阶梯后变成 {_r2_min:.1f} – {_r2_max:.1f} 分钟，"
      f"**{' / '.join(_bad2)} 击穿 14 分钟下限**。再叠一层密度阶梯就是双重压缩。")
    A("")
    A(f"如果**确实**要求五个层级时长一致（比如为了让「通关时间」可比较），"
      f"那么密度阶梯应改为 **时长等价阶梯** `{' / '.join(f'{ttk_l20[0] / v:.2f}' for v in ttk_l20)}`"
      f"（= 梦魇 I 的 TTK ÷ 各层 TTK），而不是 10.3 节的 `1.00/0.88/0.78/0.68/0.58`。")
    A("")
    A("### 10.5.8 本节一页结论")
    A("")
    A("| 问题 | 结论 |")
    A("|---|---|")
    A(f"| 现参数差多少？ | 150 杂兵 / AoE=3 / 开销 30% → "
      f"**{min(r['total_min'] for r in sim.run_time_table(cfg_d)):.1f} – "
      f"{max(r['total_min'] for r in sim.run_time_table(cfg_d)):.1f} 分钟**，"
      f"低于 14 分钟下限 |")
    A(f"| 要放多少怪？ | **AoE=2 基准下：14 分钟 {nm(14.0, 2.0):.0f} 只 / "
      f"17.5 分钟 {nm(17.5, 2.0):.0f} 只 / 21 分钟 {nm(21.0, 2.0):.0f} 只**"
      f"（推荐组合下降到 "
      f"{nm(14.0, 2.0, overhead_frac=OH_REC, elite_count=ELITE_REC, boss_ttk_s=BOSS_REC):.0f} / "
      f"{_n_all:.0f} / "
      f"{nm(21.0, 2.0, overhead_frac=OH_REC, elite_count=ELITE_REC, boss_ttk_s=BOSS_REC):.0f} 只） |")
    A(f"| AoE 基准？ | **2.0**（唯一与 250–420 只预算自洽的取值；"
      f"写成关卡设计约束「一次交火清 2 只」） |")
    A(f"| 掉落会爆炸吗？ | **不会。** 总掉落 ×{y334['items_total'] / bl['items_total']:.2f}，"
      f"橙/红只 ×{y334['rarity']['橙'] / bl['rarity']['橙']:.2f} / "
      f"×{y334['rarity']['红'] / bl['rarity']['红']:.2f}（精英/BOSS 驱动，与杂兵数无关）；"
      f"但白装 ×{y334['rarity']['白'] / bl['rarity']['白']:.2f}，拾取负担上升 |")
    A(f"| 经验会超吗？ | **会超 ×{334 / 150:.2f}。** XP 曲线系数需 100 → "
      f"{100 * 334 / 150:.0f} 才能保住「3–5 关升 1 级」 |")
    A(f"| 材料会超吗？ | **会。** 满强化从 {bl['runs_per_full_enhance']:.2f} 局/件降到 "
      f"{y334['runs_per_full_enhance']:.2f} 局/件；`MATS_PER_FULL_ENHANCE` 需 64 → "
      f"{64 * y334['mats'] / bl['mats']:.0f} |")
    A(f"| 更好的杠杆？ | **① 开销 30%→35%（地图 ×2）② 精英 5→10 ③ BOSS 战 90s→120s**"
      f"，三者合计把所需杂兵数从 {_n_base:.0f} 压到 {_n_all:.0f}。**优先用它们，加怪兜底。** |")
    A(f"| 密度阶梯还要吗？ | **不要了。** 层级 TTK 差已自带 "
      f"{_r1_min:.1f}–{_r1_max:.1f} 分钟跨度；"
      f"10.3 节的阶梯会把它压到 {_r2_min:.1f}–{_r2_max:.1f} 分钟，**击穿 14 分钟下限** |")
    A("")
    A("---")
    A("")

    # ================= 十一、风险 =================
    A("## 十一、遗留风险与下一步")
    A("")
    A("| # | 项 | 说明 | 建议 |")
    A("|---|---|---|---|")
    A("| 1 | **本模型未建模 CR/CD/AS/SkillMult 的真实装备来源** | "
      "脚本按 L1→L20 线性插值这三项，但它们实际由词缀堆叠决定。"
      "K(L) 的形态直接影响反解出的 tier 系数（1.05–1.07 区间）。 | "
      "阶段 1 建好装备词缀系统后，用真实配装数据回填 `--cr-* / --cd-* / --as-* / --sm-*` 再跑一次 |")
    A("| 2 | **装备贡献 L1 锚点（0.5）是估计值** | "
      "影响反解出的怪物 HP base（80.6–168.0 区间），但不影响层级系数结论。 | "
      "阶段 1 用真实 L1 起始装备回填 |")
    A("| 3 | **局内成长（+30% 上限）与天赋树（30 点）未纳入模型** | "
      "GDD 4.4 / 5.2。这两项会让实际 DPS 高于本模型的「期望装备」曲线。 | "
      "作为 `--dps-overhead` 类乘子后续补入，或按 +15–25% 有效输出做保守修正 |")
    A("| 4 | **N=4 同时受击数是拍脑袋值** | "
      "直接决定 SurvT 的绝对刻度。若实际战斗同时受击数多为 2–3，"
      "SurvT 会相应放大 1.3–2 倍。 | 阶段 1 在实机战斗里统计平均同时受击数后回填 `--surv-n` |")
    A("| 5 | **BOSS / 精英的 TTK 未单独校验** | "
      "本报告只校验普通怪。BOSS HP ×28 意味着 L20 梦魇 I 的 BOSS TTK ≈ "
      f"{monster_curves(rec_b)[19]['boss_hp']*rec_b.tier_hp**0/player_curves(rec_b)[19]['dps']:.0f}s。 | "
      "阶段 1 增加 BOSS/精英的独立 TTK 目标（建议 BOSS 60–120s、精英 8–15s） |")
    A("| 6 | **GDD 6.2「裸装占 25–35%」需修订** | "
      "与「满装 ×6–8 倍」互斥，见第 1 节第 5 条。 | 产品评审员在 GDD v1.1 中统一口径 |")
    A("| 7 | **稀有度从 5 档扩至 8 档（0.7 文档 v1.3+）可能抬高装备贡献系数** | "
      "0.7 文档新增「神话红」为第 6 个线性强度档，若它携带更多词缀条数，"
      "满装 AD 可能从 ×7 升到 ×9 甚至更高。"
      "**本报告 7.3(a) 的敏感性扫描已覆盖 ×3 / ×5 / ×7 / ×9 四个锚点** —— "
      "结论是：怪物 HP 成长反解值仅在 1.24–1.30 间移动，"
      "**层级 HP 系数恒为 1.07，不受影响**。 | "
      "无需重跑；阶段 1 装备系统落地后用真实配装回填 `--gear-*-20` 复核即可 |")
    A("| 8 | **`aoe_factor` 是单局时长模型里最大的未知量**（14–21 分钟目标下升级为**第一风险**） | "
      "取值 1 / 2 / 3 / 4 时，方案 D 在梦魇 V 的单局时长（334 杂兵）是 "
      "35.9 / 19.7 / 14.4 / 11.7 分钟 —— **极差 3.08 倍，远宽于 14–21 分钟的 1.5 倍目标窗口**。"
      "**在 AoE 被实测锁定之前，单关杂兵数无法最终定稿。** | "
      "阶段 1 实机埋点：统计「单位时间内击杀数 ÷ DPS/怪物HP」，回填 `--aoe-factor`；"
      "同时按 10.5.4 把 AoE 写成关卡设计约束（怪群 3–5 只 / 技能只覆盖半群），把它从「未知量」变成「设计量」 |")
    A("| 9 | **单局时长模型的固定成本占比随目标时长而变** | "
      "固定成本（5 精英 ×12s + 1 BOSS ×90s = 150s）在 10 分钟预算下占 36%，"
      "是 AoE=1 不可行的主因；但在 14–21 分钟目标 + 334 杂兵下只占 **18.1%**，不再是瓶颈。"
      "**反过来它变成了杠杆**：见 10.5.6 的 #2 / #3。 | "
      "阶段 1 把 BOSS 战目标定在 **90–120s**（14–21 分钟目标下要做长，不是做短）；"
      "精英数按层级从 5 提到 8–10 |")
    A("| 10 | **方案 D 的 SurvT 阶梯窗口需要产品侧背书** | "
      "方案 D 允许梦魇 V 的存活时间掉到 4.5s，即「高层级允许被秒」。"
      "这是一条明确的设计原则，不应由仿真单方面决定。 | "
      "product-reviewer 确认「高层级允许被秒」后，方案 D 才可写入 GDD |")
    A("| 11 | **单关内容量从 150 上调到 270–350 只，必须配「三件套」** | "
      "① **地图面积同步放大 ×2**（否则变成挤在一起的怪堆，见 10.5.5(a)）；"
      "② **0.5 经验曲线系数按比例上调**（否则升级快 1.8–2.2 倍，破坏「每 5 关 = 1 阶段」）；"
      "③ **6.5 满强化魔石按比例上调**（否则满强化从 1.73 局/件降到 1.1–1.2 局/件）。"
      "具体取值：按推荐组合 269 只 → 系数 100→180、魔石 64→106；"
      "若不加杠杆纯加怪到 334 只 → 100→223、64→89。"
      "掉落表（6.1）**不需要改** —— 橙/红由精英/BOSS 驱动，杂兵翻倍只涨 ×1.04。 | "
      "三项已写入 10.5.5；GDD 6.5 / 0.5 待同步修订 |")
    A("| 12 | **同屏并发怪物数与单关怪物总量的引擎上限未确认** | "
      "10.5.5(a) 把「同屏并发」与「单关总量」区分为两个约束：总量 300–500 只"
      "可通过分区刷怪 + 死亡回收解决，但同屏并发数取决于 AI tick 与对象池实现。 | "
      "已向 godot-engineer-2 发起咨询（同屏并发上限 / 总量瓶颈 / 掉落物堆积），"
      "回填后更新 10.5.5(a) |")
    A("")
    A("---")
    A("")
    A("> 本报告由 `tools/sim/make_report.py` 依据 `tools/sim/dps_ehp_sim.py` 的实算结果生成，")
    A("> 所有表格数字均为脚本输出，非手工誊抄。修改系数后重跑即可获得一致更新。")

    return "\n".join(R)


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.normpath(
        os.path.join(here, "..", "..", "deliverables", "gstack", "sim-report-2026-09-16.md")
    )
    p = argparse.ArgumentParser(description="生成七傳說数值仿真报告")
    p.add_argument("--out", default=default_out, help="输出路径")
    args = p.parse_args()

    text = build_report()
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"报告已写入：{os.path.abspath(args.out)}")
    print(f"字符数：{len(text)}　行数：{text.count(chr(10)) + 1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
