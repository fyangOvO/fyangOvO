## 三选一面板（ChoicePanel）配色断言 —— **headless 可跑**，归 `run_regression.py` 自动发现
##
## 用法（`run_regression.py` 会自己调）：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_choice_panel.tscn
##
## ---------------------------------------------------------------------------
## 为什么需要它（本项目的口头禅：**逻辑对 ≠ 画面对，也 ≠ 配色对**）
## ---------------------------------------------------------------------------
## `capture_choice_panel`（同目录）证明的是**画面**：真渲染一帧、量 rect / 字体 / 像素。
## 它**证明不了配色**——它需要窗口，跑不进 headless 回归；而且它只在被人工执行时才跑。
##
## 2026-09-18 真渲染审计发现：`choice_panel.gd` 是**全项目唯一一处手工建卡的 UI**，
## 因此它绕开了 `UITheme` → `GameConstants` 这条唯一色源链路。7 个色值全是
## `Color(...)` 字面量、其中 6 个不在 48 色板内 —— 而 108 项自检 + 43 个 verify **全绿**。
## 机制原因：`ui_colors_not_in_palette()` 只扫**已登记的常量**，扫不到没登记的字面量
## ⇒ **只修那 7 个色值 = 只修症状**；下一个不走主题的面板同样查不出。
##
## 本脚本把那类问题**永久关掉**，四道断言：
##   ① 源码级：`choice_panel.gd` 里**不得出现任何 `Color(...)` / `Color8(...)` /
##      `Color.html` 字面量** —— 色值必须来自 `GameConstants` 常量。
##      （这是唯一能拦住「将来新写一个不透明字面量」的关卡；值级断言拦不住「还没建的卡片」。）
##   ② 值级：把面板**真的建出来**，遍历所有 stylebox / 字体色的**实际取值**，
##      逐个断言 ∈ 48 色板（走 `GameConstants.palette_contains()`）。
##   ③ 常量表：`GameConstants.ui_colors_not_in_palette()` 必须为空
##      （覆盖新登记进去的 `UI_CHOICE_*`）。
##   ④ 结构性护栏：desc 盒不得与「选择」按钮 rect 重叠；desc 文本 ≤ 3 行；
##      遮罩存在、铺满、`MOUSE_FILTER_IGNORE`、且连续 `_build()` 两次不会重复或消失。
##
## ⚠️ 与 `capture_choice_panel` 的分工（**不要混用**）：
##   | 工具                     | 轴   | 需要窗口 | 何时跑             |
##   |--------------------------|------|----------|--------------------|
##   | `verify_choice_panel`    | 配色 | 否       | 每次回归（自动）   |
##   | `capture_choice_panel`   | 画面 | **是**   | 改视觉后手动抓图   |
##   所以 `capture_choice_panel.tscn` **故意不叫** `verify_*`：headless 回归跑不了它，
##   改名会让整条回归挂掉。
extends Node2D

const SRC_PATHS: Array[String] = [
	"res://scripts/ui/choice_panel.gd",
	"res://scripts/run/level_scene.gd",
]

## 禁止出现在 `choice_panel.gd` 里的写法（裸色值构造）
const FORBIDDEN: Array[String] = [
	"\\bColor8?\\s*\\(",   ## Color(...) / Color8(...)
	"Color\\.html",        ## Color.html("1E232B")
]

var _fail: int = 0
var _skip: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	_run()


func _run() -> void:
	print("===== ChoicePanel 配色断言（headless）=====")

	# ---- ① 源码级：不得出现裸色值字面量 ----
	# 阶段 11 收尾（team-lead 裁定）：扫描范围扩到 level_scene.gd —— 之前 ESC 确认框遮罩
	# 写了硬编码 Color(0,0,0,0.55) 正是漏在 choice_panel.gd 扫描外的下游文件。
	# 这里只保证「**所有手工建 UI 的生产代码**」都被扫；UITheme 走主题的不需要。
	var all_hits: Array[String] = []
	var all_lit_uses: int = 0
	for _src_path in SRC_PATHS:
		var src := FileAccess.get_file_as_string(_src_path)
		if src.is_empty():
			_skip += 1
			print("[SKIP] 读不到 %s（导出包裁剪了源码？）—— 源码级断言跳过，**不算通过**" % _src_path)
			continue
		var hits := _scan_forbidden(src)
		print("[Src] %s · %d 字符 · 禁止写法命中 %d 处" % [_src_path, src.length(), hits.size()])
		for h in hits:
			print("       · %s" % h)
		all_hits.append_array(hits)
		all_lit_uses += src.count("GameConstants.")
	_ok("① 源码级：%d 个文件无裸 Color(...) 字面量（命中 %d）"
			% [SRC_PATHS.size(), all_hits.size()], all_hits.is_empty())
	_ok("① 源码级：色值确实来自 GameConstants（合计引用 %d 处 ≥ 10）" % all_lit_uses,
		all_lit_uses >= 10)

	# ---- ③ 常量表全部在色板内 ----
	var bad := GameConstants.ui_colors_not_in_palette()
	_ok("③ GameConstants.ui_colors_not_in_palette() 为空（越界：%s）" % str(bad),
		bad.is_empty())

	# ---- ② / ④ 把面板真建出来 ----
	var panel := ChoicePanel.new()
	panel.size = Vector2(1920, 1080)
	add_child(panel)
	# 强制三张卡各占一个分类 ⇒ 三类描边都进入取值检查
	var opts: Array[Dictionary] = [
		RunePool.get_option("fury"),    # attack
		RunePool.get_option("bulwark"), # defense
		RunePool.get_option("greed"),   # resource
	]
	for o in opts:
		if o.is_empty():
			_ok("三分类样例选项可用（%s）" % str(o), false)
	panel.show_choices(opts, RunBuffSystem.new())
	await _frames(3)

	_check_values(panel)
	_check_structure(panel)
	await _check_desc_metrics()

	# 连续 _build() 两次：遮罩不得重复/丢失（`_build()` 的清理循环必须跳过它）
	panel.show_choices(opts, RunBuffSystem.new())
	await _frames(2)
	var dim := 0
	for c in panel.get_children():
		if c is ColorRect and c.name == StringName("Dim"):
			dim += 1
	_ok("④ 连续 _build() 两次后遮罩仍恰好 1 只（实测 %d）" % dim, dim == 1)

	print("===== 结果：%d 项失败（%d 项跳过）=====" % [_fail, _skip])
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# ① 源码扫描
# =============================================================================

func _scan_forbidden(src: String) -> Array[String]:
	var hits: Array[String] = []
	# ⚠️ 必须先剥掉注释再扫：本文件的类头注释里**故意**写了 `Color(...)` 作为反例，
	#    不剥的话断言会被自己的文档误伤（实测踩到过）。
	var re_c := RegEx.new()
	re_c.compile("#.*")
	var lines := src.split("\n")
	for i in lines.size():
		var code := re_c.sub(lines[i], "", true)
		for p in FORBIDDEN:
			var re := RegEx.new()
			if re.compile(p) != OK:
				hits.append("(正则编译失败：%s)" % p)
				continue
			if re.search(code) != null:
				hits.append("L%d: %s" % [i + 1, code.strip_edges()])
	return hits


# =============================================================================
# ② 值级：遍历面板**实际用到的**每个色值
# =============================================================================

func _check_values(panel: ChoicePanel) -> void:
	# 逐条记录（**不按色值去重**）：同一个色值在不同角色下出现也算两条，
	# 否则「按钮 hover 底 == 资源卡描边」这类同色异用会被悄悄合并、看不清全貌。
	var names: Array[String] = []
	var cols: Array[Color] = []
	for card in panel.get_children():
		if not (card is Control) or card.name == StringName("Dim"):
			continue
		var p := card as Control
		var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			names.append("%s.panel.bg" % p.name)
			cols.append(sb.bg_color)
			names.append("%s.panel.border" % p.name)
			cols.append(sb.border_color)
			_ok("卡圆角 = 0（像素风铁律；%s）" % p.name, sb.corner_radius_top_left == 0)
		for k in p.get_children():
			if k is ColorRect:
				names.append("TopHighlight")
				cols.append((k as ColorRect).color)
			elif k is Label:
				names.append("Label(%s@%d).font" % [(k as Label).text.substr(0, 6),
					(k as Label).get_theme_font_size("font_size")])
				cols.append(k.get_theme_color("font_color"))
			elif k is Button:
				var b := k as Button
				for st in ["normal", "hover", "pressed", "focus"]:
					var bs := b.get_theme_stylebox(st) as StyleBoxFlat
					if bs != null:
						names.append("Btn.%s.bg" % st)
						cols.append(bs.bg_color)
						names.append("Btn.%s.border" % st)
						cols.append(bs.border_color)
						_ok("按钮 %s 圆角 = 0" % st, bs.corner_radius_top_left == 0)
				for ck in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
					names.append("Btn.%s" % ck)
					cols.append(b.get_theme_color(ck))
	# 遮罩：RGB 必须在色板内（alpha 是 0.55，比较时按不透明比对，与 UI_PANEL_BG_ALPHA 同口径）
	for c in panel.get_children():
		if c is ColorRect and c.name == StringName("Dim"):
			var mc := (c as ColorRect).color
			names.append("Mask(%s @%.2f)" % [mc.to_html(false), mc.a])
			cols.append(Color(mc.r, mc.g, mc.b, 1.0))

	var uniq: Array[String] = []
	var bad: Array[String] = []
	for i in names.size():
		var hx := cols[i].to_html(false)
		if not uniq.has(hx):
			uniq.append(hx)
		if not GameConstants.palette_contains(cols[i]):
			bad.append("%s=%s" % [names[i], hx])
	print("[Value] 面板实际用到 %d 处色值（去重 %d 个：%s）"
		% [names.size(), uniq.size(), ", ".join(uniq)])
	for i in names.size():
		print("       · %-24s %s" % [names[i], cols[i].to_html(false)])
	_ok("② 值级：面板实际用到的全部色值 ∈ 48 色板（越界 %d 处：%s）"
		% [bad.size(), str(bad)], bad.is_empty())


# =============================================================================
# ④ 结构性护栏
# =============================================================================

func _check_structure(panel: ChoicePanel) -> void:
	var desc_top := ChoicePanel.DESC_POS.y
	var desc_bottom := desc_top + ChoicePanel.DESC_BOX_H
	print("[Geom] desc 盒 y∈[%.0f,%.0f] · 按钮 y∈[%.0f,%.0f]"
		% [desc_top, desc_bottom, ChoicePanel.BTN_POS.y, ChoicePanel.BTN_POS.y + ChoicePanel.BTN_H])
	_ok("④ desc 盒不与「选择」按钮 rect 重叠（%.0f ≤ %.0f）"
			% [desc_bottom, ChoicePanel.BTN_POS.y],
		desc_bottom <= ChoicePanel.BTN_POS.y)
	_ok("④ desc 可用高 ≥ 3 行（%d ≥ 42）" % ChoicePanel.DESC_BOX_H,
		ChoicePanel.DESC_BOX_H >= 42)

	# 遮罩：存在 / 置底 / 铺满 / 不吞鼠标
	var mask: ColorRect = null
	var idx := -1
	for i in panel.get_child_count():
		var c := panel.get_child(i)
		if c is ColorRect and c.name == StringName("Dim"):
			mask = c as ColorRect
			idx = i
			break
	if mask == null:
		_ok("④ 全屏遮罩存在", false)
		return
	_ok("④ 遮罩在 0 号位（卡片之下，实测 index=%d）" % idx, idx == 0)
	_ok("④ 遮罩铺满视口（rect %s）" % str(mask.get_global_rect()),
		mask.get_global_rect().size.is_equal_approx(Vector2(1920, 1080)))
	_ok("④ 遮罩 MOUSE_FILTER_IGNORE（不吞鼠标，实测 %d）" % mask.mouse_filter,
		mask.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var mask_a := mask.color.a
	_ok("④ 遮罩不透明度 = UI_CHOICE_MASK_ALPHA（%.2f vs %.2f）"
			% [mask_a, GameConstants.UI_CHOICE_MASK_ALPHA],
		absf(mask_a - GameConstants.UI_CHOICE_MASK_ALPHA) < 0.001)


## desc 行数度量。headless 下若 TextServer 不提供度量（行数恒 0），**明确 SKIP**，
## 不静默当通过 —— 这类「测试自己坏了却显示绿色」是本项目反复踩过的坑。
func _check_desc_metrics() -> void:
	var host := Control.new()
	add_child(host)
	var measured := 0
	var worst_lines := 0
	var worst_id := ""
	var over: Array[String] = []
	for opt in RunePool.OPTIONS:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", ChoicePanel.DESC_FONT_SIZE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(ChoicePanel.DESC_BOX_W, ChoicePanel.DESC_BOX_H)
		l.text = str(opt["desc"])
		host.add_child(l)
		l.size = Vector2(ChoicePanel.DESC_BOX_W, ChoicePanel.DESC_BOX_H)
		var lines := l.get_line_count()
		if lines > 0:
			measured += 1
			if lines > worst_lines:
				worst_lines = lines
				worst_id = str(opt["id"])
			# 行高按「盒高 ÷ 可见行数」不可靠，改用 font.get_height()
			var f := l.get_theme_font("font")
			var need := float(lines) * (f.get_height(ChoicePanel.DESC_FONT_SIZE) if f != null else 0.0)
			if need > float(ChoicePanel.BTN_POS.y - ChoicePanel.DESC_POS.y):
				over.append("%s(%d行/%.0fpx)" % [opt["id"], lines, need])
	if measured == 0:
		_skip += 1
		print("[SKIP] headless 下 Label.get_line_count() 恒 0 ⇒ desc 行数断言跳过（**不算通过**）")
	else:
		print("[Text] 量到 %d/%d 条 desc · 最多 %d 行（%s）" % [measured, RunePool.OPTIONS.size(),
			worst_lines, worst_id])
		_ok("④ 全部 desc ≤ 3 行（最多 %d 行的 %s）" % [worst_lines, worst_id], worst_lines <= 3)
		_ok("④ 全部 desc 所需高度 ≤ desc 可用区 44px（越界 %s）" % str(over), over.is_empty())
	host.queue_free()


# =============================================================================

func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
