## 工具：capture_equip_panel.gd（步骤 4 装备系统页真渲染抓图；**非玩法**）
##
## 用途：建战士档 → 据点 → 造 5 件装备（含词缀）入包 → 装备 3 件 →
##       ① 背包页（快捷装备条 + 稀有度边框）→ ② 点击格子弹对比浮窗 → ③ 装备栏六格位。
## 用法（**必须去掉 --headless**；小窗 640×360 demo）：
##   godot --path "D:/七傳說/game" res://tools/capture_equip_panel.tscn
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables"
var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== 装备系统页真渲染抓图（小窗 640×360）=====")
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless（否則抓不到畫面）", DisplayServer.get_name() != "headless")
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	var data := SaveManager.create_new_slot(0, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = 0
	_ok("战士档已建", data != null)
	if data == null:
		get_tree().quit(1)
		return

	SceneManager.fade_duration = 0.0
	var hub: Node = (load("res://scenes/main/hub.tscn") as PackedScene).instantiate()
	add_child(hub)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await get_tree().create_timer(0.6).timeout
	_ok("进入据点（手动实例化）", hub != null)
	if hub == null:
		get_tree().quit(1)
		return

	# 造 5 件装备（含词缀）入包
	var items: Array[EquipmentInstance] = []
	items.append(_make_item("sword_flame", 14, GameConstants.Rarity.RARE, "add_flat_attack"))
	items.append(_make_item("helm_crown_titan", 16, GameConstants.Rarity.EPIC, "add_flat_hp"))
	items.append(_make_item("chest_ember", 15, GameConstants.Rarity.LEGENDARY, "add_flat_armor"))
	items.append(_make_item("gloves_cold", 12, GameConstants.Rarity.MAGIC, "add_crit_chance"))
	items.append(_make_item("boots_wind", 11, GameConstants.Rarity.RARE, "add_cooldown_reduction"))
	for it in items:
		hub._inv.add(it)
	hub._sync_and_save(data)
	_ok("5 件装备入包", hub._inv.count() == 5)

	# 装备 3 件（武器 / 头 / 胸）
	hub._on_equip_instance(items[0].instance_id)
	hub._on_equip_instance(items[1].instance_id)
	hub._on_equip_instance(items[2].instance_id)
	await get_tree().process_frame
	_ok("3 件已装备", data.get_equipped(GameConstants.EquipSlot.MAIN_HAND) != null
		and data.get_equipped(GameConstants.EquipSlot.HELM) != null
		and data.get_equipped(GameConstants.EquipSlot.CHEST) != null)

	# ① 背包页
	hub._toggle_panel("inventory")
	await get_tree().create_timer(0.6).timeout
	_ok("背包面板已打开", hub.is_panel_visible("inventory"))
	await _capture(OUT_DIR + "/背包_快捷装备条_2026-09-22.png")

	# ② 点格子 → 对比浮窗
	var ip := hub.get_panel("inventory") as InventoryPanel
	var clicked := false
	for cell in ip._cell_buttons:
		if cell.icon != null:
			cell.pressed.emit()
			clicked = true
			break
	await get_tree().create_timer(0.6).timeout
	_ok("对比浮窗弹出", clicked and hub._compare_popup != null and hub._compare_popup.visible
		and hub._compare_holder != null and hub._compare_holder.visible)
	await _capture(OUT_DIR + "/装备对比_浮窗_2026-09-22.png")
	if hub._compare_popup != null:
		hub._compare_popup.close()
	await get_tree().create_timer(0.3).timeout

	# ③ 装备栏六格位
	hub._toggle_panel("equip")
	await get_tree().create_timer(0.6).timeout
	_ok("装备栏面板已打开", hub.is_panel_visible("equip"))
	# 选中武器槽展示词缀
	var ep := hub.get_panel("equip") as EquipPanel
	ep._on_slot_pressed(GameConstants.EquipSlot.MAIN_HAND)
	await get_tree().create_timer(0.3).timeout
	await _capture(OUT_DIR + "/装备栏_六格装备位_2026-09-22.png")

	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _make_item(tpl_id: String, ilvl: int, rarity: int, affix_id: String) -> EquipmentInstance:
	var tpl := ConfigLoader.get_equipment_template(tpl_id)
	if tpl == null:
		_ok("模板存在：%s" % tpl_id, false)
		return null
	var item := EquipmentInstance.create_from_template(tpl, ilvl, rarity)
	var aff := ConfigLoader.get_affix(affix_id)
	if aff != null:
		var roll := AffixRoll.create(affix_id, 8.0 + float(ilvl) * 0.5)
		roll.template = aff
		item.affixes.append(roll)
	return item


func _capture(out: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	if err == OK and _is_blank(img):
		await get_tree().create_timer(0.5).timeout
		img = get_viewport().get_texture().get_image()
		err = img.save_png(out)
	_ok("截圖 %s（err=%d）" % [out, err], err == OK)
	if err != OK:
		_fail += 1


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _is_blank(img: Image) -> bool:
	var min_c := Color(1, 1, 1)
	var max_c := Color(0, 0, 0)
	for i in 8:
		var x := (img.get_width() * i) / 8
		var c0 := img.get_pixel(x, 0)
		var c1 := img.get_pixel(x, img.get_height() / 2)
		var c2 := img.get_pixel(x, img.get_height() - 1)
		for c in [c0, c1, c2]:
			min_c = Color(min(min_c.r, c.r), min(min_c.g, c.g), min(min_c.b, c.b))
			max_c = Color(max(max_c.r, c.r), max(max_c.g, c.g), max(max_c.b, c.b))
	var range_v := max_c.r - min_c.r + max_c.g - min_c.g + max_c.b - min_c.b
	return range_v < 0.03
