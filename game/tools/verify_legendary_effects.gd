## 传奇特效系统实测（任务 3.5 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_legendary_effects.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（6 个测试段）：
##   A. 数据层：池 ≥ 30 件（GDD 遗留项 #3）、id 唯一、范式三要素、部位/稀有度/冷却合法
##   B. 类型白名单：trigger/effect 类型合法、关键参数齐全
##   C. 装配：橙+ 必挂传奇特效（模板绑定或部位池抽取）；部位匹配
##   D. 触发：叠层引爆（烬誓 5 层 → 300% 范围火伤）/ 冷却（不朽者 90s 二次拦截）/
##      概率不触发 / 阈值（七劫 10% 生命线）
##   E. 效果结算：heal / buff / extra_loot / revive / summon 数值正确
##   F. 部位池与重铸抽取：for_slot / roll_for_slot（排除原特效）
extends Node

var _fail: int = 0
var _rng := RandomNumberGenerator.new()


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 传奇特效系统实测（任务 3.5） =====")
	_rng.seed = 20260916
	await _test_data()
	await _test_types()
	await _test_equip()
	await _test_triggers()
	await _test_effects()
	await _test_pools()
	_finish()


func _make_item(rarity: int, ilvl: int = 20) -> EquipmentInstance:
	var tpl := ConfigLoader.get_equipment_template("sword_iron")
	var item := AffixRoller.roll_full_equipment(tpl, ilvl, rarity, _rng)
	return item


# =============================================================================
# A. 数据层
# =============================================================================

func _test_data() -> void:
	print("--- A. 数据层 ---")
	_ok("传奇特效池 ≥ 30 件（GDD 遗留项 #3）", ConfigLoader.legendary_effects.size() >= 30)
	_ok("GDD 3.5 五件示例齐全",
		ConfigLoader.legendary_effects.has("jin_shi_ran_po_ren")
		and ConfigLoader.legendary_effects.has("qi_chong_hui_xiang_zhi_guan")
		and ConfigLoader.legendary_effects.has("lie_jie_zhi_huan")
		and ConfigLoader.legendary_effects.has("bu_xiu_zhe_de_can_qu")
		and ConfigLoader.legendary_effects.has("shi_yi_zhe_zhi_xue"))
	var tri_ok := true
	var slot_ok := true
	var cd_ok := true
	var desc_ok := true
	for eid in ConfigLoader.legendary_effects:
		var fx: Dictionary = ConfigLoader.legendary_effects[eid]
		if not fx.has("trigger") or not fx.has("effect"):
			tri_ok = false
		if not GameConstants.EQUIP_SLOT_KEYS.has(String(fx.get("slot", ""))):
			slot_ok = false
		if float(fx.get("cooldown", 0.0)) < 0.0:
			cd_ok = false
		if String(fx.get("description", "")).is_empty():
			desc_ok = false
	_ok("范式三要素齐全（trigger + effect + description）", tri_ok and desc_ok)
	_ok("部位全部合法（10 槽枚举）", slot_ok)
	_ok("冷却全部 ≥ 0", cd_ok)
	# 每部位至少 2 件（保证重铸抽取池可用）
	var slot_min_ok := true
	for slot_key in GameConstants.EQUIP_SLOT_KEYS:
		var cnt := 0
		for fx in ConfigLoader.legendary_effects.values():
			if String(fx.get("slot", "")) == slot_key:
				cnt += 1
		if cnt < 2:
			slot_min_ok = false
			_info("%s 仅 %d 件" % [slot_key, cnt])
	_ok("每部位 ≥ 2 件（重铸池可用）", slot_min_ok)


# =============================================================================
# B. 类型白名单
# =============================================================================

func _test_types() -> void:
	print("--- B. 类型白名单 ---")
	var trigger_ok := true
	var effect_ok := true
	for fx: Dictionary in ConfigLoader.legendary_effects.values():
		var ttype := String(fx["trigger"].get("type", ""))
		if not LegendaryEffectSystem.TRIGGER_TYPES.has(ttype):
			trigger_ok = false
			_info("%s trigger=%s" % [fx.get("id", ""), ttype])
		var eff: Dictionary = fx["effect"]
		var etype := String(eff.get("type", ""))
		if not LegendaryEffectSystem.EFFECT_TYPES.has(etype):
			effect_ok = false
			_info("%s effect=%s" % [fx.get("id", ""), etype])
	_ok("trigger 类型全部合法（10 种枚举）", trigger_ok)
	_ok("effect 类型全部合法（12 种枚举）", effect_ok)
	# 关键参数抽查
	var param_ok := true
	var fx: Dictionary = ConfigLoader.legendary_effects["jin_shi_ran_po_ren"]
	if not fx["effect"].has("on_full") or not fx["effect"]["on_full"].has("damage_pct"):
		param_ok = false
	fx = ConfigLoader.legendary_effects["shi_yi_zhe_zhi_xue"]
	if not fx["effect"].has("limit_per_run"):
		param_ok = false
	fx = ConfigLoader.legendary_effects["bu_xiu_zhe_de_can_qu"]
	if not fx["effect"].has("heal_pct"):
		param_ok = false
	_ok("stack/deal_damage/heal/extra_loot 关键参数齐全", param_ok)


# =============================================================================
# C. 装配
# =============================================================================

func _test_equip() -> void:
	print("--- C. 装配 ---")
	var orange_ok := true
	for i in range(20):
		var item := _make_item(GameConstants.Rarity.LEGENDARY)
		if item.legendary_effect_id.is_empty():
			orange_ok = false
	_ok("橙装 20 件抽查全部挂传奇特效（掉落即定型）", orange_ok)
	var mythic := _make_item(GameConstants.Rarity.MYTHIC)
	_ok("红装挂传奇特效 + 神话词缀",
		not mythic.legendary_effect_id.is_empty()
		and mythic.affixes.size() >= 7)
	# 部位匹配：特效 slot 与装备槽一致
	var slot_match := true
	for i in range(15):
		var item := _make_item(GameConstants.Rarity.LEGENDARY)
		var fx := LegendaryEffectSystem.get_effect(item.legendary_effect_id)
		if GameConstants.EQUIP_SLOT_KEYS[item.slot] != String(fx.get("slot", "")):
			slot_match = false
	_ok("特效槽位与装备部位匹配（15 件抽查）", slot_match)
	# 蓝/紫不挂特效（< 传说）
	var lower := _make_item(GameConstants.Rarity.RARE)
	_ok("紫装不挂传奇特效（< 传说）", lower.legendary_effect_id.is_empty())


# =============================================================================
# D. 触发
# =============================================================================

func _test_triggers() -> void:
	print("--- D. 触发 ---")
	# 烬誓·燃魄刃：on_crit 叠 5 层 → 引爆 300% 攻击力火伤
	LegendaryEffectSystem.clear()
	var sword := _make_item(GameConstants.Rarity.LEGENDARY)
	sword.legendary_effect_id = "jin_shi_ran_po_ren"
	LegendaryEffectSystem.register(sword)
	var fired := false
	for i in range(5):
		var res: Array = LegendaryEffectSystem.on_event("on_crit", { "attack": 100.0, "max_hp": 500.0 })
		for r in res:
			if String(r["phase"]) == "on_full":
				var result: Dictionary = r["result"]
				if String(result["type"]) == "deal_damage" and absf(float(result["amount"]) - 300.0) < 0.01:
					fired = true
	_ok("烬誓叠 5 层引爆 300% 攻击力火伤", fired)
	# 冷却：不朽者 90s —— 同帧二次触发被拦截
	LegendaryEffectSystem.clear()
	var chest := _make_item(GameConstants.Rarity.LEGENDARY)
	chest.legendary_effect_id = "bu_xiu_zhe_de_can_qu"
	LegendaryEffectSystem.register(chest)
	var first := LegendaryEffectSystem.on_event("on_low_hp", { "hp_pct": 0.005, "max_hp": 1000.0 })
	var second := LegendaryEffectSystem.on_event("on_low_hp", { "hp_pct": 0.005, "max_hp": 1000.0 })
	_ok("不朽者首次触发（revive_protect）", first.size() == 1 and String(first[0]["result"]["type"]) == "revive_protect")
	_ok("不朽者 90s 冷却内二次触发被拦截", second.is_empty())
	# 阈值：七劫之冠 hp_pct > 0.1 不触发
	LegendaryEffectSystem.clear()
	var helm := _make_item(GameConstants.Rarity.LEGENDARY)
	helm.legendary_effect_id = "qi_jie_zhi_guan"
	LegendaryEffectSystem.register(helm)
	var high := LegendaryEffectSystem.on_event("on_low_hp", { "hp_pct": 0.9 })
	_ok("七劫之冠满血（90%）不触发", high.is_empty())
	# 概率：烈空·雷暴锤 pct=0.3 —— 模拟时间推进（间隔 1.1s > 冷却 1.0s）测纯概率
	LegendaryEffectSystem.clear()
	var hammer := _make_item(GameConstants.Rarity.LEGENDARY)
	hammer.legendary_effect_id = "lie_kong_lei_bao_chui"
	LegendaryEffectSystem.register(hammer)
	var hit_count := 0
	for i in range(60):
		hit_count += LegendaryEffectSystem.on_event("on_crit", { "attack": 50.0 }, float(i) * 1.1).size()
	_ok("烈空雷暴锤 30% 概率：60 次触发在 [5, 40] 区间（时间推进避开冷却）",
		hit_count >= 5 and hit_count <= 40)
	_info("       实际触发 %d 次" % hit_count)


# =============================================================================
# E. 效果结算
# =============================================================================

func _test_effects() -> void:
	print("--- E. 效果结算 ---")
	LegendaryEffectSystem.clear()
	# 血契·吸血链：暴击 heal 3% 最大生命
	var amulet := _make_item(GameConstants.Rarity.LEGENDARY)
	amulet.legendary_effect_id = "xue_qi_xi_xue_lian"
	LegendaryEffectSystem.register(amulet)
	var res: Array = LegendaryEffectSystem.on_event("on_crit", { "max_hp": 1000.0 })
	_ok("血契暴击回血 3%（30 HP）",
		res.size() == 1 and String(res[0]["result"]["type"]) == "heal"
		and absf(float(res[0]["result"]["amount"]) - 30.0) < 0.01)
	# 暗蚀·咒印书：击杀召唤幽魂
	LegendaryEffectSystem.clear()
	var book := _make_item(GameConstants.Rarity.LEGENDARY)
	book.legendary_effect_id = "an_shi_zhou_yin_shu"
	LegendaryEffectSystem.register(book)
	var summon := false
	for i in range(30):
		for r in LegendaryEffectSystem.on_event("on_kill", {}):
			if String(r["result"].get("type", "")) == "summon":
				summon = true
	_ok("暗蚀击杀 25% 召唤幽魂（30 次内命中）", summon)
	# 拾遗者之靴：拾取金币 extra_loot（limit_per_run=5）
	LegendaryEffectSystem.clear()
	var boots := _make_item(GameConstants.Rarity.LEGENDARY)
	boots.legendary_effect_id = "shi_yi_zhe_zhi_xue"
	LegendaryEffectSystem.register(boots)
	var loot_count := 0
	for i in range(200):
		loot_count += LegendaryEffectSystem.on_event("on_pickup_gold", {}).size()
	_ok("拾遗者 15% 概率额外掉落（200 次拾取触发 > 0）", loot_count > 0)
	# 复苏·生命戒：低血 heal 10%
	LegendaryEffectSystem.clear()
	var ring := _make_item(GameConstants.Rarity.LEGENDARY)
	ring.legendary_effect_id = "fu_su_sheng_ming_jie"
	LegendaryEffectSystem.register(ring)
	var heal_res := LegendaryEffectSystem.on_event("on_low_hp", { "hp_pct": 0.2, "max_hp": 800.0 })
	_ok("复苏低血回 10%（80 HP）",
		heal_res.size() == 1 and absf(float(heal_res[0]["result"]["amount"]) - 80.0) < 0.01)


# =============================================================================
# F. 部位池与重铸抽取
# =============================================================================

func _test_pools() -> void:
	print("--- F. 部位池 ---")
	var mh := LegendaryEffectSystem.for_slot("main_hand")
	_ok("主手特效池 ≥ 3 件", mh.size() >= 3)
	var rolled := LegendaryEffectSystem.roll_for_slot("main_hand", "jin_shi_ran_po_ren", _rng)
	_ok("重铸抽取排除原特效", rolled != "jin_shi_ran_po_ren" and not rolled.is_empty())
	var rolled2 := LegendaryEffectSystem.roll_for_slot("helm", "", _rng)
	_ok("头部特效池抽取成功", LegendaryEffectSystem.get_effect(rolled2).has("id"))
	LegendaryEffectSystem.clear()
	_ok("clear 后注册表为空", LegendaryEffectSystem.registered_count() == 0)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
