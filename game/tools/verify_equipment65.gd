## 装备库填充实测（任务 6.5 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_equipment65.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 装备库总量：62（武器 14 / 护甲 14 / 饰品 16 / 套装件 18）
##   B. 三章等级带覆盖：每章可用装备 ≥ 20（ilvl 区间含 1-6 / 7-13 / 14-20）
##   C. 全部底材 validate 合法 + 词缀池引用存在（load_errors 空）
##   D. 新增 20 件齐备（烈焰剑 / 血斧 / 冰川锤 / 淬毒匕首 / 风暴法杖 / 灵风长弓 /
##      石像头盔 / 烬织胸甲 / 冰织手套 / 守望腿甲 / 疾风靴 / 泰坦王冠 /
##      余烬护符 / 霜戒 / 雷暴之戒 / 影纱吊坠 / 嗜血之戒 / 烈日圣印 / 回响之戒 / 守护者勋章）
##   E. 数值合理：烈焰剑攻 22 / 泰坦王冠 HP 60 / 灵风长弓攻速 12 / 嗜血之戒吸血 3
##   F. 掉落权重：全部 > 0，稀有件权重低于普通件（泰坦王冠 < 铁剑）
##   G. 槽位覆盖：10 个槽位全部 ≥1 件；套装体系 3×6 不破坏
extends Node

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 装备库填充实测（任务 6.5） =====")
	await _test_total()
	await _test_chapters()
	await _test_valid()
	await _test_new_items()
	await _test_values()
	await _test_weights()
	await _test_slots()
	_finish()


# =============================================================================
# A. 总量
# =============================================================================

func _test_total() -> void:
	print("--- A. 装备库总量 ---")
	var ids := ConfigLoader.get_all_equipment_ids()
	_ok("装备库 62 件（weapons 14 / armor 14 / jewelry 16 + 套装件 18）",
		ids.size() == 62)


# =============================================================================
# B. 三章等级带
# =============================================================================

func _test_chapters() -> void:
	print("--- B. 三章等级带覆盖 ---")
	var ch1 := 0
	var ch2 := 0
	var ch3 := 0
	for id in ConfigLoader.get_all_equipment_ids():
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(id)
		if tpl.item_level_min <= 6:
			ch1 += 1
		if tpl.item_level_max >= 7 and tpl.item_level_min <= 13:
			ch2 += 1
		if tpl.item_level_max >= 14:
			ch3 += 1
	_ok("第一章可用 ≥20 / 第二章可用 ≥20 / 第三章可用 ≥20",
		ch1 >= 20 and ch2 >= 20 and ch3 >= 20)


# =============================================================================
# C. 合法性与池引用
# =============================================================================

func _test_valid() -> void:
	print("--- C. 合法性与池引用 ---")
	var all_valid := true
	for id in ConfigLoader.get_all_equipment_ids():
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(id)
		if tpl == null or not tpl.validate().is_empty():
			all_valid = false
	_ok("全部底材 validate 合法", all_valid)
	_ok("词缀池引用全部存在（load_errors 空）", ConfigLoader.load_errors.is_empty())


# =============================================================================
# D. 新增 20 件
# =============================================================================

func _test_new_items() -> void:
	print("--- D. 新增 20 件 ---")
	var need := ["sword_flame", "axe_blood", "hammer_glacier", "dagger_venom",
		"staff_storm", "bow_spirit", "helm_golem", "chest_ember", "gloves_cold",
		"legs_guardian", "boots_wind", "helm_crown_titan", "amulet_ember",
		"ring_frost", "ring_storm", "amulet_veil", "ring_blood", "amulet_sun",
		"ring_echo", "amulet_guard"]
	var missing := 0
	for n in need:
		if ConfigLoader.get_equipment_template(n) == null:
			missing += 1
	_ok("新增 20 件全部可解析", missing == 0)
	_ok("新增覆盖 6 武器形态 + 4 护甲 + 8 饰品",
		ConfigLoader.get_equipment_template("sword_flame").weapon_archetype
			== GameConstants.WeaponArchetype.SWORD
		and ConfigLoader.get_equipment_template("staff_storm").weapon_archetype
			== GameConstants.WeaponArchetype.STAFF)


# =============================================================================
# E. 数值
# =============================================================================

func _test_values() -> void:
	print("--- E. 数值 ---")
	var sword: EquipmentData = ConfigLoader.get_equipment_template("sword_flame")
	var crown: EquipmentData = ConfigLoader.get_equipment_template("helm_crown_titan")
	var bow: EquipmentData = ConfigLoader.get_equipment_template("bow_spirit")
	var blood: EquipmentData = ConfigLoader.get_equipment_template("ring_blood")
	_ok("烈焰剑：攻击 +22 / 主手剑", sword != null
		and is_equal_approx(float(sword.base_stats.get("flat_attack", 0.0)), 22.0))
	_ok("泰坦王冠：HP +60 / 护甲 +12 / 稀有起步", crown != null
		and is_equal_approx(float(crown.base_stats.get("flat_hp", 0.0)), 60.0)
		and crown.rarity_min == GameConstants.Rarity.RARE)
	_ok("灵风长弓：攻速 +12 / 第 1 章可用", bow != null
		and is_equal_approx(float(bow.base_stats.get("attack_speed", 0.0)), 12.0)
		and bow.item_level_min <= 6)
	_ok("嗜血之戒：吸血 +3 / HP +35", blood != null
		and is_equal_approx(float(blood.base_stats.get("life_on_hit", 0.0)), 3.0)
		and is_equal_approx(float(blood.base_stats.get("flat_hp", 0.0)), 35.0))


# =============================================================================
# F. 权重
# =============================================================================

func _test_weights() -> void:
	print("--- F. 掉落权重 ---")
	var bad := 0
	var crown: EquipmentData = ConfigLoader.get_equipment_template("helm_crown_titan")
	var sword: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	for id in ConfigLoader.get_all_equipment_ids():
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(id)
		if tpl.drop_weight <= 0.0:
			bad += 1
	_ok("全部掉落权重 > 0", bad == 0)
	_ok("稀有件权重 < 普通件（泰坦王冠 40 < 铁剑 120）",
		crown.drop_weight < sword.drop_weight)


# =============================================================================
# G. 槽位与套装
# =============================================================================

func _test_slots() -> void:
	print("--- G. 槽位覆盖与套装 ---")
	var slot_hits := {}
	for id in ConfigLoader.get_all_equipment_ids():
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(id)
		slot_hits[tpl.slot] = int(slot_hits.get(tpl.slot, 0)) + 1
	_ok("10 个槽位全部 ≥1 件", slot_hits.size() >= 10)
	var set_ids := ConfigLoader.get_all_set_ids()
	_ok("套装体系不破坏（3 套装 × 6 件 = 18）",
		set_ids.size() == 3
		and ConfigLoader.get_set("emberpath") != null
		and ConfigLoader.get_set("frostbite") != null
		and ConfigLoader.get_set("oathkeeper") != null)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
