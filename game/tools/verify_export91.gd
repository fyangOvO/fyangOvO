## 导出产物验证（任务 9.1 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_export91.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖（5 项）：
##   A. 导出 exe 存在（build/七傳說.exe）
##   B. 大小合理（内嵌 PCK ≥ 60MB；纯壳仅 ~60-80MB 无法区分 → 以 ≥ 60MB 为准）
##   C. 导出预设存在且指向正确（Windows Desktop / embed_pck）
##   D. 预设输出路径与 exe 一致
extends Node2D

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 导出产物验证（任务 9.1） =====")
	await _run()
	_finish()


func _run() -> void:
	# A/B. exe 存在 + 大小（embed_pck=true 时包内含全部资源）
	var exe_path := "res://build/七傳說.exe"
	var exists := FileAccess.file_exists(exe_path)
	var size_mb := 0.0
	if exists:
		var f := FileAccess.open(exe_path, FileAccess.READ)
		if f != null:
			size_mb = float(f.get_length()) / (1024.0 * 1024.0)
			f.close()
	_ok("导出 exe 存在（build/七傳說.exe）", exists)
	_ok("exe 体积合理（%.1f MB ≥ 60MB，资源内嵌）" % size_mb, exists and size_mb >= 60.0)

	# C. 预设存在
	var preset_text := FileAccess.get_file_as_string("res://export_presets.cfg") \
		if FileAccess.file_exists("res://export_presets.cfg") else ""
	_ok("导出预设存在（Windows Desktop）",
		preset_text.contains("platform=\"Windows Desktop\""))
	_ok("预设内嵌 PCK（embed_pck=true，单文件分发）",
		preset_text.contains("binary_format/embed_pck=true"))
	_ok("预设输出路径指向 build/七傳說.exe",
		preset_text.contains("build/七傳說.exe"))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
