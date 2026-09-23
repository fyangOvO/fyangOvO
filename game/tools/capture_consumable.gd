## 工具：capture_consumable.gd（步骤 8A · 消耗品闭环真渲染；**非玩法**）
##
## 用法（**必须去掉 --headless**；小窗 640×360 demo）：
##   godot --path "D:/七傳說/game" res://tools/capture_consumable.tscn
## 产出：局内 HUD 场景 —— 玩家带 3 瓶生命/2 瓶法力药水、快捷栏 Q/R、地面一瓶生命药水
##       掉落，自动喝一次 → 绿色回血飘字 + 数量 3→2 → 截图。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const LOOT_SCENE := preload("res://scenes/loot/loot_drop.tscn")
const QUICK_SLOT_SCRIPT := preload("res://scripts/ui/quick_slot.gd")

var _fail: int = 0


func _ready() -> void:
	print("===== 步骤 8A 消耗品快捷栏抓图（小窗 640×360）=====")
	_run()


func _run() -> void:
	_ok("渲染驱动不是 headless", DisplayServer.get_name() != "headless")

	var p := PLAYER_SCENE.instantiate()
	p.position = Vector2(320, 200)
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame

	# 给玩家药水并压一点血，让回血可被肉眼确认
	p.consumables["life_potion"] = 3
	p.consumables["mana_potion"] = 2
	var max_hp: float = float(p.health.get_max_hp())
	p.health.take_damage(max_hp * 0.45, p)

	# 地面掉落：一瓶生命药水（放远，避免被自动拾取干扰画面）
	var drop := LOOT_SCENE.instantiate() as LootDrop
	drop.setup({"type": "consumable", "item_id": "life_potion", "amount": 1,
		"rarity": -1, "item_level": 1})
	drop.position = Vector2(320 + 120, 200 + 60)
	add_child(drop)

	# HUD：血条 / 蓝条 / 消耗品快捷栏（与 level_scene 布局一致）
	var hud := CanvasLayer.new()
	add_child(hud)
	var hp := HealthBar.new()
	hp.value_kind = "hp"
	hp.target = p
	hp.position = Vector2(24, 128)
	hp.size = Vector2(172, 16)
	hud.add_child(hp)
	var mp := HealthBar.new()
	mp.value_kind = "mana"
	mp.target = p
	mp.position = Vector2(204, 128)
	mp.size = Vector2(96, 16)
	hud.add_child(mp)
	var qs: Control = QUICK_SLOT_SCRIPT.new()
	qs.position = Vector2(368, 296)
	qs.setup(p)
	hud.add_child(qs)

	# 等 0.6s 让画面稳定 → 喝一口生命药水 → 0.25s 截回血飘字（飘字寿命 0.6s，太晚就淡没了）
	await get_tree().create_timer(0.6).timeout
	p.use_consumable("life_potion")
	await get_tree().create_timer(0.25).timeout

	await _capture(OUT_DIR + "/消耗品快捷栏_药水闭环_2026-09-23.png")
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _capture(out: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	_ok("截图 %s（err=%d）" % [out, err], err == OK)
	if err != OK:
		_fail += 1


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
