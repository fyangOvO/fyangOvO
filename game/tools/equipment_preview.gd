## 词缀生成器渲染预览（任务 3.2 · 窗口化自截图验收）
##
## 用法：godot --path "D:/七傳說/game" res://tools/equipment_preview.tscn
## 显示 3 件装备卡（蓝 / 橙 / 红）：稀有度色边框 + 名称 + 词缀行（按品质档染色）。
extends Node2D

const PREVIEW_SHOT := "res://build/equipment_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var theme: Theme = load("res://assets/ui/theme.tres")
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var label := Label.new()
	label.text = "词缀生成器预览（3.2）"
	label.theme = theme
	label.position = Vector2(16, 8)
	add_child(label)

	# 三件示例装备：蓝 / 橙 / 红
	var cards := [
		_build_card("sword_iron", 12, GameConstants.Rarity.MAGIC, Vector2(24, 40)),
		_build_card("sword_iron", 22, GameConstants.Rarity.LEGENDARY, Vector2(230, 40)),
		_build_card("sword_iron", 30, GameConstants.Rarity.MYTHIC, Vector2(436, 40)),
	]
	for card in cards:
		add_child(card)


## 一张装备卡：稀有度色底 + 边框 + 名称 + 词缀行
func _build_card(tid: String, ilvl: int, rarity: int, pos: Vector2) -> Control:
	var tpl := ConfigLoader.get_equipment_template(tid)
	var item := AffixRoller.roll_full_equipment(tpl, ilvl, rarity)
	var rar_color := GameConstants.rarity_color(rarity)
	var box := Panel.new()
	box.position = pos
	box.size = Vector2(190, 290)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(rar_color, 0.16)
	sb.border_color = rar_color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0) # 像素风铁律：圆角 0
	box.add_theme_stylebox_override("panel", sb)
	var root := Control.new()
	root.position = pos
	root.size = box.size

	var name_label := Label.new()
	name_label.text = "%s %s" % [item.get_display_name(), GameConstants.rarity_name(rarity)]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", rar_color)
	name_label.position = Vector2(10, 8)
	root.add_child(name_label)

	var ilvl_label := Label.new()
	ilvl_label.text = "iLvl %d · 需求 Lv.%d" % [item.item_level, item.required_level]
	ilvl_label.add_theme_font_size_override("font_size", 11)
	ilvl_label.add_theme_color_override("font_color", Color(0.72, 0.75, 0.78))
	ilvl_label.position = Vector2(10, 26)
	root.add_child(ilvl_label)

	var y := 48
	for roll in item.affixes:
		var row := Label.new()
		var suffix := "◆" if roll.is_empowered else ""
		row.text = "%s%s" % [roll.to_text(), suffix]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", roll.quality_color())
		row.position = Vector2(10, y)
		root.add_child(row)
		y += 16

	var affix_total := Label.new()
	affix_total.text = "— %d 条词缀 —" % item.affixes.size()
	affix_total.add_theme_font_size_override("font_size", 10)
	affix_total.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
	affix_total.position = Vector2(10, y + 6)
	root.add_child(affix_total)

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
