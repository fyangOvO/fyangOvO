## 玩家持续区域实体（技能体系 §3.2 · 工单 1-L4，B3-5）
##
## 职责：在落点生成一片圆形区域 → 可选**落地一次性伤害**（`impact_multiplier`）→
##   按 `tick_interval` 周期性对半径内敌人结算 → `duration` 到期自动释放。
##
## 形态：**纯脚本实体**（不建 `.tscn`，与 `Projectile` / `enemy_projectile.gd` 同构）——
##   `GroundArea.new()` + `setup()` + `host.add_child()`；视觉为**元素对应的 `ground_*` 贴图**
##   （2026-10-14 起接通，见 `GROUND_FX_BY_ELEMENT`）+ `_draw()` 画 AoE 外圈；无贴图时退回代码圆。
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

## 元素 → 地面残留贴图（`data/fx.json` 的 id）。
##
## 2026-10-14 打击感/juice：这 5 张 `ground_*` 贴图此前是**死资产** —— `fx.json` 里定义了、
## `assets/fx/` 里有 PNG，但**全项目零 spawn 调用**（`_draw()` 只画代码圆）。本批接通。
##
## ⚠️ 键必须覆盖 `GameConstants.ELEMENTS` 的**全部值**（见 `_spawn_decal` 的兜底）；
##    `cold` 刻意复用 `ground_crack`（无 `ground_cold` 素材，且当前无冰系地面技）。
const GROUND_FX_BY_ELEMENT: Dictionary = {
	"physical": "ground_crack",
	"fire": "ground_meteor",
	"cold": "ground_crack",
	"lightning": "ground_thunder",
	"poison": "ground_poison",
	"shadow": "ground_void",
}
## 取不到 spec 时的 frame_w 兜底（`FxTable.spec()` 返回空字典时用）
const GROUND_FX_FRAME_W_FALLBACK := 32
## 地面残留贴图的不透明度。
## ⚠️ 为什么不是 1.0：本区域挂在 `Actors` 下、与敌人同层，**自绘会盖在更早入树的敌人之上**。
##    全不透明会把站在池里的敌人整只遮住；半透明则读作「站在池中」，可读性最好。
const GROUND_DECAL_ALPHA := 0.7

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

## 地面残留贴图状态（`ground_*` 循环序列帧）。**由本节点自绘**（不建子节点、不设 z_index）。
##
## ⚠️ 为什么自绘而不用 `FxTable.spawn()` 挂子节点：`z_index` 是**相对父节点递归**的，而本区域挂在
##    `Actors` 下、与 `LevelView` 同层 z=0 ⇒ 用 `fx.json` 的 `below_actors`(−1) 会**沉到整张地图之下**
##    （正是 `player_controller.gd:1337` 记录过的投影坑），用 `above_actors`(+6) 又会盖住敌人。
##    自绘天然落在「地图之上、与 Actor 同层」，且绘制次序**显式可控**（先贴图、后描边）。
## 贴图仍由 `FxTable` 三级解析（用户目录 → 内置）⇒ **换图不改代码**的契约不变。
## `_decal_tex == null`（表里没这个 id / PNG 缺失）⇒ 退回半透明圆填充，与引入贴图层前逐位一致。
var _decal_tex: Texture2D = null
var _decal_fw: int = 0
var _decal_fh: int = 0
var _decal_frames: int = 1
var _decal_fps: float = 12.0
var _decal_scale: int = 1
var _decal_elapsed: float = 0.0
var _decal_frame: int = 0


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
	# 贴图解析与落点无关（自绘，不走 global_position），但放在 `begin()` 是为了与 tick 同步启用，
	# 且 `_ready()` 里 `_data` 可能尚未 `setup()`。
	_setup_decal()
	set_physics_process(true)
	queue_redraw()


## 解析地面残留贴图（Playground 规格「地面殘留」）。
##
## 失败（表里没这个 id / PNG 缺失）⇒ `_decal_tex` 保持 `null`，`_draw()` 自动退回代码圆填充 ——
## **不崩、不静默画错**（与 `JuiceFX` 的「贴图优先、代码兜底」同一范式）。
func _setup_decal() -> void:
	var id := str(GROUND_FX_BY_ELEMENT.get(_element(), "ground_crack"))
	_decal_tex = FxTable.texture_for(id)
	if _decal_tex == null:
		return
	var sp := FxTable.spec(id)
	_decal_fw = maxi(int(sp.get("frame_w", GROUND_FX_FRAME_W_FALLBACK)), 1)
	_decal_fh = maxi(int(sp.get("frame_h", GROUND_FX_FRAME_W_FALLBACK)), 1)
	_decal_fps = maxf(float(sp.get("fps", 12.0)), 0.001)
	# 帧数夹取口径与 `FxSprite.setup()` 一致：spec 写多了就夹到贴图装得下的帧数
	_decal_frames = clampi(int(sp.get("frames", 1)), 1,
		maxi(int(_decal_tex.get_width()) / _decal_fw, 1))
	# 像素铁律：**整数缩放**。取 **ceil** ⇒ 贴图边长 ≥ 区域直径。
	# ⚠️ 为什么宁可略大：贴图是玩家读「哪里危险」的主要视觉，**小于** AoE 会让边缘那圈
	#    看起来像安全区（不公平）；略大于只是「多躲一点」（可接受）。
	_decal_scale = maxi(1, ceili(_radius * 2.0 / float(_decal_fw)))
	_decal_elapsed = 0.0
	_decal_frame = 0


## 推进循环帧（`loop` 语义内联于此 —— 自绘就不经过 `FxSprite`）。
## 只在**帧号真的变化**时 `queue_redraw()`，避免每帧重绘。
func _advance_decal(delta: float) -> void:
	if _decal_tex == null or _decal_frames <= 1:
		return
	var cycle := float(_decal_frames) / _decal_fps
	_decal_elapsed = fmod(_decal_elapsed + delta, cycle)
	var f := mini(int(_decal_elapsed * _decal_fps), _decal_frames - 1)
	if f != _decal_frame:
		_decal_frame = f
		queue_redraw()


func _physics_process(delta: float) -> void:
	if _data == null:
		queue_free()
		return
	_advance_decal(delta)
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
##
## 2026-10-13 打击感 C：落地爆发是**世界事件**（陨石砸地 / 大地践踏），无论是否命中
## 目标都要震屏 + 顿帧（玩家躲开时地面照样在震，才叫「重」）。震屏强度按区域半径分级。
func _resolve_impact() -> void:
	_impact_done = true
	EventBus.screen_impact.emit(global_position,
		GameConstants.SHAKE_IMPACT_EXPLOSION,
		GameConstants.HIT_STOP_IMPACT_EXPLOSION)
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
# 视觉
# =============================================================================

## 地面表现（2026-10-14 起「贴图优先、代码绘制兜底」，与 `JuiceFX` 同一范式）。
##
## · 有 `ground_*` 贴图 ⇒ 贴图充当**填充**（自绘，见 `_draw_decal`）；
## · 无贴图 ⇒ 退回「半透明元素配色圆 + 外圈描边」，与引入贴图层前**逐位一致**。
##
## 外圈描边**恒画**：它是 **AoE 边界**，必须精确（贴图是整数缩放，边长只会略大于直径）。
func _draw() -> void:
	var col := _element_color()
	if _decal_tex != null:
		_draw_decal()
	else:
		draw_circle(Vector2.ZERO, _radius, Color(col.r, col.g, col.b, 0.22))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.75), 1.5, true)


## 画当前帧：贴图**居中**、整数缩放（`_decal_scale`）。
## 用 `draw_texture_rect_region` 而不是 `Sprite2D` —— 与 `fx_sprite.gd` 同一理由：
## 一个 CanvasItem = 一个 draw call、零资源分配，且整数缩放不引入插值糊边。
func _draw_decal() -> void:
	var w := float(_decal_fw * _decal_scale)
	var h := float(_decal_fh * _decal_scale)
	var src := Rect2(float(_decal_frame * _decal_fw), 0.0, float(_decal_fw), float(_decal_fh))
	draw_texture_rect_region(_decal_tex, Rect2(-w * 0.5, -h * 0.5, w, h), src,
		Color(1.0, 1.0, 1.0, GROUND_DECAL_ALPHA))


## 本次施放的元素（`_data` 为空时按物理处理）。
func _element() -> String:
	if _data != null:
		return String(_data.element)
	return GameConstants.ELEMENT_PHYSICAL


func _element_color() -> Color:
	return GameConstants.ELEMENT_COLORS.get(_element(), Color("E8E8E8"))
