## 章节声望（任务 5.6 · class_name）
##
## GDD 5.5：每章独立声望，击杀 / 通关累积；每 1 级给永久小额加成
##   （+1% 经验、+1% 金币），上限 10 级/章。
class_name ChapterReputation
extends RefCounted

const MAX_REP_LEVEL := 10
const KILL_XP := 1.0       # 每击杀 1 声望
const CLEAR_BONUS := 30.0  # 每通关 +30


var rep_levels := {}   # chapter_id -> level
var rep_xp := {}       # chapter_id -> 累积 xp


func add_kill(chapter_id: String) -> void:
	_add(chapter_id, KILL_XP)


func add_clear(chapter_id: String) -> void:
	_add(chapter_id, CLEAR_BONUS)


func _add(chapter_id: String, amount: float) -> void:
	if chapter_id.is_empty():
		return
	rep_xp[chapter_id] = float(rep_xp.get(chapter_id, 0.0)) + amount
	while int(rep_levels.get(chapter_id, 0)) < MAX_REP_LEVEL:
		var lv := int(rep_levels.get(chapter_id, 0))
		var need := _xp_to_next(lv)
		if float(rep_xp[chapter_id]) < need:
			break
		rep_xp[chapter_id] = float(rep_xp[chapter_id]) - need
		rep_levels[chapter_id] = lv + 1


## 每级所需声望（工程侧默认：每级 150 = 约 1 关（150 怪），一章 20 关可升满 10 级）
static func _xp_to_next(_level: int) -> float:
	return 150.0


## 某章声望加成：+1% 经验 +1% 金币/级
static func get_bonus(level: int) -> Dictionary:
	return {"xp_gain": float(level), "gold_gain": float(level)}


## 全部章节加成汇总（并入属性结算）
func get_total_bonus() -> Dictionary:
	var out := {}
	for chapter in rep_levels:
		var lv := int(rep_levels[chapter])
		if lv <= 0:
			continue
		var bonus := get_bonus(lv)
		for key in bonus:
			out[key] = float(out.get(key, 0.0)) + float(bonus[key])
	return out
