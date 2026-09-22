## 属性结算渲染预览（任务 3.9 · 窗口化自截图验收）
## 用法：godot --path "D:/七傳說/game" res://tools/stat_preview.tscn
extends Node2D

const PREVIEW_SHOT := "res://build/stat_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "属性结算系统预览（3.9）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	title.position = Vector2(16, 8)
	add_child(title)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916

	# 左：L20 裸装
	_add_block(16, 40, "L20 裸装（GDD 6.2）", StatCalculator.to_text(StatCalculator.calculate(20, [])), Color(0.72, 0.76, 0.8))

	# 中：L20 半装（3 件橙 +6）
	var mid: Array[EquipmentInstance] = []
	var mid_tpl := ["sword_iron", "helm_hide", "ring_copper"]
	for i in range(3):
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(mid_tpl[i])
		var item := AffixRoller.roll_full_equipment(tpl, 20, GameConstants.Rarity.LEGENDARY, rng)
		item.forge_level = 6
		mid.append(item)
	_add_block(360, 40, "L20 半装（3 件橙 +6）", StatCalculator.to_text(StatCalculator.calculate(20, mid)), Color(0.8, 0.72, 0.5))

	# 右：L20 满装（8 件橙 +10）
	var full: Array[EquipmentInstance] = []
	var full_tpl := ["sword_iron", "helm_hide", "chest_chainmail", "boots_wanderer",
		"gloves_leather", "ring_copper", "amulet_bone", "shield_tower"]
	for i in range(full_tpl.size()):
		var tpl: EquipmentData = ConfigLoader.get_equipment_template(full_tpl[i])
		var item := AffixRoller.roll_full_equipment(tpl, 20, GameConstants.Rarity.LEGENDARY, rng)
		item.forge_level = 10
		full.append(item)
	var full_stats := StatCalculator.calculate(20, full)
	var bare := StatCalculator.base_stats(20)
	_add_block(720, 40, "L20 满装（8 件橙 +10）", StatCalculator.to_text(full_stats) + "\nAD 倍率 ≈ ×%.1f（裸装 %d）" % [full_stats["attack"] / bare["flat_attack"], bare["flat_attack"]], Color(0.5, 0.85, 0.55))

	# 底：Buff 演示
	_add_block(16, 620, "Buff 演示（L1 裸装 + 狂战）",
		StatCalculator.to_text(StatCalculator.calculate(1, [], {"berserk": {"flat": {"flat_attack": 10.0}, "pct": {"pct_attack": 50.0}}})) + "\n（flat +10、pct +50% → 攻击 = 22 × 1.5 = 33）", Color(0.6, 0.65, 0.7))


func _add_block(x: float, y: float, header: String, body: String, hcolor: Color) -> void:
	var h := Label.new()
	h.text = header
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", hcolor)
	h.position = Vector2(x, y)
	add_child(h)
	var b := Label.new()
	b.text = body
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	b.position = Vector2(x + 12, y + 24)
	add_child(b)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
