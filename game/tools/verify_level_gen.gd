## 关卡 / 地图生成实测（任务 6.1 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_level_gen.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（9 个测试段）：
##   A. 关卡数据：三章 20 关、等级 1–20 连续、章节归属
##   B. 解锁链：顺序 unlock_requires 完整
##   C. 布局生成：地图尺寸 / 地面连通 / 玩家出生在地面
##   D. 怪物分布：权重投放数量 / 距出生 ≥6 格 / 全部地面
##   E. 精英与 BOSS：精英锚点数匹配 / BOSS 关有远端锚点 / 无 BOSS 关无锚点
##   F. 确定性：同种子同布局（种子可复现）
##   G. 目标可达性：20 关的目标**确定可完成**（不是「大概率能完成」）
##   H. 手绘地图（`layout.cells`）：机制**确实被走到** + 地图逐格等于手绘 + **连通性** +
##      `ch1_l01` 开局三条线 + 非法图会被拒 + canary 钉住地形碰撞体（挡人格集合逐格等价）
##   I. 形状合并等价性：**全部 20 关**逐格集合 == `_merge_blocking_rects()` 展开集合
extends Node

## canary 用真路径观察地形碰撞体，必须实例化关卡场景
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
## canary 用的关卡：**运行时挑**，不写死 id（见 `_pick_canary_level()`）。
##
## ⚠️ 2026-09-21 教训：先后写死过 `ch1_l01`、`ch1_l02`，两次都被 `map-author` 的手绘化
##    追上来。而手绘数据一旦处于**非法中间态**，`LevelGenerator` 就「放弃生成」⇒
##    canary 跟着假红，看起来像「碰撞体合并写坏了」。写死任何一关都是给别人的编辑
##    埋一颗地雷 ⇒ 改为「挑第一个生成成功、且挡人格 > 0 的**程序化**关卡」。
var _canary_level_id: String = ""

var _fail: int = 0
var _rng := RandomNumberGenerator.new()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 关卡 / 地图生成实测（任务 6.1） =====")
	_rng.seed = 20260917
	await _test_levels()
	await _test_unlock()
	await _test_layout()
	await _test_monsters()
	await _test_elite_boss()
	await _test_objective_reachable()
	await _test_determinism()
	await _test_authored()
	await _test_merge_equivalence()
	_finish()


# =============================================================================
# A. 关卡数据
# =============================================================================

func _test_levels() -> void:
	print("--- A. 关卡数据 ---")
	var all := ConfigLoader.get_levels_sorted()
	_ok("关卡总数 = 20", all.size() == 20)
	_ok("等级 1–20 连续", _levels_continuous(all))
	_ok("三章齐全（1 / 2 / 3）",
		ConfigLoader.get_levels_in_chapter(1).size() >= 6
		and ConfigLoader.get_levels_in_chapter(2).size() >= 7
		and ConfigLoader.get_levels_in_chapter(3).size() >= 7)
	var bad := 0
	for lv in all:
		if not lv.validate().is_empty():
			bad += 1
	_ok("全部关卡 validate 合法", bad == 0)


func _levels_continuous(all: Array) -> bool:
	for i in range(all.size()):
		if all[i].level != i + 1:
			return false
	return true


# =============================================================================
# B. 解锁链
# =============================================================================

func _test_unlock() -> void:
	print("--- B. 解锁链 ---")
	var all := ConfigLoader.get_levels_sorted()
	var chain_ok := true
	for lv in all:
		if lv.level == 1:
			continue
		var prev: LevelData = _level_by_number(lv.level - 1)
		if prev == null or lv.unlock_requires.size() != 1 \
				or lv.unlock_requires[0] != prev.id:
			chain_ok = false
	_ok("顺序解锁链完整（跨章连接）", chain_ok)


## 按关卡序号（1–20）取关卡（跨章：1–6=ch1 / 7–13=ch2 / 14–20=ch3）
func _level_by_number(n: int) -> LevelData:
	for lv in ConfigLoader.get_levels_sorted():
		if lv.level == n:
			return lv
	return null


# =============================================================================
# C. 布局生成
# =============================================================================

func _test_layout() -> void:
	print("--- C. 布局生成 ---")
	# ⚠️ 用 `ch1_l03`（**程序化**）而不是原先的 `ch1_l01`。
	#    2026-09-21 `map-author` 把 ch1_l01 手绘化（`layout.cells`）后，本段若仍拿 ch1_l01，
	#    测的就变成**手绘分支**了 —— 「程序化默认布局（DEFAULT_LAYOUT 的 40×30、房间+走廊）」
	#    这条覆盖会**静默消失**，而断言照样全绿。那正是本项目第 5 条规律
	#    （测试会静默变少却仍然报绿）。ch1_l03 与 ch1_l01 同为「第一章、无 layout ⇒
	#    DEFAULT_LAYOUT」，所以下面「尺寸 = 40×30」这条断言的含义**没有变**。
	var lv: LevelData = ConfigLoader.get_level("ch1_l03")
	var layout := LevelGenerator.generate(lv, _rng)
	var counts := LevelGenerator.counts(layout)
	_ok("地面充足（≥ 总格数 30%）",
		counts["ground"] >= int(layout["width"] * layout["height"]) * 0.3)
	_ok("墙存在（有边界）", counts["wall"] > 0)
	_ok("玩家出生在地面", int(layout["cells"][layout["player_spawn"]]) == LevelGenerator.TILE_GROUND)
	_ok("出生点在地图内", layout["player_spawn"].x >= 0 and layout["player_spawn"].y >= 0)
	_ok("尺寸匹配默认布局（ch1_l03 无 layout ⇒ 40×30）",
		layout["width"] == 40 and layout["height"] == 30)


# =============================================================================
# D. 怪物分布
# =============================================================================

func _test_monsters() -> void:
	print("--- D. 怪物分布 ---")
	var lv: LevelData = ConfigLoader.get_level("ch2_l10")
	var layout := LevelGenerator.generate(lv, _rng)
	var total := 0
	for e in lv.monster_entries:
		total += int(e.get("count_max", 0))
	_ok("投放数量在预算内（≤ Σcount_max）", layout["monster_spawns"].size() <= total)
	_ok("投放非空", layout["monster_spawns"].size() > 0)
	var on_ground := true
	var far_enough := true
	var player: Vector2i = layout["player_spawn"]
	for m in layout["monster_spawns"]:
		var cell: Vector2i = m["cell"]
		if int(layout["cells"][cell]) != LevelGenerator.TILE_GROUND:
			on_ground = false
		if LevelGenerator._dist(cell, player) < 6.0:
			far_enough = false
	_ok("怪物全部在地面格", on_ground)
	_ok("怪物距出生 ≥ 6 格", far_enough)


# =============================================================================
# E. 精英与 BOSS
# =============================================================================

func _test_elite_boss() -> void:
	print("--- E. 精英与 BOSS ---")
	var lv: LevelData = ConfigLoader.get_level("ch2_l10")
	var layout := LevelGenerator.generate(lv, _rng)
	_ok("精英锚点数 = 定义（ch2_l10 = 4）", layout["elite_spawns"].size() == 4)
	_ok("无 BOSS 关无 BOSS 锚点", layout["boss_spawn"] == Vector2i(-1, -1))
	var boss_lv: LevelData = ConfigLoader.get_level("ch2_l13")
	var b_layout := LevelGenerator.generate(boss_lv, _rng)
	_ok("BOSS 关有远端锚点", b_layout["boss_spawn"] != Vector2i(-1, -1))
	_ok("BOSS 锚点在地面", int(b_layout["cells"][b_layout["boss_spawn"]]) == LevelGenerator.TILE_GROUND)
	_ok("BOSS 锚点远离出生", LevelGenerator._dist(b_layout["boss_spawn"], b_layout["player_spawn"]) >= 6.0)
	# ⚠️ 原断言写死「BOSS 关 = 2（ch2_l13 / ch3_l20）」，是用**观测到的数据**反推期望值 ——
	#    于是把「ch1_l06 目标是 kill_boss 却缺 boss_id」这个缺陷**断言成了正确行为**，
	#    数据缺陷因此一直绿灯。改为按**设计意图**判定：目标是 kill_boss 的关必须有 boss_id。
	var boss_objective: Array[String] = []
	var missing_boss_id: Array[String] = []
	for lv2 in ConfigLoader.get_levels_sorted():
		if lv2.objective_type == LevelData.ObjectiveType.KILL_BOSS:
			boss_objective.append(lv2.id)
			if lv2.boss_id.is_empty():
				missing_boss_id.append(lv2.id)
	_ok("目标是 kill_boss 的关 = 3（ch1_l06 / ch2_l13 / ch3_l20）：%s" % str(boss_objective),
		boss_objective.size() == 3)
	_ok("每个 kill_boss 关都有 boss_id（缺：%s）" % str(missing_boss_id),
		missing_boss_id.is_empty())


# =============================================================================
# G. 目标可达性（「20 关全部可完成」）
# =============================================================================

## 每关的目标都必须**确定可完成**，而不是「大概率能完成」。
##
## 这条断言的价值大于修个别关的数据：它把「还有没有别的关也打不通」一次性永久关掉。
## 触发本次加固的真实缺陷（2026-09-18）：
##   - ch1_l03 目标 kill_elite×2，但整章缺 `elite_count` ⇒ 精英只靠 `elite_ratio` 随机提升
##     （5% × 约 60 怪 ⇒ 期望 3 个，但 P(不足 2) ≈ 19%），是**概率可完成**而非确定可完成
##   - ch1_l06 目标 kill_boss，但缺 `boss_id` ⇒ 生成器返回 boss_spawn=(-1,-1)，锚点丢失
##   - ch1_l04 目标 collect，当时**整个目标类型都没实现**（退化为清空）
##
## 判定口径：**只看数据与生成器输出**，不实例化场景 ——
## 这样 20 关可以秒级跑完，且失败信息直接指向「哪一关的哪个字段」。
func _test_objective_reachable() -> void:
	print("--- G. 目标可达性（20 关全部可完成）---")
	var implemented := [
		LevelData.ObjectiveType.CLEAR_ALL,
		LevelData.ObjectiveType.KILL_ELITE,
		LevelData.ObjectiveType.KILL_BOSS,
		LevelData.ObjectiveType.COLLECT,
	]
	var bad_type: Array[String] = []
	var elite_short: Array[String] = []
	var boss_broken: Array[String] = []
	var collect_bad: Array[String] = []
	var layout_broken: Array[String] = []
	var boss_unspawnable: Array[String] = []

	for lv in ConfigLoader.get_levels_sorted():
		var tag := "%s(%s)" % [lv.id, lv.get_objective_name()]
		# ① 目标类型必须已实现（未实现的会退化成「清空全部」，属于玩不到设计意图）
		if not implemented.has(lv.objective_type):
			bad_type.append(tag)

		# ② 生成器输出（固定种子，保证可复现）
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260918
		var layout := LevelGenerator.generate(lv, rng)
		if layout["player_spawn"] == Vector2i(-1, -1) \
				or (layout["monster_spawns"] as Array).is_empty():
			layout_broken.append(tag)

		match lv.objective_type:
			LevelData.ObjectiveType.KILL_ELITE:
				# 精英锚点是**确定性**来源（`elite_count` 个，摆在远离出生的地面格）。
				# 只有随机提升（`elite_ratio`）不够 —— 那会让目标变成概率可完成。
				if lv.elite_count < lv.objective_value:
					elite_short.append("%s 需%d/锚点%d" % [lv.id, lv.objective_value, lv.elite_count])
				if (layout["elite_spawns"] as Array).size() < lv.objective_value:
					elite_short.append("%s 生成器只给%d个锚点" % [lv.id, (layout["elite_spawns"] as Array).size()])
			LevelData.ObjectiveType.KILL_BOSS:
				# 契约（2026-09-18 定）：`boss_id` 是**权威**来源 —— `LevelScene` 据此在
				# `LevelGenerator.boss_spawn`（地图远端锚点，即「BOSS 房」）刷 BOSS。
				# `monster_entries[].is_boss` 降级为**兼容**来源，可不再写。
				# （修复前只认 is_boss 条目 ⇒ ch2_l13 / ch3_l20 的 BOSS 永不出现。）
				if lv.boss_id.is_empty():
					boss_broken.append("%s 缺 boss_id" % lv.id)
				elif ConfigLoader.get_monster(lv.boss_id) == null:
					boss_broken.append("%s boss_id=%s 不在怪物表里" % [lv.id, lv.boss_id])
				elif layout["boss_spawn"] == Vector2i(-1, -1):
					boss_broken.append("%s boss_id=%s 但锚点仍是 (-1,-1)" % [lv.id, lv.boss_id])
				# 兜底路径：锚点无效时 `LevelScene` 只能靠条目归类刷 BOSS，
				# 所以「锚点无效 **且** boss_id 不在 monster_entries 里」= BOSS 一定刷不出来。
				var in_entries := false
				for e in lv.monster_entries:
					if str(e.get("monster_id", "")) == lv.boss_id:
						in_entries = true
						break
				if not in_entries and layout["boss_spawn"] == Vector2i(-1, -1):
					boss_unspawnable.append("%s boss_id 既不在 monster_entries、锚点也无效" % lv.id)
			LevelData.ObjectiveType.COLLECT:
				# 收集物由 `LevelScene._spawn_collectibles()` 摆在 `pickup_spawns` 上
				# （不够时从地面格补位），所以只要目标数 ≥1 且生成器给了至少一个拾取点即可。
				if lv.objective_value < 1:
					collect_bad.append("%s objective_value=%d" % [lv.id, lv.objective_value])
				if (layout["pickup_spawns"] as Array).is_empty():
					collect_bad.append("%s 生成器没给 pickup_spawns" % lv.id)

	_ok("20 关目标类型全部已实现（未实现：%s）" % str(bad_type), bad_type.is_empty())
	_ok("每关都能生成出生点与怪物（异常：%s）" % str(layout_broken), layout_broken.is_empty())
	_ok("kill_elite 关的精英锚点 ≥ 目标数（不足：%s）" % str(elite_short), elite_short.is_empty())
	_ok("kill_boss 关的 BOSS 锚点可用（异常：%s）" % str(boss_broken), boss_broken.is_empty())
	_ok("kill_boss 关的 BOSS 一定能刷出来（异常：%s）" % str(boss_unspawnable), boss_unspawnable.is_empty())
	_ok("collect 关的目标数与拾取点可用（异常：%s）" % str(collect_bad), collect_bad.is_empty())


# =============================================================================
# F. 确定性
# =============================================================================

func _test_determinism() -> void:
	print("--- F. 确定性 ---")
	# ⚠️ 必须挑**程序化**关卡来测：手绘关（`layout.cells`）按设计**忽略种子**
	#    （H 段已单独断言「手绘布局不依赖种子」），拿它测「不同种子布局不同」
	#    必然**假红** —— 2026-09-21 `map-author` 把 `ch1_l06` 手绘化后本段就这样红过。
	#    所以**动态挑**第一个程序化关，不写死 id：随手绘化推进，写死的 id 会再次失效。
	var lv: LevelData = null
	for cand in ConfigLoader.get_levels_sorted():
		if not (cand.layout is Dictionary and cand.layout.has("cells")):
			lv = cand
			break
	_ok("存在程序化关卡可用于确定性校验（当前 20 关中手绘 %d 关）"
		% _authored_count(), lv != null)
	if lv == null:
		return
	var r1 := RandomNumberGenerator.new()
	r1.seed = 777
	var a := LevelGenerator.generate(lv, r1)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 777
	var b := LevelGenerator.generate(lv, r2)
	_ok("同种子布局一致（%s）" % lv.id, _same_layout(a, b))
	var r3 := RandomNumberGenerator.new()
	r3.seed = 778
	var c := LevelGenerator.generate(lv, r3)
	_ok("不同种子布局不同（%s）" % lv.id, not _same_layout(a, c))


## 当前手绘关（`layout.cells`）的数量。仅用于把 F 段的候选集现状打进日志。
func _authored_count() -> int:
	var n := 0
	for cand in ConfigLoader.get_levels_sorted():
		if cand.layout is Dictionary and cand.layout.has("cells"):
			n += 1
	return n


func _same_layout(a: Dictionary, b: Dictionary) -> bool:
	if a["player_spawn"] != b["player_spawn"]:
		return false
	if a["cells"].size() != b["cells"].size():
		return false
	for k in a["cells"]:
		if not b["cells"].has(k) or int(b["cells"][k]) != int(a["cells"][k]):
			return false
	return true


## 本关 `monster_entries` 里**非 BOSS** 条目的数量。
##
## 为什么要排除 BOSS 条目：BOSS 由 `'B'` 锚点单独刷，`LevelScene` 会跳过
## `monster_spawns` 里 `monster_id == boss_id` 的那条 ⇒ 若把它算进发牌池，
## 那个 `'m'` 会被**静默丢弃**（用户数着 48 个 `'m'` 却只出现 47 只怪，
## 且没有任何报错）。所以「发到怪」的期望值必须按非 BOSS 条目数算。
func _non_boss_entry_count(lv: LevelData) -> int:
	var n := 0
	for e in lv.monster_entries:
		if str(e.get("monster_id", "")) != lv.boss_id:
			n += 1
	return n


# =============================================================================
# H. 手绘地图（`layout.cells`）
# =============================================================================

## 该关 monster_entries 里**非 BOSS** 的条目数（BOSS 条目不进 'm' 发牌池）
## （实现见文件上方的 `_non_boss_entry_count` —— 此处不再重复声明）


## 手绘地图是「用户自己换场地」的入口（需求原文：「我可以自己換場地地圖任務特效等」）。
##
## 本段不是「验一张图长对了」，而是守三件事：
##
## ① **机制被真正走到**。本项目已 10 次踩「代码写了但没人消费 / 分支走不到」。
##    所以断言 `authored_hits` 计数 +1，而不是只断言「输出里有 cells 键」——
##    程序化路径**也**输出 cells，光比对数据分不出走的是哪条分支。
##
## ② **逐格等于手绘**。用户画什么就该得到什么：手绘地图的尺寸、地面/墙/障碍
##    计数、四类锚点数全部按手绘图逐项核对（期望表里的关卡**全量**核对）。期望值是
##    **从手绘图数出来的**，不是「跑一遍看到是 N」。
##
## ③ **连通性**。手绘最典型的坑不是「贴脸怪」而是「打不通」：随手画一个封闭小隔间、
##    往里塞两只怪，`clear_all` 就永远过不去，玩家硬卡死且没有任何提示
##    （与 ch1_l03 软锁同类）。判定口径见 `LevelGenerator.AUTHORED_BLOCKING`。
##    ⚠️ 另有一条 canary **钉住物理现实本身**：`TileCollision` 真的建出来了、
##    层契约 layer=1/mask=0、且「碰撞体覆盖格集合 == 挡人格集合」逐格等价。
##    （canary 的**方向**已随物理现实翻转：2026-09-21 之前是「钉住墙今天不挡人」，
##     `TileCollision` 落地后翻成「要求碰撞体必须存在」—— 见本段末尾的 canary 注释。）
##
## ④ **非法图会被拒**。校验必须响亮（返回 `player_spawn = (-1,-1)`），
##    否则用户画错一格就得到一张**静默打不通**的图。
func _test_authored() -> void:
	print("--- H. 手绘地图（layout.cells）---")
	var lv: LevelData = ConfigLoader.get_level("ch1_l02")
	_ok("ch1_l02 声明了手绘地图（layout 带 cells）",
		lv.layout is Dictionary and lv.layout.has("cells"))

	# ---- ① 机制被走到 --------------------------------------------------------
	var before := LevelGenerator.authored_hits
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var layout := LevelGenerator.generate(lv, rng)
	# 立刻留一份副本：`last_authored_errors` 是「最近一次 generate」的静态结果，
	# 后面还会跑别的关卡把它覆盖掉。这份副本用来在下面判定 ch1_l02 是否可用。
	var l02_errors: Array = LevelGenerator.last_authored_errors.duplicate()
	_ok("手绘分支**确实被执行**（authored_hits %d → %d）"
		% [before, LevelGenerator.authored_hits],
		LevelGenerator.authored_hits == before + 1)
	_ok("生成器自报来源 = 手绘（is_authored）", LevelGenerator.is_authored(layout))
	_ok("手绘解析零校验错误（%s）" % str(LevelGenerator.last_authored_errors),
		LevelGenerator.last_authored_errors.is_empty())
	var proc_lv: LevelData = null
	for cand in ConfigLoader.get_levels_sorted():
		if not (cand.layout is Dictionary and cand.layout.has("cells")):
			proc_lv = cand
			break
	_ok("存在程序化关卡可用于「无来源戳」校验", proc_lv != null)
	if proc_lv != null:
		var proc := LevelGenerator.generate(proc_lv, RandomNumberGenerator.new())
		_ok("程序化布局不带手绘来源戳（%s；%d 关仍走程序化，行为与改动前一致）"
			% [proc_lv.id, ConfigLoader.get_levels_sorted().size() - _authored_count()],
			not LevelGenerator.is_authored(proc))

	# ---- ② 逐格等于手绘（三关一起核对）---------------------------------------
	# 期望值**从手绘图数出来**，不是跑一遍观测的。
	# ⚠️ ch1_l01 的 ground/wall 是 **705/483**（不是初版的 704/484）：2026-09-21 把 (19,24)
	#    从 `#` 改成 `.` —— 原先精英 'e' 所在的 (19,25) 是三面封死的**1 格壁龛**（唯一出口在东侧
	#    (20,25)），而敌人**没有寻路**（直线追 + 沿墙滑行）⇒ 玩家在它西/北/南时它两个轴的滑行
	#    分量同时为 0，**一动不动**（704 个玩家位里只有 23% 能追到）。打通 (19,24) 后该处变成
	#    普通 L 型转角，死端消失。**改图必须同 commit 改这张表**，否则下面这条断言会红。
	var expect := {
		"ch1_l01": {"w": 40, "h": 30, "ground": 705, "wall": 483, "obstacle": 12,
			"m": 23, "e": 2, "p": 3, "boss": false},
		"ch1_l02": {"w": 40, "h": 30, "ground": 626, "wall": 549, "obstacle": 25,
			"m": 48, "e": 2, "p": 3, "boss": false},
		"ch1_l05": {"w": 26, "h": 44, "ground": 769, "wall": 357, "obstacle": 18,
			"m": 41, "e": 3, "p": 3, "boss": false},
		"ch1_l06": {"w": 48, "h": 36, "ground": 960, "wall": 748, "obstacle": 20,
			"m": 32, "e": 4, "p": 3, "boss": true},
	}
	var stat_bad: Array[String] = []
	var stat_line: Array[String] = []
	var stat_pending: Array[String] = []
	for lid in expect:
		var ld: LevelData = ConfigLoader.get_level(lid)
		if ld == null:
			stat_bad.append("%s 不在关卡表里（期望表条目已过期）" % lid)
			continue
		# 期望表描述的是**目标状态**：条目对应的关卡若还没手绘化，就跳过并单独列出。
		# 这样「设计已定、实现未落」不会让测试报红；而该关一旦被手绘化，
		# 这条断言**自动**开始覆盖它，不需要回来改测试。
		if not (ld.layout is Dictionary and ld.layout.has("cells")):
			stat_pending.append(lid)
			continue
		var l := LevelGenerator.generate(ld, RandomNumberGenerator.new())
		var want: Dictionary = expect[lid]
		var got := LevelGenerator.counts(l)
		var ms_n := (l["monster_spawns"] as Array).size()
		var es_n := (l["elite_spawns"] as Array).size()
		var ps_n := (l["pickup_spawns"] as Array).size()
		# 显式标注类型：`l["boss_spawn"]` 是 Variant，`Variant != Vector2i` 无法推断
		# （GDScript 的 `:=` 要求右侧有确定类型，否则解析期即报错）。
		var bs: bool = l["boss_spawn"] != Vector2i(-1, -1)
		stat_line.append("%s %d×%d 地%d/墙%d/障%d m%d e%d p%d%s"
			% [lid, l["width"], l["height"], got["ground"], got["wall"], got["obstacle"],
				ms_n, es_n, ps_n, " B" if bs else ""])
		if int(l["width"]) != int(want["w"]) or int(l["height"]) != int(want["h"]) \
				or got["ground"] != int(want["ground"]) or got["wall"] != int(want["wall"]) \
				or got["obstacle"] != int(want["obstacle"]) \
				or ms_n != int(want["m"]) or es_n != int(want["e"]) \
				or ps_n != int(want["p"]) or bs != bool(want["boss"]):
			stat_bad.append("%s 期望%s 实际%s" % [lid, str(want), str(got)])
	_ok("手绘逐格统计 = 手绘图（已覆盖 %d 关：%s｜待手绘 %s）"
		% [stat_line.size(), "; ".join(stat_line), str(stat_pending)],
		stat_bad.is_empty() and stat_line.size() >= 1)

	# ---- ②b 第一关「开局第一屏」的三条设计目标 --------------------------------
	# 这是**设计意图**断言，不是快照：`ch1_l01` 是玩家看到的第一屏，手绘它的目的就是
	# 「开局好看 + 走得通」。写进断言后，将来**重画 ch1_l01 时会自动被守住**，
	# 不用靠人肉再看一眼（本项目已多次踩「改完没人验」）。
	#
	# 三条线来自 team-lead 给的验收标准：
	#   ① 全图可走占比 ≥ 50%（别画成迷宫墙海）
	#   ② 出生点 3×3 邻域 9/9 可走（出生不贴墙 / 不卡在障碍里）
	#   ③ 出生点所在**取景框**内可走 ≥ 50%（开局第一屏不空旷、不满屏黑 void）
	# 取景框尺寸从 `project.godot` 的**真实视口**算（640×360 ÷ TILE_PX=32 ⇒ 20×11），
	# 不写死 20×11 —— 视口一改，这条断言跟着变，不会变成过期常量。
	var vw := int(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	var vh := int(ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	var win_w := maxi(1, vw / LevelScene.TILE_PX)
	var win_h := maxi(1, vh / LevelScene.TILE_PX)
	var l1: LevelData = ConfigLoader.get_level("ch1_l01")
	if l1 != null and l1.layout is Dictionary and l1.layout.has("cells"):
		var g1 := LevelGenerator.generate(l1, RandomNumberGenerator.new())
		var c1: Dictionary = g1["cells"]
		var w1 := int(g1["width"])
		var h1 := int(g1["height"])
		var walk1 := 0
		for k1 in c1:
			if LevelGenerator._is_walkable_kind(int(c1[k1])):
				walk1 += 1
		var ratio1 := 100.0 * float(walk1) / float(maxi(w1 * h1, 1))
		var s1: Vector2i = g1["player_spawn"]
		var near3 := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var p3: Vector2i = s1 + Vector2i(dx, dy)
				if c1.has(p3) and LevelGenerator._is_walkable_kind(int(c1[p3])):
					near3 += 1
		var wx0 := maxi(0, s1.x - win_w / 2)
		var wy0 := maxi(0, s1.y - win_h / 2)
		var wx1 := mini(w1, wx0 + win_w)
		var wy1 := mini(h1, wy0 + win_h)
		var win_walk := 0
		var win_tot := 0
		for wy in range(wy0, wy1):
			for wx in range(wx0, wx1):
				win_tot += 1
				if LevelGenerator._is_walkable_kind(
						int(c1.get(Vector2i(wx, wy), LevelGenerator.TILE_WALL))):
					win_walk += 1
		var ratio_win := 100.0 * float(win_walk) / float(maxi(win_tot, 1))
		_ok("ch1_l01 开局①：全图可走占比 %.1f%% ≥ 50%%（%d/%d 格）"
			% [ratio1, walk1, w1 * h1], ratio1 >= 50.0)
		_ok("ch1_l01 开局②：出生点 3×3 邻域 9/9 可走（实际 %d/9）" % near3, near3 == 9)
		_ok("ch1_l01 开局③：出生点 %d×%d 取景框可走 %.1f%% ≥ 50%%（%d/%d 格；视口 %d×%d px）"
			% [win_w, win_h, ratio_win, win_walk, win_tot, vw, vh], ratio_win >= 50.0)

	# ---- ③ ch1_l02 锚点逐项核对 ----------------------------------------------
	# ⚠️ 手绘数据可能是**中间态**（`map-author` 正在画这一关）。生成器遇到非法手绘图会
	#    「放弃生成」：`last_authored_errors` 非空、`player_spawn` 回落 (-1,-1)、`cells` 为空。
	#    此时 `layout["cells"][spawn]` 会直接抛
	#    `Invalid access to property or key '(-1,-1)'` —— 把「手绘数据非法」伪装成
	#    「verify 脚本崩了」，**而且后面整段（连通性 + canary）都不再执行**，静默少检。
	#    所以：① 给根因一个**名字**（下面这条断言）；② 所有取值走 `.get(..., -1)` 兜底。
	var l02_ok: bool = not (layout["cells"] as Dictionary).is_empty() \
		and (layout["player_spawn"] as Vector2i) != Vector2i(-1, -1)
	_ok("ch1_l02 手绘数据合法、生成器未放弃生成（非法项：%s）" % str(l02_errors), l02_ok)

	var spawn: Vector2i = layout["player_spawn"]
	_ok("玩家出生 = 手绘 '@' 所在格 (6,5)", spawn == Vector2i(6, 5))
	# 用 `.get(..., -1)` 而不是 `[...]`：数据非法时这里必须是**报红**，不是**崩溃**
	_ok("出生点是可走地面（不变式与程序化路径一致）",
		int((layout["cells"] as Dictionary).get(spawn, -1)) == LevelGenerator.TILE_GROUND)

	var elites: Array = layout["elite_spawns"]
	_ok("精英锚点 = 手绘 'e' 的 2 个位置（(35,5)/(3,25)）",
		elites.size() == 2 and elites.has(Vector2i(35, 5)) and elites.has(Vector2i(3, 25)))
	_ok("精英锚点数 == 关卡 elite_count（%d）" % lv.elite_count,
		elites.size() == lv.elite_count)
	_ok("拾取锚点 = 手绘 'p' 的 3 个位置",
		(layout["pickup_spawns"] as Array).size() == 3)
	_ok("ch1_l02 无 boss_id ⇒ 无 BOSS 锚点（与 E 段同口径）",
		layout["boss_spawn"] == Vector2i(-1, -1))
	# BOSS 关：'B' 画在哪，BOSS 锚点就必须落在哪 —— 这是 `B` 标记**第一次**被真实数据用上。
	# ⚠️ ch1_l06 尚未手绘化（`layout.cells` 还没写），此处**显式跳过**而不是放宽断言：
	# 一旦它被手绘化，下面的断言自动生效；跳过时会打印 [SKIP] 点名，
	# 不让「静默不检查」伪装成通过（本项目第 5 条规律：测试会静默变少却仍然报绿）。
	var boss_lv: LevelData = ConfigLoader.get_level("ch1_l06")
	if boss_lv.layout is Dictionary and boss_lv.layout.has("cells"):
		var boss_layout := LevelGenerator.generate(boss_lv, RandomNumberGenerator.new())
		_ok("ch1_l06 的 BOSS 锚点 = 手绘 'B' 所在格 (24,5)",
			boss_layout["boss_spawn"] == Vector2i(24, 5))
		_ok("ch1_l06 的 BOSS 锚点在地面且远离出生（%.1f 格）"
			% LevelGenerator._dist(boss_layout["boss_spawn"], boss_layout["player_spawn"]),
			int((boss_layout["cells"] as Dictionary).get(boss_layout["boss_spawn"], -1))
				== LevelGenerator.TILE_GROUND \
			and LevelGenerator._dist(boss_layout["boss_spawn"], boss_layout["player_spawn"]) >= 6.0)
	else:
		print("[SKIP] ch1_l06 尚未手绘化 ⇒ 'B' 标记仍无真实数据在用（待补）")

	var ms: Array = layout["monster_spawns"]
	_ok("杂兵锚点 = 手绘 'm' 的 48 个位置", ms.size() == 48)
	var on_ground := true
	var far_enough := true
	var ids_known := true
	var per_id := {}
	for m in ms:
		var cell: Vector2i = m["cell"]
		if int((layout["cells"] as Dictionary).get(cell, -1)) != LevelGenerator.TILE_GROUND:
			on_ground = false
		if LevelGenerator._dist(cell, spawn) < 6.0:
			far_enough = false
		var mid := str(m["monster_id"])
		per_id[mid] = int(per_id.get(mid, 0)) + 1
		var known := false
		for e in lv.monster_entries:
			if str(e.get("monster_id", "")) == mid:
				known = true
				break
		if not known:
			ids_known = false
	_ok("杂兵全部落在手绘地面格", on_ground)
	_ok("杂兵全部距出生 ≥ 6 格（手绘路径自己保证，不靠程序化那套采样）", far_enough)
	_ok("杂兵 id 全部来自本关 monster_entries（实际：%s）" % str(per_id), ids_known)
	# BOSS 条目**不进发牌池**：它由 'B' 锚点单独刷（`LevelScene` 会跳过
	# `monster_spawns` 里 monster_id == boss_id 的那条）⇒ 不排除的话，那个 'm'
	# 会被静默丢弃，用户数着 48 个 'm' 却只出现 47 只怪。
	_ok("每条**非 BOSS** 的 monster_entries 都发到了怪（%s）" % str(per_id),
		per_id.size() == _non_boss_entry_count(lv))
	_ok("BOSS 条目没有混进 monster_spawns（否则 LevelScene 会静默丢一只）",
		lv.boss_id.is_empty() or not per_id.has(lv.boss_id))
	# 设计意图（不是快照）：条目占比由 count_min 决定 ⇒ 投放占比应与之一致（容差 = 条目数）
	var min_total := 0.0
	for e in lv.monster_entries:
		if str(e.get("monster_id", "")) == lv.boss_id:
			continue
		min_total += float(e.get("count_min", 0))
	var skew_ok := true
	var skew_detail: Array[String] = []
	for e in lv.monster_entries:
		var mid := str(e.get("monster_id", ""))
		if mid == lv.boss_id:
			continue
		var want := float(ms.size()) * float(e.get("count_min", 0)) / min_total
		var got := float(per_id.get(mid, 0))
		if absf(got - want) > float(lv.monster_entries.size()):
			skew_ok = false
			skew_detail.append("%s 期望%.1f 实际%d" % [mid, want, int(got)])
	_ok("杂兵类型占比按 count_min 投放（容差 %d 只：%s）"
		% [lv.monster_entries.size(), str(skew_detail)], skew_ok)

	# ---- 手绘 = 确定性：不依赖种子 -------------------------------------------
	var r2 := RandomNumberGenerator.new()
	r2.seed = 999999
	var other := LevelGenerator.generate(lv, r2)
	_ok("手绘布局不依赖种子（逐格 + 四类锚点全部一致）",
		_same_layout(layout, other) \
		and str(other["monster_spawns"]) == str(layout["monster_spawns"]) \
		and str(other["elite_spawns"]) == str(layout["elite_spawns"]) \
		and str(other["pickup_spawns"]) == str(layout["pickup_spawns"]))

	# 手绘是**可选**入口，不是把全项目改成手绘
	var authored_ids: Array[String] = []
	for lv2 in ConfigLoader.get_levels_sorted():
		if lv2.layout is Dictionary and lv2.layout.has("cells"):
			authored_ids.append(lv2.id)
	# 设计意图：手绘是**可选**入口，不是把全项目改成手绘。
	# ⚠️ 这里断言的是**意图**（至少一关手绘、且仍有程序化关卡），不是把具体关卡 id 钉死。
	# 钉死 `== ["ch1_l02","ch1_l05","ch1_l06"]` 属于快照断言：将来多手绘一关就会报红，
	# 而它并没有违反任何设计意图 —— 那正是本项目第 ③ 条规律要避免的。
	var level_total := ConfigLoader.get_levels_sorted().size()
	print("[INFO] 手绘关卡清单（%d/%d）：%s" % [authored_ids.size(), level_total, str(authored_ids)])
	_ok("手绘是可选入口：至少 1 关走手绘，且仍有程序化关卡（实际 %d/%d 关手绘）"
		% [authored_ids.size(), level_total],
		authored_ids.size() >= 1 and authored_ids.size() < level_total)

	# README 8.3.1 里那份「复制就能跑」的示例必须**真的能跑**（防文档腐烂：
	# 手绘格式的字符表 / 校验规则一旦调整，文档里的例子是最先失效的东西）
	var doc_lv := LevelData.new()
	doc_lv.id = "readme_example"
	doc_lv.elite_count = 2
	doc_lv.monster_entries = [
		{"monster_id": "spider_cave", "count_min": 20, "count_max": 30, "weight": 100.0},
		{"monster_id": "bat_swarm", "count_min": 10, "count_max": 16, "weight": 60.0},
		{"monster_id": "skeleton_warrior", "count_min": 6, "count_max": 10, "weight": 40.0},
	]
	doc_lv.layout = {"cells": [
		"#############",
		"#@.........##",
		"#.....##....#",
		"#.....##..e.#",
		"#...........#",
		"#.p........m#",
		"#....mm.....#",
		"#..o....oe..#",
		"#############",
	]}
	var doc := LevelGenerator.generate(doc_lv, RandomNumberGenerator.new())
	_ok("README 8.3.1 的示例地图可直接跑（出生 (1,1)；错误 %s）"
		% str(LevelGenerator.last_authored_errors),
		doc["player_spawn"] == Vector2i(1, 1) \
		and LevelGenerator.last_authored_errors.is_empty())

	# ---- 连通性（可达性）：手绘地图最典型的坑 ---------------------------------
	# 程序化路径天然连通（先造房间再挖走廊）；**手绘会**画出一个进不去的房间、
	# 或把怪关在墙里 —— 那在 clear_all / kill_boss 下就是 ch1_l03 那类
	# 「目标不可达 ⇒ 玩家硬卡死且无任何提示」。判定口径见
	# `LevelGenerator.AUTHORED_BLOCKING`（按**设计意图**：墙 / 障碍阻挡，4 连通）。
	var conn_detail: Array[String] = []
	var conn_ok := true
	for lv3 in ConfigLoader.get_levels_sorted():
		if not (lv3.layout is Dictionary and lv3.layout.has("cells")):
			continue
		var l3 := LevelGenerator.generate(lv3, RandomNumberGenerator.new())
		var c3: Dictionary = l3["cells"]
		var r3 := LevelGenerator._reachable_from(
			c3, int(l3["width"]), int(l3["height"]), l3["player_spawn"])
		var walk3 := 0
		for k in c3:
			if LevelGenerator._is_walkable_kind(int(c3[k])):
				walk3 += 1
		var anchors_ok := true
		for a in (l3["monster_spawns"] as Array):
			if not r3.has(a["cell"]):
				anchors_ok = false
		for key in ["elite_spawns", "pickup_spawns"]:
			for a in (l3[key] as Array):
				if not r3.has(a):
					anchors_ok = false
		if l3["boss_spawn"] != Vector2i(-1, -1) and not r3.has(l3["boss_spawn"]):
			anchors_ok = false
		conn_detail.append("%s 可达%d/可行走%d%s"
			% [lv3.id, r3.size(), walk3, "" if anchors_ok else " ✗锚点"])
		if r3.size() != walk3 or not anchors_ok:
			conn_ok = false
	_ok("连通性：手绘关卡可行走格 100%% 从 '@' 可达且四类锚点可达（%s）"
		% ", ".join(conn_detail), conn_ok and conn_detail.size() >= 1)

	# ---- canary：钉住「墙 / 障碍**真的**挡人」这个物理现实 ----------------------
	# ⚠️ 旧版本是**假阴性**，务必别退回去：它只 `instantiate()` 关卡场景就断言
	#    「一个物理体都没有」，而 `instantiate()` **不触发 `_ready()`** ⇒
	#    `_build_collision()` 永不执行 ⇒ 当然没有物理体 ⇒ **断言照样全绿**。
	#    于是这条 canary 从「盯着物理现实」退化成「复述自己造的空场景」，
	#    而 `AUTHORED_BLOCKING` 的说明一直写着「今天墙体实际不挡人」—— 那句话早就是假话。
	#
	# 现在走**真路径**：挂进树 → `on_scene_entered()` → `_build()` → `_build_collision()`，
	# 再遍历**运行时真的建出来的**碰撞体。冻结敌人 AI（照 `capture_ui_page.gd`），
	# 免得测试期间怪物乱跑 / 互殴引入噪声。
	var lvl := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(lvl)
	await get_tree().process_frame
	await get_tree().process_frame
	_canary_level_id = _pick_canary_level()
	_ok("canary：挑到了可用的基准关卡（%s）" % _canary_level_id,
		not _canary_level_id.is_empty())
	if not _canary_level_id.is_empty():
		lvl.on_scene_entered({
			"level_id": _canary_level_id,
			"difficulty_tier": GameConstants.DifficultyTier.NM1,
		})
	await get_tree().process_frame
	_freeze_enemies(lvl)

	var body := lvl.get_node_or_null("TileCollision") as StaticBody2D
	_ok("canary：关卡运行时**真的**建出了地形碰撞体 TileCollision（不再靠 instantiate 复述空场景）",
		body != null)
	_ok("canary：TileCollision 层契约 layer=1 / mask=0（层 1 = world）",
		body != null and body.collision_layer == 1 and body.collision_mask == 0)

	# 逐格**集合比较**：碰撞体覆盖的格子集合必须**恰好等于**挡人格集合。
	# 只比数量是不够的 —— 合并写错时「多吞一排空格 + 少盖一排墙」数量可以一样。
	var cells: Dictionary = lvl._layout.get("cells", {})
	var want: Dictionary = {}
	for key in cells:
		if not key is Vector2i:
			continue
		var c: Vector2i = key
		var t: int = int(cells[c])
		if t == LevelGenerator.TILE_WALL or t == LevelGenerator.TILE_OBSTACLE:
			want[c] = true
	var got: Dictionary = {}
	var shape_count := 0
	if body != null:
		for ch in body.get_children():
			var cs := ch as CollisionShape2D
			if cs == null:
				continue
			var rs := cs.shape as RectangleShape2D
			if rs == null:
				continue
			shape_count += 1
			var tl: Vector2 = cs.position - rs.size / 2.0
			var x0 := int(round(tl.x / float(LevelScene.TILE_PX)))
			var y0 := int(round(tl.y / float(LevelScene.TILE_PX)))
			var nx := int(round(rs.size.x / float(LevelScene.TILE_PX)))
			var ny := int(round(rs.size.y / float(LevelScene.TILE_PX)))
			for dy in ny:
				for dx in nx:
					got[Vector2i(x0 + dx, y0 + dy)] = true
	var missing: Array[Vector2i] = []
	for c in want:
		if not got.has(c):
			missing.append(c)
	var extra: Array[Vector2i] = []
	for c in got:
		if not want.has(c):
			extra.append(c)
	# ⚠️ `want.size() > 0` 不能省：基准关挑空时 `want` / `got` 都是空字典，
	#    「缺 0 / 多 0」会**假绿** —— 那正是旧版 canary 犯过的错（复述空场景还报通过）。
	_ok("canary：碰撞体覆盖格集合 == 挡人格集合（%d 格，逐格枚举比较；缺 %d / 多 %d）"
		% [want.size(), missing.size(), extra.size()],
		want.size() > 0 and missing.is_empty() and extra.is_empty())
	for c in missing:
		print("       缺：%s" % str(c))
	for c in extra:
		print("       多：%s" % str(c))

	# 地面格必须**没有**被覆盖（合并不能扩边吞掉空格）
	var ground_covered := 0
	for key2 in cells:
		if key2 is Vector2i and int(cells[key2]) == LevelGenerator.TILE_GROUND \
				and got.has(key2):
			ground_covered += 1
	_ok("canary：地面格无一被碰撞体覆盖（%d 个）" % ground_covered, ground_covered == 0)

	# 形状合并收益：同时把「逐格」这个旧基线钉进日志，便于前后对比
	var per_cell := want.size()
	_ok("canary：形状已合并（%s 逐格 %d → 实际 %d，降 %.0f%%）"
		% [_canary_level_id, per_cell, shape_count,
			100.0 * (1.0 - float(shape_count) / float(maxi(per_cell, 1)))],
		shape_count > 0 and shape_count < per_cell)

	await get_tree().process_frame
	if lvl.get_parent() != null:
		lvl.queue_free()
	await get_tree().process_frame

	var player_probe := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_ok("canary：玩家 collision_mask 仍打 world 层（1）⇒ 「墙阻挡」有代码为证，不是我编的规则",
		int((player_probe as CollisionObject2D).collision_mask) == 1)
	player_probe.free()


	# ---- ③ 非法图必须被拒（响亮）--------------------------------------------
	# ⚠️ 以下 6 例会**故意**打出 ERROR 行 —— 那是被校验拦下的证明，不是本脚本失败。
	#    前 4 例在 `cases` 里；第 5 例是 legend 篡改；第 6 例是「怪被墙围死」（见下方）。
	print("   （以下 ERROR 行属**预期**：本段故意喂 6 张非法手绘图）")
	var cases := {
		"缺玩家出生 '@'": ["####", "#mm#", "####"],
		"杂兵贴脸（距出生 < 6 格）": ["#######", "#@mm..#", "#######"],
		"出现未定义字符 'X'": ["#####", "#@X.#", "#####"],
		"四边未封墙（底部有缺口）": ["#####", "#@.m#", "#...#"],
	}
	for label in cases:
		var bad := LevelData.new()
		bad.id = "test_bad_map"
		bad.layout = {"cells": cases[label]}
		var b_layout := LevelGenerator.generate(bad, RandomNumberGenerator.new())
		_ok("非法手绘图被拒：%s（报 %d 处错）"
			% [label, LevelGenerator.last_authored_errors.size()],
			b_layout["player_spawn"] == Vector2i(-1, -1) \
			and (b_layout["monster_spawns"] as Array).is_empty() \
			and not LevelGenerator.last_authored_errors.is_empty())

	# `legend` 不能把标记字符改成非地面 —— 否则怪物会站在墙里 / 出生点落进墙里
	var bad_legend := LevelData.new()
	bad_legend.id = "test_bad_legend"
	bad_legend.layout = {"cells": ["#####", "#@.m#", "#####"], "legend": {"@": "wall"}}
	var b5 := LevelGenerator.generate(bad_legend, RandomNumberGenerator.new())
	var legend_caught := false
	for e in LevelGenerator.last_authored_errors:
		if e.contains("legend"):
			legend_caught = true
	_ok("非法手绘图被拒：legend 把 '@' 改成墙（%s）" % str(LevelGenerator.last_authored_errors),
		b5["player_spawn"] == Vector2i(-1, -1) and legend_caught)

	# ⭐ 第 6 例（最重要的一例）：四边封墙、'@' 恰好 1 个、怪距出生也够远 ——
	#    唯一的问题是「怪被墙围死」。前 5 例一条都挡不住它。
	#    这正是手绘地图最典型的坑：随手画一个封闭小隔间，里面塞两只怪，
	#    clear_all 就永远打不通，玩家硬卡死且没有任何提示。
	var bad_sealed := LevelData.new()
	bad_sealed.id = "test_sealed_monster"
	bad_sealed.layout = {"cells": [
		"###################",
		"#@................#",
		"#.................#",
		"#.........####....#",
		"#.........#mm#....#",
		"#.........####....#",
		"#.p...............#",
		"###################",
	]}
	var b6 := LevelGenerator.generate(bad_sealed, RandomNumberGenerator.new())
	var conn_caught := false
	for e in LevelGenerator.last_authored_errors:
		if e.contains("走不到") or e.contains("孤立"):
			conn_caught = true
	_ok("非法手绘图被拒：怪被墙围死（其余条件全合法）（%s）"
		% str(LevelGenerator.last_authored_errors),
		b6["player_spawn"] == Vector2i(-1, -1) and conn_caught)


## 冻结关卡里全部敌人的 AI（照 `capture_ui_page.gd:_freeze_enemies`）：
## canary 只需要静态地形，怪物乱跑 / 互殴只会引入噪声。
func _freeze_enemies(level: LevelScene) -> void:
	for e in level._alive:
		if is_instance_valid(e):
			e.set_physics_process(false)
			e.set_process(false)


## 挑 canary 的基准关卡：第一个**生成成功且挡人格 > 0** 的关卡，优先程序化关。
##
## 为什么动态挑而不是写死 id：手绘关卡正被 `map-author` 反复重画（`ch1_l01` → `ch1_l02`
## → …），写死任何一关，别人的编辑都会让本脚本假红。程序化关不受手绘编辑影响。
## 挑不到 ⇒ 返回空串，调用方**响亮报红**，绝不静默跳过。
func _pick_canary_level() -> String:
	var fallback := ""
	for lv in ConfigLoader.get_levels_sorted():
		var authored: bool = lv.layout is Dictionary and lv.layout.has("cells")
		var l := LevelGenerator.generate(lv, RandomNumberGenerator.new())
		# ⚠️ `last_authored_errors` 只在手绘分支被写；程序化分支不会清它，
		#    所以只能对**手绘关**读这个值，否则会误判。
		if authored and not LevelGenerator.last_authored_errors.is_empty():
			continue
		var cells: Dictionary = l["cells"]
		var blocking := 0
		for k in cells:
			var t := int(cells[k])
			if t == LevelGenerator.TILE_WALL or t == LevelGenerator.TILE_OBSTACLE:
				blocking += 1
		if blocking == 0:
			continue
		if not authored:
			print("[INFO] canary 基准关卡 = %s（第一个生成成功、有挡人格的**程序化**关）" % lv.id)
			return lv.id
		if fallback.is_empty():
			fallback = lv.id
	if not fallback.is_empty():
		print("[INFO] canary 基准关卡 = %s（无可用程序化关，退用手绘关）" % fallback)
	return fallback


# =============================================================================
# I. 形状合并等价性（全部关卡）
# =============================================================================

## 形状合并的**等价性**：对**全部 20 关**逐格枚举点做集合比较。
##
## 为什么不止测一关：合并算法吃的是 `cells` 的**形状**。程序化关是「方块房间」，
## 手绘关是「任意手画墙线」—— 后者才是贪心合并的真正压力测试。只测一关，
## 等于只测了一种形状分布（而且恰好是最好合并的那种）。
##
## 为什么不用场景实例：`_merge_blocking_rects()` 是**纯函数**（只读 `cells` 入参），
## 所以 `LevelScene.new()` 就能直接调，不必建 20 个关卡场景（那会很慢，
## 每个场景还要刷怪 + 建 HUD）。
##
## 输出同时充当**报告数字**：每关「逐格 → 合并」的形状数，含 `ch1_l01` / `ch1_l02`。
func _test_merge_equivalence() -> void:
	print("--- I. 形状合并等价性（全部关卡逐格集合比较）---")
	var probe := LevelScene.new()
	# 固定种子：程序化关的形状数会随种子浮动（实测 ch1_l03 在 757–776 之间），
	# 不固定的话「合计 N → M」这行日志每次都变，前后对比就没意义了。
	# ⚠️ 等价性断言本身与种子无关（自洽比较），固定种子只为让**报告数字**可复现。
	var mrng := RandomNumberGenerator.new()
	mrng.seed = 20260918
	var bad: Array[String] = []
	var lines: Array[String] = []
	var total_before := 0
	var total_after := 0
	var authored_lines: Array[String] = []
	for lv in ConfigLoader.get_levels_sorted():
		var l := LevelGenerator.generate(lv, mrng)
		var cells: Dictionary = l["cells"]
		# 逐格枚举点：期望集合 = 挡人格（墙 / 障碍）的**并集**
		var want: Dictionary = {}
		for key in cells:
			if not key is Vector2i:
				continue
			var t := int(cells[key])
			if t == LevelGenerator.TILE_WALL or t == LevelGenerator.TILE_OBSTACLE:
				want[key] = true
		# 实际集合 = 合并后的矩形**展开回格子**
		var rects := probe._merge_blocking_rects(cells)
		var got: Dictionary = {}
		for r in rects:
			for dy in r.size.y:
				for dx in r.size.x:
					got[Vector2i(r.position.x + dx, r.position.y + dy)] = true
		var missing := 0
		for c in want:
			if not got.has(c):
				missing += 1
		var extra := 0
		for c in got:
			if not want.has(c):
				extra += 1
		total_before += want.size()
		total_after += rects.size()
		var line := "%s %d→%d" % [lv.id, want.size(), rects.size()]
		lines.append(line)
		if lv.layout is Dictionary and lv.layout.has("cells"):
			authored_lines.append(line)
		# `want.size() == 0` 也算异常：空关会让「缺 0 / 多 0」变成**假绿**
		if missing != 0 or extra != 0 or want.size() == 0:
			bad.append("%s 缺%d/多%d/挡人格%d" % [lv.id, missing, extra, want.size()])
	probe.free()

	_ok("合并等价：20 关逐格集合 == 合并后展开集合（异常 %d 关：%s）"
		% [bad.size(), str(bad)], bad.is_empty())
	_ok("合并收益：合计 %d → %d 个形状（降 %.0f%%）"
		% [total_before, total_after,
			100.0 * (1.0 - float(total_after) / float(maxi(total_before, 1)))],
		total_before > 0 and total_after > 0 and total_after < total_before)
	print("       手绘关：%s" % ", ".join(authored_lines))
	for s in lines:
		print("       %s" % s)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
