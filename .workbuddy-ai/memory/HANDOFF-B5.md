# 交接说明 · B5 特殊玩法（第六步）— 给接手的 AI（豆包）

> **生成时间**：2026-09-29
> **用途**：让另一个 AI 无缝接手 B5 剩余工作。**开工前请按顺序读完本文 → 再读 §8 的必读文件。**
> **一句话现状**：B4 全批（28 条）已收线；**B5-1 已提交**；**B5-2 改到一半、未提交（8 个 dirty 文件）**；接手者从 **B5-2 剩余步骤**继续。

---

## 0. 立刻要做的事（TL;DR）

1. `cd D:/七傳說 && git status --short` 应看到 **8 个 M 文件**（B5-2 半成品，见 §3）。
2. 补齐 **两张特殊底材 JSON**（`special_abyss.json` / `special_tower.json`，各 3 件）—— 见 §5.1。
3. 跑 **解析预检 + 6 个单测**，修任何新红。
4. **重基线** 策划校验器 `06` / `07` 的「现状快照」断言（§5.3，当前 `06 --repo` 195/7、`07 --repo` 210/2）。
5. 全量回归零新增失败 → 写记忆 → **2 个本地 commit（不推送）**。

---

## 1. 环境速查（直接复制可用）

| 项 | 值 |
|---|---|
| 项目根 | `D:\七傳說` |
| 游戏工程 | `D:\七傳說\game` |
| 策划案目录 | `D:\七傳說\deliverables\gstack\策划案` |
| 记忆目录 | `D:\七傳說\.workbuddy-ai\memory` |
| Python（**必须用这个**，系统 `python` / `/tmp` 不可用） | `C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe` |
| Godot 控制台版 | `C:\Users\11265\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe` |

**常用命令**：

```bash
# 解析预检（改完任何 .gd / .json / .tscn 后先跑，扫全仓可解析）
cd D:/七傳說/game && "$GODOT_BIN" --headless --path . res://tools/parse_all.tscn

# 单跑某个 verify_*.gd（把名字换掉即可）
cd D:/七傳說/game && "$GODOT_BIN" --headless --path . res://tools/verify_loot_tables.tscn

# 全量回归（自动 glob verify_*.tscn，判定 [FAIL]==0 且 exit==0）
cd D:/七傳說 && "C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe" game/tools/run_regression.py

# 策划 7 校验器（01/02/03/04 不接受 --repo；05/06/07 必须带 --repo 否则少跑 E 组）
cd D:/七傳說/deliverables/gstack/策划案 && "C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe" 06-check_special_modes.py --repo "D:/七傳說"
cd D:/七傳說/deliverables/gstack/策划案 && "C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe" 07-check_dev_tasks.py --repo "D:/七傳說"
```

> ⚠️ `run_regression.py` 报 **NO-RESULT 是误报**：先读 `%TEMP%\ge_regress_fail_<name>.log` 再定性。

---

## 2. git 铁律（**违反会丢工作**）

- **只允许**：`add` / `commit` / `status` / `log` / `diff`。
- **禁用**：`stash`（尤其 `-u`/`-a`）、`gc`、`prune`、`reset`、`checkout`、`clean`、`read-tree`、`filter-branch`。
  （2026-09-20 事故：`stash push -u` 被 SIGTERM 中断 ⇒ `.git` 整体进回收站。）
- **只本地 commit，绝不 push**（用户明确要求）。
- 清理残留文件一律 `mv` 到 `.workbuddy-ai/trash/<日期>-<原因>/`，**不以 `rm` 直删**。
- `origin` = `github.com/fyangOvO/fyangOvO.git`（**本阶段不推送，仅备查**）。

---

## 3. 当前位置与 git 状态

```
caf60a1  feat(ui): 重做32個低精度技能圖標…        ← 非本 AI 所提交，勿动
592c4a2  docs(memory): B5-1 执行纪录 + 新踩两坑 + 子批计划   ← B5-1 记忆
3772f00  feat(save): B5-1 存档升版 v5→v6 + 门票 API（6-W6-01/02/20）  ← B5-1 代码
195521a  docs(memory): B4-6 执行纪录…             ← B4-6 记忆
5100176  test(skill): B4-6 校验补齐…              ← B4-6 代码
```

**未提交的 8 个文件（B5-2 半成品，见 §4 已完成清单）**：

```
 M game/data/loot_tables/monster_loot_tables.json
 M game/scripts/core/game_constants.gd
 M game/tools/self_check.gd
 M game/tools/verify_anim.gd
 M game/tools/verify_fx.gd
 M game/tools/verify_loot_tables.gd
 M game/tools/verify_ui.gd
 M game/tools/verify_ui_assets.gd
```

> **接手者注意**：这 8 个文件是**半成品**（改动已落盘、但未跑验证、未提交）。**不要** `git checkout` 丢弃它们（git 铁律也禁止 checkout）。直接在其基础上补齐 §5 剩余步骤即可。

---

## 4. B5 全貌

**B5 = 第六步「特殊玩法」28 条 = `6-W6-01`~`20`（20 条）+ `6-W6-Q1`~`Q8`（8 条）**，难度 🔴 极高。

### 三个硬约束
- **C7**：`6-W6-01`（存档升版）必须**最先**做。
- **C8**：`6-W6-11 + 12 + 13`（稀有度扩容三件）**必须同批**。
- **C9**：`6-W6-Q5 + Q6 + Q7`（特殊装闭环三件）**必须同批**。

### 八子批计划（**已定，勿改顺序**）
| 子批 | 内容 | 状态 |
|---|---|---|
| **B5-1** | 存档与门票底座（`01`/`02`/`20`） | ✅ 已提交 |
| **B5-2** | 稀有度扩容核心（`11`/`12`/`13`） | 🔴 **进行中（本文重点）** |
| B5-3 | 稀有度连带与守卫（`15`/`16`/`17`/`Q1`/`Q7`/`Q8`） | 待做 |
| B5-4 | 专属词缀与掉落特效（`18`/`19`） | 待做 |
| B5-5 | BOSS 二阶段（`08`/`09`/`10`） | 待做 |
| B5-6 | 塔/深渊关卡与入口（`07`/`05`/`06`/`03`/`04`） | 待做 |
| B5-7 | 特殊装闭环（`Q2`/`Q3`/`Q4`/`Q5`/`Q6`） | 待做 |
| B5-8 | 校验补齐 + E 组重基线 | 待做 |

---

## 5. B5-2 剩余步骤（**接手者的第一件事**）

### 5.1 【必做】新增两张特殊底材 JSON

新建（`ConfigLoader._load_equipment_dir()` 会**递归扫描**该目录，新档自动载入，无需改代码）：

- `game/data/equipment/special_abyss.json` —— **3 件**，`rarity_min = rarity_max = "special_abyss"`
- `game/data/equipment/special_tower.json` —— **3 件**，`rarity_min = rarity_max = "special_tower"`

**格式参照同目录 `weapons.json` / `armor.json`**（`equipment_templates` 为 `String → EquipmentData`）。
要求：
- 覆盖不同部位（如 helmet / armor / weapon 各 1，或按部位分散）。
- `affix_pool_ids` 参照 `game/data/affix_pools/pools.json` 既有池；**专属池由后续 `6-W6-18` 新增**（本批先用既有池即可）。
- ⚠️ **两档平级同强度**（`RARITY_AFFIX_RANGE` 两者都是 `Vector2i(5,7)`），不要做成强弱阶梯。
- ⚠️ **这是全案三大高危项之一**：此前 62 件底材无一件覆盖 8/9 档 ⇒ `loot_roller.gd:171` 空池会 `return null`（特殊档**什么都不掉且零报错**）。补上这两档底材就是为了填这个空池。

### 5.2 【必做】验证

```bash
# 1) 解析预检（应扫 246 档全部可解析）
cd D:/七傳說/game && "$GODOT_BIN" --headless --path . res://tools/parse_all.tscn

# 2) 逐个单跑（本批直接相关的）
verify_loot_tables / verify_ui_assets / verify_loot / self_check / verify_anim / verify_fx / verify_ui
```

预期：全部 **0 失败**。若有新红，多半是「断言里写死了 8 / 44 / 版本号」——改成引用常量（见 §6 陷阱②）。

### 5.3 【必做】策划校验器重基线（**本批最易漏**）

> **背景**：`06` 的 E 组 + `07` 的 E-repo 群**不是规格断言，而是「B5 前的现状快照」**。B5 每推进一步就会推翻几条。用户已拍板：**每子批同步重基线**，使 `06 --repo` / `07 --repo` 全程保持全绿。

**B5-2 当前实测（半成品状态）**：
- `06 --repo` = **195 通过 / 7 失败** ⇒ 目标 **202/0**
  - `E1` RARITY_COUNT 现为 10（期望 8）—— 06 脚本第 36 行常量 `RARITY_COUNT_NOW = 8`，断言在 ~706–709 行
  - `E3` ×3：`RARITY_BEAM_HEIGHTS` / `RARITY_PREFIX_LIMIT` / `RARITY_SUFFIX_LIMIT`（期望 8 项，现为 10 项）
  - `E4` ×3：`self_check.gd` / `verify_loot_tables.gd` / `verify_ui_assets.gd` —— 断言「**仍含硬编码 8**」，但我们已经把硬编码 8 改成了常量 ⇒ 命中行 `[]` ⇒ 失败（**语义要翻转**：从「仍含 8」改成「已无硬编码 8」）
- `07 --repo` = **210 通过 / 2 失败** ⇒ 目标 **212/0**
  - `R5` RARITY_COUNT 仍為 8（实 10）
  - `R6` SPECIAL_ABYSS 尚未定義（S12 未落地）—— 但 `SPECIAL_ABYSS` **已在 `game_constants.gd` 定义** ⇒ 语义要翻转

**B5-2 加完 special JSON 后还会再转红 2 条（须一并重基线）**：
- `06` **E9**「底材 rarity_max 最大仍为 7」⇒ 加入 8/9 档底材后最大变 9，需改。
- `07` **R13**「尚无 special_*.json」⇒ 加入后需改。

**做法**：直接读 `06-check_special_modes.py` / `07-check_dev_tasks.py` 的对应断言行，把「期望值」改成与当前工程一致（**B5-2 目标态**），保留注释说明「S12 已落地」。改完重跑，直到 `202/0` 与 `212/0`。

> ⚠️ 不要用 `--repo` 之外的参数跑，也不要以为「转红=bug」——**这些红是预期内的现状漂移**。

### 5.4 收尾

1. **全量回归**（76 脚本）零新增失败。**残餘基线**（**非本批造成，勿修**）：
   - `verify_choice_panel` 1 项（裸 Color，命中 `level_scene.gd`）
   - `verify_player` 1 项（手柄映射）
   - `self_check` 2 项（怪物 L20 旧值 → 属 B6 `4-W5-e`）
2. 写记忆：追加到 `.workbuddy-ai/memory/2026-09-29.md` §十一（延伸 B5-2）+ 若有新坑入 `IRON-RULES.md`。
3. **2 个本地 commit**（不推送）：
   - 代码：`feat(loot): B5-2 稀有度 8→10 扩容（6-W6-11/12/13）`
   - 记忆：`docs(memory): B5-2 执行纪录 + 新坑`

---

## 6. ⚠️ 关键陷阱（避坑清单）

1. **策划校验器的「现状快照」断言群**：`06` E 组 16 条 + `07` E-repo 群，**每子批都要同步重基线**（见 §5.3）。不同步 ⇒ 一路转红且**看起来像 bug**。
2. **断言禁写字面量**：凡「版本号 / 档数 / 项数 / 色板数」类断言，一律**引用常量**（`GameConstants.SAVE_VERSION` / `RARITY_COUNT` / `PALETTE_DEFINED_COUNT`），**不写 `== 5` / `== 8` / `== 44`**。已踩过：`verify_skill_ext.gd:541` 写死 `mig.save_version == 5`，B5-1 升 v6 后转红（全量回归才暴露）。
3. **稀有度 8→10 不可逆**：`rarity` 存 `int`，若 `RARITY_COUNT` 回退到 8，会把旧档 8/9 **静默压成 7（隐藏装）**。备份在 `game/.workbuddy_pre_b5_backup/`（`caf60a1` 前）。
4. **掉落表三表各 10 位、和 = 100**；橙装 **0.05 / 1.00 / 5.00 为硬约束不变**。新两档权重全部从 common/magic 挤出：
   - normal `[77.90,17.50,3.50,0.45,0.05,0.02,0.40,0.01,0.14,0.03]`
   - elite `[39.80,33.70,16.00,5.00,1.00,0.60,3.00,0.10,0.60,0.20]`
   - boss `[5.00,29.00,35.00,15.00,5.00,1.80,7.00,0.20,1.50,0.50]`
   （已落在 `monster_loot_tables.json` + `verify_loot_tables.gd` 的 `EXPECT_TABLES`）
5. **色板唯一真源**：`PALETTE_DEFINED_COUNT = 46`（A11+B28+C5+D2）。`self_check` / `verify_anim` / `verify_fx` / `verify_ui` 的色板断言**全部引用它**（勿再写 `== 44`）。
6. **UISkin 工厂静默返回 null**：改素材路径/键名后**必须真渲染抓图目视确认**。已知 `UISkin.RARITY_SLOT`（`ui_skin.gd:354`）是 `0..7` 映射，**缺 8/9 ⇒ 回退 `slot_normal`**（非阻断，但 8/9 档图标会退化成普通格 —— 属 B5-3 待办）。
7. **自洽式伪校验**：脚本若用自己的硬编码常量算自己的断言 ⇒ 永远通过（= 无效）。看到「永远通过」的校验，先查常量是**引用**还是**硬编码副本**。
8. **String 字段静默脱钩**：`ai_id` / `pattern` / `kind` / `behavior` 这类字段，改前先 grep 代码分支数，命中 ≤1 = 没实现。

---

## 7. B5 后续子批提示（非本批，供排期参考）

- **B5-5（BOSS 二阶段）**：注意 `BossPhaseController.validate()` 有**硬断言 3/4/4**，改阶段数会触发。
- **B5-6（塔/深渊）**：门票**尚无获取渠道 / 消耗点**（`6-W6-03` 掉落、`04` 商人、`05/06` 入口）—— 均在本批落地。`tower_progress = {highest_unlocked, current_layer, runs, best_layer}`。
- **B5-7（特殊装闭环）**：注意硬约束 **C9**（`Q5+Q6+Q7` 同批）。
- **B5-4（掉落特效）**：`6-W6-20` 的 `rare_loot_spawned` emit 目前**无消费者**（光柱 FX 属 `6-W6-19`），B5-4 才接。

---

## 8. 必读文件（开工前按序读）

| 文件 | 作用 |
|---|---|
| `.workbuddy-ai/memory/MEMORY.md` | 项目长期记忆索引（当前位置 + 最高危项 + 三坑） |
| `.workbuddy-ai/memory/IRON-RULES.md` | **完整铁律 / 坑 / 已拍板结论**（SF1–SF12 + ㉜~㊲）—— 必读 |
| `.workbuddy-ai/memory/2026-09-29.md` | 今日工作日志：§十 B4-6、**§十一 B5-1 完整落地清单**、§11.0 B5 总览 |
| `.workbuddy-ai/memory/HANDOFF-B5.md` | **本文** |
| `deliverables/gstack/策划案/06-check_special_modes.py` | 第六步校验器（E 组 = B5 现状快照） |
| `deliverables/gstack/策划案/07-check_dev_tasks.py` | 第七步校验器（E-repo 群 = B5 现状快照） |
| Skill `godot-buff-stat-pipeline` | `~/.workbuddy-ai/skills/godot-buff-stat-pipeline/SKILL.md`（九个必踩的坑） |

---

## 9. 验收基线数字（对照用）

| 校验器 | 目标（全绿） |
|---|---|
| 解析预检 `parse_all` | 246 档全部可解析 |
| 全量回归 | 76 脚本，零**新增**失败（残餘 3 档 4 项见 §5.4） |
| `01-check_skills` | 27/27 |
| `02-check_affixes` | 14/0 |
| `03-check_equipment` | 36/0 |
| `04-check_balance` | 46/0（5 待修基线） |
| `05-check_monster_level_boss --repo` | 84/2（基线） |
| `06-check_special_modes --repo` | **202/0** |
| `07-check_dev_tasks --repo` | **212/0** |
