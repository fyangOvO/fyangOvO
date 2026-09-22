## 生命系统渲染预览（任务 2.6 · 开发用，不属于游戏玩法）
##
## 窗口化运行：玩家静止（0,0）；毒史莱姆从下方 90px 走近 → 攻击（玩家掉血 + 中毒 dot）；
## 蜘蛛在右上巡逻（头顶血条可见）。同步截图两帧后退出（无协程/await，绝无卡死风险）。
## 产物：D:/七傳說/game/build/health_preview_full.png / health_preview_hurt.png
## 用法：
##   godot --path "D:/七傳說/game" res://tools/health_preview.tscn
extends Node2D

const OUT_FULL: String = "D:/七傳說/game/build/health_preview_full.png"
const OUT_HURT: String = "D:/七傳說/game/build/health_preview_hurt.png"

## 帧 45（≈0.75s）：玩家满血，史莱姆追击中；帧 200（≈3.3s）：玩家已被毒打掉血 + 中毒
var _frame: int = 0


func _ready() -> void:
	$Camera2D.position = Vector2(0, 0)
	$Camera2D.zoom = Vector2(2.5, 2.5)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 45:
		_save_now(OUT_FULL, "满血帧（HUD 血条满 + 敌人头顶血条）")
	elif _frame == 200:
		_save_now(OUT_HURT, "受伤帧（玩家被毒史莱姆攻击掉血）")
	elif _frame == 220:
		get_tree().quit(0)


## 同步截图：process 阶段 readback 拿到的是上一帧已渲染画面（差 1 帧无感知差异）
func _save_now(path: String, label: String) -> void:
	DirAccess.make_dir_recursive_absolute("D:/七傳說/game/build")
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[health_preview] %s：%s err=%d" % [label, path, err])
