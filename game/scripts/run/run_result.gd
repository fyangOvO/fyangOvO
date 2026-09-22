## 本局结算（任务 4.5 · class_name）
##
## D2 方案 B（已确认）：保留等级/经验/已入包装备/已通关解锁；
##   丢失本局未入包掉落；金币材料结算扣 50%；每关 1 次原地复活。
##
## 评分（工程侧默认）：存活 500 + 击杀 ×10 + 局内等级 ×50 + 稀有掉落（紫橙）每件 ×100
##   + 连杀峰值 ×2。
class_name RunResult
extends RefCounted

const SURVIVE_BONUS := 500.0
const KILL_SCORE := 10.0
const LEVEL_SCORE := 50.0
const RARE_DROP_SCORE := 100.0
const STREAK_SCORE := 2.0
const SETTLE_GOLD_RATE := 0.5   # D2：金币材料结算扣 50%


## 结算输入（战斗层组装）：见 finalize
var survived := false
var kills := 0
var run_level := 1
var gold_before := 0.0
var gold_after := 0.0
var materials_before := {}
var materials_after := {}
## 入包装备（保留）
##
## ⚠️ **元素类型契约：必须是 `EquipmentInstance` 对象，不能是 Dictionary。**
##    `ResultPanel.show_result()` 直接读 `item.template_id / .rarity / .item_level`
##    （result_panel.gd:75-77）。传 Dictionary 会抛
##    `Invalid access to property or key 'template_id' on a base object of type 'Dictionary'`，
##    且该异常发生在面板**创建按钮之前** ⇒ 玩家卡在结算界面回不了据点。
##    生产侧请像 `LevelScene._collect_bagged()` 那样先做类型转换。
var bagged_equipment: Array = []
var unbagged_drops: int = 0        # 未入包掉落（丢失）
var rare_drops := 0                # 紫/橙+ 稀有掉落数（评分）
var max_streak := 0
var score := 0.0
var grade := ""


## 执行结算：入参为**结算前快照**；返回自身（结算单）。
## bagged：已入包装备（保留）；unbagged_count：未入包掉落件数（丢失）；
## materials：{key: amount} 材料快照（扣 50%）。
##
## `p_gold_gain_pct`：局内「贪婪」等金币/材料获取加成（百分数，默认 0 = 不变）。
##   在 50% 结算率**之上**再乘 `1 + pct/100`（GDD 0.4 §4.2「本局金币/材料获取 +30%」）。
static func finalize(p_survived: bool, p_kills: int, p_run_level: int,
		p_gold: float, p_materials: Dictionary, p_bagged: Array,
		p_unbagged_count: int, p_rare_drops: int, p_max_streak: int,
		p_gold_gain_pct: float = 0.0) -> RunResult:
	var res := RunResult.new()
	res.survived = p_survived
	res.kills = p_kills
	res.run_level = p_run_level
	res.gold_before = p_gold
	var gain_mult := 1.0 + maxf(p_gold_gain_pct, 0.0) / 100.0
	res.gold_after = floor(p_gold * SETTLE_GOLD_RATE * gain_mult)
	res.materials_before = p_materials.duplicate()
	res.materials_after = {}
	for key in p_materials:
		res.materials_after[key] = floor(float(p_materials[key]) * SETTLE_GOLD_RATE * gain_mult)
	res.bagged_equipment = p_bagged.duplicate()
	res.unbagged_drops = p_unbagged_count
	res.rare_drops = p_rare_drops
	res.max_streak = p_max_streak
	res.score = _score(res)
	res.grade = _grade(res.score)
	return res


static func _score(res: RunResult) -> float:
	var s := float(res.kills) * KILL_SCORE + float(res.run_level) * LEVEL_SCORE \
		+ float(res.rare_drops) * RARE_DROP_SCORE + float(res.max_streak) * STREAK_SCORE
	if res.survived:
		s += SURVIVE_BONUS
	return s


static func _grade(score: float) -> String:
	if score >= 1500.0:
		return "S"
	if score >= 1000.0:
		return "A"
	if score >= 700.0:
		return "B"
	if score >= 400.0:
		return "C"
	return "D"
