## `survive` / `reach_exit` 两种目标（W5-7）+ 关卡目标再平衡 实测
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_objectives.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 为什么单独一个脚本：
##   1. `verify_level_gen` 的 G 段只看**数据与生成器**，证明不了「计时器真的在跑、
##      出口精灵真的摆出来了、走上去真的会结算」；
##   2. `verify_collect` / `verify_elite` 各只覆盖一种目标；
##   3. W5-7 之前 `survive` / `reach_exit` 是**降级为 clear_all** 的，属「数据写了、
##      玩法没实现」——本项目头号反模式。本脚本把它钉死。
##
## 覆盖（8 段）：
##   A. 关卡指派：20 关目标分布 == `05-levels.json levels_target`（6 种全用）
##   B. `survive` 进关：kind / target（秒）/ 文案 / HUD
##   C. `survive` 计时器：`_process` 真的在累加 + HUD 进度按整秒走
##   D. `survive` 刷怪波：期间真的会刷怪（否则「站着不动也能过」）
##   E. `survive` 到点判定（纯逻辑，不触发结算 ⇒ 不会被 SceneManager 换场景）
##   F. `reach_exit` 进关：出口落点 = 距出生点最远的地面格 + 可视精灵已生成
##   G. `reach_exit` 不因击杀误判（`_sync_objective_counter` 必须显式留空）
##   H. 降级保护：没有地面格可放出口 ⇒ 真的降级 + push_warning
##   I. `reach_exit` 距离触碰到场（最后一段：会触发结算，故排在最后）
##
## ⚠️ 为什么 I 段必须排最后：目标达成 → `_check_objective_and_settle()` →
##    0.6s 后 `_finish_run()` → `SceneManager` 换场景 → **本脚本自身被释放**，
##    进程会静默退出且不打结果行（`verify_elite` 已踩过这个坑）。
##    所以 I 段只断言到 `_settling` 为止，随即 `_finish()` 退出。
extends Node

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const SURVIVE_LEVEL: String = "ch2_l08"
const EXIT_LEVEL: String = "ch1_l04"

var _fail: int = 0
## 段完成标记：防「协程中 SCRIPT ERROR 静默跳段、_fail 仍 0」的伪绿（IRON-RULES ⑱）
const SECTIONS: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H", "I"]
var _sections_done: Array[String] = []

var _level: LevelScene = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== survive / reach_exit 目标实测（W5-7） =====")
	await _test_assignment()
	await _test_survive()
	await _test_exit()
	_finish()


# =============================================================================
# A. 关卡指派
# =============================================================================

func _test_assignment() -> void:
	print("--- A. 20 关目标分布 ---")
	var dist := {}
	var secs := {}
	var exit_ids: Array[String] = []
	for lv in ConfigLoader.get_levels_sorted():
		var key := LevelData.OBJECTIVE_KEYS[lv.objective_type]
		dist[key] = int(dist.get(key, 0)) + 1
		if lv.objective_type == LevelData.ObjectiveType.SURVIVE:
			secs[lv.id] = int(lv.objective_value)
		elif lv.objective_type == LevelData.ObjectiveType.REACH_EXIT:
			exit_ids.append(lv.id)
	print("    分布：%s" % str(dist))
	print("    survive 秒数：%s" % str(secs))
	print("    reach_exit 关：%s" % str(exit_ids))

	var want := {
		"clear_all": 5, "kill_elite": 4, "kill_boss": 3,
		"survive": 3, "collect": 3, "reach_exit": 2,
	}
	_ok("目标分布 == 05-levels.json levels_target（实际 %s）" % str(dist), dist == want)
	_ok("6 种目标全部被至少一关使用（实际 %d 种）" % dist.size(), dist.size() == 6)
	_ok("survive 秒数 = ch2_l08:90 / ch2_l11:105 / ch3_l17:120（实际 %s）" % str(secs),
		secs == {"ch2_l08": 90, "ch2_l11": 105, "ch3_l17": 120})
	_ok("reach_exit = ch1_l04 / ch3_l15（实际 %s）" % str(exit_ids),
		exit_ids == ["ch1_l04", "ch3_l15"])
	_sections_done.append("A")


# =============================================================================
# B/C/D/E. survive
# =============================================================================

func _test_survive() -> void:
	print("--- B. survive 进关 ---")
	_level = LEVEL_SCENE.instantiate() as LevelScene
	# ⚠️ 必须 call_deferred：`_ready()` 期间 root 正在 setup children，
	#    直接 add_child 会报 "Parent node is busy setting up children" 并静默失败。
	get_tree().root.add_child.call_deferred(_level)
	await _wait_frames(2)
	_level.on_scene_entered({
		"level_id": SURVIVE_LEVEL,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _wait_frames(3)

	var def: LevelData = ConfigLoader.get_level(SURVIVE_LEVEL)
	_ok("进关成功（玩家 / 关卡定义就绪）", _level._player != null and def != null)
	if _level._player == null or def == null:
		_sections_done.append_array(["B", "C", "D", "E"])
		return
	# 顶血：本测试不打怪，但怪会一直攻击玩家（与目标逻辑无关）
	_level._player.health.max_hp_override = 1.0e9
	_level._player.health.current_hp = 1.0e9

	_ok("_objective_kind == SURVIVE", _level._objective_kind == LevelData.ObjectiveType.SURVIVE)
	_ok("_objective_target == %d（秒，来自 objective_value）" % int(def.objective_value),
		_level._objective_target == int(def.objective_value))
	_ok("文案为「存活 %d 秒」（实际「%s」）" % [_level._objective_target, _level._objective_desc],
		_level._objective_desc == "存活 %d 秒" % _level._objective_target)
	_ok("HUD 标签已刷新（「%s」）" % _level._objective_label.text,
		_level._objective_label.text.begins_with("存活"))
	_sections_done.append("B")

	print("--- C. survive 计时器 ---")
	var t0: float = _level._survive_elapsed
	# ⚠️ 用**真实时间**等而不是等帧数：headless 下 `_process` 不受 vsync 限制，
	#    「120 帧」可能只有几十毫秒，靠帧数等计时器会假失败。
	await get_tree().create_timer(0.3).timeout
	_ok("`_process` 真的在累加 `_survive_elapsed`（%.2f → %.2f）"
			% [t0, _level._survive_elapsed], _level._survive_elapsed > t0 + 0.1)
	_ok("HUD 进度 = 整数秒（current %d / target %d）"
			% [_level._objective_current, _level._objective_target],
		_level._objective_current == int(_level._survive_elapsed))
	_sections_done.append("C")

	print("--- D. survive 刷怪波 ---")
	var alive_before: int = _level._alive.size()
	_level._survive_wave_timer = 0.001
	if not await _wait_until(func() -> bool: return _level._alive.size() > alive_before, 180):
		_ok("存活期间会持续刷怪（否则「站着不动也能过」）", false)
	else:
		_ok("存活期间会持续刷怪（场上 %d → %d）"
				% [alive_before, _level._alive.size()], true)
		_ok("刷怪波计时器被重置为 %.0fs" % LevelScene.SURVIVE_WAVE_INTERVAL,
			absf(_level._survive_wave_timer - LevelScene.SURVIVE_WAVE_INTERVAL) < 0.01)
	_sections_done.append("D")

	print("--- E. survive 到点判定（纯逻辑，不触发结算）---")
	_level._survive_elapsed = float(_level._objective_target) - 1.0
	_ok("差 1 秒时未达成", not _level._objective_done())
	_level._survive_elapsed = float(_level._objective_target)
	_ok("到点即达成 `_objective_done()`", _level._objective_done())
	_level._survive_elapsed = 0.0
	_sections_done.append("E")

	_level.queue_free()
	_level = null
	await _wait_frames(3)


# =============================================================================
# F/G/H/I. reach_exit
# =============================================================================

func _test_exit() -> void:
	print("--- F. reach_exit 进关 + 出口布置 ---")
	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _wait_frames(2)
	_level.on_scene_entered({
		"level_id": EXIT_LEVEL,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _wait_frames(3)

	var def: LevelData = ConfigLoader.get_level(EXIT_LEVEL)
	_ok("进关成功（玩家 / 关卡定义就绪）", _level._player != null and def != null)
	if _level._player == null or def == null:
		_sections_done.append_array(["F", "G", "H", "I"])
		return
	_level._player.health.max_hp_override = 1.0e9
	_level._player.health.current_hp = 1.0e9

	_ok("_objective_kind == REACH_EXIT",
		_level._objective_kind == LevelData.ObjectiveType.REACH_EXIT)
	_ok("_objective_target == 1（固定一个出口）", _level._objective_target == 1)
	_ok("文案为「抵达出口」（实际「%s」）" % _level._objective_desc,
		_level._objective_desc == "抵达出口")
	_ok("出口世界坐标已布置（%s）" % str(_level._exit_pos), _level._exit_pos != Vector2.INF)
	_ok("出口可视精灵已生成（`%s` loop 精灵）" % LevelScene.EXIT_FX_ID,
		_level._exit_portal != null and is_instance_valid(_level._exit_portal))

	# 落点核验：必须是距出生点最远的地面格
	var cells: Dictionary = _level._layout.get("cells", {})
	var spawn_cell: Vector2i = _level._layout.get("player_spawn", Vector2i(-1, -1))
	var exit_cell := Vector2i(int(_level._exit_pos.x) / LevelScene.TILE_PX,
		int(_level._exit_pos.y) / LevelScene.TILE_PX)
	_ok("出口落在**地面格**上（格 %s）" % str(exit_cell),
		int(cells.get(exit_cell, -1)) == LevelGenerator.TILE_GROUND)
	_ok("出口不在出生格上", exit_cell != spawn_cell)
	var best := -1.0
	var far := Vector2i(-1, -1)
	for c in cells.keys():
		if int(cells[c]) != LevelGenerator.TILE_GROUND or c == spawn_cell:
			continue
		var d := Vector2(c).distance_squared_to(Vector2(spawn_cell))
		if d > best:
			best = d
			far = c
	_ok("出口 == 距出生点最远的地面格（期望 %s / 实际 %s）" % [str(far), str(exit_cell)],
		exit_cell == far)
	_sections_done.append("F")

	print("--- G. reach_exit 不因击杀误判 ---")
	var kills_before: int = _level._kills
	_level._kills = kills_before + 5
	_level._sync_objective_counter()
	_ok("击杀 5 只后 `_objective_current` 仍为 0（没落到 `_:` 把 `_kills` 写进去）",
		_level._objective_current == 0)
	_ok("击杀 5 只后未达成目标", not _level._objective_done())
	_level._kills = kills_before
	_level._sync_objective_counter()
	_sections_done.append("G")

	print("--- H. 降级保护 ---")
	# 造一个「没有任何地面格」的残缺布局，直接打 `_spawn_exit_portal()`
	var saved_layout: Dictionary = _level._layout
	var saved_kind: int = _level._objective_kind
	var saved_target: int = _level._objective_target
	var saved_exit: Vector2 = _level._exit_pos
	_level._objective_kind = LevelData.ObjectiveType.REACH_EXIT
	_level._layout = {"cells": {}, "player_spawn": Vector2i(0, 0)}
	_level._exit_pos = Vector2.INF
	_level._spawn_exit_portal()
	_ok("无地面格可放出口 ⇒ 真的降级为 CLEAR_ALL（不是只改文案）",
		_level._objective_kind == LevelData.ObjectiveType.CLEAR_ALL)
	_level._layout = saved_layout
	_level._objective_kind = saved_kind
	_level._objective_target = saved_target
	_level._exit_pos = saved_exit
	_sections_done.append("H")

	print("--- I. reach_exit 距离触碰到场（会触发结算 ⇒ 排最后）---")
	_ok("触发半径 = %d px" % int(LevelScene.EXIT_TOUCH_RADIUS),
		absf(LevelScene.EXIT_TOUCH_RADIUS - 24.0) < 0.01)
	# 站到远处：不该达成
	_level._player.global_position = _level._exit_pos + Vector2(500.0, 500.0)
	_level._objective_current = 0
	_level._tick_objective_timers(0.016)
	_ok("离出口 500px 时不达成、不结算",
		_level._objective_current == 0 and not _level._settling)
	# 走到出口上：应达成并进入结算
	_level._player.global_position = _level._exit_pos
	_level._tick_objective_timers(0.016)
	_ok("站上出口即达成（current %d / target %d）"
			% [_level._objective_current, _level._objective_target],
		_level._objective_current == _level._objective_target and _level._objective_done())
	_ok("已进入结算流程（`_settling`，0.6s 后落盘）", _level._settling)
	_sections_done.append("I")


# =============================================================================
# 工具
# =============================================================================

func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		await get_tree().process_frame
		if pred.call():
			return true
	return false


func _finish() -> void:
	var missing: Array[String] = []
	for s in SECTIONS:
		if not _sections_done.has(s):
			missing.append(s)
	if not missing.is_empty():
		_fail += 1
		print("[FAIL] 测试段未跑完（缺 %s）—— 上方有 SCRIPT ERROR，结果不可信" % str(missing))
	print("===== 结果：%d 项失败（段 %d/%d）====="
		% [_fail, _sections_done.size(), SECTIONS.size()])
	get_tree().quit(0 if _fail == 0 else 1)
