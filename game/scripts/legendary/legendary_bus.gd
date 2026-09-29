## 传奇特效总线（第三步 3-K1~K9 · 让 31 条「定义完整但零调用」的特效通电）
##
## 职责（`03-装备特色玩法.md` §2.2 写死，不得越界）：
##   ① 关卡进入时 `register()` 全部已穿装备的传奇特效（`register_equipped`）
##   ② **套装机制特效**与装备特效共用本总线的注册表与执行器（第四步 B4 3-S3：
##      `sync_set_effects` 按当前穿戴差分注册 / 注销，key 前缀 `set::`）
##   ③ 监听事件点，把信号/钩子翻译成 `ctx` 字典（§2.3 契约）
##   ④ 调 `LegendaryEffectSystem.on_event()` 拿结算结果
##   ⑤ **执行**结果 —— 数值已由 `on_event` 算好，本类**不自己算伤害**
##
## ⚠️ 禁止：自己算伤害 / 直接改玩家 HP 字段（一律走 `health.restore()` / `mana.restore()`
## 等正规接口）。
##
## 本批（B3-4）实现的执行器（7 类）：`deal_damage`（含 area 范围查询）/ `heal` /
## `gain_resource` / `resource_refund`（含 `cooldown_half`）/ `reflect` /
## `revive_protect`（走死亡钩子）/ `extra_loot`（含 `limit_per_run` 单局计数）。
##
## 第四步 B4 3-B1/B2/B3 追加（4 类）：`buff_stat`（含 `target: enemy` 挂敌人）/
## `ms_boost` / `damage_reduction` / `summon` —— 前 3 类走 `BuffComponent.add_buff`，
## `summon` 走 `Summon.spawn`（与技能侧同一入口，带存活上限 + `DEFS` 未定义守门）。
## 数值已由 `on_event` 算好，本类不自己算。
## ⇒ 第二期 16 条特效**全部通电**。
##
## 事件点落点（§2.4 清单）：
##   on_hit / on_crit      ← `EventBus.damage_dealt`（`target != 玩家` 分流；is_crit 分 hit/crit）
##   on_kill / on_elite_kill ← `EventBus.unit_died`（`killer` 是玩家或召唤物；`unit != 玩家`）
##   on_damage_taken / reflect ← 玩家 `HealthComponent.damaged_hook`（覆盖近战/远程/抛掷全部来源）
##   on_low_hp             ← 每帧轮询玩家 `hp_pct`（仅「较上一帧下降」时触发；跳过濒死带）
##   on_pickup_gold        ← `EventBus.loot_picked_up`（`payload.type == "gold"`）
##   on_skill_cast         ← `EventBus.skill_cast`
##   on_resource_spend     ← `EventBus.resource_spent`
##   on_block              ← `EventBus.block_succeeded`（3-BL1）
class_name LegendaryBus
extends Node

## 玩家（关卡里唯一被监听的对象；所有特效都挂在玩家装备上）
var _player: PlayerController = null

## 上一帧玩家 HP 比例（低血轮询的「下降」判据）
var _last_hp_pct: float = 1.0

## 注入：生成一件掉落物 `(entry: Dictionary, pos: Vector2) -> void`。
## 由 `level_scene` 提供（总线**不碰**场景结构 —— 不自己 instantiate 掉落场景）。
var _spawn_loot: Callable = Callable()

## 注入：精英判定 `(unit: Node) -> bool`。
## 复用 `level_scene._is_elite` 的**唯一口径**（meta `lv_kind` 或 `data.tier`），
## 避免在总线上另起一套判定（项目已因「双口径」踩过坑）。
var _is_elite: Callable = Callable()

## 单局额外掉落计数：`{ effect_id: 已触发次数 }`（`extra_loot.limit_per_run`）
var _extra_loot_used: Dictionary = {}

## 未实现执行器的类型（只吵一次，防刷屏）
var _warned_types: Dictionary = {}

## 重入保护：`reflect` 反打 → 击杀 → `on_kill` → 再触发 可能形成递归。
## 一次 `on_event` 结算**完整执行完**之前，忽略嵌套的 dispatch（防无限递归 / 栈溢出）。
var _dispatching: bool = false


func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.loot_picked_up.connect(_on_loot_picked_up)
	EventBus.block_succeeded.connect(_on_block_succeeded)
	EventBus.skill_cast.connect(_on_skill_cast)
	EventBus.resource_spent.connect(_on_resource_spent)


func _exit_tree() -> void:
	# 断开钩子，防悬空 Callable 指向已释放的节点
	if _player != null and is_instance_valid(_player) and _player.health != null:
		_player.health.revive_hook = Callable()
		_player.health.damaged_hook = Callable()


## 绑定玩家 + 注入依赖。`spawn_loot` / `is_elite` 缺省为空 = 相应效果降级（记日志）。
func setup(player: PlayerController,
		spawn_loot: Callable = Callable(),
		is_elite: Callable = Callable()) -> void:
	_player = player
	_spawn_loot = spawn_loot
	_is_elite = is_elite
	_last_hp_pct = 1.0
	if _player != null and _player.health != null:
		# 死亡钩子（3-K7）：濒死免死
		_player.health.revive_hook = _try_revive
		# 受击钩子（3-K6/K9）：反伤 + on_damage_taken 类触发
		_player.health.damaged_hook = _on_player_damaged


# =============================================================================
# 注册 / 注销（3-K2 / 3-K3）
# =============================================================================

## 注册全部已穿装备的传奇特效（关卡进入时调用一次）
func register_equipped(equipped: Array) -> void:
	for item in equipped:
		register_item(item)


func register_item(item) -> void:
	if item is EquipmentInstance:
		LegendaryEffectSystem.register(item)


func unregister_item(item) -> void:
	if item is EquipmentInstance:
		LegendaryEffectSystem.unregister(item)


## 清空注册表 + 单局计数（离开关卡时调用）
func clear() -> void:
	LegendaryEffectSystem.clear()
	_extra_loot_used.clear()
	_warned_types.clear()
	_set_keys.clear()
	_last_hp_pct = 1.0


func registered_count() -> int:
	return LegendaryEffectSystem.registered_count()


# =============================================================================
# 套装机制特效注册（第四步 B4 · 3-S3）
# =============================================================================

## 套装特效在注册表里的 key 前缀（与装备的 `instance_id` 区分开）。
const SET_KEY_PREFIX: String = "set::"

## 当前已注册的套装特效 key（`{key: effect_id}`）—— 用于 sync 时做增删差分
var _set_keys: Dictionary = {}


## 按当前穿戴重算套装机制特效的注册集合（关卡进入 / 装备变更时调用）。
##
## 差分语义（§3.2 三条约束的落点）：
##   · 新激活 ⇒ `register_effect_id`（同 key 幂等，不重置已注册项的叠层 / 冷却）
##   · 已失效（档位回退 / 脱下）⇒ `unregister_key` —— **必须注销**，否则套装效果永久生效
##   · 同套装 effect_id 去重由 `SetSystem.get_active_effects` 保证
func sync_set_effects(equipped: Array[EquipmentInstance]) -> void:
	var want: Dictionary = {}
	for e in SetSystem.get_active_effects(equipped):
		var eid := String(e.get("effect_id", ""))
		if eid.is_empty():
			continue
		want[SET_KEY_PREFIX + eid] = eid
	# ① 注销不再激活的
	for k in _set_keys.keys():
		if not want.has(k):
			LegendaryEffectSystem.unregister_key(String(k))
	# ② 注册新增的
	for k in want.keys():
		if not _set_keys.has(k):
			LegendaryEffectSystem.register_effect_id(String(want[k]), String(k))
	_set_keys = want


## 当前注册中的套装特效 id（验证 / 面板用，按注册表顺序）
func active_set_effect_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _set_keys:
		out.append(String(_set_keys[k]))
	return out


# =============================================================================
# 低血轮询（3-K9：`hp_pct` 必须正确 —— 缺失会让 on_low_hp 类特效**永久不触发且无报错**）
# =============================================================================

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _player.health == null:
		return
	var hp_pct := _player.health.current_hp / maxf(_player.health.get_max_hp(), 1.0)
	# 只在「较上一帧下降」时触发（避免每帧重复结算）。
	# ⚠️ 跳过濒死带（`hp_pct ≤ LEGENDARY_REVIVE_BAND_HP_PCT`）—— 那一带只由死亡钩子消费，
	#    否则「活着但 HP 极低」的瞬间会白耗 revive_protect 的冷却（不朽者 90s）。
	if hp_pct < _last_hp_pct and hp_pct > GameConstants.LEGENDARY_REVIVE_BAND_HP_PCT:
		var ctx := _base_ctx()
		ctx["hp_pct"] = hp_pct
		_dispatch("on_low_hp", ctx)
	_last_hp_pct = hp_pct


# =============================================================================
# 事件点 → ctx 翻译（§2.3 契约）
# =============================================================================

## 公共 ctx：`attack`（deal_damage 算数值用）+ `max_hp`（heal 类按比值算用）
func _base_ctx() -> Dictionary:
	var attack := 0.0
	var max_hp := 100.0
	if _player != null and is_instance_valid(_player):
		attack = _player.get_attack_damage()
		if _player.health != null:
			max_hp = _player.health.get_max_hp()
	return { "attacker": _player, "attack": attack, "max_hp": max_hp }


## 玩家造成伤害（`damage_dealt` 且目标不是玩家）→ on_hit / on_crit。
## ⚠️ `damage_dealt` 是**双向**总线（敌人打玩家也走它）⇒ 必须按「目标是不是玩家」过滤。
## 召唤物造成的伤害同样计入（`target` 是敌人即可，视为「玩家的伤害」）。
func _on_damage_dealt(target: Node, amount: float, is_crit: bool, _element: String) -> void:
	if target == _player:
		return
	var ctx := _base_ctx()
	ctx["target"] = target
	ctx["amount"] = amount
	_dispatch("on_crit" if is_crit else "on_hit", ctx)


## 玩家击杀单位 → on_kill / on_elite_kill。
## 过滤：① 死的不能是玩家自己；② 凶手必须是玩家或玩家召唤物。
func _on_unit_died(unit: Node, killer: Node) -> void:
	if unit == _player:
		return
	if not _is_player_owned(killer):
		return
	var ctx := _base_ctx()
	ctx["unit"] = unit
	_dispatch("on_kill", ctx)
	if _is_elite.is_valid() and bool(_is_elite.call(unit)):
		_dispatch("on_elite_kill", ctx)


## 玩家受击（`HealthComponent.damaged_hook`）→ on_damage_taken + reflect 的 ctx。
## 用钩子而非 `EventBus.damage_taken`：后者只有**近战**会发（远程 / 抛掷漏发），
## 钩子覆盖全部伤害来源。ctx 必须带 `max_hp`（heal 类按比值算，缺失会按默认 100 严重偏低）。
func _on_player_damaged(amount: float, source: Node) -> void:
	var ctx := _base_ctx()
	ctx["source"] = source
	ctx["amount"] = amount
	_dispatch("on_damage_taken", ctx)


## 拾取金币 → on_pickup_gold。
## ⚠️ 源是 `loot_picked_up`（`payload.type == "gold"`），**不是** `gold_changed` ——
## `gold_changed` 全库只有商店一处在用，且签名不符；真正的金币拾取在 `LootDrop._pick_up()`。
func _on_loot_picked_up(payload: Dictionary) -> void:
	if String(payload.get("type", "")) != "gold":
		return
	_dispatch("on_pickup_gold", _base_ctx())


## 格挡成功 → on_block（3-BL1）
func _on_block_succeeded(blocker: Node, source: Node, amount: float) -> void:
	if blocker != _player:
		return
	var ctx := _base_ctx()
	ctx["source"] = source
	ctx["amount"] = amount
	_dispatch("on_block", ctx)


## 施放技能 → on_skill_cast（ctx 带 `amount_spent`，供 resource_refund 算返还额）
func _on_skill_cast(skill_id: String, mana_spent: float) -> void:
	var ctx := _base_ctx()
	ctx["skill_id"] = skill_id
	ctx["amount_spent"] = mana_spent
	_dispatch("on_skill_cast", ctx)


## 消耗资源 → on_resource_spend（阈值判定用 `amount_spent`）
func _on_resource_spent(amount: float) -> void:
	var ctx := _base_ctx()
	ctx["amount_spent"] = amount
	_dispatch("on_resource_spend", ctx)


## 凶手是否「玩家阵营」（玩家本人或玩家召唤物）
func _is_player_owned(killer: Node) -> bool:
	if killer == null or not is_instance_valid(killer):
		return false
	if killer == _player:
		return true
	return killer.is_in_group(&"summons")


# =============================================================================
# 结算分发 + 执行
# =============================================================================

func _dispatch(trigger_type: String, ctx: Dictionary) -> void:
	if _dispatching:
		return
	_dispatching = true
	var results := LegendaryEffectSystem.on_event(trigger_type, ctx)
	for r in results:
		_execute(r, ctx)
	_dispatching = false


func _execute(r: Dictionary, ctx: Dictionary) -> void:
	# `stack` 中间态只带层数（`{stacks, stacks_until}`，无 `type` 键），没有可执行的东西
	# —— 不跳过的话会被当成「未实现执行器」刷日志（叠层特效每次触发都吵一次）。
	if String(r.get("phase", "")) == "stack":
		return
	var result: Dictionary = r.get("result", {})
	var etype := String(result.get("type", ""))
	match etype:
		"deal_damage":
			_exec_deal_damage(result, ctx)
		"heal":
			_exec_heal(result)
		"gain_resource":
			_exec_gain_resource(result)
		"resource_refund":
			_exec_resource_refund(result, ctx)
		"reflect":
			_exec_reflect(result, ctx)
		"extra_loot":
			_exec_extra_loot(r, result)
		"buff_stat":
			_exec_buff_stat(r, result, ctx)
		"ms_boost":
			_exec_ms_boost(r, result)
		"damage_reduction":
			_exec_damage_reduction(r, result)
		"summon":
			_exec_summon(r, result)
		"revive_protect":
			# 由死亡钩子（`_try_revive`）消费；正常事件路径不执行（防「活着但低血」白耗冷却）
			pass
		_:
			_warn_once(etype, String(r.get("name", "")))


func _warn_once(etype: String, name: String) -> void:
	if _warned_types.has(etype):
		return
	_warned_types[etype] = true
	print("[Legendary] 执行器未实现 / 前置缺失：%s（%s）" % [etype, name])


# ---- 1. deal_damage（含 area 范围查询）-------------------------------------

func _exec_deal_damage(result: Dictionary, ctx: Dictionary) -> void:
	var amount := float(result.get("amount", 0.0))
	if amount <= 0.0:
		return
	var element := String(result.get("element", GameConstants.ELEMENT_PHYSICAL))
	var dot := float(result.get("dot", 0.0))
	var dot_ticks := int(result.get("dot_ticks", 0))
	if bool(result.get("area", false)):
		var origin := _effect_origin(ctx)
		var targets: Array = []
		# ⚠️ 必须显式带上「触发目标」：`HitQuery.circle` 会排除与圆心距离 ≈ 0 的节点
		# （防自伤），而范围伤害的圆心往往就是目标本身（烬誓引爆）⇒ 不加会被漏掉。
		var primary: Node = ctx.get("target", null)
		if primary != null and is_instance_valid(primary) and primary.is_in_group(&"enemies"):
			targets.append(primary)
		for e in HitQuery.circle(origin, GameConstants.LEGENDARY_AREA_RADIUS,
				get_tree().get_nodes_in_group(&"enemies")):
			if not targets.has(e):
				targets.append(e)
		for e in targets:
			_apply_legendary_damage(e, amount, element, dot, dot_ticks)
		return
	var target: Node = ctx.get("target", null)
	if target == null or not is_instance_valid(target):
		# 无目标（如 on_skill_cast 触发的非 area）→ 取玩家周围最近敌人兜底
		var near := HitQuery.circle(_player.global_position, GameConstants.LEGENDARY_AREA_RADIUS,
			get_tree().get_nodes_in_group(&"enemies"))
		target = near[0] if not near.is_empty() else null
	_apply_legendary_damage(target, amount, element, dot, dot_ticks)


## 范围伤害中心：优先用命中目标的位置（烬誓以目标为中心），无目标则用玩家位置。
func _effect_origin(ctx: Dictionary) -> Vector2:
	var target: Node = ctx.get("target", null)
	if target != null and is_instance_valid(target) and target is Node2D:
		return (target as Node2D).global_position
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return Vector2.ZERO


func _apply_legendary_damage(target: Node, amount: float, element: String,
		dot: float, dot_ticks: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	# DOT 类（炽阳·烈焰胸 / 淬毒·蛇牙套）：总伤 `amount` 摊到 `dot` 秒。
	# 走目标的异常系统（`apply_ailment_raw`），与既有 DOT 口径一致；目标无生命组件
	# （如验证靶）时退化为瞬时伤害。
	var health := _health_of(target)
	if dot_ticks > 0 and dot > 0.0 and health != null:
		var ailment := GameConstants.ailment_from_element(element)
		if not ailment.is_empty():
			health.apply_ailment_raw(ailment, amount / dot, dot)
			return
	if target.has_method("take_damage"):
		target.take_damage(amount, _player)


func _health_of(node: Node) -> HealthComponent:
	if node is EnemyBase:
		return (node as EnemyBase).health
	return null


# ---- 2. heal / gain_resource / resource_refund ------------------------------

func _exec_heal(result: Dictionary) -> void:
	var amount := float(result.get("amount", 0.0))
	if amount <= 0.0:
		return
	if _player != null and is_instance_valid(_player) and _player.health != null:
		_player.health.restore(amount)


func _exec_gain_resource(result: Dictionary) -> void:
	var amount := float(result.get("amount", 0.0))
	if amount <= 0.0:
		return
	var mana := _mana()
	if mana != null:
		mana.restore(amount)


func _exec_resource_refund(result: Dictionary, ctx: Dictionary) -> void:
	var mana := _mana()
	var pct := float(result.get("pct", 0.0))
	var spent := float(ctx.get("amount_spent", 0.0))
	if mana != null and pct > 0.0 and spent > 0.0:
		mana.restore(spent * pct)
	if bool(result.get("cooldown_half", false)):
		var sc := _skill_controller()
		var sid := String(ctx.get("skill_id", ""))
		if sc != null and not sid.is_empty():
			sc.halve_cooldown(sid)


# ---- 3. reflect（反伤）------------------------------------------------------

func _exec_reflect(result: Dictionary, ctx: Dictionary) -> void:
	var source: Node = ctx.get("source", null)
	if source == null or not is_instance_valid(source) or source == _player:
		return
	if not source.has_method("take_damage"):
		return
	var back := float(ctx.get("amount", 0.0)) * float(result.get("pct", 0.0))
	if back > 0.0:
		source.take_damage(back, _player)


# ---- 4. revive_protect（濒死免死 · 由死亡钩子消费）--------------------------

## 死亡钩子（`HealthComponent.revive_hook`）。返回 true = 已免死（不广播 unit_died）。
func _try_revive(_source: Node) -> bool:
	if _player == null or not is_instance_valid(_player) or _player.health == null:
		return false
	var ctx := _base_ctx()
	ctx["hp_pct"] = 0.0 # 濒死：HP 已归零
	var results := LegendaryEffectSystem.on_event("on_low_hp", ctx)
	var revived := false
	for r in results:
		var result: Dictionary = r.get("result", {})
		if String(result.get("type", "")) == "revive_protect":
			var heal := float(result.get("heal_pct", 0.0)) * float(ctx["max_hp"])
			if heal > 0.0:
				_player.health.restore(heal)
			if bool(result.get("drain_resource", false)):
				var mana := _mana()
				if mana != null:
					mana.set_current(0.0)
			revived = true
		else:
			# 同一 ctx 顺带触发的其它低血效果（复苏回血 / 七劫叠层）一并结算
			_execute(r, ctx)
	return revived


# ---- 5. extra_loot（额外掉落 + limit_per_run 单局计数）---------------------

func _exec_extra_loot(r: Dictionary, result: Dictionary) -> void:
	var eid := String(r.get("effect_id", ""))
	var limit := int(result.get("limit_per_run", GameConstants.LEGENDARY_EXTRA_LOOT_LIMIT_DEFAULT))
	if int(_extra_loot_used.get(eid, 0)) >= limit:
		return
	if not _spawn_loot.is_valid() or _player == null or not is_instance_valid(_player):
		return
	var entry := LootRoller.roll_guaranteed_equipment(
		_player.get_player_level(), GameConstants.DifficultyTier.NM1,
		_player.get_player_level(), "", _player.get_combat_stat("magic_find"))
	# ⚠️ 只有**真的生成**才消耗上限（掉落器在底材池为空时会退化成金币，
	#    若先计数再 roll，一次退化就白扣一次 `limit_per_run`）。
	if entry.is_empty() or String(entry.get("type", "")) != "equipment":
		return
	_extra_loot_used[eid] = int(_extra_loot_used.get(eid, 0)) + 1
	_spawn_loot.call(entry, _player.global_position)


# ---- 6. buff_stat / ms_boost / damage_reduction（第四步 B4 3-B1）-----------
#
# 三类都落到宿主 `BuffComponent`（`add_buff`）。数值 / 时长 / 叠层上限由 `on_event` 算好，
# 本类只做「挂到谁身上」的路由：
#   · `buff_stat.target`：`self`（默认）= 玩家 ｜ `enemy` = 本次触发目标（`ctx.target`）
#   · `ms_boost` / `damage_reduction` 恒挂玩家（数据里无 `target` 字段）
# `source_id` 取 `effect_id` ⇒ 同一条特效反复触发按「叠层 / 刷新」合并（见 `BuffComponent`）。

func _exec_buff_stat(r: Dictionary, result: Dictionary, ctx: Dictionary) -> void:
	var stat := String(result.get("stat", ""))
	if BuffComponent.resolve_key(stat).is_empty():
		_warn_once("buff_stat(未知 stat=%s)" % stat, String(r.get("name", "")))
		return
	var target := _resolve_buff_target(String(result.get("target", "self")), ctx)
	var bc := _buff_of(target)
	if bc == null:
		_warn_once("buff_stat(目标无 BuffComponent)", String(r.get("name", "")))
		return
	bc.add_buff(stat, float(result.get("value", 0.0)), float(result.get("duration", 1.0)),
		String(r.get("effect_id", "")), int(result.get("max_stacks", 1)))


func _exec_ms_boost(r: Dictionary, result: Dictionary) -> void:
	var bc := _player_buff()
	if bc == null:
		return
	bc.add_buff("move_speed", float(result.get("value", 0.0)),
		float(result.get("duration", 1.0)), String(r.get("effect_id", "")))
	# `element_attach`（裂界指环「攻击附带该精英的伤害类型」）需把精英元素写进攻击管线
	# —— 属攻击管线改造，本批不实现（显式记一次，不静默）。
	if bool(result.get("element_attach", false)):
		_warn_once("ms_boost(element_attach 未接线)", String(r.get("name", "")))


func _exec_damage_reduction(r: Dictionary, result: Dictionary) -> void:
	var bc := _player_buff()
	if bc == null:
		return
	bc.add_buff("damage_reduction", float(result.get("value", 0.0)),
		float(result.get("duration", 1.0)), String(r.get("effect_id", "")))


## `buff_stat` 的 `target` 路由：`enemy` ⇒ 本次触发目标（缺 target 时退化为玩家自身）。
func _resolve_buff_target(target: String, ctx: Dictionary) -> Node:
	if target == "enemy":
		var t: Node = ctx.get("target", null)
		if t != null and is_instance_valid(t):
			return t
	return _player


## 取某节点的 `BuffComponent`（缺省 null；调用方据此记日志）。
func _buff_of(node: Node) -> BuffComponent:
	if node == null or not is_instance_valid(node) or not node.has_method("get_buff_component"):
		return null
	return node.call("get_buff_component")


func _player_buff() -> BuffComponent:
	return _buff_of(_player)


# ---- 7. summon（第四步 B4 3-B1；工单 1-L5 的传奇侧落点）--------------------

## 生成 `count` 只 `creature`（走 `Summon.spawn`，与技能侧 `_execute_summon` 同一入口）。
## ⚠️ 两道守门，**都不静默**：
##   ① `creature` 必须真的在 `Summon.DEFS` 里 —— 否则 `Summon._configure` 的缺省兜底会
##      把它悄悄变成灵狼（String 字段脱钩）。命中即记一次日志并**跳过**。
##   ② 同时存活数 ≤ `LEGENDARY_SUMMON_CAP`（设计 §2.7B：防刷屏）。
func _exec_summon(r: Dictionary, result: Dictionary) -> void:
	var creature := String(result.get("creature", ""))
	if not Summon.DEFS.has(creature):
		_warn_once("summon(未定义 creature=%s)" % creature, String(r.get("name", "")))
		return
	if _player == null or not is_instance_valid(_player):
		return
	var host: Node = _player.get_parent()
	if host == null:
		return
	var count := maxi(int(result.get("count", 1)), 1)
	var duration := float(result.get("duration", 8.0))
	var alive := _count_summons(creature)
	if alive >= GameConstants.LEGENDARY_SUMMON_CAP:
		return
	count = mini(count, GameConstants.LEGENDARY_SUMMON_CAP - alive)
	# `damage_pct` 为**比例**（0.4 = 玩家攻击的 40%）；缺省 -1 = 用 DEFS 预设
	var atk_ratio := -1.0
	if result.has("damage_pct"):
		atk_ratio = float(result["damage_pct"])
	for i in range(count):
		Summon.spawn(host, _player, creature, _player.global_position, duration, atk_ratio)


## 场上（`summons` 组）指定 `summon_id` 的存活数
func _count_summons(creature: String) -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group(&"summons"):
		if s != null and is_instance_valid(s) and s.has_method("get_summon_id") \
				and String(s.call("get_summon_id")) == creature:
			n += 1
	return n


# ---- 内部小工具 -------------------------------------------------------------

func _mana() -> ManaPool:
	if _player != null and is_instance_valid(_player):
		return _player.get_mana_pool()
	return null


func _skill_controller() -> SkillController:
	if _player != null and is_instance_valid(_player):
		return _player.get_skill_controller()
	return null
