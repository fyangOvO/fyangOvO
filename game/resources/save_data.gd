## 存档数据模型（一个存档槽的完整状态）
##
## 与 `SaveManager` 的分工：
##   - 本类：**数据结构 + 序列化**（`to_dict` / `from_dict` / `migrate`）
##   - `SaveManager`：**文件 IO + 校验 + 备份轮转 + 多槽管理**
##
## 版本策略：
##   `SAVE_VERSION`（GameConstants.SAVE_VERSION）是**磁盘格式版本**，与游戏版本无关。
##   每次改动字段结构都必须 +1，并在 `migrate()` 中补一条升级分支。
##   读取低版本存档 → 自动升级；读取高版本存档 → 拒绝（防止新版存档被旧版写坏）。
class_name SaveData
extends Resource

# =============================================================================
# 元信息
# =============================================================================

## 磁盘格式版本
@export var save_version: int = GameConstants.SAVE_VERSION

## 槽位号（0 起）
@export var slot: int = 0

## 创建时间 / 最后保存时间（Unix 时间戳）
@export var created_at: int = 0
@export var updated_at: int = 0

## 累计游戏时长（秒）
@export var play_time_seconds: float = 0.0

## 存档显示名（供选档界面展示，如 "剑士 · Lv.23"）
@export var display_name: String = ""

## 职业 ID（2026-09-22 步骤 2：角色选择；旧档迁移默认 "warrior"）
@export var class_id: String = GameConstants.CLASS_DEFAULT

## 出战技能栏（3 个技能 id，按栏位 1/2/3 顺序；2026-09-22 步骤 3：职业专属技能池 + 重排）
@export var skill_bar: Array[String] = []

# =============================================================================
# 角色与成长（局外，永久）
# =============================================================================

## 账号等级（1–60，GDD 0.5 节 5.1）
@export var account_level: int = 1

## 当前等级内已累积的经验
@export var account_xp: float = 0.0

## 累计总经验（成就 / 统计用）
@export var total_xp: float = 0.0

## 未使用的天赋点
@export var talent_points: int = 0

## 已点亮的 talent node ID 列表
@export var unlocked_talent_nodes: Array[String] = []

# =============================================================================
# 资源
# =============================================================================

## 金币
@export var gold: int = 0

## 材料。键为材料 ID（"magic_stone" / "mithril_dust" / "legend_essence"），值为数量
@export var materials: Dictionary = {}

# =============================================================================
# 装备
# =============================================================================

## 背包中的装备（不含已装备的）
@export var inventory: Array[EquipmentInstance] = []

## 装备槽。长度固定为 GameConstants.EQUIP_SLOT_COUNT，下标 = 部位，元素可为 null
@export var equipped: Array[EquipmentInstance] = []

## 仓库（个人储物箱，多页）
@export var stash: Array[EquipmentInstance] = []

# =============================================================================
# 进度
# =============================================================================

## 已解锁的关卡 ID
@export var unlocked_levels: Array[String] = []

## 已通关的关卡 ID
@export var cleared_levels: Array[String] = []

## 各关卡的最快通关时间（秒），键为关卡 ID
@export var level_clear_times: Dictionary = {}

## 已解锁的最高难度层级（0 = 梦魇 I）
@export var unlocked_difficulty_tier: int = 0

## 当前所在关卡 ID（空 = 在据点）
@export var current_level_id: String = ""

## 当前选择的难度层级
@export var current_difficulty_tier: int = 0

## 各章节声望等级（键为章节号字符串，值 0–10，GDD 0.5 节 5.5）
@export var chapter_reputation: Dictionary = {}

## 已解锁的成就 ID
@export var unlocked_achievements: Array[String] = []

## 仓库页解锁数（1–4，GDD 0.5 节 5.4）
@export var stash_pages: int = 1

# =============================================================================
# 统计与设置
# =============================================================================

## 统计数据（击杀数、死亡数、掉落数等，纯展示用）
@export var statistics: Dictionary = {}

## 玩家设置（音量、按键、画质等）
@export var settings: Dictionary = {}


func _init() -> void:
	if equipped.is_empty():
		equipped.resize(GameConstants.EQUIP_SLOT_COUNT)


# =============================================================================
# 工厂
# =============================================================================

## 创建一个全新的存档（开局状态）
static func create_new(p_slot: int, p_class_id: String = GameConstants.CLASS_DEFAULT) -> SaveData:
	var data := SaveData.new()
	data.slot = p_slot
	data.save_version = GameConstants.SAVE_VERSION
	var now := int(Time.get_unix_time_from_system())
	data.created_at = now
	data.updated_at = now
	data.class_id = p_class_id
	data.skill_bar = ConfigLoader.class_default_skill_bar(p_class_id)
	data.display_name = "%s · Lv.1" % ConfigLoader.class_display_name(p_class_id)
	data.account_level = 1
	data.account_xp = 0.0
	data.talent_points = 0
	data.gold = 0
	data.materials = {
		"magic_stone": 0,
		"mithril_dust": 0,
		"legend_essence": 0,
	}
	data.unlocked_levels = ["ch1_l01"]
	data.cleared_levels = []
	data.unlocked_difficulty_tier = GameConstants.DifficultyTier.NM1
	data.current_difficulty_tier = GameConstants.DifficultyTier.NM1
	data.stash_pages = 1
	data.settings = {
		"master_volume": 1.0,
		"bgm_volume": 0.8,
		"sfx_volume": 1.0,
		"show_damage_numbers": true,
		"screen_shake": true,
	}
	data.statistics = {
		"monsters_killed": 0,
		"elites_killed": 0,
		"bosses_killed": 0,
		"deaths": 0,
		"items_picked": 0,
		"items_dismantled": 0,
		"levels_cleared": 0,
	}
	return data


# =============================================================================
# 便捷访问
# =============================================================================

## 取某个装备槽上的装备（越界或空槽返回 null）
func get_equipped(slot: int) -> EquipmentInstance:
	if slot < 0 or slot >= equipped.size():
		return null
	return equipped[slot]


## 把装备放到指定槽，返回被替换下来的旧装备（可能为 null）
func set_equipped(slot: int, item: EquipmentInstance) -> EquipmentInstance:
	if slot < 0 or slot >= GameConstants.EQUIP_SLOT_COUNT:
		return null
	if equipped.size() < GameConstants.EQUIP_SLOT_COUNT:
		equipped.resize(GameConstants.EQUIP_SLOT_COUNT)
	var old: EquipmentInstance = equipped[slot]
	equipped[slot] = item
	return old


## 取某材料数量
func get_material(material_id: String) -> int:
	return int(materials.get(material_id, 0))


## 增减材料（数量不足时不扣，返回是否成功）
func add_material(material_id: String, amount: int) -> bool:
	var current := get_material(material_id)
	var next := current + amount
	if next < 0:
		return false
	materials[material_id] = next
	return true


## 增减金币（不足时不扣，返回是否成功）
func add_gold(amount: int) -> bool:
	if gold + amount < 0:
		return false
	gold += amount
	return true


## 背包中的装备总数（含已装备与仓库，用于存档摘要）
func total_item_count() -> int:
	var n := inventory.size() + stash.size()
	for item in equipped:
		if item != null:
			n += 1
	return n


# =============================================================================
# 序列化
# =============================================================================

func to_dict() -> Dictionary:
	var inv: Array = []
	for item in inventory:
		inv.append(item.to_dict())

	# 装备槽按固定长度落盘，空槽写 null，保证槽位语义不漂移
	var eq: Array = []
	eq.resize(GameConstants.EQUIP_SLOT_COUNT)
	for i in range(GameConstants.EQUIP_SLOT_COUNT):
		var item := get_equipped(i)
		eq[i] = item.to_dict() if item != null else null

	var st: Array = []
	for item in stash:
		st.append(item.to_dict())

	return {
		"save_version": save_version,
		"slot": slot,
		"created_at": created_at,
		"updated_at": updated_at,
		"play_time_seconds": play_time_seconds,
		"display_name": display_name,
		"class_id": class_id,
		"skill_bar": skill_bar.duplicate(),
		"account_level": account_level,
		"account_xp": account_xp,
		"total_xp": total_xp,
		"talent_points": talent_points,
		"unlocked_talent_nodes": unlocked_talent_nodes,
		"gold": gold,
		"materials": materials,
		"inventory": inv,
		"equipped": eq,
		"stash": st,
		"unlocked_levels": unlocked_levels,
		"cleared_levels": cleared_levels,
		"level_clear_times": level_clear_times,
		"unlocked_difficulty_tier": unlocked_difficulty_tier,
		"current_level_id": current_level_id,
		"current_difficulty_tier": current_difficulty_tier,
		"chapter_reputation": chapter_reputation,
		"unlocked_achievements": unlocked_achievements,
		"stash_pages": stash_pages,
		"statistics": statistics,
		"settings": settings,
	}


## 反序列化。**不注入 Resource 引用** —— 调用方需再执行 `ConfigLoader.resolve_instances()`。
static func from_dict(data: Dictionary) -> SaveData:
	var out := SaveData.new()
	out.save_version = int(data.get("save_version", 1))
	out.slot = int(data.get("slot", 0))
	out.created_at = int(data.get("created_at", 0))
	out.updated_at = int(data.get("updated_at", 0))
	out.play_time_seconds = float(data.get("play_time_seconds", 0.0))
	out.display_name = String(data.get("display_name", ""))
	out.class_id = String(data.get("class_id", GameConstants.CLASS_DEFAULT))
	for sid in data.get("skill_bar", []):
		out.skill_bar.append(String(sid))
	out.account_level = clampi(int(data.get("account_level", 1)),
		GameConstants.ACCOUNT_LEVEL_MIN, GameConstants.ACCOUNT_LEVEL_MAX)
	out.account_xp = float(data.get("account_xp", 0.0))
	out.total_xp = float(data.get("total_xp", 0.0))
	out.talent_points = maxi(int(data.get("talent_points", 0)), 0)
	out.unlocked_talent_nodes = _to_string_array(data.get("unlocked_talent_nodes", []))
	out.gold = maxi(int(data.get("gold", 0)), 0)
	out.materials = data.get("materials", {}) if data.get("materials") is Dictionary else {}
	out.inventory = _to_item_array(data.get("inventory", []))
	out.stash = _to_item_array(data.get("stash", []))
	out.unlocked_levels = _to_string_array(data.get("unlocked_levels", []))
	out.cleared_levels = _to_string_array(data.get("cleared_levels", []))
	out.level_clear_times = data.get("level_clear_times", {}) if data.get("level_clear_times") is Dictionary else {}
	out.unlocked_difficulty_tier = clampi(int(data.get("unlocked_difficulty_tier", 0)),
		0, GameConstants.DIFFICULTY_TIER_COUNT - 1)
	out.current_level_id = String(data.get("current_level_id", ""))
	out.current_difficulty_tier = clampi(int(data.get("current_difficulty_tier", 0)),
		0, GameConstants.DIFFICULTY_TIER_COUNT - 1)
	out.chapter_reputation = data.get("chapter_reputation", {}) if data.get("chapter_reputation") is Dictionary else {}
	out.unlocked_achievements = _to_string_array(data.get("unlocked_achievements", []))
	out.stash_pages = clampi(int(data.get("stash_pages", 1)), 1, 4)
	out.statistics = data.get("statistics", {}) if data.get("statistics") is Dictionary else {}
	out.settings = data.get("settings", {}) if data.get("settings") is Dictionary else {}

	# 装备槽：先按固定长度初始化，再逐槽填充
	out.equipped.resize(GameConstants.EQUIP_SLOT_COUNT)
	var eq_raw: Variant = data.get("equipped", [])
	if eq_raw is Array:
		var eq_arr: Array = eq_raw
		for i in range(GameConstants.EQUIP_SLOT_COUNT):
			if i < eq_arr.size() and eq_arr[i] is Dictionary:
				out.equipped[i] = EquipmentInstance.from_dict(eq_arr[i])

	return out


# =============================================================================
# 版本迁移
# =============================================================================

## 把旧版本存档升级到当前版本。
## 返回 true = 迁移成功（或无需迁移）；false = 无法迁移（调用方应视为读取失败）。
##
## 新增格式变更时，在 `match` 中追加分支，例如：
##   if out.save_version == 1: ... 补齐 v2 新增字段 ...; out.save_version = 2
func migrate() -> bool:
	if save_version > GameConstants.SAVE_VERSION:
		# 存档来自更新版本的游戏，拒绝读取（避免降级写坏数据）
		push_warning("[SaveData] 存档版本 %d 高于当前支持版本 %d，拒绝加载"
			% [save_version, GameConstants.SAVE_VERSION])
		return false

	# v2（2026-09-22）：新增 `class_id`，旧档补默认职业 warrior。
	while save_version < GameConstants.SAVE_VERSION:
		match save_version:
			1:
				class_id = GameConstants.CLASS_DEFAULT
				save_version = 2
			2:
				skill_bar = ConfigLoader.class_default_skill_bar(class_id)
				save_version = 3
			_:
				save_version = GameConstants.SAVE_VERSION
	save_version = GameConstants.SAVE_VERSION
	return true


# =============================================================================
# 私有辅助
# =============================================================================

static func _to_string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(String(v))
	return out


static func _to_item_array(value: Variant) -> Array[EquipmentInstance]:
	var out: Array[EquipmentInstance] = []
	if value is Array:
		for v in value:
			if v is Dictionary:
				out.append(EquipmentInstance.from_dict(v))
	return out
