## 性能优化：关卡地图批处理渲染（任务 8.3 · class_name LevelView extends Node2D）
##
## 旧方案（预览工具曾用）：每个 tile 一个 ColorRect → 数百格 = 数百个节点 /
## 数百 draw calls。本组件把整个 layout 画进**一个** CanvasItem 的 _draw，
## 总 draw calls 恒定 ≈ 1–2（含字体/前景），节点数 1。
##
## 2026-09-20 变更（生物群系瓦片渲染）：
##   原先只画三种硬编码纯色矩形 ⇒ 地图在游戏里就是一片色块，没有任何场景感。
##   现在 `set_biome()` 之后改用 `TileAtlas` 的**单张**图集贴图逐格
##   `draw_texture_rect_region` —— 同贴图连续绘制会被 Godot 4 的 2D 批处理器合并，
##   **批处理前提（一个 CanvasItem / draw call ≈ 1）不变**。
##   ⚠️ 不要退化成「每种 tile 一张贴图」或「每格一个 Sprite2D」——那会重新引入
##      成百上千个 draw call，正是任务 8.3 要消灭的东西。
##
## 向后兼容：**没有** set_biome（或 biome 解析不出图集）时，`_draw()` 走原来的
##   三色 `draw_rect` 分支，所有既有预览工具 / verify 脚本行为不变。
##
## 数据源：LevelGenerator.generate() 的 layout（cells: Dictionary[Vector2i->int] + 尺寸 + 出生点）。
class_name LevelView
extends Node2D

const TILE_PX := 32

## 2.5D 墙侧面条高度（px）：南邻是地面的墙格，在底部延伸出这么高的一条暗面，
## 让墙读起来是「有高度的方块」而不是平铺色块。与墙格共用同一张图集贴图。
const WALL_FACE_H := 8

## 侧面的压暗系数（走顶点色调制，不换贴图 ⇒ 不打断批处理）
const WALL_FACE_MODULATE := Color(0.60, 0.60, 0.66)

## 【L2】南邻也是墙（或障碍 / 地图外）⇒ 这是**墙内部**的一格：
## 在格子底边叠 1px 横向接缝，让一大片墙有水平分层，而不是一整块平贴图。
## 取 0.80 而不是更暗：再暗就与 `WALL_FACE_MODULATE` 的暗面同档，反而分不出「面」与「缝」。
const WALL_SEAM_MODULATE := Color(0.80, 0.80, 0.84)

## 【L2】北邻是地面 ⇒ 墙顶受光边 1px，给墙一个「顶」（俯视 2.5D 的光从北边来）。
## 略 > 1 是**有意**的提亮；但只作用在 1px 上，不会像整格提亮那样过曝。
const WALL_TOP_MODULATE := Color(1.10, 1.10, 1.06)

## 【L2】墙内部横向接缝开关。默认开；若将来 `verify_perf83` 对顶点数敏感导致变红，
## 把这里置 false 即可省掉一趟 `_tiles` 遍历（每趟 ≤ 1800 次 `draw_texture_rect_region`），
## 代价是墙内部退回「一整块平贴图」。**draw call 数不受影响**（仍是同一个 CanvasItem）。
const WALL_SEAM_ENABLED := true

## 金色出生点调试标记。**默认关闭**（真实游戏里不该出现）。
## 预览 / 抓图工具需要时显式打开。
var show_spawn_marker: bool = false:
	set(value):
		show_spawn_marker = value
		queue_redraw()

var _layout: Dictionary = {}
var _tiles: Array = []          # [Vector3i(x, y, kind)]
var _cells: Dictionary = {}     # Vector2i -> int（南邻查询用）

var _biome: String = ""
var _atlas: TileAtlas = null
var _var_counts: Dictionary = {}  # kind(int) -> 变体数


func set_layout(layout: Dictionary) -> void:
	_layout = layout
	_cells = layout.get("cells", {})
	_tiles.clear()
	for key in _cells:
		if not key is Vector2i:
			continue
		var k: Vector2i = key
		var t: int = int(_cells[k])
		if t == LevelGenerator.TILE_GROUND or t == LevelGenerator.TILE_WALL \
				or t == LevelGenerator.TILE_OBSTACLE:
			_tiles.append(Vector3i(k.x, k.y, t))
	queue_redraw()


## 设置生物群系 → 之后的绘制走图集贴图分支。
## `tileset_path` 非空时优先用它所在目录的 `atlas.png`/`atlas.json`（消费 LevelData 字段）。
## 传空串（或 biome 解析不出图集）时退回纯色分支。
func set_biome(biome: String, tileset_path: String = "") -> void:
	_biome = biome
	if biome.is_empty():
		_atlas = null
	else:
		_atlas = TileAtlas.for_biome(biome, tileset_path)
	_var_counts.clear()
	if _atlas != null:
		_var_counts[LevelGenerator.TILE_GROUND] = _atlas.variant_count(LevelGenerator.TILE_GROUND)
		_var_counts[LevelGenerator.TILE_WALL] = _atlas.variant_count(LevelGenerator.TILE_WALL)
		_var_counts[LevelGenerator.TILE_OBSTACLE] = _atlas.variant_count(LevelGenerator.TILE_OBSTACLE)
	queue_redraw()


func biome() -> String:
	return _biome


func tile_count() -> int:
	return _tiles.size()


func _draw() -> void:
	if _atlas != null and _atlas.texture() != null:
		_draw_atlas()
	else:
		_draw_flat()
	if show_spawn_marker:
		_draw_spawn_marker()


# =============================================================================
# 分支 ①：图集贴图（生物群系渲染）
# =============================================================================

## 单次绘制批处理全部 tile：同贴图连续绘制 → 合并为 1 个 draw call。
func _draw_atlas() -> void:
	var tex: Texture2D = _atlas.texture()
	# ① 地面底衬：真实美术里的障碍（以及个别墙）是**抠出来的道具**，格子内带透明像素。
	#    而障碍格不会被当作地面格绘制，直接叠上去会在透明处露出地图外的 void（纯黑）。
	#    所以先给每个非地面格垫一层地面，再把物件压上去。
	#    仍然只用同一张贴图 ⇒ 依旧在同一个批处理里，只增加顶点数、不增加 draw call。
	var ground_n := _variant_count(LevelGenerator.TILE_GROUND)
	if ground_n > 0:
		for t in _tiles:
			if t.z == LevelGenerator.TILE_GROUND:
				continue
			var under := _atlas.region_for(
				LevelGenerator.TILE_GROUND, _variant_index(t.x, t.y, ground_n))
			draw_texture_rect_region(
				tex, Rect2(t.x * TILE_PX, t.y * TILE_PX, TILE_PX, TILE_PX), under)
	# ② 全部 tile（地面 / 墙 / 障碍）
	for t in _tiles:
		var kind: int = t.z
		var src: Rect2 = _atlas.region_for(kind, _variant_index(t.x, t.y, _variant_count(kind)))
		draw_texture_rect_region(
			tex, Rect2(t.x * TILE_PX, t.y * TILE_PX, TILE_PX, TILE_PX), src)
	# ③ 2.5D 墙面：南邻是地面的墙格，在底部延伸出一条压暗的侧面（同贴图 + 顶点色调制）
	var wall_src: Rect2 = _atlas.region_for(LevelGenerator.TILE_WALL, 0)
	var face_src := Rect2(
		wall_src.position.x, wall_src.position.y + TILE_PX - WALL_FACE_H, TILE_PX, WALL_FACE_H)
	# 1px 接缝 / 顶边用**贴图内 1px 高**的源区域 —— 源高 = 目标高 ⇒ 仍是 1:1 像素，
	# 不引入任何非整数缩放（铁律：只允许整数缩放）。
	var seam_src := Rect2(
		wall_src.position.x, wall_src.position.y + TILE_PX - 1, TILE_PX, 1)
	var top_src := Rect2(wall_src.position.x, wall_src.position.y, TILE_PX, 1)
	for t in _tiles:
		if t.z != LevelGenerator.TILE_WALL:
			continue
		if _kind_at(t.x, t.y + 1) == LevelGenerator.TILE_GROUND:
			draw_texture_rect_region(
				tex, Rect2(t.x * TILE_PX, (t.y + 1) * TILE_PX, TILE_PX, WALL_FACE_H),
				face_src, WALL_FACE_MODULATE)
		elif WALL_SEAM_ENABLED:
			# 墙内部的横向接缝（L2）：画在本格最后一行像素上，即两条墙的分界处
			draw_texture_rect_region(
				tex, Rect2(t.x * TILE_PX, (t.y + 1) * TILE_PX - 1.0, TILE_PX, 1.0),
				seam_src, WALL_SEAM_MODULATE)
	# ④ 墙顶受光边（L2）：北邻是地面 ⇒ 本格是墙的「顶面边缘」，叠 1px 亮边
	for t in _tiles:
		if t.z != LevelGenerator.TILE_WALL:
			continue
		if _kind_at(t.x, t.y - 1) != LevelGenerator.TILE_GROUND:
			continue
		draw_texture_rect_region(
			tex, Rect2(t.x * TILE_PX, t.y * TILE_PX, TILE_PX, 1.0),
			top_src, WALL_TOP_MODULATE)


## 每格变体索引：按格坐标做廉价散列（同格永远同变体，且相邻格不规律错开）
static func _variant_index(x: int, y: int, count: int) -> int:
	if count <= 1:
		return 0
	var h: int = x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return (h & 0x7fffffff) % count


func _variant_count(kind: int) -> int:
	return int(_var_counts.get(kind, 0))


func _kind_at(x: int, y: int) -> int:
	var key := Vector2i(x, y)
	if _cells.has(key):
		return int(_cells[key])
	return -1


# =============================================================================
# 分支 ②：纯色回退（未设 biome / 无图集时，保持既有行为不变）
# =============================================================================

func _draw_flat() -> void:
	# 单次绘制批处理全部 tile（地格 + 墙格），比 N 个 ColorRect 少 ~N 个 draw call
	for t in _tiles:
		var kind: int = t.z
		var col := Color(0.16, 0.16, 0.20)
		if kind == LevelGenerator.TILE_GROUND:
			col = Color(0.10, 0.11, 0.14)
		elif kind == LevelGenerator.TILE_OBSTACLE:
			col = Color(0.22, 0.10, 0.10)
		draw_rect(Rect2(t.x * TILE_PX, t.y * TILE_PX, TILE_PX, TILE_PX), col, true)


func _draw_spawn_marker() -> void:
	if not _layout.has("player_spawn") or not _layout.get("player_spawn", Vector2i.ZERO) is Vector2i:
		return
	var ps: Vector2i = _layout["player_spawn"]
	var sx := ps.x * TILE_PX + TILE_PX / 2
	var sy := ps.y * TILE_PX + TILE_PX / 2
	draw_rect(Rect2(sx - 8, sy - 8, 16, 16), Color(1.0, 0.8, 0.2), true)
