## 角色选择面板（步骤 2 · 2026-09-22 · class_name）
##
## 触发：首页「开始游戏」（无存档）→ 弹此面板 → 选职业 → `on_confirm(class_id)` → 建档进据点。
##
## 布局（640×360 全屏覆盖，四栏内容：职业描述 / 数值预览 / 立绘大图 / 技能展示）：
##   ┌──────────────────────────────────────────────┐
##   │  选择职业（22px 标题）                        │
##   │ ┌────────┬──────────┬──────────────────────┐ │
##   │ │ 职业列表 │ 立绘大图 │ 职业名 · 头衔         │ │
##   │ │ 战士    │ (188×250) │ 玩法定位             │ │
##   │ │ 弓箭手  │          │ 描述（自动换行）       │ │
##   │ │ 法师    │          ├──────────────────────┤ │
##   │ │        │          │ 数值预览（5 项 2 列）  │ │
##   │ │        │          ├──────────────────────┤ │
##   │ │        │          │ 技能展示（4 卡 + 描述） │ │
##   │ ├────────┴──────────┴──────────────────────┤ │
##   │ │           [返回]       [确认选择]          │ │
##   └──────────────────────────────────────────────┘
##
## 数据源：ConfigLoader.classes（data/classes/*.json）；技能展示读 ConfigLoader.skills +
## GameConstants.SKILL_ICON（与局内技能栏同源，防图标映射漂移）。
class_name CharacterSelectPanel
extends Control

## 选职业回调：`func(class_id: String) -> void`
var on_confirm: Callable = Callable()
## 返回回调：`func() -> void`
var on_cancel: Callable = Callable()

## 当前选中职业 id
var current_class_id: String = GameConstants.CLASS_DEFAULT

## 帧面板落点（视图 640×360，四周留 8）
const FRAME_RECT: Rect2 = Rect2(8, 8, 624, 344)
const FRAME_MARGIN: int = 10
## 标题区
const TITLE_RECT: Rect2 = Rect2(24, 14, 592, 24)
## 内容区（帧内）
const CONTENT_TOP: float = 46.0
const CONTENT_BOTTOM: float = 300.0
## 左列：职业按钮
const CLASS_LIST_RECT: Rect2 = Rect2(24, 52, 128, 196)
const CLASS_BTN_SIZE: Vector2 = Vector2(128, 40)
const CLASS_BTN_GAP: float = 8.0
## 立绘大图（200×250，512×768 高清 DNF 风立绘 KEEP_ASPECT_COVERED 填满）
const PORTRAIT_POS: Vector2 = Vector2(160, 46)
const PORTRAIT_SIZE: Vector2 = Vector2(200, 250)
## 右列：信息区
const INFO_RECT: Rect2 = Rect2(368, 46, 256, 254)
## 数值预览（2 列 5 行）
const STAT_GRID_RECT: Rect2 = Rect2(356, 152, 260, 84)
## 技能展示
const SKILL_LABEL_RECT: Rect2 = Rect2(356, 232, 260, 16)
## 技能卡區塊：單排時高 46；卡數超過一排時自動向下折行（見 _rebuild_skill_cards）。
const SKILL_CARDS_RECT: Rect2 = Rect2(356, 250, 260, 46)
## 技能卡標稱尺寸。x 僅作「期望欄寬」：實際欄寬 = 區寬均分（見 _skill_card_width）。
## 40×46：24px 圖標（48px 原生 0.5×，像素鐵律）+ 12px 名。6 欄 × 40 + 5 × 4 間隙 = 260 剛好填滿。
const SKILL_CARD_SIZE: Vector2 = Vector2(40, 46)
const SKILL_CARD_GAP: float = 4.0
## 圖標顯示邊長（原生 48px 的 1/2 整數縮放）
const SKILL_ICON_PX: float = 24.0
## 底部按钮
const BOTTOM_RECT: Rect2 = Rect2(0, 306, 640, 36)
const BTN_CONFIRM_SIZE: Vector2 = Vector2(160, 36)
const BTN_CANCEL_SIZE: Vector2 = Vector2(96, 36)
const BTN_GAP: float = 10.0

## 数值预览键 → 标签（与 StatCalculator.FINAL_KEYS / StatPanel.LABELS 同口径）
const STAT_LABELS: Dictionary = {
	"max_hp": "生命上限",
	"attack": "攻击力",
	"armor": "护甲",
	"move_speed": "速度",
	"crit_chance": "暴击率",
}
const STAT_KEYS: Array[String] = ["max_hp", "attack", "armor", "move_speed", "crit_chance"]

var _portrait: TextureRect = null
var _name_label: Label = null
var _playstyle_label: Label = null
var _desc_label: Label = null
var _stat_grid: GridContainer = null
var _skill_desc_label: Label = null
var _skill_cards: Array = []
var _class_buttons: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_select_class(current_class_id)


func _build_ui() -> void:
	# 半透明遮罩（挡首页点击）
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# 帧面板
	var frame := Panel.new()
	frame.name = "Frame"
	frame.position = FRAME_RECT.position
	frame.size = FRAME_RECT.size
	var sb := UISkin.panel_stylebox()
	if sb != null:
		frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)

	# 标题
	var title := Label.new()
	title.name = "Title"
	title.text = "选择职业"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	title.position = TITLE_RECT.position
	title.size = TITLE_RECT.size
	add_child(title)

	_build_class_list()
	_build_portrait()
	_build_info()
	_build_bottom()


## 左列：三个职业按钮（选中者套金色皮肤）
func _build_class_list() -> void:
	for cid in ConfigLoader.classes:
		var cls: Dictionary = ConfigLoader.classes[cid]
		var btn := Button.new()
		btn.name = "ClassBtn_%s" % cid
		btn.text = String(cls.get("display_name", cid))
		btn.add_theme_font_size_override("font_size", 16)
		var i := _class_buttons.size()
		btn.position = CLASS_LIST_RECT.position + Vector2(0.0, float(i) * (CLASS_BTN_SIZE.y + CLASS_BTN_GAP))
		btn.size = CLASS_BTN_SIZE
		btn.pressed.connect(func() -> void: _select_class(cid))
		AudioManager.hook_click(btn)
		btn.tooltip_text = "%s · %s" % [
			String(cls.get("display_name", cid)), String(cls.get("title", "")),
		]
		add_child(btn)
		_class_buttons.append({"id": cid, "btn": btn})


## 立绘大图：512×768 高清 DNF 风立绘，KEEP_ASPECT_COVERED 填满 200×250（上下微裁，特写更有张力）
func _build_portrait() -> void:
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.position = PORTRAIT_POS
	_portrait.size = PORTRAIT_SIZE
	add_child(_portrait)


## 右列：职业名+头衔 / 玩法定位 / 描述 / 数值预览 / 技能展示
func _build_info() -> void:
	_name_label = Label.new()
	_name_label.name = "ClassName"
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.position = INFO_RECT.position
	_name_label.size = Vector2(INFO_RECT.size.x, 24)
	add_child(_name_label)

	_playstyle_label = Label.new()
	_playstyle_label.name = "Playstyle"
	_playstyle_label.add_theme_font_size_override("font_size", 12)
	_playstyle_label.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	_playstyle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playstyle_label.position = INFO_RECT.position + Vector2(0.0, 26.0)
	_playstyle_label.size = Vector2(INFO_RECT.size.x, 18)
	add_child(_playstyle_label)

	_desc_label = Label.new()
	_desc_label.name = "Description"
	_desc_label.add_theme_font_size_override("font_size", 12)
	_desc_label.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[8])
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label.position = INFO_RECT.position + Vector2(0.0, 48.0)
	_desc_label.size = Vector2(INFO_RECT.size.x, 52)
	add_child(_desc_label)

	# 数值预览：2 列 5 行
	var stat_title := Label.new()
	stat_title.text = "基础属性（Lv.1）"
	stat_title.add_theme_font_size_override("font_size", 12)
	stat_title.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	stat_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_title.position = Vector2(INFO_RECT.position.x, 106.0)
	stat_title.size = Vector2(INFO_RECT.size.x, 16)
	add_child(stat_title)

	_stat_grid = GridContainer.new()
	_stat_grid.name = "StatGrid"
	_stat_grid.columns = 2
	_stat_grid.add_theme_constant_override("h_separation", 20)
	_stat_grid.add_theme_constant_override("v_separation", 4)
	_stat_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_grid.position = STAT_GRID_RECT.position
	_stat_grid.size = STAT_GRID_RECT.size
	add_child(_stat_grid)

	# 技能展示
	var skill_title := Label.new()
	skill_title.text = "技能"
	skill_title.add_theme_font_size_override("font_size", 12)
	skill_title.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	skill_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_title.position = SKILL_LABEL_RECT.position
	skill_title.size = SKILL_LABEL_RECT.size
	add_child(skill_title)

	# 技能卡改為「依職業池數量」於 _render_skills 動態建立（不再固定 5 張）。

	_skill_desc_label = Label.new()
	_skill_desc_label.name = "SkillDesc"
	_skill_desc_label.add_theme_font_size_override("font_size", 12)
	_skill_desc_label.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	_skill_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_desc_label.position = Vector2(INFO_RECT.position.x, 298.0)
	_skill_desc_label.size = Vector2(INFO_RECT.size.x, 16)
	add_child(_skill_desc_label)


## 技能卡欄數：由區寬 / 標稱卡寬算出（現 260 / (40+4) = 6 欄）。
## 目的：池數量改變時不必改排版代碼；未來池擴到 12 自動折成 2 排。
func _skill_columns() -> int:
	var denom := SKILL_CARD_SIZE.x + SKILL_CARD_GAP
	return maxi(1, int(floor((SKILL_CARDS_RECT.size.x + SKILL_CARD_GAP) / denom)))


## 實際欄寬：把區寬在 columns 欄之間均分（補掉標稱寬除不盡的餘數，保證右緣對齊）。
func _skill_card_width() -> float:
	var cols := _skill_columns()
	return (SKILL_CARDS_RECT.size.x - float(cols - 1) * SKILL_CARD_GAP) / float(cols)


## 依技能列表**數量**動態建卡（含自動換行）：
##   · 每張卡 = 24px 圖標（48px 原生 0.5× ⇒ 整數縮放，像素鐵律）+ 12px 名稱
##   · 超過一排欄數即折行，行高 = 卡高 + 間隙
## 切換職業時整批重建（先釋放舊卡），故 `_skill_cards.size()` 永遠 == 當前職業池大小。
## ⚠️ 2 排以上時卡片區塊會向下延伸，越過 _skill_desc_label（298）—— 現池上限 6 ⇒ 單排不受影響。
func _rebuild_skill_cards(skill_ids: Array[String]) -> void:
	for entry in _skill_cards:
		var old := entry["card"] as Control
		if old != null and is_instance_valid(old):
			old.queue_free()
	_skill_cards.clear()

	var cols := _skill_columns()
	var cw := _skill_card_width()
	var icon_x := (cw - SKILL_ICON_PX) * 0.5
	for i in skill_ids.size():
		var id := skill_ids[i]
		var card := Control.new()
		card.name = "SkillCard%d" % i
		card.position = SKILL_CARDS_RECT.position + Vector2(
			float(i % cols) * (cw + SKILL_CARD_GAP),
			float(i / cols) * (SKILL_CARD_SIZE.y + SKILL_CARD_GAP))
		card.size = Vector2(cw, SKILL_CARD_SIZE.y)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(card)

		var slot_tex0 := UISkin.texture("skill_slot")
		if slot_tex0 != null:
			var slot_bg0 := TextureRect.new()
			slot_bg0.texture = slot_tex0
			slot_bg0.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			slot_bg0.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot_bg0.stretch_mode = TextureRect.STRETCH_SCALE
			slot_bg0.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot_bg0.position = Vector2(icon_x, 2.0)
			slot_bg0.size = Vector2(SKILL_ICON_PX, SKILL_ICON_PX)
			card.add_child(slot_bg0)

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(icon_x, 2.0)
		icon.size = Vector2(SKILL_ICON_PX, SKILL_ICON_PX)
		card.add_child(icon)

		var name_l := Label.new()
		name_l.name = "Name"
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.position = Vector2(0.0, 28.0)
		name_l.size = Vector2(cw, 16)
		card.add_child(name_l)

		# hover 只綁一次（bind 按值捕獲索引，避免循環 lambda 捕獲陷阱）；
		# 事件時從 _skill_cards[i].id 現查數據（切職業不需重連）。
		card.mouse_entered.connect(_on_skill_card_hover.bind(i))
		card.mouse_exited.connect(_on_skill_card_exit.bind(i))
		_skill_cards.append({"card": card, "icon": icon, "name": name_l, "id": id})


func _on_skill_card_hover(i: int) -> void:
	var id := str(_skill_cards[i]["id"])
	if id.is_empty():
		return
	var sd := ConfigLoader.get_skill(id)
	if sd != null:
		_skill_desc_label.text = "%s：%s" % [sd.display_name, sd.description]


func _on_skill_card_exit(i: int) -> void:
	var id := str(_skill_cards[i]["id"])
	if id.is_empty():
		return
	var sd := ConfigLoader.get_skill(id)
	if sd != null and _skill_desc_label.text.begins_with(sd.display_name + "："):
		_skill_desc_label.text = ""


## 底部：返回 + 确认选择
func _build_bottom() -> void:
	var total_w := BTN_CANCEL_SIZE.x + BTN_GAP + BTN_CONFIRM_SIZE.x
	var x0 := (640.0 - total_w) * 0.5

	var cancel := _make_bottom_btn("返回", "dark", BTN_CANCEL_SIZE)
	cancel.position = Vector2(x0, BOTTOM_RECT.position.y)
	cancel.pressed.connect(func() -> void:
		if on_cancel.is_valid():
			on_cancel.call())
	add_child(cancel)

	var confirm := _make_bottom_btn("确认选择", "gold", BTN_CONFIRM_SIZE)
	confirm.position = Vector2(x0 + BTN_CANCEL_SIZE.x + BTN_GAP, BOTTOM_RECT.position.y)
	confirm.pressed.connect(func() -> void:
		if on_confirm.is_valid():
			on_confirm.call(current_class_id))
	add_child(confirm)


func _make_bottom_btn(text: String, kind: String, size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = size
	btn.size = size
	btn.add_theme_font_size_override("font_size", 16)
	var boxes := UISkin.btn_styleboxes(kind)
	for state in ["normal", "hover", "pressed"]:
		if boxes.has(state):
			btn.add_theme_stylebox_override(state, boxes[state])
	AudioManager.hook_click(btn)
	return btn


## 选中职业：刷新立绘 / 信息 / 数值 / 技能，并高亮按钮
func _select_class(cid: String) -> void:
	if not ConfigLoader.classes.has(cid):
		return
	current_class_id = cid
	var cls: Dictionary = ConfigLoader.classes[cid]

	# 立绘
	var tex := UISkin.texture(String(cls.get("portrait", "")))
	_portrait.texture = tex

	# 职业名 + 头衔（职业色）
	var cls_color := Color(String(cls.get("color", "F5D77A")))
	_name_label.text = "%s · %s" % [
		String(cls.get("display_name", cid)), String(cls.get("title", "")),
	]
	_name_label.add_theme_color_override("font_color", cls_color)

	# 玩法定位 + 描述
	_playstyle_label.text = String(cls.get("playstyle", ""))
	_desc_label.text = String(cls.get("description", ""))

	# 数值预览
	_render_stats(cls.get("stats", {}))

	# 技能展示
	_render_skills(ConfigLoader.class_skill_ids(cid))

	# 按钮高亮：选中 → 金，未选中 → 暗
	for entry in _class_buttons:
		var btn := entry["btn"] as Button
		var boxes := UISkin.btn_styleboxes("gold" if entry["id"] == cid else "dark")
		for state in ["normal", "hover", "pressed"]:
			if boxes.has(state):
				btn.add_theme_stylebox_override(state, boxes[state])


func _render_stats(stats: Dictionary) -> void:
	for child in _stat_grid.get_children():
		child.queue_free()
	for key in STAT_KEYS:
		var val := float(stats.get(key, 0.0))
		var name_l := Label.new()
		name_l.text = String(STAT_LABELS.get(key, key))
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[8])
		_stat_grid.add_child(name_l)

		var val_l := Label.new()
		val_l.text = _fmt_stat(key, val)
		val_l.add_theme_font_size_override("font_size", 12)
		val_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stat_grid.add_child(val_l)


func _fmt_stat(key: String, val: float) -> String:
	if key == "move_speed":
		return "%.1f 格/秒" % val
	if key == "crit_chance":
		return "%.0f%%" % (val * 100.0)
	if absf(val - roundf(val)) < 0.01:
		return str(int(roundf(val)))
	return "%.1f" % val


func _render_skills(skill_ids: Array[String]) -> void:
	_rebuild_skill_cards(skill_ids)
	for i in _skill_cards.size():
		var id := str(_skill_cards[i]["id"])
		var icon := _skill_cards[i]["icon"] as TextureRect
		var name_l := _skill_cards[i]["name"] as Label
		var sd: SkillData = ConfigLoader.get_skill(id)
		var icon_name := str(GameConstants.SKILL_ICON.get(id, ""))
		var tex := UISkin.texture(icon_name) if not icon_name.is_empty() else null
		icon.texture = tex if tex != null else UISkin.texture("skill_slot")
		name_l.text = sd.display_name if sd != null else id
	if skill_ids.size() > 0:
		var sd0: SkillData = ConfigLoader.get_skill(skill_ids[0])
		_skill_desc_label.text = "%s：%s" % [sd0.display_name, sd0.description] if sd0 != null else ""
	else:
		_skill_desc_label.text = ""
