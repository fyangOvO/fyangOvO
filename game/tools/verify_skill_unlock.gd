## 技能解锁逻辑实测（B7 · 1-V11 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_skill_unlock.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖（GDD 01-技能体系 §9）：
##   A. 未知技能 id ⇒ 不解锁（防拼错静默放行）
##   B. 成长轨：unlock_level 门槛（低于锁 / 达标开）
##   C. 进度轨：unlock_boss 首通门槛（未通锁 / 通后开）
##   D. unlocked_skill_ids 保持职业池顺序 + 过滤未解锁
##   E. lock_reason 文案正确（等级 / 通关 / 空=已解锁）
##   F. 解锁是**纯推导**：调用解锁判定后 SkillBar（SaveData.skill_bar）不变
extends Node

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	print("===== 技能解锁逻辑实测（1-V11）=====")
	# A. 未知 id
	_ok("A. 未知技能 id 不解锁", not UnlockSystem.is_skill_unlocked("no_such_skill", 99, []))
	# B. 成长轨：power_strike unlock_level=5
	_ok("B1. power_strike Lv4 锁定", not UnlockSystem.is_skill_unlocked("power_strike", 4, []))
	_ok("B2. power_strike Lv5 解锁", UnlockSystem.is_skill_unlocked("power_strike", 5, []))
	# C. 进度轨：iron_bulwark unlock_boss=ch1_l06, unlock_level=0
	_ok("C1. iron_bulwark 未首通 ch1_l06 锁定",
		not UnlockSystem.is_skill_unlocked("iron_bulwark", 99, ["ch1_l01"]))
	_ok("C2. iron_bulwark 首通 ch1_l06 解锁",
		UnlockSystem.is_skill_unlocked("iron_bulwark", 99, ["ch1_l01", "ch1_l06"]))
	# D. 顺序+过滤
	var ids: Array = UnlockSystem.unlocked_skill_ids("warrior", 1, [])
	_ok("D1. Lv1 战士只解锁 Lv1 技能（cleave 等）",
		ids.size() >= 1 and ids[0] == "cleave" and not ids.has("power_strike"))
	_ok("D2. unlocked 列表是职业池的保序子序列", _is_ordered_subsequence(
		UnlockSystem.unlocked_skill_ids("warrior", 99, []),
		ConfigLoader.class_skill_ids("warrior")))
	# E. 文案
	_ok("E1. 等级门槛文案", UnlockSystem.skill_lock_reason("power_strike", 4, []).contains("5"))
	_ok("E2. BOSS 门槛文案", UnlockSystem.skill_lock_reason("iron_bulwark", 99, []).contains("ch1_l06"))
	_ok("E3. 已解锁文案为空", UnlockSystem.skill_lock_reason("cleave", 1, []) == "")
	# F. 纯推导：不改动出战栏
	var before: Array = []
	if SaveManager.current_data != null:
		before = (SaveManager.current_data.skill_bar as Array).duplicate()
	UnlockSystem.unlocked_skill_ids("warrior", 99, ["ch1_l06"])
	var after: Array = []
	if SaveManager.current_data != null:
		after = (SaveManager.current_data.skill_bar as Array).duplicate()
	_ok("F. 解锁判定不改动 skill_bar（纯推导）", before == after)
	print("===== 技能解锁逻辑实测 结束：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## sub 是否为 seq 的保序子序列（子序列元素按原顺序出现，允许跳过）。
func _is_ordered_subsequence(sub: Array, seq: Array) -> bool:
	var j := 0
	for s in sub:
		while j < seq.size() and seq[j] != s:
			j += 1
		if j >= seq.size():
			return false
		j += 1
	return true

