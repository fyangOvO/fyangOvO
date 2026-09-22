## 战斗试玩场景（任务 2.2 · 开发用）
##
## 直接开玩的临时测试场：玩家 + 四个色板色靶子 + 跟随相机。
## 操作：WASD 移动 / 左键按住攻击（假连段）/ 1 2 3 技能 / 空格闪避。
## 用法：godot --path "D:/七傳說/game" res://tools/playtest.tscn（关闭窗口即退出）
extends Node2D


func _ready() -> void:
	# 相机缩放收敛到单一常量：.tscn 里写死的 zoom 改常量不会同步，
	# 所以这里从 GameConstants.CAMERA_ZOOM_BASE 赋值（此前 .tscn 硬编码 3×，已废弃）。
	var cam := get_node_or_null("Player/Camera2D") as Camera2D
	if cam != null:
		cam.zoom = GameConstants.CAMERA_ZOOM_BASE
	# 靶子上不同色板色，便于肉眼区分
	_color_dummy("DummyFront", Color("3B7A44"))
	_color_dummy("DummySide", Color("6E9BE8"))
	_color_dummy("DummyFar", Color("C42B2B"))
	_color_dummy("DummyBehind", Color("D9A521"))


func _color_dummy(node_name: String, color: Color) -> void:
	var dummy := get_node_or_null(node_name) as DamageDummy
	if dummy != null:
		dummy.damage_display.modulate = color
