## 特效贴图**真渲染**抓图 + 逐特效像素级证据（开发工具，不属于游戏玩法）
##
## 用法（**必须去掉 `--headless`** —— 无头模式下没有渲染，抓不到画面）：
##   godot --path "D:/七傳說/game" res://tools/capture_fx.tscn
##
## 为什么必须有这个工具
## --------------------
## `verify_fx.tscn` 只能证明「表能加载、贴图在磁盘上、帧号会前进」——
## 它**证明不了「这一帧画面上真的有特效」**。本项目已经吃过这类亏：
## 108 项自检 + 36 个 verify 全绿，但没人渲染过一帧（`capture_frame.gd:11-17` 记录过
## 相机未设 limit 导致半屏纯黑、出生点在房间角落等问题，全是真渲染才看见的）。
##
## 产出（`deliverables/gstack/`）
## ---------------------------
##   `screenshot-fx-montage.png`  7 个特效同屏（人眼复核用）
##
## 并且对**每个特效单独**做一次量化证明：
##   冻结时间（`Engine.time_scale = 0`）→ 抓一张无特效基准帧 → 生成该特效并 seek 到
##   最有内容的帧 → 再抓一帧 → 统计该特效屏幕矩形内**变化的像素数**。
##   变化像素 > 0 ⇒ 它真的被画到屏幕上了（不是"看着像有"）。
##
## ⚠️ 只做三件事：加载关卡 + 生成特效 + 抓图统计。不碰任何玩法代码。
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables/gstack"
const LEVEL_ID: String = "ch1_l01"

## 每个特效 seek 到「内容最满」的播放进度（0–1），这样 diff 出来的像素才够多
const SEEK: Dictionary = {
	"hit_spark": 0.40, "slash_arc": 0.25, "level_up_burst": 0.45,
	"pickup_glow": 0.50, "death_puff": 0.30,
	"ember_lord_aura": 0.30, "pyromancer_cast": 0.50,
}

## 蒙太奇布局：id → 相对**相机中心**的世界偏移。
## 视口 1920×1080 + 相机 2× ⇒ 可见世界范围 960×540，所以 ±420 / ±220 内都安全。
const LAYOUT: Dictionary = {
	"hit_spark": Vector2(-340.0, -150.0),
	"slash_arc": Vector2(-180.0, -150.0),
	"level_up_burst": Vector2(0.0, -150.0),
	"pickup_glow": Vector2(180.0, -150.0),
	"death_puff": Vector2(340.0, -150.0),
	"ember_lord_aura": Vector2(-170.0, 110.0),
	"pyromancer_cast": Vector2(230.0, 110.0),
}

var _fail: int = 0
var _level: LevelScene = null
var _base: Image = null


func _ready() -> void:
	# 120s：本工具正常 ~20–40s（含首次着色器编译）。设上限是为了**失败快速可见** ——
	# 实测过一次抓图调用在窗口尚未合成时长时间不返回，没有看门狗就会白等。
	VerifyWatchdog.arm(get_tree(), 120.0)
	_run()


func _run() -> void:
	print("===== 特效贴图 · 真渲染抓图 =====")
	_ok("渲染驱动不是 headless（否则抓不到画面）",
		DisplayServer.get_name() != "headless")

	await _enter_level()
	# 冻结时间：敌人不动、特效不自动前进 ⇒ 帧间差异只可能来自我们手动生成的特效。
	# （看门狗用 ignore_time_scale=true 的计时器，所以冻结不会让它失效。）
	Engine.time_scale = 0.0
	print("[Capture] 时间已冻结（time_scale=0）")
	await _frames(5)
	print("[Capture] 冻结后 5 帧已过，准备抓基准帧")
	_base = await _grab()
	print("[Capture] 基准帧已抓")
	_ok("抓到无特效基准帧", _base != null and _base.get_width() > 0)

	await _measure_each()
	await _montage()

	Engine.time_scale = 1.0
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _enter_level() -> void:
	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _frames(3)
	_level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _frames(10)
	await get_tree().create_timer(0.5).timeout
	_ok("关卡已构建（敌人 %d 个）" % _level._alive.size(), not _level._alive.is_empty())


# =============================================================================
# 逐特效量化证明
# =============================================================================

func _measure_each() -> void:
	print("--- 逐特效像素级证据（屏幕矩形内变化像素数）---")
	var ids := FxTable.all_ids()
	var total_changed := 0
	for id in ids:
		print("[Capture] 测量 %s …" % id)
		var world: Vector2 = _camera_center() + LAYOUT.get(id, Vector2.ZERO)
		var fx := FxTable.spawn(id, world)
		if fx == null:
			_ok("生成特效 %s" % id, false)
			continue
		_seek(fx, id)
		await _frames(3)
		var shot: Image = await _grab()
		if shot == null:
			_ok("抓图 %s" % id, false)
			fx.queue_free()
			continue
		var rect := _screen_rect(world, _fx_world_size(id))
		var changed := _diff_count(_base, shot, rect)
		total_changed += changed
		_ok("%-18s 屏幕矩形 %s 内变化像素 = %d（>0 即真的画上去了）"
				% [id, str(rect.size), changed], changed > 0)
		fx.queue_free()
		await _frames(3)
	_ok("7 个特效合计变化像素 = %d" % total_changed, total_changed > 0)


func _seek(fx: Node2D, id: String) -> void:
	var sp := FxTable.spec(id)
	var total := maxf(float(sp.get("frames", 1)) / maxf(float(sp.get("fps", 1.0)), 0.001), 0.001)
	# time_scale = 0 ⇒ 引擎每帧喂 delta = 0，所以手动喂的这一下就是最终帧
	fx.call("_process", total * float(SEEK.get(id, 0.4)))


# =============================================================================
# 蒙太奇（人眼复核）
# =============================================================================

func _montage() -> void:
	print("--- 蒙太奇：7 个特效同屏 ---")
	var made: Array[Node2D] = []
	for id in FxTable.all_ids():
		var world: Vector2 = _camera_center() + LAYOUT.get(id, Vector2.ZERO)
		var fx := FxTable.spawn(id, world)
		if fx == null:
			_ok("蒙太奇生成 %s" % id, false)
			continue
		_seek(fx, id)
		made.append(fx)
	await _frames(4)
	_ok("蒙太奇节点数 = %d" % made.size(), made.size() == FxTable.all_ids().size())
	await _shot("screenshot-fx-montage.png")
	for fx in made:
		fx.queue_free()


# =============================================================================
# 工具
# =============================================================================

func _camera_center() -> Vector2:
	# `get_screen_center_position()` 已含相机 limit 的夹取结果，比 global_position 准
	return _level._camera.get_screen_center_position()


func _fx_world_size(id: String) -> Vector2:
	var sp := FxTable.spec(id)
	return Vector2(float(sp.get("frame_w", 32)), float(sp.get("frame_h", 32)))


## 世界点 + 世界尺寸 → 视口像素矩形（含相机缩放），并夹进视口内。
func _screen_rect(world: Vector2, size: Vector2) -> Rect2i:
	var zoom: Vector2 = _level._camera.zoom
	var vp := get_viewport_rect().size
	var scr := (world - _camera_center()) * zoom + vp * 0.5
	var half := size * zoom * 0.5
	var r := Rect2(scr - half, size * zoom)
	var x0 := int(clampf(floorf(r.position.x), 0.0, vp.x - 1.0))
	var y0 := int(clampf(floorf(r.position.y), 0.0, vp.y - 1.0))
	var x1 := int(clampf(ceilf(r.end.x), 1.0, vp.x))
	var y1 := int(clampf(ceilf(r.end.y), 1.0, vp.y))
	return Rect2i(x0, y0, maxi(x1 - x0, 1), maxi(y1 - y0, 1))


## 两帧在指定矩形内的**不同像素数**（逐字节比，避开 200 万次 get_pixel 的开销）
func _diff_count(a: Image, b: Image, rect: Rect2i) -> int:
	var ca := a.get_region(rect)
	var cb := b.get_region(rect)
	ca.convert(Image.FORMAT_RGBA8)
	cb.convert(Image.FORMAT_RGBA8)
	var da := ca.get_data()
	var db := cb.get_data()
	var n := 0
	var i := 0
	while i < da.size():
		if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2]:
			n += 1
		i += 4
	return n


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

func _shot(fname: String) -> void:
	var img := await _grab()
	if img == null:
		_ok("抓图 %s" % fname, false)
		return
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
