## 关卡 / 地图生成渲染预览（任务 6.1 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/level_preview.tscn
##   输出 build/level_preview.png：三张程序化地图俯视（ch1 森林 / ch2 灰烬 / ch3 霜渊）
extends Node2D

var _frame := 0

## 瓦片配色（48 色板内取，章节主题）
const THEMES := {
	1: {"ground": Color(0.16, 0.23, 0.18), "wall": Color(0.07, 0.09, 0.07), "obstacle": Color(0.22, 0.30, 0.24)},
	2: {"ground": Color(0.23, 0.16, 0.12), "wall": Color(0.09, 0.06, 0.05), "obstacle": Color(0.30, 0.20, 0.10)},
	3: {"ground": Color(0.14, 0.19, 0.25), "wall": Color(0.06, 0.08, 0.10), "obstacle": Color(0.20, 0.26, 0.34)},
}


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "关卡 / 地图程序化生成预览（任务 6.1 · 三章主题）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 8)
	add_child(title)

	# 三章代表关：ch1_l01 / ch2_l10 / ch3_l20
	var samples := [["ch1_l01", "① 第一章 幽林（ch1_l01）"], ["ch2_l10", "② 第二章 灰烬堡（ch2_l10）"], ["ch3_l20", "③ 第三章 霜渊（ch3_l20 · BOSS 关）"]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260917
	var x := 16.0
	for sample in samples:
		var lv: LevelData = ConfigLoader.get_level(sample[0])
		var layout := LevelGenerator.generate(lv, rng)
		var theme: Dictionary = THEMES[int(lv.chapter)]
		var map := _draw_map(layout, theme, 5.0)
		map.position = Vector2(x, 60)
		add_child(map)
		var cap := Label.new()
		cap.text = sample[1]
		cap.add_theme_font_size_override("font_size", 12)
		cap.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		cap.position = Vector2(x, 66 + 5.0 * float(layout["height"]) + 6)
		add_child(cap)
		x += 5.0 * float(layout["width"]) + 20

	var foot := Label.new()
	foot.text = "程序化生成（拒绝采样房间 + 走廊连接）· 玩家出生/怪物/精英/BOSS 锚点由布局产出 · 20 关数据齐备"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 690)
	add_child(foot)


func _draw_map(layout: Dictionary, theme: Dictionary, scale: float) -> Node2D:
	var root := Node2D.new()
	for cell in layout["cells"]:
		var tile := int(layout["cells"][cell])
		var col: Color
		match tile:
			LevelGenerator.TILE_WALL: col = theme["wall"]
			LevelGenerator.TILE_OBSTACLE: col = theme["obstacle"]
			_: col = theme["ground"]
		var r := ColorRect.new()
		r.color = col
		r.position = Vector2(cell) * scale
		r.size = Vector2(scale, scale)
		root.add_child(r)
	# 出生点（白）
	var p := ColorRect.new()
	p.color = Color(0.95, 0.95, 0.95)
	p.position = Vector2(layout["player_spawn"]) * scale
	p.size = Vector2(scale, scale)
	root.add_child(p)
	# 精英（紫）
	for c in layout["elite_spawns"]:
		var e := ColorRect.new()
		e.color = Color(0.72, 0.4, 0.9)
		e.position = Vector2(c) * scale
		e.size = Vector2(scale, scale)
		root.add_child(e)
	# BOSS（金红）
	if layout["boss_spawn"] != Vector2i(-1, -1):
		var b := ColorRect.new()
		b.color = Color(0.95, 0.45, 0.2)
		b.position = Vector2(layout["boss_spawn"]) * scale
		b.size = Vector2(scale, scale)
		root.add_child(b)
	return root


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/level_preview.png")
		print("level_preview saved: err=%d" % err)
		get_tree().quit(0)
