## 局內召喚物 HUD（規格 §12.4#6 · class_name）
##
## 在 3 技能欄旁顯示**召喚物小圖標 + 剩餘時間倒數環**。
## 純展示（mouse_filter IGNORE）；數據源為 `summons` 組節點的查詢接口
## （`get_summon_icon` / `get_remaining_lifetime` / `get_total_lifetime`，鴨子型別）。
## 每幀重繪（槽數極少，與 HealthBar / SkillBarUI 同策略）。
##
## ⚠️ 640×360 空間已滿：本元件刻意**小巧**（24px 圖標），掛在技能欄**上方**，
##    不與技能欄（48px）/ 消耗品欄重疊。
class_name SummonBarUI
extends Control

## 同時顯示的召喚物上限（當前兩隻召喚技能 ⇒ 2 足夠；超出不畫，不報錯）
const MAX_SLOTS: int = 2
## 圖標邊長（px）：技能欄 48 的一半，讀作「附屬小圖標」
const ICON_PX: float = 24.0
## 槽間距（px）
const GAP: float = 4.0

## 倒數環底色（半透明近黑）
const RING_BG: Color = Color(0.0, 0.0, 0.0, 0.55)
## 倒數環前景色（沿用金強調色）
const RING_COLOR: Color = GameConstants.COLOR_ACCENT_GOLD
## 剩餘秒數字色
const TEXT_COLOR: Color = Color("DCE2E8")
## 剩餘秒數字號
const TEXT_SIZE: int = 9


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
		MAX_SLOTS * ICON_PX + (MAX_SLOTS - 1) * GAP, ICON_PX)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var summons := live_summons()
	var font := get_theme_default_font()
	for i in MAX_SLOTS:
		var rect := Rect2(float(i) * (ICON_PX + GAP), 0.0, ICON_PX, ICON_PX)
		if i >= summons.size():
			continue
		_draw_one(summons[i], rect, font)


func _draw_one(node: Node, rect: Rect2, font: Font) -> void:
	var icon := "skill_slot"
	if node.has_method("get_summon_icon"):
		var k := str(node.call("get_summon_icon"))
		if not k.is_empty():
			icon = k
	var tex := UISkin.texture(icon)
	if tex == null:
		tex = UISkin.texture("skill_slot")
	if tex != null:
		draw_texture_rect(tex, rect, false)

	# 倒數環：剩餘 / 總時長（缺口隨剩餘縮短）
	var total := 1.0
	var remain := 0.0
	if node.has_method("get_remaining_lifetime"):
		remain = float(node.call("get_remaining_lifetime"))
	if node.has_method("get_total_lifetime"):
		total = maxf(float(node.call("get_total_lifetime")), 0.001)
	var ratio := clampf(remain / total, 0.0, 1.0)
	var center := rect.position + rect.size * 0.5
	var r := ICON_PX * 0.5 - 1.5
	draw_arc(center, r, 0.0, TAU, 24, RING_BG, 2.0, true)
	if ratio > 0.0:
		draw_arc(center, r, -PI * 0.5, -PI * 0.5 + TAU * ratio, 24, RING_COLOR, 2.0, true)

	# 剩餘秒數（底部中央，帶 1px 黑底提升可讀性）
	if font != null:
		var secs := "%d" % int(ceil(remain))
		var w := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
		var pos := Vector2(center.x - w * 0.5, rect.position.y + ICON_PX - 1.0)
		draw_string(font, pos + Vector2(0.0, 1.0), secs,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Color(0.0, 0.0, 0.0, 0.75))
		draw_string(font, pos, secs, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, TEXT_COLOR)


## 場上有效的召喚物（`summons` 組），最多 `MAX_SLOTS` 個。
func live_summons() -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group(&"summons"):
		if n == null or not is_instance_valid(n):
			continue
		if not n.has_method("get_remaining_lifetime"):
			continue
		out.append(n)
		if out.size() >= MAX_SLOTS:
			break
	return out


## 驗證鉤子：顯示槽位上限
func get_slot_count() -> int:
	return MAX_SLOTS
