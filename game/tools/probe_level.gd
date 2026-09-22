## 关卡布局体检（开发用 · 不属于游戏玩法）
##
## 为什么要它：`ch1_l01` 的真渲染看起来是「一堵绿砖墙」，但「墙到底占多少」
## 只能靠数字说话。本工具把一张布局变成可比较的指标，供「第一关视觉定稿」
## 前后对比用。
##
## 打印内容（每关一段）：
##   1. 来源：手绘（`layout.cells`）/ 程序化
##   2. 尺寸 + 墙 / 可走 / 障碍的格数与占比
##   3. 出生点 + 出生点 3×3 邻域的可走格数（**识别「出生在 1 格壁龛里」**）
##   4. 从出生点 4 连通 flood fill 的可达格数 vs 可走格总数
##   5. `level_scene.gd:_build_collision()` 的碰撞形状数：
##      逐格一个 vs 贪心横向合并后，以及降幅
##   6. ASCII 预览（墙 `#` / 可走 `.` / 障碍 `o` / 出生 `@`）
##
## ⚠️ 第 5 项的存在理由：`_build_collision()` 对每个墙/障碍格建一个
##    `CollisionShape2D`。程序化关卡先把整张网格填满墙再挖房间
##    （`level_generator.gd` 的 `cells[Vector2i(x,y)] = TILE_WALL` 起手），
##    所以形状数可能是几百上千个 —— 这里给出真实数字与合并后的数字。
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/probe_level.tscn
##   godot --headless --path "D:/七傳說/game" res://tools/probe_level.tscn -- ch1_l01 ch1_l02
##   godot --headless --path "D:/七傳說/game" res://tools/probe_level.tscn -- --seed 20260921 ch1_l01
##
## ⚠️ 与 `level_scene.gd:354-356` 一致：只有当关卡数据里 `layout.seed != 0`
##    时游戏才会播种。**关卡没有 seed 时，游戏里的地图每次进都不一样** ——
##    本工具会明确打印这一点，因为「每局随机」的地图是无法做视觉定稿的。
extends Node

## 4 邻域（与 `level_generator.gd` 的连通性判定保持同一套，别另写）
const NEIGHBORS_4: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## 默认体检对象：demo 抓图用的第一关 + 唯一一关手绘（对照组）
const DEFAULT_IDS: Array[String] = ["ch1_l01", "ch1_l02"]

## 播种值。`null` = **不播种**，即模拟游戏真实行为
## （`level_scene.gd:354` 只在关卡数据带非零 seed 时才播种）。
var _seed: Variant = null


func _ready() -> void:
	var ids: Array[String] = []
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1])
			i += 2
			continue
		if a.begins_with("--"):
			i += 1
			continue
		ids.append(a)
		i += 1
	if ids.is_empty():
		ids = DEFAULT_IDS.duplicate()

	print("===== 关卡布局体检（%s）====="
		% ("seed=%d" % int(_seed) if _seed != null
			else "**不播种 = 模拟游戏真实行为**；用 --seed N 可复现"))
	for id in ids:
		_probe(id)
	print("===== 结束 =====")
	get_tree().quit(0)


func _probe(id: String) -> void:
	var lv: LevelData = ConfigLoader.get_level(id)
	print("")
	print("──────────────────────────────────────────────────────────────")
	if lv == null:
		print("[%s] 找不到该关卡（ConfigLoader.get_level 返回 null）" % id)
		return

	# 游戏内的确定性：`level_scene.gd:354` 只在 layout.seed != 0 时播种。
	# ⚠️ **手绘关卡（layout.cells）根本不走 RNG** —— `_generate_authored()` 不调用任何 rng.*，
	#    格子是照数据抄的，所以**播不播种都每局相同**。
	#    这里必须分三态报，否则会对着一张稳定地图打出「每局地图都不同」的错误结论
	#    （2026-09-21 实际发生过：`ch1_l01` 改成手绘后本行仍在报「每局都不同」，
	#     连跑 3 次指纹均为 775561156 —— 诊断工具撒谎比没有诊断更糟）。
	var game_seed := int(lv.layout.get("seed", 0))
	var authored := lv.layout.has("cells")
	var determinism := ""
	if authored:
		determinism = "n/a（**手绘 ⇒ 不走 RNG，与 seed 无关，每局相同**）"
	elif game_seed != 0:
		determinism = "%d（每局相同）" % game_seed
	else:
		determinism = "**未设 ⇒ 每局地图都不同**"
	print("[%s] %s · 来源=%s · 游戏内 seed=%s"
		% [id, lv.display_name, "手绘 layout.cells" if authored else "程序化", determinism])

	var rng := RandomNumberGenerator.new()
	if _seed != null:
		rng.seed = int(_seed)
	var layout: Dictionary = LevelGenerator.generate(lv, rng)
	if layout.is_empty():
		print("  布局生成失败")
		return
	var cells: Dictionary = layout.get("cells", {})
	var w := int(layout.get("width", 0))
	var h := int(layout.get("height", 0))

	var n_wall := 0
	var n_ground := 0
	var n_obstacle := 0
	for key in cells:
		match int(cells[key]):
			LevelGenerator.TILE_WALL:
				n_wall += 1
			LevelGenerator.TILE_GROUND:
				n_ground += 1
			LevelGenerator.TILE_OBSTACLE:
				n_obstacle += 1
	var total := maxi(cells.size(), 1)
	print("  尺寸 %d×%d（%d 格）  墙 %d(%.0f%%)  可走 %d(%.0f%%)  障碍 %d(%.0f%%)"
		% [w, h, cells.size(), n_wall, 100.0 * n_wall / total,
			n_ground, 100.0 * n_ground / total, n_obstacle, 100.0 * n_obstacle / total])

	# 出生点邻域：识别「出生点被塞进 1 格壁龛」（程序化关卡把中心格强行设成地面，
	# 若中心本来在墙体深处，就会造出这种只有 1 格能站的落点）
	var spawn: Vector2i = layout.get("player_spawn", Vector2i(-1, -1))
	if spawn == Vector2i(-1, -1):
		print("  出生点：无（生成被拒）")
	else:
		var open_nb := 0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if _walkable(cells, spawn + Vector2i(dx, dy)):
					open_nb += 1
		print("  出生点 %s · 3×3 邻域可走 %d/9%s"
			% [str(spawn), open_nb, "  ⚠️ 壁龛（活动范围极小）" if open_nb <= 2 else ""])

	# 4 连通可达性（与 `level_generator.gd` 的 AUTHORED 判定同一套规则）。
	# ⚠️ 口径：`AUTHORED_BLOCKING = [TILE_WALL, TILE_OBSTACLE]` ⇒ **障碍也挡人**，
	#    所以「应该可达」的只有**地面**格。障碍格不可达是**正确**的，不是缺陷
	#    —— 早先版本拿「地面+障碍」当分母，会打出误导性的「有走不到的格子」。
	if spawn != Vector2i(-1, -1):
		var seen := {}
		var stack: Array[Vector2i] = [spawn]
		seen[spawn] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in NEIGHBORS_4:
				var n: Vector2i = c + d
				if seen.has(n) or not _walkable(cells, n):
					continue
				seen[n] = true
				stack.append(n)
		print("  从出生点 4 连通可达地面 %d / %d%s（障碍 %d 格按设计不可达，不计）"
			% [seen.size(), n_ground,
				"" if seen.size() == n_ground else "  ⚠️ 有地面格走不到",
				n_obstacle])

	# 布局指纹：同一 seed 下应恒定；用于验证「游戏内是否每局都变」
	# 手绘关卡不受 seed 影响 ⇒ 连跑多次指纹必须相同（这是「地图已稳定」的直接证据）。
	print("  布局指纹 = %d（同布局应恒定；手绘 ⇒ 连跑多次必须相同）" % _fingerprint(cells, w, h))

	# 碰撞形状数：逐格 vs 贪心横向合并
	var per_cell := n_wall + n_obstacle
	var merged := _merged_runs(cells, w, h)
	var pct := 100.0 * (1.0 - float(merged) / float(maxi(per_cell, 1)))
	print("  碰撞形状：逐格 %d 个 → 贪心横向合并 %d 个（降 %.0f%%）"
		% [per_cell, merged, pct])

	_print_ascii(cells, w, h, spawn)


## 可走 = 地面或障碍？（**不是**。判定依据与 `level_generator.gd:AUTHORED_BLOCKING`
## 一致：墙与障碍都挡人。）本函数只回答「这一格是不是地面类」。
func _walkable(cells: Dictionary, c: Vector2i) -> bool:
	if not cells.has(c):
		return false
	return int(cells[c]) == LevelGenerator.TILE_GROUND


## 布局指纹：按 (y, x) 顺序把 tile 值折进一个整数。
## 不依赖 Dictionary 迭代顺序 ⇒ 同一张图恒定得同一个值，可用来判定「两次生成的图是否一样」。
func _fingerprint(cells: Dictionary, w: int, h: int) -> int:
	var hsh := 0
	for y in h:
		for x in w:
			hsh = (hsh * 31 + int(cells.get(Vector2i(x, y), LevelGenerator.TILE_WALL))) & 0x7fffffff
	return hsh


## 贪心横向合并：同一行里连续的「挡人格」并成一个矩形，返回矩形总数。
## 用于估算把「每格一个 CollisionShape2D」改成「每条连续段一个」能省多少。
func _merged_runs(cells: Dictionary, w: int, h: int) -> int:
	var runs := 0
	for y in h:
		var in_run := false
		for x in w:
			var t := int(cells.get(Vector2i(x, y), LevelGenerator.TILE_GROUND))
			var blocking := t == LevelGenerator.TILE_WALL or t == LevelGenerator.TILE_OBSTACLE
			if blocking and not in_run:
				runs += 1
			in_run = blocking
	return runs


func _print_ascii(cells: Dictionary, w: int, h: int, spawn: Vector2i) -> void:
	print("  ASCII（# 墙 / . 可走 / o 障碍 / @ 出生）：")
	for y in h:
		var line := ""
		for x in w:
			if Vector2i(x, y) == spawn:
				line += "@"
				continue
			match int(cells.get(Vector2i(x, y), LevelGenerator.TILE_WALL)):
				LevelGenerator.TILE_GROUND:
					line += "."
				LevelGenerator.TILE_OBSTACLE:
					line += "o"
				_:
					line += "#"
		print("    " + line)
