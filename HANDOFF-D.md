# 交接文件 HANDOFF-D（符文圖標 v2 高精細重製批次）

> 給接手 AI：本文件是《七傳說》Godot 像素刷寶 ARPG 的**符文圖標重製**批次交接。
> 日期：2026-09-30。前置：`HANDOFF-C.md`（UI 視覺打磨復盤）。

---

## 1. 本批次做了什麼

用戶原話：「這個圖片裡的符文需要全部重新設計需要高度精細像素畫的素材」。
拍板兩項：**風格 = 加符文石底座**（在純符號外加石材）、**尺寸 = 48×48 原生**。

| 項 | v1（2026-09-24） | v2（2026-09-30） |
|---|---|---|
| 尺寸 | 32×32 | **48×48 原生** |
| 明暗階數 | 1–2 階平塗 | **4–5 階**（暗/中/亮/輝光） |
| 細節 | 無 | 邊緣高光 + 底部陰影 + 內核輝光 + 微裝飾（分叉/氣泡/餘燼/放射線/刻度） |
| 底座 | 無 | **符文石石板**（外斜面 / 內凹槽 / 四角鉚釘 / 左上受光倒角） |
| 落點 | `assets/ui/quest/rune_icon_<short>_32.png` | `assets/ui/quest/rune_icon_<short>_48.png` |

24 條全數重畫，**v1 的 24 張已移入 `.workbuddy-ai/trash/2026-09-30-rune-icon-v1/`**（非直刪）。

## 2. 產線與用法

- 生成器：`deliverables/gstack/素材開發/gen_rune_icons_v2.py`（複用 `gen_icons.py` 的索引畫布機制）
- 用法：
  ```bash
  cd "D:/七傳說/deliverables/gstack/素材開發"
  PY="C:/Users/11265/.workbuddy-ai/binaries/python/envs/default/Scripts/python.exe"
  "$PY" gen_rune_icons_v2.py --sample --base slab   # 只出樣張，不覆蓋遊戲素材
  "$PY" gen_rune_icons_v2.py --base slab            # 落盤 24 張 + 合規自檢
  "$PY" gen_rune_icons_v2.py --only fire,cold --base frame   # 迭代單張
  ```
- `--base` ∈ `vector`（純符號）/ `slab`（石板，**本批採用**）/ `frame`（鏤空石框）。
  兩種底座都保留在生成器裡，日後想換風格直接改參數重跑即可。
- ⚠️ 管理版 python（`versions/3.13.12`）**沒有 numpy**；必須用 `envs/default/Scripts/python.exe`（PIL 12.3 + numpy 2.5）。

**合規保證**：全程只畫在「索引畫布」（0=透明 1=描邊 2=暗 3=中 4=亮 5=輝光，底座另用 6–10 石色索引）
→ 4 鄰接膨脹自動描邊 → 最後才用色系映射到 44 色板 ⇒ **結構上不可能畫出色板外顏色**。
`check_compliance()` 會逐張比對權威色板（`NEUTRAL` + `SERIES`，逐字抄自 `gen_icons.py`，**不是本檔自算**）。
本批實測：24 張全 48×48、alpha 二值、全體用色 32 色（色板上限 39）。

## 3. 消費端改動（**唯一消費點**）

全庫只有 `rune_codex_panel.gd` 用 `UISkin.rune_icon()`（`skill_panel.gd` 的符文槽是**文字標籤**不是圖標）。

| 檔 | 改動 |
|---|---|
| `game/scripts/ui/ui_skin.gd` | TEX 表 24 條 `rune_icon_<short>_32.png` → `_48.png`；註釋同步 |
| `game/scripts/ui/rune_codex_panel.gd` | `CELL` 48 → **52**、新增 `CELL_PAD = 2`、`_cell_box()` 加 `set_content_margin_all(2)`、詳情圖標 `custom_minimum_size` 32 → 48、面板 `custom_minimum_size` (560,300) → (600,320) |

### ⚠️ 為什麼 `CELL` 是 52 而不是 48（本批最大的坑）

`StyleBoxFlat` 的**內容邊距預設 = -1，取用時回退成「邊框寬」**。而 `_cell_box()` 的邊框寬是
`1 if 未選中 else 2` ⇒ 若不顯式指定內容邊距，**格子內容區會在 46×46 / 44×44 之間跳**，
圖標跟著非整數縮放、還會隨選中狀態變形。

修法：`CELL = 52` + **顯式 `set_content_margin_all(2)`** ⇒ 內容區恆 `52 - 2×2 = 48×48`，
邊框 1px/2px 都落在邊距外互不遮擋 ⇒ 與 `rune_icon_*_48.png` 逐像素 1:1。

## 4. 驗收

新增工具 `game/tools/capture_rune_codex.gd/.tscn`（**非 headless**，輸出 `deliverables/gstack/c_review_shot/rune-*.png`）。
它同時做**數值斷言**與**目視抓圖**：

- ① 24 張 `UISkin.rune_icon()` 貼圖皆為 48×48（`texture()` 缺檔會**靜默回 null**，只看代碼看不出來）
- ② 格子內容區恆 48×48（未選中 / 選中兩態都驗）+ 佈局後 24 格實際內容寬皆 48
- ③ 詳情圖標 48×48
- ④ 抓圖 + 格網區 **4× 最近鄰放大**供逐像素檢視（有非整數縮放會出現糊邊）

實測結果：**12 項斷言全 OK / exit 0**；4× 放大圖無糊邊（確認整數 1:1）。

全量回歸：**77 個 Godot 腳本全綠 / 189.0s / exit 0**；7 個策劃校驗器 0 新增失敗
（`05 --repo` 仍是既有的 4 紅：C12 關卡數 / C13 budget / C17 空 layout / C20 creatures 目錄數，**與本批無關**；
`06` 202/0、`07` 212/0）。

## 5. 未結事項

### 5.1 已定位但**尚未修**的既有 bug（待裁定）

**符文圖鑑選中格子的金框永遠不會出現。**

- `_on_cell_pressed(rid)`（`rune_codex_panel.gd:158`）只呼叫 `_render_detail()`，
  **不呼叫 `_render_grid()`**；`select_rune()`（:257）同樣不重繪。
- `_render_grid()` 只在 `_render()` 裡被呼叫，而 `_render()` 只在 `_build_ui()`（:97）與 `bind()`（:115）被呼叫
  ⇒ `_selected` 改了但格子的 stylebox 從不更新 ⇒ `_cell_box(rid == _selected, …)` 的選中金框**從未生效**。
- 已用抓圖目視證實：`c_review_shot/rune-3-图鉴-选中详情.png` 中詳情已切到「增幅」，但左上格子無金框。
- 一行修法：`_on_cell_pressed` 內 `_render_detail()` 後補 `_render_grid()`；
  `select_rune()` 同樣處理（或讓兩者共用一條路徑）。**屬 `game/` 改動，需用戶確認後再動。**

### 5.2 其他

- 生成器裡保留的 `frame`（鏤空石框）底座變體未採用，樣張在
  `deliverables/gstack/素材開發/preview_D2_rune_v2_frame_sample.png`。
- 若日後要換風格：`--base frame` 或 `--base vector` 重跑即可，`BASE_SPEC` 控制符文子畫布尺寸/偏移。

## 6. 避坑斷言（本批新增）

- **`StyleBoxFlat.content_margin_*` 預設 = -1 ⇒ 取用時回退成「邊框寬」**。
  凡是「邊框寬會變的控件（選中/未選中）」＋「expand_icon 的圖標」，都必須顯式 `set_content_margin_all()`，
  否則圖標會隨狀態非整數縮放。**改了不會報錯，只是默默變形。**
- 素材尺寸一改，**必須同時核對消費端的內容區尺寸**，不能只看素材本身。
  本專案「整數倍 + 最近鄰」鐵律 ⇒ 素材邊長必須等於控件內容區邊長。
- `UISkin.texture()` 缺檔回 `null` 不報錯 ⇒ 換素材後**必須真渲染抓圖**，斷言 null 才算驗到。
- 換素材前先 `mv` 舊檔到 `.workbuddy-ai/trash/<日期>-<原因>/`，**不要 `rm`**。
