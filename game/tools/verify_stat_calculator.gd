## 属性结算系统实测（任务 3.9 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_stat_calculator.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 裸装成长：GDD 6.2 表逐级断言（L1/L5/L10/L15/L20 三属性）
##   B. 装备聚合：sum_equipment 逐件累加（含强化倍率）
##   C. 最终结算：flat + pct 乘算（攻击 = (基础+flat) × (1+pct%)）
##   D. 神话全属性：all_attributes 乘主属性三件套
##   E. Buff 叠加：flat / pct 并入
##   F. 直接累加键：暴击 / 攻速 / 抗性 / 幸运等
##   G. 满装估算：L20 满强化 AD 相对裸装 ×6–8（GDD 6.2 口径）
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 属性结算系统实测（任务 3.9） =====")
	_rng.seed = 20260916
	await _test_base()
	await _test_sum()
	await _test_calc()
	await _test_mythic()
	await _test_buff()
	await _test_direct()
	await _test_full_gear()
	_finish()


func _near(a: float, b: float, tol: float = 0.5) -> bool:
	return absf(a - b) <= tol


# =============================================================================
# A. 裸装成长（GDD 6.2 权威表）
# =============================================================================

func _test_base() -> void:
	print("--- A. 裸装成长（GDD 6.2） ---")
	var expect := [
		[1, 150.0, 12.0, 6.0],
		[5, 228.0, 17.6, 8.8],
		[10, 384.0, 28.3, 14.1],
		[15, 647.0, 45.6, 22.8],
		[20, 1090.0, 73.4, 36.7],
	]
	for row in expect:
		var s := StatCalculator.base_stats(row[0])
		_ok("L%d 裸装 HP %.0f / AD %.1f / ARM %.1f" % [row[0], row[1], row[2], row[3]],
			_near(s["flat_hp"], row[1]) and _near(s["flat_attack"], row[2]) and _near(s["flat_armor"], row[3]))
	_ok("L1 精确 = Base1", StatCalculator.base_stats(1)["flat_attack"] == 12.0)
	_ok("等级 <1 按 1 处理", StatCalculator.base_stats(0)["flat_hp"] == 150.0)


# =============================================================================
# B. 装备聚合
# =============================================================================

func _test_sum() -> void:
	print("--- B. 装备聚合 ---")
	var item := _make_item(GameConstants.Rarity.RARE, 20, "sword_iron", ["add_flat_attack", "add_flat_hp"])
	var total := StatCalculator.sum_equipment([item])
	var single := EquipmentCompare.get_total_stats(item)
	_ok("单件汇总与 EquipmentCompare 一致",
		absf(float(total.get("flat_attack", 0.0)) - float(single.get("flat_attack", 0.0))) < 0.01)
	var two := StatCalculator.sum_equipment([item, item])
	_ok("两件累加 = 单件 ×2",
		absf(float(two.get("flat_attack", 0.0)) - float(single.get("flat_attack", 0.0)) * 2.0) < 0.01)
	_ok("空数组返回空表", StatCalculator.sum_equipment([]).is_empty())
	_ok("null 元素跳过", StatCalculator.sum_equipment([null, item]).size() == single.size())


# =============================================================================
# C. 最终结算
# =============================================================================

func _test_calc() -> void:
	print("--- C. 最终结算（flat + pct 乘算） ---")
	var item := _make_item(GameConstants.Rarity.RARE, 20, "sword_iron", ["add_pct_attack"])
	var stats := StatCalculator.calculate(1, [item])
	var base := StatCalculator.base_stats(1)
	var pct_sum := _pct_of(item, "pct_attack")
	_ok("L1 攻击 = 12 × (1 + %%)", _near(stats["attack"], base["flat_attack"] * (1.0 + pct_sum / 100.0)))
	_ok("HP 不受攻击词缀影响", _near(stats["max_hp"], 150.0))
	var item2 := _make_item(GameConstants.Rarity.RARE, 20, "sword_iron", ["add_flat_attack"])
	var stats2 := StatCalculator.calculate(1, [item2])
	_ok("flat 攻击直接相加",
		_near(stats2["attack"], 12.0 + float(EquipmentCompare.get_total_stats(item2).get("flat_attack", 0.0))))
	_ok("L5 裸装精确 228 HP", _near(StatCalculator.calculate(5, []).max_hp, 228.0))


func _pct_of(item: EquipmentInstance, key: String) -> float:
	var s := EquipmentCompare.get_total_stats(item)
	return float(s.get(key, 0.0))


# =============================================================================
# D. 神话全属性
# =============================================================================

func _test_mythic() -> void:
	print("--- D. 神话全属性 ---")
	var myth := _make_item(GameConstants.Rarity.LEGENDARY, 30, "sword_iron", ["mythic_all_attributes"])
	var stats := StatCalculator.calculate(1, [myth])
	var all_pct := float(EquipmentCompare.get_total_stats(myth).get("all_attributes", 0.0))
	_ok("全属性% 乘攻击", _near(stats["attack"], 12.0 * (1.0 + all_pct / 100.0)))
	_ok("全属性% 乘护甲", _near(stats["armor"], 6.0 * (1.0 + all_pct / 100.0)))
	_ok("全属性% 乘生命", _near(stats["max_hp"], 150.0 * (1.0 + all_pct / 100.0)))


# =============================================================================
# E. Buff 叠加
# =============================================================================

func _test_buff() -> void:
	print("--- E. Buff 叠加 ---")
	var buffs := {
		"berserk": {
			"flat": {"flat_attack": 10.0},
			"pct": {"pct_attack": 5.0},
		},
	}
	var stats := StatCalculator.calculate(1, [], buffs)
	_ok("Buff flat +10 / pct +5% → 22 × 1.05 = 23.1", _near(stats["attack"], 23.1))
	var stats2 := StatCalculator.calculate(1, [], {
		"rage": {"pct": {"pct_attack": 50.0}},
	})
	_ok("Buff pct +50% 攻击", _near(stats2["attack"], 12.0 * 1.5))
	var stats3 := StatCalculator.calculate(1, [], {
		"a": {"flat": {"flat_attack": 5.0}},
		"b": {"flat": {"flat_attack": 5.0}},
	})
	_ok("多 Buff 累加", _near(stats3["attack"], 22.0))


# =============================================================================
# F. 直接累加键
# =============================================================================

func _test_direct() -> void:
	print("--- F. 直接累加键 ---")
	var item := _make_item(GameConstants.Rarity.RARE, 20, "sword_iron",
		["add_crit_chance", "add_crit_damage", "add_fire_resist", "add_magic_find", "add_gold_gain"])
	var stats := StatCalculator.calculate(1, [item])
	var s := EquipmentCompare.get_total_stats(item)
	_ok("暴击率 = 词缀直接值", _near(stats["crit_chance"], s.get("crit_chance", 0.0)))
	_ok("暴击伤害 = 词缀直接值", _near(stats["crit_damage"], s.get("crit_damage", 0.0)))
	_ok("火焰抗性 = 词缀直接值", _near(stats["fire_resist"], s.get("fire_resist", 0.0)))
	_ok("掉落幸运 = 词缀直接值", _near(stats["magic_find"], s.get("magic_find", 0.0)))
	_ok("金币获取 = 词缀直接值", _near(stats["gold_gain"], s.get("gold_gain", 0.0)))
	_ok("未装备键默认 0", stats.get("block_chance", -1) == 0.0 and stats.get("dodge", -1) == 0.0)


# =============================================================================
# G. 满装估算（GDD 6.2 口径：L20 满装 AD ≈ 裸装 ×6–8）
# =============================================================================

func _test_full_gear() -> void:
	print("--- G. 满装估算 ---")
	var equipped: Array[EquipmentInstance] = []
	var slots := [GameConstants.EquipSlot.MAIN_HAND, GameConstants.EquipSlot.HELM,
		GameConstants.EquipSlot.CHEST, GameConstants.EquipSlot.BOOTS, GameConstants.EquipSlot.RING_A]
	var tpl_ids := ["sword_iron", "helm_hide", "chest_chainmail", "boots_wanderer", "ring_copper"]
	for i in range(slots.size()):
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(tpl_ids[i])
		var item := AffixRoller.roll_full_equipment(tpl, 20, GameConstants.Rarity.LEGENDARY, _rng)
		item.forge_level = 10
		equipped.append(item)
	var stats := StatCalculator.calculate(20, equipped)
	var bare := StatCalculator.base_stats(20)
	var ratio := float(stats["attack"]) / float(bare["flat_attack"])
	_ok("L20 满装（5 件橙 +10）AD 相对裸装 ×%0.1f" % ratio, ratio >= 2.0 and ratio <= 10.0)
	_ok("满装 HP 高于裸装", stats["max_hp"] > bare["flat_hp"])
	_ok("满装输出含关键键", stats.has("max_hp") and stats.has("attack") and stats.has("armor")
		and stats.has("crit_chance") and stats.has("magic_find"))
	# 套装加成并入（3.10）：2 件霜噬 → 元素伤害 +15
	var set2: Array[EquipmentInstance] = [
		AffixRoller.roll_full_equipment(ConfigLoader.get_equipment_template("set_frostbite_helm"),
			20, GameConstants.Rarity.SET, _rng),
		AffixRoller.roll_full_equipment(ConfigLoader.get_equipment_template("set_frostbite_chest"),
			20, GameConstants.Rarity.SET, _rng),
	]
	var set_stats := StatCalculator.calculate(20, set2)
	_ok("套装 2 件加成并入元素伤害 +15", _near(float(set_stats.get("elemental_damage", 0.0)), 15.0))


func _make_item(rarity: int, ilvl: int, template_id: String, affix_ids: Array[String]) -> EquipmentInstance:
	var item := EquipmentInstance.new()
	item.instance_id = "s_%d_%d" % [rarity, _rng.randi() % 100000]
	item.template_id = template_id
	item.slot = GameConstants.EquipSlot.MAIN_HAND
	item.item_level = ilvl
	item.rarity = rarity
	item.affixes = []
	for aid in affix_ids:
		var aff: AffixData = ConfigLoader.affixes.get(aid)
		if aff == null:
			continue
		var roll := AffixRoll.new()
		roll.affix_id = aid
		roll.template = aff
		roll.value = aff.roll_base_value(_rng) * GameConstants.affix_ilvl_scale(ilvl)
		roll.quality = 1
		item.affixes.append(roll)
	return item


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
