## 地面掉落物（阶段 2 · 任务 2.7 · 掉落与拾取）
##
## 美术规范 0.7 v1.4「掉落辨识度五层递进」的地面物件层：
##   1. 物件本体（装备 = 稀有度色 12×12 方块 + 稀有度描边；金币 = 金色 8×8；材料 = 蓝 8×8）
##   2. 稀有度光柱（RARITY_BEAM_HEIGHTS[rarity] 高度直线柱，按稀有度色）
##   3. 稀有度文字（1 秒后浮现，防挡视线；阶段 3 物品框/音效补足）
##
## 拾取：玩家（player 组）靠近 ≤ PICKUP_RADIUS 自动拾取（延迟 LOOT_POP_DELAY 防瞬拾）。
## 存活 LOOT_DROP_LIFETIME 后消失；死亡实体不绘制。
class_name LootDrop
extends Node2D

## 掉落类型：gold / material / equipment（LootRoller 产出字段）
var drop_type: String = "gold"

## 数量（金币/材料）
var amount: int = 1

## 装备底材 ID（equipment 时有效）
var item_id: String = ""

## 稀有度（GameConstants.Rarity；金币/材料为 -1 不显示光柱）
var rarity: int = -1

## 物品等级
var item_level: int = 1

## 掉落时定型的完整装备实例（`EquipmentInstance.to_dict()`，**含词缀**）。
##
## ⚠️ 这个字段必须一路带到 `PlayerController.pickup_loot()`，中间漏掉任何一环，
##    玩家捡到的装备就退化成**无词缀白板**，而且**不会有任何报错**
##    （`pickup_loot` 里 `if entry.has("instance")` 不成立时会静默走「无词缀占位」分支）。
##    曾经本节点就没有这个字段、`setup()` 也不读它 ⇒ 词缀在掉落物这一环被丢弃，
##    而 `verify_affix_roller.gd` 因为**直接调用** `pickup_loot()`（不经过本节点）而全绿。
##    `tools/verify_e2e.tscn` 已补「走真实掉落节点」的断言来盯死这条。
var instance: Dictionary = {}

## 是否为「收集目标物」（关卡目标 `collect` 用）。
##
## 与普通掉落有两点必须不同：
##   1. **不过期** —— 普通掉落 60s 后消失（`LOOT_DROP_LIFETIME`），但目标物一旦消失，
##      「收集 N 个」就**永久不可完成**（玩家还没走到就没了）。
##   2. **拾取后广播** —— 关卡容器靠 `picked_up` 统计进度。不能改看玩家背包：目标物是
##      `material`，不进 `inventory`，从背包侧看不见。
var is_collectible: bool = false

## 被拾取后广播（不分类型）。载荷与交给 `pickup_loot()` 的字典一致。
## 消费点：`LevelScene._on_collectible_picked_up()` 统计收集进度。
signal picked_up(entry: Dictionary)

## 收集物（目标物）配色 / 光柱高度。形状与配色都和金币（金方块）、材料（蓝方块）区分，
## 因为玩家必须能一眼认出「哪个是目标物」，否则 collect 关会变成盲找东西。
const COLLECTIBLE_COLOR: Color = Color("7FE7D0")
const COLLECTIBLE_BEAM_HEIGHT: float = 30.0

## 存活计时（LOOT_DROP_LIFETIME 后消失；收集物不过期）
var _lifetime: float = 0.0

## 出生计时（LOOT_POP_DELAY 内不可拾取）
var _age: float = 0.0

var _picked: bool = false
var _player: Node = null


## 便捷构造：按 LootRoller 条目初始化
func setup(entry: Dictionary) -> void:
	drop_type = entry.get("type", "gold")
	amount = int(entry.get("amount", 1))
	item_id = str(entry.get("item_id", ""))
	rarity = int(entry.get("rarity", -1))
	item_level = int(entry.get("item_level", 1))
	# 词缀实例（LootRoller 在掉落时就 roll 好并放在 "instance" 键，任务 3.2「掉落即定型」）
	if entry.has("instance") and entry["instance"] is Dictionary:
		instance = entry["instance"]
	# 收集目标物标记（关卡容器摆放时置 true）
	is_collectible = bool(entry.get("collectible", false))
	queue_redraw()


func _ready() -> void:
	add_to_group(&"loot_drops")
	z_index = 2
	# 收集物常驻：目标物过期消失会让「收集 N 个」永久不可完成，所以不参与 60s 过期。
	_lifetime = INF if is_collectible else GameConstants.LOOT_DROP_LIFETIME


func _process(delta: float) -> void:
	_age += delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player")
	if _player != null and _age >= GameConstants.LOOT_POP_DELAY:
		var dist := global_position.distance_to(_player.global_position)
		if dist <= GameConstants.PICKUP_RADIUS:
			_pick_up()
	if not _picked:
		queue_redraw()


## 自动拾取：调用玩家收集接口后移除
func _pick_up() -> void:
	if _picked or _player == null:
		return
	_picked = true
	var payload := {
		"type": drop_type, "amount": amount,
		"item_id": item_id, "rarity": rarity, "item_level": item_level,
	}
	# 带上词缀实例（见 instance 字段的注释：漏掉 = 装备变白板且无报错）
	if not instance.is_empty():
		payload["instance"] = instance
	if _player.has_method("pickup_loot"):
		_player.call("pickup_loot", payload)
	# 广播给关卡容器（收集类目标靠它计数）。放在 `pickup_loot` **之后**：
	# 先让金币 / 背包真正入账，再通知进度，避免出现「进度涨了但东西没进包」。
	picked_up.emit(payload)
	# 全局拾取广播（步骤 6 · 拾取提示 HUD 消费；此前该信号声明了但从未 emit）。
	EventBus.loot_picked_up.emit(payload)
	# 拾取光晕（贴图特效，见 `data/fx.json`）。
	# ⚠️ 必须挂到**父节点**：本节点下一行就 `queue_free()`，挂自己身上特效会一起消失。
	# 贴图缺失时 `spawn` 返回 null，静默无特效（不是回归 —— 引入贴图层前也没有这个表现）。
	FxTable.spawn("pickup_glow", global_position, {"host": get_parent()})
	queue_free()


func _draw() -> void:
	# 收集物（目标物）：青白色块 + 高光柱。排在 match 之前，不走金币 / 材料 / 装备的绘制。
	if is_collectible:
		_draw_box(Vector2.ZERO, 10, COLLECTIBLE_COLOR, Color("0B0D10"))
		_draw_beam(COLLECTIBLE_COLOR, COLLECTIBLE_BEAM_HEIGHT)
		return
	match drop_type:
		"gold":
			_draw_box(Vector2.ZERO, 8, Color("D9A521"), Color("0B0D10"))
		"material":
			_draw_box(Vector2.ZERO, 8, Color("4C8BF5"), Color("0B0D10"))
		"equipment":
			var c := GameConstants.rarity_color(rarity) if rarity >= 0 else Color.WHITE
			_draw_box(Vector2.ZERO, GameConstants.LOOT_EQUIPMENT_ICON_SIZE, c, Color("0B0D10"))
			_draw_beam(c)
			# 光柱顶端小亮点（高出 3px 的金字塔形，指引视线）
			var h := GameConstants.RARITY_BEAM_HEIGHTS[rarity] if rarity >= 0 else 0
			if h > 0:
				draw_rect(Rect2(-2.0, -h - 6.0, 4.0, 2.0), Color(1.0, 1.0, 1.0, 0.85))


## 色块 + 1px 深描边（像素风铁律：Nearest、描边脱离背景）
func _draw_box(center: Vector2, size: float, fill: Color, outline: Color) -> void:
	var rect := Rect2(center.x - size * 0.5, center.y - size * 0.5, size, size)
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, 1.0)


## 稀有度光柱：从物件顶部向上直线柱（高度 RARITY_BEAM_HEIGHTS），带淡出
##
## `height_override >= 0` 时用它。收集物没有 `rarity`（-1），取不到稀有度光柱高度，
## 必须显式给一个，否则光柱画不出来 ⇒ 目标物在场景里不显眼。
func _draw_beam(c: Color, height_override: float = -1.0) -> void:
	var h: float
	if height_override >= 0.0:
		h = height_override
	elif rarity >= 0:
		h = float(GameConstants.RARITY_BEAM_HEIGHTS[rarity])
	else:
		return
	if h <= 0.0:
		return
	# 渐变柱：分段绘制制造纵向渐隐（顶部淡）
	var seg := 4
	for i in seg:
		var y0 := -h + float(i) * float(h) / float(seg)
		var y1 := -h + float(i + 1) * float(h) / float(seg)
		var alpha := 0.55 * (1.0 - float(i) / float(seg))
		draw_rect(Rect2(-1.0, y0, 2.0, y1 - y0), Color(c, alpha))
	# 底部一圈（物件发光）
	draw_rect(Rect2(-4.0, 0.0, 8.0, 1.0), Color(c, 0.7))
