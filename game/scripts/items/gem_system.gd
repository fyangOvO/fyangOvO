## 宝石镶嵌（任务 5.5 · class_name）
##
## GDD 5.5「永久属性提升（强化 / 宝石镶嵌）」——宝石为工程侧默认设计
## （GDD 仅列项名，未给规则）：
##   - 宝石 4 档：碎裂 / 普通 / 完美 / 无瑕（红宝石=攻击、蓝宝石=护甲、绿宝石=生命）；
##   - 装备槽：白 0 / 蓝 1 / 黄 1 / 紫 2 / 橙+ 2（硬编码在模板 rarity_max）；
##   - 镶嵌/拆卸均免费（本地单机不搞消耗）；同槽替换直接覆盖。
class_name GemSystem
extends RefCounted

## 宝石档位基础值（百分数 / 点数，按档位放大）
const GEM_TIERS := {
	"flawed": {"name": "碎裂", "mult": 1.0},
	"normal": {"name": "普通", "mult": 2.0},
	"flawless": {"name": "完美", "mult": 4.0},
	"perfect": {"name": "无瑕", "mult": 8.0},
}
const GEM_TYPES := {
	"ruby": {"name": "红宝石", "stat": "pct_attack", "base": 3.0},
	"sapphire": {"name": "蓝宝石", "stat": "pct_armor", "base": 3.0},
	"emerald": {"name": "绿宝石", "stat": "pct_hp", "base": 3.0},
}

## 宝石上限：槽数 = 底材稀有度（白 0 / 蓝 1 / 黄 1 / 紫 2 / 橙+ 2）
static func max_sockets(item: EquipmentInstance) -> int:
	if item == null:
		return 0
	if item.rarity >= GameConstants.Rarity.LEGENDARY:
		return 2
	if item.rarity >= GameConstants.Rarity.RARE:
		return 1
	return 0


## 当前槽位：{index: "ruby.flawed"}
func get_sockets(item: EquipmentInstance) -> Dictionary:
	return item.gems


## 镶嵌：index 0–槽上限；类型合法则写入（替换覆盖）
static func socket(item: EquipmentInstance, index: int, gem_id: String) -> Dictionary:
	var parts := gem_id.split(".")
	if parts.size() != 2 or not GEM_TYPES.has(parts[0]) or not GEM_TIERS.has(parts[1]):
		return {"ok": false, "reason": "宝石 id 非法"}
	if index < 0 or index >= max_sockets(item):
		return {"ok": false, "reason": "槽位不足"}
	item.gems[index] = gem_id
	return {"ok": true}


## 拆卸：返回宝石 id（或空）
static func unsocket(item: EquipmentInstance, index: int) -> String:
	if not item.gems.has(index):
		return ""
	var gem := str(item.gems[index])
	item.gems.erase(index)
	return gem


## 宝石加成汇总：{stat_key: 数值}
static func get_gem_bonus(item: EquipmentInstance) -> Dictionary:
	var out := {}
	for i in item.gems:
		var parts := str(item.gems[i]).split(".")
		if parts.size() != 2:
			continue
		var gem_type: Dictionary = GEM_TYPES.get(parts[0], {})
		var tier: Dictionary = GEM_TIERS.get(parts[1], {})
		if gem_type.is_empty() or tier.is_empty():
			continue
		var stat := str(gem_type["stat"])
		out[stat] = float(out.get(stat, 0.0)) \
			+ float(gem_type["base"]) * float(tier["mult"])
	return out


## 全部装备宝石加成汇总（并入属性结算）
static func get_total_gem_bonus(equipped: Array[EquipmentInstance]) -> Dictionary:
	var out := {}
	for item in equipped:
		var bonus := get_gem_bonus(item)
		for key in bonus:
			out[key] = float(out.get(key, 0.0)) + float(bonus[key])
	return out
