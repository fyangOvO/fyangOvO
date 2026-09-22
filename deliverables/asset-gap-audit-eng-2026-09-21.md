# 七傳說 · 素材缺口工程影響與接線清單

> **Task**：TASK-ASSET-GAP-ENG（P0）
> **產出者**：程基岩（engineering-lead）
> **產出日**：2026-09-21
> **範圍**：純分析與接線清單，未改任何工程檔。
> **基線**：`D:\七傳說\game\`（Godot 4.7.2 / GDScript 2.0 / 邏輯 640×360 / Nearest）。

---

## 0、團隊長提供的「事實偵察」**勘誤**（先列，後續分析基於此修正版）

| # | 團隊長原述 | 實讀工程後的正確版 | 出處 |
|---|---|---|---|
| **E1** | "`scene_path` 從未被讀取；`chapter1.json` 的 `ch1_l01..l06.tscn` 是死字段" | **scene_path 確實有被讀取**，但目標檔不存在 ⇒ 走回退。`scene_manager.gd:120-133`：`change_to_level()` 先試 `level.scene_path`（若非空）；`ResourceLoader.exists` 失敗時 `print("[SceneManager] 关卡专属场景不存在，回退通用容器")` ⇒ 落到 `SCENE_LEVEL`（`level.tscn`）。**每進一個 ch1 關都會��一條 warning**。`scenes/levels/` 內只有 `level.tscn` 一個檔。 | `scene_manager.gd:115-138` |
| **E2** | "16 隻怪 `assets/sprites/enemies/<id>.png` 全缺，有 ③ 兜底 ⇒ 靜默降級還是缺口？" | **這是「正常運作」，不是缺口也不是降級**：四級鏈中 `BUNDLED_SPRITE_DIR` 是「用戶單檔覆蓋優先槽位」，不是必須；16 隻怪的 `sprite_path` 都被忽視、`resolve_character_set()` 直接走 ③ `dnf_load_set(id)`，全部命中（`assets/dnf/normalized/<id>/`）。改 ② 為主檔只會**新增**一條 fallback 命中，不改當前行為。 | `enemy_base.gd:436-454`、`BUNDLED_SPRITE_DIR=:161` |
| **E3** | "玩家/怪物 4 向解析；包內是 `_s` 單方向" | **包內其實是 8 向**（`walk_n/ne/e/se/s/sw/w/nw`），但**引擎只會用 4 向**：`PlayerController.facing_to_dir_letter()` 與 `EnemyBase.dir_from_vector()` 都把對角併入 n/e/s/w。`w/sw/nw` 依規範走鏡像（`enemy_base.gd:286-294` 已實現），但 `ne/se` 幀會**永遠不被用到**——這是 192 幀中的「76 幀死資源」，但不是 bug（接入只是讓鏡像更準；不接也照樣能玩）。 | `player_controller.gd:780-786`、`enemy_base.gd:578-581` |
| **E4** | "包內 17 張 `assets/ui/pixel/*` 與 `assets/ui/quest/*` 重複；`ui_skin.gd` 註釋稱 128×24 是『規範 C6』" | **正確**；追加：`ui_skin.gd:32 BUILTIN_ROOT = "res://assets/ui/quest"` 是 `ContentPaths.CLASS_UI` 的 bundled 側，`assets/ui/pixel/` 沒有任何消費方，**且 96×24 按鈕在 `EXPECT_TEX` 完全沒列名**。 | `ui_skin.gd:32-58`、`verify_ui_assets.gd:29-52` |
| **E5** | "4 張新特效未引用" | **正確**：`data/fx.json::effects` 只有 `hit_spark/slash_arc/level_up_burst/pickup_glow/death_puff/ember_lord_aura/pyromancer_cast` 七條；`fx_slash_px96/fx_fire_px96/fx_frost_px96/fx_thunder_px96` 四張新關鍵幀**完全沒在表內**。`verify_fx.gd:24 REQUIRED_IDS` 也只盯這七條。 | `data/fx.json:18-95`、`verify_fx.gd:24-27` |
| **E6** | "`assets/anim/<skill>/` 38 張全未接線" | **正確**。`fx_sprite.gd:54 setup(spec, tex)` 的 spec 形如 `{texture, frame_w, frames, fps, ...}` 從 `FxTable` 取；`assets/anim/*/fx_*.png` 是**逐幀獨立 PNG**（非橫向長條），無法直接喂 `FxSprite`——但**可被新消費方接手**，詳 §2.3。 | `fx_sprite.gd:54-78`、`assets/anim/*/` |

> 其他原述（`data/skills/skills.json` 無 `icon` 字段、`RARITY_SLOT` clamp、`SKILL_ICON` 缺兩條、`scene.tscn` 共用）**全部讀過驗證無誤**。

---

## 一、缺口 → 運行時行為影響矩陣

| # | 缺口 | 現在會發生什麼 | 依據（檔案:行） | 嚴重度 |
|---|---|---|---|---|
| 1 | `assets/sprites/enemies/<id>.png` × 16 全缺 | **無影響**：四級鏈 ② 落空、③ `dnf_load_set(id)` 命中 ⇒ 16 隻怪都吃 DNF 規整素材；行為與「有 ②」完全一致 | `enemy_base.gd:436-454`、`BUNDLED_SPRITE_DIR=:161` | 無 |
| 2 | `assets/characters/` 玩家三職業（213 檔） | **不接**：當前 `assets/dnf/normalized/player/` 與 `assets/dnf/normalized/player_alt_vx/` 兩套**正常運作**；新包是新增內容，不影響現狀 | `player_controller.gd:156-160`、`DNF_WHO="player"` | 無 |
| 3 | `assets/monsters/` × 5 個 id（slime_forest/frost/skeleton/imp_volcanic/boss_demon_lord，19 檔） | **部分命中／部分不命中**：slime/skeleton/imp 在 `assets/dnf/normalized/` 有對應目錄（`slime_acid/skeleton_warrior/imp_hellfire` 等）；`boss_demon_lord` 在 DNF 集是 `boss_ember_lord`（**名稱漂移**）；`warg_dark / wraith_frost` 等怪物在**兩套都沒有**——會落回占位色塊（`_build_placeholder_art`） | `enemy_base.gd:235-239`、`assets/dnf/normalized/` 列舉 | **中**：BOSS 漂移需裁定 |
| 4 | `assets/weapons/` × 10 + `assets/armor/` × 6（16 檔） | **不接**：當前 62 件裝備全指 `res://assets/icons/equipment/equip_*_48.png`，**12 檔全在**（團隊長事實正確）。`verify_ui_assets.gd:154` 顯式斷言「全部 icon_path 必須以 `res://assets/icons/equipment/` 開頭」 | `data/equipment/*.json`、`verify_ui_assets.gd:154-168` | 無 |
| 5 | `assets/fx/` 新增 4 張關鍵幀（fx_slash/fire/frost/thunder_px96） | **未消費**：表內 7 條全指舊貼圖（`slash_arc.png` 等）；新 4 張**永遠不會被 spawn | `data/fx.json:18-95`、`verify_fx.gd:24-27` | **低**：表內已有類似 id，不影響現狀 |
| 6 | `assets/anim/<skill>/` 序列幀（38 張） | **無消費方**：專案無「逐幀獨立 PNG」型特效消費鏈；`FxSprite` 只吃橫向長條 + `frame_w × frames` 切片 | `fx_sprite.gd:1-114` | **中**：是設計空白 |
| 7 | `assets/ui/pixel/` 17 張 | **完全不消費**：`BUILTIN_ROOT` 為 `ui/quest`，包內按鈕 96×24 與規範 C6（128×24）**不符**；`EXPECT_TEX` 也沒列名稱，連回歸都沒盯 | `ui_skin.gd:32`、`verify_ui_assets.gd:29-52` | **低**：規範 C6 主導 |
| 8 | `assets/backgrounds/backdrop_*_640x360.png` × 3 森林/寒霜/火山 + 1 主選單 | **同名已有**：生態背景三張在 `ui/quest/backdrops/` 與 `DNF 封面/hero_standee` 各自獨立；包內三張**未被任何消費鏈讀** | `ui_skin.gd:73-75, 83`、`TEX_DNF=:202-218` | **低**：主選單背景除外（見 §1.9） |
| 9 | `main_menu_bg_640x360.png` | **已接**：`ui_skin.gd:83` 已登錄 `main_menu_bg → main_menu_bg_640x360.png`；`main_menu_screen._build_backdrop()` 優先使用 | `ui_skin.gd:76-83`、`main_menu_screen.gd:16` | 無 |
| 10 | 套裝徽記 × 3（`res://assets/sprites/items/set_emblem_*.png`） | **無消費方 + 路徑不存在**：`config_loader.gd:374` 寫入 `SetData.emblem_path`；`grep '.emblem_path' scripts/` **唯一命中就是寫入處**——零讀取。目錄 `assets/sprites/items/` 也**不存在**（`ls` 失敗） | `config_loader.gd:374`、`resources/set_data.gd:29`、`grep .emblem_path` | **低**：純數據層冗餘 |
| 11 | `RARITY_SLOT[5/6/7]` clamp 到 `slot_orange` | **視覺降級**：MYTHIC 紅、SET 綠、HIDDEN 彩三檔與 LEGENDARY 橙同框；22 件裝備會走這條 | `ui_skin.gd:106-115`、`verify_ui_assets.gd:122`（全 8 解析出，clamp 不視為缺） | **低**：註釋自承且測試也接受 |
| 12 | `SKILL_ICON` 缺 `lightning_chain / poison_cloud` | **無影響**：當前不出戰（兩者 `slot=0`）；HUD 槽位仍可用 `skill_slot` 兜底（`level_scene.gd:1017-1019`） | `level_scene.gd:1007-1014, 1020-1048`、`data/skills/skills.json:68-92` | 無 |
| 13 | `chapter1.json::scene_path` 全指不存在的 `ch1_l01..l06.tscn` | **每關刷一條 warning**、場景仍正確加載（`level.tscn` 兜底）；功能正常但**日誌噪音**——E1 | `scene_manager.gd:120-133`、`scenes/levels/`（僅 `level.tscn`） | **低**：日誌噪音、可忽略 |

**判定總結**：13 條中，**只有第 3 條（BOSS 名漂移）需要裁定、只有第 6 條（序列幀無消費方）有真實設計空白、只有第 5+11 條有真實缺口**（4 張新特效待入表、3 檔高階稀有度框）。**E1/E2 是團隊長判讀錯誤，不算缺口**。

---

## 二、接線清單（最少改動原則）

### 2.1 玩家／怪物接入 `assets/characters/` 與 `assets/monsters/`

**前置事實**：引擎走 `assets/dnf/normalized/<id>/`（`DNF_NORM_ROOT = "res://assets/dnf/normalized"`，`enemy_base.gd:153` + `player_controller.gd:156`），檔名約定 `char_<who>_<action>_<dir>_<NN>.png`（4 向：n/e/s/w）。

**方案 A（建議，零代碼）**：把包內檔案**重新命名後**移入 `assets/dnf/normalized/<who>/`：
- 玩家：`assets/characters/walk_e/char_warrior_walk_e_01.png` → `assets/dnf/normalized/warrior/char_warrior_walk_e_01.png`（**who = `warrior`**，新增職業）
- 怪物：`assets/monsters/slime_forest/mon_slime_forest_idle_s_01.png` → `assets/dnf/normalized/slime_forest/mon_slime_forest_idle_s_01.png`（who 段含底線��解析器已支援：`enemy_base.gd:584-616`）

**方案 B（代碼側）**：在 `EnemyBase.dnf_load_set` 前加一層 `who → 目錄` 映射，把 `warrior → assets/characters/`、`mage → assets/characters/`、`archer → assets/characters/`、怪物逐一映射到 `assets/monsters/<id>/`。**不推薦**——破壞現有 DNF 解析鏈與 `_dnf_cache` 鍵空間。

**風險點**：
- **方向衰減**：包是 8 向，但引擎只認 4 向。`_ne/_se/_nw/_sw` 幀無法被引用（玩家 `facing_to_dir_letter` 只產 n/e/s/w）。**結論**：保留這 8 個子目錄即可，引擎會忽略對角幀；
- **BOSS 名漂移**：`assets/monsters/mon_boss_demon_lord_idle_s_01.png` vs 現有 `boss_ember_lord`。`monster_id` 改用 `boss_demon_lord` 後會斷鏈——**建議保守**：BOSS 不接包素材，沿用現有 `boss_ember_lord`，等工程側補一個新 monster_id；
- **靜默命中**：DNF 套已能跑，新素材不會破壞既有 `verify_ui_assets` E 段（玩家真精靈載入的 clips > 0 斷言：多套素材共用 `set_b` 載入點，新增套仍是「可以載」）。

**工作量**：M（純檔案整理 + import 重跑，無代碼改動）。

### 2.2 4 張新特效接進 `data/fx.json`

**前置事實**：表內 7 條已能跑；`verify_fx.gd:24 REQUIRED_IDS` 是「白名單」，新增 id 不會讓它變紅。

**最小改動**：在 `effects` 物件追加 4 條。約束：`frame_w × frames ≤ 貼圖寬`，由 `FxSprite.setup():68-72` 強制 clamp + warning。

```jsonc
// 範例（數值需按實際 .png 寬度校驗）：
"slash_key": {
  "texture": "fx_slash_px96.png",
  "frame_w": 96, "frame_h": 96,
  "frames": 1,         // 包內是「關鍵幀」單幀；想拆成多幀要跑 sprite_sheet_cut
  "fps": 12.0, "loop": false,
  "anchor": "center", "z": "above_actors", "fade": true
},
"fire_key":  { "texture": "fx_fire_px96.png",  "frame_w": 96, "frame_h": 96, "frames": 1, "fps": 12.0, "loop": false, "anchor": "center", "z": "above_actors", "fade": true },
"frost_key": { "texture": "fx_frost_px96.png", "frame_w": 96, "frame_h": 96, "frames": 1, "fps": 12.0, "loop": false, "anchor": "center", "z": "above_actors", "fade": true },
"thunder_key":{ "texture": "fx_thunder_px96.png","frame_w": 96, "frame_h": 96, "frames": 1, "fps": 12.0, "loop": false, "anchor": "center", "z": "above_actors", "fade": true }
```

**消費方空白**：現有 `FxTable.spawn()` 7 個調用點（`grep FxTable.spawn scripts/`）**全部用舊 7 個 id**——新 id 即使加進表也無 caller。建議**先加表、後接 caller**；不要兩步並進。

**風險**：`frame_w × frames ≤ tex.w`（96×1=96 OK）。`required_ids` 白名單**不會**因新 id 變紅。
**工作量**：S（純資料 + 4 行 JSON）。

### 2.3 `assets/anim/` 序列幀要新增什麼消費方？

**`FxSprite.setup()` 契約**（`fx_sprite.gd:54-78`）：
- 參數：`spec` 必填 `texture`（橫向長條 PNG）+ `frame_w/frame_h/frames`；
- **不吃逐幀獨立 PNG**——`setup()` 只從一張貼圖切 `frame_w` 寬的等寬列。

**所以結論**：`FxSprite` **不能直接複用**包內 38 張獨立幀。要接入必須二選一：

- **方案 A1（推薦）**：跑 `tools/pixel_pipeline/sprite_sheet_cut.py`（PACK_OVERVIEW §2.4 / §8 已列）把每個技能 9–10 張圖拼成 1 張橫向長條 PNG（例：9 幀 × 96×96 → 864×96），再走 `FxSprite` 既有鏈。**零代碼**。
- **方案 A2（不推薦）**：寫一個新的 `FxSpriteSequence extends Node2D`，持 `Array[Texture2D]`，用 `TextureRect` 切換或 `AnimatedSprite2D`。**代價**：破壞「一檔一 draw call」鐵律（`fx_sprite.gd:6-14` 明文反對）。
- **方案 A3（最簡）**：先**不接**——現有 `fx_table` 已能跑，新增此類純屬內容擴展。

**風險**：新消費方若走 `FxSprite`，**必須新 import**（否則 `ResourceLoader.exists(path)` 為 false 走 `Image.load()` fallback，但仍���黑盒 OK）。

**工作量**：A1 = S（跑一次腳本 + 4 行 fx.json 條目）；A2 = L；A3 = 0。

### 2.4 裝備圖標遷移（`icons/equipment/` vs `assets/weapons/` `assets/armor/`）

**前置事實**：`verify_ui_assets.gd:154-168` 強制 `icon_path.begins_with("res://assets/icons/equipment/")`。

**兩種方案**：

| 方案 | 動作 | 影響 |
|---|---|---|
| **保留 icons/equipment 為主** | 從 `assets/weapons/ + assets/armor/` 16 張**只取新增件**（leg 腿甲、`weapon_quiver / offblade`、`equip_ring` 第二色等），追加 `equip_*_48.png` 進 `assets/icons/equipment/`，再寫進對應 `data/equipment/*.json` | 既有 12 檔全部留著、JSON 改少數條目；`EXPECT_TEX` 與 `_check_all_paths` 零改動 |
| **全面遷移** | 將 `assets/weapons/*` 重命名 `equip_*_48.png` 後搬進 `icons/equipment/`；JSON `icon_path` 全改 | **必須**同步改 `verify_ui_assets.gd:154-168` 與 `EXPECT_TEX:29-52`；`main_menu_panel.gd:30 BTN_SIZE` 雖然管按鈕與圖標無關但要回頭檢查無連帶依賴 |

**建議方案 1**（增量接入），`verify_ui_assets` 與 `EXPECT_TEX` 零變動。

**額外考量**：裝備圖標實際用途在 `equip_panel / inventory_panel / shop_panel / compare_panel` ——這些面板現在吃 `UISkin.dnf_texture` 路徑上的 `weapon_sword_*`，**沒有一個吃 `data/equipment.icon_path`**。所以**目前圖標純屬展示**，實際影響面有限。

**工作量**：方案 1 = S；方案 2 = M（要改驗證腳本）。

### 2.5 稀有度框補 3 檔

包內有 `rarity_common/rare/epic/legend/myth_48.png`（5 檔，**無 `set_`/`hidden_`**），`myth` 對應索引 5（MYTHIC 紅）；引擎要 8 檔（COMMON..HIDDEN）。

**最小改動**：補 2 張新檔（`rarity_set_48.png` 綠、`rarity_hidden_48.png` 彩），`myth` 沿用包原檔（與現有 `slot_orange` clamp 行為並存即可——`slot_orange` 仍兜底）。**或**改 `RARITY_SLOT:106-115` 把 5→`rarity_myth`、6→`rarity_set`、7→`rarity_hidden`，並把 `EXPECT_TEX` 補 3 行。

**注意**：`verify_ui_assets.gd:122` 斷言 `slot_stylebox_rarity(0..7) 全部解析出樣式` ——目前 8 檔全部**已解析**（因為全部 clamp 到 `slot_orange`，`slot_orange` 存在）。改映射後需重驗：每個 rarity 對應檔必須真存在。

**工作量**：S（2 張 PNG + 3 行 dict + 3 行 EXPECT_TEX）。

---

## 三、回歸風險清單

> 所有「會變紅」的斷言都點到具體行；「不變紅」也明確說為何不變。

| 驗證腳本 | 觸發點 | 影響判定 | 規避 |
|---|---|---|---|
| **`verify_fx.gd`** | `REQUIRED_IDS` 是白名單（7 條），新增 id 不會被它校驗到；`frame_w × frames ≤ tex.w` 是黑盒硬約束（`fx_sprite.gd:68-72`） | 新增 4 條 id **不會變紅**；若 `frames` 寫超，會刷 `[FxSprite] 贴图宽 ... 只装得下 ... 帧` warning，但 verify 不讀 stderr | 不寫超 `frames` |
| **`verify_ui_assets.gd:29-52 EXPECT_TEX`** | 改了 UI 皮膚（SRC）或 BUILTIN_ROOT 才會紅；本輪方案都不改 SRC | **不紅** | 維持 `BUILTIN_ROOT = "res://assets/ui/quest"`，不動 `EXPECT_TEX` |
| **`verify_ui_assets.gd:154-168 _check_all_paths`** | 改 `data/equipment/*.json` 的 `icon_path` 指向新路徑 → 紅 | **採用 §2.4 方案 1 則不紅**；方案 2 全遷移會紅 | 走方案 1 |
| **`verify_ui_assets.gd:122 RARITY_SLOT 8 檔全解析`** | 改了映射後，被指名的檔必須存在 | 補 2 張 PNG 後 OK | §2.5 |
| **`verify_enemy.gd`** | 不讀 `_clips` 結構，只讀怪物 AI 行為；新增素材不影響 | **不紅** | — |
| **`verify_monsters62.gd`** | 讀 `monsters.json` 16 隻 id 與詞綴；新怪物 `boss_demon_lord` 加入 monsters.json 會破壞 `total == 16` 斷言 | **不要改 monsters.json**；只把包內怪物移到 `dnf/normalized/<existing_id>/` | §2.1 採「現有 id + 同名映射」原則 |
| **`verify_anim.gd`** | 盯 `dnf_parse_names` 與 4 向；新增職業 `warrior/mage/archer` 作新 who 是純增量 | **不紅**；但若把 8 向檔案強塞進解析器（破壞 `dir_from_vector`）會紅 | 8 向檔案保留但僅 n/e/s/w 被消費（`_ne/_se` 不寫進解析器） |
| **`parse_all.gd`** | 純解析所有 `.gd`；本輪不動 `.gd` | **不紅** | — |
| **`verify_integration.gd:36 _check_scene_paths`** | `E1`：會列舉所有 `.tscn` 並檢查引用一致性；`scene_path` 指向不存在的 `.tscn` **會刷 warning** 但不會讓 `verify_integration` 變紅（它是 list 校驗） | 既有 warning 持續，不會惡化也不會改善 | 與 E1 同處理 |

**意外風險**：`scripts/run/level_scene.gd:961` 與 `ui_skin.gd:51` 多處註解警告「**改尺寸必須同步改 `EXPECT_TEX` 與 `BTN_SIZE`**」——若**任何**把包內 96×24 按鈕納入 `EXPECT_TEX` 的改動，都會讓 `main_menu_panel.gd:30 BTN_SIZE = Vector2(256,48)`（顯示尺寸）的斷言一起紅（`verify_ui_assets.gd:224`）。**強烈建議**：包內 96×24 按鈕一律**不入** `EXPECT_TEX`、不入 `ui_skin.TEX`，**整個 `assets/ui/pixel/` 不接**。

---

## 四、**不建議動的部分**

1. **`assets/ui/pixel/` 全部 17 張**：規範 C6 是 128×24，包內是 96×24；`EXPECT_TEX` 全沒列名。若接會需要**同時**改 `EXPECT_TEX`、`main_menu_panel.BTN_SIZE`、`ui_skin.BTN_MARGIN`（從 6 改？）。**結論：留著別動**。
2. **`assets/backgrounds/` 三張生態背景**：與 `ui/quest/backdrops/` 三張重複且同名（`backdrop_forest_640x360.png` 等）；`ui_skin.gd:73-75` 已接入現有三張。**結論：留著別動**（接了會撞名，必須做命名空間隔離）。
3. **BOSS 漂移（`mon_boss_demon_lord`）**：`monsters.json` 沒有這個 id，硬塞會破 `verify_monsters62` 的「16 隻」斷言。**結論：不接**，等 monster_id 補齊後再說。
4. **`assets/weapons/` + `assets/armor/` 全面遷移**：見 §2.4 方案 2 風險——會觸發 `verify_ui_assets._check_all_paths` 全套 62 件斷言紅。**結論：方案 1（增量）**。
5. **`scene_path`（chapter1.json）**：E1 已說明——是日誌問題不是 bug。**結論：不動**（除非順手把那 6 個 `ch1_l0X.tscn` 真的做出來，那屬另一個工單）。

---

## 五、接線順序建議（**改動小 × 收益大**排序）

| 序 | 動作 | 工作量 | 收益 | 觸發回歸風險 |
|---:|---|:-:|---|---|
| 1 | 補 3 檔稀有度（myth 沿用包）+ 改 `RARITY_SLOT[5→rarity_myth, 6→rarity_set, 7→rarity_hidden]` + 補 `EXPECT_TEX` 3 行 | **S** | 中：22 件橙裝可被正確分級 | `verify_ui_assets` 全綠（補完後） |
| 2 | 加 4 條 `fx_*.json` 條目（§2.2） | **S** | 低：純資料增量 | 無（REQUIRED_IDS 不讀新 id） |
| 3 | 跑 `sprite_sheet_cut.py` 拼 4 套序列幀 → 加 4 條 `fx_*.json` 條目（§2.3 方案 A1） | **S** | 高：玩家 4 技能特效有真正可見動畫 | 無；需補 caller |
| 4 | 補 `assets/weapons/` + `assets/armor/` 增量進 `icons/equipment/`（§2.4 方案 1） | **S** | 低：純展示 | 無 |
| 5 | 玩家/怪物素材移入 `dnf/normalized/<who>/`（§2.1 方案 A） | **M** | 高：玩家三職業全部顯現 | `_check_all_paths` 不會變紅（裝備圖目不動）；`parse_all` 不讀素材 |

**工作量圖例**：S = ≤半小時；M = 半小時–2 小時；L = ≥2 小時（含代碼改動）。

---

## 六、知識缺口與風險標記

- **引擎 API 確認**：所有 `_apply_real_art` / `_resolve_sprite` / `FxSprite.setup` / `scene_manager._load_and_swap` 的呼叫契約都已**實際讀過**並引用行號；無臆造。
- **BOSS 名漂移**：建議在 `monsters.json` 加 `boss_demon_lord` 條目（不接素材）作占位——屬策劃裁定，本工單**不**建議動 `monsters.json`。
- **`scene_path` 修正**：本工單不建議動（E1）；若要修，建議獨立工單——刪 `chapter1.json` 六個 `scene_path` 欄位，或補 6 個空 `.tscn` 檔。
- **`anim/` 38 張若要走 §2.3 A1**：要先確定 4 技能（slash/fireburst/frostnova/thunder）的**實際幀寬**（可能非 96×96，需重跑 `fx_anim_gen.py` 重看輸出），否則 `frame_w × frames` 校驗會刷 warning。

---

> 本檔為分析交付，不含可執行代碼。實裝前請以本清單對 `user_manager`（art-director）產出的 `asset-gap-audit-art-2026-09-21.md` 對齊規格，並由主理人拍板接線順序。