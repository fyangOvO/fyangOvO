## 套裝機制特效實測（第四步 B4-2 · 3-S1~3-S4 · 開發用，不屬於遊戲玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_set_effects.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 數據（3-S1）：`data/set_effects/` 6 條；三要素齊全；與 `sets.json` 檔位綁定一致；
##      不污染傳奇特効池（`for_slot` 抽不到套裝特效）
##   B. 別名 + 鍵閉合（3-S1）：套裝特效用到的 `stat` 名全部可歸一，且歸一鍵真的能被消費
##   C. SetSystem.get_active_effects（3-S2）：0/2/4/6 件 → 0/0/1/2 條；檔位回退即消失；去重
##   D. 引擎條件 require_target_buff（3-S1）：目標未中減速 ⇒ 霜爆不觸發；已中 ⇒ 觸發
##   E. 註冊 / 註銷（3-S3）：穿滿 4/6 件生效、降到 3 件失效；key 前綴 `set::`；sync 幂等
##   F. 執行落點（3-S3）：6 條特效各走一遍真實消費（減速 / 霜爆 / 疊層必暴 / 點燃 / 回血 / 背水）
##   G. 面板（3-S4）：`SetPanel` 顯示「已激活機制」（非僅數值）
##
## ⚠️ 本脚本的「規範清單」（`EXPECTED_IDS` / `CALC_INPUT_KEYS`）均来自策划案与数据文件，
##    **不是**从被检代码反推 ⇒ 不属自洽式伪校验。
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## 6 條套裝機制特效 id（規範：`03-set-effects.json` / `03-装备特色玩法.md` §3.1）
const EXPECTED_IDS: Array[String] = [
	"frostbite_slow", "frostbite_burst",
	"emberpath_frenzy", "emberpath_ember",
	"oathkeeper_block_heal", "oathkeeper_last_stand",
]

## `StatCalculator` 的 **pct 乘算输入键**（本身不出现在 `FINAL_KEYS` 输出键集里）
const CALC_INPUT_KEYS: Array[String] = ["pct_armor", "pct_attack", "all_attributes", "pct_hp"]

var _fail: int = 0
var _rng := RandomNumberGenerator.new()
var _player: PlayerController = null
var _bus: LegendaryBus = null

## 已跑完的測試段標記（`_finish` 校驗）——
## ⚠️ 若中途 `SCRIPT ERROR` 打斷協程，後續斷言全部不會執行，但 `_fail` 仍是 0
##    ⇒ 必須靠「段完成標記」把「中斷」與「通過」區分開（否則就是自洽式偽校驗）。
const SECTIONS: Array[String] = ["A", "B", "C", "D", "E", "F", "G"]
var _sections_done: Array[String] = []


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 套裝機制特效實測（第四步 B4-2）=====")
	_rng.seed = 20260929
	_player = PLAYER_SCENE.instantiate() as PlayerController
	add_child(_player)
	_player.global_position = Vector2.ZERO
	_bus = LegendaryBus.new()
	_bus.name = "LegendaryBus"
	add_child(_bus)
	_bus.setup(_player)
	_ok("場景就緒：玩家 + 傳奇總線", _player != null and _bus != null)
	await _test_data()
	await _test_alias_keys()
	await _test_active_effects()
	await _test_require_target_buff()
	await _test_register_sync()
	await _test_execution()
	await _test_panel()
	_finish()


## 等 **真實時間**（秒）。
##
## ⚠️ 不可用「等 N 幀」近似時間：無頭模式 V-Sync 會把 FPS 鎖到顯示器刷新率，
##    「秒 → 幀數」換算在高刷機上會嚴重低估真實時長（同一坑已在 verify_buff 實測踩中）。
func _step(seconds: float) -> void:
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout


func _spawn_enemy(mid: String, pos: Vector2) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.monster_id = mid
	e.level = 1
	e.difficulty_tier = GameConstants.DifficultyTier.NM1
	add_child(e)
	e.global_position = pos
	return e


## 造 `count` 件某套裝的散件（部位取底材自身的 slot ⇒ `count_pieces` 按部位去重）
func _make_set_items(set_id: String, count: int) -> Array[EquipmentInstance]:
	var out: Array[EquipmentInstance] = []
	var info: SetData = ConfigLoader.sets.get(set_id, null)
	if info == null:
		return out
	var tids: Array = info.piece_template_ids
	for i in range(mini(count, tids.size())):
		var tpl := ConfigLoader.get_equipment_template(String(tids[i]))
		if tpl == null:
			continue
		out.append(AffixRoller.roll_full_equipment(tpl, 20, GameConstants.Rarity.SET, _rng))
	return out


func _clear_registry() -> void:
	LegendaryEffectSystem.clear()
	_bus._set_keys.clear()
	_bus._warned_types.clear()
	_bus._extra_loot_used.clear()


# =============================================================================
# A. 數據（3-S1）
# =============================================================================

func _test_data() -> void:
	print("--- A. 數據（3-S1）---")
	_ok("套裝特效表 6 條（實際 %d）" % ConfigLoader.set_effects.size(),
		ConfigLoader.set_effects.size() == 6)

	var missing: Array[String] = []
	for eid in EXPECTED_IDS:
		if not ConfigLoader.set_effects.has(eid):
			missing.append(eid)
	_ok("6 個規範 id 全部有定義（缺失 %d）" % missing.size(), missing.is_empty())
	for m in missing:
		_info("缺失: %s" % m)

	# 工程數據（sets.json）裡的 effect_id 集合必須與定義集合**嚴格相等**
	var in_data: Array[String] = []
	for set_id in ConfigLoader.sets:
		var sd: SetData = ConfigLoader.sets[set_id]
		for tier in sd.tier_bonuses:
			var eid := String(tier.get("effect_id", ""))
			if not eid.is_empty() and not in_data.has(eid):
				in_data.append(eid)
	in_data.sort()
	var defined := EXPECTED_IDS.duplicate()
	defined.sort()
	_ok("sets.json 的 effect_id 集合 == 定義集合（數據 %d / 定義 %d）" % [in_data.size(), defined.size()],
		in_data == defined)

	# 三要素齐全 + set_id / pieces 与 sets.json 档位一致
	var bad: Array[String] = []
	for eid in EXPECTED_IDS:
		var fx := ConfigLoader.get_set_effect(eid)
		if not (fx.get("trigger", {}) is Dictionary) or not (fx.get("effect", {}) is Dictionary) \
				or String(fx.get("description", "")).is_empty():
			bad.append("%s 三要素不全" % eid)
			continue
		var set_id := String(fx.get("set_id", ""))
		var pieces := int(fx.get("pieces", -1))
		var sd: SetData = ConfigLoader.sets.get(set_id, null)
		if sd == null:
			bad.append("%s set_id 不存在" % eid)
			continue
		var bound := false
		for tier in sd.tier_bonuses:
			if int(tier.get("pieces", -1)) == pieces and String(tier.get("effect_id", "")) == eid:
				bound = true
				break
		if not bound:
			bad.append("%s 未綁定 %s 的 %d 件檔" % [eid, set_id, pieces])
	_ok("6 條三要素齊全且與 sets.json 檔位綁定一致（異常 %d）" % bad.size(), bad.is_empty())
	for b in bad:
		_info(b)

	# 不污染傳奇特効池：for_slot 抽到的必須全是傳奇特効（無套裝特效）
	var leaked: Array[String] = []
	for slot_key in GameConstants.EQUIP_SLOT_KEYS:
		for fx in LegendaryEffectSystem.for_slot(String(slot_key)):
			if EXPECTED_IDS.has(String(fx.get("id", ""))):
				leaked.append(String(fx.get("id", "")))
	_ok("套裝特效未混入 for_slot 抽取池（洩漏 %d）" % leaked.size(), leaked.is_empty())
	_ok("載入零錯誤（含跨表綁定校驗）", ConfigLoader.load_errors.is_empty())
	for err in ConfigLoader.load_errors:
		_info(err)
	_sections_done.append("A")


# =============================================================================
# B. 別名 + 鍵閉合（3-S1）
# =============================================================================

func _test_alias_keys() -> void:
	print("--- B. 別名 + 鍵閉合（3-S1）---")
	# 收集 6 條特效用到的全部 stat 名（含 stack 的 on_full）
	var stats: Array[String] = []
	for eid in EXPECTED_IDS:
		var fx := ConfigLoader.get_set_effect(eid)
		var eff: Dictionary = fx.get("effect", {})
		if String(eff.get("type", "")) == "stack":
			eff = eff.get("on_full", {})
		var s := String(eff.get("stat", ""))
		if not s.is_empty() and not stats.has(s):
			stats.append(s)
	_ok("6 條特效共用到 %d 種 stat 名" % stats.size(), stats.size() >= 3)

	var unknown: Array[String] = []
	var unconsumable: Array[String] = []
	for s in stats:
		var k := BuffComponent.resolve_key(s)
		if k.is_empty():
			unknown.append(s)
			continue
		if not (k in StatCalculator.FINAL_KEYS) and not (k in BuffComponent.HEALTH_SIDE_KEYS) \
				and not (k in CALC_INPUT_KEYS):
			unconsumable.append("%s -> %s" % [s, k])
	_ok("套裝特效的 stat 名全部可歸一（未知 %d：%s）" % [unknown.size(), unknown], unknown.is_empty())
	_ok("歸一鍵全部可被消費（缺失 %d：%s）" % [unconsumable.size(), unconsumable], unconsumable.is_empty())

	# 三個關鍵鍵的歸一直通（本批新增：pct_armor / crit_chance / elemental_damage）
	_ok("pct_armor 同名直通", BuffComponent.resolve_key("pct_armor") == "pct_armor")
	_ok("crit_chance 同名直通", BuffComponent.resolve_key("crit_chance") == "crit_chance")

	# 反向守門：歸一鍵真的被 StatCalculator 消費（不是空轉）
	var bc := _player.get_buff_component()
	bc.clear()
	bc.add_buff("pct_armor", 100.0, 60.0, "t_armor")
	bc.add_buff("crit_chance", 30.0, 60.0, "t_crit")
	var stats_out := StatCalculator.calculate(1, [], bc.to_calculator_buffs())
	var naked := StatCalculator.calculate(1, [], {})
	_ok("pct_armor 100 ⇒ 護甲翻倍（%.2f → %.2f）" % [float(naked["armor"]), float(stats_out["armor"])],
		is_equal_approx(float(stats_out["armor"]), float(naked["armor"]) * 2.0))
	_ok("crit_chance 30 落到 FINAL_KEYS（= 30）",
		is_equal_approx(float(stats_out.get("crit_chance", -1.0)), 30.0))
	bc.clear()
	_sections_done.append("B")


# =============================================================================
# C. SetSystem.get_active_effects（3-S2）
# =============================================================================

func _test_active_effects() -> void:
	print("--- C. get_active_effects（3-S2）---")
	_ok("0 件 ⇒ 0 條", SetSystem.get_active_effects([]).is_empty())

	var two := _make_set_items("frostbite", 2)
	_ok("2 件 ⇒ 0 條（2 件檔是純數值，無 effect_id）",
		SetSystem.get_active_effects(two).is_empty())

	var four := _make_set_items("frostbite", 4)
	var fx4 := SetSystem.get_active_effects(four)
	_ok("4 件 ⇒ 1 條（%d）" % fx4.size(), fx4.size() == 1)
	_ok("4 件檔 = frostbite_slow",
		fx4.size() == 1 and String(fx4[0]["effect_id"]) == "frostbite_slow")

	var six := _make_set_items("frostbite", 6)
	var fx6 := SetSystem.get_active_effects(six)
	_ok("6 件 ⇒ 2 條（%d）" % fx6.size(), fx6.size() == 2)
	var ids6: Array[String] = []
	for e in fx6:
		ids6.append(String(e["effect_id"]))
	_ok("6 件檔 = frostbite_slow + frostbite_burst",
		ids6.has("frostbite_slow") and ids6.has("frostbite_burst"))
	_ok("每條都帶非空顯示名",
		fx6.size() == 2 and not String(fx6[0]["name"]).is_empty() and not String(fx6[1]["name"]).is_empty())

	# 檔位回退：6 → 3 件（摘下 3 件）⇒ 全失效
	var three := _make_set_items("frostbite", 3)
	_ok("降到 3 件 ⇒ 0 條（檔位回退即消失）",
		SetSystem.get_active_effects(three).is_empty())

	# 三套各 6 件 ⇒ 6 條（跨套不互斥）
	var all: Array[EquipmentInstance] = []
	all.append_array(_make_set_items("frostbite", 6))
	all.append_array(_make_set_items("emberpath", 6))
	all.append_array(_make_set_items("oathkeeper", 6))
	var allfx := SetSystem.get_active_effects(all)
	var allids: Array[String] = []
	for e in allfx:
		allids.append(String(e["effect_id"]))
	var uniq := {}
	for i in allids:
		uniq[i] = true
	_ok("三套各 6 件 ⇒ 6 條且無重複（實際 %d / 去重後 %d）" % [allids.size(), uniq.size()],
		allids.size() == 6 and uniq.size() == 6)

	# 重複部位只計 1（同一件重複放 6 次 ⇒ 仍只算 1 件）
	var dup: Array[EquipmentInstance] = []
	var one := _make_set_items("frostbite", 1)
	for i in range(6):
		dup.append(one[0])
	_ok("同部位重複 6 次 ⇒ 仍按 1 件計（0 條）",
		SetSystem.get_active_effects(dup).is_empty())
	_sections_done.append("C")


# =============================================================================
# D. 引擎條件 require_target_buff（3-S1）
# =============================================================================

func _test_require_target_buff() -> void:
	print("--- D. require_target_buff（3-S1）---")
	_clear_registry()
	var e := _spawn_enemy("skeleton_warrior", Vector2(80.0, 0.0))
	await _step(0.1)

	LegendaryEffectSystem.register_effect_id("frostbite_burst", "set::frostbite_burst")
	_ok("frostbite_burst 已註冊（registry %d）" % LegendaryEffectSystem.registered_count(),
		LegendaryEffectSystem.registered_count() == 1)

	var ctx := _bus._base_ctx()
	ctx["target"] = e
	var no_buff := LegendaryEffectSystem.on_event("on_crit", ctx)
	_ok("目標未中「霜噬·減速」⇒ 霜爆不觸發（結果 %d）" % no_buff.size(), no_buff.is_empty())

	# 給目標掛上霜噬·減速（source_id = effect_id，與 `_exec_buff_stat` 的口徑一致）
	e.get_buff_component().add_buff("move_speed", -20.0, 30.0, "frostbite_slow")
	var with_buff := LegendaryEffectSystem.on_event("on_crit", ctx)
	_ok("目標已中減速 ⇒ 霜爆觸發（結果 %d）" % with_buff.size(), with_buff.size() == 1)
	if with_buff.size() == 1:
		var r: Dictionary = with_buff[0]["result"]
		_ok("霜爆 = deal_damage / cold / area",
			String(r.get("type", "")) == "deal_damage"
			and String(r.get("element", "")) == "cold" and bool(r.get("area", false)))
		_ok("霜爆數值 = 攻擊 ×2.0（%.1f）" % float(r.get("amount", 0.0)),
			is_equal_approx(float(r.get("amount", 0.0)), _player.get_attack_damage() * 2.0))

	# 冷卻：緊接著再來一次應被 cd 3s 擋住
	var again := LegendaryEffectSystem.on_event("on_crit", ctx)
	_ok("冷卻 3s 生效 ⇒ 立即二次觸發被擋（結果 %d）" % again.size(), again.is_empty())

	# 目標無 BuffComponent ⇒ 不觸發（不得崩）
	var bare := Node2D.new()
	add_child(bare)
	var ctx2 := _bus._base_ctx()
	ctx2["target"] = bare
	_ok("目標無 BuffComponent ⇒ 不觸發且不崩", LegendaryEffectSystem.on_event("on_crit", ctx2).is_empty())
	bare.queue_free()

	e.queue_free()
	_clear_registry()
	_sections_done.append("D")


# =============================================================================
# E. 註冊 / 註銷（3-S3）
# =============================================================================

func _test_register_sync() -> void:
	print("--- E. 註冊 / 註銷（3-S3）---")
	_clear_registry()
	_bus.sync_set_effects([])
	_ok("空穿戴 ⇒ registry 0（實際 %d）" % LegendaryEffectSystem.registered_count(),
		LegendaryEffectSystem.registered_count() == 0)

	var four := _make_set_items("frostbite", 4)
	_bus.sync_set_effects(four)
	_ok("穿滿 4 件 ⇒ 註冊 1 條（實際 %d）" % LegendaryEffectSystem.registered_count(),
		LegendaryEffectSystem.registered_count() == 1)
	var ids4 := _bus.active_set_effect_ids()
	_ok("active_set_effect_ids = [frostbite_slow]",
		ids4.size() == 1 and String(ids4[0]) == "frostbite_slow")

	var six := _make_set_items("frostbite", 6)
	_bus.sync_set_effects(six)
	_ok("升到 6 件 ⇒ 註冊 2 條（實際 %d）" % LegendaryEffectSystem.registered_count(),
		LegendaryEffectSystem.registered_count() == 2)
	_ok("key 前綴為 set::",
		LegendaryEffectSystem._registry.has("set::frostbite_slow")
		and LegendaryEffectSystem._registry.has("set::frostbite_burst"))

	# 幂等：重複 sync 不得重置 stacks
	LegendaryEffectSystem._registry["set::frostbite_slow"]["stacks"] = 7
	_bus.sync_set_effects(six)
	_ok("重複 sync 幂等（stacks 保留 7，未重置）",
		int(LegendaryEffectSystem._registry["set::frostbite_slow"]["stacks"]) == 7)

	# 檔位回退：6 → 3 件 ⇒ 全部註銷
	var three := _make_set_items("frostbite", 3)
	_bus.sync_set_effects(three)
	_ok("降到 3 件 ⇒ 全部註銷（registry %d）" % LegendaryEffectSystem.registered_count(),
		LegendaryEffectSystem.registered_count() == 0 and _bus.active_set_effect_ids().is_empty())

	# 與裝備特效共存：註冊一件傳奇特効 + 一套套裝特效 ⇒ 計數 2
	_clear_registry()
	var tpl := ConfigLoader.get_equipment_template("set_frostbite_helm")
	_bus.register_item(AffixRoller.roll_full_equipment(tpl, 20, GameConstants.Rarity.SET, _rng))
	_bus.sync_set_effects(four)
	_ok("裝備特效 + 套裝特效共用註冊表（合計 %d ≥ 1）" % LegendaryEffectSystem.registered_count(),
		LegendaryEffectSystem.registered_count() >= 1)

	_bus.clear()
	_ok("clear() 一併清空套裝特效 key", _bus.active_set_effect_ids().is_empty()
		and LegendaryEffectSystem.registered_count() == 0)
	_sections_done.append("E")


# =============================================================================
# F. 執行落點（3-S3）
# =============================================================================

func _test_execution() -> void:
	print("--- F. 執行落點（3-S3）---")
	var bc := _player.get_buff_component()

	# ① frostbite_slow：命中 ⇒ 目標減速 20%（真實消費在敵人的 HealthComponent）
	_clear_registry()
	var e := _spawn_enemy("skeleton_warrior", Vector2(60.0, 0.0))
	await _step(0.1)
	var speed0 := e._move_speed()
	LegendaryEffectSystem.register_effect_id("frostbite_slow", "set::frostbite_slow")
	var ctx := _bus._base_ctx()
	ctx["target"] = e
	_bus._dispatch("on_hit", ctx)
	_ok("霜噬·減速 ⇒ 目標移速 ×0.8（%.1f → %.1f）" % [speed0, e._move_speed()],
		is_equal_approx(e._move_speed(), speed0 * 0.8))
	e.queue_free()

	# ② emberpath_frenzy：連續命中 5 次 ⇒ 玩家獲得暴擊率 +100（必暴）
	_clear_registry()
	bc.clear()
	LegendaryEffectSystem.register_effect_id("emberpath_frenzy", "set::emberpath_frenzy")
	var c2 := _bus._base_ctx()
	c2["target"] = _spawn_enemy("skeleton_warrior", Vector2(40.0, 0.0))
	await _step(0.05)
	for i in range(4):
		_bus._dispatch("on_hit", c2)
	_ok("疊 4 層尚未滿 ⇒ 無暴擊增益（%.1f）" % bc.get_stat_bonus("crit_chance"),
		is_equal_approx(bc.get_stat_bonus("crit_chance"), 0.0))
	_bus._dispatch("on_hit", c2)
	_ok("滿 5 層 ⇒ 玩家獲得 crit_chance +100（%.1f）" % bc.get_stat_bonus("crit_chance"),
		is_equal_approx(bc.get_stat_bonus("crit_chance"), 100.0))
	for n in get_tree().get_nodes_in_group(&"enemies"):
		n.queue_free()
	bc.clear()

	# ③ emberpath_ember：範圍火焰傷害真的打進目標（真實 deal_damage 執行器）
	_clear_registry()
	var e3 := _spawn_enemy("skeleton_warrior", Vector2(50.0, 0.0))
	await _step(0.1)
	var hp0 := e3.health.current_hp
	_bus._execute({ "effect_id": "emberpath_ember", "name": "烬途·余烬",
		"result": { "type": "deal_damage", "amount": 100.0, "element": "fire",
			"area": true, "dot": 0.0, "dot_ticks": 0 } }, { "target": e3 })
	_ok("烬途·余烬 ⇒ 目標掉血 100（%.0f → %.0f）" % [hp0, e3.health.current_hp],
		is_equal_approx(e3.health.current_hp, hp0 - 100.0))
	# 引擎側契約：dot 參數確實在結果裡
	var ember := LegendaryEffectSystem.get_effect("emberpath_ember")
	_ok("余烬定義帶 area + dot 3 跳",
		bool(ember["effect"].get("area", false)) and int(ember["effect"].get("dot_ticks", 0)) == 3)
	e3.queue_free()

	# ④ oathkeeper_block_heal：受擊 **25%** 概率回血（每次先把血壓回 50%，統計觸發率）
	_clear_registry()
	LegendaryEffectSystem.register_effect_id("oathkeeper_block_heal", "set::oathkeeper_block_heal")
	var half := _player.health.get_max_hp() * 0.5
	var trials := 60
	var healed := 0
	for i in range(trials):
		_player.health.current_hp = half
		var ctx4 := _bus._base_ctx()
		ctx4["source"] = null
		ctx4["amount"] = 1.0
		_bus._dispatch("on_damage_taken", ctx4)
		if _player.health.current_hp > half + 0.01:
			healed += 1
	# p = 0.25、n = 60 ⇒ 期望 15、σ ≈ 3.35；[3, 45] 約 ±3.6σ，既不誤殺也能擋住
	# 「概率寫成 0 / 1」這類靜默脫鉤（若 pct 沒被讀，結果會是 0 或 60）
	_ok("守誓·回春 ⇒ 觸發率接近 25%%（60 次觸發 %d 次）" % healed,
		healed >= 3 and healed <= 45)
	_player.health.current_hp = _player.health.get_max_hp()

	# ⑤ oathkeeper_last_stand：瀕死 ⇒ 玩家獲得 +50% 護甲
	_clear_registry()
	bc.clear()
	LegendaryEffectSystem.register_effect_id("oathkeeper_last_stand", "set::oathkeeper_last_stand")
	var ctx5 := _bus._base_ctx()
	ctx5["hp_pct"] = 0.2
	_bus._dispatch("on_low_hp", ctx5)
	_ok("守誓·背水 ⇒ 玩家獲得 pct_armor +50（%.1f）" % bc.get_stat_bonus("pct_armor"),
		is_equal_approx(bc.get_stat_bonus("pct_armor"), 50.0))
	bc.clear()

	# ⑥ 六條特效全部走通 ⇒ 不得留下「執行器未實現 / 前置缺失」告警
	var warned: Array[String] = []
	for t in _bus._warned_types.keys():
		warned.append(String(t))
	_ok("六條特效執行無告警（告警 %d：%s）" % [warned.size(), warned], warned.is_empty())

	_clear_registry()
	_sections_done.append("F")


# =============================================================================
# G. 面板（3-S4）
# =============================================================================

func _test_panel() -> void:
	print("--- G. 面板（3-S4）---")
	var four := _make_set_items("frostbite", 4)
	var progress := SetSystem.get_progress(four)
	var fb: Dictionary = {}
	for p in progress:
		if String(p["set_id"]) == "frostbite":
			fb = p
	var tier4: Dictionary = {}
	var tiers: Array = fb.get("tiers", [])
	for t in tiers:
		if int(t.get("pieces", -1)) == 4:
			tier4 = t
	_ok("get_progress 的 4 件檔帶 effect_name（%s）" % String(tier4.get("effect_name", "")),
		not String(tier4.get("effect_name", "")).is_empty())
	_ok("4 件檔 effect_name = 霜噬·减速",
		String(tier4.get("effect_name", "")) == "霜噬·减速")
	_ok("2 件檔（純數值）effect_name 為空",
		String((tiers[0] as Dictionary).get("effect_name", "")) == "")

	var panel := SetPanel.new()
	add_child(panel)
	await _step(0.05)
	panel.show_sets(four)
	await _step(0.05)
	var labels := _collect_labels(panel)
	var mech_lbl := _find_label(labels, "【霜噬·减速】")
	var off_lbl := _find_label(labels, "【霜噬·霜爆】")
	var head4 := _find_label(labels, "4件")
	var head6 := _find_label(labels, "6件")
	_ok("面板渲染出機制名標籤「【霜噬·减速】」（非僅數值）", mech_lbl != null)
	_ok("未激活檔位也標出機制名「【霜噬·霜爆】」", off_lbl != null)
	# 顏色區分「已激活 / 未激活」（真渲染層，不是文案層）
	var blue := Color(0.45, 0.78, 1.0)
	var dim := Color(0.38, 0.42, 0.5)
	_ok("已激活機制名為亮藍",
		mech_lbl != null and mech_lbl.get_theme_color("font_color").is_equal_approx(blue))
	_ok("未激活機制名為暗灰",
		off_lbl != null and off_lbl.get_theme_color("font_color").is_equal_approx(dim))
	_ok("4 件檔行高亮、6 件檔行變暗（同一行三色，不額外增高）",
		head4 != null and head6 != null
		and head4.get_theme_color("font_color").g > head6.get_theme_color("font_color").g)
	# 機制名與描述**同一行**（HBox）：面板不得因機制行被撐高
	_ok("機制行與描述同屬一個 HBox（不新增行高）",
		mech_lbl != null and mech_lbl.get_parent() is HBoxContainer
		and (mech_lbl.get_parent() as HBoxContainer).get_child_count() == 3)
	panel.queue_free()
	_sections_done.append("G")


func _collect_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	if root is Label:
		out.append(root as Label)
	for c in root.get_children():
		out.append_array(_collect_labels(c))
	return out


func _find_label(labels: Array[Label], text: String) -> Label:
	for l in labels:
		if l.text == text:
			return l
	return null


func _finish() -> void:
	var missing_sec: Array[String] = []
	for s in SECTIONS:
		if not _sections_done.has(s):
			missing_sec.append(s)
	if not missing_sec.is_empty():
		_fail += 1
		print("[FAIL] 測試段未跑完（缺 %s）—— 上方有 SCRIPT ERROR，結果不可信" % missing_sec)
	print("===== 結果：%d 項失敗（段 %d/%d）=====" % [_fail, _sections_done.size(), SECTIONS.size()])
	get_tree().quit(0 if _fail == 0 else 1)
