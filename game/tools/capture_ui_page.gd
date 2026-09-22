## 封面 / 关卡页真渲染取证（UI 接入用 · 开发工具，不属于游戏玩法）
##
## 为什么需要它：新 UI 素材包（assets/ui/quest/）与装备图标接入后，
## 无头测试只能证明「控件存在 / 贴图能 load」，证不了「画出来是什么样」。
## 本工具按页面抓真渲染帧存 PNG，让每次接入都有像素级前后对比。
##
## 用法（**必须去掉 `--headless`** —— 无头模式没有渲染）：
##   godot --path "D:/七傳說/game" res://tools/capture_ui_page.tscn
##   godot --path "D:/七傳說/game" res://tools/capture_ui_page.tscn -- cover
##   godot --path "D:/七傳說/game" res://tools/capture_ui_page.tscn -- level
##   godot --path "D:/七傳說/game" res://tools/capture_ui_page.tscn -- cover level --tag after
##   godot --path "D:/七傳說/game" res://tools/capture_ui_page.tscn -- enemies --tag after
##   godot --path "D:/七傳說/game" res://tools/capture_ui_page.tscn -- panels --tag after
##
## 产出（`deliverables/gstack/`）：`ui-<页面>[-<tag>].png`
##
## ⚠️ 只做三件事：建页面 + 渲染几帧 + 存 PNG。不碰任何玩法代码。
extends Node2D

const MENU_SCENE: PackedScene = preload("res://scenes/main/main_menu.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables/gstack"

## 关卡页固定抓第一章第一关
const LEVEL_ID: String = "ch1_l01"

var _fail: int = 0
var _tag: String = ""


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 200.0)
	_run()


func _run() -> void:
	print("===== 封面 / 关卡页抓图 =====")
	_ok("渲染驱动不是 headless（否则抓不到画面）", DisplayServer.get_name() != "headless")

	var args := OS.get_cmdline_user_args()
	var pages: Array[String] = []
	# 用 while 而非 for：`--tag <值>` 需要跳过后一个参数，
	# GDScript 的 `for i in n` 无法改步长，`continue` 只跳过当前项 → 值会被当成页面名。
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--tag" and i + 1 < args.size():
			_tag = args[i + 1]
			i += 2
			continue
		if a.begins_with("--"):
			i += 1
			continue
		pages.append(a)
		i += 1
	if pages.is_empty():
		pages = ["cover", "level"]

	print("[Capture] 目标页面：%s（tag=%s）" % [str(pages), _tag if not _tag.is_empty() else "(无)"])
	for p in pages:
		match p:
			"cover":
				await _capture_cover()
			"level":
				await _capture_level()
			"enemies":
				await _capture_enemies()
			"panels":
				await _capture_panels()
			_:
				_ok("未知页面 %s" % p, false)

	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 封面（主菜单）
func _capture_cover() -> void:
	print("--- 封面 ---")
	var menu := MENU_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await _frames(20)
	await _shot("ui-cover%s.png" % _suffix())
	_ok("封面已构建", is_instance_valid(menu))
	if is_instance_valid(menu):
		menu.queue_free()
	await _frames(3)


## 第一关关卡页
func _capture_level() -> void:
	print("--- 关卡页 %s ---" % LEVEL_ID)
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	_freeze_enemies(level)
	await _hold(level, 40)
	await _shot("ui-level1%s.png" % _suffix())
	_ok("关卡页已构建（敌人 %d 个）" % [level._alive.size()], not level._alive.is_empty())
	level.queue_free()
	await _frames(3)


## 敌人渲染取证：把相机（=玩家）移到最密集的敌人簇，冻结 AI 后抓图。
## 用途：证明「敌人真的画出来了」，而不是只有无头断言「精灵已赋值」。
## （2026-09-21 背景：基线图里看不到敌人，属相机跟随 + 敌人散落屏外，非渲染失效。）
func _capture_enemies() -> void:
	print("--- 关卡页（敌人取证）%s ---" % LEVEL_ID)
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _frames(3)

	# 关掉相机平滑，否则把玩家瞬移过去后相机追不上，抓到的还是原地
	var cam := level.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.position_smoothing_enabled = false

	# 找最密集的敌人簇（120px 半径内邻居最多者），把玩家移过去
	var best := Vector2.ZERO
	var best_n := 0
	for e in level._alive:
		if not is_instance_valid(e):
			continue
		var n := 0
		for o in level._alive:
			if is_instance_valid(o) and e.global_position.distance_to(o.global_position) < 120.0:
				n += 1
		if n > best_n:
			best_n = n
			best = e.global_position
	if level._player != null and best_n > 0:
		level._player.global_position = best
	if cam != null and level._player != null:
		cam.global_position = level._player.global_position
	await _frames(4)

	_freeze_enemies(level)
	await _hold(level, 20)
	await _shot("ui-level1-enemies%s.png" % _suffix())
	_ok("敌人取证完成（最大簇 %d 只 / 全场 %d 只）" % [best_n, level._alive.size()], best_n >= 1)
	level.queue_free()
	await _frames(3)


## 面板取证：装备栏（10 槽，看装备图标是否真的画出来）+ 背包格（图标 + 稀有度框）。
## 用途：证明「武器/装备图标」不再只有文字（此前 62 件 icon_path 全指向不存在的档）。
func _capture_panels() -> void:
	print("--- 面板取证（装备栏 + 背包）---")
	_make_backdrop()

	var ep := EquipPanel.new()
	add_child(ep)
	ep.position = Vector2(20, 20)
	ep.bind(_demo_equipped(), "warrior", Callable())
	await _frames(6)
	await _shot("ui-panels%s.png" % _suffix())
	var icons := 0
	for b in _collect_buttons(ep):
		if b.icon != null:
			icons += 1
	_ok("装备栏有图标真的显示（%d 个槽带图标）" % icons, icons >= 4)
	ep.queue_free()
	await _frames(2)

	var ip := InventoryPanel.new()
	add_child(ip)
	ip.position = Vector2(20, 20)
	var inv := Inventory.create(8, 5)
	for inst in _demo_items():
		inv.add(inst)
	ip.bind(inv, Inventory.create(8, 5))
	await _frames(6)
	await _shot("ui-bag%s.png" % _suffix())
	var bag_icons := 0
	for b in _collect_buttons(ip):
		if b.icon != null:
			bag_icons += 1
	_ok("背包格有图标真的显示（%d 个格带图标）" % bag_icons, bag_icons >= 8)
	ip.queue_free()
	await _frames(2)


## 深色底，避免面板浮在纯黑上看不清
func _make_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 1.0)
	bg.position = Vector2.ZERO
	bg.size = Vector2(640, 360)
	add_child(bg)


func _mk_inst(template_id: String, ilvl: int, rarity: int) -> EquipmentInstance:
	var tpl: EquipmentData = ConfigLoader.get_equipment_template(template_id)
	if tpl == null:
		return null
	return EquipmentInstance.create_from_template(tpl, ilvl, rarity)


## 10 槽各放一件（含腿甲 → 借胸甲图标，用于暴露缺口）
func _demo_equipped() -> Array:
	var arr: Array = []
	arr.resize(GameConstants.EQUIP_SLOT_COUNT)
	arr[GameConstants.EquipSlot.HELM] = _mk_inst("helm_golem", 12, GameConstants.Rarity.EPIC)
	arr[GameConstants.EquipSlot.CHEST] = _mk_inst("chest_ember", 12, GameConstants.Rarity.LEGENDARY)
	arr[GameConstants.EquipSlot.GLOVES] = _mk_inst("gloves_cold", 10, GameConstants.Rarity.RARE)
	arr[GameConstants.EquipSlot.LEGS] = _mk_inst("legs_guardian", 9, GameConstants.Rarity.COMMON)
	arr[GameConstants.EquipSlot.BOOTS] = _mk_inst("boots_wind", 11, GameConstants.Rarity.MAGIC)
	arr[GameConstants.EquipSlot.MAIN_HAND] = _mk_inst("sword_flame", 14, GameConstants.Rarity.LEGENDARY)
	arr[GameConstants.EquipSlot.OFF_HAND] = _mk_inst("shield_tower", 13, GameConstants.Rarity.RARE)
	arr[GameConstants.EquipSlot.AMULET] = _mk_inst("amulet_ember", 12, GameConstants.Rarity.EPIC)
	arr[GameConstants.EquipSlot.RING_A] = _mk_inst("ring_frost", 10, GameConstants.Rarity.MAGIC)
	arr[GameConstants.EquipSlot.RING_B] = _mk_inst("ring_storm", 10, GameConstants.Rarity.MAGIC)
	return arr


## 背包展示件：覆盖剑/斧/匕首/法杖/弓 + 各部位
func _demo_items() -> Array:
	var spec := [
		["sword_flame", GameConstants.Rarity.LEGENDARY],
		["axe_blood", GameConstants.Rarity.RARE],
		["dagger_venom", GameConstants.Rarity.MAGIC],
		["staff_storm", GameConstants.Rarity.EPIC],
		["bow_spirit", GameConstants.Rarity.COMMON],
		["helm_hide", GameConstants.Rarity.RARE],
		["chest_chainmail", GameConstants.Rarity.MAGIC],
		["boots_wanderer", GameConstants.Rarity.COMMON],
		["amulet_bone", GameConstants.Rarity.EPIC],
		["ring_copper", GameConstants.Rarity.MAGIC],
	]
	var out: Array = []
	for s in spec:
		var inst := _mk_inst(str(s[0]), 12, int(s[1]))
		if inst != null:
			out.append(inst)
	return out


func _collect_buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_collect_buttons(c))
	return out


# =============================================================================
# 工具
# =============================================================================

func _suffix() -> String:
	return "" if _tag.is_empty() else "-" + _tag


## 冻住所有敌人（不删，精灵照常渲染，只是不再思考/攻击）
func _freeze_enemies(level: LevelScene) -> void:
	var frozen := 0
	for e in level._alive:
		if not is_instance_valid(e):
			continue
		e.set_physics_process(false)
		e.set_process(false)
		frozen += 1
	print("[Freeze] %s · 已冻结 %d 个敌人的 AI（仅用于抓图，不改玩法代码）"
		% [level.name, frozen])


## 等 n 帧，每帧顺手把玩家奶满，避免抓图期间玩家被打死触发结算
func _hold(level: LevelScene, n: int) -> void:
	for _i in n:
		if is_instance_valid(level) and not level.is_queued_for_deletion():
			var player = level._player
			if player != null and is_instance_valid(player) and player.health != null:
				var hc = player.health
				if not hc.is_dead:
					var maxhp: float = hc.get_max_hp()
					if hc.get_current_hp() < maxhp:
						hc.restore(maxhp - hc.get_current_hp())
		await get_tree().process_frame


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	_ok("抓图 %s → %d×%d（err=%d）" % [fname, img.get_width(), img.get_height(), err],
		err == OK and img.get_width() > 0)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
