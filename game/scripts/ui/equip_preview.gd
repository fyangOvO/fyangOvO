## 装备面板角色预览（纸娃娃 · 装备可视化第1期延伸）
##
## 职责：在装备面板 SubViewport 内渲染「职业身体 + 五槽防具分件」的静态穿甲效果。
## 与局内共用同一套素材解析与部位级锚点表（`PlayerController.ARMOR_ANCHOR_OFFSET`）：
##   · 身体：`EnemyBase.resolve_character_set(<class>)` idle e 首帧（含稀有度 tint 变体）
##   · 分件：`pack/armor/<item_id>/armor_<item_id>_idle_e_01.png`（含 _tint_<rarity> 变体）
## 本组件只读展示，不改装备状态；武器暂不渲染（面板已有文字/图标，锚点位置后续可加）。
## 像素铁律：192 画布 → 0.5× 整数缩放（96px 展示）；Nearest 过滤。
class_name EquipPreview
extends Node2D

## 五槽部位 key（与 PlayerController.ARMOR_ANCHOR_OFFSET 列一致）
const SLOT_KEYS: Array[String] = ["head", "chest", "gloves", "legs", "boots"]
## 装备槽位 → 部位 key（防具槽专列；武器/饰品不入预览）
const SLOT_TO_KEY := {
	GameConstants.EquipSlot.HELM: "head",
	GameConstants.EquipSlot.CHEST: "chest",
	GameConstants.EquipSlot.GLOVES: "gloves",
	GameConstants.EquipSlot.LEGS: "legs",
	GameConstants.EquipSlot.BOOTS: "boots",
}
## 预览缩放：192 画布 → 96px（0.5×，整数倍缩放合法）
const PREVIEW_SCALE: float = 0.5

var _body: Sprite2D = null
var _pieces: Dictionary = {}  # slot_key → Sprite2D


func _ready() -> void:
	_body = Sprite2D.new()
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.centered = true
	add_child(_body)
	for key in SLOT_KEYS:
		var sp := Sprite2D.new()
		sp.name = "Piece_%s" % key
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.centered = true
		sp.visible = false
		add_child(sp)
		_pieces[key] = sp


## 渲染穿甲效果：class_id + 当前装备（六格数组）。tier 由防具最高稀有度计算（同局内外观档）。
func render(class_id: String, equipped: Array) -> void:
	var tier := _top_armor_rarity(equipped)
	_load_body(class_id, tier)
	for key in SLOT_KEYS:
		_load_piece(class_id, key, _item_for(key, equipped), tier)


## 防具槽最高稀有度（外观档换色依据；-1 = 未穿戴/默认职业色）
func _top_armor_rarity(equipped: Array) -> int:
	var top := -1
	for item in equipped:
		if item == null or item.template == null:
			continue
		if item.rarity > top and item.template.slot >= GameConstants.EquipSlot.HELM \
				and item.template.slot <= GameConstants.EquipSlot.BOOTS:
			top = item.rarity
	return top


func _item_for(key: String, equipped: Array):
	for item in equipped:
		if item == null or item.template == null:
			continue
		if SLOT_TO_KEY.get(item.template.slot, "") == key:
			return item
	return null


## 身体：idle e 首帧；稀有度 > common 时优先解析 <class>_tint_<rarity> 变体集（缺则保持默认色）。
func _load_body(class_id: String, tier: int) -> void:
	var art := EnemyBase.resolve_character_set(class_id)
	if tier > GameConstants.Rarity.COMMON and tier < GameConstants.RARITY_KEYS.size():
		var tint := EnemyBase.resolve_character_set(
			"%s_tint_%s" % [class_id, GameConstants.RARITY_KEYS[tier]])
		if tint["ok"]:
			art = tint
	var tex: Texture2D = null
	var canvas := 192.0
	if art["ok"]:
		var clips: Dictionary = art.get("clips", {})
		var idle: Dictionary = clips.get(EnemyBase.ANIM_IDLE, {})
		var frames: Array = idle.get(EnemyBase.DIR_E, [])
		if frames.is_empty():
			frames = art.get("frames", [])
		if frames.size() > 0:
			tex = frames[0]
		canvas = maxf(float(art.get("canvas", 0.0)), 1.0)
	_body.texture = tex
	if tex == null:
		_body.visible = false
		return
	_body.visible = true
	# centered + offset.y = -canvas/2 ⇒ 纹理底边落在本节点原点（= 脚底）
	_body.offset = Vector2(0.0, -canvas * 0.5)
	_body.scale = Vector2.ONE * (PREVIEW_SCALE * 192.0 / canvas)


## 分件：pack/armor/<id>/armor_<id>_idle_e_01.png；锚点偏移查部位级表（同局内，y 偏移统一 0）。
func _load_piece(class_id: String, key: String, item, tier: int) -> void:
	var sp: Sprite2D = _pieces.get(key)
	if sp == null:
		return
	if item == null:
		sp.visible = false
		return
	var dir_id: String = item.template.id
	if tier > GameConstants.Rarity.COMMON and tier < GameConstants.RARITY_KEYS.size():
		dir_id = "%s_tint_%s" % [dir_id, GameConstants.RARITY_KEYS[tier]]
	var path := "res://assets/pack/armor/%s/armor_%s_idle_e_01.png" % [dir_id, dir_id]
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		sp.visible = false
		return
	sp.texture = tex
	sp.visible = true
	var off: Vector2 = PlayerController.ARMOR_ANCHOR_OFFSET \
		.get(class_id, {}).get("e", {}).get(key, Vector2.ZERO)
	sp.offset = Vector2(off.x, off.y - 96.0)
	sp.scale = Vector2.ONE * PREVIEW_SCALE
	sp.position = Vector2.ZERO
