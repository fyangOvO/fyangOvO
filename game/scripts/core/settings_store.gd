## 设置持久化（任务 8.2 · class_name SettingsStore 纯静态）
##
## 独立于存档的 user://settings.json（换档不丢设置）。
## 类型白名单：master_volume_db(float, 默认 -6) / vsync(bool) / fullscreen(bool) /
## key_bindings(Dictionary)。读写带类型校验，非法/缺失回退默认值。
## 7.7 SettingsPanel 改动即调 save()；启动时由 main 调 load() 应用。
class_name SettingsStore

const SETTINGS_PATH := "user://settings.json"

const DEFAULTS := {
	"master_volume_db": -6.0,
	"vsync": true,
	"fullscreen": false,
	"key_bindings": {},
}

## 当前生效设置（内存镜像）
static var current: Dictionary = DEFAULTS.duplicate()


## 加载并应用：文件缺失 → 默认；JSON 非法 → 隔离 + 默认
static func load() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f != null:
			var raw := f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				out = _merge(parsed)
			else:
				# 非法 JSON：隔离现场（复制为 .corrupt_*），回退默认
				var bad_path := SETTINGS_PATH + ".corrupt_" + str(Time.get_unix_time_from_system())
				var src := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
				if src != null:
					var dst := FileAccess.open(bad_path, FileAccess.WRITE)
					if dst != null:
						dst.store_buffer(src.get_buffer(src.get_length()))
						dst.close()
					src.close()
	current = out
	_apply(out)
	# 按键绑定（InputRemapper 自有持久化，启动时回放）
	if InputRemapper != null and InputRemapper.has_method("load_bindings"):
		InputRemapper.load_bindings()
	return out


## 保存当前内存镜像到磁盘（原子写）
static func save() -> bool:
	var text := JSON.stringify(current, "  ")
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


## 改一个键并立即落盘
static func set_value(key: String, value: Variant) -> bool:
	current[key] = _typed(key, value)
	return save()


## 读取（缺失回退默认）
static func get_value(key: String) -> Variant:
	return current.get(key, DEFAULTS.get(key, null))


static func _merge(raw: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	for k in DEFAULTS:
		if raw.has(k):
			out[k] = _typed(k, raw[k])
	return out


static func _typed(key: String, v: Variant) -> Variant:
	match typeof(DEFAULTS[key]):
		TYPE_FLOAT:
			return float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else DEFAULTS[key]
		TYPE_BOOL:
			return bool(v) if typeof(v) == TYPE_BOOL else DEFAULTS[key]
		TYPE_DICTIONARY:
			return v if typeof(v) == TYPE_DICTIONARY else DEFAULTS[key]
	return v


static func _apply(s: Dictionary) -> void:
	# 音量
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, float(s["master_volume_db"]))
	# 垂直同步 / 全屏
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(s["vsync"]) else DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if bool(s["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED)
