## 红装 / 彩装渲染预览（任务 3.11 · 窗口化自截图验收）
## 用法：godot --path "D:/七傳說/game" res://tools/mythic_preview.tscn
extends Node2D

const PREVIEW_SHOT := "res://build/mythic_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "红装 / 彩装机制预览（3.11）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	title.position = Vector2(16, 8)
	add_child(title)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var y := 40.0

	# ① 红装：七劫之冠（含神话词缀）
	var crown := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("mythic_crown_seven_kalpa"), 20,
		GameConstants.Rarity.MYTHIC, rng)
	var h1 := Label.new()
	h1.text = "① 红装（神话）· 七劫之冠 + 神话词缀独立槽"
	h1.add_theme_font_size_override("font_size", 12)
	h1.add_theme_color_override("font_color", Color(0.95, 0.6, 0.6))
	h1.position = Vector2(16, y)
	add_child(h1)
	y += 24
	var mythic_text := ""
	for roll in crown.affixes:
		mythic_text += "  • %s（%s）\n" % [roll.to_text(),
			"神话·独立槽" if roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID else "普通"]
	var m1 := Label.new()
	m1.text = mythic_text
	m1.add_theme_font_size_override("font_size", 11)
	m1.add_theme_color_override("font_color", Color(0.85, 0.75, 0.7))
	m1.position = Vector2(28, y)
	add_child(m1)
	y += 24 + 20 * 5 + 20 # 8 行词缀 + 神话行
	var reroll_cost := MythicRerollController.get_reroll_cost(crown)
	var r1 := Label.new()
	r1.text = "  神话重铸成本：神话结晶 ×%d（重掷数值，可重复）" % int(reroll_cost.get(MaterialBag.KEY_CRYSTAL, 0))
	r1.add_theme_font_size_override("font_size", 11)
	r1.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	r1.position = Vector2(28, y)
	add_child(r1)
	y += 34

	# ② 彩装：七傳說·其一（成长演示）
	var amulet := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("hidden_amulet_first_tale"), 20,
		GameConstants.Rarity.HIDDEN, rng)
	var h2 := Label.new()
	h2.text = "② 彩装（隐藏）· 七傳說·其一（成长 +5% 全属性，上限 5%）"
	h2.add_theme_font_size_override("font_size", 12)
	h2.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	h2.position = Vector2(16, y)
	add_child(h2)
	y += 24
	var g0 := Label.new()
	g0.text = "  成长前：growth_value = 0.0（全属性加成并入结算为 0%）"
	g0.add_theme_font_size_override("font_size", 11)
	g0.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	g0.position = Vector2(28, y)
	add_child(g0)
	y += 22
	HiddenGrowthController.apply_growth(amulet, 5.0) # 每 1000 击杀 +1%，5 千击杀后满
	var g1 := Label.new()
	g1.text = "  成长后（5000 击杀）：growth_value = %.0f → 攻击 = 12 × (1 + %.0f%% + 底材 5%%)" % [
		amulet.growth_value, amulet.growth_value]
	g1.add_theme_font_size_override("font_size", 11)
	g1.add_theme_color_override("font_color", Color(0.6, 0.85, 0.65))
	g1.position = Vector2(28, y)
	add_child(g1)
	y += 34

	# ③ 彩装：拾荒者的执念（成长演示）
	var boots := AffixRoller.roll_full_equipment(
		ConfigLoader.get_equipment_template("hidden_boots_scavenger"), 20,
		GameConstants.Rarity.HIDDEN, rng)
	var h3 := Label.new()
	h3.text = "③ 彩装 · 拾荒者的执念（成长 +15% 移速，上限 15%· 每 10 万金币 +1%）"
	h3.add_theme_font_size_override("font_size", 12)
	h3.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	h3.position = Vector2(16, y)
	add_child(h3)
	y += 24
	HiddenGrowthController.apply_growth(boots, 10.0)
	var b1 := Label.new()
	b1.text = "  已成长 +10%% 移速（150 万金币）——结算 move_speed = %.1f（底材随 iLvl 缩放 + 成长 10）" % [
		StatCalculator.calculate(1, [boots])["move_speed"]]
	b1.add_theme_font_size_override("font_size", 11)
	b1.add_theme_color_override("font_color", Color(0.6, 0.85, 0.65))
	b1.position = Vector2(28, y)
	add_child(b1)
	y += 34

	# ④ 保护清单
	var h4 := Label.new()
	h4.text = "④ 红/彩保护清单"
	h4.add_theme_font_size_override("font_size", 12)
	h4.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	h4.position = Vector2(16, y)
	add_child(h4)
	y += 24
	var lines := [
		"  • 彩装不可分解（GDD 3.2.2 唯一性保护，3.8 已拦）",
		"  • 彩装不可重铸（本任务拦截）",
		"  • 红装可重铸神话词缀（神话结晶 ×2，GDD 3.4）",
		"  • 红装 +11/+12 强化耗神话结晶（GDD 6.5，3.4 已实现）",
		"  • 彩装不可交易（纯本地单机，天然满足）",
	]
	for line in lines:
		var row := Label.new()
		row.text = line
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
		row.position = Vector2(16, y)
		add_child(row)
		y += 20


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
