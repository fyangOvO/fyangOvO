## 合成（材料 → 装备）（任务 3.8 · 纯静态 class_name）
##
## GDD 未给合成配方（5.3 只定材料用途），此处为**工程侧默认闭环**（README 5.22 节记录）：
##   蓝装：秘银尘 ×10        → 随机 蓝色 装备（随机部位 / 底材）
##   黄装：秘银尘 ×30 + 传说精粹 ×1 → 随机 稀有（黄）装备
##   紫装：传说精粹 ×3       → 随机 史诗（紫）装备
##   橙装：传说精粹 ×6 + 神话结晶 ×1 → 随机 传奇（橙）装备（掉落即定型，含传奇特效）
##
## 产出装备：AffixRoller.roll_full_equipment 全量生成；部位随机抽底材。
class_name CraftController
extends RefCounted

const CRAFT_BLUE := "blue"
const CRAFT_RARE := "rare"
const CRAFT_EPIC := "epic"
const CRAFT_LEGENDARY := "legendary"

## recipe_id → {name, cost: {材料键: 数量}, rarity}
const RECIPES := {
	CRAFT_BLUE: {
		"name": "秘银合成 · 蓝",
		"cost": {MaterialBag.KEY_DUST: 10},
		"rarity": GameConstants.Rarity.MAGIC,
	},
	CRAFT_RARE: {
		"name": "精粹合成 · 黄",
		"cost": {MaterialBag.KEY_DUST: 30, MaterialBag.KEY_ESSENCE: 1},
		"rarity": GameConstants.Rarity.RARE,
	},
	CRAFT_EPIC: {
		"name": "精粹合成 · 紫",
		"cost": {MaterialBag.KEY_ESSENCE: 3},
		"rarity": GameConstants.Rarity.EPIC,
	},
	CRAFT_LEGENDARY: {
		"name": "神话合成 · 橙",
		"cost": {MaterialBag.KEY_ESSENCE: 6, MaterialBag.KEY_CRYSTAL: 1},
		"rarity": GameConstants.Rarity.LEGENDARY,
	},
}


static func get_recipes() -> Array[String]:
	return [CRAFT_BLUE, CRAFT_RARE, CRAFT_EPIC, CRAFT_LEGENDARY]


static func get_craft_cost(recipe_id: String) -> Dictionary:
	if not RECIPES.has(recipe_id):
		return {}
	return (RECIPES[recipe_id] as Dictionary).get("cost", {})


## 合成：材料足够则扣费并生成装备；不足返回 null（不扣费）。
## 产出装备 iLvl = 15 + randi()%16（15–30，工程侧默认，GDD 未给）。
static func try_craft(recipe_id: String, bag: MaterialBag, rng: RandomNumberGenerator) -> EquipmentInstance:
	if not RECIPES.has(recipe_id) or bag == null:
		return null
	var cost: Dictionary = get_craft_cost(recipe_id)
	if not bag.can_afford(cost):
		return null
	bag.spend(cost)
	var rarity: int = int((RECIPES[recipe_id] as Dictionary)["rarity"])
	var tpl := _random_template(rng)
	var ilvl := 15 + rng.randi_range(0, 15)
	var item := AffixRoller.roll_full_equipment(tpl, ilvl, rarity, rng)
	item.instance_id = "craft_%d" % rng.randi_range(100000, 999999)
	return item


static func _random_template(rng: RandomNumberGenerator) -> EquipmentData:
	var ids: Array[String] = []
	for id in ConfigLoader.equipment_templates:
		var tpl: EquipmentData = ConfigLoader.equipment_templates[id]
		if not tpl.id.begins_with("sword_ash_vow"): # 排除剧情/唯一底材
			ids.append(id)
	var id := ids[rng.randi_range(0, ids.size() - 1)]
	return ConfigLoader.equipment_templates[id] as EquipmentData
