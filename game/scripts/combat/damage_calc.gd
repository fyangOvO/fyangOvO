## 伤害计算管线（任务 2.3 · 用户拍板口径）
##
## 纯静态函数，无节点依赖，可无头验证。
##
## 公式（GDD 6.6 = 期望口径，本模块 = 实机每次 roll）：
##   raw  = AD × 技能倍率
##   暴击  = roll_crit(CR) → 本次 ×CD（CD 百分数 150 = ×1.5）
##   期望  = 1 + CR × (CD - 1)                    —— GDD 6.6 DPS_exp
##   元素  = ×(1 + 元素伤害%)                     —— 词缀/套装阶段 3 接入
##   减伤  = 护甲 DR（物理）/ 元素抗性 DR（元素）→ ×(1 - 减伤%)
##   final = raw × 暴击 × 元素 × (1 - 减伤)
##
## 减伤顺序（用户拍板）：护甲/抗性 → 减伤% 乘算 → 概率判定（闪避/格挡，2.5/2.6）。
class_name DamageCalc
extends RefCounted


## 暴击判定：chance（%）vs 随机。chance 会被 clamp 到 [0, CRIT_CHANCE_CAP]。
static func roll_crit(crit_chance_pct: float) -> bool:
	var chance := clampf(crit_chance_pct, 0.0, GameConstants.CRIT_CHANCE_CAP)
	return randf() * 100.0 < chance


## 本次暴击倍率：暴击 = CD（%→倍率），非暴击 = 1.0。
static func crit_multiplier(crit: bool, crit_damage_pct: float) -> float:
	if not crit:
		return 1.0
	return maxf(crit_damage_pct, 100.0) * 0.01


## 期望暴击加成倍率：1 + CR × (CD - 1)（GDD 6.6，CR/CD 为百分数）。
## 供 DPS 期望计算 / 数值校验使用，与实机 roll 的长期均值一致。
static func expected_crit_multiplier(crit_chance_pct: float, crit_damage_pct: float) -> float:
	var cr := clampf(crit_chance_pct, 0.0, GameConstants.CRIT_CHANCE_CAP) / 100.0
	var cd := maxf(crit_damage_pct, 100.0) / 100.0
	return 1.0 + cr * (cd - 1.0)


## 目标减伤后的剩余比例（0–1，1 = 无减伤）。
## physical 走护甲 DR（armor_damage_reduction），其余走元素抗性 DR。
static func mitigation_factor(
	target_armor: float,
	target_resist: float,
	target_level: int,
	element: String,
) -> float:
	if element == GameConstants.ELEMENT_PHYSICAL:
		return 1.0 - GameConstants.armor_damage_reduction(target_armor, target_level)
	return 1.0 - GameConstants.element_damage_reduction(target_resist, target_level)


## 完整命中结算。所有百分数参数用「百分数」存储（5 = 5%）。
## extra_dr_pct：额外减伤%（守誓者 40% 减伤等，乘算，默认 0）。
static func compute_hit(
	base_damage: float,
	crit_chance_pct: float,
	crit_damage_pct: float,
	element: String,
	element_bonus_pct: float,
	target_armor: float,
	target_resist: float,
	target_level: int,
	extra_dr_pct: float,
) -> DamageResult:
	var is_crit := roll_crit(crit_chance_pct)
	var c_mult := crit_multiplier(is_crit, crit_damage_pct)
	var elem_mult := 1.0 + maxf(element_bonus_pct, 0.0) / 100.0
	var mit := mitigation_factor(target_armor, target_resist, target_level, element)
	mit *= 1.0 - clampf(extra_dr_pct, 0.0, 100.0) / 100.0
	var final_dmg := base_damage * c_mult * elem_mult * mit
	return DamageResult.new(
		base_damage, is_crit, c_mult, element, elem_mult, mit, final_dmg,
	)


# =============================================================================
# 目标防御读取（统一兜底：无接口则按 0 甲 / 0 抗 / L1 处理）
# =============================================================================

static func target_armor(target: Node) -> float:
	if target != null and target.has_method("get_armor"):
		return float(target.get_armor())
	return 0.0


## 破甲：按攻击方 `armor_pierce`%（0 = 不变）削目标护甲后返回。
##
## 「无视 X% 护甲」= 先削甲，再进 `mitigation_factor` 的护甲 DR。
## 消费方：`PlayerController` 普攻管线（`:797` 一带）与 `SkillController._hit`（`:158` 一带）——
## 三选一「破甲」的消费入口。**默认 0 ⇒ 与修复前逐位一致**（向后兼容）。
static func pierced_armor(target_armor: float, armor_pierce_pct: float) -> float:
	if armor_pierce_pct <= 0.0:
		return target_armor
	return maxf(target_armor * (1.0 - clampf(armor_pierce_pct, 0.0, 100.0) / 100.0), 0.0)


static func target_resist(target: Node, element: String) -> float:
	if target != null and target.has_method("get_resist"):
		return float(target.get_resist(element))
	return 0.0


static func target_level(target: Node) -> int:
	if target != null and target.has_method("get_level"):
		return int(target.get_level())
	return 1
