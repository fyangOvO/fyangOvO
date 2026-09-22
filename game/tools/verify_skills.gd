## 攻击与技能系统实测（任务 2.2 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_skills.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围：
##   A. 技能表：skills.json 加载 / 形态 / 数值（与用户拍板一致）
##   B. 法力池：初始满 / 消耗 / 不足失败 / 自然回复 / 封顶 / 减耗折扣 / 信号
##   C. 冷却：施放后进入冷却 / 冷却中拒绝 / 计时递减 / 到期可再施放
##   D. 普攻假连段：按住连续挥击（间隔 = 1/攻速）/ 松开停止 / 攻击不打断移动 /
##      闪避打断 / 命中回蓝 / 朝向扇区判定
##   E. 技能效果：裂斩单体 / 旋刃范围+击退 / 突进位移+撞击 / 法力与冷却联动
##   F. 回归：移动 / 朝向 / 闪避不受攻击技能影响
extends Node

const DURATION_FAST := 0.05

var _fail: int = 0
var _player: PlayerController = null
var _mana: ManaPool = null
var _skills: SkillController = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 攻击与技能系统实测 =====")
	# 伤害断言（42 / 16.8 / 12）假设不暴击；固定随机种子使暴击 roll 确定（5% 基线，
	# 该种子下全程不暴击），避免偶发 1.5× 暴击导致断言抖动
	seed(20260916)
	_setup_scene()
	await _test_skill_table()
	await _test_mana_pool()
	await _test_cooldowns()
	await _test_attack_combo()
	await _test_skill_effects()
	await _test_regression()
	_finish()


func _setup_scene() -> void:
	_player = get_node_or_null("/root/VerifySkills/Player") as PlayerController
	_mana = _player.get_mana_pool()
	_skills = _player.get_skill_controller()
	_ok("场景就绪：玩家 + 法力池 + 技能控制器", _player != null and _mana != null and _skills != null)


# =============================================================================
# A. 技能表
# =============================================================================

func _test_skill_table() -> void:
	print("--- A. 技能表 ---")
	var ids := ConfigLoader.get_all_skill_ids()
	_ok("技能表 = 12 条（3 老出战 + 9 备选池，步骤 3 职业专属）", ids.size() == 12)
	_ok("技能 ID 稳定排序（字母序，含 12 个）",
		ids == ["arrow_rain", "cleave", "dash_strike", "fireball", "frost_nova",
			"lightning_chain", "piercing_shot", "poison_cloud", "power_strike",
			"shadow_blink", "spin_slash", "venom_shot"])
	_ok("出战栏 1/2/3 = 裂斩/旋刃/突进（无存档回退战士默认栏）",
		_skills.get_skill_id_at(0) == "cleave"
		and _skills.get_skill_id_at(1) == "spin_slash"
		and _skills.get_skill_id_at(2) == "dash_strike")
	var all_valid := true
	for sid in ids:
		var sd := ConfigLoader.get_skill(sid)
		if sd == null or not sd.validate().is_empty():
			all_valid = false
	_ok("全部技能数据合法（validate 空）", all_valid)

	var cleave := ConfigLoader.get_skill("cleave")
	var spin := ConfigLoader.get_skill("spin_slash")
	var dash := ConfigLoader.get_skill("dash_strike")
	_ok("裂斩：单体 350% / 6s / 30 蓝",
		cleave != null and cleave.type == SkillData.SkillType.SINGLE
		and is_equal_approx(cleave.multiplier, 3.5) and is_equal_approx(cleave.cooldown, 6.0)
		and is_equal_approx(cleave.mana_cost, 30.0) and cleave.slot == 1)
	_ok("旋刃：范围 140% / 3s / 15 蓝 / 半径 48",
		spin != null and spin.type == SkillData.SkillType.AOE
		and is_equal_approx(spin.multiplier, 1.4) and is_equal_approx(spin.cooldown, 3.0)
		and is_equal_approx(spin.mana_cost, 15.0) and is_equal_approx(spin.radius, 48.0)
		and spin.slot == 2)
	_ok("突进：位移 100% / 8s / 20 蓝 / 冲刺 96",
		dash != null and dash.type == SkillData.SkillType.DASH
		and is_equal_approx(dash.multiplier, 1.0) and is_equal_approx(dash.cooldown, 8.0)
		and is_equal_approx(dash.mana_cost, 20.0) and is_equal_approx(dash.dash_distance, 96.0)
		and dash.slot == 3)
	_ok("技能栏 1/2/3 对应裂斩/旋刃/突进",
		_skills.get_skill_id_at(0) == "cleave"
		and _skills.get_skill_id_at(1) == "spin_slash"
		and _skills.get_skill_id_at(2) == "dash_strike")

	# 6.4 + 步骤 3 技能库：9 个备选技能（slot 0）覆盖三形态 + 多元素 + 职业专属
	var frost := ConfigLoader.get_skill("frost_nova")
	var fireball := ConfigLoader.get_skill("fireball")
	var chain := ConfigLoader.get_skill("lightning_chain")
	var cloud := ConfigLoader.get_skill("poison_cloud")
	var blink := ConfigLoader.get_skill("shadow_blink")
	var strike := ConfigLoader.get_skill("power_strike")
	var pierce := ConfigLoader.get_skill("piercing_shot")
	var rain := ConfigLoader.get_skill("arrow_rain")
	var venom := ConfigLoader.get_skill("venom_shot")
	_ok("备选技能 9 个且 slot = 0（不占出战栏位）",
		frost != null and fireball != null and chain != null and cloud != null and blink != null
		and strike != null and pierce != null and rain != null and venom != null
		and frost.slot == 0 and fireball.slot == 0 and chain.slot == 0
		and cloud.slot == 0 and blink.slot == 0
		and strike.slot == 0 and pierce.slot == 0 and rain.slot == 0 and venom.slot == 0)
	_ok("备选覆盖三形态（冰环 AoE / 火球单体 / 暗影步位移）",
		frost.type == SkillData.SkillType.AOE
		and fireball.type == SkillData.SkillType.SINGLE
		and blink.type == SkillData.SkillType.DASH)
	_ok("备选覆盖四元素（冰 / 火 / 雷 / 毒 / 影）",
		frost.element == "cold" and fireball.element == "fire"
		and chain.element == "lightning" and cloud.element == "poison"
		and blink.element == "shadow")
	_ok("备选数值合理（火球 240% / 冰环半径 64 / 毒云 85% / 暗影步冲刺 120）",
		is_equal_approx(fireball.multiplier, 2.4)
		and is_equal_approx(frost.radius, 64.0)
		and is_equal_approx(cloud.multiplier, 0.85)
		and is_equal_approx(blink.dash_distance, 120.0))
	# 步骤 3 职业专属：战士蓄力斩 / 弓手三技
	_ok("蓄力斩：单体 500% / 8s / 35 蓝 / 击退 30（战士）",
		strike != null and strike.type == SkillData.SkillType.SINGLE
		and is_equal_approx(strike.multiplier, 5.0) and is_equal_approx(strike.cooldown, 8.0)
		and is_equal_approx(strike.mana_cost, 35.0) and is_equal_approx(strike.knockback, 30.0))
	_ok("穿透箭：单体 220% / 4.5s / 16 蓝 / 射程 150（弓手）",
		pierce != null and pierce.type == SkillData.SkillType.SINGLE
		and is_equal_approx(pierce.multiplier, 2.2) and is_equal_approx(pierce.cooldown, 4.5)
		and is_equal_approx(pierce.mana_cost, 16.0) and is_equal_approx(pierce.range, 150.0))
	_ok("箭雨：范围 100% / 6s / 22 蓝 / 半径 72（弓手）",
		rain != null and rain.type == SkillData.SkillType.AOE
		and is_equal_approx(rain.multiplier, 1.0) and is_equal_approx(rain.cooldown, 6.0)
		and is_equal_approx(rain.mana_cost, 22.0) and is_equal_approx(rain.radius, 72.0))
	_ok("淬毒箭：单体 160% / 5s / 18 蓝 / 毒元素（弓手）",
		venom != null and venom.type == SkillData.SkillType.SINGLE
		and is_equal_approx(venom.multiplier, 1.6) and is_equal_approx(venom.cooldown, 5.0)
		and is_equal_approx(venom.mana_cost, 18.0) and venom.element == "poison")


# =============================================================================
# B. 法力池
# =============================================================================

func _test_mana_pool() -> void:
	print("--- B. 法力池 ---")
	_mana.set_current(100.0)
	_ok("初始法力 = 100 / 100", is_equal_approx(_mana.current, 100.0) and is_equal_approx(_mana.maximum, 100.0))
	_ok("消耗 30 成功 → 70", _mana.try_spend(30.0) and is_equal_approx(_mana.current, 70.0))
	_ok("消耗 80 失败（不足）且法力不变",
		not _mana.try_spend(80.0) and is_equal_approx(_mana.current, 70.0))
	_mana.set_current(50.0)
	_mana.tick_regen(2.5)
	_ok("自然回复 4/s × 2.5s = +10 → 60", is_equal_approx(_mana.current, 60.0))
	_mana.set_current(99.0)
	_mana.restore(20.0)
	_ok("restore 封顶到 max（100）", is_equal_approx(_mana.current, 100.0))
	_mana.apply_stats(0.0, 0.0, 0.5)
	_mana.set_current(100.0)
	_ok("减耗 50%：消耗 30 只扣 15", _mana.try_spend(30.0) and is_equal_approx(_mana.current, 85.0))
	_mana.apply_stats(0.0, 0.0, 0.0) # 复位
	_mana.set_current(100.0)


# =============================================================================
# C. 冷却
# =============================================================================

func _test_cooldowns() -> void:
	print("--- C. 冷却 ---")
	# 用旋刃（3s / 15 蓝）做冷却测试，法力充足
	_mana.set_current(100.0)
	_ok("施放旋刃成功", _skills.try_cast("spin_slash"))
	_ok("旋刃冷却 = 3.0", is_equal_approx(_skills.get_cooldown_remaining("spin_slash"), 3.0))
	_ok("冷却中拒绝再次施放（法力足够）",
		not _skills.try_cast("spin_slash") and is_equal_approx(_mana.current, 85.0))
	_skills.tick_cooldowns(1.5)
	_ok("冷却计时递减 → 1.5", is_equal_approx(_skills.get_cooldown_remaining("spin_slash"), 1.5))
	_skills.tick_cooldowns(1.5)
	_ok("冷却到期 = 0", is_equal_approx(_skills.get_cooldown_remaining("spin_slash"), 0.0))
	_ok("到期后可再次施放", _skills.try_cast("spin_slash"))
	_skills.tick_cooldowns(5.0) # 清冷却，避免影响后续
	_mana.set_current(100.0)


# =============================================================================
# D. 普攻假连段
# =============================================================================

func _test_attack_combo() -> void:
	print("--- D. 普攻假连段 ---")
	var dummy := get_node_or_null("/root/VerifySkills/DummyFront") as DamageDummy
	dummy.reset()
	dummy.global_position = Vector2(0, 40) # 复位（C 段旋刃击退过它）
	# 2.5 半径扩展后 C 段两次旋刃会把 DummyBehind 击退到 (0,-12)，与玩家 (0,0) 重叠，
	# 首个物理帧会被物理引擎分离推开（Node 与物理体不同步）——先移远排除干扰
	var dummy_behind := get_node_or_null("/root/VerifySkills/DummyBehind") as DamageDummy
	dummy_behind.global_position = Vector2(0, -200)
	# 把玩家放到原点朝下（DummyFront 在正下方 40px）
	_player.global_position = Vector2(0, 0)
	_player.velocity = Vector2.ZERO
	_player.set_facing(PlayerController.Facing8.DOWN)
	_player._attack_timer = 0.0 # 清计时（测试脚本直接读内部字段）

	_ok("按住攻击 → 立即挥出第一击（伤害 = 12 × 1.0）",
		_player.try_attack() and is_equal_approx(dummy.total_damage_taken, 12.0))
	_ok("攻击后间隔内 try_attack 被拒（攻速 1.0/s）", not _player.try_attack())
	# 模拟按住 2.2s：0s / 1.0s / 2.0s 三击
	var hit_count := 1
	var elapsed := 0.0
	Input.action_press(GameConstants.ACTION_ATTACK)
	while elapsed < 2.2:
		_player._tick_attack(DURATION_FAST)
		elapsed += DURATION_FAST
	Input.action_release(GameConstants.ACTION_ATTACK)
	_ok("按住 2.2s → 共挥击 3 次（0s / 1.0s / 2.0s）", dummy.damage_log.size() >= 3)
	hit_count = dummy.damage_log.size()
	# 松开后 1.5s 不再挥击
	elapsed = 0.0
	while elapsed < 1.5:
		_player._tick_attack(DURATION_FAST)
		elapsed += DURATION_FAST
	_ok("松开后不再挥击", dummy.damage_log.size() == hit_count)

	# 攻击中可移动：按住攻击 + 移动键 → 水平速度 > 0
	Input.action_press(GameConstants.ACTION_ATTACK)
	Input.action_press(&"move_right")
	await _step_physics(0.3)
	_ok("攻击中可移动（按住攻击 + 右移 → vx > 0）", _player.velocity.x > 0.0)
	Input.action_release(&"move_right")
	Input.action_release(GameConstants.ACTION_ATTACK)
	await _step_physics(0.5)
	_player.velocity = Vector2.ZERO
	_player.global_position = Vector2(0, 0) # 复位（移动测试改变了位置）

	# 闪避打断：攻击后立刻闪避，攻击计时清零且闪避中不挥击
	_player._attack_timer = 0.6
	_ok("闪避打断攻击计时（timer 清零）", _player.try_dodge() and _player._attack_timer == 0.0)
	_player._tick_attack(0.1)
	_ok("闪避中不挥击", _player._attack_timer == 0.0)
	await _step_physics(1.2) # 等闪避结束

	# 普攻命中回蓝（先复位玩家位置——闪避测试把玩家冲到了 (0,88)）
	_player.global_position = Vector2(0, 0)
	_player.velocity = Vector2.ZERO
	_player.set_facing(PlayerController.Facing8.DOWN)
	_mana.set_current(50.0)
	_player.try_attack()
	_ok("普攻命中回蓝 +2（50 → 52）", is_equal_approx(_mana.current, 52.0))
	_mana.set_current(100.0)

	# 朝向扇区：背对目标不命中
	dummy.reset()
	_player.set_facing(PlayerController.Facing8.UP) # 朝上，dummy 在下方
	_player.try_attack()
	_ok("背对目标不命中（60° 扇区判定）", dummy.total_damage_taken == 0.0)
	_player.set_facing(PlayerController.Facing8.DOWN)


# =============================================================================
# E. 技能效果
# =============================================================================

func _test_skill_effects() -> void:
	print("--- E. 技能效果 ---")
	var dummy_front := get_node_or_null("/root/VerifySkills/DummyFront") as DamageDummy
	var dummy_far := get_node_or_null("/root/VerifySkills/DummyFar") as DamageDummy
	var dummy_behind := get_node_or_null("/root/VerifySkills/DummyBehind") as DamageDummy
	# 复位全部位置与状态（D 段的移动 / 击退改动了它们）
	_player.global_position = Vector2(0, 0)
	_player.velocity = Vector2.ZERO
	dummy_front.global_position = Vector2(0, 40)
	dummy_far.global_position = Vector2(0, 100)
	dummy_behind.global_position = Vector2(0, -60)

	# 裂斩：单体命中前方 96px 内最近目标（3.5 × 12 = 42）
	dummy_front.reset()
	dummy_behind.reset()
	_mana.set_current(100.0)
	_player.set_facing(PlayerController.Facing8.DOWN)
	_ok("裂斩施放成功且扣蓝 30", _skills.try_cast("cleave") and is_equal_approx(_mana.current, 70.0))
	_ok("裂斩命中前方目标：伤害 42", is_equal_approx(dummy_front.total_damage_taken, 42.0))
	_ok("裂斩未命中背后目标", dummy_behind.total_damage_taken == 0.0)
	_skills.tick_cooldowns(7.0)
	_mana.set_current(100.0)

	# 裂斩背对目标：施放成功（扣蓝进冷却）但无伤害
	dummy_front.reset()
	_player.set_facing(PlayerController.Facing8.UP)
	_ok("背对时裂斩仍施放（扣蓝）", _skills.try_cast("cleave") and is_equal_approx(_mana.current, 70.0))
	_ok("背对时裂斩无命中", dummy_front.total_damage_taken == 0.0)
	_skills.tick_cooldowns(7.0)
	_mana.set_current(100.0)

	# 旋刃：半径 48 内全体命中（1.4 × 12 = 16.8），远处不中，附带击退 24
	dummy_front.reset()
	dummy_far.reset()
	_player.set_facing(PlayerController.Facing8.DOWN)
	var front_before := dummy_front.global_position
	_ok("旋刃施放成功", _skills.try_cast("spin_slash"))
	_ok("旋刃命中半径内目标：伤害 16.8", is_equal_approx(dummy_front.total_damage_taken, 16.8))
	_ok("旋刃未命中半径外目标", dummy_far.total_damage_taken == 0.0)
	_ok("旋刃击退目标 24px", dummy_front.global_position.distance_to(front_before) >= 20.0)
	_skills.tick_cooldowns(4.0)
	_mana.set_current(100.0)

	# 突进：撞到前方目标 → 伤害 12 + 击退 48；玩家被挡（位移 < 96）
	dummy_front.reset()
	dummy_front.global_position = Vector2(0, 44)
	# 2.5 半径扩展后旋刃会命中并击退 DummyBehind 到 (0,-36)，与玩家碰撞框仅差 2px，
	# 物理引擎会在 dash 启动时把它当重叠体推开（玩家水平滑出）——移远排除干扰
	dummy_behind.global_position = Vector2(0, -120)
	_player.set_facing(PlayerController.Facing8.DOWN)
	# Godot 的 global_position setter 延迟同步物理体到下一次物理步进；前面 D 段物理帧
	# 已把玩家物理体带到远处，同帧 dash（move_and_collide）会从旧物理位置出发——
	# await 一帧让物理体与 Node 对齐（无重叠则玩家不动）
	await get_tree().physics_frame
	var player_before := _player.global_position
	_ok("突进施放成功", _skills.try_cast("dash_strike"))
	_ok("突进命中撞击目标：伤害 12", is_equal_approx(dummy_front.total_damage_taken, 12.0))
	_ok("突进玩家位移 < 96（被目标阻挡）", _player.global_position.distance_to(player_before) < 96.0
		and _player.global_position.distance_to(player_before) > 20.0)
	_skills.tick_cooldowns(9.0)
	_mana.set_current(100.0)

	# 法力与冷却联动
	_mana.set_current(10.0)
	_ok("法力不足（10 < 30）拒绝施放裂斩", not _skills.try_cast("cleave"))
	_mana.set_current(100.0)


# =============================================================================
# F. 回归
# =============================================================================

func _test_regression() -> void:
	print("--- F. 回归 ---")
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	Input.action_press(&"move_down")
	await _step_physics(0.4)
	_ok("移动回归：朝下速度 vy > 0", _player.velocity.y > 0.0)
	Input.action_release(&"move_down")
	await _step_physics(0.5)
	_player.velocity = Vector2.ZERO

	_ok("闪避回归：闪避成功开启无敌帧", _player.try_dodge() and _player.is_invulnerable())
	await _step_physics(1.0)


func _step_physics(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		await get_tree().physics_frame
		remaining -= get_physics_process_delta_time()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
