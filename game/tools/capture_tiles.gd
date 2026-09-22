## 三生物群系瓦片渲染真渲染取证（任务 8.3 后续 · 开发用，不属于游戏玩法）
##
## 为什么需要它：`capture_frame.gd` 把 `LEVEL_ID` 硬编码成 `ch1_l01`，只能证明
## **森林**一章的画面是对的。火山 / 霜渊两章的图集若没接上，无头测试一样全绿
## （`verify_tiles` 只证明图集能取到、能画，证明不了「画出来是那张图」）。
## 本工具按章节代表关逐关真渲染一帧并存 PNG，让三套图集都有像素级证据。
##
## 用法（**必须去掉 `--headless`** —— 无头模式没有渲染）：
##   godot --path "D:/七傳說/game" res://tools/capture_tiles.tscn
##   godot --path "D:/七傳說/game" res://tools/capture_tiles.tscn -- ch2_l07 ch3_l14
##   godot --path "D:/七傳說/game" res://tools/capture_tiles.tscn -- ch1_l01 --tag tileswap
##
## 产出（`deliverables/gstack/`）：
##   `screenshot-tiles-<level_id>[-<tag>].png`
##   `--tag <值>` 给文件名加后缀，避免覆盖既有证据图（与 `capture_ui_page.gd` 同一约定）。
##
## ⚠️ 只做两件事：渲染一帧 + 存 PNG。不碰任何玩法代码。
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables/gstack"

## 三章各取第一关（章节号 → biome 的映射由 TileAtlas 决定，这里不重复写死）
const DEFAULT_IDS: Array[String] = ["ch1_l01", "ch2_l07", "ch3_l14"]

const ZOOM: float = 2.0

## 探针清屏色（洋红）。见 `_probe_void()` 的说明。
const PROBE_CLEAR := Color(1.0, 0.0, 1.0, 1.0)

var _fail: int = 0
var _void_check: bool = false
var _tag: String = ""


func _ready() -> void:
	# 三关 × 真渲染 + 存盘，比 capture_frame 的三场景轻，200s 足够
	VerifyWatchdog.arm(get_tree(), 200.0)
	_void_check = OS.get_cmdline_user_args().has("--void-check")
	_run()


func _run() -> void:
	print("===== 三生物群系瓦片渲染抓图 =====")
	_ok("渲染驱动不是 headless（否则抓不到画面）",
		DisplayServer.get_name() != "headless")

	var ids := _resolve_ids()
	print("[Capture] 目标关卡：%s（tag=%s）" % [str(ids), _tag if not _tag.is_empty() else "(无)"])
	for id in ids:
		await _capture_level(id)

	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 命令行参数优先（`-- ch2_l07 ch3_l14`），否则跑三章代表关。
## 期间消费 `--tag <值>`（不进 ids），给输出文件加后缀。
func _resolve_ids() -> Array[String]:
	var out: Array[String] = []
	var args := OS.get_cmdline_user_args()
	# 用 while 而非 for：`--tag <值>` 需跳过其后一个参数（同 capture_ui_page.gd）。
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--tag" and i + 1 < args.size():
			_tag = args[i + 1]
			i += 2
			continue
		if a.begins_with("--"):
			i += 1
			continue
		out.append(a)
		i += 1
	if out.is_empty():
		return DEFAULT_IDS.duplicate()
	return out


func _capture_level(level_id: String) -> void:
	print("--- 关卡 %s ---" % level_id)
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": level_id,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	_freeze_enemies(level)
	await _settle(level)

	_ok("%s：关卡已构建（敌人 %d 个）" % [level_id, level._alive.size()],
		not level._alive.is_empty())

	# 把「这一帧到底用的是哪套图集」打进日志，让 PNG 与图集可对账
	var view := level._view
	var biome := view.biome()
	var atlas := TileAtlas.for_biome(biome)
	_ok("%s：LevelView 已设 biome（%s）" % [level_id, biome], not biome.is_empty())
	_ok("%s：图集贴图可用（真实美术 = %s）" % [level_id, str(atlas.has_real_art())],
		atlas.texture() != null)
	print("[Capture] %s · biome=%s · 真实美术=%s · 变体 地%d/墙%d/障%d · tile 数 %d"
		% [level_id, biome, str(atlas.has_real_art()),
			atlas.variant_count(LevelGenerator.TILE_GROUND),
			atlas.variant_count(LevelGenerator.TILE_WALL),
			atlas.variant_count(LevelGenerator.TILE_OBSTACLE),
			view.tile_count()])

	level._camera.zoom = Vector2(ZOOM, ZOOM)
	# 相机跟随在 _process 里，改完要等它重新居中 + 重绘
	await _hold(level, 5)
	await _shot("screenshot-tiles-%s%s.png" % [level_id, _suffix()])

	await _measure_map_draw_calls(level_id, view, level)
	if _void_check:
		await _probe_void(level_id, level)

	level.queue_free()
	await _frames(3)


## 「地图里有没有露出地图外的虚空（void）」的**可测量**判据。
##
## 为什么不能直接数深色像素：三套图集里占比最高的颜色恰好是 `#0b0d10`，
## 而它**逐字节等于** `project.godot` 的 `default_clear_color = Color(0.043,0.051,0.063)`。
## 于是「虚空」和「最暗的一格瓦片」在截图里颜色完全相同 —— 肉眼和颜色统计都分不出来。
##
## 所以这里把清屏色**临时换成洋红**再抓一张：任何洋红像素就是真正的虚空。
## 换色只走 `RenderingServer.set_default_clear_color`，不写任何文件、不改 project.godot，
## 抓完立刻还原。
func _probe_void(level_id: String, level: LevelScene) -> void:
	var before := RenderingServer.get_default_clear_color()
	RenderingServer.set_default_clear_color(PROBE_CLEAR)
	await _hold(level, 5)
	await _shot("screenshot-voidcheck-%s%s.png" % [level_id, _suffix()])
	RenderingServer.set_default_clear_color(before)
	await _hold(level, 3)
	print("[VoidProbe] %s · 清屏色临时置为洋红 #ff00ff，见 screenshot-voidcheck-%s%s.png"
		% [level_id, level_id, _suffix()])


## 任务 8.3 的不变量是「整张地图 ≈ 1 个 draw call」。`verify_tiles` 只能间接证明
## （`get_child_count() == 0`），那证明的是「没有拆成每格一个节点」，**不是** draw call 数。
## 这里直接读渲染器计数器：把地图节点隐藏前后各读一次，差值就是**地图自身贡献的 draw call**。
## 若哪天有人把图集渲染改成每格一个 Sprite2D，这个差值会从个位数暴涨到上千 —— 这里会红。
func _measure_map_draw_calls(level_id: String, view: LevelView, level: LevelScene) -> void:
	await _hold(level, 5)
	var with_map := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	view.visible = false
	await _hold(level, 5)
	var without_map := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	view.visible = true
	await _hold(level, 3)
	var delta := with_map - without_map
	print("[DrawCall] %s · 含地图 %d · 隐藏地图 %d · 地图贡献 %d（%d 格 tile）"
		% [level_id, with_map, without_map, delta, view.tile_count()])
	_ok("%s：地图贡献 draw call = %d（%d 格 tile，批处理不变量要求个位数）"
			% [level_id, delta, view.tile_count()],
		delta >= 1 and delta <= 4)


# =============================================================================
# 工具
# =============================================================================

## 冻住所有敌人（**不删**，精灵照常渲染，只是不再思考/攻击）。
##
## 为什么不能只靠奶血：伤害在 `_physics_process` 里结算，ch3_l14 有 43 个敌人，
## 同一物理帧里多人一起打就能把 150 血一次清零 —— 每渲染帧 `restore()` 一次也救不回来。
## 实测（保活版）ch3 仍然被打死 → `_finish_run()` 触发 → 进程直接退出，连结果行都没打。
## 冻住 AI 是唯一稳的做法，而且敌人还留在画面里，截图依旧有代表性。
func _freeze_enemies(level: LevelScene) -> void:
	var frozen := 0
	for e in level._alive:
		if not is_instance_valid(e):
			continue
		e.set_physics_process(false)
		e.set_process(false)
		frozen += 1
	print("[Freeze] %s · 已冻结 %d 个敌人的 AI（仅用于抓图，不改玩法代码）"
		% [level.name, frozen])


## 等场景稳定：敌人就位、掉落光柱出现、HUD 文本刷出来。
##
## ⚠️ 另外每帧把玩家奶满，作为 `_freeze_enemies()` 之外的兜底
##    （万一有未被冻结的伤害源，也不会让工具挂死）。
func _settle(level: LevelScene) -> void:
	await _hold(level, 10)
	await _hold(level, 36)   # ≈0.6s @60fps，替代 create_timer（time_scale 变化时更稳）


## 等 n 帧，每帧顺手把玩家奶满（见 `_settle()` 的说明）
func _hold(level: LevelScene, n: int) -> void:
	for _i in n:
		_keep_player_alive(level)
		await get_tree().process_frame


func _keep_player_alive(level: LevelScene) -> void:
	if not is_instance_valid(level) or level.is_queued_for_deletion():
		return
	var player := level._player
	if player == null or not is_instance_valid(player):
		return
	var hc = player.health
	if hc == null:
		return
	if hc.is_dead:
		return   # 已经死了就救不回来了（`_finish_run` 已触发），别假装还活着
	var maxhp: float = hc.get_max_hp()
	if hc.get_current_hp() < maxhp:
		hc.restore(maxhp - hc.get_current_hp())


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


## 文件名后缀（空 tag → 空串），与 capture_ui_page.gd 同一约定
func _suffix() -> String:
	return "" if _tag.is_empty() else "-" + _tag


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
