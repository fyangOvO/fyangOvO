## 通用生命组件（阶段 2 · 任务 2.6 · 生命 / 护盾 / 异常状态）
##
## 职责边界（2.6，别越界）：
##   ✅ 最大 / 当前生命：max_hp = 角色裸装 HP 公式（GDD 6.2：150 × 1.11^(L-1)）
##   ✅ 减伤链（用户 2.3 拍板顺序）：护甲/抗性 → 减伤% 乘算 → 概率判定（闪避/格挡）
##   ✅ 护盾：先吸收再扣血（护盾叠 #3A5FB0 视觉由血条组件负责）
##   ✅ 异常状态：中毒 / 燃烧（dot 持续伤害）+ 冰冻（移动减速）；同类刷新时长不叠加
##   ✅ 生命回复（基础 0，阶段 3 词缀 / 局内天赋「再生」写入）
##   ✅ 死亡：HP ≤ 0 → is_dead + EventBus 广播（unit_died；宿主是玩家时另发 player_died）
##   ❌ 玩家输入 / 移动（PlayerController）、敌人状态机（EnemyBase 2.4 简易生命保留，
##      2.7 掉落接入时一并迁移本组件）、受击闪白 / 伤害数字（2.8 打击感）
##
## 宿主契约（**接口探测，缺省安全兜底**；玩家场景已全部实现）：
##   get_level()                     → 等级（决定 max_hp；缺省 1）
##   is_invulnerable()               → 无敌帧（闪避中免疫；缺省 false）
##   get_armor() / get_resist(el)    → 减伤（缺省 0）
##   get_dodge_chance()              → 闪避率 %（缺省 0）
##   get_block_chance()              → 格挡率 %（缺省 0）
##   get_attack_damage()             → dot 来源攻击力（缺省 1）
##
## ⚠️ 减伤只走「物理路径」（护甲）：宿主 get_resist 阶段 3 前恒 0，
##    元素抗性减伤数学上 = 0，与物理等价；抗性接口保留供词缀接入。
class_name HealthComponent
extends Node

## 当前生命
var current_hp: float = 0.0

## 护盾值（先于生命被吸收）
var shield: float = 0.0

## 是否已死亡（死亡后忽略受击 / 施加异常）
var is_dead: bool = false

## 每帧生命回复（/s；阶段 3 词缀 / 局内天赋写入）
var regeneration_per_second: float = GameConstants.PLAYER_BASE_REGENERATION

## 激活中的异常：{ 异常类型: { "time": 剩余秒, "dps": 每秒伤害, "source": 施加方 } }
var _ailments: Dictionary = {}

## 宿主引用（默认取父节点；场景中也可显式设置）
var host: Node = null

## 是否在组件内执行减伤链（护甲 → 减伤% → 闪避/格挡）。
## 玩家 true（攻击方给的原始伤害，组件负责减伤）；
## 敌人 false（玩家攻击管线 DamageCalc 已按敌人护甲减伤过，组件再减 = 双重减伤）。
@export var apply_mitigation: bool = true

## 最大生命覆盖（>0 时优先用，跳过玩家裸装公式）。
## 敌人用它注入怪物表 HP（100.7 × 1.284^(L-1) × hp_scale × 难度系数）；
## 玩家保持 0 走 GDD 玩家公式（150 × 1.11^(L-1)）。
var max_hp_override: float = 0.0


func _ready() -> void:
	if host == null:
		host = get_parent()
	# 用宿主等级初始化满血（宿主 get_level 缺省 1）
	current_hp = get_max_hp()


func _process(delta: float) -> void:
	if is_dead:
		return
	_tick_regen(delta)
	_tick_ailments(delta)


# =============================================================================
# 一、属性查询
# =============================================================================

## 最大生命：优先用宿主覆盖（敌人怪物表 HP）；否则玩家裸装 HP 公式（GDD 6.2）
func get_max_hp() -> float:
	if max_hp_override > 0.0:
		return max_hp_override
	return GameConstants.base_stat_at_level(
		GameConstants.BASE_HP_AT_L1, GameConstants.BASE_HP_GROWTH, _host_level())


func get_current_hp() -> float:
	return current_hp


func get_shield() -> float:
	return shield


## 当前移动速度乘区：冰冻减速 0.6，否则 1.0（玩家控制器读取）
func get_move_speed_factor() -> float:
	if _ailments.has(GameConstants.AILMENT_SLOW):
		return GameConstants.AILMENT_SLOW_SPEED_FACTOR
	return 1.0


## 是否处于任一异常状态
func has_ailment(ailment: String) -> bool:
	return _ailments.has(ailment)


func get_ailment_remaining(ailment: String) -> float:
	var entry: Dictionary = _ailments.get(ailment, {})
	return entry.get("time", 0.0)


## 当前全部异常类型（字典键拷贝）
func get_active_ailments() -> Array:
	return _ailments.keys()


# =============================================================================
# 二、受击（减伤链）
# =============================================================================

## 受击入口（契约）。amount 为攻击方最终伤害（已过暴击 / 技能倍率）；
## source 为攻击方（用于元素异常与未来特效）。
## 减伤链（用户 2.3 拍板）：护甲（物理）→ 减伤% 乘算（阶段 3 套装）→ 概率判定（闪避/格挡）
func take_damage(amount: float, source: Node) -> void:
	if is_dead or amount <= 0.0:
		return
	# 1) 无敌帧（闪避 i-frames / 受控期间）：完全免疫
	if _host_invulnerable():
		return
	var dmg := amount
	if apply_mitigation:
		# 2) 减伤：护甲 DR（物理路径；元素抗性阶段 3 前 = 0）
		dmg = amount * _damage_reduction_multiplier()
		# 3) 概率判定（闪避 → 免疫；格挡 → 减伤）
		if _roll_dodge():
			return
		if _roll_block():
			dmg *= 1.0 - GameConstants.BLOCK_DAMAGE_REDUCTION
	# 4) 护盾吸收 → 扣血
	dmg = _absorb_by_shield(dmg)
	current_hp -= dmg
	EventBus.health_changed.emit(current_hp, get_max_hp())
	if current_hp <= 0.0:
		current_hp = 0.0
		_die(source)


## 直接恢复生命（封顶到 max_hp）
func restore(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_hp = minf(current_hp + amount, get_max_hp())
	EventBus.health_changed.emit(current_hp, get_max_hp())


## 授予护盾（可叠加；2.6 无上限，阶段 3 若需 cap 在此加）
func grant_shield(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	shield += amount


## 死亡（供外部直接触发，如关卡陷阱）
func die(reason: String = "hp_depleted") -> void:
	if is_dead:
		return
	_die(null, reason)


# =============================================================================
# 三、异常状态
# =============================================================================

## 按元素施加异常（敌人攻击用）：元素 → 类型映射，无异常则无事发生
func apply_ailment_from_element(element: String, source: Node) -> void:
	var ailment := GameConstants.ailment_from_element(element)
	if ailment.is_empty():
		return
	apply_ailment(ailment, source)


## 施加异常（自动按类型算 dps / 时长；来源取攻击力）
func apply_ailment(ailment: String, source: Node) -> void:
	if is_dead or ailment.is_empty():
		return
	var dps := 1.0
	if source != null and source.has_method("get_attack_damage"):
		dps = float(source.call("get_attack_damage"))
	dps *= GameConstants.ailment_dps_ratio(ailment)
	var duration := GameConstants.ailment_duration(ailment)
	_apply_ailment_entry(ailment, dps, duration, source)


## 直接指定 dps / 时长施加异常（验证脚本 / 阶段 3 词缀用）
func apply_ailment_raw(ailment: String, dps: float, duration: float) -> void:
	if is_dead or ailment.is_empty():
		return
	_apply_ailment_entry(ailment, maxf(dps, 0.0), maxf(duration, 0.0), null)


## 解除异常（冰冻到期 / 净化技能预留）
func clear_ailment(ailment: String) -> void:
	_ailments.erase(ailment)


## 内部：写入异常条目（同类刷新剩余时长，不叠加）
func _apply_ailment_entry(ailment: String, dps: float, duration: float, source: Node) -> void:
	if duration <= 0.0:
		_ailments.erase(ailment)
		return
	_ailments[ailment] = { "time": duration, "dps": dps, "source": source }


func _tick_ailments(delta: float) -> void:
	for ailment in _ailments.keys():
		var entry: Dictionary = _ailments[ailment]
		entry["time"] = float(entry["time"]) - delta
		if float(entry["time"]) <= 0.0:
			_ailments.erase(ailment)
			continue
		var dps := float(entry.get("dps", 0.0))
		if dps > 0.0:
			# dot 直接扣血（先吃护盾，不过减伤 / 格挡——持续伤害不做概率判定）
			var dot := _absorb_by_shield(dps * delta)
			if dot > 0.0:
				current_hp -= dot
				EventBus.health_changed.emit(current_hp, get_max_hp())
				if current_hp <= 0.0:
					current_hp = 0.0
					_die(entry.get("source", null))
					return


func _tick_regen(delta: float) -> void:
	if regeneration_per_second <= 0.0 or current_hp >= get_max_hp():
		return
	restore(regeneration_per_second * delta)


# =============================================================================
# 四、内部：减伤链辅助
# =============================================================================

func _host_level() -> int:
	if host != null and host.has_method("get_level"):
		return int(host.call("get_level"))
	return 1


func _host_invulnerable() -> bool:
	if host != null and host.has_method("is_invulnerable"):
		return bool(host.call("is_invulnerable"))
	return false


## 护甲减伤乘数（0–1）：DamageCalc.mitigation_factor 返回减伤后的乘数（DR=ARM/(ARM+50L)）
func _damage_reduction_multiplier() -> float:
	var armor := 0.0
	var level := _host_level()
	if host != null and host.has_method("get_armor"):
		armor = float(host.call("get_armor"))
	return DamageCalc.mitigation_factor(armor, 0.0, level, GameConstants.ELEMENT_PHYSICAL)


## 闪避率 roll（%）。命中返回 false；闪避成功返回 true（免疫本次伤害）
func _roll_dodge() -> bool:
	var chance := 0.0
	if host != null and host.has_method("get_dodge_chance"):
		chance = float(host.call("get_dodge_chance"))
	return chance > 0.0 and randf() * 100.0 < chance


## 格挡率 roll（%）。命中返回 false；格挡成功返回 true（减伤）
func _roll_block() -> bool:
	var chance := 0.0
	if host != null and host.has_method("get_block_chance"):
		chance = float(host.call("get_block_chance"))
	return chance > 0.0 and randf() * 100.0 < chance


## 护盾吸收：返回剩余未吸收伤害
func _absorb_by_shield(dmg: float) -> float:
	if shield <= 0.0 or dmg <= 0.0:
		return dmg
	var absorbed := minf(shield, dmg)
	shield -= absorbed
	return dmg - absorbed


func _die(source: Node, reason: String = "hp_depleted") -> void:
	is_dead = true
	_ailments.clear()
	EventBus.unit_died.emit(host, source)
	# 玩家死亡额外广播（死亡方案 B 结算流程监听；本组件不实现重生）
	if host != null and host.is_in_group(&"player"):
		EventBus.player_died.emit(reason)
