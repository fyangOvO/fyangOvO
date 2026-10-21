## 工具：capture_loot_beam.gd（子批4b DNF 式掉落閃光目視驗收；**非玩法**）
##
## 用法（**必須去掉 `--headless`**，否則沒有渲染）：
##   "C:/.../Godot_v4.7.2-stable_win64_console.exe" --path "D:/七傳說/game" \
##       res://tools/capture_loot_beam.tscn
## 產出：`D:/七傳說/deliverables/gstack/loot_beam_shot/`
##   光束_出生爆發.png   —— epic 光環 / legendary 十字爆閃峰值 / mythic 火環
##   光束_呼吸持續.png   —— 呼吸相位 + 上升粒子持續
##   光束_特殊檔.png     —— set 菱形環 / hidden 六色柱
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/loot_beam_shot"
const LOOT_SCENE := preload("res://scenes/loot/loot_drop.tscn")

var _fail: int = 0
var _prev_pixels: PackedByteArray = PackedByteArray()


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	print("===== DNF 式掉落閃光目視抓圖 =====")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _shot(fname: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	var data := img.get_data()
	var differs := data != _prev_pixels
	_prev_pixels = data
	_ok("截圖 %s（err=%d）" % [fname, err], err == OK)
	_ok("  ↑ 與上一張畫面不同（防凍結畫面）", differs)


## 放一個指定稀有度的裝備掉落物（無彈出動畫 ⇒ _fx_t 從出生即走）
func _spawn_drop(rarity: int, x: float) -> LootDrop:
	var ld := LOOT_SCENE.instantiate() as LootDrop
	ld.setup({ "type": "equipment", "amount": 1, "item_id": "chest_chainmail", "rarity": rarity, "item_level": 1 })
	add_child(ld)
	ld.global_position = Vector2(x, 0.0)
	return ld


func _run() -> void:
	_ok("渲染驅動不是 headless", DisplayServer.get_name() != "headless")

	# 場景：地面 + 相機
	var ground := ColorRect.new()
	ground.color = Color("14171C")
	ground.position = Vector2(-2000, -2000)
	ground.size = Vector2(4000, 4000)
	add_child(ground)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.2, 1.2)
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector2(0, 0)

	# 五檔：epic 光環 / legendary 爆閃 / mythic 火環（三檔並列拍「出生爆發」）
	var epic := _spawn_drop(GameConstants.Rarity.EPIC, -55.0)
	var legendary := _spawn_drop(GameConstants.Rarity.LEGENDARY, 0.0)
	var mythic := _spawn_drop(GameConstants.Rarity.MYTHIC, 55.0)
	await _step(0.25)
	await _shot("光束_出生爆發.png")
	# 呼吸相位：再等 1s，粒子/脈動進入持續段
	await _step(1.0)
	await _shot("光束_呼吸持續.png")

	# 特殊檔：set 菱形環 / hidden 六色柱（同框對比）
	epic.queue_free()
	legendary.queue_free()
	mythic.queue_free()
	await get_tree().process_frame
	var set_drop := _spawn_drop(GameConstants.Rarity.SET, -30.0)
	var hidden := _spawn_drop(GameConstants.Rarity.HIDDEN, 30.0)
	await _step(0.4)
	await _shot("光束_特殊檔.png")

	# 對照：普通稀有（LINE 漸變柱）保留原樣
	set_drop.queue_free()
	hidden.queue_free()
	await get_tree().process_frame
	var rare_drop := _spawn_drop(GameConstants.Rarity.RARE, 0.0)
	await _step(0.4)
	await _shot("光束_稀有對照.png")
	rare_drop.queue_free()

	_finish()


func _step(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for i in range(frames):
		await get_tree().physics_frame


func _finish() -> void:
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
