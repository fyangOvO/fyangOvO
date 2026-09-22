## 主菜单 / 角色选择面板（任务 7.1 · class_name）
##
## 纯单机单角色（战士）：主菜单显示账号概览（等级/金币/材料/声望加成），
## 按钮：开始游戏（进入局外大厅）/ 设置 / 退出。
## 数据源：SaveManager 账号数据（防御式读取，无账号则显示默认）。
## 回调注入：on_start / on_settings / on_quit（由场景或验证脚本决定去向）。
class_name MainMenuPanel
extends Control

# ── 封面佈局常量（依 gstack-designer 規範 v1.0 §1；只改數值不改結構）──────────
## 內容塊（VBoxContainer）最小尺寸。規範 §1.7/§6.1 定案 `Vector2(320, 224)`；
## 舊值 `(560, 420)` 高 420 > 視口 360 ⇒ 第三顆按鈕被切（見基線圖）。
const CONTENT_MIN_SIZE: Vector2 = Vector2(320, 224)
## 主內容 9-slice 底板（`quest_panel_9slice`）的落點尺寸。規範 §1.4 定案 320×224
## （＝ `CONTENT_MIN_SIZE`）；底板矩形落點見規範 §1.7 的 `Rect(160, 126, 320, 224)`。
## 內容內距 12px（= 8px 框 + 4px 呼吸）；素材缺失時退回 UITheme 的 StyleBoxFlat 面板。
const PANEL_CONTENT_MARGIN: int = 12
## 標題區（2026-09-22 定稿）：金色龍紋徽章底板 `title_emblem`（336×112，3:1），
## 副標題已烘焙進徽章底板。舊 `quest_banner_256x48` 2×（512×96）整版退役。
const BANNER_SIZE: Vector2 = Vector2(336, 112)
## 燙金像素標題 `title_text`（240×64）在徽章內部的落點（銘牌區域內，規範 §7.1）。
const TITLE_TEXT_RECT: Rect2 = Rect2(48, 12, 240, 64)
## 字號只用像素鐵律白名單 {11, 12, 16, 22, 32}（`GameConstants.UI_FONT_SIZES`，規範 §7.7）。
const TITLE_FONT_SIZE: int = 32
const ACCOUNT_FONT_SIZE: int = 11
const BTN_FONT_SIZE: int = 22
## 按鈕：`btn_*_128x24` **2× 整數放大** ⇒ 256×48（規範 §1.5 / §3 C6 / §7.1 白名單）。
## ⚠️ 舊值 192×48 來自 96×24 貼圖；貼圖已重導為 128×24（規範 C6：296px 的內容區裡
##    192 寬左右各空 52px，讀成「按鈕太窄」）。**改本值必須同一 commit 內改
##    `verify_ui_assets.gd` 的 `EXPECT_TEX`（6 個 btn_* → 128×24）與 `BTN_SIZE` 斷言**，
##    否則回歸立刻變紅。高度仍 48 ⇒ 內容總高仍 200，佈局不變。
const BTN_SIZE: Vector2 = Vector2(256, 48)
## 賬號信息條（`StyleBoxFlat`：底 `14171C` + 1px `3A424F`，圓角 0；規範 §1.6）
const ACCOUNT_BAR_SIZE: Vector2 = Vector2(248, 20)
## 分隔線（`divider_160x8` 1×；規範 §1.7）
const DIVIDER_SIZE: Vector2 = Vector2(160, 8)
## 垂直節奏（2026-09-22 定稿，規範 §1.2，全部落在 4px 基數上）：
## 8（頂留）+ 112（標題區）+ 8（縫）+ 224（面板）+ 8（底留）= **360** = 視口高，逐像素吻合。
## ⚠️ 副標題已烘焙進徽章底板（`title_emblem.png`），不再單獨佔一行。
const SPACER_TOP: float = 8.0
const SPACER_MID: float = 4.0
const SPACER_BTN: float = 8.0
## 標題區底 → 面板頂的呼吸。
const SPACER_BANNER: float = 8.0
const SPACER_BOTTOM: float = 8.0
## 標題字色（2026-09-22 起為 `title_text` 燙金字像素圖，此值僅作降級時用）
const TITLE_COLOR: Color = Color("F5D77A")

## 回调（可空）
var on_start: Callable = Callable()
var on_settings: Callable = Callable()
var on_quit: Callable = Callable()

var _account_label: Label = null


func _ready() -> void:
	_build_ui()
	_refresh_account()
	_build_crest()


func _build_ui() -> void:
	# ⚠️ 居中必须用 CenterContainer，**不能**只写 `set_anchors_preset(PRESET_CENTER)`：
	#    `set_anchors_preset()` 只改 anchor、**不改 offset**，控件会从屏幕中心点向右下
	#    扩展。2026-09-18 真渲染实测：内容块 rect = [P:(960,540), S:(560,420)]，
	#    块中心 x=1240 而视口中心是 960 —— 整个菜单偏右 280px（= 560/2），
	#    左半屏全空。这类问题无头测试永远看不见（它只断言「控件存在」）。
	#    CenterContainer 由父容器负责居中，不依赖 offset 计算，窗口尺寸变化也自动跟随。
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = CONTENT_MIN_SIZE
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	# 外層間距一律靠 spacer 精確控制（separator=0），避免 VBox 默認 4px 與 spacer 疊加。
	root.add_theme_constant_override("separation", 0)
	center.add_child(root)

	# 標題：`quest_banner_256x48` 2×（512×96）+ 標題文字 + **橫幅內的副標題**（素材缺失時只剩文字）
	root.add_child(_spacer(SPACER_TOP))
	root.add_child(_wrap(_make_title_banner()))

	# 橫幅底 → 面板頂 16px（規範 §3 C4）
	root.add_child(_spacer(SPACER_BANNER))

	# 主內容：帳號條 / 分隔線 / 三顆按鈕，一律放進 `quest_panel_9slice` 9-slice 內容底板
	# （規範 §1.4）。**這是實體面板節點**——舊版把 `CONTENT_MIN_SIZE` 誤當成「已落地面板」，
	# 實際只設了 VBox 最小尺寸、沒有任何底板貼圖 ⇒ 背景樹影直透到按鈕後面（T5 §3.1 修正）。
	root.add_child(_wrap(_make_content_panel(_make_panel_body())))

	# 面板底 → 屏底 16px（規範 §1.2）
	root.add_child(_spacer(SPACER_BOTTOM))


## 用 CenterContainer 包住子控件 ⇒ 讓子控件維持其 `custom_minimum_size`（不被 VBox 拉伸）。
func _wrap(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc


## 主內容 9-slice 面板（規範 §1.4）：把內容放進 PanelContainer，底板貼圖 = `quest_panel_9slice`
## （四邊邊距 8px）。素材缺失 → 不覆蓋，沿用 UITheme 的面板 StyleBoxFlat（安全降級）。
## 內容內距固定 `PANEL_CONTENT_MARGIN`（12px），使內容起點落在「8px 框 + 4px 呼吸」處。
func _make_content_panel(body: Control) -> Control:
	var pc := PanelContainer.new()
	pc.name = "ContentPanel"
	pc.custom_minimum_size = CONTENT_MIN_SIZE
	var sb := UISkin.panel_stylebox()
	if sb != null:
		sb.content_margin_left = float(PANEL_CONTENT_MARGIN)
		sb.content_margin_top = float(PANEL_CONTENT_MARGIN)
		sb.content_margin_right = float(PANEL_CONTENT_MARGIN)
		sb.content_margin_bottom = float(PANEL_CONTENT_MARGIN)
		pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(body)
	return pc


## 面板徽記（規範 §1.1 #3a / §3 C4）：`quest_marker_24`（24×24 金菱，`UISkin` 邏輯名
## `marker`）**騎在面板頂邊上、向上探 12px**，把「橫幅 → 16px 縫 → 面板」在視覺上縫成
## 一組（徽記與橫幅端飾是同一套金色菱形語言）。
##
## ⚠️ **不能寫死 y**：`ContentPanel` 的 y 是 `CenterContainer` 算出來的（不是常量），
##    寫死會在 VBox 組成變化時飄走 —— 而**無頭測試看不見**（它只斷言控件存在）。
##    所以等佈局穩定後（`await get_tree().process_frame`）用面板的 `get_global_rect()` 反推。
## ⚠️ 必須掛在**本節點**、**不能**掛 `PanelContainer`：PanelContainer 會把子節點拉滿內容區。
## ⚠️ 素材缺失 → 整塊跳過（安全降級，與 `UISkin` 契約一致）。
func _build_crest() -> void:
	var tex := UISkin.texture("marker")
	if tex == null:
		return
	await get_tree().process_frame
	var panel := find_child("ContentPanel", true, false) as Control
	if panel == null:
		return
	var crest := TextureRect.new()
	crest.name = "PanelCrest"
	crest.texture = tex
	crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_SCALE
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.size = Vector2(tex.get_width(), tex.get_height())  # 1×（24×24，整數縮放鐵律）
	add_child(crest)
	# `ContentPanel` 的 rect 是**全域**座標，本節點通常也在 (0,0)，但減掉自身全域原點
	# 才對任何掛載方式都成立。
	var rect := panel.get_global_rect()
	var origin := get_global_rect().position
	crest.position = Vector2(
		rect.get_center().x - tex.get_width() * 0.5,
		rect.position.y - tex.get_height() * 0.5) - origin
	move_child(crest, get_child_count() - 1)  # 置頂：畫在面板之上


## 面板內容：帳號信息條 / 分隔線 / 三顆按鈕。`separation=0`，間距一律由 spacer 精確控制
## （規範 §1.7：帳號條→分隔線 4px，分隔線→按鈕 8px，按鈕彼此 8px）。
func _make_panel_body() -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.name = "PanelBody"
	vb.add_theme_constant_override("separation", 0)

	# 賬號信息條：不用素材，`StyleBoxFlat` 底板（規範 §1.6）
	_account_label = _make_label("", ACCOUNT_FONT_SIZE, GameConstants.PALETTE_NEUTRAL[7])
	_account_label.custom_minimum_size = ACCOUNT_BAR_SIZE
	_account_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_account_label.add_theme_stylebox_override("normal", _account_style())
	vb.add_child(_wrap(_account_label))

	vb.add_child(_spacer(SPACER_MID))
	vb.add_child(_wrap(_make_divider()))
	vb.add_child(_spacer(SPACER_BTN))

	vb.add_child(_wrap(_make_btn("开始游戏", "gold", func() -> void:
		if on_start.is_valid():
			on_start.call())))
	vb.add_child(_spacer(SPACER_BTN))
	vb.add_child(_wrap(_make_btn("设置", "dark", func() -> void:
		if on_settings.is_valid():
			on_settings.call())))
	vb.add_child(_spacer(SPACER_BTN))
	vb.add_child(_wrap(_make_btn("退出", "dark", func() -> void:
		if on_quit.is_valid():
			on_quit.call())))
	return vb


## 標題區（2026-09-22 定稿）：金色龍紋徽章底板 + 燙金像素「七傳說」。
## 副標題已烘焙進徽章底板（`title_emblem.png` 銘牌區內）。
## 素材缺失 → 只回傳文字標題（安全降級，與 `UISkin` 契約一致）。
func _make_title_banner() -> Control:
	var box := Control.new()
	box.name = "TitleBlock"
	box.custom_minimum_size = BANNER_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var emblem_tex := UISkin.texture("title_emblem")
	var title_tex := UISkin.texture("title_text")
	if emblem_tex != null:
		var tr := TextureRect.new()
		tr.name = "Emblem"
		tr.texture = emblem_tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(tr)
	if title_tex != null:
		var tt := TextureRect.new()
		tt.name = "TitleText"
		tt.texture = title_tex
		tt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tt.stretch_mode = TextureRect.STRETCH_SCALE
		tt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tt.position = TITLE_TEXT_RECT.position
		tt.size = TITLE_TEXT_RECT.size
		box.add_child(tt)

	if emblem_tex == null and title_tex == null:
		var title := Label.new()
		title.text = "七傳說"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
		title.add_theme_color_override("font_color", TITLE_COLOR)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(title)
	return box


## 面板內分隔線（`divider_160x8` 1×）。素材缺失時回傳零高佔位（不影響佈局）。
func _make_divider() -> Control:
	var tex := UISkin.texture("divider")
	if tex == null:
		return _spacer(0.0)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = DIVIDER_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 賬號信息條底板：`StyleBoxFlat`（底 `14171C` / 1px `3A424F` / 圓角 0）
func _account_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GameConstants.UI_SLOT_BG
	sb.border_color = GameConstants.UI_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	return sb


func _make_label(text: String, fs: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", color)
	return lbl


## 按鈕：套 `UISkin` 三態皮膚（`kind` ∈ {"gold", "dark"}）。素材缺失 → 不覆蓋，
## 沿用 `UITheme` 的程序化 StyleBoxFlat 三態（安全降級）。
func _make_btn(text: String, kind: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = BTN_SIZE
	btn.add_theme_font_size_override("font_size", BTN_FONT_SIZE)
	# 文字色（規範 §1.5）：金底壓深字 `0B0D10`、藍灰底用 `UI_TEXT_BRIGHT`
	var text_col: Color = Color("0B0D10") if kind == "gold" else GameConstants.UI_TEXT_BRIGHT
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", text_col)
	btn.add_theme_color_override("font_pressed_color", text_col)
	btn.add_theme_color_override("font_focus_color", text_col)
	var boxes := UISkin.btn_styleboxes(kind)
	for state in boxes:
		btn.add_theme_stylebox_override(state, boxes[state])
	btn.pressed.connect(cb)
	return btn


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _refresh_account() -> void:
	var lv := 1
	var gold := 0
	var mats := 0
	var bonus := 0.0
	if SaveManager != null and SaveManager.has_method("get_account_data"):
		var acc: Dictionary = SaveManager.get_account_data()
		lv = int(acc.get("level", 1))
		gold = int(acc.get("gold", 0))
		mats = int(acc.get("materials", 0))
		bonus = float(acc.get("chapter_bonus", 0.0))
	if _account_label != null:
		_account_label.text = "账号 Lv.%d · 金币 %d · 魔石 %d · 章节声望加成 +%d%%" % [
			lv, gold, mats, int(bonus * 100.0)]
