## 击退 vs 地形碰撞 实测（开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_knockback.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 为什么需要它
## ------------
## ① 敌人侧的 `EnemyBase.apply_knockback()` 原本是 `position += offset` ——
##    **直接改坐标**，会瞬移 + **穿墙**。函数注释自己就写着「2.4 简易版直接位移；
##    2.6 并入 velocity 减阻并考虑地形阻挡」。墙体碰撞体（`LevelScene._build_collision()`）
##    现在是真实存在的 ⇒ 被击退的怪会穿进墙体 / 卡在几何体里。
## ② 玩家侧已经改对了（独立击退通道 + `move_and_slide()` 裁定地形），敌人侧照抄同一模式。
##    但**没有任何断言**盯着敌人侧 —— 这类「改了但没人验」正是本项目反复踩的坑。
## ③ 本脚本第一次跑就抓到更深一层：`enemy_base.tscn` 的 `CollisionShape2D` **漏写
##    `type="CollisionShape2D"`**（全项目唯一一处）⇒ Godot 实例化时静默丢弃该节点 ⇒
##    敌人**从 2.4 起一直没有碰撞体**，「撞墙会被挡住」从来就没成立过（见 README 任务 10.10）。
##    同时它的 `collision_layer = 3` 是「层 1+2」而不是层表里的「层 3 = enemy」。
##
## 覆盖：
##   A. 契约：方法存在 + **调用后同帧位置不变**（证明不再是 `position += offset` 的瞬移）
##      + 敌人场景自带 24×24 碰撞形状 + 层契约 layer=4 / mask=1（钉住现状，见上 ③）
##   B. 无障碍：位移与请求量同量级 + 衰减会停 + 击退不残留到 AI 通道
##   C. 有墙：朝墙猛推**不得穿墙**（停在「墙面 − 半宽」处），且确实被推动了
##
## ⚠️ 本脚本自建极简世界（一个 `StaticBody2D` 墙），不加载关卡场景：
##    关卡会带玩家/敌人/相机/结算面板，噪声大且慢；这里要验的只是
##    「击退通道 + move_and_slide」这一条链路。
extends Node

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")

## 墙左表面 x。墙是一根竖条，足够高，避免怪从上下绕过去。
const WALL_LEFT: float = 100.0
const WALL_SIZE: Vector2 = Vector2(64.0, 4000.0)
## 敌人碰撞形状是 `RectangleShape2D(24, 24)`（`enemy_base.tscn`）⇒ 半宽 12px
const ENEMY_HALF: float = 12.0
## 敌人出生点：墙左侧、贴得比较近
const START_POS: Vector2 = Vector2(20.0, 0.0)
## 物理帧率下的等待帧数
const FRAMES_SETTLE: int = 30

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _await_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 100.0)
	print("===== 击退 vs 地形碰撞 实测 =====")
	await _test_contract()
	await _test_open_field()
	await _test_blocked_by_wall()
	_finish()


# =============================================================================
# A. 契约
# =============================================================================

func _test_contract() -> void:
	print("--- A. 契约：方法存在 + 不瞬移 ---")
	var e := _spawn_enemy(START_POS)
	await _await_frames(2)

	_ok("EnemyBase.has_method(\"apply_knockback\") == true",
		e.has_method("apply_knockback"))

	# ⚠️ 敌人场景**自带**碰撞形状 —— 这是「move_and_slide 能裁定地形」的前提。
	#    2026-09-21 实测：`enemy_base.tscn` 里这个节点写成了
	#    `[node name="CollisionShape2D" parent="."]`（**漏了 `type="CollisionShape2D"`**），
	#    而 `player.tscn` / `damage_dummy.tscn` 都写了。Godot 实例化时静默丢弃该节点
	#    （只留一句 `WARNING: ... has vanished`）⇒ 敌人**从 2.4 起一直没有碰撞体** ⇒
	#    击退/追击都会穿墙。这条断言让「场景缺碰撞形状」自己响亮报错，
	#    而不是只在下游 C 段表现为「穿墙」那种看不出根因的症状。
	var cs := e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_ok("敌人场景自带 CollisionShape2D（否则 move_and_slide 无从裁定地形）", cs != null)
	if cs != null:
		var rshape := cs.shape as RectangleShape2D
		_ok("敌人碰撞形状 == 24×24（与 get_hit_radius()=12 一致）",
			rshape != null and rshape.size == Vector2(24.0, 24.0))

	# 层契约：敌人 = **层 3 = enemy（值 4）**，mask 只打 world（值 1）。
	#   · `layer = 4` 才是 README §7 层表里的「层 3 = enemy」；旧值 3 = 层 1+2（world+player），
	#     会把敌人放到**地形层**上 ⇒ 玩家（mask=1）会撞到怪、怪之间也互撞。
	#   · `mask` 刻意**不含玩家层**：README 任务 10.10 已记录，敌人与玩家贴脸时形状几何
	#     重叠被物理分离推到 ≈34px，而 `attack_range` 恰好 34 ⇒ CHASE↔ATTACK 震荡、
	#     攻击时断时续。那条要等「攻击判定加迟滞」（退出阈值 = `attack_range` + Δ）才能开，
	#     属 10.10，不在本轮。
	#   ⇒ 本断言**钉住现状**：谁把 mask 放开到含玩家层，这里立刻变红，逼他先读 10.10。
	_ok("敌人层契约 = layer 4（层 3 = enemy）/ mask 1（只打 world 地形）",
		e.collision_layer == 4 and e.collision_mask == 1)

	# 与玩家侧同签名的证明：能按 (Vector2) -> void 调用而不报错
	var before := e.global_position
	e.apply_knockback(Vector2(24.0, 0.0))
	# ⚠️ 核心：旧实现 `position += offset` 会让位置**当场**跳变。
	#    新实现只是把速度写进击退通道，位移要等 `_physics_process` 里的 move_and_slide 才发生。
	_ok("apply_knockback 不瞬移（同帧位置不变：%s → %s）"
		% [str(before), str(e.global_position)], e.global_position == before)

	e.queue_free()
	await _await_frames(1)


# =============================================================================
# B. 无障碍：位移量级 + 衰减停止 + 不残留
# =============================================================================

func _test_open_field() -> void:
	print("--- B. 无障碍：位移同量级 / 会停 / 不残留到 AI 通道 ---")
	var e := _spawn_enemy(START_POS)
	await _await_frames(2)
	var before := e.global_position

	# 理论值：v0 = sqrt(2·a·L) = sqrt(2×1200×24) ≈ 240 px/s，衰减 1200 px/s²
	# ⇒ 总位移 L = v0²/(2a) = 24px。离散化会略有出入，取 12–48px 的宽松窗口。
	e.apply_knockback(Vector2(24.0, 0.0))
	await _await_frames(12)
	var moved := (e.global_position - before).length()
	_ok("位移与请求量同量级（%.1f px，期望 ≈24，容许 12–48）" % moved,
		moved > 12.0 and moved < 48.0)

	# 衰减必须停：否则会一直飘
	await _await_frames(FRAMES_SETTLE)
	var d1 := (e.global_position - before).length()
	await _await_frames(10)
	var d2 := (e.global_position - before).length()
	_ok("击退已衰减停止（%.2f px → %.2f px，差值 < 0.5）" % [d1, d2], absf(d2 - d1) < 0.5)

	# 击退不得残留到 AI 通道：`_physics_process` 末尾把 velocity 写回 AI 通道，
	# 本场景 AI 速度恒 0（无玩家 + 巡逻等待被拉满）⇒ 结算后 velocity 应回到 ~0。
	# ⚠️ 写成 `velocity += _knockback_velocity` 就会在这里露馅（速度发散）。
	_ok("击退不残留到 velocity（结算后 |velocity| = %.3f，应 < 1.0）"
		% e.velocity.length(), e.velocity.length() < 1.0)

	e.queue_free()
	await _await_frames(1)


# =============================================================================
# C. 有墙：不得穿墙
# =============================================================================

func _test_blocked_by_wall() -> void:
	print("--- C. 有墙：朝墙猛推不得穿墙 ---")
	_make_wall()
	var e := _spawn_enemy(START_POS)
	await _await_frames(2)
	var before := e.global_position

	# 请求 200px，但墙左表面在 x=100、怪半宽 12 ⇒ 最多只能走到 x = 88。
	e.apply_knockback(Vector2(200.0, 0.0))
	await _await_frames(FRAMES_SETTLE)
	var after := e.global_position
	var limit := WALL_LEFT - ENEMY_HALF

	_ok("敌人确实被推动了（x %.1f → %.1f）" % [before.x, after.x], after.x > before.x + 1.0)
	_ok("被墙挡住、未穿墙（x = %.2f，上限 = 墙面 %.0f − 半宽 %.0f = %.0f）"
		% [after.x, WALL_LEFT, ENEMY_HALF, limit], after.x <= limit + 0.5)
	_ok("确实撞到了墙而不是被吃掉位移（x = %.2f ≥ %.1f）" % [after.x, limit - 8.0],
		after.x >= limit - 8.0)
	_info("墙左表面 x=%.0f，敌人最终 x=%.2f（理论停点 %.0f）" % [WALL_LEFT, after.x, limit])

	e.queue_free()
	await _await_frames(1)


# =============================================================================
# 工具
# =============================================================================

## 造一个只有墙的极简世界。层契约与 `LevelScene._build_collision()` 一致：
## `collision_layer = 1`（world）/ `collision_mask = 0`。
func _make_wall() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "TestWall"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = WALL_SIZE
	shape.shape = rect
	shape.position = Vector2(WALL_LEFT + WALL_SIZE.x / 2.0, 0.0)
	body.add_child(shape)
	add_child(body)
	return body


## 放一只怪，并**冻结它的 AI 位移**，让位置变化只可能来自击退通道：
##   · 场景里不放玩家 ⇒ `_refresh_player()` 恒拿不到人 ⇒ `_player == null` ⇒ 状态停在 PATROL；
##   · `_patrol_wait` 拉满 ⇒ `_tick_patrol` 每帧把 velocity 置 0。
## 这样断言「位置变了」就只可能是击退造成的，不会被巡逻噪声污染。
func _spawn_enemy(pos: Vector2) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.position = pos
	add_child(e)
	e._patrol_wait = 999999.0
	return e


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
