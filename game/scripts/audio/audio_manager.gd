## 音效管理器（任务 6.6 · 纯静态，零 autoload 配置）
##
## 占位音效为程序化合成 WAV（data/audio/*.wav，22050Hz 16-bit mono），
## 与占位色块美术同思路：先闭环自玩体验，后续可用真音频直接替换文件。
##
## 用法：AudioManager.play("hit_melee")  —— 播放即焚（播完自动释放节点）。
## 注册表：SFX_REGISTRY（id → 文件 + 音量）。全部合法 id 由 main.gd 自检校验。
class_name AudioManager

const SFX_REGISTRY := {
	"hit_melee": {"file": "hit_melee.wav", "volume_db": -6.0},
	"hit_crit": {"file": "hit_crit.wav", "volume_db": -4.0},
	"enemy_die": {"file": "enemy_die.wav", "volume_db": -8.0},
	"pickup_gold": {"file": "pickup_gold.wav", "volume_db": -10.0},
	"pickup_item": {"file": "pickup_item.wav", "volume_db": -8.0},
	"levelup": {"file": "levelup.wav", "volume_db": -4.0},
	"boss_phase": {"file": "boss_phase.wav", "volume_db": -6.0},
	"ui_click": {"file": "ui_click.wav", "volume_db": -12.0},
}

## id → 预载 AudioStreamWAV（首次访问惰性加载）
static var _streams := {}

## BGM 常驻播放器（与一次性音效分开）
static var _bgm_player: AudioStreamPlayer = null
static var _bgm_playing: String = ""


static func _stream_for(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var meta: Dictionary = SFX_REGISTRY.get(id, {})
	if meta.is_empty():
		return null
	var path := "res://data/audio/%s" % meta.get("file", "")
	var stream := load(path) as AudioStream
	_streams[id] = stream
	return stream


## 播放指定音效（播放即焚；无场景树时静默跳过，保证 verify 无副作用）。
## 树忙安全：main._ready 自检等「父节点正在 setup children」阶段调用时，
## 用 deferred add_child + ready 触发 play，避免 add_child/play 报错（9.1 修复）。
static func play(id: String, volume_override: float = INF) -> void:
	var meta: Dictionary = SFX_REGISTRY.get(id, {})
	if meta.is_empty():
		return
	var stream := _stream_for(id)
	if stream == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_override if volume_override != INF else float(meta.get("volume_db", 0.0))
	player.ready.connect(player.play)
	player.finished.connect(player.queue_free)
	tree.root.add_child.call_deferred(player)


static func has(id: String) -> bool:
	return SFX_REGISTRY.has(id)


## 为按钮统一挂 UI 点击音（菜单 / 据点 / 角色选择等所有入口按钮）
static func hook_click(btn: BaseButton) -> void:
	btn.pressed.connect(func() -> void: play("ui_click"))


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in SFX_REGISTRY:
		out.append(String(k))
	out.sort()
	return out


# =============================================================================
# BGM 循环播放（用户覆盖优先：user://content/music/<basename>）
# =============================================================================

## 播放背景音乐（循环）。`bundled` 为内置路径；同名文件放
## user://content/music/ 即覆盖。同一路径重复调用不重起。
static func play_bgm(bundled: String) -> void:
	if bundled.is_empty():
		stop_bgm()
		return
	if _bgm_playing == bundled and _bgm_player != null and _bgm_player.playing:
		return
	var stream := ContentLoader.load_bgm(bundled)
	if stream == null:
		# 没有 BGM 文件 → 静默，不报错（很多关没有 BGM 是正常的）
		stop_bgm()
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.bus = "Master"
		tree.root.add_child.call_deferred(_bgm_player)
	_bgm_player.stream = stream
	_bgm_player.volume_db = -8.0  # BGM 压在音效底下
	_bgm_player.finished.connect(_on_bgm_finished)
	_bgm_player.play()
	_bgm_playing = bundled


static func _on_bgm_finished() -> void:
	# 循环：BGM 播完自动重起（ogg 一般内置循环点，这里兜底）
	if _bgm_player != null and _bgm_playing != "":
		_bgm_player.play()


static func stop_bgm() -> void:
	_bgm_playing = ""
	if _bgm_player != null:
		_bgm_player.stop()
