## 红装神话词缀重铸（任务 3.11 · 纯静态 class_name）
##
## GDD 3.4：重铸（红装）= 重掷神话词缀（数值/类型），消耗「神话结晶」×2。
##   彩装：不可重铸（唯一性保护，GDD 3.2.2）；非红装：不适用。
##
## 神话词缀池当前仅 1 条（mythic_all_attributes），重掷 = 数值重掷；
## 类型重掷（未来扩展池）已按「从候选池抽」预留。
class_name MythicRerollController
extends RefCounted

const MYTHIC_REROLL_CRYSTAL := 2


## 重铸成本（红装 = 神话结晶 ×2；其余空表）
static func get_reroll_cost(item: EquipmentInstance) -> Dictionary:
	if item != null and item.rarity == GameConstants.Rarity.MYTHIC:
		return {MaterialBag.KEY_CRYSTAL: MYTHIC_REROLL_CRYSTAL}
	return {}


## 能否重铸（仅红装；彩装不可重铸）
static func can_reroll(item: EquipmentInstance) -> bool:
	return item != null and item.rarity == GameConstants.Rarity.MYTHIC


## 重掷神话词缀：找到神话独立槽词缀重掷数值；无则返回 false。
## 调用方负责扣费 + 发 EventBus.equipment_rerolled。
static func try_reroll_mythic(item: EquipmentInstance, rng: RandomNumberGenerator) -> bool:
	if not can_reroll(item) or rng == null:
		return false
	for roll in item.affixes:
		if roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID:
			var aff: AffixData = ConfigLoader.get_affix(roll.affix_id)
			if aff == null:
				return false
			roll.value = aff.roll_base_value(rng) * GameConstants.affix_ilvl_scale(item.item_level)
			roll.is_empowered = false
			return true
	return false
