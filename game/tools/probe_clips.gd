extends Node
## 精靈幀集探針（2026-09-24）：印出 `EnemyBase.resolve_character_set(id)` 的
## **全部動作 × 方向 × 幀數**，用來確認新增素材真的被載入（而不是只有檔案在磁碟上）。
##
## 為什麼需要這支：`res://` PNG **必須有 `.import`** 才會被 `ResourceLoader.exists()` 看到；
## 缺 `.import` ⇒ 該動作**靜默消失、不報錯**（不會有任何 warning，只會「少一個動作」）。
##
## 用法： "<Godot>" --headless --path . tools/probe_clips.tscn
##        （可加 -- 參數指定 id，預設掃三職業）

const DEFAULT_IDS: Array[String] = ["warrior", "archer", "mage"]

func _ready() -> void:
	var ids: Array[String] = DEFAULT_IDS
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		ids = []
		for a in argv:
			ids.append(a)

	print("[clips] Godot %s" % Engine.get_version_info()["string"])
	for who in ids:
		var r: Dictionary = EnemyBase.resolve_character_set(who)
		if not r.get("ok", false):
			print("[clips] %-8s ✗ 解析失敗" % who)
			continue
		var clips: Dictionary = r.get("clips", {})
		var acts: Array = clips.keys()
		acts.sort()
		print("[clips] %-8s source=%s  動作數=%d %s" % [who, r.get("source", "?"), acts.size(), acts])
		for a in acts:
			var dirs: Dictionary = clips[a]
			var ds: Array = dirs.keys()
			ds.sort()
			var parts: Array = []
			for d in ds:
				parts.append("%s:%d" % [d, (dirs[d] as Array).size()])
			print("          %-7s 方向=%d  %s" % [a, ds.size(), ", ".join(parts)])
	# 期望值對照（三職業）
	print("[clips] 期望：idle 8×4 · walk 8×4 · attack 8×4 · cast 8×4 · hurt 8×2 · death 8×4")
	get_tree().quit()
