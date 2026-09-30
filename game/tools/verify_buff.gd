## 臨時增益（Buff）系統實測（第四步 B4-1 · 3-B1~3-B4 · 開發用，不屬於遊戲玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_buff.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 別名表 + 鍵閉合（3-B1）：effect `stat` 名 → StatCalculator 键；`all_damage` 已进 FINAL_KEYS
##   B. BuffComponent 本體（3-B1）：施加 / 疊層 / 刷新 / 到期 / 清空 / 健康側鍵排除
##   C. 玩家消費（3-B2）：`get_damage_bonus` / 移速乘區 / 減傷乘區 / 併入 StatCalculator
##   D. 敵人消費（3-B3）：減甲（`enemy_armor_reduction`）/ 減速（`move_speed`）
##   E. 傳奇總線 4 類執行器（3-B1/B2/B3）：`buff_stat`（self / enemy）/ `ms_boost` /
##      `damage_reduction` / `summon`（含未定義 creature 守門）
##   F. BUFF 型技能（3-B1）：`BUFF_DEFS` 7 條與 `skills.json` 一致 + 施放真的生效 + 限時護盾到期
##   G. HUD 增益欄（3-B4）：`BuffBarUI` 讀到激活中的增益
##
## ⚠️ 本脚本的「规范清单」（`EFFECT_STATS` / `EXPECTED_BUFF_IDS` / `WIRED_EFFECT_IDS`）
##    均来自策划案与数据文件，**不是**从被检代码反推 ⇒ 不属自洽式伪校验。
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## effect JSON 里出现过的全部 `buff_stat.stat` 名（规范：`legendary_effects.json` 实测 8 种）
const EFFECT_STATS: Array[String] = [
	"all_attributes", "all_damage", "armor_pct", "attack_speed",
	"dodge", "enemy_armor_reduction", "gold_gain", "move_speed",
]

## 第二期 16 条「依赖临时增益 / 召唤物系统」的传奇特效 id（规范：`03-装备特色玩法.md` §2.8）
const WIRED_EFFECT_IDS: Array[String] = [
	"kuang_lan_chao_xi_ren", "you_an_yi_ying_pao", "sui_jia_po_jun_quan",
	"xun_jie_ji_xing_tui", "tie_bi_zhong_zhuang_tui", "shun_ying_huan_bu_xue",
	"wang_quan_tong_yu_zhui", "lie_jie_zhi_huan", "tan_lan_ju_bao_jie",
	"qi_jie_zhi_guan", "jian_ren_tie_lu_kui", "pan_shi_bu_dong_jia",
	"ji_feng_lie_shou_zhua", "ying_zhe_zhi_hun_jie",
	"an_shi_zhou_yin_shu", "qi_chong_hui_xiang_zhi_guan",
]

## 归一键必须可被消费：FINAL_KEYS（输出）/ 健康侧键（HealthComponent 直读）/
## `StatCalculator` 的 **pct 乘算输入键**（`pct_armor` / `pct_attack` / `all_attributes`
## 参与主属性三件套乘算，本身不出现在输出键集里）。
const CALC_INPUT_KEYS: Array[String] = ["pct_armor", "pct_attack", "all_attributes"]

var _fail: int = 0
var _player: PlayerController = null
var _skills: SkillController = null
var _bus: LegendaryBus = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 臨時增益（Buff）系統實測（第四步 B4-1）=====")
	_player = PLAYER_SCENE.instantiate() as PlayerController
	add_child(_player)
	_player.global_position = Vector2.ZERO
	_skills = _player.get_skill_controller()
	_bus = LegendaryBus.new()
	_bus.name = "LegendaryBus"
	add_child(_bus)
	_bus.setup(_player)
	_ok("場景就緒：玩家 + BuffComponent + 技能控制器 + 傳奇總線",
		_player.get_buff_component() != null and _skills != null and _bus != null)
	await _test_alias_and_keys()
	await _test_component()
	await _test_player_consumption()
	await _test_enemy_consumption()
	await _test_legendary_executors()
	await _test_buff_skills()
	await _test_hud()
	_finish()


func _spawn_enemy(mid: String, pos: Vector2) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.monster_id = mid
	e.level = 1
	e.difficulty_tier = GameConstants.DifficultyTier.NM1
	add_child(e)
	e.global_position = pos
	return e


func _step(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for i in range(frames):
		await get_tree().process_frame


# =============================================================================
# A. 別名表 + 鍵閉合（3-B1）
# =============================================================================

func _test_alias_and_keys() -> void:
	print("--- A. 別名表 + 鍵閉合（3-B1）---")
	var unknown: Array[String] = []
	for s in EFFECT_STATS:
		if BuffComponent.resolve_key(s).is_empty():
			unknown.append(s)
	_ok("8 種 effect stat 名全部可歸一（未知 %d 種）" % unknown.size(), unknown.is_empty())
	for u in unknown:
		_info("未知: %s" % u)

	_ok("armor_pct -> pct_armor", BuffComponent.resolve_key("armor_pct") == "pct_armor")
	_ok("enemy_armor_reduction -> pct_armor（掛敵人，值取負）",
		BuffComponent.resolve_key("enemy_armor_reduction") == "pct_armor")
	_ok("all_damage -> all_damage", BuffComponent.resolve_key("all_damage") == "all_damage")
	_ok("未知 stat 返回空串（調用方據此記日誌，不靜默）",
		BuffComponent.resolve_key("no_such_stat").is_empty())

	# 歸一後的鍵必須真的能被消費（輸出鍵 / 健康側鍵 / pct 乘算輸入鍵）
	var missing: Array[String] = []
	for s in EFFECT_STATS:
		var k := BuffComponent.resolve_key(s)
		if not (k in StatCalculator.FINAL_KEYS) and not (k in BuffComponent.HEALTH_SIDE_KEYS) \
				and not (k in CALC_INPUT_KEYS):
			missing.append("%s -> %s" % [s, k])
	_ok("歸一鍵全部可被消費（缺失 %d）" % missing.size(), missing.is_empty())
	for m in missing:
		_info("缺失: %s" % m)

	# 反向守門：pct_armor / all_attributes 確實會被 StatCalculator 乘算（不是空轉）
	var armor_only := StatCalculator.calculate(1, [], {
		"b1": { "pct": { "pct_armor": 100.0 } },
	})
	var attr_only := StatCalculator.calculate(1, [], {
		"b2": { "pct": { "all_attributes": 100.0 } },
	})
	var naked := StatCalculator.calculate(1, [], {})
	_ok("pct_armor 100 ⇒ 護甲翻倍（%.2f → %.2f）" % [float(naked["armor"]), float(armor_only["armor"])],
		is_equal_approx(float(armor_only["armor"]), float(naked["armor"]) * 2.0))
	_ok("all_attributes 100 ⇒ 攻擊翻倍（%.2f → %.2f）" % [float(naked["attack"]), float(attr_only["attack"])],
		is_equal_approx(float(attr_only["attack"]), float(naked["attack"]) * 2.0))

	_ok("FINAL_KEYS 含 all_damage（B4 新增）", "all_damage" in StatCalculator.FINAL_KEYS)
	_ok("FINAL_KEYS 規模 = 54（52 + all_damage + block_damage_reduction）", StatCalculator.FINAL_KEYS.size() == 54)
	_ok("StatPanel.LABELS 覆蓋 all_damage", StatPanel.LABELS.has("all_damage"))
	_ok("StatPanel.PCT_KEYS 含 all_damage", "all_damage" in StatPanel.PCT_KEYS)


# =============================================================================
# B. BuffComponent 本體（3-B1）
# =============================================================================

func _test_component() -> void:
	print("--- B. BuffComponent 本體（3-B1）---")
	var bc := BuffComponent.new()
	add_child(bc)

	# 疊層：max_stacks = 9 ⇒ 疊到 9 封頂
	for i in range(12):
		bc.add_buff("all_damage", 6.0, 999.0, "qi_jie", 9)
	_ok("疊層封頂 9（實際 %d）" % bc.get_stat_bonus("all_damage"),
		is_equal_approx(bc.get_stat_bonus("all_damage"), 54.0))
	var e1: Dictionary = bc.get_active()[0]
	_ok("疊層數 = 9", int(e1["stacks"]) == 9)

	# 刷新：max_stacks = 1 ⇒ 不疊層，取 max(剩餘)
	bc.clear()
	bc.add_buff("dodge", 20.0, 2.5, "a")
	bc.add_buff("dodge", 20.0, 1.0, "a")
	_ok("同名 max_stacks=1 ⇒ 刷新不疊層（stacks=%d）" % int(bc.get_active()[0]["stacks"]),
		int(bc.get_active()[0]["stacks"]) == 1)
	_ok("刷新取 max(剩餘) = 2.5s", float(bc.get_active()[0]["remain"]) > 2.0)

	# 不同 source_id ⇒ 各自獨立
	bc.add_buff("dodge", 20.0, 2.5, "b")
	_ok("不同 source_id 各自獨立（%d 條）" % bc.active_count(), bc.active_count() == 2)
	_ok("dodge 總加成 = 40", is_equal_approx(bc.get_stat_bonus("dodge"), 40.0))

	# 減甲：數據寫正值 ⇒ 內部存負
	bc.clear()
	bc.add_buff("enemy_armor_reduction", 10.0, 3.0, "sui_jia")
	_ok("enemy_armor_reduction 存為 -10（護甲降低）",
		is_equal_approx(bc.get_stat_bonus("pct_armor"), -10.0))

	# 邊界：duration <= 0 / 未知 stat 不入表
	bc.clear()
	bc.add_buff("dodge", 20.0, 0.0, "x")
	bc.add_buff("no_such_stat", 20.0, 5.0, "x")
	_ok("duration<=0 與未知 stat 均不入表", bc.active_count() == 0)

	# 健康側鍵不得進 StatCalculator 通道（防雙重計入）
	bc.clear()
	bc.add_buff("move_speed", 30.0, 5.0, "w")
	bc.add_buff("damage_reduction", 10.0, 5.0, "t")
	var calc_buffs := bc.to_calculator_buffs()
	var leaked: Array[String] = []
	for id in calc_buffs:
		for k in (calc_buffs[id]["pct"] as Dictionary):
			if String(k) in BuffComponent.HEALTH_SIDE_KEYS:
				leaked.append(String(k))
	_ok("to_calculator_buffs 排除健康側鍵（泄漏 %d）" % leaked.size(), leaked.is_empty())
	_ok("健康側鍵仍可由 get_stat_bonus 讀到",
		is_equal_approx(bc.get_stat_bonus("move_speed"), 30.0)
		and is_equal_approx(bc.get_stat_bonus("damage_reduction"), 10.0))

	# 到期：0.2s 後自動清理
	bc.clear()
	bc.add_buff("dodge", 20.0, 0.2, "exp")
	_ok("到期前有 1 條", bc.active_count() == 1)
	await _step(0.4)
	_ok("到期後自動清理（%d 條）" % bc.active_count(), bc.active_count() == 0)

	bc.queue_free()


# =============================================================================
# C. 玩家消費（3-B2）
# =============================================================================

func _test_player_consumption() -> void:
	print("--- C. 玩家消費（3-B2）---")
	var bc := _player.get_buff_component()
	bc.clear()
	_player.clear_combat_stats()

	# ① all_damage 進 FINAL_KEYS（經 StatCalculator）—— 物理 + 元素皆受益
	bc.add_buff_key("all_damage", 12.0, 60.0, "t_all")
	var stats := StatCalculator.calculate(1, [], bc.to_calculator_buffs())
	_ok("all_damage 經 StatCalculator 落到 FINAL_KEYS（= 12）",
		is_equal_approx(float(stats.get("all_damage", -1.0)), 12.0))
	_player.apply_combat_stats(stats, 1)
	_ok("physical 元素加成仍恆 0（口徑不變）",
		is_equal_approx(_player.get_element_damage_bonus("physical"), 0.0))
	_ok("get_damage_bonus(physical) = 0 + all_damage 12",
		is_equal_approx(_player.get_damage_bonus("physical"), 12.0))
	_ok("get_damage_bonus(fire) = 0 + all_damage 12",
		is_equal_approx(_player.get_damage_bonus("fire"), 12.0))
	_player.clear_combat_stats()

	# ② 移速：HealthComponent 直接消費（不經 StatCalculator ⇒ 不與 _move_speed_multiplier 雙計）
	bc.clear()
	_ok("無增益時移速乘區 = 1.0", is_equal_approx(_player.health.get_move_speed_factor(), 1.0))
	bc.add_buff_key("move_speed", 40.0, 60.0, "t_ms")
	_ok("+40% 移速 ⇒ 乘區 1.4",
		is_equal_approx(_player.health.get_move_speed_factor(), 1.4))
	bc.clear()

	# ③ 減傷：與護甲相乘（不相加）
	var base_mult := _player.health._damage_reduction_multiplier()
	bc.add_buff_key("damage_reduction", 20.0, 60.0, "t_dr")
	var dr_mult := _player.health._damage_reduction_multiplier()
	_ok("20%% 減傷 ⇒ 乘區 × 0.8（%.4f → %.4f）" % [base_mult, dr_mult],
		is_equal_approx(dr_mult, base_mult * 0.8))
	bc.clear()

	# ④ 併入既有 RunBuffSystem（不是取代）—— 同名 id 的 pct 相加
	var a := { "swift": { "pct": { "move_speed": 10.0 } } }
	var b := { "swift": { "pct": { "move_speed": 5.0 } }, "other": { "pct": { "dodge": 3.0 } } }
	var merged := LevelScene._merge_calc_buffs(a, b)
	_ok("合併：同名 id pct 相加（10 + 5 = 15）",
		is_equal_approx(float(merged["swift"]["pct"]["move_speed"]), 15.0))
	_ok("合併：不同 id 保留（other.dodge = 3）",
		is_equal_approx(float(merged["other"]["pct"]["dodge"]), 3.0))
	_ok("合併：不污染入參（a 仍為 10）",
		is_equal_approx(float(a["swift"]["pct"]["move_speed"]), 10.0))


# =============================================================================
# D. 敵人消費（3-B3）
# =============================================================================

func _test_enemy_consumption() -> void:
	print("--- D. 敵人消費（3-B3）---")
	var e := _spawn_enemy("skeleton_warrior", Vector2(120.0, 0.0))
	await _step(0.1)
	_ok("敵人已掛 BuffComponent", e.get_buff_component() != null)
	var armor0 := e.get_armor()
	var speed0 := e._move_speed()
	_ok("敵人基礎護甲 > 0（%s）" % armor0, armor0 > 0.0)

	e.get_buff_component().add_buff("enemy_armor_reduction", 50.0, 30.0, "sui_jia")
	_ok("減甲 50%% ⇒ 護甲減半（%s → %s）" % [armor0, e.get_armor()],
		is_equal_approx(e.get_armor(), armor0 * 0.5))

	e.get_buff_component().add_buff("move_speed", -30.0, 30.0, "kuang_lan")
	_ok("減速 30%% ⇒ 移速 ×0.7（%s → %s）" % [speed0, e._move_speed()],
		is_equal_approx(e._move_speed(), speed0 * 0.7))

	e.get_buff_component().clear()
	_ok("清空後恢復基礎值",
		is_equal_approx(e.get_armor(), armor0) and is_equal_approx(e._move_speed(), speed0))
	e.queue_free()


# =============================================================================
# E. 傳奇總線 4 類執行器（3-B1/B2/B3）
# =============================================================================

func _test_legendary_executors() -> void:
	print("--- E. 傳奇總線 4 類執行器 ---")
	var bc := _player.get_buff_component()
	bc.clear()

	# ① buff_stat（self）
	_bus._execute({ "effect_id": "ying_zhe_zhi_hun_jie", "name": "影者之魂戒",
		"result": { "type": "buff_stat", "stat": "all_damage", "value": 12.0,
			"duration": 6.0, "target": "self", "max_stacks": 1 } }, {})
	_ok("buff_stat(self) ⇒ 玩家獲得 all_damage 12",
		is_equal_approx(bc.get_stat_bonus("all_damage"), 12.0))

	# ② buff_stat（enemy）
	var e := _spawn_enemy("skeleton_warrior", Vector2(160.0, 0.0))
	await _step(0.1)
	var armor0 := e.get_armor()
	_bus._execute({ "effect_id": "sui_jia_po_jun_quan", "name": "碎甲·破军拳",
		"result": { "type": "buff_stat", "stat": "enemy_armor_reduction", "value": 10.0,
			"duration": 3.0, "target": "enemy", "max_stacks": 1 } },
		{ "target": e })
	_ok("buff_stat(target=enemy) ⇒ 目標減甲 10%%（%s → %s）" % [armor0, e.get_armor()],
		is_equal_approx(e.get_armor(), armor0 * 0.9))

	# ③ ms_boost
	_bus._execute({ "effect_id": "xun_jie_ji_xing_tui", "name": "迅捷·疾行腿",
		"result": { "type": "ms_boost", "value": 15.0, "duration": 3.0,
			"element_attach": false } }, {})
	_ok("ms_boost ⇒ 玩家移速乘區 1.15",
		is_equal_approx(_player.health.get_move_speed_factor(), 1.15))

	# ④ damage_reduction
	_bus._execute({ "effect_id": "tie_bi_zhong_zhuang_tui", "name": "铁壁·重装腿",
		"result": { "type": "damage_reduction", "value": 5.0, "duration": 3.0 } }, {})
	_ok("damage_reduction ⇒ 玩家獲得 5% 減傷",
		is_equal_approx(bc.get_stat_bonus("damage_reduction"), 5.0))

	# ⑤ summon（已定義 creature）
	_ok("Summon.DEFS 含 ghost / echo_copy",
		Summon.DEFS.has("ghost") and Summon.DEFS.has("echo_copy"))
	_bus._execute({ "effect_id": "an_shi_zhou_yin_shu", "name": "暗蚀·咒印书",
		"result": { "type": "summon", "creature": "ghost", "count": 1,
			"duration": 8.0, "damage_pct": 0.0 } }, {})
	await _step(0.05)
	_ok("summon(ghost) ⇒ 場上 1 隻幽魂（%d）" % _bus._count_summons("ghost"),
		_bus._count_summons("ghost") == 1)

	# ⑥ summon 守門：未定義 creature 不得生成（也不得靜默變成靈狼）
	_bus._execute({ "effect_id": "x", "name": "未定義召喚",
		"result": { "type": "summon", "creature": "no_such_creature", "count": 1,
			"duration": 8.0 } }, {})
	await _step(0.05)
	_ok("未定義 creature ⇒ 不生成任何召喚物（summons 組 %d）" % get_tree().get_nodes_in_group(&"summons").size(),
		get_tree().get_nodes_in_group(&"summons").size() == 1)

	# ⑦ 四類都不再落 `_warn_once`
	var warned: Array[String] = []
	for t in ["buff_stat", "ms_boost", "damage_reduction", "summon"]:
		if _bus._warned_types.has(t):
			warned.append(t)
	_ok("4 類執行器均已實現（未實現標記 %d 個）" % warned.size(), warned.is_empty())

	# ⑧ 第二期 16 條清單與數據文件一致
	var ids: Array[String] = []
	for eid in WIRED_EFFECT_IDS:
		if ConfigLoader.legendary_effects.has(eid):
			ids.append(eid)
	_ok("第二期 16 條特效全部存在於數據（缺失 %d）" % (WIRED_EFFECT_IDS.size() - ids.size()),
		ids.size() == WIRED_EFFECT_IDS.size() and WIRED_EFFECT_IDS.size() == 16)

	for s in get_tree().get_nodes_in_group(&"summons"):
		s.queue_free()
	e.queue_free()
	bc.clear()


# =============================================================================
# F. BUFF 型技能（3-B1）
# =============================================================================

func _test_buff_skills() -> void:
	print("--- F. BUFF 型技能（3-B1）---")
	# ① 定義表與技能數據一一對應
	var wanted: Array[String] = []
	for sid in ConfigLoader.skills:
		var sk: SkillData = ConfigLoader.skills[sid]
		if sk != null and sk.type == SkillData.SkillType.BUFF and not sk.buff_id.is_empty():
			wanted.append(sk.buff_id)
	_ok("skills.json 的 BUFF 技能 = 7 條（實際 %d）" % wanted.size(), wanted.size() == 7)
	var missing: Array[String] = []
	for bid in wanted:
		if not GameConstants.BUFF_DEFS.has(bid):
			missing.append(bid)
	_ok("BUFF_DEFS 覆蓋全部 buff_id（缺失 %d）" % missing.size(), missing.is_empty())
	for m in missing:
		_info("缺失: %s" % m)
	var extra: Array[String] = []
	for bid in GameConstants.BUFF_DEFS:
		if not (String(bid) in wanted):
			extra.append(String(bid))
	_ok("BUFF_DEFS 無多餘條目（多餘 %d）" % extra.size(), extra.is_empty())

	# ② 施放真的生效（走完整 try_cast：扣藍 + 冷卻 + 分派）
	var bc := _player.get_buff_component()
	bc.clear()
	_skills._skills["warcry"] = ConfigLoader.get_skill("warcry")
	_skills._cooldowns["warcry"] = 0.0
	_ok("施放戰吼成功", _skills.try_cast("warcry"))
	_ok("戰吼 ⇒ 玩家獲得 pct_attack 25",
		is_equal_approx(bc.get_stat_bonus("pct_attack"), 25.0))
	var stats := StatCalculator.calculate(1, [], bc.to_calculator_buffs())
	_ok("pct_attack 25 真的放大攻擊（%.2f > 裸裝 12）" % float(stats.get("attack", 0.0)),
		float(stats.get("attack", 0.0)) > 12.0)
	bc.clear()

	# ③ 疾風步：移速走健康側鍵、閃避走計算器
	_skills._skills["wind_walk"] = ConfigLoader.get_skill("wind_walk")
	_skills._cooldowns["wind_walk"] = 0.0
	_player.get_mana_pool().set_current(100.0)
	_ok("施放疾風步成功", _skills.try_cast("wind_walk"))
	_ok("疾風步 ⇒ 移速乘區 1.4",
		is_equal_approx(_player.health.get_move_speed_factor(), 1.4))
	_ok("疾風步 ⇒ 閃避 +25",
		is_equal_approx(bc.get_stat_bonus("dodge"), 25.0))
	bc.clear()

	# ④ 鐵壁：限時護盾（按最大生命 %）
	_skills._skills["iron_bulwark"] = ConfigLoader.get_skill("iron_bulwark")
	_skills._cooldowns["iron_bulwark"] = 0.0
	_player.get_mana_pool().set_current(100.0)
	_player.health.shield = 0.0
	_ok("施放鐵壁成功", _skills.try_cast("iron_bulwark"))
	var want_shield := _player.health.get_max_hp() * 0.35
	_ok("鐵壁 ⇒ 護盾 = 35%% 最大生命（%.2f / %.2f）" % [_player.get_shield(), want_shield],
		is_equal_approx(_player.get_shield(), want_shield))

	# ⑤ 護盾到期語義（用獨立組件，避免與上面 8 秒盾的到期時刻互相干擾）
	var hc := HealthComponent.new()
	add_child(hc)
	hc.max_hp_override = 100.0
	hc.grant_shield(50.0, 0.2)
	_ok("限時盾授予後 = 50", is_equal_approx(hc.get_shield(), 50.0))
	await _step(0.5)
	_ok("限時盾到期清零（%.2f）" % hc.get_shield(), is_equal_approx(hc.get_shield(), 0.0))
	hc.grant_shield(30.0)
	await _step(0.3)
	_ok("缺省 duration=0 ⇒ 永久盾（%.2f）" % hc.get_shield(),
		is_equal_approx(hc.get_shield(), 30.0))
	hc.queue_free()
	_player.health.shield = 0.0
	_player.health._shield_expire_at = 0.0


# =============================================================================
# G. HUD 增益欄（3-B4）
# =============================================================================

func _test_hud() -> void:
	print("--- G. HUD 增益欄（3-B4）---")
	var bar := BuffBarUI.new()
	bar.source = _player
	add_child(bar)
	await _step(0.05)
	var bc := _player.get_buff_component()
	bc.clear()
	_ok("無增益時 HUD 讀到 0 條", bar.active_buffs().is_empty())
	bc.add_buff_key("all_damage", 12.0, 6.0, "hud_a")
	bc.add_buff("move_speed", 15.0, 6.0, "hud_b")
	await _step(0.05)
	var entries := bar.active_buffs()
	_ok("HUD 讀到 2 條激活增益（實際 %d）" % entries.size(), entries.size() == 2)
	_ok("HUD 條目帶 key / remain / duration",
		entries.size() == 2 and entries[0].has("key") and entries[0].has("remain")
		and float(entries[0]["duration"]) > 0.0)
	_ok("HUD 槽位上限 = 6", bar.get_slot_count() == 6)
	bc.clear()
	await _step(0.05)
	_ok("增益清空後 HUD 同步為 0 條", bar.active_buffs().is_empty())
	bar.queue_free()


func _finish() -> void:
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
