## BOSS 阶段机制控制器（任务 6.3 · class_name 纯静态）
##
## GDD 6.3「BOSS 设计与机制」+ 6.1 掉落（BOSS 100% 掉 2–4 件）：
##   · BOSS 做长（TTK 目标 90–120s，v1.8）：血量门阶段，每阶段解锁新技能。
##   · 阶段数值乘区：阶段伤害随阶段递增；狂暴阶段攻速间隔 ×0.6 左右 + 伤害 ×1.3。
##   · 狂暴起始阶段由 `enrage_phase` 配置。
##   · 数据在 `data/monsters/bosses.json`（2 个章末 BOSS），本类只做纯计算。
##
## B5-5（6-W6-08）：由「4 阶段硬编码」改为「N 阶段数据驱动」——
##   阶段数 = thresholds.size() + 1。现网 BOSS 为 2 阶段（thresholds=[0.6]），
##   但本类不再假设 3/4/4，未来扩阶段只改 JSON。
class_name BossPhaseController
extends RefCounted

const DEFAULT_THRESHOLDS: Array[float] = [0.6]

## 阶段名（展示 / 日志）。N 阶段超出时回退罗马数字。
const PHASE_NAMES := ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"]


## 阶段总数 = 阈值数 + 1（B5-5：数据驱动，不再硬编码 4）。
static func phase_count(config: Dictionary) -> int:
	var th: Array = config.get("thresholds", DEFAULT_THRESHOLDS)
	return maxi(1, th.size() + 1)


## 数据校验：返回错误列表（空 = 合法）
static func validate(config: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if config.is_empty():
		errs.append("配置为空")
		return errs
	if not config.has("id") or str(config["id"]).is_empty():
		errs.append("缺 id")
	var n := phase_count(config)
	if n < 2:
		errs.append("thresholds 至少 1 项（否则只有 1 阶段，无阶段变化）")
	if not config.has("thresholds"):
		errs.append("缺 thresholds")
	if not config.has("phase_skills") or (config["phase_skills"] as Dictionary).size() != n:
		errs.append("phase_skills 必须 %d 段（实际 %d）" % [n, (config.get("phase_skills", {}) as Dictionary).size()])
	if not config.has("summon_pool") or (config["summon_pool"] as Array).is_empty():
		errs.append("summon_pool 不能为空")
	if not config.has("enrage") or (config["enrage"] as Dictionary).is_empty():
		errs.append("缺 enrage 狂暴配置")
	if not config.has("phase_damage_mult") or (config["phase_damage_mult"] as Array).size() != n:
		errs.append("phase_damage_mult 必须 %d 段（实际 %d）" % [n, (config.get("phase_damage_mult", []) as Array).size()])
	if not config.has("summon_count") or (config["summon_count"] as Array).size() != n:
		errs.append("summon_count 必须 %d 项（实际 %d）" % [n, (config.get("summon_count", []) as Array).size()])
	# `enrage_phase` 可选（缺省 = 最后一阶段）。写了就必须落在 1..n。
	if config.has("enrage_phase"):
		var ep := int(config["enrage_phase"])
		if ep < 1 or ep > n:
			errs.append("enrage_phase 必须在 1–%d（当前 %d）" % [n, ep])
	# B5-5（6-W6-09）二阶段场地收缩：火环半径必须是 (0,1] 的归一化值，
	# 且不能大于整个战场（spec 初值 0.35<0.45 的冲突已在此显式断言）。
	if config.has("arena_shrink"):
		var sh: Dictionary = config["arena_shrink"]
		var r := float(sh.get("fire_ring_radius", 1.0))
		if r <= 0.0 or r > 1.0:
			errs.append("arena_shrink.fire_ring_radius 必须在 (0,1]（当前 %.2f）" % r)
	return errs


## 按 HP 比例（0–1）返回当前阶段（1..n）
static func current_phase(hp_ratio: float, thresholds: Array = DEFAULT_THRESHOLDS) -> int:
	var phase := 1
	for t in thresholds:
		if hp_ratio <= float(t):
			phase += 1
		else:
			break
	return clampi(phase, 1, maxi(1, thresholds.size() + 1))


## 阶段技能集（数组，从阶段 1 累积到当前阶段，去重）
static func phase_skills(config: Dictionary, phase: int) -> Array[String]:
	var out: Array[String] = []
	var n := phase_count(config)
	var map: Dictionary = config.get("phase_skills", {})
	for p in range(1, clampi(phase, 1, n) + 1):
		for skill in map.get(str(p), []):
			var s := str(skill)
			if not out.has(s):
				out.append(s)
	return out


## 阶段召唤数（index = phase-1）
static func summon_count_for(config: Dictionary, phase: int) -> int:
	var n := phase_count(config)
	var arr: Array = config.get("summon_count", [])
	if arr.size() != n:
		return 0
	return int(arr[clampi(phase - 1, 0, n - 1)])


## 阶段伤害乘区（index = phase-1）
static func phase_damage_mult(config: Dictionary, phase: int) -> float:
	var n := phase_count(config)
	var arr: Array = config.get("phase_damage_mult", [])
	if arr.size() != n:
		return 1.0
	return float(arr[clampi(phase - 1, 0, n - 1)])


## 狂暴起始阶段（`enrage_phase`，缺省 = 最后一阶段）。
static func enrage_phase(config: Dictionary) -> int:
	return clampi(int(config.get("enrage_phase", phase_count(config))), 1, phase_count(config))


## 狂暴乘区（阶段 >= `enrage_phase` 生效）：{interval_mult, damage_mult}
static func enrage_multipliers(config: Dictionary, phase: int) -> Dictionary:
	var er: Dictionary = config.get("enrage", {})
	if phase >= enrage_phase(config):
		return {
			"interval_mult": float(er.get("attack_interval_mult", 1.0)),
			"damage_mult": float(er.get("damage_mult", 1.0)),
		}
	return {"interval_mult": 1.0, "damage_mult": 1.0}


## 是否已进入狂暴（阶段 >= `enrage_phase`）
static func is_enraged(config: Dictionary, phase: int) -> bool:
	return phase >= enrage_phase(config)
