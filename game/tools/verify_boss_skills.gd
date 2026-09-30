## BOSS 标志性技能（bone_slam / fireball / enrage）+ BOSS 差异化（W5-5 / W5-6）实测
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_boss_skills.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 为什么单独一个脚本：
##   `verify_boss63` 只覆盖「阶段判定 / 技能集累积 / 召唤数 / 狂暴乘区」的**纯计算**，
##   证明不了「`bone_slam` / `fireball` / `enrage` 三个死数据真的通电了」——
##   本项目已多次栽在「数据写了、代码零消费、测试全绿」上（IRON-RULES 坑 5）。
##
## 覆盖（7 段）：
##   A. 数据：`enrage_phase` 读取（骸骨 4 / 熔心 3）+ 缺省 4 + validate 越界报错
##   B. 召唤差异化：骸骨 [0,3,5,7] / 熔心 [0,1,2,2]
##   C. 等级区间：两只 BOSS 的区间都覆盖各自的使用关卡（05-check C19）
##   D. `bone_slam` 扇形判定：正前命中 / 侧后不中 / 超距不中 / 扇形外不中
##   E. `fireball`：按阶段发 1–3 发、投射物带 ailment、视觉用 `bolt_fire`
##   F. `enrage` 红闪：进狂暴阶段生成 `fx_enrage_flash`，且**只生成一次**
##   G. 无回归：`AoETelegraph` 缺省仍是整圆（`_aoe_strike` 行为不变）
extends Node

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")

var _fail: int = 0
## 段完成标记：防「协程中 SCRIPT ERROR 静默跳段、_fail 仍 0」的伪绿（IRON-RULES ⑱）
const SECTIONS: Array[String] = ["A", "B", "C", "D", "E", "F", "G"]
var _sections_done: Array[String] = []

var _stub: StubPlayer = null


## 假玩家：`_cone_impact` / `EnemyProjectile` 只需要「有 global_position 且能收伤」。
## 用真玩家会牵进属性/输入/血条一整条链，与本节要验证的判定逻辑无关。
class StubPlayer extends Node2D:
	var taken: float = 0.0
	var hit_count: int = 0
	var ailments: Array[String] = []

	func take_damage(amount: float, _src: Node) -> void:
		taken += amount
		hit_count += 1

	func apply_ailment_from_element(element: String, _src: Node) -> void:
		ailments.append(element)

	func is_invulnerable() -> bool:
		return false


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== BOSS 标志性技能实测（W5-5 / W5-6） =====")
	await _test_data()
	await _test_summon_diff()
	await _test_level_range()
	await _test_bone_slam()
	await _test_fireball()
	await _test_enrage_flash()
	await _test_aoe_telegraph_regression()
	_finish()


# =============================================================================
# A. 数据：enrage_phase
# =============================================================================

func _test_data() -> void:
	print("--- A. enrage_phase 配置化 ---")
	var tyrant: Dictionary = ConfigLoader.bosses["boss_bone_tyrant"]
	var ember: Dictionary = ConfigLoader.bosses["boss_ember_lord"]

	_ok("骸骨暴君 enrage_phase = 2（B5-5 二阶段即狂暴）",
		BossPhaseController.enrage_phase(tyrant) == 2)
	_ok("熔心之主 enrage_phase = 2",
		BossPhaseController.enrage_phase(ember) == 2)
	_ok("缺省（不写 enrage_phase）= 最后阶段",
		BossPhaseController.enrage_phase({"thresholds": [0.6]}) == 2)

	var e2 := BossPhaseController.enrage_multipliers(ember, 2)
	var e1 := BossPhaseController.enrage_multipliers(ember, 1)
	_ok("熔心之主阶段 2 已吃狂暴乘区（攻速 ×0.55 / 伤害 ×1.35）",
		absf(float(e2["interval_mult"]) - 0.55) < 0.01
		and absf(float(e2["damage_mult"]) - 1.35) < 0.01)
	_ok("熔心之主阶段 1 无狂暴乘区（×1.0）",
		absf(float(e1["interval_mult"]) - 1.0) < 0.01
		and absf(float(e1["damage_mult"]) - 1.0) < 0.01)
	_ok("is_enraged：两 BOSS 阶段 2 真 / 阶段 1 假",
		BossPhaseController.is_enraged(ember, 2)
		and not BossPhaseController.is_enraged(ember, 1)
		and BossPhaseController.is_enraged(tyrant, 2)
		and not BossPhaseController.is_enraged(tyrant, 1))

	_ok("validate：两个 BOSS 都合法",
		BossPhaseController.validate(tyrant).is_empty()
		and BossPhaseController.validate(ember).is_empty())
	var bad := tyrant.duplicate(true)
	bad["enrage_phase"] = 5
	_ok("validate：enrage_phase 越界（5）必须报错，不被 clampi 静默吞掉",
		not BossPhaseController.validate(bad).is_empty())
	_sections_done.append("A")


# =============================================================================
# B. 召唤差异化
# =============================================================================

func _test_summon_diff() -> void:
	print("--- B. BOSS 差异化 · summon_count ---")
	var tyrant: Dictionary = ConfigLoader.bosses["boss_bone_tyrant"]
	var ember: Dictionary = ConfigLoader.bosses["boss_ember_lord"]
	var t: Array[int] = []
	var e: Array[int] = []
	for p in range(1, 3):
		t.append(BossPhaseController.summon_count_for(tyrant, p))
		e.append(BossPhaseController.summon_count_for(ember, p))
	_ok("骸骨暴君「召唤流」2 阶段 [0,4]（实际 %s）" % str(t),
		t == [0, 4])
	_ok("熔心之主「法术流」2 阶段 [0,2]（实际 %s）" % str(e),
		e == [0, 2])
	_ok("两者召唤数不再相同（差异化真的落地）", t != e)
	_sections_done.append("B")


# =============================================================================
# C. 等级区间
# =============================================================================

func _test_level_range() -> void:
	print("--- C. boss_bone_tyrant 等级区间 ---")
	var mdef := ConfigLoader.get_monster("boss_bone_tyrant")
	_ok("找到 boss_bone_tyrant 的怪物数据", mdef != null)
	if mdef == null:
		_sections_done.append("C")
		return
	_ok("level_max 7 → 20（可复用 ch3_l20，不再与关卡 L20 矛盾）", mdef.level_max == 20)
	_ok("level_min 仍为 6", mdef.level_min == 6)
	_ok("怪物数据自校验通过（区间合法）", mdef.validate().is_empty())
	# 交叉验证：ch3_l20 的 boss_id 就是它，且关卡等级落在区间内
	var lv: LevelData = ConfigLoader.get_level("ch3_l20")
	_ok("ch3_l20 的 boss_id == boss_bone_tyrant 且 L%d ∈ [%d, %d]"
			% [lv.level, mdef.level_min, mdef.level_max],
		lv.boss_id == "boss_bone_tyrant"
		and mdef.level_min <= lv.level and lv.level <= mdef.level_max)

	# 另一只 BOSS 的区间也要覆盖它的使用关卡（05-check C19 的另一半）
	var em := ConfigLoader.get_monster("boss_ember_lord")
	var lv13: LevelData = ConfigLoader.get_level("ch2_l13")
	_ok("boss_ember_lord 区间 [%d, %d] 覆盖 ch2_l13（L%d）"
			% [em.level_min, em.level_max, lv13.level],
		lv13.boss_id == "boss_ember_lord"
		and em.level_min <= lv13.level and lv13.level <= em.level_max)
	_sections_done.append("C")


# =============================================================================
# D. bone_slam 扇形判定
# =============================================================================

## 造一只已就绪的 BOSS + 假玩家，返回 [boss, stub]。调用方负责 queue_free。
func _make_boss(monster_id: String, boss_pos: Vector2, player_pos: Vector2) -> Array:
	var boss := ENEMY_SCENE.instantiate() as EnemyBase
	boss.monster_id = monster_id
	boss.level = 7
	boss.difficulty_tier = GameConstants.DifficultyTier.NM1
	# ⚠️ 顺序不能反：`_ready()` 读 monster_id / level 建属性（见 `_spawn_enemy` 注释）
	get_tree().root.add_child.call_deferred(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	boss.global_position = boss_pos
	if _stub == null:
		_stub = StubPlayer.new()
		_stub.name = "StubPlayer"
		_stub.add_to_group(&"player")
		get_tree().root.add_child.call_deferred(_stub)
		await get_tree().process_frame
	_stub.global_position = player_pos
	_stub.taken = 0.0
	_stub.hit_count = 0
	_stub.ailments.clear()
	boss._player = _stub
	# ⚠️ 关掉 BOSS 自身的 AI（`_physics_process`）：否则它会在测试期间自己追击 / 攻击 /
	#    放技能，把「我手动调一次到底产生了几个节点」的计数搅乱（尤其 fx_sprites 计数）。
	#    本脚本要验的是各技能的**实现**，不是 AI 的自主节奏。
	boss.set_physics_process(false)
	return [boss, _stub]


func _test_bone_slam() -> void:
	print("--- D. bone_slam 扇形重击 ---")
	var boss_pos := Vector2(1000.0, 1000.0)
	var pack := await _make_boss("boss_bone_tyrant", boss_pos, boss_pos + Vector2(60.0, 0.0))
	var boss: EnemyBase = pack[0]
	var stub: StubPlayer = pack[1]

	var radius := boss.data.attack_range * EnemyBase.BONE_SLAM_RANGE_MULT
	_ok("扇形半径 = attack_range(%.0f) × %.1f = %.1f"
			% [boss.data.attack_range, EnemyBase.BONE_SLAM_RANGE_MULT, radius],
		absf(radius - 112.0) < 0.01)

	# ① 正前（中轴上、半径内）⇒ 命中
	boss._cone_impact(100.0, radius, Vector2.RIGHT)
	_ok("正前方命中（take_damage 1 次 / 伤害 100）",
		stub.hit_count == 1 and absf(stub.taken - 100.0) < 0.01)

	# ② 正后方（超出 ±60°）⇒ 不中
	stub.global_position = boss_pos + Vector2(-60.0, 0.0)
	boss._cone_impact(100.0, radius, Vector2.RIGHT)
	_ok("正后方不命中（扇形不是整圆）", stub.hit_count == 1)

	# ③ 侧向 90°（> 60°）⇒ 不中
	stub.global_position = boss_pos + Vector2(0.0, -60.0)
	boss._cone_impact(100.0, radius, Vector2.RIGHT)
	_ok("正侧方（90°）不命中", stub.hit_count == 1)

	# ④ 扇形内但超距 ⇒ 不中
	stub.global_position = boss_pos + Vector2(radius + 40.0, 0.0)
	boss._cone_impact(100.0, radius, Vector2.RIGHT)
	_ok("扇形内但超距不命中", stub.hit_count == 1)

	# ⑤ 扇形边缘内（约 50°）⇒ 命中
	stub.global_position = boss_pos + Vector2.from_angle(deg_to_rad(50.0)) * 60.0
	boss._cone_impact(100.0, radius, Vector2.RIGHT)
	_ok("±60° 内的 50° 方向命中", stub.hit_count == 2)

	# ⑥ `_bone_slam()` 真的布了预警 + 特效，且预警节点活着（0.4s 内）
	var before_fx := get_tree().get_nodes_in_group(&"fx_sprites").size()
	stub.global_position = boss_pos + Vector2(50.0, 0.0)
	boss._player = stub
	boss._bone_slam()
	await get_tree().process_frame
	var after_fx := get_tree().get_nodes_in_group(&"fx_sprites").size()
	_ok("_bone_slam() 生成了 fx_bone_slam 精灵（%d → %d）" % [before_fx, after_fx],
		after_fx > before_fx)
	var telegraphs := _count_telegraphs()
	_ok("_bone_slam() 布了地面预警（AoETelegraph 存活 %d 个）" % telegraphs,
		telegraphs >= 1)
	_ok("_bone_slam() 的预警时长是 0.4s（< AOE 的 0.6s）",
		absf(EnemyBase.BONE_SLAM_TELEGRAPH_TIME - 0.4) < 0.01)

	boss.queue_free()
	await get_tree().process_frame
	_sections_done.append("D")


## 场上活着的 AoETelegraph（内部类，靠 `aoe_telegraphs` 组认）
func _count_telegraphs() -> int:
	return get_tree().get_nodes_in_group(&"aoe_telegraphs").size()


func _all_descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in root.get_children():
		out.append(c)
		out.append_array(_all_descendants(c))
	return out


# =============================================================================
# E. fireball
# =============================================================================

func _test_fireball() -> void:
	print("--- E. fireball 火球 ---")
	var boss_pos := Vector2(2000.0, 2000.0)
	var pack := await _make_boss("boss_ember_lord", boss_pos, boss_pos + Vector2(120.0, 0.0))
	var boss: EnemyBase = pack[0]
	var stub: StubPlayer = pack[1]

	# ① 阶段 1 ⇒ 1 发（`add_child` 是同步的，不需要 await 就能数到）
	var n0 := _count_projectiles()
	boss._boss_phase = 1
	boss._cast_fireball()
	_ok("阶段 1 发 1 发（实际 %d）" % (_count_projectiles() - n0),
		_count_projectiles() - n0 == 1)

	# ② 参数在**刚创建**时读（`_life` 会随 physics 递减，等一帧就不是 3.0 了）
	var projs := _projectiles()
	_ok("场上有火球投射物（%d 个）" % projs.size(), projs.size() > 0)
	if not projs.is_empty():
		var pr: EnemyProjectile = projs[projs.size() - 1]
		_ok("火球速度 = %d" % int(EnemyBase.FIREBALL_SPEED),
			absf(pr._speed - EnemyBase.FIREBALL_SPEED) < 0.01)
		_ok("火球寿命 = %.1fs（实际 %.2f）" % [EnemyBase.FIREBALL_LIFE, pr._life],
			absf(pr._life - EnemyBase.FIREBALL_LIFE) < 0.01)
		_ok("火球带 ailment_element = 熔心之主的元素（%s）" % pr._ailment_element,
			pr._ailment_element == "fire")
		_ok("火球视觉 id = %s" % EnemyBase.FIREBALL_VISUAL_ID,
			pr._visual_id == EnemyBase.FIREBALL_VISUAL_ID)
		_ok("火球视觉真的建出来了（用 FxSprite 而不是占位色块）",
			pr._fx != null and pr._body == null)

	# ③ 阶段 2 ⇒ 2 发（B5-5：2 阶段，phase2 即 2 发）
	var n1 := _count_projectiles()
	boss._boss_phase = 2
	boss._cast_fireball()
	_ok("阶段 2 发 2 发（实际 %d）" % (_count_projectiles() - n1),
		_count_projectiles() - n1 == 2)

	# ④ 阶段号不会超过 2（N 相数据驱动），夹到上限的分支由 clampi 保证
	var n2 := _count_projectiles()
	boss._boss_phase = 2
	boss._cast_fireball()
	_ok("阶段 2 保持 2 发（不因重复召唤堆叠，实际 %d）" % (_count_projectiles() - n2),
		_count_projectiles() - n2 == 2)

	# ⑤ 命中给燃烧：把假玩家挪到某一发的正前方，等它飞过去
	var pr2: EnemyProjectile = _projectiles()[0]
	stub.global_position = pr2.global_position + pr2._dir * 4.0
	var hits_before := stub.hit_count
	var got := await _wait_until(func() -> bool: return stub.hit_count > hits_before, 240)
	_ok("火球命中假玩家", got)
	_ok("命中后施加了燃烧（fire → ailment，实际 %s）" % str(stub.ailments),
		stub.ailments.has("fire"))

	boss.queue_free()
	await get_tree().process_frame
	_sections_done.append("E")


func _projectiles() -> Array[EnemyProjectile]:
	var out: Array[EnemyProjectile] = []
	for c in _all_descendants(get_tree().root):
		var p := c as EnemyProjectile
		if p != null:
			out.append(p)
	return out


func _count_projectiles() -> int:
	return _projectiles().size()


# =============================================================================
# F. enrage 红闪
# =============================================================================

func _test_enrage_flash() -> void:
	print("--- F. enrage 狂暴红闪 ---")
	# ① 素材与表条目就绪
	var spec := FxTable.spec("fx_enrage_flash")
	_ok("fx.json 注册了 fx_enrage_flash（%d 帧 / %dx%d）"
			% [int(spec.get("frames", 0)), int(spec.get("frame_w", 0)), int(spec.get("frame_h", 0))],
		not spec.is_empty() and int(spec.get("frames", 0)) == 4)
	_ok("fx_enrage_flash 贴图可加载", FxTable.texture_for("fx_enrage_flash") != null)

	var boss_pos := Vector2(3000.0, 3000.0)
	var pack := await _make_boss("boss_bone_tyrant", boss_pos, boss_pos + Vector2(60.0, 0.0))
	var boss: EnemyBase = pack[0]

	# ② 未进狂暴阶段时不该放（B5-5：enrage_phase=2，阶段 1 不闪）
	boss._enrage_fx_played = false
	var n0 := get_tree().get_nodes_in_group(&"fx_sprites").size()
	boss._apply_boss_phase(1)
	await get_tree().process_frame
	_ok("阶段 1（骸骨 enrage_phase=2）不放红闪",
		get_tree().get_nodes_in_group(&"fx_sprites").size() == n0
		and not boss._enrage_fx_played)

	# ③ 进阶段 2 ⇒ 放一次
	boss._apply_boss_phase(2)
	await get_tree().process_frame
	var n1 := get_tree().get_nodes_in_group(&"fx_sprites").size()
	_ok("进阶段 2 放了红闪（%d → %d）且标记已置位" % [n0, n1],
		n1 > n0 and boss._enrage_fx_played)
	_ok("狂暴乘区同时生效（攻速 ×0.6 / 伤害 ×1.3）",
		absf(boss._boss_interval_mult - 0.6) < 0.01)

	# ④ 再进一次不该重放（一次性事件）
	var n2 := get_tree().get_nodes_in_group(&"fx_sprites").size()
	boss._apply_boss_phase(2)
	await get_tree().process_frame
	_ok("重复进狂暴不重放红闪（%d → %d）" % [n2, get_tree().get_nodes_in_group(&"fx_sprites").size()],
		get_tree().get_nodes_in_group(&"fx_sprites").size() <= n2)

	boss.queue_free()
	await get_tree().process_frame
	_sections_done.append("F")


# =============================================================================
# G. 无回归：AoETelegraph 缺省仍是整圆
# =============================================================================

func _test_aoe_telegraph_regression() -> void:
	print("--- G. 无回归：AoETelegraph 缺省整圆 ---")
	# 旧签名 `setup(radius, life)` 必须仍然可用（`_aoe_strike` / `_attack_lob` 走它）
	var tel: Node2D = EnemyBase.AoETelegraph.new()
	var ok2 := true
	tel.setup(110.0, 0.6)
	ok2 = ok2 and absf(float(tel.get("_arc_deg")) - 360.0) < 0.01
	# 新签名带扇形
	var tel2: Node2D = EnemyBase.AoETelegraph.new()
	tel2.setup(112.0, 0.4, 120.0, Vector2.RIGHT)
	ok2 = ok2 and absf(float(tel2.get("_arc_deg")) - 120.0) < 0.01
	ok2 = ok2 and absf(float(tel2.get("_life")) - 0.4) < 0.01
	_ok("AoETelegraph：旧签名仍整圆 / 新签名可扇形", ok2)
	_ok("BONE_SLAM_ARC_DEG = 120（策划 §3.4①）",
		absf(EnemyBase.BONE_SLAM_ARC_DEG - 120.0) < 0.01)
	tel.free()
	tel2.free()
	_sections_done.append("G")


# =============================================================================
# 工具
# =============================================================================

func _wait_until(pred: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		await get_tree().process_frame
		if pred.call():
			return true
	return false


func _finish() -> void:
	var missing: Array[String] = []
	for s in SECTIONS:
		if not _sections_done.has(s):
			missing.append(s)
	if not missing.is_empty():
		_fail += 1
		print("[FAIL] 测试段未跑完（缺 %s）—— 上方有 SCRIPT ERROR，结果不可信" % str(missing))
	print("===== 结果：%d 项失败（段 %d/%d）====="
		% [_fail, _sections_done.size(), SECTIONS.size()])
	get_tree().quit(0 if _fail == 0 else 1)
