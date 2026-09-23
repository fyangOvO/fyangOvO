## 关卡内资源与商店（任务 4.4 · class_name）
##
## 工程侧默认设计（GDD 仅确认「金币：商店」为消耗出口）：
##   - 每关 1 次商店（关卡中段触发），固定刷新 count 件商品；
##   - 商品：装备（稀有度定价）/ 药水（回血）/ 材料（秘银尘等）；
##   - 货币：本局金币（player.gold，D2 方案 B 结算扣 50% —— 本局花本局赚）；
##   - 定价 = 稀有度基准 × (1 + 0.5 × iLvl)；药水 50；材料 30/份。
class_name RunShop
extends RefCounted

const RARITY_PRICE := {
	"common": 10.0, "magic": 25.0, "rare": 60.0, "epic": 150.0,
	"legendary": 400.0, "set": 350.0, "mythic": 800.0, "hidden": 1000.0,
}
const POTION_PRICE := 50.0
const MATERIAL_PRICE := 30.0

var player: Dictionary = {}      # {gold: float, inventory: Inventory}
var stock: Array[Dictionary] = [] # {kind, label, price, item/key/amount}


static func _rarity_key(rarity: int) -> String:
	for key in RARITY_PRICE:
		if GameConstants.rarity_from_key(key) == rarity:
			return key
	return "common"


## 生成商品：装备 count-2 件 + 药水 + 材料（共 count 件）
func generate_stock(count: int, level: int, rng: RandomNumberGenerator = null) -> void:
	stock.clear()
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	# 装备（稀有度按关卡权重：越靠后越容易出高稀有度）
	var equip_slots := maxi(count - 2, 0)
	for i in equip_slots:
		var template := _pick_template(level, r)
		var rarity := _pick_rarity(level, r)
		var item := AffixRoller.roll_full_equipment(template, clampi(level, 1, 20), rarity, r)
		var price := _price_for(item)
		stock.append({"kind": "equipment", "label": item.get_display_name(),
			"price": price, "item": item})
	# 药水
	stock.append({"kind": "potion", "item_id": "life_potion", "amount": 1,
		"label": "生命药水（回复 30%% 最大生命）",
		"price": POTION_PRICE})
	stock.append({"kind": "potion", "item_id": "mana_potion", "amount": 1,
		"label": "法力药水（回复 40%% 最大法力）",
		"price": 40.0})
	# 材料
	var mats := ["dust", "essence"]
	stock.append({"kind": "material", "label": "秘银尘 ×5（分解材料）",
		"key": "dust", "amount": 5, "price": MATERIAL_PRICE})


func _pick_template(level: int, rng: RandomNumberGenerator) -> EquipmentData:
	var pool: Array[EquipmentData] = []
	for tpl in ConfigLoader.equipment_templates.values():
		if not tpl.craftable or tpl.rarity_max > GameConstants.Rarity.LEGENDARY:
			continue
		if tpl.item_level_max >= level and tpl.item_level_min <= level + 5:
			pool.append(tpl)
	if pool.is_empty():
		for tpl in ConfigLoader.equipment_templates.values():
			if tpl.craftable:
				pool.append(tpl)
	return pool[rng.randi_range(0, pool.size() - 1)]


func _pick_rarity(level: int, rng: RandomNumberGenerator) -> int:
	# 关卡 1–20：白 35 / 蓝 30 / 黄 20 / 紫 10 / 橙 5；等级越高紫橙权重略升
	var roll := rng.randf()
	var advanced := float(level) / 40.0
	if roll < 0.35 - advanced * 0.1:
		return GameConstants.Rarity.COMMON
	if roll < 0.65 - advanced * 0.1:
		return GameConstants.Rarity.MAGIC
	if roll < 0.85:
		return GameConstants.Rarity.RARE
	if roll < 0.95:
		return GameConstants.Rarity.EPIC
	return GameConstants.Rarity.LEGENDARY


static func _price_for(item: EquipmentInstance) -> float:
	return RARITY_PRICE.get(_rarity_key(item.rarity), 10.0) * (1.0 + 0.5 * float(item.item_level))


## 购买第 index 件：扣金币 → 装备入包（满仓拒绝）/ 药水材料直接入局。
## 返回 {ok, reason}；失败不扣款。
func buy(index: int) -> Dictionary:
	if index < 0 or index >= stock.size():
		return {"ok": false, "reason": "无效商品"}
	var entry: Dictionary = stock[index]
	var price := float(entry["price"])
	if player.is_empty() or float(player.get("gold", 0.0)) < price:
		return {"ok": false, "reason": "金币不足"}
	var inv: Inventory = player.get("inventory", null)
	if entry["kind"] == "equipment":
		if inv == null or not inv.add(entry["item"]):
			return {"ok": false, "reason": "背包已满"}
	# 药水 → 消耗品背包（步骤 8A 修假闭环：此前只扣款、物品凭空消失）
	if entry["kind"] == "potion":
		var cid := str(entry.get("item_id", "life_potion"))
		var c: Dictionary = player.get("consumables", {}) if player.get("consumables") is Dictionary else {}
		c[cid] = int(c.get(cid, 0)) + int(entry.get("amount", 1))
		player["consumables"] = c
		EventBus.consumables_changed.emit(c.duplicate(), "shop")
	player["gold"] = float(player.get("gold", 0.0)) - price
	EventBus.gold_changed.emit(player["gold"])
	stock.remove_at(index)
	return {"ok": true, "reason": ""}
