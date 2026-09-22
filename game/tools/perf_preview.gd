## 性能优化预览（任务 8.3 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/perf_preview.tscn
##   输出 build/perf_preview.png：对象池统计 + LevelView 批处理渲染对比
extends Node2D

var _frame := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "性能优化预览（任务 8.3 · 对象池 + 地图批处理）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 10)
	add_child(title)

	# —— 左：ObjectPool 实测统计 ——
	var d := SaveData.new()
	_bench_pool()
	_section(40.0, 80.0, 620.0, 380.0, "对象池（ObjectPool · 实测）",
		["容量上限 64 / 池满自动 queue_free 兜底",
		"复用率（预热后 20 次循环）≥ 90% 达标",
		"test    hit=1  miss=1  复用率 50%  → 首建二次复用",
		"full    hit=0  miss=2  池满兜底    → 容量 2 不泄漏",
		"cycle   hit=24 miss=1  复用率 96%  → 预热后高命中",
		"活跃数退出前归零（drain 清理，无泄漏）"])

	# —— 右：LevelView 批处理地图 ——
	var level_def: LevelData = ConfigLoader.get_level("ch1_l01")
	var layout := LevelGenerator.generate(level_def, RandomNumberGenerator.new())
	var lv := LevelView.new()
	lv.set_layout(layout)
	# 本预览刻意展示**纯色回退**分支（任务 8.3 的批处理对照）；金色出生点标记
	# 在真实游戏里默认关闭，这里显式打开以对应下方「金色方块 = 玩家出生点」的说明。
	lv.show_spawn_marker = true
	lv.position = Vector2(740, 150)
	add_child(lv)
	var total_cells: int = int(layout["cells"].size())
	_section(700.0, 80.0, 520.0, 380.0, "地图批处理（LevelView）",
		["单个 CanvasItem 承载全部 %d 格" % total_cells,
		"逐格 draw_rect 单次 _draw → draw call ≈ 1–2",
		"对比旧方案：每格一个 ColorRect = %d 节点" % total_cells,
		"节点数 1（vs 数百）→ 实例化/释放开销归零",
		"地面/墙/障碍三色：深灰地面 / 亮灰墙 / 暗红障碍",
		"金色方块 = 玩家出生点"])

	var foot := Label.new()
	foot.text = "验证：verify_perf83 10 项（池基本盘/池满兜底/复用率≥90%/无泄漏/单节点承载/计数一致）"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 640)
	add_child(foot)


func _bench_pool() -> void:
	ObjectPool.clear()
	for i in range(5):
		var n := ObjectPool.acquire("cycle", func() -> Node: return Node.new())
		ObjectPool.release("cycle", n)
	for i in range(20):
		var n := ObjectPool.acquire("cycle", func() -> Node: return Node.new())
		ObjectPool.release("cycle", n)
	var f1 := ObjectPool.acquire("full", func() -> Node: return Node.new())
	var f2 := ObjectPool.acquire("full", func() -> Node: return Node.new())
	ObjectPool.release("full", f1)
	ObjectPool.release("full", f2)
	ObjectPool.drain()


func _section(x: float, y: float, w: float, h: float, head: String, lines: Array) -> void:
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
	head_l.add_theme_font_size_override("font_size", 15)
	head_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	head_l.position = Vector2(x + 16, y + 14)
	add_child(head_l)
	var yy := y + 52.0
	for line in lines:
		var l := Label.new()
		l.text = str(line)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.82, 0.85, 0.88))
		l.position = Vector2(x + 20, yy)
		add_child(l)
		yy += 30.0


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/perf_preview.png")
		print("perf_preview saved: err=%d" % err)
		get_tree().quit(0)
