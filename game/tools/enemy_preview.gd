## 敌人 AI 渲染预览（任务 2.4 · 开发用，不属于游戏玩法）
##
## 窗口化运行：玩家静止（0,0）；蜘蛛从下方 200px 走近 → 追击 → 贴脸攻击；
## 蝙蝠在左上远处巡逻。按帧数同步截图两帧后退出（无协程/await，绝无卡死风险）。
## 产物：D:/七傳說/game/build/enemy_preview_chase.png / enemy_preview_attack.png
## 用法：
##   godot --path "D:/七傳說/game" res://tools/enemy_preview.tscn
extends Node2D

const OUT_CHASE: String = "D:/七傳說/game/build/enemy_preview_chase.png"
const OUT_ATTACK: String = "D:/七傳說/game/build/enemy_preview_attack.png"

## 帧 60（≈1s）：蜘蛛追击途中；帧 150（≈2.5s）：蜘蛛贴脸攻击中；帧 170：退出
var _frame: int = 0


func _ready() -> void:
	# 敌人已在 .tscn 中 instance（Spider/Bat），脚本只负责镜头
	$Camera2D.position = Vector2(0, 0)
	$Camera2D.zoom = Vector2(2.5, 2.5)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 60:
		_save_now(OUT_CHASE, "追击帧（蜘蛛在途中）")
	elif _frame == 150:
		_save_now(OUT_ATTACK, "攻击帧（蜘蛛贴脸）")
	elif _frame == 170:
		get_tree().quit(0)


## 同步截图：process 阶段 readback 拿到的是上一帧已渲染画面（差 1 帧无感知差异）
func _save_now(path: String, label: String) -> void:
	DirAccess.make_dir_recursive_absolute("D:/七傳說/game/build")
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[enemy_preview] %s：%s err=%d" % [label, path, err])
