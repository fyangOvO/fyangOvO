## 套装进度面板 UI（任务 3.10）
##
## 每套显示：名称 + 已穿 x/6 + 6 段进度条（GDD 0.3 节 3.7）+ 2/4/6 档文案
## （激活档高亮，未激活灰）。只读展示 SetSystem.get_progress 结果。
class_name SetPanel
extends PanelContainer

var _box: VBoxContainer = null


func _ready() -> void:
	_build_ui()


func show_sets(equipped: Array[EquipmentInstance]) -> void:
	if _box == null:
		_build_ui()
	for c in _box.get_children():
		c.queue_free()
	var progress := SetSystem.get_progress(equipped)
	if progress.is_empty():
		var empty := Label.new()
		empty.text = "（未穿戴任何套装）"
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
		_box.add_child(empty)
		return
	for entry in progress:
		_box.add_child(_make_set_row(entry))


func _build_ui() -> void:
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)


func _make_set_row(entry: Dictionary) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)

	# 标题：名称 x/6
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[8])
	title.text = "%s  %d/%d" % [entry["display_name"], entry["pieces"], entry["piece_total"]]
	vb.add_child(title)

	# 6 段进度条（激活段亮色，未激活深色）
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3)
	var tiers: Array = entry["tiers"]
	for i in range(int(entry["piece_total"])):
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(18, 6)
		seg.color = Color(0.85, 0.7, 0.4) if i < int(entry["pieces"]) else Color(0.16, 0.18, 0.22)
		bar.add_child(seg)
	vb.add_child(bar)

	# 档位文案（激活高亮）
	for tier in tiers:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 10)
		var active: bool = tier["active"]
		row.add_theme_color_override("font_color",
			Color(0.6, 0.85, 0.65) if active else GameConstants.PALETTE_NEUTRAL[6])
		row.text = "%s件%s：%s" % ["✓ " if active else "○ ", tier["pieces"], tier["description"]]
		vb.add_child(row)
	return vb
