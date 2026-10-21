## 工具：verify_focus_quiver.gd（子批4c focus/quiver 素材可用性；**非玩法**）
## focus 法器 / quiver 箭袋為副手原型（數據側暫無裝備模板），補產後驗證：
##   8 方向幀全部可 load、192×192、有非透明像素、幀名與引擎拼幀約定一致。
extends Node2D

const OUT_KEYS: Array[String] = ["focus", "quiver"]
const DIRS: Array[String] = ["e", "w", "n", "s", "ne", "se", "sw", "nw"]

var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 30.0)
	print("===== focus/quiver 素材可用性 =====")
	for key in OUT_KEYS:
		for d in DIRS:
			var path := "res://assets/pack/weapons/%s/weapon_%s_%s.png" % [key, key, d]
			var tex := load(path) as Texture2D
			_ok("%s: %s 幀可 load（%s）" % [key, d, path], tex != null)
			if tex == null:
				continue
			_ok("%s: %s 幀 192×192" % [key, d],
				tex.get_width() == 192 and tex.get_height() == 192)
			# 非透明像素存在（非空白幀）
			var img := tex.get_image()
			var alpha_ok := false
			if img != null:
				var data := img.get_data()
				for i in range(0, data.size(), 4):
					if data[i + 3] > 0:
						alpha_ok = true
						break
			_ok("%s: %s 幀有內容（非透明）" % [key, d], alpha_ok)
	# 引擎拼幀約定：weapon_<key>_<dir>.png（_refresh_weapon_sprite）——已由上面路徑覆蓋
	print("===== 結果：%d 項失敗 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
