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
	"技之极意",
]

## 「技之极意」—— 第一步 B4-4 · 1-L10 新增的**第 6 个大节点机制**。
##
## ⚠️ 与其余 5 条机制的区别：**只有它有真实消费端**（产出 `skill_level` flat 键，
##    经 `calc_buff()` → `StatCalculator` → `PlayerController.get_skill_level()`）。
##    其余 5 条仍是**展示字符串**（用户裁定「单点接线」，不整棵天赋树接线）。
const MECHANIC_SKILL_INSIGHT := "技之极意"

## 「技之极意」绑定的**具体大节点 id**（显式、确定性）。
##
## ⚠️ 原实现按「累计已点大节点数」`slice` 顺序分配机制 ⇒ 同一节点在不同学习顺序下
##    拿到不同机制（不确定）；且 3 个分支各只显示 1 个大节点（`branch.big.2`，见
##    `talent_panel.gd`），累计最多 3 ⇒ **永远够不到第 6 项**。故改为按 node id 显式绑定。
## 绑在 `might`（武力，账号 L1 解锁）以保证可达。
const SKILL_INSIGHT_NODE := "might.big.2"

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


## 已激活加成汇总：`{stats: {pct 键}, flat_stats: {flat 键}, mechanics: [...]}`。
##
## ⚠️ `stats` 只放**百分数键**（`pct_attack` 等），`flat_stats` 只放**固定值键**
##    （如 `skill_level`）—— 两者**必须分桶**：`StatCalculator` 只从 flat 汇总固定值键，
##    把 `skill_level` 塞进 `stats`（再由调用方包成 `{"pct": ...}`）会**静默失效**。
##    调用方请直接用 `calc_buff()`，不要手工包桶。
func get_bonus_stats() -> Dictionary:
	var out := {}
	var flat := {}
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
	# ---- 1-L10：唯一有真实消费端的大节点机制（产出 skill_level 固定值）----
	if points_spent.get(SKILL_INSIGHT_NODE, false):
		if not mechanics.has(MECHANIC_SKILL_INSIGHT):
			mechanics.append(MECHANIC_SKILL_INSIGHT)
		flat[GameConstants.STAT_SKILL_LEVEL] = \
			float(flat.get(GameConstants.STAT_SKILL_LEVEL, 0.0)) + 1.0
	return {"stats": out, "flat_stats": flat, "mechanics": mechanics}


## 从存档的「已点节点」构造可直接并入 `StatCalculator` 的 buff 条目。
##
## 返回 `{"pct": {...}, "flat": {...}}`；**未点任何节点时返回 `{}`**（不污染 buffs 字典）。
## 这是天赋 → 属性的**唯一接线入口**（hub 据点面板 / LevelScene 局内共用）。
static func calc_buff(learned_nodes: Array, account_level: int) -> Dictionary:
	var tree := TalentTree.new()
	tree.update_unlocks(account_level)
	for n in learned_nodes:
		tree.points_spent[String(n)] = true
	var b := tree.get_bonus_stats()
	var pct: Dictionary = b["stats"]
	var flat: Dictionary = b.get("flat_stats", {})
	if pct.is_empty() and flat.is_empty():
		return {}
	return {"pct": pct, "flat": flat}


## 进度 0–1（UI 用）
func progress(account_level: int) -> float:
	var cap := _available_points(account_level)
	if cap <= 0:
		return 0.0
	return float(_spent_count()) / float(cap)
