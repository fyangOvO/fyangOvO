## 生命 / 护盾 / 异常状态实测（任务 2.6 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_health.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（25 项断言、6 个测试段）：
##   A. 属性锚点：玩家 L1 max_hp 150 / 护甲 6 / 抗性 0 / 闪避 0 / 格挡 0 / 初始满血
##   B. 减伤链：护甲 DR（5.61 → 5.01）→ 闪避无敌帧免疫 → 无敌解除恢复受击
##   C. 护盾：先吸收（过减伤）→ 耗尽后扣血
##   D. 异常状态：中毒 dot / 冰冻减速乘区 / 燃烧 dot / 同类刷新时长不叠加
##   E. 死亡：致命伤 → is_dead + player_died 广播 → 死后受击无效 + 移动停止
##   F. 敌人接入：毒史莱姆攻击玩家扣血（减伤后）+ 附加中毒 dot
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null
var _died_count: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 生命 / 护盾 / 异常状态实测 =====")
	seed(20260916) # 固定随机：毒附加 / dot 判定的概率测试需要可复现
	_player = get_node_or_null("/root/VerifyHealth/Player") as PlayerController
	_ok("场景就绪：玩家 + 生命组件", _player != null and _player.health != null)
	EventBus.player_died.connect(func(_r: String) -> void: _died_count += 1)
	await _test_attributes()
	await _test_damage_chain()
	await _test_shield()
	await _test_ailments()
	await _test_enemy_integration()
	await _test_death()
	_finish()


## 生成敌人（L1 / NM1，出生在 pos）
func _spawn_enemy(mid: String, pos: Vector2) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.monster_id = mid
	e.level = 1
	e.difficulty_tier = GameConstants.DifficultyTier.NM1
	add_child(e)
	e.global_position = pos
	return e


## 玩家复位：位置 / 朝向 / 攻速计时 / 法力 / 生命（满血 + 清盾 + 清异常 + 复活）
func _reset_player() -> void:
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	_player._attack_timer = 0.0
	_player.set_facing(PlayerController.Facing8.DOWN)
	_player.get_mana_pool().set_current(100.0)
	_player.health.current_hp = _player.get_max_hp()
	_player.health.shield = 0.0
	_player.health.is_dead = false
	_player.health._ailments.clear()
	_player.health.regeneration_per_second = 0.0


## 推进指定秒数的物理帧（约 60 帧/秒；dot 在 process 帧 tick，物理帧近似同步）
func _step_physics(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for i in range(frames):
		await get_tree().physics_frame


# =============================================================================
# A. 属性锚点
# =============================================================================

func _test_attributes() -> void:
	print("--- A. 属性锚点 ---")
	_ok("玩家 L1 max_hp = 150（GDD 6.2）", absf(_player.get_max_hp() - 150.0) < 0.01)
	_ok("出生即满血", absf(_player.get_current_hp() - _player.get_max_hp()) < 0.01)
	_ok("护甲 = 6（GDD 6.2）", absf(_player.get_armor() - 6.0) < 0.001)
	_ok("元素抗性 = 0（阶段 3 词缀接入）", _player.get_resist("fire") == 0.0)
	_ok("闪避率 / 格挡率 = 0（基础）",
		_player.get_dodge_chance() == 0.0 and _player.get_block_chance() == 0.0)
	_ok("护盾初始 = 0", _player.get_shield() == 0.0)


# =============================================================================
# B. 减伤链
# =============================================================================

func _test_damage_chain() -> void:
	print("--- B. 减伤链 ---")
	_reset_player()
	var src := Node.new()
	add_child(src)
	_player.take_damage(5.61, src)
	# DR = ARM/(ARM+50L) = 6/56 = 0.10714 → 5.61 × 0.892857 = 5.0089
	_ok("物理攻击过护甲减伤：5.61 → ≈5.01（DR 6/56）",
		absf(_player.get_current_hp() - (150.0 - 5.0089)) < 0.01)
	_info("      当前 HP = %.2f（期望 %.2f）" % [_player.get_current_hp(), 150.0 - 5.0089])

	# 闪避无敌帧：免疫
	_reset_player()
	_player.try_dodge()
	_player.take_damage(5.61, src)
	_ok("闪避无敌帧内免疫伤害", absf(_player.get_current_hp() - 150.0) < 0.01)
	await _step_physics(0.4)  # 无敌帧 0.3s 结束
	_player.take_damage(5.61, src)
	_ok("无敌结束后恢复受击", absf(_player.get_current_hp() - (150.0 - 5.0089)) < 0.01)
	src.queue_free()


# =============================================================================
# C. 护盾
# =============================================================================

func _test_shield() -> void:
	print("--- C. 护盾 ---")
	_reset_player()
	var src := Node.new()
	add_child(src)
	_player.health.grant_shield(20.0)
	_player.take_damage(10.0, src)
	# 减伤后 10×0.892857=8.93 进护盾：盾 20−8.93=11.07、生命不变
	_ok("护盾先吸收（过减伤后）：生命不变、盾 ≈11.07",
		absf(_player.get_current_hp() - 150.0) < 0.01
		and absf(_player.get_shield() - 11.0714) < 0.05)
	_player.take_damage(15.0, src)
	# 15×0.892857=13.39 → 盾吃 11.07、剩余 2.32 扣血 → HP 147.68
	_ok("护盾耗尽后剩余伤害扣血",
		absf(_player.get_shield() - 0.0) < 0.01
		and absf(_player.get_current_hp() - 147.6786) < 0.05)
	src.queue_free()


# =============================================================================
# D. 异常状态
# =============================================================================

func _test_ailments() -> void:
	print("--- D. 异常状态 ---")
	_reset_player()
	_player.health.apply_ailment_raw(GameConstants.AILMENT_POISON, 10.0, 3.0)
	_ok("中毒生效（dot 10/s × 3s）", _player.health.has_ailment(GameConstants.AILMENT_POISON))
	await _step_physics(1.0)
	_ok("中毒 1s 扣血 ≈ 10", absf(150.0 - _player.get_current_hp() - 10.0) < 0.5)
	_info("      当前 HP = %.2f（期望 ≈140.0）" % _player.get_current_hp())

	# 冰冻减速：独立复位（清掉前面的中毒），到期多等 0.2s 覆盖帧对齐边界
	_reset_player()
	_player.health.apply_ailment_raw(GameConstants.AILMENT_SLOW, 0.0, 2.0)
	_ok("冰冻减速乘区 = 0.6（减速 40%）",
		absf(_player.health.get_move_speed_factor() - 0.6) < 0.001)
	await _step_physics(2.2)
	_ok("冰冻到期解除，乘区恢复 1.0",
		absf(_player.health.get_move_speed_factor() - 1.0) < 0.001)

	_reset_player()
	_player.health.apply_ailment_raw(GameConstants.AILMENT_BURN, 5.0, 2.0)
	await _step_physics(2.0)
	_ok("燃烧 2s 扣血 ≈ 10（5/s × 2s）", absf(150.0 - _player.get_current_hp() - 10.0) < 0.5)

	_reset_player()
	_player.health.apply_ailment_raw(GameConstants.AILMENT_POISON, 10.0, 3.0)
	await _step_physics(1.0)
	_player.health.apply_ailment_raw(GameConstants.AILMENT_POISON, 10.0, 3.0)
	_ok("同类异常刷新时长不叠加（重新计时到 3s）",
		absf(_player.health.get_ailment_remaining(GameConstants.AILMENT_POISON) - 3.0) < 0.1)


# =============================================================================
# F. 敌人接入：元素攻击 + 异常
# =============================================================================

func _test_enemy_integration() -> void:
	print("--- F. 敌人接入：元素攻击 + 异常 ---")
	_reset_player()
	# 毒史莱姆在玩家下方 30px（攻击弧：facing DOWN + attack_range 32 + 目标半径 11 → 命中）
	var slime := _spawn_enemy("slime_acid", Vector2(0, 30))
	await get_tree().physics_frame  # 敌人在 _physics_process 刷新 _player 引用
	slime.set_physics_process(false)  # 冻结状态机：dot 期间敌人不动，保证断言确定
	slime.call("_attack_player")
	# DMG = 5.61 × 1.125（damage_scale）= 6.31125 → 减伤 ×0.892857 = 5.634
	_ok("毒史莱姆攻击扣血 ≈ 5.63（150 → 144.37）",
		absf(_player.get_current_hp() - (150.0 - 5.6342)) < 0.1)
	_info("      当前 HP = %.2f（期望 ≈144.37）" % _player.get_current_hp())
	_ok("毒元素攻击附加中毒异常",
		_player.health.has_ailment(GameConstants.AILMENT_POISON))
	await _step_physics(1.0)
	# dot = 6.31125 × 0.20 = 1.262/s
	_ok("中毒 dot 1s 扣血 ≈ 1.26",
		absf(_player.get_current_hp() - (144.3658 - 1.2623)) < 0.3)
	slime.queue_free()


# =============================================================================
# E. 死亡
# =============================================================================

func _test_death() -> void:
	print("--- E. 死亡 ---")
	_reset_player()
	var died_before := _died_count
	var src := Node.new()
	add_child(src)
	_player.take_damage(999.0, src)
	_ok("致命伤 → 死亡（is_dead + HP 0）",
		_player.health.is_dead and _player.get_current_hp() == 0.0)
	_ok("死亡广播 player_died（事件 +1）", _died_count == died_before + 1)
	_player.take_damage(50.0, src)
	_ok("死亡后受击无效（HP 保持 0）", _player.get_current_hp() == 0.0)
	_player.velocity = Vector2(50.0, 0.0)
	await _step_physics(0.2)
	_ok("死亡后移动停止（velocity 归零）", _player.velocity.length() < 0.001)
	src.queue_free()


func _finish() -> void:
	print("")
	if _fail == 0:
		print("===== 结果：0 项失败 =====")
	else:
		print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
