## 词缀池覆盖率实测（第三步 B3-7 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_affix_pool.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（4 个测试段，镜像策划侧 `02-check_affix_pool.py` A1–A4）：
##   A. V2（C1 🔴）：每条词缀至少出现在 1 个池（孤儿 = 0）
##   B. V3（C2 🔴）：每个池至少被 1 件底材引用（死池 = 0）
##   C. V4（C3 🟡 警告级）：通用池不含 min_rarity >= 3 的词缀（WARN 不计失败）
##   D. V5（C4）：第二步新增 15 条词缀每条 >= 2 池
##
## 口径与 `策划案/02-check_affix_pool.py` 一致（Python 侧先行拦截，本脚本为运行时侧镜像）。
## `NEW_AFFIX_IDS` 是**规范**（spec，来自 `02-affixes.json` §3），不是从被检查数据反推
## ⇒ 不属自洽式伪校验（同 `verify_equipment.gd` 的 `EXTRA_STAT_KEYS` 体例）。
extends Node

## 第二步（D1）新增的 15 条词缀 id（规范清单，落地后与 33 条合并为 48 条）
const NEW_AFFIX_IDS: Array[String] = [
	"add_shadow_resist", "add_physical_resist", "add_all_resist",
	"add_elemental_penetration", "add_resist_penetration",
	"add_burn_damage", "add_chill_damage", "add_poison_damage",
	"add_shock_damage", "add_curse_damage",
	"add_ailment_duration", "add_ailment_chance", "add_ailment_effect",
	"add_all_element_damage", "add_damage_vs_ailment",
]

## 通用池 —— min_rarity >= 3 的词缀不得出现在此（约束 C3，🟡 软建议）
const GENERIC_POOLS: Array[String] = ["weapon_generic", "armor_generic", "jewelry_generic"]

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


## 警告级断言：输出 [WARN] 但不计入失败（依据 §1.5 裁定 / §4.4 C3 降级 / §8.3 V4）
func _warn(label: String) -> void:
	print("[WARN] %s" % label)


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 词缀池覆盖率实测（第三步 B3-7） =====")
	await _test_no_orphan()
	await _test_no_dead_pool()
	await _test_generic_pool_rarity()
	await _test_new_affix_coverage()
	_finish()


## 全部池引用的词缀 id 集合（pool_id -> affix_ids）
func _pool_affix_ids() -> Array[String]:
	var out: Array[String] = []
	for pid in ConfigLoader.affix_pools:
		var pool: Dictionary = ConfigLoader.affix_pools[pid]
		for aid in pool.get("affix_ids", []):
			out.append(String(aid))
	return out


# =============================================================================
# A. V2 —— 每条词缀至少 1 池（孤儿 = 0）
# =============================================================================

func _test_no_orphan() -> void:
	print("--- A. 每条词缀至少 1 池（2-V2 / C1）---")
	var in_any := {}
	for aid in _pool_affix_ids():
		in_any[aid] = true
	var orphans: Array[String] = []
	for key in ConfigLoader.affixes:
		if not in_any.has(key):
			orphans.append(key)
	_ok("每条词缀至少 1 池（孤儿 %d 条）" % orphans.size(), orphans.is_empty())
	for o in orphans:
		_info("孤儿: %s" % o)


# =============================================================================
# B. V3 —— 每个池至少被 1 件底材引用（死池 = 0）
# =============================================================================

func _test_no_dead_pool() -> void:
	print("--- B. 每个池至少 1 底材引用（2-V3 / C2）---")
	var referenced := {}
	for tid in ConfigLoader.get_all_equipment_ids():
		var tpl := ConfigLoader.get_equipment_template(tid)
		if tpl == null:
			continue
		for pid in tpl.affix_pool_ids:
			referenced[pid] = true
	var dead: Array[String] = []
	for pid in ConfigLoader.affix_pools:
		if not referenced.has(pid):
			dead.append(pid)
	_ok("每个池至少 1 底材引用（死池 %d 个）" % dead.size(), dead.is_empty())
	for d in dead:
		_info("死池: %s" % d)


# =============================================================================
# C. V4 —— 通用池不含 min_rarity >= 3（WARN 级，不计失败）
# =============================================================================

func _test_generic_pool_rarity() -> void:
	print("--- C. 通用池无 min_rarity>=3 词缀（2-V4 / C3，警告级）---")
	# `add_skill_level`（min_rarity=3）出现在 2 个通用池属【裁定保留】（§1.5）——
	# 其权重仅 12（全表最低），且「任何部位都可能出技能等级」是明确设计意图。
	# 故本项输出 WARN 且**不计入失败**。
	var violations: Array[String] = []
	for pid in GENERIC_POOLS:
		if not ConfigLoader.affix_pools.has(pid):
			continue
		var pool: Dictionary = ConfigLoader.affix_pools[pid]
		for aid in pool.get("affix_ids", []):
			var affix: AffixData = ConfigLoader.get_affix(String(aid))
			if affix != null and affix.min_rarity >= 3:
				violations.append("%s -> %s (min_rarity=%d)" % [pid, affix.id, affix.min_rarity])
	_warn("通用池无 min_rarity>=3 词缀（C3 软建议，违规 %d 条）" % violations.size())
	for v in violations:
		_info("提示: %s" % v)
	# 正向断言：通用池确实存在且非空（防「池缺失导致 0 违规」的假通过）
	var present := 0
	for pid in GENERIC_POOLS:
		if ConfigLoader.affix_pools.has(pid) and not ConfigLoader.get_affixes_in_pool(pid).is_empty():
			present += 1
	_ok("3 个通用池均存在且非空（实际 %d）" % present, present == GENERIC_POOLS.size())


# =============================================================================
# D. V5 —— 第二步新增 15 条每条 >= 2 池
# =============================================================================

func _test_new_affix_coverage() -> void:
	print("--- D. 新增 15 条每条 >= 2 池（2-V5 / C4）---")
	_ok("新增词缀清单规模 == 15（实际 %d）" % NEW_AFFIX_IDS.size(), NEW_AFFIX_IDS.size() == 15)
	var missing: Array[String] = []
	var thin: Array[String] = []
	for aid in NEW_AFFIX_IDS:
		if not ConfigLoader.affixes.has(aid):
			missing.append(aid)
			continue
		var cnt := 0
		for pid in ConfigLoader.affix_pools:
			var pool: Dictionary = ConfigLoader.affix_pools[pid]
			if aid in pool.get("affix_ids", []):
				cnt += 1
		if cnt < 2:
			thin.append("%s（%d 池）" % [aid, cnt])
	_ok("15 条新增词缀全部存在（缺失 %d 条）" % missing.size(), missing.is_empty())
	_ok("15 条新增词缀每条 >= 2 池（不足 %d 条）" % thin.size(), thin.is_empty())
	for m in missing:
		_info("缺失: %s" % m)
	for t in thin:
		_info("池数不足: %s" % t)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
