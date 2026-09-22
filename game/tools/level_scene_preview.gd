## 关卡容器渲染预览（阶段 3 · 自截图，用于肉眼检查相机 2× 下的细节尺度）
##
## ⚠️ 与 `tools/level_preview.tscn`（任务 6.1，三章地图生成预览）**不是同一个东西**：
##    那个画的是「布局长什么样」，本文件画的是「进关后玩家实际看到什么」
##    （LevelView 渲染 + 玩家 + 敌人 + HUD + 相机缩放）。
##
## 用法（**必须窗口化**，无头模式拿不到渲染结果）：
##   godot --path "D:/七傳說/game" res://tools/level_scene_preview.tscn
##
## 产出：`build/level_scene_preview.png`（1920×1080 全屏截图）
## 关注点：32px tile 在 2× 缩放下是否仍能看清格子 / 角色 / 敌人色块，HUD 字号是否可读。
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_PATH: String = "res://build/level_scene_preview.png"

var _level: LevelScene = null


func _ready() -> void:
	_level = LEVEL_SCENE.instantiate() as LevelScene
	# 让关卡走「直接运行」分支：`_ready` 里等 3 帧后无载荷就用默认调试关 ch1_l01
	add_child(_level)
	await get_tree().create_timer(0.4).timeout
	# 让敌人从出生点走一段，画面里能看到追击中的怪（而不是全挤在生成点）
	for _i in 90:
		await get_tree().physics_frame
	# 出生点常在地图角落 ⇒ 画面一半是地图外的空白，看不出缩放尺度。
	# 把玩家挪到地图正中再截，保证整屏都是关卡内容。
	if _level != null and _level._player != null and not _level._layout.is_empty():
		var w := float(_level._layout.get("width", 40)) * float(LevelGenerator.TILE_SIZE)
		var h := float(_level._layout.get("height", 30)) * float(LevelGenerator.TILE_SIZE)
		_level._player.global_position = Vector2(w, h) * 0.5
		_level._camera.global_position = _level._player.global_position
		_level._camera.reset_smoothing()
		for _i in 8:
			await get_tree().physics_frame
	await _screenshot()


func _screenshot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("res://build")
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_PATH)
	print("[level_scene_preview] 截图：%s err=%d（相机 zoom=%s）"
		% [OUT_PATH, err, str(_level._camera.zoom) if _level != null else "?"])
	print("[level_scene_preview] 关卡=%s · tile=%d · 存活敌人=%d · 视口=%dx%d"
		% [_level.level_id, _level._view.tile_count(), _level._alive.size(),
			GameConstants.VIEWPORT_WIDTH, GameConstants.VIEWPORT_HEIGHT])
	get_tree().quit(0)
