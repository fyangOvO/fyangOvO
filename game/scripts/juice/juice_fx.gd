## 全局打击感控制器（任务 2.8 · Autoload「JuiceFX」）
##
## 监听总线事件，把「伤害结算」翻译成「打击感表现」，全程不碰结算逻辑：
##   - `EventBus.damage_dealt(target, amount, is_crit, element)` →
##       目标头顶飘字 + **元素命中**（贴图，见下）/ 暴击斩弧（贴图）+ 目标闪白 + 震屏 +
##       **顿帧（暴击固定档 ∪ 按伤害分级 —— 2026-10-14 起重击更顿，见 `hit_stop_for_hit`）**
##   - `EventBus.unit_died(unit, killer)` → 死亡烟尘（贴图）
##   - `EventBus.run_level_up(...)`       → 升级爆光（贴图）
##   - `EventBus.damage_taken(src, ...)`  → 焰术信徒施法特效（贴图）
##   - `EventBus.boss_phase_changed(...)` → 熔心之主余烬特效（贴图）
##
## 2026-09-20 变更 · 特效贴图化（用户诉求「我可以自己換特效」）
## ------------------------------------------------------------------
## 此前本类把要播的两个场景**硬编码 preload**（`damage_number.tscn` / `pixel_burst.tscn`），
## 全项目**没有任何接口**能把用户自己的特效贴图换进来。
## 现在改成数据驱动：特效 id → `data/fx.json` → `assets/fx/<id>.png`（用户可覆盖），
## 由 `FxTable` 解析、`FxSprite` 播放。
##
## ⚠️ **代码绘制路径全部保留为兜底**（`_spawn_damage_number` / `_spawn_burst`）：
##    贴图缺失时（用户删了 PNG / 表里没这个 id）自动退回原实现，**手感不变**。
##    只做「有贴图就用贴图」，不做「没贴图就没特效」——那会让换图变成负优化。
##
## 音效反馈：`assets/audio/` 阶段 6 才有资产，届时在本类接 AudioStreamPlayer。
extends Node

# =============================================================================
# 特效 id（对应 `data/fx.json` 的键）
# =============================================================================
const FX_HIT_SPARK := "hit_spark"
const FX_SLASH_ARC := "slash_arc"
const FX_LEVEL_UP_BURST := "level_up_burst"
const FX_DEATH_PUFF := "death_puff"
const FX_EMBER_LORD_AURA := "ember_lord_aura"
const FX_PYROMANCER_CAST := "pyromancer_cast"

## 元素 → 命中特效 id（2026-09-28 接入；素材见 01-技能体系.md 附錄 A §A.7 C1 批次）。
## 键必须是 `GameConstants.ELEMENTS` 的**真实值**（lowercase）；这里写字面量是为了
## 避免 const 表达式跨类引用（`GameConstants.ELEMENT_*`）带来的解析顺序风险。
## ⚠️ **物理刻意不进表**：§A.7 明讲「物理可复用既有 `hit_spark`」⇒ 走兜底路径即可。
const ELEMENT_HIT_FX: Dictionary = {
	"fire": "elem_hit_fire",
	"cold": "elem_hit_frost",
	"lightning": "elem_hit_thunder",
	"poison": "elem_hit_poison",
	"shadow": "elem_hit_shadow",
}

## 特效与怪物的对应（`monsters.json` 的真实 id）
const MONSTER_EMBER_LORD := "boss_ember_lord"
const MONSTER_PYROMANCER := "pyromancer_cultist"

# =============================================================================
# 代码绘制兜底场景（**仅**在贴图不可用时使用；见类注释）
# =============================================================================
const FALLBACK_DAMAGE_NUMBER_SCENE := preload("res://scenes/juice/damage_number.tscn")
const FALLBACK_PIXEL_BURST_SCENE := preload("res://scenes/juice/pixel_burst.tscn")

var _shake_camera: Camera2D = null
var _restoring_time_scale: bool = false

## 全屏稀有度色光爆（懒创建；JuiceFX 是 Autoload ⇒ 跨场景复用同一个节点，切场景不重建）。
var _flash_layer: CanvasLayer = null
var _flash_rect: ColorRect = null
var _flash_tween: Tween = null


func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.run_level_up.connect(_on_run_level_up)
	EventBus.damage_taken.connect(_on_damage_taken)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	# 异常 DoT 跳字（2026-10-13 · Playground 规格「DoT 小跳字」）
	EventBus.ailment_tick.connect(_on_ailment_tick)
	# 单次冲击事件（2026-10-13 · 打击感扩展 C）：技能 / 爆炸 / BOSS 施法的屏震顿帧
	EventBus.screen_impact.connect(_on_screen_impact)
	# 稀有掉落庆祝（2026-10-14 · Playground「掉落物 pop 带星光」）
	EventBus.rare_loot_spawned.connect(_on_rare_loot_spawned)


# =============================================================================
# 命中反馈
# =============================================================================

func _on_damage_dealt(target: Node, amount: float, is_crit: bool, element: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	# 6.6 音效：暴击 → 暴击音；普通命中 → 打击音（覆盖玩家受击与敌人受击；
	# 荆棘反弹 / DoT 不经本总线，保持静默，与改动前一致）
	if is_crit:
		AudioManager.play("hit_crit")
	else:
		AudioManager.play("hit_melee")
	# 飘字是**文本**反馈，贴图替代不了 ⇒ 恒走代码绘制
	# 第四步 B4 3-E7：透传 element ⇒ 非暴击飘字按元素上色（暴击仍用暴击色，暴击优先）。
	_spawn_damage_number(target, amount, is_crit, element)
	# 命中特效：元素命中 / 暴击斩弧 / 通用火花，三者按优先级取（无贴图 = 无此效果）
	_spawn_hit_fx(target.global_position, is_crit, element)
	if target.has_method("flash"):
		target.flash()
	shake(GameConstants.SHAKE_CRIT_STRENGTH if is_crit else GameConstants.SHAKE_HIT_STRENGTH)
	# 顿帧：暴击固定档 ∪ 按伤害分级（2026-10-14 · 重击更顿）—— 合并逻辑在 `GameConstants`，
	# ⚠️ 必须**一次**调用 `hit_stop()`（它有去重，拆两次会让矮时长挤掉高时长）。
	var stop := GameConstants.hit_stop_for_hit(amount, _target_max_hp(target), is_crit)
	if stop > 0.0:
		hit_stop(stop)


## 取目标的最大生命（供「重击」分级用）。无生命组件 / 无接口 ⇒ 0（= 不按伤害顿帧）。
##
## ⚠️ 用 `get("health")` + `has_method` **鸭子探测**，而不是 `is HealthComponent`：
##    本类是纯表现层，不该反向依赖战斗组件（同 `_monster_id_of` 用 `Object.get()` 的理由）。
##    敌人（`EnemyBase`）与玩家（`PlayerController`）的属性名都是 `health`（`@onready var health`）。
func _target_max_hp(target: Node) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	var hc: Variant = target.get("health")
	if hc == null or not (hc is Node):
		return 0.0
	var o := hc as Node
	if not o.has_method("get_max_hp"):
		return 0.0
	return float(o.call("get_max_hp"))


## 命中特效，优先级：暴击斩弧 ＞ 元素命中 ＞ 通用火花。
##
## · 暴击优先保「斩弧」是有意为之：它是既有手感里「暴击更醒目」的视觉锚点，
##   不能被元素特效顶掉（否则暴击反而不如普通命中显眼）。
## · `element` 为空（物件伤害 / 未标元素的伤害）或不在表内（物理）→ 一路退到火花，
##   与引入元素贴图层之前的表现完全一致 ⇒ **换图不会变成负优化**。
func _spawn_hit_fx(pos: Vector2, is_crit: bool, element: String = "") -> void:
	if is_crit and FxTable.spawn(FX_SLASH_ARC, pos) != null:
		return
	var elem_id: String = str(ELEMENT_HIT_FX.get(element, ""))
	if not elem_id.is_empty() and FxTable.spawn(elem_id, pos) != null:
		return
	FxTable.spawn(FX_HIT_SPARK, pos)


## 死亡反馈：贴图烟尘优先；缺贴图 → 退回代码绘制的像素粒子（颜色取宿主主色）
func _on_unit_died(unit: Node, _killer: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if FxTable.spawn(FX_DEATH_PUFF, unit.global_position) != null:
		return
	var color := Color.WHITE
	if unit.has_method("get_display_color"):
		color = unit.get_display_color()
	_spawn_burst(unit.global_position, color)


# =============================================================================
# 其它事件（贴图特效，无兜底 —— 引入贴图层前本就没有对应表现，不算回归）
# =============================================================================

## 局内升级：在玩家脚下爆一圈金光
func _on_run_level_up(_new_run_level: int, _choices: Array) -> void:
	var p := _player_node()
	if p != null:
		FxTable.spawn(FX_LEVEL_UP_BURST, p.global_position)


## 敌人命中玩家：焰术信徒的攻击带自己的施法特效
func _on_damage_taken(source: Node, _amount: float, _element: String) -> void:
	if _monster_id_of(source) != MONSTER_PYROMANCER:
		return
	var s := source as Node2D
	if s != null:
		FxTable.spawn(FX_PYROMANCER_CAST, s.global_position)


## BOSS 换阶段：熔心之主迸发余烬
func _on_boss_phase_changed(enemy: Node, _phase: int, _skills: Array) -> void:
	if _monster_id_of(enemy) != MONSTER_EMBER_LORD:
		return
	var e := enemy as Node2D
	if e != null:
		FxTable.spawn(FX_EMBER_LORD_AURA, e.global_position)


## 单次冲击事件（技能命中 / 爆炸 / BOSS 技能施放）：一次事件一次反馈。
##
## ⚠️ 与 `_on_damage_dealt` 的分工：那边管**逐个命中**（飘字 / 闪白 / 轻震 / 暴击顿帧），
##    这边管**一次冲击**（重震 / 顿帧）。两者会同时发生（一次爆炸里每个受击单位仍有飘字），
##    但震屏取 max、顿帧有 `_restoring_time_scale` 去重 ⇒ 不会叠加成抖动风暴。
## `hit_stop` 复用 `hit_stop()` 的既有去重：顿帧期间再来的请求会被忽略（不延长、不重播）。
func _on_screen_impact(_position: Vector2, strength: float, hit_stop_sec: float) -> void:
	if strength > 0.0:
		shake(strength)
	if hit_stop_sec > 0.0:
		hit_stop(hit_stop_sec)


## 异常 DoT 跳字（2026-10-13 · Playground 规格「DoT 小跳字」）。
##
## `HealthComponent` 已按 `AILMENT_NUMBER_INTERVAL` 合并累计伤害后 emit；
## 本处只负责「小字号 + 异常色 + 略下移」的呈现，**不做任何结算**。
func _on_ailment_tick(host: Node, amount: float, ailment: String) -> void:
	if host == null or not is_instance_valid(host) or amount <= 0.0:
		return
	var h := host as Node2D
	if h == null:
		return
	var scene: Node = h.get_parent() if h.get_parent() != null else get_tree().current_scene
	if scene == null:
		return
	var num := FALLBACK_DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	scene.add_child(num)
	num.global_position = h.global_position + Vector2(
		randf_range(-GameConstants.DAMAGE_NUMBER_SCATTER, GameConstants.DAMAGE_NUMBER_SCATTER),
		GameConstants.DAMAGE_NUMBER_OFFSET_Y + GameConstants.DAMAGE_NUMBER_DOT_OFFSET_Y)
	num.setup_ailment(amount, ailment)


# =============================================================================
# 稀有掉落庆祝（2026-10-14 · Playground「掉落物 pop 带星光」）
# =============================================================================

## 稀有掉落庆祝：`EventBus.rare_loot_spawned`（`enemy_base.gd` 在 `rarity >= Rarity.EPIC` 时 emit）。
##
## ⚠️ 该信号此前**零消费方** —— 稀有掉落除了地面光柱（`LootDrop._draw_beam`，静态）之外
##    毫无「仪式感」，这正是暗黑刷宝类最核心的爽点（D3/D4/POE 的掉落光柱 + 音效 + 闪光）。
##    本处补上四件套：① 全屏稀有度色光爆 ② 震屏 ③ 微顿帧 ④ 掉落点稀有度色粒子爆。
##
## 强度**逐档查表**（`GameConstants.rare_drop_celebration`），不做线性公式 ——
## 套装 / 隐藏 / 深渊 / 塔不是线性档，表比公式更好调（且低档填 0 = 不庆祝）。
##
## ⚠️ `item == null` 时直接返回（Godot 允许给对象类型信号传 null；不挡会崩在 `item.rarity`）。
func _on_rare_loot_spawned(item: EquipmentInstance, position: Vector2) -> void:
	if item == null:
		return
	var rarity := item.rarity
	var cel := GameConstants.rare_drop_celebration(rarity)
	if float(cel["flash_alpha"]) > 0.0:
		_flash(GameConstants.rarity_color(rarity),
			float(cel["flash_alpha"]), float(cel["flash_time"]))
	if float(cel["shake"]) > 0.0:
		shake(float(cel["shake"]))
	if float(cel["hit_stop"]) > 0.0:
		hit_stop(float(cel["hit_stop"]))
	# 掉落点粒子爆：复用死亡表现原语（`PixelBurst`），按稀有度色 —— 零新素材、零新死钩子。
	_spawn_burst(position, GameConstants.rarity_color(rarity))


## 全屏色光爆：设色 + 设峰值透明度，然后线性淡出到 0。
##
## 重复触发（同一帧掉多件稀有）⇒ 直接重启 tween（后到者覆盖先到者），**不叠加** ——
## 否则连掉三件会闪成白屏。
func _flash(color: Color, peak_alpha: float, duration: float) -> void:
	_ensure_flash()
	if _flash_rect == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color = Color(color.r, color.g, color.b, clampf(peak_alpha, 0.0, 1.0))
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, maxf(duration, 0.01))


## 懒创建全屏光爆节点（首次稀有掉落时建；此后跨场景复用）。
##
## ⚠️ 层级 = 2：level.tscn / hub.tscn 的 HUD CanvasLayer 都是默认 `layer = 1` ⇒
##    光爆盖在 HUD 之上（整屏闪才叫「光爆」）。时长 ≤0.46s 且从低透明度淡出，不会长时间遮挡读数。
## ⚠️ `MOUSE_FILTER_IGNORE`：否则全屏 ColorRect 会吃掉所有点击（菜单点不动）。
func _ensure_flash() -> void:
	if _flash_rect != null and is_instance_valid(_flash_rect):
		return
	_flash_layer = CanvasLayer.new()
	_flash_layer.name = "RareDropFlash"
	_flash_layer.layer = 2
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.name = "Flash"
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_flash_layer.add_child(_flash_rect)


# =============================================================================
# 表现原语（代码绘制兜底）
# =============================================================================

## 目标头顶生成伤害飘字（世界空间，挂目标父节点保持图层）
## `element`（第四步 B4 3-E7）：非暴击飘字按元素上色；缺省空串 ⇒ 回退普通色（旧调用方不变）。
func _spawn_damage_number(target: Node, amount: float, is_crit: bool, element: String = "") -> void:
	var num := FALLBACK_DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	var host := target.get_parent() if target.get_parent() != null else get_tree().current_scene
	if host == null:
		return
	host.add_child(num)
	num.global_position = target.global_position + Vector2(
		randf_range(-GameConstants.DAMAGE_NUMBER_SCATTER, GameConstants.DAMAGE_NUMBER_SCATTER),
		GameConstants.DAMAGE_NUMBER_OFFSET_Y)
	num.setup(amount, is_crit, element)


## 治疗飘字（步骤 8A · 药水回血）：玩家头顶绿色 +数值（贴图/代码统一走 DamageNumber）
func spawn_heal_number(amount: float, at: Vector2) -> void:
	if amount <= 0.0:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var num := FALLBACK_DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	scene.add_child(num)
	num.global_position = at + Vector2(
		randf_range(-GameConstants.DAMAGE_NUMBER_SCATTER, GameConstants.DAMAGE_NUMBER_SCATTER),
		GameConstants.DAMAGE_NUMBER_OFFSET_Y)
	num.setup_heal(amount)


## 死亡位置生成像素粒子（贴图烟尘不可用时的兜底）
func _spawn_burst(pos: Vector2, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var burst := FALLBACK_PIXEL_BURST_SCENE.instantiate() as PixelBurst
	scene.add_child(burst)
	burst.global_position = pos
	burst.setup(color)


## 震屏：找当前场景 `main_camera` 组的 Camera2D
func shake(strength: float) -> void:
	_find_camera()
	if _shake_camera != null and _shake_camera.has_method("shake"):
		_shake_camera.shake(strength)


## 顿帧：time_scale 压到 HIT_STOP_TIME_SCALE，真实时间 seconds 后恢复。
## 恢复计时忽略 time_scale（否则顿帧期间计时也跟着变慢）。
func hit_stop(seconds: float) -> void:
	if _restoring_time_scale or Engine.time_scale < 1.0:
		return
	_restoring_time_scale = true
	Engine.time_scale = GameConstants.HIT_STOP_TIME_SCALE
	get_tree().create_timer(seconds, true, false, true).timeout.connect(_restore_time_scale)


func _restore_time_scale() -> void:
	Engine.time_scale = 1.0
	_restoring_time_scale = false


func _find_camera() -> void:
	if _shake_camera != null and is_instance_valid(_shake_camera):
		return
	_shake_camera = get_tree().get_first_node_in_group(&"main_camera")


# =============================================================================
# 小工具
# =============================================================================

func _player_node() -> Node2D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"player") as Node2D


## 取怪物 id。用 `Object.get()` 而不是 `is EnemyBase` —— 本类是纯表现层，
## 不该反向依赖敌人脚本（敌人换基类不该弄坏特效）。
func _monster_id_of(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	var v: Variant = node.get("monster_id")
	return "" if v == null else str(v)
