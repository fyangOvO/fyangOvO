## UI 皮膚層（UI Skin Layer）· 素材 → 樣式工廠
##
## 職責：把 `assets/ui/quest/`（任務 UI 素材包）與 `assets/ui/quest/backdrops/`（生態背景）
## 變成 Godot 的 `StyleBoxTexture` / `Texture2D`，供各面板（封面 / 關卡 HUD / 裝備欄）套用。
##
## 為什麼單獨一層（而不是散在各面板裡拼路徑）
## ------------------------------------------
## 專案既有的**內容替換層**鐵律：所有美術資源都必須可被玩家用 `user://content/<類別>/`
## 覆蓋（見 `content_paths.gd` 的類註釋）。UI 皮膚是新素材類別（`ContentPaths.CLASS_UI`），
## 若每個面板各寫各的路徑，這條鏈就會像 `CLASS_UI` 之前那樣**鉤子建好、零消費者**。
## 本類是 UI 素材的**唯一**解析入口，所有面板一律走這裡 → 用戶把檔案丟進
## `user://content/ui/quest/…` 即可替換，不必改代碼、不必重新打包。
##
## 三級優先（與 `ContentPaths` 一致）
## --------------------------------
##   ① `user://content/ui/<相對路徑>`   用戶覆蓋（最高）
##   ② `res://assets/ui/quest/<相對路徑>` 隨包內建
##   ③ 缺素材 → 工廠回傳 `null`           調用方回退到 `UITheme` 的 StyleBoxFlat
##
## ⚠️ **缺素材必須安全降級**：本類任何工廠方法在素材缺失時一律回傳 `null` / 空字典，
##    **絕不拋錯、絕不黑屏**。調用方（封面 / HUD / 裝備欄）拿到 `null` 就沿用既有的
##    程序化 `UITheme` 樣式 —— 這也是「把 `assets/ui/quest/` 整包移走，遊戲照樣跑」的保證。
##
## 用法：
##   var sb := UISkin.panel_stylebox()          # StyleBoxTexture 或 null
##   if sb != null: panel.add_theme_stylebox_override("panel", sb)
##   var boxes := UISkin.btn_styleboxes("gold") # {"normal":..,"hover":..,"pressed":..}
class_name UISkin
extends RefCounted

## 內建素材根目錄（用戶層為 `user://content/ui/`，相對路徑一致）
const BUILTIN_ROOT: String = "res://assets/ui/quest"

## 9-slice 邊距（像素）。SPEC.md 規定任務面板為 **8px**（四角鉚釘 + 邊框完整保留）。
const PANEL_MARGIN: int = 8
## 按鈕貼圖 96×24，邊距 6px（保留描邊與角，中央拉伸放字）。
const BTN_MARGIN: int = 6
## 物品格貼圖 48×48，邊距 4px（保留 1px 硬描邊 + 內縮）。
const SLOT_MARGIN: int = 4

## 邏輯名 → 相對路徑（相對 `BUILTIN_ROOT`；用戶層同構）。
## ⚠️ 相對路徑即**用戶覆蓋契約**：改名等於破壞玩家既有的 `user://content/ui/` 佈局。
const TEX: Dictionary = {
	# 面板 / 橫幅 / 分隔
	"panel": "quest_panel_9slice.png",
	"banner": "quest_banner_256x48.png",
	"divider": "divider_160x8.png",
	"marker": "quest_marker_24.png",
	# 按鈕三態（金系主按鈕 / 藍灰次按鈕）
	# ⚠️ 128×24（規範 C6）：2× 整數放大 ⇒ 顯示 256×48。舊 96×24 在 296px 內容區裡
	#    左右各空 52px，讀成「按鈕太窄」。**改尺寸必須同步改 `verify_ui_assets.gd`
	#    的 `EXPECT_TEX` 與 `BTN_SIZE` 斷言**，否則回歸立刻變紅。
	"btn_gold_normal": "btn_gold_normal_128x24.png",
	"btn_gold_hover": "btn_gold_hover_128x24.png",
	"btn_gold_pressed": "btn_gold_pressed_128x24.png",
	"btn_dark_normal": "btn_dark_normal_128x24.png",
	"btn_dark_hover": "btn_dark_hover_128x24.png",
	"btn_dark_pressed": "btn_dark_pressed_128x24.png",
	# 物品格（默認 / 選中 / 五階稀有度）
	"slot_normal": "slot_normal_48.png",
	"slot_selected": "slot_selected_48.png",
	"slot_common": "slot_common_48.png",
	"slot_rare": "slot_rare_48.png",
	"slot_epic": "slot_epic_48.png",
	"slot_legend": "slot_legend_48.png",
	"slot_orange": "slot_orange_48.png",
	# 高階稀有度（2026-09-21 補缺口）：神話紅 / 套裝綠 / 隱藏彩虹
	"slot_mythic": "slot_mythic_48.png",
	"slot_set": "slot_set_48.png",
	"slot_hidden": "slot_hidden_48.png",
	# 星級 / 背景
	# ⚠️ 2026-09-21 之前 `star_lit_16.png` **真的是四角十字**（檔名說謊，見規範 L3）；
	#    已由 `quest_pack_gen.py` 重導為**真五角星**（16×16，亮 `D9A521` / 暗 `3A424F`，
	#    描邊 `0B0D10`）。**檔名不變** ⇒ 本表與消費方零改動。
	"star_lit": "star_lit_16.png",
	"star_dim": "star_dim_16.png",
	"backdrop_forest": "backdrops/backdrop_forest_640x360.png",
	"backdrop_frost": "backdrops/backdrop_frost_640x360.png",
	"backdrop_volcanic": "backdrops/backdrop_volcanic_640x360.png",
	# ── 2026-09-21 用戶像素素材包接入（`ui/`）─────
	# 用戶原話「ui素材優先用這裡面的」。面板 / 槽位 / 稀有度框 / 三張生態背景
	# 是**同名替換**（檔名不變、內容換成包裡的）⇒ 本表與消費方零改動。
	# 以下這批是包**新增**、遊戲原本沒有的件，故在此追加邏輯名。
	#
	# ⚠️ 封面主菜單背景：包提供 `main_menu_bg_640x360.png`（暗色地牢 + 紅星空）。
	#    它由 `main_menu_screen.gd` 的 `_build_backdrop()` 優先使用，生態 backdrop 作回退。
	"main_menu_bg": "main_menu_bg_640x360.png",
	# 血 / 藍條（160×16，凹槽 + 金屬端帽）。填滿一律靠**代碼裁切**，不要拉伸端帽。
	"bar_hp": "bar_hp_160x16.png",
	"bar_mp": "bar_mp_160x16.png",
	# 技能欄槽（48×48，斜切角 + 四角鉚釘）與四個技能圖標。
	# ⚠️ 圖標與技能的對應關係見 `level_scene.gd` 的 `SKILL_BAR`——**不要憑檔名猜**，
	#    以 `game/data/skills.json` 的真實 id 為準。
	"skill_slot": "skill_slot_48.png",
	"skill_icon_slash": "skill_icon_slash_48.png",
	"skill_icon_fireburst": "skill_icon_fireburst_48.png",
	"skill_icon_frostnova": "skill_icon_frostnova_48.png",
	"skill_icon_shadowdash": "skill_icon_shadowdash_48.png",
	# 2026-09-21 補缺口：雷系閃電鏈 / 毒系毒雲
	"skill_icon_lightning_chain": "skill_icon_lightning_chain_48.png",
	"skill_icon_poison_cloud": "skill_icon_poison_cloud_48.png",
	"skill_icon_piercing_shot": "skill_icon_piercing_shot_48.png",
	"skill_icon_arrow_rain": "skill_icon_arrow_rain_48.png",
	# ── 2026-09-22 首頁定稿：標題 LOGO 底板 + 燙金字 + 火把 + 三職業立繪 ──
	# 標題徽章（336×112，金框龍紋 + 深色銘牌 + 副標題已烘焙）與燙金像素字（240×64）
	"title_emblem": "title_emblem.png",
	"title_text": "title_text.png",
	# 壁掛火把（80×80，含火焰；動態氛圍由場景層做 flicker + 火星粒子）
	"torch": "torch.png",
	# 三職業立繪（188×250 透明底；首頁展示戰士，弓/法為步驟 2 角色選擇備用）
	"portrait_warrior": "portraits/char_warrior.png",
	"portrait_archer": "portraits/char_archer.png",
	"portrait_mage": "portraits/char_mage.png",
}

## 稀有度（`GameConstants.Rarity` 下標）→ 格子貼圖名。
##
## 素材只給 5 階，色階對齊 `PALETTE_RARITY_SEMANTIC` = [白, 藍, 黃, 紫, 橙]，
## 正好對應 Rarity 0..4（COMMON/MAGIC/RARE/EPIC/LEGENDARY）。
## ⭐ **檔名不等於稀有度語義**（`slot_rare_48` 實為魔法藍框、`slot_epic_48` 實為稀有黃框），
## 故用一個顯式表對齊「色階序號」，**嚴禁**照檔名對映（會整體偏一檔）。
##
## 5 階以上 2026-09-21 已補專屬素材（神話紅 / 套裝綠 / 隱藏彩虹），不再 clamp 到橙。
const RARITY_SLOT: Dictionary = {
	0: "slot_common",  # COMMON    白
	1: "slot_rare",    # MAGIC     藍
	2: "slot_epic",    # RARE      黃
	3: "slot_legend",  # EPIC      紫
	4: "slot_orange",  # LEGENDARY 橙
	5: "slot_mythic",  # MYTHIC    紅
	6: "slot_set",     # SET       綠
	7: "slot_hidden",  # HIDDEN    彩
}

## 會話內貼圖快取（缺失也快取為 null，避免每幀重複 IO）
static var _cache: Dictionary = {}


# =============================================================================
# 路徑與貼圖
# =============================================================================

## 解析邏輯名對應的**實際可用路徑**（用戶覆蓋優先）；都無 → `""`。
static func path_for(name: String) -> String:
	var rel := str(TEX.get(name, ""))
	if rel.is_empty():
		return ""
	return ContentPaths.resolve_with_user(
		ContentPaths.CLASS_UI, rel, "%s/%s" % [BUILTIN_ROOT, rel])


## 取貼圖（帶快取）；缺失回傳 `null`（安全降級）。
static func texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var tex := _load(path_for(name))
	_cache[name] = tex
	return tex


## 該邏輯名的素材是否存在且可載入。
static func has(name: String) -> bool:
	return texture(name) != null


## 清快取（用戶運行時替換檔案後可調用）。
static func clear_cache() -> void:
	_cache.clear()


# =============================================================================
# 樣式工廠（全部「缺失即 null」）
# =============================================================================

## 9-slice 面板樣式（任務面板底板）。缺失 → `null`（調用方沿用 StyleBoxFlat）。
static func panel_stylebox() -> StyleBoxTexture:
	return _stylebox("panel", PANEL_MARGIN)


## 按鈕三態樣式。`kind` ∈ {"gold", "dark"}。
## 回傳 `{normal, hover, pressed}`（**只含載入成功的態**）；全缺 → `{}`。
## 調用方約定：拿到空字典就完全不覆蓋 → 沿用 `UITheme` 的 StyleBoxFlat 三態。
static func btn_styleboxes(kind: String) -> Dictionary:
	var out: Dictionary = {}
	for state in ["normal", "hover", "pressed"]:
		var sb := _stylebox("btn_%s_%s" % [kind, state], BTN_MARGIN)
		if sb != null:
			out[state] = sb
	return out


## 物品格樣式。`kind` ∈ {"normal", "selected"} 或任一 `TEX` 裡的 slot_* 名。
static func slot_stylebox(kind: String) -> StyleBoxTexture:
	return _stylebox(kind, SLOT_MARGIN)


## 依稀有度（`GameConstants.Rarity`）取格子樣式；越界安全折到合法檔。
static func slot_stylebox_rarity(rarity: int) -> StyleBoxTexture:
	var name := str(RARITY_SLOT.get(rarity, "slot_normal"))
	return slot_stylebox(name)


## 生態背景（尺寸即視口 640×360）。`biome` ∈ {forest, frost, volcanic}；
## 未知生態回退 forest；都缺 → `null`。
static func backdrop_texture(biome: String) -> Texture2D:
	var key := "backdrop_%s" % biome
	if not TEX.has(key):
		key = "backdrop_forest"
	return texture(key)


## 任務星級（難度）貼圖。`lit` = 是否點亮。
static func star_texture(lit: bool) -> Texture2D:
	return texture("star_lit" if lit else "star_dim")


# =============================================================================
# 內部
# =============================================================================

## 由邏輯名建 StyleBoxTexture（9-slice 四邊同邊距）；素材缺失 → `null`。
static func _stylebox(name: String, margin: int) -> StyleBoxTexture:
	var tex := texture(name)
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = float(margin)
	sb.texture_margin_right = float(margin)
	sb.texture_margin_top = float(margin)
	sb.texture_margin_bottom = float(margin)
	return sb


## 通用貼圖載入（res:// 走導入系統，user:// 直接解碼）—— 與 `ContentLoader` 同策略。
## UI 皮膚自持一份，避免跨模組調用其私有 `_load_any`。
static func _load(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("user://"):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
		return null
	if ResourceLoader.exists(path):
		var r: Resource = ResourceLoader.load(path)
		if r is Texture2D:
			return r
	return null
