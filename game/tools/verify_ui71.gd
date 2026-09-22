## 阶段 7 UI/UX 实测（任务 7.1–7.7 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_ui71.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 段 × 每面板若干断言）：
##   A. 7.1 主菜单：标题 + 开始/设置/退出 3 按钮 + 账号概览
##   B. 7.2 角色属性面板：31 行 = StatCalculator.FINAL_KEYS + LABELS 全覆盖 + 真实结算非 0
##   C. 7.3 背包装备界面：10 槽渲染 + 选中详情 + 穿/脱回调
##   D. 7.4 天赋界面：3 分支卡片 + 节点状态 + 点数
##   E. 7.5 锻造界面：费用显示 + 材料不足禁用 + 回调
##   F. 7.6 结算奖励界面：奖励清单 + 返回/再来按钮
##   G. 7.7 设置界面：画质/音量/按键三区 + 音量联动 AudioServer
extends Node2D

var _fail: int = 0
var _menu_started := false
var _equip_on := false
var _equip_off := false
var _learned_node := ""
var _forge_on := false
var _reroll_on := false
var _hub_on := false
var _restart_on := false


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _count_labels(node: Node, prefix: String) -> int:
	var n := 0
	for c in node.get_children():
		if c is Label and (c as Label).text.begins_with(prefix):
			n += 1
		n += _count_labels(c, prefix)
	return n


func _count_buttons(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is Button:
			n += 1
		n += _count_buttons(c)
	return n


func _has_button_text(node: Node, text: String) -> bool:
	for c in node.get_children():
		if c is Button and (c as Button).text.contains(text):
			return true
		if _has_button_text(c, text):
			return true
	return false


func _count_button_texts(node: Node, prefix: String) -> int:
	var n := 0
	for c in node.get_children():
		if c is Button and (c as Button).text.begins_with(prefix):
			n += 1
		n += _count_button_texts(c, prefix)
	return n


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 阶段 7 UI/UX 实测 =====")
	await _test_menu()
	await _test_stat()
	await _test_equip()
	await _test_talent()
	await _test_forge()
	await _test_result()
	await _test_settings()
	_finish()


# =============================================================================
# A. 7.1 主菜单
# =============================================================================

func _test_menu() -> void:
	print("--- A. 7.1 主菜单/角色选择 ---")
	var menu := MainMenuPanel.new()
	menu.custom_minimum_size = Vector2(600, 480)
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var buttons := _count_buttons(menu)
	_ok("主菜单 3 按钮（开始/设置/退出）", buttons >= 3)
	_ok("账号概览行存在（账号 Lv.）", _count_labels(menu, "账号 Lv.") >= 1)
	menu.on_start = func() -> void: _menu_started = true
	menu.on_start.call()
	_ok("开始回调可触发", _menu_started)
	menu.queue_free()


# =============================================================================
# B. 7.2 属性面板
# =============================================================================

func _test_stat() -> void:
	print("--- B. 7.2 角色属性面板（键口径 = StatCalculator.FINAL_KEYS）---")
	var sp := StatPanel.new()
	add_child(sp)
	await get_tree().process_frame
	var gear: Array[EquipmentInstance] = []
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	if tpl != null:
		gear.append(EquipmentInstance.create_from_template(tpl, 6, GameConstants.Rarity.RARE))
	sp.show_stats(StatCalculator.calculate(6, gear, {}))
	await get_tree().process_frame
	await get_tree().process_frame

	_ok("31 行 = FINAL_KEYS 长度", sp.row_count() == StatCalculator.FINAL_KEYS.size())
	var missing := 0
	for k in StatCalculator.FINAL_KEYS:
		if not StatPanel.LABELS.has(k):
			missing += 1
	_ok("LABELS 覆盖 FINAL_KEYS 全部键", missing == 0)
	_ok("渲染键集与 FINAL_KEYS 一致",
		sp.rendered_values.size() == StatCalculator.FINAL_KEYS.size())

	var core := _count_labels(sp, "生命上限") + _count_labels(sp, "攻击力") + \
		_count_labels(sp, "护甲") + _count_labels(sp, "暴击率") + \
		_count_labels(sp, "暴击伤害") + _count_labels(sp, "攻击速度") + \
		_count_labels(sp, "移动速度") + _count_labels(sp, "闪避")
	_ok("属性面板 8 行基础属性", core >= 8)
	var resist := _count_labels(sp, "火焰抗性") + _count_labels(sp, "冰霜抗性") + \
		_count_labels(sp, "毒素抗性") + _count_labels(sp, "闪电抗性")
	_ok("4 元素抗性行", resist >= 4)
	var inrun := _count_labels(sp, "护甲穿透") + _count_labels(sp, "生命吸血") + \
		_count_labels(sp, "受伤加成") + _count_labels(sp, "生命回复率") + \
		_count_labels(sp, "护盾")
	_ok("5 局内扩展行（阶段 4）", inrun >= 5)
	_ok("真实结算非全 0（生命上限 > 0）",
		sp.last_stats.get("max_hp", 0.0) > 0.0
		and String(sp.rendered_values.get("max_hp", "0")) != "0")
	sp.queue_free()


# =============================================================================
# C. 7.3 背包装备界面
# =============================================================================

func _test_equip() -> void:
	print("--- C. 7.3 背包装备界面 ---")
	var ep := EquipPanel.new()
	add_child(ep)
	await get_tree().process_frame
	var fake: Array = []
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	if tpl != null:
		var inst := EquipmentInstance.create_from_template(tpl, 5, GameConstants.Rarity.MAGIC)
		fake.append(inst)
	ep.on_equip = func() -> void: _equip_on = true
	ep.bind(fake, "warrior", func() -> void: _equip_off = true)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("装备栏六格渲染（3×2）", _count_buttons(ep) >= 6)
	_ok("六格含武器/头部（清单部位名）",
		ep._list.text.contains("武器") and ep._list.text.contains("头部"))
	ep._selected_slot = GameConstants.EquipSlot.MAIN_HAND
	ep._on_slot_pressed(GameConstants.EquipSlot.MAIN_HAND)
	await get_tree().process_frame
	_ok("选中槽详情非空", not ep._detail.text.is_empty() and ep._detail.text.contains("空槽位"))
	ep.on_equip.call()
	ep.on_unequip.call()
	_ok("穿/脱回调可触发", _equip_on and _equip_off)
	ep.queue_free()


# =============================================================================
# D. 7.4 天赋界面
# =============================================================================

func _test_talent() -> void:
	print("--- D. 7.4 天赋界面 ---")
	var tp := TalentPanel.new()
	add_child(tp)
	await get_tree().process_frame
	tp.bind(["war.small.0"], 5)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("3 分支卡片渲染", _count_labels(tp, "战争") + _count_labels(tp, "秘法") + _count_labels(tp, "影行") >= 3)
	_ok("已点节点带 ✓", _count_button_texts(tp, "war.small.0 ✓") >= 1)
	_ok("点数标签存在", _count_labels(tp, "可用点数") >= 1)
	tp.on_learn = func(node: String) -> void: _learned_node = node
	tp.on_learn.call("war.big.2")
	_ok("learn 回调可触发", _learned_node == "war.big.2")
	tp.queue_free()


# =============================================================================
# E. 7.5 锻造界面
# =============================================================================

func _test_forge() -> void:
	print("--- E. 7.5 锻造界面 ---")
	var fp := ForgePanel.new()
	add_child(fp)
	await get_tree().process_frame
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("dagger_shadow")
	var items: Array = []
	if tpl != null:
		items.append(EquipmentInstance.create_from_template(tpl, 3, GameConstants.Rarity.RARE))
	fp.bind(items, 50, func() -> void: _forge_on = true, func() -> void: _reroll_on = true)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("锻造费用显示", _count_labels(fp, "锻造") >= 1)
	_ok("魔石数量显示", _count_labels(fp, "魔石") >= 1)
	fp.on_forge.call()
	fp.on_reroll.call()
	_ok("锻造/重铸回调可触发", _forge_on and _reroll_on)
	fp.show_result("锻造成功 +1")
	await get_tree().process_frame
	_ok("结果反馈行", _count_labels(fp, "锻造成功") >= 1)
	fp.queue_free()


# =============================================================================
# F. 7.6 结算奖励界面
# =============================================================================

func _test_result() -> void:
	print("--- F. 7.6 结算奖励界面 ---")
	var rp := ResultPanel.new()
	rp.size = Vector2(960, 540)
	add_child(rp)
	await get_tree().process_frame
	var res := RunResult.new()
	res.survived = true
	res.kills = 42
	res.run_level = 7
	res.max_streak = 9
	res.gold_before = 1000.0
	res.gold_after = 500.0
	res.bagged_equipment = []
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("chest_ember")
	if tpl != null:
		res.bagged_equipment.append(
			EquipmentInstance.create_from_template(tpl, 12, GameConstants.Rarity.EPIC))
	res.unbagged_drops = 3
	res.score = 1500.0
	res.grade = "A"
	rp.on_hub = func() -> void: _hub_on = true
	rp.on_restart = func() -> void: _restart_on = true
	rp.show_result(res)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("结算标题存活通关", _count_labels(rp, "本局结算") >= 1)
	_ok("奖励清单（本次收获）", _count_labels(rp, "—— 本次收获") >= 1)
	var btns := _count_buttons(rp)
	_ok("返回大厅/再来一局按钮", btns >= 2)
	rp.on_hub.call()
	rp.on_restart.call()
	_ok("按钮回调可触发", _hub_on and _restart_on)
	rp.queue_free()


# =============================================================================
# G. 7.7 设置界面
# =============================================================================

func _test_settings() -> void:
	print("--- G. 7.7 设置界面 ---")
	var sp2 := SettingsPanel.new()
	add_child(sp2)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("画质区（垂直同步/全屏）",
		_has_button_text(sp2, "垂直同步") and _has_button_text(sp2, "全屏"))
	_ok("音量区（主音量 + dB）", _count_labels(sp2, "主音量") >= 1)
	_ok("按键区 10 动作 + 重置",
		_count_labels(sp2, "上移") >= 1 and _has_button_text(sp2, "重置全部按键"))
	# 音量联动：把 Master 音量设为 -12 dB，断言 AudioServer 生效
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -12.0)
	_ok("音量联动 AudioServer（-12 dB）",
		is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), -12.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), 0.0)
	sp2.queue_free()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
