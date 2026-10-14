## 片頭（開場動畫 · 30 秒 · 打鬥 + 覺醒立繪）· 2026-10-08
##
## 主題：**勇者鬥惡魔** —— 三職業勇者並肩出發，與魔王交手，最終覺醒共伐魔王。
##
## 結構：本節點是 `CanvasLayer`（UI 層），`_ready()` 裡程序化建全部子控件
## （與 `main_menu_screen.gd` 同款；`.tscn` 只掛腳本、不擺節點）。
##
## ⚠️ 2026-10-08 用戶裁定「**片頭先不接入遊戲**」⇒ 遊戲啟動不會播它；
##    本場景目前作為**獨立動畫**（`tools/intro_movie.tscn` 錄成 MP4）與驗證標的。
##
## ── 30 秒分鏡時間軸（各段相加 = `timeline_total_sec()` = `TOTAL_SEC`）───────
##   ① `T_BACKDROP`  1.2s  黑幕 → 魔王領域背景淡入（紅光先兆）
##   ② `T_EMBLEM`    1.4s  標題徽記「七傳說」自上下落定 + 金光一閃
##   ③ `T_SUB1`      1.4s  副標題「勇者斗恶魔」打字機
##   ④ `T_HEROES`    2.2s  三職業勇者**保持隊形**自左滑入 → 落步轉待機
##   ⑤ `T_DEMON`     2.4s  魔王顯形：白光爆閃 + 震屏 + 火星爆發 + 紅光脈動
##   ⑥ `T_SUB2`      1.2s  第二行字幕「三职业勇者 · 共伐魔王」打字機
##   ⑦ `T_APPROACH`  1.4s  三勇者整體前壓；魔王蓄力（紅光轉強 + 魔王血條亮起）
##   ⑧ `T_ATK_WAR`   1.8s  劍士突進斬擊（`attack` 幀 + `slash_arc` + `hit_spark`）
##   ⑨ `T_ATK_ARC`   1.8s  遊俠三連射（`bolt_arrow` 飛行 → 命中爆點）
##   ⑩ `T_ATK_MAGE`  2.0s  法師詠唱（`bolt_fire` → `fireburst` 大爆炸）
##   ⑪ `T_COUNTER`   2.4s  魔王反擊（`attack` 幀 + 全屏紅閃 + `ground_meteor` ×3 + 大震屏）
##   ⑫ `T_COMBO`     1.8s  三勇者合擊（`summon_circle` ×3 + `level_up_burst` + 白光吞沒）
##   ⑬ `T_AWK_DEMON` 3.2s  魔王覺醒立繪（`awaken_ember_lord`）
##   ⑭ `T_AWK_HERO`  4.2s  三勇者覺醒立繪連閃（warrior → archer → mage，各 1.4s）
##   ⑮ `T_HOLD`      1.2s  定版停頓 + 徽記再閃
##   ⑯ `T_PROMPT`    0.4s  底部「按任意键开始」淡入（+ 閃爍）
##
## 素材：
##   · 背景 `UISkin.texture("backdrop_volcanic")`（火山 + 岩漿，640×360）
##   · 標題 `UISkin.texture("title_emblem")`（336×112 暗金徽記）
##   · 角色走 `EnemyBase.resolve_character_set(id)`（**唯一精靈解析鏈**：
##     用戶覆蓋 → 素材包多幀集 → 內建單張），因此可被玩家用 `user://content/` 替換。
##   · 打鬥特效走 `FxTable.spawn()`（**資料驅動**，`data/fx.json` 可被用戶整表覆蓋）；
##     大爆炸另走 `res://assets/anim/<name>/`（96×96 整組幀）。
##   · 覺醒立繪 `res://assets/ui/awaken/awaken_<id>.png`（512×768 厚涂，本批新生成）。
##
## ⚠️ 像素鐵律：角色畫布 192（英雄）/ 256（魔王），本場景一律 **0.5× 整數縮放**。
## ⚠️ 精靈以**腳底**對齊（素材內容在畫布內底對齊）⇒ 座標一律給「腳底落點」，
##    由 `_center_from_feet()` 換算成 `Sprite2D` 的中心座標。
## ⚠️ 圖層序一律用顯式 `z_index`（Control 與 Node2D 混排時，同 z 才輪到樹序）。
class_name IntroScreen
extends CanvasLayer

# =============================================================================
# 30 秒分鏡時間軸（秒）—— 各段相加 = `TOTAL_SEC`
# =============================================================================

const T_BACKDROP: float = 1.2
const T_EMBLEM: float = 1.4
const T_SUB1: float = 1.4
const T_HEROES: float = 2.2
const T_DEMON: float = 2.4
const T_SUB2: float = 1.2
const T_APPROACH: float = 1.4
const T_ATK_WAR: float = 1.8
const T_ATK_ARC: float = 1.8
const T_ATK_MAGE: float = 2.0
const T_COUNTER: float = 2.4
const T_COMBO: float = 1.8
const T_AWK_DEMON: float = 3.2
const T_AWK_HERO: float = 4.2
const T_HOLD: float = 1.2
const T_PROMPT: float = 0.4
## 全片長度（秒）。`_ready()` 會校驗「各段之和 == 本值」，避免改了段長忘了同步。
const TOTAL_SEC: float = 30.0

## 每張覺醒立繪的時長（三勇者各一張；魔王那張用 `T_AWK_DEMON`）。
const AWK_CARD_SEC: float = T_AWK_HERO / 3.0

# =============================================================================
# 配置（版面數值集中於此，只改數值不改結構）
# =============================================================================

## 畫面尺寸（視口固定 640×360）。
const VIEW_W: float = 640.0
const VIEW_H: float = 360.0

## 三職業：順序 = 入場順序 = 畫面自左至右 = 出手順序。
const HERO_IDS: Array[String] = ["warrior", "archer", "mage"]
## 勇者一律面朝**東**（魔王在右側）。
const HERO_DIR: String = EnemyBase.DIR_E

## 魔王素材 id（`res://assets/pack/creatures/<id>/`）。
const DEMON_ID: String = "boss_ember_lord"
## 魔王用**正面**（`s`）：最懾人，且火焰劍落在左側＝勇者方向。
## （`w` 是背對鏡頭的側面，氣勢明顯弱於正面。）
const DEMON_DIR: String = EnemyBase.DIR_S

## 精靈縮放（像素鐵律：整數倍）。素材畫布 192（英雄）/ 256（魔王）。
const HERO_SCALE: float = 0.5
const DEMON_SCALE: float = 0.5

## 三勇者終點站位（腳底落點，畫面座標）。間隔 86 ⇒ 內容寬 ~60 之間留 ~26px 空隙。
const HERO_FEET_Y: float = 336.0
const HERO_FEET_XS: Array[float] = [100.0, 186.0, 272.0]
## 入場：三人**保持隊形**整體自畫面左側滑入（「並肩出發」）。
## 起點 = 終點 - `HERO_ENTER_SHIFT` ⇒ 三人位移量相同、間距恆定，中途不會互相穿模。
const HERO_ENTER_SHIFT: float = 340.0
## 入場行進時長（秒）。
const HERO_WALK_SEC: float = 2.00

## 魔王腳底落點（略高於勇者 ⇒ 站在更遠處，形成景深）。
const DEMON_FEET: Vector2 = Vector2(396.0, 298.0)
## 魔王顯形時的起始下墜偏移（px）。
const DEMON_RISE_FROM: float = 20.0

## 標題徽記（336×112）落點與落定前的高度差。
const EMBLEM_POS: Vector2 = Vector2(152.0, 6.0)
const EMBLEM_DROP_FROM: float = 12.0
## 金光一閃的過曝色（modulate > 1 會提亮）。
const EMBLEM_FLASH: Color = Color(1.70, 1.55, 1.15, 1.0)

## 紅光疊層峰值不透明度（加算混合）。
const GLOW_ALPHA: float = 0.72
## 紅光「先兆」不透明度（開場就有一絲，暗示魔王存在）。
const GLOW_FORESHADOW: float = 0.14
## 紅光貼圖邊長 / 相對魔王腳底的偏移 / 繪製邊長。
const GLOW_SIZE: int = 128
const GLOW_OFFSET: Vector2 = Vector2(0.0, -84.0)
const GLOW_DRAW: float = 232.0

## 腳下陰影（讓角色「踩在地上」而不是飄著）。
const SHADOW_SIZE: Vector2 = Vector2(64.0, 16.0)
const SHADOW_ALPHA: float = 0.55
const HERO_SHADOW_PX: Vector2 = Vector2(54.0, 13.0)
const DEMON_SHADOW_PX: Vector2 = Vector2(104.0, 18.0)

## 暗角（壓邊、聚焦中央）。貼圖 160×90 ⇒ 4× 整數放大到 640×360。
const VIGNETTE_W: int = 160
const VIGNETTE_H: int = 90
const VIGNETTE_ALPHA: float = 0.62

## 爆閃峰值不透明度（魔王顯形 / 合擊 / 反擊共用）。
const FLASH_ALPHA: float = 0.55
## 魔王反擊時的全屏紅閃峰值。
const FLASH_RED_ALPHA: float = 0.42
## 合擊白閃峰值（略低於魔王顯形，免得把三道光弧整片洗掉）。
const FLASH_COMBO_ALPHA: float = 0.68
## 震屏幅度（px，整數）與固定抖動序列（**不用隨機**，保證可重現）。
const SHAKE_PATTERN: Array[Vector2] = [
	Vector2(4, -3), Vector2(-4, 3), Vector2(3, 4), Vector2(-3, -4),
	Vector2(2, -2), Vector2(-2, 2), Vector2(1, 1), Vector2.ZERO,
]
## 大震屏（魔王反擊 / 合擊）：幅度更大、步數更多。
const SHAKE_BIG_PATTERN: Array[Vector2] = [
	Vector2(9, -7), Vector2(-9, 7), Vector2(8, 8), Vector2(-8, -8),
	Vector2(6, -5), Vector2(-6, 5), Vector2(4, 5), Vector2(-4, -5),
	Vector2(3, 3), Vector2(-3, -3), Vector2(2, -2), Vector2(-2, 2),
	Vector2(1, 1), Vector2(-1, -1), Vector2(1, 0), Vector2.ZERO,
]

## ── 打鬥落點 ──────────────────────────────────────────────────────────────
## 魔王受擊點（特效落點）：魔王腳底左前方 ≈ 劍刃可及處。
const DEMON_HIT: Vector2 = Vector2(344.0, 276.0)
## 勇者出手高度（精靈中心 y：腳底 336 - 畫布 192×0.5×0.5 = 288）。
const HERO_CENTER_Y: float = 288.0
## 出手點相對勇者中心的水平偏移（朝魔王側）。
const HERO_HAND_DX: float = 20.0
## 前壓距離（三勇者整體位移，保持隊形）。
const HERO_ADVANCE: float = 26.0
## 劍士突進距離（相對前壓後的位置再往前，砍完退回）。
const WAR_LUNGE: float = 40.0

## 魔王血條（落在魔王腳下，不與標題 / 字幕打架）。
const HP_BAR_RECT: Rect2 = Rect2(344.0, 306.0, 104.0, 6.0)
## 血條最終剩餘比例（打完三輪後）。
const HP_FINAL_RATIO: float = 0.12

## 字幕 / 提示落點。
const SUB1_RECT: Rect2 = Rect2(0.0, 122.0, 640.0, 30.0)
const SUB2_RECT: Rect2 = Rect2(0.0, 152.0, 640.0, 20.0)
const PROMPT_RECT: Rect2 = Rect2(0.0, 342.0, 640.0, 16.0)

## ── 覺醒立繪 ──────────────────────────────────────────────────────────────
const AWAKEN_ART_DIR: String = "res://assets/ui/awaken/awaken_%s.png"
## 魔王覺醒卡用哪個 id。
const AWAKEN_DEMON_ID: String = "ember_lord"
## 角色名（遊戲內文案一律**簡體**）。
const AWAKEN_NAMES: Dictionary = {
	"ember_lord": "熔心之主 · 艾姆伯",
	"warrior": "勇者 · 剑士",
	"archer": "勇者 · 游侠",
	"mage": "勇者 · 法师",
}
## 覺醒稱號（技能感）。
const AWAKEN_TITLES: Dictionary = {
	"ember_lord": "觉醒 · 焚世",
	"warrior": "觉醒 · 破军",
	"archer": "觉醒 · 贯日",
	"mage": "觉醒 · 霜华",
}
## 覺醒卡分相界線（**歸一化進度**，乘上該卡時長即為秒）。
const AWK_P_DIM: float = 0.16
const AWK_P_ART: float = 0.37
const AWK_P_NAME: float = 0.53
const AWK_P_HOLD: float = 0.82
## 立繪進場縮放（1.12 → 1.0）。
const AWK_ART_SCALE_FROM: float = 1.12
## 斜向掃光條幾何。
const AWK_SCAN_SIZE: Vector2 = Vector2(190.0, 46.0)
const AWK_SCAN_FROM_X: float = -240.0
const AWK_SCAN_TO_X: float = 820.0

## 立繪顯示框：**左半屏**，立繪整張等比縮入（不裁切）。
## ⚠️ 立繪是 2:3 豎版（512×768），視口是 16:9（640×360）——
##    用 `STRETCH_KEEP_ASPECT_COVERED` 會被裁掉頭與腳（只看到腰部），
##    所以必須用 `KEEP_ASPECT_CENTERED`（contain），並把右半屏讓給角色名 / 稱號。
const AWK_ART_RECT: Rect2 = Rect2(0.0, 0.0, 300.0, 360.0)
## 角色名 / 稱號落點（右半屏）。
const AWK_NAME_RECT: Rect2 = Rect2(300.0, 126.0, 340.0, 46.0)
const AWK_TITLE_RECT: Rect2 = Rect2(300.0, 172.0, 340.0, 26.0)
## 立繪 / 文字之間的分隔金線。
const AWK_DIVIDER_POS: Vector2 = Vector2(292.0, 106.0)
const AWK_DIVIDER_SIZE: Vector2 = Vector2(2.0, 148.0)

## 序列播完後的自動前進等待（秒）。獨立動畫模式（movie）會關掉它。
const AUTO_ADVANCE_SEC: float = 6.0

## 圖層序（顯式，見檔頭 ⚠️）。
const Z_BG: int = -10
const Z_GLOW: int = 1
const Z_SHADOW: int = 2
const Z_VIGNETTE: int = 3
const Z_DEMON: int = 4
const Z_HERO: int = 5
const Z_FX: int = 6
const Z_EMBER: int = 6
const Z_HP: int = 7
const Z_FLASH: int = 9
const Z_TEXT: int = 10
## ⚠️ 覺醒卡必須**壓在所有常規 UI 之上**（含標題徽記與字幕 z=10）——
##    否則暗幕蓋不住字幕，角色名會和副標題疊在同一行（實測踩到）。
const Z_AWAKEN: int = 12

## 色板（取自專案 48 色板 / 職業色）。
const COLOR_GOLD: Color = Color("F5D77A")
const COLOR_TEXT_DIM: Color = Color("D8D2C4")
const COLOR_TEXT_BRIGHT: Color = Color("EDE7DA")
const COLOR_FLASH: Color = Color("FFE7C2")
const COLOR_FLASH_RED: Color = Color("FF6A46")
const COLOR_HP_FILL: Color = Color("D9533B")
const COLOR_HP_BACK: Color = Color("2A1418")

## 素材缺失時的回退底色（色板內近黑）。
const FALLBACK_BG: Color = Color("0B0D10")

# =============================================================================
# 節點（供驗證工具斷言；命名穩定）
# =============================================================================

var _backdrop: TextureRect = null
var _dim: ColorRect = null
var _bottom_shade: ColorRect = null
var _glow: TextureRect = null
var _vignette: TextureRect = null
var _flash: ColorRect = null
var _embers: CPUParticles2D = null
var _burst: CPUParticles2D = null
var _demon: Sprite2D = null
var _demon_canvas: float = 256.0
var _heroes: Array[Sprite2D] = []
var _hero_canvases: Array[float] = []
var _emblem: TextureRect = null
var _sub1: Label = null
var _sub2: Label = null
var _prompt: Label = null
## 魔王血條（底 + 填充）。
var _hp_back: ColorRect = null
var _hp_fill: ColorRect = null
var _hp_ratio: float = 1.0
## 覺醒立繪層。
var _awk_root: Control = null
var _awk_dim: ColorRect = null
var _awk_art: TextureRect = null
var _awk_scan: ColorRect = null
var _awk_divider: ColorRect = null
var _awk_name: Label = null
var _awk_title: Label = null

## 精靈逐幀動畫狀態：`[{node, clips, mode, t, i, fps, once}]`
var _actors: Array = []
## 一次性特效動畫狀態（`anim/<name>/` 整組幀）：`[{node, frames, fps, t, i}]`
var _fx_actors: Array = []
## `anim/<name>/` 幀組快取（name → Array[Texture2D]）。
var _anim_cache: Dictionary = {}
## 覺醒立繪貼圖快取（cid → Texture2D）。
var _awaken_tex_cache: Dictionary = {}
## 本次播放建立的全部 Tween（跳過時統一 kill，避免動畫把終態又拉走）。
var _tweens: Array[Tween] = []
## 提示閃爍 Tween（loop）。
var _blink: Tween = null

## 覺醒卡狀態機（用 `_process` 累進驅動 —— 見檔尾「為何不用 Tween」）。
var _awk_active: bool = false
var _awk_t: float = 0.0
var _awk_dur: float = 1.0

## 序列是否已播完（或已被跳過）。
var _sequence_done: bool = false
## 是否已前進到主菜單。
var _finished: bool = false

## 自動前進開關（錄影 / 抓圖工具會關掉它，避免播到一半被切場景）。
var auto_advance_enabled: bool = true


## 分鏡各段之和（**單一來源**：`TOTAL_SEC` 是它的人為宣稱值，`_ready()` 會校驗一致）。
static func timeline_total_sec() -> float:
	return T_BACKDROP + T_EMBLEM + T_SUB1 + T_HEROES + T_DEMON + T_SUB2 \
		+ T_APPROACH + T_ATK_WAR + T_ATK_ARC + T_ATK_MAGE + T_COUNTER + T_COMBO \
		+ T_AWK_DEMON + T_AWK_HERO + T_HOLD + T_PROMPT


# =============================================================================
# 生命週期
# =============================================================================

func _ready() -> void:
	set_process_unhandled_input(true)
	if not is_equal_approx(timeline_total_sec(), TOTAL_SEC):
		push_warning("[Intro] 分鏡段長之和 %.2f != TOTAL_SEC %.2f —— 改了段長請同步 TOTAL_SEC"
			% [timeline_total_sec(), TOTAL_SEC])
	_build()
	if DisplayServer.get_name() == "headless":
		# 無頭（回歸 / 驗證）：不做動畫，直接落終態 —— 斷言才有確定性。
		_skip_to_end()
		return
	_play()


## SceneManager 遞交載荷（片頭通常為空）
func on_scene_entered(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	print("[Intro] 收到载荷：", payload)


## 片頭結束後要去的場景（**單一來源** = `SceneManager` 常量）。
func next_scene_path() -> String:
	return SceneManager.SCENE_MAIN_MENU


# =============================================================================
# 建構
# =============================================================================

func _build() -> void:
	_build_backdrop()
	_build_bottom_shade()
	_build_glow()
	_build_vignette()
	_build_embers()
	_build_burst()
	_build_flash()
	_build_demon()
	_build_heroes()
	_build_title()
	_build_hp_bar()
	_build_prompt()
	_build_awaken()


## ① 背景：火山 + 岩漿（生態 backdrop），全屏鋪滿；素材缺失 → 純黑底安全降級。
func _build_backdrop() -> void:
	var tex := UISkin.texture("backdrop_volcanic")
	if tex == null:
		tex = UISkin.backdrop_texture("volcanic")

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = FALLBACK_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = Z_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	if tex != null:
		_backdrop = TextureRect.new()
		_backdrop.name = "Backdrop"
		_backdrop.texture = tex
		_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_backdrop.z_index = Z_BG + 1
		_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_backdrop.modulate = Color(1, 1, 1, 0)
		add_child(_backdrop)

	# 壓暗疊層：讓前景角色與字幕從背景裡「浮」出來（暗黑像素風定稿口徑 0B0D10）。
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(FALLBACK_BG.r, FALLBACK_BG.g, FALLBACK_BG.b, 130.0 / 255.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.z_index = Z_BG + 2
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)


## 底部暗帶：壓住背景讓「按任意键开始」可讀，同時給三勇者一個立足的暗面。
func _build_bottom_shade() -> void:
	_bottom_shade = ColorRect.new()
	_bottom_shade.name = "BottomShade"
	_bottom_shade.color = Color(FALLBACK_BG.r, FALLBACK_BG.g, FALLBACK_BG.b, 120.0 / 255.0)
	_bottom_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_shade.z_index = Z_BG + 3
	_bottom_shade.anchor_left = 0.0
	_bottom_shade.anchor_right = 1.0
	_bottom_shade.anchor_top = 1.0
	_bottom_shade.anchor_bottom = 1.0
	_bottom_shade.offset_top = -46.0
	_bottom_shade.offset_bottom = 0.0
	add_child(_bottom_shade)


## 魔王背後的紅光（程序化徑向漸層 + 加算混合）。
func _build_glow() -> void:
	var tex := _make_glow_texture(GLOW_SIZE, Color("E8573F"))
	_glow = TextureRect.new()
	_glow.name = "DemonGlow"
	_glow.texture = tex
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.z_index = Z_GLOW
	_glow.size = Vector2(GLOW_DRAW, GLOW_DRAW)
	_glow.position = DEMON_FEET + GLOW_OFFSET - Vector2(GLOW_DRAW, GLOW_DRAW) * 0.5
	_glow.pivot_offset = Vector2(GLOW_DRAW, GLOW_DRAW) * 0.5
	_glow.modulate = Color(1, 1, 1, GLOW_FORESHADOW)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	add_child(_glow)


## 暗角：壓暗四邊、聚焦中央（160×90 貼圖 4× 整數放大）。
func _build_vignette() -> void:
	_vignette = TextureRect.new()
	_vignette.name = "Vignette"
	_vignette.texture = _make_vignette_texture()
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.z_index = Z_VIGNETTE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.modulate = Color(1, 1, 1, 0)
	add_child(_vignette)


## 火星：金 → 橙紅 → 透明，自下緣緩升（常駐）。
func _build_embers() -> void:
	_embers = _make_particles(26, false)
	_embers.name = "Embers"
	_embers.position = Vector2(320.0, 350.0)
	_embers.z_index = Z_EMBER
	add_child(_embers)


## 火星爆發：魔王顯形那一刻的一次性粒子。
func _build_burst() -> void:
	_burst = _make_particles(70, true)
	_burst.name = "Burst"
	_burst.position = DEMON_FEET
	_burst.spread = 180.0
	_burst.initial_velocity_min = 40.0
	_burst.initial_velocity_max = 110.0
	_burst.gravity = Vector2(0, -10)
	_burst.z_index = Z_EMBER
	add_child(_burst)


func _make_particles(amount: int, one_shot: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _make_dot_texture()
	p.amount = amount
	p.lifetime = 2.4 if not one_shot else 1.6
	p.preprocess = 1.0 if not one_shot else 0.0
	p.emitting = false
	p.one_shot = one_shot
	p.direction = Vector2(0, -1)
	p.spread = 42.0
	p.gravity = Vector2(0, -22)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 34.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(300.0, 8.0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color("F7DD8A"), Color("E8573F"), Color(0.35, 0.10, 0.06, 0.0),
	])
	p.color_ramp = g
	return p


## 爆閃層（魔王顯形 / 反擊 / 合擊共用；顏色由播放時改）。
func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.color = Color(COLOR_FLASH.r, COLOR_FLASH.g, COLOR_FLASH.b, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.z_index = Z_FLASH
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


## 腳下陰影：**掛在角色底下**（作為 `Sprite2D` 的子節點）⇒ 自動跟隨位移、
## 自動繼承 `modulate`（魔王淡入時陰影一起淡入），不必逐幀同步。
## ⚠️ 子節點會**繼承父級 scale**（0.5）⇒ 子 scale 需除以父 scale 還原成目標像素尺寸。
func _attach_shadow(actor: Sprite2D, canvas: float, scale: float, target_px: Vector2) -> void:
	var sh := Sprite2D.new()
	sh.name = "Shadow"
	sh.texture = _make_shadow_texture()
	sh.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sh.centered = true
	sh.modulate = Color(0, 0, 0, SHADOW_ALPHA)
	sh.scale = Vector2(target_px.x / SHADOW_SIZE.x / scale, target_px.y / SHADOW_SIZE.y / scale)
	# 腳底在**局部**座標 = canvas * 0.5（貼圖置中）；往上一點點 ⇒ 螢幕上 ~3px。
	sh.position = Vector2(0.0, canvas * 0.5 - 3.0 / scale)
	# 絕對圖層：陰影統一壓在角色之下（不繼承父 z ⇒ 不會蓋在角色腳上）
	sh.z_as_relative = false
	sh.z_index = Z_SHADOW
	actor.add_child(sh)


## ⑤ 魔王：站在火山前（景深更遠 ⇒ 腳底比勇者高）。
func _build_demon() -> void:
	var art := EnemyBase.resolve_character_set(DEMON_ID)
	var idle := _clip(art, EnemyBase.ANIM_IDLE, DEMON_DIR)
	if idle.is_empty():
		return
	_demon_canvas = float(art.get("canvas", 256.0))
	_demon = Sprite2D.new()
	_demon.name = "DemonLord"
	_demon.texture = idle[0]
	_demon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_demon.scale = Vector2(DEMON_SCALE, DEMON_SCALE)
	_demon.position = _center_from_feet(DEMON_FEET, _demon_canvas, DEMON_SCALE)
	_demon.modulate = Color(1, 1, 1, 0)
	_demon.z_index = Z_DEMON
	add_child(_demon)
	_attach_shadow(_demon, _demon_canvas, DEMON_SCALE, DEMON_SHADOW_PX)
	_register_actor(_demon, _all_clips(art, DEMON_DIR), float(art.get("fps", 12.0)))


## ④ 三勇者：站在前景，保持隊形自左側滑入後列隊面向魔王。
func _build_heroes() -> void:
	for i in HERO_IDS.size():
		var id := HERO_IDS[i]
		var art := EnemyBase.resolve_character_set(id)
		var idle := _clip(art, EnemyBase.ANIM_IDLE, HERO_DIR)
		if idle.is_empty():
			continue
		var canvas := float(art.get("canvas", 192.0))
		var sp := Sprite2D.new()
		sp.name = "Hero%d_%s" % [i, id]
		sp.texture = idle[0]
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.scale = Vector2(HERO_SCALE, HERO_SCALE)
		var target := _center_from_feet(Vector2(HERO_FEET_XS[i], HERO_FEET_Y), canvas, HERO_SCALE)
		sp.position = Vector2(target.x - HERO_ENTER_SHIFT, target.y)
		sp.z_index = Z_HERO
		add_child(sp)
		_attach_shadow(sp, canvas, HERO_SCALE, HERO_SHADOW_PX)
		_heroes.append(sp)
		_hero_canvases.append(canvas)
		_register_actor(sp, _all_clips(art, HERO_DIR), float(art.get("fps", 12.0)))


## ② 標題徽記 + 副標題
func _build_title() -> void:
	var tex := UISkin.texture("title_emblem")
	if tex != null:
		_emblem = TextureRect.new()
		_emblem.name = "TitleEmblem"
		_emblem.texture = tex
		_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_emblem.stretch_mode = TextureRect.STRETCH_SCALE
		_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_emblem.z_index = Z_TEXT
		_emblem.size = Vector2(tex.get_width(), tex.get_height())
		_emblem.position = EMBLEM_POS
		_emblem.pivot_offset = _emblem.size * 0.5
		_emblem.modulate = Color(1, 1, 1, 0)
		add_child(_emblem)

	_sub1 = _make_centered_label("Subtitle1", "勇者斗恶魔", 22, COLOR_GOLD, SUB1_RECT)
	_sub1.modulate = Color(1, 1, 1, 0)
	_sub1.visible_ratio = 0.0
	_sub2 = _make_centered_label("Subtitle2", "三职业勇者 · 共伐魔王", 12, COLOR_TEXT_DIM, SUB2_RECT)
	_sub2.modulate = Color(1, 1, 1, 0)
	_sub2.visible_ratio = 0.0


## 魔王血條（底 + 填充）。開場隱形，前壓段才亮起。
## 底色框比填充**大 1px 一圈** ⇒ 形成深色描邊，免得血條看起來像一塊純色貼紙。
func _build_hp_bar() -> void:
	_hp_back = ColorRect.new()
	_hp_back.name = "DemonHpBack"
	_hp_back.color = Color(COLOR_HP_BACK.r, COLOR_HP_BACK.g, COLOR_HP_BACK.b, 0.0)
	_hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_back.z_index = Z_HP
	_hp_back.position = HP_BAR_RECT.position - Vector2(1.0, 1.0)
	_hp_back.size = HP_BAR_RECT.size + Vector2(2.0, 2.0)
	add_child(_hp_back)

	_hp_fill = ColorRect.new()
	_hp_fill.name = "DemonHpFill"
	_hp_fill.color = Color(COLOR_HP_FILL.r, COLOR_HP_FILL.g, COLOR_HP_FILL.b, 0.0)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_fill.z_index = Z_HP
	_hp_fill.position = HP_BAR_RECT.position
	_hp_fill.size = HP_BAR_RECT.size
	add_child(_hp_fill)
	_hp_ratio = 1.0


## ⑯ 底部提示
func _build_prompt() -> void:
	_prompt = _make_centered_label("Prompt", "按任意键开始", 11, COLOR_TEXT_BRIGHT, PROMPT_RECT)
	_prompt.modulate = Color(1, 1, 1, 0)


## ⑬⑭ 覺醒立繪層：全屏暗幕 + 立繪（cover）+ 斜向掃光 + 角色名 / 稱號。
## ⚠️ 掛在一個**手動給定 640×360** 的 `Control` 之下 —— CanvasLayer 不是 Control，
##    其下子 Control 的 anchors 無法從非 Control 父級解析（會靜默退化成 0×0）。
func _build_awaken() -> void:
	_awk_root = Control.new()
	_awk_root.name = "AwakenRoot"
	_awk_root.position = Vector2.ZERO
	_awk_root.size = Vector2(VIEW_W, VIEW_H)
	_awk_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_awk_root.z_index = Z_AWAKEN
	_awk_root.visible = false
	add_child(_awk_root)

	_awk_dim = ColorRect.new()
	_awk_dim.name = "AwakenDim"
	_awk_dim.color = Color(0.0, 0.0, 0.0, 0.0)
	_awk_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_awk_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_awk_dim.z_index = 0
	_awk_root.add_child(_awk_dim)

	_awk_art = TextureRect.new()
	_awk_art.name = "AwakenArt"
	_awk_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# contain（不裁切）：2:3 豎版立繪在 16:9 視口上整張可見，見 AWK_ART_RECT 註解。
	_awk_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_awk_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_awk_art.modulate = Color(1, 1, 1, 0)
	_awk_art.position = AWK_ART_RECT.position
	_awk_art.size = AWK_ART_RECT.size
	_awk_art.pivot_offset = AWK_ART_RECT.size * 0.5
	_awk_art.scale = Vector2(AWK_ART_SCALE_FROM, AWK_ART_SCALE_FROM)
	_awk_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_awk_art.z_index = 1
	_awk_root.add_child(_awk_art)

	_awk_scan = ColorRect.new()
	_awk_scan.name = "AwakenScan"
	_awk_scan.color = Color(1.0, 0.95, 0.85, 0.28)
	_awk_scan.size = AWK_SCAN_SIZE
	_awk_scan.position = Vector2(AWK_SCAN_FROM_X, 96.0)
	_awk_scan.rotation = -0.42
	_awk_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_awk_scan.z_index = 2
	_awk_root.add_child(_awk_scan)

	# 立繪與文字之間的分隔金線（立繪右緣 270 ⇒ 線放 292，兩邊各留 ~22px 呼吸）。
	_awk_divider = ColorRect.new()
	_awk_divider.name = "AwakenDivider"
	_awk_divider.color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.55)
	_awk_divider.size = AWK_DIVIDER_SIZE
	_awk_divider.position = AWK_DIVIDER_POS
	_awk_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_awk_divider.z_index = 2
	_awk_divider.modulate = Color(1, 1, 1, 0)
	_awk_root.add_child(_awk_divider)

	_awk_name = _make_awaken_label("AwakenName", 30, COLOR_GOLD, AWK_NAME_RECT)
	_awk_title = _make_awaken_label("AwakenTitle", 13, COLOR_TEXT_BRIGHT, AWK_TITLE_RECT)


## 覺醒卡的文字標籤（掛在 `_awk_root` 下，避免與字幕同層互搶）。
func _make_awaken_label(node_name: String, font_size: int, color: Color,
		rect: Rect2) -> Label:
	var lb := Label.new()
	lb.name = node_name
	lb.text = ""
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", font_size)
	lb.add_theme_color_override("font_color", color)
	lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lb.add_theme_constant_override("shadow_offset_x", 1)
	lb.add_theme_constant_override("shadow_offset_y", 2)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.position = rect.position
	lb.size = rect.size
	lb.modulate = Color(1, 1, 1, 0)
	lb.z_index = 3
	_awk_root.add_child(lb)
	return lb


func _make_centered_label(node_name: String, text: String, font_size: int,
		color: Color, rect: Rect2) -> Label:
	var lb := Label.new()
	lb.name = node_name
	lb.text = text
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", font_size)
	lb.add_theme_color_override("font_color", color)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.z_index = Z_TEXT
	lb.position = rect.position
	lb.size = rect.size
	add_child(lb)
	return lb


# =============================================================================
# 播放（30 秒分鏡）
# =============================================================================

func _play() -> void:
	# ① 黑幕 → 背景淡入（紅光先兆）
	if _backdrop != null:
		_tw().tween_property(_backdrop, "modulate:a", 1.0, T_BACKDROP)
	if _vignette != null:
		_tw().tween_property(_vignette, "modulate:a", VIGNETTE_ALPHA, T_BACKDROP)
	if await _pace(T_BACKDROP):
		return

	# ② 標題徽記自上下落定 + 金光一閃
	if _emblem != null:
		_emblem.position.y = EMBLEM_POS.y - EMBLEM_DROP_FROM
		var et := _tw()
		et.tween_property(_emblem, "modulate:a", 1.0, T_EMBLEM * 0.55)
		et.parallel().tween_property(_emblem, "position:y", EMBLEM_POS.y, T_EMBLEM * 0.75) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_flash_emblem(EMBLEM_FLASH, T_EMBLEM * 0.45)
	if await _pace(T_EMBLEM):
		return

	# ③ 副標題1 打字機
	_typewriter(_sub1, T_SUB1)
	if await _pace(T_SUB1):
		return

	# ④ 三勇者保持隊形整體滑入（同一位移量 ⇒ 中途不穿模）
	for i in _heroes.size():
		_set_actor_mode(_heroes[i], "walk")
		_tw().tween_property(_heroes[i], "position:x",
			_center_from_feet(Vector2(HERO_FEET_XS[i], HERO_FEET_Y),
				_hero_canvases[i], HERO_SCALE).x, HERO_WALK_SEC) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if await _pace(T_HEROES * 0.86):
		return
	# 到位 → 切回待機 + 落步微沉
	for i in _heroes.size():
		var sp := _heroes[i]
		_set_actor_mode(sp, "idle")
		var settle := _tw()
		var y := sp.position.y
		settle.tween_property(sp, "position:y", y + 2.0, 0.10)
		settle.tween_property(sp, "position:y", y, 0.16)
	if await _pace(T_HEROES * 0.14):
		return

	# ⑤ 魔王顯形：爆閃 + 震屏 + 火星爆發 + 紅光脈動
	if _flash != null:
		_flash.color = Color(COLOR_FLASH.r, COLOR_FLASH.g, COLOR_FLASH.b, 0.0)
		var ft := _tw()
		ft.tween_property(_flash, "color:a", FLASH_ALPHA, 0.10)
		ft.tween_property(_flash, "color:a", 0.0, T_DEMON * 0.35)
	_shake(SHAKE_PATTERN, T_DEMON * 0.45)
	if _demon != null:
		var base := _center_from_feet(DEMON_FEET, _demon_canvas, DEMON_SCALE)
		_demon.position = base + Vector2(0, -DEMON_RISE_FROM)
		var dt := _tw()
		dt.tween_property(_demon, "modulate:a", 1.0, T_DEMON * 0.30)
		dt.parallel().tween_property(_demon, "position:y", base.y, T_DEMON * 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _glow != null:
		_tw().tween_property(_glow, "modulate:a", GLOW_ALPHA, T_DEMON * 0.35)
		var pulse := _tw()
		pulse.set_loops()
		pulse.tween_property(_glow, "scale", Vector2(1.06, 1.06), 1.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_glow, "scale", Vector2.ONE, 1.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _embers != null:
		_embers.emitting = true
	if _burst != null:
		_burst.restart()
		_burst.emitting = true
	if await _pace(T_DEMON):
		return

	# ⑥ 副標題2 打字機
	_typewriter(_sub2, T_SUB2)
	if await _pace(T_SUB2):
		return

	# ⑦ 前壓 + 魔王血條亮起 + 蓄力紅光
	_show_hp_bar()
	for i in _heroes.size():
		var sp := _heroes[i]
		if sp == null:
			continue
		_set_actor_mode(sp, "walk")
		_tw().tween_property(sp, "position:x", sp.position.x + HERO_ADVANCE, T_APPROACH * 0.75) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _glow != null:
		_tw().tween_property(_glow, "modulate:a", 0.95, T_APPROACH)
	if await _pace(T_APPROACH * 0.78):
		return
	for sp in _heroes:
		_set_actor_mode(sp, "idle")
	if await _pace(T_APPROACH * 0.22):
		return

	# ⑧ 劍士突進斬擊
	await _act_warrior()
	if _sequence_done or _finished or not is_inside_tree():
		return

	# ⑨ 遊俠三連射
	await _act_archer()
	if _sequence_done or _finished or not is_inside_tree():
		return

	# ⑩ 法師詠唱
	await _act_mage()
	if _sequence_done or _finished or not is_inside_tree():
		return

	# ⑪ 魔王反擊
	await _act_counter()
	if _sequence_done or _finished or not is_inside_tree():
		return

	# ⑫ 三勇者合擊
	await _act_combo()
	if _sequence_done or _finished or not is_inside_tree():
		return

	# ⑬ 魔王覺醒立繪
	# ⚠️ 進覺醒段前先把血條收掉：一來終態畫面（定版 + 提示）不該留戰鬥 UI 殘骸，
	#    二來無頭 `_skip_to_end()` 也是收掉的 —— 兩條路徑的終態必須一致，
	#    否則 verify 斷言的是無頭終態、玩家看到的卻是另一個畫面（偽驗收）。
	_hide_hp_bar()
	_awaken_begin(AWAKEN_DEMON_ID, T_AWK_DEMON)
	if await _pace(T_AWK_DEMON):
		return

	# ⑭ 三勇者覺醒立繪連閃
	for cid in HERO_IDS:
		_awaken_begin(cid, AWK_CARD_SEC)
		if await _pace(AWK_CARD_SEC):
			return

	# ⑮ 定版 + 徽記再閃
	_flash_emblem(EMBLEM_FLASH, T_HOLD * 0.6)
	if await _pace(T_HOLD):
		return

	# ⑯ 提示 + 閃爍
	if _prompt != null:
		_tw().tween_property(_prompt, "modulate:a", 1.0, T_PROMPT)
		_blink = _tw()
		_blink.set_loops()
		_blink.tween_interval(1.2)
		_blink.tween_property(_prompt, "modulate:a", 0.3, 0.6)
		_blink.tween_property(_prompt, "modulate:a", 1.0, 0.6)

	_sequence_done = true

	# 自動前進（獨立動畫 / 抓圖工具會把 `auto_advance_enabled` 關掉）
	if auto_advance_enabled and is_inside_tree():
		await get_tree().create_timer(AUTO_ADVANCE_SEC).timeout
		if not _finished:
			_finish()


# =============================================================================
# 打鬥段（⑧–⑫）
# =============================================================================

## ⑧ 劍士：突進 → 斬擊（slash_arc + hit_spark）→ 退回。
func _act_warrior() -> void:
	var sp := _heroes[0] if _heroes.size() > 0 else null
	if sp == null:
		await _pace(T_ATK_WAR)
		return
	var home := sp.position.x
	_set_actor_mode(sp, "walk")
	_tw().tween_property(sp, "position:x", home + WAR_LUNGE, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if await _pace(0.34):
		return
	_set_actor_mode(sp, "attack", true)
	# 斬擊落點：魔王左前方
	_spawn_anim_fx("slash", DEMON_HIT + Vector2(-18.0, -4.0), 26.0, 1.0)
	_hit_demon(DEMON_HIT, "hit_spark", 0.055)
	_shake(SHAKE_PATTERN, 0.34)
	_damage_hp(0.30, 0.34)
	if await _pace(0.62):
		return
	_set_actor_mode(sp, "walk")
	_tw().tween_property(sp, "position:x", home, 0.42) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if await _pace(0.42):
		return
	_set_actor_mode(sp, "idle")
	if await _pace(T_ATK_WAR - 1.38):
		return


## ⑨ 遊俠：三連射（bolt_arrow 逐發飛行 → 命中爆點）。
func _act_archer() -> void:
	var sp := _heroes[1] if _heroes.size() > 1 else null
	if sp == null:
		await _pace(T_ATK_ARC)
		return
	_set_actor_mode(sp, "attack", true)
	var from := _hero_hand(sp)
	var gap := 0.22
	var flight := 0.30
	for k in 3:
		_fly_bolt("bolt_arrow", from + Vector2(0.0, -2.0 * float(k)), DEMON_HIT, flight)
		if await _pace(gap):
			return
		_hit_demon(DEMON_HIT + Vector2(0.0, 6.0 * float(k) - 6.0), "hit_spark", 0.0)
		_damage_hp(0.08, 0.20)
		if k == 0:
			_shake(SHAKE_PATTERN, 0.22)
	if await _pace(0.34):
		return
	_set_actor_mode(sp, "idle")
	if await _pace(T_ATK_ARC - (gap * 3.0 + 0.34)):
		return


## ⑩ 法師：詠唱 → 火球 → 大爆炸（fireburst 96×96 整組幀）。
func _act_mage() -> void:
	var sp := _heroes[2] if _heroes.size() > 2 else null
	if sp == null:
		await _pace(T_ATK_MAGE)
		return
	_set_actor_mode(sp, "cast", true)
	# 詠唱起手：腳下法陣 + 一輪霜爆（預告「這一發很大」）
	FxTable.spawn("summon_circle", Vector2(sp.position.x, HERO_FEET_Y), {"host": self})
	_spawn_anim_fx("frostnova", _hero_hand(sp) + Vector2(0.0, 6.0), 22.0, 0.55)
	if await _pace(0.46):
		return
	_set_actor_mode(sp, "attack", true)
	var from := _hero_hand(sp)
	_fly_bolt("bolt_fire", from, DEMON_HIT, 0.42)
	if await _pace(0.42):
		return
	_spawn_anim_fx("fireburst", DEMON_HIT, 20.0, 1.35)
	if _flash != null:
		var ft := _tw()
		ft.tween_property(_flash, "color:a", 0.30, 0.06)
		ft.tween_property(_flash, "color:a", 0.0, 0.30)
	_shake(SHAKE_PATTERN, 0.42)
	_damage_hp(0.24, 0.40)
	if await _pace(0.78):
		return
	_set_actor_mode(sp, "idle")
	if await _pace(T_ATK_MAGE - 1.66):
		return


## ⑪ 魔王反擊：全屏紅閃 + 大震屏 + 三處隕石砸落 + 三勇者被打退。
func _act_counter() -> void:
	if _demon != null:
		_set_actor_mode(_demon, "attack", true)
	if _glow != null:
		var gt := _tw()
		gt.tween_property(_glow, "modulate:a", 1.0, 0.18)
		gt.tween_property(_glow, "modulate:a", 0.62, 0.70)
	# 起手：地面裂開預兆
	for i in _heroes.size():
		var sp := _heroes[i]
		if sp == null:
			continue
		_spawn_anim_fx("thunder", Vector2(sp.position.x, HERO_FEET_Y - 6.0), 24.0, 0.6)
	if await _pace(0.30):
		return
	# 全屏紅閃 + 大震屏
	if _flash != null:
		_flash.color = Color(COLOR_FLASH_RED.r, COLOR_FLASH_RED.g, COLOR_FLASH_RED.b, 0.0)
		var ft := _tw()
		ft.tween_property(_flash, "color:a", FLASH_RED_ALPHA, 0.08)
		ft.tween_property(_flash, "color:a", 0.0, 0.62)
	_shake(SHAKE_BIG_PATTERN, 0.72)
	# 三勇者被打退 + 受擊幀
	for i in _heroes.size():
		var sp := _heroes[i]
		if sp == null:
			continue
		_spawn_anim_fx("fireburst", Vector2(sp.position.x, HERO_FEET_Y - 26.0), 22.0, 0.7)
		_set_actor_mode(sp, "hurt", true)
		var bt := _tw()
		bt.tween_property(sp, "position:x", sp.position.x - 22.0, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bt.tween_property(sp, "position:x", sp.position.x, 0.30) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if await _pace(0.72):
		return
	for i in _heroes.size():
		var sp := _heroes[i]
		if sp != null:
			_set_actor_mode(sp, "idle")
	if _demon != null:
		_set_actor_mode(_demon, "idle")
	if await _pace(T_COUNTER - 1.02):
		return


## ⑫ 三勇者合擊：三色法陣 + 三道光柱匯於魔王 + 白光吞沒。
func _act_combo() -> void:
	for i in _heroes.size():
		var sp := _heroes[i]
		if sp == null:
			continue
		_set_actor_mode(sp, "cast", true)
		FxTable.spawn("summon_circle", Vector2(sp.position.x, HERO_FEET_Y), {"host": self})
	if _glow != null:
		_tw().tween_property(_glow, "modulate:a", 1.0, 0.30)
	if await _pace(0.44):
		return
	for i in _heroes.size():
		var sp := _heroes[i]
		if sp == null:
			continue
		_set_actor_mode(sp, "attack", true)
		_spawn_anim_fx("slash", Vector2(sp.position.x + 26.0, HERO_CENTER_Y), 28.0, 0.7)
	FxTable.spawn("level_up_burst", DEMON_HIT, {"host": self})
	if _flash != null:
		_flash.color = Color(COLOR_FLASH.r, COLOR_FLASH.g, COLOR_FLASH.b, 0.0)
		var ft := _tw()
		ft.tween_property(_flash, "color:a", FLASH_COMBO_ALPHA, 0.10)
		ft.tween_property(_flash, "color:a", 0.0, 0.52)
	_shake(SHAKE_BIG_PATTERN, 0.66)
	_damage_hp(0.28, 0.30)
	if await _pace(0.66):
		return
	for i in _heroes.size():
		var sp := _heroes[i]
		if sp != null:
			_set_actor_mode(sp, "idle")
	if _demon != null:
		_set_actor_mode(_demon, "idle")
	if await _pace(T_COMBO - 1.10):
		return


## 命中魔王：播一次命中特效 + 魔王受擊提亮。
func _hit_demon(pos: Vector2, fx_id: String, delay: float) -> void:
	if delay > 0.0:
		if await _pace(delay):
			return
	FxTable.spawn(fx_id, pos, {"host": self})
	if _demon == null:
		return
	var t := _tw()
	t.tween_property(_demon, "modulate", Color(1.9, 1.55, 1.35, 1.0), 0.05)
	t.tween_property(_demon, "modulate", Color(1, 1, 1, 1), 0.22)


## 血條掉落（`dur` 秒內降到 `target` 比例）。
func _damage_hp(delta_ratio: float, dur: float) -> void:
	if _hp_fill == null:
		return
	_hp_ratio = clampf(_hp_ratio - delta_ratio, HP_FINAL_RATIO, 1.0)
	_tw().tween_property(self, "_hp_ratio", _hp_ratio, dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 血條亮起（前壓段）。
func _show_hp_bar() -> void:
	if _hp_back == null or _hp_fill == null:
		return
	var t := _tw()
	t.tween_property(_hp_back, "color:a", 0.85, 0.30)
	t.parallel().tween_property(_hp_fill, "color:a", 1.0, 0.30)


## 血條收掉（進覺醒段前）。與 `_skip_to_end()` 的終態一致。
func _hide_hp_bar() -> void:
	if _hp_back == null or _hp_fill == null:
		return
	var t := _tw()
	t.tween_property(_hp_back, "color:a", 0.0, 0.26)
	t.parallel().tween_property(_hp_fill, "color:a", 0.0, 0.26)


# =============================================================================
# 覺醒立繪（⑬⑭）
# =============================================================================

## 開始一張覺醒卡。`dur` 為該卡總時長，內部分相按 `AWK_P_*` 比例縮放。
func _awaken_begin(cid: String, dur: float) -> void:
	if _awk_root == null:
		return
	var tex := _awaken_texture(cid)
	_awk_art.texture = tex
	_awk_art.visible = tex != null
	_awk_name.text = String(AWAKEN_NAMES.get(cid, ""))
	_awk_title.text = String(AWAKEN_TITLES.get(cid, ""))
	_awk_root.visible = true
	_awk_t = 0.0
	_awk_dur = maxf(dur, 0.10)
	_awk_active = true
	_awk_apply(0.0)


## 依歸一化進度 `p` 寫入覺醒卡各節點屬性（**逐幀寫**，見檔尾「為何不用 Tween」）。
func _awk_apply(p: float) -> void:
	if _awk_root == null:
		return
	var dim_a := 0.0
	var art_a := 0.0
	var name_a := 0.0
	if p < AWK_P_DIM:
		dim_a = p / AWK_P_DIM
	elif p < AWK_P_ART:
		dim_a = 1.0
		art_a = (p - AWK_P_DIM) / (AWK_P_ART - AWK_P_DIM)
	elif p < AWK_P_NAME:
		dim_a = 1.0
		art_a = 1.0
		name_a = (p - AWK_P_ART) / (AWK_P_NAME - AWK_P_ART)
	elif p < AWK_P_HOLD:
		dim_a = 1.0
		art_a = 1.0
		name_a = 1.0
	else:
		var o := 1.0 - (p - AWK_P_HOLD) / maxf(1.0 - AWK_P_HOLD, 0.001)
		dim_a = o
		art_a = o
		name_a = o

	_awk_dim.color.a = dim_a * 0.92
	_awk_art.modulate.a = art_a
	_awk_art.scale = Vector2.ONE.lerp(
		Vector2(AWK_ART_SCALE_FROM, AWK_ART_SCALE_FROM), 1.0 - art_a)
	_awk_name.modulate.a = name_a
	_awk_title.modulate.a = name_a
	if _awk_divider != null:
		_awk_divider.modulate.a = name_a
	# 掃光：與立繪同步（art 段起、name 段初掃完）
	var scan_t := clampf((p - AWK_P_DIM) / maxf(AWK_P_NAME - AWK_P_DIM, 0.001), 0.0, 1.0)
	_awk_scan.position.x = lerpf(AWK_SCAN_FROM_X, AWK_SCAN_TO_X, scan_t)
	_awk_scan.modulate.a = art_a


## 覺醒立繪貼圖（缺檔回 null ⇒ 卡片只剩暗幕 + 文字，不崩）。
func _awaken_texture(cid: String) -> Texture2D:
	if _awaken_tex_cache.has(cid):
		return _awaken_tex_cache[cid]
	var tex: Texture2D = null
	var path := AWAKEN_ART_DIR % cid
	if ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path)
		if res is Texture2D:
			tex = res
	else:
		push_warning("[Intro] 覺醒立繪缺失：%s" % path)
	_awaken_tex_cache[cid] = tex
	return tex


# =============================================================================
# 特效
# =============================================================================

## 一次性播放 `res://assets/anim/<name>/` 的整組幀（96×96），播完自動釋放。
## 回傳 false = 該組不存在（呼叫方安全略過）。
func _spawn_anim_fx(name: String, pos: Vector2, fps: float, scale: float) -> bool:
	var frames := _load_anim_frames(name)
	if frames.is_empty():
		return false
	var sp := Sprite2D.new()
	sp.name = "Fx_%s" % name
	sp.texture = frames[0]
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.position = pos
	sp.scale = Vector2(scale, scale)
	sp.z_index = Z_FX
	add_child(sp)
	_fx_actors.append({
		"node": sp, "frames": frames, "fps": maxf(fps, 1.0), "t": 0.0, "i": 0,
	})
	return true


## 載入 `anim/<name>/fx_<name>_NN.png` 幀組（**命名約定探測**，不枚舉目錄 ——
## 導出包內 `DirAccess` 枚舉 `res://` 全廢）。
func _load_anim_frames(name: String) -> Array:
	if _anim_cache.has(name):
		return _anim_cache[name]
	var out: Array = []
	for i in 16:
		var p := "res://assets/anim/%s/fx_%s_%02d.png" % [name, name, i]
		if not ResourceLoader.exists(p):
			break
		var tex: Variant = ResourceLoader.load(p)
		if tex is Texture2D:
			out.append(tex)
	if out.is_empty():
		push_warning("[Intro] 找不到特效幀組：anim/%s/" % name)
	_anim_cache[name] = out
	return out


## 生成一枚飛行的投射物（`FxTable` 序列幀貼圖），到點自動釋放。
## 貼圖缺失時仍等滿 `dur` ⇒ 呼叫方的節奏不變（不會整段塌掉）。
func _fly_bolt(fx_id: String, from: Vector2, to: Vector2, dur: float) -> void:
	var fx := FxTable.spawn(fx_id, from, {"host": self})
	if fx != null:
		# 貼圖只有 4 幀 / 12fps ≈ 0.33s，飛行時間可能更長 ⇒ 讓它循環到抵達為止。
		fx.set("loop", true)
		fx.z_index = Z_FX
		_tw().tween_property(fx, "position", to, dur).set_trans(Tween.TRANS_LINEAR)
	if await _pace(dur):
		return
	if fx != null and is_instance_valid(fx):
		fx.queue_free()


## 勇者出手點（精靈中心 → 胸口高度）。
func _hero_hand(sp: Sprite2D) -> Vector2:
	return Vector2(sp.position.x + HERO_HAND_DX, HERO_CENTER_Y)


# =============================================================================
# 通用動畫工具
# =============================================================================

## 打字機：先淡入，再逐字顯現。
func _typewriter(lb: Label, dur: float) -> void:
	if lb == null:
		return
	_tw().tween_property(lb, "modulate:a", 1.0, dur * 0.18)
	_tw().tween_property(lb, "visible_ratio", 1.0, dur * 0.72) \
		.set_trans(Tween.TRANS_LINEAR)


## 徽記閃光：提亮 → 回白。
func _flash_emblem(peak: Color, dur: float) -> void:
	if _emblem == null:
		return
	var t := _tw()
	t.tween_property(_emblem, "modulate", peak, dur * 0.35)
	t.tween_property(_emblem, "modulate", Color(1, 1, 1, 1), dur * 0.65)


## 震屏：整層 `CanvasLayer.offset` 依固定序列抖動（**不用隨機** ⇒ 可重現）。
func _shake(pattern: Array[Vector2], dur: float) -> void:
	if pattern.is_empty():
		return
	var t := _tw()
	var step := dur / float(pattern.size())
	for v in pattern:
		t.tween_property(self, "offset", v, step)


## 等 `sec` 秒；若期間已被跳過 / 已前進 / 已離樹則回 `true`（呼叫方直接 return）。
func _pace(sec: float) -> bool:
	if not is_inside_tree():
		return true
	if sec > 0.0:
		await get_tree().create_timer(sec).timeout
	return _sequence_done or _finished or not is_inside_tree()


## 跳過：kill 全部 Tween 後直接把畫面拉到終態。
func _skip_to_end() -> void:
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()
	_blink = null

	offset = Vector2.ZERO
	if _backdrop != null:
		_backdrop.modulate.a = 1.0
	if _vignette != null:
		_vignette.modulate.a = VIGNETTE_ALPHA
	if _flash != null:
		_flash.color.a = 0.0
	if _demon != null:
		_demon.modulate.a = 1.0
		_demon.position = _center_from_feet(DEMON_FEET, _demon_canvas, DEMON_SCALE)
	if _glow != null:
		_glow.modulate.a = GLOW_ALPHA
		_glow.scale = Vector2.ONE
	if _embers != null:
		_embers.emitting = true
	if _burst != null:
		_burst.emitting = true
	for i in _heroes.size():
		var sp := _heroes[i]
		if sp == null:
			continue
		sp.position.x = _center_from_feet(Vector2(HERO_FEET_XS[i], HERO_FEET_Y),
			_hero_canvases[i], HERO_SCALE).x
		sp.modulate = Color(1, 1, 1, 1)
		_set_actor_mode(sp, "idle")
	if _demon != null:
		_set_actor_mode(_demon, "idle")
	# 血條：落終態時收掉（覺醒卡 / 提示才是終態畫面）
	if _hp_back != null:
		_hp_back.color.a = 0.0
	if _hp_fill != null:
		_hp_fill.color.a = 0.0
	# 覺醒卡：終態不顯示
	_awk_active = false
	if _awk_root != null:
		_awk_root.visible = false
	# 殘留的一次性特效直接清掉
	for a in _fx_actors:
		var n := a["node"] as Node
		if n != null and is_instance_valid(n):
			n.queue_free()
	_fx_actors.clear()
	for lb in [_emblem, _sub1, _sub2, _prompt]:
		if lb != null:
			lb.modulate.a = 1.0
	if _sub1 != null:
		_sub1.visible_ratio = 1.0
	if _sub2 != null:
		_sub2.visible_ratio = 1.0
	_sequence_done = true


## 前進到主菜單。
func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_process_unhandled_input(false)
	if _blink != null and _blink.is_valid():
		_blink.kill()
	SceneManager.change_scene(next_scene_path())


# =============================================================================
# 輸入
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	var hit := (event is InputEventKey and event.is_pressed() and not event.is_echo()) \
		or (event is InputEventMouseButton and event.is_pressed()) \
		or (event is InputEventJoypadButton and event.is_pressed())
	if not hit:
		return
	get_viewport().set_input_as_handled()
	if not _sequence_done:
		# 第一次輸入 = 跳過片頭（直接落終態，不硬切）
		_skip_to_end()
		return
	_finish()


# =============================================================================
# 精靈逐幀動畫
# =============================================================================

## 把 `resolve_character_set()` 的 clips 抽成「動作 → 該方向幀組」的扁平表。
## 缺的動作給空陣列 ⇒ `_set_actor_mode` 會安全退回 idle（不會卡住不動）。
func _all_clips(art: Dictionary, d: String) -> Dictionary:
	return {
		"idle": _clip(art, EnemyBase.ANIM_IDLE, d),
		"walk": _clip(art, EnemyBase.ANIM_WALK, d),
		"attack": _clip(art, EnemyBase.ANIM_ATTACK, d),
		"cast": _clip(art, "cast", d),
		"hurt": _clip(art, EnemyBase.ANIM_HURT, d),
	}


func _register_actor(node: Sprite2D, clips: Dictionary, fps: float) -> void:
	_actors.append({
		"node": node, "clips": clips, "mode": "idle",
		"t": 0.0, "i": 0, "fps": maxf(1.0, fps), "once": false,
	})


## 切換動作。`once = true` ⇒ 播完最後一幀自動回 idle（攻擊 / 施法 / 受擊用）。
## 該動作缺幀時退回 idle（**不讓角色定格在錯的動作上**）。
func _set_actor_mode(node: Sprite2D, mode: String, once: bool = false) -> void:
	for a in _actors:
		if a["node"] != node:
			continue
		var clips: Dictionary = a["clips"]
		var frames: Array = clips.get(mode, [])
		if frames.is_empty():
			mode = "idle"
			once = false
			frames = clips.get("idle", [])
		a["mode"] = mode
		a["once"] = once
		a["t"] = 0.0
		a["i"] = 0
		if not frames.is_empty():
			node.texture = frames[0]
		return


func _process(delta: float) -> void:
	_tick_actors(delta)
	_tick_fx_actors(delta)
	_tick_awaken(delta)
	_update_hp_bar()


func _tick_actors(delta: float) -> void:
	for a in _actors:
		var node := a["node"] as Sprite2D
		if node == null or not is_instance_valid(node):
			continue
		var clips: Dictionary = a["clips"]
		var frames: Array = clips.get(String(a["mode"]), [])
		if frames.is_empty():
			continue
		if frames.size() <= 1:
			# 單幀動作（`once`）也要能「播完回 idle」，否則會永久定格。
			if bool(a["once"]) and String(a["mode"]) != "idle":
				_set_actor_mode(node, "idle")
			continue
		var t := float(a["t"]) + delta * float(a["fps"])
		var idx := int(a["i"])
		while t >= 1.0:
			t -= 1.0
			idx += 1
			if idx >= frames.size():
				if bool(a["once"]):
					_set_actor_mode(node, "idle")
					t = 0.0
					idx = 0
					break
				idx = 0
			node.texture = frames[idx]
		a["t"] = t
		a["i"] = idx


## 一次性特效：逐幀推進，最後一幀後釋放自己。
func _tick_fx_actors(delta: float) -> void:
	var keep: Array = []
	for a in _fx_actors:
		var node := a["node"] as Sprite2D
		if node == null or not is_instance_valid(node):
			continue
		var frames: Array = a["frames"]
		var t := float(a["t"]) + delta * float(a["fps"])
		var idx := int(a["i"])
		var done := false
		while t >= 1.0:
			t -= 1.0
			idx += 1
			if idx >= frames.size():
				done = true
				break
			node.texture = frames[idx]
		if done:
			node.queue_free()
			continue
		a["t"] = t
		a["i"] = idx
		keep.append(a)
	_fx_actors = keep


## 覺醒卡：按歸一化進度逐幀寫屬性（**不用 Tween**，見檔尾說明）。
func _tick_awaken(delta: float) -> void:
	if not _awk_active:
		return
	_awk_t += delta
	var p := clampf(_awk_t / _awk_dur, 0.0, 1.0)
	_awk_apply(p)
	if p >= 1.0:
		_awk_active = false
		if _awk_root != null:
			_awk_root.visible = false


## 血條填充寬度跟著 `_hp_ratio`（Tween 動的是 ratio，渲染在這裡）。
func _update_hp_bar() -> void:
	if _hp_fill == null:
		return
	_hp_fill.size.x = maxf(HP_BAR_RECT.size.x * _hp_ratio, 1.0)


# =============================================================================
# 工具
# =============================================================================

## 腳底落點 → `Sprite2D` 中心座標（素材內容在畫布內**底對齊 + 水平居中**）。
func _center_from_feet(feet: Vector2, canvas: float, scale: float) -> Vector2:
	return Vector2(feet.x, feet.y - canvas * scale * 0.5)


## 取 `{action: {dir: [Texture2D...]}}` 裡的一組幀；缺則回空陣列（呼叫方安全跳過）。
func _clip(art: Dictionary, action: String, d: String) -> Array:
	var clips: Dictionary = art.get("clips", {})
	if not clips.has(action):
		return []
	var by_dir: Dictionary = clips[action]
	if not by_dir.has(d):
		return []
	return by_dir[d]


func _tw() -> Tween:
	var t := create_tween()
	_tweens.append(t)
	return t


## 程序化徑向漸層貼圖（紅光用）。
func _make_glow_texture(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a * a))
	return ImageTexture.create_from_image(img)


## 暗角貼圖：中央全透、四邊近黑（橢圓距離歸一化 ⇒ 角落 = 1）。
func _make_vignette_texture() -> ImageTexture:
	var img := Image.create(VIGNETTE_W, VIGNETTE_H, false, Image.FORMAT_RGBA8)
	var cx := float(VIGNETTE_W - 1) * 0.5
	var cy := float(VIGNETTE_H - 1) * 0.5
	for y in VIGNETTE_H:
		for x in VIGNETTE_W:
			var dx := (float(x) - cx) / cx
			var dy := (float(y) - cy) / cy
			var d := sqrt(dx * dx + dy * dy) / sqrt(2.0)
			var a := smoothstep(0.42, 1.0, d)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	return ImageTexture.create_from_image(img)


## 64×16 橢圓陰影貼圖（邊緣柔化；`SHADOW_SIZE` 為其原生尺寸）。
func _make_shadow_texture() -> ImageTexture:
	var w := int(SHADOW_SIZE.x)
	var h := int(SHADOW_SIZE.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := float(w - 1) * 0.5
	var cy := float(h - 1) * 0.5
	for y in h:
		for x in w:
			var d := Vector2((float(x) - cx) / cx, (float(y) - cy) / cy).length()
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


## 8×8 白色圓點貼圖（火星粒子）。
func _make_dot_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in range(8):
		for x in range(8):
			var dist := Vector2(float(x) - 3.5, float(y) - 3.5).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - dist / 4.6, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# =============================================================================
# 為何覺醒卡不用 Tween（2026-10-08）
# -----------------------------------------------------------------------------
# `boss_awaken_card.gd` 的檔內教訓（2026-09-23）：鏈式 Tween 與分階段 `await Tween`
# 對 `TextureRect.modulate` 都會卡住不動（`dim` 卻正常）—— 該環境下 Tween 對
# 「同一節點的多屬性鏈」不可靠。覺醒卡是**全屏視覺主角**，一旦卡住就是整段黑屏，
# 所以沿用已被驗證的做法：`_process` 累進 `_awk_t`，逐幀寫屬性，完全可控。
# 血條寬度同理：Tween 只動 `_hp_ratio` 這個 float，渲染寫在 `_update_hp_bar()`。
# =============================================================================
