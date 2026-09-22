## 局内等级与经验（任务 4.1 · class_name）
##
## GDD 0.4 节 4.1：进关从局内 1 级开始，击杀怪物获得「本局经验」，
## 上限局内 10 级；每升 1 级触发三选一（3 个选项从池中不重复抽取）；出关清零。
##
## 经验曲线（工程侧默认，GDD 未给局内公式）：
##   XP_ToNext(level) = 20 × level^1.4   （形态参照 GDD 5.1 账号公式 180×L^1.6
##   缩到局内 10 级节奏；1→10 级总需 ≈ 1,848 XP，单关 150 怪 × 12 XP 可升满）
class_name RunProgression
extends RefCounted

const MAX_RUN_LEVEL := 10

var run_level := 1
var xp_cur := 0.0
var xp_next := 0.0

var _on_level_up: Callable  # func(new_level: int) -> void（触发三选一）


func _init(on_level_up: Callable = Callable()) -> void:
	_on_level_up = on_level_up
	_refresh_xp_next()


## 本局累计经验（出关清零）
var total_xp := 0.0


## 升到下一级所需经验（局内公式，工程侧默认）
static func xp_to_next(level: int) -> float:
	return 20.0 * pow(float(level), 1.4)


func _refresh_xp_next() -> void:
	xp_next = xp_to_next(run_level)


## 加经验；自动处理多级连升（每级触发三选一）
func add_xp(amount: float) -> void:
	if amount <= 0.0 or run_level >= MAX_RUN_LEVEL:
		return
	xp_cur += amount
	total_xp += amount
	while run_level < MAX_RUN_LEVEL and xp_cur >= xp_next:
		xp_cur -= xp_next
		run_level += 1
		AudioManager.play("levelup")
		if _on_level_up.is_valid():
			_on_level_up.call(run_level)
		_refresh_xp_next()


## 出关清零（GDD 0.4 节 4.1：局内 = 单局临时状态）
func reset() -> void:
	run_level = 1
	xp_cur = 0.0
	total_xp = 0.0
	_refresh_xp_next()


## 进度 0–1（UI 经验条用）
func progress() -> float:
	if run_level >= MAX_RUN_LEVEL:
		return 1.0
	return xp_cur / xp_next
