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
##
## 2026-09-29（第三步 B3-5 · 工单 1-L3 / 1-L4）：
##   ① PROJECTILE / GROUND 由 B0 的**过渡实现**（即时一次性结算）改为**真实实体**
##      （`Projectile` / `GroundArea`，纯脚本 + 代码生成占位视觉）
##   ② `_hit()` 增 `raw_multiplier` / `damage_scale` 两参 —— 支撑「每 tick 倍率」与
##      「连锁衰减 / 分裂占比」（此前只能用 `total_damage_multiplier()` 一种口径）
##   ③ 符文修饰器支持 `on_hit_split`（嵌套 dict）与 `chain_decay_pct`
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
##
## 2026-09-29（B3-5）：PROJECTILE / GROUND 已由 `Projectile` / `GroundArea` 落地 ⇒ 移除。
const PENDING_FORM_IMPL: Dictionary = {
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


## 冷却减半（传奇特效 `resource_refund.cooldown_half`，第三步 3-K5 的消费点）。
## 下限仍守 `SKILL_MIN_COOLDOWN_SEC`（0.2s）—— 防「多次减半」穿透零冷却兜底。
func halve_cooldown(id: String) -> void:
	if not _cooldowns.has(id):
		return
	_cooldowns[id] = maxf(float(_cooldowns[id]) * 0.5, GameConstants.SKILL_MIN_COOLDOWN_SEC)


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

	# 冷却缩减 / 技能减耗（第二步 2-L5/L6 · 第三步 X3/X4；`02-装备属性.md` §7.4 给了精确码）：
	#   两者都是**乘区**，**硬顶 70%**（`COOLDOWN_REDUCTION_CAP_PCT` / `SKILL_COST_REDUCTION_CAP_PCT`）
	#   —— 无上限会导致 100% 减免 ⇒ 技能无 CD / 负耗蓝回蓝，游戏性崩塌。
	#   ⚠️ 作用在 `effective`（已过符文修饰）之上，**不丢符文**的 `cooldown_pct` / `mana_cost_pct`。
	#   ⚠️ 未注入属性时两值均为 0 ⇒ 与接线前**逐位一致**（向后兼容）。
	var cdr := clampf(_player.get_combat_stat("cooldown_reduction"), 0.0,
		GameConstants.COOLDOWN_REDUCTION_CAP_PCT)
	var cost_red := clampf(_player.get_combat_stat("skill_cost_reduction"), 0.0,
		GameConstants.SKILL_COST_REDUCTION_CAP_PCT)

	var mana: ManaPool = _player.get_mana_pool()
	# X4：减耗 clamp ≥ 0 —— 负数耗蓝会变成**回蓝**（§4.4 明令禁止）
	var real_cost := maxf(effective.mana_cost * (1.0 - cost_red / 100.0), 0.0)
	if mana == null or not mana.try_spend(real_cost):
		return false

	# X3：冷却 clamp ≥ `SKILL_MIN_COOLDOWN_SEC`（0.2s）—— 防零冷却兜底
	_cooldowns[id] = maxf(effective.cooldown * (1.0 - cdr / 100.0),
		GameConstants.SKILL_MIN_COOLDOWN_SEC)

	# 任务 11.9 埋点：一次施放的命中数 = 这段时间里 `_hit()` 被调了几次。
	# ⚠️ B3-5 起这条「同步窗口」只对**同步结算**的形态成立（单体 / 范围 / 位移 / 召唤 / 增益）；
	#    投射物（要飞）与持续区域（按 tick 分摊）的命中落在窗口**之外**，走 `deferred_hits`
	#    ⇒ 此刻 0 命中不等于打空，命中由 `note_deferred_hit()` 补记。
	# 放空（0 命中）同样记成一次 casts，另计 `whiffs` —— 这个数不能丢：
	# 「AoE 平均命中 3.4」与「平均 3.4 但 40% 打空」是两种完全不同的手感。
	CombatMetrics.begin_cast(id, effective.type == SkillData.SkillType.AOE)
	var deferred_hits := effective.type == SkillData.SkillType.PROJECTILE \
		or effective.type == SkillData.SkillType.GROUND
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
	CombatMetrics.end_cast(deferred_hits)
	# 3-X5：施法 / 耗资源埋点（传奇特效 `on_skill_cast` / `on_resource_spend` 的落点）。
	# ⚠️ 必须放在**扣费 + 写入冷却之后** —— `resource_refund`（终末回响）要用「已扣的实耗」
	# 返还法力、要「刚写入的冷却」做 `cooldown_half`。放在前面两者都会算错。
	# 顺序：先 `resource_spent`（资源在施放前就已扣）再 `skill_cast`（施放成立）。
	EventBus.resource_spent.emit(real_cost)
	EventBus.skill_cast.emit(id, real_cost)
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


## 投射物（`01-技能体系.md` §3.2；第三步 B3-5 · 工单 1-L3 起为**真实弹道**）。
##
## 生成 `projectile_count` 枚 `Projectile`，以朝向为中轴、`spread_deg` 扇形**均匀**展开
## （`projectile_count == 1` ⇒ 正前方直线）。每发**独立**结算 ⇒ 全中 = N × multiplier
## （§5.1「全中」口径，如 `multishot` 3 发 × 100% = 300%）。
func _execute_projectile(data: SkillData) -> void:
	var host := _player.get_parent()
	if host == null:
		return
	var count := maxi(data.projectile_count, 1)
	var base_dir := _player.get_facing_vector()
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.DOWN
	var base_angle := base_dir.angle()
	var spread := deg_to_rad(data.spread_deg)
	for i in range(count):
		# 单发 ⇒ 正前方；多发 ⇒ 在 [-spread/2, +spread/2] 内均匀分布
		var offset := 0.0
		if count > 1:
			offset = spread * (float(i) / float(count - 1) - 0.5)
		var proj := Projectile.new()
		proj.setup(self, data, Vector2.from_angle(base_angle + offset))
		host.add_child(proj)
		proj.global_position = _player.global_position


## 持续区域（`01-技能体系.md` §3.2；第三步 B3-5 · 工单 1-L4 起为**真实区域实体**）。
##
## 落点 = **玩家脚下**（用户 2026-09-29 裁定）。区域按 `tick_interval` 周期结算、
## `duration` 到期释放；总伤害与 `total_damage_multiplier()` 一致（§5.1）。
func _execute_ground(data: SkillData) -> void:
	var host := _player.get_parent()
	if host == null:
		return
	var area := GroundArea.new()
	area.setup(self, data)
	host.add_child(area)
	area.global_position = _player.global_position
	# ⚠️ 必须最后调 `begin()`：`add_child()` 触发的 `_ready()` 里落点还没设，
	#    落地爆发若在那时结算会打在原点（见 GroundArea.begin 注释）。
	area.begin()


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


## 投射物命中出口（`Projectile` 调用）：走统一伤害管线。
## `damage_scale` 承载**连锁衰减**与**分裂占比**（母弹 = 1.0）。
func on_projectile_hit(target: Node, data: SkillData, damage_scale: float = 1.0) -> void:
	_hit(target, data, data.knockback, -1.0, damage_scale, data.id)


## 持续区域 **每 tick** 命中出口（`GroundArea` 调用）：倍率取 `data.multiplier`（每 tick 值）。
##
## ⚠️ 必须显式传 `data.multiplier` —— 默认口径是 `total_damage_multiplier()`（**总量**），
##    用它会把每个 tick 都算成总量，伤害 = 设计值 × tick 次数。
func on_ground_tick(target: Node, data: SkillData) -> void:
	_hit(target, data, 0.0, data.multiplier, 1.0, data.id)


## 持续区域 **落地爆发** 命中出口（`GroundArea` 调用）：倍率取 `data.impact_multiplier`。
func on_ground_impact(target: Node, data: SkillData) -> void:
	_hit(target, data, data.knockback, data.impact_multiplier, 1.0, data.id)


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
	"duration", "tick_interval", "projectile_speed", "chain_decay_pct",
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
##
## 2026-09-29（第三步 B3-5 · 1-L3）：新增 `on_hit_split`（`rune_split` 的**嵌套 dict**）
## 与 `chain_decay_pct`（`rune_chain`）—— 此前两者都被**静默丢弃**（嵌套 dict 不是标量，
## 落在 `RUNE_FIELD_KEYS`/`RUNE_PCT_KEYS` 之外）。
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
			if k == "on_hit_split":
				_apply_rune_split(out, v)
			elif k in RUNE_FIELD_KEYS:
				_apply_rune_field(out, k, v)
			elif k in RUNE_PCT_KEYS:
				_apply_rune_pct(out, k, float(v))
	return out


## `rune_split` 的 `on_hit_split` 是**嵌套 dict**（`{count, damage_pct}`），
## 不是标量字段覆盖 ⇒ 单独拆解到 `split_count` / `split_damage_pct`。
func _apply_rune_split(out: SkillData, value: Variant) -> void:
	if not (value is Dictionary):
		push_warning("[SkillController] 符文 on_hit_split 不是字典，已忽略")
		return
	var d: Dictionary = value
	out.split_count = int(d.get("count", 0))
	out.split_damage_pct = float(d.get("damage_pct", 0.0))


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
		"chain_decay_pct":
			out.chain_decay_pct = float(value)
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

## 本次命中的**有效倍率** = 命中倍率 × 技能等级系数。
##
## 🔴 技能等级系数是本项目**第二步死钩子 `skill_level` 的唯一复活点**（策划案 §2.1）。
##    公式：`1 + 0.08 × (level - 1)` ⇒ L1 = ×1.00 / L4 = ×1.24 / L7 = ×1.48 / L10 = ×1.72。
##    **不影响**冷却 / 蓝耗 / 范围（避免与 `cooldown_reduction` 双重计入）。
##
## `raw_multiplier < 0` ⇒ 用 `data.total_damage_multiplier()`（单体 / 范围 / 投射物的默认口径）；
## 显式传入 ⇒ 用该值（**持续区域**专用：tick 传 `data.multiplier`、落地爆发传
## `data.impact_multiplier`）—— 否则每 tick 会被算成「总量」而严重超伤。
func _effective_multiplier(data: SkillData, raw_multiplier: float = -1.0) -> float:
	if _player == null:
		return data.total_damage_multiplier()
	var mult := raw_multiplier if raw_multiplier >= 0.0 else data.total_damage_multiplier()
	return mult * _player.get_skill_level_multiplier()


## 统一命中结算：伤害（2.3 完整管线）+ 击退 + 事件
##
## `raw_multiplier`：本次命中的原始倍率（不含等级系数）；`< 0` ⇒ 用 `data` 的默认口径。
## `damage_scale`：本次命中的伤害系数（连锁衰减 / 分裂子投射物）；默认 1.0 = 全额。
## `deferred_cast_id`：非空 ⇒ 本次命中**在施放同步窗口之外**（投射物 / 持续区域），
##   埋点走 `note_deferred_hit()` 补记，而不是 `note_skill_hit()`（后者此时已关窗，会静默丢弃）。
func _hit(target: Node, data: SkillData, knockback_px: float,
		raw_multiplier: float = -1.0, damage_scale: float = 1.0,
		deferred_cast_id: String = "") -> void:
	if target == null or not is_instance_valid(target):
		return
	var base := _player.get_attack_damage() * _effective_multiplier(data, raw_multiplier) * damage_scale
	# 任务 2.3 伤害管线：技能元素（默认物理，词缀/套装可改写）→ 暴击 → 目标减伤
	var result := DamageCalc.compute_hit(
		base,
		_player.get_crit_chance(),
		_player.get_crit_damage(),
		data.element,
		# 元素伤害加成（第二步 2-L7 / 第三步 3-X1；死钩子① 的复活点）：
		#   由恒传 `0.0` 改为按**技能元素**取「专精子键 + 通用总键 + 全元素键」
		#   （`PlayerController.get_element_damage_bonus`，口径 §4.2.3）。
		#   `physical` ⇒ 0.0（物理不吃元素乘区，走 `pct_attack`）。
		_player.get_element_damage_bonus(data.element),
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
		if deferred_cast_id.is_empty():
			CombatMetrics.note_skill_hit()
		else:
			CombatMetrics.note_deferred_hit(deferred_cast_id)
	if knockback_px > 0.0 and target.has_method("apply_knockback"):
		var dir := _player.get_facing_vector()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		target.apply_knockback(dir * knockback_px)
	EventBus.damage_dealt.emit(target, result.final_damage, result.crit, result.element)
