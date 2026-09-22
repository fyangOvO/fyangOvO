## 角色属性面板（任务 7.2 · class_name）
##
## **键口径**：本面板**只认 `StatCalculator.FINAL_KEYS`（31 键）**，也就是
## `StatCalculator.calculate()` 的输出字典。渲染顺序直接跟随 `FINAL_KEYS`，
## 所以结算侧新增/改名键时面板会自动跟上 —— 不会再出现「面板读 flat_hp、
## 结算吐 max_hp，结果整页显示 0」这类静默漂移（集成层阶段 2 修的就是这个）。
##
## 面板只读：调用方算好属性再 `show_stats()`。
class_name StatPanel
extends PanelContainer

## 键 → 中文标签。**必须覆盖 `StatCalculator.FINAL_KEYS` 的每一个键**，
## 由 `tools/verify_hub` 断言「LABELS 与 FINAL_KEYS 键集完全一致」。
const LABELS: Dictionary = {
	"max_hp": "生命上限",
	"attack": "攻击力",
	"armor": "护甲",
	"crit_chance": "暴击率",
	"crit_damage": "暴击伤害",
	"attack_speed": "攻击速度",
	"elemental_damage": "元素伤害",
	"dodge": "闪避",
	"block_chance": "格挡率",
	"life_regen": "生命回复",
	"fire_resist": "火焰抗性",
	"cold_resist": "冰霜抗性",
	"poison_resist": "毒素抗性",
	"lightning_resist": "闪电抗性",
	"max_resource": "最大资源",
	"resource_regen": "资源回复",
	"skill_cost_reduction": "技能减耗",
	"cooldown_reduction": "冷却缩减",
	"pickup_radius": "拾取范围",
	"move_speed": "移动速度",
	"magic_find": "掉落幸运",
	"xp_gain": "经验获取",
	"gold_gain": "金币获取",
	"thorns": "荆棘反伤",
	"life_on_hit": "生命偷取",
	"kill_heal": "击杀回复",
	"armor_pierce": "护甲穿透",
	"life_steal": "生命吸血",
	"damage_taken": "受伤加成",
	"regen_pct_hp": "生命回复率",
	"shield_pct_hp": "护盾",
}

## 以百分号渲染的键（其余按整数渲染）
const PCT_KEYS: Array[String] = [
	"crit_chance", "crit_damage", "attack_speed", "elemental_damage",
	"dodge", "block_chance", "fire_resist", "cold_resist", "poison_resist",
	"lightning_resist", "resource_regen", "skill_cost_reduction",
	"cooldown_reduction", "move_speed", "magic_find", "xp_gain", "gold_gain",
	"thorns", "life_on_hit", "armor_pierce", "life_steal", "damage_taken",
	"regen_pct_hp", "shield_pct_hp",
]

var _rows: VBoxContainer = null
var _row_count: int = 0

## 标题标签（show_stats 可带职业名刷新）
var _title: Label = null

## 职业 id（标题配色用；默认战士金）
var _class_id: String = GameConstants.CLASS_DEFAULT

## 最近一次渲染用的原始属性字典（= `StatCalculator.calculate()` 的输出）
var last_stats: Dictionary = {}

## 最近一次渲染出来的文本（键 → 显示串），供验证脚本断言「真的不是 0」
var rendered_values: Dictionary = {}


func _ready() -> void:
	_build_ui()
	show_stats({})


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

	var title := Label.new()
	title.text = "角色属性"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	_title = title
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "基础属性 = 职业成长 + 装备 + 词缀 · 实时结算"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[7])
	vb.add_child(hint)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("v_separation", 2)
	vb.add_child(_rows)


## 渲染属性总表。`stats` 必须是 `StatCalculator.calculate()` 的输出。
## 布局（步骤 5 修视口裁切）：31 键 × 2 列 ≈ 31 行，高度超 640×360 视口会被切掉
## 顶部几行（实测裁到「暴击率」）→ 改为每行 3 项（HBox），11 行 × ~17px 全屏可见。
## `class_display`（2026-09-22）：职业显示名，非空时标题变为「职业 · 角色属性」。
## `class_id`（步骤 5）：标题配色跟随职业色。
func show_stats(stats: Dictionary, class_display: String = "", class_id: String = "") -> void:
	if not class_id.is_empty():
		_class_id = class_id
	if _title != null:
		_title.text = "角色属性" if class_display.is_empty() else "%s · 角色属性" % class_display
		var cls: Dictionary = ConfigLoader.classes.get(_class_id, {})
		_title.add_theme_color_override("font_color",
			Color(String(cls.get("color", "F5D77A"))))
	last_stats = stats
	rendered_values.clear()
	_row_count = 0
	if _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()
	var row: HBoxContainer = null
	var idx := 0
	for key in StatCalculator.FINAL_KEYS:
		if idx % 3 == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			_rows.add_child(row)
		var val := float(stats.get(key, 0.0))
		var text := _fmt(key, val)
		rendered_values[key] = text
		var stat := HBoxContainer.new()
		stat.add_theme_constant_override("separation", 6)
		stat.custom_minimum_size = Vector2(108, 0)
		row.add_child(stat)
		var name_l := Label.new()
		name_l.text = String(LABELS.get(key, key))
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[8])
		stat.add_child(name_l)
		var val_l := Label.new()
		val_l.text = text
		val_l.add_theme_font_size_override("font_size", 12)
		val_l.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat.add_child(val_l)
		idx += 1
	_row_count = StatCalculator.FINAL_KEYS.size()


## 面板行数（= `StatCalculator.FINAL_KEYS` 的长度）
func row_count() -> int:
	return _row_count


func _fmt(key: String, val: float) -> String:
	if key in PCT_KEYS:
		return "%.1f%%" % val
	if absf(val - roundf(val)) < 0.01:
		return str(int(roundf(val)))
	return "%.1f" % val
