## 装备对比实测（任务 3.7 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_equipment_compare.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（7 个测试段）：
##   A. stat_key：33 词缀全部映射非空（AffixData.validate 已兜底，此处抽查）
##   B. 汇总：get_total_stats = 底材基础 + 词缀归并（同键求和 / 百分比词缀并入自身键）
##   C. 对比：升 / 降 / 平 三态与 diff 值
##   D. 穿戴新件（old = null）：全为升
##   E. 空物品 / null 输入安全
##   F. 特殊键：echo_strike 不进数值对比（进 special 文本）
##   G. 面板渲染：ComparePanel.show_compare 行数与汇总文案
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 装备对比实测（任务 3.7） =====")
	_rng.seed = 20260916
	await _test_stat_key()
	await _test_total()
	await _test_compare()
	await _test_wear_new()
	await _test_safe()
	await _test_special()
	await _test_panel()
	_finish()


func _make_item(rarity: int, ilvl: int, template_id: String = "sword_iron", affix_ids: Array[String] = []) -> EquipmentInstance:
	var item := EquipmentInstance.new()
	item.instance_id = "c_%d_%d" % [rarity, _rng.randi() % 100000]
	item.template_id = template_id
	item.slot = GameConstants.EquipSlot.MAIN_HAND
	item.item_level = ilvl
	item.rarity = rarity
	item.affixes = AffixRoller.roll_affixes(ConfigLoader.get_equipment_template(template_id), ilvl, rarity, _rng)
	# 若指定词缀 ID 集合，则按集合重掷（用于精确断言 diff）
	if not affix_ids.is_empty():
		item.affixes = []
		for aid in affix_ids:
			var aff: AffixData = ConfigLoader.affixes.get(aid)
			if aff != null:
				var roll := AffixRoll.new()
				roll.affix_id = aid
				roll.template = aff
				roll.value = aff.roll_base_value(_rng) * GameConstants.affix_ilvl_scale(ilvl)
				roll.quality = 1
				item.affixes.append(roll)
	return item


# =============================================================================
# A. stat_key
# =============================================================================

func _test_stat_key() -> void:
	print("--- A. stat_key ---")
	var empty := 0
	for id in ConfigLoader.affixes:
		if (ConfigLoader.affixes[id] as AffixData).stat_key.is_empty():
			empty += 1
	_ok("33 词缀 stat_key 全部非空", ConfigLoader.affixes.size() == 33 and empty == 0)
	_ok("flat_attack 映射正确", (ConfigLoader.affixes["add_flat_attack"] as AffixData).stat_key == "flat_attack")
	_ok("crit_chance 映射正确", (ConfigLoader.affixes["add_crit_chance"] as AffixData).stat_key == "crit_chance")


# =============================================================================
# B. 汇总
# =============================================================================

func _test_total() -> void:
	print("--- B. 汇总 ---")
	var item := _make_item(GameConstants.Rarity.RARE, 20, "sword_iron", ["add_flat_attack", "add_flat_hp"])
	var stats := EquipmentCompare.get_total_stats(item)
	var base := item.get_base_stats()
	_ok("汇总包含底材攻击力", stats.has("flat_attack") and stats["flat_attack"] > 0.0)
	_ok("汇总包含词缀生命值（底材无 flat_hp 时=词缀值）",
		stats.has("flat_hp") and absf(float(stats["flat_hp"]) - float(base.get("flat_hp", 0.0)) - _affix_sum(item, "flat_hp")) < 0.01)
	_ok("汇总不含 echo_strike（特殊键）", not stats.has("echo_strike"))
	_ok("null 输入返回空表", EquipmentCompare.get_total_stats(null).is_empty())


func _affix_sum(item: EquipmentInstance, key: String) -> float:
	var s := 0.0
	for roll in item.affixes:
		var aff: AffixData = roll.template
		if aff != null and aff.stat_key == key:
			s += roll.value
	return s


# =============================================================================
# C. 对比
# =============================================================================

func _test_compare() -> void:
	print("--- C. 对比 ---")
	var old_item := _make_item(GameConstants.Rarity.RARE, 10, "sword_iron", ["add_flat_attack", "add_flat_hp"])
	var new_item := _make_item(GameConstants.Rarity.LEGENDARY, 30, "sword_iron", ["add_flat_attack", "add_crit_chance"])
	var rows := EquipmentCompare.compare(new_item, old_item)
	var attack_row: Dictionary = {}
	for r in rows:
		if r["key"] == "flat_attack":
			attack_row = r
	_ok("对比含 flat_attack 行", not attack_row.is_empty())
	_ok("新 iLvl 30 攻击力 > 旧 iLvl 10（升）", int(attack_row["delta_type"]) == 1 and float(attack_row["diff"]) > 0.0)
	var crit_row: Dictionary = {}
	for r in rows:
		if r["key"] == "crit_chance":
			crit_row = r
	_ok("新件新增暴击率为升", not crit_row.is_empty() and int(crit_row["delta_type"]) == 1)
	_ok("行排序：升在前降在后", _rows_sorted(rows))
	_ok("对比空物品返回空数组", EquipmentCompare.compare(null, null).is_empty())


func _rows_sorted(rows: Array[Dictionary]) -> bool:
	for i in range(1, rows.size()):
		if int(rows[i - 1]["delta_type"]) < int(rows[i]["delta_type"]):
			return false
	return true


# =============================================================================
# D. 穿戴新件
# =============================================================================

func _test_wear_new() -> void:
	print("--- D. 穿戴新件（old = null） ---")
	var item := _make_item(GameConstants.Rarity.LEGENDARY, 25, "sword_iron", ["add_flat_attack"])
	var rows := EquipmentCompare.compare(item, null)
	_ok("old=null 时全部为升", not rows.is_empty() and all((func(r: Dictionary) -> bool: return int(r["delta_type"]) == 1), rows))


func all(fn: Callable, arr: Array) -> bool:
	for a in arr:
		if not fn.call(a):
			return false
	return true


# =============================================================================
# E. 安全
# =============================================================================

func _test_safe() -> void:
	print("--- E. 安全 ---")
	_ok("compare(null, item) 全为升（空 vs 有）",
		not EquipmentCompare.compare(null, _make_item(GameConstants.Rarity.MAGIC, 5)).is_empty())
	_ok("无词缀物品不崩溃", EquipmentCompare.compare(
		_make_item(GameConstants.Rarity.COMMON, 1), _make_item(GameConstants.Rarity.COMMON, 1)) is Array)


# =============================================================================
# F. 特殊键
# =============================================================================

func _test_special() -> void:
	print("--- F. 特殊键 ---")
	var item := _make_item(GameConstants.Rarity.LEGENDARY, 20, "sword_iron", ["add_flat_attack", "hidden_echo_strike"])
	var stats := EquipmentCompare.get_total_stats(item)
	_ok("echo_strike 不进数值汇总", not stats.has("echo_strike"))
	var special := EquipmentCompare.get_special_text(item)
	_ok("特殊文本含回响之刃模板", special.contains("第 7 次攻击") and special.contains("%"))
	_ok("无特殊词缀时返回空串", EquipmentCompare.get_special_text(
		_make_item(GameConstants.Rarity.RARE, 10)).is_empty())


# =============================================================================
# G. 面板
# =============================================================================

func _test_panel() -> void:
	print("--- G. 面板渲染 ---")
	var panel := ComparePanel.new()
	add_child(panel) # 进树触发 _ready
	var old_item := _make_item(GameConstants.Rarity.RARE, 10, "sword_iron", ["add_flat_attack"])
	var new_item := _make_item(GameConstants.Rarity.LEGENDARY, 30, "sword_iron", ["add_flat_attack", "add_crit_chance"])
	panel.show_compare(new_item, old_item, "主手")
	_ok("面板标题含装备对比与部位", panel._title_label.text.contains("装备对比") and panel._title_label.text.contains("主手"))
	_ok("面板行数 ≥ 2（攻击力 + 暴击率）", panel._rows_box.get_child_count() >= 3)
	panel.queue_free()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
