## BOSS 觉醒立绘卡（步骤 8C · 2026-09-23 · class_name）
##
## DNF 觉醒立绘风格的全屏展示卡：暗幕渐入 → 立绘大图缩放淡入 + 斜向扫光 →
## BOSS 名 + 阶段提示打出 → 停留 → 整体渐隐 → 回调开战。
## 动态全部由代码实现（Tween + CPUParticles2D），不依赖动画素材。
##
## 用法（level_scene 触发时）：
##   BossAwakenCard.awaken(get_tree(), boss_id, display_name, phase_count, callable)
##   卡片结束（约 2.4s）后调用 callable，由关卡层解除 BOSS 冻结并播放觉醒音效。
class_name BossAwakenCard
extends CanvasLayer

## 觉醒立绘素材目录（image_gen 生成，512×768 竖版 2:3）
const ART_DIR: String = "res://assets/ui/boss/awaken_%s.png"
const ART_FALLBACK: String = "res://assets/sprites/enemies/boss_bone_tyrant.png"

## 时序（秒）：暗幕 → 立绘+扫光 → 名字 → 停留 → 渐隐
const T_DIM_IN := 0.35
const T_ART_IN := 0.45
const T_NAME_IN := 0.30
const T_HOLD := 0.65
const T_OUT := 0.45

## 粒子按 BOSS 主题：骨暴君 = 幽蓝鬼火 / 熔心之主 = 橙红余烬
const PARTICLE_BONE := {
	"count": 40, "color": Color(0.42, 0.80, 1.0, 0.85),
	"color2": Color(0.28, 0.42, 1.0, 0.0),
}
const PARTICLE_EMBER := {
	"count": 60, "color": Color(1.0, 0.62, 0.24, 0.9),
	"color2": Color(1.0, 0.25, 0.12, 0.0),
}

var _on_finished: Callable = Callable()


## 工厂：创建觉醒卡并挂到 tree（CanvasLayer 顶层，覆盖全屏 UI）。
static func awaken(parent: Node, boss_id: String, display_name: String,
		phase_count: int, on_finished: Callable) -> BossAwakenCard:
	var card := BossAwakenCard.new()
	card._on_finished = on_finished
	card.name = "BossAwakenCard"
	parent.add_child(card)
	card._build(boss_id, display_name, phase_count)
	return card


func _build(boss_id: String, display_name: String, phase_count: int) -> void:
	# --- 全屏 UI 容器 ---
	# ⚠️ CanvasLayer 不是 Control：其下子 Control 的 anchors 无法从非 Control 父
	#    解析出布局尺寸（PRESET_FULL_RECT 会静默退化成 0×0，整卡看不见）。
	#    所以先放一个**手动给定 640×360** 的 Control 容器，UI 元素挂它下面。
	var ui := Control.new()
	ui.name = "UIContainer"
	ui.position = Vector2.ZERO
	ui.size = Vector2(640.0, 360.0)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)

	# --- 全屏暗幕 ---
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dim)

	# --- 立绘大图（keep aspect covered，充满画面居中裁切）---
	var art := TextureRect.new()
	art.name = "AwakenArt"
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _load_art(boss_id)
	art.modulate = Color(1.0, 1.0, 1.0, 0.0)
	art.pivot_offset = Vector2(320.0, 180.0)
	art.scale = Vector2(1.12, 1.12)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(art)

	# --- 斜向扫光条 ---
	var scan := ColorRect.new()
	scan.name = "ScanLight"
	scan.color = Color(1.0, 0.95, 0.85, 0.28)
	scan.size = Vector2(190.0, 46.0)
	scan.position = Vector2(-240.0, 96.0)
	scan.rotation = -0.42
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(scan)

	# --- 顶部信息区（BOSS 名 + 阶段提示）---
	var info := ColorRect.new()
	info.name = "InfoBar"
	info.color = Color(0.03, 0.04, 0.06, 0.0)
	info.position = Vector2(0.0, 26.0)
	info.size = Vector2(640.0, 84.0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(info)

	var name_label := Label.new()
	name_label.name = "BossName"
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", GameConstants.COLOR_ACCENT_GOLD)
	name_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)

	var phase_label := Label.new()
	phase_label.name = "PhaseHint"
	phase_label.text = "第 1 階段 · 共 %d 階段" % maxi(phase_count, 1)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 12)
	phase_label.add_theme_color_override("font_color", GameConstants.COLOR_TEXT_BRIGHT)
	phase_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	phase_label.offset_top = 46.0
	phase_label.offset_bottom = 84.0
	phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(phase_label)

	# --- 粒子（按 BOSS 主题）---
	var parts := CPUParticles2D.new()
	parts.name = "Particles"
	parts.position = Vector2(320.0, 180.0)
	parts.emitting = false
	parts.one_shot = false
	parts.amount = 50
	parts.lifetime = 1.1
	parts.explosiveness = 0.0
	parts.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	parts.emission_sphere_radius = 150.0
	parts.direction = Vector2(0.0, -1.0)
	parts.spread = 40.0
	parts.gravity = Vector2(0.0, -36.0)
	parts.initial_velocity_min = 26.0
	parts.initial_velocity_max = 96.0
	parts.scale_amount_min = 1.6
	parts.scale_amount_max = 3.2
	parts.color = PARTICLE_BONE["color"]
	parts.color_ramp = _make_ramp(boss_id)
	add_child(parts)  # 粒子是 Node2D，直接挂 CanvasLayer（无需 UI 容器）

	# --- 动画时序：_process 手动驱动（无 Tween）---
	# ⚠️ 教训（2026-09-23）：链式 Tween 与分阶段 await Tween 对 art.modulate
	#    都会卡在 ~0.13 不动（dim 却正常）——Godot 该环境下 Tween 不可靠。
	#    改为 _process 里按 _anim_t 累进推进，逐帧写属性，完全可控。
	_art = art
	_dim = dim
	_scan = scan
	_info = info
	_name_label = name_label
	_phase_label = phase_label
	_parts = parts
	_anim_t = 0.0
	set_process(true)


const T_GAP_1 := 0.12
const T_GAP_2 := 0.28
# 总时长 = 0.35 + 0.12 + 0.45 + 0.28 + 0.30 + 0.65 + 0.45 = 2.60s
#    （验证窗口 2.2–2.8s，见 verify_boss_awaken8c C 段）


var _art: TextureRect
var _dim: ColorRect
var _scan: ColorRect
var _info: ColorRect
var _name_label: Label
var _phase_label: Label
var _parts: CPUParticles2D
var _anim_t: float = -1.0
## 阶段边界（秒）
const P1_DIM_END := T_DIM_IN                              # 0.35
const P2_ART_END := P1_DIM_END + T_GAP_1 + T_ART_IN      # 0.92
const P3_NAME_END := P2_ART_END + T_GAP_2 + T_NAME_IN    # 1.50
const P4_HOLD_END := P3_NAME_END + T_HOLD                # 2.15
const P5_OUT_END := P4_HOLD_END + T_OUT                  # 2.60


func _process(delta: float) -> void:
	if _anim_t < 0.0:
		return
	_anim_t += delta
	var t := _anim_t
	# ① 暗幕渐入（0 → P1_DIM_END）
	var dim_a := clampf(t / P1_DIM_END, 0.0, 1.0) * 0.72
	_dim.color.a = dim_a
	_info.color.a = 0.34 * dim_a / 0.72
	# ② 立绘淡入 + 缩放（P1_DIM_END + T_GAP_1 → P2_ART_END）
	var art_t := clampf((t - P1_DIM_END - T_GAP_1) / T_ART_IN, 0.0, 1.0)
	if art_t > 0.0:
		_art.modulate.a = art_t
		_art.scale = Vector2.ONE.lerp(Vector2(1.12, 1.12), 1.0 - art_t)
		if not _parts.emitting:
			_parts.emitting = true
	# 扫光平移（与立绘同步，0.62s 扫过）
	var scan_t := clampf((t - P1_DIM_END - T_GAP_1) / 0.62, 0.0, 1.0)
	_scan.position.x = lerpf(-240.0, 820.0, scan_t)
	# ③ BOSS 名 + 阶段提示（P2_ART_END + T_GAP_2 → P3_NAME_END）
	var name_t := clampf((t - P2_ART_END - T_GAP_2) / T_NAME_IN, 0.0, 1.0)
	if name_t > 0.0:
		_name_label.modulate.a = name_t
		_phase_label.modulate.a = name_t
	# ④ 停留（P3_NAME_END → P4_HOLD_END）：无操作
	# ⑤ 整体渐隐（P4_HOLD_END → P5_OUT_END）
	var out_t := clampf((t - P4_HOLD_END) / T_OUT, 0.0, 1.0)
	if out_t > 0.0:
		_parts.emitting = false
		_art.modulate.a = 1.0 - out_t
		_name_label.modulate.a = 1.0 - out_t
		_phase_label.modulate.a = 1.0 - out_t
		_scan.modulate.a = 1.0 - out_t
		_dim.color.a = 0.72 * (1.0 - out_t)
		_info.color.a = 0.34 * (1.0 - out_t)
	if t >= P5_OUT_END:
		_finish()


func _finish() -> void:
	var cb := _on_finished
	queue_free()
	if cb.is_valid():
		cb.call()


## 立绘加载：BOSS 觉醒图优先，缺则回退到敌怪精灵（保证卡不空）
func _load_art(boss_id: String) -> Texture2D:
	var path := ART_DIR % boss_id
	if ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path)
		if res is Texture2D:
			return res
	if ResourceLoader.exists(ART_FALLBACK):
		var fb: Variant = ResourceLoader.load(ART_FALLBACK)
		if fb is Texture2D:
			return fb
	return null


## 粒子渐变色带：幽蓝鬼火 / 橙红余烬（尾部 alpha 归零）
func _make_ramp(boss_id: String) -> Gradient:
	var g := Gradient.new()
	if boss_id.begins_with("boss_ember"):
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([
			PARTICLE_EMBER["color"], PARTICLE_EMBER["color2"], Color(0.0, 0.0, 0.0, 0.0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([
			PARTICLE_BONE["color"], PARTICLE_BONE["color2"], Color(0.0, 0.0, 0.0, 0.0)])
	return g


## 验证钩子：动画总时长（秒，供 verify 断言时序）
func total_duration() -> float:
	return T_DIM_IN + 0.12 + T_ART_IN + 0.28 + T_NAME_IN + T_HOLD + T_OUT
