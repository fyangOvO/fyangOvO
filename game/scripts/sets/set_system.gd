## 套装系统（任务 3.10 · 纯静态 class_name）
##
## 数据：`data/sets/sets.json`（3 套 × 6 件，2/4/6 档 tier_bonuses）。
## 职责：
##   - `get_set_of(item)`：装备所属套装 id（来自底材 set_id）
##   - `count_pieces(equipped, set_id)`：已穿件数
##   - `get_active_tiers(equipped, set_id)`：达标档位（pieces ≤ 计数）
##   - `get_bonus_stats(equipped)`：全部激活套装的数值加成（stats 字段并入最终属性；
##     effect_id 机制类仅文案展示——触发逻辑属战斗层，3.11/战斗接入时由调用方处理）
##   - `get_progress(equipped)`：每套进度（供 SetPanel 6 段进度条渲染，GDD 0.3 节 3.7）
class_name SetSystem
extends RefCounted


## 装备所属套装 id（非套装返回空串）
static func get_set_of(item: EquipmentInstance) -> String:
	if item == null:
		return ""
	if not item.set_id.is_empty():
		return item.set_id
	if item.template != null:
		return item.template.set_id
	return ""


## 已穿件数（同一套装内不同部位计 1；重复部位只计 1）
static func count_pieces(equipped: Array[EquipmentInstance], set_id: String) -> int:
	var seen: Dictionary = {}
	for item in equipped:
		if get_set_of(item) == set_id:
			seen[item.slot] = true
	return seen.size()


## 激活档位（2/4/6 → 达标列表，按 pieces 升序）
static func get_active_tiers(equipped: Array[EquipmentInstance], set_id: String) -> Array[Dictionary]:
	var info := _set_info(set_id)
	if info.is_empty():
		return []
	var count := count_pieces(equipped, set_id)
	var out: Array[Dictionary] = []
	for tier in info["tier_bonuses"]:
		if int(tier["pieces"]) <= count:
			out.append(tier)
	return out


## 全部激活套装的数值加成汇总（键 → 值，可直接并入 StatCalculator 结算）
static func get_bonus_stats(equipped: Array[EquipmentInstance]) -> Dictionary:
	var out := {}
	var sets_seen := {}
	for item in equipped:
		var set_id := get_set_of(item)
		if set_id.is_empty() or sets_seen.has(set_id):
			continue
		sets_seen[set_id] = true
		for tier in get_active_tiers(equipped, set_id):
			var stats: Dictionary = tier.get("stats", {})
			for key in stats:
				out[key] = float(out.get(key, 0.0)) + float(stats[key])
	return out


## 每套进度（SetPanel 渲染）：[{set_id, display_name, pieces, piece_total, tiers}]
## tiers = [{pieces, description, active, stats, effect_id}]
static func get_progress(equipped: Array[EquipmentInstance]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for set_id in ConfigLoader.sets:
		var info := _set_info(set_id)
		if info.is_empty():
			continue
		var count := count_pieces(equipped, set_id)
		var tiers: Array[Dictionary] = []
		for tier in info["tier_bonuses"]:
			tiers.append({
				"pieces": int(tier["pieces"]),
				"description": String(tier.get("description", "")),
				"active": int(tier["pieces"]) <= count,
				"stats": tier.get("stats", {}),
				"effect_id": String(tier.get("effect_id", "")),
			})
		out.append({
			"set_id": set_id,
			"display_name": String(info.get("display_name", set_id)),
			"pieces": count,
			"piece_total": int(info.get("piece_template_ids", []).size()),
			"tiers": tiers,
		})
	return out


static func _set_info(set_id: String) -> Dictionary:
	var data: SetData = ConfigLoader.sets.get(set_id, null)
	if data == null:
		return {}
	return {
		"id": data.id,
		"display_name": data.display_name,
		"piece_template_ids": data.piece_template_ids,
		"tier_bonuses": data.tier_bonuses,
	}
