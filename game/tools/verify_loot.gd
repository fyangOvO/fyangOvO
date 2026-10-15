## 掉落与拾取系统实测（任务 2.7 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_loot.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（11 个测试段）：
##   A. 掉落表数据：3 张表 / 权重 8 档且和为 100 / drop_chance 与件数区间合法
##   B. roll 基础：BOSS 表（drop_chance 1.0）必掉 2–4 件
##   C. 稀有度分布：普通怪权重 20k 次抽样白 > 蓝 > 黄、橙极低
##   D. 难度修正：NM1 红装清零 / NM2+ 开放 / 越级惩罚紫橙 ×0.5
##   E. 底材过滤：iLvl 区间 / 套装稀有度只出 set_id 底材 / iLvl clamp+三角抖动（4-W3·T10）
##   F. 敌人死亡掉落 + 拾取：BOSS 秒杀掉 2–4 件 LootDrop，玩家走近自动入账
##   G. 收编回归：敌人受击转发生命组件（无双重减伤）
##   H. 符文掉落桶（工单 2-L12 / 校验 2-V12）：三档概率读表 / 只产出合法 rune id / 与主掉落独立
##   I. 符文拾取：首获永久解锁 / 重复转魔石（与材料同口径）/ 结果写回载荷
##   J. 拾取反馈强化（2026-10-14）：光晕按类型/稀有度染色 / 史诗起整数放大 / 端到端真拾取
##   K. 掉落物弹出动画（2026-10-14）：抛物线飞行 + 落地回弹 / 未设起点不弹 / 只改位移不改 scale
##      / 磁吸接管即停 / **外部改写位置即让位** / 端到端（EnemyBase 已传死亡点）
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null
## 本脚本进入前的 `SaveManager.current_data`（符文拾取段需要存档对象；跑完还原）。
var _prev_save: SaveData = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 掉落与拾取系统实测 =====")
	_player = get_node_or_null("/root/VerifyLoot/Player") as PlayerController
	_ok("场景就绪：玩家", _player != null)
	# 符文拾取（段 I）需要写入 `SaveData.unlocked_runes`；本场景默认无存档对象。
	# `SaveData.new()` 的 account_level 回退值与「current_data == null」时的 `get_player_level()`
	# 同为 1 ⇒ 对既有段落（B–G）的越级惩罚判定**零影响**。
	_prev_save = SaveManager.current_data
	SaveManager.current_data = SaveData.new()
	await _test_tables()
	await _test_roll_basic()
	await _test_rarity_distribution()
	await _test_difficulty_adjust()
	await _test_template_filter()
	await _test_enemy_drop_and_pickup()
	await _test_mitigation_regression()
	await _test_rune_drop()
	await _test_rune_pickup()
	await _test_pickup_feedback()
	await _test_drop_pop()
	await _finish()


## 推进指定秒数的物理帧（约 60 帧/秒）
func _step_physics(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for i in range(frames):
		await get_tree().physics_frame


## 生成敌人（L1 / NM1，出生在 pos）
func _spawn_enemy(mid: String, pos: Vector2) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.monster_id = mid
	e.level = 1
	e.difficulty_tier = GameConstants.DifficultyTier.NM1
	add_child(e)
	e.global_position = pos
	return e


# =============================================================================
# A. 掉落表数据
# =============================================================================

func _test_tables() -> void:
	print("--- A. 掉落表数据 ---")
	_ok("掉落表 5 张（普通/精英/BOSS + 深渊 normal/boss · B5-6）", ConfigLoader.loot_tables.size() == 5)
	var normal: LootTable = ConfigLoader.loot_tables["monster_normal"]
	var elite: LootTable = ConfigLoader.loot_tables["monster_elite"]
	var boss: LootTable = ConfigLoader.loot_tables["monster_boss"]
	_ok("drop_chance 符合 GDD 6.1（8% / 60% / 100%）",
		absf(normal.drop_chance - 0.08) < 0.001 and absf(elite.drop_chance - 0.60) < 0.001
		and absf(boss.drop_chance - 1.0) < 0.001)
	var sum_w := 0.0
	for w in normal.rarity_weights:
		sum_w += float(w)
	_ok("普通表稀有度权重 8 档且和为 100 ± 0.01", absf(sum_w - 100.0) < 0.01)
	_ok("件数区间合法（BOSS 2–4 ≥ 精英 1–2 ≥ 普通 1–1）",
		boss.drop_count_range.x == 2 and boss.drop_count_range.y == 4
		and elite.drop_count_range.x == 1 and elite.drop_count_range.y == 2
		and normal.drop_count_range.x == 1 and normal.drop_count_range.y == 1)


# =============================================================================
# B. roll 基础
# =============================================================================

func _test_roll_basic() -> void:
	print("--- B. roll 基础 ---")
	seed(777)
	var boss_m: MonsterData = ConfigLoader.get_monster("boss_ember_lord")
	var drops := LootRoller.roll_loot(boss_m, 5, GameConstants.DifficultyTier.NM1, 1)
	_ok("BOSS 表（drop_chance 1.0）必掉 2–4 件", drops.size() >= 2 and drops.size() <= 4)
	var types_ok := true
	for d in drops:
		if not d.has("type") or not ["gold", "material", "equipment"].has(d["type"]):
			types_ok = false
	_ok("每件都有合法类型（金币 / 材料 / 装备）", types_ok)
	# 普通怪 8% 触发：200 次抽样应有掉落也有未掉落
	seed(778)
	var normal_m: MonsterData = ConfigLoader.get_monster("spider_cave")
	var drop_count := 0
	for i in 200:
		if not LootRoller.roll_loot(normal_m, 5, GameConstants.DifficultyTier.NM1, 1).is_empty():
			drop_count += 1
	_ok("普通怪 8% 触发（200 次抽样有掉有漏，掉 5–30 次）",
		drop_count >= 5 and drop_count <= 30)
	_info("      200 次触发 %d 次（≈%.1f%%）" % [drop_count, drop_count * 0.5])


# =============================================================================
# C. 稀有度分布
# =============================================================================

func _test_rarity_distribution() -> void:
	print("--- C. 稀有度分布 ---")
	seed(20260917)
	var weights: Array = ConfigLoader.loot_tables["monster_normal"].rarity_weights
	var counts: Array[int] = []
	for i in GameConstants.RARITY_COUNT:
		counts.append(0)
	for i in 20000:
		counts[LootRoller._roll_rarity(weights, GameConstants.DifficultyTier.NM1, 0, 1)] += 1
	_ok("普通怪稀有度：白 > 蓝 > 黄（20k 次抽样）",
		counts[GameConstants.Rarity.COMMON] > counts[GameConstants.Rarity.MAGIC]
		and counts[GameConstants.Rarity.MAGIC] > counts[GameConstants.Rarity.RARE])
	_ok("普通怪橙装极稀有（20k 次 ≈ 0.05% = 10 ± 12）",
		counts[GameConstants.Rarity.LEGENDARY] <= 22)
	_info("      分布：%s" % str(counts))


# =============================================================================
# D. 难度修正
# =============================================================================

func _test_difficulty_adjust() -> void:
	print("--- D. 难度修正 ---")
	var base: Array = ConfigLoader.loot_tables["monster_normal"].rarity_weights
	var w_nm1 := GameConstants.adjust_rarity_weights_by_difficulty(
		base, GameConstants.DifficultyTier.NM1, 0, 1)
	_ok("NM1 红装权重清零（仅梦魇 II+ 掉落）",
		w_nm1[GameConstants.Rarity.MYTHIC] == 0.0)
	var w_nm2 := GameConstants.adjust_rarity_weights_by_difficulty(
		base, GameConstants.DifficultyTier.NM2, 0, 1)
	_ok("NM2 红装开放（×1.5）", w_nm2[GameConstants.Rarity.MYTHIC]
		> float(base[GameConstants.Rarity.MYTHIC]))
	var w_under := GameConstants.adjust_rarity_weights_by_difficulty(
		base, GameConstants.DifficultyTier.NM1, 1, 10)
	_ok("越级惩罚：玩家 1 级 vs 怪 10 级 → 紫/橙 ×0.5",
		absf(float(w_under[GameConstants.Rarity.EPIC])
			- float(w_nm1[GameConstants.Rarity.EPIC]) * 0.5) < 0.001
		and absf(float(w_under[GameConstants.Rarity.LEGENDARY])
			- float(w_nm1[GameConstants.Rarity.LEGENDARY]) * 0.5) < 0.001)


# =============================================================================
# E. 底材过滤
# =============================================================================

func _test_template_filter() -> void:
	print("--- E. 底材过滤 ---")
	seed(20260918)
	var bad := 0
	var eq_count := 0
	var table: LootTable = ConfigLoader.loot_tables["monster_normal"]
	for i in 200:
		var d := LootRoller._roll_equipment(table, 5, GameConstants.DifficultyTier.NM1, 1)
		if d["type"] != "equipment":
			continue
		eq_count += 1
		# ⚠️ 判定用**实际 roll 出的 iLvl**，不写死 5 —— 2-L13 后 iLvl 是
		#    「怪等级 + 掉落表 item_level_spread 三角分布」的结果（normal 表 怪L5 ⇒ iLvl ∈ [2,8]），
		#    写死 5 会把合法的低/高 iLvl 底材误判成越界。
		var ilvl := int(d["item_level"])
		var t: EquipmentData = ConfigLoader.equipment_templates.get(d["item_id"])
		if t == null or int(d["rarity"]) < t.rarity_min or int(d["rarity"]) > t.rarity_max \
				or ilvl < t.item_level_min or ilvl > t.item_level_max:
			bad += 1
	_ok("装备底材按稀有度区间 / iLvl 区间过滤（200 次 roll 无越界）",
		eq_count >= 60 and bad == 0)
	_info("      200 次中装备 %d 件（装备占比 55%% ≈ %d）" % [eq_count, int(200 * 0.55)])
	# 套装稀有度只出 set_id 底材
	var t_set := LootRoller._pick_template(GameConstants.Rarity.SET, 5)
	_ok("套装稀有度只出带 set_id 的底材",
		t_set == null or not t_set.set_id.is_empty())
	# ---- 2-L13 / 2-V13：iLvl = 怪物等级 + 掉落表 item_level_spread 非对称三角分布 ----
	var t_normal: LootTable = ConfigLoader.loot_tables["monster_normal"]
	var t_elite: LootTable = ConfigLoader.loot_tables["monster_elite"]
	var t_boss: LootTable = ConfigLoader.loot_tables["monster_boss"]
	# normal：怪 L18 ±3（峰值 0）⇒ iLvl ∈ [15,21]，两端可达
	seed(20260928)
	var seen := {}
	var n_ok := true
	for i in 4000:
		var lv := LootRoller._roll_item_level(t_normal, 18)
		seen[lv] = int(seen.get(lv, 0)) + 1
		if lv < 15 or lv > 21:
			n_ok = false
	_ok("V13 normal：怪 L18 ±3 ⇒ iLvl ∈ [15,21] 且两端可达（峰值 18）",
		n_ok and seen.has(15) and seen.has(21))
	_info("      normal 抽样分布（L18）：%s" % str(seen))
	# boss：怪 L14 +3~+8（峰值 +5）⇒ iLvl ∈ [17,22]，两端可达（BOSS 必掉高 iLvl）
	var bseen := {}
	var b_ok := true
	for i in 4000:
		var blv := LootRoller._roll_item_level(t_boss, 14)
		bseen[blv] = int(bseen.get(blv, 0)) + 1
		if blv < 17 or blv > 22:
			b_ok = false
	_ok("V13 boss：怪 L14 +3~+8 ⇒ iLvl ∈ [17,22] 且两端可达（峰值 19）",
		b_ok and bseen.has(17) and bseen.has(22))
	_info("      boss 抽样分布（L14）：%s" % str(bseen))
	# elite：基础 ±2 ⇒ ≥16；另 10% 概率 +5 bonus，4000 次采样应能见到 >20
	var e_ok := true
	var e_bonus := false
	for i in 4000:
		var elv := LootRoller._roll_item_level(t_elite, 18)
		if elv < 16:
			e_ok = false
		if elv > 20:
			e_bonus = true
	_ok("V13 elite：怪 L18 基础 ±2（≥16），10% +5 bonus 采样可见 >20", e_ok and e_bonus)
	# 越级：iLvl 不再按玩家等级 clamp（BOSS 表 +3~+8 是表固有奖励）；normal 怪 L20 ⇒ [17,23]。
	# 越级平衡改由「稀有度越级惩罚（紫/橙/红 ×0.5）」+「装备需求等级 = ilvl-2」承担。
	var over_ok := true
	for i in 800:
		var lv20 := LootRoller._roll_item_level(t_normal, 20)
		if lv20 < 17 or lv20 > 23:
			over_ok = false
	_ok("V13 normal：怪 L20（与玩家等级无关）⇒ iLvl ∈ [17,23]；越级由稀有度层 + 需求等级兜底",
		over_ok and GameConstants.required_level_for(23) == 21)
	# 下限保护：L1 怪不会掉出 iLvl ≤ 0（iLvl 参与 item_stat_ilvl_scale / required_level_for）
	var floor_ok := true
	for i in 500:
		if LootRoller._roll_item_level(t_normal, 1) < 1:
			floor_ok = false
	_ok("L1 怪 iLvl ≥ 1（下限 max(1, 怪+min_mod)）", floor_ok)


# =============================================================================
# F. 敌人死亡掉落 + 拾取
# =============================================================================

func _test_enemy_drop_and_pickup() -> void:
	print("--- F. 敌人死亡掉落 + 拾取 ---")
	seed(20260919)
	_player.global_position = Vector2(0, 0)
	_player.gold = 0
	_player.materials = 0
	_player.inventory.clear()
	# 6-W6-20：稀有掉落广播（此前 `rare_loot_spawned` 声明了但 0 个 emit 点）。
	var rare_emits := [0]
	var cb := func(_item, _pos): rare_emits[0] += 1
	EventBus.rare_loot_spawned.connect(cb)
	var boss := _spawn_enemy("boss_ember_lord", Vector2(0, 120))
	await get_tree().physics_frame  # _refresh_player 拿到玩家引用
	boss.take_damage(999999.0, _player)  # 秒杀 → 组件死亡 → unit_died → 掉落 + 移除
	await _step_physics(0.35)  # 掉落弹出（pop delay 0.25）+ 移除完成
	_ok("BOSS 死亡后节点已移除", not is_instance_valid(boss))
	# ⚠️ 符文（2-L12）是**独立第二次 roll**，会与主掉落并存 ⇒ 「2–4 件」只统计**主掉落**，
	#    符文单独计数，否则 BOSS 掉 4 件主掉落 + 1 枚符文时这条会假红。
	var ground := get_tree().get_nodes_in_group(&"loot_drops")
	var drops: Array = []
	var rune_drops := 0
	for d in ground:
		if (d as LootDrop).drop_type == "rune":
			rune_drops += 1
		else:
			drops.append(d)
	_ok("BOSS 必掉 2–4 件主掉落地面物（符文另计）", drops.size() >= 2 and drops.size() <= 4)
	_info("      地面：主掉落 %d 件 + 符文 %d 枚" % [drops.size(), rune_drops])
	# emit 数应逐件等于「地面稀有(≥史诗)掉落数」—— 与 RNG 结果无关，故不 flaky。
	var rare_on_ground := 0
	for d in drops:
		if (d as LootDrop).rarity >= GameConstants.Rarity.EPIC:
			rare_on_ground += 1
	EventBus.rare_loot_spawned.disconnect(cb)
	_ok("rare_loot_spawned emit 数 == 地面稀有(≥史诗)掉落数（6-W6-20）",
		rare_emits[0] == rare_on_ground)
	_info("      本局稀有(≥史诗)掉落 %d 件 / 广播 %d 次" % [rare_on_ground, rare_emits[0]])
	# 走近拾取（掉落物撒在死亡点 ±14px）
	_player.global_position = Vector2(0, 120)
	await _step_physics(0.3)
	_ok("走近自动拾取（金币 / 材料 / 装备至少 1 项入账）",
		_player.gold > 0 or _player.materials > 0 or _player.inventory.size() > 0)
	_info("      拾取后：金币 %d / 魔石 %d / 装备 %d 件"
			% [_player.gold, _player.materials, _player.inventory.size()])


# =============================================================================
# G. 收编回归
# =============================================================================

func _test_mitigation_regression() -> void:
	print("--- G. 收编回归 ---")
	var e := _spawn_enemy("spider_cave", Vector2(0, 200))
	await get_tree().physics_frame
	var hp0 := e.current_hp
	_ok("敌人满血 = 怪物表 HP（L1 蜘蛛 = 100.7 × 1.284^0）",
		absf(hp0 - GameConstants.MONSTER_HP_AT_L1) < 0.1)
	e.take_damage(10.0, _player)
	_ok("敌人受击转发生命组件：HP 减 10（无双重减伤）",
		absf(e.current_hp - (hp0 - 10.0)) < 0.01)
	e.queue_free()


# =============================================================================
# H. 符文掉落桶（工单 2-L12 · 校验 2-V12）
# =============================================================================

## 造一只只有 tier 有意义的怪物（`roll_rune_drop` 只读 `tier` 找表）。
func _make_tier_monster(tier: int) -> MonsterData:
	var m := MonsterData.new()
	m.id = "sim_tier_%d" % tier
	m.tier = tier
	m.level_min = 1
	m.level_max = GameConstants.LEVEL_MAX
	return m


func _test_rune_drop() -> void:
	print("--- H. 符文掉落桶（2-L12 / 2-V12） ---")
	# 0) 表接线：JSON 的 rune_drop_chance 必须真的进到运行时 Resource
	#    （ConfigLoader 是逐字段手写映射，漏读 = 数据侧有、运行时不生效）。
	var t_normal: LootTable = ConfigLoader.loot_tables["monster_normal"]
	var t_elite: LootTable = ConfigLoader.loot_tables["monster_elite"]
	var t_boss: LootTable = ConfigLoader.loot_tables["monster_boss"]
	_ok("三表 rune_drop_chance 读表生效（0.02 / 0.08 / 0.25）",
		absf(t_normal.rune_drop_chance - 0.02) < 1e-6
		and absf(t_elite.rune_drop_chance - 0.08) < 1e-6
		and absf(t_boss.rune_drop_chance - 0.25) < 1e-6)
	_ok("符文池 = 24 条（数据驱动遍历 ConfigLoader.runes）",
		LootRoller.all_rune_ids().size() == 24)
	# 1) 三档概率抽样（4000 次/档），并断言只产出合法 rune id
	var ids := LootRoller.all_rune_ids()
	var monsters := [
		_make_tier_monster(MonsterData.Tier.NORMAL),
		_make_tier_monster(MonsterData.Tier.ELITE),
		_make_tier_monster(MonsterData.Tier.BOSS),
	]
	var expect := [0.02, 0.08, 0.25]
	var bounds := [[0.005, 0.040], [0.050, 0.120], [0.200, 0.300]]
	var samples := 4000
	seed(20260930)
	var hits := [0, 0, 0]
	var bad_type := 0
	var bad_id := 0
	var bad_ilvl := 0
	for i in samples:
		for k in 3:
			var e := LootRoller.roll_rune_drop(monsters[k], 7)
			if e.is_empty():
				continue
			hits[k] += 1
			if str(e.get("type", "")) != "rune":
				bad_type += 1
			if not ids.has(str(e.get("item_id", ""))):
				bad_id += 1
			if int(e.get("item_level", -1)) != 7:
				bad_ilvl += 1
	_ok("符文条目字段合法（type=rune / item_id ∈ 符文池 / item_level = 怪物等级）",
		bad_type == 0 and bad_id == 0 and bad_ilvl == 0)
	var rates: Array[float] = []
	for k in 3:
		rates.append(float(hits[k]) / float(samples))
	_info("      命中率：普通 %.3f / 精英 %.3f / BOSS %.3f（期望 %.2f / %.2f / %.2f，%d 次抽样）"
		% [rates[0], rates[1], rates[2], expect[0], expect[1], expect[2], samples])
	var rate_ok := true
	for k in 3:
		if rates[k] < bounds[k][0] or rates[k] > bounds[k][1]:
			rate_ok = false
	_ok("三档命中率均落在期望区间（普通 0.5–4% / 精英 5–12% / BOSS 20–30%）", rate_ok)
	_ok("概率随档位单调递增（普通 < 精英 < BOSS）",
		rates[0] < rates[1] and rates[1] < rates[2])
	# 2) 与主掉落独立：同一只怪「符文命中」不影响「主掉落是否触发」
	#    （普通怪 drop_chance 8% + 符文 2% 是两次独立 randf；此处只验两者都能单独出现）
	seed(20260931)
	var rune_only := 0
	var loot_only := 0
	var both := 0
	var neither := 0
	for i in 2000:
		var r := not LootRoller.roll_rune_drop(monsters[1], 7).is_empty()
		var l := not LootRoller.roll_loot(monsters[1], 7, GameConstants.DifficultyTier.NM1, 7).is_empty()
		if r and l:
			both += 1
		elif r:
			rune_only += 1
		elif l:
			loot_only += 1
		else:
			neither += 1
	_info("      2000 次：符文only %d / 主掉落only %d / 双响 %d / 皆无 %d"
		% [rune_only, loot_only, both, neither])
	# 独立 ⇒ 四象限都非空（精英：符文 8% × 掉落 60% ⇒ 双响 ≈ 4.8% ⇒ 期望 ~96 次）
	_ok("符文与主掉落相互独立（四象限均出现，双响 ≈ 8% × 60%）",
		rune_only > 0 and loot_only > 0 and both > 0 and neither > 0)
	# 3) 重复符文转魔石量：与 `_roll_material()` 同口径（1 + (L-1)/5，至少 1）
	var mat_ok := true
	for lv in [1, 5, 6, 11, 20]:
		var expect_mat := maxi(1, 1 + int(float(lv - 1) / GameConstants.MATERIAL_LEVEL_STEP))
		if LootRoller.rune_duplicate_material_amount(lv) != expect_mat:
			mat_ok = false
			_info("      L%d：期望 %d 实际 %d"
				% [lv, expect_mat, LootRoller.rune_duplicate_material_amount(lv)])
	_ok("重复符文转魔石量与材料掉落同口径（L1/L5/L6/L11/L20）", mat_ok)
	_ok("转化量下限保护（L1 → ≥1）", LootRoller.rune_duplicate_material_amount(1) >= 1)


# =============================================================================
# I. 符文拾取（首获解锁 / 重复转魔石）
# =============================================================================

func _test_rune_pickup() -> void:
	print("--- I. 符文拾取：首获解锁 / 重复转魔石 ---")
	var data := SaveManager.current_data
	_ok("存档对象就绪", data != null)
	if data == null:
		return
	data.unlocked_runes.clear()
	_player.materials = 0
	var rid := "rune_projectile"
	# 首获 → 永久解锁，不产魔石
	_player.pickup_loot({"type": "rune", "amount": 1, "item_id": rid, "rarity": -1, "item_level": 7})
	_ok("首获符文写入 unlocked_runes（1 枚）",
		data.unlocked_runes.size() == 1 and data.unlocked_runes.has(rid))
	_ok("首获符文不产魔石（materials == 0）", _player.materials == 0)
	# 重复 → 不重复写入 + 转魔石
	var expect_mat := LootRoller.rune_duplicate_material_amount(7)
	_player.pickup_loot({"type": "rune", "amount": 1, "item_id": rid, "rarity": -1, "item_level": 7})
	_ok("重复符文不重复写入（unlocked_runes 仍 1 枚）", data.unlocked_runes.size() == 1)
	_ok("重复符文转魔石 +%d（与材料同口径）" % expect_mat, _player.materials == expect_mat)
	# 结果写回载荷（PickupToastHUD 文案依赖；契约见 `PlayerController._pickup_rune`）
	var e := {"type": "rune", "amount": 1, "item_id": "rune_chain", "rarity": -1, "item_level": 7}
	_player.pickup_loot(e)
	_ok("首获写回载荷：rune_new=true / material_amount=0",
		bool(e.get("rune_new", false)) and int(e.get("material_amount", -1)) == 0)
	_player.pickup_loot(e)
	_ok("重复写回载荷：rune_new=false / material_amount>0",
		not bool(e.get("rune_new", true)) and int(e.get("material_amount", 0)) > 0)
	_ok("两枚不同符文均入集合（2 枚）", data.unlocked_runes.size() == 2)
	# 拾取提示条：符文分支不静默丢弃（旧实现 `_: return` ⇒ 符文拾取毫无反馈）
	var hud := PickupToastHUD.new()
	add_child(hud)
	hud.spawn({"type": "rune", "amount": 1, "item_id": "rune_chain", "rarity": -1, "item_level": 7,
		"rune_new": true})
	_ok("拾取提示条消费 rune（生成 1 条提示）", hud.get_child_count() == 1)
	hud.queue_free()


# =============================================================================
# J. 拾取反馈强化（2026-10-14 · Playground「拾取反馈」）
# =============================================================================

func _test_pickup_feedback() -> void:
	print("--- J. 拾取反馈强化（光晕染色 / 稀有度整数放大）---")
	# ① 染色与缩放口径：直接构造 LootDrop 读 helper（不 spawn 敌人，聚焦口径本身）。
	#    ⚠️ 不调 `setup()`（它会 `queue_redraw()`，节点未入树时无意义）—— 只填 helper 真正读的字段。
	var cases: Array = [
		["gold", -1, false, LootDrop.GOLD_COLOR, 1],
		["material", -1, false, LootDrop.MATERIAL_COLOR, 1],
		["rune", -1, false, LootDrop.RUNE_COLOR, 1],
		["equipment", GameConstants.Rarity.RARE, false,
			GameConstants.rarity_color(GameConstants.Rarity.RARE), 1],
		["equipment", GameConstants.Rarity.EPIC, false,
			GameConstants.rarity_color(GameConstants.Rarity.EPIC), 2],
		["equipment", GameConstants.Rarity.MYTHIC, false,
			GameConstants.rarity_color(GameConstants.Rarity.MYTHIC), 2],
	]
	var ok_color := true
	var ok_scale := true
	for c in cases:
		var d := LootDrop.new()
		d.drop_type = str(c[0])
		d.rarity = int(c[1])
		d.is_collectible = bool(c[2])
		if d._pickup_glow_color() != c[3]:
			ok_color = false
			_info("      染色不符：%s / rarity=%d ⇒ %s（期望 %s）"
				% [c[0], c[1], d._pickup_glow_color(), c[3]])
		if d._pickup_glow_scale() != int(c[4]):
			ok_scale = false
		d.free()
	_ok("拾取光晕按类型/稀有度染色（金/材料/符文/装备）", ok_color)
	_ok("拾取光晕整数放大：装备史诗起 2×、其余 1×（像素铁律）", ok_scale)

	# ② 端到端：真拾取一件史诗 ⇒ 生成**史诗色**的 pickup_glow（防「改了 helper 却没接线」）。
	_player.global_position = Vector2.ZERO
	var drop := LootDrop.new()
	drop.setup({"type": "equipment", "item_id": "sword_flame",
		"rarity": GameConstants.Rarity.EPIC, "item_level": 10})
	add_child(drop)
	drop.global_position = Vector2.ZERO
	await _step_physics(GameConstants.LOOT_POP_DELAY + 0.25)
	var tinted := false
	for n in get_tree().get_nodes_in_group(&"fx_sprites"):
		if n is FxSprite \
				and (n as FxSprite).modulate == GameConstants.rarity_color(GameConstants.Rarity.EPIC):
			tinted = true
	_ok("端到端：装备拾取生成**史诗色**拾取光晕", tinted)
	# 收尾：等光晕自然播完（`pickup_glow` 非 loop ⇒ 6 帧 @12fps ≈ 0.5s），
	# 否则 `quit()` 时仍存活会被计为「ObjectDB instances were leaked」。
	await _step_physics(0.7)


# =============================================================================
# K. 掉落物弹出动画（2026-10-14 · Playground「掉落物 pop 出來帶星光」）
# =============================================================================

func _test_drop_pop() -> void:
	print("--- K. 掉落物弹出动画 ---")
	# ① 常量合法
	_ok("弹出动画常量合法（时长 / 抬升 > 0）",
		LootDrop.POP_TIME > 0.0 and LootDrop.POP_BOUNCE_TIME > 0.0
		and LootDrop.POP_ARC_LIFT > 0.0 and LootDrop.POP_BOUNCE_LIFT > 0.0
		and LootDrop.POP_SPARKLE_COUNT >= 2)

	# ② 未设 pop_from ⇒ 不弹（关卡摆放的收集物 / 旧调用方行为逐位不变）
	var still := LootDrop.new()
	still.global_position = Vector2(400, 400)
	add_child(still)
	await get_tree().process_frame
	_ok("未设 pop_from ⇒ 不弹（_pop_elapsed 保持 < 0）", still._pop_elapsed < 0.0)
	_ok("未设 pop_from ⇒ 位置原地不动", still.global_position == Vector2(400, 400))
	still.free()

	# ③ 设 pop_from ⇒ `_ready` 里立刻挪到起点并开播（首帧不闪落点）
	#    ⚠️ 落点必须在 `add_child` **之前**设（生产代码就是这个顺序，见 `_spawn_loot_drop`）。
	var from := Vector2(0, 0)
	var to := Vector2(60, 0)
	var d := LootDrop.new()
	d.pop_from = from
	d.global_position = to
	add_child(d)
	_ok("设 pop_from ⇒ 起手即挪到起点且已开播（首帧不闪落点）",
		d._pop_elapsed >= 0.0 and d.global_position == from)

	# ④ 中途：高于「起点→落点」连线（抛物线抬升）
	await _step_physics(LootDrop.POP_TIME * 0.5)
	var mid := d.global_position
	_ok("中途高于起点-落点连线（抛物线抬升）", mid.y < -1.0)

	# ⑤ 像素铁律：弹出全程只改位移、**不改 scale**
	_ok("弹出全程 scale 恒为 1（位移不涉缩放）", d.scale == Vector2.ONE)

	# ⑥ 走完 ⇒ 精确落在落点且状态复位
	await _step_physics(LootDrop.POP_TIME + LootDrop.POP_BOUNCE_TIME + 0.15)
	_ok("动画结束 ⇒ 精确落在落点且状态复位",
		d._pop_elapsed < 0.0 and d.global_position.is_equal_approx(to))
	d.free()

	# ⑦ 磁吸接管 ⇒ 立刻结束弹出动画（防两者同帧抢写 `global_position` 而抽搐）
	#    落点距玩家 40px：> PICKUP_RADIUS(24) 且 ≤ LOOT_MAGNET_RADIUS(56) ⇒ 只会进磁吸，不会立即拾取。
	_player.global_position = Vector2(0, 0)
	var m := LootDrop.new()
	m.pop_from = Vector2(0, 0)
	m.global_position = Vector2(40, 0)
	add_child(m)
	# ⚠️ 只等到刚过 `LOOT_POP_DELAY`（0.25s）—— 此时弹出（0.34s）**仍在跑**，
	#    断言才能区分「磁吸主动叫停」与「动画自己跑完」。
	await _step_physics(GameConstants.LOOT_POP_DELAY + 0.02)
	_ok("被磁吸接管 ⇒ 弹出动画立刻结束（不抢写位置）",
		not is_instance_valid(m) or m._pop_elapsed < 0.0)
	if is_instance_valid(m):
		m.free()

	# ⑧ 外部改写让位：弹出动画每帧都写 `global_position`，若**别人**动过位置必须立刻交出控制权。
	#    回归背景：`verify_e2e` 段⑦ 会把掉落物瞬移到玩家脚下，此前会被弹回抛物线 ⇒ 永远捡不到。
	var e2 := LootDrop.new()
	e2.pop_from = Vector2(0, 0)
	e2.global_position = Vector2(60, 0)
	add_child(e2)
	await _step_physics(0.05)  # 先让动画真的跑起来（此刻 pop 仍在播）
	var external := Vector2(200, 200)
	e2.global_position = external  # 模拟「外部插手」
	await get_tree().process_frame
	# ⚠️ 必须等**两帧**：`SceneTree.process_frame` 在节点 `_process` **之前**发出 ⇒
	#    只等一帧读到的是「外部刚写完、掉落物还没跑 `_process`」的中间态（实测踩过）。
	await get_tree().process_frame
	_ok("外部改写位置 ⇒ 弹出动画立刻让位（不再覆盖）",
		e2._pop_elapsed < 0.0 and e2.global_position.is_equal_approx(external))
	e2.free()

	# ⑨ 端到端：敌人死亡掉落都带弹出起点（`EnemyBase._spawn_loot_drop` 已接线）
	_player.global_position = Vector2(600, 600)  # 远离掉落点，避免被磁吸/拾取
	var boss := _spawn_enemy("boss_ember_lord", Vector2(0, 200))
	await get_tree().physics_frame
	boss.take_damage(999999.0, _player)
	await _step_physics(0.5)
	var drops := get_tree().get_nodes_in_group(&"loot_drops")
	var all_pop := not drops.is_empty()
	for g in drops:
		if not (g as LootDrop).pop_from.is_finite():
			all_pop = false
	_ok("端到端：敌人死亡掉落 %d 件，全部带弹出起点" % drops.size(), all_pop)
	for g in drops:
		g.queue_free()
	await _step_physics(0.3)


func _finish() -> void:
	print("")
	SaveManager.current_data = _prev_save
	# 退出前停掉未播完的一次性 SFX（段 F/I/J/K 都播过音效：`pickup_gold` / `boss_phase`）。
	# headless 下 Dummy 音频驱动不推进播放头 ⇒ `finished → queue_free` 永不触发 ⇒
	# 不清理就会在退出时报 `AudioStreamPlaybackWAV` / `AudioStreamWAV` leaked。
	# 详见 `VerifyWatchdog.stop_sfx`（内含「为何还要 await 两帧」）。
	await VerifyWatchdog.stop_sfx(get_tree())
	if _fail == 0:
		print("===== 结果：0 项失败 =====")
	else:
		print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
