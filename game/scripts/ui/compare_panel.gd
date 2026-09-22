## 装备对比面板 UI（任务 3.7）
##
## 两列对比表：新装备（穿戴后）vs 旧装备（当前）。每行一个统计键，
## 升序绿色 / 降序红色 / 持平灰色，末行显示差异汇总。
## 数据来源：EquipmentCompare.compare()。
class_name ComparePanel
extends PanelContainer

var _title_label: Label = null
var _rows_box: VBoxContainer = null


func _ready() -> void:
	_build_ui()


func show_compare(new_item: EquipmentInstance, old_item: EquipmentInstance, context: String = "") -> void:
	if _title_label == null:
		_build_ui()
	var rows := EquipmentCompare.compare(new_item, old_item)
	_title_label.text = "装备对比%s" % ((" · " + context) if not context.is_empty() else "")
	# 清空旧行
	for c in _rows_box.get_children():
		c.queue_free()
	var up := 0
	var down := 0
	for row in rows:
		_rows_box.add_child(_make_row(row))
		if int(row["delta_type"]) > 0:
			up += 1
		elif int(row["delta_type"]) < 0:
			down += 1
	var summary := Label.new()
	summary.add_theme_font_size_override("font_size", 11)
	var up_color := GameConstants.PALETTE_NEUTRAL[9]
	var down_color := Color(0.85, 0.45, 0.45)
	summary.add_theme_color_override("font_color", up_color)
	summary.text = "▲ 提升 %d 项 · ▼ 降低 %d 项 · 差异合计 %s" % [
		up, down, _fmt(_sum_diff(rows))]
	_rows_box.add_child(summary)


func _build_ui() -> void:
	var vb := VBoxContainer.new()
	add_child(vb)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[8])
	vb.add_child(_title_label)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	vb.add_child(_rows_box)


func _make_row(row: Dictionary) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	var ov: float = float(row["old_val"])
	var nv: float = float(row["new_val"])
	var diff: float = float(row["diff"])
	var pct := "%" if bool(row["is_pct"]) else ""
	var dt: int = int(row["delta_type"])
	var color := GameConstants.PALETTE_NEUTRAL[7]
	if dt > 0:
		color = Color(0.5, 0.85, 0.55)
	elif dt < 0:
		color = Color(0.85, 0.45, 0.45)
	label.add_theme_color_override("font_color", color)
	label.text = "%s：%s → %s%s  (%s%+0.1f%s)" % [
		row["label"],
		_fmt(ov), _fmt(nv), pct,
		"▲ " if dt > 0 else ("▼ " if dt < 0 else "· "),
		diff, pct,
	]
	return label


func _sum_diff(rows: Array[Dictionary]) -> float:
	var s := 0.0
	for r in rows:
		if int(r["delta_type"]) != 0:
			s += absf(float(r["diff"]))
	return s


func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(int(roundf(v)))
	return "%.1f" % v
