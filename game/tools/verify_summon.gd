## 召喚物系統實測（規格 §12 · 技能體系策劃案第十二章；V10）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_summon.tscn
##   退出碼 0 = 全部通過；1 = 有失敗項
##
## 覆蓋範圍（逐條對照 §12.4 六條接口改動）：
##   A. 基礎：友方語義（summons 組 / 不進 enemies / target_group=enemies）、屬性表、生命週期
##   B. 動態讀取（§12.2 硬需求）：召喚物攻擊 / 生命上限**隨玩家變化**（非快照）
##   C. 誤傷豁免（§12.4#2）：HitQuery 三型判定跳過 summons；玩家索敵不含召喚物
##   D. 不參與掉落（§12.4#3）+ 不觸發玩家死亡（§12.4#4）
##   E. 到期消失（§12.2）：15s 到期 queue_free，**不計死亡**（不發 unit_died）
##   F. 施放分派（§7）：skill_controller 的「summon」type → `Summon.spawn`；
##      同一 id 上限 1 隻（取代）；扣藍 / 冷卻 / 到期消失
extends Node2D

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
var _player: PlayerController = null
var _spawned: Array[Node] = []
var _died_units: Array = []
var _player_died: bool = false


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _approx(a: float, b: float, tol: float = 0.01) -> bool:
	return absf(a - b) <= tol


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 召喚物系統實測（規格 §12）=====")
	_player = get_node_or_null("/root/VerifySummon/Player") as PlayerController
	_ok("場景就緒：玩家已加入 player 組", _player != null and _player.is_in_group(&"player"))
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.player_died.connect(_on_player_died)
	await _test_basic()
	await _test_dynamic_stats()
	await _test_hit_query_exclusion()
	await _test_no_loot_no_player_death()
	await _test_expire()
	await _test_cast_dispatch()
	_finish()


func _on_unit_died(unit: Node, _killer: Node) -> void:
	_died_units.append(unit)


func _on_player_died(_reason: String) -> void:
	_player_died = true


## 等 N 個物理幀
func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 生成召喚物（掛在本測試節點下），並記錄以便清理
func _spawn_summon(id: String, pos: Vector2, owner_ref: Node = null) -> Summon:
	var s := Summon.spawn(self, owner_ref if owner_ref != null else _player, id, pos)
	_spawned.append(s)
	return s


## 生成一隻怪物（spider_cave）作為召喚物的目標 / 誤傷對照
func _spawn_monster(pos: Vector2) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.monster_id = "spider_cave"
	e.level = 1
	e.difficulty_tier = GameConstants.DifficultyTier.NM1
	add_child(e)
	e.global_position = pos
	_spawned.append(e)
	return e


func _clear_spawned() -> void:
	for n in _spawned:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


## `summons` 組中指定 id 的召喚物
func _summons_of_id(id: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group(&"summons"):
		if n != null and is_instance_valid(n) and n.has_method("get_summon_id") \
				and str(n.call("get_summon_id")) == id:
			out.append(n)
	return out


## 清空場上全部召喚物
func _clear_summons() -> void:
	for n in get_tree().get_nodes_in_group(&"summons"):
		if n != null and is_instance_valid(n):
			n.queue_free()


# =============================================================================
# A. 基礎 / 友方語義
# =============================================================================

func _test_basic() -> void:
	print("--- A. 基礎 / 友方語義（§12.1 / §12.4#1/#5）---")
	var wolf := _spawn_summon("summon_spirit_wolf", Vector2(0, 0))
	await _wait_frames(2)
	_ok("召喚物加入 summons 組", wolf.is_in_group(&"summons"))
	_ok("召喚物**不進** enemies 組（玩家技能天然打不到）", not wolf.is_in_group(&"enemies"))
	_ok("is_summon = true", wolf.is_summon)
	_ok("target_group = enemies（打怪）", wolf.target_group == "enemies")
	_ok("合成 MonsterData 就緒", wolf.data != null and wolf.data.id == "summon_spirit_wolf")
	_ok("攻擊間隔 = 1.0s（狼）", _approx(wolf.data.attack_interval, 1.0))
	_ok("攻擊距離 = 25.6px（0.8 格，狼）", _approx(wolf.data.attack_range, 25.6))
	_ok("索敵 = 192px（6 格，狼）", _approx(wolf._aggro_range(), 192.0))
	_ok("存活時間 = 15s", _approx(wolf.get_total_lifetime(), 15.0))
	_ok("HUD 圖標 = skill_icon_spirit_wolf", wolf.get_summon_icon() == "skill_icon_spirit_wolf")
	_ok("get_max_hp() = 實際生命上限（世界血條不誤讀合成 data）",
		_approx(wolf.get_max_hp(), wolf.health.max_hp_override, 0.01))

	# 元素僕從對照
	var ele := _spawn_summon("summon_elemental", Vector2(40, 0))
	await _wait_frames(2)
	_ok("僕從攻擊間隔 = 1.25s", _approx(ele.data.attack_interval, 1.25))
	_ok("僕從攻擊距離 = 128px（4 格）", _approx(ele.data.attack_range, 128.0))
	_ok("僕從索敵 = 160px（5 格）", _approx(ele._aggro_range(), 160.0))
	_ok("僕從濺射 = 24px / 50%", _approx(ele._splash_radius, 24.0) and _approx(ele._splash_ratio, 0.5))
	_ok("僕從 HUD 圖標 = skill_icon_summon_elemental",
		ele.get_summon_icon() == "skill_icon_summon_elemental")
	_clear_spawned()
	await _wait_frames(2)


# =============================================================================
# B. 動態讀取（非快照）
# =============================================================================

func _test_dynamic_stats() -> void:
	print("--- B. 動態讀取玩家屬性（§12.2 硬需求）---")
	# 玩家預設在 (0, 0)：狼放 (500, 0)、僕從放 (520, 0) ⇒ 距玩家 > 各自索敵半徑（192/160），
	# 不進 CHASE / 不觸發狼衝鋒 ⇒ 後續驗移速時 `_charge_timer == 0`，乘區 = 1.0。
	var wolf := _spawn_summon("summon_spirit_wolf", Vector2(500, 0))
	var ele := _spawn_summon("summon_elemental", Vector2(520, 0))
	await _wait_frames(2)

	var p_atk := _player.get_attack_damage()
	var p_max := _player.get_max_hp()
	_info("玩家基準：攻擊 %.2f ／ 最大生命 %.2f" % [p_atk, p_max])
	_ok("狼攻擊 = 玩家攻擊 × 60%", _approx(wolf.get_attack_damage(), p_atk * 0.6))
	_ok("狼生命上限 = 玩家最大生命 × 30%", _approx(wolf.health.max_hp_override, p_max * 0.3, 0.1))
	_ok("僕從攻擊 = 玩家攻擊 × 70%", _approx(ele.get_attack_damage(), p_atk * 0.7))
	_ok("僕從生命上限 = 玩家最大生命 × 40%", _approx(ele.health.max_hp_override, p_max * 0.4, 0.1))
	# 移速 = 玩家移速 × 1.2 / 0.9
	var base := PlayerController.LOCAL_MOVE_SPEED * _player.get_move_speed_multiplier()
	_ok("狼移速 = 玩家移速 × 1.2", _approx(wolf._move_speed(), base * 1.2, 0.5))
	_ok("僕從移速 = 玩家移速 × 0.9", _approx(ele._move_speed(), base * 0.9, 0.5))

	# 改變玩家屬性 → 召喚物**同幀之後**同步（證明非召喚瞬間快照）
	var new_atk := p_atk + 50.0
	var new_max := p_max + 100.0
	_player.apply_combat_stats({"attack": new_atk}, 0)
	_player.health.max_hp_override = new_max
	await _wait_frames(2)
	_info("玩家成長後：攻擊 %.2f ／ 最大生命 %.2f" % [new_atk, new_max])
	_ok("狼攻擊隨玩家動態變強（非快照）", _approx(wolf.get_attack_damage(), new_atk * 0.6, 0.5))
	_ok("狼生命上限隨玩家動態變大（非快照）", _approx(wolf.health.max_hp_override, new_max * 0.3, 0.5))
	_ok("僕從攻擊隨玩家動態變強（非快照）", _approx(ele.get_attack_damage(), new_atk * 0.7, 0.5))

	# 還原（避免污染後續段落）
	_player.clear_combat_stats()
	_player.health.max_hp_override = p_max
	_clear_spawned()
	await _wait_frames(2)


# =============================================================================
# C. 誤傷豁免（§12.4#2）
# =============================================================================

func _test_hit_query_exclusion() -> void:
	print("--- C. 誤傷豁免 / 索敵不含召喚物（§12.4#2）---")
	var origin := Vector2(0, 0)
	var wolf := _spawn_summon("summon_spirit_wolf", Vector2(100, 0))
	var mon := _spawn_monster(Vector2(120, 0))
	# 凍結 AI：幾何斷言用固定座標，避免怪物/召喚物移動導致 flaky
	wolf.set_physics_process(false)
	mon.set_physics_process(false)
	await _wait_frames(2)

	var targets: Array[Node] = [wolf, mon]
	var circ := HitQuery.circle(origin, 300.0, targets)
	_ok("circle：命中怪物、**跳過**召喚物",
		circ.has(mon) and not circ.has(wolf))
	var arc := HitQuery.arc(origin, Vector2.RIGHT, 300.0, 120.0, targets)
	_ok("arc：命中怪物、**跳過**召喚物", arc.has(mon) and not arc.has(wolf))
	var rect := HitQuery.rect(origin, Vector2.RIGHT, 200.0, 300.0, targets)
	_ok("rect：命中怪物、**跳過**召喚物", rect.has(mon) and not rect.has(wolf))
	# 只傳召喚物 → 全空（縱深防禦：不依賴「召喚物不在 enemies 組」這一事實）
	var only: Array[Node] = [wolf]
	_ok("只傳召喚物時 circle 為空", HitQuery.circle(origin, 300.0, only).is_empty())

	# 玩家索敵（enemies 組）不含召喚物
	_player.global_position = Vector2(-40, 0)
	await _wait_frames(2)
	var found := _player.find_targets_in_radius(400.0)
	_ok("玩家範圍索敵不含召喚物（召喚物不在 enemies 組）", not found.has(wolf))
	_ok("玩家範圍索敵能命中怪物", found.has(mon))
	_clear_spawned()
	await _wait_frames(2)


# =============================================================================
# D. 不掉落 + 不觸發玩家死亡
# =============================================================================

func _test_no_loot_no_player_death() -> void:
	print("--- D. 不參與掉落 / 不觸發玩家死亡（§12.4#3/#4）---")
	var wolf := _spawn_summon("summon_spirit_wolf", Vector2(0, 0))
	await _wait_frames(2)
	var loot_before := get_tree().get_nodes_in_group(&"loot_drops").size()
	_player_died = false
	_died_units.clear()

	wolf.take_damage(999999.0, _player)
	await _wait_frames(3)
	_ok("召喚物戰死後節點已移除", not is_instance_valid(wolf))
	_ok("召喚物死亡**不掉落**任何掉落物（無刷寶漏洞）",
		get_tree().get_nodes_in_group(&"loot_drops").size() == loot_before)
	_ok("召喚物死亡**不觸發** player_died（獨立生命週期）", not _player_died)
	_ok("召喚物戰死仍走 unit_died 事件（與到期消失區別）", _died_units.size() == 1)


# =============================================================================
# E. 到期消失
# =============================================================================

func _test_expire() -> void:
	print("--- E. 到期消失（§12.2 · 不計死亡）---")
	var wolf := _spawn_summon("summon_spirit_wolf", Vector2(0, 0))
	await _wait_frames(2)
	_died_units.clear()
	# 直接把生命計時器推到臨界（@export lifetime 已在 _ready 讀走，故改內部計時器）
	wolf._life_timer = 0.02
	await _wait_frames(4)
	_ok("到期後節點已釋放（15s 消失）", not is_instance_valid(wolf))
	_ok("到期消失**不計死亡**（不發 unit_died）", _died_units.is_empty())
	_clear_spawned()
	await _wait_frames(2)


# =============================================================================
# F. 施放分派（技能 → 召喚；§7 / §12.4）
# =============================================================================

func _test_cast_dispatch() -> void:
	print("--- F. 施放分派（skill_controller「summon」）---")
	_clear_spawned()
	_clear_summons()
	await _wait_frames(2)

	# 資料層：JSON 的字符串 type "summon" 解析為 SkillType.SUMMON；圖標鍵齊全
	var sd := ConfigLoader.get_skill("summon_spirit_wolf")
	_ok("skills.json：靈狼 type 解析為 summon（SkillType.SUMMON）",
		sd != null and sd.type == SkillData.SkillType.SUMMON)
	_ok("SKILL_ICON 有 summon_spirit_wolf 映射且貼圖可載（無缺圖）",
		str(GameConstants.SKILL_ICON.get("summon_spirit_wolf", "")) == "skill_icon_spirit_wolf"
		and UISkin.texture("skill_icon_spirit_wolf") != null
		and UISkin.texture("skill_icon_summon_elemental") != null)

	# 白盒：把召喚技能塞進玩家的技能控制器（繞過存檔欄），以測 SUMMON 分派路徑
	var sc := _player.get_skill_controller()
	sc._skills["summon_spirit_wolf"] = sd
	sc._cooldowns["summon_spirit_wolf"] = 0.0
	_player.get_mana_pool().set_current(100.0)

	var cast_ok := sc.try_cast("summon_spirit_wolf")
	# ⚠️ 冷卻 / 法力必須在 `try_cast` 後**同步**讀取：`_process` 每幀 tick 冷卻、
	#    法力池每幀自然回復 ⇒ await 之後再讀會漂移，斷言變 flaky。
	var cd_after := sc.get_cooldown_remaining("summon_spirit_wolf")
	var mana_after := _player.get_mana_pool().current
	await _wait_frames(2)
	var wolves := _summons_of_id("summon_spirit_wolf")
	_ok("施放成功", cast_ok)
	_ok("扣藍 30（100 → 70）", is_equal_approx(mana_after, 70.0))
	_ok("進入冷卻 12s", is_equal_approx(cd_after, 12.0))
	_ok("場上出現 1 隻召喚物", wolves.size() == 1)
	_ok("召喚物屬 summons 組、不屬 enemies 組",
		wolves.size() == 1 and wolves[0].is_in_group(&"summons")
		and not wolves[0].is_in_group(&"enemies"))
	_ok("召喚物 id = summon_spirit_wolf",
		wolves.size() == 1 and str(wolves[0].call("get_summon_id")) == "summon_spirit_wolf")

	# 同一 id 上限 1 隻：清冷卻再放 → 仍只有 1 隻（取代，非疊加）
	var first: Node = wolves[0] if wolves.size() == 1 else null
	sc._cooldowns["summon_spirit_wolf"] = 0.0
	sc.try_cast("summon_spirit_wolf")
	await _wait_frames(2)
	var wolves2 := _summons_of_id("summon_spirit_wolf")
	_ok("重複召喚：同一 id 仍只有 1 隻（上限 1）", wolves2.size() == 1)
	_ok("重複召喚：舊個體已解召（取代）", first == null or not is_instance_valid(first))

	# 15 秒到期消失（§12.2）
	if wolves2.size() == 1:
		wolves2[0].set("_life_timer", 0.02)
		await _wait_frames(4)
		_ok("到期後召喚物消失（15s）", _summons_of_id("summon_spirit_wolf").is_empty())
	else:
		_ok("到期後召喚物消失（15s）", false)
	_clear_summons()
	await _wait_frames(2)


func _finish() -> void:
	# ⚠️ 結果行格式必須與 `verify_enemy.gd` 一致（**簡體「项失败」**）——
	#    `game/tools/run_regression.py` 的 `_result_line()` 按 `"项失败" / "全部通过（" /
	#    "项未通过"` 匹配；用繁體「項失敗」會被判成 NO-RESULT（空轉）＝回歸變紅。
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
