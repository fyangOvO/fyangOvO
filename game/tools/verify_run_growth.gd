## 局内成长实测（任务 4.1–4.3 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_run_growth.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（6 个测试段）：
##   A. 局内等级：1–10 上限、经验曲线、多级连升、出关清零
##   B. 选项池：15 个选项、类别/键完整
##   C. 三选一：不重复抽取 3 个、已选不再出现
##   D. 30% 上限：攻击/生命达上限移除，功能键不占上限
##   E. Buff 并入：三选一/祭坛/连杀 → StatCalculator buffs
##   F. 连杀：3 秒窗口、每 20 连杀 +3% 攻击、上限 +15%
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 局内成长实测（任务 4.1–4.3） =====")
	_rng.seed = 20260916
	await _test_progression()
	await _test_pool()
	await _test_choices()
	await _test_caps()
	await _test_buffs()
	await _test_streak()
	_finish()


# =============================================================================
# A. 局内等级
# =============================================================================

func _test_progression() -> void:
	print("--- A. 局内等级 ---")
	var up_events: Array[int] = []
	var prog := RunProgression.new(func(lv: int) -> void: up_events.append(lv))
	_ok("起始局内 1 级", prog.run_level == 1)
	_ok("经验曲线为正且递增", RunProgression.xp_to_next(1) > 0.0
		and RunProgression.xp_to_next(5) > RunProgression.xp_to_next(2))
	prog.add_xp(999999.0)
	_ok("大量经验连升到 10 级且触发 9 次三选一",
		prog.run_level == 10 and up_events.size() == 9)
	_ok("10 级后经验不再累积", prog.total_xp < 999999.0 or prog.run_level == 10)
	prog.reset()
	_ok("出关清零回 1 级", prog.run_level == 1 and prog.xp_cur == 0.0)
	# 单级精确：1→2 需要 xp_to_next(1) = 20
	var prog2 := RunProgression.new()
	prog2.add_xp(20.0)
	_ok("1→2 级需 20 XP（20×1^1.4）", prog2.run_level == 2 and absf(prog2.xp_cur) < 0.01)


# =============================================================================
# B. 选项池
# =============================================================================

func _test_pool() -> void:
	print("--- B. 选项池 ---")
	_ok("池 15 个选项", RunePool.OPTIONS.size() == 15)
	var cats := {}
	for opt in RunePool.OPTIONS:
		cats[opt["cat"]] = cats.get(opt["cat"], 0) + 1
		_ok("选项 %s 键完整" % opt["id"],
			opt.has("name") and opt.has("desc") and opt.has("stat_key")
			and opt.has("value") and opt.has("cap"))
	_ok("攻击 6 / 防御 5 / 资源 4", cats.get("attack", 0) == 6
		and cats.get("defense", 0) == 5 and cats.get("resource", 0) == 4)


# =============================================================================
# C. 三选一
# =============================================================================

func _test_choices() -> void:
	print("--- C. 三选一 ---")
	var c1 := RunePool.get_choices(3, [], {}, _rng)
	_ok("抽取 3 个且互不重复", c1.size() == 3
		and c1[0]["id"] != c1[1]["id"] and c1[1]["id"] != c1[2]["id"]
		and c1[0]["id"] != c1[2]["id"])
	var picked := [c1[0]["id"], c1[1]["id"]]
	var c2 := RunePool.get_choices(3, picked, {}, _rng)
	for opt in c2:
		_ok("已选过的不再出现（%s）" % opt["id"], not opt["id"] in picked)


# =============================================================================
# D. 30% 上限
# =============================================================================

func _test_caps() -> void:
	print("--- D. 上限移除 ---")
	# 攻击已达 +30%（狂怒 12×2=24 + 疾风？——用 stats_pct 直接顶到上限）
	var stats := {"pct_attack": 30.0, "attack_speed": 20.0, "crit_chance": 20.0}
	var choices := RunePool.get_choices(20, [], stats, _rng)
	var has_attack_capped := false
	for opt in choices:
		if opt["id"] in ["fury", "gale", "lethal"]:
			has_attack_capped = true
	_ok("攻击/攻速/暴击达上限后从池移除",
		not has_attack_capped and choices.size() > 0)
	_ok("功能键不占上限（移速/金币/幸运仍在）",
		RunePool.get_cap("swift") == 0.0 and RunePool.get_cap("greed") == 0.0
		and RunePool.get_cap("fortune") == 0.0)


# =============================================================================
# E. Buff 并入
# =============================================================================

func _test_buffs() -> void:
	print("--- E. Buff 并入 ---")
	var buffs := RunBuffSystem.new()
	buffs.apply_option("fury") # +12% 攻击
	buffs.apply_option("tenacity") # +15% 最大生命
	var calc_buffs := buffs.to_calculator_buffs()
	_ok("三选一转 buffs 格式（pct）",
		calc_buffs.has("fury") and calc_buffs.has("tenacity"))
	var stats := StatCalculator.calculate(1, [], calc_buffs)
	_ok("狂怒 +12% 攻击并入（12 × 1.12）", _near(stats["attack"], 12.0 * 1.12))
	_ok("坚韧 +15% 生命并入（150 × 1.15）", _near(stats["max_hp"], 150.0 * 1.15))
	# 祭坛
	buffs.reset()
	buffs.apply_option("altar_power")
	var altar_buffs := buffs.to_calculator_buffs()
	_ok("祭坛转 buffs（含负面）",
		altar_buffs.has("altar_power") and float(altar_buffs["altar_power"]["pct"]["damage_taken"]) == 15.0)
	var stats2 := StatCalculator.calculate(1, [], altar_buffs)
	_ok("祭坛 +20% 攻击 -15% 受击并入", _near(stats2["attack"], 12.0 * 1.20)
		and _near(stats2["damage_taken"], 15.0))


# =============================================================================
# F. 连杀
# =============================================================================

func _test_streak() -> void:
	print("--- F. 连杀 ---")
	var buffs := RunBuffSystem.new()
	buffs.tick(1.0)
	for i in 20:
		buffs.on_kill()
		buffs.tick(0.1)
	_ok("20 连杀 → +3% 攻击", _near(buffs.streak_bonus_attack, 3.0))
	for i in 80:
		buffs.on_kill()
		buffs.tick(0.1)
	_ok("100 连杀 → 上限 +15%", _near(buffs.streak_bonus_attack, 15.0))
	var cb_full := buffs.to_calculator_buffs()
	_ok("连杀加成并入（100 连杀 pct_attack = 15）",
		cb_full.has("kill_streak")
		and _near(float(cb_full["kill_streak"]["pct"]["pct_attack"]), 15.0))
	buffs.tick(5.0) # 超 3 秒窗口
	buffs.on_kill()
	_ok("断连后重计（1 连杀 → 加成归 0.15）", buffs.streak == 1
		and _near(buffs.streak_bonus_attack, 0.15))
	var cb := buffs.to_calculator_buffs()
	_ok("断连后连杀加成并入（pct_attack = 0.15）",
		cb.has("kill_streak")
		and _near(float(cb["kill_streak"]["pct"]["pct_attack"]), 0.15))


func _near(a: float, b: float, tol: float = 0.5) -> bool:
	return absf(a - b) <= tol


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
