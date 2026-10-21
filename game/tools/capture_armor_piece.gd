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

	print("===== 分件層抓圖完成 =====")
	get_tree().quit(0)
