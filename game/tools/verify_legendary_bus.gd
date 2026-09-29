## 传奇特效总线接线实测（第三步 B3-4 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_legendary_bus.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## ⚠️ 与 `verify_legendary_effects.gd` 的**分工**（防「自洽式伪校验」，铁律 SF4）：
##    · `verify_legendary_effects` 测**结算器**（`LegendaryEffectSystem` 内部：概率/冷却/阈值/叠层）
##      —— 它直接调 `on_event()`，**不经过总线**，所以它全绿也证明不了特效「通没通电」。
##    · 本脚本测**接线**：建 `LegendaryBus` → 注册装备 → **发真实 EventBus 信号 / 触发钩子**
##      → 断言「真的发生了游戏行为」（扣血 / 回血 / 回蓝 / 反伤 / 免死 / 掉落 / 格挡）。
##      不调 `on_event()`，不读结算结果 —— 只认最终副作用。
##
## 覆盖（A~J）：
##   A. 注册 / 注销：register_equipped 计数、unregister 后失效、clear 清零
##   B. on_crit → deal_damage（烬誓叠 5 层引爆，真扣目标血）
##   C. on_crit → heal（血契回血）
##   D. on_crit → gain_resource（清醒回蓝）
##   E. on_skill_cast → resource_refund（终末回响：返还 + 冷却减半）
##   F. on_damage_taken → reflect（踏焰反伤，真打回攻击者）
##   G. 濒死 → revive_protect（不朽者免死 + 回血 + 抽干资源）
##   H. on_pickup_gold → extra_loot（拾遗者额外掉落 + limit_per_run 上限）
##   I. on_block → heal（守护·坚壁：格挡回血）—— 3-BL1 的验收
##   J. on_low_hp → heal（复苏：ctx.hp_pct 必须正确填，否则永不触发）—— 3-K9 的验收
extends Node

var _fail: int = 0
var _player: PlayerController = null
var _bus: LegendaryBus = null
var _dummy: DamageDummy = null
var _rng := RandomNumberGenerator.new()
## extra_loot 的注入回调计数（真实生成次数）
var _spawn_calls: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 传奇特效总线接线实测（B3-4）=====")
	seed(20260916)
	_rng.seed = 20260916
	_setup()
	await _test_register()
	await _test_deal_damage()
	await _test_heal()
	await _test_gain_resource()
	await _test_resource_refund()
	await _test_reflect()
	await _test_revive()
	await _test_extra_loot()
	await _test_block()
	await _test_low_hp()
	_finish()


func _setup() -> void:
	_player = get_node_or_null("/root/VerifyLegendaryBus/Player") as PlayerController
	_dummy = get_node_or_null("/root/VerifyLegendaryBus/Dummy") as DamageDummy
	_ok("场景就绪：玩家 + 靶子", _player != null and _dummy != null)
	if _player == null:
		return
	# 属性基线：裸装（攻击走基准公式）、无护甲/闪避/格挡 ⇒ 受击伤害确定
	_player.apply_combat_stats({}, 1)
	_player.health.max_hp_override = 1000.0
	_player.health.current_hp = 1000.0
	# 总线：注入「生成掉落」与「精英判定」两个回调
	_bus = LegendaryBus.new()
	_bus.name = "LegendaryBus"
	add_child(_bus)
	_bus.setup(_player, _on_spawn_loot, func(_u: Node) -> bool: return false)
	_ok("总线挂载 + 钩子注入（revive / damaged）",
		_player.health.revive_hook.is_valid() and _player.health.damaged_hook.is_valid())


## 生成掉落的注入回调（只计数，不真建节点）
func _on_spawn_loot(_entry: Dictionary, _pos: Vector2) -> void:
	_spawn_calls += 1


## 造一件挂了指定传奇特效的装备
func _make_item(effect_id: String) -> EquipmentInstance:
	var tpl := ConfigLoader.get_equipment_template("sword_iron")
	var item := AffixRoller.roll_full_equipment(tpl, 20, GameConstants.Rarity.LEGENDARY, _rng)
	item.legendary_effect_id = effect_id
	return item


## 每个用例前：清注册表 + 满血满蓝
func _reset() -> void:
	LegendaryEffectSystem.clear()
	_player.health.is_dead = false
	_player.health.current_hp = 1000.0
	_player.health.max_hp_override = 1000.0
	_player.get_mana_pool().set_current(100.0)
	_dummy.reset(100000.0)
	_spawn_calls = 0
	# 清掉可能残留的注入属性（攻击走基准 / 无格挡）
	_player.apply_combat_stats({}, 1)


# =============================================================================
# A. 注册 / 注销
# =============================================================================

func _test_register() -> void:
	print("--- A. 注册 / 注销 ---")
	_reset()
	var a := _make_item("jin_shi_ran_po_ren")
	var b := _make_item("xue_qi_xi_xue_lian")
	_bus.register_equipped([a, b])
	_ok("register_equipped 两件 ⇒ 注册数 = 2", _bus.registered_count() == 2)
	_bus.unregister_item(a)
	_ok("unregister 一件 ⇒ 注册数 = 1", _bus.registered_count() == 1)
	# 注销后该特效真的失效：只剩「血契（on_crit 回血）」，不再有「烬誓（叠层引爆）」
	_dummy.reset(100000.0)
	for i in range(5):
		EventBus.damage_dealt.emit(_dummy, 10.0, true, "physical")
	_ok("注销后烬誓失效（5 次暴击不引爆 ⇒ 靶子零伤害）",
		is_equal_approx(_dummy.total_damage_taken, 0.0))
	_bus.clear()
	_ok("clear 后注册表为空", _bus.registered_count() == 0)


# =============================================================================
# B. on_crit → deal_damage（烬誓·燃魄刃）
# =============================================================================

func _test_deal_damage() -> void:
	print("--- B. on_crit → deal_damage（烬誓叠层引爆）---")
	_reset()
	_bus.register_item(_make_item("jin_shi_ran_po_ren"))
	var atk := _player.get_attack_damage()
	# 4 次暴击只叠层，不引爆
	for i in range(4):
		EventBus.damage_dealt.emit(_dummy, 10.0, true, "physical")
	_ok("叠 4 层未引爆（靶子零伤害）", is_equal_approx(_dummy.total_damage_taken, 0.0))
	# 第 5 次引爆：300% 攻击力火伤（area=true ⇒ 走范围查询命中靶子）
	EventBus.damage_dealt.emit(_dummy, 10.0, true, "physical")
	_ok("叠满 5 层引爆 300%% 攻击力（%.1f，攻击力 %.1f）" % [atk * 3.0, atk],
		is_equal_approx(_dummy.total_damage_taken, atk * 3.0))
	# 非暴击走 on_hit，不触发烬誓（它是 on_crit）
	_dummy.reset(100000.0)
	EventBus.damage_dealt.emit(_dummy, 10.0, false, "physical")
	_ok("非暴击（on_hit）不触发烬誓", is_equal_approx(_dummy.total_damage_taken, 0.0))


# =============================================================================
# C. on_crit → heal（血契·吸血链）
# =============================================================================

func _test_heal() -> void:
	print("--- C. on_crit → heal（血契回血）---")
	_reset()
	_bus.register_item(_make_item("xue_qi_xi_xue_lian"))
	_player.health.current_hp = 500.0
	EventBus.damage_dealt.emit(_dummy, 10.0, true, "physical")
	# heal_pct 0.03 × 1000 = 30 ⇒ 500 → 530
	_ok("暴击回血 3% 最大生命（500 → 530）",
		is_equal_approx(_player.health.current_hp, 530.0))


# =============================================================================
# D. on_crit → gain_resource（清醒·洞察冠）
# =============================================================================

func _test_gain_resource() -> void:
	print("--- D. on_crit → gain_resource（清醒回蓝）---")
	_reset()
	_bus.register_item(_make_item("qing_xing_dong_cha_guan"))
	_player.get_mana_pool().set_current(50.0)
	# 概率 0.35；失败不消耗冷却 ⇒ 连续尝试必中一次（冷却 0.5s 会拦住后续）
	for i in range(30):
		EventBus.damage_dealt.emit(_dummy, 10.0, true, "physical")
	_ok("暴击概率回蓝（50 → >50，单次 +5）",
		_player.get_mana_pool().current > 50.0 and _player.get_mana_pool().current <= 55.0)


# =============================================================================
# E. on_skill_cast → resource_refund（终末回响）
# =============================================================================

func _test_resource_refund() -> void:
	print("--- E. on_skill_cast → resource_refund（终末回响）---")
	_reset()
	_bus.register_item(_make_item("zhong_mo_hui_xiang"))
	var sc := _player.get_skill_controller()
	# 先真施放一次技能：扣 30 蓝 + 进 7s 冷却
	_player.get_mana_pool().set_current(100.0)
	_ok("裂斩施放成功（扣蓝进冷却）", sc.try_cast("cleave"))
	var cd_after_cast := sc.get_cooldown_remaining("cleave")
	# 模拟多次施法：概率 0.2 ⇒ 至少触发一次 ⇒ 返还 30 蓝 + 冷却减半
	for i in range(30):
		EventBus.skill_cast.emit("cleave", 30.0)
	_ok("资源返还（蓝量回升到 >70）", _player.get_mana_pool().current > 70.0)
	_ok("冷却减半（%.2fs < 施放后的 %.2fs）" % [sc.get_cooldown_remaining("cleave"), cd_after_cast],
		sc.get_cooldown_remaining("cleave") < cd_after_cast)
	_ok("冷却不低于兜底下限 0.2s",
		sc.get_cooldown_remaining("cleave") >= GameConstants.SKILL_MIN_COOLDOWN_SEC - 0.0001)


# =============================================================================
# F. on_damage_taken → reflect（踏焰·火行靴）
# =============================================================================

func _test_reflect() -> void:
	print("--- F. on_damage_taken → reflect（踏焰反伤）---")
	_reset()
	_bus.register_item(_make_item("ta_yan_huo_xing_xue"))
	_player.health.current_hp = 900.0
	_dummy.reset(100000.0)
	# 玩家受击 40（经护甲减伤后的**实受伤**为基准）⇒ 反伤 = 25% × 实受伤 打回攻击者
	var before := _player.health.current_hp
	_player.health.take_damage(40.0, _dummy)
	var taken := before - _player.health.current_hp
	_ok("玩家正常扣血（实受伤 %.2f > 0）" % taken, taken > 0.0)
	_ok("反伤 = 25%% 实受伤（靶子受 %.2f，期望 %.2f）" % [_dummy.total_damage_taken, taken * 0.25],
		is_equal_approx(_dummy.total_damage_taken, taken * 0.25))


# =============================================================================
# G. 濒死 → revive_protect（不朽者的残躯）
# =============================================================================

func _test_revive() -> void:
	print("--- G. 濒死 → revive_protect（不朽者免死）---")
	_reset()
	_bus.register_item(_make_item("bu_xiu_zhe_de_can_qu"))
	_player.health.current_hp = 10.0
	_player.get_mana_pool().set_current(80.0)
	# 致命一击 50 > 10
	_player.health.take_damage(50.0, _dummy)
	_ok("免死：玩家未死亡", not _player.health.is_dead)
	_ok("免死：回复 30% 最大生命（300）",
		is_equal_approx(_player.health.current_hp, 300.0))
	_ok("免死：抽干资源（drain_resource）", is_equal_approx(_player.get_mana_pool().current, 0.0))
	# 冷却 90s 内二次致命 ⇒ 不再免死（真死）
	_player.health.current_hp = 10.0
	_player.health.take_damage(50.0, _dummy)
	_ok("90s 冷却内二次致命 ⇒ 不再免死（真死）", _player.health.is_dead)


# =============================================================================
# H. on_pickup_gold → extra_loot（拾遗者之靴）
# =============================================================================

func _test_extra_loot() -> void:
	print("--- H. on_pickup_gold → extra_loot（拾遗者额外掉落）---")
	_reset()
	_bus.register_item(_make_item("shi_yi_zhe_zhi_xue"))
	# 概率 0.15 ⇒ 大量拾取必触发；limit_per_run = 5 必须封顶
	for i in range(400):
		EventBus.loot_picked_up.emit({"type": "gold", "amount": 1})
	_ok("拾取金币触发额外掉落（生成次数 > 0）", _spawn_calls > 0)
	_ok("单局上限 5 次封顶（生成次数 = 5）", _spawn_calls == 5)
	# 非金币拾取不触发
	_spawn_calls = 0
	for i in range(50):
		EventBus.loot_picked_up.emit({"type": "material", "amount": 1})
	_ok("非金币拾取不触发（生成次数 = 0）", _spawn_calls == 0)


# =============================================================================
# I. on_block → heal（守护·坚壁 · 3-BL1 验收）
# =============================================================================

func _test_block() -> void:
	print("--- I. on_block → heal（守护·坚壁）---")
	_reset()
	_bus.register_item(_make_item("shou_hu_jian_bi"))
	# 格挡率 100% ⇒ 必定格挡
	_player.apply_combat_stats({"block_chance": 100.0}, 1)
	_player.health.current_hp = 500.0
	_dummy.reset(100000.0)
	# 受击 40：格挡减半 ⇒ 实扣 20；格挡回血 2%×1000 = 20
	_player.health.take_damage(40.0, _dummy)
	# 无回血时血量 = 480；有回血则被补偿到 ≥ 480（回血在减伤后、扣血前 ⇒ 净 500）
	_ok("格挡成功触发回血（血量 ≥ 480，纯减伤应为 480）",
		_player.health.current_hp >= 480.0)
	_ok("格挡回血确实生效（血量 ≠ 纯减伤值 480）",
		not is_equal_approx(_player.health.current_hp, 480.0))


# =============================================================================
# J. on_low_hp → heal（复苏·生命戒 · 3-K9 的 ctx.hp_pct 验收）
# =============================================================================

func _test_low_hp() -> void:
	print("--- J. on_low_hp → heal（复苏·生命戒）---")
	_reset()
	_bus.register_item(_make_item("fu_su_sheng_ming_jie"))
	# 先让总线轮询到「满血」，再把血打到 20%（< 阈值 30%）
	_player.health.current_hp = 1000.0
	await get_tree().process_frame
	_player.health.current_hp = 200.0
	await get_tree().process_frame
	await get_tree().process_frame
	# heal 10% × 1000 = 100 ⇒ 200 → 300
	_ok("低血轮询触发 on_low_hp 回血（200 → 300）—— ctx.hp_pct 已正确填入",
		is_equal_approx(_player.health.current_hp, 300.0))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
