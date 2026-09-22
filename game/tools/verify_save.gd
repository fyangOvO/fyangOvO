## 存档系统实测（开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_save.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## ⚠️ 本脚本会**真实读写** `user://saves`，且故意制造一次存档损坏来验证回滚。
##    它只使用**最后一个槽位**（SAVE_MAX_SLOTS - 1），跑完会自行清理，
##    但仍请勿在玩家正在游玩的存档目录上运行。
##
## 覆盖范围：新建槽位 / 写入 / 逐字段回读 / 引用回填 / 备份轮转 /
##          主档损坏回滚 / 损坏隔离 / 恢复后主档重建 / 槽位信息 / 删除
extends Node

## 本脚本使用的槽位：取最后一个，避免碰到玩家常用的 0 号槽
const SLOT: int = GameConstants.SAVE_MAX_SLOTS - 1

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 存档系统实测（槽位 %d）=====" % SLOT)
	SaveManager.set_autosave_enabled(false)
	SaveManager.delete_slot(SLOT)

	# --- 1) 新建槽位 ---
	var d := SaveManager.create_new_slot(SLOT)
	_ok("create_new_slot 返回非空", d != null)
	_ok("slot_exists 为真", SaveManager.slot_exists(SLOT))

	# 失败兜底（第一道，不是靠看门狗）：d 为 null 时下面 `d.add_gold()` 会对 Nil 调方法，
	# 抛 `Nonexistent function 'add_gold' in base 'Nil'` 直接中断 _ready() ⇒ quit() 永不执行
	# ⇒ 进程挂死到外部 timeout（实测 exit=124）。这里直接走失败路径，保留已记的 [FAIL]。
	if d == null:
		_finish()
		return

	# --- 2) 写入数据后存档 ---
	d.add_gold(1234)
	d.add_material("magic_stone", 7)
	var tpl := ConfigLoader.get_equipment_template("sword_iron")
	_ok("底材 sword_iron 可解析", tpl != null)
	var item := EquipmentInstance.create_from_template(tpl, 12, GameConstants.Rarity.LEGENDARY)
	d.inventory.append(item)
	d.set_equipped(GameConstants.EquipSlot.MAIN_HAND, item)
	_ok("save_to_slot 成功", SaveManager.save_to_slot(SLOT, d))

	# --- 3) 读回并逐字段比对 ---
	var r := SaveManager.load_from_slot(SLOT)
	_ok("load_from_slot 返回非空", r != null)
	if r == null:
		_finish()
		return
	_ok("gold 回读 = 1234", r.gold == 1234)
	_ok("magic_stone 回读 = 7", r.get_material("magic_stone") == 7)
	_ok("inventory 回读 1 件", r.inventory.size() == 1)
	var eq := r.get_equipped(GameConstants.EquipSlot.MAIN_HAND)
	_ok("equipped[主手] 回读非空", eq != null)
	if eq != null:
		_ok("instance_id 一致", eq.instance_id == item.instance_id)
		_ok("rarity 回读 = 传说(4)", eq.rarity == GameConstants.Rarity.LEGENDARY)
		_ok("item_level 回读 = 12", eq.item_level == 12)
		_ok("slot 回读 = 主手", eq.slot == GameConstants.EquipSlot.MAIN_HAND)
		_ok("set_id 与底材一致", eq.set_id == tpl.set_id)
		_ok("equipped 数组长度 = 部位数",
			r.equipped.size() == GameConstants.EQUIP_SLOT_COUNT)

	# --- 4) resolve 引用回填 ---
	var rr := SaveManager.load_from_slot_resolved(SLOT)
	_ok("load_from_slot_resolved 回填 template 引用",
		rr != null and rr.inventory.size() == 1 and rr.inventory[0].template != null)

	# --- 5) 备份轮转（连存 4 次，应生成 bak1..bak3）---
	for i in range(4):
		SaveManager.save_to_slot(SLOT, d)
	for i in range(1, GameConstants.SAVE_BACKUP_ROTATION + 1):
		_ok("备份 %d 已生成" % i, FileAccess.file_exists(SaveManager._backup_path(SLOT, i)))

	# --- 6) 损坏主档 -> 应回滚到备份、隔离现场、并重建主档 ---
	var f := FileAccess.open(SaveManager._slot_path(SLOT), FileAccess.WRITE)
	f.store_string("{ 这不是合法 JSON")
	f.close()
	var rec := SaveManager.load_from_slot(SLOT)
	_ok("主档损坏后仍能读档（回滚备份）", rec != null)

	var prefix := SaveManager._slot_path(SLOT).get_file().replace(".json", ".corrupt_")
	var quarantined := false
	var dir := DirAccess.open(SaveManager.save_dir)
	if dir != null:
		for name in dir.get_files():
			if name.begins_with(prefix):
				quarantined = true
	_ok("损坏文件被隔离为 .corrupt_*", quarantined)

	# 恢复后主档必须被重建，否则选档界面会把槽位显示成「空档」
	_ok("恢复后主档已重建", SaveManager.slot_exists(SLOT))
	_ok("恢复后槽位信息 exists = true",
		bool(SaveManager.get_slot_info(SLOT).get("exists", false)))

	# --- 7) 槽位信息 ---
	_ok("get_all_slot_infos 返回 %d 个槽位" % GameConstants.SAVE_MAX_SLOTS,
		SaveManager.get_all_slot_infos().size() == GameConstants.SAVE_MAX_SLOTS)
	_ok("has_any_save() 为真", SaveManager.has_any_save())

	# --- 8) 删除 ---
	_ok("delete_slot 成功", SaveManager.delete_slot(SLOT))
	_ok("删除后 slot_exists 为假", not SaveManager.slot_exists(SLOT))

	_finish()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
