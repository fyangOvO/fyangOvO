## 锻造与洗练渲染预览（任务 3.4 · 窗口化自截图验收）
##
## 用法：godot --path "D:/七傳說/game" res://tools/forge_preview.tscn
## 显示 2 张橙装卡（+0 与 +10 对比）+ 1 张红装卡（+12）+ 洗练前后数值行。
extends Node2D

const PREVIEW_SHOT := "res://build/forge_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var label := Label.new()
	label.text = "锻造 / 洗练预览（3.4）"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	label.position = Vector2(16, 8)
	add_child(label)

	# 橙装 +0 与 +10 对比
	var orange0 := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("sword_iron"), 20, GameConstants.Rarity.LEGENDARY)
	var orange10 := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("sword_iron"), 20, GameConstants.Rarity.LEGENDARY)
	orange10.forge_level = 10
	add_child(_build_card(orange0, "+0 基础属性", Vector2(24, 40), false))
	add_child(_build_card(orange10, "+10 强化", Vector2(240, 40), true))

	# 红装 +12
	var mythic := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("sword_iron"), 30, GameConstants.Rarity.MYTHIC)
	mythic.forge_level = 12
	add_child(_build_card(mythic, "神话 +12", Vector2(456, 40), true))


func _build_card(item: EquipmentInstance, title: String, pos: Vector2, show_forge: bool) -> Control:
	var rar_color := item.get_rarity_color()
	var box := Panel.new()
	box.position = pos
	box.size = Vector2(190, 300)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(rar_color, 0.14)
	sb.border_color = rar_color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	box.add_theme_stylebox_override("panel", sb)
	var root := Control.new()
	root.position = pos
	root.size = box.size

	var name_label := Label.new()
	name_label.text = "%s %s" % [item.get_display_name(), title]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", rar_color)
	name_label.position = Vector2(10, 8)
	root.add_child(name_label)

	var mult := item.get_forge_multiplier()
	var ilvl_label := Label.new()
	ilvl_label.text = "iLvl %d · 强化 +%d（倍率 ×%.2f）" % [item.item_level, item.forge_level, mult]
	ilvl_label.add_theme_font_size_override("font_size", 11)
	ilvl_label.add_theme_color_override("font_color", Color(0.72, 0.75, 0.78))
	ilvl_label.position = Vector2(10, 26)
	root.add_child(ilvl_label)

	var stats := item.get_base_stats()
	var y := 48
	var stat_keys := ["flat_attack", "flat_armor", "flat_hp"]
	for key in stat_keys:
		if not stats.has(key):
			continue
		var row := Label.new()
		var label_key: String = {"flat_attack": "攻击力", "flat_armor": "护甲", "flat_hp": "生命值"}[key]
		row.text = "+%s %s" % [String.num(float(stats[key]), 1), label_key]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", Color(0.86, 0.9, 0.94) if show_forge else Color(0.66, 0.7, 0.74))
		row.position = Vector2(10, y)
		root.add_child(row)
		y += 16

	# 前两条词缀
	var affix_y := y + 4
	var affix_count := 0
	for roll in item.affixes:
		if affix_count >= 3:
			break
		var row := Label.new()
		row.text = roll.to_text()
		row.add_theme_font_size_override("font_size", 10)
		row.add_theme_color_override("font_color", roll.quality_color())
		row.position = Vector2(10, affix_y)
		root.add_child(row)
		affix_y += 14
		affix_count += 1
	root.add_child(box)
	return root


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 8 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
