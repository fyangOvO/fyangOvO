## 技能装备流程实测（步骤 3 补 · 2026-09-28 · 开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_skill_equip.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 定位：`verify_skill_panel` 覆盖「面板结构 + 单条交互 + 存档落盘」；本脚本**专攻
## 「装备链路端到端」**——把「点池卡装配 → 保存 → SkillController 重新载入 → 能施放」
## 整条路走通并取证。
##
## 职业选 mage（法师）：因召唤技 `summon_elemental` 在法师池内（战士/弓手池没有），
## 端到端才有「装一个真实存在的召唤技 → 能施放」的语义闭环。
##
## 覆盖：
##   A. bind 后结构：池卡数 = 职业池大小 / 出战栏 3 槽 / 工作区 = 存档栏
##   B. 池 → 栏：栏满拒绝 / 卸下腾位 / 装配到空位 / 已装再点拒绝
##   C. 栏 → 卸下 / 点空槽无操作 / 卸后重装（重排）
##   D. 保存：on_save 回呼收到 = 面板状态；落盘 + 读回一致；空栏拒绝
##   E. **端到端**：on_save 写 SaveManager.current_data.skill_bar（模拟 hub.gd::_on_skill_bar_saved）
##      → SkillController._load_skills() → get_skill_data != null → try_cast 成功
##   F. 符文装配门槛（HANDOFF-E）：ctx 有/无 `unlocked_runes` ⇒ 启用/不启用；
##      未解锁符文灰显 + 文案「未解锁」；空解锁集 ⇒ 24 条全不可选
##
## ⚠️ 结果行固定印「N 项失败」（简体）——回归驱动只认「项失败 / 全部通过（」，用繁体
##    「全部通過」会被误判 NO-RESULT（本项目已有 verify_class_select 踩过这坑）。
extends Node2D

## 测试用存档槽（跑完清理）
const SLOT: int = 0
## 测试职业（含召唤技 summon_elemental）
const CLASS_ID: String = "mage"

var _fail: int = 0
var _sp: SkillPanel = null
## 面板 on_save 回呼最后一次收到的栏
var _saved_bar: Array[String] = []
## on_save 被调用的次数（验证「空栏不触发保存」）
var _save_calls: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 技能装备流程实测（步骤 3 補）=====")
	SceneManager.fade_duration = 0.0
	await _test_bind_structure()
	await _test_pool_to_bar()
	await _test_bar_unequip()
	await _test_save_callback()
	await _test_end_to_end_cast()
	await _test_rune_unlock_gate()
	_cleanup()
	print("===== 技能装备流程实测 结束：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# A. bind 后结构
# =============================================================================

func _test_bind_structure() -> void:
	print("--- A. bind 后结构（池卡数随职业池动态）---")
	_prepare_slot(CLASS_ID, SLOT)
	var data := SaveManager.current_data
	_ok("新建法师档成功且默认栏 = 火球/冰霜新星/闪电链", data != null
		and data.skill_bar == ["fireball", "frost_nova", "lightning_chain"])
	if data == null:
		return
	var pool := ConfigLoader.class_skill_ids(CLASS_ID)
	_sp = SkillPanel.new()
	_sp.name = "TestSkillPanel"
	add_child(_sp)
	await _wait_frames(2)
	_sp.bind(CLASS_ID, pool, data.skill_bar, _on_save)
	await _wait_frames(1)
	_ok("池卡数 = 职业池大小（%s：%d 张）" % [CLASS_ID, pool.size()],
		_sp._pool_grid.get_child_count() == pool.size())
	_ok("出战栏 3 槽", _bar_slot_names(_sp).size() == 3)
	_ok("出战槽名 = 火球术 / 冰霜新星 / 闪电链",
		_bar_slot_names(_sp) == ["火球术", "冰霜新星", "闪电链"])
	_ok("bind 后工作区 = 存档栏", _sp.bar == data.skill_bar)


# =============================================================================
# B. 池 → 栏
# =============================================================================

func _test_pool_to_bar() -> void:
	print("--- B. 池 → 栏（拒绝满栏 / 卸下腾位 / 装配 / 已在栏）---")
	if _sp == null:
		_ok("SkillPanel 就绪（B 段前置）", false)
		return
	# 1) 栏满：点池卡 → 拒绝并提示
	_press_pool("summon_elemental")
	await _wait_frames(1)
	_ok("栏满时装配被拒（提示「已满」+ 栏不变）",
		_sp.bar == ["fireball", "frost_nova", "lightning_chain"]
		and _sp._info.text.contains("已满"))
	# 2) 卸下 1 号位（火球术）腾位 —— 点出战槽开详情 → 详情里卸下
	_unequip_bar(0)
	await _wait_frames(1)
	_ok("点出战槽 1 → 详情里「从出战栏卸下」火球术",
		_sp.bar == ["frost_nova", "lightning_chain"]
		and _sp._info.text.contains("已卸下"))
	# 3) 装配召唤技 → 自动补到空位
	_press_pool("summon_elemental")
	await _wait_frames(1)
	_ok("点池卡元素僕從 → 装配到空位",
		_sp.bar == ["frost_nova", "lightning_chain", "summon_elemental"])
	# 4) 已装再点 → 拒绝
	_press_pool("summon_elemental")
	await _wait_frames(1)
	_ok("已装技能再点池卡 → 提示「已在出战栏」",
		_sp.bar == ["frost_nova", "lightning_chain", "summon_elemental"]
		and _sp._info.text.contains("已在出战栏"))


# =============================================================================
# C. 栏 → 卸下 / 空槽 / 重排
# =============================================================================

func _test_bar_unequip() -> void:
	print("--- C. 栏 → 卸下 / 点空槽 / 重排 ---")
	if _sp == null:
		return
	# 1) 卸下 1 号位（冰霜新星）
	_unequip_bar(0)
	await _wait_frames(1)
	_ok("点出战槽 1 → 详情里卸下冰霜新星",
		_sp.bar == ["lightning_chain", "summon_elemental"])
	# 2) 栏当前 2 格，点第 3 槽（空）→ 无操作
	_press_bar(2)
	await _wait_frames(1)
	_ok("点空槽 → 无操作（栏不变）",
		_sp.bar == ["lightning_chain", "summon_elemental"])
	# 3) 卸后重装（重排）：重装火球术 → 末尾
	_press_pool("fireball")
	await _wait_frames(1)
	_ok("重装火球术 → [闪电链, 元素僕從, 火球术]",
		_sp.bar == ["lightning_chain", "summon_elemental", "fireball"])


# =============================================================================
# D. 保存回呼 + 落盘
# =============================================================================

func _test_save_callback() -> void:
	print("--- D. 保存 → on_save 回呼 + 落盘 ---")
	if _sp == null:
		return
	var before := _save_calls
	_press_save()
	await _wait_frames(2)
	_ok("保存触发 on_save 回呼（调用数 +1）", _save_calls == before + 1)
	_ok("on_save 收到的栏 = 面板工作区",
		_saved_bar == _sp.bar
		and _saved_bar == ["lightning_chain", "summon_elemental", "fireball"])
	var reloaded := SaveManager.load_from_slot(SLOT)
	_ok("落盘：存档 skill_bar 已更新 + 读回一致",
		SaveManager.current_data != null
		and SaveManager.current_data.skill_bar == _saved_bar
		and reloaded != null and reloaded.skill_bar == _saved_bar)
	# 空栏保存被拒（回呼不触发）
	_unequip_bar(0)
	await _wait_frames(1)
	_unequip_bar(0)
	await _wait_frames(1)
	_unequip_bar(0)
	await _wait_frames(1)
	var calls_before_empty := _save_calls
	_press_save()
	await _wait_frames(1)
	_ok("空栏保存被拒（提示「不能为空」+ 回呼不触发）",
		_sp.bar.is_empty()
		and _save_calls == calls_before_empty
		and _saved_bar == ["lightning_chain", "summon_elemental", "fireball"]
		and _sp._info.text.contains("不能为空"))
	# 复原面板工作区，供 E 段端到端使用
	_sp.bind(CLASS_ID, ConfigLoader.class_skill_ids(CLASS_ID), _saved_bar, _on_save)
	await _wait_frames(1)


# =============================================================================
# E. 端到端：装备 → 能施放（本任务重点）
# =============================================================================

func _test_end_to_end_cast() -> void:
	print("--- E. 端到端：装备 → 能施放（本任务重点）---")
	var data := SaveManager.current_data
	_ok("存档 skill_bar 含 summon_elemental 且与面板一致",
		data != null and _sp != null
		and _sp.bar.has("summon_elemental")
		and data.skill_bar == _sp.bar)
	var player := get_node_or_null("/root/VerifySkillEquip/Player") as PlayerController
	var sc := player.get_skill_controller() if player != null else null
	_ok("玩家 + SkillController 就绪", player != null and sc != null)
	if sc == null or _sp == null:
		return
	# 用存档栏重新载入技能（模拟进关：SkillController._ready / 读档后 _load_skills）
	sc._load_skills()
	_ok("_load_skills() 后载入 summon_elemental（装备 → 技能定义生效）",
		sc.get_skill_data("summon_elemental") != null)
	_ok("出战栏顺序 = [闪电链, 元素僕從, 火球术]",
		sc.get_skill_id_at(0) == "lightning_chain"
		and sc.get_skill_id_at(1) == "summon_elemental"
		and sc.get_skill_id_at(2) == "fireball")
	# 保证法力足够（召唤技 40 < 上限 100），排除资源干扰
	var mana := player.get_mana_pool()
	if mana != null:
		mana.set_current(mana.maximum)
	var cast := sc.try_cast("summon_elemental")
	_ok("try_cast(\"summon_elemental\") 成功（装备 → 能施放，整条链路打通）", cast)
	_ok("施放后进入冷却（冷却计时生效）", sc.is_on_cooldown("summon_elemental"))


# =============================================================================
# 工具
# =============================================================================

## 建一个干净的测试档并设为当前存档
func _prepare_slot(class_id: String, slot: int) -> void:
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
	var data := SaveManager.create_new_slot(slot, class_id)
	# 账号等级抬到 22 ⇒ 法师池全开（B4-4 / 1-L11 起，`summon_elemental` 的 unlock_level = 22）。
	# 否则 L1 账号下池卡灰显、装配被拒，整条端到端链路失效。
	data.account_level = 22
	SaveManager.current_data = data
	SaveManager.current_slot = slot


## 模拟 hub.gd::_on_skill_bar_saved：写内存 + 落盘
func _on_save(bar: Array[String]) -> void:
	_save_calls += 1
	_saved_bar = bar.duplicate()
	var data := SaveManager.current_data
	if data != null:
		data.skill_bar = bar.duplicate()
		SaveManager.save_to_slot(data.slot, data)


## 点池卡（走真实按钮 pressed 信号 → _on_pool_clicked）
func _press_pool(sid: String) -> void:
	var btn := _find_button_by_name(_sp, "PoolBtn_%s" % sid)
	if btn != null:
		btn.pressed.emit()
	else:
		_info("找不到池按钮 PoolBtn_%s" % sid)


## 点出战槽（走真实按钮 pressed 信号 → _on_bar_clicked）
func _press_bar(index: int) -> void:
	if _sp == null or _sp._bar_row == null or index >= _sp._bar_row.get_child_count():
		_info("找不到出战按钮 BarBtn%d" % index)
		return
	var slot := _sp._bar_row.get_child(index)
	var btn := slot.get_node_or_null("BarBtn%d" % index) as Button
	if btn != null:
		btn.pressed.emit()
	else:
		_info("槽 %d 内无 BarBtn%d" % [index, index])


func _press_save() -> void:
	var btn := _find_button(_sp, "保存配置")
	if btn != null:
		btn.pressed.emit()


# =============================================================================
# F. 符文装配门槛（图鉴解锁 · HANDOFF-E）
# =============================================================================

## 口径（`01-技能体系.md` §11.4 Q2「图鉴式解锁」）：**未解锁的符文不能装配**。
##
## ⚠️ 门槛写法与技能解锁**同款**：看 `ctx` 里**有没有** `unlocked_runes` 这个键 ——
##    有（哪怕空数组）= 启用门槛；没有 = 全放行（向后兼容旧调用 / 无头测试）。
##    本脚本 A~E 段的 `bind()` 都不传该键 ⇒ 不受影响。
func _test_rune_unlock_gate() -> void:
	print("--- F. 符文装配门槛（未解锁不能装）---")
	if _sp == null:
		_ok("SkillPanel 就绪（F 段前置）", false)
		return
	var pool := ConfigLoader.class_skill_ids(CLASS_ID)
	# 1) ctx **不带** unlocked_runes ⇒ 不启用门槛（向后兼容）
	_sp.bind(CLASS_ID, pool, _saved_bar, _on_save, { "skill_level": 6 })
	await _wait_frames(1)
	var swift := _open_rune_picker("fireball")
	_ok("ctx 无 unlocked_runes ⇒ 不启用门槛（rune_swift 可选）",
		swift != null and not swift.disabled)
	# 2) ctx 带 unlocked_runes = ["rune_swift"] ⇒ 只放行 swift
	_sp.bind(CLASS_ID, pool, _saved_bar, _on_save,
		{ "skill_level": 6, "unlocked_runes": ["rune_swift"] })
	await _wait_frames(1)
	swift = _open_rune_picker("fireball")
	var fire := _find_button_by_name(_sp, "RunePick_rune_fire")
	_ok("ctx 带 unlocked_runes ⇒ 已解锁的 rune_swift 可选",
		swift != null and not swift.disabled)
	_ok("未解锁的 rune_fire 灰显不可选（disabled）", fire != null and fire.disabled)
	_ok("未解锁项文案含「未解锁」（%s）" % (fire.text if fire != null else "—"),
		fire != null and fire.text.contains("未解锁"))
	# 3) 空解锁集 ⇒ 全部不可选（新档的真实状态）
	_sp.bind(CLASS_ID, pool, _saved_bar, _on_save,
		{ "skill_level": 6, "unlocked_runes": [] })
	await _wait_frames(1)
	_open_rune_picker("fireball")
	var pickable: Array[String] = []
	for rid_v in ConfigLoader.runes.keys():
		var b := _find_button_by_name(_sp, "RunePick_%s" % rid_v)
		if b != null and not b.disabled:
			pickable.append(String(rid_v))
	_ok("空解锁集 ⇒ 24 条符文全部灰显不可选（实际可选 %d 条）" % pickable.size(),
		pickable.is_empty())
	_sp._close_detail()


## 打开某技能的符文选择器（第 1 槽），返回指定符文按钮。
## 需要 `skill_level ≥ 3` 才解锁第 1 槽（`runes.json._meta.slot_unlock_skill_level = [3,6,9]`）。
func _open_rune_picker(sid: String) -> Button:
	_sp._open_detail(sid)
	_sp._on_rune_slot_pressed(0, true)
	return _find_button_by_name(_sp, "RunePick_rune_swift")


## 卸下第 index 个出战槽：B4-4 / 1-L14 起，点出战槽 = **打开技能详情**，
## 卸下入口移到详情浮层的「从出战栏卸下」按钮 ⇒ 必须两步走。
func _unequip_bar(index: int) -> void:
	_press_bar(index)
	var btn := _find_button_by_name(_sp, "DetailUnequip")
	if btn != null:
		btn.pressed.emit()
	else:
		_info("详情浮层里找不到 DetailUnequip（槽 %d）" % index)


func _bar_slot_names(sp: SkillPanel) -> Array:
	var names: Array = []
	if sp == null or sp._bar_row == null:
		return names
	for slot in sp._bar_row.get_children():
		for child in slot.get_children():
			if child is Label and (child as Label).position.y >= 40.0:
				names.append((child as Label).text)
	return names


func _find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		var btn := child as Button
		if btn.text == text:
			return btn
	return null


func _find_button_by_name(root: Node, nm: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		if child.name == nm:
			return child as Button
	return null


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _cleanup() -> void:
	for i in range(GameConstants.SAVE_MAX_SLOTS):
		if SaveManager.slot_exists(i):
			SaveManager.delete_slot(i)
	SaveManager.current_data = null
	SaveManager.current_slot = -1
