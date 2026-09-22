## 天赋树（任务 5.2 · class_name）
##
## GDD 5.2：3 大分支（武力 / 守护 / 秘法），每分支 20 节点 =
##   小节点 15（+2% 单一属性）+ 大节点 5（+8% 属性 或 解锁 1 个机制）。
## 天赋点：每 2 级 1 点 → 满级 60 级 30 点（最多点满半棵树）。
## 分支解锁：L1 武力 / L15 守护 / L30 秘法。
class_name TalentTree
extends RefCounted

const BRANCHES := ["might", "guardian", "arcane"]
const BRANCH_UNLOCK_LEVEL := {"might": 1, "guardian": 15, "arcane": 30}
const SMALL_NODE_COUNT := 15
const BIG_NODE_COUNT := 5
const SMALL_BONUS := 2.0   # +2% 单一属性
const BIG_BONUS := 8.0     # +8% 属性

## 分支 stat_key 与机制（工程侧：武力=攻击 / 守护=护甲 / 秘法=资源；5 个大节点机制示例）
const BRANCH_STAT := {"might": "pct_attack", "guardian": "pct_armor", "arcane": "resource_regen"}
const BIG_NODE_MECHANICS := [
	"护甲转护盾", "暴击溢出转伤害", "格挡后反击", "击杀叠攻（本局）", "拾取范围翻倍",
]

var unlocked := {}          # branch -> bool（L1/L15/L30）
var points_spent: Dictionary = {}  # node_id -> bool


## 分支是否已解锁（按账号等级）
static func is_branch_unlocked(branch: String, account_level: int) -> bool:
	return account_level >= int(BRANCH_UNLOCK_LEVEL.get(branch, 99))


## 节点总数（含 id 生成）：branch.small.N / branch.big.N
static func node_id(branch: String, kind: String, index: int) -> String:
	return "%s.%s.%d" % [branch, kind, index]


static func is_big(node: String) -> bool:
	return node.contains(".big.")


## 节点属性加成（百分数）：小 +2% / 大 +8%
static func node_bonus(node: String) -> float:
	return BIG_BONUS if is_big(node) else SMALL_BONUS


## 点满该分支所需点数（20 节点）
static func branch_cost() -> int:
	return SMALL_NODE_COUNT + BIG_NODE_COUNT


## 解锁分支（等级驱动，供外部在等级变化时调用）
func update_unlocks(account_level: int) -> void:
	for branch in BRANCHES:
		unlocked[branch] = is_branch_unlocked(branch, account_level)


## 学习节点：未解锁分支 / 重复 / 点不足均拒绝
func learn(node: String, account_level: int) -> Dictionary:
	var parts := node.split(".")
	if parts.size() != 3:
		return {"ok": false, "reason": "节点 id 非法"}
	var branch := parts[0]
	if not BRANCHES.has(branch):
		return {"ok": false, "reason": "分支不存在"}
	if not is_branch_unlocked(branch, account_level):
		return {"ok": false, "reason": "分支未解锁"}
	if points_spent.get(node, false):
		return {"ok": false, "reason": "已学习"}
	if _spent_count() >= _available_points(account_level):
		return {"ok": false, "reason": "天赋点不足"}
	points_spent[node] = true
	return {"ok": true, "reason": ""}


## 已用点数（含各分支）
func _spent_count() -> int:
	return points_spent.size()


## 可用点数 = 每 2 级 1 点（GDD 5.2：60 级 30 点）
static func _available_points(account_level: int) -> int:
	return int(floor(float(account_level) / 2.0))


## 已激活加成汇总：{stat_key: 百分数} + 大节点机制列表
func get_bonus_stats() -> Dictionary:
	var out := {}
	var mechanics: Array[String] = []
	var big_index := 0
	for branch in BRANCHES:
		if not unlocked.get(branch, false):
			continue
		var stat := str(BRANCH_STAT.get(branch, "pct_attack"))
		var smalls := 0
		var bigs := 0
		for node in points_spent:
			if node.begins_with(branch + ".small."):
				smalls += 1
			elif node.begins_with(branch + ".big."):
				bigs += 1
		if smalls > 0:
			out[stat] = float(out.get(stat, 0.0)) + smalls * SMALL_BONUS
		if bigs > 0:
			out[stat] = float(out.get(stat, 0.0)) + bigs * BIG_BONUS
			big_index += bigs
	if big_index > 0:
		for m in BIG_NODE_MECHANICS.slice(0, mini(big_index, BIG_NODE_MECHANICS.size())):
			mechanics.append(str(m))
	return {"stats": out, "mechanics": mechanics}


## 进度 0–1（UI 用）
func progress(account_level: int) -> float:
	var cap := _available_points(account_level)
	if cap <= 0:
		return 0.0
	return float(_spent_count()) / float(cap)
