## 据点场景（集成层阶段 2 · 任务 7.x 面板族的真实挂载点）
##
## 结构：
##   Node2D      世界层（当前是空壳 —— 据点是纯 UI 场景，阶段 3 的关卡才需要地图/玩家）
##   └ CanvasLayer "UI"   标题 / 状态栏 / 面板按钮 / 关卡列表 / 面板浮层 / 提示条
##
## 数据源：`SaveManager.current_data`（进据点前，主菜单已用 `create_new_slot()` 或
## `load_from_slot_resolved()` 备好；本场景不负责建/读档，只负责用与回写）。
##
## 入场：由 `SceneManager._deliver_payload()` 回调 `on_scene_entered(payload)` 触发
## （payload 恒为空字典；进关卡才有 level_id）。直接实例化本场景不会自动装配数据。
##
## 接线纪律（每个 emit 都有人在听）：
##   emit request_start_level      → SceneManager._on_request_start_level 接住并切关卡
##   emit request_panel_toggle     ← 由本场景的输入/按钮发出，也由本场景处理（全项目唯一处理方）
##   emit panel_visibility_changed → 本场景自己消费（输入屏蔽）+ 验证脚本
##   emit equipment_changed        → 本场景自己消费（刷新装备/背包面板 + 重算属性）
##   emit stats_recalculated       → 本场景自己消费（把结算结果推给 StatPanel）
##   emit notification_requested   → 由 EventBus.notify() 发出，本场景消费为提示条
extends Node2D

## 面板 id（`EventBus.request_panel_toggle` 的 panel_id 口径）
const PANEL_INVENTORY := "inventory"
const PANEL_CHARACTER := "character"
const PANEL_EQUIP := "equip"
const PANEL_TALENT := "talent"
const PANEL_FORGE := "forge"
const PANEL_SKILLS := "skills"

const PANEL_IDS: Array[String] = [
	PANEL_INVENTORY, PANEL_CHARACTER, PANEL_EQUIP, PANEL_TALENT, PANEL_FORGE, PANEL_SKILLS,
]
const PANEL_TITLES := {
	PANEL_INVENTORY: "背包 / 仓库",
	PANEL_CHARACTER: "角色属性",
	PANEL_EQUIP: "装备栏",
	PANEL_TALENT: "天赋树",
	PANEL_FORGE: "锻造台",
	PANEL_SKILLS: "技能",
}

## 背包 / 仓库网格（工程侧默认，见 Inventory 头注释）
const INV_COLS := 8
const INV_ROWS := 5
const STASH_COLS := 8
const STASH_ROWS := 10

## 经济层（ForgeController / MaterialBag）→ 存档层（SaveData.materials）的材料键桥接。
##
## ⚠️ 这两套词表目前**不一致**：存档只有 magic_stone / mithril_dust / legend_essence，
## 而锻造/分解/商店用的是 stone(s) / dust / essence / crystal。这里做显式映射；
## 映射不到的键（crystal = 神话结晶）在存档里没有落点，成本含它时会明确拒绝并提示。
const MATERIAL_KEY_MAP := {
	"stone": "magic_stone",
	"stones": "magic_stone",
	"dust": "mithril_dust",
	"essence": "legend_essence",
}

@onready var _ui_layer: CanvasLayer = $UI

var _level_list: VBoxContainer = null
var _status: Label = null
var _toast: Label = null

## panel_id → 浮层容器（Control，负责 show/hide）
var _holders: Dictionary = {}
## panel_id → 真面板节点（InventoryPanel / StatPanel / ...）
var _panels: Dictionary = {}

var _inv: Inventory = null
var _stash: Inventory = null

## 装备对比浮窗（懒建，置顶）
var _compare_holder: Control = null
var _compare_popup: EquipComparePopup = null

## 最近一次 `StatCalculator.calculate()` 的输出（据点口径：无局内 Buff）
var last_stats: Dictionary = {}

var _entered: bool = false


func _ready() -> void:
	_build_ui()
	EventBus.request_panel_toggle.connect(_on_request_panel_toggle)
	EventBus.panel_visibility_changed.connect(_on_panel_visibility_changed)
	EventBus.equipment_changed.connect(_on_equipment_changed)
	EventBus.stats_recalculated.connect(_on_stats_recalculated)
	EventBus.notification_requested.connect(_on_notification)


## 接收 SceneManager 递过来的载荷（据点恒为空；进关卡才带 level_id）
func on_scene_entered(payload: Dictionary) -> void:
	if _entered:
		return
	_entered = true
	if not payload.is_empty():
		print("[Hub] 收到载荷：", payload)
	_enter()


func _enter() -> void:
	var data := SaveManager.current_data
	if data == null and SaveManager.current_slot >= 0:
		data = SaveManager.load_from_slot_resolved(SaveManager.current_slot)
	if data == null:
		push_warning("[Hub] 没有可用存档，退回主菜单")
		SceneManager.change_scene(SceneManager.SCENE_MAIN_MENU)
		return

	_build_inventories(data)
	for pid in PANEL_IDS:
		_ensure_panel(pid)
	_refresh_status(data)
	_refresh_levels(data)
	_recalculate_stats(data)
	print("[Hub] 据点就绪：账号 Lv.%d · 已解锁关卡 %d/%d" % [
		data.account_level, _unlocked_level_count(data),
		ConfigLoader.get_levels_sorted().size()])


# =============================================================================
# 数据装配
# =============================================================================

## SaveData 存的是「扁平装备数组」，Inventory 是「网格对象」——这里做一次桥接
func _build_inventories(data: SaveData) -> void:
	_inv = Inventory.create(INV_COLS, INV_ROWS)
	for it in data.inventory:
		if it != null:
			_inv.add(it)
	_stash = Inventory.create(STASH_COLS, STASH_ROWS)
	for it in data.stash:
		if it != null:
			_stash.add(it)


## 网格 → 扁平数组（回写存档用）
func _write_back(inv: Inventory, into: Array) -> void:
	if inv == null:
		return
	into.clear()
	for s in inv.slots:
		if s != null:
			into.append(s)


## 落盘 + 刷新状态栏。所有会改存档的操作都走这里
func _sync_and_save(data: SaveData) -> void:
	_write_back(_inv, data.inventory)
	_write_back(_stash, data.stash)
	SaveManager.save_current()
	_refresh_status(data)


## 背包里的物品（锻造列表 / 装备搬运共用同一来源）
func _inventory_items() -> Array:
	var out: Array = []
	if _inv == null:
		return out
	for s in _inv.slots:
		if s != null:
			out.append(s)
	return out


func _unlocked_level_count(data: SaveData) -> int:
	var n := 0
	var cleared := data.cleared_levels.size()
	for lv in ConfigLoader.get_levels_sorted():
		if UnlockSystem.is_level_unlocked(lv.level, cleared):
			n += 1
	return n


# =============================================================================
# 状态栏 / 关卡列表
# =============================================================================

func _refresh_status(data: SaveData) -> void:
	if _status == null:
		return
	_status.text = "账号 Lv.%d　金币 %d　魔石 %d　已通关 %d/%d　难度 %s" % [
		data.account_level,
		data.gold,
		data.get_material("magic_stone"),
		data.cleared_levels.size(),
		ConfigLoader.get_levels_sorted().size(),
		_difficulty_name(data.current_difficulty_tier),
	]


func _difficulty_name(tier: int) -> String:
	var names := GameConstants.DIFFICULTY_TIER_NAMES
	if tier < 0 or tier >= names.size():
		return "?"
	return String(names[tier])


func _refresh_levels(data: SaveData) -> void:
	if _level_list == null:
		return
	for c in _level_list.get_children():
		c.queue_free()

	var cleared := data.cleared_levels.size()
	var chapter := -1
	for lv in ConfigLoader.get_levels_sorted():
		if lv.chapter != chapter:
			chapter = lv.chapter
			var head := Label.new()
			head.text = "── 第 %d 章 ──" % chapter
			head.add_theme_font_size_override("font_size", 12)
			head.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[4])
			_level_list.add_child(head)

		var unlocked := UnlockSystem.is_level_unlocked(lv.level, cleared)
		var done := data.cleared_levels.has(lv.id)
		var btn := Button.new()
		btn.name = lv.id # 供验证脚本/自动化按关卡 id 取按钮
		btn.text = "%s　%s%s" % [lv.id, lv.display_name, "　✔已通关" if done else ""]
		btn.custom_minimum_size = Vector2(320, 32)
		btn.add_theme_font_size_override("font_size", 12)
		btn.disabled = not unlocked
		btn.tooltip_text = "推荐等级 %d%s" % [
			lv.recommended_player_level, "" if unlocked else "（未解锁：需先通关上一关）"]
		btn.pressed.connect(_on_level_picked.bind(lv.id))
		AudioManager.hook_click(btn)
		_level_list.add_child(btn)


## 选关 —— **全项目唯一的 `request_start_level` emit 点**。
## SceneManager 接住后按 `LevelData.scene_path` 切到关卡场景（阶段 3）。
func _on_level_picked(level_id: String) -> void:
	var tier := _current_tier()
	print("[Hub] 选关：%s（难度 %s）" % [level_id, _difficulty_name(tier)])
	EventBus.request_start_level.emit(level_id, tier)


func _current_tier() -> int:
	var data := SaveManager.current_data
	if data == null:
		return GameConstants.DifficultyTier.NM1
	return data.current_difficulty_tier


# =============================================================================
# 面板开关
# =============================================================================

func _on_request_panel_toggle(panel_id: String, visible: bool) -> void:
	if not _ensure_panel(panel_id):
		_toast_msg("未知面板：%s" % panel_id)
		return
	# 同时只开一个：先把别的关掉（关掉也要广播，否则输入屏蔽会卡住）
	if visible:
		for pid in _holders:
			if pid != panel_id and _holders[pid].visible:
				_holders[pid].visible = false
				EventBus.panel_visibility_changed.emit(pid, false)
	_holders[panel_id].visible = visible
	EventBus.panel_visibility_changed.emit(panel_id, visible)


func _on_panel_visibility_changed(panel_id: String, visible: bool) -> void:
	if visible:
		_refresh_panel(panel_id)


## 取已建好的面板节点（验证脚本 / 外部查询用；未建返回 null）
func get_panel(panel_id: String) -> Control:
	return _panels.get(panel_id)


## 面板是否可见
func is_panel_visible(panel_id: String) -> bool:
	return _holders.has(panel_id) and _holders[panel_id].visible


## 懒建面板：`_enter()` 会一次性全建好（5 个面板都是纯代码构建的小控件）
##
## ⚠️ 顺序很关键：面板的子控件是在自己的 `_ready()` 里建的，而 `bind()` 内部会立刻
## `refresh()`。所以必须**先入树**（触发 `_ready`）**再 bind**，否则 refresh 会打在
## null 子控件上（`Invalid assignment ... on a base object of type 'Nil'`）。
func _ensure_panel(panel_id: String) -> bool:
	if _panels.has(panel_id):
		return true
	if not PANEL_IDS.has(panel_id):
		return false
	var data := SaveManager.current_data
	if data == null:
		return false

	var panel: Control = null
	match panel_id:
		PANEL_INVENTORY:
			panel = InventoryPanel.new()
		PANEL_CHARACTER:
			panel = StatPanel.new()
		PANEL_EQUIP:
			panel = EquipPanel.new()
		PANEL_TALENT:
			panel = TalentPanel.new()
		PANEL_FORGE:
			panel = ForgePanel.new()
		PANEL_SKILLS:
			panel = SkillPanel.new()
	if panel == null:
		return false

	# 浮层：半透明底 + 居中面板（面板自己会在 _ready 里建子控件）
	var holder := Control.new()
	holder.name = "Holder_%s" % panel_id
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(dim)
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	holder.add_child(box)
	box.add_child(panel)
	holder.visible = false

	_holders[panel_id] = holder
	_panels[panel_id] = panel
	_ui_layer.add_child(holder) # ← 入树：panel._ready() 在此触发

	_bind_panel(panel_id, panel)
	return true


## 把数据灌进面板。所有面板都只读 + 回调注入，hub 是唯一的数据来源。
func _bind_panel(panel_id: String, panel: Control) -> void:
	var data := SaveManager.current_data
	if data == null or panel == null:
		return
	match panel_id:
		PANEL_INVENTORY:
			(panel as InventoryPanel).bind(
				_inv, _stash, data.equipped,
				_on_equip_instance, _on_unequip_requested,
				_on_drop_item, _on_compare_requested)
		PANEL_CHARACTER:
			_recalculate_stats(data)
		PANEL_EQUIP:
			(panel as EquipPanel).bind(
				data.equipped, data.class_id, _on_unequip_requested)
		PANEL_TALENT:
			(panel as TalentPanel).bind(
				data.unlocked_talent_nodes, data.account_level, _on_talent_learn,
				data.class_id)
		PANEL_FORGE:
			(panel as ForgePanel).bind(
				_inventory_items(), data.get_material("magic_stone"),
				_on_forge_requested, _on_reroll_requested,
				data.class_id)
		PANEL_SKILLS:
			(panel as SkillPanel).bind(
				data.class_id,
				ConfigLoader.class_skill_ids(data.class_id),
				data.skill_bar,
				_on_skill_bar_saved)


func _refresh_panel(panel_id: String) -> void:
	if not _panels.has(panel_id):
		return
	_bind_panel(panel_id, _panels[panel_id])


## 技能栏保存（SkillPanel 的 on_save）：写内存 + 落盘 + 提示
func _on_skill_bar_saved(bar: Array[String]) -> void:
	var data := SaveManager.current_data
	if data == null:
		return
	data.skill_bar = bar.duplicate()
	if SaveManager.save_to_slot(data.slot, data):
		_toast_msg("技能栏已保存")
	else:
		_toast_msg("技能栏保存失败：%s" % SaveManager.last_error)


# =============================================================================
# 属性结算（StatCalculator.calculate 的唯一生产调用点）
# =============================================================================

## 据点没有局内 Buff，`buffs` 传空字典。
## 结果通过 `EventBus.stats_recalculated` 广播，StatPanel 由监听者刷新。
func _recalculate_stats(data: SaveData) -> void:
	EventBus.stats_recalculated.emit(
		StatCalculator.calculate(data.account_level, data.equipped, {}))


func _on_stats_recalculated(final_stats: Dictionary) -> void:
	last_stats = final_stats
	var sp := _panels.get(PANEL_CHARACTER) as StatPanel
	if sp != null:
		var data := SaveManager.current_data
		sp.show_stats(final_stats,
			ConfigLoader.class_display_name(data.class_id) if data != null else "")


# =============================================================================
# 装备穿脱
# =============================================================================

## 背包下标 → 装备槽（旧 EquipPanel「穿上选中」路径；面板已改版，保留兼容）。
func _on_equip_requested(index: int) -> void:
	var data := SaveManager.current_data
	if data == null:
		return
	if index < 0:
		_toast_msg("请先在背包中选中物品")
		return
	_do_equip(index)


## 穿装备核心：背包实例 → 对应槽位（旧件回包），落盘 + 广播 + 提示
func _do_equip(index: int) -> void:
	var data := SaveManager.current_data
	var items := _inventory_items()
	if data == null or index < 0 or index >= items.size():
		return
	var item: EquipmentInstance = items[index]
	var slot := item.slot
	var old := data.get_equipped(slot)
	_inv.remove(item.instance_id)
	data.set_equipped(slot, item)
	if old != null:
		_inv.add(old)
	_sync_and_save(data)
	EventBus.equipment_changed.emit(slot, item, old)
	_toast_msg("已装备：%s" % item.get_display_name())


## 拖拽装备（背包面板快捷装备条）：按 instance_id 定位背包物品
func _on_equip_instance(instance_id: String) -> void:
	var items := _inventory_items()
	for i in items.size():
		if (items[i] as EquipmentInstance).instance_id == instance_id:
			_do_equip(i)
			return
	_toast_msg("物品不在背包中，无法装备")


## 丢弃物品（背包 / 仓库通用）：从所在网格移除 + 落盘 + 刷新
func _on_drop_item(instance_id: String) -> void:
	var data := SaveManager.current_data
	if data == null:
		return
	var target: Inventory = null
	if _inv != null and _inv.index_of(instance_id) >= 0:
		target = _inv
	elif _stash != null and _stash.index_of(instance_id) >= 0:
		target = _stash
	if target == null:
		_toast_msg("物品不存在")
		return
	var item := target.remove(instance_id)
	_sync_and_save(data)
	_refresh_panel(PANEL_INVENTORY)
	if item != null:
		_toast_msg("已丢弃：%s" % item.get_display_name())


## 装备对比浮窗（背包点击物品触发）：与同槽位已穿戴横向对比
func _on_compare_requested(item: EquipmentInstance) -> void:
	var data := SaveManager.current_data
	if data == null or item == null:
		return
	var old := data.get_equipped(item.slot)
	var popup := _get_compare_popup()
	if popup == null:
		return
	popup.show_compare(item, old,
		String(GameConstants.EQUIP_SLOT_NAMES[clampi(item.slot, 0, GameConstants.EQUIP_SLOT_COUNT - 1)]),
		func() -> void: _on_equip_instance(item.instance_id))
	if _compare_holder != null:
		_compare_holder.visible = true


## 懒建对比浮窗（置顶于所有面板之上）
func _get_compare_popup() -> EquipComparePopup:
	if _compare_popup != null:
		return _compare_popup
	var holder := Control.new()
	holder.name = "CompareOverlay"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(dim)
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	holder.add_child(box)
	var popup := EquipComparePopup.new()
	popup.on_close = func() -> void: holder.visible = false
	box.add_child(popup)
	holder.visible = false
	_compare_holder = holder
	_compare_popup = popup
	_ui_layer.add_child(holder)
	return popup


func _on_unequip_requested(slot: int) -> void:
	var data := SaveManager.current_data
	if data == null or slot < 0:
		return
	var old := data.get_equipped(slot)
	if old == null:
		_toast_msg("该槽位是空的")
		return
	if not _inv.add(old):
		_toast_msg("背包已满，无法卸下")
		return
	data.set_equipped(slot, null)
	_sync_and_save(data)
	EventBus.equipment_changed.emit(slot, null, old)
	_toast_msg("已卸下：%s" % old.get_display_name())


func _on_equipment_changed(_slot: int, _new_item: EquipmentInstance,
		_old_item: EquipmentInstance) -> void:
	var data := SaveManager.current_data
	if data == null:
		return
	_refresh_panel(PANEL_EQUIP)
	_refresh_panel(PANEL_INVENTORY)
	_recalculate_stats(data)


# =============================================================================
# 天赋
# =============================================================================

func _on_talent_learn(node_id: String) -> void:
	var data := SaveManager.current_data
	if data == null:
		return
	var tree := TalentTree.new()
	for n in data.unlocked_talent_nodes:
		tree.points_spent[n] = true
	var res := tree.learn(node_id, data.account_level)
	if not bool(res.get("ok", false)):
		_toast_msg("无法点亮：%s" % String(res.get("reason", "条件不足")))
		return
	data.unlocked_talent_nodes.append(node_id)
	data.talent_points = maxi(0,
		TalentTree._available_points(data.account_level) - data.unlocked_talent_nodes.size())
	_sync_and_save(data)
	_refresh_panel(PANEL_TALENT)
	_recalculate_stats(data)
	_toast_msg("已点亮：%s" % node_id)


# =============================================================================
# 锻造 / 洗练
# =============================================================================

## 成本里缺哪些（空数组 = 付得起）。无法映射到存档键的材料也算「缺」。
func _missing_materials(data: SaveData, cost: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if int(cost.get("gold", 0)) > data.gold:
		out.append("金币 %d" % int(cost.get("gold", 0)))
	for key in cost:
		if key in ["gold", "target_level", "success_chance"]:
			continue
		var amount := int(cost[key])
		if amount <= 0:
			continue
		var save_key := String(MATERIAL_KEY_MAP.get(key, ""))
		if save_key.is_empty():
			out.append("%s（存档无对应材料键）" % key)
		elif data.get_material(save_key) < amount:
			out.append("%s×%d" % [key, amount])
	return out


func _pay_cost(data: SaveData, cost: Dictionary) -> void:
	data.add_gold(-int(cost.get("gold", 0)))
	for key in cost:
		if key in ["gold", "target_level", "success_chance"]:
			continue
		var amount := int(cost[key])
		if amount <= 0:
			continue
		var save_key := String(MATERIAL_KEY_MAP.get(key, ""))
		if not save_key.is_empty():
			data.add_material(save_key, -amount)


func _on_forge_requested(index: int) -> void:
	var data := SaveManager.current_data
	var items := _inventory_items()
	if data == null or index < 0 or index >= items.size():
		return
	var item: EquipmentInstance = items[index]
	if item.forge_level >= item.get_forge_max_level():
		_forge_result("已满强化（+%d）" % item.forge_level)
		return
	var cost := ForgeController.get_forge_cost(item)
	var missing := _missing_materials(data, cost)
	if not missing.is_empty():
		_forge_result("材料不足：%s" % ", ".join(missing))
		return

	var res := ForgeController.try_forge(item)
	if res.get("cost", {}).is_empty():
		_forge_result("已满强化（+%d）" % item.forge_level)
		return
	_pay_cost(data, cost)
	_sync_and_save(data)
	_refresh_panel(PANEL_FORGE)
	_recalculate_stats(data)

	var msg := "%s：%s → +%d" % ["锻造成功" if bool(res["success"]) else "锻造失败",
		item.get_display_name(), int(res["next_level"])]
	if bool(res.get("downgraded", false)):
		msg += "（掉级）"
	_forge_result(msg)


func _on_reroll_requested(index: int) -> void:
	var data := SaveManager.current_data
	var items := _inventory_items()
	if data == null or index < 0 or index >= items.size():
		return
	var item: EquipmentInstance = items[index]
	var cost := ForgeController.get_reroll_cost(item.forge_level)
	var missing := _missing_materials(data, cost)
	if not missing.is_empty():
		_forge_result("材料不足：%s" % ", ".join(missing))
		return

	var res := ForgeController.try_reroll(item, item.forge_level)
	if not bool(res.get("success", false)):
		_forge_result("没有可洗练的词缀")
		return
	_pay_cost(data, cost)
	_sync_and_save(data)
	_refresh_panel(PANEL_FORGE)
	_recalculate_stats(data)
	_forge_result("洗练完成：%s（重掷 %d 条 / 跳过 %d 条）" % [
		item.get_display_name(), int(res["rerolled"]), int(res["skipped"])])


func _forge_result(text: String) -> void:
	var fp := _panels.get(PANEL_FORGE) as ForgePanel
	if fp != null:
		fp.show_result(text)
	_toast_msg(text)


# =============================================================================
# 输入
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		_toggle_panel(PANEL_INVENTORY)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("character_panel"):
		_toggle_panel(PANEL_CHARACTER)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_close_all_panels()
		get_viewport().set_input_as_handled()


## 发一条「请求开关面板」——由本场景自己接住，形成「输入 → 请求 → 状态 → 广播」闭环
func _toggle_panel(panel_id: String) -> void:
	EventBus.request_panel_toggle.emit(panel_id, not is_panel_visible(panel_id))


func _close_all_panels() -> void:
	for pid in _holders:
		if _holders[pid].visible:
			EventBus.request_panel_toggle.emit(pid, false)


# =============================================================================
# UI 构建
# =============================================================================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_ui_layer.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "据点 · 七傳說"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
	root.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", GameConstants.PALETTE_NEUTRAL[9])
	root.add_child(_status)

	# 面板按钮条
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	root.add_child(bar)
	for pid in PANEL_IDS:
		var btn := Button.new()
		btn.text = String(PANEL_TITLES[pid])
		btn.custom_minimum_size = Vector2(80, 34)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_toggle_panel.bind(pid))
		AudioManager.hook_click(btn)
		bar.add_child(btn)
	var back := Button.new()
	back.text = "回主菜单"
	back.custom_minimum_size = Vector2(100, 34)
	back.add_theme_font_size_override("font_size", 13)
	back.pressed.connect(_on_back_to_menu)
	AudioManager.hook_click(back)
	bar.add_child(back)

	# 关卡列表（可滚动）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_level_list = VBoxContainer.new()
	_level_list.add_theme_constant_override("separation", 4)
	_level_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_level_list)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 12)
	_toast.add_theme_color_override("font_color", GameConstants.PALETTE_ACCENT[4])
	root.add_child(_toast)


func _on_back_to_menu() -> void:
	var data := SaveManager.current_data
	if data != null:
		_sync_and_save(data)
	SceneManager.change_scene(SceneManager.SCENE_MAIN_MENU)


# =============================================================================
# 提示
# =============================================================================

func _on_notification(message: String, color: Color) -> void:
	if _toast == null:
		return
	_toast.text = message
	_toast.add_theme_color_override("font_color", color)


func _toast_msg(message: String) -> void:
	EventBus.notify(message, GameConstants.COLOR_TEXT_NORMAL)
