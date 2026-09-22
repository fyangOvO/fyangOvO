## 阶段 11 新增 UI 的真渲染复核（**开发用，不属于游戏玩法**）
##
## 覆盖两个「代码建、从没人见过它渲染」的新 UI（`capture_frame.tscn` 不覆盖它们）：
##   ① `BuffHud`（`level_scene._build_buff_hud()` 建的 Label）—— 局内增益 + 连杀显示
##   ② ESC「放弃本局？」二次确认框（`level_scene._show_abandon_confirm()` 代码建的一整棵 Control 树）
##   ③ 附带：放弃后弹出的 `ResultPanel`（确认更长的数字没把结算布局挤坏）
##
## 用法（**必须去掉 `--headless`**）：
##   export APPDATA="C:/Users/11265/AppData/Roaming"
##   godot --path "D:/七傳說/game" res://tools/capture_new_ui.tscn
##
## 产出（`deliverables/gstack/`）：
##   screenshot-newui-01-buffhud-empty.png          空态（「局内增益：—」）
##   screenshot-newui-02-buffhud-normal.png         常规态（3 个增益 + 连杀）
##   screenshot-newui-03-buffhud-max.png            满态压测（全 15 增益 ×4 层 + 连杀 120）
##   screenshot-newui-04-esc-confirm.png            ESC 二次确认框
##   screenshot-newui-05-result-after-abandon.png   放弃后的结算面板
##
## ⚠️ 与另外两个工具的**分工**（不要混用）：
##   | 工具                    | 覆盖                                   | 需要窗口 |
##   |-------------------------|----------------------------------------|----------|
##   | `capture_frame`         | 主菜单 / 据点 / 关卡（三场景冒烟）      | **是**   |
##   | `capture_choice_panel`  | 三选一面板（配色轴 + 几何）             | **是**   |
##   | `capture_new_ui`（本文件）| BuffHud / ESC 确认框 / 结算面板          | **是**   |
##   | `verify_choice_panel`   | 三选一配色断言（headless，回归自动跑）  | 否       |
##
## 判定口径：**rect / 像素数字**，不靠肉眼看图（本项目已出现 2 次目测误判）。
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables/gstack"
const LEVEL_ID: String = "ch1_l01"

## 视口基准（与 `project.godot` 一致）
const VIEW_W: float = 1920.0
const VIEW_H: float = 1080.0
## 新 HUD 的既定落点（`level_scene._build_buff_hud()`），用于独立复算
const BUFF_HUD_POS: Vector2 = Vector2(24.0, 122.0)
const BUFF_HUD_FONT_SIZE: int = 13
## 规范 §2.5 / §5.1：像素字体**只允许**这些整数尺寸
const LEGAL_FONT_SIZES: Array[int] = [11, 12, 16, 22, 32]

var _fail: int = 0
var _level: LevelScene = null


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 180.0)
	_run()


func _run() -> void:
	print("===== 新增 UI 真渲染复核（BuffHud + ESC 确认框 + 结算面板）=====")
	_ok("渲染驱动不是 headless", DisplayServer.get_name() != "headless")
	print("[Env] DisplayServer=%s · 视口 %s" % [DisplayServer.get_name(), str(get_viewport_rect().size)])

	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _frames(3)
	_level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _settle()
	_ok("关卡已构建（存活敌人 %d）" % _level._alive.size(), not _level._alive.is_empty())
	_freeze_actors()

	print("[Step] ① BuffHud 空态 …")
	await _probe_buff_hud_empty()
	print("[Step] ① BuffHud 常规态 …")
	await _probe_buff_hud_normal()
	print("[Step] ① BuffHud 满态 …")
	await _probe_buff_hud_max()
	print("[Step] ② ESC 确认框 …")
	await _probe_esc_confirm()
	print("[Step] ③ 结算面板 …")
	await _probe_result_panel()

	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 冻结所有敌人。
##
## ⚠️ 为什么必须做（2026-09-18 实测踩到）：`ch1_l01` 刷 40 个敌人，进关后它们会围杀玩家，
## **大约 10 秒内把玩家打死** ⇒ `_finished = true` ⇒ `_on_escape_pressed()` 的守卫 ① 直接
## return（本局已结束，不弹确认框）⇒ ESC 那条链路根本测不到。
## 而且 40 个敌人的攻击日志会把整份日志淹掉（实测刷了 1000+ 行）。
## 冻结 `_physics_process` 即可同时解决「玩家被打死」与「日志被淹没」。
func _freeze_actors() -> void:
	for e in _level._alive:
		if is_instance_valid(e):
			e.set_physics_process(false)
			e.set_process(false)
	print("[Setup] 已冻结 %d 个敌人（_physics_process=false），玩家 HP 保持 %.0f/%.0f"
		% [_level._alive.size(), _level._player.health.get_current_hp(),
			_level._player.health.get_max_hp()])
	# 双保险：万一还有漏网的伤害来源，把玩家血量顶住
	if _level._player != null and _level._player.health != null:
		_level._player.health.current_hp = _level._player.health.get_max_hp()


# =============================================================================
# ① BuffHud
# =============================================================================

func _probe_buff_hud_empty() -> void:
	print("--- ① BuffHud · 空态 ---")
	var l := _buff_label()
	if l == null:
		_ok("找到 BuffHud 节点", false)
		return
	_ok("BuffHud 已挂在 $HUD 下（parent=%s）" % str(l.get_parent().name),
		l.get_parent() == _level.get_node("HUD"))
	_level._buff_system.buffs.clear()
	_level._buff_system.streak = 0
	_level._buff_hud_sig = ""
	_level._refresh_buff_hud()
	await _frames(2)
	_dump_label(l, "空态")
	_ok("空态文案 = 「局内增益：—」（实测「%s」）" % l.text, l.text == "局内增益：—")
	await _shot("screenshot-newui-01-buffhud-empty.png")


func _probe_buff_hud_normal() -> void:
	print("--- ① BuffHud · 常规态（3 增益 + 连杀）---")
	var l := _buff_label()
	if l == null:
		return
	_level._buff_system.buffs.clear()
	for id in ["fury", "gale", "tenacity"]:
		_level._buff_system.apply_option(id)
	_level._buff_system.streak = 0
	for _i in 25:
		_level._buff_system.on_kill()
	_level._refresh_buff_hud()
	await _frames(2)
	_dump_label(l, "常规态")
	print("      文本 = 「%s」" % l.text)
	await _shot("screenshot-newui-02-buffhud-normal.png")


## 满态压测：全部 15 个增益各 4 层 + 连杀 120（连杀加成上限 +15%）。
## 目的：把文本拉到**最长**，看它会不会越出右边界 / 压到战斗区。
func _probe_buff_hud_max() -> void:
	print("--- ① BuffHud · 满态压测（15 增益 ×4 + 连杀 120）---")
	var l := _buff_label()
	if l == null:
		return
	_level._buff_system.buffs.clear()
	for opt in RunePool.OPTIONS:
		for _k in 4:
			_level._buff_system.apply_option(str(opt["id"]))
	_level._buff_system.streak = 0
	_level._buff_system.streak_timer = 0.0
	_level._buff_system._now = 0.0
	for _i in 120:
		_level._buff_system.on_kill()
	_level._refresh_buff_hud()
	await _frames(2)
	_dump_label(l, "满态")
	print("      文本 = 「%s」" % l.text)
	await _shot("screenshot-newui-03-buffhud-max.png")


func _buff_label() -> Label:
	if _level == null:
		return null
	return _level.get_node_or_null("HUD/BuffHud") as Label


func _dump_label(l: Label, tag: String) -> void:
	var r := l.get_global_rect()
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var txt_w := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else -1.0
	print("[%s] pos=%s size=%s rect=%s · font_size=%d（%s）· 文本实测宽 %.1f · 右边界 x=%.1f"
		% [tag, str(l.position), str(l.size), str(r), fs,
			("合法" if fs in LEGAL_FONT_SIZES else "**非法：不在 %s**" % str(LEGAL_FONT_SIZES)),
			txt_w, r.position.x + maxf(txt_w, 0.0)])
	print("      色 = %s · 可见=%s · mouse_filter=%d · autowrap=%d"
		% [l.get_theme_color("font_color").to_html(false), str(l.is_visible_in_tree()),
			l.mouse_filter, l.autowrap_mode])
	_ok("[%s] 位置 = 既定落点 %s（实测 %s）" % [tag, str(BUFF_HUD_POS), str(l.position)],
		l.position.is_equal_approx(BUFF_HUD_POS))
	_ok("[%s] 字号 = 规范允许的整数尺寸（实测 %d，允许 %s）" % [tag, fs, str(LEGAL_FONT_SIZES)],
		fs in LEGAL_FONT_SIZES)
	var right := r.position.x + maxf(txt_w, 0.0)
	_ok("[%s] 文本不越右边界（右边界 x=%.1f ≤ %.0f）" % [tag, right, VIEW_W], right <= VIEW_W)
	_ok("[%s] 不越下边界（底 y=%.1f ≤ %.0f）" % [tag, r.position.y + r.size.y, VIEW_H],
		r.position.y + r.size.y <= VIEW_H)
	# 与既有 HUD 是否重叠（Objective 18..42 / Banner 46..74 / HpBar 84..100）
	for other in ["Objective", "Banner", "HpBar"]:
		var n := _level.get_node_or_null("HUD/%s" % other) as Control
		if n == null:
			continue
		var orr := n.get_global_rect()
		var overlap := r.intersects(orr) and r.size.x > 0.0 and r.size.y > 0.0
		_ok("[%s] 不与 HUD/%s 重叠（%s vs %s）" % [tag, other, str(r), str(orr)], not overlap)


# =============================================================================
# ② ESC 二次确认框
# =============================================================================

func _probe_esc_confirm() -> void:
	print("--- ② ESC「放弃本局？」二次确认框 ---")
	_ok("触发前无确认框", _level._abandon_confirm == null)
	_level._on_escape_pressed()
	await _frames(3)
	await get_tree().create_timer(0.2).timeout
	var confirm := _level._abandon_confirm
	if confirm == null or not is_instance_valid(confirm):
		_ok("确认框已弹出", false)
		return
	_ok("确认框已弹出（name=%s）" % confirm.name, confirm.name == StringName("AbandonConfirm"))
	print("--- 控件树（rect + 越界/溢出判定）---")
	_dump_ctrl(confirm, 1)

	# 遮幕
	var dim := confirm.get_child(0) as ColorRect
	print("[Dim] color=%s a=%.2f rect=%s mouse_filter=%d"
		% [dim.color.to_html(false), dim.color.a, str(dim.get_global_rect()), dim.mouse_filter])
	_ok("遮幕铺满视口（%s）" % str(dim.get_global_rect().size),
		dim.get_global_rect().size.is_equal_approx(Vector2(VIEW_W, VIEW_H)))
	_ok("遮幕不吞鼠标（MOUSE_FILTER_IGNORE，实测 %d）" % dim.mouse_filter,
		dim.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	print("      ⚠️ 遮幕色 %s 是**纯黑**，49 色板里最暗的是 #0B0D10 —— 见结论" % dim.color.to_html(false))

	# 面板盒居中（这是关键：`CenterContainer` 的 preset 是在 add_child **之前**调的）
	var panel := _find_first(confirm, "PanelContainer") as Control
	if panel == null:
		_ok("找到确认框面板（PanelContainer）", false)
	else:
		var pr := panel.get_global_rect()
		var cx := pr.position.x + pr.size.x * 0.5
		var cy := pr.position.y + pr.size.y * 0.5
		print("[Panel] rect=%s · 中心=(%.1f, %.1f) · 视口中心=(%.1f, %.1f)"
			% [str(pr), cx, cy, VIEW_W * 0.5, VIEW_H * 0.5])
		print("[Panel] 面板宽 %.1f（custom_minimum_size.x = 360）· 高 %.1f" % [pr.size.x, pr.size.y])
		_ok("确认框**水平**居中（Δx=%.1fpx，阈值 1px）" % (cx - VIEW_W * 0.5),
			absf(cx - VIEW_W * 0.5) <= 1.0)
		_ok("确认框**垂直**居中（Δy=%.1fpx，阈值 1px）" % (cy - VIEW_H * 0.5),
			absf(cy - VIEW_H * 0.5) <= 1.0)
		_ok("面板宽 ≥ custom_minimum_size 360（实测 %.1f）" % pr.size.x, pr.size.x >= 360.0)
		_ok("面板四边在视口内（%s）" % str(pr),
			pr.position.x >= 0.0 and pr.position.y >= 0.0
			and pr.position.x + pr.size.x <= VIEW_W and pr.position.y + pr.size.y <= VIEW_H)

	# 两个按钮：可点中 + 命中测试
	for bname in ["CancelButton", "ConfirmButton"]:
		var b := confirm.find_child(bname, true, false) as Button
		if b == null:
			_ok("找到按钮 %s" % bname, false)
			continue
		var br := b.get_global_rect()
		var center := br.get_center()
		var hit := _pick_top(confirm, center)
		print("[Btn %s] 「%s」 rect=%s center=%s · mouse_filter=%d · disabled=%s"
			% [bname, b.text, str(br), str(center), b.mouse_filter, str(b.disabled)])
		_ok("按钮 %s 中心最上层 = 它自己（未被遮挡）" % bname,
			hit != null and (hit == b or b.is_ancestor_of(hit)))
		_ok("按钮 %s 尺寸非零且不越视口" % bname,
			br.size.x > 0.0 and br.size.y > 0.0 and br.position.x >= 0.0
			and br.position.x + br.size.x <= VIEW_W)

	await _shot("screenshot-newui-04-esc-confirm.png")

	# 「继续」→ 关闭
	var cancel := confirm.find_child("CancelButton", true, false) as Button
	await _click(cancel)
	await _frames(2)
	_ok("点「继续」后确认框消失（_abandon_confirm = %s）" % str(_level._abandon_confirm),
		_level._abandon_confirm == null)
	_ok("点「继续」没有结算（_finished = %s）" % str(_level._finished), not _level._finished)

	# 再弹一次，点「确认放弃」→ 应结算并弹结算面板
	_level._on_escape_pressed()
	await _frames(3)
	var confirm2 := _level._abandon_confirm
	if confirm2 != null and is_instance_valid(confirm2):
		var ok_btn := confirm2.find_child("ConfirmButton", true, false) as Button
		await _click(ok_btn)
		await _frames(3)
		_ok("点「确认放弃」后进入结算（_finished = %s）" % str(_level._finished), _level._finished)
	else:
		_ok("第二次弹出确认框", false)


# =============================================================================
# ③ 结算面板
# =============================================================================

func _probe_result_panel() -> void:
	print("--- ③ 放弃后的结算面板（更长数字是否挤坏布局）---")
	var rp := _level.get_node_or_null("HUD/ResultPanel") as Control
	if rp == null:
		_ok("找到 ResultPanel", false)
		return
	_ok("结算面板可见（visible=%s）" % str(rp.visible), rp.visible)
	print("--- 结算面板控件树 ---")
	_dump_ctrl(rp, 1)
	await _shot("screenshot-newui-05-result-after-abandon.png")


# =============================================================================
# 通用工具
# =============================================================================

## 递归打印控件树：名字 / 类 / rect / 是否越视口 / 文本是否溢出自身宽度
func _dump_ctrl(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	for c in n.get_children():
		if c is Control:
			var ctl := c as Control
			var r := ctl.get_global_rect()
			var flags: Array[String] = []
			if r.position.x < 0.0 or r.position.y < 0.0 \
					or r.position.x + r.size.x > VIEW_W or r.position.y + r.size.y > VIEW_H:
				flags.append("**越视口**")
			var extra := ""
			if ctl is Label:
				var l := ctl as Label
				var f := l.get_theme_font("font")
				var fs := l.get_theme_font_size("font_size")
				var tw := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else -1.0
				extra = (" text=「%s」fs=%d%s 行=%d 文本宽=%.1f 自身宽=%.1f"
					% [l.text, fs, "" if fs in LEGAL_FONT_SIZES else "(**非法字号**)",
						l.get_line_count(), tw, r.size.x])
				if tw > r.size.x + 0.5:
					flags.append("**文本宽>控件宽**")
			elif ctl is Button:
				extra = " text=「%s」" % (ctl as Button).text
			elif ctl is ColorRect:
				var cr := ctl as ColorRect
				extra = " color=%s a=%.2f" % [cr.color.to_html(false), cr.color.a]
			print("%s%s(%s) rect=%s%s%s" % [pad, ctl.name, ctl.get_class(), str(r), extra,
				("  " + " ".join(flags)) if not flags.is_empty() else ""])
			_dump_ctrl(ctl, depth + 1)


func _find_first(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.is_class(cls):
			return c
		var f := _find_first(c, cls)
		if f != null:
			return f
	return null


func _click(b: Button) -> void:
	if b == null:
		return
	var c := b.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = c
	press.global_position = c
	get_viewport().push_input(press)
	await _frames(1)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	get_viewport().push_input(release)
	await _frames(2)


func _pick_top(n: Node, p: Vector2) -> Control:
	var c := n as Control
	if c == null or not c.is_visible_in_tree():
		return null
	if not c.get_global_rect().has_point(p):
		return null
	var kids := c.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var hit := _pick_top(kids[i], p)
		if hit != null:
			return hit
	if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return c
	return null


func _settle() -> void:
	await _frames(10)
	await get_tree().create_timer(0.6).timeout


func _shot(fname: String) -> void:
	# 逐步打印：这个 `await` 一旦卡住，没有标记的话整份日志里看不出停在哪一步
	# （2026-09-18 实测：脚本「静默停住」跑到 180s 看门狗，日志里只能看到敌人刷屏）
	print("      [Shot] wait frame_post_draw … %s" % fname)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	_ok("抓图 %s → %d×%d（err=%d）" % [fname, img.get_width(), img.get_height(), err],
		err == OK and img.get_width() > 0)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
