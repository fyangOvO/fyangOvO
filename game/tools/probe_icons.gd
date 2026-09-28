extends Node
## 臨時探針（2026-09-24）：驗證 TEX 表新登記的 59 條圖標真的載得到。
## 用途：光把檔案與 TEX 條目放上去還不夠 —— 必須確認 `UISkin.texture()` 回非 null。

func _ready() -> void:
	var affix_keys: Array[String] = [
		"flat_attack", "pct_attack", "crit_chance", "crit_damage", "attack_speed",
		"elemental_damage", "armor_penetration", "magic_find", "flat_hp", "pct_hp",
		"flat_armor", "pct_armor", "dodge", "block_chance", "thorns", "life_regen",
		"fire_resist", "cold_resist", "lightning_resist", "poison_resist",
		"max_resource", "resource_regen", "cooldown_reduction", "skill_cost_reduction",
		"pickup_radius", "gold_gain", "xp_gain", "move_speed", "life_on_hit", "kill_heal",
		"skill_level", "all_attributes", "echo_strike", "ailment_duration", "ailment_chance",
		"ailment_effect", "burn_damage", "chill_damage", "poison_damage", "shock_damage",
		"curse_damage", "shadow_resist", "physical_resist", "all_resist",
		"elemental_penetration", "resist_penetration", "all_element_damage", "damage_vs_ailment",
	]
	var ok := 0
	var miss: Array[String] = []
	for k in affix_keys:
		var t := UISkin.affix_icon(k)
		if t == null:
			miss.append(k)
		else:
			ok += 1
	print("[icon] affix 載入成功 %d / %d" % [ok, affix_keys.size()])
	if not miss.is_empty():
		print("       缺: %s" % ", ".join(miss))
		print("       尺寸抽樣: %s" % (UISkin.affix_icon(affix_keys[0]).get_size() if ok > 0 else "n/a"))

	var eok := 0
	var emiss: Array[String] = []
	for k in ["physical", "fire", "cold", "lightning", "poison", "shadow"]:
		var t := UISkin.element_icon(k)
		if t == null:
			emiss.append(k)
		else:
			eok += 1
	print("[icon] elem 載入成功 %d / 6" % eok)
	if not emiss.is_empty():
		print("       缺: %s" % ", ".join(emiss))

	var rok := 0
	var rmiss: Array[String] = []
	for k in ["fire", "cold", "lightning", "poison", "shadow"]:
		var t := UISkin.resist_icon(k)
		if t == null:
			rmiss.append(k)
		else:
			rok += 1
	print("[icon] resist 載入成功 %d / 5" % rok)
	if not rmiss.is_empty():
		print("       缺: %s" % ", ".join(rmiss))

	# 負向：物理抗性應為 null（走護甲，不該有圖標）
	print("[icon] resist_physical 應為 null → %s" % ("OK(null)" if UISkin.resist_icon("physical") == null else "意外有圖標"))
	# 取樣尺寸
	var t2 := UISkin.element_icon("fire")
	if t2 != null:
		print("[icon] elem_fire 尺寸 = %s（應 24x24）" % t2.get_size())
	var t3 := UISkin.affix_icon("flat_attack")
	if t3 != null:
		print("[icon] affix_flat_attack 尺寸 = %s（應 32x32）" % t3.get_size())
	get_tree().quit()
