## 崩溃与异常处理实测（任务 9.3 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_fix93.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖（25 项）：
##   A. 日志落盘：GameLog.info 写入 user://logs/game.log 且带时间戳
##   B. 日志尾部可读（read_tail 返回最后 N 行）
##   C. 存档容错红线：损坏主档 → 备份回滚 + 隔离 + 重建（SaveManager 既有机制抽查）
##   D. 日志轮转逻辑存在（MAX_BYTES / game.1.log 命名约定）
##   E. 【回归】日志**追加**写：连写 3 行 → read_tail 必须返回 ≥3 行；字节数递增
##          （旧实现用 FileAccess.WRITE 截断 ⇒ 日志永远只剩 1 行，
##            连带让 2MB 轮转永不触发。只测「写 1 行读 1 行」永远发现不了）
##   F. 【回归】日志轮转**实测**：把日志撑到 > MAX_BYTES → 再写一行必须触发轮转；
##          且轮转后 game.log 必须被重新建出来并含新行（这条路径要单独验）
##   I. 【回归】日志**首建**：删掉 game.log 后再写一行必须重新建出文件。
##          （`FileAccess.READ_WRITE` **不新建文件**，实测 open_error=7 ERR_FILE_NOT_FOUND。
##            旧实现只在文件已存在时能写 ⇒ **全新机器上日志永远建不出来**，9.3 整体失效。
##            E/F 都跑在「文件已存在」的前提下，抓不住这条，必须单独造「不存在」场景）
##   G. 【回归】`EnemyBase._player_level()` 方法名错配：旧实现只探测 `get_level`，
##          而玩家暴露的是 `get_player_level()` ⇒ 恒返回 0 ⇒ 越级惩罚静默失效。
##          ⚠️ 本项**必须挂真实玩家节点**：只测 `_player == null` 那条分支测不出问题
##   H. 【回归】受击契约完整性：`PlayerController` 必须有 `apply_knockback`
##          （`SkillController._hit` 用 has_method 探测，缺了就静默跳过，无任何报错）
##          且位移必须与请求量**同量级** —— 旧实现 `velocity += _knockback_velocity`
##          会逐帧累积，请求 12px 实际走 61.4px（约 5 倍且发散）。
##          只断言「> 1.0」抓不住这个，所以补了上界。
extends Node2D

var _fail: int = 0

const SLOT := 6
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const ENEMY_SCENE: String = "res://scenes/enemies/enemy_base.tscn"
const LOG_PATH: String = "user://logs/game.log"
const LOG_BACKUP_PATH: String = "user://logs/game.1.log"

var _player: PlayerController = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _await_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 崩溃与异常处理实测（任务 9.3） =====")
	await _run()
	_finish()


func _run() -> void:
	# A. 日志落盘
	GameLog.info("稳定性自检写入：engine=%s" % Engine.get_version_info().get("string", "?"))
	_ok("日志文件已落盘", FileAccess.file_exists(LOG_PATH))
	var content := _read_text(LOG_PATH)
	_ok("日志含 INFO 标记与时间戳", content.contains("[INFO]") and content.contains("2026"))

	# B. 尾部读取
	var tail := GameLog.read_tail(5)
	_ok("read_tail 返回最近日志（%d 行）" % tail.size(),
		tail.size() >= 1 and tail[tail.size() - 1].contains("稳定性自检"))

	# C. 存档容错（损坏 → 备份回滚 + 隔离 + 重建）
	if SaveManager.slot_exists(SLOT):
		SaveManager.delete_slot(SLOT)
	var d := SaveManager.create_new_slot(SLOT)
	_ok("新建槽位成功", d != null)
	if d != null:
		d.gold = 777
		SaveManager.save_to_slot(SLOT, d)
		SaveManager.save_to_slot(SLOT, d)  # 生成备份
		# 写坏主档
		var main_path := ProjectSettings.globalize_path(SaveManager._slot_path(SLOT))
		var bad := FileAccess.open(main_path, FileAccess.WRITE)
		if bad != null:
			bad.store_string("{ corrupted !!!")
			bad.close()
		var rec := SaveManager.load_from_slot(SLOT)
		_ok("存档损坏 → 备份回滚成功", rec != null and rec.gold == 777)
		SaveManager.delete_slot(SLOT)
		_ok("清理完成", not SaveManager.slot_exists(SLOT))

	# D. 轮转约定
	_ok("日志轮转约定存在（MAX_BYTES=2MB / game.N.log 命名）",
		GameLog.MAX_BYTES == 2 * 1024 * 1024 and GameLog.LOG_FILE == "game.log")

	await _test_log_append()
	await _test_log_rotation()
	await _test_log_fresh_create()
	await _test_player_level_probe()
	await _test_knockback_contract()


# =============================================================================
# E. 回归：日志必须是**追加**写，不是覆盖写
# =============================================================================

func _test_log_append() -> void:
	print("--- E. 日志追加写（回归：曾用 WRITE 截断，日志永远只剩 1 行）---")
	GameLog.info("追加写测试 1/3")
	var size1 := _file_size(LOG_PATH)
	GameLog.info("追加写测试 2/3")
	var size2 := _file_size(LOG_PATH)
	GameLog.info("追加写测试 3/3")
	var size3 := _file_size(LOG_PATH)
	var tail := GameLog.read_tail(10)
	_ok("连写 3 行后 read_tail 返回 ≥3 行（实际 %d 行）" % tail.size(), tail.size() >= 3)
	_ok("写第 2 行后文件字节数增大（%d → %d）" % [size1, size2], size2 > size1)
	_ok("写第 3 行后字节数继续增大（%d → %d）" % [size2, size3], size3 > size2)


# =============================================================================
# F. 回归：轮转路径实测（超限 → rename → 重建 game.log）
# =============================================================================

func _test_log_rotation() -> void:
	print("--- F. 日志轮转实测（撑到 > MAX_BYTES 后应触发 rename）---")
	var had_backup := FileAccess.file_exists(LOG_BACKUP_PATH)
	var backup_orig := _read_text(LOG_BACKUP_PATH)
	var log_orig := _read_text(LOG_PATH)

	# 把当前日志撑到超过 MAX_BYTES（一次性写入，不依赖循环 append）
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("FILLER".repeat((GameLog.MAX_BYTES + 64 * 1024) / 5))
		f.close()
	var oversized := _file_size(LOG_PATH)
	_ok("已构造超限日志（%d B > MAX_BYTES %d B）" % [oversized, GameLog.MAX_BYTES],
		oversized > GameLog.MAX_BYTES)

	# 再写一行 → 必须触发轮转
	GameLog.info("轮转测试标记")
	var rotated := FileAccess.file_exists(LOG_BACKUP_PATH)
	var after := _read_text(LOG_PATH)
	_ok("超限后触发轮转：game.1.log 已生成", rotated)
	_ok("轮转后 game.log 被重新建出且只含新行（%d B）" % after.length(),
		after.contains("轮转测试标记") and after.length() < 4096)
	_ok("轮转后 game.log 字节数已回落（%d → %d）" % [oversized, _file_size(LOG_PATH)],
		_file_size(LOG_PATH) < oversized)

	# 还原现场：删掉本次产生的 game.1.log（或还原原有的），并把 game.log 写回
	if had_backup:
		_write_text(LOG_BACKUP_PATH, backup_orig)
	elif FileAccess.file_exists(LOG_BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_BACKUP_PATH))
	_write_text(LOG_PATH, log_orig)


# =============================================================================
# I. 回归：日志**首建**（文件不存在时也必须能建出来）
# =============================================================================

func _test_log_fresh_create() -> void:
	print("--- I. 日志首建（回归：READ_WRITE 不新建文件 ⇒ 全新机器永远没有日志）---")
	var orig := _read_text(LOG_PATH)
	# 模拟全新机器：日志文件与目录都不存在
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))
	_ok("已构造「game.log 不存在」场景", not FileAccess.file_exists(LOG_PATH))

	GameLog.info("首建测试标记")
	_ok("首建后 game.log 已被创建", FileAccess.file_exists(LOG_PATH))
	var after := _read_text(LOG_PATH)
	_ok("首建内容非空且含本次标记（%d B）" % after.length(),
		after.contains("首建测试标记") and after.length() > 0)
	_ok("首建行带时间戳格式", after.contains("[INFO]") and after.contains("2026"))

	# 还原现场（避免把开发机的日志清成只剩一行）
	_write_text(LOG_PATH, orig)


# =============================================================================
# G. 回归：EnemyBase._player_level() 必须拿到真实玩家等级
# =============================================================================

func _test_player_level_probe() -> void:
	print("--- G. 越级惩罚用玩家等级（回归：曾探测错方法名 ⇒ 恒 0）---")
	var packed_p: PackedScene = load(PLAYER_SCENE)
	if packed_p == null:
		_ok("player.tscn 可加载", false)
		return
	_player = packed_p.instantiate() as PlayerController
	if _player == null:
		_ok("player.tscn 根节点是 PlayerController", false)
		return
	_player.global_position = Vector2(0, 0)
	add_child(_player)

	var packed_e: PackedScene = load(ENEMY_SCENE)
	if packed_e == null:
		_ok("enemy_base.tscn 可加载", false)
		return
	var enemy := packed_e.instantiate() as EnemyBase
	if enemy == null:
		_ok("enemy_base.tscn 根节点是 EnemyBase", false)
		return
	enemy.global_position = Vector2(400, 400)  # 放远一点，避免立刻进入战斗
	add_child(enemy)
	await _await_frames(3)  # 等 _refresh_player() 把玩家引用填上

	var lv := enemy._player_level()
	var expect := _player.get_player_level()
	_ok("敌人已拿到玩家引用（_player 非空）", enemy._player != null)
	_ok("_player_level() 与 get_player_level() 一致（%d / %d）" % [lv, expect], lv == expect)

	# ⚠️ 【2026-09-18 加固】旧断言是 `lv != 0` —— 桩恒返回 1 也满足它，属「弱断言把 bug
	#    伪装成通过」（本项目击退发散那条同类教训）。改为**证伪性**断言：等级必须
	#    **随账号等级变化**，而不是恒为某值。这样才能真正盯死「越级惩罚取错等级」。
	var saved_data := SaveManager.current_data
	var probe := SaveData.create_new(0)
	probe.account_level = 42
	SaveManager.current_data = probe
	var lv42 := _player.get_player_level()
	var lv42_enemy := enemy._player_level()
	_ok("账号等级 42 → get_player_level()=42（真实化，非恒 1）", lv42 == 42)
	_ok("越级惩罚取的等级跟随账号等级（enemy._player_level()=%d）" % lv42_enemy, lv42_enemy == 42)
	probe.account_level = 7
	_ok("账号等级改 7 → 跟随变化（%d ≠ 42 ⇒ 证伪「恒 1」）" % _player.get_player_level(),
		_player.get_player_level() == 7)
	SaveManager.current_data = null
	_ok("无账号数据 → 回退 1（测试环境依赖此回退）", _player.get_player_level() == 1)
	SaveManager.current_data = saved_data

	enemy.queue_free()
	await _await_frames(1)


# =============================================================================
# H. 回归：受击契约完整性（apply_knockback）
# =============================================================================

func _test_knockback_contract() -> void:
	print("--- H. 受击契约：apply_knockback 必须存在 ---")
	if _player == null:
		_ok("玩家节点就绪（前置）", false)
		return
	_ok("PlayerController.has_method(\"apply_knockback\") == true",
		_player.has_method("apply_knockback"))
	if not _player.has_method("apply_knockback"):
		return
	# 行为断言 1：真的被推开了（防止「方法存在但空实现」）
	var before := _player.global_position
	_player.apply_knockback(Vector2(12.0, 0.0))
	await _await_frames(8)
	var moved := (_player.global_position - before).length()
	_ok("apply_knockback(12,0) 真的产生位移（%.1f px > 1.0）" % moved, moved > 1.0)

	# 行为断言 2（上界）：位移必须与请求量**同量级**。
	# 旧实现 `velocity += _knockback_velocity` 把跨帧持久的 velocity 当成临时量自加，
	# 击退逐帧累积 ⇒ 请求 12px 实测走成 61.4px（且随帧数发散）。
	# 只断言「> 1.0」是抓不住这个的 —— 发散反而让上一条更容易通过，必须卡上界。
	#
	# 理论值：v0 = sqrt(2·a·L) = sqrt(2×1200×12) ≈ 169.7 px/s，衰减 1200 px/s²；
	# 8 帧（0.1333s）位移 ≈ v0·t − a·t²/2 = 169.7×0.1333 − 1200×0.1333²/2 ≈ 11.96 px。
	# 取 2 倍余量（24px）作上界：既不误伤离散化误差，也不放过 5 倍发散。
	_ok("位移与请求量同量级（%.1f px，期望 ≈12，容许 6–24）" % moved,
		moved > 6.0 and moved < 24.0)

	# 行为断言 3：击退必须会停 —— 衰减结束后速度归零，不能一直飘。
	await _await_frames(20)
	var drift := (_player.global_position - before).length()
	await _await_frames(10)
	var drift2 := (_player.global_position - before).length()
	_ok("击退已衰减停止（%.2f px → %.2f px，差值 < 0.5）" % [drift, drift2],
		absf(drift2 - drift) < 0.5)


# =============================================================================
# 工具
# =============================================================================

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()


func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
