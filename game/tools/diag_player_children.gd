## 診斷：關卡運行時遍歷 PlayerController 全部子節點，定位玩家腳下「黃色方塊」的確切節點。
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/diag_player_children.tscn
## （--headless 即可：本腳本只查節點狀態，不需渲染）
##
## 輸出：每個 CanvasItem 子節點的 path / class / visible / world_rect；
##       並列出「世界矩形落在玩家原點下方 0~40px」的候選（黃塊嫌疑犯）。
extends Node

const LEVEL_SCENE: String = "res://scenes/levels/level.tscn"
const LEVEL_ID: String = "ch1_l01"

var _fail: int = 0


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 120.0)
	_run()


func _run() -> void:
	print("===== 診斷：PlayerController 子節點 + 玩家腳下候選 =====")
	var level := (load(LEVEL_SCENE) as PackedScene).instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await _frames(4)
	level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _frames(12)
	await get_tree().create_timer(0.5).timeout

	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null:
		print("!! 找不到玩家")
		get_tree().quit(1)
		return
	var p2d := player as Node2D
	print("\n[玩家] %s  global_position=%s" % [player.name, str(p2d.global_position)])

	print("\n--- A. 玩家子樹全部 CanvasItem（遞迴）---")
	_dump(player, player, 0)

	print("\n--- B. 場景中「世界矩形落在玩家原點下方 0~48px、水平 ±40px」的 Sprite2D ---")
	_scan_below(level, p2d.global_position)

	print("\n===== 診斷結束（失敗 %d）=====" % _fail)
	get_tree().quit(0)


func _dump(node: Node, player: Node, depth: int) -> void:
	for c in node.get_children():
		if c is CanvasItem:
			var ci := c as CanvasItem
			var line := "%s%s  [%s]  visible=%s" % [
				"  ".repeat(depth), player.get_path_to(ci), ci.get_class(), str(ci.visible)]
			if ci is Node2D:
				line += "  gp=%s" % str((ci as Node2D).global_position)
			if ci is Sprite2D:
				var s := ci as Sprite2D
				line += "  tex=%s  scale=%s  offset=%s  centered=%s" % [
					("null" if s.texture == null else "%dx%d" % [s.texture.get_width(), s.texture.get_height()]),
					str(s.scale), str(s.offset), str(s.centered)]
				var r := _world_rect(s)
				line += "  world_rect=%s" % str(r)
			print(line)
			_dump(ci, player, depth + 1)


func _world_rect(s: Sprite2D) -> Rect2:
	if s.texture == null:
		return Rect2()
	var r := s.get_rect()                       # 本地（已含 centered/offset，未含 scale）
	var pos := s.global_position + r.position * s.scale
	var size := Vector2(r.size.x * absf(s.scale.x), r.size.y * absf(s.scale.y))
	return Rect2(pos, size)


func _scan_below(root: Node, ppos: Vector2) -> void:
	var hits: int = 0
	var skipped: int = 0
	for n in _all(root):
		if not (n is CanvasItem):
			continue
		var ci := n as CanvasItem
		if not ci.is_visible_in_tree():
			continue
		var r := _approx_rect(ci)
		if r.size == Vector2.ZERO:
			skipped += 1
			continue
		var dx := absf(r.get_center().x - ppos.x)
		var dy := r.get_center().y - ppos.y
		if dx <= 48.0 and dy >= -8.0 and dy <= 56.0:
			hits += 1
			print("  候選 #%d  [%s]  %s" % [hits, ci.get_class(), String(root.get_path_to(ci))])
			print("        rect=%s  modulate=%s  scene_file=%s" % [
				str(r), str(ci.modulate), str(ci.scene_file_path)])
			if ci is Sprite2D:
				var s := ci as Sprite2D
				print("        tex=%s" % ("null" if s.texture == null else
					"%dx%d" % [s.texture.get_width(), s.texture.get_height()]))
			print("        節點鏈：%s" % _chain(ci, root))
	if hits == 0:
		print("  （無候選）")
	else:
		print("  共 %d 個候選（第 1 個即玩家腳下黃塊的最可能來源）" % hits)
	print("  （另有 %d 個 CanvasItem 因無法估算矩形而未掃描，如純 _draw 節點）" % skipped)


## 盡量估算任意 CanvasItem 的世界矩形（Sprite/多邊形/線/Control）。
func _approx_rect(ci: CanvasItem) -> Rect2:
	if ci is Sprite2D:
		return _world_rect(ci as Sprite2D)
	if ci is Polygon2D:
		var p := ci as Polygon2D
		if p.polygon.size() == 0:
			return Rect2()
		var pts := PackedVector2Array()
		for v in p.polygon:
			pts.append(p.global_position + v * p.scale)
		return Rect2(_bounds(pts), Vector2.ZERO)
	if ci is Line2D:
		var l := ci as Line2D
		if l.points.size() == 0:
			return Rect2()
		var pts2 := PackedVector2Array()
		for v in l.points:
			pts2.append(l.global_position + v * l.scale)
		var b := _bounds(pts2)
		return Rect2(b, Vector2(1, 1))
	if ci is Control:
		var r := (ci as Control).get_global_rect()
		if r.position != Vector2.ZERO or r.size != Vector2.ZERO:
			return r
	return Rect2()


func _bounds(pts: PackedVector2Array) -> Vector2:
	var mn := pts[0]
	var mx := pts[0]
	for v in pts:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	return mn


func _chain(n: Node, root: Node) -> String:
	var parts: Array[String] = []
	var cur: Node = n
	while cur != null and cur != root:
		parts.push_front(cur.name)
		cur = cur.get_parent()
	parts.push_front(root.name)
	return "/".join(parts)


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
