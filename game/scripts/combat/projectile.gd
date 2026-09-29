## 玩家投射物实体（技能体系 §3.2 · 工单 1-L3，B3-5）
##
## 职责：直线飞行 → 命中结算（走 `SkillController` 的**完整伤害管线**）→ 穿透 / 连锁 / 分裂。
##
## 形态：**纯脚本实体**（不建 `.tscn`，与 `enemies/enemy_projectile.gd` 同构）——
##   `Projectile.new()` + `setup()` + `host.add_child()`；占位精灵由代码生成
##   （8×8 元素配色块，待美术 B7 补 16×16 循环帧，见 `01-技能体系.md` §6.3）。
##
## 伤害口径（`01-技能体系.md` §5.1）：
##   · **每发**伤害 = `attack × multiplier × 技能等级系数`（由 `SkillController` 结算）；
##   · 多发射击（`projectile_count > 1`）各发**独立**结算 ⇒ 全中 = N × multiplier（设计值，
##     如 `multishot` 3 发 × 100% = 300%）；
##   · 连锁：命中后弹射至 `chain_count` 个**额外**目标，每跳 ×`(1 - chain_decay_pct/100)`；
##   · 分裂：命中后从命中点放射 `split_count` 枚子投射物，每枚 ×`split_damage_pct/100`；
##   · 穿透：命中后不消失，最多再命中 `pierce_count` 个额外目标。
##
## ⚠️ `_hit_set` 防重复命中：穿透弹在目标体内会**多帧重叠**，若不记录已命中目标，
##    同一目标会被反复扣血（这是「穿透」最经典的实现坑）。
##
## ⚠️ 未实现（本批范围外，见工单标题「飛行 / 命中 / 穿透 / 分裂 / 連鎖」）：
##    `explosive_arrow` 的**命中爆炸**（`radius` 范围伤害）—— `radius` 字段对投射物
##    无法区分「显式声明」与「默认 48」（`config_loader` 兜底值），需后续加专用字段。
class_name Projectile
extends Node2D

## 目标组（与 `PlayerController.find_targets_*` 一致）
const TARGET_GROUP := &"enemies"

## 宿主的技能控制器（伤害管线出口；命中时回调 `on_projectile_hit`）
var _controller: SkillController = null

## 本次施放的**有效技能数据**（已过符文修饰，是 `duplicate()` 副本）
var _data: SkillData = null

var _dir: Vector2 = Vector2.RIGHT
var _speed: float = 400.0
var _max_range: float = 150.0
var _traveled: float = 0.0
var _life: float = GameConstants.PROJECTILE_MAX_LIFETIME

## 剩余可穿透次数（每命中一个目标减 1；>0 时命中不消失）
var _pierce_left: int = 0
## 剩余可连锁跳数（命中后弹射；每跳减 1）
var _chain_left: int = 0
## 连锁每跳衰减百分比
var _chain_decay_pct: float = 0.0
## 命中后分裂枚数与伤害占比
var _split_count: int = 0
var _split_damage_pct: float = 0.0
## 本次命中的伤害系数（分裂子投射物 = 母弹 × `split_damage_pct/100`）
var _damage_scale: float = 1.0

## 已命中目标（instance_id → true），防穿透弹重复扣血
var _hit_set: Dictionary = {}
## 是否已分裂（每次施放只分裂一次，防子投射物再分裂成无限树）
var _split_done: bool = false
## 已消亡标记（命中后到 `queue_free()` 生效前不再结算）
var _dead: bool = false

var _body: Sprite2D = null


## 设定飞行参数。
##
## `damage_scale`：本次命中伤害系数（分裂子投射物继承母弹 × 百分比）。
## `range_override`：覆盖飞行距离（>0 时生效；分裂子投射物用 `PROJECTILE_SPLIT_RANGE`）。
## `is_child`：是否为分裂子投射物 ⇒ **不再**穿透 / 连锁 / 二次分裂（防无限分裂）。
func setup(controller: SkillController, data: SkillData, direction: Vector2,
		damage_scale: float = 1.0, range_override: float = -1.0,
		is_child: bool = false) -> void:
	_controller = controller
	_data = data
	if direction.length_squared() > 0.0001:
		_dir = direction.normalized()
	_speed = maxf(data.projectile_speed, 1.0)
	_max_range = range_override if range_override > 0.0 else maxf(data.range, 1.0)
	# 存活 = 飞完射程所需时间 + 余量；再与兜底上限取小（防 range/速度 配错）
	_life = minf(_max_range / _speed + 0.25, GameConstants.PROJECTILE_MAX_LIFETIME)
	_damage_scale = damage_scale
	if is_child:
		_pierce_left = 0
		_chain_left = 0
		_split_count = 0
	else:
		_pierce_left = maxi(data.pierce_count, 0)
		_chain_left = maxi(data.chain_count, 0)
		_chain_decay_pct = maxf(data.chain_decay_pct, 0.0)
		_split_count = maxi(data.split_count, 0)
		_split_damage_pct = maxf(data.split_damage_pct, 0.0)


func _ready() -> void:
	_body = Sprite2D.new()
	_body.texture = _make_placeholder()
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.centered = true
	add_child(_body)


func _physics_process(delta: float) -> void:
	if _dead or _data == null:
		return
	var step := _speed * delta
	position += _dir * step
	_traveled += step
	_life -= delta
	if _traveled >= _max_range or _life <= 0.0:
		queue_free()
		return
	_try_hit()


# =============================================================================
# 命中
# =============================================================================

## 每帧检查是否与 `enemies` 组中的「未命中」目标相交。
## 一帧只结算**最近的一个**（穿透顺序可控，也避免同帧多次扣血）。
func _try_hit() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var origin := global_position
	var best: Node2D = null
	var best_dist := INF
	for n in tree.get_nodes_in_group(TARGET_GROUP):
		var node := n as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if _hit_set.has(node.get_instance_id()):
			continue
		var d := origin.distance_to(node.global_position)
		if d <= GameConstants.PROJECTILE_HIT_RADIUS + _target_radius(node) and d < best_dist:
			best = node
			best_dist = d
	if best == null:
		return
	_on_hit_target(best)


func _on_hit_target(target: Node2D) -> void:
	_hit_set[target.get_instance_id()] = true
	if _controller != null:
		_controller.on_projectile_hit(target, _data, _damage_scale)
	# 连锁：从命中点弹射（每次施放只解析一次，之后 `_chain_left` 归零）
	if _chain_left > 0:
		_resolve_chain(target)
		_chain_left = 0
	# 分裂：从命中点放射子投射物（每次施放只一次）
	if _split_count > 0 and not _split_done:
		_split_done = true
		_spawn_split(target.global_position)
	# 穿透：还有次数则继续飞，否则消亡
	if _pierce_left > 0:
		_pierce_left -= 1
		return
	_dead = true
	queue_free()


## 连锁弹射：从 `from_target` 起逐跳找最近的**未命中**敌人，每跳伤害 ×`(1-decay)`。
## 连锁是**瞬时**结算（不生成新弹体）—— 与 `lightning_chain`「电弧」的观感一致。
func _resolve_chain(from_target: Node2D) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var decay := 1.0 - clampf(_chain_decay_pct, 0.0, 100.0) / 100.0
	var scale := _damage_scale * decay
	var from := from_target.global_position
	for _i in range(_chain_left):
		var next := _nearest_unhit(tree, from, GameConstants.PROJECTILE_CHAIN_RANGE)
		if next == null:
			return
		_hit_set[next.get_instance_id()] = true
		if _controller != null:
			_controller.on_projectile_hit(next, _data, scale)
		from = next.global_position
		scale *= decay


## 命中分裂：从命中点向四周均匀放射 `split_count` 枚子投射物。
## 子投射物伤害 = 母弹 × `split_damage_pct/100`，且**不再**穿透 / 连锁 / 分裂。
##
## ⚠️ 子投射物**继承母弹的 `_hit_set`** —— 碎片不该回头再打母弹已经打过的目标
##    （否则在贴身命中时会「3 枚碎片全砸回同一只」，等于白送 150% 伤害）。
func _spawn_split(origin: Vector2) -> void:
	var host := get_parent()
	if host == null:
		return
	var count := maxi(_split_count, 1)
	var scale := _damage_scale * clampf(_split_damage_pct, 0.0, 100.0) / 100.0
	var base_angle := _dir.angle()
	for i in range(count):
		var ang := base_angle + TAU * float(i) / float(count)
		var child := Projectile.new()
		child.setup(_controller, _data, Vector2.from_angle(ang), scale,
			GameConstants.PROJECTILE_SPLIT_RANGE, true)
		child._hit_set = _hit_set.duplicate()
		host.add_child(child)
		child.global_position = origin


## 找 `origin` 附近 `radius` 内最近的、尚未命中的敌人（连锁用）。
func _nearest_unhit(tree: SceneTree, origin: Vector2, radius: float) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for n in tree.get_nodes_in_group(TARGET_GROUP):
		var node := n as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if _hit_set.has(node.get_instance_id()):
			continue
		var d := origin.distance_to(node.global_position)
		if d <= radius + _target_radius(node) and d < best_dist:
			best = node
			best_dist = d
	return best


## 读取目标碰撞半径（`HitQuery._target_radius` 同口径）；未实现的实体按 0。
func _target_radius(node: Node) -> float:
	if node.has_method("get_hit_radius"):
		return float(node.call("get_hit_radius"))
	return 0.0


# =============================================================================
# 视觉（占位）
# =============================================================================

## 8×8 元素配色占位块（待美术 B7 补 16×16 循环帧后替换）。
func _make_placeholder() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(_element_color())
	return ImageTexture.create_from_image(img)


func _element_color() -> Color:
	var elem := GameConstants.ELEMENT_PHYSICAL
	if _data != null:
		elem = String(_data.element)
	return GameConstants.ELEMENT_COLORS.get(elem, Color("E8E8E8"))
