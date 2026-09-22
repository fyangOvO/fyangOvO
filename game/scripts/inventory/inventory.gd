## 背包 / 仓库数据层（任务 3.6 · 纯数据 class_name，不入场景树）
##
## 设计：
##   - 固定网格：背包 8 列 × 5 行 = 40 格，仓库 8 列 × 10 行 = 80 格（工程侧默认，
##     GDD 未给背包尺寸；物品格 48×48 见 GDD 0.3 节 3.7）
##   - 一格一件（装备不堆叠）；槽位 Array[EquipmentInstance]，null = 空
##   - 排序按 稀有度 / 部位 / iLvl / 名称（升/降序）；整理 = 压缩空位到最前
##   - 仓库转移：transfer(from, to, instance_id)
##
## ⚠️ 本类不持有玩家引用、不发信号（EventBus.item_added 等由调用方发），保持可单测。
class_name Inventory
extends RefCounted

const SORT_RARITY := 0
const SORT_SLOT := 1
const SORT_ILVL := 2
const SORT_NAME := 3

var cols: int = 8
var rows: int = 5
var slots: Array[EquipmentInstance] = [] ## null = 空


static func create(p_cols: int, p_rows: int) -> Inventory:
	var inv := Inventory.new()
	inv.cols = p_cols
	inv.rows = p_rows
	inv.slots.resize(p_cols * p_rows)
	return inv


func capacity() -> int:
	return cols * rows


func count() -> int:
	var n := 0
	for s in slots:
		if s != null:
			n += 1
	return n


func is_full() -> bool:
	return count() >= capacity()


func is_empty() -> bool:
	return count() == 0


func index_of(instance_id: String) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i].instance_id == instance_id:
			return i
	return -1


## 放入物品：找第一个空位；满仓返回 false。
func add(item: EquipmentInstance) -> bool:
	if item == null:
		return false
	var idx := first_empty()
	if idx < 0:
		return false
	slots[idx] = item
	return true


func remove_at(index: int) -> EquipmentInstance:
	if index < 0 or index >= slots.size():
		return null
	var item := slots[index]
	slots[index] = null
	return item


func remove(instance_id: String) -> EquipmentInstance:
	return remove_at(index_of(instance_id))


## 交换两格（同背包内移动 / 排序也用它）。
func swap(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= slots.size() or b >= slots.size():
		return false
	var tmp := slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	return true


## 整理：把非空物品压到最前（保持相对顺序），尾部留空。
func compact() -> void:
	var write := 0
	for read in slots.size():
		if slots[read] != null:
			if write != read:
				slots[write] = slots[read]
				slots[read] = null
			write += 1


## 按 key 排序（SORT_*）。desc = true 降序。
func sort_by(key: int, desc: bool = false) -> void:
	var arr: Array[EquipmentInstance] = []
	for s in slots:
		if s != null:
			arr.append(s)
	var factor := -1.0 if desc else 1.0
	arr.sort_custom(func(a: EquipmentInstance, b: EquipmentInstance) -> bool:
		var va := _sort_key(a, key)
		var vb := _sort_key(b, key)
		if va == vb:
			return a.instance_id < b.instance_id
		return (va - vb) * factor < 0.0)
	compact()
	for i in arr.size():
		slots[i] = arr[i]


func _sort_key(item: EquipmentInstance, key: int) -> float:
	match key:
		SORT_RARITY:
			return float(item.rarity)
		SORT_SLOT:
			return float(item.slot)
		SORT_ILVL:
			return float(item.item_level)
		SORT_NAME:
			return item.get_display_name().unicode_at(0) if not item.get_display_name().is_empty() else 0.0
	return 0.0


func first_empty() -> int:
	for i in slots.size():
		if slots[i] == null:
			return i
	return -1


func get_at(index: int) -> EquipmentInstance:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## 仓库转移：从 from 移除并放入 to；to 满仓则不动返回 false。
static func transfer(from_inv: Inventory, to_inv: Inventory, instance_id: String) -> bool:
	var idx := from_inv.index_of(instance_id)
	if idx < 0:
		return false
	var item := from_inv.slots[idx]
	if not to_inv.add(item):
		return false
	from_inv.slots[idx] = null
	return true
