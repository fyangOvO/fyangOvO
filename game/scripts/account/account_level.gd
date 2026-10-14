## 账号等级与经验（任务 5.1 · class_name）
##
## GDD 5.1（v1.8）原定账号等级 1–60；**路线 A（4-W10）曾改为 1–20**：
##   20 关 reward_xp 合计 148,600 的单周目天花板是 L19（cum(20)=156,380 已超出），
##   上限留在 60 只会让 40 级目标永久悬空、`recommended_player_level` 无从收敛。
##
## 2026-10-14 用户裁定「**提高账号上限**」（备选：改天赋阶梯 / 维持 L30 / 提上限）：
##   天赋**第三分支 `arcane` 解锁在 L30**（`TalentTree.BRANCH_UNLOCK_LEVELS`），
##   上限 20 会让它**永久不可达**。故上限 **20 → 30** —— 这是让 L30 可达的**最小**取值，
##   对既有数值扰动最小（单周目仍只到 L19，20–30 属**刷级**区，符合刷宝 ARPG 预期）。
##   ⚠️ 如需回到 GDD 的 60，只改本常量 + `GameConstants.ACCOUNT_LEVEL_MAX` 两处即可。
##
## XP_ToNext(L) = 180 × L^1.6（公式不变）；
##   累计口径「累计到 L 级」= Σ₁^(L-1) XP_ToNext(i)（不含升 L 那一级）。
## 天赋点：每 2 级 1 点（L2、L4、…、L30 → 15 点）。
class_name AccountLevel
extends RefCounted

const MAX_ACCOUNT_LEVEL := 30

var level := 1
var xp_cur := 0.0
var xp_next := 0.0
var talent_points := 0
var _on_level_up: Callable  # func(new_level: int, gained_points: int)


func _init(on_level_up: Callable = Callable()) -> void:
	_on_level_up = on_level_up
	_refresh_xp_next()


## 升到下一级所需经验（GDD 5.1：180 × L^1.6）
static func xp_to_next(level: int) -> float:
	return 180.0 * pow(float(level), 1.6)


## 累计到 L 级所需总经验（Σ₁^(L-1)）
static func cumulative_to(level: int) -> float:
	var total := 0.0
	for i in range(1, level):
		total += xp_to_next(i)
	return total


func _refresh_xp_next() -> void:
	xp_next = xp_to_next(level)


## 加经验；自动处理多级连升（每级回调 + 天赋点）
func add_xp(amount: float) -> void:
	if amount <= 0.0 or level >= MAX_ACCOUNT_LEVEL:
		return
	xp_cur += amount
	while level < MAX_ACCOUNT_LEVEL and xp_cur >= xp_next:
		xp_cur -= xp_next
		level += 1
		var gained := 1 if level % 2 == 0 else 0
		talent_points += gained
		if _on_level_up.is_valid():
			_on_level_up.call(level, gained)
		_refresh_xp_next()


func progress() -> float:
	if level >= MAX_ACCOUNT_LEVEL:
		return 1.0
	return xp_cur / xp_next
