extends Node
## 臨時探針（2026-10-21）：確認三職業新畫風素材包含 sprint/jump/block 專用動作幀。
func _ready() -> void:
	var ids := ["warrior", "archer", "mage"]
	for id in ids:
		var r := EnemyBase.pack_load_set(id)
		if not bool(r["ok"]):
			print("[probe] %s FAIL ok=false" % id)
			continue
		var clips: Dictionary = r["clips"]
		var parts: Array[String] = []
		for a in ["idle", "walk", "attack", "sprint", "jump", "block", "cast", "hurt", "death"]:
			if clips.has(a):
				var by_dir: Dictionary = clips[a]
				var e_frames: int = (by_dir.get("e", []) as Array).size()
				var n_frames: int = (by_dir.get("n", []) as Array).size()
				parts.append("%s=e%d/n%d" % [a, e_frames, n_frames])
			else:
				parts.append("%s=MISS" % a)
		print("[probe] %s | %s" % [id, " ".join(parts)])
	get_tree().quit()
