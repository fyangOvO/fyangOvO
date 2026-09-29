## 套装系统（任务 3.10 · 纯静态 class_name）
##
## 数据：`data/sets/sets.json`（3 套 × 6 件，2/4/6 档 tier_bonuses）。
## 职责：
##   - `get_set_of(item)`：装备所属套装 id（来自底材 set_id）
##   - `count_pieces(equipped, set_id)`：已穿件数
##   - `get_active_tiers(equipped, set_id)`：达标档位（pieces ≤ 计数）
##   - `get_bonus_stats(equipped)`：全部激活套装的数值加成（stats 字段并入最终属性）
##   - `get_active_effects(equipped)`：全部激活套装的**机制型** effect_id（第四步 B4 3-S2，
##     交给 `LegendaryBus` 与装备传奇特效一起 register / unregister）
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


## 已激活的**套装机制特效**（第四步 B4 · 工单 3-S2）。
##
## 返回 `[{set_id, pieces, effect_id, name}]` —— 仅含**已达标**且档位声明了非空 `effect_id` 的条目。
## 关键约束（§3.2）：
##   · **每套最多 2 条**（4 件 / 6 件档；2 件档为纯数值，无 effect_id）
##   · **同套装内 effect_id 去重** —— 防同一条特效被 register 两次
##   · **档位回退即消失** —— 从 4 件降到 3 件时该档不再出现在结果里（调用方据此注销）
static func get_active_effects(equipped: Array[EquipmentInstance]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen_sets: Dictionary = {}
	for item in equipped:
		var set_id := get_set_of(item)
		if set_id.is_empty() or seen_sets.has(set_id):
			continue
		seen_sets[set_id] = true
		var seen_effects: Dictionary = {}
		for tier in get_active_tiers(equipped, set_id):
			var eid := String(tier.get("effect_id", ""))
			if eid.is_empty() or seen_effects.has(eid):
				continue
			seen_effects[eid] = true
			out.append({
				"set_id": set_id,
				"pieces": int(tier.get("pieces", 0)),
				"effect_id": eid,
				"name": effect_display_name(eid),
			})
	return out


## 套装机制特效的显示名（数据缺失时回退为 id 本身，不返回空串）。
static func effect_display_name(effect_id: String) -> String:
	if effect_id.is_empty():
		return ""
	var fx := ConfigLoader.get_set_effect(effect_id)
	var n := String(fx.get("name", ""))
	return n if not n.is_empty() else effect_id


## 每套进度（SetPanel 渲染）：[{set_id, display_name, emblem_path, pieces, piece_total, tiers}]
## tiers = [{pieces, description, active, stats, effect_id}]
## emblem_path：套装徽记贴图（完整 res:// 路径，UI 侧走 ContentLoader.load_icon 加载）
static func get_progress(equipped: Array[EquipmentInstance]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for set_id in ConfigLoader.sets:
		var info := _set_info(set_id)
		if info.is_empty():
			continue
		var count := count_pieces(equipped, set_id)
		var tiers: Array[Dictionary] = []
		for tier in info["tier_bonuses"]:
			var eid := String(tier.get("effect_id", ""))
			tiers.append({
				"pieces": int(tier["pieces"]),
				"description": String(tier.get("description", "")),
				"active": int(tier["pieces"]) <= count,
				"stats": tier.get("stats", {}),
				"effect_id": eid,
				# 第四步 B4 3-S4：机制名（非数值）—— 面板要显示「已激活机制」而非只有数值
				"effect_name": effect_display_name(eid),
			})
		out.append({
			"set_id": set_id,
			"display_name": String(info.get("display_name", set_id)),
			"emblem_path": String(info.get("emblem_path", "")),
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
		"emblem_path": data.emblem_path,
		"piece_template_ids": data.piece_template_ids,
		"tier_bonuses": data.tier_bonuses,
	}
