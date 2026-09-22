## 背包 / 仓库面板（步骤 4 · 2026-09-22 · 重做视觉）
##
## 背包格子浏览（8 列 × 5 行，稀有度边框色）+ 稀有度排序 + 丢弃 + 快捷装备条。
## 交互：
##   · 点击格子 → 选中（信息行显示详情）+ 弹出「装备对比」浮窗（同槽位对比）
##   · [按稀有度] 排序 · [丢弃] 删除选中物品 · [仓库] 切换背包 / 仓库
##   · 拖拽背包物品 → 快捷装备条对应槽位（武器拖武器）完成装备
##   · 点击快捷装备条已装备槽 → 卸下回背包
##
## 职责边界：只读展示 + 回调转发（装备 / 卸下 / 丢弃 / 对比 均由业务层注入）。
class_name InventoryPanel
extends PanelContainer

## 快捷装备条槽位（与装备栏六格一致：头 / 衣 / 手 / 腿 / 鞋 / 武器）
const EQUIP_STRIP: Array[int] = [
	GameConstants.EquipSlot.HELM, GameConstants.EquipSlot.CHEST,
	GameConstants.EquipSlot.GLOVES, GameConstants.EquipSlot.LEGS,
	GameConstants.EquipSlot.BOOTS, GameConstants.EquipSlot.MAIN_HAND,
]
const STRIP_SHORT := {
	GameConstants.EquipSlot.HELM: "头", GameConstants.EquipSlot.CHEST: "衣",
	GameConstants.EquipSlot.GLOVES: "手", GameConstants.EquipSlot.LEGS: "腿",
	GameConstants.EquipSlot.BOOTS: "鞋", GameConstants.EquipSlot.MAIN_HAND: "武器",
}

## 拖拽数据类型标签（跨面板统一口径）
const DRAG_TYPE := "bag_item"

## 绑定的背包 / 仓库数据（由场景或代码注入）
var inventory: Inventory = null
var stash: Inventory = null
## 当前装备（按槽位下标对齐；供快捷装备条展示）
var equipped: Array = []
## 回调（可选）：装备（instance_id）/ 卸下（slot）/ 丢弃（instance_id）/ 对比（item）
var on_equip_instance: Callable = Callable()
var on_unequip: Callable = Callable()
var on_drop: Callable = Callable()
var on_compare: Callable = Callable()

var _title: Label = null
var _grid: GridContainer = null
var _info: Label = null
var _strip_row: HBoxContainer = null
var _strip_buttons: Array[Button] = []
var _cell_buttons: Array[Button] = []
var _drop_btn: Button = null
var _current := true ## true = 背包，false = 仓库
var _selected_id: String = ""


func _ready() -> void:
	_build_ui()


func bind(p_inventory: Inventory, p_stash: Inventory, p_equipped: Array = [],
		p_on_equip_instance: Callable = Callable(), p_on_unequip: Callable = Callable(),
		p_on_drop: Callable = Callable(), p_on_compare: Callable = Callable()) -> void:
	inventory = p_inventory
	stash = p_stash
	equipped = p_equipped
	on_equip_instance = p_on_equip_instance
	on_unequip = p_on_unequip
	on_drop = p_on_drop
	on_compare = p_on_compare
	_refresh()


func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 315)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	margin.add_child(vb)

	# 标题行 + 工具栏
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", Color("F5D77A"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(_make_tool_btn("按稀有度", _on_sort_rarity))
	_drop_btn = _make_tool_btn("丢弃", _on_drop_pressed)
	_drop_btn.disabled = true
	top.add_child(_drop_btn)
	top.add_child(_make_tool_btn("仓库", _on_toggle_stash))

	# 快捷装备条
	var strip_l := Label.new()
	strip_l.text = "快捷装备 · 拖拽背包物品到对应槽位"
	strip_l.add_theme_font_size_override("font_size", 12)
	strip_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(strip_l)

	_strip_row = HBoxContainer.new()
	_strip_row.add_theme_constant_override("separation", 8)
	vb.add_child(_strip_row)

	# 背包网格（8 列 × 5 行，可见 3 行，滚动查看）
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 152)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 11)
	_info.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(_info)


func _make_tool_btn(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(66, 28)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(cb)
	return btn


func _refresh() -> void:
	var src := stash if not _current else inventory
	if src == null:
		return
	_title.text = ("背包（%d/%d）" if _current else "仓库（%d/%d）") % [
		src.count(), src.capacity()]
	_render_strip()
	_render_grid()
	_update_drop_btn()


## 快捷装备条：已装备槽位显示图标（稀有度边框）；空槽显示占位图标
func _render_strip() -> void:
	for b in _strip_buttons:
		b.queue_free()
	_strip_buttons.clear()
	for slot in EQUIP_STRIP:
		var item: EquipmentInstance = equipped[slot] if slot < equipped.size() else null
		var btn := Button.new()
		btn.name = "StripBtn_%d" % slot
		btn.custom_minimum_size = Vector2(48, 48)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = String(GameConstants.EQUIP_SLOT_NAMES[slot])
		btn.add_theme_stylebox_override("normal", _strip_box(item))
		btn.add_theme_stylebox_override("hover", _strip_box(item))
		btn.add_theme_stylebox_override("pressed", _strip_box(item))
		if item != null and item.template != null:
			var tex := ContentLoader.load_icon(item.template.icon_path)
			if tex != null:
				btn.icon = tex
				btn.expand_icon = true
		# 点击已装备 → 卸下回背包
		btn.pressed.connect(func() -> void:
			if item != null and on_unequip.is_valid():
				on_unequip.call(slot))
		# 拖放目标：背包物品 → 对应槽位
		btn.set_drag_forwarding(Callable(),
			_strip_can_drop.bind(slot), _strip_drop.bind(slot))
		_strip_row.add_child(btn)
		_strip_buttons.append(btn)


func _strip_box(item) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("14171C")
	sb.set_corner_radius_all(0)
	if item == null:
		sb.border_color = Color("3A424F")
		sb.set_border_width_all(1)
		return sb
	sb.border_color = GameConstants.RARITY_FRAME_COLORS[clampi(item.rarity, 0, GameConstants.RARITY_COUNT - 1)]
	sb.set_border_width_all(2)
	return sb


## 背包格：48×48，稀有度边框，图标优先
func _render_grid() -> void:
	var src := stash if not _current else inventory
	for b in _cell_buttons:
		b.queue_free()
	_cell_buttons.clear()
	for i in src.capacity():
		var cell := Button.new()
		cell.name = "Cell_%d" % i
		cell.custom_minimum_size = Vector2(48, 48)
		cell.focus_mode = Control.FOCUS_NONE
		cell.pressed.connect(_on_cell_pressed.bind(i))
		var item := src.get_at(i)
		if item != null:
			var icon := _item_icon(item)
			if icon != null:
				cell.icon = icon
				cell.expand_icon = true
			cell.add_theme_stylebox_override("normal", _cell_box(item, item.instance_id == _selected_id))
			cell.add_theme_stylebox_override("hover", _cell_box(item, true))
			cell.add_theme_stylebox_override("pressed", _cell_box(item, true))
			cell.tooltip_text = "%s · %s · iLvl %d · +%d" % [
				item.get_display_name(), GameConstants.RARITY_NAMES[clampi(item.rarity, 0, GameConstants.RARITY_COUNT - 1)],
				item.item_level, item.forge_level]
			# 拖拽源：背包物品 → 快捷装备条
			cell.set_drag_forwarding(_cell_drag_data.bind(i), Callable(), Callable())
		else:
			cell.add_theme_stylebox_override("normal", _cell_box(null, false))
		_grid.add_child(cell)
		_cell_buttons.append(cell)


func _cell_box(item, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1A1E24") if selected else Color("0F1114")
	sb.set_corner_radius_all(0)
	if item == null:
		sb.border_color = Color("2A2F38")
		sb.set_border_width_all(1)
		return sb
	var frame: Color = GameConstants.RARITY_FRAME_COLORS[clampi(item.rarity, 0, GameConstants.RARITY_COUNT - 1)]
	if selected:
		frame = frame.lightened(0.3)
	sb.border_color = frame
	sb.set_border_width_all(clampi(GameConstants.RARITY_FRAME_WIDTHS[clampi(item.rarity, 0, GameConstants.RARITY_COUNT - 1)] + 1, 1, 3))
	return sb


func _item_icon(item) -> Texture2D:
	if item == null or item.template == null:
		return null
	return ContentLoader.load_icon(item.template.icon_path)


## 拖拽数据（验证 / 测试可直接调用）
func _cell_drag_data(at_position: Vector2, cell_index: int) -> Variant:
	var src := stash if not _current else inventory
	var item := src.get_at(cell_index)
	if item == null:
		return null
	var preview := Button.new()
	preview.custom_minimum_size = Vector2(48, 48)
	var icon := _item_icon(item)
	if icon != null:
		preview.icon = icon
		preview.expand_icon = true
	preview.add_theme_stylebox_override("normal", _cell_box(item, false))
	_cell_buttons[cell_index].set_drag_preview(preview)
	return {"type": DRAG_TYPE, "instance_id": item.instance_id, "slot": int(item.slot)}


func _strip_can_drop(at_position: Vector2, data: Variant, slot_id: int) -> bool:
	return data is Dictionary \
		and String(data.get("type", "")) == DRAG_TYPE \
		and int(data.get("slot", -1)) == slot_id


## 拖放落点（验证 / 测试可直接调用）
func _strip_drop(at_position: Vector2, data: Variant, slot_id: int) -> void:
	if not _strip_can_drop(at_position, data, slot_id):
		return
	if on_equip_instance.is_valid():
		on_equip_instance.call(String(data.get("instance_id", "")))


func _on_cell_pressed(index: int) -> void:
	var src := stash if not _current else inventory
	var item := src.get_at(index)
	if item == null:
		_selected_id = ""
		_update_drop_btn()
		_render_grid()
		_info.text = "空位"
		return
	_selected_id = item.instance_id
	_update_drop_btn()
	_render_grid()
	var fx_text := ""
	if not item.legendary_effect_id.is_empty():
		var fx: Dictionary = ConfigLoader.legendary_effects.get(item.legendary_effect_id, {})
		fx_text = " · %s" % fx.get("name", "")
	_info.text = "%s · %s · iLvl %d · +%d · %d 词缀%s" % [
		item.get_display_name(), GameConstants.RARITY_NAMES[clampi(item.rarity, 0, GameConstants.RARITY_COUNT - 1)],
		item.item_level, item.forge_level, item.affixes.size(), fx_text]
	if on_compare.is_valid():
		on_compare.call(item)


func _update_drop_btn() -> void:
	var src := stash if not _current else inventory
	var sel: EquipmentInstance = null
	if src != null and not _selected_id.is_empty():
		sel = src.get_at(src.index_of(_selected_id)) if src.index_of(_selected_id) >= 0 else null
	_drop_btn.disabled = sel == null


func _on_sort_rarity() -> void:
	var src := stash if not _current else inventory
	src.sort_by(Inventory.SORT_RARITY, true)
	_refresh()


func _on_drop_pressed() -> void:
	if _selected_id.is_empty() or not on_drop.is_valid():
		return
	on_drop.call(_selected_id)


func _on_toggle_stash() -> void:
	_current = not _current
	_selected_id = ""
	_refresh()
