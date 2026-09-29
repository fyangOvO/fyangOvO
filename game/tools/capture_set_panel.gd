## 套裝機制面板目視確認抓圖（第四步 B4-2 · 3-S4 · 開發用）
##
## 用法：
##   APPDATA=<臨時目錄> "<Godot>" --path . tools/capture_set_panel.tscn
##   輸出：D:/七傳說/deliverables/gstack/set_shot/*.png
##
## 為什麼要這一張：`3-S4` 的驗收條目是「**真渲染目視確認**」——面板要顯示
## 「已激活機制」（非僅數值）。`verify_set_effects` 只斷言到 Label 文字層，
## 證明不了「畫出來看得見、不重疊、不糊」。本項目已多次栽在
## 「數據通了但沒人消費 / 畫不出來」（`UISkin` 靜默返回 null 那類）。
##
## 做法：640×360 暗底上放真實 `SetPanel`，跑三種穿戴狀態各抓一張：
##   ① 空穿戴（空狀態文案）
##   ② 霜噬 5/6（4 件檔「◆ 已激活」、6 件檔「◇ 未激活」同框 —— 對照最直觀）
##   ③ 三套各 6 件（6 條機制全部激活）
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/set_shot"

var _panel: SetPanel = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_rng.seed = 20260929

	var bg := ColorRect.new()
	bg.color = Color("1A1E24")
	bg.size = Vector2(640.0, 360.0)
	add_child(bg)

	var title := Label.new()
	title.text = "套裝面板 · 已激活機制（B4-2 · 3-S4）"
	title.position = Vector2(12.0, 6.0)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("8FA0B4"))
	add_child(title)

	_panel = SetPanel.new()
	_panel.position = Vector2(12.0, 26.0)
	add_child(_panel)

	await _frames(6)
	var empty: Array[EquipmentInstance] = []
	_panel.show_sets(empty)
	await _frames(6)
	await _shot("set-0-空穿戴.png")

	var five := _make_items("frostbite", 5)
	_panel.show_sets(five)
	await _frames(6)
	await _shot("set-1-霜噬5件（4档激活6档未激活）.png")

	var all: Array[EquipmentInstance] = []
	all.append_array(_make_items("frostbite", 6))
	all.append_array(_make_items("emberpath", 6))
	all.append_array(_make_items("oathkeeper", 6))
	_panel.show_sets(all)
	await _frames(6)
	await _shot("set-2-三套满6件（6条机制全激活）.png")

	print("[Capture] 完成 → %s" % OUT_DIR)
	get_tree().quit(0)


func _make_items(set_id: String, count: int) -> Array[EquipmentInstance]:
	var out: Array[EquipmentInstance] = []
	var info: SetData = ConfigLoader.sets.get(set_id, null)
	if info == null:
		return out
	var tids: Array = info.piece_template_ids
	for i in range(mini(count, tids.size())):
		var tpl := ConfigLoader.get_equipment_template(String(tids[i]))
		if tpl == null:
			continue
		out.append(AffixRoller.roll_full_equipment(tpl, 20, GameConstants.Rarity.SET, _rng))
	return out


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	img.save_png(path)
	print("[Capture] 已保存 %s" % path)
