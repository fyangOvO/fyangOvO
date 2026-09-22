## 伤害计算管线实测（任务 2.3 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_damage.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（用户 2.3 拍板口径）：
##   A. 基础：raw = AD × 技能倍率；无减伤无暴击路径确定性
##   B. 暴击：CR 5% / CD 150% / cap 75% / 期望公式 1+CR×(CD-1) / roll 统计
##   C. 元素：物理走护甲、元素走抗性（同构 50L）/ 元素伤害加成 / 抗性 cap 75%
##   D. 减伤：护甲 DR / 抗性 DR / 额外减伤% 乘算 / 顺序（护甲→减伤%）/ clamp
##   E. 接入回归：普攻与技能真实走管线（暴击集合断言）/ 目标护甲生效 /
##      技能元素改写后走对应抗性 / 回蓝与事件不受影响
##   F. GDD 锚点：6.6 期望公式 / DR 公式数值 / EHP 演示
extends Node

var _fail: int = 0
var _player: PlayerController = null
var _skills: SkillController = null
var _dummy: DamageDummy = null
var _last_event: Array = []


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 伤害计算管线实测 =====")
	_setup_scene()
	await _test_basics()
	await _test_crit()
	await _test_element()
	await _test_mitigation()
	await _test_integration()
	await _test_gdd_anchors()
	_finish()


func _setup_scene() -> void:
	_player = get_node_or_null("/root/VerifyDamage/Player") as PlayerController
	_skills = _player.get_skill_controller()
	_dummy = get_node_or_null("/root/VerifyDamage/Dummy") as DamageDummy
	EventBus.damage_dealt.connect(_on_damage_dealt)
	_ok("场景就绪：玩家 + 技能控制器 + 受击靶", _player != null and _skills != null and _dummy != null)
	_player.set_facing(PlayerController.Facing8.DOWN)


func _on_damage_dealt(target: Node, amount: float, crit: bool, element: String) -> void:
	_last_event = [target, amount, crit, element]


## 放玩家与靶子回初始位（技能击退 / 闪避会移位；攻速计时一并清掉，否则 try_attack 被拒）
func _reset_positions() -> void:
	_player.global_position = Vector2(0, 0)
	_player.velocity = Vector2.ZERO
	_player._attack_timer = 0.0
	_dummy.global_position = Vector2(0, 40)
	_dummy.reset()


# =============================================================================
# A. 基础
# =============================================================================

func _test_basics() -> void:
	print("--- A. 基础 ---")
	# 无暴击（chance=0）、无减伤：final = raw
	var r := DamageCalc.compute_hit(12.0, 0.0, 150.0, GameConstants.ELEMENT_PHYSICAL,
		0.0, 0.0, 0.0, 1, 0.0)
	_ok("raw=12 无暴击无减伤 → final=12, crit=false",
		is_equal_approx(r.final_damage, 12.0) and not r.crit and is_equal_approx(r.raw_damage, 12.0))
	_ok("未命中任何减伤时 mitigation_factor = 1",
		is_equal_approx(r.mitigation_factor, 1.0))
	_ok("玩家 L1 裸装 AD = 12（GDD 6.2）",
		is_equal_approx(_player.get_attack_damage(), 12.0))
	var r2 := DamageCalc.compute_hit(12.0 * 3.5, 0.0, 150.0, GameConstants.ELEMENT_PHYSICAL,
		0.0, 0.0, 0.0, 1, 0.0)
	_ok("技能基础：AD 12 × 倍率 3.5 = 42",
		is_equal_approx(r2.final_damage, 42.0))


# =============================================================================
# B. 暴击
# =============================================================================

func _test_crit() -> void:
	print("--- B. 暴击 ---")
	_ok("暴击倍率：CD 150% → ×1.5",
		is_equal_approx(DamageCalc.crit_multiplier(true, GameConstants.CRIT_DAMAGE_BASE), 1.5))
	_ok("非暴击倍率恒 1.0",
		is_equal_approx(DamageCalc.crit_multiplier(false, 999.0), 1.0))
	_ok("期望暴击加成：5% × 150% → 1.025（GDD 6.6）",
		is_equal_approx(DamageCalc.expected_crit_multiplier(5.0, 150.0), 1.025))
	_ok("期望暴击加成：75% × 150% → 1.375（cap 内）",
		is_equal_approx(DamageCalc.expected_crit_multiplier(75.0, 150.0), 1.375))
	_ok("期望暴击加成：100% 被 clamp 到 75%",
		is_equal_approx(DamageCalc.expected_crit_multiplier(100.0, 150.0), 1.375))
	_ok("roll_crit(0%) 恒不暴击", not DamageCalc.roll_crit(0.0))
	var hits := 0
	for i in 4000:
		if DamageCalc.roll_crit(5.0):
			hits += 1
	_ok("roll_crit(5%) × 4000 次 ≈ 200（区间 100–400，随机容差）",
		hits >= 100 and hits <= 400)
	# compute_hit 带随机暴击的确定性区间：100 伤 × [1.0, 1.5] ∈ [100, 150]
	var r := DamageCalc.compute_hit(100.0, 100.0, 150.0, GameConstants.ELEMENT_PHYSICAL,
		0.0, 0.0, 0.0, 1, 0.0)
	_ok("compute_hit 随机暴击区间 [100, 150]（chance=100 → clamp 75）",
		r.final_damage >= 100.0 and r.final_damage <= 150.0 + 0.001)


# =============================================================================
# C. 元素
# =============================================================================

func _test_element() -> void:
	print("--- C. 元素 ---")
	_ok("元素系 = 6 类且含 physical/fire/cold/lightning/poison/shadow",
		GameConstants.ELEMENTS.size() == 6
		and GameConstants.ELEMENTS.has("physical")
		and GameConstants.ELEMENTS.has("fire")
		and GameConstants.ELEMENTS.has("cold")
		and GameConstants.ELEMENTS.has("lightning")
		and GameConstants.ELEMENTS.has("poison")
		and GameConstants.ELEMENTS.has("shadow"))
	_ok("物理走护甲：ARM 50 @ L1 → 减伤 50%",
		is_equal_approx(DamageCalc.mitigation_factor(50.0, 0.0, 1, "physical"), 0.5))
	_ok("元素走抗性：抗性 50 @ L1 → 减伤 50%（同构公式）",
		is_equal_approx(DamageCalc.mitigation_factor(0.0, 50.0, 1, "fire"), 0.5))
	_ok("护甲不影响元素伤害：ARM 50 对 fire 无效",
		is_equal_approx(DamageCalc.mitigation_factor(50.0, 0.0, 1, "fire"), 1.0))
	var r := DamageCalc.compute_hit(12.0, 0.0, 150.0, "fire",
		0.0, 0.0, 50.0, 1, 0.0)
	_ok("火伤 12 → 火抗 50 @ L1 → final = 6",
		is_equal_approx(r.final_damage, 6.0))
	var r2 := DamageCalc.compute_hit(12.0, 0.0, 150.0, "fire",
		50.0, 0.0, 0.0, 1, 0.0)
	_ok("元素伤害加成 +50% → final = 18",
		is_equal_approx(r2.final_damage, 18.0) and is_equal_approx(r2.element_multiplier, 1.5))
	_ok("抗性减伤上限 75%（9999 抗 @ L1）",
		is_equal_approx(GameConstants.element_damage_reduction(9999.0, 1), GameConstants.RESIST_DR_CAP))


# =============================================================================
# D. 减伤
# =============================================================================

func _test_mitigation() -> void:
	print("--- D. 减伤 ---")
	_ok("护甲 DR：ARM 50 @ L1 = 50%",
		is_equal_approx(GameConstants.armor_damage_reduction(50.0, 1), 0.5))
	_ok("护甲 DR 上限 95%（巨量护甲不免疫）",
		is_equal_approx(GameConstants.armor_damage_reduction(99999.0, 1), 0.95))
	var r := DamageCalc.compute_hit(100.0, 0.0, 150.0, "physical",
		0.0, 50.0, 0.0, 1, 0.0)
	_ok("物理 100 → ARM 50 → final = 50",
		is_equal_approx(r.final_damage, 50.0))
	var r2 := DamageCalc.compute_hit(100.0, 0.0, 150.0, "physical",
		0.0, 0.0, 0.0, 1, 40.0)
	_ok("额外减伤 40%（守誓者）→ final = 60",
		is_equal_approx(r2.final_damage, 60.0))
	var r3 := DamageCalc.compute_hit(100.0, 0.0, 150.0, "physical",
		0.0, 50.0, 0.0, 1, 40.0)
	_ok("减伤顺序：护甲 50% × 额外 40% 叠乘 → final = 30",
		is_equal_approx(r3.final_damage, 30.0))
	var r4 := DamageCalc.compute_hit(100.0, 0.0, 150.0, "physical",
		0.0, 0.0, 0.0, 1, 200.0)
	_ok("额外减伤 clamp：200% → ×0",
		is_equal_approx(r4.final_damage, 0.0))


# =============================================================================
# E. 接入回归（真实玩家 + 靶子走完整管线）
# =============================================================================

func _test_integration() -> void:
	print("--- E. 接入回归 ---")
	_reset_positions()
	# 普攻：AD 12 × 1.0 → 无甲靶：12（非暴击）或 18（暴击 5%）
	_player.try_attack()
	var p_dmg := _dummy.total_damage_taken
	_ok("普攻走管线：伤害 ∈ {12, 18}（暴击 roll）",
		is_equal_approx(p_dmg, 12.0) or is_equal_approx(p_dmg, 18.0))
	_ok("普攻事件：元素 physical，金额一致",
		not _last_event.is_empty() and _last_event[0] == _dummy
		and is_equal_approx(float(_last_event[1]), p_dmg)
		and String(_last_event[3]) == GameConstants.ELEMENT_PHYSICAL)
	_ok("普攻命中回蓝 +2（回归）",
		is_equal_approx(_player.get_mana_pool().current, 100.0)
		or is_equal_approx(_player.get_mana_pool().current, 102.0))

	# 目标护甲生效：ARM 100 @ L1 → DR = 100/150 = 2/3 → 伤害 ×1/3
	_reset_positions()
	_dummy.armor = 100.0
	_player.try_attack()
	var arm_dmg := _dummy.total_damage_taken
	_ok("目标护甲 100 @ L1 → 普攻 ∈ {4, 6}（×1/3）",
		is_equal_approx(arm_dmg, 4.0) or is_equal_approx(arm_dmg, 6.0))

	# 技能裂斩：AD 12 × 3.5 = 42 → 无甲 ∈ {42, 63}
	_reset_positions()
	_player.get_mana_pool().set_current(100.0)
	_ok("裂斩施放成功", _skills.try_cast("cleave"))
	var s_dmg := _dummy.total_damage_taken
	_ok("裂斩走管线：伤害 ∈ {42, 63}",
		is_equal_approx(s_dmg, 42.0) or is_equal_approx(s_dmg, 63.0))

	# 技能元素改写 → 走目标对应抗性：裂斩改 fire，靶火抗 50 → 伤害减半
	_reset_positions()
	_player.get_mana_pool().set_current(100.0)
	_skills.tick_cooldowns(7.0)
	var sd := _skills.get_skill_data("cleave")
	sd.element = "fire"
	_dummy.resists["fire"] = 50.0
	_ok("火元素裂斩施放成功", _skills.try_cast("cleave"))
	var f_dmg := _dummy.total_damage_taken
	_ok("火裂斩 → 火抗 50 @ L1 → 伤害减半 ∈ {21, 31.5}",
		is_equal_approx(f_dmg, 21.0) or is_equal_approx(f_dmg, 31.5))
	_ok("火元素事件正确透传", not _last_event.is_empty() and String(_last_event[3]) == "fire")


# =============================================================================
# F. GDD 锚点
# =============================================================================

func _test_gdd_anchors() -> void:
	print("--- F. GDD 锚点 ---")
	_ok("DPS 期望暴击乘区 = 1 + CR×(CD-1)，5%/150% → 1.025",
		is_equal_approx(DamageCalc.expected_crit_multiplier(5.0, 150.0), 1.025))
	_ok("护甲 DR 公式锚点：裸装 L1 ARM 6 → 6/56 ≈ 10.714%",
		is_equal_approx(GameConstants.armor_damage_reduction(6.0, 1), 6.0 / 56.0))
	_ok("护甲 DR 公式锚点：裸装 L20 ARM 36.7 → 36.7/1036.7",
		is_equal_approx(GameConstants.armor_damage_reduction(36.7, 20), 36.7 / 1036.7))
	_ok("EHP 演示：HP 150 ÷ (1 − DR 10.714%) ≈ 168",
		is_equal_approx(150.0 / (1.0 - GameConstants.armor_damage_reduction(6.0, 1)), 150.0 / (50.0 / 56.0)))
	_ok("暴击基准常量（用户拍板）：CR 5 / CD 150 / cap 75",
		is_equal_approx(GameConstants.CRIT_CHANCE_BASE, 5.0)
		and is_equal_approx(GameConstants.CRIT_DAMAGE_BASE, 150.0)
		and is_equal_approx(GameConstants.CRIT_CHANCE_CAP, 75.0))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
