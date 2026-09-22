## 传奇特效系统（任务 3.5 · 纯静态 class_name）
##
## GDD 0.3 节 3.5 范式：传奇特效 = **触发条件 + 效果 + 冷却/上限** 三要素。
## 本类负责两件事：
##   1. 数据访问：`get(id)` / `for_slot(slot_key)`（同部位特效池——3.4 橙装重铸抽取用）
##   2. 触发结算：`on_event(trigger_type, context)` —— 遍历运行时已注册的特效，
##      评估 trigger 条件（概率 / 叠层 / 阈值）→ 冷却检查 → 应用效果，返回结算结果数组。
##
## ⚠️ 本类**不直接改玩家状态**（不回血、不打伤害）：效果结算结果由调用方（战斗 / UI）
## 执行。叠层与冷却计数是纯内存态（单局内有效），不入存档。
class_name LegendaryEffectSystem
extends RefCounted

## 运行时注册的一件特效状态
const TRIGGER_TYPES: Array[String] = [
	"on_hit", "on_crit", "on_kill", "on_elite_kill", "on_damage_taken", "on_low_hp",
	"on_pickup_gold", "on_skill_cast", "on_resource_spend", "on_block",
]
const EFFECT_TYPES: Array[String] = [
	"stack", "deal_damage", "heal", "gain_resource", "buff_stat", "extra_loot",
	"revive_protect", "ms_boost", "damage_reduction", "reflect", "resource_refund", "summon",
]

## instance_id → { "effect_id": String, "stacks": int, "cooldown_until": float, "limit_used": int }
static var _registry: Dictionary = {}


static func get_effect(id: String) -> Dictionary:
	return ConfigLoader.get_legendary_effect(id)


## 某部位的全部特效（同部位特效池，3.4 橙装重铸抽取用）
static func for_slot(slot_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for eid in ConfigLoader.legendary_effects:
		var fx: Dictionary = ConfigLoader.legendary_effects[eid]
		if String(fx.get("slot", "")) == slot_key:
			out.append(fx)
	return out


## 从同部位特效池随机抽 1 件（排除指定 ID；供 3.4 重铸「重掷传奇特效」）
static func roll_for_slot(slot_key: String, exclude_id: String = "", rng: RandomNumberGenerator = null) -> String:
	var pool := for_slot(slot_key)
	if pool.is_empty():
		return ""
	var candidates: Array[Dictionary] = []
	for fx in pool:
		if String(fx.get("id", "")) != exclude_id:
			candidates.append(fx)
	if candidates.is_empty():
		candidates = pool
	var r := rng if rng != null else RandomNumberGenerator.new()
	return String(candidates[r.randi() % candidates.size()].get("id", ""))


# =============================================================================
# 运行时注册（进入关卡时对装备的特效逐个 register；离开时 clear）
# =============================================================================

static func register(item: EquipmentInstance, now: float = -1.0) -> void:
	if item == null or item.legendary_effect_id.is_empty():
		return
	if ConfigLoader.legendary_effects.has(item.legendary_effect_id):
		_registry[item.instance_id] = {
			"effect_id": item.legendary_effect_id,
			"stacks": 0,
			"cooldown_until": now if now >= 0.0 else Time.get_ticks_msec() / 1000.0,
			"limit_used": 0,
		}


static func unregister(item: EquipmentInstance) -> void:
	_registry.erase(item.instance_id)


static func clear() -> void:
	_registry.clear()


static func registered_count() -> int:
	return _registry.size()


# =============================================================================
# 触发结算
# =============================================================================

## 由事件点调用：`on_event("on_crit", { "attacker": …, "target": …, "amount": … })`。
## 遍历注册特效，命中 trigger 类型 + 满足条件 → 冷却/叠层 → 效果结算。
## 返回 Array[Dictionary]：每条 = { effect_id, name, trigger_type, result: Dictionary }
static func on_event(trigger_type: String, ctx: Dictionary, now: float = -1.0) -> Array:
	var t := now if now >= 0.0 else Time.get_ticks_msec() / 1000.0
	var results: Array = []
	for key in _registry:
		var state: Dictionary = _registry[key]
		var fx := get_effect(String(state["effect_id"]))
		if fx.is_empty():
			continue
		var trigger: Dictionary = fx.get("trigger", {})
		if String(trigger.get("type", "")) != trigger_type:
			continue
		# 概率判定
		var pct := float(trigger.get("pct", 1.0))
		if pct < 1.0 and randf() > pct:
			continue
		# 冷却
		if float(state["cooldown_until"]) > t:
			continue
		# 阈值（on_low_hp：ctx 传 hp_pct）
		if trigger_type == "on_low_hp":
			var hp_pct := float(ctx.get("hp_pct", 1.0))
			if hp_pct > float(trigger.get("hp_below_pct", 0.3)):
				continue
		# 资源消耗阈值
		if trigger_type == "on_resource_spend" and trigger.has("amount"):
			if float(ctx.get("amount_spent", 0.0)) < float(trigger["amount"]):
				continue
		# 执行
		var effect: Dictionary = fx.get("effect", {})
		var etype := String(effect.get("type", ""))
		if etype == "stack":
			var on_full: Dictionary = effect.get("on_full", {})
			var limit := int(trigger.get("stacks_until", 1))
			state["stacks"] = int(state["stacks"]) + 1
			if int(state["stacks"]) >= limit:
				state["stacks"] = 0
				_apply_cooldown(state, fx)
				results.append(_make_result(fx, trigger_type, "on_full", _resolve_effect(on_full, fx, ctx)))
			else:
				results.append(_make_result(fx, trigger_type, "stack", { "stacks": int(state["stacks"]), "stacks_until": limit }))
			continue
		_apply_cooldown(state, fx)
		results.append(_make_result(fx, trigger_type, "effect", _resolve_effect(effect, fx, ctx)))
	return results


static func _apply_cooldown(state: Dictionary, fx: Dictionary) -> void:
	var cd := float(fx.get("cooldown", 0.0))
	if cd > 0.0:
		state["cooldown_until"] = Time.get_ticks_msec() / 1000.0 + cd


static func _make_result(fx: Dictionary, trigger_type: String, phase: String, payload: Dictionary) -> Dictionary:
	return {
		"effect_id": String(fx.get("id", "")),
		"name": String(fx.get("name", "")),
		"trigger_type": trigger_type,
		"phase": phase,
		"result": payload,
	}


## 把效果定义解析为结算结果（数值已算好，调用方执行）。ctx 需含 attacker 的攻击力等。
static func _resolve_effect(effect: Dictionary, fx: Dictionary, ctx: Dictionary) -> Dictionary:
	var etype := String(effect.get("type", ""))
	var attack: float = float(ctx.get("attack", 0.0))
	var max_hp: float = float(ctx.get("max_hp", 100.0))
	match etype:
		"deal_damage":
			var base: float = float(attack) * float(effect.get("damage_pct", 0.0))
			return {
				"type": "deal_damage",
				"amount": base,
				"element": String(effect.get("element", "physical")),
				"area": bool(effect.get("area", false)),
				"dot": float(effect.get("dot", 0.0)),
				"dot_ticks": int(effect.get("dot_ticks", 0)),
			}
		"heal":
			return { "type": "heal", "amount": max_hp * float(effect.get("heal_pct", 0.0)) }
		"gain_resource":
			return { "type": "gain_resource", "amount": float(effect.get("amount", 0.0)) }
		"buff_stat":
			return {
				"type": "buff_stat",
				"stat": String(effect.get("stat", "")),
				"value": float(effect.get("value", 0.0)),
				"duration": float(effect.get("duration", 1.0)),
				"target": String(effect.get("target", "self")),
			}
		"extra_loot":
			return {
				"type": "extra_loot",
				"loot_quality": String(effect.get("loot_quality", "magic")),
				"limit_per_run": int(effect.get("limit_per_run", 5)),
			}
		"revive_protect":
			return {
				"type": "revive_protect",
				"heal_pct": float(effect.get("heal_pct", 0.3)),
				"drain_resource": bool(effect.get("drain_resource", false)),
			}
		"ms_boost":
			return {
				"type": "ms_boost",
				"value": float(effect.get("value", 0.0)),
				"duration": float(effect.get("duration", 1.0)),
				"element_attach": bool(effect.get("element_attach", false)),
			}
		"damage_reduction":
			return { "type": "damage_reduction", "value": float(effect.get("value", 0.0)), "duration": float(effect.get("duration", 1.0)) }
		"reflect":
			return { "type": "reflect", "pct": float(effect.get("pct", 0.0)), "element": String(effect.get("element", "physical")) }
		"resource_refund":
			return { "type": "resource_refund", "pct": float(effect.get("pct", 0.0)), "cooldown_half": bool(effect.get("cooldown_half", false)) }
		"summon":
			return {
				"type": "summon",
				"creature": String(effect.get("creature", "")),
				"count": int(effect.get("count", 1)),
				"duration": float(effect.get("duration", 8.0)),
				"damage_pct": float(effect.get("damage_pct", 0.0)),
			}
	return { "type": "unknown", "effect": effect }
