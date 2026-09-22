## 分解 / 合成 / 材料回收渲染预览（任务 3.8 · 窗口化自截图验收）
## 用法：godot --path "D:/七傳說/game" res://tools/dismantle_preview.tscn
extends Node2D

const PREVIEW_SHOT := "res://build/dismantle_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "分解 / 合成 / 材料回收预览（3.8）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	title.position = Vector2(16, 8)
	add_child(title)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var bag := MaterialBag.create({MaterialBag.KEY_DUST: 120, MaterialBag.KEY_ESSENCE: 12, MaterialBag.KEY_CRYSTAL: 2, MaterialBag.KEY_GOLD: 5000})

	var y := 36.0
	# 分区 1：分解产出表（GDD 5.3）
	var h1 := Label.new()
	h1.text = "① 分解产出（GDD 5.3 表）"
	h1.add_theme_font_size_override("font_size", 12)
	h1.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	h1.position = Vector2(16, y)
	add_child(h1)
	y += 22
	var rarities := [GameConstants.Rarity.MAGIC, GameConstants.Rarity.RARE, GameConstants.Rarity.EPIC,
		GameConstants.Rarity.LEGENDARY, GameConstants.Rarity.SET, GameConstants.Rarity.MYTHIC, GameConstants.Rarity.HIDDEN]
	for r in rarities:
		var item := AffixRoller.roll_full_equipment(
			ConfigLoader.get_equipment_template("sword_iron"), 20, r, rng)
		var res := DismantleController.try_dismantle(item)
		var row := Label.new()
		var txt := "%s → " % GameConstants.rarity_name(r)
		if res.is_empty():
			txt += "不可分解 / 无产出"
		else:
			var parts: Array[String] = []
			for k in res:
				parts.append("%s×%d" % [MaterialBag.KEY_NAMES.get(k, k), res[k]])
			txt += " ".join(parts)
		row.text = txt
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
		row.position = Vector2(28, y)
		add_child(row)
		y += 20

	# 分区 2：合成配方（4 档）
	y += 10
	var h2 := Label.new()
	h2.text = "② 合成配方（工程侧默认，GDD 未给）"
	h2.add_theme_font_size_override("font_size", 12)
	h2.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	h2.position = Vector2(16, y)
	add_child(h2)
	y += 22
	for rid in CraftController.get_recipes():
		var cost: Dictionary = CraftController.get_craft_cost(rid)
		var parts: Array[String] = []
		for k in cost:
			parts.append("%s×%d" % [MaterialBag.KEY_NAMES.get(k, k), cost[k]])
		var row := Label.new()
		row.text = "%s：%s → %s" % [rid, " + ".join(parts), GameConstants.rarity_name(int((CraftController.RECIPES[rid] as Dictionary)["rarity"]))]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
		row.position = Vector2(28, y)
		add_child(row)
		y += 20

	# 分区 3：材料包 + 合成产出演示
	y += 10
	var h3 := Label.new()
	h3.text = "③ 材料包与合成"
	h3.add_theme_font_size_override("font_size", 12)
	h3.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	h3.position = Vector2(16, y)
	add_child(h3)
	y += 22
	var bag_row := Label.new()
	bag_row.text = "材料包：%s" % bag.to_text()
	bag_row.add_theme_font_size_override("font_size", 11)
	bag_row.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	bag_row.position = Vector2(28, y)
	add_child(bag_row)
	y += 20
	for rid in CraftController.get_recipes():
		var item := CraftController.try_craft(rid, bag, rng)
		var row := Label.new()
		if item == null:
			row.text = "%s：材料不足" % rid
		else:
			row.text = "%s → 获得 %s（%s · iLvl %d%s）" % [rid, item.get_display_name(),
				GameConstants.rarity_name(item.rarity), item.item_level,
				" · 特效：%s" % (ConfigLoader.legendary_effects.get(item.legendary_effect_id, {}).get("name", ""))
					if not item.legendary_effect_id.is_empty() else ""]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
		row.position = Vector2(28, y)
		add_child(row)
		y += 20
	var bag_after := Label.new()
	bag_after.text = "合成后：%s" % bag.to_text()
	bag_after.add_theme_font_size_override("font_size", 11)
	bag_after.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	bag_after.position = Vector2(28, y)
	add_child(bag_after)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
