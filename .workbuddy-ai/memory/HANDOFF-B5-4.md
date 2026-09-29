# 交接说明 · B5-4 开工 — 给下一个接手的 AI（豆包）

> **生成时间**：2026-09-29 深夜
> **一句话现状**：B5-1 / B5-2 / B5-3 已全部提交（本地，未 push）。**下一个子批 = B5-4（专属词缀 + 掉落特效，6-W6-18 / 6-W6-19）**，两工单均 🔴 P0、含静默失败风险。
> **开工前顺序**：读完本文 → `.workbuddy-ai/memory/2026-09-29.md` §十二 → 按 §5 动手。

---

## 0. TL;DR

1. 工作树应是**干净**的（最近两个 commit：`10517b9` B5-3 代码 / `e4abcdd` B5-3 记忆）。
2. B5-4 = **6-W6-18**（专属词缀 18 条 + AffixData.source）+ **6-W6-19**（特殊档光柱/落地演出）。
3. 两单都有「静默失败」陷阱，见 §4，**不改字段本体只加数据 = 永远通过的假校验**。
4. 收尾照旧：parse 预检 → 单测 → 06/07 重基线 → 全量回归零新增红 → 写记忆 → 2 个本地 commit（**不 push**）。

---

## 1. 环境速查（直接复制）

| 项 | 值 |
|---|---|
| 项目根 | `D:\七傳說` |
| 游戏工程 | `D:\七傳說\game` |
| 策划案目录 | `D:\七傳說\deliverables\gstack\策划案` |
| Python（**必须这个**） | `C:/Users/11265/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe` |
| Godot 控制台版 | `C:\Users\11265\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe` |

```bash
# 解析预检
cd D:/七傳說/game && "<GODOT>" --headless --path . res://tools/parse_all.tscn
# 全量回归
cd D:/七傳說 && "<PY>" game/tools/run_regression.py
# 策划校验器（06/07 必带 --repo）
cd D:/七傳說/deliverables/gstack/策划案 && "<PY>" 06-check_special_modes.py --repo "D:/七傳說"
cd D:/七傳說/deliverables/gstack/策划案 && "<PY>" 07-check_dev_tasks.py --repo "D:/七傳說"
```

---

## 2. git 铁律（违反会丢工作）

- 只用 `add / commit / status / log / diff`。**禁** `stash / reset / checkout / clean / gc / prune`。
- **只本地 commit，绝不 push**（B5 阶段；origin = github.com/fyangOvO/fyangOvO.git 仅备查）。
- 删文件一律 `mv` 到 `.workbuddy-ai/trash/<日期>-<原因>/`，不用 `rm`。
- 临时脚本别留在仓库根/`.workbuddy-ai/`，用完 mv 进 trash。

---

## 3. B5 八子批进度

| 子批 | 内容 | 状态 |
|---|---|---|
| B5-1 | 存档与门票底座（01/02/20） | ✅ 已提交 |
| B5-2 | 稀有度扩容 8→10（11/12/13） | ✅ 已提交（c1a17af / eb77b9b） |
| B5-3 | 稀有度连带与守卫（15/16/17/Q1/Q7/Q8） | ✅ 已提交（10517b9 / e4abcdd） |
| **B5-4** | **专属词缀 + 掉落特效（18/19）** | 🔴 **本批重点** |
| B5-5 | BOSS 二阶段（08/09/10） | 待做 |
| B5-6 | 塔/深渊关卡与入口（07/05/06/03/04） | 待做 |
| B5-7 | 特殊装闭环（Q2/Q3/Q4/Q5/Q6） | 待做（C9：Q5+Q6+Q7 同批） |
| B5-8 | 校验补齐 + E 组重基线 | 待做 |

---

## 4. B5-4 两工单（🔴 都有静默失败）

### 6-W6-18 — 专属词缀 18 条 + AffixData.source
- 文件：`affix_data.gd`、`affix_roller.gd:116-129`、`game/data/affixes/*.json`。
- **🔴 陷阱**：`AffixData` 目前**没有 source 字段**。不扩字段就做不了来源过滤 ⇒ 所有装备都可能抽到「深渊专属/塔专属」词缀，**且全程零报错**。
- 要做：AffixData 加 `source`（如 `"abyss"` / `"tower"` / `""`=通用）；词缀池 roll 时按底材来源（特殊档底材是深渊还是塔）过滤；新建 18 条专属词缀 JSON。
- 验收 verify 组：`6-SL SL1–SL18`。

### 6-W6-19 — 特殊档光柱 + 落地演出 + 提示分支
- 文件：`game_constants.gd:124-138`（BeamShape 枚举已扩）、`loot_drop.gd`、`pickup_toast.gd`。
- **🔴 陷阱**：`loot_drop.gd:_draw_beam()` 现在**只按高度画渐变柱，不按 BeamShape 分支**。光扩枚举 ⇒ 深渊（SPECIAL_PRISM）和塔（SPECIAL_SPIRE）两档光柱视觉**完全一样**，静默。
- 要做：`_draw_beam()` 按 `GameConstants.RARITY_BEAM_SHAPES[rarity]` 分支画（棱镜柱 / 竖塔柱）；拾取 toast 按特殊档给提示分支。
- 另：`6-W6-20` 的 `rare_loot_spawned` emit 目前**无消费者**，本批接光柱 FX。

---

## 5. 开工清单

1. 读 `game/scripts/loot/affix_roller.gd:100-140`（词缀 roll 链路）和 `game/resources/loot_drop.gd:_draw_beam`（已读过，在 loot_drop.gd:171）。
2. 扩 `AffixData.source` + config_loader 解析 + 18 条专属词缀 JSON（先看现有 `data/affixes/` 格式）。
3. 改 `_draw_beam()` 按 shape 分支。
4. parse → 单测 → 06/07 重基线（SAVE_VERSION 现 = **7**，别回退断言）。
5. 全量回归零新增红 → 写记忆 → 2 个本地 commit。

---

## 6. 当前关键常量（别改错）

- `RARITY_COUNT = 10`；`SAVE_VERSION = 7`；`PALETTE_DEFINED_COUNT = 46`。
- Rarity 0..9：common/magic/rare/epic/legendary/mythic/set/hidden/**special_abyss=8/special_tower=9**。
- 装备总数 **68**（62 + 6 特殊底材，各带 `unique_group = 自身 id`）。
- 三档掉落表权重各 10 位、和=100（normal/elite/boss，见 monster_loot_tables.json）。

---

## 7. 验收基线（对照用）

| 校验器 | 目标 |
|---|---|
| parse_all | 246 档全可解析 |
| 06 --repo | **202/0** |
| 07 --repo | **212/0** |
| 全量回归 76 脚本 | 零**新增**失败 |

**残馀基线（非本批造成，勿修）**：
- `self_check` 2 项：怪物 L20 基准 HP/DMG（B6 旧值）。
- `verify_player` 1 项（手柄映射）。
- `verify_choice_panel` 1 项（裸 Color）。
- `verify_buff` 计时项（限时盾到期）全量跑偶发红、单跑全绿 ⇒ flake。

---

## 8. 已踩坑（别再踩）

1. **按稀有度定长的数组，RARITY_COUNT 扩容后必须全仓 grep**：B5-2 漏了 `affix_roller.EMPOWER_CHANCE_BY_RARITY`（B5-3 才补）。改断言前先查数组本体是否真补到 10。
2. **策划校验器 06 E 组 / 07 E-repo 是「现状快照」**，功能落地后要**翻转语义**（`not in`→`in`、`not any`→`any`、`bool(hits)`→`not hits`），不是只改数字。
3. **断言禁写字面量**：档数/版本号/色板数一律引用 `GameConstants.*`，不写 `== 8 / == 6 / == 44`。
4. **特殊档 8/9 不可逆**：`RARITY_COUNT` 若回退 8，旧档 8/9 会被压成 7。备份在 `game/.workbuddy_pre_b5_backup/`。
5. **UISkin.RARITY_SLOT（ui_skin.gd:354）是 0..7 映射**，缺 8/9 ⇒ 退化成普通格（非阻断，视觉待后续批）。
6. **自洽式伪校验**：脚本用自己硬编码常量算自己断言 = 永远通过。看到「永远通过」先查常量是引用还是副本。
