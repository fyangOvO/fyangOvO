## 地形素材接入 · 三章地形正式交付图（步骤 8B · 开发用，不属于游戏玩法）
##
## 用法（**必须去掉 --headless**）：
##   godot --path "D:/七傳說/game" res://tools/capture_terrain8b.tscn
##
## 产出（deliverables/）：
##   `地形接入_森林_2026-09-23.png`  / `地形接入_火山_2026-09-23.png` /
##   `地形接入_霜渊_2026-09-23.png`（640×360 小窗、默认视角 1.0，展示地砖/墙/障碍全景）
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables"
const DEFAULT_IDS: Array[String] = ["ch1_l01", "ch2_l07", "ch3_l14"]
const LABELS := {"ch1_l01": "森林", "ch2_l07": "火山", "ch3_l14": "霜渊"}

var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 200.0)
	_run()


func _run() -> void:
	print("===== 步骤 8B 三章地形正式交付图（小窗 640×360）=====")
	_ok("渲染驱动不是 headless（否则抓不到画面）",
		DisplayServer.get_name() != "headless")
	for id in DEFAULT_IDS:
		await _capture_level(id)
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _capture_level(level_id: String) -> void:
	print("--- 关卡 %s ---" % level_id)
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": level_id,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	_freeze_enemies(level)
	await _settle(level)

	_ok("%s：关卡已构建（敌人 %d 个）" % [level_id, level._alive.size()],
		not level._alive.is_empty())
	var view := level._view
	var biome := view.biome()
	var atlas := TileAtlas.for_biome(biome)
	_ok("%s：LevelView 已设 biome（%s）· 真实美术 = %s" % [level_id, biome, str(atlas.has_real_art())],
		atlas.texture() != null)

	# 默认视角（zoom 1.0）跟随玩家，展示地砖/墙/障碍全景
	level._camera.zoom = Vector2(1.0, 1.0)
	await _hold(level, 5)
	var label: String = LABELS.get(level_id, level_id)
	await _shot("地形接入_%s_2026-09-23.png" % label)

	level.queue_free()
	await _frames(3)


## 冻住所有敌人（不删，精灵照常渲染，只是不再思考/攻击）——同上一步 capture_tiles
func _freeze_enemies(level: LevelScene) -> void:
	for e in level._alive:
		if not is_instance_valid(e):
			continue
		e.set_physics_process(false)
		e.set_process(false)


## 等场景稳定：敌人就位、掉落光柱出现、HUD 文本刷出来
func _settle(level: LevelScene) -> void:
	await _hold(level, 10)
	await _hold(level, 36)


func _hold(level: LevelScene, n: int) -> void:
	for _i in n:
		_keep_player_alive(level)
		await get_tree().process_frame


func _keep_player_alive(level: LevelScene) -> void:
	if not is_instance_valid(level) or level.is_queued_for_deletion():
		return
	var player := level._player
	if player == null or not is_instance_valid(player):
		return
	var hc = player.health
	if hc == null or hc.is_dead:
		return
	var maxhp: float = hc.get_max_hp()
	if hc.get_current_hp() < maxhp:
		hc.restore(maxhp - hc.get_current_hp())


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	_ok("抓图 %s → %d×%d（err=%d）" % [fname, img.get_width(), img.get_height(), err],
		err == OK and img.get_width() > 0)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
