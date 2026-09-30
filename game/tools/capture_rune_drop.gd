## 工具：capture_rune_drop.gd（HANDOFF-E 符文掉落**端到端實機**目視驗收；**非玩法**）
##
## 用法（**必須去掉 `--headless`**，否則沒有渲染）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_rune_drop.tscn
## 產出：`D:/七傳說/deliverables/gstack/e_loot_shot/e-3..7-*.png`
##
## 走的是**真實玩家路徑**（不是直接呼叫 pickup_loot）：
##   真怪物死亡 → EnemyBase._drop_loot → roll_rune_drop → LootDrop 落地 →
##   玩家走近自動拾取 → PlayerController._pickup_rune → 提示條 → 據點圖鑑
##
## ⚠️ 只用測試槽位 7（跑完刪除），**不碰玩家存檔**。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/e_loot_shot"
const TEST_SLOT: int = 7
const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _fail: int = 0
var _player: PlayerController = null
var _world: Node2D = null
var _cam: Camera2D = null
var _hud: PickupToastHUD = null
## 上一张截图的像素（防「截到冻结画面」——实测连拍 4 张字节数完全相同）
var _prev_pixels: PackedByteArray = PackedByteArray()


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 150.0)
	print("===== HANDOFF-E 符文掉落端到端目視抓圖 =====")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _shot(fname: String) -> void:
	# ⚠️ **必须**等 `frame_post_draw`：只 `await process_frame` 时，
	#    `get_viewport().get_texture().get_image()` 可能拿到**上一帧甚至冻结的画面**
	#    —— 实测症状是连拍 4 张 PNG 字节数完全相同（截到的都是同一张）。
	await get_tree().process_frame   # 让 Container 布局 / tween 先生效
	await RenderingServer.frame_post_draw
	# 调试：提示条当前有几条、文案是什么（避免「以为拍了、其实没渲染」）
	if _hud != null:
		var texts: Array[String] = []
		for c in _hud.get_children():
			var lbl := (c as PanelContainer).get_child(0).get_child(0) as Label
			texts.append(lbl.text)
		print("       [toast] %d 条：%s" % [texts.size(), str(texts)])
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	# 防「截到冻结画面」：与上一张逐像素比较，必须不同（铁律 ㊾ 的延伸）
	var data := img.get_data()
	var differs := data != _prev_pixels
	_prev_pixels = data
	_ok("截图 %s（err=%d）" % [fname, err], err == OK)
	_ok("  ↑ 与上一张画面不同（防冻结画面）", differs)


func _run() -> void:
	_ok("渲染驱动不是 headless", DisplayServer.get_name() != "headless")

	# ---- 场景：地面 + 相机（世界层）----
	_world = Node2D.new()
	add_child(_world)
	var ground := ColorRect.new()
	ground.color = Color("14171C")
	ground.position = Vector2(-2000, -2000)
	ground.size = Vector2(4000, 4000)
	_world.add_child(ground)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(2.0, 2.0)
	_world.add_child(_cam)
	_cam.make_current()

	# ---- 测试存档（槽 7）----
	if SaveManager.slot_exists(TEST_SLOT):
		SaveManager.delete_slot(TEST_SLOT)
	var data := SaveManager.create_new_slot(TEST_SLOT, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = TEST_SLOT
	data.unlocked_runes.clear()

	# ---- 拾取提示条（真实 HUD 组件；挂 CanvasLayer 以免被相机位移）----
	var ui := CanvasLayer.new()
	add_child(ui)
	var hud := PickupToastHUD.new()
	hud.position = Vector2(444.0, 64.0)
	hud.size = Vector2(184.0, 0.0)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	EventBus.loot_picked_up.connect(hud.spawn)
	_hud = hud

	# ---- 玩家 ----
	_player = PLAYER_SCENE.instantiate() as PlayerController
	_world.add_child(_player)
	_player.global_position = Vector2(0, 0)
	await get_tree().physics_frame

	# ---- 杀怪直到**真实掉落**符文（BOSS 表 25%）----
	seed(20260930)
	var rune_node: LootDrop = null
	var attempts := 0
	for i in 40:
		attempts += 1
		var boss := ENEMY_SCENE.instantiate() as EnemyBase
		boss.monster_id = "boss_ember_lord"
		boss.level = 10
		boss.difficulty_tier = GameConstants.DifficultyTier.NM1
		_world.add_child(boss)
		boss.global_position = Vector2(0, 70)
		await get_tree().physics_frame
		boss.take_damage(999999.0, _player)
		await _step(0.35)
		for n in get_tree().get_nodes_in_group(&"loot_drops"):
			var ld := n as LootDrop
			if ld.drop_type == "rune" and rune_node == null:
				rune_node = ld
		if rune_node != null:
			break
		# 清掉这一轮的非符文掉落，避免画面堆满
		for n2 in get_tree().get_nodes_in_group(&"loot_drops"):
			var ld2 := n2 as LootDrop
			if ld2.drop_type != "rune":
				ld2.queue_free()
		await get_tree().process_frame
	_ok("真实路径掉出符文（第 %d 次击杀，type=rune）" % attempts, rune_node != null)
	if rune_node == null:
		await _finish(false)
		return
	var rune_id := rune_node.item_id
	_ok("符文 id 合法（%s ∈ ConfigLoader.runes）" % rune_id, ConfigLoader.runes.has(rune_id))

	# 清掉其他掉落，只留符文，画面干净
	for n3 in get_tree().get_nodes_in_group(&"loot_drops"):
		var ld3 := n3 as LootDrop
		if ld3 != rune_node:
			ld3.queue_free()
	await get_tree().process_frame

	# ---- ① 地面符文物件（紫罗兰光柱 + 真图标）----
	_cam.global_position = rune_node.global_position + Vector2(0, -10)
	await _shot("e-3-地面符文-紫光柱.png")

	# ---- ② 玩家走近 → 自动拾取 → 首获解锁提示 ----
	_player.global_position = rune_node.global_position
	await _step(0.5)
	_ok("首获写入 unlocked_runes（1 枚）",
		SaveManager.current_data.unlocked_runes.size() == 1
		and SaveManager.current_data.unlocked_runes.has(rune_id))
	await _shot("e-4-首获解锁提示条.png")

	# ---- ③ 重复同一符文 → 自动转魔石提示 ----
	# ⚠️ 必须走**真实落地物件**：提示条消费的是 `LootDrop._pick_up()` 里的
	#    `EventBus.loot_picked_up`，直接调 `pickup_loot()` 是**不会**出提示条的。
	await _step(2.6) # 等上一条提示淡出，画面干净
	_player.materials = 0
	var dup := (load("res://scenes/loot/loot_drop.tscn") as PackedScene).instantiate() as LootDrop
	dup.setup({ "type": "rune", "amount": 1, "item_id": rune_id, "rarity": -1, "item_level": 10 })
	_world.add_child(dup)
	dup.global_position = _player.global_position + Vector2(0, 10)
	await _step(0.5)
	_ok("重复不重复写入（仍 1 枚）", SaveManager.current_data.unlocked_runes.size() == 1)
	_ok("重复转魔石（materials == %d）"
		% LootRoller.rune_duplicate_material_amount(10),
		_player.materials == LootRoller.rune_duplicate_material_amount(10))
	await _shot("e-5-重复符文转魔石提示条.png")

	# ---- ④ 据点符文图鉴：已解锁 1 / 24 ----
	_world.queue_free()
	ui.queue_free()
	await get_tree().process_frame
	SaveManager.save_to_slot(TEST_SLOT, SaveManager.current_data)
	SceneManager.fade_duration = 0.0
	var hub: Node = (load("res://scenes/main/hub.tscn") as PackedScene).instantiate()
	add_child(hub)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await get_tree().create_timer(0.9).timeout
	hub._toggle_panel("rune_codex")
	await get_tree().create_timer(0.6).timeout
	await _shot("e-6-图鉴-掉落解锁后.png")

	# ---- ⑤ 技能面板符文选择器：未解锁的 23 条灰显（装配门槛，HANDOFF-E）----
	# ⚠️ 先 toggle 让 hub 建好并 bind（会覆盖），**之后**再手动 bind 注入 skill_level=6
	#    （真实档此时技能等级还是 1，符文槽 3 级才解锁，选择器打不开）。
	hub._toggle_panel("rune_codex")
	hub._toggle_panel("skills")
	await get_tree().create_timer(0.6).timeout
	var sp := hub.get_panel("skills") as SkillPanel
	if sp != null:
		var cls: String = SaveManager.current_data.class_id
		sp.bind(cls, ConfigLoader.class_skill_ids(cls), SaveManager.current_data.skill_bar,
			Callable(), {
				"runes": SaveManager.current_data.skill_runes,
				"branches": SaveManager.current_data.skill_branches,
				"account_level": SaveManager.current_data.account_level,
				"cleared_levels": SaveManager.current_data.cleared_levels,
				"skill_level": 6,
				"unlocked_runes": SaveManager.current_data.unlocked_runes,
			})
		await get_tree().create_timer(0.3).timeout
		var pool := ConfigLoader.class_skill_ids(cls)
		var sid: String = String(pool[0]) if not pool.is_empty() else ""
		sp._open_detail(sid)
		sp._on_rune_slot_pressed(0, true)
		await get_tree().create_timer(0.4).timeout
		_ok("技能面板符文选择器已打开", sp._rune_pick_slot == 0)
		await _shot("e-7-技能面板-未解锁符文灰显.png")

	await _finish(true)


func _step(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for i in range(frames):
		await get_tree().physics_frame


func _finish(clean: bool) -> void:
	if clean and SaveManager.slot_exists(TEST_SLOT):
		SaveManager.delete_slot(TEST_SLOT)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
