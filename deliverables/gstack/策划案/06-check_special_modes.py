#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第六步「特色玩法」校验脚本
================================

覆盖：
  A 组 —— 三份 JSON 自洽（结构 / 数组长度 / 权重和 / 不变式）         [纯策划侧]
  B 组 —— S10 门票落点一致性                                        [纯策划侧]
  C 组 —— S11 BOSS 二阶段落地一致性                                 [纯策划侧]
  D 组 —— S12 特殊档 10 档体系自洽                                  [纯策划侧]
  F 组 —— Q-a / Q-b / Q-c 三细节裁定自洽                            [纯策划侧]
  E 组 —— 工程侧漂移检测（仅 --repo 时执行）                        [需工程只读]

用法：
  python 06-check_special_modes.py
  python 06-check_special_modes.py --repo D:/七傳說

约定（与本项目既有校验脚本一致）：
  - 纯策划侧全绿是「本步数据自洽」的证明
  - 带 --repo 的失败项【只允许】是已登记工单造成的漂移，不应有意外失败
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 常量（工程侧权威值的策划侧副本）
# =============================================================================

RARITY_COUNT_NOW = 8
RARITY_COUNT_TARGET = 10

# 现 8 档基线权重（monster_normal 口径）
DROP_WEIGHTS_NOW = [78.02, 17.55, 3.50, 0.45, 0.05, 0.02, 0.40, 0.01]
# 目标 10 档权重
DROP_WEIGHTS_TARGET = [77.90, 17.50, 3.50, 0.45, 0.05, 0.02, 0.40, 0.01, 0.14, 0.03]

# 硬约束：橙装权重不可变
LEGENDARY_WEIGHT_HARD = 0.05

# 现 8 档的 15 个定长数组（用于交叉校验 target 表）
BEAM_HEIGHTS_NOW = [0, 8, 16, 24, 40, 56, 32, 64]
PREFIX_NOW = [0, 1, 2, 3, 3, 4, 2, 3]
SUFFIX_NOW = [0, 1, 2, 2, 3, 3, 3, 3]
AFFIX_MAX_NOW = [0, 2, 4, 5, 6, 7, 5, 6]

BEAM_HEIGHTS_TARGET = BEAM_HEIGHTS_NOW + [48, 48]
PREFIX_TARGET = PREFIX_NOW + [4, 4]
SUFFIX_TARGET = SUFFIX_NOW + [3, 3]
AFFIX_MAX_TARGET = AFFIX_MAX_NOW + [7, 7]

# S11 目标值
PHASE2_THRESHOLD = 0.6
PHASE2_DAMAGE_MULT = 1.4
PHASE2_SKILLS_P1 = 2
PHASE2_SKILLS_P2 = 4
PHASE2_ARENA = ["fire_ring", "shrink_arena"]

# S10
TARGET_SAVE_VERSION = 6  # B4-4 已占用 5 ⇒ S10 顺延为 6
TICKET_KEYS = ["ticket_normal", "key_advanced"]

# S12 新增两档的键
NEW_RARITY_KEYS = ["special_abyss", "special_tower"]

# 工程侧「硬编码 8」的三处（必须改成 10）。
# ⚠️ 用**内容模式**定位，不用行号：行号会随文件上方任何编辑漂移
#    （2026-09-28 第一步 B0 给 self_check.gd 加了 7 行 ⇒ 原 [785,786,787] 指向了
#     别的代码，E4 一度误报「已修复」。行号定位在这里是结构性的假阴性源。）
# 每项 = (相对路径, 需命中的正则, 说明)
HARDCODED_8_SITES = [
    ("game/tools/self_check.gd", r"稀有度权重 8 档", "掉落表断言的「8 档」字面量"),
    ("game/tools/verify_loot_tables.gd", r"rarity_weights\.size\(\)\s*!=\s*8", "权重数组长度硬编码 8"),
    ("game/tools/verify_ui_assets.gd", r"for r in range\(8\)", "稀有度循环上界硬编码 8"),
]


# =============================================================================
# 断言框架
# =============================================================================

class Checker:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.failures = []

    def ok(self, cond, msg):
        if cond:
            self.passed += 1
            print("  [OK]   %s" % msg)
        else:
            self.failed += 1
            self.failures.append(msg)
            print("  [FAIL] %s" % msg)

    def group(self, title):
        print("\n=== %s ===" % title)


# =============================================================================
# 载入
# =============================================================================

def load_json(name):
    path = os.path.join(HERE, name)
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_all():
    return {
        "rarity": load_json("06-special-rarity.json"),
        "boss": load_json("06-boss-phase2.json"),
        "ticket": load_json("06-tickets.json"),
        "tower": load_json("06-tower.json"),
        "abyss": load_json("06-abyss.json"),
        "sloot": load_json("06-special-loot.json"),
    }


# =============================================================================
# A 组 —— 三份 JSON 结构存在性
# =============================================================================

def group_a(data, ck):
    ck.group("A. 三份 JSON 结构自洽")

    for name in ["rarity", "boss", "ticket"]:
        ck.ok(data[name] is not None, "%s 存在且可解析" % name)

    r = data["rarity"]
    if r:
        ck.ok(r["_meta"]["status"].startswith("已拍板"), "special-rarity 状态为已拍板")
        ck.ok(r["target_state_10"]["RARITY_COUNT"] == RARITY_COUNT_TARGET,
              "target RARITY_COUNT == 10")
        ck.ok(len(r["target_state_10"]["rows"]) == RARITY_COUNT_TARGET,
              "target rows 长度 == 10")
        ck.ok(len(r["constants_patch"]["items"]) == 15,
              "constants_patch 含 15 个常量项")
        ck.ok(len(r["current_state_8"]["rows"]) == RARITY_COUNT_NOW,
              "current rows 长度 == 8")

    b = data["boss"]
    if b:
        ck.ok(b["_meta"]["status"].startswith("已拍板"), "boss-phase2 状态为已拍板")
        ck.ok(b["target_state_2phase"]["spec"]["phase_count"] == 2,
              "target phase_count == 2")
        ck.ok(len(b["target_state_2phase"]["bosses"]) == 2,
              "target 含 2 个 BOSS")
        ck.ok(len(b["regression_rewrite"]["lines"]) >= 15,
              "回归改造清单 >= 15 行（实得 %d）" % len(b["regression_rewrite"]["lines"]))

    t = data["ticket"]
    if t:
        ck.ok("已拍板" in t["_meta"]["status"], "tickets 状态含已拍板")
        ck.ok(t["save_integration"]["_decided"].startswith("S10 = ⓒ"),
              "S10 落点为 ⓒ save_data.tickets")
        ck.ok(len(t["design"]["two_tier"]) == 2, "分级门票为 2 档")


# =============================================================================
# B 组 —— S10 门票落点一致性
# =============================================================================

def group_b(data, ck):
    ck.group("B. S10 门票落点一致性")

    t = data["ticket"]
    if not t:
        ck.ok(False, "tickets JSON 缺失，B 组跳过")
        return

    # B1: 选择了 tickets 而非 materials / consumables
    patch_targets = " ".join(p["target"] for p in t["save_integration"]["patch_items"])
    ck.ok("tickets" in t["save_integration"]["new_fields"][0]["name"],
          "B1 新增字段名为 tickets")
    ck.ok("materials" not in patch_targets.lower(),
          "B2 补丁目标未触及 materials（避免加剧两套词表混乱）")
    ck.ok("consumables" not in patch_targets.lower(),
          "B3 补丁目标未触及 consumables")

    # B2: 五项补丁齐备
    seqs = sorted(p["seq"] for p in t["save_integration"]["patch_items"])
    ck.ok(seqs == [1, 2, 3, 4, 5], "B4 补丁项编号为 1..5 连续（实得 %s）" % seqs)

    # B3: SAVE_VERSION 目标为 6（B4-4 已占用 5）
    sv = [p for p in t["save_integration"]["patch_items"]
          if "SAVE_VERSION" in p["target"]]
    ck.ok(len(sv) == 1 and sv[0]["action"].startswith("5 → 6"),
          "B5 SAVE_VERSION 5 → 6")

    # B4: migrate 分支显式存在且有警告
    ck.ok(t["save_integration"]["migration_warning"]["_critical"] is True,
          "B6 migrate 分支缺失风险已标为 critical")

    # B5: tower_progress 连带字段存在
    names = [f["name"] for f in t["save_integration"]["new_fields"]]
    ck.ok("tower_progress" in names, "B7 tower_progress 连带字段已登记")

    # B6: 读写 API 采用 save_data 风格（负数返回 false）
    api = "\n".join(t["save_integration"]["read_write_api"]["code"])
    ck.ok("return false" in api and "next < 0" in api,
          "B8 add_ticket 采用 save_data 风格（负数返回 false）")

    # B7: 已拒绝两选项均有理由
    ck.ok(len(t["rejected_options"]["rows"]) == 2,
          "B9 两个落选方案均记录拒绝理由")

    # B8: run_shop buy() 补分支已登记（防假闭环）
    shop_actions = " ".join(i["action"] for i in t["shop_patch"]["items"])
    ck.ok("ticket" in shop_actions, "B10 run_shop buy() 补 ticket 分支已登记")

    # B9: hub 三处同步警告存在
    ck.ok("三处" in t["hub_integration"]["_warn"],
          "B11 hub 新增面板的「三处同步」警告已登记")

    # B10: 门票两档 id 与获取渠道一致
    tiers = [x["id"] for x in t["design"]["two_tier"]]
    ck.ok(tiers == TICKET_KEYS,
          "B12 门票两档 id 与常量一致（实得 %s）" % tiers)


# =============================================================================
# C 组 —— S11 BOSS 二阶段一致性
# =============================================================================

def group_c(data, ck):
    ck.group("C. S11 BOSS 二阶段落地一致性")

    b = data["boss"]
    if not b:
        ck.ok(False, "boss-phase2 JSON 缺失，C 组跳过")
        return

    spec = b["target_state_2phase"]["spec"]
    ck.ok(spec["thresholds"] == [PHASE2_THRESHOLD],
          "C1 thresholds == [0.6]")
    ck.ok(spec["phase_skills_segments"] == 2, "C2 phase_skills 2 段")
    ck.ok(spec["phase_damage_mult_segments"] == 2, "C3 phase_damage_mult 2 段")
    ck.ok(spec["summon_count_segments"] == 2, "C4 summon_count 2 段")
    ck.ok(spec["enrage_at_phase"] == 2, "C5 enrage 在阶段 2")
    ck.ok(abs(spec["damage_mult_phase2"] - PHASE2_DAMAGE_MULT) < 1e-9,
          "C6 damage_mult == 1.4")

    for boss in b["target_state_2phase"]["bosses"]:
        bid = boss["id"]
        ck.ok(boss["phase_count"] == 2, "C7 %s phase_count == 2" % bid)
        ck.ok(boss["thresholds"] == [PHASE2_THRESHOLD],
              "C8 %s thresholds == [0.6]" % bid)
        sk = boss["phase_skills"]
        ck.ok(len(sk["1"]) == PHASE2_SKILLS_P1,
              "C9 %s 阶段 1 有 2 招（实得 %d）" % (bid, len(sk["1"])))
        ck.ok(len(sk["2"]) == PHASE2_SKILLS_P2,
              "C10 %s 阶段 2 有 4 招（实得 %d）" % (bid, len(sk["2"])))
        ck.ok("enrage" in sk["2"], "C11 %s 阶段 2 含 enrage" % bid)
        ck.ok(set(sk["1"]).issubset(set(sk["2"])),
              "C12 %s 阶段技能累积（阶段 2 ⊇ 阶段 1）" % bid)
        ck.ok(len(boss["phase_damage_mult"]) == 2
              and boss["phase_damage_mult"][1] == PHASE2_DAMAGE_MULT,
              "C13 %s phase_damage_mult == [1.0, 1.4]" % bid)
        sc = boss["summon_count"]
        ck.ok(len(sc) == 2 and sc[1] > sc[0],
              "C14 %s summon_count 2 段且二阶段 > 一阶段（%s）" % (bid, sc))
        ac = boss["arena_change"]
        ck.ok(all(ac.get(k) is True for k in PHASE2_ARENA),
              "C15 %s arena_change 火环 + 缩小战场均启用" % bid)

    # 控制器 5 处改动齐备
    items = b["controller_patch"]["items"]
    ck.ok(len(items) == 5, "C16 控制器改动 5 处（实得 %d）" % len(items))
    ck.ok(any(i["target"] == "current_phase() 的 clamp" and "1, 2" in i["to"]
              for i in items), "C17 current_phase clamp 改为 (phase,1,2)")
    ck.ok(any(i["target"] == "PHASE_NAMES" for i in items),
          "C18 PHASE_NAMES 改动已登记")
    ck.ok(any("validate()" in i["target"] for i in items),
          "C19 validate() 断言改动已登记")

    # 场地变化叠加约束
    sc2 = b["arena_change_spec"]["stacking_constraint"]
    ck.ok(sc2["_critical"] is True, "C20 叠加约束标为 critical")
    ck.ok("assert" in sc2["suggested_assert"], "C21 建议 assert 语句已给出")

    # 回归改造覆盖 A–G 全组
    groups = set(l["group"] for l in b["regression_rewrite"]["lines"])
    ck.ok(groups >= {"A", "B", "C", "D", "E", "G"},
          "C22 回归改造覆盖 A–G 组（实得 %s）" % sorted(groups))
    # B 组语义反转必须被标注
    b71 = [l for l in b["regression_rewrite"]["lines"]
           if l["group"] == "B" and l["line"] == "71"]
    ck.ok(len(b71) == 1 and "语义反转" in b71[0]["status"],
          "C23 B71「70%→阶段2」的语义反转已标注")

    # 第五步跨步修订表
    ck.ok(len(b["step5_cross_revision"]["rows"]) == 8,
          "C24 第五步跨步修订表 8 行（实得 %d）" % len(b["step5_cross_revision"]["rows"]))


# =============================================================================
# D 组 —— S12 特殊档 10 档自洽
# =============================================================================

def group_d(data, ck):
    ck.group("D. S12 特殊档（8 → 10 档）自洽")

    r = data["rarity"]
    if not r:
        ck.ok(False, "special-rarity JSON 缺失，D 组跳过")
        return

    rows = r["target_state_10"]["rows"]

    # D1: 新增两档的键与索引
    ck.ok(rows[8]["key"] == NEW_RARITY_KEYS[0],
          "D1 idx8 键为 special_abyss（实得 %s）" % rows[8]["key"])
    ck.ok(rows[9]["key"] == NEW_RARITY_KEYS[1],
          "D2 idx9 键为 special_tower（实得 %s）" % rows[9]["key"])
    ck.ok(rows[8]["cn"] == "深渊" and rows[9]["cn"] == "塔",
          "D3 中文名为 深渊 / 塔")
    ck.ok(rows[8]["category"] == "special" and rows[9]["category"] == "special",
          "D4 两档 category 均为 special")

    # D2: 索引连续
    idxs = [x["idx"] for x in rows]
    ck.ok(idxs == list(range(10)), "D5 idx 连续 0..9")

    # D3: 键唯一
    keys = [x["key"] for x in rows]
    ck.ok(len(set(keys)) == 10, "D6 10 个 key 无重复")

    # D4: 光柱高度不与既有冲突且符合建议
    ck.ok([x["beam_h"] for x in rows[:8]] == BEAM_HEIGHTS_NOW,
          "D7 前 8 档 beam_h 未被改动")
    ck.ok([x["beam_h"] for x in rows[8:]] == [48, 48],
          "D8 新增两档 beam_h == 48")

    # D5: 前缀 + 后缀 == 词缀上限（不变式）
    invariant_ok = True
    for x in rows:
        if x["prefix"] + x["suffix"] != x["affix"][1]:
            invariant_ok = False
    ck.ok(invariant_ok, "D9 不变式：前缀上限 + 后缀上限 == 词缀条数上限（10 档全过）")

    # D6: 目标一致（JSON 内 rows 与脚本常量）
    ck.ok([x["prefix"] for x in rows] == PREFIX_TARGET,
          "D10 prefix 目标 == %s" % PREFIX_TARGET)
    ck.ok([x["suffix"] for x in rows] == SUFFIX_TARGET,
          "D11 suffix 目标 == %s" % SUFFIX_TARGET)

    # D7: 掉落权重和 = 100
    tw = r["drop_weight_squeeze"]["tables"][0]["target"]
    ck.ok(len(tw) == 10, "D12 目标权重 10 位（实得 %d）" % len(tw))
    ck.ok(abs(sum(tw) - 100.0) < 0.001, "D13 目标权重和 == 100（实得 %.4f）" % sum(tw))

    # D8: 橙装硬约束不变
    ck.ok(abs(tw[4] - LEGENDARY_WEIGHT_HARD) < 1e-9,
          "D14 橙装权重保持 %.2f（硬约束）" % LEGENDARY_WEIGHT_HARD)

    # D9: 挤出守恒（新增 = 白蓝减少量）
    base = r["drop_weight_squeeze"]["tables"][0]
    now, tgt = base["now"], base["target"]
    delta_now = now[0] + now[1]
    delta_tgt = tgt[0] + tgt[1]
    added = tgt[8] + tgt[9]
    ck.ok(abs((delta_now - delta_tgt) - added) < 0.001,
          "D15 挤出守恒：白蓝减少量 %.2f == 新增量 %.2f" % (delta_now - delta_tgt, added))

    # D10: 三张表均登记
    ck.ok(len(r["drop_weight_squeeze"]["tables"]) == 3,
          "D16 3 张掉落表均已登记（实得 %d）" % len(r["drop_weight_squeeze"]["tables"]))

    # D11: 底材缺口已识别（最关键）
    tg = r["template_gap"]
    ck.ok(tg["_evidence"]["max_rarity_max_found"] == 7,
          "D17 已识别「现有底材 rarity_max 最大仅 7」")
    ck.ok(len(tg["_failure_chain"]) >= 5,
          "D18 空池静默失败链已记录 %d 步" % len(tg["_failure_chain"]))
    ck.ok(len(tg["planned_files"]) == 2,
          "D19 计划新增 2 个特殊档底材文件")

    # D12: 3 处硬编码 8 已登记
    sites = r["gating_audit"]["rows"]
    hard8 = [x for x in sites if "🔴 硬编码 8" in x["impact"]]
    ck.ok(len(hard8) >= 3, "D20 硬编码 8 的站点 >= 3（实得 %d）" % len(hard8))

    # D13: 不可逆已标注
    ck.ok(r["reversibility"]["is_reversible"] is False,
          "D21 已标注为不可逆决策")

    # D14: run_shop 价格缺口已识别
    ck.ok(any("run_shop" in x["site"] and "RARITY_PRICE" in x["logic"]
              for x in sites),
          "D22 run_shop.RARITY_PRICE 缺口已识别")

    # D15: 断言清单完备
    ck.ok(len(r["assertions_for_checker"]) == 14,
          "D23 断言清单 14 条（实得 %d）" % len(r["assertions_for_checker"]))


# =============================================================================
# F 组 —— Q-a / Q-b / Q-c 三细节裁定（S12 落地前置）
# =============================================================================

def group_f(data, ck):
    ck.group("F. Q-a / Q-b / Q-c 三细节裁定自洽")

    r = data["rarity"]
    if not r:
        ck.ok(False, "special-rarity JSON 缺失，F 组跳过")
        return

    if "three_details_qa_qb_qc" not in r:
        ck.ok(False, "F0 three_details_qa_qb_qc 段缺失（Q-a/Q-b/Q-c 未落地）")
        return

    q = r["three_details_qa_qb_qc"]

    # ---- Q-a ----
    qa = q["qa_overlevel_penalty"]
    ck.ok("不吃" in qa["decision"], "F1 Q-a 裁定为「不吃越级惩罚」")
    ck.ok(qa["patch"]["_after"].count("i < SPECIAL_ABYSS") == 1,
          "F2 Q-a 提供了显式守卫（`and i < SPECIAL_ABYSS`）")
    ck.ok("MYTHIC" in qa["patch"]["_before"] and "SPECIAL_ABYSS" in qa["patch"]["_after"],
          "F3 Q-a patch 的 before/after 为可执行的一行 diff 形态")

    # ---- Q-b ----
    qb = q["qb_dismantle"]
    ck.ok("可以" in qb["decision"], "F4 Q-b 裁定为「可以分解」")
    ck.ok(qb["agrees_with_skeleton"] is False,
          "F5 Q-b 已标注「推翻骨架建议」（agrees_with_skeleton == False）")
    mats = qb["material_design"]["table"]
    keys = [m["output_key"] for m in mats]
    ck.ok(len(mats) == 2, "F6 Q-b 定义 2 种专属材料（实得 %d）" % len(mats))
    ck.ok(keys[0] != keys[1], "F7 两种材料键互不相同（%s / %s）" % (keys[0], keys[1]))
    EXISTING_5 = {"gold", "magic_stone", "mithril_dust", "legend_essence", "crystal"}
    ck.ok(all(k not in EXISTING_5 for k in keys),
          "F8 两种专属材料均不属于既有 5 键（否则形成套利链）")
    ck.ok(all(0 < m["amount"][0] <= m["amount"][1] for m in mats),
          "F9 材料数量区间合法（lo <= hi 且 > 0）")
    ck.ok("MATERIAL_KEY_MAP" in qb["material_design"]["_material_bag_impact"],
          "F10 Q-b 已登记 hub.MATERIAL_KEY_MAP 连带影响")
    ck.ok(len(qb["material_design"]["_material_bag_impact"]) > 0, "F11 Q-b 材料扩容连带有记录")
    ck.ok(qb["uniqueness_interaction"]["_critical"] is True,
          "F12 Q-b 已标注唯一性「分解不释放」为关键约束")
    ck.ok("append-only" in qb["uniqueness_interaction"]["_required"],
          "F13 Q-b 唯一性已获列表要求 append-only")

    # ---- Q-c ----
    qc = q["qc_forge_reroll"]
    ck.ok("需要" in qc["decision"], "F14 Q-c 裁定为「需要」强化 + 重铸")
    enh = qc["spec"]["enhance"]
    ck.ok(enh["enabled"] is True and enh["max_level"] == 10,
          "F15 Q-c 强化上限 == 10")
    cost_str = json.dumps(enh["cost_per_level"], ensure_ascii=False)
    ck.ok(all(k not in cost_str for k in ["stones", "dust", "essence", "crystal"]),
          "F16 Q-c 强化成本只吃专属材料（不出现通用材料键）")
    ck.ok(len(enh["cost_per_level"]) == 3, "F17 Q-c 强化成本分 3 段")

    rer = qc["spec"]["reroll"]
    ck.ok(rer["enabled"] is True, "F18 Q-c 重铸已启用")
    ck.ok("半重铸" in rer["scope"], "F19 Q-c 重铸语义为「半重铸」（非整件）")
    locks = rer["lock_rules"]
    ck.ok(all(x["max_locked"] == 4 for x in locks), "F20 Q-c 锁定上限 == 4（两档一致）")
    ck.ok(all(x["max_locked"] + x["max_rerolled"] == x["affix_total"] for x in locks),
          "F21 Q-c 锁定数 + 可重抽数 == 词缀总数（7）")
    ck.ok(all(x["max_rerolled"] <= 3 for x in locks), "F22 Q-c 可重抽数 <= 3")
    ck.ok(rer["special_affix_protection"]["_critical"] is True,
          "F23 Q-c 专属词缀保护已标注为关键约束")
    ck.ok(qc["spec"]["mythic_reroll_exclusion"]["_critical"] is True,
          "F24 Q-c 已标注「特殊档必须排除出 mythic_reroll」（最危险路径）")
    ck.ok(len(qc["forge_ui_impact"]["required"]) >= 4,
          "F25 Q-c UI 影响列了 %d 项" % len(qc["forge_ui_impact"]["required"]))

    # ---- 交叉 ----
    ck.ok(len(q["cross_effects_summary"]["rows"]) >= 4,
          "F26 交叉连带效应已汇总 %d 行" % len(q["cross_effects_summary"]["rows"]))
    ck.ok(len(q["works_orders_preview"]) == 8,
          "F27 Q-a/Q-b/Q-c 工单预告 8 条（实得 %d）" % len(q["works_orders_preview"]))
    ids = [w["id"] for w in q["works_orders_preview"]]
    ck.ok(len(set(ids)) == len(ids) and all(i.startswith("W6-Q") for i in ids),
          "F28 工单编号唯一且均以 W6-Q 开头")

    a = q["assertions_for_checker"]
    ck.ok(len(a) == 12, "F29 Q 组断言 12 条（实得 %d）" % len(a))
    prefixes = [x["id"][:2] for x in a]
    ck.ok(prefixes.count("QA") == 2 and prefixes.count("QB") == 5 and prefixes.count("QC") == 5,
          "F30 断言分布 QA×2 / QB×5 / QC×5（实得 QA%d/QB%d/QC%d）"
          % (prefixes.count("QA"), prefixes.count("QB"), prefixes.count("QC")))

    # ---- 主文档与本 JSON 同步 ----
    md_path = os.path.join(HERE, "06-特色玩法.md")
    md = read_text(md_path)
    if md is None:
        ck.ok(False, "F31 无法读取 06-特色玩法.md")
    else:
        ck.ok("Q-a / Q-b / Q-c" in md and "已拍板" in md,
              "F31 主文档已包含 Q-a/Q-b/Q-c 已拍板小节")
        ck.ok("半重铸" in md, "F32 主文档已写入「半重铸」")
        ck.ok("abyss_shard" in md and "tower_sigil" in md,
              "F33 主文档已写入两种专属材料键")
        ck.ok("推翻骨架建议" in md or "推翻" in md,
              "F34 主文档已标注 Q-b 推翻了骨架建议")


# =============================================================================
# G 组 —— S1–S9 拍板落地（塔 / 深渊 / 特殊装备产出）
# =============================================================================

OBJECTIVE_KEYS = ["clear_all", "kill_elite", "kill_boss", "survive", "collect", "reach_exit"]
BUDGETS_IN_05 = {40, 50, 54, 55, 56, 58, 60, 62, 64, 66, 68, 70, 72, 76, 84}


def group_g(data, ck):
    ck.group("G. S1–S9 拍板落地（塔 / 深渊 / 特殊装备产出）")

    tw, ab, sl = data["tower"], data["abyss"], data["sloot"]
    for name, obj in [("06-tower.json", tw), ("06-abyss.json", ab), ("06-special-loot.json", sl)]:
        ck.ok(obj is not None, "G0 %s 存在且可解析" % name)
    if not (tw and ab and sl):
        return

    # ---------- 塔 ----------
    rows = tw["layer_table"]["rows"]
    ck.ok(len(rows) == 30, "G1 塔层数 == 30（实得 %d）" % len(rows))
    ck.ok([x["layer"] for x in rows] == list(range(1, 31)), "G2 layer 连续 1..30")

    bosses = [x["layer"] for x in rows if x["is_boss"]]
    ck.ok(bosses == [5, 10, 15, 20, 25, 30],
          "G3 BOSS 层 == {5,10,15,20,25,30}（实得 %s）" % bosses)

    # monster_level 公式
    import math
    formula_ok = all(x["monster_level"] == max(1, min(20, math.ceil(x["layer"] / 30 * 20)))
                     for x in rows)
    ck.ok(formula_ok, "G4 monster_level == clampi(ceil(N/30*20),1,20)")
    ck.ok(all(1 <= x["monster_level"] <= 20 for x in rows), "G5 monster_level ∈ [1,20]")

    tiers = [x["difficulty_tier"] for x in rows]
    ck.ok(all(0 <= t <= 4 for t in tiers), "G6 difficulty_tier ∈ [0,4] (TIER_COUNT-1)")
    ck.ok(tiers == sorted(tiers), "G7 difficulty_tier 单调不减")

    obj_ok = all(x["objective"] in OBJECTIVE_KEYS for x in rows)
    ck.ok(obj_ok, "G8 objective 全部 ∈ OBJECTIVE_KEYS（6 种，无大小写错误）")

    t_ok = all((x["normal_ticket"] > 0) == (x["layer"] <= 15) for x in rows)
    ck.ok(t_ok, "G9 普通票只在层 1–15 产出")
    k_ok = all(x["advanced_key"] > 0 for x in rows if x["layer"] >= 16)
    ck.ok(k_ok, "G10 高级钥匙只在层 16–30 产出（每层 >= 1）")

    # step_summary 一致性
    ss = tw["step_summary"]["rows"]
    ck.ok(len(ss) == 6, "G11 step_summary 共 6 个台阶")
    ss_bosses = [x["boss"] for x in ss]
    row_bosses = [x["boss_id"] for x in rows if x["is_boss"]]
    ck.ok(ss_bosses == row_bosses, "G12 step_summary 与 layer_table 的 boss 序列一致")
    ck.ok(all(ss[i]["boss"] != ss[i + 1]["boss"] for i in range(len(ss) - 1)),
          "G13 相邻台阶 BOSS 不重复（必换）")
    affixes = [x["unlock_affix"] for x in ss]
    ck.ok(len(set(affixes)) == 6, "G14 6 个台阶各解锁 1 条专属词缀（唯一）")

    ck.ok(tw["layout"]["seed_mode"] == "fixed", "G15 塔 layout.seed_mode == fixed")
    ck.ok(all("layout" not in x or "cells" not in x["layout"] for x in rows),
          "G16 塔层数据不含 layout.cells（与固定 seed 不可并存）")

    bad_budget = [x["budget"] for x in rows if x["budget"] not in BUDGETS_IN_05]
    ck.ok(not bad_budget, "G17 塔层 budget 全部取自 05-levels.json 既有集合（异常：%s）" % bad_budget)

    # ---------- 深渊 ----------
    ds = ab["dungeons"]
    ck.ok(len(ds) == 3, "G18 深渊 3 个（实得 %d）" % len(ds))
    ck.ok([x["chapter"] for x in ds] == [1, 2, 3], "G19 三副本对应章节 1/2/3")
    ck.ok(all(len(x["rooms"]) == 3 for x in ds), "G20 每副本 3 房间")
    ck.ok(all([r["room"] for r in x["rooms"]] == [1, 2, 3] for x in ds), "G21 房间序号 1/2/3")

    costs = [(x["entry_cost"]["item"], x["entry_cost"]["amount"]) for x in ds]
    ck.ok(costs == [("ticket_normal", 2), ("ticket_normal", 3), ("key_advanced", 1)],
          "G22 消耗分级 == 票×2 / 票×3 / 钥匙×1（实得 %s）" % str(costs))

    ck.ok(all(x["rooms"][2]["objective"] == "kill_boss" for x in ds), "G23 每副本第 3 房间为 kill_boss")
    ck.ok(all("boss_id" in x["rooms"][2] for x in ds), "G24 每副本 BOSS 房间含 boss_id")

    diver_ok = all(len({r["objective"] for r in x["rooms"]}) >= 2 for x in ds)
    ck.ok(diver_ok, "G25 每副本房间目标 >= 2 种（防退化成「打三波怪」）")

    aff_total = sum(len(x["exclusive_affix_ids"]) for x in ds)
    ck.ok(all(len(x["exclusive_affix_ids"]) == 4 for x in ds),
          "G26 每副本 4 条专属词缀（共 12 条，实得 %d）" % aff_total)
    all_ab_aff = [a for x in ds for a in x["exclusive_affix_ids"]]
    ck.ok(len(set(all_ab_aff)) == 12, "G27 12 条深渊专属词缀 id 唯一")

    tabs = ab["drop_tables"]["tables"]
    ck.ok(len(tabs) == 2, "G28 深渊掉落表 2 张")
    ck.ok(all(len(t["rarity_weights"]) == 10 for t in tabs), "G29 深渊表 rarity_weights 长度均为 10")
    ck.ok(all(abs(sum(t["rarity_weights"]) - 100.0) < 0.001 for t in tabs),
          "G30 深渊表权重和均为 100")
    ck.ok(all(t["rarity_weights"][9] == 0 for t in tabs),
          "G31 深渊表第 9 位（special_tower）均为 0（深渊不掉塔装）")
    ck.ok(tabs[1]["rarity_weights"][8] > 0,
          "G32 abyss_boss 表第 8 位（special_abyss）> 0（否则深渊装永不掉落）")

    ck.ok(ab["decisions"]["S6"]["repeatable"] is True, "G33 深渊可重复刷")
    ck.ok(ab["decisions"]["S6"]["attempt_limit"] is None, "G34 深渊无次数限制")
    ck.ok(all(x["layout"]["seed_mode"] == "fixed" for x in ds), "G35 深渊布局亦为固定 seed")

    # ---------- 特殊装备产出 ----------
    ea = sl["exclusive_affixes"]
    groups = {"tower": ea["tower"], "abyss_verdant": ea["abyss_verdant"],
              "abyss_molten": ea["abyss_molten"], "abyss_throne": ea["abyss_throne"]}
    total = sum(len(v) for v in groups.values())
    ck.ok(total == 18, "G36 专属词缀共 18 条（塔 6 + 深渊 12，实得 %d）" % total)
    ck.ok(len(ea["tower"]) == 6, "G37 塔专属词缀 6 条")

    all_aff = [a for v in groups.values() for a in v]
    ids = [a["id"] for a in all_aff]
    ck.ok(len(set(ids)) == 18, "G38 18 条 id 全局唯一")

    src_ok = all(a.get("source") in groups for a in all_aff)
    ck.ok(src_ok, "G39 全部词缀 `source` 合法（tower/abyss_*）")
    ck.ok(all(a["min_rarity"] == 8 for a in all_aff),
          "G40 全部词缀 min_rarity == 8（否则低档装备会抽到专属词缀）")
    ck.ok(all(a["position"] in ("prefix", "suffix") for a in all_aff),
          "G41 position 用字符串（非 0/1）")
    ck.ok([a["unlock_step"] for a in ea["tower"]] == [1, 2, 3, 4, 5, 6],
          "G42 塔 6 条的 unlock_step == 1..6")
    ck.ok("_stats_warning" in ea,
          "G43 已标注 stat 键需与 stat_calculator 白名单核对（防静默脱钩）")

    ug = sl["uniqueness"]
    ck.ok(len(ug["group_definition"]["tower_groups"]) == 3, "G44 塔唯一组 3 个")
    ck.ok(len(ug["group_definition"]["abyss_groups"]) == 3, "G45 深渊唯一组 3 个")
    ck.ok(ug["group_definition"]["_count"] == 6, "G46 唯一组共 6 个")
    ck.ok("append-only" in ug["save_side"]["_critical"],
          "G47 已标注唯一列表 append-only（Q-b：分解不释放）")
    ck.ok("回退" in ug["drop_gate"]["_warn"],
          "G48 已登记「唯一组全获得」回退分支（否则池空静默不掉落）")

    st = sl["special_tags"]["rows"]
    ck.ok(len(st) == 2, "G49 special_tags 2 行")
    ck.ok([x["rarity"] for x in st] == [8, 9], "G50 两档 rarity 8/9")
    ck.ok([x["beam_shape_index"] for x in st] == [8, 9], "G51 beam_shape_index 8/9")
    ck.ok(all(x["beam_height"] == 48 for x in st), "G52 两档 beam_height 均为 48")

    nr = sl["drop_fx"]["new_requirements"]
    ck.ok(len(nr) == 5, "G53 drop_fx 新需求 5 项（实得 %d）" % len(nr))
    ck.ok(any("rare_loot_spawned" in x["content"] for x in nr),
          "G54 FX-5 关联 `rare_loot_spawned` 死钩子")
    ck.ok("禁止运行时旋转" in sl["drop_fx"]["beam_shape_spec"]["_constraint"],
          "G55 已标注「禁止运行时旋转」约束")

    ep_sites = " ".join(x["site"] + x["action"] for x in sl["eng_patch"]["items"])
    ck.ok("_draw_beam" in ep_sites, "G56 eng_patch 已登记 `_draw_beam` 需按 shape 分支")
    ck.ok("source" in ep_sites and "AffixData" in ep_sites,
          "G57 eng_patch 已登记 AffixData 需扩 `source` 字段")

    ao = sl["asset_orders"]
    ck.ok(all(k in ao for k in ["fx", "audio", "ui", "material_icons"]),
          "G58 asset_orders 含 fx/audio/ui/material_icons 四类")
    ck.ok("PALETTE_ALL" in ao["_palette_warning"],
          "G59 素材已标注色板量化要求")

    # ---------- 塔/深渊 eng_patch 的 hub 三处同步 ----------
    for key, label in [("tower", "塔"), ("abyss", "深渊")]:
        ep = tw["eng_patch"]["items"] if key == "tower" else ab["eng_patch"]["items"]
        blob = " ".join(x["site"] + x["action"] for x in ep)
        ck.ok("PANEL_IDS" in blob, "G60%d %s已登记 PANEL_IDS 同步" % (0 if key == "tower" else 1, label))
        ck.ok("ConfigLoader" in blob,
              "G61%d %s已登记「ConfigLoader 需加载数据」（否则静默不存在）" % (0 if key == "tower" else 1, label))

    # ---------- 断言条数 ----------
    ck.ok(len(tw["assertions_for_checker"]) == 15, "G62 塔断言 15 条")
    ck.ok(len(ab["assertions_for_checker"]) == 17, "G63 深渊断言 17 条")
    ck.ok(len(sl["assertions_for_checker"]) == 18, "G64 特殊装备产出断言 18 条")


# =============================================================================
# E 组 —— 工程侧漂移检测（仅 --repo）
# =============================================================================

def read_text(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def group_e(data, ck, repo):
    ck.group("E. 工程侧漂移检测（--repo）")

    def p(rel):
        return os.path.join(repo, rel.replace("/", os.sep))

    # E1: RARITY_COUNT 现值
    gc = read_text(p("game/scripts/core/game_constants.gd"))
    if gc is None:
        ck.ok(False, "E0 无法读取 game_constants.gd")
        return
    m = re.search(r"const RARITY_COUNT:\s*int\s*=\s*(\d+)", gc)
    now_count = int(m.group(1)) if m else -1
    ck.ok(now_count == RARITY_COUNT_NOW,
          "E1 RARITY_COUNT 现为 %d（S12 目标 10，属已登记工单）" % now_count)

    # E2: SAVE_VERSION 现值
    m = re.search(r"const SAVE_VERSION:\s*int\s*=\s*(\d+)", gc)
    now_sv = int(m.group(1)) if m else -1
    ck.ok(now_sv == 5,
          "E2 SAVE_VERSION 现为 %d（B4-4 已落地 5；S10 目标改 6，属已登记工单）" % now_sv)

    # E3: 现存 15 个定长数组是否都是 8 项（确认扩容工作量）
    checks = {
        "RARITY_BEAM_HEIGHTS": BEAM_HEIGHTS_NOW,
        "RARITY_PREFIX_LIMIT": PREFIX_NOW,
        "RARITY_SUFFIX_LIMIT": SUFFIX_NOW,
    }
    for cname, expected in checks.items():
        m = re.search(r"const %s:\s*Array\[\w+\]\s*=\s*\[([^\]]+)\]" % cname, gc)
        if m:
            vals = [int(v) for v in re.findall(r"-?\d+", m.group(1))]
            ck.ok(vals == expected,
                  "E3 %s 现为 8 项且与策划副本一致" % cname)
        else:
            ck.ok(False, "E3 %s 未在 game_constants.gd 找到" % cname)

    # E4: 三处硬编码 8 当前确实存在（确认工单必要）
    for rel, pattern, desc in HARDCODED_8_SITES:
        txt = read_text(p(rel))
        if txt is None:
            ck.ok(False, "E4 无法读取 %s" % rel)
            continue
        hits = [i + 1 for i, ln in enumerate(txt.splitlines()) if re.search(pattern, ln)]
        ck.ok(bool(hits), "E4 %s 仍含硬编码 8（%s；命中行 %s）" % (rel, desc, hits))

    # E5: boss_phase_controller 现为 4 阶段
    bpc = read_text(p("game/scripts/enemies/boss_phase_controller.gd"))
    if bpc is None:
        ck.ok(False, "E5 无法读取 boss_phase_controller.gd")
    else:
        ck.ok("0.75, 0.5, 0.25" in bpc,
              "E5 DEFAULT_THRESHOLDS 现为 [0.75, 0.5, 0.25]（S11 目标 [0.6]）")
        ck.ok("Ⅰ" in bpc and "Ⅳ" in bpc,
              "E5 PHASE_NAMES 现含 Ⅳ（S11 目标仅 Ⅰ/Ⅱ）")
        ck.ok("1, 4" in bpc or "1,4" in bpc,
              "E5 current_phase clamp 现为 (1,4)（S11 目标 (1,2)）")

    # E6: bosses.json 现为 4 阶段
    bj = read_text(p("game/data/bosses/bosses.json"))
    if bj is None:
        ck.ok(False, "E6 无法读取 bosses.json")
    else:
        ck.ok(bj.count('"phase_count": 4') == 2,
              "E6 bosses.json 两 BOSS 均为 4 阶段（S11 目标 2）")
        ck.ok("arena_change" not in bj,
              "E6 bosses.json 尚无 arena_change 字段（S11 需新增）")

    # E7: 门票/爬塔在 scripts 内仍零命中
    hits = 0
    for root, _dirs, files in os.walk(p("game/scripts")):
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            txt = read_text(os.path.join(root, fn)) or ""
            if re.search(r"\btickets?\b|\btower\b|\babyss\b|\bdungeon\b", txt, re.I):
                hits += 1
    ck.ok(hits == 0, "E7 scripts 内门票/塔/深渊仍零命中（实得 %d 个文件）" % hits)

    # E8: verify_boss63 的 4 阶段断言仍存在
    vb = read_text(p("game/tools/verify_boss63.gd"))
    if vb is None:
        ck.ok(False, "E8 无法读取 verify_boss63.gd")
    else:
        ck.ok("== 4" in vb, "E8 verify_boss63 仍含 == 4 阶段断言（工单必要）")

    # E9: 底材 rarity_max 最大值仍为 7
    max_rmax = -1
    eqdir = p("game/data/equipment")
    if os.path.isdir(eqdir):
        idx_map = {k: i for i, k in enumerate(
            ["common", "magic", "rare", "epic", "legendary",
             "mythic", "set", "hidden", "special_abyss", "special_tower"])}
        for fn in os.listdir(eqdir):
            if not fn.endswith(".json"):
                continue
            try:
                with open(os.path.join(eqdir, fn), "r", encoding="utf-8") as f:
                    arr = json.load(f)
            except Exception:
                continue
            if not isinstance(arr, list):
                continue
            for t in arr:
                rmax = t.get("rarity_max")
                if isinstance(rmax, str):
                    rmax = idx_map.get(rmax, -1)
                if isinstance(rmax, int):
                    max_rmax = max(max_rmax, rmax)
    ck.ok(max_rmax == 7,
          "E9 底材 rarity_max 最大仍为 %d（S12 需新增 8/9 档底材，否则空池静默返回 null）" % max_rmax)


# =============================================================================
# main
# =============================================================================

def main():
    ap = argparse.ArgumentParser(description="第六步 特色玩法 校验")
    ap.add_argument("--repo", default=None,
                    help="工程根目录（如 D:/七傳說）；给出时额外跑 E 组漂移检测")
    args = ap.parse_args()

    print("=" * 70)
    print("第六步「特色玩法」校验  |  S10 / S11 / S12 + Q-a / Q-b / Q-c")
    print("=" * 70)

    data = load_all()
    ck = Checker()

    group_a(data, ck)
    group_b(data, ck)
    group_c(data, ck)
    group_d(data, ck)
    group_f(data, ck)
    group_g(data, ck)
    if args.repo:
        if not os.path.isdir(args.repo):
            print("\n[!] --repo 目录不存在：%s" % args.repo)
        else:
            group_e(data, ck, args.repo)

    print("\n" + "=" * 70)
    print("通过 %d / 失败 %d" % (ck.passed, ck.failed))
    if ck.failures:
        print("\n失败明细：")
        for f in ck.failures:
            print("  - %s" % f)
    print("=" * 70)
    return 0 if ck.failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
