## 技能管理面板（步骤 3 · 2026-09-22 · class_name）
##
## 位置：据点半透明浮层（PANEL_SKILLS，与背包/角色/装备等并列）。
## 职责：查看职业专属技能池 + 重排出战技能栏（1/2/3 键）+ **符文装配 / 形态分支 / 技能等级**，
##       保存到存档。
##
## 第四步 B4-4（工单 1-L9 + 1-L14）**两层结构**：
##   第一层 = 面板本体（400×282）：左「4×3 技能网格」（12 格，56×64）+ 右「出战栏」（3 槽 76×66 竖排）。
##   第二层 = 技能详情浮层（320×240，**置顶浮层**，由 `attach_overlay_host()` 注入宿主）：
##            图标 / 名称 / 形态 / Lv 进度条 / 倍率·冷却·蓝耗·DPS / **符文槽 3** / **分支二选一**。
##
## 符文（`01-技能体系.md` §2.2）：每技能 3 槽，技能等级达 **3 / 6 / 9** 依次解锁；
##   每个符文声明 `allowed_types`（不匹配 ⇒ 灰显）；同 `exclusive_group` 互斥。
## 分支（§2.3）：技能等级达 **5** 二选一；可在据点**免费**切换（Q5 裁定）。
## 解锁（§9）：未解锁技能灰显 + 显示解锁条件；**解锁 ≠ 出战**，不自动改出战栏。
##
## 数据流：hub 是唯一数据源。`bind()` 注入 class_id / 池 / 当前栏 / 符文 / 分支 / 解锁上下文 + 回调。
class_name SkillPanel
extends PanelContainer

## 出战栏槽数（与 project.godot skill_1/2/3 + PlayerController 输入一致）
const BAR_SLOTS: int = 3
## 技能池网格列数（4×3 = 12 格，§13.1）
const POOL_COLS: int = 4
## 技能卡尺寸（图标 48 + 名称行 14 + 间距）
const CARD_W: float = 56.0
const CARD_H: float = 64.0
## 技能图标显示尺寸：48×48 原生 1× 整数（像素铁律）
const ICON_PX: float = 48.0
## 出战槽尺寸（§13.1：3 槽 76×66 竖排）
const BAR_W: float = 76.0
const BAR_H: float = 66.0
## 符文槽数（`runes.json._meta.slots` 的镜像，用于布局；真实上限以数据为准）
const RUNE_SLOTS: int = 3
## 详情浮层尺寸（§13.1）
const DETAIL_W: float = 320.0
const DETAIL_H: float = 240.0
## 分支边框/高亮色（§13.2：A 金 / B 紫）
const BRANCH_COLOR_A: Color = Color("D9A441")
const BRANCH_COLOR_B: Color = Color("A96BFF")

var _class_id: String = GameConstants.CLASS_DEFAULT
var _pool: Array[String] = []
var _bar: Array[String] = []
## 保存回调：`func(bar: Array[String]) -> void`（hub 写存档 + 提示）
var on_save: Callable = Callable()

## 验证 / 测试用：当前工作区（保存前）
var bar: Array[String] = []
## `{skill_id: [rune_id, ...]}`（保存前的工作区）
var runes: Dictionary = {}
## `{skill_id: branch_id}`（保存前的工作区）
var branches: Dictionary = {}

## 解锁上下文（由 hub 注入；缺省 ⇒ 全部视为已解锁，兼容无档测试）
var _account_level: int = 1
var _cleared_levels: Array = []
## 是否强制解锁判定。hub 恒注入 `account_level` ⇒ true；旧调用 / 无头测试 ⇒ false（全放行）。
var _unlock_enforced: bool = false
## 已解锁符文 id（`SaveData.unlocked_runes`，由 hub 注入）。
##
## 门槛语义（**与技能解锁同一套写法**）：hub 恒注入 `unlocked_runes` 键 ⇒ `_rune_unlock_enforced = true`，
## 未解锁符文在选择器里**灰显不可选**；旧调用 / 无头测试不传该键 ⇒ false（全放行，向后兼容）。
##
## 口径（`01-技能体系.md` §11.4 Q2）：符文**图鉴式解锁** —— 首次掉落获得即永久解锁，
## 未解锁的符文**不能装配**（否则「掉落」对玩法毫无意义，图鉴只是摆设）。
var _unlocked_runes: Array[String] = []
var _rune_unlock_enforced: bool = false
## 当前全局技能等级（1–10；由 hub 从 `StatCalculator` 结算结果注入，缺省 1）。
## ⚠️ 技能等级是**全局**的（非单技能），故详情里所有技能显示同一等级。
var _skill_level_value: int = 1
## 符文/分支保存回调：`func(runes: Dictionary, branches: Dictionary) -> void`
var _on_config_saved: Callable = Callable()

var _title: Label = null
var _info: Label = null
var _pool_grid: GridContainer = null
var _bar_row: VBoxContainer = null
## 详情浮层宿主（由 `attach_overlay_host()` 注入；缺省挂在自身）
var _overlay_host: Node = null
var _detail_holder: Control = null
var _detail_box: PanelContainer = null
var _detail_skill_id: String = ""
## 正在为哪个槽位选符文（-1 = 不在选符文模式）
var _rune_pick_slot: int = -1


func _ready() -> void:
	_build_ui()


# =============================================================================
# 构建（第一层）
# =============================================================================

func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 282)
	var psb := UISkin.panel_stylebox()
	if psb != null: add_theme_stylebox_override("panel", psb)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	vb.add_child(_title)

	# ---- 主体：左「技能网格」+ 右「出战栏」（§13.1 尺寸核算 236 + 12 + 76 = 324 < 372）----
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	vb.add_child(main)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	main.add_child(left)
	var pool_l := Label.new()
	pool_l.text = "技能池（职业专属）"
	pool_l.add_theme_font_size_override("font_size", 12)
	pool_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	left.add_child(pool_l)

	_pool_grid = GridContainer.new()
	_pool_grid.columns = POOL_COLS
	_pool_grid.add_theme_constant_override("h_separation", 4)
	_pool_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(_pool_grid)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	main.add_child(right)
	var bar_l := Label.new()
	bar_l.text = "出战栏（1/2/3）"
	bar_l.add_theme_font_size_override("font_size", 12)
	bar_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	right.add_child(bar_l)

	_bar_row = VBoxContainer.new()
	_bar_row.add_theme_constant_override("separation", 6)
	right.add_child(_bar_row)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(_info)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	vb.add_child(bottom)
	var reset := _make_btn("恢复默认", "dark")
	reset.pressed.connect(func() -> void:
		_bar = ConfigLoader.class_default_skill_bar(_class_id).duplicate()
		_refresh()
		_info.text = "已恢复职业默认出战栏，记得点保存")
	bottom.add_child(reset)
	var save := _make_btn("保存配置", "gold")
	save.pressed.connect(_on_save_pressed)
	bottom.add_child(save)

	_build_detail_overlay()


## 详情浮层（第二层）：全屏 dim + 居中卡片。宿主由 `attach_overlay_host()` 注入。
##
## ⚠️ 缺省**挂自身**（否则 `_detail_holder` 不入树 ⇒ `visible = true` 也什么都不渲染，
##    无头验证里连 `DetailUnequip` 按钮都找不到）。hub 会立刻 `attach_overlay_host()`
##    把它改挂到 `_ui_layer`。
func _build_detail_overlay() -> void:
	_detail_holder = Control.new()
	_detail_holder.name = "SkillDetailOverlay"
	_detail_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_holder.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_holder.add_child(dim)
	_detail_box = PanelContainer.new()
	_detail_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_detail_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_detail_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_detail_box.custom_minimum_size = Vector2(DETAIL_W, DETAIL_H)
	_detail_holder.add_child(_detail_box)
	add_child(_detail_holder)


## 注入浮层宿主（hub 的 `_ui_layer`，类型为 CanvasLayer —— 故参数收 `Node`）。
## **必须在 `_ready()` 之后调用**。
## 不注入 ⇒ 浮层挂自身（仅用于无头验证；真机务必注入，否则会被 PanelContainer 拉伸）。
func attach_overlay_host(host: Node) -> void:
	if host == null or _detail_holder == null:
		return
	if _detail_holder.get_parent() != null:
		_detail_holder.get_parent().remove_child(_detail_holder)
	_overlay_host = host
	host.add_child(_detail_holder)
	_detail_holder.visible = false
	# 面板隐藏 ⇒ 详情一并关闭（宿主不在面板内，不会随面板隐藏）
	visibility_changed.connect(func() -> void:
		if not visible:
			_close_detail())


func _make_btn(text: String, kind: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(128, 34)
	btn.add_theme_font_size_override("font_size", 14)
	var boxes := UISkin.btn_styleboxes(kind)
	for state in ["normal", "hover", "pressed"]:
		if boxes.has(state):
			btn.add_theme_stylebox_override(state, boxes[state])
	return btn


# =============================================================================
# 数据注入
# =============================================================================

## hub 注入数据；每次打开（refresh）都会重新调用。
##
## `p_ctx`（可选）键：`runes` / `branches` / `account_level` / `cleared_levels` /
## `skill_level` / `unlocked_runes` / `on_config_saved`。
## 缺省 ⇒ 空符文、未选分支、全解锁（向后兼容旧调用与无头测试）。
func bind(p_class_id: String, p_pool: Array[String], p_bar: Array[String],
		p_on_save: Callable, p_ctx: Dictionary = {}) -> void:
	_class_id = p_class_id
	_pool = p_pool.duplicate()
	_bar = p_bar.duplicate()
	on_save = p_on_save
	runes = (p_ctx.get("runes", {}) as Dictionary).duplicate(true)
	branches = (p_ctx.get("branches", {}) as Dictionary).duplicate(true)
	_account_level = int(p_ctx.get("account_level", 1))
	_cleared_levels = (p_ctx.get("cleared_levels", []) as Array).duplicate()
	_unlock_enforced = p_ctx.has("account_level")
	# 符文解锁门槛（与技能解锁同款写法：**看键在不在**，而不是看值）
	_unlocked_runes.clear()
	for u in (p_ctx.get("unlocked_runes", []) as Array):
		_unlocked_runes.append(str(u))
	_rune_unlock_enforced = p_ctx.has("unlocked_runes")
	_skill_level_value = clampi(int(p_ctx.get("skill_level", 1)),
		GameConstants.SKILL_LEVEL_BASE, GameConstants.SKILL_LEVEL_MAX)
	_on_config_saved = p_ctx.get("on_config_saved", Callable())
	var cls: Dictionary = ConfigLoader.classes.get(_class_id, {})
	_title.text = "技能 · %s" % ConfigLoader.class_display_name(_class_id)
	_title.add_theme_color_override("font_color",
		Color(String(cls.get("color", "F5D77A"))))
	_close_detail()
	_refresh()


func _refresh() -> void:
	bar = _bar.duplicate()
	_render_pool()
	_render_bar()


# =============================================================================
# 第一层渲染
# =============================================================================

func _render_pool() -> void:
	# ⚠️ 先 remove_child 再 queue_free：queue_free 到帧末才生效，同帧内旧节点仍会被
	#    find_child / 输入命中（B4-4 实测踩到「点到上一轮的 DetailUnequip」）。
	for c in _pool_grid.get_children():
		_pool_grid.remove_child(c)
		c.queue_free()
	for sid in _pool:
		var locked := not _is_unlocked(sid)
		var card := Control.new()
		card.custom_minimum_size = Vector2(CARD_W, CARD_H)
		_pool_grid.add_child(card)

		var btn := Button.new()
		btn.name = "PoolBtn_%s" % sid
		btn.custom_minimum_size = Vector2(CARD_W, ICON_PX)
		btn.position = Vector2(0, 0)
		btn.add_theme_stylebox_override("normal", _card_box(false, locked))
		btn.add_theme_stylebox_override("hover", _card_box(true, locked))
		btn.add_theme_stylebox_override("pressed", _card_box(true, locked))
		btn.icon = UISkin.texture(_icon_key(sid))
		btn.expand_icon = true
		btn.modulate = Color(1, 1, 1, 1) if not locked else Color(0.45, 0.45, 0.5, 1)
		btn.tooltip_text = _lock_reason(sid)
		btn.pressed.connect(func() -> void: _on_pool_clicked(sid))
		card.add_child(btn)

		var name_l := Label.new()
		name_l.text = _display_name(sid)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color",
			GameConstants.PALETTE_NEUTRAL[9] if not locked else Color(0.6, 0.55, 0.5))
		name_l.position = Vector2(0, ICON_PX + 2.0)
		name_l.size = Vector2(CARD_W, 14)
		card.add_child(name_l)


func _render_bar() -> void:
	# ⚠️ 先 remove_child 再 queue_free：queue_free 到帧末才生效，同帧内旧节点仍会被
	#    find_child / 输入命中（B4-4 实测踩到「点到上一轮的 DetailUnequip」）。
	for c in _bar_row.get_children():
		_bar_row.remove_child(c)
		c.queue_free()
	for i in BAR_SLOTS:
		var sid := _bar[i] if i < _bar.size() else ""
		var slot := Control.new()
		slot.name = "BarSlot%d" % i
		slot.custom_minimum_size = Vector2(BAR_W, BAR_H)
		_bar_row.add_child(slot)

		var btn := Button.new()
		btn.name = "BarBtn%d" % i
		btn.custom_minimum_size = Vector2(BAR_W, ICON_PX)
		btn.position = Vector2(0, 0)
		btn.add_theme_stylebox_override("normal", _card_box(false, false))
		btn.add_theme_stylebox_override("hover", _card_box(true, false))
		btn.add_theme_stylebox_override("pressed", _card_box(true, false))
		btn.icon = UISkin.texture(_icon_key(sid)) if not sid.is_empty() else UISkin.texture("skill_slot")
		btn.expand_icon = true
		btn.pressed.connect(func() -> void: _on_bar_clicked(i))
		slot.add_child(btn)

		# 键位角标 1/2/3
		var key_l := Label.new()
		key_l.text = str(i + 1)
		key_l.add_theme_font_size_override("font_size", 12)
		key_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
		key_l.position = Vector2(2, 0)
		slot.add_child(key_l)

		var name_l := Label.new()
		name_l.text = _display_name(sid) if not sid.is_empty() else "空位"
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color",
			GameConstants.PALETTE_NEUTRAL[7] if sid.is_empty() else GameConstants.PALETTE_NEUTRAL[9])
		name_l.position = Vector2(0, ICON_PX + 2.0)
		name_l.size = Vector2(BAR_W, 14)
		slot.add_child(name_l)


# =============================================================================
# 交互（第一层）
# =============================================================================

## 技能池点击：装到第一个空位；已在栏 / 栏满 / 未解锁 → 提示
func _on_pool_clicked(sid: String) -> void:
	if not _is_unlocked(sid):
		_info.text = "「%s」尚未解锁（%s）" % [_display_name(sid), _lock_reason(sid)]
		return
	if _bar.has(sid):
		_info.text = "「%s」已在出战栏" % _display_name(sid)
		return
	if _bar.size() >= BAR_SLOTS:
		_info.text = "出战栏已满（%d 格），先点击出战槽卸下再装配" % BAR_SLOTS
		return
	_bar.append(sid)
	_info.text = "已装配「%s」（未保存）" % _display_name(sid)
	_refresh()
	# 装配后直接进入详情（第一层 → 第二层），便于立刻配符文 / 分支
	_open_detail(sid)


## 出战槽点击：有技能 ⇒ 打开详情；空位 ⇒ 提示
func _on_bar_clicked(index: int) -> void:
	if index >= _bar.size():
		_info.text = "空位：点击左侧技能池装配"
		return
	_open_detail(_bar[index])


## 详情浮层里的「从出战栏卸下」
func _on_unequip_pressed(sid: String) -> void:
	var idx := _bar.find(sid)
	if idx < 0:
		return
	_bar.remove_at(idx)
	_info.text = "已卸下「%s」（未保存）" % _display_name(sid)
	_close_detail()
	_refresh()


func _on_save_pressed() -> void:
	if _bar.is_empty():
		_info.text = "出战栏不能为空，请先装配至少 1 个技能"
		return
	if on_save.is_valid():
		on_save.call(_bar.duplicate())
	if _on_config_saved.is_valid():
		_on_config_saved.call(runes.duplicate(true), branches.duplicate(true))
	_info.text = "已保存：%s" % ", ".join(_bar.map(_display_name))


# =============================================================================
# 第二层：技能详情浮层（1-L9 + 1-L14）
# =============================================================================

func _open_detail(sid: String) -> void:
	if sid.is_empty() or _detail_holder == null:
		return
	_detail_skill_id = sid
	_rune_pick_slot = -1
	_render_detail()
	_detail_holder.visible = true


func _close_detail() -> void:
	if _detail_holder != null:
		_detail_holder.visible = false
	_detail_skill_id = ""
	_rune_pick_slot = -1


## 详情浮层是否可见（验证钩子）
func is_detail_open() -> bool:
	return _detail_holder != null and _detail_holder.visible


## 当前详情技能 id（验证钩子）
func detail_skill_id() -> String:
	return _detail_skill_id


func _render_detail() -> void:
	if _detail_box == null:
		return
	# ⚠️ 先 remove_child 再 queue_free：queue_free 到帧末才生效，同帧内旧节点仍会被
	#    find_child / 输入命中（B4-4 实测踩到「点到上一轮的 DetailUnequip」）。
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()
	var sid := _detail_skill_id
	var sd := ConfigLoader.get_skill(sid)
	if sd == null:
		return

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_detail_box.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	# ---- 标题行：图标 + 名称 + 形态 + 关闭 ----
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	vb.add_child(head)
	var ico := TextureRect.new()
	ico.texture = UISkin.texture(_icon_key(sid))
	ico.custom_minimum_size = Vector2(24, 24)
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(ico)
	var nm := Label.new()
	nm.text = "%s  [%s]" % [sd.display_name, _type_label(sd)]
	nm.add_theme_font_size_override("font_size", 14)
	head.add_child(nm)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "关闭"
	close.add_theme_font_size_override("font_size", 12)
	close.pressed.connect(_close_detail)
	head.add_child(close)

	# ---- 等级进度条（全局技能等级；L1 ── L10）----
	var lv := _skill_level()
	var bar_txt := "Lv.%d  %s%s  L1 ── L10" % [lv, "█".repeat(lv), "░".repeat(maxi(0, 10 - lv))]
	var lv_l := Label.new()
	lv_l.text = bar_txt
	lv_l.add_theme_font_size_override("font_size", 12)
	lv_l.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[14])
	vb.add_child(lv_l)

	# ---- 数值行：倍率 / 冷却 / 蓝耗 / DPS（倍率含等级系数）----
	var mult := sd.total_damage_multiplier() * _level_mult()
	var stat_l := Label.new()
	stat_l.text = "倍率 %.2f   冷却 %.1fs   蓝耗 %.0f   DPS %.2f" % [
		mult, sd.cooldown, sd.mana_cost, sd.dps_coefficient() * _level_mult()]
	stat_l.add_theme_font_size_override("font_size", 12)
	stat_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	vb.add_child(stat_l)

	# ---- 出战栏操作：已在栏 ⇒ 提供「卸下」----
	# ⚠️ 第一层点击出战槽现在**打开详情**（不再直接卸下），故卸下入口必须在这里，
	#    否则玩家没有任何途径把技能移出出战栏。
	if _bar.has(sid):
		var unequip := _make_btn("从出战栏卸下", "dark")
		unequip.name = "DetailUnequip"
		unequip.custom_minimum_size = Vector2(140, 28)
		unequip.pressed.connect(func() -> void: _on_unequip_pressed(sid))
		vb.add_child(unequip)

	vb.add_child(_hr())

	if _rune_pick_slot >= 0:
		_render_rune_picker(vb, sid, sd)
		return

	# ---- 符文槽（3 槽；3/6/9 解锁；不匹配灰显；同组互斥）----
	var rune_l := Label.new()
	rune_l.text = "符文槽："
	rune_l.add_theme_font_size_override("font_size", 12)
	vb.add_child(rune_l)
	var rune_row := HBoxContainer.new()
	rune_row.add_theme_constant_override("separation", 6)
	vb.add_child(rune_row)
	var slot_levels := _slot_unlock_levels()
	for s in RUNE_SLOTS:
		var need := int(slot_levels[s]) if s < slot_levels.size() else 999
		var unlocked_slot := lv >= need
		var cur := _rune_at(sid, s)
		var b := Button.new()
		b.name = "RuneSlot%d" % s
		b.custom_minimum_size = Vector2(64, 26)
		b.add_theme_font_size_override("font_size", 11)
		if not unlocked_slot:
			b.text = "🔒%d" % need
			b.disabled = true
			b.tooltip_text = "技能等级 %d 解锁" % need
		elif cur.is_empty():
			b.text = "＋"
			b.tooltip_text = "点击选择符文"
		else:
			b.text = _rune_name(cur)
			b.tooltip_text = "%s（点击更换 / 卸下）" % _rune_name(cur)
		b.pressed.connect(func() -> void: _on_rune_slot_pressed(s, unlocked_slot))
		rune_row.add_child(b)

	vb.add_child(_hr())

	# ---- 分支二选一（技能等级 5 解锁；免费切换）----
	var need_branch := _branch_unlock_level()
	var branch_l := Label.new()
	branch_l.text = "分支（Lv.%d 解锁）：" % need_branch if lv < need_branch else "分支："
	branch_l.add_theme_font_size_override("font_size", 12)
	branch_l.add_theme_color_override("font_color",
		GameConstants.PALETTE_NEUTRAL[9] if lv >= need_branch else Color(0.7, 0.55, 0.5))
	vb.add_child(branch_l)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	vb.add_child(brow)
	var cur_branch := _branch_of(sid)
	var opts := ConfigLoader.branch_options_for_type(_type_key(sd.type))
	for i in opts.size():
		var o: Dictionary = opts[i]
		var bid := String(o.get("id", ""))
		var bbtn := Button.new()
		bbtn.name = "BranchBtn_%s" % bid
		bbtn.custom_minimum_size = Vector2(132, 28)
		bbtn.add_theme_font_size_override("font_size", 12)
		var selected := bid == cur_branch
		bbtn.text = "%s%s" % [String(o.get("display_name", bid)), "  ✓" if selected else ""]
		bbtn.disabled = lv < need_branch
		bbtn.tooltip_text = String(o.get("description", ""))
		if selected:
			bbtn.add_theme_stylebox_override("normal", _branch_box(i))
		bbtn.pressed.connect(func() -> void: _on_branch_pressed(bid))
		brow.add_child(bbtn)
	if opts.is_empty():
		var none_l := Label.new()
		none_l.text = "（该形态无分支模板）"
		none_l.add_theme_font_size_override("font_size", 12)
		none_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
		brow.add_child(none_l)


## 符文选择列表（详情浮层的子视图）：只列该技能形态允许的符文；不匹配 / 同组冲突灰显。
##
## ⚠️ 三档灰显，**优先显示「未解锁」**（最可操作的那条）：
##   未解锁（图鉴没收集到）> 不适用该形态 > 与已插符文同组互斥。
func _render_rune_picker(vb: VBoxContainer, sid: String, sd: SkillData) -> void:
	var back := Button.new()
	back.text = "← 返回详情"
	back.add_theme_font_size_override("font_size", 12)
	back.pressed.connect(func() -> void:
		_rune_pick_slot = -1
		_render_detail())
	vb.add_child(back)
	var title := Label.new()
	title.text = "为第 %d 槽选择符文" % (_rune_pick_slot + 1)
	title.add_theme_font_size_override("font_size", 12)
	vb.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 140)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	# 「卸下」项
	var clear_btn := Button.new()
	clear_btn.name = "RunePick__clear"
	clear_btn.text = "（卸下该槽符文）"
	clear_btn.add_theme_font_size_override("font_size", 12)
	clear_btn.pressed.connect(func() -> void: _assign_rune(sid, _rune_pick_slot, ""))
	list.add_child(clear_btn)

	var ids := ConfigLoader.runes.keys()
	ids.sort()
	for rid_v in ids:
		var rid := String(rid_v)
		var rune: Dictionary = ConfigLoader.runes[rid]
		var unlocked := _is_rune_unlocked(rid)
		var ok_type := _rune_type_ok(sd, rune)
		var conflict := _rune_group_conflict(sid, rid)
		var b := Button.new()
		b.name = "RunePick_%s" % rid
		b.custom_minimum_size = Vector2(0, 24)
		b.add_theme_font_size_override("font_size", 12)
		var suffix := ""
		if not unlocked:
			suffix = "（未解锁 · 需掉落获得）"
		elif not ok_type:
			suffix = "（不适用该形态）"
		elif conflict:
			suffix = "（与已插符文同组互斥）"
		b.text = "%s  [%s]%s" % [String(rune.get("display_name", rid)),
			String(rune.get("category", "")), suffix]
		b.disabled = (not unlocked) or (not ok_type) or conflict
		if not unlocked:
			b.modulate = Color(0.5, 0.5, 0.55, 1)
		b.tooltip_text = String(rune.get("description", ""))
		b.pressed.connect(func() -> void: _assign_rune(sid, _rune_pick_slot, rid))
		list.add_child(b)


## 该符文是否可装配（图鉴解锁门槛）。
##
## `_rune_unlock_enforced == false`（hub 未注入 `unlocked_runes`，如旧调用 / 无头测试）⇒ **全放行**。
func _is_rune_unlocked(rid: String) -> bool:
	return (not _rune_unlock_enforced) or _unlocked_runes.has(rid)


func _hr() -> HSeparator:
	return HSeparator.new()


# =============================================================================
# 符文 / 分支 写入（工作区，保存时才落盘）
# =============================================================================

func _on_rune_slot_pressed(slot: int, unlocked_slot: bool) -> void:
	if not unlocked_slot:
		return
	_rune_pick_slot = slot
	_render_detail()


func _assign_rune(sid: String, slot: int, rune_id: String) -> void:
	var arr: Array = (runes.get(sid, []) as Array).duplicate()
	# 补齐到 slot 位（允许空串占位）
	while arr.size() <= slot:
		arr.append("")
	arr[slot] = rune_id
	# 去掉空串（紧凑存储；槽位语义由顺序决定）
	var kept: Array = []
	for r in arr:
		if not String(r).is_empty():
			kept.append(String(r))
	runes[sid] = kept
	_rune_pick_slot = -1
	_render_detail()
	_info.text = "已%s符文（未保存）" % ("卸下" if rune_id.is_empty() else "装配")


func _on_branch_pressed(branch_id: String) -> void:
	var sid := _detail_skill_id
	if sid.is_empty():
		return
	if _branch_of(sid) == branch_id:
		return
	branches[sid] = branch_id
	_render_detail()
	_info.text = "已选分支「%s」（未保存 · 免费切换）" % branch_id


# =============================================================================
# 查询辅助
# =============================================================================

func _rune_at(sid: String, slot: int) -> String:
	var arr: Array = runes.get(sid, [])
	if slot < 0 or slot >= arr.size():
		return ""
	return String(arr[slot])


func _branch_of(sid: String) -> String:
	return String(branches.get(sid, ""))


func _rune_name(rid: String) -> String:
	var r: Dictionary = ConfigLoader.runes.get(rid, {})
	return String(r.get("display_name", rid))


func _slot_unlock_levels() -> Array:
	var arr: Variant = ConfigLoader.rune_meta.get("slot_unlock_skill_level", [3, 6, 9])
	return arr if arr is Array else [3, 6, 9]


func _branch_unlock_level() -> int:
	return int(ConfigLoader.branch_meta.get("unlock_skill_level", 5))


## 符文是否适用于该技能形态（`allowed_types` 命中 `SkillData.TYPE_KEYS`）
func _rune_type_ok(sd: SkillData, rune: Dictionary) -> bool:
	var allowed: Variant = rune.get("allowed_types", [])
	if not (allowed is Array):
		return false
	return _type_key(sd.type) in allowed


## 该符文是否与已插符文同 `exclusive_group` 冲突
func _rune_group_conflict(sid: String, rid: String) -> bool:
	var g := String((ConfigLoader.runes.get(rid, {}) as Dictionary).get("exclusive_group", ""))
	if g.is_empty():
		return false
	for other in runes.get(sid, []):
		if String(other) == rid:
			continue
		var og := String((ConfigLoader.runes.get(String(other), {}) as Dictionary).get("exclusive_group", ""))
		if og == g:
			return true
	return false


func _skill_level() -> int:
	return _skill_level_value


func _level_mult() -> float:
	return 1.0 + GameConstants.SKILL_LEVEL_COEF_PER_LEVEL * float(_skill_level() - 1)


func _type_key(t: int) -> String:
	if t < 0 or t >= SkillData.TYPE_KEYS.size():
		return ""
	return String(SkillData.TYPE_KEYS[t])


func _type_label(sd: SkillData) -> String:
	if sd.type < 0 or sd.type >= SkillData.TYPE_NAMES.size():
		return "?"
	return String(SkillData.TYPE_NAMES[sd.type])


func _is_unlocked(sid: String) -> bool:
	# 未注入解锁上下文（旧调用 / 无头测试）⇒ 不设限；hub 恒注入 `account_level` ⇒ 真实判定
	if not _unlock_enforced:
		return true
	return UnlockSystem.is_skill_unlocked(sid, _account_level, _cleared_levels)


func _lock_reason(sid: String) -> String:
	return UnlockSystem.skill_lock_reason(sid, _account_level, _cleared_levels)


func _display_name(sid: String) -> String:
	var sd := ConfigLoader.get_skill(sid)
	return sd.display_name if sd != null else sid


func _icon_key(sid: String) -> String:
	var key := str(GameConstants.SKILL_ICON.get(sid, ""))
	if key.is_empty() or UISkin.texture(key) == null:
		return "skill_slot"
	return key


func _card_box(hover: bool, locked: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1A1E24") if hover else Color("14171C")
	if locked:
		box.border_color = Color("4A3F3A")
	else:
		box.border_color = Color("D9A441") if hover else Color("3A424F")
	box.set_border_width_all(1)
	return box


func _branch_box(index: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1A1E24")
	box.border_color = BRANCH_COLOR_A if index == 0 else BRANCH_COLOR_B
	box.set_border_width_all(2)
	return box
