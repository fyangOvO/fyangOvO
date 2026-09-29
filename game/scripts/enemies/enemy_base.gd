## 敌人基类（阶段 2 · 任务 2.4 · AI 状态机：巡逻 / 追击 / 攻击）
##
## 职责边界（2.4，别越界）：
##   ✅ AI 状态机：巡逻（出生点游走）→ 追击（玩家入 AGGRO）→ 攻击（attack_range 停手）
##      数据驱动：全部读 `MonsterData`（move_speed / attack_interval / attack_range /
##      hp_scale / damage_scale / element / tier），数值基线在 GameConstants 一处。
##   ✅ 可受击契约（2.2/2.3 约定，与 DamageDummy 同接口）：
##      take_damage / apply_knockback / get_armor / get_resist / get_level
##   ✅ 生命组件（2.7 收编统一）：HP / 受击扣血 / 死亡由 HealthComponent 持有
##      （apply_mitigation=false —— 玩家攻击管线已按敌人护甲减伤，避免双重减伤）；
##      死亡监听 unit_died → 掉落（LootRoller）+ 移除。
##   ✅ 对玩家攻击：attack_interval 间隔输出 `EventBus.damage_taken`（带元素）。
##      玩家扣血 / 闪避 / 格挡在 2.6 接入；本类不直接改玩家生命。
##   ✅ 掉落（2.7）：死亡时按档位掉落表 roll 金币 / 材料 / 装备（LootDrop 地面物件）。
##   ❌ 经验（2.8 局内成长）、寻路 / 地形（阶段 2 后期）、精灵动画（2.8/阶段 3 换真美术）
##
## 占位美术：按档位用色板色块（普通 暗红 / 精英 紫 / BOSS 金），像素风格铁律
##           （Nearest、色值取 48 色板）。阶段 2.8/3 替换为精灵帧。
class_name EnemyBase
extends CharacterBody2D

## W5-1 · ranged_kiter 投射物（W5-1 inline 最小可行版本）
## 用 preload 而不是 class_name 引用：`class_name` 全域註冊在 headless 解析
## 時序上不穩，曾踩過「Identifier not declared」 ⇒ 統一走 preload 最保險。
const EnemyProjectile = preload("res://scripts/enemies/enemy_projectile.gd")

# =============================================================================
# 一、状态机
# =============================================================================

## 巡逻（出生点游走）→ 追击（朝玩家）→ 攻击（attack_range 内停手输出伤害）
enum AIState { PATROL, CHASE, ATTACK }

const STATE_NAMES: Array[String] = ["巡逻", "追击", "攻击"]

## 当前状态
var state: AIState = AIState.PATROL

# =============================================================================
# 二、配置（场景摆放 / 关卡投放时设置；数据本体读 MonsterData）
# =============================================================================

## 怪物表 ID（`game/data/monsters/monsters.json`，如 "spider_cave"）
@export var monster_id: String = "spider_cave"

## 关卡等级（决定 HP / DMG / 护甲成长，GDD 6.3）
@export var level: int = 1

## 难度层级（决定 HP / DMG 难度系数，GDD 6.4 方案 D；NM1 = ×1）
@export var difficulty_tier: int = GameConstants.DifficultyTier.NM1

## 是否用占位色块美术（true = 验证 / 试玩；false = 用数据里的精灵路径）
@export var use_placeholder_art: bool = true

## 精英词缀（任务 6.2：急速 / 吸血 / 爆炸 / 回响 / 荆棘 / 闪现）
## 由关卡刷怪 / 外部在生成后注入；空 = 普通怪行为。
var affixes: Array[String] = []

## AI **搜尋目標**用的群組（規格 §12.4#1）。
##   敵方單位（本類既有用途）= "player"（預設，行為與接入前逐位一致）；
##   友方召喚物（`scripts/combat/summon.gd`）= "enemies"（打怪）。
@export var target_group: String = "player"

## 是否為**友方召喚物**（規格 §12.4#3/#4/#5）。
##   true  ⇒ 加入 `summons` 組（**不進** `enemies`）、死亡不掉落、不觸發玩家死亡邏輯；
##   false ⇒ 加入 `enemies` 組，行為與接入前逐位一致。
## ⚠️ 必須在 `add_child()` **之前**設定 —— `_ready()` 就用它決定群組歸屬。
@export var is_summon: bool = false

## 词缀移速乘法（由词缀注入）
var _move_mult := 1.0

## 词缀闪现倒计时
var _phase_timer := 0.0

## BOSS 阶段机制（任务 6.3；仅 data.tier == BOSS 时启用）
var boss_config: Dictionary = {}
var _boss_phase := 1
var _boss_skills: Array[String] = []
var _boss_interval_mult := 1.0
var _boss_dmg_mult := 1.0
var _summon_timer := 0.0
## W5-5 · 骸骨暴君「扇形重擊」冷卻計時（與普攻同節奏 tick，但有自己的冷卻）
var _slam_timer := 0.0
## W5-5 · 熔心之主「火球」冷卻計時（**獨立於普攻/狀態**，見 `_tick_state`）
var _fireball_timer := 0.0
## W5-5 · 狂暴紅閃是否已播（`enrage` 是**一次性**事件，不能每次普攻重播）
var _enrage_fx_played := false

## W5-1 · erratic_chaser 擾動累計時間（CHASE 方向加正弦擾動用）
var _erratic_phase: float = 0.0

## W5-1 · melee_charger 蓄力倒計時（> 0 = 蓄力中，動畫定格）
var _charge_windup_t: float = 0.0

## W5-1 · melee_charger 是否已蓄完、正在衝刺
var _charging: bool = false

# =============================================================================
# 三、运行时状态
# =============================================================================

## 怪物数据（ConfigLoader 注入）
var data: MonsterData = null

## 生命组件（2.7 收编：HP / 受击 / 死亡；apply_mitigation=false 防双重减伤）
@onready var health: HealthComponent = $Health

## 临时增益组件（第四步 B4 3-B3，**代码创建**，与 `Health` 并列）。
## 敌人侧消费点：`get_armor()`（减甲 `pct_armor`，来自 `enemy_armor_reduction`）/
## `_move_speed()`（减速 `move_speed`，来自 `ms_boost` 负值）。
var buff_component: BuffComponent = null

## 当前生命（转发到生命组件；保留属性名兼容 2.4 验证与外部读取）
var current_hp: float:
	get:
		return health.get_current_hp() if health != null else 0.0
	set(v):
		if health != null:
			health.current_hp = v

## 是否已死亡（转发；死亡后忽略受击与 AI）
var is_dead: bool:
	get:
		return health.is_dead if health != null else false
	set(v):
		if health != null:
			health.is_dead = v

## 出生点（巡逻围绕的中心）
var _spawn_point: Vector2 = Vector2.ZERO

## 巡逻目标点
var _patrol_target: Vector2 = Vector2.ZERO

## 巡逻停留倒计时
var _patrol_wait: float = 0.0

## 攻击节奏计时（0 就绪 → 到 0 打一下）
var _attack_timer: float = 0.0

## 受击闪白倒计时
var _flash_timer: float = 0.0
## 9.x 受击硬直（hitstun）：真掉血时短暂打断 AI 追击（移动 ×0.25），提升打击感
var _hitstun_timer: float = 0.0

## 当前朝向（移动方向；攻击时朝玩家。2.5 攻击命中判定以它为扇区中轴）
var facing: Vector2 = Vector2.DOWN

## 玩家引用（每物理帧刷新；玩家 2.6 前无生命组件，本类只发事件不扣血）
var _player: Node = null

## 掉落是否已处理（死亡只掉一次）
var _loot_dropped: bool = false

# =============================================================================
# 三·五、击退（受击契约，与 `PlayerController.apply_knockback` **同签名**）
# =============================================================================
#
# ⚠️ 契约完整性：`SkillController._hit` 用 `has_method("apply_knockback")` 探测目标，
#    **缺了就静默跳过**（不报错、不警告）。所以这个方法名必须与 PlayerController 一字不差
#    —— 别改名字，改名字会连带打红 `verify_fix93` 的 H 段。
#
# 实现取向：**不**用 `position += offset`（那会瞬移 + **穿墙**，且破坏像素网格对齐）。
#    墙体碰撞体（`LevelScene._build_collision()`）现在是真实存在的，直接改 position
#    会把怪推进墙里 / 卡在几何体中。正确做法是折算成初速放进**独立**的击退通道，
#    与 AI 通道**相加**后交给 move_and_slide() 裁定地形 —— 与玩家侧同一套模式。
#
# ⚠️ 叠加方式必须是「重算」，不能是「自加」：
#    写成 `velocity += _knockback_velocity` 会让击退逐帧累积发散（velocity 是
#    CharacterBody2D 的**跨帧持久属性**）。玩家侧实测请求 12px 位移会走成 61.4px。

## 击退速度（px/s）。独立于 AI 移动速度，不吃巡逻/追击的速度曲线。
var _knockback_velocity: Vector2 = Vector2.ZERO

## 击退衰减率（px/s²）。线性衰减下「位移 L ↔ 初速 v0」满足 L = v0² / (2a)。
## 与玩家侧同值，保证「同一次击退」对玩家和怪物的手感一致。
const KNOCKBACK_DECAY: float = 1200.0

## 击退速度下限（px/s）：低于此值直接归零，避免肉眼看不见的残余速度继续参与移动。
const KNOCKBACK_STOP_EPSILON: float = 4.0
## 9.x 受击硬直参数
const HITSTUN_DURATION: float = 0.12
const HITSTUN_SPEED_MULT: float = 0.25

const LOOT_SCENE := preload("res://scenes/loot/loot_drop.tscn")

@onready var _body: Sprite2D = $Body

# ── 真實精靈（豆包原創像素素材：多動作 × 多方向，用戶可替換）──────────────
## 所有美術一律取自豆包原創像素包，不含任何第三方素材；解析優先鏈：
##   ① 用戶覆蓋 `user://content/characters/` → ①·5 內建多幀 `assets/pack/creatures/`
##   → ② 內建單張 `assets/sprites/` → 都缺則回空集（呼叫方畫占位色塊）。
## 遊戲內縮放常數（128 畫布顯示 32px）。
const DNF_GAME_SCALE: float = 0.25
## 腳底落點 y（px）：= 敵人碰撞框半高。Body 的碰撞形狀是 24×24 **居中**，
## 故碰撞框底邊在 y=+12；腳底貼此處，視覺重心與原 32×32 佔位一致。
const DNF_FEET_Y: float = 12.0
## 內建單張精靈目錄（**用戶可用 `user://content/characters/<id>.png` 覆蓋**）。
## 敵人取 `MonsterData.sprite_path`（同目錄）；玩家此槽位為空，走 pack 多幀。
const BUNDLED_SPRITE_DIR: String = "res://assets/sprites/enemies"

## 素材包多幀集根（**committed · 豆包原創**）：`res://assets/pack/creatures/<id>/char_<id>_*.png`。
## 玩家（id=`player`）與 16 隻怪物的多動作多方向幀集落此，是可入倉的正式美術。
## 位置刻意在 ② bundled 單張**之前**：② 的單幀會先命中而遮蔽多幀集；
## 用戶覆蓋（①）仍最高優先，插在其後不破壞優先級契約。
const PACK_CREATURE_ROOT: String = "res://assets/pack/creatures"

# ── 動作（與檔名 `<action>` 段一致；四方向 + 五動作是本輪的用戶可見契約）──
const ANIM_IDLE: String = "idle"
const ANIM_WALK: String = "walk"
const ANIM_ATTACK: String = "attack"
const ANIM_HURT: String = "hurt"
const ANIM_DIE: String = "die"

## 動畫狀態（**純表現層**：不參與 AI、不閘門傷害、不影響 TTK）
enum AnimState { IDLE, WALK, ATTACK, HURT, DIE }

## 動作回退序：請求的動作不在素材裡時，按此序退到第一個存在的。
## 保證「用戶只放一組 idle」也永遠播得出東西，不會白畫面。
const ANIM_FALLBACK: Dictionary = {
	ANIM_IDLE: [ANIM_IDLE, ANIM_WALK, ANIM_ATTACK, ANIM_HURT, ANIM_DIE],
	ANIM_WALK: [ANIM_WALK, ANIM_IDLE, ANIM_ATTACK, ANIM_HURT, ANIM_DIE],
	ANIM_ATTACK: [ANIM_ATTACK, ANIM_WALK, ANIM_IDLE, ANIM_HURT, ANIM_DIE],
	ANIM_HURT: [ANIM_HURT, ANIM_IDLE, ANIM_WALK, ANIM_ATTACK, ANIM_DIE],
	ANIM_DIE: [ANIM_DIE, ANIM_HURT, ANIM_IDLE, ANIM_WALK, ANIM_ATTACK],
}

## 四方向字母（檔名 `<dir>` 段）：n = 北/上 · e = 東/右 · s = 南/下 · w = 西/左。
## 這是**寫進用戶替換文檔的正式約定**，改名等於破壞相容性。
const DIR_N: String = "n"
const DIR_E: String = "e"
const DIR_S: String = "s"
const DIR_W: String = "w"

## 受擊 / 攻擊這類「一次性動作」的默認展示時長（秒）。純視覺，不影響戰鬥計時。
const HURT_ANIM_DURATION: float = 0.18
const ATTACK_ANIM_MAX: float = 0.35

## 真實精靈狀態（art.ok == false 時全不啟用 → 行為與原佔位完全相同）
var _real_frames: Array = []
var _real_fps: float = 12.0
var _real_anim: bool = false
var _anim_t: float = 0.0
var _anim_i: int = 0

## 動作 → 方向 → 幀陣列（`{ "idle": { "s": [Texture2D, ...] }, ... }`）。
## 空 = 沒接真素材 ⇒ `_process` 零成本早退，占位行為逐位不變。
var _clips: Dictionary = {}
## 當前解析出的 clip 與其鍵（避免每幀重算字典查找）
var _clip: Array = []
var _clip_key: String = ""
var _clip_exact: bool = false

## 當前動畫狀態與方向
var _anim_state: int = AnimState.IDLE
var _anim_action: String = ANIM_IDLE
var _anim_dir: String = DIR_S
## 一次性動作（attack / hurt）剩餘秒數；0 = 無
var _anim_oneshot: String = ""
var _anim_oneshot_t: float = 0.0

## 紋理快取（static：同 who 的多隻怪共享，避免重複解碼）
static var _dnf_cache: Dictionary = {}


func _ready() -> void:
	# 俯视 ARPG：FLOATING 模式，避免被 default_gravity 往下拽
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# 群組歸屬（規格 §12.4#5）：召喚物進 `summons`（**不進** `enemies`，故玩家技能
	# 天然打不到它）；其餘單位照舊進 `enemies`。HitQuery 另有一道 `summons` 過濾作縱深防禦。
	if is_summon:
		add_to_group(&"summons")
	else:
		add_to_group(&"enemies")
	_spawn_point = global_position
	# 临时增益组件（第四步 B4 3-B3）：代码创建、与 `$Health` 并列；无增益时 `_process` 自关。
	buff_component = BuffComponent.new()
	buff_component.name = "BuffComponent"
	add_child(buff_component)
	# 允許呼叫方**預先注入** `data`（召喚物在 `Summon._ready()` 合成 MonsterData 後傳入）；
	# 未注入才走怪物表查詢 —— 既有敵人行為不變。
	if data == null:
		data = ConfigLoader.get_monster(monster_id)
	# 生命组件初始化：敌人 max_hp 用怪物表公式（覆盖玩家裸装公式）
	if health != null:
		health.max_hp_override = data.get_hp(level, difficulty_tier)
		health.current_hp = health.max_hp_override
	_attack_timer = data.attack_interval
	_patrol_target = _random_patrol_point()
	# 優先鏈：先試豆包真實精靈（pack 多幀 → data.sprite_path 單張），失敗才落回占位色塊。
	# ⚠️ 只調順序，不動 use_placeholder_art 的語義（它仍是「允許占位兜底」）。
	var art := _resolve_sprite()
	if art["ok"]:
		_apply_real_art(art)
	elif use_placeholder_art:
		_build_placeholder_art()
	# 死亡 → 掉落 + 移除（unit_died 由生命组件在 HP≤0 时广播）
	EventBus.unit_died.connect(_on_unit_died)
	# 词缀初始化（6.2：移速乘法 / 初始闪现计时）
	if not affixes.is_empty():
		_move_mult = float(AffixController.get_multipliers(affixes)["move"])
		_phase_timer = float(AffixController.AFFIXES.get("phasing", {}).get("interval", 6.0))
	# BOSS 阶段初始化（6.3：加载阶段配置，阶段 1 技能集 / 数值乘区）
	# 召喚物不走 BOSS 路徑（`is_summon` 短路，避免合成的 data 意外帶 BOSS 檔位時誤啟）。
	if not is_summon and data != null and data.tier == MonsterData.Tier.BOSS:
		boss_config = ConfigLoader.get_boss(monster_id)
		_apply_boss_phase(1)


## 占位美术：32×32 色块（档位色：普通 暗红 / 精英 紫 / BOSS 金）
func _build_placeholder_art() -> void:
	var c: Color
	match data.tier:
		MonsterData.Tier.ELITE:
			c = Color("7E44B8")
		MonsterData.Tier.BOSS:
			c = Color("D9A521")
		_:
			c = Color("8C1A1F")
	if _body != null:
		_body.texture = _solid_texture(32, 32, c)
		_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# =============================================================================
# 三·B、真實精靈：優先鏈（**用戶可替換**，美術全為豆包原創像素）
#   ① `user://content/characters/<id>/`   用戶覆蓋目錄（最高優先）
#   ①·5 `res://assets/pack/creatures/<id>/`  素材包多幀集（**committed**，怪物與玩家）
#   ② `res://assets/sprites/enemies/<id>.png`  隨包內建單張
#   ③ 都沒命中 → 回空集（`resolve_character_set` 回 ok=false）
#   ④ 程序化占位色塊（呼叫方 `_build_placeholder_art`；缺啥見《素材缺口清單》）
# =============================================================================

## 解析本怪要用的精靈。回傳結構見 `dnf_load_dir`。
## 全部落空 → `ok=false`，呼叫方落回占位色塊（**回退安全**）。
func _resolve_sprite() -> Dictionary:
	var bundled := ""
	if data != null:
		bundled = data.sprite_path
	return EnemyBase.resolve_character_set(monster_id, bundled)


## 套用真實精靈：腳底貼 DNF_FEET_Y、水平居中、最近鄰、1/4 縮放。
## 有分方向素材 ⇒ **關閉 flip_h**（方向已預烘，再翻轉會左右顛倒）。
func _apply_real_art(art: Dictionary) -> void:
	if _body == null:
		return
	_real_frames = art.get("frames", [])
	_real_fps = maxf(1.0, float(art.get("fps", 12.0)))
	_real_anim = _real_frames.size() > 1
	# ⚠️ 必須 duplicate：`art["clips"]` 是 `_dnf_cache` 裡的**同一個參照**，
	#    直接持有它會讓「任一實例改自己的 clip」污染整份快取（全場怪物一起變）。
	_clips = (art.get("clips", {}) as Dictionary).duplicate()
	if _clips.is_empty() and not _real_frames.is_empty():
		# 舊呼叫方（只給 frames）→ 合成單一 idle/s clip，動畫照舊會動
		_clips = {ANIM_IDLE: {DIR_S: _real_frames}}
	_anim_t = 0.0
	_anim_i = 0
	_clip = []
	_clip_key = ""
	_anim_oneshot = ""
	_anim_oneshot_t = 0.0
	_anim_state = AnimState.IDLE
	_anim_action = ANIM_IDLE
	if not _real_frames.is_empty():
		_body.texture = _real_frames[0]
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.centered = true
	_body.flip_h = false
	# anchor = bottom-center：centered + offset.y = -canvas_h/2 ⇒ 紋理底邊正好落在
	# 節點原點；再把 Body 移到 DNF_FEET_Y ⇒ 腳底貼碰撞框底邊。
	_body.offset = Vector2(0.0, -float(art.get("canvas", 0.0)) * 0.5)
	_body.scale = Vector2(DNF_GAME_SCALE, DNF_GAME_SCALE)
	_body.position = Vector2(0.0, DNF_FEET_Y)


## 真實精靈逐幀推進 + 動作狀態機。
## `_clips` 為空（沒接真素材）時**第一行就早退** ⇒ 占位行為與接入前逐位相同。
func _process(delta: float) -> void:
	if _clips.is_empty() or _body == null:
		return
	_tick_anim_state(delta)
	_refresh_clip()
	if _clip.is_empty():
		return
	if _clip.size() <= 1:
		if _body.texture != _clip[0]:
			_body.texture = _clip[0]
		return
	_anim_t += delta * _real_fps
	if _anim_t >= 1.0:
		_anim_t -= floorf(_anim_t)
		if _clip_exact and _anim_state != AnimState.IDLE and _anim_state != AnimState.WALK:
			# 一次性動作（攻擊 / 受擊 / 死亡）停在末幀，不循環回第一幀
			_anim_i = mini(_anim_i + 1, _clip.size() - 1)
		else:
			_anim_i = (_anim_i + 1) % _clip.size()
	# ⚠️ 換 clip 的**當幀**就得換圖。只在「推進一幀」時賦值的話，切到新動作後
	#    會用舊動作的幀多撐最多 1/fps（12fps ⇒ 83ms）—— 真渲染抓圖時抓到
	#    「受擊那張其實還是攻擊幀」。這裡改成每幀對齊，成本只是一次參照比較。
	if _body.texture != _clip[_anim_i]:
		_body.texture = _clip[_anim_i]


## 純表現層的動作狀態推導。**不讀寫任何戰鬥計時 / 傷害 / 位置**。
func _tick_anim_state(delta: float) -> void:
	if _anim_oneshot_t > 0.0:
		_anim_oneshot_t = maxf(_anim_oneshot_t - delta, 0.0)
	if is_dead:
		_anim_state = AnimState.DIE
		_anim_action = ANIM_DIE
		_anim_dir = dir_from_vector(facing)
		return
	if _anim_oneshot_t > 0.0 and not _anim_oneshot.is_empty():
		_anim_action = _anim_oneshot
		_anim_state = AnimState.ATTACK if _anim_oneshot == ANIM_ATTACK else AnimState.HURT
		_anim_dir = dir_from_vector(facing)
		return
	var moving := velocity.length_squared() > 1.0
	_anim_state = AnimState.WALK if moving else AnimState.IDLE
	_anim_action = ANIM_WALK if moving else ANIM_IDLE
	_anim_dir = dir_from_vector(facing)


## 依「動作 → 方向」取幀陣列（帶鍵快取，只在切換時重算）。
func _refresh_clip() -> void:
	var key := "%s|%s" % [_anim_action, _anim_dir]
	if key == _clip_key and not _clip.is_empty():
		return
	_clip_key = key
	var r := EnemyBase.resolve_clip(_clips, _anim_action, _anim_dir, _real_frames)
	_clip = r["frames"]
	_clip_exact = bool(r["exact"])
	_anim_i = 0
	_anim_t = 0.0


## 觸發一次性動作（attack / hurt）。受擊期間攻擊不搶播。
func _play_anim_oneshot(action: String, duration: float) -> void:
	if _clips.is_empty():
		return
	if action == ANIM_ATTACK and _anim_oneshot == ANIM_HURT and _anim_oneshot_t > 0.0:
		return
	_anim_oneshot = action
	_anim_oneshot_t = maxf(duration, 0.05)
	_clip_key = ""   # 強制下一幀重解析


## 死亡動畫：本體必須在 2 幀內被移除（`verify_enemy` D 段斷言），
## 故把 `die` 幀播在一個**脫離本體**的臨時 Sprite2D 上，播完自我釋放。
## 這樣「移除時序」逐位不變，而死亡動畫真的看得見。
## ⚠️ 只在**真的有 `die` 動作**時才放鬼影 —— 否則退回別的動作等於讓屍體演待機，
##    還不如維持現狀（原素材沒有 die 幀時，行為與接入前完全一致）。
func _spawn_death_anim() -> void:
	if _clips.is_empty() or _body == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var r := EnemyBase.resolve_clip(_clips, ANIM_DIE, dir_from_vector(facing), _real_frames)
	if not bool(r["exact"]):
		return
	var frames: Array = r["frames"]
	if frames.size() <= 1:
		return
	var ghost := Sprite2D.new()
	ghost.name = "DeathAnim"
	ghost.texture = frames[0]
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.centered = _body.centered
	ghost.offset = _body.offset
	ghost.scale = _body.scale
	ghost.z_index = _body.z_index
	parent.add_child(ghost)
	# 與本體 Body 的**世界**位置對齊（Body 是本體的子節點，故加本體原點）
	ghost.global_position = global_position + _body.position
	var n := frames.size()
	var tw := ghost.create_tween()
	tw.tween_method(func(i: float) -> void: ghost.texture = frames[clampi(int(i), 0, n - 1)],
		0.0, float(n - 1), float(n) / maxf(_real_fps, 1.0))
	tw.tween_callback(ghost.queue_free)


# =============================================================================
# 三·C、共用精靈解析工具（**玩家側 player_controller.gd 也會呼叫**）
# =============================================================================
##
## ⚠️ 為何寄生在此：本輪 team-lead 限定「只改 enemy_base.gd + player_controller.gd
##    兩個生產檔」，故這個共用工具以**靜態函式**寄居於 EnemyBase，玩家側用
##    `EnemyBase.resolve_character_set("player")` 呼叫 —— 以此換取「單一實作、兩側不漂移」。
##    若日後允許新增公用檔，請整體搬遷到獨立工具類並改這兩處呼叫點。
## （函式名保留 `dnf_` 前綴為歷史命名；它們只解析豆包素材目錄與用戶覆蓋目錄，
##    已不再讀取任何第三方路徑。）

## 五級優先鏈（**用戶可替換**）—— 玩家與敵人共用同一實作，兩側不漂移。
## `bundled_path` = 資料表給的內建單張路徑（敵人取 `MonsterData.sprite_path`；玩家傳空）。
static func resolve_character_set(id: String, bundled_path: String = "") -> Dictionary:
	# ① 用戶覆蓋目錄：user://content/characters/<id>/
	var user := dnf_load_user_dir(id)
	if user["ok"]:
		return user
	# ①·5 素材包多幀集（committed）：res://assets/pack/creatures/<id>/
	# ⚠️ 位置刻意在 ② bundled **之前**：② 的單幀會先命中而遮蔽多幀集（見 ② 註解）。
	#    用戶覆蓋（①）仍最高 —— 插在它之後不破壞既有優先級契約。
	var pack := pack_load_set(id)
	if pack["ok"]:
		return pack
	# ② 內建單張精靈（用戶單檔覆蓋優先；路徑拼接一律走 ContentPaths，不手寫）
	var b := bundled_path
	if b.is_empty():
		b = "%s/%s.png" % [BUNDLED_SPRITE_DIR, id]
	var p := ContentPaths.resolve_list(
		ContentPaths.CLASS_CHARACTERS,
		["%s.png" % id, "%s/sprite.png" % id],
		[b])
	if not p.is_empty():
		var tex := dnf_load_png_texture(p)
		if tex != null:
			return single_frame_set(tex, "user" if p.begins_with("user://") else "bundled")
	# ③ 全都沒命中：回空集（呼叫方落回占位色塊；缺的豆包像素見《素材缺口清單》）
	return _dnf_empty(id)


## 用戶覆蓋目錄：`user://content/characters/<id>/`（個別單幀 PNG，同一套命名約定）。
## 目錄不存在即視為未覆蓋（**不報錯、不警告** —— 絕大多數用戶不會放）。
static func dnf_load_user_dir(id: String) -> Dictionary:
	var key := "user::%s" % id
	if _dnf_cache.has(key):
		return _dnf_cache[key]
	var dir_path := ContentPaths.user_path(ContentPaths.CLASS_CHARACTERS, id)
	var r := _dnf_empty(id)
	if DirAccess.dir_exists_absolute(dir_path):
		# 用戶素材的畫布由**紋理實測**決定（與豆包包內幀集同一套解析）。
		r = dnf_load_dir(id, dir_path)
		if r["ok"]:
			r["source"] = "user"
	_dnf_cache[key] = r
	return r


## 素材包幀集的三段命名約定：`char_<id>_<action>_<dir>_<NN>.png`。
## 2026-09-23 全量掃描 `assets/pack/creatures/*` 實測：所有檔名 100% 符合此約定
## （動作 6 種 / 方向 8 種 / 幀號 1–6）。
## 2026-09-24 新增 `cast`（策劃案 01-技能体系.md 附錄A §A.9#3 的 1 行改動）：
##   原本沒有 cast ⇒ 法師/弓手施法會回退去播 attack 的劈砍動作，與技能語義不符。
##   `cast` 排在 `attack` 後、`hurt` 前，順序不影響探測結果（只是遍歷順序）。
const PACK_ACTIONS: Array[String] = ["idle", "walk", "attack", "cast", "hurt", "death", "die"]
const PACK_DIRS: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const PACK_MAX_FRAMES: int = 8

## 依命名約定 + `ResourceLoader.exists()` 探測出幀檔名清單（幀號 01 起，遇缺即停）。
##
## ⚠️ **為什麼不能靠 `DirAccess` 枚舉 `res://`**（2026-09-23 導出包實測）：
##    導出時 `export_filter="all_resources"` 只把 PNG 的**導入產物**（`.ctex`）寫進 PCK，
##    源 `.png` 不進檔案表（只留 remap 條目）⇒ `DirAccess.open(dir)` 打得開、
##    `list_dir()` 卻回 **0 個 .png**；而 `ResourceLoader.exists()/load()` 照樣正常。
##    後果：所有多幀素材在導出包裡**靜默退化** —— 怪物退到單幀兜底（畫面變成不動的貼圖）、
##    玩家沒有兜底 ⇒ 直接變占位色塊。此 bug 在編輯器裡永遠看不到，只有跑 `--smoke` 才暴露。
static func pack_probe_names(id: String, dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for action in PACK_ACTIONS:
		for d in PACK_DIRS:
			for i in range(1, PACK_MAX_FRAMES + 1):
				var fname := "char_%s_%s_%s_%02d.png" % [id, action, d, i]
				if ResourceLoader.exists("%s/%s" % [dir_path, fname]):
					out.append(fname)
				else:
					break
	return out


## 載入素材包多幀集：`res://assets/pack/creatures/<id>/`（**committed · 豆包原創**）。
## 畫布由紋理實測決定（不讀 manifest）。static 快取鍵加 `pack::` 前綴，與用戶
## 覆蓋（鍵 `user::`）隔離，互不污染。
static func pack_load_set(id: String) -> Dictionary:
	var key := "pack::%s" % id
	if _dnf_cache.has(key):
		return _dnf_cache[key]
	var dir_path := "%s/%s" % [PACK_CREATURE_ROOT, id]
	var r := dnf_load_names(id, dir_path, pack_probe_names(id, dir_path))
	if r["ok"]:
		r["source"] = "pack"
	_dnf_cache[key] = r
	return r


## 清空精靈快取（換素材 / 用戶改檔後強制重讀）。
## ⚠️ 靜態快取若不可失效，就會變成「改了檔案卻沒生效」的假象 —— `TileAtlas._cache` 已踩過。
static func clear_cache() -> void:
	_dnf_cache.clear()


## 解析**任意**單幀 PNG 目錄為 `{動作 → 方向 → 幀}` 的 clip 集（豆包素材 / 用戶覆蓋通用）。
## `who` 僅作診斷用；方向/動作一律由**檔名**推導。畫布由紋理實測決定、fps 用預設。
##
## ⚠️ 本函式靠 `DirAccess` 枚舉目錄 —— **只在 `user://` 下可靠**。
##    `res://` 的素材包請走 `pack_load_set()`（導出包裡枚舉不到，見 `pack_probe_names`）。
static func dnf_load_dir(who: String, dir_path: String) -> Dictionary:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return _dnf_empty(who)
	var names: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".png"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	return dnf_load_names(who, dir_path, names)


## 幀檔名清單 → clip 集。與 `dnf_load_dir` 共用同一套解析/建構管線，
## 差別只在「清單怎麼來」（枚舉 vs 命名約定探測）。
static func dnf_load_names(who: String, dir_path: String, names: Array[String]) -> Dictionary:
	if names.is_empty():
		return _dnf_empty(who)
	names.sort()
	var parsed := dnf_parse_names(names)
	var embedded := String(parsed["who"])
	if not embedded.is_empty() and embedded != who:
		# 檔名內嵌的 who 與目錄名不符時，以**檔名**為準：目錄名只決定去哪找檔案，
		# 方向/動作的切分必須靠檔名，否則多個方向會被當成同一組 → 播出「混方向鬼影」。
		push_warning("frames: 目錄 '%s' 內檔名的 who 為 '%s'，以檔名為準" % [who, embedded])
	var clips := _dnf_build_clips(parsed["groups"], dir_path)
	if clips.is_empty():
		return _dnf_empty(who)
	# `frames` 語義：idle_s → walk_s → 首組（向下相容既有呼叫方）。
	var frames: Array = resolve_clip(clips, ANIM_IDLE, DIR_S, [])["frames"]
	if frames.is_empty():
		var first := _dnf_first_texture(clips)
		if first != null:
			frames.append(first)
	var canvas := float((frames[0] as Texture2D).get_height() if not frames.is_empty() else 0)
	return {
		"ok": true,
		"frames": frames,
		"clips": clips,
		"actions": _dnf_actions_of(clips),
		"canvas": canvas,
		"fps": 12.0,
		"anchor": "bottom-center",
		"source": "local",
	}


## 單幀精靈集（內建單張 / 用戶單檔）→ 合成 `idle` 一個動作、一個方向。
static func single_frame_set(tex: Texture2D, source: String) -> Dictionary:
	return {
		"ok": true,
		"frames": [tex],
		"clips": {ANIM_IDLE: {DIR_S: [tex]}},
		"actions": [ANIM_IDLE],
		"canvas": float(tex.get_height()),
		"fps": 12.0,
		"anchor": "bottom-center",
		"source": source,
	}


## 依「動作 → 方向」取幀陣列。回傳 `{frames: Array, exact: bool}`；
## `exact=false` 表示退到了別的動作（呼叫方據此決定要不要「停在末幀」）。
static func resolve_clip(clips: Dictionary, action: String, d: String,
		fallback: Array) -> Dictionary:
	if clips.is_empty():
		return {"frames": fallback, "exact": false}
	var order: Array = ANIM_FALLBACK.get(action, [ANIM_IDLE])
	for a in order:
		if not clips.has(a):
			continue
		var by_dir: Dictionary = clips[a]
		if by_dir.has(d) and not (by_dir[d] as Array).is_empty():
			return {"frames": by_dir[d], "exact": a == action}
		var keys: Array = by_dir.keys()
		keys.sort()
		if not keys.is_empty() and not (by_dir[keys[0]] as Array).is_empty():
			return {"frames": by_dir[keys[0]], "exact": a == action}
	return {"frames": fallback, "exact": false}


## 朝向向量 → 四方向字母。|x| > |y| 取左右，否則取上下（純上下時 y ≥ 0 = 南）。
static func dir_from_vector(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return DIR_E if v.x > 0.0 else DIR_W
	return DIR_S if v.y >= 0.0 else DIR_N


## 從檔名解析 `char_<who>_<action>_<dir>_<NN>.png`。
## ⚠️ `<who>` 可含底線（`skeleton_warrior` / `boss_bone_tyrant`），故**不能**按固定位置切，
##    一律用「最後三段」反推：末段 = 幀號，倒數第二 = 方向，倒數第三 = 動作，
##    其餘全部 = who。回傳 `{who, groups: {action: {dir: {frame_no: filename}}}}`。
static func dnf_parse_names(names: Array[String]) -> Dictionary:
	var groups: Dictionary = {}
	var who := ""
	for n in names:
		var base := n.get_basename()
		if not base.begins_with("char_"):
			continue
		var toks := base.substr(5).split("_")
		if toks.size() < 4:
			continue
		var frame_no := String(toks[toks.size() - 1]).to_int()
		var d := String(toks[toks.size() - 2])
		var action := String(toks[toks.size() - 3])
		var w := ""
		for i in toks.size() - 3:
			if i > 0:
				w += "_"
			w += String(toks[i])
		if w.is_empty() or action.is_empty() or d.is_empty():
			continue
		if who.is_empty():
			who = w
		if not groups.has(action):
			groups[action] = {}
		var by_dir: Dictionary = groups[action]
		if not by_dir.has(d):
			by_dir[d] = {}
		(by_dir[d] as Dictionary)[frame_no] = n
	return {"who": who, "groups": groups}


## `{action: {dir: {frame_no: filename}}}` → `{action: {dir: Array[Texture2D]}}`（依幀號排序）
static func _dnf_build_clips(groups: Dictionary, dir_path: String) -> Dictionary:
	var clips: Dictionary = {}
	for action in groups:
		var by_dir: Dictionary = {}
		for d in (groups[action] as Dictionary):
			var texs: Array = []
			for n in _dnf_sorted((groups[action] as Dictionary)[d]):
				var t := dnf_load_png_texture("%s/%s" % [dir_path, n])
				if t != null:
					texs.append(t)
			if not texs.is_empty():
				by_dir[String(d)] = texs
		if not by_dir.is_empty():
			clips[String(action)] = by_dir
	return clips


static func _dnf_actions_of(clips: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in clips:
		out.append(String(k))
	out.sort()
	return out


static func _dnf_first_texture(clips: Dictionary) -> Texture2D:
	var actions: Array = clips.keys()
	actions.sort()
	for a in actions:
		var dirs: Array = (clips[a] as Dictionary).keys()
		dirs.sort()
		for d in dirs:
			var arr: Array = (clips[a] as Dictionary)[d]
			if not arr.is_empty():
				return arr[0]
	return null


static func _dnf_empty(_who: String) -> Dictionary:
	return {"ok": false, "frames": [], "clips": {}, "actions": [],
			"canvas": 0.0, "fps": 12.0, "anchor": "bottom-center", "source": "missing"}


## 依「幀號」排序一組幀（key = 幀號 int，value = 檔名）。
static func _dnf_sorted(d: Dictionary) -> Array[String]:
	var nos := d.keys()
	nos.sort()
	var out: Array[String] = []
	for no in nos:
		out.append(String(d[no]))
	return out


## 讀 PNG 為 Texture2D。優先已 import 的資源；未 import 的新素材直接解檔，
## 避免「素材還沒被編輯器 import 就整批載不到」。
## `user://` 的用戶素材**永遠不會被 import**，故第二條分支是它的主路徑。
static func dnf_load_png_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var r: Resource = load(path)
		if r is Texture2D:
			return r
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		# 兜底：某些平台 / 版本下 `Image.load_from_file` 不吃 `user://` 虛擬路徑
		var abs := ProjectSettings.globalize_path(path)
		if abs != path and FileAccess.file_exists(abs):
			img = Image.load_from_file(abs)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


# =============================================================================
# 四、AI 主循环
# =============================================================================

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_refresh_player()
	_tick_state(delta)
	_tick_flash(delta)
	if _hitstun_timer > 0.0:
		_hitstun_timer = maxf(_hitstun_timer - delta, 0.0)

	# 通道 1：AI 速度（`_tick_state` 已写进 velocity）。先存进局部变量，
	# 免得击退污染下一帧的巡逻 / 追击速度。
	# 9.x 受击硬直：hitstun 期间 AI 移动速度打 0.25 折（打断追击，受击更有反馈）
	var move_velocity := velocity * (HITSTUN_SPEED_MULT if _hitstun_timer > 0.0 else 1.0)
	# 通道 2：击退（见 `apply_knockback`）。两通道**相加**后交给 move_and_slide 裁定地形。
	#
	# ⚠️ 这里必须是「重算」而不是 `velocity += _knockback_velocity`：
	#    velocity 是 CharacterBody2D 的**跨帧持久属性**，上一帧的击退量已经写进去了，
	#    这一帧再 += 一次 ⇒ 击退速度逐帧累积、位移发散（玩家侧实测 12px 走成 61.4px）。
	velocity = move_velocity + _knockback_velocity
	move_and_slide()
	# 衰减放在位移**之后**：本帧按完整初速走，位移量才符合 v0 = sqrt(2·a·L) 的换算。
	if _knockback_velocity != Vector2.ZERO:
		_knockback_velocity = _knockback_velocity.move_toward(
			Vector2.ZERO, KNOCKBACK_DECAY * delta)
		if _knockback_velocity.length() < KNOCKBACK_STOP_EPSILON:
			_knockback_velocity = Vector2.ZERO
	# 只把 AI 通道写回，击退不残留到下一帧
	velocity = move_velocity


## 每帧刷新目标引用。
## ⚠️ `_player` 這個變數名在本類語義是「當前目標」（歷史命名）；召喚物語境下
##    它指向怪物，而非玩家 —— 由 `target_group` 決定，讀者請以此為準。
##
## 候選策略（2026-09-28 修，召喚系統 B1 收尾）：
##   * **怪物**（`target_group = "player"`，預設）：候選 = `player` 組 ∪ `summons` 組，
##     兩組裡**離自己最近**的節點。這是灵狼 / 元素僕從能「拉得住仇恨」的關鍵 —— 玩家
##     跑遠、召喚物擋在中間時，怪物會自動切打召喚物；玩家貼近時又會切回玩家。
##   * **玩家召喚物 / BOSS minions**（`target_group = "enemies"`）：候選固定為
##     `enemies` 組（找最近怪物）。由 `target_group` 控分流，兩個語義天然不混。
##
## 註：BOSS 召喚的 minions 用 `target_group = "enemies"`，不會被本邏輯誤打到自己人；
##     玩家召喚物（`is_summon = true` ⇒ `summons` 組）才進入候選 —— 兩個分流天然不混。
func _refresh_player() -> void:
	# 取指定群組（敵人的特例加進 `summons` ⇒ 灵狼能拉仇恨），逐一比距離，取最近者。
	# get_nodes_in_group 在本項目單位數量級（個位數到十幾隻）下成本低。
	var tree := get_tree()
	if tree == null:
		_player = null
		return
	var primary := StringName(target_group)
	var candidate_groups: Array = [primary]
	if primary == &"player":
		candidate_groups.append(&"summons")
	var best: Node2D = null
	var best_d2 := INF
	for grp_name in candidate_groups:
		for node in tree.get_nodes_in_group(grp_name):
			if not (node is Node2D) or not is_instance_valid(node):
				continue
			var n2d := node as Node2D
			var d2 := n2d.global_position.distance_squared_to(global_position)
			if d2 < best_d2:
				best_d2 = d2
				best = n2d
	_player = best


## 移動速度（px/s）。預設 = 怪物表 `move_speed` × 詞綴移速乘區 × 臨時增益移速乘區。
## 友方召喚物覆寫本方法以**每幀動態跟隨玩家**（見 `scripts/combat/summon.gd`）。
func _move_speed() -> float:
	var speed := data.move_speed * _move_mult
	# 第四步 B4 3-B3：临时增益减速（`ms_boost` / `move_speed`，百分数增量，负值即减速）
	if buff_component != null:
		var ms := buff_component.get_stat_bonus("move_speed")
		if not is_zero_approx(ms):
			speed *= maxf(1.0 + ms / 100.0, 0.0)
	return speed


## 索敵半徑（px）：目標入此範圍才由巡邏轉為追擊。預設沿用全域常量。
## 召喚物覆寫以符合規格 §12.2 的「靈狼 6 格 / 元素僕從 5 格」。
func _aggro_range() -> float:
	return GameConstants.ENEMY_AGGRO_RANGE


## 脫戰半徑（px）：目標超出此距離則回巡邏。預設沿用全域常量。召喚物覆寫。
func _lose_range() -> float:
	return GameConstants.ENEMY_LOSE_RANGE


## W5-1 · ranged_kiter / lobber 的「過近區」判定：目標比 `preferred_range` 更近。
##   過近 ⇒ 不進入 ATTACK（也不留在 ATTACK），改由 CHASE 的 `_chase_kite` /
##   `_chase_lobber` 執行**後退** —— 這是策劃 `ai_behavior_contract` 明寫的
##   「太近则后退」的落點。
##
##   ⚠️ 為什麼需要它（2026-09-28 B2 實測）：
##     `_tick_chase` 原本只在 `dist > attack_range` 時被呼叫，而全部帶
##     `preferred_range` 的怪都是 `attack_range > preferred_range`
##     ⇒ `dist > attack_range > pref + TOL` ⇒ 「後退 / 橫移」兩支**永不執行**，
##     只剩「前進」。此判定把 ATTACK 的進入條件收緊，讓過近時能落回 CHASE。
##   ⚠️ 必須**同時**出現在 `_tick_chase`（阻止進入）與 `_tick_attack`（主動退出），
##     否則會退化成「ATTACK ⇄ CHASE 每幀抖動」。
##   `preferred_range <= 0`（16 隻老怪的缺省）⇒ 恆 false ⇒ 行為與改動前逐位一致。
func _wants_back_off(dist: float) -> bool:
	return data.preferred_range > 0.0 and dist < data.preferred_range - _KITE_RANGE_TOL


## 状态分派
func _tick_state(delta: float) -> void:
	# 6.2 词缀：闪现（每 6 秒瞬移到玩家附近）
	if AffixController.has(affixes, "phasing") and _player != null:
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			_phase_timer = float(AffixController.AFFIXES.get("phasing", {}).get("interval", 6.0))
			global_position = _player.global_position \
				+ Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
	var dist := INF
	if _player != null:
		dist = global_position.distance_to(_player.global_position)
	# W5-5 · BOSS 远程招式（fireball）：**独立于普攻与 AI 状态**计时。
	# 为什么必须独立：`_cast_boss_skill()` 只在普攻命中时跑，而 BOSS 的 `attack_range`
	# 只有 70–80px —— 把「远程火球」挂在近战普攻上，等于要求 BOSS 贴身才能远程攻击。
	# 只在已交战（非 PATROL）时放，避免 BOSS 隔着半张图狙玩家。
	if _player != null and state != AIState.PATROL and _boss_skills.has("fireball"):
		_fireball_timer -= delta
		if _fireball_timer <= 0.0:
			_fireball_timer = float(boss_config.get("fireball_interval", 4.0))
			_cast_fireball()
	match state:
		AIState.PATROL:
			_tick_patrol(delta)
			if _player != null and dist <= _aggro_range():
				_set_state(AIState.CHASE)
		AIState.CHASE:
			_tick_chase(delta, dist)
		AIState.ATTACK:
			_tick_attack(delta, dist)


## 巡逻：出生点半径内随机游走，到达后歇一会儿再换点
func _tick_patrol(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		velocity = Vector2.ZERO
		return
	if global_position.distance_to(_patrol_target) <= GameConstants.ENEMY_PATROL_ARRIVE_TOLERANCE:
		velocity = Vector2.ZERO
		_patrol_wait = randf_range(
			GameConstants.ENEMY_PATROL_WAIT_MIN, GameConstants.ENEMY_PATROL_WAIT_MAX)
		_patrol_target = _random_patrol_point()
		return
	velocity = global_position.direction_to(_patrol_target) * _move_speed()
	facing = velocity.normalized()


## 追击：朝玩家直线移动；距离恢复前不换向（俯视 ARPG 无寻路，直线最贴近直觉）
## 6 种 ai_id 的 CHASE 行为**全部**在本 match 内具名分派（任务 W5-1）：
##   melee_chaser / boss_phased → `_chase_melee`（基准直冲）
##   ranged_kiter → `_chase_kite`｜erratic_chaser → `_chase_erratic`
##   lobber → `_chase_lobber`｜melee_charger → `_chase_charger`
## `_:` 只服务**未知 ai_id**（数据错配），不作为任何一种已声明行为的落点。
func _tick_chase(delta: float, dist: float) -> void:
	if _player == null or dist > _lose_range():
		velocity = Vector2.ZERO
		_set_state(AIState.PATROL)
		return
	# 進入 ATTACK 需同時滿足：進入攻擊距離 **且** 沒有「過近後撤」訴求。
	# 後者是 ranged_kiter / lobber 的「太近則後退」（見 `_wants_back_off`）。
	if dist <= data.attack_range and not _wants_back_off(dist):
		velocity = Vector2.ZERO
		# 面向玩家（攻击判定扇区中轴）
		facing = global_position.direction_to(_player.global_position).normalized()
		_set_state(AIState.ATTACK)
		return
	var dir := global_position.direction_to(_player.global_position)
	match data.ai_id:
		"melee_chaser":
			# 直线追击（基准行为）：直冲贴身
			_chase_melee(dir)
		"ranged_kiter":
			_chase_kite(delta, dist, dir)
		"erratic_chaser":
			_chase_erratic(delta, dist, dir)
		"lobber":
			_chase_lobber(delta, dist, dir)
		"melee_charger":
			_chase_charger(delta, dist, dir)
		"boss_phased":
			# BOSS 阶段：移速低，追击同 melee_chaser；招式由
			# `_check_boss_phase` / `_cast_boss_skill` 接管（ai_id 此处仅作标签）
			_chase_melee(dir)
		_:
			# 未知 ai_id（数据错配）：退回基准直冲，不静默站桩
			_chase_melee(dir)
	facing = velocity.normalized()


## 攻击：停在 attack_range 内，按 attack_interval 输出伤害事件
## 6 种 ai_id 的 ATTACK 行为在 `_attack_kiter / _attack_lob` 内分派（任务 W5-1）；
## 其余（melee_chaser / erratic_chaser / melee_charger / boss_phased）走默认
## `_attack_player`（近战弧）。
func _tick_attack(delta: float, dist: float) -> void:
	velocity = Vector2.ZERO
	if _player == null or dist > _lose_range():
		_set_state(AIState.PATROL)
		return
	# 退出 ATTACK 的兩種情形：目標出了攻擊距離，**或** 已進入「過近後撤」區
	# （後者讓 ranged_kiter / lobber 真的會後退，而非貼臉站樁射擊）。
	if dist > data.attack_range or _wants_back_off(dist):
		_set_state(AIState.CHASE)
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = data.attack_interval * _boss_interval_mult
		match data.ai_id:
			"ranged_kiter":
				_attack_kiter()
			"lobber":
				_attack_lob()
			_:
				# melee_chaser / erratic_chaser / melee_charger / boss_phased
				_attack_player()


# =============================================================================
# 四·五、AI 行为分派（W5-1 · 6 种 ai_id 的行为微调）
# =============================================================================
#
# 设计要点：
#   * 不重写状态机骨架（仍保持 PATROL→CHASE→ATTACK）。
#   * 不引入寻路 / NavigationAgent2D（全部行为在 move_and_slide 基础上做）。
#   * 不动 `_aoe_strike` 内部（BOSS 阶段技能已经依赖它）⇒ lobber 走
#     `_attack_lob` + `_lob_impact` 的 inline 新版 AoE，参数化半径 / 蓄力。
#   * 投射物 inline 在 `scripts/enemies/enemy_projectile.gd`，不新建 .tscn。
#
# 行为 → ai_id 映射（6 种全部在 `_tick_chase` / `_tick_attack` 的 match 中具名分派）：
#   melee_chaser    直线追击（基准）：CHASE 直冲，ATTACK 近战弧
#   ranged_kiter    CHASE 保持 preferred_range，ATTACK 发投射物
#   erratic_chaser  CHASE 方向加正弦扰动，ATTACK 近战弧
#   lobber          CHASE 半速 + 保持距离，ATTACK 落点 AoE
#   melee_charger   CHASE 蓄力→冲刺，ATTACK 近战弧（撞人由冲刺速度完成命中）
#   boss_phased     直线追击（同 melee_chaser）；招式走阶段系统
#                   `_check_boss_phase` / `_cast_boss_skill`，ai_id 此处仅作标签
#
# ⚠️ ATTACK 侧只有 ranged_kiter / lobber 需要独立分支（其余 4 种同为近战弧，
#    落到 `_attack_player()`）；但 CHASE 侧 6 种**各有具名 case** —— 这是
#    策划校验 `05-check_monster_level_boss.py` 的 C5 断言的直接对象，别把
#    melee_chaser / boss_phased 再塞回 `_:`。


## W5-1 · melee_chaser / boss_phased 追擊：直線直沖（基準行為）。
##   抽成獨立函式，讓 6 種 ai_id 在 `_tick_chase` 各有具名分支，
##   並使 `_:` 只承擔「未知 ai_id 兜底」而不承載任何已聲明行為。
func _chase_melee(dir: Vector2) -> void:
	velocity = dir * _move_speed()


## W5-1 · ranged_kiter 追擊：保持 `data.preferred_range`
##   太近 → 後退；太遠 → 進；中間 → 垂直橫移（半速）。
##   `preferred_range <= 0`（缺省）→ 回退到普通直沖，向後相容老怪。
const _KITE_RANGE_TOL: float = 10.0
func _chase_kite(_delta: float, dist: float, dir: Vector2) -> void:
	var pref := data.preferred_range
	if pref <= 0.0:
		velocity = dir * _move_speed()
		return
	if dist < pref - _KITE_RANGE_TOL:
		velocity = -dir * _move_speed()
	elif dist > pref + _KITE_RANGE_TOL:
		velocity = dir * _move_speed()
	else:
		# 垂直方向（左手）橫移，保持「對玩家視線切向」
		var perp := Vector2(-dir.y, dir.x)
		velocity = perp * _move_speed() * 0.5


## W5-1 · erratic_chaser 追擊：方向加正弦擾動（幅度 / 頻率由 data 決定）。
##   offset 直接加到 base velocity 上；move_and_slide 會用地形裁掉穿牆分量。
func _chase_erratic(delta: float, _dist: float, dir: Vector2) -> void:
	_erratic_phase += delta
	var perp := Vector2(-dir.y, dir.x)
	var offset := perp * data.erratic_amplitude * sin(_erratic_phase * TAU * data.erratic_frequency)
	velocity = dir * _move_speed() + offset


## W5-1 · lobber 追擊：半速移動 + 保持 `data.preferred_range`。
##   `preferred_range <= 0`（缺省）→ 一律半速直沖（向後相容 slime_acid /
##   mushroom_spore 兩隻老 lobber）。
func _chase_lobber(_delta: float, dist: float, dir: Vector2) -> void:
	var half := _move_speed() * 0.5
	var pref := data.preferred_range
	if pref <= 0.0:
		velocity = dir * half
		return
	if dist < pref - _KITE_RANGE_TOL:
		velocity = -dir * half
	elif dist > pref + _KITE_RANGE_TOL:
		velocity = dir * half
	else:
		velocity = Vector2.ZERO


## W5-1 · melee_charger 追擊：進入 `charge_range` 先蓄力（停下）`charge_windup`
## 秒，再以 `charge_speed_mult × move_speed` 直線衝刺玩家；玩家跑出
## `charge_range × 2.0` 視為衝刺失敗、退回普通直沖。
func _chase_charger(delta: float, dist: float, dir: Vector2) -> void:
	if dist > data.charge_range:
		# 玩家在 charge_range 外 → 重置蓄力 / 衝刺旗標，回普通直沖
		_charge_windup_t = 0.0
		_charging = false
		velocity = dir * _move_speed()
		return
	if _charge_windup_t > 0.0:
		# 蓄力中
		_charge_windup_t -= delta
		velocity = Vector2.ZERO
		if _charge_windup_t <= 0.0:
			_charging = true
		return
	if not _charging:
		# 首次進入 charge_range：點火蓄力
		_charge_windup_t = data.charge_windup
		velocity = Vector2.ZERO
		return
	# 衝刺中：玩家跑太遠就退回普通直沖
	if dist > data.charge_range * 2.0:
		_charging = false
		velocity = dir * _move_speed()
		return
	velocity = dir * _move_speed() * data.charge_speed_mult


## W5-1 · ranged_kiter 攻擊：發射投射物（inline EnemyProjectile，朝玩家位置直飛）。
## 不觸發近戰命中判定 / 不施加元素異常（讓遠程怪的毒 / 感電必須走近戰管線），
## 否則遠程怪會把異常做成「穩定上毒」。
func _attack_kiter() -> void:
	if _player == null:
		return
	_play_anim_oneshot(ANIM_ATTACK, minf(data.attack_interval, ATTACK_ANIM_MAX))
	var host := get_parent()
	if host == null:
		return
	var proj := EnemyProjectile.new()
	var dir := global_position.direction_to(_player.global_position)
	var dmg := data.get_damage(level, difficulty_tier) * _boss_dmg_mult
	# 壽命：飛越 attack_range × 2 的時間，下限 1.5s（防 0）
	var life := maxf(data.attack_range * 2.0 / maxf(data.projectile_speed, 1.0), 1.5)
	proj.setup(dir, data.projectile_speed, dmg, data.element, self, life)
	proj.global_position = global_position
	host.add_child(proj)


## W5-1 · lobber 攻擊：inline 新版 AoE（**不**��� `_aoe_strike` 內部）。
##   警示圈 → 延遲命中，半徑 = `data.lob_radius`、蓄力 = `data.lob_windup`、
##   傷害 × 0.9（與 BOSS 的 `_aoe_strike` 同口徑）。
func _attack_lob() -> void:
	if _player == null:
		return
	_play_anim_oneshot(ANIM_ATTACK, minf(data.attack_interval, ATTACK_ANIM_MAX))
	var host := get_parent()
	if host == null:
		return
	var radius := data.lob_radius
	var windup := data.lob_windup
	var dmg := data.get_damage(level, difficulty_tier) * _boss_dmg_mult * 0.9
	var tel := AoETelegraph.new()
	tel.position = global_position
	host.add_child(tel)
	tel.setup(radius, windup)
	var t := get_tree().create_timer(windup)
	t.timeout.connect(func() -> void: _lob_impact(dmg, radius))


## W5-1 · lobber AoE 命中結算（`_aoe_impact` 的 lobber 對應版本）。
##   與 BOSS 的 `_aoe_impact` 同形不同半徑：玩家在 `radius` 內則結算。
func _lob_impact(dmg: float, radius: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > radius:
		return
	if _player.has_method("take_damage"):
		_player.take_damage(dmg, self)
	EventBus.damage_dealt.emit(_player, dmg, false, data.element)
	print("[Lobber] %s 抛擲命中玩家 -%.1f" % [data.display_name, dmg])


## 输出一次攻击：命中判定（朝玩家 120° 扇区 + 玩家无敌尊重）通过才发事件。
## 玩家 2.6 前无生命组件，`damage_taken` 只作事件广播；若目标已实现契约直接调用。
func _attack_player() -> void:
	if _player == null:
		return
	# 揮擊動畫：**揮空也播**（玩家看得見敵人出手，才讀得到節奏）。
	# 只設一個表現計時器，不碰 `_attack_timer` / 命中判定 / 傷害。
	_play_anim_oneshot(ANIM_ATTACK, minf(data.attack_interval, ATTACK_ANIM_MAX))
	# 2.5 命中判定：玩家在攻击弧内（attack_range + 玩家命中半径）且不在无敌帧
	var hit := HitQuery.arc(
		global_position,
		facing,
		data.attack_range,
		GameConstants.ENEMY_ATTACK_ARC_DEG,
		[_player],
	)
	if hit.is_empty():
		print("[Enemy] %s 挥空（玩家在攻击弧外或无敌人）" % data.display_name)
		return
	if _player.has_method("is_invulnerable") and bool(_player.call("is_invulnerable")):
		print("[Enemy] %s 挥空（玩家闪避无敌帧）" % data.display_name)
		return
	var dmg := data.get_damage(level, difficulty_tier) * _boss_dmg_mult
	EventBus.damage_taken.emit(self, dmg, data.element)
	# 2.8 打击感：敌人命中也是「damage_dealt」——飘字 / 震屏 / 顿帧统一走这条总线
	EventBus.damage_dealt.emit(_player, dmg, false, data.element)
	if _player.has_method("take_damage"):
		_player.take_damage(dmg, self)
	# 2.6 异常状态：按怪物表 element 附加（毒→中毒 / 火→燃烧 / 冰→冰冻；物理/雷电无）
	if _player.has_method("apply_ailment_from_element"):
		_player.apply_ailment_from_element(data.element, self)
	# 6.2 词缀：吸血（攻击回复自身 HP）/ 回响（30% 概率补一击）
	if AffixController.has(affixes, "lifesteal") and health != null:
		health.current_hp = minf(health.max_hp_override, health.current_hp + dmg * 0.2)
	if AffixController.has(affixes, "echo") and randf() < 0.3:
		if _player.has_method("take_damage"):
			_player.take_damage(dmg, self)
			# 6.6 音效：回响补击不经 damage_dealt 总线，此处补打击声
			AudioManager.play("hit_melee")
	# 6.3 BOSS 阶段技能：召唤（按阶段数量生成杂兵）/ 范围技能对玩家生效
	if not _boss_skills.is_empty():
		_cast_boss_skill()
	print("[Enemy] %s 攻击 %s -%.1f %s" % [data.display_name, _player.name, dmg, data.element])


func _set_state(next: AIState) -> void:
	if state == next:
		return
	state = next
	if next == AIState.ATTACK:
		_attack_timer = 0.0  # 追上立刻打第一下，不给玩家白嫖窗口
	print("[Enemy] %s → %s" % [data.display_name, STATE_NAMES[next]])


## 随机巡逻点：出生点为圆心、PATROL_RADIUS 为半径的圆内
func _random_patrol_point() -> Vector2:
	var angle := randf() * TAU
	var r := randf() * GameConstants.ENEMY_PATROL_RADIUS
	return _spawn_point + Vector2(cos(angle), sin(angle)) * r


# =============================================================================
# 五、受击契约（2.2/2.3 与 DamageDummy 同接口；2.7 收编统一组件）
# =============================================================================

## 受击入口（契约）。amount 为最终伤害（玩家攻击管线已按敌人护甲减伤）；
## source 为攻击方。转发到生命组件（apply_mitigation=false 不再二次减伤）。
func take_damage(amount: float, source: Node) -> void:
	if is_dead:
		return
	# 6.2 词缀：荆棘（受击反弹 15% 伤害给攻击方）
	if AffixController.has(affixes, "thorn") and source != null \
			and source.has_method("take_damage"):
		source.take_damage(amount * 0.15, self)
	_flash_hit()
	if health != null:
		# 受擊動畫只在**真的掉血**時播（無敵 / 護盾全吸收 / 0 傷害都不播），
		# 純表現層，不改變任何結算。
		var hp_before := health.get_current_hp()
		health.take_damage(amount, source)
		if health.get_current_hp() < hp_before:
			_play_anim_oneshot(ANIM_HURT, HURT_ANIM_DURATION)
			_hitstun_timer = HITSTUN_DURATION  # 9.x：真掉血才打断追击
		_check_boss_phase()


## BOSS 阶段检测：HP 比例越过阈值 → 升阶段（技能集扩展 + 数值乘区 + 广播）
func _check_boss_phase() -> void:
	if boss_config.is_empty() or health == null:
		return
	var ratio := 1.0
	if health.max_hp_override > 0.0:
		ratio = health.current_hp / health.max_hp_override
	var thresholds: Array = boss_config.get("thresholds", [0.75, 0.5, 0.25])
	var next_phase := BossPhaseController.current_phase(ratio, thresholds)
	if next_phase > _boss_phase:
		_apply_boss_phase(next_phase)
		EventBus.boss_phase_changed.emit(self, next_phase, _boss_skills)
		print("[Boss] %s 进入阶段 %s（HP %.0f%%）" % [data.display_name,
			BossPhaseController.PHASE_NAMES[next_phase - 1], ratio * 100.0])


## 应用 BOSS 阶段：技能集 / 伤害乘区 / 狂暴攻速乘区
func _apply_boss_phase(phase: int) -> void:
	_boss_phase = phase
	_boss_skills = BossPhaseController.phase_skills(boss_config, phase)
	_boss_dmg_mult = BossPhaseController.phase_damage_mult(boss_config, phase)
	var er := BossPhaseController.enrage_multipliers(boss_config, phase)
	_boss_interval_mult = float(er["interval_mult"])
	if BossPhaseController.is_enraged(boss_config, phase):
		_boss_dmg_mult *= float(er["damage_mult"])
		# W5-5 · 狂暴**表现**：进狂暴阶段的那一帧放一次全屏红闪（素材 `fx_enrage_flash`）。
		# ⚠️ 刻意放在这里而不是 `_cast_boss_skill()`：`enrage` 是**一次性**事件，而
		#    `_cast_boss_skill()` 每次普攻都会跑 —— 放那边会变成「狂暴期间每 2 秒闪一次」。
		if _boss_skills.has("enrage") and not _enrage_fx_played:
			_enrage_fx_played = true
			_play_enrage_flash()
	# 6.6 音效：BOSS 阶段切换 → 低吼扫频
	AudioManager.play("boss_phase")


## 阶段技能施放（**近战耦合支线**）：召唤（冷却控制）/ 扇形重击 / 范围践踏。
##
## ⚠️ 本函数只在 BOSS **普攻命中**时被调用（`_attack_player()` 末尾），所以放在这里的
##    技能必须「贴身释放」才合理。另外两个标志性技能**刻意不在这里**：
##      · `fireball` → `_tick_state()`（远程招式不能要求贴身，见该处注释）
##      · `enrage`   → `_apply_boss_phase()`（一次性事件，不能按普攻节奏重播）
func _cast_boss_skill() -> void:
	if _player == null:
		return
	var tick := data.attack_interval * _boss_interval_mult
	var has_summon := _boss_skills.has("summon_skeleton") or _boss_skills.has("summon_imp")
	var has_aoe := _boss_skills.has("shockwave") or _boss_skills.has("magma_eruption")
	if has_summon:
		_summon_timer -= tick
		if _summon_timer <= 0.0:
			_summon_timer = float(boss_config.get("summon_interval", 8.0))
			_summon_minions()
	# W5-5 · 骸骨暴君招牌「前方扇形重击」：与普攻同节奏 tick，但有独立冷却，
	# 否则每一下普攻都叠一发扇形重击（伤害翻倍且预警圈刷屏）。
	if _boss_skills.has("bone_slam"):
		_slam_timer -= tick
		if _slam_timer <= 0.0:
			_slam_timer = float(boss_config.get("slam_interval", 5.0))
			_bone_slam()
	if has_aoe:
		_aoe_strike()


## 召唤杂兵：按阶段数量从召唤池生成（占位色块，同敌人场景）
func _summon_minions() -> void:
	var pool: Array = boss_config.get("summon_pool", [])
	if pool.is_empty():
		return
	var count := BossPhaseController.summon_count_for(boss_config, _boss_phase)
	var scene: PackedScene = load("res://scenes/enemies/enemy_base.tscn")
	for i in count:
		if pool.is_empty():
			return
		var mid := String(pool[randi() % pool.size()])
		var minion: EnemyBase = scene.instantiate()
		minion.monster_id = mid
		minion.level = level
		minion.difficulty_tier = difficulty_tier
		get_parent().add_child(minion)
		minion.global_position = global_position + Vector2(randf_range(-50.0, 50.0),
			randf_range(-50.0, 50.0))


## 范围技能（践踏 / 熔岩喷发）：以 BOSS 为中心 AoE。
## 9.x：改为「警示 → 延迟命中」两段——先在地面画 0.6s 红色圆环（可反应），
## 再结算伤害。避免瞬发不可避（公平性/手感）。
const AOE_TELEGRAPH_TIME: float = 0.6
const AOE_RADIUS: float = 110.0

func _aoe_strike() -> void:
	if _player == null:
		return
	_spawn_aoe_telegraph(AOE_RADIUS)
	var dmg := data.get_damage(level, difficulty_tier) * _boss_dmg_mult * 0.9
	var timer := get_tree().create_timer(AOE_TELEGRAPH_TIME)
	timer.timeout.connect(func() -> void: _aoe_impact(dmg))


## 警示视觉：地面红色闪烁圆环（Node2D 自绘，`life` 秒后自毁）
##
## W5-5：加三个**可选**参数以支持扇形（`arc_deg < 360` + `dir` 中轴）与自定义预警时长。
## 缺省 = 整圆 + `AOE_TELEGRAPH_TIME`，与改前逐位一致
## （`_aoe_strike` / `_attack_lob` 都不传后三个参数）。
func _spawn_aoe_telegraph(radius: float, arc_deg: float = 360.0,
		dir: Vector2 = Vector2.ZERO, life: float = -1.0) -> void:
	var host := get_parent()
	if host == null:
		return
	var dur := AOE_TELEGRAPH_TIME if life <= 0.0 else life
	var tel := AoETelegraph.new()
	tel.position = global_position
	host.add_child(tel)
	tel.setup(radius, dur, arc_deg, dir)


## 命中结算（警示结束后调用）
func _aoe_impact(dmg: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > AOE_RADIUS:
		return
	if _player.has_method("take_damage"):
		_player.take_damage(dmg, self)
	EventBus.damage_dealt.emit(_player, dmg, false, data.element)
	print("[Boss] %s 范围技能命中玩家 -%.1f" % [data.display_name, dmg])


# =============================================================================
# 五·六、W5-5 · BOSS 标志性技能（bone_slam / fireball / enrage 表现）
# =============================================================================
#
# 策划 05 §3.4① 的口径：`bone_slam` / `fireball` / `enrage` 此前是**死数据**
# （`phase_skills` 里写了，`enemy_base.gd` 零消费）。本节把三个都接上。
#
# ⚠️ 三者的**挂载点刻意不同**，不是随手放的：
#   · `bone_slam` → `_cast_boss_skill()`：近战招式，贴身释放合理
#   · `fireball`  → `_tick_state()`：远程招式，不能要求贴身（否则没有远程手段）
#   · `enrage`    → `_apply_boss_phase()`：一次性事件，不能按普攻节奏重播

## 扇形重击参数（策划 05 §3.4①：前方 120° 扇形、半径 `attack_range × 1.6`、预警 0.4s）
const BONE_SLAM_ARC_DEG: float = 120.0
const BONE_SLAM_RANGE_MULT: float = 1.6
const BONE_SLAM_TELEGRAPH_TIME: float = 0.4
const BONE_SLAM_DAMAGE_MULT: float = 1.4

## 火球参数（策划 05 §3.4①：1–3 发慢速火球、速度 ~140、命中给燃烧）
const FIREBALL_SPEED: float = 140.0
const FIREBALL_COUNT_MAX: int = 3
const FIREBALL_SPREAD_DEG: float = 14.0
const FIREBALL_LIFE: float = 3.0
const FIREBALL_VISUAL_ID: String = "bolt_fire"


## 骸骨暴君 · 前方扇形重击：地面 0.4s 预警 → 延迟结算。
## 与 `_aoe_strike()` 同范式（先画预警圈再结算），差别只在「判定形状」：
## 整圆 → 以 `dir` 为中轴的 ±60° 扇形。玩家可以横向走位躲开。
func _bone_slam() -> void:
	if _player == null:
		return
	var dir := global_position.direction_to(_player.global_position)
	if dir.length_squared() <= 0.0:
		dir = facing if facing.length_squared() > 0.0 else Vector2.RIGHT
	dir = dir.normalized()
	var radius := data.attack_range * BONE_SLAM_RANGE_MULT
	_spawn_aoe_telegraph(radius, BONE_SLAM_ARC_DEG, dir, BONE_SLAM_TELEGRAPH_TIME)
	var host := get_parent()
	if host != null:
		FxTable.spawn("fx_bone_slam", global_position + dir * radius * 0.45,
			{"host": host, "rotation": dir.angle()})
	var dmg := data.get_damage(level, difficulty_tier) * _boss_dmg_mult * BONE_SLAM_DAMAGE_MULT
	var timer := get_tree().create_timer(BONE_SLAM_TELEGRAPH_TIME)
	timer.timeout.connect(func() -> void: _cone_impact(dmg, radius, dir))


## 扇形命中结算（预警结束后调用）：距离 ≤ `radius` **且** 落在中轴 ±ARC/2 内才命中。
##
## 与 `_aoe_impact()` 同口径地**不**额外查无敌帧 —— `take_damage` 内部自会处理
## 闪避/格挡；这里只做「位置判定」，不做「减伤判定」。
func _cone_impact(dmg: float, radius: float, dir: Vector2) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector2 = _player.global_position - global_position
	if to_player.length() > radius:
		return
	if to_player.length_squared() > 0.0:
		var half_cos := cos(deg_to_rad(BONE_SLAM_ARC_DEG * 0.5))
		if dir.dot(to_player.normalized()) < half_cos:
			return
	if _player.has_method("take_damage"):
		_player.take_damage(dmg, self)
	EventBus.damage_dealt.emit(_player, dmg, false, data.element)
	print("[Boss] %s 扇形重击命中玩家 -%.1f" % [data.display_name, dmg])


## 熔心之主 · 火球：按阶段发 1–3 发扇形散开的慢速投射物，命中给燃烧。
##
## `ailment_element` 传 `data.element`（熔心之主 = `fire` ⇒ 燃烧）；
## 元素→异常的映射由 `HealthComponent.apply_ailment_from_element` 负责，
## 物理 / 雷电元素会自行返回空（不施加），所以这里不需要白名单。
func _cast_fireball() -> void:
	if _player == null:
		return
	var base_dir := global_position.direction_to(_player.global_position)
	if base_dir.length_squared() <= 0.0:
		base_dir = Vector2.RIGHT
	base_dir = base_dir.normalized()
	var host := get_parent()
	if host == null:
		return
	var count := clampi(_boss_phase, 1, FIREBALL_COUNT_MAX)
	var dmg := data.get_damage(level, difficulty_tier) * _boss_dmg_mult
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = deg_to_rad(FIREBALL_SPREAD_DEG) * (float(i) - float(count - 1) * 0.5)
		var d := base_dir.rotated(offset)
		var proj := EnemyProjectile.new()
		proj.setup(d, FIREBALL_SPEED, dmg, data.element, self, FIREBALL_LIFE,
			FIREBALL_VISUAL_ID, data.element)
		proj.global_position = global_position + d * 18.0
		host.add_child(proj)
	FxTable.spawn("pyromancer_cast", global_position, {"host": host})
	print("[Boss] %s 发射 %d 发火球" % [data.display_name, count])


## 狂暴表现：进狂暴阶段那一帧放一次**全屏红闪**（`fx_enrage_flash` 160×90 ⇒ ×5 ≈ 800×450）。
##
## 定位用**视口中心的世界坐标**（`canvas_transform` 逆变换）而不是 BOSS 自身位置 ——
## 相机跟随玩家，狂暴时 BOSS 可能在屏幕边缘，锚在 BOSS 身上会看不见。
func _play_enrage_flash() -> void:
	var host := get_parent()
	var vp := get_viewport()
	if host == null or vp == null:
		return
	var world_center: Vector2 = vp.get_canvas_transform().affine_inverse() \
		* (vp.get_visible_rect().size * 0.5)
	FxTable.spawn("fx_enrage_flash", world_center,
		{"host": host, "scale": Vector2(5.0, 5.0)})


## 死亡（组件广播 unit_died 后由 _on_unit_died 掉落 + 移除；本函数仅供外部触发）
func _die(_killer: Node) -> void:
	if health != null:
		health.die()


## 监听生命组件死亡广播：本怪死亡 → 掉落 + 移除（一次性）
func _on_unit_died(unit: Node, killer: Node) -> void:
	if unit != self or _loot_dropped:
		return
	_loot_dropped = true
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	# 6.6 音效：怪物死亡 → 下降扫频
	AudioManager.play("enemy_die")
	# 召喚物**不參與掉落**（規格 §12.4#3）：否則反覆召喚即是刷寶漏洞。
	# 詞綴爆炸一併短路（召喚物本無詞綴，這裡是防未來誤配的守門）。
	if not is_summon:
		# 6.2 词缀：爆炸（死亡时对周围 40px 造成 80% 攻击伤害）
		if AffixController.has(affixes, "explosive"):
			_explode()
		_drop_loot(killer)
	# 死亡动画：播在脫離本體的臨時精靈上（本體仍在本幀移除，時序不變）
	_spawn_death_anim()
	queue_free()


## 爆炸：对周围半径内的敌人组玩家造成词缀伤害（防御式，玩家可选）
func _explode() -> void:
	var def: Dictionary = AffixController.AFFIXES.get("explosive", {})
	var radius := float(def.get("radius", 40.0))
	var dmg_ratio := float(def.get("dmg_ratio", 0.8))
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= radius \
			and player.has_method("take_damage"):
		var dmg := data.get_damage(level, difficulty_tier) * dmg_ratio
		player.take_damage(dmg, self)
		EventBus.damage_dealt.emit(player, dmg, false, data.element)


## 掉落：按怪物档位掉落表 roll（金币 / 材料 / 装备），在死亡点周围撒出 LootDrop
func _drop_loot(killer: Node) -> void:
	var drops := LootRoller.roll_loot(
		data, level, difficulty_tier, _player_level(), _player_magic_find())
	for entry in drops:
		var drop := LOOT_SCENE.instantiate() as LootDrop
		drop.setup(entry)
		var scatter := Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		drop.global_position = global_position + scatter
		get_parent().add_child(drop)
	if not drops.is_empty():
		print("[Loot] %s 掉落 %d 件" % [data.display_name, drops.size()])


## 越级惩罚用玩家等级（玩家组第一人；无玩家 = 0 跳过惩罚）
##
## ⚠️ 方法名必须与 `PlayerController.get_player_level()` 严格一致。
##    这里用 has_method 探测是防 `_player` 不是玩家的兜底，但**拼错方法名会静默降级成 0** ——
##    曾经写成 `get_level`（PlayerController 里并不存在该方法），于是 has_method 恒为 false、
##    恒返回 0，导致 `LootRoller.roll_loot(..., 0)` 的**越级惩罚完全失效**，且不报任何错。
##    `tools/verify_fix93.tscn` 已补「有对象在场」分支断言来盯死这一条。
func _player_level() -> int:
	if _player != null and _player.has_method("get_player_level"):
		return int(_player.call("get_player_level"))
	return 0


## 玩家局内「幸运」加成（%，稀有度权重乘区）。消费方：`LootRoller.roll_loot`。
## 无玩家 / 无接口 → 0（掉落不变）。
##
## ⚠️ 与 `_player_level()` 同理：这里用 `has_method` 探测，**拼错方法名会静默降级成 0**。
##    故 `verify_choice_flow` 用「有对象在场」分支断言盯死这一条。
func _player_magic_find() -> float:
	if _player != null and _player.has_method("get_combat_stat"):
		return float(_player.call("get_combat_stat", "magic_find"))
	return 0.0


## 击退入口（契约）。offset 为位移向量（px）。
##
## 实现：把位移折算成初速放进**独立的击退通道**（`_knockback_velocity`），
## 由 `_physics_process` 与 AI 通道相加后交给 `move_and_slide()` 裁定地形
## ⇒ 撞墙会被挡住，不会穿进墙体 / 卡在几何体里。
##
## ⚠️ 与 `PlayerController.apply_knockback` **同签名、同语义**（方法名也别改：
##    `SkillController._hit` 靠 `has_method` 探测，改名会静默跳过且不报错）。
func apply_knockback(offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	# 线性衰减下 位移 L = v0² / (2a)  ⇒  v0 = sqrt(2·a·L)
	var l := offset.length()
	_knockback_velocity += offset.normalized() * sqrt(2.0 * KNOCKBACK_DECAY * l)


## 伤害管线读取接口（DamageCalc.target_*；怪物护甲来自数据 × 等级成长）。
## 第四步 B4 3-B3：再乘临时增益减甲乘区（`enemy_armor_reduction` → `pct_armor` 负值）。
func get_armor() -> float:
	var armor := data.get_armor(level)
	if buff_component != null:
		var pct := buff_component.get_stat_bonus("pct_armor")
		if not is_zero_approx(pct):
			armor *= maxf(1.0 + pct / 100.0, 0.0)
	return armor


## 临时增益组件（第四步 B4 3-B3）。`_ready()` 已建，恒非 null。
func get_buff_component() -> BuffComponent:
	return buff_component


## 元素抗性：2.4 怪物表未定义抗性，统一 0（阶段 3 词缀/特殊怪接入）
func get_resist(_element: String) -> float:
	return 0.0


func get_level() -> int:
	return level


## 受击命中半径（2.5 命中判定目标半径扩展）：敌人碰撞框 24×24 → 半宽 12px。
func get_hit_radius() -> float:
	return 12.0


## 主色（2.8 死亡粒子用）：与占位美术档位色一致（普通 暗红 / 精英 紫 / BOSS 金）
func get_display_color() -> Color:
	match data.tier:
		MonsterData.Tier.ELITE:
			return Color("7E44B8")
		MonsterData.Tier.BOSS:
			return Color("D9A521")
		_:
			return Color("8C1A1F")


## 攻击力接口（2.6 异常 dot 来源统一走 get_attack_damage；= 怪物表 DMG × 难度系数）
func get_attack_damage() -> float:
	return data.get_damage(level, difficulty_tier)


# =============================================================================
# 六、表现
# =============================================================================

## 受击闪白：亮一下再回落（最小打击反馈，2.8 由正式打击感管线接管）
func _flash_hit() -> void:
	if _body == null:
		return
	_body.modulate = Color(2.2, 2.2, 2.2)
	_flash_timer = 0.08


func _tick_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0 and _body != null:
		_body.modulate = Color.WHITE


func _solid_texture(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## 范围技能警示视觉（9.x 内部类）：红色闪烁圆环，淡出后自毁
##
## W5-5：加 `arc_deg` + `dir` 两个**可选**参数以支持**扇形**（`bone_slam` 的前方 120°）。
## 缺省 `arc_deg = 360` ⇒ 走原来的整圆分支，与改前逐位一致。
class AoETelegraph extends Node2D:
	var _radius: float = 110.0
	var _life: float = 0.6
	var _t: float = 0.0
	var _arc_deg: float = 360.0
	var _dir: Vector2 = Vector2.RIGHT

	func setup(radius: float, life: float, arc_deg: float = 360.0,
			dir: Vector2 = Vector2.ZERO) -> void:
		_radius = radius
		_life = life
		_arc_deg = arc_deg
		if dir.length_squared() > 0.0:
			_dir = dir.normalized()
		z_index = 40  # 盖在地面/敌人之上
		# 与 `FxSprite` 同一约定：把同类实例挂进组，让 verify / 抓图工具能数得出
		# 「场上此刻有几个预警圈」，而不是靠猜节点类型（内部类没法用 `is` 判）。
		add_to_group(&"aoe_telegraphs")

	func _process(delta: float) -> void:
		_t += delta
		if _t >= _life:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var alpha := 0.85 * (1.0 - _t / _life)
		var blink := 0.6 + 0.4 * sin(_t * 24.0)
		var col := Color(1.0, 0.25, 0.15, alpha * blink)
		# 整圆（缺省路径，`_aoe_strike` / `_attack_lob` 走这里）
		if _arc_deg >= 359.9:
			draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 40, col, 3.0)
			draw_arc(Vector2.ZERO, _radius * 0.88, 0.0, TAU, 32,
				Color(1.0, 0.5, 0.3, alpha * 0.5), 2.0)
			return
		# 扇形：中轴 `_dir`，张角 `_arc_deg`。外弧 + 两条半径边 + 半透明填充。
		var half := deg_to_rad(_arc_deg) * 0.5
		var mid := _dir.angle()
		var a0 := mid - half
		var a1 := mid + half
		draw_arc(Vector2.ZERO, _radius, a0, a1, 24, col, 3.0)
		draw_arc(Vector2.ZERO, _radius * 0.88, a0, a1, 20,
			Color(1.0, 0.5, 0.3, alpha * 0.5), 2.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(a0) * _radius, col, 2.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(a1) * _radius, col, 2.0)
		var pts := PackedVector2Array([Vector2.ZERO])
		var steps := 12
		for i in steps + 1:
			pts.append(Vector2.from_angle(lerpf(a0, a1, float(i) / float(steps))) * _radius)
		draw_colored_polygon(pts, Color(1.0, 0.3, 0.15, alpha * 0.18))
