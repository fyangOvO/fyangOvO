# 交接文件 HANDOFF-C（UI 視覺打磨批次）

> 給接手 AI：本文件是《七傳說》Godot 像素刷寶 ARPG 的營地/面板 UI 視覺打磨批次交接。
> 日期：2026-09-30。

---

## 1. 環境速查

- 項目根：`D:\七傳說`；遊戲工程：`D:\七傳說\game`
- Python：`C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe`
- Godot console：`C:\Users\11265\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- 啟動：`--path . res://scenes/main/main.tscn`
- 資源導入：`--headless --path . --import`
- git origin：`https://github.com/fyangOvO/fyangOvO.git`（main），用戶要求每次完成後 commit + push

## 2. 資源導入鐵律（重要，踩過多次坑）

1. 新 PNG 落盤後必須刪舊 `.import` 並跑 `godot --headless --path . --import`
2. **圖片邊長 > 2048 會導致 import valid=false 黑圖**，必須先用 PIL 縮到 ≤1920
3. 檢查 `.import` 內若有 `valid=false` 即為導入失敗，貼圖不會顯示
4. Godot 4.7.2 窗口模式枚舉名不可用，用整數字面量：0=窗口，2=獨占全屏，3=無邊框

## 3. 本批次已完成

- 全局字體從細 Cubic_11 換成更粗的 ChillBitmap_16（正文 12、標題 18）
- 設置面板新增「顯示模式」下拉（窗口/無邊框/獨占全屏）+「解析度」下拉（720p–4K）
- 背包格子改用像素槽位貼圖（空槽/稀有度配色）
- 據點從文字按鈕列表改成營地場景：
  - 背景：`game/assets/ui/camp_scene.png`（遠景，5 人圍篝火，已縮 1920×810）
  - 8 個功能熱區：半透明 Button（60×100）覆蓋人物位置，點擊彈台詞 + 開對應面板
  - 熱區位置在人物上方畫 36×48 小像素立繪（主角除外，已移除）
- 8 個 NPC 小立繪（**實測落點 `game/assets/ui/quest/npc/*_small.png`**，已摳背景，120×160 內）：
  smith_small / tailor_small / gem_small / master_small / quest_small / guard_small / abyss_small / merchant_small
- 金色雕花面板框 `game/assets/ui/quest/panel_gold.png`（512×512，卷草紋四角+寶石飾）
- 金色按鈕九宮格 `game/assets/ui/quest/btn_gold.png`（**432×92，已去白底 + bbox 裁切**），**已進 `theme.tres` 全局套用**
- 任務列表項金邊 `game/assets/ui/quest/quest_item.png`（**477×129，已去白底 + bbox 裁切**）
- UISkin 工廠：`panel_stylebox_gold()` / `button_stylebox_gold()`

> ⚠️ **路徑更正（2026-09-30 復盤）**：上述素材原本落在 `game/assets/ui/` **根目錄**，
> 而 `UISkin.TEX` 登記的是 `assets/ui/quest/<rel>`（`BUILTIN_ROOT`）⇒ `texture()` 全回 null
> ⇒ **面板金邊 / NPC 立繪從未顯示過**（這就是用戶反覆反映「面板沒變」的根因）。
> 已用 `git mv` 全部遷入 `assets/ui/quest/`（NPC 進 `quest/npc/`），並改寫 19 個 `.import` 的 `source_file`。

## 4. 關鍵文件

- `game/scripts/core/hub.gd`：據點場景。HOTSPOTS 陣列定義 8 熱區（座標對 640×360 邏輯畫布）；`_add_hotspot()` 畫貼圖+透明按鈕；`_ensure_panel()` 建面板 holder（內面板已設 StyleBoxEmpty 透明以顯外層金邊）；`_speak()` 彈 2.5 秒對話泡
- `game/scripts/ui/ui_skin.gd`：TEX 表登記貼圖路徑（注意 key 必須與 hub 熱區 tex 字段完全一致，曾因 key 不匹配導致 NPC 不顯示）
- `game/scripts/ui/ui_theme.gd`：全局主題，Button 三態已換金邊
- `game/scenes/ui/theme/theme.tres`：實際掛載的主題資源

## 5. 未完成清單（接手照做）

### 高優先
1. ~~**面板金邊實際顯示驗證**~~ ✅ **已修並目視驗證（2026-09-30 復盤）**。根因不是 margin，是**素材路徑錯位**（見 §3 更正）＋ 按鈕九宮格寫在死路徑（見 §8）。現 `panel_gold.png` / `btn_gold.png` 皆已進 `theme.tres`，`deliverables/gstack/c_review_shot/` 5 張截圖可證金邊顯示。
2. **NPC 熱區座標對齊**：HOTSPOTS 座標是對舊營地圖估的，換背景或人物位置後需重新對齊（人物實際位置 vs 熱區/貼圖位置）
3. **營地人物與背景重複**：camp_scene.png 已內建 5 個人物，熱區又疊了一層小立繪，可能視覺重複。需決定：要麼用整張圖（移除熱區貼圖只留熱區），要麼用純背景 + 獨立 NPC 貼圖

### 中優先
4. **技能樹節點圈**：AI 生圖一直畫成整個輪盤，最終改用代碼 `_draw()` 畫金色圓環，尚未做
5. **任務日誌面板**：參考圖是左右分欄（左任務列表+右任務詳情+追蹤/放棄按鈕），現有任務面板未照此重做
6. **各功能面板內容金邊化**：StatPanel/ForgePanel/RuneCodexPanel 等內部子控件（標題、分隔線、列表項）尚未全部套金邊素材
7. **merchant NPC 未接入熱區**：merchant_small 已生成但 HOTSPOTS 無對應功能（商店系統？），需確認功能後接入

### 低優先
8. NPC 待機呼吸動畫：目前只做了名字標籤浮動，人物貼圖本身未做呼吸/動圖
9. 按鈕 hover/pressed 三態目前共用同一金邊貼圖，未做壓暗/高光差異

## 6. 避坑斷言

- 任何「貼圖沒顯示」先查 `.import` 的 valid 字段，再查尺寸是否 >2048
- UISkin.texture(key) 缺失返回 null，調用方必須 null 判斷
- 稀有度/掉落表等遊戲邏輯常量不要在本批次改動，本批次只動 UI
- git 操作遵守用戶偏好：可 add/commit/push，但不要 reset/checkout/clean 丟用戶改動

## 7. 驗收方式

- 跑 `godot --headless --path . --import` 無報錯
- 實機進據點：8 個 NPC 可見、點擊彈台詞並開面板、面板顯示金邊
- 全量回歸（若存在 run_regression.py）保持通過

## 8. 復盤修正記錄（2026-09-30 接手復盤）

本輪針對「UI 打磨看起來做了卻沒生效」做根因排查，修復 4 類**靜默脫鉤**（都不報錯、只是不生效）：

| # | 症狀 | 根因 | 修法 |
|---|---|---|---|
| A | 面板金邊從未顯示 | 素材在 `assets/ui/` 根，UISkin 找 `assets/ui/quest/` | 11 個 PNG `git mv` 進 `quest/` + 改寫 19 個 `.import` 的 `source_file` |
| B | 金色按鈕無變化 | 九宮格寫在 `ui_theme.gd`，但遊戲實際掛 `theme.tres`，而生成器 `gen_ui_theme.gd` 被隔離 | 取回生成器；`ui_theme.gd` Button 五態改走 `UISkin.button_stylebox_gold()` 單一來源；重跑生成器落盤 `theme.tres` |
| C | 標題徽章消失 + 封面垂直節奏 360→328 | `title_emblem.png` 3548×1181 > 2048 ⇒ import `valid=false` ⇒ 貼圖載不到 | PIL LANCZOS 縮到 336×112，刪舊 `.import` 重導入 |
| D | `btn_gold.png` / `quest_item.png` 帶白框 | 外圍不透明白底（250,251,253,255） | 邊界連通洪水填充去背 + bbox 裁切（432×92 / 477×129） |

**連帶修復的既有紅**：
- `verify_e2e` ④（既有紅，非本批引入）——`hub._level_list` 是**懒挂載**（點「▶ 出擊」才入樹），而測試直接 `_find_button` 找關卡按鈕 ⇒ 找不到。已改測試復現真實玩家路徑（先點出擊再點關卡）。**已用「換回 HEAD 版 `hub.gd`」對照實驗證實與本批無關**。
- **閃爍（flaky）根因**：無頭模式 **V-Sync 會把 FPS 鎖到顯示器刷新率**，而 `verify_buff._step(seconds)` 用「秒 → 幀數」近似時間 ⇒ 高刷機上 24 幀遠小於 0.2s ⇒「增益到期」斷言假紅。**實測 `--fixed-fps 1000` 必紅 3 條 / `--fixed-fps 30` 必綠**。
  修：`verify_buff._step` / `verify_set_effects._step` 改用 `SceneTreeTimer`（與 `_process` 同源 delta）；`verify_e2e` 拾取等待改等 `LOOT_POP_DELAY` 真實時間。
  ⚠️ `verify_element_ext` / `verify_health` / `verify_juice` / `verify_loot` 用的是 `physics_frame`（固定 60Hz）⇒ **不受影響，勿誤改**。
- **回歸工具改進**：`tools/run_regression.py` 原本把失敗輸出的 `tail` 算出來卻**丟棄**，導致只能看到「失敗 N 項」無法定位。已加印失敗輸出的最後 25 行。

**同步更新的斷言**（口徑變更算正式設計）：
- `verify_ui`：字號 11→12 / 16→18；B2 段加 Button/normal **型別一致性**斷言；F 段 Button 改斷言 `StyleBoxTexture`；D 段 StyleBoxFlat 門檻 12→8
- `verify_ui_assets`：壓暗 alpha 128→180；新增 panel_gold/btn_gold/quest_item 釘死尺寸 + 8 NPC「載得到且 ≤120×160」
- `verify_ui71`：帳號文案 `"账号 Lv."` → `"Lv."`
- `verify_skill_panel`：熱區改用 `Hotspot_<pid>` 命名取鈕
- `self_check`：元素減傷斷言改按公式推導（`50/(50+K*1)`）而非寫死

**新增工具**：`game/tools/capture_c_review.gd/.tscn`（**非 headless**，輸出 `deliverables/gstack/c_review_shot/` 5 張）——復盤目視驗收用，只碰測試槽位 7。

**驗收結果**：全量回歸 **84 項檢查（77 Godot + 7 策劃）/ 208.0s / 失敗 0 項（全綠）**；`probe_tex` 13/13；生成器回讀校驗通過；5 張截圖目視確認徽章 / 金邊 / NPC / 金按鈕皆顯示。

> 對照：本輪共跑 4 次全量回歸。第 1 次紅 `verify_e2e`（既有紅）、第 2 次紅 `verify_buff`（閃爍）、第 3 次紅 `verify_buff`、第 4 次**全綠**。前兩次紅皆已定位並修復（見上）。
