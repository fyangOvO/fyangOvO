## 震屏（任务 2.8 · 打击感）
##
## 挂在战斗场景的 Camera2D 上（组 `main_camera`）。`shake(strength)` 把 offset
## 抖到随机偏移，按 SHAKE_DECAY_PER_SEC 衰减；归零后回正。
class_name ScreenShake
extends Camera2D

var _strength: float = 0.0


func _ready() -> void:
	# 组由脚本注册（tscn 的 groups 属性在部分加载路径下不生效）
	add_to_group(&"main_camera")


## 触发震屏（强度 px；多次触发取强值，防叠抖）
func shake(strength: float) -> void:
	_strength = maxf(_strength, strength)


func _process(delta: float) -> void:
	if _strength <= 0.0:
		return
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _strength
	_strength = maxf(_strength - GameConstants.SHAKE_DECAY_PER_SEC * delta, 0.0)
	if _strength <= 0.0:
		offset = Vector2.ZERO
