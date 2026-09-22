## 平衡性数值仿真实测（任务 8.4 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_balance84.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 仿真口径（D9 已锁定）：
##   怪物 HP  = 100.7 * 1.284^(L-1)      （怪物数值 v1.5）
##   怪物 DMG = 5.61   * 1.218^(L-1)
##   难度系数：HP * 1.08^n / DMG * 1.23^n（n=0..4；梦魇 V 伤 ×2.4 / HP ×1.36 即公式 1.23^4/1.08^4 近似）
##   玩家成长（局内 20 关 × 装备滚雪球；8.4 调优：复合成长 1.30 匹配怪成长，防海绵化）：
##     DPS(L)   = 20 * 1.30^L * 技能倍率 1.25（等级 + 装备 + 技能复合成长）
##     MaxHP(L) = 500 * 1.06^L（战士基础 + 局内成长）
##   指标：
##     TTK（常规怪击杀秒数）= 怪HP / 玩家DPS
##     承伤秒数 = 玩家MaxHP / 怪DPS（秒伤取 0.5 次/秒 → 怪物DMG/2）
##   目标（平衡报告断言）：
##     A. 常规怪 TTK ∈ [1.0, 8.0] 秒（打得动，不海绵化）
##     B. 难度单调爬坡：TTK / 承伤随 n 递增（除 HP 系数低导致 TTK 微升）
##     C. 高层级（梦魇 III-V）承伤秒数 < 10 → 玩家可被秒（D9「高层级允许被秒」）
##     D. 低层级（普通）承伤秒数 > 12 → 新手不猝死
extends Node2D

var _fail: int = 0

const MONSTER_HP_BASE := 100.7
const MONSTER_HP_GROWTH := 1.284
const MONSTER_DMG_BASE := 5.61
const MONSTER_DMG_GROWTH := 1.218
const DIFF_HP := 1.08
const DIFF_DMG := 1.23
const PLAYER_DPS_BASE := 20.0
const PLAYER_DPS_GROWTH := 1.30
const SKILL_MULT := 1.25
const PLAYER_HP_BASE := 500.0
const PLAYER_HP_GROWTH := 1.06
const MONSTER_HITS_PER_SEC := 0.5


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func monster_hp(level: int, diff: int) -> float:
	return MONSTER_HP_BASE * pow(MONSTER_HP_GROWTH, level - 1) * pow(DIFF_HP, diff)


func monster_dmg(level: int, diff: int) -> float:
	return MONSTER_DMG_BASE * pow(MONSTER_DMG_GROWTH, level - 1) * pow(DIFF_DMG, diff)


func player_dps(level: int) -> float:
	return PLAYER_DPS_BASE * pow(PLAYER_DPS_GROWTH, level) * SKILL_MULT


func player_max_hp(level: int) -> float:
	return PLAYER_HP_BASE * pow(PLAYER_HP_GROWTH, level)


func ttk(level: int, diff: int) -> float:
	return monster_hp(level, diff) / player_dps(level)


func ttk_to_kill(level: int, diff: int) -> float:
	return monster_hp(level, diff) / (player_dps(level) / 1.0)


func survive_seconds(level: int, diff: int) -> float:
	return player_max_hp(level) / (monster_dmg(level, diff) * MONSTER_HITS_PER_SEC)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 平衡性数值仿真实测（任务 8.4） =====")
	await _run()
	_finish()


func _run() -> void:
	# —— 输出仿真矩阵（20 关 × 5 难度：TTK / 承伤） ——
	print("\n【仿真矩阵】常规怪 TTK（秒）— 行=关卡 1..20，列=难度 普通..梦魇V")
	for level in range(1, 21):
		var row := ""
		for diff in range(5):
			var t := ttk(level, diff)
			row += "%6.1f " % t
		print("  L%02d: %s" % [level, row])
	print("\n【仿真矩阵】承伤秒数（玩家 MaxHP / 怪DPS）")
	for level in range(1, 21):
		var row := ""
		for diff in range(5):
			row += "%6.1f " % survive_seconds(level, diff)
		print("  L%02d: %s" % [level, row])

	# —— 断言 ——
	# A. 常规怪 TTK ∈ [1.0, 8.0]（全部 20 关 × 5 难度）
	var ttk_min := 999.0
	var ttk_max := 0.0
	for level in range(1, 21):
		for diff in range(5):
			var t := ttk(level, diff)
			ttk_min = minf(ttk_min, t)
			ttk_max = maxf(ttk_max, t)
	_ok("常规怪 TTK ∈ [1.0, 8.0] 秒（实测 %.2f–%.2f，不海绵化）" % [ttk_min, ttk_max],
		ttk_min >= 1.0 and ttk_max <= 8.0)

	# B. 难度单调爬坡：每关 TTK 随 n 递增；承伤随 n 递减（更危险）
	var mono_ttk := true
	var mono_surv := true
	for level in range(1, 21):
		for diff in range(1, 5):
			if ttk(level, diff) < ttk(level, diff - 1) - 0.001:
				mono_ttk = false
			if survive_seconds(level, diff) > survive_seconds(level, diff - 1) + 0.001:
				mono_surv = false
	_ok("难度爬坡：TTK 随难度递增（怪更肉）", mono_ttk)
	_ok("难度爬坡：承伤秒数随难度递减（怪更致命）", mono_surv)

	# C. 高层级（梦魇 III-V）承伤秒数 < 10 → 玩家可被秒（D9 授权）
	var hi_surv := 999.0
	for level in range(5, 21):
		for diff in range(3, 5):
			hi_surv = minf(hi_surv, survive_seconds(level, diff))
	_ok("梦魇 III–V 承伤秒数 < 10（玩家可被秒，实测 %.1f）" % hi_surv, hi_surv < 10.0)

	# D. 低层级（普通 I）承伤秒数 > 12 → 新手不猝死
	var lo_surv := 999.0
	for level in range(1, 6):
		lo_surv = minf(lo_surv, survive_seconds(level, 0))
	_ok("普通难度前 5 关承伤秒数 > 12（实测 %.1f，新手不猝死）" % lo_surv, lo_surv > 12.0)

	# E. 成长性：同难度 20 关 vs 1 关 TTK 收敛（装备滚雪球压过怪血成长）
	var ttk_last := ttk(20, 0)
	var ttk_first := ttk(1, 0)
	_ok("第 20 关 TTK（%.1f）不高于第 1 关（%.1f）×2（成长可见）" % [ttk_last, ttk_first],
		ttk_last <= ttk_first * 2.0)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
