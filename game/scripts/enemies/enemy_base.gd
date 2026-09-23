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

# =============================================================================
# 三、运行时状态
# =============================================================================

## 怪物数据（ConfigLoader 注入）
var data: MonsterData = null

## 生命组件（2.7 收编：HP / 受击 / 死亡；apply_mitigation=false 防双重减伤）
@onready var health: HealthComponent = $Health

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
	add_to_group(&"enemies")
	_spawn_point = global_position
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
	if data != null and data.tier == MonsterData.Tier.BOSS:
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
const PACK_ACTIONS: Array[String] = ["idle", "walk", "attack", "hurt", "death", "die"]
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


## 每帧刷新玩家引用（get_first_node_in_group 成本低，敌人数量少）
func _refresh_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player")


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
	match state:
		AIState.PATROL:
			_tick_patrol(delta)
			if _player != null and dist <= GameConstants.ENEMY_AGGRO_RANGE:
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
	velocity = global_position.direction_to(_patrol_target) * data.move_speed * _move_mult
	facing = velocity.normalized()


## 追击：朝玩家直线移动；距离恢复前不换向（俯视 ARPG 无寻路，直线最贴近直觉）
func _tick_chase(_delta: float, dist: float) -> void:
	if _player == null or dist > GameConstants.ENEMY_LOSE_RANGE:
		velocity = Vector2.ZERO
		_set_state(AIState.PATROL)
		return
	if dist <= data.attack_range:
		velocity = Vector2.ZERO
		# 面向玩家（攻击判定扇区中轴）
		facing = global_position.direction_to(_player.global_position).normalized()
		_set_state(AIState.ATTACK)
		return
	velocity = global_position.direction_to(_player.global_position) * data.move_speed * _move_mult
	facing = velocity.normalized()


## 攻击：停在 attack_range 内，按 attack_interval 输出伤害事件
func _tick_attack(delta: float, dist: float) -> void:
	velocity = Vector2.ZERO
	if _player == null or dist > GameConstants.ENEMY_LOSE_RANGE:
		_set_state(AIState.PATROL)
		return
	if dist > data.attack_range:
		_set_state(AIState.CHASE)
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = data.attack_interval * _boss_interval_mult
		_attack_player()


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
	if BossPhaseController.is_enraged(phase):
		_boss_dmg_mult *= float(er["damage_mult"])
	# 6.6 音效：BOSS 阶段切换 → 低吼扫频
	AudioManager.play("boss_phase")


## 阶段技能施放：召唤（冷却控制）/ 范围践踏（对玩家 AoE）
func _cast_boss_skill() -> void:
	if _player == null:
		return
	var has_summon := _boss_skills.has("summon_skeleton") or _boss_skills.has("summon_imp")
	var has_aoe := _boss_skills.has("shockwave") or _boss_skills.has("magma_eruption")
	if has_summon:
		_summon_timer -= data.attack_interval * _boss_interval_mult
		if _summon_timer <= 0.0:
			_summon_timer = float(boss_config.get("summon_interval", 8.0))
			_summon_minions()
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


## 警示视觉：地面红色闪烁圆环（Node2D 自绘，0.6s 后自毁）
func _spawn_aoe_telegraph(radius: float) -> void:
	var host := get_parent()
	if host == null:
		return
	var tel := AoETelegraph.new()
	tel.position = global_position
	host.add_child(tel)
	tel.setup(radius, AOE_TELEGRAPH_TIME)


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


## 伤害管线读取接口（DamageCalc.target_*；怪物护甲来自数据 × 等级成长）
func get_armor() -> float:
	return data.get_armor(level)


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
class AoETelegraph extends Node2D:
	var _radius: float = 110.0
	var _life: float = 0.6
	var _t: float = 0.0

	func setup(radius: float, life: float) -> void:
		_radius = radius
		_life = life
		z_index = 40  # 盖在地面/敌人之上

	func _process(delta: float) -> void:
		_t += delta
		if _t >= _life:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var alpha := 0.85 * (1.0 - _t / _life)
		var blink := 0.6 + 0.4 * sin(_t * 24.0)
		var col := Color(1.0, 0.25, 0.15, alpha * blink)
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 40, col, 3.0)
		draw_arc(Vector2.ZERO, _radius * 0.88, 0.0, TAU, 32, Color(1.0, 0.5, 0.3, alpha * 0.5), 2.0)
