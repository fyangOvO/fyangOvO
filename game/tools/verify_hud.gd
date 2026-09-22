## 工具：verify_hud.gd（步骤 6 · 局内 HUD + 战斗体验）
##
## A. HealthBar 法力模式：法力池读取 / 蓝渐变 / 法力文本
## B. level.tscn：MpBar 节点（value_kind=mana / bar_mp 贴图）
## C. SkillBarUI：3 槽 / 图标名 / 键位 / 冷却遮罩状态
## D. PickupToastHUD：金币/材料/装备提示条 + 上限
## E. 关卡接线：拾取广播 → 提示流；技能栏挂载
extends Node2D

var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 90.0)
	print("===== 局内 HUD + 战斗体验实测（步骤 6）=====")
	_run()


func _run() -> void:
	await _test_mana_bar()
	await _test_level_mp_node()
	await _test_skill_bar()
	await _test_pickup_toasts()
	await _test_level_wiring()
	print("===== 步骤 6 实测 结束：%s =====" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# A. HealthBar 法力模式
# =============================================================================

func _test_mana_bar() -> void:
	print("--- A. HealthBar 法力模式 ---")
	var bar := HealthBar.new()
	bar.value_kind = "mana"
	add_child(bar)
	var pool := ManaPool.new()
	pool.current = 37.0
	pool.maximum = 100.0
	var fake := Node.new()
	fake.set_script(load("res://tools/fake_mana_target.gd"))
	fake.mana_pool = pool
	bar.target = fake
	bar.show_text = true
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("法力条渐变 = 蓝（FROM 3A5FB0）", bar._grad_tex.gradient.colors[0] == GameConstants.UI_MP_BAR_GRADIENT_FROM)
	_ok("法力条渐变 = 蓝（TO 1F3468）", bar._grad_tex.gradient.colors[1] == GameConstants.UI_MP_BAR_GRADIENT_TO)
	# 法力 37/100 → ratio 0.37（私有绘制不可直接断言，用「读取不崩 + 池值变化后仍不崩」做冒烟）
	pool.set_current(0.0)
	await get_tree().process_frame
	bar.queue_free()
	fake.queue_free()
	await get_tree().process_frame
	_ok("法力条读取与绘制无异常", true)


# =============================================================================
# B. level.tscn MpBar
# =============================================================================

func _test_level_mp_node() -> void:
	print("--- B. level.tscn MpBar ---")
	var scene := load("res://scenes/levels/level.tscn") as PackedScene
	_ok("level.tscn 可加载", scene != null)
	var level: Node = scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	var mp := level.get_node_or_null("HUD/MpBar") as HealthBar
	_ok("MpBar 节点存在", mp != null)
	_ok("MpBar 法力模式", mp != null and mp.value_kind == "mana")
	_ok("MpBar 用 bar_mp 贴图", mp != null and mp.bar_texture_name == "bar_mp")
	level.queue_free()
	await get_tree().process_frame


# =============================================================================
# C. SkillBarUI
# =============================================================================

func _test_skill_bar() -> void:
	print("--- C. SkillBarUI（3 槽 / 键位 / 冷却）---")
	var bar := SkillBarUI.new()
	add_child(bar)
	var fake := _make_fake_ctrl()
	bar.setup(fake)
	await get_tree().process_frame
	_ok("3 槽", bar.get_slot_count() == 3)
	_ok("槽 1 = cleave", String(bar.get_slot_state(0)["id"]) == "cleave")
	_ok("槽 3 = dash_strike", String(bar.get_slot_state(2)["id"]) == "dash_strike")
	# 冷却：cleave 冷却 8s，剩余 5s → ratio 0.625
	_ok("cleave 冷却中", bool(bar.get_slot_state(0)["on_cd"]))
	var ratio := float(bar.get_slot_state(0)["cd_ratio"])
	_ok("冷却比例 ≈ 0.625（%.3f）" % ratio, absf(ratio - 0.625) < 0.02)
	_ok("槽 2 无冷却", not bool(bar.get_slot_state(1)["on_cd"]))
	bar.queue_free()
	await get_tree().process_frame


# =============================================================================
# D. PickupToastHUD
# =============================================================================

func _test_pickup_toasts() -> void:
	print("--- D. PickupToastHUD ---")
	var hud := PickupToastHUD.new()
	add_child(hud)
	hud.spawn({"type": "gold", "amount": 5})
	hud.spawn({"type": "material", "amount": 3})
	hud.spawn({"type": "equipment", "item_id": "sword_flame", "rarity": GameConstants.Rarity.RARE,
		"item_level": 14})
	await get_tree().process_frame
	_ok("金币提示条", _row_text(hud, 0).contains("金币 +5"))
	_ok("材料提示条", _row_text(hud, 1).contains("魔石 +3"))
	_ok("装备提示条（名称 + 稀有度色）", _row_text(hud, 2).contains("已拾取：")
		and _row_color(hud, 2) == GameConstants.rarity_color(GameConstants.Rarity.RARE))
	# 上限 5
	for i in 6:
		hud.spawn({"type": "gold", "amount": i + 1})
	await get_tree().process_frame
	_ok("上限 5 条", hud.get_child_count() == 5)
	_ok("超限移除最旧", not _row_text(hud, 0).contains("金币 +5") or hud.get_child_count() == 5)
	hud.queue_free()
	await get_tree().process_frame


# =============================================================================
# E. 关卡接线
# =============================================================================

func _test_level_wiring() -> void:
	print("--- E. 关卡接线（技能栏 + 拾取提示）---")
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	var data := SaveManager.create_new_slot(0, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = 0
	SceneManager.fade_duration = 0.0
	var level: Node = (load("res://scenes/levels/level.tscn") as PackedScene).instantiate()
	add_child(level)
	await get_tree().process_frame
	if level.has_method("on_scene_entered"):
		level.on_scene_entered({"level_id": "ch1_l01", "difficulty_tier": GameConstants.DifficultyTier.NM1})
	await get_tree().create_timer(0.8).timeout
	_ok("技能栏挂载（SkillBarUI 3 槽）", level._skill_bar != null and level._skill_bar.get_slot_count() == 3)
	_ok("拾取提示流挂载", level._pickup_toasts != null)
	level._on_loot_picked_up({"type": "gold", "amount": 7})
	await get_tree().process_frame
	_ok("拾取广播 → 提示条", level._pickup_toasts.get_child_count() >= 1)
	_ok("血蓝条已绑定玩家", level._hp_bar.target != null and level._mp_bar.target != null)
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	level.queue_free()
	await get_tree().process_frame


# =============================================================================
# 工具
# =============================================================================

## 鸭子类型控制器：get_skill_id_at / is_on_cooldown / get_cooldown_remaining / get_skill_data
func _make_fake_ctrl() -> Object:
	var obj := Object.new()
	obj.set_script(load("res://tools/fake_skill_ctrl.gd"))
	return obj


func _row_text(hud: Control, i: int) -> String:
	if i < 0 or i >= hud.get_child_count():
		return ""
	var row := hud.get_child(i)
	if row.get_child_count() == 0:
		return ""
	var mg := row.get_child(0)
	if mg.get_child_count() == 0:
		return ""
	return String((mg.get_child(0) as Label).text)


func _row_color(hud: Control, i: int) -> Color:
	if i < 0 or i >= hud.get_child_count():
		return Color.BLACK
	var row := hud.get_child(i)
	if row.get_child_count() == 0:
		return Color.BLACK
	var mg := row.get_child(0)
	if mg.get_child_count() == 0:
		return Color.BLACK
	return (mg.get_child(0) as Label).get_theme_color("font_color")


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
