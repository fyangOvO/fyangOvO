## 9.1 启动画面预览（第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/boot_preview.tscn
##   输出 build/boot_preview.png：游戏实际启动画面（主场景自检界面）
extends Node2D

var _frame := 0
var _booted := false


func _ready() -> void:
	var boot_scene: PackedScene = load("res://scenes/main/main.tscn")
	var inst: Node = boot_scene.instantiate()
	add_child(inst)
	_booted = true


func _process(_delta: float) -> void:
	if not _booted:
		return
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/boot_preview.png")
		print("boot_preview saved: err=%d" % err)
		get_tree().quit(0)
