## UI 素材接入实测（任務 T2 §5.2/§5.5/§5.6 · 開發用，不屬於遊戲玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_ui_assets.tscn
##   退出碼 0 = 全部通過；1 = 有失敗項
##
## 為什麼需要它（**驗結果，不驗函式被呼叫**）
## -----------------------------------------
## 本專案反覆踩到「斷言全綠但實際上沒生效」。所以本工具**不**斷言
## 「`UISkin.panel_stylebox()` 被呼叫過」，而是斷言：
##   · 貼圖**真的載得進**（`Texture2D != null` 且尺寸正確）；
##   · 裝備圖標**真的能為 62 件裝備解析出貼圖**（此前 62/62 全斷鏈）；
##   · 場景**真的**把皮膚掛上節點（`get_theme_stylebox()` 解析出 `StyleBoxTexture`）；
##   · 敵人**真的**解析出真精靈幀（不是占位色塊），玩家動畫集真的載入。
##
## 覆蓋範圍：
##   A. UISkin 素材解析（27 張貼圖尺寸 + 樣式工廠 + 缺素材安全降級）
##   B. 裝備圖標接線（62 件 icon_path 全部載得進；唯一名 15 枚）
##   C. 封面接線（backdrop 貼圖 / 壓暗疊層 / 內容塊 ≤ 視口高 / 按鈕皮膚）
##   D. 關卡 HUD 接線（任務底板 / 任務標記 / 關卡名橫幅）
##   E. 人物真渲染（玩家 pack clips + 全體敵人真精靈）
extends Node

const MENU_SCENE: PackedScene = preload("res://scenes/main/main_menu.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level.tscn")
const LEVEL_ID: String = "ch1_l01"

## UISkin 邏輯名 → 期望尺寸（像素）。尺寸不符 = 素材被換掉或導入設置漂移。
const EXPECT_TEX: Dictionary = {
	"panel": Vector2i(120, 120),
	"banner": Vector2i(256, 48),
	"divider": Vector2i(160, 8),
	"marker": Vector2i(24, 24),
	"btn_gold_normal": Vector2i(128, 24),
	"btn_gold_hover": Vector2i(128, 24),
	"btn_gold_pressed": Vector2i(128, 24),
	"btn_dark_normal": Vector2i(128, 24),
	"btn_dark_hover": Vector2i(128, 24),
	"btn_dark_pressed": Vector2i(128, 24),
	"slot_normal": Vector2i(48, 48),
	"slot_selected": Vector2i(48, 48),
	"slot_common": Vector2i(48, 48),
	"slot_rare": Vector2i(48, 48),
	"slot_epic": Vector2i(48, 48),
	"slot_legend": Vector2i(48, 48),
	"slot_orange": Vector2i(48, 48),
	"slot_mythic": Vector2i(48, 48),
	"slot_set": Vector2i(48, 48),
	"slot_hidden": Vector2i(48, 48),
	"skill_icon_lightning_chain": Vector2i(48, 48),
	"skill_icon_piercing_shot": Vector2i(48, 48),
	"skill_icon_arrow_rain": Vector2i(48, 48),
	"skill_icon_poison_cloud": Vector2i(48, 48),
	"star_lit": Vector2i(16, 16),
	"star_dim": Vector2i(16, 16),
	"backdrop_forest": Vector2i(640, 360),
	"backdrop_frost": Vector2i(640, 360),
	"backdrop_volcanic": Vector2i(640, 360),
	# ── 2026-09-22 首頁定稿：標題 LOGO + 三職業立繪 + 火把 ──
	"title_emblem": Vector2i(336, 112),
	"title_text": Vector2i(240, 64),
	"torch": Vector2i(80, 80),
	"portrait_warrior": Vector2i(188, 250),
	"portrait_archer": Vector2i(188, 250),
	"portrait_mage": Vector2i(188, 250),
}

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 100.0)
	print("===== UI 素材接入實測 =====")
	_test_skin_assets()
	_test_equipment_icons()
	await _test_cover()
	await _test_level_hud_and_actors()
	_finish()


# =============================================================================
# A. UISkin 素材解析
# =============================================================================

func _test_skin_assets() -> void:
	print("--- A. UISkin 素材解析（貼圖尺寸 + 樣式工廠）---")
	var loaded := 0
	for name in EXPECT_TEX:
		var tex := UISkin.texture(name)
		var want: Vector2i = EXPECT_TEX[name]
		var got := Vector2i.ZERO
		if tex != null:
			got = Vector2i(tex.get_width(), tex.get_height())
		if tex != null and got == want:
			loaded += 1
		else:
			_info("素材 %s：期望 %s，實得 %s" % [name, str(want), str(got)])
	_ok("全部 %d 張素材載入且尺寸正確（%d/%d）"
		% [EXPECT_TEX.size(), loaded, EXPECT_TEX.size()], loaded == EXPECT_TEX.size())

	# 用戶覆蓋路徑確實走 ContentPaths（CLASS_UI）
	_ok("path_for(\"panel\") 命中 res:// 內建路徑",
		UISkin.path_for("panel") == "res://assets/ui/quest/quest_panel_9slice.png")

	# 9-slice 面板：型別 + 邊距
	var psb := UISkin.panel_stylebox()
	_ok("panel_stylebox() 為 StyleBoxTexture", psb is StyleBoxTexture)
	if psb is StyleBoxTexture:
		var s := psb as StyleBoxTexture
		_ok("panel 9-slice 邊距 = 8px（四邊）",
			s.texture_margin_left == 8.0 and s.texture_margin_right == 8.0
			and s.texture_margin_top == 8.0 and s.texture_margin_bottom == 8.0)

	# 按鈕三態
	for kind in ["gold", "dark"]:
		var boxes := UISkin.btn_styleboxes(kind)
		_ok("btn_styleboxes(\"%s\") 三態齊全（normal/hover/pressed）" % kind,
			boxes.size() == 3 and boxes.has("normal") and boxes.has("hover")
			and boxes.has("pressed"))

	# 物品格：8 階稀有度全部解析出樣式
	var slot_ok := 0
	for r in range(8):
		if UISkin.slot_stylebox_rarity(r) != null:
			slot_ok += 1
	_ok("slot_stylebox_rarity(0..7) 全部解析出樣式（%d/8）" % slot_ok, slot_ok == 8)
	_ok("slot_stylebox(\"slot_selected\") 非空", UISkin.slot_stylebox("slot_selected") != null)

	# 缺素材安全降級（回傳 null，不拋錯）
	_ok("未知素材名 → null（降級契約）", UISkin.texture("__not_exist__") == null)


# =============================================================================
# B. 裝備圖標接線
# =============================================================================

func _test_equipment_icons() -> void:
	print("--- B. 裝備圖標接線（62 件真的載得進）---")
	var tpls: Dictionary = ConfigLoader.equipment_templates
	_ok("裝備模板數 = 62", tpls.size() == 62)
	var total := 0
	var ok_icon := 0
	var names := {}
	var legs_to_chest := 0
	var legs_total := 0
	for id in tpls:
		var tpl: EquipmentData = tpls[id]
		total += 1
		var tex := ContentLoader.load_icon(tpl.icon_path)
		if tex != null and tex.get_width() == 48 and tex.get_height() == 48:
			ok_icon += 1
		names[tpl.icon_path.get_file()] = true
		if tpl.slot == GameConstants.EquipSlot.LEGS:
			legs_total += 1
			if tpl.icon_path.contains("equip_chest"):
				legs_to_chest += 1
	_ok("62 件裝備 icon_path 全部解析出 48×48 貼圖（%d/%d）" % [ok_icon, total], ok_icon == total)
	_ok("圖標檔全部指向 res://assets/icons/equipment/（無殘留 sprites/items 斷鏈）",
		_check_all_paths(tpls))
	_ok("使用到 15 枚唯一圖標檔", names.size() == 15)
	_info("唯一圖標檔 %d 枚" % names.size())
	# 2026-09-21 補缺口：腿甲已有專屬圖標 equip_legs_48.png（應 0 借胸甲）
	_ok("腿甲全部使用專屬圖標（%d/%d 借胸甲，應為 0）" % [legs_to_chest, legs_total],
		legs_total > 0 and legs_to_chest == 0)


func _check_all_paths(tpls: Dictionary) -> bool:
	for id in tpls:
		var tpl: EquipmentData = tpls[id]
		if not tpl.icon_path.begins_with("res://assets/icons/equipment/"):
			return false
	return true


# =============================================================================
# C. 封面接線
# =============================================================================

func _test_cover() -> void:
	print("--- C. 封面接線 ---")
	var menu := MENU_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var backdrop := menu.get_node_or_null("Backdrop") as TextureRect
	_ok("封面 Backdrop 節點存在且貼圖非空", backdrop != null and backdrop.texture != null)
	if backdrop != null and backdrop.texture != null:
		_ok("封面 backdrop = 640×360",
			backdrop.texture.get_width() == 640 and backdrop.texture.get_height() == 360)
		# ⚠️ 釘住「不能靜默回退到 forest 兜底」：forest 也是 640×360，舊斷言照樣全綠。
		#    `_build_backdrop()` 優先級 = ① 素材包 main_menu_bg → ② 生態 forest。
		#    第三方 DNF 封面已於版權清理移除，回退序不再有 DNF 這一級。
		var pack_bg := UISkin.texture("main_menu_bg")
		if pack_bg != null:
			_ok("封面 backdrop 用的是素材包主菜單背景（而非 forest 兜底）",
				backdrop.texture == pack_bg)
		else:
			var forest := UISkin.backdrop_texture("forest")
			_ok("包背景缺失時回退生態 forest 背景",
				forest != null and backdrop.texture == forest)

	var bg := menu.get_node_or_null("Bg") as ColorRect
	# 規範 §1.1：疊層色取色板內 0B0D10，alpha = 128/255
	_ok("壓暗疊層 = 0B0D10 @ 128/255（規範 §1.1）",
		bg != null and absf(bg.color.a - 128.0 / 255.0) < 0.01
		and Color(bg.color.r, bg.color.g, bg.color.b) == Color("0B0D10"))

	var boxes := _find_vbox_with_min(menu)
	_ok("封面內容塊存在", boxes != null)
	if boxes != null:
		_ok("內容塊高度 ≤ 視口 360（無溢出）", boxes.custom_minimum_size.y <= 360.0)
		_info("內容塊 min size = %s" % str(boxes.custom_minimum_size))

	var btns := _collect_buttons(menu)
	_ok("封面 3 個按鈕", btns.size() >= 3)
	var skinned := 0
	var sized := 0
	for b in btns:
		if b.get_theme_stylebox(&"normal") is StyleBoxTexture:
			skinned += 1
		if b.custom_minimum_size == Vector2(256, 48):
			sized += 1
	_ok("主按鈕已套皮膚（StyleBoxTexture，≥3）", skinned >= 3)
	_ok("主按鈕尺寸 = 256×48（btn 128×24 貼圖 2× 整數，規範 §3 C6）", sized >= 3)
	_info("套皮膚按鈕 %d / 尺寸正確 %d / 共 %d" % [skinned, sized, btns.size()])

	# 規範 §6.1 強化：封面**全部可見 Control** 的**全域** rect 必須完全落在 0..640 × 0..360 內。
	# 舊斷言只檢查 root VBox 的 `custom_minimum_size.y ≤ 360`，既不覆蓋全體控件、
	# 也沒真的判 `get_rect()` 越界（規範 §6.1 明文要求逐控件判全域 rect）。
	# ⚠️ 必須用 `get_global_rect()`：`CenterContainer` 子塊的 `get_rect()` 是**相對父容器**的，
	#    用 `get_rect()` 會誤判（子塊看似落在原點附近，其實已被父容器置中到別處）。
	var ctrls: Array = []
	_scan_visible_controls(menu, ctrls)
	var oob: Array = []
	var max_x := 0.0
	var max_y := 0.0
	for c in ctrls:
		var r: Rect2 = (c as Control).get_global_rect()
		max_x = maxf(max_x, r.end.x)
		max_y = maxf(max_y, r.end.y)
		if r.position.x < 0.0 or r.position.y < 0.0 \
				or r.end.x > 640.0 or r.end.y > 360.0:
			oob.append([menu.get_path_to(c as Node), r])
	_ok("封面全部可見 Control（%d 個）完全落在 0..640 × 0..360 內（規範 §6.1）"
		% ctrls.size(), oob.is_empty())
	for v in oob:
		_info("越界控件：%s rect=%s" % [str(v[0]), str(v[1])])
	_info("封面控件最大右緣 x=%.1f / 最大下緣 y=%.1f" % [max_x, max_y])

	# ── 規範 §1.2 垂直節奏守衛（2026-09-21 補）──────────────────────────────────
	# ⚠️ 為什麼需要它：頂留 8 / 橫幅 96 / 縫 16 / 面板 224 / 底留 16 = **360** 這套節奏
	#    **不是**寫死的座標，而是「內容總高恰好等於視口高」時 `CenterContainer` 均分的
	#    結果。將來誰往 VBox 裡加一行（狀態提示之類），整套節奏會一起平移 ——
	#    而上面那些斷言（內容塊存在 / ≤360 / 全部控件不越界）**照樣全綠**。
	#    這裡把「總高」與三個關鍵邊界釘死，讓「再加一行」立刻變紅。
	# ⚠️ 一律用 `get_global_rect()`：`CenterContainer` 子控件的 `get_rect()` 是
	#    **相對父容器**的座標系，會誤判（規範 §6 陷阱 11）。
	if boxes != null:
		var vr: Rect2 = boxes.get_global_rect()
		_ok("封面 VBox 實測總高 == 360（節奏守衛：再加一行立刻紅；實得 %.1f）" % vr.size.y,
			is_equal_approx(vr.size.y, 360.0))
		# 2026-09-22 定稿：標題區 336×112（徽章底板），頂 == 8。
		# 無頭模式跳過標題浮動 → 頂精確 == 8；容差 0.5 防浮點。
		var banner_box := _find_by_min_size(menu, Vector2(336, 112))
		_ok("標題徽章框存在且頂 == 8（2026-09-22 定稿；實得 %s）"
			% ("null" if banner_box == null else str(banner_box.get_global_rect())),
			banner_box != null
			and absf(banner_box.get_global_rect().position.y - 8.0) <= 0.5)
		var panel := _find_named(menu, "ContentPanel") as Control
		_ok("內容面板節點存在（節奏守衛的參照系）", panel != null)
		if panel != null:
			var pr: Rect2 = panel.get_global_rect()
			_ok("內容面板頂 == 128 且底 == 352（2026-09-22 定稿；實得 top=%.1f bottom=%.1f）"
				% [pr.position.y, pr.end.y],
				is_equal_approx(pr.position.y, 128.0) and is_equal_approx(pr.end.y, 352.0))
			_info("內容面板全域 rect = %s（規範 §1.1 #3 定稿 (160,128,320,224)）" % str(pr))

	# ── 2026-09-22 首頁裝飾層：戰士立繪 / 火把 ×2 / 版本欄 ──────────────────────
	var hero := menu.get_node_or_null("HeroPortrait") as TextureRect
	_ok("戰士立繪已掛載且貼圖非空", hero != null and hero.texture != null)
	if hero != null and hero.texture != null:
		_ok("戰士立繪 = 188×250 原尺寸",
			hero.size == Vector2(188, 250) and hero.position == Vector2(4, 108))
	var torch_count := 0
	for c in menu.get_children():
		if c is TextureRect and str(c.name).begins_with("Torch"):
			torch_count += 1
	_ok("壁掛火把 ×2 已掛載", torch_count == 2)
	_ok("版本欄存在且文字非空",
		(menu.get_node_or_null("VersionLabel") as Label) != null
		and not (menu.get_node_or_null("VersionLabel") as Label).text.is_empty())

	menu.queue_free()
	await get_tree().process_frame


## 按 `custom_minimum_size` 精確查找子控件（深度優先）。
## 用途：標題橫幅框是 `Control` + `custom_minimum_size = (512,96)`，沒有唯一節點名，
## 用尺寸找比用節點路徑穩（不受掛載層級影響）。
func _find_by_min_size(node: Node, want: Vector2) -> Control:
	for c in node.get_children():
		if c is Control and (c as Control).custom_minimum_size == want:
			return c as Control
		var r := _find_by_min_size(c, want)
		if r != null:
			return r
	return null


## 按**名字**深度優先查找節點（含自身子樹）。
func _find_named(node: Node, target: String) -> Node:
	if str(node.name) == target:
		return node
	for c in node.get_children():
		var r := _find_named(c, target)
		if r != null:
			return r
	return null


## 收集 `node` 子樹下全部「可見」的 `Control`（含自身遞歸；跨層級展平成一維）。
func _scan_visible_controls(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			out.append(c)
		_scan_visible_controls(c, out)


func _find_vbox_with_min(node: Node) -> VBoxContainer:
	for c in node.get_children():
		if c is VBoxContainer and (c as VBoxContainer).custom_minimum_size.y > 0.0:
			return c as VBoxContainer
		var r := _find_vbox_with_min(c)
		if r != null:
			return r
	return null


func _collect_buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_collect_buttons(c))
	return out


## 統計名稱以 `prefix` 開頭的節點數（難度星級用）。
func _count_named(node: Node, prefix: String) -> int:
	var n := 0
	for c in node.get_children():
		if c.name.begins_with(prefix):
			n += 1
		n += _count_named(c, prefix)
	return n


## HUD 下所有 Control 是否落在 640×360 內（規範 §6.7 防越界）。
func _hud_in_bounds(node: Node) -> bool:
	for c in node.get_children():
		if c is Control:
			var r: Rect2 = (c as Control).get_rect()
			if r.position.x < 0.0 or r.position.y < 0.0 \
					or r.end.x > 640.0 or r.end.y > 360.0:
				_info("越界：%s rect=%s" % [c.name, str(r)])
				return false
		if not _hud_in_bounds(c):
			return false
	return true


# =============================================================================
# D. 關卡 HUD 接線 + E. 人物真渲染
# =============================================================================

func _test_level_hud_and_actors() -> void:
	print("--- D. 關卡 HUD 接線 ---")
	var level := LEVEL_SCENE.instantiate() as LevelScene
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.on_scene_entered({
		"level_id": LEVEL_ID,
		"difficulty_tier": GameConstants.DifficultyTier.NM1,
	})
	await get_tree().process_frame
	await get_tree().process_frame

	# 任務底板：皮膚真的掛上（解析出 StyleBoxTexture，而非主題 StyleBoxFlat）
	var plate := level.get_node_or_null("HUD/QuestPlate") as Panel
	_ok("HUD/QuestPlate 存在", plate != null)
	if plate != null:
		_ok("任務底板解析出 StyleBoxTexture（quest_panel_9slice 已接管）",
			plate.get_theme_stylebox(&"panel") is StyleBoxTexture)

	var marker := level.get_node_or_null("HUD/QuestMarker") as TextureRect
	_ok("HUD/QuestMarker 貼圖非空且可見",
		marker != null and marker.texture != null and marker.visible)

	var banner := level.get_node_or_null("HUD/LevelBanner") as TextureRect
	_ok("HUD/LevelBanner 橫幅貼圖非空且可見",
		banner != null and banner.texture != null and banner.visible)

	var btext := level.get_node_or_null("HUD/LevelBannerText") as Label
	_ok("關卡名橫幅文字非空", btext != null and not btext.text.is_empty())
	if btext != null:
		_info("橫幅文字 = %s" % btext.text)

	# HP 外框板（規範 §2.2）：9-slice 接管；血條本體零改動（純自繪）
	var hp_frame := level.get_node_or_null("HUD/HpFrame") as Panel
	_ok("HUD/HpFrame 解析出 StyleBoxTexture（HP 外框，規範 §2.2）",
		hp_frame != null and hp_frame.get_theme_stylebox(&"panel") is StyleBoxTexture)

	# 難度星級（規範 §2.1）：5 顆
	_ok("難度星級 5 顆已建立", _count_named(level.get_node("HUD"), "DiffStar") == 5)

	# HUD 落點（規範 §6.7，防越界回歸）
	var obj := level.get_node_or_null("HUD/Objective") as Label
	_ok("HUD/Objective rect = (60,72,152,32)（規範 §6.7）",
		obj != null and obj.get_rect() == Rect2(60.0, 72.0, 152.0, 32.0))
	var hpbar := level.get_node_or_null("HUD/HpBar") as Control
	_ok("HUD/HpBar rect = (24,128,172,16) 且 bar_height = 16（步驟 6 血藍並排）",
		hpbar != null and hpbar.get_rect() == Rect2(24.0, 128.0, 172.0, 16.0)
		and int(hpbar.get("bar_height")) == 16)
	var mpbar := level.get_node_or_null("HUD/MpBar") as Control
	_ok("HUD/MpBar rect = (204,128,96,16) 法力模式（步驟 6）",
		mpbar != null and mpbar.get_rect() == Rect2(204.0, 128.0, 96.0, 16.0)
		and String(mpbar.get("value_kind")) == "mana")
	_ok("HUD 全部 Control 不越界（≤640×360）", _hud_in_bounds(level.get_node("HUD")))

	print("--- E. 人物真渲染 ---")
	# 玩家：真精靈動畫集真的載入
	var p = level._player
	var p_clips := 0
	var p_tex := Vector2.ZERO
	if p != null:
		p_clips = p._clips.size()
		if p.body_sprite != null and p.body_sprite.texture != null:
			p_tex = Vector2(p.body_sprite.texture.get_width(), p.body_sprite.texture.get_height())
	_ok("玩家真精靈動畫集已載入（clips > 0）", p_clips > 0)
	_ok("玩家 body 貼圖非空", p_tex.x > 0.0)
	_info("玩家 clips=%d body_tex=%s" % [p_clips, str(p_tex)])

	# 敵人：逐隻驗證「解析出真精靈幀」而非占位色塊
	var alive := 0
	var real := 0
	var in_view := 0
	var cam: Camera2D = level.get_node_or_null("Camera2D")
	var view := Rect2()
	if cam != null:
		var half := Vector2(640, 360) * 0.5 / cam.zoom
		view = Rect2(cam.global_position - half, half * 2.0)
	for e in level._alive:
		if not is_instance_valid(e):
			continue
		alive += 1
		if e._real_frames.size() > 0:
			real += 1
		if cam != null and view.has_point(e.global_position):
			in_view += 1
	_ok("關卡敵人數 > 0", alive > 0)
	_ok("全部敵人解析出真精靈幀（非占位色塊，%d/%d）" % [real, alive], alive > 0 and real == alive)
	_info("敵人 %d 隻，視野內 %d 隻（視野內數供參考，布局隨機不作為斷言）" % [alive, in_view])

	# 玩家素材：豆包原創 pack 多幀集可載入（walk/attack 八方向；第三方第二套已移除）。
	var player_set := EnemyBase.pack_load_set("player")
	_ok("玩家 pack 多幀素材可載入（frames 非空）",
		player_set is Dictionary and (player_set.get("frames", []) as Array).size() > 0)

	if level.get_parent() != null:
		level.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
