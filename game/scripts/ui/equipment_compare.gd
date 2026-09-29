## 装备对比（任务 3.7 · 纯静态 class_name）
##
## 职责：
##   - `get_total_stats(item)`：底材基础属性（iLvl 缩放 + 强化倍率）与词缀按
##     stat_key 归并求和，产出「该装备提供的全部统计」。
##   - `compare(new_item, old_item)`：统计键并集逐键对比，输出排序后的对比行
##     （升 / 降 / 平 + 差值），供 ComparePanel 渲染。
##   - 特殊键（echo_strike 等非数值机制词缀）单独归入 `special` 桶，不参与数值对比。
##
## ⚠️ 3.9 属性结算系统上线后，玩家侧最终属性在此之上聚合；本类只负责「装备 vs 装备」。
class_name EquipmentCompare
extends RefCounted

## 非数值 / 机制类统计键（不参与数值 diff，仅文本展示）
const SPECIAL_KEYS: Array[String] = ["echo_strike"]


## 该装备提供的全部统计（键 → 数值）。底材基础属性 + 词缀（按 stat_key 归并）。
static func get_total_stats(item: EquipmentInstance) -> Dictionary:
	var out: Dictionary = {}
	if item == null:
		return out
	var base := item.get_base_stats()
	for key in base:
		out[key] = float(base[key])
	for roll in item.affixes:
		var aff: AffixData = roll.template
		if aff == null or aff.stat_key.is_empty():
			continue
		if SPECIAL_KEYS.has(aff.stat_key):
			continue
		out[aff.stat_key] = float(out.get(aff.stat_key, 0.0)) + roll.value
	return out


## 特殊机制文本（如回响之刃），无则返回空串。
static func get_special_text(item: EquipmentInstance) -> String:
	if item == null:
		return ""
	var parts: Array[String] = []
	for roll in item.affixes:
		var aff: AffixData = roll.template
		if aff != null and SPECIAL_KEYS.has(aff.stat_key):
			parts.append(roll.to_text())
	return "\n".join(parts)


## 对比两件装备。返回每行：{key, label, old_val, new_val, diff, delta_type, is_pct}
## delta_type: 1 = 升 / -1 = 降 / 0 = 平。null 旧件 = 新穿戴（全升）。
static func compare(new_item: EquipmentInstance, old_item: EquipmentInstance) -> Array[Dictionary]:
	var new_stats := get_total_stats(new_item)
	var old_stats := get_total_stats(old_item)
	var keys: Array[String] = []
	for k in new_stats:
		if not keys.has(k):
			keys.append(k)
	for k in old_stats:
		if not keys.has(k):
			keys.append(k)
	var rows: Array[Dictionary] = []
	for key in keys:
		var nv: float = float(new_stats.get(key, 0.0))
		var ov: float = float(old_stats.get(key, 0.0))
		var diff := nv - ov
		var dtype := 0
		if diff > 0.001:
			dtype = 1
		elif diff < -0.001:
			dtype = -1
		rows.append({
			"key": key,
			"label": _label_for(key),
			"old_val": ov,
			"new_val": nv,
			"diff": diff,
			"delta_type": dtype,
			# 百分数键：前缀 pct_ / ailment_ + 后缀 _resist / _damage / _penetration
			# （第三步补齐：元素子键 elemental_damage_* / 穿透 / 异常增伤 均按 % 显示）
			"is_pct": key.begins_with("pct_") or key.begins_with("ailment_")
				or key.begins_with("elemental_damage")
				or key.ends_with("_resist") or key.ends_with("_damage") or key.ends_with("_penetration")
				or key == "crit_chance" or key == "attack_speed" or key == "armor_pierce"
				or key == "dodge" or key == "block_chance" or key == "magic_find"
				or key == "xp_gain" or key == "gold_gain" or key == "life_on_hit"
				or key == "thorns" or key == "skill_cost_reduction" or key == "cooldown_reduction"
				or key == "resource_regen" or key == "move_speed" or key == "damage_vs_ailment",
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["delta_type"] != b["delta_type"]:
			return int(a["delta_type"]) > int(b["delta_type"])
		return String(a["key"]) < String(b["key"]))
	return rows


## 统计键 → 中文标签（3.9 属性结算系统的展示口径在此先行收敛）
static func _label_for(key: String) -> String:
	match key:
		"flat_attack": return "攻击力"
		"pct_attack": return "攻击力 %"
		"elemental_damage": return "元素伤害 %"
		"elemental_damage_fire": return "火焰伤害 %"
		"elemental_damage_cold": return "冰霜伤害 %"
		"elemental_damage_lightning": return "闪电伤害 %"
		"elemental_damage_poison": return "毒素伤害 %"
		"elemental_damage_shadow": return "暗影伤害 %"
		"all_element_damage": return "全元素伤害 %"
		"damage_vs_ailment": return "对异常增伤 %"
		"elemental_penetration": return "元素穿透 %"
		"resist_penetration": return "抗性穿透 %"
		"burn_damage": return "燃烧增伤 %"
		"chill_damage": return "冰冻增伤 %"
		"poison_damage": return "中毒增伤 %"
		"shock_damage": return "感电增伤 %"
		"curse_damage": return "诅咒增伤 %"
		"ailment_duration": return "异常持续 %"
		"ailment_chance": return "异常触发 %"
		"ailment_effect": return "异常强度 %"
		"crit_chance": return "暴击率 %"
		"crit_damage": return "暴击伤害 %"
		"attack_speed": return "攻击速度 %"
		"armor_penetration": return "护甲穿透 %"
		"skill_level": return "技能等级"
		"flat_hp": return "生命值"
		"pct_hp": return "生命值 %"
		"flat_armor": return "护甲"
		"pct_armor": return "护甲 %"
		"dodge": return "闪避 %"
		"block_chance": return "格挡率 %"
		"life_regen": return "生命回复"
		"fire_resist": return "火焰抗性 %"
		"cold_resist": return "冰霜抗性 %"
		"poison_resist": return "毒素抗性 %"
		"lightning_resist": return "闪电抗性 %"
		"shadow_resist": return "暗影抗性 %"
		"physical_resist": return "物理抗性 %"
		"all_resist": return "全抗性 %"
		"max_resource": return "最大资源"
		"resource_regen": return "资源回复 %"
		"skill_cost_reduction": return "技能减耗 %"
		"cooldown_reduction": return "冷却缩减 %"
		"pickup_radius": return "拾取范围"
		"move_speed": return "移动速度 %"
		"magic_find": return "掉落幸运 %"
		"xp_gain": return "经验获取 %"
		"gold_gain": return "金币获取 %"
		"thorns": return "荆棘反伤 %"
		"life_on_hit": return "生命偷取 %"
		"kill_heal": return "击杀回复"
		"all_attributes": return "全属性 %"
		_:
			return key
