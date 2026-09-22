## 锻造 / 合成界面（任务 7.5 · class_name）
##
## 展示锻造费用 + 合成按钮 + 结果反馈。数据驱动 ForgeController（3.5）：
## get_forge_cost / try_forge / get_reroll_cost / try_reroll。
## 面板只读 + 回调转发（on_forge(item_index)/on_reroll(item_index) 由业务层注入）。
class_name ForgePanel
extends PanelContainer

## 背包待锻造物品（EquipmentInstance 数组）
var items: Array = []
var materials: int = 0
## 回调：on_forge(index) / on_reroll(index)
var on_forge: Callable = Callable()
var on_reroll: Callable = Callable()

## 职业 id（标题配色用；默认战士金）
var _class_id: String = GameConstants.CLASS_DEFAULT

var _list: VBoxContainer = null
var _material_label: Label = null
var _result_label: Label = null
var _title: Label = null


func _ready() -> void:
	_build_ui()
	refresh()


func bind(p_items: Array, p_materials: int,
		p_on_forge: Callable = Callable(), p_on_reroll: Callable = Callable(),
		p_class_id: String = GameConstants.CLASS_DEFAULT) -> void:
	items = p_items
	materials = p_materials
	on_forge = p_on_forge
	on_reroll = p_on_reroll
	_class_id = p_class_id
	refresh()


func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "锻造台 · %s" % ConfigLoader.class_display_name(_class_id)
	title.add_theme_font_size_override("font_size", 16)
	head.add_child(title)
	_title = title
	_material_label = Label.new()
	_material_label.add_theme_font_size_override("font_size", 12)
	_material_label.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[4])
	head.add_child(_material_label)

	var hint := Label.new()
	hint.text = "锻造提升锻造等级 · 重铸洗练词缀数值 · 消耗魔石"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(hint)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	vb.add_child(_list)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 11)
	_result_label.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	vb.add_child(_result_label)


func refresh() -> void:
	if _title != null:
		_title.text = "锻造台 · %s" % ConfigLoader.class_display_name(_class_id)
		var cls: Dictionary = ConfigLoader.classes.get(_class_id, {})
		_title.add_theme_color_override("font_color",
			Color(String(cls.get("color", "F5D77A"))))
	if _material_label != null:
		_material_label.text = "魔石 %d" % materials
	for child in _list.get_children():
		child.queue_free()
	for i in items.size():
		var item: EquipmentInstance = items[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var name_l := Label.new()
		name_l.text = "%s · iLvl %d · +%d" % [item.get_display_name(), item.item_level, item.forge_level]
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color", item.get_rarity_color())
		name_l.custom_minimum_size = Vector2(172, 0)
		row.add_child(name_l)
		var cost := ForgeController.get_forge_cost(item)
		var stone := int(cost.get("stone", 0))
		var reroll_dust := int(ForgeController.get_reroll_cost(item.forge_level).get("dust", 0))
		var cost_l := Label.new()
		cost_l.text = "锻造 %d 石" % stone
		cost_l.add_theme_font_size_override("font_size", 10)
		cost_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[8])
		row.add_child(cost_l)
		var f_btn := _make_row_btn("锻造", "gold")
		f_btn.disabled = materials < stone
		f_btn.pressed.connect(func() -> void:
			if on_forge.is_valid():
				on_forge.call(i))
		row.add_child(f_btn)
		var r_btn := _make_row_btn("重铸", "dark")
		r_btn.disabled = materials < reroll_dust
		r_btn.pressed.connect(func() -> void:
			if on_reroll.is_valid():
				on_reroll.call(i))
		row.add_child(r_btn)


## 行内小按钮（与技能/装备面板同套金/暗按钮皮肤，步骤 5 统一视觉）
func _make_row_btn(text: String, kind: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(56, 26)
	btn.add_theme_font_size_override("font_size", 12)
	btn.focus_mode = Control.FOCUS_NONE
	var boxes := UISkin.btn_styleboxes(kind)
	for state in ["normal", "hover", "pressed"]:
		if boxes.has(state):
			btn.add_theme_stylebox_override(state, boxes[state])
	return btn


func show_result(text: String) -> void:
	if _result_label != null:
		_result_label.text = text
