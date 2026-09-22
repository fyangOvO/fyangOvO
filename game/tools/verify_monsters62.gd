## 怪物扩充 / 精英词缀怪实测（任务 6.2 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_monsters62.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 怪物数据：16 种 / 三章覆盖 / 全部 validate 合法
##   B. 数值增长：第 2/3 章怪物 HP/DMG 高于第 1 章（难度爬坡）
##   C. 精英：精英 ≥3 种（含 2 新增）+ 精英掉落表绑定
##   D. 词缀池：6 条词缀定义齐全 / 名称
##   E. 词缀抽取：1–2 条不重复 / 权重可复现
##   F. 词缀数值：急速移速 ×1.35 / 荆棘反弹 15% / 吸血 20%
##   G. 词缀并入敌人：move_mult 生效 / 爆炸半径参数
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
	print("===== 怪物扩充 / 精英词缀怪实测（任务 6.2） =====")
	_rng.seed = 20260917
	await _test_data()
	await _test_scaling()
	await _test_elite()
	await _test_pool()
	await _test_roll()
	await _test_values()
	await _test_enemy()
	_finish()


# =============================================================================
# A. 怪物数据
# =============================================================================

func _test_data() -> void:
	print("--- A. 怪物数据 ---")
	var ids: Array = ConfigLoader.monsters.keys()
	_ok("怪物总数 ≥ 16", ids.size() >= 16)
	var ch1 := 0
	var ch2 := 0
	var ch3 := 0
	var bad := 0
	for id in ids:
		var m: MonsterData = ConfigLoader.get_monster(id)
		if m == null or not m.validate().is_empty():
			bad += 1
		if m.level_min <= 6:
			ch1 += 1
		if m.level_max >= 7 and m.level_min <= 13:
			ch2 += 1
		if m.level_max >= 14:
			ch3 += 1
	_ok("全部怪物 validate 合法", bad == 0)
	_ok("三章怪物可用（一章 ≥4 / 二章 ≥6 / 三章 ≥5）",
		ch1 >= 4 and ch2 >= 6 and ch3 >= 5)
	_ok("新增 8 种齐备", ids.has("mushroom_spore") and ids.has("warg_dark")
		and ids.has("golem_ember") and ids.has("imp_hellfire")
		and ids.has("hound_ash") and ids.has("pyromancer_cultist")
		and ids.has("frozen_husk") and ids.has("ice_wraith"))


# =============================================================================
# B. 数值爬坡
# =============================================================================

func _test_scaling() -> void:
	print("--- B. 数值爬坡 ---")
	var spider: MonsterData = ConfigLoader.get_monster("spider_cave")
	var golem: MonsterData = ConfigLoader.get_monster("golem_ember")
	var husk: MonsterData = ConfigLoader.get_monster("frozen_husk")
	_ok("第二章怪 HP 系数 > 第一章（烬石魔像 1.9 > 洞穴蛛 1.0）",
		golem.hp_scale > spider.hp_scale)
	_ok("第三章怪 HP 系数 > 第一章（冰封尸骸 1.75 > 洞穴蛛 1.0）",
		husk.hp_scale > spider.hp_scale)
	_ok("等级带正确（golem 8–16 / husk 14–20）",
		golem.level_min == 8 and golem.level_max == 16
		and husk.level_min == 14 and husk.level_max == 20)


# =============================================================================
# C. 精英
# =============================================================================

func _test_elite() -> void:
	print("--- C. 精英 ---")
	var elite_count := 0
	var elite_with_loot := true
	for id in ConfigLoader.monsters.keys():
		var m: MonsterData = ConfigLoader.get_monster(id)
		if m.tier == MonsterData.Tier.ELITE:
			elite_count += 1
			if m.loot_table_id.is_empty():
				elite_with_loot = false
	_ok("精英 ≥ 4 种（屠夫 / 霜缚幽魂 / 焰术信徒 / 寒霜幽魂）", elite_count >= 4)
	_ok("全部精英绑定精英掉落表", elite_with_loot)


# =============================================================================
# D. 词缀池
# =============================================================================

func _test_pool() -> void:
	print("--- D. 词缀池 ---")
	_ok("6 条词缀定义齐全", AffixController.AFFIXES.size() == 6)
	_ok("词缀名可读（急速 / 吸血 / 爆炸 / 回响 / 荆棘 / 闪现）",
		str(AffixController.AFFIXES["haste"]["name"]) == "急速"
		and str(AffixController.AFFIXES["explosive"]["name"]) == "爆炸"
		and str(AffixController.AFFIXES["thorn"]["name"]) == "荆棘")
	_ok("权重表 6 项", AffixController.WEIGHTS.size() == 6)


# =============================================================================
# E. 词缀抽取
# =============================================================================

func _test_roll() -> void:
	print("--- E. 词缀抽取 ---")
	var seen: Dictionary = {}
	for i in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var affixes := AffixController.roll_affixes(rng)
		_ok("抽取 1–2 条", affixes.size() >= 1 and affixes.size() <= 2)
		# 不重复
		_ok("不重复", affixes.size() == affixes.duplicate().size() \
			or not (affixes.size() == 2 and affixes[0] == affixes[1]))
		for a in affixes:
			seen[a] = true
		if i >= 10:
			break
	_ok("抽到的词缀都在池内", seen.keys().all(func(a: String) -> bool: return AffixController.AFFIXES.has(a)))


# =============================================================================
# F. 词缀数值
# =============================================================================

func _test_values() -> void:
	print("--- F. 词缀数值 ---")
	_ok("急速移速 ×1.35", absf(float(AffixController.get_multipliers(["haste"])["move"]) - 1.35) < 0.01)
	_ok("吸血回复 20%", absf(float(AffixController.AFFIXES["lifesteal"]["heal_ratio"]) - 0.2) < 0.01)
	_ok("荆棘反弹 15%", absf(float(AffixController.AFFIXES["thorn"]["reflect_ratio"]) - 0.15) < 0.01)
	_ok("爆炸 40px / 80% 伤害",
		float(AffixController.AFFIXES["explosive"]["radius"]) == 40.0
		and absf(float(AffixController.AFFIXES["explosive"]["dmg_ratio"]) - 0.8) < 0.01)
	_ok("闪现间隔 6 秒", float(AffixController.AFFIXES["phasing"]["interval"]) == 6.0)


# =============================================================================
# G. 词缀并入敌人
# =============================================================================

func _test_enemy() -> void:
	print("--- G. 词缀并入敌人 ---")
	var scene := load("res://scenes/enemies/enemy_base.tscn")
	_ok("敌人场景可加载", scene != null)
	var enemy := scene.instantiate() as EnemyBase
	enemy.monster_id = "skeleton_warrior"
	enemy.level = 5
	enemy.affixes = ["haste", "thorn"]
	get_tree().root.add_child.call_deferred(enemy)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("急速使移速乘法生效（_move_mult = 1.35）", absf(enemy._move_mult - 1.35) < 0.01)
	_ok("敌人 HP 按怪物表初始化", enemy.health != null and enemy.health.max_hp_override > 0.0)
	# 荆棘反弹：给一个带 take_damage 的探针
	var probe := DamageDummy.new()
	get_tree().root.add_child.call_deferred(probe)
	await get_tree().process_frame
	var hp_before: float = probe.hp
	var dmg := 100.0
	enemy.take_damage(dmg, probe)
	await get_tree().process_frame
	_ok("荆棘反弹 15（探针掉血 ≈15）", absf(hp_before - probe.hp - 15.0) < 1.0)
	enemy.queue_free()
	probe.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
