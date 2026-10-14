## 音效/音乐实测（任务 6.6 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_audio66.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（6 个测试段）：
##   A. 注册表：8 条音效（打击/暴击/死亡/金币/装备/升级/BOSS 阶段/点击）
##   B. 文件存在：data/audio/ 8 个 wav 全部可加载（AudioStreamWAV）
##   C. 流可解析：AudioStreamWAV 数据非空（时长/数据长度合法）
##   D. 播放管线：Dummy 驱动下 play() 跳过不建播放器 / 真实驱动下挂载（2026-10-14 改口径）
##   E. 钩子接线：enemy_base/player_controller/run_progression 引用 AudioManager
##   F. 音量合法：全部 volume_db 在 -24..0 dB 区间
extends Node

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 音效/音乐实测（任务 6.6） =====")
	_test_registry()
	_test_files()
	_test_streams()
	_test_pipeline()
	_test_hooks()
	_test_volumes()
	_finish()


func _test_registry() -> void:
	print("--- A. 注册表 ---")
	var ids := AudioManager.ids()
	_ok("注册表 10 条音效", ids.size() == 10)
	var want := ["hit_melee", "hit_crit", "enemy_die", "pickup_gold",
		"pickup_item", "levelup", "boss_roar", "boss_phase", "ui_click"]
	var miss := 0
	for w in want:
		if not AudioManager.has(w):
			miss += 1
	_ok("8 个 id 全部注册", miss == 0)


func _test_files() -> void:
	print("--- B. 文件存在 ---")
	var bad := 0
	for id in AudioManager.ids():
		var meta: Dictionary = AudioManager.SFX_REGISTRY[id]
		var p := "res://data/audio/%s" % meta.get("file", "")
		if not ResourceLoader.exists(p):
			bad += 1
			print("  missing: %s" % p)
	_ok("data/audio/ 8 个 wav 资源全部存在", bad == 0)


func _test_streams() -> void:
	print("--- C. 流可解析 ---")
	var bad := 0
	for id in AudioManager.ids():
		var stream := AudioManager._stream_for(id)
		if stream == null:
			bad += 1
			continue
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			if wav.data.is_empty() or wav.mix_rate <= 0:
				bad += 1
	_ok("全部流可加载且 AudioStreamWAV 数据非空", bad == 0)


func _test_pipeline() -> void:
	print("--- D. 播放管线 ---")
	# 契约（2026-10-14 改）：**Dummy 音频驱动（headless / CI）下 `play()` 直接跳过、不建播放器**。
	# 原因：Dummy 驱动不推进播放头 ⇒ `finished` 永不触发 ⇒ 播放器会一直挂在根节点上，
	# 退出时报 `leaked at exit`（实测全库 77 个 verify 里 21 个中招）。无头下本来也听不到声。
	# ⇒ 断言必须**分运行时**写，否则「跳过」会被 `>=` 掩盖成一条永远通过的废断言。
	var tree := get_tree()
	var before := tree.root.get_child_count()
	AudioManager.play("ui_click")
	AudioManager.play("hit_melee")
	await get_tree().process_frame
	await get_tree().process_frame
	var after := tree.root.get_child_count()
	if AudioManager._is_silent_runtime():
		_ok("Dummy 驱动下 play() 不创建播放器（防退出泄漏）", after == before)
	else:
		_ok("真实驱动下 play() 挂载播放器（播放即焚：2 个尚未播完）", after > before)


func _test_hooks() -> void:
	print("--- E. 钩子接线 ---")
	var eb := FileAccess.open("res://scripts/enemies/enemy_base.gd", FileAccess.READ)
	var pc := FileAccess.open("res://scripts/player/player_controller.gd", FileAccess.READ)
	var rp := FileAccess.open("res://scripts/run/run_progression.gd", FileAccess.READ)
	var eb_s := eb.get_as_text() if eb != null else ""
	var pc_s := pc.get_as_text() if pc != null else ""
	var rp_s := rp.get_as_text() if rp != null else ""
	_ok("enemy_base：受击 hit_melee / 死亡 enemy_die / BOSS 阶段 boss_phase",
		eb_s.contains("AudioManager.play(\"hit_melee\")")
		and eb_s.contains("AudioManager.play(\"enemy_die\")")
		and eb_s.contains("AudioManager.play(\"boss_phase\")"))
	_ok("player_controller：拾取 pickup_gold / pickup_item",
		pc_s.contains("AudioManager.play(\"pickup_gold\")")
		and pc_s.contains("AudioManager.play(\"pickup_item\")"))
	_ok("run_progression：升级 levelup", rp_s.contains("AudioManager.play(\"levelup\")"))


func _test_volumes() -> void:
	print("--- F. 音量合法 ---")
	var bad := 0
	for id in AudioManager.ids():
		var v: float = AudioManager.SFX_REGISTRY[id].get("volume_db", 0.0)
		if v < -24.0 or v > 0.0:
			bad += 1
	_ok("全部 volume_db 在 -24..0 dB", bad == 0)


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
