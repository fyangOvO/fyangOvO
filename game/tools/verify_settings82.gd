## 设置持久化实测（任务 8.2 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_settings82.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（5 个测试段）：
##   A. 默认值：无文件 → 默认（音量 -6 / vsync true / fullscreen false）
##   B. 写入读回：set_value → save → 内存镜像一致
##   C. 跨加载保持：save 后 load 新镜像 → 值一致 + 应用（AudioServer 联动）
##   D. 类型白名单：字符串塞 bool/数字 → 回退默认；非法 JSON → 隔离 + 默认
##   E. 清理：测试 settings.json 删除
extends Node2D

const PATH := "user://settings.json"

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 设置持久化实测（任务 8.2） =====")
	await _run()
	_finish()


func _run() -> void:
	# 清理测试现场
	_dir_remove(PATH)

	# A. 默认值
	var s := SettingsStore.load()
	_ok("默认值：音量 -6 / vsync / 非全屏",
		is_equal_approx(float(s["master_volume_db"]), -6.0)
		and bool(s["vsync"]) and not bool(s["fullscreen"]))

	# B. 写入 + 保存
	_ok("set_value 返回 true", SettingsStore.set_value("master_volume_db", -12.0))
	SettingsStore.set_value("vsync", false)
	SettingsStore.set_value("fullscreen", true)
	_ok("内存镜像已更新", is_equal_approx(float(SettingsStore.current["master_volume_db"]), -12.0)
		and not bool(SettingsStore.current["vsync"]) and bool(SettingsStore.current["fullscreen"]))
	_ok("save 落盘成功", SettingsStore.save() and FileAccess.file_exists(PATH))

	# C. 重新加载（模拟重开）
	var s2 := SettingsStore.load()
	_ok("重载后值一致", is_equal_approx(float(s2["master_volume_db"]), -12.0)
		and not bool(s2["vsync"]) and bool(s2["fullscreen"]))
	_ok("应用联动 AudioServer（-12 dB）",
		is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), -12.0))

	# D. 类型白名单 + 非法 JSON
	SettingsStore.set_value("master_volume_db", "not_a_number")
	_ok("字符串塞 float → 回退默认 -6",
		is_equal_approx(float(SettingsStore.current["master_volume_db"]), -6.0))
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("{ broken json !!!")
		f.close()
	var s3 := SettingsStore.load()
	_ok("非法 JSON → 隔离 + 回退默认",
		is_equal_approx(float(s3["master_volume_db"]), -6.0)
		and bool(s3["vsync"]))
	var corrupt_count := 0
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			print("  [dir] ", name)
			if name.begins_with("settings.json.corrupt_"):
				corrupt_count += 1
			name = dir.get_next()
	_ok("损坏文件已隔离为 settings.json.corrupt_*（找到 %d 个）" % corrupt_count, corrupt_count >= 1)

	# E. 清理
	_dir_remove(PATH)
	_ok("清理完成（settings.json 已删）", not FileAccess.file_exists(PATH))


func _dir_remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
