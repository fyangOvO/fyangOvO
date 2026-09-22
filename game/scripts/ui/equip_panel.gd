## 装备栏（步骤 4 · 2026-09-22 · 重做视觉）
##
## 六格装备位（头 / 衣 / 手 / 腿 / 鞋 / 武器）+ 已装备清单 + 词缀展示。
## 与技能面板同一套视觉规范（深底 PanelContainer + 12/16px 像素字号 + 金/暗按钮）。
## 等级颜色：装备名与槽位边框按稀有度 8 档着色（特效渲染后续再做，本页先简单版）。
##
## 职责边界（与旧版一致）：只读展示 + 回调转发，不直接改装备状态。
##   · 点击槽位 → 右侧「词缀展示」显示该件详情（基础属性 + 词缀列表）
##   · [卸下] → on_unequip(slot)（由业务层注入）
##   · 装备动作由「背包」面板完成（拖拽 / 对比浮窗）
##
## ⚠️ 副手 / 项链 / 戒A / 戒B 暂不在本面板展示（用户定稿六格），数据与结算保留。
class_name EquipPanel
extends PanelContainer

## 六格（头 / 衣 / 手 / 腿 / 鞋 / 武器）
const SLOTS: Array[int] = [
	GameConstants.EquipSlot.HELM, GameConstants.EquipSlot.CHEST,
	GameConstants.EquipSlot.GLOVES, GameConstants.EquipSlot.LEGS,
	GameConstants.EquipSlot.BOOTS, GameConstants.EquipSlot.MAIN_HAND,
]
## 槽位短名（格下标签）
const SLOT_SHORT := {
	GameConstants.EquipSlot.HELM: "头部", GameConstants.EquipSlot.CHEST: "胸甲",
	GameConstants.EquipSlot.GLOVES: "手套", GameConstants.EquipSlot.LEGS: "腿部",
	GameConstants.EquipSlot.BOOTS: "鞋子", GameConstants.EquipSlot.MAIN_HAND: "武器",
}

## 当前装备（按槽位下标对齐；null = 空槽）
var equipped: Array = []
## 回调（可选）：穿（保留契约，新 UI 不走此路径）/ 脱（槽位）
var on_equip: Callable = Callable()
var on_unequip: Callable = Callable()

var _class_id: String = GameConstants.CLASS_DEFAULT
var _title: Label = null
var _grid: GridContainer = null
var _slot_buttons: Array[Button] = []
var _list: RichTextLabel = null
var _detail: RichTextLabel = null
var _un_btn: Button = null
var _selected_slot: int = -1


func _ready() -> void:
	_build_ui()


## hub 注入数据；每次打开（refresh）都会重新调用
func bind(p_equipped: Array, p_class_id = GameConstants.CLASS_DEFAULT,
		p_on_unequip: Callable = Callable()) -> void:
	equipped = p_equipped
	if p_class_id is String:
		_class_id = p_class_id
	on_unequip = p_on_unequip
	refresh()


func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 300)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	vb.add_child(_title)

	var hint := Label.new()
	hint.text = "点击槽位查看词缀 · 装备请在背包拖拽 / 对比浮窗完成"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(hint)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	vb.add_child(body)

	# —— 左：六格装备位 ——
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	var slot_l := Label.new()
	slot_l.text = "六格装备位"
	slot_l.add_theme_font_size_override("font_size", 12)
	slot_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	left.add_child(slot_l)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(_grid)

	# —— 右：已装备清单 + 词缀展示 ——
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.custom_minimum_size = Vector2(176, 0)
	body.add_child(right)

	var list_l := Label.new()
	list_l.text = "已装备清单"
	list_l.add_theme_font_size_override("font_size", 12)
	list_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	right.add_child(list_l)

	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.fit_content = true
	_list.scroll_active = false
	_list.add_theme_font_size_override("normal_font_size", 11)
	right.add_child(_list)

	var detail_l := Label.new()
	detail_l.text = "词缀展示（点选槽位）"
	detail_l.add_theme_font_size_override("font_size", 12)
	detail_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	right.add_child(detail_l)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.add_theme_font_size_override("normal_font_size", 11)
	right.add_child(_detail)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	vb.add_child(bottom)
	_un_btn = _make_btn("卸下", "dark")
	_un_btn.disabled = true
	_un_btn.pressed.connect(_on_unequip_pressed)
	bottom.add_child(_un_btn)


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


func refresh() -> void:
	var cls: Dictionary = ConfigLoader.classes.get(_class_id, {})
	_title.text = "装备 · %s" % ConfigLoader.class_display_name(_class_id)
	_title.add_theme_color_override("font_color",
		Color(String(cls.get("color", "F5D77A"))))
	_render_slots()
	_render_list()
	_render_detail()


## 六格槽位：图标（有）或空位，边框按稀有度着色；选中槽位底色提亮
func _render_slots() -> void:
	for b in _slot_buttons:
		b.queue_free()
	_slot_buttons.clear()
	for slot in SLOTS:
		var item: EquipmentInstance = equipped[slot] if slot < equipped.size() else null
		var btn := Button.new()
		btn.name = "SlotBtn_%d" % slot
		btn.custom_minimum_size = Vector2(88, 54)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = String(GameConstants.EQUIP_SLOT_NAMES[slot])
		btn.pressed.connect(_on_slot_pressed.bind(slot))
		btn.add_theme_stylebox_override("normal", _slot_box(item, slot == _selected_slot))
		btn.add_theme_stylebox_override("hover", _slot_box(item, true))
		btn.add_theme_stylebox_override("pressed", _slot_box(item, true))
		if item != null and item.template != null:
			var tex := ContentLoader.load_icon(item.template.icon_path)
			if tex != null:
				btn.icon = tex
				btn.expand_icon = true
		_grid.add_child(btn)
		_slot_buttons.append(btn)


func _slot_box(item, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1A1E24") if selected else Color("14171C")
	sb.set_corner_radius_all(0)
	if item == null:
		sb.border_color = Color("3A424F")
		sb.set_border_width_all(1)
		return sb
	var frame: Color = GameConstants.RARITY_FRAME_COLORS[clampi(item.rarity, 0, GameConstants.RARITY_COUNT - 1)]
	if selected:
		frame = frame.lightened(0.25)
	sb.border_color = frame
	sb.set_border_width_all(clampi(GameConstants.RARITY_FRAME_WIDTHS[clampi(item.rarity, 0, GameConstants.RARITY_COUNT - 1)] + 1, 1, 3))
	return sb


## 已装备清单：每槽一行「部位　装备名」（名按稀有度着色）
func _render_list() -> void:
	var lines: Array[String] = []
	for slot in SLOTS:
		var item: EquipmentInstance = equipped[slot] if slot < equipped.size() else null
		var name_text: String = String(SLOT_SHORT.get(slot, "?"))
		if item == null:
			lines.append("[color=#5A6270]%s　—[/color]" % name_text)
		else:
			lines.append("[color=#5A6270]%s　[/color][color=#%s]%s[/color]" % [
				name_text, item.get_rarity_color().to_html(false), item.get_display_name()])
	_list.text = "\n".join(lines)


## 词缀展示：选中槽位的装备详情（基础属性 + 词缀列表）
func _render_detail() -> void:
	var item: EquipmentInstance = null
	if _selected_slot >= 0 and _selected_slot < equipped.size():
		item = equipped[_selected_slot]
	if _un_btn != null:
		_un_btn.disabled = item == null
	if item == null:
		_detail.text = "[color=#5A6270]空槽位 —— 从背包拖拽装备到此[/color]"
		return
	var lines: Array[String] = []
	lines.append("[color=#%s]%s[/color]　iLvl %d　+%d" % [
		item.get_rarity_color().to_html(false), item.get_display_name(),
		item.item_level, item.forge_level])
	var base := item.get_base_stats()
	if not base.is_empty():
		var parts: Array[String] = []
		for key in base:
			parts.append("%s %s" % [EquipmentCompare._label_for(key), _fmt(float(base[key]))])
		lines.append("[color=#B3BCC9]基础：%s[/color]" % " · ".join(parts))
	if item.affixes.size() > 0:
		lines.append("[color=#B3BCC9]词缀：[/color]")
		for roll in item.affixes:
			lines.append("· [color=#%s]%s[/color]" % [
				(roll as AffixRoll).quality_color().to_html(false), (roll as AffixRoll).to_text()])
	else:
		lines.append("[color=#5A6270]无词缀[/color]")
	_detail.text = "\n".join(lines)


func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(int(roundf(v)))
	return "%.1f" % v


func _on_slot_pressed(slot: int) -> void:
	_selected_slot = slot
	# 刷新选中态（槽位边框提亮）
	_render_slots()
	_render_detail()


func _on_unequip_pressed() -> void:
	if _selected_slot >= 0 and on_unequip.is_valid():
		on_unequip.call(_selected_slot)
