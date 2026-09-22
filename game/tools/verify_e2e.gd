## 集成层阶段 3 · 端到端跑通（审计 §4 #2 / team-lead 阶段 3 验收标准）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_e2e.tscn
##   退出码 0 = 全流程走通；1 = 有失败项
##
## 覆盖**完整玩家路径**（不是零件自测）：
##   ① 主菜单（清空存档 → has_any_save()=false）
##   ② 新档（点「开始游戏」→ 主菜单内部走 _start_new_character）
##   ③ 据点（SceneManager 切到 hub，据点数 = 新档数据）
##   ④ 选关（**真的点关卡按钮**，不直接 emit 信号）
##   ⑤ 进关卡（LevelScene 生成布局 + 刷怪 + 相机 2×）
##   ⑥ 打怪（真实 take_damage → unit_died → 掉落）
##   ⑦ 拾取（LootDrop 走真实距离判定 → pickup_loot → 会话背包）
##   ⑧ 结算（清空目标 → RunResult.finalize → 结算面板可见）
##   ⑨ 回据点（点「返回大厅」→ 落盘 → 存档里能读到金币/通关记录）
##
## ⚠️ 两个刻意的测试期改动（不改玩法，只为让流程可在无头下快速跑完）：
##   - `SceneManager.fade_duration = 0.0`（否则每段过场都要等淡入淡出）
##   - 把地面掉落物移到玩家脚下（省去逐个跑图，拾取判定本身仍走真实距离逻辑）
##
## ⚠️ 本脚本必须把执行体挂在 `get_tree().root` 下，**不能**挂在自身场景里 ——
##    SceneManager 每次切场景都会 free 掉 `current_scene`，挂在场景里的观察者会被一起销毁。
##
## ⚠️ 同理，**结束/退出逻辑必须写在执行体内部**：执行体若通过 signal 回调宿主场景的
##    方法来 quit，宿主在第①步切场景时就已经被 free，连接被 Godot 自动断开 ⇒
##    流程跑完后无人 quit ⇒ 无头运行会一直挂到超时被 SIGTERM 杀掉（表现为"跑完了但不退出"）。
extends Node2D


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）。
	# 本脚本尤其需要 —— 退出逻辑在执行体内部（见上方第 2 条 ⚠️），执行体中途抛错时
	# 宿主已被切场景 free，没有任何人 quit ⇒ 无头下必然挂到外部 timeout。
	VerifyWatchdog.arm(get_tree())
	var runner := E2ERunner.new()
	runner.name = "E2ERunner"
	# ⚠️ 必须 call_deferred：`_ready()` 时 root 正在 setup children，
	# 直接 add_child 会报 "Parent node is busy setting up children" 并**静默失败**
	# （runner 不存在 ⇒ 没人 quit ⇒ 无头下会一直挂到超时被杀）。
	get_tree().root.add_child.call_deferred(runner)


# =============================================================================
# 执行体（挂在 root 下，跨场景存活）
# =============================================================================

class E2ERunner extends Node:
	const SLOT: int = 5
	const LEVEL_ID: String = "ch1_l01"
	const MAX_WAIT_FRAMES: int = 900

	var fail: int = 0

	## 主菜单实际用的槽位（`_start_new_character` 取第一个空槽，不一定是 SLOT 常量）
	var _slot: int = -1

	## 各阶段抓到的现场
	var _hub: Node = null
	var _level: LevelScene = null
	var _player: PlayerController = null
	var _killed: int = 0
	var _drops_seen: int = 0
	var _equip_picked: int = 0
	var _equip_with_affix: int = 0
	## 结算单口径的入包装备件数（⑧ 从 `RunResult.bagged_equipment` 取）。
	## 与 `_equip_picked`（⑦ 阶段的背包快照）分开：两者之间夹着保底掉落 + 0.6s 拾取窗口，
	## 用同一个变量跨阶段比较会 flaky。
	var _bagged_count: int = -1
	var _gold_after_settle: int = 0


	func _ok(label: String, cond: bool) -> void:
		if not cond:
			fail += 1
		print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


	func _ready() -> void:
		_run()


	func _run() -> void:
		print("===== 集成层阶段 3 · 端到端跑通 =====")
		# 过场淡入淡出对本测试没有价值，置 0 让每段切换只需 1–2 帧
		SceneManager.fade_duration = 0.0

		await _step1_boot_to_main_menu()
		await _step2_new_character()
		await _step3_hub()
		await _step4_pick_level()
		await _step5_enter_level()
		await _step6_combat()
		await _step7_pickup()
		await _step8_settle()
		await _step9_back_to_hub()

		print("===== 端到端结果：%d 项失败 =====" % fail)
		get_tree().quit(0 if fail == 0 else 1)


	# -------------------------------------------------------------------------
	# 工具
	# -------------------------------------------------------------------------

	## 等 `current_scene` 变成指定场景；超时返回 null
	##
	## ⚠️ 光看 `current_scene` 不够：`SceneManager._apply_scene()` 先设 `current_scene_path`
	## （scene_manager.gd:204）再在 `change_scene()` 末尾把 `is_transitioning` 置 false
	## （:81）。若在中间这段窗口里发起下一次切换，会被 `push_warning("正在切换中，忽略本次请求")`
	## **静默吞掉**。所以这里必须连带等 `is_transitioning` 归 false。
	func _wait_for_scene(path: String) -> Node:
		for _i in MAX_WAIT_FRAMES:
			await get_tree().process_frame
			var cs := get_tree().current_scene
			if cs != null and cs.scene_file_path == path and not SceneManager.is_transitioning:
				return cs
		return null


	func _wait_frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame


	## 递归统计含指定文本的 Label 数量（用于断言面板真的渲染出了内容）
	func _count_labels_containing(root: Node, needle: String) -> int:
		var n := 0
		for c in root.get_children():
			if c is Label and String((c as Label).text).contains(needle):
				n += 1
			n += _count_labels_containing(c, needle)
		return n


	## 递归找指定类型的后代节点（脚本类实例的**节点名**不可靠，不能按名字找）
	func _find_by_class(root: Node, cls: String) -> Node:
		for c in root.get_children():
			if c.is_class(cls) or (c.get_script() != null
					and String((c.get_script() as Script).get_global_name()) == cls):
				return c
			var r := _find_by_class(c, cls)
			if r != null:
				return r
		return null


	## 递归找按钮（用**真的按钮**驱动流程，而不是绕过 UI 直接调方法）
	func _find_button(root: Node, needle: String) -> Button:
		for c in root.get_children():
			if c is Button and String((c as Button).text).contains(needle):
				return c as Button
			var r := _find_button(c, needle)
			if r != null:
				return r
		return null


	# -------------------------------------------------------------------------
	# ① 主菜单
	# -------------------------------------------------------------------------

	func _step1_boot_to_main_menu() -> void:
		# 清空全部槽位，保证主菜单走「无存档 → 直接新档」那条分支
		for i in range(GameConstants.SAVE_MAX_SLOTS):
			if SaveManager.slot_exists(i):
				SaveManager.delete_slot(i)
		SaveManager.current_data = null
		SaveManager.current_slot = -1
		_ok("① 已清空全部存档（has_any_save=%s）" % str(SaveManager.has_any_save()),
			not SaveManager.has_any_save())

		SceneManager.change_scene(SceneManager.SCENE_MAIN_MENU)
		var menu := await _wait_for_scene(SceneManager.SCENE_MAIN_MENU)
		_ok("① 进入主菜单：%s" % SceneManager.SCENE_MAIN_MENU, menu != null)
		if menu == null:
			return
		_ok("① 主菜单根节点是 CanvasLayer 且挂了 MainMenuPanel",
			menu is CanvasLayer and _find_by_class(menu, "MainMenuPanel") != null)


	# -------------------------------------------------------------------------
	# ② 新档
	# -------------------------------------------------------------------------

	func _step2_new_character() -> void:
		var menu := get_tree().current_scene
		if menu == null:
			_ok("② 主菜单仍在场（前置）", false)
			return
		var start_btn := _find_button(menu, "开始游戏")
		_ok("② 主菜单「开始游戏」按钮存在", start_btn != null)
		if start_btn == null:
			return
		start_btn.pressed.emit()          # 真按钮 → _on_start（无档 → 弹角色选择）
		await _wait_frames(2)

		# 2026-09-22 步骤 2：无存档 → 先弹角色选择面板，点「确认选择」（默认战士）
		var csp := _find_by_class(get_tree().current_scene, "CharacterSelectPanel")
		_ok("② 无存档 → 弹出角色选择面板", csp != null)
		if csp != null:
			var confirm := _find_button(csp, "确认选择")
			_ok("② 角色选择面板「确认选择」按钮存在", confirm != null)
			if confirm != null:
				confirm.pressed.emit()
				await _wait_frames(2)

		var data := SaveManager.current_data
		_slot = SaveManager.current_slot
		_ok("② 新档已建且 current_data 就绪（槽 %d / Lv.%d / 金币 %d）"
			% [_slot, data.account_level if data != null else -1,
				data.gold if data != null else -1],
			data != null and _slot >= 0 and SaveManager.slot_exists(_slot))


	# -------------------------------------------------------------------------
	# ③ 据点
	# -------------------------------------------------------------------------

	func _step3_hub() -> void:
		_hub = await _wait_for_scene(SceneManager.SCENE_HUB)
		_ok("③ 进入据点：%s" % SceneManager.SCENE_HUB, _hub != null)
		if _hub == null:
			return
		_ok("③ 据点数 = 新档数据（金币 %d）"
			% (SaveManager.current_data.gold if SaveManager.current_data != null else -1),
			SaveManager.current_data != null)


	# -------------------------------------------------------------------------
	# ④ 选关（真的点关卡按钮）
	# -------------------------------------------------------------------------

	func _step4_pick_level() -> void:
		if _hub == null:
			_ok("④ 据点就绪（前置）", false)
			return
		var lv_def: LevelData = ConfigLoader.get_level(LEVEL_ID)
		_ok("④ 目标关数据存在：%s（%s）" % [LEVEL_ID, lv_def.display_name if lv_def != null else "?"],
			lv_def != null)
		var btn := _find_button(_hub, lv_def.display_name) if lv_def != null else null
		_ok("④ 据点数单里找到该关按钮（按显示名匹配）", btn != null)
		if btn == null:
			return
		_ok("④ 该关按钮可点（已解锁）", not btn.disabled)
		btn.pressed.emit()                # 真按钮 → _on_level_picked → EventBus.request_start_level


	# -------------------------------------------------------------------------
	# ⑤ 进关卡
	# -------------------------------------------------------------------------

	func _step5_enter_level() -> void:
		var cs := await _wait_for_scene(SceneManager.SCENE_LEVEL)
		_ok("⑤ 进入关卡容器：%s" % SceneManager.SCENE_LEVEL, cs != null)
		if cs == null:
			return
		_level = cs as LevelScene
		_ok("⑤ 关卡根节点是 LevelScene", _level != null)
		if _level == null:
			return
		_ok("⑤ 载荷生效：level_id=%s tier=%d"
			% [_level.level_id, _level.difficulty_tier],
			_level.level_id == LEVEL_ID)
		_ok("⑤ 地图已生成（tile > 0）", _level._view.tile_count() > 0)
		_ok("⑤ 敌人已刷出（%d 只）" % _level._alive.size(), _level._alive.size() > 0)
		_ok("⑤ 玩家已生成且进了 player 组",
			_level._player != null and _level._player.is_in_group(&"player"))
		_ok("⑤ 相机缩放 = CAMERA_ZOOM_BASE（%s）" % str(_level._camera.zoom),
			_level._camera.zoom == GameConstants.CAMERA_ZOOM_BASE)
		_ok("⑤ 玩家生命上限已由 StatCalculator 接管（%.0f > 0）"
			% (_level._player.health.get_max_hp() if _level._player.health != null else -1.0),
			_level._player.health != null and _level._player.health.get_max_hp() > 0.0)

		_player = _level._player
		# 把玩家挪到怪物堆中间，保证掉落都落在附近（便于后续拾取，不影响战斗判定）
		if _level._alive.size() > 0:
			var sum := Vector2.ZERO
			for e in _level._alive:
				sum += e.global_position
			_player.global_position = sum / float(_level._alive.size())
			await _wait_frames(2)


	# -------------------------------------------------------------------------
	# ⑥ 打怪
	# -------------------------------------------------------------------------

	func _step6_combat() -> void:
		if _level == null or _player == null:
			_ok("⑥ 关卡与玩家就绪（前置）", false)
			return
		var total := _level._alive.size()
		# ⚠️ 处决阶段先给玩家挂无敌帧。
		#    原因：精英词缀「荆棘」会**反弹 15% 伤害给攻击方**（enemy_base.gd:317-320）。
		#    测试用 1e9 一击必杀，被反弹回来就是 1.5e8 ⇒ 玩家当场暴毙，
		#    后续 `_on_unit_died` 因 `_finished` 已置位而全部提前 return ⇒ 击杀数卡住。
		#    这是**测试手法**的副作用（真实玩家不会打出 1e9），不是玩法缺陷。
		#    用 `is_invulnerable()`（闪避无敌帧）这条既有正规通道，而不是改血量或加开关。
		_player._iframe_timer = 9999.0
		# 逐只打死（真实走 EnemyBase.take_damage → HealthComponent → unit_died → 掉落）
		for e in _level._alive.duplicate():
			if is_instance_valid(e):
				e.take_damage(1.0e9, _player)
		await _wait_frames(10)
		_player._iframe_timer = 0.0

		_killed = _level._kills
		_ok("⑥ 击杀计数 = 刷怪数（%d / %d）" % [_killed, total], _killed == total)
		_ok("⑥ 存活敌人已清空（%d）" % _level._alive.size(), _level._alive.is_empty())
		var drops := get_tree().get_nodes_in_group(&"loot_drops")
		_drops_seen = drops.size()
		_ok("⑥ 怪物死亡产生了地面掉落（%d 件）" % _drops_seen, _drops_seen > 0)


	# -------------------------------------------------------------------------
	# ⑦ 拾取（走真实距离判定）
	# -------------------------------------------------------------------------

	func _step7_pickup() -> void:
		if _player == null:
			_ok("⑦ 玩家就绪（前置）", false)
			return
		var inv_before := _player.inventory.size()
		var gold_before := _player.gold

		# 把掉落物搬到玩家脚下 —— 拾取判定本身仍由 LootDrop._process 的真实距离逻辑决定
		var drops := get_tree().get_nodes_in_group(&"loot_drops")
		for d in drops:
			if is_instance_valid(d) and d is LootDrop:
				(d as LootDrop).global_position = _player.global_position
		# LOOT_POP_DELAY(0.25s) + 拾取判定需要若干物理/处理帧
		await _wait_frames(40)

		_equip_picked = _player.inventory.size()
		var picked_delta := _player.inventory.size() - inv_before
		_ok("⑦ 拾取后会话背包增长（%d → %d）" % [inv_before, _player.inventory.size()],
			picked_delta > 0)
		# 掉落类型是随机的（普通怪 8% 触发，触发后还要按权重在装备/金币/材料间分），
		# 所以只断言「拾取确实产生了收益」，不锁定具体是哪一类。
		# 金币进账的确定性覆盖在 ⑧（通关金币奖励）那一条。
		_ok("⑦ 拾取产生了实际收益（本次 +%d 件 / 金币 +%d / 魔石 +%d）"
			% [picked_delta, _player.gold - gold_before, _player.materials],
			picked_delta > 0 or _player.gold > gold_before or _player.materials > 0)

		# 【回归】装备条目必须穿过 LootDrop 这一环。
		# 曾经 `LootDrop` 既没有 `instance` 字段、`setup()` 也不读它 ⇒ 词缀在掉落物这一环被丢弃，
		# `pickup_loot()` 静默走「无词缀占位」分支 ⇒ 玩家捡到的装备全是白板，且无任何报错。
		# `verify_affix_roller.gd` 抓不到是因为它**直接调用** `pickup_loot()`（不经过 LootDrop）。
		# 断言口径：**每条入包装备都必须带非空 instance**（不要求有词缀 —— iLvl 1 的普通装本来就没词缀）。
		#
		# ⚠️ `_equip_picked` 记的是**背包全量**、不是本次增量 —— 下面的循环遍历整个背包，
		#    两者口径必须一致。2026-09-18 修：此前记增量，当 `inv_before > 0`
		#    （掉落多、玩家在测试搬运动作之前已自动捡到）时「全量 3 ≠ 增量 2」必红；
		#    此前一直绿只是因为恰好 `inv_before == 0`，增量碰巧等于全量。
		#    教训：**两个数相除/相等之前，先确认它们数的是同一个集合。**
		_equip_with_affix = 0
		for entry in _player.inventory:
			var inst: Dictionary = entry.get("instance", {})
			if not inst.is_empty() and not String(inst.get("template_id", "")).is_empty():
				_equip_with_affix += 1
		_ok("⑦【回归】入包装备都带完整 instance（%d / %d 件，证明词缀穿过 LootDrop 未被丢弃）"
			% [_equip_with_affix, _equip_picked],
			_equip_picked > 0 and _equip_with_affix == _equip_picked)


	# -------------------------------------------------------------------------
	# ⑧ 结算
	# -------------------------------------------------------------------------

	func _step8_settle() -> void:
		if _level == null:
			_ok("⑧ 关卡就绪（前置）", false)
			return
		# 清空全部敌人后，_objective_done() 会在 unit_died 回调里触发结算
		var waited := 0
		while not _level._finished and waited < MAX_WAIT_FRAMES:
			await get_tree().process_frame
			waited += 1
		_ok("⑧ 目标达成后自动结算（等了 %d 帧）" % waited, _level._finished)
		await _wait_frames(2)
		_ok("⑧ 结算面板已显示",
			_level._result_panel != null and _level._result_panel.visible)
		var hub_btn := _find_button(_level._result_panel, "返回大厅")
		_ok("⑧ 结算面板有「返回大厅」按钮", hub_btn != null)

		# 【回归】level_completed 必须**既有生产者又有消费者**（审计 #10：此前零生产者）。
		# 监听者必须挂 Autoload：`change_scene()` 走 `change_scene_to_packed()` 会释放旧场景，
		# 结算那一刻据点还没被实例化 ⇒ 挂 hub 的监听在真实流程里**永不触发**。
		var summary: Dictionary = SceneManager.last_run_summary
		var res_obj: RunResult = summary.get("result", null)

		# ⚠️ 基准用**结算单自己的** `bagged_equipment`，不用 ⑦ 阶段记的快照：
		#    ⑦ 与 ⑧ 之间还夹着「目标达成 → 补保底掉落 → 等 GUARANTEE_PICKUP_GRACE(0.6s)」，
		#    那件保底装备可能在这段时间里被自动捡走 ⇒ 拿旧快照比会 flaky。
		#    教训：**每个断言用自己阶段的数据源**，别跨阶段传快照。
		_bagged_count = res_obj.bagged_equipment.size() if res_obj != null else -1

		# 【回归】结算面板必须真的把「入包装备」逐件渲染出来。
		# 曾经关卡容器往 `RunResult.bagged_equipment` 里塞 Dictionary，而面板按对象读
		# `item.template_id` ⇒ 抛 SCRIPT ERROR 并**在创建按钮之前中断** ⇒
		# 玩家卡在结算界面回不了据点（上面的「返回大厅」断言会一起变红）。
		_ok("⑧【回归】结算面板渲染出奖励清单（%d 件入包 → %d 行明细）"
			% [_bagged_count, _count_labels_containing(_level._result_panel, "iLvl")],
			_bagged_count <= 0
				or _count_labels_containing(_level._result_panel, "iLvl") == mini(_bagged_count, 6))

		_ok("⑧ level_completed 已被 SceneManager 收到（载荷单键 {\"result\": RunResult}）",
			not summary.is_empty() and summary.keys().size() == 1 and res_obj != null)
		_ok("⑧ 收到的结算单与本次一致（击杀 %d / 评分 %s）"
			% [res_obj.kills if res_obj != null else -1,
				res_obj.grade if res_obj != null else "?"],
			res_obj != null and res_obj.kills == _killed)

		var data := SaveManager.current_data
		_gold_after_settle = data.gold if data != null else -1
		_ok("⑧ 结算已落盘：金币 %d / 击杀统计 %d / 通关记录含 %s"
			% [_gold_after_settle,
				int(data.statistics.get("monsters_killed", 0)) if data != null else -1,
				LEVEL_ID],
			data != null and data.gold > 0
				and int(data.statistics.get("monsters_killed", 0)) >= _killed
				and data.cleared_levels.has(LEVEL_ID))
		_ok("⑧ 入包装备已进存档背包（存档 %d 件 / 结算单 %d 件）"
			% [data.inventory.size() if data != null else -1, _bagged_count],
			data != null and _bagged_count >= 0 and data.inventory.size() == _bagged_count)


	# -------------------------------------------------------------------------
	# ⑨ 回据点
	# -------------------------------------------------------------------------

	func _step9_back_to_hub() -> void:
		if _level == null:
			_ok("⑨ 关卡就绪（前置）", false)
			return
		var hub_btn := _find_button(_level._result_panel, "返回大厅")
		if hub_btn == null:
			return
		hub_btn.pressed.emit()            # → on_hub → SceneManager.change_to_hub()
		var hub := await _wait_for_scene(SceneManager.SCENE_HUB)
		_ok("⑨ 从结算回到据点", hub != null)
		if hub == null:
			return

		# 重开一次存档，确认结算真的写进了磁盘（而不是只改了内存对象）
		var reloaded := SaveManager.load_from_slot(_slot)
		_ok("⑨ 重新读档后金币仍在（%d）" % (reloaded.gold if reloaded != null else -1),
			reloaded != null and reloaded.gold == _gold_after_settle and reloaded.gold > 0)
		_ok("⑨ 重新读档后通关记录含 %s" % LEVEL_ID,
			reloaded != null and reloaded.cleared_levels.has(LEVEL_ID))
		_ok("⑨ 重新读档后背包里装备仍在（%d 件）"
			% (reloaded.inventory.size() if reloaded != null else -1),
			reloaded != null and reloaded.inventory.size() == _bagged_count)

		# 清理：把本测试占用的槽位删掉，别污染开发机
		if _slot >= 0:
			SaveManager.delete_slot(_slot)
