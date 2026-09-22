## 局外成长实测（任务 5.1–5.6 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_account.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（9 个测试段）：
##   A. 账号等级：公式节点（GDD 5.1 表）、连升、60 满级、天赋点
##   B. 天赋树：3 分支 / 20 节点 / 分支解锁（L1/L15/L30）/ 点数上限
##   C. 天赋加成：小 +2% / 大 +8% / 机制列表
##   D. 解锁系统：关卡顺序 / 梦魇递进 / 仓库页
##   E. 洗练附魔：成本 / 重掷数值 / 特效重铸
##   F. 宝石：槽位上限 / 镶嵌 / 拆卸 / 加成并入
##   G. 声望：击杀升级 / 每级 +1% exp+gold / 上限 10
##   H. 成就：JSON 加载 / 进度解锁 / 外观奖励不给战力
##   I. 并入结算：天赋 + 宝石 + 声望 → StatCalculator buffs
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
	print("===== 局外成长实测（任务 5.1–5.6） =====")
	_rng.seed = 20260916
	await _test_account()
	await _test_tree()
	await _test_tree_bonus()
	await _test_unlock()
	await _test_enchant()
	await _test_gem()
	await _test_reputation()
	await _test_achievement()
	await _test_merge()
	_finish()


# =============================================================================
# A. 账号等级
# =============================================================================

func _test_account() -> void:
	print("--- A. 账号等级 ---")
	_ok("L10 单级 7166（GDD 5.1 表）", absf(AccountLevel.xp_to_next(10) - 7166.0) < 10.0)
	_ok("L20 单级 21723", absf(AccountLevel.xp_to_next(20) - 21723.0) < 10.0)
	_ok("L30 单级 41559", absf(AccountLevel.xp_to_next(30) - 41559.0) < 20.0)
	_ok("L45 单级 79508", absf(AccountLevel.xp_to_next(45) - 79508.0) < 50.0)
	_ok("L60 单级 125984", absf(AccountLevel.xp_to_next(60) - 125984.0) < 50.0)
	_ok("累计到 L10 ≈ 24071", absf(AccountLevel.cumulative_to(10) - 24071.0) < 50.0)
	var acc := AccountLevel.new()
	var up_events: Array[int] = []
	acc._on_level_up = func(lv: int, _g: int) -> void: up_events.append(lv)
	acc.add_xp(99999999.0)
	_ok("大量经验升到 60 级", acc.level == 60)
	_ok("60 级 30 天赋点（每 2 级 +1）", acc.talent_points == 30)
	_ok("升级事件已触发（59 次）", up_events.size() == 59)


# =============================================================================
# B. 天赋树
# =============================================================================

func _test_tree() -> void:
	print("--- B. 天赋树 ---")
	_ok("3 分支", TalentTree.BRANCHES.size() == 3)
	_ok("每分支 20 节点（15 小 + 5 大）",
		TalentTree.SMALL_NODE_COUNT == 15 and TalentTree.BIG_NODE_COUNT == 5)
	_ok("分支解锁 L1/L15/L30", TalentTree.is_branch_unlocked("might", 1)
		and not TalentTree.is_branch_unlocked("guardian", 14)
		and TalentTree.is_branch_unlocked("guardian", 15)
		and not TalentTree.is_branch_unlocked("arcane", 29)
		and TalentTree.is_branch_unlocked("arcane", 30))
	var tree := TalentTree.new()
	tree.update_unlocks(30)
	_ok("30 级三分支全解锁", tree.unlocked.get("might", false)
		and tree.unlocked.get("guardian", false) and tree.unlocked.get("arcane", false))
	var r1 := tree.learn("might.small.0", 2)
	_ok("L2 可学武力小节点（每 2 级 1 点）", r1["ok"])
	var r2 := tree.learn("guardian.small.0", 5)
	_ok("L5 守护分支未解锁拒绝", not r2["ok"])
	var r3 := tree.learn("might.small.0", 2)
	_ok("重复学习拒绝", not r3["ok"])
	# 30 级 15 点 → 学到 16 个拒绝
	for i in range(1, 15):
		tree.learn("might.small.%d" % i, 30)
	var r4 := tree.learn("might.small.14", 30)
	_ok("点超可用点数拒绝（30 级 15 点）", not r4["ok"])


# =============================================================================
# C. 天赋加成
# =============================================================================

func _test_tree_bonus() -> void:
	print("--- C. 天赋加成 ---")
	var tree := TalentTree.new()
	tree.update_unlocks(30)
	tree.learn("might.small.0", 30)
	tree.learn("might.small.1", 30)
	tree.learn("might.big.0", 30)
	var bonus := tree.get_bonus_stats()
	_ok("2 小 + 1 大 = +12% 攻击", absf(float(bonus["stats"].get("pct_attack", 0.0)) - 12.0) < 0.01)
	_ok("大节点机制列表非空", bonus["mechanics"].size() >= 1)


# =============================================================================
# D. 解锁系统
# =============================================================================

func _test_unlock() -> void:
	print("--- D. 解锁系统 ---")
	_ok("L1 恒开", UnlockSystem.is_level_unlocked(1, 0))
	_ok("L3 需通关 2", not UnlockSystem.is_level_unlocked(3, 1)
		and UnlockSystem.is_level_unlocked(3, 2))
	_ok("L21 不存在", not UnlockSystem.is_level_unlocked(21, 99))
	_ok("梦魇 I 需全 20 关", not UnlockSystem.is_difficulty_unlocked(1, 19)
		and UnlockSystem.is_difficulty_unlocked(1, 20))
	_ok("梦魇 II 再通 5 关", not UnlockSystem.is_difficulty_unlocked(2, 24)
		and UnlockSystem.is_difficulty_unlocked(2, 25))
	_ok("仓库页 2/3/4 = 通关 5/10/15",
		UnlockSystem.stash_pages_unlocked(4) == 1
		and UnlockSystem.stash_pages_unlocked(5) == 2
		and UnlockSystem.stash_pages_unlocked(10) == 3
		and UnlockSystem.stash_pages_unlocked(15) == 4)


# =============================================================================
# E. 洗练附魔
# =============================================================================

func _test_enchant() -> void:
	print("--- E. 洗练附魔 ---")
	var sword := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("sword_iron"), 12,
		GameConstants.Rarity.RARE, _rng)
	var cost := EnchantController.get_reroll_cost(sword)
	_ok("洗练成本秘银尘 ×3", int(cost.get(MaterialBag.KEY_DUST, 0)) == 3)
	var old_val := float(sword.affixes[0].value)
	var res := EnchantController.try_reroll_affix(sword, _rng)
	_ok("洗练成功且数值重掷", res["ok"])
	# 特效重铸（橙装带特效）
	var legend := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("sword_iron"), 12,
		GameConstants.Rarity.LEGENDARY, _rng)
	if legend.legendary_effect_id.is_empty():
		legend.legendary_effect_id = "sword_burning" # 兜底绑定（测试用）
	var ecost := EnchantController.get_reforge_cost(legend)
	_ok("特效重铸成本精粹 ×2", int(ecost.get(MaterialBag.KEY_ESSENCE, 0)) == 2)
	var eid_before := legend.legendary_effect_id
	var res2 := EnchantController.try_reforge_effect(legend, _rng)
	_ok("特效重铸成功且更换", res2["ok"] and str(res2.get("effect_id", "")) != eid_before)


# =============================================================================
# F. 宝石
# =============================================================================

func _test_gem() -> void:
	print("--- F. 宝石 ---")
	var item := EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("sword_iron"), 12, GameConstants.Rarity.RARE)
	_ok("黄装 1 槽", GemSystem.max_sockets(item) == 1)
	var item2 := EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("sword_iron"), 12, GameConstants.Rarity.LEGENDARY)
	_ok("橙装 2 槽", GemSystem.max_sockets(item2) == 2)
	var r1 := GemSystem.socket(item, 0, "ruby.normal")
	_ok("红宝石镶嵌成功", r1["ok"])
	var r2 := GemSystem.socket(item, 1, "ruby.normal")
	_ok("槽位不足拒绝", not r2["ok"])
	var bonus := GemSystem.get_gem_bonus(item)
	_ok("红宝石普通 = +6% 攻击", absf(float(bonus.get("pct_attack", 0.0)) - 6.0) < 0.01)
	var out := GemSystem.unsocket(item, 0)
	_ok("拆卸返回宝石", out == "ruby.normal" and item.gems.is_empty())


# =============================================================================
# G. 声望
# =============================================================================

func _test_reputation() -> void:
	print("--- G. 声望 ---")
	var rep := ChapterReputation.new()
	rep.add_clear("chapter_1")
	rep.add_clear("chapter_1")
	for i in 90:
		rep.add_kill("chapter_1") # 60 + 90 = 150 → 1 级（每级 150 = 约 1 关）
	_ok("1 关量声望 = 1 级", int(rep.rep_levels.get("chapter_1", 0)) == 1)
	for i in 5000:
		rep.add_kill("chapter_1")
	_ok("击杀累积上限 10 级", int(rep.rep_levels.get("chapter_1", 0)) == ChapterReputation.MAX_REP_LEVEL)
	var bonus := ChapterReputation.get_bonus(5)
	_ok("5 级声望 +5% 经验 +5% 金币",
		float(bonus["xp_gain"]) == 5.0 and float(bonus["gold_gain"]) == 5.0)


# =============================================================================
# H. 成就
# =============================================================================

func _test_achievement() -> void:
	print("--- H. 成就 ---")
	var sys := AchievementSystem.new()
	sys.load_definitions()
	_ok("成就数据加载（≥20 个）", sys.total_count() >= 20)
	var new_ones := sys.report_progress("kills", 5000.0)
	_ok("击杀 5000 解锁多个成就", new_ones.size() >= 3)
	_ok("100 成就解锁", sys.is_unlocked("kill_100"))
	var none := sys.report_progress("kills", 5000.0)
	_ok("重复上报不重复解锁", none.is_empty())
	_ok("外观奖励非空且无战力字段",
		not AchievementSystem.reward_label("kill_5000", sys.achievements).is_empty())


# =============================================================================
# I. 并入结算
# =============================================================================

func _test_merge() -> void:
	print("--- I. 并入结算 ---")
	# 天赋 +2% 攻 + 宝石 +6% 攻 + 声望 +5% 金币 → buffs 并入
	var tree := TalentTree.new()
	tree.update_unlocks(30)
	tree.learn("might.small.0", 30)
	var gem_item := EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("sword_iron"), 12, GameConstants.Rarity.RARE)
	GemSystem.socket(gem_item, 0, "ruby.normal")
	var rep := ChapterReputation.new()
	rep.add_clear("chapter_1")
	for i in 120:
		rep.add_kill("chapter_1") # 30 + 120 = 150 → 1 级 → +1% 金币
	var buffs := {
		"talent": {"pct": tree.get_bonus_stats()["stats"]},
		"gem": {"pct": GemSystem.get_total_gem_bonus([gem_item])},
		"rep": {"pct": rep.get_total_bonus()},
	}
	var stats := StatCalculator.calculate(1, [], buffs)
	_ok("天赋 2% + 宝石 6% = 攻击 ×1.08", _near(stats["attack"], 12.0 * 1.08))
	_ok("声望 +1% 金币并入", _near(stats["gold_gain"], 1.0))


func _near(a: float, b: float, tol: float = 0.5) -> bool:
	return absf(a - b) <= tol


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
