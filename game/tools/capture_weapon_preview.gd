## 武器層掛載真渲染抓圖（臨時驗證用，不進導出包）
## 用法：godot --path "D:/七傳說/game" res://tools/capture_weapon_preview.tscn
## （**不能加 --headless**，否則渲染不推進）
extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables/gstack/weapon_preview"


func _ready() -> void:
	_run()


func _run() -> void:
	var cam := Camera2D.new()
	cam.zoom = Vector2(4, 4)
	cam.position = Vector2(320, 180)
	add_child(cam)
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.art_id = "warrior"
	add_child(player)
	player.global_position = Vector2(320, 180)
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_flame")
	print("[OK] sword 模板存在: ", tpl != null)
	if tpl == null:
		_finish()
		return
	var inst := EquipmentInstance.new()
	inst.template = tpl
	player.apply_equipment_visual([inst])
	await _settle(0.4)
	await _shot("weapon_idle_s.png")
	player._facing = PlayerController.Facing8.RIGHT
	player._apply_facing()
	await _settle(0.2)
	await _shot("weapon_idle_e.png")
	player._perform_attack()
	await _settle(0.18)
	await _shot("weapon_attack_e.png")
	# 防具換色檔驗收（子批3）：同朝向右逐檔抓 idle，驗證預烘主題色變體
	var tiers := {
		"default": -1,
		"magic": GameConstants.Rarity.MAGIC,
		"legendary": GameConstants.Rarity.LEGENDARY,
		"mythic": GameConstants.Rarity.MYTHIC,
	}
	for label in tiers:
		player.set_visual_tier(tiers[label])
		await _settle(0.15)
		await _shot("tier_%s_e.png" % label)
	_finish()


func _settle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png(OUT_DIR + "/" + name)
	print("[OK] 截圖 ", name)


func _finish() -> void:
	print("===== 武器掛載抓圖完成 =====")
	get_tree().quit(0)
