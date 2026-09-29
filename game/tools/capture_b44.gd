## B4-4 目视确认抓图（1-L13 / 1-L14 / 1-L12 · 开发用，不属于游戏玩法）
##
## 用法：
##   APPDATA='C:\Users\11265\AppData\Roaming' "<Godot>" --path . tools/capture_b44.tscn
##   输出：D:/七傳說/deliverables/gstack/b44_shot/*.png
##
## 为什么必须真渲染抓图：`1-L13` 的三标识是**纯 `_draw()` 绘制**（等级角标 / 符文圆点 /
## 分支色框），`1-L14` 的两层结构与 `1-L12` 的 24 格图鉴都是**布局**——
## `verify_skill_ext` 只能断言到「字段与钩子」，证明不了「画出来看得见、不重叠、不糊」。
## 本项目已多次栽在「数据通了但没人消费 / 画不出来」（`UISkin` 静默返回 null 那类）。
##
## 四张：
##   ① 技能栏三标识（槽 1 = 2 符文 + 分支 A 金框 / 槽 2 = 1 符文 + 分支 B 紫框 / 槽 3 = 裸）
##   ② 技能面板第一层（4×3 = 12 池卡 + 右侧 3 槽出战栏）
##   ③ 技能详情浮层（等级条 + 符文槽 3 + 分支二选一）
##   ④ 符文图鉴（6×4 = 24 格，含未解锁锁标记）
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/b44_shot"
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

var _ui_root: Control = null
var _panel: SkillPanel = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var bg := ColorRect.new()
	bg.color = Color("1A1E24")
	bg.size = Vector2(640.0, 360.0)
	bg.z_index = -10
	add_child(bg)

	var title := Label.new()
	title.text = "B4-4 · 技能扩展 UI（1-L12 / 1-L13 / 1-L14）"
	title.position = Vector2(12.0, 6.0)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("8FA0B4"))
	add_child(title)

	# 全屏 UI 层（详情浮层的宿主；hub 里对应 `_ui_layer` 这个 CanvasLayer）。
	# ⚠️ 必须用 CanvasLayer 承载：`Control` 直接挂在 `Node2D` 下拿不到视口尺寸
	#    （size 恒为 0）⇒ 详情浮层的 `PRESET_CENTER` 会算到 (0,0)，整块跑到屏幕左上角外。
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)
	_ui_root = Control.new()
	_ui_root.name = "UIRoot"
	_ui_root.size = Vector2(640.0, 360.0)
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui_root)

	# ---- 测试存档：账号 22（技能全解锁）+ 符文 / 分支 / 图鉴 ----
	var data := SaveData.create_new(0, "archer")
	data.account_level = 22
	data.skill_bar = ["piercing_shot", "venom_shot", "arrow_rain"]
	data.skill_runes = {
		"piercing_shot": ["rune_swift", "rune_fire"],
		"venom_shot": ["rune_pierce"],
	}
	data.skill_branches = {
		"piercing_shot": "proj_sharp",   # 模板第 1 个 ⇒ 金框
		"venom_shot": "proj_scatter",    # 模板第 2 个 ⇒ 紫框
	}
	data.unlocked_runes = [
		"rune_swift", "rune_fire", "rune_cold", "rune_lightning", "rune_pierce",
		"rune_split", "rune_chain", "rune_echo", "rune_heavy", "rune_leech",
		"rune_stun", "rune_barrier",
	]
	SaveManager.current_data = data

	# ---- 玩家（提供真实的 SkillController：符文 / 分支 / 技能等级）----
	var player := PLAYER_SCENE.instantiate() as PlayerController
	add_child(player)
	await _frames(4)
	var sc := player.get_skill_controller()
	sc._load_skills()
	sc.set_equipped_runes("piercing_shot", ["rune_swift", "rune_fire"])
	sc.set_equipped_runes("venom_shot", ["rune_pierce"])
	sc.set_equipped_branch("piercing_shot", "proj_sharp")
	sc.set_equipped_branch("venom_shot", "proj_scatter")
	# 技能等级 6（注入 5 + 基准 1）⇒ 符文槽 1/2 已解锁、第 3 槽仍锁
	player.apply_combat_stats(
		{"attack": 100.0, "crit_chance": -100.0, "skill_level": 5.0}, 22)

	# ---- ① 技能栏三标识 ----
	var bar := SkillBarUI.new()
	bar.position = Vector2(20.0, 40.0)
	_ui_root.add_child(bar)
	await _frames(2)
	bar.setup(sc)
	await _frames(3)
	await _shot("b44-1-技能栏三标识.png")
	bar.queue_free()
	await _frames(2)

	# ---- ② 技能面板第一层 ----
	_panel = SkillPanel.new()
	_panel.position = Vector2(120.0, 40.0)
	_ui_root.add_child(_panel)
	await _frames(3)
	_panel.attach_overlay_host(_ui_root)
	_panel.bind("archer", ConfigLoader.class_skill_ids("archer"), data.skill_bar,
		func(_b: Array[String]) -> void: pass,
		{
			"runes": data.skill_runes,
			"branches": data.skill_branches,
			"account_level": data.account_level,
			"cleared_levels": data.cleared_levels,
			"skill_level": 6,
		})
	await _frames(3)
	await _shot("b44-2-技能面板第一层.png")

	# ---- ③ 技能详情浮层 ----
	_panel._open_detail("piercing_shot")
	await _frames(3)
	await _shot("b44-3-技能详情浮层.png")
	_panel._close_detail()
	await _frames(2)

	# ---- ④ 符文图鉴 ----
	_panel.visible = false   # 图鉴单独出图，避免与技能面板叠在一起
	var codex := RuneCodexPanel.new()
	codex.position = Vector2(40.0, 30.0)
	_ui_root.add_child(codex)
	await _frames(2)
	codex.bind(data.unlocked_runes, 6)
	codex.select_rune("rune_swift")
	await _frames(3)
	await _shot("b44-4-符文图鉴.png")

	print("[Capture] 完成 → %s" % OUT_DIR)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	img.save_png(path)
	print("[Capture] 已保存 %s" % path)
