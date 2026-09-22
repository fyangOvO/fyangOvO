## 场景管理器（Autoload · 单例名 `SceneManager`）
##
## 职责：
##   1. **场景切换** —— 统一的切换入口，其他模块只发 `EventBus.request_scene_change`
##   2. **异步加载** —— 用 `ResourceLoader.load_threaded_request` 后台加载，避免大关卡卡帧
##   3. **过场** —— 自动生成淡入淡出遮罩 + 载入进度提示，无需手工维护 UI 场景
##
## 用法：
##   SceneManager.change_scene("res://scenes/levels/ch1_l01.tscn", {"level_id": "ch1_l01"})
##   SceneManager.change_to_level("ch1_l01", GameConstants.DifficultyTier.NM1)
##
## 载荷传递：新场景根节点若实现了 `func on_scene_entered(payload: Dictionary)`，
##           切换完成后会被自动调用一次（用于接收 level_id / 难度等参数）。
##
## ⚠️ 本管理器**不做关卡玩法逻辑**，只负责「把场景换掉并把参数递过去」。
extends Node

## 场景切换中的互斥标志（防止连点导致并发切换）
var is_transitioning: bool = false

## 当前场景路径
var current_scene_path: String = ""

## 过场淡入淡出时长（秒）
var fade_duration: float = 0.25

## 是否显示载入进度文字
var show_loading_progress: bool = true

## 最近一次错误
var last_error: String = ""

## 场景路径常量（新增场景时在此登记，避免路径字符串散落各处）
const SCENE_BOOT: String = "res://scenes/main/main.tscn"      ## 启动分流（--verify / 进游戏）
const SCENE_MAIN_MENU: String = "res://scenes/main/main_menu.tscn"
const SCENE_HUB: String = "res://scenes/main/hub.tscn"

## 通用关卡容器（20 关共用一份）。关卡差异全部由 `on_scene_entered(payload)` 里的
## level_id + difficulty_tier 驱动，不靠 20 份 .tscn。
const SCENE_LEVEL: String = "res://scenes/levels/level.tscn"

var _overlay_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _loading_label: Label = null

## 待切换的载荷（切换完成后递交给新场景）
var _pending_payload: Dictionary = {}

## 最近一次关卡结算的载荷（`EventBus.level_completed` 的 `summary` 原样保存）。
##
## 为什么监听者放在 SceneManager（Autoload）而不是据点：
##   `change_scene()` 内部走 `tree.change_scene_to_packed()`（本文件 :194），它会**释放旧场景**。
##   结算那一刻在树上的是关卡场景，据点还没被实例化 —— 所以任何挂在 hub 上的监听
##   在真实流程里**永不触发**（只有单场景调试时才偶然有效）。
##   Autoload 常驻，是唯一能稳定收到该信号的地方。
var last_run_summary: Dictionary = {}


func _ready() -> void:
	_build_transition_overlay()
	EventBus.request_scene_change.connect(_on_request_scene_change)
	EventBus.request_start_level.connect(_on_request_start_level)
	EventBus.level_completed.connect(_on_level_completed)


## 关卡结算广播的消费点（**全项目唯一**）。
##
## 载荷契约（team-lead 裁决）：`summary` 只有**一个键** —— `{"result": RunResult}`，直通不做镜像。
## 这样消费方拿到的是结算单本体，不需要跟着 RunResult 的字段增删改镜像字典。
func _on_level_completed(level_id: String, difficulty_tier: int, summary: Dictionary) -> void:
	last_run_summary = summary
	var res: RunResult = summary.get("result", null)
	if res == null:
		# 格式不符时明确吵一声：否则这条广播会静默变成「发了但没人看懂」
		push_warning("[SceneManager] level_completed 载荷缺 'result' 键（level=%s）" % level_id)
		GameLog.warn("关卡结算载荷格式异常：level=%s keys=%s"
			% [level_id, str(summary.keys())])
		return
	GameLog.info("关卡结算：%s · 难度 %d · %s · 击杀 %d · 局内等级 %d · 评分 %s（%.0f）"
		% [level_id, difficulty_tier, "存活" if res.survived else "失败",
			res.kills, res.run_level, res.grade, res.score])


# =============================================================================
# 公开接口
# =============================================================================

## 切换到任意场景。payload 会递交给新场景的 `on_scene_entered`（若存在）。
func change_scene(scene_path: String, payload: Dictionary = {}) -> void:
	if is_transitioning:
		push_warning("[SceneManager] 正在切换中，忽略本次请求：%s" % scene_path)
		return

	if not ResourceLoader.exists(scene_path):
		last_error = "场景不存在：%s" % scene_path
		push_error("[SceneManager] " + last_error)
		EventBus.notify(last_error, Color("E8573F"))
		return

	is_transitioning = true
	_pending_payload = payload

	EventBus.scene_transition_started.emit(scene_path)

	await _fade_out()
	await _load_and_swap(scene_path)
	await _fade_in()

	current_scene_path = scene_path
	is_transitioning = false
	EventBus.scene_transition_finished.emit(scene_path)


## 切换到关卡场景。
## 场景路径解析顺序（阶段 2 决策：**不造 20 份 .tscn**）：
##   1. `LevelData.scene_path` —— 存在该文件就用它（将来某一关要做专属场景时）
##   2. `res://scenes/levels/<level_id>.tscn` —— 命名约定兜底
##   3. `SCENE_LEVEL`（通用容器）—— 前两者都不存在时的最终兜底
## 无论走哪条，载荷恒为 `{level_id, difficulty_tier}`，关卡容器靠它自取数据。
func change_to_level(level_id: String, difficulty_tier: int = GameConstants.DifficultyTier.NM1) -> void:
	var level := ConfigLoader.get_level(level_id)
	var scene_path := ""

	if level != null and not level.scene_path.is_empty():
		scene_path = level.scene_path
	else:
		scene_path = "res://scenes/levels/%s.tscn" % level_id

	if not ResourceLoader.exists(scene_path):
		if level != null and not level.scene_path.is_empty():
			print("[SceneManager] 关卡专属场景不存在，回退通用容器：%s → %s"
				% [level.scene_path, SCENE_LEVEL])
		scene_path = SCENE_LEVEL

	if level == null:
		push_warning("[SceneManager] 关卡 '%s' 未在数据表中定义，仍尝试加载场景" % level_id)

	change_scene(scene_path, {
		"level_id": level_id,
		"difficulty_tier": difficulty_tier,
	})


## 回据点（主菜单 / 营地）
func change_to_hub() -> void:
	change_scene(SCENE_HUB, {})


## 重新加载当前场景
func reload_current_scene() -> void:
	var tree := get_tree()
	if tree.current_scene == null:
		return
	change_scene(tree.current_scene.scene_file_path, _pending_payload)


## 取当前场景根节点（未就绪返回 null）
func get_current_scene() -> Node:
	return get_tree().current_scene


# =============================================================================
# 内部：切换流程
# =============================================================================

func _load_and_swap(scene_path: String) -> void:
	_show_loading(true, 0.0)

	# 1) 发起后台加载
	var err := ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if err != OK:
		push_warning("[SceneManager] 后台加载发起失败（错误码 %d），回退为同步加载" % err)
		await _swap_scene_sync(scene_path)
		_show_loading(false, 1.0)
		return

	# 2) 轮询进度（每帧检查一次，不阻塞主线程）
	var packed: PackedScene = null
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		var ratio: float = progress[0] if progress.size() > 0 else 0.0

		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				packed = ResourceLoader.load_threaded_get(scene_path) as PackedScene
				_show_loading(true, 1.0)
				break
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_show_loading(true, ratio)
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("[SceneManager] 后台加载失败：%s，回退为同步加载" % scene_path)
				await _swap_scene_sync(scene_path)
				_show_loading(false, 1.0)
				return
			_:
				await get_tree().process_frame

	# 3) 替换场景（_apply_scene 内部会 await 两帧等待 current_scene 生效）
	if packed == null:
		last_error = "加载结果为空：%s" % scene_path
		push_error("[SceneManager] " + last_error)
		_show_loading(false, 1.0)
		return

	await _apply_scene(packed, scene_path)
	_show_loading(false, 1.0)


func _swap_scene_sync(scene_path: String) -> void:
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		last_error = "同步加载失败：%s" % scene_path
		push_error("[SceneManager] " + last_error)
		return
	await _apply_scene(packed, scene_path)


func _apply_scene(packed: PackedScene, scene_path: String) -> void:
	var tree := get_tree()
	var swap_err := tree.change_scene_to_packed(packed)
	if swap_err != OK:
		last_error = "场景替换失败（错误码 %d）：%s" % [swap_err, scene_path]
		push_error("[SceneManager] " + last_error)
		return

	# change_scene_to_packed 是延迟生效的，等一帧后 current_scene 才是新场景
	await tree.process_frame
	await tree.process_frame

	current_scene_path = scene_path
	_deliver_payload()

	if not _pending_payload.is_empty():
		_pending_payload = {}


## 把载荷递交给新场景（若其实现了 on_scene_entered）
func _deliver_payload() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.has_method("on_scene_entered"):
		scene.call("on_scene_entered", _pending_payload)


# =============================================================================
# 内部：过场遮罩
# =============================================================================

func _build_transition_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "TransitionLayer"
	_overlay_layer.layer = 128 # 盖在所有游戏 UI 之上
	add_child(_overlay_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = GameConstants.COLOR_DARK_BG
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP # 过场期间吞掉点击，防误操作
	_fade_rect.modulate = Color(1, 1, 1, 0)
	_fade_rect.visible = false
	_overlay_layer.add_child(_fade_rect)

	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_label.add_theme_color_override("font_color", GameConstants.COLOR_TEXT_NORMAL)
	_loading_label.add_theme_font_size_override("font_size", 28)
	_loading_label.visible = false
	_fade_rect.add_child(_loading_label)


func _show_loading(visible: bool, ratio: float) -> void:
	if _loading_label == null:
		return
	if visible and show_loading_progress:
		_loading_label.text = "载入中… %d%%" % int(clampf(ratio, 0.0, 1.0) * 100.0)
	_loading_label.visible = visible and show_loading_progress


func _fade_out() -> void:
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, fade_duration)
	await tween.finished


func _fade_in() -> void:
	if _fade_rect == null:
		return
	_show_loading(false, 1.0)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, fade_duration)
	await tween.finished
	_fade_rect.visible = false


# =============================================================================
# 内部：信号响应
# =============================================================================

func _on_request_scene_change(scene_path: String, payload: Dictionary) -> void:
	change_scene(scene_path, payload)


func _on_request_start_level(level_id: String, difficulty_tier: int) -> void:
	change_to_level(level_id, difficulty_tier)
