## 攻击与技能系统实测（任务 2.2 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_skills.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围：
##   A. 技能表：skills.json 36 条 / 7 形态 / 三职业池 / DPS 系数区间
##      （设计意图见 deliverables/gstack/策划案/01-技能体系.md §4–§5）
##   B. 法力池：初始满 / 消耗 / 不足失败 / 自然回复 / 封顶 / 减耗折扣 / 信号
##   C. 冷却：施放后进入冷却 / 冷却中拒绝 / 计时递减 / 到期可再施放
##   D. 普攻假连段：按住连续挥击（间隔 = 1/攻速）/ 松开停止 / 攻击不打断移动 /
##      闪避打断 / 命中回蓝 / 朝向扇区判定
##   E. 技能效果：裂斩单体 / 旋刃范围+击退 / 突进位移+撞击 / 法力与冷却联动
##   F. 回归：移动 / 朝向 / 闪避不受攻击技能影响
extends Node

const DURATION_FAST := 0.05

# =============================================================================
# 设计意图锚点（01-技能体系.md §4「技能清單（36 個）」/ §5.1「統一標尺」）
# -----------------------------------------------------------------------------
# 鐵律：斷言寫「設計意圖」，不寫「當前快照」。
#   · 技能表擴充時**只維護 `DESIGN_SKILL_IDS` 清單**，不動斷言結構（1-V2）
#   · 具體數值一律改為**區間斷言**（1-V3）——單點快照改一次數值就紅，區間才是設計
# =============================================================================

## 設計清單：三職業各 12（§4.1 / §4.2 / §4.3）
const DESIGN_SKILL_IDS: Array[String] = [
	# 戰士（warrior）
	"cleave", "spin_slash", "dash_strike", "power_strike", "shadow_blink", "whirlwind",
	"shield_bash", "warcry", "ground_slam", "blade_toss", "blood_rage", "iron_bulwark",
	# 弓箭手（archer）
	"piercing_shot", "arrow_rain", "venom_shot", "multishot", "explosive_arrow", "trap_spike",
	"hawk_eye", "wind_walk", "poison_field", "spirit_wolf", "shadow_volley", "hunters_mark",
	# 法師（mage）
	"fireball", "frost_nova", "lightning_chain", "poison_cloud", "frost_bolt", "meteor",
	"arcane_shield", "blink", "summon_elemental", "thunder_storm", "mana_surge", "void_rift",
]

const CLASS_IDS: Array[String] = ["warrior", "archer", "mage"]
const CLASS_SKILL_COUNT := 12

## §5.1 設計區間（硬約束）：DPS 係數 = 總傷害 ÷ 冷卻
## ⚠️ 用 `Array`（64-bit double）而非 `Vector2`——Vector2 的分量是 **32-bit float**，
##    會把下界 0.40 存成 0.40000000596，導致 `1.8/4.5 = 0.400` 這類合法值被誤判失敗。
const DPS_RANGE_DAMAGE := [0.40, 0.70] ## 單體 / 範圍 / 投射物
const DPS_RANGE_GROUND := [0.45, 0.75] ## 持續區域（含全部 tick）
const DPS_RANGE_DASH := [0.10, 0.20]   ## 位移（價值在位移，傷害為輔）

var _fail: int = 0
var _player: PlayerController = null
var _mana: ManaPool = null
var _skills: SkillController = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


## 断言技能 DPS 系数落在 §5.1 设计区间内（统一标尺：总伤害 ÷ 冷却）
## 口径由 `SkillData.dps_coefficient()` 承担（GROUND 含全部 tick / PROJECTILE 按全中计）
## `rng` = `[下界, 上界]`（Array 存 64-bit double，见上方 Vector2 精度说明）
func _ok_dps(label: String, data: SkillData, rng: Array) -> void:
	if data == null:
		_ok("%s（数据缺失）" % label, false)
		return
	var lo: float = rng[0]
	var hi: float = rng[1]
	var dps := data.dps_coefficient()
	_ok("%s = %.3f ∈ %.2f–%.2f" % [label, dps, lo, hi], dps >= lo and dps <= hi)


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 攻击与技能系统实测 =====")
	# 伤害断言（42 / 16.8 / 12）假设不暴击；固定随机种子使暴击 roll 确定（5% 基线，
	# 该种子下全程不暴击），避免偶发 1.5× 暴击导致断言抖动
	seed(20260916)
	_setup_scene()
	await _test_skill_table()
	await _test_mana_pool()
	await _test_cooldowns()
	await _test_attack_combo()
	await _test_skill_effects()
	await _test_regression()
	_finish()


func _setup_scene() -> void:
	_player = get_node_or_null("/root/VerifySkills/Player") as PlayerController
	_mana = _player.get_mana_pool()
	_skills = _player.get_skill_controller()
	_ok("场景就绪：玩家 + 法力池 + 技能控制器", _player != null and _mana != null and _skills != null)


# =============================================================================
# A. 技能表
# =============================================================================

func _test_skill_table() -> void:
	print("--- A. 技能表 ---")
	var ids := ConfigLoader.get_all_skill_ids()
	_ok("技能表 = 36 条（三职业各 12；01-技能体系.md §4）",
		ids.size() == DESIGN_SKILL_IDS.size())

	# 1-V2：逐字 id 列表 → 集合包含断言（扩容只改 DESIGN_SKILL_IDS，不动断言）
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	_ok("技能 ID 稳定排序（字母序）", ids == sorted_ids)
	var missing: Array[String] = []
	for sid in DESIGN_SKILL_IDS:
		if not ids.has(sid):
			missing.append(sid)
	_ok("技能表 ⊇ 设计清单（%d 个 id 全覆盖）" % DESIGN_SKILL_IDS.size(), missing.is_empty())
	if not missing.is_empty():
		_info("缺失 id：%s" % str(missing))

	# 三职业池：各 12 且并集 == 全表（无孤儿技能 / 无未分配技能）
	var pools_ok := true
	var pool_union: Dictionary = {}
	var pool_desc := ""
	for cid in CLASS_IDS:
		var pool := ConfigLoader.class_skill_ids(cid)
		pool_desc += ("%s%s=%d" % [" " if pool_desc != "" else "", cid, pool.size()])
		if pool.size() != CLASS_SKILL_COUNT:
			pools_ok = false
		for sid in pool:
			pool_union[sid] = true
	_ok("三职业技能池各 %d 个（%s）" % [CLASS_SKILL_COUNT, pool_desc], pools_ok)
	_ok("三职业池并集 == 全表 %d（无孤儿技能）" % DESIGN_SKILL_IDS.size(),
		pool_union.size() == ids.size() and pool_union.size() == DESIGN_SKILL_IDS.size())

	# 出战栏 9 格（三职业各 3），其余为备选（slot 0）
	var slot_counts := {0: 0, 1: 0, 2: 0, 3: 0}
	for sid in ids:
		var sd0 := ConfigLoader.get_skill(sid)
		if sd0 != null and slot_counts.has(sd0.slot):
			slot_counts[sd0.slot] += 1
	_ok("出战栏共 9 格（slot 1/2/3 各 3），其余 %d 个为备选（slot 0）"
		% (ids.size() - 9),
		slot_counts[1] == 3 and slot_counts[2] == 3 and slot_counts[3] == 3
		and slot_counts[0] == ids.size() - 9)

	var all_valid := true
	for sid in ids:
		var sd := ConfigLoader.get_skill(sid)
		if sd == null or not sd.validate().is_empty():
			all_valid = false
			if sd != null:
				_info("%s 校验失败：%s" % [sid, str(sd.validate())])
	_ok("全部技能数据合法（validate 空）", all_valid)

	_ok("出战栏 1/2/3 = 裂斩/旋刃/突进（无存档回退战士默认栏）",
		_skills.get_skill_id_at(0) == "cleave"
		and _skills.get_skill_id_at(1) == "spin_slash"
		and _skills.get_skill_id_at(2) == "dash_strike")

	# 1-V3：老出战三技 —— 形态/槽位（设计意图）+ DPS 系数区间（§5.1）
	var cleave := ConfigLoader.get_skill("cleave")
	var spin := ConfigLoader.get_skill("spin_slash")
	var dash := ConfigLoader.get_skill("dash_strike")
	_ok("裂斩：单体 / slot 1",
		cleave != null and cleave.type == SkillData.SkillType.SINGLE and cleave.slot == 1)
	_ok_dps("裂斩 DPS 系数", cleave, DPS_RANGE_DAMAGE)
	_ok("旋刃：范围 / slot 2 / 半径 > 0",
		spin != null and spin.type == SkillData.SkillType.AOE and spin.slot == 2 and spin.radius > 0.0)
	_ok_dps("旋刃 DPS 系数", spin, DPS_RANGE_DAMAGE)
	_ok("突进：位移 / slot 3 / 冲刺距离 > 0",
		dash != null and dash.type == SkillData.SkillType.DASH and dash.slot == 3
		and dash.dash_distance > 0.0)
	_ok_dps("突进 DPS 系数", dash, DPS_RANGE_DASH)
	_ok("技能栏 1/2/3 对应裂斩/旋刃/突进",
		_skills.get_skill_id_at(0) == "cleave"
		and _skills.get_skill_id_at(1) == "spin_slash"
		and _skills.get_skill_id_at(2) == "dash_strike")

	# ---- 1-V4 + 1-V3：§4 被改造的 7 个技能（形态 / 数值均变，断言写新设计意图）----
	var fireball := ConfigLoader.get_skill("fireball")
	var frost := ConfigLoader.get_skill("frost_nova")
	var chain := ConfigLoader.get_skill("lightning_chain")
	var cloud := ConfigLoader.get_skill("poison_cloud")
	var pierce := ConfigLoader.get_skill("piercing_shot")
	var rain := ConfigLoader.get_skill("arrow_rain")
	var venom := ConfigLoader.get_skill("venom_shot")
	var strike := ConfigLoader.get_skill("power_strike")

	_ok("火球术：SINGLE → PROJECTILE（真弹道）/ slot 1 / 火",
		fireball != null and fireball.type == SkillData.SkillType.PROJECTILE
		and fireball.element == "fire" and fireball.slot == 1
		and fireball.projectile_speed > 0.0 and fireball.projectile_count >= 1)
	_ok_dps("火球术 DPS 系数", fireball, DPS_RANGE_DAMAGE)

	_ok("冰霜新星：AOE / slot 2 / 冰 / 半径 > 0",
		frost != null and frost.type == SkillData.SkillType.AOE
		and frost.element == "cold" and frost.slot == 2 and frost.radius > 0.0)
	_ok_dps("冰霜新星 DPS 系数", frost, DPS_RANGE_DAMAGE)

	_ok("闪电链：SINGLE → PROJECTILE + 连锁 2 目标 / slot 3 / 雷",
		chain != null and chain.type == SkillData.SkillType.PROJECTILE
		and chain.element == "lightning" and chain.slot == 3
		and chain.chain_count == 2 and chain.projectile_speed > 0.0)
	_ok_dps("闪电链 DPS 系数", chain, DPS_RANGE_DAMAGE)

	_ok("毒云：SINGLE → GROUND / 毒 / 半径与结算参数齐备",
		cloud != null and cloud.type == SkillData.SkillType.GROUND
		and cloud.element == "poison"
		and cloud.radius > 0.0 and cloud.duration > 0.0 and cloud.tick_interval > 0.0)
	_ok_dps("毒云 DPS 系数", cloud, DPS_RANGE_GROUND)

	_ok("穿透箭：SINGLE → PROJECTILE / slot 1 / 射程 > 0",
		pierce != null and pierce.type == SkillData.SkillType.PROJECTILE and pierce.slot == 1
		and pierce.range > 0.0 and pierce.projectile_speed > 0.0)
	_ok_dps("穿透箭 DPS 系数", pierce, DPS_RANGE_DAMAGE)

	_ok("箭雨：AOE / slot 2 / 半径 > 0",
		rain != null and rain.type == SkillData.SkillType.AOE
		and rain.slot == 2 and rain.radius > 0.0)
	_ok_dps("箭雨 DPS 系数", rain, DPS_RANGE_DAMAGE)

	_ok("淬毒箭：SINGLE → PROJECTILE / slot 3 / 毒",
		venom != null and venom.type == SkillData.SkillType.PROJECTILE
		and venom.element == "poison" and venom.slot == 3 and venom.projectile_speed > 0.0)
	_ok_dps("淬毒箭 DPS 系数", venom, DPS_RANGE_DAMAGE)

	_ok("蓄力斩：单体 / slot 0（战士备选）",
		strike != null and strike.type == SkillData.SkillType.SINGLE and strike.slot == 0)
	_ok_dps("蓄力斩 DPS 系数", strike, DPS_RANGE_DAMAGE)

	# ---- 7 种形态全覆盖（§3 新增 4 种：投射物 / 持续区域 / 召唤 / 增益）----
	var form_hits: Dictionary = {}
	var elems: Dictionary = {}
	for sid in ids:
		var sd := ConfigLoader.get_skill(sid)
		if sd != null:
			form_hits[sd.type] = int(form_hits.get(sd.type, 0)) + 1
			elems[sd.element] = true
	var forms_ok := true
	for t in range(SkillData.SkillType.SINGLE, SkillData.SkillType.BUFF + 1):
		if int(form_hits.get(t, 0)) <= 0:
			forms_ok = false
			_info("形态「%s」无任何技能" % SkillData.TYPE_NAMES[t])
	_ok("7 种形态全覆盖（单体/范围/位移/投射物/持续区域/召唤/增益）", forms_ok)
	_ok("元素覆盖 物理/火/冰/雷/毒/暗影（6 种）",
		elems.has("physical") and elems.has("fire") and elems.has("cold")
		and elems.has("lightning") and elems.has("poison") and elems.has("shadow"))

	# ---- §12 召唤（技能 id ≠ 召唤物 id，见 1-D1 的 summon_id 字段）----
	var wolf := ConfigLoader.get_skill("spirit_wolf")
	var elem := ConfigLoader.get_skill("summon_elemental")
	_ok("灵狼：召唤形态 / slot 0 / 召唤物 summon_spirit_wolf / 有时长（弓手）",
		wolf != null and wolf.type == SkillData.SkillType.SUMMON and wolf.slot == 0
		and wolf.summon_id == "summon_spirit_wolf" and wolf.duration > 0.0)
	_ok("元素仆从：召唤形态 / slot 0 / 召唤物 summon_elemental / 有时长（法师）",
		elem != null and elem.type == SkillData.SkillType.SUMMON and elem.slot == 0
		and elem.summon_id == "summon_elemental" and elem.duration > 0.0)
	_ok("召唤物 id 已在 Summon.DEFS 注册（素材目录 / spawn / 图标映射同一字符串）",
		Summon.DEFS.has("summon_spirit_wolf") and Summon.DEFS.has("summon_elemental")
		and Summon.DEFS.has(wolf.summon_id) and Summon.DEFS.has(elem.summon_id))


# =============================================================================
# B. 法力池
# =============================================================================

func _test_mana_pool() -> void:
	print("--- B. 法力池 ---")
	_mana.set_current(100.0)
	_ok("初始法力 = 100 / 100", is_equal_approx(_mana.current, 100.0) and is_equal_approx(_mana.maximum, 100.0))
	_ok("消耗 30 成功 → 70", _mana.try_spend(30.0) and is_equal_approx(_mana.current, 70.0))
	_ok("消耗 80 失败（不足）且法力不变",
		not _mana.try_spend(80.0) and is_equal_approx(_mana.current, 70.0))
	_mana.set_current(50.0)
	_mana.tick_regen(2.5)
	_ok("自然回复 4/s × 2.5s = +10 → 60", is_equal_approx(_mana.current, 60.0))
	_mana.set_current(99.0)
	_mana.restore(20.0)
	_ok("restore 封顶到 max（100）", is_equal_approx(_mana.current, 100.0))
	_mana.apply_stats(0.0, 0.0, 0.5)
	_mana.set_current(100.0)
	_ok("减耗 50%：消耗 30 只扣 15", _mana.try_spend(30.0) and is_equal_approx(_mana.current, 85.0))
	_mana.apply_stats(0.0, 0.0, 0.0) # 复位
	_mana.set_current(100.0)


# =============================================================================
# C. 冷却
# =============================================================================

func _test_cooldowns() -> void:
	print("--- C. 冷却 ---")
	# 用旋刃（3s / 15 蓝）做冷却测试，法力充足
	_mana.set_current(100.0)
	_ok("施放旋刃成功", _skills.try_cast("spin_slash"))
	_ok("旋刃冷却 = 3.0", is_equal_approx(_skills.get_cooldown_remaining("spin_slash"), 3.0))
	_ok("冷却中拒绝再次施放（法力足够）",
		not _skills.try_cast("spin_slash") and is_equal_approx(_mana.current, 85.0))
	_skills.tick_cooldowns(1.5)
	_ok("冷却计时递减 → 1.5", is_equal_approx(_skills.get_cooldown_remaining("spin_slash"), 1.5))
	_skills.tick_cooldowns(1.5)
	_ok("冷却到期 = 0", is_equal_approx(_skills.get_cooldown_remaining("spin_slash"), 0.0))
	_ok("到期后可再次施放", _skills.try_cast("spin_slash"))
	_skills.tick_cooldowns(5.0) # 清冷却，避免影响后续
	_mana.set_current(100.0)


# =============================================================================
# D. 普攻假连段
# =============================================================================

func _test_attack_combo() -> void:
	print("--- D. 普攻假连段 ---")
	var dummy := get_node_or_null("/root/VerifySkills/DummyFront") as DamageDummy
	dummy.reset()
	dummy.global_position = Vector2(0, 40) # 复位（C 段旋刃击退过它）
	# 2.5 半径扩展后 C 段两次旋刃会把 DummyBehind 击退到 (0,-12)，与玩家 (0,0) 重叠，
	# 首个物理帧会被物理引擎分离推开（Node 与物理体不同步）——先移远排除干扰
	var dummy_behind := get_node_or_null("/root/VerifySkills/DummyBehind") as DamageDummy
	dummy_behind.global_position = Vector2(0, -200)
	# 把玩家放到原点朝下（DummyFront 在正下方 40px）
	_player.global_position = Vector2(0, 0)
	_player.velocity = Vector2.ZERO
	_player.set_facing(PlayerController.Facing8.DOWN)
	_player._attack_timer = 0.0 # 清计时（测试脚本直接读内部字段）

	_ok("按住攻击 → 立即挥出第一击（伤害 = 12 × 1.0）",
		_player.try_attack() and is_equal_approx(dummy.total_damage_taken, 12.0))
	_ok("攻击后间隔内 try_attack 被拒（攻速 1.0/s）", not _player.try_attack())
	# 模拟按住 2.2s：0s / 1.0s / 2.0s 三击
	var hit_count := 1
	var elapsed := 0.0
	Input.action_press(GameConstants.ACTION_ATTACK)
	while elapsed < 2.2:
		_player._tick_attack(DURATION_FAST)
		elapsed += DURATION_FAST
	Input.action_release(GameConstants.ACTION_ATTACK)
	_ok("按住 2.2s → 共挥击 3 次（0s / 1.0s / 2.0s）", dummy.damage_log.size() >= 3)
	hit_count = dummy.damage_log.size()
	# 松开后 1.5s 不再挥击
	elapsed = 0.0
	while elapsed < 1.5:
		_player._tick_attack(DURATION_FAST)
		elapsed += DURATION_FAST
	_ok("松开后不再挥击", dummy.damage_log.size() == hit_count)

	# 攻击中可移动：按住攻击 + 移动键 → 水平速度 > 0
	Input.action_press(GameConstants.ACTION_ATTACK)
	Input.action_press(&"move_right")
	await _step_physics(0.3)
	_ok("攻击中可移动（按住攻击 + 右移 → vx > 0）", _player.velocity.x > 0.0)
	Input.action_release(&"move_right")
	Input.action_release(GameConstants.ACTION_ATTACK)
	await _step_physics(0.5)
	_player.velocity = Vector2.ZERO
	_player.global_position = Vector2(0, 0) # 复位（移动测试改变了位置）

	# 闪避打断：攻击后立刻闪避，攻击计时清零且闪避中不挥击
	_player._attack_timer = 0.6
	_ok("闪避打断攻击计时（timer 清零）", _player.try_dodge() and _player._attack_timer == 0.0)
	_player._tick_attack(0.1)
	_ok("闪避中不挥击", _player._attack_timer == 0.0)
	await _step_physics(1.2) # 等闪避结束

	# 普攻命中回蓝（先复位玩家位置——闪避测试把玩家冲到了 (0,88)）
	_player.global_position = Vector2(0, 0)
	_player.velocity = Vector2.ZERO
	_player.set_facing(PlayerController.Facing8.DOWN)
	_mana.set_current(50.0)
	_player.try_attack()
	_ok("普攻命中回蓝 +2（50 → 52）", is_equal_approx(_mana.current, 52.0))
	_mana.set_current(100.0)

	# 朝向扇区：背对目标不命中
	dummy.reset()
	_player.set_facing(PlayerController.Facing8.UP) # 朝上，dummy 在下方
	_player.try_attack()
	_ok("背对目标不命中（60° 扇区判定）", dummy.total_damage_taken == 0.0)
	_player.set_facing(PlayerController.Facing8.DOWN)


# =============================================================================
# E. 技能效果
# =============================================================================

func _test_skill_effects() -> void:
	print("--- E. 技能效果 ---")
	var dummy_front := get_node_or_null("/root/VerifySkills/DummyFront") as DamageDummy
	var dummy_far := get_node_or_null("/root/VerifySkills/DummyFar") as DamageDummy
	var dummy_behind := get_node_or_null("/root/VerifySkills/DummyBehind") as DamageDummy
	# 复位全部位置与状态（D 段的移动 / 击退改动了它们）
	_player.global_position = Vector2(0, 0)
	_player.velocity = Vector2.ZERO
	dummy_front.global_position = Vector2(0, 40)
	dummy_far.global_position = Vector2(0, 100)
	dummy_behind.global_position = Vector2(0, -60)

	# 裂斩：单体命中前方 96px 内最近目标（3.5 × 12 = 42）
	dummy_front.reset()
	dummy_behind.reset()
	_mana.set_current(100.0)
	_player.set_facing(PlayerController.Facing8.DOWN)
	_ok("裂斩施放成功且扣蓝 30", _skills.try_cast("cleave") and is_equal_approx(_mana.current, 70.0))
	_ok("裂斩命中前方目标：伤害 42", is_equal_approx(dummy_front.total_damage_taken, 42.0))
	_ok("裂斩未命中背后目标", dummy_behind.total_damage_taken == 0.0)
	_skills.tick_cooldowns(7.0)
	_mana.set_current(100.0)

	# 裂斩背对目标：施放成功（扣蓝进冷却）但无伤害
	dummy_front.reset()
	_player.set_facing(PlayerController.Facing8.UP)
	_ok("背对时裂斩仍施放（扣蓝）", _skills.try_cast("cleave") and is_equal_approx(_mana.current, 70.0))
	_ok("背对时裂斩无命中", dummy_front.total_damage_taken == 0.0)
	_skills.tick_cooldowns(7.0)
	_mana.set_current(100.0)

	# 旋刃：半径 48 内全体命中（1.4 × 12 = 16.8），远处不中，附带击退 24
	dummy_front.reset()
	dummy_far.reset()
	_player.set_facing(PlayerController.Facing8.DOWN)
	var front_before := dummy_front.global_position
	_ok("旋刃施放成功", _skills.try_cast("spin_slash"))
	_ok("旋刃命中半径内目标：伤害 16.8", is_equal_approx(dummy_front.total_damage_taken, 16.8))
	_ok("旋刃未命中半径外目标", dummy_far.total_damage_taken == 0.0)
	_ok("旋刃击退目标 24px", dummy_front.global_position.distance_to(front_before) >= 20.0)
	_skills.tick_cooldowns(4.0)
	_mana.set_current(100.0)

	# 突进：撞到前方目标 → 伤害 12 + 击退 48；玩家被挡（位移 < 96）
	dummy_front.reset()
	dummy_front.global_position = Vector2(0, 44)
	# 2.5 半径扩展后旋刃会命中并击退 DummyBehind 到 (0,-36)，与玩家碰撞框仅差 2px，
	# 物理引擎会在 dash 启动时把它当重叠体推开（玩家水平滑出）——移远排除干扰
	dummy_behind.global_position = Vector2(0, -120)
	_player.set_facing(PlayerController.Facing8.DOWN)
	# Godot 的 global_position setter 延迟同步物理体到下一次物理步进；前面 D 段物理帧
	# 已把玩家物理体带到远处，同帧 dash（move_and_collide）会从旧物理位置出发——
	# await 一帧让物理体与 Node 对齐（无重叠则玩家不动）
	await get_tree().physics_frame
	var player_before := _player.global_position
	_ok("突进施放成功", _skills.try_cast("dash_strike"))
	_ok("突进命中撞击目标：伤害 12", is_equal_approx(dummy_front.total_damage_taken, 12.0))
	_ok("突进玩家位移 < 96（被目标阻挡）", _player.global_position.distance_to(player_before) < 96.0
		and _player.global_position.distance_to(player_before) > 20.0)
	_skills.tick_cooldowns(9.0)
	_mana.set_current(100.0)

	# 法力与冷却联动
	_mana.set_current(10.0)
	_ok("法力不足（10 < 30）拒绝施放裂斩", not _skills.try_cast("cleave"))
	_mana.set_current(100.0)


# =============================================================================
# F. 回归
# =============================================================================

func _test_regression() -> void:
	print("--- F. 回归 ---")
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	Input.action_press(&"move_down")
	await _step_physics(0.4)
	_ok("移动回归：朝下速度 vy > 0", _player.velocity.y > 0.0)
	Input.action_release(&"move_down")
	await _step_physics(0.5)
	_player.velocity = Vector2.ZERO

	_ok("闪避回归：闪避成功开启无敌帧", _player.try_dodge() and _player.is_invulnerable())
	await _step_physics(1.0)


func _step_physics(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		await get_tree().physics_frame
		remaining -= get_physics_process_delta_time()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
