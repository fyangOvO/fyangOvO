## 工具：intro_movie.gd（把 15 秒片頭錄成影片幀；**非玩法**）
##
## 用法（**必須去掉 `--headless`**，且**必須**加 `--write-movie`）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       --write-movie "D:/七傳說/deliverables/gstack/intro_movie/frames/intro.png" \
##       --fixed-fps 30 res://tools/intro_movie.tscn
##
## 原理：Godot **Movie Maker** 模式會用**固定時間步長**逐幀渲染（不與真實時間同步），
##       所以 15 秒 × 30fps = **450 幀**，且每一幀都確定可重現 —— 這正是做片頭動畫
##       要的效果（真實時間抓圖會掉幀 / 抖動）。
##
## 本腳本只做三件事：實例化片頭 → 關掉「自動前進」→ 等滿片長後退出。
## ⚠️ 只做「播放 + 退出」；不改任何玩法代碼、不動素材。
extends Node2D


func _ready() -> void:
	# 錄影模式下若卡住會一直寫幀寫到爆盤 ⇒ 看門狗必須比片長寬鬆但一定存在
	VerifyWatchdog.arm(get_tree(), 180.0)

	# ⚠️ 片長**從片頭腳本自己的常量讀**（單一來源），不用硬編碼副本。
	#    也不靠 `class_name IntroScreen` 的全域註冊 —— 新腳本的 class_name 要等
	#    編輯器重掃 `global_script_class_cache.cfg` 才生效，用 `load()` 最穩。
	var total := 15.0
	var script: Script = load("res://scripts/ui/intro_screen.gd")
	if script != null:
		total = float((script.get_script_constant_map()).get("TOTAL_SEC", 15.0))
	print("===== 片頭錄影：%.1f 秒 / %d 幀（30fps）=====" % [total, int(round(total * 30.0))])
	print("[IntroMovie] 渲染驅動：%s（必須不是 headless）" % DisplayServer.get_name())

	var packed := load("res://scenes/main/intro.tscn") as PackedScene
	if packed == null:
		push_error("[IntroMovie] 片頭場景載入失敗")
		get_tree().quit(1)
		return
	var intro: Node = packed.instantiate()
	# 關掉自動前進：否則播完會切場景，錄影會多錄到主菜單
	intro.set("auto_advance_enabled", false)
	add_child(intro)

	# 等滿片長（Movie Maker 下 = 固定步長 × 幀數，非真實時間）
	await get_tree().create_timer(total).timeout
	print("[IntroMovie] 片長播畢，結束錄影")
	get_tree().quit(0)
