## 拾取提示流（步骤 6 · 2026-09-22 · class_name）
##
## 局内掉落拾取的视觉反馈：右上角逐条弹出「金币 +N / 魔石 +N / 已拾取：装备名（稀有度色）
## / 解锁符文：名 / 重复符文 X → 魔石 +N」，
## 每条 2.2s 淡出；最多保留 MAX_TOASTS 条（超出移除最旧）。
## 消费 `EventBus.loot_picked_up(entry: Dictionary)`（LootDrop 拾取时广播）。
class_name PickupToastHUD
extends VBoxContainer

## 单条存活时长（秒）
const LIFE: float = 2.2
## 淡出时长（秒）
const FADE: float = 0.35
## 最多同时显示条数
const MAX_TOASTS: int = 5

const FONT_SIZE: int = 12
const GOLD_COLOR: Color = Color("D9A521")
const MATERIAL_COLOR: Color = Color("4C8BF5")
## 符文提示色（与 `LootDrop.RUNE_COLOR` 同色，地面物件 ↔ 提示条视觉一致）
const RUNE_COLOR: Color = Color("9B6BE8")


## 按 LootDrop 拾取载荷组成提示条。
## 载荷：{type: gold|material|equipment|rune, amount, item_id, rarity, item_level,
##        rune_new?, material_amount?, instance?}
##
## ⚠️ `rune_new` / `material_amount` 由 `PlayerController._pickup_rune()` **写回同一个载荷字典**
##    （依赖 LootDrop 先调 pickup_loot 再 emit loot_picked_up 的顺序）。缺失时默认 `true`
##    ⇒ 退化成「解锁符文：X」文案，不会崩。
func spawn(entry: Dictionary) -> void:
	var text := ""
	var color := GameConstants.UI_TEXT_BRIGHT
	var t := str(entry.get("type", ""))
	match t:
		"gold":
			text = "金币 +%d" % int(entry.get("amount", 1))
			color = GOLD_COLOR
		"material":
			text = "魔石 +%d" % int(entry.get("amount", 1))
			color = MATERIAL_COLOR
		"rune":
			var rn := _rune_name(str(entry.get("item_id", "")))
			if bool(entry.get("rune_new", true)):
				text = "解锁符文：%s" % rn
			else:
				text = "重复符文 %s → 魔石 +%d" % [rn, int(entry.get("material_amount", 0))]
			color = RUNE_COLOR
		"equipment":
			var item_id := str(entry.get("item_id", ""))
			var tpl: EquipmentData = ConfigLoader.get_equipment_template(item_id)
			var nm := tpl.display_name if tpl != null else item_id
			var r := int(entry.get("rarity", GameConstants.Rarity.COMMON))
			# B5-4：特殊档加来源前缀，玩家一眼区分深渊 / 塔专属掉落
			match r:
				GameConstants.Rarity.SPECIAL_ABYSS:
					text = "【深渊】已拾取：%s" % nm
				GameConstants.Rarity.SPECIAL_TOWER:
					text = "【镇塔】已拾取：%s" % nm
				_:
					text = "已拾取：%s" % nm
			color = GameConstants.rarity_color(r)
		_:
			return
	_push(text, color)


## 符文显示名（缺表 / 空 id 时回退 id 本身，避免提示条出现空文案）
func _rune_name(rune_id: String) -> String:
	if ConfigLoader.runes is Dictionary and ConfigLoader.runes.has(rune_id):
		var r: Dictionary = ConfigLoader.runes[rune_id]
		return str(r.get("display_name", rune_id))
	return rune_id


func _push(text: String, color: Color) -> void:
	# 上限：移除最旧一条
	while get_child_count() >= MAX_TOASTS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()

	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.051, 0.063, 0.82)
	sb.set_border_width_all(1)
	sb.border_color = Color("3A424F")
	sb.set_corner_radius_all(0)
	row.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 6)
	mg.add_theme_constant_override("margin_right", 6)
	mg.add_theme_constant_override("margin_top", 2)
	mg.add_theme_constant_override("margin_bottom", 2)
	mg.add_child(lbl)
	row.add_child(mg)
	add_child(row)

	# 2.2s 后淡出并移除
	var tw := create_tween()
	tw.tween_interval(LIFE)
	tw.tween_property(row, "modulate:a", 0.0, FADE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(row):
			row.queue_free())
