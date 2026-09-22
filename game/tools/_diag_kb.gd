extends Node
## 临时诊断（用完即删）：列出敌人实例的全部子节点

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")


func _ready() -> void:
	var e := ENEMY_SCENE.instantiate()
	add_child(e)
	await get_tree().physics_frame
	print("DIAG 敌人实例共 %d 个子节点：" % e.get_child_count())
	for c in e.get_children():
		print("DIAG   · %s  class=%s" % [c.name, c.get_class()])
	var direct := e.get_node_or_null("CollisionShape2D")
	print("DIAG get_node_or_null(\"CollisionShape2D\") = %s" % str(direct))
	print("DIAG 全树搜索 CollisionShape2D：")
	for n in e.find_children("*", "CollisionShape2D", true, false):
		print("DIAG   found %s disabled=%s" % [str(n), str(n.disabled)])
	print("DIAG 敌人自身 get_hit_radius() = %.1f" % e.call("get_hit_radius"))
	get_tree().quit(0)
