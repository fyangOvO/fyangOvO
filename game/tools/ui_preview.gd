## 阶段 7 UI/UX 面板渲染预览（第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/ui_preview.tscn
##   输出 build/ui_preview.png：7 面板分区（主菜单/属性/装备/天赋/锻造/结算/设置）
extends Node2D

var _frame := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "阶段 7 UI/UX 面板全览（7.1 主菜单 · 7.2 属性 · 7.3 装备 · 7.4 天赋 · 7.5 锻造 · 7.6 结算 · 7.7 设置）"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 8)
	add_child(title)

	# —— 左列：主菜单 / 属性 / 天赋 / 设置 ——
	_add_card_frame(Vector2(20, 46), Vector2(620, 250), "7.1 主菜单 / 角色选择")
	var menu := MainMenuPanel.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mc := _wrap(menu, Vector2(20, 46), Vector2(620, 250))
	add_child(mc)

	_add_card_frame(Vector2(20, 308), Vector2(620, 300), "7.2 角色属性面板")
	var sp := StatPanel.new()
	var sc := _wrap(sp, Vector2(20, 308), Vector2(620, 300))
	add_child(sc)
	# 属性面板只认 StatCalculator.FINAL_KEYS —— 预览直接走真实结算路径
	var stat_gear: Array[EquipmentInstance] = []
	var stpl: EquipmentData = ConfigLoader.get_equipment_template("sword_flame")
	if stpl != null:
		stat_gear.append(
			EquipmentInstance.create_from_template(stpl, 14, GameConstants.Rarity.EPIC))
	sp.show_stats(StatCalculator.calculate(14, stat_gear, {}))

	_add_card_frame(Vector2(20, 620), Vector2(620, 300), "7.4 天赋界面")
	var tp := TalentPanel.new()
	var tc := _wrap(tp, Vector2(20, 620), Vector2(620, 300))
	add_child(tc)
	tp.bind(["war.small.0", "war.small.1", "war.big.2"], 8)

	_add_card_frame(Vector2(20, 932), Vector2(620, 140), "7.7 设置界面（画质/音量/按键）")
	var sp2 := SettingsPanel.new()
	var s2c := _wrap(sp2, Vector2(20, 932), Vector2(620, 140))
	add_child(s2c)

	# —— 右列：装备 / 锻造 / 结算 ——
	_add_card_frame(Vector2(660, 46), Vector2(1240, 360), "7.3 背包装备界面（10 槽）")
	var ep := EquipPanel.new()
	var ec := _wrap(ep, Vector2(660, 46), Vector2(1240, 360))
	add_child(ec)
	var fake: Array = []
	var sword: EquipmentData = ConfigLoader.get_equipment_template("sword_flame")
	if sword != null:
		fake.append(EquipmentInstance.create_from_template(sword, 14, GameConstants.Rarity.RARE))
	var helm: EquipmentData = ConfigLoader.get_equipment_template("helm_crown_titan")
	if helm != null:
		fake.append(EquipmentInstance.create_from_template(helm, 16, GameConstants.Rarity.EPIC))
	var amu: EquipmentData = ConfigLoader.get_equipment_template("amulet_sun")
	if amu != null:
		fake.append(EquipmentInstance.create_from_template(amu, 15, GameConstants.Rarity.LEGENDARY))
	ep.bind(fake)

	_add_card_frame(Vector2(660, 420), Vector2(1240, 300), "7.5 锻造界面")
	var fp := ForgePanel.new()
	var fc := _wrap(fp, Vector2(660, 420), Vector2(1240, 300))
	add_child(fc)
	var forge_items: Array = []
	var dag: EquipmentData = ConfigLoader.get_equipment_template("dagger_venom")
	if dag != null:
		forge_items.append(EquipmentInstance.create_from_template(dag, 9, GameConstants.Rarity.MAGIC))
	var axe: EquipmentData = ConfigLoader.get_equipment_template("axe_blood")
	if axe != null:
		forge_items.append(EquipmentInstance.create_from_template(axe, 11, GameConstants.Rarity.RARE))
	fp.bind(forge_items, 320)

	_add_card_frame(Vector2(660, 732), Vector2(1240, 340), "7.6 结算 / 奖励界面")
	var rp := ResultPanel.new()
	rp.size = Vector2(1240, 340)
	var rc := _wrap(rp, Vector2(660, 732), Vector2(1240, 340))
	add_child(rc)
	var res := RunResult.new()
	res.survived = true
	res.kills = 57
	res.run_level = 9
	res.max_streak = 12
	res.gold_before = 2400.0
	res.gold_after = 1200.0
	var chest: EquipmentData = ConfigLoader.get_equipment_template("chest_ember")
	if chest != null:
		res.bagged_equipment.append(
			EquipmentInstance.create_from_template(chest, 15, GameConstants.Rarity.EPIC))
	var staff: EquipmentData = ConfigLoader.get_equipment_template("staff_storm")
	if staff != null:
		res.bagged_equipment.append(
			EquipmentInstance.create_from_template(staff, 16, GameConstants.Rarity.LEGENDARY))
	res.unbagged_drops = 2
	res.score = 2890.0
	res.grade = "S"
	rp.show_result(res)

	var foot := Label.new()
	foot.text = "全部面板纯代码构建（class_name + 像素风 Theme）· 回调注入解耦业务层 · 验证 verify_ui71 24 项"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 1082)
	add_child(foot)


func _wrap(panel: Control, pos: Vector2, size: Vector2) -> Control:
	var c := Control.new()
	c.position = pos
	c.size = size
	panel.position = Vector2(8, 30)
	panel.size = Vector2(size.x - 16, size.y - 38)
	c.add_child(panel)
	return c


func _add_card_frame(pos: Vector2, size: Vector2, label: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08)
	sb.border_color = Color(0.28, 0.3, 0.36)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sb)
	pc.position = pos
	pc.size = size
	add_child(pc)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	l.position = pos + Vector2(6, -16)
	add_child(l)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/ui_preview.png")
		print("ui_preview saved: err=%d" % err)
		get_tree().quit(0)
