extends Node
## 通用 TEX 載入探針（2026-09-28）
##
## 用途：光有檔案 + TEX 表條目**不代表載得到** —— `res://` PNG 必須有 `.import`，
## 否則 `UISkin.texture()` 回 null（**靜默降級、不報錯**）。
##
## 用法： "<Godot>" --headless --path . tools/probe_tex.tscn -- key1 key2 key3 ...
##        傳入 `UISkin.TEX` 的**邏輯名**（不是檔名）。
## 輸出：每鍵 `OK <尺寸>` 或 `MISS null`，末尾給彙總。

func _ready() -> void:
	var keys := OS.get_cmdline_user_args()
	if keys.is_empty():
		print("[tex] 未傳入鍵名。用法： tools/probe_tex.tscn -- <logical_key> ...")
		get_tree().quit()
		return
	var ok := 0
	var miss: Array[String] = []
	var wrong_size: Array[String] = []
	for k in keys:
		if not UISkin.TEX.has(k):
			miss.append("%s(未登記)" % k)
			continue
		var t: Texture2D = UISkin.texture(k)
		if t == null:
			miss.append("%s(檔案載不到)" % k)
			continue
		ok += 1
		# 從 TEX 的檔名推期望尺寸
		var fn: String = str(UISkin.TEX[k])
		var want := expected_size(fn)
		if want.x > 0 and t.get_size() != want:
			wrong_size.append("%s 實=%s 期望=%s" % [k, t.get_size(), want])
	print("[tex] 通過 %d / %d" % [ok, keys.size()])
	if not miss.is_empty():
		print("[tex] 失敗： %s" % ", ".join(miss))
	if not wrong_size.is_empty():
		print("[tex] 尺寸不符： %s" % ", ".join(wrong_size))
	get_tree().quit()

## 由檔名的尺寸尾碼推期望尺寸。
## 支援兩種專案慣例：`..._48.png`（方形）與 `..._256x48.png`（矩形）；
## 無尺寸尾碼（如 `panel.png`）→ 回 ZERO 表「不比對」。
func expected_size(fn: String) -> Vector2:
	var base := fn.get_basename()  # 去掉 .png
	var parts := base.split("_")
	if parts.size() < 2:
		return Vector2.ZERO
	var tag: String = parts[parts.size() - 1]
	if tag.is_valid_int():
		var n := int(tag)
		return Vector2(n, n)
	var segs := tag.split("x")
	if segs.size() == 2 and segs[0].is_valid_int() and segs[1].is_valid_int():
		return Vector2(int(segs[0]), int(segs[1]))
	return Vector2.ZERO
