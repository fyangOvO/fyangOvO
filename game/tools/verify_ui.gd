## UI 框架与主题实测（任务 1.6 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_ui.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围：
##   A. 常量自洽：48 色板 = 43 已定义色；UI 颜色常量全部取自色板
##   B. 主题构建：build() 返回 Theme；面板 / 按钮 / 进度条 / 输入框样式齐全
##   B2. theme.tres 产物：生成器落盘文件存在、可加载、关键项齐全、与代码构建对齐、
##       project.godot 已注册 gui/theme/custom
##   C. 字体：ChillBitmap-16px 挂默认字体与标题变体；
##          抗锯齿 / hinting / 子像素定位全部关闭；默认字号 12、标题 18
##          （2026-09-30 全局换字：细体 Cubic_11 → 粗体 ChillBitmap_16）
##   D. 像素铁律：全部 StyleBoxFlat 圆角 = 0；描边 1px；底色与描边色（RGB）均取自色板
##   E. 窗口挂载：apply_to_window 不崩溃且返回 Theme（项目默认主题才是权威机制）
##   F. 冒烟：真实 Button / Label 在项目默认主题下解析出主题样式与字体
extends Node

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== UI 框架与主题实测 =====")
	await _test_constants()
	await _test_build()
	await _test_theme_artifact()
	await _test_fonts()
	await _test_pixel_rules()
	await _test_apply_window()
	await _test_smoke()
	_finish()


# =============================================================================
# A. 常量自洽
# =============================================================================

func _test_constants() -> void:
	print("--- A. 色板与 UI 常量 ---")
	# 阶段 11 收尾：DBCC85（暖金）入中性基底；B5-2 占用 D 组 2 槽（深渊 / 塔）⇒ 46 已定义 + 2 预留 = 48
	_ok("48 色板已定义色 = %d（A11+B28+C5+D2）" % GameConstants.PALETTE_DEFINED_COUNT,
		GameConstants.PALETTE_ALL.size() == GameConstants.PALETTE_DEFINED_COUNT)
	_ok("PALETTE_NEUTRAL = 11 色", GameConstants.PALETTE_NEUTRAL.size() == 11)
	_ok("PALETTE_ACCENT = 28 色（7 系 × 4）", GameConstants.PALETTE_ACCENT.size() == 28)
	_ok("PALETTE_RARITY_SEMANTIC = 5 色", GameConstants.PALETTE_RARITY_SEMANTIC.size() == 5)
	var bad := GameConstants.ui_colors_not_in_palette()
	_ok("UI 颜色常量全部取自 48 色板", bad.is_empty())
	if not bad.is_empty():
		_info("越界：%s" % ", ".join(bad))
	_ok("UI_FONT_SIZES 全为整数像素尺寸", _all_int_font_sizes())
	_ok("面板底色 = 0B0D10 / 描边 = 3A424F",
		GameConstants.UI_PANEL_BG == Color("0B0D10")
		and GameConstants.UI_PANEL_BORDER == Color("3A424F"))


func _all_int_font_sizes() -> bool:
	for s in GameConstants.UI_FONT_SIZES:
		if s <= 0 or s % 1 != 0:
			return false
	return true


# =============================================================================
# B. 主题构建
# =============================================================================

func _test_build() -> void:
	print("--- B. 主题构建 ---")
	var t := UITheme.build()
	_ok("build() 返回 Theme", t != null)
	if t == null:
		_finish()
		return
	_ok("默认字号 = 12px", t.default_font_size == 12)
	_ok("面板样式（PanelContainer/panel）存在", t.has_stylebox(&"panel", "PanelContainer"))
	_ok("按钮 4 态样式齐全",
		t.has_stylebox(&"normal", "Button")
		and t.has_stylebox(&"hover", "Button")
		and t.has_stylebox(&"pressed", "Button")
		and t.has_stylebox(&"disabled", "Button"))
	# 2026-09-30：Button 三态改由金色九宫格（`btn_gold.png`）承载 ⇒ 必须是 StyleBoxTexture。
	# 素材缺失才回退 StyleBoxFlat（安全降级）。
	_ok("按钮 normal = 金色九宫格 StyleBoxTexture（btn_gold 已接管）",
		t.get_stylebox(&"normal", "Button") is StyleBoxTexture)
	_ok("进度条 background/fill 样式存在",
		t.has_stylebox(&"background", "ProgressBar")
		and t.has_stylebox(&"fill", "ProgressBar"))
	_ok("输入框 normal/focus 样式存在",
		t.has_stylebox(&"normal", "LineEdit")
		and t.has_stylebox(&"focus", "LineEdit"))
	_ok("提示面板 TooltipPanel 样式存在", t.has_stylebox(&"panel", "TooltipPanel"))
	_ok("标题变体 TitleLabel 字号 = 18px",
		t.get_font_size(&"font_size", "TitleLabel") == 18)


# =============================================================================
# B2. theme.tres 产物与项目注册
# =============================================================================

func _test_theme_artifact() -> void:
	print("--- B2. theme.tres 产物与项目默认主题注册 ---")
	var path := "res://scenes/ui/theme/theme.tres"
	_ok("theme.tres 存在", ResourceLoader.exists(path))
	var res: Resource = load(path)
	_ok("theme.tres 可加载为 Theme", res is Theme)
	if res is Theme:
		var lt := res as Theme
		_ok("产物：默认字号 12", lt.default_font_size == 12)
		_ok("产物：面板 / 按钮 / 进度条样式齐全",
			lt.has_stylebox(&"panel", "PanelContainer")
			and lt.has_stylebox(&"normal", "Button")
			and lt.has_stylebox(&"fill", "ProgressBar"))
		_ok("产物：标题字体已挂（ChillBitmap-16px）",
			lt.get_font(&"font", "TitleLabel") != null)
	_ok("project.godot 已注册 gui/theme/custom = theme.tres",
		ProjectSettings.get_setting("gui/theme/custom") == path)
	var code_t := UITheme.build()
	var loaded_t: Theme = load(path) if ResourceLoader.exists(path) else null
	_ok("产物与代码构建默认字号一致（生成器未过期）",
		loaded_t != null and loaded_t.default_font_size == code_t.default_font_size)
	# ⚠️ 2026-09-30 復盤：只比字號**抓不到**「改了样式忘了重跑生成器」——
	#    本批把 Button 换成金九宫格 StyleBoxTexture 却没重生成 theme.tres，
	#    字號一致 ⇒ 旧断言全绿，游戏里按钮毫无变化。必须比**型别**。
	if loaded_t != null:
		var want_sb := code_t.get_stylebox(&"normal", "Button")
		var got_sb := loaded_t.get_stylebox(&"normal", "Button")
		_ok("产物与代码 Button/normal 型别一致（生成器未过期）",
			want_sb != null and got_sb != null
			and want_sb.get_class() == got_sb.get_class())


# =============================================================================
# C. 字体
# =============================================================================

func _test_fonts() -> void:
	print("--- C. 字体与像素设置 ---")
	var t := UITheme.build()
	var body: Font = t.default_font
	var title: Font = t.get_font(&"font", "TitleLabel")
	_ok("默认字体已挂载（Cubic-11）", body != null)
	_ok("标题字体已挂载（ChillBitmap-16px）", title != null)
	if body is FontFile:
		var b := body as FontFile
		_ok("正文：抗锯齿关闭", b.antialiasing == TextServer.FONT_ANTIALIASING_NONE)
		_ok("正文：hinting 关闭", b.hinting == 0) # FONT_HINTING_NONE 未暴露，比较枚举值 0
		_ok("正文：子像素定位关闭", b.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED)
		_ok("正文：oversampling = 0", is_equal_approx(b.oversampling, 0.0))
	else:
		_info("正文非 FontFile（回退默认字体），跳过像素设置断言")
	if title is FontFile:
		var tf := title as FontFile
		_ok("标题：抗锯齿关闭", tf.antialiasing == TextServer.FONT_ANTIALIASING_NONE)
		_ok("标题：hinting 关闭", tf.hinting == 0) # FONT_HINTING_NONE 未暴露，比较枚举值 0
	else:
		_info("标题非 FontFile（回退默认字体），跳过像素设置断言")
	# 字体文件本身必须真实存在（资源路径有效）
	_ok("Cubic-11 字体文件存在", ResourceLoader.exists(GameConstants.UI_FONT_CUBIC11_PATH))
	_ok("ChillBitmap-16px 字体文件存在", ResourceLoader.exists(GameConstants.UI_FONT_CHILL_PATH))


# =============================================================================
# D. 像素铁律
# =============================================================================

func _test_pixel_rules() -> void:
	print("--- D. 样式像素铁律（圆角 0 / 描边 1px / 色值全在色板）---")
	var t := UITheme.build()
	var types := [&"Panel", &"PanelContainer", &"Button", &"LineEdit",
		&"ProgressBar", &"TooltipPanel"]
	var checked: int = 0
	var bad_corner: PackedStringArray = []
	var bad_border_w: PackedStringArray = []
	var bad_color: PackedStringArray = []
	for typ in types:
		for name in t.get_stylebox_list(typ):
			var sb := t.get_stylebox(name, typ)
			if not (sb is StyleBoxFlat):
				continue
			checked += 1
			var f := sb as StyleBoxFlat
			if f.corner_radius_top_left != 0 or f.corner_radius_top_right != 0 \
					or f.corner_radius_bottom_left != 0 or f.corner_radius_bottom_right != 0:
				bad_corner.append("%s/%s" % [typ, name])
			# 边框宽度断言只针对「实心描边」的通用面板/按钮/进度条（1px）
			if f.border_width_left != 0 and f.border_width_left != 1:
				bad_border_w.append("%s/%s" % [typ, name])
			# 色板校验只看 RGB：alpha 是主题层维度（面板 85% / 禁用 40%），不算越界
			if not _color_in_palette_rgb(f.bg_color):
				bad_color.append("%s/%s bg=%s" % [typ, name, f.bg_color.to_html(false)])
			if not _color_in_palette_rgb(f.border_color):
				bad_color.append("%s/%s border=%s" % [typ, name, f.border_color.to_html(false)])
	# 2026-09-30：Button 五态已改为 StyleBoxTexture（本段只统计 StyleBoxFlat）⇒ 门槛 12 → 8。
	_ok("已检查 %d 个 StyleBoxFlat 样式" % checked, checked >= 8)
	_ok("全部圆角 = 0（像素风禁圆角）", bad_corner.is_empty())
	if not bad_corner.is_empty():
		_info("异常：%s" % ", ".join(bad_corner))
	_ok("描边宽度合法（0 或 1px）", bad_border_w.is_empty())
	if not bad_border_w.is_empty():
		_info("异常：%s" % ", ".join(bad_border_w))
	_ok("全部底色 / 描边色（RGB）取自 48 色板", bad_color.is_empty())
	if not bad_color.is_empty():
		_info("越界：%s" % ", ".join(bad_color))


## 色板 RGB 三通道比较（忽略 Alpha —— 透明属于样式层，不是色板维度）
func _color_in_palette_rgb(c: Color) -> bool:
	for p in GameConstants.PALETTE_ALL:
		if absf(c.r - p.r) < 0.0005 and absf(c.g - p.g) < 0.0005 and absf(c.b - p.b) < 0.0005:
			return true
	return false


# =============================================================================
# E. 窗口挂载
# =============================================================================

func _test_apply_window() -> void:
	print("--- E. 窗口挂载 ---")
	var t := UITheme.apply_to_window(get_window())
	_ok("apply_to_window 返回 Theme", t != null)
	_ok("窗口 theme 已生效", get_window().theme == t)
	_ok("重复构建幂等（无崩溃）", UITheme.build() != null)


# =============================================================================
# F. 冒烟：真实控件解析主题
# =============================================================================

func _test_smoke() -> void:
	print("--- F. 控件主题解析冒烟 ---")
	var btn := Button.new()
	btn.text = "测试按钮"
	add_child(btn)
	var lbl := Label.new()
	lbl.text = "测试正文"
	add_child(lbl)
	await get_tree().process_frame

	var sb := btn.get_theme_stylebox(&"normal")
	# 2026-09-30：项目默认主题（theme.tres）的 Button 已换成金色九宫格 ⇒ StyleBoxTexture。
	_ok("Button 解析出 normal 样式（金色九宫格 StyleBoxTexture）", sb is StyleBoxTexture)
	if sb is StyleBoxTexture:
		_ok("按钮样式带贴图（btn_gold 已挂）", (sb as StyleBoxTexture).texture != null)
	var resolved_font: Font = lbl.get_theme_font(&"font")
	_ok("Label 解析出默认字体（ChillBitmap-16px）",
		resolved_font != null and resolved_font == UITheme.build().default_font)
	var resolved_size := lbl.get_theme_font_size(&"font_size")
	_ok("Label 默认字号 = 12px", resolved_size == 12)

	btn.queue_free()
	lbl.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
