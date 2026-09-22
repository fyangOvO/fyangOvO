## 掉落表（数据驱动 · 自定义 Resource）
##
## 定位：描述「某类怪 / 某个箱子掉落什么」。**只定义权重与数量，不定义 roll 算法** ——
##       roll 算法属阶段 3 掉落系统（`scripts/items/loot_generator.gd`）。
##
## 权重口径（GDD 0.6 节 6.1）：
##   - `rarity_weights` 是**相对权重**，不是百分比；实际概率 = w[i] / Σw。
##     这样难度层级修正（白 ×0.85 / 黄 ×1.15 / 紫橙 ×1.30）可以直接乘权重再归一化。
##   - `drop_chance` 是「本次击杀是否触发掉落」的概率（普通 8% / 精英 60% / BOSS 100%）。
##
## 数据来源：`game/data/loot_tables/*.json`
class_name LootTable
extends Resource

## 唯一标识
@export var id: String = ""

## 适用档位（对应 MonsterData.Tier；用于校验与调试）
@export var tier: int = MonsterData.Tier.NORMAL

## 掉落触发概率（0–1）
@export var drop_chance: float = 0.08

## 触发后掉落件数区间 [min, max]
@export var drop_count_range: Vector2i = Vector2i(1, 1)

## 各稀有度相对权重，下标对应 GameConstants.Rarity（8 档）。
## 默认值取自 GDD 0.6 节 6.1「普通怪」一行；神话/套装/隐藏为占位值。
@export var rarity_weights: Array[float] = [
	78.0, 18.0, 3.50, 0.45, 0.05, 0.02, 0.08, 0.01,
]

## 装备掉落占总掉落的比例（其余为金币 / 材料 / 消耗品）
@export var equipment_share: float = 0.55

## 金币掉落权重
@export var gold_weight: float = 30.0

## 材料掉落权重
@export var material_weight: float = 12.0

## 消耗品掉落权重
@export var consumable_weight: float = 3.0

## 保底：本次未掉落装备时，是否累积「幸运」并在下次提高稀有度权重
## （GDD 0.2 节「变强可感知」保底机制，暂定：精英掉落权重 +20%，最多叠至 +60%）
@export var pity_enabled: bool = false
@export var pity_bonus_per_stack: float = 0.20
@export var pity_max_stacks: int = 3

## 允许掉落的底材 ID 白名单（空 = 不限）
@export var allowed_template_ids: Array[String] = []

## 禁止掉落的底材 ID 黑名单
@export var excluded_template_ids: Array[String] = []


## 归一化后的稀有度概率数组（总和为 1）。
## `difficulty_tier` 用于应用 GDD 0.6 节 6.1 的难度层级修正。
## `apply_overlevel_penalty` 用于应用越级惩罚（紫/橙 ×0.5，GDD 0.3 节 3.6）。
func get_rarity_probabilities(difficulty_tier: int = 0, apply_overlevel_penalty: bool = false) -> Array[float]:
	var weights := get_adjusted_weights(difficulty_tier, apply_overlevel_penalty)
	var total := 0.0
	for w in weights:
		total += w

	var probs: Array[float] = []
	if total <= 0.0:
		probs.resize(GameConstants.RARITY_COUNT)
		probs.fill(0.0)
		return probs

	for w in weights:
		probs.append(w / total)
	return probs


## 应用难度层级与越级惩罚后的权重数组（未归一化）
##
## 修正规则（GDD 0.6 节 6.1「修正规则」v1.3）：
##   白/蓝 ×0.85^n ｜ 黄 ×1.15^n ｜ 紫/橙 ×1.30^n ｜ 绿 ×1.10^n ｜ 红 ×1.50^n ｜ 彩 不变
##   神话红**仅梦魇 II 及以上掉落**，难度不足时权重直接归零。
##   越级惩罚（紫/橙/红 ×0.5）由 `apply_overlevel_penalty` 控制。
func get_adjusted_weights(difficulty_tier: int = 0, apply_overlevel_penalty: bool = false) -> Array[float]:
	var tier := clampi(difficulty_tier, 0, GameConstants.DIFFICULTY_TIER_COUNT - 1)
	var common_mult := pow(GameConstants.DIFFICULTY_COMMON_WEIGHT_MULT, float(tier))
	var rare_mult := pow(GameConstants.DIFFICULTY_RARE_WEIGHT_MULT, float(tier))
	var epic_mult := pow(GameConstants.DIFFICULTY_EPIC_WEIGHT_MULT, float(tier))
	var set_mult := pow(GameConstants.DIFFICULTY_SET_WEIGHT_MULT, float(tier))
	var mythic_mult := pow(GameConstants.DIFFICULTY_MYTHIC_WEIGHT_MULT, float(tier))

	var out: Array[float] = []
	for i in range(GameConstants.RARITY_COUNT):
		var w: float = rarity_weights[i] if i < rarity_weights.size() else 0.0
		match i:
			GameConstants.Rarity.COMMON, GameConstants.Rarity.MAGIC:
				w *= common_mult
			GameConstants.Rarity.RARE:
				w *= rare_mult
			GameConstants.Rarity.EPIC, GameConstants.Rarity.LEGENDARY:
				w *= epic_mult
			GameConstants.Rarity.MYTHIC:
				# 门槛：仅梦魇 II 及以上掉落（GDD 0.3 节 3.2.2）
				if tier < GameConstants.MYTHIC_MIN_DIFFICULTY_TIER:
					w = 0.0
				else:
					w *= mythic_mult
			GameConstants.Rarity.SET:
				w *= set_mult
			_:
				pass # 隐藏彩：权重不随难度变化
		if apply_overlevel_penalty and i >= GameConstants.Rarity.EPIC and i <= GameConstants.Rarity.MYTHIC:
			w *= GameConstants.OVERLEVEL_PENALTY_MULT
		out.append(w)
	return out


## 期望掉落件数（用于数值仿真与保底校验，不参与运行时 roll）
func expected_drops() -> float:
	var avg_count := float(drop_count_range.x + drop_count_range.y) * 0.5
	return drop_chance * avg_count


## 期望产出指定稀有度的件数（GDD 0.6 节 6.6 校验用）
func expected_count_of_rarity(rarity: int, difficulty_tier: int = 0) -> float:
	var probs := get_rarity_probabilities(difficulty_tier)
	if rarity < 0 or rarity >= probs.size():
		return 0.0
	return expected_drops() * probs[rarity]


## 校验数据完整性，返回错误信息数组（空数组 = 通过）
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("LootTable.id 为空")
	if rarity_weights.size() != GameConstants.RARITY_COUNT:
		errors.append("掉落表 '%s' 的 rarity_weights 长度应为 %d，实际 %d"
			% [id, GameConstants.RARITY_COUNT, rarity_weights.size()])
	if drop_chance < 0.0 or drop_chance > 1.0:
		errors.append("掉落表 '%s' 的 drop_chance 应在 [0,1]，实际 %f" % [id, drop_chance])
	if drop_count_range.x < 0 or drop_count_range.y < drop_count_range.x:
		errors.append("掉落表 '%s' 的 drop_count_range 非法" % id)
	return errors
