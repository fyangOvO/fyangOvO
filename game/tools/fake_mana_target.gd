## 验证辅助：法力目标（HealthBar 法力模式读 target.get_mana_pool()）
extends Node

var mana_pool: ManaPool = null


func get_mana_pool() -> ManaPool:
	return mana_pool
