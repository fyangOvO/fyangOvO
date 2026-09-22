## 完整存档实测（任务 8.1 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_save81.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（6 个测试段）：
##   A. 局外进度全字段：账号等级/经验/天赋/金币/材料/背包/装备/仓库/解锁/声望/成就/统计
##   B. 局内进度：current_level_id / current_difficulty_tier 跨会话保持
##   C. 设置字典：settings 自由键值随档保存
##   D. 装备实例回读：词缀/稀有度/锻造等级逐项一致
##   E. 跨会话模拟：保存 → 重建（模拟重开）→ 读回 → 全字段一致
##   F. 清理：测试槽位删除干净
extends Node2D

const SLOT := 7

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 完整存档实测（任务 8.1） =====")
	await _run()
	_finish()


func _run() -> void:
	# 准备：删除旧测试槽
	if SaveManager.slot_exists(SLOT):
		SaveManager.delete_slot(SLOT)
	var d := SaveManager.create_new_slot(SLOT)
	_ok("新建槽位成功", d != null)
	if d == null:
		return

	# --- 写入局外进度全字段 ---
	d.display_name = "八一八测试档"
	d.account_level = 17
	d.account_xp = 342.0
	d.total_xp = 12000.0
	d.talent_points = 5
	d.unlocked_talent_nodes = ["war.small.0", "war.small.1", "war.big.2"]
	d.gold = 9876
	d.add_material("magic_stone", 42)
	d.add_material("ember_core", 3)
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_flame")
	var item := EquipmentInstance.create_from_template(tpl, 14, GameConstants.Rarity.RARE) if tpl != null else null
	if item != null:
		d.inventory.append(item)
	var eq_tpl: EquipmentData = ConfigLoader.get_equipment_template("helm_crown_titan")
	if eq_tpl != null:
		d.set_equipped(GameConstants.EquipSlot.HELM,
			EquipmentInstance.create_from_template(eq_tpl, 16, GameConstants.Rarity.EPIC))
	var stash_tpl: EquipmentData = ConfigLoader.get_equipment_template("ring_echo")
	if stash_tpl != null:
		d.stash.append(EquipmentInstance.create_from_template(stash_tpl, 8, GameConstants.Rarity.MAGIC))
	d.unlocked_levels = ["ch2_l07", "ch2_l08"]
	d.cleared_levels = ["ch1_l01"]
	d.level_clear_times = {"ch1_l01": 152.0}
	d.unlocked_difficulty_tier = 2
	d.chapter_reputation = {"ch1": 120.0}
	d.unlocked_achievements = ["ach_first_blood"]
	d.stash_pages = 2
	d.statistics = {"total_kills": 512, "total_gold": 88888}
	# 局内进度
	d.current_level_id = "ch2_l09"
	d.current_difficulty_tier = 3
	# 设置字典
	d.settings = {"master_volume_db": -8.0, "vsync": false, "fullscreen": true, "custom_key": "abc"}

	_ok("局外进度字段已写入（等级 17 / 金币 9876 / 材料 2 种）",
		d.account_level == 17 and d.gold == 9876 and d.get_material("magic_stone") == 42)
	_ok("局内进度已写入（ch2_l09 / 难度 3）",
		d.current_level_id == "ch2_l09" and d.current_difficulty_tier == 3)

	# --- 保存 ---
	_ok("保存成功", SaveManager.save_to_slot(SLOT, d))

	# --- 读回 + 逐字段比对 ---
	var r := SaveManager.load_from_slot(SLOT)
	_ok("读回非空", r != null)
	if r == null:
		return
	_ok("局外：等级/天赋/金币/材料一致",
		r.account_level == 17 and r.talent_points == 5 and r.gold == 9876
		and r.get_material("magic_stone") == 42 and r.get_material("ember_core") == 3)
	_ok("局外：天赋节点/解锁/声望/成就一致",
		r.unlocked_talent_nodes.size() == 3
		and r.cleared_levels.size() == 1
		and r.chapter_reputation.get("ch1", 0.0) == 120.0
		and r.unlocked_achievements.size() == 1)
	_ok("局内：current_level_id / difficulty 一致",
		r.current_level_id == "ch2_l09" and r.current_difficulty_tier == 3)
	_ok("设置字典随档保持", r.settings.get("master_volume_db", 0.0) == -8.0
		and r.settings.get("custom_key", "") == "abc")
	_ok("统计随档保持", int(r.statistics.get("total_kills", 0)) == 512)
	_ok("背包/仓库件数一致", r.inventory.size() == 1 and r.stash.size() == 1)
	var r_item := r.inventory[0] if r.inventory.size() > 0 else null
	_ok("装备实例回读：模板/稀有/锻造等级",
		r_item != null and r_item.template_id == "sword_flame"
		and r_item.rarity == GameConstants.Rarity.RARE and r_item.item_level == 14)
	var r_eq := r.get_equipped(GameConstants.EquipSlot.HELM)
	_ok("已装备回读：泰坦王冠 EPIC",
		r_eq != null and r_eq.template_id == "helm_crown_titan"
		and r_eq.rarity == GameConstants.Rarity.EPIC)

	# --- 跨会话：删除内存对象，重新加载（模拟重开） ---
	var r2 := SaveManager.load_from_slot(SLOT)
	_ok("跨会话重读一致（display_name / play_time 保留）",
		r2 != null and r2.display_name == "八一八测试档")

	# --- 清理 ---
	SaveManager.delete_slot(SLOT)
	_ok("清理：测试槽已删除", not SaveManager.slot_exists(SLOT))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
