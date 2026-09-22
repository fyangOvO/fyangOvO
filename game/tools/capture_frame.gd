## 窗口化冒烟 + 三场景真渲染抓图（任务 10.7 / 10.11 · 开发用，不属于游戏玩法）
##
## 用法（**必须去掉 `--headless`** —— 无头模式下没有渲染，抓不到画面）：
##   godot --path "D:/七傳說/game" res://tools/capture_frame.tscn
##   godot --path "D:/七傳說/game" res://tools/capture_frame.tscn -- --tag tileswap
##
## 产出（`deliverables/gstack/`）：
##   `screenshot-main-menu[-<tag>].png`            主菜单
##   `screenshot-hub[-<tag>].png`                  据点（含选关列表）
##   `screenshot-<level>-zoom<N>x[-<tag>].png`     关卡（2× = 规范值，3× = 对照）
##
## `--tag <值>` 给文件名加后缀，避免覆盖既有证据图（与 `capture_ui_page.gd` 同一约定）。
##
## 为什么需要它：
##   `--verify` / 全部 `verify_*` 都是无头跑，**证明不了「画面是对的」**。
##   本工具实测抓到过 3 个无头测试永远看不见的问题：
##     ① 相机未设 limit ⇒ 地图边缘露出纯黑 void
##     ② `player_spawn = carved[0]` 实为房间角落（注释却写「房间中心」）⇒ 开局贴墙
##     ③ 相机缩放 2× 与 3× 的战术视野差异（一屏 16 个敌人 vs 1 个）
##   凡涉及「玩家用眼睛看的东西」，都必须真渲染一帧才算验证过。
##
## ⚠️ 只做两件事：渲染一帧 + 存 PNG。不碰任何玩法代码。
extends Node2D

const MENU_SCENE: PackedScene = preload("res://scenes/main/main_menu.tscn")
const HUB_SCENE: PackedScene = preload("res://scenes/main/hub.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables/gstack"

const LEVEL_ID: String = "ch1_l01"

## 要抓的缩放档位：2× = 现行规范值（`GameConstants.CAMERA_ZOOM_BASE`），3× = 对照
const ZOOM_STEPS: Array[float] = [2.0, 3.0]

var _fail: int = 0
var _tag: String = ""


func _ready() -> void:
	# 看门狗给足时间：三个场景 + 真渲染 + 存盘比无头慢，但也不该超过 150s
	VerifyWatchdog.arm(get_tree(), 150.0)
	_parse_tag()
	_run()


## 消费 `--tag <值>`（其余参数忽略），给输出文件加后缀
func _parse_tag() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--tag" and i + 1 < args.size():
			_tag = args[i + 1]
			i += 2
			continue
		i += 1


func _run() -> void:
	print("===== 窗口化冒烟 + 三场景抓图 =====")
	_ok("渲染驱动不是 headless（否则抓不到画面）",
		DisplayServer.get_name() != "headless")

	await _capture_main_menu()
	await _capture_hub()
	await _capture_level()

	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# ① 主菜单
# =============================================================================

func _capture_main_menu() -> void:
	print("--- ① 主菜单 ---")
	var menu := MENU_SCENE.instantiate()
	# ⚠️ 必须 call_deferred：`_ready()` 期间 root 正在 setup children
	get_tree().root.add_child.call_deferred(menu)
	await _frames(3)
	await _settle()

	# 主菜单是 CanvasLayer，抓的是整视口
	_ok("主菜单已挂载到场景树", menu.is_inside_tree())

	# 布局诊断：`set_anchors_preset(PRESET_CENTER)` 只改 anchor 不改 offset，
	# 控件会从屏幕中心点向右下扩展（表现为整体偏右）。这里把实际 rect 打出来，
	# 让「偏了」这件事有可对账的数字，而不是靠肉眼看图猜。
	# 节点层级：menu → [Bg（来自 .tscn）, MainMenuPanel] → CenterContainer → VBoxContainer。
	# ⚠️ 必须一路走到**真正的 VBox** 再断言：CenterContainer 是 FULL_RECT 铺满的，
	#    拿它断言「居中」恒真 —— 那是弱断言，会把 bug 伪装成通过。
	var vp := get_viewport_rect().size
	var panel: Control = null
	for c in menu.get_children():
		if c is MainMenuPanel:
			panel = c
			break
	var box: Control = _first_vbox(panel)
	if box != null:
		var r := box.get_global_rect()
		print("[Diag] 视口 %s · 内容块 rect %s · 块中心 x=%.1f（期望 %.1f）"
			% [str(vp), str(r), r.position.x + r.size.x * 0.5, vp.x * 0.5])
		_ok("主菜单内容块水平居中（块中心 x=%.1f，视口中心 %.1f）"
				% [r.position.x + r.size.x * 0.5, vp.x * 0.5],
			absf(r.position.x + r.size.x * 0.5 - vp.x * 0.5) <= 2.0)
		_ok("主菜单内容块没有超出视口左边界（rect.x=%.1f）" % r.position.x,
			r.position.x >= 0.0)
	else:
		_ok("找到主菜单内容块（VBoxContainer）", false)

	await _shot("screenshot-main-menu%s.png" % _suffix())

	menu.queue_free()
	await _frames(3)


# =============================================================================
# ② 据点（需要存档，否则 `_enter()` 会退回主菜单）
# =============================================================================

func _capture_hub() -> void:
	print("--- ② 据点 ---")
	if SaveManager.current_data == null:
		SaveManager.current_slot = 0
		var data := SaveManager.create_new_slot(0)
		_ok("据点前置：新建存档成功（否则据点数不到选关列表）", data != null)

	var hub := HUB_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(hub)
	await _frames(3)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await _settle()

	_ok("据点已挂载到场景树", hub.is_inside_tree())
	# 据点必须在树上「活着」——无档时它会立刻 change_scene 回主菜单，
	# 那种情况下这帧抓到的其实是残留画面，截图会骗人
	_ok("据点没有退回主菜单（is_queued_for_deletion = %s）" % str(hub.is_queued_for_deletion()),
		not hub.is_queued_for_deletion())

	# 关卡按钮布局诊断：确认按钮是否被拉伸到列表宽度（文字居中依赖这个）
	var btn := hub.find_child("ch1_l01", true, false) as Button
	var list: Control = hub._level_list
	if btn != null:
		var br := btn.get_global_rect()
		print("[Diag] 关卡按钮 %s rect %s · 文字「%s」" % [btn.name, str(br), btn.text])
		_ok("关卡按钮被拉伸到列表宽度（按钮宽 %.0f，列表宽 %.0f）"
				% [br.size.x, list.size.x if list != null else -1.0],
			list != null and absf(br.size.x - list.size.x) <= 2.0)
	else:
		_ok("找到关卡按钮 ch1_l01（据点选关列表已填充）", false)

	await _shot("screenshot-hub%s.png" % _suffix())

	hub.queue_free()
	await _frames(3)


# =============================================================================
# ③ 关卡（含相机缩放对照）
# =============================================================================

func _capture_level() -> void:
	print("--- ③ 关卡 ---")
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _settle()

	_ok("相机缩放 = CAMERA_ZOOM_BASE（%s）" % str(GameConstants.CAMERA_ZOOM_BASE),
		level._camera.zoom.is_equal_approx(GameConstants.CAMERA_ZOOM_BASE))
	_ok("关卡已构建（敌人 %d 个）" % level._alive.size(), not level._alive.is_empty())

	# 相机必须被限制在地图内，否则边缘处会露出地图外的纯黑 void（2026-09-18 实测发现）
	var map_w := int(level._layout.get("width", 0)) * LevelScene.TILE_PX
	var map_h := int(level._layout.get("height", 0)) * LevelScene.TILE_PX
	_ok("相机限制 = 地图边界（%d×%d，实际 R%d B%d）"
			% [map_w, map_h, level._camera.limit_right, level._camera.limit_bottom],
		level._camera.limit_right == map_w and level._camera.limit_bottom == map_h)
	print("[Capture] 玩家 HP %.0f / %.0f · 地图 %d×%d px · 出生格 %s"
		% [level._player.health.get_current_hp(), level._player.health.get_max_hp(),
			map_w, map_h, str(level._layout.get("player_spawn", Vector2i.ZERO))])

	for z in ZOOM_STEPS:
		level._camera.zoom = Vector2(z, z)
		# 相机跟随在 _process 里，改完要等它重新居中 + 重绘
		await _frames(5)
		await _shot("screenshot-%s-zoom%dx%s.png" % [LEVEL_ID, int(z), _suffix()])

	# 还原成规范值，避免留下被改过的状态（本工具本就一次性，纯属好习惯）
	level._camera.zoom = GameConstants.CAMERA_ZOOM_BASE


# =============================================================================
# 工具
# =============================================================================

## 等场景稳定：敌人就位、掉落光柱出现、HUD 文本刷出来
func _settle() -> void:
	await _frames(10)
	await get_tree().create_timer(0.6).timeout


## 深度优先找第一个 VBoxContainer（主菜单的内容块）
func _first_vbox(n: Node) -> Control:
	if n == null:
		return null
	for c in n.get_children():
		if c is VBoxContainer:
			return c
		var found := _first_vbox(c)
		if found != null:
			return found
	return null


## 文件名后缀（空 tag → 空串），与 capture_ui_page.gd 同一约定
func _suffix() -> String:
	return "" if _tag.is_empty() else "-" + _tag


## 抓当前视口存 PNG
func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	_ok("抓图 %s → %d×%d（err=%d）" % [fname, img.get_width(), img.get_height(), err],
		err == OK and img.get_width() > 0)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
