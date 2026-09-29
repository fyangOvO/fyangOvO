## 敵方投射物（W5-1 · inline 最小可行版本）
##
## 為什麼獨立寫：主理人 2026-09-29 工單明確「不要新建投射物 scene、不要碰
## 投射物管線」。玩家側投射物管線（skill_controller）是成熟系統但本次
## 不允許複用，因此獨立寫一個極簡版本：直線飛行 + 命中偵測 + 超時自毀。
##
## 與玩家側管線**有意義差異**（這是設計取捨不是 bug）：
##   - 不走玩家 buff / 暴擊鏈
##   - **預設**不走毒/感電等元素異常施加（_attack_player 的那條鏈會施加異常，本投射物
##     故意不施加，否則敵方一個遠程怪就能穩定上毒）
##   - 只發 damage_dealt 總線事件 + 顯式回呼玩家 take_damage
##
## 【2026-09-29 · W5-5】BOSS 火球是**唯二**需要「命中給燃燒」的投射物，所以加兩個
## **可選**參數而不是改預設值：
##   · `visual_id`        —— 指定 `FxTable` 特效 id（如 `bolt_fire`）當飛行視覺；
##                          留空 = 沿用金黃占位色塊（遠程小怪行為零變化）
##   · `ailment_element`  —— 命中時施加的元素異常（如 `"fire"`）；
##                          留空 = 不施加（維持 W5-1「遠程怪不上毒」的原裁定）
##
## 命中邏輯：與玩家組測距 < 8px 算命中；命中或超時或離屏自毀。
## 命中**只觸發一次**（避免「每幀重疊」）。
class_name EnemyProjectile
extends Node2D

var _dir: Vector2 = Vector2.RIGHT
var _speed: float = 180.0
var _damage: float = 0.0
var _element: String = "physical"
var _source: Node = null
## 剩餘壽命（秒）：超過即自毀（防止怪消失後投射物飄向無窮遠）
var _life: float = 2.0
## 是否已命中（命中後立即 queue_free；此旗標阻止「同一幀多次命中」）
var _hit: bool = false
## 視覺 sprite（金黃占位色塊；`visual_id` 為空時使用）
var _body: Sprite2D = null
## 序列幀視覺（`visual_id` 非空且解析成功時使用；否則為 null）
var _fx: FxSprite = null
## 可選：`FxTable` 特效 id（空 = 占位色塊）
var _visual_id: String = ""
## 可選：命中時施加的元素異常（空 = 不施加）
var _ailment_element: String = ""


## 設定飛行參數。`life` 由呼叫方傳入，預設 2.0 秒。
##
## `visual_id` / `ailment_element` 為 W5-5 新增的**可選**參數，預設空串 ⇒
## 既有呼叫點（`_attack_kiter`）不傳即與改動前逐位一致。
func setup(direction: Vector2, speed: float, damage: float,
		element: String, source: Node, life: float = 2.0,
		visual_id: String = "", ailment_element: String = "") -> void:
	if direction.length_squared() > 0.0:
		_dir = direction.normalized()
	_speed = maxf(speed, 1.0)
	_damage = damage
	_element = element
	_source = source
	_life = life
	_visual_id = visual_id
	_ailment_element = ailment_element


func _ready() -> void:
	# 优先序列帧视觉：`FxTable` 查不到（未知 id / 缺贴图）时**静默回退占位色块**，
	# 不崩、不刷屏 —— 与 `FxTable.spawn` 的「未知 id 只警告返回 null」同口径。
	if not _visual_id.is_empty():
		var spec := FxTable.spec(_visual_id)
		var tex := FxTable.texture_for(_visual_id)
		if not spec.is_empty() and tex != null:
			var fx := FxSprite.new()
			if fx.setup(spec, tex):
				fx.rotation = _dir.angle()
				add_child(fx)
				_fx = fx
	if _fx == null:
		_body = Sprite2D.new()
		_body.texture = _make_placeholder()
		_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_body.centered = true
		add_child(_body)


func _physics_process(delta: float) -> void:
	if _hit:
		return
	position += _dir * _speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# 命中檢測：與玩家組測距 < 8px
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group(&"player")
	if player == null or not is_instance_valid(player) or not (player is Node2D):
		return
	var p2d := player as Node2D
	if position.distance_to(p2d.global_position) > 8.0:
		return
	_hit = true
	# ⚠️ `_source` 可能是**已释放**的发射者（BOSS 被击杀后，它发射的火球还在飞）。
	#    直接把它传进 `take_damage(amount: float, source: Node)` 会因类型不符抛
	#    `SCRIPT ERROR: ... previously freed ...`（2026-09-29 实测）。所以先判活。
	var src: Node = _source if is_instance_valid(_source) else null
	if player.has_method("take_damage"):
		player.take_damage(_damage, src)
	EventBus.damage_dealt.emit(player, _damage, false, _element)
	# W5-5：可選元素異常（BOSS 火球 → 燃燒）。空串 ⇒ 完全不進這條分支。
	if not _ailment_element.is_empty() and player.has_method("apply_ailment_from_element"):
		player.apply_ailment_from_element(_ailment_element, src)
	queue_free()


## 8×8 金黃占位色塊（與怪占位色塊同一視覺語言；待美術補精靈時換）
func _make_placeholder() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color("F5D77A"))
	return ImageTexture.create_from_image(img)