#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第二步「装备属性体系」校验脚本。

校验对象 = 现状数据 + 第二步草案：
  A. 词缀池覆盖率（每条词缀至少 1 池 / 每池至少 1 底材引用）
  B. 前后缀上限不变式（PREFIX[i] + SUFFIX[i] == AFFIX_RANGE[i].y，逐 8 档）
  C. stat_key 白名单（防「死钩子」再产生）
  D. 数值区间合法性（min < max、decimals、weight）
  E. 第二步新增项的完整性（15 条新词缀 / 4 个新池 / 4 条权重patch）
  F. 与第一步的口径一致性（01-branches.json 的 reset_cost_gold、01-runes.json 的语义说明）

用法：
    python 02-check_affix_pool.py            # 校验现状（game/data）
    python 02-check_affix_pool.py --draft    # 连同第二步草案一起校验

退出码：0 = 全通过；1 = 有失败项
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
_HERE = Path(__file__).resolve().parent
_REPO = _HERE.parent.parent.parent          # deliverables/gstack/策划案 -> 仓库根
_GAME = _REPO / "game"

AFFIX_DIR = _GAME / "data" / "affixes"
POOLS_FILE = _GAME / "data" / "affix_pools" / "pools.json"
EQUIP_DIR = _GAME / "data" / "equipment"
CONSTANTS_FILE = _GAME / "scripts" / "core" / "game_constants.gd"

DRAFT_AFFIXES = _HERE / "02-affixes.json"
RUNES_FILE = _HERE / "01-runes.json"
BRANCHES_FILE = _HERE / "01-branches.json"

EQUIP_FILES = [
    "weapons.json", "armor.json", "jewelry.json",
    "set_pieces_emberpath.json", "set_pieces_frostbite.json", "set_pieces_oathkeeper.json",
    "special_abyss.json", "special_tower.json",
]

# ---------------------------------------------------------------------------
# 期望值（来自 game_constants.gd，改动时两处一起改）
# ---------------------------------------------------------------------------
# RARITY_AFFIX_RANGE / RARITY_PREFIX_LIMIT / RARITY_SUFFIX_LIMIT
EXPECT_RANGE = [(0, 0), (1, 2), (3, 4), (4, 5), (5, 6), (6, 7), (3, 5), (5, 6)]
EXPECT_PREFIX = [0, 1, 2, 3, 3, 4, 2, 3]
EXPECT_SUFFIX = [0, 1, 2, 2, 3, 3, 3, 3]
RARITY_NAMES = ["白", "蓝", "黄", "紫", "橙", "红", "绿", "彩"]

# 已知合法 stat_key（= StatKey 语义 + FINAL_KEYS + 第二步新增 + 局内键）
KNOWN_STAT_KEYS = {
    # 主属性 / 基础
    "flat_hp", "flat_attack", "flat_armor", "pct_hp", "pct_attack", "pct_armor",
    # 攻击
    "crit_chance", "crit_damage", "attack_speed", "elemental_damage",
    "armor_pierce", "armor_penetration",  # armor_penetration 过渡期保留（应逐步清空）
    "all_element_damage", "damage_vs_ailment",
    # 防御
    "dodge", "block_chance", "life_regen",
    "fire_resist", "cold_resist", "lightning_resist", "poison_resist",
    "shadow_resist", "physical_resist", "all_resist",
    # 资源
    "max_resource", "resource_regen", "skill_cost_reduction", "cooldown_reduction",
    "pickup_radius", "move_speed",
    # 特殊
    "magic_find", "xp_gain", "gold_gain", "thorns", "life_on_hit", "kill_heal",
    "all_attributes", "echo_strike", "skill_level",
    # 穿透
    "elemental_penetration", "resist_penetration",
    # 异常状态（待 AilmentSystem）
    "burn_damage", "chill_damage", "poison_damage", "shock_damage", "curse_damage",
    "ailment_duration", "ailment_chance", "ailment_effect",
    # 局内（阶段 4）
    "life_steal", "damage_taken", "regen_pct_hp", "shield_pct_hp",
}

# 通用池 —— min_rarity >= 3 的词缀不得出现在此（约束 C3）
GENERIC_POOLS = {"weapon_generic", "armor_generic", "jewelry_generic"}

# 第二步期望新增数量
EXPECT_NEW_AFFIXES = 15
EXPECT_NEW_POOLS = 4

# ---------------------------------------------------------------------------
# 结果统计
# ---------------------------------------------------------------------------
_fail: list[str] = []
_pass = 0


def ok(msg: str) -> None:
    global _pass
    _pass += 1
    print(f"  [OK]   {msg}")


def fail(msg: str) -> None:
    _fail.append(msg)
    print(f"  [FAIL] {msg}")


def check(cond: bool, msg: str) -> None:
    (ok if cond else fail)(msg)


def warn(msg: str, details: list[str] | None = None) -> None:
    """警告级断言：输出 [WARN] 但不计入失败。

    依据 `02-装备属性.md` §1.5 裁定 / §4.4 C3 降级说明 / §8.3 V4：
    约束 C3（min_rarity>=3 的词缀不得进通用池）已由**硬约束降为软建议**。
    """
    print(f"  [WARN] {msg}")
    for d in (details or []):
        print(f"          提示: {d}")


def load(path: Path):
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def as_list(data, key_hint: str | None = None) -> list:
    """本项目 JSON 顶层结构不统一：list / {"pools":[]} / {"effects":[]} / {"items":[]}。"""
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and key_hint and key_hint in data:
        return data[key_hint]
    if isinstance(data, dict):
        for key in ("items", "effects", "runes", "templates", "affixes", "pools"):
            if key in data and isinstance(data[key], list):
                return data[key]
    return []


# ---------------------------------------------------------------------------
# A. 词缀池覆盖率
# ---------------------------------------------------------------------------
def section_a(affixes: dict, pools: dict, equip_slots: dict) -> None:
    print("\n--- A. 词缀池覆盖率 ---")

    # A1 每条词缀至少出现在 1 个池
    in_any_pool = set()
    for pool in pools.values():
        in_any_pool.update(pool)
    orphans = sorted(set(affixes) - in_any_pool)
    check(not orphans, f"A1 每条词缀至少 1 池（孤儿词缀 {len(orphans)} 条）")
    if orphans:
        for a in orphans:
            print(f"          孤儿: {a}")

    # A2 每池至少 1 件底材引用
    referenced = set()
    for fname, items in equip_slots.items():
        for it in items:
            referenced.update(it.get("affix_pool_ids") or [])
    dead_pools = sorted(set(pools) - referenced)
    check(not dead_pools, f"A2 每池至少 1 底材引用（死池 {len(dead_pools)} 个）")
    if dead_pools:
        for p in dead_pools:
            print(f"          死池: {p}")

    # A3 池内 affix_id 必须真实存在
    missing = []
    for pid, ids in pools.items():
        for aid in ids:
            if aid not in affixes:
                missing.append(f"{pid} -> {aid}")
    check(not missing, f"A3 池内 affix_id 全部存在（缺失 {len(missing)} 条）")
    for m in missing:
        print(f"          缺失: {m}")

    # A4 通用池不得含 min_rarity >= 3（约束 C3 —— 🟡 软建议，警告级）
    #
    # 依据 `02-装备属性.md` §1.5 裁定 / §4.4 C3 降级说明 / §8.3 V4：
    #   `add_skill_level`（min_rarity=3）出现在 2 个通用池属【裁定保留】——
    #   其权重仅 12（全表最低），实际出现概率已极低，且「任何部位都可能出技能等级」
    #   是明确的设计意图。故 C3 由硬约束降为软建议，本项输出 WARN 且不计入失败。
    violations = []
    for pid in GENERIC_POOLS & set(pools):
        for aid in pools[pid]:
            info = affixes.get(aid)
            if info and info.get("min_rarity", -1) >= 3:
                violations.append(f"{pid} -> {aid} (min_rarity={info['min_rarity']})")
    warn(f"A4 通用池无 min_rarity>=3 词缀（C3 软建议，违规 {len(violations)} 条）", violations)

    # A5 底材 base_stats 的键必须合法（附錄 B.8 发现①：hammer_glacier 用了 legacy 键）
    bad_base = []
    for fname, items in equip_slots.items():
        for it in items:
            for k in (it.get("base_stats") or {}):
                if k not in KNOWN_STAT_KEYS:
                    bad_base.append(f"{it.get('id')} -> base_stats.{k}")
                elif k == "armor_penetration":
                    bad_base.append(f"{it.get('id')} -> base_stats.{k} (legacy 键，应改 armor_pierce)")
    check(not bad_base, f"A5 底材 base_stats 键全部合法（违规 {len(bad_base)} 条）")
    for b in bad_base:
        print(f"          违规: {b}")


# ---------------------------------------------------------------------------
# B. 前后缀上限不变式
# ---------------------------------------------------------------------------
def section_b() -> None:
    print("\n--- B. 前后缀上限不变式（GDD 3.2.3 权威表）---")
    check(len(EXPECT_RANGE) == 8 and len(EXPECT_PREFIX) == 8 and len(EXPECT_SUFFIX) == 8,
          "B0 三张表长度均为 8（RARITY_COUNT）")
    bad = []
    for i in range(8):
        if EXPECT_PREFIX[i] + EXPECT_SUFFIX[i] != EXPECT_RANGE[i][1]:
            bad.append(f"{RARITY_NAMES[i]} {EXPECT_PREFIX[i]}+{EXPECT_SUFFIX[i]}"
                       f" != {EXPECT_RANGE[i][1]}")
    check(not bad, f"B1 不变式 前缀+后缀 == 条数上限（逐档，违规 {len(bad)}）")
    for b in bad:
        print(f"          违规: {b}")
    for i in range(8):
        print(f"          {RARITY_NAMES[i]}: {EXPECT_PREFIX[i]}前 + {EXPECT_SUFFIX[i]}后 "
              f"| 条数 {EXPECT_RANGE[i][0]}-{EXPECT_RANGE[i][1]}")


# ---------------------------------------------------------------------------
# C. stat_key 白名单（防死钩子）
# ---------------------------------------------------------------------------
def section_c(affixes: dict) -> None:
    print("\n--- C. stat_key 白名单（防死钩子）---")
    unknown = sorted({info.get("stat_key", "") for info in affixes.values()
                      if info.get("stat_key") not in KNOWN_STAT_KEYS})
    check(not unknown, f"C1 所有 stat_key 在已知白名单内（未知 {len(unknown)} 个）")
    for u in unknown:
        print(f"          未知 stat_key: {u}")

    # C2 armor_penetration 应已被统一为 armor_pierce
    legacy = [aid for aid, info in affixes.items()
              if info.get("stat_key") == "armor_penetration"]
    check(not legacy,
          f"C2 无词缀产出 legacy 键 armor_penetration（残留 {len(legacy)} 条）")
    for l in legacy:
        print(f"          待改: {l}.stat_key -> armor_pierce")


# ---------------------------------------------------------------------------
# D. 数值区间合法性
# ---------------------------------------------------------------------------
def section_d(affixes: dict) -> None:
    print("\n--- D. 数值区间合法性 ---")
    bad_range, bad_pos, bad_weight, bad_dec = [], [], [], []
    for aid, info in affixes.items():
        lo, hi = info.get("value_min"), info.get("value_max")
        if lo is None or hi is None or lo > hi:
            bad_range.append(f"{aid}: [{lo}, {hi}]")
        # ⚠️ 实测：JSON 里 position 是字符串 "prefix"/"suffix"（非 0/1）
        pos = info.get("position")
        if pos not in (0, 1, "prefix", "suffix"):
            bad_pos.append(f"{aid}: position={pos}")
        w = info.get("weight")
        if w is not None and w < 0:
            bad_weight.append(f"{aid}: weight={w}")
        dec = info.get("decimals")
        if dec is not None and dec not in (0, 1):
            bad_dec.append(f"{aid}: decimals={dec}")
    check(not bad_range, f"D1 value_min <= value_max（违规 {len(bad_range)}）")
    for b in bad_range:
        print(f"          {b}")
    check(not bad_pos, f"D2 position ∈ {{0,1,\"prefix\",\"suffix\"}}（违规 {len(bad_pos)}）")
    for b in bad_pos:
        print(f"          {b}")
    check(not bad_weight, f"D3 weight >= 0（违规 {len(bad_weight)}）")
    for b in bad_weight:
        print(f"          {b}")
    check(not bad_dec, f"D4 decimals ∈ {{0,1}}（违规 {len(bad_dec)}）")
    for b in bad_dec:
        print(f"          {b}")

    def is_prefix(v) -> bool:
        return v in (0, "prefix")

    def is_suffix(v) -> bool:
        return v in (1, "suffix")

    pfx = sum(1 for i in affixes.values() if is_prefix(i.get("position")))
    sfx = sum(1 for i in affixes.values() if is_suffix(i.get("position")))
    print(f"          分布：前缀 {pfx} / 后缀 {sfx} / 合计 {len(affixes)}")


# ---------------------------------------------------------------------------
# E. 第二步草案完整性
# ---------------------------------------------------------------------------
def section_e(draft: dict, base_affix_ids: set[str]) -> None:
    print("\n--- E. 第二步草案完整性 ---")
    new_affixes = as_list(draft, "affixes")
    check(len(new_affixes) == EXPECT_NEW_AFFIXES,
          f"E1 新增词缀数 == {EXPECT_NEW_AFFIXES}（实际 {len(new_affixes)}）")
    new_ids = [a.get("id") for a in new_affixes]
    dup = {i for i in new_ids if new_ids.count(i) > 1}
    check(not dup, f"E2 新增词缀 id 无重复（重复 {len(dup)}）")
    for d in dup:
        print(f"          重复: {d}")
    collide = sorted(set(new_ids) & base_affix_ids)
    check(not collide, f"E3 新增词缀与现有词缀不冲突（冲突 {len(collide)}）")
    for c in collide:
        print(f"          冲突: {c}")

    new_pools = as_list(draft.get("_pools_new", {}), "pools")
    check(len(new_pools) == EXPECT_NEW_POOLS,
          f"E4 新增池数 == {EXPECT_NEW_POOLS}（实际 {len(new_pools)}）")
    for p in new_pools:
        ids = p.get("affix_ids") or []
        check(len(ids) > 0, f"E5 池 {p.get('id')} 非空（{len(ids)} 条）")

    patches = as_list(draft.get("_weight_patches", {}), "patches")
    check(len(patches) == 4, f"E6 权重调整 patch == 4 条（实际 {len(patches)}）")
    for p in patches:
        check(p.get("new") is not None and p.get("old") is not None,
              f"E7 patch {p.get('id')}: {p.get('old')} -> {p.get('new')}")

    kp = as_list(draft.get("_key_patches", {}), "patches")
    has_pen = any(p.get("id") == "add_armor_penetration"
                  and p.get("new") == "armor_pierce" for p in kp)
    check(has_pen, "E8 含 add_armor_penetration -> armor_pierce 键名统一 patch")

    loot = draft.get("_loot_tables_new", {})
    lpatches = as_list(loot, "patches")
    check(len(lpatches) == 3, f"E9 掉落表 patch == 3 档（实际 {len(lpatches)}）")
    for lp in lpatches:
        has_rune = "rune_drop_chance" in lp
        has_ilvl = "item_level_spread" in lp
        check(has_rune and has_ilvl,
              f"E10 {lp.get('id')} 含 rune_drop_chance + item_level_spread")
    # 符文掉率与第一步 §11.4 对齐
    want = {"monster_normal": 0.02, "monster_elite": 0.08, "monster_boss": 0.25}
    for lp in lpatches:
        exp = want.get(lp.get("id"))
        if exp is not None:
            check(abs(float(lp.get("rune_drop_chance", -1)) - exp) < 1e-9,
                  f"E11 {lp.get('id')} rune_drop_chance == {exp}")


# ---------------------------------------------------------------------------
# F. 与第一步的口径一致性
# ---------------------------------------------------------------------------
def section_f() -> None:
    print("\n--- F. 与第一步的口径一致性 ---")

    # F1 01-branches.json 的 reset_cost_gold 必须为 0（Q5 裁定先免费）
    if BRANCHES_FILE.exists():
        br = load(BRANCHES_FILE)
        meta = br.get("_meta", {}) if isinstance(br, dict) else {}
        cost = meta.get("reset_cost_gold")
        check(cost == 0,
              f"F1 01-branches.json reset_cost_gold == 0（实际 {cost}）—— Q5 裁定先免费")
    else:
        fail("F1 01-branches.json 不存在")

    # F2 01-runes.json 的 modifier_semantics 需说明 *_pct 为带符号增量
    if RUNES_FILE.exists():
        rn = load(RUNES_FILE)
        ms = rn.get("_meta", {}).get("modifier_semantics", {})
        blob = json.dumps(ms, ensure_ascii=False)
        # 只报警告级：这是文档口径，不做硬断言
        if "带符号" in blob or "正值延长" in blob:
            ok("F2 01-runes.json modifier_semantics 已注明 *_pct 带符号语义")
        else:
            print("  [WARN] F2 01-runes.json modifier_semantics 未注明 *_pct 带符号语义"
                  "（第二步 §7.4 待落，见工单 D8）")
    else:
        fail("F2 01-runes.json 不存在")


# ---------------------------------------------------------------------------
# 加载
# ---------------------------------------------------------------------------
def collect_affixes() -> dict:
    """汇总 4 张词缀表 -> {id: info}（并附上来源文件名）。"""
    out: dict = {}
    for fname in ("attack.json", "defense.json", "resource.json", "special.json", "special_sources.json"):
        path = AFFIX_DIR / fname
        if not path.exists():
            print(f"  [WARN] 缺少 {fname}")
            continue
        for item in as_list(load(path)):
            aid = item.get("id")
            info = dict(item)
            info["_file"] = fname
            out[aid] = info
    return out


def collect_pools() -> dict:
    """pools.json -> {pool_id: [affix_id, ...]}"""
    if not POOLS_FILE.exists():
        return {}
    data = load(POOLS_FILE)
    out: dict = {}
    for p in as_list(data, "pools"):
        out[p.get("id")] = p.get("affix_ids") or []
    return out


def collect_equipment() -> dict:
    """{filename: [item, ...]}"""
    out: dict = {}
    for fname in EQUIP_FILES:
        path = EQUIP_DIR / fname
        if path.exists():
            out[fname] = as_list(load(path), "items")
    return out


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description="第二步装备属性体系校验")
    ap.add_argument("--draft", action="store_true",
                    help="连同 02-affixes.json 草案一起校验")
    args = ap.parse_args()

    print("=" * 72)
    print("第二步「装备属性体系」校验")
    print(f"仓库根: {_REPO}")
    print(f"模式: {'现状 + 草案' if args.draft else '仅现状'}")
    print("=" * 72)

    if not AFFIX_DIR.exists():
        print(f"[ERROR] 词缀目录不存在: {AFFIX_DIR}")
        return 1

    affixes = collect_affixes()
    pools = collect_pools()
    equip = collect_equipment()

    print(f"\n载入：词缀 {len(affixes)} 条 / 池 {len(pools)} 个 / "
          f"底材 {sum(len(v) for v in equip.values())} 件")

    section_a(affixes, pools, equip)
    section_b()
    section_c(affixes)
    section_d(affixes)
    section_f()

    if args.draft:
        if DRAFT_AFFIXES.exists():
            section_e(load(DRAFT_AFFIXES), set(affixes))
        else:
            fail(f"草案文件不存在: {DRAFT_AFFIXES}")

    print("\n" + "=" * 72)
    print(f"结果：{_pass} 通过 / {len(_fail)} 失败")
    if _fail:
        print("失败项：")
        for f in _fail:
            print(f"  - {f}")
    print("=" * 72)
    return 1 if _fail else 0


if __name__ == "__main__":
    sys.exit(main())
