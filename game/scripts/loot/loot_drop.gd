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

## 掉落类型：gold / material / equipment / consumable / rune（LootRoller 产出字段）
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

## 金币 / 材料配色。抽成常量供 `_draw()` 与「拾取光晕染色」（`_pickup_glow_color`）**共用** ——
## 此前 `_draw` 里是两处十六进制字面量，加染色时再抄一遍就会变成「改一处忘一处」的漂移源。
const GOLD_COLOR: Color = Color("D9A521")
const MATERIAL_COLOR: Color = Color("4C8BF5")

## 符文掉落物（2-L12）：紫罗兰色 + 光柱高度。
##
## ⚠️ 符文没有 `rarity`（-1）⇒ 取不到 `RARITY_BEAM_HEIGHTS`，**必须**给显式高度，
##    否则 `_draw_beam()` 直接 return，地面上只剩一个孤零零的图标（不显眼）。
const RUNE_COLOR: Color = Color("9B6BE8")
const RUNE_BEAM_HEIGHT: float = 28.0
## 符文图标的**世界尺寸**（源素材 `rune_icon_*_48.png` 是 48×48，缩到 20 才能和 12px 的
## 装备方块在同一视觉量级；再大就会盖住光柱、并在密集掉落时糊成一团）。
const RUNE_ICON_WORLD_SIZE: float = 20.0

## 存活计时（LOOT_DROP_LIFETIME 后消失；收集物不过期）
var _lifetime: float = 0.0

## 出生计时（LOOT_POP_DELAY 内不可拾取）
var _age: float = 0.0

var _picked: bool = false
var _player: Node = null

## 地面光柱特效累计时长（秒）。`_draw_beam` 各形状分支用它做呼吸 / 脉动 / 粒子相位
## （DNF 式掉落閃光：光柱 + 十字爆闪 + 火环 + 上升粒子，全部程序化绘制、零新素材）。
var _fx_t: float = 0.0

## 吸附当前速度（px/s）。进入磁吸半径后逐帧加速，见 `_process`。
var _magnet_speed: float = 0.0

# -----------------------------------------------------------------------------
# 弹出动画（Playground「拾取：掉落物 pop 出來帶星光」）
# -----------------------------------------------------------------------------
#
# 此前掉落物是「直接出现在落点」—— 敌人一死，地上凭空多出几件东西，毫无「掉出来」的感觉。
# 本组让掉落物从**死亡点**沿抛物线弹到落点，落地后再小回弹一次，并带 4 点星光。
#
# ⚠️ 全程只改 `global_position`、**不改 scale**：像素铁律只允许整数缩放，
#    位移不受此限（而 `scale` 从 0 弹到 1 会经过一堆非整数倍，直接违规）。

## 弹出动画的起点（世界坐标）。`Vector2.INF` = 不做弹出（关卡摆放的收集物 / 旧调用方 / 测试桩）。
##
## ⚠️ 必须由调用方在 `add_child()` **之前**设好 —— `_ready` 一进树就据此把节点挪到起点
##    （见 `_ready` 的「两段式落点」说明）。
var pop_from: Vector2 = Vector2.INF

## 抛物线飞行时长（秒）
const POP_TIME: float = 0.34
## 落地小回弹时长（秒）
const POP_BOUNCE_TIME: float = 0.12
## 飞行途中的额外抛物高度（px）
const POP_ARC_LIFT: float = 12.0
## 落地小回弹的抬升高度（px）
const POP_BOUNCE_LIFT: float = 5.0
## 弹出星光：斜向星点个数 / 内圈半径 / 外圈半径 / 星点边长（px）
const POP_SPARKLE_COUNT: int = 4
const POP_SPARKLE_INNER: float = 4.0
const POP_SPARKLE_OUTER: float = 13.0
const POP_SPARKLE_SIZE: float = 2.0

## 弹出动画已播时长（秒）。**< 0 = 未在播放**（也是「有没有弹出」的唯一判据）。
var _pop_elapsed: float = -1.0
## 落点（`_ready` 里从「调用方已设好的 global_position」捕获）。
var _pop_target: Vector2 = Vector2.ZERO
## 弹出动画**上一帧自己写下的位置** —— 用来侦测「外部插手」：
## `_process` 里若发现 `global_position` 不等于它，说明别人动过 ⇒ 动画立刻让位（见 `_process`）。
var _pop_written: Vector2 = Vector2.ZERO


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
	# 弹出动画（Playground「掉落物 pop 出來帶星光」）。
	# ⚠️ 为什么放在 `_ready`：这是「进树」的时点，早于任何 `_process` ⇒ 第一帧就已在起点，
	#    不会先闪一下落点（与 `GroundArea.begin()` 处理「两段式落点」是同一族问题）。
	# ⚠️ `_pop_target` 取此刻的 `global_position` —— 调用方必须**在 `add_child` 之前**设好落点。
	if pop_from.is_finite():
		_pop_target = global_position
		global_position = pop_from
		_pop_written = pop_from
		_pop_elapsed = 0.0


func _process(delta: float) -> void:
	_age += delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	_fx_t += delta
	if _pop_elapsed >= 0.0:
		# 外部改写让位：`_advance_pop` 每帧都写 `global_position` ⇒ 若**别人**（磁吸 / 测试 /
		# 未来任何调用方）在本帧之前动过位置，动画必须**立刻交出控制权**，否则会把对方写的
		# 位置当场覆盖掉。⚠️ 实测撞红过 `verify_e2e` 段⑦（它把掉落物瞬移到玩家脚下，
		# 结果每帧被弹回抛物线 ⇒ 永远拾取不到 ⇒ 假红「背包没增长」）。
		# 判据 = 和「上一帧我自己写下的位置」比 —— 只有没人插手时两者才相等。
		if global_position.is_equal_approx(_pop_written):
			_advance_pop(delta)
		else:
			_pop_elapsed = -1.0
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player")
	if _player != null and _age >= GameConstants.LOOT_POP_DELAY:
		var ppos: Vector2 = _player.global_position
		var dist := global_position.distance_to(ppos)
		var bonus := _player_pickup_bonus()
		if dist <= GameConstants.PICKUP_RADIUS + bonus:
			_pick_up()
			return
		# 吸附（magnet · Playground 规格「靠近自动吸附」）：普通掉落进入磁吸半径后
		# 朝玩家加速飞去；目标物（is_collectible）保持静止（关卡刻意摆放，不该被吸走）。
		if not is_collectible and dist <= GameConstants.LOOT_MAGNET_RADIUS + bonus:
			# 被磁吸接管 ⇒ **立刻结束弹出动画**：否则 `_advance_pop` 与 `move_toward`
			# 会在同一帧抢着写 `global_position`（后写者赢），掉落物会左右抽搐。
			# （上面那条「外部改写让位」是同一件事的通用兜底，这里显式叫停是为了**当帧即停**。）
			_pop_elapsed = -1.0
			_magnet_speed = minf(
				maxf(_magnet_speed, GameConstants.LOOT_MAGNET_SPEED_INIT)
					+ GameConstants.LOOT_MAGNET_ACCEL * delta,
				GameConstants.LOOT_MAGNET_MAX_SPEED)
			global_position = global_position.move_toward(ppos, _magnet_speed * delta)
	if not _picked:
		queue_redraw()


## 推进弹出动画：`POP_TIME` 内沿抛物线从 `pop_from` 落到 `_pop_target`，
## 随后 `POP_BOUNCE_TIME` 内小回弹一次，然后复位（`_pop_elapsed = -1`）。
##
## 只写 `global_position` —— 见字段区「不改 scale」的说明（像素铁律）。
## 每次写完都同步记进 `_pop_written`（外部改写的侦测基线，见 `_process`）。
func _advance_pop(delta: float) -> void:
	_pop_elapsed += delta
	var t := _pop_elapsed
	if t < POP_TIME:
		var u := t / POP_TIME
		# ease-out quad：末段减速，读作「落地」
		var e := 1.0 - (1.0 - u) * (1.0 - u)
		var base := pop_from.lerp(_pop_target, e)
		# 抛物线抬升（u = 0.5 时最高）
		global_position = base + Vector2(0.0, -POP_ARC_LIFT * 4.0 * u * (1.0 - u))
	elif t < POP_TIME + POP_BOUNCE_TIME:
		var u := (t - POP_TIME) / POP_BOUNCE_TIME
		global_position = _pop_target + Vector2(0.0, -POP_BOUNCE_LIFT * sin(PI * u))
	else:
		global_position = _pop_target
		_pop_elapsed = -1.0
	_pop_written = global_position


## 玩家 `pickup_radius` 词缀加成（px）。**本函数是该词缀的唯一消费点** ——
## 此前 `StatCalculator` 算出它、UI 也显示它，却没有任何地方读它（死属性）。
## 未注入战斗属性（测试环境 / 旧调用方）⇒ 返回 0，与引入吸附前逐位一致。
func _player_pickup_bonus() -> float:
	if _player != null and _player.has_method("get_combat_stat"):
		return maxf(float(_player.call("get_combat_stat", GameConstants.STAT_PICKUP_RADIUS)), 0.0)
	return 0.0


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
	# 2026-10-14 拾取反馈强化：**按类型 / 稀有度染色** + 史诗以上**整数放大 2×**。
	# 此前是一张固定白图 —— 捡到金币和捡到神话装，地上那一下爆光长得一模一样。
	var glow := FxTable.spawn("pickup_glow", global_position, {"host": get_parent()})
	if glow != null:
		glow.modulate = _pickup_glow_color()
		var s := _pickup_glow_scale()
		if s > 1:
			# 像素铁律：**只整数缩放**（2× 是 24→48px，仍是像素对齐的）。
			glow.scale = Vector2(float(s), float(s))
	queue_free()


## 拾取光晕的颜色：按掉落类型 / 装备稀有度取。色源与地面物件、提示条一致。
## 未知类型 ⇒ 白色（`pickup_glow` 原图色，等同染色前的表现）。
func _pickup_glow_color() -> Color:
	if is_collectible:
		return COLLECTIBLE_COLOR
	match drop_type:
		"gold":
			return GOLD_COLOR
		"material":
			return MATERIAL_COLOR
		"rune":
			return RUNE_COLOR
		"equipment":
			return GameConstants.rarity_color(rarity) if rarity >= 0 else Color.WHITE
	return Color.WHITE


## 拾取光晕的**整数**缩放倍率（像素铁律）。
## 装备且史诗起 ⇒ 2×（越稀有越显眼，与「稀有掉落庆祝」同一情绪梯度）；其余 1×。
func _pickup_glow_scale() -> int:
	if drop_type == "equipment" and rarity >= GameConstants.Rarity.EPIC:
		return 2
	return 1


func _draw() -> void:
	# 收集物（目标物）：青白色块 + 高光柱。排在 match 之前，不走金币 / 材料 / 装备的绘制。
	if is_collectible:
		_draw_box(Vector2.ZERO, 10, COLLECTIBLE_COLOR, Color("0B0D10"))
		_draw_beam(COLLECTIBLE_COLOR, COLLECTIBLE_BEAM_HEIGHT)
		return
	match drop_type:
		"gold":
			_draw_box(Vector2.ZERO, 8, GOLD_COLOR, Color("0B0D10"))
		"material":
			_draw_box(Vector2.ZERO, 8, MATERIAL_COLOR, Color("0B0D10"))
			# 2026-10-19：地面材料（魔石）叠加 16px 图标（透明底，色块透出当底光）
			var mat_tex := UISkin.texture("stone_forge_16")
			if mat_tex != null:
				draw_texture_rect(mat_tex, Rect2(-8.0, -8.0, 16.0, 16.0), false)
		"consumable":
			var c := Color("E04848") if item_id == "life_potion" else Color("4890E0")
			_draw_box(Vector2.ZERO, 16, c, Color("0B0D10"))
			var con: Dictionary = ConfigLoader.consumables.get(item_id, {})
			var icon_name := str(con.get("icon", ""))
			if not icon_name.is_empty():
				var tex := UISkin.texture(icon_name)
				if tex != null:
					draw_texture_rect(tex, Rect2(-8.0, -8.0, 16.0, 16.0), false)
		"equipment":
			var c := GameConstants.rarity_color(rarity) if rarity >= 0 else Color.WHITE
			_draw_box(Vector2.ZERO, GameConstants.LOOT_EQUIPMENT_ICON_SIZE, c, Color("0B0D10"))
			_draw_beam(c)
			# 光柱顶端小亮点（高出 3px 的金字塔形，指引视线）
			var h := GameConstants.RARITY_BEAM_HEIGHTS[rarity] if rarity >= 0 else 0
			if h > 0:
				draw_rect(Rect2(-2.0, -h - 6.0, 4.0, 2.0), Color(1.0, 1.0, 1.0, 0.85))
		"rune":
			# 符文（2-L12）：紫罗兰光柱 + **真实符文图标**（与图鉴同一张 48×48 素材）。
			# 先画光柱再画图标，让图标压在柱脚上（否则柱脚会盖住图标下半）。
			_draw_beam(RUNE_COLOR, RUNE_BEAM_HEIGHT)
			var rtex := UISkin.rune_icon(item_id)
			if rtex != null:
				var s := RUNE_ICON_WORLD_SIZE
				draw_texture_rect(rtex, Rect2(-s * 0.5, -s * 0.5, s, s), false)
			else:
				# 素材缺失兜底：退回紫色方块（`UISkin.rune_icon` 缺档静默回 null，
				# 不兜底的话地面上就只剩一根光柱，玩家看不见掉的是什么）。
				_draw_box(Vector2.ZERO, 8, RUNE_COLOR, Color("0B0D10"))
	# 弹出星光**画在物件之上**（收集物永不弹出 ⇒ 上面那条 `return` 分支不需要它）。
	if _pop_elapsed >= 0.0:
		_draw_pop_sparkles()


## 弹出星光（Playground「掉落物 pop 出來帶星光」）。
##
## 纯 `_draw` 的 4 个斜向星点：随弹出进度由内向外扩散 + 线性淡出 ——
## **零新素材、零子节点、零 `z_index` 参与**（与「地面残留」自绘同一理由）。
## 颜色取 `_pickup_glow_color()` ⇒ 「掉出来时看到的星光色」== 「捡起来时的光晕色」，视觉自洽。
func _draw_pop_sparkles() -> void:
	var u := clampf(_pop_elapsed / (POP_TIME + POP_BOUNCE_TIME), 0.0, 1.0)
	var alpha := (1.0 - u) * 0.95
	if alpha <= 0.01:
		return
	var col := Color(_pickup_glow_color(), alpha)
	var r := lerpf(POP_SPARKLE_INNER, POP_SPARKLE_OUTER, u)
	for i in POP_SPARKLE_COUNT:
		var ang := TAU * float(i) / float(POP_SPARKLE_COUNT) + PI * 0.25  # 四个斜角
		var p := Vector2(cos(ang), sin(ang)) * r
		# 取整对齐像素：星点位移若非整数，在整数缩放下会「跳格」闪烁。
		p = Vector2(roundf(p.x), roundf(p.y))
		var h := POP_SPARKLE_SIZE * 0.5
		draw_rect(Rect2(p.x - h, p.y - h, POP_SPARKLE_SIZE, POP_SPARKLE_SIZE), col)


## 色块 + 1px 深描边（像素风铁律：Nearest、描边脱离背景）
func _draw_box(center: Vector2, size: float, fill: Color, outline: Color) -> void:
	var rect := Rect2(center.x - size * 0.5, center.y - size * 0.5, size, size)
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, 1.0)


## 稀有度光柱：从物件顶部向上直线柱（高度 RARITY_BEAM_HEIGHTS），带淡出
##
## `height_override >= 0` 时用它。收集物没有 `rarity`（-1），取不到稀有度光柱高度，
## 必须显式给一个，否则光柱画不出来 ⇒ 目标物在场景里不显眼。
##
## B5-4（6-W6-19）：按 BeamShape 分支绘制。此前无论什么稀有度都画同一根渐变柱，
## 深渊（PRISM）与塔（SPIRE）两档视觉完全相同 ⇒ 玩家无法在地面一眼区分来源。
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
	var shape: int = GameConstants.rarity_beam_shape(rarity) if height_override < 0.0 else GameConstants.BeamShape.LINE
	match shape:
		GameConstants.BeamShape.SPECIAL_PRISM:
			_draw_prism_beam(h, c)
			return
		GameConstants.BeamShape.SPECIAL_SPIRE:
			_draw_spire_beam(h, c)
			return
		GameConstants.BeamShape.LINE_PULSE:
			_draw_pulse_beam(h, c)
			return
		GameConstants.BeamShape.LINE_RING:
			_draw_ring_beam(h, c)
			return
		GameConstants.BeamShape.LINE_BURST:
			_draw_burst_beam(h, c)
			return
		GameConstants.BeamShape.LINE_FIRERING:
			_draw_firering_beam(h, c)
			return
		GameConstants.BeamShape.DIAMOND_RING:
			_draw_diamond_ring(c)
			return
		GameConstants.BeamShape.GRADIENT_SEG:
			_draw_gradient_beam(h)
			return
	# 普通档：渐变柱（分段纵向渐隐，顶部淡）
	var seg := 4
	for i in seg:
		var y0 := -h + float(i) * float(h) / float(seg)
		var y1 := -h + float(i + 1) * float(h) / float(seg)
		var alpha := 0.55 * (1.0 - float(i) / float(seg))
		draw_rect(Rect2(-1.0, y0, 2.0, y1 - y0), Color(c, alpha))
	# 底部一圈（物件发光）
	draw_rect(Rect2(-4.0, 0.0, 8.0, 1.0), Color(c, 0.7))


## 深渊光柱（SPECIAL_PRISM）：深紫主柱 + 青/品红分层切面，每 8px 一个切面。
## 静态可辨（不依赖动画），靠「双色分层」和普通单柱拉开差距。
func _draw_prism_beam(h: float, c: Color) -> void:
	var cyan := Color("37E6D8")
	var magenta := Color("C74BD8")
	# 主柱（深紫，3px 宽，比普通柱粗）
	for i in 5:
		var y0 := -h + float(i) * h / 5.0
		var y1 := -h + float(i + 1) * h / 5.0
		var alpha := 0.6 * (1.0 - float(i) / 5.0)
		draw_rect(Rect2(-1.5, y0, 3.0, y1 - y0), Color(c, alpha))
	# 每 8px 一个侧切面：左右交替青色 / 品红
	var y := -h
	var toggle := true
	while y < -2.0:
		var side := -3.5 if toggle else 0.5
		var facet := cyan if toggle else magenta
		draw_rect(Rect2(side, y, 2.0, 3.0), Color(facet, 0.8))
		y += 8.0
		toggle = not toggle
	draw_rect(Rect2(-5.0, 0.0, 10.0, 1.0), Color(c, 0.8))


## 塔光柱（SPECIAL_SPIRE）：青白主色，分 3 段递窄，段间 2px 暗色分隔。
## 越往上越细，剪影像一座塔，区别于深渊的双色棱柱。
func _draw_spire_beam(h: float, c: Color) -> void:
	var segs := [3.0, 2.0, 1.0]  # 底→顶逐段宽度
	var seg_h := h / 3.0
	for i in 3:
		var w: float = segs[i]
		var y0 := -h + float(i) * seg_h + (2.0 if i > 0 else 0.0)  # 段间 2px 暗缝
		var y1 := -h + float(i + 1) * seg_h
		var alpha := 0.7 - float(i) * 0.15
		draw_rect(Rect2(-w * 0.5, y0, w, y1 - y0), Color(c, alpha))
	draw_rect(Rect2(-4.0, 0.0, 8.0, 1.0), Color(c, 0.8))


# -----------------------------------------------------------------------------
# DNF 式掉落闪光（B5-4 已聲明、此前未實現的光柱形狀）
# 全部程序化 `_draw` 繪製、零新素材；相位統一用 `_fx_t`（見 `_process`）。
# 像素鐵律：所有座標取整、只畫 1px 系矩形，不做運行時旋轉。
# -----------------------------------------------------------------------------

## 柱頂十字閃光（legendary 爆閃用）：垂直 + 水平亮線，alpha 隨 len 呼吸。
## 垂直線從柱頂再向上 14px；水平線以柱軸為中點向兩側各 6px。
func _draw_top_cross(c: Color, strength: float) -> void:
	var top: float = -12.0
	if rarity >= 0 and rarity < GameConstants.RARITY_BEAM_HEIGHTS.size():
		top = -float(GameConstants.RARITY_BEAM_HEIGHTS[rarity])
	var a := clampf(strength, 0.0, 1.0)
	if a <= 0.02:
		return
	# 垂直線（柱頂向上延伸，1px 寬）
	draw_rect(Rect2(-1.0, top - 14.0, 2.0, 14.0), Color(c, 0.85 * a))
	# 水平線（柱頂向兩側，2px 高）
	draw_rect(Rect2(-8.0, top - 2.0, 16.0, 2.0), Color(c, 0.75 * a))
	# 中心亮點
	draw_rect(Rect2(-1.0, top - 3.0, 3.0, 3.0), Color(1.0, 1.0, 1.0, 0.9 * a))


## 上升光點（legendary/mythic 粒子）：count 個光點沿柱頂往上循環上浮 + 淡出。
func _draw_rising_particles(c: Color, count: int, span: float, speed: float) -> void:
	for i in count:
		var phase := fmod(_fx_t * speed + float(i) * span / float(count), span)
		var y := -span * 0.5 - phase  # 從柱半腰往上浮出畫面
		var x := -1 + (i % 3)  # 1px 橫向錯開，避免粒子疊成一條線
		var a := 0.85 * (1.0 - phase / span)
		draw_rect(Rect2(float(x), roundf(y), 2.0, 2.0), Color(c, a))


## 地面像素環（epic 光環 / mythic 火環共用）：r 半徑的 8 點環 + 對角 4 點，
## alpha 呼吸（`breath` 0..1）。點為 2×2 亮塊（1px 見方在整數縮放下會跳格）。
func _draw_ground_ring(c: Color, r: float, breath: float) -> void:
	var a := clampf(breath, 0.0, 1.0)
	if a <= 0.02:
		return
	var pts: Array[Vector2] = []
	for i in 8:
		var ang := TAU * float(i) / 8.0
		pts.append(Vector2(roundf(cos(ang) * r), roundf(sin(ang) * r)))
	for p in pts:
		draw_rect(Rect2(p.x - 1.0, p.y - 1.0, 2.0, 2.0), Color(c, 0.8 * a))
	# 物件腳下一圈底座亮點（環的「錨」）
	draw_rect(Rect2(-4.0, -1.0, 8.0, 1.0), Color(c, 0.9 * a))


## 稀有（LINE_PULSE）：直線柱 + 呼吸脈動（alpha 整體起伏）。
func _draw_pulse_beam(h: float, c: Color) -> void:
	var pulse := 0.72 + 0.28 * sin(_fx_t * 3.2)
	var seg := 4
	for i in seg:
		var y0 := -h + float(i) * float(h) / float(seg)
		var y1 := -h + float(i + 1) * float(h) / float(seg)
		var alpha := 0.6 * (1.0 - float(i) / float(seg)) * pulse
		draw_rect(Rect2(-1.0, y0, 2.0, y1 - y0), Color(c, alpha))
	draw_rect(Rect2(-4.0, 0.0, 8.0, 1.0), Color(c, 0.8 * pulse))


## 史詩（LINE_RING）：直線柱 + 地面光環（8 點環呼吸擴散）。
func _draw_ring_beam(h: float, c: Color) -> void:
	_draw_pulse_beam(h, c)
	var r := 9.0 + 4.0 * sin(_fx_t * 2.4)
	var breath := 0.55 + 0.45 * sin(_fx_t * 2.4)
	_draw_ground_ring(c, r, breath)


## 金色大柱（legendary/mythic 共用，DNF 式冲击）：外层金色光晕 3px + 内芯白亮 1px，
## 顶段更亮（上实下虚）。与普通单柱在「宽度 + 双层 + 金色」三维拉开差距。
func _draw_gold_beam(h: float) -> void:
	var gold := Color("F5C542")
	# 外层金色光晕（3px 宽，纵向分段渐隐）
	var seg := 5
	for i in seg:
		var y0 := -h + float(i) * float(h) / float(seg)
		var y1 := -h + float(i + 1) * float(h) / float(seg)
		var alpha := 0.55 * (1.0 - float(i) / float(seg))
		draw_rect(Rect2(-1.5, y0, 3.0, y1 - y0), Color(gold, alpha))
	# 内芯白亮（1px）
	for i in seg:
		var y0 := -h + float(i) * float(h) / float(seg)
		var y1 := -h + float(i + 1) * float(h) / float(seg)
		var alpha := 0.9 * (1.0 - float(i) / float(seg))
		draw_rect(Rect2(-0.5, y0, 1.0, y1 - y0), Color(1.0, 1.0, 1.0, alpha))
	# 底部金色底座圈
	draw_rect(Rect2(-4.0, 0.0, 8.0, 1.0), Color(gold, 0.95))


## 傳說（LINE_BURST）：金色大柱 + 掉落瞬間柱頂十字爆閃 + 上升金色粒子。
func _draw_burst_beam(h: float, c: Color) -> void:
	_draw_gold_beam(h)
	var gold := Color("F5C542")
	# 地面爆閃（出生後 0.5s 內）：金色十字向外擴 + 淡出
	if _fx_t < 0.5:
		var u := _fx_t / 0.5
		var burst := (1.0 - u) * 0.9
		_draw_top_cross(gold, burst)
		_draw_ground_ring(gold, 12.0 + 10.0 * u, burst)
	# 持續：上升金色粒子
	_draw_rising_particles(gold, 3, h + 10.0, 18.0)


## 神話（LINE_FIRERING）：金色大柱 + 地面持續火環（呼吸）+ 上升金色粒子。
## 火環色固定金色（與角色神話紅主色分離，一眼認出「火」）。
func _draw_firering_beam(h: float, c: Color) -> void:
	_draw_gold_beam(h)
	var fire := Color("F5C542")
	var r := 11.0 + 3.0 * sin(_fx_t * 3.6)
	var breath := 0.6 + 0.4 * sin(_fx_t * 3.6)
	_draw_ground_ring(fire, r, breath)
	_draw_rising_particles(fire, 4, h + 12.0, 22.0)
	_draw_ground_ring(c, 5.0, 0.8)  # 內圈主色底座


## 套裝（DIAMOND_RING）：菱形環（青綠）取代直線柱 —— 換形狀不比高度。
func _draw_diamond_ring(c: Color) -> void:
	var r := 10.0 + 2.0 * sin(_fx_t * 2.0)
	var a := 0.7 + 0.3 * sin(_fx_t * 2.0)
	# 菱形 4 角 + 4 邊點（像素菱形，靜態不旋轉）
	var pts: Array[Vector2] = [
		Vector2(0.0, -r), Vector2(r, 0.0), Vector2(0.0, r), Vector2(-r, 0.0),
		Vector2(r * 0.5, -r * 0.5), Vector2(r * 0.5, r * 0.5),
		Vector2(-r * 0.5, r * 0.5), Vector2(-r * 0.5, -r * 0.5),
	]
	for p in pts:
		draw_rect(Rect2(p.x - 1.0, p.y - 1.0, 2.0, 2.0), Color(c, 0.9 * a))
	draw_rect(Rect2(-3.0, -1.0, 6.0, 1.0), Color(c, 0.95))


## 隱藏（GRADIENT_SEG）：6 色分段柱 + 上升白星點（彩蛋專屬，全池最低權重）。
func _draw_gradient_beam(h: float) -> void:
	var colors := [
		Color("FF2D55"), Color("FF8A2B"), Color("F5C542"),
		Color("2FA37A"), Color("4C8BF5"), Color("A96BFF"),
	]
	var seg_h := h / 6.0
	for i in 6:
		var y0 := -h + float(i) * seg_h
		var y1 := -h + float(i + 1) * seg_h
		draw_rect(Rect2(-2.0, y0, 4.0, y1 - y0), Color(colors[i], 0.8))
	_draw_rising_particles(Color(1.0, 1.0, 1.0), 4, h + 8.0, 20.0)
	draw_rect(Rect2(-4.0, 0.0, 8.0, 1.0), Color(colors[1], 0.9))
