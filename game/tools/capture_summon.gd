## 召喚技能取證：證明「施放召喚技能 → 畫面上真的出現召喚物」。
##
## 為什麼需要它：`tools/verify_summon.tscn` 的 headless 斷言只能證明
## 「場上多了 1 個節點」，證明不了「它有被畫出來」——
## 本專案踩過：PNG 缺 `.import` ⇒ `ResourceLoader.exists()` 回 false ⇒
## 精靈**靜默消失且不報錯**（當時 `cast` 方向數 = 0 就是這樣來的）。
##
## ⚠️ 必須**去掉 `--headless`** 跑（headless 沒有 viewport 可抓，會存出 0 字節 PNG）。
## 用法：
##   "<Godot>" --path . tools/capture_summon.tscn
##
## 取證內容：施放 → 場上數量 → 抓圖。**走技能系統 `try_cast()`**，
## 而不是直接呼叫 `Summon.spawn()` —— 這樣才順帶驗證了「技能接線」真的通。
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const LEVEL_ID: String = "ch1_l01"
const OUT_DIR: String = "D:/七傳說/deliverables/gstack/summon_shot"

var _fail := 0


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _case("summon_spirit_wolf", 0)
	await _case("summon_elemental", 1)
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _case(skill_id: String, idx: int) -> void:
	print("--- 召喚取證：%s ---" % skill_id)
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(3)
	level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	_freeze_enemies(level)
	await _frames(3)

	# 關掉相機平滑，否則把玩家瞬移過去後相機追不上，抓到的還是原地
	var cam := level.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.position_smoothing_enabled = false

	# 把玩家移到敵人最密集處（讓畫面裡同時有敵人與召喚物）
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

	# 走技能系統施放（驗證接線，而不是直接呼叫 Summon.spawn）
	var sc: SkillController = level._player.get_skill_controller()
	_ok("取得 SkillController", sc != null)
	if sc == null:
		level.queue_free()
		return
	# ⚠️ 白盒注入（模擬「玩家已裝備」）：
	#    `SkillController._load_skills()` **只載入出戰欄**（`SaveData.skill_bar`）的技能，
	#    而召喚技能是進「技能池」的（4:1 選擇比）⇒ 沒裝備就 `get_skill_data()` 回 null、
	#    `try_cast()` 必回 false（第一次跑這支工具就是這樣失敗的，實測）。
	#    這裡把技能直接注入控制器並補滿法力（召喚要 30/40 藍），
	#    以便取證「施放 → 召喚物真的被畫出來」。
	var sd := ConfigLoader.get_skill(skill_id)
	sc._skills[skill_id] = sd
	sc._cooldowns[skill_id] = 0.0
	level._player.get_mana_pool().set_current(100.0)
	var cast_ok := sc.try_cast(skill_id)
	_ok("施放 %s → try_cast 回 %s" % [skill_id, str(cast_ok)], cast_ok)

	await _frames(3)
	var summs := get_tree().get_nodes_in_group(&"summons")
	_ok("場上 summons 組節點 = %d（期望 1）" % summs.size(), summs.size() == 1)

	# 讓動畫真的跑起來再抓（idle 有 4 幀）
	await _hold(level, 24)
	await _shot("summon-%d-%s.png" % [idx, skill_id])

	# 順手記錄召喚物的實際解析結果（精靈是否真的載到）
	for s in summs:
		if is_instance_valid(s) and s.has_method("get_summon_id"):
			_ok("召喚物 id = %s" % str(s.call("get_summon_id")),
				str(s.call("get_summon_id")) == skill_id)

	level.queue_free()
	await _frames(3)


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


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
