## 片頭場景驗證（開發用，不屬於遊戲玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_intro.tscn
##   退出碼 0 = 全部通過；1 = 有失敗項
##
## 為什麼需要它（**驗結果，不驗函式被呼叫**）
## -----------------------------------------
## 本專案反覆踩到「斷言全綠但實際上沒生效」，所以這裡**不**斷言
## 「`_build()` 被呼叫過」，而是斷言：
##   · 素材**真的**從**指定來源**解析出來（不是靜默回退到別的圖）；
##   · 三勇者 / 魔王**真的**是素材包多幀集（canvas 192 / 256）；
##   · 無頭下**真的**落到終態（字幕/角色/提示都在位、不透明度 = 1）；
##   · 全部可見 Control **真的**落在 0..640 × 0..360 內；
##   · **端到端**：啟動分流 main → 片頭 → 主菜單（走真實 `SceneManager` 切換）。
##
## ⚠️ 執行體必須掛在 `get_tree().root` 下（不能掛在自身場景裡）：
##    B 段會真的換場景，`SceneManager` 會 free 掉 `current_scene`，
##    掛在場景裡的觀察者會被一起銷毀 ⇒ 流程靜默中斷、無頭下掛到超時。
extends Node2D

const INTRO_SCENE: String = "res://scenes/main/intro.tscn"
const BOOT_SCENE: String = "res://scenes/main/main.tscn"


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 90.0)
	var verifier := IntroVerifier.new()
	verifier.name = "IntroVerifier"
	# ⚠️ 必須 call_deferred：`_ready()` 時 root 正在 setup children，
	#    直接 add_child 會報 "Parent node is busy setting up children" 並**靜默失敗**。
	get_tree().root.add_child.call_deferred(verifier)


class IntroVerifier extends Node:
	const MAX_WAIT_FRAMES: int = 600

	var fail: int = 0


	func _ok(label: String, cond: bool) -> void:
		if not cond:
			fail += 1
		print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


	func _info(label: String) -> void:
		print("       %s" % label)


	func _ready() -> void:
		_run()


	func _run() -> void:
		print("===== 片頭場景驗證（勇者斗恶魔 · 三职业勇者共伐魔王）=====")
		await _part_a_structure()
		await _part_b_boot_chain()
		print("===== 结果：%d 项失败 =====" % fail)
		get_tree().quit(0 if fail == 0 else 1)


	# -------------------------------------------------------------------------
	# 工具
	# -------------------------------------------------------------------------

	func _wait_frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame


	## 等 `current_scene` 变成指定场景（连带等 `is_transitioning` 归 false，见 verify_e2e 注释）
	func _wait_for_scene(path: String) -> Node:
		for _i in MAX_WAIT_FRAMES:
			await get_tree().process_frame
			var cs := get_tree().current_scene
			if cs != null and cs.scene_file_path == path and not SceneManager.is_transitioning:
				return cs
		return null


	func _scan_visible_controls(node: Node, out: Array) -> void:
		for c in node.get_children():
			if c is Control and (c as Control).is_visible_in_tree():
				out.append(c)
			_scan_visible_controls(c, out)


	# -------------------------------------------------------------------------
	# A. 場景結構 + 素材 + 終態
	# -------------------------------------------------------------------------

	func _part_a_structure() -> void:
		print("--- A. 場景結構 / 素材來源 / 終態 ---")
		_ok("SceneManager.SCENE_INTRO 已登記且指向片頭場景",
			SceneManager.SCENE_INTRO == INTRO_SCENE and ResourceLoader.exists(SceneManager.SCENE_INTRO))
		_ok("片頭場景檔存在且可載入", ResourceLoader.exists(INTRO_SCENE))

		var packed := load(INTRO_SCENE) as PackedScene
		_ok("片頭 .tscn 載入成功", packed != null)
		if packed == null:
			return
		var intro := packed.instantiate()
		get_tree().root.add_child.call_deferred(intro)
		await _wait_frames(4)

		_ok("片頭根節點是 CanvasLayer", intro is CanvasLayer)
		_ok("片頭掛的是 IntroScreen（有 next_scene_path）", intro.has_method("next_scene_path"))
		_ok("片頭 next_scene_path() == SceneManager.SCENE_MAIN_MENU",
			String(intro.call("next_scene_path")) == SceneManager.SCENE_MAIN_MENU)

		# ⚠️ 片頭腳本**自己的常量**（斷言一律從這裡讀，不在此硬編碼副本 ——
		#    否則腳本改了數值、這裡照樣全綠，屬自洽式偽校驗）。
		var consts: Dictionary = (intro.get_script() as Script).get_script_constant_map()

		# ── 背景：必須真的是生態 backdrop（釘住不是純黑回退）──
		var backdrop := intro.get_node_or_null("Backdrop") as TextureRect
		var want_bg := UISkin.texture("backdrop_volcanic")
		_ok("背景 Backdrop 存在且貼圖非空", backdrop != null and backdrop.texture != null)
		if backdrop != null and backdrop.texture != null:
			_ok("背景 = 640×360", backdrop.texture.get_width() == 640
				and backdrop.texture.get_height() == 360)
			_ok("背景用的是火山生態 backdrop（而非純黑兜底）",
				want_bg != null and backdrop.texture == want_bg)

		# ── 標題徽記 ──
		var emblem := intro.get_node_or_null("TitleEmblem") as TextureRect
		var want_emblem := UISkin.texture("title_emblem")
		_ok("標題徽記存在且 = title_emblem（336×112）",
			emblem != null and emblem.texture != null and emblem.texture == want_emblem
			and emblem.texture.get_width() == 336 and emblem.texture.get_height() == 112)

		# ── 魔王：必須來自精靈解析鏈（canvas 256 ⇒ 素材包多幀集）──
		var demon := intro.get_node_or_null("DemonLord") as Sprite2D
		_ok("魔王 DemonLord 存在且貼圖非空", demon != null and demon.texture != null)
		if demon != null and demon.texture != null:
			_ok("魔王畫布 = 256（素材包多幀集，非單幀兜底）", demon.texture.get_height() == 256)
			_ok("魔王縮放 = 0.5（整數縮放鐵律）", is_equal_approx(demon.scale.x, 0.5))

		# ── 三勇者：戰士 / 弓箭手 / 法師 ──
		var hero_names: Array[String] = ["Hero0_warrior", "Hero1_archer", "Hero2_mage"]
		var heroes_ok := 0
		for i in hero_names.size():
			var h := intro.get_node_or_null(hero_names[i]) as Sprite2D
			if h != null and h.texture != null and h.texture.get_height() == 192 \
					and is_equal_approx(h.scale.x, 0.5):
				heroes_ok += 1
			else:
				_info("勇者 %s：%s" % [hero_names[i],
					"null" if h == null else "tex=%s scale=%s" % [
						str(h.texture.get_size() if h.texture != null else Vector2.ZERO),
						str(h.scale)]])
		_ok("三職業勇者（warrior/archer/mage）皆為 192 畫布 + 0.5 縮放（%d/3）" % heroes_ok,
			heroes_ok == 3)

		# ── 動畫幀集：idle / walk / attack 都真的載入（打鬥段全靠 attack）──
		var actors: Array = intro.get("_actors")
		_ok("精靈動畫註冊數 = 4（三勇者 + 魔王）", actors.size() == 4)
		var anim_ok := 0
		var atk_ok := 0
		var mage_cast: Array = []
		var mage_node := intro.get_node_or_null("Hero2_mage")
		for a in actors:
			var clips: Dictionary = a["clips"]
			var walk: Array = clips.get("walk", [])
			var idle: Array = clips.get("idle", [])
			var atk: Array = clips.get("attack", [])
			if walk.size() >= 2 and idle.size() >= 2:
				anim_ok += 1
			if atk.size() >= 2:
				atk_ok += 1
			if a["node"] == mage_node:
				mage_cast = clips.get("cast", [])
		_ok("四隻精靈的 idle / walk 幀集都 ≥ 2 幀（%d/4）" % anim_ok, anim_ok == 4)
		_ok("四隻精靈的 attack 幀集都 ≥ 2 幀（打鬥段真的會動；%d/4）" % atk_ok, atk_ok == 4)
		_ok("法師有 cast 幀集（詠唱段有專屬動作）", mage_cast.size() >= 2)

		# ── 分鏡時間軸自洽（段長之和 == TOTAL_SEC）──
		var total := float(consts.get("TOTAL_SEC", -1.0))
		var sum := float(intro.call("timeline_total_sec"))
		_ok("分鏡時間軸自洽：各段之和 %.1f == TOTAL_SEC %.1f" % [sum, total],
			total > 0.0 and absf(sum - total) < 0.01)
		_ok("片長為 30 秒級（TOTAL_SEC ∈ [25, 35]；實得 %.1f）" % total,
			total >= 25.0 and total <= 35.0)

		# ── 打鬥：魔王血條 + 受擊落點 ──
		var hp_back := intro.get_node_or_null("DemonHpBack") as ColorRect
		var hp_fill := intro.get_node_or_null("DemonHpFill") as ColorRect
		_ok("魔王血條節點存在（底 + 填充）", hp_back != null and hp_fill != null)
		var demon_hit: Vector2 = consts.get("DEMON_HIT", Vector2.ZERO)
		_ok("魔王受擊落點在畫面內且靠魔王側（x ∈ 320..420；實得 %.0f）" % demon_hit.x,
			demon_hit.x >= 320.0 and demon_hit.x <= 420.0)
		_ok("打鬥段時長合計 ≥ 9 秒（⑧–⑫）",
			float(consts.get("T_ATK_WAR", 0.0)) + float(consts.get("T_ATK_ARC", 0.0))
			+ float(consts.get("T_ATK_MAGE", 0.0)) + float(consts.get("T_COUNTER", 0.0))
			+ float(consts.get("T_COMBO", 0.0)) >= 9.0)

		# ── 覺醒立繪：4 張都要真的載得到，且 512×768 ──
		var art_dir := String(consts.get("AWAKEN_ART_DIR", ""))
		_ok("覺醒立繪路徑模板非空", art_dir != "")
		var art_ids: Array[String] = ["ember_lord", "warrior", "archer", "mage"]
		var art_ok := 0
		for cid in art_ids:
			var p := art_dir % cid
			if not ResourceLoader.exists(p):
				_info("覺醒立繪缺檔：%s" % p)
				continue
			var t: Variant = ResourceLoader.load(p)
			if t is Texture2D and (t as Texture2D).get_width() == 512 \
					and (t as Texture2D).get_height() == 768:
				art_ok += 1
			else:
				_info("覺醒立繪尺寸異常：%s → %s"
					% [p, "null" if t == null else str((t as Texture2D).get_size())])
		_ok("四張覺醒立繪皆為 512×768（%d/4）" % art_ok, art_ok == 4)

		# ── 覺醒卡層：節點齊備，且終態不顯示 ──
		var awk_root := intro.get_node_or_null("AwakenRoot") as Control
		var awk_art := intro.get_node_or_null("AwakenRoot/AwakenArt") as TextureRect
		var awk_name := intro.get_node_or_null("AwakenRoot/AwakenName") as Label
		var awk_title := intro.get_node_or_null("AwakenRoot/AwakenTitle") as Label
		_ok("覺醒卡層節點齊備（Root / Art / Name / Title）",
			awk_root != null and awk_art != null and awk_name != null and awk_title != null)
		_ok("覺醒卡立繪等比縮入（contain —— 2:3 豎版不裁切頭腳）",
			awk_art != null and awk_art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		# 立繪框與角色名框不得重疊（否則名字會壓在角色身上）
		var art_rect: Rect2 = consts.get("AWK_ART_RECT", Rect2())
		var name_rect: Rect2 = consts.get("AWK_NAME_RECT", Rect2())
		_ok("覺醒卡版面：立繪框與角色名框不重疊（art.x2=%.0f ≤ name.x1=%.0f）"
			% [art_rect.end.x, name_rect.position.x],
			art_rect.end.x <= name_rect.position.x + 0.01)
		_ok("終態：覺醒卡不顯示", awk_root != null and not awk_root.visible)
		# ⚠️ 實測踩到：覺醒卡 z 若低於字幕（Z_TEXT=10），暗幕蓋不住字幕，
		#    角色名會和「勇者斗恶魔」疊在同一行。這條斷言把圖層序釘死。
		var z_awaken := int(consts.get("Z_AWAKEN", -1))
		var z_text := int(consts.get("Z_TEXT", -1))
		_ok("覺醒卡圖層壓在字幕之上（Z_AWAKEN=%d > Z_TEXT=%d）" % [z_awaken, z_text],
			z_awaken > z_text)
		_ok("終態：魔王血條已收掉", hp_back != null and is_equal_approx(hp_back.color.a, 0.0))
		_ok("終態：無殘留的一次性特效（_fx_actors 空）",
			(intro.get("_fx_actors") as Array).is_empty())

		# ── 字幕文案 ──
		var sub1 := intro.get_node_or_null("Subtitle1") as Label
		var sub2 := intro.get_node_or_null("Subtitle2") as Label
		var prompt := intro.get_node_or_null("Prompt") as Label
		_ok("副標題1 = 「勇者斗恶魔」", sub1 != null and sub1.text == "勇者斗恶魔")
		_ok("副標題2 = 「三职业勇者 · 共伐魔王」",
			sub2 != null and sub2.text == "三职业勇者 · 共伐魔王")
		_ok("底部提示 = 「按任意键开始」", prompt != null and prompt.text == "按任意键开始")

		# ── 無頭 ⇒ _ready 即落終態 ──
		_ok("無頭下 _ready 即落終態（_sequence_done）", bool(intro.get("_sequence_done")))
		_ok("終態：背景不透明度 = 1",
			backdrop != null and is_equal_approx(backdrop.modulate.a, 1.0))
		_ok("終態：魔王不透明度 = 1（已顯形）",
			demon != null and is_equal_approx(demon.modulate.a, 1.0))
		var glow := intro.get_node_or_null("DemonGlow") as TextureRect
		# ⚠️ 峰值不透明度**從片頭腳本自己的常量讀**（不在此硬編碼副本 ⇒ 免得改了數值這裡照樣綠）
		var glow_alpha := float(consts.get("GLOW_ALPHA", -1.0))
		_ok("終態：魔王紅光 = 峰值不透明度 %.2f（已亮起；實得 %s）"
			% [glow_alpha, "null" if glow == null else "%.2f" % glow.modulate.a],
			glow != null and glow_alpha > 0.0 and absf(glow.modulate.a - glow_alpha) < 0.01)
		var embers := intro.get_node_or_null("Embers") as CPUParticles2D
		_ok("終態：火星粒子已發射", embers != null and embers.emitting)
		for n in ["TitleEmblem", "Subtitle1", "Subtitle2", "Prompt"]:
			var c := intro.get_node_or_null(n) as CanvasItem
			_ok("終態：%s 不透明度 = 1" % n, c != null and is_equal_approx(c.modulate.a, 1.0))

		# ── 三勇者真的走到終點（不是停在畫面外）──
		# ⚠️ 站位一律**從片頭腳本自己的常量讀**（`get_script_constant_map()`），
		#    不在此硬編碼一份副本 —— 否則腳本改了站位、這裡照樣全綠（自洽式偽校驗）。
		var feet_xs: Array = consts.get("HERO_FEET_XS", [])
		_ok("片頭站位常量 HERO_FEET_XS 有 3 項", feet_xs.size() == 3)
		var at_target := 0
		if feet_xs.size() == hero_names.size():
			for i in hero_names.size():
				var h := intro.get_node_or_null(hero_names[i]) as Sprite2D
				if h != null and absf(h.position.x - float(feet_xs[i])) < 0.5:
					at_target += 1
				elif h != null:
					_info("勇者 %s x=%.1f（期望 %.1f）" % [hero_names[i], h.position.x, feet_xs[i]])
		_ok("終態：三勇者都走到列隊位（x = %s；%d/3）" % [str(feet_xs), at_target], at_target == 3)

		# ── 版面：全部可見 Control 落在視口內（規範 §6.1）──
		var ctrls: Array = []
		_scan_visible_controls(intro, ctrls)
		var oob: Array = []
		for c in ctrls:
			var r: Rect2 = (c as Control).get_global_rect()
			if r.position.x < 0.0 or r.position.y < 0.0 \
					or r.end.x > 640.0 or r.end.y > 360.0:
				oob.append([intro.get_path_to(c as Node), r])
		_ok("全部可見 Control（%d 個）落在 0..640 × 0..360 內" % ctrls.size(), oob.is_empty())
		for v in oob:
			_info("越界控件：%s rect=%s" % [str(v[0]), str(v[1])])

		if intro.get_parent() != null:
			intro.queue_free()
		await _wait_frames(2)


	# -------------------------------------------------------------------------
	# B. 啟動分流（main → main_menu）＋ 片頭自己的出口（intro → main_menu）
	# -------------------------------------------------------------------------

	func _part_b_boot_chain() -> void:
		print("--- B. 啟動分流（main → main_menu；片頭未接入）---")
		SceneManager.fade_duration = 0.0
		var err := get_tree().change_scene_to_file(BOOT_SCENE)
		_ok("啟動分流場景 main.tscn 可載入（err=%d）" % err, err == OK)
		if err != OK:
			return

		var menu := await _wait_for_scene(SceneManager.SCENE_MAIN_MENU)
		# ⚠️ 2026-10-08 用戶裁定「**片頭先不接入遊戲**」⇒ 啟動**直進主菜單**才是預期行為。
		#    這條斷言的作用是「釘住該裁定」：哪天有人把片頭接回啟動流程，這裡會轉紅提醒。
		_ok("正常啟動直進主菜單（片頭未接入 —— 用戶 2026-10-08 裁定）", menu != null)
		if menu == null:
			return
		_ok("主菜單是 CanvasLayer 且掛 MainMenuPanel",
			menu is CanvasLayer and _find_by_class(menu, "MainMenuPanel") != null)

		print("--- B2. 片頭自己的出口（intro → main_menu）---")
		var err2 := get_tree().change_scene_to_file(INTRO_SCENE)
		_ok("片頭場景可獨立作為 current_scene 載入（err=%d）" % err2, err2 == OK)
		if err2 != OK:
			return
		var intro := await _wait_for_scene(SceneManager.SCENE_INTRO)
		_ok("片頭獨立載入成功（不依賴啟動流程）", intro != null)
		if intro == null:
			return
		_ok("片頭是 CanvasLayer 且掛 IntroScreen",
			intro is CanvasLayer and intro.has_method("next_scene_path"))
		intro.call("_finish")
		var back := await _wait_for_scene(SceneManager.SCENE_MAIN_MENU)
		_ok("片頭 _finish() → 真的回到主菜單", back != null)


	func _find_by_class(root: Node, cls: String) -> Node:
		for c in root.get_children():
			if c.is_class(cls) or (c.get_script() != null
					and String((c.get_script() as Script).get_global_name()) == cls):
				return c
			var r := _find_by_class(c, cls)
			if r != null:
				return r
		return null
