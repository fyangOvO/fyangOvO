## 拾取提示流（步骤 6 · 2026-09-22 · class_name）
##
## 局内掉落拾取的视觉反馈：右上角逐条弹出「金币 +N / 魔石 +N / 已拾取：装备名（稀有度色）」，
## 每条 2.2s 淡出；最多保留 MAX_TOASTS 条（超出移除最旧）。
## 消费 `EventBus.loot_picked_up(entry: Dictionary)`（LootDrop 拾取时广播）。
class_name PickupToastHUD
extends VBoxContainer

## 单条存活时长（秒）
const LIFE: float = 2.2
## 淡出时长（秒）
const FADE: float = 0.35
## 最多同时显示条数
const MAX_TOASTS: int = 5

const FONT_SIZE: int = 12
const GOLD_COLOR: Color = Color("D9A521")
const MATERIAL_COLOR: Color = Color("4C8BF5")


## 按 LootDrop 拾取载荷组成提示条。
## 载荷：{type: gold|material|equipment, amount, item_id, rarity, item_level, instance?}
func spawn(entry: Dictionary) -> void:
	var text := ""
	var color := GameConstants.UI_TEXT_BRIGHT
	var t := str(entry.get("type", ""))
	match t:
		"gold":
			text = "金币 +%d" % int(entry.get("amount", 1))
			color = GOLD_COLOR
		"material":
			text = "魔石 +%d" % int(entry.get("amount", 1))
			color = MATERIAL_COLOR
		"equipment":
			var item_id := str(entry.get("item_id", ""))
			var tpl: EquipmentData = ConfigLoader.get_equipment_template(item_id)
			var nm := tpl.display_name if tpl != null else item_id
			text = "已拾取：%s" % nm
			var r := int(entry.get("rarity", GameConstants.Rarity.COMMON))
			color = GameConstants.rarity_color(r)
		_:
			return
	_push(text, color)


func _push(text: String, color: Color) -> void:
	# 上限：移除最旧一条
	while get_child_count() >= MAX_TOASTS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()

	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.051, 0.063, 0.82)
	sb.set_border_width_all(1)
	sb.border_color = Color("3A424F")
	sb.set_corner_radius_all(0)
	row.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 6)
	mg.add_theme_constant_override("margin_right", 6)
	mg.add_theme_constant_override("margin_top", 2)
	mg.add_theme_constant_override("margin_bottom", 2)
	mg.add_child(lbl)
	row.add_child(mg)
	add_child(row)

	# 2.2s 后淡出并移除
	var tw := create_tween()
	tw.tween_interval(LIFE)
	tw.tween_property(row, "modulate:a", 0.0, FADE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(row):
			row.queue_free())
