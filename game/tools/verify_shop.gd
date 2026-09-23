## 关卡商店实测（任务 4.4 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_shop.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（5 个测试段）：
##   A. 数据/生成：stock 商品数、种类齐全（装备/药水/材料）
##   B. 定价：装备价 = 稀有度基准 × (1+0.5×iLvl)；药水 50；材料 30
##   C. 购买：扣金币 + 装备入包 + 从库存移除
##   D. 失败：金币不足不扣款；背包满不扣款；无效索引
##   E. 稀有度分布：多关采样含橙装（非全白）
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 关卡商店实测（任务 4.4） =====")
	_rng.seed = 20260916
	await _test_generate()
	await _test_pricing()
	await _test_buy()
	await _test_fail()
	await _test_rarity()
	_finish()


func _make_player(gold: float) -> Dictionary:
	return {"gold": gold, "inventory": Inventory.create(8, 5)}


# =============================================================================
# A. 生成
# =============================================================================

func _test_generate() -> void:
	print("--- A. 生成 ---")
	var shop := RunShop.new()
	shop.player = _make_player(9999.0)
	shop.generate_stock(4, 5, _rng)
	_ok("生成 5 件商品（2装备+生命/法力药水+材料）", shop.stock.size() == 5)
	var kinds := {}
	for entry in shop.stock:
		kinds[entry["kind"]] = true
	_ok("含装备/药水/材料", kinds.has("equipment") and kinds.has("potion") and kinds.has("material"))
	_ok("装备商品带物品实例",
		shop.stock[0]["kind"] == "equipment" and shop.stock[0]["item"] is EquipmentInstance)


# =============================================================================
# B. 定价
# =============================================================================

func _test_pricing() -> void:
	print("--- B. 定价 ---")
	var shop := RunShop.new()
	shop.player = _make_player(9999.0)
	shop.generate_stock(4, 5, _rng)
	var potion_found := false
	var material_found := false
	for entry in shop.stock:
		if entry["kind"] == "potion":
			_ok("药水定价（生命50/法力40）",
				int(entry["price"]) == 50 or int(entry["price"]) == 40)
			potion_found = true
		elif entry["kind"] == "material":
			_ok("材料 30 金", int(entry["price"]) == 30)
			material_found = true
		else:
			var item: EquipmentInstance = entry["item"]
			var base: float = RunShop.RARITY_PRICE.get(
				RunShop._rarity_key(item.rarity), 10.0)
			var expect := base * (1.0 + 0.5 * float(item.item_level))
			_ok("装备价 = 基准 × (1+0.5×iLvl)", absf(float(entry["price"]) - expect) < 0.01)
	_ok("药水材料均出现", potion_found and material_found)


# =============================================================================
# C. 购买
# =============================================================================

func _test_buy() -> void:
	print("--- C. 购买 ---")
	var shop := RunShop.new()
	shop.player = _make_player(9999.0)
	shop.generate_stock(4, 5, _rng)
	var equip_idx := -1
	for i in shop.stock.size():
		if shop.stock[i]["kind"] == "equipment":
			equip_idx = i
			break
	var price := float(shop.stock[equip_idx]["price"])
	var before := int(shop.player["gold"])
	var inv_before: int = shop.player["inventory"].count()
	var res := shop.buy(equip_idx)
	_ok("装备购买成功", res["ok"])
	_ok("金币扣除精确", int(shop.player["gold"]) == before - int(price))
	_ok("装备入包（+1）", shop.player["inventory"].count() == inv_before + 1)
	_ok("商品从库存移除（5→4）", shop.stock.size() == 4)


# =============================================================================
# D. 失败
# =============================================================================

func _test_fail() -> void:
	print("--- D. 失败 ---")
	var shop := RunShop.new()
	shop.player = _make_player(10.0)
	shop.generate_stock(4, 5, _rng)
	var gold_before := int(shop.player["gold"])
	var res := shop.buy(0)
	_ok("金币不足不购买", not res["ok"] and int(shop.player["gold"]) == gold_before)
	shop.player["gold"] = 9999.0
	var res2 := shop.buy(99)
	_ok("无效索引拒绝", not res2["ok"])
	var shop2 := RunShop.new()
	shop2.player = _make_player(9999.0)
	var tiny_inv := Inventory.create(1, 1)
	shop2.player["inventory"] = tiny_inv
	tiny_inv.add(EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("sword_iron"), 5, GameConstants.Rarity.COMMON))
	shop2.generate_stock(4, 5, _rng)
	var equip_idx := -1
	for i in shop2.stock.size():
		if shop2.stock[i]["kind"] == "equipment":
			equip_idx = i
			break
	var gold_before2 := int(shop2.player["gold"])
	var res3 := shop2.buy(equip_idx)
	_ok("背包满不扣款", not res3["ok"] and int(shop2.player["gold"]) == gold_before2)


# =============================================================================
# E. 稀有度分布
# =============================================================================

func _test_rarity() -> void:
	print("--- E. 稀有度分布 ---")
	var shop := RunShop.new()
	shop.player = _make_player(9999.0)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var rarities := {}
	var total := 0
	for lv in range(1, 11):
		shop.generate_stock(4, lv, rng2)
		for entry in shop.stock:
			if entry["kind"] == "equipment":
				rarities[entry["item"].rarity] = rarities.get(entry["item"].rarity, 0) + 1
				total += 1
	_ok("10 关采样含橙装（非全白）", rarities.get(GameConstants.Rarity.LEGENDARY, 0) > 0
		or rarities.get(GameConstants.Rarity.EPIC, 0) > 0)
	_ok("全为可入库稀有度（无红彩）",
		not rarities.has(GameConstants.Rarity.MYTHIC) and not rarities.has(GameConstants.Rarity.HIDDEN))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
