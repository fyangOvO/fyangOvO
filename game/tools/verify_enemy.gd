## 敌人 AI 基类实测（任务 2.4 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_enemy.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围：
##   A. 数据：EnemyBase 从 MonsterData 加载（spider_cave 字段锚点），HP 公式正确
##   B. 状态机：出生 PATROL → 玩家入 AGGRO → CHASE → 入 attack_range → ATTACK →
##      玩家远离 → 回 PATROL
##   C. 移动：CHASE 速度 = move_speed；ATTACK 停住
##   D. 受击契约：take_damage 扣血 / 玩家普攻与技能真实命中敌人 / apply_knockback /
##      死亡发 unit_died + 移除 / 死后无视受击
##   E. 攻击：ATTACK 状态按 attack_interval 输出 damage_taken 事件（带元素），
##      玩家 2.6 前无生命组件不崩
##   F. 回归：玩家移动 / 技能不受敌人存在影响
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null
var _enemy: EnemyBase = null
var _died_events: Array = []
var _taken_events: Array = []


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 敌人 AI 基类实测 =====")
	_player = get_node_or_null("/root/VerifyEnemy/Player") as PlayerController
	_ok("场景就绪：玩家已加入 player 组", _player != null and _player.is_in_group(&"player"))
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.damage_taken.connect(_on_damage_taken)
	await _test_data()
	await _test_state_machine()
	await _test_movement()
	await _test_take_damage()
	await _test_attack()
	await _test_regression()
	_finish()


func _on_unit_died(unit: Node, killer: Node) -> void:
	_died_events.append([unit, killer])


func _on_damage_taken(source: Node, amount: float, element: String) -> void:
	_taken_events.append([source, amount, element])


## 生成一只 spider_cave（L1 / NM1），出生在 pos
func _spawn_enemy(pos: Vector2) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.monster_id = "spider_cave"
	e.level = 1
	e.difficulty_tier = GameConstants.DifficultyTier.NM1
	add_child(e)
	e.global_position = pos
	return e


## 玩家复位：位置 / 朝向 / 攻速计时（否则 try_attack 被 _attack_timer 拒绝）
func _reset_player() -> void:
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	_player._attack_timer = 0.0
	_player.set_facing(PlayerController.Facing8.DOWN)


## 等 N 个物理帧
func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# =============================================================================
# A. 数据
# =============================================================================

func _test_data() -> void:
	print("--- A. 数据 ---")
	_enemy = _spawn_enemy(Vector2(0, 0))
	_ok("怪物数据加载成功（spider_cave）", _enemy.data != null)
	_ok("移动速度 = 75 px/s", is_equal_approx(_enemy.data.move_speed, 75.0))
	_ok("攻击间隔 = 1.2 s", is_equal_approx(_enemy.data.attack_interval, 1.2))
	_ok("攻击距离 = 34 px", is_equal_approx(_enemy.data.attack_range, 34.0))
	_ok("元素 = physical", _enemy.data.element == GameConstants.ELEMENT_PHYSICAL)
	_ok("初始状态 = PATROL", _enemy.state == EnemyBase.AIState.PATROL)
	_ok("已加入 enemies 组", _enemy.is_in_group(&"enemies"))
	var expect_hp := _enemy.data.get_hp(1, GameConstants.DifficultyTier.NM1)
	_ok("HP = get_hp(1, NM1) = 100.7（基线 × hp_scale × 档位 × 难度）",
		is_equal_approx(expect_hp, 100.7) and is_equal_approx(_enemy.current_hp, expect_hp))
	_ok("占位美术已生成（32×32 色块）", _enemy.get_node("Body").texture != null)
	await _wait_frames(2)


# =============================================================================
# B. 状态机
# =============================================================================

func _test_state_machine() -> void:
	print("--- B. 状态机 ---")
	# 玩家放远 → 保持 PATROL 且不离开巡逻半径
	_reset_player()
	_player.global_position = Vector2(500, 500)
	await _wait_frames(3)
	_ok("玩家远离时保持 PATROL", _enemy.state == EnemyBase.AIState.PATROL)
	_ok("巡逻位移限制在半径内（≤ PATROL_RADIUS + 容差）",
		_enemy.global_position.distance_to(Vector2.ZERO) <= GameConstants.ENEMY_PATROL_RADIUS + 6.0)

	# 玩家进入 AGGRO → CHASE
	_reset_player()
	_player.global_position = Vector2(0, 50)
	await _wait_frames(3)
	_ok("玩家进入 AGGRO(160) → CHASE", _enemy.state == EnemyBase.AIState.CHASE)

	# 玩家进入 attack_range → ATTACK
	_player.global_position = Vector2(0, 20)
	await _wait_frames(3)
	_ok("玩家进入 attack_range(34) → ATTACK", _enemy.state == EnemyBase.AIState.ATTACK)

	# 玩家远离超过 LOSE → 回 PATROL
	_player.global_position = Vector2(0, 500)
	await _wait_frames(3)
	_ok("玩家远离 LOSE(240) → 回 PATROL", _enemy.state == EnemyBase.AIState.PATROL)


# =============================================================================
# C. 移动
# =============================================================================

func _test_movement() -> void:
	print("--- C. 移动 ---")
	# CHASE：玩家在 80px 外，朝玩家直线移动，速度 ≈ move_speed(75)
	_reset_player()
	_player.global_position = Vector2(0, 80)
	await _wait_frames(3)
	_ok("追击状态就绪", _enemy.state == EnemyBase.AIState.CHASE)
	var p0 := _enemy.global_position
	await _wait_frames(10)
	var moved := _enemy.global_position.distance_to(p0)
	_info("10 帧位移 = %.2f px（期望 ≈ 12.5）" % moved)
	_ok("追击速度 ≈ 75 px/s（10 帧位移 8–17px）", moved >= 8.0 and moved <= 17.0)
	_ok("追击方向朝向玩家（玩家在下方 → y 增大）", _enemy.global_position.y > p0.y)

	# ATTACK：停住不动
	_player.global_position = Vector2(0, 20)
	await _wait_frames(3)
	_ok("攻击状态就绪", _enemy.state == EnemyBase.AIState.ATTACK)
	var p1 := _enemy.global_position
	await _wait_frames(5)
	_ok("攻击期间停住（位移 ≤ 0.1）",
		_enemy.global_position.distance_to(p1) <= 0.1)


# =============================================================================
# D. 受击契约
# =============================================================================

func _test_take_damage() -> void:
	print("--- D. 受击契约 ---")
	# 直接契约调用：take_damage 扣血
	_enemy.current_hp = 100.0
	_enemy.take_damage(20.0, _player)
	_ok("take_damage(20) → HP 80", is_equal_approx(_enemy.current_hp, 80.0))

	# 玩家普攻真实命中敌人（armor 0 → 12 或 18）
	_reset_player()
	_player.global_position = Vector2(0, 0)
	_enemy.global_position = Vector2(0, 38)
	_enemy.current_hp = 100.0
	_player.try_attack()
	await _wait_frames(2)
	_info("普攻后敌人 HP = %.2f" % _enemy.current_hp)
	_ok("普攻命中敌人：HP ∈ {88, 82}（12/18）",
		is_equal_approx(_enemy.current_hp, 88.0) or is_equal_approx(_enemy.current_hp, 82.0))

	# 技能裂斩真实命中（42/63）
	_reset_player()
	_player.get_mana_pool().set_current(100.0)
	_enemy.global_position = Vector2(0, 38)
	_enemy.current_hp = 100.0
	var cast_ok := _player.get_skill_controller().try_cast("cleave")
	await _wait_frames(2)
	_info("裂斩后敌人 HP = %.2f" % _enemy.current_hp)
	_ok("裂斩命中敌人：HP ∈ {58, 37}（42/63）", cast_ok
		and (is_equal_approx(_enemy.current_hp, 58.0) or is_equal_approx(_enemy.current_hp, 37.0)))

	# 击退
	# ⚠️ 2026-09-21「碰撞线收口」把 `EnemyBase.apply_knockback` 从
	#    `position += offset`（**瞬移**，会穿墙）改成「独立击退通道 + `move_and_slide()`」
	#    ⇒ 调用**当帧不再位移**，位移由随后的物理帧完成。
	#    旧断言 `is_equal_approx(global_position.x, before_x + 10.0)` 是「同帧精确 +10px」，
	#    它钉住的**正是被修掉的那个 bug** ⇒ 改成「当帧不瞬移」。
	#    击退的完整契约（位移量级 / 衰减停止 / 不残留到 AI 通道 / **撞墙不穿**）
	#    已迁到 `tools/verify_knockback.gd`，那里用自建极简世界测得更干净。
	var before_x := _enemy.global_position.x
	_enemy.apply_knockback(Vector2(10, 0))
	_ok("apply_knockback 当帧不瞬移（改通道后的新契约）",
		is_equal_approx(_enemy.global_position.x, before_x))

	# 死亡：unit_died 事件 + 节点移除 + 死亡瞬间忽略补刀
	_died_events.clear()
	_enemy.current_hp = 5.0
	_enemy.take_damage(10.0, _player)
	_enemy.take_damage(1.0, _player)  # 同帧补刀：is_dead=true → return（queue_free 帧末才执行）
	await _wait_frames(2)
	_ok("死亡触发 unit_died 事件（killer=玩家，补刀不重复触发）",
		_died_events.size() == 1 and _died_events[0][0] == _enemy and _died_events[0][1] == _player)
	_ok("死亡后节点已移除", not is_instance_valid(_enemy))


# =============================================================================
# E. 攻击
# =============================================================================

## ⚠️ 本段同时是「敌人碰撞形状」的**边界守卫** —— 改动 `enemy_base.tscn` 的碰撞前请先读完。
##
## 现象（2026-09-18 实测）：给 `enemy_base.tscn` 的 CollisionShape2D 补上缺失的
## `type="CollisionShape2D"`（该节点是全项目**唯一**漏写 `type=` 的节点，此前被当成
## 普通 `Node` 建出来、`shape` 应用失败、节点被丢弃 ⇒ 敌人**没有任何碰撞形状**），
## 结果：
##   - 每关 42 条 `Node './CollisionShape2D' was modified from inside an instance,
##     but it has vanished` 警告消失（证明此前确实是坏的）；
##   - **本段立刻变红**：玩家形状（`player.tscn` 的 RectangleShape2D(20,22)，
##     偏移 `(0,-11)`）与敌人形状（RectangleShape2D(24,24)，居中）在贴脸时
##     几何重叠 14px，物理分离会把两者推到 **≈34px** —— 而本段 `attack_range` 恰好是
##     **34**。于是敌人被顶到边界后在 CHASE ↔ ATTACK 之间**来回震荡**，攻击时断时续。
##
## 结论：**启用敌人碰撞不是改个字段，而是一次平衡调整** —— 必须同时处理
##   ① 敌人形状几何（居中 vs 玩家形状的向上偏移口径不一致）
##   ② 玩家形状偏移
##   ③ 每只怪的 `attack_range`（需 > 最大分离距离）
## 且项目当前**整体没有物理碰撞**（墙 / 障碍也没有 StaticBody2D，见
## `level_scene.gd` 已知限制 1），敌人不实心与之一致。故暂不启用，
## 待「墙碰撞 + 攻击距离重调」一并做。**本段断言就是防它被无声开启的闸门。**
func _test_attack() -> void:
	print("--- E. 攻击 ---")
	_taken_events.clear()
	_enemy = _spawn_enemy(Vector2(0, 40))
	_reset_player()
	_player.global_position = Vector2(0, 60)  # 距敌人 20px < attack_range 34
	await _wait_frames(5)
	_ok("玩家贴脸 → ATTACK", _enemy.state == EnemyBase.AIState.ATTACK)
	_ok("进入攻击后立即输出第一击（事件 ≥ 1）", _taken_events.size() >= 1)
	var first: Array = _taken_events[0]
	_ok("第一击：amount ≈ 5.61（GDD 6.3 L1 基线）且元素 physical",
		is_equal_approx(float(first[1]), 5.61) and String(first[2]) == GameConstants.ELEMENT_PHYSICAL)
	# 再等 1.2s+ → 第二击
	var before := _taken_events.size()
	await _wait_frames(80)
	_ok("1.2s 间隔后输出第二击（事件 ≥ 2）", _taken_events.size() >= before + 1)
	# 玩家无 take_damage（2.6 前）→ 只发事件不崩（前面已证明；这里确认进程存活）
	_ok("玩家无生命组件不崩（事件正常计数 %d）" % _taken_events.size(), true)


# =============================================================================
# F. 回归
# =============================================================================

func _test_regression() -> void:
	print("--- F. 回归 ---")
	# 玩家在敌人存在时移动 / 攻击 / 技能均正常
	_reset_player()
	_player.get_mana_pool().set_current(100.0)
	_player.global_position = Vector2(0, 0)
	_enemy.global_position = Vector2(0, 500)  # 放远，不干扰
	var p0 := _player.global_position
	_player.velocity = Vector2(0, -100)
	_player.move_and_slide()
	await _wait_frames(2)
	_ok("玩家移动正常（位移 ≈ 期望方向）", _player.global_position.y < p0.y)
	_ok("玩家普攻正常", _player.try_attack())
	_ok("玩家技能施放正常", _player.get_skill_controller().try_cast("spin_slash"))
	await _wait_frames(2)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
