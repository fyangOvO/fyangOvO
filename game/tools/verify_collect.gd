## 收集目标（`collect`）端到端实测（2026-09-18）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_collect.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 为什么单独一个脚本：
##   `verify_level_gen` 的 G 段只能证明**数据与生成器**健全（有 `pickup_spawns`、
##   目标数 ≥1），证明不了「收集物真的摆出来了、真的能捡、捡完真的会结算」；
##   而 `verify_e2e` 跑的是 `ch1_l01`（clear_all），走不到这条路。
##   本脚本补的正是这条缝：**数据对了 ≠ 玩法通了**（本项目已多次栽在这条上）。
##
## 覆盖：
##   A. 摆放：进关后恰好有 `objective_value` 个收集物，且都落在**地面格**上
##   B. 不过期：普通掉落 60s 后消失；收集物必须常驻（消失 = 目标**永久不可完成**）
##   C. 拾取：玩家走到收集物上 → 走**真实** `LootDrop._process` 距离判定 → 计数递增
##   D. 不污染经济：收集物是 material，**不进装备背包**（否则装备经济被目标物注水）
##   E. 结算：捡满目标数 → 目标达成 → 结算面板**真的渲染出来**（不是只改个标志位）
##   F. 广播：`level_completed` 载荷为 `{"result": RunResult}` 且与本次一致
##
## ⚠️ 测试期唯一改动：把玩家血量顶到极大，避免被怪围殴致死打断流程
##    （本测试不打怪，怪会一直攻击玩家；这与被验证的收集逻辑无关）。
extends Node

const LEVEL_ID: String = "ch1_l04"          ## 第一章唯一的 collect 关（目标收集 3 个）
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const MAX_WAIT_FRAMES: int = 600

var _fail: int = 0
var _level: LevelScene = null
var _player: PlayerController = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	_run()


func _run() -> void:
	print("===== 收集目标（collect）端到端实测 · %s =====" % LEVEL_ID)

	# --- 进关（复用真实入场契约 `on_scene_entered`）---
	_level = LEVEL_SCENE.instantiate() as LevelScene
	# ⚠️ 必须 call_deferred：`_ready()` 期间 root 正在 setup children，
	#    直接 add_child 会报 "Parent node is busy setting up children" 并**静默失败**
	#    （节点没进树 ⇒ @onready 全是 null ⇒ `_build()` 里 `_view.set_layout()` 对 Nil 调方法）。
	get_tree().root.add_child.call_deferred(_level)
	await _wait_frames(2)
	_level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _wait_frames(3)

	var def: LevelData = ConfigLoader.get_level(LEVEL_ID)
	_player = _level._player
	_ok("进关成功：玩家与关卡定义就绪", _player != null and def != null)
	if _player == null or def == null:
		_finish()
		return

	# 顶血：本测试不打怪，但怪会一直攻击玩家（见文件头说明）
	_player.health.max_hp_override = 1.0e9
	_player.health.current_hp = 1.0e9

	# --- A. 摆放 ---
	print("--- A. 收集物摆放 ---")
	var drops := _collectibles()
	_ok("收集物数量 = objective_value（%d）：实际 %d" % [def.objective_value, drops.size()],
		drops.size() == def.objective_value)
	_ok("目标数已读进 HUD（_objective_target = %d / 当前 %d）"
			% [_level._objective_target, _level._objective_current],
		_level._objective_target == def.objective_value and _level._objective_current == 0)

	var off_ground: Array[String] = []
	var cells: Dictionary = _level._layout.get("cells", {})
	for d in drops:
		var cell := Vector2i(int(d.global_position.x) / LevelScene.TILE_PX,
			int(d.global_position.y) / LevelScene.TILE_PX)
		if int(cells.get(cell, -1)) != LevelGenerator.TILE_GROUND:
			off_ground.append(str(cell))
	_ok("收集物全部落在地面格（异常：%s）" % str(off_ground), off_ground.is_empty())

	# --- B. 不过期 ---
	print("--- B. 不过期 ---")
	var expiring: Array[String] = []
	for d in drops:
		if d._lifetime != INF:
			expiring.append("%s lifetime=%s" % [d.name, str(d._lifetime)])
	_ok("收集物不过期（普通掉落 %ss 会消失，消失 = 目标永久不可完成；异常：%s）"
			% [str(GameConstants.LOOT_DROP_LIFETIME), str(expiring)],
		expiring.is_empty())

	# --- C / D. 逐个走过去捡 ---
	print("--- C. 拾取（走真实距离判定）---")
	var mats_before: int = _player.materials
	for i in drops.size():
		var alive := _collectibles()
		if alive.is_empty():
			break
		var target: LootDrop = alive[0]
		# 传送到收集物正上方：`LootDrop._process` 用真实距离判定，不绕过
		_player.global_position = target.global_position
		var before: int = _level._collected
		if not await _wait_until(func() -> bool: return _level._collected > before, 120):
			_ok("第 %d 个收集物被拾取" % (i + 1), false)
			break
		_ok("第 %d 个收集物被拾取（进度 %d / %d）"
				% [i + 1, _level._objective_current, _level._objective_target],
			_level._objective_current == i + 1)

	_ok("收集计数 = 目标数（%d / %d）" % [_level._collected, _level._objective_target],
		_level._collected == _level._objective_target)
	_ok("收集物已全部从场景移除（残留 %d）" % _collectibles().size(),
		_collectibles().is_empty())
	print("--- D. 不污染装备经济 ---")
	_ok("收集物是 material：装备背包仍为空（实际 %d 件）" % _player.inventory.size(),
		_player.inventory.is_empty())
	_ok("收集物计入材料（%d → %d）" % [mats_before, _player.materials],
		_player.materials == mats_before + def.objective_value)

	# --- E. 结算 ---
	print("--- E. 结算 ---")
	if not await _wait_until(func() -> bool: return _level._finished, MAX_WAIT_FRAMES):
		_ok("捡满目标数后触发结算（_finished）", false)
	else:
		_ok("捡满目标数后触发结算（_finished）", true)
		await _wait_frames(2)
		_ok("结算面板可见", _level._result_panel.visible)
		_ok("结算面板渲染出了按钮（返回大厅 / 再来一局）",
			_count_buttons(_level._result_panel) >= 2)
		# 结算前会补保底掉落（`guaranteed_equipment_drops`），所以背包应至少有 1 件装备
		_ok("保底装备已入包（%d 件 ≥ %d）"
				% [_player.inventory.size(), def.guaranteed_equipment_drops],
			_player.inventory.size() >= def.guaranteed_equipment_drops)

	# --- F. 广播 ---
	print("--- F. level_completed 广播 ---")
	var summary: Dictionary = SceneManager.last_run_summary
	var res: RunResult = summary.get("result", null)
	_ok("level_completed 载荷为单键 {\"result\": RunResult}（实际键：%s）" % str(summary.keys()),
		summary.keys().size() == 1 and res != null)
	# ⚠️ `RunResult` 里**没有** level_id 字段（关卡 id 只在信号的第一个参数上），
	#    所以这里改用「本次结算单的内容」交叉验证，而不是比对关卡 id。
	_ok("广播的结算单就是本次（survived=%s · 入包 %d 件）"
			% [str(res.survived) if res != null else "?", res.bagged_equipment.size() if res != null else -1],
		res != null and res.survived
			and res.bagged_equipment.size() == _player.inventory.size()
			and res.bagged_equipment.size() >= def.guaranteed_equipment_drops)

	_finish()


# =============================================================================
# 工具
# =============================================================================

## 场景里现存的收集物（`is_collectible` 标记的 LootDrop）
func _collectibles() -> Array[LootDrop]:
	var out: Array[LootDrop] = []
	for n in get_tree().get_nodes_in_group(&"loot_drops"):
		var d := n as LootDrop
		if d != null and d.is_collectible and is_instance_valid(d):
			out.append(d)
	return out


func _count_buttons(root: Node) -> int:
	var n := 0
	if root is Button:
		n += 1
	for c in root.get_children():
		n += _count_buttons(c)
	return n


func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## 轮询直到 `pred()` 为真，返回是否成功（超时返回 false）
func _wait_until(pred: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		await get_tree().process_frame
		if pred.call():
			return true
	return false


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
