## 局内三选一选项池（任务 4.2 · class_name 纯静态）
##
## GDD 0.4 节 4.2：15 个具体选项（攻击 6 / 防御 5 / 资源 4），
## 每升 1 级从池中不重复抽取 3 个。
##
## GDD 0.4 节 4.4：局内增益对任意单一属性增幅上限 =
##   攻击/生命 +30%（硬上限）、攻速/暴击率 +20%、移速/拾取/金币不占上限；
##   达上限后该类选项从池中移除，自动切换为功能性选项。
class_name RunePool
extends RefCounted


## 选项定义：id / 类别 / 名称 / 效果文案 / stat_key / 加成值（百分数）
## stat_key 对应 StatCalculator 统计键；cap 为类别上限（0 = 不占上限）。
const OPTIONS: Array[Dictionary] = [
	# ---- 攻击 ----
	{"id": "fury",        "cat": "attack",   "name": "狂怒",   "desc": "+12% 攻击力",
		"stat_key": "pct_attack", "value": 12.0, "cap": 30.0},
	{"id": "gale",        "cat": "attack",   "name": "疾风",   "desc": "+10% 攻击速度",
		"stat_key": "attack_speed", "value": 10.0, "cap": 20.0},
	{"id": "lethal",      "cat": "attack",   "name": "致命",   "desc": "+8% 暴击率",
		"stat_key": "crit_chance", "value": 8.0, "cap": 20.0},
	{"id": "rend",        "cat": "attack",   "name": "撕裂",   "desc": "+25% 暴击伤害",
		"stat_key": "crit_damage", "value": 25.0, "cap": 0.0},
	{"id": "elemental",   "cat": "attack",   "name": "元素附魔", "desc": "攻击附加 20% 随机元素伤害",
		"stat_key": "elemental_damage", "value": 20.0, "cap": 0.0},
	{"id": "armor_pierce","cat": "attack",   "name": "破甲",   "desc": "无视敌方 15% 护甲",
		"stat_key": "armor_pierce", "value": 15.0, "cap": 0.0},
	# ---- 防御 ----
	{"id": "tenacity",    "cat": "defense",  "name": "坚韧",   "desc": "+15% 最大生命",
		"stat_key": "pct_hp", "value": 15.0, "cap": 30.0},
	{"id": "bulwark",     "cat": "defense",  "name": "铁壁",   "desc": "+20% 护甲",
		"stat_key": "pct_armor", "value": 20.0, "cap": 0.0},
	{"id": "regrowth",    "cat": "defense",  "name": "再生",   "desc": "每秒回复 1.5% 最大生命",
		"stat_key": "regen_pct_hp", "value": 1.5, "cap": 0.0},
	{"id": "thorns",      "cat": "defense",  "name": "荆棘",   "desc": "受击反弹 30% 攻击力伤害",
		"stat_key": "thorns", "value": 30.0, "cap": 0.0},
	{"id": "ward",        "cat": "defense",  "name": "护盾",   "desc": "每 10 秒获得 15% 最大生命的护盾",
		"stat_key": "shield_pct_hp", "value": 15.0, "cap": 0.0},
	# ---- 资源 ----
	{"id": "swift",       "cat": "resource", "name": "迅捷",   "desc": "+12% 移动速度",
		"stat_key": "move_speed", "value": 12.0, "cap": 0.0},
	{"id": "greed",       "cat": "resource", "name": "贪婪",   "desc": "本局金币/材料获取 +30%",
		"stat_key": "gold_gain", "value": 30.0, "cap": 0.0},
	{"id": "fortune",     "cat": "resource", "name": "幸运",   "desc": "本局掉落稀有度权重 +10%",
		"stat_key": "magic_find", "value": 10.0, "cap": 0.0},
	{"id": "drain",       "cat": "resource", "name": "汲取",   "desc": "攻击回复 2% 造成伤害（生命偷取）",
		"stat_key": "life_steal", "value": 2.0, "cap": 0.0},
]


## 按 id 取选项（无则 null）
static func get_option(option_id: String) -> Dictionary:
	for opt in OPTIONS:
		if opt["id"] == option_id:
			return opt
	return {}


## 该类别的属性上限（0 = 不占上限）
static func get_cap(option_id: String) -> float:
	var opt := get_option(option_id)
	if opt.is_empty():
		return 0.0
	return float(opt["cap"])


## 某 **stat_key** 的上限（0 = 不占上限）。
##
## 用于 `RunBuffSystem.to_calculator_buffs()` 的**硬顶钳制**（GDD 0.4 §4.4：
## 「局内增益对任意单一属性的增幅上限 = 基础属性 +30%」）。一个 stat_key 可能有多个
## 选项共用（当前数据是一对一，但 key 级钳制不依赖这个假设），故取其中最大 cap。
static func cap_for_stat_key(stat_key: String) -> float:
	var cap := 0.0
	for opt in OPTIONS:
		if str(opt["stat_key"]) == stat_key and float(opt["cap"]) > 0.0:
			cap = maxf(cap, float(opt["cap"]))
	return cap


## 从池中抽取 count 个不重复选项（**同一次抽出的结果之间**必不重复）。
##
## `picked_ids`：要**显式排除**的 id（调用方决定语义）。⚠️ 生产路径 `LevelScene`
##   **传空数组** —— GDD 0.4 §4.1「从池中不重复抽取」只约束**单次 3 张之间**，
##   不禁止跨级重复；跨级可重复才能让 `apply_option` 叠层、并让 §4.4 的「达上限移除」生效。
## `stats_pct`：当前各属性累计值（百分数）→ 达上限类别自动移除（GDD 0.4 §4.4）。
static func get_choices(count: int, picked_ids: Array = [],
		stats_pct: Dictionary = {}, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var pool: Array[Dictionary] = []
	for opt in OPTIONS:
		if opt["id"] in picked_ids:
			continue
		var cap := float(opt["cap"])
		if cap > 0.0 and float(stats_pct.get(opt["stat_key"], 0.0)) >= cap:
			continue # 该类已达上限，从池移除
		pool.append(opt)
	var out: Array[Dictionary] = []
	while out.size() < count and not pool.is_empty():
		var idx := r.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)
	return out
