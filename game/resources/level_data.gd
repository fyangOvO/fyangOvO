## 关卡定义（数据驱动 · 自定义 Resource）
##
## 字段覆盖任务清单 1.7：关卡等级、目标类型、怪物配置、奖励。
##
## 数据来源：`game/data/levels/*.json`
##
## ⚠️ 跨阶段依赖（GDD 0.7 节风险 #6）：
##   武器层的**手部锚点与层结构**必须在阶段 2 任务 2.1 就预留，
##   关卡场景的 Player 实例化路径应指向带好锚点的角色场景（见 `player_scene_path`）。
class_name LevelData
extends Resource

## 关卡目标类型
enum ObjectiveType {
	CLEAR_ALL = 0,   ## 清空全部怪物
	KILL_ELITE = 1,  ## 击杀指定数量精英
	KILL_BOSS = 2,   ## 击杀 BOSS
	SURVIVE = 3,     ## 存活指定时长
	COLLECT = 4,     ## 收集指定数量的目标物
	REACH_EXIT = 5,  ## 抵达出口
}

const OBJECTIVE_NAMES: Array[String] = ["清怪", "击杀精英", "击杀 BOSS", "存活", "收集", "抵达出口"]
const OBJECTIVE_KEYS: Array[String] = ["clear_all", "kill_elite", "kill_boss", "survive", "collect", "reach_exit"]

## 唯一标识（如 "ch1_l03"）
@export var id: String = ""

## UI 显示名
@export var display_name: String = ""

## 所属章节（1–3，对应美术规范 1.3 节三章主题色）
@export var chapter: int = 1

## 关卡等级 L1–L20（= 该关掉落装备的 iLvl，GDD 0.3 节 3.6）
@export var level: int = GameConstants.LEVEL_MIN

## 推荐玩家等级（用于章节软门槛提示，GDD 0.5 节 5.4）
@export var recommended_player_level: int = 1

# -----------------------------------------------------------------------------
# 目标
# -----------------------------------------------------------------------------

## 目标类型 —— ObjectiveType
@export var objective_type: int = ObjectiveType.CLEAR_ALL

## 目标参数。语义随 objective_type 变化：
##   CLEAR_ALL / KILL_BOSS / REACH_EXIT → 忽略
##   KILL_ELITE / COLLECT → 需要的数量
##   SURVIVE → 需要存活的秒数
@export var objective_value: float = 0.0

## 可选目标（达成给额外奖励，不阻塞通关）
@export var optional_objectives: Array[Dictionary] = []

# -----------------------------------------------------------------------------
# 怪物配置
# -----------------------------------------------------------------------------
#
# 每个条目的结构（JSON 中为对象数组）：
#   {
#     "monster_id": "spider_cave",   // 必填，对应 MonsterData.id
#     "count_min": 20,               // 必填，最少生成数
#     "count_max": 35,               // 必填，最多生成数
#     "weight": 100.0,               // 可选，同池相对权重，默认 100
#     "spawn_group": "ambient",      // 可选，"ambient"(散布) / "pack"(成堆) / "guard"(守卫)
#     "is_boss": false               // 可选，是否为该关 BOSS
#   }
@export var monster_entries: Array[Dictionary] = []

## 该关刷怪总预算（用于关卡节奏校验；0 = 不限制）
@export var total_monster_budget: int = 0

## 是否允许随机精英替换（GDD 0.2 节：精英提供掉落与事件）
@export var elite_spawn_enabled: bool = true

## 精英替换比例（0–1）
@export var elite_ratio: float = 0.05

# -----------------------------------------------------------------------------
# 奖励
# -----------------------------------------------------------------------------

## 通关经验奖励（GDD 0.5 节 5.1：普通关 2500–4000）
@export var reward_xp: float = 2500.0

## 通关金币奖励区间
@export var reward_gold: Vector2i = Vector2i(100, 200)

## 必掉的装备件数（保底，GDD 0.2 节「变强可感知」）
@export var guaranteed_equipment_drops: int = 1

## 该关使用的掉落表 ID（覆盖怪物自带掉落表；空 = 使用怪物各自的表）
@export var loot_table_id: String = ""

## 首通奖励（材料 / 装备 ID 列表）
@export var first_clear_rewards: Array[Dictionary] = []

# -----------------------------------------------------------------------------
# 场景与解锁
# -----------------------------------------------------------------------------

## 关卡场景路径（阶段 2 填充；阶段 1 仅占位）
@export_file("*.tscn") var scene_path: String = ""

## 使用的 TileSet 路径
@export_file("*.tres") var tileset_path: String = ""

## 环境光调制色（对应美术规范 1.3 节章节主题色；Color(0,0,0,0) = 不覆盖）
@export var ambient_color: Color = Color(0, 0, 0, 0)

## 解锁条件：需先通关的关卡 ID 列表
@export var unlock_requires: Array[String] = []

## 允许挑战的最低难度层级（梦魇 I–V 逐层递进，GDD 0.5 节 5.4）
@export var min_difficulty_tier: int = GameConstants.DifficultyTier.NM1

# -----------------------------------------------------------------------------
# 程序化生成（任务 6.1）
# -----------------------------------------------------------------------------

## 精英锚点数（布局时远离出生点摆放；0 = 不摆精英锚点）
@export var elite_count: int = 0

## 本关 BOSS 怪物 ID（空 = 无 BOSS；BOSS 锚点摆在地图远端）
@export var boss_id: String = ""

## 布局参数。**两种模式由有没有 `cells` 键二选一**（见 `level_generator.gd` 类头）：
##   - 无 `cells` = **程序化**：`width`/`height`/`room_count`/`room_min`/`room_max`/
##     `obstacle_density`/`seed`；空 = 用 `LevelGenerator.DEFAULT_LAYOUT`。
##   - 有 `cells` = **手绘**：`cells` 为行字符串数组（`'#'`墙 `'.'`地面 `'o'`障碍
##     `'@'`玩家 `'m'`杂兵 `'e'`精英 `'B'`BOSS `'p'`拾取），可另带 `legend` 覆盖图例；
##     此时 `width`/`height`/`seed` 都不起作用（尺寸由行数 / 行宽决定，且整条路径不读 rng）。
##     逐字示例与校验规则见 `README.md` 8.3.1；实例如 `data/levels/chapter1.json` 的 `ch1_l02`。
@export var layout: Dictionary = {}

## 背景音乐路径
@export_file("*.ogg", "*.wav") var bgm_path: String = ""


# =============================================================================
# 查询
# =============================================================================

## 取指定难度层级下的实际经验奖励（难度越高经验越多，系数沿用 DMG 曲线）
func get_reward_xp(difficulty_tier: int) -> float:
	return reward_xp * GameConstants.difficulty_dmg_multiplier(difficulty_tier)


## 目标类型的中文名
func get_objective_name() -> String:
	if objective_type < 0 or objective_type >= OBJECTIVE_NAMES.size():
		return "未知"
	return OBJECTIVE_NAMES[objective_type]


## 该关的怪物条目是否合法（字段完整性检查）
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("LevelData.id 为空")
	if level < GameConstants.LEVEL_MIN or level > GameConstants.LEVEL_MAX:
		errors.append("关卡 '%s' 的 level 越界：%d（应在 %d–%d）"
			% [id, level, GameConstants.LEVEL_MIN, GameConstants.LEVEL_MAX])
	if objective_type < 0 or objective_type >= OBJECTIVE_NAMES.size():
		errors.append("关卡 '%s' 的 objective_type 非法：%d" % [id, objective_type])
	if monster_entries.is_empty():
		errors.append("关卡 '%s' 没有任何 monster_entries" % id)
	for i in range(monster_entries.size()):
		var entry: Dictionary = monster_entries[i]
		if not entry.has("monster_id"):
			errors.append("关卡 '%s' 的第 %d 条 monster_entry 缺少 monster_id" % [id, i])
		var cmin := int(entry.get("count_min", 0))
		var cmax := int(entry.get("count_max", 0))
		if cmax < cmin:
			errors.append("关卡 '%s' 的第 %d 条 monster_entry 的 count_max < count_min" % [id, i])
	return errors


## 转为字典（供仿真脚本 / 调试输出）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"chapter": chapter,
		"level": level,
		"objective_type": objective_type,
		"objective_value": objective_value,
		"monster_entries": monster_entries,
		"reward_xp": reward_xp,
		"reward_gold": [reward_gold.x, reward_gold.y],
	}
