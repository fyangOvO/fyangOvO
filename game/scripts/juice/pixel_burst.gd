## 死亡像素粒子（任务 2.8 · 打击感）
##
## 死亡时爆发：N 个 3×3 色块碎片（径向散开 + 微重力 + 淡出）+
## 一圈白色扩散环（死亡闪光）。像素风自绘，零资产。
class_name PixelBurst
extends Node2D

const PART_SIZE: float = 3.0

var _parts: Array = []  # [{ pos: Vector2, vel: Vector2, color: Color }]
var _ring_radius: float = 0.0
var _lifetime: float = 0.0
var _duration: float = GameConstants.DEATH_BURST_DURATION
var _spawned: bool = false


## 初始化：按怪物主色生成碎片（颜色提亮模拟死亡闪光）
func setup(base_color: Color) -> void:
	add_to_group(&"juice_bursts")
	_spawned = true
	var bright := base_color.lightened(0.25)
	for i in GameConstants.DEATH_BURST_PARTS:
		var ang := randf() * TAU
		var spd := randf_range(
			GameConstants.DEATH_BURST_SPEED_MIN, GameConstants.DEATH_BURST_SPEED_MAX)
		_parts.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"color": bright if i % 2 == 0 else base_color,
		})
	queue_redraw()


func _process(delta: float) -> void:
	_lifetime += delta
	var t := _lifetime / _duration
	if t >= 1.0:
		queue_free()
		return
	_ring_radius += 46.0 * delta
	for p in _parts:
		p["pos"] = p["pos"] + p["vel"] * delta
		p["vel"] = p["vel"] + Vector2(0.0, GameConstants.DEATH_BURST_GRAVITY * delta)
	queue_redraw()


func _draw() -> void:
	if not _spawned:
		return
	var t := _lifetime / _duration
	var fade := 1.0 - t
	# 白色扩散环（死亡闪光，从 8px 扩开）
	var ring_a := 0.7 * fade
	if ring_a > 0.0:
		draw_arc(Vector2.ZERO, _ring_radius, 0.0, TAU, 20,
				Color(1.0, 1.0, 1.0, ring_a), 1.0)
	# 碎片
	for p in _parts:
		var c: Color = p["color"]
		c.a = fade
		draw_rect(Rect2(p["pos"] - Vector2(PART_SIZE, PART_SIZE) * 0.5,
				Vector2(PART_SIZE, PART_SIZE)), c)
