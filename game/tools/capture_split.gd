## 工具：capture_split.gd（同一實例分離渲染：只有分件 / 只有法師 ⇒ 精確偏移；**非玩法**）
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
	var inst := EquipmentInstance.new()
	inst.template = ConfigLoader.get_equipment_template(item_id)
	return inst


func _run() -> void:
	var cid_all: Array[String] = ["warrior", "mage", "archer"]
	for zoom in [4.0, 1.0]:
		await _run_one(cid_all, zoom)
	print("===== 分離渲染診斷完成 =====")
	get_tree().quit(0)


func _run_one(cids: Array, zoom: float) -> void:
	var cam := Camera2D.new()
	cam.zoom = Vector2(zoom, zoom)
	cam.position = Vector2(320, 180)
	add_child(cam)
	print("[CAM] zoom=", cam.zoom, " pos=", cam.position)

	for cid in cids:
		var pc: PlayerController = PLAYER_SCENE.instantiate()
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
		# 朝向對照：LEFT（驗證 flip_h 是否影響主體側向）
		pc._facing = PlayerController.Facing8.LEFT
		pc._apply_facing()
		await _settle(0.3)
		if pc.body_sprite != null:
			print("[SPR-L] flip_h=", pc.body_sprite.flip_h, " anim_dir=", pc._anim_dir,
				" clip0=", (pc._clip[0].resource_path if not pc._clip.is_empty() else "none"))
			pc.body_sprite.visible = false
		for layer in ["WeaponLayer", "FxLayer"]:
			var l := pc.get_node_or_null(NodePath(layer))
			if l != null:
				l.visible = false
		await _settle(0.3)
		await _shot("split_%s_only_pieces_L.png" % cid)
		if pc.body_sprite != null:
			pc.body_sprite.visible = true
		for layer in ["WeaponLayer", "FxLayer"]:
			var l := pc.get_node_or_null(NodePath(layer))
			if l != null:
				l.visible = true
		var al2 := pc.get_node_or_null(NodePath("ArmorLayer"))
		if al2 != null:
			al2.visible = false
		await _settle(0.3)
		await _shot("split_%s_only_body_L.png" % cid)
		# 回到 RIGHT（後續正常拍）
		pc._facing = PlayerController.Facing8.RIGHT
		pc._apply_facing()
		if al2 != null:
			al2.visible = true
		await _settle(0.3)
		# 只有分件（隱藏身體 / 武器 / FX 層）
		if pc.body_sprite != null:
			pc.body_sprite.visible = false
			print("[SPR] body offset=", pc.body_sprite.offset, " scale=", pc.body_sprite.scale,
				" pos=", pc.body_sprite.position, " gx=", pc.body_sprite.global_position,
				" region=", pc.body_sprite.region_enabled, " tex_size=", pc.body_sprite.texture.get_size())
		for layer in ["WeaponLayer", "FxLayer"]:
			var l := pc.get_node_or_null(NodePath(layer))
			if l != null:
				l.visible = false
		await _settle(0.3)
		await _shot("split_z%03d_%s_only_pieces.png" % [int(zoom), cid])
		# 只有法師（隱藏分件層）
		if pc.body_sprite != null:
			pc.body_sprite.visible = true
		for layer in ["WeaponLayer", "FxLayer"]:
			var l := pc.get_node_or_null(NodePath(layer))
			if l != null:
				l.visible = true
		var al := pc.get_node_or_null(NodePath("ArmorLayer"))
		if al != null:
			al.visible = false
		await _settle(0.3)
		await _shot("split_z%03d_%s_only_body.png" % [int(zoom), cid])
		pc.queue_free()
		await _settle(0.1)
	cam.queue_free()
	await _settle(0.1)
