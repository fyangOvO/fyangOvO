## 工具：capture_step5.gd（步骤 5 · 据点半透明面板统一视觉；**非玩法**）
##
## 用法（**必须去掉 --headless**；小窗 640×360 demo）：
##   godot --path "D:/七傳說/game" res://tools/capture_step5.tscn
## 产出：角色属性 / 天赋树 / 锻造台 三张统一视觉截图。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables"
var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== 步骤 5 据点半透明面板统一视觉抓图（小窗 640×360）=====")
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless", DisplayServer.get_name() != "headless")
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	var data := SaveManager.create_new_slot(0, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = 0
	# 造 2 件装备入包（锻造台有行可显示）
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	if tpl != null:
		data.inventory.append(EquipmentInstance.create_from_template(tpl, 9, GameConstants.Rarity.MAGIC))
	tpl = ConfigLoader.get_equipment_template("dagger_venom")
	if tpl != null:
		data.inventory.append(EquipmentInstance.create_from_template(tpl, 11, GameConstants.Rarity.RARE))
	SaveManager.save_to_slot(0, data)

	SceneManager.fade_duration = 0.0
	var hub: Node = (load("res://scenes/main/hub.tscn") as PackedScene).instantiate()
	add_child(hub)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await get_tree().create_timer(0.6).timeout
	_ok("进入据点", hub != null)
	if hub == null:
		get_tree().quit(1)
		return

	# ① 角色属性
	hub._toggle_panel("character")
	await get_tree().create_timer(0.5).timeout
	_ok("角色属性面板打开", hub.is_panel_visible("character"))
	await _capture(OUT_DIR + "/角色属性_统一视觉_2026-09-22.png")
	hub._toggle_panel("character")
	await get_tree().create_timer(0.25).timeout

	# ② 天赋树
	hub._toggle_panel("talent")
	await get_tree().create_timer(0.5).timeout
	_ok("天赋树面板打开", hub.is_panel_visible("talent"))
	await _capture(OUT_DIR + "/天赋树_统一视觉_2026-09-22.png")
	hub._toggle_panel("talent")
	await get_tree().create_timer(0.25).timeout

	# ③ 锻造台
	hub._toggle_panel("forge")
	await get_tree().create_timer(0.5).timeout
	_ok("锻造台面板打开", hub.is_panel_visible("forge"))
	await _capture(OUT_DIR + "/锻造台_统一视觉_2026-09-22.png")

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
	_ok("截圖 %s（err=%d）" % [out, err], err == OK)
	if err != OK:
		_fail += 1


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
