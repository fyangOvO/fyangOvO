## 精英词缀怪系统（任务 6.2 · class_name 纯静态）
##
## GDD 6.2「怪物种类与精英 / 词缀怪」——词缀怪为工程侧默认实现：
##   精英死亡 / 刷怪时按权重附加 1–2 条词缀，词缀改变行为与数值。
##   词缀池（数据驱动常量，仅精英可用）：
##     急速 haste     移速 ×1.35
##     吸血 lifesteal 攻击回复自身 HP（伤害 ×20%）
##     爆炸 explosive 死亡时对周围 40px 造成 80% 攻击伤害
##     回响 echo      攻击 30% 概率二连击
##     荆棘 thorn     受击反弹 15% 伤害
##     闪现 phasing   每 6 秒瞬移到玩家附近
class_name AffixController
extends RefCounted

const AFFIXES := {
	"haste": {"name": "急速", "move_mult": 1.35},
	"lifesteal": {"name": "吸血", "heal_ratio": 0.2},
	"explosive": {"name": "爆炸", "radius": 40.0, "dmg_ratio": 0.8},
	"echo": {"name": "回响", "chance": 0.3},
	"thorn": {"name": "荆棘", "reflect_ratio": 0.15},
	"phasing": {"name": "闪现", "interval": 6.0},
}
const WEIGHTS := {"haste": 100.0, "lifesteal": 80.0, "explosive": 70.0,
	"echo": 60.0, "thorn": 60.0, "phasing": 50.0}


## 随机 1–2 条词缀（不重复）
static func roll_affixes(rng: RandomNumberGenerator, count: int = -1) -> Array[String]:
	if count < 0:
		count = 1 if rng.randf() < 0.6 else 2
	var pool: Array[String] = []
	for key in AFFIXES:
		pool.append(key)
	var out: Array[String] = []
	for i in mini(count, pool.size()):
		var total := 0.0
		for a in pool:
			total += float(WEIGHTS.get(a, 50.0))
		var roll := rng.randf() * total
		var acc := 0.0
		var pick := ""
		for a in pool:
			acc += float(WEIGHTS.get(a, 50.0))
			if roll <= acc:
				pick = a
				break
		if pick.is_empty():
			pick = pool[0]
		out.append(pick)
		pool.erase(pick)
	return out


## 数值乘法汇总（HP / DMG / 移速）
static func get_multipliers(affixes: Array[String]) -> Dictionary:
	var hp := 1.0
	var dmg := 1.0
	var move := 1.0
	for a in affixes:
		var def: Dictionary = AFFIXES.get(a, {})
		move *= float(def.get("move_mult", 1.0))
		if a == "lifesteal":
			dmg *= 1.0  # 吸血不加成数值
	return {"hp": hp, "dmg": dmg, "move": move}


static func has(affixes: Array[String], affix: String) -> bool:
	return affixes.has(affix)


static func get_name(affix: String) -> String:
	return str(AFFIXES.get(affix, {}).get("name", affix))


static func describe(affixes: Array[String]) -> String:
	var names: Array[String] = []
	for a in affixes:
		names.append(get_name(a))
	return "、".join(names)
