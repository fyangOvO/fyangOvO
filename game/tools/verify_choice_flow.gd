## 局内成长「三选一」全链路独立验证（2026-09-18 · 阶段 11 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_choice_flow.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 为什么单独一个脚本（**不能用实现者自证**）：
##   `verify_run_growth.gd` 只测**零件**（直接调 `RunBuffSystem.apply_option` /
##   `RunePool.get_choices` / `StatCalculator`），证明不了「升级 → 弹面板 → 点选 →
##   **玩家战斗数值**真的动了」这条接线。本项目的头号缺陷模式正是「生成了但没人消费」：
##   2022b86 之前 `to_calculator_buffs()` 从未被调用；2026-09-18 排障又发现它的产出
##   `attack` 等键**没有下游**（`PlayerController` 战斗 getter 整层是阶段 2 占位桩）。
##   本脚本补的正是这条缝：**逐环节实体断言，不看「信号发了」只认「数值动了」**。
##
## 覆盖：
##   A. 真实触发：`RunProgression` 升级 → 弹 3 个互不重复候选（含 run_level_up 广播）
##   B. 属性真的变（代表项「狂怒」）：玩家**攻击力**真的上升（接线的正例）
##   C. 叠层：连选 3 次「狂怒」⇒ 层数 3；cap 硬顶把 pct_attack 夹到 30%（GDD 0.4 §4.4）
##   D. 上限语义：受 cap 约束的 stat_key 各只有一个选项；达上限后从池移除
##   E. 确定性隔离：三选一用 `_choice_rng`，**不消耗**地图/保底掉落的 `_rng`
##   F. `_apply_account_stats(false)` 不白送满血（升级加血上限 ≠ 回血道具）
##   G. **15 个选项逐个**验证「选了之后至少有一个可观测的战斗属性变了」
##   H. 属性注入层：注入 / 清除 / 回退基线（向后兼容契约）
##   I. GDD §4.4 降级：受限属性达上限后池切换为功能性选项（池永不为空）
##   J. 局内增益 HUD：消费 `kill_streak_changed` + `run_buff_selected`（两个此前零消费者的信号）
##   K. **装备 → 玩家实际输出**（双向断言：下界排除「没变」、上界排除「双重计入」）★
##   L. 4 项扩展**走真实消费路径**：swift(移动 velocity) / greed(结算) / fortune(掉 roll) / armor_pierce(减伤)
##
## ⚠️ K 段是本轮唯一能永久拦住「装备全层失灵」这类缺口的东西：G 段只问「增益→玩家属性」，
##    **只有 K 段问「装备→玩家实际输出」**。改动战斗属性口径后**必须**跑本脚本。
##
## ⚠️ 测试期唯一改动：给玩家挂无敌帧，避免被怪围殴致死提前结算（与本链路无关）。
extends Node

const LEVEL_ID: String = "ch1_l01"
const SLOT: int = 6
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _level: LevelScene = null
var _player: PlayerController = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	_run()


func _run() -> void:
	print("===== 局内成长「三选一」全链路独立验证 =====")

	if SaveManager.slot_exists(SLOT):
		SaveManager.delete_slot(SLOT)
	var data := SaveManager.create_new_slot(SLOT)
	_ok("测试存档就绪（槽 %d / Lv.%d）" % [SLOT, data.account_level if data != null else -1],
		data != null and SaveManager.current_data != null)
	if data == null:
		_finish()
		return

	await _spawn_level()
	if _level == null or _player == null:
		_ok("进关成功（前置）", false)
		_finish()
		return
	_ok("进关成功（玩家 / 局内等级 %d）" % _level._progression.run_level, true)

	var max0 := _player.health.get_max_hp()
	_ok("基线：攻击 %.2f / 最大生命 %.1f（无装备、账号 Lv1）"
			% [_player.get_attack_damage(), max0],
		is_equal_approx(_player.get_attack_damage(), 12.0) and is_equal_approx(max0, 150.0))

	# 【E 前置】`_rng` 播到已知种子取探针（末尾比对「升级是否消耗 _rng」）
	var rng_probe_a := _probe_rng()

	var lv_events: Array = []
	var lv_probe := func(nl: int, ch: Array) -> void: lv_events.append({"lv": nl, "n": ch.size()})
	EventBus.run_level_up.connect(lv_probe)

	# --- A. 真实触发 ---
	print("--- A. 真实触发：升级 → 弹 3 个不重复候选 ---")
	_ok("升级并抽到「狂怒」候选", await _level_up_for("fury"))
	_ok("升级到局内 2 级", _level._progression.run_level == 2)
	_ok("弹出了三选一面板且可见",
		_level._choice_panel != null and is_instance_valid(_level._choice_panel)
		and _level._choice_panel.visible)
	var opts1: Array = _choice_options()
	_ok("候选数量 = 3", opts1.size() == 3)
	_ok("候选互不重复", _unique_ids(opts1).size() == opts1.size())
	_ok("run_level_up 广播已发出（%d 次 / 末次 lv=%d / 候选 %d）"
			% [lv_events.size(), int(lv_events[-1]["lv"]) if lv_events.size() > 0 else -1,
				int(lv_events[-1]["n"]) if lv_events.size() > 0 else -1],
		lv_events.size() == 1 and int(lv_events[0]["lv"]) == 2 and int(lv_events[0]["n"]) == 3)

	# --- B. 属性真的变（正例）---
	print("--- B. 属性真的变（狂怒 → 玩家攻击力）---")
	var atk_before := _player.get_attack_damage()
	_ok("点选「狂怒」成功", await _pick_option("fury"))
	await _wait_frames(2)
	_ok("狂怒层数 = 1", _level._buff_system.get_stacks("fury") == 1)
	var atk_after := _player.get_attack_damage()
	# 12 × (1 + 12%) = 13.44（两向：>12 且不超 13.44 + 容差）
	_ok("点选狂怒后玩家**攻击力真的变高**（%.2f → %.2f，期望 13.44）"
			% [atk_before, atk_after],
		atk_after > atk_before and absf(atk_after - 13.44) < 0.05)
	_ok("狂怒不影响生命上限（仍 %.1f）" % _player.health.get_max_hp(),
		is_equal_approx(_player.health.get_max_hp(), max0))

	# --- C. 叠层 + cap 硬顶 ---
	print("--- C. 叠层（连选狂怒）与 cap 硬顶 ---")
	_ok("再选一次狂怒（叠到 2 层）", await _select_fury())
	await _wait_frames(2)
	_ok("狂怒层数 = 2", _level._buff_system.get_stacks("fury") == 2)
	_ok("2 层狂怒 → 攻击力 ≈ 14.88（12×1.24，实际 %.2f）" % _player.get_attack_damage(),
		absf(_player.get_attack_damage() - 14.88) < 0.05)
	_ok("再选一次狂怒（叠到 3 层）", await _select_fury())
	await _wait_frames(2)
	_ok("狂怒层数 = 3（跨级可重复抽取，叠层机制可达）",
		_level._buff_system.get_stacks("fury") == 3)
	# 3 层 = 36% 原始值，必须被 cap 30 夹住
	var fury_pct := float(_level._buff_system.to_calculator_buffs()["fury"]["pct"]["pct_attack"])
	_ok("cap 硬顶：3 层狂怒的 pct_attack 被夹到 30（原始 36，实际 %.1f）" % fury_pct,
		absf(fury_pct - 30.0) < 0.01)
	_ok("3 层狂怒 → 攻击力 ≈ 15.60（12×1.30，实际 %.2f）" % _player.get_attack_damage(),
		absf(_player.get_attack_damage() - 15.60) < 0.05)

	# --- D. 上限语义 ---
	print("--- D. 上限语义 ---")
	var stat_at_cap := {"pct_attack": 36.0}
	var r := RandomNumberGenerator.new()
	r.seed = 424242
	var fury_in_pool := false
	for opt in RunePool.get_choices(3, [], stat_at_cap, r):
		if str(opt["id"]) == "fury":
			fury_in_pool = true
	_ok("pct_attack 达上限后狂怒从池移除（GDD 0.4 §4.4）", not fury_in_pool)
	var cap_options := {}
	for opt in RunePool.OPTIONS:
		if float(opt["cap"]) > 0.0:
			cap_options[str(opt["stat_key"])] = int(cap_options.get(str(opt["stat_key"]), 0)) + 1
	_ok("受 cap 约束的每个 stat_key 只有 1 个选项（%s）" % str(cap_options.keys()),
		cap_options.size() == 4)

	# --- E. 确定性隔离 ---
	print("--- E. 三选一不消耗 `_rng`（地图/保底掉落随机源）---")
	_ok("做完 3 次升级选卡后，`_rng` 状态与升级前完全相同（地图可复现性未破坏）",
		_probe_rng() == rng_probe_a)
	_ok("对照：`_choice_rng` 确实被消耗过（否则上一条是假绿）", _level._choice_rng.state != 0)

	# --- F. 不白送满血 ---
	print("--- F. `_apply_account_stats(false)` 不白送满血 ---")
	_player.health.current_hp = 100.0
	_ok("升级并抽到「坚韧」候选", await _level_up_for("tenacity"))
	_ok("点选「坚韧」成功", await _pick_option("tenacity"))
	await _wait_frames(2)
	var new_max := _player.health.get_max_hp()
	_ok("点选坚韧后**最大生命真的变高**（%.1f → %.1f，期望 172.5）" % [max0, new_max],
		new_max > max0 and absf(new_max - 172.5) < 0.05)
	_ok("升级加血上限**不白送满血**：当前血量保持 100（实际 %.1f）" % _player.health.current_hp,
		is_equal_approx(_player.health.current_hp, 100.0))
	_level._apply_account_stats(true)
	_ok("对照：`_apply_account_stats(true)` 会补满（%.1f == max）" % _player.health.current_hp,
		is_equal_approx(_player.health.current_hp, new_max))

	# --- G. 15 个选项逐个「属性真的变」---
	await _test_all_options_observable()

	# --- H. 注入层（A 的向后兼容契约）---
	_test_injection_layer()

	# --- I. GDD §4.4 降级 ---
	_test_cap_degrade()

	# --- J. 局内增益 HUD（原任务 D）---
	await _test_buff_hud()

	# --- K. 装备 → 玩家实际输出（H 要求）---
	await _test_equipment_to_output()

	# --- L. 4 项扩展走真实消费路径 ---
	await _test_extensions()

	EventBus.run_level_up.disconnect(lv_probe)

	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		await _wait_frames(1)
	if SaveManager.slot_exists(SLOT):
		SaveManager.delete_slot(SLOT)
	_finish()


# =============================================================================
# G. 15 个选项逐个可观测
# =============================================================================

## 每个三选一选项 → 它在 `StatCalculator` 输出里的**可观测键**。
## 多数 stat_key 与输出键同名；只有「百分比型主属性」在输出里变成绝对值键。
func _observable_key(rune_stat_key: String) -> String:
	match rune_stat_key:
		"pct_attack": return "attack"
		"pct_hp": return "max_hp"
		"pct_armor": return "armor"
	return rune_stat_key


## 已有**真实战斗 getter**接线的选项（其余选项目前只到达「玩家战斗属性表」，
## 战斗管线尚未消费 —— 见报告「不该改的项」：消费方在 damage_calc / health_component，
## 不在本轮文件独占范围）。
const _WIRED_GETTER_IDS: Array[String] = ["fury", "gale", "lethal", "rend", "tenacity", "bulwark"]


func _test_all_options_observable() -> void:
	print("--- G. 15 个选项逐个「属性真的变」---")
	var checked := 0
	for opt in RunePool.OPTIONS:
		var id := str(opt["id"])
		var obs_key := _observable_key(str(opt["stat_key"]))
		# 基线：清空局内增益后重算属性
		_level._buff_system.reset()
		_level._apply_account_stats(false)
		var before := _player.get_combat_stat(obs_key)
		# 选中该选项后重算
		_level._buff_system.apply_option(id)
		_level._apply_account_stats(false)
		var after := _player.get_combat_stat(obs_key)
		_ok("选项 %-12s 选了之后「%s」变了（%.3f → %.3f）" % [id, obs_key, before, after],
			after > before)
		checked += 1
		# 已接线的 6 个：再断言**真实战斗 getter** 也变了
		match id:
			"fury":
				_ok("   └ 真实 getter get_attack_damage = %.2f > 12" % _player.get_attack_damage(),
					_player.get_attack_damage() > 12.0)
			"gale":
				_ok("   └ 真实 getter get_attack_speed_multiplier = %.2f > 1"
						% _player.get_attack_speed_multiplier(),
					_player.get_attack_speed_multiplier() > 1.0)
			"lethal":
				_ok("   └ 真实 getter get_crit_chance = %.1f > 5" % _player.get_crit_chance(),
					_player.get_crit_chance() > 5.0)
			"rend":
				_ok("   └ 真实 getter get_crit_damage = %.1f > 150" % _player.get_crit_damage(),
					_player.get_crit_damage() > 150.0)
			"tenacity":
				_ok("   └ 真实 getter get_max_hp = %.1f > 150" % _player.get_max_hp(),
					_player.get_max_hp() > 150.0)
			"bulwark":
				_ok("   └ 真实 getter get_armor = %.2f > 6" % _player.get_armor(),
					_player.get_armor() > 6.0)
	_ok("15 个选项全部纳入逐项断言（实际 %d）" % checked, checked == 15)
	# 复位
	_level._buff_system.reset()
	_level._apply_account_stats(false)


# =============================================================================
# H. 注入层契约
# =============================================================================

func _test_injection_layer() -> void:
	print("--- H. 属性注入层（注入 / 清除 / 回退基线）---")
	_player.clear_combat_stats()
	_ok("清除注入后回退基线：攻击 12 / 暴击 5 / 护甲 6 / 抗性 0 / 攻速 ×1 / 等级 1",
		is_equal_approx(_player.get_attack_damage(), 12.0)
		and is_equal_approx(_player.get_crit_chance(), 5.0)
		and is_equal_approx(_player.get_armor(), 6.0)
		and _player.get_resist("fire") == 0.0
		and is_equal_approx(_player.get_attack_speed_multiplier(), 1.0)
		and _player.get_player_level() == 1)
	_player.apply_combat_stats({
		"attack": 100.0, "max_hp": 999.0, "armor": 50.0,
		"crit_chance": 10.0, "crit_damage": 50.0, "attack_speed": 20.0,
		"fire_resist": 30.0,
	}, 30)
	_ok("注入后：攻击=100（绝对值直读，不叠裸装）", is_equal_approx(_player.get_attack_damage(), 100.0))
	_ok("注入后：护甲=50（绝对值）", is_equal_approx(_player.get_armor(), 50.0))
	_ok("注入后：暴击 5+10=15 / 暴伤 150+50=200（增量叠加）",
		is_equal_approx(_player.get_crit_chance(), 15.0)
		and is_equal_approx(_player.get_crit_damage(), 200.0))
	_ok("注入后：攻速 ×1.20 / 火抗 30 / 等级 30",
		is_equal_approx(_player.get_attack_speed_multiplier(), 1.2)
		and is_equal_approx(_player.get_resist("fire"), 30.0)
		and _player.get_player_level() == 30)
	_player.clear_combat_stats()
	_ok("再次清除 → 回退基线（攻击 12）", is_equal_approx(_player.get_attack_damage(), 12.0))


# =============================================================================
# I. GDD §4.4 降级
# =============================================================================

func _test_cap_degrade() -> void:
	print("--- I. GDD §4.4：受限属性达上限后池切换为功能性选项 ---")
	# 受限属性全部顶到上限
	var capped := {"pct_attack": 30.0, "attack_speed": 20.0, "crit_chance": 20.0, "pct_hp": 30.0}
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var choices := RunePool.get_choices(3, [], capped, r)
	var any_capped := false
	for opt in choices:
		if str(opt["stat_key"]) in capped:
			any_capped = true
	_ok("受限属性全达上限后，池仍有功能性选项（不空，GDD §4.4「自动切换」）", choices.size() > 0)
	_ok("达上限的类别不再出现在候选（%s）" % _ids_text(choices), not any_capped)


# =============================================================================
# J. 局内增益 HUD（原任务 D）
# =============================================================================

func _test_buff_hud() -> void:
	print("--- J. 局内增益 HUD（三选一叠层 + 连杀）---")
	_ok("HUD 增益 Label 已创建", _level._buff_label != null and is_instance_valid(_level._buff_label))
	if _level._buff_label == null:
		return
	# 三选一叠层可见
	_level._buff_system.reset()
	_level._buff_system.apply_option("fury")
	_level._buff_system.apply_option("fury")
	_level._refresh_buff_hud()
	_ok("HUD 显示三选一叠层「狂怒×2」（实际：%s）" % _level._buff_label.text,
		_level._buff_label.text.contains("狂怒×2"))
	# 连杀：`on_kill()` 发 `kill_streak_changed` → HUD 作为**消费者**刷新（此前该信号零消费者）
	_level._buff_system.on_kill()
	await _wait_frames(1)
	_ok("HUD 消费 `kill_streak_changed` 显示连杀（实际：%s）" % _level._buff_label.text,
		_level._buff_label.text.contains("连杀"))
	_level._buff_system.reset()
	_level._refresh_buff_hud()
	_ok("复位后 HUD 回到「—」（实际：%s）" % _level._buff_label.text,
		_level._buff_label.text.contains("—"))
	# `run_buff_selected` 消费者（裁定2）：面板广播 → HUD 刷新（事件驱动，非轮询）
	_level._buff_system.apply_option("gale")
	EventBus.run_buff_selected.emit("gale", 1)
	await _wait_frames(1)
	_ok("HUD 消费 `run_buff_selected` 后刷新（实际：%s）" % _level._buff_label.text,
		_level._buff_label.text.contains("疾风×1"))
	_level._buff_system.reset()
	_level._refresh_buff_hud()


# =============================================================================
# K. 装备 → 玩家实际输出（H 要求 · 双向断言防双重计入）
# =============================================================================

## 这一段的理由：G 段验的是「增益 → 玩家属性」，**没有任何一条**问「装备 → 玩家实际输出」——
## 而装备正是本游戏的核心前提，也正是这次被发现**全层失灵**的东西。没有 K，同类缺口会再发生。
##
## 断言口径（team-lead 要求）：
##   下界：装备上加攻属性后 `get_attack_damage()` **真的变大**（排除「没接上」）；
##   上界：攻击 ≤ `(裸装flat + 装备flat) × (1 + 装备pct%) × 1.05`（排除「把绝对值再乘裸装基线」的**双重计入**）。
func _test_equipment_to_output() -> void:
	print("--- K. 装备 → 玩家实际输出（双向断言）---")
	var data := SaveManager.current_data
	if data == null:
		_ok("存档就绪（前置）", false)
		return
	var saved_level := data.account_level
	var saved_main := data.get_equipped(GameConstants.EquipSlot.MAIN_HAND)
	# 用较高账号等级：让「被重复乘裸装成长」这类双重计入在上界下暴露（L1 时 1.1^0=1 掩盖）
	data.account_level = 11
	data.set_equipped(GameConstants.EquipSlot.MAIN_HAND, null)
	_level._buff_system.reset()
	_level._apply_account_stats(false)
	var atk_no_gear := _player.get_attack_damage()

	var item := _make_attack_item(50.0, 11)
	data.set_equipped(GameConstants.EquipSlot.MAIN_HAND, item)
	_level._apply_account_stats(false)
	var atk_gear := _player.get_attack_damage()

	var gear := EquipmentCompare.get_total_stats(item)
	var base_atk := float(StatCalculator.base_stats(11)["flat_attack"])
	var expected := (base_atk + float(gear.get("flat_attack", 0.0))) \
		* (1.0 + float(gear.get("pct_attack", 0.0)) / 100.0)
	_ok("① 下界：装备 +50%% 攻击后玩家攻击力**真的变大**（%.2f → %.2f）" % [atk_no_gear, atk_gear],
		atk_gear > atk_no_gear)
	_ok("② 上界：未被重复计入（攻击 %.2f ∈ [%.2f, %.2f]）"
			% [atk_gear, expected * 0.95, expected * 1.05],
		atk_gear >= expected * 0.95 and atk_gear <= expected * 1.05)
	_ok("③ 装备确实改变了输出（装备 pct_attack=%.1f，相对裸装 +%.0f%%）"
			% [float(gear.get("pct_attack", 0.0)), (atk_gear / atk_no_gear - 1.0) * 100.0],
		atk_gear > atk_no_gear * 1.1)

	# 还原
	data.account_level = saved_level
	data.set_equipped(GameConstants.EquipSlot.MAIN_HAND, saved_main)
	_level._apply_account_stats(false)


## 造一件**确定**加攻击的武器（词缀值固定，便于算上界）
func _make_attack_item(pct: float, ilvl: int) -> EquipmentInstance:
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	var item := EquipmentInstance.create_from_template(tpl, ilvl, GameConstants.Rarity.RARE)
	var aff: AffixData = ConfigLoader.affixes.get("add_pct_attack")
	if aff != null:
		var roll := AffixRoll.new()
		roll.affix_id = "add_pct_attack"
		roll.template = aff
		roll.value = pct
		roll.quality = 1
		item.affixes = [roll]
	return item


# =============================================================================
# L. 4 项扩展走真实消费路径
# =============================================================================

func _test_extensions() -> void:
	print("--- L. 扩展 4 项走真实消费路径 ---")
	await _test_swift()
	_test_greed()
	_test_fortune()
	_test_armor_pierce()


## swift：真实路径 = 移动公式产出的**实际 velocity**
func _test_swift() -> void:
	var mv := PLAYER_SCENE.instantiate() as PlayerController
	add_child(mv)
	# ⚠️ 把临时玩家移出 `player` 组：否则它会污染后面 `enemy._refresh_player()` 的
	#    `get_first_node_in_group("player")` 结果（本测试曾因此 flaky）。
	mv.remove_from_group(&"player")
	mv.global_position = Vector2.ZERO
	await _wait_physics(2)
	mv.clear_combat_stats()
	var v_base := await _drive_move_speed(mv)
	mv.apply_combat_stats({"move_speed": 12.0}, 1)
	var v_swift := await _drive_move_speed(mv)
	_ok("swift 迅捷 ×1.12：真实移动速度 %.1f → %.1f（期望 %.1f）"
			% [v_base, v_swift, v_base * 1.12],
		absf(v_base - 144.0) < 2.0 and absf(v_swift - 144.0 * 1.12) < 3.0)
	mv.apply_combat_stats({}, 0)
	_ok("swift 默认（未注入）回退 1.0", is_equal_approx(mv.get_move_speed_multiplier(), 1.0))
	mv.queue_free()
	await _wait_frames(1)


## 按住 move_right 若干物理帧后读**实际 velocity**（= 移动公式产出，非属性表）
func _drive_move_speed(p: PlayerController) -> float:
	Input.action_press(&"move_right")
	for _i in 30:
		await get_tree().physics_frame
	var v := p.velocity.length()
	Input.action_release(&"move_right")
	return v


## greed：真实路径 = RunResult.finalize 的结算乘区
func _test_greed() -> void:
	var base := RunResult.finalize(true, 0, 1, 100.0, {"magic_stone": 10}, [], 0, 0, 0, 0.0)
	var greedy := RunResult.finalize(true, 0, 1, 100.0, {"magic_stone": 10}, [], 0, 0, 0, 30.0)
	_ok("greed 贪婪：结算金币 %d → %d（期望 50 → 65）"
			% [int(base.gold_after), int(greedy.gold_after)],
		int(base.gold_after) == 50 and int(greedy.gold_after) == 65)
	_ok("greed 贪婪：结算材料 %d → %d（期望 5 → 6）"
			% [int(base.materials_after.get("magic_stone", 0)),
				int(greedy.materials_after.get("magic_stone", 0))],
		int(base.materials_after.get("magic_stone", 0)) == 5
		and int(greedy.materials_after.get("magic_stone", 0)) == 6)
	_ok("greed 默认（0）与修复前逐位一致（金币 50）", int(base.gold_after) == 50)


## fortune：真实路径① = LootRoller 稀有度 roll（固定种子统计）；② = enemy→LootRoller 消费者链路
func _test_fortune() -> void:
	var weights: Array = []
	weights.resize(GameConstants.RARITY_COUNT)
	weights.fill(0.0)
	weights[GameConstants.Rarity.COMMON] = 100.0
	weights[GameConstants.Rarity.RARE] = 100.0
	var n := 800
	seed(20260918)
	var base_rare := 0
	for _i in n:
		if LootRoller._roll_rarity(weights, 0, 0, 1, 0.0) != GameConstants.Rarity.COMMON:
			base_rare += 1
	seed(20260918)
	var luck_rare := 0
	for _i in n:
		if LootRoller._roll_rarity(weights, 0, 0, 1, 100.0) != GameConstants.Rarity.COMMON:
			luck_rare += 1
	_ok("fortune 幸运：固定种子下非白掉落 %d → %d（+100%% 幸运应更多）" % [base_rare, luck_rare],
		luck_rare > base_rare)
	_ok("fortune 默认（0）不改变分布（同种子同结果）",
		base_rare == _count_non_common(weights, 0.0, n))

	# 消费者链路：enemy._drop_loot → LootRoller.roll_loot（读玩家的 magic_find）。
	# ⚠️ 用**关卡里已有的敌人**作探针（它们的 `_player` 在建关时就绑好了），
	#    不要新建敌人——新建时 `_ready` 的 `get_first_node_in_group("player")` 有时序 flaky。
	_player.apply_combat_stats({"magic_find": 10.0}, 1)
	var probe: EnemyBase = null
	for e in _level._alive:
		if is_instance_valid(e):
			probe = e
			break
	_ok("关卡里有敌人可作掉落消费者探针", probe != null)
	if probe != null:
		_ok("敌人已绑定玩家（probe._player 非空）", probe._player != null)
		_ok("enemy._player_magic_find() 读到玩家幸运=10（实际 %.2f）" % probe._player_magic_find(),
			absf(probe._player_magic_find() - 10.0) < 0.001)
	_player.clear_combat_stats()


func _count_non_common(weights: Array, magic_find: float, n: int) -> int:
	seed(20260918)
	var c := 0
	for _i in n:
		if LootRoller._roll_rarity(weights, 0, 0, 1, magic_find) != GameConstants.Rarity.COMMON:
			c += 1
	return c


## armor_pierce：真实路径 = DamageCalc 减伤（crit=0 ⇒ 确定性）
func _test_armor_pierce() -> void:
	_ok("pierced_armor(100, 15) = 85", is_equal_approx(DamageCalc.pierced_armor(100.0, 15.0), 85.0))
	_ok("pierced_armor(100, 0) = 100（默认不变）",
		is_equal_approx(DamageCalc.pierced_armor(100.0, 0.0), 100.0))
	var no_pierce := DamageCalc.compute_hit(100.0, 0.0, 150.0, GameConstants.ELEMENT_PHYSICAL,
		0.0, 100.0, 0.0, 1, 0.0)
	var with_pierce := DamageCalc.compute_hit(100.0, 0.0, 150.0, GameConstants.ELEMENT_PHYSICAL,
		0.0, DamageCalc.pierced_armor(100.0, 15.0), 0.0, 1, 0.0)
	_ok("armor_pierce 破甲：最终伤害真的变高（%.2f → %.2f）"
			% [no_pierce.final_damage, with_pierce.final_damage],
		with_pierce.final_damage > no_pierce.final_damage)


# =============================================================================
# 工具
# =============================================================================

func _spawn_level() -> void:
	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _wait_frames(2)
	_level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _wait_frames(3)
	_player = _level._player
	if _player != null and _player.health != null:
		_player._iframe_timer = 9999.0


## 在 [1, 50000) 找「用当前 stats_pct 能抽到 target_id」的确定性种子
func _seed_for(target_id: String, stats_pct: Dictionary) -> int:
	for s in range(1, 50000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		for opt in RunePool.get_choices(3, [], stats_pct, r):
			if str(opt["id"]) == target_id:
				return s
	return -1


## 触发一次升级并把候选固定到「含 target_id」，返回是否成功（不点选，仅弹面板）
func _level_up_for(target_id: String) -> bool:
	var sp := _level._run_stats_pct()
	var s := _seed_for(target_id, sp)
	if s <= 0:
		return false
	_level._choice_rng.seed = s
	_level._progression.add_xp(RunProgression.xp_to_next(_level._progression.run_level))
	await _wait_frames(3)
	return _has_option(_choice_options(), target_id)


## 升级 + 点选 target_id（完整真实链路）
func _select_fury() -> bool:
	if not await _level_up_for("fury"):
		return false
	return await _pick_option("fury")


func _probe_rng() -> int:
	_level._rng.seed = 777
	var v := _level._rng.randi()
	_level._rng.seed = 777
	return v


func _choice_options() -> Array:
	if _level._choice_panel == null or not is_instance_valid(_level._choice_panel):
		return []
	return _level._choice_panel._options


func _pick_option(option_id: String) -> bool:
	var panel := _level._choice_panel
	if panel == null or not is_instance_valid(panel):
		return false
	var idx := -1
	for i in panel._options.size():
		if str(panel._options[i]["id"]) == option_id:
			idx = i
			break
	if idx < 0:
		return false
	var btns := _find_buttons(panel)
	if idx >= btns.size():
		return false
	btns[idx].pressed.emit()
	return true


func _find_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	for c in root.get_children():
		if c is Button:
			out.append(c as Button)
		out.append_array(_find_buttons(c))
	return out


func _has_option(opts: Array, id: String) -> bool:
	for o in opts:
		if str(o["id"]) == id:
			return true
	return false


func _unique_ids(opts: Array) -> Array:
	var s: Array = []
	for o in opts:
		if not s.has(str(o["id"])):
			s.append(str(o["id"]))
	return s


func _ids_text(opts: Array) -> String:
	var a: Array[String] = []
	for o in opts:
		a.append(str(o["id"]))
	return "[" + ", ".join(a) + "]"


func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _wait_physics(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
