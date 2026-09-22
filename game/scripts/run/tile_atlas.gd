## 生物群系瓦片图集（class_name TileAtlas extends RefCounted）
##
## 为什么需要它：关卡地图原先由 `LevelView._draw()` 用三种硬编码颜色 `draw_rect` 画出
## ——地图在游戏里就是一片纯色矩形，没有任何「场景」感。本文件提供每个生物群系的
## **单张** atlas 贴图，让 `LevelView` 用 `draw_texture_rect_region` 逐格采样。
##
## ⚠️ 关键约束：**不能破坏任务 8.3 的批处理前提**（整张地图 = 一个 CanvasItem，
##    draw call ≈ 1）。所以这里每个 biome 只产出**一张**贴图，`LevelView` 全程复用同一张，
##    Godot 4 的 2D 批处理器会把同贴图的连续绘制合并；**禁止**改成「每种 tile 一张贴图」
##    或「每格一个 Sprite2D」。
##
## 美术来源优先级（前者可用就用前者）：
##   ① `LevelData.tileset_path` 所在目录的 `atlas.png` + `atlas.json`（数据表可覆盖，
##      20 关的该字段当前为空 —— 这是「设计了但没人消费」的接口，本文件把它接上）
##   ② `res://assets/tilesets/<biome>/atlas.png` + `atlas.json`（tile-scout 下载的真实美术落点）
##   ③ 都没有 → **运行时程序化生成占位图集**，让地图立刻不再是纯色矩形
##
## 占位图集按 biome 名播种（FNV-1a，不依赖 `String.hash()` 的实现），
## 同一 biome 每次生成的像素**逐字节一致**。
class_name TileAtlas
extends RefCounted

## 单格像素（与 LevelGenerator.TILE_SIZE / LevelView.TILE_PX 对齐）
const TILE_SIZE := 32
const TILE_HALF := 16

## 占位图集网格：6 列 × 3 行。行 = 类别，列 = 变体。
##   行 0 = 地面变体（6 个，避免大面积地板看出「盖章」感）
##   行 1 = 墙体变体（3 个）
##   行 2 = 障碍变体（3 个）
const COLS := 6
const GROUND_VARIANTS := 6
const WALL_VARIANTS := 3
const OBSTACLE_VARIANTS := 3

const BIOME_FOREST := "forest"
const BIOME_VOLCANIC := "volcanic"
const BIOME_FROST := "frost"

## 静态缓存：biome（+ 自定义图集目录）→ TileAtlas，重复进关不重复生成贴图
static var _cache: Dictionary = {}

var biome: String = ""
var tile_size: int = TILE_SIZE

var _tex: Texture2D = null
var _regions: Dictionary = {}   ## kind(int) -> Array[Rect2]
var _real_art: bool = false


# =============================================================================
# 生物群系判定
# =============================================================================

## 关卡 → 生物群系。**任何** LevelData 都必须拿到非空结果（20 关全覆盖）。
## 章节号优先（1/2/3 = 森林/火山/霜渊）；章节缺失或越界时退回按 ambient_color 推断。
static func biome_for_level(level: LevelData) -> String:
	if level == null:
		return BIOME_FOREST
	match int(level.chapter):
		1:
			return BIOME_FOREST
		2:
			return BIOME_VOLCANIC
		3:
			return BIOME_FROST
	return _biome_from_color(level.ambient_color)


## 从章节主题色反推 biome：绿主导 → 森林，红/橙主导 → 火山，蓝主导 → 霜渊。
## alpha == 0 表示「不覆盖」（LevelData 的默认值），按森林兜底。
static func _biome_from_color(c: Color) -> String:
	if c.a <= 0.0:
		return BIOME_FOREST
	if c.g >= c.r and c.g >= c.b:
		return BIOME_FOREST
	if c.r >= c.g and c.r >= c.b:
		return BIOME_VOLCANIC
	return BIOME_FROST


# =============================================================================
# 构造
# =============================================================================

## 取某 biome 的图集（带缓存）。
## `tileset_path` 非空时优先用它所在目录的 `atlas.png`/`atlas.json`（消费 LevelData 字段）。
static func for_biome(biome_name: String, tileset_path: String = "") -> TileAtlas:
	var art_dir := ""
	var key := biome_name
	if not tileset_path.is_empty():
		art_dir = tileset_path.get_base_dir()
		key = "%s|%s" % [biome_name, art_dir]
	if _cache.has(key):
		return _cache[key]
	var atlas := TileAtlas.new()
	atlas.biome = biome_name
	atlas._build(art_dir)
	_cache[key] = atlas
	return atlas


## 清空缓存（仅供调试 / 换图后强制重建）
static func clear_cache() -> void:
	_cache.clear()


func _build(art_dir: String) -> void:
	var dirs: Array[String] = []
	# ① 用户覆盖（最高优先）：`user://content/tilesets/<biome>/atlas.{png,json}`
	#    用户只放一个生态就只覆盖那个生态，其余仍走内置 —— 不必整套复制。
	#    这是「三级优先」的第一级；第三级（程序化占位）由 _generate_placeholder() 承担。
	dirs.append(ContentPaths.class_dir(ContentPaths.CLASS_TILESETS).path_join(biome))
	if not art_dir.is_empty():
		dirs.append(art_dir)
	dirs.append("res://assets/tilesets/%s" % biome)
	for d in dirs:
		if _try_load_real(d):
			return
	_generate_placeholder()


# =============================================================================
# ① 真实美术
# =============================================================================

## 尝试从 `dir/atlas.png` + `dir/atlas.json` 载入。
## 清单形状：{"tile_size":32,"tiles":{"ground":[[x,y],...],"wall":[[x,y],...],
##            "obstacle":[[x,y],...]}}（每个 [x,y] 是图集**格坐标**，可给多个变体）
func _try_load_real(dir: String) -> bool:
	var png := "%s/atlas.png" % dir
	var meta_path := "%s/atlas.json" % dir
	if not ResourceLoader.exists(png) and not FileAccess.file_exists(png):
		return false
	var tex := _load_texture(png)
	if tex == null:
		return false
	if not FileAccess.file_exists(meta_path):
		return false   # 有图无清单 → 不知道哪格是什么，退回占位图（不猜）
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not parsed is Dictionary:
		return false
	var meta: Dictionary = parsed
	var ts := int(meta.get("tile_size", TILE_SIZE))
	if ts <= 0:
		return false
	var tiles: Dictionary = meta.get("tiles", {})
	var kind_names := {
		"ground": LevelGenerator.TILE_GROUND,
		"wall": LevelGenerator.TILE_WALL,
		"obstacle": LevelGenerator.TILE_OBSTACLE,
	}
	var regions := {}
	for name in kind_names:
		var cells: Array = tiles.get(name, [])
		var out: Array[Rect2] = []
		for cell in cells:
			if cell is Array and cell.size() >= 2:
				out.append(Rect2(int(cell[0]) * ts, int(cell[1]) * ts, ts, ts))
		if out.is_empty():
			return false   # 缺任何一类 → 视为不可用图集，整体退回占位图
		regions[kind_names[name]] = out
	_tex = tex
	tile_size = ts
	_regions = regions
	_real_art = true
	return true


static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path)
		if res is Texture2D:
			return res
	# 未经导入的裸 PNG（tile-scout 刚下载、还没跑 import 时）
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null


# =============================================================================
# ② 程序化占位图集
# =============================================================================

## 程序化生成占位图集（纯函数：同一 biome 永远得到逐字节一致的 Image）。
## 拆成 public static 是为了让 verify 脚本能**不依赖渲染器**验证确定性
## （headless 下 `Texture2D.get_image()` 不保证可用）。
static func build_placeholder_image(biome_name: String) -> Image:
	var pal := _palette(biome_name)
	var img := Image.create_empty(COLS * TILE_SIZE, 3 * TILE_SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_of(biome_name)

	for v in GROUND_VARIANTS:
		_paint_ground(img, v * TILE_SIZE, 0, pal, rng)
	for v in WALL_VARIANTS:
		_paint_wall(img, v * TILE_SIZE, TILE_SIZE, pal, rng)
	for v in OBSTACLE_VARIANTS:
		_paint_obstacle(img, v * TILE_SIZE, 2 * TILE_SIZE, pal, rng)

	# 未使用的格子（墙 / 障碍只用前 3 列）填成对应类别的第 0 格样式，
	# 避免图集里出现透明格 —— 万一将来变体数变化导致采样越界，也不会露出怪色。
	for c in range(WALL_VARIANTS, COLS):
		_blit(img, c * TILE_SIZE, TILE_SIZE, img, 0, TILE_SIZE)
		_blit(img, c * TILE_SIZE, 2 * TILE_SIZE, img, 0, 2 * TILE_SIZE)
	return img


func _generate_placeholder() -> void:
	var img := build_placeholder_image(biome)
	var ground: Array[Rect2] = []
	for v in GROUND_VARIANTS:
		ground.append(Rect2(v * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE))
	var wall: Array[Rect2] = []
	for v in WALL_VARIANTS:
		wall.append(Rect2(v * TILE_SIZE, TILE_SIZE, TILE_SIZE, TILE_SIZE))
	var obstacle: Array[Rect2] = []
	for v in OBSTACLE_VARIANTS:
		obstacle.append(Rect2(v * TILE_SIZE, 2 * TILE_SIZE, TILE_SIZE, TILE_SIZE))

	_tex = ImageTexture.create_from_image(img)
	tile_size = TILE_SIZE
	_regions = {
		LevelGenerator.TILE_GROUND: ground,
		LevelGenerator.TILE_WALL: wall,
		LevelGenerator.TILE_OBSTACLE: obstacle,
	}
	_real_art = false


## 格内复制（源 = 目标图集自身，用于把第 0 格样式铺到空列）
static func _blit(img: Image, dx: int, dy: int, src: Image, sx: int, sy: int) -> void:
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			img.set_pixel(dx + x, dy + y, src.get_pixel(sx + x, sy + y))


# -----------------------------------------------------------------------------
# 三章调色板（取自美术规范 1.3 节主题色，48 色板内）
# -----------------------------------------------------------------------------

static func _palette(biome_name: String) -> Dictionary:
	match biome_name:
		"volcanic":
			# 灰烬堡：炭灰基底 + 余烬橙点缀
			return {
				"ground": Color8(54, 47, 45),
				"ground_alt": Color8(68, 58, 53),
				"grout": Color8(28, 24, 23),
				"speckle": Color8(198, 92, 34),
				"wall": Color8(33, 29, 29),
				"wall_bevel": Color8(66, 58, 54),
				"wall_seam": Color8(20, 17, 17),
				"shadow": Color8(24, 20, 19),
				"obstacle": Color8(74, 46, 37),
				"obstacle_hi": Color8(152, 74, 38),
				"obstacle_lo": Color8(36, 22, 19),
			}
		"frost":
			# 霜渊：苍白冰蓝 + 雪白高光
			return {
				"ground": Color8(150, 172, 198),
				"ground_alt": Color8(170, 192, 216),
				"grout": Color8(106, 128, 156),
				"speckle": Color8(206, 226, 246),
				"wall": Color8(96, 120, 148),
				"wall_bevel": Color8(158, 180, 206),
				"wall_seam": Color8(70, 92, 118),
				"shadow": Color8(108, 132, 160),
				"obstacle": Color8(178, 208, 234),
				"obstacle_hi": Color8(238, 250, 255),
				"obstacle_lo": Color8(120, 150, 182),
			}
		_:
			# 幽林：苔绿 + 泥土棕
			return {
				"ground": Color8(60, 76, 52),
				"ground_alt": Color8(74, 92, 62),
				"grout": Color8(38, 50, 34),
				"speckle": Color8(88, 108, 68),
				"wall": Color8(36, 44, 32),
				"wall_bevel": Color8(56, 68, 46),
				"wall_seam": Color8(24, 30, 22),
				"shadow": Color8(40, 50, 36),
				"obstacle": Color8(96, 78, 54),
				"obstacle_hi": Color8(142, 118, 80),
				"obstacle_lo": Color8(52, 40, 28),
			}


# -----------------------------------------------------------------------------
# 三类瓦片的画法
# -----------------------------------------------------------------------------

## 逐像素微抖（三通道独立、确定性）：让地表/墙面有「颗粒感」而不是几块纯色。
## 幅度刻意压小 —— 大到能看出质感，小到不变成电视雪花。
static func _jitter(c: Color, rng: RandomNumberGenerator, amp: float) -> Color:
	return Color(
		clampf(c.r + rng.randf_range(-amp, amp), 0.0, 1.0),
		clampf(c.g + rng.randf_range(-amp, amp), 0.0, 1.0),
		clampf(c.b + rng.randf_range(-amp, amp), 0.0, 1.0),
		c.a)


## 地面：基色 + 确定性噪点（斑驳感）+ 下/右各 1px 勾缝（相邻格可分辨）
static func _paint_ground(img: Image, ox: int, oy: int, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var base: Color = pal["ground"]
	var alt: Color = pal["ground_alt"]
	var grout: Color = pal["grout"]
	var speckle: Color = pal["speckle"]
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			var r := rng.randf()
			var c := base
			if r < 0.16:
				c = alt
			elif r < 0.185:
				c = speckle
			elif r < 0.215:
				c = grout
			img.set_pixel(ox + x, oy + y, _jitter(c, rng, 0.030))
	for x in TILE_SIZE:
		img.set_pixel(ox + x, oy + TILE_SIZE - 1, grout)
	for y in TILE_SIZE:
		img.set_pixel(ox + TILE_SIZE - 1, oy + y, grout)


## 墙体：更暗的基底 + 顶部 1px 受光亮边 + 砖缝（中横缝 + 错缝竖缝）
static func _paint_wall(img: Image, ox: int, oy: int, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var base: Color = pal["wall"]
	var bevel: Color = pal["wall_bevel"]
	var seam: Color = pal["wall_seam"]
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			var r := rng.randf()
			var c := base
			if r < 0.18:
				c = base.lightened(0.05)
			elif r < 0.235:
				c = seam
			img.set_pixel(ox + x, oy + y, _jitter(c, rng, 0.026))
	# 顶部受光边
	for x in TILE_SIZE:
		img.set_pixel(ox + x, oy, bevel)
	# 砖缝
	for x in TILE_SIZE:
		img.set_pixel(ox + x, oy + TILE_HALF, seam)
		img.set_pixel(ox + x, oy + TILE_SIZE - 1, seam)
	for y in range(1, TILE_HALF):
		img.set_pixel(ox + TILE_HALF, oy + y, seam)
	for y in range(TILE_HALF + 1, TILE_SIZE - 1):
		img.set_pixel(ox, oy + y, seam)


## 障碍：先铺压暗底（障碍格下方没有地格可透出，必须自带底），
## 再画一个圆润石块剪影 —— 明确是「一个物件」，不是地板换色。
static func _paint_obstacle(img: Image, ox: int, oy: int, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var shadow: Color = pal["shadow"]
	var rock: Color = pal["obstacle"]
	var hi: Color = pal["obstacle_hi"]
	var lo: Color = pal["obstacle_lo"]
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			img.set_pixel(ox + x, oy + y, shadow)
	var cx := 15.5 + rng.randf_range(-0.8, 0.8)
	var cy := 16.5 + rng.randf_range(-0.8, 0.8)
	var jitter := rng.randf_range(-1.2, 1.2)
	var rx := 11.5 + jitter
	var ry := 10.0 - jitter * 0.5
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			var dx := (float(x) - cx) / rx
			var dy := (float(y) - cy) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var c := rock
			if d > 0.72:
				c = lo        # 外圈压暗 → 轮廓
			elif dy < -0.35:
				c = hi        # 上部受光
			img.set_pixel(ox + x, oy + y, c)


## FNV-1a 32 位：跨运行 / 跨引擎版本稳定（不用 String.hash()，其实现不保证稳定）
static func _seed_of(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xffffffff
		h = (h * 16777619) & 0xffffffff
	return h


# =============================================================================
# 公共 API
# =============================================================================

func texture() -> Texture2D:
	return _tex


func has_real_art() -> bool:
	return _real_art


## 某类 tile 的变体数量（0 = 该类不可用）
func variant_count(kind: int) -> int:
	var arr: Array = _regions.get(kind, [])
	return arr.size()


## 取某类 tile 第 variant_index 个变体的图集区域（自动取模，负数也安全）
func region_for(kind: int, variant_index: int) -> Rect2:
	var arr: Array = _regions.get(kind, [])
	if arr.is_empty():
		return Rect2(0, 0, tile_size, tile_size)
	var n := arr.size()
	var i := variant_index % n
	if i < 0:
		i += n
	return arr[i]
