## 集成层验收（阶段 1：启动分流 / 主菜单 / 账号概览）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_integration.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖（随集成层阶段推进而扩充）：
##   A. 集成层四个场景路径已就位（boot / main_menu / hub / self_check）
##   B. 主菜单场景可实例化、能挂上 MainMenuPanel、回调已接线
##   C. `SaveManager.get_account_data()` 存在、键契约完整、有档/无档都正确
##   D. 自检场景可加载（`--verify` 的落点）
##   E. 启动脚本仍是分流器（保留 `on_scene_entered` 契约）
extends Node2D

## 本脚本专用的测试槽位（远离 0 号真实档）
const TEST_SLOT := 6

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 集成层验收（阶段 1：启动流程） =====")
	await _run()
	_finish()


func _run() -> void:
	_check_scene_paths()
	await _check_main_menu_scene()
	_check_account_data()
	_check_self_check_scene()
	_check_boot_dispatcher()


# =============================================================================
# A. 场景路径
# =============================================================================

func _check_scene_paths() -> void:
	_ok("启动分流场景存在：scenes/main/main.tscn",
		ResourceLoader.exists("res://scenes/main/main.tscn"))
	_ok("主菜单场景存在：scenes/main/main_menu.tscn",
		ResourceLoader.exists("res://scenes/main/main_menu.tscn"))
	_ok("自检场景存在：tools/self_check.tscn",
		ResourceLoader.exists("res://tools/self_check.tscn"))
	_ok("SceneManager 已登记主菜单常量且指向 main_menu.tscn",
		SceneManager.SCENE_MAIN_MENU.ends_with("main_menu.tscn"))
	_ok("SceneManager.SCENE_HUB 指向 scenes/main/hub.tscn",
		SceneManager.SCENE_HUB == "res://scenes/main/hub.tscn")


# =============================================================================
# B. 主菜单场景
# =============================================================================

func _check_main_menu_scene() -> void:
	var ps := load("res://scenes/main/main_menu.tscn") as PackedScene
	_ok("主菜单 .tscn 可加载", ps != null)
	if ps == null:
		return

	var menu: Node = ps.instantiate()
	add_child(menu)
	await get_tree().process_frame

	_ok("主菜单根节点是 CanvasLayer（UI 层）", menu is CanvasLayer)

	var panel: MainMenuPanel = null
	for c in menu.get_children():
		if c is MainMenuPanel:
			panel = c
			break
	_ok("主菜单挂载了 MainMenuPanel", panel != null)
	_ok("MainMenuPanel 三个回调已接线（on_start / on_settings / on_quit）",
		panel != null and panel.on_start.is_valid()
		and panel.on_settings.is_valid() and panel.on_quit.is_valid())

	menu.free()


# =============================================================================
# C. 账号概览接口
# =============================================================================

func _check_account_data() -> void:
	_ok("SaveManager.get_account_data() 存在", SaveManager.has_method("get_account_data"))
	if not SaveManager.has_method("get_account_data"):
		return

	# ---- 无存档：必须返回安全默认值，绝不 null ----
	var backup_slot := SaveManager.current_slot
	var backup_data := SaveManager.current_data
	SaveManager.current_slot = -1
	SaveManager.current_data = null
	var empty: Dictionary = SaveManager.get_account_data()
	_ok("无存档时返回默认值而非 null（level=1 / gold=0 / materials=0）",
		int(empty.get("level", 0)) == 1 and int(empty.get("gold", -1)) == 0
		and int(empty.get("materials", -1)) == 0)
	_ok("账号概览含全部 7 个契约键",
		empty.has_all(["level", "xp", "xp_next", "gold", "materials",
			"chapter_bonus", "cleared_count"]))

	# ---- 有存档：逐字段核对 ----
	if SaveManager.slot_exists(TEST_SLOT):
		SaveManager.delete_slot(TEST_SLOT)
	var d := SaveManager.create_new_slot(TEST_SLOT)
	if d == null:
		_ok("测试槽可新建", false)
		SaveManager.current_slot = backup_slot
		SaveManager.current_data = backup_data
		return

	d.account_level = 7
	d.account_xp = 123.0
	d.gold = 4321
	d.add_material("magic_stone", 9)
	d.cleared_levels = ["ch1_l01", "ch1_l02"]
	d.chapter_reputation = {"ch1": 3}
	SaveManager.save_to_slot(TEST_SLOT, d)

	var acc: Dictionary = SaveManager.get_account_data()
	_ok("有存档时概览反映真实值（等级 7 / 金币 4321 / 魔石 9 / 通关 2）",
		int(acc.get("level", 0)) == 7 and int(acc.get("gold", 0)) == 4321
		and int(acc.get("materials", 0)) == 9 and int(acc.get("cleared_count", 0)) == 2)
	_ok("章节声望 3 级 → chapter_bonus = 3%（UI 再 ×100）",
		is_equal_approx(float(acc.get("chapter_bonus", 0.0)), 0.03))
	_ok("xp_next 与 AccountLevel.xp_to_next(7) 一致",
		is_equal_approx(float(acc.get("xp_next", 0.0)), AccountLevel.xp_to_next(7)))
	_ok("脏档防御：声望值超上限被夹紧（120 → 10 级 = 10%）",
		_clamp_probe())

	# ---- 清理 ----
	SaveManager.delete_slot(TEST_SLOT)
	SaveManager.current_slot = backup_slot
	SaveManager.current_data = backup_data
	_ok("清理：测试槽已删除", not SaveManager.slot_exists(TEST_SLOT))


## 往存档里塞一个超上限的声望值，验证 get_account_data 会夹紧而不是算成天文数字
func _clamp_probe() -> bool:
	if not SaveManager.slot_exists(TEST_SLOT):
		return false
	var d := SaveManager.load_from_slot(TEST_SLOT)
	if d == null:
		return false
	d.chapter_reputation = {"ch1": 120}
	SaveManager.save_to_slot(TEST_SLOT, d)
	var acc: Dictionary = SaveManager.get_account_data()
	return is_equal_approx(float(acc.get("chapter_bonus", -1.0)), 0.10)


# =============================================================================
# D. 自检场景
# =============================================================================

func _check_self_check_scene() -> void:
	var ps := load("res://tools/self_check.tscn") as PackedScene
	_ok("自检 .tscn 可加载", ps != null)
	if ps == null:
		return
	# 只查脚本路径，不实例化 —— 实例化会立刻跑完自检并 quit()
	var root: Node = ps.instantiate()
	_ok("自检场景根节点是 Node2D 且挂了 tools/self_check.gd",
		root is Node2D and root.get_script() != null
		and String(root.get_script().resource_path).ends_with("tools/self_check.gd"))
	root.free()


# =============================================================================
# E. 启动分流脚本
# =============================================================================

func _check_boot_dispatcher() -> void:
	var boot := load("res://scripts/core/main.gd") as GDScript
	_ok("启动脚本可加载：scripts/core/main.gd", boot != null)
	if boot == null:
		return

	var names: Array[String] = []
	for m in boot.get_script_method_list():
		names.append(String(m["name"]))
	_ok("启动脚本保留 on_scene_entered 契约（SceneManager 回调式交付）",
		names.has("on_scene_entered"))
	_ok("启动脚本已卸掉自检（不再自带 _run_self_check）",
		not names.has("_run_self_check"))
	_ok("启动脚本登记了自检场景常量 SELF_CHECK_SCENE",
		_load_const_names(boot).has("SELF_CHECK_SCENE"))


func _load_const_names(script: GDScript) -> Array[String]:
	var out: Array[String] = []
	for c in script.get_script_constant_map():
		out.append(String(c))
	return out


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
