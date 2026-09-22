## 一次命中结算的完整结果（任务 2.3 · 伤害计算管线）
##
## 由 `DamageCalc.compute_hit()` 产出，供伤害数字显示（2.8 打击感）、
## 事件负载（EventBus.damage_dealt）、词缀/套装结算（阶段 3）消费。
## 纯数据对象，不持有节点引用。
class_name DamageResult
extends RefCounted

## 未暴击、未减伤、未元素加成的基础伤害（AD × 技能倍率）
var raw_damage: float = 0.0

## 本次是否暴击
var crit: bool = false

## 本次实际暴击倍率（非暴击 = 1.0；暴击默认 1.5）
var crit_multiplier: float = 1.0

## 伤害元素（GameConstants.ELEMENT_*：physical / fire / cold / lightning / poison）
var element: String = GameConstants.ELEMENT_PHYSICAL

## 元素加成倍率（1 + 元素伤害%；当前恒 1.0，词缀/套装阶段 3 接入）
var element_multiplier: float = 1.0

## 减伤后剩余比例（0–1，1 = 无减伤）
var mitigation_factor: float = 1.0

## 最终伤害（取整前，可带小数；显示层按 UI 规范取整）
var final_damage: float = 0.0


func _init(
	p_raw: float = 0.0,
	p_crit: bool = false,
	p_crit_multiplier: float = 1.0,
	p_element: String = GameConstants.ELEMENT_PHYSICAL,
	p_element_multiplier: float = 1.0,
	p_mitigation_factor: float = 1.0,
	p_final_damage: float = 0.0,
) -> void:
	raw_damage = p_raw
	crit = p_crit
	crit_multiplier = p_crit_multiplier
	element = p_element
	element_multiplier = p_element_multiplier
	mitigation_factor = p_mitigation_factor
	final_damage = p_final_damage


## 人类可读摘要（验证脚本 / 调试输出用）
func to_summary() -> String:
	var parts := "[raw=%.1f" % raw_damage
	if crit:
		parts += " crit=×%.2f" % crit_multiplier
	if not is_equal_approx(element_multiplier, 1.0):
		parts += " elem=×%.2f(%s)" % [element_multiplier, element]
	if not is_equal_approx(mitigation_factor, 1.0):
		parts += " mit=×%.2f" % mitigation_factor
	parts += " final=%.1f]" % final_damage
	return parts
