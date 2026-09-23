## 工具：capture_settings.gd（步骤 7 · 设置面板真渲染；**非玩法**）
##
## 用法（**必须去掉 --headless**；小窗 640×360 demo）：
##   godot --path "D:/七傳說/game" res://tools/capture_settings.tscn
## 产出：主菜单 → 点开「设置」浮层 → 截图（含画质/音量/按键全区域）。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables"
var _fail: int = 0


func _ready() -> void:
	print("===== 步骤 7 设置面板抓图（小窗 640×360）=====")
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless", DisplayServer.get_name() != "headless")
	# 清场：避免存档影响主菜单状态
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	SceneManager.fade_duration = 0.0

	var menu: Node = (load("res://scenes/main/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(0.8).timeout
	# 直接调主菜单的 _on_settings 打开设置浮层（等价于点「设置」按钮）
	if menu.has_method("_on_settings"):
		menu.call("_on_settings")
	await get_tree().create_timer(0.6).timeout

	# 找浮层上的设置面板，确认在视口内完整可见
	var sp: Control = null
	for child in menu.find_children("*", "SettingsPanel", true, false):
		sp = child
		break
	if sp == null:
		_ok("设置浮层已打开", false)
		get_tree().quit(1)
		return
	_ok("设置浮层已打开", true)
	var panel: PanelContainer = null
	for child in sp.find_children("*", "PanelContainer", true, false):
		panel = child
		break
	if panel != null:
		print("      sp.size=%s panel.pos=%s panel.size=%s panel.min=%s"
			% [str(sp.size), str(panel.position), str(panel.size),
				str(panel.get_combined_minimum_size())])
	_ok("面板内容高度适配视口", panel != null and panel.get_combined_minimum_size().y <= 358.0)

	await _capture(OUT_DIR + "/设置面板_统一视觉_2026-09-23.png")

	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _capture(out: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	_ok("截圖 %s（err=%d）" % [out, err], err == OK)
	if err != OK:
		_fail += 1


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
