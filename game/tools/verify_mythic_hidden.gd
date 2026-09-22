## 红装 / 彩装机制实测（任务 3.11 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_mythic_hidden.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 数据：红装 2 件 / 彩装 2 件注册、rarity_min/max、undismantlable
##   B. 神话词缀：红装 roll 后含神话独立槽（mythic_all_attributes，不占普通位）
##   C. 神话重铸：成本（红 = 结晶 ×2）/ 可重铸判定 / 数值重掷 / 彩装拦截
##   D. 彩装成长：apply_growth 累积 / 上限夹取（其一 +5% / 拾荒者 +15%）
##   E. 成长并入：StatCalculator 含彩装成长（move_speed + / all_attributes ×）
##   F. 彩装保护：不可分解（3.8 已拦）不可重铸
##   G. 边界：null / 非红装 / 非彩装
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
	print("===== 红装 / 彩装机制实测（任务 3.11） =====")
	_rng.seed = 20260916
	await _test_data()
	await _test_mythic_slot()
	await _test_reroll()
	await _test_growth()
	await _test_merge()
	await _test_protect()
	await _test_edge()
	_finish()


func _make(template_id: String, rarity: int) -> EquipmentInstance:
	var item := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template(template_id), 20, rarity, _rng)
	item.rarity = rarity
	return item


# =============================================================================
# A. 数据
# =============================================================================

func _test_data() -> void:
	print("--- A. 数据 ---")
	var mythic_ids := ["mythic_crown_seven_kalpa", "mythic_staff_final_echo"]
	for id in mythic_ids:
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(id)
		_ok("%s 模板存在且限红装" % id, tpl != null
			and GameConstants.rarity_from_key("mythic") == tpl.rarity_min
			and GameConstants.rarity_from_key("mythic") == tpl.rarity_max)
	var hidden_ids := ["hidden_amulet_first_tale", "hidden_boots_scavenger"]
	for id in hidden_ids:
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(id)
		_ok("%s 模板存在且限彩装 + 不可分解" % id, tpl != null
			and GameConstants.rarity_from_key("hidden") == tpl.rarity_min
			and tpl.undismantlable)
	_ok("其一成长配置 all_attributes/5",
		ConfigLoader.get_equipment_template("hidden_amulet_first_tale").growth_stat_key == "all_attributes"
		and ConfigLoader.get_equipment_template("hidden_amulet_first_tale").growth_max == 5.0)
	_ok("拾荒者成长配置 move_speed/15",
		ConfigLoader.get_equipment_template("hidden_boots_scavenger").growth_stat_key == "move_speed"
		and ConfigLoader.get_equipment_template("hidden_boots_scavenger").growth_max == 15.0)


# =============================================================================
# B. 神话词缀
# =============================================================================

func _test_mythic_slot() -> void:
	print("--- B. 神话词缀独立槽 ---")
	var myth := _make("mythic_crown_seven_kalpa", GameConstants.Rarity.MYTHIC)
	var has_mythic := false
	for roll in myth.affixes:
		if roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID:
			has_mythic = true
	_ok("红装含神话词缀", has_mythic)
	var legend := _make("sword_iron", GameConstants.Rarity.LEGENDARY)
	var lg_mythic := false
	for roll in legend.affixes:
		if roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID:
			lg_mythic = true
	_ok("橙装不含神话词缀", not lg_mythic)


# =============================================================================
# C. 神话重铸
# =============================================================================

func _test_reroll() -> void:
	print("--- C. 神话重铸 ---")
	var myth := _make("mythic_crown_seven_kalpa", GameConstants.Rarity.MYTHIC)
	_ok("红装重铸成本 = 结晶 ×2", _dict_eq(MythicRerollController.get_reroll_cost(myth), {MaterialBag.KEY_CRYSTAL: 2}))
	_ok("红装可重铸", MythicRerollController.can_reroll(myth))
	var old_val := 0.0
	for roll in myth.affixes:
		if roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID:
			old_val = roll.value
	var ok := MythicRerollController.try_reroll_mythic(myth, _rng)
	var new_val := 0.0
	for roll in myth.affixes:
		if roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID:
			new_val = roll.value
	_ok("重掷成功且数值变化（或同值但调用返回 true）", ok and new_val > 0.0)
	var legend := _make("sword_iron", GameConstants.Rarity.LEGENDARY)
	_ok("非红装不可重铸 / 成本空", not MythicRerollController.can_reroll(legend)
		and MythicRerollController.get_reroll_cost(legend).is_empty())
	var hidden := _make("hidden_amulet_first_tale", GameConstants.Rarity.HIDDEN)
	_ok("彩装不可重铸 / 成本空", not MythicRerollController.can_reroll(hidden)
		and MythicRerollController.get_reroll_cost(hidden).is_empty())


# =============================================================================
# D. 彩装成长
# =============================================================================

func _test_growth() -> void:
	print("--- D. 彩装成长 ---")
	var amulet := _make("hidden_amulet_first_tale", GameConstants.Rarity.HIDDEN)
	_ok("其一可成长", HiddenGrowthController.can_grow(amulet))
	var applied := HiddenGrowthController.apply_growth(amulet, 1.0)
	_ok("应用 +1%（实际 +1.0）", applied == 1.0 and amulet.growth_value == 1.0)
	HiddenGrowthController.apply_growth(amulet, 4.0)
	_ok("累积到上限 5% 停", amulet.growth_value == 5.0)
	var applied_full := HiddenGrowthController.apply_growth(amulet, 3.0)
	_ok("满上限后再加不涨（实际 +0）", applied_full == 0.0 and amulet.growth_value == 5.0)
	var boots := _make("hidden_boots_scavenger", GameConstants.Rarity.HIDDEN)
	HiddenGrowthController.apply_growth(boots, 20.0)
	_ok("拾荒者上限 15%（非 20）", boots.growth_value == 15.0)
	var bonus := HiddenGrowthController.get_growth_bonus(amulet)
	_ok("成长加成映射 all_attributes: 5", bonus.has("all_attributes") and float(bonus["all_attributes"]) == 5.0)
	_ok("非彩装不可成长", not HiddenGrowthController.can_grow(_make("sword_iron", GameConstants.Rarity.LEGENDARY)))


# =============================================================================
# E. 成长并入
# =============================================================================

func _test_merge() -> void:
	print("--- E. 成长并入属性结算 ---")
	var amulet := EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("hidden_amulet_first_tale"), 20, GameConstants.Rarity.HIDDEN)
	var attack_before: float = StatCalculator.calculate(1, [amulet])["attack"]
	HiddenGrowthController.apply_growth(amulet, 5.0) # +5% 全属性
	var attack_after: float = StatCalculator.calculate(1, [amulet])["attack"]
	_ok("全属性成长并入乘算（+5% → 攻击 ×1.05）",
		_near(attack_after, attack_before * 1.05))
	var boots := EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("hidden_boots_scavenger"), 20, GameConstants.Rarity.HIDDEN)
	HiddenGrowthController.apply_growth(boots, 10.0)
	var stats2 := StatCalculator.calculate(1, [boots])
	_ok("移速成长并入直接键（≥ 底材 18 + 成长 10）", stats2["move_speed"] >= 28.0)


# =============================================================================
# F. 彩装保护
# =============================================================================

func _test_protect() -> void:
	print("--- F. 彩装保护 ---")
	var amulet := _make("hidden_amulet_first_tale", GameConstants.Rarity.HIDDEN)
	_ok("彩装不可分解（3.8 拦截）", not DismantleController.can_dismantle(amulet))
	_ok("彩装不可重铸（本任务拦截）", not MythicRerollController.can_reroll(amulet))
	_ok("彩装 try_dismantle 空", DismantleController.try_dismantle(amulet).is_empty())


# =============================================================================
# G. 边界
# =============================================================================

func _test_edge() -> void:
	print("--- G. 边界 ---")
	_ok("null 不可重铸", not MythicRerollController.can_reroll(null))
	_ok("null 成长成本空", HiddenGrowthController.get_growth_bonus(null).is_empty())
	_ok("null 成长不可用", not HiddenGrowthController.can_grow(null))
	_ok("重掷 null rng 拒绝", not MythicRerollController.try_reroll_mythic(
		_make("mythic_crown_seven_kalpa", GameConstants.Rarity.MYTHIC), null))


func _dict_eq(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in b:
		if int(a.get(k, -999)) != int(b[k]):
			return false
	return true


func _near(a: float, b: float, tol: float = 0.5) -> bool:
	return absf(a - b) <= tol


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
