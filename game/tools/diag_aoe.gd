extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")

func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 60.0)
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.on_scene_entered({"level_id": "ch2_l13", "difficulty_tier": 0})
	for i in 50:
		await get_tree().process_frame
	var boss: EnemyBase = null
	for e in level._alive:
		if e.data != null and e.data.tier == MonsterData.Tier.BOSS:
			boss = e
			break
	print("boss=", boss != null, " player=", boss._player != null if boss != null else "?")
	print("boss parent=", boss.get_parent().name if boss != null else "?")
	var before := level.get_child_count()
	boss._aoe_strike()
	for i in 5:
		await get_tree().process_frame
	print("children before=", before, " after=", level.get_child_count())
	for c in level.get_children():
		var v: Variant = c.get("_radius")
		if v != null:
			print("  telegraph-like: ", c.name, " pos=", c.position, " radius=", v)
	get_tree().quit(0)
