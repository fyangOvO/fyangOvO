extends SceneTree
## 调试：直接进第一关，3 秒后截图保存
func _initialize() -> void:
	var packed := load("res://scenes/levels/level.tscn") as PackedScene
	if packed == null:
		print("ERR: level_scene.tscn not found")
		quit(1)
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	# 等几帧让场景初始化
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	# 截图
	var img := root.get_viewport().get_texture().get_image()
	var out := "user://debug_screenshot.png"
	img.save_png(out)
	print("SAVED: ", out, " size=", img.get_width(), "x", img.get_height())
	quit(0)
