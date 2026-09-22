## 套装系统渲染预览（任务 3.10 · 窗口化自截图验收）
## 用法：godot --path "D:/七傳說/game" res://tools/set_preview.tscn
extends Node2D

const PREVIEW_SHOT := "res://build/set_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "套装系统预览（3.10）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	title.position = Vector2(16, 8)
	add_child(title)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916

	# 装备 5 件霜噬 + 1 件烬途（演示 4 档激活）
	var equipped: Array[EquipmentInstance] = []
	var frost_tpl := ["set_frostbite_helm", "set_frostbite_chest", "set_frostbite_gloves",
		"set_frostbite_legs", "set_frostbite_boots"]
	var frost_slots := [GameConstants.EquipSlot.HELM, GameConstants.EquipSlot.CHEST,
		GameConstants.EquipSlot.GLOVES, GameConstants.EquipSlot.LEGS, GameConstants.EquipSlot.BOOTS]
	for i in range(5):
		var item := AffixRoller.roll_full_equipment(
			ConfigLoader.get_equipment_template(frost_tpl[i]), 20, GameConstants.Rarity.SET, rng)
		item.slot = frost_slots[i]
		equipped.append(item)
	equipped.append(AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("set_emberpath_amulet"), 20, GameConstants.Rarity.SET, rng))

	# 左上：套装进度面板
	var info := Label.new()
	info.text = "① 套装进度（霜噬 5/6 · 烬途 1/6 · 守誓者 0/6）"
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	info.position = Vector2(16, 36)
	add_child(info)

	var panel := SetPanel.new()
	add_child(panel)
	panel.show_sets(equipped)
	panel.position = Vector2(16, 62)

	# 右上：激活加成汇总
	var stats := SetSystem.get_bonus_stats(equipped)
	var stats_label := Label.new()
	stats_label.text = "② 激活套装加成汇总（并入属性结算）"
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	stats_label.position = Vector2(460, 36)
	add_child(stats_label)
	var st_lines := "（无激活加成）" if stats.is_empty() else ""
	var y := 62.0
	for key in stats:
		st_lines += "  %s：+%s\n" % [EquipmentCompare._label_for(key), ("%.0f" % stats[key])]
	var st := Label.new()
	st.text = st_lines
	st.add_theme_font_size_override("font_size", 11)
	st.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	st.position = Vector2(472, y)
	add_child(st)

	# 底：属性结算含套装
	var final_stats := StatCalculator.calculate(20, equipped)
	var final_label := Label.new()
	final_label.text = "③ 属性结算（L20 + 5 霜噬 + 1 烬途，套装加成已并入）"
	final_label.add_theme_font_size_override("font_size", 12)
	final_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	final_label.position = Vector2(16, 330)
	add_child(final_label)
	var final_text := Label.new()
	final_text.text = StatCalculator.to_text(final_stats)
	final_text.add_theme_font_size_override("font_size", 11)
	final_text.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	final_text.position = Vector2(28, 356)
	add_child(final_text)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
