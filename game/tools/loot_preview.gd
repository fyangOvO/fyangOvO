## 掉落系统渲染预览（任务 2.7 · 开发用，不属于游戏玩法）
##
## 窗口化运行：地面摆一排掉落物（金币 / 魔石 / 白 / 蓝 / 黄 / 紫 / 橙 / 红 / 绿 / 彩），
## 展示物件色块 + 稀有度描边 + 光柱（高度按 RARITY_BEAM_HEIGHTS）。同步截图后退出。
## 产物：D:/七傳說/game/build/loot_preview.png
## 用法：
##   godot --path "D:/七傳說/game" res://tools/loot_preview.tscn
extends Node2D

const OUT: String = "D:/七傳說/game/build/loot_preview.png"

var _frame: int = 0


func _ready() -> void:
	$Camera2D.position = Vector2.ZERO
	$Camera2D.zoom = Vector2(2.5, 2.5)
	# 初始化各掉落物（setup 后 _draw 按类型/稀有度渲染）
	_setup($GoldDrop, { "type": "gold", "amount": 6 })
	_setup($MaterialDrop, { "type": "material", "amount": 2 })
	_setup($DropCommon, { "type": "equipment", "item_id": "sword_iron", "rarity": 0, "item_level": 1 })
	_setup($DropMagic, { "type": "equipment", "item_id": "sword_iron", "rarity": 1, "item_level": 1 })
	_setup($DropRare, { "type": "equipment", "item_id": "sword_iron", "rarity": 2, "item_level": 1 })
	_setup($DropEpic, { "type": "equipment", "item_id": "sword_iron", "rarity": 3, "item_level": 1 })
	_setup($DropLegendary, { "type": "equipment", "item_id": "sword_iron", "rarity": 4, "item_level": 1 })
	_setup($DropMythic, { "type": "equipment", "item_id": "sword_iron", "rarity": 5, "item_level": 1 })
	_setup($DropSet, { "type": "equipment", "item_id": "sword_iron", "rarity": 6, "item_level": 1 })
	_setup($DropHidden, { "type": "equipment", "item_id": "sword_iron", "rarity": 7, "item_level": 1 })


func _setup(drop: Node, entry: Dictionary) -> void:
	if drop.has_method("setup"):
		drop.call("setup", entry)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 50:
		DirAccess.make_dir_recursive_absolute("D:/七傳說/game/build")
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(OUT)
		print("[loot_preview] 截图：%s err=%d" % [OUT, err])
	elif _frame == 70:
		get_tree().quit(0)
