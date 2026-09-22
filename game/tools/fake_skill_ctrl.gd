## 验证辅助：技能栏鸭子控制器（SkillBarUI 只读查询接口）
extends Object

## cleave 冷却 8s 剩余 5s；其余无冷却
var _cd: Dictionary = {"cleave": 5.0}
var _total: Dictionary = {"cleave": 8.0, "spin_slash": 6.0, "dash_strike": 8.0}
var _ids: Array[String] = ["cleave", "spin_slash", "dash_strike"]


func get_skill_id_at(index: int) -> String:
	if index < 0 or index >= _ids.size():
		return ""
	return _ids[index]


func is_on_cooldown(id: String) -> bool:
	return float(_cd.get(id, 0.0)) > 0.0


func get_cooldown_remaining(id: String) -> float:
	return float(_cd.get(id, 0.0))


func get_skill_data(id: String) -> Dictionary:
	return {"cooldown": float(_total.get(id, 1.0))}
