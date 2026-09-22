## 装备数据结构实测（任务 3.1 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_equipment.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（6 个测试段）：
##   A. 底材数据：全部模板 validate() 通过、部位 / 稀有度 / 等级区间合法
##   B. 词缀数据：全部词缀 validate() 通过、前/后缀分布、互斥组不悬空
##   C. 词缀池表：≥8 池、装备引用全部存在、池内词缀全部存在、mythic_pool 就位
##   D. 词缀条数表：GDD 3.2.3 权威不变式 前缀上限+后缀上限=条数上限（8 档）
##   E. 实例化：create_from_template → 字段正确、to_dict/from_dict 往返一致、iLvl 缩放正确
##   F. 池查询：get_affixes_in_pool 部位过滤、get_affixes_for_slot 部位合法
extends Node

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 装备数据结构实测（任务 3.1） =====")
	await _test_templates()
	await _test_affixes()
	await _test_pools()
	await _test_rarity_limits()
	await _test_instance()
	await _test_pool_query()
	_finish()


# =============================================================================
# A. 底材数据
# =============================================================================

func _test_templates() -> void:
	print("--- A. 底材数据 ---")
	var ids := ConfigLoader.get_all_equipment_ids()
	_ok("底材总数 ≥ 40（GDD 1.7 基准）", ids.size() >= 40)
	var all_valid := true
	var slot_mask := 0
	for tid in ids:
		var tpl := ConfigLoader.get_equipment_template(tid)
		if tpl == null or not tpl.validate().is_empty():
			all_valid = false
			_info("底材 %s 校验失败：%s" % [tid, [] if tpl == null else tpl.validate()])
			continue
		slot_mask |= 1 << tpl.slot
	_ok("全部底材数据合法", all_valid)
	var expected_slots := 0
	for s in range(GameConstants.EQUIP_SLOT_COUNT):
		expected_slots |= 1 << s
	_ok("部位覆盖齐全（%d 个部位）" % GameConstants.EQUIP_SLOT_COUNT, slot_mask == expected_slots)
	# 稀有度区间与 iLvl 区间抽样断言
	var range_ok := true
	for tid in ids:
		var tpl := ConfigLoader.get_equipment_template(tid)
		if tpl.item_level_min < 1 or tpl.item_level_max < tpl.item_level_min:
			range_ok = false
		if tpl.rarity_min < 0 or tpl.rarity_max < tpl.rarity_min:
			range_ok = false
	_ok("全部底材 iLvl / 稀有度区间合法", range_ok)


# =============================================================================
# B. 词缀数据
# =============================================================================

func _test_affixes() -> void:
	print("--- B. 词缀数据 ---")
	var all_valid := true
	var prefix_count := 0
	var suffix_count := 0
	for key in ConfigLoader.affixes:
		var affix: AffixData = ConfigLoader.affixes[key]
		if affix == null or not affix.validate().is_empty():
			all_valid = false
			continue
		if affix.position == GameConstants.AffixPosition.PREFIX:
			prefix_count += 1
		else:
			suffix_count += 1
	_ok("词缀总数 ≥ 30（GDD 词缀池基准）", ConfigLoader.affixes.size() >= 30)
	_ok("全部词缀数据合法", all_valid)
	_ok("前/后缀都有分布（前 %d / 后 %d）" % [prefix_count, suffix_count], prefix_count > 0 and suffix_count > 0)
	# 互斥组引用不悬空（组名要么是自身 id 要么是存在的词缀 id）
	var group_ok := true
	for key in ConfigLoader.affixes:
		var affix: AffixData = ConfigLoader.affixes[key]
		var g := affix.get_exclusive_group()
		if g != key and not ConfigLoader.affixes.has(g):
			group_ok = false
	_ok("词缀互斥组全部可解析", group_ok)


# =============================================================================
# C. 词缀池表
# =============================================================================

func _test_pools() -> void:
	print("--- C. 词缀池表 ---")
	var pool_ids := ConfigLoader.get_all_affix_pool_ids()
	_ok("词缀池 ≥ 8 个（实际 %d）" % pool_ids.size(), pool_ids.size() >= 8)
	# 每池非空
	var nonempty := true
	for pid in pool_ids:
		if ConfigLoader.get_affixes_in_pool(pid).is_empty():
			nonempty = false
	_ok("全部词缀池非空", nonempty)
	# 装备引用的池全部存在（跨表校验已兜底，这里正向断言）
	var refs_ok := true
	var ref_count := 0
	for tid in ConfigLoader.get_all_equipment_ids():
		var tpl := ConfigLoader.get_equipment_template(tid)
		for pid in tpl.affix_pool_ids:
			ref_count += 1
			if not ConfigLoader.affix_pools.has(pid):
				refs_ok = false
	_ok("装备词缀池引用全部存在（%d 处引用）" % ref_count, refs_ok)
	# 池内词缀全部存在（跨表校验已兜底，正向断言）
	var pool_affix_ok := true
	var pool_affix_count := 0
	for pid in pool_ids:
		for affix in ConfigLoader.get_affixes_in_pool(pid):
			pool_affix_count += 1
			if affix == null:
				pool_affix_ok = false
	_ok("池内词缀全部可解析（共 %d 条池条目）" % pool_affix_count, pool_affix_ok)
	_ok("神话特殊池就位（mythic_pool）", ConfigLoader.affix_pools.has("mythic_pool"))
	# 装备类别×池覆盖：武器有攻击/通用/施法/防御池
	for expected in ["weapon_offense", "weapon_generic", "weapon_caster", "weapon_defense",
			"armor_defense", "armor_generic", "jewelry_generic"]:
		_ok("池 %s 存在" % expected, ConfigLoader.affix_pools.has(expected))


# =============================================================================
# D. 词缀条数表（GDD 3.2.3 权威不变式）
# =============================================================================

func _test_rarity_limits() -> void:
	print("--- D. 词缀条数表（GDD 3.2.3） ---")
	_ok("条数区间数组等长 8 档",
		GameConstants.RARITY_AFFIX_RANGE.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_PREFIX_LIMIT.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_SUFFIX_LIMIT.size() == GameConstants.RARITY_COUNT)
	# GDD 3.2.3 权威表：白 0+0 / 蓝 1+1 / 黄 2+2 / 紫 3+2 / 橙 3+3 / 红 4+3 / 绿 2+3 / 彩 3+3
	var expect_prefix := [0, 1, 2, 3, 3, 4, 2, 3]
	var expect_suffix := [0, 1, 2, 2, 3, 3, 3, 3]
	var limits_ok := true
	for i in range(GameConstants.RARITY_COUNT):
		if GameConstants.RARITY_PREFIX_LIMIT[i] != expect_prefix[i] \
				or GameConstants.RARITY_SUFFIX_LIMIT[i] != expect_suffix[i]:
			limits_ok = false
			_info("档 %d：期望前%d后%d，实际前%d后%d" % [i, expect_prefix[i], expect_suffix[i],
				GameConstants.RARITY_PREFIX_LIMIT[i], GameConstants.RARITY_SUFFIX_LIMIT[i]])
	_ok("前后缀上限与 GDD 3.2.3 权威表一致", limits_ok)
	# 不变式：前缀上限 + 后缀上限 = 词缀条数上限（区间 y）
	var invariant := true
	for i in range(GameConstants.RARITY_COUNT):
		var rng: Vector2i = GameConstants.RARITY_AFFIX_RANGE[i]
		if rng.x < 0 or rng.y < rng.x:
			invariant = false
		if GameConstants.RARITY_PREFIX_LIMIT[i] + GameConstants.RARITY_SUFFIX_LIMIT[i] != rng.y:
			invariant = false
	_ok("不变式：前缀上限+后缀上限=条数上限（8 档全过）", invariant)


# =============================================================================
# E. 实例化
# =============================================================================

func _test_instance() -> void:
	print("--- E. 实例化 ---")
	var tpl := ConfigLoader.get_equipment_template("sword_iron")
	_ok("拿到底材 sword_iron", tpl != null)
	if tpl == null:
		return
	var item := EquipmentInstance.create_from_template(tpl, 17, GameConstants.Rarity.RARE)
	_ok("实例字段正确（slot/iLvl/ReqLv/稀有度/套装）",
		item.slot == GameConstants.EquipSlot.MAIN_HAND
		and item.item_level == 17
		and item.required_level == GameConstants.required_level_for(17)
		and item.rarity == GameConstants.Rarity.RARE
		and item.instance_id.begins_with("i_"))
	_ok("底材引用已注入", item.template == tpl)
	# iLvl 缩放：get_base_stats 用了 item_stat_ilvl_scale
	var base := item.get_base_stats()
	_ok("基础属性随 iLvl 缩放（非空且含 flat_attack）", base.has("flat_attack") and base.size() > 0)
	var scale := GameConstants.item_stat_ilvl_scale(17)
	var expect := float(tpl.base_stats["flat_attack"]) * scale
	_ok("flat_attack = 底材值 × iLvl 缩放（%.2f）" % expect, absf(float(base["flat_attack"]) - expect) < 0.001)
	# 序列化往返
	var dict := item.to_dict()
	var restored := EquipmentInstance.from_dict(dict)
	_ok("to_dict/from_dict 往返一致（id/iLvl/稀有度/ReqLv）",
		restored.instance_id == item.instance_id
		and restored.template_id == item.template_id
		and restored.item_level == item.item_level
		and restored.rarity == item.rarity
		and restored.required_level == item.required_level)
	# 强化上限按稀有度（神话 +12 / 其余 +10）
	var mythic := EquipmentInstance.create_from_template(tpl, 1, GameConstants.Rarity.MYTHIC)
	_ok("神话红装强化上限 +12", mythic.get_forge_max_level() == 12)
	var normal := EquipmentInstance.create_from_template(tpl, 1, GameConstants.Rarity.LEGENDARY)
	_ok("橙装强化上限 +10", normal.get_forge_max_level() == 10)


# =============================================================================
# F. 池查询
# =============================================================================

func _test_pool_query() -> void:
	print("--- F. 池查询 ---")
	var weapon_offense := ConfigLoader.get_affixes_in_pool("weapon_offense")
	_ok("weapon_offense 池非空", weapon_offense.size() > 0)
	var slot_main := ConfigLoader.get_affixes_for_slot(GameConstants.EquipSlot.MAIN_HAND)
	_ok("主手部位词缀 ≥ 20 条（实际 %d）" % slot_main.size(), slot_main.size() >= 20)
	var slot_legal := true
	for affix in slot_main:
		if not affix.fits_slot(GameConstants.EquipSlot.MAIN_HAND):
			slot_legal = false
	_ok("主手部位词缀全部 fits_slot", slot_legal)
	# 部位过滤：add_block_chance 限定副手/头/胸/项链，不应出现在主手池查询
	var has_block := false
	for affix in slot_main:
		if affix.id == "add_block_chance":
			has_block = true
	_ok("部位过滤生效（add_block_chance 不出现在主手）", not has_block)
	# 神话池只在神话档可用（min_rarity 或池分离）——mythic 词缀应仅 mythic_pool
	var mythic_affix: AffixData = ConfigLoader.get_affix("mythic_all_attributes")
	_ok("神话词缀存在且 min_rarity=MYTHIC",
		mythic_affix != null and mythic_affix.min_rarity == GameConstants.Rarity.MYTHIC)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
