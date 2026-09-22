# 素材替換規格書 — 怪物映射換色 + 三套地磚
**Task：TASK-SWAP-ART ｜ 版本：2026-09-22 ｜ 作者：林繪澄（art-director）｜ 語言：繁體中文**

> 本輪把渲染切到**素材包**（`game/assets/monsters|characters|tilesets`）＋補包內沒有的地磚。
> 所有產物落 **staging**，由工程主管搬運接線；**未改 `game/` 任何檔**。

---

## 0. 一頁摘要（交付清單）

| 交付 | 路徑 | 內容 |
|---|---|---|
| 怪物資產集 | `deliverables/asset-swap-2026-09-22/creatures/<id>/` | 16 id ×（idle + walk〔+ attack〕），**共 131 PNG** |
| 地磚三套 | `deliverables/asset-swap-2026-09-22/tilesets/<biome>/` | `atlas.png` + `atlas.json` ×3（forest/frost/volcanic） |
| 本規格書 | `deliverables/asset-swap-spec-2026-09-22.md` | — |
| 生成腳本（可重跑） | `.../asset-swap-2026-09-22/_work/{creature_gen,tileset_gen,preview_maps}.py` | 確定性、無隨機副作用 |

**關鍵視覺決策**
1. **16 id 共用 5 個包內原型骨架**（換色不改輪廓）—— 4 小怪 + 1 BOSS。
2. **地磚森林地面均色由舊 `(22,29,27)` 抬到 `(75,91,56)`**（亮度 0.11→0.36），讓亮色小怪可辨識（本輪核心 KPI，已真合成驗證）。
3. **三 biome 色調一眼可辨**：森林苔綠 / 霜淵冰藍 / 火山暖灰。
4. **只做 `_s`（南）單一方向**：包內怪物素材僅 `_s`；引擎 `resolve_clip` 對缺方向會回退取第一個可用方向，故可用。對角（ne/nw/sw/se）**不做**（見 §6）。

---

## 1. 引擎解析契約（產物必須逐條符合，已全量驗過）

來源（只讀）：`scripts/enemies/enemy_base.gd`

| 契約 | 要求 | 本輪狀態 |
|---|---|---|
| 命名 | `char_<id>_<action>_<dir>_<NN>.png`；解析取**末三段**（動作/方向/幀號），其餘=id | ✅ 131/131 通過（id 含底線正確還原） |
| 前綴 | **必須** `char_`（`mon_` 前綴被 100% 忽略） | ✅ 全部 `char_` |
| action | `idle｜walk｜attack｜hurt｜die` | ✅ 只出 idle/walk/attack |
| dir | 僅消費 `n｜e｜s｜w`（`dir_from_vector()`） | ✅ 全部 `_s` |
| 幀號 | 2 位、由 `01` 起、連續 | ✅ `01..04` |
| alpha | 二值（0/255） | ✅ 全量驗過 |
| 畫布/基線 | 幀間畫布尺寸與**腳底 baseline** 一致 | ✅ 同 clip 共用單一 union-bbox 變換 |
| 畫布尺寸 | 小怪 **128×128**（顯示 32px）／BOSS **256×256**（顯示 64px）；`DNF_GAME_SCALE=0.25` | ✅ |

**落點（工程主管接線用）**：素材為**多動作多幀集** ⇒ 應落 **`res://assets/dnf/normalized/<id>/`**（四級鏈第 ③ 級）。
> ⚠️ **遮蔽風險（需工程處理）**：目前 16 id 在 `res://assets/sprites/enemies/<id>.png` 有**單幀 bundled 圖**（第 ② 級），
> 四級鏈「先命中先返回」⇒ 第②級會**遮蔽**本輪的多幀集。要讓本輪生效，須把那 16 張 bundled 單幀**移入**
> `deliverables/_quarantine_2026-09-22/`（禁刪，僅移）。否則怪物仍是靜態立繪。

---

## 2. 16 隻 id ↔ 原型映射表

映射依據：`data/monsters/monsters.json` 的 `tier / element / is_flying`（實際讀取）＋素材包 5 原型的主題親和。

| # | id | tier | element | 飛行 | 原型骨架 | 類型 | 動作覆蓋 | 備註 |
|---|---|---|---|---|---|---|---|---|
| 1 | `slime_acid` | normal | poison | — | `slime_forest` | 換色 | idle,walk | 酸液綠 |
| 2 | `mushroom_spore` | normal | poison | — | `slime_forest` | 換色 | idle,walk | 孢紫 |
| 3 | `frozen_husk` | normal | cold | — | `slime_frost` | 換色 | idle,walk | 蒼冰白 |
| 4 | `wraith_frost` | elite | cold | ✔ | `slime_frost` | 換色＋抬升 | idle,walk | 幽青·懸浮 +14px |
| 5 | `ice_wraith` | elite | cold | ✔ | `slime_frost` | 換色＋抬升 | idle,walk | 深冰藍·懸浮 +14px |
| 6 | `skeleton_warrior` | normal | physical | — | `skeleton` | 原樣 canon | idle,walk,attack | 骨白（基準） |
| 7 | `brute_butcher` | elite | physical | — | `skeleton` | 換色 | idle,walk,attack | 血鏽紅 |
| 8 | `spider_cave` | normal | physical | — | `skeleton` | 換色 | idle,walk,attack | 洞穴板岩灰 |
| 9 | `warg_dark` | normal | physical | — | `skeleton` | 換色 | idle,walk,attack | 暗影紫 |
| 10 | `hound_ash` | normal | fire | — | `skeleton` | 換色 | idle,walk,attack | 灰燼炭（與 #9 共骨架成對） |
| 11 | `imp_hellfire` | normal | fire | — | `imp_volcanic` | 原樣 canon | idle,walk,attack | 惡魔紅（基準） |
| 12 | `golem_ember` | normal | fire | — | `imp_volcanic` | 換色（雙色調） | idle,walk,attack | 炭岩＋余燼橙 |
| 13 | `pyromancer_cultist` | elite | fire | — | `imp_volcanic` | 換色 | idle,walk,attack | 焰橙 |
| 14 | `bat_swarm` | normal | physical | ✔ | `imp_volcanic` | 換色＋抬升 | idle,walk,attack | 暗灰紫·懸浮 +16px |
| 15 | `boss_ember_lord` | boss | fire | — | `boss` (demon_lord) | 原樣 canon | idle,walk | 熔心之主 |
| 16 | `boss_bone_tyrant` | boss | physical | — | `boss` (demon_lord) | 換色 | idle,walk | 骨金暴君 |

**全部 16 隻皆為「包內原型 × 換色/規整」，無全新繪製**（新出 = 0，換色 = 11，原樣 canon = 3，抬升 = 3）。

### 共用骨架（silhouette 不變，只換色相/飽和/明度）
- **`slime_forest`（2 隻）**：毒系 → `slime_acid` / `mushroom_spore`
- **`slime_frost`（3 隻）**：冰系 → `frozen_husk` / `wraith_frost` / `ice_wraith`
- **`skeleton`（5 隻）**：物理系 → `skeleton_warrior` / `brute_butcher` / `spider_cave` / `warg_dark` / `hound_ash`
- **`imp_volcanic`（4 隻）**：火系 → `imp_hellfire` / `golem_ember` / `pyromancer_cultist` / `bat_swarm`
- **`boss_demon_lord`（2 隻）**：BOSS → `boss_ember_lord` / `boss_bone_tyrant`

---

## 3. 換色對照表（原型 → id）

換色演算法（`creature_gen.py`）：HSV 空間 remap，`h' = 目標色相 + 最短弧差(h−原型色相)×0.25`（保留明暗色相變化、防 0/360 環繞跳色），
`s' = clamp(s×sm+sa)`，`v' = clamp(v×vm)`；近黑描邊與純白高光（眼）自然保留；輸出再 **自適應量化 ~48 色**（與包內角色一致，保留必需中間色）。
`canon` = 不做色相位移（原樣量化）。

| id | 原型 | 目標色相 | s×(+加) | v× | 產出主色（實測 hex） | 原型主色（對照） |
|---|---|---|---:|---:|---|---|
| slime_acid | slime_forest | 82° | ×1.15+0.02 | ×1.25 | `#DDFFA4 h82 s0.36 v1.00` | `#EDFFA1 h71 s0.37 v1.00` |
| mushroom_spore | slime_forest | 302° | ×0.85+0.02 | ×0.95 | `#F2A1EF h302 s0.33 v0.95` | 同上 |
| frozen_husk | slime_frost | 198° | ×0.55+0.02 | ×1.05 | `#7DD2FA h199 s0.50 v0.98` | `#1363D9 h215 s0.91 v0.85` |
| wraith_frost | slime_frost | 172° | ×0.62 | ×1.02 | `#70F3E5 h173 s0.54 v0.95` | 同上 |
| ice_wraith | slime_frost | 216° | ×1.05 | ×0.82 | `#1054C3 h217 s0.92 v0.76` | 同上 |
| skeleton_warrior | skeleton | — canon | — | — | `#FDF6D4 h49 s0.16 v0.99` | `#FDF6D4 h49 s0.16 v0.99` |
| brute_butcher | skeleton | 8° | ×2.20+0.25 | ×0.90 | `#E3624D h8 s0.66 v0.89` | `#FDF6D4 h49 s0.16 v0.99` |
| spider_cave | skeleton | 205° | ×0.45+0.02 | ×0.42 | `#60666A h203 s0.09 v0.42` | 同上 |
| warg_dark | skeleton | 272° | ×0.90+0.05 | ×0.52 | `#776983 h272 s0.20 v0.51` | 同上 |
| hound_ash | skeleton | 30° | ×0.60+0.05 | ×0.55 | `#8B8076 h28 s0.15 v0.55` | 同上 |
| imp_hellfire | imp_volcanic | — canon | — | — | `#FA382A h4 s0.83 v0.98` | `#FA382A h4 s0.83 v0.98` |
| golem_ember | imp_volcanic | 雙色調 | — | — | 亮豔部 `#FF7D0C h27 s0.95 v1.00`／暗部 `#302D2C v0.19` | `#5E2E2F h358 v0.37` |
| pyromancer_cultist | imp_volcanic | 24° | ×0.85 | ×0.95 | `#E38340 h24 s0.72 v0.89` | 同上 |
| bat_swarm | imp_volcanic | 250° | ×0.40 | ×0.42 | `#494365 h250 s0.34 v0.40` | 同上 |
| boss_ember_lord | boss | — canon | — | — | `#E85D1E h18 s0.87 v0.91`（焰） | `#E85D1E h18 …` |
| boss_bone_tyrant | boss | 48° | ×0.42+0.02 | ×1.18 | `#46453D h53 s0.13 v0.27`（骨甲） | `#241A1F h330 v0.14` |

> 可辨識性：同骨架各 id 色相至少拉開 60°（如 skeleton 群：紅8° / 灰205° / 紫272° / 炭30°）；
> 明度亦分層（冰系：蒼白 v1.0 / 幽青 v0.95 / 深藍 v0.76）。

### 動作覆蓋矩陣
| 骨架 | idle | walk | attack | 取得方式 |
|---|---|---|---|---|
| slime_forest / slime_frost | 4 幀（彈跳） | 4 幀（＝彈跳，史萊姆以彈跳前進） | — | 包內 idle 4 幀 |
| skeleton / imp_volcanic | 1 幀 | 4 幀（idle 輕微上下浮動合成） | 4 幀（揮擊） | 包內 idle1 + attack4 |
| boss | 1 幀 | 4 幀（合成浮動） | —（缺，回退 idle） | 包內 idle1 |

> `hurt` / `die` 素材包內無 ⇒ **不出**，由引擎 `ANIM_FALLBACK` 回退（不報錯、不白畫面）。
> BOSS `attack` 亦缺 ⇒ 出招時停在 idle（可接受；列為後續缺口）。

---

## 4. 地磚三套 — 規格

**schema（沿用既有鍵，未發明新鍵）**：`{"tile_size":32,"tiles":{"ground":[[x,y]…],"wall":[…] ,"obstacle":[…] }}`
（三鍵缺一即整張圖集被 `tile_atlas.gd::_try_load_real` **整張棄用** ⇒ 已確保三鍵皆非空）
**圖集佈局**：6 欄 × 3 列（192×96）。列 0 = ground 6 變體；列 1 = wall 3 變體；列 2 = obstacle 3 變體。
**tile 尺寸**：32px（＝`TILE_SIZE` / `TILE_PX`）。**變體數**：ground×6（抗「蓋章感」）、wall×3、obstacle×3。

| biome | 地面均色 | 地面基色 | 牆基色 | 障礙基色/強調 | 主題 |
|---|---|---|---|---|---|
| **forest** 幽林 | `(75,91,56)` | `#4A5A38` 苔綠 | `#2C3A24` 深綠 | `#787258` 石／`#6FB35C` 苔 | 苔蘚＋泥土棕 |
| **frost** 霜淵 | `(110,135,167)` | `#6C86A6` 冰藍 | `#4C6482` 深冰藍 | `#A2BCD6` 冰岩／`#6E9BE8` 霜 | 蒼藍＋雪白高光 |
| **volcanic** 火山 | `(81,70,64)` | `#504640` 暖灰 | `#2E2A28` 玄武岩 | `#6E4630` 熔岩岩／`#E8573F` 余燼 | 炭灰＋余燼橙 |

**語義（沿用既有三類，無新增）：**
- `ground` → **可走**（`LevelGenerator.TILE_GROUND`）
- `wall` → **阻擋**（`TILE_WALL`）；設計已配合引擎 2.5D：頂列=受光邊、底列=接縫、底 8px=側面暗面（引擎 `WALL_FACE_MODULATE 0.60`）
- `obstacle` → **阻擋**（`TILE_OBSTACLE`）；帶透明像素（引擎 `_draw_atlas` 會先墊地面再壓物件）
- 未新增「裝飾/危險格」鍵 —— 若需此語義，**屬引擎改動**，寫在此由 team-lead 裁定（見 §7）

**與怪物對比度（KPI 實測，真合成見附圖 `_work/tileset_map_preview.png`）：**
- 森林地面亮度 **0.11 → 0.36**（約 ×3.3）；亮色怪（骨白/酸綠）與暗描邊怪皆可辨識。
- 噪點幅度刻意壓小（±6/通道，斑點機率 <8%），避免與怪物剪影「搶像素」。
- 三 biome 地面亮度分層（森林 0.36 / 霜 0.53 / 火山 0.28），**互相一眼區分**。

---

## 5. 產出目視驗證（staging 內附）
- `_work/creature_preview.png`：16 id 依骨架分組對照。
- `_work/boss_preview.png`：2 BOSS。
- `_work/anim_strip.png`：idle/walk/attack 逐幀（驗 baseline 不抖）。
- `_work/tileset_map_preview.png`：三 biome 模擬地圖 + 怪物疊合（驗 KPI）。
- **對外展示用（已另存）**：`deliverables/gstack/asset-swap-tilesets-preview.png`（三 biome 合成）、
  `deliverables/gstack/asset-swap-creatures-preview.png`（16 id 換色合成）。

---

## 6. 對角方向（ne/nw/sw/se）處置
**本輪：不做對角。** 理由：
1. 包內**怪物**素材僅 `_s`；玩家 `characters/` 有 8 向，但本輪範圍是怪物映射 + 地磚。
2. 引擎 `dir_from_vector()` **只消費 n/e/s/w 四向**，對角是**死資源**（`resolve_clip` 永不查 ne/nw/sw/se）。
3. `resolve_clip` 對缺方向**回退取第一個可用方向** ⇒ 只給 `_s` 可用，不會白畫面。

**建議後續（另開工單，非本輪）**：若日後要 4 向怪物（走位更自然），用 `sprite_sheet_cut.py` 同流程補 `e/n`，再鏡像出 `w`；
對角仍不建議直接出圖（引擎不消費），除非先改 `dir_from_vector()` 支援 8 向（**屬引擎層改動**）。

---

## 7. 裁定結果（team-lead 2026-09-22 · 已收口）
1. **bundled 遮蔽 → 一併處理**：工程主管將 `assets/sprites/enemies/<16 id>.png`（含 `.import`）**移入**
   `deliverables/_quarantine_2026-09-22/bundled_single_frame/`（禁刪），多幀集接到一個新的 committed 解析層、**優先於第③級 DNF**。
2. **映射 stretch → 接受**（取捨＝主題/元素可辨 > 形似）。**名字與形象最不符的三隻**（供日後評估「補繪新原型」工單）：
   - **<span style="color:#C42B2B">spider_cave</span>（洞穴蛛）** → 掛在 `skeleton` 人形骨架上：是「骷髏」不是「蜘蛛」。
   - **<span style="color:#C42B2B">mushroom_spore</span>（孢蘑菇）** → 掛在 `slime_forest` 軟泥骨架上：是「史萊姆團」不是「蘑菇」。
   - **<span style="color:#C42B2B">bat_swarm</span>（血蝠）** → 掛在 `imp_volcanic` 小鬼骨架上：無翼，是「惡魔」不是「蝙蝠」。
   - 次級（同屬妥協、但成對一致，優先度較低）：`warg_dark` / `hound_ash`（犬形 → 人形骨架）。
3. **`obstacle` 裝飾/可破壞語義 → 不加**：保持 `ground/wall/obstacle` 三鍵，避免引擎契約漂移。
   **後續可選**：若日後需「裝飾/危險/可破壞」格，建議以 `LevelGenerator` 新增 kind 常數 ＋ 圖集新增對應鍵的方式**另立工單**（屬引擎改動）。
4. **BOSS `attack` 缺幀 → 接受**（出招停 idle，靠 `ANIM_FALLBACK`），**列入 backlog**，不合成攻擊幀。
5. **地磚 tile 尺寸 → 維持 32px**（改尺寸須動 `TILE_SIZE`，本輪不開口子）。

---

## 8. 本輪明確未做 / 待辦
- ❌ 未改 `game/` 任何代碼或數據（只讀）。❌ 未刪任何檔（舊素材如需淘汰，僅**移入 quarantine** 並回報清單）。
- ❌ 未出 `hurt`/`die`/對角方向（包內無源；見 §3、§6）。
- ❌ 未建 `.tres` / `AnimatedSprite2D` 掛載、未改 `monsters.json` 的 `sprite_path`（屬接線，交工程主管）。
- ⏳ 待 team-lead 裁定 §7 後，必要時補第二輪（新繪原型 / 補 attack 幀 / 8 向）。
