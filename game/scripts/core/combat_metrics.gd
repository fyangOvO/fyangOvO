## 战斗指标采集（任务 11.9 · AoE 实测埋点 · **纯观测，不参与任何战斗计算**）
##
## ---------------------------------------------------------------------------
## 为什么需要（任务清单裁定 ②）
## ---------------------------------------------------------------------------
## 20 关的 `total_monster_budget` 现在是 demo 期 POC 值：合计 **1174** / 均值 **58.7**，
## 而 GDD v1.8 定稿是 **269/关** ⇒ **单局只有 ≈3–5 分钟，是 D5 下限 14 分钟的约 1/3**。
## 拿这版 demo 测「单局时长」**必失真**。
##
## 回填卡在一个鸡生蛋问题上：`sim-report §10.5.6` 的 269 建立在 **AoE = 2.0 设计基准**上，
## 而 §10.5.7 自承「AoE 未实测」，且 §10.5.4 说「杂兵数 ∝ AoE」。
## 测 AoE 最快的路径**就是让用户试玩这版** ⇒ 所以本任务只做**埋点**，不做回填。
##
## ---------------------------------------------------------------------------
## 采集什么（任务表原文）
## ---------------------------------------------------------------------------
##   · 每技能命中数    → `skills[id].hits_per_cast` + `max_hits`
##   · 单位时间清怪数  → `kills_per_min` / `kills_per_combat_min`
##   · 交火清怪均值    → `kills_per_engagement`
##
## 另加一项**回填真正需要的**：`aoe_samples` = 每次 AoE 施放时的 (存活敌人数, 命中数)。
## 因为「杂兵数 ∝ AoE」是**双向**的：密度决定 AoE，AoE 又决定清怪速度。
## 只给一个标量 AoE 解不了这个不动点，必须给出 **AoE(密度) 曲线**。
##
## ---------------------------------------------------------------------------
## 输出
## ---------------------------------------------------------------------------
##   `user://metrics/combat_metrics.jsonl` —— 每局一行 JSON（append，不覆盖历史）
##   聚合用 `tools/metrics_report.py`
##
## 目录刻意与 `user://logs/` 分开：`game_log.gd` 的轮转只认 `game.log` 这个名字，
## 分开放可避免将来「加了个文件把日志轮转搞乱」。
##
## ---------------------------------------------------------------------------
## 设计约束
## ---------------------------------------------------------------------------
##   · **纯观测**：不读写任何战斗数值，不改变任何判定，不参与掉落 / 结算 / 目标计数。
##   · **零节点**：静态类，**不新增 autoload**（不动 `project.godot`、不动加载顺序）。
##   · **可关闭**：`enabled = false` 时所有入口立即返回，零开销。
##   · **无消费者即缺陷**：本项目的第 1 类缺陷是「生成了但没人消费」。
##     本类的消费方是 `tools/metrics_report.py`（聚合）+ `tools/verify_metrics.gd`（断言）。
class_name CombatMetrics
extends RefCounted

## 记录格式版本。字段增删时 +1，聚合脚本据此分流。
const SCHEMA: int = 1

const LOG_DIR: String = "user://metrics"
const LOG_FILE: String = "user://metrics/combat_metrics.jsonl"

## 交火（engagement）判定：无敌输出静默超过这个时长，就算上一段交火结束。
##
## 取值依据：一次 AoE 的冷却在 4–6 秒量级、一次贴身缠斗的间隔也在这个量级，
## 而「跑到下一堆怪」通常 > 6 秒。4 秒能把「同一堆怪里的多次施放」归并为一次交火，
## 又不会把「走到下一堆」误并进来。**这是可调参数，不是物理常数。**
const ENGAGE_GAP_MS: int = 4000

## 运行时生效的阈值（初值 = `ENGAGE_GAP_MS`）。
## 独立成一个可写变量，只为让 `verify_metrics` 能把它调到毫秒级 ——
## 否则每个用例都要真等 4 秒，测试会慢到没人愿意跑。
static var engage_gap_ms: int = ENGAGE_GAP_MS

## 总开关。关掉后所有入口立即返回（供将来「关闭埋点跑性能测试」用）。
static var enabled: bool = true

# ---- 本局状态 ----
static var _active: bool = false
static var _level_id: String = ""
static var _tier: int = 0
static var _monster_budget: int = 0
static var _spawned: int = 0
static var _started_ms: int = 0

static var _kills: int = 0
static var _kills_elite: int = 0
static var _kills_boss: int = 0

## 存活敌人数（由 `LevelScene` 推送，见 `set_alive_count`）。
## 本类不认识场景树，所以不自己去查 —— 一个写入方，零耦合。
static var _alive: int = 0

## skill_id -> { casts, hits, whiffs, max_hits, aoe }
static var _skills: Dictionary = {}

## 每次 **AoE** 施放的采样：[存活敌人数, 命中数]。
## 这是回填要的 `AoE(密度)` 曲线，比任何标量都重要。
static var _aoe_samples: Array = []

# ---- 交火 ----
static var _engage_open: bool = false
static var _engage_count: int = 0
static var _engage_started_ms: int = 0
static var _last_outgoing_ms: int = 0
static var _combat_ms: int = 0

# ---- 本次施放的命中计数（`skill_controller` 在一次施放内累积） ----
static var _cast_id: String = ""
static var _cast_is_aoe: bool = false
static var _cast_hits: int = 0


# =============================================================================
# 生命周期（由 `LevelScene` 调）
# =============================================================================

## 开一局。**会重置全部本局状态**，所以漏调 `end_run` 也不会把上一局的数串进来。
static func begin_run(level_id: String, tier: int, monster_budget: int, spawned: int) -> void:
	if not enabled:
		return
	_active = true
	_level_id = level_id
	_tier = tier
	_monster_budget = monster_budget
	_spawned = spawned
	_started_ms = Time.get_ticks_msec()
	_kills = 0
	_kills_elite = 0
	_kills_boss = 0
	_alive = spawned
	_skills = {}
	_aoe_samples = []
	_engage_open = false
	_engage_count = 0
	_engage_started_ms = 0
	_last_outgoing_ms = 0
	_combat_ms = 0
	_cast_id = ""
	_cast_is_aoe = false
	_cast_hits = 0


## 收一局：算出派生指标 → **追加**一行 JSON → 返回这条记录（便于测试与 HUD 复用）。
## 未开局的调用返回空字典（不写文件），避免测试里误触发产生垃圾行。
##
## `write_log = false` 只算不写 —— 给 `verify_metrics` 断言数学用，
## 免得每个用例都往指标文件里塞一行测试数据（用户在真实 APPDATA 下手跑时尤其明显）。
static func end_run(completed: bool, write_log: bool = true) -> Dictionary:
	if not enabled or not _active:
		return {}
	_close_engagement()
	var dur_ms := maxi(1, Time.get_ticks_msec() - _started_ms)
	var rec := _build_record(completed, dur_ms)
	_active = false
	if not write_log:
		return rec
	_append_line(rec)
	print("[CombatMetrics] %s tier=%d：%.1f 分钟 / %d 杀 / %d 次交火 / "
		% [rec["level_id"], rec["tier"], float(rec["duration_s"]) / 60.0,
			int(rec["kills"]), int(rec["engagements"])]
		+ "AoE %.2f 命中每施放 → %s"
		% [float(rec["aoe_hits_per_cast"]), log_absolute_path()])
	return rec


## 手动重置（测试用；也用于「中途放弃且不写记录」的场景）。
static func reset() -> void:
	_active = false
	_level_id = ""
	_tier = 0
	_monster_budget = 0
	_spawned = 0
	_started_ms = 0
	_kills = 0
	_kills_elite = 0
	_kills_boss = 0
	_alive = 0
	_skills = {}
	_aoe_samples = []
	_engage_open = false
	_engage_count = 0
	_engage_started_ms = 0
	_last_outgoing_ms = 0
	_combat_ms = 0
	_cast_id = ""
	_cast_is_aoe = false
	_cast_hits = 0


static func is_active() -> bool:
	return _active


# =============================================================================
# 采集入口
# =============================================================================

## 存活敌人数变化（`LevelScene` 在 `_alive` 变动时推送）。
static func set_alive_count(n: int) -> void:
	if not enabled or not _active:
		return
	_alive = maxi(0, n)


## 一次技能施放开始（`SkillController.use_skill` 调）。随后每次 `note_skill_hit()` 累加。
static func begin_cast(skill_id: String, is_aoe: bool) -> void:
	if not enabled or not _active:
		return
	_cast_id = skill_id
	_cast_is_aoe = is_aoe
	_cast_hits = 0


## 本次施放命中了一个目标（`SkillController._hit` 调）。
static func note_skill_hit() -> void:
	if not enabled or not _active or _cast_id.is_empty():
		return
	_cast_hits += 1


## 一次技能施放结束。`hits == 0` 就是**放空**（whiff）—— 这个数不能丢：
## 「AoE 平均命中 3.4」和「AoE 平均命中 3.4 但 40% 的施放打空」是两种完全不同的手感。
static func end_cast() -> void:
	if not enabled or not _active or _cast_id.is_empty():
		return
	var e: Dictionary = _skills.get(_cast_id, {
		"casts": 0, "hits": 0, "whiffs": 0, "max_hits": 0, "aoe": _cast_is_aoe,
	})
	e["casts"] = int(e["casts"]) + 1
	e["hits"] = int(e["hits"]) + _cast_hits
	if _cast_hits == 0:
		e["whiffs"] = int(e["whiffs"]) + 1
	e["max_hits"] = maxi(int(e["max_hits"]), _cast_hits)
	_skills[_cast_id] = e
	if _cast_is_aoe:
		# 关键采样：这一刀是在「场上还剩几只」的时候放的、打中了几只
		_aoe_samples.append([_alive, _cast_hits])
	_cast_id = ""
	_cast_hits = 0


## 击杀一只怪。`kind` ∈ "normal" / "elite" / "boss"。
static func note_kill(kind: String) -> void:
	if not enabled or not _active:
		return
	_kills += 1
	if kind == "boss":
		_kills_boss += 1
	elif kind == "elite":
		_kills_elite += 1


## 玩家打出了一次伤害（用来切分交火段）。**只认玩家打出去的**，不认挨打。
static func note_outgoing_damage() -> void:
	if not enabled or not _active:
		return
	var now := Time.get_ticks_msec()
	if _engage_open:
		if now - _last_outgoing_ms > engage_gap_ms:
			# 上一段已经静默超过阈值 → 收尾，并从这次开始新的一段
			_combat_ms += _last_outgoing_ms - _engage_started_ms
			_engage_count += 1
			_engage_started_ms = now
	else:
		_engage_open = true
		_engage_count += 1
		_engage_started_ms = now
	_last_outgoing_ms = now


# =============================================================================
# 派生指标
# =============================================================================

## 当前快照（调试 HUD / 测试断言用）。不写文件、不改状态。
static func snapshot() -> Dictionary:
	var dur_ms := maxi(1, Time.get_ticks_msec() - _started_ms) if _active else 1
	var combat := _combat_ms
	if _engage_open and _active:
		combat += maxi(0, _last_outgoing_ms - _engage_started_ms)
	return {
		"active": _active,
		"level_id": _level_id,
		"monster_budget": _monster_budget,
		"spawned": _spawned,
		"alive": _alive,
		"kills": _kills,
		"engagements": _engage_count,
		"duration_s": dur_ms / 1000.0,
		"combat_s": combat / 1000.0,
		"kills_per_engagement": _ratio(_kills, _engage_count),
		"aoe_hits_per_cast": _aoe_hits_per_cast(),
	}


## 日志文件的**真实磁盘路径**（给用户看「去哪拿文件」）。
## 注意：无头 / 便携模式下 `globalize_path()` 会返回**相对路径**，
## 直接给用户等于给了一条没法用的路径 —— 这里补成绝对路径（同 `ContentPaths`）。
static func log_absolute_path() -> String:
	var p := ProjectSettings.globalize_path(LOG_FILE)
	if not p.is_absolute_path():
		p = ProjectSettings.globalize_path("res://").path_join(p)
	return p.simplify_path()


static func _close_engagement() -> void:
	if not _engage_open:
		return
	_combat_ms += maxi(0, _last_outgoing_ms - _engage_started_ms)
	_engage_open = false


static func _build_record(completed: bool, dur_ms: int) -> Dictionary:
	var skills_out: Dictionary = {}
	var aoe_casts := 0
	var aoe_hits := 0
	for id in _skills.keys():
		var e: Dictionary = _skills[id]
		var casts := int(e["casts"])
		var hits := int(e["hits"])
		var is_aoe := bool(e["aoe"])
		skills_out[id] = {
			"casts": casts,
			"hits": hits,
			"whiffs": int(e["whiffs"]),
			"max_hits": int(e["max_hits"]),
			"aoe": is_aoe,
			"hits_per_cast": _ratio(hits, casts),
		}
		if is_aoe:
			aoe_casts += casts
			aoe_hits += hits
	return {
		"schema": SCHEMA,
		"level_id": _level_id,
		"tier": _tier,
		"completed": completed,
		"monster_budget": _monster_budget,
		"spawned": _spawned,
		"duration_s": _round2(dur_ms / 1000.0),
		"combat_s": _round2(_combat_ms / 1000.0),
		"kills": _kills,
		"kills_normal": _kills - _kills_elite - _kills_boss,
		"kills_elite": _kills_elite,
		"kills_boss": _kills_boss,
		"engagements": _engage_count,
		"kills_per_min": _per_min(_kills, dur_ms),
		"kills_per_combat_min": _per_min(_kills, _combat_ms),
		"kills_per_engagement": _ratio(_kills, _engage_count),
		"skills": skills_out,
		"aoe_casts": aoe_casts,
		"aoe_hits": aoe_hits,
		"aoe_hits_per_cast": _ratio(aoe_hits, aoe_casts),
		"aoe_samples": _aoe_samples.duplicate(),
	}


static func _aoe_hits_per_cast() -> float:
	var casts := 0
	var hits := 0
	for id in _skills.keys():
		var e: Dictionary = _skills[id]
		if bool(e["aoe"]):
			casts += int(e["casts"])
			hits += int(e["hits"])
	return _ratio(hits, casts)


static func _ratio(a: int, b: int) -> float:
	if b <= 0:
		return 0.0
	return _round2(float(a) / float(b))


static func _per_min(count: int, ms: int) -> float:
	if ms <= 0:
		return 0.0
	return _round2(count * 60000.0 / float(ms))


static func _round2(v: float) -> float:
	return snappedf(v, 0.01)


static func _append_line(rec: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path(LOG_DIR)
	if not dir.is_absolute_path():
		dir = ProjectSettings.globalize_path("res://").path_join(dir)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(LOG_FILE, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	if f == null:
		push_warning("[CombatMetrics] 无法写入 %s（error %d）—— 本局指标丢失"
			% [LOG_FILE, FileAccess.get_open_error()])
		return
	f.seek_end()
	f.store_line(JSON.stringify(rec))
	f.close()
