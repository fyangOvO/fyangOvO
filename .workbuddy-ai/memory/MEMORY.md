# 项目长期记忆 — 七傳說

## 当前项目：暗黑刷宝 ARPG（装备驱动刷宝类）

### 技术基线（2026-09-16 用户确认）
- 引擎：Godot 4（GDScript / C#）
- 平台：PC ｜ ⚠️ **2026-09-23 用戶裁定「代碼不上線」⇒ 不做 Steam 發行，純本地自玩**
  （原「PC / Steam」記述就此降級為歷史，詳見下方「已拍板」節）
- 联机：纯单机（无服务器）
- 美术：AI 生成 + 后期精修
- 核心玩法：装备驱动；**局内成长 + 局外成长**双线并行

### 📦 當前可運行包（2026-09-23 最終）
```
D:\七傳說\game\build\七傳說.exe
```
128,723,832 B ｜ 導出 2026-09-23 17:04:46 ｜ MD5 `1078e026f6da49b7129b0e216e0f73fb`
（含 ch1_l05/l06 P0 修復；舊包與存檔備份在 `build/_prev/`，未刪）

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
- 当前手绘 **4 关**：`ch1_l01`（40×30，地705/墙483/障12，m23 e2 p3）、
  `ch1_l02`（40×30，地626/墙549/障25，m48 e2 p3）、
  `ch1_l05`（26×44，地769/墙357/障18，m41 e3 p3）、
  `ch1_l06`（48×36，地960/墙748/障20，m32 e4 p3 **B**，objective=kill_boss）。
  其余 16 关程序化（墙 58–68% / 可走 31–40%）⇒ 「一堵绿砖墙」的量化根因。
- 字符图例（`AUTHORED_CHARS`）：`#`墙 `.`/` `地面 `o`障碍 `@`玩家(恰好1) `m`杂兵(≥1)
  `e`精英(==`elite_count`) `B`BOSS(`boss_id`非空⇒恰好1) `p`拾取/祭坛(≥1)。
  **实际刷怪数 = `m` + `e` + (`B`?1:0)**，與 `total_monster_budget` **無強制等式**。
- ⚠️ **手绘关卡有一条硬数值约束**：`'m'`（杂兵）标记数**不得超过该关 `monster_entries` 的
  `Σcount_max` 预算**（`level_generator.gd:385-390`，只比 `'m'`，不含 `'e'`/`'B'`）。
  超了不是「自动裁剪」，而是 **整关校验失败 ⇒ `_generate_authored()` 整体放弃**
  ⇒ `player_spawn = (-1,-1)`、可达 0 格、无怪无 BOSS ⇒ **整关不可玩**。
- ✅ **2026-09-23 P0 已修復**（採「選項 b：提預算」）：`ch1_l05` `Σcount_max` 34→**62**、
  `ch1_l06` 21→**66**，與 `total_monster_budget`(62/66) 對齊。
  **關鍵性質：手繪模式 `count_max` 不參與刷怪**（只按標記數生成）⇒ 修復**不改變任何實際刷怪數**，
  純修校驗閘門。驗證：`verify_level_gen` 6→**0**、`verify_terrain8b` 6→**0**、
  `verify_boss_awaken8c` 2→**0**；連通性 l05 769/769、l06 960/960。
- ⚠️ **不可動 `total_monster_budget`**：它是**權威設計字段**，被 `verify_metrics` / `verify_polish9x`
  按步驟 9 曲線 `40→50→55→58→62→66` 斷言。預算不一致時**改 `Σcount_max`，不要改它**。
- 🔸 殘留 P4：`ch1_l02` `'m'`=48 ≤ `Σcount_max`=**51** > `total_monster_budget`=**50**
  （校驗只看 `'m'` 是否超 `Σcount_max`，故不卡）⇒ 殘餘 1 點不一致，非阻塞。
- ⚠️ 手绘关卡**用 `boss_id` 字段驅動 BOSS**；`level_scene.gd:534-537` 另有一處按
  `monster_entries[].is_boss` 判定，**措辭會誤導**（寫成「沒有任何 is_boss=true 的條目」，
  但實際上 `ch1_l06` **確實有** `is_boss: true`）。該 WARNING 的**真實成因是生成被中止**
  ⇒ 它是**症狀不是原因**。建議改措辭為「本關 BOSS 未刷出（生成器可能已放棄生成）」。
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


### ⚠️ 打包 / 回歸工具鏈（2026-09-23 實測，必須遵守）

**① `APPDATA` 空串 ⇒ 導出失敗 + 靜默漏清存檔（本 shell 實測就是空的）**

`APPDATA` 為空時 Godot 把數據目錄解析成**相對路徑** `./Godot/`，後果有兩個：
- **導出直接失敗**：Godot 去 `./Godot/export_templates/4.7.2.stable/` 找模板，
  模板實際在 `%APPDATA%\Godot\export_templates\4.7.2.stable\`（109 MB 在位）。
  報錯 `在預期路徑處未找到導出模板：...windows_release_x86_64.exe`。
- **`package_demo.py` 的「清數據」鐵律被靜默繞過**：兩個掃描根（`%APPDATA%` 推導 + 工程內鏡像）
  都落空，真實存檔一個都沒清，腳本卻只印「跳過 不存在」。

⇒ **打包一律這樣調用**（`run_regression.py` 早就把這個坑寫進註釋了，`package_demo.py` 沒防）：
```bash
cd D:/七傳說/game && APPDATA='C:\Users\11265\AppData\Roaming' python tools/package_demo.py --backup
```
建議給 `package_demo.py` 加前置校驗：`APPDATA` 為空即中止，別靜默產出「沒清乾淨」的包。

**② `run_regression.py` 的 `NO-RESULT` 是誤報，不等於失敗**

結果行正則只認「`項失敗` / `全部通過（` / `項未通過`」，**不認繁體「全部通過」與
「`27 通過 / 0 失敗`」格式** ⇒ 5 個腳本被判空轉（`verify_class_select` / `verify_consumable` /
`verify_equip_panel` / `verify_hud` / `verify_panel_unify`），實查日誌末行皆為全綠。
⇒ **看到 `NO-RESULT` 先讀 `%TEMP%\ge_regress_fail_<name>.log` 再定性。**

**③ 回歸斷言與實現已漂移（2026-09-23 在案，非玩法 bug）**

| 測試 | 寫死 | 實際 |
|---|---|---|
| `verify_fix85` | 技能 8 | **12** |
| `verify_skill_panel` | `save_version == 3` | `SAVE_VERSION = 4` |
| `self_check` / `verify_settings` | 音效註冊表 9 條 | **10**（8E 加 `boss_roar`） |
| `self_check` | 怪物 L20 HP≈11635 / DMG≈237.83 | 步驟 9 改係數後實為 **HP 4404.2 / DMG 94.12**（差 2.6× / 2.5×） |

⚠️ **`self_check` 那兩條斷言的來源是一段過期註釋**：`game_constants.gd:462-476` 仍寫
`Monster_HP(L)=100.7×1.284^(L-1)` / `Monster_DMG(L)=5.61×1.218^(L-1)`、錨點 `L20 HP 11,635 / DMG 237.83`，
而**下方 478/480 行的常量已是 `1.22` / `1.16`**（行內註「9.x 調優：1.284→1.22，裸裝 Lv20 TTK 150→45 擊」）。
⇒ **改這批時註釋塊與 `self_check` 必須一起改**（HP/DMG 是配套斷言，只改一半會誤導）。

**④ 導出就緒缺口 → 已因「代碼不上線」移出範圍**

`export_presets.cfg` 的 `application/icon` / `file_version` / `product_version` /
`company_name` / `copyright` **全空**，且 `codesign/enable=false`
⇒ exe 無圖標、屬性頁空白、Windows SmartScreen 報「未知發布者」。
**但用戶已裁定純本地自玩 ⇒ 以上皆不影響運行，不要再當整改項提。**（見下「已拍板」節）

**⑤ 上線前全檢結論（2026-09-23）**：零網絡能力 · 零命令執行 · 零硬編碼密鑰 · 零遞迴刪除；
存檔 SHA-256 **只防意外損壞、不防人為改檔**（單機無排行榜則無影響）；
`encrypt_pck=false`（PCK 可解包，單機可接受）；`script_export_mode=2`（源碼非明文 ✅）。
報告：`deliverables/gstack/上线前全检报告-2026-09-23.md`。

### ✅ 已拍板：代碼不上線（2026-09-23 用戶確認）

原話「**代码不上线**」⇒ **純本地自玩，不做 Steam 發行**。與任務清單 D7「純自玩」一致，
長期掛着的那條衝突（PC/Steam 發行 vs 不上線）**就此關閉**。

**移出範圍（不必做）**：
- 應用圖標 / `file_version` / `product_version` / `company_name` / `copyright`
- 代碼簽名（`codesign/enable=false` 無所謂，SmartScreen「未知發布者」警告可無視）
- PCK 加密 / 素材防提取（`encrypt_pck=false` 可接受）
- 存檔防篡改（SHA-256 只防意外損壞即足夠）

**仍在範圍（必須做）**：
- **本地可玩性** —— P0 關卡不可玩（如 ch1_l05/l06）必須修
- 存檔可靠性（防意外損壞 / 崩潰不產生半截檔）
- 素材授權乾淨（自用仍建議留 OFL 等授權文件）

⇒ ⚠️ **不要**再以「上架就緒」為由提圖標/版本號/簽名/加密的整改項。

### 已知素材站结论
- **aigei.com（爱给网）已上登录墙**：未登录时页面无 `data-original` 属性，
  站方 JS 返回「当前 IP 访问频率过高」；下载还需登录 + 爱给币。
  仓库内 `game/tools/aigei_batch_dl_*.py` **只是下载器不是登录器**，无法绕过。
  ⇒ 外部免费素材改走 **CC0 源**（DCSS 32×32 tileset 等）。

