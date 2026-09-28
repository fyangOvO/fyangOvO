# 七傳說 · 鐵律與坑分冊（IRON-RULES）

> **本檔是 `MEMORY.md`（索引）的詳細分冊 —— 動 `game/` 或寫策劃案前必讀。**
> 進度與當前位置見 `MEMORY.md`；數值與清單明細見 `deliverables/gstack/策划案/`（01–07 .md/.json）。
> **下一步 = 照 `策划案/07-开发总表.md` 的 B0→B7 批次落地；B0 ✅ / B1 ✅ / B2 ✅ ⇒ 起點 `B3 死鉤子接線`（58 工單 · 最大批）**

## 基线 / 协作约定
- 暗黑刷宝 ARPG ｜ **Godot 4.7.2** ｜ GDScript ｜ 纯单机 ｜ 美术 AI 生成
- ⚠️ 2026-09-23 用戶裁定「代碼不上線」⇒ 不做 Steam 發行，純本地自玩
  （移出：圖標/版本號/簽名/PCK 加密/存檔防篡改；仍在：本地可玩性、存檔可靠性、素材授權乾淨）
- 产物统一放 `deliverables/gstack/`；命名 `<场景类型>-<主题简称>-<YYYY-MM-DD>.md`
- **「幹活簡潔明瞭，不做多餘的事，或做之前問我」** ⇒ 少寫長報告、少做自選動作；**動手前先確認**
- 原「AI 只是策劃、不改 `game/`」的邊界在**素材開發線**已被突破（`素材開發/README.md` §7.2/§9.2 實際改了
  `ui_skin.gd`/`fx.json`/`juice_fx.gd`/`skills.json`/`skill_controller.gd`/`enemy_base.gd`/`summon.gd`…）
  ⇒ **動 `game/` 前仍須逐次確認**，且改動必須附驗證
- git 提交是常規動作；**推送前必須確認目標遠程**

---

## 七步彙總（散落 6 份文檔 → 單一入口）

**① 工單 180 條**：步分佈 33/42/47/17/13/28 ｜ P0 **73** / P1 **59** / P2 **43** / P3 **5**（舊口徑「179」漏算 `V7b`）

**② 8 批次**（按序開工）
```
B0 數據地基(13) 1-D1..D7 + 1-L1/L2 + 1-V1..V4 ⇒ 讓「+技能等級」詞綴真生效，不動戰鬥平衡
B1 數值三件套(7) 🔴 4-W1+W2+W3+W10+W11 + 5-W5-4 + 5-W5-10
B2 內容底座(3)   🔴 5-W5-1+W5-2+W5-3（先修 AI 再加怪）
B3 死鉤子接線(58) 最大批 ｜ B4 玩法擴展(28)
B5 特殊玩法(28)  🔴 內部嚴格順序 01→11/12/13→08/09/10→05/06/07
B6 打磨清理(26) ｜ B7 素材替換(16)（`5-W5-12` batch="—" 明確不執行）
```

**③ 14 條同批硬約束**（違反 = 靜默失敗或數值不自洽）
C1 `W1+W2+W3` ｜ **C2 `W2+W10+W11`（路線A三件套）** ｜ **C3 `W5-4` 與 `W2` 同批** ｜ **C4 `W5-1` 與 `W5-3` 同批**
｜ **C5 `W5-10` 與 `W5-4` 同批**（曲線斷言同步）｜ C6 `E1–E5` ｜ **C7 `W6-01` 存檔升版最先行**
｜ **C8 `W6-11+12+13`（特殊檔三件套）** ｜ **C9 `W6-Q5+Q6+Q7`（半重鑄三件套）** ｜ C10 `1-D1` 先於 `1-D2/D5`
｜ C11 `2-D1` 先於 `2-D4` ｜ C12 `SUM0` 先於 `SUM1` ｜ C13 素材「一般→實機跑→再細化」｜ C14 UI 素材登記後必須真渲染抓圖

**④ 14 行跨步修訂表**（**不回改 01–05 原文件**，留歷史快照）
R1 `05-bosses.json` 4 階段→二階段(S11) ｜ R2 全文「8 檔」→10 檔(S12) ｜ R3 **保持 D4 不變**（不新增 BOSS，用場地變化區分）
｜ R4 第四步 18 底材**不執行** ｜ R5 `frost_monarch` 84 幀**不入清單** ｜ R6 D1 ai_id 一次做全 ｜ R7 D2 走 `count_*`
｜ R8 D3 16→24 ｜ R9 D5 兩種目標都補 ｜ R11 第六步 v0.1 骨架**三條全推翻** ｜ R12 `game/README.md` 視口過期
｜ R13 註釋塊舊成長率 ｜ R14 `verify_balance84` 偽校驗

**依賴鏈關鍵路徑**：`1-D1→1-D2→1-V1/V2` ｜ `1-D1→1-L1→1-L2→3-X6 / 1-L3..L5` ｜ `4-W2→5-W5-4→5-W5-10`
｜ `5-W5-1→5-W5-3→5-W5-5→6-W6-08→09/10` ｜ `6-W6-01→…→6-W6-11→12/13`

**七步校驗基線**：01 `27/0` ｜ 02 `11/4`⚠️ ｜ 03 `36/0` ｜ 04 `46/0` ｜ 05 `66/0` ｜ 06 `186/0`（`--repo` 202/0）｜ 07 `196/0`（`--repo` 212/0）
⇒ **568 通過 / 4 失敗**。4 條全為第二步**已知待修缺口**（非 bug）：`A1` 孤兒詞綴 1 / `A4` 通用池混 min_rarity≥3 共 2 /
`A5` 底材 base_stats 鍵 1 / `C2` legacy 鍵 `armor_penetration` 殘留 1 ⇒ 對應工單 `2-D1`/`2-D4`/`2-D2`，落地後應全綠。

**第七步新查出並已修的兩問題**：① **素材跨步重複下單三處**（召喚物精靈：第一步 2 隻 vs 第四步 4 隻 ⇒ 取 4 隻，
`sum_wolf`≈`spirit_wolf` 須合併命名；元素圖標：第四步 10 ⊂ 第三步 14；技能圖標「一般 48 = 技能 24 + 符文 24」）
⇒ 去重後一般方案 ≈ **1,920 幀 + 224 圖標 + 2 音頻** ② **依賴圖有環** `6-W6-17` ↔ `6-W6-Q8` ⇒ 兩者都只依賴 `6-W6-11`

---

## ⚠️ 全案三條最高危項
1. **稀有度 8→10 不可逆** —— `rarity` 存 int；`RARITY_COUNT` 回退會把舊檔 8/9 **靜默壓成 7（隱藏裝）** ⇒ 存檔永久損壞
2. **62 件底材無一覆蓋 8/9 檔**（最大 `rarity_max`=7）⇒ `loot_roller.gd:171` 空池 `return null` ⇒ 特殊檔什麼都不掉且零報錯
3. **`migrate()` 的 `_:` 兜底** —— 漏加 `4:` 分支**不報錯**、新字段直接消失 ⇒ 存檔升版必須逐版加顯式分支

---

## 铁律三条（改動前必读）

**① 唯一色源** `game_constants.gd:607` —— 烘焙圖像資產像素必須全落在 `PALETTE_ALL`（名義 48 **已定義 44**；校驗 `:659`）
- 權威 `art-style-and-ai-pipeline-phase0-0.7-2026-09-16.md` §1.1：俯視 / tile 32×32 / 角色 48×48 / 單精靈 ≤24 色 / 只允許整數縮放 / **禁止運行時旋轉**

**② 视口 640×360** `project.godot:44-51` —— `canvas_items`+`keep`+**`scale_mode=integer`**
⇒ 可見 **20 列 × 11.25 行 tile**（32px）⇒ **一屏裝不下一個房間**；字號僅 11/12px
⇒ ⚠️ `game/README.md` 寫「1920×1080…一屏 60 tile」**已過期**（R12）
⇒ `DNF_GAME_SCALE=0.25` ⇒ 192px 精靈實機只顯示 **48px**，素材 1–2px 細節會被降採樣吃掉

**③ 导出包内 `DirAccess` 枚举 `res://` 全废（P0）**
根因 `export_filter="all_resources"` 只把 PNG 導入產物 `.ctex` 寫進 PCK ⇒ **按路徑載入 ✅ / 目錄枚舉 ❌**。
**編輯器內永遠看不到**，只有跑 `七傳說.exe --smoke` 才暴露。修法：`enemy_base.gd` 的 `pack_load_set()` 走
`pack_probe_names()` 命名約定探測。**⇒ 通則：導出包裡凡要讀 `res://` 一批檔案，一律走顯式清單 / 命名約定探測。**

---

## ⚠️ 五类「静默失败」陷阱 + 自查清單 SF1–SF12
1. **`.tscn` 節點漏 `type=` ⇒ Godot 靜默丟棄節點**（`CollisionShape2D vanished` 爆發源）
   排查 `grep -n '^\[node name="[^"]*" parent="[^"]*"\]$'` ⇒ **成批量同類警告先當 bug 症狀查**
2. **`UISkin` 工廠靜默返回 null**（素材缺失或**鍵名寫錯** ⇒ 返回 null 並快取，調用方跳過 ⇒ 畫面空空而回歸全綠）
   ⇒ 改素材路徑/鍵名後**必須真渲染抓圖目視確認**；「Godot 能否加載」用 `ResourceLoader.exists()`，
   「檔案在不在磁盤」用 `FileAccess.file_exists()`，**兩者不可互替**
3. 導出包目錄枚舉失效 ⇒ 見铁律③
4. **「自洽式偽校驗」永遠通過的校驗腳本**（實例 `tools/verify_balance84.gd:26-29` 硬編碼 1.284/1.218，實值 1.22/1.16；R14）
5. **「String 字段靜默脫鉤」**（最重）—— `ai_id` 是 `String` 非 `enum` ⇒ 無編譯期約束 ⇒ 定義 6 種、代碼 **0 分支**、測試全綠

**SF1** `.tscn` 漏 `type=` ｜ **SF2** `UISkin` 返回 null ｜ **SF3** 導出包目錄枚舉 ｜ **SF4** 自洽式偽校驗
｜ **SF5** String 字段脫鉤 ｜ **SF6** `migrate()` 的 `_:` 兜底 ｜ **SF7** `loot_roller` 空池 return null
｜ **SF8** `_draw_beam()` 不按 shape 分支 ｜ **SF9** `AffixData` 無 `source` ｜ **SF10** 枚舉字符串大小寫
｜ **SF11** 材料鍵兩套詞表不一致 ｜ **SF12** `budget` 只是埋點

**三條判據**：① 看到「永遠通過」的校驗 ⇒ 查常量是**引用**還是**硬編碼副本**
② 看到 `String` 字段（`ai_id`/`pattern`/`kind`/`behavior`）⇒ 先 grep 代碼分支數，命中 ≤1 = 沒實現
③ 改「看起來是配置項」的字段前 ⇒ 先 grep 消費點；只有「埋點/展示/註釋」⇒ 改了不會有行為變化

### 🆕 2026-09-28（B0）新踩三坑

**① `Vector2` 分量是 32-bit float ⇒ 數值區間下界被抬高，合法值被誤判失敗**
`const R := Vector2(0.40, 0.70)` 的 `R.x` 實為 **0.40000000596**（> 0.4）；`1.8 / 4.5 = 0.400` 被判 `< 下界`。
⇒ **凡存閾值 / 區間 / 精度敏感常量，用 `Array`（64-bit double）或兩個 float 常量，別用 `Vector2`。**
（GDScript 的 `float` 是 64-bit；`Vector2/3`、`Transform` 的 `real_t` 是 32-bit —— 標準版編譯即是如此。）

**② 同一資料目錄混放「不同頂層結構」的表 ⇒ 被錯誤 loader 讀入並噴噪音警告**
`data/skills/` 下放了 `branches.json`（頂層 `{_meta, templates}` 對象），而 `_load_skill_dir` 靠
`_scan_data_files()` 按 `.json` 遞歸枚舉 ⇒ 它被當成一條技能記錄 ⇒ 3 條警告（缺少 id / id 為空 / 缺 display_name）。
⇒ 修法 `SKILL_DIR_SKIP_FILES = ["branches.json"]`。**凡「同目錄多表」場景，loader 都要有顯式排除清單。**

**③ 策劃校驗腳本按「行號」定位工程側硬編碼 ⇒ 上方任何編輯都造成假陰性**
`06-check_special_modes.py` 的 `HARDCODED_8_SITES` 原寫 `self_check.gd:[785,786,787]`；B0 給該檔加了 7 行
⇒ 行號漂到別的代碼，E4 誤報「已修復」（`--repo` 202/0 → 201/1）。
⇒ 已改為**正則內容定位**（命中行號打在輸出裡）。**凡校驗引用工程側某行，一律用內容/正則而非行號。**

### 🆕 2026-09-28（B1）新踩四坑

**① 手繪關的 `count_min` 是「種類權重」，不是刷怪數下限 —— 逐條目之和必須 == `'m'`（P0）**
`level_generator.gd:461-486` 的手繪關路徑**完全不走 RNG**：把各條目 `count_min` **交錯展開成發牌池**，
再按 `'m'` 數**行主序循環發牌** `pool[i % pool.size()]`（`:472-478` 顯式跳過 BOSS ⇒ **池只由非 BOSS 條目構成**）。
⇒ 若 `Σcount_min(非BOSS) ≠ m`，池長與 `m` 不匹配 ⇒ **池尾怪種被系統性少發**。
實測 `ch1_l02`：聲明比例 53/29/18（蜘蛛/蝙蝠/骷髏）⇒ 實發 **44%/36%/19%**（蜘蛛少 9pt、蝙蝠多 7pt）。
⇒ **規則**：程序化關 `Σcount_min ≈ budget × 0.65`（策劃 05 §3.3②，`:220-238` 每條目獨立 `randi_range`）；
**手繪關 `Σcount_min(非BOSS)` 必須恰等於 `m`**。⚠️ 這也意味著手繪關的 `count_max` 只需保證 `m ≤ Σcount_max`。

**② Python `round()` 是銀行家進位 ⇒ 與策劃表差 1**
`round(136.5) == 136`，但策劃表是 **137**。⇒ 對齊策劃表一律用 `floor(x + 0.5)`（半向上）。
（本輪 `Σmin` 校驗被此卡住：`ch1_l06` 得 136 vs 表 137。）

**③ GDScript `"..." % [...]` 中的字面 `%` 必須寫 `%%`**
`"... 装备占比 55% ≈ %d" % [n]` 會拋 `String formatting error: unsupported format character`。
⇒ 寫含百分號的格式化字串時，**字面 `%` 一律寫 `%%`**。（`verify_loot.gd` 預存即有此缺陷。）

**④ 規律採樣會在「所見即所得」的數據裡留下可見指紋**
手繪關 `cells` 是**人看的字串陣列**；用「每 3 格取 1」散布 `'m'` 會留下明顯週期性網格 ⇒ 一眼看出是機器塞的。
⇒ 改**確定性泊松盤散布**（逐級放寬最小間距 6→5→4→3→2.5→2），種子 `zlib.crc32(level_id.encode())`。
⚠️ **不可用 Python `hash()`** —— str hash 每進程隨機化，重跑結果不同。
⇒ 通則：**凡產出「人要讀/要對齊的數據」（手繪圖、策劃表、可視清單），一律避免規律性取樣。**

### 🆕 2026-09-28（B2）新踩一坑

**「分支存在但不可達」—— 比「沒有分支」更隱蔽（P0）**
`_chase_kite` / `_chase_lobber` 都寫了完整三段（後退 / 橫移 / 前進），grep 得到分支數也好看；
但上游 `_tick_chase` **只在 `dist > data.attack_range` 時才呼叫它們**，而全部 5 隻帶
`preferred_range` 的怪都是 `attack_range > preferred_range`
（storm_wisp 150>130｜thunder_herald 130>110｜bone_archer 160>145｜frost_lobber 135>115｜void_priest 145>125）
⇒ `dist > attack_range > pref + tol` ⇒ **「後退」與「橫移」兩支永不執行**，只剩「前進」。
策劃契約明寫「太近则后退」，實際沒實現，而**所有回歸全綠**（因為沒人斷言過它）。
⇒ 通則：**驗「字段有分支」不夠，要驗「分支的進入條件可達」** —— 把上游守衛條件代進去算一遍區間。
（與判據②同源：② 抓「分支數 ≤1」，本坑抓「分支數夠但路徑被上游條件堵死」。）
⇒ 檢測手法：把「分支的 if 條件」與「呼叫點的前置條件」取交集，交集為空 = 死分支。

### 🆕 2026-09-28（B3-1）新踩兩坑

**① 「硬編碼快照斷言」—— 改數據規模即紅（P1）**
把詞綴數 33→48 後，兩處寫死數量的斷言立刻變紅：
`verify_equipment_compare.gd:75` 的 `affixes.size() == 33`、`self_check.gd:403` 的 `affixes.size() != 33`。
它們**看起來是「數據完整性校驗」，實則是「當前快照副本」**——數據一擴容就假紅，
逼著後來者「改斷言讓它綠」（正是 SF4 偽校驗的變體）。
⇒ 通則：**凡 `xxx.size() == N`（字面量）的斷言，先問「N 是設計意圖還是快照」**；
是快照 ⇒ 改為**下界**（`>= 基準`）或**動態取數**（`"%d ..." % size()`）。
⇒ 檢測手法：`grep -rnE "\.size\(\) *(==|!=) *[0-9]+" tools/ scripts/`

**② 「文檔內部矛盾」—— 以**明文裁定**為準，不以工單 note 為準（P0）**
`2-D4` 的 note 寫「修掉 A4 通用池混入 `min_rarity>=3` 詞綴」，
但 `02-裝備屬性.md` **§1.5 明文裁定**「`add_skill_level` 保留現狀」，並把約束 C3 **降為軟建議**、
驗證腳本改**警告級**（§4.4 C3 降級說明 + §8.3 V4 工單**三處一致**）。
⇒ 通則：**工單 note 是摘要，設計文檔的「裁定」段才是權威**；兩者衝突時先找 `裁定` / `拍板` / `降級` 字樣。
⇒ 本次落地：**數據不動**，改 `02-check_affix_pool.py` 新增 `warn()`、A4 由 `check` 改 `warn`（輸出 `[WARN]`，不計失敗）。

---

## ⚠️⚠️ 素材加載【兩條互不相通的路徑】
| 路徑 | 機制 | 適用 | 判斷依據 |
|---|---|---|---|
| **A · UISkin 表驅動** | `ui_skin.gd` 的 `TEX` 字典（**245 條**）顯式登記 | UI 框架件（面板/按鈕/**稀有度邊框**/背景/圖標） | **是否在 TEX 表** |
| **B · 數據驅動直載** | `EquipmentData.icon_path` / `SetData.emblem_path` → `ContentLoader.load_icon()` | 裝備圖標、套裝徽記 | **是否被 `*.json` 引用** |

- **通則**：判斷素材狀態須走完「**素材存在? → 誰登記? → 誰加載? → 誰渲染?**」四步（曾三連誤判）
- ⚠️ **稀有度邊框是 `slot_*` 系列**（`assets/ui/quest/slot_*_48.png`，8 檔齊全），**不在** `ui/pixel/`；
  `ui_skin.gd:127-136` 的 `RARITY_SLOT` 是唯一映射；`:123` 警告「檔名不等於稀有度語義」——
  `slot_rare`=魔法蓝 / `slot_epic`=稀有黄 / `slot_legend`=史诗紫 / `slot_orange`=神话红
- ⚠️ `assets/ui/pixel/rarity_*_48.png`（5 張）**零引用的歷史殘留**

### ⚠️ 已知「生成但沒人消費」清單（主線①病根）
- **套裝徽記**：素材/`sets.json`/`SetData`/`ConfigLoader:453` 全通 → **無 UI 渲染點** ⇒ 3 張白做（工單 `2-L15`）
- **傳奇特效 / 套裝 `effect_id`**：31 條特效 + 6 個 `effect_id` 定義完整但生產代碼零調用（`3-K1`–`K10`）
- **BOSS 技能** `bone_slam`/`fireball` 被 `bosses.json` 引用，但 `_cast_boss_skill` 只做 `has_summon`/`has_aoe` 兩閘門 ⇒ 死數據（`5-W5-5`）
- **I1 臨時增益 UI** / **D3 分支圖標**：素材已備、系統未實作

---

## ⚠️ 數值【易踩坑項】（完整数值见策划案 04/05/06）

- ⚠️ **双等级勿混**：账号级（持久 1–20）`180×L^1.6`（`account_level.gd:24-33`）｜局内级（出关清零 1–10）`20×L^1.4`（`run_progression.gd:31-32`）
  ⇒ **关卡 `reward_xp` 走账号级**（`level_scene.gd:1361-1370`）；**怪物 `base_xp` 走局内级**（`:901`）
- ⚠️ **註釋塊 `game_constants.gd:462-476` 仍寫舊值**（1.284/1.218、L20 HP 11,635），**B1 後實值已為 `1.12/1.12`**
  ⇒ 改這批時**註釋塊與 `self_check` 必須一起改**（屬 B6 `4-W5-a/b/e`）；⚠️ `monsters.json` 字段名是 **`damage_scale`**（非 dmg_scale）
- ⚠️ **`total_monster_budget` 只是埋點，不驅動刷怪**。真刷怪數 = `Σ randi_range(count_min,count_max)`（`level_generator.gd:478-485`）；
  手繪關 = `'m'` 數（`:388-390`）；唯一消費點是埋點（`level_scene.gd:411`）
  ⇒ 只改 `budget` = 「報表好看、時長不變」的假修復 ⇒ **改 `budget` 必須同批改 `Σcount_max`（及手繪關 `Σcount_min==m`）**
  ✅ **B1（`4-W2`）已如此落地**：20 關 `budget` 重排 ⇒ 同步等比縮放 `count_*` + 重畫 4 手繪關 `'m'` + 同步
  `verify_polish9x`/`verify_metrics` 斷言（⚠️ 這兩支有 budget/曲線斷言，**不同步必紅**）
  ⚠️ 歷史狀態（B1 前）：**17/20 關 `budget ≠ Σcount_max`**
- ⚠️ **手繪關卡完全不走 RNG**；`'m'` 數不得超該關 `Σcount_max`（`level_generator.gd:385-390`）⇒ 超了整關不可玩
  🔴 **且 `Σcount_min(非BOSS)` 必須恰等於 `'m'`**（`count_min` 在手繪關是**發牌池的種類權重**，見下方 B1 新坑①）⇒ 不等則池尾怪種被系統性少發
  圖例 `#`牆 `.`地 `o`障 `@`玩家 `m`雜兵 `e`精英 `B`BOSS `p`拾取
- ⚠️ **難度星級**：NM1=0…NM5=4，**沒有 0 星檔** ⇒ 亮燈數 = `clampi(tier,0,4)+1`；
  `verify_ui_assets.gd:348` 斷言「5 顆已建立」；該腳本**無**亮燈數斷言 ⇒ 改對了回歸照樣全綠，**必須真渲染自查**
- ⚠️ **詞綴池不需要 `slot`/`rarity` 字段**；部位過濾在 `AffixData.allowed_slots`+`fits_slot()`（`affix_data.gd:93`）；
  **池不區分前後綴**（由 `_pick_weighted(..., position, ...)` 過濾）；傳奇特效**有回退**（`affix_roller.gd:83-88`）不是死鉤子
- ⚠️ **裝備結算四個死鉤子**：`elemental_damage`（`compute_hit` 第 5 形參在 `skill_controller.gd:168`/`player_controller.gd:945` **硬編碼 0.0`）｜
  `armor_penetration`（詞綴產出它，管線只讀 `armor_pierce`，`:171`/`:946`）｜
  `skill_level`（① `SkillData` 無 level ② `stat_calculator` 白名單不含 ③ `:161` 用裸 `data.multiplier`）｜
  `cooldown_reduction`/`skill_cost_reduction`（`:116` 裸賦 `_cooldowns[id]`；`:113` 裸扣）
- ⚠️ **敌人 AI / 精靈契约**：`enemy_base.gd` 只有 `move_and_slide()`（`:745`），**無 `NavigationAgent2D`** ⇒ 直線追人+沿牆滑行
  ⇒ **「出生點合法」≠「怪追得到人」**。層位：敵 `layer=3/mask=3`、玩家 `layer=2/mask=1`、地形 `layer=1/mask=0`；
  Godot 配對**雙向任一命中即交互** ⇒ 只改敵人 `mask` 去不掉敵人互卡
  命名 **`char_<id>_<action>_<dir>_<NN>.png`**，`NN` 從 `01` 起、**遇缺即停**（不可跳號）
  `PACK_ACTIONS`（`:496`）**不含 `cast`**（A2 已加）；`death`/`die` 並列但**素材只有 `die`** ⇒ `death` 冗餘（`5-W5-11`）
  `PACK_DIRS` 聲明 8 方向、**素材只有 4**（n/e/s/w）；`PACK_MAX_FRAMES=8`；fps 硬編碼 `12.0`
  怪物 **84 幀**（idle4+walk4+attack4+hurt3+die6=21 ×4 方向）；玩家三職業各 **71 幀**
  ⇒ 「轉向尷尬」根因：`resolve_clip` 缺失方向硬回退首幀 + `_apply_facing()` 左右翻轉**只在 `_clips.is_empty()` 時生效**
  `PlayerController.art_id` **須在 `add_child()` 前注入**；`level_scene._player_art_id_from_class()` 依 `class_id` 注入
  ⚠️ `assets/sprites/enemies/*.png`（128/256）是**舊素材**，與 `pack/creatures` 並存

---

## ✅ 已拍板結論（跨步 · 明细见策划案 04/05/06）

**決策明細一律見 `04/05/06-*.md` 與對應 JSON；此處只留「決策 + 工程衝擊」。**

### 第四步 路線 A（提預算）
- **根因**：GDD v1.8 數值框架圍繞 **269 怪/關**設計，工程側實際跑 **60 怪/關**（POC）⇒ 五處失衡同源
- **方案**：預算 `1,199→5,660`｜關卡 XP 不動 ⇒ 落點仍 **L19**｜**賬號上限 60→20**（`4-W10`）｜`recommended_player_level` 1…38→5…20（`4-W11`）⇒ 落差 **恆定 +1**｜**怪物成長率 1.22/1.16 → 1.12/1.12**｜iLvl 掉落改 `clamp(怪等級±三角抖動, 下限 怪等級-2, 上限 max(怪等級, 玩家等級))`
- 🔴 **機械事實**：**提預算無法修落差**（關卡 `reward_xp` 是賬號 XP 唯一來源）⇒ **W2+W10+W11 必須同批**（C2）
  ⇒ 通則：**改任何「產出類」數值前，先確認它流向哪個等級體系**
- 📌 `ratio = 被擊殺所需擊數 ÷ 擊殺一隻怪所需擊數`（健康 **1.0–3.0**；裸裝口徑）
- ✅ **B1 已落地（2026-09-28）**：成長率 `1.12/1.12`（同值⇒相對強度恆定）｜賬號上限 `20`｜20 關 `budget` 合計 `5,660` + `rec` `5…20`｜4 手繪關 `'m'` 重畫｜iLvl clamp+三角抖動 ⇒ 預測 ratio **1.11–3.19 單調緩降**（明細見 `memory/2026-09-28.md` §七）
- ⚠️ 用戶原話「上限 22」但 XP 只夠 **L19** ⇒ 按 **20** 落地；替代方案 = 怪物擊殺 XP 的 15–25% 接入賬號級（05 §3.1，待選）

### 第五步（怪物·關卡·BOSS）
- **五處結構性缺口**：① `ai_id` **零實現**（定義 6 種、代碼 0 分支 ⇒ 16 隻怪行為一致）② 等級覆蓋塌縮（L17–20 只剩 `frozen_husk`；精英 L1–4=0 但 l01–l04 `elite_count`=2/2/2/3 ⇒ 9 槽位刷不出）③ BOSS 技能半數死數據 ④ 目標類型 6 定義 4 實現 ⑤ 地圖形態單一（`ch1_l03`/`l04` layout 空）
- ✅ **D1–D5 已拍板（全取推薦值）**：D1 `ai_id` 6 種**一次做全**（複用 `move_and_slide`+`AOE_TELEGRAPH_TIME`，不引尋路）｜D2 **改 `count_*`**（不動代碼）、`5-W5-12` 降 P3 不執行｜D3 怪物 **16→24**（**素材已交付 G1**）｜D4 **不新增 BOSS**，改做召喚流 vs 法術流差異化｜D5 `survive` 3 關 + `reach_exit` 2 關
  ⇒ 權威副本 `05-monsters.json.decisions_2026_09_24`；新增 9 字段（`preferred_range` 最關鍵）
  ⚠️ `hp_scale`/`dmg_scale` 待驗證：現值在舊成長率下標定，W1 後 L20 怪 HP 只剩 ~19% ⇒ 建議 `hp_scale ×1.3`/`dmg_scale ×0.9` 試跑

### 第六步（特殊玩法，15 項全關）
- S1 塔 1 + 深淵 3 ｜ S2 30 層（1–15 普通票/16–30 高級鑰匙）｜ S3 每 5 層台階、第 5 層二階段 BOSS（保持 D4 不變，用場地變化區分）
- S4 死亡保留/逐層可選帶出/自選已解鎖層 ｜ S5 固定 `layout.seed=6000+layer`（**不可與 `layout.cells` 並存**）
- S6 3 副本 × 3 房間；票 ×2/×3/鑰匙 ×1；**無次數限制** ｜ S7 **18 條**專屬詞綴（塔 6 + 深淵 4×3）｜ S8 通關 +1 普通票 / BOSS 關 +1 高級鑰匙 / 精英 15% ｜ S9 關卡內商店加門票（低機率）；據點商人暫不做
- S10 門票落點 = **新增 `save_data.tickets` 字典**（拒絕塞 `materials`/`consumables`）｜ S11 BOSS 真二階段：`thresholds=[0.6]`、2 招→4 招、`phase_damage_mult=[1.0,1.4]`、場地=火環+縮場｜ S12 **稀有度 8→10**（`SPECIAL_ABYSS=8`/`SPECIAL_TOWER=9`）
- Q-a 特殊檔**不吃**越級懲罰（補顯式守衛）｜ Q-b 特殊裝**可分解** ⇒ +2 專屬材料，**唯一性 append-only 不釋放**｜ Q-c **要**強化 + **半重鑄**（鎖 ≤4/重抽 ≤3），獨立 `special_reroll_controller`
- ⚠️ **S10 同批五改**：`create_new`/`to_dict`/`from_dict`/`migrate` 加 `4:` 分支/**`SAVE_VERSION` 4→5**；連帶 `tower_progress`
- ⚠️ **S12 衝擊**：① **15 個常量數組擴容** ② 3 張掉落表 8→10 位（目標 `[77.90,17.50,3.50,0.45,0.05,0.02,0.40,0.01,0.14,0.03]`，**橙 0.05 硬約束不變**）③ 62 底材無 8/9 檔 ⇒ 空池 ④ 3 處硬編碼 8：`self_check.gd:785-787`/`verify_loot_tables.gd:85`/`verify_ui_assets.gd:139` ⑤ `run_shop.RARITY_PRICE` 無新檔 key ⇒ 賤賣 10 金 ⑥ 不可逆
- ⚠️ **Q-b/Q-c 材料 5→7 鍵**（+`abyss_shard`/`tower_sigil`）需同步 `MaterialBag` + `hub.gd:53-58 MATERIAL_KEY_MAP`（現 4 鍵）+ `hub.gd:181-191 _refresh_status()`；**漏一處 ⇒ 材料持有但界面不顯示**
  🔴 特殊檔**不可**加進 `mythic_reroll_controller` 允許列表（會洗掉專屬詞綴）⇒ 顯式排除 8/9
  🔴 **UI 是本項最大新增**：半重鑄面板 = 7 詞綴槽 + 鎖定開關 + 上限 4 校驗
- ⚠️ **S11 工程面**：`BossPhaseController.validate()` 硬斷言 3/4/4 ⇒ 只改 JSON 不改 `.gd` 靜默失敗；`verify_boss63.gd` A–G **18 處需重寫**（B 組 `:71` 在 0.6 閾值下**語義反轉**，須逐條重算）；🆕 硬約束 **火環 `R_inner ≥` 縮場 `R_arena`**
- ✅ 第五步跨步修訂**用戶已接受回改**，但**不動第五步文件**（留歷史快照），在第七步做「跨步修訂表」

---

## 素材開發線（✅ 2026-09-28 收線）
- 產線 `deliverables/gstack/素材開發/`：`ASSET_MANIFEST.json`(v7) ｜ `README.md`（進度與踩坑全紀錄）
- **done 25 批 / BLOCKED 0**：A1 idle / A2 cast / A3 hurt / A4 death / D1–D4 圖標 / E1–E4 / F1–F3 / G1 新怪 / B1 召喚
- **G1**：8 種新怪 **672 幀**（唯一 AI 出圖批次，32 張 ≈160–320 credits）｜**B1**：召喚 2 隻 168 幀
- **H1 重新分類**：不是素材批次 ⇒ 4 種地圖形態 = `layout.pattern` 欄位（`rooms`/`corridor`/`arena`/`ring`），**屬工程工單**（`level_generator.gd` 小改）；未來第四群系拍板 = **swamp 毒沼**（未排）
- 🔴 **摳底是唯一真難點**：AI 給洋紅漸層底 + 黑陰影 + 誤畫色塊 ⇒ 三方案全推翻，定案 = **相鄰差泛洪（`_flood_from_border`，th=30）+ 純底色補挖（距邊緣中位色 <50）**（`g1_postprocess.py::key_bg`）
- ⚠️ **4 方向獨立出圖會風格漂移** ⇒ 必須數量化驗收，不能憑目視
- ⚠️ **匯入變通**：Godot 編輯器寫快取「先寫 `.tmp` 再 rename」在本工作區**必然失敗**（`WinError 5`，外部行程鎖檔）
  ⇒ 解法 = 複製到工作區外跑 `--headless --editor --quit`，再把新 `.import`/`ctex` 搬回
  ⚠️ 搬回中斷會留下 **0 byte `.import`** ⇒ 圖標靜默消失；**搬完必掃 `<50 bytes` 的 `.import`**
- 舊素材隔離區 `deliverables/_quarantine_2026-09-24/`（**移動非刪除**）：`assets/characters`(426)/`backgrounds`(8)/`weapons`(20)/`armor`(12)/`monsters`(38)/`策划案/art_test`(53)
- ⚠️ **未隔離**：`assets/anim/`(80，附錄A 定為參考風格稿)、`assets/previews/`(14)、`assets/ui/pixel/rarity_*`(5，實測被 build_overview/scene_gen 用到)

---

## 📦 當前可運行包（2026-09-23，**已落後於工作區**）
`game\build\七傳說.exe` ｜ 128,723,832 B ｜ MD5 `1078e026f6da49b7129b0e216e0f73fb`（含 ch1_l05/l06 P0 修復；舊包 `build/_prev/`）

## ⚠️ 远程仓库 / git 铁律
- `origin` = `github.com/fyangOvO/fyangOvO.git` ✅ **推送一律 `git push origin main`**；`github.com/fyangOvO/game.git` ❌ 不再管
- Git LFS 已啟用；憑據已緩存；本地 `main` 根提交 `a8c6f6c` ⇒ 純快進無需強推
- **禁用**：`stash`（尤其 `-u`/`-a`）、`gc`、`prune`、`reset`、`checkout`、`clean`、`read-tree`、`filter-branch`
  **僅允許** `add`/`commit`/`status`/`log`/`diff`（2026-09-20 事故：`stash push -u` 被 SIGTERM 中斷 ⇒ `.git` 整體進回收站）
- 测基线「複製檔案到外部臨時目錄」；清理殘留 `mv` 到 `.workbuddy-ai/trash/<日期>-<原因>/`，**不以 `rm` 直刪**
- 备份 `.workbuddy-ai/backups/git-<日期>/.git`；已知殘留：缺失 tree `0e21f118`，**決定不修**

---

## 工具链 / 打包

### ⚠️ 打包回歸三個坑（2026-09-23 實測）
**① `APPDATA` 空串 ⇒ 導出失敗 + 靜默漏清存檔**（本 shell 實測為空）：Godot 把數據目錄解析成 `./Godot/`
```bash
cd D:/七傳說/game && APPDATA='C:\Users\11265\AppData\Roaming' python tools/package_demo.py --backup
```
**② `run_regression.py` 的 `NO-RESULT` 是誤報**：正則不認繁體「全部通過」與「27 通過 / 0 失敗」
⇒ 5 腳本被判空轉（`verify_class_select`/`verify_consumable`/`verify_equip_panel`/`verify_hud`/`verify_panel_unify`），
實查日誌末行皆全綠。⇒ **見 `NO-RESULT` 先讀 `%TEMP%\ge_regress_fail_<name>.log` 再定性**
**③ 回歸斷言與實現已漂移（非玩法 bug）**
| 測試 | 寫死 | 實際 |
|---|---|---|
| `verify_fix85` | 技能 8 | **14**（B0 後 36） |
| `verify_skill_panel` | `save_version == 3` | `SAVE_VERSION = 4`（S10 後 **5**） |
| `self_check`/`verify_settings` | 音效 9 條 | **10**（8E 加 `boss_roar`） |
| `self_check` | 怪物 L20 HP≈11635 / DMG≈237.83 | B0 時實為 **HP 4404.2 / DMG 94.12**；⚠️ **B1 改成長率 1.12 後再降（約 867 / 48，待 `4-W5-e` 實跑取證重算）** |

### 其他
- Python：`C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe`（系統 `python`/`/tmp` 不可用）
- 特效系統數據驅動：`data/fx.json`（**33 已註冊**）+ `assets/fx/*.png` + `tools/fx_build_sheets.py` ⇒ **加 json 條目 + 放 PNG 即可擴增，不改代碼**。
  4 個游離貼圖未註冊：`fx_{fire,frost,slash,thunder}_px96`（皆 96×96 單幀，**不符「橫向序列幀」契約**）
- **aigei.com 已上登錄牆**（無 `data-original`）⇒ 外部免費素材改走 **CC0 源**
- **臨時目錄**：`deliverables/gstack/策划案/_tmp/`（用完 `mv` 到 trash，不 `rm`）
- 驗證探針（`game/tools/`）：`probe_tex`（TEX 載入）/`probe_fx`（fx 表契約）/`probe_clips`（精靈幀集）/`probe_level`（關卡體檢）
