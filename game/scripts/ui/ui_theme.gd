class_name UITheme
## 任务 1.6 · UI 框架与主题（美术规范 0.7 v1.6 第 5 节）
##
## 程序化构建像素风 Theme，避免手写巨型 `.tres`（改一处常量 → 重跑构建即可）。
## 遵守的铁律：
##   1. **唯一色源** —— 所有色值取自 `GameConstants` 八·五/八·六（48 色板）。
##      新增 UI 色必须先查色板（`GameConstants.palette_contains`）再落常量。
##   2. **像素字体** —— Cubic-11（正文 11px）/ ChillBitmap 16px（标题），
##      关闭抗锯齿 / hinting / 子像素定位，只允许整数尺寸（11/12/16/22/32）。
##      字体缺失时静默回退默认字体并打 `[UITheme]` 警告，不阻断启动。
##   3. **圆角一律 0** —— 像素风禁圆角（StyleBoxFlat.corner_radius_* = 0）。
##   4. UI 逻辑基准以 `project.godot` 视口为準（当前 **640×360**，`stretch=canvas_items` +
##      `aspect=keep` + `scale_mode=integer`）；挂 CanvasLayer，锚点 + 容器自适应（美术规范 2.5）；
##      本类只提供样式与字体，布局由各场景的容器完成。
##      （2026-09-21 修正：此处原写「1920×1080」，与现行视口不符，属陈旧注释。）
##
## 用法：
##   # 场景 _ready() 里调用一次（建议主场景入口做）：
##   UITheme.apply_to_window(get_window())
##   # 控件挂主题类型变体获得预设样式（.tscn 里设 theme_type_variation）：
##   #   TitleLabel —— ChillBitmap 16px 标题
##   #   BodyLabel  —— Cubic-11 11px 正文
##   #   ValueLabel —— Cubic-11 12px 数值（伤害数字 / 属性值）
##   #   TooltipPanel —— 半透明深底提示面板
##
## 已知限制（场景层处理）：
##   · 面板「顶部 1px 高光 #4E5866」：StyleBoxFlat 不支持单边异色描边，
##     由场景在面板顶部放一根 1px ColorRect 实现（色值 UI_PANEL_HIGHLIGHT）。
##   · 血条「#C42B2B→#8C1A1F 渐变」：StyleBoxFlat 不支持渐变填充，
##     由血条组件（阶段 2）用自定义绘制或 TextureProgressBar 实现。

## 主题类型变体名（控件 `theme_type_variation` 用）
const TYPE_TITLE: StringName = &"TitleLabel"
const TYPE_BODY: StringName = &"BodyLabel"
const TYPE_VALUE: StringName = &"ValueLabel"
const TYPE_MONO: StringName = &"MonoLabel"
const TYPE_TOOLTIP: StringName = &"TooltipPanel"

## 会话内缓存；资源热更后调用 build() 重建
static var _cached_theme: Theme = null


## 构建主题并挂到窗口（无缓存）。
## 返回构建出的 Theme，便于调用方直接断言。
static func apply_to_window(win: Window) -> Theme:
	var t := build()
	if win != null:
		win.theme = t
	return t


## 取主题（带会话缓存）
static func get_theme() -> Theme:
	if _cached_theme == null:
		_cached_theme = build()
	return _cached_theme


## 从头构建一份主题。幂等，可重复调用（用于验证 / 热更）。
static func build() -> Theme:
	var t := Theme.new()

	# ---- 1. 字体 ---------------------------------------------------------
	var body_font: Font = _load_font(GameConstants.UI_FONT_CUBIC11_PATH)
	var title_font: Font = _load_font(GameConstants.UI_FONT_CHILL_PATH)

	t.default_font_size = GameConstants.UI_FONT_SIZES[0] # 11px 正文
	if body_font != null:
		t.default_font = body_font
	else:
		push_warning("[UITheme] Cubic-11 未加载，正文回退默认字体（%s）"
			% GameConstants.UI_FONT_CUBIC11_PATH)

	if title_font != null:
		t.set_font(&"font", TYPE_TITLE, title_font)
		t.set_font_size(&"font_size", TYPE_TITLE, 16) # ChillBitmap 16px 标题
	else:
		push_warning("[UITheme] ChillBitmap-16px 未加载，标题回退默认字体（%s）"
			% GameConstants.UI_FONT_CHILL_PATH)

	# 数值 / 正文变体沿用默认字体，只改字号（12px 数值 / 11px 正文）
	t.set_font_size(&"font_size", TYPE_VALUE, 12)
	t.set_font_size(&"font_size", TYPE_BODY, 11)
	t.set_font_size(&"font_size", TYPE_MONO, 11)

	# ---- 2. 文本颜色 -------------------------------------------------------
	# 信息层级用「亮度差」：常规 B3BCC9 / 高亮 DCE2E8 / 禁用 6B7688
	t.set_color(&"font_color", "Label", GameConstants.COLOR_TEXT_NORMAL)
	t.set_color(&"font_color", "RichTextLabel", GameConstants.COLOR_TEXT_NORMAL)
	t.set_color(&"font_color", "Button", GameConstants.COLOR_TEXT_NORMAL)
	t.set_color(&"font_hover_color", "Button", GameConstants.COLOR_TEXT_BRIGHT)
	t.set_color(&"font_pressed_color", "Button", GameConstants.COLOR_TEXT_BRIGHT)
	t.set_color(&"font_focus_color", "Button", GameConstants.COLOR_TEXT_BRIGHT)
	t.set_color(&"font_disabled_color", "Button", GameConstants.UI_TEXT_DISABLED)
	t.set_color(&"font_color", "LineEdit", GameConstants.COLOR_TEXT_NORMAL)

	# ---- 3. 面板 -----------------------------------------------------------
	# 底 0B0D10@85% + 1px 描边 3A424F；圆角 0（顶部高光由场景层实现）
	# 【2026-09-21 裁定】此处曾一度改用一組金褐 DNF 配色（底 1a1510 / 边 8b6914）+ 2px 描边，
	# 但那组色值**不在 48 色板**、描边也非 1px ⇒ `verify_ui` D 段两条铁律断言报红，
	# 且 `theme.tres`（project.godot 实际挂载的那份）从未同步重生成 ⇒ 该改动是**未激活的死配色**。
	# 现回退为色板内的原值，恢复回归全绿；视觉零变化（游戏用的仍是 theme.tres）。
	# 【2026-09-21 T5】那组 DNF 常量本体已从 `game_constants.gd` 删除（零消费者，避免被误用）。
	# 新的 UI 皮肤由 `UISkin`（脚本层 StyleBoxTexture 覆盖）承载，不再改这里。
	t.set_stylebox(&"panel", "Panel", _flat(
		GameConstants.UI_PANEL_BG, GameConstants.UI_PANEL_BORDER, 1,
		GameConstants.UI_PANEL_BG_ALPHA))
	t.set_stylebox(&"panel", "PanelContainer", _flat(
		GameConstants.UI_PANEL_BG, GameConstants.UI_PANEL_BORDER, 1,
		GameConstants.UI_PANEL_BG_ALPHA))
	# 提示面板：更不透（0.95），仍 1px 描边
	t.set_stylebox(&"panel", TYPE_TOOLTIP, _flat(
		GameConstants.UI_PANEL_BG, GameConstants.UI_PANEL_BORDER, 1, 0.95))

	# ---- 4. 按钮三态 -------------------------------------------------------
	# Normal 1E232B / Hover 2A313B+描边高光 / Pressed 14171C+内阴影 / 禁用降透明
	t.set_stylebox(&"normal", "Button", _flat(
		GameConstants.UI_BTN_NORMAL, GameConstants.UI_BTN_BORDER, 1))
	t.set_stylebox(&"hover", "Button", _flat(
		GameConstants.UI_BTN_HOVER, GameConstants.UI_BTN_HOVER_BORDER, 1))
	t.set_stylebox(&"pressed", "Button", _flat(
		GameConstants.UI_BTN_PRESSED, GameConstants.UI_BTN_BORDER, 1,
		1.0, GameConstants.UI_PANEL_BG, 2))
	t.set_stylebox(&"focus", "Button", _flat(
		GameConstants.UI_BTN_NORMAL, GameConstants.UI_BTN_HOVER_BORDER, 1))
	t.set_stylebox(&"disabled", "Button", _flat(
		GameConstants.UI_BTN_NORMAL, GameConstants.UI_BTN_BORDER, 1,
		GameConstants.UI_BTN_DISABLED_ALPHA))

	# ---- 5. 输入框 ----------------------------------------------------------
	t.set_stylebox(&"normal", "LineEdit", _flat(
		GameConstants.UI_SLOT_BG, GameConstants.UI_BTN_BORDER, 1))
	t.set_stylebox(&"focus", "LineEdit", _flat(
		GameConstants.UI_SLOT_BG, GameConstants.UI_BTN_HOVER_BORDER, 1))
	t.set_stylebox(&"read_only", "LineEdit", _flat(
		GameConstants.UI_SLOT_BG, GameConstants.UI_BTN_BORDER, 1, 0.5))

	# ---- 6. 进度条（血条 / 经验条通用）---------------------------------------
	# 底槽 14171C + 1px 0B0D10 描边；填充 C42B2B（渐变由血条组件实现）
	t.set_stylebox(&"background", "ProgressBar", _flat(
		GameConstants.UI_HP_BAR_BG, GameConstants.UI_HP_BAR_OUTLINE, 1))
	t.set_stylebox(&"fill", "ProgressBar", _flat(
		GameConstants.UI_HP_BAR_GRADIENT_FROM, GameConstants.UI_HP_BAR_OUTLINE, 1))

	return t


# =============================================================================
# 内部工具
# =============================================================================

## 加载已导入的字体资源（带像素风导入参数），失败返回 null。
static func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	if res is FontFile:
		var ff := res as FontFile
		# 双保险：导入参数之外再强制像素设置（导入参数漂移时兜底）
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		# TextServer.FONT_HINTING_NONE 未在 GDScript 暴露，用其枚举值 0
		ff.hinting = 0
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		ff.oversampling = 0.0
		return ff
	return null


## 构造一个像素风 StyleBoxFlat：圆角一律 0。
## `alpha`：底色透明度倍率（1.0 = 不透明）；`shadow`/`shadow_size`：内阴影近似。
static func _flat(bg: Color, border: Color, border_w: int = 1,
		alpha: float = 1.0, shadow: Color = Color.TRANSPARENT,
		shadow_size: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg.r, bg.g, bg.b, bg.a * alpha)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.shadow_color = shadow
	sb.shadow_size = shadow_size
	return sb
