## 技能控制器（任务 2.2 · 主动技能 / 冷却 / 资源消耗）
##
## 职责：
##   · 从 ConfigLoader 加载技能定义（data/skills/*.json），与技能栏 1/2/3 对应
##   · 冷却计时（独立每技能）
##   · 施放管线：冷却检查 → 法力检查 → 扣费 → 按 SkillType 分派效果
##   · 命中结算出口：对目标调 `take_damage(amount, source)`（2.3 接入完整伤害公式）
##
## 设计约束：
##   · 本组件**不移动玩家**。位移类技能（DASH）由 PlayerController 执行物理位移，
##     完成后回调本组件结算撞击伤害与击退。
##   · 目标查找复用 PlayerController 的公开接口（战斗判定辅助，2.5 替换几何部分）。
##   · 目标约定：所有可受击实体加入 `enemies` 组，并实现
##     `take_damage(amount: float, source: Node)` 与 `apply_knockback(offset: Vector2)`。
class_name SkillController
extends Node

## 宿主玩家（提供朝向 / 位置 / 攻击力 / 位移）
@export var player_path: NodePath
var _player: PlayerController = null

## 已加载技能，按技能栏顺序（id → SkillData）
var _skills: Dictionary = {}

## 冷却剩余时间（id → 秒，>0 表示冷却中）
var _cooldowns: Dictionary = {}


func _ready() -> void:
	if not player_path.is_empty():
		_player = get_node_or_null(player_path) as PlayerController
	_load_skills()


## 从存档加载出战技能（2026-09-22 步骤 3：职业专属技能池 + 技能栏重排）。
## 出战栏 = `SaveData.skill_bar`（3 个技能 id，顺序 = 栏位 1/2/3）；
## 取栏链：存档栏（非空）> 职业默认栏 > 战士默认栏（兼容无档测试 / 旧全局 slot≥1 行为）。
func _load_skills() -> void:
	_skills.clear()
	_cooldowns.clear()
	var ids := _equipped_skill_ids()
	for id in ids:
		var data := ConfigLoader.get_skill(id)
		if data != null:
			_skills[id] = data
			_cooldowns[id] = 0.0


## 出战技能 id 列表（取栏链，见 _load_skills 注释）
func _equipped_skill_ids() -> Array[String]:
	var data := SaveManager.current_data
	if data != null:
		if not data.skill_bar.is_empty():
			return data.skill_bar.duplicate()
		return ConfigLoader.class_default_skill_bar(data.class_id)
	return ConfigLoader.class_default_skill_bar(GameConstants.CLASS_DEFAULT)


# =============================================================================
# 查询
# =============================================================================

## 技能栏第 index 个（0 基）技能的 id；越界返回空串。
## 顺序 = _load_skills 按 slot 排序后的加载顺序（裂斩/旋刃/突进 = 1/2/3）。
func get_skill_id_at(index: int) -> String:
	if index < 0 or index >= _skills.size():
		return ""
	return String(_skills.keys()[index])


func get_skill_data(id: String) -> SkillData:
	return _skills.get(id, null)


func get_cooldown_remaining(id: String) -> float:
	return float(_cooldowns.get(id, 0.0))


func is_on_cooldown(id: String) -> bool:
	return get_cooldown_remaining(id) > 0.0


# =============================================================================
# 主循环
# =============================================================================

func _process(delta: float) -> void:
	tick_cooldowns(delta)


## 推进全部冷却计时（_process 调用；验证脚本可手动推进以确定性断言）
func tick_cooldowns(delta: float) -> void:
	for id in _cooldowns:
		if _cooldowns[id] > 0.0:
			_cooldowns[id] = maxf(float(_cooldowns[id]) - delta, 0.0)


# =============================================================================
# 施放
# =============================================================================

## 尝试施放技能。返回 true = 已施放（扣除法力并进入冷却）。
func try_cast(id: String) -> bool:
	if _player == null:
		return false
	var data := get_skill_data(id)
	if data == null:
		return false
	if is_on_cooldown(id):
		return false

	var mana: ManaPool = _player.get_mana_pool()
	if mana == null or not mana.try_spend(data.mana_cost):
		return false

	_cooldowns[id] = data.cooldown

	# 任务 11.9 埋点：一次施放的命中数 = 这段时间里 `_hit()` 被调了几次。
	# 三个分支**全部同步**（`perform_skill_dash` 内部直接 `move_and_collide` +
	# `on_dash_hit`，不跨帧），所以这一对 begin/end 能框住全部命中。
	# 放空（0 命中）同样记成一次 casts，另计 `whiffs` —— 这个数不能丢：
	# 「AoE 平均命中 3.4」与「平均 3.4 但 40% 打空」是两种完全不同的手感。
	CombatMetrics.begin_cast(id, data.type == SkillData.SkillType.AOE)
	match data.type:
		SkillData.SkillType.SINGLE:
			_execute_single(data)
		SkillData.SkillType.AOE:
			_execute_aoe(data)
		SkillData.SkillType.DASH:
			_player.perform_skill_dash(data)
	CombatMetrics.end_cast()
	return true


## 单体：朝向前方 60° 扇区内、range 内**最近**的一个目标
func _execute_single(data: SkillData) -> void:
	var targets := _player.find_targets_in_arc(data.range, GameConstants.ATTACK_ARC_DEG)
	if targets.is_empty():
		return
	_hit(targets[0], data, data.knockback)


## 范围：以玩家为中心、radius 内全部目标
func _execute_aoe(data: SkillData) -> void:
	var targets := _player.find_targets_in_radius(data.radius)
	for target in targets:
		_hit(target, data, data.knockback)


## 位移技能撞击结算（PlayerController.perform_skill_dash 完成后回调）
func on_dash_hit(target: Node, data: SkillData) -> void:
	if target == null:
		return
	_hit(target, data, data.knockback)


## 统一命中结算：伤害（2.3 完整管线）+ 击退 + 事件
func _hit(target: Node, data: SkillData, knockback_px: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var base := _player.get_attack_damage() * data.multiplier
	# 任务 2.3 伤害管线：技能元素（默认物理，词缀/套装可改写）→ 暴击 → 目标减伤
	var result := DamageCalc.compute_hit(
		base,
		_player.get_crit_chance(),
		_player.get_crit_damage(),
		data.element,
		0.0,
		# 破甲：先按玩家 armor_pierce% 削目标护甲（默认 0 ⇒ 与修复前一致）
		DamageCalc.pierced_armor(
			DamageCalc.target_armor(target), _player.get_combat_stat("armor_pierce")),
		DamageCalc.target_resist(target, data.element),
		DamageCalc.target_level(target),
		0.0,
	)
	if target.has_method("take_damage"):
		target.take_damage(result.final_damage, _player)
		# 任务 11.9 埋点：只统计**真的落到目标身上**的那一次
		# （没有 `take_damage` 的目标不算命中，否则「命中数」会虚高）
		CombatMetrics.note_skill_hit()
	if knockback_px > 0.0 and target.has_method("apply_knockback"):
		var dir := _player.get_facing_vector()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		target.apply_knockback(dir * knockback_px)
	EventBus.damage_dealt.emit(target, result.final_damage, result.crit, result.element)
