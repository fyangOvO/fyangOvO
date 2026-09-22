## BOSS 阶段机制渲染预览（任务 6.3 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/boss_preview.tscn
##   输出 build/boss_preview.png：
##     左区 = 骸骨暴君（骨系）：4 阶段血条 + 阶段技能标签
##     右区 = 熔心之主（火系）：4 阶段血条 + 阶段技能标签 + 阶段乘区
extends Node2D

var _frame := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "BOSS 阶段机制预览（任务 6.3 · 4 阶段 / 召唤 / 范围 / 狂暴）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 8)
	add_child(title)

	var x := 40.0
	for bid in ["boss_bone_tyrant", "boss_ember_lord"]:
		var cfg: Dictionary = ConfigLoader.bosses[bid]
		var m: MonsterData = ConfigLoader.get_monster(bid)
		var cap := Label.new()
		cap.text = "%s（%s · L%d–%d）" % [m.display_name, bid, m.level_min, m.level_max]
		cap.add_theme_font_size_override("font_size", 14)
		cap.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
		cap.position = Vector2(x, 56)
		add_child(cap)
		var y := 90.0
		for phase in range(1, 5):
			# 阶段血条（当前阶段高亮金）
			var bar_bg := ColorRect.new()
			bar_bg.color = Color(0.15, 0.15, 0.15)
			bar_bg.position = Vector2(x, y)
			bar_bg.size = Vector2(260, 18)
			add_child(bar_bg)
			var ratio: float = [1.0, 0.75, 0.5, 0.25][phase - 1]
			var bar := ColorRect.new()
			bar.color = Color(0.9, 0.4, 0.2) if phase < 4 else Color(0.95, 0.2, 0.1)
			bar.position = Vector2(x, y)
			bar.size = Vector2(260 * ratio, 18)
			add_child(bar)
			var lbl := Label.new()
			var skills := BossPhaseController.phase_skills(cfg, phase)
			lbl.text = "阶段 %s（HP %d%%–%d%%）：%s" % [
				BossPhaseController.PHASE_NAMES[phase - 1],
				int(ratio * 100) if phase > 1 else 100,
				int([1.0, 0.75, 0.5, 0.25][phase] * 100) if phase < 4 else 0,
				"、".join(skills)]
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
			lbl.position = Vector2(x + 8, y + 22)
			lbl.size = Vector2(300, 30)
			add_child(lbl)
			y += 54.0
		var er := BossPhaseController.enrage_multipliers(cfg, 4)
		var foot := Label.new()
		foot.text = "狂暴：攻速 ×%.2f / 伤害 ×%.2f · 召唤池 %s" % [
			float(er["interval_mult"]), float(er["damage_mult"]),
			", ".join(cfg.get("summon_pool", []))]
		foot.add_theme_font_size_override("font_size", 11)
		foot.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		foot.position = Vector2(x, y + 4)
		foot.size = Vector2(320, 30)
		add_child(foot)
		x += 360.0

	var note := Label.new()
	note.text = "阶段门 75% / 50% / 25% → 技能逐阶段解锁（召唤 → 范围 AoE → 狂暴）· BOSS 掉落 100% 掉 2–4 件 · 占位色块美术"
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	note.position = Vector2(16, 690)
	add_child(note)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/boss_preview.png")
		print("boss_preview saved: err=%d" % err)
		get_tree().quit(0)
