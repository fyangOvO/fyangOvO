## 工具：capture_main_menu.gd（P-A/P-C 封面接入真渲染抓圖；**非玩法**）
##
## 用途：真渲染實例化主菜單（豆包主菜單背景 + 面板；第三方立繪 / 武器展示欄已移除），
##       截圖落盤供肉眼驗收。素材缺失時主菜單自行安全降級，本工具照樣能截。
##
## 用法（**必須去掉 --headless**，否則沒有渲染）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_main_menu.tscn
## 退出碼：0 = 截圖成功；1 = 失敗。
##
## ⚠️ 只做「渲染 + 存 PNG」；不改任何玩法代碼、不動素材。
extends Node2D

const MENU_SCENE: String = "res://scenes/main/main_menu.tscn"
const OUT_PATH: String = "D:/七傳說/deliverables/首页定稿_主菜单_2026-09-22.png"


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== 主菜單封面真渲染抓圖 =====")
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
	# 等兩幀 + 0.5s：讓 _ready 全部跑完、貼圖上 GPU
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_PATH)
	_ok("截圖寫出 %s（err=%d）" % [OUT_PATH, err], err == OK)
	print("===== 結果：%d 項失敗 =====" % (1 if err != OK else 0))
	get_tree().quit(0 if err == OK else 1)


func _ok(label: String, cond: bool) -> void:
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
