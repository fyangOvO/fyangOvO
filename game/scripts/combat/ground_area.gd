## 玩家持续区域实体（技能体系 §3.2 · 工单 1-L4，B3-5）
##
## 职责：在落点生成一片圆形区域 → 可选**落地一次性伤害**（`impact_multiplier`）→
##   按 `tick_interval` 周期性对半径内敌人结算 → `duration` 到期自动释放。
##
## 形态：**纯脚本实体**（不建 `.tscn`，与 `Projectile` / `enemy_projectile.gd` 同构）——
##   `GroundArea.new()` + `setup()` + `host.add_child()`；视觉由 `_draw()` 画半透明圆
##   （待美术 B7 补地面贴图后替换，见 `01-技能体系.md` §6.3）。
##
## 伤害口径（`01-技能体系.md` §5.1）：**每 tick** = `attack × multiplier × 技能等级系数`；
##   总伤害 = `impact_multiplier + multiplier × (duration / tick_interval)`，
##   与 `SkillData.total_damage_multiplier()` **逐位一致**（这是 B0 过渡实现留下的口径，
##   本批只是把「一次性打完」换成「分摊到 tick」，**总量不变**）。
##
## 落点：**玩家脚下**（用户 2026-09-29 裁定）—— 与 `ground_slam`「踏碎地面」/
##   `poison_cloud`「喷出毒云」的语义一致；「陨石落点」类技能待后续加落点字段。
##
## ⚠️ 命中判定复用 `HitQuery.circle`（排除召唤物 + 排除圆心 0.001px 内的目标）。
##    本区域圆心 = 玩家位置，不是任何敌人 ⇒ 圆心排除不影响正确性。
##
## ⚠️ 未实现（本批范围外）：`poison_cloud` / `void_rift` 描述里的「使其中毒」/
##    「把敌人拉向中心」等**附加效果**（属元素异常与位移钩子，见 `3-K*` / `1-L*`）。
class_name GroundArea
extends Node2D

## 目标组（与 `PlayerController.find_targets_*` 一致）
const TARGET_GROUP := &"enemies"

## 宿主的技能控制器（伤害管线出口；结算时回调 `on_ground_tick` / `on_ground_impact`）
var _controller: SkillController = null

## 本次施放的**有效技能数据**（已过符文修饰，是 `duplicate()` 副本）
var _data: SkillData = null

var _radius: float = 48.0
var _duration: float = 3.0
var _tick_interval: float = 0.5
## 总 tick 次数（= `round(duration / tick_interval)`，与 `total_damage_multiplier` 同口径）
var _total_ticks: int = 0
var _ticks_done: int = 0
var _elapsed: float = 0.0
## 下一次 tick 的触发时刻
var _next_tick: float = 0.0
## 落地爆发是否已结算（`impact_multiplier > 0` 时只做一次）
var _impact_done: bool = false


## 设定区域参数。调用方负责在 `add_child()` 后设置 `global_position`（落点）。
func setup(controller: SkillController, data: SkillData) -> void:
	_controller = controller
	_data = data
	_radius = maxf(data.radius, 1.0)
	_duration = maxf(data.duration, GameConstants.GROUND_TICK_MIN_INTERVAL)
	_tick_interval = maxf(data.tick_interval, GameConstants.GROUND_TICK_MIN_INTERVAL)
	_total_ticks = maxi(int(round(_duration / _tick_interval)), 1)
	_next_tick = _tick_interval


func _ready() -> void:
	# ⚠️ 落点尚未设定（`add_child()` 先于调用方赋 `global_position`）⇒ 这里**不能**结算
	#    落地爆发，否则会打在原点。等调用方定位后调 `begin()`。
	#    同理先关掉物理帧，防「落点未定就 tick」。
	set_physics_process(false)


## 落点设定完成后调用：结算落地爆发 + 启动 tick 计时 + 首次绘制。
##
## ⚠️ 为什么不放在 `_ready()`：`add_child()` 触发 `_ready` 时，`global_position` 还没被
##    调用方赋值（落点仍是 (0,0)）⇒ `impact_multiplier` 会打在原点。
##    本批自查发现，故改为显式两段式：`add_child` → 赋位置 → `begin()`。
func begin() -> void:
	if _data != null and _data.impact_multiplier > 0.0:
		_resolve_impact()
	set_physics_process(true)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _data == null:
		queue_free()
		return
	_elapsed += delta
	# 补算所有「已到点」的 tick —— 若某帧 delta 偏大，剩余 tick 会在本帧一次补齐，
	# 保证**总 tick 次数恒定**（伤害总量与帧率无关）。
	while _ticks_done < _total_ticks and _elapsed >= _next_tick:
		_resolve_tick()
		_ticks_done += 1
		_next_tick += _tick_interval
	if _elapsed >= _duration:
		queue_free()


# =============================================================================
# 结算
# =============================================================================

## 落地爆发：以区域中心为圆心的范围命中（击退取 `data.knockback`）。
func _resolve_impact() -> void:
	_impact_done = true
	for target in _targets_in_radius():
		if _controller != null:
			_controller.on_ground_impact(target, _data)


## 周期性 tick：对半径内全部敌人结算**每 tick** 伤害（无击退）。
func _resolve_tick() -> void:
	for target in _targets_in_radius():
		if _controller != null:
			_controller.on_ground_tick(target, _data)


## 半径内的敌人（复用 `HitQuery.circle`，排除召唤物）。
func _targets_in_radius() -> Array[Node]:
	var tree := get_tree()
	if tree == null:
		return []
	return HitQuery.circle(global_position, _radius,
		tree.get_nodes_in_group(TARGET_GROUP))


# =============================================================================
# 视觉（占位）
# =============================================================================

## 半透明元素配色圆 + 外圈描边（待美术 B7 补地面贴图后替换）。
func _draw() -> void:
	var col := _element_color()
	draw_circle(Vector2.ZERO, _radius, Color(col.r, col.g, col.b, 0.22))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.75), 1.5, true)


func _element_color() -> Color:
	var elem := GameConstants.ELEMENT_PHYSICAL
	if _data != null:
		elem = String(_data.element)
	return GameConstants.ELEMENT_COLORS.get(elem, Color("E8E8E8"))
