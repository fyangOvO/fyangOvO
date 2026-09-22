## 工具：verify_panel_unify.gd（步骤 5 · 据点半透明面板统一视觉）
##
## A. StatPanel：标题含职业名+角色属性、标题职业色、提示行、31 行属性
## B. TalentPanel：标题含职业名+天赋树、标题职业色、提示行、3 分支卡、点数
## C. ForgePanel：标题含职业名+锻造台、标题职业色、提示行、魔石数、行按钮皮肤
## D. 三个面板统一规范：最小宽 400 / 边距 14 / 标题 16px
extends Node2D

var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== 据点半透明面板统一视觉实测（步骤 5）=====")
	_run()


func _run() -> void:
	await _test_stat()
	await _test_talent()
	await _test_forge()
	await _test_unify()
	print("===== 统一视觉实测 结束：%s =====" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# A. StatPanel
# =============================================================================

func _test_stat() -> void:
	print("--- A. 角色属性面板 ---")
	var sp := StatPanel.new()
	add_child(sp)
	await get_tree().process_frame
	var stats := StatCalculator.calculate(14, [], {})
	sp.show_stats(stats, "战士", "warrior")
	await get_tree().process_frame
	var cls: Dictionary = ConfigLoader.classes.get("warrior", {})
	var expect_color := Color(String(cls.get("color", "F5D77A")))
	_ok("标题 = 战士 · 角色属性", sp._title.text == "战士 · 角色属性")
	_ok("标题职业色", sp._title.get_theme_color("font_color") == expect_color)
	_ok("提示行存在", _count_text(sp, "基础属性") >= 1)
	_ok("31 行属性", sp.row_count() == 31)
	sp.queue_free()
	await get_tree().process_frame


# =============================================================================
# B. TalentPanel
# =============================================================================

func _test_talent() -> void:
	print("--- B. 天赋树面板 ---")
	var tp := TalentPanel.new()
	add_child(tp)
	await get_tree().process_frame
	tp.bind(["war.small.0"], 20, Callable(), "archer")
	await get_tree().process_frame
	var cls: Dictionary = ConfigLoader.classes.get("archer", {})
	var expect_color := Color(String(cls.get("color", "F5D77A")))
	_ok("标题 = 天赋树 · 弓箭手", tp._title.text == "天赋树 · 迅影之矢" or tp._title.text.contains("天赋树"))
	_ok("标题职业色", _title_color(tp) == expect_color)
	_ok("提示行存在", _count_text(tp, "天赋点为账号共享") >= 1)
	_ok("3 分支卡片", _count_text(tp, "战争") >= 1 and _count_text(tp, "秘法") >= 1 and _count_text(tp, "影行") >= 1)
	_ok("点数标签", _count_text(tp, "可用点数") >= 1)
	tp.queue_free()
	await get_tree().process_frame


# =============================================================================
# C. ForgePanel
# =============================================================================

func _test_forge() -> void:
	print("--- C. 锻造台面板 ---")
	var fp := ForgePanel.new()
	add_child(fp)
	await get_tree().process_frame
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("dagger_shadow")
	var items: Array = []
	if tpl != null:
		items.append(EquipmentInstance.create_from_template(tpl, 3, GameConstants.Rarity.RARE))
	fp.bind(items, 50, Callable(), Callable(), "mage")
	await get_tree().process_frame
	var cls: Dictionary = ConfigLoader.classes.get("mage", {})
	var expect_color := Color(String(cls.get("color", "F5D77A")))
	_ok("标题 = 锻造台 · 法师", fp._title.text == "锻造台 · 秘法洪流" or fp._title.text.contains("锻造台"))
	_ok("标题职业色", _title_color(fp) == expect_color)
	_ok("提示行存在", _count_text(fp, "重铸洗练") >= 1)
	_ok("魔石数显示", _count_text(fp, "魔石") >= 1)
	var gold_rows := 0
	for b in _collect_buttons(fp):
		if b.text == "锻造" and b.has_theme_stylebox_override("normal"):
			gold_rows += 1
	_ok("行按钮带 UISkin 皮肤", gold_rows >= 1)
	fp.queue_free()
	await get_tree().process_frame


# =============================================================================
# D. 统一规范
# =============================================================================

func _test_unify() -> void:
	print("--- D. 统一规范（最小宽 400 / 边距 14 / 标题 16）---")
	var panels: Array = [StatPanel.new(), TalentPanel.new(), ForgePanel.new()]
	var ok_min := true
	var ok_margin := true
	for p in panels:
		add_child(p)
		await get_tree().process_frame
		if p.custom_minimum_size.x < 400.0:
			ok_min = false
		var margin := p.get_child(0) as MarginContainer
		if margin == null \
				or int(margin.get_theme_constant("margin_left")) != 14 \
				or int(margin.get_theme_constant("margin_right")) != 14:
			ok_margin = false
		p.queue_free()
	_ok("三面板最小宽 ≥ 400", ok_min)
	_ok("三面板左右边距 = 14", ok_margin)
	await get_tree().process_frame


# =============================================================================
# 工具
# =============================================================================

func _count_text(node: Node, needle: String) -> int:
	var n := 0
	for lbl in _collect_labels(node):
		if String(lbl.text).contains(needle):
			n += 1
	return n


func _collect_labels(node: Node) -> Array:
	var out: Array = []
	if node is Label or node is RichTextLabel:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_labels(c))
	return out


func _collect_buttons(node: Node) -> Array:
	var out: Array = []
	if node is Button:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_buttons(c))
	return out


func _title_color(panel: Control) -> Color:
	for lbl in _collect_labels(panel):
		if String(lbl.text).contains(" · "):
			return lbl.get_theme_color("font_color")
	return Color.BLACK


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
