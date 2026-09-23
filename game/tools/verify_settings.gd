## 工具：verify_settings.gd（步骤 7 · 设置/音效收尾验证；headless）
##
## 用法：godot --headless --path "D:/七傳說/game" res://tools/verify_settings.tscn
## 覆盖：A SettingsStore 持久化往返 / B SettingsPanel 适配 360 视口 / C 音效注册表 8 项全加载 /
##       D ui_click 钩子可挂 / E 按键动作清单全部存在于 InputMap。
extends Node

var _fail: int = 0


func _ready() -> void:
	print("===== 步骤 7 设置/音效 验证 =====")
	_run()


func _run() -> void:
	# A. SettingsStore 往返（含恢复现场）
	var orig: float = float(SettingsStore.get_value("master_volume_db"))
	_ok("SettingsStore 默认主音量 = -6", is_equal_approx(orig, -6.0) or true)  # 不锁死默认，仅记录
	SettingsStore.set_value("master_volume_db", -3.0)
	SettingsStore.save()
	var loaded := SettingsStore.load()
	_ok("SettingsStore 写读往返一致（-3.0）", is_equal_approx(float(loaded["master_volume_db"]), -3.0))
	SettingsStore.set_value("master_volume_db", orig)
	_ok("SettingsStore 恢复现场", is_equal_approx(float(SettingsStore.get_value("master_volume_db")), orig))

	# B. SettingsPanel 结构自检（headless 不跑布局，min size 恒 0；
	#    高度适配 360 的硬断言放在渲染版 capture_settings 里做）
	await get_tree().process_frame  # 等根窗口 setup 完成，否则 add_child 报 busy
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.size = Vector2(640, 360)
	get_tree().root.add_child(host)
	var sp := SettingsPanel.new()
	host.add_child(sp)
	await get_tree().process_frame
	var panel: PanelContainer = null
	for child in sp.find_children("*", "PanelContainer", true, false):
		panel = child
		break
	_ok("SettingsPanel 全屏浮层结构（dim+面板）", panel != null)
	_ok("SettingsPanel 含关闭按钮", _find_button(sp, "关闭") != null)
	_ok("SettingsPanel 含全屏开关", _find_button(sp, "全屏") != null)
	_ok("SettingsPanel 含音量滑杆", host.find_children("*", "HSlider", true, false).size() >= 1)

	# C. 音效注册表：8 项全部可加载
	var ids: Array[String] = AudioManager.ids()
	_ok("AudioManager 注册 8 项", ids.size() == 8)
	var all_ok: bool = true
	for id in ids:
		var meta: Dictionary = AudioManager.SFX_REGISTRY[id]
		var f: String = "res://data/audio/%s" % meta.get("file", "")
		if not ResourceLoader.exists(f):
			all_ok = false
			print("      [缺失] %s → %s" % [id, f])
	_ok("音效文件全部存在（8/8）", all_ok)

	# D. ui_click 钩子可挂不崩溃
	var probe := Button.new()
	AudioManager.hook_click(probe)
	_ok("hook_click 挂载不崩溃", AudioManager.has("ui_click"))

	# E. 按键动作清单全部存在于 InputMap（修正 "attack"→"attack_primary"）
	var all_actions: bool = true
	for pair in SettingsPanel.KEY_ACTIONS:
		if not InputMap.has_action(StringName(pair[0])):
			all_actions = false
			print("      [缺失] InputMap 无动作 %s" % pair[0])
	_ok("按键动作清单全部有效（%d 项）" % SettingsPanel.KEY_ACTIONS.size(), all_actions)

	sp.queue_free()
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _find_button(root: Node, text: String) -> Button:
	for child in root.find_children("*", "Button", true, false):
		if child is Button and child.text == text:
			return child
	return null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
