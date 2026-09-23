## BOSS 觉醒立绘卡 · 真渲染取证（步骤 8C · 开发用，不属于游戏玩法）
##
## 用法（**必须去掉 --headless**）：
##   godot --path "D:/七傳說/game" res://tools/capture_boss_awaken8c.tscn
##
## 产出（deliverables/）：
##   `BOSS觉醒立绘卡_骨暴君_2026-09-23.png`（ch1_l06 · 骸骨暴君觉醒卡瞬间，
##   640×360 小窗：暗幕 + 立绘大图 + 扫光 + BOSS 名 + 第 1 階段提示 + 粒子）
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables"

var _fail: int = 0
var _level: LevelScene = null


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 200.0)
	_run()


func _run() -> void:
	print("===== 步骤 8C BOSS 觉醒立绘卡抓图（小窗 640×360）=====")
	_ok("渲染驱动不是 headless（否则抓不到画面）",
		DisplayServer.get_name() != "headless")

	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _frames(3)
	_level.on_scene_entered({
		"level_id": "ch1_l06",
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _settle(_level)

	var boss: EnemyBase = null
	for e in _level._alive:
		if e.data != null and e.data.tier == MonsterData.Tier.BOSS:
			boss = e
			break
	_ok("场上存在 BOSS（骸骨暴君）", boss != null)
	_ok("BOSS 沉睡中（AI 冻结，待机动画保留）", not boss.is_physics_processing())

	# 玩家传送到 BOSS 旁 → 触发觉醒卡
	_level._player.global_position = boss.global_position - Vector2(70.0, 0.0)
	await _frames(4)
	# 等 1.05s 真实时间：立绘淡入完成（0.92s 结束）、BOSS 名与阶段提示打出中
	# ⚠️ 不能靠 process_frame 计数——渲染帧率 ~115fps，60 帧只有 0.52s 真实时间。
	var t0 := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t0 < 1.45:
		_keep_player_alive(_level)
		await get_tree().process_frame
	var art_node: Control = null
	var card = _level._awaken_card
	if card != null and is_instance_valid(card):
		var ui = card.get_node_or_null("UIContainer")
		art_node = ui.get_node_or_null("AwakenArt") if ui != null else null
	print("[Capture] 立绘 alpha=%.2f（截图时机）" % (art_node.modulate.a if art_node != null else -1.0))
	await _shot("BOSS觉醒立绘卡_骨暴君_2026-09-23.png")

	# 再等卡片结束（真实时间上限 4s），验证 BOSS 解冻开战
	var t1 := Time.get_ticks_msec() / 1000.0
	while _level._awaken_card != null and Time.get_ticks_msec() / 1000.0 - t1 < 4.0:
		_keep_player_alive(_level)
		await get_tree().process_frame
	_ok("觉醒卡已回收且 BOSS 解冻开战",
		_level._awaken_card == null and boss.is_physics_processing())

	_level.queue_free()
	await _frames(4)
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


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
