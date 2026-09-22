## 套装系统实测（任务 3.10 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_set_system.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 数据：3 套注册、每套 6 件、2/4/6 档齐全
##   B. 计数：count_pieces 按部位去重
##   C. 档位：2 件 → [2 档]；4 件 → [2,4]；6 件 → [2,4,6]
##   D. 统计加成：get_bonus_stats 数值汇总（2 件霜噬 +15 冰伤 / 6 件烬途 +20% 攻）
##   E. 进度：get_progress 每套 6 段 + 档位 active 标记
##   F. 面板：SetPanel 渲染（进度条段数 / 文案）
##   G. 边界：非套装装备、null、重复部位
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
	print("===== 套装系统实测（任务 3.10） =====")
	_rng.seed = 20260916
	await _test_data()
	await _test_count()
	await _test_tiers()
	await _test_stats()
	await _test_progress()
	await _test_panel()
	await _test_edge()
	_finish()


func _make_set_item(set_id: String, template_id: String, slot: int) -> EquipmentInstance:
	var item := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template(template_id), 20, GameConstants.Rarity.SET, _rng)
	item.slot = slot
	return item


# =============================================================================
# A. 数据
# =============================================================================

func _test_data() -> void:
	print("--- A. 数据 ---")
	_ok("3 套注册", ConfigLoader.sets.size() == 3)
	for set_id in ConfigLoader.sets:
		var info: Dictionary = ConfigLoader.sets[set_id]
		var pieces: Array = info.get("piece_template_ids", [])
		var tiers: Array = info.get("tier_bonuses", [])
		_ok("%s 6 件 + 3 档" % set_id, pieces.size() == 6 and tiers.size() == 3)
		var piece_marks := [2, 4, 6]
		var ok_tiers := true
		for i in range(tiers.size()):
			if int(tiers[i]["pieces"]) != piece_marks[i]:
				ok_tiers = false
		_ok("%s 档位 2/4/6" % set_id, ok_tiers)
	_ok("set_ 模板 set_id 关联", ConfigLoader.get_equipment_template("set_frostbite_helm").set_id == "frostbite")


# =============================================================================
# B. 计数
# =============================================================================

func _test_count() -> void:
	print("--- B. 计数 ---")
	var equipped: Array[EquipmentInstance] = [
		_make_set_item("frostbite", "set_frostbite_helm", GameConstants.EquipSlot.HELM),
		_make_set_item("frostbite", "set_frostbite_chest", GameConstants.EquipSlot.CHEST),
		_make_set_item("emberpath", "set_emberpath_gloves", GameConstants.EquipSlot.GLOVES),
	]
	_ok("霜噬 2 件", SetSystem.count_pieces(equipped, "frostbite") == 2)
	_ok("烬途 1 件", SetSystem.count_pieces(equipped, "emberpath") == 1)
	_ok("守誓者 0 件", SetSystem.count_pieces(equipped, "oathkeeper") == 0)
	# 重复部位（两件头盔）只计 1
	var dup: Array[EquipmentInstance] = [
		_make_set_item("frostbite", "set_frostbite_helm", GameConstants.EquipSlot.HELM),
		_make_set_item("frostbite", "set_frostbite_helm", GameConstants.EquipSlot.HELM),
	]
	_ok("重复部位去重计 1", SetSystem.count_pieces(dup, "frostbite") == 1)


# =============================================================================
# C. 档位
# =============================================================================

func _test_tiers() -> void:
	print("--- C. 档位 ---")
	var t2: Array[EquipmentInstance] = [
		_make_set_item("frostbite", "set_frostbite_helm", GameConstants.EquipSlot.HELM),
		_make_set_item("frostbite", "set_frostbite_chest", GameConstants.EquipSlot.CHEST),
	]
	var tiers2 := SetSystem.get_active_tiers(t2, "frostbite")
	_ok("2 件激活 [2 档]", tiers2.size() == 1 and int(tiers2[0]["pieces"]) == 2)
	var t4: Array[EquipmentInstance] = t2.duplicate()
	t4.append(_make_set_item("frostbite", "set_frostbite_gloves", GameConstants.EquipSlot.GLOVES))
	t4.append(_make_set_item("frostbite", "set_frostbite_legs", GameConstants.EquipSlot.LEGS))
	var tiers4 := SetSystem.get_active_tiers(t4, "frostbite")
	_ok("4 件激活 [2,4]", tiers4.size() == 2 and int(tiers4[1]["pieces"]) == 4)
	var t6: Array[EquipmentInstance] = t4.duplicate()
	t6.append(_make_set_item("frostbite", "set_frostbite_boots", GameConstants.EquipSlot.BOOTS))
	t6.append(_make_set_item("frostbite", "set_frostbite_mainhand", GameConstants.EquipSlot.MAIN_HAND))
	var tiers6 := SetSystem.get_active_tiers(t6, "frostbite")
	_ok("6 件激活 [2,4,6]", tiers6.size() == 3 and int(tiers6[2]["pieces"]) == 6)


# =============================================================================
# D. 统计加成
# =============================================================================

func _test_stats() -> void:
	print("--- D. 统计加成 ---")
	var t2: Array[EquipmentInstance] = [
		_make_set_item("frostbite", "set_frostbite_helm", GameConstants.EquipSlot.HELM),
		_make_set_item("frostbite", "set_frostbite_chest", GameConstants.EquipSlot.CHEST),
	]
	var s2 := SetSystem.get_bonus_stats(t2)
	_ok("2 件霜噬 +15 冰伤", absf(float(s2.get("elemental_damage", 0.0)) - 15.0) < 0.01)
	var t6: Array[EquipmentInstance] = t2.duplicate()
	t6.append(_make_set_item("frostbite", "set_frostbite_gloves", GameConstants.EquipSlot.GLOVES))
	t6.append(_make_set_item("frostbite", "set_frostbite_legs", GameConstants.EquipSlot.LEGS))
	t6.append(_make_set_item("frostbite", "set_frostbite_boots", GameConstants.EquipSlot.BOOTS))
	t6.append(_make_set_item("frostbite", "set_frostbite_mainhand", GameConstants.EquipSlot.MAIN_HAND))
	var s6 := SetSystem.get_bonus_stats(t6)
	_ok("6 件霜噬 +15 冰伤 +20 暴击", absf(float(s6.get("elemental_damage", 0.0)) - 15.0) < 0.01
		and absf(float(s6.get("crit_chance", 0.0)) - 20.0) < 0.01)
	var ember6: Array[EquipmentInstance] = [
		_make_set_item("emberpath", "set_emberpath_helm", GameConstants.EquipSlot.HELM),
		_make_set_item("emberpath", "set_emberpath_chest", GameConstants.EquipSlot.CHEST),
		_make_set_item("emberpath", "set_emberpath_gloves", GameConstants.EquipSlot.GLOVES),
		_make_set_item("emberpath", "set_emberpath_legs", GameConstants.EquipSlot.LEGS),
		_make_set_item("emberpath", "set_emberpath_boots", GameConstants.EquipSlot.BOOTS),
		_make_set_item("emberpath", "set_emberpath_amulet", GameConstants.EquipSlot.AMULET),
	]
	var es := SetSystem.get_bonus_stats(ember6)
	_ok("6 件烬途 +12 火伤 +20% 攻击", absf(float(es.get("elemental_damage", 0.0)) - 12.0) < 0.01
		and absf(float(es.get("pct_attack", 0.0)) - 20.0) < 0.01)


# =============================================================================
# E. 进度
# =============================================================================

func _test_progress() -> void:
	print("--- E. 进度 ---")
	var equipped: Array[EquipmentInstance] = [
		_make_set_item("frostbite", "set_frostbite_helm", GameConstants.EquipSlot.HELM),
		_make_set_item("frostbite", "set_frostbite_chest", GameConstants.EquipSlot.CHEST),
	]
	var progress := SetSystem.get_progress(equipped)
	_ok("进度含 3 套", progress.size() == 3)
	var frost: Dictionary = {}
	for p in progress:
		if p["set_id"] == "frostbite":
			frost = p
	_ok("霜噬进度 2/6", not frost.is_empty() and frost["pieces"] == 2 and frost["piece_total"] == 6)
	_ok("2 件时档位 active = [2,4,6] → [true,false,false]",
		bool(frost["tiers"][0]["active"]) and not bool(frost["tiers"][1]["active"])
		and not bool(frost["tiers"][2]["active"]))


# =============================================================================
# F. 面板
# =============================================================================

func _test_panel() -> void:
	print("--- F. 面板渲染 ---")
	var panel := SetPanel.new()
	add_child(panel)
	var equipped: Array[EquipmentInstance] = [
		_make_set_item("frostbite", "set_frostbite_helm", GameConstants.EquipSlot.HELM),
		_make_set_item("frostbite", "set_frostbite_chest", GameConstants.EquipSlot.CHEST),
		_make_set_item("emberpath", "set_emberpath_gloves", GameConstants.EquipSlot.GLOVES),
	]
	panel.show_sets(equipped)
	_ok("面板渲染 3 套行", panel._box.get_child_count() == 3)
	var first: VBoxContainer = panel._box.get_child(0)
	_ok("首行标题含 x/6", (first.get_child(0) as Label).text.contains("2/6") or (first.get_child(0) as Label).text.contains("1/6"))
	_ok("首行进度条 6 段", (first.get_child(1) as HBoxContainer).get_child_count() == 6)
	panel.queue_free()


# =============================================================================
# G. 边界
# =============================================================================

func _test_edge() -> void:
	print("--- G. 边界 ---")
	_ok("空装备进度返回 3 套（全 0 件）", SetSystem.get_progress([]).size() == 3
		and int(SetSystem.get_progress([])[0]["pieces"]) == 0)
	_ok("null 集合套装为空", SetSystem.get_set_of(null).is_empty())
	var normal := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("sword_iron"), 20, GameConstants.Rarity.LEGENDARY, _rng)
	_ok("非套装装备 get_set_of 为空", SetSystem.get_set_of(normal).is_empty())
	_ok("非套装装备不计入套装", SetSystem.count_pieces([normal], "frostbite") == 0)
	_ok("未知套装计数 0", SetSystem.count_pieces([], "nope") == 0)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
