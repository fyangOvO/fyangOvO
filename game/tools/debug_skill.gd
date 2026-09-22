extends Node2D

func _ready() -> void:
	for sid in ["frost_nova", "fireball", "lightning_chain", "poison_cloud", "shadow_blink"]:
		var sd := ConfigLoader.get_skill(sid)
		print(sid, " element=", sd.element if sd else "NULL",
			" inELEMENTS=", (GameConstants.ELEMENTS.has(sd.element) if sd else false),
			" validate=", sd.validate() if sd else "NULL")
	get_tree().quit(0)
