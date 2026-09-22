## 关卡商店渲染预览（任务 4.4 · 窗口化自截图验收）
## 用法：godot --path "D:/七傳說/game" res://tools/shop_preview.tscn
extends Node2D

const PREVIEW_SHOT := "res://build/shop_preview.png"

var _shot_taken := false
var _frames := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "关卡内商店预览（4.4）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	title.position = Vector2(16, 8)
	add_child(title)

	var y := 40.0
	var h1 := Label.new()
	h1.text = "① 商品生成（每关 1 次：装备 ×2 + 药水 + 材料，本局金币支付）"
	h1.add_theme_font_size_override("font_size", 12)
	h1.add_theme_color_override("font_color", Color(0.95, 0.6, 0.6))
	h1.position = Vector2(16, y)
	add_child(h1)
	y += 24

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var shop := RunShop.new()
	shop.player = {"gold": 1000.0, "inventory": Inventory.create(8, 5)}
	shop.generate_stock(4, 12, rng)

	var lines := ""
	for entry in shop.stock:
		lines += "  • %s — %d 金币\n" % [entry["label"], int(entry["price"])]
	var s1 := Label.new()
	s1.text = lines
	s1.add_theme_font_size_override("font_size", 11)
	s1.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	s1.position = Vector2(28, y)
	add_child(s1)
	y += 24 + 20 * 4

	var h2 := Label.new()
	h2.text = "② 定价规则（工程侧默认）：稀有度基准 × (1 + 0.5 × iLvl)"
	h2.add_theme_font_size_override("font_size", 12)
	h2.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	h2.position = Vector2(16, y)
	add_child(h2)
	y += 24
	var price_lines := ""
	var order := ["common", "magic", "rare", "epic", "legendary", "set", "mythic", "hidden"]
	for key in order:
		price_lines += "  %s 基准 %d 金（iLvl 12 → %d）\n" % [
			key, int(RunShop.RARITY_PRICE[key]),
			int(RunShop.RARITY_PRICE[key] * (1.0 + 0.5 * 12.0))]
	var s2 := Label.new()
	s2.text = price_lines
	s2.add_theme_font_size_override("font_size", 11)
	s2.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	s2.position = Vector2(28, y)
	add_child(s2)
	y += 24 + 20 * 8

	var h3 := Label.new()
	h3.text = "③ 购买演示（1000 金起）"
	h3.add_theme_font_size_override("font_size", 12)
	h3.add_theme_color_override("font_color", Color(0.6, 0.85, 0.65))
	h3.position = Vector2(16, y)
	add_child(h3)
	y += 24
	var equip_idx := -1
	for i in shop.stock.size():
		if shop.stock[i]["kind"] == "equipment":
			equip_idx = i
			break
	if equip_idx >= 0:
		var price := int(shop.stock[equip_idx]["price"])
		var res := shop.buy(equip_idx)
		var s3 := Label.new()
		s3.text = "  购买「%s」（-%d 金）→ %s；背包 %d 件，余 %d 金" % [
			shop.player["inventory"].get_at(0).get_display_name(),
			price, "成功" if res["ok"] else "失败",
			shop.player["inventory"].count(), int(shop.player["gold"])]
		s3.add_theme_font_size_override("font_size", 11)
		s3.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
		s3.position = Vector2(28, y)
		add_child(s3)
		y += 30

	var h4 := Label.new()
	h4.text = "④ 约束（D2 方案 B）：本局金币本局花，结算时未入包掉落丢失 + 金币扣 50%"
	h4.add_theme_font_size_override("font_size", 12)
	h4.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))
	h4.position = Vector2(16, y)
	add_child(h4)
	y += 24
	var s4 := Label.new()
	s4.text = "  · 商店商品即买即入包（不丢）\n  · 结算：金币材料扣 50%、每关 1 次原地复活\n  · 每关 1 次商店，商品不刷新"
	s4.add_theme_font_size_override("font_size", 11)
	s4.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	s4.position = Vector2(28, y)
	add_child(s4)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and not _shot_taken:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(PREVIEW_SHOT)
		print("[Preview] 已保存 %s（%d×%d）" % [PREVIEW_SHOT, img.get_width(), img.get_height()])
		get_tree().quit()
