## 特殊档（深渊/塔）装备半重铸（B5-7 · 6-W6-Q5 · 纯静态 class_name）
##
## 与 MythicRerollController 的区别：
##   · 只重掷**非专属**词缀（来源 != 本装备来源），专属词缀（abyss_*/tower_*）锁定保护；
##   · 允许最多锁 4 条（locked_indices），锁住的不重掷；
##   · 消耗专属材料（深渊裂片 / 塔印），不吃神话结晶。
##
## 调用方负责：扣材料 + 发 EventBus.equipment_rerolled + UI 刷新。
class_name SpecialRerollController
extends RefCounted

const COST_ABYSS_SHARD := 2
const COST_TOWER_SIGIL := 2
const MAX_LOCKS := 4


## 该装备来源对应的专属材料键
static func material_key_for(rarity: int) -> String:
	if rarity == GameConstants.Rarity.SPECIAL_ABYSS:
		return MaterialBag.KEY_ABYSS_SHARD
	if rarity == GameConstants.Rarity.SPECIAL_TOWER:
		return MaterialBag.KEY_TOWER_SIGIL
	return ""


static func can_reroll(item: EquipmentInstance) -> bool:
	if item == null:
		return false
	return item.rarity == GameConstants.Rarity.SPECIAL_ABYSS \
		or item.rarity == GameConstants.Rarity.SPECIAL_TOWER


static func get_reroll_cost(item: EquipmentInstance) -> Dictionary:
	var key := material_key_for(item.rarity if item != null else -1)
	if key.is_empty():
		return {}
	return {key: COST_ABYSS_SHARD if item.rarity == GameConstants.Rarity.SPECIAL_ABYSS else COST_TOWER_SIGIL}


## 半重铸：重掷所有「非专属且未锁」的词缀数值。返回实际重掷条数（0 = 无可重掷）。
## locked_indices：要锁定的 affix 下标（外部 UI 给，最多 MAX_LOCKS 条，超出截断）。
static func try_reroll(item: EquipmentInstance, rng: RandomNumberGenerator,
		locked_indices: Array = []) -> int:
	if not can_reroll(item) or rng == null:
		return 0
	var source := "abyss" if item.rarity == GameConstants.Rarity.SPECIAL_ABYSS else "tower"
	var locked: Array = []
	for i in locked_indices:
		if locked.size() < MAX_LOCKS:
			locked.append(int(i))
	var rerolled := 0
	for i in range(item.affixes.size()):
		if locked.has(i):
			continue
		var roll: AffixRoll = item.affixes[i]
		var aff: AffixData = ConfigLoader.get_affix(roll.affix_id)
		if aff == null:
			continue
		# 专属词缀保护：来源匹配本装备 ⇒ 不洗
		if aff.source == source:
			continue
		roll.value = aff.roll_base_value(rng) * GameConstants.affix_ilvl_scale(item.item_level)
		roll.is_empowered = false
		rerolled += 1
	return rerolled
