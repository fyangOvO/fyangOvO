## 局內臨時增益 HUD（第四步 B4 · 3-B4 · class_name）
##
## 在技能欄 / 召喚欄**上方**顯示**激活中的增益小圖標 + 剩餘時間**。
## 設計硬要求（`03-装备特色玩法.md` §2.7A「可视化」）：
##   「HUD 必须显示 buff 图标 + 剩余时间，否则玩家不知在增益中」
##
## 數據源：玩家 `BuffComponent.get_active()`（鴨子型別，不直接持有組件引用）。
## 每幀重繪（槽數極少，與 `SummonBarUI` / `HealthBar` 同策略）。
##
## ⚠️ **素材已就位（2026-10-16）**：`status_*_24.png` 14 張（原 12 + 補產
##    wind_walk / mana_surge）已註冊 TEX、`BUFF_ICONS` 7 條全覆蓋；
##    未知來源才走佔位繪製（縮寫色塊 + 剩餘秒 + 疊層），為純兜底。
class_name BuffBarUI
extends Control

## 同時顯示的增益上限（超出不畫，不報錯）
const MAX_SLOTS: int = 6
## 圖標邊長（px）：與召喚欄同尺寸（24），留得下「縮寫 + 剩餘秒 + 疊層」三層信息
const ICON_PX: float = 24.0
## 槽間距（px）
const GAP: float = 3.0

## 正增益底色（藍）
const POS_COLOR: Color = Color("3A6FD8")
## 負增益 / 減益底色（紅）
const NEG_COLOR: Color = Color("C42B2B")
## 文字色
const TEXT_COLOR: Color = Color("F2F5F8")
## 屬性縮寫字號
const LABEL_SIZE: int = 10
## 剩餘秒數字號
const SECS_SIZE: int = 8
## 底部「疊層數 + 剩餘秒」暗條高度（px）
const SECS_BAR_H: float = 9.0

## 屬性鍵 → 2 字縮寫（佔位標籤）。缺省取鍵前 2 字。
const KEY_LABELS: Dictionary = {
	"pct_armor": "护甲",
	"all_damage": "通用",
	"move_speed": "移速",
	"attack_speed": "攻速",
	"dodge": "闪避",
	"all_attributes": "全属",
	"gold_gain": "金币",
	"damage_reduction": "减伤",
	"pct_attack": "攻击",
	"life_steal": "吸血",
	"crit_chance": "暴击",
	"elemental_damage": "元素",
}

## ── 2026-10-16：真素材接通 ────────────────────────────────
## 增益來源 `source_id`（技能 `buff_id`）→ `UISkin` 狀態圖標鍵（24×24，
## `status_*_24.png` 已備、已註冊 TEX）。`BUFF_DEFS` 7 條全覆蓋（含 2026-10-16
## 補產的 wind_walk / mana_surge）；`regen` 通用來源備用。
const BUFF_ICONS: Dictionary = {
	"buff_warcry": "status_warcry",
	"buff_blood_rage": "status_blood_rage",
	"buff_iron_bulwark": "status_iron_bulwark",
	"buff_hawk_eye": "status_hawk_eye",
	"buff_arcane_shield": "status_shield",
	"buff_wind_walk": "status_wind_walk",
	"buff_mana_surge": "status_mana_surge",
	"regen": "status_regen",
}

## 数据源（玩家节点；由 `LevelScene` 注入）
var source: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
		MAX_SLOTS * ICON_PX + (MAX_SLOTS - 1) * GAP, ICON_PX)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var entries := active_buffs()
	for i in MAX_SLOTS:
		if i >= entries.size():
			break
		var rect := Rect2(float(i) * (ICON_PX + GAP), 0.0, ICON_PX, ICON_PX)
		_draw_one(entries[i], rect, font)


func _draw_one(entry: Dictionary, rect: Rect2, font: Font) -> void:
	var key := String(entry.get("key", ""))
	var value := float(entry.get("value", 0.0))
	var stacks := int(entry.get("stacks", 1))
	var remain := float(entry.get("remain", 0.0))
	var total := maxf(float(entry.get("duration", 1.0)), 0.001)
	var bar_w := 2.0
	var ratio := clampf(remain / total, 0.0, 1.0)

	# ① 真素材优先：来源 id 命中 `status_*` 图标 ⇒ 整格铺图标（24×24 原尺寸）
	var icon: Texture2D = null
	var icon_key := String(BUFF_ICONS.get(String(entry.get("source_id", "")), ""))
	if icon_key != "":
		icon = UISkin.texture(icon_key)
	if icon != null:
		draw_texture_rect(icon, rect, false)
	else:
		# 占位分支：正增益蓝 / 负增益红 + 属性缩写（素材未覆盖的来源）
		var base := POS_COLOR if value >= 0.0 else NEG_COLOR
		draw_rect(rect, base, true)
		if font != null:
			var label := String(KEY_LABELS.get(key, key.substr(0, mini(key.length(), 2))))
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
			var pos := Vector2(
				rect.position.x + bar_w + (rect.size.x - bar_w - w) * 0.5,
				rect.position.y + rect.size.y - SECS_BAR_H - 2.0)
			draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, TEXT_COLOR)

	# ② 剩余时间：左侧竖条按剩余比例收缩（不遮字，一眼读出「还剩多久」）
	draw_rect(Rect2(rect.position, Vector2(bar_w, rect.size.y)), Color(0.0, 0.0, 0.0, 0.45), true)
	draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * (1.0 - ratio),
		bar_w, rect.size.y * ratio), Color("7FE3A1"), true)

	# ③ 底部暗条：左 = 叠层数（仅 N > 1），右 = 剩余秒
	if font != null:
		var strip := Rect2(rect.position.x, rect.position.y + rect.size.y - SECS_BAR_H,
			rect.size.x, SECS_BAR_H)
		draw_rect(strip, Color(0.0, 0.0, 0.0, 0.5), true)
		var baseline := strip.position.y + SECS_BAR_H - 1.0
		if stacks > 1:
			draw_string(font, Vector2(strip.position.x + bar_w + 1.0, baseline),
				"x%d" % stacks, HORIZONTAL_ALIGNMENT_LEFT, -1, SECS_SIZE, Color("FFD86B"))
		var secs := "%d" % int(ceil(remain))
		var sw := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, SECS_SIZE).x
		draw_string(font, Vector2(strip.position.x + strip.size.x - sw - 1.0, baseline),
			secs, HORIZONTAL_ALIGNMENT_LEFT, -1, SECS_SIZE, TEXT_COLOR)

	# ④ 1px 暗描边（最后画，压住溢出像素）
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.6), false, 1.0)


## 激活中的增益（鸭子型別：`source.get_buff_component().get_active()`）。
## 缺组件 / 空列表 ⇒ 返回空数组（不報錯、不畫）。
func active_buffs() -> Array:
	if source == null or not is_instance_valid(source) \
			or not source.has_method("get_buff_component"):
		return []
	var bc = source.call("get_buff_component")
	if bc == null or not bc.has_method("get_active"):
		return []
	return bc.call("get_active")


## 驗證鉤子：顯示槽位上限
func get_slot_count() -> int:
	return MAX_SLOTS
