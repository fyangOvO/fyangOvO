# 交接文件 HANDOFF-E（符文掉落接線批次 · B6 `2-L12` / `2-V12`）

> 日期：2026-09-30 ｜ 分支：`main` ｜ 前置：HANDOFF-D（符文圖標 v2）
> 本批把「**符文從哪來**」接上 —— 在此之前 `roll_rune_drop()` **零呼叫方**、
> `unlocked_runes` 在真實遊玩路徑**零寫入方** ⇒ 剛打磨好的符文圖鑑實機永遠 **0 / 24**。

---

## 1. 本批次做了什麼

| # | 改動 | 檔案 |
|---|---|---|
| 1 | `LootTable` 新增 `rune_drop_chance`（+ `validate()` 範圍檢查） | `resources/loot_table.gd` |
| 2 | `ConfigLoader` 補讀 `rune_drop_chance`（**原本沒讀 ⇒ 靜默脫鉤**） | `scripts/autoload/config_loader.gd` |
| 3 | 重寫 `roll_rune_drop()`：改讀表、收 `MonsterData`、加 `all_rune_ids()` / `rune_duplicate_material_amount()` | `scripts/loot/loot_roller.gd` |
| 4 | 怪物死亡接上符文桶（抽 `_spawn_loot_drop()` 消除重複落地邏輯） | `scripts/enemies/enemy_base.gd` |
| 5 | 地面符文物件：紫罗兰光柱 + **真实符文图标**（20px 世界尺寸） | `scripts/loot/loot_drop.gd` |
| 6 | 玩家拾取：**首获永久解锁** / **重复转魔石** | `scripts/player/player_controller.gd` |
| 7 | 拾取提示条：`解锁符文：X` / `重复符文 X → 魔石 +N` | `scripts/ui/pickup_toast.gd` |
| 8 | 校驗：`verify_loot_tables` F 段（2-V12）+ `verify_loot` H/I 段 | `tools/verify_loot_tables.gd`、`tools/verify_loot.gd` |
| 9 | 掉落预览工具：符文行 + **修好「所有掉落物在画面外」的既有 bug** | `tools/loot_preview.gd/.tscn` |

### 1b. 第二輪（遺漏掃描「繼續往下做」時挖出來的）

| # | 改動 | 檔案 |
|---|---|---|
| 10 | **策劃自相矛盾**：`01-技能体系.md §11.4` 寫普通怪 0%，而 `02-装备属性.md §6.1` + JSON + 校驗器全寫 0.02 ⇒ 保留 2%，回頭同步 §11.4（節奏重算 + 收集者問題說明） | `01-技能体系.md`、`02-装备属性.md`、`02-check_affix_pool.py`、`07-dev-tasks.json`、`07-开发总表.md` |
| 11 | **技能面板不看得解鎖狀態** ⇒ 未解鎖符文照樣能裝（掉落變擺設）：`hub` 注入 `unlocked_runes`，picker 灰顯不可選 | `scripts/core/hub.gd`、`scripts/ui/skill_panel.gd` |
| 12 | 圖鑑進度文案**硬編碼**「精英 8% · BOSS 25%」漏了普通 2% ⇒ 改**從掉落表實時讀** | `scripts/ui/rune_codex_panel.gd` |
| 13 | 校驗：`verify_skill_equip` 新增 F 段（5 項）、`verify_skill_ext` 新增文案斷言 | `tools/verify_skill_equip.gd`、`tools/verify_skill_ext.gd` |
| 14 | 端到端抓圖工具修「**截到凍結畫面**」+ 加 e-7（技能面板未解鎖灰顯） | `tools/capture_rune_drop.gd/.tscn` |
| 15 | 新增診斷工具 `capture_gold_btn`（按鈕九宮格高度階梯） | `tools/capture_gold_btn.gd/.tscn` |
| 16 | **修金按鈕 24px 破相**（目視 e-7 時發現的既有破相，用戶裁定「改用 128×24 平面金」）—— 見 §6 | `ui_theme.gd`、`main_menu_panel.gd` + 重跑 `gen_ui_theme` 落盤 `theme.tres` |
| 17 | 全部受影響截圖**重拍**（舊圖拍的是舊 `theme.tres`，按新鐵律 53 一律作廢） | `c_review_shot/` 5 張 + `e-3…e-8` |

---

## 2. 符文掉落全链路（本批后的真实数据流）

```
怪物死亡
  └ EnemyBase._drop_loot()
      ├ LootRoller.roll_loot(...)        ← 主掉落（金币/材料/消耗品/装备），受 drop_chance 触发
      └ LootRoller.roll_rune_drop(data, level)  ← 【本批新增】第二次**独立** randf，读表 rune_drop_chance
      └ _spawn_loot_drop(entry) × N      ← 统一落地（instantiate / setup / 撒点 ±14px / rare emit）
            └ LootDrop._draw()  "rune" 分支：紫罗兰光柱(28) + UISkin.rune_icon(item_id) 缩到 20×20
                  └ 玩家走近 ≤ PICKUP_RADIUS(24) 且 age ≥ LOOT_POP_DELAY(0.25)
                        └ PlayerController.pickup_loot(entry) → _pickup_rune(entry)
                              ├ 未解锁 → data.unlocked_runes.append(rid)   ← **永久**，分解/死亡不回收
                              └ 已解锁 → materials += rune_duplicate_material_amount(item_level)
                              └ 结果写回 entry：rune_new / material_amount
                        └ EventBus.loot_picked_up.emit(payload)   ← 与上面**同一个 Dictionary 引用**
                              └ PickupToastHUD.spawn()  "rune" 分支读 rune_new 组文案
```

**存档持久化**：写入的是 `SaveManager.current_data.unlocked_runes`，与 `obtain_unique()` 同路径 ——
由关卡结束时 `level_scene.gd:1703` 的 `SaveManager.save_to_slot()` 落盘，**无需额外调用**。

---

## 3. 三个已拍板的设计口径

### 3.1 三档全接（读表，不写死）
`rune_drop_chance`：**普通 0.02 / 精英 0.08 / BOSS 0.25**（深渊表 `abyss_loot_tables.json` 另为 0.05 / 0.30，随表读）。
符文是**第二次独立 roll** —— 命中**不会**挤掉金币/材料/装备那一次判定，两者可同时出现（「双响」）。
> ⚠️ 旧实现的 `RUNE_DROP_CHANCE := {"elite": 0.08, "boss": 0.25}` 已删除：它收 `tier: String`，
> 而调用侧只有 `MonsterData.Tier`（int）⇒ 即使接上也会恒取 0（见铁律 ㊽）。

### 3.2 拾取端判定「首次解锁 / 重复转魔石」
**roll 端不做任何过滤**（重复符文照常掉出）。理由：
- 忠于策划 §11.4「首次获得即永久解锁，之后重复掉落自动转化为魔石（避免垃圾堆积）」；
- 符文桶**永远有效** —— 24 个全解锁后仍持续产出魔石，不会退化成空桶（若在 roll 端过滤未解锁，后期会变成「掉空」）。

**转化量口径 = 与材料掉落完全一致**（`1 + (L-1)/5`，至少 1）⇒ 一颗重复符文 ≈ 一次材料掉落。
不另立一套数值，避免两处常量各自漂移（铁律 ㊺）。实现为 `LootRoller.rune_duplicate_material_amount(level)`。

### 3.3 地面用真图标（20px）
`UISkin.rune_icon(item_id)` 就是图鉴那张 `rune_icon_*_48.png`，缩到 **20px** 世界尺寸
（装备方块是 12px，金/材料 8px ⇒ 20 是同一视觉量级的上限；再大会盖住光柱、密集掉落时糊成一团）。
缺档时兜底成紫方块（`UISkin` 缺档静默回 null，不兜底就只剩一根光柱）。

### 3.4 未解锁的符文**不能装配**（第二輪補上）
只把「掉落 → 图鉴」接通还不够：技能面板的符文选择器原本**遍历全部 24 个**，未解锁的也能插上
⇒ 图鉴只是计数器，「掉落」对玩法毫无意义。现在 `hub._skill_panel_ctx()` 注入 `unlocked_runes`，
选择器三档灰显**优先显示「未解锁」**（未解锁 > 不适用形态 > 同组互斥），文案「（未解锁 · 需掉落获得）」。

门槛写法与技能解锁**同一套**：`_rune_unlock_enforced = p_ctx.has("unlocked_runes")` ——
**看键在不在，不看值**。旧调用 / 无头测试不传该键 ⇒ 全放行（向后兼容，`verify_skill_equip` A~E 段不受影响）。

---

## 4. 验收

| 项 | 结果 |
|---|---|
| 全量回归 `run_regression.py` | **77 脚本全绿 / 189.9s / exit 0** |
| `verify_loot_tables` F 段（2-V12） | 三表逐位 `0.02/0.08/0.25` + 全表 `[0,1]` + `validate()` 通过 |
| `verify_loot` H 段 | 4000 次/档实测命中率 **0.021 / 0.079 / 0.246**（期望 0.02/0.08/0.25）；条目字段合法；四象限独立性 |
| `verify_loot` I 段 | 首获写入 1 枚 / 不产魔石；重复不重写 + 转魔石 ×2；载荷写回两态；提示条消费 rune |
| `verify_loot` F 段实测 | BOSS 秒杀后地面 **主掉落 2 件 + 符文 1 枚**，走近拾取 → `[Loot] 解锁符文 rune_swift（图鉴 1 枚）` |
| 掉落预览抓图 | `game/build/loot_preview.png` + `loot_preview_runes_4x.png`（4× 最近邻放大逐像素目视） |
| 策划侧 | `02-check_affix_pool.py` 14/0 ｜ `07-check_dev_tasks.py --repo` 212/0 ｜ `01-check_skill_dps.py` 27 条全在区间 |

**第二輪复跑（2026-09-30）**

| 项 | 结果 |
|---|---|
| 全量回归 `run_regression.py` | **77 脚本全绿 / 182.3s / exit 0** |
| `verify_skill_equip` F 段 | 5/5 —— 无 `unlocked_runes` ⇒ 全放行；带 `["rune_swift"]` ⇒ swift 可选 / rune_fire disabled + 文案含「未解锁」；空集 ⇒ 24 条**全部**不可选 |
| `verify_skill_ext` 文案断言 | 进度文案含「普通 2% / 精英 8% / BOSS 25%」（从表实时读） |
| `capture_rune_drop` 端到端 | **0 项失败 / 8 张截图**，每张都比上一张「画面不同」（防冻结画面断言生效） |
| 策划侧复跑 | `02-check` 14/0 ｜ `07-check --repo` 212/0 ｜ `01-check` 27 条全在区间 |

---

## 5. 附帶修復：掉落预览工具「拍不到东西」

`tools/loot_preview.tscn` 原本把 **10 个掉落物全摆在 `y = -80`**，而相机 `zoom = 2.5` + 视口 640×360
⇒ **可见世界范围只有 256×144（`y ∈ [-72, 72]`）**，那一排从头顶出画。
它被当成「掉落视觉验收依据」沿用了好几批 —— 因为 PNG 有产出、`err=0`、没人**数过图里有几个目标**。

本批重排为两行（都在可见范围内）：装备/金币/魔石行 `y = 0`（x 从 -117 到 117，步长 26），
符文行 `y = 50`。**改 zoom 时必须重算可见世界矩形再摆位**（见铁律 ㊾）。

---

## 6. ⚠️ 目视验收时发现的既有破相：金色按钮在 24px 下「金线横穿文字」（**已修**）

**怎么发现的**：本批目视 `e-7-技能面板-未解锁符文灰显.png` 时，符文选择器里 **26 颗按钮全部**
「文字被一条金线划掉」。这不是本批改动引入的，但此前**没有任何一张截图看过金按钮的真实尺寸**。

**根因（已用控制变量渲染证实）**：

- `ui_theme.gd` 把 Button 五态**全部**指向 `UISkin.button_stylebox_gold()` = 华丽雕花 `btn_gold.png`(432×92)，
  `texture_margin_top/bottom = 14`。
- 该素材的上下金线在**源 y=10 与 y=82/86**（实测：y=10 有 227/280 像素是亮金）。
- 按钮高度 < 28 时上下带重叠；高度 < ~40 时金线落进按钮垂直中央 ⇒ **正好压在文字上**。
- 而**默认按钮高度就是 ~24px**（字体 12 + `content_margin` 6/6）⇒ 所有**没有**用
  `UISkin.btn_styleboxes()` 覆写的裸 `Button` 全部中招。

**证据**：`game/tools/capture_gold_btn.gd/.tscn` 把 24/28/32/40/48 五档并排渲染
→ `deliverables/gstack/e_loot_shot/e-8-按鈕九宮格-高度階梯診斷.png`。
**h=24/28/32 全破相；h=40 起才干净；h=48 完全正常。**

**影响面**（`grep -c "Button.new()"` vs `btn_styleboxes`）：`scripts/` 下 **40 处** `Button.new()`，
只有 **11 处** `btn_styleboxes()` 覆写。裸按钮集中在
`skill_panel`（9 处，含符文选择器 26 颗）、`rune_codex_panel`、`choice_panel`、`result_panel`、
`shop_panel`、`talent_panel`、`main_menu_screen`。

**为什么没人发现**：HANDOFF-C 的 `c_review_shot/*.png` 拍于 **16:08–16:09**，而
「金按钮真的上线」（重跑 `gen_ui_theme` 落盘 `theme.tres`）在 **16:24** 的提交里
⇒ **那 5 张截图拍的是旧 theme.tres**（当时按钮是平面金，看着很正常）。
这正是铁律 ㊾「验收工具自己没被验收」的第二次复发。

### 6.1 修法（用户裁定「A · 改用 128×24 平面金」）

**一句话：素材尺寸即用途契约 —— 24px 的按钮就用为 24px 设计的素材。**

| 落点 | 改动 |
|---|---|
| `scripts/ui/ui_theme.gd` §4 | Button 五态改走 `UISkin.btn_styleboxes("gold")`（`btn_gold_normal/hover/pressed_128x24.png`）；`focus` = hover；`disabled` = 同贴图 + **`modulate_color` 压暗**（`StyleBoxTexture` 没有 alpha 字段，新增 `_dim()` 帮手；写成别的参数 = 改了不生效的假参数） |
| `scripts/ui/main_menu_panel.gd` | 全局唯一的「英雄按钮」位（`BTN_SIZE = 256×48`，**48px 足够**）⇒ `kind == "gold"` 走**雕花** `button_stylebox_gold()`，`hover/pressed` 用 `_tint()`（`modulate_color` 0.92/0.78）派生（素材只有一态，不派生就没有点击反馈） |
| 同上 · **文字色** | ⚠️ 踩到第二个坑：雕花框**中央是暗底**，而金按钮原字色是深字 `0B0D10` ⇒ 「开始游戏」四个字**整颗隐形**。已改为「只有**平面**金底才压深字，雕花配 `UI_TEXT_BRIGHT`」 |
| `game/tools/gen_ui_theme.tscn` | **必须重跑**落盘 `theme.tres`（否则游戏挂的还是旧主题，本处改动静默失效）；回读校验已通过 |
| `deliverables/gstack/c_review_shot/*.png` | **全部重拍**（旧图拍于 16:08，是**旧 theme.tres** ⇒ 按铁律 53 一律作废；旧图已 `mv` 到 `.workbuddy-ai/trash/2026-09-30-舊診斷圖與過期截圖/`） |
| `e-8-按鈕九宮格-高度階梯診斷.png` | 改为**两组对照**：A 全局 Button（128×24）@24/28/32/40/48 **全干净**；B 雕花 @24 **仍破相** / @48 完美 ⇒ 同时是「修好了」与「雕花不能下放」的双重证据 |

**验收**：`verify_ui` / `verify_ui_assets` / `verify_ui71` / `verify_panel_unify` / `verify_hub` / `verify_skill*` 共 11 脚本全绿（26.6s）；
全量回归见 §4。目视：`c-1-主菜單.png`（雕花「开始游戏」+ 暗色次级按钮的层级）、`e-7`（符文选择器文字全部可读）。

---

## 7. 遗留（**不在本批范围**，但已定位）

| 项 | 说明 | 归属 |
|---|---|---|
| `material_sub_weights` / `item_level_spread` | JSON 有、`LootTable` **没有字段**、`ConfigLoader` **没读** ⇒ 两个死字段 | `2-D6` 剩余部分 |
| `item_level_spread` 与实现矛盾 | 代码 `_roll_item_level()` 用硬编码 `ITEM_LEVEL_JITTER = 2`（±2）给**所有档位**；而 JSON 写 BOSS 是 `min_mod 3 / mode_mod 5 / max_mod 8` ⇒ BOSS 本应掉 iLvl+5 左右 | `2-L13` / `2-V13` |
| 深渊表的 `rune_drop_chance`（0.05/0.30）**当前不会被消费** | `roll_rune_drop` 与 `roll_loot` 一样只走 `ConfigLoader.LOOT_TABLE_BY_TIER`（按 `MonsterData.Tier`），深渊表要经 `LevelData.loot_table_id` 才用得上（只有 `roll_guaranteed_equipment` 支持） | 待裁定 |
| 符文图鉴**不会在局内实时刷新** | 图鉴在据点，`hub.gd` 每次进入重新 `bind(data.unlocked_runes)` ⇒ 回据点即更新，无需信号 | 无（设计如此） |
