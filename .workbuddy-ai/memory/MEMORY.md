# 项目长期记忆 — 七傳說（索引檔）

> **本檔只做「當前位置 + 最高優先事項」索引。**
> 📕 **完整鐵律 / 坑 / 已拍板結論 → 同目錄 `IRON-RULES.md`（開工前必讀）**
> 📘 **數值與清單明細 → `deliverables/gstack/策划案/`（01–07 .md/.json）**

---

## 🔴 當前位置（2026-09-29）

| 線 | 狀態 |
|---|---|
| 策劃七步 | ✅ 完成（180 工單 / 8 批次 / 568 通過 4 待修） |
| 素材開發線 | ✅ 收線（ASSET_MANIFEST v7：done 25 / BLOCKED 0） |
| **工程落地** | 🟡 **B3-5 技能形態實體 完成**（B3 實際 54 工單，分 7 小批）⇒ 下一步 **B3-6 套裝徽記 UI（`2-L15`，1 工單）** |

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

**⇒ B2 驗收**：工程回歸 67 腳本零新增失敗（殘餘與 B1 基線逐條一致）；`05 --repo` 82/4（C5 已修）；`06/07 --repo` 202/0 · 212/0

⇒ **B3-1 數據底座 已落地**（6 工單）：詞綴 **33→48** ｜ 池 **10→14**（epic_empower/legendary_pool/set_pool/hidden_pool）
｜ `add_armor_penetration.stat_key` → **`armor_pierce`**（修死鉤子 C2）｜ 4 條權重 ｜ 18 件套裝散件 +`set_pool`
｜ 掉落表 3 檔 +`rune_drop_chance`/`material_sub_weights`/`item_level_spread` ｜ `02-check` **11/4 → 14/0**（A4 依 §1.5 裁定改 `[WARN]`）
⚠️ **B3 口徑**：官方 members 58 條，**實際 `batch==B3` 為 54 條**（7 條歸 B6/B7/B4）
⚠️ **已落地 5 條不必重做**：`2-L2`/`2-L4`/`2-V9`/`3-X2`/`3-X6`（B0 已做）；`2-L1`/`2-V8` 係數在 `PlayerController`（裁定保持現狀）
⇒ **B3-2 元素與抗性管線 已落地**（9 工單 / 8 檔）：`FINAL_KEYS` 32→**52**（元素子鍵 5 + 抗性 3
+ 穿透 2 + 異常 8 + 全元素/對異常 2）｜ `_RESIST_KEY_BY_ELEMENT` 4 系 → **6 系全映射**（補 shadow/physical）
｜ `mitigation_factor` +`resist_penetration_pct`（`eff=max(0,r-p)`）｜ **物理減傷改護甲×物抗相乘**
｜ `STAT_ARMOR_PENETRATION` → **`STAT_ARMOR_PIERCE`**（C2 殘留清零）｜ 面板 `LABELS`/`PCT_KEYS` 補 20 鍵
+ **3 欄→4 欄**（52 鍵 × 4 = 13 行仍適配 640×360）｜ 新增斷言 **2-V6**（stat_key 白名單）/ **2-V14**
（6 系映射 + 行為斷言）/ 穿透+物理相乘 G1 段 / **新鍵裝備路徑注入 H 段**
⚠️ **本批新踩坑（後綴漏判）**：pct 用 `ends_with("_damage")` ⇒ `elemental_damage_fire`（真後綴 `_fire`）
**全漏判恆 0** ⇒ 補前綴規則 `begins_with("elemental_damage")`（詳見 `IRON-RULES.md`）
⚠️ **遺留**：① 元素子鍵**暫無供給源**（15 條新詞綴不含子鍵）⇒ 恆 0，**接線已就位**（待元素專精詞綴）
② `UISkin` 圖標鍵仍 `affix_armor_penetration` ⇒ `affix_icon("armor_pierce")` 回 null（**無運行時消費點**，留 B7）

⇒ **B3-3 傷害與資源接線 已落地**（7 工單 / 5 檔）：`SkillController.try_cast` 接 **CDR + 減耗**（皆 **70% 硬頂**，
`real_cost≥0` / `_cooldowns≥0.2s`，作用在符文修飾後的 `effective` 上不丟符文）｜ `_hit` 第 5 形參改
`get_element_damage_bonus(data.element)`（死鉤子① 復活）｜ 新增 `PlayerController.get_element_damage_bonus()`
（`physical⇒0`；其餘 = 專精子鍵 + `elemental_damage` + `all_element_damage` 三者累加）｜ `apply_combat_stats`
追加 `mana_pool.apply_stats(max_resource, resource_regen/100, **0**）` + `_physics_process` 補 `tick_regen`
（`resource_regen`/`max_resource` 兩死鉤子復活；`cost_reduction_pct` 刻意傳 0 防雙重減免）｜ 新增斷言
**2-V10**（元素端到端「+100% ⇒ 傷害翻倍」+ 普攻不吃元素）/ **2-V11**（+70% 與 +200% 等價）
⚠️ **本批 4 項用戶裁定**：`all_element_damage` 計入 / 資源屬性順手接線 / **普攻物理一律 0**（取 `03 §4.2.3`
而非 `02 §7.1②`，兩文衝突取更晚更權威）/ 補 `tick_regen`

⇒ **B3-4 傳奇特效總線 已落地（B3 核心批 / 11 工單 / 8 檔）**：新建 `scripts/legendary/legendary_bus.gd`
（`class_name LegendaryBus extends Node`，**結算/執行分離**：`LegendaryEffectSystem` 純結算不動狀態、Bus 執行）
｜ `event_bus.gd` +3 信號（`block_succeeded`/`skill_cast(id,mana_spent)`/`resource_spent(amount)`）
｜ `health_component.gd` +2 鉤子（`revive_hook`/`damaged_hook`）+ 格擋廣播
｜ `skill_controller.gd` +`halve_cooldown` + `try_cast` 埋點｜ `game_constants.gd` +3 常量
｜ `level_scene.gd` 掛載（`equipment_changed` ⇒ register/unregister）｜ 新增 `tools/verify_legendary_bus`（**27 條走生產路徑**）
**成果**：**10 個 trigger 全通** ｜ 第一期 **15 條特效（7 類執行器）通電**（deal_damage/heal/gain_resource/
extra_loot/revive_protect/reflect/resource_refund）｜ `03-legendary-wiring.json` `ready_to_wire` 22→**31**
⚠️ **本批 3 項用戶裁定**：`revive_protect` 走 **Callable 掛鉤**（`HealthComponent.revive_hook`）/ `on_low_hp` 走
**輪詢玩家 HP**（bus `_process` 讀 `hp_pct`）/ 本批執行器**僅 7 類**（`buff_stat`/`ms_boost`/`damage_reduction`/`summon` 歸 **B4**）
⚠️ **本批新踩 3 坑**（詳見 `IRON-RULES.md` ⑥⑦⑧）：⑥**新建 `class_name` 必跑 `--editor --quit` 重建全域類快取**
（否則 `Could not find type`）⑦**`HitQuery.circle` 排除圓心節點** ⇒ 以目標為圓心的 AoE 會漏掉目標本身（顯式補 `ctx.target`）
⑧**`EventBus.damage_taken` 只有近戰會發** ⇒ 玩家受擊改用 `HealthComponent.damaged_hook` 才覆蓋全
⚠️ **遺留**：①16 條待 B4 ②`extra_loot` 未強制 `loot_quality` ③套裝特效未接（屬「第 2 塊 套裝機制」）

⇒ **B3-5 技能形態實體 已落地**（2 工單 / 10 檔）：新建 `scripts/combat/projectile.gd`（**飛行/命中/穿透/分裂/連鎖**）
+ `scripts/combat/ground_area.gd`（**tick 結算/落地爆發/到期釋放**），皆**純腳本實體**（`.new()` + 代碼占位視覺，
與 `enemy_projectile.gd` 同構）｜`skill_controller.gd` 的 B0 **過渡實現**（即時一次性結算）**換成真實實體**
｜`skill_data.gd` +3 字段（`chain_decay_pct`/`split_count`/`split_damage_pct`）+ `config_loader` 載入
｜符文修飾器支援 **`on_hit_split` 嵌套 dict**（此前**靜默丟棄**）｜`_hit()` +`raw_multiplier`/`damage_scale`
（支撐「每 tick 倍率」與「連鎖衰減/分裂佔比」）｜`game_constants.gd` +`ELEMENT_COLORS` +7 投射物/地面常量
｜新增 `tools/verify_skill_forms`（**A~K 十一段 27 條，全走 `try_cast` 生產路徑**）
**成果**：7 個技能形態**全部有實體實現**（`PENDING_FORM_IMPL` 只剩 BUFF）｜**多發投射物傷害修正到設計值**
（B0 只結算 1 發 ⇒ 現 N 發獨立結算，`multishot` 全中 300%）｜持續區域總量 == `total_damage_multiplier()`（§5.1 不變量）
⚠️ **本批 3 項用戶裁定**：純腳本（不建 `.tscn`）/ 擴 `SkillData` 字段（非硬編碼）/ 持續區域落點 = **玩家腳下**
⚠️ **本批新踩 3 坑**（詳見 `IRON-RULES.md` ⑨⑩⑪）：⑨**`add_child()` 觸發的 `_ready()` 早於 `global_position` 賦值**
⇒ 落點相關結算會打在原點（改兩段式 `begin()`）⑩**`end_cast()` 的同步窗口**：投射物/區域命中在窗口外
⇒ 埋點**靜默漏記**（+`note_deferred_hit()` 補記，並區分「非同步」與「真空放」）⑪**測試清場須 `free()` 而非 `queue_free()`**
（延遲釋放會讓下一用例誤計殘留實體）
⚠️ **遺留（非本批）**：①`explosive_arrow` 的**命中爆炸**（`radius` 對投射物無法區分「顯式聲明」與「默認 48」）
②`poison_cloud`/`void_rift` 的「使其中毒」/「拉向中心」等附加效果 ③`rune_echo`（`echo_count`）未承載
⚠️ **B3 分 7 小批**（逐批驗收）：B3-1 ✅ → B3-2 ✅ → B3-3 ✅ → B3-4 ✅ → B3-5 ✅ → **B3-6 徽記** → B3-7 校驗

（明細見 `.workbuddy-ai/memory/2026-09-28.md` §六/§七/§八/§九/§十）

⚠️ **留給各自批次的預存回歸紅**（用戶已裁定本輪不動）：4 條**無工單**（`verify_choice_panel` 裸 Color
／`verify_player` 手柄映射／`verify_skill_panel` `save_version==3` vs `SAVE_VERSION=4`）＋ `self_check`
怪物 L20 舊值 2 條（→ B6 `4-W5-e`）。B2 開工不受影響。

⚠️ **git**：09-28 backlog 5 天已補提交（`8801219`/`61322b8`/`d27c31e`/`ef604aa`），B0/B1/B2/B3-1/B3-2/B3-3/B3-4/B3-5 各另起 commit（**最新 `89a88b7`**）。

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
