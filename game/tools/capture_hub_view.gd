## 工具：capture_hub_view.gd（據點整體 UI 目視抓圖；**非玩法、不動用戶存檔**）
##
## 用法（必須去掉 --headless，否則沒有渲染）：
##   godot --path "D:/七傳說/game" res://tools/capture_hub_view.tscn
## 產出：據點全景 + 角色面板 兩張（deliverables/gstack/hub_shot/）。
## ⚠️ 用**臨時空槽**（動態找，不碰用戶槽）；結束後刪除臨時槽。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/hub_shot"
var _temp_slot := -1
var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 90.0)
	print("===== 據點整體 UI 真渲染抓圖 =====")
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless", DisplayServer.get_name() != "headless")
	# 動態找第一個空槽（不碰用戶存檔）；全滿則不執行
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if not SaveManager.slot_exists(i):
			_temp_slot = i
			break
	if _temp_slot < 0:
		_ok("無空槽可建臨時存檔", false)
		get_tree().quit(1)
		return
	var data := SaveManager.create_new_slot(_temp_slot, "warrior")
	if data == null:
		_ok("臨時存檔創建失敗：%s" % SaveManager.last_error, false)
		get_tree().quit(1)
		return
	SaveManager.current_data = data
	SaveManager.current_slot = _temp_slot
	# 造 2 件裝備入包（角色面板有行可顯示）
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	if tpl != null:
		data.inventory.append(EquipmentInstance.create_from_template(tpl, 9, GameConstants.Rarity.MAGIC))
	tpl = ConfigLoader.get_equipment_template("dagger_venom")
	if tpl != null:
		data.inventory.append(EquipmentInstance.create_from_template(tpl, 11, GameConstants.Rarity.RARE))
	SaveManager.save_to_slot(_temp_slot, data)

	SceneManager.fade_duration = 0.0
	var hub: Node = (load("res://scenes/main/hub.tscn") as PackedScene).instantiate()
	add_child(hub)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await get_tree().create_timer(0.6).timeout
	_ok("進入據點", hub != null)
	if hub == null:
		_cleanup()
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	await _shot("hub-0-據點全景.png")
	# 打開角色面板
	if hub.has_method("toggle_panel"):
		hub.toggle_panel("character")
	elif hub.has_method("_toggle_panel"):
		hub.call("_toggle_panel", "character")
	await get_tree().create_timer(0.4).timeout
	await _shot("hub-1-角色面板.png")
	# 關面板，打開背包
	if hub.has_method("toggle_panel"):
		hub.toggle_panel("inventory")
	elif hub.has_method("_toggle_panel"):
		hub.call("_toggle_panel", "inventory")
	await get_tree().create_timer(0.4).timeout
	await _shot("hub-2-背包面板.png")
	# 技能师對話氣泡（portrait_quest 立繪；缺口驗收）
	if hub.has_method("_speak"):
		hub.call("_speak", "技能怎么带？我帮你调。", "portrait_quest")
	await get_tree().create_timer(0.4).timeout
	await _shot("hub-3-技能师对话.png")
	# 熱區 hover 金框反饋（鼠標移到技能師熱區中心）
	Input.warp_mouse(Vector2(220, 230))
	await get_tree().create_timer(0.4).timeout
	await _shot("hub-4-热区hover.png")
	# 深渊使者對話氣泡（portrait_abyss 立繪）
	if hub.has_method("_speak"):
		hub.call("_speak", "深渊之下……你确定要去？", "portrait_abyss")
	await get_tree().create_timer(0.4).timeout
	await _shot("hub-5-深渊使者对话.png")

	print("[Capture] 完成 → %s" % OUT_DIR)
	_cleanup()
	get_tree().quit(0)


## 清理臨時槽（不碰用戶存檔）
func _cleanup() -> void:
	if _temp_slot >= 0 and SaveManager.slot_exists(_temp_slot):
		SaveManager.delete_slot(_temp_slot)
	SaveManager.current_slot = -1
	SaveManager.current_data = null


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	img.save_png(path)
	print("[Capture] 已保存 %s" % path)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
