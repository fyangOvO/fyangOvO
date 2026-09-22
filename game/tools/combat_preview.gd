## 战斗渲染预览（任务 2.2 · 开发用）
##
## 窗口化运行，播放一小段战斗演示（普攻假连段 + 三技能）后自动截图保存并退出。
## 用途：肉眼确认攻击/技能在真实渲染下的效果（无头模式无法渲染，故需窗口）。
##
## 用法：
##   godot --path "D:/七傳說/game" res://tools/combat_preview.tscn
##   产物：D:/七傳說/game/build/combat_preview.png（自动退出）
extends Node2D

const OUT_PATH: String = "D:/七傳說/game/build/combat_preview_attack.png"
const OUT_PATH_SKILL: String = "D:/七傳說/game/build/combat_preview_skill.png"

var _elapsed: float = 0.0
var _casted_spin := false
var _casted_cleave := false
var _casted_dash := false
var _shot_attack := false
var _shot_skill := false

@onready var _player: PlayerController = $Player
@onready var _skill_controller: SkillController = $Player/SkillController


func _ready() -> void:
	# 演示假连段：按住攻击键持续挥击
	Input.action_press(GameConstants.ACTION_ATTACK)
	# 把镜头对准战场（玩家放屏幕中央），3x 放大让像素角色清晰可见
	$Camera2D.position = Vector2(0, 0)
	$Camera2D.zoom = Vector2(3.0, 3.0)
	# 给三个靶子上不同色板色，便于肉眼区分
	_color_dummy("DummyFront", Color("3B7A44"))
	_color_dummy("DummyNear", Color("3A5FB0"))
	_color_dummy("DummyFar", Color("8C1A1F"))


func _color_dummy(node_name: String, color: Color) -> void:
	var dummy := get_node_or_null(node_name) as DamageDummy
	if dummy != null:
		dummy.damage_display.modulate = color


func _process(delta: float) -> void:
	_elapsed += delta

	# 演示技能节奏：0.8s 旋刃 / 1.4s 裂斩 / 2.0s 突进
	if _elapsed >= 0.8 and not _casted_spin:
		_cast_spin()
	if _elapsed >= 1.4 and not _casted_cleave:
		_cast_cleave()
	if _elapsed >= 2.0 and not _casted_dash:
		_cast_dash()

	if not _shot_attack and _elapsed >= 0.10:
		_screenshot(OUT_PATH, "普攻挥击帧")
		_shot_attack = true
	if not _shot_skill and _elapsed >= 1.15:
		_screenshot(OUT_PATH_SKILL, "技能帧（旋刃）")
		_shot_skill = true

	if _elapsed >= 2.6:
		Input.action_release(GameConstants.ACTION_ATTACK)
		get_tree().quit(0)


func _cast_spin() -> void:
	_cast_hint("旋刃")
	_skill_controller.try_cast("spin_slash")
	_cast_timer()

func _cast_cleave() -> void:
	_cast_hint("裂斩")
	_skill_controller.try_cast("cleave")
	_cast_timer()

func _cast_dash() -> void:
	_cast_hint("突进")
	_skill_controller.try_cast("dash_strike")
	_cast_timer()


## 施放时在目标位置打一个短暂色环（演示技能生效；阶段 6 由真实特效替换）
func _cast_timer() -> void:
	var ring := _make_ring(Color("6E9BE8"))
	ring.position = _player.global_position
	$Fx.add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector2(4.0, 4.0), 0.25)
	tween.tween_property(ring, "modulate:a", 0.0, 0.35)
	tween.tween_callback(ring.queue_free)


func _cast_hint(skill_name: String) -> void:
	print("[combat_preview] 施放：", skill_name)


func _make_ring(color: Color) -> Sprite2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 画一个 1px 圆环（中点圆算法，像素风）
	var c := Vector2i(16, 16)
	var r := 13
	var x := 0
	var y := r
	var d := 3 - 2 * r
	while x <= y:
		for s in [[x, y], [-x, y], [x, -y], [-x, -y], [y, x], [-y, x], [y, -x], [-y, -x]]:
			img.set_pixel(c.x + s[0], c.y + s[1], color)
		x += 1
		if d < 0:
			d = d + 4 * x + 6
		else:
			y -= 1
			d = d + 4 * (x - y) + 10
	var tex := ImageTexture.create_from_image(img)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return spr


func _screenshot(path: String, label: String) -> void:
	# 等两帧再捕获：窗口首帧可能尚未渲染完（过早 readback 会拿到白屏）
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("D:/七傳說/game/build")
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[combat_preview] %s：%s err=%d" % [label, path, err])
