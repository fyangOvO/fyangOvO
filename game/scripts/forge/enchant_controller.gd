## 词缀洗练 / 特效重铸（任务 5.4 · class_name 纯静态）
##
## GDD 5.3 材料表：秘银尘 = 词缀洗练、传说精粹 = 橙装特效重铸、
##   神话结晶 = 红装强化与神话词缀重铸（3.4/3.11 已做）。
## 附魔（工程侧默认，GDD 未给具体规则）：洗练 = 重掷 1 条普通词缀数值，
##   秘银尘 ×3；特效重铸 = 重掷橙装传奇特效，传说精粹 ×2。
class_name EnchantController
extends RefCounted

const REROLL_DUST := 3      # 词缀洗练：秘银尘 ×3
const REREFORGE_ESSENCE := 2 # 特效重铸：传说精粹 ×2


## 洗练成本（普通词缀 ≥1 条才可洗）
static func get_reroll_cost(item: EquipmentInstance) -> Dictionary:
	if item == null or _ordinary_affix_count(item) == 0:
		return {}
	return {MaterialBag.KEY_DUST: REROLL_DUST}


## 特效重铸成本（传说+ 且已绑定特效才可重铸）
static func get_reforge_cost(item: EquipmentInstance) -> Dictionary:
	if item == null or item.rarity < GameConstants.Rarity.LEGENDARY \
			or item.legendary_effect_id.is_empty():
		return {}
	return {MaterialBag.KEY_ESSENCE: REREFORGE_ESSENCE}


## 洗练：重掷第 1 条普通词缀的数值（含强化缩放）；返回新值 / false
static func try_reroll_affix(item: EquipmentInstance, rng: RandomNumberGenerator) -> Dictionary:
	if get_reroll_cost(item).is_empty() or rng == null:
		return {"ok": false}
	for roll in item.affixes:
		if roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID:
			continue
		var aff: AffixData = ConfigLoader.get_affix(roll.affix_id)
		if aff == null:
			continue
		roll.value = aff.roll_base_value(rng) * GameConstants.affix_ilvl_scale(item.item_level)
		roll.is_empowered = false
		return {"ok": true, "value": roll.value}
	return {"ok": false}


## 特效重铸：重掷橙装传奇特效（从同部位特效池抽，不重复当前）
static func try_reforge_effect(item: EquipmentInstance, rng: RandomNumberGenerator) -> Dictionary:
	if get_reforge_cost(item).is_empty() or rng == null:
		return {"ok": false}
	var slot_key := GameConstants.EQUIP_SLOT_KEYS[item.slot]
	var candidates: Array[String] = []
	for eid in ConfigLoader.legendary_effects:
		var e: Dictionary = ConfigLoader.get_legendary_effect(eid)
		if str(e.get("slot", "")) == slot_key and eid != item.legendary_effect_id:
			candidates.append(eid)
	if candidates.is_empty():
		return {"ok": false, "reason": "无可选特效"}
	var new_id := candidates[rng.randi_range(0, candidates.size() - 1)]
	item.legendary_effect_id = new_id
	return {"ok": true, "effect_id": new_id}


static func _ordinary_affix_count(item: EquipmentInstance) -> int:
	var n := 0
	for roll in item.affixes:
		if roll.affix_id != AffixRoller.MYTHIC_AFFIX_ID:
			n += 1
	return n