## 掉落引擎（阶段 2 · 任务 2.7 · 掉落与拾取）
##
## 纯静态类：读 `ConfigLoader.loot_tables`（只读表数据），按 GDD 6.1 规则
## 完成「触发 → 件数 → 物品类型 → 稀有度（含难度修正 / 越级惩罚）→ 底材」的 roll。
##
## 返回的掉落物条目（Dictionary，供 LootDrop 地面物件渲染与玩家拾取）：
##   { "type": "gold"|"material"|"equipment",
##     "amount": int,                    # 金币 / 材料数量（装备为 1）
##     "item_id": String,                # 装备底材 ID（非装备为空）
##     "rarity": int,                    # GameConstants.Rarity（装备有效；金币/材料 -1）
##     "item_level": int }               # 物品等级 = 怪物等级
##
## ⚠️ 随机性：roll 用全局 randf（Godot 伪随机）。验证脚本用 seed() 固定。
## ⚠️ 保底 pity：数据字段保留（elite 有 pity_*），机制阶段 3「掉落手感调优」接入
##    （需会话级幸运状态，本类保持无状态）。
class_name LootRoller


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


## 对一只怪物 roll 掉落（怪物等级 = 掉落物等级；player_level ≤ 0 时不启用越级惩罚）。
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
	# 消耗品尚未实现（阶段 3.8 后），回退金币
	return _roll_gold(level)


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


## 装备：稀有度（难度修正 + 越级惩罚）→ 底材（drop_weight 加权，稀有度/等级过滤）
## → 词缀（AffixRoller，任务 3.2）：掉落即定型，拾取直接入包。
static func _roll_equipment(table: LootTable, level: int, difficulty: int,
		player_level: int, magic_find_pct: float = 0.0) -> Dictionary:
	var rarity := _roll_rarity(table.rarity_weights, difficulty, player_level, level, magic_find_pct)
	var template := _pick_template(rarity, level)
	if template == null:
		# 装备池在该稀有度/等级下无可用底材（正常不会发生）——回退金币，避免空掉落
		return _roll_gold(level)
	var item := AffixRoller.roll_full_equipment(template, level, rarity)
	return {
		"type": "equipment", "amount": 1,
		"item_id": template.id, "rarity": rarity, "item_level": level,
		"instance": item.to_dict(),
	}


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
