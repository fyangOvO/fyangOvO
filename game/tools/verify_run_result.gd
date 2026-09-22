## 本局结算实测（任务 4.5 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_run_result.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（5 个测试段）：
##   A. 存活结算：字段完整、金币扣 50%、材料扣 50%
##   B. 死亡结算：无存活加成
##   C. 掉落：已入包保留 / 未入包丢失计数
##   D. 评分：击杀/等级/稀有掉落/连杀/存活加成分解
##   E. 评级：D/C/B/A/S 阈值
extends Node

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 本局结算实测（任务 4.5） =====")
	await _test_survive()
	await _test_death()
	await _test_drops()
	await _test_score()
	await _test_grade()
	_finish()


# =============================================================================
# A. 存活结算
# =============================================================================

func _test_survive() -> void:
	print("--- A. 存活结算 ---")
	var bagged := [EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("sword_iron"), 12, GameConstants.Rarity.RARE)]
	var res := RunResult.finalize(true, 100, 10, 1234.0,
		{"gold": 100.0, "dust": 20.0}, bagged, 5, 3, 80)
	_ok("存活标记", res.survived)
	_ok("金币扣 50%（1234 → 617）", int(res.gold_after) == 617)
	_ok("材料扣 50%（dust 20 → 10）", int(res.materials_after["dust"]) == 10)
	_ok("入包装备保留 1 件", res.bagged_equipment.size() == 1)
	_ok("未入包掉落计数 5（丢失）", res.unbagged_drops == 5)


# =============================================================================
# B. 死亡结算
# =============================================================================

func _test_death() -> void:
	print("--- B. 死亡结算 ---")
	var res := RunResult.finalize(false, 30, 5, 500.0, {}, [], 10, 0, 0)
	_ok("死亡无存活加成（30×10 + 5×50 = 550）", int(res.score) == 550)


# =============================================================================
# C. 掉落
# =============================================================================

func _test_drops() -> void:
	print("--- C. 掉落 ---")
	var res := RunResult.finalize(true, 0, 1, 0.0, {}, [], 0, 0, 0)
	_ok("零击杀结算存活 500 + 等级 50 = 550", int(res.score) == 550)
	var res2 := RunResult.finalize(true, 0, 1, 0.0, {}, [], 12, 0, 0)
	_ok("未入包掉落只计数不扣分", int(res2.score) == 550)


# =============================================================================
# D. 评分
# =============================================================================

func _test_score() -> void:
	print("--- D. 评分 ---")
	# 存活 500 + 击杀 50×10 + 等级 8×50 + 稀有 2×100 + 连杀 40×2
	var res := RunResult.finalize(true, 50, 8, 0.0, {}, [], 0, 2, 40)
	_ok("评分分解精确（500+500+400+200+80 = 1680）", int(res.score) == 1680)


# =============================================================================
# E. 评级
# =============================================================================

func _test_grade() -> void:
	print("--- E. 评级 ---")
	_ok("1680 → S", RunResult._grade(1680.0) == "S")
	_ok("1200 → A", RunResult._grade(1200.0) == "A")
	_ok("800 → B", RunResult._grade(800.0) == "B")
	_ok("450 → C", RunResult._grade(450.0) == "C")
	_ok("100 → D", RunResult._grade(100.0) == "D")


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
