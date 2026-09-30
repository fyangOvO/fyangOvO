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
- 8 個 NPC 小立繪（`game/assets/ui/npc/*_small.png`，已摳背景，120×160 內）：
  smith_small / tailor_small / gem_small / master_small / quest_small / guard_small / abyss_small / merchant_small
- 金色雕花面板框 `panel_gold.png`（512×512，卷草紋四角+寶石飾）
- 金色按鈕九宮格 `btn_gold.png`（512×180），已在 ui_theme 全局套用
- 任務列表項金邊 `quest_item.png`（512×140）
- UISkin 工廠：`panel_stylebox_gold()` / `button_stylebox_gold()`

## 4. 關鍵文件

- `game/scripts/core/hub.gd`：據點場景。HOTSPOTS 陣列定義 8 熱區（座標對 640×360 邏輯畫布）；`_add_hotspot()` 畫貼圖+透明按鈕；`_ensure_panel()` 建面板 holder（內面板已設 StyleBoxEmpty 透明以顯外層金邊）；`_speak()` 彈 2.5 秒對話泡
- `game/scripts/ui/ui_skin.gd`：TEX 表登記貼圖路徑（注意 key 必須與 hub 熱區 tex 字段完全一致，曾因 key 不匹配導致 NPC 不顯示）
- `game/scripts/ui/ui_theme.gd`：全局主題，Button 三態已換金邊
- `game/scenes/ui/theme/theme.tres`：實際掛載的主題資源

## 5. 未完成清單（接手照做）

### 高優先
1. **面板金邊實際顯示驗證**：用戶多次反映「面板沒變」。已修：內面板透明 + 外層金邊。接手後必須實機開背包/天賦確認金邊真的顯示，若仍不顯示，檢查 panel_gold.png 的 valid 狀態與九宮格 texture margin（現 60）
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
