## 关卡容器（集成层阶段 3 · 审计行动 #2「能从据点进关、打完能出结算」）
##
## 结构（见 `scenes/levels/level.tscn`，节点名与下方 @onready 一一对应）：
##   Level (Node2D)            ← 本脚本
##   ├── LevelView (Node2D)    ← 单节点批处理绘制全图（任务 8.3：恒定 1–2 个 draw call）
##   ├── Actors (Node2D)       ← 运行时容器：玩家 / 敌人 / 掉落物
##   │                              （`EnemyBase._drop_loot()` 会把 LootDrop 塞进 `get_parent()`，
##   │                                所以敌人必须挂在这个容器下，掉落才会落在同一层）
##   ├── Camera2D              ← zoom 在代码里设 `GameConstants.CAMERA_ZOOM_BASE`，**不写死在 .tscn**
##   └── HUD (CanvasLayer)
##       ├── Objective (Label)      ← 目标进度
##       ├── Banner (Label)         ← 失败 / 提示横幅
##       ├── HpBar (HealthBar)      ← 绑玩家 HealthComponent
##       └── ResultPanel (ResultPanel)
##
## 入场契约：`SceneManager.change_to_level()` 切场景后回调 `on_scene_entered(payload)`，
##   payload 恒为 `{level_id: String, difficulty_tier: int}`（scene_manager.gd:88-100）。
##   ⚠️ 直接 F6 运行本场景**不经过** SceneManager ⇒ `on_scene_entered` 不会触发；
##   `_ready` 里等 3 帧后仍无 level_id 就退回默认关，保证单场景可调试。
##
## 数据源：
##   - 关卡定义 `ConfigLoader.get_level(level_id)`
##   - 布局     `LevelGenerator.generate(level_def, rng)`
##   - 账号属性 `SaveManager.current_data` → `StatCalculator.calculate()`（取 max_hp 写进玩家）
##
## 接线（**每个 emit 都注明谁在听**，避免制造审计 §2.5 说的「死信号」）：
##   connect unit_died               ← HealthComponent 广播（玩家与敌人共用），消费为击杀计数
##   emit    level_started           → 本场景 HUD（写目标文案）
##   emit    level_objective_updated → 本场景 HUD（刷新进度）
##   emit    level_failed            → 本场景 HUD（失败横幅）
##   emit    run_level_up            → 本场景（弹 `ChoicePanel` 三选一，选定后重算属性）
##   emit    level_completed         → SceneManager._on_level_completed（Autoload 常驻；载荷 {"result": res}）
##
## ⚠️ 已知限制（明确记录，**不静默**）：
##   1. `LevelView` 只画不碰撞 —— 墙 / 障碍**没有 StaticBody2D**（任务 8.3 为压 draw call
##      刻意把全图塞进单个 CanvasItem）。本阶段玩家可以走过墙格，属已知表现缺口。
##   2. 目标类型完整实现 `clear_all` / `kill_boss` / `kill_elite` / `collect`；
##      `survive` / `reach_exit` **未实现** ⇒ 退化为「清空全部」并 `push_warning`，
##      不假装完成（否则玩家会遇到「打光了也不结算」且无任何提示）。
##      `collect` 的目标物在 `LevelGenerator.pickup_spawns` 上**确定性**摆放（数量恒等于
##      `objective_value`），不依赖随机掉落 —— 靠掉落凑数会让「收集 3 个」变成概率目标
##      （普通怪掉率 8%，一整关可能一件都不出），端到端验收会 flaky。
##   3. BOSS 以 `LevelData.boss_id` 为**权威**来源，刷在 `LevelGenerator.boss_spawn`
##      （地图远端锚点，即「BOSS 房」）上；`monster_entries[].is_boss` 作为**兼容**来源保留。
##      2026-09-18 修复：此前只认 `is_boss` 条目 ⇒ 只写了 `boss_id` 的 `ch2_l13` /
##      `ch3_l20` 的 BOSS **永不出现**，而目标是 kill_boss ⇒ 这两关永远打不完。
##   4. 局内三选一（GDD 0.4 节 4.1）：`RunProgression` 升级 → 本场景弹 `ChoicePanel`，
##      选定后经 `_apply_account_stats(false)` 把 `RunBuffSystem.to_calculator_buffs()`
##      传给 `StatCalculator` 重算属性。2026-09-18 修复：此前**只打印不弹面板**，
##      且属性计算传的是**空 buffs** ⇒ 局内成长在实战中完全不可用（升级拿不到任何增益），
##      尽管 `ChoicePanel` / `RunBuffSystem` / `RunePool` 三件套早已实现并各自验证通过。
##      ⚠️ 待裁定：三选一**不暂停**游戏（GDD 未规定），玩家读卡时仍会被攻击。
##      若要暂停，需 `get_tree().paused = true` + 给面板与 HUD 设 `PROCESS_MODE_ALWAYS`。
##   5. ESC「放弃本局」逃生口（2026-09-18 主理人裁定，同日落地）：
##      ESC → 二次确认「放弃本局？」→ 确认走 `_finish_run(false)`（与玩家死亡**同一条**
##      失败结算分支）。这是关卡里**唯一**的正规退出路径 —— 此前没有它，玩家唯一出路是
##      Alt+F4，而 Alt+F4 会绕过 `_persist()` ⇒ **已入包装备静默丢失**（比卡死更隐蔽）。
##      ⚠️ 绝不允许把「放弃」实现成直接 `SceneManager.change_to_hub()`：那同样绕过 `_persist()`。
##      - 结算已发生（`_finished` / `_settling`）时按 ESC：不弹确认（本局已结束）。
##      - 三选一面板显示中按 ESC：**吞掉、不放弃**（详见 `_on_escape_pressed` 的理由）。
extends Node2D
class_name LevelScene

# =============================================================================
# 常量
# =============================================================================

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")
const LOOT_SCENE: PackedScene = preload("res://scenes/loot/loot_drop.tscn")

## 不经 SceneManager 直接运行本场景时的调试关（ch1_l01 是 clear_all，最易跑通）
const DEFAULT_LEVEL_ID: String = "ch1_l01"

const TILE_PX: int = 32

# =============================================================================
# 节点引用
# =============================================================================

@onready var _view: LevelView = $LevelView
@onready var _actors: Node2D = $Actors
@onready var _camera: Camera2D = $Camera2D
@onready var _objective_label: Label = $HUD/Objective
@onready var _banner: Label = $HUD/Banner
@onready var _hp_bar: HealthBar = $HUD/HpBar
@onready var _mp_bar: HealthBar = $HUD/MpBar
@onready var _result_panel: ResultPanel = $HUD/ResultPanel

# =============================================================================
# 运行时状态
# =============================================================================

## 入场载荷
var level_id: String = ""
var difficulty_tier: int = GameConstants.DifficultyTier.NM1

var _level_def: LevelData = null
var _layout: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _player: PlayerController = null
## 存活敌人（死亡时移出；用数组而非计数，方便断言「谁还在」）
var _alive: Array[EnemyBase] = []
var _boss_total: int = 0
var _elite_total: int = 0

## 局内成长 / 连杀（GDD 0.4 节 4.1：出关清零）
var _progression: RunProgression = null
var _buff_system := RunBuffSystem.new()

## 当前三选一面板（同一时刻最多一个，连续升级时替换而不是叠层）
var _choice_panel: ChoicePanel = null

## 「放弃本局」二次确认弹窗（ESC 触发）。null = 未弹出。
## 用**自建 Control + 按钮**而非原生 `ConfirmationDialog`：后者是 `Window` 子类，
## `popup_centered()` 走 OS 窗口路径，无头下不可驱动（测试拿不到也点不着它的按钮）。
## 自建面板可在无头下由测试直接找到按钮并 `pressed.emit()` 驱动。
var _abandon_confirm: Control = null

## 局内增益 HUD（原任务 D）：显示三选一叠层 + 连杀，让「局内成长」对玩家**可见**。
## 节点在代码里建（`scenes/levels/level.tscn` 不在本次文件独占范围，不能改场景文件）。
var _buff_label: Label = null

## 增益 HUD 轮询兜底间隔（秒）。事件驱动为主，见 `_build_buff_hud` 的刷新策略说明。
const BUFF_HUD_POLL_INTERVAL: float = 0.2
var _buff_hud_poll: float = 0.0
## 上次 HUD 文本签名（相同则不改 `text`，避免每帧触发 UI 重排）
var _buff_hud_sig: String = ""

## 三选一抽卡的**独立**随机源。
## ⚠️ 不能与地图生成的 `_rng` 共用：`_rng` 会被 `layout_seed` 播种以保证地图可复现，
##    而三选一消耗随机流会让「升了几级」反过来影响地图布局，破坏确定性测试。
var _choice_rng := RandomNumberGenerator.new()

## 本局统计（结算单入参）
var _kills: int = 0
var _elite_kills: int = 0
var _boss_kills: int = 0
var _rare_drops: int = 0
## 局内技能栏（步骤 6 · SkillBarUI，含键位角标 + 冷却遮罩）
var _skill_bar: SkillBarUI = null
## 拾取提示流（步骤 6 · 右上角逐条）
var _pickup_toasts: PickupToastHUD = null

## 8C BOSS 觉醒卡：BOSS 远端沉睡，玩家接近 AWAKEN_TRIGGER_DIST 触发觉醒立绘卡，
## 卡结束后解除冻结正式开战（DNF 觉醒立绘风格，步骤 8C）。
const AWAKEN_TRIGGER_DIST: float = 200.0
var _pending_boss: EnemyBase = null
var _boss_awakened: bool = false
var _awaken_card: BossAwakenCard = null

## 目标
##
## `_objective_kind` 是**运行时**目标类型，初值等于 `_level_def.objective_type`。
## 单独存一份的理由：数据写了但运行时无法完成的目标（例如收集物一个都摆不下）需要能
## **真的降级**成 clear_all —— 直接改 `_level_def` 会污染共享的配置对象（ConfigLoader 缓存）。
var _objective_kind: int = LevelData.ObjectiveType.CLEAR_ALL
var _objective_target: int = 0
var _objective_current: int = 0
var _objective_desc: String = ""

## 已拾取的收集目标物数量（`collect` 目标专用）
var _collected: int = 0

var _built: bool = false
var _finished: bool = false
## 结算流程进行中（保底掉落 → 等拾取 → 落盘）。防止 `_on_unit_died` 重入重复结算。
var _settling: bool = false

## 保底装备生成后，留给玩家拾取的窗口（秒）。
## `LootDrop.LOOT_POP_DELAY` 是 0.25s，所以窗口必须显著大于它，否则保底掉落还没可拾取就结算了。
const GUARANTEE_PICKUP_GRACE: float = 0.6

# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	# 敌人死亡由 HealthComponent 广播 unit_died（玩家死亡也走同一个信号）
	EventBus.unit_died.connect(_on_unit_died)
	# 任务 11.9 埋点：`damage_dealt` 是**双向**总线（玩家打敌人 / 敌人打玩家都走它），
	# 交火判定只认玩家打出去的，所以处理器里要按「目标是不是玩家」过滤。
	EventBus.damage_dealt.connect(_on_damage_dealt)
	# 8C BOSS 阶段切换 → 顶部阶段横幅（觉醒卡只覆盖开战第 1 阶段）
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	_progression = RunProgression.new(_on_run_level_up)
	# 相机缩放：全项目唯一来源是 GameConstants.CAMERA_ZOOM_BASE，不在 .tscn 里硬编码
	_camera.zoom = GameConstants.CAMERA_ZOOM_BASE
	_banner.text = ""
	_result_panel.visible = false
	_apply_hud_skin()
	_build_buff_hud()
	_build_pickup_toasts()
	_fallback_build_if_standalone()


func _process(delta: float) -> void:
	if _player != null and is_instance_valid(_player):
		_camera.global_position = _player.global_position
	_check_boss_awaken()
	if not _finished:
		_buff_system.tick(delta)
	# 增益 HUD 的**轮询兜底**（事件驱动为主，见 `_build_buff_hud`）：低频比对签名，变化才改文本
	_buff_hud_poll += delta
	if _buff_hud_poll >= BUFF_HUD_POLL_INTERVAL:
		_buff_hud_poll = 0.0
		_refresh_buff_hud()


## ESC → 放弃本局（见类头第 5 条）。用 `_unhandled_input` 而非 `_input`：
## 让按钮 / 文本框等 Control 先消费输入，ESC 只在没人处理时才落到本关卡。
## 同时认 `ui_cancel` 动作与**裸 Escape 键**：内置 `ui_cancel` 默认绑 Escape，
## 但显式兜底可防将来 InputMap 被 `InputRemapper` 覆写后这条逃生口失效。
func _unhandled_input(event: InputEvent) -> void:
	var is_escape := event.is_action_pressed("ui_cancel")
	if not is_escape and event is InputEventKey:
		var k := event as InputEventKey
		is_escape = k.pressed and not k.echo and k.keycode == KEY_ESCAPE
	if is_escape:
		_on_escape_pressed()
		get_viewport().set_input_as_handled()


## ESC 的**入口逻辑**（与输入事件解耦，便于无头测试直接调用；见 `verify_esc.gd`）。
##
## 三种守卫，顺序不能乱：
##   ① 结算已发生 / 结算中（`_finished` / `_settling`）→ 不弹确认。
##      本局已结束，唯一出路是结算面板上的按钮（返回大厅 / 再来一局）；再弹「放弃本局」是噪音。
##   ② 三选一面板显示中（`_choice_panel.visible`）→ 吞掉 ESC，**不放弃、也不替玩家选**。
##      理由：三选一是**带收益的强制选择**，没有「取消」语义 —— 关掉面板 = 玩家白丢一次
##      升级收益；替玩家选一张 = 更糟。玩家先选一张卡再按 ESC 即可放弃，**不存在死路**。
##      （此行为 GDD 未规定，已在交付报告列为待裁定项，非静默决定。）
##   ③ 确认弹窗已弹出 → ESC 视为「取消」（等同点「继续」），避免误触二次确认。
func _on_escape_pressed() -> void:
	if _finished or _settling:
		return
	if _choice_panel != null and is_instance_valid(_choice_panel) and _choice_panel.visible:
		return
	if _abandon_confirm != null and is_instance_valid(_abandon_confirm):
		_dismiss_abandon_confirm()
		return
	_show_abandon_confirm()


## 弹出「放弃本局？」二次确认。
## 面板尺寸 / 文案只为可读性，**玩家可感知的契约是**：确认 → `_finish_run(false)`（落盘）。
func _show_abandon_confirm() -> void:
	if _abandon_confirm != null and is_instance_valid(_abandon_confirm):
		return
	var confirm := Control.new()
	confirm.name = "AbandonConfirm"
	confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 吃掉鼠标事件：防止透过暗幕误点到底下的 HUD / 世界
	confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	$HUD.add_child(confirm)
	_abandon_confirm = confirm

	var dim := ColorRect.new()
	# 与 ChoicePanel 复用同一遮罩常量（team-lead 裁定 1 · 阶段 11 收尾）
	# `UI_CHOICE_MASK = 0B0D10` + `UI_CHOICE_MASK_ALPHA = 0.55` ⇒ 两处遮罩同色同 alpha
	dim.color = GameConstants.UI_CHOICE_MASK
	dim.color.a = GameConstants.UI_CHOICE_MASK_ALPHA
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm.add_child(center)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(360.0, 0.0)
	center.add_child(box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)

	var title := Label.new()
	title.name = "Title"
	title.text = "放弃本局？"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)

	var hint := Label.new()
	hint.name = "Hint"
	# 这句不是空话：`_persist()` 确实会把 `_player.inventory` 落盘（见 `_finish_run` → `_persist`）
	hint.text = "将按「战斗失败」结算本局。已入包装备会存入存档，不会丢失。"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(320.0, 0.0)
	vb.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)

	var cancel_btn := Button.new()
	cancel_btn.name = "CancelButton"
	cancel_btn.text = "继续"
	row.add_child(cancel_btn)

	var ok_btn := Button.new()
	ok_btn.name = "ConfirmButton"
	ok_btn.text = "确认放弃"
	row.add_child(ok_btn)

	cancel_btn.pressed.connect(_dismiss_abandon_confirm)
	ok_btn.pressed.connect(_on_abandon_confirmed)


## 收起确认弹窗（点「继续」/ 再按一次 ESC / 放弃前统一走这里）
func _dismiss_abandon_confirm() -> void:
	if _abandon_confirm != null and is_instance_valid(_abandon_confirm):
		_abandon_confirm.queue_free()
	_abandon_confirm = null


## 确认放弃本局。
## ⚠️ 走**与玩家死亡完全相同**的失败结算分支 `_finish_run(false, "abandoned")` ——
##    该分支内部会调用 `_persist(res)`，把本局已入包的装备写进存档。
##    绝**不能**改成直接 `SceneManager.change_to_hub()`：那会绕过 `_persist()`，
##    已入包装备静默丢失（这正是本逃生口要修复的问题，别把它重新引入）。
func _on_abandon_confirmed() -> void:
	_dismiss_abandon_confirm()
	_finish_run(false, "abandoned")



## 不经 SceneManager 直接运行本场景时的兜底：等 3 帧（`SceneManager` 是在
## `change_scene_to_packed` 后等 2 个 process_frame 才递载荷，见 scene_manager.gd:200-205），
## 仍无 level_id 说明确实没人给载荷 → 用默认关。
func _fallback_build_if_standalone() -> void:
	for _i in 3:
		await get_tree().process_frame
	if level_id.is_empty():
		push_warning("[Level] 未收到 SceneManager 载荷（直接运行本场景？），"
			+ "退回调试关 %s" % DEFAULT_LEVEL_ID)
		level_id = DEFAULT_LEVEL_ID
		_build()


## SceneManager 的载荷交付入口（回调式，**没有** get_payload()）
func on_scene_entered(payload: Dictionary) -> void:
	level_id = str(payload.get("level_id", DEFAULT_LEVEL_ID))
	difficulty_tier = int(payload.get("difficulty_tier", GameConstants.DifficultyTier.NM1))
	_build()


# =============================================================================
# 构建
# =============================================================================

func _build() -> void:
	if _built:
		return
	_built = true

	_level_def = ConfigLoader.get_level(level_id)
	if _level_def == null:
		push_error("[Level] 关卡 '%s' 未在数据表中定义，无法生成" % level_id)
		_set_banner("关卡数据缺失：%s" % level_id)
		return

	# 1) 生成布局。数据里显式给了 seed 才固定种子（可复现），否则每次不同。
	var layout_seed := int(_level_def.layout.get("seed", 0))
	if layout_seed != 0:
		_rng.seed = layout_seed
	_layout = LevelGenerator.generate(_level_def, _rng)
	# 生物群系瓦片渲染：先定 biome（章节 → 森林/火山/霜渊），再灌 layout。
	# 不设 biome 时 LevelView 退回纯色分支（预览工具 / verify 行为不变）。
	_view.set_biome(TileAtlas.biome_for_level(_level_def), _level_def.tileset_path)
	_view.set_layout(_layout)
	_build_collision()
	# 相机限制在地图内：否则玩家靠近地图边缘时，屏幕会露出地图外的**纯黑 void**。
	# 窗口化实测发现（上半屏全黑）—— **这类问题无头测试永远看不见**：108 项自检 +
	# 36 个 verify 全绿，但没有任何一条路径渲染过一帧。
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(_layout.get("width", 0)) * TILE_PX
	_camera.limit_bottom = int(_layout.get("height", 0)) * TILE_PX

	# 2) 玩家
	var spawn_cell: Vector2i = _layout.get("player_spawn", Vector2i(1, 1))
	_player = PLAYER_SCENE.instantiate() as PlayerController
	_actors.add_child(_player)
	_player.global_position = _cell_to_world(spawn_cell)
	_apply_account_stats()
	_hp_bar.target = _player
	_mp_bar.target = _player
	_camera.global_position = _player.global_position

	# 3) 敌人
	_spawn_monsters()

	# 4) 目标
	_setup_objective()
	# 4b) 收集目标物（`collect` 专用；摆不出来时会把自己降级成 clear_all 并吵一声）
	_spawn_collectibles()

	EventBus.level_started.emit(level_id, difficulty_tier)
	# 5) 任务 11.9 埋点：开一局。**必须在全部生成之后** —— 要拿最终的敌人数
	#    （`AoE(密度)` 曲线的密度轴就是它）。纯观测，不参与任何判定。
	CombatMetrics.begin_run(level_id, difficulty_tier,
		int(_level_def.total_monster_budget), _alive.size())
	_refresh_objective()
	_refresh_level_banner()
	_build_difficulty_stars()
	_build_skill_bar()
	_build_quick_slot()
	print("[Level] 进入「%s」Lv.%d · 难度 %d · 敌人 %d（精英 %d / BOSS %d）· 目标：%s"
		% [_level_def.display_name, _level_def.level, difficulty_tier,
			_alive.size(), _elite_total, _boss_total, _objective_desc])


## 账号属性 + **局内增益** → 玩家。
##
## 【2026-09-18 修复 · D1】把 `StatCalculator` 的**完整平铺总属性**注入 `PlayerController`
## （`apply_combat_stats`），**不再只写 `max_hp`**。此前只有生命上限接线，导致
## 攻击/暴击/暴伤/攻速/护甲/抗性 等 **13/15 个三选一选项玩家零感知** —— 这是「第 10 个
## 生成了但没人消费」。口径裁定：`StatCalculator` 是唯一真相源，PlayerController 消费平铺
## 总属性、不再自乘裸装基线（避免与 StatCalculator 已含的裸装成长双重计入）。
##
## `refill_hp`：进关时 true（满血开局）；**升级选完增益后必须传 false** ——
## 否则「升一级 = 白送满血」，三选一就变成了回血道具，会破坏 GDD P3「风险与收益的抉择」。
func _apply_account_stats(refill_hp: bool = true) -> void:
	var data := SaveManager.current_data
	if data == null or _player == null or _player.health == null:
		return
	# 第三参数 = 局内增益（三选一 / 祭坛 / 连杀，由 `RunBuffSystem` 汇总）。
	# ⚠️ 此前传的是**空字典** ⇒ 面板接上后选了增益也不生效（第 9 个「生成没人消费」）。
	var stats := StatCalculator.calculate(data.account_level, data.equipped,
		_buff_system.to_calculator_buffs())
	# 【D1】注入完整属性 + 账号等级（等级供 `get_player_level()` / 越级惩罚 / 保底掉落使用）
	_player.apply_combat_stats(stats, data.account_level)
	var max_hp := float(stats.get("max_hp", 0.0))
	if max_hp > 0.0:
		_player.health.max_hp_override = max_hp
		if refill_hp:
			_player.health.current_hp = max_hp
		else:
			# 保留当前血量，只把超出新上限的部分削掉（升级加血上限不自动补满）
			_player.health.current_hp = minf(_player.health.current_hp, max_hp)


func _spawn_monsters() -> void:
	var entries: Array = _level_def.monster_entries

	# --- BOSS 身份解析 ---
	# 两个来源：
	#   ① `LevelData.boss_id` —— **权威**来源；`LevelGenerator.boss_spawn` 会按它把锚点
	#      摆在地图**远端**（BOSS 房设计）
	#   ② `monster_entries[].is_boss` —— 旧写法（把 BOSS 当普通条目列出来）
	# ⚠️ 本函数此前**只认 ②**，于是：
	#   - `ch2_l13` / `ch3_l20`（只写了 `boss_id`）的 BOSS **永不出现**，而目标是 kill_boss
	#     ⇒ 这两关**永远打不完**；
	#   - 生成器产出的 `boss_spawn` **从未被消费**（本项目第 8 个「生成了但没人用」的输出，
	#     此前只有 `tools/level_preview.gd` 用它画预览）。
	var boss_id := str(_level_def.boss_id)
	var boss_anchor: Vector2i = _layout.get("boss_spawn", Vector2i(-1, -1))
	## 走锚点生成（boss_id 有效 且 锚点有效）。否则退回「按条目归类」的老路径。
	var use_anchor := not boss_id.is_empty() and boss_anchor != Vector2i(-1, -1)

	var entry_boss_ids := {}
	for e in entries:
		if bool(e.get("is_boss", false)):
			entry_boss_ids[str(e.get("monster_id", ""))] = true

	# 1) 常规刷怪（生成器已按 count_min/max 与权重解析成具体坐标）
	#    走锚点生成时跳过 BOSS 条目，避免同一只 BOSS 被刷两次。
	for s in _layout.get("monster_spawns", []):
		var mid := str(s.get("monster_id", ""))
		if use_anchor and mid == boss_id:
			continue
		var cell: Vector2i = s.get("cell", Vector2i.ZERO)
		var e := _spawn_enemy(mid, cell)
		if e == null:
			continue
		if entry_boss_ids.has(mid) or mid == boss_id:
			_boss_total += 1
			_mark_kind(e, "boss")
			_freeze_boss_until_awaken(e)

	# 1b) BOSS 锚点：按 `boss_id` 刷在地图远端（BOSS 房）
	if use_anchor:
		var be := _spawn_enemy(boss_id, boss_anchor)
		if be != null:
			_boss_total += 1
			_mark_kind(be, "boss")
			_freeze_boss_until_awaken(be)

	# 2) 精英：**三条**通路都要认，否则「精英关」的计数与实际场上的精英对不上。
	#    ① 固定锚点 —— LevelData.elite_count（生成器摆在地图远端）
	#    ② 随机替换 —— LevelData.elite_ratio（GDD：精英提供掉落与事件）
	#    ③ 数据层精英档 —— monster_entries 里 `tier == ELITE` 的怪（已在 `_spawn_enemy()`
	#       里打了标记）。**这一条以前是漏的**，见 `_is_elite()` 的说明。
	var elite_anchors: Array = _layout.get("elite_spawns", [])
	var pool := _weighted_monster_ids(entries)
	for cell_v in elite_anchors:
		var cell: Vector2i = cell_v
		var mid := _pick_weighted(pool)
		if mid.is_empty():
			break
		_spawn_enemy(mid, cell, true)

	var ratio := float(_level_def.elite_ratio) if _level_def.elite_spawn_enabled else 0.0
	if ratio > 0.0:
		for e in _alive:
			if e.get_meta("lv_kind", "") != "":
				continue   # 已是 BOSS / 锚点精英 / 数据层精英档
			if _rng.randf() < ratio:
				e.affixes = AffixController.roll_affixes(_rng, 1)
				_mark_kind(e, "elite")

	# 2b) `_elite_total` 按**实际生成的精英**重算，而不是沿途 `+= 1`：
	#     三条来源任何一条漏加，下面第 3 步的可达性自检就会说谎（报「只生成出 N 个」
	#     而场上其实更多），而这个自检正是用来发现软锁的。
	_elite_total = 0
	for e in _alive:
		if _is_elite(e):
			_elite_total += 1

	# 3) 目标可达性自检：数据缺字段会让「精英关 / BOSS 关」变成不可能完成，
	#    这种情况必须吵，不能等玩家打光了才发现不结算。
	match _level_def.objective_type:
		LevelData.ObjectiveType.KILL_ELITE:
			if _elite_total < int(_level_def.objective_value):
				push_warning("[Level] %s 目标需击杀 %d 个精英，但只生成出 %d 个"
					% [level_id, int(_level_def.objective_value), _elite_total])
		LevelData.ObjectiveType.KILL_BOSS:
			if _boss_total <= 0:
				push_warning("[Level] %s 目标是击杀 BOSS，但 monster_entries 里没有任何 "
					% level_id + "is_boss=true 的条目（且 LevelGenerator 只认 boss_id 字段）")


func _spawn_enemy(monster_id: String, cell: Vector2i, as_elite: bool = false) -> EnemyBase:
	var mdef := ConfigLoader.get_monster(monster_id)
	if monster_id.is_empty() or mdef == null:
		push_warning("[Level] 跳过未知怪物 id：'%s'" % monster_id)
		return null
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	# ⚠️ 顺序不能反：`EnemyBase._ready()` 会读 monster_id / level / difficulty_tier / affixes
	#    去建属性、算词缀乘区。先 add_child 再赋值 = 属性按默认值建，且不报错。
	e.monster_id = monster_id
	e.level = _level_def.level
	e.difficulty_tier = difficulty_tier
	if as_elite:
		e.affixes = AffixController.roll_affixes(_rng, 1)
		_mark_kind(e, "elite")
	elif int(mdef.tier) == int(MonsterData.Tier.ELITE):
		# 数据层本身就是精英档的怪（屠夫 / 霜缚幽魂 / 焚火邪教徒 / 冰霜幽魂）。
		# 它们**不额外掷词缀**（强度来自 tier 的 4.5× HP 倍率，不是词缀），
		# 但必须打上同一个 `lv_kind` 标记 —— 口径见 `_is_elite()`。
		_mark_kind(e, "elite")
	_actors.add_child(e)
	e.global_position = _cell_to_world(cell)
	_alive.append(e)
	# 任务 11.9 埋点：BOSS 召唤也会走这里 ⇒ 存活数会**涨**，不只是跌。
	CombatMetrics.set_alive_count(_alive.size())
	return e


## 给敌人打「本场景归类」标记（不占用 EnemyBase 的字段，避免与战斗逻辑耦合）
func _mark_kind(e: EnemyBase, kind: String) -> void:
	e.set_meta("lv_kind", kind)


## 「这只怪算不算精英」的**唯一**判定口径。
##
## 为什么需要它：以前代码里有两套口径 ——
##   · 击杀计数 `_on_unit_died()` 看 `lv_kind == "elite"`（只有生成器锚点 / `elite_ratio`
##     随机提升才会打这个标记）；
##   · 掉落质量统计 `_count_rare_drops()` 看 `data.tier`。
## 于是**数据层就是精英档**的怪（`brute_butcher` 屠夫 / `wraith_frost` 霜缚幽魂 /
## `pyromancer_cultist` / `ice_wraith`）被杀时不算精英击杀 —— 玩家看着一个 4.5 倍血、
## 掉 60% 装备的屠夫倒下，任务计数器纹丝不动。实测（2026-09-20 探针）：
##   · ch1_l03：场上 2 只精英档怪没被标记（任务目标 kill_elite×2）
##   · ch2_l10：12 只精英档怪里 8 只没被标记（目标 ×4）
##   · ch2_l13：10 只里 9 只没被标记
## 现在统一成「被标记 **或** 数据层档位是精英」，并让 `_spawn_enemy()` 在生成时就
## 给精英档怪补上标记，这样 `_elite_total`（可达性自检用的数）与实际场上精英一致。
##
## ⚠️ 注意：被 `elite_ratio` 随机提升的怪**不会**变成精英档（`data.tier` 仍是 NORMAL，
##    所以没有 4.5× HP），它们只多一条词缀。这是既有的数值设计，本次不改；
##    但「谁算精英」的口径必须只有一套。
func _is_elite(e: EnemyBase) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if str(e.get_meta("lv_kind", "")) == "elite":
		return true
	return e.data != null and int(e.data.tier) == int(MonsterData.Tier.ELITE)


func _weighted_monster_ids(entries: Array) -> Array:
	var pool: Array = []
	for e in entries:
		var mid := str(e.get("monster_id", ""))
		if mid.is_empty():
			continue
		# BOSS 不参与精英替换（否则「BOSS 关」会多出精英怪干扰目标判定）
		if bool(e.get("is_boss", false)):
			continue
		pool.append({"id": mid, "w": maxf(float(e.get("weight", 1.0)), 0.001)})
	return pool


func _pick_weighted(pool: Array) -> String:
	if pool.is_empty():
		return ""
	var total := 0.0
	for p in pool:
		total += float(p["w"])
	var r := _rng.randf() * total
	for p in pool:
		r -= float(p["w"])
		if r <= 0.0:
			return str(p["id"])
	return str(pool[pool.size() - 1]["id"])


# =============================================================================
# 8C BOSS 觉醒卡（沉睡 → 接近 → 觉醒立绘卡 → 开战）
# =============================================================================

## BOSS 沉睡：暂停 AI（_physics_process），保留待机动画渲染
func _freeze_boss_until_awaken(boss: EnemyBase) -> void:
	boss.set_physics_process(false)
	if _pending_boss == null:
		_pending_boss = boss


## 每帧检查：玩家进入 BOSS 触发圈 → 觉醒（只触发一次）
func _check_boss_awaken() -> void:
	if _boss_awakened or _pending_boss == null or not is_instance_valid(_pending_boss):
		return
	if _player == null or not is_instance_valid(_player):
		return
	if _player.global_position.distance_to(_pending_boss.global_position) > AWAKEN_TRIGGER_DIST:
		return
	_trigger_boss_awaken()


## 弹觉醒立绘卡 + 震屏；卡片结束回调里解除冻结
func _trigger_boss_awaken() -> void:
	_boss_awakened = true
	var boss := _pending_boss
	var boss_id := ""
	var display_name := "BOSS"
	if boss.data != null:
		boss_id = str(boss.data.id)
		display_name = str(boss.data.display_name)
	var phase_count := 1
	var cfg: Dictionary = boss.boss_config
	if not cfg.is_empty():
		phase_count = maxi(int(cfg.get("phase_count", 1)), 1)
	_awaken_card = BossAwakenCard.awaken(self, boss_id, display_name,
		phase_count, _on_boss_awaken_finished)
	_shake_camera()


func _on_boss_awaken_finished() -> void:
	_awaken_card = null
	if _pending_boss != null and is_instance_valid(_pending_boss):
		_pending_boss.set_physics_process(true)
		_pending_boss = null
	# 觉醒吼（低吼扫频）：开战瞬间
	AudioManager.play("boss_phase")


## 相机震屏（觉醒卡出现瞬间的冲击感，0.4s 衰减归零）
func _shake_camera() -> void:
	var t := create_tween()
	for i in 8:
		var amp := 5.0 * (1.0 - float(i) / 8.0)
		t.tween_callback(func() -> void:
			_camera.offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp)))
		t.tween_interval(0.05)
	t.tween_callback(func() -> void: _camera.offset = Vector2.ZERO)


## BOSS 阶段切换横幅（2/3/4 阶段：顶部金色横幅 1.6s 淡入淡出）
func _on_boss_phase_changed(_enemy: Node, phase: int, _skills: Array) -> void:
	if _finished:
		return
	var layer := CanvasLayer.new()
	layer.name = "PhaseBanner"
	add_child(layer)
	var bar := ColorRect.new()
	bar.color = Color(0.03, 0.04, 0.06, 0.0)
	bar.position = Vector2(0.0, 20.0)
	bar.size = Vector2(640.0, 44.0)
	layer.add_child(bar)
	var lab := Label.new()
	lab.text = "第 %s 階段 · 覺醒之力" % BossPhaseController.PHASE_NAMES[
		clampi(phase - 1, 0, BossPhaseController.PHASE_NAMES.size() - 1)]
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 16)
	lab.add_theme_color_override("font_color", GameConstants.COLOR_ACCENT_GOLD)
	lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	lab.modulate = Color(1.0, 1.0, 1.0, 0.0)
	bar.add_child(lab)
	var tw := create_tween()
	tw.tween_property(bar, "color:a", 0.55, 0.15)
	tw.parallel().tween_property(lab, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.1)
	tw.tween_property(bar, "color:a", 0.0, 0.35)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, 0.35)
	tw.tween_callback(layer.queue_free)


func _cell_to_world(cell: Vector2i) -> Vector2:
	# 取格中心：与 LevelView 画格 + 出生点金块标记的口径一致
	return Vector2(cell.x * TILE_PX + TILE_PX / 2.0, cell.y * TILE_PX + TILE_PX / 2.0)


# =============================================================================
# 目标
# =============================================================================

func _setup_objective() -> void:
	_objective_kind = _level_def.objective_type
	match _objective_kind:
		LevelData.ObjectiveType.KILL_BOSS:
			_objective_target = maxi(_boss_total, 1)
			_objective_desc = "击杀 BOSS"
		LevelData.ObjectiveType.KILL_ELITE:
			_objective_target = int(_level_def.objective_value)
			_objective_desc = "击杀精英"
		LevelData.ObjectiveType.COLLECT:
			_objective_target = maxi(int(_level_def.objective_value), 1)
			_objective_desc = "收集目标物"
		LevelData.ObjectiveType.CLEAR_ALL:
			_objective_target = _alive.size()
			_objective_desc = "清空全部敌人"
		_:
			# 未实现的目标类型：明确退化 + 吵一声，不假装完成
			push_warning("[Level] 目标类型 '%s' 未实现，本局退化为「清空全部敌人」"
				% _level_def.get_objective_name())
			_degrade_to_clear_all("%s（未实现，退化为清空）" % _level_def.get_objective_name())


## 降级为「清空全部敌人」。
## ⚠️ 是**真的降级**（改 `_objective_kind`），不是只改文案 —— 只改文案的话
##    `_objective_done()` 仍按原类型判定，玩家打光了也不会结算。
func _degrade_to_clear_all(desc: String) -> void:
	_objective_kind = LevelData.ObjectiveType.CLEAR_ALL
	_objective_target = _alive.size()
	_objective_desc = desc


func _refresh_objective() -> void:
	_objective_label.text = "%s：%d / %d" % [_objective_desc, _objective_current, _objective_target]
	EventBus.level_objective_updated.emit(
		float(_objective_current), float(_objective_target), _objective_desc)


func _objective_done() -> bool:
	match _objective_kind:
		LevelData.ObjectiveType.KILL_BOSS:
			return _boss_kills >= _objective_target
		LevelData.ObjectiveType.KILL_ELITE:
			return _elite_kills >= _objective_target
		LevelData.ObjectiveType.COLLECT:
			return _collected >= _objective_target
		_:
			return _alive.is_empty()


func _sync_objective_counter() -> void:
	match _objective_kind:
		LevelData.ObjectiveType.KILL_BOSS:
			_objective_current = _boss_kills
		LevelData.ObjectiveType.KILL_ELITE:
			_objective_current = _elite_kills
		LevelData.ObjectiveType.COLLECT:
			_objective_current = _collected
		_:
			_objective_current = _kills
	_refresh_objective()


## 摆放收集目标物（`collect` 目标）：数量恒等于 `objective_value`，摆在
## `LevelGenerator` 产出的 `pickup_spawns` 上。
##
## 为什么这么做，而不是「捡任意 N 件掉落」：
##   - **确定性**：与怪物掉率无关。靠掉落凑数会让「收集 3 个」变成概率目标
##     （普通怪掉率 8%，一整关可能一件都不出），端到端验收必然 flaky。
##   - **激活既有死输出**：`pickup_spawns` 由 `level_generator.gd` 生成（2–3 个地面格），
##     此前**全项目从未被消费**。
##   - **不污染经济**：目标物是 `material` 类型，不进 `_player.inventory`（装备背包），
##     也不影响 `_spawn_guaranteed_drops()` 的「已入包件数」判定。
func _spawn_collectibles() -> void:
	if _objective_kind != LevelData.ObjectiveType.COLLECT:
		return
	var need := maxi(int(_level_def.objective_value), 1)
	var cells: Array = []
	for c in _layout.get("pickup_spawns", []):
		cells.append(c)
	# 生成器只给 2–3 个点，目标数可能更多 —— 从地面格补位。
	# 用 `_rng` 而非全局 rand：`layout_seed` 固定时结果可复现，测试才稳定。
	if cells.size() < need:
		var ground: Array = []
		var layout_cells: Dictionary = _layout.get("cells", {})
		for c in layout_cells.keys():
			if int(layout_cells[c]) == LevelGenerator.TILE_GROUND:
				ground.append(c)
		for _k in need * 4:
			if cells.size() >= need or ground.is_empty():
				break
			var c: Vector2i = ground[_rng.randi_range(0, ground.size() - 1)]
			if not cells.has(c):
				cells.append(c)
	if cells.is_empty():
		# 摆不出来 = 目标不可完成。**不静默假装**：降级成清空并吵一声。
		push_warning("[Level] %s 目标为收集，但布局里没有任何地面格可摆放目标物，降级为清空全部"
			% level_id)
		_degrade_to_clear_all("收集物摆放失败（退化为清空）")
		return
	for i in need:
		var cell: Vector2i = cells[i % cells.size()]
		var drop := LOOT_SCENE.instantiate() as LootDrop
		drop.setup({
			"type": "material", "amount": 1, "item_id": "",
			"rarity": -1, "item_level": 1, "collectible": true,
		})
		_actors.add_child(drop)
		drop.global_position = _cell_to_world(cell)
		drop.picked_up.connect(_on_collectible_picked_up)
	print("[Level] 收集目标物已摆放 %d 个（目标 %d）" % [need, _objective_target])


## 收集物被拾取 → 计数 → 可能达成目标。
## ⚠️ 目标达成必须同时从**击杀**和**拾取**两条路检查。只挂在 `_on_unit_died` 里的话，
##    「收集」类目标达成后不会触发结算（玩家会站着干等，看起来像卡死）。
func _on_collectible_picked_up(_entry: Dictionary) -> void:
	if _finished:
		return
	_collected += 1
	_sync_objective_counter()
	_check_objective_and_settle()


# =============================================================================
# 战斗回馈
# =============================================================================

func _on_unit_died(unit: Node, killer: Node) -> void:
	if _finished:
		return
	# 玩家死亡 → 失败结算
	if unit == _player:
		_finish_run(false)
		return
	var e := unit as EnemyBase
	if e == null or not _alive.has(e):
		return

	_alive.erase(e)
	_kills += 1

	# 击杀分类的**唯一口径**：三个计数器与 11.9 埋点都读它，不另立第二套标准
	var kind := str(e.get_meta("lv_kind", ""))
	var mkind := "normal"
	if kind == "boss":
		_boss_kills += 1
		mkind = "boss"
	elif _is_elite(e):
		_elite_kills += 1
		mkind = "elite"
	# 任务 11.9 埋点（纯观测）
	CombatMetrics.note_kill(mkind)
	CombatMetrics.set_alive_count(_alive.size())

	# 掉落质量统计（结算评分用）：稀有度 ≥ 紫
	_rare_drops += _count_rare_drops(e)

	# 局内成长（GDD 0.4 节 4.1）：只有玩家击杀才给经验
	if killer == _player and e.data != null:
		_progression.add_xp(e.data.base_xp)
		_buff_system.on_kill()

	_sync_objective_counter()
	_check_objective_and_settle()


## 任务 11.9 埋点：`damage_dealt` 是**双向**总线 —— 玩家打敌人（`skill_controller.gd:172`）
## 与敌人打玩家（`enemy_base.gd` 三处）走的是同一条信号。交火（engagement）判定只认
## **玩家打出去的**伤害，所以按「目标是不是玩家」过滤，而不是按发射方。
func _on_damage_dealt(target: Node, _amount: float, _is_crit: bool, _element: String) -> void:
	if target == _player:
		return
	CombatMetrics.note_outgoing_damage()


## 目标达成的**唯一**结算入口 —— 击杀与拾取两条路径都走它。
##
## 不抽出来的话：① 「收集」类目标达成后不会结算（`_on_unit_died` 不会被触发）；
## ② 以后每加一种目标类型都要在 N 个调用点补一遍判定。
func _check_objective_and_settle() -> void:
	if _finished or _settling or not _objective_done():
		return
	_settling = true
	# 目标达成 → 先补保底掉落，给玩家一个拾取窗口，再结算。
	# 不补的话「必掉装备」这条数据形同虚设：普通怪 8% 触发率下一整关可能一件装备都不出，
	# 而 GDD 0.2 节「变强可感知」要求每关至少能拿到装备。
	_spawn_guaranteed_drops()
	await get_tree().create_timer(GUARANTEE_PICKUP_GRACE).timeout
	_finish_run(true)


## 统计该怪本次掉落的稀有件数。
## ⚠️ 掉落是 `EnemyBase._drop_loot()` 内部 roll 的，本场景拿不到那次 roll 的结果，
## 所以这里**按怪物档位给期望值**（BOSS 必掉 2–4 件、精英 60%、普通 8%），
## 用于结算评分的量级估计，不等于实际入包数。真实入包数以 `_player.inventory` 为准。
func _count_rare_drops(e: EnemyBase) -> int:
	if e.data == null:
		return 0
	match e.data.tier:
		MonsterData.Tier.BOSS:
			return 3
		MonsterData.Tier.ELITE:
			return 1
		_:
			return 0


## 保底掉落：`LevelData.guaranteed_equipment_drops`（必掉的装备件数）。
##
## 判定口径是「**已入包**的装备件数」而不是「地面上出现过的装备」：
## 玩家可能漏捡，而保底的意义是「玩家一定拿得到」，所以按入包数补足。
## 补出来的装备生成在**玩家脚下**（距离 0），`LootDrop` 的自动拾取会在
## `LOOT_POP_DELAY` 后收走，随后 `GUARANTEE_PICKUP_GRACE` 的窗口结束才结算。
func _spawn_guaranteed_drops() -> void:
	if _player == null or _level_def == null:
		return
	var need := _level_def.guaranteed_equipment_drops - _player.inventory.size()
	if need <= 0:
		return
	var table_id := str(_level_def.loot_table_id)
	var made := 0
	for _i in need:
		var entry := LootRoller.roll_guaranteed_equipment(
			_level_def.level, difficulty_tier, _player.get_player_level(), table_id,
			# 局内「幸运」稀有度权重乘区（默认 0 = 不变）
			_player.get_combat_stat("magic_find"))
		if entry.is_empty() or str(entry.get("type", "")) != "equipment":
			continue
		var drop := LOOT_SCENE.instantiate() as LootDrop
		drop.setup(entry)
		_actors.add_child(drop)
		drop.global_position = _player.global_position
		made += 1
	print("[Level] 保底掉落 %d 件（已入包 %d / 要求 %d）"
		% [made, _player.inventory.size(), _level_def.guaranteed_equipment_drops])


func _on_run_level_up(new_run_level: int) -> void:
	# ⚠️ 选项来源必须是 `RunePool.get_choices`（三选一池，含 cat/name/desc/stat_key/value/cap），
	#    **不是** `RunBuffSystem.SHINE_OPTIONS()` —— 后者是**祭坛**选项，只有 id/name/desc/pct。
	#    2026-09-18 修：此前用错来源 ⇒ `ChoicePanel._build()` 访问 `opt["cat"]` 直接
	#    SCRIPT ERROR，面板一张卡都画不出来。之前只 `print` 不弹面板，所以这个接口错配
	#    一直没暴露（**面板接线一接上就炸**，这正是「先证伪再转正」的价值）。
	#    `picked_ids`：**传空数组**（2026-09-18 裁定 D2）。GDD 0.4 §4.1「3 个选项从池中
	#    **不重复抽取**」指的是**同一次抽出的 3 张之间**不重复（`get_choices` 内部靠
	#    「抽一个就从池里 `remove_at`」天然保证），**不是**「本局内同一 id 不得再出现」。
	#    ⚠️ 此前传 `_buff_system.buffs.keys()`（= 全部历史已选 id）⇒ 同一 id 永不能再抽到
	#    ⇒ `RunBuffSystem.apply_option` 的**叠层机制在实战中不可达**，GDD 0.4 §4.4
	#    「达上限后该类选项自动从池中移除」成了死文（永远到不了上限）。
	#    现改为跨级可重复抽取，上限由 `stats_pct` 达 cap 后移除 + `to_calculator_buffs` 钳制共同控制。
	#    `stats_pct` 传累计值（某属性类达上限后自动从池中移除，避免「无意义选项」）。
	var choices := RunePool.get_choices(3, [], _run_stats_pct(), _choice_rng)
	EventBus.run_level_up.emit(new_run_level, choices)
	if choices.is_empty():
		# ⚠️ 本分支在 GDD 0.4 §4.4 下**设计上不可达**：15 个选项里 11 个 `cap=0`
		#    （功能性 / 其它属性）永不被移出池 ⇒ 池永不为空。**保留作纯防御**（便宜的保险，
		#    §4.10 铁律：分支要写明命中条件）。**可命中条件**：将来若给所有 `stat_key` 都补了 cap
		#    且同时顶满，池才会空。届时本告警即为第一现场证据。
		push_warning("[Level] 局内升到 %d 级，但三选一候选池为空 —— 面板无法弹出" % new_run_level)
		return
	print("[Level] 局内升到 %d 级，弹出三选一（%d 个候选）" % [new_run_level, choices.size()])
	_show_choice_panel(choices)


## 局内各属性类的**累计百分比**（供 `RunePool.get_choices` 做上限判定）。
## 口径与 `RunBuffSystem.to_calculator_buffs()` 一致：单层 `value` × 层数。
func _run_stats_pct() -> Dictionary:
	var out := {}
	for option_id in _buff_system.buffs:
		var opt := RunePool.get_option(option_id)
		if opt.is_empty():
			continue
		var key := str(opt["stat_key"])
		out[key] = float(out.get(key, 0.0)) + float(opt["value"]) * float(_buff_system.buffs[option_id])
	return out


## 弹出三选一面板（GDD 0.4 节 4.1：每升 1 级从池中不重复抽取 3 个选项）。
## 同一时刻只保留一个面板：一次击杀跨两级时信号会连发，叠层会让玩家看到两套卡片。
func _show_choice_panel(choices: Array[Dictionary]) -> void:
	if _choice_panel != null and is_instance_valid(_choice_panel):
		_choice_panel.queue_free()
	_choice_panel = ChoicePanel.new()
	_choice_panel.choice_made.connect(_on_choice_made)
	$HUD.add_child(_choice_panel)
	# ⚠️ 必须在 add_child **之后**设 preset：`ChoicePanel._build()` 用 `size` 算卡片位置，
	#    面板尺寸为 0 时三张卡会全部叠在原点。
	_choice_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 再延一帧：`size` 要等本轮布局算完才可靠，否则 `_build()` 读到的仍是 0
	_choice_panel.show_choices.call_deferred(choices, _buff_system)


## 三选一选定 → 增益已在 `ChoicePanel._on_pick()` 里写进 `_buff_system`，这里只负责**让它生效**。
## 不重算属性的话，「选了 +12% 攻击」就只存在于字典里，玩家毫无感觉 ——
## 这正是「局内成长」此前在实战中完全不可用的原因（面板没接 + buffs 没传进属性计算）。
func _on_choice_made(option_id: String) -> void:
	print("[Level] 三选一选定：%s（当前层数 %d）" % [option_id, _buff_system.get_stacks(option_id)])
	# 【原任务 D】选了增益 → 刷新局内增益 HUD（让「变强」对玩家可见）
	_refresh_buff_hud()
	# refill_hp = false：升级不该白送满血，见 `_apply_account_stats` 注释
	_apply_account_stats(false)


# =============================================================================
# HUD 皮膚（UI 素材接入 §5.4）
# =============================================================================

## 套用 HUD 皮膚：任務底板（`quest_panel_9slice` 9-slice）、任務標記（`quest_marker_24`）、
## 章節/關卡名橫幅（`quest_banner_256x48`）。
##
## ⚠️ **素材缺失安全降級**：`UISkin` 全部工廠在缺素材時回傳 `null` → 這裡就**不做任何覆蓋**。
##    `QuestPlate` 是 `Panel`，會自動沿用 `UITheme` 的 StyleBoxFlat 面板（近黑底 + 描邊）；
##    `QuestMarker` / `LevelBanner` 缺貼圖時隱藏，避免留空框。整包素材移走也不崩。
func _apply_hud_skin() -> void:
	var sb := UISkin.panel_stylebox()

	var plate := get_node_or_null("HUD/QuestPlate") as Panel
	if plate != null and sb != null:
		plate.add_theme_stylebox_override("panel", sb)

	# HP 外框板（規範 §2.2）：9-slice 內區 = `14171C` = 血條底槽色 ⇒ 接縫不可見，
	# 因此**不必改** `health_bar.gd`（它仍是純自繪）。
	var hp_frame := get_node_or_null("HUD/HpFrame") as Panel
	if hp_frame != null and sb != null:
		hp_frame.add_theme_stylebox_override("panel", sb)

	var marker := get_node_or_null("HUD/QuestMarker") as TextureRect
	if marker != null:
		var mtex := UISkin.texture("marker")
		marker.texture = mtex
		marker.visible = mtex != null

	var banner := get_node_or_null("HUD/LevelBanner") as TextureRect
	if banner != null:
		var btex := UISkin.texture("banner")
		banner.texture = btex
		banner.visible = btex != null


## 難度星級（規範 §2.1）：5 顆 `star_*_16`，亮燈數 = `difficulty_tier + 1`。
##
## ⚠️ `difficulty_tier` 的取值域是 **0..4**（`DifficultyTier.NM1 = 0` … `NM5 = 4`，
##    `DIFFICULTY_TIER_COUNT = 5`）—— **tier=0 就是「夢魘 I」，不存在 0 星檔**。
##    故亮燈數 = `clampi(tier, 0, 4) + 1` ⇒ NM1→1 / NM2→2 / … / NM5→5。
##    歷史缺陷：原式 `clampi(tier, 1, 5)` **上下限同時錯** —— 上限只到 4 ⇒ NM5 永遠只亮 4/5 顆；
##    下限把 tier 0 與 1 併成同一檔 ⇒ NM1 與 NM2 看起來完全一樣。
##    **不可**改成「`lit == 0` 時整排不建」：正解下 `lit` 恒 ≥ 1，且
##    `verify_ui_assets.gd` 斷言「難度星級 5 顆已建立」，整排隱藏會讓回歸直接變紅。
## 起點 (216, 80)，每顆 16×16 無間隙。素材缺失則整排不建（安全降級）。
func _build_difficulty_stars() -> void:
	var lit := clampi(difficulty_tier, 0, 4) + 1
	var made := 0
	for i in 5:
		var tex := UISkin.star_texture(i < lit)
		if tex == null:
			break
		var tr := TextureRect.new()
		tr.name = "DiffStar%d" % i
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.position = Vector2(216.0 + 16.0 * float(i), 80.0)
		tr.size = Vector2(16, 16)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$HUD.add_child(tr)
		made += 1
	if made > 0:
		print("[Level] 難度星級：%d 顆（亮 %d，tier %d）" % [made, lit, difficulty_tier])


# =============================================================================
# 技能欄（2026-09-21 用戶像素素材包接入）
# =============================================================================

## 技能欄原點（螢幕座標，px）。**右對齊**：3 槽 × 48 + 2 間隙 × 4 = 152，
## 右緣留 16px ⇒ x = 640 - 16 - 152 = 472；y = 360 - 16 - 48 = 296。
## 避讓：左下 `HUD/Banner`(16,328,336,352) 在 x≤336，本欄自 x=472 起 ⇒ 無重疊。
const SKILL_BAR_ORIGIN: Vector2 = Vector2(472.0, 296.0)
## 消耗品快捷栏原点（步骤 8A）：2 槽 × 48 + 1 间隙 × 4 = 100，
## 左对齐技能栏并留 4px ⇒ x = 472 - 4 - 100 = 368；y 与技能栏同行 296。
const QUICK_SLOT_ORIGIN: Vector2 = Vector2(368.0, 296.0)
## 槽邊長（px）。與 `skill_slot_48.png` / `skill_icon_*_48.png` 原生尺寸一致 ⇒ **1× 整數**。
const SKILL_SLOT_PX: float = 48.0
## 槽間距（px）。
const SKILL_SLOT_GAP: float = 4.0

## 技能 id → 圖標邏輯名。**以 `game/data/skills/skills.json` 的真實 id 為準，不要憑檔名猜**。
##
## 語義對齊（包只給了 4 張圖標，覆蓋 4 個系）：
##   `slash` 刀光系 / `fireburst` 火焰系 / `frostnova` 冰霜系 / `shadowdash` 衝刺系。
## ⚠️ 玩家**出戰**技能（`slot >= 1`）目前只有 3 個：裂斬 / 旋刃 / 突進 —— **全是物理系**，
##    所以 `skill_icon_fireburst` / `skill_icon_frostnova` 在本局**不會出現**
##    （火球術 / 冰霜新星在資料裡是 `slot = 0` = 技能庫，不佔出戰欄位）。
##    這是**內容缺口**（包的元素系圖標等元素系技能出戰），不是代碼缺陷 ——
##    映射表本身是完整的，一旦技能出戰就會自動顯示對應圖標。
const SKILL_ICON: Dictionary = GameConstants.SKILL_ICON

## 技能欄（步骤 6 重做）：`SkillBarUI` 3 槽（1/2/3 键位角标 + 冷却遮罩 + 图标）。
## **必須在 `_player` 建好之後呼叫** —— 故掛在 `_build()` 而非 `_ready()`。
func _build_skill_bar() -> void:
	var ctrl := _player.get_skill_controller() if _player != null else null
	var bar := SkillBarUI.new()
	bar.name = "SkillBar"
	bar.position = SKILL_BAR_ORIGIN
	bar.setup(ctrl)
	$HUD.add_child(bar)
	_skill_bar = bar
	print("[Level] 技能栏：SkillBarUI %d 槽（出战 %d）" % [SkillBarUI.SLOT_COUNT, bar.get_slot_count()])


## 消耗品快捷栏（步骤 8A · 药水）：Q=生命 / R=法力，图标+数量+冷却遮罩。
## 必须与 `_build_skill_bar` 一样在 `_player` 建好之后调用。
func _build_quick_slot() -> void:
	var slot := QuickSlotUI.new()
	slot.name = "QuickSlot"
	slot.position = QUICK_SLOT_ORIGIN
	slot.setup(_player)
	$HUD.add_child(slot)
	print("[Level] 消耗品快捷栏：QuickSlotUI %d 槽" % QuickSlotUI.SLOT_COUNT)


## 章節/關卡名橫幅文字（底板貼圖見 `_apply_hud_skin`）。`_build()` 取得關卡定義後呼叫。
## 拾取提示流（步骤 6）：右上角逐条，消费 `EventBus.loot_picked_up`。
## 位置：顶部横匾（192,8-448,56）下方右侧，避免与左栏任务板/血条重叠。
func _build_pickup_toasts() -> void:
	_pickup_toasts = PickupToastHUD.new()
	_pickup_toasts.name = "PickupToasts"
	_pickup_toasts.position = Vector2(444.0, 64.0)
	_pickup_toasts.size = Vector2(184.0, 0.0)
	_pickup_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_pickup_toasts)
	# 此前零消费者的信号（README 审计第 7 条）—— 拾取提示 HUD 是它的第一个消费者
	EventBus.loot_picked_up.connect(_on_loot_picked_up)


func _on_loot_picked_up(entry: Dictionary) -> void:
	if _pickup_toasts != null and is_instance_valid(_pickup_toasts):
		_pickup_toasts.spawn(entry)


func _refresh_level_banner() -> void:
	var lbl := get_node_or_null("HUD/LevelBannerText") as Label
	if lbl == null:
		return
	lbl.text = _level_def.display_name if _level_def != null else ""


# =============================================================================
# 局内增益 HUD（原任务 D）
# =============================================================================

## 建 HUD：一块底板（`BuffPlate`，修 L4 的可读性）+ 一个文本 Label，列出当前三选一叠层 + 连杀。
##
## 同时**消费 `EventBus.kill_streak_changed`** —— 该信号此前是零消费者（本项目
## 「生成了但没人消费」之一），连杀机制对玩家完全不可见。这里把它接上，HUD 随连杀刷新。
## （节点用代码建：`level.tscn` 不在本次文件独占范围。）
## 刷新策略（team-lead 裁定）：**事件驱动为主 + 轮询兜底**。
##   - 事件：`run_buff_selected`（三选一选定）/ `kill_streak_changed`（连杀）→ 立即刷新；
##   - 兜底：`_process` 每 `BUFF_HUD_POLL_INTERVAL` 秒比对一次签名——**防将来新增的增益来源
##     漏发事件时 HUD 永久不更新**（信号漏发 = HUD 失联，这正是本项目「生成没人消费」的镜像）。
func _build_buff_hud() -> void:
	# 【L4】底板：文案此前**直接压在亮绿地图上**（字色 DBCC85 对地图亮绿 3B7A44 只有 3.2:1，
	# 且地图明度不均 ⇒ 有的字落暗格、有的落亮格，可读性不稳定）。
	# 加 0B0D10 @ 0.78 的底板后对比度 11.9:1 ✓。**字色常量不动** —— 问题不在它。
	# 无描边（描边只允许 0 或 1px，这里取 0，避免与 HP 外框的 1px 内框抢视线）。
	var plate := Panel.new()
	plate.name = "BuffPlate"
	var plate_sb := StyleBoxFlat.new()
	var plate_bg := GameConstants.UI_PANEL_BG  # 0B0D10（色板内）
	plate_bg.a = 0.78
	plate_sb.bg_color = plate_bg
	plate_sb.set_border_width_all(0)
	plate.add_theme_stylebox_override("panel", plate_sb)
	plate.position = Vector2(16, 168)
	plate.size = Vector2(288, 16)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(plate)

	_buff_label = Label.new()
	_buff_label.name = "BuffHud"
	# 左栏三块板（任务底板 / HP 外框 / 增益底板）统一 x=16 对齐、同宽 288。
	_buff_label.position = Vector2(24, 168)
	_buff_label.size = Vector2(280, 16)
	_buff_label.add_theme_font_size_override("font_size", 11)  # 规范 §2.5/§5.1：仅允许 [11, 12, 16, 22, 32]（L4：12 → 11，与左栏其余两板统一）
	_buff_label.add_theme_color_override("font_color", GameConstants.UI_BUFF_HUD_TEXT)  # 阶段 11 收尾 · team-lead 裁定 L864 方案 A
	$HUD.add_child(_buff_label)
	# 两个消费者（均此前零消费者）：连杀 + 三选一选定
	EventBus.kill_streak_changed.connect(_on_kill_streak_changed)
	EventBus.run_buff_selected.connect(_on_run_buff_selected)
	_refresh_buff_hud()


## 刷新 HUD 文本。无增益时显示「—」，避免出现空行。**文本未变则不动 `text`**（省重排）。
func _refresh_buff_hud() -> void:
	if _buff_label == null or not is_instance_valid(_buff_label):
		return
	var parts: Array[String] = []
	for id in _buff_system.buffs:
		var opt := RunePool.get_option(str(id))
		var nm := str(opt["name"]) if not opt.is_empty() else str(id)
		parts.append("%s×%d" % [nm, int(_buff_system.buffs[id])])
	if _buff_system.streak > 0:
		parts.append("连杀 %d（+%.1f%% 攻）" % [_buff_system.streak, _buff_system.streak_bonus_attack])
	var text := "局内增益：" + ("—" if parts.is_empty() else " · ".join(parts))
	if text == _buff_hud_sig:
		return
	_buff_hud_sig = text
	_buff_label.text = text


## `kill_streak_changed` 的消费者（此前零消费者 ⇒ 连杀不可见）
func _on_kill_streak_changed(_streak: int, _bonus_attack_pct: float) -> void:
	_refresh_buff_hud()


## `run_buff_selected` 的消费者（此前零消费者）。面板选定增益后广播此信号 ⇒ 刷新增益 HUD。
## 选它而不是删信号：① 满足 §4.10「有生产者必须有消费者」；② 不必碰 `choice_panel.gd`（设计顾问独占）。
func _on_run_buff_selected(_buff_id: String, _stacks: int) -> void:
	_refresh_buff_hud()


# =============================================================================
# 结算
# =============================================================================

## `reason` 仅用于失败横幅与 `level_failed` 载荷的区分（"hp_depleted" = 被打死，
## "abandoned" = ESC 放弃）。**结算分支本身只有一条** —— 放弃与死亡共用它，
## 避免「少则一处不一致」（例如放弃路径漏调 `_persist()`）。
func _finish_run(survived: bool, reason: String = "hp_depleted") -> void:
	if _finished:
		return
	_finished = true

	var bagged := _collect_bagged()
	var res := RunResult.finalize(
		survived, _kills, _progression.run_level,
		float(_player.gold if _player != null else 0),
		{"magic_stone": _player.materials} if _player != null else {},
		bagged, 0, _rare_drops, _buff_system.streak,
		# 局内「贪婪」金币/材料获取加成（默认 0 = 不变）
		_player.get_combat_stat("gold_gain") if _player != null else 0.0)
	res.bagged_equipment = bagged

	_persist(res)

	# 结算面板：直接调用（审计 §4 #2 要求的「打完能出结算」路径）
	_result_panel.on_hub = func() -> void: SceneManager.change_to_hub()
	_result_panel.on_restart = func() -> void: SceneManager.change_to_level(level_id, difficulty_tier)
	_result_panel.visible = true
	_result_panel.show_result(res)

	if not survived:
		_set_banner("已放弃本局" if reason == "abandoned" else "战斗失败")
		EventBus.level_failed.emit(level_id, reason)

	# 任务 11.9 埋点：收一局（追加一行 JSON 到 user://metrics/combat_metrics.jsonl）。
	# 放在 `_finished` 已经置位之后 —— 它是**唯一**收口，放弃 / 死亡 / 通关都到这儿。
	CombatMetrics.end_run(survived)

	# 结算广播（审计 #10：这条信号此前**零生产者**）。
	# 载荷契约（team-lead 裁决）：`summary` **只有一个键** `{"result": RunResult}`，直通不镜像。
	# 消费方是 `SceneManager._on_level_completed()`（Autoload 常驻）——
	# 不能挂据点：`change_scene()` 会释放旧场景，结算时据点还不在树上。
	# 存活与失败都发：这是「本局已结算」的事实，不是「通关了」的意思（那看 res.survived）。
	EventBus.level_completed.emit(level_id, difficulty_tier, {"result": res})

	print("[Level] 结算：%s · 击杀 %d · 局内等级 %d · 评分 %s（%.0f）"
		% ["存活" if survived else "失败", _kills, _progression.run_level, res.grade, res.score])


## 会话背包（Dictionary 条目）→ `EquipmentInstance` 数组。
##
## ⚠️ **元素类型契约**：`RunResult.bagged_equipment` 的元素必须是 `EquipmentInstance`。
##    理由：`ResultPanel.show_result()` 直接读 `item.template_id / .rarity / .item_level`
##    （result_panel.gd:75-77），`verify_run_result.gd:42` 与 `verify_ui71.gd:246`
##    也都按**对象**构造。
##    曾经本场景图省事把会话背包的 Dictionary 原样塞进去 ⇒ 结算面板抛
##    `Invalid access to property or key 'template_id' on a base object of type 'Dictionary'`，
##    而且是在**创建「返回大厅 / 再来一局」按钮之前**就中断 ⇒ **玩家卡在结算界面回不了据点**。
##    两个既有测试都没抓到：它们绕过本场景，直接拿 EquipmentInstance 构造结算单。
func _collect_bagged() -> Array[EquipmentInstance]:
	var out: Array[EquipmentInstance] = []
	if _player == null:
		return out
	for entry in _player.inventory:
		var inst := _to_instance(entry)
		if inst != null:
			out.append(inst)
	return out


## 结算落盘：金币 / 材料按结算率进账，入包装备进存档背包，统计与通关记录更新。
func _persist(res: RunResult) -> void:
	var data := SaveManager.current_data
	if data == null:
		push_warning("[Level] 无 current_data，本局结算不落盘")
		return

	data.gold += int(res.gold_after)
	# 通关金币奖励（LevelData.reward_gold 区间）。**不参与** RunResult 的 50% 结算率 ——
	# 那 50% 是「局内捡到但没带出」的规则（`RunResult.SETTLE_GOLD_RATE`），
	# 通关奖励是关卡给的，不该被扣。
	# ⚠️ 已知缺口：结算面板只显示 `res.gold_after`，**不含**这笔通关奖励，
	#    所以面板上的金币数会小于实际入账数。面板改造属阶段 7 UI 范围。
	var clear_gold := 0
	if res.survived:
		clear_gold = _rng.randi_range(_level_def.reward_gold.x, _level_def.reward_gold.y)
		data.gold += clear_gold
	for k in res.materials_after:
		data.materials[k] = int(data.materials.get(k, 0)) + int(res.materials_after[k])

	# res.bagged_equipment 的元素已是 EquipmentInstance（见 _collect_bagged 的契约说明）
	for inst in res.bagged_equipment:
		if inst is EquipmentInstance:
			data.inventory.append(inst)

	data.statistics["monsters_killed"] = int(data.statistics.get("monsters_killed", 0)) + res.kills
	data.statistics["items_picked"] = int(data.statistics.get("items_picked", 0)) \
		+ res.bagged_equipment.size()

	if res.survived:
		# 账号经验：关卡奖励经验按难度 DMG 曲线放大（LevelData.get_reward_xp）
		var acc := AccountLevel.new()
		acc.level = data.account_level
		acc.xp_cur = data.account_xp
		acc.talent_points = data.talent_points
		acc.add_xp(_level_def.get_reward_xp(difficulty_tier))
		data.account_level = acc.level
		data.account_xp = acc.xp_cur
		data.talent_points = acc.talent_points

		if not data.cleared_levels.has(level_id):
			data.cleared_levels.append(level_id)
		data.level_clear_times[level_id] = int(data.level_clear_times.get(level_id, 0)) + 1

	var ok := SaveManager.save_to_slot(data.slot, data)
	if not ok:
		push_warning("[Level] 结算落盘失败（槽 %d）" % data.slot)


## 会话背包条目 → EquipmentInstance。
## 优先用掉落时定型的完整实例（含词缀，任务 3.2），否则用模板重建无词缀占位。
func _to_instance(entry: Dictionary) -> EquipmentInstance:
	if entry.has("instance") and entry["instance"] is Dictionary:
		return EquipmentInstance.from_dict(entry["instance"])
	var tpl: EquipmentData = ConfigLoader.equipment_templates.get(str(entry.get("item_id", "")))
	if tpl == null:
		return null
	return EquipmentInstance.create_from_template(
		tpl, int(entry.get("item_level", 1)), int(entry.get("rarity", GameConstants.Rarity.COMMON)))


func _set_banner(text: String) -> void:
	_banner.text = text


## 生成墙体/障碍碰撞体。
## LevelView 只画不碰撞（任务 8.3 压 draw call），墙格和障碍格没有物理体，
## 玩家/敌人会穿墙。这里用一个 StaticBody2D 父节点装**合并后的**矩形碰撞体。
##
## ⚠️ 契约（别改）：
##   · `collision_layer = 1` / `collision_mask = 0` —— 层 1 = world（地形）。
##     玩家 `mask=1`、敌人 `mask=3`（`scenes/player/player.tscn` /
##     `scenes/enemies/enemy_base.tscn`），改层号等于让所有挡人逻辑失效。
##   · **合并后的碰撞面必须与逐格完全等价**（同一集合的并集，不多不少）。
##     等价性由 `tools/verify_level_gen.gd` 的 canary 段**逐格枚举点做集合比较**盯死。
##
## 为什么要合并（原注释写的「物理引擎自动批处理」是错的）：
##   独立 `CollisionShape2D` 节点**各自**是一个 broadphase AABB + shape owner，
##   引擎不会替你把它们并起来。程序化关卡先填满墙再挖房间，逐格能到几百上千个：
##   实测 `ch1_l01` 717/829/770 个、`ch1_l02` 574 个。
##   合并后降到百来个（`tools/probe_level.gd` 可复现）。
func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "TileCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for r in _merge_blocking_rects(_layout.get("cells", {})):
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(r.size.x * TILE_PX, r.size.y * TILE_PX)
		shape.shape = rect
		shape.position = Vector2(
			r.position.x * TILE_PX + r.size.x * TILE_PX / 2.0,
			r.position.y * TILE_PX + r.size.y * TILE_PX / 2.0)
		body.add_child(shape)


## 挡人格（墙 / 障碍）→ **矩形并集**（格坐标，`Rect2i`）。
##
## 算法（纯几何，**独立于渲染**，只读 `cells` 字典）：
##   ① 逐行取横向连续段：同一行里 x 连续的一串挡人格 → 一个 `1×N` 矩形；
##   ② 纵向合并：x 起点、宽度都相同、且 y 首尾相接的两段 → 并成一个更高的矩形。
##
## ⚠️ **等价性是硬约束**：返回的矩形并集必须**恰好等于**输入里挡人格的集合。
##    合并只是「把同色格子拼成更大的块」，不允许扩边、不允许吞掉空格。
##    （`verify_level_gen` 的 canary 段会用逐格枚举点做集合比较来盯这一条。）
##
## 返回顺序不保证，调用方不应依赖。
func _merge_blocking_rects(cells: Dictionary) -> Array[Rect2i]:
	# ① 按行归集挡人格的 x
	var by_row: Dictionary = {}   # y -> Array[int]
	for key in cells:
		if not key is Vector2i:
			continue
		var c: Vector2i = key
		var t: int = int(cells[c])
		if t != LevelGenerator.TILE_WALL and t != LevelGenerator.TILE_OBSTACLE:
			continue
		if not by_row.has(c.y):
			by_row[c.y] = []
		(by_row[c.y] as Array).append(c.x)

	# ② 逐行切横向连续段
	var runs: Array[Rect2i] = []
	var rows: Array = by_row.keys()
	rows.sort()
	for y in rows:
		var xs: Array = by_row[y]
		xs.sort()
		var start: int = int(xs[0])
		var prev: int = start
		for i in range(1, xs.size()):
			var x: int = int(xs[i])
			if x != prev + 1:
				runs.append(Rect2i(start, int(y), prev - start + 1, 1))
				start = x
			prev = x
		runs.append(Rect2i(start, int(y), prev - start + 1, 1))

	# ③ 纵向合并：按 (x, 宽度, y) 排序后，同列且首尾相接的直接延伸
	runs.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		if a.position.x != b.position.x:
			return a.position.x < b.position.x
		if a.size.x != b.size.x:
			return a.size.x < b.size.x
		return a.position.y < b.position.y)
	var out: Array[Rect2i] = []
	var last_index: Dictionary = {}   # "x:w" -> out 里该列当前可延伸矩形的下标
	for r in runs:
		var k := "%d:%d" % [r.position.x, r.size.x]
		if last_index.has(k):
			var idx: int = int(last_index[k])
			var o: Rect2i = out[idx]
			if o.position.y + o.size.y == r.position.y:
				out[idx] = Rect2i(o.position.x, o.position.y, o.size.x, o.size.y + r.size.y)
				continue
		out.append(r)
		last_index[k] = out.size() - 1
	return out
