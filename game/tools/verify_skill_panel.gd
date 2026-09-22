## 技能管理面板实测（步骤 3 · 2026-09-22 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_skill_panel.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围：
##   A. 职业专属技能池 + 默认出战栏（数据层）
##   B. 存档 v3：skill_bar 字段落盘 / 读档 / v2→v3 迁移补默认栏
##   C. 据点技能面板：懒建 / 打开 / 结构（标题 / 池卡 / 出战槽）
##   D. 交互：池卡装配 / 出战槽卸下 / 栏满提示 / 重排（卸下重装）/ 保存落盘 / 恢复默认
##   E. 控制器联动：skill_controller 读档出战栏（职业专属 + 顺序生效）
extends Node2D

const CLASS_IDS: Array[String] = ["warrior", "archer", "mage"]

var _fail: int = 0
var _hub: Node = null

func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 技能管理面板实测（步骤 3）=====")
	SceneManager.fade_duration = 0.0
	_test_class_data()
	await _test_save_v3()
	await _test_hub_panel()
	await _test_interactions()
	await _test_controller_wiring()
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	print("===== 技能管理面板实测 结束：%s ====="
		% ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# A. 职业专属技能池 + 默认出战栏
# =============================================================================

func _test_class_data() -> void:
	print("--- A. 职业专属技能池 ---")
	var expect := {
		"warrior": ["cleave", "spin_slash", "dash_strike"],
		"archer": ["piercing_shot", "arrow_rain", "venom_shot"],
		"mage": ["fireball", "frost_nova", "lightning_chain"],
	}
	var ok_defaults := true
	var ok_pools := true
	for cid in CLASS_IDS:
		var bar := ConfigLoader.class_default_skill_bar(cid)
		if bar != expect[cid]:
			ok_defaults = false
			_info("%s 默认栏 = %s（期望 %s）" % [cid, str(bar), str(expect[cid])])
		var pool := ConfigLoader.class_skill_ids(cid)
		if pool.size() < 3 or pool.size() > 5:
			ok_pools = false
			_info("%s 池数异常：%d" % [cid, pool.size()])
		for sid in bar:
			if not pool.has(sid):
				ok_pools = false
				_info("%s 默认栏技能 %s 不在池" % [cid, sid])
	_ok("三职业默认出战栏 = 战(裂斩/旋刃/突进) 弓(穿透箭/箭雨/淬毒箭) 法(火球/冰环/雷链)",
		ok_defaults)
	_ok("技能池：战士 5 / 弓箭手 4 / 法师 5（专属，默认栏均在池内）",
		ok_pools
		and ConfigLoader.class_skill_ids("warrior").size() == 5
		and ConfigLoader.class_skill_ids("archer").size() == 4
		and ConfigLoader.class_skill_ids("mage").size() == 5)


# =============================================================================
# B. 存档 v3
# =============================================================================

func _test_save_v3() -> void:
	print("--- B. 存档 v3（skill_bar 落盘 / 迁移）---")
	var slot := 0
	if SaveManager.slot_exists(slot):
		SaveManager.delete_slot(slot)
	var data := SaveManager.create_new_slot(slot, "archer")
	_ok("新建弓箭手档：skill_bar = 职业默认栏", data != null
		and data.skill_bar == ["piercing_shot", "arrow_rain", "venom_shot"]
		and data.save_version == GameConstants.SAVE_VERSION)
	if data != null:
		data.skill_bar = ["venom_shot", "piercing_shot", "arrow_rain"]
		_ok("改栏后重存并重读：顺序保留（重排落盘）",
			SaveManager.save_to_slot(slot, data)
			and SaveManager.load_from_slot(slot) != null
			and SaveManager.load_from_slot(slot).skill_bar
				== ["venom_shot", "piercing_shot", "arrow_rain"])
	# v2 → v3 迁移：旧档无 skill_bar → 补职业默认栏
	var legacy := {
		"save_version": 2, "slot": 1, "class_id": "mage",
		"account_level": 1, "gold": 0, "inventory": [], "stash": [],
		"equipped": {}, "unlocked_talent_nodes": [], "cleared_levels": [],
		"display_name": "法师 · Lv.1", "created_at": 0, "updated_at": 0,
	}
	var migrated := SaveData.from_dict(legacy)
	var mig_ok := migrated != null and migrated.migrate()
	_ok("v2 旧档迁移：skill_bar 补法师默认栏 + 版本升 3", mig_ok
		and migrated != null
		and migrated.skill_bar == ["fireball", "frost_nova", "lightning_chain"]
		and migrated.save_version == 3)
	if SaveManager.slot_exists(slot):
		SaveManager.delete_slot(slot)


# =============================================================================
# C. 据点技能面板（懒建 / 打开 / 结构）
# =============================================================================

func _test_hub_panel() -> void:
	print("--- C. 据点技能面板 ---")
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	var data := SaveManager.create_new_slot(0, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = 0
	# 手动实例化据点场景（不换 current_scene，避免工具脚本根节点随场景替换被释放）
	var packed: PackedScene = load("res://scenes/main/hub.tscn")
	_hub = packed.instantiate()
	add_child(_hub)
	if _hub.has_method("on_scene_entered"):
		_hub.on_scene_entered({})
	await _wait_frames(4)
	_ok("进入据点（手动实例化）", _hub != null)
	if _hub == null:
		return
	_ok("技能面板已构建（据点 _enter 预建全部面板）", _hub.get_panel("skills") != null)
	# 通过据点按钮条打开（真按钮）
	var btn := _find_button(_hub, "技能")
	_ok("据点半按钮条含「技能」", btn != null)
	if btn == null:
		return
	btn.pressed.emit()
	await _wait_frames(2)
	_ok("技能面板已打开（is_panel_visible）", _hub.is_panel_visible("skills"))
	var sp := _hub.get_panel("skills") as SkillPanel
	_ok("面板类型 SkillPanel + 标题含职业", sp != null
		and sp._title != null and sp._title.text.contains("战士"))
	if sp == null:
		return
	_ok("战士池卡 5 张（GridContainer 子节点）", sp._pool_grid.get_child_count() == 5)
	var slot_names := _bar_slot_names(sp)
	_ok("出战槽 3 个 = 裂斩 / 旋刃 / 突进（默认栏）",
		slot_names.size() == 3 and slot_names == ["裂斩", "旋刃", "突进"])
	_ok("「恢复默认」「保存技能栏」按钮存在",
		_find_button(sp, "恢复默认") != null and _find_button(sp, "保存技能栏") != null)


func _bar_slot_names(sp: SkillPanel) -> Array:
	var names: Array = []
	if sp._bar_row == null:
		return names
	for slot in sp._bar_row.get_children():
		for child in slot.get_children():
			if child is Label and (child as Label).position.y >= 40.0:
				names.append((child as Label).text)
	return names


# =============================================================================
# D. 交互
# =============================================================================

func _test_interactions() -> void:
	print("--- D. 面板交互 ---")
	var sp := _hub.get_panel("skills") as SkillPanel
	if sp == null:
		return
	# 1) 栏满时装配 → 拒绝并提示
	_find_button_by_name(sp, "PoolBtn_power_strike").pressed.emit()
	await _wait_frames(1)
	_ok("出战栏满时装配被拒（提示 + 栏不变）",
		sp.bar == ["cleave", "spin_slash", "dash_strike"]
		and sp._info.text.contains("已满"))
	# 2) 卸下 1 号位（裂斩）→ 栏变 [旋刃, 突进]
	sp._bar_row.get_child(0).get_node("BarBtn0").pressed.emit()
	await _wait_frames(1)
	_ok("点击出战槽 1 → 卸下裂斩", sp.bar == ["spin_slash", "dash_strike"]
		and sp._info.text.contains("已卸下"))
	# 3) 装配蓄力斩 → 自动补到末尾
	_find_button_by_name(sp, "PoolBtn_power_strike").pressed.emit()
	await _wait_frames(1)
	_ok("点击池卡蓄力斩 → 装配到空位",
		sp.bar == ["spin_slash", "dash_strike", "power_strike"])
	# 4) 重排：卸下旋刃 → 重装裂斩 → [突进, 蓄力斩, 裂斩]
	sp._bar_row.get_child(0).get_node("BarBtn0").pressed.emit()
	_find_button_by_name(sp, "PoolBtn_cleave").pressed.emit()
	await _wait_frames(1)
	_ok("重排生效（卸旋刃 → 装裂斩 → [突进,蓄力斩,裂斩]）",
		sp.bar == ["dash_strike", "power_strike", "cleave"])
	# 5) 保存 → 内存 + 落盘
	var save_btn := _find_button(sp, "保存技能栏")
	save_btn.pressed.emit()
	await _wait_frames(2)
	_ok("保存后存档 skill_bar = [突进,蓄力斩,裂斩]",
		SaveManager.current_data != null
		and SaveManager.current_data.skill_bar == ["dash_strike", "power_strike", "cleave"])
	var reloaded := SaveManager.load_from_slot(0)
	_ok("重新读档：技能栏仍在磁盘（v3）", reloaded != null
		and reloaded.skill_bar == ["dash_strike", "power_strike", "cleave"]
		and reloaded.save_version == 3)
	# 6) 恢复默认（不落盘）
	_find_button(sp, "恢复默认").pressed.emit()
	await _wait_frames(1)
	_ok("恢复默认 → 工作区回职业默认栏（存档不变）",
		sp.bar == ["cleave", "spin_slash", "dash_strike"]
		and SaveManager.current_data.skill_bar == ["dash_strike", "power_strike", "cleave"])


# =============================================================================
# E. 控制器联动
# =============================================================================

func _test_controller_wiring() -> void:
	print("--- E. 技能控制器读档联动 ---")
	var player := get_node_or_null("/root/VerifySkillPanel/Player") as PlayerController
	var sc := player.get_skill_controller() if player != null else null
	_ok("玩家 + 技能控制器就绪", player != null and sc != null)
	if sc == null:
		return
	# 无档回退战士默认栏
	SaveManager.current_data = null
	sc._load_skills()
	_ok("无存档：出战栏回退战士默认（裂斩/旋刃/突进）",
		sc.get_skill_id_at(0) == "cleave"
		and sc.get_skill_id_at(1) == "spin_slash"
		and sc.get_skill_id_at(2) == "dash_strike")
	# 弓箭手档 → 弓手默认栏
	var data := SaveManager.create_new_slot(1, "archer")
	SaveManager.current_data = data
	SaveManager.current_slot = 1
	sc._load_skills()
	_ok("弓箭手档：出战栏 = 穿透箭/箭雨/淬毒箭",
		sc.get_skill_id_at(0) == "piercing_shot"
		and sc.get_skill_id_at(1) == "arrow_rain"
		and sc.get_skill_id_at(2) == "venom_shot")
	# 重排后顺序生效
	data.skill_bar = ["venom_shot", "piercing_shot", "arrow_rain"]
	sc._load_skills()
	_ok("重排后：出战栏顺序 = 淬毒箭/穿透箭/箭雨",
		sc.get_skill_id_at(0) == "venom_shot"
		and sc.get_skill_id_at(1) == "piercing_shot"
		and sc.get_skill_id_at(2) == "arrow_rain")
	SaveManager.current_data = null
	SaveManager.current_slot = -1


# =============================================================================
# 工具
# =============================================================================

func _find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		var btn := child as Button
		if btn.text == text:
			return btn
	return null


func _find_button_by_name(root: Node, name: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		if child.name == name:
			return child as Button
	return null


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_for_scene(scene_name: String) -> Node:
	for i in 300:
		var cs := SceneManager.get_current_scene()
		if cs != null and cs.name == scene_name:
			return cs
		await get_tree().process_frame
	return null
