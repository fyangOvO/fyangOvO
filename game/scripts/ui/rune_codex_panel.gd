## 符文图鉴面板（第四步 B4-4 · 工单 1-L12 · 2026-09-29 · class_name）
##
## 位置：据点面板按钮条第 **7** 项（`PANEL_RUNE_CODEX`），与背包/角色/装备/天赋/锻造/技能并列。
## 职责：**只读**展示 24 条符文的收集进度与详情（`01-技能体系.md` §13.3）。
##
## 布局：左「6×4 = 24 格网格」（每格 48×48，像素铁律 1×）+ 右「详情」（名称 / 互斥组 /
##       适用形态 / 效果文案 / 解锁状态）。
##
## 解锁口径（§11.4 · Q2 图鉴式）：**首次获得即永久解锁**，来源为精英 8% / BOSS 25% 掉落。
##   解锁集合由 `SaveData.unlocked_runes` 提供（掉落接线见 B6 `2-L12`）。
##   ⚠️ 未解锁 = 灰显 + 锁标记；**图鉴不是装配入口**（装配在技能面板的详情浮层）。
##
## 数据流：hub 是唯一数据源。`bind(unlocked, skill_level)` 注入；本面板**零写操作**。
class_name RuneCodexPanel
extends PanelContainer

## 网格列/行（§13.3：6×4 = 24）
const COLS: int = 6
const ROWS: int = 4
## 每格边长（§13.3：48×48）
const CELL: float = 48.0
## 详情区宽度
const DETAIL_W: float = 224.0

## 已解锁符文 id（hub 注入）
var _unlocked: Array[String] = []
## 当前全局技能等级（仅用于提示「符文槽何时解锁」；不参与图鉴解锁）
var _skill_level: int = GameConstants.SKILL_LEVEL_BASE

## 当前选中的符文 id（空 = 未选）
var _selected: String = ""

var _grid: GridContainer = null
var _detail: VBoxContainer = null
var _progress: Label = null


func _ready() -> void:
	_build_ui()


# =============================================================================
# 构建
# =============================================================================

func _build_ui() -> void:
	custom_minimum_size = Vector2(560, 300)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "符文图鉴"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[14])
	vb.add_child(title)

	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 12)
	_progress.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	vb.add_child(_progress)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	vb.add_child(main)

	# ---- 左：6×4 网格 ----
	_grid = GridContainer.new()
	_grid.name = "RuneGrid"
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	main.add_child(_grid)

	# ---- 右：详情 ----
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(DETAIL_W, 0)
	main.add_child(right)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 5)
	right.add_child(_detail)

	_render()


func _render() -> void:
	_render_grid()
	_render_detail()


# =============================================================================
# 数据注入
# =============================================================================

## hub 注入。`p_unlocked` = `SaveData.unlocked_runes`；`p_skill_level` 仅作提示用。
func bind(p_unlocked: Array[String], p_skill_level: int) -> void:
	_unlocked = p_unlocked.duplicate()
	_skill_level = maxi(GameConstants.SKILL_LEVEL_BASE, p_skill_level)
	_selected = ""
	if _grid != null:
		_render()


# =============================================================================
# 网格
# =============================================================================

func _render_grid() -> void:
	# ⚠️ 先 remove_child 再 queue_free：queue_free 到帧末才生效，同帧内旧节点仍会被
	#    find_child / 输入命中（B4-4 实测踩到「点到上一轮的 DetailUnequip」）。
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var ids := _all_rune_ids()
	for rid in ids:
		var unlocked := is_rune_unlocked(rid)
		var btn := Button.new()
		btn.name = "RuneCell_%s" % rid
		btn.custom_minimum_size = Vector2(CELL, CELL)
		btn.add_theme_stylebox_override("normal", _cell_box(rid == _selected, false, unlocked))
		btn.add_theme_stylebox_override("hover", _cell_box(rid == _selected, true, unlocked))
		btn.add_theme_stylebox_override("pressed", _cell_box(rid == _selected, true, unlocked))
		btn.icon = UISkin.rune_icon(rid)
		btn.expand_icon = true
		btn.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.4, 0.4, 0.45, 1)
		btn.tooltip_text = _rune_name(rid)
		btn.pressed.connect(func() -> void: _on_cell_pressed(rid))
		_grid.add_child(btn)

		if not unlocked:
			var lock := Label.new()
			lock.name = "RuneLock_%s" % rid
			lock.text = "🔒"
			lock.add_theme_font_size_override("font_size", 14)
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock.position = Vector2(CELL - 16.0, CELL - 18.0)
			btn.add_child(lock)

	_progress.text = "收集进度 %d / %d　（精英 8%% · BOSS 25%% 掉落，首次获得即永久解锁）" % [
		_unlocked.size(), ids.size()]


## 单元格点击：选中并刷新详情
func _on_cell_pressed(rid: String) -> void:
	_selected = rid
	_render_detail()


# =============================================================================
# 详情
# =============================================================================

func _render_detail() -> void:
	# ⚠️ 先 remove_child 再 queue_free：queue_free 到帧末才生效，同帧内旧节点仍会被
	#    find_child / 输入命中（B4-4 实测踩到「点到上一轮的 DetailUnequip」）。
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	if _selected.is_empty():
		var hint := Label.new()
		hint.text = "← 点击左侧符文查看详情"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(hint)
		return

	var rid := _selected
	var rune: Dictionary = ConfigLoader.runes.get(rid, {})
	var unlocked := is_rune_unlocked(rid)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_detail.add_child(head)
	var ico := TextureRect.new()
	ico.texture = UISkin.rune_icon(rid)
	ico.custom_minimum_size = Vector2(32, 32)
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ico.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.4, 0.4, 0.45, 1)
	head.add_child(ico)
	var nm := Label.new()
	nm.text = "%s%s" % [_rune_name(rid), "" if unlocked else "  🔒"]
	nm.add_theme_font_size_override("font_size", 14)
	head.add_child(nm)

	_detail.add_child(_line("互斥组：%s" % _group_label(String(rune.get("exclusive_group", "")))))
	_detail.add_child(_line("适用形态：%s" % _types_label(rune)))
	_detail.add_child(_line("效果：%s" % String(rune.get("description", "—"))))
	_detail.add_child(HSeparator.new())

	var state := Label.new()
	state.add_theme_font_size_override("font_size", 12)
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if unlocked:
		state.text = "状态：已解锁 · 可在技能详情里装配"
		state.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[14])
	else:
		state.text = "状态：未解锁 · 精英 8% / BOSS 25% 掉落，首次获得永久解锁"
		state.add_theme_color_override("font_color", Color(0.7, 0.55, 0.5))
	_detail.add_child(state)

	var slots := Label.new()
	slots.text = "符文槽：技能等级 3 / 6 / 9 依次解锁（当前 Lv.%d）" % _skill_level
	slots.add_theme_font_size_override("font_size", 11)
	slots.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	slots.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(slots)


func _line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# =============================================================================
# 查询（验证钩子）
# =============================================================================

## 全部符文 id（按 `ConfigLoader.runes` 键排序，稳定顺序）
func _all_rune_ids() -> Array[String]:
	var out: Array[String] = []
	for k in ConfigLoader.runes.keys():
		out.append(String(k))
	out.sort()
	return out


## 该符文是否已解锁
func is_rune_unlocked(rune_id: String) -> bool:
	return _unlocked.has(rune_id)


## 当前选中的符文 id（验证钩子）
func selected_rune() -> String:
	return _selected


## 选中指定符文（验证 / 无头测试用，等价于点格子）
func select_rune(rune_id: String) -> void:
	_selected = rune_id
	if _detail != null:
		_render_detail()


## 已解锁数量 / 总数（验证钩子）
func unlock_progress() -> Vector2i:
	return Vector2i(_unlocked.size(), _all_rune_ids().size())


# =============================================================================
# 文案辅助
# =============================================================================

func _rune_name(rid: String) -> String:
	var r: Dictionary = ConfigLoader.runes.get(rid, {})
	return String(r.get("display_name", rid))


func _group_label(group: String) -> String:
	match group:
		"form": return "形态（form）"
		"element": return "元素（element）"
		"amp": return "增幅（amp）"
		"util": return "行为（util）"
		_: return group if not group.is_empty() else "—"


func _types_label(rune: Dictionary) -> String:
	var allowed: Variant = rune.get("allowed_types", [])
	if not (allowed is Array) or (allowed as Array).is_empty():
		return "—"
	var names: Array[String] = []
	for t in allowed:
		names.append(_type_label(String(t)))
	return " / ".join(names)


func _type_label(key: String) -> String:
	var idx := SkillData.TYPE_KEYS.find(key)
	if idx < 0 or idx >= SkillData.TYPE_NAMES.size():
		return key
	return String(SkillData.TYPE_NAMES[idx])


func _cell_box(selected: bool, hover: bool, unlocked: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1A1E24") if hover else Color("14171C")
	if selected:
		box.border_color = GameConstants.PALETTE_ACCENT[14]
	elif unlocked:
		box.border_color = Color("3A424F")
	else:
		box.border_color = Color("4A3F3A")
	box.set_border_width_all(2 if selected else 1)
	return box
