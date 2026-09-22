## 分解 / 合成 / 材料回收实测（任务 3.8 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_dismantle.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 分解产出：GDD 5.3 权威表逐档断言（白 0 / 蓝 1 尘 / 黄 3 尘 / 紫 1 精粹+5 尘 /
##      橙 3 精粹 / 绿 4 精粹 / 红 6 精粹+1 结晶 / 彩拒绝）
##   B. 材料包：增 / 扣 / 不足拒绝 / 批量 spend 原子性
##   C. 合成配方：4 档成本 / 稀有度映射
##   D. 合成成功：扣费 + 产出装备稀有度 / iLvl 区间 / 词缀非空
##   E. 合成失败：材料不足不扣费返回 null
##   F. 合成循环：材料充足时连续合成不崩溃、材料正确递减
##   G. 端到端：分解紫装 → 材料入包 → 合成蓝装 → 再分解闭环
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
	print("===== 分解 / 合成 / 材料回收实测（任务 3.8） =====")
	_rng.seed = 20260916
	await _test_dismantle()
	await _test_bag()
	await _test_recipes()
	await _test_craft_ok()
	await _test_craft_fail()
	await _test_craft_loop()
	await _test_e2e()
	_finish()


func _make_item(rarity: int, ilvl: int = 20) -> EquipmentInstance:
	return AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("sword_iron"), ilvl, rarity, _rng)


# =============================================================================
# A. 分解产出（GDD 5.3 权威表）
# =============================================================================

func _test_dismantle() -> void:
	print("--- A. 分解产出（GDD 5.3） ---")
	var cases := [
		[GameConstants.Rarity.COMMON, {}],
		[GameConstants.Rarity.MAGIC, {"dust": 1}],
		[GameConstants.Rarity.RARE, {"dust": 3}],
		[GameConstants.Rarity.EPIC, {"dust": 5, "essence": 1}],
		[GameConstants.Rarity.LEGENDARY, {"essence": 3}],
		[GameConstants.Rarity.SET, {"essence": 4}],
		[GameConstants.Rarity.MYTHIC, {"essence": 6, "crystal": 1}],
	]
	for c in cases:
		var r: int = c[0]
		var expect: Dictionary = c[1]
		var got := DismantleController.get_dismantle_result(_make_item(r))
		_ok("分解 %s 产出 %s" % [GameConstants.rarity_name(r), expect], _dict_eq(got, expect))
	_ok("彩装不可分解", not DismantleController.can_dismantle(_make_item(GameConstants.Rarity.HIDDEN)))
	_ok("彩装 try_dismantle 返回空", DismantleController.try_dismantle(_make_item(GameConstants.Rarity.HIDDEN)).is_empty())
	_ok("null 返回空", DismantleController.get_dismantle_result(null).is_empty())


func _dict_eq(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in b:
		if int(a.get(k, -999)) != int(b[k]):
			return false
	return true


# =============================================================================
# B. 材料包
# =============================================================================

func _test_bag() -> void:
	print("--- B. 材料包 ---")
	var bag := MaterialBag.create()
	bag.add(MaterialBag.KEY_DUST, 10)
	bag.add(MaterialBag.KEY_ESSENCE, 2)
	_ok("增材料后读数正确", bag.get_amount(MaterialBag.KEY_DUST) == 10 and bag.get_amount(MaterialBag.KEY_ESSENCE) == 2)
	_ok("扣减成功", bag.remove(MaterialBag.KEY_DUST, 3) and bag.get_amount(MaterialBag.KEY_DUST) == 7)
	_ok("扣减不足拒绝且不扣", not bag.remove(MaterialBag.KEY_DUST, 99) and bag.get_amount(MaterialBag.KEY_DUST) == 7)
	_ok("can_afford 批量判断", bag.can_afford({MaterialBag.KEY_DUST: 7, MaterialBag.KEY_ESSENCE: 2})
		and not bag.can_afford({MaterialBag.KEY_DUST: 8}))
	_ok("spend 原子性（不足全不扣）", not bag.spend({MaterialBag.KEY_DUST: 5, MaterialBag.KEY_ESSENCE: 99})
		and bag.get_amount(MaterialBag.KEY_DUST) == 7)
	_ok("spend 成功批量扣", bag.spend({MaterialBag.KEY_DUST: 5, MaterialBag.KEY_ESSENCE: 2})
		and bag.get_amount(MaterialBag.KEY_DUST) == 2 and bag.get_amount(MaterialBag.KEY_ESSENCE) == 0)


# =============================================================================
# C. 合成配方
# =============================================================================

func _test_recipes() -> void:
	print("--- C. 合成配方 ---")
	_ok("4 档配方", CraftController.get_recipes().size() == 4)
	_ok("蓝装成本 = 10 秘银尘", _dict_eq(CraftController.get_craft_cost(CraftController.CRAFT_BLUE), {MaterialBag.KEY_DUST: 10}))
	_ok("黄装成本 = 30 尘 + 1 精粹", _dict_eq(CraftController.get_craft_cost(CraftController.CRAFT_RARE),
		{MaterialBag.KEY_DUST: 30, MaterialBag.KEY_ESSENCE: 1}))
	_ok("紫装成本 = 3 精粹", _dict_eq(CraftController.get_craft_cost(CraftController.CRAFT_EPIC), {MaterialBag.KEY_ESSENCE: 3}))
	_ok("橙装成本 = 6 精粹 + 1 结晶", _dict_eq(CraftController.get_craft_cost(CraftController.CRAFT_LEGENDARY),
		{MaterialBag.KEY_ESSENCE: 6, MaterialBag.KEY_CRYSTAL: 1}))
	_ok("未知配方返回空成本", CraftController.get_craft_cost("nope").is_empty())


# =============================================================================
# D. 合成成功
# =============================================================================

func _test_craft_ok() -> void:
	print("--- D. 合成成功 ---")
	var bag := MaterialBag.create({MaterialBag.KEY_DUST: 100, MaterialBag.KEY_ESSENCE: 20, MaterialBag.KEY_CRYSTAL: 5})
	var item := CraftController.try_craft(CraftController.CRAFT_BLUE, bag, _rng)
	_ok("蓝装合成产出非空", item != null)
	if item != null:
		_ok("产出为蓝色", item.rarity == GameConstants.Rarity.MAGIC)
		_ok("iLvl 在 15–30", item.item_level >= 15 and item.item_level <= 30)
		_ok("扣费 10 尘", bag.get_amount(MaterialBag.KEY_DUST) == 90)
	var epic := CraftController.try_craft(CraftController.CRAFT_EPIC, bag, _rng)
	_ok("紫装合成产出 + 扣 3 精粹", epic != null and epic.rarity == GameConstants.Rarity.EPIC
		and bag.get_amount(MaterialBag.KEY_ESSENCE) == 17)
	var orange := CraftController.try_craft(CraftController.CRAFT_LEGENDARY, bag, _rng)
	_ok("橙装合成产出（含传奇特效装配）", orange != null and orange.rarity == GameConstants.Rarity.LEGENDARY
		and not orange.legendary_effect_id.is_empty())


# =============================================================================
# E. 合成失败
# =============================================================================

func _test_craft_fail() -> void:
	print("--- E. 合成失败 ---")
	var bag := MaterialBag.create({MaterialBag.KEY_DUST: 5})
	_ok("材料不足返回 null", CraftController.try_craft(CraftController.CRAFT_BLUE, bag, _rng) == null)
	_ok("失败不扣费", bag.get_amount(MaterialBag.KEY_DUST) == 5)
	_ok("未知配方返回 null", CraftController.try_craft("nope", bag, _rng) == null)
	_ok("null 包返回 null", CraftController.try_craft(CraftController.CRAFT_BLUE, null, _rng) == null)


# =============================================================================
# F. 合成循环
# =============================================================================

func _test_craft_loop() -> void:
	print("--- F. 合成循环 ---")
	var bag := MaterialBag.create({MaterialBag.KEY_DUST: 30})
	for i in range(3):
		var item := CraftController.try_craft(CraftController.CRAFT_BLUE, bag, _rng)
		_ok("循环第 %d 次合成成功" % (i + 1), item != null)
	_ok("3 次后尘耗尽", bag.get_amount(MaterialBag.KEY_DUST) == 0)
	_ok("耗尽后再合成失败", CraftController.try_craft(CraftController.CRAFT_BLUE, bag, _rng) == null)


# =============================================================================
# G. 端到端
# =============================================================================

func _test_e2e() -> void:
	print("--- G. 端到端 ---")
	var bag := MaterialBag.create()
	var purple := _make_item(GameConstants.Rarity.EPIC, 25)
	var result := DismantleController.try_dismantle(purple)
	bag.add(MaterialBag.KEY_DUST, int(result.get("dust", 0)))
	bag.add(MaterialBag.KEY_ESSENCE, int(result.get("essence", 0)))
	_ok("分解紫装入包（1 精粹 + 5 尘）",
		bag.get_amount(MaterialBag.KEY_ESSENCE) == 1 and bag.get_amount(MaterialBag.KEY_DUST) == 5)
	var crafted := CraftController.try_craft(CraftController.CRAFT_BLUE, bag, _rng)
	_ok("用 5 尘不够合蓝（需 10）", crafted == null)
	bag.add(MaterialBag.KEY_DUST, 5)
	var crafted2 := CraftController.try_craft(CraftController.CRAFT_BLUE, bag, _rng)
	_ok("凑满 10 尘合成成功", crafted2 != null and crafted2.rarity == GameConstants.Rarity.MAGIC)
	var re := DismantleController.try_dismantle(crafted2)
	_ok("再分解蓝装回 1 尘", _dict_eq(re, {"dust": 1}))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
