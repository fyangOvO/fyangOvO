## 工具：debug_armor_tex.gd（檢查引擎加載的分件紋理與磁盤素材是否一致；**非玩法**）
## 用法：godot --headless --path "D:/七傳說/game" res://tools/debug_armor_tex.tscn
extends Node2D

const OUT_DIR: String = "D:/七傳說/.workbuddy-ai/scratch"


func _ready() -> void:
	_run()


func _run() -> void:
	for tex_path in [
		"res://assets/pack/armor/helm_hide/armor_helm_hide_idle_e_03.png",
		"res://assets/pack/armor/chest_chainmail/armor_chest_chainmail_idle_e_03.png",
		"res://assets/pack/armor/gloves_leather/armor_gloves_leather_idle_e_03.png",
		"res://assets/pack/armor/legs_plate/armor_legs_plate_idle_e_03.png",
		"res://assets/pack/armor/boots_wanderer/armor_boots_wanderer_idle_e_03.png",
	]:
		var tex: Texture2D = load(tex_path)
		if tex == null:
			print("[MISS] ", tex_path)
			continue
		var img: Image = tex.get_image()
		var name: String = tex_path.get_file().replace(".png", "_loaded.png")
		img.save_png(OUT_DIR + "/" + name)
		print("[OK] 已保存引擎加载纹理 -> ", OUT_DIR + "/" + name, " size=", img.get_size())
	print("===== 完成 =====")
	get_tree().quit(0)
