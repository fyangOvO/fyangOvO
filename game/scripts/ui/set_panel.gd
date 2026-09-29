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

	# 标题行：徽记图标 + 名称 x/6
	# 徽记走「数据驱动直载」路线（ContentLoader.load_icon，完整 res:// 路径），
	# 不进 UISkin 的 TEX 表——见设计文档 §B.1.4 素材路径契约。
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)

	var emblem := TextureRect.new()
	var emblem_size := GameConstants.SET_EMBLEM_SIZE
	emblem.custom_minimum_size = Vector2(emblem_size, emblem_size)
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.texture = ContentLoader.load_icon(String(entry.get("emblem_path", "")))
	head.add_child(emblem)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[8])
	title.text = "%s  %d/%d" % [entry["display_name"], entry["pieces"], entry["piece_total"]]
	head.add_child(title)
	vb.add_child(head)

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
	# 第四步 B4 3-S4：机制型档位在**同一行**用独立颜色显示机制名（非仅数值）。
	# ⚠️ 不另起一行 —— 3 套 × (2 数值档 + 4 机制行) 会把面板撑出 640×360 视口（预览已实测溢出）。
	var green := Color(0.6, 0.85, 0.65)
	var grey := GameConstants.PALETTE_NEUTRAL[6]
	for tier in tiers:
		var active: bool = tier["active"]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)

		var piece_lbl := Label.new()
		piece_lbl.add_theme_font_size_override("font_size", 10)
		piece_lbl.add_theme_color_override("font_color", green if active else grey)
		piece_lbl.text = "%s件" % tier["pieces"]
		line.add_child(piece_lbl)

		var effect_name := String(tier.get("effect_name", ""))
		if not effect_name.is_empty():
			var mech := Label.new()
			mech.add_theme_font_size_override("font_size", 10)
			mech.add_theme_color_override("font_color",
				Color(0.45, 0.78, 1.0) if active else Color(0.38, 0.42, 0.5))
			mech.text = "【%s】" % effect_name
			line.add_child(mech)

		var desc := Label.new()
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", green if active else grey)
		desc.text = "：%s" % tier["description"]
		line.add_child(desc)
		vb.add_child(line)
	return vb
