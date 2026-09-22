## 账号等级与经验（任务 5.1 · class_name）
##
## GDD 5.1（v1.8）：账号等级 1–60；XP_ToNext(L) = 180 × L^1.6；
##   累计口径「累计到 L 级」= Σ₁^(L-1) XP_ToNext(i)（不含升 L 那一级）。
## 天赋点：每 2 级 1 点（L2、L4、…、L60 → 30 点，GDD 5.2）。
class_name AccountLevel
extends RefCounted

const MAX_ACCOUNT_LEVEL := 60

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
