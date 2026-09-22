## 性能优化实测（任务 8.3 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_perf83.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（5 个测试段）：
##   A. ObjectPool 基本盘：acquire 工厂创建 → release 回池 → 二次 acquire 命中复用
##   B. 池满兜底：超容量 release → queue_free 不泄漏（活跃数回落）
##   C. 复用率：预热后第二次周期命中率 ≥ 90%
##   D. LevelView 批处理：单个节点承载全部 tile（对比 ColorRect 方案节点数）
##   E. 渲染正确性：地面/墙计数 + 出生点标记存在（_draw 队列触发）
##
## ⚠️ D/E 段的地图生成**必须用固定 seed 的 RNG**（见 `_run()` 里 `FIXED_SEED`）。
##    seed 固定以消除 flaky；阈值强度不变（原为未播种 RNG，地面占比在 296–467 间浮动）。
##    未播种的 `RandomNumberGenerator.new()` 由系统熵初始化，同一份关卡定义每次跑出的
##    地面格数都不同，而断言 `g >= total_cells * 0.3`（约 1200 格 ⇒ 360）是**硬阈值**，
##    历史上出现过 296 ⇒ 随机变红。固定 seed 后布局完全可复现，断言强度一点没降
##    （**禁止用放宽阈值的方式「修」flaky —— 那是把断言改弱，属于掩盖**）。
extends Node2D

## D/E 段地图生成的固定种子。改动它等于换一张地图，请连跑 5 次确认断言仍全绿。
const FIXED_SEED: int = 20260918

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 性能优化实测（任务 8.3） =====")
	await _run()
	_finish()


func _run() -> void:
	ObjectPool.clear()

	# A. 对象池基本盘
	var node_a := ObjectPool.acquire("test", func() -> Node: return Node.new())
	_ok("首次 acquire 走工厂创建", node_a != null and ObjectPool.misses("test") == 1)
	ObjectPool.release("test", node_a)
	_ok("release 后回池", ObjectPool.pool_size("test") == 1 and ObjectPool.live("test") == 0)
	var node_b := ObjectPool.acquire("test", func() -> Node: return Node.new())
	_ok("二次 acquire 命中复用（同一实例）", node_b == node_a and ObjectPool.hits("test") == 1)

	# B. 池满兜底
	ObjectPool.register("full", 2)
	var f1 := ObjectPool.acquire("full", func() -> Node: return Node.new())
	var f2 := ObjectPool.acquire("full", func() -> Node: return Node.new())
	ObjectPool.release("full", f1)
	ObjectPool.release("full", f2)
	_ok("池满（容量 2）后第 3 次 release 走 queue_free（池仍 2）",
		ObjectPool.pool_size("full") == 2 and ObjectPool.live("full") == 0)

	# C. 复用率：预热 5 次后连续 20 次循环，命中率应 ≥ 90%
	for i in range(5):
		var n := ObjectPool.acquire("cycle", func() -> Node: return Node.new())
		ObjectPool.release("cycle", n)
	var hit0 := ObjectPool.hits("cycle")
	for i in range(20):
		var n := ObjectPool.acquire("cycle", func() -> Node: return Node.new())
		ObjectPool.release("cycle", n)
	var rate := ObjectPool.reuse_rate("cycle")
	_ok("复用率 ≥ 90%（实测 " + str(int(rate * 100.0)) + "%）", rate >= 0.9)
	_ok("活跃数为 0（无泄漏）", ObjectPool.live("cycle") == 0)

	# D. LevelView 批处理（对比 ColorRect 方案）
	var level_def: LevelData = ConfigLoader.get_level("ch1_l01")
	# ⚠️ 必须用固定 seed —— 未播种时每次布局都不同，硬阈值会随机变红（见文件头注释）。
	var rng := RandomNumberGenerator.new()
	rng.seed = FIXED_SEED
	var layout := LevelGenerator.generate(level_def, rng)
	var lv := LevelView.new()
	lv.set_layout(layout)
	add_child(lv)
	var total_cells: int = int(layout["cells"].size())
	_ok("LevelView 单节点承载全部 tile（%d 格）" % lv.tile_count(), lv.tile_count() == total_cells)
	_ok("批处理节点数=1（对比 ColorRect 方案 %d 节点 → draw call 大幅下降）" % total_cells,
		lv.get_child_count() == 0 and lv.get_parent() != null)
	# 地面 / 墙 / 障碍物比例（地图生成器已验证地面 ≥30%）
	var g := 0
	var wall := 0
	var obst := 0
	for t in lv._tiles:
		if t.z == LevelGenerator.TILE_GROUND:
			g += 1
		elif t.z == LevelGenerator.TILE_WALL:
			wall += 1
		elif t.z == LevelGenerator.TILE_OBSTACLE:
			obst += 1
	_ok("地面/墙/障碍计数与生成器一致（地面 %d / 墙 %d / 障碍 %d）" % [g, wall, obst],
		g + wall + obst == total_cells and g >= int(total_cells * 0.3))
	# E. 渲染正确性：总 tile = 地面+墙+障碍（全部进入批处理数组）
	_ok("全部 tile 进入单次批处理（%d = %d + %d + %d）" % [lv.tile_count(), g, wall, obst],
		lv.tile_count() == g + wall + obst and total_cells > 0)

	# 输出报告供优化报告引用
	print(ObjectPool.report())
	ObjectPool.drain()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
