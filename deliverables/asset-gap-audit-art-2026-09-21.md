# 七傳說 · 素材缺口規格清單（美術）
> 任務：TASK-ASSET-GAP-ART（art-director 林繪澄）  
> 對象：team-lead + engineering-lead（handoff）  
> 製作日期：2026-09-21｜專案：`D:\七傳說\game`（Godot 4.7.2，邏輯解析度 640×360，Nearest 過濾，整數倍縮放）

---

## 0. 鐵律與既定約定（不可破）

| 項 | 規則 | 來源 |
|---|---|---|
| 邏輯解析度 | 640×360，1× 整數倍 | `game_constants.gd::VIEWPORT_WIDTH/HEIGHT` |
| 畫布對齊 | 角色 / 怪物 / BOSS：**腳底居中**；武器 / 裝備 / 圖標：**畫布居中** | `game_constants.gd::SPRITE_ANCHOR_OFFSET (24,44)` + 美術規範 0.7 §2.1 |
| 運行時烘焙色板 | **44 色 `PALETTE_ALL`** 強制（FX / 背景 / UI / 技能圖標） | `game_constants.gd::PALETTE_ALL` |
| 角色 / 怪物 / 武器 / 裝備色板 | 自適應量化 ~48 色（保留肉色 / 皮柄棕） | PACK_OVERVIEW §八 色板策略 |
| Alpha | **二值**：0 或 255，硬邊 | `fx_anim_gen.py::binarize()`、`pixel_pipeline.py` |
| 縮放過濾 | 全項目 Nearest，禁止 Linear | `project.godot` |
| 玩家腳底錨點 | (24, 44) ⇒ 螢幕 48×48 | `GameConstants.CHARACTER_SPRITE_SIZE=48`、`SPRITE_ANCHOR_OFFSET` |
| 裝備槽 icon 尺寸 | 背包 48×48 / 裝備槽 64×64 | `GameConstants.UI_SLOT_SIZE_BAG/EQUIP` |
| 套裝徽記尺寸 | 16×16 / 進度條 8×8 | `GameConstants.SET_EMBLEM_SIZE / SET_BADGE_SIZE / SET_PROGRESS_BAR_HEIGHT` |

### 命名契約（既有，**不許改**，詳 §三）

| 類別 | 規則 | 引擎消費點 |
|---|---|---|
| 玩家 | `char_<class>_<action>_<dir>_<NN>.png` | `enemy_base.gd::dnf_parse_names`（line 588） |
| 怪物 | `char_<name>_<action>_<dir>_<NN>.png` | 同上；**包內寫成 `mon_*` ⇒ 解析器會跳過（line 593 強制 `begins_with("char_")`）** |
| 動作集合 | `idle / walk / attack / hurt / die` | `enemy_base.gd::ANIM_IDLE/WALK/ATTACK/HURT/DIE`（line 164-168） |
| 方向集合 | `n / e / s / w`（4 向） | `enemy_base.gd::DIR_N/E/S/W` + `dir_from_vector()` line 578（永遠只回傳這 4 個） |
| 武器 | `weapon_<type>_48.png`（type ∈ sword/axe/hammer/dagger/staff/longbow/shield/focus/quiver/offblade） | `data/equipment/weapons.json::icon_path` 目前**只指向 `icons/equipment/equip_*.png`**，未對應 `weapon_*` |
| 裝備 | `equip_<slot>_48.png`（slot ∈ helmet/chest/gauntlet/legs/boots/main_hand/off_hand/amulet/ring_a/ring_b） | `data/equipment/armor.json + jewelry.json::icon_path` 全部走 `icons/equipment/` |
| FX 關鍵幀 | `fx_<skill>_px96.png`（96×96，**單張**） | `data/fx.json` + `assets/fx/` |
| FX 序列幀 | `anim/<skill>/fx_<skill>_<NN>.png`（NN 從 00 起） | **無消費方**；需新增 `SkillFX` / `BattleVFX` 接線 |
| 生態背景 | `backdrop_<biome>_640x360.png` | `ui_skin.gd::TEX.backdrop_forest/frost/volcanic` |
| UI 元素 | `panel_9slice_120 / btn_*_96x24 / bar_hp_mp_160x16 / slot_*_48 / rarity_*_48 / skill_slot_48 / skill_<name>_48` | `ui_skin.gd::TEX`（**路徑指向 `ui/quest/`，不是 `ui/pixel/`**） |

### 關鍵契約差異（§五 詳述）

**包內 5 個怪物形象 vs 引擎解析契約** —— **完全無法對接**：

| 軸 | 包內現況 | 引擎契約 | 缺口 |
|---|---|---|---|
| 檔名前綴 | `mon_<name>_<action>_<dir>_<NN>.png` | 必須 `char_*` | **解析器 0% 命中**（line 593 `if not base.begins_with("char_"): continue`） |
| 方向 | `n/ne/e/se/s/sw/w/nw`（8 向） | `n/e/s/w`（4 向） | ne/nw/sw/se 雖被解析器存入字典，但 `dir_from_vector()` 永遠不查詢 ⇒ **寫了 4 個方向 ≈ 0 消費** |
| 動作 | 只有 `idle`（slime），或 `idle+attack`（skel/imp） | `idle/walk/attack/hurt/die` | walk/hurt/die 全缺 ⇒ 全部靠 `ANIM_FALLBACK` 鏈降級（line 501） |

**武器命名不一致**：
- 包內 `weapons/weapon_*.png` 用 `weapon_` 前綴
- 工程既有 + `data/equipment/*.json` 一律用 `equip_` 前綴（`equip_sword_48.png` 等）
- 包內 `armor/equip_*.png` 與 `icons/equipment/equip_*.png` 同名前綴 ⇒ **武器不同前綴是唯一的命名風格漏洞**

---

## 一、缺口總表

> 優先級定義：  
> **P0** = 阻塞可玩性 / 被代碼斷言 / 數據→代碼 對接必填  
> **P1** = 視覺降級可接受但明顯殘缺（如只能靠 fallback 跑）  
> **P2** = 不影響運行 / 純內容豐富度 / 可後置

| # | 類別 | 缺口 | 影響面 | 優先級 | 理由 | 歸屬（建議） |
|---|---|---|---|---|---|---|
| 1 | 怪物形象 | **16 隻怪**全部在 `res://assets/sprites/enemies/<id>.png` 找不到；且 `assets/sprites/enemies/` 目錄**整個不存在** | 所有怪物處置永遠走 `ANIM_FALLBACK` 4 級鏈降級；當前全場實際由 `assets/dnf/normalized/` 兜底（僅 walk） | **P1** | 運行不崩；目前 ② 槽位空、③ 槽位只有 walk ⇒ 不會白畫面，但視覺永遠不是 idle | 美術 |
| 2 | 套裝徽記 | `res://assets/sprites/items/set_emblem_{frostbite,emberpath,oathkeeper}.png` **3 個缺口**；`assets/sprites/items/` 目錄不存在 | `ConfigLoader.get_set()` 載入 `emblem_path` 字段但**全項目無 UI 消費** | **P2** | 無視覺後果；`set_emblem_*` 必須做但不被任何 `.tscn` / `level_scene.gd` 引用 | 美術 |
| 3 | 關卡 tscn | `ch1_l01..ch1_l06.tscn` **6 條不存在的「缺口」** | 0（`level_data.gd::scene_path` 從未被讀取） | **排除** | 不真實缺口，`level.tscn` 一份通用場景 | — |
| 4 | 稀有度框 | 5/6/7（MYTHIC / SET / HIDDEN）**clamp 到 `slot_orange`**（`ui_skin.gd::RARITY_SLOT` line 112-114 自承「缺口」） | MYTHIC（紅 0.02%）、SET（綠 0.40%）、HIDDEN（彩 0.01%）的裝備顯示成橙框 | **P1** | 8 檔色板（`RARITY_COLORS`）+ `RARITY_FRAME_STYLES` 早就有紅 / 青綠 / 彩漸變，只是**沒人畫框貼圖**；GDD 1.4 節問題 4 是已拍板的硬性需求 | 美術 |
| 5 | 技能圖標 | `lightning_chain`（雷）+ `poison_cloud`（毒）**無圖標無消費** | 玩家把元素技能從 `slot=0`（技能庫）拖進 `slot>=1`（出戰欄）後，UI 無對應圖標 ⇒ `level_scene.gd::SKILL_ICON` 取空字串 ⇒ 整欄空槽 | **P1** | `skills.json` 已有 2 個技能但 SKILL_ICON 表只覆蓋 6 個；當前 slot≥1 全是物理系不觸發，等元素系技能上出戰必壞 | 美術 |
| 6 | 腿甲 / 戒指 B / 副手圖標 | `data/equipment/armor.json` 有 `legs_plate / legs_guardian` 等條目 ⇒ `icon_path` 全走 `icons/equipment/`，且**該目錄無 `equip_legs_48.png`** | 腿甲部位永遠 fallback 顯示 chest 圖標（不可接受：腳部 / 胸部混淆） | **P1** | `GameConstants.EQUIP_SLOT_KEYS` 已有 `legs`，`ui_skin.gd::RARITY_SLOT` 也用 5 階欄位；缺口就在 `icons/equipment/equip_legs_48.png` 一張 | 美術 |
| 6b | 副手原型 | `data/equipment/weapons.json` 只有 `shield`（1 個 off_hand 條目，line 130）；包內另有 `weapon_orb / weapon_quiver / weapon_offblade / weapon_hammer` **4 個無數據條目** | 副手永遠只能出盾；法器 / 箭袋 / 副刃 / 錘無圖標可走 | **P1** | `GameConstants.WEAPON_ARCHETYPE` 已列 10 個（line 263-274），數據只填了 7 個；3 個空 archetype 連底圖都沒接 | 美術 + 文策（補數據） |
| 7 | 玩家三職業 | 包內 `characters/` 213 檔（warrior / mage / archer × 8 向 walk/attack + hurt/death 南）；玩家現走 `assets/dnf/normalized/player/`（33 張） | 包的 3 職業**完全未接**；視覺永遠是 DNF 統一形象 | **P2** | 不影響可玩性，但角色面板「創建角色 / 選職業」永遠看不到包內形象 | 美術 + 工程（接線） |
| 8 | 怪物 5 形象 | 包內 `monsters/` 19 檔（slime_forest × 4 + slime_frost × 4 + skeleton × 5 + imp_volcanic × 5 + BOSS demon_lord × 1）；數據 16 隻怪 ID **沒有一個與包內 5 個形象對應** | 見 §三 命名錯配 | **P1** | 工程可透過 `monsters.json::sprite_path` 改路徑走包內形象，但要先解決 `mon_*` → `char_*` 重命名 + 動作缺失 | 美術 + 文策（對齊） |
| 9 | FX 關鍵幀 | `data/fx.json` 已有 7 條；包內 `fx/fx_{slash,fire,frost,thunder}_px96.png` 4 張**未被引用** | 4 元素技能（fireball / frost_nova / lightning_chain / cleave）施放無獨立特效貼圖，命中只靠 `slash_arc / hit_spark` 兜底 | **P1** | 元素系是 4 個獨立技能的核心視覺標識 | 美術 + 工程（接線） |
| 10 | FX 序列幀 | `assets/anim/<skill>/` 38 張（slash 9 + fireburst 10 + frostnova 10 + thunder 9），**全項目零引用** | 技能施放動畫只有單幀關鍵幀，無連續運動感 | **P2** | 包內的 4 個 GIF 預覽非常完整；但 `SkillFX` / `BattleVFX` 模組**尚未實作**才完全沒消費 | 美術 + 工程（新模組） |
| 11 | 生態背景 | `assets/backgrounds/` 4 張（forest / frost / volcanic / main_menu_bg）；**3 張生態 + main_menu_bg 與 `assets/ui/quest/backdrops/` 同名重複**（`ui_skin.gd` 在讀 quest 那份） | 0（兩套並存，現讀的是 ui/quest 那套） | **P2** | ui/quest 同名件**已 import + 內容不錯**；包內 4 張當備份，等活松動時再切換 | 美術（待裁定） |
| 12 | UI 像素包 | `assets/ui/pixel/` 17 張 + `assets/ui/skill_icons/` 4 張；**與 `assets/ui/quest/` 同名重複**（按鈕 96 vs 128 寬差異、panel 9-slice 同名、技能圖標同名） | 同上（兩套並存，現讀 ui/quest） | **P2** | 同 §五 的三處邊界 | 美術（待裁定） |
| 13 | 受擊 / 死亡單方向 | 角色 hurt/death **只有朝南**（包 README §六 自承） | 朝其他方向受擊時也播放朝南動作（角色「面南挨打」會穿幫） | **P2** | 對俯視刷寶 ARPG 影響小（死亡趴下、hurt 是反彈瞬間） | 美術（補圖） |
| 14 | 怪物動作不全 | 包內怪物只有 idle（slime）或 idle+attack（skel/imp）；**無 walk 8 向、無 hurt、無 death** | 怪物移動永遠 fallback 到 idle（史萊姆「彈著彈著追玩家」反而貼切）；hurt 不播 ⇒ 受擊無視覺反饋；death 不播 ⇒ 用 `death_puff`（已存在）兜底 | **P2** | `enemy_base.gd::ANIM_FALLBACK` 兜得很穩；死亡用現成粒子；hurt 缺是**視覺級**缺失 | 美術 |
| 15 | 腿甲圖標 | `assets/armor/` 只有 helmet/chest/gauntlet/boots/amulet/ring —— **沒有 legs** | 與 §6 同因（包內也沒補） | **P1** | 同 §6 | 美術 |

---

## 二、逐條美術規格

### 2.1 怪物 16 隻（§1 第 1 條）

> 路徑建議：`assets/sprites/enemies/<id>.png`（建立該目錄）  
> 解析契約：`enemy_base.gd::resolve_character_set` ② 槽位（單張 PNG）；每張 PNG 即一隻怪  
> 解析順序：先試① user override → ② 這條路徑 → ③ DNF normalized → ④ 占位色塊

- **畫布**：192×192（小怪）/ 256×256（BOSS），腳底居中對齊（基線 = `canvas_h - 24`）
- **色板**：自適應 48 色（保留肉色 / 皮柄棕 / 史萊姆半透明綠 / 骷髏骨白）
- **Alpha**：二值 0/255（`verify_pack.py::verify_alpha_binarize`）
- **單張**：僅 idle 一幀（**第一步只滿足 `data.sprite_path` 不 404**，複動作在 §2.2 處理）
- **16 個 ID**（與 `data/monsters/monsters.json` 嚴格對齊）：
  ```
  spider_cave / bat_swarm / skeleton_warrior / slime_acid / brute_butcher /
  wraith_frost / boss_bone_tyrant / boss_ember_lord / mushroom_spore /
  warg_dark / golem_ember / imp_hellfire / hound_ash / pyromancer_cultist /
  frozen_husk / ice_wraith
  ```
- **檔名格式**（**注意**：單張路徑就一個 ID；不是 char/mono 命名）：直接 `<id>.png`  
  例：`assets/sprites/enemies/skeleton_warrior.png`、`assets/sprites/enemies/boss_ember_lord.png`
- **建議尺寸**：先按 DNF normalized 的 manifest canvas（line 522 `dnf_read_manifest` 讀 `normalized/_manifest/<who>_manifest.json::canvas`）—— slime 192、BOSS 256、其他基本 192
- **管線**：`tools/pixel_pipeline/pixel_pipeline.py`（綠幕摳底 + 主色降採樣 + 48 色量化 + alpha 二值）

### 2.2 怪物 5 形象接入（§1 第 8 條 / §三命名錯配）

> 路徑：`assets/monsters/<name>/`  
> 引擎消費點：`enemy_base.gd::resolve_character_set` ③ 槽位（DNF normalized）；目前走 `assets/dnf/normalized/<name>/`  
> **必須先做重命名**（§五決策點 A）

**若決策為「出圖時就對齊契約」**（推薦）：
- **畫布**：slime/skeleton/imp = 192×192；BOSS = 256×256（與包內現況一致）
- **色板**：自適應 48 色
- **檔名格式**：`char_<name>_<action>_<dir>_<NN>.png`（**前綴從 `mon_` 改 `char_`**）
- **動作集合**：`idle` + `attack`（包內現狀）；`walk/hurt/die` 走 `ANIM_FALLBACK`
- **方向集合**：僅 `n/e/s/w` 4 向（**不要做 ne/nw/se/sw**，運行情況見 §五決策點 B）
- **幀數**：idle 4 幀（slime）+ 1 幀（skeleton/imp/boss，已是現狀）；attack 4 幀（skeleton/imp，已是現狀）
- **fps**：idle 12fps 循環、attack 12fps 單次（與 `enemy_base.gd::_real_fps=12.0` 對齊）
- **管線**：
  - slime → `slime_squash.py <src> <out_dir> <prefix>`（程序化彈跳 4 幀，腳底對齊）
  - skel/imp → 直接複用包內檔案 + 重命名 `mon_*` → `char_*`，刪除 ne/nw/se/sw

### 2.3 套裝徽記 3 枚（§1 第 2 條）

> 路徑：`assets/sprites/items/set_emblem_{frostbite,emberpath,oathkeeper}.png`  
> 引擎消費點：`data/sets/sets.json::emblem_path` ⇒ `ConfigLoader.get_set().emblem_path`  
> **全項目無 UI 消費**（圖標可被預先生成，UI 模組階段 6 才接）

- **畫布**：16×16（`GameConstants.SET_EMBLEM_SIZE`），居中對齊
- **色板**：必須**嚴格 44 色 `PALETTE_ALL`**（運行時烘焙）
- **元素配色**：
  - `frostbite`：冰霜藍 `#6E9BE8` 主色（`PALETTE_ACCENT` 魔/冰·亮） + 白 `#DCE2E8` 描邊
  - `emberpath`：火焰橙 `#FF8A2B` 主色（`PALETTE_RARITY_SEMANTIC` 第 5 色 / `PALETTE_ACCENT` 血/危险·辉光） + 黑 `#0B0D10` 描邊
  - `oathkeeper`：金 `#D9A521` 主色（`PALETTE_ACCENT` 金/光·中）+ 黑描邊
- **設計**：六芒星 / 菱形 / 盾形 各自獨立幾何，**不依賴顏色區分**（色弱可訪問性，與 GDD 1.4 §問題 4 一致）
- **管線**：`ui_pixel_gen.py`（已歸位）—— 但需補此 3 枚的生成函數

### 2.4 稀有度框 3 枚（§1 第 4 條）—— 補 MYTHIC / SET / HIDDEN

> 路徑：`assets/ui/quest/slot_{mythic,set,hidden}_48.png`（與現有 `slot_*_48.png` 同目錄）  
> 引擎消費點：`ui_skin.gd::RARITY_SLOT` 索引 5/6/7（line 112-114）  
> **更新 `ui_skin.gd::TEX` 表**（新增 3 個條目，line 67 區）

- **畫布**：48×48，居中對齊
- **色板**：必須 44 色 `PALETTE_ALL`（UI 鐵律）
- **3 枚具體**：
  - `slot_mythic_48.png`：紅 `#FF2D55` 3px 描邊 + 金 `#F5D77A` 雙層外框（與 `MYTHIC_GOLD_FRAME_COLOR` 對齊；實作 `FrameStyle.SOLID_GOLD_DOUBLE`）
  - `slot_set_48.png`：青綠 `#2FA37A` 2px 描邊 + 四角菱形節點 `#F5D77A`（實作 `FrameStyle.SOLID_DIAMOND`）
  - `slot_hidden_48.png`：6 色漸變描邊 `#E8573F / #FF8A2B / #F5D77A / #6FB35C / #6E9BE8 / #B07DE0`（取自 `PRISMATIC_GRADIENT`） + 描邊寬 3px（實作 `FrameStyle.GRADIENT_FLOW`）
- **管線**：`ui_pixel_gen.py` 補三個函數：`gen_slot_mythic / gen_slot_set / gen_slot_hidden`

### 2.5 技能圖標 2 枚（§1 第 5 條）

> 路徑：`assets/ui/quest/skill_icon_{thunder,poison}_48.png`（與 `skill_icon_{slash,fireburst,frostnova,shadowdash}_48.png` 同目錄）  
> 引擎消費點：`ui_skin.gd::TEX.skill_icon_thunder / skill_icon_poison` + `level_scene.gd::SKILL_ICON` 表（line 1056）  
> **更新兩處**：
> - `ui_skin.gd::TEX` 加 2 條
> - `level_scene.gd::SKILL_ICON` 加 `"lightning_chain": "skill_icon_thunder"` 與 `"poison_cloud": "skill_icon_poison"`

- **畫布**：48×48，居中對齊
- **色板**：44 色 `PALETTE_ALL`
- **設計**：
  - `skill_icon_thunder_48.png`：閃電符號（黃 `#F5D77A` + 紫 `#7E44B8` 雙色描邊）
  - `skill_icon_poison_48.png`：毒霧符號（綠 `#6FB35C` 主色 + 紫 `#B07DE0` 邊緣）
- **管線**：`ui_pixel_gen.py` 補 `gen_skill_thunder / gen_skill_poison`

### 2.6 腿甲 / 戒指 B / 副手圖標（§1 第 6 條 / 6b）

> 路徑：`assets/icons/equipment/equip_<slot>_48.png`（與 `equip_helmet/chest/gauntlet/boots/amulet/ring` 同目錄、同前綴）  
> 引擎消費點：`data/equipment/{armor,jewelry,weapons}.json::icon_path`

#### 2.6.1 腿甲（**必須**）

- **檔名**：`equip_legs_48.png`（**新增**，目錄下原本沒有）
- **畫布**：48×48，居中對齊
- **色板**：44 色 `PALETTE_ALL`
- **設計**：金屬護腿剪影（金 `#D9A521` / 鋼灰 `#4E5866` 雙色 + 黑 `#0B0D10` 描邊）
- **管線**：`ui_pixel_gen.py` 補 `gen_equip_legs`

#### 2.6.2 副手 4 原型（**優先**：FOCUS / QUIVER / OFFBLADE）

- **檔名**：`equip_focus_48.png` / `equip_quiver_48.png` / `equip_offblade_48.png`（**統一 `equip_` 前綴以對齊現有 convention**）  
  ⚠️ **包內寫成 `weapon_orb_48.png` / `weapon_quiver_48.png` / `weapon_offblade_48.png`** —— 與既有 `equip_*` 不一致 ⇒ **決策點 C（§五）**：要麼改包檔名，要麼 `data/equipment/weapons.json` 全用 `weapon_*` 路徑（破壞現有 12 個 `equip_*`）
- **畫布**：48×48，居中對齊
- **色板**：44 色 `PALETTE_ALL`
- **設計**：
  - focus：寶石球（紫 `#B07DE0` 主體 + 金 `#D9A521` 底座）
  - quiver：箭袋皮（棕褐自適應 + 金屬環）
  - offblade：副刃（與匕首同款縮短版）—— 注意 `GameConstants.WEAPON_ARCHETYPE_SPRITE_SOURCE[9] = DAGGER`，**美術可選 0 新增幀**（複用 `equip_dagger_48.png`）
- **管線**：`ui_pixel_gen.py` 補 `gen_equip_focus / quiver`，offblade 直接複用 dagger

#### 2.6.3 錘（HAMMER）

- **檔名**：`equip_hammer_48.png`（或保留包內 `weapon_hammer_48.png`，取決於決策點 C）
- 包內已有 `weapon_hammer_48.png` ⇒ 若選 C 路徑一（`equip_*`），**重命名**；若選路徑二（`weapon_*`），**更新 `data/equipment/weapons.json` 已有條目的 `icon_path` 字段**
- **管線**：直接重命名 + `verify_pack.py::verify_alpha_binarize` 復跑

### 2.7 玩家三職業（§1 第 7 條）

> 路徑：`assets/characters/char_<class>_<action>_<dir>_<NN>.png`（包內已就位）  
> 引擎消費點：`player_controller.gd::dnf_load_set`（與 enemy_base 同套）—— 玩家原本走 `dnf/normalized/player/`，**包內 3 個職業完全沒接**  
> **需工程側加 `PlayerClass` 字段 → 映射到 `warrior/mage/archer` 子目錄**（決策點 D，§五）

- **畫布**：192×192，腳底居中對齊
- **色板**：自適應 48 色
- **動作**：`idle`（1 幀 s）+ `walk_<dir>`（4 幀 × 8 向）+ `attack_<dir>`（4 幀 × 8 向）+ `hurt_s`（2 幀）+ `death_s`（4 幀）
- **fps**：walk 8–10 fps 循環；attack 12 fps 單次；hurt 10 fps 單次；death 8 fps 單次停末幀
- **方向**：`n/ne/e/se/s/sw/w/nw`（8 向）—— 與怪物決策點 B **相反**：
  - 玩家是主動旋轉的近戰格鬥，**保留 8 向是必要的**（這也是包原意）
  - 但 §五決策點 B 仍要裁定：**包內 4 個對角方向需另寫 `_dir_from_vector_8()`** 或允許鏡像
- **管線**：**直接複用包內檔**，**命名已對齊契約**（`char_<class>_*`，前綴正確）；只需工程側加 player class 選擇 UI

### 2.8 FX 關鍵幀（§1 第 9 條）

> 路徑：`assets/fx/fx_<skill>_px96.png`（包內已就位 4 張）  
> 引擎消費點：`data/fx.json::effects[<id>].texture`  
> **更新 `data/fx.json`**（line 67 區），新增 4 條：

| id | texture | frame_w/h | frames | 對應技能 |
|---|---|---:|---:|---|
| `fireball_keyframe` | `fx_fire_px96.png` | 96 | 1 | fireball（slot≥1 上出戰後） |
| `frost_nova_keyframe` | `fx_frost_px96.png` | 96 | 1 | frost_nova |
| `lightning_chain_keyframe` | `fx_thunder_px96.png` | 96 | 1 | lightning_chain |
| `cleave_keyframe` | `fx_slash_px96.png` | 96 | 1 | cleave（取代 slash_arc） |

- **畫布**：96×96，居中對齊
- **色板**：**44 色 `PALETTE_ALL`**（FX 鐵律）
- **Alpha**：二值 0/255
- **管線**：`pixel_pipeline.py` 校驗（已是出圖後驗收階段）

### 2.9 FX 序列幀（§1 第 10 條）

> 路徑：`assets/anim/<skill>/fx_<skill>_<NN>.png`（包內已就位 38 張）  
> 引擎消費點：**無**；需新增 `SkillFX.tscn` / `scripts/vfx/battle_vfx.gd`  
> **這是一個新模組，屬於工程階段 6+**

- **畫布**：96×96，**與 FX 關鍵幀同畫布可疊加**（包已如此）
- **色板**：`PALETTE_ALL`（FX 鐵律）
- **幀率**：14 fps，單次不循環（PACK_OVERVIEW §2.4）
- **序列**：slash 9 / fireburst 10 / frostnova 10 / thunder 9（NN 由 00 起，**注意**與關鍵幀 `_NN.png` 編號從 00 起不同）
- **管線**：`fx_anim_gen.py` 已能生成；現成可驗收

### 2.10 受擊 / 死亡單方向（§1 第 13 條）

> 路徑：`assets/characters/hurt_<dir>/` / `assets/characters/death_<dir>/`（補 e/n 後再鏡像 w）  
> **包內只有 `hurt_s/` `death_s/`**（PACK_OVERVIEW §九 自承）

- **畫布**：192×192，腳底居中
- **方向**：補 `e` + `n`（2 個 × 2 動作 = 4 個動作），w 用 e 鏡像，ne/nw/sw/se 走就近
- **幀數**：hurt 2 幀、death 4 幀
- **管線**：`sprite_sheet_cut.py`（既有，橫向多幀切割 + 腳底對齊 + 48 色量化）

### 2.11 怪物動作補完（§1 第 14 條）

> 優先補 hurt（受擊反饋缺失最影響打擊感）與 walk（移動時永遠 fallback 到 idle）

- **hurt 2 幀**：所有怪物共用一個 `monster_hurt_strip_96x96.png` 風格（**單方向，紅閃一下**）  
  視覺一致優先，圖標級即可（不需要每怪單獨出）
- **walk 4 幀 4 向**：史萊姆用 `slime_squash.py` 程序化（已就緒）；skel/imp 走 `sprite_sheet_cut.py`
- **death**：可用現成 `death_puff.png`（`fx.json` line 65 + 已就位），美術可選不補

---

## 三、命名錯配對齊方案（§1 第 8 條決策）

### 3.1 5 包內怪物形象 ↔ 16 數據 ID 映射表

| 數據 ID | 生態 | tier | 建議包內形象 | 理由 |
|---|---|---|---|---|
| `slime_acid`（酸液史莱姆） | forest | normal | **`mon_slime_forest`** | 史萊姆族共用骨架 + 毒色覆蓋；色板自適應量化即可把綠換綠（毒） |
| `slime_acid`（備選） | forest | normal | **新出 `char_slime_acid`**（綠色版） | 若不接受色覆蓋共用，獨立出；包未提供 |
| `frozen_husk`（冰封尸骸） | frost | normal | **`mon_skeleton`**（骨白 + 藍覆蓋） | 骷髏骨架族共用，色覆蓋即可 |
| `ice_wraith`（寒霜幽魂） | frost | elite | **新出** | 包無幽魂類；需從零畫（最重） |
| `skeleton_warrior`（骷髅战士） | frost | normal | **`mon_skeleton`**（共用） | 同上 |
| `imp_hellfire`（炼狱小鬼） | volcanic | normal | **`mon_imp_volcanic`**（紅 + 火焰覆蓋） | 小鬼族共用 |
| `brute_butcher`（屠夫） | volcanic | elite | **新出** | 包無人類敵；最重 |
| `wraith_frost`（霜缚幽魂） | frost | elite | **新出**（或與 ice_wraith 共用基底） | 同 ice_wraith |
| `boss_bone_tyrant`（骨狱暴君） | frost | boss | **`mon_boss_demon_lord`**（骨骼色覆蓋） | BOSS 共用骨架 + 配色覆蓋 |
| `boss_ember_lord`（熔心之主） | volcanic | boss | **`mon_boss_demon_lord`**（紅色覆蓋） | 同上 |
| `spider_cave / bat_swarm / mushroom_spore / warg_dark / golem_ember / hound_ash / pyromancer_cultist` | 各自 | 各自 | **必須新出**（包內無對應形象） | 7 個怪需獨立畫 |

### 3.2 對齊建議（3 條路徑，由 team-lead 拍板）

1. **A · 共用骨架 + 配色覆蓋（推薦）**：史萊姆 / 骷髏 / 小鬼 / BOSS 用包內 4 形象，加 6 張色覆蓋版（凍藍 / 毒綠 / 火紅 / 骨白）= 共用出圖成本最低、視覺一致性最高。需在 `data/monsters.json::sprite_path` 加 `_palette_override` 字段。
2. **B · 獨立出圖（最重）**：11 隻怪全獨立出圖，視覺差異最大、產量最大、不依賴色覆蓋。
3. **C · 混合**：slime/skel/imp/boss 走 A，其餘 11 隻走 B。產量中等。

---

## 四、可複用出圖管線（§五決策後批量執行）

| 缺口類別 | 主腳本 | 輔助腳本 | 思路 |
|---|---|---|---|
| 怪物單張（§2.1） | `pixel_pipeline.py` | — | 綠幕摳底 → 主色降採 → 192/256 固定畫布 → 腳底居中 → 48 色量化 → alpha 二值 |
| 怪物史萊姆彈跳（§2.2） | `slime_squash.py` | `pixel_pipeline.py` | 先 pipeline 出基準幀 → squash 程序化擠壓 4 幀 |
| 怪物 skel/imp walk | `sprite_sheet_cut.py` | `pixel_pipeline.py` | 多幀表切割 → 列投影找中心 → 統一縮放 → 腳底對齊 → 48 色量化 |
| 受擊 / 死亡補方向（§2.10） | `sprite_sheet_cut.py` | — | 同上 |
| 套裝徽記（§2.3） | `ui_pixel_gen.py`（補 3 函數） | `verify_pack.py` | 直接生成 16×16 + 6 色漸變描邊 |
| 稀有度框 3 枚（§2.4） | `ui_pixel_gen.py`（補 3 函數） | — | 同 §2.3 思路；分別實作 `FrameStyle.SOLID_GOLD_DOUBLE/SOLID_DIAMOND/GRADIENT_FLOW` |
| 技能圖標 2 枚（§2.5） | `ui_pixel_gen.py`（補 2 函數） | — | 48×48 居中 + 元素配色 + 1px 深描邊 |
| 裝備圖標（§2.6） | `ui_pixel_gen.py`（補 4 函數） | — | 48×48 居中 + 金屬 / 寶石 / 皮件配色 |
| FX 關鍵幀 | `verify_pack.py` | — | **已是出圖後驗收階段**，複用包內檔即可 |
| FX 序列幀 | `fx_anim_gen.py` | `verify_pack.py` | 已生成；**複用包內 38 張** |
| 玩家三職業 | **直接複用** | `verify_pack.py` | 包內 213 檔已就位；命名已對齊契約；只需工程接線 |

---

## 五、決策點（需 team-lead 拍板，影響後續全部出圖）

| # | 決策 | 兩個選項 | 我的建議 |
|---|---|---|---|
| **A** | 怪物包內 `mon_*` → 引擎契約 `char_*` | A1. **出圖時直接用 `char_*` 名**（一次到位）<br>A2. 出圖後**批量重命名 + 改 `dnf_parse_names` 兼容 `mon_*`** | **A1**（重命名成本 0；改 parser 風險大且破壞既有 `char_*` 契約） |
| **B** | 怪物方向：4 向 vs 8 向 | B1. **只做 n/e/s/w 4 向**（玩家 4 向就夠，��視 ARPG 對角不顯著）<br>B2. 做 8 向 + 擴展 `dir_from_vector` 支援 `ne/nw/sw/se` | **B1**（俯視 ARPG 視角下對角幀辨識度低；省 4×幀成本；玩家另議，見 D） |
| **C** | 武器命名：`weapon_*` vs `equip_*` | C1. **統一 `equip_*`**（與既有 `icons/equipment/equip_*.png` 一致，影響 `weapons.json` 字段重寫）<br>C2. 統一 `weapon_*`（與包內一致，影響既有 12 個 `equip_*.png` 重命名 + 數據） | **C1**（既有 convention 12 條，重寫 4 條數據比改 12 個檔名便宜） |
| **D** | 玩家三職業 8 向 vs 4 向 | D1. **玩家保留 8 向**（主戰旋轉必備）<br>D2. 玩家改 4 向與怪物對齊 | **D1**（玩家是動畫主角，8 向可讀性高；怪物純功能性，可降） |
| **E** | 怪物形象共用 vs 獨立（§3.2） | A 共用骨架 + 配色覆蓋 / B 獨立 / C 混合 | **C**（slime/skel/imp/boss 共用 + 7 隻新出） |
| **F** | UI 套件走向 | F1. **沿用 `ui/quest/`**（現狀，已 import 27 張）<br>F2. 切到 `ui/pixel/`（包內新） | **F1**（動 `ui_skin.gd` 路徑是破壞性變更；包內當備份即可） |

---

## 六、不建議出的圖（看似缺但不需要）

| # | 名義缺口 | 為何不建議出 |
|---|---|---|
| 1 | `ch1_l01..ch1_l06.tscn` 6 條關卡場景（brief§A.3） | `resources/level_data.gd:105` 的 `scene_path` **從未被讀取**；全部載入共用 `res://scenes/levels/level.tscn`。`LevelGenerator` 動態擺怪、動態擺牆，場景本身只是空容器 |
| 2 | 包內 `assets/backgrounds/` 與 `ui/quest/backdrops/` 同名重複 | ui/quest 已 import + 內容合規；包內當備份 |
| 3 | 包內 `assets/ui/pixel/btn_*_96x24.png` 與 `ui/quest/btn_*_128x24.png` | ui/quest 是規範 C6 拍板的 128×24；包內 96×24 為內容輕微版，**不要動 ui_skin.gd 切到 96** |
| 4 | 包內 `assets/ui/pixel/rarity_myth_48.png` 等 5 檔 | `ui_skin.gd` 沒在讀 `ui/pixel/rarity_*`；**讀的是 `ui/quest/slot_*`**（命名空間不同）。包內 5 檔**根本不被消費**——除非決策 F2 才有意義 |
| 5 | 怪物 die 動畫 | 死亡用現成 `death_puff.png`（fx.json 已就位 line 65）+ `_spawn_death_anim` ghost 機制（`enemy_base.gd::line 395-422`）；包的 `_death_s/` 是可選品 |
| 6 | 玩家 restart 8 向 walk（包已齊） | 包內已齊 8 向 walk/attack + hurt/death 南；無需補圖 |
| 7 | 武器 4 方向 × 8 幀（`GameConstants.WEAPON_ANIM_FRAMES=8` × 4 = 32 幀/原型 × 10 = 320 幀） | 武器**不是背包 icon 級**，而是**裝備到角色身上的即時 sprite**（line 300-301）；**裝備穿戴模組尚未實作**——整套武器 sprite 是階段 6+ 才需要的產物，現階段不建議出 |
| 8 | `set_emblem_*` 3 枚（brief§A.2） | **全項目無 UI 消費**——`ConfigLoader.get_set().emblem_path` 字段有但沒人讀。出圖純粹備庫，**優先級 P2** |
| 9 | FX 序列幀 38 張 | 同上：**無 `BattleVFX` 模組接線**，先出圖後接線是雙重浪費。**優先級 P2** |

---

## 七、與工程側可能有分歧的點（預先標記）

1. **怪物 `mon_*` vs `char_*`**（決策 A）：工程側可能希望「改 parser 兼容 `mon_*`」（減少一次性重命名工作量）。我建議反之：包只 19 檔，重命名 19 個檔案 < 改 parser 風險。
2. **方向 4 vs 8 向**（決策 B/D）：玩家 8 向已就位且是玩家專屬動作感核心，怪物降 4 向省產能。工程側若堅持一致 8 向，**怪物工作量 ×2**（加 ne/nw/se/sw）。
3. **武器 `equip_*` vs `weapon_*` 統一**（決策 C）：工程側 `data/equipment/weapons.json` 全走 `icons/equipment/equip_*`，**統一 `equip_*` 對工程最友善**（只改 4 條 `icon_path` 而非 12 條）。
4. **FX 序列幀接線優先級**（§1 第 10 條）：我列 P2，但工程若把它當新模組要做，**先確認是否有 `SkillFX` / `BattleVFX` 的時間盒**再出圖。
5. **UI 套件走向**（決策 F）：**強烈建議 F1��沿用 ui/quest）**，切到 ui/pixel 是破壞性變更且收益不明。
6. **怪物形象共用 vs 獨立**（決策 E）：共用骨架方案需要 `data/monsters.json::sprite_path` 加 `_palette_override` 字段（**工程側要配合新增字段**）。

---

## 八、產能估算（出圖側）

> 假設走 §五 全部「我的建議」：A1 + B1 + C1 + D1 + E（混合）+ F1

| 類別 | 件數 | 備註 |
|---|---:|---|
| 怪物單張（§2.1，16 隻各 1 張） | 16 | 純單張，1 天 |
| 怪物共用骨架（§3.2 C 方案：覆蓋色版） | 6 | 半天 |
| 怪物獨立新增（§3.2：spider / bat / mushroom / warg / golem / hound / pyromancer / ice_wraith / wraith_frost / brute_butcher） | 10 隻怪 × idle 1 幀 = 10 | 5 天 |
| 怪物 walk 補完（§2.11） | 16 × 4 方向 × 3 幀 = 192 | 程序化 + 切割，3 天 |
| 怪物 hurt（§2.11，通用） | 16 × 1 方向 × 2 幀 = 32 | 1 天（共用基底） |
| 套裝徽記（§2.3） | 3 | 半天 |
| 稀有度框（§2.4） | 3 | 半天 |
| 技能圖標（§2.5） | 2 | 1 小時 |
| 裝備圖標（§2.6，腿甲 + 副手 3 + 錘） | 4（錘可重命名） | 1 天 |
| 受擊 / 死亡補方向（§2.10） | 3 職業 × 4 動作 × 1 方向 = 12 張 | 半天 |
| **合計** | ~282 張 + 工程接線 ~3 天 | **總計 ~12 天**（1 人） |

> P0/P1 子集（不含怪物獨立新增 + walk 補完）≈ **6 天**

---

**檔案結尾**  
Author：art-director 林繪澄  
Output：`D:\七傳說\deliverables\asset-gap-audit-art-2026-09-21.md`  
Handoff：team-lead via SendMessage（≤40 行摘要）