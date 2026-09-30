## 特殊档（深渊/塔）装备强化表（B5-7 · 6-W6-Q4 · 纯静态 class_name）
##
## 与普通强化的区别：
##   · 上限 +10（普通装通常 +5）；
##   · 三段成本：1–3 / 4–6 / 7–10，专属材料逐级递增；
##   · 只吃专属材料（深渊裂片 / 塔印），不吃魔石/秘银尘等通用材料。
class_name SpecialUpgradeController
extends RefCounted

const MAX_PLUS := 10

## 升到 next_plus 一级的成本；等级 1..10。越界返回空表。
static func upgrade_cost(item: EquipmentInstance, current_plus: int) -> Dictionary:
	if not SpecialRerollController.can_reroll(item):
		return {}
	var key := SpecialRerollController.material_key_for(item.rarity)
	var next := current_plus + 1
	if next < 1 or next > MAX_PLUS:
		return {}
	# 三段：1-3 每层 1 个，4-6 每层 2 个，7-10 每层 3 个
	var per := 1 if next <= 3 else (2 if next <= 6 else 3)
	return {key: per}


static func can_upgrade(item: EquipmentInstance, current_plus: int) -> bool:
	return SpecialRerollController.can_reroll(item) and current_plus < MAX_PLUS
