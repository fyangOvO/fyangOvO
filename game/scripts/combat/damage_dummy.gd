## 受击靶（任务 2.2 · 伤害出口的验证占位）
##
## 用途：
##   · 无头验证 / 渲染预览里的「假敌人」——提供 `take_damage` 与 `apply_knockback`
##     接口，让技能控制器在 2.4 敌人 AI / 2.6 生命系统就绪前可被完整验证。
##   · 本类**不是**敌人基类。阶段 2.4 的 EnemyBase 将实现相同接口并加入 `enemies` 组，
##     届时替换靶子即可，技能控制器的调用方无需改动。
##
## 接口契约（所有可受击实体必须一致，阶段 2.6 会收编为统一组件）：
##   take_damage(amount: float, source: Node)
##   apply_knockback(offset: Vector2)
##
## ⚠️ 必须是 StaticBody2D：突进技能用 `move_and_collide` 物理检测撞击，
##    CollisionShape2D 需要 CollisionObject2D 祖先才会注册到物理服务。
class_name DamageDummy
extends StaticBody2D

## 加入 `enemies` 组（技能控制器按此组查找目标）
func _ready() -> void:
	add_to_group(&"enemies")
	if damage_display != null:
		damage_display.texture = _solid_texture(24, 24, Color("B3BCC9"))
		damage_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## 初始生命（验证脚本可覆盖）
@export var hp: float = 100.0

## 防御属性（任务 2.3 伤害管线读取；验证脚本可覆盖以测减伤）
## 护甲 → 物理减伤 DR = ARM/(ARM + 50×L)；元素抗性 → 对应元素减伤（同构公式）。
@export var armor: float = 0.0
@export var level: int = 1

## 元素抗性（element → 百分数值；默认全 0）
var resists: Dictionary = {}


## 伤害管线读取接口（DamageCalc.target_* 统一调用；2.4 敌人基类实现同名接口）
func get_armor() -> float:
	return armor


func get_resist(element: String) -> float:
	return float(resists.get(element, 0.0))


func get_level() -> int:
	return level


## 受击命中半径（2.5 命中判定目标半径扩展）：靶子 24×24 → 半宽 12px。
func get_hit_radius() -> float:
	return 12.0


## 收到伤害累计（验证用）
var total_damage_taken: float = 0.0

## 击退累计位移（验证用）
var total_knockback: float = 0.0

## 是否已被「击杀」（hp <= 0）
var is_dead: bool = false

## 伤害日志（验证断言用；条数上限防内存膨胀）
var damage_log: Array[float] = []

@onready var damage_display: Sprite2D = $DamageDisplay


## 受击入口（契约）。source 为攻击方节点。
func take_damage(amount: float, _source: Node) -> void:
	if is_dead:
		return
	hp -= amount
	total_damage_taken += amount
	damage_log.append(amount)
	if damage_log.size() > 200:
		damage_log.pop_front()
	if hp <= 0.0:
		is_dead = true
	# 受击闪白（最小打击反馈；阶段 2.8 由正式打击感管线接管）
	_flash_hit()
	print("[DamageDummy] 受击 -%.1f（剩余 HP %.1f）%s" % [amount, hp, "→ 死亡" if is_dead else ""])


## 受击闪白：0.08s 内亮一下再回原色（占位特效，无头模式同样生效）
func _flash_hit() -> void:
	if damage_display == null:
		return
	var tween := create_tween()
	tween.tween_property(damage_display, "modulate", Color(2.2, 2.2, 2.2), 0.04)
	tween.tween_property(damage_display, "modulate", Color.WHITE, 0.10)


## 击退入口（契约）。offset 为位移向量（px）。
func apply_knockback(offset: Vector2) -> void:
	total_knockback += offset.length()
	position += offset


func reset(hp_value: float = 100.0) -> void:
	hp = hp_value
	total_damage_taken = 0.0
	total_knockback = 0.0
	is_dead = false
	damage_log.clear()
	armor = 0.0
	level = 1
	resists.clear()


func _solid_texture(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
