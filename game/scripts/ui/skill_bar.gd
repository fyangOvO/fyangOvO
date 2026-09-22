## 局内技能栏（步骤 6 · 2026-09-22 · class_name）
##
## 显示 3 个出战技能槽（1/2/3 键）：图标（UISkin skill_icon_*，缺图回退空槽贴图）
## + 键位角标 + 冷却遮罩（从槽顶向下按剩余比例变暗 + 剩余秒数）。
## 纯展示（mouse_filter IGNORE）；数据只读 `SkillController` 的查询接口。
## 每帧重绘（槽数少，比事件驱动简单可靠；与 HealthBar 同策略）。
class_name SkillBarUI
extends Control

## 出战槽数（与 project.godot skill_1/2/3 + PlayerController 输入一致）
const SLOT_COUNT: int = 3
## 槽边长（px）。与 skill_slot_48 / skill_icon_*_48 原生尺寸一致 ⇒ 1× 整数
const SLOT_PX: float = 48.0
## 槽间距（px）
const SLOT_GAP: float = 4.0
## 冷却遮罩色（半透明近黑）
const CD_MASK: Color = Color(0.0, 0.0, 0.0, 0.58)
## 键位角标文字色
const KEY_TEXT: Color = Color("DCE2E8")
## 键位角标底（1px 黑边 + 半透明深底）
const KEY_BG: Color = Color(0.0, 0.0, 0.0, 0.65)
## 冷却秒数文字色
const CD_TEXT: Color = Color("DCE2E8")

## 技能控制器（鸭子类型：get_skill_id_at / is_on_cooldown / get_cooldown_remaining / get_skill_data）
var controller: Object = null

var _icon_names: Array[String] = []
var _slot_tex: Texture2D = null


func _ready() -> void:
	_slot_tex = UISkin.texture("skill_slot")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 绑定控制器并重建（须在 _ready 之后调用）
func setup(ctrl: Object) -> void:
	controller = ctrl
	_icon_names.clear()
	for i in SLOT_COUNT:
		var id: String = ctrl.get_skill_id_at(i) if ctrl != null else ""
		_icon_names.append(id)
	custom_minimum_size = Vector2(SLOT_COUNT * SLOT_PX + (SLOT_COUNT - 1) * SLOT_GAP, SLOT_PX)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for i in SLOT_COUNT:
		_draw_slot(i)


func _draw_slot(i: int) -> void:
	var x := float(i) * (SLOT_PX + SLOT_GAP)
	var rect := Rect2(x, 0.0, SLOT_PX, SLOT_PX)
	var id := _icon_names[i] if i < _icon_names.size() else ""
	var tex: Texture2D = null
	if not id.is_empty():
		var icon_name := str(GameConstants.SKILL_ICON.get(id, ""))
		if not icon_name.is_empty():
			tex = UISkin.texture(icon_name)
	if tex == null:
		tex = _slot_tex
	if tex != null:
		draw_texture_rect(tex, rect, false)

	# 冷却遮罩：从槽顶向下按 剩余/总冷却 变暗 + 剩余秒数
	var on_cd := false
	var ratio := 0.0
	if controller != null and not id.is_empty() and controller.is_on_cooldown(id):
		var remaining := float(controller.get_cooldown_remaining(id))
		var total := _cd_total(id)
		ratio = clampf(remaining / total, 0.0, 1.0)
		on_cd = ratio > 0.0
	if on_cd:
		draw_rect(Rect2(x, 0.0, SLOT_PX, SLOT_PX * ratio), CD_MASK)
		var font := get_theme_default_font()
		var secs := "%.1f" % maxf(float(controller.get_cooldown_remaining(id)), 0.0)
		var fs := 11
		var tw := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(x + (SLOT_PX - tw) * 0.5, SLOT_PX * 0.5 + fs * 0.5)
		draw_string(font, pos, secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CD_TEXT)

	# 键位角标（右下角 1/2/3）
	var key := str(i + 1)
	var font2 := get_theme_default_font()
	var fs2 := 11
	var kw := font2.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	var kb := Rect2(x + SLOT_PX - kw - 8.0, SLOT_PX - fs2 - 4.0, kw + 4.0, fs2 + 2.0)
	draw_rect(kb, KEY_BG)
	draw_rect(kb, Color("0B0D10"), false, 1.0)
	draw_string(font2, kb.position + Vector2(2.0, fs2 - 1.0), key,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, KEY_TEXT)


## 验证钩子：出战槽数
func get_slot_count() -> int:
	return SLOT_COUNT


## 验证钩子：槽状态（id / 是否冷却 / 冷却比例）
func get_slot_state(i: int) -> Dictionary:
	if i < 0 or i >= SLOT_COUNT:
		return {}
	var id := _icon_names[i] if i < _icon_names.size() else ""
	var ratio := 0.0
	if controller != null and not id.is_empty() and controller.is_on_cooldown(id):
		var remaining := float(controller.get_cooldown_remaining(id))
		var total := _cd_total(id)
		ratio = clampf(remaining / total, 0.0, 1.0)
	return {"id": id, "on_cd": ratio > 0.0, "cd_ratio": ratio}


## 技能总冷却（SkillData 属性 / Dictionary 双兼容，防运行时类型炸）
func _cd_total(id: String) -> float:
	var sd: Variant = controller.get_skill_data(id) if controller != null else null
	if sd is Dictionary:
		return maxf(float(sd.get("cooldown", 1.0)), 0.001)
	if sd is SkillData:
		return maxf(float(sd.cooldown), 0.001)
	return 1.0
