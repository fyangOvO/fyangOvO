## 主动技能定义（数据驱动 · 自定义 Resource）
##
## 字段覆盖任务清单 2.2：主动技能 / 冷却 / 资源消耗。
## 数值口径见 GDD 0.6 节 6.6（DPS = AD × 暴击乘区 × 攻速 × SkillMult）与
## sim-report §7（SkillMult L1 = 1.8 → L20 = 2.8 为**综合系数**；单技能个体倍率见下表）。
##
## 注意：本类是**模板**。技能的实际冷却计时 / 法力消耗 / 命中结算
##       由 `scripts/combat/skill_controller.gd` 在运行时执行，本类只存定义。
##
## 数据来源：`game/data/skills/*.json`
class_name SkillData
extends Resource

## 技能形态（决定 SkillController 的施放分派；2.5 碰撞与命中判定会替换几何部分）
enum SkillType {
	SINGLE = 0, ## 单体：朝向前方 range 内最近的 1 个目标
	AOE = 1,    ## 范围：以玩家为中心 radius 内全部目标（AoE 设计基准 2.0 的主力）
	DASH = 2,   ## 位移：沿朝向冲刺并击退撞到的目标
}

const TYPE_NAMES: Array[String] = ["单体", "范围", "位移"]
const TYPE_KEYS: Array[String] = ["single", "aoe", "dash"]

## 唯一标识（如 "cleave"）
@export var id: String = ""

## UI 显示名
@export var display_name: String = ""

## 技能栏位（1/2/3，对应 project.godot 的 skill_1/skill_2/skill_3；唯一）。
## 6.4 扩充：slot 0 = 备选技能（入库但不占出战栏位，供局内成长替换选择）。
@export var slot: int = 0

## 技能形态 —— SkillType
@export var type: int = SkillType.SINGLE

## 伤害倍率（× 攻击力）。原始伤害 = 玩家攻击力 × multiplier（2.3 起走完整伤害管线）
@export var multiplier: float = 1.0

## 伤害元素（GameConstants.ELEMENT_*，默认物理）。
## 任务 2.3 拍板：普攻/技能默认物理；元素来源 = 词缀「+元素伤害」与套装特效
## （霜噬=冰、烬途=火），届时由装备/状态改写本字段。
@export var element: String = GameConstants.ELEMENT_PHYSICAL

## 冷却时间（秒）
@export var cooldown: float = 1.0

## 法力消耗（点）
@export var mana_cost: float = 0.0

## 单体技能射程（px）；范围技能用 radius；位移技能用 dash_distance。
@export var range: float = 96.0

## 范围技能半径（px）
@export var radius: float = 48.0

## 位移技能冲刺距离（px）
@export var dash_distance: float = 96.0

## 命中击退距离（px）。0 = 不击退（BOSS / 精英由阶段 2.6 免疫规则接管）
@export var knockback: float = 0.0

## 技能说明（UI 技能栏 / 教程用）
@export var description: String = ""


# =============================================================================
# 校验
# =============================================================================

## 校验数据完整性，返回错误信息数组（空数组 = 通过）
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("SkillData.id 为空")
	if display_name.is_empty():
		errors.append("技能 '%s' 缺少 display_name" % id)
	if slot < 0 or slot > 3:
		errors.append("技能 '%s' 的 slot 非法：%d（须 0–3，0 = 备选）" % [id, slot])
	if type < 0 or type > SkillType.DASH:
		errors.append("技能 '%s' 的 type 非法：%d" % [id, type])
	if multiplier <= 0.0:
		errors.append("技能 '%s' 的 multiplier 必须 > 0" % id)
	if not GameConstants.ELEMENTS.has(element):
		errors.append("技能 '%s' 的 element 非法：%s（须 ∈ ELEMENTS）" % [id, element])
	if cooldown < 0.0:
		errors.append("技能 '%s' 的 cooldown 必须 >= 0" % id)
	if mana_cost < 0.0:
		errors.append("技能 '%s' 的 mana_cost 必须 >= 0" % id)
	match type:
		SkillType.SINGLE:
			if range <= 0.0:
				errors.append("单体技能 '%s' 的 range 必须 > 0" % id)
		SkillType.AOE:
			if radius <= 0.0:
				errors.append("范围技能 '%s' 的 radius 必须 > 0" % id)
		SkillType.DASH:
			if dash_distance <= 0.0:
				errors.append("位移技能 '%s' 的 dash_distance 必须 > 0" % id)
	return errors
