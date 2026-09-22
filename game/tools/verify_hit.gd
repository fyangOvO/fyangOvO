## 碰撞与命中判定实测（任务 2.5 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_hit.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围：
##   A. HitQuery.circle：圆内命中 / 目标半径扩展 / 距离排序 / 圆心重叠跳过 / 无效节点过滤
##   B. HitQuery.arc：正前与 ±25° 命中 / 90° 侧外不命中 / range 外不命中 / 半径扩展 / 零 facing 回退
##   C. HitQuery.rect：前方命中 / 侧宽超限不命中 / 身后不命中 / 深度外不命中
##   D. 玩家接入：普攻（arc）前方命中 / 背对不命中 / 旋刃（circle）命中
##   E. 敌人攻击角度：攻击弧内命中发事件 / 90° 弧外挥空 / 超距离挥空
##   F. 玩家无敌帧：闪避中敌人攻击挥空 / 结束后恢复可命中
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null
var _enemy: EnemyBase = null
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
	print("===== 命中判定实测 =====")
	_player = get_node_or_null("/root/VerifyHit/Player") as PlayerController
	_ok("场景就绪：玩家", _player != null)
	EventBus.damage_taken.connect(_on_damage_taken)
	await _test_circle()
	await _test_arc()
	await _test_rect()
	await _test_player_integration()
	await _test_enemy_attack_angle()
	await _test_invulnerable()
	_finish()


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


## 玩家复位：位置 / 朝向 / 攻速计时 / 法力
func _reset_player() -> void:
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	_player._attack_timer = 0.0
	_player.set_facing(PlayerController.Facing8.DOWN)
	_player.get_mana_pool().set_current(100.0)


# =============================================================================
# A. circle
# =============================================================================

func _test_circle() -> void:
	print("--- A. HitQuery.circle ---")
	var a := _spawn_enemy(Vector2(10, 0))
	var b := _spawn_enemy(Vector2(30, 0))
	var c := _spawn_enemy(Vector2(100, 0))
	var hits := HitQuery.circle(Vector2.ZERO, 50.0, [a, b, c])
	_ok("圆内命中 2 个（距离 10/30 ≤ 50）", hits.size() == 2)
	_ok("按距离升序（a 在前）", hits[0] == a and hits[1] == b)

	# 目标半径扩展：dist 53 − 12 = 41 > 40 不命中；dist 51 − 12 = 39 ≤ 40 命中
	c.global_position = Vector2(53, 0)
	var hits2 := HitQuery.circle(Vector2.ZERO, 40.0, [a, b, c])
	_ok("目标半径扩展：dist 53 − 12 = 41 > 40 不命中", not hits2.has(c))
	c.global_position = Vector2(51, 0)
	var hits3 := HitQuery.circle(Vector2.ZERO, 40.0, [c])
	_ok("目标半径扩展：dist 51 − 12 = 39 ≤ 40 命中", hits3.size() == 1)

	var overlap := _spawn_enemy(Vector2.ZERO)
	_ok("与圆心重叠的目标跳过（dist ≤ 0.001）",
		HitQuery.circle(Vector2.ZERO, 50.0, [overlap]).is_empty())
	# ⚠️ 已释放（freed）对象无法传入 Array[Node] 类型化参数（传参即校验报错），
	#    函数体内 is_instance_valid 是防御冗余，不再单测（A 段覆盖到此为止）。


# =============================================================================
# B. arc
# =============================================================================

func _test_arc() -> void:
	print("--- B. HitQuery.arc ---")
	var f := _spawn_enemy(Vector2(50, 0))
	var p25 := _spawn_enemy(Vector2(50.0 * cos(deg_to_rad(25.0)), 50.0 * sin(deg_to_rad(25.0))))
	var n25 := _spawn_enemy(Vector2(50.0 * cos(deg_to_rad(25.0)), -50.0 * sin(deg_to_rad(25.0))))
	var side := _spawn_enemy(Vector2(0, 50))
	var far := _spawn_enemy(Vector2(100, 0))
	var hits := HitQuery.arc(Vector2.ZERO, Vector2.RIGHT, 60.0, 60.0, [f, p25, n25, side, far])
	_ok("正前方 + ±25° 命中（60° 弧内）",
		hits.size() == 3 and hits.has(f) and hits.has(p25) and hits.has(n25))
	_ok("90° 侧方不命中（弧宽外）", not hits.has(side))
	_ok("range 外不命中（100 > 60 + 12）", not hits.has(far))

	var e40 := _spawn_enemy(Vector2(50, 0))
	_ok("目标半径扩展：range 40 命中 dist 50 目标（50−12=38 ≤ 40）",
		HitQuery.arc(Vector2.ZERO, Vector2.RIGHT, 40.0, 60.0, [e40]).size() == 1)

	var below := _spawn_enemy(Vector2(0, 50))
	_ok("零 facing 回退 DOWN（下方命中）",
		HitQuery.arc(Vector2.ZERO, Vector2.ZERO, 60.0, 60.0, [below]).size() == 1)


# =============================================================================
# C. rect
# =============================================================================

func _test_rect() -> void:
	print("--- C. HitQuery.rect ---")
	var front := _spawn_enemy(Vector2(50, 0))
	var angled := _spawn_enemy(Vector2(50, 15))
	var side_l := _spawn_enemy(Vector2(0, 40))
	var behind := _spawn_enemy(Vector2(-20, 30))
	var far := _spawn_enemy(Vector2(100, 0))
	var hits := HitQuery.rect(Vector2.ZERO, Vector2.RIGHT, 40.0, 60.0,
		[front, angled, side_l, behind, far])
	_ok("前方正中 + 前方偏侧命中 2 个", hits.size() == 2 and hits.has(front) and hits.has(angled))
	_ok("侧方超宽不命中（40 > 20 + 12）", not hits.has(side_l))
	_ok("身后不命中（forward < 0）", not hits.has(behind))
	_ok("深度外不命中（100 > 60 + 12）", not hits.has(far))


# =============================================================================
# D. 玩家接入
# =============================================================================

func _test_player_integration() -> void:
	print("--- D. 玩家接入回归 ---")
	_enemy = _spawn_enemy(Vector2(0, 38))
	_enemy.current_hp = 100.0  # 初始 100.7（get_hp），统一为 100 便于断言
	_reset_player()
	_player.try_attack()
	await get_tree().physics_frame
	_info("普攻后敌人 HP = %.1f" % _enemy.current_hp)
	_ok("普攻命中（arc：38 − 12 = 26 ≤ 48，朝下扇区）",
		is_equal_approx(_enemy.current_hp, 88.0) or is_equal_approx(_enemy.current_hp, 82.0))

	_enemy.current_hp = 100.0
	_player.set_facing(PlayerController.Facing8.UP)
	_player.try_attack()
	await get_tree().physics_frame
	_ok("背对不命中（60° 扇区朝上，敌人仍满血）", is_equal_approx(_enemy.current_hp, 100.0))

	_enemy.current_hp = 100.0
	_player.set_facing(PlayerController.Facing8.DOWN)
	var cast_ok := _player.get_skill_controller().try_cast("spin_slash")
	await get_tree().physics_frame
	_info("旋刃后敌人 HP = %.1f" % _enemy.current_hp)
	_ok("旋刃命中（circle：38 − 12 = 26 ≤ 48；12×1.4 = 16.8 或暴击 25.2）",
		cast_ok and (is_equal_approx(_enemy.current_hp, 83.2) or is_equal_approx(_enemy.current_hp, 74.8)))


# =============================================================================
# E. 敌人攻击角度
# =============================================================================

func _test_enemy_attack_angle() -> void:
	print("--- E. 敌人攻击角度判定 ---")
	_enemy = _spawn_enemy(Vector2.ZERO)
	await get_tree().physics_frame  # 等敌人刷新玩家引用（否则 _player 为 null）
	_enemy.facing = Vector2.DOWN
	_reset_player()

	# 正前方（攻击弧内）→ 命中
	_player.global_position = Vector2(0, 20)
	_taken_events.clear()
	_enemy._attack_player()
	_ok("玩家在攻击弧内（正下方）→ 命中发事件", _taken_events.size() == 1)

	# 90° 侧方（弧外）→ 挥空
	_player.global_position = Vector2(-20, 0)
	_enemy.facing = Vector2.DOWN
	_taken_events.clear()
	_enemy._attack_player()
	_ok("玩家在弧外（90° > 60°）→ 挥空", _taken_events.is_empty())

	# 超距离 → 挥空（34 + 11 = 45 有效距离）
	_player.global_position = Vector2(0, 50)
	_enemy.facing = Vector2.DOWN
	_taken_events.clear()
	_enemy._attack_player()
	_ok("玩家超攻击距离（50 > 34 + 11）→ 挥空", _taken_events.is_empty())


# =============================================================================
# F. 玩家无敌帧
# =============================================================================

func _test_invulnerable() -> void:
	print("--- F. 玩家无敌帧 ---")
	_enemy = _spawn_enemy(Vector2.ZERO)
	await get_tree().physics_frame  # 等敌人刷新玩家引用
	_enemy.facing = Vector2.DOWN
	_reset_player()
	_player.global_position = Vector2(0, 20)
	_player.try_dodge()
	await get_tree().physics_frame
	_ok("闪避中玩家标记无敌（iframe）", _player.is_invulnerable())
	_player.global_position = Vector2(0, 20)  # 同帧放回（否则闪避位移冲出攻击范围）
	_taken_events.clear()
	_enemy._attack_player()
	_ok("无敌帧内敌人攻击挥空", _taken_events.is_empty())
	# 闪避无敌帧 0.30s ≈ 18 帧；等 30 帧后解除
	for i in 30:
		await get_tree().physics_frame
	_ok("闪避结束后解除无敌", not _player.is_invulnerable())
	# 复位双方位置（30 帧里敌人已追到玩家闪避落点附近）再测恢复命中
	_enemy.global_position = Vector2.ZERO
	_enemy.facing = Vector2.DOWN
	_player.global_position = Vector2(0, 20)
	_taken_events.clear()
	_enemy._attack_player()
	_ok("无敌解除后攻击恢复命中", _taken_events.size() == 1)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
