## 词缀定义（数据驱动 · 自定义 Resource）
##
## 定位：**模板**，描述「一条词缀长什么样」，不承载任何一条具体装备上的实际数值。
## 具体数值由 `AffixRoll`（见本文件末尾）承载并挂在装备实例上。
##
## 数值公式（GDD 0.6 节 6.2）：
##   Value(iLvl) = Base × (1 + 0.085 × (iLvl - 1)) × roll_quality
## 其中 Base 由本类的 `value_min` / `value_max` 在 roll 时线性插值得到。
##
## 数据来源：`game/data/affixes/*.json`，由 ConfigLoader 解析后实例化本类。
class_name AffixData
extends Resource

## 唯一标识，必须与数据文件名/JSON 中的 key 一致（如 "add_flat_attack"）
@export var id: String = ""

## UI 显示名（如 "攻击力"）—— 拼装完整词缀文本时用
@export var display_name: String = ""

## 描述模板。支持两个占位符：
##   `{value}`     —— 数值原样输出（按 `decimal_places` 取精度）。
##                    **百分比词缀的数值本身就是百分数**（5.0 表示 5%），模板里直接写 "%"，
##                    例如 `"+{value}% 攻击速度"`。
##   `{value_pct}` —— 数值 ×100。仅用于「以小数存储的比例」这类特殊词缀（如 0.15 → 15）。
## 例："+{value} 攻击力" / "+{value}% 攻击速度"
@export var description_template: String = ""

## 词缀类别（攻击 / 防御 / 资源 / 特殊）—— 见 GameConstants.AffixCategory
@export var category: int = GameConstants.AffixCategory.ATTACK

## 位置（前缀 = 数值型 / 后缀 = 机制型）—— 见 GameConstants.AffixPosition
@export var position: int = GameConstants.AffixPosition.PREFIX

## 数值是否为百分比（影响 UI 显示与最终结算口径）
@export var is_percentage: bool = false

## 基础数值区间（iLvl = 1 时）。roll 时取 [value_min, value_max] 内均匀随机。
@export var value_min: float = 0.0
@export var value_max: float = 0.0

## 数值显示精度（小数位）
@export var decimal_places: int = 0

## 统计键（3.7 装备对比 / 3.9 属性结算）：把词缀归并到玩家属性键，
## 如 "add_flat_attack" → "flat_attack"、"add_crit_chance" → "crit_chance"。
@export var stat_key: String = ""

## 该词缀可出现的部位（空数组 = 任意部位可用）。
## 元素为 GameConstants.EquipSlot 的 int 值。
@export var allowed_slots: Array[int] = []

## 是否随物品等级缩放。绝大多数为 true；少数固定值词缀（如 +1 技能等级）设 false。
@export var scales_with_item_level: bool = true

## 可否被洗练（GDD 0.3 节 3.4）。隐藏专属词缀通常不可洗练。
@export var can_reroll: bool = true

## 同名词缀互斥组。同组内不可重复出现（GDD 0.3 节 3.3「同名词缀不可重复」）。
## 留空则用 `id` 自身作为互斥组。
@export var exclusive_group: String = ""

## 该词缀是否仅限特定稀有度及以上（-1 = 不限）。用于隐藏专属词缀。
@export var min_rarity: int = -1

## 掉落权重（同类池内相对权重，越大越常见）
@export var weight: float = 100.0

## 是否可出现在商店 / 锻造产出中（阶段 3 使用）
@export var obtainable_from_craft: bool = true


## 取 iLvl = 1 时的基准值（区间内均匀随机）
func roll_base_value(rng: RandomNumberGenerator = null) -> float:
	if rng == null:
		return randf_range(value_min, value_max)
	return rng.randf_range(value_min, value_max)


## 按物品等级缩放后的取值区间下界 / 上界
func scaled_range(item_level: int) -> Vector2:
	var scale := 1.0
	if scales_with_item_level:
		scale = GameConstants.affix_ilvl_scale(item_level)
	return Vector2(value_min * scale, value_max * scale)


## 互斥组键名（未显式配置时退化为 id 自身）
func get_exclusive_group() -> String:
	return exclusive_group if not exclusive_group.is_empty() else id


## 该词缀能否出现在指定部位
func fits_slot(slot: int) -> bool:
	return allowed_slots.is_empty() or allowed_slots.has(slot)


## 校验数据完整性，返回错误信息数组（空数组 = 通过）
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("AffixData.id 为空")
	if display_name.is_empty():
		errors.append("词缀 '%s' 缺少 display_name" % id)
	if value_max < value_min:
		errors.append("词缀 '%s' 的 value_max < value_min" % id)
	if category < 0 or category >= GameConstants.AFFIX_CATEGORY_COUNT:
		errors.append("词缀 '%s' 的 category 越界：%d" % [id, category])
	if position != GameConstants.AffixPosition.PREFIX and position != GameConstants.AffixPosition.SUFFIX:
		errors.append("词缀 '%s' 的 position 非法：%d" % [id, position])
	if stat_key.is_empty():
		errors.append("词缀 '%s' 缺少 stat_key（3.7 装备对比 / 3.9 属性结算依赖）" % id)
	return errors


## 转为字典（供存档 / 调试输出）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"category": category,
		"position": position,
		"is_percentage": is_percentage,
		"value_min": value_min,
		"value_max": value_max,
	}
