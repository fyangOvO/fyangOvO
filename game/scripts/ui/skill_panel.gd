## 技能管理面板（步骤 3 · 2026-09-22 · class_name）
##
## 位置：据点半透明浮层（PANEL_SKILLS，与背包/角色/装备等并列）。
## 职责：查看职业专属技能池 + 重排出战技能栏（1/2/3 键），保存到存档。
## 升级系统：**本页不做**（形态未定，后续单独做）。
##
## 交互（v1，无拖拽）：
##   · 点击技能池卡片 → 装配到出战栏第一个空位（栏满则提示）
##   · 点击出战槽 → 卸下该技能（重排 = 卸下后按顺序重装）
##   · [恢复默认] → 恢复职业默认出战栏（不落盘，需再点保存）
##   · [保存] → 写入存档（出战栏不允许为空）
##
## 数据流：hub 是唯一数据源。`bind()` 注入 class_id / 池 / 当前栏 / on_save 回调。
class_name SkillPanel
extends PanelContainer

## 出战栏槽数（与 project.godot skill_1/2/3 + PlayerController 输入一致）
const BAR_SLOTS: int = 3
## 技能图标显示尺寸：48×48 原生 1× 整数（像素铁律）
const ICON_PX: float = 48.0

var _class_id: String = GameConstants.CLASS_DEFAULT
var _pool: Array[String] = []
var _bar: Array[String] = []
## 保存回调：`func(bar: Array[String]) -> void`（hub 写存档 + 提示）
var on_save: Callable = Callable()

## 验证 / 测试用：当前工作区出战栏（保存前）
var bar: Array[String] = []

var _title: Label = null
var _info: Label = null
var _pool_grid: GridContainer = null
var _bar_row: HBoxContainer = null


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 282)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	vb.add_child(_title)

	var hint := Label.new()
	hint.text = "点击技能池装配出战 · 点击出战槽卸下 · 重排 = 卸下后按顺序重装"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(hint)

	var pool_l := Label.new()
	pool_l.text = "技能池（职业专属）"
	pool_l.add_theme_font_size_override("font_size", 12)
	pool_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	vb.add_child(pool_l)

	_pool_grid = GridContainer.new()
	_pool_grid.columns = 5
	_pool_grid.add_theme_constant_override("h_separation", 6)
	_pool_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_pool_grid)

	var bar_l := Label.new()
	bar_l.text = "出战技能栏（1 / 2 / 3 键）"
	bar_l.add_theme_font_size_override("font_size", 12)
	bar_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	vb.add_child(bar_l)

	_bar_row = HBoxContainer.new()
	_bar_row.add_theme_constant_override("separation", 10)
	vb.add_child(_bar_row)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(_info)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	vb.add_child(bottom)
	var reset := _make_btn("恢复默认", "dark")
	reset.pressed.connect(func() -> void:
		_bar = ConfigLoader.class_default_skill_bar(_class_id).duplicate()
		_refresh()
		_info.text = "已恢复职业默认出战栏，记得点保存")
	bottom.add_child(reset)
	var save := _make_btn("保存技能栏", "gold")
	save.pressed.connect(_on_save_pressed)
	bottom.add_child(save)


func _make_btn(text: String, kind: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(128, 34)
	btn.add_theme_font_size_override("font_size", 14)
	var boxes := UISkin.btn_styleboxes(kind)
	for state in ["normal", "hover", "pressed"]:
		if boxes.has(state):
			btn.add_theme_stylebox_override(state, boxes[state])
	return btn


## hub 注入数据；每次打开（refresh）都会重新调用
func bind(p_class_id: String, p_pool: Array[String], p_bar: Array[String],
		p_on_save: Callable) -> void:
	_class_id = p_class_id
	_pool = p_pool.duplicate()
	_bar = p_bar.duplicate()
	on_save = p_on_save
	var cls: Dictionary = ConfigLoader.classes.get(_class_id, {})
	_title.text = "技能 · %s" % ConfigLoader.class_display_name(_class_id)
	_title.add_theme_color_override("font_color",
		Color(String(cls.get("color", "F5D77A"))))
	_refresh()


func _refresh() -> void:
	bar = _bar.duplicate()
	_render_pool()
	_render_bar()


func _render_pool() -> void:
	for c in _pool_grid.get_children():
		c.queue_free()
	for sid in _pool:
		var card := Control.new()
		card.custom_minimum_size = Vector2(56, 64)
		_pool_grid.add_child(card)

		var btn := Button.new()
		btn.name = "PoolBtn_%s" % sid
		btn.custom_minimum_size = Vector2(56, 48)
		btn.position = Vector2(0, 0)
		btn.add_theme_stylebox_override("normal", _card_box(false))
		btn.add_theme_stylebox_override("hover", _card_box(true))
		btn.add_theme_stylebox_override("pressed", _card_box(true))
		btn.icon = UISkin.texture(_icon_key(sid))
		btn.expand_icon = true
		btn.pressed.connect(func() -> void: _on_pool_clicked(sid))
		card.add_child(btn)

		var name_l := Label.new()
		name_l.text = _display_name(sid)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
		name_l.position = Vector2(0, 50)
		name_l.size = Vector2(56, 14)
		card.add_child(name_l)


func _render_bar() -> void:
	for c in _bar_row.get_children():
		c.queue_free()
	for i in BAR_SLOTS:
		var sid := _bar[i] if i < _bar.size() else ""
		var slot := Control.new()
		slot.name = "BarSlot%d" % i
		slot.custom_minimum_size = Vector2(76, 66)
		_bar_row.add_child(slot)

		var btn := Button.new()
		btn.name = "BarBtn%d" % i
		btn.custom_minimum_size = Vector2(76, 48)
		btn.position = Vector2(0, 0)
		btn.add_theme_stylebox_override("normal", _card_box(false))
		btn.add_theme_stylebox_override("hover", _card_box(true))
		btn.add_theme_stylebox_override("pressed", _card_box(true))
		btn.icon = UISkin.texture(_icon_key(sid)) if not sid.is_empty() else UISkin.texture("skill_slot")
		btn.expand_icon = true
		btn.pressed.connect(func() -> void: _on_bar_clicked(i))
		slot.add_child(btn)

		# 键位角标 1/2/3
		var key_l := Label.new()
		key_l.text = str(i + 1)
		key_l.add_theme_font_size_override("font_size", 12)
		key_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
		key_l.position = Vector2(2, 0)
		slot.add_child(key_l)

		var name_l := Label.new()
		name_l.text = _display_name(sid) if not sid.is_empty() else "空位"
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color",
			GameConstants.PALETTE_NEUTRAL[7] if sid.is_empty() else GameConstants.PALETTE_NEUTRAL[9])
		name_l.position = Vector2(0, 50)
		name_l.size = Vector2(76, 14)
		slot.add_child(name_l)


## 技能池点击：装到第一个空位；已在栏 / 栏满 → 提示
func _on_pool_clicked(sid: String) -> void:
	if _bar.has(sid):
		_info.text = "「%s」已在出战栏" % _display_name(sid)
		return
	if _bar.size() >= BAR_SLOTS:
		_info.text = "出战栏已满（%d 格），先点击出战槽卸下再装配" % BAR_SLOTS
		return
	_bar.append(sid)
	_info.text = "已装配「%s」（未保存）" % _display_name(sid)
	_refresh()


## 出战槽点击：卸下（重排 = 卸下后按顺序重装）
func _on_bar_clicked(index: int) -> void:
	if index >= _bar.size():
		return
	var sid := _bar[index]
	_bar.remove_at(index)
	_info.text = "已卸下「%s」（未保存）" % _display_name(sid)
	_refresh()


func _on_save_pressed() -> void:
	if _bar.is_empty():
		_info.text = "出战栏不能为空，请先装配至少 1 个技能"
		return
	if on_save.is_valid():
		on_save.call(_bar.duplicate())
	_info.text = "已保存：%s" % ", ".join(_bar.map(_display_name))


func _display_name(sid: String) -> String:
	var sd := ConfigLoader.get_skill(sid)
	return sd.display_name if sd != null else sid


func _icon_key(sid: String) -> String:
	var key := str(GameConstants.SKILL_ICON.get(sid, ""))
	if key.is_empty() or UISkin.texture(key) == null:
		return "skill_slot"
	return key


func _card_box(hover: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1A1E24") if hover else Color("14171C")
	box.border_color = Color("D9A441") if hover else Color("3A424F")
	box.set_border_width_all(1)
	return box
