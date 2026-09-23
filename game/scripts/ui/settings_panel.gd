## 设置界面（步骤 7 定稿 · class_name）
##
## 画质（垂直同步 / 全屏）/ 音量（主音量 -30..0 dB → AudioServer）/
## 按键（InputRemapper 动作列表 + 重置）。持久化由 `SettingsStore`（user://settings.json）
## 承担：改动即存，`main.gd` 启动时 `SettingsStore.load()` 应用。
##
## 步骤 7 修复清单：
## ① 原面板 520×460 套在 `_make_overlay` 里（外再加一层标题 + 40px 边距），
##    总高 >560px 被 640×360 视口裁掉大半 → 改为**全屏浮层自管理**（dim + 居中面板），
##    面板自身含标题与关闭按钮，总高 ≈344px 完整可见；
## ② 统一视觉（margin 14 / 标题 16px / 内容 12px / UISkin 按钮，步骤 5 规范）；
## ③ 修正按键动作清单（原 "attack" 不存在于 InputMap → 恒显示未绑定，改 "attack_primary"）；
## ④ 全屏/垂直同步/音量改动即写 `SettingsStore`，启动由 main 应用。
class_name SettingsPanel
extends Control

## 可重绑动作清单（必须与 project.godot 的 InputMap 动作名一致）
const KEY_ACTIONS := [
	["move_up", "上移"], ["move_down", "下移"], ["move_left", "左移"], ["move_right", "右移"],
	["attack_primary", "普攻"], ["dodge", "闪避"], ["skill_1", "技能 1"], ["skill_2", "技能 2"],
	["skill_3", "技能 3"], ["consume_1", "生命药水"], ["consume_2", "法力药水"], ["interact", "交互"],
]

## 面板关闭回调（由主菜单注入 `_clear_overlay`）
var on_close: Callable = Callable()

var _keys_scroll: ScrollContainer = null
var _keys_list: VBoxContainer = null


func _ready() -> void:
	_build_ui()


## UISkin 按钮（gold / dark 三态 + 点击音）
func _ui_btn(text: String, kind: String, min_h: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", 11)
	var boxes := UISkin.btn_styleboxes(kind)
	for state in ["normal", "hover", "pressed"]:
		if boxes.has(state):
			b.add_theme_stylebox_override(state, boxes[state])
	if boxes.has("normal"):
		b.add_theme_stylebox_override("focus", boxes["normal"])
	b.pressed.connect(cb)
	AudioManager.hook_click(b)
	return b


func _build_ui() -> void:
	# 全屏浮层：压暗 + 居中面板（自管理，不依赖主菜单 overlay 的额外标题/边距）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := UISkin.panel_stylebox()
	if sb != null:
		panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(372, 0)
	root.add_theme_constant_override("separation", 5)
	margin.add_child(root)

	# 标题（16px 统一规范）
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	root.add_child(title)

	# —— 画质 ——
	root.add_child(_section_label("画质"))
	root.add_child(_check_row("垂直同步", "vsync", func(on: bool) -> void:
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)))
	root.add_child(_check_row("全屏", "fullscreen", func(on: bool) -> void:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)))

	# —— 音量 ——
	root.add_child(_section_label("音量"))
	var vol := HBoxContainer.new()
	vol.add_theme_constant_override("separation", 8)
	root.add_child(vol)
	var vol_l := Label.new()
	vol_l.text = "主音量"
	vol_l.add_theme_font_size_override("font_size", 12)
	vol_l.custom_minimum_size = Vector2(72, 0)
	vol.add_child(vol_l)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(180, 18)
	var master := AudioServer.get_bus_index("Master")
	slider.min_value = -30.0
	slider.max_value = 0.0
	slider.step = 1.0
	slider.value = float(SettingsStore.get_value("master_volume_db"))
	slider.value_changed.connect(func(v: float) -> void:
		AudioServer.set_bus_volume_db(master, v)
		SettingsStore.set_value("master_volume_db", v))
	vol.add_child(slider)
	var vol_val := Label.new()
	vol_val.add_theme_font_size_override("font_size", 11)
	vol_val.custom_minimum_size = Vector2(64, 0)
	vol.add_child(vol_val)
	slider.value_changed.connect(func(v: float) -> void: vol_val.text = "%d dB" % int(v))
	vol_val.text = "%d dB" % int(slider.value)

	# —— 按键（滚动区，视口内约 4.4 行可见） ——
	root.add_child(_section_label("按键（行内重置 / 底部全部重置）"))
	_keys_scroll = ScrollContainer.new()
	_keys_scroll.custom_minimum_size = Vector2(0, 84)
	_keys_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_keys_list = VBoxContainer.new()
	_keys_list.add_theme_constant_override("separation", 2)
	_keys_scroll.add_child(_keys_list)
	root.add_child(_keys_scroll)
	_refresh_keys()

	var reset_all := _ui_btn("重置全部按键", "gold", 24, func() -> void:
		InputRemapper.reset_all_to_default()
		_refresh_keys())
	root.add_child(reset_all)

	var close := _ui_btn("关闭", "dark", 26, func() -> void:
		if on_close.is_valid():
			on_close.call())
	root.add_child(close)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[4])
	return l


func _check_row(text: String, key: String, apply: Callable) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = text
	cb.add_theme_font_size_override("font_size", 12)
	cb.button_pressed = bool(SettingsStore.get_value(key))
	cb.toggled.connect(func(on: bool) -> void:
		SettingsStore.set_value(key, on)
		apply.call(on))
	return cb


func _refresh_keys() -> void:
	for child in _keys_list.get_children():
		child.queue_free()
	for a in KEY_ACTIONS:
		var action: StringName = StringName(a[0])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_keys_list.add_child(row)
		var name_l := Label.new()
		name_l.text = a[1]
		name_l.add_theme_font_size_override("font_size", 10)
		name_l.custom_minimum_size = Vector2(64, 0)
		row.add_child(name_l)
		var ev_l := Label.new()
		ev_l.text = _event_text(action)
		ev_l.add_theme_font_size_override("font_size", 10)
		ev_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
		ev_l.custom_minimum_size = Vector2(150, 0)
		ev_l.clip_text = true
		ev_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ev_l)
		var reset_btn := _ui_btn("重置", "dark", 18, func() -> void:
			InputRemapper.reset_to_default(action)
			_refresh_keys())
		reset_btn.custom_minimum_size = Vector2(56, 18)
		row.add_child(reset_btn)


func _event_text(action: StringName) -> String:
	var evs := InputRemapper.get_action_events(action)
	if evs.is_empty():
		return "未绑定"
	var parts: Array[String] = []
	for e in evs:
		parts.append(e.as_text())
	return " / ".join(parts)
