## 技能形态实体实测（第三步 B3-5 · 工单 1-L3 / 1-L4 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_skill_forms.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 定位（与既有脚本的分工，防「自洽式伪校验」，铁律 SF4）：
##   · `verify_skills` 测**技能数据**（36 条 / 形态字段 / DPS 系数区间）与 B0 的
##     **过渡实现**（即时一次性结算）—— 它**不**生成实体。
##   · 本脚本测**真实实体**：`Projectile`（飞行 / 命中 / 穿透 / 分裂 / 连锁）与
##     `GroundArea`（tick 结算 / 落地爆发 / 到期释放），全部走 `SkillController.try_cast`
##     生产路径（真扣费 / 真冷却 / 真符文修饰），断言**真落到靶子上的伤害**。
##
## ⚠️ 伤害断言的可确定性来源（三条，缺一不可）：
##   ① 攻击固定 100（注入 `attack`）；② 技能等级 1（未注入 `skill_level`）；
##   ③ 暴击率注入 −100 ⇒ `5 − 100 < 0` ⇒ **永不暴击**（比固定随机种子更稳：固定种子的
##      「全程不暴击」会随调用序列漂移，本脚本的命中次数远多于 `verify_skills`）。
##
## 覆盖（A~K）：
##   A. 投射物：施放即生成实体 / 飞行若干帧才命中（真弹道）/ 命中后自毁
##   B. 多发射击：`projectile_count` 各自独立结算 ⇒ 全中 = N × multiplier（§5.1）
##   C. 穿透：`rune_pierce` ⇒ 命中不消失，连续命中同一直线上的 2 个目标
##   D. 连锁：`lightning_chain`（chain_count=2 / 无衰减）⇒ 弹射 2 个额外目标
##   E. 连锁衰减：`rune_chain`（chain_decay_pct=25）⇒ 每跳 ×0.75
##   F. 分裂：`rune_split` ⇒ 3 枚子投射物；母弹只结算一次、碎片不回头打同一目标
##   G. 持续区域：tick 总伤害 == `SkillData.total_damage_multiplier()`（§5.1 不变量）
##   H. 落地爆发：`meteor` 的 `impact_multiplier` 先于 tick 结算
##   I. 技能等级系数在投射物上生效（L4 ⇒ ×1.24）
##   J. 符文修饰器承载：`on_hit_split`（嵌套 dict）与 `chain_decay_pct` 不再被丢弃
##   K. 埋点：投射物命中补记进 `CombatMetrics`（deferred），且不被误记为空放
extends Node

## 地面靶子的「停放位」：远离投射物弹道与地面半径，避免误伤
const GROUND_PARK := Vector2(600, 600)

## 默认出战栏（投射物 / 连锁用）。地面用例传自己的栏 —— `try_cast` 只认栏内技能。
const BAR_DEFAULT: Array[String] = ["piercing_shot", "multishot", "lightning_chain"]

var _fail: int = 0
var _player: PlayerController = null
var _skills: SkillController = null
var _d1: DamageDummy = null
var _d2: DamageDummy = null
var _d3: DamageDummy = null
var _dground: DamageDummy = null
## 一次施放期间同时存在的投射物峰值数（分裂用例用）
var _max_projectiles: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 技能形态实体实测（B3-5）=====")
	_setup()
	await _test_projectile_flight()
	await _test_multishot()
	await _test_pierce()
	await _test_chain()
	await _test_chain_decay()
	await _test_split()
	await _test_ground_ticks()
	await _test_ground_impact()
	await _test_skill_level()
	_test_rune_modifiers()
	await _test_metrics_deferred()
	_finish()


func _setup() -> void:
	var root := "/root/VerifySkillForms/"
	_player = get_node_or_null(root + "Player") as PlayerController
	_d1 = get_node_or_null(root + "D1") as DamageDummy
	_d2 = get_node_or_null(root + "D2") as DamageDummy
	_d3 = get_node_or_null(root + "D3") as DamageDummy
	_dground = get_node_or_null(root + "DGround") as DamageDummy
	_ok("场景就绪：玩家 + 4 个靶子", _player != null and _d1 != null and _d2 != null
		and _d3 != null and _dground != null)
	if _player == null:
		return
	_skills = _player.get_skill_controller()
	_ok("技能控制器就绪", _skills != null)
	# 出战栏换成测试用技能（`try_cast` 只认栏内技能）
	var data := SaveData.create_new(0, "archer")
	data.skill_bar = ["piercing_shot", "multishot", "lightning_chain"]
	SaveManager.current_data = data
	_ok("存档栏就绪（穿透箭 / 多重射击 / 闪电链）",
		SaveManager.current_data != null and SaveManager.current_data.skill_bar.size() == 3)


# =============================================================================
# 用例基础设施
# =============================================================================

## 每个用例前复位：清场 + 满血靶子 + 固定属性 + 卸符文 + 重载技能（顺带清冷却）。
## `bar` 为空 ⇒ 用 `BAR_DEFAULT`。
func _reset(bar: Array[String] = []) -> void:
	_clear_entities()
	for d in [_d1, _d2, _d3, _dground]:
		d.reset(1_000_000.0)
	_d1.global_position = Vector2(0, 50)
	_d2.global_position = Vector2(0, 120)
	_d3.global_position = Vector2(0, 180)
	_dground.global_position = GROUND_PARK
	_player.global_position = Vector2.ZERO
	# 攻击 100 / 永不暴击（5 − 100 < 0）/ 技能等级 1
	_player.apply_combat_stats({"attack": 100.0, "crit_chance": -100.0}, 1)
	_player.get_mana_pool().set_current(1000.0)
	var ids: Array[String] = BAR_DEFAULT if bar.is_empty() else bar
	var data := SaveManager.current_data
	if data != null:
		data.skill_bar = ids.duplicate()
	for sid in ids:
		_skills.set_equipped_runes(sid, [])
	_skills._load_skills()
	_max_projectiles = 0


## 立即清场。⚠️ 用 `free()` 而非 `queue_free()` —— 后者的延迟释放会让下一用例
## 误计上一用例残留的弹体 / 区域（`_projectiles().is_empty()` 会永远为假）。
func _clear_entities() -> void:
	for child in get_children():
		if child is Projectile or child is GroundArea:
			child.free()


func _projectiles() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child in get_children():
		if child is Projectile:
			out.append(child)
	return out


func _ground_areas() -> Array[GroundArea]:
	var out: Array[GroundArea] = []
	for child in get_children():
		if child is GroundArea:
			out.append(child)
	return out


## 施放并等到「场上再没有任何投射物」（弹道飞完 / 命中 / 分裂子弹全部消亡）。
## 返回 false = 施放被拒（冷却 / 蓝不足 / 技能不在栏内）。
func _cast_and_settle(sid: String, max_frames: int = 180) -> bool:
	if not _skills.try_cast(sid):
		return false
	var frames := 0
	while frames < max_frames and not _projectiles().is_empty():
		await get_tree().physics_frame
		_max_projectiles = maxi(_max_projectiles, _projectiles().size())
		frames += 1
	return true


## 施放地面技能并返回生成的 `GroundArea`（未生成返回 null）。
func _cast_ground(sid: String) -> GroundArea:
	if not _skills.try_cast(sid):
		_info("施放被拒：%s（技能数据=%s / 冷却=%.2f / 蓝=%.1f）"
			% [sid, "有" if _skills.get_skill_data(sid) != null else "无",
				_skills.get_cooldown_remaining(sid), _player.get_mana_pool().current])
		return null
	var areas := _ground_areas()
	return areas[0] if not areas.is_empty() else null


## 驱动一个 `GroundArea` 走完一生（确定性：关掉自动物理帧，手动喂固定 delta）。
##
## 为什么不靠真实帧：区域存活 2–4 秒 = 120–240 个物理帧，既慢、tick 次数又会在
## 浮点边界上随帧率抖动。手动喂 `tick_interval` 让「总 tick 次数」精确等于
## `round(duration / tick_interval)`，断言才写得死。
func _drive_ground(area: GroundArea, interval: float, ticks: int) -> void:
	area.set_physics_process(false)
	for _i in range(ticks):
		area._physics_process(interval)


# =============================================================================
# A. 投射物：生成 / 飞行 / 命中 / 自毁
# =============================================================================

func _test_projectile_flight() -> void:
	print("--- A. 投射物：生成 / 飞行 / 命中 / 自毁 ---")
	_reset()
	_ok("施放穿透箭成功（扣费 + 进冷却）", _skills.try_cast("piercing_shot"))
	_ok("施放即生成 1 枚 Projectile 实体", _projectiles().size() == 1)
	var frames := 0
	while frames < 180 and _d1.total_damage_taken <= 0.0:
		await get_tree().physics_frame
		frames += 1
	_ok("飞行 %d 帧后才命中（真弹道，非即时结算）" % frames,
		frames > 1 and frames < 60)
	_ok("D1 伤害 = 攻击 100 × 倍率 2.2 = 220",
		is_equal_approx(_d1.total_damage_taken, 220.0))
	for _i in range(5):
		await get_tree().physics_frame
	_ok("命中后自毁（pierce_count=0 ⇒ 场上 0 枚）", _projectiles().is_empty())


# =============================================================================
# B. 多发射击
# =============================================================================

func _test_multishot() -> void:
	print("--- B. 多发射击：全中 = N × multiplier（§5.1）---")
	_reset()
	await _cast_and_settle("multishot")
	_ok("多重射击 3 枚全中 ⇒ D1 伤害 300（= 3 × 100 × 1.0）",
		is_equal_approx(_d1.total_damage_taken, 300.0))


# =============================================================================
# C. 穿透
# =============================================================================

func _test_pierce() -> void:
	print("--- C. 穿透：rune_pierce ⇒ 命中不消失 ---")
	_reset()
	_skills.set_equipped_runes("piercing_shot", ["rune_pierce"])
	await _cast_and_settle("piercing_shot")
	_ok("命中 D1（220）", is_equal_approx(_d1.total_damage_taken, 220.0))
	_ok("穿透后继续命中 D2（220）", is_equal_approx(_d2.total_damage_taken, 220.0))
	_ok("D3 超出射程 150 ⇒ 未被命中", is_zero_approx(_d3.total_damage_taken))


# =============================================================================
# D / E. 连锁
# =============================================================================

func _test_chain() -> void:
	print("--- D. 连锁：lightning_chain 弹射 2 个额外目标（无衰减）---")
	_reset()
	await _cast_and_settle("lightning_chain")
	_ok("命中 D1（220）", is_equal_approx(_d1.total_damage_taken, 220.0))
	_ok("弹射至 D2（220；chain_decay_pct=0 ⇒ 不衰减）",
		is_equal_approx(_d2.total_damage_taken, 220.0))
	_ok("弹射至 D3（220）", is_equal_approx(_d3.total_damage_taken, 220.0))


func _test_chain_decay() -> void:
	print("--- E. 连锁衰减：rune_chain（25% / 跳）---")
	_reset()
	_skills.set_equipped_runes("lightning_chain", ["rune_chain"])
	await _cast_and_settle("lightning_chain")
	_ok("第 1 跳 D1 = 220", is_equal_approx(_d1.total_damage_taken, 220.0))
	_ok("第 2 跳 D2 = 220 × 0.75 = 165", is_equal_approx(_d2.total_damage_taken, 165.0))
	_ok("第 3 跳 D3 = 220 × 0.75² = 123.75", is_equal_approx(_d3.total_damage_taken, 123.75))


# =============================================================================
# F. 分裂
# =============================================================================

func _test_split() -> void:
	print("--- F. 分裂：rune_split ⇒ 3 枚子投射物（每枚 50%）---")
	_reset()
	_skills.set_equipped_runes("piercing_shot", ["rune_split"])
	await _cast_and_settle("piercing_shot")
	_ok("母弹命中 D1 只结算一次（220；碎片继承命中记录，不回头打 D1）",
		is_equal_approx(_d1.total_damage_taken, 220.0))
	_ok("分裂出 3 枚子投射物（峰值同屏 3）", _max_projectiles == 3)
	_ok("1 枚碎片命中 D2（220 × 50% = 110）",
		is_equal_approx(_d2.total_damage_taken, 110.0))


# =============================================================================
# G / H. 持续区域
# =============================================================================

func _test_ground_ticks() -> void:
	print("--- G. 持续区域：tick 总伤害 == total_damage_multiplier() ---")
	_reset(["trap_spike"])
	_dground.global_position = Vector2(0, 40) ## 进入半径（48 + 靶半径 12 = 60）
	var data := ConfigLoader.get_skill("trap_spike")
	var area := _cast_ground("trap_spike")
	_ok("施放尖刺陷阱生成 GroundArea 实体", area != null)
	if area == null:
		return
	var ticks := int(round(data.duration / data.tick_interval))
	_drive_ground(area, data.tick_interval, ticks)
	_ok("%d 次 tick ⇒ 总伤害 %.0f == 100 × total_damage_multiplier(%.2f)"
		% [ticks, _dground.total_damage_taken, data.total_damage_multiplier()],
		is_equal_approx(_dground.total_damage_taken, 100.0 * data.total_damage_multiplier()))
	_ok("tick 不推人（持续区域无击退）", is_zero_approx(_dground.total_knockback))
	_ok("duration 到期自动释放", area.is_queued_for_deletion())


func _test_ground_impact() -> void:
	print("--- H. 落地爆发：meteor 的 impact_multiplier 先于 tick ---")
	_reset(["meteor"])
	_dground.global_position = Vector2(0, 40)
	var data := ConfigLoader.get_skill("meteor")
	var area := _cast_ground("meteor")
	_ok("施放陨石术生成 GroundArea 实体", area != null)
	if area == null:
		return
	_ok("落地爆发先结算：Dground = 300（= 100 × impact 3.0）",
		is_equal_approx(_dground.total_damage_taken, 300.0))
	var ticks := int(round(data.duration / data.tick_interval))
	_drive_ground(area, data.tick_interval, ticks)
	_ok("tick 叠加后总量 = 100 × total_damage_multiplier(%.2f) = %.0f"
		% [data.total_damage_multiplier(), 100.0 * data.total_damage_multiplier()],
		is_equal_approx(_dground.total_damage_taken, 100.0 * data.total_damage_multiplier()))


# =============================================================================
# I. 技能等级系数
# =============================================================================

func _test_skill_level() -> void:
	print("--- I. 技能等级系数在投射物上生效（L4 ⇒ ×1.24）---")
	_reset()
	# 注入 skill_level 3 ⇒ 等级 4 ⇒ 系数 1 + 0.08 × 3 = 1.24
	_player.apply_combat_stats(
		{"attack": 100.0, "crit_chance": -100.0, "skill_level": 3.0}, 1)
	_ok("技能等级 = 4（注入 3 + 基准 1）", _player.get_skill_level() == 4)
	await _cast_and_settle("piercing_shot")
	_ok("穿透箭伤害 = 100 × 2.2 × 1.24 = 272.8",
		is_equal_approx(_d1.total_damage_taken, 272.8))


# =============================================================================
# J. 符文修饰器承载
# =============================================================================

func _test_rune_modifiers() -> void:
	print("--- J. 符文修饰器：on_hit_split（嵌套 dict）/ chain_decay_pct ---")
	var base := ConfigLoader.get_skill("piercing_shot")
	var split := _skills._apply_rune_modifiers(base, ["rune_split"])
	_ok("rune_split ⇒ split_count=3 / split_damage_pct=50（嵌套 dict 已被解析）",
		split.split_count == 3 and is_equal_approx(split.split_damage_pct, 50.0))
	_ok("返回副本，不改注册表模板",
		base.split_count == 0 and is_zero_approx(base.split_damage_pct))
	var chain := _skills._apply_rune_modifiers(
		ConfigLoader.get_skill("lightning_chain"), ["rune_chain"])
	_ok("rune_chain ⇒ chain_count=2 / chain_decay_pct=25",
		chain.chain_count == 2 and is_equal_approx(chain.chain_decay_pct, 25.0))


# =============================================================================
# K. 埋点（deferred hits）
# =============================================================================

func _test_metrics_deferred() -> void:
	print("--- K. 埋点：投射物命中补记（deferred，不计 whiff）---")
	_reset()
	CombatMetrics.reset()
	CombatMetrics.begin_run("verify_skill_forms", 0, 0, 0)
	await _cast_and_settle("piercing_shot")
	var rec := CombatMetrics.end_run(false, false)
	var s: Dictionary = rec.get("skills", {}).get("piercing_shot", {})
	_ok("投射物施放被记录（casts = 1）", int(s.get("casts", 0)) == 1)
	_ok("延迟命中被补记（hits >= 1）", int(s.get("hits", 0)) >= 1)
	_ok("投射物不被误记为空放（whiffs = 0）", int(s.get("whiffs", 0)) == 0)
	CombatMetrics.reset()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
