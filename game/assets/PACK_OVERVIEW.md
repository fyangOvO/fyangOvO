# 七傳說 · 素材包歸位索引（PACK_OVERVIEW）

> **來源**：`deliverables/七傳說_像素素材包_2026-09-21.zip`（339 檔 / 5.75 MB）
> **歸位日**：2026-09-21
> **歸位方式**：純整理 —— 只把檔案放進工程既有目錄並產生本索引，**未改動任何 `.gd` / `.tscn` / `.json`，未刪除任何既有檔案，未覆蓋任何同名檔**。
> **可重跑**：`python game/tools/pixel_pipeline/import_pack.py`（乾跑）／`... --apply`（實際歸位，預設不覆蓋）

風格定位：**嚴謹 16-bit 2D 像素風（DNF 暗黑地下城）**。工程邏輯分辨率 640×360，整數倍縮放 + 最近鄰（Nearest），有限色板。

---

## 一、歸位總表

| zip 目錄 | 工程路徑 | 檔數 | 尺寸 | 內容 |
|---|---|---:|---|---|
| `characters/` | `assets/characters/` | 213 | 192×192 | 三職業 8 方向 walk／attack + hurt／death（南） |
| `monsters/` | `assets/monsters/` | 19 | 192×192 · 256×256 | 4 小怪 + BOSS 惡魔領主 |
| `weapons/` | `assets/weapons/` | 10 | 48×48 | 主手 6 + 副手 4 |
| `armor/` | `assets/armor/` | 6 | 48×48 | 頭／胸／手／鞋／項鍊／戒指 |
| `fx/` | `assets/fx/` | 4 | 96×96 | 劍氣／火焰／冰霜／落雷關鍵幀（**併入既有目錄**） |
| `anim/` | `assets/anim/` | 42 | 96×96 | 4 技能序列幀 + 預覽 gif |
| `backgrounds/` | `assets/backgrounds/` | 4 | 640×360 | 森林／寒霜／火山／主選單 |
| `ui/pixel/` | `assets/ui/pixel/` | 17 | 見 §2.6 | 面板／按鈕／血藍條／槽／稀有度 |
| `ui/skill_icons/` | `assets/ui/skill_icons/` | 4 | 48×48 | 4 個技能圖標 |
| `previews/` + 根目錄 3 張 | `assets/previews/` | 11 | 多規格 | 動圖預覽 + 全包總覽 + 實戰合成圖 |
| 根目錄 `*.py` + `README.md` | `tools/pixel_pipeline/` | 9 | — | 像素化／切割／校驗管線腳本 |

**合計 339 檔**（含管線腳本與 README）。

---

## 二、各類別明細

### 2.1 `assets/characters/` —— 三職業角色（213）

| 動作 | 目錄 | 每職業幀數 | 職業數 | 小計 |
|---|---|---:|---:|---:|
| idle | `characters/`（根，單幀） | 1 | 3 | 3 |
| walk 8 方向 | `characters/walk_<dir>/` | 4 | 3 | 96 |
| attack 8 方向 | `characters/attack_<dir>/` | 4 | 3 | 96 |
| hurt | `characters/hurt_s/` | 2 | 3 | 6 |
| death | `characters/death_s/` | 4 | 3 | 12 |

- 方向：`n / ne / e / se / s / sw / w / nw`。
- **`w` / `sw` / `nw` 由 `e` / `se` / `ne` 水平鏡像得到**，幀序與原始方向一致 ⇒ 引擎內可直接 `scale.x = -1` 重用，不必再存一份。
- 命名：`char_<class>_<action>_<dir>_<NN>.png`，`NN` 由 `01` 起算；idle 為單幀 `char_<class>_idle_s_01.png`。
- 三職業：`warrior`（銀白短髮／紅黑皮甲／大劍）、`mage`（金髮兜帽長袍／水晶法杖）、`archer`（精靈尖耳／綠兜帽／長弓）。

### 2.2 `assets/monsters/` —— 怪物與 BOSS（19）

| 目錄 | 內容 | 幀數 |
|---|---|---:|
| `monsters/slime_forest/` | 毒史萊姆（森林）彈跳 idle | 4 |
| `monsters/slime_frost/` | 冰霜史萊姆（寒霜）彈跳 idle | 4 |
| `monsters/skeleton/` | 骷髏兵（骨刃劍）idle + attack | 5 |
| `monsters/imp_volcanic/` | 火焰小鬼（三叉叉）idle + attack | 5 |
| `monsters/`（根） | BOSS 惡魔領主 idle | 1 |

- 命名：`mon_<name>_<action>_<dir>_<NN>.png`；BOSS 為 `mon_boss_demon_lord_idle_s_01.png`。
- BOSS 為 **256×256 畫布**（玩家／小怪為 192×192），刻意做大以製造壓迫感。

### 2.3 `assets/weapons/` + `assets/armor/` —— 裝備圖標（16）

| 檔案 | 部位 |
|---|---|
| `weapons/weapon_sword_48.png` | 主手 · 劍 |
| `weapons/weapon_axe_48.png` | 主手 · 斧 |
| `weapons/weapon_hammer_48.png` | 主手 · 錘 |
| `weapons/weapon_dagger_48.png` | 主手 · 匕首 |
| `weapons/weapon_staff_48.png` | 主手 · 法杖 |
| `weapons/weapon_bow_48.png` | 主手 · 長弓 |
| `weapons/weapon_shield_48.png` | 副手 · 盾 |
| `weapons/weapon_orb_48.png` | 副手 · 法器 |
| `weapons/weapon_quiver_48.png` | 副手 · 箭袋 |
| `weapons/weapon_offblade_48.png` | 副手 · 副刃 |
| `armor/equip_helmet_48.png` | 頭 |
| `armor/equip_chest_48.png` | 胸 |
| `armor/equip_gauntlet_48.png` | 手 |
| `armor/equip_boots_48.png` | 鞋 |
| `armor/equip_amulet_48.png` | 項鍊 |
| `armor/equip_ring_48.png` | 戒指 |

### 2.4 `assets/fx/` + `assets/anim/` —— 特效與技能序列幀（46）

`assets/fx/`（關鍵幀，**併入既有目錄，與原 7 張並存**）：

| 檔案 | 用途 |
|---|---|
| `fx_slash_px96.png` | 劍氣 |
| `fx_fire_px96.png` | 火焰 |
| `fx_frost_px96.png` | 冰霜 |
| `fx_thunder_px96.png` | 落雷 |

`assets/anim/`（序列幀，14 fps 單次不循環）：

| 技能 | 目錄 | 幀數 | 運動 |
|---|---|---:|---|
| 劍氣斬 | `anim/slash/` | 9 | 月牙展開 → 飛出 → 淡出 |
| 火焰爆發 | `anim/fireburst/` | 10 | 火星 → 火柱放大 1.15× → 消散 |
| 冰霜新星 | `anim/frostnova/` | 10 | 亮點 → 冰環擴散 1.9× → 淡出 |
| 落雷 | `anim/thunder/` | 9 | 閃電劈下 → 白閃 → 消散 |

另附 4 條同名 `.gif` 預覽（`anim/*.gif`）供快速比對。

> **兩層設計**：角色動作（`characters/attack_*`）與技能特效（`anim/`）是**獨立兩層** —— AnimatedSprite2D 播角色動作，在命中幀另疊一層特效精靈。

### 2.5 `assets/backgrounds/` —— 生態背景（4）

`backdrop_forest_640x360.png`、`backdrop_frost_640x360.png`、`backdrop_volcanic_640x360.png`、`main_menu_bg_640x360.png`

### 2.6 `assets/ui/` —— UI 組件（21）

| 檔案 | 尺寸 | 用法 |
|---|---|---|
| `ui/pixel/panel_9slice_120.png` | 120×120 | 9-slice，**邊距 8px**，中心可拉伸 |
| `ui/pixel/btn_gold_{normal,hover,pressed}_96x24.png` | 96×24 | 主按鈕三態，水平拉伸 |
| `ui/pixel/btn_dark_{normal,hover,pressed}_96x24.png` | 96×24 | 次按鈕三態 |
| `ui/pixel/bar_hp_160x16.png` / `bar_mp_160x16.png` | 160×16 | 血／藍條，填充建議代碼裁切 |
| `ui/pixel/slot_normal_48.png` / `slot_selected_48.png` | 48×48 | 物品槽普通／選中 |
| `ui/pixel/rarity_{common,rare,epic,legend,myth}_48.png` | 48×48 | 5 檔稀有度框（白／藍／金／紫／橙） |
| `ui/pixel/skill_slot_48.png` | 48×48 | 技能欄斜切角槽 |
| `ui/skill_icons/skill_{slash,fireburst,frostnova,shadowdash}_48.png` | 48×48 | 技能圖標 |

> 按鈕文字、血條數字一律由代碼字體渲染，**不燒進圖片**。

### 2.7 `assets/previews/` —— 預覽與總覽（11）

| 檔案 | 說明 |
|---|---|
| `previews/PACK_OVERVIEW.png` | 全素材分區總覽（1680×2597） |
| `previews/scene_preview_640x360.png` | 實戰合成畫面（原生分辨率） |
| `previews/scene_preview_2x.png` | 實戰合成畫面（2× 放大） |
| `previews/warrior_attack_s.gif` · `warrior_walk_s.gif` · `warrior_death_s.gif` | 戰士動作動圖 |
| `previews/mage_attack_s.gif` · `archer_attack_s.gif` | 法師／弓手攻擊動圖 |
| `previews/slime_forest_bounce.gif` · `skeleton_attack.gif` · `imp_attack.gif` | 怪物動圖 |

---

## 三、命名規範（保留包內原樣，**未做改名**）

| 類別 | 規則 | 例 |
|---|---|---|
| 玩家 | `char_<class>_<action>_<dir>_<NN>.png` | `char_mage_attack_ne_03.png` |
| 怪物 | `mon_<name>_<action>_<dir>_<NN>.png` | `mon_skeleton_attack_s_02.png` |
| BOSS | `mon_boss_<name>_idle_s_01.png` | `mon_boss_demon_lord_idle_s_01.png` |
| 武器 | `weapon_<type>_48.png` | `weapon_shield_48.png` |
| 裝備 | `equip_<slot>_48.png` | `equip_gauntlet_48.png` |
| 特效 | `fx_<skill>_px96.png` | `fx_thunder_px96.png` |
| 序列幀 | `anim/<skill>/fx_<skill>_<NN>.png`（NN 由 `00` 起） | `anim/slash/fx_slash_03.png` |
| 背景 | `backdrop_<biome>_640x360.png` | `backdrop_frost_640x360.png` |

---

## 四、動畫播放參數（建議值，引擎側尚未接線）

### 玩家動作

| 動作 | 幀數 | 幀率 | 循環 |
|---|---:|---:|---|
| walk（8 方向） | 4 | 8–10 fps | 循環（邁步–併腳–反向–併腳） |
| attack（8 方向） | 4 | 12 fps | 單次，回 idle |
| hurt | 2 | 10 fps | 單次／短暫 |
| death | 4 | 8 fps | 單次（停最後倒地幀） |

### 怪物

- 史萊姆彈跳 idle：4 幀，8 fps 循環。
- 骷髏／小鬼攻擊：4 幀，12 fps 單次。

### 技能序列幀

- 統一 **14 fps、單次不循環**。

> 長袍法師行走腿部被衣袍遮擋，動畫主要靠袍角擺動 ⇒ 建議引擎中對移動角色疊加輕微上下浮動（bob）。

---

## 五、與工程既有素材的邊界（本輪**未覆蓋**，需你裁定）

以下三處是包內素材與工程既有素材「同名／近似同職能」的地方。本輪一律**不覆蓋、不改名**，兩套並存：

| # | 包內 | 工程既有 | 差異 | 建議 |
|---|---|---|---|---|
| 1 | `assets/armor/equip_*_48.png`（6 檔） | `assets/icons/equipment/equip_*_48.png`（12 檔，含武器） | **同名不同來源**；工程版把武器與防具合併放 `icons/equipment/`，命名前綴統一 `equip_` | 需定「以哪套為準」；若要合併，可能要把 `weapons/weapon_*` 改名為 `equip_*` |
| 2 | `assets/ui/pixel/btn_*_96x24.png` | `assets/ui/quest/btn_*_128x24.png` | **尺寸不同**（96 vs 128 寬），樣式亦不同代 | 需定 UI 走哪套；`ui_skin.gd` 目前讀的是 `assets/ui/quest/` |
| 3 | `assets/ui/pixel/bar_*.png` · `slot_*.png` · `rarity_*.png` · `panel_9slice_120.png` | 工程既有 UI 由 `ui_theme.gd` 程序化生成 | 包內是**貼圖版**，工程是**代碼繪製版** | 兩者可並存；若要走貼圖版，需另開一輪改 `ui_skin.gd` |

既有但**完全未被本輪觸碰**的目錄：`assets/fx/`（原 7 張關鍵幀）、`assets/ui/quest/`（27 PNG + 3 背景）、`assets/icons/equipment/`（12 檔）、`assets/dnf/`、`assets/tilesets/`、`assets/sprites/`、`assets/audio/`、`assets/fonts/`。

---

## 六、本輪明確**未做**的事

- ❌ 未改任何遊戲邏輯：`scripts/**`、`scenes/**`、`data/**` 一個字都沒動。
- ❌ 未建立 SpriteFrames（`.tres`）、未掛任何 `AnimatedSprite2D` 到 `player.tscn` / `enemy_base.tscn`。
- ❌ 未把裝備圖標路徑寫進 `data/equipment/*.json`。
- ❌ 未覆蓋／未刪除任何既有檔案。
- ❌ 未改素材檔名（保留包內原命名，與包 README 規範一致）。

---

## 七、下一步候選（等你拍板）

1. **接角色／怪物動畫**：建 `SpriteFrames` 資源並掛到 `player.tscn` / `enemy_base.tscn`，把 `w/sw/nw` 走鏡像。
2. **接裝備圖標**：把 `assets/weapons`・`assets/armor` 對應到 `data/equipment/*.json` 的 icon 欄位，並補 §5 的三處邊界裁定。
3. **接 UI 貼圖**：把 `assets/ui/pixel/` 接進 `ui_skin.gd`（現讀 `assets/ui/quest/`）。
4. **接背景／生態**：`assets/backgrounds/` 對應三個生態（森林／寒霜／火山）+ 主選單。

---

## 八、再生／加工管線（隨包交付，已歸位到 `tools/pixel_pipeline/`）

| 腳本 | 職責 |
|---|---|
| `pixel_pipeline.py` | 核心像素化：綠幕摳底 → 主色降採樣 → 固定畫布（腳底對齊／圖標居中）→ 色板量化 → alpha 二值化 |
| `sprite_sheet_cut.py` | 橫向多幀動作表切割（列投影找中心 → 統一縮放 → 腳底對齊 → 48 色量化） |
| `slime_squash.py` | 史萊姆程序化擠壓彈跳 |
| `ui_pixel_gen.py` | 代碼繪製 17 個 UI 組件 |
| `fx_anim_gen.py` | 4 技能序列幀 |
| `build_overview.py` / `scene_gen.py` | 產生 `PACK_OVERVIEW.png` 與實戰合成預覽 |
| `verify_pack.py` | 遞迴校驗色板合規／alpha 二值／尺寸 |
| `README.md` | 包原始說明（§三 動畫參數、§四 UI 組件、§六 待辦） |
| `import_pack.py` | **本輪新增**：素材包歸位匯入（乾跑／`--apply`／`--force`） |

### 色板策略

- **運行時烘焙資產**（`fx/`、`anim/`、`backgrounds/`、`ui/`、技能圖標）嚴格使用 `game_constants.gd` 的 **44 色 `PALETTE_ALL`**（經 `verify_pack.py` 校驗通過）。
- **角色／怪物／武器／裝備**走自適應量化（約 48 色），保留肉色／皮柄棕等 DNF 角色必需中間色。

---

## 九、包原始待辦（沿用包 README §六）

- 受擊／死亡目前僅做朝南（倒地後方向無關）；可按 `sprite_sheet_cut.py` 同流程補 `e/n`，再鏡像 `w`。
- 玩家 walk／attack 已 8 方向齊全；法師／弓手的對角方向由實作幀 + 鏡像構成。
- 怪物目前 4 小怪 + 1 BOSS 的 idle／attack，待補：小怪 8 方向移動、受擊／死亡、更多生態怪物、更多 BOSS 與 BOSS 技能。
- 剩餘裝備（腿甲、戒指 B、更多套裝）與武器強化外觀可繼續擴展。
- 遊戲內動圖已由 `anim/` 序列幀與角色動作幀覆蓋，不依賴演示視頻。

---

## 十、缺口补齐轮（2026-09-21 · 按代碼反向對帳補真缺口）

> 依據「代碼正在索要的路徑 vs 實際檔案」反向對帳，補齊六類**真缺口**，並完成接線。
> 風格延續嚴謹 16-bit 2D 像素風；全數 PNG 已 `godot --headless --import` 生成 `.import`（本工程 `.gitignore` 要求 `.import` 入庫）。
> `verify_ui_assets.gd` headless 回歸 **0 項失敗**（27/27 UI、8/8 稀有度、62/62 裝備圖標、15 枚唯一圖標、敵人 25/25 真精靈）。

### 10.1 怪物內建單張（`assets/sprites/enemies/`，16 檔）—— 補齊 monsters.json 的 `sprite_path`

`enemy_base.gd` 四級優先鏈的**第 ② 級（bundled 單張）**此前恆空（只靠 gitignored 第三方 `dnf/normalized/` 第 ③ 級兜底）。本輪 16 檔全數命中 bundled（headless 實測 `source=bundled ×16`），統一為自有可入庫像素風、版權安全。

| 規格 | 尺寸 | 數量 | 來源 |
|---|---|---:|---|
| 小怪（×0.25 顯示 32px） | 128×128 | 14 | 4 張復用包內形象規整（slime_acid/skeleton_warrior/imp_hellfire）+ 10 張新生成 + 2 張換色 |
| BOSS（×0.25 顯示 64px） | 256×256 | 2 | boss_bone_tyrant（骨獄暴君，新生成）、boss_ember_lord（惡魔領主，復用） |

14 小怪：spider_cave、bat_swarm（飛行，畫布內懸浮）、slime_acid、skeleton_warrior、mushroom_spore、warg_dark、imp_hellfire、golem_ember、brute_butcher、frozen_husk、pyromancer_cultist、hound_ash（warg 換色·炭灰餘燼）、wraith_frost（飛行懸浮）、ice_wraith（wraith 換色·霜青）。
腳底對齊 baseline、alpha 二值化；飛行單位（蝙蝠／幽魂）在畫布內上抬 14–16px。

> 現為**單張靜態立繪**（`single_frame_set`，idle 一幀）。後續如需 walk/attack/受擊/死亡 × 8 方向，沿用 `pixel_pipeline.py` + `sprite_sheet_cut.py` 出多幀集放到 `dnf/normalized/<id>/`，或擴充 bundled 為多幀。

### 10.2 高階稀有度框（`assets/ui/quest/`，3 檔）

| 檔案 | 色階 | 顏色 |
|---|---|---|
| `slot_mythic_48.png` | 5 MYTHIC 神話 | 猩紅 `FF2D55` |
| `slot_set_48.png` | 6 SET 套裝 | 套裝青綠 `2FA37A` |
| `slot_hidden_48.png` | 7 HIDDEN 隱藏 | 五色循環彩虹框 |

`ui_skin.gd` 的 `RARITY_SLOT` 5/6/7 不再 clamp 到橙，改指向各自專屬框（此前 22 件高階裝備被誤導成橙框）。

### 10.3 技能圖標（`assets/ui/quest/`，2 枚）

| 檔案 | 技能 id |
|---|---|
| `skill_icon_lightning_chain_48.png` | lightning_chain（紫底金雙段閃電 + 連鎖節點） |
| `skill_icon_poison_cloud_48.png` | poison_cloud（深綠毒霧團） |

已接 `level_scene.gd` 的 `SKILL_ICON`（此前列表無此二 id，雷/毒技能進出戰欄會顯示空槽）。

### 10.4 專屬裝備圖標（`assets/icons/equipment/`，新增 6 枚）

| 檔案 | 部位 | 接線 |
|---|---|---|
| `equip_legs_48.png` | 腿甲（深鐵板甲雙腿 + 膝甲） | 5 件腿甲（2 普通 + 3 套裝）原借胸甲 → 全改本圖 |
| `equip_ring_b_48.png` | 戒指 B（銀戒藍寶，區別於戒指 A 金戒紅寶） | 3 件 ring_b 原借戒指 A → 全改本圖 |
| `equip_hammer_48.png` | 錘（白錘頭金紋） | 2 件錘原借斧 → 改本圖 |
| `equip_orb_48.png` | 副手法器（藍水晶球金座） | **圖等數據**：尚無武器數據條目 |
| `equip_quiver_48.png` | 副手箭袋（棕袋紅羽） | **圖等數據**：尚無武器數據條目 |
| `equip_offblade_48.png` | 副手副刃（銀匕金柄） | **圖等數據**：尚無武器數據條目 |

接線後唯一裝備圖標 **12 → 15 枚**；裝備總數仍 **62 件**（本輪未新增武器數據條目，法器/箭袋/副刃的 archetype/affix 平衡留待設計裁定）。

### 10.5 套裝徽章（`assets/sprites/items/`，3 檔，48×48）

`set_emblem_frostbite.png`（霜噬·金邊藍底雪花）、`set_emblem_emberpath.png`（燼途·金邊紅底火焰）、`set_emblem_oathkeeper.png`（守誓者·金邊灰底盾劍）。路徑即 `sets.json` 的 `emblem_path`，`config_loader.gd` 載入 SetData（目前尚無 UI 消費，作為後續套裝界面的現成素材）。

### 10.6 本輪改動的代碼/數據

| 檔案 | 改動 |
|---|---|
| `scripts/ui/ui_skin.gd` | TEX +5（3 稀有度框 + 2 技能圖標）；RARITY_SLOT 5/6/7 指向專屬框 |
| `scripts/run/level_scene.gd` | SKILL_ICON +lightning_chain / poison_cloud |
| `data/equipment/armor.json` | legs_plate / legs_guardian icon → equip_legs |
| `data/equipment/set_pieces_{frostbite,emberpath,oathkeeper}.json` | 3 套裝腿 icon → equip_legs |
| `data/equipment/jewelry.json` | ring_rift_b / ring_storm / ring_echo icon → equip_ring_b |
| `data/equipment/weapons.json` | hammer_earthshaker / hammer_glacier icon → equip_hammer |
| `tools/verify_ui_assets.gd` | EXPECT_TEX +5；唯一圖標斷言 12→15；腿甲斷言改為「0 借胸甲」；封面斷言同步為「素材包背景優先」新優先序 |

### 10.7 假缺口（無需出圖，已確認）

- `res://scenes/levels/ch1_l01..l06.tscn` ×6：`chapter1.json` 曾登記 `scene_path` 指向這 6 個**不存在**的場景。
  **訂正（2026-09-22）**：該欄位**並非死字段** —— `scene_manager.gd::change_to_level()` 第 124 行確實會讀它，
  只是「欄位有值但檔案不存在 ⇒ 回退通用容器」與「欄位為空 ⇒ 命名約定兜底後同樣回退」**最終結果等價**，
  故仍判「無需出圖」。已於 2026-09-22 **刪除這 6 條欄位**（`LevelData.scene_path` 欄位本身與三級解析邏輯**保留**，
  將來某關要做專屬場景時直接填即可）；刪後全量回歸 55 腳本全綠。

### 10.8 有圖無人接（屬接線/管線，非缺圖，本輪未動）

- `assets/characters/`（213 檔三職業 8 方向）、`assets/monsters/`（19 檔）、`assets/fx/`（4 張）、`assets/anim/`（38 序列幀）目前無消費方；玩家與怪物仍走 `assets/dnf/normalized/`。這是一層待新建的資產管線，需另開接線輪（含幀資源 `.tres` / AnimatedSprite2D 掛載）。
- 包內 `assets/ui/pixel/`（17）、`assets/backgrounds/`（4）與 `assets/ui/quest/` 內容重複，後者才是 `ui_skin.gd` 實讀目錄，**不建議遷移**（會撞 verify 尺寸斷言）。

### 10.9 回歸契約收口（2026-09-22）

16 隻怪補上第②級 bundled 單張後，四級優先鏈是「先命中先返回」，故活體敵人一律取得單幀集
（此為**已拍板的產品契約**：怪物統一自有像素風靜態立繪，動作多樣性靠 `ANIM_FALLBACK` 回退鏈維持）。
連帶使 `verify_anim` E 段 3 條幀數斷言（idle 13 / walk 16 / attack 10）失效，收口方式如下：

| 項 | 處理 |
|---|---|
| E 段幀數斷言 | 改鎖 **bundled 契約**（活體敵人 `_clip.size() == 1`；idle 的 `exact` 仍為 true，walk/attack 因回退而 `exact=false`） |
| E 段新增哨兵 | 「第②級命中 `source=bundled`」＋「第③級 DNF `idle s` 仍為 13 幀（僅被遮蔽、**未刪除**）」——防止日後誤刪 DNF 素材無人發現 |
| tier③ 多幀覆蓋 | 由 **B 段**保留（`dnf_load_set` 直測 5 隻 × 動作 × 四方向），未減損 |
| 狀態機斷言 | IDLE / WALK / ATTACK / HURT 切換與「受擊期間攻擊不搶播」全數維持不變 |

> ⚠️ 實作註記：`resolve_character_set(id, "")` **不能**用來繞過第②級 —— 傳空字串時它會自行拼回
> `BUNDLED_SPRITE_DIR/<id>.png`（`enemy_base.gd:443-445`），仍命中 bundled。要直測 tier③ 得呼叫 `dnf_load_set(id)`。

改後 `verify_anim` **0 項失敗**；全量回歸 55 腳本 / 111.4s / **全部全綠**。


---

## 十一、怪物多幀動畫輪（2026-09-22 · 16 怪從靜態立繪升級為 5 動作 × 四方向）

### 11.1 結論：清單 6 類裡，只有「怪物多幀」是真缺口

本輪用戶清單列了 6 類（怪物 / 地磚 / 技能圖標 / UI 皮膚 / 裝備圖標 / 特效）。逐條對代碼真實消費路徑反向對帳後，**地磚、技能圖標、UI 皮膚、裝備圖標、特效 5 類均已存在且合格（見 11.5），唯一真缺口是怪物在運行時只有單幀**。已為 16 怪補上自有多幀，**不改遊戲邏輯**：放進 resolver 第①·五級 pack 槽位（`assets/pack/creatures/`）即自動生效，優先於第②級單張。

> 本輪**覆蓋了 10.9 的「靜態立繪契約」**：怪物不再是單張靜圖，而是 idle/walk/attack/hurt/die × 四方向多幀；`verify_anim` E/F 段已同步為「pack 多幀契約」。

### 11.2 產出規格

| 項 | 值 |
|---|---|
| 遊戲實際消費目錄 | `assets/pack/creatures/<id>/` |
| 檔名 | `char_<id>_<action>_<dir>_<NN>.png`（NN 從 01 起） |
| 動作 × 幀數 | idle **4** / walk **4** / attack **4** / hurt **3** / die **6**（共 21 唯一幀） |
| 方向 | s / e / w / n（怪物側 `dir_from_vector` 只產四向，**不消费對角**） |
| 每怪幀數 | 21 幀 × 4 方向 = **84 幀** |
| 總量 | **16 怪 × 84 = 1344 幀**（目錄另含 player 71 幀，非本輪；合計 1415 檔、1415 個 `.import`） |
| 畫布 | 小怪 **128×128**；BOSS（boss_bone_tyrant / boss_ember_lord）**256×256** |
| 播放 | fps 12；腳底中心（bottom-center）錨定；最近鄰縮放，無濾波 |

16 怪 id：`spider_cave`、`bat_swarm`、`slime_acid`、`skeleton_warrior`、`mushroom_spore`、`warg_dark`、`imp_hellfire`、`golem_ember`、`brute_butcher`、`frozen_husk`、`pyromancer_cultist`、`hound_ash`、`wraith_frost`、`ice_wraith`、`boss_bone_tyrant`、`boss_ember_lord`。

### 11.3 運動分型與方向策略

| 分型 | 怪物 | 動態 |
|---|---|---|
| `slime` | slime_acid | squash & stretch（擠壓拉伸） |
| `float` | bat_swarm、wraith_frost、ice_wraith | 上下浮動（無步態） |
| `biped` | 其餘 13（含 2 BOSS） | 步態 bob + 重心起伏 |

- **方向策略**：s 為形變正面；e / n 複製正面（立繪型怪的 e/n 本就與正面同構，與第三方 normalized 金標準一致）；w 為水平鏡像。
- **受擊 hurt**：朝白 lerp 閃白（3 幀）；**死亡 die**：壓扁 + 淡出（6 幀），死亡時由既有鬼影邏輯脫離本體播放。
- **製作方法（程序化形變，非 AI 逐幀）**：以上輪 16 張自有像素立繪為**唯一基準**，用 PIL 做 NEAREST 縮放、整數像素平移、水平鏡像、受擊閃白、死亡壓扁，腳底中心錨定。AI 逐幀無法保證同一怪物跨幀造型 / 錨點 / 配色一致，會產生抖動鬼影，故棄用。

### 11.4 優先鏈、回歸與未刪除項

- resolver 五級：① `user://content/characters` → **①·五 `res://assets/pack/creatures`（本輪，committed）** → ② bundled 單張（`sprites/enemies`）→ ③ `dnf/normalized` 多幀 → 占位。活體敵人命中 `source=pack`。
- 第②級單張（16 檔）、第③級 normalized 多幀均**未刪除、僅被遮蔽**；`verify_anim` E 段保留兩條哨兵（bundled 單張可載入、DNF idle s 仍 13 幀），B 段對 tier③ 的直測完整保留。
- `verify_anim` **E 段**改鎖 pack 多幀：`source=pack`、五動作×四方向幀數（4/4/4/3/6）、idle/walk/attack 為 4 幀且 `exact=true`、die 為 6 幀且 `exact=true`；**F 段**改為「注入『移除 die 的 clips 副本』驗證無鬼影 → 恢復真實 clips 驗證有鬼影」，新增 `_clear_ghosts()` 防止鬼影跨段殘留（不再依賴「素材本身有無 die」的前提）。
- **全量回歸 55 腳本 + self_check（111 項）全部全綠，85.1s（2026-09-22）**。

> ⚠️ **訂正（2026-09-22 稍晚，見第十二章）**：本章關於「第③級 `dnf/normalized` 多幀**未刪除、僅被遮蔽**、E 段保留 DNF idle 13 幀哨兵、B 段保留 tier③ 直測」的描述**已失效**。版權清理輪已物理刪除整個 `assets/dnf/` 第三方整合包並改寫解析鏈，第③級改為空集回退；解析鏈、導入符號與回歸基準以第十二章為準。

### 11.5 清單其餘 5 類復核（均已存在，本輪無需補）

| 清單項 | 實際位置 | 復核結論 |
|---|---|---|
| 地磚 3 套（森林 / 霜淵 / 火山） | `assets/tilesets/{forest,frost,volcanic}/atlas.png` + `atlas.json` | 32px tile，ground/wall/obstacle 齊全，合格 |
| 技能圖標（8 技能） | `level_scene.gd::SKILL_ICON` 覆蓋全部 8 個 id（6 唯一圖標，id↔檔名映射） | 不缺（lightning_chain、poison_cloud 已在） |
| UI 皮膚（35 邏輯名） | 代碼實讀 `assets/ui/quest/`（實測 35 PNG） | 齊全；清單說的 `ui/pixel/` 96×24 那套是**無消費方的備份**，屬假缺口，遷移會撞尺寸斷言 |
| 裝備圖標（10 槽） | `assets/icons/equipment/` 18 枚 | 含 legs / ring_b / hammer / orb / quiver / offblade，10 槽全有 |
| 特效（7 fx + 技能序列幀） | `data/fx.json` 7 條 sheet | 7 條 sheet 尺寸均滿足 `frame_w × frames`，不缺 |

### 11.6 歸檔、預覽與復現

- **遊戲消費檔**：`game/assets/pack/creatures/`（16 目錄 1344 幀 + 各 `.import`，已 headless 導入）。
- **歸檔副本（僅 PNG）**：`deliverables/pixel_pack_2026-09-21/creatures/`（16 目錄 1344 PNG）。
- **預覽**：`deliverables/pixel_pack_2026-09-21/previews/` —— `creatures_anim_overview.png`（16 行×21 幀 s 向總覽）+ 6 個 GIF（walk_slime / walk_skeleton / float_bat / walk_warg / combat_skeleton / combat_boss）。
- **復現腳本**（pixel_pack 根）：`creature_anim_gen.py`（全量生成 / `sheet` 出聯繫表；分型常量 `SLIME`/`FLOAT`、`ACTIONS`/`DIRS`）、`anim_preview.py`（GIF + 總覽）。改動作節奏改 `frames_for()` 後重跑全量，再 `godot --headless --import`。

### 11.7 已知邊界（要更細需另開手繪輪）

- 目前為**四方向**：s 正面形變、e/n 正面、w 鏡像；**無真側身 / 真背面、無對角 8 向**（怪物側代碼不消费 8 向，做了也無人接）。人形怪若要真側身 / 背面，需逐幀手繪，程序化無法從正面單張得到。
- 動態為**程序化微動**（步態 bob / squash / 前撲 / 閃白 / 壓扁死亡），非像素畫師逐幀肢體動畫；要更精細的肢體動作需逐幀手繪或骨骼方案。
- 玩家多職業（法師 / 弓手）、其餘裝備部位的資料條目（項鏈 / 戒指 / 副手法器 / 箭袋 / 副刃已有圖、尚無裝備條目）、新怪物與 BOSS 擴展，仍屬後續待辦，本輪只覆蓋既有 16 怪的動畫。

---

## 十二、非豆包素材版權清理（2026-09-22 · 第三方整合包與抓取鏈全部物理刪除）

> 用戶指令：整個專案所有「非豆包生成的素材」全部刪除，並刪除/重寫專門導入這些素材的代碼與導入邏輯，讓遊戲只跑豆包原創素材；**直接刪、不用詢問、不用回滾**；刪除導致的缺圖/缺功能記錄成清單後續補，本輪先完成「刪除不必要素材與相關代碼」。
> 結果：遊戲本體所有第三方素材（含拳皇 / 街霸 / 漫威 vs 卡普空 / 植物大戰殭屍 / Minecraft / DNF 等）已物理刪除，解析鏈改為只走豆包/用戶目錄；`godot --headless --import` 成功，**全量回歸 54 腳本 + self_check 111 項全部全綠（77.2s）**。

### 12.1 遊戲內已物理刪除的第三方素材

| 路徑 | 內容 | 規模 |
|---|---|---:|
| `game/assets/dnf/` | 第三方整合包：raw 原始下載 518、normalized 規整 1052、characters 194、fx 18、ui 26、_manifest（10 JSON + README） | **1819 檔 / 8.44 MB** |
| `game/dnf_preview.png` + `.import` | 第三方素材預覽抓圖 | 2 |
| `.godot/imported/dnf_preview.png-*.ctex/.md5` | 失效導入快取 | 2 |
| `deliverables/gstack/`（內 17 檔） | 16 張開發抓圖 PNG + `_contact.py`（保留空目錄） | 17 |

> `assets/dnf/` 的 README 自述素材來自 aigei.com 手動下載，`.gitignore` 對 `assets/dnf/**` 做二進制隔離；`data/` 配置本就不引用 dnf（icon_path 指 `icons/equipment/`、monsters sprite_path 指 `sprites/enemies`）。

### 12.2 已刪除的第三方抓取/開發工具（20 個）

- 5 個 `.gd` 三件套：`capture_dnf_pc`、`dnf_assets_capture`、`dnf_assets_preview`、`dnf_pc_proof`、`verify_dnf_ui`（連同名 `.tscn`）。
- 15 個 `.py`：`dnf_asset_pipeline`、`dnf_build_pc`、`dnf_main_menu_assets`、`dnf_normalize`、`dnf_stage_in`、`dnf_weapon_icons`、`aigei_batch_dl`（含 r4/r5/r6/r6_retry）、`aigei_dl_fx`、`aigei_extract_sets`、`aigei_open`、`aigei_probe`。
- 回歸腳本數由 55 降為 **54**（`verify_dnf_ui` 已刪）。

### 12.3 交付目錄 / 工具工作目錄的第三方殘留清除

| 路徑 | 性質 | 規模 |
|---|---|---:|
| `deliverables/_quarantine_2026-09-22/bakimg/` | 第三方素材備份（dnf_album/dnf_char/dnf_monster/dnf_map/dnf_tileset/dnf_ui/dnf_skill 等，含 64 gif、bgm） | 779 檔 / 6.34 MB |
| `…/dot_vu/_disabled_old_normalized/` | 舊第三方 normalized 幀（boss_forest/ghoul/golem/player_alt_vx 等 + manifest） | 119 檔 / 0.37 MB |
| `…/dot_vu/sheets/` | 第三方選型圖集（拳皇/街霸/漫威卡普空/PVZ/三國志/RPG Maker/山海經/DNF 等拼合圖） | 55 檔 / 2.33 MB |
| `…/dot_vu/`（根） | 含第三方時期畫面的開發/QA/mock 截圖 | 47 張 |
| `…/dot_vu/` 下載清單 | `dnf_raw_catalog.json`、`icons_urls.json`、`icons_raw.txt`、`dl_urls.txt` | 4 |
| `.workbuddy-ai/aigei-profile/` | aigei 抓取用瀏覽器設定檔與快取（Chromium 分片/db/journal） | 227 檔 / **312.63 MB** |
| `.workbuddy-ai/tmp/`、`…/trash/` | 第三方封面裁切（hero_*/z_*）與開發截圖/廢棄按鈕 | 38 + 14 張 |

全專案圖片檔名第三方關鍵詞掃描（dnf/kof/street_fighter/marvel/capcom/pvz/minecraft/sanguo/shanhaijing/rpg_maker/album/…）**歸零**。

### 12.4 改寫的運行時代碼（只移除第三方路徑與符號，保留通用幀解析函數）

| 檔案 | 改動 |
|---|---|
| `scripts/enemies/enemy_base.gd` | 刪常量 `DNF_NORM_ROOT`、`dnf_load_set()`、`dnf_read_manifest()`；解析鏈第③級由回傳 dnf 多幀改為 `_dnf_empty(id)` 空集；`dnf_load_dir()` 去 `use_manifest`（現兩參）、meta 恆空、canvas 由紋理實測、fps 恆 12、source 由 `dnf` 改 `local`；`_dnf_empty` source 改 `missing` |
| `scripts/player/player_controller.gd` | 刪死常量 `DNF_NORM_ROOT`、`DNF_GAME_SCALE`；`DNF_WHO` 改名 `PLAYER_ART_ID="player"`（定義 + 調用兩處） |
| `scripts/ui/ui_skin.gd` | 刪整段 DNF 素材：常量 `DNF_UI_ROOT`、`TEX_DNF`（12 鍵）、靜態 `dnf_texture()`；TEX 封面回退改生態 backdrop |
| `scripts/ui/main_menu_screen.gd` | 刪英雄立繪/武器展示欄常量與 `_build_showcase()`、`_hero_atlas()`、`_add_hero_shadow()` 三函數及 `_ready` 調用；封面優先序改為 main_menu_bg → forest backdrop → 純黑 |
| `scripts/core/content_paths.gd` | 註釋舉例 `EnemyBase.DNF_NORM_ROOT` → `PACK_CREATURE_ROOT` |
| `tools/capture_main_menu.gd` | 僅更新用途註釋（安全降級） |
| `tools/verify_anim.gd` | B 段改遍歷 16 怪 `pack_load_set()` 驗五動作×四方向（4/4/4/3/6）；C 段玩家改 pack 八方向；D/E/G 段移除 dnf/use_manifest 哨兵，第③級改測空集回退 |
| `tools/verify_ui_assets.gd` | 封面分支刪 `dnf_texture("cover")`；玩家由 A/B 兩套改單條 `pack_load_set("player")` |

### 12.5 清理後的角色解析鏈（`enemy_base.gd::resolve_character_set`）

① `user://content/characters`（用戶目錄）→ **①·五 `res://assets/pack/creatures`（豆包，committed，16 怪 1344 幀 + 玩家 71 幀）** → ② bundled 單張（`sprites/enemies`，16 檔豆包像素）→ ③ **空集回退（原 dnf/normalized 已刪除）**。

> 歷史命名說明：`dnf_load_dir`、`dnf_load_user_dir`、`dnf_parse_names`、`_dnf_build_clips`、`_dnf_actions_of`、`_dnf_first_texture`、`_dnf_empty`、`_dnf_sorted`、`_dnf_cache`、常量 `DNF_GAME_SCALE`/`DNF_FEET_Y` 等**名字保留 dnf 字樣但只解析豆包/用戶目錄**，是通用幀解析器，無第三方含義（`enemy_base.gd` 已加註釋），勿當殘留刪除。`ui_theme.gd` 的 dnf 字樣僅為歷史配色註釋。

### 12.6 驗證（2026-09-22）

- `godot --headless --import` exit 0，全局類註冊正常，無報錯。
- `python tools/run_regression.py`：**54 個腳本全綠 + self_check「全部通過（111 項）」，77.2s，FAIL=0**。
- 危險引用掃描（`assets/dnf`、`dnf_texture`、`TEX_DNF`、`DNF_UI_ROOT`、`dnf_load_set`、`dnf_read_manifest`、`DNF_NORM_ROOT`、`aigei`、`hero_standee`、`verify_dnf` 等）在 `game/` 的 `.gd/.tscn/.json/.tres/.cfg` **歸零**。
- 遊戲內圖片（1827 張）全部為豆包素材：pack/creatures 1415 幀、ui/quest、icons/equipment、tilesets、weapons/armor、fx、anim、characters、monsters、backgrounds、previews；`assets/` 之外無散落圖片。

### 12.7 刪除產生的待補清單（本輪只記錄，後續補）

1. **主選單英雄立繪**：原 `hero_standee` 為第三方（180×236，底裁 14px），已隨 `main_menu_screen` 一併移除，目前封面走背景圖。
2. **主選單武器展示欄 2 圖**：原 `weapon_sword_blue/green`（展示 96×96、源 48×48），展示代碼已整體移除；**補豆包像素圖後需重新接線**（`_build_showcase` 已刪）。
3. **玩家 idle / hurt / death 僅朝南**：walk/attack 八方向已齊（64 幀），其餘方向目前走 `resolve_clip` fallback（idle_s 1、hurt_s 2、death_s 4）。
4. **16 怪動畫為程序化形變微動**（非逐幀手繪肢體），質量邊界見 §11.7；要更精細需手繪/骨骼輪。

### 12.8 保留項（非第三方或非圖片素材，已核實）

- **字體** `assets/fonts/`（ChillBitmap_16px、Cubic_11）為 SIL OFL 可商用開源像素字體，非圖片、文字必需，**保留**。
- 隔離區殘留為**豆包素材副本 + 開發環境快照**（`asset-swap-2026-09-22`、`pixel_pack_2026-09-21` 副本、`tilesets_procedural`、`dot_vu` 的 PIL/OFL 字體/Godot 快取/saves/日誌，已無第三方圖片）；遊戲不引用，正本在 `game/assets` 與 `deliverables/pixel_pack_2026-09-21`，**如需進一步瘦身可整個刪除 `_quarantine_2026-09-22`**。
- 項目根 `ui/`（330 張，豆包像素包早期副本）、`.fxwork/`（豆包 fx 程序化工作目錄）、`.preview/`（工具快取）為豆包產物/工具檔，**保留**。
- 豆包生成但「有圖無人接」的 `assets/characters/`、`assets/monsters/`、`assets/ui/pixel/`、`assets/anim/`、`assets/fx/` 默認保留（接線缺口，非版權問題）。
- 本檔較早章節（§2.5、§5、§10.1、§10.8、§10.9、§11.4 等）凡提及 `assets/dnf/`、`normalized`、第三方兜底者，**均為該歷史輪次的快照，自本章起失效**，以本章為準。
