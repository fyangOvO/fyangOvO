## 工具：capture_rune_codex.gd（符文圖標 v2「48×48 石板底座」驗收；**非玩法**）
##
## 用法（**必須去掉 `--headless`**，否則沒有渲染）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_rune_codex.tscn
## 產出：`D:/七傳說/deliverables/gstack/c_review_shot/rune-*.png`
##
## 驗收重點（對應 2026-09-30 符文圖標 v2 換裝）：
##   ① 24 張 `UISkin.rune_icon()` 貼圖**真的是 48×48**（不是 32、不是 null）
##      —— `texture()` 缺檔會**靜默回 null**，只看代碼永遠看不出來
##   ② 圖鑑格子**內容區恆 48×48**：未選中（邊框 1px）與選中（邊框 2px）兩態都不縮
##      —— `StyleBoxFlat` 內容邊距預設 = 邊框寬，不顯式指定就會隨選中狀態跳
##   ③ 目視：石板底座 + 高精細符文符號真的顯示（抓圖 + 4× 最近鄰放大供逐像素檢視）
##
## ⚠️ 只用測試槽位 7（跑完刪除），**不碰玩家存檔**。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/c_review_shot"
const TEST_SLOT: int = 7
## 期望的圖標邊長（= `rune_codex_panel.CELL` - 2 × `CELL_PAD`）
const EXPECT: float = 48.0
var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 90.0)
	print("===== 符文圖鑑 v2（48×48 石板底座）驗收 =====")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless", DisplayServer.get_name() != "headless")

	var ids: Array[String] = []
	for k in ConfigLoader.runes.keys():
		ids.append(String(k))
	ids.sort()
	_ok("符文條數 = 24（實際 %d）" % ids.size(), ids.size() == 24)

	# ---- ① 貼圖尺寸（最容易被「靜默 null」騙過的一步）----
	var bad: int = 0
	for rid in ids:
		var t := UISkin.rune_icon(rid)
		if t == null:
			print("  [FAIL] %s → null（UISkin 表鍵名或檔名不符）" % rid)
			bad += 1
		elif t.get_size() != Vector2(EXPECT, EXPECT):
			print("  [FAIL] %s → %s" % [rid, t.get_size()])
			bad += 1
	_ok("24 張貼圖皆為 48×48", bad == 0)

	# ---- ② 面板幾何 ----
	var panel := RuneCodexPanel.new()
	add_child(panel)
	panel.position = Vector2(20, 20)
	await get_tree().process_frame
	panel.bind(ids, 20)
	await get_tree().process_frame
	await get_tree().process_frame

	var grid := panel.find_child("RuneGrid", true, false) as GridContainer
	_ok("找到符文格網且為 24 格", grid != null and grid.get_child_count() == 24)

	# 兩態都必須：內容邊距 == CELL_PAD、內容區 == 48（與邊框寬解耦）
	var geo_bad: int = 0
	for sel in [false, true]:
		var sb: StyleBoxFlat = panel._cell_box(sel, false, true)
		var bw: int = sb.get_border_width(SIDE_LEFT)
		var cm: float = sb.get_content_margin(SIDE_LEFT)
		var content: float = RuneCodexPanel.CELL - cm * 2.0
		var tag := "选中  " if sel else "未选中"
		if not is_equal_approx(cm, RuneCodexPanel.CELL_PAD) or not is_equal_approx(content, EXPECT):
			print("  [FAIL] %s：边框 %dpx / 内容边距 %.0fpx ⇒ 内容区 %.0f" % [tag, bw, cm, content])
			geo_bad += 1
		else:
			print("  [OK]   %s：边框 %dpx / 内容边距 %.0fpx ⇒ 内容区 %.0f×%.0f（1:1）"
				% [tag, bw, cm, content, content])
	_ok("格子内容区恒 48×48（未选中 / 选中两态）", geo_bad == 0)

	# 真實佈局後的按鈕尺寸也要對得上（防「設了常量但容器給別的值」）
	var real_bad: int = 0
	for c in grid.get_children():
		var b := c as Button
		var sb := b.get_theme_stylebox("normal")
		var cw: float = b.size.x - sb.get_content_margin(SIDE_LEFT) - sb.get_content_margin(SIDE_RIGHT)
		if not is_equal_approx(cw, EXPECT):
			print("  [FAIL] %s 實際內容寬 %.1f（按鈕寬 %.1f）" % [b.name, cw, b.size.x])
			real_bad += 1
	_ok("佈局後 24 格實際內容寬皆 48", real_bad == 0)

	await _shot("rune-1-图鉴-全解锁.png")
	await _zoom_shot(grid, "rune-2-图鉴格网-4x.png")

	# ---- ③ 选中一个符文：详情图标也必須 48×48 ----
	grid.get_child(0).emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame

	var icons: Array[TextureRect] = []
	for n in _walk(panel):
		if n is TextureRect:
			icons.append(n as TextureRect)
	var ok_ico := icons.size() == 1 and icons[0].custom_minimum_size == Vector2(EXPECT, EXPECT)
	if not ok_ico:
		for i in icons:
			print("  [FAIL] 详情 TextureRect custom_minimum_size = %s" % i.custom_minimum_size)
	_ok("详情图标 48×48", ok_ico)
	await _shot("rune-3-图鉴-选中详情.png")

	if SaveManager.slot_exists(TEST_SLOT):
		SaveManager.delete_slot(TEST_SLOT)
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _shot(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s" % [OUT_DIR, fname])
	_ok("截圖 %s（err=%d）" % [fname, err], err == OK)


## 把格網區域裁出來 4× 最近鄰放大 —— 用來逐像素目視「有沒有非整數縮放的糊邊」
func _zoom_shot(ctrl: Control, fname: String) -> void:
	var r := ctrl.get_global_rect()
	var img := get_viewport().get_texture().get_image()
	var x := maxi(0, int(r.position.x) - 2)
	var y := maxi(0, int(r.position.y) - 2)
	var w := mini(img.get_width() - x, int(r.size.x) + 4)
	var h := mini(img.get_height() - y, int(r.size.y) + 4)
	var crop := img.get_region(Rect2i(x, y, w, h))
	crop.resize(w * 4, h * 4, Image.INTERPOLATE_NEAREST)
	var err := crop.save_png("%s/%s" % [OUT_DIR, fname])
	_ok("放大截圖 %s（%d×%d→%d×%d，err=%d）"
		% [fname, w, h, w * 4, h * 4, err], err == OK)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
