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
##     "item_level": int }               # 物品等级 = 怪物等级 + 掉落表 item_level_spread
##                                       #   非对称三角分布（GDD 02 §6.2 / 2-L13）
##
## ⚠️ 随机性：roll 用全局 randf（Godot 伪随机）。验证脚本用 seed() 固定。
## ⚠️ 保底 pity：数据字段保留（elite 有 pity_*），机制阶段 3「掉落手感调优」接入
##    （需会话级幸运状态，本类保持无状态）。
class_name LootRoller


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
	#   · 稀有度的越级惩罚看的是「怪物等级 vs 玩家等级」（见 _roll_rarity）；
	#   · iLvl 看的是「怪物等级 + 本表 item_level_spread 三角分布」（2-L13 / GDD 02 §6.2）。
	var rarity := _roll_rarity(table.rarity_weights, difficulty, player_level, level, magic_find_pct)
	var ilvl := _roll_item_level(table, level)
	var template := _pick_template(rarity, ilvl)
	if template == null:
		# iLvl 可能超出装备池顶（如 L20 BOSS 表 +8 冲到 28，而底材 item_level_max ≤ 22）：
		# 降到该稀有度「可用底材的最高 iLvl」重选，保证 BOSS 必掉装备而不是退化成金币。
		var cap := _max_template_level(rarity)
		if cap > 0 and ilvl > cap:
			ilvl = cap
			template = _pick_template(rarity, ilvl)
	if template == null:
		# 该稀有度在任何 iLvl 下都无可用底材（如特殊档无池）——回退金币，避免空掉落
		return _roll_gold(level)
	var item := AffixRoller.roll_full_equipment(template, ilvl, rarity)
	return {
		"type": "equipment", "amount": 1,
		"item_id": template.id, "rarity": rarity, "item_level": ilvl,
		"instance": item.to_dict(),
	}


## 掉落物等级（iLvl）—— GDD 02 §6.2「掉落 iLvl 分布」（工单 2-D6 / 2-L13 / 验收 V13）。
##
##   item_level = max(1, 怪物等级 + min_mod,
##                    怪物等级 + 三角分布[min_mod, max_mod]（峰值 mode_mod）
##                    +（bonus_chance 命中 ? bonus_mod : 0）)
##
## 口径（随掉落表 `item_level_spread` 读取，代码不写死，见 `LootTable`）：
##   · normal：怪等级 ±3（峰值 0）；
##   · elite：怪等级 ±2（峰值 0），另 10% 概率 +5；
##   · boss：怪等级 +3~+8（峰值 +5）⇒ BOSS 必掉高 iLvl；
##   · 深渊表另配。
##
## 越级平衡（2026-10-15 起 iLvl 层不再 clamp）：
##   旧 4-W3 公式 `hi=max(怪,玩家)` 会把 BOSS 表的 +3~+8 正向奖励压平（玩家平级打 BOSS 时
##   hi=怪等级，BOSS 永远掉不出 +3~+8）。表的 max_mod 已是天然 iLvl 天花板，越级刷装改由
##   两道独立机制兜底 —— ① 稀有度越级惩罚（玩家比怪低 >3 级，紫/橙/红 ×0.5，见 _roll_rarity）；
##   ② 装备需求等级 required_level = ilvl-2（低级玩家拿到高 iLvl 也穿不上）。
##   · 下限 max(1, ...)：iLvl 参与 item_stat_ilvl_scale() / affix_ilvl_scale() /
##     required_level_for()，0 或负数会算错（L1 怪是唯一触发点）。
##   · 装备池顶（底材 item_level_max ≤ 22）由 `_roll_equipment()` 的 cap clamp 兜底，不在此处。
static func _roll_item_level(table: LootTable, monster_level: int) -> int:
	var mod := _triangular_int(table.ilvl_min_mod, table.ilvl_max_mod, table.ilvl_mode_mod)
	if table.ilvl_bonus_mod != 0 and table.ilvl_bonus_chance > 0.0 \
			and randf() < table.ilvl_bonus_chance:
		mod += table.ilvl_bonus_mod
	var lo := maxi(1, monster_level + table.ilvl_min_mod)
	return maxi(lo, monster_level + mod)


## 非对称整数三角分布：返回 `[min_mod, max_mod]` 内的整数偏移，**峰值在 mode_mod**
## （GDD 02 §6.2）。连续三角分布逆变换采样后四舍五入（`randf()` 随全局 `seed()` 固定）。
## 两端在足够样本下可达（验收 V13：基础掉落 iLvl ∈ [怪+min_mod, 怪+max_mod]）。
static func _triangular_int(min_mod: int, max_mod: int, mode_mod: int) -> int:
	if max_mod <= min_mod:
		return min_mod
	var lo := mini(min_mod, mode_mod)
	var hi := maxi(max_mod, mode_mod)
	var mode := clampi(mode_mod, lo, hi)
	var span := float(hi - lo)
	var fc := float(mode - lo) / span  # 峰值处的累积概率
	var u := randf()
	var v: float
	if u < fc:
		v = float(lo) + sqrt(u * span * float(mode - lo))
	else:
		v = float(hi) - sqrt((1.0 - u) * span * float(hi - mode))
	return clampi(int(round(v)), lo, hi)


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


## 该稀有度下装备池能提供的**最高 item_level**（遍历底材，过滤口径同 `_pick_template`
## 但不限 iLvl 区间）。无任何底材时返回 0。
## 用途：BOSS 表把 iLvl 冲到池顶之上（如 L20 +8=28 > 底材 max 22）时，把 iLvl 收回到池顶，
## 保证「必掉装备」而不是空池回退金币（2-L13 接线时新增）。
static func _max_template_level(rarity: int) -> int:
	var top := 0
	for template: EquipmentData in ConfigLoader.equipment_templates.values():
		if rarity < template.rarity_min or rarity > template.rarity_max:
			continue
		if rarity == GameConstants.Rarity.SET and template.set_id.is_empty():
			continue
		if not template.unique_group.is_empty() and locked_unique_groups.has(template.unique_group):
			continue
		top = maxi(top, template.item_level_max)
	return top
