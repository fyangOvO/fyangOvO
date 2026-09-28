#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第三步「装备特色玩法 & 技能联动」策划校验脚本

覆盖 03-装备特色玩法.md §7.2 的 12 条断言（T1–T12）：
  T1-T3   31 条传奇特效的 trigger / effect / slot 合法性
  T4      10 个 trigger 每个都有落点
  T5      12 个 effect_type 每个都有执行方
  T6-T7   6 个套装 effect_id 有定义 + 无重复
  T8      元素口径：elemental_damage 仅对非 physical 生效
  T9-T10  CDR / 减耗 clamp 红线
  T11     召唤上限
  T12     特效 damage_pct 红线

用法：
  python 03-check_third_step.py                # 全量校验
  python 03-check_third_step.py --draft        # 把「待实现」项降级为 WARN（策划阶段用）
"""
import json
import os
import sys
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.abspath(os.path.join(HERE, "..", "..", "..", "game"))

DRAFT = "--draft" in sys.argv

PASS, FAIL, WARN = [], [], []


def check(cond, msg, draft_ok=False):
    """draft_ok=True 表示「该项属于待实现工程改动，策划阶段失败不算错」。"""
    if cond:
        PASS.append(msg)
    elif draft_ok and DRAFT:
        WARN.append(msg)
    else:
        FAIL.append(msg)


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# =============================================================================
# 载入真实工程数据
# =============================================================================
FX_PATH = os.path.join(GAME, "data", "legendary_effects", "legendary_effects.json")
SETS_PATH = os.path.join(GAME, "data", "sets", "sets.json")
SKILLS_PATH = os.path.join(GAME, "data", "skills", "skills.json")

missing_src = [p for p in (FX_PATH, SETS_PATH) if not os.path.isfile(p)]
if missing_src:
    print("!! 找不到工程数据源：")
    for p in missing_src:
        print("   ", p)
    sys.exit(2)

fx_raw = load(FX_PATH)
FX = fx_raw["effects"] if isinstance(fx_raw, dict) else fx_raw
FX_META = fx_raw.get("_meta", {}) if isinstance(fx_raw, dict) else {}

SETS_RAW = load(SETS_PATH)
SETS = SETS_RAW if isinstance(SETS_RAW, list) else SETS_RAW.get("sets", [])

# 策划产出
WIRING = load(os.path.join(HERE, "03-legendary-wiring.json"))
SETFX = load(os.path.join(HERE, "03-set-effects.json"))
SYNERGY = load(os.path.join(HERE, "03-synergy.json"))

TRIGGER_TYPES = set(FX_META.get("trigger_types", []))
EFFECT_TYPES = set(FX_META.get("effect_types", []))

# 工程侧真实部位键
EQUIP_SLOT_KEYS = {
    "main_hand", "off_hand", "helm", "chest", "gloves", "legs", "boots",
    "amulet", "ring_a", "ring_b",
}
# 技能元素（第一步定义）
SKILL_ELEMENTS = {"physical", "fire", "cold", "lightning", "poison", "shadow"}

print("=" * 72)
print("第三步策划校验 · 03-装备特色玩法.md")
print("模式：%s" % ("DRAFT（待实现项降级为 WARN）" if DRAFT else "STRICT"))
print("=" * 72)

# =============================================================================
# T1-T3 · 31 条传奇特效合法性
# =============================================================================
bad_t, bad_e, bad_s = [], [], []
for e in FX:
    t = e.get("trigger", {}).get("type", "")
    f = e.get("effect", {}).get("type", "")
    s = e.get("slot", "")
    if t not in TRIGGER_TYPES:
        bad_t.append("%s -> trigger.%s" % (e.get("id"), t))
    if f not in EFFECT_TYPES:
        bad_e.append("%s -> effect.%s" % (e.get("id"), f))
    if s not in EQUIP_SLOT_KEYS:
        bad_s.append("%s -> slot.%s" % (e.get("id"), s))
    # stack 的 on_full 子效果也要合法
    sub = e.get("effect", {}).get("on_full", {})
    if sub and sub.get("type") not in EFFECT_TYPES:
        bad_e.append("%s -> on_full.%s" % (e.get("id"), sub.get("type")))

check(not bad_t, "T1 31 条特效 trigger.type 全部合法（违规 %d）" % len(bad_t))
check(not bad_e, "T2 31 条特效 effect.type 全部合法（违规 %d）" % len(bad_e))
check(not bad_s, "T3 31 条特效 slot 全部合法（违规 %d）" % len(bad_s))
check(len(FX) == 31, "T3b 特效池共 31 条（实测 %d）" % len(FX))

# =============================================================================
# T4 · 10 个 trigger 每个都有落点（§2.4）
# =============================================================================
sites = WIRING.get("trigger_sites", {})
used_triggers = {e.get("trigger", {}).get("type", "") for e in FX}
missing_site = sorted(t for t in used_triggers if t not in sites)
no_landing = sorted(t for t in used_triggers
                    if sites.get(t, {}).get("status") == "missing")
check(not missing_site,
      "T4 全部 trigger 都有落点声明（缺 %d：%s）" % (len(missing_site), missing_site),
      draft_ok=True)
# on_block 无落点是「待用户拍板」项，draft 下只警告
check(not no_landing,
      "T4b 无 trigger 处于 missing 状态（当前 %d：%s）" % (len(no_landing), no_landing),
      draft_ok=True)

# =============================================================================
# T5 · 12 个 effect_type 每个都有执行方（§2.6）
# =============================================================================
execs = WIRING.get("effect_executors", {})
used_effects = set()
for e in FX:
    used_effects.add(e.get("effect", {}).get("type", ""))
    sub = e.get("effect", {}).get("on_full", {}).get("type", "")
    if sub:
        used_effects.add(sub)
used_effects.discard("")
missing_exec = sorted(x for x in used_effects if x not in execs)
check(not missing_exec,
      "T5 全部 effect_type 都有执行方声明（缺 %d：%s）" % (len(missing_exec), missing_exec),
      draft_ok=True)
# 完整覆盖与 _meta.effect_types 对齐
declared = set(FX_META.get("effect_types", []))
not_used = sorted(declared - used_effects)
check(not not_used,
      "T5b 声明的 12 种 effect_type 全部被使用（未用 %d：%s）" % (len(not_used), not_used),
      draft_ok=True)

# =============================================================================
# T6-T7 · 6 个套装 effect_id
# =============================================================================
set_ids_in_data = []
for s in SETS:
    for t in s.get("tier_bonuses", []):
        eid = str(t.get("effect_id", "")).strip()
        if eid:
            set_ids_in_data.append((s.get("id"), int(t.get("pieces", 0)), eid))

defined_ids = {d["id"] for d in SETFX.get("set_effects", [])}
undefined = [(sid, pc, eid) for sid, pc, eid in set_ids_in_data if eid not in defined_ids]
check(not undefined,
      "T6 套装 effect_id 全部有策划定义（未定义 %d：%s）"
      % (len(undefined), [u[2] for u in undefined]))

dups = [i for i in defined_ids if
        len([d for d in SETFX.get("set_effects", []) if d["id"] == i]) > 1]
check(not dups, "T7 套装 effect_id 无重复定义（重复 %d）" % len(dups))
check(len(set_ids_in_data) == 6,
      "T6b 工程数据中套装 effect_id 共 6 个（实测 %d）" % len(set_ids_in_data))

# 套装档位与定义的 pieces 必须一致
piece_mismatch = []
for sid, pc, eid in set_ids_in_data:
    d = next((x for x in SETFX.get("set_effects", []) if x["id"] == eid), None)
    if d is not None and int(d.get("pieces", -1)) != pc:
        piece_mismatch.append("%s: 数据 %d 件 vs 定义 %d 件" % (eid, pc, d.get("pieces")))
check(not piece_mismatch,
      "T7b 套装 effect_id 的触发档位数与工程数据一致（不一致 %d）" % len(piece_mismatch),
      draft_ok=True)

# =============================================================================
# T8 · 元素口径（§4.2）
# =============================================================================
es = SYNERGY.get("element_scope", {})
check(es.get("rule", "").find("physical") >= 0,
      "T8 元素口径声明「仅对非 physical 技能生效」")
check(set(es.get("skill_elements", [])) == SKILL_ELEMENTS,
      "T8b 技能元素集合与第一步定义一致（声明 %d 种）" % len(es.get("skill_elements", [])))

# =============================================================================
# T9-T10 · 数值红线（策划稿声明，非工程实测）
# =============================================================================
s = SYNERGY.get("lines", [])
l3 = next((x for x in s if x.get("id") == "L3"), {})
l4 = next((x for x in s if x.get("id") == "L4"), {})
check("0.2" in str(l3.get("rule", "")), "T9 冷却缩减声明 clamp >= 0.2 秒下限")
check("clamp" in str(l4.get("rule", "")), "T10 耗蓝缩减声明 clamp >= 0 下限")

# =============================================================================
# T11-T12 · 特效数值红线（§7.1）
# =============================================================================
# T11 召唤上限：count x 理论触发频率 <= 5
SUMMON_LIMIT = 5
bad_summon = []
for e in FX:
    f = e.get("effect", {})
    if f.get("type") == "summon":
        cnt = int(f.get("count", 1))
        if cnt > SUMMON_LIMIT:
            bad_summon.append("%s -> count %d > %d" % (e.get("id"), cnt, SUMMON_LIMIT))
check(not bad_summon,
      "T11 召唤 count 不超过上限 %d（违规 %d）" % (SUMMON_LIMIT, len(bad_summon)))

# T12 damage_pct <= 5.0（含 on_full）
DMG_CAP = 5.0
bad_dmg = []
for e in FX:
    f = e.get("effect", {})
    cands = [f] + ([f.get("on_full", {})] if f.get("type") == "stack" else [])
    for c in cands:
        if c.get("type") == "deal_damage":
            pct = float(c.get("damage_pct", 0.0))
            if pct > DMG_CAP:
                bad_dmg.append("%s -> damage_pct %.2f > %.1f" % (e.get("id"), pct, DMG_CAP))
check(not bad_dmg,
      "T12 特效 damage_pct 不超过 %.1f（违规 %d：%s）" % (DMG_CAP, len(bad_dmg), bad_dmg))

# =============================================================================
# T13（附加）· 接线图与真实数据一致性
# =============================================================================
wiring_ids = {r["id"] for r in WIRING.get("effects", [])}
real_ids = {e["id"] for e in FX}
check(wiring_ids == real_ids,
      "T13 接线图 31 条与工程数据完全一致（差集 %d）"
      % len(wiring_ids.symmetric_difference(real_ids)))

# 套装特效与传奇特效不撞名
clash = sorted(defined_ids & real_ids)
check(not clash, "T14 套装特效 ID 与传奇特效 ID 无撞名（撞名 %d：%s）" % (len(clash), clash))

# =============================================================================
# T15-T24 · 元素体系（2026-09-24 拍板「拆 6 个子键」后新增）
# =============================================================================
try:
    ELEM = load(os.path.join(HERE, "03-elements.json"))
    _have_elem = True
except Exception as _e:
    ELEM = {}
    _have_elem = False
    check(False, "T15 03-elements.json 可读取（错误：%s）" % _e)

if _have_elem:
    els = ELEM.get("elements", [])
    # T15 六元素齐全且与 game_constants 一致
    elem_keys = [e["key"] for e in els]
    check(set(elem_keys) == SKILL_ELEMENTS and len(els) == 6,
          "T15 元素清单 6 种与引擎定义一致（%s）" % ",".join(elem_keys))

    # T16 非物理元素都有伤害子键
    non_phys = [e for e in els if e["key"] != "physical"]
    no_sub = [e["key"] for e in non_phys if not e.get("damage_subkey")]
    check(not no_sub,
          "T16 5 个非物理元素都有伤害子键（缺 %d：%s）" % (len(no_sub), no_sub))

    # T17 物理不建子键（与 pct_attack 重叠）
    phys = next((e for e in els if e["key"] == "physical"), {})
    check(phys.get("damage_subkey") is None,
          "T17 物理元素不建伤害子键（避免与 pct_attack 双重加成）")

    # T18 子键命名规范
    bad_name = [e["damage_subkey"] for e in non_phys
                if e.get("damage_subkey") != "elemental_damage_" + e["key"]]
    check(not bad_name,
          "T18 子键命名符合 elemental_damage_<元素>（违规 %d：%s）" % (len(bad_name), bad_name))

    # T19 每个非物理元素都有抗性键
    no_res = [e["key"] for e in non_phys if not e.get("resist_key")]
    check(not no_res,
          "T19 5 个非物理元素都有抗性键（缺 %d：%s）" % (len(no_res), no_res))

    # T20 必修缺口清单（shadow_resist 等）
    gaps = ELEM.get("gaps", [])
    must = [g for g in gaps if g.get("must_fix")]
    check(len(must) == 3,
          "T20 必修缺口共 3 项（实测 %d：%s）"
          % (len(must), [g["id"] for g in must]))
    # shadow 抗性缺口必须被标记
    shadow = next((e for e in els if e["key"] == "shadow"), {})
    check("MISSING" in str(shadow.get("resist_status", "")),
          "T20b shadow 抗性缺口已被显式标记（防遗漏）")

    # T21 素材命名规范完整
    naming = ELEM.get("naming", {})
    need_keys = {"element_icon", "resist_icon", "ailment_icon",
                 "attach_layer", "skill_frame", "affix_badge"}
    miss_naming = sorted(need_keys - set(naming.keys()))
    check(not miss_naming,
          "T21 6 类元素素材命名规范齐全（缺 %d：%s）" % (len(miss_naming), miss_naming))

    # T22 素材路径铁律必须写明
    rule = ELEM.get("_meta", {}).get("asset_path_rule", "")
    check("TEX" in rule or "路径A" in rule,
          "T22 已写明「UI 图标必须登记 TEX 表」的路径铁律")

    # T23 工单齐全：E 系列 >= 8，M 系列 >= 8，且 M7 注册项必须在
    wo = ELEM.get("workorders", {})
    e_wo, m_wo = wo.get("E", []), wo.get("M", [])
    check(len(e_wo) >= 8 and len(m_wo) >= 8,
          "T23 元素工单齐全（E=%d / M=%d）" % (len(e_wo), len(m_wo)))
    has_m7 = any("TEX" in str(x.get("task", "")) or x.get("id") == "M7" for x in m_wo)
    check(has_m7, "T23b M7（注册进 TEX 表）在工单内 —— 防「素材做了取不到」")

    # T24 素材优先级：P0 必须存在
    assets = ELEM.get("assets", {})
    p0 = [a for a in assets.get("general", []) if a.get("priority") == "P0"]
    check(len(p0) >= 2,
          "T24 元素素材有 P0 项（%d 项）" % len(p0))

# =============================================================================
# T25-T27 · 四项决策落地（2026-09-24）
# =============================================================================
dec = WIRING.get("_meta", {}).get("decisions_2026_09_24", {})
check(len(dec) == 4, "T25 四项决策已写入接线 JSON（%d 项）" % len(dec))

# on_block 不再是 missing
ob = sites.get("on_block", {})
check(ob.get("status") != "missing",
      "T26 on_block 已从 missing 修正为 %s（格挡系统本已存在）" % ob.get("status"))
check("格挡" in str(ob.get("note", "")) or "block" in str(ob.get("site", "")).lower(),
      "T26b on_block 落点指向格挡事件（修正首稿误判）")

# 元素拆键决策已记录
check("element_split" in dec, "T27 元素拆键决策已记录")

# =============================================================================
# 输出
# =============================================================================
print()
for m in PASS:
    print("  [PASS] %s" % m)
for m in WARN:
    print("  [WARN] %s" % m)
for m in FAIL:
    print("  [FAIL] %s" % m)

print()
print("=" * 72)
print("结果：%d 通过 / %d 失败%s" % (len(PASS), len(FAIL),
                              (" / %d 待实现(WARN)" % len(WARN)) if WARN else ""))

# 关键情报汇总
summary = WIRING.get("summary", {})
print()
print("【31 条特效接线现状】")
print("  可立即接线      : %d" % summary.get("ready_to_wire", 0))
print("  需埋点          : %d" % summary.get("need_hook", 0))
print("  需核实落点      : %d" % summary.get("need_verify", 0))
print("  完全没有落点    : %d" % summary.get("missing_landing", 0))
print("  依赖新系统      : %d" % summary.get("need_new_system", 0))
print("  ⇒ 先接通不需要新系统的 %d 条，剩下 %d 条分期"
      % (len(FX) - summary.get("need_new_system", 0), summary.get("need_new_system", 0)))
print("=" * 72)

sys.exit(1 if FAIL else 0)
