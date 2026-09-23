## 伤害飘字（任务 2.8 · 打击感）
##
## 世界空间 Node2D + Label（套项目默认主题 → Cubic-11 像素字体）。
## 受击目标头顶生成：上飘 + 淡出 + 轻微放大；暴击橙红大字。
## 像素风铁律：Label 位置 / 缩放取整，避免像素字发糊。
class_name DamageNumber
extends Node2D

var _lifetime: float = 0.0
var _rise_speed: float = GameConstants.DAMAGE_NUMBER_RISE_SPEED
var _duration: float = GameConstants.DAMAGE_NUMBER_LIFETIME
var _start_ms: int = 0


## 初始化：金额 / 是否暴击（样式由字体颜色 + 字号区分）
func setup(amount: float, is_crit: bool) -> void:
	add_to_group(&"juice_numbers")
	_start_ms = Time.get_ticks_msec()
	var label: Label = $Label
	label.text = str(roundi(amount))
	if is_crit:
		label.add_theme_color_override("font_color", GameConstants.COLOR_DAMAGE_CRIT)
		label.add_theme_font_size_override("font_size", GameConstants.DAMAGE_NUMBER_CRIT_FONT_SIZE)
	else:
		label.add_theme_color_override("font_color", GameConstants.COLOR_DAMAGE_NORMAL)
		label.add_theme_font_size_override("font_size", GameConstants.DAMAGE_NUMBER_FONT_SIZE)


## 治疗飘字（步骤 8A · 药水回血）：绿色、正常字号
func setup_heal(amount: float) -> void:
	setup(amount, false)
	var label: Label = $Label
	label.add_theme_color_override("font_color", GameConstants.COLOR_HEAL)


func _process(delta: float) -> void:
	# 寿命用真实时间（毫秒）：顿帧（time_scale<1）期间飘字不加速老化
	var t := float(Time.get_ticks_msec() - _start_ms) / 1000.0 / _duration
	if t >= 1.0:
		queue_free()
		return
	# 上飘 + 淡出（像素风铁律：不做非整数缩放，避免像素字发糊）
	position.y -= _rise_speed * delta
	modulate.a = 1.0 - t
	# 像素对齐：位置取整（Nearest 渲染下防糊）
	position = position.round()
