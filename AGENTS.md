# AGENTS.md —— 「七傳說」AI 接手入口

> **v2.0 ｜ 最後更新 2026-10-14**
>
> **讀完這一頁就能開始幹活。** 這裡有：現狀、可複製命令、倉庫地圖、架構速查、開發工作流、未結遺留。
>
> ⚠️ **代碼是唯一事實來源。** 任何文檔（含本檔）與代碼衝突 ⇒ **以代碼為準，並回來改文檔**。
> 本專案已發生過「記憶檔寫『片頭已接入啟動流程』、實際代碼仍直進主菜單」這類漂移，別重蹈。

---

## 0. 30 秒速覽

| | |
|---|---|
| **是什麼** | 純單機 **2D 俯視暗黑刷寶 ARPG** —— 局內三選一成長 + 局外裝備鍛造雙線養成 |
| **引擎** | **Godot 4.7.2.stable** ｜ GDScript 2.0 ｜ **不是** .NET / C# 版 |
| **倉庫根** | `D:\七傳說` ｜ 遊戲工程在 `game/` |
| **畫面** | 視口 **640×360**（`canvas_items` + **`integer`** 縮放）｜ tile 32×32 ｜ 角色 48×48 ｜ 過濾 **Nearest** |
| **規模** | **259** 個 `.gd`（約 **64,000** 行）｜ **160** 個 `.tscn`（含 **77** 個驗證場景）｜ **31** 份 `data/*.json` |
| **驗證** | `self_check` **122 項** + **77** 個 `verify_*` + **7** 個策劃校驗器 ⇒ 全綠約 **230s** |
| **發布** | ❌ **不上線 / 不發行 / 無聯網**（2026-09-23 用戶裁定）⇒ 不做圖標 / 版本簽名 / PCK 加密 / 存檔防篡改 |
| **三職業** | 戰士 `warrior`（金 `D9A441`）｜ 弓手 `archer`（綠 `8FBF5F`）｜ 法師 `mage`（藍 `7FA8E8`） |

**當前位置（2026-10-14）**：策劃七步 ✅ ｜ 素材開發線 ✅ ｜ 工程落地 B0–B5 ✅ ｜
HANDOFF-C/D/E ✅ ｜ 片頭「勇者斗惡魔」✅ ｜ **全面優化①–⑧ ✅**（清理 928MB + 賬號上限 20→30 + 打擊感/juice 八項）｜
**文檔 2.0 ✅**（本檔 + README 重寫 + 交接文檔歸檔）

---

## 1. 五條鐵律（違反 = 事故）

| # | 鐵律 | 為什麼 |
|---|---|---|
| **1** | **像素鐵律**：只允許**整數縮放**；紋理過濾必須 **Nearest**；**禁止運行時旋轉精靈**（方向動畫靠預烘） | 破壞像素網格 |
| **2** | **常量唯一源**：枚舉 / 顏色 / 系數全在 `game/scripts/core/game_constants.gd`；業務腳本**禁止**出現 `"legendary"` `0xFF8A2B` `1.28` 這類字面量 | 改一處全生效 |
| **3** | **模組間只走 `EventBus`**；換場景只發 `request_scene_change`，由 `SceneManager` 響應 | 避免節點直連耦合 |
| **4** | **資料與代碼分離**：策劃改 `game/data/*.json`，程序改 `game/resources/*.gd`，橋是 `ConfigLoader`；禁止硬編碼裝備名 / 數值 | 見 `game/README.md` §四 |
| **5** | **改動必須附驗證**：每輪結束跑全量回歸，`[FAIL]` 計數 == 0 **且** exit == 0 | 本專案的核心紀律 |

> 📕 **完整版 60+ 條坑（含踩坑現場與修法）→ [`IRON-RULES.md`](.workbuddy-ai/memory/IRON-RULES.md)**
>
> **動 `game/` 前必讀的幾條**（都在 IRON-RULES，這裡先給結論）：
> - **`class_name` 全局類緩存陷阱**：新 clone 沒有 `.godot/` ⇒ 一片 `Parse Error`。先跑一次 `--headless --editor --quit`。
> - **`APPDATA` 空串 ⇒ `user://` 變相對路徑**：會**偽裝成存檔代碼 bug**（一半能寫一半不能寫）。跑 Godot 前必須 `export APPDATA=...`。
> - **自洽式偽校驗**：斷言用自己的硬編碼常量算自己 ⇒ 永遠通過。要讀**被測物自己的常量**或真跑一遍。
> - **`String` 字段靜默脫鉤**：看到 `String` 字段先 grep 代碼分支數，命中 ≤1 = 沒實現。
> - **零調用方埋點**：有註釋、有常量、有邏輯的函數，先 grep 調用方數，== 0 = 死代碼。
> - **抓圖工具本身也要驗**：必須 `await RenderingServer.frame_post_draw` + 斷言「與上一張不同」；**改素材後舊截圖一律作廢**。
> - **兩段式落點坑**：要「進樹前」的狀態就在 `add_child` **前**設；要「進樹後」的狀態就在 `add_child` **後**讀。
> - **換全局控件樣式前先量「預設尺寸」**；**換底必查字**（雕花框中央是暗底 ⇒ 深字會隱形）。
> - **「回歸全綠」≠「無告警」**：`run_regression.py` **不轉發 stderr**，退出期泄漏只有單跑才看得到。

### 全案三條最高危項

1. **稀有度 8→10 不可逆** —— `rarity` 存 int；`RARITY_COUNT` 回退會把舊檔 8/9 **靜默壓成 7（隱藏裝）**
2. **62 件底材無一覆蓋 8/9 檔** ⇒ `loot_roller.gd:171` 空池 `return null` ⇒ 特殊檔**什麼都不掉且零報錯**
3. **`migrate()` 的 `_:` 兜底** —— 漏加版本分支**不報錯**、新欄位直接消失 ⇒ 存檔升版必須逐版加顯式分支

---

## 2. 快速上手（可複製命令）

### 2.1 環境路徑

```bash
GODOT="C:/Users/11265/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
export APPDATA='C:\Users\11265\AppData\Roaming'      # ← 不能省（見鐵律區的 APPDATA 坑）
PY="C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe"
```

> ⚠️ 圖像 / 素材生成腳本要用**另一個** Python（管理版**無 numpy**）：
> `C:/Users/11265/.workbuddy-ai/binaries/python/envs/default/Scripts/python.exe`（PIL + numpy）

### 2.2 四個高頻命令

```bash
# ① 首次（或刪過 .godot/）—— 生成 class_name 全局類緩存，只跑一次
"$GODOT" --headless --editor --quit --path "D:/七傳說/game"

# ② 自檢：122 項全綠 ⇒ exit 0
"$GODOT" --headless --path "D:/七傳說/game" -- --verify

# ③ 全量回歸（**收線必跑**）：77 verify 場景 + self_check + 7 策劃校驗器
cd "D:/七傳說" && python tools/run_regression.py

# ④ 單點排查（換檔名即可）
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_loot.tscn
```

**回歸判讀**：`[FAIL]` == 0 **且** exit == 0 ⇒ 全綠（約 230s）。

### 2.3 無頭開發約定（用戶明確要求）

- 🚫 **不要打開遊戲窗口** —— 一律 `--headless`，在後台靜默開發
- ⚠️ **例外**：抓圖工具（`capture_*`）**必須去掉 `--headless`**，否則渲染不推進、抓到的畫面是凍結的
- 用 `run_in_background` 跑長命令（回歸 230s）

---

## 3. 倉庫地圖

```
D:\七傳說\
├── AGENTS.md                   ← 📌 本檔（AI 唯一入口）
├── Playground開發描述.md        ← 🎯 玩法設計總綱（對標爆款暗黑向：割草 / 打擊感 / Build 聚變 / 像素動效）
├── docs/
│   ├── README.md               ← 文檔總索引（現行 vs 歸檔）
│   └── archive/                ← 已歸檔的一次性交接單（HANDOFF-C / D / E）
│
├── game/                       ← 🎮 Godot 工程（細節見 game/README.md）
│   ├── project.godot           ← 渲染 / 視口 / 輸入映射 / Autoload / 物理層
│   ├── export_presets.cfg
│   ├── CONTENT_GUIDE.md        ← 素材替換指南（不碰代碼換素材）
│   ├── scripts/                ← 邏輯（259 個 .gd，16 個子目錄）
│   ├── scenes/                 ← 場景（160 個 .tscn，8 個子目錄）
│   ├── resources/              ← 自訂 Resource 類（資料結構的**代碼定義**）
│   ├── data/                   ← 🎯 配置資料（31 份純 JSON，**策劃直接改這裡**）
│   ├── assets/                 ← 美術 / 音頻（走 **Git LFS**）
│   └── tools/                  ← 驗證 / 抓圖 / 探針（**不進導出包**）
│
├── deliverables/gstack/
│   ├── 策划案/                  ← 📐 01–07 設計文檔 + JSON + **7 個 Python 校驗器**
│   ├── 素材開發/                ← ASSET_MANIFEST.json + 素材生成腳本
│   └── *_shot/                 ← 真渲染截圖（目視驗收產物）
│
├── tools/run_regression.py     ← 全量回歸入口
│
└── .workbuddy-ai/
    ├── memory/
    │   ├── MEMORY.md           ← 🧠 專案長期記憶索引（當前位置 / 未結遺留 / 基線約定 / git 鐵律）
    │   ├── IRON-RULES.md       ← 📕 60+ 條坑（含踩坑現場與修法）
    │   └── YYYY-MM-DD.md       ← 逐日工作誌（每批次的完整復盤）
    ├── trash/                  ← 清理暫存（**可還原**，勿直接 `rm`）
    └── scratch/                ← 臨時腳本與日誌
```

### 事實來源優先序（衝突時）

```
代碼 / project.godot  >  IRON-RULES.md + MEMORY.md  >  deliverables/gstack/策划案  >  game/README.md  >  docs/archive/
```

---

## 4. 架構速查

### 4.1 Autoload（6 個，**順序不可調換**）

| # | 名稱 | 腳本 | 職責 |
|---|---|---|---|
| 1 | `EventBus` | `scripts/autoload/event_bus.gd` | 信號總線，模組間**唯一**通信管道 |
| 2 | `ConfigLoader` | `scripts/autoload/config_loader.gd` | 讀 `data/*.json` → Resource 註冊表 + 跨表校驗 |
| 3 | `SaveManager` | `scripts/autoload/save_manager.gd` | 多槽存檔 / 版本遷移 / 校驗 / 備份輪轉 |
| 4 | `SceneManager` | `scripts/autoload/scene_manager.gd` | 場景切換 / 異步加載 / 過場 |
| 5 | `InputRemapper` | `scripts/core/input_remapper.gd` | 輸入重映射 / 手柄熱插拔 |
| 6 | `JuiceFX` | `scripts/juice/juice_fx.gd` | 打擊感控制器：監聽事件 → 飄字 / 閃白 / 震屏 / 頓幀 / 粒子 |

> `GameConstants` **不是** Autoload —— 它是純靜態常量類（`class_name GameConstants`），
> 直接 `GameConstants.Rarity.LEGENDARY` 訪問即可。

### 4.2 場景流

```
main.tscn（啟動分流）
 ├─ --verify  → tools/self_check.tscn（打印報告 + 按退出碼 quit）
 ├─ --smoke   → tools/verify_e2e.tscn（導出包內跑完整流程）
 └─ 正常啟動 → main_menu.tscn（⚠️ 片頭 intro.tscn 刻意未接入，見 game/README.md §1.1）
                     ↓
                  hub.tscn（據點：選關 / 鍛造 / 天賦 / 倉庫）
                     ↓
                  levels/level.tscn（20 關**共用一份**，差異由 level_id + difficulty_tier 驅動）
```

### 4.3 資料流與兩層結構

```
data/*.json  ──ConfigLoader──▶  Resource 模板（EquipmentData / MonsterData / LevelData …）
                                        │
                                  loot_roller / affix_roller 擲骰
                                        ▼
                                EquipmentInstance（實例，可入包 / 可存檔）
```

- **模板 / 實例分離**：`EquipmentData`（幾百個底材模板）vs `EquipmentInstance`（每掉一件一份）
- 存檔只落盤**模板 ID + 實例字段**，讀檔由 `ConfigLoader.resolve_instance()` 回填
- ⚠️ **任何讀檔路徑都必須用 `SaveManager.load_from_slot_resolved()`**，否則 `template` 為空、`get_display_name()` 退化

### 4.4 打擊感架構（全面優化②–⑧ 的成果）

**全部事件驅動，`JuiceFX` 統一出表現，不新增素材。**

```
戰鬥事件 ──EventBus──▶ JuiceFX ──▶ 表現
  damage_dealt            ├─ 傷害飄字（含異常 DoT 小跳字）
  ailment_tick            ├─ 屏震（按 AoE 半徑分級）
  screen_impact           ├─ 頓幀（暴擊固定檔 ∪ 按傷害比例分級，取 max）
  rare_loot_spawned       ├─ 稀有掉落慶祝（全屏稀有度色閃光 + 震 + 頓 + 粒子迸發）
  enemy_died              └─ 像素粒子
```

其他 juice：掉落**磁吸吸附**（`pickup_radius` 詞綴首次接通）、掉落物 **pop 動畫**（自死亡點拋物線飛出 + 星光）、
拾取光暈**按稀有度染色**、地面**元素貼花**（自繪，避開 `z_index` 遞迴陷阱）。

---

## 5. 開發工作流（AI 該怎麼幹活）

### 5.1 動手前

1. **先讀**：本檔 → `IRON-RULES.md` 相關條目 → `MEMORY.md` 未結遺留
2. **先查**：要動的東西有沒有**已存在的機制**（`grep` 事件名 / 常量名 / 類名）
3. **先確認**：涉及 `game/` 的改動、或有多種合理做法時 —— **問用戶**（見下方約定）
4. **建立任務清單**：3 步以上的活，用 TaskCreate 列出來

### 5.2 動手時

- **一次一個主題**，改完立刻小範圍驗證，別攢一大坨
- **不要自選動作** —— 用戶反覆強調「**幹活簡潔明了，不做多餘的事，或做之前問我**」
- 清理檔案一律 **`mv` 到 `.workbuddy-ai/trash/<日期>-<原因>/`**，**不以 `rm` 直刪**
- 文案：**遊戲內 UI 用簡體**；**註釋 / 文檔用繁體**

### 5.3 收線時（缺一不可）

1. **跑全量回歸** `python tools/run_regression.py` ⇒ 必須 `[FAIL]` == 0 且 exit == 0
   - 若動過 `game/`，**額外單跑**受影響的 `verify_*` 看有無退出告警（回歸看不到）
2. **更新記憶**：
   - 追加到 `.workbuddy-ai/memory/YYYY-MM-DD.md`（當日工作誌，**append-only**）
   - 影響長期事實的（約定 / 架構選擇 / 遺留變化）改 `MEMORY.md`；新坑寫進 `IRON-RULES.md`
3. **提交**（見 5.4）

### 5.4 提交規範

- **一個提交 = 一個可獨立理解的主題**（不按時間硬切）
- 訊息格式：`<type>(<scope>): <中文一句話>` + body 寫**為什麼**與**怎麼驗的**
- **git 只允許**：`add` / `commit` / `status` / `log` / `diff`
- 🚫 **禁用**：`stash`（尤其 `-u` / `-a`）、`gc`、`prune`、`reset`、`checkout`、`clean`、`read-tree`、`filter-branch`
  （2026-09-20 事故：`stash push -u` 被 SIGTERM 中斷 ⇒ `.git` 整體進回收站）
- **推送**：`git push origin main`（`origin` = `github.com/fyangOvO/fyangOvO.git`；`.../game.git` ❌ 不管）
  - ⚠️ 本機**直連 github 不通**，必須走本地代理 `http://127.0.0.1:7888`（已配在 `git config`，**別清空代理**）
  - ⚠️ **推送必須在沙箱外**執行（沙箱網絡中介會攔 `github.com`）
  - ⚠️ 先探活再推：`curl -sS -o /dev/null -w "%{http_code}\n" -x http://127.0.0.1:7888 https://github.com`（3 次都 200 再推；偶發失敗直接重試）
  - ⚠️ LFS 的 locks API 報 `does not support ... locking` 屬**正常噪音**，不影響推送

---

## 6. 未結遺留與待裁定（摘要）

> 完整清單（含每一項的現狀與影響）→ `game/README.md` §9.2

### 6.1 需用戶裁定（5 項）

| # | 項 | 一句話 |
|---|---|---|
| 1 | `04-check_number_model.py` 仍是**上限 20** 口徑 | 上限已改 30 ⇒ `L2/L2b` 不變式失效。04 仍綠但**文檔與代碼已知分歧** |
| 2 | 技能終極階 `unlock_level` = **20**（原 22） | 上限回 30 後 L22 又可達 ⇒ 維持 20 or 改回 22？ |
| 3 | `boss_ember_lord.level_min` **19 → 13** | 刻意偏離策劃等級帶表（表寫 19–20），為讓 `05-check` C19 轉綠 |
| 4 | 深淵表 `rune_drop_chance` **不會被消費** | 要不要讓深淵房走自己的掉落表？ |
| 5 | `EventBus.loot_dropped` 是**死信號**（零 emit） | 接線 or 刪除？ |

### 6.2 工程側待接線（節選，詳見 README §9.2(b)）

分支 7 個 modifier（**刻意延後**）｜ `material_sub_weights` / `item_level_spread` 死字段 ｜
玩家→怪物施加異常未接通 ｜ 無異常 HUD ｜ `SetPanel` 未掛進真實 UI ｜
`UISkin.affix_icon()` 零調用方 ｜ 8 隻新怪 `sprite_path` 指向不存在的 png（B7 素材替換）

### 6.3 策劃側仍紅

`05-check` C17 / C20 / C12 / C13（既有口徑差，`05 --repo` 合計 **82/4**）

### 6.4 已知測試噪音（不影響回歸判定）

- `self_check` 退出時漏 **28** 個物件（UI 類，非音頻）
- `verify_hud` 退出時漏 **6** 個物件 + 2 個資源

---

## 7. 文檔索引

| 想知道什麼 | 讀哪 |
|---|---|
| **怎麼開始幹活** | **本檔** |
| 全庫文檔導航 | [`docs/README.md`](docs/README.md) |
| 遊戲工程細節 / 目錄 / 約定 / 怎麼加內容 | [`game/README.md`](game/README.md) |
| **踩過的坑（60+ 條）** | [`IRON-RULES.md`](.workbuddy-ai/memory/IRON-RULES.md) |
| 當前位置 / 遺留 / 基線約定 / git 鐵律 | [`MEMORY.md`](.workbuddy-ai/memory/MEMORY.md) |
| 某個批次的完整復盤 | [`.workbuddy-ai/memory/`](.workbuddy-ai/memory/)（按日期） |
| 玩法方向 / 對標爆款 | [`Playground開發描述.md`](Playground開發描述.md) |
| 技能 / 裝備 / 數值 / 怪物 / 特殊玩法 | [`deliverables/gstack/策划案/README.md`](deliverables/gstack/策划案/README.md) |
| 換素材（不碰代碼） | [`game/CONTENT_GUIDE.md`](game/CONTENT_GUIDE.md) |
| 歷史交接單（**已歸檔**） | [`docs/archive/`](docs/archive/) |

---

## 8. 協作約定（用戶偏好，務必遵守）

- 🗣️ **回覆用簡體中文**；遊戲內 UI 文案用**簡體**；註釋 / 文檔用**繁體**
- ✋ **「幹活簡潔明了，不做多餘的事，或做之前問我」** —— 少寫長報告、少做自選動作、**動手前先確認**
- 🔧 **動 `game/` 前逐次確認**，且改動必須附驗證
- 🎯 **後台靜默開發**，不要打開遊戲窗口
- 📦 產物統一放 `deliverables/gstack/`，命名 `<場景類型>-<主題簡稱>-<YYYY-MM-DD>.md`
- 🚫 不主動建立 `*.md` 文檔（除非用戶要求）；不寫 emoji 進檔案
