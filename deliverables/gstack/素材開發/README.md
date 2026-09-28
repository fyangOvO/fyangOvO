# 七傳說 · 素材開發（依 `策划案/07-开发总表.md` §5 素材總帳）

> 建立：2026-09-24 ｜ 目標引擎：`D:/七傳說/game`（Godot 4.7.2）

## 一、這個目錄是什麼

把總表的**素材總帳**落成**可執行的產線**。總表 §5 是「核算」，本目錄是「下單與交貨」。

| 檔案 | 用途 |
|---|---|
| `ASSET_MANIFEST_v2.json` | **開發總清單**（28 批 / 1573 新檔）：每批的檔名契約、尺寸、色板路線、落點、方法、優先級、來源章節 |
| `build_manifest.py` | 清單產生器（id 清單一律回讀策劃案 JSON，不手抄） |
| `gen_player_idle.py` | **A1 批次產線**：玩家 idle 8 方向 |
| `quarantine_orphans.py` | 舊素材隔離（移動而非刪除） |
| `preview_A1_idle_8dir.png` | 三職業 × 8 方向交付預覽 |
| `preview_A1_breathing.png` | 呼吸動畫 + 胸線接縫檢查 |

## 二、已完成批次

### P1 批次（2026-09-24）

| 批 | 內容 | 張/幀 | 尺寸 | 檔名 | 落點 |
|---|---|---|---|---|---|
| **A3** | 玩家 hurt 8 方向 | **42**（+6 既有 = 48） | 192×192 | `char_<class>_hurt_<dir>_<NN>.png` | `assets/pack/creatures/<class>/` |
| **A4** | 玩家 death 8 方向 | **84**（+12 既有 = 96） | 192×192 | `char_<class>_death_<dir>_<NN>.png` | 同上 |
| **D1** | 技能圖標（**一技能一圖標**） | **32**（+4 既有 = 36） | 48×48 | `skill_icon_<skill_id>_48.png` | `assets/ui/quest/` |
| **D2** | 符文圖標 | **24** | 32×32 | `rune_icon_<short>_32.png` | `assets/ui/quest/` |
| **E3** | 系統標識 3 + 材料 3 | **5** | 48×48 / 32×32 | `forge_icon_48.png` … `crystal_reroll_32.png` | `assets/ui/quest/` |
| **E2** | 固定檔位裝備獨立圖標 | **5** | 48×48 | `equip_<base_id>_48.png` | `assets/icons/equipment/` |

產線：`gen_player_hurt_death.py`（A3/A4）、`gen_icons_p1.py`（D1/D2/E2/E3）；全部 **零 AI 成本**。

**A3/A4 的衍生方式（依附錄A §A.3 的幀序設計）**
- `hurt`：① 後仰 → ② 回復中。**位移方向與受擊方向一致**（沿朝向反向水平位移 ±2px）+ 頭後傾。
- `death`：① 後仰 → ② 跪倒（壓縮 0.58）→ ③ 側倒（0.38）→ ④ 躺地。
  躺地幀**有水平分量 → 精確 90° 旋轉**（`np.rot90`，無插值，不糊像素）；純 `n`/`s` → 前縮壓扁（趴倒）。
- ⚠️ 品質定位：**衍生 placeholder**，能修掉「所有方向都播正面受擊/死亡」的硬傷，但演出細節（膝蓋彎曲、手撐地）仍建議後期手繪。

**補上的缺口（原本缺的、我一併修掉）**
1. `game_constants.gd` 的 `SKILL_ICON` 原是「**12 技能共用 4 張通用圖標**」（cleave/spin_slash/power_strike 都指向 `skill_icon_slash`）。
   已改為 **36 技能各自一圖**（附錄A §A.8 的「一技能一圖標」原則）。
2. `ui_skin.gd` 的 `TEX` 表新增 **68 條**（32 技能 + 24 符文 + 3 系統 + 3 材料），
   並補 `UISkin.skill_icon(id)` / `UISkin.rune_icon(rune_id)` 兩個取用函式。
   ⚠️ `skill_icon()` 內部走 `GameConstants.SKILL_ICON`，那是唯一權威（角色選擇面板與局內技能欄同源）。

### 已交付的 P0 四項
`idle` 8 方向（A1，93 幀）· `cast` 8 方向（A2，96 幀）· 詞綴圖標 48（E1）· 元素圖標 11（F1/F2）
### A1 · 玩家 idle 8 方向（總表 §5.4 **P0**）

**交付 93 個新 PNG**（3 職業 × 31；`idle_s_01` 為既有幀保留）→ 落點 `game/assets/pack/creatures/{warrior,archer,mage}/`
- 檔名：`char_<class>_idle_<dir>_<NN>.png`
- 規格：192×192、腳底 y=191、alpha 二值、48 色
- 素材來源：**不重畫**。s 方向由既有 `idle_s_01` 衍生；其餘 7 方向以 `walk_<dir>_02`（並腳幀）為基準
- 幀序（依附錄A §A.3）：① 中立 → ② 吸氣 → ③ 中立 → ④ 吐氣

**兩個與策劃案不同的工程決策**（已記入清單，不是擅自偏離）：

1. **切分線取「胸線以上」而非腰線**。這套素材的劍垂到地面，按腰線切會把劍身切成兩段（斷劍／拉長）。切在胸線以上只動「頭＋肩」，劍與下半身完全不動。
2. **幅度預設 ±2px**（`--amp` 可調）。遊戲內 `DNF_GAME_SCALE = 0.25` ⇒ 4:1 降採樣，**1px 起伏只有 0.25 螢幕像素**。附錄A 的「1–2px」若指 192 畫布，實機等於沒動。

**驗證**：Godot 匯入成功（353 個 idle `.import` 生成）；`verify_anim` **0 失敗 / exit=0 / 全綠**。

### A2 · 玩家 cast 8 方向（總表 §5.4 **P0**）

**交付 96 個新 PNG**（3 職業 × 8 方向 × 4 幀）→ 同上落點
- 檔名：`char_<class>_cast_<dir>_<NN>.png`
- 幀序（附錄A §A.3）：① 起手 → ② 蓄力 → ③ **釋放（向前推）** → ④ 收勢

**⚠️ 前置的代碼改動（已執行）**：`enemy_base.gd:496` 的 `PACK_ACTIONS` 加上 `"cast"`。
不加這 1 行，上面 96 個檔案**一個都不會被載入**（實測 `PACK_ACTIONS` 只有定義與探測迴圈兩處使用，**零斷言引用**，故改動安全）。

**素材來源**：既有 `char_<class>_attack_<dir>_<NN>.png`（不重畫）。逐職業差異是關鍵：

| 職業 | attack 序列的性質 | ③ 釋放幀取用 |
|---|---|---|
| 法師 | 聚能 → 舉杖 → **魔法彈前飛** → 收招 | `attack_03`（本身即施法釋放） |
| 弓手 | 持弓 → 拉弓 → **放箭帶箭矢** → 收弓 | `attack_03`（本身即蓄力釋放） |
| 戰士 | 舉劍 → 前指 → **橫斬帶白色刀弧** → 收招 | **`attack_02`**（持劍前指，**刻意避開帶刀弧的 03**） |

⇒ 戰士的 cast 不再出現橫斬刀弧，符合附錄A「attack 是橫向劈砍，cast 是向前推」的分野。

**三種變換**：`lean`（胸線以上垂直位移：蓄力上升 / 釋放前傾下壓 ±2px）、
`push`（釋放幀沿朝向水平前送 3px，腳底 y 不變）、戰士的來源幀替換。

**已知瑕疵（繼承自原包，非本次產生）**：`mage/char_mage_attack_n_04.png` 的腳底是 **y=190**（其餘 400/402 幀都是 191）。
A2 的 `char_mage_cast_n_04.png` 從它衍生，故同樣是 190。要修的話是「把這 2 張下移 1px」。

### ✅ 2026-09-24 · 匯入已完成（用「工作區外匯入」變通）

**問題**：Godot 編輯器寫快取是「先寫 `.tmp` 再 rename」，而 **該 rename 在本工作區必然失敗**
（用 Python 對 `.godot/global_script_class_cache.cfg` 做 `os.replace` 也回 `WinError 5`
⇒ **檔案被外部行程鎖住**，最可能是 WorkBuddy 桌面版的檔案監控），
所以編輯器永遠卡在 `[16%] 正在載入全域類別名稱`。

**解法（已執行，可重現）**：把專案複製到工作區外 → 在那邊跑編輯器 → 把產物搬回來。

```bash
# 1) 複製到工作區外（含 .godot，這樣只需匯入新增的）
cp -r "D:/七傳說/game/." "$TEMP/qcs_import/"
# 2) 在複製區跑匯入（會印到 [DONE] loading_editor_layout）
cd "$TEMP/qcs_import" && "<Godot>" --headless --editor --quit --path .
# 3) 搬回三樣：新 PNG 的 .import、.godot/imported 的新 ctex/md5、其餘快取
#    （只複製「原專案沒有的」，幂等可重跑）
# 4) 刪掉臨時複製（約 581 MB）
```

**踩坑**：搬回的過程被中斷會留下 **0 byte 的 `.import`** ⇒
`UISkin.texture()` / `ResourceLoader.exists()` 回 null ⇒ 該圖標**靜默消失**。
本次就中了 `elem_poison_24.png.import`（0 byte），已修。**搬完務必掃 `<50 bytes` 的 `.import`**。

**驗證（兩支探針都寫在 `game/tools/`）**：

| 探針 | 實測結果 |
|---|---|
| `probe_cast.tscn` | `warrior/archer/mage` 動作 = `[attack, **cast**, death, hurt, idle, walk]`，**cast 8 方向 × 4 幀** ✓ |
| `probe_icons.tscn` | affix **48/48** · elem **6/6** · resist **5/5** ✓；`resist_physical` 正確回 `null`；尺寸 32×32 / 24×24 正確 ✓ |

### ✅ 2026-09-24 · 詞綴圖標已在 `ui_skin.gd` 的 TEX 表登記（工單 2-L16）

`game/scripts/ui/ui_skin.gd` 的 `TEX` 表新增 **59 條**（48 詞綴 + 6 元素屬性 + 5 抗性），
並補了三個便利函式供代碼側叫用：

```gdscript
UISkin.affix_icon(stat_key)   # 32×32，stat_key 取自 data/affixes/*.json
UISkin.element_icon(key)      # 24×24，physical/fire/cold/lightning/poison/shadow
UISkin.resist_icon(key)       # 24×24，⚠️ physical 無圖標（走護甲）⇒ 回 null
```

**驗證**：`parse_all` 222 個 `.gd` 全綠；`verify_ui` / `verify_ui_assets` / `verify_ui71` 全綠；
全套回歸與基線一致（同樣 3 項既有待修缺口，無新增失敗）。

## 三、怎麼用

```bash
# 重生 A1（改呼吸幅度）
python gen_player_idle.py --amp 4      # 想更明顯
python gen_player_idle.py --amp 1      # 想完全照策劃案

# 重生清單
python build_manifest.py

# Godot 匯入新 PNG（必須，否則 .import 不會生成）
"<Godot>" --headless --editor --quit --path D:/七傳說/game

# 驗證
python game/tools/run_regression.py --only verify_anim --no-preflight
```

> ⚠️ 新檔一律要跑一次 `--editor --quit` 產生 `.import`，否則 Godot 不認。

## 四、已拍板規格（2026-09-24，柳絮裁定）

| # | 問題 | **裁定** | 落地 |
|---|---|---|---|
| 1 | 總表寫「單精靈 ≤24 色」vs 實際 48 色 | **按 48 色做**（精細優先） | A1/A2 皆 47–48 色 |
| 2 | 召喚物 32×32 vs 既有怪物 128×128 | **按 128×128** | 已寫入清單 B1 批次 |
| 3 | `cast` 不在 `PACK_ACTIONS` | **要改**（1 行代碼） | ✅ 已改 `enemy_base.gd:496` |
| 4 | 44 色 / 48 色的適用範圍 | **按 `pixel_pipeline/README.md §二` 兩路線** | 角色/怪物/武器/裝備＝48 色；fx/背景/UI/圖標＝44 色 |

> ⚠️ 總表 §5.5#10 「單精靈 ≤24 色」與 §5.5#7 「像素必須 ∈ `PALETTE_ALL`」兩條，
> 與現行素材包（角色實測 48 色、0 色落 44 色內）不符。**建議回頭修總表這兩行**，以免後續再被誤導。

## 五、已隔離的舊素材（移動非刪除，可回復）

隔離區：`deliverables/_quarantine_2026-09-24/`，記錄 `_quarantine_log.json` / `_oneoff_tools.txt`

| 項目 | 檔數 | 依據 |
|---|---|---|
| `game/assets/characters/` | 426 | 與 `pack/creatures/{warrior,archer,mage}` **100% 位元組相同**；且不在任何 runtime 載入鏈 |
| `game/assets/backgrounds/` | 8 | 與 `assets/ui/quest/backdrops/` **100% 位元組相同** |
| `game/assets/weapons/` | 20 | 策劃案 02 附錄B **自己標為「与装备图标重复」**；runtime 零引用 |
| `game/assets/armor/` | 12 | 同上；`equip_*` 與活躍目錄同名但內容不同（舊版） |
| `game/assets/monsters/` | 38 | 192×192 舊怪物圖，已被 `pack/creatures/`（128/256 畫布）取代 |
| `策划案/art_test/` | 53 | 2026-09-24 風格測試 scratch |

**未隔離（我判定不該刪，附理由）**：
- `assets/anim/`(80) — 策劃案附錄A §A.7 明寫「**作為參考風格稿 ✅ 推薦**」
- `assets/previews/`(14) — `PACK_OVERVIEW.md` 引用的文檔圖
- `assets/ui/pixel/rarity_*_48.png`(5) — 策劃案說「全項目零引用」，**但實測被 `build_overview.py` / `scene_gen.py` 用到** ⇒ 不刪（策劃案這條寫得不準）

### ⚠️ 未能執行：`game/tools/` 的除錯殘骸清理

已用逐檔 grep 驗證出 **零外部引用** 的除錯/一次性腳本清單：
`_diag_kb` · `debug_screenshot` · `debug_skill` · `diag_aoe` · `diag_player_children` · `sample_pixels` ·
`tiles_{diag,search,credits,preview}.py` · `_audit_report.txt` · `__pycache__/`
（`fake_mana_target` / `fake_skill_ctrl` **有引用，保留**。）

**但本 session 動不了**：`game/` 內的個別檔案被外部行程鎖住，`os.rename` / `os.remove`
一律回 `WinError 5`（實測連同目錄改名都失敗；與 `.godot` 的 `.tmp` 改名失敗同源）。
⇒ 已備好可執行腳本 **`cleanup_oneoff_tools.py`**，請在 **WorkBuddy 之外** 執行：

```bash
python cleanup_oneoff_tools.py --dry-run   # 先看清單
python cleanup_oneoff_tools.py            # 移到隔離區（可回復）
```

## 六、下一批建議（總表 §5.4 剩餘項）

已交付的 P0 四項：`idle` 8 方向（A1）、`cast` 8 方向（A2）、詞綴圖標 48（E1）、元素圖標 11（F1/F2）。

### E1 + F1/F2 · UI 圖標（**零 AI 成本，全部 44 色合規**）

| 批次 | 內容 | 張數 | 尺寸 | 檔名 |
|---|---|---|---|---|
| **E1** | 詞綴圖標 | **48** | 32×32 | `affix_<stat_key>_32.png` |
| **F1** | 元素屬性圖標 | **6** | 24×24 | `elem_<key>_24.png` |
| **F2** | 元素抗性圖標 | **5** | 24×24 | `resist_<key>_24.png` |

落點皆為 `game/assets/ui/quest/`。產線：`gen_icons.py`。

**⚠️ 修正清單 v2 的錯誤**：元素圖標我原本寫 48×48，實際規範是 **24×24**
（`03-elements.json` → `naming.element_icon = "elem_<key>_24.png"`）。

**為什麼保證色板合規（結構性保證，非事後檢查）**：全程只畫在「索引畫布」上
（0=透明 1=描邊 2=暗 3=中 4=亮 5=輝光），畫完自動描邊，**最後才用色系把索引映射成 `PALETTE_ALL` 的顏色**。
⇒ 實測 **59/59 張色板外顏色 = 0**、alpha 皆二值。

**驗證**：`verify_ui_assets` + `verify_ui` 全綠（新增檔案不會撞既有的 `EXPECT_TEX` 逐一列舉斷言）。
**✅ 2026-09-24：48 條已在 `ui_skin.gd` 的 `TEX` 表登記**（工單 2-L16 已完成），
並提供 `UISkin.affix_icon()` / `element_icon()` / `resist_icon()`；`probe_icons.tscn` 實測 48/48 + 6/6 + 5/5 全數載入。

### 後續（依總表 §5.4）
- **P1**：玩家 hurt/death 8 方向（168 幀）· 技能圖標 28 張 · 符文圖標 24 張 · 系統標識+材料 6 張 · 稀有裝備圖標 5 張
- **P2**：投射物 5 + 地面區域 5 · 元素異常 3（`ailment_<key>_24.png`）+ 附著層 6（`attach_<key>_32.png`）
- **P3**：增益光環 4 + 元素命中 5 + 召喚法陣 1 · 召喚物 4 隻（一期 224 幀）

---

# 七、2026-09-28 續作（本節為最新狀態）

## 7.0 先修掉的兩件事

### ① 匯入阻塞解除 —— **不再需要「工作區外匯入」**
上一輪 `.godot/global_script_class_cache.cfg` 被外部行程鎖住（Python `os.replace` 也回 `WinError 5`），
導致編輯器卡在 `[16%] 正在載入全域類別名稱`。**2026-09-28 實測鎖已過期**：

```bash
"<Godot>" --headless --editor --quit --path "D:/七傳說/game"    # 直接就地跑，印到 [DONE] 即成功
```

⇒ 第六節那套「複製到工作區外 → 匯入 → 搬回」的變通**只在鎖生效期間需要**；正常情況就地跑即可。
（本輪所有批次：idle/cast/hurt/death、UI 圖標、FX、walk/attack 6 幀，全部就地匯入成功。）

### ② 修復一條我上一輪引入的回歸
`ui_skin.gd` 第 376 行尾端留了一個多餘的反斜線（`return texture(...)\`）——在 GDScript 是**行接續符**，
於是整個 `UISkin` 類別解析失敗，**連帶拖垮 `loot_drop.gd` / `hub.gd` 等 20+ 個引用它的腳本**
（症狀是 `Could not resolve class "UISkin"` 洗版）。已修，`parse_all` 226 個 `.gd` 全綠。

> 教訓：`ui_skin.gd` 這種「被大量腳本引用」的類別，**改完必須立刻跑 `--check-only --script`**，
> 否則一個字元就能讓全專案編譯失敗，而且 `verify_*` 不會告訴你原因。

## 7.1 本輪新增素材（全程序化，**零 AI 成本**）

| 批次 | 內容 | 張/幀 | 尺寸 | 落點 | 消費狀態 |
|---|---|---|---|---|---|
| **F3 + §8.3** | 異常狀態 6 + 附著層 6 + 技能邊框 6 + 專精角標 5 | 23 | 24/32/48/16 | `assets/ui/quest/` | 待接線 |
| **§8.3** | 單元素傷害圖標 6 | 6 | 24×24 | `assets/ui/quest/` | 待接線 |
| **I1（§8.1）** | 臨時增益：神龕 3 + 增益球 5 + 倒計時條 2 | 10 | 32/24/64×6 | `assets/ui/quest/` | ⚠️ **系統未實作** |
| **C1–C5（§A.7）** | 元素命中 5 + 投射物 5 + 地面 5 + 光環 4 + 法陣 1 | 20 | sheet | `assets/fx/` | ✅ **元素命中已接線** |
| **C6（第五步）** | 雷花/咒印/骨擊/落點/傳送門/狂暴 | 6 | sheet | `assets/fx/` | ⚠️ 系統未實作 |
| **A5（§A.4）** | 玩家 walk/attack 4 → **6 幀** | 288 檔（淨增 96） | 192×192 | `pack/creatures/` | ✅ **已通電（探針實測 6 幀）** |
| **D3（§A.8）** | 技能分支圖標 14 模板 × 2 態 | 28 | 32×32 | `assets/ui/quest/` | ⚠️ **分支系統未實作** |

**合計本輪新增 351 個 PNG + 26 張特效 sheet。**

### 各批次的關鍵決策（**偏離直覺但正確**）

**A5 · walk/attack 6 幀**
- **產線會毀資料，已修**：輸出路徑與來源路徑重疊（`idx4` 會蓋掉原始第 4 幀），
  若不先把 4 張來源讀進記憶體，`idx5` 就會讀到被污染的檔。**原始 4 幀已備份**到
  `deliverables/_quarantine_2026-09-24/walk_attack_4f_originals/`（可回復）。
- **walk 用胸線切分、attack 預備/收勢改「整張位移」**：
  attack 的 `a1` 是「劍斜舉過頭」，**任何水平切分線都會切斷劍**（hip 切分實測把劍尾切平）。
  整張位移不會產生斷口；代價是 30 個過渡幀腳底離地 1–2px（= **0.5 螢幕像素**，
  因玩家顯示是 `centered + offset.y=-canvas/2`、`scale=48/canvas` ⇒ **尺寸由畫布決定、不吃 bbox**）。
- ⚠️ **本批的天花板**：從 4 幀衍生只能改出「上身起伏 / 蓄勢 / 慣性」，
  **做不出真正的新抬腳姿**。§A.4 的「抬腳–過渡–落」三段式目前只達成「落–起伏」兩段。

**FX · 命名與契約**
- runtime sheet 的既有慣例是 **特效 id ≡ 檔名 stem**（`hit_spark.png` ↔ `hit_spark`），
  **沒有 `_pxNN` 後綴**——`fx_*_px96` 那 4 張是**產線中間素材**（§A.7 已警告不要當現成素材用）。
- `fx.json` 自校驗必須抓 **三個**色板常量：`PALETTE_ALL = PALETTE_NEUTRAL + PALETTE_ACCENT + PALETTE_RARITY_SEMANTIC`；
  只抓 `PALETTE_ALL = [...]` 會得到 11 色並**誤報 24 張違規**（實測踩過）。

## 7.2 本輪代碼改動（4 處，都有對應驗證）

| # | 檔案 | 改動 | 驗證 |
|---|---|---|---|
| 1 | `scripts/ui/ui_skin.gd` | `TEX` **+67 條**（39 圖標 + 28 分支）；新增 7 個便捷函式（`ailment_icon` / `element_damage_icon` / `attach_layer` / `element_skill_frame` / `element_badge` / `temp_buff_orb` / `temp_buff_shrine`）；修掉行尾反斜線 | `--check-only` 無錯；`probe_tex` **233/233** |
| 2 | `data/fx.json` | effects **7 → 33 條**（C1–C6，含 `frame_w/frame_h/frames/fps/loop/anchor/z/fade`）；原 7 條**一字未動**（已逐條比對）；舊檔備份 `data/fx.json.bak_20260928` | `probe_fx` **33/33**（含表↔檔尺寸契約比對） |
| 3 | `scripts/juice/juice_fx.gd` | `_on_damage_dealt` 的第 4 個參數由 `_element`（被忽略）改為實際使用；新增 `ELEMENT_HIT_FX` 表與 `_spawn_hit_fx(pos, is_crit, element)`，優先序 **暴擊斬弧 ＞ 元素命中 ＞ 通用火花**；物理刻意不進表（§A.7 明講複用 `hit_spark`） | `verify_juice` **0 失敗**；`probe_fx` 實測 5 條接線全部命中 |
| 4 | 3 張 PNG | 修掉**原包既有**的腳底基準偏差（`mage` 的 `attack_n_05/06`、`cast_n_04` 由 y=190 → 191） | 全量掃描：三職業僅這 3 張曾偏離 |

## 7.3 本輪新增的驗證工具（留在 `game/tools/`）

| 工具 | 用途 |
|---|---|
| `probe_tex.tscn` | **通用** TEX 載入探針：傳入邏輯鍵名，逐條回 `OK <尺寸>` / `MISS null`。尺寸期望由檔名尾碼推（支援 `_48` 與 `_256x48`） |
| `probe_fx.tscn` | **特效表契約探針**：檢查 `fx.json` 的 `frame_w × frames` 是否與實際貼圖寬度一致（不一致 ⇒ 播放時取到貼圖外，且**不報錯**），並自檢元素命中接線 |
| `probe_clips.tscn` | 精靈幀集探針：印出 `resolve_character_set(id)` 的全部動作 × 方向 × 幀數 |
| `probe_cast.tscn` / `probe_icons.tscn` | 上一輪的單用途探針（`cast` 動作、59 條圖標），已被上面兩支取代，保留作歷史對照 |

## 7.4 未做與阻塞（**誠實清單**）

| 項 | 狀態 | 原因 |
|---|---|---|
| **D4 狀態圖標 12 張** | ❌ 未做 | 策劃案只寫「buff / debuff 12 張」，**沒有 id 清單**；遊戲 `data/` + `scripts/` 也**沒有 buff/debuff id 體系**（只有 `BUFF_*_CAP` 這類數值上限常量）。憑空造 id ⇒ 必然做出對不上代碼的垃圾檔 |
| **G1 新增怪物 8 種**（672 幀） | ❌ 未做 | **必須 AI 或手繪**（不能從既有 14 怪衍生出新品種），且需先確認「AI 出圖的跨格一致性」這條已知風險願不願意承擔 |
| **B1 召喚物 2 隻**（256 幀） | ❌ 未做 | 同上；且 `summon` 形態在 `skill_controller.gd` 尚未實作 |
| **H1 4 種地圖形態 tileset** | ❌ 未做 | 策劃案明寫「**先定 4 種形態的設計，再談張數**」——無設計無從下手 |
| **E4 套裝徽記** | ✅ 早就存在 | `assets/sprites/items/set_emblem_{frostbite,emberpath,oathkeeper}.png` **已是 48×48**。缺的不是素材，是**消費點**（`set_panel.gd` 的 `_make_set_row()`）＝工單 **L15**，屬工程側 |
| **I1 臨時增益 UI** | ⚠️ 素材已備、系統未實作 | `scripts/` 下無 `temp_buff` / `shrine` 消費點（第四步 §8.1 是設計稿） |
| **D3 分支圖標** | ⚠️ 素材已備、系統未實作 | `skill_controller.gd` 只實作 `SINGLE/AOE/DASH`，**缺 `projectile/ground/summon/buff` 四種形態**；分支系統未落地 |
| **`game/tools/` 除錯殘骸清理** | ❌ 未執行 | 上輪的「零引用」判定方法**有缺陷**：`run_regression.py` 是**動態 glob `verify_*.tscn`**，所以所有 `verify_*` 都顯示「零引用」卻是活的。已改為保守作法，只列清單不動手 |

## 7.5 驗證證據（本輪）

| 檢查 | 結果 |
|---|---|
| `parse_all` | **226 個 `.gd` 全部可解析**（0 parse error） |
| `probe_clips` | 三職業 × 6 動作 × 8 方向；**walk/attack 各 6 幀**、idle/cast/death 各 4、hurt 2 ✓ |
| `probe_tex` | **233 / 233** |
| `probe_fx` | **33 / 33**（含表↔檔尺寸契約）；元素命中接線 5/5 命中 |
| 色板合規 | 本輪 351 PNG + 26 sheet **全部 0 色超出 `PALETTE_ALL`**、alpha 皆二值 |
| 全套回歸 | **與基線完全一致**：`self_check` 3 項（L20 怪物 HP/DMG 數值、音效註冊表）、`verify_skill_panel` 2 項（存檔 v3 遷移）——皆為既有待修缺口，**零新增失敗**；`verify_juice` / `verify_ui` / `verify_ui_assets` / `verify_anim` 全綠 |



---

## 8 · G1 新增怪物 8 種（2026-09-28 完成，**672 幀**）

> 這批是**唯一用 AI 出圖**的批次（其餘皆程序化）。32 張 AI 圖 ≈ 160–320 credits。

### 8.1 交付清單

| 怪物 ID | 中文 | 定位 | 造型 |
|---|---|---|---|
| `void_priest` | 虚空祭司 | shadow **精英** | 虛空秘教祭司 |
| `shade_stalker` | 影袭者 | shadow 普通 | 暗影掠食獸 |
| `storm_wisp` | 雷灵 | lightning 普通 | 雷電精魂 |
| `thunder_herald` | 雷罚使徒 | lightning **精英** | 雷罰重甲使徒 |
| `plague_bearer` | 疫病携者 | poison 普通 | 疫病散播者 |
| `frost_lobber` | 霜爆投手 | cold 普通 | 冰霜投擲怪 |
| `rat_swarm` | 腐鼠群 | physical **精英** | 腐化鼠群 |
| `bone_archer` | 骸骨弓手 | physical 普通 | 持弓骸骨 |

每隻 **84 幀**（4 方向 × idle 4 / walk 4 / attack 4 / hurt 3 / **die 6**），
落點 `game/assets/pack/creatures/<id>/char_<id>_<action>_<dir>_<NN>.png`。

**副作用（正面）**：這批解掉了「元素抗性裝備是廢屬性」的一半 ——
原本只有 fire/cold 有承載怪，現在 **lightning 與 shadow 各有一普通一精英**了。

### 8.2 摳底是這條管線唯一真正的難點（換了 3 種失敗方案）

AI 給的是**洋紅漸層底**，且會在角色下方多畫黑陰影、在角色身上誤畫洋紅塊。
依序試過並**全部推翻**的方案：

| 方案 | 失敗症狀 | 根因 |
|---|---|---|
| Pillow `ImageDraw.floodfill`（四角單點種子） | despill 計數 1788 → **27685**，整張洋紅底留著 | 黑陰影把底**隔斷**，泛洪只填得到外圈（實測只填 **9%**） |
| 「洋紅色相」`R-G>40 且 B-G>40` | `rat_swarm_s` 整張底沒摳掉 | 漸層暗端偏成**深紫紅**（B 不夠高）⇒ 漏判 |
| 「與邊緣中位色的距離」（含自適應） | 輸出變**灰色剪影**（角色被當成底） | 底色是中亮洋紅 `(175,47,111)` 時，**灰鼠 `#929483` 只差 99.4** ⇒ 能覆蓋漸層的門檻必然咬掉整隻老鼠 |

**定案＝兩層互補（`g1_postprocess.py::key_bg`）**
1. **相鄰差泛洪** `_flood_from_border`：/4 NEAREST 縮圖 + numpy roll 迭代（32 張約 54s）。
   底色靠「相鄰色差小」自己串起來，角色靠「**邊界色差大**」自然斷開。
   門檻 `th=30`（相鄰像素 L1 差）；實測 th 15→40 對結果幾乎無影響 ⇒ 不必在此調參。
2. **純底色補挖**：與邊緣中位色距離 < **50**。處理泛洪**進不去**的封閉洞
   （`bone_archer` 弓弦圍出的區域）、腳下殘帶、AI 誤畫在角色上的洋紅（曾達 48459 px）。
   **50 這個值很關鍵**：`void_priest` 紫袍距底色 ≈223、權杖亮紫球 ≈85，才都在安全區。

### 8.3 4 方向獨立出圖的風格漂移（**要用數量化驗收，不能憑目視**）

本輪最大的教訓：我一度「目視判斷」`thunder_herald` 的 n/w 偏紫，於是把提示詞寫成
`slate blue-grey` ⇒ 結果 n/w 變藍灰，但 `s`/`e` 其實是**深青綠**，**反而更不一致**。

實測（飽和像素的主色相中位數）：

| 方向 | 修正前 | 修正後 |
|---|---|---|
| `s` | 64° | 64° |
| `e` | 99° | 120° |
| `n` | **159°**（青） | 92° ✓ |
| `w` | **146°**（青） | 110–146° ✓ |

⇒ **正確做法**：把色相寫死進提示詞（給 HEX：`#1C4436` / `#2F4335`，並明寫 `NOT blue-grey`），
驗收時算主色相、差 >40° 就算漂。

### 8.4 其他踩過的坑

1. **平台壓浮水印**（右下「AI生成」）⇒ 摳底後仍帶 alpha ⇒ 用 BFS 只留最大連通塊。
2. **提示詞必須明講 Q 版**：「enormous oversized head / only TWO heads tall / SNES-DNF enemy sprite」；
   沒寫就出寫實比例。**輸出用 `1024x1536`（直式）** ⇒ 整數降採樣倍率大、像素塊細（約 1–2px，與源素材一致）。
3. **把「怪物名＋視角」放提示詞最前面** ⇒ ImageGen 輸出檔名自帶識別碼，4 方向完全可批次化。
   ⚠️ 重出時 `raw_fix/` 會累積多輪同前綴檔 ⇒ **按檔名排序取最後一個**（時間戳在檔名裡）。
4. **AI 會畫地面陰影**（提示詞寫 `no ground shadow` 也照畫）⇒ `trim_shadow_small`
   在 **128px 尺度**裁（三條件：帶亮度<0.22、上方 >1.6× 驟降、帶高 6–16 列）。
   ⚠️ 門檻是 128px 量的，**套在 1024×1536 原圖上會誤裁 12/16 張**；裁完**必須重算高度**否則腳底不再是 127。

### 8.5 驗證證據

| 檢查 | 結果 |
|---|---|
| `.import` | 8 隻 × **84/84** |
| `probe_clips` | 8 隻全部 `source=pack 動作數=5 [attack,die,hurt,idle,walk]` |
| 規格 | 主體 72–128 × 92–122、**腳底統一 127**、用色 22–48（自適應色板，非 44 色） |
| 全套回歸 | **與基線完全一致**（`self_check` 3 + `verify_skill_panel` 2，零新增失敗） |

### 8.6 剩餘 BLOCKED（**不是能力問題，是前置條件缺失**）

| 批次 | 阻塞原因 |
|---|---|
| `D4` 狀態圖標 12 張 | 策劃案只寫「buff/debuff 12 張」**沒給 id 清單**，代碼也無 buff/debuff id 體系 |
| `H1` 4 種地圖形態 tileset | 策劃案明寫「**先定 4 種形態的設計，再談張數**」 |
| `B1-summon_*` 召喚物 2 隻 | `summon` 形態在 `skill_controller.gd` 未實作（**素材鏈路已通，只差系統**） |


---

## 9 · B1 玩家召喚系統（2026-09-28 完成）

### 9.1 分工
- **工程**：`engineering-lead`（Task B1-ENG-01）實作規格 §12.4 的六條接口 + `Summon` 本體。
- **素材**：本產線（AI 出圖 → 後處理 → 動作衍生），**先於工程完成** ⇒ 工程可零改動載入。

### 9.2 工程改動（全部向後兼容）
| 檔案 | 動作 |
|---|---|
| `scripts/combat/summon.gd` | **新** `class_name Summon extends EnemyBase`；`_sync_dynamic_stats()` **每幀**讀玩家攻擊/最大生命；15s 到期 `_expire()`（不計死亡） |
| `game/scenes/combat/summon.tscn` | **新**（比照 `enemy_base.tscn`） |
| `scripts/ui/summon_bar.gd` | **新** `SummonBarUI`：`summons` 組圖標 + 剩餘時間倒數環 |
| `scripts/enemies/enemy_base.gd` | 加 `@export target_group`（預設 `"player"`）＋`@export is_summon`（預設 false）；`_move_speed/_aggro_range/_lose_range` 抽成可覆寫；`is_summon` 短路 BOSS 路徑 |
| `scripts/combat/hit_query.gd` | `circle`/`arc`/`rect` 三型一律排除 `summons` 組 |
| `scripts/player/player_controller.gd` | `perform_skill_dash()` 撞擊判定同樣排除 `summons` |
| `scripts/run/level_scene.gd` | `_build_summon_bar()`（HUD 原點 `(472,268)`） |
| `game/tools/verify_summon.gd`＋`.tscn` | **新** V10 專項測試（**39 條斷言**） |

**架構決策**：`Summon extends EnemyBase` 複用既有 AI 狀態機／精靈優先鏈／`HealthComponent`，
對 `EnemyBase` 只加**守門鉤子**（預設值下行為逐位不變）⇒ 既有回歸腳本**零新增失敗**。

### 9.3 素材交付：2 隻 × 84 幀 = 168 幀（**只用了 8 張 AI 圖**）
| 召喚物 | 配色（規格 §12.5） | 落點 |
|---|---|---|
| `summon_spirit_wolf` 靈狼 | 銀白毛皮 + 青色眼 | `game/assets/pack/creatures/summon_spirit_wolf/` |
| `summon_elemental` 元素僕從 | 橙紅火焰 | `game/assets/pack/creatures/summon_elemental/` |

**⚠️ 為什麼是 4 方向 × 21 幀，而不是規格書寫的「8 方向 × 16 幀」**
規格 §12.3 寫「8 方向 / 32×32」，但實測代碼現實是：
- `enemy_base.gd::dir_from_vector()` **只回 4 方向**（且只有 `DIR_N/E/S/W` 四個常量）
- 召喚物走 `EnemyBase.resolve_character_set()` ⇒ **只能吃 4 方向**
⇒ 做 **4 方向**（與既有小怪同構），並沿用既有的 idle4/walk4/attack4/hurt3/die6 = **84 幀**。
**這讓 AI 出圖從 16 張降到 8 張**，且能直接複用 `gen_monster_actions.py`。

**新增兩支薄包裝（本專案推薦模式）**：
`gen_summon_postprocess.py` / `gen_summon_actions.py` —— 只 `import` 既有模組並覆寫
`RAW` / `OUT_ROOT` / `SRC` 三個常數，**邏輯一行不改**。
⇒ 摳底與動作衍生是踩過多次才定案的技術，**複製一份＝兩份會各自漂移的真相**；
薄包裝讓「修 G1 的 bug，召喚物自動受益」。

### 9.4 驗證證據
| 檢查 | 結果 |
|---|---|
| `.import` | 2 隻 × **84/84** |
| `probe_clips` | `summon_spirit_wolf` / `summon_elemental` 皆 `source=pack 動作數=5 [attack,die,hurt,idle,walk]` |
| `verify_summon` | **39 條斷言 0 失敗**（含「動態讀取非快照」：改玩家攻擊 12→62、生命 150→250 後召喚物同步） |
| `parse_all` | 全部可解析（222 個 `.gd`） |
| 全套回歸 | **零新增失敗**（腳本數 65 → 66 ＝ 新增的 `verify_summon`） |
| **真渲染取證** | `tools/capture_summon.tscn`（**新增**）→ **0 項失敗** + 實際畫面：召喚物可見、藍量正確扣除、右下倒數環顯示 15 |

### 9.4.1 真渲染取證（為什麼非做不可）
`verify_summon` 的 headless 斷言只能證明「場上多了 1 個節點」，**證明不了「它有被畫出來」**——
本專案踩過：PNG 缺 `.import` ⇒ 精靈**靜默消失且不報錯**。
⇒ 新增 `tools/capture_summon.tscn`（**走技能系統 `try_cast()`** 而非直接 `Summon.spawn()`，
順帶驗證接線）：

| 檢查 | 結果 |
|---|---|
| 施放 `summon_spirit_wolf` | `try_cast` → **true**，藍 **100 → 70**（扣 30），場上 1 隻，id 正確 |
| 施放 `summon_elemental` | `try_cast` → **true**，藍 **100 → 60**（扣 40），場上 1 隻，id 正確 |
| 畫面 | 靈狼（銀白）/ 火焰元素（橙紅）**可見**；右下**倒數環顯示 15** |

> ⚠️ **它第一次跑是失敗的（`try_cast` 回 false、場上 0 隻）**，因此暴露了一個真實的可用性事實：
> `SkillController._load_skills()` **只載入「出戰欄」（`SaveData.skill_bar`）的技能**，
> 而召喚技能是進**技能池**的 ⇒ **玩家必須先在技能面板把它裝備到出戰欄才能施放**。
> 工具內以「白盒注入 `_skills`」模擬已裝備，並在註解標明原因。

### 9.4.2 端到端取證：裝備 → 施放（**玩家真實操作路徑**）
9.4.1 是**白盒**（注入 `_skills`），只驗了「召喚技能的分派路徑」。
⇒ 再新增 `tools/capture_summon_equip.tscn`，走**真實路徑**：
技能面板點擊 → 保存（落 `SaveData.skill_bar`）→ `SkillController._load_skills()` 重新載入
→ `try_cast()`。**這才是「裝備 → 能施放」整條路打完的證據。**

| 職業 / 技能 | 裝備前出戰欄 | 裝備後出戰欄 | 進關卡結果 |
|---|---|---|---|
| archer / `summon_spirit_wolf` | `[piercing_shot, arrow_rain, venom_shot]` | `[arrow_rain, venom_shot, **summon_spirit_wolf**]` | **自動載入（非注入）** → `try_cast` **true** → 場上 1 隻 |
| mage / `summon_elemental` | `[fireball, frost_nova, lightning_chain]` | `[frost_nova, lightning_chain, **summon_elemental**]` | 同上 ✓ |

**結果 0 項失敗**；畫面見 `deliverables/gstack/summon_shot/equip_flow_combined.png`
（技能池 5/6 個全顯示 → 裝上後出戰欄更新 + 底部「已保存：…」→ 進關卡召喚物出現且藍量正確扣除）。

> ⚠️ **跑這支工具必須隔離 `APPDATA`**（它會寫存檔）：
> `APPDATA=<臨時目錄> "<Godot>" --path . tools/capture_summon_equip.tscn`

> 🔴 **我在寫這支工具時踩了兩個 UI 測試的坑（斷言會靜默失效）**：
> 1. **找按鈕要同時比對 `text` 與 `name`** —— `hub.gd` 的面板切換鈕只設 `text`（"技能"），
>    `name` 是預設 `"Button"`；而 `SkillPanel` 的池按鈕設 `name`（`PoolBtn_<id>`）。
> 2. **`_on_bar_clicked()` 會 `_refresh()` 重建整個面板**（`queue_free` 舊節點）
>    ⇒ **卸下前拿到的 `pool_btn` 引用已失效**，`pressed.emit()` 沒反應
>    （症狀：卸下成功 3→2，卻裝不上去）。⇒ 取節點引用必須在**最後一次 `_refresh()` 之後**。

### 9.5 未完成（**誠實清單**）
| 項 | 狀態 |
|---|---|
| ~~**技能裝備流程**~~ | ✅ **已驗證**（本來就完整；9.4.2 走玩家真實路徑取證，0 失敗）。⚠️ 需隔離 `APPDATA` 才跑 |
| ~~**技能接線**~~ | ✅ **已完成** —— `skills.json` **12 → 14 條**、`SkillType` +`SUMMON=3`、`skill_controller` +`_execute_summon()`、`classes.json` 進技能池（**不動 `default_skill_bar`**）。⚠️ 玩家仍需在技能面板**裝備**才能施放，見 §9.4.1 |
| **選角面板只顯示 5 張技能卡** | ⚠️ `character_select_panel._build_skill_cards()` **硬寫 `for i in 5`** ⇒ 法師池第 6 個技能在**選角面板不顯示**（技能管理面板正常）。未動版面（`SKILL_CARDS_RECT` 是 5 格排布） |
| `verify_fix85.gd` 仍紅 | ⚠️ 它斷言 `skills.size() == 8`，與現實（14）早已不符 ⇒ **既有問題**，非本次造成 |
| **怪物索敵納入召喚物** | ❌ §12.4#1 只定義「召喚物打誰」，未定義「怪打誰」⇒ 靈狼**無法真的拉仇恨**，只能靠輸出牽制 |
| 元素僕從火球彈道 | ⚠️ 專案尚無投射物系統 ⇒ 目前「命中即結算 + 命中點播 `elem_hit_fire`」，無飛行時間 |
| 衝鋒 / 濺射實機手感 | ⚠️ 邏輯與比例已由測試覆蓋，手感待實機確認 |


---

## 10 · D4 狀態欄圖標 12 張（2026-09-28 完成 · 零 AI）

### 10.1 id 依據與裁定
- `03-装备特色玩法.md` §11.1.1 明列 5 個異常鍵（`AILMENT_BURN/SLOW/POISON` ＋建議「麻痺/虛弱」）；
  附錄 A §A.8 說「狀態圖標 12 張（buff/debuff）」。
- **debuff 6**：沿用 F3 六鍵 `burn/chill/poison/shock/curse/sunder`（與 §11.1.1 的 `AILMENT_*` 對應）
- **buff 6**：`warcry/blood_rage/iron_bulwark/hawk_eye/regen/shield`
  （前 4 個 = C4 光環同源技能，後 2 個 = 既有詞綴/格擋機制）

### 10.2 與 F3（ailment_*）的分工 —— 不重複
| | `ailment_*`（F3） | `status_*`（D4，本批） |
|---|---|---|
| 用途 | 元素異常圖標（飄字/命中提示） | **狀態欄**長駐圖標 |
| 區分方式 | 按**元素色**（flame 紅 / snow 藍…） | 按 **buff/debuff 語意**：buff=teal＋▲角標、debuff=blood＋▼角標 |
| 符號 | 兩階亮色 | **單色剪影**（見 10.3） |

### 10.3 🔴 踩坑：`SERIES` 每個色系只有 **4 色**
`compose` 的映射＝`IDX_D/M/B/G → series[0..3]`（`IDX_B(4)`→cols[2]、`IDX_G(5)`→cols[3]，不越界）。
但 `_stamp` 的「基元細節→hi(IDX_B)、主體→glow(IDX_G)」分工，在 **teal 系會糊**：
teal 的 hi(`2FA37A`) 與內圈(`1B6B52`) 亮度差只有 **0x14**（blood 差 0x38）
⇒ `iron_bulwark` / `shield` 實測變成一團綠。
**修法**：狀態欄 24px 本就該是單色剪影 ⇒ 符號細節與主體**都壓到 `IDX_G`（該色系最亮階）**。v2 全部清晰。

### 10.4 產出與驗證
`status_{warcry,blood_rage,iron_bulwark,hawk_eye,regen,shield,burn,chill,poison,shock,curse,sunder}_24.png`
＝ **12 張**；自校驗 **0 異常**（PALETTE_ALL 44 色、alpha 二值、24×24）。產線：`gen_icons_p4_status.py`。

✅ **收尾已完成**（同日稍晚）：**匯入 Godot**（status **12/12** + `rat_swarm` 84/84 `.import`）、
**`ui_skin.gd` TEX 表登記 12 條**（總條目 **233 → 245**，單檔預檢無 Parse Error）、
`probe_tex` **245/245 全過**。剩狀態欄 UI 消費端（系統本身未實作）。

### 10.6 🔴 H1 重新分類（拍板的意外結論）：**它不是素材批次**
追到 `05-怪物关卡BOSS.md:832` 的原文——「4 種形態」＝**關卡空間布局的 4 種生成算法**：
給 `layout` 加 `pattern` 欄位（`level_generator.gd` 小改）：`rooms`（現狀）/ `corridor` / `arena` / `ring`，
分別適配 clear_all / reach_exit / kill_boss+survive / kill_elite ⇒ **零素材量，屬工程工單**（隨 §7.4 批次④）。
⇒ **素材線正式收線**（ASSET_MANIFEST v7：done 25、BLOCKED 0）。
tileset 反而不缺（3 章=3 群系）；若未來要第四群系，拍板＝**swamp 毒沼**（程序化零成本，未排）。
另：`rat_swarm` 正面重出後的 84 幀**已匯入**（84/84）並 `probe_clips` 驗證載入 ✓。

### 10.5 素材批次總結（ASSET_MANIFEST v6）
**done 25 批 / BLOCKED 僅剩 H1**（4 種地圖形態 tileset——策劃案明寫「先定形態設計再談張數」，
`assets/tilesets/` 現有 forest/frost/volcanic 三群系）。G2 = 0 檔（不新增 BOSS，特效已列 C6）；
E4 = 徽記 3 張早已存在（缺消費點 L15，屬工程側）。

---

## 11 · 精細度體檢（2026-09-28 · 柳絮問「是否需要優化」的判斷紀錄）

### 11.1 結論：**不做大規模精修**；只修 1 個真實瑕疵（已修）

| 檢查項 | 結論 |
|---|---|
| 技術質量（色板/alpha/腳底基準/尺寸） | 全批合規 ⇒ **無需修** |
| **風格差異**（舊資產 vs G1/召喚物） | 舊=細線條寫實（1-2px 細節）、新=Q 版大輪廓。**判斷：不修**——怪物實機只顯示 32px（`DNF_GAME_SCALE=0.25`），舊怪的 1-2px 細節會被 4:1 降採樣吃掉，**Q 版大輪廓在實機反而更可讀**；重做需 40 張 AI 圖（≈200+ credits）換一個「實機看不到」的改動 |
| 瑕疵：`rat_swarm` 正面是**單隻大鼠**、側/背卻是三隻鼠群 | **已修**（1 張 AI 圖重出正面 ⇒ 提示詞強調「必須讀成鼠群」；84 幀已重衍生裝入，**等最後匯入才生效**） |

### 11.2 順手修掉的產線 bug
`gen_monster_actions.py` 的 `--only` **從一開始就失效**——`ids = args.only if …` 下一行
**又無條件覆蓋** ⇒ 跑 `--only rat_swarm` 會重跑全部怪（冪等無害但浪費時間）。已合併成一行。

### 11.3 體檢對照圖
`preview_quality_check.png`（舊/新/召喚物 × 人形/群體/大型，6x）——
風格差異在圖上可直接看：同屏時舊怪細長、新怪矮胖，但實機 32px 下輪廓可讀性反而是新怪贏。