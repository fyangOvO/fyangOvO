## 本地完整流程自测（任务 9.2 · 数据链路自动化部分）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_play92.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖（模拟「新档 → 刷怪掉落 → 换装变强 → 存档 → 重开」核心循环的数据层）：
##   A. 新档 → 初始属性可算
##   B. 刷怪掉落：LootRoller 产出装备条目（seed 固定可复现）
##   C. 换装：生成装备 → 穿戴 → 属性增幅（变强，D9 成长曲线）
##   D. 存档 → 重开加载 → 全字段一致（金币/等级/经验/装备/材料/统计）
##   E. 输出自测记录摘要（供 9.2 自测记录合并）
##
## ============================================================================
## ⚠️⚠️ 重要限定：本脚本只验「**数据层**」，**不**验「**战斗表现**」⚠️⚠️
## ============================================================================
##   它证明「装备 / 属性 / 存档的数据链路对」，**不**证明「装备真的影响玩家**实际输出**」。
##
##   2026-09-18 实测教训：`PlayerController` 的战斗属性 getter 整层曾是**阶段 2 占位桩** ——
##   装备一度**只影响生命上限**，攻击 / 暴击 / 攻速 / 护甲 / 抗性**全都不吃装备与增益**。
##   而本脚本当时**依然全绿**：C 段只算了 `StatCalculator` 的属性，**从没问过一句**
##   `PlayerController.get_attack_damage()`。这就是「数据对了 ≠ 玩法通了」最典型的一次。
##
##   ⇒ 「装备 → 玩家**实际输出**」的真实验证在 `tools/verify_choice_flow.gd` **K 段**
##     （双向断言：下界排除「没变」、上界排除「被重复计入」）。
##   ⇒ **任何人改动战斗属性口径（PlayerController / StatCalculator / 装备）后，必须跑
##     `verify_choice_flow`**，只跑本脚本会漏掉整类「接口没接线」的缺陷。
## ============================================================================
extends Node2D

var _fail: int = 0
var _report: Array[String] = []

const SLOT := 3


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 本地完整流程自测（任务 9.2 · 数据链路） =====")
	await _run()
	_finish()


func _run() -> void:
	seed(20260917)

	# A. 新档
	if SaveManager.slot_exists(SLOT):
		SaveManager.delete_slot(SLOT)
	var d := SaveManager.create_new_slot(SLOT)
	_ok("新档创建（槽 %d）" % SLOT, d != null)
	if d == null:
		return
	var base := StatCalculator.calculate(d.account_level, d.equipped)
	_ok("初始属性可算（生命 %.0f / 攻击 %.0f）" % [base.get("max_hp", 0.0), base.get("attack", 0.0)],
		base.get("max_hp", 0.0) > 0 and base.get("attack", 0.0) > 0)

	# B. 刷怪掉落（LootRoller 固定 seed，多次采样取装备条目）
	var monster: MonsterData = ConfigLoader.get_monster("spider_cave")
	var equip_drop: Dictionary = {}
	for _i in 40:
		var drops := LootRoller.roll_loot(monster, 5, 0, d.account_level)
		for drop in drops:
			if drop.get("type", "") == "equipment":
				equip_drop = drop
				break
		if not equip_drop.is_empty():
			break
	_ok("刷怪掉落（5 级蜘蛛，seed 固定 → 40 次采样内产出装备）", not equip_drop.is_empty())
	if equip_drop.is_empty():
		# 兜底：直接取底材（保证后续链路可验证）
		var tpl: EquipmentData = ConfigLoader.equipment_templates.get("sword_iron")
		equip_drop = { "type": "equipment", "item_id": "sword_iron", "rarity": GameConstants.Rarity.MAGIC, "item_level": 5 }

	# C. 换装变强
	var tpl: EquipmentData = ConfigLoader.equipment_templates.get(String(equip_drop.get("item_id", "")))
	var item := EquipmentInstance.create_from_template(tpl, int(equip_drop.get("item_level", 5)),
		int(equip_drop.get("rarity", GameConstants.Rarity.MAGIC))) if tpl != null else null
	_ok("掉落装备可实例化（%s Lv.%d）" % [String(equip_drop.get("item_id", "?")), int(equip_drop.get("item_level", 0))],
		item != null)
	if item != null:
		if item.slot >= 0 and item.slot < GameConstants.EQUIP_SLOT_COUNT:
			d.set_equipped(item.slot, item)
			d.gold = 120
			d.account_xp = 45.0
			d.statistics["monsters_killed"] = 7
			d.statistics["items_picked"] = 1
			var after := StatCalculator.calculate(d.account_level, d.equipped)
			var grew: bool = after.get("attack", 0.0) > base.get("attack", 0.0) \
				or after.get("max_hp", 0.0) > base.get("max_hp", 0.0)
			_ok("换装后属性增长（攻击 %.0f→%.0f）" % [base.get("attack", 0.0), after.get("attack", 0.0)], grew)
			d.display_name = "剑士 · Lv.1"
		else:
			_ok("换装后属性增长（槽位 %d 越界）" % item.slot, false)

	# D. 存档 → 重开 → 一致性
	SaveManager.save_to_slot(SLOT, d)
	_ok("存档写入", SaveManager.slot_exists(SLOT))
	var r := SaveManager.load_from_slot(SLOT)
	var consistent: bool = r != null and r.gold == d.gold and r.account_xp == d.account_xp \
		and r.statistics.get("monsters_killed", 0) == d.statistics.get("monsters_killed", 0)
	# 装备槽逐一比对（null 与 template_id）
	if r != null:
		for i in range(GameConstants.EQUIP_SLOT_COUNT):
			var a: EquipmentInstance = d.get_equipped(i)
			var b: EquipmentInstance = r.get_equipped(i)
			var same := (a == null and b == null) or (a != null and b != null and a.template_id == b.template_id)
			if not same:
				consistent = false
	_ok("重开加载：金币/经验/击杀/装备槽全一致", consistent)

	# E. 自测记录摘要
	_report.append("自测记录（9.2 自动化部分，seed=20260917）")
	_report.append("  1. 新档：槽 %d，账号 Lv.%d，初始生命 %.0f / 攻击 %.0f" % [SLOT, d.account_level, base.get("max_hp", 0.0), base.get("attack", 0.0)])
	if item != null:
		var after := StatCalculator.calculate(d.account_level, d.equipped)
		_report.append("  2. 刷怪掉落：%s（%s，Lv.%d）" % [String(equip_drop.get("item_id", "?")), GameConstants.RARITY_NAMES[int(equip_drop.get("rarity", 0))], int(equip_drop.get("item_level", 0))])
		_report.append("  3. 换装变强：攻击 %.0f → %.0f（+%.0f）" % [base.get("attack", 0.0), after.get("attack", 0.0), after.get("attack", 0.0) - base.get("attack", 0.0)])
	_report.append("  4. 存档重开：金币 %d / 经验 %.0f / 击杀 %d 一致" % [d.gold, d.account_xp, d.statistics.get("monsters_killed", 0)])
	_report.append("  5. 手感反馈（待玩家实际试玩补充）")


func _finish() -> void:
	print("----- 自测记录摘要 -----")
	for line in _report:
		print(line)
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
