## 掉落引擎（阶段 2 · 任务 2.7 · 掉落与拾取）
##
## 纯静态类：读 `ConfigLoader.loot_tables`（只读表数据），按 GDD 6.1 规则
## 完成「触发 → 件数 → 物品类型 → 稀有度（含难度修正 / 越级惩罚）→ 底材」的 roll。
##
## 返回的掉落物条目（Dictionary，供 LootDrop 地面物件渲染与玩家拾取）：
##   { "type": "gold"|"material"|"consumable"|"equipment"|"rune",
##     "amount": int,                    # 金币 / 材料数量（装备 / 消耗品 / 符文为 1）
##     "item_id": String,                # 装备底材 ID / 消耗品 ID / 符文 ID（金币、材料为空）
##     "rarity": int,                    # GameConstants.Rarity（装备有效；其余 -1）
##     "item_level": int }               # 物品等级 = clamp(怪物等级 ± 三角抖动, 下限 怪-2,
##                                       #                     上限 max(怪等级, 玩家等级))（4-W3）
##
## ⚠️ 随机性：roll 用全局 randf（Godot 伪随机）。验证脚本用 seed() 固定。
## ⚠️ 保底 pity：数据字段保留（elite 有 pity_*），机制阶段 3「掉落手感调优」接入
##    （需会话级幸运状态，本类保持无状态）。
class_name LootRoller


## 掉落 iLvl 的三角抖动跨度（±N）。口径见 `_roll_item_level()`（GDD 04 §3.3 / 工单 4-W3）。
const ITEM_LEVEL_JITTER: int = 2

## 本跑已锁的唯一性组（B5-3 / 6-W6-17）。开局由 level_scene 从
## SaveData.obtained_unique_groups 灌入；拾取唯一装备时即时追加。
## 已锁组对应的底材不再进入掉落池（同组只掉一次）。
static var locked_unique_groups: Array[String] = []


## 开局从持久存档灌入已锁唯一组（每关开始调一次，清空上一跑残留再同步）。
static func sync_locked_unique_groups() -> void:
	locked_unique_groups.clear()
	var data = SaveManager.current_data
	if data != null and data.get("obtained_unique_groups") is Array:
		for g in data.obtained_unique_groups:
			var s := str(g)
			if not s.is_empty() and not locked_unique_groups.has(s):
				locked_unique_groups.append(s)


## 记录一组唯一装备「已获得」（append-only，B5-3 / 6-W6-Q8）。
## 同时锁本跑 + 写持久存档。**分解不调用本函数** ⇒ 永不释放，杜绝
## 「获得 → 分解 → 再刷」无限重复（与「拆解后不能再掉 = 不能」自洽）。
static func obtain_unique(group: String) -> void:
	if group.is_empty():
		return
	if not locked_unique_groups.has(group):
		locked_unique_groups.append(group)
	var data = SaveManager.current_data
	if data != null and not data.obtained_unique_groups.has(group):
		data.obtained_unique_groups.append(group)


## 保底装备：直接 roll **一件装备**，**不经过** `drop_chance` 触发判定。
##
## 供关卡容器实现 `LevelData.guaranteed_equipment_drops`（「必掉的装备件数（保底）」
## —— GDD 0.2 节「变强可感知」）。普通怪 `drop_chance` 只有 8%，
## 一关 30 只怪平均只出 2.4 件，**装备掉落本质上不可靠** —— 保底字段就是为此存在的。
##
## `table_id` 为空时用普通怪表（`monster_normal`）；关卡可用 `LevelData.loot_table_id` 覆盖。
static func roll_guaranteed_equipment(level: int, difficulty: int,
		player_level: int = 0, table_id: String = "",
		magic_find_pct: float = 0.0) -> Dictionary:
	var key := table_id if not table_id.is_empty() else "monster_normal"
	var table: LootTable = ConfigLoader.loot_tables.get(key)
	if table == null:
		return {}
	return _roll_equipment(table, level, difficulty, player_level, magic_find_pct)


## 对一只怪物 roll 掉落（`monster_level` = 怪物等级，是 iLvl 的**基准**而非等值；
## iLvl 口径见 `_roll_item_level()`；`player_level ≤ 0` 时不启用越级惩罚）。
## `magic_find_pct`：局内「幸运」稀有度权重加成（默认 0 = 不变）。
## 返回掉落条目数组（未触发返回空数组）。
static func roll_loot(monster: MonsterData, monster_level: int,
		difficulty: int, player_level: int = 0,
		magic_find_pct: float = 0.0) -> Array[Dictionary]:
	if monster == null:
		return []
	var table: LootTable = ConfigLoader.loot_tables.get(
		ConfigLoader.LOOT_TABLE_BY_TIER.get(monster.tier, "monster_normal"))
	if table == null:
		return []
	# 1) 触发判定
	if randf() > table.drop_chance:
		return []
	# 2) 件数
	var count := randi_range(table.drop_count_range.x, table.drop_count_range.y)
	var drops: Array[Dictionary] = []
	for i in count:
		var drop := _roll_one(table, monster_level, difficulty, player_level, magic_find_pct)
		if not drop.is_empty():
			drops.append(drop)
	return drops


## 单件 roll：物品类型（装备 / 金币 / 材料，按表权重）→ 具体内容
## GDD 6.1 口径：equipment_share（55/80/90%）是**直接概率**；
## 金币 / 材料权重（30/25/20 与 12/40/60）在**剩余部分内**按相对权重瓜分。
static func _roll_one(table: LootTable, level: int, difficulty: int,
		player_level: int, magic_find_pct: float = 0.0) -> Dictionary:
	var r := randf()
	var equip_pct := clampf(table.equipment_share, 0.0, 1.0)
	if r < equip_pct:
		return _roll_equipment(table, level, difficulty, player_level, magic_find_pct)
	var rest := 1.0 - equip_pct
	if rest <= 0.0:
		return _roll_equipment(table, level, difficulty, player_level, magic_find_pct)
	var gold_w := maxf(table.gold_weight, 0.0)
	var mat_w := maxf(table.material_weight, 0.0)
	var consumable_w := maxf(table.consumable_weight, 0.0)
	var total_rest := gold_w + mat_w + consumable_w
	if total_rest <= 0.0:
		return _roll_gold(level)
	var rr := (r - equip_pct) / rest
	if rr < gold_w / total_rest:
		return _roll_gold(level)
	if rr < (gold_w + mat_w) / total_rest:
		return _roll_material(level)
	# 消耗品（步骤 8A 接通：药水掉落，不再回退金币）
	return _roll_consumable(level)


## 消耗品（步骤 8A · 药水）：从已加载的消耗品表随机一枚；数量 1。
## 数据驱动：遍历 ConfigLoader.consumables 的 id，避免硬编码列表漂移。
static func _roll_consumable(level: int) -> Dictionary:
	var ids: Array[String] = []
	for k in ConfigLoader.consumables.keys():
		ids.append(str(k))
	if ids.is_empty():
		ids = ["life_potion"]
	var id := ids[randi() % ids.size()]
	return { "type": "consumable", "amount": 1, "item_id": id,
		"rarity": -1, "item_level": level }


## 符文掉落桶（2-L12 / 2-V12）。
##
## 与主掉落**相互独立**：读本档位掉落表的 `rune_drop_chance`
## （普通 0.02 / 精英 0.08 / BOSS 0.25，随表读取、不写死），命中则**额外**掉一枚符文。
## ⇒ 符文命中不会挤掉金币/材料/装备那次 roll，反之亦然（两次独立 `randf()`）。
##
## `unlocked` 语义（策划 §11.4 Q2 图鉴式）：
##   · **roll 端不做任何过滤** —— 重复符文照常掉出，由拾取端判定「首次解锁 / 转魔石」。
##     这样符文桶永远有效（24 个全解锁后仍持续产出魔石），不会退化成空桶。
##
## ⚠️ 旧实现（2026-09-29 B4 埋点）有两个静默脱钩，本次一并修掉：
##   1. 签名收 `tier: String`，而调用侧只有 `MonsterData.Tier`（**int**）⇒ 永远取不到值；
##   2. 概率硬编码 `{elite, boss}`，而 `ConfigLoader` 从不读 JSON 的 `rune_drop_chance`
##      ⇒ 数据侧写了、运行时不生效（第 5 类坑「String 字段静默脱钩」的同族）。
static func roll_rune_drop(monster: MonsterData, monster_level: int) -> Dictionary:
	if monster == null:
		return {}
	var table: LootTable = ConfigLoader.loot_tables.get(
		ConfigLoader.LOOT_TABLE_BY_TIER.get(monster.tier, "monster_normal"))
	if table == null:
		return {}
	var chance := clampf(table.rune_drop_chance, 0.0, 1.0)
	if chance <= 0.0 or randf() > chance:
		return {}
	var ids := all_rune_ids()
	if ids.is_empty():
		return {}
	return { "type": "rune", "amount": 1,
		"item_id": ids[randi() % ids.size()],
		"rarity": -1, "item_level": maxi(1, monster_level) }


## 全部符文 id（**数据驱动**，遍历 `ConfigLoader.runes` 的键，避免硬编码 24 条列表漂移）。
## 消费点：`roll_rune_drop()`（掉落）/ 校验脚本（2-V12）。
static func all_rune_ids() -> Array[String]:
	var ids: Array[String] = []
	if ConfigLoader.runes is Dictionary:
		for k in ConfigLoader.runes.keys():
			ids.append(str(k))
	ids.sort() # 稳定顺序：便于验证脚本固定 seed 复现
	return ids


## 重复符文 → 魔石转化数量（策划 §11.4「重复掉落自动转化为魔石，避免垃圾堆积」）。
##
## 口径与 `_roll_material()` **完全一致**（1 + (L-1)/5，至少 1）——「一颗重复符文 ≈ 一次材料掉落」，
## 不另立一套数值，避免两处常量各自漂移（见坑：常數多處複製）。
static func rune_duplicate_material_amount(monster_level: int) -> int:
	return maxi(1, 1 + int(float(maxi(1, monster_level) - 1) / GameConstants.MATERIAL_LEVEL_STEP))


## 金币：round(4 × 1.12^(L-1) × randf_range(0.8, 1.2))，至少 1
static func _roll_gold(level: int) -> Dictionary:
	var amount := maxi(1, int(round(
		GameConstants.GOLD_BASE_AT_L1 * pow(GameConstants.GOLD_GROWTH, float(level - 1))
		* randf_range(0.8, 1.2))))
	return { "type": "gold", "amount": amount, "item_id": "", "rarity": -1, "item_level": level }


## 材料（魔石）：1 + (L-1)/5，至少 1
static func _roll_material(level: int) -> Dictionary:
	var amount := maxi(1, 1 + int(float(level - 1) / GameConstants.MATERIAL_LEVEL_STEP))
	return { "type": "material", "amount": amount, "item_id": "", "rarity": -1, "item_level": level }


## 装备：稀有度（难度修正 + 越级惩罚）→ iLvl（三角抖动 + clamp）→ 底材（drop_weight 加权，
## 稀有度 / iLvl 过滤）→ 词缀（AffixRoller，任务 3.2）：掉落即定型，拾取直接入包。
static func _roll_equipment(table: LootTable, level: int, difficulty: int,
		player_level: int, magic_find_pct: float = 0.0) -> Dictionary:
	# 稀有度与 iLvl 是**两次独立 roll**：
	#   · 稀有度的越级惩罚看的是「怪物等级 vs 玩家等级」（口径不变）；
	#   · iLvl 看的是「怪物等级 ± 抖动，上限 max(怪物等级, 玩家等级)」（4-W3）。
	var rarity := _roll_rarity(table.rarity_weights, difficulty, player_level, level, magic_find_pct)
	var ilvl := _roll_item_level(level, player_level)
	var template := _pick_template(rarity, ilvl)
	if template == null:
		# 装备池在该稀有度/iLvl 下无可用底材（正常不会发生）——回退金币，避免空掉落
		return _roll_gold(level)
	var item := AffixRoller.roll_full_equipment(template, ilvl, rarity)
	return {
		"type": "equipment", "amount": 1,
		"item_id": template.id, "rarity": rarity, "item_level": ilvl,
		"instance": item.to_dict(),
	}


## 掉落物等级（iLvl）—— GDD 04 §3.3「修复三：iLvl 上限释放」（工单 4-W3）。
##
##   item_level = clamp(怪物等级 + 三角抖动(±2),
##                      下限 = max(1, 怪物等级 - 2),
##                      上限 = max(怪物等级, 玩家等级))
##
## 设计意图：
##   · 「打高等级怪掉好装备」的直觉保留 —— 基准仍是**怪物等级**；
##   · 玩家等级 ≥ 怪等级时上限抬到玩家等级 ⇒ 清低关的掉落能跟上玩家
##     （但抖动跨度只有 ±2，所以实际最高到 怪物等级 + 2）；
##   · 玩家等级 < 怪等级时上限被压回怪物等级 ⇒ 低级玩家越级刷怪**拿不到**超模装备；
##   · 路线 A（4-W10）下账号上限 20 ⇒ 该上限天然被账号等级封顶在 20，
##     **不需要再加硬编码上限**（GDD 04 §3.3 路线 A 补充：公式保持原样即可）；
##   · 下限用 `max(1, ...)` 而不是裸的 `怪物等级 - 2`：iLvl 会参与
##     `item_stat_ilvl_scale()` / `affix_ilvl_scale()` / `required_level_for()`，
##     0 或负数会算错（L1 怪是唯一触发点）。
static func _roll_item_level(monster_level: int, player_level: int) -> int:
	var lo := maxi(1, monster_level - ITEM_LEVEL_JITTER)
	var hi := maxi(monster_level, maxi(player_level, 1))
	return clampi(monster_level + _triangular_jitter(ITEM_LEVEL_JITTER), lo, hi)


## 三角分布抖动：返回 `[-span, span]`，**中心 0 权重最高**（GDD 02 掉落 iLvl 三角分布）。
##
## 两个独立 `[0, span]` 均匀分布之和 - span ⇒ 三角分布（权重 span+1 : span : … : 1）。
## 用全局 `randi_range`（与其它 roll 同一套 RNG）⇒ `seed()` 能固定整条链路。
static func _triangular_jitter(span: int) -> int:
	if span <= 0:
		return 0
	return randi_range(0, span) + randi_range(0, span) - span


## 稀有度 roll：权重数组（难度修正后）归一化加权抽样。
##
## `magic_find_pct`：局内「幸运」加成（默认 0 = 不变）。**工程侧默认口径**：把**非普通**
##   （`rarity > Rarity.COMMON`）的权重统一 ×(1 + pct/100) —— 即「白装占比下降、稀有度
##   整体上移」，非普通之间的相对比例不变。数值口径待阶段 12「增益管线贯通」按 GDD 复核。
static func _roll_rarity(weights: Array, difficulty: int,
		player_level: int, monster_level: int, magic_find_pct: float = 0.0) -> int:
	var adj := GameConstants.adjust_rarity_weights_by_difficulty(
		weights, difficulty, player_level, monster_level)
	if magic_find_pct > 0.0:
		var mult := 1.0 + magic_find_pct / 100.0
		for i in adj.size():
			if i > GameConstants.Rarity.COMMON:
				adj[i] = float(adj[i]) * mult
	var total := 0.0
	for w in adj:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return GameConstants.Rarity.COMMON
	var r := randf() * total
	for i in adj.size():
		r -= maxf(float(adj[i]), 0.0)
		if r <= 0.0:
			return i
	return adj.size() - 1


## 底材 pick：equipment_templates 中稀有度区间 / 等级区间匹配者，按 drop_weight 加权。
## 套装稀有度（SET）优先取带 set_id 的底材；隐藏（HIDDEN）从全池按 drop_weight 抽。
static func _pick_template(rarity: int, level: int) -> EquipmentData:
	var pool: Array[EquipmentData] = []
	for template: EquipmentData in ConfigLoader.equipment_templates.values():
		if rarity < template.rarity_min or rarity > template.rarity_max:
			continue
		if level < template.item_level_min or level > template.item_level_max:
			continue
		if rarity == GameConstants.Rarity.SET and template.set_id.is_empty():
			continue
		# B5-3 / 6-W6-17：唯一组已锁（本跑或历史已获得）⇒ 该底材不再进池。
		if not template.unique_group.is_empty() and locked_unique_groups.has(template.unique_group):
			continue
		pool.append(template)
	if pool.is_empty():
		return null
	var total := 0.0
	for t in pool:
		total += maxf(t.drop_weight, 0.0)
	if total <= 0.0:
		return pool[0]
	var r := randf() * total
	for t in pool:
		r -= maxf(t.drop_weight, 0.0)
		if r <= 0.0:
			return t
	return pool[pool.size() - 1]
