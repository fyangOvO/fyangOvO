## 存档管理器（Autoload · 单例名 `SaveManager`）
##
## 职责：
##   1. **多存档槽** —— 每槽一个 JSON 文件，独立读写
##   2. **版本号** —— 磁盘格式版本随 `SaveData.save_version` 落盘，读档时自动迁移
##   3. **JSON 序列化** —— 人可读、可手改、易调试（本项目纯单机，无体积压力）
##   4. **目录用 `user://`** —— 跨平台安全（Windows 下实际位于 `%APPDATA%/Godot/app_userdata/七傳說/`）
##   5. **损坏保护** —— SHA-256 校验 + 损坏文件隔离，绝不静默丢档
##   6. **备份轮转** —— 每槽保留 N 份历史备份，主档损坏时按新→旧自动回滚
##
## 磁盘布局：
##   user://saves/slot_00.json          主档
##   user://saves/slot_00.json.bak1     最近一次写入前的备份
##   user://saves/slot_00.json.bak2
##   user://saves/slot_00.json.bak3
##   user://saves/slot_00.corrupt_<ts>  损坏档隔离区（不自动删除，便于人工抢救）
##
## 写入是**原子**的：先写 `.tmp`，成功后替换主档 —— 断电/崩溃不会产生半截文件。
##
## ⚠️ 本管理器**不做任何游戏逻辑**（不涨经验、不算掉落），只负责「把 SaveData 存下来/取出来」。
extends Node

# =============================================================================
# 常量
# =============================================================================

## 文件头标识，用于快速判断「这是不是本游戏的存档」
const SAVE_MAGIC: String = "QILUAN_SAVE"

## 主档文件名模板
const SLOT_FILE_FORMAT: String = "slot_%02d.json"

## 备份份数（取 GameConstants.SAVE_BACKUP_ROTATION）
const BACKUP_COUNT: int = GameConstants.SAVE_BACKUP_ROTATION

## 存档 `materials` 字典里「魔石」的键（`SaveData.create_new` 初始化，见 resources/save_data.gd）
const MATERIAL_KEY_MAGIC_STONE: String = "magic_stone"

# =============================================================================
# 状态
# =============================================================================

## 存档目录（user://saves）
var save_dir: String = GameConstants.SAVE_DIR

## 当前操作的槽位（-1 = 未选定）
var current_slot: int = -1

## 当前已加载的存档数据（未加载时为 null）
var current_data: SaveData = null

## 是否启用自动存档
var autosave_enabled: bool = true

## 自动存档间隔（秒）
var autosave_interval: float = 120.0

## 运行期错误记录（供调试面板显示）
var last_error: String = ""

var _autosave_timer: Timer = null


func _ready() -> void:
	_ensure_save_dir()
	_setup_autosave_timer()


# =============================================================================
# 槽位管理
# =============================================================================

## 指定槽位是否存在主档
func slot_exists(slot: int) -> bool:
	return _file_exists(_slot_path(slot))


## 是否存在任意可用存档
func has_any_save() -> bool:
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if slot_exists(i):
			return true
	return false


## 取全部槽位信息（供选档界面使用；只读文件头，不完整解析 payload）
func get_all_slot_infos() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		out.append(get_slot_info(i))
	return out


## 取单个槽位信息。
## 返回：{ slot, exists, corrupted, display_name, account_level, play_time_seconds,
##         updated_at, save_version, error }
func get_slot_info(slot: int) -> Dictionary:
	var info := {
		"slot": slot,
		"exists": false,
		"corrupted": false,
		"display_name": "",
		"account_level": 0,
		"play_time_seconds": 0.0,
		"updated_at": 0,
		"save_version": 0,
		"error": "",
	}

	var path := _slot_path(slot)
	if not _file_exists(path):
		return info

	info["exists"] = true

	var envelope := _read_envelope(path)
	if not envelope.get("ok", false):
		info["corrupted"] = true
		info["error"] = String(envelope.get("error", "未知错误"))
		return info

	var data: Dictionary = envelope.get("data", {})
	info["display_name"] = String(data.get("display_name", ""))
	info["account_level"] = int(data.get("account_level", 0))
	info["play_time_seconds"] = float(data.get("play_time_seconds", 0.0))
	info["updated_at"] = int(data.get("updated_at", 0))
	info["save_version"] = int(data.get("save_version", 0))
	return info


## 删除槽位（含全部备份）。**不可逆**，调用方必须先向用户确认。
func delete_slot(slot: int) -> bool:
	var ok := true
	for path in _all_paths_for_slot(slot):
		if _file_exists(path):
			if not _remove_file(path):
				ok = false
				last_error = "删除存档文件失败：%s" % path
	if current_slot == slot:
		current_slot = -1
		current_data = null
	if ok:
		EventBus.save_slots_changed.emit()
	return ok


## 清空全部槽位
func delete_all_slots() -> bool:
	var ok := true
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if not delete_slot(i):
			ok = false
	EventBus.save_slots_changed.emit()
	return ok


# =============================================================================
# 保存
# =============================================================================

## 把数据写入指定槽位。成功返回 true。
##
## 流程：轮转备份 → 原子写入 → 发信号。
func save_to_slot(slot: int, data: SaveData) -> bool:
	if slot < 0 or slot >= GameConstants.SAVE_MAX_SLOTS:
		last_error = "槽位号越界：%d" % slot
		push_error("[SaveManager] " + last_error)
		EventBus.game_saved.emit(slot, false, last_error)
		return false

	if data == null:
		last_error = "SaveData 为空"
		push_error("[SaveManager] " + last_error)
		EventBus.game_saved.emit(slot, false, last_error)
		return false

	_ensure_save_dir()

	# 1) 更新时间戳与槽位号（以实际写入为准，防止调用方漏填）
	var now := int(Time.get_unix_time_from_system())
	if data.created_at == 0:
		data.created_at = now
	data.updated_at = now
	data.slot = slot
	data.save_version = GameConstants.SAVE_VERSION

	# 2) 序列化 payload（缩进格式，便于人工排查）
	var payload := JSON.stringify(data.to_dict(), "\t")

	# 3) 组装信封 + 校验和
	var envelope := {
		"magic": SAVE_MAGIC,
		"save_version": data.save_version,
		"slot": slot,
		"updated_at": now,
		"checksum": payload.sha256_text(),
		"payload": payload,
	}
	var text := JSON.stringify(envelope, "\t")

	# 4) 轮转备份（必须在覆盖主档之前）
	_rotate_backups(slot)

	# 5) 原子写入
	var path := _slot_path(slot)
	if not _atomic_write(path, text):
		last_error = "写入存档失败：%s" % path
		push_error("[SaveManager] " + last_error)
		EventBus.game_saved.emit(slot, false, last_error)
		return false

	current_slot = slot
	current_data = data
	last_error = ""
	print("[SaveManager] 已保存至槽位 %d（%s）" % [slot, path])
	EventBus.game_saved.emit(slot, true, "")
	EventBus.save_slots_changed.emit()
	return true


## 保存当前已加载的存档（未加载任何槽位时失败）
func save_current() -> bool:
	if current_slot < 0 or current_data == null:
		last_error = "尚未加载任何存档槽，无法保存"
		push_warning("[SaveManager] " + last_error)
		return false
	return save_to_slot(current_slot, current_data)


## 自动存档（若启用且有当前槽）
func autosave() -> void:
	if autosave_enabled and current_slot >= 0 and current_data != null:
		save_current()


# =============================================================================
# 读取
# =============================================================================

## 从指定槽位读取。成功返回 SaveData，失败返回 null（详细原因见 `last_error`）。
##
## 读取顺序：主档 → bak1 → bak2 → bak3。
## 主档损坏时自动回滚到最新可用备份，并发出 `save_corrupted_recovered` 信号。
func load_from_slot(slot: int) -> SaveData:
	if slot < 0 or slot >= GameConstants.SAVE_MAX_SLOTS:
		last_error = "槽位号越界：%d" % slot
		EventBus.game_loaded.emit(slot, false, last_error)
		return null

	# 1) 先试主档
	var main_path := _slot_path(slot)
	var main_result := _try_load_file(main_path)

	if main_result.get("ok", false):
		var data: SaveData = main_result["data"]
		current_slot = slot
		current_data = data
		last_error = ""
		EventBus.game_loaded.emit(slot, true, "")
		return data

	# 2) 主档不存在且没有备份 → 直接判定为空槽
	var first_error := String(main_result.get("error", ""))

	# 3) 主档损坏：隔离它，然后按新→旧试备份
	if _file_exists(main_path):
		_quarantine_corrupt_file(main_path)

	for i in range(1, BACKUP_COUNT + 1):
		var bak_path := _backup_path(slot, i)
		var bak_result := _try_load_file(bak_path)
		if bak_result.get("ok", false):
			var data: SaveData = bak_result["data"]
			current_slot = slot
			current_data = data
			last_error = ""
			push_warning("[SaveManager] 槽位 %d 主档不可用，已回滚到备份 %d" % [slot, i])

			# 立刻把恢复出来的数据写回主档。
			# 不写回的话：主档已被隔离、只剩备份，而 `slot_exists()` / `get_slot_info()`
			# 只看主档，于是选档界面会把槽位显示成「空档」——玩家会以为存档丢了。
			# 恢复必须让槽位重新自洽，否则只算恢复了一半。
			# 此时主档不存在，`_rotate_backups()` 会直接返回，不会破坏现存备份。
			if not save_to_slot(slot, data):
				push_warning("[SaveManager] 槽位 %d 已在内存中恢复，但回写主档失败；"
					% slot + "下次启动仍会走备份回滚流程")

			EventBus.save_corrupted_recovered.emit(slot, i)
			EventBus.game_loaded.emit(slot, true, "")
			return data

	last_error = "槽位 %d 读取失败：%s" % [slot, first_error]
	push_error("[SaveManager] " + last_error)
	EventBus.game_loaded.emit(slot, false, last_error)
	return null


## 读取并回填 Resource 引用（底材模板、词缀模板）。
## 业务侧应优先调用本方法而非 `load_from_slot`，否则装备的 template 为空。
func load_from_slot_resolved(slot: int) -> SaveData:
	var data := load_from_slot(slot)
	if data == null:
		return null
	ConfigLoader.resolve_instances(data.inventory)
	ConfigLoader.resolve_instances(data.stash)
	ConfigLoader.resolve_instances(data.equipped)
	return data


## 新建一个空存档并写入指定槽位
## `class_id`（2026-09-22 步骤 2）：角色选择页传入职业；缺省 = 战士（兼容旧调用）
func create_new_slot(slot: int, class_id: String = GameConstants.CLASS_DEFAULT) -> SaveData:
	var data := SaveData.create_new(slot, class_id)
	if not save_to_slot(slot, data):
		return null
	return data


# =============================================================================
# 账号概览（UI 用）
# =============================================================================

## 取当前账号的概览数据（供主菜单 / 据点显示）。
##
## 返回键（**UI 侧契约，改名要同步 MainMenuPanel / HubScene**）：
##   level         int    账号等级（无档时为 1）
##   xp            float  当前等级内已累积经验
##   xp_next       float  升到下一级所需经验（AccountLevel.xp_to_next）
##   gold          int    金币
##   materials     int    魔石数量（= materials["magic_stone"]，供 UI 直接显示）
##   chapter_bonus float  章节声望加成（0.10 = +10%，UI 自己 ×100）
##   cleared_count int    已通关关卡数
##
## 无存档时返回全 0 的安全默认值，绝不返回 null —— UI 不必判空。
func get_account_data() -> Dictionary:
	var out := {
		"level": 1,
		"xp": 0.0,
		"xp_next": AccountLevel.xp_to_next(1),
		"gold": 0,
		"materials": 0,
		"chapter_bonus": 0.0,
		"cleared_count": 0,
	}
	if current_data == null:
		return out

	out["level"] = current_data.account_level
	out["xp"] = current_data.account_xp
	out["xp_next"] = AccountLevel.xp_to_next(current_data.account_level)
	out["gold"] = current_data.gold
	out["materials"] = current_data.get_material(MATERIAL_KEY_MAGIC_STONE)
	out["chapter_bonus"] = float(_chapter_reputation_total(current_data)) / 100.0
	out["cleared_count"] = current_data.cleared_levels.size()
	return out


## 各章节声望等级之和（每级 +1% 经验 / 金币，见 ChapterReputation.get_bonus）。
## 逐章夹紧到 [0, MAX_REP_LEVEL]，避免脏档把加成算成天文数字。
func _chapter_reputation_total(data: SaveData) -> int:
	var total := 0
	for chapter in data.chapter_reputation:
		total += clampi(int(data.chapter_reputation[chapter]), 0, ChapterReputation.MAX_REP_LEVEL)
	return total


# =============================================================================
# 备份与原子写入
# =============================================================================

## 轮转备份：bak(N-1) → bakN，主档 → bak1。
## 从最高序号开始处理，避免覆盖。
func _rotate_backups(slot: int) -> void:
	var main_path := _slot_path(slot)
	if not _file_exists(main_path):
		return # 首次保存，无需备份

	# 删除最旧的备份，腾出位置
	var oldest := _backup_path(slot, BACKUP_COUNT)
	if _file_exists(oldest):
		_remove_file(oldest)

	# 依次后移：bak(N-1) → bakN ... bak1 → bak2
	for i in range(BACKUP_COUNT - 1, 0, -1):
		var src := _backup_path(slot, i)
		var dst := _backup_path(slot, i + 1)
		if _file_exists(src):
			_move_file(src, dst)

	# 主档 → bak1
	_move_file(main_path, _backup_path(slot, 1))


## 原子写入：先写 .tmp，再替换目标。失败时清理 .tmp。
func _atomic_write(path: String, text: String) -> bool:
	var tmp_path := path + ".tmp"

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] 无法写入临时文件 '%s'（错误码 %d）"
			% [tmp_path, FileAccess.get_open_error()])
		return false

	file.store_string(text)
	file.flush()
	file.close()

	# 校验临时文件确实写完整
	if not _file_exists(tmp_path) or _file_size(tmp_path) <= 0:
		push_error("[SaveManager] 临时文件写入不完整：%s" % tmp_path)
		_remove_file(tmp_path)
		return false

	# 替换目标（Windows 下 rename 不覆盖已存在文件，需先删）
	if _file_exists(path):
		if not _remove_file(path):
			push_error("[SaveManager] 无法移除旧存档 '%s'，写入中止" % path)
			_remove_file(tmp_path)
			return false

	if not _move_file(tmp_path, path):
		push_error("[SaveManager] 无法将临时文件重命名为 '%s'" % path)
		_remove_file(tmp_path)
		return false

	return true


## 读取并校验一个存档文件。返回 { ok: bool, data: SaveData, error: String }
func _try_load_file(path: String) -> Dictionary:
	if not _file_exists(path):
		return {"ok": false, "data": null, "error": "文件不存在"}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": null,
			"error": "无法打开文件（错误码 %d）" % FileAccess.get_open_error()}

	var text := file.get_as_text()
	file.close()

	if text.strip_edges().is_empty():
		return {"ok": false, "data": null, "error": "文件为空"}

	var envelope := _read_envelope_text(text, path)
	if not envelope.get("ok", false):
		return envelope

	var raw: Dictionary = envelope.get("data", {})
	var data := SaveData.from_dict(raw)

	if not data.migrate():
		return {"ok": false, "data": null,
			"error": "存档版本 %d 高于当前支持的 %d" % [data.save_version, GameConstants.SAVE_VERSION]}

	return {"ok": true, "data": data, "error": ""}


## 从文件读取并解包信封
func _read_envelope(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "error": "无法打开文件"}
	var text := file.get_as_text()
	file.close()
	return _read_envelope_text(text, path)


## 解包并校验信封文本。返回 { ok, data: Dictionary, error: String }
func _read_envelope_text(text: String, path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "data": {},
			"error": "JSON 解析失败（第 %d 行）：%s" % [json.get_error_line(), json.get_error_message()]}

	if not (json.data is Dictionary):
		return {"ok": false, "data": {}, "error": "存档顶层结构不是对象"}

	var envelope: Dictionary = json.data

	if String(envelope.get("magic", "")) != SAVE_MAGIC:
		return {"ok": false, "data": {}, "error": "文件头标识不匹配，可能不是本游戏存档"}

	if not envelope.has("payload"):
		return {"ok": false, "data": {}, "error": "存档缺少 payload 字段"}

	var payload := String(envelope["payload"])
	var expected := String(envelope.get("checksum", ""))

	if expected.is_empty():
		return {"ok": false, "data": {}, "error": "存档缺少校验和"}

	if payload.sha256_text() != expected:
		return {"ok": false, "data": {}, "error": "校验和不匹配，存档已损坏"}

	var payload_json := JSON.new()
	if payload_json.parse(payload) != OK:
		return {"ok": false, "data": {},
			"error": "payload 解析失败（第 %d 行）：%s" % [payload_json.get_error_line(), payload_json.get_error_message()]}

	if not (payload_json.data is Dictionary):
		return {"ok": false, "data": {}, "error": "payload 顶层结构不是对象"}

	return {"ok": true, "data": payload_json.data, "error": ""}


## 把损坏的主档改名隔离（保留现场，绝不删除）
func _quarantine_corrupt_file(path: String) -> void:
	var ts := int(Time.get_unix_time_from_system())
	var dir_path := path.get_base_dir()
	var base_name := path.get_file().get_basename()
	var quarantine := "%s/%s.corrupt_%d" % [dir_path, base_name, ts]
	if _move_file(path, quarantine):
		push_warning("[SaveManager] 损坏存档已隔离至：%s" % quarantine)
	else:
		push_warning("[SaveManager] 损坏存档隔离失败：%s" % path)


# =============================================================================
# 自动存档定时器
# =============================================================================

func _setup_autosave_timer() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.wait_time = autosave_interval
	_autosave_timer.one_shot = false
	_autosave_timer.autostart = false
	_autosave_timer.timeout.connect(autosave)
	add_child(_autosave_timer)


## 开关自动存档
func set_autosave_enabled(enabled: bool, interval: float = -1.0) -> void:
	autosave_enabled = enabled
	if interval > 0.0:
		autosave_interval = interval
	if _autosave_timer == null:
		return
	_autosave_timer.wait_time = autosave_interval
	if enabled and current_slot >= 0:
		_autosave_timer.start()
	else:
		_autosave_timer.stop()


# =============================================================================
# 路径与文件工具
# =============================================================================

func _slot_path(slot: int) -> String:
	return "%s/%s" % [save_dir, SLOT_FILE_FORMAT % slot]


func _backup_path(slot: int, index: int) -> String:
	return "%s.bak%d" % [_slot_path(slot), index]


## 某槽位的全部相关文件（主档 + 全部备份）
func _all_paths_for_slot(slot: int) -> Array[String]:
	var out: Array[String] = [_slot_path(slot)]
	for i in range(1, BACKUP_COUNT + 1):
		out.append(_backup_path(slot, i))
	return out


func _ensure_save_dir() -> void:
	if DirAccess.dir_exists_absolute(save_dir):
		return
	var err := DirAccess.make_dir_recursive_absolute(save_dir)
	if err != OK:
		push_error("[SaveManager] 无法创建存档目录 '%s'（错误码 %d）" % [save_dir, err])
	else:
		print("[SaveManager] 已创建存档目录：%s（实际路径 %s）"
			% [save_dir, ProjectSettings.globalize_path(save_dir)])


func _file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size


func _remove_file(path: String) -> bool:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	return dir.remove(path.get_file()) == OK


func _move_file(from_path: String, to_path: String) -> bool:
	var dir := DirAccess.open(from_path.get_base_dir())
	if dir == null:
		return false
	return dir.rename(from_path.get_file(), to_path.get_file()) == OK
