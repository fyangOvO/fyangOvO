## 完整存档预览（任务 8.1 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/save_preview.tscn
##   输出 build/save_preview.png：存档内容快照面板（局外/局内/设置 三大区）
extends Node2D

var _frame := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "完整存档预览（任务 8.1 · 局外进度 + 局内进度 + 设置，全字段序列化）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 10)
	add_child(title)

	var d := SaveManager.create_new_slot(7)
	if d == null:
		return
	d.display_name = "示例档"
	d.account_level = 23
	d.account_xp = 456.0
	d.total_xp = 26000.0
	d.talent_points = 8
	d.unlocked_talent_nodes = ["war.small.0", "war.small.1", "war.big.2", "mage.small.0"]
	d.gold = 15800
	d.add_material("magic_stone", 320)
	d.add_material("ember_core", 18)
	d.unlocked_levels = ["ch1_l01", "ch2_l07", "ch2_l08"]
	d.cleared_levels = ["ch1_l01"]
	d.unlocked_difficulty_tier = 3
	d.chapter_reputation = {"ch1": 240.0}
	d.unlocked_achievements = ["ach_first_blood", "ach_kill_100"]
	d.stash_pages = 2
	d.statistics = {"total_kills": 1530, "total_gold": 92000}
	d.current_level_id = "ch2_l09"
	d.current_difficulty_tier = 3
	d.settings = {"master_volume_db": -6.0, "vsync": true, "fullscreen": false}

	var cols := 0.0
	var x0 := 40.0
	var y0 := 80.0
	var card_w := 600.0
	var card_h := 500.0
	_section(x0, y0, card_w, card_h, "局外进度（账号 / 养成）",
		["账号等级 Lv.%d（经验 %.0f / 总经验 %.0f）" % [d.account_level, d.account_xp, d.total_xp],
		"天赋点 %d · 已点节点 %d（战争×3 / 秘法×1）" % [d.talent_points, d.unlocked_talent_nodes.size()],
		"金币 %d · 魔石 %d · 烬核 %d" % [d.gold, d.get_material("magic_stone"), d.get_material("ember_core")],
		"已解锁关卡 %d · 已通关 %d · 难度层级 %d" % [d.unlocked_levels.size(), d.cleared_levels.size(), d.unlocked_difficulty_tier + 1],
		"章节声望 ch1 %d 点 · 成就 %d / 统计（击杀 %d）" % [int(d.chapter_reputation.get("ch1", 0.0)), d.unlocked_achievements.size(), int(d.statistics.get("total_kills", 0))],
		"仓库页 %d · 背包 %d 件 · 已装备 %d 件" % [d.stash_pages, d.inventory.size(), d.get_equipped(GameConstants.EquipSlot.MAIN_HAND) != null]])
	cols += 1
	_section(x0 + cols * (card_w + 40), y0, card_w, card_h, "局内进度（关卡 / 难度）",
		["当前关卡：%s" % d.current_level_id,
		"当前难度：第 %d 层（难度系数 1.08^%d HP / 1.23^%d DMG）" % [d.current_difficulty_tier + 1, d.current_difficulty_tier, d.current_difficulty_tier],
		"",
		"关卡边界存档（D2 方案 B）：",
		"· 本局未入包掉落丢失",
		"· 金币材料结算扣 50%",
		"· 每关 1 次原地复活"])
	cols += 1
	_section(x0 + cols * (card_w + 40), y0, card_w, card_h, "设置（随档保存 / 8.2 独立持久化）",
		["主音量：%.0f dB" % d.settings.get("master_volume_db", 0.0),
		"垂直同步：%s" % str(d.settings.get("vsync", false)),
		"全屏：%s" % str(d.settings.get("fullscreen", false)),
		"",
		"字段：save_version / slot / created_at / updated_at /",
		"play_time_seconds / statistics / settings",
		"",
		"→ 8.2 起设置改为独立 user://settings.json（与存档解耦）"])

	var foot := Label.new()
	foot.text = "验证：verify_save81 15 项（局外 10+ / 局内 2 / 设置 / 装备实例回读 / 跨会话 / 清理）"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 640)
	add_child(foot)

	SaveManager.delete_slot(7)


func _section(x: float, y: float, w: float, h: float, head: String, lines: Array) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09)
	sb.border_color = Color(0.35, 0.42, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sb)
	pc.position = Vector2(x, y)
	pc.size = Vector2(w, h)
	add_child(pc)
	var head_l := Label.new()
	head_l.text = head
	head_l.add_theme_font_size_override("font_size", 15)
	head_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	head_l.position = Vector2(x + 16, y + 14)
	add_child(head_l)
	var yy := y + 52.0
	for line in lines:
		var l := Label.new()
		l.text = str(line)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.82, 0.85, 0.88))
		l.position = Vector2(x + 20, yy)
		add_child(l)
		yy += 26.0


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/save_preview.png")
		print("save_preview saved: err=%d" % err)
		get_tree().quit(0)
