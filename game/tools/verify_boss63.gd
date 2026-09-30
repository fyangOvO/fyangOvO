## BOSS 设计与机制实测（任务 6.3 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_boss63.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. BOSS 数据：2 个章末 BOSS 配置合法（thresholds / 4 段技能 / 召唤池 / 狂暴）
##   B. 阶段判定：HP 比例 → 阶段（100→1 / 80→1 / 70→2 / 40→3 / 10→4）
##   C. 技能集：逐阶段累积（阶段 2 ⊇ 阶段 1；阶段 2 含狂暴，共 4 招）
##   D. 召唤：数量随阶段递增 / 池内 id 全部存在（ConfigLoader 交叉校验）
##   E. 狂暴乘区：阶段 2 攻速 ×0.6 / 伤害 ×1.3 类生效（骸骨阶段 1 为 1）；
##      B5-5 后狂暴起始阶段统一 = 2
##   F. BOSS 掉落：monster_boss 100% 掉 2–4 件（GDD 6.1）
##   G. 集成：EnemyBase tier=BOSS 挂载阶段机制；HP 打至 50% 触发阶段 2 + 广播
extends Node

var _fail: int = 0

## 阶段广播断言用（lambda 捕获基本类型按值，改用成员）
var _phase_triggered := false
var _phase_seen := 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== BOSS 设计与机制实测（任务 6.3） =====")
	await _test_data()
	await _test_phase()
	await _test_skills()
	await _test_summon()
	await _test_enrage()
	await _test_loot()
	await _test_integration()
	_finish()


# =============================================================================
# A. BOSS 数据
# =============================================================================

func _test_data() -> void:
	print("--- A. BOSS 数据 ---")
	_ok("BOSS 配置 2 个（骸骨暴君 / 熔心之主）",
		ConfigLoader.bosses.size() == 2
		and ConfigLoader.bosses.has("boss_bone_tyrant")
		and ConfigLoader.bosses.has("boss_ember_lord"))
	var all_valid := true
	for id in ConfigLoader.bosses:
		if not BossPhaseController.validate(ConfigLoader.bosses[id]).is_empty():
			all_valid = false
	_ok("全部 BOSS 数据 validate 合法", all_valid)
	_ok("全部 BOSS 在怪物表（ConfigLoader 交叉校验无 load_errors）",
		ConfigLoader.load_errors.is_empty())


# =============================================================================
# B. 阶段判定
# =============================================================================

func _test_phase() -> void:
	print("--- B. 阶段判定（B5-5 · 2 阶段，阈值 60%） ---")
	_ok("100% HP → 阶段 1", BossPhaseController.current_phase(1.0) == 1)
	_ok("80% HP → 阶段 1", BossPhaseController.current_phase(0.8) == 1)
	_ok("61% HP → 阶段 1（仍在 60% 阈值上）", BossPhaseController.current_phase(0.61) == 1)
	_ok("60% HP → 阶段 2（60% 阈值）", BossPhaseController.current_phase(0.6) == 2)
	_ok("40% HP → 阶段 2", BossPhaseController.current_phase(0.4) == 2)
	_ok("0% HP → 阶段 2（不死锁）", BossPhaseController.current_phase(0.0) == 2)


# =============================================================================
# C. 技能集
# =============================================================================

func _test_skills() -> void:
	print("--- C. 技能集（B5-5 · 阶段1 2招 → 阶段2 4招） ---")
	var tyrant: Dictionary = ConfigLoader.bosses["boss_bone_tyrant"]
	_ok("骸骨暴君 阶段 1 = 2 招（重击+召唤）",
		BossPhaseController.phase_skills(tyrant, 1) == ["bone_slam", "summon_skeleton"])
	_ok("阶段 2 解锁践踏+狂暴（共 4 招）",
		BossPhaseController.phase_skills(tyrant, 2).size() == 4
		and BossPhaseController.phase_skills(tyrant, 2).has("shockwave")
		and BossPhaseController.phase_skills(tyrant, 2).has("enrage"))
	_ok("技能集逐阶段累积（阶段 2 ⊇ 阶段 1）",
		BossPhaseController.phase_skills(tyrant, 2).has("bone_slam")
		and BossPhaseController.phase_skills(tyrant, 2).has("summon_skeleton"))
	var ember: Dictionary = ConfigLoader.bosses["boss_ember_lord"]
	_ok("熔心之主 阶段 2 = 4 招（火球/召唤小鬼/熔岩喷发/狂暴）",
		BossPhaseController.phase_skills(ember, 2) == ["fireball", "summon_imp", "magma_eruption", "enrage"])


# =============================================================================
# D. 召唤
# =============================================================================

func _test_summon() -> void:
	print("--- D. 召唤 ---")
	var tyrant: Dictionary = ConfigLoader.bosses["boss_bone_tyrant"]
	var ember: Dictionary = ConfigLoader.bosses["boss_ember_lord"]
	# B5-5（2026-09-30）2 阶段：召唤数从 4 项压缩为 2 项。
	#   骸骨暴君 → 「召唤流」0/4；熔心之主 → 「法术流」0/2
	_ok("骸骨暴君召唤数量（阶段1=0 / 阶段2=4）",
		BossPhaseController.summon_count_for(tyrant, 1) == 0
		and BossPhaseController.summon_count_for(tyrant, 2) == 4)
	_ok("熔心之主召唤数量（阶段1=0 / 阶段2=2，法术流少召唤）",
		BossPhaseController.summon_count_for(ember, 1) == 0
		and BossPhaseController.summon_count_for(ember, 2) == 2)
	_ok("骸骨暴君召唤骷髅/猎犬（怪物表已含）",
		ConfigLoader.monsters.has("skeleton_warrior") and ConfigLoader.monsters.has("warg_dark"))
	_ok("熔心之主召唤小鬼/猎犬（怪物表已含）",
		ConfigLoader.monsters.has("imp_hellfire") and ConfigLoader.monsters.has("hound_ash"))


# =============================================================================
# E. 狂暴乘区
# =============================================================================

func _test_enrage() -> void:
	print("--- E. 狂暴乘区（B5-5 · 狂暴起始阶段 = 2） ---")
	var tyrant: Dictionary = ConfigLoader.bosses["boss_bone_tyrant"]
	var er2 := BossPhaseController.enrage_multipliers(tyrant, 2)
	var er1 := BossPhaseController.enrage_multipliers(tyrant, 1)
	_ok("阶段 2 狂暴：攻速 ×0.6", absf(float(er2["interval_mult"]) - 0.6) < 0.01)
	_ok("阶段 2 狂暴：伤害 ×1.3", absf(float(er2["damage_mult"]) - 1.3) < 0.01)
	_ok("阶段 1 无狂暴乘区（×1.0）",
		absf(float(er1["interval_mult"]) - 1.0) < 0.01
		and absf(float(er1["damage_mult"]) - 1.0) < 0.01)
	_ok("阶段伤害乘区 2 段（1.0 → 1.4）",
		BossPhaseController.phase_damage_mult(tyrant, 1) == 1.0
		and BossPhaseController.phase_damage_mult(tyrant, 2) == 1.4)
	# B5-5：狂暴起始阶段统一 = 2（二阶段即狂暴）
	var ember: Dictionary = ConfigLoader.bosses["boss_ember_lord"]
	_ok("骸骨暴君 enrage_phase = 2",
		BossPhaseController.enrage_phase(tyrant) == 2)
	_ok("熔心之主 enrage_phase = 2",
		BossPhaseController.enrage_phase(ember) == 2)
	var e2 := BossPhaseController.enrage_multipliers(ember, 2)
	var e1 := BossPhaseController.enrage_multipliers(ember, 1)
	_ok("熔心之主阶段 2 已吃狂暴乘区（攻速 ×0.55 / 伤害 ×1.35）",
		absf(float(e2["interval_mult"]) - 0.55) < 0.01
		and absf(float(e2["damage_mult"]) - 1.35) < 0.01)
	_ok("熔心之主阶段 1 无狂暴乘区（×1.0）",
		absf(float(e1["interval_mult"]) - 1.0) < 0.01
		and absf(float(e1["damage_mult"]) - 1.0) < 0.01)
	_ok("is_enraged：两 BOSS 阶段 2 真 / 阶段 1 假",
		BossPhaseController.is_enraged(ember, 2)
		and not BossPhaseController.is_enraged(ember, 1)
		and BossPhaseController.is_enraged(tyrant, 2)
		and not BossPhaseController.is_enraged(tyrant, 1))
	# B5-5（6-W6-09）：二阶段场地收缩配置合法
	_ok("两 BOSS 均配 arena_shrink（火环半径 0.45）",
		float(tyrant.get("arena_shrink", {}).get("fire_ring_radius", 0.0)) == 0.45
		and float(ember.get("arena_shrink", {}).get("fire_ring_radius", 0.0)) == 0.45)


# =============================================================================
# F. BOSS 掉落
# =============================================================================

func _test_loot() -> void:
	print("--- F. BOSS 掉落 ---")
	var table: LootTable = ConfigLoader.get_loot_table("monster_boss")
	_ok("monster_boss 掉落表存在", table != null)
	if table != null:
		_ok("BOSS 100% 掉落", is_equal_approx(table.drop_chance, 1.0))
		_ok("BOSS 掉 2–4 件（GDD 6.1）",
			table.drop_count_range == Vector2i(2, 4))


# =============================================================================
# G. 集成
# =============================================================================

func _test_integration() -> void:
	print("--- G. 集成 ---")
	var scene: PackedScene = load("res://scenes/enemies/enemy_base.tscn")
	_ok("敌人场景可加载", scene != null)
	var boss: EnemyBase = scene.instantiate()
	boss.monster_id = "boss_bone_tyrant"
	boss.level = 7
	boss.difficulty_tier = GameConstants.DifficultyTier.NM1
	get_tree().root.add_child.call_deferred(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("BOSS 挂载阶段配置", not boss.boss_config.is_empty())
	_ok("BOSS 初始阶段 1 / 技能 = 重击+召唤",
		boss._boss_phase == 1 and boss._boss_skills == ["bone_slam", "summon_skeleton"])
	# 模拟受击：把 HP 打到 60% 以下（B5-5 阈值 0.6）
	var max_hp := boss.health.max_hp_override
	_phase_triggered = false
	_phase_seen = 0
	EventBus.boss_phase_changed.connect(func(_e: Node, p: int, _s: Array) -> void:
		_phase_triggered = true
		_phase_seen = p)
	boss.take_damage(max_hp * 0.45, null)
	await get_tree().process_frame
	_ok("HP 降至 55% 触发阶段 2 广播", _phase_triggered and _phase_seen == 2)
	_ok("阶段 2 解锁践踏", boss._boss_skills.has("shockwave"))
	_ok("阶段 2 狂暴乘区生效（攻速 ×0.6）",
		boss._boss_phase == 2 and absf(boss._boss_interval_mult - 0.6) < 0.01)
	boss.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
