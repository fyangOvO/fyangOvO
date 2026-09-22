## ESC「放弃本局」逃生口实测（2026-09-18 · 阶段 11 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_esc.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 背景：关卡内此前**没有任何退出路径**（全文件零 `_input` / `KEY_ESCAPE`），玩家唯一出路是
##   Alt+F4，而 Alt+F4 绕过 `_persist()` ⇒ 已入包装备**静默丢失**。本脚本验证新加的
##   ESC → 二次确认 → `_finish_run(false)` 这条逃生口，重点是「确认后装备**真的落盘**」。
##
## 覆盖：
##   A. 弹出：ESC 真的弹出二次确认（入口方法 + 两条输入通路：ui_cancel / 裸 Escape 键）
##   B. 取消：点「继续」→ 不结算、不切场景、存档不变
##   C. 三选一面板显示中：ESC 被吞，不放弃、不结算（防误触丢升级收益）
##   D. 确认：走 `_finish_run(false)` → 结算面板显示 → `_persist()` 执行 →
##            已入包装备**在内存与磁盘存档里都还在**（这才是本逃生口的根本目的）
##   E. 结算后：ESC 不再弹确认（本局已结束）
##
## ⚠️ 测试期唯一改动：把玩家血量顶到极大，避免被怪围殴致死提前触发死亡结算
##    （与被验证的 ESC 逻辑无关）。
extends Node

const LEVEL_ID: String = "ch1_l01"
const SLOT: int = 7
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")

var _fail: int = 0
var _level: LevelScene = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死
	VerifyWatchdog.arm(get_tree())
	_run()


func _run() -> void:
	print("===== ESC「放弃本局」逃生口实测 =====")

	# 独立存档槽（回归默认隔离 APPDATA，这里再显式占一个不常用的槽）
	if SaveManager.slot_exists(SLOT):
		SaveManager.delete_slot(SLOT)
	var data := SaveManager.create_new_slot(SLOT)
	_ok("测试存档就绪（槽 %d / current_data=%s）" % [SLOT, str(data != null)],
		data != null and SaveManager.current_data != null)
	if data == null:
		_finish()
		return

	await _spawn_level()

	# --- A. 弹出 ---
	print("--- A. ESC 弹出二次确认 ---")
	_level._on_escape_pressed()
	await _wait_frames(1)
	_ok("按 ESC 后弹出确认弹窗", _abandon_valid())
	_ok("弹窗含「放弃本局？」标题",
		_count_labels_containing(_level._abandon_confirm, "放弃本局") >= 1)
	_ok("弹窗有「继续」与「确认放弃」两个按钮",
		_find_button(_level._abandon_confirm, "继续") != null
		and _find_button(_level._abandon_confirm, "确认放弃") != null)

	# 输入通路①：InputEventAction("ui_cancel")（内置动作默认绑 Escape）
	_level._dismiss_abandon_confirm()
	var act := InputEventAction.new()
	act.action = "ui_cancel"
	act.pressed = true
	_level._unhandled_input(act)
	await _wait_frames(1)
	_ok("经 _unhandled_input(ui_cancel) 也能弹出", _abandon_valid())

	# 输入通路②：裸 Escape 键（防将来 InputMap 被 InputRemapper 覆写后失效）
	_level._dismiss_abandon_confirm()
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	_level._unhandled_input(key)
	await _wait_frames(1)
	_ok("经裸 Escape 键也能弹出", _abandon_valid())

	# --- B. 取消 ---
	print("--- B. 取消：不结算 / 不切场景 / 存档不变 ---")
	_level._dismiss_abandon_confirm()
	_level._on_escape_pressed()
	await _wait_frames(1)
	var scene_before := get_tree().current_scene
	var gold_before := SaveManager.current_data.gold
	var kills_before := int(SaveManager.current_data.statistics.get("monsters_killed", 0))
	var inv_before_cancel := SaveManager.current_data.inventory.size()
	var cancel_btn := _find_button(_level._abandon_confirm, "继续")
	cancel_btn.pressed.emit()
	await _wait_frames(2)
	_ok("点「继续」后弹窗消失（_abandon_confirm 置空）", _level._abandon_confirm == null)
	_ok("点「继续」后未结算（_finished=false）", _level._finished == false)
	_ok("点「继续」后结算面板未显示", _level._result_panel.visible == false)
	_ok("点「继续」后未切场景", get_tree().current_scene == scene_before)
	_ok("点「继续」后存档未被改动（金币 %d / 击杀 %d / 背包 %d）"
			% [gold_before, kills_before, inv_before_cancel],
		SaveManager.current_data.gold == gold_before
		and int(SaveManager.current_data.statistics.get("monsters_killed", 0)) == kills_before
		and SaveManager.current_data.inventory.size() == inv_before_cancel)

	# --- C. 三选一面板显示中 ---
	print("--- C. 三选一面板显示中：ESC 被吞 ---")
	var choices := RunePool.get_choices(3, [], {}, _level._choice_rng)
	_level._show_choice_panel(choices)
	await _wait_frames(2)
	_ok("三选一面板已弹出且可见",
		_level._choice_panel != null and is_instance_valid(_level._choice_panel)
		and _level._choice_panel.visible)
	_level._on_escape_pressed()
	await _wait_frames(1)
	_ok("面板显示中按 ESC **不**弹放弃确认", _level._abandon_confirm == null)
	_ok("面板显示中按 ESC **不**结算", _level._finished == false)
	# 收面板：连续升级时会被替换；这里直接清掉，避免遮挡后续操作
	if _level._choice_panel != null and is_instance_valid(_level._choice_panel):
		_level._choice_panel.visible = false

	# --- D. 确认放弃：失败结算 + 落盘（核心）---
	print("--- D. 确认放弃：走失败结算 + 装备落盘 ---")
	# 注入一件「本局已入包」装备（模拟玩家在关卡里捡到的战利品）
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	_ok("装备模板存在（sword_iron）", tpl != null)
	if tpl == null:
		_finish()
		return
	var inst := EquipmentInstance.create_from_template(tpl, 5, GameConstants.Rarity.RARE)
	var injected_id := inst.instance_id
	_level._player.inventory.append({
		"item_id": "sword_iron", "item_level": 5,
		"rarity": GameConstants.Rarity.RARE, "instance": inst.to_dict(),
	})
	var inv_before_confirm := SaveManager.current_data.inventory.size()

	# 探针：确认 level_failed 的 reason 是 "abandoned"（而非 "hp_depleted"）
	var failed_reasons: Array = []
	var probe := func(_lid: String, reason: String) -> void: failed_reasons.append(reason)
	EventBus.level_failed.connect(probe)

	_level._on_escape_pressed()
	await _wait_frames(1)
	var ok_btn := _find_button(_level._abandon_confirm, "确认放弃")
	_ok("确认弹窗有「确认放弃」按钮", ok_btn != null)
	ok_btn.pressed.emit()
	await _wait_frames(3)
	EventBus.level_failed.disconnect(probe)

	_ok("确认后已结算（_finished=true）", _level._finished == true)
	_ok("确认后弹出结算面板", _level._result_panel.visible == true)
	_ok("确认后弹窗已收起", _level._abandon_confirm == null)
	_ok("失败横幅 = 「已放弃本局」（实际：%s）" % _level._banner.text,
		_level._banner.text == "已放弃本局")
	_ok("level_failed reason = abandoned（实际：%s）" % str(failed_reasons),
		failed_reasons.has("abandoned") and not failed_reasons.has("hp_depleted"))

	# 核心断言：装备在**内存存档**里
	var mem_ids := _instance_ids(SaveManager.current_data.inventory)
	_ok("已入包装备在内存存档里（injected=%s / 存档 %d 件 / 之前 %d 件）"
			% [injected_id, mem_ids.size(), inv_before_confirm],
		mem_ids.has(injected_id)
		and SaveManager.current_data.inventory.size() == inv_before_confirm + 1)

	# 核心断言：装备在**磁盘存档**里（证明 `_persist()` 真的写了，而不是只改内存对象）
	var reloaded := SaveManager.load_from_slot(SLOT)
	var disk_ids := _instance_ids(reloaded.inventory if reloaded != null else [])
	_ok("重新读档后装备仍在磁盘（%d 件）" % disk_ids.size(), disk_ids.has(injected_id))

	# --- E. 结算后 ESC ---
	print("--- E. 结算后：ESC 不再弹确认 ---")
	_level._on_escape_pressed()
	await _wait_frames(1)
	_ok("结算面板显示中按 ESC 不弹放弃确认", _level._abandon_confirm == null)

	# 清理
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		await _wait_frames(1)
	if SaveManager.slot_exists(SLOT):
		SaveManager.delete_slot(SLOT)
	_finish()


# =============================================================================
# 工具
# =============================================================================

## 进关（复用真实入场契约 `on_scene_entered`），并把玩家血量顶到极大
func _spawn_level() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		await get_tree().process_frame
	_level = LEVEL_SCENE.instantiate() as LevelScene
	# ⚠️ 必须 call_deferred：`_ready()` 期间 root 正在 setup children，
	#    直接 add_child 会报 "Parent node is busy setting up children" 并**静默失败**。
	get_tree().root.add_child.call_deferred(_level)
	await _wait_frames(2)
	_level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _wait_frames(3)
	if _level._player != null and _level._player.health != null:
		# 顶血：本测试不打怪，但怪会一直攻击玩家（见文件头说明）
		_level._player.health.max_hp_override = 1.0e9
		_level._player.health.current_hp = 1.0e9


func _abandon_valid() -> bool:
	return _level._abandon_confirm != null and is_instance_valid(_level._abandon_confirm)


func _instance_ids(items: Array) -> Array:
	var out: Array = []
	for it in items:
		if it is EquipmentInstance:
			out.append((it as EquipmentInstance).instance_id)
	return out


func _count_labels_containing(root: Node, needle: String) -> int:
	if root == null:
		return 0
	var n := 0
	for c in root.get_children():
		if c is Label and String((c as Label).text).contains(needle):
			n += 1
		n += _count_labels_containing(c, needle)
	return n


func _find_button(root: Node, needle: String) -> Button:
	if root == null:
		return null
	for c in root.get_children():
		if c is Button and String((c as Button).text).contains(needle):
			return c as Button
		var r := _find_button(c, needle)
		if r != null:
			return r
	return null


func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
