## 打击感系统实测（任务 2.8 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_juice.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 参数与接入：打击感常量合法、JuiceFX Autoload 存在并监听两条事件总线
##   B. 飘字：damage_dealt → 生成 DamageNumber、位置在目标头顶上方、暴击样式
##   C. 飘字生命周期：0.7s 后自动消失
##   D. 顿帧：hit_stop 后 time_scale 短暂 <1 并恢复 1.0
##   E. 震屏：shake 后相机 offset 抖动、衰减回 0
##   F. 死亡表现：unit_died → 贴图特效（有贴图时）或 PixelBurst（兜底）、自动消失
##   G. 玩家闪白：flash 后 modulate 提亮并恢复
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null
var _camera: Camera2D = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 打击感系统实测 =====")
	_player = get_node_or_null("/root/VerifyJuice/Player") as PlayerController
	_camera = get_tree().get_first_node_in_group(&"main_camera") as Camera2D
	_ok("场景就绪：玩家", _player != null)
	_ok("场景就绪：震屏相机（main_camera 组）", _camera != null)
	await _test_params()
	await _test_damage_number()
	await _test_number_lifetime()
	await _test_hit_stop()
	await _test_shake()
	await _test_death_burst()
	await _test_player_flash()
	_finish()


## 推进指定秒数的物理帧
func _step(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for i in range(frames):
		await get_tree().physics_frame


# =============================================================================
# A. 参数与接入
# =============================================================================

func _test_params() -> void:
	print("--- A. 参数与接入 ---")
	_ok("打击感常量合法（寿命 > 0、顿帧 ∈ (0,0.1)、震屏/衰减 > 0）",
		GameConstants.DAMAGE_NUMBER_LIFETIME > 0.0
		and GameConstants.DAMAGE_NUMBER_RISE_SPEED > 0.0
		and GameConstants.HIT_FLASH_DURATION > 0.0
		and GameConstants.HIT_STOP_DURATION > 0.0
		and GameConstants.HIT_STOP_DURATION < 0.1
		and GameConstants.HIT_STOP_TIME_SCALE > 0.0
		and GameConstants.HIT_STOP_TIME_SCALE < 1.0
		and GameConstants.SHAKE_HIT_STRENGTH > 0.0
		and GameConstants.SHAKE_DECAY_PER_SEC > 0.0
		and GameConstants.DEATH_BURST_PARTS >= 4)
	_ok("JuiceFX Autoload 存在", get_node_or_null("/root/JuiceFX") != null)


# =============================================================================
# B. 飘字
# =============================================================================

func _test_damage_number() -> void:
	print("--- B. 飘字 ---")
	var before := get_tree().get_nodes_in_group(&"juice_numbers").size()
	var target: Node = _player
	EventBus.damage_dealt.emit(target, 42.0, false, GameConstants.ELEMENT_PHYSICAL)
	await get_tree().process_frame
	var nums := get_tree().get_nodes_in_group(&"juice_numbers")
	_ok("damage_dealt 生成飘字（普通命中）", nums.size() == before + 1)
	if nums.size() > before:
		var n := nums[nums.size() - 1] as DamageNumber
		_ok("飘字显示金额 42", n.get_node("Label").text == "42")
		_ok("飘字位置在目标头顶上方", n.global_position.y < target.global_position.y)
		_ok("普通飘字为亮白色",
			(n.get_node("Label") as Label).get_theme_color("font_color") == GameConstants.COLOR_DAMAGE_NORMAL)
	EventBus.damage_dealt.emit(target, 99.0, true, GameConstants.ELEMENT_PHYSICAL)
	await get_tree().process_frame
	nums = get_tree().get_nodes_in_group(&"juice_numbers")
	var crit_num := nums[nums.size() - 1] as DamageNumber
	_ok("暴击飘字为橙红色大字",
		(crit_num.get_node("Label") as Label).get_theme_color("font_color") == GameConstants.COLOR_DAMAGE_CRIT
		and (crit_num.get_node("Label") as Label).get_theme_font_size("font_size")
			== GameConstants.DAMAGE_NUMBER_CRIT_FONT_SIZE)


# =============================================================================
# C. 飘字生命周期
# =============================================================================

func _test_number_lifetime() -> void:
	print("--- C. 飘字生命周期 ---")
	var n := get_tree().get_nodes_in_group(&"juice_numbers")
	if n.is_empty():
		_ok("飘字生命周期：无可测节点（跳过）", true)
		return
	var alive: Node = n[0]
	await _step(GameConstants.DAMAGE_NUMBER_LIFETIME + 0.2)
	_ok("飘字 %s 秒后自动消失" % str(GameConstants.DAMAGE_NUMBER_LIFETIME),
		not is_instance_valid(alive) or not get_tree().get_nodes_in_group(&"juice_numbers").has(alive))


# =============================================================================
# D. 顿帧
# =============================================================================

func _test_hit_stop() -> void:
	print("--- D. 顿帧 ---")
	Engine.time_scale = 1.0
	var jf := get_node_or_null("/root/JuiceFX")
	jf.hit_stop(GameConstants.HIT_STOP_DURATION)
	var ts0 := Engine.time_scale
	_ok("顿帧触发后 time_scale 压低", ts0 < 1.0)
	await _step(0.2)  # 超过 HIT_STOP_DURATION（真实时间，忽略 time_scale）
	_ok("顿帧后 time_scale 恢复 1.0", absf(Engine.time_scale - 1.0) < 0.001)


# =============================================================================
# E. 震屏
# =============================================================================

func _test_shake() -> void:
	print("--- E. 震屏 ---")
	_camera.offset = Vector2.ZERO
	var jf := get_node_or_null("/root/JuiceFX")
	jf.shake(GameConstants.SHAKE_CRIT_STRENGTH)
	await _step(0.06)  # 多等几物理帧（process_frame 先于 _process，同帧读 offset 恒 0）
	var moved := _camera.offset.length() > 0.0
	await _step(0.3)  # 3px / 40px-per-sec ≈ 0.075s 衰减完
	var settled := _camera.offset == Vector2.ZERO
	_ok("震屏触发后相机 offset 抖动", moved)
	_ok("震屏衰减后相机 offset 归零", settled)


# =============================================================================
# F. 死亡表现（贴图优先 / 代码绘制兜底）
# =============================================================================

func _test_death_burst() -> void:
	print("--- F. 死亡表现（贴图优先 / 代码绘制兜底）---")
	# 2026-09-20：死亡表现改为「贴图优先、代码绘制兜底」（见 `juice_fx.gd` 类注释）。
	# 契约从「一定生成 PixelBurst」变成「**二者必居其一**」：
	#   · 有 death_puff 贴图 → 生成 FxSprite（组 fx_sprites）；
	#   · 贴图缺失        → 退回 PixelBurst（组 juice_bursts）。
	# 这里两条都数，断言总数 +1；再单独验证兜底原语本身仍然可用。
	var before_burst := get_tree().get_nodes_in_group(&"juice_bursts").size()
	var before_fx := get_tree().get_nodes_in_group(&"fx_sprites").size()
	var dummy := _make_dummy(Vector2(0, -60))
	EventBus.unit_died.emit(dummy, _player)
	await get_tree().process_frame
	var burst_add := get_tree().get_nodes_in_group(&"juice_bursts").size() - before_burst
	var fx_add := get_tree().get_nodes_in_group(&"fx_sprites").size() - before_fx
	_ok("unit_died 产生死亡表现（贴图 +%d / 粒子 +%d，合计应为 1）" % [fx_add, burst_add],
		fx_add + burst_add == 1)
	_ok("有 death_puff 贴图时走贴图分支（而不是静默什么都不做）",
		not FxTable.has_texture("death_puff") or fx_add == 1)

	# 兜底原语单独验证：贴图缺失时 JuiceFX 走的就是这条（`_spawn_burst`）
	var jf := get_node_or_null("/root/JuiceFX")
	var b0 := get_tree().get_nodes_in_group(&"juice_bursts").size()
	jf._spawn_burst(dummy.global_position, Color.WHITE)
	await get_tree().process_frame
	var bursts := get_tree().get_nodes_in_group(&"juice_bursts")
	_ok("代码绘制兜底 _spawn_burst 仍生成 PixelBurst", bursts.size() == b0 + 1)
	if bursts.size() > b0:
		var b: PixelBurst = bursts[bursts.size() - 1]
		_ok("粒子位于死亡点", b.global_position.distance_to(dummy.global_position) < 0.01)
		await _step(GameConstants.DEATH_BURST_DURATION + 0.2)
		_ok("粒子 %s 秒后自动消失" % str(GameConstants.DEATH_BURST_DURATION),
			not is_instance_valid(b) or not get_tree().get_nodes_in_group(&"juice_bursts").has(b))


## 简易可死宿主（免 spawn 敌人，聚焦事件链路；无 get_display_color → 白色粒子）
func _make_dummy(pos: Vector2) -> Node2D:
	var d := Node2D.new()
	d.name = "JuiceDeadDummy"
	d.global_position = pos
	add_child(d)
	return d


# =============================================================================
# G. 玩家闪白
# =============================================================================

func _test_player_flash() -> void:
	print("--- G. 玩家闪白 ---")
	_player.flash()
	var lit := _player.body_sprite.modulate.r > 1.5
	await _step(GameConstants.HIT_FLASH_DURATION + 0.1)
	_ok("玩家受击闪白并恢复", lit and _player.body_sprite.modulate == Color.WHITE)


func _finish() -> void:
	print("")
	if _fail == 0:
		print("===== 结果：0 项失败 =====")
	else:
		print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
