# 七傳說 · 严谨 2D 像素素材包（DNF 风）

生成日期：2026-09-21（含三职业 8 方向 / 怪物 / BOSS 扩展）
风格定位：**严谨 16-bit 2D 像素风（DNF 暗黑地下城）**，非厚涂、非插画。
适配游戏：Godot 4 纯单机 2D 俯视 ARPG「七傳說」，游戏内逻辑分辨率 640×360，整数倍缩放 + 最近邻（Nearest），有限色板。

> 本包为严谨像素风主线；先前的厚涂插画风包、孤儿厚涂图、非像素源图、重复副本均已删除。

---

## 一、素材总览（约 315 个 PNG，全部通过 `verify_pack.py` 校验）

| 目录 | 内容 | 数量 | 尺寸 | 色板 |
|---|---|---:|---|---|
| `characters/` 根 | 三职业 idle（南） | 3 | 192×192 | 自适应 ~48 色 |
| `characters/walk_<dir>/` | 三职业 8 方向行走，每职业 4 帧 | 96 | 192×192 | 自适应 ~48 色 |
| `characters/attack_<dir>/` | 三职业 8 方向攻击，每职业 4 帧 | 96 | 192×192 | 自适应 ~48 色 |
| `characters/hurt_s/` | 三职业受击（南），每职业 2 帧 | 6 | 192×192 | 自适应 ~48 色 |
| `characters/death_s/` | 三职业死亡（南），每职业 4 帧 | 12 | 192×192 | 自适应 ~48 色 |
| `monsters/slime_forest/` | 毒史莱姆弹跳 idle 4 帧 | 4 | 192×192 | 自适应 ~48 色 |
| `monsters/slime_frost/` | 冰霜史莱姆弹跳 4 帧 | 4 | 192×192 | 自适应 ~48 色 |
| `monsters/skeleton/` | 骷髅兵 idle + 攻击 4 帧 | 5 | 192×192 | 自适应 ~48 色 |
| `monsters/imp_volcanic/` | 火焰小鬼 idle + 攻击 4 帧 | 5 | 192×192 | 自适应 ~48 色 |
| `monsters/` 根 | BOSS 恶魔领主 idle | 1 | **256×256** | 自适应 ~48 色 |
| `weapons/` | 主手 6 + 副手 4 | 10 | 48×48 | 自适应 ~48 色 |
| `armor/` | 头/胸/手/鞋/项链/戒指 | 6 | 48×48 | 自适应 ~48 色 |
| `fx/` | 剑气/火焰/冰霜/落雷（关键帧） | 4 | 96×96 | **严格 44 色板** |
| `anim/<skill>/` | 4 技能序列帧（透明底，二值 alpha） | 38 | 96×96 | **严格 44 色板** |
| `backgrounds/` | 森林/寒霜/火山/主菜单 | 4 | 640×360 | **严格 44 色板** |
| `ui/pixel/` | 面板/按钮/血蓝条/槽/稀有度/技能槽 | 17 | 见下 | **严格 44 色板** |
| `ui/skill_icons/` | 4 个技能图标 | 4 | 48×48 | **严格 44 色板** |
| `PACK_OVERVIEW.png` | 全素材分区总览（含三职业/8方向/怪物/装备） | 1 | — | — |
| `scene_preview_640x360.png` / `scene_preview_2x.png` | 实战合成画面 | 2 | 640×360 / 2× | — |

### 三职业
| 职业 | 外观 | 武器 | 攻击动作 |
|---|---|---|---|
| 战士 warrior | 银白尖刺短发、红黑无袖皮甲、红护手 | 银灰大剑 | 蓄力 → 挥剑 → 横斩剑气 → 收招 |
| 法师 mage | 金发、深蓝紫兜帽长袍、冰蓝水晶法杖 | 法杖 | 聚能 → 水晶亮起 → 发射冰蓝魔法弹 → 收招 |
| 弓手 archer | 金（绿）发、精灵尖耳、绿兜帽皮甲、背箭袋 | 长弓 | 抽箭 → 拉满弓 → 放箭 → 收弓 |

### 8 方向
`n / ne / e / se / s / sw / w / nw`。其中 `w`（西）、`sw`、`nw` 由 `e`/`se`/`ne` **水平镜像**得到，帧序与原始方向一致。

### 怪物与 BOSS
- 毒史莱姆（森林）、冰霜史莱姆（寒霜）：程序化 4 帧挤压弹跳（着地压扁 → 跳起拉长）。
- 骷髅兵（骨刃剑）、火焰小鬼（三叉叉）：idle + 4 帧攻击。
- BOSS 恶魔领主（大角、蝙蝠翼、火焰巨剑、熔岩裂纹），**256×256 画布**，比玩家更大以制造压迫感。

---

## 二、规格与命名

### 尺寸
- 玩家/小怪：**192×192 画布**，玩家实际高约 156、小怪按体型（史莱姆约 110、小鬼约 140），**脚底对齐**画布底部。
- BOSS：**256×256 画布**，高约 212。
- 武器 / 装备 / 技能图标：**48×48**，内容约 40px 居中。
- 特效 / 序列帧：**96×96**；背景：**640×360**。
- 所有 PNG 透明底、**alpha 二值（0/255）**、无半透明像素、无抗锯齿渐变。

### 命名
- 玩家：`char_<class>_<action>_<dir>_<NN>.png`
  - 例：`char_warrior_walk_s_01.png`、`char_mage_attack_ne_03.png`、`char_archer_death_s_04.png`
  - class：`warrior` / `mage` / `archer`；action：`idle` / `walk` / `attack` / `hurt` / `death`；dir：`n/ne/e/se/s/sw/w/nw`
  - idle 单帧：`char_<class>_idle_s_01.png`
- 怪物：`mon_<name>_<action>_<dir>_<NN>.png`（如 `mon_skeleton_attack_s_02.png`）；BOSS 为 `mon_boss_demon_lord_idle_s_01.png`
- 武器：`weapon_<type>_48.png`（sword/axe/hammer/dagger/staff/bow/shield/orb/quiver/offblade）
- 装备：`equip_<slot>_48.png`（helmet/chest/gauntlet/boots/amulet/ring）
- 特效：`fx_<skill>_px96.png`；序列帧 `anim/<skill>/fx_<skill>_NN.png`（NN 从 00）
- 背景：`backdrop_<biome>_640x360.png`、`main_menu_bg_640x360.png`

### 色板策略
- **运行时烘焙资产**（特效 `fx/`、`anim/`、背景、UI、技能图标）严格使用 `game_constants.gd` 的 **44 色 `PALETTE_ALL`**（`verify_pack.py` 校验通过）。
- **角色 / 怪物 / 武器 / 装备**走自适应量化（约 48 色），保留肉色 / 皮柄棕等 DNF 角色必需中间色——符合 DNF 素材色数超规的既有裁定。
- 44 色板含：中性 11 色 + 血/毒/冰/金/紫/猩红/套装 7 系各 4 色 + 5 档稀有度色。

---

## 三、动画播放参数

### 玩家动作（Godot AnimatedSprite2D）
| 动作 | 帧数 | 建议帧率 | 循环 |
|---|---:|---:|---|
| walk（8 方向） | 4 | 8–10 fps | 循环（迈步-并脚-反向-并脚） |
| attack（8 方向） | 4 | 12 fps | 单次，回到 idle |
| hurt | 2 | 10 fps | 单次/短暂 |
| death | 4 | 8 fps | 单次（停在最后倒地帧） |

### 怪物
- 史莱姆弹跳 idle：4 帧，8 fps 循环。
- 骷髅 / 小鬼攻击：4 帧，12 fps 单次。

### 技能序列帧（特效，14fps，单次不循环）
| 技能 | 目录 | 帧数 | 运动描述 |
|---|---|---:|---|
| 剑气斩 | `anim/slash/` | 9 | 月牙展开 → 飞出 → 淡出 |
| 火焰爆发 | `anim/fireburst/` | 10 | 火星 → 火柱放大 1.15× → 消散 |
| 冰霜新星 | `anim/frostnova/` | 10 | 亮点 → 冰环扩散 1.9× → 淡出 |
| 落雷 | `anim/thunder/` | 9 | 闪电劈下 → 白闪 → 消散 |

> 玩家攻击动作（挥剑/施法/射箭）与 `anim/` 特效是**两层**：AnimatedSprite2D 播角色动作，在命中帧叠加一层独立特效精灵。
> 长袍法师行走腿部被衣袍遮挡，动画主要靠袍角摆动；建议在引擎中对移动角色叠加轻微上下浮动（bob）。

### Godot 接入示例（片段）
```gdscript
var frames := SpriteFrames.new()
frames.add_animation("walk_s")
frames.set_anim_loop("walk_s", true)
frames.set_anim_speed("walk_s", 9.0)
for i in range(1, 5):
    var tex = load("res://assets/characters/walk_s/char_warrior_walk_s_%02d.png" % i)
    frames.add_frame("walk_s", tex)
$AnimatedSprite2D.sprite_frames = frames
# 朝西直接复用朝东并设置 scale.x = -1（镜像）
```

---

## 四、UI 组件（9-slice / 拉伸）

| 文件 | 尺寸 | 用法 |
|---|---|---|
| `panel_9slice_120.png` | 120×120 | 9-slice，**边距 8px**，四角铆钉 + 顶金三角，中心纯深槽可拉伸 |
| `btn_gold_{normal,hover,pressed}_96x24.png` | 96×24 | 主按钮三态，斜切金属，水平拉伸 |
| `btn_dark_{normal,hover,pressed}_96x24.png` | 96×24 | 次按钮三态 |
| `bar_hp_160x16.png` / `bar_mp_160x16.png` | 160×16 | 血/蓝条，填充建议代码裁切 |
| `slot_normal_48.png` / `slot_selected_48.png` | 48×48 | 物品槽普通/选中 |
| `rarity_{common,rare,epic,legend,myth}_48.png` | 48×48 | 5 档稀有度框：白/蓝/金/紫/橙 |
| `skill_slot_48.png` | 48×48 | 技能栏斜切角槽 |

> 按钮文字、血条数字用代码字体渲染，不烧进图片。

---

## 五、再生 / 加工管线（可复现）

- `pixel_pipeline.py`：核心像素化。AI 设计稿（统一**纯绿幕 #00FF00**）→ 边界泛洪抠底（含封闭绿缝全局键控、边缘去污染）→ 块主色（众数）降采样 → 固定画布（脚底对齐/图标居中）→ 色板量化 → alpha 二值化。
  - 角色/怪物/武器/装备：`--palette char`（自适应 48 色）；特效/背景/UI：`--palette 44`。
- `sprite_sheet_cut.py`：**横向多帧动作表切割**。整表抠绿 → 头部带列投影找每帧中心（不受腰部横斩剑气、底部基线干扰）→ 相邻中心中点为界，删除贴边越界碎片 → 统一缩放比例（防帧间跳变）→ 脚底对齐 → 48 色量化。
  - 用法：`python sprite_sheet_cut.py <sheet.png> <out_dir> <prefix> --n 4`
  - `--cuts x1 x2 ...` 手动分界；`--equal` 强制等宽；`--char-h` / `--canvas` 控制尺寸。
- `slime_squash.py`：史莱姆程序化挤压弹跳（NEAREST 形变，脚底对齐）。
- `ui_pixel_gen.py`：代码绘制 17 个 UI 组件；`fx_anim_gen.py`：4 技能序列帧。
- `build_overview.py` / `scene_gen.py`：生成 `PACK_OVERVIEW.png` 与实战合成预览。
- `verify_pack.py`：递归校验色板合规 / alpha 二值 / 尺寸（含怪物与动作子目录）。
- 高分辨率 AI 原始设计稿（绿幕、非像素成品）已在清理中移除；`_dl/` 为本次动作表的临时下载/预览，**不进交付包**，可随时删除。

---

## 六、待办与说明

- 受击/死亡目前仅做朝南（倒地后方向无关）；需要可按 `sprite_sheet_cut.py` 同流程补 e/n，再镜像 w。
- 玩家 walk/attack 已 8 方向齐全；法师/弓手的对角方向（ne/nw/se/sw）由实做帧 + 镜像构成，如对 45° 角度有更高要求可再细化。
- 怪物目前 4 小怪 + 1 BOSS 的 idle/攻击，待补：小怪 8 方向移动、受击/死亡、更多生态怪物（森林/寒霜/火山各成组）、更多 BOSS 与 BOSS 技能。
- 剩余装备（腿甲、戒指 B、更多套装）与武器强化外观可继续扩展。
- Seedance 2.5 像素风技能**演示视频**（非游戏序列帧，用于宣发）可选；游戏内动图已由 `anim/` 序列帧与角色动作帧覆盖，无需依赖视频。
