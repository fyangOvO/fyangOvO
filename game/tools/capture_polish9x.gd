## 9.x 综合打磨 · 真渲染取证（开发用，不属于游戏玩法）
##
## 用法（**必须去掉 --headless**）：
##   godot --path "D:/七傳說/game" res://tools/capture_polish9x.tscn
##
## 产出（deliverables/）：
##   `手感打磨_BOSS范围技能警示_2026-09-23.png`（ch2_l13 · 熔心之主范围技能
##   telegraph：红色闪烁圆环 + BOSS 立绘 + HUD，640×360 小窗）
##   `手感打磨_近战命中反馈_2026-09-23.png`（ch1_l02 近战砍怪：飘字+火花+受击）
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables"

var _fail: int = 0
var _level: LevelScene = null


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 240.0)
	_run()


func _run() -> void:
	print("===== 9.x 综合打磨抓图（小窗 640×360）=====")
	_ok("渲染驱动不是 headless（否则抓不到画面）",
		DisplayServer.get_name() != "headless")

	# ── 场景 1：BOSS 范围技能警示（telegraph）──
	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _frames(3)
	_level.on_scene_entered({
		"level_id": "ch2_l13",
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _settle(_level)

	var boss: EnemyBase = null
	for e in _level._alive:
		if e.data != null and e.data.tier == MonsterData.Tier.BOSS:
			boss = e
			break
	_ok("场上存在 BOSS（熔心之主）", boss != null)
	if boss == null:
		_fail += 1
		_finish()
		return

	# 玩家传送到 BOSS 旁（在其攻击半径内，110px）
	_level._player.global_position = boss.global_position - Vector2(60.0, 0.0)
	await _frames(4)
	# 手动触发范围技能 → 播 telegraph（0.6s 红色圆环）
	boss._aoe_strike()
	await _frames(8)
	# 0.25s 真实时间后截图（圆环闪烁中）
	var t0 := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t0 < 0.25:
		_keep_player_alive(_level)
		await get_tree().process_frame
	var tel_count := _count_telegraphs(_level)
	_ok("地面存在 AoETelegraph 红色警示圆环（%d 个）" % tel_count, tel_count > 0)
	await _shot("手感打磨_BOSS范围技能警示_2026-09-23.png")
	# 等 telegraph 结束（0.6s）→ 命中结算
	var t1 := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t1 < 0.8:
		_keep_player_alive(_level)
		await get_tree().process_frame
	_ok("telegraph 已回收（警示结束）", _count_telegraphs(_level) == 0)

	_level.queue_free()
	await _frames(4)

	# ── 场景 2：近战命中反馈（飘字+火花+受击闪）──
	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _frames(3)
	_level.on_scene_entered({
		"level_id": "ch1_l02",
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _settle(_level)
	# 找最近敌人，传送到玩家面前并打它一拳
	var target: EnemyBase = null
	var best_d := 1e9
	for e in _level._alive:
		var d := _level._player.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			target = e
	_ok("场上存在可攻击敌人", target != null)
	if target != null:
		_level._player.global_position = target.global_position - Vector2(50.0, 0.0)
		await _frames(6)
		var dmg := _level._player.get_attack_damage()
		target.take_damage(dmg, _level._player)
		await _frames(6)
		_ok("敌人受击后处于硬直/闪白（_hitstun_timer>0）", target._hitstun_timer > 0.0)
		await _shot("手感打磨_近战命中反馈_2026-09-23.png")

	_level.queue_free()
	await _frames(4)
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _count_telegraphs(level: LevelScene) -> int:
	# telegraph 挂在 BOSS 父节点（Actors）下 → 递归全树，用内部类特有属性 _radius 探测
	var n := 0
	var stack: Array = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node2D and node.get("_radius") != null:
			n += 1
		for child in node.get_children():
			stack.append(child)
	return n


func _finish() -> void:
	_level.queue_free()
	await get_tree().process_frame
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
