## 主菜单场景（集成层阶段 1 · 任务 7.1 面板的挂载点）
##
## 结构：本节点是 `CanvasLayer`（UI 层），唯一子节点是 `MainMenuPanel`
## （面板在 `_ready()` 里自建全部子控件，所以 `.tscn` 只挂脚本、不摆节点）。
##
## 职责：
##   1. 把 `MainMenuPanel` 的三个回调接到真实流程（开始 / 设置 / 退出）
##   2. 无存档 → 直接建新档进据点；有存档 → 弹选档列表
##   3. 设置 → 叠一层 `SettingsPanel`
##
## 数据源：`SaveManager`（账号概览 `get_account_data()` + 槽位 `get_all_slot_infos()`）。
## 场景切换一律走 `SceneManager`（带淡入淡出），本脚本不直接碰 `get_tree().change_scene_*`。
extends CanvasLayer

# ── 封面背景可調常量（依 gstack-designer 規範 v1.0 §1；只改數值不改結構）──────
## 封面使用的生態背景（ch1 → forest，見 `TileAtlas.biome_for_level`）。
const COVER_BIOME: String = "forest"
## 背景壓暗疊層：色取色板內 `0B0D10`（`UI_PANEL_BG`），alpha = 128/255（規範 §1.1）。
const COVER_DIM_COLOR: Color = Color("0B0D10")
const COVER_DIM_ALPHA: float = 128.0 / 255.0
## backdrop 素材缺失時的回退底色（同為色板內近黑，規範 §8.15）。
const COVER_FALLBACK_BG: Color = Color("0B0D10")
## ── 封面裝飾層（2026-09-22 首頁定稿）──────────────────────────────────────
## 豆包原創像素素材已補入：戰士立繪（首頁展示；弓/法留步驟 2 角色選擇）、
## 壁掛火把 ×2（flame flicker + 火星粒子）、右下版本欄、標題浮動。
## 素材缺失 → 各裝飾節點安全跳過，不影響流程（與 `UISkin` 降級契約一致）。

var _panel: MainMenuPanel = null

## 当前浮层（选档 / 设置）；同一时刻最多一个
var _overlay: Control = null

## 浮层里装内容的 VBoxContainer（`_make_overlay` 填）
var _overlay_box: VBoxContainer = null


func _ready() -> void:
	_build_backdrop()
	_build_atmosphere()
	_panel = MainMenuPanel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.on_start = _on_start
	_panel.on_settings = _on_settings
	_panel.on_quit = _on_quit
	add_child(_panel)

	# 動態氛圍（標題浮動 / 火把 flicker）純視覺：無頭回歸裡跳過，保持斷言確定性
	if DisplayServer.get_name() != "headless":
		_start_ambient_tweens()

	# 启动标记：冒烟测试 / CI 靠这行确认「真的进到主菜单了」
	var acc: Dictionary = SaveManager.get_account_data()
	print("[MainMenu] 主菜单就绪：账号 Lv.%d · 金币 %d · 已有存档 %s" % [
		int(acc.get("level", 1)), int(acc.get("gold", 0)),
		"是" if SaveManager.has_any_save() else "否"])
	GameLog.info("进入主菜单：账号 Lv.%d" % int(acc.get("level", 1)))


## 接收 SceneManager 递过来的载荷（主菜单通常为空）
func on_scene_entered(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	print("[MainMenu] 收到载荷：", payload)


# =============================================================================
# 封面背景（UI 素材接入 §5.3）
# =============================================================================

## 鋪生態背景 + 壓暗疊層。素材缺失 → 安全降級為純黑底（不崩、不黑屏之外的副作用）。
##
## 結構：`Bg`（tscn 內既有 ColorRect）= 壓暗疊層；本函式在它**下層**插一張
## `TextureRect`（backdrop 640×360 原尺寸鋪滿視口）。素材不存在時只把 `Bg` 設回純黑。
func _build_backdrop() -> void:
	var bg := get_node_or_null("Bg") as ColorRect
	## 優先序（美術全為豆包原創像素）：
	##   ① 包的主菜單背景 `UISkin.TEX.main_menu_bg`（暗色地牢 + 紅星空，640×360）
	##      —— 用戶原話「ui素材優先用這裡面的」，且構圖比紫色山景更貼合暗黑基調。
	##   ② 生態 backdrop（forest）。
	##   ③ 純黑（`Bg` 底色）。
	var tex := UISkin.texture("main_menu_bg")
	if tex == null:
		tex = UISkin.backdrop_texture(COVER_BIOME)
	if tex == null:
		if bg != null:
			bg.color = COVER_FALLBACK_BG
		return

	var backdrop := TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.texture = tex
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)  # 置底：畫在 `Bg` 之下

	if bg != null:
		bg.color = Color(COVER_DIM_COLOR.r, COVER_DIM_COLOR.g, COVER_DIM_COLOR.b, COVER_DIM_ALPHA)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE


# =============================================================================
# 封面裝飾層（2026-09-22 首頁定稿）
# =============================================================================

## 戰士立繪落點（畫面左下，墊在面板下層；右緣被面板輕微遮住形成層次）。
const PORTRAIT_POS: Vector2 = Vector2(4, 108)
## 左右壁掛火把落點（火把精靈 80×80 原尺寸）。
const TORCH_LEFT_POS: Vector2 = Vector2(24, 24)
const TORCH_RIGHT_POS: Vector2 = Vector2(536, 24)
## 右下版本欄（11px，色板內 `B3BCC9`；規範 §7.7 白名單）。
const VERSION_TEXT: String = "v0.1.0 · 七傳說開發版"

## 裝飾層總入口：任一素材缺失 → 該裝飾安全跳過（不崩、不影響流程）。
func _build_atmosphere() -> void:
	_build_portrait()
	_build_torches()
	_build_version_label()


## 戰士立繪：貼在背景與面板之間，腳踩視口底邊。
func _build_portrait() -> void:
	var tex := UISkin.texture("portrait_warrior")
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.name = "HeroPortrait"
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = PORTRAIT_POS
	tr.size = Vector2(tex.get_width(), tex.get_height())
	add_child(tr)


## 壁掛火把 ×2：flicker（pivot 中心縮放脈動）+ 火苗處火星粒子。
func _build_torches() -> void:
	var tex := UISkin.texture("torch")
	if tex == null:
		return
	var tsize := Vector2(tex.get_width(), tex.get_height())
	var specs: Array = [
		{"pos": TORCH_LEFT_POS, "flip": false},
		{"pos": TORCH_RIGHT_POS, "flip": true},
	]
	for i in specs.size():
		var s: Dictionary = specs[i]
		var tr := TextureRect.new()
		tr.name = "Torch%d" % i
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.position = s["pos"]
		tr.size = tsize
		if bool(s["flip"]):
			tr.flip_h = true
		tr.pivot_offset = tsize * 0.5
		add_child(tr)

		# 火星粒子：從火苗處（火把精靈頂部中央）上升、金→橙→透明
		var p := CPUParticles2D.new()
		p.name = "TorchEmbers%d" % i
		p.texture = _make_ember_texture()
		p.amount = 10
		p.lifetime = 1.1
		p.preprocess = 0.5
		p.emitting = true
		p.one_shot = false
		p.direction = Vector2(0, -1)
		p.spread = 30.0
		p.gravity = Vector2(0, -16)
		p.initial_velocity_min = 16.0
		p.initial_velocity_max = 42.0
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.7
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		g.colors = PackedColorArray([
			Color("F7DD8A"), Color("E08A3C"), Color(0.6, 0.2, 0.08, 0.0),
		])
		p.color_ramp = g
		p.position = Vector2(s["pos"]) + Vector2(tsize.x * 0.5, 22.0)
		add_child(p)

		# flicker：縮放脈動，錯開相位更像真實火焰跳動
		if DisplayServer.get_name() != "headless":
			var base := Vector2.ONE
			var t := create_tween()
			t.set_loops()
			t.tween_interval(float(i) * 0.4)
			t.tween_property(tr, "scale", base * 1.07, 0.30) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t.tween_property(tr, "scale", base, 0.36) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 8×8 白色圓點粒子貼圖（火星）
func _make_ember_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in range(8):
		for x in range(8):
			var dist := Vector2(x - 3.5, y - 3.5).length()
			var a := clampf(1.0 - dist / 4.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## 右下角版本欄
func _build_version_label() -> void:
	var lb := Label.new()
	lb.name = "VersionLabel"
	lb.text = VERSION_TEXT
	lb.add_theme_font_size_override("font_size", 11)
	lb.add_theme_color_override("font_color", Color("B3BCC9"))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lb.offset_left = -152.0
	lb.offset_top = -28.0
	lb.offset_right = -6.0
	lb.offset_bottom = -8.0
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(lb)


## 標題浮動：TitleBlock 上下 ±1.5px 正弦呼吸（純視覺；無頭跳過）
func _start_ambient_tweens() -> void:
	var tb := _panel.get_node_or_null("TitleBlock") as Control
	if tb == null:
		return
	var base_y: float = tb.position.y
	var t := create_tween()
	t.set_loops()
	t.tween_interval(0.4)
	t.tween_property(tb, "position:y", base_y + 1.5, 1.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(tb, "position:y", base_y - 1.5, 1.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# =============================================================================
# 三个按钮的去向
# =============================================================================

func _on_start() -> void:
	if SaveManager.has_any_save():
		_show_slot_picker()
	else:
		# 2026-09-22 步骤 2：无存档 → 先选职业再建档
		_show_class_select()


func _on_settings() -> void:
	_clear_overlay()
	# 步骤 7：SettingsPanel 是全屏浮层自管理（含标题/关闭按钮），
	# 不再套 _make_overlay —— 旧版 520×460 + overlay 标题/边距总高超 560px 被 360 视口裁掉。
	var sp := SettingsPanel.new()
	sp.on_close = _clear_overlay
	add_child(sp)
	_overlay = sp


func _on_quit() -> void:
	get_tree().quit()


# =============================================================================
# 存档流程
# =============================================================================

## 角色选择浮层（步骤 2）：选职业 → 确认 → 建档进据点。
func _show_class_select() -> void:
	_clear_overlay()
	var sp := CharacterSelectPanel.new()
	sp.on_confirm = func(class_id: String) -> void:
		_start_new_character(class_id)
	sp.on_cancel = _clear_overlay
	add_child(sp)
	_overlay = sp


## 在第一个空槽建新档（带职业）并进据点
func _start_new_character(class_id: String) -> void:
	var slot := _first_free_slot()
	if slot < 0:
		_toast("存档槽已满（上限 %d 个）" % GameConstants.SAVE_MAX_SLOTS)
		return
	var data := SaveManager.create_new_slot(slot, class_id)
	if data == null:
		_toast("新建存档失败：%s" % SaveManager.last_error)
		return
	_enter_hub()


## 列出已有存档，点一条即读档进据点
func _show_slot_picker() -> void:
	_clear_overlay()
	_make_overlay("选择存档")
	var box: VBoxContainer = _overlay_box

	for info in SaveManager.get_all_slot_infos():
		if not bool(info.get("exists", false)):
			continue
		var slot := int(info["slot"])
		var label := "槽位 %d · %s · Lv.%d · %s" % [
			slot,
			String(info.get("display_name", "")),
			int(info.get("account_level", 1)),
			_format_play_time(float(info.get("play_time_seconds", 0.0))),
		]
		if bool(info.get("corrupted", false)):
			label += "（已损坏，将尝试备份回滚）"
		box.add_child(_make_btn(label, func() -> void: _load_slot(slot)))

	box.add_child(_make_btn("新建角色", _show_class_select))
	box.add_child(_make_btn("返回", _clear_overlay))


## 读档（带底材/词缀模板回填）并进据点
func _load_slot(slot: int) -> void:
	if SaveManager.load_from_slot_resolved(slot) == null:
		_toast("读档失败：%s" % SaveManager.last_error)
		return
	_enter_hub()


## 进据点。`hub.tscn` 由阶段 2 提供；若尚不存在，SceneManager 会 push_error 并中止。
func _enter_hub() -> void:
	SceneManager.change_to_hub()


# =============================================================================
# 浮层与工具
# =============================================================================

func _first_free_slot() -> int:
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if not SaveManager.slot_exists(i):
			return i
	return -1


## 居中浮层：半透明底 + 居中面板 + 一个 VBoxContainer（内容塞进 `_overlay_box`）
func _make_overlay(title: String) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	box.add_child(head)

	add_child(root)
	_overlay = root
	_overlay_box = box


func _make_btn(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(360, 40)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(cb)
	AudioManager.hook_click(btn)
	return btn


func _clear_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_overlay_box = null


func _toast(msg: String) -> void:
	EventBus.notify(msg, Color("E8573F"))


func _format_play_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]
