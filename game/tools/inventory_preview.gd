## 背包 / 仓库渲染预览（任务 3.6 · 窗口化自截图验收）
##
## 用法：godot --path "D:/七傳說/game" res://tools/inventory_preview.tscn
## 显示背包网格（8×5，含稀有度边框色块）+ 仓库网格（8×10）+ 整理/排序后对比。
extends Node2D

const PREVIEW_SHOT := "res://build/inventory_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var label := Label.new()
	label.text = "背包 / 仓库预览（3.6）"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	label.position = Vector2(16, 8)
	add_child(label)

	# 背包：8×5，装入 12 件（含 3 件橙 + 1 件红带特效）
	var inv := Inventory.create(8, 5)
	var stash := Inventory.create(8, 10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var templates := [
		ConfigLoader.get_equipment_template("sword_iron"),
		ConfigLoader.get_equipment_template("staff_ashen"),
	]
	var rarities := [
		GameConstants.Rarity.MAGIC, GameConstants.Rarity.RARE, GameConstants.Rarity.EPIC,
		GameConstants.Rarity.LEGENDARY, GameConstants.Rarity.LEGENDARY, GameConstants.Rarity.MYTHIC,
	]
	for i in range(12):
		var tpl: EquipmentData = templates[i % templates.size()]
		var rarity: int = rarities[i % rarities.size()]
		var item := AffixRoller.roll_full_equipment(tpl, 15 + (i % 10), rarity, rng)
		if i == 3:
			item.legendary_effect_id = "jin_shi_ran_po_ren"
		if not inv.add(item):
			break
	# 制造空位演示整理
	inv.remove_at(5)
	inv.remove_at(2)

	# 仓库装 4 件
	for i in range(4):
		stash.add(AffixRoller.roll_full_equipment(
			templates[0], 20 + i, rarities[i + 1], rng))

	# 左侧：整理前背包
	var before_label := Label.new()
	before_label.text = "背包（整理前）"
	before_label.add_theme_font_size_override("font_size", 11)
	before_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.8))
	before_label.position = Vector2(16, 34)
	add_child(before_label)
	var panel := InventoryPanel.new()
	add_child(panel) # 先进树触发 _ready（_build_ui）
	panel.bind(inv, stash)
	panel.position = Vector2(16, 56)
	panel._current = true
	panel._refresh()

	# 右侧：排序后（稀有度降序）
	var after_label := Label.new()
	after_label.text = "按稀有度排序后"
	after_label.add_theme_font_size_override("font_size", 11)
	after_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.8))
	after_label.position = Vector2(470, 34)
	add_child(after_label)
	var panel2 := InventoryPanel.new()
	var inv2 := Inventory.create(8, 5)
	for i in range(12):
		var tpl: EquipmentData = templates[i % templates.size()]
		var rarity: int = rarities[i % rarities.size()]
		var item := AffixRoller.roll_full_equipment(tpl, 15 + (i % 10), rarity, rng)
		if not inv2.add(item):
			break
	inv2.sort_by(Inventory.SORT_RARITY, true)
	add_child(panel2) # 先进树再 bind
	panel2.bind(inv2, Inventory.create(8, 10))
	panel2.position = Vector2(470, 56)
	panel2._current = true
	panel2._refresh()

	# 底部：仓库（8×10 只显示前 2 行）
	var stash_label := Label.new()
	stash_label.text = "仓库（8×10）"
	stash_label.add_theme_font_size_override("font_size", 11)
	stash_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.8))
	stash_label.position = Vector2(16, 330)
	add_child(stash_label)
	var panel3 := InventoryPanel.new()
	add_child(panel3) # 先进树再 bind
	panel3.bind(inv, stash)
	panel3.position = Vector2(16, 352)
	panel3._current = false
	panel3._refresh()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
