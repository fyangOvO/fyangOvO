## 敵方投射物（W5-1 · inline 最小可行版本）
##
## 為什麼獨立寫：主理人 2026-09-29 工單明確「不要新建投射物 scene、不要碰
## 投射物管線」。玩家側投射物管線（skill_controller）是成熟系統但本次
## 不允許複用，因此獨立寫一個極簡版本：直線飛行 + 命中偵測 + 超時自毀。
##
## 與玩家側管線**有意義差異**（這是設計取捨不是 bug）：
##   - 不走玩家 buff / 暴擊鏈
##   - 不走毒/感電等元素異常施加（_attack_player 的那條鏈會施加異常，本投射物
##     故意不施加，否則敵方一個遠程怪就能穩定上毒）
##   - 只發 damage_dealt 總線事件 + 顯式回呼玩家 take_damage
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
## 視覺 sprite（金黃占位色塊；待美術補再換）
var _body: Sprite2D = null


## 設定飛行參數。`life` 由呼叫方傳入，預設 2.0 秒。
func setup(direction: Vector2, speed: float, damage: float,
		element: String, source: Node, life: float = 2.0) -> void:
	if direction.length_squared() > 0.0:
		_dir = direction.normalized()
	_speed = maxf(speed, 1.0)
	_damage = damage
	_element = element
	_source = source
	_life = life


func _ready() -> void:
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
	if player.has_method("take_damage"):
		player.take_damage(_damage, _source)
	EventBus.damage_dealt.emit(player, _damage, false, _element)
	queue_free()


## 8×8 金黃占位色塊（與怪占位色塊同一視覺語言；待美術補精靈時換）
func _make_placeholder() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color("F5D77A"))
	return ImageTexture.create_from_image(img)