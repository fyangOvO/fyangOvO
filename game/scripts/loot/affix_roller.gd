## 词缀生成器（任务 3.2 · 纯静态 class_name）
##
## 职责：给一件**具体装备实例**随机 roll 词缀：
##   条数（按稀有度区间）→ 前后缀拆分（GDD 3.2.3 权威表约束）
##   → 从装备的词缀池（affix_pool_ids）收集候选（部位 / 稀有度过滤）
##   → 权重 + 互斥组逐条 pick → 数值（Base × iLvl 缩放 × 品质系数）
##   → 紫+ 概率「强化词缀」（×1.5）→ 红装神话独立槽（不占普通位）。
##
## 纯静态（不挂场景）：任何地方 `AffixRoller.roll_affixes(...)` 即可调用。
## 掉落（LootRoller）与商店 / 锻造共用本生成器，保证全游戏词缀口径一致。
class_name AffixRoller
extends RefCounted

## 品质档权重（与 GameConstants.AFFIX_ROLL_QUALITY_TIERS 一一对应）：
## 0.60 灰 35% / 0.75 绿 30% / 0.90 蓝 20% / 1.00 黄 10% / 1.15 橙 5%。
## GDD 只给了 5 阶档位与 UI 染色，未给概率 —— 工程侧默认曲线（越高级越稀有）。
const QUALITY_WEIGHTS: Array[float] = [35.0, 30.0, 20.0, 10.0, 5.0]

## 「强化词缀」触发概率（%），按稀有度：紫 15 / 橙 20 / 红 25 / 彩 20 / 绿 10。
## GDD 3.2：「史诗（紫）可含 1 条强化词缀（数值 ×1.5）」——工程侧按档位线性上浮。
const EMPOWER_CHANCE_BY_RARITY: Array[float] = [
	0.0,   # COMMON 白
	0.0,   # MAGIC 蓝
	0.0,   # RARE 黄
	15.0,  # EPIC 紫
	20.0,  # LEGENDARY 橙
	25.0,  # MYTHIC 红
	10.0,  # SET 绿（套装单件弱于紫，概率同档压低）
	20.0,  # HIDDEN 彩（锚定橙装）
]

## 神话词缀 ID（红装独立槽，不占普通词缀位）
const MYTHIC_AFFIX_ID: String = "mythic_all_attributes"


## 给一件装备 roll 全部普通词缀（不含神话/彩蛋/套装标记特殊槽）。
## 返回 Array[AffixRoll]（已注入 template 引用）。
static func roll_affixes(template: EquipmentData, item_level: int, rarity: int,
		rng: RandomNumberGenerator = null) -> Array[AffixRoll]:
	var out: Array[AffixRoll] = []
	if template == null:
		return out
	rarity = clampi(rarity, 0, GameConstants.RARITY_COUNT - 1)

	# 1) 条数 + 前后缀拆分（GDD 3.2.3 不变式：前缀 + 后缀 = 条数）
	var split := _roll_affix_split(rarity, rng)

	# 2) 候选池收集（多池合并去重 + 部位 / 稀有度过滤）
	var candidates := _collect_candidates(template, rarity)

	# 3) 分别 roll 前缀 / 后缀（互斥组 + 权重）
	var chosen_groups := {}
	for i in split.x:
		var affix := _pick_weighted(candidates, chosen_groups, GameConstants.AffixPosition.PREFIX, rng)
		if affix == null:
			break
		chosen_groups[affix.get_exclusive_group()] = true
		out.append(_make_roll(affix, item_level, rng))
	for i in split.y:
		var affix := _pick_weighted(candidates, chosen_groups, GameConstants.AffixPosition.SUFFIX, rng)
		if affix == null:
			break
		chosen_groups[affix.get_exclusive_group()] = true
		out.append(_make_roll(affix, item_level, rng))

	# 4) 紫+ 概率强化：把一条已 roll 词缀 ×1.5
	_maybe_empower(out, rarity, rng)
	return out


## 便捷入口：由底材生成一件**完整装备**（基础字段 + 词缀 + 引用注入）。
static func roll_full_equipment(template: EquipmentData, item_level: int, rarity: int,
		rng: RandomNumberGenerator = null) -> EquipmentInstance:
	var item := EquipmentInstance.create_from_template(template, item_level, rarity)
	item.affixes = roll_affixes(template, item_level, rarity, rng)
	# 红装神话独立槽（不占普通位，GDD 3.2.2：普通 6–7 + 神话 1 + 传奇 1）
	if rarity == GameConstants.Rarity.MYTHIC:
		var mythic := _make_mythic_roll(item_level, rng)
		if mythic != null:
			item.affixes.append(mythic)
	# 传奇特效（GDD 3.2.2：橙必含 1 条传奇特效，红 1 条 + 神话词缀）：
	# 优先底材绑定，否则从同部位特效池抽取（掉落即定型，供 3.4 重铸抽取）
	if rarity >= GameConstants.Rarity.LEGENDARY:
		var fx_id := template.legendary_effect_id
		if fx_id.is_empty():
			fx_id = LegendaryEffectSystem.roll_for_slot(
				GameConstants.EQUIP_SLOT_KEYS[template.slot], "", rng)
		item.legendary_effect_id = fx_id
	# 已 roll 出的词缀全部注入模板引用（掉落物直接可用，无需二次 resolve）
	for roll in item.affixes:
		roll.template = ConfigLoader.get_affix(roll.affix_id)
	return item


# =============================================================================
# 内部实现
# =============================================================================

## 条数区间 + 前后缀拆分。
## 返回 Vector2i(prefix_count, suffix_count)，保证不超 GDD 3.2.3 上限。
static func _roll_affix_split(rarity: int, rng: RandomNumberGenerator) -> Vector2i:
	var range: Vector2i = GameConstants.RARITY_AFFIX_RANGE[rarity]
	var total := _randi_range(rng, range.x, range.y)
	var prefix_limit := GameConstants.RARITY_PREFIX_LIMIT[rarity]
	var suffix_limit := GameConstants.RARITY_SUFFIX_LIMIT[rarity]
	var prefix_min := maxi(0, total - suffix_limit)
	var prefix_max := mini(total, prefix_limit)
	if prefix_max < prefix_min:
		prefix_max = prefix_min
	var prefix_count := _randi_range(rng, prefix_min, prefix_max)
	return Vector2i(prefix_count, total - prefix_count)


## 候选池收集：装备 affix_pool_ids 的全部池 → 去重 → 部位 / 稀有度过滤。
## 神话词缀不在此收集（独立槽单独处理），避免红装普通位出现神话词缀。
static func _collect_candidates(template: EquipmentData, rarity: int) -> Array[AffixData]:
	var out: Array[AffixData] = []
	var seen := {}
	for pool_id in template.affix_pool_ids:
		for affix in ConfigLoader.get_affixes_in_pool(String(pool_id), template.slot):
			if seen.has(affix.id):
				continue
			seen[affix.id] = true
			if affix.min_rarity >= 0 and rarity < affix.min_rarity:
				continue
			if affix.id == MYTHIC_AFFIX_ID:
				continue
			out.append(affix)
	return out


## 权重 + 互斥组 pick。position 用于按前后缀分别抽池（词缀的 position 必须匹配）。
static func _pick_weighted(candidates: Array[AffixData], chosen_groups: Dictionary,
		position: int, rng: RandomNumberGenerator) -> AffixData:
	# 过滤：position 匹配 + 互斥组未占用
	var usable: Array[AffixData] = []
	var total_weight := 0.0
	for affix in candidates:
		if affix.position != position:
			continue
		if chosen_groups.has(affix.get_exclusive_group()):
			continue
		usable.append(affix)
		total_weight += affix.weight
	if usable.is_empty() or total_weight <= 0.0:
		return null
	var r := _randf(rng) * total_weight
	var acc := 0.0
	for affix in usable:
		acc += affix.weight
		if r <= acc:
			return affix
	return usable[usable.size() - 1]


## 数值 roll：Base(iLvl=1 区间均匀) × (1 + 0.085×(iLvl-1)) × 品质系数
static func _make_roll(affix: AffixData, item_level: int, rng: RandomNumberGenerator) -> AffixRoll:
	var quality := _roll_quality(rng)
	var base := affix.roll_base_value(rng)
	var value := base * GameConstants.affix_ilvl_scale(item_level) * quality
	var roll := AffixRoll.create(affix.id, value, quality)
	roll.template = affix
	return roll


## 品质档：按权重抽 AFFIX_ROLL_QUALITY_TIERS 之一
static func _roll_quality(rng: RandomNumberGenerator) -> float:
	var total := 0.0
	for w in QUALITY_WEIGHTS:
		total += float(w)
	var r := _randf(rng) * total
	var acc := 0.0
	for i in range(QUALITY_WEIGHTS.size()):
		acc += QUALITY_WEIGHTS[i]
		if r <= acc:
			return GameConstants.AFFIX_ROLL_QUALITY_TIERS[i]
	return GameConstants.AFFIX_ROLL_QUALITY_TIERS[GameConstants.AFFIX_ROLL_QUALITY_TIERS.size() - 1]


## 紫+ 概率强化：把一条已有词缀 is_empowered（数值 ×1.5，GDD 3.2「对已有词缀数值 ×1.5」）
static func _maybe_empower(rolls: Array[AffixRoll], rarity: int, rng: RandomNumberGenerator) -> void:
	if rolls.is_empty():
		return
	var chance: float = EMPOWER_CHANCE_BY_RARITY[clampi(rarity, 0, EMPOWER_CHANCE_BY_RARITY.size() - 1)]
	if chance <= 0.0:
		return
	if _randf(rng) * 100.0 >= chance:
		return
	var idx := _randi_range(rng, 0, rolls.size() - 1)
	var roll := rolls[idx]
	roll.is_empowered = true
	roll.value = roll.value * 1.5


## 红装神话词缀（独立槽）：只从 mythic_pool 取 min_rarity=MYTHIC 的词缀
static func _make_mythic_roll(item_level: int, rng: RandomNumberGenerator) -> AffixRoll:
	var mythic_affix := ConfigLoader.get_affix(MYTHIC_AFFIX_ID) as AffixData
	if mythic_affix == null:
		return null
	return _make_roll(mythic_affix, item_level, rng)


# =============================================================================
# 随机数辅助（rng 为 null 时用全局随机）
# =============================================================================

static func _randi_range(rng: RandomNumberGenerator, from: int, to: int) -> int:
	if rng == null:
		return randi_range(from, to)
	return rng.randi_range(from, to)


static func _randf(rng: RandomNumberGenerator) -> float:
	if rng == null:
		return randf()
	return rng.randf()
