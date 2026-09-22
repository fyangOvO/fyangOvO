## 装备对比渲染预览（任务 3.7 · 窗口化自截图验收）
## 用法：godot --path "D:/七傳說/game" res://tools/compare_preview.tscn
extends Node2D

const PREVIEW_SHOT := "res://build/compare_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var label := Label.new()
	label.text = "装备对比预览（3.7）"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	label.position = Vector2(16, 8)
	add_child(label)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916

	# 旧件：铁剑 橙 +6 iLvl 20（词缀：攻击力 / 生命值 / 暴击率）
	var old_item := EquipmentInstance.new()
	old_item.instance_id = "old_sword"
	old_item.template_id = "sword_iron"
	old_item.slot = GameConstants.EquipSlot.MAIN_HAND
	old_item.item_level = 20
	old_item.rarity = GameConstants.Rarity.LEGENDARY
	old_item.forge_level = 6
	var old_aff: Array[String] = ["add_flat_attack", "add_flat_hp", "add_crit_chance"]
	for aid in old_aff:
		var aff: AffixData = ConfigLoader.affixes.get(aid)
		var roll := AffixRoll.new()
		roll.affix_id = aid
		roll.template = aff
		roll.value = aff.roll_base_value(rng) * GameConstants.affix_ilvl_scale(20)
		roll.quality = 1
		old_item.affixes.append(roll)

	# 新件：烬誓·燃魄刃 橙 +8 iLvl 35（词缀：攻击力 / 暴击率 / 攻击速度 + 传奇特效）
	var new_item := EquipmentInstance.new()
	new_item.instance_id = "new_sword"
	new_item.template_id = "sword_ash_vow"
	new_item.slot = GameConstants.EquipSlot.MAIN_HAND
	new_item.item_level = 35
	new_item.rarity = GameConstants.Rarity.LEGENDARY
	new_item.forge_level = 8
	new_item.legendary_effect_id = "jin_shi_ran_po_ren"
	var new_aff: Array[String] = ["add_flat_attack", "add_crit_chance", "add_attack_speed"]
	for aid in new_aff:
		var aff: AffixData = ConfigLoader.affixes.get(aid)
		var roll := AffixRoll.new()
		roll.affix_id = aid
		roll.template = aff
		roll.value = aff.roll_base_value(rng) * GameConstants.affix_ilvl_scale(35)
		roll.quality = 1
		new_item.affixes.append(roll)

	# 标题行
	var old_label := Label.new()
	old_label.text = "旧：铁剑 橙 +6（iLvl 20）"
	old_label.add_theme_font_size_override("font_size", 11)
	old_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.8))
	old_label.position = Vector2(16, 36)
	add_child(old_label)

	var new_label := Label.new()
	new_label.text = "新：烬誓·燃魄刃 橙 +8（iLvl 35）"
	new_label.add_theme_font_size_override("font_size", 11)
	new_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.8))
	new_label.position = Vector2(16, 54)
	add_child(new_label)

	var panel := ComparePanel.new()
	add_child(panel)
	panel.show_compare(new_item, old_item, "主手")
	panel.position = Vector2(16, 76)

	# 特殊词缀展示（回响之刃）
	var fx_text := EquipmentCompare.get_special_text(new_item)
	if fx_text.is_empty():
		fx_text = "（无特殊机制词缀）"
	var special := Label.new()
	special.text = "特殊机制：%s" % fx_text
	special.add_theme_font_size_override("font_size", 11)
	special.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	special.position = Vector2(16, 380)
	add_child(special)

	# 传奇特效
	var fx: Dictionary = ConfigLoader.legendary_effects.get(new_item.legendary_effect_id, {})
	var fx_row := Label.new()
	fx_row.text = "传奇特效：%s —— %s" % [fx.get("name", ""), fx.get("description", "")]
	fx_row.add_theme_font_size_override("font_size", 11)
	fx_row.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	fx_row.position = Vector2(16, 402)
	add_child(fx_row)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
