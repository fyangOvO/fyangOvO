## 9.x 综合打磨实测（开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_polish9x.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（5 个测试段）：
##   A. 手感·受击硬直（hitstun）：enemy_base 真掉血打断追击（0.12s ×0.25）
##   B. 手感·BOSS 范围技能警示（telegraph）：0.6s 红色圆环后延迟命中
##   C. 平衡·敌人成长收敛：HP / DMG growth **同为 1.12**（路线 A · 4-W1）；
##      裸装模拟 Lv20 TTK ≈ 15 击、承伤 ≈ 12 击（不再海绵 / 不再猝死）
##   D. 难度·怪物预算平滑：三章 20 关预算单调递进、章内涨幅 ≤ 25、
##      章节衔接跌幅 ≤ 20%（ch2/ch3 头 ≥ 前章尾 ×0.8）；合计 5,660（路线 A · 4-W2）
##   E. 性能·回归保障：ObjectPool + LevelView 批处理仍就位（perf83 已全绿，本次不改性能代码）
extends Node2D

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 9.x 综合打磨实测 =====")
	_test_hitstun()
	_test_telegraph()
	_test_balance()
	_test_difficulty_curve()
	_test_perf_baseline()
	_finish()


func _test_hitstun() -> void:
	print("--- A. 手感·受击硬直 ---")
	var eb := FileAccess.open("res://scripts/enemies/enemy_base.gd", FileAccess.READ)
	var s := eb.get_as_text() if eb != null else ""
	_ok("enemy_base 定义 HITSTUN_DURATION=0.12", s.contains("const HITSTUN_DURATION: float = 0.12"))
	_ok("enemy_base 定义 HITSTUN_SPEED_MULT=0.25", s.contains("const HITSTUN_SPEED_MULT: float = 0.25"))
	_ok("真掉血时设受击硬直", s.contains("_hitstun_timer = HITSTUN_DURATION"))
	_ok("AI 移动在硬直期间打折", s.contains("HITSTUN_SPEED_MULT if _hitstun_timer > 0.0 else 1.0"))


func _test_telegraph() -> void:
	print("--- B. 手感·BOSS 范围技能警示 ---")
	var eb := FileAccess.open("res://scripts/enemies/enemy_base.gd", FileAccess.READ)
	var s := eb.get_as_text() if eb != null else ""
	_ok("enemy_base 定义 AOE_TELEGRAPH_TIME=0.6", s.contains("const AOE_TELEGRAPH_TIME: float = 0.6"))
	_ok("警示后延迟命中（_aoe_impact）", s.contains("func _aoe_impact"))
	_ok("AoETelegraph 视觉类（红色闪烁圆环）", s.contains("class AoETelegraph extends Node2D")
		and s.contains("draw_arc"))
	_ok("BOSS 范围技能集不变（shockwave/magma 仍在阶段技能）",
		s.contains("has_aoe := _boss_skills.has(\"shockwave\") or _boss_skills.has(\"magma_eruption\")"))


func _test_balance() -> void:
	print("--- C. 平衡·敌人成长收敛 ---")
	# ⚠️ 断言引用 GameConstants 而**不是写死数字** —— 旧版写死 1.22 / 1.16，
	#    等于把「常量有没有被改动」这件事排除在断言之外（改了也不会红）。
	_ok("MONSTER_HP_GROWTH = 1.12（路线 A · 4-W1）",
		GameConstants.MONSTER_HP_GROWTH == 1.12)
	_ok("MONSTER_DMG_GROWTH = 1.12（与 HP 同值 ⇒ 相对强度全程恒定）",
		GameConstants.MONSTER_DMG_GROWTH == 1.12)
	# 裸装模拟（无装备下限）：Lv20 常规怪（hp_scale=1.25）
	var mhp := GameConstants.MONSTER_HP_AT_L1 \
		* pow(GameConstants.MONSTER_HP_GROWTH, 19.0) * 1.25
	var p_ad := 12.0 * pow(1.10, 19)
	var ttk := mhp / p_ad
	# 设计目标（GDD 04 §3.2 修复后预测表）：L20 击杀击数 ≈ 11.8
	# ⇒ 裸装下限放宽到 2.5×；调前（1.22）是 75 击。
	_ok("裸装 Lv20 TTK = %.1f 击 ≤ 30（设计 ~11.8 击；调前 1.22 时 75 击）" % ttk, ttk <= 30.0)
	var mdmg := GameConstants.MONSTER_DMG_AT_L1 \
		* pow(GameConstants.MONSTER_DMG_GROWTH, 19.0) * 1.25
	var p_hp := 150.0 * pow(1.11, 19) * (95.0 / 150.0)  # 战士裸装 HP
	var dr := 1.0 - 12.0 / (12.0 + 50.0 * 20)
	var hits := p_hp / (mdmg * dr)
	# 设计目标：L20 被击杀数 ≈ 22.5（同上表；本式另乘 1.25 常规怪倍率、再扣护甲减伤 ⇒ 约一半）
	_ok("裸装 Lv20 承伤 = %.1f 击 ≥ 8（设计 ~22.5 击；调前 1.16 时 5.9 击）" % hits, hits >= 8.0)


func _test_difficulty_curve() -> void:
	print("--- D. 难度·怪物预算平滑 ---")
	# 路线 A（4-W2）：章节梯度 120→440，合计 5,660（原 1,199 / 均值 60.0）
	var ch1: Array = [120, 140, 160, 175, 190, 210]
	var ch2: Array = [230, 250, 265, 280, 295, 310, 325]
	var ch3: Array = [340, 355, 370, 385, 400, 420, 440]
	var curves := {"chapter1": ch1, "chapter2": ch2, "chapter3": ch3}
	# ⚠️ 章内涨幅上限由 12 放宽到 25：新序列 ch1 段 190→210 涨 20
	#    （旧序列最大 8），见 GDD 05 §5.2「须放宽阈值或改为比例单调」。
	var bad := 0
	for ch in curves:
		var arr: Array = curves[ch]
		for i in arr.size() - 1:
			var a: int = arr[i]
			var b: int = arr[i + 1]
			if b < a or b - a > 25:
				bad += 1
				print("  %s 段 %d→%d 不单调/涨幅过大" % [ch, a, b])
	_ok("三章章内预算单调递增且涨幅 ≤ 25", bad == 0)
	_ok("章节衔接不暴跌：ch2 头 ≥ ch1 尾×0.8、ch3 头 ≥ ch2 尾×0.8",
		ch2[0] >= int(ch1[5] * 0.8) and ch3[0] >= int(ch2[6] * 0.8))
	var total := 0
	for ch in curves:
		for v in curves[ch]:
			total += int(v)
	_ok("三章预算合计 = %d ∈ [5400, 5900]（第四步 T8 目标 5,660）" % total,
		total >= 5400 and total <= 5900)
	# 与数据文件一致（直接读 JSON，不依赖 autoload）
	var bad2 := 0
	for i in 3:
		var ch_key := "chapter%d" % (i + 1)
		var f := FileAccess.open("res://data/levels/%s.json" % ch_key, FileAccess.READ)
		var raw: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		if f == null or raw == null:
			bad2 += 1
			continue
		var first_budget: int = raw[0].get("total_monster_budget", 0)
		if first_budget != curves[ch_key][0]:
			bad2 += 1
			print("  %s 首关 budget=%d 预期 %d" % [ch_key, first_budget, curves[ch_key][0]])
	_ok("数据文件 budget 与曲线一致（抽查每章第 1 关）", bad2 == 0)


func _test_perf_baseline() -> void:
	print("--- E. 性能·回归保障 ---")
	# 纯文本断言（避免 headless 下 load/类查询挂死风险）
	# 纯文本断言（避免 headless 下类注册/加载依赖风险）
	var op_text := ""
	var op_file := FileAccess.open("res://scripts/core/object_pool.gd", FileAccess.READ)
	if op_file != null:
		op_text = op_file.get_as_text()
	_ok("ObjectPool 类注册可用（class_name 就位）", op_text.contains("class_name ObjectPool"))
	var lv_text := ""
	var lv_file := FileAccess.open("res://scenes/levels/level.tscn", FileAccess.READ)
	if lv_file != null:
		lv_text = lv_file.get_as_text()
	_ok("level.tscn 引用 LevelView 批处理（level_view.gd）", lv_text.contains("level_view.gd"))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
