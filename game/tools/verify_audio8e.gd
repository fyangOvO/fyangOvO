## 音效包实测（步骤 8E · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_audio8e.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（4 个测试段）：
##   A. 8E 音效注册：boss_roar 已注册；10 个 wav 文件全部存在
##   B. 采样率契约：全部 AudioStreamWAV 且 mix_rate == 22050（与旧占位音效同规格）
##   C. 时长合理：每类音效在预期窗口内（开战吼/阶段转换/命中/药水/死亡/升级/拾取）
##   D. 挂接接线：level_scene 觉醒结束播 boss_roar；enemy_base 阶段转换播 boss_phase；
##      player_controller 用药播 potion_drink
extends Node

var _fail: int = 0

## id → 合理时长窗口（秒）：短促 SFX 必须精确，过长/过短都算失败
const DUR_WINDOWS := {
	"boss_roar": [1.5, 2.5],
	"boss_phase": [0.8, 1.8],
	"hit_melee": [0.3, 1.0],
	"hit_crit": [0.3, 1.0],
	"potion_drink": [0.5, 1.5],
	"enemy_die": [0.4, 1.2],
	"levelup": [0.6, 1.5],
	"pickup_item": [0.2, 1.0],
}


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 音效包实测（步骤 8E） =====")
	_test_registry()
	_test_format()
	_test_durations()
	_test_hooks()
	_finish()


func _test_registry() -> void:
	print("--- A. 8E 音效注册与文件 ---")
	_ok("boss_roar 已注册（开战吼）", AudioManager.has("boss_roar"))
	_ok("注册表 10 条音效", AudioManager.ids().size() == 10)
	var bad := 0
	for id in AudioManager.ids():
		var meta: Dictionary = AudioManager.SFX_REGISTRY[id]
		var p := "res://data/audio/%s" % meta.get("file", "")
		if not ResourceLoader.exists(p):
			bad += 1
			print("  missing: %s" % p)
	_ok("data/audio/ 10 个 wav 资源全部存在", bad == 0)


func _test_format() -> void:
	print("--- B. 采样率契约（22050Hz 16-bit mono） ---")
	var bad := 0
	for id in AudioManager.ids():
		var stream := AudioManager._stream_for(id)
		if stream == null or not (stream is AudioStreamWAV):
			bad += 1
			print("  not wav: %s" % id)
			continue
		var wav := stream as AudioStreamWAV
		if wav.mix_rate != 22050 or wav.data.is_empty():
			bad += 1
			print("  bad rate/data: %s (%d Hz)" % [id, wav.mix_rate])
	_ok("全部 AudioStreamWAV 且 22050Hz 数据非空", bad == 0)


func _test_durations() -> void:
	print("--- C. 时长合理（短促 SFX 精确） ---")
	# ⚠️ 不能用 AudioStreamWAV.data.size()：.import 默认 compress/mode=2（QOA 压缩），
	#    data 是压缩字节而非原始 PCM，算出来的时长偏小 ~5 倍。
	#    直接解析 WAV 文件头（fmt 采样率 + data 块大小）求真实时长。
	var bad := 0
	for id in DUR_WINDOWS:
		if not AudioManager.has(id):
			bad += 1
			print("  missing id: %s" % id)
			continue
		var meta: Dictionary = AudioManager.SFX_REGISTRY[id]
		var f := FileAccess.open("res://data/audio/%s" % meta.get("file", ""), FileAccess.READ)
		if f == null:
			bad += 1
			print("  cannot open: %s" % id)
			continue
		var dur := _wav_duration(f)
		f.close()
		var win: Array = DUR_WINDOWS[id]
		if dur < win[0] or dur > win[1]:
			bad += 1
			print("  %s 时长 %.2fs 超出窗口 %.1f–%.1f" % [id, dur, win[0], win[1]])
	_ok("8 个 8E 核心音效时长均在预期窗口", bad == 0)


## 解析 WAV 头（RIFF）：返回时长秒；格式异常返回 -1。
## 假设标准 PCM WAV：RIFF/WAVE → fmt 子块（audio_format=1）→ data 子块。
func _wav_duration(f: FileAccess) -> float:
	if f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return -1.0
	f.get_buffer(8)  # size + WAVE
	var sample_rate := 22050
	var block_align := 2
	var data_bytes := 0
	while f.get_position() < f.get_length() - 8:
		var cid := f.get_buffer(4).get_string_from_ascii()
		var csize := f.get_32()
		if cid == "fmt ":
			var audio_format := f.get_16()
			f.get_16()  # channels
			sample_rate = f.get_32()
			f.get_32()  # byte rate
			block_align = f.get_16()
			f.get_16()  # bits per sample
			f.get_buffer(maxi(csize - 16, 0))
			if audio_format != 1:
				return -1.0
		elif cid == "data":
			data_bytes = csize
			f.get_buffer(csize)
		else:
			f.get_buffer(csize + (csize & 1))
	if data_bytes <= 0 or block_align <= 0:
		return -1.0
	return float(data_bytes) / float(sample_rate * block_align)


func _test_hooks() -> void:
	print("--- D. 挂接接线 ---")
	var ls := FileAccess.open("res://scripts/run/level_scene.gd", FileAccess.READ)
	var eb := FileAccess.open("res://scripts/enemies/enemy_base.gd", FileAccess.READ)
	var pc := FileAccess.open("res://scripts/player/player_controller.gd", FileAccess.READ)
	var ls_s := ls.get_as_text() if ls != null else ""
	var eb_s := eb.get_as_text() if eb != null else ""
	var pc_s := pc.get_as_text() if pc != null else ""
	_ok("level_scene：BOSS 觉醒结束播 boss_roar（开战吼）",
		ls_s.contains("AudioManager.play(\"boss_roar\")"))
	_ok("enemy_base：BOSS 阶段转换播 boss_phase",
		eb_s.contains("AudioManager.play(\"boss_phase\")"))
	_ok("player_controller：饮用药水播 potion_drink",
		pc_s.contains("AudioManager.play(\"potion_drink\")"))


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
