# 项目长期记忆 — 七傳說（索引檔）

> **本檔只做「當前位置 + 未結遺留 + 最高優先事項」索引。**
> 📕 完整鐵律 / 坑 / 已拍板結論 → 同目錄 `IRON-RULES.md`（開工前必讀）
> 📘 數值與清單明細 → `deliverables/gstack/策划案/`（01–07 .md/.json）
> 📗 逐日細節 → `.workbuddy-ai/memory/YYYY-MM-DD.md`

---

## 🔴 當前位置（2026-09-30）

| 線 | 狀態 |
|---|---|
| 策劃七步 | ✅ 完成（180 工單 / 8 批次 / 568 通過 4 待修） |
| 素材開發線 | ✅ 收線（ASSET_MANIFEST v7：done 25 / BLOCKED 0） |
| 工程落地 B0–B5 | ✅ B5 特殊玩法八子批全收線（B5-1…B5-8） |
| **HANDOFF-C UI 打磨復盤** | ✅ **完成**（4 類靜默脫鉤全修 + 2 個既有紅修復） |
| **HANDOFF-D 符文圖標 v2** | ✅ **完成**（24 張重製為 48×48 高精細 + 符文石石板底座；1 個既有 bug 已定位未修） |

### HANDOFF-D 符文圖標 v2（2026-09-30）
- 24 條符文全部重畫：**4–5 階明暗 + 邊緣高光 + 內核輝光 + 微裝飾**，外掛**符文石石板底座**（外斜面 / 內凹槽 / 四角鉚釘）。
- 尺寸 32×32 → **48×48 原生**（原 32→48 是 1.5× 非整數縮放，違反像素鐵律）。
- 產線 `deliverables/gstack/素材開發/gen_rune_icons_v2.py`（`--base {vector,slab,frame}` / `--sample` / `--only` + `check_compliance()` 對照**權威色板**）。
- 消費端全庫唯一 = `rune_codex_panel.gd`；`ui_skin.gd` TEX 表 24 條改 `_48.png`。
- **關鍵坑**：`StyleBoxFlat.content_margin_*` 預設 = 邊框寬 ⇒ 格子內容區會隨「選中 1→2px」在 46/44 間跳、圖標變形。修法 `CELL 48→52` + 顯式 `set_content_margin_all(2)` ⇒ 內容區恆 48×48。
- 驗收：新增 `game/tools/capture_rune_codex.gd/.tscn`（斷言 24 張貼圖 48×48 + 兩態內容區 48 + 詳情圖標 48 + 4× 最近鄰放大目視）；**17 項全 OK**；全量回歸 77 Godot 全綠 / 185.2s。
- **附帶修復既有 bug**：圖鑑選中金框**從未顯示** —— `_on_cell_pressed()`/`select_rune()` 只重繪詳情、**不重繪格網**（典型「寫了狀態、沒寫渲染」靜默脫鉤）。已讓 `select_rune()` 補 `_render_grid()`，並加防回歸斷言（點擊後恰好 1 格選中 + 邊框 2px + 強調色）。

### HANDOFF-C 復盤（2026-09-30）
**4 類靜默脫鉤**（都不報錯、只是不生效）：
- **A 面板金邊從未顯示**：素材落 `assets/ui/` 根，而 `UISkin.TEX` 找 `assets/ui/quest/` ⇒ `texture()` 回 null（用戶反覆反映「面板沒變」的根因）。已 `git mv` 11 PNG 進 `quest/`（NPC → `quest/npc/`）+ 改寫 19 個 `.import` 的 `source_file`。
- **B 金色按鈕無變化**：九宮格寫在 `ui_theme.gd`，但遊戲實掛 `theme.tres`，而生成器 `gen_ui_theme.gd` 曾被隔離。已取回生成器；`ui_theme.gd` Button 五態改走 `UISkin.button_stylebox_gold()` 單一來源；重跑生成器落盤。
- **C 標題徽章消失 + 封面節奏 360→328**：`title_emblem.png` 3548×1181 > 2048 ⇒ import `valid=false`。已 LANCZOS 縮到 336×112 重導入。
- **D `btn_gold`/`quest_item` 帶白框**：外圍不透明白底。已洪水填充去背 + bbox 裁切（432×92 / 477×129）。

**2 個既有紅**（已用「換回 HEAD 版」對照實驗證實與本批無關）：
- `verify_e2e` ④：`hub._level_list` 是**懒挂載**（點「▶ 出擊」才入樹）⇒ 測試直接 `_find_button` 找不到。已改測試走真實玩家路徑。
- `verify_buff` **閃爍**：無頭 V-Sync 把 FPS 鎖到**顯示器刷新率**，而 `_step(seconds)` 用「秒→幀數」近似 ⇒ 高刷機假紅（`--fixed-fps 1000` 必紅 / `30` 必綠）。已改 `SceneTreeTimer`。

**新增工具**：`game/tools/capture_c_review.gd/.tscn`（非 headless，輸出 `deliverables/gstack/c_review_shot/` 5 張）。
**工具改進**：`tools/run_regression.py` 原本把失敗輸出算出來卻丟棄 ⇒ 已加印最後 25 行。

---

## 📋 未結遺留清單（跨批次匯總）

### 需用戶裁定
- **`boss_ember_lord.level_min 19 → 13`** 刻意偏離策劃 §1.1 等級帶表（表寫 19–20），為讓 `05-check` C19 轉綠 ⇒ 待裁定「改表 or 改回並放寬 C19」。
（無）

### 策劃側仍紅（非工程批）
- `05-check` **C17**（`ch1_l03/l04` 空 layout，屬 `5-W5-9`）· **C20**（creatures 目錄數，素材側）
- 另 **C12**（工程側關卡數 == 20）· **C13**（budget == Σcount_max）同屬既有口徑差，`05 --repo` 合計 **82/4**

### 工程側待接線（有落點、無消費方 = 死鉤子）
- **分支 8 個 modifier 未接**（`combo_hits`/`combo_damage_pct`/`linger`/`afterimage`/`pulse`/`summon_count`/`summon_damage_pct`/`buff_potency_pct`，面板標「暫未生效」）
- **符文掉落接線屬 B6 `2-L12`**（精英 8%/BOSS 25%，`unlocked_runes` 已備落點但無寫入方）
- **玩家→怪物施加異常未接通**（B4-5 拍板不做）⇒ 雷/暗異常只能由 2 雷怪 / 2 暗怪打玩家觸發
- **無異常 HUD**（`status_shock`/`status_curse` 素材已在但無消費點）
- `STAT_SHOCK_DAMAGE`/`STAT_CURSE_DAMAGE` 仍死鉤子（屬詞綴管線）；元素子鍵（`elemental_damage_*`）暫無供給源 ⇒ 恆 0
- `ms_boost.element_attach`（裂界指環附元素）未接線；`extra_loot` 未強制 `loot_quality`
- **`SetPanel` 尚未掛進真實 UI**（全庫只有 `set_preview`/`capture_set_panel` 在用）
- `talent_panel` 面板鍵（war/mage/shadow）與 `TalentTree` 鍵（might/guardian/arcane）**不一致（既有 bug）**
- `ACCOUNT_LEVEL_MAX 60` vs 策劃 `ruled_max_level 20`；`BIG_NODE_MECHANICS` 前 5 機制仍為展示字符串
- 套裝專屬特效視覺 6 套未生產；增益圖標 12 張未生產（B4-1 走佔位繪製）
- `explosive_arrow` 命中爆炸 / `poison_cloud`「使其中毒」/ `rune_echo`（`echo_count`）未承載
- 命名漂移：`AILMENT_SLOW="slow"` vs 素材鍵 `chill`；策劃 gaps 建議雷=「麻痺」，實現採「感電」
- 8 隻新怪 `sprite_path` 指向不存在 png（`use_placeholder_art` 兜底不崩，屬 **B7 素材替換**）
- `UISkin.affix_icon("armor_pierce")` 回 null（無運行時消費點，留 B7）

### 回歸殘餘（口徑）
- 舊記「**3 檔 4 項**」（`verify_choice_panel` 裸 Color 1 / `verify_player` 手柄映射 1 / `self_check` 怪物 L20 舊值 2→B6 `4-W5-e`）。本輪 `self_check` 已全綠、`verify_e2e`/`verify_buff` 已修 ⇒ **以最新一次全量回歸為準，勿沿用舊數字**。

---

## 批次歷程速覽

| 批 | 內容 | 備註 |
|---|---|---|
| B0 | `SkillType` 4→7 / `skills.json` 14→36 / 新建 `runes.json`(24)+`branches.json`(7) | — |
| B1 | 成長率 1.22/1.16→**1.12/1.12**（同值⇒相對強度恆定）/ 賬號上限 60→20 / 20 關 `budget` 5,660 / iLvl 三角抖動 | — |
| B2 | `ai_id` match 4→6 具名分支 / 修 `ranged_kiter`/`lobber` 死分支 / 12 關換越界怪 | `05 --repo` 82/4 |
| B3 | 詞綴 33→48、池 10→14、`FINAL_KEYS` 32→52、元素/抗性/穿透管線、`LegendaryBus` 總線、技能形態實體（projectile/ground_area）、套裝徽記 UI | 70 腳本 |
| B4 | B4-1 BuffComponent / B4-2 套裝特效 / B4-3 BOSS 技能+關卡目標 6 種 / B4-4 技能擴展 UI（**SAVE v5**）/ B4-5 元素飄字+異常 / B4-6 校驗補齊 | 76 腳本 |
| B5 | B5-1 存檔 **v6**+門票 / B5-2 稀有度 **8→10** / B5-3~8 特殊裝閉環+塔/深淵+校驗 | 06 202/0 · 07 212/0 |
| HANDOFF-C | UI 視覺打磨（本輪復盤：素材歸位 / 金按鈕上線 / 徽章修復 / 去白框） | 見上 |
| HANDOFF-D | 符文圖標 v2：24 張重製 48×48 高精細 + 符文石石板底座；`CELL 48→52` + 顯式內容邊距 | 77 Godot 全綠 |

---

## 基線 / 協作約定

- 暗黑刷寶 ARPG ｜ **Godot 4.7.2** ｜ GDScript ｜ 純單機 ｜ 美術 AI 生成 ｜ 視口 640×360
- ⚠️ 2026-09-23 用戶裁定「**代碼不上線**」⇒ 不做 Steam 發行，純本地自玩（移出：圖標/版本號/簽名/PCK 加密/存檔防篡改；仍在：本地可玩性、存檔可靠性、素材授權乾淨）
- 產物統一放 `deliverables/gstack/`；命名 `<場景類型>-<主題簡稱>-<YYYY-MM-DD>.md`
- **「幹活簡潔明瞭，不做多餘的事，或做之前問我」** ⇒ 少寫長報告、少做自選動作；**動手前先確認**
- 遊戲內 UI 文案用**簡體**；註釋/文檔用**繁體**
- 動 `game/` 前仍須逐次確認，且改動必須附驗證（原「AI 只策劃不改 game」邊界已在素材線突破）

---

## ⚠️ 最常踩的五個坑（詳解與全套 SF1–SF12 見 `IRON-RULES.md`）

1. **導出包內 `DirAccess` 枚舉 `res://` 全廢**（編輯器內永遠看不到）⇒ 一律走**顯式清單 / 命名約定探測**
2. **`.tscn` 節點漏 `type=` ⇒ Godot 靜默丟棄節點**（成批量同類警告先當 bug 症狀查）
3. **`UISkin` 工廠靜默返回 null** ⇒ 改素材路徑/鍵名後**必須真渲染抓圖目視確認**
4. **自洽式偽校驗**（腳本用自己的硬編碼常量算自己的斷言 ⇒ 永遠通過）
5. **String 字段靜默脫鉤**（`ai_id` 定義 6 種、代碼 0 分支、測試全綠）

**三條判據**：① 看到「永遠通過」的校驗 ⇒ 查常量是**引用**還是**硬編碼副本**
② 看到 `String` 字段（`ai_id`/`pattern`/`kind`/`behavior`）⇒ 先 grep 代碼分支數，命中 ≤1 = 沒實現
③ 改「看起來是配置項」的字段前 ⇒ 先 grep 消費點；只有「埋點/展示/註釋」⇒ 改了不會有行為變化

---

## ⚠️ 全案三條最高危項

1. **稀有度 8→10 不可逆** —— `rarity` 存 int；`RARITY_COUNT` 回退會把舊檔 8/9 **靜默壓成 7（隱藏裝）**
2. **62 件底材無一覆蓋 8/9 檔** ⇒ `loot_roller.gd:171` 空池 `return null` ⇒ 特殊檔什麼都不掉且零報錯
3. **`migrate()` 的 `_:` 兜底** —— 漏加版本分支**不報錯**、新字段直接消失 ⇒ 存檔升版必須逐版加顯式分支

---

## git 鐵律

- `origin` = `github.com/fyangOvO/fyangOvO.git` ✅ **推送一律 `git push origin main`**；`github.com/fyangOvO/game.git` ❌ 不再管
- Git LFS 已啟用；本地 `main` 根提交 `a8c6f6c` ⇒ 純快進無需強推
- **禁用**：`stash`（尤其 `-u`/`-a`）、`gc`、`prune`、`reset`、`checkout`、`clean`、`read-tree`、`filter-branch`
  **僅允許**：`add`/`commit`/`status`/`log`/`diff`（2026-09-20 事故：`stash push -u` 被 SIGTERM 中斷 ⇒ `.git` 整體進回收站）
- 清理殘留一律 `mv` 到 `.workbuddy-ai/trash/<日期>-<原因>/`，**不以 `rm` 直刪**

---

## 環境速查

```bash
cd D:/七傳說/game && APPDATA='C:\Users\11265\AppData\Roaming' python tools/package_demo.py --backup
```
- ⚠️ `APPDATA` 空串 ⇒ 導出失敗 + **靜默漏清存檔**（Godot 把數據目錄解析成 `./Godot/`）
- Python：`C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe`（系統 `python`/`/tmp` 不可用）
  - ⚠️ **管理版無 numpy**；素材生成/圖像腳本一律用 `C:/Users/11265/.workbuddy-ai/binaries/python/envs/default/Scripts/python.exe`（PIL 12.3 + numpy 2.5）
- 策劃校驗器（`deliverables/gstack/策划案/0N-check_*.py`，共 7 個）帶 `--repo D:/七傳說`（**專案根**，它自己拼 `game/`）
- Godot console：`C:\Users\11265\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- 全量回歸：`python tools/run_regression.py`（口徑：`[FAIL]==0 且 exit==0`）
- 驗證探針（`game/tools/`）：`probe_tex`（TEX 載入）/ `probe_fx`（fx 表契約）/ `probe_clips`（精靈幀集）/ `probe_level`（關卡體檢）
