## 工具：capture_intro.gd（片頭「勇者斗恶魔」真渲染抓圖；**非玩法**）
##
## 用法（**必須去掉 `--headless`**，否則沒有渲染）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_intro.tscn
## 產出：`D:/七傳說/deliverables/gstack/intro_shot/*.png`（18 張，按播放時序）
## 退出碼：0 = 全部截圖成功；1 = 有失敗項。
##
## ⚠️ 兩條硬約束（本專案踩過的坑，見 MEMORY 鐵律 ⑥/⑦）：
##   ① 抓圖前必須 `await RenderingServer.frame_post_draw` —— 只等 `process_frame`
##      會截到**凍結畫面**（症狀：連拍多張 PNG 位元組數完全相同）。
##   ② 每次抓完要斷言「與上一張**不同**」，否則「抓圖工具本身壞了」也會全綠。
##
## ⚠️ 只做「渲染 + 存 PNG」；不改任何玩法代碼、不動素材、不碰玩家存檔。
extends Node2D

const INTRO_SCENE: String = "res://scenes/main/intro.tscn"
const OUT_DIR: String = "D:/七傳說/deliverables/gstack/intro_shot"

## 抓圖時序（秒，從片頭開始播放算起）→ 檔名。
## 對齊 30 秒分鏡：①②標題 ③④入場 ⑤⑥魔王 ⑦前壓 ⑧–⑫打鬥 ⑬⑭覺醒 ⑮⑯收尾。
const SHOTS: Array = [
	[0.6, "01-背景淡入.png"],
	[2.0, "02-标题浮现.png"],
	[5.0, "03-勇者入场中.png"],
	[6.4, "04-勇者列队.png"],
	[7.6, "05-魔王显形.png"],
	[9.3, "06-魔王与字幕.png"],
	[10.7, "07-勇者前压.png"],
	[11.8, "08-剑士斩击.png"],
	[13.7, "09-游侠连射.png"],
	[15.9, "10-法师火球.png"],
	[17.4, "11-魔王反击.png"],
	[19.9, "12-三勇者合击.png"],
	[23.0, "13-魔王觉醒立绘.png"],
	[25.1, "14-剑士觉醒立绘.png"],
	[26.5, "15-游侠觉醒立绘.png"],
	[27.9, "16-法师觉醒立绘.png"],
	[29.0, "17-定版.png"],
	[29.85, "18-完整画面.png"],
]

var _fail: int = 0
var _start_ms: int = 0
var _prev_bytes: int = -1


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 120.0)
	print("===== 片頭真渲染抓圖（勇者斗恶魔）=====")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless（否則抓不到畫面）", DisplayServer.get_name() != "headless")

	var intro: Node = (load(INTRO_SCENE) as PackedScene).instantiate()
	# 關掉自動前進：否則序列播完會切場景，抓到一半畫面就沒了
	intro.set("auto_advance_enabled", false)
	add_child(intro)
	_start_ms = Time.get_ticks_msec()
	_ok("片頭場景已實例化", intro != null)

	for shot in SHOTS:
		await _wait_to(float(shot[0]))
		await _capture(String(shot[1]))

	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 等到「片頭開始後 sec 秒」（真實時間，不按幀數近似）。
func _wait_to(sec: float) -> void:
	var target := _start_ms + int(sec * 1000.0)
	while Time.get_ticks_msec() < target:
		await get_tree().process_frame


func _capture(fname: String) -> void:
	# ⚠️ 必須等 GPU 真的畫完這一幀，否則會截到凍結畫面
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	var bytes := 0
	if err == OK:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			bytes = int(f.get_length())
			f.close()
	_ok("截圖 %s（%d bytes）" % [fname, bytes], err == OK and bytes > 0)
	# ② 防「抓圖工具本身壞了」：本張必須與上一張不同
	if _prev_bytes >= 0:
		_ok("  ↳ %s 與上一張畫面不同（非凍結畫面）" % fname, bytes != _prev_bytes)
	_prev_bytes = bytes


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
