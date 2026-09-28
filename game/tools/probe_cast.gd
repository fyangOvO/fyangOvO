extends Node
## 臨時探針（2026-09-24）：確認 cast 動作是否真的被 pack 解析器吃到。
## 用途：新增 PACK_ACTIONS 的 "cast" 後，驗證 `res://assets/pack/creatures/<id>/` 的
## `char_<id>_cast_<dir>_<NN>.png` 有被載入（而不是只有檔案存在）。

func _ready() -> void:
	for who in ["warrior", "archer", "mage"]:
		var r: Dictionary = EnemyBase.resolve_character_set(who)
		if not r.get("ok", false):
			print("[probe] %s 解析失敗" % who)
			continue
		var clips: Dictionary = r.get("clips", {})
		var actions: Array = clips.keys()
		actions.sort()
		print("[probe] %s  source=%s  動作=%s" % [who, r.get("source", "?"), actions])
		var c: Dictionary = clips.get("cast", {})
		var cdirs: Array = c.keys()
		cdirs.sort()
		var counts: Array = []
		for d in cdirs:
			counts.append("%s:%d" % [d, (c[d] as Array).size()])
		print("        cast 方向數=%d  %s" % [cdirs.size(), ", ".join(counts)])
		var i: Dictionary = clips.get("idle", {})
		var idirs: Array = i.keys()
		idirs.sort()
		var icounts: Array = []
		for d in idirs:
			icounts.append("%s:%d" % [d, (i[d] as Array).size()])
		print("        idle 方向數=%d  %s" % [idirs.size(), ", ".join(icounts)])
	get_tree().quit()
