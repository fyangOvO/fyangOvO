## 关卡 / 地图生成器（任务 6.1 · class_name）
##
## GDD 6.1（手工 + 程序化生成）：20 关 × 5 难度层级；单关内容量 v1.8
## （杂兵按关卡预算 / 精英 8–10 / BOSS 每章末）。
##
## 两种模式，由 `layout` 里**有没有 `cells` 键**二选一：
##
##   A. **程序化**（`layout` 无 `cells`）—— 缺省路径。
##      种子化网格地图（随机游走挖房间 + 走廊连接），tile 32px。
##      布局输出纯数据（字典 / 锚点列表），由场景层消费生成 TileMapLayer。
##      玩家出生在首个房间中心；怪物按 monster_entries 权重分布（距出生 ≥6 格）；
##      精英 / BOSS 锚点按关卡定义放置；祭坛 / 商店点按布局随机。
##
##   B. **手绘**（`layout.cells` 存在）—— 见 `_generate_authored()`。
##      用户直接画一张字符地图，生成器只做「解析 + 校验 + 发牌」。
##
## ---------------------------------------------------------------------------
## 手绘地图格式（用户可用；逐字示例见 `game/data/levels/chapter1.json` 的 ch1_l02）
## ---------------------------------------------------------------------------
## 在关卡条目的 `layout` 里加 `cells`，值为**行字符串数组**（一行一个字符串）：
##
##   "layout": {
##     "cells": [
##       "####################",
##       "#@.......#.........#",
##       "#........#....o....#",
##       "#...##...#.........#",
##       "#...##.............#",
##       "#........#....m....#",
##       "#..e.....#....B....#",
##       "#........#.........#",
##       "####################"
##     ]
##   }
##
## 注意第 4 行（`#...##.............#`）在 x=9 处是**地面**——它是左右两半唯一
## 的连通口。手绘地图最容易犯的错就是「画了个漂亮但进不去的房间」，而那种图在
## 目标要求清空 / 击杀时会让玩家硬卡死（见下方校验第 10 条）。
##
## 字符图例（`AUTHORED_CHARS`，可用 `layout.legend` 逐字符覆盖）：
##   '#' 墙      '.' 地面    'o' 障碍    ' ' 地面（等同 '.'，纯视觉留白）
##   '@' 玩家出生（**恰好 1 个**）
##   'm' 杂兵锚点（≥1 个，且 ≤ 本关 Σcount_max）
##   'e' 精英锚点（个数必须 == `elite_count`）
##   'B' BOSS 锚点（`boss_id` 非空时**恰好 1 个**；否则必须 0 个）
##   'p' 拾取 / 祭坛锚点（≥1 个；目标为 `collect` 时 ≥ `objective_value`）
##
## **为什么选「行字符串」而不是 `[x, y, kind]` 三元组**：
##   ① 所见即所得 —— 手绘地图的全部价值就是「看得见形状」，三元组要先在脑子里反解坐标；
##   ② 不会漂移 —— 坐标表与几何是两份数据，改了地图忘了改坐标 ⇒ 出生点落进墙里；
##      行字符串里出生点就是地图上的一个字符，改地图必然改到它；
##   ③ git diff 可读 —— 改一格只动一行里的一个字符，review 时一眼看出改了哪面墙。
##   （三元组形式对本项目的收益只有「用脚本批量生成」，而那用行字符串同样好生成。）
##
## 手绘模式的**确定性**：整条路径不消耗 `rng`，同一份 JSON 每次产出完全相同的
## `cells` 与锚点（程序化模式的 `seed` 对手绘模式无意义）。
##
## 手绘模式的**校验**：任何一条不满足都 `push_error` 并返回一个
## `player_spawn == (-1,-1)` 的**残缺布局**（而不是静默给一张打不通的图）。
## 校验清单见 `_generate_authored()` 内注释。
##
## ---------------------------------------------------------------------------
## 输出契约（两种模式**完全一致**，消费点见 README 4.10）
## ---------------------------------------------------------------------------
##   cells:          Dictionary[Vector2i -> int]   → `LevelView.set_layout()`
##   player_spawn:   Vector2i                      → `LevelScene._ready()` 放玩家
##   monster_spawns: [{cell, monster_id}]          → `LevelScene._spawn_monsters()`
##   elite_spawns:   [Vector2i]                    → `LevelScene._spawn_elites()`
##   boss_spawn:     Vector2i（无则 (-1,-1)）       → `LevelScene` 放 BOSS
##   pickup_spawns:  [Vector2i]                    → `LevelScene._spawn_collectibles()`
##   width/height:   int                           → 相机边界 / 渲染范围
##   seed:           int                           → 仅程序化模式有意义
##   authored:       bool（**仅手绘路径带这个键**）  → `is_authored()` / `verify_level_gen` H 段
class_name LevelGenerator
extends RefCounted

const TILE_SIZE := 32
const TILE_GROUND := 0
const TILE_WALL := 1
const TILE_OBSTACLE := 2

## 布局参数（数据驱动，缺省值）
const DEFAULT_LAYOUT := {
	"width": 40, "height": 30, "room_count": 10, "room_min": 5, "room_max": 10,
	"obstacle_density": 0.05, "seed": 0,
}

## 手绘地图字符 → tile 类型（`layout.legend` 可逐字符覆盖）。
## 标记字符（@ m e B p）同时是**地面**：标记画在哪，哪就必须能站人。
const AUTHORED_CHARS := {
	"#": TILE_WALL,
	".": TILE_GROUND,
	" ": TILE_GROUND,
	"o": TILE_OBSTACLE,
	"@": TILE_GROUND,
	"m": TILE_GROUND,
	"e": TILE_GROUND,
	"B": TILE_GROUND,
	"p": TILE_GROUND,
}

## 手绘地图字符 → 锚点种类（不在表内的字符只决定 tile 类型，不产生锚点）
const AUTHORED_MARKERS := {
	"@": "player", "m": "monster", "e": "elite", "B": "boss", "p": "pickup",
}

## 手绘地图的「可通行」判定 —— **唯一来源**，别在别处再写一套。
##
## 判定依据全部来自真实代码（不是猜的，也不是我另定的规则）：
##   · `scenes/player/player.tscn`：Player 是 `CharacterBody2D`，`collision_mask = 1`；
##     README 第七节的层表里 **层 1 = `world`（地形 / 墙体）**
##     ⇒ 玩家**设计上**就是会被墙挡住的。
##   · `scripts/run/level_scene.gd:_build_collision()`（2026-09-21「碰撞线收口」）：
##     运行时建出 `TileCollision`（`StaticBody2D`，`collision_layer = 1`），
##     把 `TILE_WALL` + `TILE_OBSTACLE` 按矩形并集铺成碰撞面。
##     **碰撞体今天真的存在**，所以本判定与物理现实**已经一致** —— 不再是「提前算」。
##   · `enemies/enemy_base.gd:800`：「追击：朝玩家直线移动……俯视 ARPG **无寻路**」
##     ⇒ 敌人不走格子图，代码里不存在「敌人的连通性」这回事。
##     但敌人是 `CharacterBody2D` 且 `collision_mask = 1`（world 层）⇒ 撞墙会被挡住。
##     ⚠️ 2026-09-21 实测补记：这句话**曾经是假话**，而且是**两层**假话：
##       ① `scenes/enemies/enemy_base.tscn` 的 `CollisionShape2D` 漏写 `type="CollisionShape2D"`
##          （全项目唯一一处）⇒ Godot 实例化时**静默丢弃**该节点 ⇒ 敌人从 2.4 起
##          **一直没有碰撞体** ⇒ 穿墙 / 穿玩家 / 彼此穿过。少一个 `type=` 就够了。
##       ② `collision_layer = 3` 是「层 1+2（world+player）」而非 README §7 层表里的
##          「层 3 = enemy」⇒ 敌人被放到了**地形层**上，玩家（mask=1）会撞到怪。
##     两处均已修（layer=4 / mask=1），并由 `tools/verify_knockback.gd` A 段
##     「敌人场景自带 CollisionShape2D」+「层契约 layer=4 / mask=1」盯死。
##     `mask` **刻意不含玩家层**：那属 README 任务 10.10（需先给攻击判定加迟滞，
##     否则贴脸时被物理分离推到 ≈34px、正好卡在 `attack_range` 上 ⇒ CHASE↔ATTACK 震荡）。
##     于是「把怪画在封闭隔间里」= 它出不来、你也进不去 ⇒ `clear_all` 永远打不通。
##
## 为什么仍然要这一条（手绘真正会犯的错）：
##   「画了个漂亮但进不去的房间 / 关在墙里的怪」—— 那立刻变成 ch1_l03 那类
##   「目标不可达 ⇒ 玩家硬卡死、无任何提示」。程序化路径天然连通（先造房间再挖走廊），
##   手绘会出这个错，所以校验必须在这里。
##
## 历史（别删，这是「为什么曾经按设计意图算」的答案）：
##   2026-09-21 之前 `level.tscn` 整棵树没有任何物理体，`LevelView` 只是纯 `Node2D`
##   （`level_view.gd:20` 只画不碰撞）⇒ 那时墙**不**挡人，本判定是「按设计意图提前算」的，
##   并留了一条 canary 断言盯着这个差异。`TileCollision` 落地后 canary 已**翻转**为
##   「要求碰撞体存在」（`verify_level_gen` H 段：「关卡运行时**真的**建出了地形碰撞体
##   TileCollision」+「碰撞体覆盖格集合 == 挡人格集合」逐格枚举比较）。
##   两者现在是同一件事 —— 这正是当初写 canary 想要的结果：物理现实变了，断言跟着变红，
##   逼着回来重读本段，而不是让校验悄悄退化成「测一个不存在的世界」。
##
## 连通性取 **4 连通**（不是 8 连通）：玩家的碰撞形状是 `RectangleShape2D(20, 22)`
## （`player.tscn`），半宽 10px > 0 ⇒ 两个**对角相接**的墙格之间没有能挤过去的缝。
## 用 8 连通会把「只能斜着挤过去」的假通路算成连通，等于把校验放水。
const AUTHORED_BLOCKING: Array[int] = [TILE_WALL, TILE_OBSTACLE]

## 4 邻域偏移（提出来做 const，避免 flood fill 每轮重建数组）
const NEIGHBORS_4: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## 手绘分支被**真正走到**的次数。
## ⚠️ 存在的唯一理由：本项目已 10 次踩「产出了但没人消费 / 写了但走不到」。
## `verify_level_gen` 的 H 段靠它断言「手绘分支确实被执行了」——
## 只断言「地图长对了」是不够的，那可能是程序化路径碰巧长成那样。
static var authored_hits: int = 0

## 最近一次手绘解析的校验错误（空 = 合法）。供 verify / 工具读取。
static var last_authored_errors: Array[String] = []

## 生成关卡布局：返回 {cells: {Vector2i: int}, player_spawn: Vector2i,
##   monster_spawns: [{cell, monster_id}], elite_spawns: [Vector2i],
##   boss_spawn: Vector2i, pickup_spawns: [Vector2i], width, height, seed}
static func generate(level_def: LevelData, rng: RandomNumberGenerator) -> Dictionary:
	var layout: Dictionary = level_def.layout if not level_def.layout.is_empty() else DEFAULT_LAYOUT
	# 手绘分支：`layout.cells` 存在即接管。缺省（19 关）不带这个键，行为与以前逐字节一致。
	if layout.has("cells"):
		return _generate_authored(level_def, layout)
	var width := int(layout.get("width", 40))
	var height := int(layout.get("height", 30))
	var cells := {}
	# 1) 全墙
	for y in range(height):
		for x in range(width):
			cells[Vector2i(x, y)] = TILE_WALL
	# 2) 拒绝采样挖房间（独立随机位置，间隔 ≥2 格，保证地面充足）
	var room_count := int(layout.get("room_count", 10))
	var room_min := int(layout.get("room_min", 5))
	var room_max := int(layout.get("room_max", 10))
	var rooms: Array[Rect2i] = []
	var carved: Array[Vector2i] = []
	var attempts := 0
	while rooms.size() < room_count and attempts < 200:
		attempts += 1
		var rw := rng.randi_range(room_min, room_max)
		var rh := rng.randi_range(room_min, room_max)
		var corner := Vector2i(
			rng.randi_range(1, width - rw - 2),
			rng.randi_range(1, height - rh - 2))
		var rect := Rect2i(corner, Vector2i(rw, rh))
		if _overlaps(rect, rooms, 2):
			continue
		rooms.append(rect)
		for y in range(corner.y, corner.y + rh):
			for x in range(corner.x, corner.x + rw):
				cells[Vector2i(x, y)] = TILE_GROUND
				carved.append(Vector2i(x, y))
	# 3) 顺序连接相邻房间（走廊）
	for i in range(1, rooms.size()):
		_carve_hall(cells, rooms[i - 1].get_center(), rooms[i].get_center(), width, height)
	# 3) 障碍（地面格随机密度）
	var obstacle_density := float(layout.get("obstacle_density", 0.05))
	for c in carved:
		if cells[c] == TILE_GROUND and rng.randf() < obstacle_density:
			cells[c] = TILE_OBSTACLE
	# 4) 玩家出生 = **首个房间中心**。
	#    ⚠️ 2026-09-18 修正：此前取 `carved[0]`，那是第一个房间的**左上角**（注释写的是
	#    「中心」，实现不是）。出生点贴在地图角落，叠加「相机原先没有边界限制」后，
	#    窗口化实测整屏一半是地图外的纯黑 void。**这类问题无头测试永远看不见**
	#    （108 项自检 + 36 个 verify 全绿，但没人渲染过一帧）。
	var player_spawn := Vector2i(width / 2, height / 2)
	if not rooms.is_empty():
		player_spawn = rooms[0].get_center()
	# 出生点必须可站：障碍是挖完房间后随机撒的，可能正好盖住房间中心
	cells[player_spawn] = TILE_GROUND
	# 5) 怪物分布：按 monster_entries 权重，距离出生 ≥ 6 格
	var monster_spawns: Array[Dictionary] = []
	var entries: Array = level_def.monster_entries
	var total_weight := 0.0
	for e in entries:
		total_weight += float(e.get("weight", 1.0))
	var ground: Array[Vector2i] = []
	for c in carved:
		if cells[c] == TILE_GROUND and _dist(c, player_spawn) >= 6.0:
			ground.append(c)
	if total_weight > 0.0 and not ground.is_empty():
		for e in entries:
			var n := rng.randi_range(
				int(e.get("count_min", 0)), int(e.get("count_max", 0)))
			for i in n:
				monster_spawns.append({
					"cell": ground[rng.randi_range(0, ground.size() - 1)],
					"monster_id": str(e.get("monster_id", "")),
				})
	# 6) 精英锚点（按定义数量，远离出生）
	var elite_spawns: Array[Vector2i] = []
	var elite_count := int(level_def.elite_count)
	for i in elite_count:
		if ground.is_empty():
			break
		elite_spawns.append(ground[rng.randi_range(0, ground.size() - 1)])
	# 7) BOSS 锚点（远离出生，优先地图远端）
	var boss_spawn := Vector2i(-1, -1)
	var boss_id := str(level_def.boss_id)
	if not boss_id.is_empty() and not ground.is_empty():
		var far := ground[0]
		for c in ground:
			if _dist(c, player_spawn) > _dist(far, player_spawn):
				far = c
		boss_spawn = far
	# 8) 拾取点（祭坛 / 商店候选，随机 2–3 个）
	var pickup_spawns: Array[Vector2i] = []
	var pickup_n := rng.randi_range(2, 3)
	for i in pickup_n:
		if ground.is_empty():
			break
		pickup_spawns.append(ground[rng.randi_range(0, ground.size() - 1)])
	return {
		"cells": cells, "player_spawn": player_spawn,
		"monster_spawns": monster_spawns, "elite_spawns": elite_spawns,
		"boss_spawn": boss_spawn, "pickup_spawns": pickup_spawns,
		"width": width, "height": height, "seed": int(layout.get("seed", 0)),
	}


## 手绘地图分支：把 `layout.cells` 的字符地图解析成与程序化路径**同契约**的布局。
##
## 与程序化路径的关键差异：本函数**不消耗 `rng`**（手绘 = 确定性），
## 且不按权重随机撒怪 —— 怪物锚点就是用户画的 'm' 的位置。
##
## 校验清单（任一不满足 → `push_error` + 返回残缺布局，绝不静默产出打不通的图）：
##   1. `cells` 非空、元素全是字符串、各行等长；
##   2. 每个字符都在图例里（未定义字符直接报出「第几行第几列是什么」）；
##   3. 玩家标记 '@' **恰好 1 个**，且落在可走地面（标记本身即地面）；
##   4. 地图**四边全是墙** —— 本项目 2026-09-18 踩过「出生点贴边 + 相机无边界
##      ⇒ 整屏一半是地图外 void」；手绘时最容易犯的就是忘了封边；
##   5. 杂兵 'm' ≥1 个、≤ Σcount_max（超预算就是超出本关设计内容量）；
##      且每个 'm' 距玩家出生 ≥6 格（与程序化路径同一条口径，verify 的 D 段依赖它）；
##   6. 精英 'e' 个数 == `elite_count`（保持 `elite_spawns.size() == elite_count` 不变式）；
##   7. `boss_id` 非空 ⇒ 'B' 恰好 1 个；`boss_id` 为空 ⇒ 'B' 必须 0 个；
##   8. 拾取 'p' ≥1 个；目标是 `collect` 时 ≥ `objective_value`；
##   9. 若同时写了 `layout.width/height`，必须与行数 / 行宽一致（防止改了地图忘改尺寸）；
##  10. **连通性**：从 '@' 出发，四类锚点全部可达，且不存在孤立可行走区域
##      （口径与「为什么今天仍要按设计意图算」见 `AUTHORED_BLOCKING` 的说明）。
static func _generate_authored(level_def: LevelData, layout: Dictionary) -> Dictionary:
	authored_hits += 1
	var errors: Array[String] = []
	var cells := {}
	var markers: Array[Dictionary] = []
	var width := 0
	var height := 0

	# ---- 1) 逐字符解析 -------------------------------------------------------
	var rows: Variant = layout.get("cells", [])
	if not (rows is Array) or (rows as Array).is_empty():
		errors.append("layout.cells 必须是非空的行字符串数组（一行一个字符串）")
	else:
		var lines: Array = rows as Array
		height = lines.size()
		var legend := _authored_legend(layout)
		# 标记字符画在哪、哪就必须能站人 —— 不允许用 `legend` 把 '@ m e B p' 改成墙 / 障碍
		for ch in AUTHORED_MARKERS:
			if int(legend[ch]) != TILE_GROUND:
				errors.append("layout.legend 把标记字符 '%s' 改成了非地面（标记格必须可走）" % ch)
		for y in height:
			var row: Variant = lines[y]
			if not (row is String):
				errors.append("layout.cells[%d] 不是字符串（行字符串形式要求每行都是字符串）" % y)
				continue
			var line: String = row
			if y == 0:
				width = line.length()
			elif line.length() != width:
				errors.append("layout.cells 第 %d 行长度 %d ≠ 第 0 行长度 %d（每行必须等长）"
					% [y, line.length(), width])
			for x in line.length():
				var ch := line[x]
				if not legend.has(ch):
					var names: Array[String] = []
					for k in legend:
						names.append("'%s'" % k)
					errors.append("layout.cells 第 %d 行第 %d 列出现未定义字符 '%s'（可用字符：%s）"
						% [y, x, ch, ", ".join(names)])
					continue
				cells[Vector2i(x, y)] = int(legend[ch])
				if AUTHORED_MARKERS.has(ch):
					markers.append({"kind": str(AUTHORED_MARKERS[ch]), "cell": Vector2i(x, y)})

	# ---- 2) 收集锚点（`markers` 按行主序，结果确定）---------------------------
	var players: Array[Vector2i] = []
	var monster_cells: Array[Vector2i] = []
	var elite_cells: Array[Vector2i] = []
	var boss_cells: Array[Vector2i] = []
	var pickup_cells: Array[Vector2i] = []
	for m in markers:
		var c: Vector2i = m["cell"]
		match str(m["kind"]):
			"player": players.append(c)
			"monster": monster_cells.append(c)
			"elite": elite_cells.append(c)
			"boss": boss_cells.append(c)
			"pickup": pickup_cells.append(c)

	var player_spawn := Vector2i(-1, -1)
	if players.size() != 1:
		errors.append("手绘地图需要**恰好 1 个**玩家出生标记 '@'（当前 %d 个）" % players.size())
	else:
		player_spawn = players[0]
		# 保持与程序化路径同一不变式：出生点必可站（`generate()` 程序化分支同样强制置地面）
		cells[player_spawn] = TILE_GROUND

	# ---- 3) 封边（防「整屏 void」，见函数头 4）--------------------------------
	if width > 0 and height > 0:
		var open_cells: Array[String] = []
		for x in width:
			for y in [0, height - 1]:
				if int(cells.get(Vector2i(x, y), TILE_WALL)) != TILE_WALL:
					open_cells.append("第%d行第%d列" % [y, x])
		for y in height:
			for x in [0, width - 1]:
				if int(cells.get(Vector2i(x, y), TILE_WALL)) != TILE_WALL:
					open_cells.append("第%d行第%d列" % [y, x])
		if not open_cells.is_empty():
			errors.append("地图四边必须全是墙（未封边：%s）" % ", ".join(open_cells))

	# ---- 4) 尺寸字段一致性 ---------------------------------------------------
	if layout.has("width") and int(layout.get("width", 0)) != width:
		errors.append("layout.width=%d 与手绘行宽 %d 不一致（手绘时以 cells 为准，建议删掉 width/height）"
			% [int(layout.get("width", 0)), width])
	if layout.has("height") and int(layout.get("height", 0)) != height:
		errors.append("layout.height=%d 与手绘行数 %d 不一致（手绘时以 cells 为准，建议删掉 width/height）"
			% [int(layout.get("height", 0)), height])

	# ---- 5) 杂兵 -------------------------------------------------------------
	# 预算不含 BOSS 条目：BOSS 由 'B' 锚点单独刷，不参与 'm' 发牌（见第 9 步）
	var budget_max := 0
	for e in level_def.monster_entries:
		if _is_boss_entry(level_def, e):
			continue
		budget_max += int(e.get("count_max", 0))
	if monster_cells.is_empty():
		errors.append("手绘地图没有任何杂兵标记 'm'（本关 monster_entries=%d 条，必须有敌人）"
			% level_def.monster_entries.size())
	elif budget_max > 0 and monster_cells.size() > budget_max:
		errors.append("手绘地图有 %d 个杂兵标记 'm'，超过本关预算 Σcount_max=%d"
			% [monster_cells.size(), budget_max])
	if player_spawn != Vector2i(-1, -1):
		var too_close: Array[String] = []
		for c in monster_cells:
			if _dist(c, player_spawn) < 6.0:
				too_close.append("(%d,%d)" % [c.x, c.y])
		if not too_close.is_empty():
			errors.append("杂兵标记距玩家出生 < 6 格（出生即被围）：%s" % ", ".join(too_close))

	# ---- 6) 精英 / BOSS / 拾取 ----------------------------------------------
	if elite_cells.size() != level_def.elite_count:
		errors.append("手绘地图有 %d 个精英标记 'e'，与 elite_count=%d 不一致"
			% [elite_cells.size(), level_def.elite_count])
	if level_def.boss_id.is_empty():
		if not boss_cells.is_empty():
			errors.append("本关没有 boss_id，但手绘地图画了 %d 个 BOSS 标记 'B'"
				% boss_cells.size())
	elif boss_cells.size() != 1:
		errors.append("本关 boss_id='%s'，手绘地图需要**恰好 1 个** BOSS 标记 'B'（当前 %d 个）"
			% [level_def.boss_id, boss_cells.size()])
	var need_pickup := 1
	if level_def.objective_type == LevelData.ObjectiveType.COLLECT:
		need_pickup = maxi(1, int(level_def.objective_value))
	if pickup_cells.size() < need_pickup:
		errors.append("手绘地图有 %d 个拾取标记 'p'，至少需要 %d 个（目标类型 %s）"
			% [pickup_cells.size(), need_pickup, level_def.get_objective_name()])

	# ---- 7) 连通性（可达性）--------------------------------------------------
	# 为什么必须有这一条：程序化生成是「先造房间再挖走廊」，天然连通；
	# **手绘会出问题** —— 一个人随手多画一个封闭的小隔间、往里面塞两只怪，
	# `clear_all` 就永远打不通了，玩家硬卡死且没有任何提示。
	# 这与 ch1_l03 的精英软锁是**同一类失败**（目标不可达），而「贴脸怪」「未封边」
	# 两条校验都挡不住它。判定口径见 `AUTHORED_BLOCKING` 的说明。
	if player_spawn != Vector2i(-1, -1) and width > 0 and height > 0:
		var reach := _reachable_from(cells, width, height, player_spawn)
		# ① 四类锚点必须都能从 '@' 走到
		var unreachable: Array[String] = []
		_collect_unreachable(unreachable, "'m'", monster_cells, reach)
		_collect_unreachable(unreachable, "'e'", elite_cells, reach)
		_collect_unreachable(unreachable, "'B'", boss_cells, reach)
		_collect_unreachable(unreachable, "'p'", pickup_cells, reach)
		if not unreachable.is_empty():
			errors.append("从玩家出生 '@'(第%d行第%d列) 走不到这些锚点：%s"
				% [player_spawn.y, player_spawn.x, ", ".join(unreachable)])
		# ② 不允许存在「孤立可行走区域」——
		#    这一条提前挡住「画了个漂亮但进不去的房间」，且它比 ① 更严格：
		#    哪怕那个房间是空的、没有任何锚点，也照样报。
		var stranded: Array[String] = []
		for c in cells:
			if _is_walkable_kind(int(cells[c])) and not reach.has(c):
				stranded.append("第%d行第%d列" % [c.y, c.x])
		if not stranded.is_empty():
			var head := ", ".join(stranded.slice(0, 8))
			errors.append("存在 %d 个可行走格从出生走不到（被墙 / 障碍围死了）：%s%s"
				% [stranded.size(), head, " …" if stranded.size() > 8 else ""])

	# ---- 8) 校验不过：响亮报错 + 返回残缺布局（player_spawn = (-1,-1)）-------
	last_authored_errors = errors.duplicate()
	if not errors.is_empty():
		for e in errors:
			push_error("[LevelGenerator] 手绘地图 '%s' 非法：%s" % [level_def.id, e])
		print("[LevelGenerator] 手绘地图 '%s' 有 %d 处非法，已放弃生成（详见上方 ERROR）"
			% [level_def.id, errors.size()])
		return {
			"cells": cells, "player_spawn": Vector2i(-1, -1),
			"monster_spawns": [], "elite_spawns": [],
			"boss_spawn": Vector2i(-1, -1), "pickup_spawns": [],
			"width": width, "height": height, "seed": int(layout.get("seed", 0)),
			"authored": true,
		}

	# ---- 9) 发牌：怪物 id 按 monster_entries 交错发（行主序 × 池循环）---------
	# 池的构造：先取各条目的 count_min（至少 1），**逐轮交错**而不是「整条排完再下一条」——
	# 交错后池是 [蜘蛛, 蝙蝠, 骷髅, 蜘蛛, 蝙蝠, 骷髅, ...]，行主序发下去时
	# 怪物类型在空间上也是混的；若整条排完，地图上半屏会全是同一只怪。
	#
	# ⚠️ BOSS 条目**不进池**：BOSS 由 'B' 锚点单独刷，而 `LevelScene` 走锚点生成时
	#    会**跳过** `monster_spawns` 里 `monster_id == boss_id` 的那条。若把 BOSS 发到
	#    某个 'm' 上，那个 'm' 会被静默丢弃 —— 用户数着 48 个 'm' 却只出现 47 只怪。
	var pool: Array[String] = []
	var rounds := 0
	for e in level_def.monster_entries:
		if _is_boss_entry(level_def, e):
			continue
		rounds = maxi(rounds, maxi(1, int(e.get("count_min", 1))))
	for i in rounds:
		for e in level_def.monster_entries:
			if _is_boss_entry(level_def, e):
				continue
			if i < maxi(1, int(e.get("count_min", 1))):
				pool.append(str(e.get("monster_id", "")))
	var monster_spawns: Array[Dictionary] = []
	for i in monster_cells.size():
		monster_spawns.append({
			"cell": monster_cells[i],
			"monster_id": pool[i % pool.size()] if not pool.is_empty() else "",
		})

	var boss_spawn := Vector2i(-1, -1)
	if boss_cells.size() == 1:
		boss_spawn = boss_cells[0]
	return {
		"cells": cells, "player_spawn": player_spawn,
		"monster_spawns": monster_spawns, "elite_spawns": elite_cells,
		"boss_spawn": boss_spawn, "pickup_spawns": pickup_cells,
		"width": width, "height": height, "seed": int(layout.get("seed", 0)),
		"authored": true,
	}


## 这个 tile 类型能不能站人。判定口径见 `AUTHORED_BLOCKING` 的说明。
static func _is_walkable_kind(kind: int) -> bool:
	return not AUTHORED_BLOCKING.has(kind)


## 这条 monster_entry 是不是本关的 BOSS 条目（`boss_id` 非空且 id 相同）。
## BOSS 条目不进 'm' 发牌池，也不计入 'm' 的预算上限 —— 理由见第 9 步的注释。
static func _is_boss_entry(level_def: LevelData, entry: Dictionary) -> bool:
	return not level_def.boss_id.is_empty() \
		and str(entry.get("monster_id", "")) == level_def.boss_id


## 从 `start` 做 **4 连通** flood fill，返回可达格集合 `{Vector2i: true}`。
##
## 连通性为什么取 4 连通见 `AUTHORED_BLOCKING` 的说明；边界外的格子按墙处理。
static func _reachable_from(cells: Dictionary, width: int, height: int,
		start: Vector2i) -> Dictionary:
	var seen := {}
	if not cells.has(start) or not _is_walkable_kind(int(cells[start])):
		return seen
	seen[start] = true
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in NEIGHBORS_4:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= width or n.y >= height:
				continue
			if seen.has(n) or not _is_walkable_kind(int(cells.get(n, TILE_WALL))):
				continue
			seen[n] = true
			queue.append(n)
	return seen


## 把 `cells` 里不在 `reach` 中的格子按「第 y 行第 x 列」追加进 `out`（带标记字符名）。
static func _collect_unreachable(out: Array[String], label: String,
		cells: Array[Vector2i], reach: Dictionary) -> void:
	for c in cells:
		if not reach.has(c):
			out.append("%s 第%d行第%d列" % [label, c.y, c.x])


## 手绘图例：默认 `AUTHORED_CHARS`，被 `layout.legend` 里出现的字符逐条覆盖。
## `layout.legend` 的值可以是类型名（"wall"/"ground"/"obstacle"）或 0/1/2。
static func _authored_legend(layout: Dictionary) -> Dictionary:
	var legend := AUTHORED_CHARS.duplicate()
	var over: Variant = layout.get("legend", {})
	if not (over is Dictionary):
		return legend
	for ch in (over as Dictionary):
		var v: Variant = (over as Dictionary)[ch]
		if v is int or v is float:
			legend[String(ch)] = int(v)
		else:
			match str(v):
				"ground": legend[String(ch)] = TILE_GROUND
				"wall": legend[String(ch)] = TILE_WALL
				"obstacle": legend[String(ch)] = TILE_OBSTACLE
	return legend


## 这份布局是否来自手绘地图（`layout.cells` 分支）。
##
## ⚠️ 不能用 `layout.has("cells")` 判断 —— 程序化路径**也**返回 `cells`。
## 手绘分支额外带 `"authored": true` 作为来源戳（程序化路径不带，保持逐字节不变）。
## 消费点：`tools/verify_level_gen.gd` H 段（断言机制被走到 + 地图与手绘一致）。
static func is_authored(layout: Dictionary) -> bool:
	return bool(layout.get("authored", false))


static func _carve_hall(cells: Dictionary, a: Vector2i, b: Vector2i,
		width: int, height: int) -> void:
	var x := a.x
	var y := a.y
	while x != b.x:
		x += 1 if b.x > x else -1
		cells[Vector2i(x, y)] = TILE_GROUND
	while y != b.y:
		y += 1 if b.y > y else -1
		cells[Vector2i(x, y)] = TILE_GROUND


## 房间是否与已存在房间重叠（gap = 最小间隔格数）
static func _overlaps(rect: Rect2i, rooms: Array[Rect2i], gap: int) -> bool:
	for r in rooms:
		if rect.grow(gap).intersects(r):
			return true
	return false


static func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()


## 布局统计（verify 用）：地面 / 墙 / 障碍计数
static func counts(layout: Dictionary) -> Dictionary:
	var ground := 0
	var wall := 0
	var obstacle := 0
	for c in layout["cells"]:
		match int(layout["cells"][c]):
			TILE_GROUND: ground += 1
			TILE_WALL: wall += 1
			_: obstacle += 1
	return {"ground": ground, "wall": wall, "obstacle": obstacle}
