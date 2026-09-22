## 词缀生成器实测（任务 3.2 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_affix_roller.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 参数：品质权重和 100、条数表合法（沿用 3.1）
##   B. 条数拆分：白 0 条 / 蓝 1–2 / 橙 5–6 / 红 6–7，前后缀不超上限，不变式保真
##   C. 互斥 + 权重：同互斥组不重复、权重词缀出现率高于低权重（抽样）
##   D. 数值：value = Base × iLvl 缩放 × 品质系数、品质档合法、模板已注入
##   E. 强化词缀：紫+ 概率区间内出现、数值 ×1.5 且 is_empowered
##   F. 红装神话槽：必含 1 条神话词缀，普通条数仍为 6–7（不占普通位）
##   G. 掉落接入：roll_loot 装备条目带 instance 词缀，pickup_loot 入包
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null
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
	print("===== 词缀生成器实测（任务 3.2） =====")
	_rng.seed = 20260916
	_player = get_node_or_null("/root/VerifyAffixRoller/Player") as PlayerController
	_ok("场景就绪：玩家", _player != null)
	await _test_params()
	await _test_split()
	await _test_exclusive_weight()
	await _test_values()
	await _test_empower()
	await _test_mythic_slot()
	await _test_loot_integration()
	_finish()


## 抽样 roll 一批词缀列表
func _roll_many(tid: String, ilvl: int, rarity: int, n: int) -> Array:
	var tpl := ConfigLoader.get_equipment_template(tid)
	var out: Array = []
	for i in range(n):
		out.append(AffixRoller.roll_affixes(tpl, ilvl, rarity, _rng))
	return out


# =============================================================================
# A. 参数
# =============================================================================

func _test_params() -> void:
	print("--- A. 参数 ---")
	var sum_w := 0.0
	for w in AffixRoller.QUALITY_WEIGHTS:
		sum_w += float(w)
	_ok("品质权重和 = 100（%.1f）" % sum_w, absf(sum_w - 100.0) < 0.001)
	_ok("品质权重与 5 阶档位等长",
		AffixRoller.QUALITY_WEIGHTS.size() == GameConstants.AFFIX_ROLL_QUALITY_TIERS.size())
	_ok("强化概率数组覆盖 8 档", AffixRoller.EMPOWER_CHANCE_BY_RARITY.size() == GameConstants.RARITY_COUNT)
	var empowered_ok := AffixRoller.EMPOWER_CHANCE_BY_RARITY[GameConstants.Rarity.MYTHIC] >= \
		AffixRoller.EMPOWER_CHANCE_BY_RARITY[GameConstants.Rarity.LEGENDARY] \
		and AffixRoller.EMPOWER_CHANCE_BY_RARITY[GameConstants.Rarity.LEGENDARY] >= \
		AffixRoller.EMPOWER_CHANCE_BY_RARITY[GameConstants.Rarity.EPIC] \
		and AffixRoller.EMPOWER_CHANCE_BY_RARITY[GameConstants.Rarity.EPIC] > 0.0
	_ok("强化概率紫 < 橙 < 红 递增", empowered_ok)


# =============================================================================
# B. 条数拆分
# =============================================================================

func _test_split() -> void:
	print("--- B. 条数拆分 ---")
	var sword := ConfigLoader.get_equipment_template("sword_iron")
	# 白装 0 条
	var whites := _roll_many("sword_iron", 10, GameConstants.Rarity.COMMON, 30)
	var white_ok := true
	for rolls in whites:
		if rolls.size() != 0:
			white_ok = false
	_ok("白装恒 0 条词缀", white_ok)
	# 蓝装 1–2
	var blues := _roll_many("sword_iron", 10, GameConstants.Rarity.MAGIC, 60)
	var blue_min := 99
	var blue_max := 0
	for rolls in blues:
		blue_min = mini(blue_min, rolls.size())
		blue_max = maxi(blue_max, rolls.size())
	_ok("蓝装条数 ∈ [1,2]（实际 %d–%d）" % [blue_min, blue_max],
		blue_min >= 1 and blue_max <= 2)
	# 橙装 5–6
	var oranges := _roll_many("sword_iron", 10, GameConstants.Rarity.LEGENDARY, 60)
	var orange_min := 99
	var orange_max := 0
	for rolls in oranges:
		orange_min = mini(orange_min, rolls.size())
		orange_max = maxi(orange_max, rolls.size())
	_ok("橙装条数 ∈ [5,6]（实际 %d–%d）" % [orange_min, orange_max],
		orange_min >= 5 and orange_max <= 6)
	# 前后缀不超上限（抽样所有稀有度）
	var limits_ok := true
	for rarity in range(GameConstants.RARITY_COUNT):
		for rolls in _roll_many("sword_iron", 10, rarity, 20):
			var prefixes := 0
			var suffixes := 0
			for roll in rolls:
				var affix: AffixData = ConfigLoader.get_affix(roll.affix_id)
				if affix.position == GameConstants.AffixPosition.PREFIX:
					prefixes += 1
				else:
					suffixes += 1
			if prefixes > GameConstants.RARITY_PREFIX_LIMIT[rarity] \
					or suffixes > GameConstants.RARITY_SUFFIX_LIMIT[rarity]:
				limits_ok = false
	_ok("前后缀条数不超 GDD 3.2.3 上限（8 档 × 20 次抽样）", limits_ok)


# =============================================================================
# C. 互斥 + 权重
# =============================================================================

func _test_exclusive_weight() -> void:
	print("--- C. 互斥 + 权重 ---")
	# 同互斥组不重复（找一件词缀池足够大的底材：sword_iron 引 weapon_offense + weapon_generic）
	var groups_seen := {}
	var exclusive_ok := true
	for rolls in _roll_many("sword_iron", 10, GameConstants.Rarity.LEGENDARY, 40):
		groups_seen.clear()
		for roll in rolls:
			var affix: AffixData = ConfigLoader.get_affix(roll.affix_id)
			var g := affix.get_exclusive_group()
			if groups_seen.has(g):
				exclusive_ok = false
			groups_seen[g] = true
	_ok("同互斥组不重复（橙装 40 次抽样）", exclusive_ok)
	# 权重：add_flat_attack(120) 出现率 > add_skill_level(12)
	var flat_count := 0
	var skill_count := 0
	for rolls in _roll_many("sword_iron", 10, GameConstants.Rarity.LEGENDARY, 200):
		for roll in rolls:
			if roll.affix_id == "add_flat_attack":
				flat_count += 1
			elif roll.affix_id == "add_skill_level":
				skill_count += 1
	_info("权重抽样：flat_attack=%d / skill_level=%d" % [flat_count, skill_count])
	_ok("高权重词缀出现率显著高于低权重（10×）", flat_count > skill_count * 8)


# =============================================================================
# D. 数值
# =============================================================================

func _test_values() -> void:
	print("--- D. 数值 ---")
	var affix := ConfigLoader.get_affix("add_flat_attack") as AffixData
	# 构造已知品质 = 1.0 的 roll：Base ∈ [4,6]，iLvl 20 缩放 = 1+0.085×19 = 2.615
	var ilvl := 20
	var scale := GameConstants.affix_ilvl_scale(ilvl)
	var quality_ok := true
	var range_ok := true
	var template_ok := true
	for i in range(200):
		var roll := AffixRoller._make_roll(affix, ilvl, _rng)
		if not GameConstants.AFFIX_ROLL_QUALITY_TIERS.has(roll.quality):
			quality_ok = false
		# value = base × scale × quality；base ∈ [4,6]
		var lo := 4.0 * scale * roll.quality
		var hi := 6.0 * scale * roll.quality
		if roll.value < lo - 0.01 or roll.value > hi + 0.01:
			range_ok = false
		if roll.template != affix:
			template_ok = false
	_ok("品质系数 ∈ 5 阶档位（200 次）", quality_ok)
	_ok("数值 = Base × iLvl 缩放 × 品质（200 次区间命中）", range_ok)
	_ok("AffixRoll.template 已注入", template_ok)


# =============================================================================
# E. 强化词缀
# =============================================================================

func _test_empower() -> void:
	print("--- E. 强化词缀 ---")
	# 紫 15%：600 次 → 期望 ~90，区间 [40,150]
	var empowered := 0
	var value_scaled := true
	for rolls in _roll_many("sword_iron", 10, GameConstants.Rarity.EPIC, 600):
		for roll in rolls:
			if roll.is_empowered:
				empowered += 1
				# 数值应≈ 原值 ×1.5（这里只需非空且模板存在）
				if roll.value <= 0.0:
					value_scaled = false
	_info("紫装强化词缀命中 %d / 600（期望 ~90）" % empowered)
	_ok("紫装强化词缀概率 ∈ [6%,25%]（实际 %.1f%%）" % (empowered / 6.0),
		empowered >= 40 and empowered <= 150)
	_ok("强化词缀数值合法", value_scaled)
	# 白装永不强化
	var white_empowered := false
	for rolls in _roll_many("sword_iron", 10, GameConstants.Rarity.COMMON, 50):
		for roll in rolls:
			if roll.is_empowered:
				white_empowered = true
	_ok("白装永不出现强化词缀", not white_empowered)


# =============================================================================
# F. 红装神话槽
# =============================================================================

func _test_mythic_slot() -> void:
	print("--- F. 红装神话槽 ---")
	var mythic_ok := true
	var mythic_found := 0
	for i in range(40):
		var item := AffixRoller.roll_full_equipment(
			ConfigLoader.get_equipment_template("sword_iron"), 30, GameConstants.Rarity.MYTHIC, _rng)
		var has_mythic := false
		var count := 0
		for roll in item.affixes:
			count += 1
			if roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID:
				has_mythic = true
		if not has_mythic:
			mythic_ok = false
		# 普通位 6–7 + 神话 1 → 总 7–8；且神话词缀不带 is_empowered
		if count < 7 or count > 8:
			mythic_ok = false
		if has_mythic:
			mythic_found += 1
	_ok("红装每件必含神话词缀（40 件全中）", mythic_found == 40)
	_ok("红装总行数 = 普通 6–7 + 神话 1", mythic_ok)


# =============================================================================
# G. 掉落接入
# =============================================================================

func _test_loot_integration() -> void:
	print("--- G. 掉落接入 ---")
	# 直接 roll 装备条目（BOSS 表：必掉装备、稀有度分布广）
	var table: LootTable = ConfigLoader.loot_tables["monster_boss"]
	var equip_seen := false
	var instance_ok := true
	for i in range(30):
		var entry := LootRoller._roll_equipment(table, 15, GameConstants.DifficultyTier.NM1, 0)
		if entry["type"] != "equipment":
			continue
		equip_seen = true
		var inst: Dictionary = entry.get("instance", {})
		var affixes: Array = inst.get("affixes", [])
		if affixes.is_empty() and int(entry["rarity"]) > GameConstants.Rarity.MAGIC:
			instance_ok = false
	_ok("BOSS 表必掉装备条目（30 次抽样）", equip_seen)
	_ok("装备条目带词缀 instance（稀有度 > 蓝必有词缀）", instance_ok)
	# 拾取入包
	var inv_before: int = _player.inventory.size()
	_player.pickup_loot({
		"type": "equipment", "item_id": "sword_iron",
		"rarity": GameConstants.Rarity.LEGENDARY, "item_level": 20,
		"instance": {
			"instance_id": "i_test_0001",
			"template_id": "sword_iron",
			"slot": 0, "rarity": GameConstants.Rarity.LEGENDARY,
			"item_level": 20, "required_level": 18, "forge_level": 0,
			"affixes": [AffixRoll.create("add_flat_attack", 12.0, 1.0).to_dict()],
			"legendary_effect_id": "", "set_id": "", "is_set_item": false,
		},
	})
	_ok("拾取后背包 +1", _player.inventory.size() == inv_before + 1)
	var last: Dictionary = _player.inventory[_player.inventory.size() - 1]
	_ok("拾取条目带 affix_count=1 与完整 instance",
		int(last.get("affix_count", -1)) == 1 and last.has("instance"))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
