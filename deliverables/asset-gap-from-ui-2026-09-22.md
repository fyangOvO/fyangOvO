# 七傳說 · 素材缺口清單（以 `D:\七傳說\ui\` 為唯一素材來源）

**日期**：2026-09-22　**負責**：林繪澄（美術總監）　**Task**：TASK-GAP-FROM-UI　**對象**：柳絮（用戶）

## 0. 前提交代（本清單的判定口徑）

- **唯一素材來源**＝`D:\七傳說\ui\`（＝`七傳說_像素素材包_2026-09-21.zip` 本體，330 張，我逐項比對過）。
- **可用性判定**：只有包裡**原樣存在**的檔可用；我自行生成／換色／新畫的一律不算（先前的換色怪、程序化地磚**已作廢，不在本清單**）。
- 本輪**不產任何新圖**。本清單就是「**缺什麼 → 請你去找**」的採購單。
- 比對依據（我逐檔只讀核對）：`game/data/monsters/monsters.json`(16 怪)、`game/data/skills/skills.json`(8 技能)、`game/data/equipment/*.json`(62 件)、`game/data/levels/chapter*.json`(20 關)、`game/data/fx.json`、`game/scripts/ui/ui_skin.gd`、`game/scripts/run/level_scene.gd`、`game/scripts/run/tile_atlas.gd`、`game/scripts/enemies/enemy_base.gd`。
- **引擎只消費 `n/e/s/w` 四方向**（`dir_from_vector()`），包內的 `ne/nw/se/sw` 對角向**不進遊戲**。
- **檔名契約（硬）**：角色與怪物都必須 `char_<who>_<action>_<dir>_<NN>.png`（引擎 `dnf_parse_names()` 只認 `char_` 開頭）；action ∈ `idle/walk/attack/hurt/die`；dir ∈ `n/e/s/w`；NN 兩位數。**包內怪物用 `mon_` 前綴，引擎不吃 → 必須改成 `char_` 前綴**（見 §3）。

---

## 1. 缺口總表

> 「包內是否有」＝ `ui/` 目錄裡是否有**可用（內容+命名皆對得上契約）**的檔。
> 「影響」＝ 阻塞（沒它就缺畫面/缺內容）／降級（有代碼兜底，只是變醜）／可忽略。

| 類別 | 遊戲需要的具體項 | 包內是否有 | 缺什麼（數量/方向/動作/尺寸/命名） | 影響 | 優先 |
|---|---|---|---|---|---|
| **場景** | 3 套地磚圖集 `tilesets/{forest,frost,volcanic}/atlas.png`＋`atlas.json` | **完全沒有** | 3 套 atlas 貼圖＋3 份 json；tile=32px；每套需 ground／wall／obstacle 三類 | **阻塞** | **P0** |
| **怪物** | 16 隻怪的多幀精靈（4 向 × 5 動作） | 僅 5 隻原型、且只 `_s` 向 | **12 隻完全缺**；4 隻僅部分（且缺 n/e/w、缺 walk/hurt/die） | **阻塞** | **P0** |
| **技能** | 8 技能 → 6 個圖標名 | 4 個（slash/fireburst/frostnova/shadowdash） | **缺 2**：`skill_icon_lightning_chain_48`、`skill_icon_poison_cloud_48` | 降級 | P1 |
| **任務／UI** | UI 皮膚 26 個邏輯名（`UISkin.TEX`） | 內容多數有、命名/尺寸多不對 | 缺 8 檔（banner/divider/marker/star_lit/star_dim/slot_orange/slot_set/slot_hidden）＋按鈕 6 檔尺寸不符（96→128） | 降級 | P1 |
| **裝備** | 15 個圖標名（`icon_path`） | 包 10 武器＋6 護甲，**命名用 `weapon_*`** | **缺 2**：`equip_legs_48`(腿甲)、`equip_ring_b_48`(戒指B)；武器需 `weapon_*→equip_*` 改名 | 降級 | P1 |
| **特效** | 元素施法特效 6 系 | slash/fire/frost/thunder 4 系 | **缺 2 系**：poison、shadow | 降級 | P1 |
| **特效** | `data/fx.json` 邏輯特效 7 個 id | **完全沒有** | 7 個 id 的序列圖（hit_spark/slash_arc/level_up_burst/pickup_glow/death_puff/ember_lord_aura/pyromancer_cast） | 降級 | P2 |
| **裝備** | 3 套裝徽章 `sets.json`→`set_emblem_*` | 完全沒有 | 3 張 48×48 徽章 | 降級 | P2 |
| **角色** | 玩家 1 套（`player`）多向精靈 | 有 3 職業全套（warrior/mage/archer） | 缺 n/e/w 的 idle/hurt/die（每職業 21 張）；且目錄/前綴需 `player` 對齊 | 降級 | P2 |
| **背景** | `backdrop_{forest,frost,volcanic}_640x360`＋`main_menu_bg_640x360` | **齊全（4/4）** | 無 | — | — |

**缺口總數**：**P0 阻塞 2 類**（地磚 3 套、怪物 12 隻全缺）＋**P1 降級 4 類**（技能圖標 2、UI 8+6 檔、裝備圖標 2＋改名、元素特效 2）＋**P2 降級 3 類**（fx.json 7 個 id、套裝徽章 3、玩家補向 21×N）。**背景與主菜單背景 0 缺**。

---

## 2. 逐條規格（可直接照著找素材）

尺寸沿用包內原生；**alpha 一律二值（0/255），透明底，無半透明、無抗鋸齒**。

### P0-1　三套地磚圖集（場景）— **最缺、最影響觀感**
- **路徑/命名**：`atlas.png` ＋ `atlas.json`，**一生態一套**：`forest/`、`frost/`、`volcanic/`（章節 1/2/3 各對應一態）。
- **尺寸**：單格 **32×32**；建議整張 **8 欄 × 5 列 = 256×160**（沿用我已驗證可載入的版面），亦可自定，但 `atlas.json` 必須對得上。
- **每套至少要有**：`ground`（地面，建議 6 個變體避免「蓋章感」）、`wall`（牆）、`obstacle`（障礙）**三類都非空**（缺任何一類 → 引擎整體退回占位圖）。
- **附帶 `atlas.json`**：`{"tile_size":32,"tiles":{"ground":[[x,y],...],"wall":[...],"obstacle":[...]}}`，`[x,y]`＝**格座標**（非像素），可多變體。
- **找不到現成 atlas 也 OK**：只要給我「同風格的一組 32×32 地面/牆/障礙小圖」，我可幫排成 atlas。

### P0-2　16 隻怪物精靈（角色/怪物）— **戰鬥主體**
- **命名**：`char_<id>_<action>_<dir>_<NN>.png`（**注意：前綴是 `char_`，不是包裡的 `mon_`**）。`<id>` 用下表 id；放到 `assets/pack/creatures/<id>/`。
- **尺寸**：小怪/普通/精英 **192×192**；BOSS **256×256**；腳底對齊畫布底部。
- **動作集合**：`idle`(1–4 幀)、`walk`(4 幀)、`attack`(4 幀)、`hurt`(2 幀)、`die`(4 幀)。
- **方向集合**：**n / e / s / w**（引擎只用這 4 向；對角向不要）。**最低可跑**＝每隻至少 1 向 `idle`。

| id | 名稱 | tier | 元素 | 飛行 | 需向數 | 包內現況 |
|---|---|---|---|---|---|---|
| spider_cave | 洞穴蛛 | normal | physical | 否 | 2 | **全缺** |
| bat_swarm | 血蝠 | normal | physical | **是** | 2 | **全缺**（需飛行姿態） |
| skeleton_warrior | 骷髏戰士 | normal | physical | 否 | 4 | 部分（`skeleton/` 僅 s 向 idle+attack） |
| slime_acid | 酸液史萊姆 | normal | **poison** | 否 | 2 | 部分（`slime_forest/slime_frost` 是森林/冰霜色，非毒） |
| mushroom_spore | 孢蘑菇 | normal | poison | 否 | 2 | **全缺** |
| warg_dark | 暗影獵犬 | normal | physical | 否 | 2 | **全缺** |
| golem_ember | 燼石魔像 | normal | fire | 否 | 2 | **全缺** |
| imp_hellfire | 煉獄小鬼 | normal | fire | 否 | 2 | 部分（`imp_volcanic/` 僅 s 向 idle+attack） |
| hound_ash | 灰燼獵犬 | normal | fire | 否 | 2 | **全缺** |
| frozen_husk | 冰封屍骸 | normal | cold | 否 | 4 | **全缺** |
| brute_butcher | 屠夫 | **elite** | physical | 否 | 4 | **全缺**（精英，體型大） |
| wraith_frost | 霜縛幽魂 | **elite** | cold | **是** | 4 | **全缺**（飛行） |
| pyromancer_cultist | 焰術信徒 | **elite** | fire | 否 | 4 | **全缺**（施法者） |
| ice_wraith | 寒霜幽魂 | **elite** | cold | 否 | 4 | **全缺** |
| boss_bone_tyrant | 骨獄暴君 | **boss** | physical | 否 | 4 | **全缺**（骨架系 BOSS） |
| boss_ember_lord | 熔心之主 | **boss** | fire | 否 | 4 | 部分（`mon_boss_demon_lord` 僅 s 向 idle 1 幀） |

→ **全缺 12 隻**（spider_cave, bat_swarm, mushroom_spore, warg_dark, golem_ember, hound_ash, frozen_husk, brute_butcher, wraith_frost, pyromancer_cultist, ice_wraith, boss_bone_tyrant）；
→ **部分 4 隻**（skeleton_warrior, slime_acid, imp_hellfire, boss_ember_lord）。
> 找不到 16 種也沒關係：**每一隻都要能被玩家一眼分辨**（元素色/輪廓），這比湊齊動作幀重要。

### P1-1　技能圖標（技能）— 缺 2
- **命名**：`skill_icon_<name>_48.png`（**包裡叫 `skill_<name>_48.png`，需補上 `_icon`**）。**48×48**，內容約 40px 居中。
- **缺**：`skill_icon_lightning_chain_48.png`（閃電鏈）、`skill_icon_poison_cloud_48.png`（毒雲）。
- 已有：slash(裂斬/旋刃)、fireburst(火球術)、frostnova(冰霜新星)、shadowdash(突進/暗影步)。

### P1-2　任務／UI 皮膚（任務、UI）— 缺 8 檔＋按鈕尺寸
- 契約名（放到 `assets/ui/quest/`，**命名以遊戲為準**）：

| 邏輯名 | 契約檔名 | 尺寸 | 包內現況 |
|---|---|---|---|
| banner | `quest_banner_256x48.png` | 256×48 | **缺** |
| divider | `divider_160x8.png` | 160×8 | **缺** |
| marker | `quest_marker_24.png` | 24×24 | **缺** |
| star_lit | `star_lit_16.png` | 16×16 | **缺**（點亮星） |
| star_dim | `star_dim_16.png` | 16×16 | **缺**（暗星） |
| slot_orange | `slot_orange_48.png` | 48×48 | **缺**（LEGENDARY 橙框） |
| slot_set | `slot_set_48.png` | 48×48 | **缺**（套裝綠框） |
| slot_hidden | `slot_hidden_48.png` | 48×48 | **缺**（隱藏彩虹框） |
| btn_gold/dark ×3 態 | `btn_{gold,dark}_{normal,hover,pressed}_128x24.png` | **128×24** | **尺寸不符**（包是 96×24，底部左右各空 52px） |

- **命名需對齊（內容包內有，改名即可）**：`rarity_*_48.png` → `slot_*_48.png`；`panel_9slice_120.png` → `quest_panel_9slice.png`；`skill_*_48.png` → `skill_icon_*_48.png`。
- 稀有度共 8 階（白/藍/黃/紫/橙/紅/綠/彩），包給 5 階 → 缺橙/綠/彩三階（上表）。

### P1-3　裝備圖標（裝備）— 缺 2＋改名
- **契約命名**：`equip_<slot>_48.png`（**包內武器叫 `weapon_<type>_48.png`，需改 `equip_*`**）。**48×48**，內容約 40px 居中。
- **缺**：`equip_legs_48.png`（腿甲，5 件裝備用）、`equip_ring_b_48.png`（戒指 B，3 件裝備用）。
- **改名對齊（內容包內有）**：`weapon_sword/axe/hammer/dagger/staff/bow/shield_48` → `equip_sword/axe/hammer/dagger/staff/bow/shield_48`。包內 `weapon_orb/quiver/offblade` 遊戲未用（可忽略）。

### P1-4　元素施法特效（特效）— 缺 2 系
- **命名**：`fx_<element>_px96.png`，**96×96**，二值 alpha（包內 4 張已符合）。
- 已有：`fx_slash_px96`（物理）、`fx_fire_px96`、`fx_frost_px96`、`fx_thunder_px96`（＝閃電）。
- **缺**：`fx_poison_px96.png`（毒）、`fx_shadow_px96.png`（暗影）。
- 另有 4 組序列動畫 `anim/{slash,fireburst,frostnova,thunder}/`（96×96，二值 alpha）可用，遊戲**未接**；若要動態施法特效可直接沿用包內這 4 組。

### P2-1　`fx.json` 邏輯特效（特效）— 全缺（有代碼兜底）
- 遊戲 `data/fx.json` 定義 7 個 id，缺對應序列圖（找不到不影響運行，只是代碼畫色塊）。**序列圖橫向排列、尺寸＝frame_w×frames**：

| id | 用途 | 單幀 | 幀數 | 整圖尺寸 |
|---|---|---|---|---|
| hit_spark | 命中火花 | 32×32 | 6 | 192×32 |
| slash_arc | 斬擊弧光 | 48×48 | 6 | 288×48 |
| level_up_burst | 升級爆閃 | 48×48 | 8 | 384×48 |
| pickup_glow | 拾取光暈 | 24×24 | 6 | 144×24 |
| death_puff | 死亡煙霧 | 32×32 | 6 | 192×32 |
| ember_lord_aura | BOSS 熔心光環 | 236×212 | 7 | 1652×212 |
| pyromancer_cast | 焰術信徒施法 | 85×56 | 2 | 170×56 |

### P2-2　套裝徽章（裝備/UI）— 缺 3
- **命名**：`set_emblem_<set>_48.png`，**48×48**，放 `assets/sprites/items/`。
- 缺：`set_emblem_emberpath`、`set_emblem_frostbite`、`set_emblem_oathkeeper`（3 套裝各 1）。

### P2-3　玩家精靈補向（角色）— 降級
- 包內 3 職業（warrior/mage/archer）**齊全但只補了 s 向**的 idle(1)/hurt(2)/die(4)。遊戲只需 1 套 `player`。
- **缺（若要求全向）**：每職業 `idle_n/e/w`＋`hurt_n/e/w`＋`die_n/e/w`＝**21 張**。
- **命名/目錄對齊**：包是 `characters/<class>/char_warrior_*`；引擎要 `assets/pack/creatures/player/char_player_<action>_<dir>_<NN>.png` → **目錄名與 `who` 需改成 `player`**（改名即可，不算新素材）。
- walk/attack 的 n/e/s/w（4 幀）**已齊**，可不動。

---

## 3. 可降級項（**不給也能跑，只是變醜**——可以慢慢找）

| 項 | 沒素材時的行為 | 嚴重度 |
|---|---|---|
| 技能圖標 lightning_chain/poison_cloud | 該技能槽空（顯示 `skill_slot` 空槽貼圖） | 低 |
| UI banner/divider/marker/star_* | 對應元件**隱藏**（不留空框） | 低 |
| UI slot_orange/set/hidden | 該稀有度框退回程序化 StyleBox | 低 |
| UI 按鈕 96×24（非 128） | 按鈕偏窄，仍可點 | 低 |
| 裝備 equip_legs/ring_b  | 該槽道具**無圖標**（空格框） | 中 |
| 元素特效 poison/shadow | 施法**無特效**（或代碼色塊） | 低 |
| fx.json 7 個 id | **全部退回代碼繪製**（色塊/粒子） | 低 |
| 套裝徽章 3 張 | 套裝面板無徽章 | 低 |
| 玩家缺 n/e/w idle·hurt·die | 這些方向**沿用 s 向**（角色不轉向） | 低 |

**不可降級（阻塞）**：只有兩類——**地磚圖集**（沒有＝地圖是純色矩形）與**怪物的整體形象**（沒有＝敵人全是 32×32 色塊）。其餘都能安全降級。

---

## 4. 最關鍵的 5 條（若我只能拿 5 條去找柳絮）

1. **三套地磚圖集**（forest/frost/volcanic 的 `atlas.png`＋`atlas.json`，tile=32）——**全缺**，20 關場景 100% 靠它；這是「有沒有場景」的分界線。
2. **16 隻怪的形象**（至少 12 隻全缺那批，`char_<id>_*`，192×192／BOSS 256×256）——戰鬥主體；目前玩家打的多半是色塊。
3. **技能圖標閃電鏈＋毒雲**（`skill_icon_lightning_chain_48`、`skill_icon_poison_cloud_48`）——8 個技能裡唯一無圖的 2 個，**成本最低、回報最直接**。
4. **任務 UI 核心件**（`quest_banner_256x48`、`quest_marker_24`、`star_lit/star_dim_16`）——任務/關卡名/HUD/結算星星全靠它，缺則面板「撐不起來」。
5. **裝備圖標腿甲＋戒指B**（`equip_legs_48`、`equip_ring_b_48`）＋**武器 `weapon_*→equip_*` 改名對齊**——62 件裝備中有 8 件沒圖，且武器命名整批要對齊。

> 理由：1、2 是**阻塞級**（沒就沒場景/沒敵人）；3 是**最高性價比**；4、5 是**介面完整性**的最後缺口。

---

## 5. 明確排除（**不缺，不用找**）

- `previews/`（8 個 GIF/PNG）＝**展示用預覽**，非遊戲素材，**不缺**。
- 對角方向 `ne/nw/se/sw`（角色 walk/attack 對角組）＝引擎 `dir_from_vector()` **只產 n/e/s/w**，**不消費**，不用找。
- `.gif`（`anim/*.gif`）＝**不進遊戲**（遊戲只讀 `anim/<skill>/*.png` 序列），不用找。
- 包內 `weapon_orb/quiver/offblade`＝現有 62 件裝備**未引用**，可忽略。
- **背景／主菜單背景**：包內 4 張 640×360 齊全，**不缺**。
- 音效／BGM 屬音頻領域（阮和鳴），不在本清單。

---

*本清單僅供「照著找素材」用；除本文件外未改動 `game/` 任何檔、未產出任何圖片、未刪任何檔。*
