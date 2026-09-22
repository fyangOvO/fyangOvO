## BOSS 阶段机制控制器（任务 6.3 · class_name 纯静态）
##
## GDD 6.3「BOSS 设计与机制」+ 6.1 掉落（BOSS 100% 掉 2–4 件）：
##   · BOSS 做长（TTK 目标 90–120s，v1.8）：4 阶段血量门（100–75% / 75–50% /
##     50–25% / 25–0%），每阶段解锁新技能（召唤 → 范围践踏 → 狂暴）。
##   · 阶段数值乘区：阶段伤害随阶段递增；狂暴阶段攻速间隔 ×0.6 左右 + 伤害 ×1.3。
##   · 数据在 `data/monsters/bosses.json`（2 个章末 BOSS），本类只做纯计算。
class_name BossPhaseController
extends RefCounted

const DEFAULT_THRESHOLDS: Array[float] = [0.75, 0.5, 0.25]

## 阶段名（展示 / 日志）
const PHASE_NAMES := ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"]


## 数据校验：返回错误列表（空 = 合法）
static func validate(config: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if config.is_empty():
		errs.append("配置为空")
		return errs
	if not config.has("id") or str(config["id"]).is_empty():
		errs.append("缺 id")
	if not config.has("thresholds") or (config["thresholds"] as Array).size() != 3:
		errs.append("thresholds 必须 3 项（75/50/25%）")
	if not config.has("phase_skills") or (config["phase_skills"] as Dictionary).size() != 4:
		errs.append("phase_skills 必须 4 段")
	if not config.has("summon_pool") or (config["summon_pool"] as Array).is_empty():
		errs.append("summon_pool 不能为空")
	if not config.has("enrage") or (config["enrage"] as Dictionary).is_empty():
		errs.append("缺 enrage 狂暴配置")
	if not config.has("phase_damage_mult") or (config["phase_damage_mult"] as Array).size() != 4:
		errs.append("phase_damage_mult 必须 4 段")
	return errs


## 按 HP 比例（0–1）返回当前阶段（1–4）
static func current_phase(hp_ratio: float, thresholds: Array = DEFAULT_THRESHOLDS) -> int:
	var phase := 1
	for t in thresholds:
		if hp_ratio <= float(t):
			phase += 1
		else:
			break
	return clampi(phase, 1, 4)


## 阶段技能集（数组，从阶段 1 累积到当前阶段，去重）
static func phase_skills(config: Dictionary, phase: int) -> Array[String]:
	var out: Array[String] = []
	var map: Dictionary = config.get("phase_skills", {})
	for p in range(1, clampi(phase, 1, 4) + 1):
		for skill in map.get(str(p), []):
			var s := str(skill)
			if not out.has(s):
				out.append(s)
	return out


## 阶段召唤数（index = phase-1）
static func summon_count_for(config: Dictionary, phase: int) -> int:
	var arr: Array = config.get("summon_count", [0, 0, 0, 0])
	return int(arr[clampi(phase - 1, 0, 3)])


## 阶段伤害乘区（index = phase-1）
static func phase_damage_mult(config: Dictionary, phase: int) -> float:
	var arr: Array = config.get("phase_damage_mult", [1.0, 1.0, 1.0, 1.0])
	return float(arr[clampi(phase - 1, 0, 3)])


## 狂暴乘区（仅阶段 4 生效）：{interval_mult, damage_mult}
static func enrage_multipliers(config: Dictionary, phase: int) -> Dictionary:
	var er: Dictionary = config.get("enrage", {})
	if phase >= 4:
		return {
			"interval_mult": float(er.get("attack_interval_mult", 1.0)),
			"damage_mult": float(er.get("damage_mult", 1.0)),
		}
	return {"interval_mult": 1.0, "damage_mult": 1.0}


## 是否已进入狂暴（阶段 4）
static func is_enraged(phase: int) -> bool:
	return phase >= 4
