## 隐藏（彩蛋）装成长（任务 3.11 · 纯静态 class_name）
##
## GDD 3.2.2：隐藏装随特定行为累积成长（如每 1000 击杀 +1% 某属性），
## 上限按底材 growth_max（默认 20%，低于红装——强度锚定橙装）。
## 成长是单件物品的持久状态：实例 growth_value（百分数）累积，
## 并入属性结算时按 growth_stat_key 加算。
class_name HiddenGrowthController
extends RefCounted


## 单件彩装当前成长上限（底材 growth_max，缺省 20%）
static func get_growth_max(item: EquipmentInstance) -> float:
	if item == null or item.template == null:
		return GameConstants.HIDDEN_GROWTH_MAX_BONUS * 100.0
	if item.template.growth_max > 0.0:
		return item.template.growth_max
	return GameConstants.HIDDEN_GROWTH_MAX_BONUS * 100.0


## 能否成长（彩装 + 底材配置 growth_stat_key）
static func can_grow(item: EquipmentInstance) -> bool:
	return item != null and item.rarity == GameConstants.Rarity.HIDDEN \
		and item.template != null and not item.template.growth_stat_key.is_empty()


## 应用成长（amount 为百分数，如 1.0 = +1%）；到上限即停。
## 返回本次实际增加量（0 = 已满 / 不可成长）。
static func apply_growth(item: EquipmentInstance, amount: float) -> float:
	if not can_grow(item) or amount <= 0.0:
		return 0.0
	var before := item.growth_value
	var cap := get_growth_max(item)
	item.growth_value = minf(before + amount, cap)
	return item.growth_value - before


## 成长加成（{stat_key: 百分数}；并入属性结算用）
static func get_growth_bonus(item: EquipmentInstance) -> Dictionary:
	if not can_grow(item) or item.growth_value <= 0.0:
		return {}
	return {item.template.growth_stat_key: item.growth_value}


## 全部彩装的成长加成汇总（并入 StatCalculator）
static func get_total_growth_bonus(equipped: Array[EquipmentInstance]) -> Dictionary:
	var out := {}
	for item in equipped:
		var bonus := get_growth_bonus(item)
		for key in bonus:
			out[key] = float(out.get(key, 0.0)) + float(bonus[key])
	return out
