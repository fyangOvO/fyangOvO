## 局内临时增益 / Buff（任务 4.3 · class_name）
##
## GDD 0.4 节 4.3/4.4：三选一选项、祭坛二选一、连杀层数机制 → 统一的
## 局内 buff 字典（{buff_id: stacks}），转成 StatCalculator 的 buffs 格式
## （{buff_id: {"pct": {...}}}）并入属性结算。
##
## 连杀（GDD 0.4 节 4.3）：3 秒内连续击杀不断连，每 20 连杀 +3% 攻击力，
## 上限 +15%。
class_name RunBuffSystem
extends RefCounted

const STREAK_WINDOW := 3.0
const STREAK_STEP := 20
const STREAK_BONUS_PER_STEP := 3.0
const STREAK_BONUS_MAX := 15.0

var buffs: Dictionary = {}          # {buff_id: stacks}
var streak := 0
var streak_timer := 0.0
var streak_bonus_attack := 0.0
var _now := 0.0


## 应用选项（三选一 / 祭坛）：同 id 叠层
func apply_option(option_id: String) -> void:
	buffs[option_id] = int(buffs.get(option_id, 0)) + 1


func get_stacks(option_id: String) -> int:
	return int(buffs.get(option_id, 0))


## 记录一次击杀：3 秒内不断连则连杀 +1，每 20 连杀 +3% 攻击（上限 +15%）
func on_kill() -> void:
	if _now - streak_timer > STREAK_WINDOW:
		streak = 0
		streak_bonus_attack = 0.0
	streak += 1
	streak_timer = _now
	streak_bonus_attack = minf(float(streak) / STREAK_STEP * STREAK_BONUS_PER_STEP, STREAK_BONUS_MAX)
	EventBus.kill_streak_changed.emit(streak, streak_bonus_attack)


## 祭坛二选一：触碰后应用（随机二选一）
## 选项：{id, name, desc, pct: {key: value}}
static func SHINE_OPTIONS() -> Array[Dictionary]:
	return [
		{"id": "altar_power", "name": "狂怒祭坛", "desc": "+20% 攻击力，但受到伤害 +15%",
			"pct": {"pct_attack": 20.0, "damage_taken": 15.0}},
		{"id": "altar_haste", "name": "疾风祭坛", "desc": "+15% 攻击速度，但移动速度 -10%",
			"pct": {"attack_speed": 15.0, "move_speed": -10.0}},
	]


## 转成 StatCalculator buffs 格式并入结算（`{buff_id: {"pct": {...}}}`）。
##
## 【2026-09-18 修复 · D3】cap 从「抽卡过滤」升级为**硬顶钳制**：
##   旧实现只在 `RunePool.get_choices` 抽卡时按 `stats_pct >= cap` 过滤，**不钳制最终值** ⇒
##   一旦叠层（如 3 层狂怒 = 36%）就突破 GDD 0.4 §4.4 的 +30% 硬上限。现在改为：
##     ① 先按 **stat_key** 汇总全部来源（三选一 / 祭坛 / 连杀）的贡献；
##     ② 若某 stat_key 总额 > 其 cap（cap 由 `RunePool.cap_for_stat_key` 给出），
##        **按比例缩放**所有贡献者，使总额恰好 = cap（超出部分夹住，不是丢弃某一项）；
##     ③ 写回各 option_id。
##   缩放对全部贡献者**一致**，保证「同样的选择永远得到同样的结果」（确定性）。
##   `picked_pct` 保留（历史签名兼容），当前不参与计算。
func to_calculator_buffs(picked_pct: Dictionary = {}) -> Dictionary:
	# ---- ① 收集原始贡献（option_id → {stat_key: pct}）并汇总每 stat_key 总量 ----
	var raw: Dictionary = {}      # option_id -> {stat_key: value}
	var totals: Dictionary = {}   # stat_key -> 累计
	for option_id in buffs:
		var opt := RunePool.get_option(option_id)
		if not opt.is_empty():
			var key := str(opt["stat_key"])
			var val := float(opt["value"]) * float(buffs[option_id])
			raw[option_id] = {key: val}
			totals[key] = float(totals.get(key, 0.0)) + val
		else:
			# 祭坛等非池选项（id/name/desc/pct）
			for altar in SHINE_OPTIONS():
				if altar["id"] == option_id:
					var pct: Dictionary = (altar["pct"] as Dictionary).duplicate()
					raw[option_id] = pct
					for k in pct:
						totals[k] = float(totals.get(k, 0.0)) + float(pct[k])
	# 连杀攻击加成（GDD 0.4 §4.3：每 20 连杀 +3% 攻击，上限 +15%）——同样计入 pct_attack 总量
	if streak_bonus_attack > 0.0:
		raw["kill_streak"] = {"pct_attack": streak_bonus_attack}
		totals["pct_attack"] = float(totals.get("pct_attack", 0.0)) + streak_bonus_attack

	# ---- ② 每 stat_key 求钳制缩放（超出 cap 的部分夹住）----
	var scale: Dictionary = {}
	for k in totals:
		var cap := RunePool.cap_for_stat_key(str(k))
		var total := float(totals[k])
		scale[k] = (cap / total) if (cap > 0.0 and total > cap) else 1.0

	# ---- ③ 按缩放写回 ----
	var out := {}
	for option_id in raw:
		var pct_out: Dictionary = {}
		for k in raw[option_id]:
			pct_out[k] = float(raw[option_id][k]) * float(scale.get(k, 1.0))
		out[option_id] = {"pct": pct_out}
	return out


func tick(delta: float) -> void:
	_now += delta


func reset() -> void:
	buffs.clear()
	streak = 0
	streak_timer = 0.0
	streak_bonus_attack = 0.0
	_now = 0.0
