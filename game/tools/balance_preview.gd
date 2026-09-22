## 平衡性仿真预览（任务 8.4 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/balance_preview.tscn
##   输出 build/balance_preview.png：TTK 曲线（5 难度）+ 承伤秒数曲线
extends Node2D

var _frame := 0

# 与 verify_balance84 同口径
const MH_BASE := 100.7
const MH_GROWTH := 1.284
const MD_BASE := 5.61
const MD_GROWTH := 1.218
const DIFF_HP := 1.08
const DIFF_DMG := 1.23
const PD_BASE := 20.0
const PD_GROWTH := 1.30
const SKILL_MULT := 1.25
const PH_BASE := 500.0
const PH_GROWTH := 1.06
const HPS := 0.5


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "平衡性数值仿真（任务 8.4 · TTK 与承伤，20 关 × 5 难度）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 10)
	add_child(title)

	# —— 左：TTK 曲线（5 条难度线）——
	_chart(60.0, 90.0, 560.0, 360.0, "常规怪 TTK（秒）· 目标 [1, 8] · 不海绵化",
		func(l: int, d: int) -> float:
			return MH_BASE * pow(MH_GROWTH, l - 1) * pow(DIFF_HP, d) \
				/ (PD_BASE * pow(PD_GROWTH, l) * SKILL_MULT),
		["普通", "精英", "英雄", "梦魇I", "梦魇V"],
		[Color(0.35, 0.75, 0.45), Color(0.45, 0.65, 0.95), Color(0.95, 0.75, 0.35), Color(0.9, 0.5, 0.4), Color(0.95, 0.3, 0.3)])

	# —— 右：承伤秒数曲线 ——
	_chart(700.0, 90.0, 560.0, 360.0, "玩家承伤秒数（MaxHP / 怪DPS）· 梦魇<10s 可被秒",
		func(l: int, d: int) -> float:
			return PH_BASE * pow(PH_GROWTH, l) \
				/ (MD_BASE * pow(MD_GROWTH, l - 1) * pow(DIFF_DMG, d) * HPS),
		["普通", "精英", "英雄", "梦魇I", "梦魇V"],
		[Color(0.35, 0.75, 0.45), Color(0.45, 0.65, 0.95), Color(0.95, 0.75, 0.35), Color(0.9, 0.5, 0.4), Color(0.95, 0.3, 0.3)])

	var foot := Label.new()
	foot.text = "平衡报告：8/8 断言全过 — TTK 2.4–4.2s / 梦魇III-V 承伤<10s / 普通前5关>12s / 20关成长可见"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 640)
	add_child(foot)


func _chart(x: float, y: float, w: float, h: float, head: String, f: Callable, labels: Array, cols: Array) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09)
	sb.border_color = Color(0.35, 0.42, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sb)
	pc.position = Vector2(x, y)
	pc.size = Vector2(w, h)
	add_child(pc)
	var head_l := Label.new()
	head_l.text = head
	head_l.add_theme_font_size_override("font_size", 13)
	head_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	head_l.position = Vector2(x + 16, y + 10)
	add_child(head_l)

	# 计算数据范围
	var vals := {}
	var vmin := 9999.0
	var vmax := 0.0
	for d in range(5):
		var row := []
		for l in range(1, 21):
			var v: float = f.call(l, d)
			row.append(v)
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)
		vals[d] = row
	if vmax - vmin < 1.0:
		vmax = vmin + 1.0
	# 图区
	var gx := x + 60.0
	var gy := y + 70.0
	var gw := w - 90.0
	var gh := h - 130.0
	# 网格
	for i in range(5):
		var ly := gy + gh - gh * i / 4.0
		_draw_line(Vector2(gx, ly), Vector2(gx + gw, ly), Color(0.2, 0.22, 0.26), 1.0)
		var lv := vmin + (vmax - vmin) * i / 4.0
		var ll := Label.new()
		ll.text = "%d" % int(lv)
		ll.add_theme_font_size_override("font_size", 10)
		ll.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
		ll.position = Vector2(x + 14, ly - 8)
		add_child(ll)
	for i in range(5):
		var lx := gx + gw * i / 4.0
		_draw_line(Vector2(lx, gy), Vector2(lx, gy + gh), Color(0.2, 0.22, 0.26), 1.0)
	# 曲线
	for d in range(5):
		var pts := PackedVector2Array()
		for l in range(20):
			var v: float = vals[d][l]
			var px := gx + gw * l / 19.0
			var py := gy + gh - gh * (v - vmin) / (vmax - vmin)
			pts.append(Vector2(px, py))
		for i in range(pts.size() - 1):
			_draw_line(pts[i], pts[i + 1], cols[d], 2.0)
	# 图例
	var lx0 := x + 16.0
	var ly0 := y + h - 34.0
	for d in range(5):
		_draw_rect(Rect2(lx0, ly0, 14, 10), cols[d])
		var ll := Label.new()
		ll.text = labels[d]
		ll.add_theme_font_size_override("font_size", 10)
		ll.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		ll.position = Vector2(lx0 + 18, ly0 - 4)
		add_child(ll)
		lx0 += 96.0


func _draw_line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	var line := Line2D.new()
	line.add_point(a)
	line.add_point(b)
	line.width = w
	line.default_color = c
	add_child(line)


func _draw_rect(r: Rect2, c: Color) -> void:
	var cr := ColorRect.new()
	cr.color = c
	cr.position = r.position
	cr.size = r.size
	add_child(cr)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/balance_preview.png")
		print("balance_preview saved: err=%d" % err)
		get_tree().quit(0)
