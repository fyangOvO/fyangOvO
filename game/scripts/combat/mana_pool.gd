## 法力池（任务 2.2 · 资源消耗）
##
## 职责：维护当前法力值 / 上限，处理自然回复与消耗，并通过 EventBus.resource_changed
##       通知 UI 资源条。挂在 Player 节点下（组件式，便于后续给怪物 / BOSS 复用）。
##
## 数值基线（GameConstants 八·七）：上限 100 / 自然回复 4/s / 普攻命中 +2。
## 阶段 3 词缀乘区（+最大资源 / +资源回复速度 / +技能减耗）从 `apply_stats()` 接入。
class_name ManaPool
extends Node

## 当前法力
var current: float = GameConstants.MANA_BASE_MAX

## 最大法力（阶段 3 词缀加成后 = MANA_BASE_MAX + bonus）
var maximum: float = GameConstants.MANA_BASE_MAX

## 词缀附加最大法力（阶段 3 由装备系统写入）
var max_bonus: float = 0.0

## 回复速度倍率（阶段 3 由「+资源回复速度」词缀写入）
var regen_multiplier: float = 1.0

## 技能消耗折扣（0–1；阶段 3 由「+技能减耗」词缀写入，1.0 = 全额）
var cost_multiplier: float = 1.0


func _ready() -> void:
	_clamp_current()
	_emit()


## 自然回复（每物理帧调用一次；delta 秒 × 每秒回复量）
func tick_regen(delta: float) -> void:
	if delta <= 0.0:
		return
	current = minf(current + GameConstants.MANA_REGEN_PER_SEC * regen_multiplier * delta, maximum)
	# 只在真正变化时发信号，避免 UI 每帧刷新
	_emit()


## 尝试消耗法力。返回是否成功（不足则失败且不扣减）。
func try_spend(amount: float) -> bool:
	var actual := amount * cost_multiplier
	if current + 0.0001 < actual:
		return false
	current -= actual
	_emit()
	return true


## 恢复法力（普攻命中 / 药水 / 击杀回蓝）
func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	current = minf(current + amount, maximum)
	_emit()


## 直接设置当前法力（读档 / 调试用）
func set_current(value: float) -> void:
	current = clampf(value, 0.0, maximum)
	_emit()


## 应用属性乘区（阶段 3 调用：传入 flat 与 pct 加成）
func apply_stats(flat_max: float = 0.0, regen_pct: float = 0.0, cost_reduction_pct: float = 0.0) -> void:
	max_bonus = flat_max
	maximum = maxf(GameConstants.MANA_BASE_MAX + max_bonus, 1.0)
	regen_multiplier = 1.0 + regen_pct
	cost_multiplier = clampf(1.0 - cost_reduction_pct, 0.0, 1.0)
	_clamp_current()
	_emit()


## 当前是否足够支付某消耗
func can_afford(amount: float) -> bool:
	return current + 0.0001 >= amount * cost_multiplier


func _clamp_current() -> void:
	current = clampf(current, 0.0, maximum)


func _emit() -> void:
	EventBus.resource_changed.emit(current, maximum)
