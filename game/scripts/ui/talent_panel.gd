## 技能树 / 天赋界面（任务 7.4 · class_name）
##
## 展示局外天赋树（TalentTree 数据）：三分支（战/法/影）节点 + 已点/可点/锁定状态 +
## 可用点数 + 加成汇总。面板只读展示 + learn 回调转发（由账号层注入）。
class_name TalentPanel
extends PanelContainer

const BRANCHES := ["war", "mage", "shadow"]
const BRANCH_NAMES := {"war": "战争", "mage": "秘法", "shadow": "影行"}
## 面板分支的解锁等级（与规划文档/提示行口径一致：战争 L1 / 秘法 L15 / 影行 L30）。
## 注：TalentTree 内部用 might/guardian/arcane 键；面板用 war/mage/shadow 展示键，
## 二者等级一一对应（war→might=1 / mage→guardian=15 / shadow→arcane=30）。
const BRANCH_UNLOCK := {"war": 1, "mage": 15, "shadow": 30}
const BRANCH_COLORS := {
	"war": Color(0.75, 0.4, 0.35), "mage": Color(0.4, 0.55, 0.85), "shadow": Color(0.55, 0.4, 0.75),
}

## 已点节点（String 数组，TalentTree.node_id 格式）
var learned: Array = []
var account_level: int = 1
## 回调：learn(node_id)
var on_learn: Callable = Callable()

## 职业 id（标题配色用；默认战士金）
var _class_id: String = GameConstants.CLASS_DEFAULT

var _grid: GridContainer = null
var _points_label: Label = null
var _title: Label = null


func _ready() -> void:
	_build_ui()
	refresh()


func bind(p_learned: Array, p_account_level: int, p_on_learn: Callable = Callable(),
		p_class_id: String = GameConstants.CLASS_DEFAULT) -> void:
	learned = p_learned
	account_level = p_account_level
	on_learn = p_on_learn
	_class_id = p_class_id
	refresh()


func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "天赋树 · %s" % ConfigLoader.class_display_name(_class_id)
	title.add_theme_font_size_override("font_size", 16)
	head.add_child(title)
	_title = title
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 12)
	_points_label.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[4])
	head.add_child(_points_label)

	var hint := Label.new()
	hint.text = "天赋点为账号共享 · 分支按账号等级解锁（战争 L1 / 秘法 L15 / 影行 L30）"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(hint)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(_grid)


func refresh() -> void:
	if _title != null:
		_title.text = "天赋树 · %s" % ConfigLoader.class_display_name(_class_id)
		var cls: Dictionary = ConfigLoader.classes.get(_class_id, {})
		_title.add_theme_color_override("font_color",
			Color(String(cls.get("color", "F5D77A"))))
	if _points_label != null:
		_points_label.text = "可用点数 %d" % maxi(0, TalentTree._available_points(account_level) - learned.size())
	for child in _grid.get_children():
		child.queue_free()
	for branch in BRANCHES:
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(116, 260)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.08, 0.11)
		sb.border_color = BRANCH_COLORS.get(branch, Color(0.5, 0.5, 0.5))
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(0)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", sb)
		_grid.add_child(pc)
		pc.add_child(card)
		var name_l := Label.new()
		name_l.text = BRANCH_NAMES.get(branch, branch)
		name_l.add_theme_font_size_override("font_size", 14)
		name_l.add_theme_color_override("font_color", BRANCH_COLORS.get(branch, Color.WHITE))
		card.add_child(name_l)
		var unlocked := account_level >= int(BRANCH_UNLOCK.get(branch, 99))
		var state_l := Label.new()
		# 修 bug：原实现把 branch_cost()（=20）当等级显示，所有分支显示 Lv20；
		# 且用 TalentTree 的 might/guardian/arcane 键去查（面板键是 war/mage/shadow）→ Lv99。
		# 正确口径 = 面板分支自己的解锁等级（BRANCH_UNLOCK：战争 L1 / 秘法 L15 / 影行 L30）。
		var unlock_lv := int(BRANCH_UNLOCK.get(branch, 99))
		state_l.text = "解锁" if unlocked else "未解锁（账号 Lv.%d）" % unlock_lv
		state_l.add_theme_font_size_override("font_size", 10)
		state_l.add_theme_color_override("font_color",
			GameConstants.PALETTE_NEUTRAL[9] if unlocked else Color(0.7, 0.55, 0.5))
		card.add_child(state_l)
		# 每分支 4 个节点（2 小 + 1 大 + 1 小 示意）
		for i in 4:
			var node := TalentTree.node_id(branch, "small" if i != 2 else "big", i)
			var is_learned := learned.has(node)
			var can_learn := unlocked and not is_learned and not learned.has(node)
			var btn := Button.new()
			btn.text = "%s%s" % [node, " ✓" if is_learned else ""]
			btn.add_theme_font_size_override("font_size", 10)
			btn.focus_mode = Control.FOCUS_NONE
			btn.disabled = not can_learn
			if is_learned:
				btn.add_theme_stylebox_override("normal", _node_style(BRANCH_COLORS.get(branch, Color.WHITE)))
			btn.pressed.connect(func() -> void:
				if on_learn.is_valid():
					on_learn.call(node))
			card.add_child(btn)


func _node_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	return sb
