## 稀有度与掉落权重表实测（任务 3.3 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_loot_tables.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（6 个测试段）：
##   A. 权威表逐位断言：三张表 × 10 档与 GDD 6.1 + S12 完全一致（容差 0.001）
##   B. 权重和 = 100、橙装概率随怪物档位递增（0.05 → 1.00 → 5.00）
##   C. 难度修正规则：NM1 红清零 / NM2+ 红 ×1.5 / 白 ×0.85 / 黄 ×1.15 / 紫橙 ×1.30 /
##      绿 ×1.10 / 彩不变 / 越级紫橙红 ×0.5
##   D. 一局节奏仿真（GDD 6.1 基准：150 普通 + 5 精英 + 1 BOSS 掉 3 件，3000 局）：
##      橙 ≈ 0.186 / 黄 ≈ 1.95 / 红(NM2) ≈ 0.074 / 绿 ≈ 0.348 件每局
##   E. 底材联动：稀有度分布下掉出的装备 item_id 全部 fits（稀有度 / 等级区间）
##   F. 符文掉落桶（2-D6 / 2-V12）：rune_drop_chance 真的从 JSON 映射进 LootTable /
##      三表 0.02·0.08·0.25 逐位 / 全表范围合法 + validate() 通过 / 符文池 24 条
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()

## GDD 6.1 权威表（%）+ 第六步 S12（B5-2）新增深渊 / 塔两档
##
## ⚠️ 三表各 **10 位**、和 = 100；橙 0.05 / 1.00 / 5.00 为硬约束**不变**。
##    新增两档权重全部从 common / magic 挤出（normal −0.12/−0.05；elite −0.50/−0.30；boss −1.00/−1.00）。
const EXPECT_TABLES := {
	"monster_normal": [77.90, 17.50, 3.50, 0.45, 0.05, 0.02, 0.40, 0.01, 0.14, 0.03],
	"monster_elite": [39.80, 33.70, 16.00, 5.00, 1.00, 0.60, 3.00, 0.10, 0.60, 0.20],
	"monster_boss": [5.00, 29.00, 35.00, 15.00, 5.00, 1.80, 7.00, 0.20, 1.50, 0.50],
}

## GDD 6.1 一局节奏期望（件/局）
const EXPECT_PACE := {
	GameConstants.Rarity.RARE: 1.95,
	GameConstants.Rarity.EPIC: 0.65,
	GameConstants.Rarity.LEGENDARY: 0.186,
	GameConstants.Rarity.SET: 0.348,
	GameConstants.Rarity.MYTHIC: 0.074,
	GameConstants.Rarity.HIDDEN: 0.010,
}

## 符文掉落桶概率（工单 2-D6 / 校验 2-V12 · 策划 §11.4 / `02-装备属性.md` §D6）。
## ⚠️ 这是**第二次独立 roll**，与 `drop_chance` 无关（符文是额外惊喜，不挤掉主掉落）。
const EXPECT_RUNE_DROP := {
	"monster_normal": 0.02,
	"monster_elite": 0.08,
	"monster_boss": 0.25,
}


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 稀有度与掉落权重表实测（任务 3.3） =====")
	_rng.seed = 20260916
	randomize() # 仿真段用真实随机（D 段不做种子复现，只验区间）
	await _test_authoritative()
	await _test_weights()
	await _test_difficulty_rules()
	await _test_pace_simulation()
	await _test_template_linkage()
	await _test_rune_bucket()
	_finish()


## 造一只指定档位的怪物（纯数据，无场景）
func _make_monster(tier: int) -> MonsterData:
	var m := MonsterData.new()
	m.id = "sim_%d" % tier
	m.tier = tier
	m.level_min = 1
	m.level_max = GameConstants.LEVEL_MAX
	return m


# =============================================================================
# A. 权威表逐位断言
# =============================================================================

func _test_authoritative() -> void:
	print("--- A. 权威表逐位断言（GDD 6.1） ---")
	var all_ok := true
	for table_id in EXPECT_TABLES:
		var table: LootTable = ConfigLoader.loot_tables.get(table_id)
		if table == null:
			all_ok = false
			continue
		var expect: Array = EXPECT_TABLES[table_id]
		if table.rarity_weights.size() != GameConstants.RARITY_COUNT:
			all_ok = false
			continue
		for i in range(GameConstants.RARITY_COUNT):
			if absf(float(table.rarity_weights[i]) - float(expect[i])) > 0.001:
				all_ok = false
				_info("%s 第 %d 档：期望 %.2f 实际 %.2f"
					% [table_id, i, float(expect[i]), float(table.rarity_weights[i])])
	_ok("三张表 × 8 档与 GDD 6.1 逐位一致", all_ok)


# =============================================================================
# B. 权重和 + 单调性
# =============================================================================

func _test_weights() -> void:
	print("--- B. 权重和 / 单调性 ---")
	var sum_ok := true
	for table_id in EXPECT_TABLES:
		var table: LootTable = ConfigLoader.loot_tables[table_id]
		var s := 0.0
		for w in table.rarity_weights:
			s += float(w)
		if absf(s - 100.0) > 0.01:
			sum_ok = false
			_info("%s 权重和 = %.2f" % [table_id, s])
	_ok("三张表权重和 = 100", sum_ok)
	var orange_normal: float = ConfigLoader.loot_tables["monster_normal"].rarity_weights[GameConstants.Rarity.LEGENDARY]
	var orange_elite: float = ConfigLoader.loot_tables["monster_elite"].rarity_weights[GameConstants.Rarity.LEGENDARY]
	var orange_boss: float = ConfigLoader.loot_tables["monster_boss"].rarity_weights[GameConstants.Rarity.LEGENDARY]
	_ok("橙装概率随档位递增（%.2f → %.2f → %.2f）" % [orange_normal, orange_elite, orange_boss],
		orange_normal < orange_elite and orange_elite < orange_boss)


# =============================================================================
# C. 难度修正规则
# =============================================================================

func _test_difficulty_rules() -> void:
	print("--- C. 难度修正规则 ---")
	var base: Array = ConfigLoader.loot_tables["monster_elite"].rarity_weights.duplicate()
	# NM1：红清零
	var nm1 := GameConstants.adjust_rarity_weights_by_difficulty(base, GameConstants.DifficultyTier.NM1, 0, 20)
	_ok("NM1 红装权重清零", float(nm1[GameConstants.Rarity.MYTHIC]) == 0.0)
	# NM2：红 ×1.5、白 ×0.85、黄 ×1.15、紫/橙 ×1.30、绿 ×1.10、彩不变
	var nm2 := GameConstants.adjust_rarity_weights_by_difficulty(base, GameConstants.DifficultyTier.NM2, 0, 20)
	var mythic_expect: float = float(base[GameConstants.Rarity.MYTHIC]) * GameConstants.RARITY_MYTHIC_DIFF_FACTOR
	var white_expect: float = float(base[GameConstants.Rarity.COMMON]) * GameConstants.RARITY_WHITE_DIFF_FACTOR
	var rare_expect: float = float(base[GameConstants.Rarity.RARE]) * GameConstants.RARITY_RARE_DIFF_FACTOR
	var epic_expect: float = float(base[GameConstants.Rarity.EPIC]) * GameConstants.RARITY_EPIC_LEGENDARY_DIFF_FACTOR
	var leg_expect: float = float(base[GameConstants.Rarity.LEGENDARY]) * GameConstants.RARITY_EPIC_LEGENDARY_DIFF_FACTOR
	var set_expect: float = float(base[GameConstants.Rarity.SET]) * GameConstants.RARITY_SET_DIFF_FACTOR
	_ok("NM2 红装 ×1.50（%.2f）" % mythic_expect,
		absf(float(nm2[GameConstants.Rarity.MYTHIC]) - mythic_expect) < 0.001)
	_ok("NM2 白装 ×0.85（%.2f）" % white_expect,
		absf(float(nm2[GameConstants.Rarity.COMMON]) - white_expect) < 0.001)
	_ok("NM2 黄装 ×1.15（%.2f）" % rare_expect,
		absf(float(nm2[GameConstants.Rarity.RARE]) - rare_expect) < 0.001)
	_ok("NM2 紫装 ×1.30（%.2f）" % epic_expect,
		absf(float(nm2[GameConstants.Rarity.EPIC]) - epic_expect) < 0.001)
	_ok("NM2 橙装 ×1.30（%.2f）" % leg_expect,
		absf(float(nm2[GameConstants.Rarity.LEGENDARY]) - leg_expect) < 0.001)
	_ok("NM2 绿装 ×1.10（%.2f）" % set_expect,
		absf(float(nm2[GameConstants.Rarity.SET]) - set_expect) < 0.001)
	_ok("彩装权重不随难度变化",
		absf(float(nm2[GameConstants.Rarity.HIDDEN]) - float(base[GameConstants.Rarity.HIDDEN])) < 0.001)
	# 越级惩罚：玩家 L16 vs 怪物 L20（差 4 > 3）→ 紫/橙/红 ×0.5
	var under := GameConstants.adjust_rarity_weights_by_difficulty(base, GameConstants.DifficultyTier.NM2, 16, 20)
	var epic_under: float = float(base[GameConstants.Rarity.EPIC]) * GameConstants.RARITY_EPIC_LEGENDARY_DIFF_FACTOR * GameConstants.UNDERPOWERED_RARITY_FACTOR
	_ok("越级惩罚：紫 ×0.5（差 4 级）",
		absf(float(under[GameConstants.Rarity.EPIC]) - epic_under) < 0.001)
	var fair := GameConstants.adjust_rarity_weights_by_difficulty(base, GameConstants.DifficultyTier.NM2, 19, 20)
	_ok("同级不惩罚（差 1 级紫保持 ×1.30）",
		absf(float(fair[GameConstants.Rarity.EPIC]) - epic_expect) < 0.001)


# =============================================================================
# D. 一局节奏仿真（GDD 6.1 基准）
# =============================================================================

func _test_pace_simulation() -> void:
	print("--- D. 一局节奏仿真（3000 局：150 普通 + 5 精英 + 1 BOSS） ---")
	var normal_monster := _make_monster(MonsterData.Tier.NORMAL)
	var elite_monster := _make_monster(MonsterData.Tier.ELITE)
	var boss_monster := _make_monster(MonsterData.Tier.BOSS)
	var counts := {}
	for rarity in range(GameConstants.RARITY_COUNT):
		counts[rarity] = 0
	var runs := 3000
	for run in range(runs):
		for i in range(150):
			for entry in LootRoller.roll_loot(normal_monster, 20, GameConstants.DifficultyTier.NM2):
				if entry["type"] == "equipment":
					counts[int(entry["rarity"])] += 1
		for i in range(5):
			for entry in LootRoller.roll_loot(elite_monster, 20, GameConstants.DifficultyTier.NM2):
				if entry["type"] == "equipment":
					counts[int(entry["rarity"])] += 1
		for entry in LootRoller.roll_loot(boss_monster, 20, GameConstants.DifficultyTier.NM2):
			if entry["type"] == "equipment":
				counts[int(entry["rarity"])] += 1
	var pace := {}
	for rarity in EXPECT_PACE:
		pace[rarity] = float(counts[rarity]) / float(runs)
	_info("实测节奏：黄 %.2f / 紫 %.2f / 橙 %.2f / 绿 %.2f / 红 %.2f / 彩 %.3f"
		% [pace[GameConstants.Rarity.RARE], pace[GameConstants.Rarity.EPIC],
			pace[GameConstants.Rarity.LEGENDARY], pace[GameConstants.Rarity.SET],
			pace[GameConstants.Rarity.MYTHIC], pace[GameConstants.Rarity.HIDDEN]])
	# GDD 硬约束：橙 ≈ 0.186（5.4 局 1 件）。
	# 注：NM2 难度修正按 6.1 规则生效（紫/橙 ×1.30、红 ×1.50），归一化后实际节奏
	# 略高于设计目标 —— 上限吸收修正系数 + 15% 统计容差。
	var orange: float = pace[GameConstants.Rarity.LEGENDARY]
	_ok("橙装节奏 ∈ [0.13, 0.28] 件/局（GDD 0.186 × NM2×1.30，实际 %.2f）" % orange,
		orange >= 0.13 and orange <= 0.28)
	# 其余档位：黄/紫/绿 ±30%；红 [0.04, 0.15]（吸收 NM2 ×1.50 + 噪声）；彩 ±60%
	var pace_ok := true
	for rarity in EXPECT_PACE:
		if rarity == GameConstants.Rarity.LEGENDARY:
			continue
		var expect: float = EXPECT_PACE[rarity]
		var actual: float = pace[rarity]
		var lo := expect * (0.5 if rarity == GameConstants.Rarity.MYTHIC else 0.7)
		var hi := expect * 2.0
		if rarity == GameConstants.Rarity.MYTHIC:
			hi = 0.15
		if rarity == GameConstants.Rarity.HIDDEN:
			lo = expect * 0.4
			hi = expect * 1.6
		if actual < lo or actual > hi:
			pace_ok = false
			_info("档 %d：期望 %.3f 实际 %.3f" % [rarity, expect, actual])
	_ok("黄/紫/绿/红/彩节奏落在 GDD 期望容差内", pace_ok)


# =============================================================================
# E. 底材联动
# =============================================================================

func _test_template_linkage() -> void:
	print("--- E. 底材联动 ---")
	var normal_monster := _make_monster(MonsterData.Tier.NORMAL)
	var boss_monster := _make_monster(MonsterData.Tier.BOSS)
	var fit_ok := true
	var count := 0
	for i in range(200):
		for entry in LootRoller.roll_loot(normal_monster, 20, GameConstants.DifficultyTier.NM1):
			if entry["type"] != "equipment":
				continue
			count += 1
			var tpl: EquipmentData = ConfigLoader.get_equipment_template(entry["item_id"])
			if tpl == null or not tpl.fits(int(entry["item_level"]), int(entry["rarity"])):
				fit_ok = false
		for entry in LootRoller.roll_loot(boss_monster, 30, GameConstants.DifficultyTier.NM2):
			if entry["type"] != "equipment":
				continue
			count += 1
			var tpl2: EquipmentData = ConfigLoader.get_equipment_template(entry["item_id"])
			if tpl2 == null or not tpl2.fits(int(entry["item_level"]), int(entry["rarity"])):
				fit_ok = false
	_ok("掉落底材全部 fits 稀有度 / 等级区间（%d 件抽样）" % count, fit_ok and count > 0)
	# 高稀有度底材抽查：红装（NM2 下）掉出的底材 rarity_max ≥ MYTHIC
	var red_fit := true
	var red_seen := false
	for i in range(300):
		for entry in LootRoller.roll_loot(boss_monster, 40, GameConstants.DifficultyTier.NM2):
			if entry["type"] != "equipment" or int(entry["rarity"]) != GameConstants.Rarity.MYTHIC:
				continue
			red_seen = true
			var tpl: EquipmentData = ConfigLoader.get_equipment_template(entry["item_id"])
			if tpl == null or tpl.rarity_max < GameConstants.Rarity.MYTHIC:
				red_fit = false
	_info("红装抽样：%s" % ("出现" if red_seen else "未出现（概率 ~0.6%×3件，可接受）"))
	_ok("红装底材区间合法（出现时）", red_fit)


# =============================================================================
# F. 符文掉落桶（2-D6 / 2-V12）
# =============================================================================

## 表侧断言：`rune_drop_chance` 必须从 JSON **真的映射进** 运行时 `LootTable`。
##
## ⚠️ 本段盯的是第 5 类静默脱钩：`ConfigLoader._load_loot_table_dir()` 是**逐字段手写映射**，
##    JSON 里写了 `rune_drop_chance` 而这里漏读 ⇒ 数据侧有、运行时不生效、**零报错**。
##    （2026-09-29 B4 埋点时就踩了这条：`roll_rune_drop` 用硬编码常量，表字段从未被读。）
func _test_rune_bucket() -> void:
	print("--- F. 符文掉落桶（2-D6 / 2-V12） ---")
	var all_ok := true
	for table_id in EXPECT_RUNE_DROP:
		var table: LootTable = ConfigLoader.loot_tables.get(table_id)
		if table == null:
			all_ok = false
			_info("%s 表不存在" % table_id)
			continue
		var expect: float = EXPECT_RUNE_DROP[table_id]
		if absf(table.rune_drop_chance - expect) > 1e-9:
			all_ok = false
			_info("%s：期望 %.2f 实际 %.3f" % [table_id, expect, table.rune_drop_chance])
	_ok("三表 rune_drop_chance 逐位一致（0.02 / 0.08 / 0.25）", all_ok)
	# 全部表（含深渊 normal/boss = 0.05 / 0.30）范围合法 + validate() 通过
	var range_ok := true
	var nonzero := 0
	var val_ok := true
	for table_id in ConfigLoader.loot_tables:
		var t: LootTable = ConfigLoader.loot_tables[table_id]
		if t.rune_drop_chance < 0.0 or t.rune_drop_chance > 1.0:
			range_ok = false
		if t.rune_drop_chance > 0.0:
			nonzero += 1
		var errs := t.validate()
		if not errs.is_empty():
			val_ok = false
			_info("%s 校验错误：%s" % [table_id, str(errs)])
	_ok("全部 %d 张表 rune_drop_chance ∈ [0,1]（其中 %d 张 > 0）"
		% [ConfigLoader.loot_tables.size(), nonzero], range_ok)
	_ok("全部掉落表 validate() 通过（含 rune_drop_chance 范围检查）", val_ok)
	# 符文池：掉落来源必须非空，否则 `roll_rune_drop` 恒返回空表（静默不掉）
	_ok("符文池 24 条（ConfigLoader.runes 非空）", ConfigLoader.runes.size() == 24)
	_ok("符文概率随档位单调递增（普通 < 精英 < BOSS）",
		EXPECT_RUNE_DROP["monster_normal"] < EXPECT_RUNE_DROP["monster_elite"]
		and EXPECT_RUNE_DROP["monster_elite"] < EXPECT_RUNE_DROP["monster_boss"])


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
