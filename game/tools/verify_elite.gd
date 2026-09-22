## 精英判定口径 + kill_elite 目标可达性验证
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_elite.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 背景（2026-09-20 修复）：
##   代码里曾有两套「什么算精英」的口径 ——
##     · 击杀计数 `LevelScene._on_unit_died()` 看 `lv_kind == "elite"`（只有生成器锚点 /
##       `elite_ratio` 随机提升才会打这个标记）；
##     · 掉落质量统计 `LevelScene._count_rare_drops()` 看 `data.tier`。
##   于是**数据层就是精英档**的怪（`brute_butcher` 屠夫 / `wraith_frost` 霜缚幽魂 /
##   `pyromancer_cultist` / `ice_wraith`）被杀时不算精英击杀。实测：ch2_l10 场上有
##   12 只精英档怪，其中 8 只没被标记；ch2_l13 有 10 只，其中 9 只没被标记。
##   玩家视角 = 「我打死了屠夫，任务计数器不动」。
##
## 本脚本守住三件事：
##   A. 7 个 kill_elite 关的 `elite_count` 与生成器锚点都 ≥ `objective_value`
##   B. 口径统一：场上不存在「数据层是精英档但没被标记」的怪；
##      `_elite_total` == 场上 `_is_elite()` 为真的只数；且 ≥ `objective_value`
##   C. 击杀计数行为：杀掉 `objective_value` 个精英（**优先挑数据层精英档的**，
##      因为它们在旧代码里正好是不计入的那批）→ `_elite_kills` 达标且
##      `_objective_done()` 为真（不是软锁）
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")

## 每关只等这么多帧就去读计数 —— 必须**远小于** `LevelScene.GUARANTEE_PICKUP_GRACE`
## （0.6s）。目标达成会触发 `_check_objective_and_settle()` → 0.6s 后 `_finish_run()`
## → `SceneManager` 换场景 → **本验证脚本自身会被释放**，进程静默退出且不打结果行。
## 所以读完立刻 `queue_free()` 掉关卡。
const SAFE_FRAMES := 3

var _fail: int = 0
var _levels: Array[LevelData] = []


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 120.0)
	print("===== 精英判定口径 + kill_elite 可达性验证 =====")
	await _run()
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _run() -> void:
	_collect_levels()
	_check_static()
	await _check_scenes()


func _collect_levels() -> void:
	for lv in ConfigLoader.get_levels_sorted():
		if lv.objective_type == LevelData.ObjectiveType.KILL_ELITE:
			_levels.append(lv)
	print("[Info] kill_elite 关共 %d 个：%s"
		% [_levels.size(), str(_level_ids())])


func _level_ids() -> Array:
	var out: Array = []
	for lv in _levels:
		out.append(lv.id)
	return out


# =============================================================================
# A. 静态：数据层就保证了锚点够用
# =============================================================================

func _check_static() -> void:
	_ok("存在 kill_elite 关（数据没被改光）", _levels.size() > 0)

	var short_anchors: Array[String] = []
	var short_count: Array[String] = []
	for lv in _levels:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(lv.layout.get("seed", 0))
		var layout := LevelGenerator.generate(lv, rng)
		var anchors: int = (layout.get("elite_spawns", []) as Array).size()
		if anchors < int(lv.objective_value):
			short_anchors.append("%s 锚点%d<%d" % [lv.id, anchors, int(lv.objective_value)])
		if lv.elite_count < int(lv.objective_value):
			short_count.append("%s elite_count%d<%d"
				% [lv.id, lv.elite_count, int(lv.objective_value)])
	_ok("每个 kill_elite 关的生成器锚点数 ≥ objective_value（不足：%s）"
		% str(short_anchors), short_anchors.is_empty())
	_ok("每个 kill_elite 关的 elite_count ≥ objective_value（不足：%s）"
		% str(short_count), short_count.is_empty())


# =============================================================================
# B / C. 场景层
# =============================================================================

func _check_scenes() -> void:
	for lv in _levels:
		await _check_one(lv)


func _check_one(lv: LevelData) -> void:
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": lv.id,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	# 冻住 AI：本用例不该被围殴打断（也避免玩家在等待期间被打死触发换场景）
	_freeze(level)
	await _frames(SAFE_FRAMES)

	var need := int(lv.objective_value)

	# ---------- B. 口径统一 ----------
	var unmarked_tier_elites: Array[String] = []
	var counted := 0
	var tier_elites: Array[EnemyBase] = []
	for e in level._alive:
		if not is_instance_valid(e):
			continue
		var marked: bool = str(e.get_meta("lv_kind", "")) == "elite"
		var tier_elite: bool = e.data != null \
			and int(e.data.tier) == int(MonsterData.Tier.ELITE)
		if tier_elite:
			tier_elites.append(e)
			if not marked:
				unmarked_tier_elites.append(e.monster_id)
		if level._is_elite(e):
			counted += 1

	_ok("%s：不存在「数据层精英档但没被标记」的怪（%d 只漏标：%s）"
		% [lv.id, unmarked_tier_elites.size(), str(unmarked_tier_elites)],
		unmarked_tier_elites.is_empty())
	_ok("%s：_elite_total（%d）== 场上 _is_elite() 为真的只数（%d）"
		% [lv.id, level._elite_total, counted],
		level._elite_total == counted)
	_ok("%s：_elite_total（%d）≥ 目标（%d）⇒ 目标可达"
		% [lv.id, level._elite_total, need],
		level._elite_total >= need)

	# ---------- C. 击杀计数 ----------
	# 优先挑「数据层精英档」的怪：它们在旧代码里正好是杀了不计入的那批。
	var victims: Array[EnemyBase] = []
	for e in tier_elites:
		if victims.size() >= need:
			break
		victims.append(e)
	for e in level._alive:
		if victims.size() >= need:
			break
		if is_instance_valid(e) and level._is_elite(e) and not victims.has(e):
			victims.append(e)

	var before := level._elite_kills
	var killed := 0
	for e in victims:
		if is_instance_valid(e):
			e.health.take_damage(999999.0, level._player)
			killed += 1
	await _frames(SAFE_FRAMES)
	var after := level._elite_kills

	_ok("%s：杀了 %d 个精英（其中数据层精英档 %d 个）→ _elite_kills %d→%d，恰好 +%d"
		% [lv.id, killed, mini(tier_elites.size(), need), before, after, killed],
		killed > 0 and after == before + killed)
	_ok("%s：达成 %d 个精英击杀后 _objective_done() 为真（不是软锁）" % [lv.id, need],
		after >= need and level._objective_done())

	level.queue_free()
	await _frames(SAFE_FRAMES)


func _freeze(level: LevelScene) -> void:
	for e in level._alive:
		if is_instance_valid(e):
			e.set_physics_process(false)
			e.set_process(false)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
