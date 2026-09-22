## 技能库渲染预览（任务 6.4 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/skills_preview.tscn
##   输出 build/skills_preview.png：8 技能（3 出战 + 5 备选）卡片网格
extends Node2D

var _frame := 0

## 元素 → 色（48 色板内取）
const ELEMENT_COLORS := {
	"physical": Color(0.72, 0.62, 0.5),
	"fire": Color(0.85, 0.35, 0.15),
	"cold": Color(0.35, 0.6, 0.85),
	"lightning": Color(0.85, 0.78, 0.25),
	"poison": Color(0.45, 0.7, 0.3),
	"shadow": Color(0.5, 0.35, 0.7),
}

const TYPE_NAMES := {"single": "单体", "aoe": "范围", "dash": "位移"}


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "技能库扩充预览（任务 6.4 · 8 技能 = 3 出战 + 5 备选，6 元素）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 8)
	add_child(title)

	var ids := ConfigLoader.get_all_skill_ids()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var sa := ConfigLoader.get_skill(a)
		var sb := ConfigLoader.get_skill(b)
		if sa == null or sb == null:
			return a < b
		return sa.slot > sb.slot)  # 出战（slot 1-3）排前

	var x0 := 30.0
	var y0 := 60.0
	var col_w := 330.0
	var row_h := 118.0
	for i in ids.size():
		var sd: SkillData = ConfigLoader.get_skill(ids[i])
		var cx := x0 + float(i % 2) * col_w
		var cy := y0 + float(i / 2) * row_h
		# 卡片底
		var card := ColorRect.new()
		card.color = Color(0.09, 0.09, 0.12)
		card.position = Vector2(cx, cy)
		card.size = Vector2(310, 100)
		add_child(card)
		# 元素条
		var el := ColorRect.new()
		el.color = ELEMENT_COLORS.get(sd.element, Color(0.5, 0.5, 0.5))
		el.position = Vector2(cx + 8, cy + 8)
		el.size = Vector2(46, 46)
		add_child(el)
		var badge := Label.new()
		badge.text = "%s\n%s" % [sd.element, TYPE_NAMES.get(SkillData.TYPE_KEYS[sd.type], "")]
		badge.add_theme_font_size_override("font_size", 9)
		badge.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
		badge.position = Vector2(cx + 10, cy + 10)
		badge.size = Vector2(46, 42)
		add_child(badge)
		# 技能名 + 槽位
		var nm := Label.new()
		nm.text = "%s%s" % [sd.display_name, "" if sd.slot == 0 else "（出战·栏 %d）" % sd.slot]
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
		nm.position = Vector2(cx + 62, cy + 6)
		add_child(nm)
		# 数值行
		var nums := Label.new()
		var extra := ""
		match sd.type:
			SkillData.SkillType.SINGLE:
				extra = "射程 %.0f" % sd.range
			SkillData.SkillType.AOE:
				extra = "半径 %.0f" % sd.radius
			SkillData.SkillType.DASH:
				extra = "冲刺 %.0f" % sd.dash_distance
		nums.text = "倍率 %.2f  ·  冷却 %.1fs  ·  蓝 %.0f  ·  %s" % [
			sd.multiplier, sd.cooldown, sd.mana_cost, extra]
		nums.add_theme_font_size_override("font_size", 11)
		nums.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
		nums.position = Vector2(cx + 62, cy + 28)
		add_child(nums)
		# 描述
		var desc := Label.new()
		desc.text = sd.description
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", Color(0.62, 0.66, 0.7))
		desc.position = Vector2(cx + 62, cy + 48)
		desc.size = Vector2(240, 46)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(desc)

	var foot := Label.new()
	foot.text = "出战栏位 1/2/3（裂斩/旋刃/突进）· 备选 5 个 slot 0（冰霜新星/火球/闪电链/毒云/暗影步）供局内成长替换 · 元素表扩至 6 系（+影）"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 690)
	add_child(foot)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/skills_preview.png")
		print("skills_preview saved: err=%d" % err)
		get_tree().quit(0)
