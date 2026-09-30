## 技能管理面板实测（步骤 3 · 2026-09-22 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_skill_panel.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围：
##   A. 职业专属技能池 + 默认出战栏（数据层）
##   B. 存档 v5：skill_bar / skill_runes / skill_branches / unlocked_runes 落盘 + v2→v5 迁移
##   C. 据点技能面板：懒建 / 打开 / 结构（标题 / 池卡 / 出战槽 / 符文图鉴）
##   D. 交互：池卡装配 / 详情卸下 / 栏满提示 / 重排（卸下重装）/ 保存落盘 / 恢复默认
##   E. 控制器联动：skill_controller 读档出战栏（职业专属 + 顺序生效）
extends Node2D

const CLASS_IDS: Array[String] = ["warrior", "archer", "mage"]
const CLASS_SKILL_COUNT := 12

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
	await _test_save_v5()
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
		if pool.size() != CLASS_SKILL_COUNT:
			ok_pools = false
			_info("%s 池数异常：%d（期望 %d）" % [cid, pool.size(), CLASS_SKILL_COUNT])
		for sid in bar:
			if not pool.has(sid):
				ok_pools = false
				_info("%s 默认栏技能 %s 不在池" % [cid, sid])
	_ok("三职业默认出战栏 = 战(裂斩/旋刃/突进) 弓(穿透箭/箭雨/淬毒箭) 法(火球/冰环/雷链)",
		ok_defaults)
	_ok("技能池：三职业各 12（专属 + §12 召唤技，默认栏均在池内）",
		ok_pools
		and ConfigLoader.class_skill_ids("warrior").size() == CLASS_SKILL_COUNT
		and ConfigLoader.class_skill_ids("archer").size() == CLASS_SKILL_COUNT
		and ConfigLoader.class_skill_ids("mage").size() == CLASS_SKILL_COUNT)


# =============================================================================
# B. 存档 v5
# =============================================================================

func _test_save_v5() -> void:
	print("--- B. 存档 v5（skill_bar / 符文 / 分支 / 图鉴落盘 + 迁移）---")
	var slot := 0
	if SaveManager.slot_exists(slot):
		SaveManager.delete_slot(slot)
	var data := SaveManager.create_new_slot(slot, "archer")
	_ok("新建弓箭手档：skill_bar = 职业默认栏", data != null
		and data.skill_bar == ["piercing_shot", "arrow_rain", "venom_shot"]
		and data.save_version == GameConstants.SAVE_VERSION)
	_ok("新建档：符文/分支/图鉴三项均为空（v5 新字段有落点）", data != null
		and data.skill_runes.is_empty()
		and data.skill_branches.is_empty()
		and data.unlocked_runes.is_empty())
	if data != null:
		data.skill_bar = ["venom_shot", "piercing_shot", "arrow_rain"]
		data.skill_runes = {"venom_shot": ["rune_swift", "rune_fire"]}
		data.skill_branches = {"venom_shot": "poison_cloud"}
		data.unlocked_runes = ["rune_swift", "rune_fire"]
		_ok("改栏 + 装配符文/分支/图鉴后重存并重读：全部保留",
			SaveManager.save_to_slot(slot, data)
			and SaveManager.load_from_slot(slot) != null
			and SaveManager.load_from_slot(slot).skill_bar
				== ["venom_shot", "piercing_shot", "arrow_rain"]
			and SaveManager.load_from_slot(slot).skill_runes
				== {"venom_shot": ["rune_swift", "rune_fire"]}
			and SaveManager.load_from_slot(slot).skill_branches
				== {"venom_shot": "poison_cloud"}
			and SaveManager.load_from_slot(slot).unlocked_runes
				== ["rune_swift", "rune_fire"])
	# v2 → v5 迁移：旧档无 skill_bar / skill_runes / skill_branches / unlocked_runes
	var legacy := {
		"save_version": 2, "slot": 1, "class_id": "mage",
		"account_level": 1, "gold": 0, "inventory": [], "stash": [],
		"equipped": {}, "unlocked_talent_nodes": [], "cleared_levels": [],
		"display_name": "法师 · Lv.1", "created_at": 0, "updated_at": 0,
	}
	var migrated := SaveData.from_dict(legacy)
	var mig_ok := migrated != null and migrated.migrate()
	_ok("v2 旧档迁移：skill_bar 补法师默认栏 + 三项新字段补空 + 版本升到 %d"
		% GameConstants.SAVE_VERSION, mig_ok
		and migrated != null
		and migrated.skill_bar == ["fireball", "frost_nova", "lightning_chain"]
		and migrated.skill_runes.is_empty()
		and migrated.skill_branches.is_empty()
		and migrated.unlocked_runes.is_empty()
		and migrated.save_version == GameConstants.SAVE_VERSION)
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
	# 账号等级抬到 20 ⇒ 技能解锁闸门全开（B4-4 / 1-L11 起，技能按 `unlock_level` 灰显）。
	# 否则 L1 账号下除前 3 个初始技能外全被锁，D 段的装配/重排断言全部失效。
	data.account_level = 20
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
	# 2026-09-30：據點已由「文字按鈕條」改成營地整圖 + 透明熱區（熱區鈕**不設 text**，
	# 否則文字會撐大按鈕最小尺寸、改變點擊區）⇒ 改用 `Hotspot_<panel_id>` 命名取鈕。
	var btn := _find_button_by_name(_hub, "Hotspot_skills")
	_ok("據點含「技能」熱區（Hotspot_skills）", btn != null)
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
	_ok("战士池卡 12 张（GridContainer 子节点）",
		sp._pool_grid.get_child_count() == CLASS_SKILL_COUNT)
	var slot_names := _bar_slot_names(sp)
	_ok("出战槽 3 个 = 裂斩 / 旋刃 / 突进（默认栏）",
		slot_names.size() == 3 and slot_names == ["裂斩", "旋刃", "突进"])
	_ok("「恢复默认」「保存配置」按钮存在",
		_find_button(sp, "恢复默认") != null and _find_button(sp, "保存配置") != null)
	# 符文图鉴（第 7 项）
	var codex_btn := _find_button_by_name(_hub, "Hotspot_rune_codex")
	_ok("據點含「符文圖鑑」熱區（Hotspot_rune_codex，第 7 项）", codex_btn != null)
	_ok("符文图鉴面板已构建（据点 _enter 预建全部面板）",
		_hub.get_panel("rune_codex") != null)
	if codex_btn != null:
		codex_btn.pressed.emit()
		await _wait_frames(2)
		_ok("符文图鉴已打开（is_panel_visible）",
			_hub.is_panel_visible("rune_codex"))
		var cp := _hub.get_panel("rune_codex") as RuneCodexPanel
		_ok("面板类型 RuneCodexPanel", cp != null)
		if cp != null:
			var grid := cp.find_child("RuneGrid", true, false)
			_ok("符文图鉴网格 24 格（6×4）",
				grid != null and grid.get_child_count() == 24)
			_ok("符文图鉴进度 = 0 / 24（新档未解锁任何符文）",
				cp.unlock_progress() == Vector2i(0, 24))
			cp.select_rune("rune_swift")
			await _wait_frames(1)
			_ok("选中符文后详情可渲染（selected_rune 钩子）",
				cp.selected_rune() == "rune_swift")


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
	# 2) 点击出战槽 1 → 打开详情（v5 起不再直接卸下）→ 详情里「从出战栏卸下」
	sp._bar_row.get_child(0).get_node("BarBtn0").pressed.emit()
	await _wait_frames(1)
	_ok("点击出战槽 1 → 打开技能详情浮层（不是直接卸下）",
		sp.is_detail_open() and sp.detail_skill_id() == "cleave"
		and sp.bar == ["cleave", "spin_slash", "dash_strike"])
	_find_button_by_name(_hub, "DetailUnequip").pressed.emit()
	await _wait_frames(1)
	_ok("详情里「从出战栏卸下」→ 卸下裂斩",
		sp.bar == ["spin_slash", "dash_strike"]
		and sp._info.text.contains("已卸下"))
	# 3) 装配蓄力斩 → 自动补到末尾
	_find_button_by_name(sp, "PoolBtn_power_strike").pressed.emit()
	await _wait_frames(1)
	_ok("点击池卡蓄力斩 → 装配到空位",
		sp.bar == ["spin_slash", "dash_strike", "power_strike"])
	# 4) 重排：卸下旋刃 → 重装裂斩 → [突进, 蓄力斩, 裂斩]
	sp._bar_row.get_child(0).get_node("BarBtn0").pressed.emit()
	await _wait_frames(1)
	_find_button_by_name(_hub, "DetailUnequip").pressed.emit()
	_find_button_by_name(sp, "PoolBtn_cleave").pressed.emit()
	await _wait_frames(1)
	_ok("重排生效（卸旋刃 → 装裂斩 → [突进,蓄力斩,裂斩]）",
		sp.bar == ["dash_strike", "power_strike", "cleave"])
	# 5) 保存 → 内存 + 落盘
	var save_btn := _find_button(sp, "保存配置")
	save_btn.pressed.emit()
	await _wait_frames(2)
	_ok("保存后存档 skill_bar = [突进,蓄力斩,裂斩]",
		SaveManager.current_data != null
		and SaveManager.current_data.skill_bar == ["dash_strike", "power_strike", "cleave"])
	var reloaded := SaveManager.load_from_slot(0)
	_ok("重新读档：技能栏仍在磁盘（v%d）" % GameConstants.SAVE_VERSION,
		reloaded != null
		and reloaded.skill_bar == ["dash_strike", "power_strike", "cleave"]
		and reloaded.save_version == GameConstants.SAVE_VERSION)
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
