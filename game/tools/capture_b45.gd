## B4-5 目视确认抓图（`3-E7` 元素伤害飘字配色 · 开发用，不属于游戏玩法）
##
## 用法：
##   APPDATA='C:\Users\11265\AppData\Roaming' "<Godot>" --path . tools/capture_b45.tscn
##   输出：D:/七傳說/deliverables/gstack/b45_shot/*.png
##
## 为什么必须真渲染抓图：`3-E7` 是**配色**——`verify_element_ext` 只能断言
## `normal_color_for()` 的返回值，证明不了「真渲染出来肉眼可分辨、白字在深底上看得清」。
## 本项目已多次栽在「数据通了但画不出来」（`UISkin` 静默返回 null 那类）。
##
## 一张：6 元素飘字并排 + 暴击/普通对照。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/b45_shot"
const DN_SCENE: PackedScene = preload("res://scenes/juice/damage_number.tscn")

const ELEMENTS: Array = [
	["physical", "物理"], ["fire", "火"], ["cold", "冰"],
	["lightning", "雷"], ["poison", "毒"], ["shadow", "暗"],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var bg := ColorRect.new()
	bg.color = Color("1A1E24")
	bg.size = Vector2(640.0, 360.0)
	bg.z_index = -10
	add_child(bg)

	_title("B4-5 · 3-E7 元素伤害飘字配色（6 元素各一色 / 暴击优先）", Vector2(12.0, 8.0), 12, "8FA0B4")
	_title("① 6 元素各一色（非暴击）", Vector2(12.0, 34.0), 11, "C8D2DE")

	var x := 66.0
	for pair in ELEMENTS:
		_spawn_num(Vector2(x, 96.0), 1234.0, false, pair[0])
		_title("%s / %s" % [pair[1], pair[0]], Vector2(x - 34.0, 132.0), 10, "8FA0B4")
		x += 96.0

	_title("② 暴击优先（暴击 + 火 ⇒ 暴击色，而非火色）", Vector2(12.0, 190.0), 11, "C8D2DE")
	_spawn_num(Vector2(96.0, 252.0), 5678.0, true, "fire")
	_title("暴击 + 火 ⇒ 橙红大字", Vector2(46.0, 288.0), 10, "8FA0B4")
	_spawn_num(Vector2(320.0, 252.0), 999.0, false, "")
	_title("非暴击 + 空元素 ⇒ 普通色", Vector2(270.0, 288.0), 10, "8FA0B4")
	_spawn_num(Vector2(520.0, 252.0), 4321.0, false, "shadow")
	_title("非暴击 + 暗 ⇒ 暗紫", Vector2(486.0, 288.0), 10, "8FA0B4")

	await _frames(5)
	await _shot("b45-1-元素飘字配色.png")

	print("[Capture] 完成 → %s" % OUT_DIR)
	get_tree().quit(0)


## 生成一个飘字并**冻结**（关掉 `_process`：否则它会持续上飘 + 淡出，抓图会糊/淡）
func _spawn_num(pos: Vector2, amount: float, is_crit: bool, element: String) -> void:
	var num := DN_SCENE.instantiate() as DamageNumber
	add_child(num)
	num.global_position = pos
	num.setup(amount, is_crit, element)
	num.set_process(false)


func _title(text: String, pos: Vector2, size: int, hex: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(hex))
	add_child(l)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	img.save_png(path)
	print("[Capture] 已保存 %s" % path)
