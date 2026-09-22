## 成就系统（任务 5.6 · class_name）
##
## GDD 5.5：50 个成就（暂定），完成后给**外观奖励**（武器光效 / 角色配色），
##   不给战力。工程侧默认：数据表 data/achievements.json（20 个起步示例），
##   成就 = id / 名称 / 条件（type + target）/ 外观奖励标记。
class_name AchievementSystem
extends RefCounted

const ACHIEVEMENTS_FILE := "res://data/achievements.json"

var achievements: Dictionary = {}   # id -> {name, type, target, reward}
var unlocked: Dictionary = {}       # id -> true


func load_definitions() -> void:
	var path := ACHIEVEMENTS_FILE
	if not ResourceLoader.exists(path):
		push_warning("成就数据缺失：%s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	if raw is Dictionary and raw.has("achievements"):
		achievements = raw["achievements"]


## 上报进度：type + 当前值 → 检查全部成就解锁
## 返回本次新解锁的成就 id 列表
func report_progress(type: String, value: float) -> Array[String]:
	var new_unlocks: Array[String] = []
	for id in achievements:
		if unlocked.has(id):
			continue
		var a: Dictionary = achievements[id]
		if str(a.get("type", "")) != type:
			continue
		if value >= float(a.get("target", 0.0)):
			unlocked[id] = true
			new_unlocks.append(id)
	return new_unlocks


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func unlocked_count() -> int:
	return unlocked.size()


func total_count() -> int:
	return achievements.size()


## 外观奖励标记（不给战力）：reward 字段
static func reward_label(id: String, achievements_data: Dictionary) -> String:
	var a: Dictionary = achievements_data.get(id, {})
	return str(a.get("reward", "无"))
