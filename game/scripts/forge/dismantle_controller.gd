## 装备分解（任务 3.8 · 纯静态 class_name）
##
## GDD 5.3 分解产出表（权威）：
##   白 → 无 / 蓝 → 1 秘银尘 / 黄 → 3 秘银尘 / 紫 → 1 传说精粹 + 5 秘银尘 /
##   橙 → 3 传说精粹 / 绿（套装）→ 4 传说精粹 / 红（神话）→ 6 传说精粹 + 1 神话结晶 /
##   彩（隐藏）→ 不可分解（唯一性保护，防误操作）
##
## 产出键与 MaterialBag 一致：dust / essence / crystal。
class_name DismantleController
extends RefCounted


## GDD 5.3 权威表：稀有度 → 产出（键与 MaterialBag 材料键一致，省略 0）
static func get_dismantle_result(item: EquipmentInstance) -> Dictionary:
	if item == null:
		return {}
	match item.rarity:
		GameConstants.Rarity.MAGIC:
			return {"dust": 1}
		GameConstants.Rarity.RARE:
			return {"dust": 3}
		GameConstants.Rarity.EPIC:
			return {"dust": 5, "essence": 1}
		GameConstants.Rarity.LEGENDARY:
			return {"essence": 3}
		GameConstants.Rarity.SET:
			return {"essence": 4}
		GameConstants.Rarity.MYTHIC:
			return {"essence": 6, "crystal": 1}
		_:
			return {}


## 能否分解（彩装 / 隐藏 = 不可分解）
static func can_dismantle(item: EquipmentInstance) -> bool:
	return item != null and item.rarity != GameConstants.Rarity.HIDDEN


## 分解并返回产出（null / 彩装返回空表）。
## 调用方负责：从背包移除该装备 + 材料入包 + 发 EventBus.equipment_dismantled / materials_changed。
static func try_dismantle(item: EquipmentInstance) -> Dictionary:
	if not can_dismantle(item):
		return {}
	return get_dismantle_result(item)
