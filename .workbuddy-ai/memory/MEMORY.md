# 项目长期记忆 — 七傳說（索引檔）

> **本檔只做「當前位置 + 最高優先事項」索引。**
> 📕 **完整鐵律 / 坑 / 已拍板結論 → 同目錄 `IRON-RULES.md`（開工前必讀）**
> 📘 **數值與清單明細 → `deliverables/gstack/策划案/`（01–07 .md/.json）**

---

## 🔴 當前位置（2026-09-28）

| 線 | 狀態 |
|---|---|
| 策劃七步 | ✅ 完成（180 工單 / 8 批次 / 568 通過 4 待修） |
| 素材開發線 | ✅ 收線（ASSET_MANIFEST v7：done 25 / BLOCKED 0） |
| **工程落地** | 🟡 **B2 內容底座 完成**（3 工單）⇒ 下一步 **B3 死鉤子接線（58 工單 · 最大批）** |

⇒ **B0 已落地**：`SkillType` 4→7 / `skills.json` 14→**36** / 新建 `runes.json`(24)+`branches.json`(7)
/ 三職業池各 12 / `skill_level` 死鉤子復活（`FINAL_KEYS` 31→32）/ `verify_skills` 四條同步

⇒ **B1 已落地**：成長率 1.22/1.16→**1.12/1.12**（同值⇒相對強度恆定）｜賬號上限 60→**20**｜20 關
`budget` 合計 **5,660** + `rec` 5…20 + `count_*` 等比｜4 個手繪關 `'m'` 重畫（23/48/41/32 → **60/72/86/92**）
｜iLvl = `clamp(怪等級±三角抖動(±2), 怪等級-2, max(怪等級,玩家等級))`｜曲線斷言 ≤12→**≤25**

⇒ **B2 已落地**（3 commit）：`enemy_base.gd` 的 `ai_id` match **4→6 具名分支**（策劃 C5 4/6→**6/6**）
｜`verify_enemy.gd` 新增 **G 段 13 條 AI 分派斷言**（6 種行為互不相同 + 新字段對老怪缺省透明）
｜**修 `ranged_kiter`/`lobber` 的「太近則後退」死分支**（`_wants_back_off`）
｜**12 關 `monster_entries` 換掉越界怪**（15 條目；越界殘留 0）
⚠️ **重大發現**：`5-W5-2`（9 字段）/ `5-W5-3` 前半（8 隻新怪）**已在 `d27c31e`（素材線）落地**，非 B2 所加
⚠️ **8 隻新怪的 `sprite_path` 指向不存在的 png** ⇒ `use_placeholder_art` 兜底不崩，**屬 B7 素材替換**

**⇒ 驗收：工程回歸 67 腳本零新增失敗（殘餘與 B1 基線逐條一致）；`05 --repo` 82/4（C5 已修）；`06/07 --repo` 202/0 · 212/0**

（明細見 `.workbuddy-ai/memory/2026-09-28.md` §六/§七/§八）

⚠️ **留給各自批次的預存回歸紅**（用戶已裁定本輪不動）：4 條**無工單**（`verify_choice_panel` 裸 Color
／`verify_player` 手柄映射／`verify_skill_panel` `save_version==3` vs `SAVE_VERSION=4`）＋ `self_check`
怪物 L20 舊值 2 條（→ B6 `4-W5-e`）。B2 開工不受影響。

⚠️ **git**：09-28 backlog 5 天已補提交（`8801219`/`61322b8`/`d27c31e`/`ef604aa`），B0/B1 各另起 commit。

---

## 基线 / 协作约定

- 暗黑刷宝 ARPG ｜ **Godot 4.7.2** ｜ GDScript ｜ 纯单机 ｜ 美术 AI 生成
- ⚠️ 2026-09-23 用戶裁定「代碼不上線」⇒ 不做 Steam 發行，純本地自玩
  （移出：圖標/版本號/簽名/PCK 加密/存檔防篡改；仍在：本地可玩性、存檔可靠性、素材授權乾淨）
- 产物统一放 `deliverables/gstack/`；命名 `<场景类型>-<主题简称>-<YYYY-MM-DD>.md`
- **「幹活簡潔明瞭，不做多餘的事，或做之前問我」** ⇒ 少寫長報告、少做自選動作；**動手前先確認**
- 原「AI 只是策劃、不改 `game/`」的邊界在**素材開發線**已被突破（`素材開發/README.md` §7.2/§9.2 實際改了
  `ui_skin.gd`/`fx.json`/`juice_fx.gd`/`skills.json`/`skill_controller.gd`/`enemy_base.gd`/`summon.gd`…）
  ⇒ **動 `game/` 前仍須逐次確認**，且改動必須附驗證

---

## ⚠️ 最常踩的五個坑（詳解與全套 SF1–SF12 見 `IRON-RULES.md`）

1. **導出包內 `DirAccess` 枚舉 `res://` 全廢**（編輯器內永遠看不到）⇒ 一律走**顯式清單 / 命名約定探測**
2. **`.tscn` 節點漏 `type=` ⇒ Godot 靜默丟棄節點**（成批量同類警告先當 bug 症狀查）
3. **`UISkin` 工廠靜默返回 null** ⇒ 改素材路徑/鍵名後**必須真渲染抓圖目視確認**
4. **自洽式偽校驗**（腳本用自己的硬編碼常量算自己的斷言 ⇒ 永遠通過）
5. **String 字段靜默脫鉤**（`ai_id` 定義 6 種、代碼 **0 分支**、測試全綠）

**三條判據**：① 看到「永遠通過」的校驗 ⇒ 查常量是**引用**還是**硬編碼副本**
② 看到 `String` 字段（`ai_id`/`pattern`/`kind`/`behavior`）⇒ 先 grep 代碼分支數，命中 ≤1 = 沒實現
③ 改「看起來是配置項」的字段前 ⇒ 先 grep 消費點；只有「埋點/展示/註釋」⇒ 改了不會有行為變化

---

## ⚠️ 全案三條最高危項

1. **稀有度 8→10 不可逆** —— `rarity` 存 int；`RARITY_COUNT` 回退會把舊檔 8/9 **靜默壓成 7（隱藏裝）**
2. **62 件底材無一覆蓋 8/9 檔** ⇒ `loot_roller.gd:171` 空池 `return null` ⇒ 特殊檔什麼都不掉且零報錯
3. **`migrate()` 的 `_:` 兜底** —— 漏加 `4:` 分支**不報錯**、新字段直接消失 ⇒ 存檔升版必須逐版加顯式分支

---

## git 铁律

- `origin` = `github.com/fyangOvO/fyangOvO.git` ✅ **推送一律 `git push origin main`**；`github.com/fyangOvO/game.git` ❌ 不再管
- Git LFS 已啟用；本地 `main` 根提交 `a8c6f6c` ⇒ 純快進無需強推
- **禁用**：`stash`（尤其 `-u`/`-a`）、`gc`、`prune`、`reset`、`checkout`、`clean`、`read-tree`、`filter-branch`
  **僅允許**：`add`/`commit`/`status`/`log`/`diff`（2026-09-20 事故：`stash push -u` 被 SIGTERM 中斷 ⇒ `.git` 整體進回收站）
- 清理殘留一律 `mv` 到 `.workbuddy-ai/trash/<日期>-<原因>/`，**不以 `rm` 直刪**

---

## 打包 / 環境速查

```bash
cd D:/七傳說/game && APPDATA='C:\Users\11265\AppData\Roaming' python tools/package_demo.py --backup
```
- ⚠️ `APPDATA` 空串 ⇒ 導出失敗 + **靜默漏清存檔**（Godot 把數據目錄解析成 `./Godot/`）
- Python：`C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe`（系統 `python`/`/tmp` 不可用）
- `run_regression.py` 的 `NO-RESULT` **是誤報** ⇒ 先讀 `%TEMP%\ge_regress_fail_<name>.log` 再定性
- 驗證探針（`game/tools/`）：`probe_tex`（TEX 載入）/ `probe_fx`（fx 表契約）/ `probe_clips`（精靈幀集）/ `probe_level`（關卡體檢）
