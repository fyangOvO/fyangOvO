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
##
## 2026-09-28（第一步 B0 · 工单 1-L2）：
##   ① `_hit()` 乘上**技能等级系数**（`1 + 0.08 × (L-1)`）—— 🔴 复活第二步死钩子 `skill_level`
##   ② `try_cast()` 补 4 个新形态的 match 分支（PROJECTILE / GROUND / BUFF）
##   ③ 符文修饰器在施放前套用（字段覆盖 / 乘算修饰）
class_name SkillController
extends Node

## 宿主玩家（提供朝向 / 位置 / 攻击力 / 位移）
@export var player_path: NodePath
var _player: PlayerController = null

## 已加载技能，按技能栏顺序（id → SkillData）
var _skills: Dictionary = {}

## 冷却剩余时间（id → 秒，>0 表示冷却中）
var _cooldowns: Dictionary = {}

## 已装配符文：`{skill_id: [rune_id, ...]}`（最多 3 槽）。
##
## ⚠️ **数据源尚未落地**：符文槽的存 / 取（`SaveData` 字段 + 技能面板 UI）
##    属工单 `1-L9`（B4）。本类只提供 `set_equipped_runes()` 入口 + 套用逻辑，
##    默认空 ⇒ 行为与「无符文」完全一致（向后兼容）。
##    由 `tools/verify_skills.gd` 的符文段直接注入验证，**不是死代码**。
var _equipped_runes: Dictionary = {}

## 已警告过的「形态实现未落地」标记（避免每次施放都刷屏）
var _pending_form_warned: Dictionary = {}

## 形态 → 尚未落地的实现工单。落地后从表中删除即可（B0 的过渡实现随之失效）。
const PENDING_FORM_IMPL: Dictionary = {
	SkillData.SkillType.PROJECTILE: "1-L3（B3）projectile.gd",
	SkillData.SkillType.GROUND: "1-L4（B3）ground_area.gd",
	SkillData.SkillType.BUFF: "3-B1（B4）BuffComponent",
}


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
	_warn_pending_forms()


## 出战技能 id 列表（取栏链，见 _load_skills 注释）
func _equipped_skill_ids() -> Array[String]:
	var data := SaveManager.current_data
	if data != null:
		if not data.skill_bar.is_empty():
			return data.skill_bar.duplicate()
		return ConfigLoader.class_default_skill_bar(data.class_id)
	return ConfigLoader.class_default_skill_bar(GameConstants.CLASS_DEFAULT)


## 出战栏里若有「形态实现未落地」的技能，**加载时打印一次明确警告**。
##
## 为什么要这条：B0 只交付数据地基 + 技能等级，`1-L3/L4`（投射物 / 持续区域实体）与
## `3-B1`（BuffComponent）在 B3/B4。若不给提示，玩家装上这些技能后
## **什么都不会发生且零报错**——正是本项目反复栽的「静默失败」。
func _warn_pending_forms() -> void:
	var pending: Array[String] = []
	for id in _skills:
		var data: SkillData = _skills[id]
		if PENDING_FORM_IMPL.has(data.type):
			pending.append("%s(%s → 待 %s)" % [id, SkillData.TYPE_NAMES[data.type],
				PENDING_FORM_IMPL[data.type]])
	if not pending.is_empty():
		push_warning("[SkillController] 出战栏含过渡实现技能（B0 简化版，实体待后续批次）：%s"
			% ", ".join(pending))


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
# 符文装配（数据源待 1-L9/B4；本类只提供入口与套用逻辑）
# =============================================================================

## 设置某技能已装配的符文（最多 3 槽，超出部分忽略）。传空数组 = 卸下全部。
func set_equipped_runes(skill_id: String, rune_ids: Array) -> void:
	var kept: Array = []
	for rid in rune_ids:
		if kept.size() >= 3:
			break
		if ConfigLoader.runes.has(String(rid)):
			kept.append(String(rid))
	_equipped_runes[skill_id] = kept


func get_equipped_runes(skill_id: String) -> Array:
	return _equipped_runes.get(skill_id, [])


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

	# 符文修饰器（第一步 §2.2）：形态 / 元素 / 数值改写在**扣费与分派之前**套用。
	# 未装配符文时返回原对象（零开销、零行为变化）。
	var effective := _apply_rune_modifiers(data, get_equipped_runes(id))

	var mana: ManaPool = _player.get_mana_pool()
	if mana == null or not mana.try_spend(effective.mana_cost):
		return false

	_cooldowns[id] = effective.cooldown

	# 任务 11.9 埋点：一次施放的命中数 = 这段时间里 `_hit()` 被调了几次。
	# 七个分支**全部同步**（`perform_skill_dash` 内部直接 `move_and_collide` +
	# `on_dash_hit`，不跨帧），所以这一对 begin/end 能框住全部命中。
	# 放空（0 命中）同样记成一次 casts，另计 `whiffs` —— 这个数不能丢：
	# 「AoE 平均命中 3.4」与「平均 3.4 但 40% 打空」是两种完全不同的手感。
	CombatMetrics.begin_cast(id, effective.type == SkillData.SkillType.AOE)
	match effective.type:
		SkillData.SkillType.SINGLE:
			_execute_single(effective)
		SkillData.SkillType.AOE:
			_execute_aoe(effective)
		SkillData.SkillType.DASH:
			_player.perform_skill_dash(effective)
		SkillData.SkillType.PROJECTILE:
			_execute_projectile(effective)
		SkillData.SkillType.GROUND:
			_execute_ground(effective)
		SkillData.SkillType.SUMMON:
			_execute_summon(effective)
		SkillData.SkillType.BUFF:
			_execute_buff(effective)
		_:
			push_warning("[SkillController] 技能 '%s' 的形态 %d 无分派分支（已被静默吞掉）"
				% [id, effective.type])
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


## 投射物（第一步 §3.2）。
##
## ⚠️ **B0 过渡实现**：`1-L3`（B3）会新建 `scripts/combat/projectile.gd` 承载真实飞行弹道
## （速度 / 射程 / 穿透 / 分裂 / 连锁）。在那之前，这里按**同一伤害口径**即时结算：
## 沿朝向 `range` 内扇区命中，伤害 = `multiplier × projectile_count`（§5.1 的「全中」口径）
## ⇒ 伤害期望与真实弹道一致（仅少了飞行时间），不会因过渡而改变数值平衡。
func _execute_projectile(data: SkillData) -> void:
	var targets := _player.find_targets_in_arc(data.range, GameConstants.ATTACK_ARC_DEG)
	if targets.is_empty():
		return
	_hit(targets[0], data, data.knockback)


## 持续区域（第一步 §3.2）。
##
## ⚠️ **B0 过渡实现**：`1-L4`（B3）会新建 `scripts/combat/ground_area.gd` 承载
## 每 tick 结算与到期释放。在那之前，这里在玩家位置做**一次性结算**，
## 伤害 = `total_damage_multiplier()`（= 落地爆发 + 全部 tick 之和，口径见 §5.1）
## ⇒ 总伤害不变，只是从「分摊到 duration」变成「一次打完」。
func _execute_ground(data: SkillData) -> void:
	var targets := _player.find_targets_in_radius(data.radius)
	for target in targets:
		_hit(target, data, data.knockback)


## 增益（第一步 §3.2）。
##
## ⚠️ **B0 过渡实现**：时限 + 叠层 + 过期清理由 `3-B1`（B4）的 `BuffComponent` 承载。
## 在那之前，这里把 `buff_id` 写进 `RunBuffSystem.buffs`（叠层语义已有），
## 但 `RunBuffSystem.to_calculator_buffs()` 需要 `buff_id → pct` 的定义表才能换算成属性
## ⇒ **目前会生效为空**，故此处额外打一次明确警告（避免静默）。
func _execute_buff(data: SkillData) -> void:
	var run := _find_run_buff_system()
	if run == null:
		push_warning("[SkillController] 增益技能 '%s' 找不到 RunBuffSystem，效果未生效" % data.id)
		return
	run.apply_option(data.buff_id)
	_warn_once(data.type, "[SkillController] 增益技能 '%s'（buff_id=%s）已记入 RunBuffSystem，"
		% [data.id, data.buff_id]
		+ "但 buff_id→属性 的换算表尚未落地（待 3-B1/B4）⇒ 实际属性暂无变化")


## 从场景树里找 `RunBuffSystem`（`level_scene` 通过 `get_run_buff_system()` 暴露）。
func _find_run_buff_system() -> RunBuffSystem:
	if _player == null:
		return null
	var host: Node = _player.get_parent()
	if host == null:
		return null
	if host.has_method("get_run_buff_system"):
		return host.call("get_run_buff_system") as RunBuffSystem
	return null


func _warn_once(key: int, msg: String) -> void:
	if _pending_form_warned.has(key):
		return
	_pending_form_warned[key] = true
	push_warning(msg)


## 位移技能撞击结算（PlayerController.perform_skill_dash 完成后回调）
func on_dash_hit(target: Node, data: SkillData) -> void:
	if target == null:
		return
	_hit(target, data, data.knockback)


## 召唤（技能体系 §12）：在玩家脚下生成**友方召唤物**。
##
## 召唤物 id 取 `data.summon_id`（**不是** `data.id`）——两者不必相同：
## 技能 `spirit_wolf` → 召唤物 `summon_spirit_wolf`。`Summon.spawn()` 内部会播
## `summon_circle` 脚下法阵（FX 单一来源，此处不重复播，避免出现双法阵）。
##
## 同一 id 上限 1 只（裁定）：已有同名召唤物时**取代**（旧的解召 → 新的生成）。
## 理由：冷却（12s / 14s）短于存活（15s），不设上限会自然叠出第 2 只；
## 取代＝不叠加、也不浪费这次冷却。被取代者走 `queue_free()`（解召，非死亡，
## 不触发 `unit_died`）。
func _execute_summon(data: SkillData) -> void:
	var host: Node = _player.get_parent()
	if host == null:
		return
	var summon_id := data.summon_id if not data.summon_id.is_empty() else data.id
	for n in get_tree().get_nodes_in_group(&"summons"):
		if n != null and is_instance_valid(n) and n.has_method("get_summon_id") \
				and str(n.call("get_summon_id")) == summon_id:
			n.queue_free()
	Summon.spawn(host, _player, summon_id, _player.global_position)


# =============================================================================
# 符文修饰器（第一步 §2.2）
# =============================================================================

## 可**直接覆盖字段**的修饰键（runes.json `_meta.modifier_semantics.字段覆盖`）
const RUNE_FIELD_KEYS: Array[String] = [
	"type", "element", "pierce_count", "projectile_count", "chain_count",
	"duration", "tick_interval", "projectile_speed",
]
## **乘算**修饰键（带符号增量：+25 = 放大 25%，-25 = 缩小 25%）
const RUNE_PCT_KEYS: Array[String] = [
	"multiplier_pct", "cooldown_pct", "mana_cost_pct", "radius_pct", "range_pct",
]

## 套用符文修饰：返回**副本**（不改动注册表里的模板对象）。
## 未装配符文 ⇒ 原样返回 `data`（零开销）。
##
## ⚠️ 只处理「字段覆盖 + 乘算修饰」；`stun_chance` / `life_leech_pct` / `on_hit_slow` 等
## **附加效果**需要战斗钩子（`3-B1`/`3-K*`），不在本函数职责内。
func _apply_rune_modifiers(data: SkillData, rune_ids: Array) -> SkillData:
	if rune_ids.is_empty():
		return data
	var out: SkillData = data.duplicate()
	for rid in rune_ids:
		var rune: Dictionary = ConfigLoader.runes.get(String(rid), {})
		var mods: Dictionary = rune.get("modifiers", {})
		for key in mods:
			var k := String(key)
			var v: Variant = mods[key]
			if k in RUNE_FIELD_KEYS:
				_apply_rune_field(out, k, v)
			elif k in RUNE_PCT_KEYS:
				_apply_rune_pct(out, k, float(v))
	return out


func _apply_rune_field(out: SkillData, key: String, value: Variant) -> void:
	match key:
		"type":
			var idx := SkillData.TYPE_KEYS.find(String(value).to_lower())
			if idx >= 0:
				out.type = idx
			else:
				push_warning("[SkillController] 符文覆盖了未知技能形态 '%s'，已忽略" % str(value))
		"element":
			var elem := String(value)
			if GameConstants.ELEMENTS.has(elem):
				out.element = elem
		"pierce_count":
			out.pierce_count = int(value)
		"projectile_count":
			out.projectile_count = int(value)
		"chain_count":
			out.chain_count = int(value)
		"duration":
			out.duration = float(value)
		"tick_interval":
			out.tick_interval = float(value)
		"projectile_speed":
			out.projectile_speed = float(value)


func _apply_rune_pct(out: SkillData, key: String, pct: float) -> void:
	var factor := 1.0 + pct / 100.0
	match key:
		"multiplier_pct":
			out.multiplier *= factor
		"cooldown_pct":
			out.cooldown = maxf(out.cooldown * factor, 0.0)
		"mana_cost_pct":
			out.mana_cost = maxf(out.mana_cost * factor, 0.0)
		"radius_pct":
			out.radius *= factor
		"range_pct":
			out.range *= factor


# =============================================================================
# 命中结算
# =============================================================================

## 本次命中的**有效倍率** = 技能倍率（GROUND 含全部 tick）× 技能等级系数。
##
## 🔴 技能等级系数是本项目**第二步死钩子 `skill_level` 的唯一复活点**（策划案 §2.1）。
##    公式：`1 + 0.08 × (level - 1)` ⇒ L1 = ×1.00 / L4 = ×1.24 / L7 = ×1.48 / L10 = ×1.72。
##    **不影响**冷却 / 蓝耗 / 范围（避免与 `cooldown_reduction` 双重计入）。
func _effective_multiplier(data: SkillData) -> float:
	if _player == null:
		return data.total_damage_multiplier()
	return data.total_damage_multiplier() * _player.get_skill_level_multiplier()


## 统一命中结算：伤害（2.3 完整管线）+ 击退 + 事件
func _hit(target: Node, data: SkillData, knockback_px: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var base := _player.get_attack_damage() * _effective_multiplier(data)
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
