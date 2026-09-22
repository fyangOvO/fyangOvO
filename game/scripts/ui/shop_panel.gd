## 关卡内商店面板（任务 4.4 · class_name）
##
## 商品列表（名称 + 价格 + 购买按钮）；点购买 → RunShop.buy →
## 金币扣除 + 装备入包；金币不足按钮置灰。
class_name ShopPanel
extends Control

signal bought(index: int)

var _shop: RunShop


## 绑定商店并刷新列表（战斗层调用）
func open_shop(shop: RunShop) -> void:
	_shop = shop
	_refresh()


func _refresh() -> void:
	for child in get_children():
		child.queue_free()
	if _shop == null:
		return
	var row_h := 56
	for i in _shop.stock.size():
		var entry: Dictionary = _shop.stock[i]
		var row := Panel.new()
		row.custom_minimum_size = Vector2(0, row_h - 8)
		row.position = Vector2(8, 8 + i * row_h)
		row.size = Vector2(size.x - 16, row_h - 8)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.09, 0.12)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.border_color = _kind_color(str(entry["kind"]))
		row.add_theme_stylebox_override("panel", sb)
		add_child(row)
		var label := Label.new()
		label.text = "%s    %s 金币" % [entry["label"], str(int(entry["price"]))]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.9))
		label.position = Vector2(14, 10)
		row.add_child(label)
		var btn := Button.new()
		var can_buy := not _shop.player.is_empty() \
			and float(_shop.player.get("gold", 0.0)) >= float(entry["price"])
		btn.text = "购买" if can_buy else "金币不足"
		btn.disabled = not can_buy
		btn.position = Vector2(size.x - 118, 12)
		btn.custom_minimum_size = Vector2(100, 26)
		row.add_child(btn)
		var idx := i
		btn.pressed.connect(func() -> void:
			var res := _shop.buy(idx)
			if res["ok"]:
				bought.emit(idx)
			_refresh())


func _kind_color(kind: String) -> Color:
	match kind:
		"equipment": return Color(0.75, 0.5, 0.3)
		"potion": return Color(0.5, 0.8, 0.5)
		"material": return Color(0.6, 0.7, 0.9)
	return Color(0.6, 0.6, 0.6)
