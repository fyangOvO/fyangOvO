# 七傳說 · 素材缺口審計總表（主理人彙編）

> **主理人**：游承峰（game-development-studio team-lead）
> **彙編日**：2026-09-21
> **成員交付**：
> - `asset-gap-audit-art-2026-09-21.md`（TASK-ASSET-GAP-ART · art-director 林繪澄）
> - `asset-gap-audit-eng-2026-09-21.md`（TASK-ASSET-GAP-ENG · engineering-lead 程基岩）
> **前置**：`game/assets/PACK_OVERVIEW.md`（素材包歸位索引）

---

## 〇、一句話結論

**表面 25 條缺口，真正需要「新畫」的只有 9 張圖；其餘全是「改名 / 搬位置 / 接線」。**

而且四級解析鏈裡有一個**反直覺陷阱**：往 `assets/sprites/enemies/<id>.png` 補單張 idle 圖，**會把現在有動畫的怪物變成靜止一張**——這條被兩位成員都判成「補上就好」，實測是**降級**。詳 §三。

---

## 一、事實勘誤（三方交叉核對結果）

| # | 誰說錯 | 原述 | 實測正確版 | 出處 |
|---|---|---|---|---|
| 1 | **主理人**（我） | `scene_path` 是死字段、從未被讀取 | **有被讀取**。`scene_manager.gd:120-133` 先試 `level.scene_path`，`ResourceLoader.exists` 失敗才回退 `level.tscn`，並 `print` 一行訊息。我先前 `grep` 被 `head_limit:30` 截斷而誤判 | `scene_manager.gd:112-140` |
| 2 | **主理人**（我） | 16 隻怪 `assets/sprites/enemies/<id>.png` 是「缺檔」 | **是設計上的「使用者單檔覆蓋槽位」**，不是必填。空著 = 正常運作（走 ③ DNF normalized） | `enemy_base.gd:436-454` |
| 3 | **art-director** | `scene_path` 從未被讀取（§六 #1） | 同勘誤 1。**但結論仍成立**：不需要出圖；差別在於它是「日誌噪音 + 可清理的冗餘欄位」，不是「死字段」 | 同上 |
| 4 | **engineering-lead** | 補 ② 單張「只會新增一條 fallback 命中，不改當前行為」 | **不對，這是降級**。`resolve_character_set()` 的 ② 若命中就 `return single_frame_set(...)`（`enemy_base.gd:544-554`），**永遠不會走到 ③**；回傳的 clips 只有 `{idle:{s:[tex]}}` ⇒ **怪物從「有 walk 動畫」變成「靜止一張」** | `enemy_base.gd:436-454` + `:544-554` |

---

## 二、主理人裁定（6 條決策點，逐條定案）

| # | 決策 | 裁定 | 理由 |
|---|---|---|---|
| **F** | UI 套件走向 | **F1 · 沿用 `assets/ui/quest/`** | 已 import、已按規範 C6 拍板 128×24、`verify_ui_assets.gd::EXPECT_TEX` 把它綁死。切到 `ui/pixel/`（96×24）是破壞性變更且收益不明 |
| **C** | 武器圖標命名 | **C1 · 統一 `equip_*`** | `verify_ui_assets.gd:154` 硬斷言 `icon_path` 必須以 `res://assets/icons/equipment/` 開頭。改 4 條 JSON 遠便宜於改 12 個檔名 + 改斷言 |
| **A** | 怪物前綴 `mon_*` | **A1 · 改名對齊 `char_*`**，反對改 parser | 改 `dnf_parse_names` 會動到玩家 + 全部 DNF 素材共用的既有契約（`verify_anim` 也盯它）；19 檔改名成本≈0。**補充**：我獨立驗證 `enemy_base.gd:593` 的 `if not base.begins_with("char_")` ⇒ 包內怪物**目前 0% 命中**，不改名等於完全不會生效 |
| **B** | 怪物方向 4 / 8 向 | **B1 · 只做 4 向** | `dir_from_vector()`（`:578`）永遠只回 n/e/s/w，對角幀是死資源。**補充**：包內已存在的對角幀**不要刪**，留著作 8 向的未來素材，只是不再投產能 |
| **D** | 玩家方向 | **D1 · 素材保留 8 向**，但**接線先按 4 向** | `player_controller.gd::facing_to_dir_letter()` 同樣只回 4 向。真要吃 8 向需**改代碼**（`dir_from_vector` + `facing_to_dir_letter` 同步擴），屬獨立工單，不是素材問題 |
| **E** | 怪物形象共用 / 獨立 | **E-混合**，但**分兩步**：先「併入既有 id」（零新畫），後「7 隻獨立新畫」（延後） | 見 §四——DNF 集已提供 walk，包提供 idle/attack，**兩者可互補而非替換** |

---

## 三、⚠️ 關鍵陷阱：`assets/sprites/enemies/<id>.png` **不要填**

`resolve_character_set()` 的四級優先鏈是「**先命中先返回**」：

```
① user://content/characters/<id>/     ← 命中就 return
② res://assets/sprites/enemies/<id>.png  ← 命中就 return（單張！）
③ res://assets/dnf/normalized/<id>/   ← 目前全體怪物實際來源
④ 程序化占位色塊
```

② 的回傳是 `single_frame_set()`：`clips = {idle: {s: [那一張]}}`、只有 1 幀。

⇒ **一旦往 ② 放單張 idle PNG，怪物立刻喪失全部動畫**（含現有的 walk 四向）。
⇒ art 文檔 §2.1「第一步只滿足 `data.sprite_path` 不 404」與 eng 文檔「只新增一條 fallback」**都低估了這條**。

**正解**：怪物素材要走 **③ 的目錄形式**（`assets/dnf/normalized/<id>/`），與 DNF 集**合併同目錄**，讓解析器把兩批檔案合成同一份 clips。② 保持空著。

---

## 四、最有價值的一項發現：DNF 集與包素材是**互補**關係

實測 `assets/dnf/normalized/` 每隻怪的動作覆蓋：

| 怪物 | DNF 現有動作 | 包能補的動作 | 合併後 |
|---|---|---|---|
| slime_acid / skeleton_warrior / imp_hellfire | **walk** 四向 | **idle**（+ skeleton/imp 的 **attack**） | idle + walk + attack |
| bat_swarm / spider_cave / mushroom_spore / warg_dark / golem_ember / hound_ash / frozen_husk / ice_wraith / wraith_frost | **walk** 四向 | 包內無對應形象 | 維持現狀（idle 靠 `ANIM_FALLBACK` 退到 walk） |
| boss_bone_tyrant / boss_ember_lord | **idle** 四向 | 包的 `boss_demon_lord` 是**另一套形象** | 換 BOSS 形象＝視覺改版，非補洞 |
| brute_butcher | idle 四向 | 無 | 維持現狀 |
| pyromancer_cultist | idle + walk + **attack**（156 檔，最完整） | 無 | 維持現狀 |

⇒ **零新畫、零代碼**的第一步：把包的 slime/skeleton/imp 改名（`mon_*`→`char_*`）+ 併入 `slime_acid/`、`skeleton_warrior/`、`imp_hellfire/` 三個既有目錄 ⇒ 這 3 隻怪立刻從「只會走、idle 也是走」變成「有真正的 idle 與攻擊動作」。

---

## 五、缺口分級總表

### A. 真正需要「新畫」的圖（9 張）

| # | 檔案 | 尺寸 | 色板 | 消費點 | 優先 |
|---|---|---|---|---|---|
| 1 | `assets/ui/quest/slot_mythic_48.png` | 48×48 | 44 色 | `ui_skin.gd::RARITY_SLOT[5]`（現 clamp 到橙） | **P1** |
| 2 | `assets/ui/quest/slot_set_48.png` | 48×48 | 44 色 | `RARITY_SLOT[6]` | **P1** |
| 3 | `assets/ui/quest/slot_hidden_48.png` | 48×48 | 44 色 | `RARITY_SLOT[7]` | **P1** |
| 4 | `assets/ui/quest/skill_icon_thunder_48.png` | 48×48 | 44 色 | `SKILL_ICON["lightning_chain"]`（現無條目） | **P1** |
| 5 | `assets/ui/quest/skill_icon_poison_48.png` | 48×48 | 44 色 | `SKILL_ICON["poison_cloud"]` | **P1** |
| 6 | `assets/icons/equipment/equip_legs_48.png` | 48×48 | 44 色 | `legs` 槽（現借 `equip_chest`） | **P1** |
| 7-9 | `assets/sprites/items/set_emblem_{frostbite,emberpath,oathkeeper}.png` | 16×16 | 44 色 | `sets.json::emblem_path` → **目前無任何 UI 讀取** | **P2** |

> 命名以 `slot_*` 而非包內 `rarity_*`：`ui_skin.gd::TEX` 的既有命名空間是 `slot_*`，包內 `ui/pixel/rarity_*` 不被消費。

### B. 零新畫，只需改名 / 搬位置 / 補數據

| # | 動作 | 來源 | 落點 |
|---|---|---|---|
| 1 | 3 隻怪 idle/attack **併入** | `assets/monsters/{slime_forest,skeleton,imp_volcanic}/` | `assets/dnf/normalized/{slime_acid,skeleton_warrior,imp_hellfire}/`（`mon_*`→`char_*`；只取 n/e/s/w） |
| 2 | 玩家三職業接入 | `assets/characters/`（命名**已合契約**） | 新增 `assets/dnf/normalized/{warrior,mage,archer}/` + 工程側職業選擇 |
| 3 | 錘 / 法器 / 箭袋 / 副刃圖標 | `assets/weapons/weapon_{hammer,orb,quiver,offblade}_48.png` | `assets/icons/equipment/equip_{hammer,focus,quiver}_48.png`（offblade 可直接複用 `equip_dagger_48.png`）+ 補 `weapons.json` 條目 |
| 4 | 4 張元素關鍵幀入表 | `assets/fx/fx_{slash,fire,frost,thunder}_px96.png` | `data/fx.json` 追加 4 條（`frames:1`, `frame_w:96`） |

### C. 不是缺口（表面像缺，別浪費產能）

| # | 名義缺口 | 判定 |
|---|---|---|
| 1 | `ch1_l01..l06.tscn` ×6 | **不是素材缺口**。會被讀，但失敗即回退共通容器 + 一行 `print`。可清理（刪 6 個 `scene_path` 欄位）或補 6 個空場景，屬獨立小工單 |
| 2 | `assets/sprites/enemies/<id>.png` ×16 | **不要填**（§三 陷阱） |
| 3 | `assets/ui/pixel/` 17 張 + `assets/backgrounds/` 4 張 | 與 `assets/ui/quest/` 重複且現行斷言綁在 quest。**留著當備份，不接** |
| 4 | `assets/anim/` 38 張序列幀 | **無消費方**（`FxSprite` 只吃橫向長條，不吃逐幀 PNG）。先做接線（`sprite_sheet_cut.py` 拼長條 → 走既有鏈）再出圖，否則雙重浪費 |
| 5 | 武器「4 向 × 8 幀」穿戴 sprite（~320 幀） | 裝備穿戴模組未實作，屬階段 6+ |
| 6 | 怪物 `death` 動畫 | 已有 `death_puff` + ghost 機制兜底 |

---

## 六、回歸紅線（接線前必看）

| 驗證腳本 | 觸發條件 | 規避 |
|---|---|---|
| `verify_ui_assets.gd:154-168` | 改 `data/equipment/*.json` 的 `icon_path` 指向 `assets/weapons/` `assets/armor/` ⇒ **紅** | 一律搬進 `assets/icons/equipment/` 並沿用 `equip_*` 命名 |
| `verify_ui_assets.gd:29-52 EXPECT_TEX` | 動 `ui_skin.gd::TEX` 或 `BUILTIN_ROOT` | 只**新增**條目，不改既有；新增 3 檔稀有度框需同步補 3 行 |
| `verify_ui_assets.gd:122` | `RARITY_SLOT` 改映射後，被指名的檔必須存在 | 先出圖，再改映射 |
| `verify_monsters62.gd` | 動 `monsters.json` 的 16 隻數量 ⇒ **紅** | 只搬素材、不改 `monsters.json` 條目數 |
| `verify_fx.gd:24 REQUIRED_IDS` | 白名單 7 條，**新增 id 不會紅** | 注意 `frame_w × frames ≤ 貼圖寬` 硬約束 |
| `main_menu_panel.gd:30 BTN_SIZE` | 若把包內 96×24 按鈕納入 `EXPECT_TEX` ⇒ 連帶紅 | 整個 `assets/ui/pixel/` 不接 |

---

## 七、建議執行順序（改動小 × 收益大）

| 序 | 動作 | 工作量 | 回歸風險 |
|---:|---|:-:|---|
| 1 | 3 隻怪 idle/attack 併入 `dnf/normalized/{slime_acid,skeleton_warrior,imp_hellfire}/` | **S** | 無（純加檔 + 重跑 import） |
| 2 | 出 3 檔稀有度框 + 改 `RARITY_SLOT` + 補 `EXPECT_TEX` | **S** | `verify_ui_assets` 補完後全綠 |
| 3 | 出 `equip_legs_48.png` + 4 個武器圖標搬進 `icons/equipment/` + 補數據 | **S** | 無（走增量路線） |
| 4 | 出 2 檔技能圖標 + 補 `ui_skin.TEX` 與 `SKILL_ICON` 各 2 條 | **S** | 無 |
| 5 | 4 張元素關鍵幀入 `data/fx.json` | **S** | 無 |
| 6 | 玩家三職業接入 + 職業選擇 | **M** | 無（新增 who，不動既有） |
| 7 | `anim/` 序列幀接線（拼長條 + 新 caller） | **M** | 無 |
| 8 | 怪物 7 隻獨立形象 + walk/hurt 補完 | **L** | 素材側，無回歸面 |

> 1–5 全部是 **S**，且合計只需 **9 張新圖**，可一輪做完。

---

## 八、待使用者裁定

1. **§七 順序是否照辦**（推薦先做 1–5 一輪）。
2. **§四 的「併入既有 id」是否接受**——它會讓 slime/skeleton/imp 的**外觀換成包內像素風**（替換現有 DNF 素材的視覺），動作數變多但畫風會變。這是**產品向的視覺決策**，不是技術決策。
3. `scene_path` 6 個冗餘欄位：刪欄位 or 補 6 個空場景 or 不動。

---

**檔案結尾** ｜ 彙編：游承峰 ｜ 未改動任何工程檔（本輪純審計）
