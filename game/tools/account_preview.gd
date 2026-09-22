## 局外成长渲染预览（任务 5.1–5.6 · 开发用，第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/account_preview.tscn
##   输出 build/account_preview.png（四块：账号等级 / 天赋树 / 解锁 / 宝石声望成就）
extends Node2D

var _frame := 0


func _ready() -> void:
	# 用 3.11/4.x 预览同款：根 Control 注入 Viewport，手动画（不依赖主题）
	var c := CanvasLayer.new()
	add_child(c)
	var panel := Panel.new()
	panel.size = Vector2(1280, 720)
	panel.position = Vector2(0, 0)
	c.add_child(panel)

	var title := _label("局外成长 · 任务 5.1–5.6 预览", 26, Color(1.0, 0.84, 0.2))
	title.position = Vector2(24, 16)
	panel.add_child(title)

	# --- 1. 账号等级（左列） ---
	var acc := AccountLevel.new()
	acc.add_xp(AccountLevel.cumulative_to(21)) # 升到 21 级
	var acc_txt := "账号等级：L%d\n" % acc.level
	acc_txt += "升级经验 180×L^1.6：L10=7166 / L20=21723 / L30=41559\n"
	acc_txt += "天赋点：%d / 30（每 2 级 1 点）\n" % acc.talent_points
	acc_txt += "当前进度：%.0f / %.0f（%.0f%%）" % [acc.xp_cur, acc.xp_next, acc.progress() * 100]
	var acc_box := _box("账号 / 巅峰等级（5.1）", acc_txt, Color(0.16, 0.17, 0.22), 300)
	acc_box.position = Vector2(24, 60)
	panel.add_child(acc_box)

	# --- 2. 天赋树（中左） ---
	var tree := TalentTree.new()
	tree.update_unlocks(30)
	tree.learn("might.small.0", 30)
	tree.learn("might.small.1", 30)
	tree.learn("might.big.0", 30)
	tree.learn("guardian.small.0", 30)
	tree.learn("guardian.small.1", 30)
	var b := tree.get_bonus_stats()
	var tree_txt := "3 分支：武力 / 守护 / 秘法（L1/L15/L30 解锁）\n"
	tree_txt += "每分支 15 小(+2%) + 5 大(+8%/机制)，满级 30 点\n"
	tree_txt += "已点 5 节点：攻击 +12% + 护甲 +4%\n"
	tree_txt += "大节点机制：%s\n" % (", ".join(b["mechanics"]) if not b["mechanics"].is_empty() else "—")
	tree_txt += "进度：%d / 15（30 级可用）" % tree.points_spent.size()
	var tree_box := _box("天赋树（5.2）", tree_txt, Color(0.16, 0.19, 0.27), 300)
	tree_box.position = Vector2(340, 60)
	panel.add_child(tree_box)

	# --- 3. 解锁系统（中右） ---
	var unlock_txt := "关卡 L2–L20：顺序通关（已通 12 → L13 开放）\n"
	unlock_txt += "梦魇 I–V：全 20 关解锁，逐层递进\n"
	unlock_txt += "天赋分支 2/3：L15 / L30\n"
	unlock_txt += "仓库页：累计通关 5/10/15 关\n"
	unlock_txt += "— 当前：关卡已解锁 L%d / 梦魇未开 / 仓库 %d 页" % [12, UnlockSystem.stash_pages_unlocked(12)]
	var unlock_box := _box("解锁系统（5.3）", unlock_txt, Color(0.22, 0.16, 0.16), 300)
	unlock_box.position = Vector2(656, 60)
	panel.add_child(unlock_box)

	# --- 4. 锻造附魔 / 宝石 / 声望 / 成就（下排） ---
	var sword := EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("sword_iron"), 12, GameConstants.Rarity.LEGENDARY)
	GemSystem.socket(sword, 0, "ruby.normal")
	GemSystem.socket(sword, 1, "sapphire.flawless")
	var gem_bonus := GemSystem.get_gem_bonus(sword)
	var rep := ChapterReputation.new()
	rep.add_clear("chapter_1")
	for i in 120:
		rep.add_kill("chapter_1")
	var rep_bonus := rep.get_total_bonus()
	var ach := AchievementSystem.new()
	ach.load_definitions()
	ach.report_progress("kills", 5000.0)
	var craft_txt := "洗练（秘银尘×3）/ 特效重铸（精粹×2）\n"
	craft_txt += "橙剑 2 槽：红宝石普通(+6%攻) + 蓝宝石完美(+12%护甲)\n"
	craft_txt += "宝石总加成：攻击 +6% / 护甲 +12%\n"
	craft_txt += "章节声望：1 级（+1% 经验 / +1% 金币）\n"
	craft_txt += "成就：%d / %d 已解锁（纯外观奖励）" % [ach.unlocked_count(), ach.total_count()]
	var craft_box := _box("附魔 / 宝石 / 声望 / 成就（5.4–5.6）", craft_txt, Color(0.15, 0.22, 0.19), 932)
	craft_box.position = Vector2(24, 380)
	panel.add_child(craft_box)

	var foot := _label("数据与代码分离 data/achievements.json · 像素风铁律 · 纯本地自玩不发行", 14, Color(0.6, 0.6, 0.6))
	foot.position = Vector2(24, 690)
	panel.add_child(foot)


func _box(head: String, body: String, bg: Color, w: float) -> Panel:
	var p := Panel.new()
	p.size = Vector2(w, 300)
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = Color(1.0, 0.84, 0.2, 1.0)
	st.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", st)
	var h := _label(head, 20, Color(1.0, 0.84, 0.2))
	h.position = Vector2(12, 10)
	p.add_child(h)
	var l := _label(body, 17, Color(0.96, 0.96, 0.96))
	l.position = Vector2(12, 44)
	p.add_child(l)
	return p


func _label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	return l


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/account_preview.png")
		print("account_preview saved: err=%d" % err)
		get_tree().quit(0)
