## 玩家召喚物（技能體系策劃案第十二章 · 規格 §12.1 / §12.2 / §12.4）
##
## 設計取向（**複用而非另起一套**）：
##   本類 `extends EnemyBase`，直接複用其 AI 狀態機（巡邏 / 追擊 / 攻擊）、精靈優先鏈
##   （`pack_load_set` 命名約定探測）、`HealthComponent`、擊退通道與動畫狀態機。
##   與 BOSS 召喚（`enemy_base.gd::_summon_minions()`）同構，差別只在**友方語義**：
##     · `target_group = "enemies"`（打怪，而非打玩家）；
##     · `is_summon = true`（進 `summons` 組、不掉落、不觸發玩家死亡邏輯）。
##
## 屬性**每幀動態讀取**（規格 §12.2 硬需求）：
##   生命 = 玩家最大生命 × 30%（狼）/ 40%（僕從）；
##   攻擊 = 玩家攻擊 × 60% / 70%；移速 = 玩家移速 × 1.2 / 0.9。
##   ⇒ 局內三選一加攻 / 加血上限時，召喚物**同步變強**（非召喚瞬間快照）。
##
## 特殊行為（§12.2）：
##   靈狼：首次接觸目標時**衝鋒**（+50% 移速 1 秒）；
##   元素僕從：遠程（4 格）投射小火球，命中帶**小範圍濺射**（24px / 50%）。
##
## 生命週期：存活 15 秒到期**消失**（`queue_free`，不計死亡 → 不發 `unit_died`）。
##
## ⚠️ 素材落點（並行生產中）：`res://assets/pack/creatures/summon_spirit_wolf|summon_elemental/`，
##    命名 `char_<id>_<action>_<dir>_<NN>.png`（idle 4 / walk 6 / attack 6，8 方向，128×128）。
##    素材未到位時 `pack_load_set` 回 `ok=false` ⇒ 自動落回占位色塊（安全降級）；
##    素材到位後**零改動**即可載入（走 `pack_probe_names`，不靠目錄枚舉）。
class_name Summon
extends EnemyBase

## 召喚物場景（根腳本即本類）
const SCENE_PATH := "res://scenes/combat/summon.tscn"

## 衝鋒參數（靈狼）
const CHARGE_DURATION: float = 1.0
const CHARGE_SPEED_MULT: float = 1.5
const CHARGE_TRIGGER_MARGIN: float = 12.0

## 兩隻召喚物的屬性表（規格 §12.2；攻擊距離以格換算，1 格 = 32px）
##   attack_range：狼 0.8 格 = 25.6px ｜ 僕從 4 格 = 128px
##   search_range：狼 6 格 = 192px ｜ 僕從 5 格 = 160px
const DEFS: Dictionary = {
	"summon_spirit_wolf": {
		"display_name": "靈狼",
		"hp_ratio": 0.30,
		"atk_ratio": 0.60,
		"speed_ratio": 1.2,
		"search_range": 192.0,
		"attack_range": 25.6,
		"attack_interval": 1.0,
		"ranged": false,
		"splash_radius": 0.0,
		"splash_ratio": 0.0,
		"charge": true,
		"element": "physical",
		"icon": "skill_icon_spirit_wolf",
	},
	"summon_elemental": {
		"display_name": "元素僕從",
		"hp_ratio": 0.40,
		"atk_ratio": 0.70,
		"speed_ratio": 0.9,
		"search_range": 160.0,
		"attack_range": 128.0,
		"attack_interval": 1.25,
		"ranged": true,
		"splash_radius": 24.0,
		"splash_ratio": 0.5,
		"charge": false,
		"element": "fire",
		"icon": "skill_icon_summon_elemental",
	},
}

## 召喚物 id（§12.1）：`summon_spirit_wolf` / `summon_elemental`。
## ⚠️ 也是素材目錄名與 `owner_player` 之外的唯一識別；必須在 `add_child()` 前設定。
@export var summon_id: String = "summon_spirit_wolf"

## 存活時間（秒，§12.2）：到期消失（不計死亡）。
@export var lifetime: float = 15.0

## 召喚者（玩家）。由 `spawn()` 注入，亦可在生成後補設。
## ⚠️ 必須在 `add_child()` 前設定，`_ready()` 就會讀它算初始生命上限。
var owner_player: Node = null

# ---- 由 DEFS 解析出的比例 / 參數（_configure 填入）----
var _hp_ratio: float = 0.30
var _atk_ratio: float = 0.60
var _speed_ratio: float = 1.2
var _search_range: float = 192.0
var _attack_range_px: float = 25.6
var _attack_interval_s: float = 1.0
var _ranged: bool = false
var _splash_radius: float = 0.0
var _splash_ratio: float = 0.5
var _can_charge: bool = true
var _element: String = GameConstants.ELEMENT_PHYSICAL
var _icon: String = "skill_icon_spirit_wolf"

# ---- 執行期狀態 ----
var _life_timer: float = 0.0
var _expired: bool = false
var _charge_timer: float = 0.0
var _charge_used: bool = false


# =============================================================================
# 生成入口
# =============================================================================

## 生成一隻召喚物（**技能側統一入口**）。
## 由未來的 `SkillController` SUMMON 分派 / 驗證腳本調用；
## host 一般傳 `LevelScene` 的 `Actors` 容器（與 BOSS 召喚一致）。
static func spawn(host: Node, owner_ref: Node, id: String, pos: Vector2) -> Summon:
	if host == null:
		return null
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("[Summon] 找不到場景 %s" % SCENE_PATH)
		return null
	var s := scene.instantiate() as Summon
	if s == null:
		return null
	# ⚠️ 順序：先設定匯出/注入欄位，再 add_child（`_ready()` 就用它們建屬性、定群組）
	s.summon_id = id
	s.owner_player = owner_ref
	host.add_child(s)
	s.global_position = pos
	s.play_spawn_fx()
	return s


# =============================================================================
# 生命週期
# =============================================================================

func _ready() -> void:
	# 友方語義：打怪 + 進 summons 組（不進 enemies）
	is_summon = true
	target_group = "enemies"
	_configure()
	super._ready()
	_life_timer = maxf(lifetime, 0.0)
	# 初始動態屬性（生命 = 玩家最大生命 × 比例）
	_sync_dynamic_stats()


## 依 `summon_id` 從 `DEFS` 解析參數，並合成一份 `MonsterData` 供 EnemyBase 既有管線使用。
## ⚠️ 必須在 `super._ready()` **之前**執行（EnemyBase 的 `data == null` 守門會保留它）。
func _configure() -> void:
	var d: Dictionary = DEFS.get(summon_id, DEFS["summon_spirit_wolf"])
	_hp_ratio = float(d["hp_ratio"])
	_atk_ratio = float(d["atk_ratio"])
	_speed_ratio = float(d["speed_ratio"])
	_search_range = float(d["search_range"])
	_attack_range_px = float(d["attack_range"])
	_attack_interval_s = float(d["attack_interval"])
	_ranged = bool(d["ranged"])
	_splash_radius = float(d["splash_radius"])
	_splash_ratio = float(d["splash_ratio"])
	_can_charge = bool(d["charge"])
	_element = String(d["element"])
	_icon = String(d["icon"])
	# 合成怪物資料：HP / 傷害欄位不參與召喚物結算（覆寫了 getter），僅供既有管線讀取。
	var md := MonsterData.new()
	md.id = summon_id
	md.display_name = String(d["display_name"])
	md.tier = MonsterData.Tier.NORMAL
	md.hp_scale = 1.0
	md.damage_scale = 1.0
	md.move_speed = 100.0
	md.attack_interval = _attack_interval_s
	md.attack_range = _attack_range_px
	md.base_armor = 0.0
	md.element = _element
	md.sprite_path = ""
	data = md


func _physics_process(delta: float) -> void:
	if _expired or is_dead:
		return
	# 15 秒到期消失（§12.2）：**不計死亡** —— 直接釋放，不發 unit_died。
	if _life_timer > 0.0:
		_life_timer = maxf(_life_timer - delta, 0.0)
		if _life_timer <= 0.0:
			_expire()
			return
	if _charge_timer > 0.0:
		_charge_timer = maxf(_charge_timer - delta, 0.0)
	# 每幀動態同步（§12.2 硬需求）
	_sync_dynamic_stats()
	super._physics_process(delta)


# =============================================================================
# 動態屬性（§12.2：每幀讀玩家，非快照）
# =============================================================================

## 取得召喚者：優先注入的 `owner_player`，否則回退場上第一個玩家（測試 / 容錯）。
func _owner() -> Node:
	if owner_player != null and is_instance_valid(owner_player):
		return owner_player
	return get_tree().get_first_node_in_group(&"player")


## 每幀把生命上限同步為「玩家最大生命 × 比例」。
## 上限變動時把差額加到當前生命（玩家成長 ⇒ 召喚物同步變硬；上限下降則削減且不低於 0）。
func _sync_dynamic_stats() -> void:
	if health == null:
		return
	var src := _owner()
	if src == null or not src.has_method("get_max_hp"):
		return
	var new_max := float(src.call("get_max_hp")) * _hp_ratio
	if new_max <= 0.0:
		return
	var diff := new_max - health.max_hp_override
	health.max_hp_override = new_max
	if not is_equal_approx(diff, 0.0):
		health.current_hp = clampf(health.current_hp + diff, 0.0, new_max)


## 攻擊力 = 玩家當前攻擊 × 比例（每幀呼叫 ⇒ 動態）。
func get_attack_damage() -> float:
	var src := _owner()
	if src != null and src.has_method("get_attack_damage"):
		return float(src.call("get_attack_damage")) * _atk_ratio
	return 0.0


## 生命上限 / 當前生命：世界血條（`WorldHealthBar`）**優先走方法接口**。
## ⚠️ 必須提供 —— 否則血條會退回 `data.get_hp(...)`，而召喚物的實際上限是
##    「玩家最大生命 × 比例」，兩者不一致 ⇒ 血條比例失真。
func get_max_hp() -> float:
	return health.get_max_hp() if health != null else 0.0


func get_current_hp() -> float:
	return health.get_current_hp() if health != null else 0.0


# =============================================================================
# AI 覆寫（速度 / 索敵；衝鋒）
# =============================================================================

## 移速 = 玩家移速 × 比例（× 衝鋒加成）。玩家移速 = 基礎 × 移速乘區。
func _move_speed() -> float:
	var src := _owner()
	var mult := 1.0
	if src != null and src.has_method("get_move_speed_multiplier"):
		mult = float(src.call("get_move_speed_multiplier"))
	var base := PlayerController.LOCAL_MOVE_SPEED * mult
	var charge := CHARGE_SPEED_MULT if _charge_timer > 0.0 else 1.0
	return base * _speed_ratio * charge


func _aggro_range() -> float:
	return _search_range


## 脫戰半徑放寬至索敵半徑 1.5 倍：召喚物應貼著目標打，不輕易放棄。
func _lose_range() -> float:
	return _search_range * 1.5


## 靈狼：首次接觸目標（進入攻擊距離 + 邊距）時觸發一次衝鋒。
func _tick_chase(delta: float, dist: float) -> void:
	if _can_charge and not _charge_used and dist <= _attack_range_px + CHARGE_TRIGGER_MARGIN:
		_charge_used = true
		_charge_timer = CHARGE_DURATION
	super._tick_chase(delta, dist)


# =============================================================================
# 攻擊（友方版：對 `enemies` 結算；元素僕從帶濺射）
# =============================================================================

## 覆寫敵方攻擊：以自身朝向對**目標（怪物）**結算，並在元素僕從時做範圍濺射。
## 走 `DamageCalc` 完整管線（目標護甲 / 抗性減傷），與玩家技能口徑一致。
func _attack_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_play_anim_oneshot(ANIM_ATTACK, minf(_attack_interval_s, ATTACK_ANIM_MAX))
	var hit := HitQuery.arc(global_position, facing, _attack_range_px,
		GameConstants.ENEMY_ATTACK_ARC_DEG, [_player])
	if hit.is_empty():
		return
	var base_atk := get_attack_damage()
	if base_atk <= 0.0:
		return
	_deal_damage(_player, base_atk)
	# 元素僕從：命中帶小範圍濺射（24px / 50%）
	if _splash_radius > 0.0:
		_apply_splash(base_atk, _player)


## 濺射：以命中點為中心、半徑內其餘敵人受 50% 傷害（不含主目標，不誤傷召喚物）。
func _apply_splash(base_atk: float, primary: Node) -> void:
	var impact := (primary as Node2D).global_position
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node == primary or not (node is Node2D) or node.is_in_group(&"summons"):
			continue
		if (node as Node2D).global_position.distance_to(impact) <= _splash_radius:
			_deal_damage(node, base_atk * _splash_ratio)


## 對單一目標結算一次召喚物傷害（暴擊不計，元素 = 各自元素）。
func _deal_damage(target: Node, base: float) -> void:
	if target == null or not is_instance_valid(target) or base <= 0.0:
		return
	var res := DamageCalc.compute_hit(
		base,
		0.0,
		150.0,
		_element,
		0.0,
		DamageCalc.target_armor(target),
		DamageCalc.target_resist(target, _element),
		DamageCalc.target_level(target),
		0.0,
	)
	if target.has_method("take_damage"):
		target.take_damage(res.final_damage, self)
	EventBus.damage_dealt.emit(target, res.final_damage, res.crit, res.element)
	# 元素僕從：命中點播火球命中特效（無投射物系統，暫以命中特效代表「小火球」）
	if _ranged and target is Node2D:
		var host := get_parent()
		if host != null:
			FxTable.spawn("elem_hit_fire", (target as Node2D).global_position, {"host": host})


# =============================================================================
# 表現 / 生命週期收尾
# =============================================================================

## 召喚法陣（§12.5）：施放時腳下播一次 `summon_circle`。由 `spawn()` 在定位後呼叫。
func play_spawn_fx() -> void:
	var host := get_parent()
	if host == null:
		return
	FxTable.spawn("summon_circle", global_position, {"host": host})


## 到期消失（§12.5）：播消散特效後釋放，**不發 unit_died**（區別於戰死）。
func _expire() -> void:
	_expired = true
	var host := get_parent()
	if host != null:
		FxTable.spawn("death_puff", global_position, {"host": host})
	queue_free()


## 精靈解析：以 `summon_id` 走 pack 命名約定探測（素材未到位 → 落回占位色塊）。
func _resolve_sprite() -> Dictionary:
	return EnemyBase.resolve_character_set(summon_id, "")


# =============================================================================
# HUD / 驗證查詢接口
# =============================================================================

## 剩餘存活時間（秒；0 = 已到期）。HUD 倒數環消費。
func get_remaining_lifetime() -> float:
	return maxf(_life_timer, 0.0)


## 總存活時間（秒）。HUD 環比例分母。
func get_total_lifetime() -> float:
	return maxf(lifetime, 0.001)


## HUD 圖標邏輯名（`UISkin.texture`）。
func get_summon_icon() -> String:
	return _icon


## 召喚物 id。
func get_summon_id() -> String:
	return summon_id
