## 本局结算面板（任务 4.5 · class_name，7.6 增强：奖励明细 + 返回/再来按钮）
##
## 展示结算单：存活状态 / 击杀 / 局内等级 / 金币材料扣 50% / 掉落统计 / 评分等级。
## 7.6 新增：逐项奖励清单（金币/材料/已入包装备）+ 两个按钮（返回大厅 / 再来一局），
## 回调由战斗层注入（on_hub / on_restart）。
class_name ResultPanel
extends Control

## 7.6 回调（可空）
var on_hub: Callable = Callable()
var on_restart: Callable = Callable()


## 显示结算单
func show_result(res: RunResult) -> void:
	for child in get_children():
		child.queue_free()
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(480, 430)
	panel.position = Vector2((size.x - 480) / 2.0, (size.y - 430) / 2.0)
	panel.size = Vector2(480, 430)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.5, 0.8, 0.5) if res.survived else Color(0.8, 0.4, 0.35)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var title := Label.new()
	title.text = "本局结算（4.5 / 7.6）— " + ("存活通关" if res.survived else "战斗失败")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color",
		Color(0.6, 0.9, 0.6) if res.survived else Color(0.9, 0.55, 0.5))
	title.position = Vector2(20, 14)
	panel.add_child(title)

	var y := 48.0
	var lines := [
		"击杀：%d 只" % res.kills,
		"局内等级：%d" % res.run_level,
		"连杀峰值：%d（评分 +%d）" % [res.max_streak, int(res.max_streak * RunResult.STREAK_SCORE)],
		"",
		"—— 结算规则（D2 方案 B）——",
		"金币：%d → %d（扣 50%%）" % [int(res.gold_before), int(res.gold_after)],
		"材料：入包保留、扣 50%%",
		"已入包装备：%d 件（保留）" % res.bagged_equipment.size(),
		"未入包掉落：%d 件（丢失）" % res.unbagged_drops,
		"",
	]
	for line in lines:
		var row := Label.new()
		row.text = line
		row.add_theme_font_size_override("font_size", 12)
		row.add_theme_color_override("font_color", Color(0.85, 0.88, 0.9))
		row.position = Vector2(28, y)
		panel.add_child(row)
		y += 22

	# 7.6：逐项奖励清单（前 6 件已入包装备，超出显示计数）
	var reward_head := Label.new()
	reward_head.text = "—— 本次收获（前 6 件）——"
	reward_head.add_theme_font_size_override("font_size", 11)
	reward_head.add_theme_color_override("font_color", Color(0.8, 0.75, 0.55))
	reward_head.position = Vector2(28, y + 2)
	panel.add_child(reward_head)
	y += 20
	var shown := 0
	for item in res.bagged_equipment:
		if shown >= 6:
			break
		var rl := Label.new()
		var tmpl: EquipmentData = ConfigLoader.get_equipment_template(item.template_id)
		var nm: String = tmpl.display_name if tmpl != null else str(item.template_id)
		rl.text = "· %s（稀有 %d · iLvl %d）" % [nm, item.rarity, item.item_level]
		rl.add_theme_font_size_override("font_size", 11)
		rl.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
		rl.position = Vector2(44, y)
		panel.add_child(rl)
		y += 18
		shown += 1
	if res.bagged_equipment.size() > 6:
		var more := Label.new()
		more.text = "… 另有 %d 件" % (res.bagged_equipment.size() - 6)
		more.add_theme_font_size_override("font_size", 10)
		more.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		more.position = Vector2(44, y)
		panel.add_child(more)
		y += 18
	y += 6

	var score_l := Label.new()
	score_l.text = "评分：%d 分 · 评级 " % int(res.score)
	score_l.add_theme_font_size_override("font_size", 13)
	score_l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.9))
	score_l.position = Vector2(28, y)
	panel.add_child(score_l)

	var grade_l := Label.new()
	grade_l.text = res.grade
	grade_l.add_theme_font_size_override("font_size", 20)
	grade_l.add_theme_color_override("font_color", _grade_color(res.grade))
	grade_l.position = Vector2(150, y - 2)
	panel.add_child(grade_l)

	# 7.6：按钮行
	var btn_y := y + 40.0
	var hub_btn := Button.new()
	hub_btn.text = "返回大厅"
	hub_btn.add_theme_font_size_override("font_size", 13)
	hub_btn.position = Vector2(120, btn_y)
	hub_btn.pressed.connect(func() -> void:
		if on_hub.is_valid():
			on_hub.call())
	panel.add_child(hub_btn)
	var rest_btn := Button.new()
	rest_btn.text = "再来一局"
	rest_btn.add_theme_font_size_override("font_size", 13)
	rest_btn.position = Vector2(270, btn_y)
	rest_btn.pressed.connect(func() -> void:
		if on_restart.is_valid():
			on_restart.call())
	panel.add_child(rest_btn)


func _grade_color(grade: String) -> Color:
	match grade:
		"S": return Color(1.0, 0.75, 0.3)
		"A": return Color(0.6, 0.85, 0.5)
		"B": return Color(0.5, 0.75, 0.95)
		"C": return Color(0.85, 0.8, 0.6)
	return Color(0.6, 0.6, 0.6)
