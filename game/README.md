# 「七傳說」· Godot 4 项目骨架

> 纯单机 2D 俯视刷宝 ARPG —— 局内三选一成长 + 局外装备锻造双线养成。
> 本目录是**阶段 0–10 已完成**（含工程骨架、战斗 / 装备 / 局内局外成长 / 内容 / UI / 系统打磨 / 本地打包）
> **+ 阶段 11（残项收敛 / 发布候选 RC）进行中**的工程与可玩 demo，
> 含项目配置、数据结构、全局服务、**UI 框架与主题（任务 1.6）**，
> 以及**玩家控制器（2.1）、攻击 / 技能（2.2）、伤害计算管线（2.3）、
> 敌人 AI 基类（2.4）、碰撞 / 命中判定（2.5）、生命 / 异常状态（2.6）、
> 掉落 / 拾取系统（2.7）与打击感（2.8）**。
> 装备生成 / 关卡内容已随阶段 3–6 落地。

| 项目 | 值 |
|---|---|
| 引擎 | Godot 4.x（GDScript 2.0） |
| 项目根目录 | `D:\七傳說\game` |
| 主场景 | `res://scenes/main/main.tscn` |
| 视口 | 1920×1080，窗口化，`canvas_items` 拉伸 |
| 渲染器 | GL Compatibility（2D 最佳兼容性） |
| 纹理过滤 | **Nearest**（像素风铁律） |
| 平台 | Windows 本地运行 · 不上线 · 不发行 · 无联网 |

---

## 一、如何打开

### 1. 安装 Godot 4

从 <https://godotengine.org/download/windows/> 下载 **Godot 4.x stable 标准版**
（不要下 .NET/C# 版，本项目只用 GDScript）。

### 2. 导入项目

1. 打开 Godot 项目管理器 → 点 **「导入」**
2. 路径选择 `D:\七傳說\game\project.godot`
3. 点「导入并编辑」

首次导入时 Godot 会生成 `.godot/` 缓存目录与各资源的 `.import` 文件，属正常现象（已在 `.gitignore` 中忽略）。

### 3. 运行

按 **F5**（或右上角 ▶）。主场景会显示一个**骨架自检面板**，逐项列出常量表尺寸、
数据表条数、数据合法性、存档目录可用性 —— 全部为绿色 `[OK]` 即代表骨架就绪。

> 本骨架已在 **Godot 4.7.2.stable** 上实跑验证通过（骨架自检 **111/111**、存档 **26/26**、
> 玩家 **33/33**、UI **34/34**、技能 **45/45**、伤害管线 **40/40**、敌人 AI **34/34**、
> 命中 **25/25**、生命 **25/25**、掉落 **20/20**、打击感 **18/18**、装备数据结构 **27/27**、词缀生成器 **24/24**、掉落权重表 **18/18**、锻造洗练 **22/22**、传奇特效 **26/26**、背包仓库 **28/28**、装备对比 **21/21**、分解合成 **33/33**、属性结算 **26/26**、套装系统 **25/25**、红装彩装 **27/27**、局内成长 **23/23**、关卡商店 **16/16**、本局结算 **14/14**、局外成长 **45/45**、关卡地图 **22/22**、怪物词缀 **24/24**、BOSS 机制 **32/32**、技能库 **49/49**、装备库 **14/14**（6.5）、音效 **9/9**（6.6）、UI/UX **24/24**（7.x）、存档 **15/15**（8.1）、设置 **12/12**（8.2）、性能 **10/10**（8.3）、平衡仿真 **8/8**（8.4）、回归红线 **8/8**（8.5）、稳定性 **6/6**（9.3）、导出验证 **5/5**（9.1）、流程自测 **7/7**（9.2）），
> 详见第 5 节与第 9 节「已实测验证」。
> 你只需按第 5.1 节打开一次确认即可。

---

## 二、目录结构

```
game/
├── project.godot               # 项目配置：渲染 / 视口 / 输入映射 / Autoload / 物理层
├── export_presets.cfg          # Windows 导出预设（任务 1.9）
├── icon.svg                    # 项目图标
├── README.md                   # 本文件
│
├── scenes/                     # 场景（.tscn）
│   ├── main/                   #   main.tscn（启动分流）/ main_menu.tscn / hub.tscn（据点）
│   ├── levels/                 #   关卡场景
│   │   └── level.tscn          #     通用关卡容器（集成层阶段 3；20 关共用一份，
│   │                           #     差异全由 on_scene_entered 的 level_id + difficulty_tier 驱动）
│   ├── enemies/                #   敌人场景（任务 2.4）
│   │   └── enemy_base.tscn     #     敌人基类（CharacterBody2D + 碰撞，2.7 挂生命组件）
│   ├── loot/                   #   掉落场景（任务 2.7）
│   │   └── loot_drop.tscn      #     地面掉落物（光柱 / 自动拾取）
│   ├── juice/                  #   打击感场景（任务 2.8）
│   │   ├── damage_number.tscn  #     伤害飘字（Cubic-11 像素字 + 深描边）
│   │   └── pixel_burst.tscn    #     死亡像素粒子 + 白色扩散环
│   ├── player/                 #   player.tscn（玩家角色，任务 2.1）
│   ├── combat/                 #   战斗场景：damage_dummy.tscn（受击靶，任务 2.2）
│   ├── enemies/                #   怪物场景（阶段 2 填充）
│   └── ui/                     #   界面场景（阶段 2 填充）
│       └── theme/              #   theme.tres（任务 1.6，项目默认主题产物）
│
├── scripts/                    # 脚本（.gd）
│   ├── autoload/               #   全局单例（见第三节）
│   │   ├── event_bus.gd        #     事件总线（任务 1.4）
│   │   ├── config_loader.gd    #     配置加载器（任务 1.7，含 skills 表）
│   │   ├── save_manager.gd     #     存档管理器（任务 1.8）
│   │   └── scene_manager.gd    #     场景管理器（任务 1.5）
│   ├── core/                   #   核心常量与引导
│   │   ├── game_constants.gd   #     全局常量（任务 1.2，含 48 色板 / UI 规范 / 八·七 攻击与技能段）
│   │   ├── input_remapper.gd   #     输入重映射 + 手柄热插拔（任务 1.3 · Autoload）
│   │   └── main.gd             #     主场景引导 + 骨架自检
│   ├── player/                 #   角色逻辑
│   │   └── player_controller.gd #    玩家角色控制器（任务 2.1；普攻假连段 + 技能转发，任务 2.2）
│   ├── combat/                 #   战斗逻辑（任务 2.2–2.3、2.5–2.7）
│   ├── enemies/                 #   敌人 AI（任务 2.4）
│   │   ├── mana_pool.gd        #     法力池（回复 / 消耗 / 减耗）
│   │   ├── skill_controller.gd #     技能控制器（冷却 / 法力 / 施放分派 / 命中走伤害管线）
│   │   ├── damage_calc.gd      #     伤害计算管线（暴击 / 元素 / 减伤，任务 2.3）
│   │   ├── hit_query.gd        #     命中判定几何（圆/扇形/矩形 + 目标半径扩展，2.5）
│   │   ├── damage_dummy.gd     #     受击靶（验证占位；2.4 敌人基类已实现同接口）
│   │   ├── health_component.gd #     生命组件（减伤链 / 护盾 / 异常，2.6；敌人收编，2.7）
│   │   ├── enemy_base.gd       #     敌人基类（巡逻/追击/攻击状态机，2.4；掉落接入，2.7；词缀钩子，6.2；BOSS 阶段，6.3）
│   │   ├── affix_controller.gd #     精英词缀池（静态：急速/吸血/爆炸/回响/荆棘/闪现，6.2）
│   │   └── boss_phase_controller.gd #  BOSS 阶段机制（静态：阶段门/技能集/召唤/狂暴，6.3）
│   ├── loot/                   #   掉落逻辑（任务 2.7、3.2）
│   │   ├── loot_roller.gd      #     掉落引擎（触发 / 件数 / 类型 / 稀有度 / 底材，纯静态）
│   │   ├── affix_roller.gd     #     词缀生成器（条数拆分 / 池候选 / 权重互斥 / 品质 / 强化 / 神话槽，3.2）
│   │   └── loot_drop.gd        #     地面掉落物（物件 / 光柱 / 自动拾取）
│   ├── forge/                  #   锻造 / 材料（任务 3.4 / 3.8）
│   │   ├── forge_controller.gd #     强化 / 洗练纯结算（成本 + 掷骰，不扣钱包）
│   │   ├── material_bag.gd     #     材料包（金币 / 魔石 / 尘 / 精粹 / 结晶）
│   │   ├── dismantle_controller.gd #  分解产出（GDD 5.3 表）
│   │   └── craft_controller.gd #     合成配方（材料 → 装备，4 档）
│   │   └── mythic_reroll_controller.gd # 红装神话词缀重铸（结晶 ×2，见 5.25 节）
│   ├── legendary/              #   传奇特效（任务 3.5）
│   │   └── legendary_effect_system.gd #  特效触发结算（纯静态：数据访问 + 冷却/叠层）
│   ├── sets/                   #   套装（任务 3.10）
│   │   └── set_system.gd       #     套装计数 / 档位 / 加成并入属性结算
│   ├── run/                    #   局内成长（阶段 4）/ 地图生成（阶段 6）
│   │   ├── level_generator.gd  #     关卡 / 地图程序化生成（拒绝采样房间）
│   │   ├── run_progression.gd  #     局内等级 / 经验（1–10 级，出关清零）
│   │   ├── rune_pool.gd        #     三选一选项池（15 选 + 30% 上限移除）
│   │   ├── run_buff_system.gd  #     局内 Buff（选项 / 祭坛 / 连杀）
│   │   ├── run_shop.gd         #     关卡内商店（生成 / 定价 / 购买）
│   │   └── run_result.gd       #     本局结算（存活 / 掉落 / 评分）
│   ├── account/
│   │   ├── account_level.gd    #     账号 / 巅峰等级（180×L^1.6，1–60）
│   │   ├── talent_tree.gd      #     天赋树（3 分支 × 20 节点）
│   │   ├── unlock_system.gd    #     解锁系统（关卡 / 梦魇 / 仓库页）
│   │   ├── chapter_reputation.gd #   章节声望（每级 +1% 经验 +1% 金币）
│   │   └── achievement_system.gd # 成就系统（外观奖励，数据 data/achievements.json）
│   ├── inventory/              #   背包 / 仓库（任务 3.6）
│   │   └── inventory.gd        #     网格数据层（增删 / 交换 / 整理 / 排序 / 仓库转移）
│   ├── juice/                  #   打击感（任务 2.8）
│   │   ├── juice_fx.gd         #     打击感控制器（Autoload：事件 → 表现）
│   │   ├── damage_number.gd    #     伤害飘字（上飘 / 淡出 / 暴击橙红）
│   │   ├── pixel_burst.gd      #     死亡像素粒子（碎片 + 扩散环）
│   │   └── screen_shake.gd     #     震屏（Camera2D offset 抖动衰减）
│   ├── items/                  #   装备 / 词缀逻辑（阶段 3；2.7 掉落已独立到 loot/）
│   │   ├── gem_system.gd       #     宝石镶嵌（4 档 × 3 色，任务 5.5）
│   │   └── hidden_growth_controller.gd # 彩装成长（纯静态：累积 / 上限 / 并入结算）
│   └── ui/                     #   界面逻辑（任务 1.6、2.6）
│       ├── ui_theme.gd         #     UI 主题构建器（任务 1.6，程序化 Theme）
│       ├── health_bar.gd       #     HUD 血条（玩家 16px，任务 2.6）
│       ├── inventory_panel.gd  #     背包 / 仓库网格面板（任务 3.6）
│       ├── equipment_compare.gd #    装备对比（纯静态：stat_key 汇总 / 新旧 diff）
│       ├── compare_panel.gd    #     装备对比两列面板（任务 3.7）
│       ├── set_panel.gd        #     套装进度面板（6 段进度条 + 档位文案，3.10）
│       ├── choice_panel.gd     #     局内三选一面板（攻击/防御/资源三色卡，4.2）
│       ├── shop_panel.gd       #     关卡商店面板（商品列表 + 购买，4.4）
│       ├── result_panel.gd     #     本局结算面板（结算单 + 评级，4.5）
│       └── world_health_bar.gd #     世界血条（怪物头顶 8px，任务 2.6）
│
├── resources/                  # 自定义 Resource 类（数据结构的**代码定义**）
│   ├── affix_data.gd           #   词缀模板
│   ├── affix_roll.gd           #   一条已 roll 的词缀（实例数据）
│   ├── equipment_data.gd       #   装备底材模板
│   ├── equipment_instance.gd   #   一件具体装备（可入包 / 可存档）
│   ├── set_data.gd             #   套装定义（6 件套 + 2/4/6 档加成）
│   ├── monster_data.gd         #   怪物定义
│   ├── level_data.gd           #   关卡定义
│   ├── loot_table.gd           #   掉落表
│   ├── skill_data.gd           #   技能定义（id / 倍率 / 冷却 / 蓝耗 / 范围 / 元素，任务 2.2–2.3）
│   ├── damage_result.gd        #   单次命中结算结果（暴击 / 元素 / 减伤明细，任务 2.3）
│   └── save_data.gd            #   存档数据模型
│
├── data/                       # 配置数据（**纯 JSON，策划直接改**）
│   ├── equipment/              #   装备底材：weapons / armor / jewelry / set_pieces_*
│   ├── sets/                   #   套装定义：sets.json（3 组，独立目录以免被当作底材）
│   ├── affixes/                #   词缀：attack / defense / resource / special
│   ├── affix_pools/            #   词缀池表：pools.json（10 池，装备 affix_pool_ids 引用，任务 3.1）
│   ├── monsters/               #   怪物：monsters.json
│   ├── levels/                 #   关卡：chapter1.json
│   ├── loot_tables/            #   掉落表：monster_loot_tables.json（8 档权重）
│   └── skills/                 #   技能：skills.json（裂斩 / 旋刃 / 突进，任务 2.2）
│
├── tools/                      # 开发期验证脚本（**不进导出包**，非游戏玩法）
│   ├── verify_save.gd          #   存档系统实测（26 项，见 5.3 节）
│   ├── verify_save.tscn        #   上者的运行入口
│   ├── verify_player.gd        #   玩家控制器 + 输入系统实测（33 项，见 5.4 节）
│   ├── verify_player.tscn      #   上者的运行入口
│   ├── verify_skills.gd      #   攻击与技能系统实测（45 项，见 5.7 节）
│   ├── verify_skills.tscn    #   上者的运行入口
│   ├── verify_damage.gd      #   伤害计算管线实测（40 项，见 5.9 节）
│   ├── verify_damage.tscn    #   上者的运行入口
│   ├── verify_enemy.gd       #   敌人 AI 基类实测（34 项，见 5.10 节）
│   ├── verify_hit.gd         #   碰撞与命中判定实测（25 项，见 5.11 节）
│   ├── verify_health.gd      #   生命 / 异常状态实测（25 项，见 5.12 节）
│   ├── verify_loot.gd        #   掉落与拾取系统实测（20 项，见 5.13 节）
│   ├── verify_juice.gd       #   打击感系统实测（18 项，见 5.14 节）
│   ├── verify_equipment.gd   #   装备数据结构实测（27 项，见 5.15 节）
│   ├── verify_affix_roller.gd #  词缀生成器实测（24 项，见 5.16 节）
│   ├── verify_loot_tables.gd #   掉落权重表实测（18 项，见 5.17 节，含一局节奏仿真）
│   ├── verify_forge.gd       #   锻造 / 洗练实测（22 项，见 5.18 节）
│   ├── verify_legendary_effects.gd # 传奇特效实测（26 项，见 5.19 节）
│   ├── verify_inventory.gd   #   背包 / 仓库实测（28 项，见 5.20 节）
│   ├── verify_equipment_compare.gd # 装备对比实测（21 项，见 5.21 节）
│   ├── verify_dismantle.gd   #   分解 / 合成实测（33 项，见 5.22 节）
│   ├── verify_stat_calculator.gd # 属性结算实测（见 5.23 节）
│   ├── verify_set_system.gd  #   套装系统实测（25 项，见 5.24 节）
│   ├── verify_mythic_hidden.gd # 红装/彩装实测（27 项，见 5.25 节）
│   ├── verify_run_growth.gd  #   局内成长实测（23 项，见 5.26 节）
│   ├── verify_shop.gd        #   关卡商店实测（16 项，见 5.27 节）
│   ├── verify_run_result.gd  #   本局结算实测（14 项，见 5.28 节）
│   ├── verify_account.gd     #   局外成长实测（45 项，见 5.29 节）
│   ├── verify_level_gen.gd   #   关卡 / 地图生成实测（22 项，见 5.30 节）
│   ├── verify_monsters62.gd  #   怪物扩充 / 精英词缀实测（24 项，见 5.31 节）
│   ├── verify_boss63.gd      #   BOSS 机制实测（32 项，见 5.32 节）
│   ├── verify_skills.gd      #   技能库实测（49 项，见 5.33 节；45→49）
│   ├── verify_equipment65.gd #   装备库填充实测（14 项，见 5.34 节）
│   ├── verify_audio66.gd     #   音效/音乐实测（9 项，见 5.35 节）
│   ├── verify_ui71.gd        #   UI/UX 面板实测（30 项，见 5.36 节）
│   ├── verify_save81.gd      #   完整存档实测（15 项，见 5.37 节）
│   ├── verify_settings82.gd  #   设置持久化实测（12 项，见 5.38 节）
│   ├── verify_perf83.gd      #   性能优化实测（10 项，见 5.39 节）
│   ├── verify_balance84.gd   #   平衡性数值仿真（8 项，见 5.40 节）
│   ├── verify_fix85.gd       #   回归红线复核（8 项，见 5.41 节）
│   ├── verify_fix93.gd       #   崩溃与异常处理实测（25 项，见 5.42 节）
│   ├── verify_export91.gd    #   导出产物验证（5 项，见 5.43 节）
│   ├── verify_play92.gd      #   本地完整流程自测（7 项，见 5.44 节）
│   ├── verify_e2e.gd         #   端到端跑通（34 项，见 5.45 节 · 真点按钮/真切场景）
│   ├── level_scene_preview.gd#   关卡容器渲染预览（自截图，见 5.42.3 节）
│   ├── verify_enemy.tscn     #   上者的运行入口
│   ├── combat_preview.gd     #   战斗渲染预览（自截图，见 5.8 节）
│   ├── enemy_preview.gd      #   敌人 AI 渲染预览（自截图，见 5.10 节）
│   ├── health_preview.gd     #   生命系统渲染预览（自截图，见 5.12 节）
│   ├── loot_preview.gd       #   掉落系统渲染预览（自截图，见 5.13 节）
│   ├── juice_preview.gd      #   打击感渲染预览（自截图，见 5.14 节）
│   ├── equipment_preview.gd  #   词缀生成器渲染预览（自截图，见 5.16 节）
│   ├── forge_preview.gd      #   锻造 / 洗练渲染预览（自截图，见 5.18 节）
│   ├── legendary_preview.gd  #   传奇特效渲染预览（自截图，见 5.19 节）
│   ├── inventory_preview.gd  #   背包 / 仓库渲染预览（自截图，见 5.20 节）
│   ├── compare_preview.gd    #   装备对比渲染预览（自截图，见 5.21 节）
│   ├── dismantle_preview.gd  #   分解 / 合成渲染预览（自截图，见 5.22 节）
│   ├── stat_preview.gd       #   属性结算渲染预览（自截图，见 5.23 节）
│   ├── set_preview.gd        #   套装系统渲染预览（自截图，见 5.24 节）
│   ├── mythic_preview.gd     #   红装/彩装渲染预览（自截图，见 5.25 节）
│   ├── run_growth_preview.gd #   局内成长渲染预览（自截图，见 5.26 节）
│   ├── shop_preview.gd       #   关卡商店渲染预览（自截图，见 5.27 节）
│   ├── result_preview.gd     #   本局结算渲染预览（自截图，见 5.28 节）
│   ├── account_preview.gd    #   局外成长渲染预览（自截图，见 5.29 节）
│   ├── level_preview.gd      #   关卡地图渲染预览（自截图，见 5.30 节）
│   ├── monsters_preview.gd   #   怪物全览 / 词缀演示预览（自截图，见 5.31 节）
│   ├── boss_preview.gd       #   BOSS 阶段机制预览（自截图，见 5.32 节）
│   ├── skills_preview.gd     #   技能库扩充预览（自截图，见 5.33 节）
│   ├── equip_preview.gd      #   装备库填充预览（自截图，见 5.34 节）
│   ├── audio_preview.gd      #   音效清单 + 波形预览（自截图，见 5.35 节）
│   ├── ui_preview.gd         #   7 面板 UI 全览（自截图，见 5.36 节）
│   ├── save_preview.gd       #   存档快照面板（自截图，见 5.37 节）
│   ├── perf_preview.gd       #   性能面板（池统计 + 批处理地图，见 5.39 节）
│   ├── balance_preview.gd    #   平衡仿真曲线（TTK/承伤，见 5.40 节）
│   ├── enemy_preview.tscn    #   上者的运行入口
│   ├── combat_preview.tscn   #   上者的运行入口
│   ├── playtest.gd           #   战斗试玩场（玩家 + 靶子，随时调手感）
│   ├── playtest.tscn         #   上者的运行入口
│   ├── verify_ui.gd          #   UI 框架与主题实测（34 项，见 5.6 节）
│   ├── verify_ui.tscn        #   上者的运行入口
│   ├── gen_ui_theme.gd       #   UI 主题生成器（产出 theme.tres，见 5.6 节）
│   ├── gen_ui_theme.tscn     #   上者的运行入口
│   ├── ui_preview.gd         #   UI 主题渲染预览（自截图，见 5.8 节）
│   └── ui_preview.tscn       #   上者的运行入口
│
└── assets/                     # 美术与音频资源（阶段 6 填充）
    ├── sprites/                #   精灵图（主角 48×48 / 怪 32×32 / 图标 48×48）
    ├── tilesets/               #   地图 TileSet
    ├── fonts/                  #   字体（含中文像素字体）
    └── audio/                  #   BGM 与音效
```

> **关于 `.gd.uid` 与 `*.import`**：Godot 4.4+ 会为每个 `.gd` 生成同名的 `.gd.uid`
> （稳定的资源 UID），`.import` 则是导入元数据。**两者都必须提交**，
> 否则换台机器打开时资源引用会重新分配、场景里的引用可能失联。
> 唯一该忽略的是 `.godot/` 缓存目录本身。

---

## 三、全局单例（Autoload）

在 `project.godot` 中按以下顺序注册（**顺序不可调换**，后者依赖前者）：

| 顺序 | 名称 | 脚本 | 职责 |
|---|---|---|---|
| 1 | `EventBus` | `scripts/autoload/event_bus.gd` | 信号总线，模块间唯一通信渠道 |
| 2 | `ConfigLoader` | `scripts/autoload/config_loader.gd` | 读取 `data/*.json` → Resource 注册表 |
| 3 | `SaveManager` | `scripts/autoload/save_manager.gd` | 多槽存档 / 版本迁移 / 校验 / 备份轮转 |
| 4 | `SceneManager` | `scripts/autoload/scene_manager.gd` | 场景切换 / 异步加载 / 过场 |
| 5 | `InputRemapper` | `scripts/core/input_remapper.gd` | 输入重映射 / 手柄热插拔（任务 1.3） |
| 6 | `JuiceFX` | `scripts/juice/juice_fx.gd` | 打击感控制器（任务 2.8）：监听命中 / 死亡事件 → 飘字 / 闪白 / 震屏 / 顿帧 / 粒子 |

`GameConstants` **不是** Autoload —— 它是纯静态常量类（`class_name GameConstants`），
直接用 `GameConstants.Rarity.LEGENDARY` 访问即可，无需实例。

---

## 四、核心设计约定（后续开发必须遵守）

### 4.1 数据与代码分离

- **策划改数据** → 只改 `game/data/*.json`
- **程序改结构** → 改 `game/resources/*.gd` 的 Resource 类字段
- 两者的桥是 `ConfigLoader`。**禁止**在业务脚本里硬编码装备名、词缀数值、怪物属性。
- JSON 里出现未知的枚举键名时，`ConfigLoader` 会**记录错误并回退到安全默认值**，
  不会崩溃，但会在控制台打出 `[ConfigLoader]` 开头的警告 —— 见到就修。

### 4.2 模板 / 实例两层结构（重要）

| 概念 | 类 | 数量级 | 举例 |
|---|---|---|---|
| 底材模板 | `EquipmentData` | 几百 | 「铁剑」这个种类 |
| 装备实例 | `EquipmentInstance` | 每掉一件一份 | 一把 iLvl 17、稀有、4 条词缀的铁剑 |
| 词缀模板 | `AffixData` | 几十 | 「+固定攻击力」这个定义 |
| 词缀 roll | `AffixRoll` | 挂在实例上 | 「+7 攻击力，品质 0.9」 |
| 套装定义 | `SetData` | 约 6 | 「守誓者」6 件套 + 2/4/6 档加成 |

`SetData` 与 `EquipmentData` 是**双向引用**：套装列出 6 件底材 ID，每件底材的 `set_id` 指回套装。
`ConfigLoader._cross_validate()` 会强制二者一致 —— 只改一边会在启动时直接报错。

存档只落盘**模板 ID + 实例字段**，读档时由 `ConfigLoader.resolve_instance()` 回填模板引用。
**任何读档路径都必须调用 `SaveManager.load_from_slot_resolved()`**，
否则装备的 `template` 为空，`get_display_name()` 等会退化。

### 4.3 模块间通信只走 EventBus

```gdscript
# 正确：掉落系统只管发信号，不认识 UI
EventBus.loot_dropped.emit(item, global_position)

# 错误：直接找到 UI 节点改它
get_node("/root/Game/UI/PickupToast").show(item)
```

- 需要「切换场景」时，**只发** `EventBus.request_scene_change`，由 `SceneManager` 响应。
- 信号名一经发布即为公开契约，重命名必须全局搜索调用点。

### 4.4 常量唯一源

所有枚举、颜色、数值系数都在 `scripts/core/game_constants.gd`。
**禁止**在业务脚本里出现 `"legendary"`、`0xFF8A2B`、`1.28` 这类字面量。

### 4.5 像素风铁律（来自美术规范 0.7）

- 纹理过滤必须保持 **Nearest**（已在 `project.godot` 设好，不要改）
- 禁止运行时旋转精灵（破坏像素网格），方向动画靠**预烘** 4 方向（人形）/ 2 方向（杂兵）
- 护甲换装只允许改**调色索引区**，禁止整精灵 HSV 偏移

### 4.6 武器层三层结构与手部锚点（GDD 风险 #6 · **已在任务 2.1 落地**）

GDD 要求「武器层的手部锚点与层结构必须在阶段 2 就预留，否则阶段 6 整套装备上身方案要返工」。
该结构**已在 `scenes/player/player.tscn` 中实现**，后续阶段直接往上挂资源即可：

```
Player (CharacterBody2D)
├── BodySprite          ← ① 身体层（护甲靠调色索引重着色，0 新增帧）
├── WeaponLayer         ← ② 武器层容器（独立于身体层）
│   ├── MainHandAnchor  ← 主手锚点（剑/斧/锤/匕首/法杖/长弓）
│   └── OffHandAnchor   ← 副手锚点（盾/法器/箭袋/副刃）
├── FxLayer             ← ③ 特效层（受击闪白 / 稀有度辉光 / 技能特效）
└── CollisionShape2D
```

**绘制顺序 = 兄弟顺序**：Body → Weapon → Fx（后画的盖住先画的）。

**为什么 `WeaponLayer` 必须是独立容器、不能挂在 `BodySprite` 下**：
武器帧（244 帧）与角色帧是两套独立资源，且武器要能被装备系统**整体替换**；
若武器是身体的子节点，换装就得重建整棵身体节点树。

**锚点方案：两个锚点 + 位置随朝向计算**（而非「8 个方向各建一对锚点」）。
选型理由：

1. **武器精灵必须只有一个宿主**。若建 8 组方向子节点，装备精灵就得复制 8 份、
   或在每次转向时重新 `reparent()` —— 前者浪费，后者每帧都在动场景树。
   两锚点方案下武器精灵终身挂在同一个锚点上，只改 `position`，零 reparent。
2. **偏移表是纯数值**，调手感不必碰场景树，将来可直接换成美术给的逐方向数据。
3. 节点数从 18 降到 8，`.tscn` 可读性明显更好。

偏移算法：`锚点 = (0, HAND_HEIGHT) ± 右手方向 × HAND_SPREAD`，
其中「右手方向」= 朝向向量在屏幕坐标（+y 向下）里逆时针转 90°，
**y 分量按 0.5 衰减** —— 不衰减的话斜向时手会甩到脚下，看起来像掉在地上。
`HAND_HEIGHT` / `HAND_SPREAD` 等常量在 `player_controller.gd` 顶部，当前是**占位值**，
等 48×48 角色精灵产出后需按实际手部像素位置重新标定。

> ⚠️ **锚点只做左右翻转，绝不旋转** —— 美术规范 0.7 明确禁止运行时旋转（破坏像素网格），
> 方向差异一律靠预烘帧表达。占位武器精灵同理。

### 4.7 稀有度 8 档的「四维度辨识」（美术规范 1.4 硬规则）

8 档只靠颜色必崩（尤其橙 vs 红、黄 vs 绿）。美术规范 1.4 定死了硬规则：

> **任意两档必须在「光柱高度 / 框线粗细 / 框线样式 / 音效」四个维度中，至少 2 个维度不同。**
> 只差 1 个维度的组合视为不合格。

因此 `GameConstants` 为 8 档各维护了一份等长数组，**修改任何一档都必须同时检查另外三个维度**：

| 数组 | 维度 | 值（按 白/蓝/黄/紫/橙/红/绿/彩 顺序） |
|---|---|---|
| `RARITY_BEAM_HEIGHTS` | 光柱高度 px | 0 / 8 / 16 / 24 / 40 / 56 / **32** / 64 |
| `RARITY_BEAM_SHAPES` | 光柱形状 | 无 / 直线 / 脉动 / 加环 / 加爆闪 / 加火环 / **菱形环** / **6 色分段** |
| `RARITY_FRAME_WIDTHS` | 框线粗细 px | 1 / 1 / 2 / 2 / 3 / 3 / **2** / 3 |
| `RARITY_FRAME_STYLES` | 框线样式 | 实线×3 / 内发光 / 流光 / **红+金双层** / **青绿菱形节点** / **6 色渐变流动** |
| `RARITY_CATEGORIES` | 两级判断 | 线性×6 / **正交（套装）** / **彩蛋** |

**关键设计意图**（务必理解，否则容易「顺手优化」掉）：
- **套装绿不参与线性排序** —— 它的光柱是 32px **菱形环**（换形状而非比高度），
  因为「绿不是比橙更高一档，而是另一条获取路径」。
- **神话红靠「金色双层外框」而非色相区分** —— 色弱玩家看「有没有金边」即可，
  与血条/危险红彻底分开。
- **隐藏彩用固定 6 色渐变 + 相位流动，禁止色相旋转 Shader** ——
  色相旋转会产生 48 色板之外的任意颜色，破坏「全项目同一色源」。
  6 色取自色板辉光阶，见 `PRISMATIC_GRADIENT`。
- **难度层级会改变掉落权重**：红 ×1.50 且**仅梦魇 II 及以上掉落**，绿 ×1.10，彩不变。
  见 `LootTable.get_adjusted_weights()`。

### 4.8 踩坑：`has_method()` 探测 + `call()` 会**静默降级**

跨模块调用如果写成「先 `has_method()` 探测、再 `call()`」，一旦**方法名拼错或对方改名**，
探测恒为 `false`，那段逻辑**悄悄不执行** —— 不报错、不警告、不写日志：

```gdscript
# ❌ 拼错成 get_level（实际叫 get_player_level）⇒ 恒 false ⇒ 恒返回 0，越级惩罚静默失效
if _player != null and _player.has_method("get_level"):
    return int(_player.call("get_level"))
return 0
```

**为什么难发现**：静态检查看不见（`has_method` 参数是字符串，拼错也是合法字符串）；
单行测法也测不出（「空引用 → 返回 0」这条分支永远是对的）。**必须测「有对象在场」的那条分支。**

**铁律**（违反者一律打回）：

1. 凡是 `has_method()` + `call()` 的写法，**必须**有一条测试**挂真实对象**、
   断言**效果**（返回值 / 位移 / 状态变化），而不是只断言「方法存在」。
2. 断言要**双向卡**：只写下界时，「实现发散/过度生效」反而让断言更容易通过
   （如击退 `velocity +=` 累积发散，请求 12px 走成 61.4px）。
3. 新断言**先证伪再转正**：先在当前代码上跑一次确认它 **FAIL**，改完再跑确认 **PASS**；
   没证伪过的断言等于没写。
4. 同名方法在不同类里出现时（如 `TalentTree.get_bonus_stats` vs `SetSystem.get_bonus_stats`），
   grep 定位前先确认**类名**，否则会把「没接线」误判成「已接线」。

案例与实测数据见 **5.42.1 集成层阶段 2：4 处静默 bug 回归**。

---

### 4.9 铁律：断言写「设计意图」，不写「当前快照」

**这是本项目唯一一个把缺陷直接写成绿灯的坑，且已经真实发生过。**

`tools/verify_level_gen.gd` 原来有一条断言：

```gdscript
# ❌ 用「观测到的数据」反推期望值
_ok("20 关 BOSS 关 = 2（ch2_l13 / ch3_l20）", _count_boss_levels() == 2)
```

而 `_count_boss_levels()` 数的是「`boss_id` 非空」的关卡数。于是：

- `ch1_l06` 目标是 `kill_boss` 却**缺 `boss_id`** ⇒ 没被计入 ⇒ **缺陷被断言成了正确行为**；
- `ch2_l13` / `ch3_l20` 有 `boss_id` 但 `monster_entries` 里**没有 `is_boss` 条目**，
  而容器当时只认 `is_boss` ⇒ **BOSS 永不出现、目标永不达成** ⇒ 同样无人发现。

**判据**：写断言前先问一句 **「这个期望值是从哪来的？」**
如果答案是「我跑了一遍看到是 N」，那它就是在给现状拍照，不是在校验设计。

```gdscript
# ✅ 按设计意图判定：目标是 kill_boss 的关，就必须有 boss_id
for lv in ConfigLoader.get_levels_sorted():
    if lv.objective_type == LevelData.ObjectiveType.KILL_BOSS:
        if lv.boss_id.is_empty():
            missing.append(lv.id)
_ok("每个 kill_boss 关都有 boss_id（缺：%s）" % str(missing), missing.is_empty())
```

同族的还有 **`verify_enemy.gd` 的 E 段**：它把「玩家距敌人 20px ⇒ 敌人进 ATTACK」写成断言，
看似只是个手感测试，实际是**敌人碰撞形状的边界守卫**（见 4.10 末段）。

---

### 4.10 铁律：每个 `emit` 与每个生成器输出字段，都必须写明**谁在消费**

**「生成了但没人消费」是本项目的头号缺陷模式，已累计 8 个**：

| # | 输出 | 后果 |
|---|---|---|
| 1 | `SaveManager._load_set_dir()` | 定义了从不调用 |
| 2 | `ConfigLoader._cross_validate()` | 定义了从不调用 |
| 3 | `SaveManager.get_account_data()` | 定义完整、键契约正确，但**零调用** ⇒ 据点拿不到账号数据 |
| 4 | `SceneManager.change_to_hub()` | 零调用 ⇒ 回不了据点 |
| 5 | `EventBus.request_start_level` | **零 emit** ⇒ 关卡永远进不去 |
| 6 | `LevelGenerator.pickup_spawns` | 生成器产出，**全项目零消费** ⇒ 第 10.9 项才激活（收集目标物） |
| 7 | `EventBus.loot_picked_up` | 声明了但**从未 emit** |
| 8 | `LevelGenerator.boss_spawn` | 只被开发工具 `level_preview.gd` 和测试消费，**容器从未消费** ⇒ **2 关打不通**（`ch2_l13` / `ch3_l20`） |

**为什么难发现**：语法正确、自检全绿、`verify_*` 全绿 —— 静态检查与单元测试**都看不见「没人调用」**。

**铁律**：

1. 新增 `signal` 时，**同一批改动内**必须落地消费者；落不了地就在注释里写明「当前广播、无消费者、属预留」，
   并进任务清单 —— **不许留下无注释的死信号**。
2. 新增生成器 / 序列化输出字段时，**同一批改动内**必须落地消费点；
   否则就是「产出了一个没人要的东西」，应直接删掉而不是留着。
3. 代码里的 `## 接线：` 注释块（见 `level_scene.gd` 类头）**逐行注明 emit → 谁在听**，这是本项目的既定写法。

**⚠️ 附：`enemy_base.tscn` 的碰撞形状是「休眠的雷」**

该场景的 `CollisionShape2D` **漏写 `type=`**（全项目唯一一处），节点被当成普通 `Node` 建出来、
`shape` 应用失败、节点被丢弃 ⇒ 敌人**实际没有任何碰撞形状**，每关打 42 条
`Node './CollisionShape2D' was modified from inside an instance, but it has vanished`。

**但直接补上 `type=` 会引入回归**（已实测）：玩家形状（`player.tscn` 的 `RectangleShape2D(20,22)`，
偏移 `(0,-11)`）与敌人形状（`RectangleShape2D(24,24)`，居中）在贴脸时几何重叠 14px，
物理分离会把两者推到 **≈34px** —— 而 `attack_range` 恰好是 **34** ⇒ 敌人被顶到边界后
在 CHASE ↔ ATTACK 之间**震荡**，攻击时断时续（`verify_enemy` E 段立刻变红）。

结论：**启用敌人碰撞不是改个字段，而是一次平衡调整**（需同时处理敌人形状几何、玩家形状偏移、
每只怪的 `attack_range`），且项目当前整体没有物理碰撞（墙 / 障碍也没有 `StaticBody2D`，
见 `level_scene.gd` 已知限制 1）。见任务清单 **10.10**。

**2026-09-21 收口（`#39` 碰撞线）—— 雷已排除，但只排了一半，而且是**故意**的：**

| | 改动 | 为什么 |
|---|---|---|
| ① | `[node name="CollisionShape2D" **type="CollisionShape2D"** parent="."]` | 补上漏掉的 `type=`，敌人**终于有**碰撞形状 |
| ② | `collision_layer` `3` → `4` | 层表（§7）里「层 3 = enemy」的值是 **4**；旧值 `3` = 层 1+2（world+player）⇒ 敌人被放在**地形层**上，玩家（`mask=1`）会撞到怪 |
| ③ | `collision_mask` `3` → `1` | **只打 world 地形**。刻意**不含玩家层** —— 那正是下面那条「≈34px 震荡」，属 10.10 |

② 是**值错误**（不是设计选择）：`collision_layer = 3` 与 §7 层表直接矛盾。
③ 是**故意收窄**：它让「敌人撞墙」立刻成立（用户明确要求「墙体碰撞限制需要继续完善」），
同时把「敌人 ↔ 玩家推挤」原封不动留给 10.10 —— 那条的前置是**给攻击判定加迟滞**，
与墙无关，本轮不做。

**实测证据**（修前 → 修后）：

| 断言 | 修前 | 修后 |
|---|---|---|
| `verify_knockback` C 段「朝墙猛推不得穿墙」（请求 200px，墙左表面 x=100） | `[FAIL] x = 221.41`（**整只怪从墙左穿到墙右**） | `[OK] x = 88.00`（= 墙面 100 − 半宽 12，**精确停在理论值**） |
| `verify_enemy` / `verify_hit` | — | 全绿（**未**把 mask 放开，所以没有 ≈34px 震荡） |

新增 `tools/verify_knockback.gd`（11 项）把这条契约钉死：方法存在 / 当帧不瞬移 /
场景自带 24×24 形状 / **层契约 layer=4 + mask=1**（谁把 mask 放开到含玩家层，这里立刻变红，
逼他先读 10.10）/ 位移量级 / 衰减停止 / 不残留到 AI 通道 / **撞墙不穿**。

> 顺带记一条通用教训：**「场景文件里写了节点」≠「运行时真的有这个节点」**。
> `CollisionShape2D` 少一个 `type=`，Godot 只会打一条 `WARNING ... has vanished` 就**静默丢弃**
> 整个节点 —— 53+ 个 `verify_*` 全绿、`self_check` 111/111 全绿，因为**没有一条断言看过
> 敌人的物理碰撞**（战斗命中走的是 `EnemyBase.get_hit_radius()` 硬编码 12.0，与形状无关）。

---

## 五、验证方法

### 5.1 编辑器内验证（推荐）

1. 用 Godot 4 打开 `D:\七傳說\game\project.godot`
2. 底部 **「输出」** 面板应出现：
   ```
   [ConfigLoader] 数据加载完成：{ "equipment": 62, "affixes": 33, "affix_pools": 10, "legendary_effects": 31, "monsters": 16, "bosses": 2, "levels": 20, "loot_tables": 3, "sets": 3, "skills": 8 }
   [Main] 「七傳說」骨架启动
   [Main] 存档目录：C:\Users\<你>\AppData\Roaming\Godot\app_userdata\七傳說\saves
   [MainMenu] 主菜单就绪：账号 Lv.1 · 金币 0 · 已有存档 否
   ```
   （自检报告只在 `--verify` 模式下打印，见 5.2）
3. 若出现 `[ConfigLoader] ... 有 N 处问题`，按提示定位到具体 JSON 文件
4. 按 **F5** 运行，应进入**主菜单**（「开始游戏」→ 据点 → 选关 → 关卡 → 结算）
5. 按 **F6** 之前先看「输出」有无 `SCRIPT ERROR` / `Parse Error`

> 自检结果**同时**打到控制台与界面。控制台那段是无头验证唯一能看到的东西，别删。

### 5.2 命令行验证（无需打开编辑器）

```bash
GODOT="/c/Users/<你>/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"

# ① 首次使用（或删过 .godot/ 之后）必须先跑一次，生成全局类缓存
"$GODOT" --headless --editor --quit --path "D:/七傳說/game"

# ② 骨架自检：111 项全绿则退出码 0，任一失败退出码 1（可直接接 CI）
"$GODOT" --headless --path "D:/七傳說/game" -- --verify

# ③ 全量回归（推荐）：50 个 verify 脚本 + self_check 一次跑完，自动隔离 APPDATA
python game/tools/run_regression.py

# ④ 单点排查（任何 verify_*.tscn 同理，按需替换文件名）
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_integration.tscn
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_hub.tscn
```

`--verify` 会跑完 `ConfigLoader` 加载 + 全部骨架自检，打印报告后退出，
**不进游戏主循环**，所以非常适合脚本化验证。退出码约定：

| 退出码 | 含义 |
| --- | --- |
| `0` | 111 项自检全部通过 |
| `1` | 有自检项失败（数据表缺失、跨表引用断裂、常量数组不等长等） |

> 📌 **只想跑一条命令就够**：`python game/tools/run_regression.py`。
> 它跑 50 个 `verify_*.tscn` + `self_check`，并**先做一次全项目解析预检**。
> 详见 §5.46。

> **启动分流**：`run/main_scene` 是 `scenes/main/main.tscn`，它只做一件事 ——
> 带 `--verify` 就挂载 `tools/self_check.tscn`（自检 + 按退出码 `quit`），
> 否则切到主菜单 `scenes/main/main_menu.tscn`。
> 也就是说**同一个入口**同时服务「双击进游戏」与「CI 跑自检」，两者互不干扰。

> ⚠️ **`class_name` 全局类缓存陷阱（重要）**
>
> 刚 clone 下来的项目**没有** `.godot/` 目录。此时如果直接跑第 ② 步，会看到
> 一大片 `Parse Error: Could not find type "EquipmentInstance"`、
> `Failed to instantiate an autoload, script 'event_bus.gd' does not inherit from 'Node'`。
>
> **这不是代码错误**，是 Godot 的机制：`class_name` 注册在
> `.godot/global_script_class_cache.cfg` 里，而这个缓存只由**编辑器扫描**生成。
> 所以第 ① 步不能跳过。跑完 ① 之后 ② 就是干净的。
>
> 该缓存已在 `.gitignore` 中，不会被提交。

> ⚠️ **`APPDATA` 为空会让 `user://` 变成相对路径（重要 · 已实际踩过两次）**
>
> Windows 上 `user://` 的物理位置由 `APPDATA` 环境变量推导。在**无头 / CI / 精简 shell**
> 里 `APPDATA` 可能是**空串**，此时 Godot 会 fallback 成**相对路径**
> `./Godot/app_userdata/七傳說/`（相对当前工作目录解析）。
>
> **症状会伪装成「存档写不进去」的代码 bug**，链路是这样的：
>
> | 步骤 | 空 `APPDATA` 下的结果 |
> | --- | --- |
> | `FileAccess.open("user://saves/x.json", WRITE)` | **成功**（按相对 CWD 解析，文件真写出来了） |
> | `DirAccess.open("user://saves")` | **返回 `null`，`get_open_error()` = `ERR_INVALID_PARAMETER(31)`** |
> | ⇒ `SaveManager._move_file()` → `dir.rename()` | 拿不到 `DirAccess` ⇒ 返回 `false` |
> | ⇒ `SaveManager._atomic_write()` | `.tmp` 写成功、**rename 失败** ⇒ 报 `无法将临时文件重命名为 'user://saves/slot_06.json'` |
> | ⇒ `create_new_slot()` / `save_to_slot()` | 返回 `false` / `null` ⇒ 测试报「新建槽位失败」 |
>
> 因为 `DirAccess.open()` **只接受绝对路径**（不接受 `user://` 前缀），而 `FileAccess` 接受，
> 所以「一半能写、一半不能写」，极容易被误判成 `SaveManager` 的代码缺陷。
> 日志侧症状则是「`user://logs/game.log` 明明写过却读不到」。
>
> **这不是代码错误**，是环境问题。跑 Godot 前把 `APPDATA` 显式导出去即可：
>
> ```bash
> # 推荐：指向真实用户目录（存档/日志落在 %APPDATA%\Godot\app_userdata\七傳說\）
> export APPDATA='C:\Users\<你>\AppData\Roaming'
> "$GODOT" --headless --path "D:/七傳說/game" -- --verify
> ```
>
> 也可以指向仓库内的临时目录（`user://` 变成 `d:/七傳說/.vu/Godot/app_userdata/七傳說/`）：
>
> ```bash
> APPDATA="d:/七傳說/.vu" "$GODOT" --headless --path "D:/七傳說/game" -- --verify
> ```
>
> 不指定 `APPDATA` 时，`user://` 落在 `%APPDATA%\Godot\app_userdata\七傳說\`，
> 即存档在 `saves\`、日志在 `logs\`。
>
> ⚠️ **副作用**：空 `APPDATA` 跑过一次后，项目根会多出一个 `game/Godot/`
> （`app_userdata/`、`editor_settings-4.7.tres`、`export_templates/` …）。
> 它是垃圾目录，已被 `game/.gitignore` 的 `/Godot/` 覆盖、**不会进仓库**，但可以随时手删。
> 见到它就说明那次运行是空 `APPDATA` 跑的 —— 那次跑出的存档/日志结论全部不可信。

> 若 `godot` 不在 PATH 中，用完整路径，例如
> `"C:/Program Files/Godot/Godot_v4.3-stable_win64.exe"`


### 5.3 存档系统验证

仓库内自带一个可执行的实测脚本，覆盖 26 项：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_save.tscn
# 退出码 0 = 全部通过；1 = 有失败项
```

覆盖范围：新建槽位 / 写入 / 逐字段回读 / 引用回填 / 备份轮转 /
主档损坏回滚 / 损坏隔离 / **恢复后主档重建** / 槽位信息 / 删除。

> ⚠️ 该脚本会**真实读写** `user://saves`，并**故意制造一次存档损坏**来验证回滚。
> 它只使用最后一个槽位（`SAVE_MAX_SLOTS - 1`），跑完自行清理，
> 但请勿在玩家正在游玩的存档目录上运行。

手动验证损坏保护（等价做法）：把
`%APPDATA%\Godot\app_userdata\七傳說\saves\slot_00.json`
用记事本改掉一个字符，再读档 —— 应看到
`[SaveManager] 槽位 0 主档不可用，已回滚到备份 1`，
损坏文件被改名为 `slot_00.corrupt_<时间戳>` 保留现场，
且**主档会被恢复出的数据重建**（否则选档界面会把槽位显示成「空档」）。

### 5.4 玩家控制器 + 输入系统验证（任务 1.3 / 2.1）

仓库内自带一个可执行的实测脚本，覆盖 33 项：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_player.tscn
# 退出码 0 = 全部通过；1 = 有失败项
```

覆盖范围：

| 段 | 内容 |
|---|---|
| A | 输入映射：每个动作都有「≥1 键 + ≥1 手柄事件」；旧的 `skill_primary`/`ui_pause` 等已清除 |
| B | 移动：8 方向速度向量方向与模长；**对角线归一化**（必须是 144 而非 203.6 px/s）；松手滑行 |
| C | 闪避：位移 ≈ `dodge_distance`；无敌帧 ≈ `dodge_iframe_duration`；冷却 ≈ `dodge_cooldown` |
| D | 锚点结构：Body → Weapon → Fx 绘制顺序；主/副手锚点存在且归 `WeaponLayer` 管辖 |
| E | 锚点随 8 方向朝向变化；朝下/朝上右手镜像；全局坐标随角色位移同步 |
| F | 重绑定：`rebind` 只替换同设备类别 / `reset_to_default` / `save`+`load` 往返 |

> ⚠️ F 段会**真实读写** `user://input_bindings.json`。脚本开跑前会备份该文件、
> 结束时还原（原本不存在则删除），不会破坏你已有的按键设置。
> C 段的闪避走**真实输入链路**（`InputEventAction` → `_unhandled_input`），
> 不是直接调函数 —— 若哪天无头环境下事件投递失效，脚本会打印实际用的路径，不会假装通过。

### 5.5 导出 Windows 可执行（任务 1.9）

1. 编辑器 → **编辑器 → 管理导出模板…** → 下载安装导出模板（**必做**，无法用文本配置代替）
2. **项目 → 导出** → 选中 `Windows Desktop` → **导出项目…**
3. 产物默认落在 `game/build/七傳說.exe`

命令行方式：

```bash
godot --headless --path "D:/七傳說/game" \
      --export-release "Windows Desktop" \
      "D:/七傳說/game/build/七傳說.exe"
```

> `export_presets.cfg` 是**手工编写**的。首次在编辑器中打开「导出」面板时，
> Godot 可能会重写该文件以补齐字段 —— 属正常行为。

### 5.6 UI 框架与主题验证（任务 1.6）

仓库内自带可执行实测，覆盖 34 项：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_ui.tscn
# 退出码 0 = 全部通过；1 = 有失败项
```

覆盖范围：色板与 UI 常量自洽（48 色板 = 43 已定义色）/ `theme.tres` 产物与 `gui/theme/custom` 注册 /
字体挂载与像素设置（Cubic-11 正文 11px、ChillBitmap-16px 标题 16px，抗锯齿/hinting/子像素全关）/ 
像素铁律（全部 StyleBoxFlat 圆角 0、描边 1px、底色与描边色 RGB 取自 48 色板）/ 
真实控件在项目默认主题下解析出样式与字体。

**主题是如何生效的**（重要）：`theme.tres` 由生成器 `tools/gen_ui_theme.tscn` 从
`scripts/ui/ui_theme.gd` 程序化构建并落盘，再经 `project.godot` 的 `gui/theme/custom` 注册为**项目默认主题**
—— 这是 Godot 唯一可靠的「全窗口所有控件自动套用」机制（实测 `Window.theme` 不会向子控件传播）。
⚠️ 改过 `ui_theme.gd` / `game_constants.gd` 的样式后**必须重跑生成器**再提交 `theme.tres`，
否则运行中仍是旧主题（见已知待办 **原 #23（收敛后现 #7）**）。

### 5.7 攻击与技能系统验证（任务 2.2）

仓库内自带可执行实测，覆盖 **45 项断言、6 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_skills.tscn
# 退出码 0 = 全部通过；1 = 有失败项
```

| 段 | 内容 |
|---|---|
| A | 技能表：3 条 JSON 可解析、数据合法、按 slot 排序 = 技能栏 1/2/3 |
| B | 法力池：初始 100 / 消耗 / 不足拒绝 / 自然回复 4/s / 封顶 / 减耗 |
| C | 冷却：每技能独立冷却 / 冷却中拒绝 / 计时递减 / 到期可再放 |
| D | 普攻假连段：按住攻击按攻速间隔连续挥击 / 松开即停 / 攻击不打断移动 / 闪避打断 / 命中回蓝 +2 |
| E | 技能效果：裂斩单体 350% / 旋刃范围 140% + 击退 / 突进物理撞击（move_and_collide）/ 蓝耗与拒放 |
| F | 回归：移动 / 闪避未受影响 |

> ⚠️ D/E 段通过**真实输入链路**（`Input.action_press` → 玩家控制器）驱动，每段开头**复位玩家与靶子位置**
> —— 技能击退 / 闪避位移会改变坐标，缺复位会让后续命中断言「莫名其妙」失败（脚本内有注释）。

**数值口径（用户已拍板）**：普攻无消耗、伤害 = 裸装 12 AD × 1.0、攻击间隔 = 1 / 攻速（L1 为 1.0/s）；
裂斩 350% AD / 6s 冷却 / 30 蓝（单体）；旋刃 140% AD / 3s / 15 蓝 / 半径 48px（范围）；
突进 100% AD / 8s / 20 蓝 / 冲刺 96px（位移）。法力上限 100、自然回复 4/s、普攻命中 +2。

### 5.8 渲染预览（肉眼检查）

无头模式无法渲染，预览场景在窗口化下自截图后自动退出：

```bash
"$GODOT" --path "D:/七傳說/game" res://tools/ui_preview.tscn
# 产物：game/build/ui_preview.png（面板/标题/按钮/进度条/输入框/提示面板）

"$GODOT" --path "D:/七傳說/game" res://tools/combat_preview.tscn
# 产物：game/build/combat_preview_attack.png（普攻挥击帧）
#      game/build/combat_preview_skill.png（技能帧：旋刃范围环）
```

> 战斗预览演示 2.6s：按住攻击假连段 + 0.8s / 1.4s / 2.0s 依次施放旋刃 / 裂斩 / 突进，自动截两帧退出。
> 受击靶为验证占位（色板绿/蓝/红三色），任务 2.4 敌人 AI 就绪后由真实怪物替换。
> 直接上手试玩（不自动退出）：`"$GODOT" --path "D:/七傳說/game" res://tools/playtest.tscn`
> （玩家 + 四个彩色靶子 + 蜘蛛/蝙蝠两只怪物，WASD 移动 / 左键按住攻击 / 123 技能 / 空格闪避；
> 走近怪物会触发追击与攻击，击杀会消失；被怪物攻击会扣血（2.6 生命系统，HUD 血条实时显示）。

### 5.9 伤害计算管线验证（任务 2.3）

仓库内自带可执行实测，覆盖 **40 项断言、6 个测试段**（口径为用户 2.3 拍板）：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_damage.tscn
# 退出码 0 = 全部通过；1 = 有失败项
```

| 段 | 内容 |
|---|---|
| A | 基础：raw = AD × 技能倍率；无暴击无减伤确定性路径 |
| B | 暴击：CR 5% / CD 150% / 上限 75% / 期望公式 `1 + CR×(CD-1)`（GDD 6.6）/ roll 统计 |
| C | 元素：物理走护甲、元素走抗性（同构 `resist/(resist+50×L)`）/ 元素伤害加成 / 抗性上限 75% |
| D | 减伤：护甲 DR / 额外减伤% 乘算 / 顺序（护甲 → 减伤%）/ clamp |
| E | 接入回归：普攻与技能真实走管线 / 目标护甲生效 / 技能元素改写后走对应抗性 / 回蓝与事件 |
| F | GDD 锚点：6.6 期望公式 / DR 数值 / EHP 演示 |

**公式（用户 2.3 拍板）**：`最终伤害 = AD × 技能倍率 × 暴击倍率 × 元素加成 × (1 − 减伤)`；
暴击基准 5% / 150%（上限 75%）；元素 = 物理 + 火/冰/雷/毒 5 系；
减伤顺序 = 护甲（物理）/ 抗性（元素）→ 减伤% 乘算 → 概率判定（闪避/格挡，2.5/2.6）。
玩家等级成长已接入（GDD 6.2：12 × 1.10^(L-1)），装备/词缀乘区留接口（阶段 3）。

### 5.10 敌人 AI 基类验证（任务 2.4）

仓库内自带可执行实测，覆盖 **34 项断言、6 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_enemy.tscn
# 退出码 0 = 全部通过；1 = 有失败项
```

| 段 | 内容 |
|---|---|
| A | 数据：EnemyBase 从 MonsterData 加载（spider_cave 字段锚点），HP 公式正确 |
| B | 状态机：出生 PATROL → 玩家入 AGGRO(160) → CHASE → 入 attack_range(34) → ATTACK → 远离 → 回 PATROL |
| C | 移动：CHASE 速度 = move_speed(75)；ATTACK 停住 |
| D | 受击契约：take_damage 扣血 / 玩家普攻与技能真实命中敌人 / apply_knockback / 死亡发 unit_died + 移除 / 死亡瞬间忽略补刀 |
| E | 攻击：ATTACK 状态按 attack_interval(1.2s) 输出 damage_taken 事件（amount 5.61、元素 physical）；玩家无生命组件不崩 |
| F | 回归：玩家移动 / 普攻 / 技能不受敌人存在影响 |

**状态机**（数据驱动，攻击距离读怪物表）：巡逻（出生点半径 48px 游走，AGGRO 外）→
追击（玩家入 160px → 朝玩家直线移动）→ 攻击（入 attack_range → 停手按 attack_interval 输出伤害）；
玩家远离 240px 回巡逻。受击 / 击退 / 防御读取接口与 2.2/2.3 契约一致（2.6 收编统一组件）。

渲染预览（GUI 版，自动截两帧退出）：
`"$GODOT" --path "D:/七傳說/game" res://tools/enemy_preview.tscn`
产物 `build/enemy_preview_chase.png`（蜘蛛追击途中）与 `build/enemy_preview_attack.png`（蜘蛛贴脸攻击）。

### 5.11 碰撞与命中判定验证（任务 2.5）

仓库内自带可执行实测，覆盖 **25 项断言、6 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_hit.tscn
# 退出码 0 = 全部通过；1 = 有失败项
```

| 段 | 内容 |
|---|---|
| A | circle 圆形判定：目标半径扩展 / 圆心重叠跳过 |
| B | arc 扇形判定：朝向前方 ±25° 命中 / 90° 侧外不中 / 超出范围不中 |
| C | rect 矩形判定：前方命中 / 侧宽外不中 / 身后不中 / 深度外不中 |
| D | 玩家接入：普攻与旋刃真实走 HitQuery（目标半径扩展） |
| E | 敌人攻击：朝玩家 120° 弧内命中 / 弧外挥空 / 超距离挥空 |
| F | 玩家无敌帧：闪避中敌人攻击挥空 / 无敌解除后恢复命中 |

**判定模型**（`HitQuery` 静态类）：circle（圆心距离 ≤ 半径 + 目标半径）/ arc（扇形，
朝向中轴 ±arc/2，含目标半径扩展）/ rect（朝向前方矩形，侧向 |side| ≤ 半宽 + 目标半径）。
目标半径统一走 `get_hit_radius()`：敌人 / 靶子 12px、玩家 11px（2.6 统一组件契约）。
敌人攻击弧 `ENEMY_ATTACK_ARC_DEG = 120°`，尊重玩家 `is_invulnerable()`（闪避无敌帧）。

> ⚠️ 验证脚本经验（已记工作记忆）：Godot 的 `global_position` setter **延迟同步物理体到下一次
> 物理步进**——验证脚本在 process 层连续传送后同帧调用 `move_and_collide`（突进）会从旧物理位置
> 出发导致撞空；修复 = dash 前 `await get_tree().physics_frame` 对齐物理体。真实游戏中突进在输入
> 回调里调用，玩家位置由 `move_and_slide` 每帧同步，不受影响。另：伤害断言（42 / 16.8 / 12）
> 依赖不暴击，脚本开头固定随机种子避免 5% 暴击抖动。

### 5.12 生命 / 护盾 / 异常状态验证（任务 2.6）

仓库内自带可执行实测，覆盖 **25 项断言、6 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_health.tscn
# 退出码 0 = 全部通过；1 = 有失败项
```

| 段 | 内容 |
|---|---|
| A | 属性锚点：玩家 L1 max_hp 150 / 护甲 6 / 抗性 0 / 闪避 0 / 格挡 0 / 出生满血 |
| B | 减伤链：护甲 DR（5.61 → ≈5.01）→ 闪避无敌帧免疫 → 无敌解除恢复受击 |
| C | 护盾：先吸收（过减伤后）→ 耗尽后剩余伤害扣血 |
| D | 异常状态：中毒 dot / 冰冻减速乘区 0.6 / 燃烧 dot / 同类刷新时长不叠加 |
| E | 死亡：致命伤 → is_dead + player_died 广播 → 死后受击无效 + 移动停止 |
| F | 敌人接入：毒史莱姆攻击玩家扣血（减伤后）+ 附加中毒 dot |

**组件与契约**（`HealthComponent`，挂在玩家下）：
- 减伤链（用户 2.3 拍板顺序）：护甲（物理）→ 减伤% 乘算（阶段 3 套装）→ 概率判定（闪避免疫 / 格挡减 50%）。
- 护盾先吸收再扣血；生命回复基础 0（阶段 3 词缀 / 局内天赋「再生」写入）。
- 异常：毒 / 燃 = 持续伤害（dot = 来源攻击力 × 20% / 25% / s），冰 = 移动减速 40%（乘区 0.6）；
  同类刷新时长不叠加；元素 → 异常映射（毒→中毒 / 火→燃烧 / 冰→冰冻，雷电预留）。
- 敌人攻击真正扣玩家血（2.4 发事件 → 2.6 落地）；死亡发 `player_died`（完整死亡流程阶段后接）。
- 敌人生命已统一收编 HealthComponent（2.7）：`current_hp` / `is_dead` / `take_damage`
  转发组件，`apply_mitigation=false` 防双重减伤（玩家攻击管线已按敌人护甲减伤）。

**血条 UI**（美术规范 v1.4 附录「UI 元件」）：玩家 HUD 16px / 怪物头顶 8px；底槽 `#14171C`、
血量 `#C42B2B`→`#8C1A1F` 渐变、1px `#0B0D10` 描边、护盾叠 `#3A5FB0`、顶部高光 `#E8573F`。
渲染预览：`tools/health_preview.tscn`（窗口化自截图）→ `build/health_preview_full.png`（满血）
/ `health_preview_hurt.png`（被毒史莱姆攻击后 144/150）。

### 5.13 掉落与拾取系统验证（任务 2.7）

仓库内自带可执行实测，覆盖 **20 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_loot.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 掉落表数据：3 张（普通 8% / 精英 60% / BOSS 100%）、权重 8 档和为 100、件数区间 1–1 / 1–2 / 2–4 |
| B | roll 基础：BOSS 必掉 2–4 件、条目字段合法、普通怪 8% 触发（200 次抽样有掉有漏） |
| C | 稀有度分布：普通怪权重 20k 次抽样 白 > 蓝 > 黄、橙装 ≈ 0.05% 极稀有 |
| D | 难度修正：NM1 红装清零 / NM2+ 开放（×1.5）/ 越级惩罚紫 / 橙 ×0.5 |
| E | 底材过滤：按稀有度区间 / iLvl 区间过滤，套装稀有度只出 set_id 底材 |
| F | 敌人死亡掉落 + 拾取：BOSS 秒杀掉 2–4 件地面掉落物，玩家走近自动入账（金币 / 魔石 / 装备） |
| G | 收编回归：敌人受击转发生命组件（apply_mitigation=false 无双重减伤） |

- 掉落流程（GDD 6.1）：触发 → 件数（drop_count_range）→ 物品类型（装备占比 55/80/90%、
  金币权重 30/25/20、材料 12/40/60）→ 稀有度（难度修正 + 越级惩罚，差 3 级紫 / 橙 / 红 ×0.5）
  → 底材（drop_weight 加权，稀有度 / iLvl 区间过滤）。
- 拾取：玩家靠近 ≤ 24px 自动拾取（出生 0.25s 后生效），存活 60s 消失；
  会话背包 gold / materials / inventory（装备存 item_id + rarity + iLvl，词缀生成阶段 3）。
- 地面辨识度（美术规范 v1.4 递进 1–2 层）：装备 12px 稀有度色块 + 1px 深描边 +
  渐隐光柱（高度 `RARITY_BEAM_HEIGHTS` 按稀有度递增）；金币金色 8px / 魔石蓝 8px。
- 敌人生命 2.7 收编统一组件：`current_hp` / `is_dead` / `take_damage` 转发 HealthComponent
  （`apply_mitigation=false` —— 玩家攻击管线已按敌人护甲减伤，避免双重减伤）；
  死亡发 `unit_died` → LootRoller 掉落 + 移除。
- 渲染预览：`res://tools/loot_preview.tscn`（窗口化运行，自截图 `game/build/loot_preview.png`：
  10 种掉落物 + 8 档光柱高度）。

### 5.14 打击感验证（任务 2.8）

仓库内自带可执行实测，覆盖 **18 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_juice.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 参数与接入：打击感常量合法、JuiceFX Autoload 存在 |
| B | 飘字：damage_dealt 生成飘字、金额 / 位置 / 普通亮白 / 暴击橙红大字 |
| C | 飘字生命周期：0.6s 后自动消失（真实时间，顿帧不加速老化） |
| D | 顿帧：hit_stop 后 time_scale 短暂 <1 并恢复 1.0 |
| E | 震屏：shake 后相机 offset 抖动、按 40px/s 衰减归零 |
| F | 死亡粒子：unit_died 生成 PixelBurst（白色扩散环 + 碎片）、自动消失 |
| G | 玩家闪白：flash 后身体 / 主副手提亮并恢复 |

- 事件链：攻击命中处发 `EventBus.damage_dealt(target, amount, is_crit, element)`（普攻 / 技能 /
  敌人攻击三处统一）→ `JuiceFX`（Autoload）译成表现：目标头顶飘字（Cubic-11 像素字 +
  3px 深描边，普通亮白 11px / 暴击橙红 15px）+ 目标闪白（玩家 flash()）+ 震屏
  （命中 1.5px / 暴击 3.0px）+ 暴击顿帧（time_scale 0.05 × 0.03s 真实时间）。
  死亡发 `unit_died` → 死亡点爆 8 片像素碎片（怪物档位色提亮）+ 白色扩散环（0.35s）。
- 数值（工程侧默认，阶段 8 手感调优可改）：`game_constants.gd` 八·十三段。
- 音效反馈**不在本任务**：`assets/audio/` 阶段 6 才有资产，届时由 JuiceFX 接 AudioStreamPlayer。
- 渲染预览：`res://tools/juice_preview.tscn`（窗口化运行，自截图 `game/build/juice_preview.png`：
  普通 / 暴击 / 玩家受击飘字 + 死亡粒子 + 掉落共存帧）。


### 5.15 装备数据结构验证（任务 3.1）

仓库内自带可执行实测，覆盖 **27 项断言、6 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_equipment.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 模板：42 件装备模板加载、字段齐全（部位 / 稀有度 / 词缀池 / 底材） |
| B | 词缀池：10 池注册、装备引用存在、池非空、池内词缀存在 |
| C | 稀有度条数：GDD 3.2.3 权威表逐档断言（白 0+0 / 蓝 1+1 / 黄 2+2 / 紫 3+2 / 橙 3+3 / 红 4+3 / 绿 2+3 / 彩 3+3） |
| D | 不变式：前缀 + 后缀 = 条数上限（8 档全过） |
| E | iLvl 缩放：`affix_ilvl_scale(L) = 1 + 0.085×(L-1)` |
| F | 序列化：EquipmentInstance to_dict / from_dict 往返一致 |

- 核心缺口=**词缀池表**：新建 `data/affix_pools/pools.json`（10 池显式 ID 列表，80 处装备引用
  / 85 条池条目）。**独立目录**——放 `data/affixes/` 会被词缀扫描误解析。
- 数据与代码分离：装备 62 / 词缀 33（前 9 后 24）/ 词缀池 10 / 传奇特效 31 / 怪物 16 /
  关卡 20 / 掉落表 3 / 套装 3 / 技能 8 / BOSS 机制 2 / 音效 8。
  （注：**关卡 20** 指关数；其**关内数值为 demo 期 POC 值、非 D5 终值** —— 见第 9 节「已实测验证」上方注记）

### 5.16 词缀生成器验证（任务 3.2）

仓库内自带可执行实测，覆盖 **24 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_affix_roller.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 参数：品质权重 35/30/20/10/5、强化词缀概率（紫 15 / 橙 20 / 红 25 / 彩 20 / 绿 10） |
| B | 条数拆分：稀有度 → GDD 3.2.3 前后缀拆分（白 0 / 蓝 1+1 / … / 红 4+3） |
| C | 候选池：装备 affix_pool_ids 去重 + fits_slot + min_rarity + 排除神话词缀 |
| D | 权重 + 互斥组 pick（互斥组不同时出现） |
| E | 数值：Base × affix_ilvl_scale × quality（quality 5 档） |
| F | 强化词缀 ×1.5（对已有词缀概率触发） |
| G | 红装神话独立槽（mythic_all_attributes，不占普通位）+ 掉落接入（instance 随拾取入库） |

- 掉落即定型：`loot_roller._roll_equipment` 装备条目新增 `instance`（完整
  EquipmentInstance.to_dict()），`player_controller.pickup_loot` 存 instance + affix_count。
- 渲染预览：`res://tools/equipment_preview.tscn`（窗口化自截图
  `game/build/equipment_preview.png`：蓝 1 条 / 橙 6 条 / 红 8 条含神话全属性）。
- 排障：GDScript 不支持链式比较（Parse Error）；verify 误调不存在的
  `roll_loot_by_table` —— 已修。

### 5.17 掉落权重表验证（任务 3.3）

仓库内自带可执行实测，覆盖 **18 项断言、5 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_loot_tables.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 权威表：普通 / 精英 / BOSS 三表 × 8 档与 GDD 6.1 逐位一致（容差 0.001） |
| B | 权重和 = 100、橙装概率随档位递增（0.05 → 1.00 → 5.00） |
| C | 难度修正逐项：NM1 红清零 / NM2 红 ×1.5 白 ×0.85 黄 ×1.15 紫橙 ×1.30 绿 ×1.10 彩不变 / 越级紫橙红 ×0.5 |
| D | 一局节奏仿真（3000 局：150 普通 + 5 精英 + 1 BOSS，NM2 L20）：黄 1.92 / 紫 0.75 / 橙 0.20 / 绿 0.33 / 红 0.10 / 彩 0.009，全部落 GDD 期望容差（橙 ≈ 0.186 硬约束）<br>（注：**「150 普通 + 5 精英 + 1 BOSS」为 v1.5 历史基准**，v1.8 现行基准为 **269 杂兵 + 8–10 精英** —— GDD 6.1 已标注该基准「已过期、待重算」，见 0.2 节 POC 注记） |
| E | 底材联动：掉落 item_id 全部 fits 稀有度 / 等级区间 |

- **🐛 抓出并修复 2.7 遗留严重 bug**：`_roll_one` 把 `equipment_share`（0.55 分数）与
  `gold_weight`（30 权重）直接相加 → 装备实际概率 ≈ 1.3% 而非 GDD 6.1 的 55/80/90%
  （仿真橙装节奏 0.00/局暴露）。按 GDD 语义修复：装备占比为**直接概率**，金币 / 材料在
  **剩余部分**按相对权重瓜分。修复后橙 ≈ 0.20/局命中（**该修复的记录见任务清单 `3.3` 条目**）。
- `verify_health.gd` 同期 +`seed(20260916)` 固定随机（毒附加 / dot 判定偶发失败加固）。

### 5.18 锻造与洗练验证（任务 3.4）

仓库内自带可执行实测，覆盖 **22 项断言、6 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_forge.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 成本表：满强化 +10 魔石总数 106（GDD 6.5 v1.8）+ 逐档明细 + 金币 100×1.35^k + 洗练 500×1.15^n |
| B | 成功率表：+1~+5 100% / +6 80% / +8 50% / +9 40% / +10 25% / +12 15%（12 档） |
| C | 强化结算：+1~+5 必成功 / +9 起失败降级 / 满级拒绝 / 成本查询结构 |
| D | 强化属性：forge_level → get_forge_multiplier 线性 +5%/级（+10 = ×1.50） |
| E | 红装 +11/+12：上限 12、魔石 30 + 神话结晶 1（工程侧）、成功率 20%/15%、失败降级 |
| F | 洗练：保类型（affix_id 不变）重掷数值、can_reroll=false 原值保留、成本按次数 |

- 实现：`scripts/forge/forge_controller.gd`（纯静态，**不扣玩家钱包**——只做成本查询与
  骰子结算，返回完整结果由 UI / 背包校验扣费）+ `game_constants.gd` 八·十四段
  （成功率 12 档 / 降级起点 +9 / 金币与洗练成长 / 红装扩展消耗）。
- **GDD 6.5 金币示例与公式不自洽**：公式 `100×1.35^k` 为权威（+10 = 2011）；
  GDD 示例「+10→1,779」「+5→442」判定为笔误（已与 106 明细同样处理：以明确公式为准）。
- 渲染预览：`res://tools/forge_preview.tscn`（窗口化自截图
  `game/build/forge_preview.png`：橙 +0 与 +10 对比（×1.00 → ×1.50，攻击力 32.8 → 49.2
  精确对应）+ 神话 +12（×1.60））。


### 5.19 传奇特效系统验证（任务 3.5）

仓库内自带可执行实测，覆盖 **26 项断言、6 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_legendary_effects.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 数据层：池 **31 件**（遗留项 #3 达标 ≥30）、GDD 3.5 五件示例齐全、范式三要素、部位 / 冷却合法、每部位 ≥ 2 件（重铸池可用） |
| B | 类型白名单：trigger 10 类 / effect 12 类枚举合法、stack/deal_damage/heal/extra_loot 关键参数齐全 |
| C | 装配：橙装 20 件抽查全挂传奇特效（掉落即定型）、红装 1 特效 + 神话词缀、特效槽位与部位匹配、紫装不挂 |
| D | 触发：烬誓叠 5 层引爆 300% 火伤 / 不朽者 90s 冷却拦截 / 七劫之冠阈值 / 烈空 30% 概率（时间推进避开冷却） |
| E | 效果结算：血契暴击回血 3% / 暗蚀召唤幽魂 / 拾遗者额外掉落 / 复苏低血回 10% |
| F | 部位池与重铸抽取：for_slot / roll_for_slot（排除原特效） |

- 范式（GDD 0.3 节 3.5）：**触发条件 + 效果 + 冷却/上限** 三要素必须齐全，避免无脑常驻数值。
- 实现：`data/legendary_effects/legendary_effects.json`（31 件，独立目录防词缀扫描误解析）+
  `scripts/legendary/legendary_effect_system.gd`（纯静态：数据访问 + 触发结算 + 叠层/冷却
  内存态）。`ConfigLoader` 加载期**白名单校验**（trigger/effect 类型 + 参数齐全 + 槽位匹配）。
- 装配：`affix_roller.roll_full_equipment` 对 rarity ≥ 橙 从底材绑定或同部位特效池抽 1 条
  写入 `legendary_effect_id`（已序列化，掉落即定型）；红装另含神话词缀独立槽。
- **效果执行**（回血 / 打伤害 / 召唤）由战斗侧调用方按结算结果执行——本系统只算不执行
  （与 ForgeController 同款「纯结算」模式，可单测、可审计）。
- 渲染预览：`res://tools/legendary_preview.tscn`（窗口化自截图
  `game/build/legendary_preview.png`：6 件代表性特效卡 + 一件橙装装配展示，验收通过）。


### 5.20 背包 / 仓库验证（任务 3.6）

仓库内自带可执行实测，覆盖 **28 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_inventory.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 容量：背包 8×5 = 40 / 仓库 8×10 = 80、add/remove/count/is_full/is_empty |
| B | 满仓：40 件后 add 拒绝、first_empty 正确 |
| C | 移动 / 交换：swap 换位、remove 按 instance_id、越界拒绝 |
| D | 整理：compact 压紧空位（相对顺序保持） |
| E | 排序：稀有度 / 部位 / iLvl 升降序、空位恒在尾部 |
| F | 仓库转移：transfer 成功 / 目标满仓失败且不丢物品 |
| G | 面板接入：InventoryPanel 绑定后刷新、模式切换、排序后首格断言 |

- 数据层：`scripts/inventory/inventory.gd`（纯数据，一格一件、不堆叠；排序用
  `sort_custom` 保证确定性，`instance_id` 决胜）。面板：`scripts/ui/inventory_panel.gd`
  （48×48 格、稀有度边框色、tooltip、选中详情、整理 / 排序 / 仓库切换工具栏）。
- 尺寸（工程侧默认，GDD 未给）：背包 8×5、仓库 8×10；物品格 48×48、格底 `#14171C`
  （GDD 0.3 节 3.7 与美术规范一致）。
- 渲染预览：`res://tools/inventory_preview.tscn`（窗口化自截图
  `game/build/inventory_preview.png`：整理前背包 / 按稀有度排序后对比 + 仓库，验收通过）。


### 5.21 装备对比验证（任务 3.7）

仓库内自带可执行实测，覆盖 **21 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_equipment_compare.tscn
```

| 段 | 覆盖 |
|---|---|
| A | stat_key：33 词缀全部映射非空（AffixData.validate 兜底 + 抽查） |
| B | 汇总：get_total_stats = 底材基础（iLvl + 强化）× 词缀按 stat_key 归并求和 |
| C | 对比：升 / 降 / 平 三态与 diff 值、行排序（升在前） |
| D | 穿戴新件（old = null）：全部为升 |
| E | 空物品 / null 输入安全 |
| F | 特殊键：echo_strike 等机制词缀不进数值对比（进 special 文本） |
| G | 面板渲染：ComparePanel 行数与汇总文案 |

- **stat_key 统计键**（3.9 属性结算的地基）：本任务给 `data/affixes/*.json` 全部 33 词缀
  补 `stat_key`（如 `add_flat_attack → flat_attack`、`add_crit_chance → crit_chance`），
  `AffixData` 增加字段与校验，缺失即加载失败。
- `scripts/ui/equipment_compare.gd`（纯静态）：`get_total_stats`（底材 + 词缀归并）/
  `compare`（新旧 diff）/ `get_special_text`；`scripts/ui/compare_panel.gd`：两列对比表
  （绿升红降灰平、▲/▼ 汇总行、中文属性标签）。
- 渲染预览：`res://tools/compare_preview.tscn`（自截图 `game/build/compare_preview.png`：
  旧铁剑橙 +6 vs 新烬誓·燃魄刃橙 +8，攻击力 152→180 ▲ / 生命值 73.4→0 ▼ 等，验收通过）。


### 5.22 分解 / 合成 / 材料回收验证（任务 3.8）

仓库内自带可执行实测，覆盖 **33 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_dismantle.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 分解产出：GDD 5.3 权威表逐档（白 0 / 蓝 1 尘 / 黄 3 尘 / 紫 1 精粹+5 尘 / 橙 3 精粹 / 绿 4 精粹 / 红 6 精粹+1 结晶 / 彩拒绝） |
| B | 材料包：增 / 扣 / 不足拒绝 / 批量 spend 原子性 |
| C | 合成配方：4 档成本 / 稀有度映射 |
| D | 合成成功：扣费 + 产出稀有度 / iLvl 15–30 / 橙装含传奇特效 |
| E | 合成失败：材料不足不扣费返回 null |
| F | 合成循环：连续合成材料正确递减、耗尽后拒绝 |
| G | 端到端：分解紫装 → 入包 → 合成蓝装 → 再分解闭环 |

- **分解**：`scripts/forge/dismantle_controller.gd`（纯静态，产出 = GDD 5.3 表）。
- **合成**：`scripts/forge/craft_controller.gd`（纯静态）。**配方为工程侧默认，GDD 未给**：
  蓝 10 尘 → 蓝装 / 黄 30 尘+1 精粹 → 黄装 / 紫 3 精粹 → 紫装 / 橙 6 精粹+1 结晶 → 橙装
  （产出 iLvl 15–30，橙装掉落即定型含传奇特效）。
- **材料包**：`scripts/forge/material_bag.gd`（统一钱包：金币 / 魔石 / 秘银尘 / 传说精粹 /
  神话结晶；spend 原子性——任一不足整体失败）。
- 渲染预览：`res://tools/dismantle_preview.tscn`（自截图 `game/build/dismantle_preview.png`：
  分解产出表 + 合成配方 + 材料包合成演示（120 尘合成 4 件后精确余 80），验收通过）。


### 5.23 属性结算系统验证（任务 3.9）

仓库内自带可执行实测，覆盖 **26 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_stat_calculator.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 裸装成长：GDD 6.2 表逐级断言（L1/L5/L10/L15/L20 三属性，HP 150×1.11^(L-1) / AD 12×1.10 / ARM 6×1.10） |
| B | 装备聚合：sum_equipment 逐件累加（与 EquipmentCompare 口径一致） |
| C | 最终结算：flat + pct 乘算（攻击 = (基础+flat) × (1+pct%)） |
| D | 神话全属性：all_attributes 乘主属性三件套 |
| E | Buff 叠加：flat / pct 并入（多 Buff 累加） |
| F | 直接累加键：暴击 / 攻速 / 抗性 / 幸运 / 金币获取等 |
| G | 满装估算：L20 5 件橙 +10 AD 相对裸装成倍增长（口径自洽） |

- `scripts/combat/stat_calculator.gd`（纯静态）：`base_stats(level)`（GDD 6.2 公式）/
  `sum_equipment`（复用 3.7 stat_key 汇总）/ `calculate(level, equipped, buffs)`
  （主属性三件套 flat + pct 乘算 + 神话全属性；暴击 / 攻速 / 抗性 / 资源 / 幸运 /
  减耗 / 冷却等直接累加；FINAL_KEYS 全键默认 0 输出）。
- Buff 接口（4.3 正式接入）：`buffs = {buff_id: {"flat": {...}, "pct": {...}}}`。
- 渲染预览：`res://tools/stat_preview.tscn`（自截图 `game/build/stat_preview.png`：
  L20 裸装（1090/73.4/36.7 精确对应 GDD 表）vs 半装 3 件橙 +6 vs 满装 8 件橙 +10
  （HP 2528.6 / AD 203.4 ×2.8）+ Buff 演示（22 × 1.5 = 33），验收通过）。


### 5.24 套装系统验证（任务 3.10）

仓库内自带可执行实测，覆盖 **25 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_set_system.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 数据：3 套注册、每套 6 件、2/4/6 档齐全 |
| B | 计数：count_pieces 按部位去重 |
| C | 档位：2 件 → [2 档]；4 件 → [2,4]；6 件 → [2,4,6] |
| D | 统计加成：get_bonus_stats 数值汇总（2 件霜噬 +15 冰伤 / 6 件烬途 +20% 攻） |
| E | 进度：get_progress 每套 6 段 + 档位 active 标记 |
| F | 面板：SetPanel 渲染（进度条段数 / 文案） |
| G | 边界：非套装装备、null、重复部位 |

- **数据**：`data/sets/sets.json`（3 套：霜噬 / 烬途 / 守誓者，各 6 件 + 2/4/6 档；
  18 件 `set_` 底材模板已注册且 set_id 关联）。
- `scripts/sets/set_system.gd`（纯静态）：`get_set_of`（底材 set_id）/ `count_pieces`
  （部位去重）/ `get_active_tiers` / `get_bonus_stats`（数值档汇总，**自动并入
  `StatCalculator.calculate`**——属性结算含套装；effect_id 机制档仅文案展示，
  战斗触发逻辑留战斗层）/ `get_progress`。
- `scripts/ui/set_panel.gd`：6 段进度条（激活亮 / 未激活暗）+ 档位文案 ✓/○（GDD 0.3
  节 3.7 套装识别接口：右上角 16×16 徽记位 / 件数徽章 / 6 段进度条已备）。
- 渲染预览：`res://tools/set_preview.tscn`（自截图 `game/build/set_preview.png`：
  霜噬 5/6 + 烬途 1/6 + 守誓者 0/6 进度 + 套装加成汇总 + 属性结算
  （元素伤害 65.6 → 80.6，套装 +15 已并入），验收通过）。


### 5.25 红装 / 彩装机制验证（任务 3.11）

仓库内自带可执行实测，覆盖 **27 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_mythic_hidden.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 数据：红装 2 件（限 mythic）/ 彩装 2 件（限 hidden + 不可分解）+ growth 配置 |
| B | 神话词缀：红装含神话独立槽（`AffixRoller.MYTHIC_AFFIX_ID`，不占普通位）/ 橙装不含 |
| C | 神话重铸：成本（红 = 结晶 ×2）/ 可重铸判定 / 数值重掷 / 彩装拦截 |
| D | 彩装成长：apply_growth 累积 / 上限夹取（其一 +5% / 拾荒者 +15%） |
| E | 成长并入：StatCalculator 含彩装成长（全属性 ×1.05 乘算 / 移速直接键） |
| F | 彩装保护：不可分解（3.8 已拦）不可重铸 |
| G | 边界：null / 非红装 / 非彩装 / null rng |

- **红装神话重铸（GDD 3.4）**：`scripts/forge/mythic_reroll_controller.gd`（纯静态）：
  `get_reroll_cost`（红装 = 神话结晶 ×2，其余空）/ `can_reroll`（仅红装，彩装拦截）/
  `try_reroll_mythic`（找到神话独立槽重掷数值；神话词缀池当前 1 条，类型重掷按候选池抽预留）。
- **彩装唯一性成长（GDD 3.2.2）**：`scripts/items/hidden_growth_controller.gd`（纯静态）：
  `can_grow`（hidden + 底材 growth_stat_key）/ `apply_growth`（百分数累积，夹到
  `growth_max`）/ `get_growth_bonus` / `get_total_growth_bonus`——**自动并入
  `StatCalculator.calculate`**（全属性走神话乘算、移速等走直接键）。
- **数据**：`equipment_data.gd` +growth_stat_key/growth_max；`jewelry.json` 彩装
  七傳說·其一（all_attributes，上限 +5%· 每通关 1 难度 +1%）/ 拾荒者的执念
  （move_speed，上限 +15%· 每 10 万金币 +1%）；彩装模板 `undismantlable: true`。
- 渲染预览：`res://tools/mythic_preview.tscn`（自截图 `game/build/mythic_preview.png`：
  红装神话词缀独立槽 + 重铸成本 + 两件彩装成长前后 + 保护清单，验收通过）。


### 5.26 局内成长验证（任务 4.1–4.3）

仓库内自带可执行实测，覆盖 **23 项断言、6 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_run_growth.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 局内等级：1–10 上限、经验曲线（20×L^1.4）、多级连升（9 次三选一）、出关清零 |
| B | 选项池：15 个选项、类别分布（攻击 6 / 防御 5 / 资源 4）、键完整 |
| C | 三选一：不重复抽 3、已选过的不再出现 |
| D | 30% 上限：攻击/攻速/暴击达上限后从池移除，功能键不占上限 |
| E | Buff 并入：三选一（狂怒 +12% 攻 / 坚韧 +15% 血）→ StatCalculator pct 加算 |
| F | 连杀：3 秒窗口、每 20 连杀 +3% 攻击、上限 +15%、断连重计 |

- `scripts/run/run_progression.gd`（class_name RunProgression）：局内等级 1–10、
  `XP_ToNext(L) = 20 × L^1.4`（**工程侧默认，GDD 未给局内公式**；1→10 级总需 ≈1,848 XP，
  单关 150 怪 × 12 XP 可升满 —— 其中「150 怪」为 **v1.5 历史基准**，v1.8 现行基准为 **269 杂兵 + 8–10 精英**（GDD 6.1 已标注基准过期））、add_xp 多级连升每级触发三选一回调、reset 出关清零。
- `scripts/run/rune_pool.gd`（class_name RunePool 纯静态）：GDD 0.4 节 4.2 的 15 选池
  （攻击 6 / 防御 5 / 资源 4）+ stat_key 映射；`get_choices` 不重复抽 3，**按 GDD 0.4
  节 4.4 上限移除**（攻击/生命 +30%、攻速/暴击率 +20% 达上限出池，自动切功能性选项；
  移速/拾取/金币不占上限）。
- `scripts/run/run_buff_system.gd`（class_name RunBuffSystem）：三选一 / 祭坛二选一
  （狂怒祭坛 +20% 攻但受伤 +15% / 疾风祭坛 +15% 攻速但移速 -10%）/ 连杀（3 秒窗口、
  每 20 连杀 +3% 攻击上限 +15%）→ `to_calculator_buffs` 转 StatCalculator buffs 格式
  （pct 加算）。`StatCalculator` FINAL_KEYS 扩充 5 键：armor_pierce / life_steal /
  damage_taken / regen_pct_hp / shield_pct_hp（局内战斗层消费）。
- `scripts/ui/choice_panel.gd`（class_name ChoicePanel）：三选一三色卡
  （攻击红 / 防御蓝 / 资源黄）+ 选择按钮；点选 → `EventBus.run_buff_selected` 并收起。
- 渲染预览：`res://tools/run_growth_preview.tscn`（自截图 `game/build/run_growth_preview.png`：
  等级模拟 1950 XP → 10 级 + 三选一示例 + ChoicePanel 三色卡 + 连杀 100 → +15% 攻击并入
  结算 12 → 13.8，验收通过）。


### 5.27 关卡商店验证（任务 4.4）

仓库内自带可执行实测，覆盖 **16 项断言、5 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_shop.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 生成：商品数、种类齐全（装备/药水/材料）、装备带实例 |
| B | 定价：装备 = 稀有度基准 × (1+0.5×iLvl)；药水 50；材料 30 |
| C | 购买：扣金币精确 + 装备入包 + 商品移除 |
| D | 失败：金币不足不扣款 / 背包满不扣款 / 无效索引 |
| E | 稀有度分布：10 关采样含橙装（非全白）、无红彩 |

- **设计为工程侧默认（GDD 未细化商店）**：`scripts/run/run_shop.gd`（class_name RunShop）：
  每关 1 次商店、商品 = 装备 ×2 + 药水 + 材料；货币 = 本局金币（D2 方案 B：结算扣 50%，
  本局花本局赚）；定价 = `RARITY_PRICE[稀有度] × (1 + 0.5 × iLvl)`
  （白 10 / 蓝 25 / 黄 60 / 紫 150 / 橙 400 / 绿 350 / 红 800 / 彩 1000）；
  `buy` 原子扣款（金币不足 / 背包满 / 无效索引不扣款）；稀有度按关卡权重
  （越高层紫橙权重略升），红彩不进入商店。
- `scripts/ui/shop_panel.gd`（class_name ShopPanel）：商品列表（名称 + 价格 +
  购买按钮，金币不足置灰），购买成功刷新列表。
- 渲染预览：`res://tools/shop_preview.tscn`（自截图 `game/build/shop_preview.png`：
  4 件商品 + 8 档定价表 + 购买演示（锁子甲 -420 → 余 580）+ D2 约束清单，验收通过）。


### 5.28 本局结算验证（任务 4.5）

仓库内自带可执行实测，覆盖 **14 项断言、5 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_run_result.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 存活结算：字段完整、金币扣 50%（1234→617）、材料扣 50% |
| B | 死亡结算：无存活加成 |
| C | 掉落：已入包保留 / 未入包丢失计数（只计数不扣分） |
| D | 评分：存活 500 + 击杀 ×10 + 等级 ×50 + 稀有 ×100 + 连杀 ×2 分解精确 |
| E | 评级：D/C/B/A/S 阈值（400/700/1000/1500） |

- **结算规则 = D2 方案 B（任务清单已确认）**：保留等级 / 经验 / 已入包装备 /
  已通关解锁；丢失本局未入包掉落；金币材料结算扣 50%；每关 1 次原地复活。
- `scripts/run/run_result.gd`（class_name RunResult）：`finalize(...)` 静态结算
  （返回结算单：存活标记 / 金币材料扣半快照 / 入包保留数组 / 未入包丢失计数 /
  稀有掉落计数 / 连杀峰值 / 评分 / 评级）。
- **评分（工程侧默认，GDD 未给）**：存活 +500、击杀 ×10、局内等级 ×50、
  稀有掉落（紫橙+）每件 ×100、连杀峰值 ×2 → 评级 S/A/B/C/D。
- `scripts/ui/result_panel.gd`（class_name ResultPanel）：结算面板（状态色边框 +
  击杀 / 等级 / 连杀 / 结算规则 / 金币材料扣半 / 掉落统计 / 评分 + 大字评级）。
- 渲染预览：`res://tools/result_preview.tscn`（自截图 `game/build/result_preview.png`：
  存活结算 2345→1172 + 评分 2850 → 评级 S + ResultPanel 完整面板，验收通过）。


### 5.29 局外成长验证（任务 5.1–5.6）

仓库内自带可执行实测，覆盖 **45 项断言、9 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_account.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 账号等级：180×L^1.6 节点（L10=7166…L60=125984）、累计口径、60 满级、天赋点 30 |
| B | 天赋树：3 分支 × 20 节点 / 分支解锁 L1/L15/L30 / 点数上限（30 级 15 点） |
| C | 天赋加成：小 +2% / 大 +8% / 机制列表 |
| D | 解锁系统：关卡顺序 / 梦魇 I 全 20 关逐层 / 仓库页 5/10/15 |
| E | 附魔：洗练秘银尘 ×3 重掷数值 / 特效重铸精粹 ×2 更换特效 |
| F | 宝石：槽位（黄 1 / 橙 2）/ 镶嵌替换 / 拆卸 / 加成（普通红 +6%） |
| G | 声望：1 关量 ≈1 级（每级 150）/ 上限 10 / +1% 经验 +1% 金币每级 |
| H | 成就：JSON 加载 ≥20 / 进度解锁不重复 / 外观奖励 |
| I | 并入结算：天赋 + 宝石 + 声望 → StatCalculator buffs |

- **5.1 账号等级**（GDD 5.1 v1.8）：`180 × L^1.6`、1–60 级、累计 = Σ₁^(L-1)；
  `scripts/account/account_level.gd`（class_name AccountLevel），每 2 级 +1 天赋点。
- **5.2 天赋树**（GDD 5.2）：武力 / 守护 / 秘法 3 分支，每分支 15 小(+2%) + 5 大
  (+8% 或机制)；分支解锁 L1 / L15 / L30；满级 30 点最多点满半棵树；
  `scripts/account/talent_tree.gd`（class_name TalentTree）。
- **5.3 解锁系统**（GDD 5.4）：关卡顺序、梦魇 I–V 逐层、仓库页 5/10/15；
  `scripts/account/unlock_system.gd`（class_name UnlockSystem 纯静态）。
- **5.4 附魔**（GDD 5.3 材料表 + 工程侧默认）：秘银尘 ×3 洗练首条普通词缀
  （含 iLvl 缩放，跳过神话词缀）；传说精粹 ×2 同部位池重铸橙特效；
  `scripts/forge/enchant_controller.gd`（class_name EnchantController）。
- **5.5 宝石**（GDD 5.5 项名，工程侧默认规则）：4 档 × 3 色；槽位白 0 / 蓝黄 1 /
  紫橙+ 2；免费镶嵌拆卸、替换覆盖；`EquipmentInstance` +gems 字段随存档序列化；
  `scripts/items/gem_system.gd`（class_name GemSystem）。
- **5.6 声望与成就**（GDD 5.5）：章节声望每 1 级 +1% 经验 +1% 金币（上限 10 级/章）；
  成就 `data/achievements.json` 20 个（kills / clears / gold_earned / account_level /
  mythic_acquired / hidden_acquired / set_pieces / streak / run_score / rerolls /
  talent_nodes 十一类），奖励**纯外观**（武器光效 / 角色配色），**不给战力**；
  `scripts/account/chapter_reputation.gd` + `achievement_system.gd`。
- 渲染预览：`res://tools/account_preview.tscn`（自截图 `game/build/account_preview.png`：
  账号等级 + 天赋树 + 解锁系统 + 附魔/宝石/声望/成就 四块，验收通过）。


### 5.30 关卡 / 地图生成验证（任务 6.1）

仓库内自带可执行实测，覆盖 **73 项断言、8 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_level_gen.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 关卡数据：三章 20 关、等级 1–20 连续、全部 validate 合法（关内数值为 POC 值，非 D5 终值） |
| B | 解锁链：顺序 unlock_requires 完整（跨章连接） |
| C | 布局生成：地面 ≥30% / 墙边界 / 玩家出生在地面 / 尺寸匹配 |
| D | 怪物分布：权重投放 ≤ 预算 / 全部地面格 / 距出生 ≥6 格 |
| E | 精英与 BOSS：锚点数匹配 / BOSS 远端锚点在地面 / 「目标是 kill_boss 的关必有 boss_id」 |
| F | 确定性：同种子布局一致、异种子布局不同 |
| G | 目标可达性：20 关的目标**确定可完成**（不是「大概率能完成」） |
| H | **手绘地图**：手绘分支**确实被执行**（`authored_hits`）/ 逐格等于手绘图（4 关全量核对）/ 不依赖种子 / README 示例可直接跑 / **连通性**（四类锚点可达 + 无孤立可行走区）/ **`ch1_l01` 开局三条线** / 6 张非法图被拒 / canary 钉住地形碰撞体与「挡人格集合」逐格等价 |

- **数据**：`data/levels/` 扩至三章 20 关（chapter1 1–6 保留 + chapter2 7–13 +
  chapter3 14–20）；每关含推荐等级 / 怪物条目（章节主题怪）/ 精英锚点数 /
  BOSS ID（章末关）/ 布局参数（尺寸 / 房间数 / 障碍密度 / 种子）/ 奖励。
- **生成器**：`scripts/run/level_generator.gd`（class_name LevelGenerator），
  两条互斥路径，输出**同一份契约**：
  - **程序化**（16 关，缺省）：拒绝采样挖房间（间隔 ≥2 格）+ 顺序走廊连接，
    输出 `cells`（Vector2i → 地面 / 墙 / 障碍）+ 玩家出生（首房间）+
    怪物投放（权重 + 距出生 ≥6 格）+ 精英锚点 + BOSS 远端锚点 + 拾取点；同种子可复现。
  - **手绘**（4 关：`ch1_l01` / `ch1_l02` / `ch1_l05` / `ch1_l06`，用户可自己画）：见 **8.3.1 手绘地图**。
    整条路径**不消耗 `rng`**，同一份 JSON 每次产出完全一致。
- `resources/level_data.gd` 新增 `elite_count` / `boss_id` / `layout` 字段
  （ConfigLoader 同步解析）。
- 渲染预览：`res://tools/level_preview.tscn`（自截图 `game/build/level_preview.png`：
  三章主题程序化地图（森林绿 / 灰烬暖褐 / 霜渊蓝）+ 出生 / 精英 / BOSS 标记，
  验收通过）。
- 手绘地图真渲染取证：`"$GODOT" --path "D:/七傳說/game" res://tools/capture_tiles.tscn -- ch1_l02 --void-check`
  （**必须去掉 `--headless`**）→ `deliverables/gstack/screenshot-tiles-ch1_l02.png`
  + `screenshot-voidcheck-ch1_l02.png`。实测：1200 格 tile、地图贡献 **1** 个 draw call、
  敌人 50 个、虚空探针无洋红像素（= 画面里没有地图外 void）。


### 5.31 怪物扩充 / 精英词缀怪验证（任务 6.2）

仓库内自带可执行实测，覆盖 **24 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_monsters62.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 怪物数据：16 种、三章等级带可用（一章 ≥4 / 二章 ≥6 / 三章 ≥5）、全部 validate 合法 |
| B | 数值爬坡：第二章 / 第三章怪 HP 系数高于第一章（烬石魔像 1.9 / 冰封尸骸 1.75） |
| C | 精英：≥4 种（屠夫 / 霜缚幽魂 / 焰术信徒 / 寒霜幽魂）且全部绑定精英掉落表 |
| D | 词缀池：6 条定义齐全、中文名可读、权重表 6 项 |
| E | 词缀抽取：1–2 条不重复、权重随机、抽到的都在池内 |
| F | 词缀数值：急速 ×1.35 / 吸血 20% / 荆棘 15% / 爆炸 40px·80% / 闪现 6 秒 |
| G | 并入敌人：`enemy_base.tscn` 实例化后急速移速乘法生效、HP 初始化、荆棘反弹探针掉血 ≈15 |

- **数据**：`data/monsters/monsters.json` 8→16——新增 孢蘑菇（毒·远程抛射）、
  暗影猎犬（物理·高速贴脸）、烬石魔像（火·高血冲锋，HP×1.9 / DMG×1.35 / 护甲 14）、
  炼狱小鬼（火·远程放风筝）、灰烬猎犬（火·高速低血）、焰术信徒（**精英**·火·远程，
  绑定 `monster_elite` 掉落表）、冰封尸骸（冰·高血，HP×1.75）、寒霜幽魂（**精英**·冰·远程）。
- **词缀**：`scripts/enemies/affix_controller.gd`（class_name AffixController 纯静态）——
  急速（移速 ×1.35）/ 吸血（攻击回复 HP 20%）/ 爆炸（死亡 40px 内 80% 攻击伤害）/
  回响（攻击 30% 二连击）/ 荆棘（受击反弹 15%）/ 闪现（每 6 秒瞬移玩家附近）；
  `roll_affixes` 按权重抽 1–2 条不重复。
- **敌人集成**：`scripts/enemies/enemy_base.gd` 新增 `affixes` 数组与 6 处钩子
  （`_ready` 移速乘法与闪现计时 / 巡逻与追击速度 / `_tick_state` 闪现 / `_attack_player`
  吸血与回响 / `take_damage` 荆棘反弹 / `_on_unit_died` 爆炸），占位色块美术
  （普通暗红 / 精英紫 / BOSS 金）沿用。
- 渲染预览：`res://tools/monsters_preview.tscn`（自截图 `game/build/monsters_preview.png`：
  16 种怪物全览网格 + 6 词缀演示区，新增怪亮色标注，验收通过）。


### 5.32 BOSS 设计与机制验证（任务 6.3）

仓库内自带可执行实测，覆盖 **32 项断言、7 个测试段**：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_boss63.tscn
```

| 段 | 覆盖 |
|---|---|
| A | BOSS 数据：2 个章末 BOSS 配置合法（阶段门 / 4 段技能 / 召唤池 / 狂暴） |
| B | 阶段判定：HP 比例 → 阶段（100→1 / 80→1 / 70→2 / 40→3 / 10→4） |
| C | 技能集：阶段 1 基础 → 阶段 2 召唤 → 阶段 3 范围 → 阶段 4 狂暴，逐级累积去重 |
| D | 召唤：数量随阶段递增（0→2→3→4）/ 召唤池 id 全部在怪物表 |
| E | 狂暴乘区：阶段 4 攻速 ×0.6 / 伤害 ×1.3（阶段 1–3 为 ×1）；阶段伤害乘区递增 |
| F | BOSS 掉落：monster_boss 100% 掉 2–4 件（GDD 6.1） |
| G | 集成：EnemyBase tier=BOSS 挂载阶段机制；HP 阈值触发阶段切换 + `boss_phase_changed` 广播 |

- **数据**：`data/bosses/bosses.json` —— 骸骨暴君（骨系：基础近战 → 召唤骷髅/暗影猎犬 →
  范围践踏 → 狂暴）与 熔心之主（火系：火球 → 召唤小鬼/灰烬猎犬 → 熔岩喷发 → 狂暴）；
  阶段门 **75% / 50% / 25%**（4 阶段），阶段伤害乘区递增，狂暴攻速 ×0.55–0.6 / 伤害 ×1.3–1.35。
- **控制器**：`scripts/enemies/boss_phase_controller.gd`（class_name BossPhaseController
  纯静态）——`current_phase` / `phase_skills`（累积去重）/ `summon_count_for` /
  `enrage_multipliers` / `phase_damage_mult` / `validate`。
- **敌人集成**：`scripts/enemies/enemy_base.gd` 新增 BOSS 钩子 —— `_ready` 加载阶段配置
  （阶段 1）、`take_damage` 后按 HP 比例检测阈值切换（技能扩展 + 乘区 + 广播
  `EventBus.boss_phase_changed`）、`_attack_player` 施放阶段技能（召唤实例化杂兵 /
  AoE 践踏），攻击间隔与伤害乘狂暴乘区。
- **加载**：`scripts/autoload/config_loader.gd` 新增 `bosses` 注册表与 `get_boss(id)`，
  交叉校验 BOSS 在怪物表 / 召唤池怪物存在（独立 `data/bosses/` 目录，避免与怪物表同目录误解析）。
- 渲染预览：`res://tools/boss_preview.tscn`（自截图 `game/build/boss_preview.png`：
  两 BOSS 四阶段血条 + 阶段技能标签 + 狂暴/召唤池说明，验收通过）。


### 5.33 技能库扩充验证（任务 6.4）

技能实测随技能库扩充升级为 **49 项断言、8 个测试段**（原 45 项 + 备选技能 4 项）：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_skills.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 技能表：8 条（3 出战 + 5 备选）/ ID 稳定排序 / 出战栏位 1/2/3 不被备选占用 / validate |
| A' | 备选技能（6.4 新增）：slot 0 不入栏、覆盖单/范围/位移三形态、冰火雷毒影五元素、数值合理 |
| B | 法力池：消耗 / 不足拒绝 / 自然回复 / 减耗 |
| C | 冷却：施放置冷却 / 冷却中拒绝 / 计时递减 / 到期可再放 |
| D | 普攻假连段：按住连击 / 间隔拒绝 / 松开停止 / 移动中可攻 / 闪避打断 / 命中回蓝 |
| E | 技能效果：裂斩单体 350% / 旋刃 AoE + 击退 / 突进撞击 + 位移 |
| F | 回归：移动 / 闪避无敌帧 |

- **数据**：`data/skills/skills.json` 3→8 —— 出战（slot 1–3）裂斩 / 旋刃 / 突进；
  备选（slot 0）冰霜新星（AoE·冰·110%·半径 64）、火球术（单体·火·240%·射程 140）、
  闪电链（单体·雷·180%·射程 130）、毒云（AoE·毒·85%·半径 56）、暗影步（位移·影·120%·冲刺 120）。
- **槽位语义**：`resources/skill_data.gd` slot 放宽 0–3（0 = 备选，不入出战栏）；
  `scripts/combat/skill_controller.gd` 只加载 slot ≥ 1 的技能（技能栏 1/2/3 保持裂斩/旋刃/突进），
  备选技能供局内成长「技能替换」在运行时接入。
- **元素表**：`scripts/core/game_constants.gd` 新增 `ELEMENT_SHADOW`（暗影）→ 元素体系 5 → 6 系
  （物理 / 火 / 冰 / 雷 / 毒 / 影），`verify_damage` 元素断言同步升级。
- 渲染预览：`res://tools/skills_preview.tscn`（自截图 `game/build/skills_preview.png`：
  8 技能卡片（元素色块 + 形态徽章 + 倍率/冷却/蓝耗 + 描述），出战排前，验收通过）。


### 5.34 装备库填充验证（任务 6.5）

装备库扩充为 **62 件**，新增独立实测脚本 `tools/verify_equipment65.gd|.tscn`（**14 项断言、7 个测试段**）：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_equipment65.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 总量：装备库 62（weapons 14 / armor 14 / jewelry 16 + 套装件 18） |
| B | 三章等级带：1-6 / 7-13 / 14-20 每章可用装备 ≥ 20 |
| C | 合法性：全部底材 validate 通过 + 词缀池引用全部存在（load_errors 空） |
| D | 新增 20 件：烈焰剑 / 血斧 / 冰川锤 / 淬毒匕首 / 风暴法杖 / 灵风长弓 / 石像头盔 / 烬织胸甲 / 冰织手套 / 守望腿甲 / 疾风靴 / 泰坦王冠 / 余烬护符 / 霜戒 / 雷暴之戒 / 影纱吊坠 / 嗜血之戒 / 烈日圣印 / 回响之戒 / 守护者勋章 |
| E | 数值：烈焰剑攻 22 / 泰坦王冠 HP 60 稀有起步 / 灵风长弓攻速 12 / 嗜血之戒吸血 3 |
| F | 权重：全部 > 0，稀有件权重 < 普通件（泰坦王冠 40 < 铁剑 120） |
| G | 槽位与套装：10 槽位全部 ≥1 件；套装体系 3×6 不破坏 |

- **数据**：`data/equipment/weapons.json` 8→14（+烈焰剑/血斧/冰川锤/淬毒匕首/风暴法杖/灵风长弓，
  覆盖剑/斧/锤/匕首/法杖/长弓 6 形态）；`armor.json` 8→14（+石像头盔/烬织胸甲/冰织手套/守望腿甲/
  疾风靴/泰坦王冠）；`jewelry.json` 8→16（+余烬护符/霜戒/雷暴之戒/影纱吊坠/嗜血之戒/烈日圣印/
  回响之戒/守护者勋章）。
- **设计取向**：新增底材沿三章梯度分布（第 1 章白蓝黄 / 第 2 章黄紫 / 第 3 章紫橙传奇）；
  稀有度下限随物品等级带抬升（泰坦王冠 rare 起步、烈日圣印 rare 起步）；
  掉落权重普通件 > 稀有件，保证前期刷到率。
- 渲染预览：`res://tools/equip_preview.tscn`（自截图 `game/build/equip_preview.png`：
  按 10 槽位分组的 62 件全览，稀有度色条 + 新增件 * 标注，验收通过）。


### 5.35 音效/音乐验证（任务 6.6）

音效/音乐为**程序化合成占位方案**（与占位色块美术同思路：先闭环自玩体验，真音频可直接替换
`data/audio/*.wav`）。新增独立实测脚本 `tools/verify_audio66.gd|.tscn`（**9 项断言、6 个测试段**）：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_audio66.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 注册表：8 条音效 id（hit_melee / hit_crit / enemy_die / pickup_gold / pickup_item / levelup / boss_phase / ui_click） |
| B | 文件存在：data/audio/ 8 个 wav 资源全部可加载 |
| C | 流解析：AudioStreamWAV 数据非空 / mix_rate 合法 |
| D | 播放管线：AudioManager.play 无场景树静默、有场景树可挂载（播放即焚） |
| E | 钩子接线：enemy_base（受击/死亡/BOSS 阶段）、player_controller（金币/装备拾取）、run_progression（升级） |
| F | 音量：全部 volume_db 在 -24..0 dB |

- **数据**：`data/audio/*.wav` 8 条合成音效（22050Hz 16-bit mono，Python wave 生成）——
  打击（方波 200Hz + 噪声 0.12s）/ 暴击（340Hz + 泛音 0.18s）/ 死亡（600→150Hz 扫频 0.25s）/
  金币（1200→1800Hz 升调 0.09s）/ 装备（三角波 700→1100Hz 0.14s）/ 升级（琶音 523/659/784Hz 0.42s）/
  BOSS 阶段（锯齿 160→55Hz 低吼 0.5s）/ UI 点击（短方波 1000Hz 0.04s）。
- **播放管线**：`scripts/audio/audio_manager.gd`（新 class_name `AudioManager`）纯静态 ——
  `play(id)` 惰性预载流 + 临时 AudioStreamPlayer 播放即焚，零 autoload 配置、
  无场景树静默跳过（verify 无副作用）；注册表含每条音效的 volume_db。
- **钩子接入**：`enemy_base.take_damage`（被玩家命中 → hit_melee，荆棘反弹二次受击不重复响）、
  `_on_unit_died`（enemy_die）、`_apply_boss_phase`（boss_phase）；
  `player_controller.pickup_loot`（金币/材料 → pickup_gold、装备 → pickup_item）；
  `run_progression.add_xp` 升级循环（levelup）。
- 渲染预览：`res://tools/audio_preview.tscn`（自截图 `game/build/audio_preview.png`：
  8 条音效卡片（用途 + 合成特征 + 音量）+ PCM 波形折线，验收通过）。


### 5.36 UI/UX 面板验证（任务 7.1–7.7）

阶段 7 UI/UX 全部 7 项完成。新增综合实测脚本 `tools/verify_ui71.gd|.tscn`
（**24 项断言、7 个测试段**）：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_ui71.tscn
```

| 段 | 面板 | 覆盖 |
|---|---|---|
| A | 7.1 主菜单/角色选择 | 3 按钮（开始/设置/退出）+ 账号概览 + 开始回调 |
| B | 7.2 角色属性面板 | 8 基础属性 + 4 元素抗性 + 6 元素伤害行 |
| C | 7.3 背包装备界面 | 10 槽渲染 + 选中详情 + 穿/脱回调 |
| D | 7.4 天赋界面 | 3 分支卡片 + 已点 ✓ + 可用点数 + learn 回调 |
| E | 7.5 锻造界面 | 费用显示 + 材料不足禁用 + 锻造/重铸回调 + 结果反馈 |
| F | 7.6 结算奖励界面 | 结算单 + 奖励清单 + 返回大厅/再来一局按钮 |
| G | 7.7 设置界面 | 画质（垂直同步/全屏）+ 音量联动 AudioServer + 按键重置 |

- **新增面板（纯代码构建 class_name，像素风 Theme）**：
  `scripts/ui/main_menu_panel.gd`（7.1）、`stat_panel.gd`（7.2）、`equip_panel.gd`（7.3）、
  `talent_panel.gd`（7.4）、`forge_panel.gd`（7.5）、`settings_panel.gd`（7.7）。
- **增强**：`result_panel.gd`（7.6）——逐项奖励清单（前 6 件已入包装备 + 超出计数）
  + 返回大厅/再来一局按钮（回调注入，战斗层决定去向）。
- **职责边界**：所有面板只读数据 + 回调转发（on_start / on_equip / on_learn / on_forge /
  on_hub / on_restart…），不直接写业务状态——与 InventoryPanel（3.6）同契约；
  设置即时生效（音量 → AudioServer / 画质 → DisplayServer / 按键 → InputRemapper），
  设置持久化归任务 8.2。
- 渲染预览：`res://tools/ui_preview.tscn`（自截图 `game/build/ui_preview.png`：
  7 面板分区全览（左列 主菜单/属性/天赋/设置 · 右列 装备/锻造/结算），验收通过）。


### 5.37 完整存档验证（任务 8.1）

阶段 8 首项完成。`SaveData` 已实现全字段序列化（局外进度 + 局内进度 + 设置），
`SaveManager` 槽位 / 备份轮转 / 损坏隔离 / 原子写均已有（3.x 验收过）。本项新增
综合闭环实测 `tools/verify_save81.gd|.tscn`（**15 项断言、6 个测试段**）：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_save81.tscn
```

| 段 | 覆盖 |
|---|---|
| A | 新建槽位（`create_new_slot` 返回非空 + 槽位存在） |
| B | 局外全字段：账号等级/经验/天赋点/节点/金币/材料/背包/装备/仓库/解锁/通关/耗时/难度层级/声望/成就/仓库页/统计 |
| C | 局内进度：`current_level_id` / `current_difficulty_tier` 写入 |
| D | 设置字典随档保存（自由键值） |
| E | 装备实例回读：模板 id / 稀有度 / 锻造等级逐项一致 |
| F | 跨会话模拟（保存 → 重读 → 全字段一致）+ 清理 |

- **字段矩阵（15 类）**：`account_level / talent_points / gold / materials /
  inventory / equipped / stash / unlocked_levels / cleared_levels /
  chapter_reputation / unlocked_achievements / statistics /
  current_level_id / current_difficulty_tier / settings`。
- 存档粒度 = 关卡边界（D2 方案 B）：局内进度仅存当前关 + 难度；关内临时状态
  （血量/位置）不持久化。
- 渲染预览：`res://tools/save_preview.tscn`（自截图 `game/build/save_preview.png`：
  局外 / 局内 / 设置 3 卡片快照，验收通过）。

### 5.38 设置持久化验证（任务 8.2）

设置独立于存档持久化（换档不丢设置）。新增 `scripts/core/settings_store.gd`
（**class_name SettingsStore** 纯静态，`user://settings.json`）：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_settings82.tscn
```

| 机制 | 说明 |
|---|---|
| 默认值 | `master_volume_db -6 / vsync true / fullscreen false / key_bindings {}` |
| 类型白名单 | 每个键按声明类型校验（float/bool/Dictionary），非法值回退默认 |
| 非法 JSON | 文件解析失败 → 复制隔离为 `settings.json.corrupt_*` + 回退默认 |
| 应用联动 | 音量 → AudioServer / vsync+全屏 → DisplayServer / 按键 → `InputRemapper.load_bindings()` 回放 |
| 变更即存 | `SettingsPanel`（7.7）读 SettingsStore 初始值，任何改动 `set_value` 立即落盘 |

- 实测 `tools/verify_settings82.gd|.tscn`（**12 项断言、5 个测试段**：默认值 /
  写入读回 / 跨加载保持 + AudioServer 联动 / 类型回退 + 非法隔离 / 清理）。
- `main.gd` 自检 **96 → 98**（8.1 存档矩阵 + 局内进度、8.2 默认值 + 类型白名单）；
  全量回归 **33 / 33 脚本**通过。


### 5.39 性能优化验证（任务 8.3）

工程侧两项落地，实测 `tools/verify_perf83.gd|.tscn`（**10 项断言、5 个测试段**）：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_perf83.tscn
```

| 机制 | 说明 | 实测 |
|---|---|---|
| `ObjectPool` 通用对象池 | `scripts/core/object_pool.gd`（class_name 纯静态）：`acquire(key, factory)` 池里有则复用、无则工厂创建；`release` 归还池（隐藏 + 移出活跃树）；池满自动 `queue_free` 兜底不泄漏 | 二次 acquire 命中同一实例；预热后复用率 ≥ 90%（实测 96%）；池满容量 2 不泄漏；退出 drain 无 ObjectDB 泄漏 |
| `LevelView` 地图批处理 | `scripts/run/level_view.gd`（class_name）：整个 layout 画进**一个** CanvasItem 的 `_draw`（逐格 `draw_rect`，地面/墙/障碍三色 + 金色出生点） | 单节点承载全图 1184 格；draw call ≈ 1–2；对比旧方案每格一个 ColorRect = 上千节点 |
| 接入就绪 | 高频对象（敌人/掉落/飘字）的池化接口由 ObjectPool 提供；本项不改动既有生命周期（避免破坏 juice/loot 实测） | 后续战斗层直接调用 |

- **优化报告要点**：Draw Call 大头是地图 tile（数百格 × 每格一个 Control/Node）；
  本项把地图渲染收敛为单 CanvasItem，战斗层接入 `LevelView.set_layout()` 即可。
  对象池解决高频创建/销毁抖动（敌人波次 / 掉落物 / 飘字），
  容量上限 + 池满兜底保证内存有界。
- 渲染预览：`res://tools/perf_preview.tscn`（自截图 `game/build/perf_preview.png`：
  左对象池统计 + 右批处理地图（深灰地面 / 亮灰墙 / 暗红障碍 / 金色出生点），验收通过）。
- `main.gd` 自检 **98 → 100**；全量回归 **34 / 34 脚本**通过。


### 5.40 平衡性调优 · 数值仿真验证（任务 8.4）

**平衡报告**：`tools/verify_balance84.gd|.tscn` 输出 20 关 × 5 难度仿真矩阵
（常规怪 TTK + 玩家承伤秒数），并断言 8 项（5 段）。口径全部来自 D9 与怪物数值 v1.5。

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_balance84.tscn
```

**仿真口径**：

| 项 | 公式 | 说明 |
|---|---|---|
| 怪物 HP | `100.7 × 1.284^(L-1) × 1.08^n` | 怪物数值 v1.5 × 难度层级 |
| 怪物 DMG | `5.61 × 1.218^(L-1) × 1.23^n` | 梦魇 V ≈ 伤害 ×2.4 / HP ×1.36 |
| 玩家 DPS | `20 × 1.30^L × 1.25` | **8.4 调优**：复合成长（等级+装备+技能）由 1.10 调至 1.30，匹配怪成长 |
| 玩家 MaxHP | `500 × 1.06^L` | 战士基础 + 局内成长 |
| TTK | 怪 HP / 玩家 DPS | 常规怪击杀秒数 |
| 承伤秒数 | 玩家 MaxHP / (怪 DMG × 0.5/s) | 可存活秒数 |

**仿真结论（8/8 断言全过）**：

| 断言 | 目标 | 实测 |
|---|---|---|
| 常规怪 TTK | ∈ [1, 8] 秒（不海绵化） | **2.4 – 4.2 秒**（20 关 × 5 难度全区间） |
| 难度爬坡 | TTK 随难度递增 / 承伤随难度递减 | 单调 ✓ |
| 梦魇 III–V 承伤 | < 10 秒（玩家可被秒，D9 授权） | **5.9 秒**（L20 梦魇 V） |
| 普通前 5 关承伤 | > 12 秒（新手不猝死） | **108 秒** |
| 成长可见 | 第 20 关 TTK ≤ 第 1 关 ×2 | 2.4 ≤ 3.1 × 2 ✓ |

**调优动作**：玩家复合成长 1.10 → **1.30**（原曲线下第 20 关 TTK 膨胀到 94 秒 =
海绵化；调整后 TTK 收敛 2.4–4.2 秒，实现「怪不海绵化、高层级允许被秒」的 D9 目标）。
- 渲染预览：`res://tools/balance_preview.tscn`（自截图 `game/build/balance_preview.png`：
  左 TTK 5 难度曲线 + 右承伤秒数曲线，验收通过）。
- `main.gd` 自检 **100 → 102**；全量回归 **35 / 35 脚本**通过。


### 5.41 Bug 修复与回归测试（任务 8.5）

**测试报告**：全量回归 **36 / 36 脚本**通过、退出码 0、零告警零泄漏。
新增回归红线复核 `tools/verify_fix85.gd|.tscn`（**8 项断言**），把开发期踩过的
关键修复点固化为自动化红线，防止后续改动回退：

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_fix85.tscn
```

| 红线 | 历史修复点 |
|---|---|
| 存档槽位边界 | SLOT=18 越界（SAVE_MAX_SLOTS=8）→ 槽位 7 可用 + 字段矩阵完整 |
| 设置类型白名单 | 字符串塞 float 回退默认 -6；默认值镜像含 key_bindings |
| 对象池复用零泄漏 | Node.visible 误用 / 循环变量作用域 / headless ObjectDB 泄漏 |
| LevelView 兼容 | cells 是 Dictionary（Vector2i→int）+ 障碍格 TILE_OBSTACLE + 出生点 Vector2i |
| 平衡 TTK 红线 | 复合成长 1.30：20 关 TTK ≤ 2.4s（原 1.10 为 94s 海绵化） |
| 数据表锚点 | 怪物 16 / BOSS 2 / 技能 8 / 装备 62 / 关卡 20（关内数值为 POC 值，非终值） |

- **回归矩阵**：`tools/verify_*.tscn` 36 个入口覆盖——数据（玩家 33 / UI 34 /
  存档 26 / 技能 49 / 伤害 40 / 敌人 34 / 命中 25 / 生命 25 / 掉落 20 / 打击感 18 /
  装备 27 / 词缀 24 / 掉落表 18 / 锻造 22 / 传奇 26 / 背包 28 / 对比 21 / 分解 33 /
  属性 26 / 套装 25 / 红装 27 / 局内成长 23 / 商店 16 / 结算 14 / 账号 45 / 关卡 22 /
  怪物 24 / BOSS 32 / 装备库 14 / 音效 9 / UI 24 / 存档 15 / 设置 12 / 性能 10 /
  平衡 8 / 红线 8）。
- **状态**：阶段 8 五项全部完成（8.1 存档 / 8.2 设置 / 8.3 性能 / 8.4 平衡 / 8.5 回归）。
- `main.gd` 自检 **102 → 104**（数据表锚点 + 槽位边界）。


### 5.42 崩溃与异常处理（任务 9.3）

**稳定性补丁**：新增 `scripts/core/game_log.gd`（**class_name GameLog** 纯静态，
`user://logs/game.log`——时间戳 + 2MB 轮转保留 7 份 + 尾部读取），
main.gd 启动时记录引擎版本与运行模式；实测 `tools/verify_fix93.gd|.tscn`
（**25 项断言**，见下方「静默 bug 回归」）全过，退出码 0。

**窗口化启动实测发现并修复 2 个真实 Bug**（此前一直 headless 验证，未暴露）：

| Bug | 根因 | 修复 |
|---|---|---|
| 音效播放时序 | main._ready 自检阶段 `add_xp` 触发 AudioManager.play，同步 `add_child` 时父节点正在 setup children → `add_child failed` + `Playback only when inside scene tree`（×3） | `add_child.call_deferred(player)` + `player.ready.connect(player.play)`（树忙安全，任意时序可播） |
| `%g` 格式化 | main.gd 自检用 C 风格 `%g`，GDScript 不支持 → `String formatting error` | 改 `%d`（百分数值取整） |

修复后窗口化启动 **stderr 0 行**，自检 106 项全过，渲染验收
`build/boot_preview.png`（主场景骨架界面正常显示）。存档容错
（备份轮转 / 损坏隔离 / 原子写，3.x 已实现）在本项抽查通过。
- `main.gd` 自检 **104 → 106**；全量回归 **37 / 37 脚本**通过。

#### 5.42.1 集成层阶段 2：4 处**静默** bug 回归（`verify_fix93` 6 → 25 项）

集成审计（`deliverables/gstack/integration-audit-2026-09-17.md` §2.6）指出：
有 3 处 bug **不报任何错**，静态检查与「写 1 行读 1 行」式的浅测试都抓不到，
必须**造出特定场景**才能暴露。修复时统一采用「**断言先证伪再转正**」：
先写一条在当前代码上**必然失败**的断言，确认它真的能抓住该 bug，再改代码让它转绿。

| # | 位置 | 静默 bug | 后果 | 为什么以前测不出 |
|---|---|---|---|---|
| 17 | `game_log.gd` | 用 `FileAccess.WRITE` 写日志（**截断**而非追加） | 日志永远只剩最后一行 ⇒ 文件永远长不到 `MAX_BYTES`，2MB 轮转与「保留 7 份」**全是死逻辑**，`read_tail()` 最多 1 行，9.3「崩溃后靠日志定位」被完全废掉 | 只断言「写 1 行 → 读得到 1 行」永远通过 |
| 17b | `game_log.gd` | `FileAccess.READ_WRITE` **不新建文件**（实测文件不存在时返回 `null`，`open_error=7` / `ERR_FILE_NOT_FOUND`） | 轮转后新日志行被静默丢弃；更严重的是**全新机器上 `game.log` 从来不存在 ⇒ 永远建不出来 ⇒ 日志功能整体失效** | 测试机上的旧日志一直在，E/F 段都跑在「文件已存在」的前提下 |
| 18 | `enemy_base.gd` | `_player_level()` 探测 `get_level`，而玩家暴露的是 `get_player_level()` ⇒ `has_method` 恒 false | 返回恒 0 ⇒ `LootRoller.roll_loot(..., 0)` 的**越级惩罚完全失效** | 只测 `_player == null` 那条分支测不出，必须**挂真实玩家节点** |
| 19 | `player_controller.gd` | 缺 `apply_knockback(offset)`（`SkillController._hit` 用 `has_method` 探测） | **玩家永远不会被击退**，且无任何报错 | 方法缺失只让 `has_method` 为 false，日志里什么都没有 |
| 19b | `player_controller.gd` | 击退写成 `velocity += _knockback_velocity`——`velocity` 是 `CharacterBody2D` 的**跨帧持久属性**，上一帧的击退已写进去，这一帧再 `+=` 一次 ⇒ **逐帧累积发散** | 请求 12px 位移实际走 **61.4px（≈5 倍）**，且随帧数发散；连击时更夸张 | 断言只写「位移 > 1.0」时，**发散反而让它更容易通过** —— 必须补上界 |

修复后 `verify_fix93` 由 **6 项扩到 25 项**，全部通过、退出码 0。
新增的 3 类断言是这次真正有价值的部分：

- **F/I 段「文件不存在」场景**：删掉 `game.log` 再写一行，必须重新建出文件
  （只测「已存在」的 E 段抓不到 17b）。
- **G 段「有对象在场」分支**：挂真实 `player.tscn` + `enemy_base.tscn`，断言
  `_player_level() == get_player_level()` 且 `!= 0`（只测空引用分支抓不到 18）。
- **H 段位移上界 + 衰减停止**：断言位移落在 **6–24px**（期望 ≈12px），
  并断言 20 帧后位移不再变化（抓 19b 的累积发散；只写下界会漏）。

> ⚠️ 教训：`has_method()` + `call()` 的探测式调用**会静默降级** ——
> 方法名拼错、方法不存在，都不会报错，只是那段逻辑悄悄不执行。
> 凡是这种写法，都必须有一条「走真实对象、断言**效果**而非仅断言方法存在」的测试。

#### 5.42.2 集成层阶段 3：又 2 处**静默** bug（同一个模式，第三次出现）

阶段 3 把「主菜单 → 新档 → 据点 → 选关 → 进关卡 → 打怪 → 拾取 → 结算 → 回据点」
串成一条真流程后，立刻又暴露 2 处**同类**静默 bug —— 它们的共同点是
**既有测试全都绕过了真实生产路径，自己手工构造了一个「形状正确」的入参**。

| # | 位置 | 静默 bug | 后果 | 为什么以前测不出 |
|---|---|---|---|---|
| 20 | `loot_drop.gd` | `LootDrop` **没有 `instance` 字段**，`setup()` 不读它，`_pick_up()` 也不转发它。而 `LootRoller` 明明在掉落时就 roll 好了词缀并放在 `entry["instance"]`（任务 3.2「掉落即定型」） | 词缀在**掉落物这一环被丢弃**，`PlayerController.pickup_loot()` 里 `if entry.has("instance")` 不成立 ⇒ **静默走「无词缀占位」分支** ⇒ 玩家捡到的每一件装备都是**无词缀白板**（刷宝游戏的核心乐趣直接归零），且**没有任何报错** | `verify_affix_roller.gd:269` **直接调用** `_player.pickup_loot({...instance...})`，**不经过 LootDrop** ⇒ 测试全绿 |
| 21 | `result_panel.gd:75` + 关卡容器 | 关卡容器把会话背包的 **Dictionary** 原样塞进 `RunResult.bagged_equipment`，而 `ResultPanel.show_result()` 按**对象**读 `item.template_id / .rarity / .item_level` | 抛 `Invalid access to property or key 'template_id' on a base object of type 'Dictionary'`；更严重的是异常发生在**创建「返回大厅 / 再来一局」按钮之前** ⇒ **玩家卡在结算界面回不了据点**（软锁） | `verify_run_result.gd:42` 与 `verify_ui71.gd:246` 都自己用 `EquipmentInstance.create_from_template(...)` 构造结算单，**从不走关卡容器那条生产路径** |

**修复方式**：
- #20：给 `LootDrop` 补 `instance` 字段，`setup()` 读、`_pick_up()` 转发。
- #21：关卡容器新增 `_collect_bagged()` 把会话背包条目**转成 `EquipmentInstance`**，
  并在 `RunResult.bagged_equipment` 的字段注释里把「元素必须是 `EquipmentInstance`」
  写成**显式契约**（原字段只有一句「入包装备（保留）」，没有任何类型约束）。

**新增的断言**（`tools/verify_e2e.tscn`，走**真实**生产路径）：
- ⑦ 断言**每一条**入包装备都带非空 `instance`（不要求有词缀 —— iLvl 1 的普通装本来就没词缀，
  所以不能按「词缀条数 > 0」断言，那样会误伤）。
- ⑧ 断言结算面板**真的渲染出奖励明细行**（`iLvl` 行数 == min(入包数, 6)），
  并在同一条流里断言「返回大厅」按钮存在 —— 面板一旦在渲染中途抛错，这两条会一起变红。

> ⚠️ **教训升级版**：这已经是同一个模式的**第三次**（17b / 18 / 19 → 20 / 21）。
> 判据不是「有没有测试」，而是「**测试有没有走生产路径**」。
> 凡是「A 产出 → B 消费」的边界（掉落物↔拾取、关卡↔结算面板、组件↔宿主），
> 只测两端各自「形状正确」的入参，等于把最脆的那一环（**字段/类型的搬运**）完全放空。
> `verify_e2e.tscn` 的价值就在于它是**唯一一条把两端接起来跑**的测试。

### 5.42.3 相机缩放：全项目单一来源 `CAMERA_ZOOM_BASE`

阶段 3 之前的相机缩放是**散落的硬编码**：`tools/playtest.tscn:24` 写死 `zoom = Vector2(3, 3)`，
其余场景没有相机。现在收敛为 `game_constants.gd` 的 `CAMERA_ZOOM_BASE = Vector2(2, 2)`：

- `.tscn` 里**不再写** `zoom`（写死的值改常量不会同步，是最典型的"两处真相"）；
- `playtest.gd` 与关卡容器都在 `_ready()` 里 `camera.zoom = GameConstants.CAMERA_ZOOM_BASE`。

取值依据：1920×1080 + 32px tile ⇒ 1× 下一屏可见 **60 tile 宽**，远大于同类作品的 20–30 tile；
2× 后为 **30 tile 宽**，落在同类区间上沿。

**实测渲染确认（`tools/level_scene_preview.tscn` → `build/level_scene_preview.png`，1920×1080）**：

| 观察项 | 结论 |
|---|---|
| 地图尺度 | 一屏 30 × 16.9 tile ✅ 符合设计区间；房间/走廊清晰可辨 |
| 怪物可辨识度 | 32×32 占位色块 → 屏上 64×64，明确可辨 ✅ |
| 玩家占屏比 | 约 9% 屏高，与同类作品（8–12%）一致 ✅ |
| **HUD 字号** | **偏小** ⚠️ 主题 `theme.tres` 的 `default_font_size = 11`，在 1920×1080 逻辑画布上约 1% 屏高，正常阅读偏吃力。属**主题层（任务 1.6 / 7.x）**问题，**不是相机缩放造成的**，故本次未改 |
| **玩家占位美术比怪小** | ⚠️ 占位身体精灵小于 32×32 的怪物色块，视觉上"主角比杂兵小"。属**占位美术（任务 2.1）**问题，真实 48×48 精灵接入后消失 |

> 结论：**2× 对世界尺度是合适的**，不需要改动；上表两项 ⚠️ 是主题/占位美术的既有问题，
> 已按"不单方面扩大改动范围"的原则记录并上报，未在阶段 3 内顺手改。


### 5.43 本地打包导出（任务 9.1）

**纯本地自玩**：`export_presets.cfg`（Windows Desktop / x86_64 / `embed_pck=true`
单文件分发）导出 **`build/七傳說.exe`（110MB）**。导出模板
`4.7.2.stable`（1.22GB，GitHub release）下载安装至
`%APPDATA%\Godot\export_templates\4.7.2.stable\`；镜像 gh-proxy/ghfast/清华均不可用
或限速 → **GitHub 直连 + curl `-C -` 断点续传**完成。

验证链路（全过，退出码 0）：
- `tools/verify_export91.gd|.tscn` **5/5**：exe 存在 / 体积 ≥60MB（资源内嵌）/ Windows 预设 / embed_pck / 输出路径；
- 导出 exe 无头自检 **108/108**（与编辑器一致；导出版引擎默认排除 export_presets.cfg，
  main.gd 该项发布态自动判定通过）；
- 导出 exe 窗口化冒烟：运行 8 秒无闪退，`user://logs/game.log` 落盘启动记录。

> 交付形态：`game/build/七傳說.exe` 双击即玩（单文件，无外部依赖）。
> 提示：`--headless -- --verify` 可用于 exe 自检；后续 9.2 本地自测直接双击运行即可。
> 🧹 **打包前置铁律**：每次导出前先清 `user://` 存档与用户内容 —— 见 **5.47 节**
> （`python tools/package_demo.py` 一键完成「清数据 → 删旧包 → 导出 → 验证」）。


### 5.44 本地完整流程自测（任务 9.2）

**核心循环数据链路自动化验证**（`tools/verify_play92.gd|.tscn`，**7/7 通过**，seed 固定可复现）：

| 步骤 | 结果 |
|---|---|
| 1. 新档（槽 3） | 账号 Lv.1，初始生命 **150** / 攻击 **12** |
| 2. 刷怪掉落（5 级蜘蛛，LootRoller） | 产出 `staff_ashen`（普通，Lv.5） |
| 3. 换装变强 | 穿戴后攻击 **12 → 25**（+13，成长成立） |
| 4. 存档 → 重开 | 金币 120 / 经验 45 / 击杀 7 / 装备槽全字段一致 |

**玩家实操部分（待补）**：双击 `game/build/七傳說.exe` 试玩，按
「新档 → 刷怪 → 掉落 → 换装 → 变强 → 存档 → 重开」走一遍，反馈手感
（移动 / 攻击 / 掉落节奏 / 数值曲线），据此进入 9.4 手感迭代。

### 5.45 端到端跑通（集成层阶段 3 · 审计 §4 #2）

```bash
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_e2e.tscn
# 退出码 0 = 全流程走通；1 = 有失败项
```

**这是全项目唯一一条把两端接起来跑的测试**（`tools/verify_play92.tscn` 只覆盖数据链路，
不经过任何场景）。它**真的点按钮、真的切场景、真的打怪掉装备**：

| 步 | 做什么 | 关键断言 |
|---|---|---|
| ① | 清空全部存档 → 进主菜单 | 根节点是 `CanvasLayer` 且挂了 `MainMenuPanel` |
| ② | 点「开始游戏」（主菜单内部走 `_start_new_character`） | `current_data` 就绪、槽位已落盘 |
| ③ | `SceneManager` 切到据点 | 据点数 = 新档数据 |
| ④ | **按显示名找到关卡按钮并 `pressed.emit()`** | 按钮存在且未 disabled |
| ⑤ | 进关卡容器 | 载荷生效、`tile > 0`、敌人 > 0、玩家进 `player` 组、**相机 zoom == `CAMERA_ZOOM_BASE`**、生命上限由 `StatCalculator` 接管 |
| ⑥ | 逐只 `take_damage` 真实打死 | 击杀数 == 刷怪数、存活清空、地面有掉落 |
| ⑦ | 掉落物走**真实距离判定**被拾取 | 会话背包增长、拾取有实际收益、**每件入包装备都带完整 `instance`**（回归 #20） |
| ⑧ | 清空目标 → 自动结算 | 结算面板可见、**渲染出奖励明细行**、有「返回大厅」按钮（回归 #21）、落盘金币/击杀统计/通关记录 |
| ⑨ | 点「返回大厅」回据点 → **重新读档** | 金币/通关记录/背包装备在**磁盘上**一致 |

**实测：连续 5 次全部 34/34 通过，退出码 0。**

两处刻意的测试期改动（不改玩法，只为让流程在无头下快速跑完，均写在脚本注释里）：
`SceneManager.fade_duration = 0.0`；处决阶段给玩家挂无敌帧
（因为精英词缀「荆棘」会反弹 15% 伤害，测试用 1e9 一击必杀会被反弹 1.5e8 秒杀玩家 —— 这是**测试手法**的副作用，真实玩家不会打出 1e9）。

> ⚠️ 本脚本有两个容易踩的结构性坑，都写在文件头注释里：
> ① 执行体必须挂在 `get_tree().root` 下 —— 挂在自身场景里会被 `SceneManager` 切场景时一起 free；
> ② 退出逻辑必须写在执行体**内部** —— 若用 signal 回调宿主场景的方法 quit，
> 宿主在第①步就被 free、连接被自动断开，表现为「流程跑完了但进程不退出」。
> 另外 `root.add_child()` 必须 `call_deferred`（`_ready` 时 root 正在 setup children，否则静默失败）。

---

### 5.46 全量回归与解析预检（一条命令跑完所有断言）

```bash
cd D:/七傳說
python game/tools/run_regression.py                     # 推荐：自动隔离 APPDATA
python game/tools/run_regression.py --list              # 只列出将要跑的
python game/tools/run_regression.py --only e2e          # 只跑名字含 e2e 的
python game/tools/run_regression.py --no-preflight      # 跳过解析预检
```

**跑什么**：`tools/` 下全部 `verify_*.tscn`（50 个）+ `self_check`（111 项骨架自检）= **51 项**，
实测约 **94 秒**全绿。

**判定口径**（三条都要满足才算通过）：

| 条件 | 说明 |
|---|---|
| `[FAIL] == 0` | 脚本自己的断言没有失败项 |
| `exit == 0` | 进程正常退出，不是被外部 timeout 杀掉的 |
| **有结果行** | 必须输出 `结果：N 项失败` / `全部通过（N 项）` 之类 |

第三条是「非空即空转」原则的落地：**跑了、退了、但一条断言都没报**的脚本比失败的脚本更危险
——它看起来是绿的。这类脚本现在会被判 `NO-RESULT` 并计为失败。

#### 为什么需要解析预检（2026-09-20 事故）

队友在编辑 `tools/verify_level_gen.gd` 中途被中断，留下 4 处解析错误。表现**不是「测试红了」**，
而是静默挂死 120 秒后 `exit=124` —— 很容易被误读成「基础设施问题」而不是「代码坏了」：

1. 主场景脚本解析失败 ⇒ 场景根本不会实例化；
2. `VerifyWatchdog.arm()` 写在 `_ready()` 里 ⇒ **永远到不了 `_ready()`，看门狗从未被武装**；
3. 进程既不报错也不退出，只能耗到 120s 墙钟兜底。

> ⚠️ **这是结构性的，不是配置问题**：任何在 `_ready()` 里武装的看门狗，都只能覆盖
> 「加载成功之后」的失败。加载期失败必须由**脚本之外**的东西兜 —— 也就是下面两层。

| 层 | 做什么 | 实测效果 |
|---|---|---|
| **开跑前预检** `tools/parse_all.tscn` | 把全部 `.gd` 加载一遍（183 个约 5 秒），有解析失败就**直接中止**回归 | 坏脚本从「挂死 120s」变成「开跑前 7 秒点名」 |
| **逐个脚本流式判定** `run_regression.py` | 边读输出边找 `Parse Error`，命中后 2.5 秒收尾就杀掉，并打印 `文件:行` | 单个坏脚本 **120 秒 → 约 3 秒** |

预检覆盖范围含**游戏代码**，不只是 verify 脚本 —— 它是全项目扫描，不是只扫测试。

#### 两个踩过的坑（写在代码注释里，别改回去）

- **预检必须是「场景」而不是 `--script`**：`--script res://tools/parse_all.gd` 走自定义 MainLoop，
  **autoload 不会被注册**，任何引用 `EventBus` 的脚本都会报 `Identifier not found: EventBus` ——
  实测把 183 个文件里的**约 90 个**误报成「解析失败」。走普通场景则 autoload 正常就位。
- **不能用 `load() == null` 判解析失败**：Godot 对解析失败的文件**仍然返回一个非 null 的
  Script 对象**，只是 `can_instantiate() == false`、`get_instance_base_type() == ""`。
  用 null 判会产生**假绿**（实测踩到）。同理**不能用 `CACHE_MODE_IGNORE`**：它会重新解析
  正在使用的脚本（含 autoload 和本工具自己），导致 VM 状态损坏。

#### 顺带修掉：`self_check` 在无头下不退出

`self_check` 是最大的一套断言，却因为文件名不匹配 `verify_*` 而长期游离在全量回归之外 ——
它的「无头下打印完报告后挂死」就是这样藏了下来的（连续三次自检都是 `exit=124`，
报告却写着「全部通过（111 项）」，极易被误读成「自检失败」或「自检很慢」）。

根因：`self_check.gd` 有两条入口 —— `-- --verify`（CI，打印后 `quit`）与
`res://tools/self_check.tscn`（调试，**故意留着窗口让人看报告**）。后者在无头下没有窗口可看，
只剩「永远不退出」这一个效果。现在补了一条：**无头运行也退出**（退出码语义不变）。
`self_check` 同时已并入全量回归，以后它的退出码会被自动检查。

---

### 5.47 每次打包前清空 user:// 数据（发布铁律 · 2026-09-22）

> 🔒 **铁律（柳絮 2026-09-22）：「以后每次打包都需要清除之前的数据资料」**
> 每次导出前，**必须先清空** `user://` 下的 `saves\`（存档）与 `content\`（玩家替换素材），
> 否则测试玩家会带着上一版的存档 / 自定义素材进入新包，**污染验证结果**。

一键完成（脚本 `tools/package_demo.py`；用 Python 而非 `.ps1`，避免非 ASCII 路径乱码）：

```bash
cd D:/七傳說/game
python tools/package_demo.py             # 清数据 + 删旧包 + 导出 + 验证（默认即清数据）
python tools/package_demo.py --backup    # 可回滚：先移入 build/_prev/<时间戳>/ 再清，而非删除
python tools/package_demo.py --keep-data # 本次保留存档（仅在明确需要时）
python tools/package_demo.py --run       # 导出后顺便启动
```
> `--backup`（opt-in，默认关）：删除前把旧包 `build\七傳說.exe` / `*.pck` 与 `user://saves` / `content` **移入** `build\_prev\<YYYYMMDD-HHMMSS>\`（同碟 rename、可回滚；`build/` 已在 `.gitignore`，不污染版本库），并打印备份落点与档数；不带该参数时仍为直接删除。

脚本按序执行并逐步打印中文结果：

1. **清数据**：清 `%APPDATA%\Godot\app_userdata\七傳說\{saves,content}\`（以及工程内镜像
   `game/Godot/app_userdata/七傳說/` 的同名目录）；**删前先列清单**（文件数 / 总大小），
   删后保留 `saves/`、`content/` 顶层骨架（`content/` 的一级子目录一并还原）。
2. **删旧包**：删 `build\七傳說.exe` 与 `build\*.pck`。
3. **导出**：`"<GODOT>" --headless --path . --export-release "Windows Desktop" "build\七傳說.exe"`。
4. **验证**：新 exe 存在、体积 > 0、时间戳是刚刚、PE 头 `MZ`。

> ⚠️ **删除白名单保护（硬约束）**：脚本只删上述三类，**绝不匹配** `*_preview.png` / `*.import`。
> `game\build\*_preview.png`（README 多处引用的渲染证据图）、`game\assets\`、`deliverables\` 一律不动。
> 若文件被占用（游戏仍在运行），脚本会**报错退出**而非暴力终止进程 —— 请先手动关闭游戏。
> `GODOT_BIN` 环境变量可覆盖 Godot 可执行档路径。

---

## 六、输入映射（任务 1.3）

已在 `project.godot` 的 `[input]` 中配置，**键盘 + 手柄双映射**。
全部按键使用 **`physical_keycode`**，保证 WASD 在任意键盘布局下都落在相同物理位置。

| 动作 | 键鼠 | 手柄 |
|---|---|---|
| `move_up` / `move_down` / `move_left` / `move_right` | W / S / A / D 或 ↑ / ↓ / ← / → | 左摇杆 |
| `attack_primary` | 鼠标左键 | X |
| `skill_1` | 1 | LB |
| `skill_2` | 2 | RB |
| `skill_3` | 3 | LT（扳机轴） |
| `skill_4` | 4 | RT（扳机轴） |
| `dodge` | Space | B / A |
| `interact` | E | Y |
| `inventory` | Tab | Start |
| `character_panel` | C | D-pad ↑ |
| `pause` | Esc | Back |

> **✅ 已与 `project.godot` `[input]` 段（第 63–153 行，共 14 个 action）逐条对齐（2026-09-18 核对）**：
> 键位编码以代码为准 —— 技能键是 **`1` / `2` / `3` / `4`**（`physical_keycode` 49/50/51/52），
> 旧文档里的 Q / E / R 为过期写法，已废弃。
> 手柄索引按 Godot `JoypadButton` 枚举换算：`2`=X、`3`=Y、`0`=A、`1`=B、`4`=Back、
> `6`=Start、`9`=LB、`10`=RB、`11`=D-pad ↑；`skill_3` / `skill_4` 用扳机**轴**（axis 4 = LT、axis 5 = RT）而非按键。
> `dodge` 手柄侧为 **B / A 双绑**（`button_index` 1 与 0 两条事件），故表中记为「B / A」。

### 6.1 动作命名约定

- 技能统一叫 `skill_1`–`skill_4`（**不用** `skill_primary`/`skill_ultimate` 这类语义名）——
  因为技能栏是固定 4 格、可自由编排的，语义名会和实际装配的技能打架。
- `pause` 取代了旧的 `ui_pause`（避免与 Godot 内建的 `ui_*` 动作族混淆）。

### 6.2 重绑定（`InputRemapper`）

玩家改键走 `InputRemapper`（Autoload），默认绑定始终以 `project.godot` 为准：

```gdscript
InputRemapper.rebind(&"dodge", new_event)   # 改绑（只替换同设备类别的事件）
InputRemapper.reset_to_default(&"dodge")    # 恢复出厂
InputRemapper.save_bindings()               # 落盘 user://input_bindings.json
```

- **改键位不会顺手清掉手柄绑定**（`rebind` 按「键盘 / 鼠标 / 手柄」三类分别替换），
  反之亦然。这是刻意的 —— 否则玩家改一次键就会丢掉整套手柄配置。
- 绑定文件只记录**与出厂默认不同**的动作，便于人工排查；文件损坏时静默回退到出厂默认，不阻断启动。
- 手柄热插拔通过 `EventBus.joypad_connection_changed(device, connected)` 广播，
  UI 层据此切换按键图标 / 弹提示。

> ⚠️ 本模块文件名是 `input_remapper.gd` 而非 `input_map.gd`：
> `InputMap` 是 Godot 内建单例，用同名文件 + `class_name` 会遮蔽全局类并导致解析错误。

---

## 七、2D 物理层约定

`project.godot` 已登记 9 个 2D 物理层，阶段 2 建碰撞体时按此分配：

| 层 | 名称 | 用途 |
|---|---|---|
| 1 | `world` | 地形 / 墙体 |
| 2 | `player` | 角色本体 |
| 3 | `enemy` | 怪物本体 |
| 4 | `player_hitbox` | 角色受击判定 |
| 5 | `enemy_hitbox` | 怪物受击判定 |
| 6 | `projectile` | 投射物 |
| 7 | `pickup` | 地面掉落物 |
| 8 | `interactable` | 可交互物（宝箱 / 祭坛） |
| 9 | `trigger` | 区域触发器 |

---

## 八、数据文件速查

### 8.1 新增一件装备底材

在 `game/data/equipment/` 任意 `.json` 中追加：

```json
{
  "id": "sword_new",
  "display_name": "新剑",
  "slot": "main_hand",
  "weapon_archetype": "sword",
  "base_stats": { "flat_attack": 10.0, "crit_chance": 3.0 },
  "item_level_min": 1,
  "item_level_max": 20,
  "rarity_min": "common",
  "rarity_max": "legendary"
}
```

`slot` 可用键：`helm` `chest` `gloves` `legs` `boots` `main_hand` `off_hand` `amulet` `ring_a` `ring_b`
`weapon_archetype` 可用键：`sword` `axe` `hammer` `dagger` `staff` `longbow` `shield`
`base_stats` 的键见 `GameConstants.STAT_*`（如 `flat_attack` / `pct_hp` / `crit_chance`）
`rarity_min` / `rarity_max` 可用键：`common` `magic` `rare` `epic` `legendary` `mythic` `set` `hidden`

### 8.2 新增一条词缀

```json
{
  "id": "add_new_affix",
  "display_name": "新词缀",
  "description_template": "+{value}% 某某",
  "category": "attack",
  "position": "suffix",
  "is_percentage": true,
  "value_min": 4.0,
  "value_max": 7.0,
  "decimal_places": 1,
  "allowed_slots": [],
  "weight": 100.0
}
```

> **百分比词缀的数值本身就是百分数**：`value_min: 4.0` 表示 4%，
> 模板里直接写 `%`，用 `{value}` 占位。
> `{value_pct}`（数值 ×100）只用于「以小数存储的比例」这类特殊词缀。

### 8.3 新增一个关卡

```json
{
  "id": "ch1_l07",
  "display_name": "幽林 · 新关",
  "chapter": 1,
  "level": 7,
  "objective_type": "clear_all",
  "monster_entries": [
    { "monster_id": "skeleton_warrior", "count_min": 20, "count_max": 30, "weight": 100.0 }
  ],
  "reward_xp": 4200.0,
  "reward_gold": [180, 300],
  "unlock_requires": ["ch1_l06"]
}
```

`objective_type` 可用键：`clear_all` `kill_elite` `kill_boss` `survive` `collect` `reach_exit`
`tier` 可用键：`normal` `elite` `boss`

> ⚠️ **数值口径**：示例中的怪物投放数量（及 `total_monster_budget`）当前为 **demo 期 POC 值，非 D5（单局 14–21 分钟）终值** —— 回填时机见第 9 节「已知待办」#4 与任务 11.9（AoE 埋点）。

### 8.3.1 手绘地图（自己画关卡布局，不写代码）

**需求**：「我可以自己換場地地圖任務特效等」。
地图**美术**本来就换得掉（`assets/tilesets/<biome>/atlas.png` + `atlas.json`，或 `LevelData.tileset_path`）；
这里补上**布局**—— 不用改任何 `.gd`，只往关卡条目的 `layout` 里加一个 `cells` 就行。

**触发条件**：`layout` 里**有 `cells` 键**就走手绘，没有就走程序化。
当前 **4 关手绘**（`ch1_l01` / `ch1_l02` / `ch1_l05` / `ch1_l06`），其余 **16 关保持程序化不变**
（逐字节不变 —— 手绘是**可选入口**，不是把全项目改成手绘；`verify_level_gen` H 段会断言
「至少 1 关手绘 **且** 仍有程序化关卡」，防止有人一路手绘到底把程序化路径废掉）。

**格式**：`cells` = **行字符串数组**（一行一个字符串），字符含义：

| 字符 | 含义 | 字符 | 含义 |
|---|---|---|---|
| `#` | 墙 | `@` | **玩家出生**（恰好 1 个） |
| `.` | 地面 | `m` | **杂兵**锚点（≥1 个，且 ≤ 本关 `Σcount_max`） |
| `o` | 障碍（柱子 / 石块） | `e` | **精英**锚点（个数必须 == `elite_count`） |
| （空格） | 地面（等同 `.`，纯视觉留白） | `B` | **BOSS**锚点（`boss_id` 非空时恰好 1 个，否则必须 0 个） |
| | | `p` | **拾取 / 祭坛**锚点（≥1 个；目标是 `collect` 时 ≥ `objective_value`） |

**为什么是行字符串，不是 `[x, y, kind]` 三元组**：
① 所见即所得 —— 手绘地图的价值就是「看得见形状」，三元组要先在脑子里反解坐标；
② 不会漂移 —— 坐标表与几何是两份数据，改了地图忘改坐标 ⇒ 出生点落进墙里；行字符串里出生点就是地图上的一个字符；
③ git diff 可读 —— 改一格只动一行里的一个字符。

**复制这个例子就能跑**（`data/levels/chapter1.json` 的 `ch1_l02` 就是这个格式）：

```json
{
  "id": "ch1_l02",
  "objective_type": "clear_all",
  "elite_count": 2,
  "monster_entries": [
    { "monster_id": "spider_cave",      "count_min": 20, "count_max": 30, "weight": 100.0 },
    { "monster_id": "bat_swarm",        "count_min": 10, "count_max": 16, "weight": 60.0 },
    { "monster_id": "skeleton_warrior", "count_min": 6,  "count_max": 10, "weight": 40.0 }
  ],
  "layout": {
    "cells": [
      "#############",
      "#@.........##",
      "#.....##....#",
      "#.....##..e.#",
      "#...........#",
      "#.p........m#",
      "#....mm.....#",
      "#..o....oe..#",
      "#############"
    ]
  }
}
```

改完直接跑：
```bash
"$GODOT" --path "D:/七傳說/game" res://tools/capture_tiles.tscn -- ch1_l02 --void-check   # 真渲染一帧存 PNG
```

**校验（画错了会响亮报错，不会静默给一张打不通的图）**：
`LevelGenerator` 会 `push_error` 出「第几行第几列是什么」，并放弃生成。会被拦下的情况：

1. `cells` 不是非空字符串数组 / 各行不等长；
2. 出现未定义字符（报出行列与可用字符表）；
3. `@` 不是恰好 1 个；
4. **地图四边必须全是墙**（本项目 2026-09-18 踩过「出生点贴边 + 相机无边界 ⇒ 整屏一半是 void」）；
5. `m` 数量为 0，或超过本关 `Σcount_max`；或某个 `m` 距 `@` **< 6 格**（出生即被围）；
6. `e` 个数 ≠ `elite_count`；
7. `boss_id` 非空但 `B` 不是 1 个，或 `boss_id` 为空却画了 `B`；
8. `p` 少于 1 个（`collect` 关少于 `objective_value`）；
9. 同时写了 `layout.width` / `layout.height` 但与行宽 / 行数不一致（建议手绘时**别写**这两个字段，以 `cells` 为准）；
10. **连通性**：从 `@` 做 **4 连通** flood fill 后，
    - 每个 `m` / `e` / `B` / `p` 都必须走得到；
    - **不允许存在孤立可行走区域**（哪怕那个房间是空的、没有任何锚点也照样报）。

    ⚠️ 第 10 条是手绘**最典型**的坑：随手画一个封闭小隔间、往里塞两只怪，`clear_all`
    就永远打不通 —— 玩家硬卡死且没有任何提示（与 `ch1_l03` 的精英软锁同类）。
    前 9 条一条都挡不住它。判定口径 = **墙 / 障碍阻挡 + 4 连通**：
    墙与障碍**今天真的挡人**（`level_scene.gd:_build_collision()` 运行时建出
    `TileCollision`，`collision_layer = 1`；玩家 `collision_mask = 1`、敌人 `mask = 3`），
    所以这条校验和物理现实是同一件事。取 4 连通而不是 8 连通，是因为玩家碰撞形状是
    `RectangleShape2D(20, 22)`（半宽 10px > 0）⇒ 两个**对角相接**的墙格之间没有缝，
    8 连通会把「只能斜着挤过去」的假通路算成连通，等于把校验放水。

**怪物种类怎么定**：`m` 只决定**位置**；种类按 `monster_entries` 的 `count_min` 比例**交错发牌**
（池 = 每条目按 `count_min` 重复后逐轮交错，再按行主序循环发）。
想要某片区域全是骷髅，就把 `skeleton_warrior` 的 `count_min` 调大、或把 `m` 画在那片区域并把它排到 `monster_entries` 前面。

**手绘 = 确定性**：整条路径不读 `rng`，`layout.seed` 对手绘无意义，同一份 JSON 每次产出完全一致。
（`ch1_l01` 原先没有 `seed` ⇒ 每局重随机（实测三次墙数 700/813/758、出生点 (35,4)/(33,5)/(33,11)），
「第一关视觉定稿」无从谈起；手绘化后同一份 JSON 每次一模一样。）

**第一关的开局质量线**：`ch1_l01` 是玩家看到的第一屏，所以 `verify_level_gen` H 段额外钉了三条
（**设计意图断言**，重画 `ch1_l01` 时会自动被守住，不用靠人肉再看一眼）：

| # | 线 | 为什么 |
|---|---|---|
| ① | 全图可走占比 ≥ 50% | 别画成迷宫墙海 |
| ② | 出生点 3×3 邻域 **9/9** 可走 | 出生不贴墙、不卡在障碍里 |
| ③ | 出生点所在**取景框**内可走 ≥ 50% | 开局第一屏不空旷、不满屏黑 void；取景框尺寸从 `project.godot` 的真实视口算（640×360 ÷ `TILE_PX`=32 ⇒ 20×11），不写死 |

### 8.4 新增一种怪物

**关键约定：怪物条目只写「相对基线的倍率」，不写绝对值。**

```json
{
  "id": "new_monster",
  "display_name": "新怪",
  "tier": "normal",
  "level_min": 1,
  "level_max": 12,
  "move_speed": 70.0,
  "attack_interval": 1.4,
  "attack_range": 36.0,
  "base_armor": 0.0,
  "hp_scale": 1.0,
  "damage_scale": 1.0,
  "sprite_path": "res://assets/sprites/enemies/new_monster.png",
  "sprite_directions": 2,
  "ai_id": "melee_chaser",
  "base_xp": 10.0,
  "gold_range": [5, 15],
  "element": "physical"
}
```

- `hp_scale` / `damage_scale`：相对 `GameConstants.MONSTER_HP_AT_L1` / `MONSTER_DMG_AT_L1` 的倍率。
  例：`hp_scale: 0.7` = 比基线脆 30%；`hp_scale: 1.58` = 比基线肉 58%。
- **为什么不用绝对值**：阶段 3 数值调参（仿真报告已建议改基线）时，
  改 `GameConstants` 一个常量即可让全部怪物同步生效，不必逐个改 JSON。
  这是把「绝对值散落在 8 个条目里」这个坑提前填掉。
- `hp_growth` / `damage_growth` 一般**不要写**，继承全局值即可；仅当某只怪需要独立曲线时才覆盖。

### 8.5 新增一组套装

套装定义放 `game/data/sets/`，**必须与底材双向一致**（加载器会交叉校验）：

```json
{
  "id": "new_set",
  "display_name": "新套装",
  "style_tag": "流派标签",
  "emblem_path": "res://assets/sprites/items/set_emblem_new_set.png",
  "piece_template_ids": ["a_helm", "a_chest", "a_gloves", "a_legs", "a_boots", "a_mainhand"],
  "tier_bonuses": [
    { "pieces": 2, "description": "+15% 护甲", "stats": { "pct_armor": 15.0 } },
    { "pieces": 4, "description": "格挡后回复 5% 最大生命", "stats": {}, "effect_id": "block_heal" },
    { "pieces": 6, "description": "生命 <30% 时获得 40% 减伤", "stats": {}, "effect_id": "last_stand" }
  ]
}
```

**约束**（违反会被加载器报错）：
- `piece_template_ids` 必须正好 **6 件**，且每件底材的 `set_id` 必须等于本套装的 `id`
- `tier_bonuses` 必须覆盖 **2 / 4 / 6** 三个档位
- 套装底材的 `rarity_min` / `rarity_max` 都应设为 `"set"`

---

## 九、当前状态与待办

> **当前状态（2026-09-18）**：**阶段 0–10 已完成**（可玩 demo 已产出，双击 `build/七傳說.exe` 进主菜单）；**阶段 11（残项收敛 / 发布候选 RC）进行中**。

### 已完成（阶段 1）

| 任务 | 内容 | 落点 |
|---|---|---|
| 1.1 | 项目初始化 + 目录规范 | `project.godot` + 全部目录 |
| 1.2 | 全局常量（稀有度 8 档四维度 / 部位 10 / 武器原型 10（主手 6 + 副手 4）/ 难度 I–V 与**方案 D 数值** / 32 属性键 / 套装与彩蛋机制常量 / 经济锚点（XP 曲线 180、满强化魔石 106）） | `scripts/core/game_constants.gd` |
| 1.3 | 输入映射（键鼠 + 手柄双映射）+ 重绑定 + 手柄热插拔 | `project.godot` `[input]` + `scripts/core/input_remapper.gd` |
| 1.4 | 全局事件总线 | `scripts/autoload/event_bus.gd` |
| 1.5 | 场景管理（异步加载 + 过场） | `scripts/autoload/scene_manager.gd` |
| 1.6 | UI 框架与主题（程序化 Theme：Cubic-11 正文 / ChillBitmap 标题 / 面板·按钮·进度条样式 / 48 色板唯一色源） | `scripts/ui/ui_theme.gd` + `scenes/ui/theme/theme.tres`（生成器 `tools/gen_ui_theme.*`） |
| 1.7 | 数据驱动架构（9 个 Resource 类 + JSON 加载器 + 跨表一致性校验） | `resources/*.gd` + `scripts/autoload/config_loader.gd` |
| 1.8 | 存档系统框架（多槽 / 版本 / JSON / `user://` / 损坏保护 / 备份轮转） | `scripts/autoload/save_manager.gd` |
| 1.9 | Windows 导出预设 | `export_presets.cfg` |

### 已完成（阶段 2 起步）

| 任务 | 内容 | 落点 |
|---|---|---|
| 2.1 | 玩家角色控制器（8 方向移动 / 闪避 + 无敌帧 / 8 方向朝向 / **武器层三层结构与主副手锚点**） | `scenes/player/player.tscn` + `scripts/player/player_controller.gd` |
| 2.2 | 攻击与技能系统（技能数据表 / 法力池 / 技能控制器：冷却·蓝耗·施放分派 / **普攻假连段**（按住连续挥击）/ 受击靶验证占位 / 战斗渲染预览） | `resources/skill_data.gd` + `data/skills/skills.json` + `scripts/combat/*.gd` + `scenes/combat/damage_dummy.tscn` + `tools/verify_skills.*` + `tools/combat_preview.*` |
| 2.3 | 伤害计算管线（暴击 / 元素 / 减伤，用户拍板口径：CR 5%·CD 150%·上限 75% / 物理+火冰雷毒 5 系 / 护甲·抗性同构减伤 / 减伤顺序） | `resources/damage_result.gd` + `scripts/combat/damage_calc.gd` + `game_constants.gd` 八·八段 + 普攻/技能接入 + `tools/verify_damage.*` |
| 2.4 | 敌人 AI 基类（巡逻 / 追击 / 攻击状态机，数据驱动读 MonsterData；受击契约与 2.2/2.3 对齐；对玩家攻击发 damage_taken 事件） | `scripts/enemies/enemy_base.gd` + `scenes/enemies/enemy_base.tscn` + `game_constants.gd` 八·九段 + `tools/verify_enemy.*` + `tools/enemy_preview.*` |
| 2.5 | 碰撞与命中判定（HitQuery 圆/扇形/矩形几何判定 + 目标半径扩展 get_hit_radius；玩家普攻/技能与敌人攻击统一走几何判定；敌人攻击弧 120° 并尊重闪避无敌帧） | `scripts/combat/hit_query.gd` + `verify_hit` |
| 2.6 | 生命 / 护盾 / 异常状态（HealthComponent：减伤链 / 护盾吸收 / 毒燃 dot / 冰减速 / 死亡广播；敌人攻击真正扣玩家血并附加元素异常；HUD 16px + 怪物头顶 8px 血条） | `scripts/combat/health_component.gd` + `scripts/ui/health_bar.gd` `world_health_bar.gd` + `verify_health` |
| 2.7 | 掉落与拾取系统（LootRoller 权重 roll：触发 / 件数 / 类型 / 稀有度难度修正 / 底材过滤；LootDrop 地面物件 + 稀有度光柱 + 自动拾取；敌人死亡掉落，生命组件收编） | `scripts/loot/*` + `scenes/loot/loot_drop.tscn` + `scripts/combat/health_component.gd`（收编）+ `scripts/enemies/enemy_base.gd`（掉落接入） |
| 2.8 | 打击感打磨（JuiceFX 监听 damage_dealt / unit_died → 伤害飘字 + 受击闪白 + 死亡像素粒子 / 扩散环 + 震屏 + 暴击顿帧；敌人攻击命中补发 damage_dealt 统一事件链；音效留阶段 6 音频资产就绪） | `scripts/juice/*` + `scenes/juice/*` + `project.godot`（JuiceFX Autoload）+ `enemy_base.gd`（命中事件 + 死亡色）+ `player_controller.gd`（flash）+ `tools/verify_juice.*` + `tools/juice_preview.*` |

### 已完成（阶段 3 起步）

| 任务 | 内容 | 落点 |
|---|---|---|
| 3.1 | 装备数据结构（部位 / 等级需求 / 基础属性 / 词缀列表；**词缀池表落地**：10 池显式词缀 ID 列表 + 加载器跨表校验装备池引用 / 池内词缀引用 + 池查询接口；GDD 3.2.3 前后缀上限不变式） | `data/affix_pools/pools.json` + `scripts/autoload/config_loader.gd`（词缀池加载与校验）+ `game_constants.gd`（RARITY_PREFIX_LIMIT / RARITY_SUFFIX_LIMIT，阶段 1 已落）+ `main.gd` 自检 +3 → 55 项 + `tools/verify_equipment.*` |
| 3.2 | 词缀生成器（AffixRoller：稀有度条数区间 → GDD 3.2.3 前后缀拆分 → 装备词缀池候选（部位 / 稀有度过滤）→ 权重 + 互斥组 pick → Base × iLvl 缩放 × 品质系数（5 档权重 35/30/20/10/5）→ 紫+ 概率强化词缀 ×1.5 → 红装神话独立槽；掉落即定型，拾取直接入包带词缀） | `scripts/loot/affix_roller.gd` + `loot_roller.gd`（装备条目带 instance）+ `player_controller.gd`（pickup 存 instance）+ `main.gd` 自检 56 项 + `tools/verify_affix_roller.*` + `tools/equipment_preview.*` |
| 3.3 | 稀有度与掉落权重表（**GDD 6.1 权威逐位校验**：三表 × 8 档与文档一致 + 权重和 100 + 难度修正规则（NM1 红清零 / NM2 红 ×1.5 白 ×0.85 黄 ×1.15 紫橙 ×1.30 绿 ×1.10 彩不变 / 越级紫橙红 ×0.5）+ **一局节奏仿真**（3000 局：150 普通 + 5 精英 + 1 BOSS → 橙 ≈ 0.186 命中，黄/紫/绿/红/彩全部落 GDD 期望容差；**150 为 v1.5 历史基准，v1.8 现行基准 269 杂兵 + 8–10 精英，见 GDD 6.1 已注「基准过期」**）+ 底材联动抽查；**修复 2.7 遗留类型占比 bug**（装备概率 ~1.3% → 55/80/90%）） | `main.gd` 自检 58 项 + `tools/verify_loot_tables.*`（仿真无渲染预览） |
| 3.4 | 装备品质 / 升级 / 洗练（**GDD 0.3 节 3.4 + 6.5**：强化 +1~+12（橙/绿/彩 +10、红 +12，每级 +5% 基础属性）、成功率表（+1~+5 100% / +6 80% / +8 50% / +9 40% / +10 25% / +12 15%）、失败惩罚（+9 起降级；红 +11/+12 耗神话结晶）、成本（魔石 106 明细 v1.8、金币 100×1.35^k、洗练 500×1.15^n + 1 秘银尘）；洗练保类型重掷数值（can_reroll=false 保留）） | `scripts/forge/forge_controller.gd` + `game_constants.gd` 八·十四段 + `main.gd` 自检 60 项 + `tools/verify_forge.*` + `tools/forge_preview.*` |
| 3.5 | 传奇特效系统（**GDD 0.3 节 3.5 范式 = 触发条件 + 效果 + 冷却/上限 三要素**：池 **31 件**（5 件 GDD 示例 + 2 件神话示例 + 24 件扩展，遗留项 #3 达标 ≥30）；触发 10 类 / 效果 12 类白名单；**掉落即定型**——橙+ 必挂 1 条（模板绑定或同部位池抽取，红另含神话词缀）；`LegendaryEffectSystem` 纯静态触发结算（概率 / 叠层引爆 / 冷却 / 阈值，返回结果由调用方执行）；同部位特效池供 3.4 橙装重铸抽取） | `data/legendary_effects/legendary_effects.json` + `scripts/legendary/legendary_effect_system.gd` + `config_loader.gd`（加载 + 范式校验）+ `affix_roller.gd`（橙+ 装配）+ `main.gd` 自检 63 项 + `tools/verify_legendary_effects.*` + `tools/legendary_preview.*` |
| 3.6 | 背包 / 仓库 / 整理 / 排序（背包 8×5 = 40 格、仓库 8×10 = 80 格，一格一件；增删 / 交换 / 按 instance_id 移除；**整理**压缩空位保持相对顺序；**排序**按 稀有度 / 部位 / iLvl / 名称 升降序（空位恒在尾部）；**仓库转移**满仓保护不丢物品；`InventoryPanel` 网格 UI（48×48 格、稀有度边框色、tooltip、选中详情、整理 / 排序 / 仓库切换工具栏）） | `scripts/inventory/inventory.gd` + `scripts/ui/inventory_panel.gd` + `main.gd` 自检 64 项 + `tools/verify_inventory.*` + `tools/inventory_preview.*` |
| 3.7 | 装备对比 UI（**词缀 stat_key 统计键补齐**（33 词缀映射到玩家属性键，3.9 属性结算的地基）；`EquipmentCompare` 纯静态：底材基础（iLvl + 强化）× 词缀归并求和 → 新旧对比（升 / 降 / 平 + 差值，特殊机制词缀如回响之刃隔离不参与数值）；`ComparePanel` 两列对比表（绿升红降灰平、汇总行）） | `resources/affix_data.gd`（+stat_key 校验）+ `data/affixes/*.json`（+stat_key）+ `scripts/ui/equipment_compare.gd` `compare_panel.gd` + `main.gd` 自检 65 项 + `tools/verify_equipment_compare.*` + `tools/compare_preview.*` |
| 3.8 | 分解 / 合成 / 材料回收（**分解产出 = GDD 5.3 权威表**：白 0 / 蓝 1 尘 / 黄 3 尘 / 紫 1 精粹+5 尘 / 橙 3 精粹 / 绿 4 精粹 / 红 6 精粹+1 结晶 / **彩不可分解**；**合成配方 4 档（工程侧默认，GDD 未给）**：蓝 10 尘 → 蓝装、黄 30 尘+1 精粹 → 黄装、紫 3 精粹 → 紫装、橙 6 精粹+1 结晶 → 橙装（掉落即定型含特效）；`MaterialBag` 统一钱包（金币 / 魔石 / 秘银尘 / 精粹 / 结晶，spend 原子性）；端到端分解→合成→再分解闭环） | `scripts/forge/material_bag.gd` `dismantle_controller.gd` `craft_controller.gd` + `main.gd` 自检 66 项 + `tools/verify_dismantle.*` + `tools/dismantle_preview.*` |
| 3.9 | 属性结算系统（**GDD 6.2 裸装成长公式** Base(L) = Base1 × (1+g)^(L-1)：HP 150×1.11 / AD 12×1.10 / ARM 6×1.10，L1–L20 逐级断言；`StatCalculator` 纯静态：裸装 + 装备（3.7 stat_key 汇总）× Buff → 最终属性——主属性三件套 flat 合并 + pct 乘算 + 神话全属性、暴击 / 攻速 / 抗性 / 资源 / 幸运 / 减耗 / 冷却等直接累加；`stats_recalculated` 信号契约已备） | `scripts/combat/stat_calculator.gd` + `main.gd` 自检 67 项 + `tools/verify_stat_calculator.*` + `tools/stat_preview.*` |
| 3.10 | 套装系统（**3 套 × 6 件 × 2/4/6 档**：霜噬 / 烬途 / 守誓者；`SetSystem` 纯静态：按部位去重计数、档位激活判定、`get_bonus_stats` 数值加成汇总——**自动并入 `StatCalculator.calculate`**（属性结算含套装）、`get_progress` 每套进度；`SetPanel` 6 段进度条 + 档位文案（GDD 0.3 节 3.7：套装徽记位 / 件数徽章接口已备）；effect_id 机制档文案展示（战斗触发逻辑留战斗层）） | `scripts/sets/set_system.gd` + `scripts/ui/set_panel.gd` + `stat_calculator.gd`（套装并入）+ `main.gd` 自检 68 项 + `tools/verify_set_system.*` + `tools/set_preview.*` |
| 3.11 | 红装 / 彩装机制（**GDD 3.4 红装神话词缀重铸**：`MythicRerollController` 重掷神话独立槽数值 / 类型（池当前 1 条，重掷数值），成本神话结晶 ×2，彩装拦截；**GDD 3.2.2 彩装唯一性成长**：`HiddenGrowthController` 按底材 `growth_stat_key` 累积 `growth_value`（百分数），上限底材 `growth_max`（其一 +5% 全属性 / 拾荒者 +15% 移速），**成长加成自动并入 `StatCalculator.calculate`**（全属性走神话乘算 / 移速走直接键）；彩装不可分解（3.8 已拦）不可重铸不可交易；`EquipmentData` +growth 两字段、模板 JSON 已配） | `scripts/items/hidden_growth_controller.gd` + `scripts/forge/mythic_reroll_controller.gd` + `stat_calculator.gd`（成长并入）+ `equipment_data.gd`（+growth）+ `main.gd` 自检 69 项 + `tools/verify_mythic_hidden.*` + `tools/mythic_preview.*` |
| 4.1 | 局内等级与经验（**GDD 0.4 节 4.1**：进关局内 1 级、击杀获得本局经验、上限 10 级、每级触发三选一、出关清零；**经验曲线为工程侧默认**（GDD 未给局内公式）：`XP_ToNext(L) = 20 × L^1.4`，1→10 级总需 ≈1,848 XP，单关 150 怪 × 12 XP 可升满；**「150 怪」为 v1.5 历史基准，v1.8 现行基准 269 杂兵 + 8–10 精英（GDD 6.1 已注过期）**） | `scripts/run/run_progression.gd` + `main.gd` 自检 70 项 + `tools/verify_run_growth.*` + `tools/run_growth_preview.*` |
| 4.2 | 局内技能 / 符文三选一（**GDD 0.4 节 4.2/4.4**：15 选池 = 攻击 6 / 防御 5 / 资源 4（狂怒/疾风/致命/撕裂/元素附魔/破甲/坚韧/铁壁/再生/荆棘/护盾/迅捷/贪婪/幸运/汲取），每升 1 级不重复抽 3；**30% 上限分配**：攻击/生命 +30% 硬上限、攻速/暴击率 +20%，达上限该类选项自动移除切功能性选项（移速/拾取/金币不占上限）；`ChoicePanel` 三色选项卡） | `scripts/run/rune_pool.gd` + `scripts/ui/choice_panel.gd` + `main.gd` 自检 70 项 + `tools/verify_run_growth.*` + `tools/run_growth_preview.*` |
| 4.3 | 临时增益 / Buff 系统（**GDD 0.4 节 4.3/4.4**：三选一 / 祭坛二选一（狂怒祭坛 +20% 攻 / 疾风祭坛 +15% 攻速）/ 连杀（3 秒窗口、每 20 连杀 +3% 攻击上限 +15%）→ 统一 `RunBuffSystem` 转 `StatCalculator` buffs 格式并入结算（pct 加算）；`StatCalculator` FINAL_KEYS 扩充 5 键：armor_pierce / life_steal / damage_taken / regen_pct_hp / shield_pct_hp） | `scripts/run/run_buff_system.gd` + `stat_calculator.gd`（+5 键）+ `main.gd` 自检 70 项 + `tools/verify_run_growth.*` + `tools/run_growth_preview.*` |
| 4.4 | 关卡内资源与商店（**工程侧默认，GDD 未细化**：每关 1 次商店、商品 = 装备 ×2 + 药水 + 材料；货币 = 本局金币（D2 方案 B 结算扣 50%）；定价 = 稀有度基准 × (1 + 0.5 × iLvl)（白 10 / 蓝 25 / 黄 60 / 紫 150 / 橙 400 / 绿 350 / 红 800 / 彩 1000）；`RunShop.buy` 原子扣款（金币不足 / 背包满不扣款）；`ShopPanel` 商品列表 + 购买按钮） | `scripts/run/run_shop.gd` + `scripts/ui/shop_panel.gd` + `main.gd` 自检 71 项 + `tools/verify_shop.*` + `tools/shop_preview.*` |
| 4.5 | 本局结算（**D2 方案 B（已确认）**：保留等级 / 经验 / 已入包装备 / 已通关解锁；丢失本局未入包掉落；金币材料结算扣 50%；每关 1 次原地复活；`RunResult.finalize` 静态结算单（存活标记 + 击杀 / 局内等级 / 连杀峰值 + 金币材料扣半快照 + 入包保留 / 未入包丢失计数 + 稀有掉落计数）；**评分（工程侧默认）**：存活 500 + 击杀 ×10 + 等级 ×50 + 稀有掉落 ×100 + 连杀 ×2 → 评级 D/C/B/A/S（400/700/1000/1500 阈值）；`ResultPanel` 结算面板 + 大字评级） | `scripts/run/run_result.gd` + `scripts/ui/result_panel.gd` + `main.gd` 自检 72 项 + `tools/verify_run_result.*` + `tools/result_preview.*` |
| 5.1 | 账号 / 巅峰等级（**GDD 5.1 v1.8**：`180 × L^1.6`，等级 1–60；累计口径 Σ₁^(L-1)；L10=7166 / L20=21723 / L30=41559 / L45=79508 / L60=125984；每 2 级 +1 天赋点 → 满级 30 点；`AccountLevel.add_xp` 自动连升 + 回调） | `scripts/account/account_level.gd` + `main.gd` 自检 78 项（新增 6） + `tools/verify_account.*` + `tools/account_preview.*` |
| 5.2 | 天赋树（**GDD 5.2**：3 大分支 武力 / 守护 / 秘法，每分支 20 节点 = 小 15（+2%）+ 大 5（+8% 或机制）；分支解锁 L1 / L15 / L30；满级 30 点最多点满半棵树；`TalentTree.learn` 校验未解锁 / 重复 / 点数不足） | `scripts/account/talent_tree.gd` |
| 5.3 | 解锁系统（**GDD 5.4**：关卡 L2–L20 顺序通关；梦魇 I–V 全 20 关后逐层递进（简化口径每再通 5 关 +1 层）；天赋分支 L15 / L30；仓库页 2/3/4 累计通关 5/10/15 关） | `scripts/account/unlock_system.gd` |
| 5.4 | 材料与锻造 / 附魔（**GDD 5.3 材料表**：魔石=强化（3.4 已做）、秘银尘=词缀洗练、传说精粹=橙装特效重铸、神话结晶=红装+11/+12 与神话词缀重铸（3.11 已做）；**附魔（工程侧默认）**：`EnchantController.try_reroll_affix` 重掷首条普通词缀（秘银尘 ×3，含 iLvl 缩放）、`try_reforge_effect` 同部位池重铸橙特效（精粹 ×2）） | `scripts/forge/enchant_controller.gd` |
| 5.5 | 永久属性提升（**GDD 5.5 项名；宝石为工程侧默认**：4 档（碎裂/普通/完美/无瑕 ×1/2/4/8）× 3 色（红=攻击 / 蓝=护甲 / 绿=生命 +3%）；槽位 = 白 0 / 蓝黄 1 / 紫橙+ 2；镶嵌/拆卸免费、替换覆盖；`GemSystem` 加成并入结算） | `scripts/items/gem_system.gd` + `resources/equipment_instance.gd`（+gems 字段序列化） |
| 5.6 | 声望 / 成就（**GDD 5.5**：章节声望击杀/通关累积，每 1 级 +1% 经验 +1% 金币，上限 10 级/章；成就 50 个暂定 → 工程侧 `data/achievements.json` 20 个起步，类型 kills / clears / gold_earned / account_level / mythic / hidden / set / streak / run_score / rerolls / talent_nodes，奖励**纯外观**（武器光效 / 角色配色）不入战力） | `scripts/account/chapter_reputation.gd` + `scripts/account/achievement_system.gd` + `data/achievements.json` |
| 6.1 | 关卡 / 地图（**GDD 6.1：手工 + 程序化生成；20 关 × 5 难度层级**。工程侧：数据扩至三章 20 关（chapter1 1–6 / chapter2 7–13 / chapter3 14–20，顺序解锁链完整，每章末 BOSS 关）；`LevelGenerator` 拒绝采样房间 + 走廊连接，种子化布局输出 cells / 玩家出生 / 怪物投放（权重 + 距出生 ≥6 格）/ 精英锚点 / BOSS 远端锚点 / 拾取点） | `scripts/run/level_generator.gd` + `data/levels/chapter2.json` + `data/levels/chapter3.json` + `resources/level_data.gd`（+elite_count / boss_id / layout 字段）+ `main.gd` 自检 80 项（新增 2）+ `tools/verify_level_gen.*` + `tools/level_preview.*` |
| 6.2 | 怪物扩充 / 精英词缀怪（**GDD 6.2：怪物种类与精英 / 词缀怪；8 档掉落**。工程侧：怪物 8→16 种（新增孢蘑菇 / 暗影猎犬 / 烬石魔像 / 炼狱小鬼 / 灰烬猎犬 / 焰术信徒（精英）/ 冰封尸骸 / 寒霜幽魂（精英），三章等级带全覆盖，数值爬坡 HP×1.9 / ×1.75 与护甲）；`AffixController` 纯静态词缀池 6 条（急速移速×1.35 / 吸血回复 20% / 爆炸 40px·80% / 回响 30% 二连击 / 荆棘反弹 15% / 闪现 6 秒），权重随机 1–2 条不重复；`EnemyBase` 集成词缀钩子（移速 / 闪现 / 吸血 / 回响 / 荆棘 / 爆炸）） | `data/monsters/monsters.json`（8→16）+ `scripts/enemies/affix_controller.gd` + `scripts/enemies/enemy_base.gd`（词缀钩子）+ `main.gd` 自检 83 项（新增 3）+ `tools/verify_monsters62.*` + `tools/monsters_preview.*` |
| 6.3 | BOSS 设计与机制（**GDD 6.3：BOSS 做长 TTK 90–120s / 掉落 100% 掉 2–4 件**。工程侧：`data/bosses/bosses.json` 2 个章末 BOSS（骸骨暴君 L6-7 骨系 / 熔心之主 L19-20 火系）4 阶段血量门（75% / 50% / 25%），阶段技能逐级解锁（基础 → 召唤杂兵 → 范围 AoE → 狂暴），召唤池指向怪物表，狂暴攻速 ×0.6 / 伤害 ×1.3；`BossPhaseController` 纯静态阶段计算 + `EnemyBase` 集成（血量阈值阶段切换 / 召唤实例化 / AoE / 广播 `boss_phase_changed`）） | `data/bosses/bosses.json` + `scripts/enemies/boss_phase_controller.gd` + `scripts/enemies/enemy_base.gd`（BOSS 阶段钩子）+ `scripts/autoload/event_bus.gd`（+boss_phase_changed）+ `main.gd` 自检 86 项（新增 3）+ `tools/verify_boss63.*` + `tools/boss_preview.*` |
| 6.4 | 技能库扩充（**GDD 6.6：DPS = AD × 暴击 × 攻速 × SkillMult；技能形态单/范围/位移**。工程侧：技能 3→8（裂斩/旋刃/突进出战 + 冰霜新星 AoE 冰 / 火球术 单体火 / 闪电链 单体雷 / 毒云 AoE 毒 / 暗影步 位移影 5 个备选 slot 0，覆盖三形态 + 六元素）；`SkillData` slot 放宽 0–3（0 = 备选不入出战栏）；`SkillController` 只加载 slot 1–3 出战技能；元素表扩至 6 系（+影）） | `data/skills/skills.json`（3→8）+ `resources/skill_data.gd`（slot 0–3）+ `scripts/combat/skill_controller.gd`（备选不入栏）+ `scripts/core/game_constants.gd`（+ELEMENT_SHADOW）+ `main.gd` 自检 88 项（新增 2）+ `tools/verify_skills.gd`（45→49）+ `tools/skills_preview.*` |
| 6.5 | 装备库填充（**GDD 6.2：装备词缀体系 — 白 0 词 / 蓝 1–2 / 黄 3–4 / 紫 5–6 / 橙 7–8 / 红 4–5 神话；底材覆盖武器 6 形态 + 防具 5 部位 + 饰品 3 槽**。工程侧：装备 42→62（weapons 8→14：+烈焰剑/血斧/冰川锤/淬毒匕首/风暴法杖/灵风长弓；armor 8→14：+石像头盔/烬织胸甲/冰织手套/守望腿甲/疾风靴/泰坦王冠；jewelry 8→16：+余烬护符/霜戒/雷暴之戒/影纱吊坠/嗜血之戒/烈日圣印/回响之戒/守护者勋章）；等级带覆盖三章（1-6 / 7-13 / 14-20），稀有度梯级（普通→传奇），掉落权重按稀有度递减；套装体系 3×6 不破坏） | `data/equipment/weapons.json`+`armor.json`+`jewelry.json`（8+8+8→14+14+16）+ `main.gd` 自检 90 项（新增 2）+ `tools/verify_equipment65.*`（14 项）+ `tools/equip_preview.*` |
| 6.6 | 音效/音乐（**GDD 6.7 音效：命中 / 死亡 / 拾取 / 升级反馈；纯本地单机**。工程侧：程序化合成 8 条占位音效 `data/audio/*.wav`（22050Hz 16-bit mono，Python wave 合成：打击/暴击/死亡/金币/装备/升级/BOSS 阶段/UI 点击），`AudioManager` 纯静态播放管线（播放即焚、零 autoload），钩子接入受击/死亡/拾取/升级/BOSS 阶段；真音频可直接替换 wav 文件） | `data/audio/*.wav`（8 条，新）+ `scripts/audio/audio_manager.gd`（新 class_name）+ `scripts/enemies/enemy_base.gd`+`scripts/player/player_controller.gd`+`scripts/run/run_progression.gd`（播放钩子）+ `main.gd` 自检 92 项（新增 2）+ `tools/verify_audio66.*`（9 项）+ `tools/audio_preview.*` |
| 7.1 | 主菜单 / 角色选择（**P0 界面**。工程侧：`MainMenuPanel` 主菜单（标题 + 开始/设置/退出 + 账号概览 Lv/金币/魔石/声望加成），纯单机单角色战士，回调注入跳转） | `scripts/ui/main_menu_panel.gd`（新 class_name）+ `main.gd` 自检 94 项（新增 2）+ `tools/verify_ui71.*`（24 项）+ `tools/ui_preview.*` |
| 7.2 | 角色属性面板（**P0 界面**。工程侧：`StatPanel` 属性总表——8 基础（攻击/生命/护甲/暴击率/暴伤/攻速/移速/吸血）+ 4 元素抗性 + 6 元素伤害，数据源 StatCalculator） | `scripts/ui/stat_panel.gd`（新 class_name） |
| 7.3 | 背包 / 装备界面（**P0 界面**。工程侧：`EquipPanel` 10 槽装备栏（主/副手/头/胸/手/腿/靴/护符/戒A/戒B）+ 选中详情 + 穿/脱回调；背包网格复用 3.6 InventoryPanel） | `scripts/ui/equip_panel.gd`（新 class_name） |
| 7.4 | 技能树 / 天赋界面（**P1 界面**。工程侧：`TalentPanel` 三分支（战争/秘法/影行）卡片 + 节点状态（已点 ✓ / 可点 / 未解锁）+ 可用点数 + learn 回调；数据源 TalentTree） | `scripts/ui/talent_panel.gd`（新 class_name） |
| 7.5 | 锻造 / 合成界面（**P1 界面**。工程侧：`ForgePanel` 物品行（费用/材料不足禁用/锻造/重铸）+ 结果反馈；数据源 ForgeController） | `scripts/ui/forge_panel.gd`（新 class_name） |
| 7.6 | 结算 / 奖励界面（**P0 界面**。工程侧：`ResultPanel` 增强——逐项奖励清单（前 6 件已入包装备 + 超出计数）+ 返回大厅/再来一局按钮（回调注入），结算单本体 4.5 已有） | `scripts/ui/result_panel.gd`（改：+奖励明细 + 按钮） |
| 7.7 | 设置界面（**P1 界面**。工程侧：`SettingsPanel` 画质（垂直同步/全屏）+ 音量（slider → AudioServer）+ 按键（10 动作列表 + 单项/全部重置 → InputRemapper）；设置持久化已并入 8.2） | `scripts/ui/settings_panel.gd`（新 class_name）+ `scripts/core/settings_store.gd`（8.2 新 class_name） |
| 8.1 | 完整存档（局内 + 局外进度，**P0 存档模块**。工程侧：`SaveData` 全字段序列化（局外：账号/经验/天赋/金币/材料/背包/装备/仓库/解锁/声望/成就/统计/设置；局内：current_level_id / current_difficulty_tier；15 类字段矩阵），`SaveManager` 槽位/备份/损坏隔离已有；新增完整闭环实测） | `main.gd` 自检 96 项（新增 2）+ `tools/verify_save81.*`（15 项）+ `tools/save_preview.*` |
| 8.2 | 设置持久化（**P1 设置模块**。工程侧：`SettingsStore` 独立 `user://settings.json`（换档不丢设置）——默认值 + 类型白名单校验回退 + 非法 JSON 隔离 + 应用联动（音量→AudioServer / vsync/全屏→DisplayServer / 按键→InputRemapper 回放）；`SettingsPanel` 改读 SettingsStore 初始值 + 变更即落盘） | `scripts/core/settings_store.gd`（新 class_name）+ `scripts/ui/settings_panel.gd`（改）+ `main.gd` 自检 98 项（新增 2）+ `tools/verify_settings82.*`（12 项） |
| 8.3 | 性能优化（**P1 优化报告**。工程侧：`ObjectPool` 通用对象池（acquire/release/容量上限/池满兜底/复用率统计）+ `LevelView` 地图批处理渲染（单个 CanvasItem _draw 承载全部 tile，逐格 draw_rect，draw call ≈ 1–2，替代每格一个 ColorRect）；高频对象接入池的接口已就绪） | `scripts/core/object_pool.gd`（新 class_name）+ `scripts/run/level_view.gd`（新 class_name）+ `main.gd` 自检 100 项（新增 2）+ `tools/verify_perf83.*`（10 项）+ `tools/perf_preview.*` |
| 8.4 | 平衡性调优（**P1 平衡报告**。工程侧：数值仿真 `verify_balance84`——怪物 HP 100.7×1.284^(L-1) / DMG 5.61×1.218^(L-1) × 难度 1.08^n / 1.23^n（D9 已锁定）；玩家复合成长调优为 DPS 20×1.30^L×1.25 / MaxHP 500×1.06^L，仿真断言 8 项全过：TTK ∈ [2.4, 4.2]s 不海绵化 / 难度爬坡单调 / 梦魇 III-V 承伤 <10s 可被秒 / 普通前 5 关 >12s 不猝死 / 20 关成长可见） | `main.gd` 自检 102 项（新增 2）+ `tools/verify_balance84.*`（8 项）+ `tools/balance_preview.*` |
| 8.5 | Bug 修复与回归测试（**P1 测试报告**。工程侧：全量回归 **36 / 36 脚本**全绿零告警；新增 `verify_fix85` 回归红线复核——历史修复点抽查 8 项（存档槽位边界 / 字段矩阵 / 设置类型白名单 / 默认值镜像 / 对象池复用零泄漏 / LevelView Dictionary+障碍格兼容 / 平衡 TTK 红线 / 数据表锚点）全过） | `main.gd` 自检 104 项（新增 2）+ `tools/verify_fix85.*`（8 项） |
| 9.3 | 崩溃与异常处理（**P1 稳定性补丁**。工程侧：`GameLog` 日志落盘 user://logs/game.log（时间戳 + 2MB 轮转保留 7 份 + 尾部读取）；main.gd 启动记录引擎/模式；修复窗口化启动 2 个真实 Bug——① AudioManager 树忙时序（main._ready 自检触发音效时同步 add_child 失败 → deferred add_child + ready 触发 play）② main.gd `%g` 格式化错误（GDScript 不支持 %g → %d）；存档容错（备份回滚/损坏隔离）既有机制抽查通过） | `scripts/core/game_log.gd`（新 class_name）+ `scripts/audio/audio_manager.gd`（改）+ `main.gd`（改 + 自检 106 项）+ `tools/verify_fix93.*`（6 项） |
| 9.1 | 本地打包导出（**P1 纯本地自玩**。工程侧：主场景 + `export_presets.cfg`（Windows Desktop / x86_64 / embed_pck=true / 单文件 `build/七傳說.exe` 110MB）；导出模板 4.7.2.stable 下载安装完成（GitHub release 1.22GB，gh-proxy 不可用 → 直连 + curl 断点续传）；`--export-release` 导出成功；导出 exe 无头自检 **108/108**、窗口化冒烟运行 8 秒正常 + 日志落盘） | `export_presets.cfg`（新）+ `tools/verify_export91.*`（5 项）+ `build/七傳說.exe`（产物，git 忽略体积不入库）+ `main.gd`（改 + 自检 108 项） |
| 9.2 | 本地完整流程自测（**P1**。自动化部分 `verify_play92` **7/7**：新档 → 刷怪掉落 → 换装变强（攻击 12→25）→ 存档 → 重开加载全字段一致；导出 exe 双击试玩部分**待玩家实操**补充手感反馈 → 进入 9.4 迭代） | `tools/verify_play92.*`（7 项） |

**已与 GDD v1.3 / 美术规范 0.7 v1.3–v1.4 对齐**：
稀有度 8 档体系（6 线性 + 套装正交 + 彩蛋）、8 档掉落权重（含红装梦魇 II 门槛、绿 ×1.10、红 ×1.50）、
套装 6 件套 + 2/4/6 档加成（3 组套装全部 18 件底材已录入）、神话红装 +12 强化上限与金色双层外框、
彩蛋 6 色渐变（`PRISMATIC_GRADIENT`）与可成长字段。

### 已实测验证（Godot 4.7.2，2026-09-16）

在本机用 **Godot 4.7.2.stable** 实跑，非静态检查：

> ⚠️ **关卡数值 = POC 值注记（2026-09-18）**
> 本节及第 5 节中所有涉及「关卡 20」「关卡数值 / 内容量」的行，其**关内数值一律为 demo 期 POC 值，不是 D5（单局 14–21 分钟）终值**。
> 现 20 关 `total_monster_budget` 合计 **1174** / 均值 **58.7** / 区间 **40–85**，与 GDD v1.8 定稿 **269/关（区间 192–347）差 4.58 倍**
> ⇒ 按 sim 公式估算单局仅 **≈3–5 分钟**（仅为 D5 下限 14 分钟的约 1/3），**拿这版 demo 测「单局时长」会失真**。
> 回填时机在 **AoE 实测之后**（归口任务 **11.9**）；且 **269 本身亦非终值** —— 它出自 `sim-report §10.5.6`，建立在 **AoE = 2.0 设计基准**上，
> 而 §10.5.7 自承 AoE 未实测，且「杂兵数 ∝ AoE」（§10.5.4）。详见第 9 节「已知待办」#4。

| 项 | 命令 | 结果 |
|---|---|---|
| 编辑器导入 | `--headless --editor --quit` | **0 个 ERROR**，11 个 `class_name` 全部注册（含 UITheme） |
| 骨架自检 | `--headless -- --verify` | **111 / 111 通过**，退出码 0（含数值锚点 + 48 色板唯一色源 + 技能表 + 伤害管线常量 + AI 参数 + 怪物表 + 物理层 + 攻击弧 + 生命异常锚点 + 词缀池表 + 生成器抽查 + 掉落表锚点 + 锻造锚点 + 传奇特效池 + 背包 + 装备对比 + 分解合成 + 属性结算 + 套装 + 红装彩装 + 局内成长 + 关卡商店 + 本局结算 + 账号等级 + 天赋树 + 解锁系统 + 附魔成本 + 宝石 + 声望成就 + 关卡 20 关 + 地图生成器 + 怪物 16 种 + 精英词缀池 + BOSS 机制 2 个 + BOSS 掉落 + 技能库 8 个 + 备选形态元素 + 装备库 62 件 + 三章等级带 + 音效 8 条 + 音效文件加载 + **特效贴图 7 张（表已加载 / 全部可加载 / 帧数与尺寸自洽）** + 7 面板可实例化 + 回调契约 + 存档字段矩阵 + 局内进度 + 设置默认值 + 类型白名单 + 对象池复用 + LevelView 批处理 + 平衡仿真 TTK + 梦魇承伤 + 数据表锚点 + 槽位边界 + 日志可写 + 日志尾部自检 + 主场景存在 + 导出预设） |
| 存档系统实测 | `res://tools/verify_save.tscn` | **26 / 26 通过**，退出码 0 |
| 玩家 + 输入系统实测 | `res://tools/verify_player.tscn` | **33 / 33 通过**，退出码 0 |
| 攻击与技能系统实测 | `res://tools/verify_skills.tscn` | **45 / 45 通过**，退出码 0（技能表 / 法力 / 冷却 / 假连段 / 技能效果 / 回归；固定随机种子） |
| 伤害计算管线实测 | `res://tools/verify_damage.tscn` | **40 / 40 通过**，退出码 0（基础 / 暴击 / 元素 / 减伤 / 接入回归 / GDD 锚点 6 段） |
| 敌人 AI 基类实测 | `res://tools/verify_enemy.tscn` | **34 / 34 通过**，退出码 0（数据 / 状态机 / 移动 / 受击契约 / 攻击） |
| 碰撞与命中判定实测 | `res://tools/verify_hit.tscn` | **25 / 25 通过**，退出码 0（circle / arc / rect / 玩家接入 / 敌人攻击弧 / 无敌帧） |
| 生命 / 异常状态实测 | `res://tools/verify_health.tscn` | **25 / 25 通过**，退出码 0（属性 / 减伤链 / 护盾 / 异常 / 死亡 / 敌人接入） |
| 掉落与拾取实测 | `res://tools/verify_loot.tscn` | **20 / 20 通过**，退出码 0（掉落表 / roll / 稀有度分布 / 难度修正 / 底材过滤 / 死亡掉落+拾取 / 收编回归 7 段） |
| 打击感实测 | `res://tools/verify_juice.tscn` | **18 / 18 通过**，退出码 0（参数 / 飘字 / 生命周期 / 顿帧 / 震屏 / 死亡粒子 / 闪白 7 段） |
| 装备数据结构实测 | `res://tools/verify_equipment.tscn` | **27 / 27 通过**，退出码 0（底材 / 词缀 / 词缀池 / 条数表不变式 / 实例化 / 池查询 6 段） |
| 词缀生成器实测 | `res://tools/verify_affix_roller.tscn` | **24 / 24 通过**，退出码 0（参数 / 条数拆分 / 互斥权重 / 数值 / 强化词缀 / 神话槽 / 掉落接入 7 段） |
| 掉落权重表实测 | `res://tools/verify_loot_tables.tscn` | **18 / 18 通过**，退出码 0（权威表 / 权重和 / 难度修正 / 一局节奏仿真 3000 局 / 底材联动 5 段） |
| 锻造 / 洗练实测 | `res://tools/verify_forge.tscn` | **22 / 22 通过**，退出码 0（成本表 / 成功率 / 强化结算 / 属性 / 红装 +11/+12 / 洗练 6 段） |
| 传奇特效实测 | `res://tools/verify_legendary_effects.tscn` | **26 / 26 通过**，退出码 0（数据 31 件 / 类型白名单 / 装配 / 触发 / 效果结算 / 部位池 6 段） |
| 背包 / 仓库实测 | `res://tools/verify_inventory.tscn` | **28 / 28 通过**，退出码 0（容量 / 满仓 / 移动交换 / 整理 / 排序 / 仓库转移 / 面板接入 7 段） |
| 装备对比实测 | `res://tools/verify_equipment_compare.tscn` | **21 / 21 通过**，退出码 0（stat_key / 汇总 / 对比三态 / 穿戴新件 / 安全 / 特殊键 / 面板 7 段） |
| 分解 / 合成实测 | `res://tools/verify_dismantle.tscn` | **33 / 33 通过**，退出码 0（分解产出 / 材料包 / 配方 / 合成成功 / 合成失败 / 合成循环 / 端到端 7 段） |
| 属性结算实测 | `res://tools/verify_stat_calculator.tscn` | **26 / 26 通过**，退出码 0（裸装成长 / 装备聚合 / flat+pct 结算 / 神话全属性 / Buff 叠加 / 直接累加 / 满装估算 + 套装并入 7 段） |
| 套装系统实测 | `res://tools/verify_set_system.tscn` | **25 / 25 通过**，退出码 0（数据 / 计数去重 / 档位 / 加成汇总 / 进度 / 面板 / 边界 7 段） |
| 红装彩装实测 | `res://tools/verify_mythic_hidden.tscn` | **27 / 27 通过**，退出码 0（数据 / 神话槽 / 重铸 / 成长 / 并入结算 / 彩装保护 / 边界 7 段） |
| 局内成长实测 | `res://tools/verify_run_growth.tscn` | **23 / 23 通过**，退出码 0（局内等级 / 选项池 / 三选一 / 上限移除 / Buff 并入 / 连杀 6 段） |
| 关卡商店实测 | `res://tools/verify_shop.tscn` | **16 / 16 通过**，退出码 0（生成 / 定价 / 购买 / 失败 / 稀有度分布 5 段） |
| 本局结算实测 | `res://tools/verify_run_result.tscn` | **14 / 14 通过**，退出码 0（存活 / 死亡 / 掉落 / 评分 / 评级 5 段） |
| 局外成长实测 | `res://tools/verify_account.tscn` | **45 / 45 通过**，退出码 0（账号等级 / 天赋树 / 加成 / 解锁 / 洗练 / 宝石 / 声望 / 成就 / 并入 9 段） |
| 关卡地图实测 | `res://tools/verify_level_gen.tscn` | **73 / 73 通过**，退出码 0（关卡数据 / 解锁链 / 布局 / 怪物分布 / 精英 BOSS / 确定性 / 目标可达性 / **手绘地图** 8 段） |
| 怪物词缀实测 | `res://tools/verify_monsters62.tscn` | **24 / 24 通过**，退出码 0（怪物数据 / 数值爬坡 / 精英 / 词缀池 / 抽取 / 数值 / 并入敌人 7 段） |
| BOSS 机制实测 | `res://tools/verify_boss63.tscn` | **32 / 32 通过**，退出码 0（BOSS 数据 / 阶段判定 / 技能集 / 召唤 / 狂暴 / 掉落 / 集成 7 段） |
| 技能库实测 | `res://tools/verify_skills.tscn` | **49 / 49 通过**，退出码 0（技能表 8 条 / 出战栏位 / 备选形态元素数值 / 法力 / 冷却 / 假连段 / 技能效果 / 回归 8 段） |
| 装备库填充实测 | `res://tools/verify_equipment65.tscn` | **14 / 14 通过**，退出码 0（总量 62 / 三章等级带 / 合法性 / 新增 20 件 / 数值 / 权重 / 槽位套装 7 段） |
| 音效/音乐实测 | `res://tools/verify_audio66.tscn` | **9 / 9 通过**，退出码 0（注册表 / 文件存在 / 流解析 / 播放管线 / 钩子接线 / 音量 6 段） |
| UI/UX 面板实测 | `res://tools/verify_ui71.tscn` | **30 / 30 通过**，退出码 0（主菜单 / 属性 / 装备 / 天赋 / 锻造 / 结算 / 设置 7 段；含 StatPanel↔StatCalculator **键契约**断言） |
| 完整存档实测 | `res://tools/verify_save81.tscn` | **15 / 15 通过**，退出码 0（新建槽位 / 局外全字段 / 局内进度 / 设置字典 / 装备实例回读 / 跨会话模拟 / 清理 6 段） |
| 设置持久化实测 | `res://tools/verify_settings82.tscn` | **12 / 12 通过**，退出码 0（默认值 / 写入读回 / 跨加载保持 / 应用联动 / 类型白名单 / 非法 JSON 隔离 / 清理 5 段） |
| 性能优化实测 | `res://tools/verify_perf83.tscn` | **10 / 10 通过**，退出码 0（池基本盘 / 池满兜底 / 复用率≥90% / 无泄漏 / 单节点承载全图 / 地面墙障碍计数 / 批处理数组完整 5 段） |
| 平衡仿真实测 | `res://tools/verify_balance84.tscn` | **8 / 8 通过**，退出码 0（TTK 区间 / 难度爬坡单调 / 梦魇可被秒 / 新手不猝死 / 成长可见 5 段，输出 20 关×5 难度 TTK/承伤矩阵） |
| 回归红线复核 | `res://tools/verify_fix85.tscn` | **8 / 8 通过**，退出码 0（存档槽位边界 / 字段矩阵 / 设置类型白名单 / 默认值镜像 / 对象池复用零泄漏 / LevelView Dictionary+障碍格 / 平衡 TTK 红线 / 数据表锚点） |
| 稳定性实测 | `res://tools/verify_fix93.tscn` | **25 / 25 通过**，退出码 0（日志落盘 / 追加写 / 轮转实测 / **首建** / 存档损坏回滚 / 清理 / 轮转约定 / **越级惩罚用真实等级** / **击退契约含位移上界**） |
| 导出验证 | `res://tools/verify_export91.tscn` | **5 / 5 通过**，退出码 0（exe 存在 / 体积 ≥60MB 内嵌 / Windows 预设 / embed_pck / 输出路径） |
| 导出 exe 自检 | `build/七傳說.exe --headless -- --verify` | **108 / 108 通过**，退出码 0（与编辑器一致；导出包引擎默认排除 export_presets.cfg → 该项发布态自动通过）<br>ℹ️ 该构建（2026-09-18 17:50）的 PCK 内为 108 项；自检此后增至 111 项（新增特效贴图层），**重新导出即同步** |
| 导出 exe 冒烟 | `build/七傳說.exe` 窗口化 | 运行 8 秒正常（无闪退），`user://logs/game.log` 落盘启动记录 |
| 流程自测 | `res://tools/verify_play92.tscn` | **7 / 7 通过**，退出码 0（新档属性可算 / 刷怪掉落 / 装备实例化 / 换装变强 攻击12→25 / 存档写入 / 重开一致 / 摘要输出） |
| **端到端跑通** | `res://tools/verify_e2e.tscn` | **34 / 34 通过**，退出码 0，**连续 5 次稳定**（主菜单 → 新档 → 据点 → 选关 → 进关卡 → 打怪掉装备 → 拾取进包 → 结算 → 回据点，全程真点按钮 / 真切场景） |
| 据点实测 | `res://tools/verify_hub.tscn` | **42 / 42 通过**，退出码 0（面板开关 / 数据源 / 信号接线 / 选关入口） |
| 集成层验收 | `res://tools/verify_integration.tscn` | **23 / 23 通过**，退出码 0（启动分流 / 主菜单 / 账号概览接口） |
| 关卡渲染预览 | `res://tools/level_scene_preview.tscn` | 1920×1080 截图 `build/level_scene_preview.png`：一屏 30×16.9 tile、相机 2×、HUD 与敌我清晰可辨 |
| UI 框架与主题实测 | `res://tools/verify_ui.tscn` | **34 / 34 通过**，退出码 0（含 theme.tres 产物与项目注册校验） |
| 跨表校验反向测试 | 故意注入坏引用后自检 | **正确报错并返回退出码 1**（证明校验不是空壳） |
| 全量回归 | `python game/tools/run_regression.py` | **51 / 51 通过**，退出码 0，约 94 秒（50 个 `verify_*.tscn` + `self_check`；含开跑前的**全项目解析预检**，见 §5.46） |
| 窗口化冒烟 | `main.tscn` 窗口化 `--quit-after 240` | **stderr 0 行**，退出码 0 |
| 数据表 | — | 装备 **62** / 词缀 **33**（前 9 后 24，stat_key 已补齐）/ **词缀池 10** / **传奇特效 31** / 怪物 **16** / 关卡 **20** / 掉落表 3 / 套装 3（各 6 件 × 2/4/6 档）/ 技能 **8** / **BOSS 机制 2** / **音效 8**（口径与 5.15 节一致）<br>⚠️ **关卡 20 的关内数值为 POC 值，非 D5 终值**（见本节上方注记） |

**实测中抓出并已修复的真实缺陷（本表 A–F 共 6 行）**（静态检查与人工阅读都没发现）：

| # | 缺陷 | 后果 | 修复 |
|---|---|---|---|
| A | `ConfigLoader._load_set_dir()` **定义了但从未被调用** | 3 组套装完全没加载，`sets: 0`；自检又用 `if not set_ids.is_empty()` 静默跳过，双重掩盖 | 在 `load_all()` 中补上调用 |
| B | `ConfigLoader._cross_validate()` **定义了但从未被调用** | 「跨表一致性校验」在运行时从未生效，套装↔底材引用断裂不会报错 | 在全部表加载完成后补上调用 |
| C | `load_all()` 漏了 `sets.clear()` | 重复调用 `load_all()` 时套装残留旧数据 | 补上 |
| D | `SaveManager` 从备份回滚后**不重建主档** | 主档被隔离、只剩备份，而 `slot_exists()` / `get_slot_info()` 只看主档 → **选档界面把槽位显示成「空档」，玩家以为存档丢了**（恢复只做了一半） | 回滚成功后立即把恢复数据写回主档 |
| E | `STAT_DISPLAY_NAMES` 漏了 `all_attributes`（全属性） | 神话词缀「全属性」在角色面板会显示为空标签 | 补上中文名，并把「属性键全部有显示名」纳入自检 |
| F | **`PlayerController` 战斗属性接口**整层是**阶段 2 占位桩** —— 7 个战斗 getter 里**只有 `get_max_hp()` 接了桥**：`get_player_level()` 恒 `1`、`_get_attack_multiplier_from_stats()` 恒 `1.0`、`get_crit_chance()` / `get_crit_damage()` 恒基准常量、`get_attack_speed_multiplier()` 恒 `1.0`、`get_armor()` 按 **1 级**裸装算、`get_resist()` 恒 `0.0` | **「装备驱动刷宝 ARPG」而装备只影响生命上限** —— 攻击 / 暴击 / 暴伤 / 攻速 / 护甲 / 抗性**全不吃装备与局内增益**，核心幻想在实战中不存在；连带 `enemy_base` 的**越级惩罚永远按「玩家 1 级」算**（20 关 level 1–20 ⇒ `ch1_l05` 起一律判越级，账号 60 级亦然）。**严重度高于 A–E** | **11.11**：`PlayerController` 新增 `apply_combat_stats(stats, account_level)`（**注入优先 / 回退基线 / 向后兼容**），`level_scene._apply_account_stats` 注入**完整** `StatCalculator` 结果（不再只写 `max_hp`）。实测：狂怒 **12.00 → 13.44**、3 层 cap 夹到 30 ⇒ **15.60**、账号 42 ⇒ `get_player_level()=42` |

> A、B 属于「死代码」——函数写得很完整，但从没被接上。这类问题**只有真正跑起来才会暴露**，
> 也是本次从「静态检查通过」升级为「引擎实跑通过」的主要收益。

> **F 为何能藏这么久（两条叠加，缺一不可）**：
> ① **`PlayerController` 每个占位桩都留着「阶段 3 接入」的注释** ⇒ 用「**未来会做**」把一个「**现在没有**」的事实伪装成了「**计划中**」。阶段 3（装备 / 词缀 / 强化）与阶段 5（账号 / 天赋 / 宝石 / 套装）都「完成」并通过了各自的验证，但**没有一条流过这层接口**。
> ② **`verify_play92` 的「C. 换装变强」断言的是 `StatCalculator` 的返回字典（数据层）**，不是玩家的实际输出。而任务 9.2 的标题写「换装 → **变强**」、本表上方写「换装变强 攻击 12→25」—— **任何读者都会理解为「人真的变强了」**。**没有任何一条测试问过「换装之后，玩家打出的伤害真的变高了吗」。**
> ⇒ 已追加断言 **H**：装备 / 增益 → **玩家真实接口**（`get_attack_damage()`）的**双向**断言（**上界专门抓「双重计入」**，那是本次重构最易犯的错）；并在 `verify_play92.gd` 头部加显式警告，标注「本脚本只验证数据层」。

> ⚠️ **计数说明**：原标题写「6 个」，但当时表内只有 **A–E 5 行**，属**预存计数错误**（2026-09-18 由 qa-lead 发现）。11.11 补入 F 后为 6 行 —— **数字以表内行数为准，勿用标题反推行数**。

### 已知待办

| 新 # | 原 # | 项 | 归属 |
|---|---|---|---|
| 1 | 11 | `assets/` 下全部为空，图标 / 徽记路径已在 JSON 登记但文件未产出；UI 须对缺失图标**优雅降级** | 阶段 6（designer） |
| 2 | 13 | 副手原型已扩到 4 个（盾 / 法器 / 箭袋 / 副刃），但装备表只有 `shield_tower` 一件副手底材，**法器 / 箭袋 / 副刃三类零条目**（缺口唯一归口「装备库填充」） | 任务 6.5 |
| 3 | 14 | **关卡数据回填**：现 20 关 `total_monster_budget` 合计 **1174** / 均值 **58.7** / 区间 **40–85**，与 GDD v1.8 定稿 **269/关（192–347）差 4.58 倍** ⇒ 单局仅 **≈3–5 分钟**（D5 下限 14 分钟的约 1/3），**拿这版 demo 测「单局时长」会失真**。回填须在 **AoE 实测之后**（见 #10 / 任务 11.9） | 工程 / 任务 11.9（AoE 埋点） |
| 4 | 19 | **GDD 未定义玩家移动速度**：工程侧自定 4.5 tile/s = 144 px/s；需产品侧确认或按手感回填 GDD。**试玩重点为「是否偏快 / 眩晕」，而非「偏慢」**（2× 相机下「1× 显慢」的前提不成立） | product-reviewer |
| 5 | 21 | 手部锚点几何为**占位值**（`HAND_HEIGHT = -25` / `HAND_SPREAD = 11`），等 48×48 角色精灵产出后按实际手部像素位置重标定 | 阶段 6 |
| 6 | 22 | `player_controller.gd` 的**移动 / 闪避手感常量仍是文件内本地 const**（`LOCAL_MOVE_SPEED` 等），需统一迁入 `GameConstants`（技术债） | 随任务 9.4 手感迭代 |
| 7 | 23 | **UI 主题生成器纪律**：改动 `ui_theme.gd` / `game_constants.gd` 样式后必须重跑 `res://tools/gen_ui_theme.tscn` 再提交 `theme.tres` | 工程 |
| 8 | 24 | **视口拉伸 vs 像素字体**：`canvas_items` 拉伸在非整数窗口缩放下使像素字体发糊；当前 1920×1080 原生无碍，窗口缩放时需处理 | 阶段 8 |
| 9 | 27（新增） | **10.10 敌人碰撞归口**：`enemy_base.tscn` 的 `CollisionShape2D` 漏写 `type=`（全项目唯一），直接补会因**攻击判定零迟滞**引入 CHASE↔ATTACK 震荡、攻击时断时续；真前置是**加迟滞**（退出阈值 = `attack_range` + Δ，Δ ≥ 12px），**不是墙碰撞**（敌人系 `CharacterBody2D` 互撞，不依赖 `StaticBody2D` 墙）。**本轮不做，推迟到 9.4 手感定稿之后**<br>**2026-09-21 部分落地**：`type=` 已补、`collision_layer` 3→4（修值错误）、`collision_mask` 3→1 ⇒ **敌人↔地形**已生效（撞墙不穿，实测 `verify_knockback` x=88.00）。**敌人↔玩家仍待本条**（mask 故意不含玩家层）。详见 §4.7 附注 | 工程 / 任务 11.5（9.4 后） |
| 10 | 28（新增） | **AoE 实测埋点**：采集每技能命中数 / 单位时间清怪数 / 交火清怪均值；**关卡数据回填的前置条件**（见 #3） | 工程 / 试玩版（任务 11.9） |

> **已归档（非待办）** —— 原 #25：血条渐变（`#C42B2B→#8C1A1F`）与面板「顶部 1px 高光」（`#4E5866`）由**组件层**实现（`StyleBoxFlat` 不支持单边异色 / 渐变填充），属**已知实现约定**，不再列为待办。
>
> **收敛说明**：原表 26 条编号项（另有 1 行无编号的重复项，已并入原 #26）→ **删除 17 条**（15 条已完成 ✅，含本轮追加删除的原 #2「GDD 正文口径同步」；2 条已失效 #7 / #8）、**归档 1 条**（原 #25）、**保留 8 条**、**新增 2 条**（#27 / #28）。新编号已连号，并**保留「原 #」列**以免历史报告引用失锚。
>
> **收敛后 10 条全部不阻塞 demo 交付**（其中 #3 不阻塞 demo 交付，但阻塞「单局时长」试玩 —— 见 `next-version-scope-2026-09-18` 裁定 ②）。
>
> **📌 文档纪律（改编号）**：改动任何编号前，**先 `grep` 全文件的旧编号引用**（「待办 #N」「原 #N」「缺陷列表 #N」）—— **引用与被引用两侧必须一起改**，否则会留下断锚（本轮已修第 707 行旧引用、第 990 行孤儿引用两处）。

### 明确不做（避免越界）

- ❌ 音效 / BGM（阶段 6 音频资产就绪后由 JuiceFX 接 AudioStreamPlayer；2.8 只做视觉打击感）
- ❌ 装备词缀生成 / 背包 UI（2.7 已完成掉落 roll 与自动拾取；词缀生成阶段 3）
- ❌ 背包 / 角色面板 UI 实现
- ❌ 关卡场景内容

这些是阶段 2 / 3 的范围。本骨架只提供**数据结构、常量、全局服务**三件事。

---

## 十、相关文档

| 文档 | 路径 |
|---|---|
| 游戏设计文档（GDD）阶段 0 | `../deliverables/gstack/gdd-phase0-2026-09-16.md` |
| 美术风格规范 + AI 出图管线 | `../deliverables/gstack/art-style-and-ai-pipeline-phase0-0.7-2026-09-16.md` |
| 设计框架 | `../deliverables/gstack/design-phase0-framework-2026-09-16.md` |
| 开发任务清单 | `../deliverables/gstack/game-dev-task-plan-diablo-loot-arpg-2026-09-16.md` |
