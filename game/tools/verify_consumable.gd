## 工具：verify_consumable.gd（步骤 8A · 消耗品闭环验证；headless）
##
## 用法：godot --headless --path "D:/七傳說/game" res://tools/verify_consumable.tscn
## 覆盖：A 消耗品数据表 / B 商店购买入包 / C 掉落 roll / D 玩家使用回血回蓝+冷却 /
##       E 存档往返 / F 药水图标贴图 / G QuickSlotUI 结构。
extends Node

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const QUICK_SLOT_SCRIPT := preload("res://scripts/ui/quick_slot.gd")

var _fail: int = 0


func _ready() -> void:
	print("===== 步骤 8A 消耗品闭环 验证 =====")
	_run()


func _run() -> void:
	await get_tree().process_frame

	# A. 数据表
	_ok("消耗品表已加载（>=2）", ConfigLoader.consumables.size() >= 2)
	_ok("生命药水配置合法",
		ConfigLoader.consumables.has("life_potion")
		and str(ConfigLoader.consumables["life_potion"].get("kind", "")) == "heal_hp"
		and float(ConfigLoader.consumables["life_potion"].get("percent", 0.0)) > 0.0)
	_ok("法力药水配置合法",
		ConfigLoader.consumables.has("mana_potion")
		and str(ConfigLoader.consumables["mana_potion"].get("kind", "")) == "heal_mp")

	# B. 商店购买入包（修假闭环：此前只扣款、物品消失）
	var shop := RunShop.new()
	shop.player = {"gold": 200.0, "inventory": Inventory.create(8, 5), "consumables": {}}
	shop.generate_stock(5, 1)
	var potion_idx := -1
	for i in shop.stock.size():
		if str(shop.stock[i].get("kind", "")) == "potion":
			potion_idx = i
			break
	_ok("商店药水在架", potion_idx >= 0)
	if potion_idx >= 0:
		var before: int = int(shop.player["consumables"].get("life_potion", 0))
		var res := shop.buy(potion_idx)
		var after: int = int(shop.player["consumables"].get("life_potion", 0))
		_ok("买药水入包成功（数量+1）", res.get("ok", false) and after == before + 1)
		_ok("买药水扣款", float(shop.player["gold"]) < 200.0)

	# C. 掉落 roll：消耗品分支返回合法载荷
	var drop := LootRoller._roll_consumable(7)
	_ok("消耗品掉落类型正确", str(drop.get("type", "")) == "consumable")
	_ok("消耗品掉落 id 在表中", ConfigLoader.consumables.has(str(drop.get("item_id", ""))))
	_ok("消耗品掉落数量>=1", int(drop.get("amount", 0)) >= 1)

	# D. 玩家使用：回血 / 回蓝 / 冷却 / 数量
	var p := PLAYER_SCENE.instantiate()
	get_tree().root.add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	# 扣血到半血，保证回血量可断言
	var max_hp: float = float(p.health.get_max_hp())
	p.health.take_damage(max_hp * 0.5, p)
	var hp_before: float = float(p.health.get_current_hp())
	p.consumables["life_potion"] = 2
	var use: Dictionary = p.use_consumable("life_potion")
	_ok("使用生命药水成功", use.get("ok", false))
	_ok("回血生效（HP 提升）", float(p.health.get_current_hp()) > hp_before + 1.0)
	_ok("回血量=30% 最大生命（容差 1）", absf(float(use.get("healed", 0.0)) - max_hp * 0.30) <= 1.0)
	_ok("数量扣减（2→1）", p.consumable_count("life_potion") == 1)
	var cd1: float = float(p.get_consumable_cd_remaining("life_potion"))
	_ok("冷却开始（剩余>0）", cd1 > 0.0)
	var blocked: Dictionary = p.use_consumable("life_potion")
	_ok("冷却中阻止使用", not blocked.get("ok", true) and str(blocked.get("reason", "")) == "冷却中")
	_ok("冷却中不扣数量（仍=1）", p.consumable_count("life_potion") == 1)
	# 回蓝
	var mp_max: float = float(p.get_mana_pool().maximum)
	p.get_mana_pool().set_current(mp_max * 0.2)
	p.consumables["mana_potion"] = 1
	var use_m: Dictionary = p.use_consumable("mana_potion")
	_ok("使用法力药水成功", use_m.get("ok", false))
	_ok("回蓝生效（法力提升）", float(p.get_mana_pool().current) > mp_max * 0.2 + 1.0)
	_ok("法力回蓝量=40% 上限（容差 1）", absf(float(use_m.get("healed", 0.0)) - mp_max * 0.40) <= 1.0)
	# 数量不足
	p.consumables["mana_potion"] = 0
	var empty: Dictionary = p.use_consumable("mana_potion")
	_ok("数量不足阻止使用", not empty.get("ok", true))
	p.queue_free()
	await get_tree().process_frame

	# E. 存档往返
	var sd := SaveData.create_new(0, "warrior")
	sd.consumables = {"life_potion": 3, "mana_potion": 2}
	var dict := sd.to_dict()
	_ok("to_dict 含 consumables", dict.get("consumables") is Dictionary)
	var back := SaveData.from_dict(dict)
	_ok("from_dict 往返一致", int(back.consumables.get("life_potion", 0)) == 3
		and int(back.consumables.get("mana_potion", 0)) == 2)
	_ok("存档版本=4", back.save_version == 4)
	var old := SaveData.new()
	old.save_version = 3
	old.class_id = "warrior"
	old.skill_bar = ["slash"]
	_ok("旧档 v3 迁移成功", old.migrate() and old.save_version == 4 and old.consumables is Dictionary)

	# F. 药水图标贴图
	var life := UISkin.texture("potion_life")
	var mana := UISkin.texture("potion_mana")
	_ok("生命药水图标 48×48", life != null and life.get_width() == 48 and life.get_height() == 48)
	_ok("法力药水图标 48×48", mana != null and mana.get_width() == 48 and mana.get_height() == 48)

	# G. QuickSlotUI 结构（仅结构检查，不依赖玩家）
	var slot: Control = QUICK_SLOT_SCRIPT.new()
	get_tree().root.add_child(slot)
	await get_tree().process_frame
	_ok("快捷栏 2 槽", slot.get_slot_count() == 2)

	print("===== 结果：%d 通过 / %d 失败 =====" % [_pass, _fail])
	if _fail > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


var _pass: int = 0


func _ok(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] " + name)
	else:
		_fail += 1
		print("  [FAIL] " + name)
