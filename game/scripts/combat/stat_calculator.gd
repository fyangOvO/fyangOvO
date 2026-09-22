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
##   max_hp / attack / armor / crit_chance / crit_damage / attack_speed / life_regen /
##   fire_resist / cold_resist / poison_resist / lightning_resist / max_resource /
##   resource_regen / skill_cost_reduction / cooldown_reduction / pickup_radius /
##   move_speed / magic_find / xp_gain / gold_gain / thorns / life_on_hit / kill_heal
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
	"elemental_damage", "dodge", "block_chance", "life_regen", "fire_resist",
	"cold_resist", "poison_resist", "lightning_resist", "max_resource",
	"resource_regen", "skill_cost_reduction", "cooldown_reduction",
	"pickup_radius", "move_speed", "magic_find", "xp_gain", "gold_gain",
	"thorns", "life_on_hit", "kill_heal",
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
	var pct := {}
	for key in gear:
		if (key.begins_with("pct_") or key in [
				"crit_chance", "crit_damage", "attack_speed", "elemental_damage",
				"dodge", "block_chance", "magic_find", "xp_gain", "gold_gain",
				"life_on_hit", "thorns", "skill_cost_reduction", "cooldown_reduction",
				"resource_regen", "move_speed", "all_attributes",
				"armor_pierce", "life_steal", "damage_taken", "regen_pct_hp",
				"shield_pct_hp"]
				or key.ends_with("_resist")):
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
		"dodge": pct.get("dodge", 0.0),
		"block_chance": pct.get("block_chance", 0.0),
		"life_regen": flat.get("life_regen", 0.0) + pct.get("life_regen", 0.0),
		"fire_resist": pct.get("fire_resist", 0.0),
		"cold_resist": pct.get("cold_resist", 0.0),
		"poison_resist": pct.get("poison_resist", 0.0),
		"lightning_resist": pct.get("lightning_resist", 0.0),
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
		if key in ["crit_chance", "crit_damage", "attack_speed", "fire_resist",
				"cold_resist", "poison_resist", "lightning_resist", "resource_regen",
				"skill_cost_reduction", "cooldown_reduction", "move_speed", "magic_find",
				"xp_gain", "gold_gain", "thorns", "life_on_hit"]:
			pct = "%"
		lines.append("%s：%s%s" % [label, ("%.1f" % v).rstrip("0").rstrip(".") if absf(v - roundf(v)) > 0.01 else str(int(roundf(v))), pct])
	return "\n".join(lines)
