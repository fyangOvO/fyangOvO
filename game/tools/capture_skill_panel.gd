## 工具：capture_skill_panel.gd（步驟 3 技能管理面板真渲染抓圖；**非玩法**）
##
## 用途：建战士档 → 进据点 → 打开技能面板 → 截「默认出战栏」；
##       再卸下裂斩装蓄力斩（重排演示）→ 截「重排后」。
##       落盤供肉眼驗收（技能池 / 出战槽 / 保存按钮）。
##
## 用法（**必須去掉 --headless**，否則沒有渲染；小窗 640×360 demo）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_skill_panel.tscn
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables"

var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== 技能管理面板真渲染抓圖（小窗 640×360）=====")
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless（否則抓不到畫面）", DisplayServer.get_name() != "headless")
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	var data := SaveManager.create_new_slot(0, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = 0
	_ok("战士档已建", data != null)
	if data == null:
		get_tree().quit(1)
		return

	SceneManager.fade_duration = 0.0
	# 手动实例化据点场景（不换 current_scene，避免工具脚本根节点被释放）
	var packed: PackedScene = load("res://scenes/main/hub.tscn")
	var hub: Node = packed.instantiate()
	add_child(hub)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await get_tree().create_timer(0.5).timeout
	_ok("进入据点（手动实例化）", hub != null)
	if hub == null:
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.5).timeout

	var btn := _find_button(hub, "技能")
	_ok("据点按钮条「技能」存在", btn != null)
	if btn == null:
		get_tree().quit(1)
		return
	btn.pressed.emit()
	await get_tree().create_timer(0.6).timeout
	_ok("技能面板已打开", hub.is_panel_visible("skills"))
	await _capture(OUT_DIR + "/技能面板_默认出战栏_2026-09-22.png")

	# 重排演示：卸下裂斩（槽1）→ 装蓄力斩 → 保存
	var sp := hub.get_panel("skills") as SkillPanel
	if sp == null:
		get_tree().quit(1)
		return
	sp.find_child("BarBtn0", true, false).pressed.emit()
	await get_tree().process_frame
	var pool_btn := _find_button_by_name(sp, "PoolBtn_power_strike")
	if pool_btn != null:
		pool_btn.pressed.emit()
	await get_tree().process_frame
	_find_button(sp, "保存技能栏").pressed.emit()
	await get_tree().create_timer(0.6).timeout
	_ok("重排并保存：%s" % str(sp.bar), sp.bar == ["spin_slash", "dash_strike", "power_strike"])
	await _capture(OUT_DIR + "/技能面板_重排后_2026-09-22.png")

	# —— 第二阶段：弓箭手职业池（展示穿透箭/箭雨新图标）——
	hub.queue_free()
	await get_tree().create_timer(0.3).timeout
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	var data2 := SaveManager.create_new_slot(0, "archer")
	SaveManager.current_data = data2
	SaveManager.current_slot = 0
	_ok("弓箭手档已建", data2 != null)
	if data2 == null:
		get_tree().quit(1)
		return
	var packed2: PackedScene = load("res://scenes/main/hub.tscn")
	var hub2: Node = packed2.instantiate()
	add_child(hub2)
	if hub2.has_method("on_scene_entered"):
		hub2.on_scene_entered({})
	await get_tree().create_timer(0.6).timeout
	var btn2 := _find_button(hub2, "技能")
	_ok("弓箭手据点按钮条「技能」存在", btn2 != null)
	if btn2 == null:
		get_tree().quit(1)
		return
	btn2.pressed.emit()
	await get_tree().create_timer(0.6).timeout
	_ok("弓箭手技能面板已打开", hub2.is_panel_visible("skills"))
	var sp2 := hub2.get_panel("skills") as SkillPanel
	_ok("弓箭手池含新图标技能", sp2 != null and sp2._pool_grid.get_child_count() == 4)
	await _capture(OUT_DIR + "/技能面板_弓箭手_2026-09-22.png")
	hub2.queue_free()

	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _capture(out: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	if err == OK and _is_blank(img):
		await get_tree().create_timer(0.5).timeout
		img = get_viewport().get_texture().get_image()
		err = img.save_png(out)
	_ok("截圖 %s（err=%d）" % [out, err], err == OK)
	if err != OK:
		_fail += 1


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _find_button(root: Node, needle: String) -> Button:
	for c in root.get_children():
		if c is Button and String((c as Button).text).contains(needle):
			return c as Button
		var r := _find_button(c, needle)
		if r != null:
			return r
	return null


func _find_button_by_name(root: Node, needle: String) -> Button:
	for c in root.get_children():
		if c is Button and String(c.name).contains(needle):
			return c as Button
		var r := _find_button_by_name(c, needle)
		if r != null:
			return r
	return null


func _wait_for_scene(scene_name: String) -> Node:
	for i in 300:
		var cs := SceneManager.get_current_scene()
		if cs != null and cs.name == scene_name:
			return cs
		await get_tree().process_frame
	return null


func _is_blank(img: Image) -> bool:
	var min_c := Color(1, 1, 1)
	var max_c := Color(0, 0, 0)
	for i in 8:
		var x := (img.get_width() * i) / 8
		var c0 := img.get_pixel(x, 0)
		var c1 := img.get_pixel(x, img.get_height() / 2)
		var c2 := img.get_pixel(x, img.get_height() - 1)
		for c in [c0, c1, c2]:
			min_c = Color(min(min_c.r, c.r), min(min_c.g, c.g), min(min_c.b, c.b))
			max_c = Color(max(max_c.r, c.r), max(max_c.g, c.g), max(max_c.b, c.b))
	var range_v := max_c.r - min_c.r + max_c.g - min_c.g + max_c.b - min_c.b
	return range_v < 0.03
