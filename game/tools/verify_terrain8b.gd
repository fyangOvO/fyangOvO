## 地形素材接入实测（步骤 8B · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_terrain8b.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 背景：地形渲染（LevelView + TileAtlas 三套真实美术）与碰撞（_build_collision
##   矩形并集）在任务 8.3 已接通。本工具把「地形素材接入」的**数据契约**固化，
##   防止将来换瓦片 / 改数据时静默退化。与 verify_level_gen（布局生成机制）互补，
##   本工具只断言「美术与关卡数据的对接层」：
##
## 覆盖范围（6 个测试段）：
##   A. 三套真实美术可达：forest / volcanic / frost 的 res://assets/tilesets/*/atlas.png
##      + atlas.json 存在，TileAtlas.for_biome 加载成功（has_real_art），变体数 地6/墙3/障3，
##      且每类都能取到有效采样区域（Rect2 尺寸 == tile_size）
##   B. 20 关 biome 全覆盖：每关 biome_for_level 非空；第 1/2/3 章 → forest/volcanic/frost
##   C. 20 关布局可生成：cells 非空、玩家出生格是地面（可站）
##   D. 障碍覆盖：每关 cells 里 obstacle > 0（手绘 'o' / 程序化 density 复现），
##      且障碍占比 ≤ 25%（防密度失控堵死房间）
##   E. 出生四邻可走出：出生格 4 邻至少 1 格是地面（防止「出生即卡」）
##   F. tileset_path 兜底契约：数据表该字段全空时，默认 res://assets/tilesets/<biome>
##      路径必须可用（三套 png 都存在），且 20 关全部能通过默认路径取到图集
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()

const BIOME_PATHS := {
	"forest": "res://assets/tilesets/forest/atlas.png",
	"volcanic": "res://assets/tilesets/volcanic/atlas.png",
	"frost": "res://assets/tilesets/frost/atlas.png",
}
const BIOME_JSONS := {
	"forest": "res://assets/tilesets/forest/atlas.json",
	"volcanic": "res://assets/tilesets/volcanic/atlas.json",
	"frost": "res://assets/tilesets/frost/atlas.json",
}
const CHAPTER_BIOME := {1: "forest", 2: "volcanic", 3: "frost"}


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 地形素材接入实测（步骤 8B） =====")
	_rng.seed = 20260923
	await _test_art()
	await _test_biome_coverage()
	await _test_layout_gen()
	await _test_obstacle_coverage()
	await _test_spawn_exit()
	await _test_tileset_fallback()
	_finish()


# =============================================================================
# A. 三套真实美术可达
# =============================================================================

func _test_art() -> void:
	print("--- A. 三套真实美术可达 ---")
	for biome in BIOME_PATHS:
		var png_ok := ResourceLoader.exists(BIOME_PATHS[biome])
		var json_ok := FileAccess.file_exists(BIOME_JSONS[biome])
		_ok("%s：atlas.png + atlas.json 存在" % biome, png_ok and json_ok)
		var atlas := TileAtlas.for_biome(biome)
		_ok("%s：图集加载为真实美术（非程序化占位）" % biome,
			atlas != null and atlas.has_real_art() and atlas.texture() != null)
		var g: int = atlas.variant_count(LevelGenerator.TILE_GROUND)
		var w: int = atlas.variant_count(LevelGenerator.TILE_WALL)
		var o: int = atlas.variant_count(LevelGenerator.TILE_OBSTACLE)
		_ok("%s：变体 地%d/墙%d/障%d（契约 6/3/3）" % [biome, g, w, o],
			g >= 6 and w >= 3 and o >= 3)
		var regions_ok := true
		for kind in [LevelGenerator.TILE_GROUND, LevelGenerator.TILE_WALL,
				LevelGenerator.TILE_OBSTACLE]:
			var n: int = atlas.variant_count(kind)
			for i in n:
				var r := atlas.region_for(kind, i)
				if absf(r.size.x - atlas.tile_size) > 0.01 \
						or absf(r.size.y - atlas.tile_size) > 0.01:
					regions_ok = false
		_ok("%s：全部变体采样区域尺寸 == tile_size（无错位取样）" % biome, regions_ok)


# =============================================================================
# B. 20 关 biome 全覆盖
# =============================================================================

func _test_biome_coverage() -> void:
	print("--- B. 20 关 biome 全覆盖 ---")
	var all := ConfigLoader.get_levels_sorted()
	_ok("关卡总数 = 20", all.size() == 20)
	var mapped_ok := true
	var chapter_ok := true
	for lv in all:
		var b := TileAtlas.biome_for_level(lv)
		if b.is_empty():
			mapped_ok = false
		var expect: String = CHAPTER_BIOME.get(int(lv.chapter), "")
		if not expect.is_empty() and b != expect:
			chapter_ok = false
	_ok("每关 biome 映射非空", mapped_ok)
	_ok("章节 → biome 映射正确（1 森林 / 2 火山 / 3 霜渊）", chapter_ok)


# =============================================================================
# C. 20 关布局可生成
# =============================================================================

func _test_layout_gen() -> void:
	print("--- C. 20 关布局可生成 ---")
	var bad := 0
	for lv in ConfigLoader.get_levels_sorted():
		var layout := LevelGenerator.generate(lv, _rng)
		var cells: Dictionary = layout.get("cells", {})
		if cells.is_empty() or cells.size() < 100:
			bad += 1
			_ok("%s：cells 非空且 ≥100 格" % lv.id, false)
			continue
		var spawn: Vector2i = layout.get("player_spawn", Vector2i(-1, -1))
		if int(cells.get(spawn, -1)) != LevelGenerator.TILE_GROUND:
			bad += 1
			_ok("%s：出生格为地面" % lv.id, false)
	_ok("20 关全部：布局生成 + 出生格可站", bad == 0)


# =============================================================================
# D. 障碍覆盖
# =============================================================================

func _test_obstacle_coverage() -> void:
	print("--- D. 障碍覆盖 ---")
	var no_obstacle := 0
	var too_dense := 0
	for lv in ConfigLoader.get_levels_sorted():
		var layout := LevelGenerator.generate(lv, _rng)
		var cells: Dictionary = layout.get("cells", {})
		var obs := 0
		var total := 0
		for k in cells:
			var t: int = int(cells[k])
			total += 1
			if t == LevelGenerator.TILE_OBSTACLE:
				obs += 1
		if obs == 0:
			no_obstacle += 1
			_ok("%s：存在障碍格" % lv.id, false)
		if total > 0 and float(obs) / float(total) > 0.25:
			too_dense += 1
			_ok("%s：障碍占比 ≤ 25%%" % lv.id, false)
	_ok("20 关全部有障碍格（手绘 'o' / 程序化 density）", no_obstacle == 0)
	_ok("障碍占比全部 ≤ 25%%（防密度失控）", too_dense == 0)


# =============================================================================
# E. 出生四邻可走出
# =============================================================================

func _test_spawn_exit() -> void:
	print("--- E. 出生四邻可走出 ---")
	var stuck := 0
	for lv in ConfigLoader.get_levels_sorted():
		var layout := LevelGenerator.generate(lv, _rng)
		var cells: Dictionary = layout.get("cells", {})
		var spawn: Vector2i = layout.get("player_spawn", Vector2i(-1, -1))
		var exit_ok := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = spawn + d
			if cells.has(n) and int(cells[n]) != LevelGenerator.TILE_WALL \
					and int(cells[n]) != LevelGenerator.TILE_OBSTACLE:
				exit_ok = true
				break
		if not exit_ok:
			stuck += 1
			_ok("%s：出生四邻有可走格" % lv.id, false)
	_ok("20 关全部：出生格四邻可走出（无出生即卡）", stuck == 0)


# =============================================================================
# F. tileset_path 兜底契约
# =============================================================================

func _test_tileset_fallback() -> void:
	print("--- F. tileset_path 兜底契约 ---")
	# 数据表当前约定：20 关 tileset_path 全空 → TileAtlas 走默认
	# res://assets/tilesets/<biome>。断言默认路径确实可用（防止将来删图集）。
	var all := ConfigLoader.get_levels_sorted()
	var path_empty := true
	for lv in all:
		if not str(lv.tileset_path).is_empty():
			path_empty = false
	_ok("20 关 tileset_path 字段均为空（数据表约定走默认路径）", path_empty)
	var usable := true
	var seen := {}
	for lv in all:
		var b := TileAtlas.biome_for_level(lv)
		seen[b] = true
		var atlas := TileAtlas.for_biome(b)
		if atlas == null or atlas.texture() == null:
			usable = false
	_ok("三 biome 均出现且全部可通过默认路径取到图集",
		usable and seen.size() == 3 and seen.has("forest")
		and seen.has("volcanic") and seen.has("frost"))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
