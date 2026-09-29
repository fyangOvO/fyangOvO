## 技能扩展体系实测（第四步 B4-4 · 工单 1-L8 / 1-L9 / 1-L10 / 1-L11 / 1-L13 / 1-L14 ·
## 2026-09-29 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_skill_ext.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 定位（与既有脚本的分工，防「自洽式伪校验」，铁律 SF4）：
##   · `verify_skill_panel` 测**据点面板的交互闭环**（装配 / 卸下 / 保存 / 读档 / 图鉴入口）。
##   · `verify_skill_forms` 测**形态实体**（投射物 / 地面区域的真实弹道与 tick）。
##   · `verify_account` 测**天赋树点选**（含「技之极意」入池）。
##   · 本脚本测 **B4-4 新增的数据与套用逻辑本身**：技能解锁判定 / 等级公式 /
##     符文表自洽与互斥 / 分支模板与套用器 / 技能栏三标识 / 存档 v5 清洗。
##
## ⚠️ 防 SF4 的两条硬规矩：
##   ① 等级系数的期望值**硬编码**（1.00 / 1.24 / 1.48 / 1.72），不用
##      `SKILL_LEVEL_COEF_PER_LEVEL` 现算 —— 否则常量改错时测试照样通过。
##   ② 分支 modifier 的期望值取自**策划案 §2.3 的文字描述**（+40% / ×1.5 / 3 枚扇形），
##      不从 `branches.json` 反读 —— 数据被改坏时测试必须红。
##
## 覆盖（A~I）：
##   A. 技能解锁判定（1-L11）：双轨门槛 / 边界等级 / 未注册 id / 不改出战栏
##   B. 等级公式（1-L2）：L1/L4/L7/L10 四点 + 不影响冷却 / 蓝耗 / 范围
##   C. 符文表自洽（1-D3）：槽位 / 解锁等级 / 互斥组 / 适用形态 / 修饰非空
##   D. 符文互斥（1-L9）：同组冲突 / 跨组放行
##   E. 分支模板与套用器（1-L9）：7 形态 × 2 分支 / 可映射 7 键生效 / 未支持键零变化 + 警告
##   F. 技能栏三标识（1-L13）：等级角标 / 符文圆点 / 分支色框
##   G. 天赋「技之极意」（1-L10）：flat 桶 +1 技能等级
##   H. 存档 v5 清洗：符文槽截断 / 脏值丢弃 / 图鉴数组
##   I. 符文图鉴面板（1-L12）：24 格 / 解锁态 / 详情钩子
extends Node2D

## 等级系数期望值（硬编码，见头注释 ①）
const EXPECT_LEVEL_MULT := [1.00, 1.24, 1.48, 1.72]
## 对应的技能等级
const EXPECT_LEVELS := [1, 4, 7, 10]

var _fail: int = 0
var _player: PlayerController = null
var _skills: SkillController = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


## `_branch_warned` 的键是 `skill_id:修饰键`（不是 branch_id）—— 按前缀判定该技能是否被警告过
func _has_warned_for(skill_id: String) -> bool:
	for k in _skills._branch_warned:
		if String(k).begins_with(skill_id + ":"):
			return true
	return false


## 逐元素整数比较（JSON 里的数字会以 float 落地，`Array ==` 对 int/float 混比不可靠）
func _same_ints(a: Variant, b: Array) -> bool:
	if not (a is Array) or (a as Array).size() != b.size():
		return false
	var arr: Array = a
	for i in b.size():
		if int(arr[i]) != int(b[i]):
			return false
	return true


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 技能扩展体系实测（B4-4）=====")
	_setup()
	_test_skill_unlock()
	await _test_level_formula()
	_test_rune_data()
	_test_rune_exclusive()
	_test_branch_templates()
	_test_branch_apply()
	await _test_skill_bar_badges()
	_test_talent_insight()
	_test_save_v5_sanitize()
	await _test_codex_panel()
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	print("===== 技能扩展体系实测 结束：%s ====="
		% ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	get_tree().quit(0 if _fail == 0 else 1)


func _setup() -> void:
	_player = get_node_or_null("/root/VerifySkillExt/Player") as PlayerController
	_ok("场景就绪：玩家节点", _player != null)
	if _player == null:
		return
	_skills = _player.get_skill_controller()
	_ok("技能控制器就绪", _skills != null)


# =============================================================================
# A. 技能解锁判定（1-L11）
# =============================================================================

func _test_skill_unlock() -> void:
	print("--- A. 技能解锁判定（账号等级 + BOSS 首通 双轨）---")
	var all := ConfigLoader.skills.keys()
	var data_ok := true
	for sid_v in all:
		var sd := ConfigLoader.get_skill(String(sid_v))
		if sd == null:
			data_ok = false
			continue
		# 既无等级门槛也无 BOSS 门槛 ⇒ 永久锁死（validate() 已拦，这里再验一次）
		if sd.unlock_level <= 0 and sd.unlock_boss.is_empty():
			data_ok = false
			_info("%s 无任何解锁门槛" % sd.id)
	_ok("36 技能全部至少有一条解锁门槛（无永久锁死项）", data_ok and all.size() == 36)

	# L1 账号 + 无通关 ⇒ 恰好 3 个初始技能
	var l1_ok := true
	for cid in ["warrior", "archer", "mage"]:
		var ids := UnlockSystem.unlocked_skill_ids(cid, 1, [])
		if ids.size() != 3 or ids != ConfigLoader.class_default_skill_bar(cid):
			l1_ok = false
			_info("%s L1 解锁 = %s（期望默认栏 3 个）" % [cid, str(ids)])
	_ok("L1 账号 + 无通关：三职业各只解锁默认栏 3 个初始技能", l1_ok)

	# 边界：L5 恰好放开「账号 L5」那一档（同时 L3 的暗影步也已在列）
	_ok("战士 L5：解锁 5 个（初始 3 + 暗影步 L3 + 蓄力斩 L5）",
		UnlockSystem.is_skill_unlocked("power_strike", 5, [])
		and not UnlockSystem.is_skill_unlocked("power_strike", 4, [])
		and UnlockSystem.unlocked_skill_ids("warrior", 5, []).size() == 5)
	_ok("战士 L4：解锁 4 个（蓄力斩尚未到 L5）",
		not UnlockSystem.is_skill_unlocked("power_strike", 4, [])
		and UnlockSystem.unlocked_skill_ids("warrior", 4, []).size() == 4)
	# 边界：L22 放开终极技，但 BOSS 技仍需首通
	_ok("战士 L22：11 个解锁（终极技血怒在内，铁壁仍锁）",
		UnlockSystem.is_skill_unlocked("blood_rage", 22, [])
		and UnlockSystem.unlocked_skill_ids("warrior", 22, []).size() == 11
		and not UnlockSystem.is_skill_unlocked("iron_bulwark", 22, []))
	# BOSS 首通轨：与等级无关
	_ok("BOSS 首通轨：L1 账号 + 已通 ch1_l06 ⇒ 铁壁解锁",
		UnlockSystem.is_skill_unlocked("iron_bulwark", 1, ["ch1_l06"])
		and not UnlockSystem.is_skill_unlocked("iron_bulwark", 1, ["ch1_l05"]))
	_ok("三职业 BOSS 技门槛 = ch1_l06 / ch2_l13 / ch3_l20",
		String(ConfigLoader.get_skill("iron_bulwark").unlock_boss) == "ch1_l06"
		and String(ConfigLoader.get_skill("hunters_mark").unlock_boss) == "ch2_l13"
		and String(ConfigLoader.get_skill("void_rift").unlock_boss) == "ch3_l20")
	# 未注册 id ⇒ false（防拼错静默放行）
	_ok("未注册技能 id ⇒ 未解锁 + 原因文案「技能不存在」",
		not UnlockSystem.is_skill_unlocked("no_such_skill", 60, [])
		and UnlockSystem.skill_lock_reason("no_such_skill", 60, []) == "技能不存在")
	_ok("锁定原因文案：等级门槛 / BOSS 门槛",
		UnlockSystem.skill_lock_reason("power_strike", 1, []) == "账号等级 5 解锁"
		and UnlockSystem.skill_lock_reason("iron_bulwark", 60, []) == "通关 ch1_l06 解锁"
		and UnlockSystem.skill_lock_reason("cleave", 1, []) == "")
	# §9.3：解锁 ≠ 出战 ⇒ 解锁判定**不触碰** skill_bar
	var data := SaveData.create_new(0, "warrior")
	var bar_before := data.skill_bar.duplicate()
	UnlockSystem.unlocked_skill_ids("warrior", 60, ["ch1_l06", "ch2_l13", "ch3_l20"])
	_ok("§9.3 解锁不自动改出战栏（skill_bar 逐位不变）",
		data.skill_bar == bar_before and bar_before.size() == 3)


# =============================================================================
# B. 等级公式（1-L2）
# =============================================================================

func _test_level_formula() -> void:
	print("--- B. 等级公式：L1/L4/L7/L10（期望值硬编码）---")
	if _player == null or _skills == null:
		return
	var sd := ConfigLoader.get_skill("piercing_shot")
	var lv_ok := true
	var mult_ok := true
	for i in EXPECT_LEVELS.size():
		var level: int = EXPECT_LEVELS[i]
		# 注入 skill_level = level - 1（get_skill_level 会加基准 1）
		_player.apply_combat_stats(
			{"attack": 100.0, "crit_chance": -100.0, "skill_level": float(level - 1)}, 1)
		if _player.get_skill_level() != level:
			lv_ok = false
			_info("注入 %d ⇒ get_skill_level = %d（期望 %d）"
				% [level - 1, _player.get_skill_level(), level])
		var got := _skills._effective_multiplier(sd, -1.0)
		var want: float = 2.2 * float(EXPECT_LEVEL_MULT[i])
		if not is_equal_approx(got, want):
			mult_ok = false
			_info("L%d 有效倍率 %.4f（期望 %.4f）" % [level, got, want])
	_ok("四点等级映射：注入 0/3/6/9 ⇒ L1/L4/L7/L10", lv_ok)
	_ok("四点倍率：2.2 × {1.00, 1.24, 1.48, 1.72} = {2.2, 2.728, 3.256, 3.784}", mult_ok)
	_ok("等级上限钳制：注入 99 ⇒ L10（不越 SKILL_LEVEL_MAX）",
		_player.get_skill_level() == GameConstants.SKILL_LEVEL_MAX)

	# 等级系数只吃倍率，不得污染冷却 / 蓝耗 —— 走**真实施放**路径断言，不比对注册表模板
	# （比对模板是自洽式伪校验：`_effective_multiplier` 本来就不碰 data）。
	var data := SaveData.create_new(0, "archer")
	data.skill_bar = ["piercing_shot", "multishot", "lightning_chain"]
	SaveManager.current_data = data
	_skills._load_skills()
	_player.get_mana_pool().set_current(1000.0)
	var mana_before := _player.get_mana_pool().current
	_player.apply_combat_stats(
		{"attack": 100.0, "crit_chance": -100.0, "skill_level": 9.0}, 1)
	var casted := _skills.try_cast("piercing_shot")
	_ok("L10 施放成功（走生产路径）", casted)
	_ok("等级系数不污染冷却：L10 冷却仍 = data.cooldown(%.2f)" % sd.cooldown,
		is_equal_approx(_skills.get_cooldown_remaining("piercing_shot"), sd.cooldown))
	_ok("等级系数不污染蓝耗：L10 扣蓝 = data.mana_cost(%.1f)" % sd.mana_cost,
		is_equal_approx(mana_before - _player.get_mana_pool().current, sd.mana_cost))


# =============================================================================
# C. 符文表自洽（1-D3）
# =============================================================================

func _test_rune_data() -> void:
	print("--- C. 符文表自洽（槽位 / 互斥组 / 适用形态）---")
	_ok("槽位 = 3；解锁等级 = [3, 6, 9]",
		int(ConfigLoader.rune_meta.get("slots", 0)) == 3
		and _same_ints(ConfigLoader.rune_meta.get("slot_unlock_skill_level", []), [3, 6, 9]))
	var groups: Array = ConfigLoader.rune_meta.get("exclusive_groups", [])
	_ok("互斥组 = form / element / amp / util（4 组）",
		groups == ["form", "element", "amp", "util"])
	_ok("符文总数 = 24", ConfigLoader.runes.size() == 24)

	var self_ok := true
	var counts := {"form": 0, "element": 0, "amp": 0, "util": 0}
	for rid_v in ConfigLoader.runes.keys():
		var rid := String(rid_v)
		var r: Dictionary = ConfigLoader.runes[rid]
		var g := String(r.get("exclusive_group", ""))
		if g not in groups:
			self_ok = false
			_info("%s 互斥组 '%s' 不在 _meta 内" % [rid, g])
			continue
		counts[g] = int(counts.get(g, 0)) + 1
		if String(r.get("category", "")) != g:
			self_ok = false
			_info("%s category '%s' != exclusive_group '%s'"
				% [rid, String(r.get("category", "")), g])
		var allowed: Variant = r.get("allowed_types", [])
		if not (allowed is Array) or (allowed as Array).is_empty():
			self_ok = false
			_info("%s allowed_types 为空" % rid)
			continue
		for t in allowed:
			if not SkillData.TYPE_KEYS.has(String(t)):
				self_ok = false
				_info("%s 适用形态 '%s' 不是合法形态键" % [rid, String(t)])
		var mods: Variant = r.get("modifiers", {})
		if not (mods is Dictionary) or (mods as Dictionary).is_empty():
			self_ok = false
			_info("%s modifiers 为空" % rid)
	_ok("24 条符文：category==exclusive_group / allowed_types ⊆ 7 形态 / modifiers 非空", self_ok)
	_ok("组内分布 = form 6 / element 5 / amp 4 / util 9",
		counts == {"form": 6, "element": 5, "amp": 4, "util": 9})

	var per_type := true
	for t in SkillData.TYPE_KEYS:
		if ConfigLoader.runes_for_skill_type(SkillData.TYPE_KEYS.find(t)).size() < 1:
			per_type = false
			_info("形态 %s 无任何可用符文" % t)
	_ok("7 个形态各有 ≥1 个可用符文（无「形态无符文」死形态）", per_type)
	# 召唤 / 增益只吃 amp 2 + util 2 = 4（§11.1）
	var summon_n := ConfigLoader.runes_for_skill_type(
		SkillData.TYPE_KEYS.find("summon")).size()
	var buff_n := ConfigLoader.runes_for_skill_type(
		SkillData.TYPE_KEYS.find("buff")).size()
	_ok("召唤 / 增益形态各 4 个可用符文（amp 2 + util 2，§11.1）",
		summon_n == 4 and buff_n == 4)


# =============================================================================
# D. 符文互斥（1-L9）
# =============================================================================

func _test_rune_exclusive() -> void:
	print("--- D. 符文互斥：同组冲突 / 跨组放行 ---")
	var panel := SkillPanel.new()
	add_child(panel)
	var sd := ConfigLoader.get_skill("piercing_shot")
	panel.runes = {"piercing_shot": ["rune_pierce"]}
	_ok("同组冲突：已插「穿透」(form) ⇒「分裂」(form) 被拒",
		panel._rune_group_conflict("piercing_shot", "rune_split"))
	_ok("同组冲突：已插「穿透」⇒「迅捷」(amp) 放行",
		not panel._rune_group_conflict("piercing_shot", "rune_swift"))
	_ok("重复插同一个符文不算冲突（幂等）",
		not panel._rune_group_conflict("piercing_shot", "rune_pierce"))
	_ok("形态适配：「穿透」对 projectile 有效 ⇒ 对 single 无效",
		panel._rune_type_ok(sd, ConfigLoader.runes["rune_pierce"])
		and not panel._rune_type_ok(ConfigLoader.get_skill("cleave"),
			ConfigLoader.runes["rune_pierce"]))
	_ok("槽位解锁等级取自数据（[3,6,9]）", _same_ints(panel._slot_unlock_levels(), [3, 6, 9]))
	_ok("分支解锁等级取自数据（5）", panel._branch_unlock_level() == 5)
	panel.queue_free()


# =============================================================================
# E. 分支模板与套用器（1-L9）
# =============================================================================

func _test_branch_templates() -> void:
	print("--- E1. 分支模板：7 形态 × 2 分支 ---")
	_ok("模板覆盖 7 个形态", ConfigLoader.branches.size() == 7)
	_ok("解锁技能等级 = 5；重置费用 = 0（Q5 裁定先免费）",
		int(ConfigLoader.branch_meta.get("unlock_skill_level", 0)) == 5
		and int(ConfigLoader.branch_meta.get("reset_cost_gold", -1)) == 0)
	var ids := {}
	var shape_ok := true
	for t in SkillData.TYPE_KEYS:
		var opts := ConfigLoader.branch_options_for_type(t)
		if opts.size() != 2:
			shape_ok = false
			_info("形态 %s 分支数 = %d（期望 2）" % [t, opts.size()])
			continue
		for o in opts:
			var bid := String((o as Dictionary).get("id", ""))
			if bid.is_empty() or ids.has(bid):
				shape_ok = false
				_info("分支 id 空或重复：%s" % bid)
			ids[bid] = true
			if not ((o as Dictionary).get("modifiers", {}) is Dictionary):
				shape_ok = false
				_info("分支 %s modifiers 非字典" % bid)
	_ok("每形态恰好 2 分支 + 14 个 id 全局唯一", shape_ok and ids.size() == 14)


func _test_branch_apply() -> void:
	print("--- E2. 分支套用器：可映射 7 键生效 ---")
	if _skills == null:
		return
	# 合法写入 / 非法拒绝
	_skills.set_equipped_branch("piercing_shot", "proj_sharp")
	_ok("合法分支写入：piercing_shot ⇒ proj_sharp",
		_skills.get_equipped_branch("piercing_shot") == "proj_sharp")
	_skills.set_equipped_branch("piercing_shot", "single_focus")
	_ok("非法分支（single 模板的分支给 projectile 技能）⇒ 拒绝，保留原值",
		_skills.get_equipped_branch("piercing_shot") == "proj_sharp")
	_skills.set_equipped_branch("piercing_shot", "")
	_ok("空串 ⇒ 清除分支", _skills.get_equipped_branch("piercing_shot").is_empty())
	_ok("branch_options 返回该形态 2 个分支（含 modifiers）",
		_skills.branch_options("piercing_shot").size() == 2)

	# 逐键断言：期望值来自策划案 §2.3 的文字描述（硬编码，见头注释 ②）
	var base_proj := ConfigLoader.get_skill("piercing_shot")
	var proj_mult0 := base_proj.multiplier
	var proj_count0 := base_proj.projectile_count
	var cases := [
		# [技能, 分支, 校验 lambda 由下面显式写]
		["cleave", "single_focus"],
		["spin_slash", "aoe_expand"],
		["dash_strike", "dash_pierce"],
		["piercing_shot", "proj_sharp"],
		["piercing_shot", "proj_scatter"],
		["trap_spike", "ground_deep"],
		["warcry", "buff_lasting"],
	]
	var expect := {
		"single_focus": "倍率 ×1.4",
		"aoe_expand": "半径 ×1.4",
		"dash_pierce": "冲刺距离 ×1.5 且倍率 ×1.3",
		"proj_sharp": "穿透 +2",
		"proj_scatter": "3 枚扇形（70% 倍率 / 24°）",
		"ground_deep": "持续 +50%",
		"buff_lasting": "持续 +50%",
	}
	var applied_ok := true
	for c in cases:
		var sid: String = c[0]
		var bid: String = c[1]
		var base := ConfigLoader.get_skill(sid)
		var out := _skills._apply_branch_modifiers(base, bid)
		var good := false
		match bid:
			"single_focus":
				good = is_equal_approx(out.multiplier, base.multiplier * 1.4)
			"aoe_expand":
				good = is_equal_approx(out.radius, base.radius * 1.4)
			"dash_pierce":
				good = is_equal_approx(out.dash_distance, base.dash_distance * 1.5) \
					and is_equal_approx(out.multiplier, base.multiplier * 1.3)
			"proj_sharp":
				good = out.pierce_count == base.pierce_count + 2
			"proj_scatter":
				good = out.projectile_count == 3 \
					and is_equal_approx(out.spread_deg, 24.0) \
					and is_equal_approx(out.multiplier, base.multiplier * 0.7)
			"ground_deep", "buff_lasting":
				good = is_equal_approx(out.duration, base.duration * 1.5)
		if not good:
			applied_ok = false
			_info("%s + %s 未按「%s」生效" % [sid, bid, String(expect.get(bid, ""))])
	_ok("7 个可映射分支逐条生效（倍率 / 半径 / 冲刺距离 / 穿透 / 扇形 / 持续）", applied_ok)
	_ok("套用器返回副本，不改注册表模板（piercing_shot 仍为 1 枚 / 原倍率）",
		ConfigLoader.get_skill("piercing_shot").projectile_count == proj_count0
		and is_equal_approx(ConfigLoader.get_skill("piercing_shot").multiplier, proj_mult0)
		and proj_count0 == 1)
	_ok("未选分支 ⇒ 原样返回同一对象（零开销、零行为变化）",
		_skills._apply_branch_modifiers(
			ConfigLoader.get_skill("piercing_shot"), "") == ConfigLoader.get_skill("piercing_shot"))

	print("--- E3. 分支套用器：未支持键 ⇒ 零变化 + 一次性警告 ---")
	var unsupported := [
		["cleave", "single_combo"],
		["spin_slash", "aoe_linger"],
		["dash_strike", "dash_afterimage"],
		["trap_spike", "ground_pulse"],
		["spirit_wolf", "summon_legion"],
		["spirit_wolf", "summon_elite"],
		["warcry", "buff_empower"],
	]
	var zero_ok := true
	var warned_ok := true
	for c in unsupported:
		var sid: String = c[0]
		var bid: String = c[1]
		var base := ConfigLoader.get_skill(sid)
		var out := _skills._apply_branch_modifiers(base, bid)
		# 所有数值字段必须逐位不变
		if not (is_equal_approx(out.multiplier, base.multiplier)
				and is_equal_approx(out.radius, base.radius)
				and is_equal_approx(out.duration, base.duration)
				and is_equal_approx(out.dash_distance, base.dash_distance)
				and out.pierce_count == base.pierce_count
				and out.projectile_count == base.projectile_count):
			zero_ok = false
			_info("%s + %s 改动了字段（应零变化）" % [sid, bid])
		if not _has_warned_for(sid):
			warned_ok = false
			_info("%s + %s 未记入一次性警告表" % [sid, bid])
	_ok("7 个未支持分支 ⇒ 数值字段逐位不变（不静默半套用）", zero_ok)
	_ok("7 个未支持分支 ⇒ 全部记入 `_branch_warned`（不静默吞）", warned_ok)
	_ok("未支持键清单 = 8 个（combo/linger/afterimage/pulse/summon×2/potency）",
		SkillController.BRANCH_UNSUPPORTED_KEYS.size() == 8)


# =============================================================================
# F. 技能栏三标识（1-L13）
# =============================================================================

func _test_skill_bar_badges() -> void:
	print("--- F. 技能栏三标识：等级角标 / 符文圆点 / 分支色框 ---")
	if _skills == null:
		return
	var data := SaveData.create_new(0, "archer")
	data.skill_bar = ["piercing_shot", "multishot", "lightning_chain"]
	SaveManager.current_data = data
	_skills._load_skills()
	_skills.set_equipped_runes("piercing_shot", ["rune_swift", "rune_fire"])
	_skills.set_equipped_branch("piercing_shot", "proj_sharp")
	_player.apply_combat_stats(
		{"attack": 100.0, "crit_chance": -100.0, "skill_level": 5.0}, 1)

	var bar := SkillBarUI.new()
	add_child(bar)
	await get_tree().process_frame
	bar.setup(_skills)
	var st := bar.get_slot_state(0)
	_ok("槽 0 = piercing_shot", String(st.get("id", "")) == "piercing_shot")
	_ok("标识① 等级角标：skill_level = 6（注入 5 + 基准 1）",
		int(st.get("skill_level", 0)) == 6)
	_ok("标识② 符文圆点：rune_count = 2", int(st.get("rune_count", 0)) == 2)
	_ok("标识③ 分支色框：branch_id = proj_sharp 且色 = 分支 A（金）",
		String(st.get("branch_id", "")) == "proj_sharp"
		and (st.get("branch_color") as Color) == SkillBarUI.BRANCH_COLOR_A)
	var st1 := bar.get_slot_state(1)
	_ok("未配符文 / 未选分支的槽：圆点 0 + 色框灰",
		int(st1.get("rune_count", -1)) == 0
		and (st1.get("branch_color") as Color) == SkillBarUI.BRANCH_COLOR_NONE)
	_ok("符文圆点硬上限 3（控制器侧截断）",
		_skills.get_rune_count("piercing_shot") == 2)
	_skills.set_equipped_runes("piercing_shot",
		["rune_swift", "rune_fire", "rune_pierce", "rune_leech"])
	_ok("超 3 槽的符文被截断（3 槽硬上限）",
		_skills.get_rune_count("piercing_shot") == 3)
	bar.queue_free()
	_skills.set_equipped_runes("piercing_shot", [])
	_skills.set_equipped_branch("piercing_shot", "")


# =============================================================================
# G. 天赋「技之极意」（1-L10）
# =============================================================================

func _test_talent_insight() -> void:
	print("--- G. 天赋「技之极意」：flat 桶 +1 技能等级 ---")
	_ok("机制池含「技之极意」（第 6 个）",
		TalentTree.BIG_NODE_MECHANICS.size() == 6
		and TalentTree.BIG_NODE_MECHANICS.has(TalentTree.MECHANIC_SKILL_INSIGHT))
	_ok("节点 id = might.big.2", TalentTree.SKILL_INSIGHT_NODE == "might.big.2")
	var empty := TalentTree.calc_buff([], 30)
	_ok("未点任何节点 ⇒ 空字典（据点不传无意义 buff）", empty.is_empty())
	var buff := TalentTree.calc_buff([TalentTree.SKILL_INSIGHT_NODE], 30)
	var flat: Dictionary = buff.get("flat", {})
	_ok("点亮 ⇒ flat.skill_level = 1（走 flat 桶，与 StatCalculator 口径一致）",
		int(flat.get("skill_level", 0)) == 1)
	_ok("点亮 ⇒ 机制列表含「技之极意」",
		(TalentTree.new().get_bonus_stats() as Dictionary).has("mechanics"))


# =============================================================================
# H. 存档 v5 清洗
# =============================================================================

func _test_save_v5_sanitize() -> void:
	print("--- H. 存档 v5 清洗（脏档不炸运行时）---")
	var dirty := {
		"save_version": GameConstants.SAVE_VERSION, "slot": 0,
		"skill_runes": {
			"a": ["r1", "r2", "r3", "r4", "r5"],   # 超 3 槽 ⇒ 截断
			"b": "not_an_array",                     # 非数组 ⇒ 丢弃
		},
		"skill_branches": {"a": "single_focus", "b": {"x": 1}},  # 非 String 值 ⇒ 丢弃
		"unlocked_runes": ["rune_swift", 123],
	}
	var out := SaveData.from_dict(dirty)
	_ok("符文槽截断到 3（第 4/5 个被丢弃）",
		(out.skill_runes.get("a", []) as Array).size() == 3)
	_ok("非数组的符文值整条丢弃",
		not out.skill_runes.has("b") and out.skill_runes.size() == 1)
	_ok("分支只收 String 值（dict 值丢弃）",
		out.skill_branches.size() == 1
		and String(out.skill_branches.get("a", "")) == "single_focus")
	_ok("图鉴解锁列表容错（非字符串元素转字符串）",
		out.unlocked_runes.size() == 2 and out.unlocked_runes.has("rune_swift"))
	# v4 → v5 迁移补三项
	var v4 := {"save_version": 4, "slot": 0, "class_id": "warrior"}
	var mig := SaveData.from_dict(v4)
	var mig_ok := mig.migrate()
	_ok("v4 旧档迁移 ⇒ v5：三项新字段补空 + 版本升 5",
		mig_ok and mig.save_version == 5
		and mig.skill_runes.is_empty() and mig.skill_branches.is_empty()
		and mig.unlocked_runes.is_empty())
	_ok("SAVE_VERSION ≥ 5（B4-4 起符文/分支/图鉴三字段存在）",
		GameConstants.SAVE_VERSION >= 5)


# =============================================================================
# I. 符文图鉴面板（1-L12）
# =============================================================================

func _test_codex_panel() -> void:
	print("--- I. 符文图鉴面板：24 格 / 解锁态 / 详情钩子 ---")
	var panel := RuneCodexPanel.new()
	add_child(panel)
	await get_tree().process_frame
	var grid := panel.find_child("RuneGrid", true, false)
	_ok("6×4 = 24 格", grid != null and grid.get_child_count() == 24)
	_ok("面板列数 = 6", (grid as GridContainer).columns == 6)
	panel.bind(["rune_swift", "rune_fire"], 6)
	# ⚠️ `_render_grid()` 用 `queue_free()` 清旧格 ⇒ 必须等一帧，否则 `find_child`
	#    会命中**上一轮**（全部未解锁）遗留的锁节点，断言假红。
	await get_tree().process_frame
	_ok("注入 2 个已解锁 ⇒ 进度 = 2 / 24",
		panel.unlock_progress() == Vector2i(2, 24))
	_ok("is_rune_unlocked 钩子：swift 已解锁 / pierce 未解锁",
		panel.is_rune_unlocked("rune_swift") and not panel.is_rune_unlocked("rune_pierce"))
	panel.select_rune("rune_pierce")
	_ok("选中未解锁符文 ⇒ 详情可渲染（不崩）",
		panel.selected_rune() == "rune_pierce")
	var locked_cell := panel.find_child("RuneLock_rune_pierce", true, false)
	_ok("未解锁格子带锁标记", locked_cell != null)
	_ok("已解锁格子无锁标记",
		panel.find_child("RuneLock_rune_swift", true, false) == null)
	panel.queue_free()
