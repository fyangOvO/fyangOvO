## 端到端取證：**在據點的技能面板「裝備」召喚技能 → 進關卡 → 施放 → 抓圖**。
##
## 與 `capture_summon.tscn` 的差別（兩者互補，不是重複）：
##   · `capture_summon` 走「白盒注入 `_skills`」⇒ 驗的是**召喚技能的分派路徑**。
##   · 本工具走**玩家真實操作路徑**：技能面板點擊 → 保存（落 `SaveData.skill_bar`）
##     → `SkillController._load_skills()` 重新載入 → `try_cast()`。
##     ⇒ 這才是「裝備 → 能施放」整條路打完的證據。
##
## ⚠️ 它**會寫存檔**（`SaveManager`）⇒ 必須用隔離的 `APPDATA` 跑：
##   APPDATA=<臨時目錄> "<Godot>" --path . tools/capture_summon_equip.tscn
##   （`run_regression.py::make_isolated_appdata` 就是這個手法；不隔離會動到真實存檔）
## ⚠️ 必須**去掉 `--headless`**（headless 沒 viewport 可抓）。
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const HUB_SCENE: String = "res://scenes/main/hub.tscn"
const LEVEL_ID: String = "ch1_l01"
const OUT_DIR: String = "D:/七傳說/deliverables/gstack/summon_shot"

## 職業 → 召喚技能 id（對應 `classes.json` 的技能池）
const CASES := [
	{"cls": "archer", "skill": "summon_spirit_wolf"},
	{"cls": "mage", "skill": "summon_elemental"},
]

var _fail := 0


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for c in CASES:
		await _case(String(c["cls"]), String(c["skill"]))
	_clean_slots()
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 一個職業的完整鏈路：裝備 → 進關卡 → 施放 → 抓圖
func _case(cls: String, skill_id: String) -> void:
	print("--- 端到端取證：%s / %s ---" % [cls, skill_id])
	_clean_slots()
	var data := SaveManager.create_new_slot(0, cls)
	SaveManager.current_data = data
	SaveManager.current_slot = 0
	_ok("建立 %s 存檔" % cls, data != null)
	if data == null:
		return
	var bar_before: Array = data.skill_bar.duplicate()
	_info("裝備前 skill_bar = %s" % str(bar_before))

	# ── 階段 1：據點 → 技能面板 → 點擊裝備 → 保存 ──────────────────────
	var hub: Node = (load(HUB_SCENE) as PackedScene).instantiate()
	add_child(hub)
	if hub.has_method("on_scene_entered"):
		hub.on_scene_entered({})
	await _wait(0.6)

	var btn := _find_button(hub, "技能")
	_ok("據點按鈕「技能」存在", btn != null)
	if btn == null:
		hub.queue_free()
		return
	btn.pressed.emit()
	await _wait(0.6)
	_ok("技能面板已開啟", bool(hub.call("is_panel_visible", "skills")))

	var sp := hub.call("get_panel", "skills") as SkillPanel
	_ok("取得 SkillPanel", sp != null)
	if sp == null:
		hub.queue_free()
		return
	await _shot("equip-%s-1-面板初始.png" % cls)

	# 玩家操作：點欄位 0（卸下）→ 點池裡的召喚技能（裝上）→ 按保存
	var bar_btn := sp.find_child("BarBtn0", true, false) as Button
	_ok("欄位 0 按鈕存在", bar_btn != null)
	if bar_btn != null:
		bar_btn.pressed.emit()
		await get_tree().process_frame
	# ⚠️ **池按鈕必須在「卸下」之後才查找**：`_on_bar_clicked()` 會呼叫 `_refresh()`，
	#    而 `_refresh()` 會 `queue_free()` 掉 bar/pool 的所有子節點再重建
	#    ⇒ 卸下之前拿到的 `pool_btn` 引用已經失效，`pressed.emit()` 完全沒反應（第一次跑就是這樣失敗的，實測）。
	var pool_btn := _find_button_by_name(sp, "PoolBtn_%s" % skill_id)
	_ok("池內可見 %s" % skill_id, pool_btn != null)
	if pool_btn != null:
		pool_btn.pressed.emit()
		await get_tree().process_frame
	var save_btn := _find_button(sp, "保存技能栏")
	_ok("保存按鈕存在", save_btn != null)
	if save_btn != null:
		save_btn.pressed.emit()
	await _wait(0.6)

	_ok("面板 bar 含 %s（實際 %s）" % [skill_id, str(sp.bar)], (sp.bar as Array).has(skill_id))
	_ok("已落盤到 SaveData.skill_bar（%s）" % str(SaveManager.current_data.skill_bar),
		(SaveManager.current_data.skill_bar as Array).has(skill_id))
	await _shot("equip-%s-2-裝備後保存.png" % cls)
	hub.queue_free()
	await _wait(0.3)

	# ── 階段 2：進關卡 → 不白盒注入 → 直接 try_cast ────────────────────
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	_freeze_enemies(level)
	await _frames(3)

	var cam := level.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.position_smoothing_enabled = false
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

	var sc: SkillController = level._player.get_skill_controller()
	_ok("SkillController 已載入 %s（非白盒注入）" % skill_id,
		sc != null and sc.get_skill_data(skill_id) != null)
	level._player.get_mana_pool().set_current(100.0)
	var cast_ok := sc.try_cast(skill_id) if sc != null else false
	_ok("施放 %s → try_cast 回 %s" % [skill_id, str(cast_ok)], cast_ok)
	await _frames(3)
	var summs := get_tree().get_nodes_in_group(&"summons")
	_ok("場上 summons = %d（期望 1）" % summs.size(), summs.size() == 1)
	await _hold(level, 24)
	await _shot("equip-%s-3-關卡內施放.png" % cls)
	level.queue_free()
	await _frames(3)


func _clean_slots() -> void:
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1


func _freeze_enemies(level: LevelScene) -> void:
	var frozen := 0
	for e in level._alive:
		if not is_instance_valid(e):
			continue
		e.set_physics_process(false)
		e.set_process(false)
		frozen += 1
	print("[Freeze] 已凍結 %d 個敵人的 AI（僅用於抓圖，不改玩法代碼）" % frozen)


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
	_ok("抓圖 %s → %d×%d（err=%d）" % [fname, img.get_width(), img.get_height(), err],
		err == OK and img.get_width() > 0)


## ⚠️ 必須**同時**比對 `text` 與 `name`：
##   · `hub.gd::_build_ui` 的面板切換鈕只設了 `btn.text`（"技能"），`name` 是預設的 `"Button"`
##   · `SkillPanel` 的池按鈕則是設 `name`（`PoolBtn_<id>`），text 是技能顯示名
##   只比對其中一邊就會找不到（第一次跑就是這樣失敗的，實測）。
func _find_button(root: Node, needle: String) -> Button:
	for c in root.get_children():
		if c is Button and (String(c.text).contains(needle) or String(c.name).contains(needle)):
			return c as Button
		var r := _find_button(c, needle)
		if r != null:
			return r
	return null


func _find_button_by_name(root: Node, needle: String) -> Button:
	return _find_button(root, needle)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
