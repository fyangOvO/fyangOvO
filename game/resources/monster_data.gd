## 怪物定义（数据驱动 · 自定义 Resource）
##
## 字段覆盖任务清单 1.7：名称、等级、HP、伤害、掉落表引用。
## 数值口径见 GDD 0.6 节 6.3：Monster_HP(L) = 60 × 1.28^(L-1)，DMG(L) = 8 × 1.24^(L-1)。
##
## 注意：本类是**模板**。同一种怪在不同关卡等级下 HP/DMG 不同，
##       而数值基线（L1 普通怪的 HP / DMG）**只存在于 `GameConstants` 一处**，
##       本类只存「相对基线的倍率」（`hp_scale` / `damage_scale`）。
##       实际值由 `get_hp(level, tier)` / `get_damage(level, tier)` 计算。
##
## 数据来源：`game/data/monsters/*.json`
class_name MonsterData
extends Resource

## 怪物档位（决定 HP 倍率与掉落口径）
enum Tier {
	NORMAL = 0, ## 普通怪 —— 掉落触发 8%
	ELITE = 1,  ## 精英怪 —— 掉落触发 60%
	BOSS = 2,   ## BOSS —— 掉落触发 100%，掉 2–4 件
}

const TIER_NAMES: Array[String] = ["普通", "精英", "BOSS"]
const TIER_KEYS: Array[String] = ["normal", "elite", "boss"]

## 唯一标识（如 "spider_cave"）
@export var id: String = ""

## UI 显示名
@export var display_name: String = ""

## 档位 —— Tier
@export var tier: int = Tier.NORMAL

## 出现等级区间（该怪可被投放到哪些关卡等级）
@export var level_min: int = 1
@export var level_max: int = GameConstants.LEVEL_MAX

# -----------------------------------------------------------------------------
# 数值（**相对基线**的倍率，而非绝对值）
# -----------------------------------------------------------------------------
#
# 设计要点：怪物数值基线（L1 的 HP / DMG）**只存在于 `GameConstants` 一处**，
# 本类只描述「这只怪相对基线是几倍」。这样阶段 3 调参时改一个常量即可全局生效，
# 不需要去 8 个怪物条目里逐个改绝对值。
#
# 实际公式：
#   HP(L, tier) = MONSTER_HP_AT_L1 × hp_scale × hp_growth^(L-1) × 档位倍率 × 难度 HP 系数
#   DMG(L, tier)= MONSTER_DMG_AT_L1 × damage_scale × damage_growth^(L-1) × 难度 DMG 系数

## HP 相对基线（L1 普通怪）的倍率。1.0 = 与基线持平；0.7 = 脆皮；1.6 = 肉盾。
@export var hp_scale: float = 1.0

## 单次伤害相对基线的倍率
@export var damage_scale: float = 1.0

## HP 成长系数（每级倍率）。默认继承 GameConstants.MONSTER_HP_GROWTH；
## 仅当某只怪需要与全局不同的成长曲线时才在数据里覆盖。
@export var hp_growth: float = GameConstants.MONSTER_HP_GROWTH

## 伤害成长系数（每级倍率）。默认继承 GameConstants.MONSTER_DMG_GROWTH。
@export var damage_growth: float = GameConstants.MONSTER_DMG_GROWTH

## 移动速度（像素/秒）
@export var move_speed: float = 60.0

## 攻击间隔（秒）
@export var attack_interval: float = 1.5

## 攻击距离（像素）
@export var attack_range: float = 40.0

## 护甲
@export var base_armor: float = 0.0

# -----------------------------------------------------------------------------
# 掉落与表现
# -----------------------------------------------------------------------------

## 掉落表 ID（引用 `game/data/loot_tables/` 中的表；空 = 使用档位默认表）
@export var loot_table_id: String = ""

## 精灵资源路径（32×32 或 48×48，见美术规范 2.1）
@export_file("*.png") var sprite_path: String = ""

## 动画方向数：人形怪 4，非人形杂兵 2（美术规范 3.1 节「朝向敏感度分级出图」）
@export var sprite_directions: int = 4

## AI 行为 ID（阶段 2 由 AI 工厂解析；阶段 1 仅占位）
@export var ai_id: String = "melee_chaser"

## 是否为飞行单位（影响寻路与地形通行，阶段 2 使用）
@export var is_flying: bool = false

## 经验奖励基准（L1；实际值随等级缩放）
@export var base_xp: float = 10.0

## 金币奖励区间 [min, max]（L1；GDD 0.6 节 6.5）
@export var gold_range: Vector2i = Vector2i(5, 15)

## 元素类型（决定攻击伤害类型与抗性穿透，阶段 2 使用）
@export var element: String = "physical"


# =============================================================================
# 数值计算
# =============================================================================

## 档位 HP 倍率（精英 ×4.5，BOSS ×28，GDD 0.6 节 6.3）
func get_tier_hp_multiplier() -> float:
	match tier:
		Tier.ELITE:
			return GameConstants.MONSTER_ELITE_HP_MULT
		Tier.BOSS:
			return GameConstants.MONSTER_BOSS_HP_MULT
		_:
			return 1.0


## 指定关卡等级 + 难度层级下的实际 HP
func get_hp(level: int, difficulty_tier: int = GameConstants.DifficultyTier.NM1) -> float:
	var l := maxi(level, 1)
	var base := GameConstants.MONSTER_HP_AT_L1 * hp_scale * pow(hp_growth, float(l - 1))
	return base * get_tier_hp_multiplier() * GameConstants.difficulty_hp_multiplier(difficulty_tier)


## 指定关卡等级 + 难度层级下的实际单次伤害
func get_damage(level: int, difficulty_tier: int = GameConstants.DifficultyTier.NM1) -> float:
	var l := maxi(level, 1)
	var base := GameConstants.MONSTER_DMG_AT_L1 * damage_scale * pow(damage_growth, float(l - 1))
	return base * GameConstants.difficulty_dmg_multiplier(difficulty_tier)


## 指定关卡等级下的护甲
func get_armor(level: int) -> float:
	return base_armor * GameConstants.item_stat_ilvl_scale(level)


## 指定关卡等级下的经验奖励
func get_xp(level: int) -> float:
	return base_xp * pow(1.12, float(maxi(level, 1) - 1))


## 指定关卡等级下的金币奖励区间
func get_gold_range(level: int) -> Vector2i:
	var mult := 1.0 + 0.10 * float(maxi(level, 1))
	return Vector2i(int(gold_range.x * mult), int(gold_range.y * mult))


## 该怪能否出现在指定关卡等级
func fits_level(level: int) -> bool:
	return level >= level_min and level <= level_max


## 校验数据完整性，返回错误信息数组（空数组 = 通过）
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("MonsterData.id 为空")
	if display_name.is_empty():
		errors.append("怪物 '%s' 缺少 display_name" % id)
	if tier < 0 or tier > Tier.BOSS:
		errors.append("怪物 '%s' 的 tier 非法：%d" % [id, tier])
	if level_max < level_min:
		errors.append("怪物 '%s' 的等级区间非法：[%d, %d]" % [id, level_min, level_max])
	if hp_scale <= 0.0:
		errors.append("怪物 '%s' 的 hp_scale 必须 > 0" % id)
	if damage_scale <= 0.0:
		errors.append("怪物 '%s' 的 damage_scale 必须 > 0" % id)
	return errors
