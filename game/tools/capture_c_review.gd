## 工具：capture_c_review.gd（HANDOFF-C UI 打磨批 · 復盤目視驗收；**非玩法**）
##
## 用法（**必須去掉 `--headless`**，否則沒有渲染）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_c_review.tscn
## 產出：`D:/七傳說/deliverables/gstack/c_review_shot/*.png`
##
## 驗收重點（對應 2026-09-30 復盤修復項）：
##   ① 主菜單：標題徽章**真的顯示**（此前 `title_emblem.png` 是 3548×1181 ⇒ 導入 valid=false
##      ⇒ 貼圖載不到、徽章消失，還連帶把封面垂直節奏從 360 打成 328）
##   ② 據點營地：7 個 NPC 小立繪**真的顯示**（此前素材放在 `assets/ui/` 根、UISkin 找的是
##      `assets/ui/quest/` ⇒ `texture()` 全回 null）
##   ③ 面板金邊**真的顯示**（此前 `UISkin.panel_stylebox_gold()` 回 null ⇒ 從未生效）
##   ④ 按鈕金色九宮格**真的顯示**（此前只寫在死路徑 `ui_theme.gd`，`theme.tres` 從未重生成）
##
## ⚠️ 只用測試槽位 7（跑完刪除），**不碰玩家存檔**。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/c_review_shot"
const TEST_SLOT: int = 7
var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 90.0)
	print("===== HANDOFF-C UI 復盤目視抓圖 =====")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless", DisplayServer.get_name() != "headless")

	# ---- ① 主菜單（徽章 / 壓暗深度 / 帳號文案 / 金按鈕）----
	var menu: Node = (load("res://scenes/main/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	await _shot("c-1-主菜單.png")
	menu.queue_free()
	await get_tree().process_frame

	# ---- 據點：造測試存檔（槽位 7）----
	if SaveManager.slot_exists(TEST_SLOT):
		SaveManager.delete_slot(TEST_SLOT)
	var data := SaveManager.create_new_slot(TEST_SLOT, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = TEST_SLOT
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	if tpl != null:
		data.inventory.append(
			EquipmentInstance.create_from_template(tpl, 9, GameConstants.Rarity.RARE))
	SaveManager.save_to_slot(TEST_SLOT, data)

	SceneManager.fade_duration = 0.0
	var hub: Node = (load("res://scenes/main/hub.tscn") as PackedScene).instantiate()
	add_child(hub)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await get_tree().create_timer(0.9).timeout
	_ok("進入據點", hub != null)

	# ---- ② 營地（NPC 小立繪 + 金按鈕）----
	await _shot("c-2-據點營地.png")

	# ---- ③ 背包（面板金邊）----
	hub._toggle_panel("inventory")
	await get_tree().create_timer(0.5).timeout
	await _shot("c-3-背包面板金邊.png")
	hub._toggle_panel("inventory")
	await get_tree().create_timer(0.3).timeout

	# ---- ④ 技能面板 ----
	hub._toggle_panel("skills")
	await get_tree().create_timer(0.5).timeout
	await _shot("c-4-技能面板.png")
	hub._toggle_panel("skills")
	await get_tree().create_timer(0.3).timeout

	# ---- ⑤ 符文圖鑑 ----
	hub._toggle_panel("rune_codex")
	await get_tree().create_timer(0.5).timeout
	await _shot("c-5-符文圖鑑.png")

	if SaveManager.slot_exists(TEST_SLOT):
		SaveManager.delete_slot(TEST_SLOT)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _shot(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	_ok("截圖 %s（err=%d）" % [fname, err], err == OK)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
