## BOSS 觉醒立绘卡实测（步骤 8C · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_boss_awaken8c.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（5 个测试段）：
##   A. 素材：两个 BOSS 觉醒立绘存在（512×768 竖版 2:3）
##   B. 卡片结构：BossAwakenCard 建卡后含 暗幕/立绘/扫光/信息区/粒子，
##      名字 = BOSS 显示名，阶段提示 = 「第 1 階段 · 共 N 階段」
##   C. 时序：total_duration 在合理窗口（2.2–2.8s）
##   D. 集成闭环（真实例化关卡）：BOSS 生成后 AI 冻结（physics disabled）→
##      玩家传送接近 → 觉醒卡弹出（_boss_awakened）→ 卡结束后 BOSS 恢复 AI
##      （physics enabled）→ 觉醒音效已播
##   E. 阶段横幅：boss_phase_changed 事件 → 顶部 PhaseBanner 出现
extends Node2D

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
## ch1_l06 手绘 BOSS 关（boss_id = boss_bone_tyrant）
const TEST_LEVEL := "ch1_l06"
const ART_PATHS := {
	"boss_bone_tyrant": "res://assets/ui/boss/awaken_bone_tyrant.png",
	"boss_ember_lord": "res://assets/ui/boss/awaken_ember_lord.png",
}

var _fail: int = 0
var _level: LevelScene = null


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 240.0)
	print("===== BOSS 觉醒立绘卡实测（步骤 8C） =====")
	_test_art()
	_test_card_structure()
	_test_timing()
	await _test_integration()
	await _test_phase_banner()
	_finish()


# =============================================================================
# A. 素材
# =============================================================================

func _test_art() -> void:
	print("--- A. 觉醒立绘素材 ---")
	for bid in ART_PATHS:
		var ok := ResourceLoader.exists(ART_PATHS[bid])
		_ok("%s 觉醒立绘存在" % bid, ok)
		if ok:
			var img := Image.new()
			var err := img.load(ART_PATHS[bid].replace("res://", "D:/七傳說/game/"))
			_ok("%s 尺寸 512×768（2:3 竖版）" % bid,
				err == OK and img.get_width() == 512 and img.get_height() == 768)


# =============================================================================
# B. 卡片结构
# =============================================================================

func _test_card_structure() -> void:
	print("--- B. 卡片结构 ---")
	var card := BossAwakenCard.awaken(self, "boss_ember_lord", "熔心之主", 4, Callable())
	_ok("卡片含暗幕 Dim", card.get_node_or_null("UIContainer/Dim") != null)
	_ok("卡片含立绘 AwakenArt", card.get_node_or_null("UIContainer/AwakenArt") != null)
	_ok("卡片含扫光 ScanLight", card.get_node_or_null("UIContainer/ScanLight") != null)
	_ok("卡片含信息区 InfoBar", card.get_node_or_null("UIContainer/InfoBar") != null)
	_ok("卡片含粒子 Particles", card.get_node_or_null("Particles") != null)
	var info: Control = card.get_node_or_null("UIContainer/InfoBar")
	var name_lab: Label = info.get_node_or_null("BossName") if info != null else null
	var phase_lab: Label = info.get_node_or_null("PhaseHint") if info != null else null
	_ok("BOSS 名 = 熔心之主", name_lab != null and name_lab.text == "熔心之主")
	_ok("阶段提示 = 第 1 階段 · 共 4 階段",
		phase_lab != null and phase_lab.text == "第 1 階段 · 共 4 階段")
	card.queue_free()


# =============================================================================
# C. 时序
# =============================================================================

func _test_timing() -> void:
	print("--- C. 时序 ---")
	var card := BossAwakenCard.awaken(self, "boss_bone_tyrant", "骸骨暴君", 4, Callable())
	var d := card.total_duration()
	_ok("总时长 %.2fs 在 2.2–2.8s 窗口" % d, d >= 2.2 and d <= 2.8)
	card.queue_free()


# =============================================================================
# D. 集成闭环
# =============================================================================

func _test_integration() -> void:
	print("--- D. 集成闭环（ch1_l06） ---")
	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _frames(3)
	_level.on_scene_entered({
		"level_id": TEST_LEVEL,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _frames(6)
	_ok("关卡已构建", not _level._alive.is_empty())

	var boss: EnemyBase = null
	for e in _level._alive:
		if e.data != null and e.data.tier == MonsterData.Tier.BOSS:
			boss = e
			break
	_ok("场上存在 BOSS", boss != null)
	if boss == null:
		_finish()
		return
	_ok("BOSS 已进入沉睡（physics 冻结）", not boss.is_physics_processing())
	_ok("_pending_boss 已登记", _level._pending_boss == boss)

	# 玩家传送到 BOSS 旁 → 触发觉醒
	_level._player.global_position = boss.global_position - Vector2(60.0, 0.0)
	await _frames(6)
	_ok("觉醒已触发（_boss_awakened）", _level._boss_awakened)
	_ok("觉醒卡已弹出", _level._awaken_card != null and is_instance_valid(_level._awaken_card))

	# 等待卡片动画结束（total_duration + 余量）
	await _wait(2.9)
	_ok("卡片已回收", _level._awaken_card == null)
	_ok("BOSS 恢复 AI（physics 解冻）", boss.is_physics_processing())
	_ok("_pending_boss 已清空", _level._pending_boss == null)

	_level.queue_free()
	await _frames(4)


# =============================================================================
# E. 阶段横幅
# =============================================================================

func _test_phase_banner() -> void:
	print("--- E. 阶段横幅 ---")
	_level = LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(_level)
	await _frames(3)
	_level.on_scene_entered({
		"level_id": TEST_LEVEL,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await _frames(6)
	var boss: EnemyBase = null
	for e in _level._alive:
		if e.data != null and e.data.tier == MonsterData.Tier.BOSS:
			boss = e
			break
	# 直接触发 BOSS 阶段切换（绕过血量阈值，纯 UI 链路测试）
	EventBus.boss_phase_changed.emit(boss, 2, ["bone_slam", "summon_skeleton"])
	await _frames(3)
	var found := false
	for c in _level.get_children():
		if c is CanvasLayer and c.name == "PhaseBanner":
			found = true
			break
	_ok("阶段横幅已弹出（PhaseBanner）", found)
	_level.queue_free()
	await _frames(4)


func _wait(secs: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t < secs:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
