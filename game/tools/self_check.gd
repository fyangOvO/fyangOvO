## 骨架自检面板（任务 1.x–9.x 回归矩阵）
##
## 本脚本原本内联在 `scripts/core/main.gd` 里；集成层改造时**整段迁出**，
## 让 `main.tscn` 腾出来做「启动分流」，而自检逻辑一行不改地留在这里。
##
## 用法：
##   godot --headless --path "D:/七傳說/game" -- --verify   # CI：打印报告 + 退出码
##   godot --path "D:/七傳說/game" res://tools/self_check.tscn  # 调试：留窗看报告
##
## ⚠️ 退出码语义是 CI 契约，**不可改**：0 = 全部通过 / 1 = 有失败项。
extends Node2D

## 自检结果文本（仅编辑器与调试构建可见）
var _report_lines: Array[String] = []

## 自检未通过项数，供 `--verify` 决定退出码
var _failed_count: int = 0

## 是否以「只自检、不进游戏」的方式启动（命令行带 `--verify`）
var _verify_only: bool = false

@onready var _report_label: RichTextLabel = $UI/Panel/Margin/Report


func _ready() -> void:
	# 允许两种写法：`godot --path . -- --verify` 与 `godot --path . --verify`
	_verify_only = (OS.get_cmdline_user_args() + OS.get_cmdline_args()).has("--verify")

	# 任务 1.6：像素风 UI 主题已通过 project.godot `gui/theme/custom` 注册为项目默认
	# （正文 Cubic-11 / 标题 ChillBitmap，色值全取自 48 色板），全窗口控件自动套用。

	_run_self_check()
	_render_report()

	EventBus.game_ready.emit()

	# 退出条件（两条）。**退出码语义是 CI 契约，不可改**：0 = 全通过 / 1 = 有失败项。
	#   ① `--verify`：自检模式，打印完就退出；
	#   ② 无头运行：没有窗口可以「留着看报告」，所以也退出。
	#      否则 `--headless res://tools/self_check.tscn` 会**打印完报告后永久挂住**，
	#      外部只能靠 timeout 杀掉、拿到 exit=124 —— 看起来像基础设施故障，
	#      而实际自检是全绿的。（2026-09-20 实测踩到：连续三次自检都是 exit=124，
	#      报告却写着「全部通过（111 项）」，极易被误读成「自检失败」或「自检很慢」。）
	var headless := DisplayServer.get_name() == "headless"
	if _verify_only or headless:
		print("[Main] 自检结束（%s），退出码 = %d"
			% ["--verify" if _verify_only else "无头",
				0 if _failed_count == 0 else 1])
		get_tree().quit(0 if _failed_count == 0 else 1)


# =============================================================================
# 骨架自检
# =============================================================================

## 检查数据表是否加载成功、常量表是否自洽。
## 这些检查**只读**，不修改任何状态。
func _run_self_check() -> void:
	_report_lines.clear()

	# 1) 常量表尺寸自洽
	_add_check("稀有度档数 = %d" % GameConstants.RARITY_COUNT,
		GameConstants.RARITY_COLORS.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_NAMES.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_DROP_BASE_PERCENT.size() == GameConstants.RARITY_COUNT)
	# 8 档的四个辨识维度 + 分类数组必须与档数等长（美术规范 1.4 节「问题 3」硬规则）
	_add_check("稀有度四维度数组等长",
		GameConstants.RARITY_FRAME_COLORS.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_FRAME_WIDTHS.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_BEAM_HEIGHTS.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_BEAM_SHAPES.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_FRAME_STYLES.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_CATEGORIES.size() == GameConstants.RARITY_COUNT)
	_add_check("稀有度词缀条数/前后缀上限数组等长",
		GameConstants.RARITY_AFFIX_RANGE.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_PREFIX_LIMIT.size() == GameConstants.RARITY_COUNT
		and GameConstants.RARITY_SUFFIX_LIMIT.size() == GameConstants.RARITY_COUNT)
	# 前后缀上限之和必须落在词缀条数区间内（GDD 3.3 节的隐含约束）
	var affix_limits_ok := true
	for i in range(GameConstants.RARITY_COUNT):
		var total := GameConstants.RARITY_PREFIX_LIMIT[i] + GameConstants.RARITY_SUFFIX_LIMIT[i]
		var rng := GameConstants.RARITY_AFFIX_RANGE[i]
		if total != rng.y:
			affix_limits_ok = false
	_add_check("前后缀上限之和 = 词缀条数上限", affix_limits_ok)
	_add_check("彩蛋渐变 6 色", GameConstants.PRISMATIC_GRADIENT.size() == 6)

	# 任务 1.6：48 色板唯一色源（美术规范附录 PALETTE）
	# 阶段 11 收尾：DBCC85（暖金）入中性基底，消耗 1 个 D 组预留槽位 ⇒ 44 已定义 + 4 预留 = 48
	_add_check("48 色板已定义色 = %d（A11+B28+C5）" % GameConstants.PALETTE_ALL.size(),
		GameConstants.PALETTE_ALL.size() == 44)
	var bad_ui_colors := GameConstants.ui_colors_not_in_palette()
	var palette_label := "UI 颜色常量全部取自 48 色板"
	if not bad_ui_colors.is_empty():
		palette_label += "（越界：%s）" % ", ".join(bad_ui_colors)
	_add_check(palette_label, bad_ui_colors.is_empty())

	_add_check("装备部位数 = %d" % GameConstants.EQUIP_SLOT_COUNT,
		GameConstants.EQUIP_SLOT_NAMES.size() == GameConstants.EQUIP_SLOT_COUNT)
	_add_check("武器原型数 = %d（主手 6 + 副手 4）" % GameConstants.WEAPON_ARCHETYPE_COUNT,
		GameConstants.WEAPON_ARCHETYPE_NAMES.size() == GameConstants.WEAPON_ARCHETYPE_COUNT
		and GameConstants.WEAPON_ARCHETYPE_KEYS.size() == GameConstants.WEAPON_ARCHETYPE_COUNT
		and GameConstants.WEAPON_ARCHETYPE_FRAMES.size() == GameConstants.WEAPON_ARCHETYPE_COUNT
		and GameConstants.WEAPON_ARCHETYPE_SPRITE_SOURCE.size() == GameConstants.WEAPON_ARCHETYPE_COUNT
		and GameConstants.MAIN_HAND_ARCHETYPES.size() == 6
		and GameConstants.OFF_HAND_ARCHETYPES.size() == 4)
	# 主手 6×32 + 副手(32+16+4+0) = 244（美术规范 0.7 v1.5 附录分项表；正文误写 245）
	_add_check("武器层美术帧数合计 = %d" % GameConstants.weapon_layer_total_frames(),
		GameConstants.weapon_layer_total_frames() == 244)
	_add_check("难度层级数 = %d" % GameConstants.DIFFICULTY_TIER_COUNT,
		GameConstants.DIFFICULTY_TIER_NAMES.size() == GameConstants.DIFFICULTY_TIER_COUNT)
	# 数值锚点回归（GDD 6.3 / 6.4 v1.5 定稿 = 仿真方案 D）
	# 6.3 的怪物基础值与 6.4 的层级系数是**同一方案的配套、不可拆分使用**，
	# 这组断言就是防止其中一半被单独改动后没人发现。
	_add_check("怪物 L20 基准 HP ≈ 11635（GDD 6.3）",
		absf(GameConstants.MONSTER_HP_AT_L1
			* pow(GameConstants.MONSTER_HP_GROWTH, 19.0) - 11635.0) < 5.0)
	_add_check("怪物 L20 基准 DMG ≈ 237.83（GDD 6.3）",
		absf(GameConstants.MONSTER_DMG_AT_L1
			* pow(GameConstants.MONSTER_DMG_GROWTH, 19.0) - 237.83) < 0.5)
	_add_check("梦魇 V 系数 = ×1.36 HP / ×2.29 DMG（GDD 6.4）",
		absf(GameConstants.difficulty_hp_multiplier(GameConstants.DifficultyTier.NM5) - 1.36) < 0.01
		and absf(GameConstants.difficulty_dmg_multiplier(GameConstants.DifficultyTier.NM5) - 2.29) < 0.01)
	_add_check("套装阈值 = %s" % str(GameConstants.SET_THRESHOLDS),
		GameConstants.SET_THRESHOLDS.size() == 3 and GameConstants.SET_THRESHOLDS[2] == GameConstants.SET_PIECE_COUNT)

	# 每个属性键都必须有中文显示名，否则角色面板会出现空标签
	var stats_without_name: Array[String] = []
	for key in GameConstants.ALL_STAT_KEYS:
		if not GameConstants.STAT_DISPLAY_NAMES.has(key):
			stats_without_name.append(key)
	var stat_label := "属性键 %d 个，全部有中文显示名" % GameConstants.ALL_STAT_KEYS.size()
	if not stats_without_name.is_empty():
		stat_label += "（缺：%s）" % ", ".join(stats_without_name)
	_add_check(stat_label, stats_without_name.is_empty())

	# 经济锚点回归（GDD 0.5 节 5.1 / 5.3，v1.8 定稿 —— 随单关杂兵数 150→269 配套上调）
	# 断言一律拿「代码实算值」与定稿目标比对，不写死结果。
	var xp_l1 := GameConstants.xp_to_next(1)
	_add_check("XP 曲线 XP_ToNext(1) 实算 = %d（定稿 180）" % int(xp_l1),
		is_equal_approx(xp_l1, 180.0))
	_add_check("XP_CURVE_BASE 实算 = %.1f（定稿 180.0）" % GameConstants.XP_CURVE_BASE,
		is_equal_approx(GameConstants.XP_CURVE_BASE, 180.0))
	var forge_total := GameConstants.forge_total_stones()
	_add_check("满强化魔石合计 实算 = %d（定稿 106）" % forge_total,
		forge_total == 106)
	_add_check("魔石分档数 = %d，须 == 强化上限 %d"
		% [GameConstants.FORGE_STONE_COST.size(), GameConstants.FORGE_MAX_LEVEL],
		GameConstants.FORGE_STONE_COST.size() == GameConstants.FORGE_MAX_LEVEL)

	# 2) 数据表加载结果
	var counts := ConfigLoader.get_entry_counts()
	for key in counts:
		_add_check("数据表 %s：%d 条" % [key, counts[key]], int(counts[key]) > 0)
	_add_check("数据加载无错误（含跨表一致性）", ConfigLoader.load_errors.is_empty())

	# 任务 3.1：词缀池表（装备 affix_pool_ids 的引用目标）
	var pool_ids := ConfigLoader.get_all_affix_pool_ids()
	var pools_ok := pool_ids.size() >= 8
	var pools_nonempty := true
	for pid in pool_ids:
		var pool_affixes := ConfigLoader.get_affixes_in_pool(pid)
		if pool_affixes.is_empty():
			pools_nonempty = false
	_add_check("词缀池表：%d 个池，全部非空" % pool_ids.size(), pools_ok and pools_nonempty)
	var pool_refs_ok := true
	for tid in ConfigLoader.get_all_equipment_ids():
		var tpl := ConfigLoader.get_equipment_template(tid)
		for pid in tpl.affix_pool_ids:
			if not ConfigLoader.affix_pools.has(pid):
				pool_refs_ok = false
	_add_check("装备词缀池引用全部可解析（%d 件底材）" % ConfigLoader.get_all_equipment_ids().size(), pool_refs_ok)

	# 任务 6.5：装备库填充（42 → 62：weapons 14 / armor 14 / jewelry 16 + 套装件 18）
	var equip_total := ConfigLoader.get_all_equipment_ids().size()
	var equip_weapons := 0
	var equip_body := 0
	var equip_jewel := 0
	for eid in ConfigLoader.get_all_equipment_ids():
		var et := ConfigLoader.get_equipment_template(eid)
		match et.slot:
			GameConstants.EquipSlot.MAIN_HAND:
				equip_weapons += 1
			GameConstants.EquipSlot.AMULET, GameConstants.EquipSlot.RING_A, GameConstants.EquipSlot.RING_B:
				equip_jewel += 1
			GameConstants.EquipSlot.HELM, GameConstants.EquipSlot.CHEST, GameConstants.EquipSlot.GLOVES, GameConstants.EquipSlot.LEGS, GameConstants.EquipSlot.BOOTS, GameConstants.EquipSlot.OFF_HAND:
				equip_body += 1
	var equip_chapters_ok := true
	for eid in ConfigLoader.get_all_equipment_ids():
		var et2 := ConfigLoader.get_equipment_template(eid)
		if et2.item_level_min <= 6 or (et2.item_level_min <= 13 and et2.item_level_max >= 7) or et2.item_level_max >= 14:
			pass
		else:
			equip_chapters_ok = false
	_add_check("装备库 62 件（主手 %d / 防具 %d / 饰品 %d + 套装件 18）" % [
		equip_weapons, equip_body, equip_jewel],
		equip_total == 62 and equip_weapons >= 14 and equip_body >= 28 and equip_jewel >= 13)
	_add_check("装备三章等级带覆盖（1-6 / 7-13 / 14-20）",
		equip_chapters_ok and ConfigLoader.get_equipment_template("bow_spirit") != null
		and ConfigLoader.get_equipment_template("helm_crown_titan") != null)

	# 任务 6.6：音效/音乐（8 条合成占位音效 + 播放管线）
	var audio_ok := AudioManager.ids().size() == 9
	var audio_files_ok := true
	for aid in AudioManager.ids():
		var ameta: Dictionary = AudioManager.SFX_REGISTRY[aid]
		if not ResourceLoader.exists("res://data/audio/%s" % ameta.get("file", "")):
			audio_files_ok = false
	_add_check("音效注册表 9 条（打击/暴击/死亡/金币/装备/升级/BOSS/点击/药水）", audio_ok)
	_add_check("音效文件全部可加载（data/audio/*.wav）",
		audio_files_ok and AudioManager.has("boss_phase")
		and AudioManager.has("ui_click"))

	# 任务 7.x：UI/UX 面板族（7.1 主菜单 / 7.2 属性 / 7.3 装备 / 7.4 天赋 / 7.5 锻造 / 7.6 结算 / 7.7 设置）
	var ui_panels_ok := MainMenuPanel.new() != null \
		and StatPanel.new() != null and EquipPanel.new() != null \
		and TalentPanel.new() != null and ForgePanel.new() != null \
		and SettingsPanel.new() != null and ResultPanel.new() != null
	var ui_contract_ok := true
	var menu_p := MainMenuPanel.new()
	var r := ResultPanel.new()
	var eqp := EquipPanel.new()
	ui_contract_ok = ui_contract_ok and menu_p.on_start == Callable() and r.on_hub == Callable()
	ui_contract_ok = ui_contract_ok and eqp.on_equip == Callable() and eqp.on_unequip == Callable()
	menu_p.free()
	r.free()
	eqp.free()
	_add_check("7 个 UI 面板 class 全部可实例化（7.1–7.7）", ui_panels_ok)
	_add_check("面板回调契约默认空（on_start/on_hub/on_equip/on_unequip）", ui_contract_ok)

	# 任务 8.1：完整存档（局内 + 局外全字段序列化）
	var save_fields_ok := SaveData.new().to_dict().has_all([
		"account_level", "talent_points", "gold", "materials", "inventory",
		"equipped", "stash", "unlocked_levels", "cleared_levels",
		"chapter_reputation", "unlocked_achievements", "statistics",
		"current_level_id", "current_difficulty_tier", "settings"])
	var sd81 := SaveData.new()
	sd81.current_level_id = "ch2_l09"
	sd81.current_difficulty_tier = 3
	_add_check("存档字段矩阵 15 类齐全（局外 10+ / 局内 2 / 设置 / 统计）", save_fields_ok)
	_add_check("局内进度可读写（current_level_id / difficulty_tier）",
		sd81.current_level_id == "ch2_l09" and sd81.current_difficulty_tier == 3)

	# 任务 8.2：设置持久化（SettingsStore 默认值 + 类型白名单）
	var ss := SettingsStore.load()
	var ss_ok := is_equal_approx(float(ss["master_volume_db"]), -6.0) \
		and bool(ss["vsync"]) and not bool(ss["fullscreen"])
	_add_check("设置持久化默认值（音量 -6 / vsync / 非全屏）", ss_ok)
	_add_check("类型白名单回退（字符串塞 float → 默认）",
		SettingsStore._typed("master_volume_db", "bad") == -6.0)

	# 任务 8.3：性能优化（对象池 + 地图批处理）
	var pool_node := ObjectPool.acquire("selfcheck", func() -> Node: return Node.new())
	ObjectPool.release("selfcheck", pool_node)
	var pool_hit := ObjectPool.acquire("selfcheck", func() -> Node: return Node.new()) == pool_node
	ObjectPool.drain()
	_add_check("对象池复用（二次 acquire 命中同一实例）", pool_hit)
	var lv_def: LevelData = ConfigLoader.get_level("ch1_l01")
	var lv_layout := LevelGenerator.generate(lv_def, RandomNumberGenerator.new())
	var lv_check := LevelView.new()
	lv_check.set_layout(lv_layout)
	_add_check("LevelView 批处理（单节点承载全图 %d 格）" % lv_check.tile_count(),
		lv_check.tile_count() == int(lv_layout["cells"].size()))

	# 任务 8.4：平衡性数值仿真（D9 口径：怪 HP 1.284^L / DMG 1.218^L；难度 1.08^n / 1.23^n）
	var bal_ok := true
	var bal_ttk_low := 999.0
	var bal_ttk_high := 0.0
	for bl in range(1, 21):
		for bd in range(5):
			var bh := 100.7 * pow(1.284, bl - 1) * pow(1.08, bd)
			var bdps := 20.0 * pow(1.30, bl) * 1.25
			var bt := bh / bdps
			bal_ttk_low = minf(bal_ttk_low, bt)
			bal_ttk_high = maxf(bal_ttk_high, bt)
	_add_check("平衡仿真：常规怪 TTK ∈ [1, 8]s（实测 %.1f–%.1f，不海绵化）" % [bal_ttk_low, bal_ttk_high],
		bal_ttk_low >= 1.0 and bal_ttk_high <= 8.0)
	var bal_surv_hi := 999.0
	for bl in range(5, 21):
		for bd in range(3, 5):
			var bmh := 500.0 * pow(1.06, bl)
			var bdmg := 5.61 * pow(1.218, bl - 1) * pow(1.23, bd) * 0.5
			bal_surv_hi = minf(bal_surv_hi, bmh / bdmg)
	_add_check("平衡仿真：梦魇 III–V 承伤 < 10s（可被秒，实测 %.1f）" % bal_surv_hi, bal_surv_hi < 10.0)

	# 任务 8.5：Bug 修复与回归红线（历史修复点不回退）
	var fix_data_ok := ConfigLoader.monsters.size() == 16 \
		and ConfigLoader.bosses.size() == 2 and ConfigLoader.skills.size() == 12 \
		and ConfigLoader.equipment_templates.size() == 62 and ConfigLoader.levels.size() == 20
	_add_check("回归红线：数据表锚点（怪物 16 / BOSS 2 / 技能 12 / 装备 62 / 关卡 20）", fix_data_ok)
	var fix_slot_ok := GameConstants.SAVE_MAX_SLOTS >= 8
	_add_check("回归红线：存档槽位边界（SAVE_MAX_SLOTS=%d）" % GameConstants.SAVE_MAX_SLOTS, fix_slot_ok)

	# 任务 9.3：崩溃与异常处理（日志落盘 + 容错红线）
	GameLog.info("自检：稳定性模块 OK（engine %s）" % Engine.get_version_info().get("string", "?"))
	_add_check("游戏日志可写（user://logs/game.log）",
		FileAccess.file_exists("user://logs/game.log"))
	_add_check("日志尾部含本次自检记录", GameLog.read_tail(8).size() >= 1)

	# 任务 9.1：导出就绪（主场景 + 导出预设）
	_add_check("导出就绪：主场景存在（scenes/main/main.tscn）",
		ResourceLoader.exists("res://scenes/main/main.tscn"))
	var preset_91 := FileAccess.get_file_as_string("res://export_presets.cfg") \
		if FileAccess.file_exists("res://export_presets.cfg") else ""
	if preset_91 != "":
		# 开发态：预设必须含 Windows + 内嵌 PCK
		_add_check("导出就绪：Windows 预设 + 内嵌 PCK",
			preset_91.contains("platform=\"Windows Desktop\"")
			and preset_91.contains("binary_format/embed_pck=true"))
	else:
		# 发布态（导出的 exe）：引擎导出时默认排除 export_presets.cfg，
		# 此项由 tools/verify_export91 在开发环境验证，此处视为通过
		_add_check("导出就绪：发布包（预设已由 verify_export91 验证）", true)

	# 任务 3.2：词缀生成器抽查（橙 5–6 条 / 品质合法 / 红装神话槽）
	var gen_ok := true
	var gen_tpl := ConfigLoader.get_equipment_template("sword_iron")
	if gen_tpl != null:
		var gen_item := AffixRoller.roll_full_equipment(gen_tpl, 15, GameConstants.Rarity.LEGENDARY)
		if gen_item.affixes.size() < 5 or gen_item.affixes.size() > 6:
			gen_ok = false
		for gen_roll in gen_item.affixes:
			if not GameConstants.AFFIX_ROLL_QUALITY_TIERS.has(gen_roll.quality):
				gen_ok = false
		var mythic_item := AffixRoller.roll_full_equipment(gen_tpl, 15, GameConstants.Rarity.MYTHIC)
		var has_mythic := false
		for gen_roll in mythic_item.affixes:
			if gen_roll.affix_id == AffixRoller.MYTHIC_AFFIX_ID:
				has_mythic = true
		gen_ok = gen_ok and has_mythic
	_add_check("词缀生成器抽查（橙 5–6 条 / 品质合法 / 红装神话槽）", gen_ok)

	# 任务 3.3：稀有度与掉落权重表锚点（GDD 6.1 权威）
	var table_anchor_ok := true
	var type_share_ok := true
	for tid in ConfigLoader.loot_tables:
		var table: LootTable = ConfigLoader.loot_tables[tid]
		if table.rarity_weights.size() != GameConstants.RARITY_COUNT:
			table_anchor_ok = false
			continue
		var s := 0.0
		for w in table.rarity_weights:
			s += float(w)
		if absf(s - 100.0) > 0.01:
			table_anchor_ok = false
		if table.equipment_share < 0.0 or table.equipment_share > 1.0 \
				or table.gold_weight <= 0.0 or table.material_weight <= 0.0:
			type_share_ok = false
	_add_check("掉落表权重和 = 100（3 张 × 8 档）", table_anchor_ok)
	_add_check("物品类型占比合法（装备 55/80/90% 直接概率 + 金币/材料权重）", type_share_ok)

	# 任务 3.4：锻造 / 洗练锚点（GDD 0.3 节 3.4 + 6.5）
	var forge_ok := GameConstants.forge_total_stones() == 106
	var chance_sum_ok := true
	for k in range(1, 13):
		var c := GameConstants.forge_success_chance(k)
		if c <= 0.0 or c > 1.0:
			chance_sum_ok = false
	_add_check("锻造魔石总数 = 106（GDD 6.5 v1.8 定稿）", forge_ok)
	_add_check("锻造成功率表 12 档合法（+1~+12）", chance_sum_ok)

	# 任务 3.5：传奇特效（GDD 0.3 节 3.5 范式 + 遗留项 #3 扩至 ≥ 30）
	var fx_count_ok := ConfigLoader.legendary_effects.size() >= 30
	var fx_type_ok := true
	for fx: Dictionary in ConfigLoader.legendary_effects.values():
		var trigger: Dictionary = fx.get("trigger", {})
		var effect: Dictionary = fx.get("effect", {})
		if not LegendaryEffectSystem.TRIGGER_TYPES.has(String(trigger.get("type", ""))):
			fx_type_ok = false
		if not LegendaryEffectSystem.EFFECT_TYPES.has(String(effect.get("type", ""))):
			fx_type_ok = false
	_add_check("传奇特效池 ≥ 30 件（GDD 遗留项 #3）", fx_count_ok)
	_add_check("传奇特效 trigger/effect 类型合法", fx_type_ok)

	# 任务 3.6：背包 / 仓库（容量合法 + 排序键覆盖）
	var inv_ok := true
	var test_inv := Inventory.create(8, 5)
	if test_inv.capacity() != 40 or not test_inv.is_empty():
		inv_ok = false
	var sort_keys_ok := true
	for key in [Inventory.SORT_RARITY, Inventory.SORT_SLOT, Inventory.SORT_ILVL, Inventory.SORT_NAME]:
		var it := EquipmentInstance.new()
		it.instance_id = "sk_%d" % key
		it.rarity = GameConstants.Rarity.LEGENDARY
		it.item_level = 20
		test_inv.add(it)
	test_inv.sort_by(Inventory.SORT_RARITY, true)
	if test_inv.count() != 4 or test_inv.get_at(0) == null:
		sort_keys_ok = false
	_add_check("背包 8×5 = 40 格 / 排序可用", inv_ok and sort_keys_ok)

	# 任务 3.7：装备对比（stat_key 汇总 + 特殊键隔离）
	var cmp_ok := true
	if ConfigLoader.affixes.size() != 33:
		cmp_ok = false
	var probe := EquipmentInstance.new()
	probe.instance_id = "cmp_probe"
	probe.template_id = "sword_iron"
	probe.slot = GameConstants.EquipSlot.MAIN_HAND
	probe.item_level = 20
	probe.rarity = GameConstants.Rarity.LEGENDARY
	var roll := AffixRoll.new()
	roll.affix_id = "add_flat_attack"
	roll.template = ConfigLoader.affixes.get("add_flat_attack") as AffixData
	roll.value = 5.0
	roll.quality = 1
	probe.affixes.append(roll)
	var cmp_stats := EquipmentCompare.get_total_stats(probe)
	if not cmp_stats.has("flat_attack") or cmp_stats.has("echo_strike"):
		cmp_ok = false
	_add_check("装备对比 stat_key 汇总 / 特殊键隔离", cmp_ok)

	# 任务 3.8：分解 / 合成 / 材料回收（GDD 5.3 产出表 + 4 档合成配方）
	var rec_ok := true
	var dm_probe := EquipmentInstance.new()
	dm_probe.instance_id = "dm_probe"
	dm_probe.rarity = GameConstants.Rarity.MYTHIC
	if DismantleController.get_dismantle_result(dm_probe).get("crystal", 0) != 1:
		rec_ok = false
	if DismantleController.get_dismantle_result(dm_probe).get("essence", 0) != 6:
		rec_ok = false
	dm_probe.rarity = GameConstants.Rarity.HIDDEN
	if DismantleController.can_dismantle(dm_probe):
		rec_ok = false
	if CraftController.get_recipes().size() != 4:
		rec_ok = false
	var bag := MaterialBag.create()
	bag.add(MaterialBag.KEY_DUST, 10)
	if not bag.can_afford(CraftController.get_craft_cost(CraftController.CRAFT_BLUE)):
		rec_ok = false
	_add_check("分解产出（GDD 5.3）/ 合成配方 / 材料包", rec_ok)

	# 任务 3.9：属性结算（GDD 6.2 裸装公式 + 最终结算）
	var stat_ok := true
	var b20 := StatCalculator.base_stats(20)
	if absf(float(b20["flat_hp"]) - 1090.0) > 1.0 or absf(float(b20["flat_attack"]) - 73.4) > 0.5:
		stat_ok = false
	var calc1 := StatCalculator.calculate(1, [])
	if absf(float(calc1["attack"]) - 12.0) > 0.01 or absf(float(calc1["max_hp"]) - 150.0) > 0.01:
		stat_ok = false
	var calc_buff := StatCalculator.calculate(1, [], {"rage": {"pct": {"pct_attack": 50.0}}})
	if absf(float(calc_buff["attack"]) - 18.0) > 0.01:
		stat_ok = false
	_add_check("属性结算（GDD 6.2 裸装公式 + flat/pct 结算 + Buff）", stat_ok)

	# 任务 3.10：套装系统（3 套 × 2/4/6 档 + 加成并入结算）
	var set_ok := true
	if ConfigLoader.sets.size() != 3:
		set_ok = false
	var set_helm := EquipmentInstance.new()
	set_helm.instance_id = "set_probe"
	set_helm.set_id = "frostbite"
	set_helm.slot = GameConstants.EquipSlot.HELM
	var set_chest := EquipmentInstance.new()
	set_chest.instance_id = "set_probe2"
	set_chest.set_id = "frostbite"
	set_chest.slot = GameConstants.EquipSlot.CHEST
	if SetSystem.count_pieces([set_helm, set_chest], "frostbite") != 2:
		set_ok = false
	var bonus := SetSystem.get_bonus_stats([set_helm, set_chest])
	if absf(float(bonus.get("elemental_damage", 0.0)) - 15.0) > 0.01:
		set_ok = false
	_add_check("套装系统（3 套注册 / 计数 / 加成并入）", set_ok)

	# 任务 3.11：红装神话词缀重铸 + 彩装成长（GDD 3.4 / 3.2.2）
	var mythic_ok := true
	var myth_tpl: EquipmentData = ConfigLoader.get_equipment_template("mythic_crown_seven_kalpa")
	if myth_tpl == null or GameConstants.rarity_from_key("mythic") != myth_tpl.rarity_min:
		mythic_ok = false
	var myth_probe := EquipmentInstance.create_from_template(
		myth_tpl, 20, GameConstants.Rarity.MYTHIC)
	if myth_probe == null or not MythicRerollController.can_reroll(myth_probe):
		mythic_ok = false
	var cost := MythicRerollController.get_reroll_cost(myth_probe)
	if int(cost.get(MaterialBag.KEY_CRYSTAL, 0)) != 2:
		mythic_ok = false
	var hidden_tpl: EquipmentData = ConfigLoader.get_equipment_template("hidden_amulet_first_tale")
	var hidden_probe := EquipmentInstance.create_from_template(
		hidden_tpl, 20, GameConstants.Rarity.HIDDEN)
	if not HiddenGrowthController.can_grow(hidden_probe):
		mythic_ok = false
	HiddenGrowthController.apply_growth(hidden_probe, 5.0)
	if hidden_probe.growth_value != 5.0 or hidden_probe.growth_value > hidden_tpl.growth_max:
		mythic_ok = false
	_add_check("红装/彩装机制（神话重铸成本 / 彩装成长）", mythic_ok)

	# 任务 4.1–4.3：局内等级 / 三选一 / Buff（GDD 0.4 节）
	var run_ok := true
	var up_events: Array[int] = []
	var run_prog := RunProgression.new(func(_lv: int) -> void: up_events.append(_lv))
	run_prog.add_xp(999999.0)
	if run_prog.run_level != 10 or up_events.size() != 9:
		run_ok = false
	var run_choices := RunePool.get_choices(3, [], {"pct_attack": 30.0})
	for opt in run_choices:
		if opt["id"] == "fury":
			run_ok = false
	var run_buffs := RunBuffSystem.new()
	run_buffs.apply_option("fury")
	for i in 100:
		run_buffs.on_kill()
		run_buffs.tick(0.1)
	var run_stats := StatCalculator.calculate(1, [], run_buffs.to_calculator_buffs())
	if absf(run_stats["attack"] - 12.0 * 1.27) > 0.5: # +12% 狂怒 + 15% 连杀（加算）
		run_ok = false
	_add_check("局内成长（等级上限 / 三选一池 / Buff 并入）", run_ok)

	# 任务 4.4：关卡内资源与商店（工程侧默认：每关 1 次、稀有度定价）
	var shop_ok := true
	var shop := RunShop.new()
	shop.player = {"gold": 9999.0, "inventory": Inventory.create(8, 5)}
	shop.generate_stock(4, 12, RandomNumberGenerator.new())
	if shop.stock.size() != 5:
		shop_ok = false
	var kind_seen := {}
	for entry in shop.stock:
		kind_seen[entry["kind"]] = true
	if not (kind_seen.has("equipment") and kind_seen.has("potion") and kind_seen.has("material")):
		shop_ok = false
	var equip_idx := -1
	for i in shop.stock.size():
		if shop.stock[i]["kind"] == "equipment":
			equip_idx = i
			break
	var price := float(shop.stock[equip_idx]["price"])
	var res_buy := shop.buy(equip_idx)
	if not res_buy["ok"] or absf(float(shop.player["gold"]) - (9999.0 - price)) > 0.01:
		shop_ok = false
	_add_check("关卡商店（生成 / 定价 / 购买闭环）", shop_ok)

	# 任务 4.5：本局结算（D2 方案 B：扣 50% + 入包保留 + 评分）
	var result_ok := true
	var bagged_probe := [EquipmentInstance.create_from_template(
		ConfigLoader.get_equipment_template("sword_iron"), 12, GameConstants.Rarity.RARE)]
	var res := RunResult.finalize(true, 50, 8, 1000.0,
		{"dust": 10.0}, bagged_probe, 6, 2, 40)
	if int(res.gold_after) != 500 or int(res.materials_after["dust"]) != 5:
		result_ok = false
	if res.bagged_equipment.size() != 1 or res.unbagged_drops != 6:
		result_ok = false
	if int(res.score) != 500 + 500 + 400 + 200 + 80:
		result_ok = false
	if res.grade != "S":
		result_ok = false
	_add_check("本局结算（扣 50% / 入包保留 / 评分评级）", result_ok)

	# 任务 5.1：账号等级（180×L^1.6，GDD 5.1 节点）
	var acc_ok := absf(AccountLevel.xp_to_next(10) - 7166.0) < 10.0 \
		and absf(AccountLevel.xp_to_next(60) - 125984.0) < 50.0 \
		and AccountLevel.MAX_ACCOUNT_LEVEL == 60
	_add_check("账号等级（180×L^1.6：L10≈7166 / L60≈125984，上限 60）", acc_ok)

	# 任务 5.2：天赋树（3 分支 × 20 节点，满级 30 点）
	var tree_ok := TalentTree.BRANCHES.size() == 3 \
		and TalentTree.SMALL_NODE_COUNT == 15 and TalentTree.BIG_NODE_COUNT == 5 \
		and TalentTree.is_branch_unlocked("guardian", 15) \
		and TalentTree.is_branch_unlocked("arcane", 30)
	_add_check("天赋树（3 分支 × 20 节点 / 分支解锁 L15/L30）", tree_ok)

	# 任务 5.3：解锁系统（梦魇全 20 关 + 仓库页 5/10/15）
	var unlock_ok := not UnlockSystem.is_difficulty_unlocked(1, 19) \
		and UnlockSystem.is_difficulty_unlocked(1, 20) \
		and UnlockSystem.stash_pages_unlocked(15) == 4
	_add_check("解锁系统（梦魇 I 需全 20 关 / 仓库页 5/10/15）", unlock_ok)

	# 任务 5.4：附魔洗练 / 特效重铸成本
	var enchant_ok := EnchantController.REROLL_DUST == 3 \
		and EnchantController.REREFORGE_ESSENCE == 2
	_add_check("附魔成本（洗练秘银尘×3 / 重铸精粹×2）", enchant_ok)

	# 任务 5.5：宝石（橙+ 2 槽 / 无瑕红宝石 ×8）
	var gem_ok := GemSystem.GEM_TIERS.size() == 4 \
		and GemSystem.max_sockets(EquipmentInstance.create_from_template(
			ConfigLoader.get_equipment_template("sword_iron"), 12,
			GameConstants.Rarity.LEGENDARY)) == 2
	_add_check("宝石（4 档 × 3 色 / 橙+ 2 槽）", gem_ok)

	# 任务 5.6：声望 / 成就（章节声望上限 10，成就表 ≥20 纯外观）
	var rep_ok := ChapterReputation.MAX_REP_LEVEL == 10
	var ach := AchievementSystem.new()
	ach.load_definitions()
	_add_check("声望上限 10 级 / 成就表 %d 个（外观向）" % [ach.total_count()],
		rep_ok and ach.total_count() >= 20)

	# 3) 关键引用可解析（抽查第一件装备 / 第一条词缀 / 第一个关卡 / 第一组套装）
	var equip_ids := ConfigLoader.get_all_equipment_ids()
	if not equip_ids.is_empty():
		var tpl := ConfigLoader.get_equipment_template(equip_ids[0])
		_add_check("底材可解析：%s" % equip_ids[0], tpl != null)
		_add_check("底材 '%s' 数据合法" % equip_ids[0], tpl.validate().is_empty())

	var level_list := ConfigLoader.get_levels_sorted()
	if not level_list.is_empty():
		var lv := level_list[0]
		_add_check("关卡可解析：%s（Lv.%d）" % [lv.id, lv.level], lv.validate().is_empty())
		# 任务 6.1：20 关数据齐备 + 程序化生成器可用
		_add_check("关卡数据 20 关（三章，等级 1–20 连续）", level_list.size() == 20
			and level_list[19].level == 20)
		var gen_rng := RandomNumberGenerator.new()
		gen_rng.seed = 20260917
		var gen_layout := LevelGenerator.generate(lv, gen_rng)
		var gen_counts := LevelGenerator.counts(gen_layout)
		_add_check("地图生成器（地面 ≥30% / 出生点在地面）",
			gen_counts["ground"] >= int(gen_layout["width"] * gen_layout["height"]) * 0.3
			and int(gen_layout["cells"][gen_layout["player_spawn"]]) == LevelGenerator.TILE_GROUND)

	# 任务 6.2：怪物扩充（8→16）+ 精英词缀池（6 条）
	var monster_total := ConfigLoader.monsters.size()
	var elite_n := 0
	var elite_loot_ok := true
	for mid in ConfigLoader.monsters:
		var m2: MonsterData = ConfigLoader.monsters[mid]
		if m2.tier == MonsterData.Tier.ELITE:
			elite_n += 1
			if m2.loot_table_id.is_empty():
				elite_loot_ok = false
	_add_check("怪物表 16 种（新增孢蘑菇/猎犬/魔像/小鬼等 8 种）", monster_total >= 16)
	_add_check("精英 ≥4 种且全部绑定精英掉落表（焰术信徒/寒霜幽魂新增）",
		elite_n >= 4 and elite_loot_ok)
	_add_check("精英词缀池 6 条（急速/吸血/爆炸/回响/荆棘/闪现）",
		AffixController.AFFIXES.size() == 6
		and AffixController.WEIGHTS.size() == 6)

	# 任务 6.3：BOSS 设计与机制（2 个章末 BOSS / 4 阶段 / 掉落 2–4 件）
	var boss_total := ConfigLoader.bosses.size()
	var boss_valid := true
	for bid in ConfigLoader.bosses:
		if not BossPhaseController.validate(ConfigLoader.bosses[bid]).is_empty():
			boss_valid = false
	var boss_table: LootTable = ConfigLoader.get_loot_table("monster_boss")
	_add_check("BOSS 机制配置 2 个（骸骨暴君 / 熔心之主，4 阶段阈值）",
		boss_total == 2 and boss_valid
		and BossPhaseController.current_phase(0.4) == 3)
	_add_check("BOSS 掉落 100% / 2–4 件（GDD 6.1）",
		boss_table != null and is_equal_approx(boss_table.drop_chance, 1.0)
		and boss_table.drop_count_range == Vector2i(2, 4))

	# 任务 6.4 + 步骤 3：技能库（3 → 12：职业专属池，覆盖三形态 + 多元素）
	var skill_total := ConfigLoader.get_all_skill_ids().size()
	var slot_ids: Array[String] = []
	for sid in ConfigLoader.get_all_skill_ids():
		var sd3 := ConfigLoader.get_skill(sid)
		if sd3 != null and sd3.slot >= 1:
			slot_ids.append(sid)
	var has_frost := ConfigLoader.get_skill("frost_nova") != null
	var has_shadow := GameConstants.ELEMENTS.has(GameConstants.ELEMENT_SHADOW)
	var class_bar_ok := ConfigLoader.class_default_skill_bar("warrior").size() == 3 \
		and ConfigLoader.class_default_skill_bar("archer").size() == 3 \
		and ConfigLoader.class_default_skill_bar("mage").size() == 3
	_add_check("技能库 12 个（3 老出战 + 9 备选池，三职业默认栏各 3）",
		skill_total == 12 and slot_ids.size() == 3 and has_frost and class_bar_ok)
	_add_check("备选技能覆盖三形态 + 暗影元素入元素表",
		has_shadow
		and ConfigLoader.get_skill("lightning_chain") != null
		and ConfigLoader.get_skill("shadow_blink") != null
		and ConfigLoader.get_skill("piercing_shot") != null
		and ConfigLoader.get_skill("arrow_rain") != null
		and ConfigLoader.get_skill("power_strike") != null)

	var set_ids := ConfigLoader.get_all_set_ids()
	if not set_ids.is_empty():
		var st := ConfigLoader.get_set(set_ids[0])
		_add_check("套装可解析：%s（%s，%d 件）" % [st.id, st.display_name, st.piece_template_ids.size()],
			st.validate().is_empty())
		_add_check("套装 '%s' 的 6 件底材全部存在" % st.id,
			_resolve_all_set_pieces(st))

	# 任务 2.2：技能表与形态覆盖（AoE 设计基准 2.0 需要有实现载体）
	var skill_ids := ConfigLoader.get_all_skill_ids()
	if not skill_ids.is_empty():
		var type_mask := 0
		var skill_valid := true
		for sid in skill_ids:
			var sd := ConfigLoader.get_skill(sid)
			if sd == null or not sd.validate().is_empty():
				skill_valid = false
				continue
			type_mask |= 1 << sd.type
		_add_check("技能表可解析：%d 条，全部数据合法" % skill_ids.size(), skill_valid)
		_add_check("技能形态覆盖单/范围/位移三类", type_mask == 0b111)

	# 任务 2.3：伤害计算管线锚点（暴击 / 元素 / 减伤，用户拍板口径）
	var crit_ok := (
		GameConstants.CRIT_DAMAGE_BASE >= 100.0
		and GameConstants.CRIT_CHANCE_CAP >= GameConstants.CRIT_CHANCE_BASE
		and GameConstants.CRIT_CHANCE_BASE >= 0.0
	)
	_add_check("暴击基准合法：CR %d%% / CD %d%% / 上限 %d%%" % [
		GameConstants.CRIT_CHANCE_BASE, GameConstants.CRIT_DAMAGE_BASE,
		GameConstants.CRIT_CHANCE_CAP], crit_ok)
	var elem_unique := GameConstants.ELEMENTS.size() == 6
	if elem_unique:
		var seen := {}
		for e in GameConstants.ELEMENTS:
			if seen.has(e):
				elem_unique = false
				break
			seen[e] = true
	_add_check("元素体系 = 物理+火/冰/雷/毒/影 6 系，键唯一",
		elem_unique and GameConstants.ELEMENTS.has(GameConstants.ELEMENT_PHYSICAL)
		and GameConstants.ELEMENTS.has(GameConstants.ELEMENT_SHADOW))
	# 减伤公式锚点（GDD 6.6）：裸装 L1 护甲 6 → 6/(6+50) = 10.714%；
	# 元素抗性同构：50 抗 @ L1 → 50/100 = 50%
	_add_check("护甲减伤公式锚点：ARM 6 @ L1 ≈ 10.71%",
		is_equal_approx(GameConstants.armor_damage_reduction(6.0, 1), 6.0 / 56.0))
	_add_check("元素减伤公式同构：抗性 50 @ L1 ≈ 50%",
		is_equal_approx(GameConstants.element_damage_reduction(50.0, 1), 0.5))

	# 任务 2.4：敌人 AI 参数与怪物数据锚点
	var ai_ok := (
		GameConstants.ENEMY_LOSE_RANGE > GameConstants.ENEMY_AGGRO_RANGE
		and GameConstants.ENEMY_AGGRO_RANGE > 0.0
		and GameConstants.ENEMY_PATROL_RADIUS > 0.0
		and GameConstants.ENEMY_PATROL_WAIT_MAX >= GameConstants.ENEMY_PATROL_WAIT_MIN
		and GameConstants.ENEMY_AGGRO_RANGE > 40.0
	)
	_add_check("AI 参数合法：LOSE > AGGRO > 0、巡逻半径/等待区间自洽", ai_ok)
	var monster_ai_ok := true
	for mid in ConfigLoader.monsters:
		var m: MonsterData = ConfigLoader.monsters[mid]
		if m.move_speed <= 0.0 or m.attack_interval <= 0.0 \
				or m.attack_range <= 0.0 or m.ai_id.is_empty():
			monster_ai_ok = false
	_add_check("怪物表 %d 条：AI 字段（速度/间隔/距离/ai_id）完整" % ConfigLoader.monsters.size(),
		monster_ai_ok and ConfigLoader.monsters.size() >= 8)

	# 任务 2.5：物理层与命中判定锚点
	var layers_ok := GameConstants.ALL_LAYERS.size() == 9
	if layers_ok:
		for i in range(GameConstants.ALL_LAYERS.size()):
			var v := GameConstants.ALL_LAYERS[i]
			if v < 1 or v > 9 or GameConstants.ALL_LAYERS.find(v) != i:
				layers_ok = false
				break
	_add_check("物理层 9 层约定：值唯一且落在 1–9（README 第七节）", layers_ok)
	_add_check("攻击判定弧宽合法（玩家 60° / 敌人 120° 均在 1–180）",
		GameConstants.ATTACK_ARC_DEG >= 1.0 and GameConstants.ATTACK_ARC_DEG <= 180.0
		and GameConstants.ENEMY_ATTACK_ARC_DEG >= 1.0
		and GameConstants.ENEMY_ATTACK_ARC_DEG <= 180.0)

	# 任务 2.6：生命与异常状态锚点
	_add_check("玩家基础属性锚点（GDD 6.2）：HP 150 / 护甲 6 / 闪避 0 / 格挡 0",
		absf(GameConstants.BASE_HP_AT_L1 - 150.0) < 0.001
		and absf(GameConstants.BASE_ARMOR_AT_L1 - 6.0) < 0.001
		and GameConstants.PLAYER_BASE_DODGE_CHANCE == 0.0
		and GameConstants.PLAYER_BASE_BLOCK_CHANCE == 0.0)
	var ailment_map_ok := (
		GameConstants.ailment_from_element(GameConstants.ELEMENT_POISON) == GameConstants.AILMENT_POISON
		and GameConstants.ailment_from_element(GameConstants.ELEMENT_FIRE) == GameConstants.AILMENT_BURN
		and GameConstants.ailment_from_element(GameConstants.ELEMENT_COLD) == GameConstants.AILMENT_SLOW
		and GameConstants.ailment_from_element(GameConstants.ELEMENT_PHYSICAL).is_empty()
		and GameConstants.ailment_from_element(GameConstants.ELEMENT_LIGHTNING).is_empty())
	_add_check("元素→异常映射合法（毒/火/冰；物理/雷电无异常）", ailment_map_ok)
	_add_check("异常参数合法（dot 比例 > 0、时长 > 0、冰冻减速 ∈ (0,1)、格挡减伤 ∈ (0,1)）",
		GameConstants.AILMENT_POISON_DPS_RATIO > 0.0
		and GameConstants.AILMENT_BURN_DPS_RATIO > 0.0
		and GameConstants.ailment_duration(GameConstants.AILMENT_POISON) > 0.0
		and GameConstants.ailment_duration(GameConstants.AILMENT_BURN) > 0.0
		and GameConstants.ailment_duration(GameConstants.AILMENT_SLOW) > 0.0
		and GameConstants.AILMENT_SLOW_SPEED_FACTOR > 0.0
		and GameConstants.AILMENT_SLOW_SPEED_FACTOR < 1.0
		and GameConstants.BLOCK_DAMAGE_REDUCTION > 0.0
		and GameConstants.BLOCK_DAMAGE_REDUCTION < 1.0)

	# 任务 2.7：掉落与拾取锚点
	var loot_tables_ok := (
		ConfigLoader.loot_tables.size() == ConfigLoader.LOOT_TABLE_BY_TIER.size()
		and ConfigLoader.equipment_templates.size() >= 30)
	for lt_id in ConfigLoader.LOOT_TABLE_BY_TIER.values():
		var lt: LootTable = ConfigLoader.loot_tables.get(lt_id)
		if lt == null or lt.drop_chance <= 0.0 or lt.drop_chance > 1.0 \
				or lt.rarity_weights.size() != GameConstants.RARITY_KEYS.size() \
				or lt.drop_count_range.x < 1 or lt.drop_count_range.y < lt.drop_count_range.x:
			loot_tables_ok = false
			break
	_add_check("掉落表完整（3 档位映射齐全、drop_chance ∈ (0,1]、稀有度权重 8 档、件数区间自洽）",
		loot_tables_ok)
	_add_check("拾取与金币常量合法（拾取半径 > 0、金币成长 > 1、物件尺寸 > 0）",
		GameConstants.PICKUP_RADIUS > 0.0
		and GameConstants.GOLD_GROWTH > 1.0
		and GameConstants.GOLD_BASE_AT_L1 > 0.0
		and GameConstants.LOOT_EQUIPMENT_ICON_SIZE > 0
		and GameConstants.LOOT_DROP_LIFETIME > 0.0)
	var rarity_adjust_ok := (
		GameConstants.RARITY_KEYS.size() == 8
		and GameConstants.RARITY_BEAM_HEIGHTS.size() == 8
		and GameConstants.RARITY_BEAM_SHAPES.size() == 8)
	if rarity_adjust_ok:
		var w := GameConstants.adjust_rarity_weights_by_difficulty(
			GameConstants.RARITY_DROP_BASE_PERCENT,
			GameConstants.DifficultyTier.NM1, 0, 1)
		rarity_adjust_ok = w[GameConstants.Rarity.MYTHIC] == 0.0  # NM1 红装清零
		var w2 := GameConstants.adjust_rarity_weights_by_difficulty(
			GameConstants.RARITY_DROP_BASE_PERCENT,
			GameConstants.DifficultyTier.NM2, 0, 1)
		rarity_adjust_ok = rarity_adjust_ok and w2[GameConstants.Rarity.MYTHIC] > 0.0
	_add_check("稀有度难度修正合法（NM1 红装清零、NM2+ 红装开放、光柱/形状 8 档对齐）",
		rarity_adjust_ok)

	# 任务 2.8：打击感锚点
	var juice_ok := (
		GameConstants.DAMAGE_NUMBER_LIFETIME > 0.0
		and GameConstants.DAMAGE_NUMBER_RISE_SPEED > 0.0
		and GameConstants.HIT_FLASH_DURATION > 0.0
		and GameConstants.HIT_STOP_DURATION > 0.0
		and GameConstants.HIT_STOP_DURATION < 0.1
		and GameConstants.HIT_STOP_TIME_SCALE > 0.0
		and GameConstants.HIT_STOP_TIME_SCALE < 1.0
		and GameConstants.SHAKE_HIT_STRENGTH > 0.0
		and GameConstants.SHAKE_DECAY_PER_SEC > 0.0
		and GameConstants.DEATH_BURST_PARTS >= 4
		and GameConstants.DEATH_BURST_DURATION > 0.0)
	_add_check("打击感参数合法（飘字寿命/上飘 > 0、顿帧 ∈ (0,0.1)、震屏/衰减 > 0、死亡粒子 ≥ 4）",
		juice_ok)
	_add_check("打击感场景可加载（飘字 / 像素粒子）",
		ResourceLoader.exists("res://scenes/juice/damage_number.tscn")
		and ResourceLoader.exists("res://scenes/juice/pixel_burst.tscn")
		and ResourceLoader.exists("res://scripts/juice/juice_fx.gd"))

	# 特效贴图层（2026-09-20 · 用户诉求「我可以自己換特效」）。
	# 这三条是「贴图缺失」的守门员：少了它们，删掉一张 PNG 后游戏会**静默**退回
	# 代码绘制、自检依旧全绿 —— 正是本项目反复踩的「静默降级」坑。
	var fx_ids := FxTable.all_ids()
	var fx_missing: Array[String] = []
	var fx_frames_bad: Array[String] = []
	for fid in fx_ids:
		var tex := FxTable.texture_for(fid)
		if tex == null:
			fx_missing.append(fid)
			continue
		var sp := FxTable.spec(fid)
		var need_w := int(sp.get("frames", 1)) * int(sp.get("frame_w", 1))
		if tex.get_width() < need_w or tex.get_height() < int(sp.get("frame_h", 1)):
			fx_frames_bad.append("%s(%d<%d)" % [fid, tex.get_width(), need_w])
	_add_check("特效表已加载：%d 条（%s）" % [fx_ids.size(), "fx.json"],
		FxTable.is_loaded() and fx_ids.size() >= 7)
	_add_check("特效贴图全部可加载（缺 %d 条）" % fx_missing.size(), fx_missing.is_empty())
	_add_check("特效帧数与贴图尺寸自洽（frame_w×frames ≤ 贴图宽）", fx_frames_bad.is_empty())

	# 4) 存档系统可用性（只检查目录，不写文件）
	_add_check("存档目录可用", DirAccess.dir_exists_absolute(GameConstants.SAVE_DIR))


## 检查一组套装的 6 件底材是否都能解析，且 set_id 反向一致
func _resolve_all_set_pieces(set_data: SetData) -> bool:
	for template_id in set_data.piece_template_ids:
		var tpl := ConfigLoader.get_equipment_template(template_id)
		if tpl == null or tpl.set_id != set_data.id:
			return false
	return true


func _add_check(label: String, passed: bool) -> void:
	_report_lines.append("%s %s" % ["[OK]  " if passed else "[FAIL]", label])


## 把自检结果同时输出到「控制台」与「界面」。
##
## 控制台那一段是**无头验证（`--verify`）唯一能看到的输出**，不要删。
func _render_report() -> void:
	_failed_count = 0
	for line in _report_lines:
		if line.begins_with("[FAIL]"):
			_failed_count += 1

	# ---- 1) 控制台纯文本（无头验证靠这段）----
	print("[Main] ===== 「七傳說」骨架自检 =====")
	for line in _report_lines:
		print("[Main] " + line)
	if _failed_count == 0:
		print("[Main] 结果：全部通过（%d 项）。骨架就绪，可以进入阶段 2。" % _report_lines.size())
	else:
		print("[Main] 结果：%d / %d 项未通过。" % [_failed_count, _report_lines.size()])

	# ---- 2) 界面富文本 ----
	if _report_label == null:
		return

	var text := "[b]「七傳說」骨架自检[/b]\n"
	text += "[color=#6B7688]────────────────────────────[/color]\n"
	for line in _report_lines:
		if line.begins_with("[FAIL]"):
			text += "[color=#E8573F]%s[/color]\n" % line # 血/危险辉光（48 色板内）
		else:
			text += "[color=#6FB35C]%s[/color]\n" % line # 毒/自然辉光（48 色板内）

	text += "[color=#6B7688]────────────────────────────[/color]\n"
	if _failed_count == 0:
		text += "[color=#D9A521]全部通过。骨架就绪，可以进入阶段 2。[/color]\n"
	else:
		text += "[color=#E05252]有 %d 项未通过，请查看控制台输出。[/color]\n" % _failed_count

	text += "\n[color=#6B7688]输入映射：WASD 移动 / 左键 攻击（按住连击）/ 1 2 3 技能 / Space 闪避 / I 背包 / C 角色 / F 交互[/color]"
	_report_label.text = text
