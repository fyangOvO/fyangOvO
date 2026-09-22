## 一件**具体装备实例**（可掉落、可入包、可装备、可存档）
##
## 与 `EquipmentData` 的区别：
##   - `EquipmentData` = 底材模板（"铁剑"这个种类，全局唯一一份）
##   - `EquipmentInstance` = 一件具体的铁剑（iLvl 17 / 稀有 / 4 条词缀 / +3 强化）
##
## 字段覆盖任务清单 1.7 的全部要求：
##   部位、稀有度（8 档）、基础属性、词缀列表、物品等级、需求等级、是否套装、套装 ID。
##
## 存档策略：`to_dict()` 只落盘 **模板 ID + 实例字段 + 词缀 roll**，
##          读档后由 ConfigLoader 依据 `template_id` / `affix_id` 回填运行时引用。
class_name EquipmentInstance
extends Resource

## 全局唯一实例 ID（存档、拖拽、比较、交易都靠它；运行时生成）
@export var instance_id: String = ""

## 底材模板 ID（对应 EquipmentData.id）
@export var template_id: String = ""

## 自定义显示名（如 "烬誓·燃魄刃"）。空 = 使用底材的 display_name
@export var custom_name: String = ""

# -----------------------------------------------------------------------------
# 核心属性
# -----------------------------------------------------------------------------

## 装备部位 —— GameConstants.EquipSlot
@export var slot: int = GameConstants.EquipSlot.MAIN_HAND

## 稀有度 —— GameConstants.Rarity（8 档：白/蓝/黄/紫/橙/红/绿/彩）
@export var rarity: int = GameConstants.Rarity.COMMON

## 物品等级 iLvl（= 掉落时的关卡等级，GDD 0.3 节 3.6）
@export var item_level: int = 1

## 需求等级 ReqLv（= max(1, iLvl - 2)，GDD 0.3 节 3.6）。
## 存字段而非实时计算：便于阶段 3 引入「减需求」词缀而不破坏存档兼容。
@export var required_level: int = 1

## 强化等级 +0 ~ +10（GDD 0.3 节 3.4）
@export var forge_level: int = 0

# -----------------------------------------------------------------------------
# 词缀
# -----------------------------------------------------------------------------

## 已 roll 出的词缀列表（含前缀与后缀，顺序 = 显示顺序）
@export var affixes: Array[AffixRoll] = []

## 传奇特效 ID（仅传说及以上档位；空 = 无）
@export var legendary_effect_id: String = ""

# -----------------------------------------------------------------------------
# 隐藏（彩蛋）装的可成长字段 —— GDD 0.3 节 3.2.2
# -----------------------------------------------------------------------------
#
# 隐藏装随特定行为累积成长（如每 1000 击杀 +1% 某属性，上限 +20%）。
# 成长是**单件物品的持久状态**，因此必须落在实例上而非模板上。

## 成长作用的属性键（GameConstants.STAT_*；空 = 该件不可成长）
@export var growth_stat_key: String = ""

## 已累积的成长加成（百分数，如 8.0 表示 +8%），上限 HIDDEN_GROWTH_MAX_BONUS
@export var growth_value: float = 0.0

# -----------------------------------------------------------------------------
# 套装
# -----------------------------------------------------------------------------

## 套装 ID（空 = 非套装件）
@export var set_id: String = ""

## 是否为套装件（冗余字段：便于存档读取时无需查表即可判断，
## 也保证套装定义被移除后旧存档仍能正确显示）
@export var is_set_item: bool = false

## 已镶嵌宝石：{槽位 index: "type.tier"}（任务 5.5，随存档序列化）
@export var gems: Dictionary = {}

# -----------------------------------------------------------------------------
# 运行时引用（不序列化）
# -----------------------------------------------------------------------------

## 底材模板引用，由 ConfigLoader 注入
var template: EquipmentData = null

## 是否已装备（仅内存态，不入存档 —— 装备状态由角色的装备槽决定）
var equipped: bool = false


# =============================================================================
# 构造
# =============================================================================

## 由底材模板生成一件空白实例（**不 roll 词缀**；roll 逻辑属阶段 3 掉落系统）
static func create_from_template(p_template: EquipmentData, p_item_level: int, p_rarity: int) -> EquipmentInstance:
	var item := EquipmentInstance.new()
	item.template = p_template
	item.template_id = p_template.id
	item.slot = p_template.slot
	item.item_level = p_item_level
	item.rarity = p_rarity
	item.required_level = GameConstants.required_level_for(p_item_level)
	item.set_id = p_template.set_id
	item.is_set_item = p_template.is_set_item()
	item.instance_id = generate_instance_id()
	return item


## 生成实例唯一 ID。格式：`i_<时间戳>_<随机>`，保证同帧多次生成也不冲突。
static func generate_instance_id() -> String:
	return "i_%d_%04d" % [Time.get_ticks_usec(), randi() % 10000]


# =============================================================================
# 查询
# =============================================================================

## 显示名：优先自定义名（传奇/套装会有专属名），否则用底材名
func get_display_name() -> String:
	if not custom_name.is_empty():
		return custom_name
	if template != null:
		return template.display_name
	return template_id


## 稀有度文字色（UI 直接用）
func get_rarity_color() -> Color:
	return GameConstants.rarity_color(rarity)


## 是否为武器（决定是否走武器视觉原型层）
func is_weapon() -> bool:
	return template != null and template.is_weapon()


## 武器视觉原型；非武器返回 -1
func get_weapon_archetype() -> int:
	return template.weapon_archetype if template != null else -1


## 强化带来的基础属性加成系数（+10 = 1.5 倍基础属性，GDD 0.3 节 3.4）
func get_forge_multiplier() -> float:
	return 1.0 + GameConstants.FORGE_STAT_BONUS_PER_LEVEL * float(forge_level)


## 本件装备的强化上限（神话红装 +12，其余 +10）
func get_forge_max_level() -> int:
	return GameConstants.forge_max_level_for(rarity)


## 是否已强化满
func is_forge_maxed() -> bool:
	return forge_level >= get_forge_max_level()


## 是否为隐藏（彩蛋）装
func is_hidden_item() -> bool:
	return rarity == GameConstants.Rarity.HIDDEN


## 是否为神话（红）装
func is_mythic_item() -> bool:
	return rarity == GameConstants.Rarity.MYTHIC


## 该装备的全部基础属性（已应用 iLvl 缩放与强化加成）。
## 注意：**不含词缀**。词缀结算属阶段 2/3 的属性聚合器。
func get_base_stats() -> Dictionary:
	if template == null:
		return {}
	var out := {}
	var forge := get_forge_multiplier()
	for key in template.base_stats:
		out[key] = float(template.base_stats[key]) * GameConstants.item_stat_ilvl_scale(item_level) * forge
	return out


## 装备能否被指定玩家等级穿戴
func can_equip(player_level: int) -> bool:
	return player_level >= required_level


## 装备的「战力评分」占位 —— 阶段 3 用真实公式替换。
## 这里只做**结构占位**，禁止在阶段 1 用它做任何平衡决策。
func get_power_score() -> float:
	var score := 0.0
	var stats := get_base_stats()
	for key in stats:
		score += float(stats[key])
	for roll in affixes:
		score += roll.value
	return score


# =============================================================================
# 序列化
# =============================================================================

func to_dict() -> Dictionary:
	var affix_dicts: Array = []
	for roll in affixes:
		affix_dicts.append(roll.to_dict())
	return {
		"instance_id": instance_id,
		"template_id": template_id,
		"custom_name": custom_name,
		"slot": slot,
		"rarity": rarity,
		"item_level": item_level,
		"required_level": required_level,
		"forge_level": forge_level,
		"affixes": affix_dicts,
		"legendary_effect_id": legendary_effect_id,
		"set_id": set_id,
		"is_set_item": is_set_item,
	}


## 反序列化。**不注入 template 引用** —— 由 ConfigLoader 统一回填（见 resolve_refs）。
static func from_dict(data: Dictionary) -> EquipmentInstance:
	var item := EquipmentInstance.new()
	item.instance_id = String(data.get("instance_id", generate_instance_id()))
	item.template_id = String(data.get("template_id", ""))
	item.custom_name = String(data.get("custom_name", ""))
	item.slot = int(data.get("slot", GameConstants.EquipSlot.MAIN_HAND))
	item.rarity = clampi(int(data.get("rarity", GameConstants.Rarity.COMMON)), 0, GameConstants.RARITY_COUNT - 1)
	item.item_level = maxi(int(data.get("item_level", 1)), 1)
	item.required_level = maxi(int(data.get("required_level", GameConstants.required_level_for(item.item_level))), 1)
	# 强化上限随稀有度变化（神话 +12），故必须在 rarity 解析之后夹取
	item.forge_level = clampi(int(data.get("forge_level", 0)), 0, item.get_forge_max_level())
	item.legendary_effect_id = String(data.get("legendary_effect_id", ""))
	item.set_id = String(data.get("set_id", ""))
	item.is_set_item = bool(data.get("is_set_item", false))
	item.growth_stat_key = String(data.get("growth_stat_key", ""))
	item.growth_value = clampf(float(data.get("growth_value", 0.0)), 0.0, GameConstants.HIDDEN_GROWTH_MAX_BONUS)

	var affix_data: Array = data.get("affixes", [])
	for entry in affix_data:
		if entry is Dictionary:
			item.affixes.append(AffixRoll.from_dict(entry))
	return item
