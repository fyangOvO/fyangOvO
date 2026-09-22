## 装备库填充渲染预览（任务 6.5 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/equip_preview.tscn
##   输出 build/equip_preview.png：按部位分列的 62 件装备全览（含 20 件新增高亮）
extends Node2D

var _frame := 0

## 稀有度 → 色
const RARITY_COLORS := {
	"common": Color(0.82, 0.82, 0.82),
	"magic": Color(0.4, 0.6, 0.9),
	"rare": Color(0.9, 0.78, 0.3),
	"epic": Color(0.6, 0.4, 0.85),
	"legendary": Color(0.95, 0.55, 0.2),
	"mythic": Color(0.85, 0.3, 0.35),
	"set": Color(0.35, 0.8, 0.45),
	"hidden": Color(0.9, 0.3, 0.85),
}

const NEW_IDS := ["sword_flame", "axe_blood", "hammer_glacier", "dagger_venom",
	"staff_storm", "bow_spirit", "helm_golem", "chest_ember", "gloves_cold",
	"legs_guardian", "boots_wind", "helm_crown_titan", "amulet_ember",
	"ring_frost", "ring_storm", "amulet_veil", "ring_blood", "amulet_sun",
	"ring_echo", "amulet_guard"]

const SLOT_NAMES := {
	GameConstants.EquipSlot.MAIN_HAND: "主手",
	GameConstants.EquipSlot.OFF_HAND: "副手",
	GameConstants.EquipSlot.HELM: "头盔",
	GameConstants.EquipSlot.CHEST: "胸甲",
	GameConstants.EquipSlot.GLOVES: "手套",
	GameConstants.EquipSlot.LEGS: "腿甲",
	GameConstants.EquipSlot.BOOTS: "靴子",
	GameConstants.EquipSlot.AMULET: "护符",
	GameConstants.EquipSlot.RING_A: "戒指A",
	GameConstants.EquipSlot.RING_B: "戒指B",
}


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "装备库填充预览（任务 6.5 · 42 → 62 件：武器 14 / 护甲 14 / 饰品 16 + 套装件 18）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 8)
	add_child(title)

	# 按槽位分组
	var groups := {}
	for id in ConfigLoader.get_all_equipment_ids():
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(id)
		if not groups.has(tpl.slot):
			groups[tpl.slot] = []
		groups[tpl.slot].append(tpl)

	var y0 := 52.0
	var x0 := 24.0
	var row_h := 44.0
	var rows_drawn := 0
	for slot in [GameConstants.EquipSlot.MAIN_HAND, GameConstants.EquipSlot.OFF_HAND,
			GameConstants.EquipSlot.HELM, GameConstants.EquipSlot.CHEST,
			GameConstants.EquipSlot.GLOVES, GameConstants.EquipSlot.LEGS,
			GameConstants.EquipSlot.BOOTS, GameConstants.EquipSlot.AMULET,
			GameConstants.EquipSlot.RING_A, GameConstants.EquipSlot.RING_B]:
		var list: Array = groups.get(slot, [])
		list.sort_custom(func(a, b): return a.id < b.id)
		var label := Label.new()
		label.text = "%s（%d）" % [SLOT_NAMES.get(slot, "?"), list.size()]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		label.position = Vector2(x0, y0 + rows_drawn * row_h)
		add_child(label)
		rows_drawn += 1
		var x := x0 + 90.0
		for tpl in list:
			if x > 1740.0:
				rows_drawn += 1
				x = x0 + 90.0
			var is_new := NEW_IDS.has(tpl.id)
			var chip := ColorRect.new()
			chip.color = Color(0.12, 0.12, 0.16) if not is_new else Color(0.18, 0.22, 0.16)
			chip.position = Vector2(x, y0 + rows_drawn * row_h - 12)
			chip.size = Vector2(150, 26)
			add_child(chip)
			var rar := ColorRect.new()
			rar.color = RARITY_COLORS.get(GameConstants.RARITY_KEYS[tpl.rarity_min], Color(0.6, 0.6, 0.6))
			rar.position = Vector2(x + 4, y0 + rows_drawn * row_h - 10)
			rar.size = Vector2(8, 22)
			add_child(rar)
			var nm := Label.new()
			nm.text = "%s%s" % [tpl.display_name, "*" if is_new else ""]
			nm.add_theme_font_size_override("font_size", 10)
			nm.add_theme_color_override("font_color",
				Color(1.0, 0.95, 0.7) if is_new else Color(0.82, 0.84, 0.86))
			nm.position = Vector2(x + 16, y0 + rows_drawn * row_h - 13)
			nm.size = Vector2(130, 16)
			add_child(nm)
			x += 156.0
		rows_drawn += 1

	var foot := Label.new()
	foot.text = "色条 = 稀有度下限（白/蓝/黄/紫/橙/红/绿/彩）· * = 6.5 新增 20 件 · 套装件 18 件含于其中（3 套装 × 6）"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 696)
	add_child(foot)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/equip_preview.png")
		print("equip_preview saved: err=%d" % err)
		get_tree().quit(0)
