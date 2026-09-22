## 命中判定查询（任务 2.5 · 碰撞与命中判定）
##
## 纯静态几何判定，无物理依赖（不依赖 Area/RayCast），可在无头模式下完整验证。
## 三种命中形状：
##   circle —— 以 origin 为圆心的圆（范围技能 / 爆炸）
##   arc    —— 以 origin 为圆心、facing 为中轴的扇形（普攻 / 近战挥击）
##   rect   —— 以 origin 为起点、facing 为深度方向的矩形（横扫 / 直线武器）
##
## 目标半径扩展：可受击实体提供 `get_hit_radius()`（碰撞框半宽，2.4 敌人 / 靶子已实现）。
##   命中判定 = 攻击范围 + 目标半径（打到目标**边缘**即算命中，而非只认圆心）——
##   这是 2.5 相对 2.2 圆心判定的升级：近战打「身体」不要求精确对心。
##
## ⚠️ 不做：伤害结算（DamageCalc）、目标筛选策略（调用方传入 targets）、
##    物理碰撞（突进撞击仍走 move_and_collide，属 PlayerController）。
class_name HitQuery
extends RefCounted


## 圆形命中判定。
## targets 由调用方传入（如 enemies 组）；返回按距离升序（nearest_first=true 时）。
static func circle(
		origin: Vector2,
		radius: float,
		targets: Array[Node],
		nearest_first: bool = true,
		use_target_radius: bool = true) -> Array[Node]:
	var out: Array[Node] = []
	for target in targets:
		var node := target as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var dist := node.global_position.distance_to(origin)
		if dist <= 0.001:
			continue
		var effective := radius + (_target_radius(node) if use_target_radius else 0.0)
		if dist <= effective:
			out.append(node)
	if nearest_first and out.size() > 1:
		out.sort_custom(func(a: Node, b: Node) -> bool:
			return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	return out


## 扇形命中判定：facing 为中轴、左右各 arc_deg/2，半径 range_px。
## facing 为零向量时按 Vector2.DOWN 处理（与玩家 facing 约定一致）。
static func arc(
		origin: Vector2,
		facing: Vector2,
		range_px: float,
		arc_deg: float,
		targets: Array[Node],
		nearest_first: bool = true,
		use_target_radius: bool = true) -> Array[Node]:
	var dir := facing
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var cos_half := cos(deg_to_rad(arc_deg * 0.5))
	var out: Array[Node] = []
	for target in targets:
		var node := target as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var to_target := node.global_position - origin
		var dist := to_target.length()
		if dist <= 0.001:
			continue
		var effective := range_px + (_target_radius(node) if use_target_radius else 0.0)
		if dist > effective:
			continue
		if dir.dot(to_target / dist) < cos_half:
			continue
		out.append(node)
	if nearest_first and out.size() > 1:
		out.sort_custom(func(a: Node, b: Node) -> bool:
			return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	return out


## 矩形命中判定：从 origin 沿 facing 方向深度 depth_px、垂直方向全宽 width_px。
## 命中条件：前方投影 ∈ [0, depth + 目标半径]，侧向投影 |side| ≤ width/2 + 目标半径。
static func rect(
		origin: Vector2,
		facing: Vector2,
		width_px: float,
		depth_px: float,
		targets: Array[Node],
		use_target_radius: bool = true) -> Array[Node]:
	var dir := facing
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var half_width := width_px * 0.5
	var out: Array[Node] = []
	for target in targets:
		var node := target as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var offset := node.global_position - origin
		if offset.length_squared() <= 0.000001:
			continue
		var forward := offset.dot(dir)
		if forward < 0.0:
			continue
		var tr := _target_radius(node) if use_target_radius else 0.0
		if forward > depth_px + tr:
			continue
		if absf(offset.dot(side)) > half_width + tr:
			continue
		out.append(node)
	return out


## 读取目标碰撞半径；未实现 get_hit_radius() 的实体按 0（只认圆心）处理。
static func _target_radius(node: Node) -> float:
	if node.has_method("get_hit_radius"):
		return float(node.call("get_hit_radius"))
	return 0.0
