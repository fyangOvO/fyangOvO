## 局内成长渲染预览（任务 4.1–4.3 · 窗口化自截图验收）
## 用法：godot --path "D:/七傳說/game" res://tools/run_growth_preview.tscn
extends Node2D

const PREVIEW_SHOT := "res://build/run_growth_preview.png"

var _shot_taken := false
var _frames := 0
var _prog: RunProgression
var _buffs := RunBuffSystem.new()
var _levelups: Array = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "局内成长预览（4.1–4.3）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	title.position = Vector2(16, 8)
	add_child(title)

	var y := 40.0
	var h1 := Label.new()
	h1.text = "① 局内等级（GDD 0.4 节 4.1：1–10 级，每级三选一，出关清零）"
	h1.add_theme_font_size_override("font_size", 12)
	h1.add_theme_color_override("font_color", Color(0.95, 0.6, 0.6))
	h1.position = Vector2(16, y)
	add_child(h1)
	y += 24

	# 模拟击杀经验：1→10 级（每 150 XP 一档，共 ~1850 XP）
	_prog = RunProgression.new(func(lv: int) -> void: _levelups.append(lv))
	var xp_gained := 0.0
	while _prog.run_level < 10:
		_prog.add_xp(150.0)
		xp_gained += 150.0
	var l1 := Label.new()
	l1.text = "  单关 150 怪 × 12 XP 节奏模拟：累计 %d XP → 局内 %d 级（触发 %d 次三选一）" % [
		int(xp_gained), _prog.run_level, _levelups.size()]
	l1.add_theme_font_size_override("font_size", 11)
	l1.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	l1.position = Vector2(28, y)
	add_child(l1)
	y += 34

	var h2 := Label.new()
	h2.text = "② 三选一示例（15 选池，不重复抽取，含 30% 上限移除）"
	h2.add_theme_font_size_override("font_size", 12)
	h2.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	h2.position = Vector2(16, y)
	add_child(h2)
	y += 24

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var stats_pct := {"pct_attack": 24.0} # 假设已选 2 次狂怒（24%）
	var choices := RunePool.get_choices(3, [], stats_pct, rng)
	var desc := ""
	for opt in choices:
		desc += "  【%s】%s：%s\n" % [_cat(str(opt["cat"])), opt["name"], opt["desc"]]
	var c1 := Label.new()
	c1.text = desc
	c1.add_theme_font_size_override("font_size", 11)
	c1.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	c1.position = Vector2(28, y)
	add_child(c1)
	y += 24 + 20 * 3

	var cap_txt := "  （攻击已达 +24%，狂怒再选 1 次即顶 +30% 上限——达上限后该类选项自动移除，切功能性选项）"
	var c2 := Label.new()
	c2.text = cap_txt
	c2.add_theme_font_size_override("font_size", 10)
	c2.add_theme_color_override("font_color", Color(0.6, 0.85, 0.65))
	c2.position = Vector2(28, y)
	add_child(c2)
	y += 30

	var h3 := Label.new()
	h3.text = "③ 三选一 UI（ChoicePanel：攻击 / 防御 / 资源三色卡）"
	h3.add_theme_font_size_override("font_size", 12)
	h3.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	h3.position = Vector2(16, y)
	add_child(h3)
	y += 6

	# ChoicePanel 展示（直接渲染 3 张卡，不弹窗）
	var panel := ChoicePanel.new()
	panel.size = Vector2(900, 200)
	panel.position = Vector2(0, y)
	var demo_opts: Array[Dictionary] = [
		RunePool.get_option("fury"), RunePool.get_option("regrowth"),
		RunePool.get_option("swift"),
	]
	panel._options = demo_opts
	panel._build()
	add_child(panel)
	y += 220

	var h4 := Label.new()
	h4.text = "④ 连杀（GDD 0.4 节 4.3：3 秒内不断连，每 20 连杀 +3% 攻击，上限 +15%）"
	h4.add_theme_font_size_override("font_size", 12)
	h4.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	h4.position = Vector2(16, y)
	add_child(h4)
	y += 24

	_buffs.tick(1.0)
	for i in 100:
		_buffs.on_kill()
		_buffs.tick(0.1)
	var s1 := Label.new()
	s1.text = "  100 连杀（模拟）→ +" + str(round(_buffs.streak_bonus_attack)) + "% 攻击力（已达上限 +15%）"
	s1.add_theme_font_size_override("font_size", 11)
	s1.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	s1.position = Vector2(28, y)
	add_child(s1)
	y += 24

	var calc_buffs := _buffs.to_calculator_buffs()
	var stats := StatCalculator.calculate(1, [], calc_buffs)
	var s2 := Label.new()
	s2.text = "  连杀并入结算：L1 攻击 12 → " + str(round(stats["attack"] * 10.0) / 10.0) + "（×1.15）"
	s2.add_theme_font_size_override("font_size", 11)
	s2.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	s2.position = Vector2(28, y)
	add_child(s2)


func _cat(cat: String) -> String:
	match cat:
		"attack": return "攻击"
		"defense": return "防御"
		"resource": return "资源"
	return cat


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
