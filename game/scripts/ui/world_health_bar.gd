## 世界空间血条（阶段 2 · 任务 2.6 · 怪物头顶）
##
## 美术规范 0.7 v1.4 附录「UI 元件」：怪物血条 8px 高；底槽 `#14171C`；
## 血量 `#C42B2B`→`#8C1A1F` 渐变；1px `#0B0D10` 描边；护盾叠 `#3A5FB0`。
##
## 挂在实体子节点，跟随实体移动；实体死亡 queue_free 时随父一起消失。
## 兼容读取：优先 get_current_hp / get_max_hp / get_shield 方法接口，
## 回退到 `current_hp` 属性 + `data.get_hp(level, difficulty_tier)`（EnemyBase 简易生命）。
class_name WorldHealthBar
extends Node2D

## 绑定实体（EnemyBase 等；NodePath 便于 .tscn 引用父节点）
@export var target_path: NodePath = NodePath("..")

## 血条宽（px）。32 = 敌人占位色块尺寸，头顶 8px 高（美术规范）。
@export var width_px: float = 32.0

## 血条高（px）
@export var height_px: float = GameConstants.UI_HP_BAR_HEIGHT_MONSTER

## 相对实体的垂直偏移（负值向上，让血条悬在头顶）
@export var offset_y: float = -22.0

## 【L6】视口内缩 4px 的安全框：敌人**身体**（精灵矩形）不完全落在里面 ⇒ 不画血条。
##
## 为什么判据是「身体是否被裁」而不是「血条自身是否在屏内」：
## 屏边敌人**只有一条红条可见、身体在屏外**时，玩家会把它读成噪点 / UI 元素。
## 身体被裁时血条本来就读不出来，屏边敌人短暂「无血条」是**正确**的。
const HP_BAR_SAFE := Rect2(4, 4, 632, 352)

var _target: Node = null
var _grad_tex: GradientTexture2D = null


func _ready() -> void:
	if target_path != null and not target_path.is_empty():
		_target = get_node_or_null(target_path)
		if _target == null:
			_target = get_parent()
	_grad_tex = GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = [GameConstants.UI_HP_BAR_GRADIENT_FROM, GameConstants.UI_HP_BAR_GRADIENT_TO]
	_grad_tex.gradient = grad
	_grad_tex.fill = GradientTexture2D.FILL_LINEAR
	_grad_tex.fill_from = Vector2(0.0, 0.0)
	_grad_tex.fill_to = Vector2(1.0, 0.0)
	_grad_tex.width = 32
	_grad_tex.height = 8


func _process(_delta: float) -> void:
	# 死亡 / 已释放实体不绘制（queue_free 前最后几帧 is_dead 也隐藏）
	var dead := false
	if _target != null and _target.get("is_dead") != null:
		dead = bool(_target.get("is_dead"))
	if _target == null or not is_instance_valid(_target) or dead:
		visible = false
		return
	visible = true
	# 【L6】身体被视口裁切 ⇒ 血条不画（见 `HP_BAR_SAFE` 的说明）。
	# ⚠️ 判据必须走**世界坐标的精灵矩形**，不能用血条自身的 `visible` / `position` 推算 ——
	#    那正是本缺陷的成因（血条挂在实体下、永远「在屏内」附近，推算不出身体已被裁）。
	if not _body_fully_in_safe_area():
		visible = false
		return
	queue_redraw()


## 敌人身体（精灵矩形）是否完整落在视口安全框内。
## 取不到精灵 / 精灵没有有效尺寸时**返回 true**（不隐藏）—— 宁可多画一条血条，
## 也不要因为素材缺失导致全场没有血条。
func _body_fully_in_safe_area() -> bool:
	var sprite := _body_sprite()
	if sprite == null:
		return true
	var vp := get_viewport()
	if vp == null:
		return true
	# `Sprite2D.get_rect()` 是**局部**矩形（含 centered / offset，不含 scale），
	# 套精灵全局变换 → 世界坐标矩形；再套画布变换（含相机缩放 / 位移）→ 视口像素矩形。
	var world: Rect2 = sprite.get_global_transform() * sprite.get_rect()
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		return true
	var in_viewport: Rect2 = vp.get_canvas_transform() * world
	return HP_BAR_SAFE.encloses(in_viewport)


## 敌人本体的精灵节点。优先 `Body`（`enemy_base.tscn` 的节点名），
## 兼容玩家侧命名 `BodySprite`，再兜底第一个 Sprite2D 子节点。
func _body_sprite() -> Sprite2D:
	if _target == null or not is_instance_valid(_target):
		return null
	for n in ["Body", "BodySprite"]:
		var s := _target.get_node_or_null(NodePath(n))
		if s is Sprite2D:
			return s
	for child in _target.get_children():
		if child is Sprite2D:
			return child
	return null


func _draw() -> void:
	if _target == null:
		return
	var cur := _read_hp()
	var max_hp := _read_max_hp()
	if max_hp <= 0.0:
		return
	var ratio := clampf(cur / max_hp, 0.0, 1.0)
	var w := width_px
	var h := height_px
	# 血条中心对齐实体，垂直悬在头顶
	var pos := Vector2(-w * 0.5, offset_y)
	var full := Rect2(pos, Vector2(w, h))

	draw_rect(full, GameConstants.UI_HP_BAR_BG)
	var hp_rect := Rect2(pos.x + 1.0, pos.y + 1.0, maxf((w - 2.0) * ratio, 0.0), h - 2.0)
	if hp_rect.size.x > 0.0 and _grad_tex != null:
		draw_texture_rect(_grad_tex, hp_rect, false)
	draw_rect(Rect2(pos.x + 1.0, pos.y + 1.0, w - 2.0, 1.0), Color("E8573F"))
	draw_rect(full, GameConstants.UI_HP_BAR_OUTLINE, false, 1.0)


func _read_hp() -> float:
	if _target.has_method("get_current_hp"):
		return float(_target.call("get_current_hp"))
	if _target.get("current_hp") != null:
		return float(_target.get("current_hp"))
	return 0.0


func _read_max_hp() -> float:
	if _target.has_method("get_max_hp"):
		return float(_target.call("get_max_hp"))
	if _target.get("data") != null:
		var data: Object = _target.get("data")
		var level: int = _target.get("level") if _target.get("level") != null else 1
		var tier: int = _target.get("difficulty_tier") if _target.get("difficulty_tier") != null else 0
		if data.has_method("get_hp"):
			return float(data.call("get_hp", level, tier))
	return 0.0
