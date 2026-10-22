## 工具：capture_armor_piece.gd（子批4 防具外觀分件層真渲染目視驗收；**非玩法**）
##
## 用法（**必須去掉 `--headless`**，否則沒有渲染）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_armor_piece.tscn
## 產出：`D:/七傳說/deliverables/gstack/armor_piece_shot/`
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

	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.art_id = "warrior"
	add_child(player)
	player.global_position = Vector2(320, 180)
	await _settle(0.2)

	# ① 只戴兜帽（helm_hide）：頭部部件對齊驗證
	var helm: EquipmentInstance = _mk_instance("helm_hide")
	player.apply_equipment_visual([helm])
	player._facing = PlayerController.Facing8.RIGHT
	player._apply_facing()
	await _settle(0.3)
	await _shot("helm_hide_idle_e.png")

	# ② 兜帽 + 鎖子甲：頭胸同時掛載
	var chest: EquipmentInstance = _mk_instance("chest_chainmail")
	player.apply_equipment_visual([helm, chest])
	await _settle(0.3)
	await _shot("helm_chest_idle_e.png")

	# ③ 攻擊幀：部件隨身體前傾（attack 變體）
	player._perform_attack()
	await _settle(0.12)
	await _shot("helm_chest_attack_e.png")

	# ④ 傳說檔：部件隨稀有度換色（橙）
	player.apply_equipment_visual([helm, chest])
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("helm_golem")
	var legendary_helm := EquipmentInstance.new()
	legendary_helm.template = tpl
	legendary_helm.rarity = GameConstants.Rarity.LEGENDARY
	player.apply_equipment_visual([legendary_helm, _mk_instance("chest_ember")])
	await _settle(0.3)
	await _shot("legendary_pieces_e.png")

	# ⑤ 南朝向（對稱性 / 方向幀）
	player._facing = PlayerController.Facing8.DOWN
	player._apply_facing()
	await _settle(0.3)
	await _shot("pieces_s.png")

	# ⑥ 全職業錨點對齊：archer（頭身比例不同）穿兜帽+鎖子甲
	var archer := PLAYER_SCENE.instantiate()
	archer.art_id = "archer"
	add_child(archer)
	archer.global_position = Vector2(320, 180)
	await _settle(0.2)
	archer._facing = PlayerController.Facing8.RIGHT
	archer._apply_facing()
	archer.apply_equipment_visual([_mk_instance("helm_hide"), _mk_instance("chest_chainmail")])
	await _settle(0.3)
	await _shot("archer_helm_chest_idle_e.png")
	archer.queue_free()
	await _settle(0.1)

	# ⑦ mage（法袍）同樣穿法
	var mage := PLAYER_SCENE.instantiate()
	mage.art_id = "mage"
	add_child(mage)
	mage.global_position = Vector2(320, 180)
	await _settle(0.2)
	mage._facing = PlayerController.Facing8.RIGHT
	mage._apply_facing()
	mage.apply_equipment_visual([_mk_instance("helm_hide"), _mk_instance("chest_chainmail")])
	await _settle(0.3)
	await _shot("mage_helm_chest_idle_e.png")
	mage.queue_free()
	await _settle(0.1)

	# ⑧ 下肢延伸：手套 / 腿甲 / 靴子（warrior，三槽分件）
	player._facing = PlayerController.Facing8.RIGHT
	player._apply_facing()
	player.apply_equipment_visual([
		_mk_instance("gloves_leather"), _mk_instance("legs_plate"), _mk_instance("boots_wanderer")])
	await _settle(0.3)
	await _shot("gloves_legs_boots_idle_e.png")

	# ⑨ 傳說檔：三槽隨稀有度換色（橙）
	var g_leg := EquipmentInstance.new()
	g_leg.template = ConfigLoader.get_equipment_template("legs_plate")
	g_leg.rarity = GameConstants.Rarity.LEGENDARY
	var g_boot := EquipmentInstance.new()
	g_boot.template = ConfigLoader.get_equipment_template("boots_wind")
	g_boot.rarity = GameConstants.Rarity.LEGENDARY
	player.apply_equipment_visual([
		_mk_instance("helm_golem"), _mk_instance("chest_ember"),
		_mk_instance("gloves_cold"), g_leg, g_boot])
	await _settle(0.3)
	await _shot("full5_slot_legendary_e.png")

	# ⑩ archer / mage 下肢分件對齊
	# ⚠️ 先把 ①–⑨ 的 warrior（player）移出畫面，否則會與新職業疊在同一位置（歷史坑）。
	player.global_position = Vector2(1000, 1000)
	await _settle(0.1)
	for cid in ["archer", "mage"]:
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
		for a in ["head_anchor", "chest_anchor", "gloves_anchor", "legs_anchor", "boots_anchor"]:
			var anc: Marker2D = pc.get(a)
			if anc == null:
				print("[DBG] %s %s 錨點缺失" % [cid, a])
				continue
			var sp := anc.get_node_or_null(NodePath("RealArmorPiece"))
			if sp is Sprite2D:
				print("[DBG] %s %s sp.position=%s global=%s tex=%s" % [cid, a, sp.position, sp.global_position, (sp.texture.resource_path if sp.texture != null else "none")])
			else:
				print("[DBG] %s %s 無分件節點" % [cid, a])
		print("[DBG] %s anim_dir=%s facing=%s offset=%s" % [cid, pc._anim_dir, pc._facing, pc._armor_anchor_offset()])
		await _shot("%s_full_set_idle_e.png" % cid)
		pc.queue_free()
		await _settle(0.1)

	print("===== 分件層抓圖完成 =====")
	get_tree().quit(0)
