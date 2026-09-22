## 单次播放的横向序列帧特效（class_name FxSprite extends Node2D）
##
## 一个特效 = 一张**横向长条**贴图：`frame_count` 个 `frame_w × frame_h` 的格子，
## 从左到右依次播放，到最后一帧自动 `queue_free()`（`loop=false` 时）。
##
## 为什么用 `_draw()` + `draw_texture_rect_region`，而不是 `AnimatedSprite2D`
## ----------------------------------------------------------------------
## 这些特效是**每次命中都生成**的（普通攻击一秒钟可能十几次），所以生成开销敏感：
##   · `AnimatedSprite2D` 需要每个实例构造一份 `SpriteFrames` 资源并逐帧建
##     `AtlasTexture` —— 每次 spawn 都是一次资源分配（还要挂到树上才生效）；
##   · `_draw()` 方案整个特效只有 **1 个 CanvasItem ⇒ 1 个 draw call**，且**零资源分配**
##     （贴图从 `FxTable` 的静态缓存里复用，只有 `Rect2` 是逐帧重算的）。
## 与项目既有约定一致：`pixel_burst.gd` / `loot_drop.gd` / `level_view.gd` 也都是
## 「一个节点自绘全部内容」，`level_view.gd:12` 明确禁止退化成「每格一个 Sprite2D」。
##
## 生命周期用 `delta`（跟随游戏时间）而非真实时间 —— 与 `pixel_burst.gd:34` 一致。
## （`damage_number.gd:31` 用真实时间是因为顿帧期间飘字不该加速老化，那是飘字特有的诉求。）
class_name FxSprite
extends Node2D

## 横向长条贴图。为 `null` 时 `_draw()` 什么都不画（不崩）。
var sheet: Texture2D = null

var frame_w: int = 32
var frame_h: int = 32
var frame_count: int = 1
var fps: float = 18.0

## true = 播完不停留（不自动释放，交给调用方管理）；false = 播完 `queue_free()`。
var loop: bool = false

## 锚点语义：`center` / `top_left` / `bottom_center`（见 `_dest_rect()`）。
var anchor: String = "center"

## true = 播放期间线性淡出（`modulate.a` 1 → 0），软化尾帧的"啪一下消失"。
var fade: bool = false

var _elapsed: float = 0.0
var _frame: int = 0
var _total: float = 0.0


func _ready() -> void:
	# 像素风铁律：Nearest 采样。显式设置而不依赖继承 —— 父节点可能是 Linear。
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 与 `pixel_burst.gd:19` / `damage_number.gd:17` 同一约定：把同类实例挂进组，
	# 让 verify / 抓图工具能数得出「屏幕上此刻有几个特效」，而不是靠猜。
	add_to_group(&"fx_sprites")
	_total = maxf(float(frame_count), 1.0) / maxf(fps, 0.001)
	queue_redraw()


## 按 `FxTable` 解析出的 spec 配置本实例。返回 false = spec 不可用（不播放）。
func setup(spec: Dictionary, tex: Texture2D) -> bool:
	if tex == null:
		return false
	sheet = tex
	frame_w = maxi(int(spec.get("frame_w", 32)), 1)
	frame_h = maxi(int(spec.get("frame_h", 32)), 1)
	fps = maxf(float(spec.get("fps", 18.0)), 0.001)
	loop = bool(spec.get("loop", false))
	anchor = str(spec.get("anchor", "center"))
	fade = bool(spec.get("fade", false))

	# 边界：用户可能塞一张尺寸不匹配的 PNG（把 frames 写多了）。
	# 不崩、不静默播错帧 —— 夹到贴图实际装得下的帧数，并吵一声。
	var want := maxi(int(spec.get("frames", 1)), 1)
	var fit := maxi(int(tex.get_width()) / frame_w, 1)
	if want > fit:
		push_warning("FxSprite: 贴图宽 %dpx 只装得下 %d 帧（frame_w=%d），spec 写了 %d 帧，已夹到 %d"
			% [tex.get_width(), fit, frame_w, want, fit])
	frame_count = mini(want, fit)

	_total = maxf(float(frame_count), 1.0) / fps
	_elapsed = 0.0
	_frame = 0
	queue_redraw()
	return true


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _total:
		if loop:
			_elapsed = fmod(_elapsed, _total)
		else:
			queue_free()
			return
	_frame = mini(int(_elapsed * fps), frame_count - 1)
	if fade:
		modulate.a = clampf(1.0 - _elapsed / _total, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if sheet == null or frame_count <= 0:
		return
	var src := Rect2(float(_frame * frame_w), 0.0, float(frame_w), float(frame_h))
	draw_texture_rect_region(sheet, _dest_rect(), src)


## 目标矩形（相对本节点原点）。三种锚点覆盖「以命中点为中心」/「左上角对齐」/
## 「底部中心对齐角色脚底」三类常见需求。
func _dest_rect() -> Rect2:
	var w := float(frame_w)
	var h := float(frame_h)
	match anchor:
		"top_left":
			return Rect2(0.0, 0.0, w, h)
		"bottom_center":
			return Rect2(-w * 0.5, -h, w, h)
		_:
			return Rect2(-w * 0.5, -h * 0.5, w, h)
