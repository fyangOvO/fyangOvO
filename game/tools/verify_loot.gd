## 掉落与拾取系统实测（任务 2.7 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_loot.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（6 个测试段）：
##   A. 掉落表数据：3 张表 / 权重 8 档且和为 100 / drop_chance 与件数区间合法
##   B. roll 基础：BOSS 表（drop_chance 1.0）必掉 2–4 件
##   C. 稀有度分布：普通怪权重 20k 次抽样白 > 蓝 > 黄、橙极低
##   D. 难度修正：NM1 红装清零 / NM2+ 开放 / 越级惩罚紫橙 ×0.5
##   E. 底材过滤：iLvl 区间 / 套装稀有度只出 set_id 底材
##   F. 敌人死亡掉落 + 拾取：BOSS 秒杀掉 2–4 件 LootDrop，玩家走近自动入账
##   G. 收编回归：敌人受击转发生命组件（无双重减伤）
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null


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
	await _test_tables()
	await _test_roll_basic()
	await _test_rarity_distribution()
	await _test_difficulty_adjust()
	await _test_template_filter()
	await _test_enemy_drop_and_pickup()
	await _test_mitigation_regression()
	_finish()


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
	_ok("掉落表 3 张（普通 / 精英 / BOSS）", ConfigLoader.loot_tables.size() == 3)
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
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	for i in 20000:
		counts[LootRoller._roll_rarity(weights, GameConstants.DifficultyTier.NM1, 0, 1)] += 1
	_ok("普通怪稀有度：白 > 蓝 > 黄（20k 次抽样）",
		counts[GameConstants.Rarity.COMMON] > counts[GameConstants.Rarity.MAGIC]
		and counts[GameConstants.Rarity.MAGIC] > counts[GameConstants.Rarity.RARE])
	_ok("普通怪橙装极稀有（20k 次 ≈ 0.05% = 10 ± 12）",
		counts[GameConstants.Rarity.LEGENDARY] <= 22)
	_info("      分布：白 %d / 蓝 %d / 黄 %d / 紫 %d / 橙 %d / 红 %d / 绿 %d / 彩 %d"
			% [counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7]])


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
		var t: EquipmentData = ConfigLoader.equipment_templates.get(d["item_id"])
		if t == null or int(d["rarity"]) < t.rarity_min or int(d["rarity"]) > t.rarity_max \
				or 5 < t.item_level_min or 5 > t.item_level_max:
			bad += 1
	_ok("装备底材按稀有度区间 / 等级区间过滤（200 次 roll 无越界）",
		eq_count >= 60 and bad == 0)
	_info("      200 次中装备 %d 件（装备占比 55% ≈ %d）" % [eq_count, int(200 * 0.55)])
	# 套装稀有度只出 set_id 底材
	var t_set := LootRoller._pick_template(GameConstants.Rarity.SET, 5)
	_ok("套装稀有度只出带 set_id 的底材",
		t_set == null or not t_set.set_id.is_empty())


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
	var boss := _spawn_enemy("boss_ember_lord", Vector2(0, 120))
	await get_tree().physics_frame  # _refresh_player 拿到玩家引用
	boss.take_damage(999999.0, _player)  # 秒杀 → 组件死亡 → unit_died → 掉落 + 移除
	await _step_physics(0.35)  # 掉落弹出（pop delay 0.25）+ 移除完成
	_ok("BOSS 死亡后节点已移除", not is_instance_valid(boss))
	var drops := get_tree().get_nodes_in_group(&"loot_drops")
	_ok("BOSS 必掉 2–4 件地面掉落物", drops.size() >= 2 and drops.size() <= 4)
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


func _finish() -> void:
	print("")
	if _fail == 0:
		print("===== 结果：0 项失败 =====")
	else:
		print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
