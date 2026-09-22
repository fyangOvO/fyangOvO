## 战斗指标采集验证（任务 11.9 · AoE 实测埋点）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_metrics.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 背景：
##   20 关 `total_monster_budget` 是 POC 值（单局 ≈3–5 分钟，D5 下限 14 分钟的 1/3），
##   回填卡在「AoE 未实测」上（`sim-report §10.5.7` 自承）。测 AoE 最快的路径是
##   让用户试玩 ⇒ 本轮只做**埋点**。本脚本守住埋点本身是对的。
##
## ⚠️ **本脚本不驱动真实关卡跑完**：目标达成会触发 `_check_objective_and_settle()`
##    → `_finish_run()` → `SceneManager` 换场景 → **本验证脚本自身被释放**，
##    进程静默退出且不打结果行（`verify_elite.gd` 头部记录了同一个坑）。
##    所以这里用**静态 API 直接驱动**，全部确定性；只在最后做一次「关卡开局后
##    采集器确实活着」的轻量集成断言，读到就 `queue_free()`。
##
## 守住九件事：
##   A. `begin_run` 重置全部本局状态（不串上一局的数）
##   B. 施放计数：命中数 / **放空(whiff)** / 单次最大命中 / AoE 分类
##   C. AoE 采样逐条落库 —— 这是回填要的 `AoE(密度)` 曲线的原始数据
##   D. 击杀分类（normal / elite / boss）
##   E. 交火切分：静默 > gap 断成两段，< gap 合并成一段
##   F. 派生指标数学自洽
##   G. JSONL **真落盘**、可解析、schema 正确、字段齐全
##   H. 未开局时 `end_run` 返回空且**不写垃圾行**
##   I. `enabled = false` 时全部入口是 no-op
extends Node

const SAFE_FRAMES: int = 3

## 测试用的交火间隔（毫秒）。生产值是 4000 —— 真等 4 秒会让本脚本慢到没人跑。
const TEST_GAP_MS: int = 200

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 120.0)
	print("===== 战斗指标采集验证（任务 11.9 · AoE 实测埋点） =====")
	await _run()
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _run() -> void:
	await _check_reset()
	await _check_cast_accounting()
	_check_kills()
	await _check_engagement()
	# ⚠️ 必须 await：本函数里有 `await _wait_ms()`，不 await 的话它会**挂起后继续**
	# —— 于是它的 `end_run()` 会在**后面某个用例的中途**把采集器关掉，
	# 表现为「J 段刚开的局，快照却是空的」（实测踩到，且极难看出来）。
	await _check_derived()
	await _check_persistence()
	await _check_inactive_no_write()
	await _check_disabled()
	await _check_level_integration()
	CombatMetrics.engage_gap_ms = CombatMetrics.ENGAGE_GAP_MS
	CombatMetrics.enabled = true
	CombatMetrics.reset()


# =============================================================================
# A. begin_run 重置
# =============================================================================

func _check_reset() -> void:
	# 先弄脏状态，再开新局 —— 断言的是「开新局会把脏状态清掉」
	CombatMetrics.begin_run("stale_level", 3, 999, 42)
	CombatMetrics.note_kill("boss")
	CombatMetrics.begin_cast("x", true)
	CombatMetrics.note_skill_hit()
	CombatMetrics.end_cast()
	_ok("A. 弄脏：脏局确实记下了 1 个 boss 击杀与 1 条 AoE 采样",
		int(CombatMetrics.snapshot()["kills"]) == 1
		and CombatMetrics._aoe_samples.size() == 1)

	CombatMetrics.begin_run("second", 0, 10, 5)
	var snap := CombatMetrics.snapshot()
	_ok("A. begin_run 重置：换一局后 level_id 已更新（%s）" % str(snap["level_id"]),
		snap["level_id"] == "second")
	_ok("A. begin_run 重置：击杀数清零（上一局的 boss 不串进来）",
		int(snap["kills"]) == 0)
	_ok("A. begin_run 重置：技能表清空", CombatMetrics._skills.is_empty())
	_ok("A. begin_run 重置：AoE 采样清空", CombatMetrics._aoe_samples.is_empty())
	_ok("A. begin_run 重置：存活数被新局的 spawned 覆盖",
		int(CombatMetrics._alive) == 5)
	CombatMetrics.reset()


# =============================================================================
# B. 施放计数
# =============================================================================

func _check_cast_accounting() -> void:
	CombatMetrics.begin_run("cast_test", 0, 0, 12)
	# 单体命中 1
	CombatMetrics.begin_cast("cleave", false)
	CombatMetrics.note_skill_hit()
	CombatMetrics.end_cast()
	# AoE 命中 3（密度 7）
	CombatMetrics.set_alive_count(7)
	CombatMetrics.begin_cast("whirl", true)
	for _i in 3:
		CombatMetrics.note_skill_hit()
	CombatMetrics.end_cast()
	# AoE 放空（密度 2）
	CombatMetrics.set_alive_count(2)
	CombatMetrics.begin_cast("whirl", true)
	CombatMetrics.end_cast()

	var rec := CombatMetrics.end_run(true, false)   # 只算不写：让指标文件里只留 G 段那一行测试记录
	var sk: Dictionary = rec["skills"]
	_ok("B. 单体技能命中 1：casts=1 hits=1 whiffs=0 max=1",
		int(sk["cleave"]["casts"]) == 1 and int(sk["cleave"]["hits"]) == 1
		and int(sk["cleave"]["whiffs"]) == 0 and int(sk["cleave"]["max_hits"]) == 1)
	_ok("B. 单体技能不计为 AoE", not bool(sk["cleave"]["aoe"]))
	_ok("B. AoE 两次施放共命中 3：casts=2 hits=3 max=3",
		int(sk["whirl"]["casts"]) == 2 and int(sk["whirl"]["hits"]) == 3
		and int(sk["whirl"]["max_hits"]) == 3)
	_ok("B. **放空被单独记成 whiff=1**（丢了它就分不清「命中高」和「一半打空」）",
		int(sk["whirl"]["whiffs"]) == 1)
	_ok("B. AoE 分类正确", bool(sk["whirl"]["aoe"]))
	_ok("B. hits_per_cast = 3/2 = 1.5", absf(float(sk["whirl"]["hits_per_cast"]) - 1.5) < 0.001)
	_ok("B. aoe_hits_per_cast 只统计 AoE 技能 = 1.5",
		absf(float(rec["aoe_hits_per_cast"]) - 1.5) < 0.001)
	_ok("B. 非 AoE 技能不污染 aoe_hits（aoe_casts=2）", int(rec["aoe_casts"]) == 2)

	# C. AoE 采样
	var s: Array = rec["aoe_samples"]
	_ok("C. AoE 采样逐条落库（2 条）", s.size() == 2)
	_ok("C. 采样内容 = [(密度 7, 命中 3), (密度 2, 命中 0)]",
		s.size() == 2 and s[0][0] == 7 and s[0][1] == 3 and s[1][0] == 2 and s[1][1] == 0)
	CombatMetrics.reset()


# =============================================================================
# D. 击杀分类
# =============================================================================

func _check_kills() -> void:
	CombatMetrics.begin_run("kill_test", 0, 0, 10)
	CombatMetrics.note_kill("normal")
	CombatMetrics.note_kill("normal")
	CombatMetrics.note_kill("normal")
	CombatMetrics.note_kill("elite")
	CombatMetrics.note_kill("elite")
	CombatMetrics.note_kill("boss")
	var rec := CombatMetrics.end_run(false, false)   # 只算不写（本段只验数学）
	_ok("D. 击杀总数 6", int(rec["kills"]) == 6)
	_ok("D. 分类计数 normal=3 / elite=2 / boss=1",
		int(rec["kills_normal"]) == 3 and int(rec["kills_elite"]) == 2
		and int(rec["kills_boss"]) == 1)
	CombatMetrics.reset()


# =============================================================================
# E. 交火切分
# =============================================================================

func _check_engagement() -> void:
	# gap 取 200ms（生产是 4000ms）：比「段内间隔 30ms」大一个量级，
	# 这样即使某一帧卡到 100ms 也不会把同一段交火误判成两段。
	# 反过来说，用 40ms 这种贴着脸的阈值会让本用例随帧率随机变红。
	CombatMetrics.engage_gap_ms = TEST_GAP_MS
	CombatMetrics.begin_run("engage_test", 0, 0, 10)

	# 段内输出：间隔 30ms < gap ⇒ 同一段交火
	CombatMetrics.note_outgoing_damage()
	await _wait_ms(30)
	CombatMetrics.note_outgoing_damage()
	await _wait_ms(30)
	CombatMetrics.note_outgoing_damage()
	var one := CombatMetrics.snapshot()
	_ok("E. 段内间隔 30ms（< gap %dms）的三次输出归并为**一段**交火（engagements=%d，期望 1）"
		% [CombatMetrics.engage_gap_ms, int(one["engagements"])],
		int(one["engagements"]) == 1)
	_ok("E. 交火时长 = 首末次输出之差（%.3fs，应 > 0）" % float(one["combat_s"]),
		float(one["combat_s"]) > 0.0)

	# 静默超过 gap → 断成新的一段
	var t0 := Time.get_ticks_msec()
	await _wait_ms(500)
	var waited := Time.get_ticks_msec() - t0
	CombatMetrics.note_outgoing_damage()
	var two := CombatMetrics.snapshot()
	_ok("E. 静默 %dms（> gap %dms）后再输出 → 断成第二段（engagements=%d，期望 2）"
		% [waited, CombatMetrics.engage_gap_ms, int(two["engagements"])],
		int(two["engagements"]) == 2)
	_ok("E. 断段后交火时长继续累计（%.3fs）" % float(two["combat_s"]),
		float(two["combat_s"]) >= float(one["combat_s"]))

	# 静默期内不应自己冒出新交火
	await _wait_ms(500)
	_ok("E. 静默期不产生新交火（engagements 仍为 %d）"
		% int(CombatMetrics.snapshot()["engagements"]),
		int(CombatMetrics.snapshot()["engagements"]) == 2)
	CombatMetrics.reset()


# =============================================================================
# F. 派生指标
# =============================================================================

func _check_derived() -> void:
	CombatMetrics.begin_run("derived_test", 2, 40, 41)
	# 先开一段交火，再真等一会儿 —— 否则整段落在同一毫秒里，
	# `combat_s` 会是 0，`kills_per_combat_min` 直接返回 0（不是除零，是「没有时长」）。
	# 这也是本类刻意的语义：**交火时长 = 首末次输出的差**，不含后面那段静默尾巴，
	# 否则「打完站着不动」的时间会被算进交火，把清怪效率虚高。
	CombatMetrics.note_outgoing_damage()
	await _wait_ms(50)
	for _i in 6:
		CombatMetrics.note_kill("normal")
		CombatMetrics.note_outgoing_damage()
	var rec := CombatMetrics.end_run(true, false)
	var kills := int(rec["kills"])
	var eng := int(rec["engagements"])
	_ok("F. kills_per_engagement = kills / engagements",
		eng > 0 and absf(float(rec["kills_per_engagement"]) - float(kills) / float(eng)) < 0.02)
	_ok("F. kills_per_combat_min ≥ kills_per_min（交火时长 ≤ 总时长）",
		float(rec["kills_per_combat_min"]) >= float(rec["kills_per_min"]))
	_ok("F. duration_s > 0 且 combat_s ≤ duration_s",
		float(rec["duration_s"]) > 0.0
		and float(rec["combat_s"]) <= float(rec["duration_s"]) + 0.05)
	_ok("F. 无 AoE 施放时 aoe_hits_per_cast = 0（不是除零 NaN）",
		absf(float(rec["aoe_hits_per_cast"])) < 0.001)
	_ok("F. monster_budget / spawned 原样带出",
		int(rec["monster_budget"]) == 40 and int(rec["spawned"]) == 41)
	CombatMetrics.reset()


# =============================================================================
# G / H. 落盘
# =============================================================================

func _check_persistence() -> void:
	var before := _line_count()
	CombatMetrics.begin_run("persist_test", 1, 55, 55)
	CombatMetrics.set_alive_count(9)
	CombatMetrics.begin_cast("frost_nova", true)
	for _i in 4:
		CombatMetrics.note_skill_hit()
	CombatMetrics.end_cast()
	CombatMetrics.note_kill("elite")
	CombatMetrics.note_outgoing_damage()
	CombatMetrics.end_run(true)

	var after := _line_count()
	_ok("G. 每局**追加**一行 JSONL（%d → %d）" % [before, after], after == before + 1)

	var line := _last_line()
	var parsed: Variant = JSON.parse_string(line)
	_ok("G. 最后一行是**合法 JSON**", parsed is Dictionary)
	if parsed is Dictionary:
		var d: Dictionary = parsed
		_ok("G. schema = %d" % CombatMetrics.SCHEMA, int(d.get("schema", -1)) == CombatMetrics.SCHEMA)
		_ok("G. level_id 正确", str(d.get("level_id", "")) == "persist_test")
		var need := ["duration_s", "combat_s", "kills", "engagements", "skills",
			"aoe_casts", "aoe_hits", "aoe_hits_per_cast", "aoe_samples",
			"kills_per_min", "kills_per_combat_min", "kills_per_engagement",
			"monster_budget", "spawned", "completed"]
		var missing: Array[String] = []
		for k in need:
			if not d.has(k):
				missing.append(k)
		_ok("G. 字段齐全（缺：%s）" % str(missing), missing.is_empty())
		_ok("G. AoE 采样也落进了文件", (d.get("aoe_samples", []) as Array).size() == 1)
	_ok("G. 日志绝对路径可给用户（不是相对路径）",
		CombatMetrics.log_absolute_path().is_absolute_path())
	CombatMetrics.reset()


func _check_inactive_no_write() -> void:
	CombatMetrics.reset()
	var before := _line_count()
	var rec := CombatMetrics.end_run(true)
	var after := _line_count()
	_ok("H. 未开局时 end_run 返回空字典", rec.is_empty())
	_ok("H. 未开局时 end_run **不写文件**（%d → %d）" % [before, after], after == before)
	_ok("H. is_active() 为 false", not CombatMetrics.is_active())


# =============================================================================
# I. 总开关
# =============================================================================

func _check_disabled() -> void:
	var before := _line_count()
	CombatMetrics.enabled = false
	CombatMetrics.begin_run("disabled_test", 0, 0, 5)
	CombatMetrics.note_kill("boss")
	CombatMetrics.begin_cast("whirl", true)
	CombatMetrics.note_skill_hit()
	CombatMetrics.end_cast()
	CombatMetrics.note_outgoing_damage()
	var rec := CombatMetrics.end_run(true)
	CombatMetrics.enabled = true
	_ok("I. enabled=false 时 begin_run 不激活", not CombatMetrics.is_active())
	_ok("I. enabled=false 时 end_run 返回空", rec.is_empty())
	_ok("I. enabled=false 时不写文件（%d → %d）" % [before, _line_count()],
		_line_count() == before)


# =============================================================================
# 轻量集成：真实关卡开局后采集器确实活着
# =============================================================================

func _check_level_integration() -> void:
	CombatMetrics.reset()
	var lv: LevelData = ConfigLoader.get_level("ch1_l01")
	if lv == null:
		_ok("J. 取到 ch1_l01 用于集成断言", false)
		return
	var level := (preload("res://scenes/levels/level.tscn") as PackedScene).instantiate() as LevelScene
	# ⚠️ 顺序不能反：`add_child` 会**同步**触发 `_ready()`，而关卡要靠
	# `on_scene_entered(payload)` 才真正建场 —— 先设字段再 add_child 是无效的。
	# 挂到 `root` 而不是自己身上（同 `verify_elite.gd` 的写法）。
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": lv.id,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	_freeze(level)
	await _frames(SAFE_FRAMES)

	_ok("J. 进关卡后采集器已激活", CombatMetrics.is_active())
	var snap := CombatMetrics.snapshot()
	_ok("J. 快照 level_id 与关卡一致（%s）" % str(snap["level_id"]),
		str(snap["level_id"]) == lv.id)
	_ok("J. 快照记下实际刷怪数（spawned=%d，应 > 0）" % int(snap["spawned"]),
		int(snap["spawned"]) > 0)
	_ok("J. 快照记下设计预算（monster_budget=%d）"
		% int(snap["monster_budget"]), int(snap["monster_budget"]) == int(lv.total_monster_budget))

	# 不触发结算（会换场景、把自己 free 掉）：冻住 AI 后直接拆
	level.queue_free()
	await _frames(SAFE_FRAMES)
	CombatMetrics.reset()


## 冻住敌人 AI：本用例只验「采集器活着」，不该被围殴打断
## （也避免玩家被打死在等待期间触发 `_finish_run` → 换场景 → 本脚本被释放）。
func _freeze(level: LevelScene) -> void:
	for e in level._alive:
		if is_instance_valid(e):
			e.set_physics_process(false)
			e.set_process(false)


# =============================================================================
# 工具
# =============================================================================

func _line_count() -> int:
	if not FileAccess.file_exists(CombatMetrics.LOG_FILE):
		return 0
	var f := FileAccess.open(CombatMetrics.LOG_FILE, FileAccess.READ)
	if f == null:
		return 0
	var n := 0
	while not f.eof_reached():
		if not f.get_line().strip_edges().is_empty():
			n += 1
	f.close()
	return n


func _last_line() -> String:
	if not FileAccess.file_exists(CombatMetrics.LOG_FILE):
		return ""
	var f := FileAccess.open(CombatMetrics.LOG_FILE, FileAccess.READ)
	if f == null:
		return ""
	var last := ""
	while not f.eof_reached():
		var l := f.get_line()
		if not l.strip_edges().is_empty():
			last = l
	f.close()
	return last


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## 等**真实墙钟**毫秒数。
##
## ⚠️ **不要用 `create_timer` 做这种事**：实测无头下在 `_ready` 里创建的短定时器
## 会在下一帧**立刻**触发 —— 首帧 delta 含启动 / 场景加载耗时，一次就吃掉了整个时长。
## 实测对照：`create_timer(0.08)` 实际等了 **0ms**，而 `create_timer(0.5)` 正常等 490ms。
## 按 `Time.get_ticks_msec()` 轮询没有这个问题，也不受帧率 / delta 异常影响。
func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
