## 装备**底材模板**（数据驱动 · 自定义 Resource）
##
## 定位：描述「一把铁剑长什么样」——部位、视觉原型、iLvl=1 时的基础属性、固有词缀、
##       以及可用的词缀池。**不含**物品等级、稀有度、实际词缀数值 ——
##       那些属于「一件具体装备」，见 `EquipmentInstance`。
##
## 为什么分模板 / 实例两层：
##   「铁剑」这一底材在游戏里会掉落成百上千件（不同 iLvl、不同稀有度、不同词缀）。
##   模板全局唯一（几百个），实例每件一份。这与美术规范 3.1 节
##   「物品几百件，视觉原型只有个位数」的分层思路一致。
##
## 数据来源：`game/data/equipment/*.json`，由 ConfigLoader 解析后实例化本类。
class_name EquipmentData
extends Resource

## 唯一标识（如 "sword_iron"）
@export var id: String = ""

## UI 显示名（如 "铁剑"）
@export var display_name: String = ""

## 装备部位 —— GameConstants.EquipSlot
@export var slot: int = GameConstants.EquipSlot.MAIN_HAND

## 视觉原型 —— GameConstants.WeaponArchetype。
## 非武器部位（头/胸/手/腿/脚/项链/戒指）固定为 -1，走 Body 重着色方案。
@export var weapon_archetype: int = -1

## 基础属性（iLvl = 1 时的值）。键为 GameConstants.StatKey 中的字符串键，值为数值。
## 例：{"flat_attack": 10.0, "crit_chance": 5.0}
## 实际取值 = base_stats[k] × (1 + 0.12 × (iLvl - 1))
@export var base_stats: Dictionary = {}

## 固有词缀 ID（该底材必带、不占词缀条数的词缀，可为空）
@export var implicit_affix_id: String = ""

## 该底材允许出现的词缀池 ID 列表（对应 `game/data/affixes/` 中的池定义）。
## 空数组 = 使用该部位 + 类别的默认池。
@export var affix_pool_ids: Array[String] = []

## 该底材可出现的物品等级区间 [min, max]（用于掉落时的底材筛选）
@export var item_level_min: int = 1
@export var item_level_max: int = GameConstants.LEVEL_MAX

## 该底材可出现的稀有度区间 [min, max]（对应 GameConstants.Rarity）。
## 例：白装底材可 roll 到橙，但某些底材（如任务物品）限死为白。
@export var rarity_min: int = GameConstants.Rarity.COMMON
@export var rarity_max: int = GameConstants.Rarity.LEGENDARY

## 图标资源路径（48×48，美术规范 2.6 节）
@export_file("*.png") var icon_path: String = ""

## 套装 ID（空 = 非套装底材）。套装加成定义见 `game/data/equipment/sets/`
@export var set_id: String = ""

## 掉落权重（同部位底材池内的相对权重）
@export var drop_weight: float = 100.0

## 是否可在商店 / 锻造产出
@export var craftable: bool = true

## 是否禁止分解（如任务道具）
@export var undismantlable: bool = false

## 传奇特效 ID（可选：底材固定绑定一件特效；空 = 掉落时从同部位特效池抽取）。
## 仅稀有度 ≥ 传说（橙）时生效（GDD 0.3 节 3.2.2：橙必含 1 条传奇特效）。
@export var legendary_effect_id: String = ""

## 隐藏（彩蛋）装的成长配置（GDD 3.2.2：每 1000 击杀 +1% 某属性，上限 +20%）
## growth_stat_key：成长的属性键（统计键，如 all_attributes / move_speed；空 = 不可成长）
@export var growth_stat_key: String = ""

## 成长上限（百分数，如 5.0 = +5%）；默认取 HIDDEN_GROWTH_MAX_BONUS（20%）
@export var growth_max: float = 20.0


## 取某条基础属性在指定物品等级下的数值（未配置该属性则返回 0）
func get_base_stat(stat_key: String, item_level: int) -> float:
	if not base_stats.has(stat_key):
		return 0.0
	return float(base_stats[stat_key]) * GameConstants.item_stat_ilvl_scale(item_level)


## 取该底材在指定物品等级下的全部基础属性（已缩放）
func get_scaled_base_stats(item_level: int) -> Dictionary:
	var out := {}
	var scale := GameConstants.item_stat_ilvl_scale(item_level)
	for key in base_stats:
		out[key] = float(base_stats[key]) * scale
	return out


## 该底材能否出现在指定物品等级 / 稀有度
func fits(item_level: int, rarity: int) -> bool:
	if item_level < item_level_min or item_level > item_level_max:
		return false
	return rarity >= rarity_min and rarity <= rarity_max


## 是否为武器（走武器视觉原型层）
func is_weapon() -> bool:
	return weapon_archetype >= 0


## 是否为套装底材
func is_set_item() -> bool:
	return not set_id.is_empty()


## 校验数据完整性，返回错误信息数组（空数组 = 通过）
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("EquipmentData.id 为空")
	if display_name.is_empty():
		errors.append("底材 '%s' 缺少 display_name" % id)
	if slot < 0 or slot >= GameConstants.EQUIP_SLOT_COUNT:
		errors.append("底材 '%s' 的 slot 越界：%d" % [id, slot])
	if rarity_min < 0 or rarity_min >= GameConstants.RARITY_COUNT:
		errors.append("底材 '%s' 的 rarity_min 越界：%d" % [id, rarity_min])
	if rarity_max < rarity_min or rarity_max >= GameConstants.RARITY_COUNT:
		errors.append("底材 '%s' 的 rarity_max 非法：%d" % [id, rarity_max])
	if item_level_min < 1 or item_level_max < item_level_min:
		errors.append("底材 '%s' 的 item_level 区间非法：[%d, %d]" % [id, item_level_min, item_level_max])
	if slot == GameConstants.EquipSlot.MAIN_HAND and weapon_archetype < 0:
		errors.append("底材 '%s' 是主手但未指定 weapon_archetype" % id)
	return errors
