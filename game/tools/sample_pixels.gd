## 像素采样工具（开发用，不属于游戏玩法）：读 PNG → 输出指定坐标的颜色。
## 用法：
##   $GODOT --path "D:/七傳說/game" --headless res://tools/sample_pixels.gd -- \
##       <png_path> <x1,y1> <x2,y2> ...
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("用法: godot --headless res://tools/sample_pixels.gd -- <png_path> <x1,y1> [<x2,y2>...]")
		quit(1)
		return
	var path: String = args[0]
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		printerr("加载失败 %s err=%d" % [path, err])
		quit(1)
		return
	print("IMG=%s · %d×%d" % [path, img.get_width(), img.get_height()])
	for i in range(1, args.size()):
		var parts: PackedStringArray = args[i].split(",")
		if parts.size() != 2:
			printerr("坐标格式错: %s" % args[i])
			continue
		var x := int(parts[0])
		var y := int(parts[1])
		if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
			print("  (%s,%s) → 越界" % [x, y])
			continue
		var px := img.get_pixel(x, y)
		print("  (%d,%d) = rgba(%d,%d,%d,%d) #%02x%02x%02x"
			% [x, y, int(px.r * 255.0), int(px.g * 255.0), int(px.b * 255.0), int(px.a * 255.0),
				int(px.r * 255.0), int(px.g * 255.0), int(px.b * 255.0)])
	quit(0)