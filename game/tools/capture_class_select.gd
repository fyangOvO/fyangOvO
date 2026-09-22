## 工具：capture_class_select.gd（步驟 2 角色選擇頁真渲染抓圖；**非玩法**）
##
## 用途：主菜單點「開始遊戲」→ 彈出角色選擇面板 → 依次切換三職業各截一張，
##       落盤供肉眼驗收（職業描述 / 數值預覽 / 立繪大圖 / 技能展示四欄）。
##
## 用法（**必須去掉 --headless**，否則沒有渲染）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_class_select.tscn
## 退出碼：0 = 全部截圖成功；1 = 失敗。
##
## ⚠️ 只做「渲染 + 存 PNG」；不改任何玩法代碼、不動素材。
extends Node2D

const MENU_SCENE: String = "res://scenes/main/main_menu.tscn"
const OUT_DIR: String = "D:/七傳說/deliverables"
const CLASSES: Array = [
	{"id": "warrior", "file": "角色选择_战士_2026-09-22.png"},
	{"id": "archer", "file": "角色选择_弓箭手_2026-09-22.png"},
	{"id": "mage", "file": "角色选择_法师_2026-09-22.png"},
]

var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== 角色选择面板真渲染抓圖 =====")
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless（否則抓不到畫面）", DisplayServer.get_name() != "headless")
	var packed: PackedScene = load(MENU_SCENE)
	_ok("主菜單場景可載入", packed != null)
	if packed == null:
		get_tree().quit(1)
		return
	var menu: Node = packed.instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout

	# 無存檔 → 點「開始遊戲」彈角色選擇
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1

	var start_btn := _find_button(get_tree().current_scene, "开始游戏")
	_ok("主菜單「开始游戏」按鈕存在", start_btn != null)
	if start_btn == null:
		get_tree().quit(1)
		return
	start_btn.pressed.emit()
	await get_tree().create_timer(0.5).timeout

	var csp := _find_by_class(get_tree().current_scene, "CharacterSelectPanel")
	_ok("角色選擇面板已彈出", csp != null)
	if csp == null:
		get_tree().quit(1)
		return

	for entry in CLASSES:
		var btn := _find_button(csp, ConfigLoader.class_display_name(String(entry["id"])))
		if btn != null:
			btn.pressed.emit()
		# 轮询：等职业名标签真的切到目标职业（防瞬时竞态）
		for _i in 60:
			await get_tree().process_frame
			var name_l := _find_label(csp, ConfigLoader.class_display_name(String(entry["id"])))
			if name_l != null:
				break
		await get_tree().create_timer(0.4).timeout
		var img := get_viewport().get_texture().get_image()
		var out := OUT_DIR + "/" + String(entry["file"])
		var err := img.save_png(out)
		# 非空白校验：全黑/全白说明没抓到帧，重试一次
		if err == OK and _is_blank(img):
			await get_tree().create_timer(0.5).timeout
			img = get_viewport().get_texture().get_image()
			err = img.save_png(out)
		_ok("截圖 %s（err=%d）" % [out, err], err == OK)
		if err != OK:
			_fail += 1

	# 清理：不污染開發機
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1

	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _find_by_class(root: Node, cls: String) -> Node:
	for c in root.get_children():
		if c.is_class(cls) or (c.get_script() != null
				and String((c.get_script() as Script).get_global_name()) == cls):
			return c
		var r := _find_by_class(c, cls)
		if r != null:
			return r
	return null


func _find_button(root: Node, needle: String) -> Button:
	for c in root.get_children():
		if c is Button and String((c as Button).text).contains(needle):
			return c as Button
		var r := _find_button(c, needle)
		if r != null:
			return r
	return null


func _find_label(root: Node, needle: String) -> Label:
	for c in root.get_children():
		if c is Label and String((c as Label).text).contains(needle):
			return c as Label
		var r := _find_label(c, needle)
		if r != null:
			return r
	return null


## 空白校验：近纯色（方差极小）视为没抓到帧
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
