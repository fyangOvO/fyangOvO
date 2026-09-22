## 背包 / 仓库实测（任务 3.6 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_inventory.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. 容量：背包 8×5=40 / 仓库 8×10=80、add/remove/count/is_full/is_empty
##   B. 满仓：40 件后 add 拒绝、first_empty 正确
##   C. 移动 / 交换：swap 换位、remove 按 instance_id
##   D. 整理：compact 压紧空位（相对顺序保持）
##   E. 排序：稀有度 / 部位 / iLvl 升降序（含 null 跳过）
##   F. 仓库转移：transfer 成功 / 目标满仓失败且不丢物品
##   G. 面板接入：InventoryPanel 绑定数据后刷新（count 文案正确）
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 背包 / 仓库实测（任务 3.6） =====")
	_rng.seed = 20260916
	await _test_capacity()
	await _test_full()
	await _test_move()
	await _test_compact()
	await _test_sort()
	await _test_transfer()
	await _test_panel()
	_finish()


func _make_item(rarity: int, ilvl: int = 20, slot: int = GameConstants.EquipSlot.MAIN_HAND) -> EquipmentInstance:
	var item := EquipmentInstance.new()
	item.instance_id = "t_%d_%d" % [rarity, _rng.randi() % 100000]
	item.template_id = "sword_iron"
	item.slot = slot
	item.item_level = ilvl
	item.rarity = rarity
	item.affixes = AffixRoller.roll_affixes(ConfigLoader.get_equipment_template("sword_iron"), ilvl, rarity, _rng)
	return item


# =============================================================================
# A. 容量
# =============================================================================

func _test_capacity() -> void:
	print("--- A. 容量 ---")
	var inv := Inventory.create(8, 5)
	_ok("背包 8×5 = 40 格", inv.capacity() == 40 and inv.is_empty())
	var stash := Inventory.create(8, 10)
	_ok("仓库 8×10 = 80 格", stash.capacity() == 80)
	for i in range(3):
		_ok("add 成功", inv.add(_make_item(GameConstants.Rarity.MAGIC + i)))
	_ok("count = 3 / 非空", inv.count() == 3 and not inv.is_empty())
	_ok("remove_at 返回物品并清空该格", inv.remove_at(0) != null and inv.count() == 2)


# =============================================================================
# B. 满仓
# =============================================================================

func _test_full() -> void:
	print("--- B. 满仓 ---")
	var inv := Inventory.create(4, 2)
	for i in range(8):
		_ok("第 %d 件入包" % (i + 1), inv.add(_make_item(GameConstants.Rarity.MAGIC)))
	_ok("满仓（8/8）", inv.is_full() and inv.count() == 8)
	_ok("满仓 add 拒绝", not inv.add(_make_item(GameConstants.Rarity.MAGIC)))
	_ok("first_empty = -1", inv.first_empty() == -1)
	inv.remove_at(3)
	_ok("移除后 first_empty = 3", inv.first_empty() == 3 and not inv.is_full())


# =============================================================================
# C. 移动 / 交换
# =============================================================================

func _test_move() -> void:
	print("--- C. 移动 / 交换 ---")
	var inv := Inventory.create(8, 5)
	var a := _make_item(GameConstants.Rarity.LEGENDARY, 25)
	var b := _make_item(GameConstants.Rarity.RARE, 10)
	inv.add(a)
	inv.add(b)
	_ok("swap 0/1 交换", inv.swap(0, 1) and inv.get_at(0) == b and inv.get_at(1) == a)
	_ok("swap 越界拒绝", not inv.swap(-1, 0) and not inv.swap(0, 999))
	_ok("remove 按 instance_id", inv.remove(a.instance_id) == a and inv.count() == 1)
	_ok("remove 不存在返回 null", inv.remove("no_such_id") == null)


# =============================================================================
# D. 整理
# =============================================================================

func _test_compact() -> void:
	print("--- D. 整理 ---")
	var inv := Inventory.create(8, 2)
	var items: Array[EquipmentInstance] = []
	for i in range(4):
		var it := _make_item(GameConstants.Rarity.MAGIC + i)
		items.append(it)
		inv.add(it)
	inv.remove_at(1) # [0, 空, 2, 3]
	inv.remove_at(2) # [0, 空, 空, 3]
	inv.compact()    # [0, 3, 空, 空]
	_ok("整理后物品压到最前（相对顺序保持）",
		inv.get_at(0) == items[0] and inv.get_at(1) == items[3]
		and inv.get_at(2) == null and inv.count() == 2)


# =============================================================================
# E. 排序
# =============================================================================

func _test_sort() -> void:
	print("--- E. 排序 ---")
	var inv := Inventory.create(8, 5)
	var rare := _make_item(GameConstants.Rarity.RARE, 15)
	var legend := _make_item(GameConstants.Rarity.LEGENDARY, 30)
	var magic := _make_item(GameConstants.Rarity.MAGIC, 5)
	inv.add(rare)
	inv.add(legend)
	inv.add(magic)
	inv.sort_by(Inventory.SORT_RARITY, true) # 降序：橙 > 蓝 > 白
	_ok("稀有度降序（橙/蓝/白）",
		inv.get_at(0) == legend and inv.get_at(1) == rare and inv.get_at(2) == magic)
	inv.sort_by(Inventory.SORT_ILVL, false) # 升序：5 / 15 / 30
	_ok("iLvl 升序（5/15/30）",
		inv.get_at(0) == magic and inv.get_at(1) == rare and inv.get_at(2) == legend)
	inv.sort_by(Inventory.SORT_SLOT, true)
	_ok("部位降序（slot 值排序，主手 5 最大在首位）", inv.get_at(0) != null)
	# 排序后无空位在前
	var null_before := false
	var seen_null := false
	for s in inv.slots:
		if s == null:
			seen_null = true
		elif seen_null:
			null_before = true
	_ok("排序后空位全部在尾部", not null_before)


# =============================================================================
# F. 仓库转移
# =============================================================================

func _test_transfer() -> void:
	print("--- F. 仓库转移 ---")
	var inv := Inventory.create(8, 5)
	var stash := Inventory.create(2, 1)
	var item := _make_item(GameConstants.Rarity.LEGENDARY)
	inv.add(item)
	_ok("转移成功（背包 → 仓库）", Inventory.transfer(inv, stash, item.instance_id))
	_ok("转移后背包空 / 仓库 1 件", inv.count() == 0 and stash.count() == 1)
	var item2 := _make_item(GameConstants.Rarity.RARE)
	inv.add(item2)
	stash.add(_make_item(GameConstants.Rarity.MAGIC))
	_ok("仓库满仓（2/2）", stash.is_full())
	_ok("满仓转移失败且不丢物品", not Inventory.transfer(inv, stash, item2.instance_id)
		and inv.count() == 1 and inv.get_at(0) == item2)
	_ok("转移不存在的物品失败", not Inventory.transfer(inv, stash, "nope"))


# =============================================================================
# G. 面板接入
# =============================================================================

func _test_panel() -> void:
	print("--- G. 面板接入 ---")
	var inv := Inventory.create(8, 5)
	var stash := Inventory.create(8, 10)
	inv.add(_make_item(GameConstants.Rarity.LEGENDARY, 25))
	inv.add(_make_item(GameConstants.Rarity.RARE, 10))
	var panel := InventoryPanel.new()
	add_child(panel) # 进树触发 _ready（_build_ui）
	panel.bind(inv, stash)
	panel._refresh()
	_ok("面板模式文案 = 背包（2/40）", panel._mode_label.text == "背包（2/40）")
	panel._on_toggle_stash()
	_ok("切换仓库文案 = 仓库（0/80）", panel._mode_label.text == "仓库（0/80）")
	panel._on_toggle_stash() # 切回背包
	panel._sort(Inventory.SORT_RARITY)
	_ok("面板排序后首格 = 稀有度最高（橙）",
		panel._cell_buttons.size() == 40 and panel.inventory.get_at(0).rarity == GameConstants.Rarity.LEGENDARY)
	panel._on_compact()
	_ok("面板整理后 count 不变", panel.inventory.count() == 2)
	panel.queue_free()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
