## B4-3 目视确认抓图（W5-5 / W5-7 · 开发用，不属于游戏玩法）
##
## 用法：
##   APPDATA='C:\Users\11265\AppData\Roaming' "<Godot>" --path . tools/capture_b43.tscn
##   输出：D:/七傳說/deliverables/gstack/b43_shot/*.png
##
## 为什么要这几张：`5-W5-5` / `5-W5-7` 的验收条目里都有「**真渲染目视确认**」——
## `verify_boss_skills` / `verify_objectives` 只断言到节点与数值层，证明不了
## 「画出来看得见、位置对、不糊」。本项目已多次栽在「数据通了但没人消费 /
## 画不出来」（`UISkin` 静默返回 null 那类）。
##
## 三张：
##   ① bone_slam 扇形预警（120° 扇形 + `fx_bone_slam`）
##   ② enrage 全屏红闪（`fx_enrage_flash`）
##   ③ reach_exit 出口传送门（`tile_exit_portal` loop 精灵，摆在地面格上）
extends Node2D

const OUT_DIR: String = "D:/七傳說/deliverables/gstack/b43_shot"
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")

var _boss: EnemyBase = null
var _stub: Node2D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var bg := ColorRect.new()
	bg.color = Color("1A1E24")
	bg.size = Vector2(640.0, 360.0)
	# ⚠️ 必须压到最底层：出口传送门是 `z: below_actors`（z_index = -1），
	#    背景若留在 0 层就会把它整个盖住（第一次抓图实测踩到）。
	bg.z_index = -10
	add_child(bg)

	var title := Label.new()
	title.text = "B4-3 · BOSS 标志性技能 + 关卡目标（W5-5 / W5-7）"
	title.position = Vector2(12.0, 6.0)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("8FA0B4"))
	add_child(title)

	# 假玩家（扇形判定需要「面朝玩家」）
	_stub = Node2D.new()
	_stub.name = "StubPlayer"
	_stub.add_to_group(&"player")
	add_child(_stub)

	_boss = ENEMY_SCENE.instantiate() as EnemyBase
	_boss.monster_id = "boss_bone_tyrant"
	_boss.level = 7
	_boss.difficulty_tier = GameConstants.DifficultyTier.NM1
	# ⚠️ 顺序不能反：`_ready()` 会读 monster_id / level 去建属性
	add_child(_boss)
	await _frames(4)
	_boss.set_physics_process(false)
	_boss.global_position = Vector2(200.0, 200.0)
	_stub.global_position = Vector2(330.0, 200.0)
	_boss._player = _stub
	_boss.facing = Vector2.RIGHT

	# ① bone_slam 扇形预警
	_boss._bone_slam()
	await _frames(3)
	await _shot("b43-1-bone_slam扇形预警.png")
	# 用**真实时间**等（headless 下帧率不受限，「30 帧」可能只有几十毫秒）
	await get_tree().create_timer(1.2).timeout

	# ② enrage 全屏红闪
	_boss._enrage_fx_played = false
	_boss._apply_boss_phase(4)
	await _frames(2)
	await _shot("b43-2-enrage全屏红闪.png")
	await get_tree().create_timer(1.2).timeout

	# ③ reach_exit 出口传送门
	FxTable.spawn("tile_exit_portal", Vector2(420.0, 260.0), {"host": self})
	await _frames(4)
	await _shot("b43-3-reach_exit出口传送门.png")

	print("[Capture] 完成 → %s" % OUT_DIR)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	img.save_png(path)
	print("[Capture] 已保存 %s" % path)
