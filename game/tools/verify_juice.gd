## 打击感系统实测（任务 2.8 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_juice.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（10 个测试段）：
##   A. 参数与接入：打击感常量合法、JuiceFX Autoload 存在并监听两条事件总线
##   B. 飘字：damage_dealt → 生成 DamageNumber、位置在目标头顶上方、暴击样式
##   C. 飘字生命周期：0.7s 后自动消失
##   D. 顿帧：hit_stop 后 time_scale 短暂 <1 并恢复 1.0
##   E. 震屏：shake 后相机 offset 抖动、衰减回 0
##   F. 死亡表现：unit_died → 贴图特效（有贴图时）或 PixelBurst（兜底）、自动消失
##   G. 玩家闪白：flash 后 modulate 提亮并恢复
##   H. 冲击事件（2026-10-13 打击感 C）：screen_impact → 震屏 + 顿帧、半径分级函数单调夹取
##   I. 稀有掉落庆祝（2026-10-14）：强度表逐档 / 低档不庆祝 / 单调 / 越界安全 / 端到端光爆震屏顿帧
##   J. 顿帧按伤害分级（2026-10-14）：阈值夹取 / 单调 / 暴击∪重击取 max / 鸭子探测 / 端到端
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
	await _test_screen_impact()
	await _test_rare_drop_celebration()
	await _test_damage_scaled_hit_stop()
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
		# 第四步 B4 `3-E7`：非暴击 + 有元素 ⇒ 走 `ELEMENT_COLORS[element]`（物理 E8E8E8）。
		# 此处以同一发色口径的 `normal_color_for()` 作期望值，避免断言与实现各写一份常量而漂移。
		_ok("普通飘字为元素色（物理 ⇒ 银白）",
			(n.get_node("Label") as Label).get_theme_color("font_color")
				== DamageNumber.normal_color_for(GameConstants.ELEMENT_PHYSICAL))
		# 向后兼容：空元素（旧调用方不传 element）⇒ 回退 `COLOR_DAMAGE_NORMAL`。
		_ok("空元素飘字回退普通亮白",
			DamageNumber.normal_color_for("") == GameConstants.COLOR_DAMAGE_NORMAL)
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


# =============================================================================
# H. 冲击事件（技能 / 爆炸 / BOSS 施法）—— 2026-10-13 打击感扩展 C
# =============================================================================

func _test_screen_impact() -> void:
	print("--- H. 冲击事件（技能 / 爆炸 / BOSS 施法）---")
	# ① 常量合法：顿帧全部落在 Playground 建议的 30–60ms 带内；震屏强度递增。
	var stops: Array = [GameConstants.HIT_STOP_IMPACT_SKILL,
		GameConstants.HIT_STOP_IMPACT_EXPLOSION,
		GameConstants.HIT_STOP_IMPACT_BOSS_CAST]
	var in_band := true
	for s in stops:
		if float(s) < 0.03 or float(s) > 0.06:
			in_band = false
	_ok("冲击顿帧常量 ∈ [30ms, 60ms]（Playground 建议带）", in_band)
	_ok("冲击震屏常量递增（技能 < 爆炸 ≤ BOSS）",
		GameConstants.SHAKE_IMPACT_SKILL_BASE < GameConstants.SHAKE_IMPACT_EXPLOSION
		and GameConstants.SHAKE_IMPACT_EXPLOSION <= GameConstants.SHAKE_IMPACT_BOSS_CAST
		and GameConstants.SHAKE_IMPACT_SKILL_MAX > GameConstants.SHAKE_IMPACT_SKILL_BASE)

	# ② 半径分级函数：真跑函数（不重写公式）+ 单调不减 + 两端夹取。
	var s0 := GameConstants.shake_strength_for_radius(0.0)
	var s_small := GameConstants.shake_strength_for_radius(40.0)
	var s_big := GameConstants.shake_strength_for_radius(GameConstants.SHAKE_IMPACT_RADIUS_REF)
	var s_over := GameConstants.shake_strength_for_radius(9999.0)
	_ok("半径分级：0 → 基础值", is_equal_approx(s0, GameConstants.SHAKE_IMPACT_SKILL_BASE))
	_ok("半径分级：≥ 参考半径 → 封顶（超界不越界）",
		is_equal_approx(s_big, GameConstants.SHAKE_IMPACT_SKILL_MAX)
		and is_equal_approx(s_over, GameConstants.SHAKE_IMPACT_SKILL_MAX))
	_ok("半径分级：单调不减（0 ≤ 40 ≤ 参考半径）", s0 <= s_small and s_small <= s_big)

	# ③ 接线：JuiceFX 确实连上了 screen_impact（不是「有信号没人听」的死钩子）。
	var jf := get_node_or_null("/root/JuiceFX")
	_ok("JuiceFX 监听 screen_impact", jf != null
		and EventBus.screen_impact.is_connected(Callable(jf, "_on_screen_impact")))

	# ④ 端到端：发一次冲击 → 顿帧 + 相机抖动 → 全部自动复原。
	_camera.offset = Vector2.ZERO
	Engine.time_scale = 1.0
	EventBus.screen_impact.emit(Vector2.ZERO,
		GameConstants.SHAKE_IMPACT_EXPLOSION, GameConstants.HIT_STOP_IMPACT_EXPLOSION)
	_ok("screen_impact → 顿帧（time_scale < 1）", Engine.time_scale < 1.0)
	await _step(0.06)
	_ok("screen_impact → 相机 offset 抖动", _camera.offset.length() > 0.0)
	await _step(0.35)
	_ok("冲击结束后 time_scale 恢复 1.0 且 offset 归零",
		absf(Engine.time_scale - 1.0) < 0.001 and _camera.offset == Vector2.ZERO)


# =============================================================================
# I. 稀有掉落庆祝（2026-10-14 · Playground「掉落物 pop 带星光」）
# =============================================================================

func _test_rare_drop_celebration() -> void:
	print("--- I. 稀有掉落庆祝 ---")
	var jf := get_node_or_null("/root/JuiceFX")
	var n := GameConstants.RARITY_COUNT

	# ① 四条并行表必须逐档对齐（越界取到 0 会静默「不庆祝」，正是要防的静默脱钩）。
	_ok("庆祝强度表等长（== RARITY_COUNT）",
		GameConstants.RARE_DROP_FLASH_ALPHA.size() == n
		and GameConstants.RARE_DROP_FLASH_TIME.size() == n
		and GameConstants.RARE_DROP_SHAKE.size() == n
		and GameConstants.RARE_DROP_HIT_STOP.size() == n)

	# ② 低档（普通/魔法/稀有）全 0：rare_loot_spawned 本就不为它们发射，此处是防御性约束。
	var low_silent := true
	for r in range(GameConstants.Rarity.EPIC):
		var cel := GameConstants.rare_drop_celebration(r)
		if float(cel["flash_alpha"]) != 0.0 or float(cel["shake"]) != 0.0 \
				or float(cel["hit_stop"]) != 0.0:
			low_silent = false
	_ok("普通/魔法/稀有档不庆祝（防将来放宽门槛导致低档闪屏）", low_silent)

	# ③ 史诗起有光爆 + 震屏，但**不顿帧**（掉落物高频，顿帧会卡手）；传说起才给顿帧。
	var epic := GameConstants.rare_drop_celebration(GameConstants.Rarity.EPIC)
	var legend := GameConstants.rare_drop_celebration(GameConstants.Rarity.LEGENDARY)
	_ok("史诗起有光爆 + 震屏",
		float(epic["flash_alpha"]) > 0.0 and float(epic["shake"]) > 0.0)
	_ok("史诗不顿帧（掉落太频繁，顿帧会卡手）", float(epic["hit_stop"]) == 0.0)
	_ok("传说顿帧 ∈ [30ms, 60ms]（Playground 建议带）",
		float(legend["hit_stop"]) >= 0.03 and float(legend["hit_stop"]) <= 0.06)

	# ④ 强度分两段：线性带（史诗 → 神话）单调递增；正交/特殊档（套装/隐藏/深渊/塔）全部 ≥ 史诗。
	#    这不是「整表单调」—— 套装矮於神话、隐藏最高，是「两级判断」设计哲学的体现
	#    （线性档比强度，正交/特殊档比来源），与 `RARITY_BEAM_HEIGHTS` 的非单调同源。
	var linear_mono := true
	var prev_f := -1.0
	var prev_s := -1.0
	for r in range(GameConstants.Rarity.EPIC, GameConstants.Rarity.SET):
		var cel := GameConstants.rare_drop_celebration(r)
		var f := float(cel["flash_alpha"])
		var s := float(cel["shake"])
		if f < prev_f or s < prev_s:
			linear_mono = false
		prev_f = f
		prev_s = s
	_ok("线性带庆祝强度单调递增（史诗 → 神话，光爆/震屏）", linear_mono)
	var special_ge := true
	for r in range(GameConstants.Rarity.SET, n):
		var cel := GameConstants.rare_drop_celebration(r)
		if float(cel["flash_alpha"]) < float(epic["flash_alpha"]) \
				or float(cel["shake"]) < float(epic["shake"]):
			special_ge = false
	_ok("正交/特殊档庆祝强度 ≥ 史诗（套装/隐藏/深渊/塔都值得庆祝）", special_ge)

	# ⑤ 越界安全：不崩、返回全 0。
	var oob := GameConstants.rare_drop_celebration(999)
	_ok("越界稀有度返回全 0（不崩）",
		float(oob["flash_alpha"]) == 0.0 and float(oob["shake"]) == 0.0
		and float(oob["hit_stop"]) == 0.0)

	# ⑥ 接线：JuiceFX 确实连上了 rare_loot_spawned（不是「有信号没人听」的死钩子）。
	_ok("JuiceFX 监听 rare_loot_spawned", jf != null
		and EventBus.rare_loot_spawned.is_connected(Callable(jf, "_on_rare_loot_spawned")))

	# ⑦ 端到端（史诗）：全屏光爆 + 掉落点粒子爆；**不顿帧**。
	_camera.offset = Vector2.ZERO
	Engine.time_scale = 1.0
	var burst_before := get_tree().get_nodes_in_group(&"juice_bursts").size()
	var item := EquipmentInstance.new()
	item.rarity = GameConstants.Rarity.EPIC
	EventBus.rare_loot_spawned.emit(item, Vector2(10, 20))
	await get_tree().process_frame
	_ok("rare_loot_spawned → 全屏光爆（alpha > 0）",
		jf._flash_rect != null and jf._flash_rect.color.a > 0.0)
	_ok("rare_loot_spawned → 掉落点粒子爆",
		get_tree().get_nodes_in_group(&"juice_bursts").size() == burst_before + 1)
	_ok("史诗不顿帧（time_scale 保持 1.0）", absf(Engine.time_scale - 1.0) < 0.001)
	await _step(GameConstants.RARE_DROP_FLASH_TIME[GameConstants.Rarity.EPIC] + 0.3)
	_ok("光爆淡出归零（不残留）", jf._flash_rect.color.a <= 0.001)

	# ⑧ 端到端（隐藏 · 最高震屏档）：顿帧 + 震屏，全部自动复原。
	#    用隐藏（rarity 7）而不是史诗，是因为史诗震屏仅 1.5px（0.0375s 衰完）——
	#    断言「offset > 0」的取样窗口太窄，容易踩空成伪失败。
	_camera.offset = Vector2.ZERO
	Engine.time_scale = 1.0
	var hidden_item := EquipmentInstance.new()
	hidden_item.rarity = GameConstants.Rarity.HIDDEN
	EventBus.rare_loot_spawned.emit(hidden_item, Vector2(30, 40))
	_ok("隐藏掉落 → 顿帧（time_scale < 1）", Engine.time_scale < 1.0)
	await _step(0.06)
	_ok("隐藏掉落 → 相机 offset 抖动", _camera.offset.length() > 0.0)
	await _step(0.35)
	_ok("庆祝结束后 time_scale 恢复 1.0 且 offset 归零",
		absf(Engine.time_scale - 1.0) < 0.001 and _camera.offset == Vector2.ZERO)


# =============================================================================
# J. 命中顿帧 · 按伤害分级（2026-10-14 · Playground「重击/技能命中定格稍久」）
# =============================================================================

func _test_damage_scaled_hit_stop() -> void:
	print("--- J. 命中顿帧 · 按伤害分级 ---")
	var jf := get_node_or_null("/root/JuiceFX")

	# ① 常量合法：0 < 10% < 50% < 100%；时长 0 < 下沿 ≤ 上沿 ≤ 60ms（Playground 带上沿）。
	_ok("分级阈值合法（0 < 10% < 50% < 100%）",
		GameConstants.HIT_STOP_DAMAGE_MIN_RATIO > 0.0
		and GameConstants.HIT_STOP_DAMAGE_MIN_RATIO < GameConstants.HIT_STOP_DAMAGE_MAX_RATIO
		and GameConstants.HIT_STOP_DAMAGE_MAX_RATIO < 1.0)
	_ok("分级时长 ∈ (0, 60ms] 且 下沿 ≤ 上沿",
		GameConstants.HIT_STOP_DAMAGE_MIN > 0.0
		and GameConstants.HIT_STOP_DAMAGE_MIN <= GameConstants.HIT_STOP_DAMAGE_MAX
		and GameConstants.HIT_STOP_DAMAGE_MAX <= 0.06)

	# ② **真跑纯函数**（不重写公式）：边界 + 夹取 + 单调。
	_ok("max_hp ≤ 0 ⇒ 不顿（无血条 / 测试桩 / 未接生命组件）",
		GameConstants.hit_stop_for_damage(100.0, 0.0) == 0.0
		and GameConstants.hit_stop_for_damage(100.0, -5.0) == 0.0)
	_ok("amount ≤ 0 ⇒ 不顿", GameConstants.hit_stop_for_damage(0.0, 100.0) == 0.0)
	_ok("小伤害（5% 最大生命）⇒ 不顿（连招不发涩）",
		GameConstants.hit_stop_for_damage(5.0, 100.0) == 0.0)
	_ok("刚过阈值（10%）⇒ 下沿时长",
		is_equal_approx(GameConstants.hit_stop_for_damage(10.0, 100.0),
			GameConstants.HIT_STOP_DAMAGE_MIN))
	_ok("半管血（50%）⇒ 顿满",
		is_equal_approx(GameConstants.hit_stop_for_damage(50.0, 100.0),
			GameConstants.HIT_STOP_DAMAGE_MAX))
	_ok("一击秒杀（100%）⇒ 顿满（夹取，不越界）",
		is_equal_approx(GameConstants.hit_stop_for_damage(100.0, 100.0),
			GameConstants.HIT_STOP_DAMAGE_MAX))
	_ok("分级单调不减（5% ≤ 20% ≤ 40% ≤ 50%）",
		GameConstants.hit_stop_for_damage(5.0, 100.0)
			<= GameConstants.hit_stop_for_damage(20.0, 100.0)
		and GameConstants.hit_stop_for_damage(20.0, 100.0)
			<= GameConstants.hit_stop_for_damage(40.0, 100.0)
		and GameConstants.hit_stop_for_damage(40.0, 100.0)
			<= GameConstants.hit_stop_for_damage(50.0, 100.0))

	# ③ 三路合并（暴击 ∪ 重击）取 max —— 防「拆两次调用被矮时长挤掉」的回归。
	_ok("非暴击小伤害 ⇒ 0（不顿）",
		GameConstants.hit_stop_for_hit(5.0, 100.0, false) == 0.0)
	_ok("暴击小伤害 ⇒ 暴击固定档（不被新逻辑削弱）",
		is_equal_approx(GameConstants.hit_stop_for_hit(5.0, 100.0, true),
			GameConstants.HIT_STOP_DURATION))
	_ok("非暴击重击 ⇒ 分级档（新增能力：此前非暴击一律不顿）",
		is_equal_approx(GameConstants.hit_stop_for_hit(60.0, 100.0, false),
			GameConstants.HIT_STOP_DAMAGE_MAX))
	_ok("暴击 + 重击 ⇒ 取 max（分级档 60ms 不被暴击档 30ms 挤掉）",
		is_equal_approx(GameConstants.hit_stop_for_hit(60.0, 100.0, true),
			GameConstants.HIT_STOP_DAMAGE_MAX)
		and GameConstants.HIT_STOP_DAMAGE_MAX > GameConstants.HIT_STOP_DURATION)

	# ④ `_target_max_hp` 鸭子探测：真实目标取其 HealthComponent；裸节点 ⇒ 0。
	_ok("_target_max_hp(玩家) == 其 HealthComponent 最大生命",
		jf != null and is_equal_approx(jf._target_max_hp(_player), _player.health.get_max_hp()))
	var bare := _make_dummy(Vector2(0, -80))
	_ok("_target_max_hp(无生命组件的裸节点) == 0",
		jf != null and jf._target_max_hp(bare) == 0.0)

	# ⑤ 端到端：小伤害不顿 / 重击顿 / 暴击小伤害仍顿（全部自动恢复）。
	var max_hp: float = _player.health.get_max_hp()
	Engine.time_scale = 1.0
	EventBus.damage_dealt.emit(_player, max_hp * 0.05, false, GameConstants.ELEMENT_PHYSICAL)
	_ok("端到端：小伤害（5% 最大生命）不顿（time_scale 保持 1.0）",
		absf(Engine.time_scale - 1.0) < 0.001)
	Engine.time_scale = 1.0
	EventBus.damage_dealt.emit(_player, max_hp * 0.6, false, GameConstants.ELEMENT_PHYSICAL)
	_ok("端到端：重击（60% 最大生命）触发顿帧（time_scale < 1）", Engine.time_scale < 1.0)
	await _step(0.3)
	_ok("端到端：重击顿帧后恢复 1.0", absf(Engine.time_scale - 1.0) < 0.001)
	Engine.time_scale = 1.0
	EventBus.damage_dealt.emit(_player, max_hp * 0.05, true, GameConstants.ELEMENT_PHYSICAL)
	_ok("端到端：暴击小伤害仍顿（暴击固定档保留）", Engine.time_scale < 1.0)
	await _step(0.3)
	_ok("端到端：暴击顿帧后恢复 1.0", absf(Engine.time_scale - 1.0) < 0.001)
	# 收尾：本段发过 3 次 damage_dealt ⇒ 飘字 / 命中特效仍在场。
	# ⚠️ 必须等它们自然过期再 `_finish()`，否则 `quit()` 时被计为「ObjectDB instances were leaked」
	#    （实测：不等 = 5 leaked / 2 resources；等过 `DAMAGE_NUMBER_LIFETIME` 后归零）。
	await _step(GameConstants.DAMAGE_NUMBER_LIFETIME + 0.3)


func _finish() -> void:
	print("")
	if _fail == 0:
		print("===== 结果：0 项失败 =====")
	else:
		print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
