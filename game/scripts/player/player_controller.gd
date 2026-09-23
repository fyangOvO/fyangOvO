## 玩家角色控制器（阶段 2 · 任务 2.1 / 2.2 · 单职业「战士」）
##
## 职责边界（2.1 + 2.2，别越界）：
##   ✅ 8 方向移动 + 加减速手感
##   ✅ 闪避（冲刺 + 无敌帧 + 冷却）
##   ✅ 8 方向朝向
##   ✅ **武器层三层精灵结构 + 主/副手锚点**（跨阶段硬依赖，GDD 风险 #6）
##   ✅ 普攻（假连段：按住连续挥击，同一段 8 帧动画循环）+ 技能输入转发（任务 2.2）
##   ✅ 生命契约宿主（任务 2.6：take_damage / get_armor / 异常转发；扣血逻辑在 HealthComponent）
##   ❌ 伤害公式（暴击/减伤）、生命值、异常状态 —— 属任务 2.3 / 2.6（组件）
##   ❌ 装备上身（把真实武器精灵挂到锚点上）—— 属阶段 3
##
## ⚠️ 本地常量说明：`game_constants.gd` 的 2.1 部分常量由早期成员维护，
##    为避免并发写冲突，**既有常量**沿用本地定义（数值相同）；
##    2.2 新增常量（攻击/技能/法力）统一引用 `GameConstants`（八·七段）。
##    阶段 3 统一迁移进 `GameConstants` 时删掉本节即可（数值不变）。
##
## 节点结构（**必须是最终形态**，阶段 3/6 直接往上挂资源）：
##   Player (CharacterBody2D)
##   ├── BodySprite          ← 身体层（护甲靠调色索引重着色，0 新增帧）
##   ├── WeaponLayer         ← 武器层容器（独立于身体层，因为武器帧与角色帧是两套资源）
##   │   ├── MainHandAnchor  ← 主手锚点（剑/斧/锤/匕首/法杖/长弓）
##   │   └── OffHandAnchor   ← 副手锚点（盾/法器/箭袋/副刃）
##   ├── FxLayer             ← 特效层（受击闪白、稀有度辉光、技能特效）
##   └── CollisionShape2D
##   绘制顺序即兄弟顺序：Body → Weapon → Fx（后画的盖住先画的）
class_name PlayerController
extends CharacterBody2D

# =============================================================================
# 一、朝向
# =============================================================================

## 8 方向朝向。序号是「从正下开始顺时针」，与美术 4 方向出图的映射见 `facing_to_4dir()`。
enum Facing8 {
	DOWN = 0,       ## 正下（面向镜头）
	DOWN_LEFT = 1,
	LEFT = 2,
	UP_LEFT = 3,
	UP = 4,         ## 正上（背对镜头）
	UP_RIGHT = 5,
	RIGHT = 6,
	DOWN_RIGHT = 7,
}

const FACING_COUNT: int = 8

# =============================================================================
# 二、移动（本地常量，阶段 3 迁移进 GameConstants）
# =============================================================================

## 单个 tile 的像素边长（GDD / 美术规范：32×32）
const LOCAL_TILE_SIZE: int = 32

## 移动速度：**4.5 tile/s = 144 px/s**。
##
## 取值依据：
##   - GDD **未定义**玩家移动速度（阶段 0 只定义了怪物数值），此为工程侧自定，待手感调优；
##   - 取「4.0–5.0 tile/s」区间中值，理由：暗黑类俯视 ARPG 的常规手感区间为 3–6 tile/s，
##     低于 3 会显得拖沓，高于 6 会削弱闪避与走位的意义；
##   - 换算：4.5 × 32 = 144 px/s。
##
## ⚠️ **待确认的隐患**：1920×1080 原生视口 + 32px tile ⇒ 一屏可见 **60 tile 宽**，
##    远大于同类作品的 20–30 tile。这会让「按屏幕感知」的移动显得很慢。
##    几乎可以肯定后续需要给 Camera2D 加 2× 左右缩放，届时**感知速度会翻倍**。
##    本值按「世界坐标真实速度」定义，不因相机缩放而变 —— 调手感时请连带考虑相机缩放。
const LOCAL_MOVE_SPEED: float = 144.0

## 加速度（px/s²）：0 → 满速约 0.12s。给一点起步缓冲，避免瞬发瞬停的塑料感。
const LOCAL_ACCELERATION: float = 1200.0

## 减速度（px/s²）：松手 → 停住约 0.09s。比加速度略快，让操作「跟手」。
const LOCAL_DECELERATION: float = 1600.0

# =============================================================================
# 二·五、击退（受击契约，与 `EnemyBase.apply_knockback` **同签名**）
# =============================================================================
#
# ⚠️ 契约完整性：`SkillController._hit` 用 `has_method("apply_knockback")` 探测目标，
#    **缺了就静默跳过**（不报错、不警告）。所以这个方法名必须与 EnemyBase 一字不差。
#
# 实现取向：**不**用 `position += offset`（那会瞬移 + 穿墙，且破坏像素网格对齐），
#    而是折算成初速放进**独立**的击退通道，与输入通道**相加**后交给 move_and_slide() 裁定地形。
#
# ⚠️ 叠加方式必须是「重算」，不能是「自加」：
#    写成 `velocity += _knockback_velocity` 会让击退逐帧累积发散（velocity 是跨帧持久属性），
#    实测请求 12px 位移会走成 61.4px。详见 `_physics_process` 内注释。

## 击退速度（px/s）。独立于输入速度，不吃 LOCAL_ACCELERATION/DECELERATION 曲线。
var _knockback_velocity: Vector2 = Vector2.ZERO

## 击退衰减率（px/s²）。线性衰减下「位移 L ↔ 初速 v0」满足 L = v0² / (2a)。
const KNOCKBACK_DECAY: float = 1200.0

## 击退速度下限（px/s）：低于此值直接归零。move_toward 虽会精确归零，
## 但留一个阈值可以避免「肉眼看不见的残余速度」继续每帧参与 move_and_slide。
const KNOCKBACK_STOP_EPSILON: float = 4.0

# =============================================================================
# 三、闪避（导出变量，供手感调优；GDD 未定义，工程侧自定）
# =============================================================================

## 冲刺距离（px）。88px ≈ 2.75 tile，约等于「一个身位多一点」，够穿过一次攻击判定。
@export var dodge_distance: float = 88.0

## 冲刺持续时间（秒）。距离 ÷ 时间 = 冲刺速度，故不单独导出速度，避免两者打架。
@export var dodge_duration: float = 0.18

## 无敌帧时长（秒）。**刻意长于冲刺时长**，留出「冲刺结束后仍能穿过攻击」的容错窗口。
@export var dodge_iframe_duration: float = 0.30

## 闪避冷却（秒）。从冲刺**开始**计时（不是结束后），否则实际间隔会变成 冷却+时长。
@export var dodge_cooldown: float = 0.80

## 冷却期间是否允许「预输入缓冲」（松开后再按会排队）
@export var dodge_input_buffer: bool = true

# =============================================================================
# 四、手部锚点几何（占位值，等美术产出后按 48×48 精灵重新标定）
# =============================================================================

## 手部距脚底中心的高度（px，负值向上）。原点在脚底中心（对齐美术规范 2.1 的锚点 (24,44)）。
const HAND_HEIGHT: float = -25.0

## 手部横向张距（px）：手相对身体中线的左右偏移量。
const HAND_SPREAD: float = 11.0

## 斜向朝向时 y 分量的衰减系数。
## 不衰减的话，斜向时「手」会按 45° 甩到脚下，看起来像掉在地上。
const HAND_SPREAD_Y_DAMP: float = 0.5

# =============================================================================
# 五、节点引用
# =============================================================================

@onready var body_sprite: Sprite2D = $BodySprite
@onready var weapon_layer: Node2D = $WeaponLayer
@onready var main_hand_anchor: Marker2D = $WeaponLayer/MainHandAnchor
@onready var off_hand_anchor: Marker2D = $WeaponLayer/OffHandAnchor
@onready var fx_layer: Node2D = $FxLayer

## 法力池（任务 2.2，挂在 Player 下）
@onready var mana_pool: ManaPool = $ManaPool
## 技能控制器（任务 2.2，挂在 Player 下，player_path 指向自身）
@onready var skill_controller: SkillController = $SkillController
## 生命组件（任务 2.6，挂在 Player 下；持有 HP / 护盾 / 异常状态 / 减伤链）
@onready var health: HealthComponent = $Health

## 是否生成占位美术（真实资源就绪后置 false）。占位贴图在运行时用代码生成，
## 避免把二进制资源塞进仓库。
@export var use_placeholder_art: bool = true

# ── 真實精靈（豆包原創像素素材：多動作 × 多方向 + 用戶可替換）──────────────
## 美術全為豆包原創，不含任何第三方素材；共用解析工具寄居於 EnemyBase
## （理由見 enemy_base.gd「三·C」段）。
## 玩家素材目錄名（`assets/pack/creatures/player/`）。**也是用戶覆蓋目錄名**：
## `user://content/characters/player/`
const PLAYER_ART_ID: String = "player"

## 真實精靈狀態（未接真素材時全不啟用 → 行為與原佔位完全相同）
var _real_frames: Array = []
var _real_fps: float = 12.0
var _real_anim: bool = false
var _anim_t: float = 0.0
var _anim_i: int = 0

## 動作 → 方向 → 幀（見 `EnemyBase.dnf_load_dir`）。空 = 沒接真素材。
var _clips: Dictionary = {}
var _clip: Array = []
var _clip_key: String = ""
var _clip_exact: bool = false
## 純表現層的動作狀態（與 EnemyBase.AnimState 同一套枚舉，避免兩側語義漂移）
var _anim_state: int = EnemyBase.AnimState.IDLE
var _anim_action: String = EnemyBase.ANIM_IDLE
var _anim_dir: String = EnemyBase.DIR_S
var _anim_oneshot: String = ""
var _anim_oneshot_t: float = 0.0

# =============================================================================
# 六、运行时状态
# =============================================================================

var _facing: int = Facing8.DOWN
var _dodge_dir: Vector2 = Vector2.DOWN
var _dodge_timer: float = 0.0
var _iframe_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _buffered_dodge: bool = false

# ---- 攻击与技能（任务 2.2）----

## 当前攻击动作剩余时间（>0 = 攻击间隔中，不能发起下一次挥击）
var _attack_timer: float = 0.0

## 攻击键是否按住（假连段：按住则间隔结束立即挥下一击）
var _attack_held: bool = false

## 武器前伸动画（连续挥击时复用同一 tween，防止堆积）
var _attack_lunge: Tween = null

## 攻速乘区（阶段 3 由词缀 / 局内增益写入；1.0 = 基线 1.0 次/秒）
var _attack_speed_multiplier: float = 1.0

## 移速乘区（三选一「迅捷」等注入；1.0 = 基线。默认 1.0 ⇒ 未注入时行为与修复前一致）
var _move_speed_multiplier: float = 1.0

# ---- 阶段 3/5 战斗属性注入（2026-09-18 · 排障修复 · team-lead 裁定）----
#
# 背景（本项目第 10 个「生成了但没人消费」）：本类**全部**战斗属性 getter 整层停留在
#   阶段 2 的占位桩 —— `get_attack_damage()` 恒 = 裸装 12、`get_crit_*()` 恒基准常量、
#   `get_armor()` 只吃等级、`get_resist()` 恒 0、`get_player_level()` 恒 1。
#   阶段 3（装备/词缀）与阶段 5（账号/天赋/宝石/套装）都「完成」了，但做完的东西
#   **没有一条流进实战**。净效果：这是一个「装备驱动刷宝 ARPG」，而装备**只影响生命上限**。
#
# 修法：`StatCalculator` 是唯一真相源；本类**消费平铺总属性**，**不再**自己乘裸装基线
#   （`StatCalculator.calculate()` 的输出已含裸装成长，再乘一次 = 双重计入）。
#
# ⚠️ 向后兼容（硬要求）：**未注入（字典为空）时，所有 getter 行为与修复前逐位一致**
#   —— 既有 45 个 verify 脚本不会因本次重构集体变红；`get_player_level()` 无账号数据
#   时回退 1（测试环境依赖这一点）。回归由 `verify_combat_stats.gd` 独立盯死。
#
# ⚠️ StatCalculator 输出口径（决定各 getter 怎么读，别搞反）：
#   - `attack` / `max_hp` / `armor`  = **绝对值**（已含裸装成长）→ 直接返回；
#   - `crit_chance` / `crit_damage` / `attack_speed` / `move_speed` / 各 `*_resist` /
#     `armor_pierce` / `life_steal` … = **百分比（增量）** → 叠加在基线常量上。
var _combat_stats: Dictionary = {}

## 注入的账号等级（0 = 未注入 → 回退读 `SaveManager.current_data.account_level` → 再无则 1）
var _injected_level: int = 0

## 元素 → StatCalculator 抗性键（shadow 无抗性键，恒 0）
const _RESIST_KEY_BY_ELEMENT := {
	GameConstants.ELEMENT_FIRE: "fire_resist",
	GameConstants.ELEMENT_COLD: "cold_resist",
	GameConstants.ELEMENT_LIGHTNING: "lightning_resist",
	GameConstants.ELEMENT_POISON: "poison_resist",
}


## 注入战斗属性（由 `LevelScene._apply_account_stats` 调；stats = StatCalculator.calculate 的输出）。
##
## `account_level` 传 0 表示「不覆盖等级」（仍回退读存档）。
## 空字典 = 清除注入，回到阶段 2 占位基线（便于测试与「未进关」场景）。
func apply_combat_stats(stats: Dictionary, account_level: int = 0) -> void:
	_combat_stats = stats.duplicate() if stats != null else {}
	_injected_level = account_level
	# 攻速乘区：`attack_speed` 是百分比增量（+10 → ×1.10）
	_attack_speed_multiplier = 1.0 + float(_combat_stats.get("attack_speed", 0.0)) / 100.0
	# 移速乘区：`move_speed` 是百分比增量（+12 → ×1.12）。三选一「迅捷」等的消费入口。
	_move_speed_multiplier = 1.0 + float(_combat_stats.get("move_speed", 0.0)) / 100.0


## 清除注入，回到占位基线（攻击=裸装、暴击=基准、抗性=0 …）
func clear_combat_stats() -> void:
	_combat_stats = {}
	_injected_level = 0
	_attack_speed_multiplier = 1.0
	_move_speed_multiplier = 1.0


## 是否已注入战斗属性
func has_combat_stats() -> bool:
	return not _combat_stats.is_empty()


## 通用战斗属性读取（**注入优先**，未注入回退 0）。
## 供「本类尚无专用 getter 的键」（move_speed / life_steal / thorns / gold_gain …）读取，
## 也是 `verify_choice_flow` 逐选项断言「属性真的到了玩家」的统一入口。
func get_combat_stat(key: String) -> float:
	return float(_combat_stats.get(key, 0.0))


func _ready() -> void:
	# 敌人 AI（2.4）按本组定位玩家；玩家生命/受击在 2.6 接入前只有组定位职责
	add_to_group(&"player")
	# 顶层俯视移动：用 FLOATING 模式，否则会被 default_gravity 往下拽
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# 占位美术**总是先建**：主/副手占位武器节点是既有契约（`verify_player` D 段
	# 断言其存在；接真素材时只隐藏、不删）。
	# ⚠️ 修的是既有缺陷：此前真素材命中就跳过建节点 ⇒ 占位武器「根本不存在」。
	if use_placeholder_art:
		_build_placeholder_art()
	# 優先鏈（**用戶可替換**，美術全為豆包原創）：① user://content/characters/player/
	# → ①·5 pack/creatures/player 多幀 → ② 內建單張 → ③ 占位色塊。
	var art := EnemyBase.resolve_character_set(PLAYER_ART_ID)
	if art["ok"]:
		_apply_real_art(art)
	_apply_facing()
	# 【L5】腳下投影：與美術無關，永遠建（真素材 / 占位都受益）
	_build_ground_shadow()


func _physics_process(delta: float) -> void:
	# 2.6 死亡：不再接受输入 / 移动（完整死亡流程阶段后接，见 EventBus.player_died）
	if health != null and health.is_dead:
		velocity = Vector2.ZERO
		_knockback_velocity = Vector2.ZERO
		return
	_tick_timers(delta)
	_tick_flash(delta)
	_tick_attack(delta)
	var input_dir := _read_move_input()

	# 通道 1：输入 / 闪避速度。算进局部变量 move_velocity，**不直接写 velocity** ——
	# 否则击退残留会污染下一帧的加减速曲线（松手后拖尾）。
	var move_velocity := velocity
	if _is_dodging():
		# 冲刺期间速度完全由闪避接管，忽略常规移动输入
		move_velocity = _dodge_dir * (dodge_distance / maxf(dodge_duration, 0.001))
	elif input_dir != Vector2.ZERO:
		# 2.6 冰冻减速：移动速度 × 异常乘区（减速不作用于闪避冲刺）
		var slow := 1.0
		if health != null:
			slow = health.get_move_speed_factor()
		move_velocity = move_velocity.move_toward(
			input_dir * LOCAL_MOVE_SPEED * slow * _move_speed_multiplier,
			LOCAL_ACCELERATION * delta)
	else:
		move_velocity = move_velocity.move_toward(Vector2.ZERO, LOCAL_DECELERATION * delta)

	# 通道 2：击退（见 `apply_knockback`）。两通道**相加**后交给 move_and_slide 裁定地形。
	#
	# ⚠️ 这里必须是「重算」而不是 `velocity += _knockback_velocity`。
	#    velocity 是 CharacterBody2D 的**跨帧持久属性**：上一帧的击退量已经写进去了，
	#    这一帧再 += 一次 ⇒ 击退速度逐帧累积、位移发散。
	#    实测（tools/verify_fix93 H 段）请求 12px 位移会走成 61.4px；
	#    逐帧速度序列 169.7/292.7/395.7/478.7/541.7/584.7/607.7/610.7 与 61.4px 完全吻合。
	velocity = move_velocity + _knockback_velocity
	move_and_slide()
	# 衰减放在位移**之后**：本帧按完整初速走，位移量才符合 v0 = sqrt(2·a·L) 的换算。
	if _knockback_velocity != Vector2.ZERO:
		_knockback_velocity = _knockback_velocity.move_toward(
			Vector2.ZERO, KNOCKBACK_DECAY * delta)
		if _knockback_velocity.length() < KNOCKBACK_STOP_EPSILON:
			_knockback_velocity = Vector2.ZERO
	# 只把输入通道写回，击退不残留到下一帧
	velocity = move_velocity
	_update_facing_from(input_dir)


func _unhandled_input(event: InputEvent) -> void:
	if health != null and health.is_dead:
		return
	if event.is_action_pressed(&"dodge"):
		_try_dodge()
		return
	# 消耗品快捷（步骤 8A）：Q=生命药水 / R=法力药水（闪避中也允许喝药）
	if event.is_action_pressed(&"consume_1"):
		use_consumable("life_potion")
		return
	if event.is_action_pressed(&"consume_2"):
		use_consumable("mana_potion")
		return
	# 技能输入（1/2/3 键 + 手柄）；闪避中忽略，防止位移技能与冲刺打架
	if _is_dodging():
		return
	for i in range(GameConstants.SKILL_BAR_ACTIONS.size()):
		if event.is_action_pressed(StringName(GameConstants.SKILL_BAR_ACTIONS[i])):
			var id := skill_controller.get_skill_id_at(i)
			if not id.is_empty():
				skill_controller.try_cast(id)
			return


# =============================================================================
# 七、公开查询接口（供 UI / 战斗 / 验证脚本使用）
# =============================================================================

func get_facing() -> int:
	return _facing


## 当前朝向的单位向量（屏幕坐标，+y 向下）
func get_facing_vector() -> Vector2:
	return _facing_to_vector(_facing)


## 当前是否有无敌帧（阶段 2.3 伤害管线据此免伤）
func is_invulnerable() -> bool:
	return _iframe_timer > 0.0


func is_dodging() -> bool:
	return _dodge_timer > 0.0


func get_dodge_cooldown_remaining() -> float:
	return _cooldown_timer


## 主手锚点的**全局**位置（阶段 3 装备上身 / 阶段 6 特效定位用）
func get_main_hand_global_position() -> Vector2:
	return main_hand_anchor.global_position


func get_off_hand_global_position() -> Vector2:
	return off_hand_anchor.global_position


## 供外部（如击退、传送）强制设置朝向
func set_facing(facing: int) -> void:
	_facing = clampi(facing, 0, FACING_COUNT - 1)
	_apply_facing()


## 以编程方式触发闪避（验证脚本 / AI 演示用）。返回是否成功触发。
func try_dodge() -> bool:
	return _try_dodge()


# =============================================================================
# 七·五、攻击与技能公开接口（任务 2.2）
# =============================================================================

## 当前攻击力。
##
## **注入优先**：已注入战斗属性时直接返回 `StatCalculator` 的 `attack`（绝对值，含裸装成长
## 与装备/增益）—— 不再叠乘裸装基线（那是双重计入）。
## 未注入时回退到修复前的行为：裸装 `Base1 × (1+0.10)^(L-1)`（= 12 @ L1）。
func get_attack_damage() -> float:
	if _combat_stats.has("attack"):
		return float(_combat_stats["attack"])
	var base := GameConstants.base_stat_at_level(
		GameConstants.PLAYER_BASE_ATTACK_AT_L1,
		GameConstants.BASE_AD_GROWTH,
		get_player_level(),
	)
	return base * _get_attack_multiplier_from_stats()


## 玩家等级。
## 优先级：**注入等级** → `SaveManager.current_data.account_level` → 1。
## ⚠️ 修复前恒返回 1，导致 `EnemyBase._player_level()` 的**越级惩罚**永远按 1 级判定
##    （20 关里 ch1_l05 起一律被当成越级）。`verify_fix93` 已针对此补「随账号等级变化」证伪断言。
func get_player_level() -> int:
	if _injected_level > 0:
		return _injected_level
	var data := SaveManager.current_data
	if data != null:
		return maxi(int(data.account_level), 1)
	return 1


## 暴击率（%）。**注入优先**：基准 + 装备/增益增量（`StatCalculator` 的 crit_chance 是增量）。
func get_crit_chance() -> float:
	return GameConstants.CRIT_CHANCE_BASE + float(_combat_stats.get("crit_chance", 0.0))


## 暴击伤害（%）。**注入优先**：基准 + 增量。
func get_crit_damage() -> float:
	return GameConstants.CRIT_DAMAGE_BASE + float(_combat_stats.get("crit_damage", 0.0))


## 攻速乘区。注入时 = 1 + attack_speed%/100（`apply_combat_stats` 里算好）；未注入 = 1.0。
func get_attack_speed_multiplier() -> float:
	return _attack_speed_multiplier


## 移速乘区。注入时 = 1 + move_speed%/100；未注入 = 1.0。
## 消费方：`_physics_process` 的常规移动（闪避冲刺刻意不吃移速，见该处注释）。
func get_move_speed_multiplier() -> float:
	return _move_speed_multiplier


func get_mana_pool() -> ManaPool:
	return mana_pool


func get_skill_controller() -> SkillController:
	return skill_controller


## 朝向前方 arc_deg 扇区内、range 内全部目标，按距离升序（第 0 个 = 最近）。
## 目标约定：加入 `enemies` 组的 Node。2.5 起走 HitQuery 统一命中判定（目标半径扩展）。
func find_targets_in_arc(range_px: float, arc_deg: float) -> Array[Node]:
	return HitQuery.arc(global_position, get_facing_vector(), range_px, arc_deg,
		get_tree().get_nodes_in_group(&"enemies"))


## 以玩家为中心、radius 内全部目标（范围技能）
func find_targets_in_radius(radius_px: float) -> Array[Node]:
	return HitQuery.circle(global_position, radius_px,
		get_tree().get_nodes_in_group(&"enemies"))


## 受击命中半径（2.5 碰撞判定目标半径扩展）：玩家碰撞框 20×22 → 半宽 11px。
func get_hit_radius() -> float:
	return 11.0


# =============================================================================
# 七·六、生命契约（任务 2.6 · HealthComponent 宿主接口）
# =============================================================================
#
# 2.4/2.5 受击契约收编：敌人攻击 `_player.take_damage(dmg, self)` 自此真正扣血；
# 减伤链（护甲 → 减伤% → 闪避/格挡）由 HealthComponent 执行，本类只提供宿主属性。

## 受击入口（契约）。转发给生命组件（减伤 / 护盾 / 异常 / 死亡在组件内）
func take_damage(amount: float, source: Node) -> void:
	if health == null:
		return
	# 受击动画只在**真的掉血**时播：无敌帧 / 闪避 / 格挡全免 / 护盾全吸收都不播。
	# 纯表现层，不改变任何结算（`verify_health` 的 HP 断言因此逐位不变）。
	var hp_before := health.get_current_hp()
	health.take_damage(amount, source)
	if health.get_current_hp() < hp_before:
		_play_anim_oneshot(EnemyBase.ANIM_HURT, EnemyBase.HURT_ANIM_DURATION)


## 击退入口（契约）。offset 为位移向量（px）。
##
## 与 `EnemyBase.apply_knockback` **同签名** —— `SkillController._hit` 靠
## `has_method("apply_knockback")` 探测，方法名不一致会**静默跳过**（无报错）。
## 语义：offset 是「期望位移」，本实现折算成初速并入击退通道（见二·五节），
## 实际位移由 `move_and_slide()` 裁定，撞墙时会自然变短 —— 这是刻意的，优于瞬移。
func apply_knockback(offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	# 线性衰减下 位移 L = v0² / (2a)  ⇒  v0 = sqrt(2·a·L)
	var l := offset.length()
	_knockback_velocity += offset.normalized() * sqrt(2.0 * KNOCKBACK_DECAY * l)


## 按元素施加异常（敌人攻击用）：毒→中毒 / 火→燃烧 / 冰→冰冻
func apply_ailment_from_element(element: String, source: Node) -> void:
	if health != null:
		health.apply_ailment_from_element(element, source)


func get_max_hp() -> float:
	if health != null:
		return health.get_max_hp()
	return 0.0


func get_current_hp() -> float:
	if health != null:
		return health.get_current_hp()
	return 0.0


func get_shield() -> float:
	if health != null:
		return health.get_shield()
	return 0.0


## 护甲。**注入优先**：返回 `StatCalculator` 的 `armor`（绝对值）。
## 未注入时回退裸装公式 `Base1 × (1+0.10)^(L-1)`（= 6 @ L1）。
func get_armor() -> float:
	if _combat_stats.has("armor"):
		return float(_combat_stats["armor"])
	return GameConstants.base_stat_at_level(
		GameConstants.BASE_ARMOR_AT_L1, GameConstants.BASE_ARMOR_GROWTH, get_player_level())


## 元素抗性（%）。**注入优先**：读注入的 `<element>_resist`（增量）。
## 未注入或未知元素（如 shadow）回退 0。
func get_resist(element: String) -> float:
	var key: String = _RESIST_KEY_BY_ELEMENT.get(element, "")
	if key.is_empty():
		return 0.0
	return float(_combat_stats.get(key, 0.0))


## 闪避率（%）：**注入优先**（增量叠加在基准上）
func get_dodge_chance() -> float:
	return GameConstants.PLAYER_BASE_DODGE_CHANCE + float(_combat_stats.get("dodge", 0.0))


## 格挡率（%）：**注入优先**（增量叠加在基准上）
func get_block_chance() -> float:
	return GameConstants.PLAYER_BASE_BLOCK_CHANCE + float(_combat_stats.get("block_chance", 0.0))


# =============================================================================
# 七·七、拾取契约（任务 2.7 · 掉落与拾取）
# =============================================================================
#
# 会话级背包：金币 / 魔石 / 装备列表。持久化（存档扩展）阶段 3 接 SaveData；
# 背包 UI 阶段 7。拾取由 LootDrop 靠近自动调用本接口。

## 金币（会话）
var gold: int = 0

## 魔石（锻造强化材料占位，会话）
var materials: int = 0

## 装备背包（会话）：[{ "item_id", "rarity", "item_level", "affix_count", "instance" }]
## instance 为完整 EquipmentInstance.to_dict()（含词缀，任务 3.2 起由掉落时生成）
var inventory: Array[Dictionary] = []

## 消耗品（会话，步骤 8A）：{ 消耗品ID: 数量 }（药水：掉落/商店入账，Q/R 喝）
var consumables: Dictionary = {}
## 消耗品冷却截止时间（毫秒）：{ id: ms }
var _consumable_cd_until_ms: Dictionary = {}


## 拾取入口（LootDrop 调用）
func pickup_loot(entry: Dictionary) -> void:
	var type: String = entry.get("type", "gold")
	match type:
		"gold":
			gold += int(entry.get("amount", 0))
			AudioManager.play("pickup_gold")
			print("[Loot] 拾取 金币 ×%d（累计 %d）" % [entry.get("amount", 0), gold])
		"material":
			materials += int(entry.get("amount", 0))
			AudioManager.play("pickup_gold")
			print("[Loot] 拾取 魔石 ×%d（累计 %d）" % [entry.get("amount", 0), materials])
		"consumable":
			var cid := str(entry.get("item_id", ""))
			if not cid.is_empty():
				consumables[cid] = int(consumables.get(cid, 0)) + int(entry.get("amount", 1))
			AudioManager.play("pickup_item")
			EventBus.consumables_changed.emit(consumables.duplicate(), "pickup")
			print("[Loot] 拾取 消耗品 %s ×%d（持有 %d）"
				% [cid, entry.get("amount", 1), consumables.get(cid, 0)])
		"equipment":
			AudioManager.play("pickup_item")
			var item: Dictionary = {
				"item_id": entry.get("item_id", ""),
				"rarity": int(entry.get("rarity", GameConstants.Rarity.COMMON)),
				"item_level": int(entry.get("item_level", 1)),
			}
			# 词缀（3.2 起掉落即定型）：优先用完整实例，否则退化为无词缀占位
			if entry.has("instance") and entry["instance"] is Dictionary:
				item["instance"] = entry["instance"]
				item["affix_count"] = (entry["instance"] as Dictionary).get("affixes", []).size()
			else:
				item["affix_count"] = 0
			inventory.append(item)
			var rn := GameConstants.rarity_name(int(item["rarity"]))
			var tmpl: EquipmentData = ConfigLoader.equipment_templates.get(item["item_id"])
			var nm: String = tmpl.display_name if tmpl != null else str(item["item_id"])
			print("[Loot] 拾取 %s（%s · iLvl %d · %d 条词缀，背包 %d 件）"
					% [nm, rn, item["item_level"], item["affix_count"], inventory.size()])


# ============ 消耗品（步骤 8A · 药水） ============

## 消耗品：当前持有数量（无则 0）
func consumable_count(id: String) -> int:
	return int(consumables.get(id, 0))


## 消耗品全量快照（UI 刷新用）
func get_consumables() -> Dictionary:
	return consumables.duplicate()


## 消耗品剩余冷却（秒；0 = 可用）
func get_consumable_cd_remaining(id: String) -> float:
	var until_ms: int = int(_consumable_cd_until_ms.get(id, 0))
	return maxf(float(until_ms - Time.get_ticks_msec()) / 1000.0, 0.0)


## 使用消耗品（药水）。返回 {ok, reason, healed, kind}。
## 数量不足 / 冷却中 / 未知 ID → 失败且不扣任何东西。
func use_consumable(id: String) -> Dictionary:
	var cfg: Dictionary = ConfigLoader.consumables.get(id, {})
	if cfg.is_empty():
		return {"ok": false, "reason": "未知消耗品"}
	if consumable_count(id) <= 0:
		return {"ok": false, "reason": "数量不足"}
	if get_consumable_cd_remaining(id) > 0.0:
		return {"ok": false, "reason": "冷却中"}
	var kind := str(cfg.get("kind", ""))
	var pct := clampf(float(cfg.get("percent", 0.0)), 0.0, 1.0)
	var healed := 0.0
	if kind == "heal_hp" and health != null:
		healed = health.get_max_hp() * pct
		health.restore(healed)
	elif kind == "heal_mp" and mana_pool != null:
		healed = mana_pool.maximum * pct
		mana_pool.restore(healed)
	consumables[id] = maxi(int(consumables.get(id, 0)) - 1, 0)
	_consumable_cd_until_ms[id] = Time.get_ticks_msec() + int(float(cfg.get("cooldown", 3.0)) * 1000.0)
	AudioManager.play("potion_drink")
	EventBus.consumables_changed.emit(consumables.duplicate(), "used")
	if healed > 0.0 and not is_queued_for_deletion():
		JuiceFX.spawn_heal_number(healed, global_position)
	print("[Consumable] 使用 %s：回复 %.0f（%s 剩余 %d）"
		% [id, healed, str(cfg.get("display_name", id)), consumable_count(id)])
	return {"ok": true, "reason": "", "healed": healed, "kind": kind}


# =============================================================================
# 七·八、受击表现（任务 2.8 · 打击感）
# =============================================================================
#
# JuiceFX 监听 `damage_dealt`（含敌人命中）→ 调本方法闪白。
# 只做表现（modulate 白闪），不碰伤害结算。

var _flash_timer: float = 0.0
var _flash_nodes: Array[Node] = []


## 受击闪白：身体 + 主副手一起亮 0.08s（JuiceFX 调用）
func flash() -> void:
	_flash_nodes.clear()
	if body_sprite != null:
		_flash_nodes.append(body_sprite)
	if weapon_layer != null:
		for child in weapon_layer.get_children():
			_collect_sprites(child)
	for n in _flash_nodes:
		if n is CanvasItem:
			(n as CanvasItem).modulate = Color(2.2, 2.2, 2.2)
	_flash_timer = GameConstants.HIT_FLASH_DURATION


func _collect_sprites(node: Node) -> void:
	if node is Sprite2D:
		_flash_nodes.append(node)
	for child in node.get_children():
		_collect_sprites(child)


func _tick_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		for n in _flash_nodes:
			if is_instance_valid(n) and n is CanvasItem:
				(n as CanvasItem).modulate = Color.WHITE
		_flash_nodes.clear()


## 位移技能：沿朝向冲刺，撞到的第一个目标回调 SkillController 结算。
## 物理位移必须在 CharacterBody2D 上执行，故由本类实现（SkillController 不移动玩家）。
func perform_skill_dash(data: SkillData) -> void:
	var dir := get_facing_vector()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var collision := move_and_collide(dir * data.dash_distance)
	if collision:
		var target := collision.get_collider()
		if target is Node and target.is_in_group(&"enemies"):
			skill_controller.on_dash_hit(target, data)


## 以编程方式发起一次普攻（验证脚本用；与按住攻击键等价）
func try_attack() -> bool:
	if health != null and health.is_dead:
		return false
	if _is_dodging() or _attack_timer > 0.0:
		return false
	_perform_attack()
	return true


# =============================================================================
# 八、内部：移动与朝向
# =============================================================================

func _read_move_input() -> Vector2:
	var raw := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	# Input.get_vector 已做归一化，但显式再夹一次，防止将来换成手动拼向量时漏掉
	return raw.limit_length(1.0)


func _update_facing_from(input_dir: Vector2) -> void:
	if input_dir.length_squared() < 0.01:
		return
	_facing = _vector_to_facing(input_dir)
	_apply_facing()


## 把朝向同步到表现层：身体翻转 + 锚点位置 + 武器翻转
func _apply_facing() -> void:
	# 左右翻轉**只在沒有分方向素材時**使用：真素材的四方向是預烘的，
	# 再翻一次會把「西向幀」鏡像成東向，方向就全錯了（`_clips` 非空即代表有方向幀）。
	if body_sprite != null and _clips.is_empty():
		var fv := get_facing_vector()
		# 纯上/下朝向不翻转，避免左右横跳；左右有分量时按 x 符号翻转
		if absf(fv.x) > 0.01:
			body_sprite.flip_h = fv.x < 0.0

	var r := _right_hand_dir(_facing)
	var lateral := Vector2(r.x * HAND_SPREAD, r.y * HAND_SPREAD * HAND_SPREAD_Y_DAMP)
	var base := Vector2(0.0, HAND_HEIGHT)

	if main_hand_anchor != null:
		main_hand_anchor.position = base + lateral
		_orient_placeholder_weapon(main_hand_anchor)
	if off_hand_anchor != null:
		off_hand_anchor.position = base - lateral
		_orient_placeholder_weapon(off_hand_anchor)


## 角色「右手方向」：屏幕坐标（+y 向下）里把朝向逆时针转 90°。
## 校验：朝下(0,1) → 右(-1,0) 即面向镜头时右手在屏幕左侧 ✔
##      朝上(0,-1) → 右(1,0) 即背对镜头时右手在屏幕右侧 ✔
static func _right_hand_dir(facing: int) -> Vector2:
	var d := _facing_to_vector(facing)
	return Vector2(-d.y, d.x)


## 朝向枚举 → 单位向量。**必须是 static**：`_right_hand_dir()` 是静态函数并依赖它。
static func _facing_to_vector(facing: int) -> Vector2:
	match facing:
		Facing8.DOWN: return Vector2(0, 1)
		Facing8.DOWN_LEFT: return Vector2(-1, 1).normalized()
		Facing8.LEFT: return Vector2(-1, 0)
		Facing8.UP_LEFT: return Vector2(-1, -1).normalized()
		Facing8.UP: return Vector2(0, -1)
		Facing8.UP_RIGHT: return Vector2(1, -1).normalized()
		Facing8.RIGHT: return Vector2(1, 0)
		Facing8.DOWN_RIGHT: return Vector2(1, 1).normalized()
	return Vector2(0, 1)


func _vector_to_facing(dir: Vector2) -> int:
	if dir.length_squared() < 0.0001:
		return _facing
	# atan2 的角度按 22.5° 一档切成 8 份
	var angle := atan2(dir.y, dir.x) # 0 = 右，+π/2 = 下
	var sector := int(round(angle / (PI / 4.0))) # -4..4
	match sector:
		-4, 4: return Facing8.RIGHT
		-3: return Facing8.UP_RIGHT
		-2: return Facing8.UP
		-1: return Facing8.UP_LEFT
		0: return Facing8.RIGHT
		1: return Facing8.DOWN_RIGHT
		2: return Facing8.DOWN
		3: return Facing8.DOWN_LEFT
	return _facing


## 8 方向 → 美术出图的 4 方向索引（0=下 1=左 2=上 3=右）。
## 用于阶段 6 按「人形怪 4 方向 / 杂兵 2 方向」分级取帧。
static func facing_to_4dir(facing: int) -> int:
	match facing:
		Facing8.DOWN, Facing8.DOWN_LEFT, Facing8.DOWN_RIGHT: return 0
		Facing8.LEFT, Facing8.UP_LEFT: return 1
		Facing8.UP: return 2
		Facing8.RIGHT, Facing8.UP_RIGHT: return 3
	return 0


## 8 方向 → **檔名用的 4 方向字母**（n 北/上 · e 東/右 · s 南/下 · w 西/左）。
## 這是寫進用戶替換文檔的正式方向約定，與 `EnemyBase.dir_from_vector` 同一套字母。
static func facing_to_dir_letter(facing: int) -> String:
	match facing:
		Facing8.DOWN, Facing8.DOWN_LEFT, Facing8.DOWN_RIGHT: return EnemyBase.DIR_S
		Facing8.LEFT, Facing8.UP_LEFT: return EnemyBase.DIR_W
		Facing8.UP: return EnemyBase.DIR_N
		Facing8.RIGHT, Facing8.UP_RIGHT: return EnemyBase.DIR_E
	return EnemyBase.DIR_S


# =============================================================================
# 九、内部：闪避
# =============================================================================

func _tick_timers(delta: float) -> void:
	if _dodge_timer > 0.0:
		_dodge_timer = maxf(_dodge_timer - delta, 0.0)
	if _iframe_timer > 0.0:
		_iframe_timer = maxf(_iframe_timer - delta, 0.0)
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
		# 冷却刚结束的瞬间，兑现缓冲的闪避输入
		if _cooldown_timer == 0.0 and _buffered_dodge:
			_buffered_dodge = false
			_try_dodge()


func _try_dodge() -> bool:
	if _cooldown_timer > 0.0:
		if dodge_input_buffer:
			_buffered_dodge = true
		return false
	if _is_dodging():
		return false

	var input_dir := _read_move_input()
	# 有移动输入就朝输入方向闪，没有就朝当前朝向闪（站桩闪避也要有方向）
	_dodge_dir = input_dir.normalized() if input_dir != Vector2.ZERO else get_facing_vector()
	if _dodge_dir == Vector2.ZERO:
		_dodge_dir = Vector2.DOWN

	_dodge_timer = dodge_duration
	_iframe_timer = dodge_iframe_duration
	_cooldown_timer = dodge_cooldown
	velocity = _dodge_dir * (dodge_distance / maxf(dodge_duration, 0.001))
	# 闪避打断当前攻击动作（假连段下一击在闪避结束后才可继续）
	_interrupt_attack()
	return true


func _is_dodging() -> bool:
	return _dodge_timer > 0.0


# =============================================================================
# 八·五、内部：攻击与假连段（任务 2.2）
# =============================================================================
#
# 假连段设计（用户拍板）：美术只有「4 方向 × 8 帧」攻击动画，无连段动画预算，
#   故按住攻击键 → 按攻速间隔**连续挥击同一段动画**（视觉像连击），不做连段状态机。
#   攻击不打断移动（可边打边走），闪避打断当前挥击。

func _tick_attack(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer = maxf(_attack_timer - delta, 0.0)

	_attack_held = Input.is_action_pressed(GameConstants.ACTION_ATTACK)
	if _attack_held and _attack_timer <= 0.0 and not _is_dodging():
		_perform_attack()


func _perform_attack() -> void:
	var interval := 1.0 / maxf(GameConstants.ATTACK_BASE_RATE * get_attack_speed_multiplier(), 0.001)
	_attack_timer = interval
	# 攻擊動作動畫：**只設表現計時器**，不碰 `_attack_timer` / 命中判定 / 傷害時點
	# （`verify_hit` / `verify_damage` 都靠 `try_attack()` 同幀出傷，這裡不能延後任何東西）。
	_play_anim_oneshot(EnemyBase.ANIM_ATTACK, minf(interval, EnemyBase.ATTACK_ANIM_MAX))
	_play_attack_lunge()

	var targets := find_targets_in_arc(GameConstants.ATTACK_RANGE, GameConstants.ATTACK_ARC_DEG)
	if targets.is_empty():
		return
	var target := targets[0]
	var base := get_attack_damage() * GameConstants.ATTACK_BASE_MULTIPLIER
	# 任务 2.3 伤害管线：暴击 roll → 元素（普攻物理）→ 目标减伤（护甲，先过破甲乘区）
	var result := DamageCalc.compute_hit(
		base,
		get_crit_chance(),
		get_crit_damage(),
		GameConstants.ELEMENT_PHYSICAL,
		0.0,
		DamageCalc.pierced_armor(DamageCalc.target_armor(target), get_combat_stat("armor_pierce")),
		DamageCalc.target_resist(target, GameConstants.ELEMENT_PHYSICAL),
		DamageCalc.target_level(target),
		0.0,
	)
	if target.has_method("take_damage"):
		target.take_damage(result.final_damage, self)
	# 普攻命中回蓝（任务 2.2 决策：普攻命中 +2）
	if mana_pool != null:
		mana_pool.restore(GameConstants.MANA_ON_HIT)
	EventBus.damage_dealt.emit(target, result.final_damage, result.crit, result.element)


## 武器前伸表现（占位；阶段 6 换成真实攻击动画后删除本函数）
func _play_attack_lunge() -> void:
	if weapon_layer == null or main_hand_anchor == null:
		return
	var dir := get_facing_vector()
	if dir == Vector2.ZERO:
		return
	if _attack_lunge != null and _attack_lunge.is_valid():
		_attack_lunge.kill()
	_attack_lunge = create_tween()
	var rest_pos := main_hand_anchor.position
	var lunge_pos := rest_pos + dir * 10.0
	_attack_lunge.tween_property(main_hand_anchor, "position", lunge_pos, 0.06)
	_attack_lunge.tween_property(main_hand_anchor, "position", rest_pos, 0.10)


## 打断当前攻击（闪避 / 受控时调用）
func _interrupt_attack() -> void:
	_attack_timer = 0.0
	if _attack_lunge != null and _attack_lunge.is_valid():
		_attack_lunge.kill()
		_attack_lunge = null


## 攻击力乘区（阶段 3 接入：装备 + 词缀 + 局内增益；当前恒 1.0）
func _get_attack_multiplier_from_stats() -> float:
	return 1.0


# =============================================================================
# 九·B、真實精靈（T3 · 用戶裁定：接入遊戲看效果）
# =============================================================================

## 套用真實精靈：腳底貼玩家原點（玩家原點本就是腳底中心，見 HAND_HEIGHT 註解）、
## 水平居中、最近鄰；並隱藏占位武器（角色精靈自帶武器）。
## 顯示縮放由 `GameConstants.CHARACTER_SPRITE_SIZE` 反推（見 `_game_scale_for`）。
func _apply_real_art(art: Dictionary) -> void:
	if body_sprite == null:
		return
	_real_frames = art.get("frames", [])
	_real_fps = maxf(1.0, float(art.get("fps", 12.0)))
	_real_anim = _real_frames.size() > 1
	# ⚠️ 必須 duplicate：`art["clips"]` 是 `EnemyBase._dnf_cache` 裡的**同一個參照**，
	#    直接持有會讓本實例改 clip 時污染快取。
	_clips = (art.get("clips", {}) as Dictionary).duplicate()
	if _clips.is_empty() and not _real_frames.is_empty():
		_clips = {EnemyBase.ANIM_IDLE: {EnemyBase.DIR_S: _real_frames}}
	_anim_t = 0.0
	_anim_i = 0
	_clip = []
	_clip_key = ""
	_anim_oneshot = ""
	_anim_oneshot_t = 0.0
	_anim_state = EnemyBase.AnimState.IDLE
	_anim_action = EnemyBase.ANIM_IDLE
	if not _real_frames.is_empty():
		body_sprite.texture = _real_frames[0]
	body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body_sprite.centered = true
	# 有分方向素材 ⇒ 方向已預烘，禁止再左右翻轉
	body_sprite.flip_h = false
	# centered + offset.y = -canvas_h/2 ⇒ 紋理底邊落在玩家原點（= 腳底）
	body_sprite.offset = Vector2(0.0, -float(art.get("canvas", 0.0)) * 0.5)
	body_sprite.scale = Vector2.ONE * _game_scale_for(float(art.get("canvas", 0.0)))
	_hide_placeholder_weapons()


## 螢幕顯示縮放 = `CHARACTER_SPRITE_SIZE`（美術規範的主角畫布 48px）÷ 素材畫布。
## 這是 `CHARACTER_SPRITE_SIZE` 的**唯一權威消費點**：換一張不同畫布的圖
## （例如用戶自己出 96×96），螢幕上的角色大小仍鎖在 48px，不會忽大忽小。
## 畫布缺失（0）時退回預設 1/4 縮放（`EnemyBase.DNF_GAME_SCALE`，歷史命名保留）。
static func _game_scale_for(canvas: float) -> float:
	if canvas <= 0.0:
		return EnemyBase.DNF_GAME_SCALE
	return float(GameConstants.CHARACTER_SPRITE_SIZE) / canvas


## 隱藏占位武器精靈（**不刪除節點** —— verify_player D 段斷言兩者必須存在且為
## 32×8 / Sprite2D；角色精靈自帶武器，留著會與角色重疊、觀感混亂）。
func _hide_placeholder_weapons() -> void:
	if main_hand_anchor != null:
		var pm := main_hand_anchor.get_node_or_null(NodePath("PlaceholderMainWeapon"))
		if pm is Sprite2D:
			(pm as Sprite2D).visible = false
	if off_hand_anchor != null:
		var po := off_hand_anchor.get_node_or_null(NodePath("PlaceholderOffWeapon"))
		if po is Sprite2D:
			(po as Sprite2D).visible = false


## 真實精靈逐幀推進 + 動作狀態機（idle / walk / attack / hurt / die）。
## 未接真素材時 `_clips` 為空 → 第一行早退，占位行為與接入前逐位相同。
## （朝向翻轉由既有 `_apply_facing()` 負責；有方向素材時它會自動不翻。）
func _process(delta: float) -> void:
	if _clips.is_empty() or body_sprite == null:
		return
	_tick_anim_state(delta)
	_refresh_clip()
	if _clip.is_empty():
		return
	if _clip.size() <= 1:
		if body_sprite.texture != _clip[0]:
			body_sprite.texture = _clip[0]
		return
	_anim_t += delta * _real_fps
	if _anim_t >= 1.0:
		_anim_t -= floorf(_anim_t)
		if _clip_exact and _anim_state != EnemyBase.AnimState.IDLE \
				and _anim_state != EnemyBase.AnimState.WALK:
			# 一次性動作（攻擊 / 受擊 / 死亡）停在末幀，不循環回第一幀
			_anim_i = mini(_anim_i + 1, _clip.size() - 1)
		else:
			_anim_i = (_anim_i + 1) % _clip.size()
	# 換 clip 的**當幀**就得換圖（理由同 EnemyBase._process：否則會用舊動作的幀
	# 多撐最多 1/fps，切換動作時肉眼可見地「慢半拍」）。
	if body_sprite.texture != _clip[_anim_i]:
		body_sprite.texture = _clip[_anim_i]


## 純表現層的動作狀態推導。**不讀寫任何戰鬥計時 / 傷害 / 位置**。
func _tick_anim_state(delta: float) -> void:
	if _anim_oneshot_t > 0.0:
		_anim_oneshot_t = maxf(_anim_oneshot_t - delta, 0.0)
	_anim_dir = facing_to_dir_letter(_facing)
	if health != null and health.is_dead:
		_anim_state = EnemyBase.AnimState.DIE
		_anim_action = EnemyBase.ANIM_DIE
		return
	if _anim_oneshot_t > 0.0 and not _anim_oneshot.is_empty():
		_anim_action = _anim_oneshot
		_anim_state = EnemyBase.AnimState.ATTACK if _anim_oneshot == EnemyBase.ANIM_ATTACK \
				else EnemyBase.AnimState.HURT
		return
	var moving := velocity.length_squared() > 1.0
	_anim_state = EnemyBase.AnimState.WALK if moving else EnemyBase.AnimState.IDLE
	_anim_action = EnemyBase.ANIM_WALK if moving else EnemyBase.ANIM_IDLE


## 依「動作 → 方向」取幀（帶鍵快取，只在切換時重算）
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
	if action == EnemyBase.ANIM_ATTACK and _anim_oneshot == EnemyBase.ANIM_HURT \
			and _anim_oneshot_t > 0.0:
		return
	_anim_oneshot = action
	_anim_oneshot_t = maxf(duration, 0.05)
	_clip_key = ""


# =============================================================================
# 十、内部：占位美术（阶段 6 换成真实资源后整段删除）
# =============================================================================

## 生成纯色占位贴图。**注意：只做左右翻转，绝不旋转** ——
## 美术规范 0.7 明确禁止运行时旋转（会破坏像素网格），方向差异一律靠预烘帧表达。
func _build_placeholder_art() -> void:
	var body_size := 24
	var weapon_size := 32

	var body_tex := _solid_texture(body_size, body_size, Color("C9D1D9"))
	if body_sprite != null:
		body_sprite.texture = body_tex
		body_sprite.offset = Vector2(0, HAND_HEIGHT * 0.6)

	var main_tex := _solid_texture(weapon_size, 8, Color("F5C542"))
	var off_tex := _solid_texture(20, 20, Color("4C8BF5"))
	_attach_placeholder_sprite(main_hand_anchor, "PlaceholderMainWeapon", main_tex, Vector2(weapon_size * 0.5, 0))
	_attach_placeholder_sprite(off_hand_anchor, "PlaceholderOffWeapon", off_tex, Vector2(0, 0))


func _attach_placeholder_sprite(anchor: Marker2D, node_name: String, tex: Texture2D, offset: Vector2) -> void:
	if anchor == null:
		return
	var existing := anchor.get_node_or_null(NodePath(node_name))
	var sprite: Sprite2D = null
	if existing is Sprite2D:
		sprite = existing
	else:
		sprite = Sprite2D.new()
		sprite.name = node_name
		anchor.add_child(sprite)
	sprite.texture = tex
	sprite.offset = offset
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _solid_texture(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


# =============================================================================
# 九·C、腳下投影（L5 · 玩家可讀性）
# =============================================================================

## 投影尺寸（px）：橢圓 28×8 —— 略寬於身體（角色螢幕寬約 48px 的 6 成），
## 夠讀成「貼地」但不會蓋住腳部細節。
const SHADOW_SIZE := Vector2(28, 8)

## 投影中心相對玩家原點（= 腳底中心，見 HAND_HEIGHT 註解）的偏移。
## −2 讓投影**略微上移**、邊緣仍探到腳底之下 ⇒ 讀成「身體壓在地面上」。
const SHADOW_OFFSET := Vector2(0.0, -2.0)

## 投影色 = 色板最暗中性色 `0B0D10`（`UI_PANEL_BG`），透明度 0.60。
const SHADOW_COLOR := Color("0B0D10")
const SHADOW_ALPHA: float = 0.60


## 建腳下投影（**程式生成貼圖，不進倉庫**）。
##
## 這是俯視 ARPG 裡性價比最高的可讀性手段：讓玩家「貼地」而不是「飄在地圖上」。
## ⚠️ **刻意不給玩家加描邊** —— 那只是補丁；真正的地面可讀性由瓦片渲染（L1 地面提亮）修。
##
## 繪製次序：插為 Player 的**第 0 個子節點**（不是用 `z_index = -1`）——
## `z_index` 是相對父節點遞歸的，玩家本身 z=0，置 −1 會讓投影落到 `LevelView`（同層 z=0）之下、
## 被整張地圖蓋掉。用兄弟次序則投影仍在地圖之上、只在 BodySprite / WeaponLayer / FxLayer 之下。
func _build_ground_shadow() -> void:
	if get_node_or_null(NodePath("GroundShadow")) != null:
		return
	var sp := Sprite2D.new()
	sp.name = "GroundShadow"
	sp.texture = _shadow_texture(int(SHADOW_SIZE.x), int(SHADOW_SIZE.y))
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.centered = true
	sp.position = SHADOW_OFFSET
	add_child(sp)
	move_child(sp, 0)


## 橢圓投影貼圖：中心最實、邊緣漸淡。
## 不做漸淡的話硬邊會讀成「腳下壓著一個黑方塊」，比沒有投影更糟。
func _shadow_texture(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := float(w - 1) * 0.5
	var cy := float(h - 1) * 0.5
	var rx := maxf(cx, 0.001)
	var ry := maxf(cy, 0.001)
	var base := SHADOW_COLOR
	for y in h:
		for x in w:
			var dx := (float(x) - cx) / rx
			var dy := (float(y) - cy) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			# d ≤ 0.35 保持滿不透明，之後線性衰減到 0
			var f := 1.0 if d <= 0.35 else 1.0 - (d - 0.35) / 0.65
			var c := base
			c.a = SHADOW_ALPHA * f
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## 占位武器的左右翻转：手在身体中线左侧就朝左，右侧就朝右。
## 纯左右朝向时两手中线重合（x≈0），退回用身体朝向判断。
func _orient_placeholder_weapon(anchor: Marker2D) -> void:
	var sprite := anchor.get_node_or_null(NodePath("PlaceholderMainWeapon"))
	if sprite == null:
		sprite = anchor.get_node_or_null(NodePath("PlaceholderOffWeapon"))
	if not (sprite is Sprite2D):
		return
	var flip := false
	if absf(anchor.position.x) > 0.5:
		flip = anchor.position.x < 0.0
	else:
		flip = get_facing_vector().x < 0.0
	(sprite as Sprite2D).flip_h = flip
