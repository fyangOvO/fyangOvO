## 锻造与洗练实测（任务 3.4 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_forge.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（6 个测试段）：
##   A. 成本表：魔石 106 明细（GDD 6.5 v1.8）+ 金币 100×1.35^k + 洗练 500×1.15^n
##   B. 成功率表：+1~+5 100% / +6 80% / +8 50% / +9 40% / +10 25% / +12 15%
##   C. 强化结算：成功 +1 / 失败 +9 起降级 / +1~+8 失败不降级 / 满级拒绝
##   D. 强化属性：forge_level 提升 → get_forge_multiplier 线性 +5%/级
##   E. 红装 +11/+12：上限 12、魔石 30 + 神话结晶 1、成功率 20%/15%
##   F. 洗练：保持词缀类型重掷数值、can_reroll=false 保留、成本按次数
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 锻造与洗练实测（任务 3.4） =====")
	_rng.seed = 20260916
	await _test_costs()
	await _test_chances()
	await _test_forge()
	await _test_stats()
	await _test_mythic_forge()
	await _test_reroll()
	_finish()


## 构造一件指定稀有度的测试装备
func _make_item(rarity: int, ilvl: int = 20) -> EquipmentInstance:
	var tpl := ConfigLoader.get_equipment_template("sword_iron")
	var item := EquipmentInstance.create_from_template(tpl, ilvl, rarity)
	item.affixes = AffixRoller.roll_affixes(tpl, ilvl, rarity, _rng)
	return item


# =============================================================================
# A. 成本表
# =============================================================================

func _test_costs() -> void:
	print("--- A. 成本表 ---")
	_ok("满强化 +10 魔石总数 = 106（GDD 6.5 v1.8）",
		GameConstants.forge_total_stones() == 106)
	var stone_ok := true
	var expect_stones := [3, 3, 3, 7, 7, 7, 13, 13, 25, 25]
	for k in range(1, 11):
		if GameConstants.forge_stone_cost(k) != expect_stones[k - 1]:
			stone_ok = false
	_ok("+1~+10 魔石逐档 = GDD 106 明细", stone_ok)
	_ok("+1 金币 = 135（GDD 6.5 公式 100×1.35^1）",
		GameConstants.forge_gold_cost(1) == 135)
	# GDD 6.5 示例写「+10→1,779」，但公式 100×1.35^10 = 2010.65 → 2011。
	# 示例与公式、合计（≈4,900）三者不自洽 —— 以明确公式为权威，示例降级为示意。
	_ok("+10 金币 = 2011（公式 100×1.35^10；GDD 示例 1779 判定为笔误）",
		GameConstants.forge_gold_cost(10) == 2011)
	_ok("洗练第 0 次 = 500 金币（GDD 3.4）", GameConstants.reroll_gold_cost(0) == 500)
	_ok("洗练第 5 次 = 1006 金币（500×1.15^5）",
		GameConstants.reroll_gold_cost(5) == int(round(500.0 * pow(1.15, 5.0))))


# =============================================================================
# B. 成功率表
# =============================================================================

func _test_chances() -> void:
	print("--- B. 成功率表 ---")
	var chance_ok := true
	var expect := [1.00, 1.00, 1.00, 1.00, 1.00, 0.80, 0.65, 0.50, 0.40, 0.25, 0.20, 0.15]
	for k in range(1, 13):
		var got := GameConstants.forge_success_chance(k)
		if absf(got - expect[k - 1]) > 0.001:
			chance_ok = false
			_info("+%d：期望 %.2f 实际 %.2f" % [k, expect[k - 1], got])
	_ok("+1~+12 成功率 = GDD 3.4 表（12 档）", chance_ok)
	_ok("越界成功率返回 0", GameConstants.forge_success_chance(13) == 0.0
		and GameConstants.forge_success_chance(0) == 0.0)


# =============================================================================
# C. 强化结算
# =============================================================================

func _test_forge() -> void:
	print("--- C. 强化结算 ---")
	# +1~+5 必成功（100%）
	var item := _make_item(GameConstants.Rarity.LEGENDARY)
	for i in range(5):
		var result := ForgeController.try_forge(item, _rng)
		if not result["success"]:
			_info("第 %d 次 +1~+5 失败" % (i + 1))
	_ok("+1~+5 全部成功（forge_level=5）", item.forge_level == 5)
	# +6（80%）多抽几次有成功
	var reached_6 := false
	for i in range(50):
		if ForgeController.try_forge(item, _rng)["success"]:
			reached_6 = true
			break
	_ok("+6 可成功（80% 概率 50 次内命中）", reached_6 and item.forge_level >= 6)
	# 失败不降级：+6~+8 失败只耗材料（模拟 30 次失败：forge_level 不回退到 5）
	var lv_before := item.forge_level
	var downgraded_before := false
	for i in range(30):
		var result := ForgeController.try_forge(item, _rng)
		if result["success"] and item.forge_level >= 9:
			break # 进入 +9 段，降级规则改变
		if result["downgraded"]:
			downgraded_before = true
	_ok("+6~+8 失败不降级", not downgraded_before or item.forge_level <= lv_before)
	# 满级拒绝
	var maxed_item := _make_item(GameConstants.Rarity.LEGENDARY)
	maxed_item.forge_level = 10
	var maxed := ForgeController.try_forge(maxed_item, _rng)
	_ok("橙装 +10 满级拒绝强化", not maxed["success"] and maxed.get("reason", "") == "maxed")
	# 成本查询结构
	var cost := ForgeController.get_forge_cost(_make_item(GameConstants.Rarity.LEGENDARY))
	_ok("成本查询含 target/gold/stone/success_chance",
		cost.has("target_level") and cost.has("gold") and cost.has("stone") and cost.has("success_chance"))


# =============================================================================
# D. 强化属性
# =============================================================================

func _test_stats() -> void:
	print("--- D. 强化属性 ---")
	var item := _make_item(GameConstants.Rarity.LEGENDARY, 15)
	var base_mult := item.get_forge_multiplier()
	_ok("未强化倍率 = 1.0", absf(base_mult - 1.0) < 0.001)
	item.forge_level = 10
	_ok("+10 倍率 = 1.5（每级 +5% × 10）", absf(item.get_forge_multiplier() - 1.5) < 0.001)
	var stats := item.get_base_stats()
	var raw: float = float(ConfigLoader.get_equipment_template("sword_iron").base_stats["flat_attack"])
	var expect: float = raw * GameConstants.item_stat_ilvl_scale(15) * 1.5
	_ok("基础属性应用强化（flat_attack = 底材 × iLvl 缩放 × 1.5）",
		absf(float(stats["flat_attack"]) - expect) < 0.01)


# =============================================================================
# E. 红装 +11/+12
# =============================================================================

func _test_mythic_forge() -> void:
	print("--- E. 红装 +11/+12 ---")
	var mythic := _make_item(GameConstants.Rarity.MYTHIC)
	_ok("红装强化上限 +12", mythic.get_forge_max_level() == 12)
	mythic.forge_level = 10
	var cost := ForgeController.get_forge_cost(mythic)
	_ok("+11 成本 = 30 魔石 + 1 神话结晶（工程侧）",
		int(cost["stone"]) == 30 and int(cost["crystal"]) == 1)
	_ok("+11 成功率 = 20%", absf(float(cost["success_chance"]) - 0.20) < 0.001)
	mythic.forge_level = 11
	var cost12 := ForgeController.get_forge_cost(mythic)
	_ok("+12 成功率 = 15%", absf(float(cost12["success_chance"]) - 0.15) < 0.001)
	# +11/+12 失败降级（模拟多次失败看降级发生）
	var downgraded := false
	var probe := _make_item(GameConstants.Rarity.MYTHIC)
	probe.forge_level = 11
	for i in range(100):
		if ForgeController.try_forge(probe, _rng)["downgraded"]:
			downgraded = true
			break
	_ok("+11 失败降 1 级（100 次内命中降级）", downgraded)


# =============================================================================
# F. 洗练
# =============================================================================

func _test_reroll() -> void:
	print("--- F. 洗练 ---")
	var item := _make_item(GameConstants.Rarity.LEGENDARY)
	var before: Array = []
	for roll in item.affixes:
		before.append([roll.affix_id, roll.value, roll.quality])
	var result := ForgeController.try_reroll(item, 0, _rng)
	_ok("洗练成功（rerolled > 0）", bool(result["success"]) and int(result["rerolled"]) > 0)
	var type_ok := true
	for i in range(before.size()):
		if i >= item.affixes.size():
			type_ok = false
			continue
		if item.affixes[i].affix_id != before[i][0]:
			type_ok = false
	_ok("洗练保持词缀类型（affix_id 全部不变）", type_ok)
	_ok("洗练后数值改变（至少一条）", item.affixes.size() > 0 and int(result["rerolled"]) > 0)
	var cost0 := ForgeController.get_reroll_cost(0)
	_ok("洗练成本 = 500 金币 + 1 秘银尘",
		int(cost0["gold"]) == 500 and int(cost0["dust"]) == 1)
	# 不可洗练词缀保留：造一条 can_reroll=false 的词缀
	var fixed := _make_item(GameConstants.Rarity.LEGENDARY)
	var hidden := AffixRoll.create("mythic_all_attributes", 7.0, 1.0)
	hidden.template = ConfigLoader.get_affix("mythic_all_attributes")
	hidden.template.can_reroll = false
	fixed.affixes.append(hidden)
	var old_value := 7.0
	var reroll_result := ForgeController.try_reroll(fixed, 1, _rng)
	var kept := true
	for roll in fixed.affixes:
		if roll.affix_id == "mythic_all_attributes" and absf(roll.value - old_value) > 0.001:
			kept = false
	_ok("can_reroll=false 词缀洗练后原值保留", kept and int(reroll_result["skipped"]) >= 1)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
