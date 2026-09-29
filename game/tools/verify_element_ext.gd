## 元素深化实测（第四步 B4 · `3-E7` 元素飘字配色 + `3-E8` 雷/暗异常）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_element_ext.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（9 个测试段）：
##   A. 元素配色表：6 元素齐备 + 两两不同 + `normal_color_for` 映射 + **暴击优先**（真实例化飘字）
##   B. 元素→异常映射：毒/火/冰/雷/暗；物理无异常
##   C. 异常常量自洽：AILMENTS 5 项 / 时长 > 0 / shock·curse 无 dot / 乘区合法
##   D. 感电易伤：受击伤害 ×1.20（玩家）
##   E. 感电**不**放大 DoT（防「感电+中毒」乘法雪球）
##   F. 诅咒降攻：玩家攻击力 ×0.80（唯一出口 `get_attack_damage`）
##   G. 诅咒降攻：敌人攻击力 ×0.80（与玩家同口径，对称）
##   H. 异常到期自动解除，效果随之消失
##   I. 零回归：无异常时攻击力 / 受击逐位不变
extends Node

const DAMAGE_NUMBER_SCENE := preload("res://scenes/juice/damage_number.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 元素深化实测（3-E7 飘字配色 / 3-E8 雷暗异常）=====")
	seed(20260929)
	_player = get_node_or_null("/root/VerifyElementExt/Player") as PlayerController
	_ok("场景就绪：玩家 + 生命组件", _player != null and _player.health != null)
	_test_element_colors()
	_test_element_ailment_map()
	_test_ailment_constants()
	await _test_shock_damage_taken()
	await _test_shock_not_amplify_dot()
	_test_curse_player_attack()
	_test_curse_enemy_attack()
	await _test_ailment_expiry()
	_test_zero_regression()
	_finish()


func _spawn_enemy(mid: String, pos: Vector2) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.monster_id = mid
	e.level = 1
	e.difficulty_tier = GameConstants.DifficultyTier.NM1
	add_child(e)
	e.global_position = pos
	return e


## 玩家复位：满血 + 清盾 + 清异常 + 复活 + 清注入
func _reset_player() -> void:
	_player.clear_combat_stats()
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	_player.health.current_hp = _player.get_max_hp()
	_player.health.shield = 0.0
	_player.health.is_dead = false
	_player.health._ailments.clear()
	_player.health.regeneration_per_second = 0.0


## 推进指定秒数的物理帧（约 60 帧/秒；DoT 在 process 帧 tick，物理帧近似同步）
func _step_physics(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for _i in range(frames):
		await get_tree().physics_frame


# =============================================================================
# A. 元素配色表（3-E7）
# =============================================================================

func _test_element_colors() -> void:
	print("--- A. 元素配色表（3-E7）---")
	var all_present := true
	for el in GameConstants.ELEMENTS:
		if not GameConstants.ELEMENT_COLORS.has(el):
			all_present = false
	_ok("ELEMENT_COLORS 覆盖全部 %d 个元素" % GameConstants.ELEMENTS.size(), all_present)
	_ok("ELEMENT_COLORS 条目数 == 元素数（无多余/遗漏）",
		GameConstants.ELEMENT_COLORS.size() == GameConstants.ELEMENTS.size())

	# 两两不同：6 元素各一色（防「两元素同色」而肉眼不可分）
	var distinct := true
	var seen: Array[Color] = []
	for el in GameConstants.ELEMENTS:
		var c: Color = GameConstants.ELEMENT_COLORS[el]
		for s in seen:
			if s.is_equal_approx(c):
				distinct = false
		seen.append(c)
	_ok("6 元素配色两两不同（各一色）", distinct)

	# normal_color_for：元素 → 元素色；空串 / 未知 → 普通色
	_ok("normal_color_for(\"fire\") == 火色",
		DamageNumber.normal_color_for("fire").is_equal_approx(GameConstants.ELEMENT_COLORS["fire"]))
	_ok("normal_color_for(\"shadow\") == 暗色",
		DamageNumber.normal_color_for("shadow").is_equal_approx(GameConstants.ELEMENT_COLORS["shadow"]))
	_ok("normal_color_for(\"\") 回退普通色",
		DamageNumber.normal_color_for("").is_equal_approx(GameConstants.COLOR_DAMAGE_NORMAL))
	_ok("normal_color_for(未知元素) 回退普通色",
		DamageNumber.normal_color_for("no_such_element").is_equal_approx(GameConstants.COLOR_DAMAGE_NORMAL))

	# 真实例化：**暴击优先**（暴击 + 火 ⇒ 暴击色；非暴击 + 火 ⇒ 火色）
	var num := DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	add_child(num)
	var lbl := num.get_node("Label") as Label
	num.setup(100.0, true, "fire")
	_ok("暴击优先：暴击 + 火 ⇒ 暴击色（非火色）",
		lbl.get_theme_color("font_color").is_equal_approx(GameConstants.COLOR_DAMAGE_CRIT))
	num.setup(100.0, false, "fire")
	_ok("非暴击 + 火 ⇒ 火色",
		lbl.get_theme_color("font_color").is_equal_approx(GameConstants.ELEMENT_COLORS["fire"]))
	num.setup(100.0, false, "")
	_ok("非暴击 + 空元素 ⇒ 普通色（旧调用方向后兼容）",
		lbl.get_theme_color("font_color").is_equal_approx(GameConstants.COLOR_DAMAGE_NORMAL))
	num.queue_free()


# =============================================================================
# B. 元素 → 异常映射（3-E8）
# =============================================================================

func _test_element_ailment_map() -> void:
	print("--- B. 元素→异常映射（3-E8）---")
	var pairs := {
		GameConstants.ELEMENT_POISON: GameConstants.AILMENT_POISON,
		GameConstants.ELEMENT_FIRE: GameConstants.AILMENT_BURN,
		GameConstants.ELEMENT_COLD: GameConstants.AILMENT_SLOW,
		GameConstants.ELEMENT_LIGHTNING: GameConstants.AILMENT_SHOCK,
		GameConstants.ELEMENT_SHADOW: GameConstants.AILMENT_CURSE,
	}
	for el in pairs.keys():
		_ok("ailment_from_element(%s) == %s" % [el, pairs[el]],
			GameConstants.ailment_from_element(el) == pairs[el])
	_ok("物理无异常（返回空串）",
		GameConstants.ailment_from_element(GameConstants.ELEMENT_PHYSICAL).is_empty())


# =============================================================================
# C. 异常常量自洽
# =============================================================================

func _test_ailment_constants() -> void:
	print("--- C. 异常常量自洽 ---")
	_ok("AILMENTS 共 5 种", GameConstants.AILMENTS.size() == 5)
	var has_all := (
		GameConstants.AILMENTS.has(GameConstants.AILMENT_SHOCK)
		and GameConstants.AILMENTS.has(GameConstants.AILMENT_CURSE))
	_ok("AILMENTS 含 shock / curse", has_all)
	var durations_ok := true
	for a in GameConstants.AILMENTS:
		if GameConstants.ailment_duration(a) <= 0.0:
			durations_ok = false
	_ok("全部异常时长 > 0", durations_ok)
	_ok("shock 无 dot（dps 比例 = 0）", GameConstants.ailment_dps_ratio(GameConstants.AILMENT_SHOCK) == 0.0)
	_ok("curse 无 dot（dps 比例 = 0）", GameConstants.ailment_dps_ratio(GameConstants.AILMENT_CURSE) == 0.0)
	_ok("感电易伤乘区 > 1（%.2f）" % GameConstants.shock_damage_taken_multiplier(),
		GameConstants.shock_damage_taken_multiplier() > 1.0)
	_ok("诅咒降攻乘区 ∈ (0,1)（%.2f）" % GameConstants.curse_damage_dealt_multiplier(),
		GameConstants.curse_damage_dealt_multiplier() > 0.0
		and GameConstants.curse_damage_dealt_multiplier() < 1.0)


# =============================================================================
# D. 感电易伤（受击 +20%）
# =============================================================================

func _test_shock_damage_taken() -> void:
	print("--- D. 感电易伤（玩家受击 ×1.20）---")
	var src := Node.new()
	add_child(src)
	# 基准：无异常
	_reset_player()
	var hp0 := _player.health.current_hp
	_player.take_damage(100.0, src)
	var base_loss := hp0 - _player.health.current_hp
	# 感电
	_reset_player()
	_player.health.apply_ailment_raw(GameConstants.AILMENT_SHOCK, 0.0, 3.0)
	var hp1 := _player.health.current_hp
	_player.take_damage(100.0, src)
	var shock_loss := hp1 - _player.health.current_hp
	_ok("感电时受击伤害 ×1.20（无 %.3f → 有 %.3f）" % [base_loss, shock_loss],
		base_loss > 0.0 and absf(shock_loss / base_loss - 1.2) < 0.01)
	src.queue_free()


# =============================================================================
# E. 感电不放大 DoT（防乘法雪球）
# =============================================================================

func _test_shock_not_amplify_dot() -> void:
	print("--- E. 感电不放大 DoT ---")
	# 中毒 alone
	_reset_player()
	_player.health.apply_ailment_raw(GameConstants.AILMENT_POISON, 10.0, 3.0)
	var h0 := _player.health.current_hp
	await _step_physics(1.0)
	var poison_loss := h0 - _player.health.current_hp
	# 中毒 + 感电
	_reset_player()
	_player.health.apply_ailment_raw(GameConstants.AILMENT_POISON, 10.0, 3.0)
	_player.health.apply_ailment_raw(GameConstants.AILMENT_SHOCK, 0.0, 3.0)
	var h1 := _player.health.current_hp
	await _step_physics(1.0)
	var both_loss := h1 - _player.health.current_hp
	_ok("感电不放大 DoT（毒 %.3f vs 毒+感电 %.3f）" % [poison_loss, both_loss],
		poison_loss > 0.0 and absf(both_loss - poison_loss) <= poison_loss * 0.05 + 0.1)


# =============================================================================
# F. 诅咒降攻（玩家）
# =============================================================================

func _test_curse_player_attack() -> void:
	print("--- F. 诅咒降攻（玩家）---")
	_reset_player()
	_player.apply_combat_stats({ "attack": 100.0 }, 1)
	_ok("无诅咒：攻击力 = 注入值 100",
		absf(_player.get_attack_damage() - 100.0) < 0.001)
	_player.health.apply_ailment_raw(GameConstants.AILMENT_CURSE, 0.0, 3.0)
	_ok("诅咒：攻击力 ×0.80 = 80（实际 %.3f）" % _player.get_attack_damage(),
		absf(_player.get_attack_damage() - 80.0) < 0.001)
	_player.clear_combat_stats()


# =============================================================================
# G. 诅咒降攻（敌人，对称）
# =============================================================================

func _test_curse_enemy_attack() -> void:
	print("--- G. 诅咒降攻（敌人，与玩家同口径）---")
	var e := _spawn_enemy("slime_acid", Vector2(200.0, 0.0))
	var raw := e.get_attack_damage()
	_ok("敌人攻击力 = 怪物表值（> 0）", raw > 0.0)
	e.health.apply_ailment_raw(GameConstants.AILMENT_CURSE, 0.0, 3.0)
	var cursed := e.get_attack_damage()
	_ok("敌人诅咒后攻击力 ×0.80（%.3f → %.3f）" % [raw, cursed],
		absf(cursed / raw - 0.8) < 0.001)
	e.queue_free()


# =============================================================================
# H. 异常到期自动解除
# =============================================================================

func _test_ailment_expiry() -> void:
	print("--- H. 异常到期自动解除 ---")
	_reset_player()
	_player.apply_combat_stats({ "attack": 100.0 }, 1)
	_player.health.apply_ailment_raw(GameConstants.AILMENT_SHOCK, 0.0, 0.2)
	_player.health.apply_ailment_raw(GameConstants.AILMENT_CURSE, 0.0, 0.2)
	_ok("施加后：感电 + 诅咒均在身",
		_player.health.has_ailment(GameConstants.AILMENT_SHOCK)
		and _player.health.has_ailment(GameConstants.AILMENT_CURSE))
	await _step_physics(0.6)
	_ok("到期后：感电已解除", not _player.health.has_ailment(GameConstants.AILMENT_SHOCK))
	_ok("到期后：诅咒已解除", not _player.health.has_ailment(GameConstants.AILMENT_CURSE))
	_ok("到期后：攻击力恢复满值 100", absf(_player.get_attack_damage() - 100.0) < 0.001)
	_player.clear_combat_stats()


# =============================================================================
# I. 零回归
# =============================================================================

func _test_zero_regression() -> void:
	print("--- I. 零回归（无异常逐位不变）---")
	_reset_player()
	# 注入攻击：无异常时 get_attack_damage 必须**逐位**等于注入值（不引入任何默认乘区）
	_player.apply_combat_stats({ "attack": 137.5 }, 1)
	_ok("无异常：get_attack_damage 逐位 == 注入值 137.5（零回归）",
		_player.get_attack_damage() == 137.5)
	# 未注入：回退裸装基线（仍受诅咒乘区影响 = 1.0 ⇒ 不变）
	_player.clear_combat_stats()
	var bare := _player.get_attack_damage()
	_ok("未注入：回退裸装基线且 > 0（无异常乘区 = 1.0）", bare > 0.0)


func _finish() -> void:
	print("")
	if _fail == 0:
		print("===== 结果：0 项失败 =====")
	else:
		print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
