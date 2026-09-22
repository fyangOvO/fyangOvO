## 材料包（任务 3.8 · 纯数据 class_name，不入场景树）
##
## 材料键：gold（金币）/ stones（魔石）/ dust（秘银尘）/ essence（传说精粹）/
## crystal（神话结晶）。gold 与 player_controller.gold 并存（会话侧沿用旧字段，
## 本类用于锻造 / 分解 / 合成的统一钱包视图）。
class_name MaterialBag
extends RefCounted

const KEY_GOLD := "gold"
const KEY_STONES := "stones"
const KEY_DUST := "dust"
const KEY_ESSENCE := "essence"
const KEY_CRYSTAL := "crystal"

## 中文名（UI / 日志）
const KEY_NAMES := {
	KEY_GOLD: "金币",
	KEY_STONES: "魔石",
	KEY_DUST: "秘银尘",
	KEY_ESSENCE: "传说精粹",
	KEY_CRYSTAL: "神话结晶",
}

var materials: Dictionary = {}


static func create(initial: Dictionary = {}) -> MaterialBag:
	var bag := MaterialBag.new()
	bag.materials = initial.duplicate()
	return bag


func get_amount(key: String) -> int:
	return int(materials.get(key, 0))


func add(key: String, amount: int) -> void:
	if amount <= 0:
		return
	materials[key] = get_amount(key) + amount


## 扣减；不足返回 false 且不扣。
func remove(key: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if get_amount(key) < amount:
		return false
	materials[key] = get_amount(key) - amount
	return true


## 批量扣减（{key: amount}）；任一不足整体失败。
func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if get_amount(String(key)) < int(cost[key]):
			return false
	return true


## 批量扣减；任一不足整体失败（不扣任何项）。
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for key in cost:
		remove(String(key), int(cost[key]))
	return true


func to_text() -> String:
	var parts: Array[String] = []
	for key in [KEY_GOLD, KEY_STONES, KEY_DUST, KEY_ESSENCE, KEY_CRYSTAL]:
		parts.append("%s×%d" % [KEY_NAMES.get(key, key), get_amount(key)])
	return " ".join(parts)
