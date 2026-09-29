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
##
## 2026-09-28（第一步 B0 · 工单 1-D1）：
##   · `SkillType` 由 4 值扩到 **7 值**（新增 PROJECTILE / GROUND / BUFF）
##   · 新增 13 个字段（持续区域 / 投射物 / 增益 / 召唤 / 眩晕 / 分支）
##   · `validate()` 按新形态补分支；`multiplier <= 0` 校验收紧为「仅 BUFF / SUMMON 可为 0」
##
## 2026-09-29（第三步 B3-5 · 工单 1-L3）：
##   · 新增 3 字段：`chain_decay_pct` / `split_count` / `split_damage_pct`
##     —— 承载 `rune_chain`（连锁衰减）与 `rune_split`（命中分裂）的语义
##     （此前这两个符文修饰**被 `_apply_rune_modifiers` 静默丢弃**）
class_name SkillData
extends Resource

## 技能形态（决定 SkillController 的施放分派；2.5 碰撞与命中判定会替换几何部分）
##
## ⚠️ **顺序即 `config_loader._to_skill_type()` 的 index**（按 `TYPE_KEYS` 字符串查找），
##    且 `SkillData.type` 只存在运行时内存、**不进存档** ⇒ 2026-09-28 按策划案
##    重排（`SUMMON` 由 3 → 5）是安全的。**此后只能在尾部追加，不可再重排。**
enum SkillType {
	SINGLE = 0,     ## 单体：朝向前方 range 内最近的 1 个目标
	AOE = 1,        ## 范围：以玩家为中心 radius 内全部目标（AoE 设计基准 2.0 的主力）
	DASH = 2,       ## 位移：沿朝向冲刺并击退撞到的目标
	PROJECTILE = 3, ## 投射物：发射飞行弹道，命中结算（新增）
	GROUND = 4,     ## 持续区域：地面生成区域实体，每 tick 结算（新增）
	SUMMON = 5,     ## 召唤：在玩家脚下生成友方召唤物（技能体系 §12；无直接伤害）
	BUFF = 6,       ## 增益：对自身施加增益 / 护盾（新增）
}

## ⚠️ 顺序即 `config_loader._to_skill_type()` 的 index ⇒ **只能在尾部追加**，不可重排。
const TYPE_NAMES: Array[String] = ["单体", "范围", "位移", "投射物", "持续区域", "召唤", "增益"]
const TYPE_KEYS: Array[String] = ["single", "aoe", "dash", "projectile", "ground", "summon", "buff"]

## 唯一标识（如 "cleave"）
@export var id: String = ""

## UI 显示名
@export var display_name: String = ""

## 技能栏位（1/2/3，对应 project.godot 的 skill_1/skill_2/skill_3；唯一）。
## 6.4 扩充：slot 0 = 备选技能（入库但不占出战栏位，供局内成长替换选择）。
@export var slot: int = 0

## 解鎖門檻 · 賬號等級（第一步 B4 · 工单 1-L11）。`0` = 無等級門檻。
## 数据源 `skills.json`；節奏表见 `01-技能体系.md` §9.2（L3/L5/L7/L9/L12/L15/L18/L22）。
## ⚠️ 解鎖狀態**不進存檔**：由「賬號等級 + 已通關關卡」推導（见 `UnlockSystem`）。
@export var unlock_level: int = 0

## 解鎖門檻 · 需**首通**的關卡 id（如 `ch1_l06`）。空串 = 無 BOSS 門檻。
## 数据源 `skills.json`；每職 1 個招牌技綁定章節 BOSS 首通（§9.2）。
@export var unlock_boss: String = ""

## 技能形态 —— SkillType
@export var type: int = SkillType.SINGLE

## 伤害倍率（× 攻击力）。原始伤害 = 玩家攻击力 × multiplier（2.3 起走完整伤害管线）
##
## ⚠️ BUFF / SUMMON **合法为 0**（无直接伤害）。GROUND 的此字段是**每 tick 倍率**，
##    总伤害 = `impact_multiplier + multiplier × (duration ÷ tick_interval)`。
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
# 新增字段（第一步 B0 · 工单 1-D1）
# =============================================================================

## 持续时间（秒）。适用：GROUND（区域存活）/ BUFF（增益时长）/ SUMMON（召唤物存活）。
@export var duration: float = 0.0

## 结算间隔（秒）。适用：GROUND 每 tick 结算；AOE 的「滞留」分支复用。
@export var tick_interval: float = 0.0

## 落地一次性伤害倍率（× 攻击力）。仅 GROUND 使用（如陨石落点爆发），默认 0 = 无。
@export var impact_multiplier: float = 0.0

## 投射物飞行速度（px/s）。仅 PROJECTILE 使用。
@export var projectile_speed: float = 0.0

## 投射物数量（≥1）。仅 PROJECTILE 使用；>1 时按 `spread_deg` 扇形展开。
@export var projectile_count: int = 0

## 扇形张角（度）。仅 PROJECTILE 多发射击使用；0 = 全部重叠同向。
@export var spread_deg: float = 0.0

## 穿透数量。仅 PROJECTILE 使用：0 = 命中即消失，N = 可多命中 N 个额外目标。
@export var pierce_count: int = 0

## 连锁弹射目标数。PROJECTILE / SINGLE 使用；0 = 不连锁。
@export var chain_count: int = 0

## 连锁每跳的伤害衰减（%）。仅 `chain_count > 0` 生效；0 = 不衰减（每跳全额）。
## 数据源：`rune_chain` 的 `chain_decay_pct = 25.0`（策划案 §2.2）。
## 技能自带连锁（`lightning_chain` chain_count=2）未声明 ⇒ 保持 0（全额弹射），
## 与技能描述「造成 220% 攻击力闪电伤害」一致。
@export var chain_decay_pct: float = 0.0

## 命中后分裂出的子投射物数量（`rune_split` 的 `on_hit_split.count`）；0 = 不分裂。
## 子投射物从命中点向四周放射，飞行距离/存活见 `GameConstants.PROJECTILE_SPLIT_*`。
@export var split_count: int = 0

## 分裂子投射物的伤害占母弹的百分比（`rune_split` 的 `on_hit_split.damage_pct`）。
@export var split_damage_pct: float = 0.0

## 召唤物 id（= `assets/pack/creatures/<id>/` 目录名）。仅 SUMMON 使用。
## ⚠️ 与技能 `id` **不必相同**（如技能 `spirit_wolf` → 召唤物 `summon_spirit_wolf`）。
@export var summon_id: String = ""

## 增益 id（写入 `RunBuffSystem` 的 buffs 字典键）。仅 BUFF 使用。
@export var buff_id: String = ""

## 眩晕时长（秒）。命中时施加；0 = 不眩晕。
@export var stun_duration: float = 0.0

## 分支 A / B 的 id（技能等级达 5 时二选一；模板见 `data/skills/branches.json`）。
## 空串 = 尚未选择（走模板默认值）。运行时由技能面板写入。
@export var branch_a: String = ""
@export var branch_b: String = ""


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
	# 解鎖門檻（1-L11）：等級門檻不可為負；BOSS 門檻（若有）不可與等級門檻同時缺省
	if unlock_level < 0:
		errors.append("技能 '%s' 的 unlock_level 不能为负：%d" % [id, unlock_level])
	if unlock_level <= 0 and unlock_boss.is_empty():
		errors.append("技能 '%s' 既无等级门槛也无 BOSS 门槛（会永久锁死）" % id)
	if type < 0 or type > SkillType.BUFF:
		errors.append("技能 '%s' 的 type 非法：%d" % [id, type])
	# ⚠️ multiplier 校验收紧（原为「必须 > 0」）：BUFF / SUMMON 无直接伤害倍率，合法为 0。
	if multiplier < 0.0:
		errors.append("技能 '%s' 的 multiplier 不能为负：%s" % [id, multiplier])
	elif is_zero_approx(multiplier) and not _type_allows_zero_multiplier():
		errors.append("技能 '%s' 的 multiplier 必须 > 0（仅 BUFF / SUMMON 可为 0）" % id)
	if not GameConstants.ELEMENTS.has(element):
		errors.append("技能 '%s' 的 element 非法：%s（须 ∈ ELEMENTS）" % [id, element])
	if cooldown < 0.0:
		errors.append("技能 '%s' 的 cooldown 必须 >= 0" % id)
	if mana_cost < 0.0:
		errors.append("技能 '%s' 的 mana_cost 必须 >= 0" % id)
	if duration < 0.0:
		errors.append("技能 '%s' 的 duration 必须 >= 0" % id)
	if tick_interval < 0.0:
		errors.append("技能 '%s' 的 tick_interval 必须 >= 0" % id)
	if impact_multiplier < 0.0:
		errors.append("技能 '%s' 的 impact_multiplier 必须 >= 0" % id)
	if projectile_speed < 0.0:
		errors.append("技能 '%s' 的 projectile_speed 必须 >= 0" % id)
	if projectile_count < 0:
		errors.append("技能 '%s' 的 projectile_count 必须 >= 0" % id)
	if spread_deg < 0.0:
		errors.append("技能 '%s' 的 spread_deg 必须 >= 0" % id)
	if pierce_count < 0:
		errors.append("技能 '%s' 的 pierce_count 必须 >= 0" % id)
	if chain_count < 0:
		errors.append("技能 '%s' 的 chain_count 必须 >= 0" % id)
	if chain_decay_pct < 0.0:
		errors.append("技能 '%s' 的 chain_decay_pct 必须 >= 0" % id)
	if split_count < 0:
		errors.append("技能 '%s' 的 split_count 必须 >= 0" % id)
	if split_damage_pct < 0.0:
		errors.append("技能 '%s' 的 split_damage_pct 必须 >= 0" % id)
	# 分裂若声明了数量却没给伤害占比 ⇒ 子投射物会打出 0 伤害（静默无效果），必须拦。
	if split_count > 0 and is_zero_approx(split_damage_pct):
		errors.append("技能 '%s' 的 split_count=%d 但 split_damage_pct 为 0（子投射物无伤害）"
			% [id, split_count])
	if stun_duration < 0.0:
		errors.append("技能 '%s' 的 stun_duration 必须 >= 0" % id)
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
		SkillType.PROJECTILE:
			if range <= 0.0:
				errors.append("投射物技能 '%s' 的 range 必须 > 0" % id)
			if projectile_speed <= 0.0:
				errors.append("投射物技能 '%s' 的 projectile_speed 必须 > 0" % id)
			if projectile_count < 1:
				errors.append("投射物技能 '%s' 的 projectile_count 必须 >= 1" % id)
			if projectile_count > 1 and spread_deg <= 0.0:
				errors.append("投射物技能 '%s' 有 %d 发但 spread_deg 为 0（会全部重叠同向）"
					% [id, projectile_count])
		SkillType.GROUND:
			if radius <= 0.0:
				errors.append("持续区域技能 '%s' 的 radius 必须 > 0" % id)
			if duration <= 0.0:
				errors.append("持续区域技能 '%s' 的 duration 必须 > 0" % id)
			if tick_interval <= 0.0:
				errors.append("持续区域技能 '%s' 的 tick_interval 必须 > 0" % id)
		SkillType.SUMMON:
			# 召唤技能不产生直接命中几何（伤害/存活/比例由召唤物自身定义）。
			if summon_id.is_empty():
				errors.append("召唤技能 '%s' 缺少 summon_id" % id)
			if duration <= 0.0:
				errors.append("召唤技能 '%s' 的 duration 必须 > 0" % id)
		SkillType.BUFF:
			if buff_id.is_empty():
				errors.append("增益技能 '%s' 缺少 buff_id" % id)
			if duration <= 0.0:
				errors.append("增益技能 '%s' 的 duration 必须 > 0" % id)
	return errors


## 该形态是否允许 `multiplier == 0`（无直接伤害倍率）
func _type_allows_zero_multiplier() -> bool:
	return type == SkillType.BUFF or type == SkillType.SUMMON


## 是否为「无直接伤害」的形态（BUFF / SUMMON）——供 UI 与统计判断
func is_non_damaging() -> bool:
	return type == SkillType.BUFF or type == SkillType.SUMMON


## GROUND 的总伤害倍率（含全部 tick 与落地爆发）。非 GROUND 返回 `multiplier`。
## 口径见 `01-技能体系.md` §5.1：`impact + multiplier × (duration ÷ tick_interval)`。
func total_damage_multiplier() -> float:
	if type != SkillType.GROUND or tick_interval <= 0.0:
		return multiplier
	return impact_multiplier + multiplier * (duration / tick_interval)


## 单次施放的 DPS 系数（总伤害 ÷ 冷却；§5.1 的统一标尺）。
## 非伤害形态（BUFF / SUMMON）返回 0。
func dps_coefficient() -> float:
	if is_non_damaging() or cooldown <= 0.0:
		return 0.0
	var shots := float(maxi(projectile_count, 1)) if type == SkillType.PROJECTILE else 1.0
	return total_damage_multiplier() * shots / cooldown
