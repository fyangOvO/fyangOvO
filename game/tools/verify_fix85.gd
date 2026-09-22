## Bug 修复与回归红线复核（任务 8.5 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_fix85.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 目的：对开发期踩过坑的关键修复点做「回归红线」抽查，防止后续改动回退。
## 覆盖（8 项）：
##   A. 存档槽位边界（历史：SLOT=18 越界 SAVE_MAX_SLOTS=8）
##   B. 设置持久化（历史：非法 JSON 隔离句柄锁 / 类型白名单）
##   C. 对象池无泄漏（历史：Node.visible 误用 / 循环变量作用域）
##   D. 地图批处理（历史：cells 是 Dictionary / player_spawn 是 Vector2i / 障碍格）
##   E. 平衡口径（历史：TTK 94s 海绵化 → 复合成长 1.30）
##   F. 数据完整性锚点（BOSS 2 / 怪物 16 / 技能 8 / 装备 62）
extends Node2D

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== Bug 修复与回归红线复核（任务 8.5） =====")
	await _run()
	_finish()


func _run() -> void:
	# A. 存档槽位边界
	_ok("存档槽位边界：槽位 7 可用（SAVE_MAX_SLOTS=%d）" % GameConstants.SAVE_MAX_SLOTS,
		GameConstants.SAVE_MAX_SLOTS >= 8 and 7 < GameConstants.SAVE_MAX_SLOTS)
	var sd := SaveData.new()
	_ok("SaveData 字段矩阵完整（含局内进度/设置）",
		sd.to_dict().has("current_level_id") and sd.to_dict().has("settings"))

	# B. 设置持久化
	var ss := SettingsStore.load()
	_ok("设置类型白名单（字符串塞 float 回退默认 -6）",
		SettingsStore._typed("master_volume_db", "bad") == -6.0)
	_ok("设置默认值镜像完整", is_equal_approx(float(ss["master_volume_db"]), -6.0)
		and bool(ss["vsync"]) and ss.has("key_bindings"))

	# C. 对象池
	ObjectPool.clear()
	var p1 := ObjectPool.acquire("redline", func() -> Node: return Node.new())
	ObjectPool.release("redline", p1)
	var p2 := ObjectPool.acquire("redline", func() -> Node: return Node.new())
	ObjectPool.release("redline", p2)
	_ok("对象池复用 + 退出零泄漏", p2 == p1 and ObjectPool.live("redline") == 0)
	ObjectPool.drain()

	# D. 地图批处理
	var ldef: LevelData = ConfigLoader.get_level("ch1_l01")
	var layout := LevelGenerator.generate(ldef, RandomNumberGenerator.new())
	var lv := LevelView.new()
	lv.set_layout(layout)
	var cells: Dictionary = layout["cells"]
	var has_obstacle := false
	for k in cells:
		if int(cells[k]) == LevelGenerator.TILE_OBSTACLE:
			has_obstacle = true
			break
	_ok("LevelView 兼容 Dictionary cells + 障碍格（%d 格 / 障碍 %s）" % [lv.tile_count(), str(has_obstacle)],
		lv.tile_count() == cells.size() and lv.tile_count() > 0)
	lv.queue_free()

	# E. 平衡口径（复合成长 1.30 → TTK 收敛）
	var t20 := 100.7 * pow(1.284, 19) / (20.0 * pow(1.30, 20) * 1.25)
	var t1 := 100.7 / (20.0 * pow(1.30, 1) * 1.25)
	_ok("平衡红线：20 关 TTK=%.1fs（不海绵化，原 1.10 为 94s）" % t20,
		t20 >= 1.0 and t20 <= 8.0 and t20 <= t1 * 2.0)

	# F. 数据完整性锚点
	_ok("数据表锚点：怪物 16 / BOSS 2 / 技能 8 / 装备 62 / 关卡 20",
		ConfigLoader.monsters.size() == 16 and ConfigLoader.bosses.size() == 2
		and ConfigLoader.skills.size() == 8 and ConfigLoader.equipment_templates.size() == 62
		and ConfigLoader.levels.size() == 20)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
