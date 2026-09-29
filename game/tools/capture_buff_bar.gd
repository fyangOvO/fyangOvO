## 臨時增益 HUD 目視確認抓圖（第四步 B4 · 3-B4 · 開發用）
##
## 用法：
##   APPDATA=<臨時目錄> "<Godot>" --path . tools/capture_buff_bar.tscn
##   輸出：D:/七傳說/deliverables/gstack/buff_shot/*.png
##
## 為什麼要這一張：`3-B4` 的驗收條目是「**目視確認** buff 圖標可見」
## （設計案 §2.7A「可观测」硬要求）。`verify_buff` 只證明數據鏈路通，
## 證明不了「畫出來看得見」—— 本項目已多次栽在「生成了但沒人消費 / 畫不出來」。
##
## 做法：不跑整關（需要存檔與關卡定義），而是把 `BuffBarUI` 放到**真實座標**
## （`LevelScene.BUFF_BAR_ORIGIN`）與同尺寸（640×360）的暗底上，旁邊放一條召喚欄做參照，
## 看兩者是否重疊、字是否可讀。
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/buff_shot"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _player: PlayerController = null
var _bar: BuffBarUI = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# ① 640×360 暗底（模擬遊戲畫面）
	var bg := ColorRect.new()
	bg.color = Color("1A1E24")
	bg.size = Vector2(640.0, 360.0)
	add_child(bg)
	# ② 玩家（BuffComponent 的宿主）
	_player = PLAYER_SCENE.instantiate() as PlayerController
	add_child(_player)
	_player.global_position = Vector2(-9999.0, -9999.0) # 移出畫面，只借它的組件
	# ③ 對照組：召喚欄（同一條水平線的下一行）
	var sb := SummonBarUI.new()
	sb.position = LevelScene.SUMMON_BAR_ORIGIN
	add_child(sb)
	# ④ 受測元件
	_bar = BuffBarUI.new()
	_bar.position = LevelScene.BUFF_BAR_ORIGIN
	_bar.source = _player
	add_child(_bar)
	# ⑤ 技能欄位置標記（純文字，確認不重疊）
	var mark := Label.new()
	mark.text = "[技能欄 472,296]"
	mark.position = LevelScene.SKILL_BAR_ORIGIN
	mark.add_theme_color_override("font_color", Color("8FA0B4"))
	add_child(mark)

	await _frames(6)
	await _shot("buff-0-空狀態.png")

	var bc := _player.get_buff_component()
	bc.clear()
	# 正增益 + 疊層 + 負增益 + 限時長短混合
	bc.add_buff_key("all_damage", 12.0, 6.0, "ying_zhe_zhi_hun_jie")
	bc.add_buff_key("move_speed", 15.0, 3.0, "xun_jie_ji_xing_tui")
	bc.add_buff_key("damage_reduction", 5.0, 8.0, "tie_bi_zhong_zhuang_tui")
	bc.add_buff("attack_speed", 15.0, 4.0, "ji_feng_lie_shou_zhua")
	# 疊 9 層（驗證疊層數顯示）
	for _i in range(9):
		bc.add_buff("all_attributes", 8.0, 15.0, "wang_quan_tong_yu_zhui", 9)
	bc.add_buff("enemy_armor_reduction", 10.0, 3.0, "sui_jia_po_jun_quan")
	await _frames(6)
	await _shot("buff-1-六條混合.png")

	bc.clear()
	await _frames(6)
	await _shot("buff-2-清空後.png")

	print("[Capture] 完成 → %s" % OUT_DIR)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	img.save_png(path)
	print("[Capture] 已保存 %s" % path)
