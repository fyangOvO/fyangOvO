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
			"is_pct": key.begins_with("pct_") or key == "crit_chance" or key == "crit_damage"
				or key == "attack_speed" or key == "armor_penetration" or key == "dodge"
				or key == "block_chance" or key == "elemental_damage" or key == "magic_find"
				or key == "xp_gain" or key == "gold_gain" or key == "life_on_hit"
				or key == "thorns" or key == "skill_cost_reduction" or key == "cooldown_reduction"
				or key == "resource_regen" or key == "move_speed" or key.ends_with("_resist"),
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
