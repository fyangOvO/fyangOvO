## 玩家 HUD 血条（阶段 2 · 任务 2.6）
##
## 美术规范 0.7 v1.4 附录「UI 元件」：高 16px；底槽 `#14171C`；血量 `#C42B2B`→`#8C1A1F`
## 渐变；1px `#0B0D10` 描边；护盾叠 `#3A5FB0`（护盾值盖在血量上方）。
## 另加「顶部高光」：血量上缘 1px 亮线（血系亮色 `#E8573F`，压低暗背景下的可读性）。
##
## 【2026-09-21 用戶像素素材包接入】
## 用戶原話「ui素材優先用這裡面的」。包的 `bar_hp_160x16.png` / `bar_mp_160x16.png`
## 是「凹槽 + 金屬端帽 + 亮紅填充」的整條貼圖（160×16）。接法：
##   · **9-slice 橫向**：兩端各保留 `BAR_CAP`=5px 金屬端帽，**中段是純平色塊**
##     ⇒ 拉伸中段**無損**（不是非整數縮放，是包 README §四自己建議的用法）。
##   · **填充比例靠代碼裁切**：未填充段以 `DRAIN_MODULATE` 壓暗讀成「空槽」，
##     填充段原色繪製到 `ratio` 寬度 —— 這也是包 README §四的原話建議。
##   · 貼圖缺失 ⇒ **完整回退**到原本的純代碼繪製（漸變 + draw_rect），行為不變。
##
## 绑定：target 提供 get_current_hp / get_max_hp / get_shield（HealthComponent 宿主接口）。
## 轮询刷新（每帧 queue_redraw）：实体数量少，比事件订阅简单可靠。
class_name HealthBar
extends Control

## 邏輯貼圖名（`UISkin.TEX` 的鍵）。血條用 `"bar_hp"`；法力條用 `"bar_mp"`。
@export var bar_texture_name: String = "bar_hp"

## 綁定實體（PlayerController 或任意实现生命契约的宿主；NodePath 解析）
@export var target_path: NodePath = NodePath()
var target: Node = null

## 值类型（步骤 6）："hp" = 生命（读 get_current_hp/get_max_hp/get_shield）；
## "mana" = 法力（读 target.get_mana_pool().current/maximum，无护盾层）。
@export var value_kind: String = "hp"

## 血量条高度（px）。玩家 16px（美术规范）。
@export var bar_height: int = GameConstants.UI_HP_BAR_HEIGHT_PLAYER

## 是否显示 "当前/最大" 文本（玩家 HUD 开；怪物头顶关）
@export var show_text: bool = true

## 是否绘制护盾叠层
@export var show_shield: bool = true

## 9-slice 端帽寬度（px）。源貼圖 160×16，兩端各 5px 是金屬端帽。
const BAR_CAP: float = 5.0
## 源貼圖寬度（px）。用於切片源矩形計算。
const BAR_SRC_W: float = 160.0
## 未填充段的壓暗係數：讓「空槽」讀得出來，同時保留端帽與凹槽的形。
const DRAIN_MODULATE: Color = Color(0.34, 0.36, 0.42)

var _grad_tex: GradientTexture2D = null
var _bar_tex: Texture2D = null


func _ready() -> void:
	custom_minimum_size = Vector2(0, bar_height)
	if target_path != null and not target_path.is_empty():
		target = get_node_or_null(target_path)
	_bar_tex = UISkin.texture(bar_texture_name)
	_grad_tex = GradientTexture2D.new()
	var grad := Gradient.new()
	if value_kind == "mana":
		grad.colors = [GameConstants.UI_MP_BAR_GRADIENT_FROM, GameConstants.UI_MP_BAR_GRADIENT_TO]
	else:
		grad.colors = [GameConstants.UI_HP_BAR_GRADIENT_FROM, GameConstants.UI_HP_BAR_GRADIENT_TO]
	_grad_tex.gradient = grad
	_grad_tex.fill = GradientTexture2D.FILL_LINEAR
	_grad_tex.fill_from = Vector2(0.0, 0.0)
	_grad_tex.fill_to = Vector2(1.0, 0.0)
	_grad_tex.width = 64
	_grad_tex.height = 16


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if target == null:
		return
	var cur: float
	var max_v: float
	var sh: float = 0.0
	var sh_ratio: float = 0.0
	if value_kind == "mana":
		var pool: ManaPool = target.get_mana_pool() if target.has_method("get_mana_pool") else null
		if pool == null:
			return
		cur = pool.current
		max_v = pool.maximum
	else:
		cur = _read_float("get_current_hp")
		max_v = _read_float("get_max_hp")
		if show_shield:
			sh = _read_float("get_shield")
			sh_ratio = clampf(sh / max_v, 0.0, 1.0)
	if max_v <= 0.0:
		return
	var ratio := clampf(cur / max_v, 0.0, 1.0)

	var w := size.x
	var h := float(bar_height)
	var full := Rect2(0.0, 0.0, w, h)

	if _bar_tex != null:
		_draw_textured(w, h, ratio, sh_ratio)
	else:
		_draw_fallback(w, h, ratio, sh_ratio)

	# 文本（兩條路徑共用）
	if show_text:
		var label := "%d / %d" % [int(ceil(cur)), int(max_v)]
		var font := get_theme_default_font()
		var font_size := 11
		var pos := Vector2(4.0, (h - font_size) * 0.5 + font_size)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
			GameConstants.UI_TEXT_BRIGHT)


## 素材包貼圖路徑：整條以暗調制畫成「空槽」，再按 ratio 原色畫出填充段。
func _draw_textured(w: float, h: float, ratio: float, sh_ratio: float) -> void:
	# ① 空槽（整條，壓暗）
	_bar_slice(Rect2(0.0, 0.0, w, h), DRAIN_MODULATE)
	# ② 填充段（原色，只到 ratio 寬）。**小於一個端帽寬時整段略過**，避免畫出畸形切片。
	var fill_w := w * ratio
	if fill_w >= BAR_CAP * 2.0:
		_bar_slice(Rect2(0.0, 0.0, fill_w, h), Color.WHITE)
	# ③ 護盾疊層（沿用純色，畫在填充之上）
	if sh_ratio > 0.0:
		var sh_w := w * sh_ratio
		if sh_w > 0.0:
			draw_rect(Rect2(BAR_CAP, 1.0, maxf(sh_w - BAR_CAP, 0.0), h - 2.0),
				GameConstants.UI_SHIELD_COLOR)


## 把 `_bar_tex` 以「端帽固定 + 中段拉伸」畫進 `dst`。
## 中段是**純平色塊** ⇒ 橫向拉伸無損；端帽保持 1:1 像素。
func _bar_slice(dst: Rect2, mod: Color) -> void:
	var tex_h := float(_bar_tex.get_height())
	var c := minf(BAR_CAP, dst.size.x * 0.5)
	# 左端帽
	draw_texture_rect_region(_bar_tex,
		Rect2(dst.position.x, dst.position.y, c, dst.size.y),
		Rect2(0.0, 0.0, c, tex_h), mod)
	# 中段（可拉伸）
	var mid_w := dst.size.x - c * 2.0
	if mid_w > 0.0:
		draw_texture_rect_region(_bar_tex,
			Rect2(dst.position.x + c, dst.position.y, mid_w, dst.size.y),
			Rect2(BAR_CAP, 0.0, BAR_SRC_W - BAR_CAP * 2.0, tex_h), mod)
	# 右端帽
	draw_texture_rect_region(_bar_tex,
		Rect2(dst.position.x + dst.size.x - c, dst.position.y, c, dst.size.y),
		Rect2(BAR_SRC_W - BAR_CAP, 0.0, BAR_CAP, tex_h), mod)


## 純代碼繪製（**貼圖缺失時的回退**，行為與接入素材包之前完全一致）。
func _draw_fallback(w: float, h: float, ratio: float, sh_ratio: float) -> void:
	var full := Rect2(0.0, 0.0, w, h)
	# 1) 底槽
	draw_rect(full, GameConstants.UI_HP_BAR_BG)
	# 2) 血量（渐变；护盾层占位，血量画在护盾之上——护盾更「贴近皮肤」）
	var hp_rect := Rect2(1.0, 1.0, maxf((w - 2.0) * ratio, 0.0), h - 2.0)
	if hp_rect.size.x > 0.0 and _grad_tex != null:
		draw_texture_rect(_grad_tex, hp_rect, false)
	# 3) 护盾叠层（叠加在血量上，按 shield/max 比例）
	if sh_ratio > 0.0:
		var sh_rect := Rect2(1.0, 1.0, maxf((w - 2.0) * sh_ratio, 0.0), h - 2.0)
		draw_rect(sh_rect, GameConstants.UI_SHIELD_COLOR)
	# 4) 顶部高光（上缘 1px 亮线，覆盖整条；血系亮红 / 法力亮蓝）
	var hi := Color("6E9BE8") if value_kind == "mana" else Color("E8573F")
	draw_rect(Rect2(1.0, 1.0, w - 2.0, 1.0), hi)
	# 5) 描边（外框 1px）
	draw_rect(full, GameConstants.UI_HP_BAR_OUTLINE, false, 1.0)


## 优先走方法接口，缺失则回退 get 属性（EnemyBase 简易生命兼容）
func _read_float(method: String) -> float:
	if target != null and target.has_method(method):
		return float(target.call(method))
	return 0.0
