## 局內異常狀態 HUD（2026-10-15 · §6.2 異常 HUD 接通）
##
## 在**血條正下方**顯示玩家身上的異常狀態小圖標 + 剩餘時間。
## 設計硬要求：玩家被怪上異常（中毒/燃燒/冰凍/感電/詛咒）必須**可見**，
## 否則「為什麼血一直掉 / 為什麼動不了」對玩家不可知。
##
## 數據源：`EventBus.ailment_status_changed(host, ailment, applied)`，
## 過濾 `host == source`（玩家節點）——與 `enemy_base._on_ailment_status_changed`
## （怪物染色）是**同一信號的兩個並行消費點**，不互相影響。
##
## 圖標：`UISkin.ailment_icon()` 真素材（24×24，`ailment_<key>_24.png`）。
## ⚠️ 命名漂移（README §9.2 已記錄）：邏輯鍵 `slow`（`AILMENT_SLOW`）vs 素材鍵
##    `chill`（`ailment_chill_24.png`）⇒ 本組件在 UI 層做 `slow → chill` 映射，
##    不改核心邏輯鍵（`GameConstants.AILMENT_SLOW` 被 health/damage 大量引用）。
##
## 每幀重繪（槽數極少，與 `BuffBarUI` / `SummonBarUI` 同策略）；剩餘秒走
## 底部暗條縮放（同 BuffBar 風格），不逐幀改 `text`。
class_name AilmentBarUI
extends Control

## 同時顯示的異常上限（5 種異常全顯示）
const MAX_SLOTS: int = 5
## 圖標邊長（px）：與 `ailment_*_24` 素材一致，**不縮放**（像素鐵律）
const ICON_PX: float = 24.0
## 槽間距（px）
const GAP: float = 3.0
## 剩餘秒暗條高度（px）
const SECS_BAR_H: float = 8.0
## 剩餘秒數字號
const SECS_SIZE: int = 8
## 文字色
const TEXT_COLOR: Color = Color("F2F5F8")
## 剩餘條顏色（綠，剩餘比例收縮）
const SECS_COLOR: Color = Color("7FE3A1")

## 顯示順序（固定，防施加順序造成圖標跳動）
const DISPLAY_ORDER: Array[String] = [
	GameConstants.AILMENT_POISON,
	GameConstants.AILMENT_BURN,
	GameConstants.AILMENT_SLOW,
	GameConstants.AILMENT_SHOCK,
	GameConstants.AILMENT_CURSE,
]

## 邏輯鍵 → 素材鍵映射（僅處理漂移；其餘同鍵）
const ICON_KEY_MAP: Dictionary = {
	GameConstants.AILMENT_SLOW: "chill",
}

## 玩家節點（由 `LevelScene` 注入；僅顯示 `host == source` 的異常）
var source: Node = null

## 激活中的異常：{ 異常鍵: { "time": 剩餘秒, "total": 初始時長 } }
var _active: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
		MAX_SLOTS * ICON_PX + (MAX_SLOTS - 1) * GAP, ICON_PX)
	EventBus.ailment_status_changed.connect(_on_ailment_status_changed)


func _process(delta: float) -> void:
	# 兜底：健康組件正常會發 false 移除；這裡防「漏發」導致的死圖標（與 BuffBar 同策略）
	if _active.is_empty():
		return
	var changed := false
	for ailment in _active.keys():
		_active[ailment]["time"] = float(_active[ailment]["time"]) - delta
		if float(_active[ailment]["time"]) <= 0.0:
			_active.erase(ailment)
			changed = true
	if changed:
		queue_redraw()
	else:
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var slot := 0
	for ailment in DISPLAY_ORDER:
		if not _active.has(ailment):
			continue
		var rect := Rect2(float(slot) * (ICON_PX + GAP), 0.0, ICON_PX, ICON_PX)
		_draw_one(ailment, rect, font)
		slot += 1


func _draw_one(ailment: String, rect: Rect2, font: Font) -> void:
	var entry: Dictionary = _active[ailment]
	var remain := clampf(float(entry["time"]), 0.0, float(entry["total"]))
	var total := maxf(float(entry["total"]), 0.001)

	# ① 圖標（24×24 原尺寸；缺檔回 null 時畫暗底佔位）
	var tex := UISkin.ailment_icon(icon_key(ailment))
	if tex != null:
		draw_texture_rect(tex, rect, false)
	else:
		draw_rect(rect, Color(0.1, 0.1, 0.12, 0.8), true)

	# ② 剩餘時間：底部暗條 + 綠色比例條（左側，不遮圖標主體）
	var strip := Rect2(rect.position.x, rect.position.y + rect.size.y - SECS_BAR_H,
		rect.size.x, SECS_BAR_H)
	draw_rect(strip, Color(0.0, 0.0, 0.0, 0.55), true)
	var ratio := remain / total
	draw_rect(Rect2(strip.position.x, strip.position.y,
		strip.size.x * ratio, SECS_BAR_H), SECS_COLOR, true)

	# ③ 剩餘秒數（暗條上，右對齊；10 秒內顯示）
	if font != null and remain < 9.95:
		var secs := "%d" % int(ceil(remain))
		var sw := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, SECS_SIZE).x
		draw_string(font,
			Vector2(strip.position.x + strip.size.x - sw - 1.0, strip.position.y + SECS_BAR_H - 1.0),
			secs, HORIZONTAL_ALIGNMENT_LEFT, -1, SECS_SIZE, TEXT_COLOR)

	# ④ 1px 暗描邊（最後畫，壓住溢出像素）
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.6), false, 1.0)


## 邏輯鍵 → 素材鍵（slow → chill；其餘原樣）
static func icon_key(ailment: String) -> String:
	return String(ICON_KEY_MAP.get(ailment, ailment))


## 信號回調：只處理發生在玩家身上的異常
func _on_ailment_status_changed(who: Node, ailment: String, applied: bool) -> void:
	if who != source or not is_instance_valid(source):
		return
	if applied:
		_active[ailment] = { "time": GameConstants.ailment_duration(ailment),
			"total": GameConstants.ailment_duration(ailment) }
	else:
		_active.erase(ailment)
	queue_redraw()


## 驗證鉤子：當前激活異常（[{ailment, time, total, icon_key}]，按顯示順序）
func get_active_ailments() -> Array:
	var out: Array = []
	for ailment in DISPLAY_ORDER:
		if _active.has(ailment):
			var e: Dictionary = _active[ailment]
			out.append({ "ailment": ailment, "time": float(e["time"]),
				"total": float(e["total"]), "icon_key": icon_key(ailment) })
	return out
