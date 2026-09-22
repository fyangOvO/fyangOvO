## 本局结算渲染预览（任务 4.5 · 窗口化自截图验收）
## 用法：godot --path "D:/七傳說/game" res://tools/result_preview.tscn
extends Node2D

const PREVIEW_SHOT := "res://build/result_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "本局结算预览（4.5）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	title.position = Vector2(16, 8)
	add_child(title)

	var y := 40.0
	var h1 := Label.new()
	h1.text = "① 存活结算（D2 方案 B：金币材料扣 50%、入包保留、未入包丢失）"
	h1.add_theme_font_size_override("font_size", 12)
	h1.add_theme_color_override("font_color", Color(0.95, 0.6, 0.6))
	h1.position = Vector2(16, y)
	add_child(h1)
	y += 24

	var bagged: Array = []
	for i in 3:
		bagged.append(EquipmentInstance.create_from_template(
			ConfigLoader.get_equipment_template(
				["sword_iron", "helm_hide", "ring_copper"][i]), 12,
			GameConstants.Rarity.MAGIC))
	var res := RunResult.finalize(true, 126, 10, 2345.0,
		{"gold": 200.0, "dust": 40.0, "essence": 8.0}, bagged, 7, 4, 95)
	var s1 := Label.new()
	s1.text = "  存活通关：击杀 126 / 局内 10 级 / 连杀峰值 95\n" \
		+ "  金币 " + str(int(res.gold_before)) + " → " + str(int(res.gold_after)) + "（扣 50%）· 材料金 " \
		+ str(int(res.materials_after["gold"])) + " / 尘 40→20 / 精粹 8→4\n" \
		+ "  入包 3 件保留 · 未入包 7 件丢失 · 稀有掉落 4 件（评分 +400）"
	s1.add_theme_font_size_override("font_size", 11)
	s1.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	s1.position = Vector2(28, y)
	add_child(s1)
	y += 70

	var h2 := Label.new()
	h2.text = "② 评分公式（工程侧默认）：存活 500 + 击杀 ×10 + 等级 ×50 + 稀有掉落 ×100 + 连杀 ×2"
	h2.add_theme_font_size_override("font_size", 12)
	h2.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	h2.position = Vector2(16, y)
	add_child(h2)
	y += 24
	var s2 := Label.new()
	s2.text = "  本局得分：%d（500 存活 + 1260 击杀 + 500 等级 + 400 稀有 + 190 连杀）→ 评级 S" % int(res.score)
	s2.add_theme_font_size_override("font_size", 11)
	s2.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	s2.position = Vector2(28, y)
	add_child(s2)
	y += 30

	var h3 := Label.new()
	h3.text = "③ 结算面板（ResultPanel）"
	h3.add_theme_font_size_override("font_size", 12)
	h3.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	h3.position = Vector2(16, y)
	add_child(h3)
	y += 6

	var panel := ResultPanel.new()
	panel.size = Vector2(900, 420)
	panel.position = Vector2(0, y)
	panel.show_result(res)
	add_child(panel)
	y += 430

	var h4 := Label.new()
	h4.text = "④ 每关 1 次原地复活（D2）：死亡后可复活继续，复活后金币不再扣"
	h4.add_theme_font_size_override("font_size", 11)
	h4.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	h4.position = Vector2(16, y)
	add_child(h4)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
