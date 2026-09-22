## 工具：verify_equip_panel.gd（步骤 4 · 装备系统页验证）
##
## A. EquipPanel：六格结构 / 标题职业名 / 已装备清单 / 点槽位词缀展示 / 卸下回调
## B. InventoryPanel：网格 / 稀有度排序 / 选中→对比回调 / 丢弃回调
## C. 拖拽数据契约：payload / 槽位匹配 / 落点回调
## D. EquipComparePopup：对比行渲染
## E. hub 接线：建档 → 加物品 → _on_equip_instance 装备生效 → _on_drop_item 丢弃 → 对比浮窗
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables"
var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== 装备系统页实测（步骤 4）=====")
	_run()


func _run() -> void:
	await _test_equip_panel()
	await _test_inventory_panel()
	await _test_drag_contract()
	await _test_compare_popup()
	await _test_hub_wiring()
	print("===== 装备系统页实测 结束：%s =====" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# A. EquipPanel 六格装备位
# =============================================================================

func _test_equip_panel() -> void:
	print("--- A. EquipPanel（六格 + 清单 + 词缀）---")
	var eq := EquipPanel.new()
	add_child(eq)
	eq.position = Vector2(20, 20)
	var equipped: Array = []
	equipped.resize(GameConstants.EQUIP_SLOT_COUNT)
	var sword := _make_item("sword_flame", 14, GameConstants.Rarity.RARE)
	equipped[GameConstants.EquipSlot.MAIN_HAND] = sword
	var helm := _make_item("helm_crown_titan", 16, GameConstants.Rarity.EPIC)
	equipped[GameConstants.EquipSlot.HELM] = helm
	eq.bind(equipped, "warrior", Callable())
	await get_tree().process_frame

	_ok("标题 = 装备 · 战士", eq._title.text == "装备 · 战士")
	_ok("六格按钮（3×2）", eq._slot_buttons.size() == 6)
	var icons := 0
	for b in eq._slot_buttons:
		if b.icon != null:
			icons += 1
	_ok("装备槽图标渲染（%d 个）" % icons, icons >= 2)
	var list_text: String = eq._list.text
	_ok("已装备清单含武器名", list_text.contains("燃魄刃") or list_text.contains(sword.get_display_name()))
	_ok("清单含稀有度色标签", list_text.contains("[color=#"))
	# 点选武器槽 → 详情含词缀文本
	eq._on_slot_pressed(GameConstants.EquipSlot.MAIN_HAND)
	var detail: String = eq._detail.text
	_ok("词缀展示含 iLvl 与基础属性", detail.contains("iLvl 14") and detail.contains("基础"))
	_ok("词缀展示含词缀行", detail.contains("词缀") and (detail.contains("攻击力") or detail.contains("词缀：")))
	# 空槽位详情
	eq._on_slot_pressed(GameConstants.EquipSlot.GLOVES)
	_ok("空槽详情提示", eq._detail.text.contains("空槽位"))
	# 卸下回调
	var un_called: Array = []
	eq.on_unequip = func(slot: int) -> void: un_called.append(slot)
	eq._selected_slot = GameConstants.EquipSlot.MAIN_HAND
	eq._on_unequip_pressed()
	_ok("卸下回调触发（槽位 %s）" % str(un_called), un_called.size() == 1 and int(un_called[0]) == GameConstants.EquipSlot.MAIN_HAND)
	eq.queue_free()
	await get_tree().process_frame


# =============================================================================
# B. InventoryPanel 背包
# =============================================================================

func _test_inventory_panel() -> void:
	print("--- B. InventoryPanel（网格 / 排序 / 对比 / 丢弃）---")
	var ip := InventoryPanel.new()
	add_child(ip)
	var inv := Inventory.create(8, 5)
	var i_common := _make_item("sword_iron", 5, GameConstants.Rarity.COMMON)
	var i_rare := _make_item("helm_golem", 12, GameConstants.Rarity.RARE)
	var i_epic := _make_item("chest_chainmail", 15, GameConstants.Rarity.EPIC)
	inv.add(i_common)
	inv.add(i_rare)
	inv.add(i_epic)
	var compare_called: Array = []
	var drop_called: Array = []
	ip.bind(inv, Inventory.create(8, 5), [],
		Callable(), Callable(), func(id: String) -> void: drop_called.append(id),
		func(item) -> void: compare_called.append(item))
	await get_tree().process_frame

	_ok("背包标题显示数量（3/40）", ip._title.text.contains("3/40"))
	_ok("网格 40 格", ip._cell_buttons.size() == 40)
	_ok("快捷装备条 6 槽", ip._strip_buttons.size() == 6)
	# 稀有度排序：史诗最前
	ip._on_sort_rarity()
	var first: EquipmentInstance = inv.get_at(0)
	_ok("稀有度排序首格 = 史诗", first != null and first.rarity == GameConstants.Rarity.EPIC)
	# 选中 → 对比回调
	ip._on_cell_pressed(0)
	_ok("点击格子触发对比回调", compare_called.size() == 1 and compare_called[0] == first)
	_ok("丢弃按钮可用", not ip._drop_btn.disabled)
	# 丢弃回调
	ip._on_drop_pressed()
	_ok("丢弃回调带 instance_id", drop_called.size() == 1 and String(drop_called[0]) == first.instance_id)
	# 空位点击 → 丢弃禁用
	ip._on_cell_pressed(5)
	_ok("空位点击后丢弃禁用", ip._drop_btn.disabled)
	ip.queue_free()
	await get_tree().process_frame


# =============================================================================
# C. 拖拽数据契约
# =============================================================================

func _test_drag_contract() -> void:
	print("--- C. 拖拽契约（payload / 槽位匹配 / 落点）---")
	var ip := InventoryPanel.new()
	add_child(ip)
	var inv := Inventory.create(8, 5)
	var sword := _make_item("sword_iron", 10, GameConstants.Rarity.MAGIC)
	var helm := _make_item("helm_golem", 10, GameConstants.Rarity.MAGIC)
	inv.add(sword)
	inv.add(helm)
	var equipped: Array = []
	equipped.resize(GameConstants.EQUIP_SLOT_COUNT)
	var equip_called: Array = []
	ip.bind(inv, Inventory.create(8, 5), equipped,
		func(id: String) -> void: equip_called.append(id), Callable(), Callable(), Callable())
	await get_tree().process_frame

	var payload: Variant = ip._cell_drag_data(Vector2.ZERO, 0)
	_ok("拖拽 payload 类型", payload is Dictionary and String(payload.get("type", "")) == InventoryPanel.DRAG_TYPE)
	_ok("payload 带 instance_id 与槽位", String(payload.get("instance_id", "")) == sword.instance_id
		and int(payload.get("slot", -1)) == GameConstants.EquipSlot.MAIN_HAND)
	_ok("武器只能落武器槽", ip._strip_can_drop(Vector2.ZERO, payload, GameConstants.EquipSlot.MAIN_HAND)
		and not ip._strip_can_drop(Vector2.ZERO, payload, GameConstants.EquipSlot.HELM))
	ip._strip_drop(Vector2.ZERO, payload, GameConstants.EquipSlot.MAIN_HAND)
	_ok("落点回调触发装备（instance_id）", equip_called.size() == 1 and String(equip_called[0]) == sword.instance_id)
	# 错误类型拒绝
	var bad := {"type": "other", "slot": GameConstants.EquipSlot.MAIN_HAND}
	_ok("非背包类型拒绝", not ip._strip_can_drop(Vector2.ZERO, bad, GameConstants.EquipSlot.MAIN_HAND))
	ip.queue_free()
	await get_tree().process_frame


# =============================================================================
# D. EquipComparePopup 对比浮窗
# =============================================================================

func _test_compare_popup() -> void:
	print("--- D. EquipComparePopup（对比行）---")
	var pop := EquipComparePopup.new()
	add_child(pop)
	await get_tree().process_frame
	var new_item := _make_item("sword_flame", 14, GameConstants.Rarity.RARE)
	_apply_affix(new_item, "add_flat_attack", 8.0)
	var old_item := _make_item("sword_iron", 10, GameConstants.Rarity.MAGIC)
	pop.show_compare(new_item, old_item, "武器", Callable())
	await get_tree().process_frame
	_ok("对比浮窗可见", pop.visible)
	_ok("对比标题含槽位名", pop._compare._title_label.text.contains("武器"))
	var rows: int = pop._compare._rows_box.get_child_count()
	_ok("对比行渲染（%d 行）" % rows, rows >= 2)
	_ok("副标题含新旧名称", pop._sub.text.contains(new_item.get_display_name())
		and pop._sub.text.contains(old_item.get_display_name()))
	# 空槽位提示
	pop.show_compare(new_item, null, "武器", Callable())
	_ok("空槽位提示", pop._sub.text.contains("空槽位"))
	# 装备回调
	var equip_called: Array = []
	pop.show_compare(new_item, old_item, "武器", func() -> void: equip_called.append(true))
	pop._on_equip_pressed()
	_ok("装备此件回调 + 关闭", equip_called.size() == 1 and not pop.visible)
	pop.queue_free()
	await get_tree().process_frame


# =============================================================================
# E. hub 接线
# =============================================================================

func _test_hub_wiring() -> void:
	print("--- E. hub 接线（装备 / 丢弃 / 对比浮窗）---")
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	var data := SaveManager.create_new_slot(0, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = 0
	SceneManager.fade_duration = 0.0
	var hub: Node = (load("res://scenes/main/hub.tscn") as PackedScene).instantiate()
	add_child(hub)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await get_tree().create_timer(0.4).timeout
	_ok("据点在树", hub != null)

	var sword := _make_item("sword_flame", 14, GameConstants.Rarity.RARE)
	_apply_affix(sword, "add_flat_attack", 8.0)
	var helm := _make_item("helm_crown_titan", 15, GameConstants.Rarity.EPIC)
	hub._inv.add(sword)
	hub._inv.add(helm)
	hub._sync_and_save(data)

	hub._on_equip_instance(sword.instance_id)
	await get_tree().process_frame
	var equipped_item: EquipmentInstance = data.get_equipped(GameConstants.EquipSlot.MAIN_HAND)
	_ok("装备生效（主手）", equipped_item != null and equipped_item.instance_id == sword.instance_id)
	_ok("装备后背包移除", hub._inv.index_of(sword.instance_id) < 0)

	hub._on_compare_requested(helm)
	await get_tree().process_frame
	_ok("对比浮窗弹出（holder + popup 均可见）", hub._compare_popup != null
		and hub._compare_popup.visible and hub._compare_holder != null
		and hub._compare_holder.visible)
	hub._compare_popup.close()
	await get_tree().process_frame
	_ok("关闭后 holder 隐藏", hub._compare_holder != null and not hub._compare_holder.visible)

	hub._on_drop_item(helm.instance_id)
	await get_tree().process_frame
	_ok("丢弃生效（背包移除）", hub._inv.index_of(helm.instance_id) < 0)

	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	hub.queue_free()
	await get_tree().process_frame


# =============================================================================
# 工具
# =============================================================================

func _make_item(tpl_id: String, ilvl: int, rarity: int) -> EquipmentInstance:
	var tpl := ConfigLoader.get_equipment_template(tpl_id)
	if tpl == null:
		_ok("模板存在：%s" % tpl_id, false)
		return null
	return EquipmentInstance.create_from_template(tpl, ilvl, rarity)


func _apply_affix(item: EquipmentInstance, affix_id: String, value: float) -> void:
	var tpl := ConfigLoader.get_affix(affix_id)
	if tpl == null:
		return
	var roll := AffixRoll.create(affix_id, value)
	roll.template = tpl
	item.affixes.append(roll)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
