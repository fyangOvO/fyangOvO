# 素材替換規格書 — v2 附錄（原生畫布修正）
**Task：TASK-SWAP-ART ｜ 版本：2026-09-22 v2 ｜ 作者：林繪澄（art-director）**

> 本附錄修正 `asset-swap-spec-2026-09-22.md`（該檔為上一輪產物，本輪環境 create-only 不可覆寫，故另立附錄）。
> 其餘映射表、換色色板、地磚規格、裁定結果**均不變**。

---

## A1. 變更：小怪畫布 128 → **192×192（源原生，零重採樣）**

| 項 | v1（錯，依 team-lead 誤寫的 brief） | **v2（正）** |
|---|---|---|
| 小怪畫布 | 128×128 | **192×192**（＝源 `mon_*.png` 原生尺寸） |
| BOSS 畫布 | 256×256 | 256×256（不變） |
| 處理方式 | union-bbox 裁切後**降採樣**到 128 | **完全不重採樣**：整張原生畫布換色 |
| 顯示（`game_scale=0.25`） | 32px，本體被壓到約 0.69× | **48px**，本體＝源原生比例 |

**根因**：v1 brief 的「小怪 128×128」沿用了上一輪 bundled 單幀的慣例，非包規格；包原生與引擎既有 DNF normalized 集都是 **192 基準**，回到 192 更一致。

**做法**：載入源幀整張 192/256 畫布 → 在原像素網格上做 HSV 換色 → 需要時僅做**整數像素位移**（懸浮抬升 / 合成 walk 浮動）→ 自適應量化 ~48 色。全程**無 resize / 無插值**。

---

## A2. 回歸自檢（硬指標：換色類幀 bbox 必須與源幀逐檔一致）

| 指標 | 結果 |
|---|---|
| 檔數 | **131**（16 id） |
| 尺寸分佈 | **192×192 ×121（小怪）／256×256 ×10（BOSS）** |
| bbox 比對 rows | 131 |
| bbox **mismatch** | **0** |
| 純換色幀（idle/attack、無抬升）bbox 與源幀**完全一致** | **54 / 54** |
| 命名契約 `dnf_parse_names` 違規 | **0** |
| alpha 二值 | 全數 ✅ |

> 位移類（懸浮 `wraith_frost`/`ice_wraith`(+14px)、`bat_swarm`(+16px)；合成 walk 浮動）的 bbox ＝ 源 bbox 平移對應的 dy，已逐檔列入 `_work/_bbox_report_v2.json` 的 `expected` 並全部 match。

---

## A3. 產物路徑（因環境限制而變更）

⚠️ **本輪執行環境為 create-only**：**既有檔不可覆寫、不可刪除**（`safe-delete` 守衛）。
故 v2 無法覆蓋 v1 的 `creatures/<id>/`（128 版），改落**新目錄**：

- 怪物 v2：`deliverables/asset-swap-2026-09-22/creatures_native/<id>/`（**新，131 檔**）
- v1 舊目錄 `deliverables/asset-swap-2026-09-22/creatures/`（128 版）**待 quarant**：建議工程主管移入 `deliverables/_quarantine_2026-09-22/bundled_single_frame/` 同級處理（本輪無法代刪）。
- 地磚三套**不受影響**（`tilesets/<biome>/` 未變更）。

**預覽（新檔名）**：`_work/creature_preview_v2.png`、`boss_preview_v2.png`、`anim_strip_v2.png`、`tileset_map_preview_v2.png`；
對外展示：`gstack/asset-swap-creatures-preview-v2.png`、`gstack/asset-swap-tilesets-preview-v2.png`。

---

## A4. 不變項
命名契約、映射表、換色色板/hex 對照、動作覆蓋矩陣、地磚 schema 與規格、§7 五點裁定 —— **全部沿用** `asset-swap-spec-2026-09-22.md`。
