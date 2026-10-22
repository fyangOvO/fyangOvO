## 工具：capture_parts.gd（部位級錨點驗證；**非玩法**）
## 用法（必須去 --headless）：Godot_v4.7.2-stable_win64_console.exe --path "D:/七傳說/game" res://tools/capture_parts.tscn
extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const OUT_DIR: String = "D:/七傳說/deliverables/gstack/armor_piece_shot"


func _ready() -> void:
	_run()


func _settle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png(OUT_DIR + "/" + name)
	print("[OK] 截圖 ", name)


func _mk_instance(item_id: String) -> EquipmentInstance:
	var tpl: EquipmentData = ConfigLoader.get_equipment_template(item_id)
	var inst := EquipmentInstance.new()
	inst.template = tpl
	return inst


func _run() -> void:
	var cam := Camera2D.new()
	cam.zoom = Vector2(4, 4)
	cam.position = Vector2(320, 180)
	add_child(cam)

	for cid in ["mage", "archer"]:
		var pc := PLAYER_SCENE.instantiate()
		pc.art_id = cid
		add_child(pc)
		pc.global_position = Vector2(320, 180)
		await _settle(0.2)
		pc._facing = PlayerController.Facing8.RIGHT
		pc._apply_facing()
		pc.apply_equipment_visual([
			_mk_instance("helm_hide"), _mk_instance("chest_chainmail"),
			_mk_instance("gloves_leather"), _mk_instance("legs_plate"), _mk_instance("boots_wanderer")])
		await _settle(0.3)
		# 打印每部位錨點偏移
		for a in ["head_anchor", "chest_anchor", "gloves_anchor", "legs_anchor", "boots_anchor"]:
			var anc: Marker2D = pc.get(a)
			if anc == null:
				continue
			var sp := anc.get_node_or_null(NodePath("RealArmorPiece"))
			if sp is Sprite2D:
				var slot: String = a.replace("_anchor", "")
				print("[PT] %s %s offset=%s (查表=%s)" % [cid, slot, sp.offset, pc._armor_anchor_offset(slot)])
		await _shot("%s_full_set_idle_e.png" % cid)
		pc.queue_free()
		await _settle(0.2)

	print("===== 部位級抓圖完成 =====")
	get_tree().quit(0)
