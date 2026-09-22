## 工具：capture_step6.gd（步骤 6 · 局内 HUD 真渲染；**非玩法**）
##
## 用法（**必须去掉 --headless**；小窗 640×360 demo）：
##   godot --path "D:/七傳說/game" res://tools/capture_step6.tscn
## 产出：① 血蓝条 + 3 槽技能栏（键位角标）；② 施法后冷却遮罩 + 拾取提示。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables"
var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 90.0)
	print("===== 步骤 6 局内 HUD 抓图（小窗 640×360）=====")
	_run()


func _run() -> void:
	_ok("渲染驅動不是 headless", DisplayServer.get_name() != "headless")
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	var data := SaveManager.create_new_slot(0, "warrior")
	SaveManager.current_data = data
	SaveManager.current_slot = 0
	SceneManager.fade_duration = 0.0
	var level: Node = (load("res://scenes/levels/level.tscn") as PackedScene).instantiate()
	add_child(level)
	if level.has_method("on_scene_entered"):
		level.on_scene_entered({"level_id": "ch1_l01", "difficulty_tier": GameConstants.DifficultyTier.NM1})
	await get_tree().create_timer(1.0).timeout
	_ok("关卡已构建", level._player != null and level._skill_bar != null)
	if level._player == null or level._skill_bar == null:
		get_tree().quit(1)
		return

	# ① 常态：血蓝条 + 技能栏
	await _capture(OUT_DIR + "/局内HUD_血蓝条技能栏_2026-09-22.png")

	# ② 施法 → 冷却遮罩；再弹拾取提示
	var ctrl: Object = level._player.get_skill_controller()
	if ctrl != null and ctrl.get_skill_id_at(0) != "":
		ctrl.try_cast(ctrl.get_skill_id_at(0))
	level._on_loot_picked_up({"type": "equipment", "item_id": "sword_flame",
		"rarity": GameConstants.Rarity.RARE, "item_level": 14})
	level._on_loot_picked_up({"type": "gold", "amount": 12})
	await get_tree().create_timer(0.5).timeout
	_ok("冷却遮罩出现", bool(level._skill_bar.get_slot_state(0)["on_cd"]))
	_ok("拾取提示出现", level._pickup_toasts != null and level._pickup_toasts.get_child_count() >= 1)
	await _capture(OUT_DIR + "/局内HUD_冷却与拾取提示_2026-09-22.png")

	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _capture(out: String) -> void:
	# 与 capture_step5 同款：等 2 帧让渲染追上，直接读 viewport 纹理（不 await 渲染信号，实测会挂）
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	_ok("截圖 %s（err=%d）" % [out, err], err == OK)
	if err != OK:
		_fail += 1


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
