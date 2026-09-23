## 全局打击感控制器（任务 2.8 · Autoload「JuiceFX」）
##
## 监听总线事件，把「伤害结算」翻译成「打击感表现」，全程不碰结算逻辑：
##   - `EventBus.damage_dealt(target, amount, is_crit, element)` →
##       目标头顶飘字 + 命中火花（贴图）/ 暴击斩弧（贴图）+ 目标闪白 + 震屏 + 暴击顿帧
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


func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.run_level_up.connect(_on_run_level_up)
	EventBus.damage_taken.connect(_on_damage_taken)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)


# =============================================================================
# 命中反馈
# =============================================================================

func _on_damage_dealt(target: Node, amount: float, is_crit: bool, _element: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	# 6.6 音效：暴击 → 暴击音；普通命中 → 打击音（覆盖玩家受击与敌人受击；
	# 荆棘反弹 / DoT 不经本总线，保持静默，与改动前一致）
	if is_crit:
		AudioManager.play("hit_crit")
	else:
		AudioManager.play("hit_melee")
	# 飘字是**文本**反馈，贴图替代不了 ⇒ 恒走代码绘制
	_spawn_damage_number(target, amount, is_crit)
	# 命中火花 / 暴击斩弧：贴图优先（无贴图 = 无此效果，与引入贴图层之前的手感一致）
	_spawn_hit_fx(target.global_position, is_crit)
	if target.has_method("flash"):
		target.flash()
	shake(GameConstants.SHAKE_CRIT_STRENGTH if is_crit else GameConstants.SHAKE_HIT_STRENGTH)
	if is_crit:
		hit_stop(GameConstants.HIT_STOP_DURATION)


## 命中特效：暴击用斩弧（更大、更醒目），普通命中用火花。
## 暴击斩弧缺失时退回火花 —— 保证「暴击一定比普通更醒目」这条既有手感不被贴图层破坏。
func _spawn_hit_fx(pos: Vector2, is_crit: bool) -> void:
	if is_crit and FxTable.spawn(FX_SLASH_ARC, pos) != null:
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


# =============================================================================
# 表现原语（代码绘制兜底）
# =============================================================================

## 目标头顶生成伤害飘字（世界空间，挂目标父节点保持图层）
func _spawn_damage_number(target: Node, amount: float, is_crit: bool) -> void:
	var num := FALLBACK_DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	var host := target.get_parent() if target.get_parent() != null else get_tree().current_scene
	if host == null:
		return
	host.add_child(num)
	num.global_position = target.global_position + Vector2(
		randf_range(-GameConstants.DAMAGE_NUMBER_SCATTER, GameConstants.DAMAGE_NUMBER_SCATTER),
		GameConstants.DAMAGE_NUMBER_OFFSET_Y)
	num.setup(amount, is_crit)


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
