# 「七傳說」· Godot 4 暗黑刷寶 ARPG（v2.0）

> **純單機 2D 俯視刷寶 ARPG** —— 局內三選一成長 + 局外裝備鍛造雙線養成。
> 本檔是 **`game/` 工程本身**的說明書（工程細節與開發約定）。
>
> 👉 **接手開發的 AI / 新同學請先讀倉庫根的 [`../AGENTS.md`](../AGENTS.md)** ——
> 那裡有**現狀、可複製命令、倉庫地圖、鐵律與未結遺留**；本檔提供**工程細節**。
>
> ⚠️ **代碼是唯一事實來源。** 本檔與任何文檔若與代碼衝突，**以代碼為準並回來改文檔**。

| 項目 | 值 |
|---|---|
| 引擎 | **Godot 4.7.2.stable**（GDScript 2.0，**不是** .NET / C# 版） |
| 專案根目錄 | `D:\七傳說\game` |
| 主場景 | `res://scenes/main/main.tscn`（啟動分流：`--verify` / `--smoke` / 進遊戲） |
| 視口 | **640×360**，`canvas_items` 拉伸 + **`integer` 縮放**（窗口覆寫 640×360） |
| 渲染器 | GL Compatibility ｜ 紋理過濾 **Nearest**（像素鐵律，勿改） |
| 平台 | Windows 本地運行 · **不上線 · 不發行 · 無聯網**（2026-09-23 用戶裁定） |
| 規模 | **259** 個 `.gd`（約 **64,000** 行）｜ **160** 個 `.tscn`（含 **77** 個驗證場景）｜ **31** 份 `data/*.json` |
| 驗證 | `self_check` **122 項** + **77** 個 `verify_*` 場景 + **7** 個策劃校驗器 |

---

## 一、快速上手

### 1.1 打開與運行（人）

1. 裝 **Godot 4.7.2 stable 標準版**（<https://godotengine.org/download/windows/>，**不要** .NET 版）
2. 專案管理器 →「導入」→ 選 `D:\七傳說\game\project.godot`
3. 首次導入 Godot 會生成 `.godot/` 與各資源的 `.import`（已在 `.gitignore` 忽略，屬正常）
4. 按 **F5** → 進**主菜單**（開始遊戲 → 據點 → 選關 → 關卡 → 結算）

> 片頭場景 `res://scenes/main/intro.tscn` **刻意未接入啟動流程**
> （用戶 2026-10-08 裁定「片頭先不接入遊戲」）；`verify_intro` 有斷言**釘住**此裁定，
> 誰把它接回啟動流程，那條斷言就會轉紅提醒。

### 1.2 無頭驗證三件套（AI / CI 用）

```bash
GODOT="C:/Users/<你>/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
export APPDATA='C:\Users\<你>\AppData\Roaming'      # ← 見 1.3，不能省

# ① 首次（或刪過 .godot/ 之後）先跑一次，生成 class_name 全局類緩存
"$GODOT" --headless --editor --quit --path "D:/七傳說/game"

# ② 自檢：122 項全綠 ⇒ 退出碼 0；任一失敗 ⇒ 1
"$GODOT" --headless --path "D:/七傳說/game" -- --verify

# ③ 全量回歸（推薦，一條搞定）：77 個 verify 場景 + self_check + 7 個策劃校驗器
cd "D:/七傳說" && python tools/run_regression.py

# ④ 單點排查（換檔名即可）
"$GODOT" --headless --path "D:/七傳說/game" res://tools/verify_loot.tscn
```

**回歸判讀口徑**：`[FAIL]` 計數 == **0** **且** exit code == **0** ⇒ 全綠（實測約 **230s**）。

### 1.3 兩個必須知道的环境陷阱

> ⚠️ **陷阱 A：`class_name` 全局類緩存**
>
> 剛 clone 下來的專案**沒有** `.godot/`。此時直接跑 ② 會看到一大片
> `Parse Error: Could not find type "EquipmentInstance"`、
> `Failed to instantiate an autoload, script 'event_bus.gd' does not inherit from 'Node'`。
>
> **這不是代碼錯誤** —— `class_name` 註冊在 `.godot/global_script_class_cache.cfg`，
> 而該緩存**只由編輯器掃描生成**。所以 ① 不能跳過；跑完 ① 之後 ② 就是乾淨的。
> 該緩存已在 `.gitignore` 中。

> ⚠️ **陷阱 B：`APPDATA` 為空 ⇒ `user://` 變成相對路徑**（實際踩過兩次）
>
> Windows 上 `user://` 的物理位置由 `APPDATA` 推導。在**無頭 / CI / 精簡 shell** 裡
> `APPDATA` 可能是**空串**，此時 Godot fallback 成**相對路徑**
> `./Godot/app_userdata/七傳說/`（相對當前工作目錄）。
>
> **症狀會偽裝成「存檔寫不進去」的代碼 bug**，鏈路是：
>
> | 步驟 | 空 `APPDATA` 下的結果 |
> |---|---|
> | `FileAccess.open("user://saves/x.json", WRITE)` | **成功**（按相對 CWD 解析，檔案真寫出來了） |
> | `DirAccess.open("user://saves")` | **返回 `null`，`get_open_error()` = `ERR_INVALID_PARAMETER(31)`** |
> | ⇒ `SaveManager._move_file()` → `dir.rename()` | 拿不到 `DirAccess` ⇒ 返回 `false` |
> | ⇒ `SaveManager._atomic_write()` | `.tmp` 寫成功、**rename 失敗** ⇒ 報「無法將臨時檔案重命名為 …」 |
> | ⇒ `create_new_slot()` / `save_to_slot()` | 返回 `false` / `null` ⇒ 測試報「新建槽位失敗」 |
>
> 因為 `DirAccess.open()` **只接受絕對路徑**（不接受 `user://` 前綴）而 `FileAccess` 接受，
> 所以「一半能寫、一半不能寫」，**極容易被誤判成 `SaveManager` 的代碼缺陷**。
>
> **這不是代碼錯誤**，是環境問題。跑 Godot 前把 `APPDATA` 顯式導出即可（見 1.2）。
> **副作用**：空 `APPDATA` 跑過一次後，`game/` 下會多出垃圾目錄 `game/Godot/`
> （已被 `game/.gitignore` 的 `/Godot/` 覆蓋、不進倉庫，可隨時手刪）。
> **見到它就說明那次運行是空 `APPDATA` 跑的 —— 那次跑出的存檔 / 日誌結論全部不可信。**

> 📌 更多坑（共 60+ 條，含每條的踩坑現場與修法）見
> [`../.workbuddy-ai/memory/IRON-RULES.md`](../.workbuddy-ai/memory/IRON-RULES.md)。

---

## 二、目錄結構

```
game/
├── project.godot               # 專案配置：渲染 / 視口 / 輸入映射 / Autoload / 物理層
├── export_presets.cfg          # Windows 導出預設
├── icon.svg                    # 專案圖示
├── README.md                   # 本檔
├── CONTENT_GUIDE.md            # 素材替換指南（不碰代碼換素材）
│
├── scenes/                     # 場景（.tscn）
│   ├── main/                   #   main.tscn（啟動分流）/ intro.tscn（片頭 · 未接入）
│   │                           #   / main_menu.tscn / hub.tscn（據點）
│   ├── levels/                 #   level.tscn —— 20 關**共用一份**，
│   │                           #   差異全由 on_scene_entered 的 level_id + difficulty_tier 驅動
│   ├── player/                 #   player.tscn（武器層三層結構 + 主副手錨點）
│   ├── enemies/                #   enemy_base.tscn（CharacterBody2D + 碰撞 + 生命組件）
│   ├── loot/                   #   loot_drop.tscn（光柱 / 磁吸 / pop 動畫）
│   ├── combat/                 #   damage_dummy.tscn（受擊靶，驗證用）
│   ├── juice/                  #   damage_number.tscn / pixel_burst.tscn
│   └── ui/theme/               #   theme.tres（專案預設主題產物）
│
├── scripts/                    # 腳本（.gd）—— 16 個子目錄，259 檔 / 約 64,000 行
│   ├── autoload/               #   全局單例（見第三節）
│   ├── core/                   #   game_constants.gd（**常量唯一源**）/ input_remapper.gd / main.gd
│   ├── player/                 #   player_controller.gd（移動 / 閃避無敵幀 / 普攻假連段 / 技能轉發）
│   ├── combat/                 #   傷害管線 / 命中幾何 / 生命組件（異常 DoT）/ 技能控制器 / 法力池 / 地面區域
│   ├── enemies/                #   enemy_base.gd（AI 狀態機）/ 精英詞綴 / BOSS 階段
│   ├── loot/                   #   loot_roller（掉落引擎）/ affix_roller（詞綴生成）/ loot_drop（地面物）
│   ├── forge/                  #   強化洗練 / 材料包 / 分解 / 合成 / 神話重鑄
│   ├── legendary/              #   傳奇特効觸發結算（純靜態）
│   ├── sets/                   #   套裝計數 / 檔位 / 加成併入屬性結算
│   ├── run/                    #   關卡生成 / 局內等級 / 三選一池 / Buff / 商店 / 本局結算
│   ├── account/                #   賬號等級（**1–30**）/ 天賦樹（3 分支）/ 解鎖 / 聲望 / 成就
│   ├── inventory/              #   背包 / 倉庫網格資料層
│   ├── items/                  #   寶石鑲嵌 / 彩裝成長
│   ├── juice/                  #   juice_fx.gd（**Autoload**）/ 飄字 / 像素粒子 / 屏震
│   ├── audio/                  #   audio_manager.gd（含 headless Dummy 驅動短路，見 5.1 註）
│   └── ui/                     #   主題構建 / HUD / 各面板
│
├── resources/                  # 自訂 Resource 類（資料結構的**代碼定義**）
│   └── affix_data / affix_roll / equipment_data / equipment_instance / set_data /
│       monster_data / level_data / loot_table / skill_data / damage_result / save_data
│
├── data/                       # 配置資料（**純 JSON，策劃直接改**）—— 31 份
│   ├── equipment/  sets/  affixes/  affix_pools/  monsters/  levels/
│   ├── loot_tables/  skills/  runes/  bosses/  classes/  consumables/
│   └── legendary_effects/  set_effects/  audio/
│
├── tools/                      # 開發期驗證 / 抓圖 / 探針（**不進導出包**，見第五節）
│
└── assets/                     # 美術與音頻資源
    ├── sprites/                #   主角 48×48 / 怪 32×32 / 圖示 48×48
    ├── tilesets/               #   地圖 TileSet（每格 32×32）
    ├── fx/  ui/  fonts/  audio/
```

> **關於 `.gd.uid` 與 `*.import`**：Godot 4.4+ 會為每個 `.gd` 生成同名的 `.gd.uid`
> （穩定的資源 UID），`.import` 則是導入元資料。**兩者都必須提交**，
> 否則換台機器打開時資源引用會重新分配、場景裡的引用可能失聯。
> 唯一該忽略的是 `.godot/` 緩存目錄本身。

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
| 套装定义 | `SetData` | **3**（霜噬 / 烬途 / 守誓者） | 「守誓者」6 件套 + 2/4/6 档加成 |

`SetData` 与 `EquipmentData` 是**双向引用**：套装列出 6 件底材 ID，每件底材的 `set_id` 指回套装。
`ConfigLoader._cross_validate()` 会强制二者一致 —— 只改一边会在启动时直接报错。

存档只落盘**模板 ID + 实例字段**，读档时由 `ConfigLoader.resolve_instance()` 回填模板引用。
**任何读档路径都必须调用 `SaveManager.load_from_slot_resolved()`**，
否则装备的 `template` 为空，`get_display_name()` 等会退化。

### 4.3 模块间通信只走 EventBus

```gdscript
# 正确：掉落拾取只管发信号，不认识 UI（消费方 PickupToastHUD 监听 loot_picked_up）
EventBus.loot_picked_up.emit(entry)

# 错误：直接找到 UI 节点改它
get_node("/root/Game/UI/PickupToast").show(entry)
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
> 整个节点 —— 当时的 `verify_*` 全绿、`self_check` 全绿，因为**没有一条断言看过
> 敌人的物理碰撞**（战斗命中走的是 `EnemyBase.get_hit_radius()` 硬编码 12.0，与形状无关）。

---

## 五、驗證方法

> 本專案的鐵律是 **「改動必須附驗證」**。所有驗證都是**無頭可跑**的 Godot 場景，
> 每個場景自己打印 `[OK] / [FAIL]` 並以退出碼表態（`0` = 全通過，`1` = 有失敗項）。

### 5.1 判讀約定

| 命令 | 通過標準 |
|---|---|
| `-- --verify` | 打印「結果：全部通過（**122** 項）」且退出碼 `0` |
| 任一 `verify_*.tscn` | 打印「===== 结果：**0** 项失败 =====」且退出碼 `0` |
| `python tools/run_regression.py` | `[FAIL]` 計數 == **0** 且退出碼 `0` |

> ⚠️ **「回歸全綠」≠「無告警」**：`tools/run_regression.py` 只轉發 `[PASS]/[FAIL]`，
> **不轉發 stderr** ⇒ 退出期的 `leaked at exit` / `resources still in use`
> 在全量回歸裡**完全看不到**，只有**單跑**該場景才看得到。
> 別拿「全綠」當「乾淨」的證明。（已知殘留：`self_check` 退出時漏 28 個物件、
> `verify_hud` 漏 6 個 —— 均為既有問題，見 `AGENTS.md` 未結遺留。）

### 5.2 驗證腳本一覽（**77** 個場景，按域分組）

| 域 | 腳本 |
|---|---|
| 資料 / 常量 / 校驗 | `verify_integration` `verify_metrics` `verify_affix_pool` `verify_affix_roller` `verify_equipment` `verify_equipment65` `verify_equipment_compare` `verify_loot_tables` `verify_stat_calculator` `verify_balance84` |
| 戰鬥 / 命中 / 生命 | `verify_damage` `verify_hit` `verify_health` `verify_knockback` `verify_element_ext` `verify_buff` `verify_juice` `verify_fx` `verify_skill_forms` `verify_skills` |
| 敵人 / BOSS / 召喚 | `verify_enemy` `verify_elite` `verify_monsters62` `verify_boss63` `verify_boss_skills` `verify_boss_awaken8c` `verify_summon` |
| 掉落 / 鍛造 / 裝備 | `verify_loot` `verify_forge` `verify_dismantle` `verify_inventory` `verify_legendary_effects` `verify_legendary_bus` `verify_set_system` `verify_set_effects` `verify_mythic_hidden` `verify_consumable` `verify_equip_panel` |
| 局內 / 關卡 / 目標 | `verify_run_growth` `verify_run_result` `verify_level_gen` `verify_shop` `verify_choice_flow` `verify_choice_panel` `verify_collect` `verify_objectives` `verify_terrain8b` `verify_tiles` `verify_esc` |
| 局外 / 賬號 / 技能裝配 | `verify_account` `verify_class_select` `verify_hub` `verify_skill_equip` `verify_skill_unlock` `verify_skill_panel` `verify_skill_ext` |
| UI / HUD / 面板 / 設置 | `verify_ui` `verify_ui71` `verify_ui_assets` `verify_hud` `verify_panel_unify` `verify_polish9x` `verify_settings` `verify_settings82` |
| 存檔 / 音頻 / 性能 / 導出 | `verify_save` `verify_save81` `verify_audio66` `verify_audio8e` `verify_perf83` `verify_export91` `verify_play92` |
| 端到端 / 片頭 / 動畫 / 回歸紅線 | `verify_e2e` `verify_intro` `verify_anim` `verify_player` `verify_fix85` `verify_fix93` |

> 清單以檔案系統為準：`ls game/tools/verify_*.tscn`。
> **新增驗證場景不必改任何清單** —— `run_regression.py` 會自動掃描。

### 5.3 三類工具（`game/tools/`，**不進導出包**）

| 類別 | 命名 | 用途 | 注意 |
|---|---|---|---|
| 斷言型 | `verify_*.tscn` | **主力**：打印 `[OK]/[FAIL]` 並以退出碼表態 | 無頭可跑 |
| 抓圖型 | `capture_*.tscn` | 真渲染一幀存 PNG（目視驗收） | ⚠️ **必須去掉 `--headless`**，且改素材後**舊截圖一律作廢** |
| 探針型 | `probe_*.tscn` | 只打印事實、不斷言（給人看） | 無頭可跑 |
| 預覽型 | `*_preview.tscn` | 面板 / 曲線的渲染預覽（自截圖） | 需窗口 |

### 5.4 策劃校驗器（**7** 個，Python，不在 Godot 內）

位於 `deliverables/gstack/策划案/`，由 `run_regression.py` 一併執行：

| 校驗器 | 守什麼 |
|---|---|
| `01-check_skill_dps.py` | 技能 DPS 與倍率體系 |
| `02-check_affix_pool.py` | 詞綴池 / 權重 / 互斥 |
| `03-check_third_step.py` | 元素 / 套裝 / 傳奇接線 |
| `04-check_number_model.py` | 數值模型（XP 曲線 / 經濟 / 預算） |
| `05-check_monster_level_boss.py` | 怪物等級帶 / BOSS / 關卡 |
| `06-check_special_modes.py` | 深淵 / 高塔 / 特殊稀有度 |
| `07-check_dev_tasks.py` | 開發總表契約（含 `R9 賬號上限 == 30`） |

用法：`python "deliverables/gstack/策划案/0N-check_*.py" --repo D:/七傳說`（**倉庫根**，腳本自己拼 `game/`）。

### 5.5 只跑一條命令

```bash
cd "D:/七傳說" && python tools/run_regression.py
```

它會：① 全專案解析預檢（`parse_all`）→ ② 掃描並跑完全部 `game/tools/verify_*.tscn`
→ ③ 跑 `self_check`（EXTRA_CHECKS）→ ④ 跑 7 個策劃校驗器 → ⑤ 打印耗時與失敗數。
`[FAIL]` == 0 且 exit == 0 即全綠。

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

> **✅ 已与 `project.godot` `[input]` 段（第 64–167 行，共 16 个 action）逐条对齐（2026-10-14 重新核对）**：
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

> ⚠️ **数值口径**：示例中的怪物投放数量（及 `total_monster_budget`）当前为 **demo 期 POC 值，非 D5（单局 14–21 分钟）终值**。
> 回填属**策划侧数值调整**，见 §9.2(a) 待裁定项与 `../deliverables/gstack/策划案/04-数值与数据模型.md`。

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

## 九、當前狀態與後續（**2026-10-14 · v2.0**）

### 9.1 已收線批次

| 批 | 內容 |
|---|---|
| 策劃七步 | ✅ 完成（180 工單 / 8 批次）· `deliverables/gstack/策划案/01–07` |
| 素材開發線 | ✅ 收線（`ASSET_MANIFEST.json` v7：done 25 / BLOCKED 0） |
| 工程落地 B0–B5 | ✅ 特殊玩法八子批全收線 |
| HANDOFF-C / D / E | ✅ UI 打磨復盤 / 符文圖標 v2 / 符文掉落接線 |
| 片頭「勇者斗惡魔」 | ✅ 可播放開場（**刻意未接入啟動流程**，見 1.1） |
| **全面優化①–⑧** | ✅ 清理瘦身 **928.4 MB** + 賬號上限 **20→30** + 打擊感/juice 八項（磁吸 / DoT 跳字 / 屏震頓幀 / 地面貼花 / 稀有慶祝 / 傷害分級頓幀 / 拾取反饋 / 掉落彈出） |
| 文檔 2.0 | ✅ 本檔重寫 + `AGENTS.md` 新增 + 一次性交接文檔歸檔 |

### 9.2 未結遺留

#### (a) 需用戶裁定

| # | 項 | 現狀 |
|---|---|---|
| 1 | `04-check_number_model.py` / `04-數值與數據模型.md` 仍是**上限 20** 口徑 | 上限已改 30 ⇒ 其 `L2/L2b` 不變式「單周目落點 == 上限 − 1」失效。04 **目前仍綠**（自洽模型、漂移檢測不含該常量），但**文檔與代碼存在已知分歧**。待裁定：接受 20–30 刷級區並改寫 L2/L2b，或同步抬 `reward_xp`（≈ ×2.8）保住不變式 |
| ~~2~~ | ~~技能終極階 `unlock_level` 20~~ **已裁定改回 22（2026-10-14）** | `blood_rage` / `spirit_wolf` / `summon_elemental` 三終極階回到 22；`warcry` / `shadow_volley` / `mana_surge` 維持 18 |
| 3 | `boss_ember_lord.level_min` **19 → 13** | 刻意偏離策劃 §1.1 等級帶表（表寫 19–20），為讓 `05-check` C19 轉綠。待裁定「改表 or 改回並放寬 C19」 |
| 4 | 深淵表的 `rune_drop_chance`（0.05 / 0.30）**當前不會被消費** | `roll_rune_drop` / `roll_loot` 只走 `ConfigLoader.LOOT_TABLE_BY_TIER`（按 `MonsterData.Tier`）；深淵表要經 `LevelData.loot_table_id` 才用得上（只有 `roll_guaranteed_equipment` 支援）。待裁定「要不要讓深淵房走自己的掉落表」 |
| ~~5~~ | ~~`EventBus.loot_dropped` 死信號~~ **已刪除（2026-10-15）** | 地面掉落直接掛 LootDrop 節點；稀有特效走 `rare_loot_spawned`、拾取走 `loot_picked_up`，零消費需求 ⇒ 刪除（README 教學示例改用 `loot_picked_up`） |

#### (b) 工程側待接線（有落點、無消費方）

- **分支 7 個 modifier 未接**（`combo_hits` / `combo_damage_pct` / `linger` / `afterimage` / `pulse` /
  `summon_damage_pct` / `buff_potency_pct`，面板標「暫未生效」）——
  ⚠️ `summon_count` **已接**；2026-09-29 用戶已裁定「只接可映射的 7 個」⇒ 屬**刻意延後**，非 bug
- **`material_sub_weights` 屬廢棄字段（刻意不接線，勿誤接）**：GDD 02 §6.1 早期設想怪物直接按
  `forge_stone` / `enchant_scroll` / `reroll_crystal`（normal 70/20/10）掉三種用途材料；但實際材料經濟
  已走 **GDD 5.3 分解產出**——怪物只掉 `stones`（魔石），高級材料 `dust` / `essence` / `crystal` 由
  分解裝備獲得（藍→1 塵 … 紅→6 精粹+1 結晶），特殊檔分解出 `abyss_shard` / `tower_sigil`。
  這三個鍵在 `MaterialBag` **根本不存在**；若按權重映射成 stones/dust/crystal，會讓普通怪直接掉
  神話結晶、繞過分解循環、破壞稀有度經濟。⇒ JSON 數據保留（ConfigLoader 刻意不讀），等 GDD 回頭標廢。
- **`item_level_spread` 已接線（2026-10-15，2-L13 / V13）**：`LootTable` 加 `ilvl_min/max/mode_mod`
  + `bonus_*` 字段、`ConfigLoader` 讀取、`_roll_item_level()` 改按表的**非對稱三角分佈**（normal ±3、
  elite ±2 + 10% 再 +5、BOSS 怪 +3~8 峰值 +5）。舊硬編碼 `ITEM_LEVEL_JITTER=2`（±2 全檔位）與
  `hi=max(怪,玩家)` 越级 clamp **一併移除**：後者會把 BOSS 表正向獎勵壓平；越级平衡改由
  「稀有度越级懲罰（紫/橙/紅 ×0.5）」+「裝備需求等級 ilvl-2」承擔。L20 BOSS 衝到 iLvl 28 超過
  底材池頂 22 時，cap 到該稀有度池頂，保證 BOSS 必掉裝備而非回退金幣。
- **玩家→怪物施加異常已接通（2026-10-14）**：`skill_controller._hit` / `summon` 命中補
  `apply_ailment_from_element`，`enemy_base` 補轉發到 health；命中後按異常染色（見打擊感）。
- **無異常 HUD**（`status_shock` / `status_curse` 素材已在但無消費點）
- `ms_boost.element_attach`（裂界指環附元素）未接線；`extra_loot` 未強制 `loot_quality`
- **`SetPanel` 尚未掛進真實 UI**（全庫只有 `set_preview` / `capture_set_panel` 在用）
- `BIG_NODE_MECHANICS` 前 5 機制仍為展示字串
- 套裝專屬特效視覺 6 套未生產；增益圖標 12 張未生產（B4-1 走佔位繪製）
- `explosive_arrow` 命中爆炸 / `poison_cloud`「使其中毒」/ `rune_echo`（`echo_count`）未承載
- 命名漂移：`AILMENT_SLOW="slow"` vs 素材鍵 `chill`
- 8 隻新怪 `sprite_path` **已兜底（2026-10-14）**：複製 creatures 目錄 `idle_s_01` 生成
  `sprites/enemies` 單張 png + .import，全 24 怪 `sprite_path` 有效（原「指向不存在 png」已消除）
- `UISkin.affix_icon()` **零調用方**（死函數）；且 TEX 鍵用舊名 `affix_armor_penetration`
  對不上 `stat_key=armor_pierce`（無運行時消費點，留 B7）

#### (c) 策劃側仍紅（非工程批）

- `05-check` **C17**（`ch1_l03/l04` 空 layout，屬 `5-W5-9`）· **C20**（creatures 目錄數，素材側）
- **C12**（工程側關卡數 == 20）· **C13**（budget == Σcount_max）同屬既有口徑差，
  `05 --repo` 合計 **82/4**

#### (d) 已知測試噪音（不影響回歸判定）

- `self_check` 退出時漏 **28** 個物件（`GDScript` ×8 / `Object` ×7 / `PanelContainer` ×4 /
  `Control` ×3 / `Node` ×2 / `StyleBoxFlat` ×1 —— **UI 類，非音頻**）
- `verify_hud` 退出時漏 **6** 個物件 + 2 個資源（段 A 的孤兒 `Node`、段 C 的 `extends Object` 未 `free()`）

### 9.3 全案三條最高危項（改動前務必確認）

1. **稀有度 8→10 不可逆** —— `rarity` 存 int；`RARITY_COUNT` 回退會把舊檔 8/9 **靜默壓成 7（隱藏裝）**
2. **62 件底材無一覆蓋 8/9 檔** ⇒ `loot_roller.gd:171` 空池 `return null` ⇒ 特殊檔**什麼都不掉且零報錯**
3. **`migrate()` 的 `_:` 兜底** —— 漏加版本分支**不報錯**、新欄位直接消失 ⇒ 存檔升版必須逐版加顯式分支

---

## 十、相關文檔

| 文檔 | 路徑 | 讀它幹什麼 |
|---|---|---|
| **AI 接手入口** | [`../AGENTS.md`](../AGENTS.md) | **先讀這個**：現狀 / 命令 / 地圖 / 鐵律 / 遺留 |
| 文檔總索引 | [`../docs/README.md`](../docs/README.md) | 全庫文檔導航（現行 vs 歸檔） |
| **鐵律與坑分冊** | [`../.workbuddy-ai/memory/IRON-RULES.md`](../.workbuddy-ai/memory/IRON-RULES.md) | **60+ 條坑**（含踩坑現場與修法）—— 動代碼前必讀 |
| 專案長期記憶 | [`../.workbuddy-ai/memory/MEMORY.md`](../.workbuddy-ai/memory/MEMORY.md) | 當前位置 / 未結遺留 / 基線約定 / git 鐵律 |
| 逐日工作誌 | [`../.workbuddy-ai/memory/`](../.workbuddy-ai/memory/) | 每個批次的完整復盤（按日期） |
| 策劃案 01–07 | `../deliverables/gstack/策划案/README.md` | 技能 / 裝備 / 數值 / 怪物 / 特殊玩法 / 開發總表 |
| 玩法設計總綱 | [`../Playground開發描述.md`](../Playground開發描述.md) | 對標爆款暗黑向的玩法方向（割草 / 打擊感 / Build 聚變 / 像素動效） |
| 素材替換指南 | [`CONTENT_GUIDE.md`](CONTENT_GUIDE.md) | 不碰代碼換素材（使用者內容目錄 `content/`） |
| 一次性交接（歸檔） | `../docs/archive/HANDOFF-C.md` · `-D` · `-E` | 歷史交接單（**已歸檔，非現行**） |
