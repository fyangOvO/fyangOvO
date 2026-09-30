## 工具：capture_gold_btn.gd（**診斷 + 回歸用**：按鈕九宮格在不同高度下的實際渲染）
##
## 用法（**必須去掉 `--headless`**）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_gold_btn.tscn
## 產出：`D:/七傳說/deliverables/gstack/e_loot_shot/e-8-按鈕九宮格-高度階梯診斷.png`
##
## 起因（HANDOFF-E 第二輪目視 e-7 時發現的破相）：
## `ui_theme.gd` 曾把全局 `Button` 五態指向**雕花** `btn_gold.png`(432×92)，
## `texture_margin_top/bottom = 14`；而該素材的上下金線落在**源 y=10 與 y=82/86**。
## 按鈕高度 < 28 時九宮格上下帶重疊、< ~40 時金線落進垂直中央 ⇒ **橫穿文字**；
## 而**默認按鈕高度只有 ~24px** ⇒ 全部裸按鈕中招。
##
## 本工具同時渲染**兩組**（修好之後就是防回歸證據）：
##   A. 全局 `Button`（主題默認 = 128×24 平面金）@ 24/28/32/40/48 —— 應**全部乾淨**
##   B. 雕花 `UISkin.button_stylebox_gold()` @ 24 / 48 —— 24 應破相（證明它不能下放）、48 應乾淨（主菜單用）
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/e_loot_shot"
const HEIGHTS: Array[int] = [24, 28, 32, 40, 48]
const SAMPLE_TEXT: String = "增幅 [utility]（未解锁 · 需掉落获得）"


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
	vb.position = Vector2(14, 8)
	vb.add_theme_constant_override("separation", 6)
	layer.add_child(vb)

	_head(vb, "A · 全局 Button（主题默认 = 128×24 平面金）—— 应全部干净")
	for h in HEIGHTS:
		_row(vb, "h=%d" % h, h, null)

	_head(vb, "B · 雕花 btn_gold.png（432×92）—— 24 应破相 / 48 才干净（主菜单 256×48 专用）")
	for h in [24, 48]:
		_row(vb, "h=%d" % h, h, UISkin.button_stylebox_gold())

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/e-8-按鈕九宮格-高度階梯診斷.png" % OUT_DIR
	var err := img.save_png(path)
	print("[%s] 截图 %s（err=%d）" % ["OK  " if err == OK else "FAIL", path, err])
	get_tree().quit(0 if err == OK else 1)


func _head(vb: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("C8B78A"))
	vb.add_child(l)


func _row(vb: VBoxContainer, tag_text: String, h: int, sb: StyleBox) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var tag := Label.new()
	tag.text = tag_text
	tag.add_theme_font_size_override("font_size", 12)
	tag.custom_minimum_size = Vector2(46, 0)
	row.add_child(tag)
	var b := Button.new()
	b.text = SAMPLE_TEXT
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(340, h)
	if sb != null:
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, sb)
	row.add_child(b)
