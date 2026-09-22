# 七傳說 · 严谨 2D 像素素材包（DNF 风）

生成日期：2026-09-21
风格定位：**严谨 16-bit 2D 像素风（DNF 暗黑地下城）**，非厚涂、非插画。
适配游戏：Godot 4 纯单机 2D 俯视 ARPG「七傳說」，游戏内逻辑分辨率 640×360，整数倍缩放 + 最近邻（Nearest），有限色板。

> 本包为严谨像素风主线；先前的厚涂插画风包（`high_art_pack_*`、`seven-legends-art-pack-v2`）及孤儿厚涂图、非像素源图、重复副本均已在 2026-09-21 清理中删除。

---

## 一、素材清单（41 个静态 PNG + 38 帧序列帧 + 4 个 GIF）

| 目录 | 内容 | 数量 | 尺寸 | 色板策略 |
|---|---|---:|---|---|
| `characters/` | 主角战士 idle（南） | 1 | 192×192 画布 | 自适应 ~48 色 |
| `weapons/` | 剑/斧/锤/匕首/法杖/长弓/盾 | 7 | 48×48 | 自适应 ~48 色 |
| `armor/` | 头盔/胸甲/护手/战靴 | 4 | 48×48 | 自适应 ~48 色 |
| `fx/` | 剑气斩/火焰爆发/冰霜新星/落雷（关键帧） | 4 | 96×96 | **严格 44 色板** |
| `backgrounds/` | 森林/寒霜/火山/主菜单 | 4 | 640×360 | **严格 44 色板** |
| `ui/pixel/` | 面板/按钮/血蓝条/物品槽/稀有度框/技能槽 | 17 | 见下 | **严格 44 色板** |
| `ui/skill_icons/` | 4 个技能栏图标 | 4 | 48×48 | **严格 44 色板** |
| `anim/<skill>/` | 4 技能序列帧（透明底，二值 alpha） | 38 | 96×96 | **严格 44 色板** |
| `anim/*.gif` | 4 个技能循环预览（深底） | 4 | 96×96 | — |

### 角色与装备设定
- 主角：Q 版二头身、银白色尖刺短发、肉色皮肤、红黑无袖皮质战甲、深色长裤、红护手、持银灰大剑。
- 6 类主手：剑 / 斧 / 锤 / 匕首 / 法杖 / 长弓；副手 4 类：盾 / 法器 / 箭袋 / 副刃（本包先出盾）。
- 10 装备部位：头 / 胸 / 手 / 腿 / 鞋 / 主手 / 副手 / 项链 / 戒指 A / 戒指 B（本包先出头/胸/手/鞋）。
- 三生态配色：森林（毒绿）、寒霜（冰蓝）、火山（血红），与 `game_constants.gd` 色板一致。

---

## 二、规格与命名

### 尺寸
- 角色：**192×192 画布**，角色实际高约 156，**脚底对齐**画布底部（与现有 `dnf/normalized/player/` 一致）。
- 武器 / 装备 / 技能图标：**48×48**，内容约 40px，居中。
- 特效 / 序列帧：**96×96**，内容约 88px，居中。
- 背景：**640×360**（游戏内满屏，整数倍缩放）。
- 所有 PNG 透明底、**alpha 二值（0/255）**、无半透明像素、无抗锯齿渐变。

### 色板策略（重要）
- **运行时烘焙资产**（特效 `fx/`、`anim/`、背景、UI、技能图标）严格使用 `game_constants.gd` 的 **44 色 `PALETTE_ALL`**（`verify_pack.py` 已校验通过）。
- **角色 / 武器 / 装备**走自适应量化（约 48 色），保留肉色 / 皮柄棕等 DNF 角色必需的中间色——这与现有 `char_player_idle_s_01.png`（46 色）一致，符合用户裁定的"DNF 素材色数超规可接受"。
- 44 色板含：中性 11 色 + 血/毒/冰/金/紫/猩红/套装 7 系各 4 色 + 5 档稀有度色。

### 命名
- 武器：`weapon_<type>_48.png`（type: sword/axe/hammer/dagger/staff/bow/shield）
- 装备：`equip_<slot>_48.png`（slot: helmet/chest/gauntlet/boots）
- 特效：`fx_<skill>_px96.png`；序列帧 `anim/<skill>/fx_<skill>_NN.png`（NN 从 00）
- 背景：`backdrop_<biome>_640x360.png`、`main_menu_bg_640x360.png`
- 技能图标：`ui/skill_icons/skill_<skill>_48.png`

---

## 三、序列帧动画播放参数

| 技能 | 目录 | 帧数 | 建议帧率 | 循环 | 运动描述 |
|---|---|---:|---:|---|---|
| 剑气斩 | `anim/slash/` | 9 | 14 fps（70ms） | 单次 | 月牙在左侧展开 → 向右飞出 → 淡出 |
| 火焰爆发 | `anim/fireburst/` | 10 | 14 fps | 单次 | 地面小火星 → 火柱放大到 1.15× → 上升消散 |
| 冰霜新星 | `anim/frostnova/` | 10 | 14 fps | 单次 | 中心亮点 → 冰环向外扩散到 1.9× → 淡出 |
| 落雷 | `anim/thunder/` | 9 | 14 fps | 单次 | 闪电自顶劈下 → 命中白闪 → 快速消散 |

> 预览 GIF 已用 70ms/帧、循环导出（仅用于查看效果，游戏内请用透明 PNG 序列帧）。
> 建议 Godot 中用 `AnimatedSprite2D` 或 `SpriteFrames` 加载，渲染模式 `CanvasItem` 默认，混合模式火焰/雷电可加 Add。

### Godot 接入示例（片段）
```gdscript
var frames := SpriteFrames.new()
frames.add_animation("fireburst")
frames.set_anim_loop("fireburst", false)
frames.set_anim_speed("fireburst", 14.0)
for i in range(10):
    var tex = load("res://assets/fx/fireburst/fx_fireburst_%02d.png" % i)
    frames.add_frame("fireburst", tex)
$AnimatedSprite2D.sprite_frames = frames
```

---

## 四、UI 组件（9-slice / 拉伸）

| 文件 | 尺寸 | 用法 |
|---|---|---|
| `panel_9slice_120.png` | 120×120 | 9-slice，**边距 8px**，四角铆钉 + 顶金三角，中心纯深槽可任意拉伸 |
| `btn_gold_{normal,hover,pressed}_96x24.png` | 96×24 | 主按钮三态，斜切金属，水平可拉伸（切角两端不要拉伸） |
| `btn_dark_{normal,hover,pressed}_96x24.png` | 96×24 | 次按钮三态 |
| `bar_hp_160x16.png` / `bar_mp_160x16.png` | 160×16 | 血/蓝条，凹槽 + 金属端帽；**填充建议用代码裁切**，或把端帽与中段分 9-slice |
| `slot_normal_48.png` / `slot_selected_48.png` | 48×48 | 物品槽普通/选中（选中亮金框 + 四角） |
| `rarity_{common,rare,epic,legend,myth}_48.png` | 48×48 | 5 档稀有度框：白/蓝/金/紫/橙 |
| `skill_slot_48.png` | 48×48 | 技能栏斜切角槽 + 四角铆钉 |

> 按钮文字、血条数字一律用代码字体渲染，不要烧进图片。

---

## 五、再生 / 加工管线（可复现）

- `pixel_pipeline.py`：核心像素化管线。AI 设计稿（统一**纯绿幕 #00FF00**）→ 边界泛洪抠底（含封闭绿缝全局键控、边缘去污染）→ 块主色（众数）降采样到目标像素尺寸 → 固定画布（角色脚底对齐、图标居中）→ 色板量化 → alpha 二值化。
  - 角色/武器/装备：`--palette char`（自适应 48 色，保留肉色）
  - 特效/背景/UI：`--palette 44`
  - 图标加 `--center`；背景用 `--mode background`（不抠图）
- `ui_pixel_gen.py`：代码精确绘制 17 个 UI 组件。
- `fx_anim_gen.py`：基于静态特效帧，用整数像素 NEAREST 变换（缩放/位移/裁剪）生成 4 技能序列帧 + GIF。
- `verify_pack.py`：自校验（色板合规 / alpha 二值 / 尺寸）。
- 高分辨率 AI 原始设计稿（1024 绿幕、非像素成品）已在素材清理中移除；如需再生，重新生成绿幕设计稿后按上述管线参数重跑（`--tol` / `--canvas` / `--char-h` / `--palette`）。

---

## 六、待办与说明

- 本包为**先遣美术基线**：角色目前仅 1 个 idle 帧；后续应补 walk/attack/受击/死亡及 8 方向。
- 其余装备部位（项链/戒指/副手法器/箭袋/副刃）、其他职业（法师/弓手）、怪物与 BOSS 待扩展。
- Seedance 2.5 像素风技能**演示视频**（非游戏序列帧，用于宣发/效果展示）可选；游戏内动图已由 `anim/` 序列帧覆盖，无需依赖视频。
