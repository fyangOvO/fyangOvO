## 配置加载器（Autoload · 单例名 `ConfigLoader`）
##
## 职责：把 `game/data/` 下的**纯数据文件**（.json 为主，.tres 可选）
##       解析为 `game/resources/` 下的**自定义 Resource 对象**，并建立 ID → 对象的注册表。
##
## 设计原则：
##   1. **数据与代码分离**：策划只改 `game/data/*.json`，不碰 GDScript。
##   2. **加载期一次性校验**：格式错误在启动时就报错并汇总，不带进运行时。
##   3. **只读**：本加载器不提供「运行时改数据」的接口。掉落 / 锻造等业务不得回写模板。
##
## 数据目录约定：
##   `game/data/equipment/`     → EquipmentData（可含子目录，递归扫描）
##   `game/data/affixes/`       → AffixData
##   `game/data/affix_pools/`   → 词缀池表（pools.json，装备 affix_pool_ids 引用）
##   `game/data/monsters/`      → MonsterData
##   `game/data/levels/`        → LevelData
##   `game/data/loot_tables/`   → LootTable
##
## JSON 文件结构：可以是**单个对象**，也可以是**对象数组**（一个文件放多条）。
##
## 何时重新加载：编辑器内改完 JSON 后按 F6 重跑，或调用 `reload_all()`。
extends Node

# =============================================================================
# 数据目录
# =============================================================================

const DATA_ROOT: String = "res://data"

const DIR_EQUIPMENT: String = DATA_ROOT + "/equipment"
const DIR_AFFIXES: String = DATA_ROOT + "/affixes"
const DIR_AFFIX_POOLS: String = DATA_ROOT + "/affix_pools"
const DIR_LEGENDARY_EFFECTS: String = DATA_ROOT + "/legendary_effects"
const DIR_MONSTERS: String = DATA_ROOT + "/monsters"
const DIR_BOSSES: String = DATA_ROOT + "/bosses"
const DIR_LEVELS: String = DATA_ROOT + "/levels"
const DIR_LOOT_TABLES: String = DATA_ROOT + "/loot_tables"
const DIR_SETS: String = DATA_ROOT + "/sets"
const DIR_SKILLS: String = DATA_ROOT + "/skills"
const DIR_CONSUMABLES: String = DATA_ROOT + "/consumables"
const DIR_CLASSES: String = DATA_ROOT + "/classes"

## 档位 → 默认掉落表 ID 的映射（与 `game/data/loot_tables/` 中的文件名一致）
const LOOT_TABLE_BY_TIER: Dictionary = {
	0: "monster_normal", # MonsterData.Tier.NORMAL
	1: "monster_elite",  # MonsterData.Tier.ELITE
	2: "monster_boss",   # MonsterData.Tier.BOSS
}

# =============================================================================
# 注册表（ID → Resource）
# =============================================================================

var equipment_templates: Dictionary = {} ## String → EquipmentData
var affixes: Dictionary = {}             ## String → AffixData
var affix_pools: Dictionary = {}         ## String → {display_name: String, affix_ids: Array[String]}
var legendary_effects: Dictionary = {}   ## String → Dictionary（传奇特效定义，任务 3.5）
var monsters: Dictionary = {}            ## String → MonsterData
var bosses: Dictionary = {}              ## String → Dictionary（BOSS 阶段机制，任务 6.3）
var levels: Dictionary = {}              ## String → LevelData
var loot_tables: Dictionary = {}         ## String → LootTable
var sets: Dictionary = {}                ## String → SetData
var skills: Dictionary = {}              ## String → SkillData
var classes: Dictionary = {}             ## String → Dictionary（职业模板，任务 7.1 角色选择）
var consumables: Dictionary = {}       ## String → Dictionary（消耗品/药水，步骤 8A）

## 加载过程中的错误信息（启动时若有内容，说明数据文件有问题）
var load_errors: Array[String] = []

## 是否已完成一次加载
var is_loaded: bool = false


func _ready() -> void:
	load_all()


# =============================================================================
# 加载入口
# =============================================================================

## 重新加载全部数据（清空注册表后重来）
##
## 顺序要求：
##   1. 底材必须在套装之前加载 —— 套装的跨表校验要反向查底材
##   2. `_cross_validate()` 必须在**所有**表加载完成后调用，否则引用检查会误报
func load_all() -> void:
	equipment_templates.clear()
	affixes.clear()
	affix_pools.clear()
	legendary_effects.clear()
	monsters.clear()
	bosses.clear()
	levels.clear()
	loot_tables.clear()
	sets.clear()
	skills.clear()
	classes.clear()
	consumables.clear()
	load_errors.clear()

	# 确保用户内容目录存在（`user://content/{characters,fx,tilesets,levels}/`）。
	# 放在加载之前：用户要「自己换素材」得先能找到该往哪放。此前 ContentPaths
	# 提供了 ensure_user_dirs() 但**从未被任何地方调用** ⇒ 目录从不创建，
	# 用户只能自己猜路径（典型的「声明了接口但没人消费」）。
	#
	# 同时把**解析后的绝对路径**打出来：`user://` 的根随启动方式变化
	# （正常启动是 %APPDATA%，无头/便携模式会落到 <项目目录>\Godot\app_userdata\），
	# 所以不能让用户去猜，必须由程序告诉他往哪放。
	ContentPaths.ensure_user_dirs()
	print("[ContentPaths] 用户内容目录（替换素材放这里）：%s" % ContentPaths.user_root_absolute())

	_load_equipment_dir(DIR_EQUIPMENT)
	_load_affix_dir(DIR_AFFIXES)
	_load_affix_pool_dir(DIR_AFFIX_POOLS)
	_load_legendary_effect_dir(DIR_LEGENDARY_EFFECTS)
	_load_monster_dir(DIR_MONSTERS)
	_load_boss_dir(DIR_BOSSES)
	_load_level_dir(DIR_LEVELS)
	# 用户关卡覆盖（最高优先）：`user://content/levels/*.json`，按关卡 id 覆盖内置关卡。
	# 用户可只改一关的 `layout.cells` 而不动仓库里的数据表。
	# **必须在内置之后加载**：`_register()` 按 id 覆盖，后加载的胜出。
	# 目录不存在时 `_scan_recursive()` 静默返回（"允许阶段性只提供部分数据表"）。
	_load_level_dir(ContentPaths.class_dir(ContentPaths.CLASS_LEVELS))
	_load_loot_table_dir(DIR_LOOT_TABLES)
	_load_set_dir(DIR_SETS)
	_load_skill_dir(DIR_SKILLS)
	_load_class_dir(DIR_CLASSES)
	_load_consumable_dir(DIR_CONSUMABLES)

	_cross_validate()

	is_loaded = true

	var counts := get_entry_counts()
	if load_errors.is_empty():
		print("[ConfigLoader] 数据加载完成：", counts)
	else:
		push_warning("[ConfigLoader] 数据加载完成，但有 %d 处问题，详见下方输出。" % load_errors.size())
		for err in load_errors:
			push_warning("[ConfigLoader] " + err)

	EventBus.config_loaded.emit(counts)


## 各表条目数（供日志与 `config_loaded` 信号）
##
## 注意：套装件本身也是底材，已计入 `equipment`；`sets` 只统计套装定义条数。
func get_entry_counts() -> Dictionary:
	return {
		"equipment": equipment_templates.size(),
		"affixes": affixes.size(),
		"affix_pools": affix_pools.size(),
		"legendary_effects": legendary_effects.size(),
		"monsters": monsters.size(),
		"bosses": bosses.size(),
		"levels": levels.size(),
		"loot_tables": loot_tables.size(),
		"sets": sets.size(),
		"skills": skills.size(),
		"classes": classes.size(),
		"consumables": consumables.size(),
	}


# =============================================================================
# 各表加载
# =============================================================================

func _load_equipment_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var res := EquipmentData.new()
			res.id = String(raw.get("id", ""))
			res.display_name = String(raw.get("display_name", ""))
			res.slot = _to_slot(raw.get("slot", "main_hand"))
			res.weapon_archetype = _to_weapon_archetype(raw.get("weapon_archetype", ""))
			res.base_stats = _to_float_dict(raw.get("base_stats", {}))
			res.implicit_affix_id = String(raw.get("implicit_affix_id", ""))
			res.affix_pool_ids = _to_string_array(raw.get("affix_pool_ids", []))
			res.item_level_min = int(raw.get("item_level_min", 1))
			res.item_level_max = int(raw.get("item_level_max", GameConstants.LEVEL_MAX))
			res.rarity_min = GameConstants.rarity_from_key(String(raw.get("rarity_min", "common")))
			res.rarity_max = GameConstants.rarity_from_key(String(raw.get("rarity_max", "legendary")))
			res.icon_path = String(raw.get("icon_path", ""))
			res.set_id = String(raw.get("set_id", ""))
			res.drop_weight = float(raw.get("drop_weight", 100.0))
			res.craftable = bool(raw.get("craftable", true))
			res.undismantlable = bool(raw.get("undismantlable", false))
			res.legendary_effect_id = String(raw.get("legendary_effect_id", ""))
			res.growth_stat_key = String(raw.get("growth_stat_key", ""))
			res.growth_max = float(raw.get("growth_max", GameConstants.HIDDEN_GROWTH_MAX_BONUS * 100.0))
			_register(equipment_templates, res.id, res, entry)
			_validate(res, entry)


func _load_affix_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var res := AffixData.new()
			res.id = String(raw.get("id", ""))
			res.display_name = String(raw.get("display_name", ""))
			res.description_template = String(raw.get("description_template", ""))
			res.category = _to_affix_category(raw.get("category", "attack"))
			res.position = _to_affix_position(raw.get("position", "prefix"))
			res.is_percentage = bool(raw.get("is_percentage", false))
			res.value_min = float(raw.get("value_min", 0.0))
			res.value_max = float(raw.get("value_max", 0.0))
			res.decimal_places = int(raw.get("decimal_places", 0))
			res.stat_key = String(raw.get("stat_key", ""))
			res.allowed_slots = _to_slot_array(raw.get("allowed_slots", []))
			res.scales_with_item_level = bool(raw.get("scales_with_item_level", true))
			res.can_reroll = bool(raw.get("can_reroll", true))
			res.exclusive_group = String(raw.get("exclusive_group", ""))
			res.min_rarity = int(raw.get("min_rarity", -1))
			res.weight = float(raw.get("weight", 100.0))
			res.obtainable_from_craft = bool(raw.get("obtainable_from_craft", true))
			_register(affixes, res.id, res, entry)
			_validate(res, entry)


## 词缀池表：`data/affix_pools/*.json`（结构 `{"pools": [{id, display_name, affix_ids}]}`）。
## 池是**显式词缀 ID 列表**（策划可控），roll 时还要叠加词缀自身的部位 / 稀有度过滤。
func _load_affix_pool_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var pool_array: Array = raw.get("pools", [])
			if pool_array.is_empty():
				load_errors.append("词缀池文件 '%s' 缺少 pools 数组" % entry)
				continue
			for pool_raw in pool_array:
				if not pool_raw is Dictionary:
					continue
				var pool_id := String(pool_raw.get("id", ""))
				if pool_id.is_empty():
					load_errors.append("词缀池文件 '%s' 中存在缺少 id 的池定义" % entry)
					continue
				if affix_pools.has(pool_id):
					load_errors.append("词缀池 ID 重复：'%s'" % pool_id)
					continue
				affix_pools[pool_id] = {
					"display_name": String(pool_raw.get("display_name", pool_id)),
					"affix_ids": _to_string_array(pool_raw.get("affix_ids", [])),
				}


## 传奇特效池：`data/legendary_effects/*.json`
## （结构 `{"effects": [{id, name, slot, rarity_min, trigger, effect, cooldown, description}]}`）。
## 范式（GDD 0.3 节 3.5）：触发条件 + 效果 + 冷却/上限 三要素必须齐全。
func _load_legendary_effect_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var effect_array: Array = raw.get("effects", [])
			if effect_array.is_empty():
				load_errors.append("传奇特效文件 '%s' 缺少 effects 数组" % entry)
				continue
			for effect_raw in effect_array:
				if not effect_raw is Dictionary:
					continue
				var eid := String(effect_raw.get("id", ""))
				if eid.is_empty():
					load_errors.append("传奇特效文件 '%s' 中存在缺少 id 的特效" % entry)
					continue
				if legendary_effects.has(eid):
					load_errors.append("传奇特效 ID 重复：'%s'" % eid)
					continue
				legendary_effects[eid] = effect_raw.duplicate(true)


func _load_monster_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var res := MonsterData.new()
			res.id = String(raw.get("id", ""))
			res.display_name = String(raw.get("display_name", ""))
			res.tier = _to_monster_tier(raw.get("tier", "normal"))
			res.level_min = int(raw.get("level_min", 1))
			res.level_max = int(raw.get("level_max", GameConstants.LEVEL_MAX))
			res.hp_scale = float(raw.get("hp_scale", 1.0))
			res.damage_scale = float(raw.get("damage_scale", 1.0))
			res.hp_growth = float(raw.get("hp_growth", GameConstants.MONSTER_HP_GROWTH))
			res.damage_growth = float(raw.get("damage_growth", GameConstants.MONSTER_DMG_GROWTH))
			res.move_speed = float(raw.get("move_speed", 60.0))
			res.attack_interval = float(raw.get("attack_interval", 1.5))
			res.attack_range = float(raw.get("attack_range", 40.0))
			res.base_armor = float(raw.get("base_armor", 0.0))
			res.loot_table_id = String(raw.get("loot_table_id", ""))
			res.sprite_path = String(raw.get("sprite_path", ""))
			res.sprite_directions = int(raw.get("sprite_directions", 4))
			res.ai_id = String(raw.get("ai_id", "melee_chaser"))
			res.is_flying = bool(raw.get("is_flying", false))
			res.base_xp = float(raw.get("base_xp", 10.0))
			res.gold_range = _to_vector2i(raw.get("gold_range", [5, 15]))
			res.element = String(raw.get("element", "physical"))
			_register(monsters, res.id, res, entry)
			_validate(res, entry)


## 职业模板：`data/classes/*.json`
## （结构 `[{id, display_name, title, playstyle, description, stats, skills, portrait, color}]`）。
## 原样存 Dictionary；跨表引用（skills → 技能 id、portrait → UISkin 逻辑名）在加载时校验。
func _load_class_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var cid := String(raw.get("id", ""))
			if cid.is_empty():
				load_errors.append("职业文件 '%s' 中存在缺少 id 的条目" % entry)
				continue
			if classes.has(cid):
				load_errors.append("职业 ID 重复：'%s'" % cid)
				continue
			var skill_ids: Array[String] = _to_string_array(raw.get("skills", []))
			for sid in skill_ids:
				if not skills.has(sid):
					load_errors.append("职业 '%s' 引用了不存在的技能 '%s'" % [cid, sid])
			var default_bar: Array[String] = _to_string_array(raw.get("default_skill_bar", []))
			if default_bar.is_empty():
				load_errors.append("职业 '%s' 缺少 default_skill_bar" % cid)
			for sid in default_bar:
				if not skill_ids.has(sid):
					load_errors.append("职业 '%s' 的 default_skill_bar 含池外技能 '%s'" % [cid, sid])
			classes[cid] = {
				"id": cid,
				"display_name": String(raw.get("display_name", cid)),
				"title": String(raw.get("title", "")),
				"playstyle": String(raw.get("playstyle", "")),
				"description": String(raw.get("description", "")),
				"stats": raw.get("stats", {}) if raw.get("stats") is Dictionary else {},
				"skills": skill_ids,
				"default_skill_bar": default_bar,
				"portrait": String(raw.get("portrait", "")),
				"color": String(raw.get("color", "F5D77A")),
			}


## 消耗品（步骤 8A · 药水）：`data/consumables/*.json`
## 结构 `[{id, display_name, kind(heal_hp/heal_mp), percent, cooldown, price, icon, desc}]`。
## 原样存 Dictionary；语义（回血/回蓝/冷却）由 PlayerController.use_consumable 消费。
func _load_consumable_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var cid := String(raw.get("id", ""))
			if cid.is_empty():
				load_errors.append("消耗品文件 '%s' 中存在缺少 id 的条目" % entry)
				continue
			if consumables.has(cid):
				load_errors.append("消耗品 ID 重复：'%s'" % cid)
				continue
			var kind := String(raw.get("kind", ""))
			if kind != "heal_hp" and kind != "heal_mp":
				load_errors.append("消耗品 '%s' 的 kind 非法（须 heal_hp/heal_mp）：'%s'" % [cid, kind])
			if float(raw.get("percent", 0.0)) <= 0.0 or float(raw.get("percent", 0.0)) > 1.0:
				load_errors.append("消耗品 '%s' 的 percent 须在 (0,1]" % cid)
			if float(raw.get("cooldown", 0.0)) <= 0.0:
				load_errors.append("消耗品 '%s' 的 cooldown 须 > 0" % cid)
			consumables[cid] = {
				"id": cid,
				"display_name": String(raw.get("display_name", cid)),
				"kind": kind,
				"percent": float(raw.get("percent", 0.0)),
				"cooldown": float(raw.get("cooldown", 3.0)),
				"price": float(raw.get("price", 0.0)),
				"icon": String(raw.get("icon", "")),
				"desc": String(raw.get("desc", "")),
			}


## BOSS 阶段机制：`data/monsters/bosses.json`
## （结构 `[{id, display_name, phase_count, thresholds, phase_skills,
##    summon_pool, summon_count, summon_interval, enrage, phase_damage_mult}]`）。
## 原样存 Dictionary，语义由 BossPhaseController 纯静态计算；跨表引用（召唤池 →
## 怪物 id）在 `_cross_validate` 校验。
func _load_boss_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var bid := String(raw.get("id", ""))
			if bid.is_empty():
				load_errors.append("BOSS 文件 '%s' 中存在缺少 id 的条目" % entry)
				continue
			if bosses.has(bid):
				load_errors.append("BOSS ID 重复：'%s'" % bid)
				continue
			var errs := BossPhaseController.validate(raw)
			if not errs.is_empty():
				load_errors.append("BOSS '%s' 数据非法：%s" % [bid, "；".join(errs)])
			bosses[bid] = raw.duplicate(true)


func _load_level_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var res := LevelData.new()
			res.id = String(raw.get("id", ""))
			res.display_name = String(raw.get("display_name", ""))
			res.chapter = int(raw.get("chapter", 1))
			res.level = int(raw.get("level", 1))
			res.recommended_player_level = int(raw.get("recommended_player_level", 1))
			res.objective_type = _to_objective_type(raw.get("objective_type", "clear_all"))
			res.objective_value = float(raw.get("objective_value", 0.0))
			res.optional_objectives = _to_dict_array(raw.get("optional_objectives", []))
			res.monster_entries = _to_dict_array(raw.get("monster_entries", []))
			res.total_monster_budget = int(raw.get("total_monster_budget", 0))
			res.elite_spawn_enabled = bool(raw.get("elite_spawn_enabled", true))
			res.elite_ratio = float(raw.get("elite_ratio", 0.05))
			res.reward_xp = float(raw.get("reward_xp", 2500.0))
			res.reward_gold = _to_vector2i(raw.get("reward_gold", [100, 200]))
			res.guaranteed_equipment_drops = int(raw.get("guaranteed_equipment_drops", 1))
			res.loot_table_id = String(raw.get("loot_table_id", ""))
			res.first_clear_rewards = _to_dict_array(raw.get("first_clear_rewards", []))
			res.scene_path = String(raw.get("scene_path", ""))
			res.tileset_path = String(raw.get("tileset_path", ""))
			res.ambient_color = _to_color(raw.get("ambient_color", ""))
			res.unlock_requires = _to_string_array(raw.get("unlock_requires", []))
			res.min_difficulty_tier = int(raw.get("min_difficulty_tier", 0))
			res.bgm_path = String(raw.get("bgm_path", ""))
			res.elite_count = int(raw.get("elite_count", 0))
			res.boss_id = String(raw.get("boss_id", ""))
			var raw_layout: Variant = raw.get("layout", {})
			res.layout = raw_layout if raw_layout is Dictionary else {}
			_register(levels, res.id, res, entry)
			_validate(res, entry)


func _load_loot_table_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var res := LootTable.new()
			res.id = String(raw.get("id", ""))
			res.tier = _to_monster_tier(raw.get("tier", "normal"))
			res.drop_chance = float(raw.get("drop_chance", 0.08))
			res.drop_count_range = _to_vector2i(raw.get("drop_count_range", [1, 1]))
			res.rarity_weights = _to_float_array(raw.get("rarity_weights", GameConstants.RARITY_DROP_BASE_PERCENT))
			res.equipment_share = float(raw.get("equipment_share", 0.55))
			res.gold_weight = float(raw.get("gold_weight", 30.0))
			res.material_weight = float(raw.get("material_weight", 12.0))
			res.consumable_weight = float(raw.get("consumable_weight", 3.0))
			res.pity_enabled = bool(raw.get("pity_enabled", false))
			res.pity_bonus_per_stack = float(raw.get("pity_bonus_per_stack", 0.20))
			res.pity_max_stacks = int(raw.get("pity_max_stacks", 3))
			res.allowed_template_ids = _to_string_array(raw.get("allowed_template_ids", []))
			res.excluded_template_ids = _to_string_array(raw.get("excluded_template_ids", []))
			_register(loot_tables, res.id, res, entry)
			_validate(res, entry)


func _load_set_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var res := SetData.new()
			res.id = String(raw.get("id", ""))
			res.display_name = String(raw.get("display_name", ""))
			res.style_tag = String(raw.get("style_tag", ""))
			res.emblem_path = String(raw.get("emblem_path", ""))
			res.piece_template_ids = _to_string_array(raw.get("piece_template_ids", []))
			res.tier_bonuses = _to_dict_array(raw.get("tier_bonuses", []))
			_register(sets, res.id, res, entry)
			_validate(res, entry)


func _load_skill_dir(dir_path: String) -> void:
	for entry in _scan_data_files(dir_path):
		for raw in _read_entries(entry):
			var res := SkillData.new()
			res.id = String(raw.get("id", ""))
			res.display_name = String(raw.get("display_name", ""))
			res.slot = int(raw.get("slot", 0))
			res.type = _to_skill_type(raw.get("type", "single"))
			res.multiplier = float(raw.get("multiplier", 1.0))
			var elem := String(raw.get("element", GameConstants.ELEMENT_PHYSICAL))
			res.element = elem if GameConstants.ELEMENTS.has(elem) else GameConstants.ELEMENT_PHYSICAL
			res.cooldown = float(raw.get("cooldown", 1.0))
			res.mana_cost = float(raw.get("mana_cost", 0.0))
			res.range = float(raw.get("range", 96.0))
			res.radius = float(raw.get("radius", 48.0))
			res.dash_distance = float(raw.get("dash_distance", 96.0))
			res.knockback = float(raw.get("knockback", 0.0))
			res.description = String(raw.get("description", ""))
			_register(skills, res.id, res, entry)
			_validate(res, entry)


## 跨表一致性校验（必须在全部表加载完成后执行）。
## 目前覆盖：
##   - EquipmentData.set_id ↔ SetData.piece_template_ids 双向一致
##   - EquipmentData.implicit_affix_id 引用的词缀存在
##   - EquipmentData.affix_pool_ids 引用的词缀池存在，且池内词缀全部存在（任务 3.1）
##   - MonsterData.loot_table_id / LevelData.loot_table_id 引用的掉落表存在
##   - LevelData.monster_entries 引用的怪物存在
func _cross_validate() -> void:
	# 1) 套装双向一致
	for set_key in sets:
		var set_data: SetData = sets[set_key]
		for template_id in set_data.piece_template_ids:
			if not equipment_templates.has(template_id):
				load_errors.append("套装 '%s' 引用了不存在的底材 '%s'" % [set_data.id, template_id])
				continue
			var tpl: EquipmentData = equipment_templates[template_id]
			if tpl.set_id != set_data.id:
				load_errors.append("底材 '%s' 的 set_id 为 '%s'，但被套装 '%s' 收录，二者不一致"
					% [template_id, tpl.set_id, set_data.id])

	for tpl_key in equipment_templates:
		var tpl: EquipmentData = equipment_templates[tpl_key]
		if tpl.set_id.is_empty():
			continue
		var set_data: SetData = sets.get(tpl.set_id, null)
		if set_data == null:
			load_errors.append("底材 '%s' 的 set_id '%s' 没有对应的套装定义" % [tpl.id, tpl.set_id])
		elif not set_data.contains_template(tpl.id):
			load_errors.append("底材 '%s' 声称属于套装 '%s'，但该套装未收录它"
				% [tpl.id, tpl.set_id])

	# 2) 词缀引用
	for tpl_key in equipment_templates:
		var tpl: EquipmentData = equipment_templates[tpl_key]
		if not tpl.implicit_affix_id.is_empty() and not affixes.has(tpl.implicit_affix_id):
			load_errors.append("底材 '%s' 的固有词缀 '%s' 不存在" % [tpl.id, tpl.implicit_affix_id])

	# 2.5) 词缀池引用（任务 3.1）
	for tpl_key in equipment_templates:
		var tpl: EquipmentData = equipment_templates[tpl_key]
		for pool_id in tpl.affix_pool_ids:
			if not affix_pools.has(pool_id):
				load_errors.append("底材 '%s' 引用了不存在的词缀池 '%s'" % [tpl.id, pool_id])
				continue
			var pool: Dictionary = affix_pools[pool_id]
			var pool_affix_ids: Array = pool.get("affix_ids", [])
			if pool_affix_ids.is_empty():
				load_errors.append("词缀池 '%s' 为空（被底材 '%s' 引用）" % [pool_id, tpl.id])
			for affix_id in pool_affix_ids:
				if not affixes.has(String(affix_id)):
					load_errors.append("词缀池 '%s' 引用了不存在的词缀 '%s'" % [pool_id, affix_id])

	# 2.7) 传奇特效引用（任务 3.5）：底材绑定特效必须存在，且部位与稀有度合法
	for tpl_key in equipment_templates:
		var tpl: EquipmentData = equipment_templates[tpl_key]
		if tpl.legendary_effect_id.is_empty():
			continue
		if not legendary_effects.has(tpl.legendary_effect_id):
			load_errors.append("底材 '%s' 绑定的传奇特效 '%s' 不存在"
				% [tpl.id, tpl.legendary_effect_id])
			continue
		var fx: Dictionary = legendary_effects[tpl.legendary_effect_id]
		if _to_slot(String(fx.get("slot", ""))) != tpl.slot:
			load_errors.append("底材 '%s'（槽 %s）绑定的特效 '%s' 槽位不匹配（%s）"
				% [tpl.id, GameConstants.EQUIP_SLOT_KEYS[tpl.slot], tpl.legendary_effect_id, fx.get("slot", "")])

	# 2.8) 传奇特效定义校验（范式三要素 + 类型枚举 + 参数齐全）
	_validate_legendary_effects()

	# 3) 掉落表引用
	for monster_key in monsters:
		var monster: MonsterData = monsters[monster_key]
		if not monster.loot_table_id.is_empty() and not loot_tables.has(monster.loot_table_id):
			load_errors.append("怪物 '%s' 的掉落表 '%s' 不存在" % [monster.id, monster.loot_table_id])

	# 3.1) BOSS 阶段机制引用（任务 6.3）：召唤池怪物必须存在，且 BOSS 自身在怪物表
	for boss_key in bosses:
		var boss: Dictionary = bosses[boss_key]
		var bid := String(boss.get("id", ""))
		if not monsters.has(bid):
			load_errors.append("BOSS '%s' 不在怪物表（章节关无法刷出）" % bid)
		for summon_id in boss.get("summon_pool", []):
			if not monsters.has(String(summon_id)):
				load_errors.append("BOSS '%s' 召唤池引用了不存在的怪物 '%s'" % [bid, summon_id])

	for level_key in levels:
		var level: LevelData = levels[level_key]
		if not level.loot_table_id.is_empty() and not loot_tables.has(level.loot_table_id):
			load_errors.append("关卡 '%s' 的掉落表 '%s' 不存在" % [level.id, level.loot_table_id])

		# 4) 关卡引用的怪物
		for i in range(level.monster_entries.size()):
			var monster_id := String(level.monster_entries[i].get("monster_id", ""))
			if monster_id.is_empty():
				continue
			if not monsters.has(monster_id):
				load_errors.append("关卡 '%s' 的第 %d 条怪物条目引用了不存在的怪物 '%s'"
					% [level.id, i, monster_id])


## 传奇特效定义校验（任务 3.5）：GDD 范式 = 触发条件 + 效果 + 冷却/上限 三要素齐全。
## 类型枚举与 trigger/effect 参数做白名单校验（数据写错在加载期就暴露，而非运行时静默失效）。
const LEGENDARY_TRIGGER_TYPES: Array[String] = [
	"on_hit", "on_crit", "on_kill", "on_elite_kill", "on_damage_taken", "on_low_hp",
	"on_pickup_gold", "on_skill_cast", "on_resource_spend", "on_block",
]
const LEGENDARY_EFFECT_TYPES: Array[String] = [
	"stack", "deal_damage", "heal", "gain_resource", "buff_stat", "extra_loot",
	"revive_protect", "ms_boost", "damage_reduction", "reflect", "resource_refund", "summon",
]

func _validate_legendary_effects() -> void:
	for eid in legendary_effects:
		var fx: Dictionary = legendary_effects[eid]
		# 三要素：trigger / effect / description
		if not fx.has("trigger") or not fx.get("trigger") is Dictionary:
			load_errors.append("传奇特效 '%s' 缺少 trigger（触发条件）" % eid)
			continue
		if not fx.has("effect") or not fx.get("effect") is Dictionary:
			load_errors.append("传奇特效 '%s' 缺少 effect（效果）" % eid)
			continue
		if String(fx.get("description", "")).is_empty():
			load_errors.append("传奇特效 '%s' 缺少 description（三要素之上限/说明）" % eid)
		# 冷却 ≥ 0
		if float(fx.get("cooldown", 0.0)) < 0.0:
			load_errors.append("传奇特效 '%s' 的 cooldown 为负" % eid)
		# 部位合法
		var slot_key := str(fx.get("slot", ""))
		if slot_key.is_empty() or not GameConstants.EQUIP_SLOT_KEYS.has(slot_key):
			load_errors.append("传奇特效 '%s' 的部位 '%s' 非法" % [eid, slot_key])
		# 稀有度下限合法
		var rmin: int = GameConstants.rarity_from_key(str(fx.get("rarity_min", "legendary")))
		if rmin < 0:
			load_errors.append("传奇特效 '%s' 的 rarity_min 非法" % eid)
		# trigger 类型白名单
		var trigger: Dictionary = fx["trigger"]
		var ttype := String(trigger.get("type", ""))
		if not LEGENDARY_TRIGGER_TYPES.has(ttype):
			load_errors.append("传奇特效 '%s' 的 trigger 类型 '%s' 非法" % [eid, ttype])
		else:
			if ttype == "on_low_hp" and not trigger.has("hp_below_pct"):
				load_errors.append("传奇特效 '%s' 的 on_low_hp 缺少 hp_below_pct" % eid)
		# effect 类型白名单 + 参数齐全
		var effect: Dictionary = fx["effect"]
		var etype := String(effect.get("type", ""))
		if not LEGENDARY_EFFECT_TYPES.has(etype):
			load_errors.append("传奇特效 '%s' 的 effect 类型 '%s' 非法" % [eid, etype])
		else:
			match etype:
				"stack":
					if not effect.has("on_full"):
						load_errors.append("传奇特效 '%s' 的 stack 效果缺少 on_full" % eid)
				"deal_damage":
					if not effect.has("damage_pct"):
						load_errors.append("传奇特效 '%s' 的 deal_damage 缺少 damage_pct" % eid)
				"heal":
					if not effect.has("heal_pct"):
						load_errors.append("传奇特效 '%s' 的 heal 缺少 heal_pct" % eid)
				"buff_stat":
					if not effect.has("stat") or not effect.has("value"):
						load_errors.append("传奇特效 '%s' 的 buff_stat 缺少 stat/value" % eid)
				"extra_loot":
					if not effect.has("limit_per_run"):
						load_errors.append("传奇特效 '%s' 的 extra_loot 缺少 limit_per_run" % eid)
				"resource_refund":
					if not effect.has("pct"):
						load_errors.append("传奇特效 '%s' 的 resource_refund 缺少 pct" % eid)
				"reflect":
					if not effect.has("pct"):
						load_errors.append("传奇特效 '%s' 的 reflect 缺少 pct" % eid)
				"ms_boost":
					if not effect.has("value") or not effect.has("duration"):
						load_errors.append("传奇特效 '%s' 的 ms_boost 缺少 value/duration" % eid)
				"revive_protect":
					if not effect.has("heal_pct"):
						load_errors.append("传奇特效 '%s' 的 revive_protect 缺少 heal_pct" % eid)
				"summon":
					if not effect.has("creature"):
						load_errors.append("传奇特效 '%s' 的 summon 缺少 creature" % eid)


# =============================================================================
# 查询接口
# =============================================================================

func get_equipment_template(id: String) -> EquipmentData:
	return equipment_templates.get(id, null)


func get_affix(id: String) -> AffixData:
	return affixes.get(id, null)


## 传奇特效定义（任务 3.5）。返回 Dictionary（id/name/slot/rarity_min/trigger/effect/cooldown/description）。
func get_legendary_effect(id: String) -> Dictionary:
	return legendary_effects.get(id, {})


func get_monster(id: String) -> MonsterData:
	return monsters.get(id, null)


func get_boss(id: String) -> Dictionary:
	return bosses.get(id, {})


func get_level(id: String) -> LevelData:
	return levels.get(id, null)


func get_loot_table(id: String) -> LootTable:
	return loot_tables.get(id, null)


func get_set(id: String) -> SetData:
	return sets.get(id, null)


## 取职业模板（不存在返回 null）
func get_class_template(id: String) -> Dictionary:
	return classes.get(id, {})


## 职业显示名（不存在回退为 id 或 "战士"）
func class_display_name(id: String) -> String:
	if classes.has(id):
		return String(classes[id].get("display_name", id))
	return id


## 职业立绘逻辑名（UISkin.texture 用）
func class_portrait_key(id: String) -> String:
	if classes.has(id):
		return String(classes[id].get("portrait", ""))
	return ""


## 取职业的默认出战技能栏（3 个，按栏位顺序）
func class_default_skill_bar(id: String) -> Array[String]:
	var out: Array[String] = []
	if classes.has(id):
		for sid in classes[id].get("default_skill_bar", []):
			out.append(String(sid))
	return out


## 取职业的技能 ID 列表（按模板顺序）
func class_skill_ids(id: String) -> Array[String]:
	if classes.has(id):
		return (classes[id].get("skills", []) as Array[String]).duplicate()
	return []


func get_skill(id: String) -> SkillData:
	return skills.get(id, null)


## 取全部技能 ID（稳定排序，与技能栏 1/2/3 顺序一致）
func get_all_skill_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in skills:
		ids.append(String(key))
	ids.sort()
	return ids


## 取某底材所属的套装定义（不属于任何套装则返回 null）
func get_set_for_template(template_id: String) -> SetData:
	var tpl := get_equipment_template(template_id)
	if tpl == null or tpl.set_id.is_empty():
		return null
	return get_set(tpl.set_id)


## 取全部套装 ID（稳定排序）
func get_all_set_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in sets:
		ids.append(String(key))
	ids.sort()
	return ids


## 取全部底材 ID（稳定排序，保证不同机器上顺序一致）
func get_all_equipment_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in equipment_templates:
		ids.append(String(key))
	ids.sort()
	return ids


## 取某部位的底材列表
func get_equipment_by_slot(slot: int) -> Array[EquipmentData]:
	var out: Array[EquipmentData] = []
	for key in equipment_templates:
		var tpl: EquipmentData = equipment_templates[key]
		if tpl.slot == slot:
			out.append(tpl)
	return out


## 取某部位可用的词缀（已过滤 allowed_slots）
func get_affixes_for_slot(slot: int) -> Array[AffixData]:
	var out: Array[AffixData] = []
	for key in affixes:
		var affix: AffixData = affixes[key]
		if affix.fits_slot(slot):
			out.append(affix)
	return out


## 取词缀池定义（{display_name, affix_ids}；不存在返回 null）
func get_affix_pool(pool_id: String) -> Dictionary:
	return affix_pools.get(pool_id, {})


## 取某池内的词缀（按池列表顺序；slot >= 0 时再过滤部位）。
## 池内词缀不存在（理论已被跨表校验拦住）会跳过。
func get_affixes_in_pool(pool_id: String, slot: int = -1) -> Array[AffixData]:
	var out: Array[AffixData] = []
	var pool: Dictionary = affix_pools.get(pool_id, {})
	var affix_ids: Array = pool.get("affix_ids", [])
	for affix_id in affix_ids:
		var affix := affixes.get(String(affix_id), null) as AffixData
		if affix == null:
			continue
		if slot >= 0 and not affix.fits_slot(slot):
			continue
		out.append(affix)
	return out


## 全部词缀池 ID（稳定排序）
func get_all_affix_pool_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in affix_pools:
		ids.append(String(key))
	ids.sort()
	return ids


## 取全部关卡，按 level 升序
func get_levels_sorted() -> Array[LevelData]:
	var out: Array[LevelData] = []
	for key in levels:
		out.append(levels[key])
	out.sort_custom(func(a: LevelData, b: LevelData) -> bool: return a.level < b.level)
	return out


## 取某章节的关卡
func get_levels_in_chapter(chapter: int) -> Array[LevelData]:
	var out: Array[LevelData] = []
	for lv in get_levels_sorted():
		if lv.chapter == chapter:
			out.append(lv)
	return out


## 取某档位的默认掉落表（未找到则返回 null）
func get_default_loot_table(tier: int) -> LootTable:
	var table_id: String = String(LOOT_TABLE_BY_TIER.get(tier, ""))
	if table_id.is_empty():
		return null
	return get_loot_table(table_id)


# =============================================================================
# 引用回填（读档 / 掉落生成后调用）
# =============================================================================

## 为一件装备实例注入底材模板与词缀模板引用。
## 返回是否全部解析成功（缺模板不算致命，但会记录警告）。
func resolve_instance(item: EquipmentInstance) -> bool:
	var ok := true

	item.template = get_equipment_template(item.template_id)
	if item.template == null:
		push_warning("[ConfigLoader] 装备实例 %s 的底材 '%s' 不存在" % [item.instance_id, item.template_id])
		ok = false

	for roll in item.affixes:
		roll.template = get_affix(roll.affix_id)
		if roll.template == null:
			push_warning("[ConfigLoader] 装备 %s 的词缀 '%s' 不存在" % [item.instance_id, roll.affix_id])
			ok = false

	return ok


## 批量回填
func resolve_instances(items: Array) -> void:
	for item in items:
		if item is EquipmentInstance:
			resolve_instance(item)


# =============================================================================
# 文件读取
# =============================================================================

## 递归扫描目录下的 JSON 数据文件，返回相对路径列表（稳定排序）
func _scan_data_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	_scan_recursive(dir_path, out)
	out.sort()
	return out


func _scan_recursive(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		# 目录不存在不算错误：允许阶段性只提供部分数据表
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		var full := dir_path.path_join(file_name)
		if dir.current_is_dir():
			_scan_recursive(full, out)
		elif file_name.get_extension().to_lower() == "json":
			out.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()


## 读取一个数据文件，返回**对象数组**（单对象也包成单元素数组）。
## 非对象的条目会被记录为错误并跳过，保证调用方拿到的都是 Dictionary。
func _read_entries(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var content: Variant = _load_data_file(path)
	if content == null:
		return out

	var raw_entries: Array = []
	if content is Array:
		raw_entries = content
	elif content is Dictionary:
		raw_entries = [content]
	else:
		load_errors.append("文件 '%s' 的顶层结构应为对象或对象数组，实际为 %s"
			% [path, type_string(typeof(content))])
		return out

	for i in range(raw_entries.size()):
		var item: Variant = raw_entries[i]
		if item is Dictionary:
			out.append(item)
		else:
			load_errors.append("文件 '%s' 的第 %d 条不是对象（%s），已跳过"
				% [path, i, type_string(typeof(item))])
	return out


## 读取文件内容为 Variant（Dictionary / Array）
func _load_data_file(path: String) -> Variant:
	# 优先走 Godot 资源系统：Godot 4 的 JSON 导入器会把 .json 变成 JSON 资源，
	# 这样在**导出版本**里也能正确加载（res:// 下的原始文本文件默认不进包）。
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is JSON:
			return (res as JSON).data
		if res != null:
			return res

	# 回退：直接读文本（编辑器内 / 未被导入器接管的情况）
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err_msg := "无法打开数据文件 '%s'（错误码 %d）" % [path, FileAccess.get_open_error()]
		load_errors.append(err_msg)
		EventBus.config_load_failed.emit(path, err_msg)
		return null

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		var msg := "JSON 解析失败 '%s' 第 %d 行：%s" % [path, json.get_error_line(), json.get_error_message()]
		load_errors.append(msg)
		EventBus.config_load_failed.emit(path, msg)
		return null

	return json.data


# =============================================================================
# 注册与校验
# =============================================================================

func _register(table: Dictionary, id: String, res: Resource, source: String) -> void:
	if id.is_empty():
		load_errors.append("文件 '%s' 中有一条记录缺少 id，已跳过" % source)
		return
	if table.has(id):
		load_errors.append("ID 重复：'%s'（来源 '%s'），后者被忽略" % [id, source])
		return
	table[id] = res


func _validate(res: Resource, source: String) -> void:
	if not res.has_method("validate"):
		return
	# 用 call() 而非 res.validate()：Resource 基类没有该方法，直接调用会触发
	# unsafe_method_access 警告。这里已用 has_method 做了前置保护。
	var errors: Array = res.call("validate")
	for e in errors:
		load_errors.append("[%s] %s" % [source, str(e)])


# =============================================================================
# 字段转换辅助（JSON 是弱类型，统一在此收口）
# =============================================================================

func _to_slot(value: Variant) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, GameConstants.EQUIP_SLOT_COUNT - 1)
	var idx := GameConstants.equip_slot_from_key(String(value))
	if idx < 0:
		load_errors.append("未知部位键名 '%s'，回退为 main_hand" % str(value))
		return GameConstants.EquipSlot.MAIN_HAND
	return idx


func _to_slot_array(value: Variant) -> Array[int]:
	var out: Array[int] = []
	if value is Array:
		for v in value:
			out.append(_to_slot(v))
	return out


func _to_weapon_archetype(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var key := String(value)
	if key.is_empty():
		return -1
	return GameConstants.weapon_archetype_from_key(key)


func _to_affix_category(value: Variant) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, GameConstants.AFFIX_CATEGORY_COUNT - 1)
	var idx := GameConstants.AFFIX_CATEGORY_KEYS.find(String(value).to_lower())
	if idx < 0:
		load_errors.append("未知词缀类别 '%s'，回退为 attack" % str(value))
		return GameConstants.AffixCategory.ATTACK
	return idx


func _to_affix_position(value: Variant) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, 1)
	var key := String(value).to_lower()
	if key == "suffix" or key == "后缀":
		return GameConstants.AffixPosition.SUFFIX
	return GameConstants.AffixPosition.PREFIX


func _to_monster_tier(value: Variant) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, MonsterData.Tier.BOSS)
	var idx := MonsterData.TIER_KEYS.find(String(value).to_lower())
	if idx < 0:
		load_errors.append("未知怪物档位 '%s'，回退为 normal" % str(value))
		return MonsterData.Tier.NORMAL
	return idx


func _to_skill_type(value: Variant) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, SkillData.SkillType.DASH)
	var idx := SkillData.TYPE_KEYS.find(String(value).to_lower())
	if idx < 0:
		load_errors.append("未知技能形态 '%s'，回退为 single" % str(value))
		return SkillData.SkillType.SINGLE
	return idx


func _to_objective_type(value: Variant) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, LevelData.OBJECTIVE_KEYS.size() - 1)
	var idx := LevelData.OBJECTIVE_KEYS.find(String(value).to_lower())
	if idx < 0:
		load_errors.append("未知关卡目标类型 '%s'，回退为 clear_all" % str(value))
		return LevelData.ObjectiveType.CLEAR_ALL
	return idx


func _to_vector2i(value: Variant) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Vector2i:
		return value
	return Vector2i.ZERO


func _to_color(value: Variant) -> Color:
	var s := String(value)
	if s.is_empty():
		return Color(0, 0, 0, 0)
	return Color(s)


func _to_string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(String(v))
	return out


func _to_float_array(value: Variant) -> Array[float]:
	var out: Array[float] = []
	if value is Array:
		for v in value:
			out.append(float(v))
	return out


func _to_float_dict(value: Variant) -> Dictionary:
	var out := {}
	if value is Dictionary:
		for k in value:
			out[String(k)] = float(value[k])
	return out


func _to_dict_array(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for v in value:
			if v is Dictionary:
				out.append(v)
			else:
				load_errors.append("期望对象数组，遇到 %s，已跳过" % type_string(typeof(v)))
	return out
