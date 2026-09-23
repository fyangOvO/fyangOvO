## 局内消耗品快捷栏（步骤 8A · 2026-09-23 · class_name）
##
## 显示 2 个药水槽（Q=生命药水 / R=法力药水）：槽贴图 + 药水图标 + 数量角标 +
## 键位角标 + 冷却遮罩（从槽顶向下按剩余比例变暗 + 剩余秒数）。
## 纯展示（mouse_filter IGNORE）；数据只读 `PlayerController` 的查询接口
## （consumable_count / get_consumable_cd_remaining / get_consumables）。
## 每帧重绘（与 SkillBarUI / HealthBar 同策略）。
class_name QuickSlotUI
extends Control

## 快捷槽数（与 project.godot consume_1/2 + PlayerController 输入一致）
const SLOT_COUNT: int = 2
## 槽边长（px）。与 skill_slot_48 / potion_*_48 原生尺寸一致 ⇒ 1× 整数
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
## 数量角标文字色（亮金）
const COUNT_TEXT: Color = Color("D9A521")
## 数量角标底
const COUNT_BG: Color = Color(0.0, 0.0, 0.0, 0.70)

## 快捷槽 ID 清单（与键位一一对应）
const SLOT_IDS: Array[String] = ["life_potion", "mana_potion"]
## 键位标签（右下角角标）
const SLOT_KEYS: Array[String] = ["Q", "R"]

## 玩家引用（鸭子类型：consumable_count / get_consumable_cd_remaining / get_consumables）
var player: Object = null

var _slot_tex: Texture2D = null
## 每槽图标（Texture2D 或 null）
var _icons: Array = []


func _ready() -> void:
	_slot_tex = UISkin.texture("skill_slot")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_icons()


## 绑定玩家并重建（须在 _ready 之后调用）
func setup(p: Object) -> void:
	player = p
	_refresh_icons()
	custom_minimum_size = Vector2(SLOT_COUNT * SLOT_PX + (SLOT_COUNT - 1) * SLOT_GAP, SLOT_PX)
	queue_redraw()


## 图标表：从 ConfigLoader 消耗品配置读 icon 逻辑名 → UISkin 贴图
func _refresh_icons() -> void:
	_icons.clear()
	for id in SLOT_IDS:
		var cfg: Dictionary = ConfigLoader.consumables.get(id, {})
		var icon_name := str(cfg.get("icon", ""))
		var tex: Texture2D = null
		if not icon_name.is_empty():
			tex = UISkin.texture(icon_name)
		_icons.append(tex if tex != null else _slot_tex)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for i in SLOT_COUNT:
		_draw_slot(i)


func _draw_slot(i: int) -> void:
	var x := float(i) * (SLOT_PX + SLOT_GAP)
	var rect := Rect2(x, 0.0, SLOT_PX, SLOT_PX)
	var tex: Texture2D = _icons[i] if i < _icons.size() else _slot_tex
	if tex != null:
		draw_texture_rect(tex, rect, false)

	var id := SLOT_IDS[i] if i < SLOT_IDS.size() else ""
	var count := 0
	var on_cd := false
	var ratio := 0.0
	var cd_remain := 0.0
	if player != null and not id.is_empty():
		count = int(player.call("consumable_count", id))
		cd_remain = float(player.call("get_consumable_cd_remaining", id))
		if cd_remain > 0.0:
			var total := _cd_total(id)
			ratio = clampf(cd_remain / total, 0.0, 1.0)
			on_cd = ratio > 0.0

	# 冷却遮罩：从槽顶向下按 剩余/总冷却 变暗 + 剩余秒数
	if on_cd:
		draw_rect(Rect2(x, 0.0, SLOT_PX, SLOT_PX * ratio), CD_MASK)
		var font := get_theme_default_font()
		var secs := "%.1f" % maxf(cd_remain, 0.0)
		var fs := 11
		var tw := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(x + (SLOT_PX - tw) * 0.5, SLOT_PX * 0.5 + fs * 0.5)
		draw_string(font, pos, secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CD_TEXT)

	# 数量角标（左下角 ×N；无数量时置灰）
	var font2 := get_theme_default_font()
	var fs2 := 11
	var count_txt := "×%d" % count
	var cw := font2.get_string_size(count_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	var cb := Rect2(x + 2.0, SLOT_PX - fs2 - 4.0, cw + 4.0, fs2 + 2.0)
	draw_rect(cb, COUNT_BG)
	draw_rect(cb, Color("0B0D10"), false, 1.0)
	draw_string(font2, cb.position + Vector2(2.0, fs2 - 1.0), count_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs2,
		COUNT_TEXT if count > 0 else Color(0.55, 0.6, 0.66))

	# 键位角标（右下角 Q/R）
	var key := SLOT_KEYS[i] if i < SLOT_KEYS.size() else str(i)
	var fs3 := 11
	var kw := font2.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x
	var kb := Rect2(x + SLOT_PX - kw - 8.0, SLOT_PX - fs3 - 4.0, kw + 4.0, fs3 + 2.0)
	draw_rect(kb, KEY_BG)
	draw_rect(kb, Color("0B0D10"), false, 1.0)
	draw_string(font2, kb.position + Vector2(2.0, fs3 - 1.0), key,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, KEY_TEXT)


## 验证钩子：快捷槽数
func get_slot_count() -> int:
	return SLOT_COUNT


## 验证钩子：槽状态（id / 数量 / 是否冷却 / 冷却比例）
func get_slot_state(i: int) -> Dictionary:
	if i < 0 or i >= SLOT_COUNT:
		return {}
	var id := SLOT_IDS[i] if i < SLOT_IDS.size() else ""
	var count := 0
	var ratio := 0.0
	var on_cd := false
	if player != null and not id.is_empty():
		count = int(player.call("consumable_count", id))
		var cd_remain := float(player.call("get_consumable_cd_remaining", id))
		if cd_remain > 0.0:
			ratio = clampf(cd_remain / _cd_total(id), 0.0, 1.0)
			on_cd = ratio > 0.0
	return {"id": id, "count": count, "on_cd": on_cd, "cd_ratio": ratio}


## 消耗品总冷却（ConsumableData 配置；缺省 3s）
func _cd_total(id: String) -> float:
	var cfg: Dictionary = ConfigLoader.consumables.get(id, {})
	return maxf(float(cfg.get("cooldown", 3.0)), 0.001)
