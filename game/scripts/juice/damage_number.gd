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


## 初始化：金额 / 是否暴击 / 伤害元素（第四步 B4 `3-E7` 元素飘字配色表）。
##
## 配色优先级（用户拍板「暴击优先」）：
##   暴击          → `COLOR_DAMAGE_CRIT`（保留「暴击更醒目」的视觉锚点，与
##                    `JuiceFX._spawn_hit_fx` 的「暴击斩弧优先」同口径）；
##   非暴击 + 有元素 → `ELEMENT_COLORS[element]`（6 元素各一色，**单一来源**，与投射物/地面区域共用）；
##   非暴击 + 无元素 → `COLOR_DAMAGE_NORMAL`（向后兼容：旧调用方不传 `element` 时逐位不变）。
##
## ⚠️ 物理飘字由 `COLOR_DAMAGE_NORMAL`(DCE2E8) 变为 `ELEMENT_COLORS[physical]`(E8E8E8) ——
##    两者皆为银白、肉眼不可分辨，是 `3-E7`「6 元素各一色」的既定口径。
func setup(amount: float, is_crit: bool, element: String = "") -> void:
	add_to_group(&"juice_numbers")
	_start_ms = Time.get_ticks_msec()
	var label: Label = $Label
	label.text = str(roundi(amount))
	if is_crit:
		label.add_theme_color_override("font_color", GameConstants.COLOR_DAMAGE_CRIT)
		label.add_theme_font_size_override("font_size", GameConstants.DAMAGE_NUMBER_CRIT_FONT_SIZE)
	else:
		label.add_theme_color_override("font_color", normal_color_for(element))
		label.add_theme_font_size_override("font_size", GameConstants.DAMAGE_NUMBER_FONT_SIZE)


## 非暴击飘字配色：有元素 ⇒ 元素色；空串 / 未知元素 ⇒ 回退普通色。
## 抽成方法便于无头断言（不必真实例化节点即可验配色口径）。
static func normal_color_for(element: String) -> Color:
	if element.is_empty():
		return GameConstants.COLOR_DAMAGE_NORMAL
	return GameConstants.ELEMENT_COLORS.get(element, GameConstants.COLOR_DAMAGE_NORMAL)


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
