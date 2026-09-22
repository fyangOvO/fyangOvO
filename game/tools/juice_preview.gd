## 打击感渲染预览（任务 2.8 · 开发用，不属于游戏玩法）
##
## 窗口化运行：依次触发 普通命中飘字 / 玩家受击飘字+闪白 / 暴击橙红大字 /
## 元素飘字 / 敌人死亡像素粒子 + 白色扩散环（敌人按档位色），展示打击感全貌。
## 产物：D:/七傳說/game/build/juice_preview.png
## 用法：
##   godot --path "D:/七傳說/game" res://tools/juice_preview.tscn
extends Node2D

const OUT: String = "D:/七傳說/game/build/juice_preview.png"

var _frame: int = 0
var _enemy: Node = null
var _enemy2: Node = null


func _ready() -> void:
	$Player/Camera2D.position = Vector2.ZERO
	$Player/Camera2D.zoom = Vector2(2.5, 2.5)
	_enemy = $Enemy
	_enemy2 = $Enemy2
	# 敌人放远点（不追玩家），只当打击感展示台
	$Player.position = Vector2(0, 0)


func _process(_delta: float) -> void:
	_frame += 1
	match _frame:
		8:
			EventBus.damage_dealt.emit(_enemy, 42.0, false, GameConstants.ELEMENT_PHYSICAL)
			EventBus.damage_dealt.emit($Player, 23.0, false, GameConstants.ELEMENT_PHYSICAL)
		16:
			EventBus.damage_dealt.emit(_enemy2, 156.0, true, GameConstants.ELEMENT_PHYSICAL)
		24:
			EventBus.damage_dealt.emit(_enemy2, 89.0, false, GameConstants.ELEMENT_FIRE)
		32:
			_enemy.take_damage(999999.0, $Player)  # 真死亡：粒子 + 扩散环 + 掉落（普通怪 暗红）
		38:
			DirAccess.make_dir_recursive_absolute("D:/七傳說/game/build")
			var img := get_viewport().get_texture().get_image()
			var err := img.save_png(OUT)
			print("[juice_preview] 截图：%s err=%d" % [OUT, err])
		60:
			get_tree().quit(0)
