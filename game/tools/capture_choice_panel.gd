## 三选一面板（ChoicePanel）**真渲染**取证工具（阶段 11 · 开发用，不属于游戏玩法）
##
## 背景：`ChoicePanel` 经提交 `2022b86` 接线后**从未有人见过它渲染出来的样子**。
## 它的 `_build()` 用 `size` 算卡片位置（`start_x = (size.x - total_w) / 2.0`），
## 调用方 `level_scene._show_choice_panel()` 是「add_child → set preset → call_deferred」三步，
## 这套「先挂后设尺寸再延一帧」的顺序极易出错（本项目已因此踩过 3 次同类坑）。
##
## 本工具只做两件事：**真渲染一帧 + 打印数字诊断**。不碰任何玩法代码。
## 判定口径以 rect / 像素为准，不靠肉眼看图（本项目出现过目测误判：据点按钮「看着偏右」
## 实测中心 959.0、偏差 −1.0px，完全居中）。
##
## 用法（**必须去掉 `--headless`**）：
##   export APPDATA="C:/Users/11265/AppData/Roaming"
##   "$GODOT" --path "D:/七傳說/game" res://tools/capture_choice_panel.tscn
##
## 产出（`deliverables/gstack/`）：
##   screenshot-choice-panel-00-level-baseline.png   无面板的关卡基线（对比「无遮罩」可读性）
##   screenshot-choice-panel-01-real-path.png        真实升级路径弹出的三选一
##   screenshot-choice-panel-02-worst-case-desc.png  最长文案强制三选一（压文字溢出）
##   screenshot-choice-panel-03-after-click.png      点击「选择」之后（验证点击真的生效）
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables/gstack"
const LEVEL_ID: String = "ch1_l01"

## 面板卡片几何（**独立复算**：刻意不读 `ChoicePanel` 的常量，而是写死者以互证；
## 另有 `_check_constant_parity()` 断言两处数值一致，防止漂移）
const CARD_W: float = 220.0
const CARD_H: float = 140.0
const GAP: float = 16.0
const DESC_W: float = CARD_W - 24.0   # 196
const DESC_H: float = 44.0
const DESC_FONT_SIZE: int = 12
const BTN_OFF: Vector2 = Vector2(CARD_W - 76.0, 106.0)   # (144, 106)
const BTN_MIN: Vector2 = Vector2(64.0, 26.0)

var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 180.0)
	_run()


func _run() -> void:
	print("===== ChoicePanel 真渲染取证（阶段 11）=====")
	_ok("渲染驱动不是 headless（否则抓不到画面）",
		DisplayServer.get_name() != "headless")
	var vp := get_viewport_rect().size
	print("[Env] DisplayServer=%s · 视口 %s · 窗口 %s"
		% [DisplayServer.get_name(), str(vp), str(DisplayServer.window_get_size())])
	_ok("视口 = 1920×1080（测得 %s）" % str(vp),
		vp.is_equal_approx(Vector2(1920.0, 1080.0)))

	# ---- ⓪ 常量一致性 + 标题字体可用性（都是「本工具 vs 被测对象」的漂移护栏）----
	_check_constant_parity()
	var tf := ChoicePanel.title_font_report()
	print("[Font] 标题字体实测 = %s · ChillBitmap-16px 可用 = %s"
		% [tf["used"], str(tf["chillbitmap_usable"])])

	# ---- ① 先建关卡，抓一帧「无面板」基线 ----
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _settle()
	_ok("关卡已构建（存活敌人 %d）" % level._alive.size(), not level._alive.is_empty())
	print("[Base] 相机 zoom %s · 玩家 HP %.0f/%.0f · 地图 %d×%d px · 出生格 %s"
		% [str(level._camera.zoom), level._player.health.get_current_hp(),
			level._player.health.get_max_hp(),
			int(level._layout.get("width", 0)) * LevelScene.TILE_PX,
			int(level._layout.get("height", 0)) * LevelScene.TILE_PX,
			str(level._layout.get("player_spawn", Vector2i.ZERO))])
	await _shot("screenshot-choice-panel-00-level-baseline.png")

	# ---- ② size 时序探针：证明「新建的 ChoicePanel.size 在布局跑完前是 0」----
	await _probe_size_timing(level)

	# ---- ③ 文案度量：把 15 条 desc 都在 196×50 / 12px 下量一遍 ----
	var metrics: Array[Dictionary] = await _measure_all_descs(level)

	# ---- ④ 真实升级路径（固定 seed 保证可复现）----
	level._choice_rng.seed = 20260918
	level._on_run_level_up(2)
	await _await_panel_layout(level)
	var panel := level._choice_panel
	_print_panel_dump(panel, "① 真实升级路径（seed=20260918）")
	await _shot("screenshot-choice-panel-01-real-path.png")

	# ---- ⑤ 压测：强制成「度量出来最高的 3 条 desc」----
	var worst := _top3_longest(metrics)
	print("[Worst] 强制三选一 = %s" % str(worst.map(func(o): return o["id"])))
	var forced: Array[Dictionary] = []
	for m in worst:
		forced.append(m)
	level._show_choice_panel(forced)
	await _await_panel_layout(level)
	panel = level._choice_panel
	_print_panel_dump(panel, "② 最长文案强制（压文字溢出）")
	await _shot("screenshot-choice-panel-02-worst-case-desc.png")

	# ---- ⑥ 可点击性：走真实 GUI 事件派发，验证「选择」按钮能被点中 ----
	await _probe_clickable(level, panel)

	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func ford_append(arr: Array[Dictionary], d: Dictionary) -> void:
	arr.append(d)


# =============================================================================
# ② size 时序探针
# =============================================================================

## 实测「新建 ChoicePanel → add_child → set preset → call_deferred」这条链上，
## `size` 到底在哪一帧才变成 1920×1080。这是 `_build()` 能否算出正确卡片位置的前提。
func _probe_size_timing(level: LevelScene) -> void:
	print("--- ② size 时序探针（独立于关卡那一个面板）---")
	var hud: CanvasLayer = level.get_node("HUD")
	var probe := ChoicePanel.new()
	print("[Probe] new() 之后 size = %s（未 add_child）" % str(probe.size))
	_ok("新建 ChoicePanel 初始 size 为 0（若不为 0 则前提变了）",
		probe.size.is_zero_approx())
	hud.add_child(probe)
	print("[Probe] add_child 当帧 size = %s" % str(probe.size))
	probe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	print("[Probe] 设 PRESET_FULL_RECT 当帧 size = %s（同帧读，布局尚未跑）" % str(probe.size))
	print("[Probe] 设 preset 当帧 anchors = L%.2f T%.2f R%.2f B%.2f · offsets = L%.0f T%.0f R%.0f B%.0f"
		% [probe.anchor_left, probe.anchor_top, probe.anchor_right, probe.anchor_bottom,
			probe.offset_left, probe.offset_top, probe.offset_right, probe.offset_bottom])
	await _frames(1)
	print("[Probe] 延 1 帧后 size = %s" % str(probe.size))
	_ok("延 1 帧后 ChoicePanel.size 才等于视口（实测 %s）" % str(probe.size),
		probe.size.is_equal_approx(get_viewport_rect().size))
	print("[Probe] 结论：`_build()` 若在 add_child/set preset 的**同一帧**被调用，"
		+ "读到的 size = (0,0)，start_x = (0−692)/2 = −346、start_y = (0−140)/2 = −70 ⇒ 三卡飞出屏幕左上；"
		+ "`call_deferred` 把它推到下一帧 ⇒ 读到 1920×1080 ⇒ 正常。")
	probe.queue_free()
	await _frames(2)


# =============================================================================
# ③ 文案度量（不渲染，纯 font 度量，覆盖全部 15 条）
# =============================================================================

## 在真实主题（项目默认主题 = Cubic-11）下量出每条 desc 在
## `custom_minimum_size = (196, 50)` + `font_size = 12` + `AUTOWRAP_WORD_SMART` 下的
## 行数与所需高度。返回按「所需高度」降序的数组。
func _measure_all_descs(level: LevelScene) -> Array[Dictionary]:
	print("--- ③ 文案度量（196×50 · 12px · AUTOWRAP_WORD_SMART，全 15 条）---")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level.get_node("HUD").add_child(host)
	await _frames(2)
	var out: Array[Dictionary] = []
	for opt in RunePool.OPTIONS:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(DESC_W, DESC_H)
		l.text = str(opt["desc"])
		host.add_child(l)
		l.size = Vector2(DESC_W, DESC_H)
		var f := l.get_theme_font("font")
		var fh := f.get_height(DESC_FONT_SIZE) if f != null else 0.0
		var lines := l.get_line_count()
		var vis := l.get_visible_line_count()
		var need_h := float(lines) * fh
		var min_sz := l.get_minimum_size()
		out.append({
			"id": str(opt["id"]), "desc": str(opt["desc"]), "cat": str(opt["cat"]),
			"lines": lines, "visible": vis, "font_h": fh, "need_h": need_h,
			"box_h": DESC_H, "over_h": need_h > DESC_H,
			"min_sz": min_sz, "font": f.get_font_name() if f != null else "(null)",
		})
		l.queue_free()
	host.queue_free()
	await _frames(1)

	out.sort_custom(func(a, b): return a["need_h"] > b["need_h"])
	var max_lines := 0
	var overflow_cnt := 0
	for m in out:
		max_lines = maxi(max_lines, int(m["lines"]))
		if bool(m["over_h"]):
			overflow_cnt += 1
		print("    · %-10s %d 行 · 行高 %.1f · 需高 %.1f · 盒高 %.0f · 可见行 %d · min=%s · 「%s」"
			% [m["id"], m["lines"], m["font_h"], m["need_h"], m["box_h"], m["visible"],
				str(m["min_sz"]), m["desc"]])
	print("[Metrics] 字体=%s · 最大行数 %d · 所需最大高度 %.1f（盒高 %.0f）· 溢出 %d/15 条"
		% [out[0]["font"] if not out.is_empty() else "(null)",
			max_lines, out[0]["need_h"] if not out.is_empty() else 0.0, DESC_H, overflow_cnt])
	_ok("全部 15 条 desc 均不溢出卡片下沿（盒高 %.0f，最大需高 %.1f）"
			% [DESC_H, out[0]["need_h"] if not out.is_empty() else 0.0],
		overflow_cnt == 0)
	return out


func _top3_longest(metrics: Array[Dictionary]) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for i in mini(3, metrics.size()):
		var id := str(metrics[i]["id"])
		res.append(RunePool.get_option(id))
	return res


# =============================================================================
# ④ 面板 dump
# =============================================================================

## 等到 `call_deferred(show_choices)` 真正跑完、卡片建好、布局稳定。
func _await_panel_layout(level: LevelScene) -> void:
	await _frames(3)                 # 让 call_deferred 落地
	await get_tree().create_timer(0.25).timeout
	await _frames(3)


func _print_panel_dump(panel: ChoicePanel, label: String) -> void:
	print("--- %s ---" % label)
	if panel == null or not is_instance_valid(panel):
		_ok("ChoicePanel 实例存在", false)
		return
	print("[Panel] visible=%s · size=%s · global_rect=%s" % [str(panel.visible), str(panel.size), str(panel.get_global_rect())])
	print("[Panel] anchors L%.2f T%.2f R%.2f B%.2f · offsets L%.0f T%.0f R%.0f B%.0f · mouse_filter=%d · process_mode=%d"
		% [panel.anchor_left, panel.anchor_top, panel.anchor_right, panel.anchor_bottom,
			panel.offset_left, panel.offset_top, panel.offset_right, panel.offset_bottom,
			panel.mouse_filter, panel.process_mode])
	_ok("面板尺寸 = 视口 1920×1080（实测 %s）—— 直接回答「抓图那刻 size 是否已是 1920×1080」" % str(panel.size),
		panel.size.is_equal_approx(Vector2(1920.0, 1080.0)))
	_ok("面板铺满视口原点（global_rect %s）" % str(panel.get_global_rect()),
		panel.get_global_rect().position.is_zero_approx())
	_check_mask(panel)

	var cards: Array[Control] = []
	for c in panel.get_children():
		# ⚠️ 只认 `Panel`：阶段 11 起面板多了一只全屏 `ColorRect` 遮罩（Dim），
		#    它也是 Control，误当卡片会让边界盒变成整个视口（实测踩到过）。
		if c is Panel:
			cards.append(c)
	var n := cards.size()
	_ok("卡片数 = 选项数（%d）" % n, n > 0)

	# ---- 每张卡的 rect / 颜色 ----
	var xs_lo := INF
	var xs_hi := -INF
	var ys_lo := INF
	var ys_hi := -INF
	var prev_right := -INF
	var overlap := false
	var gap_err := 0.0
	var out_of_screen: Array[String] = []
	for i in n:
		var card := cards[i]
		var r := card.get_global_rect()
		xs_lo = minf(xs_lo, r.position.x)
		xs_hi = maxf(xs_hi, r.position.x + r.size.x)
		ys_lo = minf(ys_lo, r.position.y)
		ys_hi = maxf(ys_hi, r.position.y + r.size.y)
		var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
		print("  [Card %d] pos=%s size=%s rect=%s · bg=%s border=%s(%dpx) · corner_radius=%d"
			% [i, str(card.position), str(card.size), str(r),
				sb.bg_color.to_html(false) if sb != null else "?",
				sb.border_color.to_html(false) if sb != null else "?", sb.border_width_left if sb != null else -1,
				sb.corner_radius_top_left if sb != null else -1])
		if sb != null:
			_ok("  Card %d 底色在 48 色板内（%s）" % [i, sb.bg_color.to_html(false)],
				GameConstants.palette_contains(sb.bg_color))
			_ok("  Card %d 描边色在 48 色板内（%s）" % [i, sb.border_color.to_html(false)],
				GameConstants.palette_contains(sb.border_color))
			_ok("  Card %d 圆角 = 0（像素风铁律）" % i, sb.corner_radius_top_left == 0)
		_ok("  Card %d 尺寸 = (220×140)（实测 %s）" % [i, str(r.size)],
			absf(r.size.x - CARD_W) < 0.6 and absf(r.size.y - CARD_H) < 0.6)
		if r.position.x < 0.0 or r.position.y < 0.0 \
				or r.position.x + r.size.x > 1920.0 or r.position.y + r.size.y > 1080.0:
			out_of_screen.append(str(i))
		if i > 0:
			var gap := r.position.x - prev_right
			gap_err = maxf(gap_err, absf(gap - GAP))
			if gap < 0.0:
				overlap = true
		prev_right = r.position.x + r.size.x
		_print_card_children(card, i)

	# ---- 整体居中 ----
	var box_center_x := (xs_lo + xs_hi) * 0.5
	var box_center_y := (ys_lo + ys_hi) * 0.5
	var dx := box_center_x - 960.0
	var dy := box_center_y - 540.0
	print("[BBox] 三卡整体边界盒 x∈[%.1f, %.1f] y∈[%.1f, %.1f] · 宽 %.1f 高 %.1f"
		% [xs_lo, xs_hi, ys_lo, ys_hi, xs_hi - xs_lo, ys_hi - ys_lo])
	print("[BBox] 整体中心 = (%.1f, %.1f) · 视口中心 (960.0, 540.0) · 偏差 Δx=%.1f Δy=%.1f"
		% [box_center_x, box_center_y, dx, dy])
	print("[BBox] total_w 期望 %.0f（实测 %.1f）· total_h 期望 %.0f（实测 %.1f）"
		% [CARD_W * float(n) + GAP * float(n - 1), xs_hi - xs_lo, CARD_H, ys_hi - ys_lo])
	_ok("三卡整体水平居中（Δx = %.1fpx，阈值 1px）" % dx, absf(dx) <= 1.0)
	_ok("三卡整体垂直居中（Δy = %.1fpx，阈值 1px）" % dy, absf(dy) <= 1.0)
	_ok("相邻卡间距 = gap 16px（最大误差 %.2fpx）" % gap_err, gap_err <= 0.5)
	_ok("相邻卡无重叠", not overlap)
	_ok("四边不越界（越界卡 %s）" % str(out_of_screen), out_of_screen.is_empty())


func _print_card_children(card: Control, ci: int) -> void:
	for c in card.get_children():
		if c is Button:
			var b := c as Button
			var br := b.get_global_rect()
			print("      [Btn] 「%s」 rect=%s · mouse_filter=%d · disabled=%s · 底边 y=%.1f（卡底 %.1f）"
				% [b.text, str(br), b.mouse_filter, str(b.disabled),
					br.position.y + br.size.y, card.get_global_rect().position.y + CARD_H])
			_ok("      Card %d 按钮底边不越卡底（btn_bottom=%.1f ≤ card_bottom=%.1f）"
					% [ci, br.position.y + br.size.y,
						card.get_global_rect().position.y + CARD_H],
				br.position.y + br.size.y <= card.get_global_rect().position.y + CARD_H + 0.01)
			_ok("      Card %d 按钮 mouse_filter 可接收点击（=STOP/PASS，实测 %d）" % [ci, b.mouse_filter],
				b.mouse_filter == Control.MOUSE_FILTER_STOP or b.mouse_filter == Control.MOUSE_FILTER_PASS)
		elif c is Label:
			var l := c as Label
			var lr := l.get_global_rect()
			var card_r := card.get_global_rect()
			var f := l.get_theme_font("font")
			var col := l.get_theme_color("font_color")
			print("      [Label] size=%.0f · 「%s」 rect=%s（相对卡 x=%.0f y=%.0f，高 %.1f）· 行数 %d · 可见行 %d · 色 %s · 字体 %s"
				% [l.get_theme_font_size("font_size"), l.text, str(lr),
					lr.position.x - card_r.position.x, lr.position.y - card_r.position.y, lr.size.y,
					l.get_line_count(), l.get_visible_line_count(), col.to_html(false),
					f.get_font_name() if f != null else "(null)"])
			_ok("      Label「%s」色值在 48 色板内" % l.text.substr(0, 8),
				GameConstants.palette_contains(col))
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
				_ok("      Card %d desc 未溢出盒高（可见行 %d / 总行 %d）" % [ci, l.get_visible_line_count(), l.get_line_count()],
					l.get_visible_line_count() >= l.get_line_count())
				_ok("      Card %d desc 不越卡底（desc_bottom=%.1f ≤ card_bottom=%.1f）"
						% [ci, lr.position.y + lr.size.y, card_r.position.y + CARD_H],
					lr.position.y + lr.size.y <= card_r.position.y + CARD_H + 0.01)
				_ok("      Card %d desc 不越卡右（desc_right=%.1f ≤ card_right=%.1f）"
						% [ci, lr.position.x + lr.size.x, card_r.position.x + CARD_W],
					lr.position.x + lr.size.x <= card_r.position.x + CARD_W + 0.01)


# =============================================================================
# ⑥ 可点击性
# =============================================================================

## 用**真实 GUI 事件**（push_input）验证「选择」按钮能被点中，
## 并用「命中测试」独立复算一次，防止被别的节点遮住。
func _probe_clickable(level: LevelScene, panel: ChoicePanel) -> void:
	print("--- ⑥ 可点击性 ---")
	if panel == null or not is_instance_valid(panel):
		_ok("有面板可测", false)
		return
	var btn: Button = null
	var card0: Control = null
	for c in panel.get_children():
		if not (c is Control) or c.name == StringName("Dim"):
			continue
		for k in (c as Control).get_children():
			if k is Button:
				btn = k
				card0 = c as Control
				break
		if btn != null:
			break
	if btn == null:
		_ok("找到「选择」按钮", false)
		return

	var center := btn.get_global_rect().get_center()
	print("[Click] 目标按钮 center = %s" % str(center))
	# 命中测试：谁在最上层接到这个点
	var hit := _pick_top(panel, center)
	print("[Click] 命中测试结果 = %s / %s（期望 = Button）"
		% [hit.get_class() if hit != null else "(null)", hit.name if hit != null else "(null)"])
	_ok("按钮中心点最上层控件就是该 Button（被遮挡 = 点不中）",
		hit != null and (hit == btn or btn.is_ancestor_of(hit)))

	# 面板自身是否会吞掉全屏鼠标事件（影响「面板显示时玩家用鼠标能否攻击」）
	print("[Click] ChoicePanel.mouse_filter=%d（Control 默认 0=STOP；STOP 会吞掉全屏鼠标点击）"
		% panel.mouse_filter)

	var before_vis := panel.visible
	var before_stacks := level._buff_system.get_stacks(str(RunePool.OPTIONS[0]["id"]))
	# 用真实 GUI 事件点击（Button 默认 ACTION_MODE_BUTTON_RELEASE，需 press + release）
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	get_viewport().push_input(press)
	await _frames(1)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	get_viewport().push_input(release)
	await _frames(2)
	var after_vis := panel.visible
	print("[Click] push_input 点击后：visible %s → %s" % [str(before_vis), str(after_vis)])
	_ok("真实事件点击「选择」按钮被处理（面板收起 visible=false）", before_vis and not after_vis)
	_ok("点击后增益已生效（任选一 id 层数 %d → %d）"
			% [before_stacks, level._buff_system.get_stacks(str(RunePool.OPTIONS[0]["id"]))],
		level._buff_system.buffs.size() > 0)
	await _shot("screenshot-choice-panel-03-after-click.png")


## 递归找最上层命中点 p 的 Control（子先于父、后画先于先画；忽略 IGNORE）。
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


# =============================================================================
# 遮罩（阶段 11 新增）
# =============================================================================

## 全屏遮罩：存在 / 置底 / 铺满 / 不吞鼠标 / alpha 正确。
## **注意**：这里不检查「遮罩是否提高了对比度」——遮罩的价值是模态感与降噪，
## 实测它只把「卡面 vs 地面」从 1.03:1 抬到 1.09:1（几乎没用）。别用它当验收指标。
func _check_mask(panel: ChoicePanel) -> void:
	var mask: ColorRect = null
	var idx := -1
	for i in panel.get_child_count():
		var c := panel.get_child(i)
		if c is ColorRect and c.name == StringName("Dim"):
			mask = c as ColorRect
			idx = i
			break
	if mask == null:
		_ok("全屏遮罩存在（Dim）", false)
		return
	print("[Mask] color=%s a=%.2f · rect=%s · child_index=%d · mouse_filter=%d"
		% [mask.color.to_html(false), mask.color.a, str(mask.get_global_rect()), idx, mask.mouse_filter])
	_ok("遮罩在 0 号位（卡片之下）", idx == 0)
	_ok("遮罩铺满视口（%s）" % str(mask.get_global_rect().size),
		mask.get_global_rect().size.is_equal_approx(Vector2(1920.0, 1080.0)))
	_ok("遮罩 MOUSE_FILTER_IGNORE（不吞鼠标）", mask.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_ok("遮罩 alpha = UI_CHOICE_MASK_ALPHA（%.2f）" % GameConstants.UI_CHOICE_MASK_ALPHA,
		absf(mask.color.a - GameConstants.UI_CHOICE_MASK_ALPHA) < 0.001)
	_ok("遮罩底色 ∈ 48 色板（%s）" % mask.color.to_html(false),
		GameConstants.palette_contains(Color(mask.color.r, mask.color.g, mask.color.b, 1.0)))


# =============================================================================
# 工具
# =============================================================================

## 本工具写死的几何常量 vs `ChoicePanel` 的常量：不一致说明有人改了布局没同步诊断口径。
func _check_constant_parity() -> void:
	_ok("几何常量与 ChoicePanel 一致：CARD_W %s/%s" % [CARD_W, ChoicePanel.CARD_W],
		absf(CARD_W - float(ChoicePanel.CARD_W)) < 0.01)
	_ok("几何常量与 ChoicePanel 一致：CARD_H %s/%s" % [CARD_H, ChoicePanel.CARD_H],
		absf(CARD_H - float(ChoicePanel.CARD_H)) < 0.01)
	_ok("几何常量与 ChoicePanel 一致：GAP %s/%s" % [GAP, ChoicePanel.CARD_GAP],
		absf(GAP - float(ChoicePanel.CARD_GAP)) < 0.01)
	_ok("几何常量与 ChoicePanel 一致：DESC_H %s/%s" % [DESC_H, ChoicePanel.DESC_BOX_H],
		absf(DESC_H - float(ChoicePanel.DESC_BOX_H)) < 0.01)
	_ok("几何常量与 ChoicePanel 一致：DESC_W %s/%s" % [DESC_W, ChoicePanel.DESC_BOX_W],
		absf(DESC_W - float(ChoicePanel.DESC_BOX_W)) < 0.01)
	_ok("几何常量与 ChoicePanel 一致：按钮位置 %s/%s" % [str(Vector2(CARD_W - 76.0, 106.0)), str(ChoicePanel.BTN_POS)],
		Vector2(CARD_W - 76.0, 106.0).is_equal_approx(ChoicePanel.BTN_POS))
	_ok("几何常量与 ChoicePanel 一致：按钮尺寸 %s/%s" % [str(BTN_MIN), str(Vector2(ChoicePanel.BTN_W, ChoicePanel.BTN_H))],
		BTN_MIN.is_equal_approx(Vector2(ChoicePanel.BTN_W, ChoicePanel.BTN_H)))


func _settle() -> void:
	await _frames(10)
	await get_tree().create_timer(0.6).timeout


func _shot(fname: String) -> void:
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
