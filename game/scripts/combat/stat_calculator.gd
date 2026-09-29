## 属性结算系统（任务 3.9 · 纯静态 class_name）
##
## 职责：装备 + 天赋 + Buff → 最终属性（任务清单 3.9）。
##   - `base_stats(level)`：裸装基础属性（GDD 6.2 成长公式 Base(L) = Base1 × (1+g)^(L-1)，
##     L1 150 HP / 12 AD / 6 ARM，g = 0.11 / 0.10 / 0.10）
##   - `sum_equipment(equipped)`：逐件装备汇总（复用 3.7 EquipmentCompare.get_total_stats）
##   - `calculate(level, equipped, buffs)`：最终结算
##     - flat 与 pct 分组；pct 乘算；all_attributes（神话全属性）乘主属性三件套
##     - 暴击 / 攻速 / 抗性 / 资源 / 幸运 / 经验 / 金币 / 拾取 / 移速 / 减耗 / 冷却 = 直接累加
##   - Buff 接口（4.3 正式接入）：buffs = {key: {"flat": {...}, "pct": {...}}}
##
## 输出键（最终属性字典，3.10 套装 / 4.x 战斗消费）：
##   **唯一权威 = 下方 `FINAL_KEYS`**（输出字典的键集与它**严格相等**，
##   由 `tools/verify_hub.gd` 断言 `stats.size() == FINAL_KEYS.size()`）。
##   分四段：① 主属性三件套（flat × pct 乘算）② 通用直接累加键
##   ③ 第三步元素专精 / 抗性 3 系 / 穿透 / 异常增伤 ④ 局内（阶段 4）附加键。
class_name StatCalculator
extends RefCounted

## GDD 6.2 裸装成长表（权威）：属性 → [Base1, g]
const BASE_GROWTH := {
	"flat_hp": [150.0, 0.11],
	"flat_attack": [12.0, 0.10],
	"flat_armor": [6.0, 0.10],
}

## 受神话「全属性」百分比加成的键（主属性三件套）
const MYTHIC_SCALED_KEYS: Array[String] = ["max_hp", "attack", "armor"]

## 最终属性键顺序（展示用）
const FINAL_KEYS: Array[String] = [
	"max_hp", "attack", "armor", "crit_chance", "crit_damage", "attack_speed",
	"elemental_damage", "all_damage", "dodge", "block_chance", "life_regen", "fire_resist",
	"cold_resist", "poison_resist", "lightning_resist",
	# 第三步补齐的抗性 3 系（3-E5 / 2-L3）：暗影 / 物理 / 全抗
	"shadow_resist", "physical_resist", "all_resist",
	"max_resource",
	"resource_regen", "skill_cost_reduction", "cooldown_reduction",
	"pickup_radius", "move_speed", "magic_find", "xp_gain", "gold_gain",
	"thorns", "life_on_hit", "kill_heal", "skill_level",
	# 第三步元素专精（3-E1 / 3-E2）：5 个非物理子键 + 全元素伤害 + 对异常增伤 + 穿透
	"elemental_damage_fire", "elemental_damage_cold", "elemental_damage_lightning",
	"elemental_damage_poison", "elemental_damage_shadow",
	"all_element_damage", "damage_vs_ailment",
	"elemental_penetration", "resist_penetration",
	# 第三步异常状态增伤（3.3；待 AilmentSystem 实装后接线）
	"burn_damage", "chill_damage", "poison_damage", "shock_damage", "curse_damage",
	"ailment_duration", "ailment_chance", "ailment_effect",
	# 局内（阶段 4）：三选一 / 祭坛 / 连杀附加键
	"armor_pierce", "life_steal", "damage_taken", "regen_pct_hp", "shield_pct_hp",
]


## 裸装基础属性（GDD 6.2 公式）
static func base_stats(level: int) -> Dictionary:
	var out := {}
	for key in BASE_GROWTH:
		var row: Array = BASE_GROWTH[key]
		out[key] = float(row[0]) * pow(1.0 + float(row[1]), max(0, level - 1))
	return out


## 逐件装备汇总（含底材 + 词缀 + 强化倍率；复用 3.7 汇总口径）
static func sum_equipment(equipped: Array[EquipmentInstance]) -> Dictionary:
	var out := {}
	for item in equipped:
		if item == null:
			continue
		var stats := EquipmentCompare.get_total_stats(item)
		for key in stats:
			out[key] = float(out.get(key, 0.0)) + float(stats[key])
	return out


## 最终结算：level + 装备 + buffs → 最终属性字典。
## 套装加成（3.10）自动并入装备汇总（SetSystem.get_bonus_stats）。
static func calculate(level: int, equipped: Array[EquipmentInstance], buffs: Dictionary = {}) -> Dictionary:
	var base := base_stats(level)
	var gear := sum_equipment(equipped)
	var set_bonus := SetSystem.get_bonus_stats(equipped)
	for key in set_bonus:
		gear[key] = float(gear.get(key, 0.0)) + float(set_bonus[key])
	# 隐藏（彩蛋）装成长加成（3.11）：growth_value 为百分数，并入 pct 键
	var growth := HiddenGrowthController.get_total_growth_bonus(equipped)
	for key in growth:
		gear[key] = float(gear.get(key, 0.0)) + float(growth[key])

	# ---- flat 汇总 ----
	var flat := {}
	for key in base:
		flat[key] = float(base[key])
	for key in gear:
		flat[key] = float(flat.get(key, 0.0)) + float(gear[key])
	# Buff flat
	for bkey in buffs:
		var b: Dictionary = buffs[bkey]
		if b.has("flat") and b["flat"] is Dictionary:
			for key in b["flat"]:
				flat[key] = float(flat.get(key, 0.0)) + float(b["flat"][key])

	# ---- pct 汇总（% 词缀为数值即百分数：0.05 = 5%）----
	# 判定：前缀 `pct_`/`ailment_` + 后缀 `_resist`/`_damage`/`_penetration` + 显式列表。
	# 后缀规则覆盖第三步新增（元素子键 `elemental_damage_*` / 穿透 `*_penetration` /
	# 异常增伤 `*_damage` / 异常 `ailment_*`），避免逐个硬编码遗漏（死钩子）。
	var pct := {}
	for key in gear:
		if (key.begins_with("pct_") or key.begins_with("ailment_")
				or key.begins_with("elemental_damage")
				or key.ends_with("_resist") or key.ends_with("_damage")
				or key.ends_with("_penetration")
				or key in [
				"crit_chance", "attack_speed",
				"dodge", "block_chance", "magic_find", "xp_gain", "gold_gain",
				"life_on_hit", "thorns", "skill_cost_reduction", "cooldown_reduction",
				"resource_regen", "move_speed", "all_attributes",
				"armor_pierce", "life_steal", "damage_taken", "regen_pct_hp",
				"shield_pct_hp", "damage_vs_ailment", "all_element_damage", "all_damage"]):
			pct[key] = float(pct.get(key, 0.0)) + float(gear[key])
	# Buff pct（嵌套：buffs = {buff_id: {"pct": {...}}}）
	for bkey in buffs:
		var b: Dictionary = buffs[bkey]
		if b.has("pct") and b["pct"] is Dictionary:
			for key in b["pct"]:
				pct[key] = float(pct.get(key, 0.0)) + float(b["pct"][key])

	# ---- 主属性三件套：flat 合并 + pct 乘算 + 神话全属性 ----
	var mythic_pct := float(pct.get("all_attributes", 0.0))
	var out := {}
	for key in FINAL_KEYS:
		out[key] = 0.0
	var mythic_hp := float(pct.get("pct_hp", 0.0)) + mythic_pct
	out["max_hp"] = float(flat.get("flat_hp", 0.0)) * (1.0 + mythic_hp / 100.0)
	var mythic_attack := float(pct.get("pct_attack", 0.0)) + mythic_pct
	out["attack"] = float(flat.get("flat_attack", 0.0)) * (1.0 + mythic_attack / 100.0)
	var mythic_armor := float(pct.get("pct_armor", 0.0)) + mythic_pct
	out["armor"] = float(flat.get("flat_armor", 0.0)) * (1.0 + mythic_armor / 100.0)

	# ---- 直接累加键（pct 词缀值本身即百分数）----
	var direct := {
		"crit_chance": pct.get("crit_chance", 0.0),
		"crit_damage": pct.get("crit_damage", 0.0),
		"attack_speed": pct.get("attack_speed", 0.0),
		"elemental_damage": pct.get("elemental_damage", 0.0),
		# 通用伤害加成（第四步 B4 3-B1）：临时增益 `all_damage` 的落点。
		# 消费在 `PlayerController.get_element_damage_bonus`（物理 + 元素皆受益）。
		"all_damage": pct.get("all_damage", 0.0),
		"dodge": pct.get("dodge", 0.0),
		"block_chance": pct.get("block_chance", 0.0),
		"life_regen": flat.get("life_regen", 0.0) + pct.get("life_regen", 0.0),
		"fire_resist": pct.get("fire_resist", 0.0),
		"cold_resist": pct.get("cold_resist", 0.0),
		"poison_resist": pct.get("poison_resist", 0.0),
		"lightning_resist": pct.get("lightning_resist", 0.0),
		# 第三步补齐抗性 3 系（3-E5 / 2-L3）：暗影 / 物理 / 全抗
		"shadow_resist": pct.get("shadow_resist", 0.0),
		"physical_resist": pct.get("physical_resist", 0.0),
		"all_resist": pct.get("all_resist", 0.0),
		"max_resource": flat.get("max_resource", 0.0),
		"resource_regen": pct.get("resource_regen", 0.0),
		"skill_cost_reduction": pct.get("skill_cost_reduction", 0.0),
		"cooldown_reduction": pct.get("cooldown_reduction", 0.0),
		"pickup_radius": flat.get("pickup_radius", 0.0),
		"move_speed": pct.get("move_speed", 0.0),
		"magic_find": pct.get("magic_find", 0.0),
		"xp_gain": pct.get("xp_gain", 0.0),
		"gold_gain": pct.get("gold_gain", 0.0),
		"thorns": pct.get("thorns", 0.0),
		"life_on_hit": pct.get("life_on_hit", 0.0),
		"kill_heal": flat.get("kill_heal", 0.0),
		# 技能等级（第一步 B0）：**固定值累加**（非百分数）—— 词缀 add_skill_level
		# 与底材 base_stats 的 skill_level 都走这里；漏掉这一行 ⇒ 词缀持有但玩家读不到（死钩子）
		"skill_level": flat.get("skill_level", 0.0),
		# 元素专精（第三步 3-E2 / 2-L3）：5 个非物理子键 + 全元素伤害 + 对异常增伤 + 穿透。
		# 子键命名与 `GameConstants.STAT_ELEMENTAL_DAMAGE_*` 一致；取键口径见 §4.2.3。
		"elemental_damage_fire": pct.get("elemental_damage_fire", 0.0),
		"elemental_damage_cold": pct.get("elemental_damage_cold", 0.0),
		"elemental_damage_lightning": pct.get("elemental_damage_lightning", 0.0),
		"elemental_damage_poison": pct.get("elemental_damage_poison", 0.0),
		"elemental_damage_shadow": pct.get("elemental_damage_shadow", 0.0),
		"all_element_damage": pct.get("all_element_damage", 0.0),
		"damage_vs_ailment": pct.get("damage_vs_ailment", 0.0),
		"elemental_penetration": pct.get("elemental_penetration", 0.0),
		"resist_penetration": pct.get("resist_penetration", 0.0),
		# 异常状态增伤（第三步 3.3）：**只落键**，待 AilmentSystem 实装后接线
		"burn_damage": pct.get("burn_damage", 0.0),
		"chill_damage": pct.get("chill_damage", 0.0),
		"poison_damage": pct.get("poison_damage", 0.0),
		"shock_damage": pct.get("shock_damage", 0.0),
		"curse_damage": pct.get("curse_damage", 0.0),
		"ailment_duration": pct.get("ailment_duration", 0.0),
		"ailment_chance": pct.get("ailment_chance", 0.0),
		"ailment_effect": pct.get("ailment_effect", 0.0),
		# 局内（阶段 4）：三选一 / 祭坛 / 连杀
		"armor_pierce": pct.get("armor_pierce", 0.0),
		"life_steal": pct.get("life_steal", 0.0),
		"damage_taken": pct.get("damage_taken", 0.0),
		"regen_pct_hp": pct.get("regen_pct_hp", 0.0),
		"shield_pct_hp": pct.get("shield_pct_hp", 0.0),
	}
	for key in direct:
		out[key] = float(direct[key])
	return out


## 最终属性转展示文本（多行）
static func to_text(stats: Dictionary) -> String:
	var lines: Array[String] = []
	for key in FINAL_KEYS:
		if not stats.has(key):
			continue
		var v: float = float(stats[key])
		var label := EquipmentCompare._label_for(key)
		var pct := ""
		if (key.begins_with("pct_") or key.begins_with("ailment_")
				or key.begins_with("elemental_damage")
				or key.ends_with("_resist") or key.ends_with("_damage")
				or key.ends_with("_penetration")
				or key in ["crit_chance", "attack_speed", "resource_regen",
					"skill_cost_reduction", "cooldown_reduction", "move_speed", "magic_find",
					"xp_gain", "gold_gain", "thorns", "life_on_hit", "dodge", "block_chance",
					"damage_vs_ailment", "all_element_damage", "armor_pierce",
					"life_steal", "damage_taken", "regen_pct_hp", "shield_pct_hp"]):
			pct = "%"
		lines.append("%s：%s%s" % [label, ("%.1f" % v).rstrip("0").rstrip(".") if absf(v - roundf(v)) > 0.01 else str(int(roundf(v))), pct])
	return "\n".join(lines)
