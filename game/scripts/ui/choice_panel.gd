## 局内三选一面板（任务 4.2 · class_name）
##
## GDD 0.4 节 4.1/4.2：每升 1 级弹出 3 张选项卡（从池中不重复抽取）；
## 点选后发 EventBus.run_buff_selected(buff_id, stacks) 并收起。
## 由 RunProgression.on_level_up 触发、战斗层实例化挂载。
##
## ---------------------------------------------------------------------------
## 阶段 11（2026-09-18）真渲染视觉审计后的修复
## 审计报告：`deliverables/gstack/design-visual-audit-choice-panel-2026-09-18.md`
## （方法：真渲染抓图 + rect/font 诊断 + 纯标准库像素反推，两条独立轴互证）
## ---------------------------------------------------------------------------
## 审计结论：几何 / 文字 / 点击全部正确（三卡居中 Δx=0.0px、间距 16px、无越界、
## 全 15 条 desc 不溢出、按钮可点且真实生效）；**唯一实质缺陷是配色**。
## 本文件按裁定做了 5 处修改：
##   ① 7 个硬编码 `Color(...)` 字面量 → `GameConstants.UI_CHOICE_*`（全部色板内色），
##      并在 `GameConstants.ui_colors_not_in_palette()` 登记 ⇒ 纳入 `self_check`。
##   ② 卡填充 `#171921` → `#1E232B`（§1.3「面板底」）+ 卡顶 1px 高光 `#4E5866`（§5.2）。
##      依据：原填充对**纯黑**也只有 1.20:1 —— 「看不清卡片」的根因是**底色本身太暗**，
##      不是背景太花（实测卡框内背景只有 2 种颜色、敌方像素 0 个）。**抬填充不可被遮罩替代**。
##   ③ 新增全屏遮罩 `#0B0D10` @ 0.55（常驻一只、每次 `move_child(0)` 压到卡片之下、
##      `MOUSE_FILTER_IGNORE` 不吞鼠标）。
##      ⚠️ 遮罩的价值是「模态感 + 压掉背景的运动与光斑」，**不是提高稿面亮度** ——
##      实测叠 45% 纯黑后「卡面 vs 地面」只从 1.03:1 升到 1.09:1。**别因为「对比度没变好」删掉它。**
##      ⚠️ **标称 alpha ≠ 线性不透明度**（2026-09-18 真渲染实测，调参前必读）：
##      `ColorRect` 在 **linear 空间**混合，`UI_CHOICE_MASK_ALPHA = 0.55` 实际只把 sRGB 背景
##      压到约 **60~70%**（实测 `#191C24 → #111419`、`#292933 → #181920`，即暗化约 **30~40%**，
##      而非 55%）。**按 sRGB 直觉推算会白调**：想让背景再暗一档，alpha 需要提到 **0.70+**。
##      当前 0.55 是 team-lead 裁定值（配合卡面抬到 `#1E232B`，模态信号已建立）；
##      「够不够暗」列为**试玩观测点**，不在此处擅自加码。
##   ④ 「选择」按钮提亮到金 `#D9A521`：原按钮底对卡面 1.11:1、描边对按钮底 1.56:1，
##      都低于 WCAG「非文本 UI 组件边界 ≥ 3:1」。
##   ⑤ desc 盒高 50 → 44（= desc 顶 62 到按钮顶 106 的**真实可用区**）。
##
## ⚠️⚠️ 本类**不走 `UITheme` 的主题变体**（手工建卡），因此它的色值必须自己走常量。
##     它是全项目唯一这样的 UI，也是**最容易重新引入硬编码色值**的地方 ——
##     改本文件前后都请跑 `res://tools/verify_choice_panel.tscn`（源码级 + 值级双重断言）。
class_name ChoicePanel
extends Control

signal choice_made(option_id: String)

# ---------------------------------------------------------------------------
# 布局常量（与 `tools/capture_choice_panel.gd` 的诊断口径一一对应）
# ---------------------------------------------------------------------------

const CARD_W: int = 220
const CARD_H: int = 140
const CARD_GAP: int = 16
const CARD_BORDER_W: int = 2
## 卡顶高光条高（§5.2「顶部 1px 高光」；StyleBoxFlat 不支持单边异色描边，
## 故由场景层放一根 ColorRect 实现 —— 见 `ui_theme.gd` 的「已知限制」注）
const CARD_HIGHLIGHT_H: int = 1
## desc 盒高。= 62（desc 顶）→ 106（按钮顶）的真实可用区，44px = 3 行 × 14px + 2px。
## **不是**越大越好：Label 不裁剪（`clip_text` 默认 false），盒子改大既不会多显示一行、
## 又会与按钮 rect 重叠。真正的结构性护栏是 `verify_choice_panel` 的「desc ≤ 3 行」断言。
const DESC_BOX_H: int = 44
const DESC_BOX_W: int = CARD_W - 24
const DESC_POS: Vector2 = Vector2(12, 62)
const TITLE_FONT_SIZE: int = 16
const CAT_FONT_SIZE: int = 11
const DESC_FONT_SIZE: int = 12
const BTN_W: int = 64
const BTN_H: int = 26
## 按钮右下角内缩 12px：`card_w - 64 - 12 = 144`，与原 `card_w - 76` 完全等价（不改布局，只改写法）
const BTN_POS: Vector2 = Vector2(CARD_W - BTN_W - 12, 106)

var _options: Array[Dictionary] = []
var _buff_system: RunBuffSystem = null
## 全屏遮罩（常驻；见类头说明 ③）。`_build()` / `_on_pick()` 的清理循环必须跳过它。
var _mask: ColorRect = null
## 标题字体（规范 §5.1：标题走 ChillBitmap-16px）。`null` = 回退主题默认字体（Cubic-11）。
static var _title_font: Font = null
static var _title_font_probed: bool = false


## 弹出三选一（战斗层调用）：options 由 RunePool.get_choices 给出
func show_choices(options: Array[Dictionary], buff_system: RunBuffSystem) -> void:
	_options = options
	_buff_system = buff_system
	_build()


func _build() -> void:
	# 清掉上一次的卡片 —— **跳过遮罩**（遮罩常驻，见 `_ensure_mask`）
	for child in get_children():
		if child != _mask:
			child.queue_free()
	_ensure_mask()

	var total_w := CARD_W * _options.size() + CARD_GAP * (_options.size() - 1)
	var start_x := (size.x - total_w) / 2.0
	for i in _options.size():
		var opt: Dictionary = _options[i]
		var card := Panel.new()
		card.custom_minimum_size = Vector2(CARD_W, CARD_H)
		card.position = Vector2(start_x + i * (CARD_W + CARD_GAP), (size.y - CARD_H) / 2.0)
		card.size = Vector2(CARD_W, CARD_H)
		card.add_theme_stylebox_override("panel", _style(opt["cat"]))
		add_child(card)
		_add_card_highlight(card)
		var name_l := Label.new()
		name_l.text = str(opt["name"])
		name_l.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
		var title_font := _resolve_title_font()
		if title_font != null:
			name_l.add_theme_font_override("font", title_font)
		name_l.add_theme_color_override("font_color", GameConstants.UI_CHOICE_TITLE)
		name_l.position = Vector2(12, 12)
		card.add_child(name_l)
		var cat_l := Label.new()
		cat_l.text = "【%s】" % _cat_label(str(opt["cat"]))
		cat_l.add_theme_font_size_override("font_size", CAT_FONT_SIZE)
		cat_l.add_theme_color_override("font_color", GameConstants.UI_CHOICE_CAT)
		cat_l.position = Vector2(12, 40)
		card.add_child(cat_l)
		var desc_l := Label.new()
		desc_l.text = str(opt["desc"])
		desc_l.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
		desc_l.add_theme_color_override("font_color", GameConstants.UI_CHOICE_DESC)
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_l.custom_minimum_size = Vector2(DESC_BOX_W, DESC_BOX_H)
		desc_l.position = DESC_POS
		card.add_child(desc_l)
		var btn := Button.new()
		btn.text = "选择"
		btn.position = BTN_POS
		btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
		_add_button_style(btn)
		card.add_child(btn)
		var opt_id: String = str(opt["id"])
		btn.pressed.connect(func() -> void: _on_pick(opt_id))


## 全屏遮罩：常驻一只，每次 `_build()` 重新铺满并压到 0 号位（卡片之下）。
##
## 放在 `_build()` 而不是 `_ready()` 里，是因为**尺寸的时点**：`_ready()` 触发于
## `add_child` 期间，此刻面板自己的 `size` 还是 (0,0)（见 `level_scene._show_choice_panel`
## 的顺序说明）。而 `PRESET_FULL_RECT` 会把 offsets 归零、anchors 拉成 0..1，
## 因此遮罩会**自动跟随面板尺寸**——放在 `_build()` 只是让「建立时刻」也落在尺寸就绪之后，
## 便于将来有人改成带像素偏移的遮罩。
func _ensure_mask() -> void:
	if _mask == null or not is_instance_valid(_mask):
		_mask = ColorRect.new()
		_mask.name = "Dim"
		# ⚠️ 不要写 `Color(...)` 字面量：`verify_choice_panel` 的源码级断言会直接报红。
		#    色值一律来自 GameConstants 常量，alpha 单独从常量取（与 UI_PANEL_BG_ALPHA 同口径）。
		var dim := GameConstants.UI_CHOICE_MASK
		dim.a = GameConstants.UI_CHOICE_MASK_ALPHA
		_mask.color = dim
		# 不吞鼠标：遮罩只负责压暗，点击要能落到卡片按钮上
		_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_mask)
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_child(_mask, 0)


## 卡顶 1px 高光（§5.2）：让卡片读起来是「一块面板」而不是「一圈线」。
func _add_card_highlight(card: Panel) -> void:
	var hl := ColorRect.new()
	hl.name = "TopHighlight"
	hl.color = GameConstants.UI_CHOICE_CARD_HIGHLIGHT
	hl.position = Vector2(CARD_BORDER_W, CARD_BORDER_W)
	hl.size = Vector2(CARD_W - CARD_BORDER_W * 2, CARD_HIGHLIGHT_H)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hl)


func _on_pick(option_id: String) -> void:
	if _buff_system != null:
		_buff_system.apply_option(option_id)
	EventBus.run_buff_selected.emit(option_id, _buff_system.get_stacks(option_id) if _buff_system != null else 1)
	choice_made.emit(option_id)
	visible = false
	for child in get_children():
		if child != _mask:
			child.queue_free()


func _cat_label(cat: String) -> String:
	match cat:
		"attack": return "攻击"
		"defense": return "防御"
		"resource": return "资源"
	return cat


## 卡片样式：填充满铺 + 2px 分类描边 + 圆角 0（像素风铁律）。
## 描边取三个语义色系的**辉光阶**（同类卡片视觉等重），对遮罩后地面 5.47 / 6.97 / 13.8，
## 全部 ≥ 3:1 —— 在当前这套极暗色板里，**描边是卡片唯一的界定手段，不要削弱它**。
func _style(cat: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GameConstants.UI_CHOICE_CARD_BG
	sb.set_border_width_all(CARD_BORDER_W)
	sb.border_color = GameConstants.UI_PANEL_BORDER
	match cat:
		"attack":
			sb.border_color = GameConstants.UI_CHOICE_BORDER_ATTACK
		"defense":
			sb.border_color = GameConstants.UI_CHOICE_BORDER_DEFENSE
		"resource":
			sb.border_color = GameConstants.UI_CHOICE_BORDER_RESOURCE
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	return sb


## 「选择」按钮三态：金底 + 1px 深描边（像素风「crisp 1px dark outline」）。
## 对比度（真渲染实测）：按钮底 vs 卡面 7.07:1、按钮字 vs 按钮底 8.67:1、
## 描边 vs 按钮底 8.67:1 —— 全部 ≥ 3:1（非文本组件）/ ≥ 4.5:1（文字）。
func _add_button_style(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal",
		_btn_style(GameConstants.UI_CHOICE_BTN_BG, GameConstants.UI_CHOICE_BTN_BORDER, 1))
	btn.add_theme_stylebox_override("hover",
		_btn_style(GameConstants.UI_CHOICE_BTN_BG_HOVER, GameConstants.UI_CHOICE_BTN_BORDER, 1))
	# Pressed 用「更粗的深描边」表达下沉，而不是把底色压暗 ——
	# 压暗会掉到 2.96:1（低于 3:1 阈值），加粗描边则保持 7.07:1
	btn.add_theme_stylebox_override("pressed",
		_btn_style(GameConstants.UI_CHOICE_BTN_BG, GameConstants.UI_CHOICE_BTN_PRESSED_BORDER, 2))
	btn.add_theme_stylebox_override("focus",
		_btn_style(GameConstants.UI_CHOICE_BTN_BG_HOVER, GameConstants.UI_CHOICE_BTN_BORDER, 1))
	btn.add_theme_color_override("font_color", GameConstants.UI_CHOICE_BTN_TEXT)
	btn.add_theme_color_override("font_hover_color", GameConstants.UI_CHOICE_BTN_TEXT)
	btn.add_theme_color_override("font_pressed_color", GameConstants.UI_CHOICE_BTN_TEXT)
	btn.add_theme_color_override("font_focus_color", GameConstants.UI_CHOICE_BTN_TEXT)


func _btn_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	return sb


## 解析标题字体：规范 §5.1 要求 16px 标题用 ChillBitmap-16px。
## ⚠️ **必须实测缺字**：点阵字体对 CJK 覆盖不全时，缺字会渲染成豆腐块 —— 比「字体不对」更糟。
## 所以这里逐个抽查**全部选项名**的每个字形，全都有才启用；
## 任一缺字 ⇒ 回退主题默认字体（Cubic-11）并 `push_warning` 一次，**不阻断**。
## 抽查结果写进 `tools/capture_choice_panel.gd` 的诊断输出（窗口化抓图时可见）。
static func _resolve_title_font() -> Font:
	if _title_font_probed:
		return _title_font
	_title_font_probed = true
	if not ResourceLoader.exists(GameConstants.UI_FONT_CHILL_PATH):
		push_warning("[ChoicePanel] 找不到标题字体 %s，回退主题默认字体"
			% GameConstants.UI_FONT_CHILL_PATH)
		return null
	var f := ResourceLoader.load(GameConstants.UI_FONT_CHILL_PATH) as FontFile
	if f == null:
		push_warning("[ChoicePanel] 标题字体加载失败，回退主题默认字体")
		return null
	for opt in RunePool.OPTIONS:
		for ch in str(opt["name"]):
			if not f.has_char(ch.unicode_at(0)):
				push_warning("[ChoicePanel] ChillBitmap-16px 缺字形『%s』⇒ 标题整体回退主题默认字体"
					% ch)
				return null
	_title_font = f
	return _title_font


## 供诊断工具读取：标题字体最终解析结果（"ChillBitmap-16px" / "主题默认(Cubic-11)"）。
static func title_font_report() -> Dictionary:
	var f := _resolve_title_font()
	return {
		"used": f.get_font_name() if f != null else "(theme default)",
		"chillbitmap_usable": f != null,
	}
