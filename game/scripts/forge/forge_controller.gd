## 锻造与洗练控制器（任务 3.4 · 纯静态 class_name）
##
## 职责：装备**强化**（forge）与**洗练**（reroll）的纯结算逻辑。
##   - 强化：消耗 魔石（+1~+12）+ 金币（100×1.35^k）+ 神话结晶（红装 +11/+12）
##     掷骰成功 → forge_level+1；失败 → +9 起降 1 级，+1~+8 仅耗材料。
##   - 洗练：保持词缀**类型**（affix_id 不变），重掷**数值**；第 n 次
##     消耗 500×1.15^n 金币 + 1 秘银尘。
##
## ⚠️ 本类**不直接扣玩家钱包**（不持有玩家引用）：只做成本查询与骰子结算，
## 返回完整结果由调用方（UI / 背包）校验并扣费 —— 保持纯函数、可单测。
class_name ForgeController
extends RefCounted


## 查询强化到下一级的目标成本（不掷骰）。
## 返回 { target_level, gold, stone, crystal, success_chance }
static func get_forge_cost(item: EquipmentInstance) -> Dictionary:
	var target := item.forge_level + 1
	return {
		"target_level": target,
		"gold": GameConstants.forge_gold_cost(target),
		"stone": GameConstants.forge_stone_cost(target),
		"crystal": GameConstants.FORGE_CRYSTAL_COST_PER_TRY if target > GameConstants.FORGE_MAX_LEVEL else 0,
		"success_chance": GameConstants.forge_success_chance(target),
	}


## 尝试强化（掷骰结算；不扣费，由调用方按返回值扣）。
## 返回 { success, next_level, downgraded, cost: Dictionary }
static func try_forge(item: EquipmentInstance, rng: RandomNumberGenerator = null) -> Dictionary:
	var max_lv := item.get_forge_max_level()
	if item.forge_level >= max_lv:
		return { "success": false, "next_level": item.forge_level, "downgraded": false,
			"cost": {}, "reason": "maxed" }
	var cost := get_forge_cost(item)
	var chance: float = cost["success_chance"]
	var roll := (rng.randf() if rng != null else randf())
	var success := roll < chance
	var next := item.forge_level
	var downgraded := false
	if success:
		next = item.forge_level + 1
		item.forge_level = next
	else:
		if item.forge_level + 1 >= GameConstants.FORGE_FAIL_DOWNGRADE_FROM and item.forge_level > 0:
			item.forge_level -= 1
			downgraded = true
	return { "success": success, "next_level": next, "downgraded": downgraded, "cost": cost }


## 查询洗练第 n 次的成本（n 从 0 起：第一次洗练 = 500 金币）。
static func get_reroll_cost(n: int) -> Dictionary:
	return {
		"gold": GameConstants.reroll_gold_cost(n),
		"dust": GameConstants.REROLL_DUST_COST,
	}


## 洗练：保持词缀类型重掷数值（can_reroll 词缀）。
## 返回 { success, rerolled: int, skipped: int, cost: Dictionary }
## ⚠️ 调用方负责校验并扣费（gold / dust）。
static func try_reroll(item: EquipmentInstance, n: int, rng: RandomNumberGenerator = null) -> Dictionary:
	if item.affixes.is_empty():
		return { "success": false, "rerolled": 0, "skipped": 0,
			"cost": get_reroll_cost(n), "reason": "no_affixes" }
	var r := rng if rng != null else RandomNumberGenerator.new()
	var rerolled := 0
	var skipped := 0
	for roll in item.affixes:
		var template: AffixData = roll.template
		if template == null:
			template = ConfigLoader.get_affix(roll.affix_id)
			roll.template = template
		if template == null or not template.can_reroll:
			skipped += 1
			continue
		# 保持类型（affix_id / position / is_empowered），重掷数值与品质
		var quality := _roll_quality(r)
		var base := template.roll_base_value(r)
		roll.value = base * GameConstants.affix_ilvl_scale(item.item_level) * quality
		roll.quality = quality
		rerolled += 1
	return { "success": rerolled > 0, "rerolled": rerolled, "skipped": skipped,
		"cost": get_reroll_cost(n) }


static func _roll_quality(rng: RandomNumberGenerator) -> float:
	var total := 0.0
	for w in AffixRoller.QUALITY_WEIGHTS:
		total += float(w)
	var rr := rng.randf() * total
	var acc := 0.0
	for i in range(AffixRoller.QUALITY_WEIGHTS.size()):
		acc += AffixRoller.QUALITY_WEIGHTS[i]
		if rr <= acc:
			return GameConstants.AFFIX_ROLL_QUALITY_TIERS[i]
	return GameConstants.AFFIX_ROLL_QUALITY_TIERS[GameConstants.AFFIX_ROLL_QUALITY_TIERS.size() - 1]
