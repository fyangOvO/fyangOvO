## 传奇特效渲染预览（任务 3.5 · 窗口化自截图验收）
##
## 用法：godot --path "D:/七傳說/game" res://tools/legendary_preview.tscn
## 显示 6 件代表性特效卡（GDD 3.5 五件 + 神话示例）+ 一件橙装装配展示。
extends Node2D

const PREVIEW_SHOT := "res://build/legendary_preview.png"

var _shot_taken := false
var _frames := 0

const FEATURE_IDS := [
	"jin_shi_ran_po_ren",
	"qi_chong_hui_xiang_zhi_guan",
	"lie_jie_zhi_huan",
	"bu_xiu_zhe_de_can_qu",
	"shi_yi_zhe_zhi_xue",
	"zhong_mo_hui_xiang",
]


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var label := Label.new()
	label.text = "传奇特效预览（3.5）"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	label.position = Vector2(16, 8)
	add_child(label)

	var x := 16
	for fx_id in FEATURE_IDS:
		add_child(_build_card(ConfigLoader.legendary_effects[fx_id], Vector2(x, 36)))
		x += 228

	# 底部：一件橙装的装配展示（词缀 + 传奇特效 + 强化）
	var sword := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("sword_iron"), 20, GameConstants.Rarity.LEGENDARY)
	sword.forge_level = 6
	add_child(_build_item_card(sword, Vector2(16, 340)))


func _build_card(fx: Dictionary, pos: Vector2) -> Control:
	var box := Panel.new()
	box.position = pos
	box.size = Vector2(212, 290)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.12)
	sb.border_color = Color(0.78, 0.55, 0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	box.add_theme_stylebox_override("panel", sb)

	var root := Control.new()
	root.position = pos
	root.size = box.size
	root.add_child(box) # 背景框先加，label 在其上层

	var name_label := Label.new()
	name_label.text = str(fx.get("name", ""))
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.72, 0.3))
	name_label.position = Vector2(8, 8)
	root.add_child(name_label)

	var slot_label := Label.new()
	var slot_key := str(fx.get("slot", ""))
	slot_label.text = "部位：%s" % GameConstants.EQUIP_SLOT_NAMES[GameConstants.EQUIP_SLOT_KEYS.find(slot_key)] if GameConstants.EQUIP_SLOT_KEYS.has(slot_key) else "部位：?"
	slot_label.add_theme_font_size_override("font_size", 10)
	slot_label.add_theme_color_override("font_color", Color(0.6, 0.64, 0.68))
	slot_label.position = Vector2(8, 26)
	root.add_child(slot_label)

	var trigger: Dictionary = fx.get("trigger", {})
	var trig_label := Label.new()
	trig_label.text = "触发：%s" % _trigger_cn(String(trigger.get("type", "")))
	trig_label.add_theme_font_size_override("font_size", 10)
	trig_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	trig_label.position = Vector2(8, 44)
	root.add_child(trig_label)

	var cd := float(fx.get("cooldown", 0.0))
	var cd_label := Label.new()
	cd_label.text = "冷却：%s" % ("%.1f 秒" % cd if cd > 0.0 else "无")
	cd_label.add_theme_font_size_override("font_size", 10)
	cd_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	cd_label.position = Vector2(8, 60)
	root.add_child(cd_label)

	var desc_label := Label.new()
	desc_label.text = str(fx.get("description", ""))
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size = Vector2(196, 120)
	desc_label.position = Vector2(8, 84)
	root.add_child(desc_label)

	var sep := ColorRect.new()
	sep.color = Color(0.78, 0.55, 0.2, 0.4)
	sep.position = Vector2(8, 250)
	sep.size = Vector2(196, 1)
	root.add_child(sep)
	var num_label := Label.new()
	var rmin_int := int(fx.get("rarity_min", 5))
	var rmin_key := GameConstants.RARITY_KEYS[clampi(rmin_int, 0, GameConstants.RARITY_KEYS.size() - 1)]
	num_label.text = "rarity ≥ %s" % rmin_key
	num_label.add_theme_font_size_override("font_size", 10)
	num_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.7))
	num_label.position = Vector2(8, 258)
	root.add_child(num_label)

	return root


func _build_item_card(item: EquipmentInstance, pos: Vector2) -> Control:
	var box := Panel.new()
	box.position = pos
	box.size = Vector2(880, 130)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.12)
	sb.border_color = item.get_rarity_color()
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	box.add_theme_stylebox_override("panel", sb)

	var root := Control.new()
	root.position = pos
	root.size = box.size
	root.add_child(box) # 背景框先加，label 在其上层

	var name_label := Label.new()
	name_label.text = "%s +%d（装配展示）" % [item.get_display_name(), item.forge_level]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", item.get_rarity_color())
	name_label.position = Vector2(12, 10)
	root.add_child(name_label)

	var fx: Dictionary = ConfigLoader.legendary_effects.get(item.legendary_effect_id, {})
	var fx_label := Label.new()
	fx_label.text = "⚔ 传奇特效：%s —— %s" % [fx.get("name", "无"), fx.get("description", "")]
	fx_label.add_theme_font_size_override("font_size", 11)
	fx_label.add_theme_color_override("font_color", Color(0.92, 0.72, 0.3))
	fx_label.position = Vector2(12, 36)
	fx_label.size = Vector2(856, 40)
	root.add_child(fx_label)

	var affix_y := 84
	for roll in item.affixes:
		if affix_y > 110:
			break
		var row := Label.new()
		row.text = roll.to_text()
		row.add_theme_font_size_override("font_size", 10)
		row.add_theme_color_override("font_color", roll.quality_color())
		row.position = Vector2(12, affix_y)
		root.add_child(row)
		affix_y += 14

	return root


func _trigger_cn(t: String) -> String:
	match t:
		"on_hit": return "攻击命中"
		"on_crit": return "暴击"
		"on_kill": return "击杀"
		"on_elite_kill": return "击杀精英"
		"on_damage_taken": return "受到攻击"
		"on_low_hp": return "低生命"
		"on_pickup_gold": return "拾取金币"
		"on_skill_cast": return "施放技能"
		"on_resource_spend": return "消耗资源"
		"on_block": return "格挡"
	return t


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 8 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
