## 设置界面（任务 7.7 · class_name）
##
## 画质（垂直同步 / 全屏）/ 音量（主音量 -30..0 dB → AudioServer）/
## 按键（InputRemapper 动作列表 + 重置）。设置持久化属任务 8.2，本节只做界面 + 即时生效。
class_name SettingsPanel
extends Control

const AUDIO_ACTIONS := [
	["move_up", "上移"], ["move_down", "下移"], ["move_left", "左移"], ["move_right", "右移"],
	["attack", "普攻"], ["dodge", "闪避"], ["skill_1", "技能 1"], ["skill_2", "技能 2"],
	["skill_3", "技能 3"], ["interact", "交互"],
]

var _keys_list: VBoxContainer = null


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(520, 460)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	root.add_child(title)

	# —— 画质 ——
	root.add_child(_section_label("画质"))
	var vbox_gfx := VBoxContainer.new()
	root.add_child(vbox_gfx)
	var vsync := CheckButton.new()
	vsync.text = "垂直同步"
	vsync.button_pressed = bool(SettingsStore.get_value("vsync"))
	vsync.toggled.connect(func(on: bool) -> void:
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
		SettingsStore.set_value("vsync", on))
	vbox_gfx.add_child(vsync)
	var full := CheckButton.new()
	full.text = "全屏"
	full.button_pressed = bool(SettingsStore.get_value("fullscreen"))
	full.toggled.connect(func(on: bool) -> void:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
		SettingsStore.set_value("fullscreen", on))
	vbox_gfx.add_child(full)

	# —— 音量 ——
	root.add_child(_section_label("音量"))
	var vol := HBoxContainer.new()
	vol.add_theme_constant_override("separation", 8)
	root.add_child(vol)
	var vol_l := Label.new()
	vol_l.text = "主音量"
	vol_l.add_theme_font_size_override("font_size", 12)
	vol.add_child(vol_l)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(260, 20)
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
	vol.add_child(vol_val)
	slider.value_changed.connect(func(v: float) -> void: vol_val.text = "%d dB" % int(v))
	vol_val.text = "%d dB" % int(slider.value)

	# —— 按键 ——
	root.add_child(_section_label("按键（点击动作名可重绑定 / 右键重置）"))
	_keys_list = VBoxContainer.new()
	_keys_list.add_theme_constant_override("separation", 4)
	root.add_child(_keys_list)
	_refresh_keys()

	var reset_all := Button.new()
	reset_all.text = "重置全部按键"
	reset_all.add_theme_font_size_override("font_size", 12)
	reset_all.pressed.connect(func() -> void:
		InputRemapper.reset_all_to_default()
		_refresh_keys())
	root.add_child(reset_all)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[4])
	return l


func _refresh_keys() -> void:
	for child in _keys_list.get_children():
		child.queue_free()
	for a in AUDIO_ACTIONS:
		var action: StringName = StringName(a[0])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_keys_list.add_child(row)
		var name_l := Label.new()
		name_l.text = a[1]
		name_l.add_theme_font_size_override("font_size", 11)
		name_l.custom_minimum_size = Vector2(90, 0)
		row.add_child(name_l)
		var ev_l := Label.new()
		ev_l.text = _event_text(action)
		ev_l.add_theme_font_size_override("font_size", 11)
		ev_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
		ev_l.custom_minimum_size = Vector2(220, 0)
		row.add_child(ev_l)
		var reset_btn := Button.new()
		reset_btn.text = "重置"
		reset_btn.add_theme_font_size_override("font_size", 10)
		reset_btn.pressed.connect(func() -> void:
			InputRemapper.reset_to_default(action)
			_refresh_keys())
		row.add_child(reset_btn)


func _event_text(action: StringName) -> String:
	var evs := InputRemapper.get_action_events(action)
	if evs.is_empty():
		return "未绑定"
	var parts: Array[String] = []
	for e in evs:
		parts.append(e.as_text())
	return " / ".join(parts)
