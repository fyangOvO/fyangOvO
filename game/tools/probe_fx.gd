extends Node
## 特效表探針（2026-09-28）
##
## 為什麼需要：`fx.json` 條目 + PNG 檔案**都對了也不代表能載** ——
##   · 缺 `.import` ⇒ `texture_for()` 回 null；
##   · `frames` / `frame_w` 與實際貼圖寬度不符 ⇒ 播放時會**取到貼圖外的區域**（靜默出錯）。
## 本探針把「表 ↔ 檔」的契約實際比對一次。
##
## 用法： "<Godot>" --headless --path . tools/probe_fx.tscn

func _ready() -> void:
	FxTable.clear_cache()
	var ids: Array = FxTable.all_ids()
	ids.sort()
	var ok := 0
	var bad: Array = []
	for id in ids:
		var sp: Dictionary = FxTable.spec(id)
		var t: Texture2D = FxTable.texture_for(id)
		if t == null:
			bad.append("%s(無貼圖)" % id)
			continue
		var fw := int(sp.get("frame_w", 0))
		var fh := int(sp.get("frame_h", 0))
		var n := int(sp.get("frames", 0))
		if fw <= 0 or fh <= 0 or n <= 0:
			bad.append("%s(spec 不完整)" % id)
			continue
		var want := Vector2(fw * n, fh)
		if t.get_size() != want:
			bad.append("%s 尺寸%s≠契約%s" % [id, t.get_size(), want])
			continue
		ok += 1
	print("[fx] 通過 %d / %d" % [ok, ids.size()])
	if not bad.is_empty():
		print("[fx] 失敗： %s" % ", ".join(bad))

	# 元素命中接線自檢：JuiceFX.ELEMENT_HIT_FX 指到的 id 必須真的存在
	var wired: Array = []
	for k in ["fire", "cold", "lightning", "poison", "shadow"]:
		var eid: String = str(JuiceFX.ELEMENT_HIT_FX.get(k, ""))
		wired.append("%s→%s%s" % [k, eid, "✓" if ids.has(eid) else "✗"])
	print("[fx] 元素命中接線： %s" % ", ".join(wired))
	# 物理刻意不在表內（§A.7：複用 hit_spark）
	print("[fx] physical 走兜底 hit_spark： %s" % ("OK" if not JuiceFX.ELEMENT_HIT_FX.has("physical") else "意外有專屬"))
	get_tree().quit()
