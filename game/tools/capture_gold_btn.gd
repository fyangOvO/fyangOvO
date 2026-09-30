## 工具：capture_gold_btn.gd（**診斷用**：金色雕花九宮格在不同按鈕高度下的實際渲染）
##
## 用法（**必須去掉 `--headless`**）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_gold_btn.tscn
## 產出：`D:/七傳說/deliverables/gstack/e_loot_shot/e-8-金色按鈕高度階梯診斷.png`
##
## 起因（HANDOFF-E 目視 e-7 時發現）：`UISkin.button_stylebox_gold()` 的
## `texture_margin_top/bottom = 14`，而素材 `btn_gold.png`(432×92) 的上下金線落在
## 源 y=10 與 y=82/86。按鈕高度 < 28 時，九宮格的「下帶」被整體上提 ⇒ 金線落進
## 按鈕垂直中央 ⇒ **橫穿文字**。本工具把 24/28/32/40/48 五檔並排渲染，目視定最小可用高度。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/e_loot_shot"
const HEIGHTS: Array[int] = [24, 28, 32, 40, 48]


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== 金色按鈕九宮格 · 高度階梯診斷 =====")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run()


func _run() -> void:
	print("渲染驱动：%s" % DisplayServer.get_name())
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color("14171C")
	bg.size = Vector2(640, 360)
	layer.add_child(bg)

	var vb := VBoxContainer.new()
	vb.position = Vector2(20, 20)
	vb.add_theme_constant_override("separation", 10)
	layer.add_child(vb)

	for h in HEIGHTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		var tag := Label.new()
		tag.text = "h=%d" % h
		tag.add_theme_font_size_override("font_size", 12)
		tag.custom_minimum_size = Vector2(46, 0)
		row.add_child(tag)
		var b := Button.new()
		b.text = "增幅 [utility]（未解锁 · 需掉落获得）"
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(340, h)
		row.add_child(b)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/e-8-金色按鈕高度階梯診斷.png" % OUT_DIR
	var err := img.save_png(path)
	print("[%s] 截图 %s（err=%d）" % ["OK  " if err == OK else "FAIL", path, err])
	get_tree().quit(0 if err == OK else 1)
