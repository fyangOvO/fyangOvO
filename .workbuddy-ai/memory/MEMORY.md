# 项目长期记忆 — 七傳說

## 当前项目：暗黑刷宝 ARPG（装备驱动刷宝类）

### 技术基线（2026-09-16 用户确认）
- 引擎：Godot 4（GDScript / C#）
- 平台：PC / Steam
- 联机：纯单机（无服务器）
- 美术：AI 生成 + 后期精修
- 核心玩法：装备驱动；**局内成长 + 局外成长**双线并行

### 阶段划分约定
0 立项与设计 → 1 项目基建 → 2 核心战斗 → 3 装备系统 → 4 局内成长 → 5 局外成长 → 6 内容生产 → 7 UI/UX → 8 系统与打磨 → 9 Steam 发布

### 优先级定义
- P0 = MVP 核心（跑通核心循环）
- P1 = 首个可玩版本
- P2 = 打磨与上线
- P3 = 上线后迭代

### 协作约定
- 规划与报告产物统一存放于 `deliverables/gstack/`
- 命名规范：`<场景类型>-<主题简称>-<YYYY-MM-DD>.md`

### ⚠️ 仓库安全铁律（2026-09-20 事故后确立，必须遵守）
本仓库**无 remote**（纯本地），`.git` 是唯一副本。2026-09-20 一次 `git stash push -u`
被 SIGTERM 中断后 `.git` 整体被移入回收站，全库险些灭失。因此：
- **禁用**：`git stash`（尤其 `-u`/`-a`）、`git gc`、`git prune`、`git reset`、
  `git checkout`、`git clean`、`git read-tree`、`git filter-branch`。
  仅允许 `git add` / `commit` / `status` / `log` / `diff`。
- **测基线一律「复制文件到外部临时目录」**，禁止原地改仓库 git 状态。
- 备份：`.workbuddy-ai/backups/git-<日期>/.git`（已 gitignore，见其 `README.md`）。
  **每次重大提交后需刷新**，否则备份过期。
- 清理残留一律 `mv` 到 `.workbuddy-ai/trash/<日期>-<原因>/`，**不以 `rm` 直删**。
- 已知残留：缺失 tree `0e21f118`（历史提交 `4c66f836` 的 `deliverables/` 快照），
  仅影响该历史提交的 diff，**决定不修**（修需重写历史）。

### ⚠️ 唯一色源铁律（美术资产硬约束）
`game/scripts/core/game_constants.gd:607`：**烘焙图像资产（PNG 精灵 / 图标 / tile）
全部像素必须落在 `PALETTE_ALL`**（44 色，`:654`；校验 `palette_contains()` `:659`）。
⇒ 任何外部素材（含 aigei / CC0 下载）**必须先做色板量化**才能入
`game/assets/tilesets/`。程序化生成的图集必须直接取自 `PALETTE_ALL`。
**UI 主题构建也受本铁律约束**（`palette_contains()` 的注释明列该用途）。
美术规范权威文档：`deliverables/gstack/art-style-and-ai-pipeline-phase0-0.7-2026-09-16.md`
（§1.1：俯视 / Tile 32×32 / 角色 48×48 / 48 色板单精灵 ≤24 / 只允许整数缩放）。

### ⚠️ 视口铁律（2026-09-21 实测确认，与旧文档冲突）
`game/project.godot:44-51`：**视口 = 640×360**，`stretch/mode=canvas_items`、
`aspect=keep`、**`scale_mode=integer`**。
⇒ 可见世界 = **20 列 × 11.25 行 tile**（32px tile），**屏幕装不下一个完整房间**。
⇒ 字号只有 11/12px、布局余量极小，都是这个画布尺寸决定的。
⇒ ⚠️ `game/README.md` 仍写「1920×1080…一屏 60 tile」，**是过期的**，别照它算。

### 关卡地图：手绘 vs 程序化（2026-09-21 实测）
- `LevelGenerator.generate()`：关卡数据带 `layout.cells` ⇒ **手绘分支**（`_generate_authored()`）；
  否则走程序化。判定用 **4 连通 flood fill**，`AUTHORED_BLOCKING = [TILE_WALL, TILE_OBSTACLE]`
  ⇒ **障碍也挡人**，校验时会拒掉 6 类非法图（`verify_level_gen.gd` H 段）。
- ⚠️ **手绘关卡完全不走 RNG**（`_generate_authored()` 不调用任何 `rng.*`）⇒ 播不播种都**每局相同**；
  只有**程序化且无 `layout.seed`** 的关卡才每局重随机（`level_scene.gd:354-356`）。
- 当前手绘：`ch1_l01`（墙 40% / 可走 59% / 障碍 1%，指纹 775561156）、`ch1_l02`（46% / 52% / 2%）。
  其余 18 关程序化（墙 58–68% / 可走 31–40%）⇒ 「一堵绿砖墙」的量化根因。
- 体检工具：`game/tools/probe_level.gd` + `res://tools/probe_level.tscn`
  （墙/地占比、出生点邻域、4 连通可达、碰撞形状逐格 vs 贪心合并、布局指纹、ASCII 预览）。
  连跑多次指纹相同 = 地图已稳定的直接证据。
- `_build_collision()`（`level_scene.gd`）对每个墙/障碍格建 `CollisionShape2D`，
  现已改为 **`_merge_blocking_rects()` 矩形并集**：`ch1_l01` 496→95（降 81%）、`ch1_l02` 574→127（降 78%）。
  等价性由 `verify_level_gen` 的 canary 逐格枚举点做集合比较盯死。

### ⚠️ `.tscn` 节点声明漏 `type=` 会被 Godot **静默丢弃**（2026-09-21 挖出）
`scenes/enemies/enemy_base.tscn` 的 `CollisionShape2D` 曾漏写 `type="CollisionShape2D"`
⇒ Godot 不报错、不崩溃，**只是那个节点不存在** ⇒ **从 2.4 到 2.6 所有敌人根本没有碰撞体**。
- **哨兵**：Godot 会打印 `CollisionShape2D vanished` 一类警告。
  该 bug 期间有 **71 条**，被上一轮报告列为「既有、与本轮无关」——
  **那不是噪音，那就是症状本身。** 修好后 71 → 0。
- 排查手法（全仓库一次跑完）：
  `find . -name "*.tscn" | xargs grep -n '^\[node name="[^"]*" parent="[^"]*"\]$'`，
  命中即「既无 `type=` 又无 `instance=`」的非法声明（2026-09-21 全库扫完仅此一例）。
- ⇒ **见到成批量的同类警告，先当成 bug 症状查，不要归为「既有噪音」。**

### ⚠️ `UISkin` 工厂**静默返回 null** ⇒ 素材/键名错会静默降级（2026-09-21 事故）
`UISkin.texture()` / `dnf_texture()` / `panel_stylebox()` 在素材缺失或**逻辑键名写错**时
**返回 null 并把 null 缓存进 `_cache`**；调用方一律 `continue` / 跳过 ⇒
**画面上什么都没有，而回归全绿、无头测试也看不见**（它只断言控件存在）。
- 2026-09-21 实例：交付截图 12:13 抓、`.import` 13:51 才生成 ⇒ 立绘 + 3 把武器一个都没建，
  背景静默回退成兜底图，而 53 个回归脚本全绿。见 `verify_dnf_ui.gd`（24 条断言，为此而写）。
- 键名以 `ui_skin.gd` 的 `TEX` / `TEX_DNF` 字典为准，**不要凭直觉拼**：
  例如 `quest_marker_24.png` 的逻辑键是 **`"marker"`**，不是 `"quest_marker"`。
- ⇒ **改任何素材路径/键名后，必须真渲染抓图目视确认它真的出现在画面上。**
- ⇒ 判断「Godot 能否加载」要用 `ResourceLoader.exists()`；
  判断「文件在不在磁盘」才用 `FileAccess.file_exists()`。**两者不可互相替代。**

### 难度星级契约（2026-09-21 修正）
`DifficultyTier` = `NM1=0 … NM5=4`（`game_constants.gd:380-384`），`DIFFICULTY_TIER_COUNT = 5`，
名字「梦魇 I」–「梦魇 V」⇒ **没有 0 星档**。
⇒ 亮灯数必须为 **`lit = clampi(tier, 0, 4) + 1`**（NM1→1 … NM5→5）。
- `clampi(tier,1,5)`（旧码）缺陷在**上限**：`lit` 最多 4 ⇒ NM5 只亮 4 颗，且 NM1/NM2 长得一样。
- `clampi(tier,0,5)`（曾提议）会把 NM1 变成 0 颗 ⇒ **引入** bug。
- ⚠️ 不要让 `lit==0` 时整排不建 —— `verify_ui_assets.gd:348` 断言「5 颗已建立」。
- ⚠️ `verify_ui_assets.gd` **没有**亮灯数断言 ⇒ 改对了回归照样全绿，**必须真渲染自查**。

### 敌人 AI 没有寻路（2026-09-21 确认，墙碰撞生效后的新风险）
`enemy_base.gd` 只有 `move_and_slide()`（`:745`），**无 `NavigationAgent2D` / 无 pathfinding**
⇒ 怪是「直线追人 + 沿墙滑行」。墙生效**前**怪穿墙直达玩家所以永远追得到；
生效**后**遇凹形墙（U 形/内嵌房间）可能**沿墙滑进死角停住**。
⇒ **「出生点合法」≠「怪追得到人」**，改地图后要单独验可达性。
层位现状：敌人 `layer=3/mask=3`、玩家 `layer=2/mask=1`、地形 `layer=1/mask=0`；
Godot 配对是**双向任一命中即交互** ⇒ 只改敌人 `mask` 去不掉敌人互卡（no-op），需重构层位。


### ⚠️ 待用户确认的冲突
「平台 PC / Steam」vs 任务清单 `game-dev-task-plan-diablo-loot-arpg-2026-09-16.md:377`
**D7 = 纯自玩、不上线**（原话「不需要考慮上線，本地先運行」）。后者更新，影响发行与
素材授权口径，**待用户拍板**。

### 已知素材站结论
- **aigei.com（爱给网）已上登录墙**：未登录时页面无 `data-original` 属性，
  站方 JS 返回「当前 IP 访问频率过高」；下载还需登录 + 爱给币。
  仓库内 `game/tools/aigei_batch_dl_*.py` **只是下载器不是登录器**，无法绕过。
  ⇒ 外部免费素材改走 **CC0 源**（DCSS 32×32 tileset 等）。

