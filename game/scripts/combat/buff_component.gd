## 临时增益组件（第四步 B4 · 3-B1 · 解锁 16 条「需临时增益系统」的传奇/套装特效）
##
## 挂载：玩家 / 敌人**各一个独立节点**（与 `Health` 并列，代码创建、显式互相引用）。
## 生命周期：**单局态，不写存档**（设计 §2.7A 硬约束）。
##
## 数据结构：`_buffs = [{id, key, value, expire_at, duration, stacks, max_stacks, source_id}]`
##   · `key` = 归一化后的 StatCalculator 键（经 `STAT_ALIAS` 别名表）
##   · 每帧 `_prune()` 清理过期项；新增 / 叠层 / 清理时 emit `changed`
##     （供关卡重算属性、HUD 重绘）
##
## 同名 buff（同 `key` + 同 `source_id`）：
##   · `max_stacks > 1` ⇒ **叠层**（`stacks+1`，封顶 `max_stacks`），并刷新到期时间
##   · `max_stacks == 1` ⇒ **刷新**（到期时间取 `max(旧, 新)`），不叠层
##
## 消费分工（**防双重计入**）：
##   · `to_calculator_buffs()` 产出 `{id: {"pct": {key: value}}}` ⇒ 并入 `StatCalculator`
##     （攻击/护甲/闪避/攻速/全属性/金币/全伤害 …）
##   · `HEALTH_SIDE_KEYS`（`move_speed` / `damage_reduction`）**不**并入计算器，
##     由 `HealthComponent` 直接读取（玩家与敌人通用，见 `get_move_speed_factor` /
##     `_damage_reduction_multiplier`）—— 否则玩家侧会经 `_move_speed_multiplier` 二次计入。
class_name BuffComponent
extends Node

## 生效时发出（新增 / 叠层 / 到期清理）
signal changed

## effect JSON 的 `stat` 名 → StatCalculator 键（别名表）。
## ⚠️ 这是**规范**（对齐 `02-装备属性.md` §8.2 / 特效数据），不是从被检数据反推。
##
## 两类条目：
##   ① **改写名**（effect 数据用的口语名 → 引擎规范键）：`armor_pct` / `enemy_armor_reduction`
##   ② **同名直通**（数据里就写 StatCalculator 规范键）：`move_speed` / `crit_chance` / `pct_armor` …
## 同名直通必须**显式列出**——`resolve_key` 用 `STAT_ALIAS.get(stat, "")` 取键，
## 表里没有就直接返回空串（调用方记日志后跳过）。漏列 ⇒ 「数据里写了、代码零消费」的死钩子。
const STAT_ALIAS: Dictionary = {
	# ① 改写名
	"armor_pct": "pct_armor",
	"enemy_armor_reduction": "pct_armor",  # 挂敌人，值为正 ⇒ 内部取负（护甲降低）
	# ② 同名直通（StatCalculator 规范键）
	"all_damage": "all_damage",            # 通用伤害加成（物理 + 元素，见 compute_hit 的 element_bonus_pct）
	"move_speed": "move_speed",
	"attack_speed": "attack_speed",
	"dodge": "dodge",
	"all_attributes": "all_attributes",
	"gold_gain": "gold_gain",
	"damage_reduction": "damage_reduction",  # 非 StatCalculator 键：HealthComponent 直接消费
	"pct_armor": "pct_armor",                # pct 乘算输入键（主属性三件套）
	"pct_attack": "pct_attack",
	"pct_hp": "pct_hp",
	"crit_chance": "crit_chance",
	"elemental_damage": "elemental_damage",
}

## 由 `HealthComponent` 直接消费、**不**并入 StatCalculator 的键（防双重计入）
const HEALTH_SIDE_KEYS: Array[String] = ["move_speed", "damage_reduction"]

## 时基（每帧推进；`expire_at` 与之比较）
var _time: float = 0.0

## 激活中的增益
var _buffs: Array[Dictionary] = []


func _process(delta: float) -> void:
	_time += delta
	_prune()


func _ready() -> void:
	_sync_process()


## 无激活增益时关掉 `_process`（敌人数量多，省每帧开销）
func _sync_process() -> void:
	set_process(not _buffs.is_empty())


## stat 名 → 归一化键。未知返回空串（调用方据此记日志，不静默）。
static func resolve_key(stat: String) -> String:
	return String(STAT_ALIAS.get(stat, ""))


## 施加一个增益。`stat` 为 effect JSON 的 `stat` 名（经别名表归一）。
## `value` 为**百分数增量**（+6.0 = +6%）；`duration <= 0` 直接忽略。
func add_buff(stat: String, value: float, duration: float,
		source_id: String = "", max_stacks: int = 1) -> void:
	var key := resolve_key(stat)
	if key.is_empty():
		return
	# `enemy_armor_reduction`：数据里写正值（「降低 X% 护甲」），内部存负 pct_armor
	var v := value
	if stat == "enemy_armor_reduction":
		v = -absf(value)
	_add_entry(key, v, duration, source_id, max_stacks)


## 直接按 **StatCalculator 键**施加（技能 BUFF / 内部调用；键已归一，不再过别名表）。
## 供 `GameConstants.BUFF_DEFS`（7 条 BUFF 技能）与 `HealthComponent` 侧键（`move_speed` /
## `damage_reduction`）使用 —— 它们的键来自代码常量，不需要（也不该）经过 effect JSON 别名。
func add_buff_key(key: String, value: float, duration: float,
		source_id: String = "", max_stacks: int = 1) -> void:
	if key.is_empty():
		return
	_add_entry(key, value, duration, source_id, max_stacks)


func _add_entry(key: String, v: float, duration: float,
		source_id: String, max_stacks: int) -> void:
	if duration <= 0.0:
		return
	var cap := maxi(max_stacks, 1)
	var id := "%s|%s" % [key, source_id]
	for b in _buffs:
		if String(b["id"]) == id:
			b["stacks"] = mini(int(b["stacks"]) + 1, cap)
			b["max_stacks"] = cap
			b["expire_at"] = maxf(float(b["expire_at"]), _time + duration)
			b["duration"] = maxf(float(b["duration"]), duration)
			b["value"] = v
			changed.emit()
			_sync_process()
			return
	_buffs.append({
		"id": id, "key": key, "value": v,
		"expire_at": _time + duration, "duration": duration,
		"stacks": 1, "max_stacks": cap, "source_id": source_id,
	})
	changed.emit()
	_sync_process()


## 某键的当前总加成（`Σ value × stacks`，百分数）。供 HealthComponent 等直接消费。
func get_stat_bonus(key: String) -> float:
	var total := 0.0
	for b in _buffs:
		if String(b["key"]) == key:
			total += float(b["value"]) * int(b["stacks"])
	return total


## 转成 `StatCalculator` 的 buffs 格式 `{id: {"pct": {key: value}}}`。
## ⚠️ 排除 `HEALTH_SIDE_KEYS`（move_speed / damage_reduction）—— 它们由 HealthComponent 直接消费。
func to_calculator_buffs() -> Dictionary:
	var out := {}
	for b in _buffs:
		var key := String(b["key"])
		if key in HEALTH_SIDE_KEYS:
			continue
		var val := float(b["value"]) * int(b["stacks"])
		out[String(b["id"])] = {"pct": {key: val}}
	return out


## 激活中的增益（HUD / 验证用）：[{id, key, value, stacks, remain, duration, source_id}]
func get_active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in _buffs:
		out.append({
			"id": String(b["id"]),
			"key": String(b["key"]),
			"value": float(b["value"]),
			"stacks": int(b["stacks"]),
			"remain": maxf(float(b["expire_at"]) - _time, 0.0),
			"duration": maxf(float(b["duration"]), 0.001),
			"source_id": String(b["source_id"]),
		})
	return out


func active_count() -> int:
	return _buffs.size()


func has_key(key: String) -> bool:
	for b in _buffs:
		if String(b["key"]) == key:
			return true
	return false


## 是否带有指定 `source_id` 的增益（第四步 B4 3-S1：`require_target_buff` 条件判定用）。
## `source_id` = 施加者身份（特效取 `effect_id`）⇒ 「目标是否中了霜噬·减速」即查此。
func has_source(source_id: String) -> bool:
	if source_id.is_empty():
		return false
	for b in _buffs:
		if String(b["source_id"]) == source_id:
			return true
	return false


## 清空（离开关卡 / 死亡时调用）
func clear() -> void:
	if _buffs.is_empty():
		return
	_buffs.clear()
	changed.emit()
	_sync_process()


func _prune() -> void:
	var removed := false
	for i in range(_buffs.size() - 1, -1, -1):
		if float(_buffs[i]["expire_at"]) <= _time:
			_buffs.remove_at(i)
			removed = true
	if removed:
		changed.emit()
		_sync_process()
