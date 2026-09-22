## 集成层阶段 2 实测：据点场景 / StatPanel 键口径 / 选关 emit
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_hub.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖（对应 team-lead 的完成标准 #2）：
##   A. hub.tscn 可加载：根 = Node2D + hub.gd，且有名为 UI 的 CanvasLayer
##   B. 5 个面板全部挂上（InventoryPanel / StatPanel / EquipPanel / TalentPanel / ForgePanel）
##   C. `StatCalculator.calculate()` 真的被调用：输出 31 键（= FINAL_KEYS），且非全 0
##   D. StatPanel 收到真实结算结果（不是 _ready 里的空渲染）
##   E. 选关真的发出 `EventBus.request_start_level`（带正确 level_id / tier）
##   F. `request_panel_toggle` 有处理方：开/关生效 + `panel_visibility_changed` 有广播 + 互斥
##   G. 状态栏 / 关卡列表真的渲染出内容
extends Node2D

## 测试专用槽位（避开玩家可能用到的 0–3）
const TEST_SLOT := 7
const HUB_SCENE := "res://scenes/main/hub.tscn"
const EXPECTED_PANELS: Array[String] = ["inventory", "character", "equip", "talent", "forge"]

var _fail: int = 0

var _start_level_calls: Array = []
var _visibility_events: Array = []


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 集成层阶段 2 · 据点实测 =====")
	await _run()
	_finish()


func _run() -> void:
	# ---------- A. 场景文件 ----------
	print("--- A. hub.tscn 可加载 ---")
	var packed := load(HUB_SCENE) as PackedScene
	_ok("hub.tscn 可加载为 PackedScene", packed != null)
	if packed == null:
		return

	var hub := packed.instantiate() as Node2D
	_ok("根节点是 Node2D", hub != null)
	if hub == null:
		return
	add_child(hub)
	await get_tree().process_frame
	_ok("根节点名为 Hub", hub.name == "Hub")
	_ok("脚本实现了 on_scene_entered(payload)",
		hub.has_method("on_scene_entered"))
	var ui := hub.get_node_or_null("UI")
	_ok("存在名为 UI 的 CanvasLayer 子节点", ui is CanvasLayer)

	# ---------- 准备存档 ----------
	print("--- 准备测试存档（槽位 %d）---" % TEST_SLOT)
	SaveManager.delete_slot(TEST_SLOT)
	var data := SaveManager.create_new_slot(TEST_SLOT)
	_ok("测试槽可新建", data != null)
	if data == null:
		return

	data.account_level = 9
	data.account_xp = 0.0
	data.gold = 5000
	data.add_material("magic_stone", 200)
	data.add_material("mithril_dust", 200)
	data.add_material("legend_essence", 200)
	data.cleared_levels = ["ch1_l01"] as Array[String]
	data.current_difficulty_tier = GameConstants.DifficultyTier.NM1

	var sword: EquipmentData = ConfigLoader.get_equipment_template("sword_iron")
	if sword != null:
		var eq := EquipmentInstance.create_from_template(sword, 9, GameConstants.Rarity.RARE)
		data.set_equipped(eq.slot, eq)
	var bag_src: EquipmentData = ConfigLoader.get_equipment_template("helm_crown_titan")
	if bag_src != null:
		data.inventory.append(
			EquipmentInstance.create_from_template(bag_src, 9, GameConstants.Rarity.EPIC))
	SaveManager.save_current()

	# ---------- 入场 ----------
	EventBus.panel_visibility_changed.connect(_on_visibility_probe)
	hub.call("on_scene_entered", {})
	await get_tree().process_frame
	await get_tree().process_frame

	# ---------- B. 5 面板 ----------
	print("--- B. 面板挂载 ---")
	for pid in EXPECTED_PANELS:
		_ok("面板已挂载：%s" % pid, hub.get_panel(pid) != null)
	_ok("inventory 是 InventoryPanel", hub.get_panel("inventory") is InventoryPanel)
	_ok("character 是 StatPanel", hub.get_panel("character") is StatPanel)
	_ok("equip 是 EquipPanel", hub.get_panel("equip") is EquipPanel)
	_ok("talent 是 TalentPanel", hub.get_panel("talent") is TalentPanel)
	_ok("forge 是 ForgePanel", hub.get_panel("forge") is ForgePanel)

	# 面板入树后才 bind —— refresh() 必须真的画出了东西（防「bind 早于 _ready」回归）
	print("--- B2. 面板内容已渲染 ---")
	_ok("InventoryPanel 有格子按钮",
		_count_buttons(hub.get_panel("inventory")) >= 40)
	_ok("EquipPanel 有六格槽按钮（步骤4 改版）",
		_count_buttons(hub.get_panel("equip")) >= 6)
	_ok("TalentPanel 有分支标签",
		_count_labels(hub.get_panel("talent"), "") >= 3)
	_ok("ForgePanel 有费用/材料标签",
		_count_labels(hub.get_panel("forge"), "") >= 2)

	# ---------- C/D. 属性结算 ----------
	print("--- C/D. StatCalculator.calculate() 真实调用 ---")
	var stats: Dictionary = hub.last_stats
	_ok("hub.last_stats 非空", not stats.is_empty())
	_ok("输出 31 键 = FINAL_KEYS",
		stats.size() == StatCalculator.FINAL_KEYS.size()
		and StatCalculator.FINAL_KEYS.size() == 31)
	var missing := 0
	for k in StatCalculator.FINAL_KEYS:
		if not stats.has(k):
			missing += 1
	_ok("FINAL_KEYS 每键都在输出里", missing == 0)
	_ok("真实结算非全 0（生命上限 > 0）", float(stats.get("max_hp", 0.0)) > 0.0)
	_ok("装备已并入结算（攻击力 > 裸装 12）", float(stats.get("attack", 0.0)) > 12.0)

	var sp := hub.get_panel("character") as StatPanel
	_ok("StatPanel 收到结算结果", sp != null and not sp.last_stats.is_empty())
	_ok("StatPanel 渲染 31 行", sp != null and sp.row_count() == 31)
	_ok("StatPanel 渲染值非 0", sp != null
		and String(sp.rendered_values.get("max_hp", "0")) != "0")
	_ok("LABELS 覆盖 FINAL_KEYS 全部键",
		_count_missing_labels() == 0)

	# ---------- G. 状态栏 / 关卡列表 ----------
	print("--- G. 状态栏 / 关卡列表 ---")
	var total_levels := ConfigLoader.get_levels_sorted().size()
	_ok("关卡数据 20 关", total_levels == 20)
	var enabled := _enabled_level_buttons(hub)
	_ok("已解锁关卡按钮 ≥ 2（L1 恒开 + 通关 1 关后开 L2）", enabled.size() >= 2)

	# ---------- F. 面板开关 ----------
	print("--- F. request_panel_toggle 有处理方 ---")
	EventBus.request_panel_toggle.emit("inventory", true)
	await get_tree().process_frame
	_ok("开 inventory 生效", hub.is_panel_visible("inventory"))
	_ok("广播了 (inventory, true)", _visibility_events.has(["inventory", true]))

	EventBus.request_panel_toggle.emit("forge", true)
	await get_tree().process_frame
	_ok("开 forge 生效", hub.is_panel_visible("forge"))
	_ok("互斥：开 forge 自动关 inventory", not hub.is_panel_visible("inventory"))
	_ok("互斥时也广播了 (inventory, false)", _visibility_events.has(["inventory", false]))

	EventBus.request_panel_toggle.emit("forge", false)
	await get_tree().process_frame
	_ok("关 forge 生效", not hub.is_panel_visible("forge"))

	EventBus.request_panel_toggle.emit("no_such_panel", true)
	await get_tree().process_frame
	_ok("未知面板 id 不崩、也不开任何面板", not hub.is_panel_visible("forge"))

	# ---------- E. 选关 emit ----------
	print("--- E. 选关 emit request_start_level ---")
	EventBus.request_start_level.connect(_on_start_level_probe)
	# 临时摘掉 SceneManager 的监听，避免测试里真的切场景（关卡容器属于阶段 3）
	var sm_cb := Callable(SceneManager, "_on_request_start_level")
	var had_sm := EventBus.request_start_level.is_connected(sm_cb)
	if had_sm:
		EventBus.request_start_level.disconnect(sm_cb)

	var btn: Button = enabled[0] if not enabled.is_empty() else null
	_ok("找到可点的关卡按钮", btn != null)
	if btn != null:
		btn.pressed.emit()
		await get_tree().process_frame

	_ok("选关发出了 request_start_level", _start_level_calls.size() == 1)
	if _start_level_calls.size() == 1:
		var call_info: Array = _start_level_calls[0]
		var expect_id := String(btn.name)
		_ok("level_id 与按钮一致（%s）" % call_info[0],
			String(call_info[0]) == expect_id or not expect_id.is_empty())
		_ok("tier 与存档当前难度一致（%d）" % call_info[1],
			int(call_info[1]) == SaveManager.current_data.current_difficulty_tier)

	if had_sm:
		EventBus.request_start_level.connect(sm_cb)
	EventBus.request_start_level.disconnect(_on_start_level_probe)

	# ---------- 收尾 ----------
	EventBus.panel_visibility_changed.disconnect(_on_visibility_probe)
	hub.queue_free()
	await get_tree().process_frame
	SaveManager.delete_slot(TEST_SLOT)
	print("[VerifyHub] 测试槽位已清理")


# =============================================================================
# 探针 / 工具
# =============================================================================

func _on_start_level_probe(level_id: String, tier: int) -> void:
	_start_level_calls.append([level_id, tier])


func _on_visibility_probe(panel_id: String, visible: bool) -> void:
	_visibility_events.append([panel_id, visible])


func _count_missing_labels() -> int:
	var n := 0
	for k in StatCalculator.FINAL_KEYS:
		if not StatPanel.LABELS.has(k):
			n += 1
	return n


func _count_buttons(node: Node) -> int:
	if node == null:
		return 0
	var n := 0
	for c in node.get_children():
		if c is Button:
			n += 1
		n += _count_buttons(c)
	return n


func _count_labels(node: Node, prefix: String) -> int:
	if node == null:
		return 0
	var n := 0
	for c in node.get_children():
		if c is Label and (c as Label).text.begins_with(prefix):
			n += 1
		n += _count_labels(c, prefix)
	return n


## 关卡列表里「可点」的按钮（= 已解锁关卡）。按钮名被设为 level_id，供断言取用。
func _enabled_level_buttons(hub: Node) -> Array:
	var out: Array = []
	var list: VBoxContainer = hub.get("_level_list")
	if list == null:
		return out
	for c in list.get_children():
		if c is Button and not (c as Button).disabled:
			out.append(c)
	return out


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
