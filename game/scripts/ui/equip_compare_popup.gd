## 装备对比浮窗（步骤 4 · 2026-09-22）
##
## 点击背包物品弹出：与当前穿戴「同槽位」横向对比数值（复用 ComparePanel 行渲染），
## 底部 [装备此件] / [关闭]。槽位为空时展示「可直接装备」提示。
##
## 由 hub 持有（懒建，浮层置顶）；数据注入 + 回调转发，不直接改装备状态。
class_name EquipComparePopup
extends PanelContainer

var _compare: ComparePanel = null
var _sub: RichTextLabel = null
var _on_equip: Callable = Callable()
## 关闭回调（hub 用来隐藏整个浮层 holder）
var on_close: Callable = Callable()


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(420, 268)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	# 主体：对比行（可滚动，词缀键多时不溢出）
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 168)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_compare = ComparePanel.new()
	scroll.add_child(_compare)

	_sub = RichTextLabel.new()
	_sub.bbcode_enabled = true
	_sub.fit_content = true
	_sub.scroll_active = false
	_sub.add_theme_font_size_override("normal_font_size", 11)
	vb.add_child(_sub)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(bottom)
	var equip_btn := _make_btn("装备此件", "gold")
	equip_btn.pressed.connect(_on_equip_pressed)
	bottom.add_child(equip_btn)
	var close_btn := _make_btn("关闭", "dark")
	close_btn.pressed.connect(close)
	bottom.add_child(close_btn)


func _make_btn(text: String, kind: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(108, 34)
	btn.add_theme_font_size_override("font_size", 13)
	var boxes := UISkin.btn_styleboxes(kind)
	for state in ["normal", "hover", "pressed"]:
		if boxes.has(state):
			btn.add_theme_stylebox_override(state, boxes[state])
	return btn


## 显示对比：new_item（背包）vs old_item（同槽位已穿戴）；context = 槽位名
func show_compare(new_item: EquipmentInstance, old_item: EquipmentInstance,
		context: String, p_on_equip: Callable) -> void:
	if _compare == null:
		_build_ui()
	_on_equip = p_on_equip
	_compare.show_compare(new_item, old_item, context)

	var lines: Array[String] = []
	if new_item != null:
		lines.append("[color=#%s]背包：%s（%s）[/color]" % [
			new_item.get_rarity_color().to_html(false),
			new_item.get_display_name(),
			GameConstants.RARITY_NAMES[clampi(new_item.rarity, 0, GameConstants.RARITY_COUNT - 1)]])
	else:
		lines.append("[color=#5A6270]背包：—[/color]")
	if old_item != null:
		lines.append("[color=#%s]已穿戴：%s（%s）[/color]" % [
			old_item.get_rarity_color().to_html(false),
			old_item.get_display_name(),
			GameConstants.RARITY_NAMES[clampi(old_item.rarity, 0, GameConstants.RARITY_COUNT - 1)]])
	else:
		lines.append("[color=#5A6270]已穿戴：空槽位（可直接装备）[/color]")
	_sub.text = "\n".join(lines)
	visible = true


func _on_equip_pressed() -> void:
	if _on_equip.is_valid():
		_on_equip.call()
	close()


func close() -> void:
	visible = false
	if on_close.is_valid():
		on_close.call()
