## 输入重映射 + 手柄热插拔（任务 1.3 · Autoload 单例名 `InputRemapper`）
##
## 定位：把「输入动作的默认定义」与「玩家自定义绑定」分开。
##   - **默认绑定**写在 `project.godot` 的 `[input]` 段 —— 权威来源，首次启动即生效；
##   - **玩家改动**写入 `user://input_bindings.json`，启动时覆盖默认值。
##
## ⚠️ 文件名刻意叫 `input_remapper.gd` 而非 `input_map.gd`：
##    `InputMap` 是 Godot 内建单例，同名会遮蔽全局类导致解析错误。
##
## 重绑定语义（重要，别改）：
##   `rebind()` 只替换**同设备类别**的既有事件 —— 改键位不会顺手清掉手柄绑定，反之亦然。
##   例：把 dodge 从 Space 改到 Shift，手柄 B 键的绑定保持不变。
##
## 用法：
##   InputRemapper.rebind("dodge", new_event)   # 改绑（按设备类别替换）
##   InputRemapper.reset_to_default("dodge")    # 恢复单个动作的出厂绑定
##   InputRemapper.reset_all_to_default()       # 全部恢复出厂
##   InputRemapper.save_bindings()              # 落盘到 user://
##   InputRemapper.load_bindings()              # 读盘（_ready 已自动调用一次）
extends Node

## 玩家自定义绑定的落盘路径（`user://` 由 Godot 按平台映射到可写目录）
const BINDINGS_PATH: String = "user://input_bindings.json"

## 本模块负责的动作全集（顺序即「按键设置」界面的展示顺序）。
## 增删动作时必须同步 project.godot 的 [input] 段，否则自检会报缺。
const MANAGED_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"dodge", &"attack_primary",
	&"skill_1", &"skill_2", &"skill_3", &"skill_4",
	&"consume_1", &"consume_2",
	&"interact", &"inventory", &"character_panel", &"pause",
]

## 设备类别标签：同类别的事件互相替换，不同类别共存
const CLASS_KEYBOARD: String = "keyboard"
const CLASS_MOUSE: String = "mouse"
const CLASS_JOYPAD: String = "joypad"
const CLASS_UNKNOWN: String = "unknown"

## 出厂默认绑定快照 {action: Array[InputEvent]}。
## 在 _ready 里、**加载玩家覆盖之前**捕获 —— 顺序颠倒会让「恢复默认」变成空操作。
var _defaults: Dictionary = {}


func _ready() -> void:
	_capture_defaults()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	load_bindings()


## 把当前 InputMap（= project.godot 的默认绑定）存为出厂快照
func _capture_defaults() -> void:
	_defaults.clear()
	for action in MANAGED_ACTIONS:
		if not InputMap.has_action(action):
			push_warning("[InputRemapper] 动作缺失，请检查 project.godot 的 [input] 段：%s" % action)
			continue
		_defaults[action] = InputMap.action_get_events(action).duplicate()


# =============================================================================
# 一、查询
# =============================================================================

## 取某动作当前的全部绑定事件（返回副本，调用方随便改）
func get_action_events(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		out.append(e)
	return out


## 取某动作的出厂默认绑定
func get_default_events(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var stored: Variant = _defaults.get(action)
	if stored is Array:
		for e in stored:
			out.append(e)
	return out


## 该动作是否已被玩家改过（与出厂快照不一致）
func is_modified(action: StringName) -> bool:
	return _fingerprint(get_action_events(action)) != _fingerprint(get_default_events(action))


## 本模块管理的动作里，是否至少有一个存在绑定（用于「有没有手柄」这类判断）
func has_any_joypad_binding() -> bool:
	for action in MANAGED_ACTIONS:
		for e in get_action_events(action):
			if _device_class(e) == CLASS_JOYPAD:
				return true
	return false


# =============================================================================
# 二、重绑定
# =============================================================================

## 改绑：把 `action` 中与 `event` **同设备类别**的旧事件全部替换为 `event`。
## 返回 false 表示动作不存在或事件类型不受支持。
func rebind(action: StringName, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		push_warning("[InputRemapper] 未知动作，改绑失败：%s" % action)
		return false
	var cls := _device_class(event)
	if cls == CLASS_UNKNOWN:
		push_warning("[InputRemapper] 不支持的事件类型，改绑失败：%s" % event)
		return false

	# 先清掉同类别旧事件，再挂新的 —— 避免出现「一个动作绑了两个空格键」
	for existing in InputMap.action_get_events(action):
		if _device_class(existing) == cls:
			InputMap.action_erase_event(action, existing)
	InputMap.action_add_event(action, event)

	EventBus.input_binding_changed.emit(action)
	return true


## 追加一个绑定（不清旧事件）。用于「一键两用」的场景。
func add_binding(action: StringName, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		push_warning("[InputRemapper] 未知动作，追加绑定失败：%s" % action)
		return false
	if _device_class(event) == CLASS_UNKNOWN:
		return false
	InputMap.action_add_event(action, event)
	EventBus.input_binding_changed.emit(action)
	return true


## 把单个动作恢复为出厂默认
func reset_to_default(action: StringName) -> bool:
	var stored: Variant = _defaults.get(action)
	if not (stored is Array):
		push_warning("[InputRemapper] 无出厂快照，恢复默认失败：%s" % action)
		return false
	InputMap.action_erase_events(action)
	for e in stored:
		InputMap.action_add_event(action, e)
	EventBus.input_binding_changed.emit(action)
	return true


## 全部动作恢复出厂默认
func reset_all_to_default() -> void:
	for action in MANAGED_ACTIONS:
		reset_to_default(action)


# =============================================================================
# 三、持久化
# =============================================================================

## 把当前绑定落盘。只写**与出厂默认不同**的动作，让文件尽量小、也便于人工排查。
func save_bindings() -> bool:
	var payload: Dictionary = {
		"version": 1,
		"bindings": {},
	}
	var changed: Dictionary = {}
	for action in MANAGED_ACTIONS:
		if not InputMap.has_action(action):
			continue
		if not is_modified(action):
			continue
		var encoded: Array = []
		for e in InputMap.action_get_events(action):
			var d := _event_to_dict(e)
			if not d.is_empty():
				encoded.append(d)
		changed[String(action)] = encoded
	payload["bindings"] = changed

	var f := FileAccess.open(BINDINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[InputRemapper] 无法写入 %s（错误码 %d）" % [BINDINGS_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return true


## 读盘并覆盖当前绑定。文件不存在 / 损坏时**静默回退到出厂默认**，不阻断启动。
func load_bindings() -> bool:
	if not FileAccess.file_exists(BINDINGS_PATH):
		return false
	var f := FileAccess.open(BINDINGS_PATH, FileAccess.READ)
	if f == null:
		push_warning("[InputRemapper] 无法读取 %s，沿用出厂默认" % BINDINGS_PATH)
		return false
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[InputRemapper] 绑定文件格式非法，沿用出厂默认：%s" % BINDINGS_PATH)
		return false

	var bindings: Variant = (parsed as Dictionary).get("bindings", {})
	if not (bindings is Dictionary):
		return false

	var applied: int = 0
	for key in (bindings as Dictionary).keys():
		var action := StringName(String(key))
		if not InputMap.has_action(action):
			push_warning("[InputRemapper] 绑定文件里有未知动作，已跳过：%s" % action)
			continue
		var raw: Variant = (bindings as Dictionary)[key]
		if not (raw is Array):
			continue
		InputMap.action_erase_events(action)
		for entry in (raw as Array):
			var ev := _dict_to_event(entry)
			if ev != null:
				InputMap.action_add_event(action, ev)
		applied += 1

	if applied == 0:
		return false
	EventBus.input_bindings_loaded.emit(applied)
	return true


# =============================================================================
# 四、手柄热插拔
# =============================================================================

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	# 只做转发，不做业务判断 —— 具体反应（弹提示 / 切 UI 提示）交给监听方
	EventBus.joypad_connection_changed.emit(device, connected)


# =============================================================================
# 五、内部：事件分类与序列化
# =============================================================================

func _device_class(event: InputEvent) -> String:
	if event is InputEventKey:
		return CLASS_KEYBOARD
	if event is InputEventMouseButton:
		return CLASS_MOUSE
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return CLASS_JOYPAD
	return CLASS_UNKNOWN


## 事件 → 可 JSON 化的字典。Godot 没有内建 InputEvent 序列化，这里手写白名单。
func _event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var k := event as InputEventKey
		return {
			"type": "key",
			"physical_keycode": int(k.physical_keycode),
			"keycode": int(k.keycode),
			"shift": k.shift_pressed,
			"ctrl": k.ctrl_pressed,
			"alt": k.alt_pressed,
			"meta": k.meta_pressed,
		}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button_index": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button_index": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		return {"type": "joy_axis", "axis": int(m.axis), "axis_value": m.axis_value}
	return {}


## 字典 → 事件。无法识别时返回 null（调用方跳过，不崩）。
func _dict_to_event(entry: Variant) -> InputEvent:
	if not (entry is Dictionary):
		return null
	var d := entry as Dictionary
	match String(d.get("type", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("physical_keycode", 0)) as Key
			k.keycode = int(d.get("keycode", 0)) as Key
			k.shift_pressed = bool(d.get("shift", false))
			k.ctrl_pressed = bool(d.get("ctrl", false))
			k.alt_pressed = bool(d.get("alt", false))
			k.meta_pressed = bool(d.get("meta", false))
			return k
		"mouse_button":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.get("button_index", 1)) as MouseButton
			return mb
		"joy_button":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("button_index", 0)) as JoyButton
			return jb
		"joy_axis":
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(d.get("axis", 0)) as JoyAxis
			jm.axis_value = float(d.get("axis_value", 1.0))
			return jm
	return null


## 绑定集合的指纹，用于 is_modified 比较（顺序无关）
func _fingerprint(events: Array[InputEvent]) -> String:
	var parts: PackedStringArray = []
	for e in events:
		parts.append(JSON.stringify(_event_to_dict(e)))
	parts.sort()
	return "|".join(parts)
