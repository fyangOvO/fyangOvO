#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第五步「怪物 · 关卡 · BOSS 扩充」校验脚本（只读）。

用法：
    python 05-check_monster_level_boss.py
    python 05-check_monster_level_boss.py --repo D:/七傳說     # 加上工程侧漂移检测

设计原则（沿用第四步）：
  - 默认只校验策划产物（本目录 05-*.json）之间的自洽性 ⇒ 无 --repo 也应有意义
  - --repo 时才去读工程真实文件，检测「策划说的」与「工程实际的」是否脱钩
  - 绝不写入任何文件，绝不改工程代码

本步特有的两类断言（第五步确立的判据）：
  判据二：String 类型的「类型字段」（ai_id / objective_type / pattern）
          第一件事是 grep 它在代码里的分支数。命中 ≤1 = 没实现。
  判据三：改一个「看起来是配置项」的字段前，先 grep 它的消费点。
          若消费点只有埋点 / 展示 / 注释 ⇒ 改了不会有任何行为变化。
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))

# ----------------------------------------------------------------------------
# 常量：与 05-*.json 的约定保持一致
# ----------------------------------------------------------------------------

MONSTER_IDS_DECLARED = [
    # 现状 16 种（monsters.json，含 2 个 boss）
    "spider_cave", "bat_swarm", "skeleton_warrior", "slime_acid",
    "brute_butcher", "wraith_frost", "boss_bone_tyrant", "boss_ember_lord",
    "mushroom_spore", "warg_dark", "golem_ember", "imp_hellfire",
    "hound_ash", "pyromancer_cultist", "frozen_husk", "ice_wraith",
]

AI_IDS = ["melee_chaser", "ranged_kiter", "erratic_chaser",
          "lobber", "melee_charger", "boss_phased"]

NEW_FIELDS = ["preferred_range", "charge_speed_mult", "charge_range",
              "charge_windup", "erratic_amplitude", "erratic_frequency",
              "projectile_speed", "lob_radius", "lob_windup"]

ELEMENTS = ["physical", "fire", "cold", "lightning", "poison", "shadow"]

OBJECTIVES = ["clear_all", "kill_elite", "kill_boss", "survive", "collect", "reach_exit"]

LEVEL_COUNT = 20
ACCOUNT_MAX_LEVEL = 20          # 第四步路线 A 拍板值
BUDGET_TARGET_TOTAL = 5660      # 第四步路线 A 目标预算合计
BUDGET_TARGET = [120, 140, 160, 175, 190, 210, 230, 250, 265, 280,
                 295, 310, 325, 340, 355, 370, 385, 400, 420, 440]
COUNT_MIN_RATIO = 0.65

BOSS_LEVEL_USED = {
    "boss_bone_tyrant": [6, 20],   # ch1_l06(L6) / ch3_l20(L20)
    "boss_ember_lord": [13],       # ch2_l13(L13)
}

# 结果收集
RESULTS = []   # (group, ident, ok, detail)


def check(group, ident, ok, detail=""):
    RESULTS.append((group, ident, bool(ok), detail))
    return bool(ok)


def load(name):
    p = os.path.join(HERE, name)
    with open(p, encoding="utf-8") as f:
        return json.load(f)


# ----------------------------------------------------------------------------
# A 组：策划 JSON 的自洽性
# ----------------------------------------------------------------------------

def group_a(monsters, levels, bosses):
    print("\n=== A 组：策划产物自洽性 ===")

    # A1 怪物总数
    n_now = len(monsters.get("monsters_now", []))
    n_new = len(monsters.get("monsters_new", []))
    check("A", "A1 现状怪物条数 == 16", n_now == 16, f"实际 {n_now}")
    check("A", "A2 新增怪物条数 == 8", n_new == 8, f"实际 {n_new}")

    # A3 新增怪 id 不与现有重复
    now_ids = {m["id"] for m in monsters.get("monsters_now", [])}
    new_ids = [m["id"] for m in monsters.get("monsters_new", [])]
    dup = now_ids & set(new_ids)
    check("A", "A3 新增怪 id 不与现状重复", not dup, f"重复 {sorted(dup)}")
    check("A", "A4 新增怪 id 自身唯一", len(new_ids) == len(set(new_ids)))

    # A5 ai_id 取值合法
    bad = []
    for m in monsters.get("monsters_now", []) + monsters.get("monsters_new", []):
        if m.get("ai_id") not in AI_IDS:
            bad.append((m["id"], m.get("ai_id")))
    check("A", "A5 ai_id 取值均在 6 种内", not bad, f"越界 {bad}")

    # A6 element 取值合法
    bad = []
    for m in monsters.get("monsters_new", []):
        if m.get("element") not in ELEMENTS:
            bad.append((m["id"], m.get("element")))
    check("A", "A6 新增怪 element 取值合法", not bad, f"越界 {bad}")

    # A7 新增怪等级区间合法
    bad = [m["id"] for m in monsters.get("monsters_new", [])
           if not (1 <= m.get("level_min", 0) <= m.get("level_max", 0) <= ACCOUNT_MAX_LEVEL)]
    check("A", "A7 新增怪 level_min<=level_max 且 ⊆[1,20]", not bad, f"越界 {bad}")

    # A8 新增 8 怪覆盖抽样的元素需求
    new_elems = Counter(m["element"] for m in monsters.get("monsters_new", []))
    need = {"lightning": 2, "shadow": 2, "cold": 1, "poison": 1}
    short = {k: (new_elems.get(k, 0), v) for k, v in need.items() if new_elems.get(k, 0) < v}
    check("A", "A8 新增怪补齐 4 个缺口元素", not short, f"不足 {short}")

    # A9 9 个新字段齐备
    declared_fields = {f["name"] for f in monsters["ai_behavior_contract"]["fields_to_add"]}
    missing = set(NEW_FIELDS) - declared_fields
    check("A", "A9 新字段清单齐备（9 个）", not missing, f"缺 {sorted(missing)}")

    # A10 关卡数
    rows = levels["levels_target"]["rows"]
    check("A", "A10 关卡目标行数 == 20", len(rows) == 20, f"实际 {len(rows)}")

    # A11 budget == Σcount_max
    bad = [r["id"] for r in rows if r["budget"] != r["sigma_count_max"]]
    check("A", "A11 每关 budget == Σcount_max", not bad, f"不一致 {bad}")

    # A12 budget 序列 == 第四步目标序列
    got = [r["budget"] for r in rows]
    check("A", "A12 budget 序列 == 第四步 120→440", got == BUDGET_TARGET,
          f"首个不符 {next((i for i, (a, b) in enumerate(zip(got, BUDGET_TARGET)) if a != b), None)}")

    # A13 budget 单调不减
    mono = all(rows[i]["budget"] <= rows[i + 1]["budget"] for i in range(len(rows) - 1))
    check("A", "A13 budget 单调不减（消除倒挂）", mono)

    # A14 count_min ≈ count_max × 0.65
    bad = [(r["id"], r["sigma_count_min"], round(r["sigma_count_max"] * COUNT_MIN_RATIO))
           for r in rows if abs(r["sigma_count_min"] - round(r["sigma_count_max"] * COUNT_MIN_RATIO)) > 1]
    check("A", "A14 count_min ≈ count_max × 0.65（±1 容差）", not bad, f"偏差 {bad[:3]}")

    # A15 手绘关 m ≤ Σcount_max
    authored = [r for r in rows if r["form"] == "authored"]
    bad = [(r["id"], r.get("authored_m"), r["sigma_count_max"]) for r in authored
           if r.get("authored_m", 0) > r["sigma_count_max"]]
    check("A", "A15 手绘关 m ≤ Σcount_max", not bad, f"越界 {bad}")

    # A16 手绘关 m 留 ≥20% 余量
    bad = [r["id"] for r in authored
           if r["sigma_count_max"] > 0 and r.get("authored_m", 0) / r["sigma_count_max"] > 0.8]
    check("A", "A16 手绘关 m 余量 ≥20%", not bad, f"余量不足 {bad}")

    # A17 手绘关数量 == 4
    check("A", "A17 手绘关数量 == 4", len(authored) == 4, f"实际 {len(authored)}")

    # A18 合计对账
    t = levels["levels_target"]["totals"]
    check("A", "A18 budget 合计 == 5660", t["budget_total"] == BUDGET_TARGET_TOTAL, f"{t['budget_total']}")
    check("A", "A19 Σcount_max 合计 == 5660", t["sigma_count_max_total"] == BUDGET_TARGET_TOTAL, f"{t['sigma_count_max_total']}")
    check("A", "A20 Σcount_min 合计 == 行内求和",
          t["sigma_count_min_total"] == sum(r["sigma_count_min"] for r in rows),
          f"{t['sigma_count_min_total']} vs {sum(r['sigma_count_min'] for r in rows)}")
    check("A", "A21 手绘 m 合计 == 310",
          t["authored_m_total"] == sum(r.get("authored_m", 0) for r in authored),
          f"{t['authored_m_total']}")

    # A22 目标类型 6 种全用
    used = Counter(r["objective_target"] for r in rows)
    check("A", "A22 目标类型使用 6 种", len(used) == 6, f"实际 {len(used)}: {sorted(used)}")
    check("A", "A23 目标类型分布 == JSON 声明",
          used == Counter(levels["levels_target"]["self_consistency"]["objective_types"]),
          f"{dict(used)}")

    # A24 clear_all + kill_elite 占比 ≤60%
    conc = (used.get("clear_all", 0) + used.get("kill_elite", 0)) / len(rows)
    check("A", "A24 clear_all+kill_elite 占比 ≤60%", conc <= 0.60, f"{conc:.0%}")

    # A25 layout.pattern 4 种
    pat = Counter(r["pattern"] for r in rows)
    check("A", "A25 pattern 使用 4 种", len(pat) == 4, f"{dict(pat)}")

    # A26 无空 layout
    # （目标态所有关卡都有 pattern ⇒ 空 layout 数为 0）
    check("A", "A26 目标态空 layout 关 == 0", all("pattern" in r for r in rows))

    # A27 现状不一致关数 == 17
    d = levels["diagnosis"]
    check("A", "A27 现状 budget≠Σmax 关数 == 17", d["budget_ne_sigma_count_max_levels"] == 17,
          f"{d['budget_ne_sigma_count_max_levels']}")

    # A28 BOSS 数 == 2，且新增 BOSS 默认不执行
    check("A", "A28 现有 BOSS 数 == 2", len(bosses["bosses_now"]) == 2)
    check("A", "A29 新增 BOSS execute == false", bosses["new_boss_draft"]["execute"] is False)

    # A30 BOSS 技能清单：死数据识别正确
    skills = {s["name"]: s for s in bosses["diagnosis"]["skill_consumption"]["skills"]}
    check("A", "A30 bone_slam 标为死数据", skills.get("bone_slam", {}).get("state") == "DEAD_DATA")
    check("A", "A31 fireball 标为死数据", skills.get("fireball", {}).get("state") == "DEAD_DATA")
    check("A", "A32 enrage 标为部分实现", skills.get("enrage", {}).get("state") == "PARTIAL")

    # A33 差异化后 summon_count 不同
    rows2 = bosses["differentiation_spec"]["rows"]
    sc = {r["boss"]: tuple(r["summon_count_target"]) for r in rows2}
    check("A", "A33 差异化后两 BOSS summon_count 不同",
          sc.get("boss_bone_tyrant") != sc.get("boss_ember_lord"), f"{sc}")

    # A34 差异化后 enrage 阶段不同
    ep = {r["boss"]: r["enrage_phase_target"] for r in rows2}
    check("A", "A34 差异化后 enrage 阶段不同",
          ep.get("boss_bone_tyrant") != ep.get("boss_ember_lord"), f"{ep}")

    # A35 ember_lord 的 phase_skills 里 enrage 已提前到阶段 3
    ps = bosses["differentiation_spec"]["phase_skills_target"]["boss_ember_lord"]
    check("A", "A35 ember_lord 的 enrage 提前到阶段 3", "enrage" in ps.get("3", []))

    # A36 boss_bone_tyrant level_max 目标 == 20
    r = next(x for x in rows2 if x["boss"] == "boss_bone_tyrant")
    check("A", "A36 bone_tyrant level_max 目标 == 20",
          str(r["level_min_max_target"]).endswith("20"), r["level_min_max_target"])

    # A37 素材帧数对账
    a = monsters["asset_orders"]
    check("A", "A37 新怪精灵帧数 == 8×84 = 672",
          a["new_monster_sprites"]["frames_total"] == 672, f"{a['new_monster_sprites']['frames_total']}")
    check("A", "A38 新怪精灵逐项合计 == 672",
          sum(i["frames"] for i in a["new_monster_sprites"]["items"]) == 672)
    check("A", "A39 特效帧数 == 24", a["fx_frames_total"] == 24, f"{a['fx_frames_total']}")
    check("A", "A40 总帧数 == 696",
          a["new_monster_sprites"]["frames_total"] + a["fx_frames_total"] == 696)


# ----------------------------------------------------------------------------
# B 组：覆盖矩阵（用目标数据复算，验证断言成立）
# ----------------------------------------------------------------------------

def group_b(monsters):
    print("\n=== B 组：目标覆盖矩阵复算 ===")

    pool = []
    for m in monsters.get("monsters_now", []) + monsters.get("monsters_new", []):
        tier = m.get("tier")
        if tier == "boss":
            continue
        pool.append(m)

    cov = defaultdict(lambda: {"normal": [], "elite": []})
    for m in pool:
        t = m.get("tier")
        if t not in ("normal", "elite"):
            continue
        for L in range(m["level_min"], m["level_max"] + 1):
            if 1 <= L <= LEVEL_COUNT:
                cov[L][t].append(m["id"])

    print("  等级  普通  精英")
    for L in range(1, LEVEL_COUNT + 1):
        c = cov[L]
        print(f"  L{L:<4} {len(c['normal']):>4}  {len(c['elite']):>4}")

    # B1 每级普通怪 ≥4（L1 例外：目标声明就是 2）
    bad = [L for L in range(2, LEVEL_COUNT + 1) if len(cov[L]["normal"]) < 4]
    check("B", "B1 L2–L20 普通怪每级 ≥4", not bad, f"不足 {bad}")

    # B2 L1 普通怪 == 2（现状，不强制提升）
    check("B", "B2 L1 普通怪 == 2（现状保持）", len(cov[1]["normal"]) == 2,
          f"{cov[1]['normal']}")

    # B3 精英从 L2 起 ≥1（rat_swarm 补 L2–9）
    bad = [L for L in range(2, 10) if len(cov[L]["elite"]) < 1]
    check("B", "B3 L2–L9 精英 ≥1", not bad, f"不足 {bad}")

    # B4 L17–L20 普通怪 ≥5
    bad = [L for L in range(17, 21) if len(cov[L]["normal"]) < 5]
    check("B", "B4 L17–L20 普通怪 ≥5", not bad,
          f"{ {L: len(cov[L]['normal']) for L in range(17,21)} }")
    # B5 L17–L20 精英 ≥5
    bad = [L for L in range(17, 21) if len(cov[L]["elite"]) < 5]
    check("B", "B5 L17–L20 精英 ≥5", not bad,
          f"{ {L: len(cov[L]['elite']) for L in range(17,21)} }")

    # B6 6 元素各 ≥2 只承载怪
    elem = Counter(m["element"] for m in pool if m.get("element") in ELEMENTS)
    short = {e: elem.get(e, 0) for e in ELEMENTS if elem.get(e, 0) < 2}
    check("B", "B6 6 元素各 ≥2 只承载怪", not short, f"不足 {short}")

    # B7 L17–L20 元素多样性 ≥3（普通怪）
    e1720 = set()
    for L in range(17, 21):
        for mid in cov[L]["normal"]:
            m = next(x for x in pool if x["id"] == mid)
            e1720.add(m["element"])
    check("B", "B7 L17–L20 普通怪元素 ≥3 种", len(e1720) >= 3, f"{sorted(e1720)}")

    # B8 无等级完全空缺
    empty = [L for L in range(1, LEVEL_COUNT + 1)
             if not cov[L]["normal"] and not cov[L]["elite"]]
    check("B", "B8 无完全空缺等级", not empty, f"空缺 {empty}")

    # B9 ai_id 6 种都有承载怪
    #    ⚠️ 口径：boss_phased 由 BOSS 自身承载（tier=boss），不计入普通/精英池
    used = Counter(m["ai_id"] for m in pool)
    boss_carried = {m["ai_id"] for m in monsters.get("monsters_now", [])
                    if m.get("tier") == "boss"}
    for a in boss_carried:
        used[a] += 1
    short = [a for a in AI_IDS if used.get(a, 0) == 0]
    check("B", "B9 6 种 ai_id 都有承载怪", not short, f"无承载 {short}")
    print(f"  ai_id 承载：{dict(used)}（其中 {sorted(boss_carried)} 由 BOSS 承载）")


# ----------------------------------------------------------------------------
# C 组：工程侧漂移检测（需 --repo）
# ----------------------------------------------------------------------------

def group_c(repo):
    print("\n=== C 组：工程侧漂移检测 ===")

    mpath = os.path.join(repo, "game", "data", "monsters", "monsters.json")
    if not os.path.isfile(mpath):
        check("C", "C0 找到 game/data/monsters/monsters.json", False, mpath)
        return
    check("C", "C0 找到 game/data/monsters/monsters.json", True)

    with open(mpath, encoding="utf-8") as f:
        raw = json.load(f)
    ms = raw if isinstance(raw, list) else raw.get("monsters", raw)
    if isinstance(ms, dict):
        ms = list(ms.values())

    # C1 现状怪物条数
    check("C", "C1 工程侧怪物条数 ∈ {16, 24}", len(ms) in (16, 24), f"{len(ms)}")

    # C2 ai_id 取值集合
    ids = sorted({m.get("ai_id") for m in ms})
    unknown = [i for i in ids if i not in AI_IDS]
    check("C", "C2 工程侧 ai_id 取值 ⊆ 6 种已声明", not unknown, f"未知 {unknown}")

    # C3 tier 分布
    tiers = Counter(m.get("tier") for m in ms)
    print(f"  tier 分布：{dict(tiers)}")

    # C4 工程侧元素分布
    elems = Counter(m.get("element") for m in ms)
    print(f"  element 分布：{dict(elems)}")
    miss = [e for e in ELEMENTS if elems.get(e, 0) == 0]
    check("C", "C4 工程侧元素无空缺（拍板 D3=accept 后期望）",
          not miss or len(ms) == 16, f"空缺 {miss}（现状 16 条时为预期）")

    # ---- 判据二：String 类型字段的代码分支数 ----
    ebase = os.path.join(repo, "game", "scripts", "enemies", "enemy_base.gd")
    if not os.path.isfile(ebase):
        check("C", "C5 找到 enemy_base.gd", False, ebase)
        return
    with open(ebase, encoding="utf-8") as f:
        src = f.read()

    # 统计形如 "melee_chaser": 的 match 分支
    branch_n = 0
    for a in AI_IDS:
        # match 分支写法： "ai_id":
        if re.search(r'["\']' + re.escape(a) + r'["\']\s*:', src):
            branch_n += 1
    check("C", "C5 enemy_base.gd 的 ai_id match 分支数 == 6", branch_n == 6,
          f"实际 {branch_n}/6（0 = 未实现，本步 W5-1 待办）")

    # C6 9 个新字段是否已在 monster_data.gd 声明
    mdata = os.path.join(repo, "game", "resources", "monster_data.gd")
    if os.path.isfile(mdata):
        with open(mdata, encoding="utf-8") as f:
            md = f.read()
        have = [fld for fld in NEW_FIELDS if re.search(r'\b' + re.escape(fld) + r'\b', md)]
        check("C", "C6 monster_data.gd 新字段数 == 9", len(have) == 9,
              f"实际 {len(have)}/9（本步 W5-2 待办）")
    else:
        check("C", "C6 找到 monster_data.gd", False, mdata)

    # C7 BOSS 技能消费分支
    consumed = set()
    for s in ["summon_skeleton", "summon_imp", "shockwave", "magma_eruption",
              "bone_slam", "fireball", "enrage"]:
        if re.search(r'["\']' + re.escape(s) + r'["\']', src):
            consumed.add(s)
    check("C", "C7 BOSS 技能名在 enemy_base.gd 被引用数 == 7", len(consumed) == 7,
          f"实际 {len(consumed)}/7，缺 {sorted(set(['summon_skeleton','summon_imp','shockwave','magma_eruption','bone_slam','fireball','enrage']) - consumed)}")

    # C8 PACK_ACTIONS 是否仍含冗余 "death"
    has_death = re.search(r'PACK_ACTIONS[^\]]*"death"', src, re.S) is not None
    check("C", "C8 PACK_ACTIONS 不含冗余 \"death\"", not has_death,
          "仍含 ⇒ W5-11 待办")

    # ---- 判据三：total_monster_budget 的消费点 ----
    hits = []
    gd_files = []
    for root, _dirs, files in os.walk(os.path.join(repo, "game")):
        for fn in files:
            if fn.endswith(".gd"):
                gd_files.append(os.path.join(root, fn))
    for p in gd_files:
        try:
            with open(p, encoding="utf-8") as f:
                for i, line in enumerate(f, 1):
                    if "total_monster_budget" in line:
                        hits.append((os.path.relpath(p, repo), i, line.strip()))
        except (UnicodeDecodeError, OSError):
            continue

    print(f"  total_monster_budget 消费点（{len(hits)} 处）：")
    for h in hits:
        print(f"    {h[0]}:{h[1]}  {h[2][:90]}")

    # 期望：只有定义 + 读入 + 埋点，不应有「驱动刷怪」的用法
    driver_like = [h for h in hits if "randi_range" in h[2] or "count" in h[2].lower()
                   and "budget" in h[2].lower()]
    check("C", "C9 total_monster_budget 无『驱动刷怪数』的消费点",
          not driver_like, f"疑似驱动点 {driver_like}")

    # C10 level_scene 的埋点存在
    scene_hit = [h for h in hits if "level_scene.gd" in h[0]]
    check("C", "C10 level_scene.gd 有 budget 埋点（预期唯一消费点）",
          len(scene_hit) >= 1, f"{scene_hit}")

    # ---- 关卡侧 ----
    ldir = os.path.join(repo, "game", "data", "levels")
    if not os.path.isdir(ldir):
        check("C", "C11 找到 game/data/levels", False, ldir)
        return
    check("C", "C11 找到 game/data/levels", True)

    levels = []
    for fn in sorted(os.listdir(ldir)):
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(ldir, fn), encoding="utf-8") as f:
            raw = json.load(f)
        lv = raw if isinstance(raw, list) else raw.get("levels", raw)
        if isinstance(lv, dict):
            lv = list(lv.values())
        levels.extend(lv)

    check("C", "C12 工程侧关卡数 == 20", len(levels) == 20, f"{len(levels)}")

    mism = []
    budget_total = 0
    smax_total = 0
    for L in levels:
        me = L.get("monster_entries", []) or []
        smax = sum(e.get("count_max", 0) for e in me)
        b = L.get("total_monster_budget", 0)
        budget_total += b
        smax_total += smax
        if b != smax:
            mism.append(L["id"])
    check("C", "C13 工程侧 budget == Σcount_max（拍板后应 20/20）",
          not mism, f"不一致 {len(mism)} 关：{mism[:5]}...")
    print(f"  budget 合计 {budget_total} / Σcount_max 合计 {smax_total}")

    # C14 目标类型
    objs = Counter(L.get("objective_type") for L in levels)
    print(f"  objective 分布：{dict(objs)}")
    check("C", "C14 工程侧无未知目标类型",
          all(o in OBJECTIVES for o in objs), f"{[o for o in objs if o not in OBJECTIVES]}")

    # C15 未实现目标的降级保护仍在
    lscene = os.path.join(repo, "game", "scripts", "run", "level_scene.gd")
    if os.path.isfile(lscene):
        with open(lscene, encoding="utf-8") as f:
            ls = f.read()
        check("C", "C15 level_scene.gd 保留『未实现目标明确降级 + push_warning』",
              "push_warning" in ls and ("未实现" in ls or "\u672a\u5b9e\u73b0" in ls))
    else:
        check("C", "C15 找到 level_scene.gd", False, lscene)

    # C16 手绘关 m ≤ Σcount_max（工程侧硬约束）
    bad = []
    for L in levels:
        cells = (L.get("layout") or {}).get("cells")
        if not cells:
            continue
        m = sum(row.count("m") for row in cells)
        smax = sum(e.get("count_max", 0) for e in (L.get("monster_entries") or []))
        if m > smax:
            bad.append((L["id"], m, smax))
    check("C", "C16 工程侧手绘关 m ≤ Σcount_max（防整关不可玩）", not bad, f"越界 {bad}")

    # C17 空 layout 的关
    empty_layout = [L["id"] for L in levels if not (L.get("layout") or {})]
    print(f"  空 layout 关：{empty_layout}")
    check("C", "C17 工程侧空 layout 关数（拍板后应 0）", not empty_layout,
          f"{len(empty_layout)} 关：{empty_layout}")

    # ---- BOSS 侧 ----
    bpath = os.path.join(repo, "game", "data", "bosses", "bosses.json")
    if os.path.isfile(bpath):
        with open(bpath, encoding="utf-8") as f:
            raw = json.load(f)
        bs = raw if isinstance(raw, list) else raw.get("bosses", raw)
        if isinstance(bs, dict):
            bs = list(bs.values())
        check("C", "C18 工程侧 BOSS 数 == 2", len(bs) == 2, f"{len(bs)}")

        # C19 BOSS 等级区间与使用关卡的矛盾
        m_by_id = {m.get("id"): m for m in ms}
        conflicts = []
        for bid, used_levels in BOSS_LEVEL_USED.items():
            ent = m_by_id.get(bid)
            if not ent:
                continue
            lo, hi = ent.get("level_min"), ent.get("level_max")
            for lv in used_levels:
                if not (lo <= lv <= hi):
                    conflicts.append((bid, f"used@L{lv}", f"declared {lo}-{hi}"))
        check("C", "C19 BOSS 等级区间覆盖其使用关卡（W5-6 待办）",
              not conflicts, f"{conflicts}")
    else:
        check("C", "C18 找到 bosses.json", False, bpath)

    # ---- 精灵素材 ----
    cdir = os.path.join(repo, "game", "assets", "pack", "creatures")
    if os.path.isdir(cdir):
        dirs = sorted(d for d in os.listdir(cdir) if os.path.isdir(os.path.join(cdir, d)))
        print(f"  creatures 目录 {len(dirs)} 个：{dirs}")
        check("C", "C20 creatures 目录数 ∈ {20, 28}", len(dirs) in (20, 28), f"{len(dirs)}")
        # 抽样检查帧数
        sample = [d for d in dirs if d not in ("player",)][:3]
        for d in sample:
            p = os.path.join(cdir, d)
            n = len([x for x in os.listdir(p) if x.endswith(".png")])
            print(f"    {d}: {n} png")
    else:
        check("C", "C20 找到 assets/pack/creatures", False, cdir)


# ----------------------------------------------------------------------------
# D 组：D1–D5 拍板落地（2026-09-24 用户裁定）
# ----------------------------------------------------------------------------

DECIDED_EXPECT = {
    "D1": "all",     # ai_id 6 种一次做全
    "D2": "route1",  # 改 count_*（不动代码）
    "D3": "accept",  # 怪物 16 → 24（+8）
    "D4": "none",    # 不新增 BOSS
    "D5": "both",    # survive / reach_exit 两种都补
}


def group_d(monsters, levels, bosses):
    print("\n=== D 组：D1–D5 拍板落地 ===")

    dec = monsters.get("decisions_2026_09_24")
    if not dec:
        check("D", "D0 05-monsters.json 有 decisions_2026_09_24 段", False, "缺失")
        return
    check("D", "D0 05-monsters.json 有 decisions_2026_09_24 段", True)

    # D1-D5 全部已裁定，且值 == 预期
    items = {i["id"]: i for i in dec.get("items", [])}
    for k, want in DECIDED_EXPECT.items():
        got = items.get(k, {}).get("decision")
        check("D", f"D-{k} 裁定 == {want}", got == want, f"实际 {got}")

    # 待拍板清单已清空
    check("D", "D6 decisions_pending 已清空",
          monsters.get("decisions_pending") == [],
          f"{monsters.get('decisions_pending')}")

    # status 已更新
    for jf, tag in ((monsters, "05-monsters.json"),
                    (levels, "05-levels.json"),
                    (bosses, "05-bosses.json")):
        st = jf.get("_meta", {}).get("status", "")
        check("D", f"D7 {tag} status 標記為已拍板",
              ("已拍板" in st) or ("已拍板" in st), st)

    # D2 → levels 侧有记录
    check("D", "D8 05-levels.json 记录 D2=route1 / D5=both",
          levels.get("decisions_2026_09_24", {}).get("D2", {}).get("decision") == "route1"
          and levels.get("decisions_2026_09_24", {}).get("D5", {}).get("decision") == "both")

    # D4 → 新 BOSS 草案不执行
    check("D", "D9 D4 后 new_boss_draft.execute == false（永久）",
          bosses["new_boss_draft"]["execute"] is False)

    # D2 路线① ⇒ 目标行全部 budget == Σcount_max（无 budget 单独驱动的残留）
    rows = levels["levels_target"]["rows"]
    check("D", "D10 路線①：20 關 budget == Σcount_max",
          all(r["budget"] == r["sigma_count_max"] for r in rows))

    # D5 ⇒ 目标序列用满 6 种
    used = Counter(r["objective_target"] for r in rows)
    check("D", "D11 D5 后目標類型 6 種全用", len(used) == 6, f"{sorted(used)}")
    check("D", "D12 survive 用 3 關 / reach_exit 用 2 關",
          used.get("survive") == 3 and used.get("reach_exit") == 2,
          f"survive={used.get('survive')} reach_exit={used.get('reach_exit')}")

    # D3 ⇒ 新怪 8 只，且 D1 后都有 ai_id
    check("D", "D13 D3 後新增怪 == 8 隻", len(monsters["monsters_new"]) == 8)

    # D1 全做 ⇒ 分期表不作执行
    ph = monsters["ai_behavior_contract"].get("phasing_option", {})
    check("D", "D14 D1 後分期表標記為不執行",
          "不作执行" in ph.get("_note", "") or "不执行" in ph.get("_note", ""),
          ph.get("_note", "")[:60])


# ----------------------------------------------------------------------------
# 报告
# ----------------------------------------------------------------------------

def report(passed_only=False):
    groups = defaultdict(lambda: [0, 0])
    fails, todos = [], []
    for g, ident, ok, detail in RESULTS:
        if ok:
            groups[g][0] += 1
        else:
            groups[g][1] += 1
            fails.append((g, ident, detail))
    total_ok = sum(v[0] for v in groups.values())
    total_fail = sum(v[1] for v in groups.values())

    print("\n" + "=" * 74)
    print("分组结果：")
    for g in sorted(groups):
        ok, bad = groups[g]
        print(f"  {g} 组：{ok} 通过 / {bad} 失败")

    if fails and not passed_only:
        print("\n失败项：")
        for g, ident, detail in fails:
            print(f"  [FAIL] {ident}")
            if detail:
                print(f"         {detail}")
    print("\n" + "=" * 74)
    print(f"合计：{total_ok} 通过 / {total_fail} 失败")
    return total_fail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=None,
                    help="工程根目录（如 D:/七傳說）；给定则额外做工程侧漂移检测")
    ap.add_argument("--quiet-pass", action="store_true", help="只打印失败项")
    args = ap.parse_args()

    print("第五步「怪物 · 关卡 · BOSS 扩充」校验")
    print(f"策划案目录：{HERE}")
    if args.repo:
        print(f"工程根目录：{args.repo}")
    else:
        print("工程根目录：（未提供，跳过 C 组）")

    monsters = load("05-monsters.json")
    levels = load("05-levels.json")
    bosses = load("05-bosses.json")

    group_a(monsters, levels, bosses)
    group_b(monsters)
    group_d(monsters, levels, bosses)
    if args.repo:
        group_c(args.repo)

    n = report(passed_only=args.quiet_pass)
    sys.exit(0 if n == 0 else 1)


if __name__ == "__main__":
    main()
