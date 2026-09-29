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
| **工程落地** | 🔴 **B5 特殊玩法 進行中（第六步 / 28 條 / 8 子批）**：**B5-1 存檔與門票底座 ✅**（`6-W6-01`/`02`/`20`）⇒ 下一步 **B5-2 稀有度擴容核心（`6-W6-11/12/13/14`，8→10 不可逆）** |

⇒ **B5-1 已落地**（3 工單，**存檔升版 v5→v6 + 門票 API + 稀有掉落廣播**）：
**`6-W6-01`** `SAVE_VERSION 5→6`；`save_data.gd` 新增 `tickets`/`tower_progress` 兩字段
（`create_new` 初始化 / `to_dict` / `from_dict` 帶 `is Dictionary` 守衛 / **`migrate()` 顯式 `5:` 分支**）
｜**`6-W6-02`** `get_ticket(id)->int` / `add_ticket(id, amount)->bool`（**風格對齊 `add_material()`**：
不足返回 `false` 且**不寫入** ⇒ 消耗即 `add_ticket(id,-1)`；門票永不为负）
｜**`6-W6-20`** `enemy_base._drop_loot()` 補 `EventBus.rare_loot_spawned` emit（`rarity >= Rarity.EPIC`，
位置取 add_child 之後的 `drop.global_position`）
｜門票 id 落常量：`game_constants.gd` 新增 `TICKET_NORMAL="ticket_normal"` / `TICKET_ADVANCED="key_advanced"` / `TICKET_KEYS`
⚠️ **本批新踩兩坑**（詳見 `IRON-RULES.md` ㊱㊲）：㊱**「版本號/檔數/項數」類斷言禁寫字面量**
（`verify_skill_ext.gd` 寫死 `save_version == 5` ⇒ 升 v6 即轉紅；改引用 `GameConstants.SAVE_VERSION`）
㊲**策劃校驗器的「現狀快照」斷言群須隨批次同步重基線**（`06` E 組 16 條 + `07` E-repo 群；
看到「尚無/仍為/零命中」措辭即是快照 ⇒ 落地該功能時必須同步翻轉）
**⇒ 驗收**：`verify_save`（+13 條）/ `verify_loot`（+稀有 emit 一致性）/ `verify_skill_ext` 全綠；
**證偽測試 ×2**（拿掉 `5:` 補字段 ⇒ 哨兵斷言轉紅；關掉 emit ⇒ emit 數斷言轉紅，均已還原）；
`06 --repo` **202/0** · `07 --repo` **212/0**（重基線後）；全量回歸 **76 腳本零新增失敗**。

⇒ **B4-6 已落地**（3 工單，**純驗證批 / 不動生產代碼**）：
**`1-V8`** `verify_skills` 新增 **G 段** `_test_dps_full_scan()` —— 36 條技能 × DPS 係數區間全量掃描
（`DPS_RANGE_BY_TYPE` 5 形態映射 + `DPS_EPSILON` 容差；非傷害形態斷言 `dps_coefficient()==0`；越界 0）**2 斷言全綠**
｜**`1-V9`** `verify_skill_ext` 新增 **J 段** `_test_dps_cross_check()` —— **獨立重算 × 交叉比對**
（`_raw_total_damage()` 直接讀 raw 欄位按 §5.1 重算，**不調用** `dps_coefficient()`）+ 兩定點易錯點
（`meteor` GROUND impact 只計一次 / `multishot` PROJECTILE count 已計入）**8 斷言全綠**
｜**`1-V7`** `verify_skill_ext` 新增 **K 段** `_test_form_coverage()` —— 7 形態 × 全表齊備
（single 4/aoe 4/dash 3/projectile 9/ground 7/summon 2/buff 7 = 36）**8 斷言全綠**
（「4 新形態」實測已由 `verify_skill_forms.gd` 覆蓋，本批不重複）
⚠️ **本批新踩四坑**（詳見 `IRON-RULES.md` ㉜㉝㉞㉟）：㉜**驗計算函數必須「獨立重算 × 交叉比對」**（拿被測函數自算期望值 = SF4 偽綠）
㉝**定點易錯點斷言須先確認樣本真的走那條分支**（全表**僅 `meteor`** 的 `impact_multiplier > 0`）
㉞**策劃 `06/07-check_*.py` 的 `--repo` 必須帶路徑**（否則少跑 E 組、計數少 16：186↔202 / 196↔212）
㉟**改配色/口徑後須 grep 全倉斷言同步**（B4-5 `3-E7` 改飄字色致 `verify_juice` **延遲紅**，本批暴露並修正）
**⇒ 驗收**：`verify_skills` G 段 / `verify_skill_ext` J+K 段全綠；證偽測試（改壞 `projectile_count` 乘數 ⇒ 兩段精準轉紅，已還原）；
`verify_juice` 延遲紅修正後 **0 失敗**；全量回歸 **76 腳本 / 225.1s 零新增失敗**（殘餘 3 檔 4 項與基線逐條一致）；
策劃 `06 --repo` 202/0 · `07 --repo` 212/0（本批無策劃側變更）。

⇒ **B4-5 已落地**（2 工單，**元素深化閉環**）：
**`3-E7` 元素飄字配色**：`DamageNumber.setup(amount, is_crit, element)` + `static normal_color_for(element)`
（有元素 ⇒ `ELEMENT_COLORS` 單一來源；空串/未知 ⇒ 普通色）；**暴擊優先**（暴擊用暴擊色，非暴擊才按元素上色）；
`JuiceFX._spawn_damage_number` 透傳 element ⇒ 6 元素各一色（白/橙/冰藍/黃/綠/紫）
｜**`3-E8` 雷/暗異常**：新增 `AILMENT_SHOCK`（**感電**，受到的直接傷害 ×1.20，落 `HealthComponent.take_damage`）
+ `AILMENT_CURSE`（**詛咒**，造成的傷害 ×0.80，折進 `PlayerController/EnemyBase.get_attack_damage` —— 唯一輸出出口）
｜`AILMENTS` 3→**5**；`AILMENT_ELEMENT_MAP` 補 lightning→shock / shadow→curse
｜乘區單一來源：`shock_damage_taken_multiplier()` / `curse_damage_dealt_multiplier()`
⚠️ **命名口徑（重要）**：新異常 id **必須**取 `shock`/`curse` —— 對齊既有素材鍵（`ui_skin.ailment_icon` = burn/chill/poison/shock/curse/sunder）
與既有屬性鍵（`STAT_SHOCK_DAMAGE` 对感电目标增伤 / `STAT_CURSE_DAMAGE` 对诅咒目标增伤）；**勿自創 `weaken`**
⚠️ **本批新踩兩坑**（詳見 `IRON-RULES.md` ㉚㉛）：㉚**新增狀態效果前先 grep 素材鍵/屬性鍵再定 id**
㉛**`self_check` 的「某元素無異常」是硬編碼斷言 ⇒ 加映射必轉紅**（須同步 + 查 `AILMENTS.size()` 類計數）
⚠️ **遺留**：①**玩家→怪物施加異常未接通**（本批拍板不做）⇒ 新異常目前**只能由 2 隻雷怪 / 2 隻暗怪打玩家觸發**
②**無異常 HUD**（`status_shock`/`status_curse` 素材已存在但無消費點）③既有命名漂移 `AILMENT_SLOW="slow"` vs 素材鍵 `chill`
④`STAT_SHOCK_DAMAGE`/`STAT_CURSE_DAMAGE` 仍是死鉤子（屬詞綴管線）⑤策劃 gaps 建議雷=「麻痺」，實現採「感電」（已記 `resolution`）
**⇒ 驗收**：`verify_element_ext`（新建，**9 段 / 41 斷言全綠**）；全量回歸 **76 腳本（+1）/ 198.2s 零新增失敗**（殘餘 3 檔 4 項，與 B4-4 逐條一致）；
策劃 `06 --repo` **202/0** · `07 --repo` **212/0**；`b45_shot/` 1 張目視確認。

⇒ **B4-4 已落地**（7 工單，**技能擴展 UI 全線閉環**）：`SAVE_VERSION 4 → 5`（新增 `skill_runes`/`skill_branches`/`unlocked_runes` 三欄位 + migrate 顯式 `4:` 分支）
｜**技能等級**（每級 +8% 傷害係數，`1-L8`）修 flat/pct 桶錯位（`run_buff_system` 走 **flat 桶**）
｜**技能解鎖節奏表落數據**（`skills.json` 每條加 `unlock_level`/`unlock_boss`，`1-L11`）+ `UnlockSystem.is_skill_unlocked()` 雙軌（等級軌 + BOSS 首通軌）+ skill_panel 解鎖閘門
｜**天賦「技之極意」單點接線**（第 6 個大節點機制 + hub 消費 `TalentTree.get_bonus_stats()`，`1-L10`）
｜**符文/分支完整閉環**（`1-L13`）：`SkillController._apply_rune_modifiers`/`_apply_branch_modifiers`（**可映射 7 鍵**）+ hub 落盤 + 局內讀檔套用
｜**`skill_panel.gd` 整檔重寫**（`1-L9`/`1-L14`）：兩層（12 池卡 + 3 出戰槽 / 詳情浮層）+ 符文槽 3（3/6/9 解鎖）+ 分支二選一 + 卸下入口
｜**`skill_bar.gd` 三標識**（等級數字 / 符文圓點 / 分支色框）
｜**新增 `rune_codex_panel.gd`（`class_name RuneCodexPanel`）**：hub 第 7 面板「符文图鉴」6×4=24 格 + 右詳情，未解鎖灰化 + 🔒（`1-L12`）
⚠️ **本批新踩五坑**（詳見 `IRON-RULES.md` ㉔㉕㉖㉗㉘㉙）：㉔**`String(v)` 對數字拋錯 ⇒ 一律 `str(v)`**（髒檔讀檔炸）
㉕**`queue_free()` 延遲釋放 ⇒ 同幀舊節點仍被 `find_child`/輸入命中**（**真實產品 bug**：點到上一輪 `DetailUnequip`；清格改 `remove_child`+`queue_free`）
㉖**新 `class_name` 未進快取 ⇒ 全庫 `Could not find type`**（跑 `--headless --editor --quit` 重建）
㉗**`Control` 掛 `Node2D` 拿不到視口尺寸**（宿主改 `CanvasLayer`）㉘**`PALETTE_ACCENT` 是 7×4 扁平原色，`[4]` 是暗綠**（亮金前景用 `[14]`）
⚠️ **遺留（記錄在案）**：①分支 **8 個 modifier 未接**（`combo_hits`/`combo_damage_pct`/`linger`/`afterimage`/`pulse`/`summon_count`/`summon_damage_pct`/`buff_potency_pct`，面板標「暫未生效」）
②**符文掉落接線屬 B6 `2-L12`**（精英 8%/BOSS 25%，`unlocked_runes` 已備落點但**無寫入方**）③`BIG_NODE_MECHANICS` 前 5 機制仍為展示字符串
④`talent_panel` 面板鍵（war/mage/shadow）與 `TalentTree` 鍵（might/guardian/arcane）**不一致（既有 bug）** ⑤`ACCOUNT_LEVEL_MAX 60` vs 策劃 `ruled_max_level 20`
⑥策劃 **S10 的 `SAVE_VERSION` 編號已順延為 `5→6`**（B4-4 先行占用 v5）
**⇒ 驗收**：`verify_skill_ext`（新建，**9 段 / 50 斷言全綠**）；全量回歸 **75 腳本（+1）/ 180.6s 零新增失敗**（殘餘 **3 檔 4 項**，比 B4-3 少 2 項）；
策劃 `06` **202/0** · `07 --repo` **212/0**（已同步編號轉綠）；`b44_shot/` 4 張目視確認。

⇒ **B4-3 已落地**（3 工單）：BOSS 三標誌性技能**全部通電**（`05-check` **C7 4/7 → 7/7**）——
`bone_slam`（前方 **120° 扇形** / 範圍 `attack_range × 1.6` / **0.4s 預警**→延遲命中 / ×1.4 傷害 / `fx_bone_slam`）·
`fireball`（**1–3 發**扇形散開 / 速度 140 / 壽命 3s / `bolt_fire` 精靈 / 命中**燃燒**）·
`enrage`（**全屏紅閃一次性**，`_enrage_fx_played` 旗標）
｜**掛載點刻意分化**：`bone_slam`→`_cast_boss_skill()`（近戰）· `fireball`→`_tick_state()`（遠程，`state != PATROL`）·
`enrage`→`_apply_boss_phase()`（一次性事件）
｜`BossPhaseController` 加 **`enrage_phase` 配置化**（骸骨 4 / 熔心 **3**）+ `validate()` 1–4 範圍報錯 +
`is_enraged(config, phase)`（**簽名變更**）｜召喚差異化：骸骨 `[0,3,5,7]`（召喚流）/ 熔心 `[0,1,2,2]`（法術流）
｜**兩 BOSS 等級區間放開**（骸骨 `6–20` / 熔心 `13–20`）⇒ **C19 轉綠**
｜**關卡目標 6 種全實現**：`survive`（計時 + 每 12s 刷 3–5 隻、距玩家 ≥140px + 整秒 HUD）/
`reach_exit`（最遠地面格 + `tile_exit_portal` loop 精靈 + 24px 觸碰）
｜**9 關目標再平衡** ⇒ 20 關分布 == `levels_target`（`clear_all 5 / kill_elite 4 / kill_boss 3 / survive 3 / collect 3 / reach_exit 2`）
⚠️ **本批新踩 4 坑**（詳見 `IRON-RULES.md` ⑳㉑㉒㉓）：⑳**已釋放節點傳進帶型別標註方法 ⇒ `previously freed` 執行期錯**
（**真實產品 bug**：玩家殺 BOSS 後其火球命中即炸）㉑**headless「等 N 幀」不是時間單位**（計時/淡出須 `create_timer`）
㉒**`z: below_actors` 精靈被 `z_index=0` 背景整層蓋住**（抓圖假陰性）㉓**`match` 的 `_:` 兜底錯誤賦值**
（`reach_exit` 若不顯式 `pass` ⇒ 殺 1 隻怪即過關）
⚠️ **遺留待裁定**：**`boss_ember_lord.level_min 19 → 13` 刻意偏離策劃 §1.1 等級帶表**（表寫 19–20），為讓 C19 轉綠
⇒ 需裁定「改表 or 改回並放寬 C19」；`05-check` **C17**（`ch1_l03/l04` 空 layout，屬 `5-W5-9`）/ **C20**（creatures 目錄數，素材側）仍紅（非本批）
**⇒ 驗收**：`verify_boss_skills`（新建，7 段）· `verify_objectives`（新建，9 段）**皆 0 失敗**；
全量回歸 **74 腳本（+2）/ 254.2s 零新增失敗**；`05 --repo` **84/2**（C7/C19 轉綠）；`b43_shot/` 3 張目視確認。

⇒ **B4-2 已落地**（4 工單）：新建 `data/set_effects/set_effects.json`（**6 條**，與傳奇特効同形但**無 slot/rarity_min**）
｜`ConfigLoader.set_effects` + `_load_set_effect_dir` + `_validate_set_effects`（不查 slot）+ `_validate_set_effect_bindings`（掛 `_cross_validate` §2.9，**依賴 sets 已載入**）
｜`BuffComponent.STAT_ALIAS` 補**同名直通** 5 鍵（`pct_armor`/`pct_attack`/`pct_hp`/`crit_chance`/`elemental_damage`）+ `has_source()`
｜`LegendaryEffectSystem` 加 `register_effect_id()/unregister_key()` + `get_effect()` 兜底 `set_effects` + `on_event` 的 **`require_target_buff`** 條件
｜`SetSystem.get_active_effects()` + `get_progress` tier 補 `effect_name`
｜`LegendaryBus.sync_set_effects()`（差分註冊/註銷，key 前綴 **`set::`**）+ `level_scene` 兩處接線
｜`set_panel.gd` 檔位行改 **HBox 三色**（件數/`【機制名】`/描述，**不另起一行**防溢出）
｜`sets.json` 6 條 description 回填與定義一致
⚠️ **口徑**：套裝特效與裝備特效**共用同一個 `_registry` 與執行器**（不另起總線）；`SetPanel` **尚未掛進真實 UI**（只有工具在用）

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
⚠️ **B3 分 7 小批**（逐批驗收）：B3-1 ✅ → B3-2 ✅ → B3-3 ✅ → B3-4 ✅ → B3-5 ✅ → B3-6 ✅ → **B3-7 ✅（B3 全批收線）**

⇒ **B3-6 套裝徽記 UI 已落地**（1 工單 `2-L15` / 4 檔）：`set_system.gd` 的 `_set_info()` + `get_progress()`
透出 **`emblem_path`**（此前只到 `SetData`/`ConfigLoader` 就斷鏈）｜ `set_panel.gd` 的 `_make_set_row()`
標題行由**單 Label** 改 **`HBoxContainer{TextureRect + Label}`**，徽記走 **`ContentLoader.load_icon(完整 res:// 路徑)`**
（**路線 B 數據驅動直載，不進 `UISkin` TEX 表** —— 徽記在 `assets/sprites/items/` 不屬 `CLASS_UI`）
｜ `game_constants.gd:541` **`SET_EMBLEM_SIZE` 16 → 48**（素材實測 48×48；16 渲染為 1/3 非整數縮放違反美術規範 §1.1）
｜ `verify_set_system.gd` 修 **`:187` 脆弱斷言**（`get_child(0)` 已由 `Label` 變 `HBoxContainer`）+ 加 **6 條徽記斷言**
**成果**：修「**3 張徽記白做**」（素材/sets.json/SetData/ConfigLoader 全通但 **UI 零消費、零報錯**）；
`set_preview` 目視確認 3 徽記 48×48 正確顯示
⚠️ **本批新踩 1 坑**（詳見 `IRON-RULES.md` ⑫）：**「生成但沒人消費」的靜默鏈路** —— 數據鏈路「上半截通了」≠ 有消費點，
驗收看**末端渲染**；且**改 UI 子節點結構前必先 grep verify 的「按子節點序號取值」硬斷言**
⚠️ **遺留**：本批完整閉環、無新遺留

⇒ **B3-7 校驗補齊 已落地**（B3 收尾批 / 4 檔）：官方列 11 條 `2-V*`，但 **`2-V6/V10/V11/V14` 已於 B3-2/B3-3 落地**
⇒ **本批實際補 7 條**：`verify_equipment.gd` +**V1**（詞綴 == 48）+ **H 段 V7b**（底材 `base_stats` 白名單 + 禁 legacy 鍵，146 鍵）
｜ **新建 `verify_affix_pool.gd` + `.tscn`**：**V2** 孤兒 0 / **V3** 死池 0 / **V4** 通用池無 `min_rarity≥3`（**WARN 級**）
/ **V5** 新增 15 條每條 ≥2 池 ｜ `verify_affix_roller.gd` +**H 段 V7**（`armor_pierce` + legacy 殘留 0）
⚠️ **本批新踩 2 坑**（詳見 `IRON-RULES.md` ⑬⑭）：⑬**工單 `title` 與 `verify` 欄位可能不一致 ⇒ 以 `title` 為準**
（`2-V5` title「每條 ≥2 池」vs verify 欄「02-check A3」語義完全不同，Python 側無對應檢查）
⑭**WARN 級斷言須另立 `_warn()`**（`_ok()` 只計 `_fail`，回歸只數 `[FAIL]` ⇒ WARN 不污染判定）
**成果**：全量回歸 **70 腳本（+1 新腳本）/ 零新增失敗**；策劃 7 校驗器與 B3-6 基線一致
⚠️ **遺留**：**無** —— **B3 7 小批全數收線**

⇒ **B4-1 臨時增益系統 已落地**（4 工單 `3-B1`~`3-B4` / 16 檔）：**新建 `BuffComponent`**（獨立節點，
玩家/敵人各一；`STAT_ALIAS` 別名表 8 種 stat 名 / 疊層+刷新並存 / 到期 `_prune` / `changed` 信號 /
無增益自關 `_process`）｜ **`StatCalculator.FINAL_KEYS` 52→53**（新增 **`all_damage`**，
`PlayerController.get_damage_bonus()` 併入 `compute_hit` 第 5 形參 ⇒ 物理 + 元素皆受益）
｜ `HealthComponent` 內接 **移速 / 減傷**（不進計算器，防雙重計入）+ **限時盾** `grant_shield(amount, duration=0)`
｜ `EnemyBase` `get_armor()` 減甲 / `_move_speed()` 減速 ｜ `LevelScene` 把 `BuffComponent.to_calculator_buffs()`
**併入**（非取代）`RunBuffSystem` 的 buffs + `changed` ⇒ 重算屬性
｜ **`LegendaryBus` 補 4 執行器**（`buff_stat`（含 `target=enemy`）/ `ms_boost` / `damage_reduction` / `summon`）
⇒ **第二期 16 條特效全通電** ｜ `Summon.DEFS` 補 `ghost`/`echo_copy`（此前**缺定義 ⇒ 靜默變靈狼**）
+ `spawn` 支援 `lifetime`/`atk_ratio` 覆寫 + **存活上限 4** ｜ **BUFF 型技能改道**（新增 `GameConstants.BUFF_DEFS`
7 條；移除 B0 過渡的 `PENDING_FORM_IMPL`/`_warn_pending_forms`/`_find_run_buff_system`）
｜ **新建 `BuffBarUI`**（3-B4 HUD，24px×6 槽 + 剩餘豎條 + 疊層/秒數；**素材 12 張未生產 ⇒ 佔位繪製**）
⚠️ **本批新踩 3 坑**（詳見 `IRON-RULES.md` ⑮⑯⑰）：⑮**測試殘留狀態污染**（`grant_shield` 到期取 `maxf`
⇒ 同實例疊時長會假紅，邊界測試須用獨立實例）⑯**格式化字串裡的 `%` 要寫 `%%`**（否則
`unsupported format character`）⑰**`Dict.get(id, default)` 的缺省兜底會掩蓋 id 拼錯**（消費端須先 `has()` 守門）
⚠️ **遺留**：①`ms_boost.element_attach`（裂界指環附元素）未接線 ②`ghost`/`echo_copy` 無精靈素材（走佔位）
③增益圖標 12 張仍為 0（設計案 §六 P0）④`extra_loot` 未強制 `loot_quality`（B3-4 遺留）⑤~~套裝特效未接~~（**B4-2 已接**）
⑥**`SetPanel` 尚未掛進真實 UI**（全庫只有 `set_preview`/`capture_set_panel` 兩個工具在用）⑦套裝專屬特效視覺 6 套未生產（設計案 §六 P1）
**⇒ 驗收**：`verify_buff`（新建，7 段 72 條）**0 失敗**；全量回歸 **71 腳本（+1）/ 零新增失敗**；
`buff_shot/` 4 張目視確認（與技能欄不重疊）；策劃 7 校驗器與 B3-7 基線逐條一致。

⇒ **B4 分 6 小批**（用戶裁定，逐批驗收）：**B4-1 ✅** → **B4-2 套裝特效 ✅** → **B4-3 BOSS+關卡目標 ✅** → **B4-4 技能擴展 UI（`1-L8`~`1-L14`）** → B4-5 元素深化（`3-E7`/`3-E8`） → B4-6 校驗補齊（`1-V7`~`1-V9` + 坐實 5 條已落地）。

⚠️ **B4 摸底結論（28 工單，**5 條已落地**，勿重做）**：`1-L5`（`summon.gd` 完整）/ `1-L6`（`target_group`）/
`1-L7`（`hit_query` 跳過 `summons`）/ `3-E6`（`get_element_damage_bonus`）/ `3-B2`（介面已備，B4-1 已補產出方）。

（明細見 `.workbuddy-ai/memory/2026-09-29.md` §五）

⚠️ **留給各自批次的預存回歸紅**（用戶已裁定本輪不動）：**3 檔 4 項** —— `verify_choice_panel` 裸 Color 1
（命中在 `level_scene.gd`，非驗證批所引入）／`verify_player` 手柄映射 1 ／`self_check` 怪物 L20 舊值 2
（→ B6 `4-W5-e`）。`verify_skill_panel` 的 `save_version==3` 殘餘**已隨 B4-4 升版消失**。
（另：`verify_juice` 的「普通飄字亮白」1 項已於 **B4-6** 修正，見上方㉟。）

⚠️ **git**：09-28 backlog 5 天已補提交（`8801219`/`61322b8`/`d27c31e`/`ef604aa`），B0/B1/B2/B3-1…B3-7/B4-1…B4-6/B5-1 各另起 commit（**最新 `3772f00`**，B5-1）。

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
