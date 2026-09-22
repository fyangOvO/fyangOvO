## 崩溃与异常处理：游戏日志（任务 9.3 · class_name GameLog 纯静态）
##
## 职责：
##   - 日志落盘 user://logs/game.log（append，按天轮转 7 份）
##   - 启动时记录引擎/项目/存档目录，异常与关键事件带时间戳
##   - Godot 无全局异常钩子；本模块 + SaveManager 容错（备份/损坏隔离）共同构成
##     9.3 稳定性补丁。崩溃后下一次启动可通过日志定位。
class_name GameLog

const LOG_DIR := "user://logs"
const LOG_FILE := "game.log"
const MAX_BYTES := 2 * 1024 * 1024


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LOG_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))


static func info(msg: String) -> void:
	_write("INFO", msg)


static func warn(msg: String) -> void:
	_write("WARN", msg)


static func error(msg: String) -> void:
	_write("ERROR", msg)


static func _write(level: String, msg: String) -> void:
	_ensure_dir()
	var path := LOG_DIR + "/" + LOG_FILE
	# 超限轮转：game.log → game.1.log → … → game.6.log（保留 7 份）
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var sz := f.get_length()
			f.close()
			if sz > MAX_BYTES:
				for i in range(5, 0, -1):
					var from_path := LOG_DIR + "/game.%d.log" % i
					var to_path := LOG_DIR + "/game.%d.log" % (i + 1)
					if FileAccess.file_exists(from_path):
						DirAccess.rename_absolute(
							ProjectSettings.globalize_path(from_path),
							ProjectSettings.globalize_path(to_path))
				if FileAccess.file_exists(path):
					DirAccess.rename_absolute(
						ProjectSettings.globalize_path(path),
						ProjectSettings.globalize_path(LOG_DIR + "/game.1.log"))
	var line := "%s [%s] %s\n" % [Time.get_datetime_string_from_system(), level, msg]
	# ⚠️ 两个坑，都必须显式处理：
	#
	# 1) 必须是**追加**，不能截断。用 FileAccess.WRITE 会清空文件，日志永远只剩最后一行 ——
	#    文件永远长不到 MAX_BYTES，上面的 2MB 轮转与「保留 7 份」全是死逻辑，
	#    read_tail() 也最多返回 1 行，9.3「崩溃后靠日志定位」的目的被完全废掉。
	#
	# 2) `FileAccess.READ_WRITE` **不会新建文件**。实测：文件不存在时返回 null，
	#    open_error=7（ERR_FILE_NOT_FOUND）。
	#    后果有两个，且第二个更严重：
	#      - 轮转刚把 game.log rename 成 game.1.log，这一行会被静默丢弃；
	#      - **全新机器上 game.log 从来不存在 ⇒ 永远建不出来 ⇒ 日志功能整体失效**。
	#    只测「文件已存在时能不能追加」是发现不了第 2 条的 —— 测试机上的旧日志一直在。
	#    所以这里按存在与否选模式：不存在用 WRITE 新建（空文件 + seek_end 即追加），
	#    存在用 READ_WRITE 定位到尾部追加。
	var f2 := FileAccess.open(
		path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f2 == null:
		return
	f2.seek_end()
	f2.store_string(line)
	f2.close()


static func read_tail(lines: int = 20) -> Array[String]:
	var out: Array[String] = []
	var path := LOG_DIR + "/" + LOG_FILE
	if not FileAccess.file_exists(path):
		return out
	var all := FileAccess.get_file_as_string(path).split("\n")
	for i in range(maxi(0, all.size() - lines), all.size()):
		if all[i] != "":
			out.append(all[i])
	return out
