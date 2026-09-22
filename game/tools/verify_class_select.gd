## 角色选择面板实测（步驟 2 · 2026-09-22 · 開發用，不屬於遊戲玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_class_select.tscn
##   退出碼 0 = 全部通過；1 = 有失敗項
##
## 驗證思路（驗結果，不驗函式被呼叫）：
##   A. 職業數據表：3 職業齊全，stats / skills / portrait 全可解析（貼圖真的載得進）
##   B. 面板結構：四欄佈局節點存在（職業按鈕 ×3 / 立繪 / 數值 2×5 / 技能卡 ×4）
##   C. 交互流：默認選中戰士 → 點弓箭手 → 點法師 → 各欄內容真的切換
##   D. 確認流：on_confirm 回傳當前 class_id；主菜單「開始遊戲」→ 面板 → 確認 → 建檔 class_id 落盤
##
## ⚠️ 必須把執行體掛在 `get_tree().root` 下（不能掛在自身場景）：
##    SceneManager 切場景會 free 掉 current_scene，掛場景裡的觀察者會被一起銷毀。
extends Node2D

const MENU_SCENE: PackedScene = preload("res://scenes/main/main_menu.tscn")
const CLASS_IDS: Array[String] = ["warrior", "archer", "mage"]
const STAT_KEYS: Array[String] = ["max_hp", "attack", "armor", "move_speed", "crit_chance"]


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	var runner := Runner.new()
	runner.name = "ClassSelectRunner"
	get_tree().root.add_child.call_deferred(runner)


# =============================================================================
# 执行体（挂在 root 下，跨场景存活）
# =============================================================================

class Runner extends Node:
	var _fail: int = 0


	func _ok(label: String, cond: bool) -> void:
		if not cond:
			_fail += 1
		print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


	func _info(label: String) -> void:
		print("       %s" % label)


	var _got_confirm: String = ""

	func _on_test_confirm(class_id: String) -> void:
		_got_confirm = class_id

	func _wait_frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame


	func _find_by_class(root: Node, cls: String) -> Node:
		for c in root.get_children():
			if c.is_class(cls) or (c.get_script() != null
					and String((c.get_script() as Script).get_global_name()) == cls):
				return c
			var r := _find_by_class(c, cls)
			if r != null:
				return r
		return null


	func _find_button(root: Node, needle: String) -> Button:
		for c in root.get_children():
			if c is Button and String((c as Button).text).contains(needle):
				return c as Button
			var r := _find_button(c, needle)
			if r != null:
				return r
		return null


	func _count_labels_containing(root: Node, needle: String) -> int:
		var n := 0
		for c in root.get_children():
			if c is Label and String((c as Label).text).contains(needle):
				n += 1
			n += _count_labels_containing(c, needle)
		return n


	func _wait_for_scene(path: String) -> Node:
		for _i in 600:
			await get_tree().process_frame
			var cs := get_tree().current_scene
			if cs != null and cs.scene_file_path == path and not SceneManager.is_transitioning:
				return cs
		return null


	func _ready() -> void:
		_run()


	func _run() -> void:
		print("===== 角色选择面板實測（步驟 2）=====")
		SceneManager.fade_duration = 0.0
		_test_class_data()
		await _test_panel_layout()
		await _test_class_switching()
		await _test_confirm_flow()
		print("===== 角色选择面板實測 結束：%s ====="
			% ("全部通過" if _fail == 0 else "%d 項失敗" % _fail))
		get_tree().quit(0 if _fail == 0 else 1)


	# =========================================================================
	# A. 職業數據表
	# =========================================================================

	func _test_class_data() -> void:
		print("--- A. 職業數據表 ---")
		_ok("ConfigLoader.classes 含 3 職業（%s）" % ", ".join(CLASS_IDS),
			CLASS_IDS.all(func(id: String) -> bool: return ConfigLoader.classes.has(id)))

		var ok_stats := true
		var ok_skills := true
		var ok_portrait := true
		for cid in CLASS_IDS:
			var cls: Dictionary = ConfigLoader.classes[cid]
			var stats: Dictionary = cls.get("stats", {})
			for key in STAT_KEYS:
				if not stats.has(key) or not (stats[key] is float or stats[key] is int):
					ok_stats = false
					_info("%s 缺屬性 %s" % [cid, key])
			var sids: Array = cls.get("skills", [])
			if sids.size() < 3 or sids.size() > 5:
				ok_skills = false
				_info("%s 技能池數不在 3–5（%d）" % [cid, sids.size()])
			var dbar: Array = cls.get("default_skill_bar", [])
			if dbar.size() != 3:
				ok_skills = false
				_info("%s default_skill_bar 數 != 3（%d）" % [cid, dbar.size()])
			for sid in dbar:
				if not sids.has(sid):
					ok_skills = false
					_info("%s 默認欄 %s 不在技能池" % [cid, sid])
			for sid in sids:
				if ConfigLoader.get_skill(String(sid)) == null:
					ok_skills = false
					_info("%s 引用不存在技能 %s" % [cid, sid])
				else:
					var icon := str(GameConstants.SKILL_ICON.get(String(sid), ""))
					if icon.is_empty() or UISkin.texture(icon) == null:
						ok_skills = false
						_info("%s 技能 %s 的圖標映射缺失：%s" % [cid, sid, icon])
			var pkey := String(cls.get("portrait", ""))
			if pkey.is_empty() or UISkin.texture(pkey) == null:
				ok_portrait = false
				_info("%s 立繪缺失：%s" % [cid, pkey])
		_ok("3 職業的數值預覽鍵（max_hp/attack/armor/move_speed/crit_chance）齊全", ok_stats)
		_ok("3 職業技能池（3–5）全可解析 + 默認欄（3）在池內 + 圖標齊全", ok_skills)
		_ok("3 職業立繪貼圖全部載得進（portrait_*）", ok_portrait)

		var w: Dictionary = ConfigLoader.classes["warrior"]["stats"]
		var a: Dictionary = ConfigLoader.classes["archer"]["stats"]
		var m: Dictionary = ConfigLoader.classes["mage"]["stats"]
		_ok("分工成立：戰士生命最高（%d）＞弓（%d）＞法（%d）"
			% [int(w.max_hp), int(a.max_hp), int(m.max_hp)],
			int(w.max_hp) > int(a.max_hp) and int(a.max_hp) > int(m.max_hp))
		_ok("分工成立：弓暴擊最高（%.0f%%）＞法（%.0f%%）＞戰（%.0f%%）"
			% [float(a.crit_chance) * 100.0, float(m.crit_chance) * 100.0,
				float(w.crit_chance) * 100.0],
			float(a.crit_chance) > float(m.crit_chance)
				and float(m.crit_chance) > float(w.crit_chance))
		_ok("分工成立：法術攻最高（%d）＞戰（%d）＞弓（%d）"
			% [int(m.attack), int(w.attack), int(a.attack)],
			int(m.attack) > int(w.attack) and int(w.attack) > int(a.attack))


	# =========================================================================
	# B. 面板結構
	# =========================================================================

	func _test_panel_layout() -> void:
		print("--- B. 面板結構（直接實例化）---")
		var sp := CharacterSelectPanel.new()
		add_child(sp)
		await _wait_frames(2)

		var ok_btns := true
		for cid in CLASS_IDS:
			if _find_button(sp, ConfigLoader.class_display_name(cid)) == null:
				ok_btns = false
				_info("缺職業按鈕 %s" % cid)
		_ok("3 個職業按鈕存在", ok_btns)

		_ok("立繪 TextureRect 存在且有貼圖（默認戰士）",
			sp._portrait != null and sp._portrait.texture != null)

		var lbl_count := sp._stat_grid.get_child_count() if sp._stat_grid != null else -1
		_info("数值预览实际 Label 数：%d" % lbl_count)
		_ok("數值預覽 GridContainer 已渲染 2×5=10 個 Label",
			sp._stat_grid != null and lbl_count == 10)

		_ok("技能展示卡已建 5 張（職業池上限，技能描述行有內容）",
			sp._skill_cards.size() == 5 and not sp._skill_desc_label.text.is_empty())

		var visible_cards := 0
		var ok_icons := true
		for entry in sp._skill_cards:
			if not (entry["card"] as Control).visible:
				continue
			visible_cards += 1
			var icon := (entry["icon"] as TextureRect).texture
			if icon == null or icon == UISkin.texture("skill_slot"):
				ok_icons = false
		_ok("可見技能卡 = 職業池數（默認戰士 5）", visible_cards == 5)
		_ok("可見技能卡圖標全部非空（不佔位）", ok_icons)

		_ok("底部「确认选择」「返回」按鈕存在",
			_find_button(sp, "确认选择") != null and _find_button(sp, "返回") != null)

		var size := get_viewport().get_visible_rect().size
		_ok("面板完整落在視口 %s×%s 內（無溢出）"
			% [str(size.x), str(size.y)],
			sp.get_rect().end.x <= size.x + 0.5 and sp.get_rect().end.y <= size.y + 0.5)
		sp.queue_free()
		await _wait_frames(2)


	# =========================================================================
	# C. 職業切換
	# =========================================================================

	func _test_class_switching() -> void:
		print("--- C. 職業切換 ---")
		var sp := CharacterSelectPanel.new()
		add_child(sp)
		await _wait_frames(2)

		_ok("默認選中 %s" % sp.current_class_id, sp.current_class_id == "warrior")

		var archer_btn := _find_button(sp, "弓箭手")
		archer_btn.pressed.emit()
		await _wait_frames(2)
		var a: Dictionary = ConfigLoader.classes["archer"]["stats"]
		_ok("點弓箭手 → current_class_id=archer、立繪切換、暴擊率顯示 %.0f%%"
			% [float(a.crit_chance) * 100.0],
			sp.current_class_id == "archer"
				and sp._portrait.texture == UISkin.texture("portrait_archer")
				and _count_labels_containing(sp._stat_grid, "20%") > 0)

		var mage_btn := _find_button(sp, "法师")
		mage_btn.pressed.emit()
		await _wait_frames(2)
		var m: Dictionary = ConfigLoader.classes["mage"]["stats"]
		_ok("點法師 → current_class_id=mage、攻擊顯示 %d、技能描述含「火」"
			% [int(m.attack)],
			sp.current_class_id == "mage"
				and sp._portrait.texture == UISkin.texture("portrait_mage")
				and _count_labels_containing(sp._stat_grid, str(int(m.attack))) > 0
				and sp._skill_desc_label.text.contains("火"))

		_got_confirm = ""
		sp.on_confirm = _on_test_confirm
		var confirm := _find_button(sp, "确认选择")
		if confirm != null:
			confirm.pressed.emit()
		await _wait_frames(2)
		_ok("on_confirm 回傳當前職業 %s" % _got_confirm, _got_confirm == "mage")
		sp.queue_free()
		await _wait_frames(2)


	# =========================================================================
	# D. 確認流（主菜單 → 面板 → 建檔落盤）
	# =========================================================================

	func _test_confirm_flow() -> void:
		print("--- D. 主菜單確認流 ---")
		for i in range(GameConstants.SAVE_MAX_SLOTS):
			if SaveManager.slot_exists(i):
				SaveManager.delete_slot(i)
		SaveManager.current_data = null
		SaveManager.current_slot = -1

		SceneManager.change_scene(SceneManager.SCENE_MAIN_MENU)
		var menu := await _wait_for_scene(SceneManager.SCENE_MAIN_MENU)
		_ok("主菜單已切換", menu != null)
		if menu == null:
			return

		var start_btn := _find_button(get_tree().current_scene, "开始游戏")
		_ok("主菜單「开始游戏」按鈕存在", start_btn != null)
		if start_btn == null:
			return
		start_btn.pressed.emit()
		await _wait_frames(3)

		var csp := _find_by_class(get_tree().current_scene, "CharacterSelectPanel")
		_ok("無存檔 → 點开始游戏彈出角色選擇面板", csp != null)
		if csp == null:
			return

		var mage_btn := _find_button(csp, "法师")
		if mage_btn != null:
			mage_btn.pressed.emit()
		await _wait_frames(2)
		var confirm := _find_button(csp, "确认选择")
		_ok("面板「确认选择」按鈕存在", confirm != null)
		if confirm == null:
			return
		confirm.pressed.emit()
		await _wait_frames(3)

		var data := SaveManager.current_data
		_ok("確認 → 新檔已建（槽 %d）且 class_id=mage（%s）"
			% [SaveManager.current_slot, data.class_id if data != null else "?"],
			data != null and data.class_id == "mage"
				and SaveManager.slot_exists(SaveManager.current_slot))
		if data != null:
			_ok("新檔顯示名含職業名：%s" % data.display_name,
				data.display_name.contains("法师"))

		var hub := await _wait_for_scene(SceneManager.SCENE_HUB)
		_ok("確認後進入據點", hub != null)

		# 據點屬性面板標題帶職業名（直接實例化 StatPanel 驗證新簽名）
		var sp2 := StatPanel.new()
		add_child(sp2)
		sp2.show_stats({"max_hp": 95.0, "attack": 15.0, "armor": 12.0}, "法师")
		await _wait_frames(2)
		_ok("StatPanel.show_stats(..., \"法师\") 標題含職業名",
			sp2._title != null and String(sp2._title.text).contains("法师")
				and String(sp2._title.text).contains("角色属性"))
		sp2.queue_free()

		# 清理：把本測試佔用的槽位刪掉，別污染開發機
		if SaveManager.current_slot >= 0:
			SaveManager.delete_slot(SaveManager.current_slot)
		SaveManager.current_data = null
		SaveManager.current_slot = -1
