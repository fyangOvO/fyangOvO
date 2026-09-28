# 第五步 · 怪物 · 关卡 · BOSS 扩充

> **文档性质**：策划文本（不含任何工程代码改动）。凡涉及 `game/` 下代码或数据的修改，
> 一律以**工单**形式在本文档中指明方向（改哪个文件、哪一行、改成什么、为什么、怎么验收），
> 由工程侧执行。
>
> **前置**：`01-技能体系.md` / `02-装备属性.md` / `03-装备特色玩法.md` / `04-数值与数据模型.md`
> **本步目标**：把「4 处结构性缺口」补齐 —— ① **ai_id 定义了 6 种但零实现**
> ② **怪物等级覆盖在 L13+ 塌缩** ③ **BOSS 技能只消费 4 条中的 2 类** ④ **地图与目标类型单一**。
> 并承接第四步路线 A 的「预算 120→440」重排、手绘关 `'m'` 标记、装备池 iLvl 22 的落地需求。
>
> **版本**：v1.1 ｜ 2026-09-24 ｜ 状态：**已拍板（D1–D5 全部裁定）**

---

## 目录

- [〇、本步结论速览（先读这一页）](#〇本步结论速览先读这一页)
- [一、现状实测基线](#一现状实测基线)
  - [1.1 怪物：16 种，但等级覆盖在 L13+ 塌缩](#11-怪物16-种但等级覆盖在-l13-塌缩)
  - [1.2 AI：定义了 6 种 `ai_id`，实现 0 种](#12-ai定义了-6-种-ai_id实现-0-种)
  - [1.3 关卡：20 关，4 手绘 + 16 程序化](#13-关卡20-关4-手绘--16-程序化)
  - [1.4 ⚠️ `total_monster_budget` 只是埋点，不驱动刷怪](#14-️-total_monster_budget-只是埋点不驱动刷怪)
  - [1.5 BOSS：2 个配置完整，但技能只消费 2 类](#15-boss2-个配置完整但技能只消费-2-类)
  - [1.6 目标类型：6 种定义，4 种实现](#16-目标类型6-种定义4-种实现)
  - [1.7 精灵素材：4 方向而非 8 方向](#17-精灵素材4-方向而非-8-方向)
- [二、五处结构性缺口（诊断）](#二五处结构性缺口诊断)
- [三、修复方案](#三修复方案)
  - [3.1 修复一：AI 行为落地（6 种）](#31-修复一ai-行为落地6-种)
  - [3.2 修复二：怪物扩充与等级覆盖](#32-修复二怪物扩充与等级覆盖)
  - [3.3 修复三：关卡重排](#33-修复三关卡重排)
  - [3.4 修复四：BOSS 扩充与技能接线](#34-修复四boss-扩充与技能接线)
  - [3.5 修复五：目标类型与地图多样性](#35-修复五目标类型与地图多样性)
- [四、怪物扩充表（目标）](#四怪物扩充表目标)
- [五、关卡重排表（目标）](#五关卡重排表目标)
- [六、BOSS 设计表（目标）](#六boss-设计表目标)
- [七、工程工单](#七工程工单)
- [八、素材工单](#八素材工单)
- [九、与前后步的衔接](#九与前后步的衔接)

---

## 〇、本步结论速览（先读这一页）

**一句话**：第四步解决了「数字能不能跑」，本步解决「**内容够不够撑**」。
实测发现 **4 处结构性缺口 + 1 处语义误解**，其中**最严重的一条是 `ai_id` 完全没实现** ——
怪物数据里写了 6 种 AI 行为（`melee_chaser` / `ranged_kiter` / `erratic_chaser` / `lobber` /
`melee_charger` / `boss_phased`），但**全仓 0 处分支**，所有怪物跑的是**同一套「直线追人」逻辑**
⇒ 16 种怪在**行为上只有 1 种**。

### 五处缺口总表

| # | 缺口 | 量化症状 | 严重度 | 修复档 |
|---|---|---|---|---|
| **1** | **`ai_id` 零实现** | 数据定义 **6 种**行为，代码 **0 处分支**；`ranged_kiter`/`lobber` 等 5 种**形同注释** | 🔴 P0 | 工程档（`enemy_base.gd`） |
| **2** | **怪物等级覆盖塌缩** | L1–12 有 **6–7 种**普通怪可选；**L17–20 只剩 `frozen_husk` 1 种**；精英 L1–4 **完全没有**；**暗影元素 0 只** | 🔴 P0 | 策划档（`monsters.json`） |
| **3** | **BOSS 技能只消费 2 类** | 配置写 4 类技能（slam/summon/aoe/enrage），代码**只识别 summon + aoe**；`fireball`/`bone_slam`/`enrage` 是**死数据**；`enrage` 只折算成倍率、**无独立行为** | 🟠 P1 | 工程档（`enemy_base.gd`） |
| **4** | **目标类型 6 定义 4 实现** | `survive` / `reach_exit` **未实现** ⇒ 用了会**静默降级**为「清空全部敌人」；20 关实际只用了 **4 种** | 🟠 P1 | 工程档 + 策划档 |
| **5** | **地图与关卡形态单一** | 20 关中 **16 关程序化**，且参数高度同构（宽 44–58 / `room_count` 10–17 / 密集度 0.05–0.09）；`ch1_l03/l04` **连 layout 参数都没有**（走默认值） | 🟡 P2 | 策划档（`chapter*.json`） |

### ⚠️ 本步最重要的一个「语义误解」（比缺口本身更容易踩）

> ### `total_monster_budget` **不驱动刷怪**，它只是埋点。
>
> **实测证据**：
> - `level_scene.gd:411` 是**唯一**消费点，用法是 `CombatMetrics.begin_run(..., int(_level_def.total_monster_budget), _alive.size())`
>   —— 把预算作为**观测值**记录，**不参与任何生成决策**（注释原文：「纯观测，不参与任何判定」）
> - 程序化刷怪数来自 `level_generator.gd:478-485` 的
>   `n = rng.randi_range(count_min, count_max)`，**Σ 的是 `count_*`，不是 `budget`**
> - 20 关里 **17 关 `budget ≠ Σcount_max`**（最大差 **+19**：`ch3_l15` budget=60、Σmax=41）
>   ⇒ 若把 budget 从 60 提到 283 而不动 `count_*`，**实际刷怪数一只都不会变**
>
> **⇒ 第四步路线 A 的「预算提到 120→440」若只改 `total_monster_budget`，将得到一个
> 「报表好看、实际没变」的假修复。这与第四步的「提预算不修落差」是同一种病：
> 改了一个**不被消费的字段**。**
>
> **两条出路（见 §3.3）**：
> - **路线 ① ✅ 已拍板**：**改 `count_*`**（这是**真正**的刷怪源），`budget` 顺带对齐 ⇒ 单局时长真的变长
> - **路线 ②（不执行，降为 P3）**：**让 `budget` 真正驱动刷怪**（改代码，把 `count_*` 降级为权重/形状）
>   ⇒ 需要工程改动，但一劳永逸（以后调密度只改一个数）

> ✅ **D2 裁定：走路线 ①**。⇒ 本步只改数据、不动 `level_generator.gd`；
> 路线 ② 的工单 W5-12 **降级为 P3 可选、本步不执行**。

### ✅ 第四步路线 A 的落地需求（本步承接）

| 承接项 | 第四步给出 | 本步落地方式 |
|---|---|---|
| 预算 120→440（合计 5,660） | 目标序列 | ⚠️ **须同时改 `count_*`**（见上） |
| 手绘关 `'m'` 标记数 | 需提到目标预算 | 4 关的 `m` 需从 23/48/41/32 提到 **~55/72/88/110** 量级 |
| 装备池 iLvl 22 | `item_level_max` ≤20 → 22 | 本步**不需新怪**即可支撑（怪等级只到 20） |
| 怪物成长率 1.12/1.12 | 已拍板 | 本步怪物 `hp_scale`/`damage_scale` 需**按新曲线复核** |

### 本步产出清单

| 文件 | 内容 |
|---|---|
| `05-怪物关卡BOSS.md` | 本文档 |
| `05-monsters.json` | 怪物扩充草案 + 等级覆盖矩阵 + `ai_id` 行为契约（6 种行为 + 9 个新字段） |
| `05-levels.json` | 20 关重排（真刷怪数 / budget 语义 / layout.pattern / objective） |
| `05-bosses.json` | BOSS 技能接线状态 + 差异化 + 新 BOSS 草案 |
| `05-check_monster_level_boss.py` | 校验脚本（A 组 40 自洽 + B 组 9 覆盖复算 + **D 组 17 拍板落地** + C 组 20 工程漂移检测） |

**校验结果**（2026-09-24 实测，脚本已加入 **D 组：D1–D5 拍板落地** 17 条断言）：

| 口径 | 结果 |
|---|---|
| 不带 `--repo`（纯策划自洽） | **66 通过 / 0 失败**（A 40 + B 9 + D 17） |
| 带 `--repo D:/七傳說`（+工程漂移） | **80 通过 / 6 失败** |

> 6 项失败**全部是已登记的工单**，无意外：C5（W5-1 `ai_id` 0 分支）、
> C6（W5-2 缺 9 字段）、C7（W5-5 缺 `bone_slam`/`fireball`/`enrage`）、
> C13（W5-4 `budget≠Σcount_max` 17 关）、C17（W5-9 空 layout 2 关）、
> C19（W5-6 BOSS 等级区间矛盾）⇒ **断言能精确抓到缺口，而非泛泛全绿**。
>
> ✅ **D 组 17 条全通过**：D1–D5 五项裁定值、`decisions_pending` 已清空、
> 三份 JSON 的 `status` 已标「已拍板」、`new_boss_draft.execute` 仍为 `false`、
> 目标行 `budget == Σcount_max` 20/20、目标类型 6 种全用（`survive` 3 / `reach_exit` 2）、
> 新增怪 8 只、分期表已标「不作执行」。

### ✅ 拍板结果（2026-09-24 用户裁定 · 5 项全取推荐值）

| # | 决策 | **裁定** | 落地路径 |
|---|---|---|---|
| **D1** | `ai_id` 6 种行为：全做还是分期？ | ✅ **一次做全 6 种** | W5-1 + W5-2（同批） |
| **D2** | `budget` 与 `count_*` 的关系？ | ✅ **路线 ①：改 `count_*`**（不动代码） | W5-4（**与第四步 W2 同批**） |
| **D3** | 怪物扩充到多少种？ | ✅ **16 → 24（+8）** | W5-3 |
| **D4** | 是否新增 BOSS？ | ✅ **不新增**；改做「召唤流 vs 法术流」差异化 | W5-5 + W5-6 |
| **D5** | 补 `survive` / `reach_exit` 吗？ | ✅ **两种都补** | W5-7 |

**裁定带来的三处口径收口**：

1. **D1 全做** ⇒ 原 §3.1 的「分期表（一期 `ranged_kiter`+`lobber` / 二期 `melee_charger`+`erratic_chaser`）」
   **永久不执行**，仅作存档。`boss_phased` 也在本次范围内（虽然它只是标签，但既然全做就一并落）。
2. **D2 路线 ①** ⇒ 路线 ② 的工单 **W5-12 降级为 P3 可选、本步不执行**；
   `05-levels.json` 的 `levels_target.rows` 即最终落地值。
3. **D4 不新增** ⇒ `05-bosses.json` 的 `new_boss_draft.execute` **永久 `false`**；
   `boss_frost_monarch` **不进素材工单**（§8.2 的 84 帧不计入本步素材总量）。

> 📌 **本表的权威机器可读副本**：`05-monsters.json` → `decisions_2026_09_24`
> （`05-levels.json` / `05-bosses.json` 各有一份分项记录）。改决策请改 JSON，本表随动。

---

## 一、现状实测基线

> 全部数据由 `game/data/` 实测读取（见 `05-check_monster_level_boss.py` 的复算输出）。

### 1.1 怪物：16 种，但等级覆盖在 L13+ 塌缩

**总数 16**（普通 10 / 精英 4 / BOSS 2）。**等级带宽 `level_min`–`level_max`**：

| id | 名称 | 档位 | 等级带 | `ai_id` | 元素 | XP |
|---|---|---|---|---:|---|---:|
| `spider_cave` | 洞穴蛛 | normal | 1–6 | `melee_chaser` | physical | 10 |
| `bat_swarm` | 蝠群 | normal | 1–8 | `erratic_chaser` | physical | 9 |
| `skeleton_warrior` | 骸骨战士 | normal | 2–12 | `melee_chaser` | physical | 14 |
| `warg_dark` | 暗狼 | normal | 2–9 | `melee_chaser` | physical | 15 |
| `slime_acid` | 酸液史莱姆 | normal | 3–10 | `lobber` | poison | 12 |
| `mushroom_spore` | 孢子菇 | normal | 3–9 | `lobber` | poison | 13 |
| `imp_hellfire` | 烬火魔精 | normal | 7–14 | `ranged_kiter` | fire | 22 |
| `golem_ember` | 烬石魔像 | normal | 8–16 | `melee_charger` | fire | 26 |
| `hound_ash` | 灰烬猎犬 | normal | 9–16 | `erratic_chaser` | fire | 24 |
| `frozen_husk` | 冻骸 | normal | 14–20 | `melee_chaser` | cold | 40 |
| `brute_butcher` | 屠夫 | elite | 5–20 | `melee_charger` | physical | 90 |
| `wraith_frost` | 霜怨灵 | elite | 8–20 | `ranged_kiter` | cold | 95 |
| `pyromancer_cultist` | 烬焰信徒 | elite | 10–18 | `ranged_kiter` | fire | 120 |
| `ice_wraith` | 冰魄 | elite | 15–20 | `ranged_kiter` | cold | 150 |
| `boss_bone_tyrant` | 骸骨暴君 | boss | 6–7 | `boss_phased` | physical | 900 |
| `boss_ember_lord` | 熔心之主 | boss | 19–20 | `boss_phased` | fire | 3200 |

> ⚠️ **本表已按 `monsters.json` 实测修正**（初稿有 5 处 `ai_id` / 名称 / 等级带错误，
> 例如 `bat_swarm` 实为 `erratic_chaser` 而非 `ranged_kiter`、
> `slime_acid` 实为 `lobber`、`pyromancer_cultist` 实为 `ranged_kiter` 而非 `lobber`）
> ⇒ **教训：策划案里的数据若靠记忆或转述，必然漂移**。一切以 `05-check_monster_level_boss.py` 的复算输出为准。

#### 🔴 覆盖矩阵：普通怪可选项随等级**单调塌缩**

> 数据来自 `05-check_monster_level_boss.py` 的逐级复算（口径：`level_min ≤ L ≤ level_max`）。

| 等级 | 普通怪 | 精英 | 说明 |
|---:|---:|---:|---|
| L1 | **2** | **0** ⚠️ | spider_cave, bat_swarm |
| L2 | 4 | **0** ⚠️ | +skeleton_warrior, warg_dark |
| L3–L4 | **6**（峰值） | **0** ⚠️ | +slime_acid, mushroom_spore |
| L5–L7 | 6 | 1–2 | +brute_butcher(L5) |
| L8–L9 | **7** | 2–3 | +golem_ember, +wraith_frost(L8), +hound_ash(L9) |
| L10 | 5 | 3 | skeleton_warrior/slime_acid/mushroom_spore/warg_dark 相继到期 |
| L11–L12 | 4 | 3 | |
| **L13** | **3** 🔴 | 3 | golem_ember, imp_hellfire, hound_ash（**局部低谷**） |
| L14 | 4 | 3 | +frozen_husk |
| L15–L16 | 3 | 4 | +ice_wraith(L15) |
| **L17–L18** | **1** 🔴 | 4 | **只有 frozen_husk** |
| **L19–L20** | **1** 🔴 | 3 | **只有 frozen_husk** |

**三条明确症状**：

1. **L17–20 段只有 1 种普通怪**（`frozen_husk`）
   ⇒ 第 17–20 关（**4 关、占全游戏 20%**）的杂兵**全是同一只**，视觉与行为零变化
2. **精英在 L1–L4 完全没有**（`brute_butcher` 从 L5 起）
   ⇒ 但 `ch1_l01`–`ch1_l04` 的 `elite_count` 是 **2/2/2/3**
   ⇒ **这 4 关要刷 9 只精英，而 data 里没有任何 L1–4 可用的精英**
   ⇒ **精英列表为空 ⇒ 精英锚点刷不出来**（见 §2.2 的机械分析）
3. **L13 是「局部低谷」**：`skeleton_warrior`(≤12)、`slime_acid`(≤10)、`mushroom_spore`(≤9)、
   `warg_dark`(≤9) **同时到期**，而新的只有 `frozen_husk`(14+) 未到
   ⇒ 只剩 `golem_ember`(8–16) / `imp_hellfire`(7–14) / `hound_ash`(9–16) **3 种**

#### 元素分布失衡

| 元素 | 怪物数 | 说明 |
|---|---:|---|
| `physical` | 6 | spider_cave / bat_swarm / skeleton_warrior / warg_dark / brute_butcher / boss_bone_tyrant |
| `fire` | 5 | imp_hellfire / golem_ember / hound_ash / pyromancer_cultist / boss_ember_lord |
| `cold` | **3** | frozen_husk / wraith_frost / ice_wraith |
| `poison` | 2 | slime_acid / mushroom_spore |
| **`lightning`** | **0** 🔴 | 第四步 §4.3 已定义该元素 + 感电异常，**但没有一只怪用它** |
| **`shadow`** | **0** 🔴 | 同上（诅咒异常也没有承载怪） |

⇒ **第四步设计的 6 元素专精，实际只有 4 种元素有怪**
⇒ 玩家收集「电抗/暗影抗」装备**永远无用**（没有对应的伤害来源）

#### 各关实际引用的怪物（复算）

⚠️ **一个更严重的问题**：各关 `monster_entries` 引用的怪，**14/20 关存在超出该怪 `level_max` 的情况**
（实测复算，口径：`monster.level_min ≤ 关卡 level ≤ monster.level_max`）：

| 关 | 关等级 | 引用的怪（含 `level_max`） | 越界 |
|---|---:|---|---|
| `ch1_l01` | 1 | spider_cave(≤6), bat_swarm(≤8) | ✅ |
| `ch1_l02` | 2 | spider_cave, bat_swarm, skeleton_warrior(≤12) | ✅ |
| `ch1_l03` | 3 | spider_cave, slime_acid, **brute_butcher(≥5)** | 🔴 精英等级未到 |
| `ch1_l04` | 4 | skeleton_warrior, slime_acid, bat_swarm | ✅ |
| `ch1_l05` | 5 | skeleton_warrior, brute_butcher, slime_acid | ✅ |
| `ch1_l06` | 6 | skeleton_warrior, **wraith_frost(≥8)**, boss_bone_tyrant(6–7) | 🔴 精英等级未到 |
| `ch2_l07` | 7 | skeleton_warrior, **wraith_frost(≥8)**, slime_acid | 🔴 |
| `ch2_l08` | 8 | skeleton_warrior, bat_swarm(≤8), brute_butcher | ✅ |
| `ch2_l09` | 9 | skeleton_warrior, wraith_frost, slime_acid | ✅ |
| `ch2_l10` | 10 | skeleton_warrior, brute_butcher, wraith_frost | ✅ |
| `ch2_l11` | 11 | **slime_acid(≤10)**, wraith_frost, skeleton_warrior | 🔴 普通怪过期 |
| `ch2_l12` | 12 | skeleton_warrior, brute_butcher, wraith_frost | ✅ |
| `ch2_l13` | 13 | **skeleton_warrior(≤12)**, wraith_frost, brute_butcher | 🔴 |
| `ch3_l14` | 14 | wraith_frost, **skeleton_warrior(≤12)**, **bat_swarm(≤8)** | 🔴 双重过期 |
| `ch3_l15` | 15 | wraith_frost, **slime_acid(≤10)**, brute_butcher | 🔴 |
| `ch3_l16` | 16 | wraith_frost, **skeleton_warrior(≤12)**, brute_butcher | 🔴 |
| `ch3_l17` | 17 | wraith_frost, **slime_acid(≤10)**, **skeleton_warrior(≤12)** | 🔴 双重过期 |
| `ch3_l18` | 18 | **skeleton_warrior(≤12)**, wraith_frost, brute_butcher | 🔴 |
| `ch3_l19` | 19 | wraith_frost, **skeleton_warrior(≤12)**, **slime_acid(≤10)** | 🔴 双重过期 |
| `ch3_l20` | 20 | **skeleton_warrior(≤12)**, wraith_frost, brute_butcher | 🔴 |

> 📌 **越界的两种形态**：
> ① **普通怪过期**（`slime_acid` ≤10 / `skeleton_warrior` ≤12 / `bat_swarm` ≤8）
> ② **精英等级未到**（`brute_butcher` ≥5 出现在 L3、`wraith_frost` ≥8 出现在 L6/L7）
> ⇒ 两种都会让「稀疏的等级带」被进一步放大

⇒ **`level_min`/`level_max` 似乎只是"文档字段"，运行时并不做过滤**
（`level_scene` 按 `monster_entries` 无条件生成）
⇒ 但**设计上**这造成两个后果：① 高关用低阶怪（数值靠 `hp_scale` 硬撑，行为却是最笨的 AI）
② 稀疏的等级带让**关卡的怪物组合实际上只在 3–4 套之间循环**
（实测 20 关的 `monster_entries` 只有 **3 个条目/关**，且 `skeleton_warrior` / `wraith_frost` / `brute_butcher`
这 3 只在 13 关里反复出现）

### 1.2 AI：定义了 6 种 `ai_id`，实现 0 种

**这是本步最严重的一条。**

| `ai_id` | 数据里用它 | 代码里的分支数 |
|---|---:|---:|
| `melee_chaser` | 4 只 | **0**（仅 `monster_data.gd:89` 的**默认值字符串**） |
| `ranged_kiter` | 4 只 | **0** |
| `erratic_chaser` | 2 只 | **0** |
| `lobber` | 2 只 | **0** |
| `melee_charger` | 2 只 | **0** |
| `boss_phased` | 2 只 | **0** |

**全仓 `ai_id` 的搜索命中（3 处，全部不是行为分支）**：

```
resources/monster_data.gd:89     @export var ai_id: String = "melee_chaser"   ← 字段定义
scripts/autoload/config_loader.gd:290  res.ai_id = String(raw.get("ai_id", ...))  ← 读入
tools/self_check.gd:722          or m.ai_id.is_empty()                        ← 只查「非空」
```

**`enemy_base.gd` 的实际 AI**（`:26-27`、`:821-868`）：

```gdscript
enum AIState { PATROL, CHASE, ATTACK }   # 只有 3 个状态，对全体怪物一视同仁
# 巡逻：出生点游走
# 追击：direction_to(player) * move_speed     ← 无避障、无寻路、无风筝
# 攻击：dist <= attack_range 时停手输出伤害
```

⇒ **6 种 `ai_id` 在行为上完全等价**。数据里写的 `ranged_kiter`
（远程风筝）实际表现是**贴上来砍**；`lobber`（投掷）实际表现也是**贴上来砍**。

> 📌 **这是「静默失败」的第 5 类变体，与第四步的「自洽式伪校验」并列**：
> **「数据里写了、代码里没读」的 `enum`-like 字符串字段**。
> 特征：字段类型是 `String`（不是 `enum`）⇒ 编译器**不会**在 `match` 缺失时报错
> ⇒ 数据与实现之间**没有任何编译期或运行期约束**。
> **判据**：看到一个 `String` 类型的"类型字段"（`ai_id` / `behavior` / `kind`），
> **第一件事是 grep 它在代码里的分支数** —— 命中 ≤ 1（只有定义+读入）= 没实现。

### 1.3 关卡：20 关，4 手绘 + 16 程序化

| 关 | 等级 | 形态 | 尺寸 | 目标 | `budget` | Σ`count_min`–`max` |
|---|---:|---|---|---|---:|---|
| ch1_l01 | 1 | 手绘 | 40×30 | `clear_all` | 40 | 26–40 |
| ch1_l02 | 2 | 手绘 | 40×30 | `clear_all` | 50 | 32–51 |
| ch1_l03 | 3 | 程序 | 默认 | `kill_elite` | 55 | 28–44 |
| ch1_l04 | 4 | 程序 | 默认 | `collect` | 58 | 28–43 |
| ch1_l05 | 5 | 手绘 | 26×44 | `clear_all` | 62 | 22–62 |
| ch1_l06 | 6 | 手绘 | 48×36 | `kill_boss` | 66 | 16–66 |
| ch2_l07 | 7 | 程序 | 44×32 | `clear_all` | 54 | 32–50 |
| ch2_l08 | 8 | 程序 | 44×32 | `kill_elite` | 56 | 33–50 |
| ch2_l09 | 9 | 程序 | 46×34 | `clear_all` | 58 | 34–50 |
| ch2_l10 | 10 | 程序 | 48×34 | `kill_elite` | 60 | 34–52 |
| ch2_l11 | 11 | 程序 | 48×36 | `clear_all` | 62 | 45–65 |
| ch2_l12 | 12 | 程序 | 50×36 | `kill_elite` | 64 | 37–55 |
| ch2_l13 | 13 | 程序 | 52×38 | `kill_boss` | 66 | 42–63 |
| ch3_l14 | 14 | 程序 | 50×36 | `clear_all` | 58 | 33–49 |
| ch3_l15 | 15 | 程序 | 52×38 | `kill_elite` | 60 | 27–41 |
| ch3_l16 | 16 | 程序 | 52×38 | `clear_all` | 62 | 33–48 |
| ch3_l17 | 17 | 程序 | 54×40 | `kill_elite` | 64 | 43–65 |
| ch3_l18 | 18 | 程序 | 54×40 | `clear_all` | 66 | 40–61 |
| ch3_l19 | 19 | 程序 | 56×42 | `kill_elite` | 68 | 55–77 |
| ch3_l20 | 20 | 程序 | 58×42 | `kill_boss` | 70 | 54–79 |

**问题**：
1. **`ch1_l03`/`ch1_l04` 的 `layout` 是空字典** ⇒ 走 `level_generator.gd:85` 的默认参数
   （`width/height` 由 `DEFAULT_LAYOUT` 决定，`room_count` 等也是默认值）
   ⇒ **这两关的地图形态与「第一次写默认值的那天」完全绑定**，且**与相邻关卡无设计关系**
2. **16 关程序化参数高度同构**：宽 44→58（+32%）、`room_count` 10→17、`obstacle_density` 0.05→0.09
   ⇒ 增大是"线性放大"，**形态上仍是「撒房间 + 连走廊」**，玩家感知不到"这关不一样"
3. **目标类型只用 4 种**：`clear_all` ×9 / `kill_elite` ×7 / `kill_boss` ×3 / `collect` ×1
   （`survive` / `reach_exit` **0 次**，因为它们**未实现**）
   - ⚠️ 更细的问题：`clear_all` 占 **45%**、`kill_elite` 占 **35%** ⇒ 两者合计 **80%**
     ⇒ 20 关里有 16 关的玩法其实是「把怪清掉」，**目标层面几乎没有变化**

### 1.4 ⚠️ `total_monster_budget` 只是埋点，不驱动刷怪

| 关 | `budget` | Σ`count_max` | 差 |
|---|---:|---:|---:|
| ch1_l01 | 40 | 40 | 0 ✅ |
| ch1_l05 | 62 | 62 | 0 ✅ |
| ch1_l06 | 66 | 66 | 0 ✅ |
| ch1_l03 | 55 | 44 | **+11** 🔴 |
| ch1_l04 | 58 | 43 | **+15** 🔴 |
| ch1_l14 | 58 | 49 | +9 🔴 |
| ch3_l15 | 60 | 41 | **+19** 🔴（最大） |
| ch3_l16 | 62 | 48 | +14 🔴 |
| ch3_l19 | 68 | 77 | −9 |
| ch3_l20 | 70 | 79 | −9（唯一反向） |
| 其余 8 关 | — | — | 非 0（见 `05-levels.json`） |

- **合计**：`budget` **1,199** vs `Σcount_min`–`max` 区间 **[694, 1,111]**（均值 ≈ 902）
- **17 / 20 关** `budget ≠ Σcount_max`，**最大偏差 +19**（`ch3_l15` budget=60 / Σmax=41；`ch3_l20` budget=70 / Σmax=79 是唯一反向偏差 −9）
  - 📌 只有 **`ch1_l01` / `ch1_l05` / `ch1_l06`** 三关的 `budget == Σcount_max`

**机械成因**（两处代码）：

```gdscript
# ① 刷怪数：只看 count_min/count_max，不看 budget
#    level_generator.gd:478-485（程序化）
var n := rng.randi_range(int(e.get("count_min", 0)), int(e.get("count_max", 0)))
# ② 手绘：'m' 标记数 = 刷怪数，且必须 ≤ Σcount_max
#    level_generator.gd:388-390
elif budget_max > 0 and monster_cells.size() > budget_max:
    errors.append("手绘地图有 %d 个杂兵标记 'm'，超过本关预算 Σcount_max=%d")

# ③ budget 的唯一消费点：埋点，纯观测
#    level_scene.gd:411
CombatMetrics.begin_run(level_id, difficulty_tier,
    int(_level_def.total_monster_budget), _alive.size())
```

⇒ **「20 关预算」这件事在工程里其实是 `Σcount_*` 的字符串在起作用，
`total_monster_budget` 是一个不受约束的、独立的、仅供报表的数字。**
⇒ **第四步路线 A 若只改 `budget`，单局时长与刷怪数都不会变。**

#### 🔍 附带发现：注释里的数字也是脱钩的

本步校验脚本扫描 `total_monster_budget` 的**全部 7 处消费点**时，抓到两处注释写错：

| 位置 | 注释写的 | 实测 | 状态 |
|---|---|---|---|
| `combat_metrics.gd:6` | 合计 **1174** / 均值 **58.7** | **1199 / 60.0** | 🔴 脱钩 |
| `verify_metrics.gd:8` | 「POC 值（单局 ≈3–5 分钟）」 | 同一件事，但未标数字 | 🟡 可接受 |

⇒ 与 `verify_balance84.gd` 硬编码常量（第四步 W5-c）**同源**：
**注释里的具体数值无人消费 ⇒ 改数时不会报错、也不会有人想起它。**
⇒ 列为 **W5-13**（P2，与 W2/W5-4 同批改）。

### 1.5 BOSS：2 个配置完整，但技能只消费 2 类

**`data/bosses/bosses.json`**（2 个 BOSS，各 4 阶段）：

| BOSS | `phase_count` | `phase_skills`（4 阶段） | `summon_pool` | `enrage` |
|---|---:|---|---|---|
| `boss_bone_tyrant` | 4 | slam / +summon / +shockwave / +enrage | skeleton_warrior, warg_dark | atk×0.6 dmg×1.3 |
| `boss_ember_lord` | 4 | fireball / +summon_imp / +magma_eruption / +enrage | imp_hellfire, hound_ash | atk×0.55 dmg×1.35 |

**代码实际消费的技能**（`enemy_base.gd:972-984`）：

```gdscript
var has_summon := _boss_skills.has("summon_skeleton") or _boss_skills.has("summon_imp")
var has_aoe := _boss_skills.has("shockwave") or _boss_skills.has("magma_eruption")
```

| 技能 id | 是否被消费 | 说明 |
|---|---|---|
| `summon_skeleton` / `summon_imp` | ✅ | 触发 `_summon_minions()` |
| `shockwave` / `magma_eruption` | ✅ | 触发 `_aoe_strike()`（带 0.6s 预警） |
| **`bone_slam`** | ❌ | **死数据**（配置里 4 个阶段都出现） |
| **`fireball`** | ❌ | **死数据**（同上） |
| **`enrage`** | 🔸 **半消费** | 不触发独立行为，只在 `_apply_boss_phase` 里折算成 `damage_mult` + `interval_mult` |

⇒ **2 个 BOSS 的「阶段技能扩展」体验实际上只有两种变化**：
**「多刷小怪」+「多了个 AoE」**（第 1 阶段甚至**什么都不做**，只有普通攻击）
⇒ `bone_slam` / `fireball` 这类**标志性技能没有表现**，BOSS 的"招式感"缺一半

### 1.6 目标类型：6 种定义，4 种实现

```gdscript
# resources/level_data.gd:23-24
const OBJECTIVE_NAMES := ["清怪", "击杀精英", "击杀 BOSS", "存活", "收集", "抵达出口"]
const OBJECTIVE_KEYS  := ["clear_all","kill_elite","kill_boss","survive","collect","reach_exit"]
```

| 类型 | 实现 | 20 关使用次数 |
|---|---|---:|
| `clear_all` | ✅ | 9 |
| `kill_elite` | ✅ | 7 |
| `kill_boss` | ✅ | 3 |
| `collect` | ✅ | 1 |
| **`survive`** | ❌ **未实现** | 0 |
| **`reach_exit`** | ❌ **未实现** | 0 |

**未实现的降级行为**（`level_scene.gd:755-761`）：

```gdscript
_:
    push_warning("[Level] 目标类型 '%s' 未实现，本局退化为「清空全部敌人」")
    _degrade_to_clear_all(...)
```

> ✅ **这个设计是好的** —— 它**明确退化 + 吵一声**，不假装完成
> （对比第四步的「静默失败」，这里是正例）。
> 但**功能上仍缺失**：`survive`（生存 N 秒）与 `reach_exit`（抵达出口）
> 是 ARPG 最基础的两种节奏变化，**没有它们，20 关的玩法骨架只有"打光/杀精英/杀 BOSS"**

### 1.7 精灵素材：4 方向而非 8 方向

**`assets/pack/creatures/<id>/`**（20 个目录 = 16 怪 + 3 职业 + 1 `player`）：

| 项 | 实测 |
|---|---|
| 怪物帧数 | **84 帧**（`idle` 4 + `walk` 4 + `attack` 4 + `hurt` 3 + `die` 6）**× 4 方向** = 84 |
| 玩家帧数 | **71 帧**（三职业一致） |
| 命名约定 | `char_<id>_<action>_<dir>_<NN>.png` ✅ 100% 合规 |
| 帧号范围 | 01 起、遇缺即停 ✅ |
| **方向数** | **4**（`n` / `e` / `s` / `w`） |
| **`PACK_DIRS` 声明** | **8**（`n,ne,e,se,s,sw,w,nw`） |
| `PACK_ACTIONS` | 6 种（含 `death` 与 `die` 两个**同义**动作） |

**两个观察**：

1. **4 方向素材 + 8 方向声明** ⇒ `pack_probe_names()` 对 `ne/se/sw/nw` 探测**必然返回空**
   ⇒ 斜向移动时**回退到最近的 4 方向帧**（`resolve_clip` 的兜底）
   ⇒ ⚠️ 与项目记忆里的「玩家转向尴尬」**同源**：斜向移动**没有独立帧**
2. **`death` 与 `die` 双动作**：`PACK_ACTIONS` 同时列了两个，实测素材里**只有 `die`**
   ⇒ `death` 探测**永远返回空**（无副作用，但属**冗余/误导字段**）

**尺寸**：`assets/sprites/enemies/*.png` 是 **128×128**（怪物）/ **256×256**（BOSS）
—— **这是旧的单帧/图集素材**，与 `pack/creatures/` 的逐帧素材**是两套并存**
（加载优先级：`user://content` → `res://assets/pack/creatures/` → `sprites/enemies/`）

---

## 二、五处结构性缺口（诊断）

### 2.1 缺口一：`ai_id` 零实现（最重）

**症状**：16 种怪的 `ai_id` 分布是 6 种，但代码里 **0 个分支** ⇒ 行为上只有 **1 种**。

**为什么这是最重的**：
- 第四步把「伤害/血量/成长率」调平了，但那只是**数值手感**
- **行为手感**完全由 AI 决定 ⇒ `ranged_kiter` 的怪贴脸、`lobber` 的怪也贴脸
  ⇒ 玩家**看不出 16 种怪的区别**，只看到"血厚血薄"
- 且这是**怪物/关卡/BOSS 三者的公共底座**：不修 AI，加多少怪都只是"换皮"

**根因**：`ai_id` 是 `String` 字段 ⇒ 无编译期约束 ⇒ 数据与实现可**永久脱钩**。

### 2.2 缺口二：怪物等级覆盖塌缩

**三条症状**（见 §1.1）：L17–20 只有 1 种普通怪 / 精英 L1–4 空 / L13 假低谷。

**外加一条隐藏症状**：**精英数在低关刷不出来**

| 关 | `elite_count` | 该关等级可用的精英 | 结果 |
|---|---:|---|---|
| ch1_l01 | 2 | **无** | 🔴 精英表为空 |
| ch1_l02 | 2 | **无** | 🔴 |
| ch1_l03 | 2 | **无**（brute_butcher ≥5） | 🔴 |
| ch1_l04 | 3 | **无** | 🔴 |

⇒ **前 4 关写了「共刷 9 只精英」，但没有任何精英可用**
⇒ 需确认工程侧对"空精英表"的处理（是静默跳过、还是崩溃）—— **列为待验证项**

### 2.3 缺口三：BOSS 技能只消费 2 类

见 §1.5。**核心问题**：`phase_skills` 的**设计意图是"阶段越高，招式越丰富"**，
但代码只认 **2 个技能名**（各 2 个别名）⇒ 实际体验是**"多刷怪 + 一个大圈"**。

**另外**：`boss_bone_tyrant` 与 `boss_ember_lord` 的**阶段技能集结构完全相同**
（1 个基础技 → +召唤 → +AoE → +狂暴）⇒ **2 个 BOSS 打起来是同一套节奏**。

### 2.4 缺口四：目标类型 6 定义 4 实现

见 §1.6。**正例**：退化时明确警告（不静默）。
**缺口**：`survive` / `reach_exit` 不可用 ⇒ 无法设计「守点 N 秒」「抵达传送门」这类关卡。

### 2.5 缺口五：地图与关卡形态单一

**16 关程序化参数同构** + **`ch1_l03/l04` 无显式 layout** ⇒
20 关的**空间体验**实际上只有：**4 张手绘 + 16 张"参数微调的房间迷宫"**。

**验证方法（本步给出，留给工程侧可选执行）**：
用现成工具 `game/tools/probe_level.gd` 对 20 关各跑一次，
比较「可走占比 / 出生点 / 碰撞矩形数 / 指纹」⇒ **指纹重复率 = 空间多样性的量化指标**。

---

## 三、修复方案

### 3.1 修复一：AI 行为落地（6 种）

**目标**：让 `ai_id` 真正分出行为，且**零新增系统**（在现有 `AIState` 三态上扩展）。

**设计原则**：
1. **不改状态机骨架**（仍是 `PATROL → CHASE → ATTACK`），只改**每个状态下的运动/输出方式**
2. **全部数据驱动**（读 `MonsterData` 现有字段 + 少量新字段）
3. **每个 `ai_id` 一个"可观测差异"**（玩家能一句话说出区别）

#### 6 种 AI 的行为定义

| `ai_id` | 中文 | 追击方式 | 攻击方式 | 站位偏好 | 玩家感知 |
|---|---|---|---|---|---|
| `melee_chaser` | 直线追击 | 直冲玩家 | 近战弧 | 贴身 | 「最标准的怪」 |
| `ranged_kiter` | 远程风筝 | **保持 `preferred_range`**（太近则后撤） | 投射物 | 距离 110–160 | 「它一直躲，得追」 |
| `erratic_chaser` | 飘忽突击 | 追击方向 **加入正弦扰动** | 近战弧 | 贴身（但走 Z 字） | 「走位很怪，难打中」 |
| `lobber` | 抛掷 | **半速移动**，且**不贴脸**（保持 80–140） | 抛物线落点 AoE | 中距 | 「地上会有落点圈」 |
| `melee_charger` | 冲锋 | **看到玩家先蓄力冲刺**（`charge_speed` 高速直线） | 冲锋撞人 + 近战 | 直线上 | 「会突然冲过来」 |
| `boss_phased` | BOSS 阶段 | 同 `melee_chaser`（BOSS 速度低） | 阶段技能（见 §3.4） | 中远 | 「招式会变」 |

#### 需要的新字段（`monster_data.gd`）

| 字段 | 类型 | 默认 | 用途 | 用于哪些 `ai_id` |
|---|---|---|---|---|
| `preferred_range` | `float` | `0.0` | 理想站位距离；`>0` 时启用"保持距离" | `ranged_kiter` / `lobber` |
| `charge_speed_mult` | `float` | `2.2` | 冲锋速度倍率 | `melee_charger` |
| `charge_range` | `float` | `180.0` | 进入此距离开始蓄力 | `melee_charger` |
| `charge_windup` | `float` | `0.45` | 蓄力时长（可反应） | `melee_charger` |
| `erratic_amplitude` | `float` | `26.0` | 正弦扰动幅度（像素） | `erratic_chaser` |
| `erratic_frequency` | `float` | `2.4` | 扰动频率（Hz） | `erratic_chaser` |
| `projectile_speed` | `float` | `180.0` | 投射物速度 | `ranged_kiter` |
| `lob_radius` | `float` | `52.0` | 抛掷落点半径 | `lobber` |
| `lob_windup` | `float` | `0.6` | 落点预警时长（沿用现有 `AOE_TELEGRAPH_TIME` 口径） | `lobber` |

> 📌 **`preferred_range` 是最重要的一个新字段**：它一个字段就把
> `ranged_kiter`（110–160）与 `lobber`（80–140）区分开了。
> **且它复用现有的 `move_and_slide()`**：`dist < preferred_range_lo` 时
> `velocity = direction_to(player).rotated(PI)`（后退）⇒ **不引入寻路**。

#### 具体实现方向（工单 W5-1）

```gdscript
# enemy_base.gd — _chase_state / _attack_state 内，按 ai_id 分派
match data.ai_id:
    "ranged_kiter":
        # 保持 preferred_range：太近后退、太远进、中间横向微移
        ...
    "melee_charger":
        # dist <= charge_range 且冷却好 → windup → 冲刺(charge_speed_mult)
        ...
    "erratic_chaser":
        # 追击方向 base_dir.rotated(sin(时间 × erratic_frequency) × 振幅角)
        ...
    "lobber":
        # 半速进到 preferred_range，攻击改为「预警圈 → 落点 AoE」
        # 复用现有的 AOE_TELEGRAPH_TIME / _aoe_strike 的「警示→延迟命中」两段式
        ...
    _:  # melee_chaser / boss_phased
        ...  # 保持现状（直冲）
```

> ⚠️ **`lobber` 与 BOSS 的 `_aoe_strike()` 复用**：工程侧已有「0.6s 红色圆环预警 → 再结算」
> 的两段式（`AOE_TELEGRAPH_TIME`）。`lobber` 直接用同款 ⇒ **公平性与手感已被验证过**。

#### ~~分级（若走 D1 备选「分期」）~~ —— ✅ D1 已拍板「一次做全」⇒ 本表**不执行**，仅存档

| 期 | 做哪些 | 理由 |
|---|---|---|
| **一期** | `ranged_kiter` + `lobber` | 这 2 种**改变玩家的移动决策**（要不要追/要不要走位），手感差异最大 |
| **二期** | `melee_charger` + `erratic_chaser` | 都属"近战变体"，差异在走位细节 |
| 三期（可不做） | `boss_phased` | 已有独立的阶段系统，`ai_id` 只是标签 |

> ⚠️ **D1 裁定：6 种一次做全**（用户 2026-09-24 拍板）。
> ⇒ 本表所列的「一期/二期/三期」**不作执行**；W5-1 需一次性落 6 个 `match` 分支，
> 含上表的 `boss_phased`（它虽是标签，但一并落入 `match` 以满足「6 个取值各有 ≥1 分支」的验收断言 M5）。
> 保留本表的目的：若日后需**回退**为分期，可直接照此切分。

### 3.2 修复二：怪物扩充与等级覆盖

**目标**：① 每个等级 ≥ **4 种**普通怪可选 ② 精英从 **L1** 就有 ③ **补齐 `lightning` / `shadow` 元素**

#### 扩充策略：**16 → 24 种**（+8）

| 新增 | 理由 | 建议类型 | 建议等级带 |
|---|---|---|---|
| `rat_swarm` 腐鼠群 | L1–4 精英空缺 → 补**低阶精英** | elite | 2–9 |
| `bone_archer` 骸骨弓手 | 补 **L17–20** 段的远程普通怪 | normal | 14–20 |
| `frost_lobber` 霜爆投手 | 补 **L17–20** 段的投掷普通怪 | normal | 15–20 |
| `storm_wisp` 雷灵 | 补 **`lightning` 元素**（第四步设计了感电但无承载怪） | normal | 10–18 |
| `shade_stalker` 影袭者 | 补 **`shadow` 元素**（第四步设计了诅咒但无承载怪） | normal | 12–20 |
| `plague_bearer` 疫病携者 | 补 **`poison` 后期**（现 `poison` 只到 L10） | normal | 11–18 |
| `thunder_herald` 雷罚使徒 | 补 **`lightning` 精英** | elite | 12–20 |
| `void_priest` 虚空祭司 | 补 **`shadow` 精英** + L17–20 精英多样性 | elite | 16–20 |

**扩充后覆盖矩阵（目标）**：

| 等级 | 普通怪数 | 精英数 |
|---:|---:|---:|
| L1 | 2 | 0（**建议补 1 只 `rat_swarm`**） |
| L2–L4 | 4–6 | **1** ✅ |
| L5–L12 | 6–8 | 1–4 |
| L13–L16 | **6+**（+storm_wisp/plague_bearer） | 3–5 |
| **L17–L20** | **5**（+bone_archer/frost_lobber/shade_stalker） | **5** |

⇒ **L17–20 从 1 种 → 5 种**（**5 倍**），且**元素从 1 种（cold）→ 4 种**

#### 元素补齐后的分布（目标）

| 元素 | 现在 | 目标 | 新增承载怪 |
|---|---:|---:|---|
| physical | 6 | 6 | — |
| fire | 5 | 5 | — |
| cold | 3 | 4 | +frost_lobber |
| poison | 2 | 3 | +plague_bearer |
| **lightning** | **0** | **2** | +storm_wisp, +thunder_herald |
| **shadow** | **0** | **2** | +shade_stalker, +void_priest |

⇒ **第四步 §4.3 的 6 元素专精全部有承载怪**（电抗/暗影抗装备不再是废属性）

### 3.3 修复三：关卡重排

#### ① 预算语义纠正（**本步最关键的动作**）

**两条路线**（见 §〇 **D2 已拍板 = 路线 ①**）：

| 路线 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **① 改 `count_*`** ✅ **已拍板** | 把 20 关的 `count_min`/`count_max` 提到目标值，`budget` 顺带对齐 | ✅ **不碰代码**，符合"只做文字策划"边界<br>✅ 立刻生效 | 🟠 每关要调 3 组数（×20 关） |
| ② 让 `budget` 驱动 | 改 `level_generator.gd`：`budget` 决定**总数**，`count_*` 降级为**权重/形状** | ✅ 一劳永逸（以后调密度只改一个数） | 🔴 需改代码 + 改 2 处断言（`verify_metrics` / `verify_polish9x`） |

> ✅ **D2 裁定：路线 ①**（用户 2026-09-24 拍板）。
> 理由：路线 ① 与第四步 W2（已在改 `chapter*.json`）**同一批文件、同一次改动**，
> 把「改哪几个字段」说清楚即可一次到位，不必再开代码工单。
> ⇒ **路线 ② 对应的 W5-12 降级为 P3 可选、本步不执行**；若日后游戏密度需频繁调整，
> 再单独立项评估（届时需同步改 `verify_metrics` / `verify_polish9x` 两处断言）。

#### ② 20 关目标刷怪数（路线 ① 的 `count_*` 目标）

**对齐第四步的预算序列（120→440）**，并**消除 `budget ≠ Σcount_max` 的 17 处不一致**：

| 关 | 等级 | 形态 | `budget`(第四步) | **目标 Σ`count_max`** | 目标 Σ`count_min` |
|---|---:|---|---:|---:|---:|
| ch1_l01 | 1 | 手绘 | 120 | 120 | 78 |
| ch1_l02 | 2 | 手绘 | 140 | 140 | 91 |
| ch1_l03 | 3 | 程序 | 160 | 160 | 104 |
| ch1_l04 | 4 | 程序 | 175 | 175 | 114 |
| ch1_l05 | 5 | 手绘 | 190 | 190 | 124 |
| ch1_l06 | 6 | 手绘 | 210 | 210 | 137 |
| ch2_l07 | 7 | 程序 | 230 | 230 | 150 |
| ch2_l08 | 8 | 程序 | 250 | 250 | 163 |
| ch2_l09 | 9 | 程序 | 265 | 265 | 172 |
| ch2_l10 | 10 | 程序 | 280 | 280 | 182 |
| ch2_l11 | 11 | 程序 | 295 | 295 | 192 |
| ch2_l12 | 12 | 程序 | 310 | 310 | 202 |
| ch2_l13 | 13 | 程序 | 325 | 325 | 211 |
| ch3_l14 | 14 | 程序 | 340 | 340 | 221 |
| ch3_l15 | 15 | 程序 | 355 | 355 | 231 |
| ch3_l16 | 16 | 程序 | 370 | 370 | 241 |
| ch3_l17 | 17 | 程序 | 385 | 385 | 250 |
| ch3_l18 | 18 | 程序 | 400 | 400 | 260 |
| ch3_l19 | 19 | 程序 | 420 | 420 | 273 |
| ch3_l20 | 20 | 程序 | 440 | 440 | 286 |
| | | | **合计 5,660** | **5,660** ✅ | **3,682** |

> 📌 **`count_min ≈ count_max × 0.65`**（保持现有的"区间跨度"手感不变）
> ⇒ 实际刷怪数在 `[3,682, 5,660]` 区间随机，**均值 ≈ 4,671**
> ⚠️ 这个量级是**第四步按「283 怪/关均值」估算单局 14–24 分钟来的**，
> 若实测单局过长（>25 分钟），**优先降 `count_min`**（保 `count_max` 不变）。

#### ③ 手绘关 `'m'` 标记（4 关）

| 关 | 现在 `m` | 现在 `Σcount_max` | **目标 `m`** | **目标 `Σcount_max`** |
|---|---:|---:|---:|---:|
| ch1_l01 | 23 | 40 | **60** | 120 |
| ch1_l02 | 48 | 51 | **72** | 140 |
| ch1_l05 | 41 | 62 | **86** | 190 |
| ch1_l06 | 32 | 66 | **92** | 210 |

> ⚠️ **硬约束**（`level_generator.gd:388-390`）：`'m'` 标记数 **必须 ≤ `Σcount_max`**，
> 否则**整关校验失败、`_generate_authored()` 整体放弃** ⇒ 出生点 (-1,-1)、无怪、**整关不可玩**。
> ⇒ **改 `m` 与改 `Σcount_max` 必须同批**，且 `m ≤ Σcount_max` 要留**至少 20% 余量**
> （实际刷怪数 = `m` 个，而 `Σcount_max` 只是上限）。
>
> 📌 **手绘关的刷怪数 = `m` 的个数**（不是 `Σcount_*`）⇒ **这是唯一"所见即所得"的关卡形态**。

#### ④ 关卡结构（补 `layout` 参数 + 目标多样化）

| 关 | 现在 | **建议** |
|---|---|---|
| ch1_l03 / ch1_l04 | `layout: {}`（走默认） | **补显式参数**（见 `05-levels.json`） |
| 16 关程序化 | 宽 44–58 线性放大 | **引入"形态标签"**：`rooms`（房间迷宫）/ `corridor`（长走廊）/ `arena`（单一大厅）/ `ring`（环形） |
| 目标类型 | 只用 4 种 | **20 关目标序列重排**（见下） |

**20 关目标类型建议序列**：

| 关 | 现目标 | **建议目标** | 理由 |
|---|---|---|---|
| ch1_l01 | `clear_all` | `clear_all` | 教学关，不改 |
| ch1_l02 | `clear_all` | `collect` | 提前教收集（现在 L4 才教） |
| ch1_l03 | `kill_elite` | `kill_elite` | 教精英 |
| ch1_l04 | `collect` | **`reach_exit`** | 教"找到出口"（需先补实现） |
| ch1_l05 | `clear_all` | `clear_all` | |
| ch1_l06 | `kill_boss` | `kill_boss` | 章末 BOSS |
| ch2_l07 | `clear_all` | `clear_all` | |
| ch2_l08 | `kill_elite` | **`survive`** | 首次生存关（需先补实现） |
| ch2_l09 | `clear_all` | `kill_elite` | |
| ch2_l10 | `kill_elite` | `collect` | |
| ch2_l11 | `clear_all` | **`survive`** | |
| ch2_l12 | `kill_elite` | `kill_elite` | |
| ch2_l13 | `kill_boss` | `kill_boss` | 章末 BOSS |
| ch3_l14 | `clear_all` | `clear_all` | |
| ch3_l15 | `kill_elite` | **`reach_exit`** | |
| ch3_l16 | `clear_all` | `collect` | |
| ch3_l17 | `kill_elite` | **`survive`** | |
| ch3_l18 | `clear_all` | `clear_all` | |
| ch3_l19 | `kill_elite` | `kill_elite` | |
| ch3_l20 | `kill_boss` | `kill_boss` | 终局 BOSS |

**目标分布（目标）**：`clear_all` ×5 / `kill_elite` ×4 / `kill_boss` ×3 /
`survive` ×3 / `collect` ×3 / `reach_exit` ×2 ⇒ **6 种全用上**
（`clear_all` + `kill_elite` 占比由 **80% → 45%**）

### 3.4 修复四：BOSS 扩充与技能接线

#### ① 技能接线（让 4 类技能都有行为）

| 技能 | 现状 | **建议行为** |
|---|---|---|
| `summon_skeleton` / `summon_imp` | ✅ 已实现 | 保持 |
| `shockwave` / `magma_eruption` | ✅ 已实现（AoE + 预警） | 保持 |
| **`bone_slam`** | ❌ 死数据 | **前方扇形重击**：对自己面前 120° 扇形、半径 `attack_range × 1.6` 结算一次高伤（可预警 0.4s） |
| **`fireball`** | ❌ 死数据 | **直线投射物**：向玩家发射 1–3 发慢速火球（速度 ~140），命中给燃烧 |
| **`enrage`** | 🔸 只折算倍率 | **独立表现**：狂暴瞬间全屏红闪 + 移速/攻速提升（已有 `enrage` 倍率，**只缺"表现"**） |

> 📌 已有基建可复用：`_aoe_strike()` 的两段式（预警→延迟命中）、
> `AOE_TELEGRAPH_TIME`、玩家的 `data.attack_range` 扇形判定
> ⇒ `bone_slam` 与 `fireball` **不需要新系统**，是"接线"而非"开发"。

#### ② BOSS 阶段节奏差异化（让 2 个 BOSS 不像同一个）

**现状**：两者阶段技能结构**完全相同**（基础 → +召唤 → +AoE → +狂暴）。

| BOSS | 现在 | **建议差异化** |
|---|---|---|
| `boss_bone_tyrant`（骨骸系） | 召唤 + AoE | **改成"召唤流"**：召唤数 **2/3/4** 提升到 **3/5/7**，AoE 只保留 `shockwave`，加强 `bone_slam` |
| `boss_ember_lord`（火焰系） | 召唤 + AoE | **改成"法术流"**：召唤数**降到 1/2/2**，主输出交给 `fireball` + `magma_eruption`，`enrage` 提前到阶段 3 |

⇒ 两个 BOSS 的战斗节奏变成 **"人海 vs 法术"**，而非"同一个 BOSS 换个皮"。

#### ③ BOSS 数量（✅ D4 已拍板 = 不新增）

⚠️ **第四步路线 A 已把账号上限压到 20** ⇒ 现有 2 个 BOSS（**L6 / L20**）
**恰好覆盖两头**（章末 + 终局）。✅ **D4 裁定：不新增 BOSS**，改为：
- **把 `boss_bone_tyrant` 的 `level_max` 从 7 放开**（现 6–7）⇒ 让它能复用在 `ch3_l20`
  （现在 `ch3_l20` 的 `boss_id` 就是 `boss_bone_tyrant`，但 `level_max=7` 与关卡 L20 **矛盾**）
- **`boss_frost_monarch`（霜渊君主）草案不入工单、不入素材清单** —— 见 `05-bosses.json` 的
  `new_boss_draft`（`execute: false` 为**最终状态**）；若未来扩章再启用

> ✅ **D4 判定的三条理由**（用户 2026-09-24 拍板）：
> 1. 路线 A 上限 20 ⇒ 2 个 BOSS（L6/L20）已覆盖两端，**加第三个没有对应的等级区间可放**
> 2. 新增 BOSS 需 **84 帧精灵 + 专属技能实现**，成本高收益低
> 3. 更关键：新 BOSS 若沿用现有 `_cast_boss_skill`，会**再产生一批"行为与现有 BOSS 一样"的死数据**
>    ⇒ 先做「让现有 2 个 BOSS 真的不同」（W5-5 / W5-6），性价比更高
>
> 🔴 **发现一个数据矛盾**：`ch3_l20`（L20）的 `boss_id = boss_bone_tyrant`，
> 但该 BOSS 的 `level_min/max = 6/7` ⇒ **终局 BOSS 的实际等级区间与所在关卡不符**
> ⇒ 需确认工程侧是否按关卡等级覆盖 BOSS 等级（若按 `monster.level_max` 取，则终局 BOSS 只有 L7 强度）

### 3.5 修复五：目标类型与地图多样性

#### ① 补 2 种目标类型（✅ D5 已拍板 = 两种都补）

| 类型 | 语义 | 实现难点 | 建议数值 |
|---|---|---|---|
| `survive` | 存活 N 秒 | **无**（只需计时器 + 到点结算）<br>⚠️ 需处理"不杀怪也能过"的问题 | `objective_value` = 秒数，建议 **90–150s**；期间可刷怪 |
| `reach_exit` | 抵达出口 | **无**（需生成一个出口格 + 触碰判定） | `objective_value` = 0（出口 1 个） |

> 📌 **两者都是"最基础的 ARPG 关卡类型"**，且**实现成本极低**（无新系统）。
> ✅ **D5 裁定：两种都补**（用户 2026-09-24 拍板）。
> ⇒ 备选「只补 `survive`」与「都不补、从 `OBJECTIVE_KEYS` 移除」**均不执行**。
> 若不补，`OBJECTIVE_KEYS` 里的 2 项**永久是死定义**（与 `ai_id` 同类问题）；
> 补了之后 6 种目标类型**全部可用**，20 关目标序列见 §3.3④。
>
> **具体建议值**（已写进 `05-levels.json` 的 `objective_rules.new_specs`）：
> `survive` → `ch2_l08` 90s / `ch2_l11` 105s / `ch3_l17` 120s；
> `reach_exit` → `ch1_l04` / `ch3_l15`（各 1 个出口）。

#### ② 地图形态多样化（程序化）

**给 `layout` 增加一个 `pattern` 字段**（`level_generator.gd` 的小改）：

| `pattern` | 生成方式 | 适合的目标 |
|---|---|---|
| `rooms`（现状） | 撒房间 + 连走廊 | `clear_all` / `collect` |
| `corridor` | 长走廊 + 分支小间 | `reach_exit` |
| `arena` | 单一大厅 + 少量柱子 | `kill_boss` / `survive` |
| `ring` | 环形通路 + 中央岛 | `kill_elite` |

⇒ 20 关的**空间体验**从「1 种形态 × 参数微调」变成 **4 种形态**。

---

## 四、怪物扩充表（目标）

> 完整字段见 `05-monsters.json`。下表为**新增 8 种**的设计值。

| id | 名称 | 档位 | 等级带 | `ai_id` | 元素 | `hp_scale` | `dmg_scale` | `base_xp` | `move_speed` | `attack_range` | 备注 |
|---|---|---|---|---:|---|---:|---:|---:|---:|---:|---|
| `rat_swarm` | 腐鼠群 | elite | 2–9 | `erratic_chaser` | physical | 1.6 | 1.1 | 55 | 92 | 30 | **补 L1–4 精英空缺** |
| `storm_wisp` | 雷灵 | normal | 10–18 | `ranged_kiter` | **lightning** | 0.75 | 1.15 | 30 | 88 | 150 | 电系远程 |
| `plague_bearer` | 疫病携者 | normal | 11–18 | `melee_charger` | poison | 1.4 | 1.2 | 34 | 78 | 36 | 毒系冲锋 |
| `shade_stalker` | 影袭者 | normal | 12–20 | `erratic_chaser` | **shadow** | 1.05 | 1.3 | 44 | 105 | 34 | 暗影飘忽 |
| `thunder_herald` | 雷罚使徒 | elite | 12–20 | `lobber` | **lightning** | 1.0 | 1.25 | 165 | 62 | 130 | 电系投掷精英 |
| `bone_archer` | 骸骨弓手 | normal | 14–20 | `ranged_kiter` | physical | 0.85 | 1.2 | 42 | 70 | 160 | **补 L17–20 远程** |
| `frost_lobber` | 霜爆投手 | normal | 15–20 | `lobber` | cold | 1.15 | 1.25 | 46 | 58 | 135 | **补 L17–20 投掷** |
| `void_priest` | 虚空祭司 | elite | 16–20 | `lobber` | **shadow** | 1.0 | 1.3 | 190 | 55 | 145 | **补 L17–20 精英** |

> ⚠️ **`hp_scale` / `dmg_scale` 需在第四步 W1（`1.12/1.12`）落地后复核**：
> 这两个值是在旧成长率（`1.22/1.16`）下标的；成长率下降后，
> **高等级怪的绝对 HP 会大幅降低** ⇒ 可能需**上调 `hp_scale`** 以维持手感。
> 具体：`1.12^19 / 1.22^19 ≈ 0.19` ⇒ L20 怪 HP 只剩原来的 **~19%**。
> ⇒ **建议在 W1 落地后，统一把 `hp_scale` × `1.3`、`dmg_scale` × `0.9` 试跑**（列为待验证项）。

---

## 五、关卡重排表（目标）

> 完整字段见 `05-levels.json`。核心是 §3.3 的三张表（`count_*` 目标 / `m` 标记 / 目标类型）。

### 5.1 汇总

| 项 | 现在 | 目标 |
|---|---|---|
| `budget` 合计 | 1,199 | **5,660** |
| **实际刷怪数**（Σ`count_*`） | 694–1,111 | **3,682–5,660** |
| `budget` 与 `Σcount_max` 不一致的关 | **17 关** | **0 关** ✅ |
| 手绘关 `m` 合计 | 144 | **310** |
| 目标类型种类 | 4 | **6** ✅ |
| 地图形态 | 1 种（rooms） | **4 种** |
| `layout: {}` 的关 | 2 关 | **0 关** ✅ |

### 5.2 与第四步的联立约束（**必读**）

> 🔴 **`budget` + `count_*` 必须与第四步的 W2 同批改**。
>
> 第四步 W2 说「`chapter*.json` 的 `total_monster_budget` 按目标列替换」——
> 本步补充：**必须同时改 `count_min`/`count_max`**，否则：
> - 埋点报表显示「283 怪/关」（好看）
> - 实际仍是「60 怪/关」（单局 3–5 分钟，**没变**）
> ⇒ 这正是 §1.4 描述的「改了不被消费的字段」。
>
> **另**：`verify_polish9x.gd:78-92` 的**预算曲线断言**（`ch1 = [40,50,55,58,62,66]` …
> 「章内涨幅 ≤ 12」）**必须同批更新**，否则回归会红。
> 新曲线涨幅最大到 **25**（`ch1_l05 190 → l06 210`），**须放宽阈值或改为"比例单调"**。

---

## 六、BOSS 设计表（目标）

> 完整字段见 `05-bosses.json`。

### 6.1 现有 2 个 BOSS 的调整

| 项 | `boss_bone_tyrant` | `boss_ember_lord` |
|---|---|---|
| 定位 | **召唤流**（人海） | **法术流**（投射物 + AoE） |
| `summon_count` | `[0,2,3,4]` → **`[0,3,5,7]`** | `[0,2,3,4]` → **`[0,1,2,2]`** |
| 主输出技能 | **`bone_slam`**（需接线） | **`fireball`**（需接线） |
| AoE | `shockwave` | `magma_eruption` |
| `enrage` 阶段 | 阶段 4（不变） | 阶段 4 → **阶段 3**（提前） |
| `level_min/max` | `6/7` → **`6/20`**（修正矛盾，见 §3.4③） | `19/20`（不变） |

### 6.2 新增 BOSS 草案（**仅存档，路线 A 下不执行**）

| id | 名称 | 等级带 | 定位 | 阶段技能 | 说明 |
|---|---|---|---:|---|---|
| `boss_frost_monarch` | 霜渊君主 | 20–20 | 控场流 | `ice_nova` / +`summon_ice_wraith` / +`glacial_spike` / +`enrage` | 若未来扩章 / 替换 `ch3_l20` 的 BOSS |

> ⚠️ **不新增 BOSS 的理由**：路线 A 上限 20 ⇒ 2 个 BOSS（L6/L20）已覆盖两端。
> 且**新增 BOSS 需要 84 帧精灵 + 专属技能实现**，成本高、收益低。

---

## 七、工程工单

> 全部为**建议**，需工程侧评估后实施。本步不执行任何代码改动。

| ID | 优先级 | 文件 | 改动 | 关联 |
|---|---|---|---|---|
| **W5-1** | 🔴 P0 | `enemy_base.gd`（`_chase_state`/`_attack_state`） | 按 `data.ai_id` 分派 6 种行为（`match`），复用现有 `move_and_slide` + `AOE_TELEGRAPH_TIME` | §3.1 |
| **W5-2** | 🔴 P0 | `monster_data.gd` | 新增 9 个字段（`preferred_range` / `charge_*` / `erratic_*` / `projectile_speed` / `lob_*`） | §3.1 |
| **W5-3** | 🔴 P0 | `data/monsters/monsters.json` | 新增 8 种怪（§四）+ 修正 4 处 `level_max` 与关卡等级的矛盾 | §3.2 |
| **W5-4** | 🔴 P0 | `data/levels/chapter*.json` | `count_min`/`count_max` 按 §3.3② 替换（**与第四步 W2 同批**）；手绘关 `m` 按 §3.3③ 重画 | §3.3 |
| **W5-5** | 🟠 P1 | `enemy_base.gd`（`_cast_boss_skill`） | 补 `bone_slam`（扇形重击）/ `fireball`（直线投射物）/ `enrage`（视觉表现） | §3.4 |
| **W5-6** | 🟠 P1 | `data/bosses/bosses.json` | 2 个 BOSS 差异化（`summon_count` / `enrage` 阶段）；`boss_bone_tyrant` 的 `level_max` 7→20 | §3.4 |
| **W5-7** | 🟠 P1 | `level_scene.gd` + `level_data.gd` | 补 `survive`（计时器）/ `reach_exit`（出口格 + 触碰）两种目标 | §3.5① |
| **W5-8** | 🟡 P2 | `level_generator.gd` | 新增 `layout.pattern`（`rooms`/`corridor`/`arena`/`ring`） | §3.5② |
| **W5-9** | 🟡 P2 | `data/levels/chapter*.json` | `ch1_l03`/`ch1_l04` 补显式 `layout` 参数 | §3.3④ |
| **W5-10** | 🟡 P2 | `tools/verify_polish9x.gd:78-92` | 预算曲线断言按新序列更新（涨幅阈值 ≤12 → ≤25 或改比例判定） | §5.2 |
| **W5-11** | 🟡 P2 | `enemy_base.gd:497` | `PACK_ACTIONS` 删除冗余的 `"death"`（素材只有 `die`） | §1.7 |
| **W5-12** | 🟢 P3（**D2 拍板后降级**） | `level_generator.gd`（可选） | 路线 ②：让 `total_monster_budget` 真正驱动刷怪数，`count_*` 降级为权重。**本步不执行** | §3.3① |
| **W5-13** | 🟡 P2 | `combat_metrics.gd:6` + `verify_metrics.gd:8` | **注释脱钩修正**：两处注释写「合计 **1174** / 均值 **58.7**」，实测为 **1199 / 60.0**（且路线 A 落地后应为 **5660 / 283.0**） | §1.4 |

> 📌 **W5-13 是第五步校验脚本实测抓到的**（`total_monster_budget` 的消费点扫描）——
> 属第四步「自洽式伪校验」的同类：**注释写错数字，无人消费 ⇒ 永久不报错**。
> ⇒ 凡注释里出现具体数值，都应视为**可能脱钩**，改数时一并 grep 注释。

### 建议实施顺序

```
第 1 批（P0，内容底座，必须一起改）
  W5-1（AI 行为） + W5-2（数据字段） + W5-3（怪物扩充）
  + W5-4（关卡 count_*/m  ← 与第四步 W2 同批）

第 2 批（P1，玩法扩展）
  W5-5（BOSS 技能接线） + W5-6（BOSS 差异化）
  + W5-7（survive / reach_exit）

第 3 批（P2，打磨）
  W5-8 + W5-9 + W5-10 + W5-11 + W5-13
```

> ⚠️ **W5-1 与 W5-3 必须同批**：只加怪不改 AI ⇒ 8 种新怪**行为上仍只有 1 种**，
> 白花素材成本。**先修 AI，再加怪。**
>
> ⚠️ **W5-4 必须与第四步 W2 同批**：见 §5.2。

---

## 八、素材工单

> 承第一/二/三/四步的素材清单，本步新增以下条目。**只指明方向，不制作。**

### 8.1 新增怪物精灵（8 种 × 84 帧 = 672 帧）

**规格**（严格遵循现有约定，见 §1.7）：

```
路径：res://assets/pack/creatures/<id>/char_<id>_<action>_<dir>_<NN>.png
动作：idle(4) / walk(4) / attack(4) / hurt(3) / die(6)   ← 共 21 帧/方向
方向：n / e / s / w                                       ← 4 方向
帧数：21 × 4 = 84 帧/怪
命名：NN 从 01 起、遇缺即停（不可跳号）
```

| 怪 | 帧数 | 备注 |
|---|---:|---|
| `rat_swarm` 腐鼠群 | 84 | 精英（可稍大，48×48 内） |
| `storm_wisp` 雷灵 | 84 | 建议半透明发光 |
| `plague_bearer` 疫病携者 | 84 | |
| `shade_stalker` 影袭者 | 84 | 建议暗色剪影 |
| `thunder_herald` 雷罚使徒 | 84 | 精英 |
| `bone_archer` 骸骨弓手 | 84 | 需 `attack` 体现拉弓 |
| `frost_lobber` 霜爆投手 | 84 | 需 `attack` 体现抛掷 |
| `void_priest` 虚空祭司 | 84 | 精英 |
| | **672** | |

> ⚠️ **铁律一（唯一色源）**：全部像素必须落在 `PALETTE_ALL`（44 色）
> ⚠️ **铁律二（视口 640×360）**：单精灵 **≤24 色**、尺寸 **48×48 内**、只允许整数缩放、**禁止运行时旋转**

### 8.2 新增 BOSS 精灵（❌ 不入本步素材清单 —— D4 已拍板不新增 BOSS）

| BOSS | 帧数 | 说明 |
|---|---:|---|
| `boss_frost_monarch` 霜渊君主 | 84（+ 阶段特效帧） | **❌ 不入本步素材清单**（D4 拍板不新增 BOSS）；仅在扩章时启用 |

### 8.3 新增异常/技能特效（承第四步 §8）

| 素材 | 规格 | 数量 | 说明 |
|---|---|---|---|
| `fx_lightning_spark.png` | 32×32 | 4 帧 | 感电命中特效（**第四步定义了异常但无承载怪/特效**） |
| `fx_shadow_curse.png` | 32×32 | 4 帧 | 诅咒命中特效 |
| `fx_bone_slam.png` | 64×64 | 4 帧 | `bone_slam` 扇形重击（若 W5-5 落地） |
| `fx_lob_impact.png` | 48×48 | 4 帧 | `lobber` 落点冲击 |
| `tile_exit_portal.png` | 32×32 | 4 帧 | `reach_exit` 出口传送门 |
| `fx_enrage_flash.png` | 全屏叠加 | 4 帧 | `enrage` 狂暴视觉（**目前只有倍率、无表现**；最小可接受 = 全屏红闪 0.3s） |

**小计：新增精灵 672 帧（8 怪）+ 特效 24 帧 = 696 帧**
（其中 `fx_enrage_flash` / `tile_exit_portal` 分别对应 W5-5 / W5-7，**若对应工单不做则可不制作**）

> ✅ **本小计已按 D1–D5 拍板结果收口**：
> - 新怪 **672 帧** = D3「接受 +8 种」
> - 特效 **24 帧** = D5「`survive`/`reach_exit` 都补」（`tile_exit_portal` 属 `reach_exit`）+ D4「BOSS 技能接线」（`fx_enrage_flash`）
> - **不含** `boss_frost_monarch` 的 84 帧（D4 不新增 BOSS）

---

## 九、与前后步的衔接

### 9.1 承接前四步的待办

| 来源 | 待办 | 本步处理 |
|---|---|---|
| 第四步 | 预算 120→440 落地 | ✅ §3.3（**并纠正**：须同改 `count_*`，非只改 `budget`） |
| 第四步 | 手绘关 `'m'` 标记提到目标预算 | ✅ §3.3③（4 关对照表） |
| 第四步 | 装备池 iLvl ≤20 → 22 | ✅ 本步**不需新怪**（怪等级只到 20）即可支撑 |
| 第四步 | 怪物成长率 1.12/1.12 落地后复核 `hp_scale` | ⚠️ 见 §四 备注（列为待验证项） |
| 第四步 | L21–38 段怪物 | ✅ **路线 A 下不需要**（上限 20） |
| 第四步 | BOSS 需补 L13 + L38 | ✅ **路线 A 下不需要**（2 个 BOSS 已覆盖 L6/L20） |
| 第三步 | 元素专精 6 子键 | ⚠️ 第四步定义了，但**本步才发现没有 `lightning`/`shadow` 承载怪** ⇒ §3.2 补齐 |
| 第一步 | 5 种新技能形态引擎 | ⏳ 留第六步（与召唤物联动） |

### 9.2 移交给第六步（汇总为 AI 可读开发文档）

| # | 移交项 | 说明 |
|---|---|---|
| 1 | **全部工单汇总** | 第四步 W1–W11 + 本步 W5-1–W5-13 = **24 条**，需按批次重排为一份总表（已拍板项标 ✅） |
| 2 | **素材总量核算** | 四步累计：UI + 精灵 + 图标 + 特效，需给出一张总清单（本步 **696 帧**，不含 `boss_frost_monarch`） |
| 3 | **落地顺序** | 建议：W1+W2+W10+W11（第四步三件套）→ W5-1/2/3/4 → W5-5/6/7 → 其余（W5-12 已降级，可忽略） |
| 4 | **验收总表** | 第四步 T1–T20 + 本步断言，合并为一份可执行清单 |

### 9.2.1 ✅ D1–D5 拍板后的工单范围（给第六步的对账口径）

| 工单 | 拍板前 | **拍板后** | 变化 |
|---|---|---|---|
| W5-1 `ai_id` 分派 | P0，可能分期 | **P0，6 种一次做全**（含 `boss_phased`） | 范围确定、不可裁 |
| W5-2 新增 9 字段 | P0 | **P0，不变** | — |
| W5-3 +8 怪 | P0 | **P0，固定 8 只**（D3=accept） | 4 只的保守方案作废 |
| W5-4 `count_*` + `m` | P0 | **P0，路线 ①**（与第四步 W2 同批） | 路线 ② 作废 |
| W5-5 BOSS 技能接线 | P1 | **P1，不变**（D4 的正向路径） | — |
| W5-6 BOSS 差异化 | P1 | **P1，不变**（D4 的正向路径） | — |
| W5-7 `survive`/`reach_exit` | P1 | **P1，两种都补**（D5=both） | 「只补 survive」作废 |
| W5-8/9/10/11/13 | P2 | **P2，不变** | — |
| **W5-12** | P3 可选 | **P3 可选，本步明确不执行** | ⬇️ 降级说明 |

**⇒ 本步实际待落 = 24 条中的 13 条 W5 工单 + 第四步 W1–W11（其中 W2/W10/W11 与本步 W5-4 同批）。**
**⇒ 无 BOSS 新增、无 `frost_monarch` 素材、无路线 ② 代码改动。**

### 9.3 本步的核心遗产

**一句话**：本步把项目从「**数字对了、内容是空的**」推进到「**内容也有结构了**」。

```
        第四步解决：数字自洽（曲线不崩）
              ↓
        本步解决：内容自洽（数据与实现不脱钩）
              ↓
   ┌──────────────────────────────────────┐
   │ ai_id 6 种 → 真的 6 种行为            │  ← W5-1
   │ 怪物覆盖 → 每级 ≥4 种可选             │  ← W5-3
   │ budget  → 真的驱动单局时长            │  ← W5-4
   │ BOSS 技能 → 4 类都有表现              │  ← W5-5
   │ 目标类型 → 6 种都能用                 │  ← W5-7
   └──────────────────────────────────────┘
```

**⇒ 本步确立的第二条判据（与第四步的「自洽式伪校验」并列）**：

> **看到 `String` 类型的"类型字段"（`ai_id` / `behavior` / `kind` / `pattern`），
> 第一件事是 grep 它在代码里的分支数。**
> 命中 ≤ 1（只有字段定义 + 读入）= **没实现**。
> 特征：`String` 无编译期约束 ⇒ 数据与实现可**永久静默脱钩**，且**测试全绿**。

**⇒ 本步确立的第三条判据**：

> **改一个"看起来是配置项"的字段前，先 grep 它的消费点。**
> 若消费点只有「埋点 / 展示 / 注释」⇒ **改了不会有任何行为变化**。
> （本步的 `total_monster_budget` 就是活例：改了报表变，单局不变。）

---

## 附：本步方法论备注

**为什么先修 AI 再加怪？**

因为**素材是有成本的**（8 只怪 = 672 帧），而**AI 是公共底座**。
若先加怪，`ranged_kiter` 的 4 只新怪仍是贴脸砍 ⇒
**玩家看到的是 8 张新皮 + 1 种旧行为**，素材成本全浪费。
⇒ **先修底座（W5-1），再加内容（W5-3）**，顺序不可逆。

**为什么 `String` 字段比 `enum` 危险？**

`enum` 在 `match` 缺失时会**编译报错或返回默认**，是"会亮灯"的失败；
`String` 字段**永远合法** ⇒ 拼错、漏实现、值改了没人读，**全都是静默的**。
⇒ 项目里所有「类型语义的 String 字段」都应有一份**断言**兜底
（本步的校验脚本已加入此类检查：列出全部 `ai_id` 的取值，并检查代码分支数）。
