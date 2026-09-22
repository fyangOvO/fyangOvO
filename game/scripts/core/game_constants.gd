## 「七傳說」全局常量（纯静态常量表，非 Autoload）
##
## 用法：直接以类名访问，例如 `GameConstants.Rarity.LEGENDARY`、
## `GameConstants.EQUIP_SLOT_COUNT`、`GameConstants.rarity_color(GameConstants.Rarity.EPIC)`。
##
## 定位：本文件是**唯一常量源**。任何脚本需要枚举 / 数值阈值 / 颜色时都必须引用此处，
## 禁止在业务脚本里硬编码字符串或魔数，否则阶段 3 调参会失控。
##
## 数据来源：
##   - 稀有度 8 档 / 部位 10 / 难度 I–V：任务清单阶段 1（1.2 常量表）
##   - 武器原型 10（主手 6 + 副手 4）：美术规范 0.7 **v1.5 附录**（权威），
##     并经 v1.6 消歧「主手 6 原型」措辞。详见第三节的版本漂移说明。
##   - 颜色 HEX：`art-style-and-ai-pipeline-phase0-0.7-2026-09-16.md` 1.3 / 1.4 节
##   - 数值系数（成长、掉落、经济）：`gdd-phase0-2026-09-16.md` 0.6 节（暂定，待仿真回测修正）
class_name GameConstants
extends RefCounted

# =============================================================================
# 一、稀有度 8 档
# =============================================================================
#
# 体系结构（GDD 0.3 节 3.2 v1.3「6 档线性 + 2 独立维度」）：
#   线性阶梯（严格递增）：白 → 蓝 → 黄 → 紫 → 橙 → 红
#   正交维度：套装绿 —— 并行的另一条路，单件弱于紫，集齐 6 件后 ≈ 红装
#   彩蛋维度：隐藏彩 —— 强度锚定橙装（不设更强），价值在唯一外观 + 可成长
#
#   单件强度排序：红 > 橙 ≈ 彩 > 绿（单件）> 紫 > 黄 > 蓝 > 白
#
# 顺序即枚举序号，**禁止调整**（存档、掉落表、数据文件均按 int / 顺序索引）。
enum Rarity {
	COMMON = 0,    ## 普通 · 白 —— 0 条词缀，仅基础属性
	MAGIC = 1,     ## 魔法 · 蓝 —— 1–2 条
	RARE = 2,      ## 稀有 · 黄 —— 3–4 条（上限 2 前 + 2 后）
	EPIC = 3,      ## 史诗 · 紫 —— 4–5 条（上限 3 前 + 2 后），可含 1 条强化词缀（数值 ×1.5）
	LEGENDARY = 4, ## 传说 · 橙 —— 5–6 条（上限 3 前 + 3 后），必含 1 条传奇特效
	MYTHIC = 5,    ## 神话 · 红 —— 普通词缀 6–7 条（上限 4 前 + 3 后）+ 1 条神话词缀（独立槽），必含传奇特效，基础属性上浮
	SET = 6,       ## 套装 · 绿 —— 3–5 条（上限 2 前 + 3 后）+ 1 条套装标记词缀（独立槽），必带 set_id，凑齐触发套装加成
	HIDDEN = 7,    ## 隐藏 · 彩 —— 5–6 条（上限 3 前 + 3 后）+ 1 条彩蛋标记词缀（独立槽），全池掉落权重极低
}

## 稀有度档数（数组尺寸校验用）
const RARITY_COUNT: int = 8

## 稀有度中文名（UI 显示用，索引对应 Rarity）
const RARITY_NAMES: Array[String] = [
	"普通", "魔法", "稀有", "史诗", "传说", "神话", "套装", "隐藏",
]

## 稀有度英文名（存档 / 日志 / 数据文件键名用，禁止本地化）
const RARITY_KEYS: Array[String] = [
	"common", "magic", "rare", "epic", "legendary", "mythic", "set", "hidden",
]

## 稀有度文字色（HEX）。
##
## 前 6 档为**线性阶梯**，后 2 档为**独立维度**（不参与线性排序）：
##   线性：白 → 蓝 → 黄 → 紫 → 橙 → 红
##   独立：套装（绿，正交分类）/ 隐藏（彩，彩蛋）
##
## 色值全部取自美术规范 0.7 v1.3 第 1.3 / 1.4 节：
##   神话红 `#FF2D55` 走新增的「神话/猩红」色系（色相 ~348°），
##   与「血/危险」`#C42B2B`（暗哑砖红，仅用于血条等 UI 语义）**色相与明度双重拉开**；
##   套装青绿 `#2FA37A` 走新增的「套装/青绿」色系（色相 ~160°），
##   与「毒/自然」`#3B7A44`（黄绿，仅用于元素/环境）区分。
##   隐藏彩实际渲染为 `PRISMATIC_GRADIENT` 六色渐变流动，此处为**单色回退值**。
const RARITY_COLORS: Array[Color] = [
	Color("C9D1D9"), # 普通 Common · 线性 —— 色板「近白」
	Color("4C8BF5"), # 魔法 Magic · 线性
	Color("F5C542"), # 稀有 Rare · 线性
	Color("A96BFF"), # 史诗 Epic · 线性
	Color("FF8A2B"), # 传说 Legendary · 线性
	Color("FF2D55"), # 神话 Mythic · 线性顶点（专属色，非血红）
	Color("2FA37A"), # 套装 Set · 正交（专属色，非毒绿）
	Color("F5D77A"), # 隐藏 Hidden · 彩蛋（单色回退；实际走 PRISMATIC_GRADIENT）
]

## 稀有度物品框颜色（美术规范 1.4 节「物品框」）
const RARITY_FRAME_COLORS: Array[Color] = [
	Color("3A424F"), # 普通：1px 实线 灰
	Color("4C8BF5"), # 魔法：1px 实线 蓝
	Color("F5C542"), # 稀有：2px 实线 黄
	Color("A96BFF"), # 史诗：2px 实线 紫 + 内发光
	Color("FF8A2B"), # 传说：3px 实线 橙 + 动态流光
	Color("FF2D55"), # 神话：3px 实线 红 + 金色双层外框（见 MYTHIC_GOLD_FRAME_COLOR）
	Color("2FA37A"), # 套装：2px 实线 青绿 + 四角菱形节点
	Color("F5D77A"), # 隐藏：6 色渐变描边（单色回退；实际走 PRISMATIC_GRADIENT）
]

## 神话装专属的**金色双层外框**色（美术规范 1.4 节「问题 1」）。
## 作用：让色弱玩家靠「有没有金边」即可把神话红与血条/危险红分开 —— 不依赖色相。
const MYTHIC_GOLD_FRAME_COLOR: Color = Color("F5D77A")

## 血条 / 危险语义红（美术规范 0.7 v1.5 附录「实现要点 3」）。
##
## ⚠️ **与神话红 `#FF2D55` 是两个独立常量，严禁合并成一个「红」。**
##    神话红走「神话/猩红」色系（色相 ~348°、高饱和高亮，用于掉落辉光与物品框）；
##    血条红 `#C42B2B` 是暗哑砖红，只用于血条、受伤闪屏等 UI 语义。
##    合并会造成两个后果：① 玩家分不清「掉了神话装」和「我正在掉血」；
##    ② 色弱玩家失去「金边 vs 无金边」之外的第二个区分依据。
const HEALTH_BAR_RED: Color = Color("C42B2B")

## 隐藏（彩蛋）装的六色渐变。
## 美术规范 1.4 节「问题 2」定稿：**不用色相循环 Shader**，改用「固定 6 色渐变 + 相位流动」，
## 6 色全部取自 48 色板的辉光色阶。渲染方式为 6×1 渐变贴图 + `TIME` 驱动 UV 偏移，
## `Filter = Nearest`，按整数像素步进。
const PRISMATIC_GRADIENT: Array[Color] = [
	Color("E8573F"), # 红（血 · 辉光）
	Color("FF8A2B"), # 橙（传说 · 文字色）
	Color("F5D77A"), # 黄（金 · 辉光）
	Color("6FB35C"), # 绿（自然 · 辉光）
	Color("6E9BE8"), # 蓝（冰 · 辉光）
	Color("B07DE0"), # 紫（虚空 · 辉光）
]

## 稀有度框线宽度（px）。
## 美术规范 1.4 节：线性档 1/1/2/2/3/3；套装 2px（靠形状而非粗细区分）；隐藏 3px 渐变。
const RARITY_FRAME_WIDTHS: Array[int] = [1, 1, 2, 2, 3, 3, 2, 3]

## 稀有度地面光柱高度（px）。普通档无光柱（0）。
## 美术规范 1.4 节：线性档 0/8/16/24/40/56；套装走菱形环（32px，换形状）；隐藏 64px 分段柱。
const RARITY_BEAM_HEIGHTS: Array[int] = [0, 8, 16, 24, 40, 56, 32, 64]

## 光柱形状（美术规范 1.4 节「问题 3」的四个差异维度之一）
enum BeamShape {
	NONE = 0,         ## 无光柱，仅 1px 深描边
	LINE = 1,         ## 直线柱
	LINE_PULSE = 2,   ## 直线柱 + 脉动
	LINE_RING = 3,    ## 直线柱 + 地面光环
	LINE_BURST = 4,   ## 直线柱 + 地面爆闪 + 粒子
	LINE_FIRERING = 5,## 直线柱 + 地面持续火环 + 上升金色粒子
	DIAMOND_RING = 6, ## 菱形环（套装专用：换形状，不比高度）
	GRADIENT_SEG = 7, ## 6 色分段柱 + 上升星点（彩蛋专用）
}

const RARITY_BEAM_SHAPES: Array[int] = [
	BeamShape.NONE, BeamShape.LINE, BeamShape.LINE_PULSE, BeamShape.LINE_RING,
	BeamShape.LINE_BURST, BeamShape.LINE_FIRERING, BeamShape.DIAMOND_RING, BeamShape.GRADIENT_SEG,
]

## 框线样式（第四个差异维度，专治「同粗细难区分」）
enum FrameStyle {
	SOLID = 0,            ## 实线
	SOLID_GLOW = 1,       ## 实线 + 内发光
	SOLID_FLOW = 2,       ## 实线 + 动态流光
	SOLID_GOLD_DOUBLE = 3,## 红 + 金色双层外框（神话专属）
	SOLID_DIAMOND = 4,    ## 青绿 + 四角菱形节点（套装专属）
	GRADIENT_FLOW = 5,    ## 6 色渐变流动（彩蛋专属）
}

const RARITY_FRAME_STYLES: Array[int] = [
	FrameStyle.SOLID, FrameStyle.SOLID, FrameStyle.SOLID, FrameStyle.SOLID_GLOW,
	FrameStyle.SOLID_FLOW, FrameStyle.SOLID_GOLD_DOUBLE, FrameStyle.SOLID_DIAMOND,
	FrameStyle.GRADIENT_FLOW,
]

## 稀有度的**类别**，用于美术规范 1.4 节要求的「两级判断」：
## 玩家先分清「线性 / 套装 / 彩蛋」，再判断具体档位，降低 8 档的认知负荷。
enum RarityCategory {
	LINEAR = 0,   ## 线性强度阶梯（白/蓝/黄/紫/橙/红）
	ORTHOGONAL = 1,## 正交分类（套装绿，并行获取路径）
	EASTER_EGG = 2,## 彩蛋（隐藏彩）
}

const RARITY_CATEGORIES: Array[int] = [
	RarityCategory.LINEAR, RarityCategory.LINEAR, RarityCategory.LINEAR,
	RarityCategory.LINEAR, RarityCategory.LINEAR, RarityCategory.LINEAR,
	RarityCategory.ORTHOGONAL, RarityCategory.EASTER_EGG,
]

## 稀有度掉落权重基准（百分数，**普通怪**口径，GDD 0.6 节 6.1「8 档掉落率曲线」）。
##
## 硬约束：新增档位（红/绿/彩）的概率**全部从白/蓝低档位挤出**，
##         橙装概率与原 5 档表完全一致（0.05%），保证「约 5 局 1 件橙」的节奏不变。
##
## 注意：掉落逻辑必须使用 `game/data/loot_tables/` 中的数据，本表仅作校验基准。
const RARITY_DROP_BASE_PERCENT: Array[float] = [
	78.02, # 普通
	17.55, # 魔法
	3.50,  # 稀有
	0.45,  # 史诗
	0.05,  # 传说 ← 与原 5 档表一致（硬约束）
	0.02,  # 神话（仅梦魇 II 及以上掉落）
	0.40,  # 套装（因需集齐 6 件，故频率高于橙）
	0.01,  # 隐藏（约 98 局 1 件）
]

## 各稀有度的词缀条数区间 [最小, 最大]（GDD 0.3 节 3.2「稀有度 8 档体系」表）
const RARITY_AFFIX_RANGE: Array[Vector2i] = [
	Vector2i(0, 0), # 普通：0（仅基础属性）
	Vector2i(1, 2), # 魔法
	Vector2i(3, 4), # 稀有
	Vector2i(4, 5), # 史诗
	Vector2i(5, 6), # 传说
	Vector2i(6, 7), # 神话（仅普通前/后缀条数；神话词缀为独立槽，不计入）
	Vector2i(3, 5), # 套装（单件弱于紫，靠集齐补回）
	Vector2i(5, 6), # 隐藏（强度锚定橙装）
]

## 各稀有度的前缀 / 后缀条数上限。
##
## **已确认**：权威来源为 GDD 0.3 节 **3.2.3「前后缀上限拆分表」（v1.6 拍板，唯一权威）**，
## 本文件数组与该表逐项一致。不变式：`前缀上限 + 后缀上限 = 词缀条数上限`
## （后者见 RARITY_AFFIX_RANGE，二者由 main.gd 自检校验）。
##
## 拆分结果：黄 2+2 / 紫 3+2 / 橙 3+3 / 红 4+3 / 绿 2+3 / 彩 3+3。
##
## ⚠️ **计数口径（GDD 唯一定义）**：表中「词缀条数」只算**普通前 / 后缀**；
##    神话词缀 / 套装标记词缀 / 彩蛋标记词缀 / 传奇特效均为**特殊槽，不计入条数**。
##    因此不要把特殊槽算进 RARITY_AFFIX_RANGE。
const RARITY_PREFIX_LIMIT: Array[int] = [0, 1, 2, 3, 3, 4, 2, 3]
const RARITY_SUFFIX_LIMIT: Array[int] = [0, 1, 2, 2, 3, 3, 3, 3]

## 神话词缀的最低稀有度要求（神话装必含 1 条「全属性 +X%」词缀）
const MYTHIC_AFFIX_MIN_RARITY: int = Rarity.MYTHIC


# =============================================================================
# 二、装备部位 10 个
# =============================================================================
enum EquipSlot {
	HELM = 0,       ## 头部 —— 生命 / 抗性
	CHEST = 1,      ## 胸甲 —— 护甲 / 生命
	GLOVES = 2,     ## 手套 —— 攻击速度 / 暴击
	LEGS = 3,       ## 腿部 —— 护甲 / 移动
	BOOTS = 4,      ## 鞋子 —— 移动速度 / 闪避
	MAIN_HAND = 5,  ## 主手 —— 攻击力（最高权重）
	OFF_HAND = 6,   ## 副手 —— 格挡 / 攻击力
	AMULET = 7,     ## 项链 —— 全属性 / 暴击伤害
	RING_A = 8,     ## 戒指 A —— 暴击 / 生命偷取
	RING_B = 9,     ## 戒指 B —— 可与 A 叠同名不同词缀
}

const EQUIP_SLOT_COUNT: int = 10

const EQUIP_SLOT_NAMES: Array[String] = [
	"头部", "胸甲", "手套", "腿部", "鞋子", "主手", "副手", "项链", "戒指 A", "戒指 B",
]

const EQUIP_SLOT_KEYS: Array[String] = [
	"helm", "chest", "gloves", "legs", "boots", "main_hand", "off_hand", "amulet", "ring_a", "ring_b",
]

## 装备槽 UI 图标尺寸（美术规范 2.6 节：装备槽 64×64，背包格 48×48）
const EQUIP_SLOT_ICON_SIZE: int = 64
const INVENTORY_GRID_SIZE: int = 48


# =============================================================================
# 三、武器 / 副手视觉原型
# =============================================================================
#
# 权威来源：美术规范 0.7 **v1.5 附录「供工程实现的常量对照」** —— `WeaponArchetype` 共 **10 个**
#   = 主手 6（剑 / 斧 / 锤 / 匕首 / 法杖 / 长弓）+ 副手 4（盾 / 法器 / 箭袋 / 副刃）。
#
# ⚠️ 版本漂移史（别再走回头路）：
#   - 0.7 v1.1 写「剑/斧/弓/法杖/匕首/盾」6 个，把盾误放进主手、且漏了锤
#   - 0.7 v1.2 修正为「主手 6 + 副手 4」，但工程侧仍按 v1.1 实现了 7 个
#   - 0.7 v1.5 专门加附录把枚举钉死；v1.6 又消歧了「主手 6 原型」的措辞
#   - 本枚举现与 v1.5/v1.6 对齐 = 10 个
#
# 新增的 FOCUS / QUIVER / OFFBLADE **追加在末尾**，因此不打乱既有索引，
# 已录入的武器底材 JSON（用字符串键映射）无需改动。
enum WeaponArchetype {
	SWORD = 0,    ## 剑（主手）
	AXE = 1,      ## 斧（主手）
	HAMMER = 2,   ## 锤（主手）
	DAGGER = 3,   ## 匕首（主手）
	STAFF = 4,    ## 法杖（主手）
	LONGBOW = 5,  ## 长弓（主手）
	SHIELD = 6,   ## 盾（副手）
	FOCUS = 7,    ## 法器（副手，轻量原型：持握静态 + 微光）
	QUIVER = 8,   ## 箭袋（副手，背部静态贴图，不参与攻击动画）
	OFFBLADE = 9, ## 副刃（副手，复用匕首精灵，0 新增帧）
}

const WEAPON_ARCHETYPE_COUNT: int = 10

const WEAPON_ARCHETYPE_NAMES: Array[String] = [
	"剑", "斧", "锤", "匕首", "法杖", "长弓", "盾", "法器", "箭袋", "副刃",
]

const WEAPON_ARCHETYPE_KEYS: Array[String] = [
	"sword", "axe", "hammer", "dagger", "staff", "longbow", "shield",
	"focus", "quiver", "offblade",
]

## 主手可用的原型（副手 4 个不可作主手）
const MAIN_HAND_ARCHETYPES: Array[int] = [
	WeaponArchetype.SWORD, WeaponArchetype.AXE, WeaponArchetype.HAMMER,
	WeaponArchetype.DAGGER, WeaponArchetype.STAFF, WeaponArchetype.LONGBOW,
]

## 副手可用的原型（美术规范 0.7 v1.5 附录）
const OFF_HAND_ARCHETYPES: Array[int] = [
	WeaponArchetype.SHIELD, WeaponArchetype.FOCUS,
	WeaponArchetype.QUIVER, WeaponArchetype.OFFBLADE,
]

## 各原型的视觉规格（美术规范 3.1 节：每原型 4 方向 × 8 帧）
const WEAPON_ANIM_DIRECTIONS: int = 4
const WEAPON_ANIM_FRAMES: int = 8

## 各原型的**美术帧数预算**（美术规范 0.7 v1.5 附录 2.6 节分项表）。
## 供阶段 6 按原型逐个勾进度 —— 排期单位是「每个原型多少帧」，不是合计。
## 索引与 `WeaponArchetype` 一一对应。
##
## ⚠️ 规范正文两处写「合计 245 帧」，但按其自身分项表逐项相加为 **244**
##    （主手 6×32=192 + 副手 32+16+4+0=52）。此处以**分项表为准**（244），
##    差异 1 帧已上报 designer 核对。若规范改为 245，只需改本表。
const WEAPON_ARCHETYPE_FRAMES: Array[int] = [
	32, 32, 32, 32, 32, 32,  # 主手 6 原型：各 4 方向 × 8 帧
	32,                      # 盾：含格挡姿势
	16,                      # 法器：轻量原型
	4,                       # 箭袋：背部静态贴图
	0,                       # 副刃：复用匕首精灵，0 新增帧
]

## 副手原型在美术资产上的复用关系：原型 → 实际取图的原型。
## `-1` 表示该原型自己出图；非 -1 表示复用目标原型的精灵（镜像到副手）。
const WEAPON_ARCHETYPE_SPRITE_SOURCE: Array[int] = [
	-1, -1, -1, -1, -1, -1,  # 主手 6 原型各自出图
	-1,                      # 盾：独立出图
	-1,                      # 法器：独立出图
	-1,                      # 箭袋：独立出图（静态贴图）
	WeaponArchetype.DAGGER,  # 副刃：复用匕首
]


# =============================================================================
# 四、词缀分类与前后缀
# =============================================================================
enum AffixCategory {
	ATTACK = 0,   ## 攻击类
	DEFENSE = 1,  ## 防御类
	RESOURCE = 2, ## 资源类
	SPECIAL = 3,  ## 特殊类
}

const AFFIX_CATEGORY_COUNT: int = 4

const AFFIX_CATEGORY_NAMES: Array[String] = ["攻击", "防御", "资源", "特殊"]
const AFFIX_CATEGORY_KEYS: Array[String] = ["attack", "defense", "resource", "special"]

## 词缀位置：前缀 = 数值型（如 +攻击力）；后缀 = 机制型（如 +暴击率）
enum AffixPosition {
	PREFIX = 0,
	SUFFIX = 1,
}

const AFFIX_POSITION_NAMES: Array[String] = ["前缀", "后缀"]

## 词缀数值随物品等级缩放的线性系数（GDD 0.6 节 6.2）：
## Value(iLvl) = Base × (1 + 0.085 × (iLvl - 1))
const AFFIX_ILVL_SCALE_PER_LEVEL: float = 0.085

## 装备主属性（基础属性）随物品等级缩放的线性系数（GDD 0.6 节 6.2）：
## Item_Stat(iLvl) = S0 × (1 + 0.12 × (iLvl - 1))
const ITEM_STAT_ILVL_SCALE_PER_LEVEL: float = 0.12

## 词缀 roll 品质 5 阶（GDD 0.3 节 3.3），用于 UI 染色
const AFFIX_ROLL_QUALITY_TIERS: Array[float] = [0.60, 0.75, 0.90, 1.00, 1.15]

## 词缀 roll 品质对应的 UI 颜色（灰/绿/蓝/黄/橙）
const AFFIX_ROLL_QUALITY_COLORS: Array[Color] = [
	Color("6B7688"), # 0.60 灰
	Color("6FB35C"), # 0.75 绿
	Color("4C8BF5"), # 0.90 蓝
	Color("F5C542"), # 1.00 黄
	Color("FF8A2B"), # 1.15 橙
]

## 史诗档「强化词缀」数值倍率（GDD 0.3 节 3.2）
const EPIC_EMPOWERED_AFFIX_MULT: float = 1.5


# =============================================================================
# 五、难度层级（梦魇 I–V）
# =============================================================================
enum DifficultyTier {
	NM1 = 0, ## 梦魇 I
	NM2 = 1, ## 梦魇 II
	NM3 = 2, ## 梦魇 III
	NM4 = 3, ## 梦魇 IV
	NM5 = 4, ## 梦魇 V
}

const DIFFICULTY_TIER_COUNT: int = 5

const DIFFICULTY_TIER_NAMES: Array[String] = [
	"梦魇 I", "梦魇 II", "梦魇 III", "梦魇 IV", "梦魇 V",
]

const DIFFICULTY_TIER_KEYS: Array[String] = ["nm1", "nm2", "nm3", "nm4", "nm5"]

## 难度层级系数：**HP 1.08^n / DMG 1.23^n**（GDD 0.6 节 6.4 **v1.5 定稿 = 仿真方案 D**）
##
## 指数约定：`n = tier`（梦魇 I = 0），故梦魇 V = 1.08^4 = ×1.36 / 1.23^4 = ×2.29。
##
## 设计意图 —— **DMG 主导轴**：层级差异靠「更致命」而非「更海绵」。
##   梦魇 V 怪伤害 ×2.29，HP 仅 ×1.36。产品原则已确认为「**高层级允许被秒**」。
##
## 数值来源链（勿再漂移）：
##   GDD 6.3/6.4 v1.5 定稿 ← sim-report 9.3 / 10.4 节方案 D ← 独立复现原始缺陷
##   （原 ×1.8^n 下 TTK 17.62s / SurvT 99 格越界 / 满装被 4 杂兵围住 0.56s 即死）
##
## ⚠️ 结构性约束（GDD 6.4 记录，勿忘）：
##   在「5 个层级共用同一套装备（难度不提升 iLvl）」+「TTK 必须落窄区间」两条约束下，
##   层级系数存在数学上限 `tierHP ≤ (TTK_max / TTK_min)^(1/4)`。
##   方案 D 是**主动放开 SurvT 下沿为阶梯窗口**才换来 1.08^n / 1.23^n 这组值 ——
##   即 **6.3 的怪物基础值与 6.4 的层级系数是同一方案的配套，不可拆分使用**。
const DIFFICULTY_HP_FACTOR_BASE: float = 1.08
const DIFFICULTY_DMG_FACTOR_BASE: float = 1.23

## 每层难度对掉落稀有度权重的修正（GDD 0.6 节 6.1「修正规则」，v1.3 扩至 8 档）
const DIFFICULTY_COMMON_WEIGHT_MULT: float = 0.85  ## 白/蓝权重 ×0.85
const DIFFICULTY_RARE_WEIGHT_MULT: float = 1.15    ## 黄权重 ×1.15
const DIFFICULTY_EPIC_WEIGHT_MULT: float = 1.30    ## 紫/橙权重 ×1.30
const DIFFICULTY_SET_WEIGHT_MULT: float = 1.10     ## 套装绿权重 ×1.10
const DIFFICULTY_MYTHIC_WEIGHT_MULT: float = 1.50  ## 神话红权重 ×1.50
## 隐藏彩权重**不随难度变化**（彩蛋的稀有性不该被难度稀释）

## 神话红装的掉落门槛：**仅梦魇 II 及以上**（GDD 0.3 节 3.2.2）。
## 难度 I（普通关卡）不掉红装，保证红装是「终局追求」而非「刷白图出货」。
const MYTHIC_MIN_DIFFICULTY_TIER: int = DifficultyTier.NM2


# =============================================================================
# 六、关卡与角色成长
# =============================================================================
const LEVEL_MIN: int = 1
const LEVEL_MAX: int = 20

const ACCOUNT_LEVEL_MIN: int = 1
const ACCOUNT_LEVEL_MAX: int = 60

## 局内等级上限（GDD 0.4 节 4.1）
const RUN_LEVEL_MIN: int = 1
const RUN_LEVEL_MAX: int = 10

## 升级所需经验：XP_ToNext(L) = BASE × L^1.6（GDD 0.5 节 5.1）
##
## **v1.8 定稿：BASE = 180**（由 100 上调，team-lead 拍板以 `sim-report §10.5.6` 为准）。
## 上调理由：单关杂兵数由 150 上调到 **269** 后，经验产出超预算 ×2.23，
## 需按比例上调曲线才能保住「前期 3–5 关升 1 级、后期 8–12 关升 1 级」的关/级节奏。
##
## ⚠️ 历史：GDD v1.7 正文曾写 185，与 sim-report 的 180 不一致；
##    team-lead 已裁定 **以 sim-report 的 180 为准**，GDD 正文的 185 属笔误（待 product-reviewer 同步）。
const XP_CURVE_BASE: float = 180.0
const XP_CURVE_EXPONENT: float = 1.6

## 角色裸装基础属性（GDD 0.6 节 6.2）：Base(L) = Base1 × (1+g)^(L-1)
const BASE_HP_AT_L1: float = 150.0
const BASE_HP_GROWTH: float = 0.11
const BASE_AD_AT_L1: float = 12.0
const BASE_AD_GROWTH: float = 0.10
const BASE_ARMOR_AT_L1: float = 6.0
const BASE_ARMOR_GROWTH: float = 0.10

## 护甲减伤公式：DR(L) = ARM / (ARM + 50 × L)（GDD 0.6 节 6.6）
const ARMOR_DR_CONSTANT_PER_LEVEL: float = 50.0

## 怪物数值基准（GDD 0.6 节 6.3 **v1.5 定稿 = 仿真方案 D 配套**）
##
##   Monster_HP(L)  = 100.7 × 1.284^(L-1)
##   Monster_DMG(L) =  5.61 × 1.218^(L-1)
##
## ⚠️ **与 6.4 的层级系数（1.08^n / 1.23^n）是同一方案 D 的配套，不可拆分使用。**
##
## v1.5 修订说明（GDD 6.3）：
##   - HP base 60 → 100.7（×1.68）：这是原 TTK 全表偏低的**根因** —— 怪物血量过低导致一击秒杀
##   - DMG base 8 → 5.61、growth 1.24 → 1.218：降低单发伤害，配合 SurvT 阶梯窗口
##   - HP growth 1.28 → 1.284：基本不变（仿真独立反解 1.2840，与原值 1.28 吻合）
##
## 校验锚点（GDD 6.3 表，可用于回归）：
##   L1 普通怪：HP 100.7 / DMG 5.61
##   L20 普通怪：HP ≈ 11,635 / DMG ≈ 237.83
const MONSTER_HP_AT_L1: float = 100.7
const MONSTER_HP_GROWTH: float = 1.284
const MONSTER_DMG_AT_L1: float = 5.61
const MONSTER_DMG_GROWTH: float = 1.218

## 怪物档位倍率
const MONSTER_ELITE_HP_MULT: float = 4.5
const MONSTER_BOSS_HP_MULT: float = 28.0

## 装备需求等级：ReqLv = max(1, iLvl - 2)（GDD 0.3 节 3.6）
const ITEM_REQ_LEVEL_OFFSET: int = 2

## 越级惩罚：玩家等级 < 关卡等级 - 3 时，紫/橙/**红** 概率 ×0.5（GDD 0.3 节 3.6 / 0.6 节 6.1）
const OVERLEVEL_PENALTY_LEVEL_GAP: int = 3
const OVERLEVEL_PENALTY_MULT: float = 0.5

## 强化上限（GDD 0.3 节 3.4 / 3.2.2）
const FORGE_MAX_LEVEL: int = 10        ## 常规装备 +10
const FORGE_MAX_LEVEL_MYTHIC: int = 12 ## 神话红装可强化至 +12
const FORGE_STAT_BONUS_PER_LEVEL: float = 0.05

## 单件满强化（+10）各档魔石消耗（GDD 6.5 节，v1.8 定稿合计 = 106 个）。
##
## 索引即目标强化等级 - 1（`FORGE_STONE_COST[0]` = 从 +0 强化到 +1 的花费）。
## 分档：+1~+3 各 3 / +4~+6 各 7 / +7~+8 各 13 / +9~+10 各 25
##
## ⚠️ **末档取 25，不是 GDD 6.5 正文写的 26。**
##    GDD 6.5 的原文分档（… / +9~+10 各 26）逐项相加 = **108**，
##    与已拍板的总数 **106** 差 2。team-lead 裁定以 `sim-report §10.5.6` 的 **106** 为准，
##    并明确末档取 **25**（3+3+3+7+7+7+13+13+25+25 = 106）。
##    即：**末档 25 是使总数落在 106 的定稿值，GDD 6.5 正文的 26 属笔误**（待 product-reviewer 同步）。
##
## 本数组长度必须 == `FORGE_MAX_LEVEL`（+10 共 10 档），已纳入骨架自检。
const FORGE_STONE_COST: Array[int] = [3, 3, 3, 7, 7, 7, 13, 13, 25, 25]

## 单件满强化（+10）所需魔石总数（应 == 106，见 GDD 6.5）
static func forge_total_stones() -> int:
	var total: int = 0
	for c in FORGE_STONE_COST:
		total += c
	return total

## 单局魔石产出估算（GDD 0.5 节 5.3，v1.8 按 269 杂兵 / 9 精英重算）
const FORGE_MATERIAL_PER_RUN_ESTIMATE: int = 59


# =============================================================================
# 六·五、套装机制（绿装）与彩蛋机制（隐藏彩）—— GDD 0.3 节 3.2.1 / 3.2.2
# =============================================================================

## 每组套装的件数（覆盖 6 个固定部位槽）
const SET_PIECE_COUNT: int = 6

## 套装加成触发阈值（逐级解锁，鼓励「混搭过渡 → 集齐」）
const SET_THRESHOLDS: Array[int] = [2, 4, 6]

## 全项目套装数量（用于徽记图标的复用核算）
const SET_TOTAL_COUNT: int = 6

## 套装掉落「智能偏置」：有该概率优先掉落玩家**当前未拥有**的该套部件，
## 避免单机自玩卡在「就差最后一件」。
const SET_SMART_BIAS_CHANCE: float = 0.60

## 套装徽记图标尺寸（嵌在物品框右上角，GDD 3.2.1 / 美术规范 1.4「问题 4」）
const SET_EMBLEM_SIZE: int = 16

## 套装件数徽章尺寸（背包图标右下角，如 "4/6"）
const SET_BADGE_SIZE: int = 16

## 套装进度条分段数（= SET_PIECE_COUNT，对应 2/4/6 三个阈值）
const SET_PROGRESS_BAR_HEIGHT: int = 8
const SET_PROGRESS_BAR_SEGMENT_GAP: int = 2

## 隐藏（彩蛋）装的可成长上限（GDD 3.2.2：每 1000 击杀 +1% 某属性，上限 +20%）
const HIDDEN_GROWTH_MAX_BONUS: float = 0.20

## 隐藏装的期望掉落节奏（件/局），仅用于仿真校验
const HIDDEN_EXPECTED_DROPS_PER_RUN: float = 0.010

## 隐藏装不可分解、不可交易（防误操作，GDD 3.2.2）
const HIDDEN_UNDISMANTLABLE: bool = true


# =============================================================================
# 七、局内增益上限（GDD 0.4 节 4.4）
# =============================================================================
const RUN_BUFF_ATTACK_CAP: float = 0.30
const RUN_BUFF_HP_CAP: float = 0.30
const RUN_BUFF_ATTACK_SPEED_CAP: float = 0.20
const RUN_BUFF_CRIT_CAP: float = 0.20


# =============================================================================
# 八、渲染与像素规格
# =============================================================================
const TILE_SIZE: int = 32             ## 地图 tile 尺寸
## 主角精灵**螢幕畫布**（px）。權威消費點：`PlayerController._game_scale_for()`
## —— 顯示縮放 = 本值 ÷ 素材畫布，故換任何尺寸的素材，螢幕上的角色都鎖在 48px。
const CHARACTER_SPRITE_SIZE: int = 48
const SPRITE_ANCHOR_OFFSET: Vector2 = Vector2(24, 44) ## 主角脚底中心锚点（美术规范 2.1）

const VIEWPORT_WIDTH: int = 1920
const VIEWPORT_HEIGHT: int = 1080

## 相机基准缩放（2× = 一屏可见 30×16.9 tile）。
##
## 取值依据：1920×1080 原生视口 + 32px tile ⇒ 1× 下一屏可见 **60 tile 宽**，
## 远大于同类作品的 20–30 tile，角色会小得像蚂蚁、移动"看起来"很慢。
## 2× 后可见 30 tile 宽，落在同类区间上沿。
##
## ⚠️ 这是**全项目唯一的相机缩放来源**。`playtest.tscn` / 关卡容器 / 将来任何
##    预览场景都必须引用本常量（.tscn 里手写的 zoom 是硬编码，改这里不会同步 —— 
##    所以关卡容器改为在代码里设 `camera.zoom = CAMERA_ZOOM_BASE`）。
##
## 关联：`PlayerController.LOCAL_MOVE_SPEED` 的注释里提到「感知速度会随相机缩放翻倍」，
## 该值按世界坐标真实速度定义，**不因缩放而变**。调手感时请连带考虑本常量。
const CAMERA_ZOOM_BASE: Vector2 = Vector2(1, 1)

## 美术规范 1.3 节中性色阶（UI 用）
const COLOR_PANEL_BG: Color = Color("1E232B")
const COLOR_DARK_BG: Color = Color("14171C")
const COLOR_BORDER: Color = Color("3A424F")
const COLOR_TEXT_NORMAL: Color = Color("B3BCC9")
const COLOR_TEXT_BRIGHT: Color = Color("DCE2E8")
const COLOR_ACCENT_GOLD: Color = Color("D9A521")


# =============================================================================
# 八·五、48 色主色板（美术规范 0.7 v1.6 附录 PALETTE，任务 1.6）
# =============================================================================
#
# 唯一色源铁律（美术规范 1.2 / 附录）：
#   · 烘焙图像资产（PNG 精灵 / 图标 / tile）全部像素必须落在 `PALETTE_ALL`
#     （44 已定义色，阶段 11 收尾 DBCC85 入中性基底消耗 1 个 D 组预留槽）内 —— 阶段 6 资产校验以此为准。
#   · 运行时特效层（Shader 流光 / 光柱 / 粒子）颜色须落在
#     `PALETTE_ACCENT + PALETTE_RARITY_SEMANTIC` 内，禁止引入色板外颜色。
#   · 彩蛋装 `PRISMATIC_GRADIENT` 的 6 色取自 B 系辉光阶，天然合规。
#
# A. 中性基底（11）
const PALETTE_NEUTRAL: Array[Color] = [
	Color("0B0D10"), ## 近黑（面板底）
	Color("14171C"), ## 深槽（物品格 / 血条槽）
	Color("1E232B"), ## 中灰蓝（按钮 Normal）
	Color("2A313B"), ## 亮灰蓝（按钮 Hover）
	Color("3A424F"), ## 边框（描边）
	Color("4E5866"), ## 高光（面板顶线）
	Color("6B7688"), ## 灰（禁用文字）
	Color("8C97A8"), ## 浅灰（次要文字）
	Color("B3BCC9"), ## 正文（常规文字）
	Color("DCE2E8"), ## 亮白（关键数值）
	Color("DBCC85"), ## 暖金（BuffHud 文字色，亲缘：金/光·亮；阶段 11 收尾 team-lead 裁定 L864 方案 A 配套）
]

## B. 强调色系（7 系 × 4 = 28，顺序恒为 暗/中/亮/辉光）
const PALETTE_ACCENT: Array[Color] = [
	# 血 / 危险
	Color("4A0E12"), Color("8C1A1F"), Color("C42B2B"), Color("E8573F"),
	# 毒 / 自然
	Color("0F2417"), Color("1E4A2B"), Color("3B7A44"), Color("6FB35C"),
	# 魔法 / 冰
	Color("101A3A"), Color("1F3468"), Color("3A5FB0"), Color("6E9BE8"),
	# 金 / 光
	Color("4A3208"), Color("8C6510"), Color("D9A521"), Color("F5D77A"),
	# 虚空 / 奥术紫
	Color("2A1440"), Color("4E2478"), Color("7E44B8"), Color("B07DE0"),
	# 神话 / 猩红
	Color("4A0816"), Color("B01038"), Color("FF2D55"), Color("FF7A96"),
	# 套装 / 青绿
	Color("0A2B22"), Color("1B6B52"), Color("2FA37A"), Color("6FE0B4"),
]

## C. 稀有度语义色（5）
const PALETTE_RARITY_SEMANTIC: Array[Color] = [
	Color("C9D1D9"), Color("4C8BF5"), Color("F5C542"), Color("A96BFF"), Color("FF8A2B"),
]

## 全部已定义色（A + B + C = 44）。D 组 4 色为预留，未定义（原 5 色，阶段 11 收尾 DBCC85 占用 1）。
const PALETTE_ALL: Array[Color] = PALETTE_NEUTRAL + PALETTE_ACCENT + PALETTE_RARITY_SEMANTIC


## 判断颜色是否落在 48 色板已定义色内（含 Alpha 容差）。
## 用途：阶段 6 资产校验、UI 主题构建、运行时特效层颜色抽查。
static func palette_contains(c: Color, alpha_tolerance: float = 0.02) -> bool:
	for p in PALETTE_ALL:
		if absf(c.r - p.r) < 0.0005 and absf(c.g - p.g) < 0.0005 and absf(c.b - p.b) < 0.0005 \
				and absf(c.a - p.a) < alpha_tolerance:
			return true
	return false


## 返回**不在 48 色板内**的 UI 相关颜色常量名（空 = 全部合规）。
## 唯一色源铁律的可执行化：新加 UI 色若忘了查色板，骨架自检直接报红。
static func ui_colors_not_in_palette() -> Array[String]:
	var bad: Array[String] = []
	var check := func(name: String, c: Color) -> void:
		if not palette_contains(c):
			bad.append("%s(%s)" % [name, c.to_html(false)])
	# 八·六 UI 主题色
	check.call("UI_PANEL_BG", UI_PANEL_BG)
	check.call("UI_PANEL_BORDER", UI_PANEL_BORDER)
	check.call("UI_PANEL_HIGHLIGHT", UI_PANEL_HIGHLIGHT)
	check.call("UI_BTN_NORMAL", UI_BTN_NORMAL)
	check.call("UI_BTN_HOVER", UI_BTN_HOVER)
	check.call("UI_BTN_PRESSED", UI_BTN_PRESSED)
	check.call("UI_BTN_BORDER", UI_BTN_BORDER)
	check.call("UI_BTN_HOVER_BORDER", UI_BTN_HOVER_BORDER)
	check.call("UI_SLOT_BG", UI_SLOT_BG)
	check.call("UI_HP_BAR_BG", UI_HP_BAR_BG)
	check.call("UI_HP_BAR_GRADIENT_FROM", UI_HP_BAR_GRADIENT_FROM)
	check.call("UI_HP_BAR_GRADIENT_TO", UI_HP_BAR_GRADIENT_TO)
	check.call("UI_HP_BAR_OUTLINE", UI_HP_BAR_OUTLINE)
	check.call("UI_SHIELD_COLOR", UI_SHIELD_COLOR)
	check.call("UI_MP_BAR_GRADIENT_FROM", UI_MP_BAR_GRADIENT_FROM)
	check.call("UI_MP_BAR_GRADIENT_TO", UI_MP_BAR_GRADIENT_TO)
	check.call("UI_DMG_NORMAL_COLOR", UI_DMG_NORMAL_COLOR)
	check.call("UI_DMG_CRIT_COLOR", UI_DMG_CRIT_COLOR)
	check.call("UI_DMG_OUTLINE", UI_DMG_OUTLINE)
	check.call("UI_TALENT_LIT", UI_TALENT_LIT)
	check.call("UI_TALENT_AVAILABLE", UI_TALENT_AVAILABLE)
	check.call("UI_TALENT_LOCKED", UI_TALENT_LOCKED)
	check.call("UI_TEXT_NORMAL", UI_TEXT_NORMAL)
	check.call("UI_TEXT_BRIGHT", UI_TEXT_BRIGHT)
	check.call("UI_TEXT_DISABLED", UI_TEXT_DISABLED)
	# 八·五 之前遗留的通用 UI 色（八·六 的别名，必须同步在色板内）
	check.call("COLOR_PANEL_BG", COLOR_PANEL_BG)
	check.call("COLOR_DARK_BG", COLOR_DARK_BG)
	check.call("COLOR_BORDER", COLOR_BORDER)
	check.call("COLOR_TEXT_NORMAL", COLOR_TEXT_NORMAL)
	check.call("COLOR_TEXT_BRIGHT", COLOR_TEXT_BRIGHT)
	check.call("COLOR_ACCENT_GOLD", COLOR_ACCENT_GOLD)
	# 语义色（血条红 / 神话金边 / 稀有度 / 品质档）
	check.call("HEALTH_BAR_RED", HEALTH_BAR_RED)
	check.call("MYTHIC_GOLD_FRAME_COLOR", MYTHIC_GOLD_FRAME_COLOR)
	for i in RARITY_COLORS.size():
		check.call("RARITY_COLORS[%d]" % i, RARITY_COLORS[i])
	for i in AFFIX_ROLL_QUALITY_COLORS.size():
		check.call("AFFIX_ROLL_QUALITY_COLORS[%d]" % i, AFFIX_ROLL_QUALITY_COLORS[i])
	# 八·六·补 局内三选一面板（ChoicePanel）语义色 —— 阶段 11
	# 登记理由：`choice_panel.gd` 手工建卡、不走主题，是唯一会「绕开唯一色源」的 UI。
	# 把它的色值纳入本函数 ⇒ 纳入 `self_check` 的「UI 颜色常量全部取自 48 色板」一条。
	check.call("UI_CHOICE_CARD_BG", UI_CHOICE_CARD_BG)
	check.call("UI_CHOICE_CARD_HIGHLIGHT", UI_CHOICE_CARD_HIGHLIGHT)
	check.call("UI_CHOICE_BORDER_ATTACK", UI_CHOICE_BORDER_ATTACK)
	check.call("UI_CHOICE_BORDER_DEFENSE", UI_CHOICE_BORDER_DEFENSE)
	check.call("UI_CHOICE_BORDER_RESOURCE", UI_CHOICE_BORDER_RESOURCE)
	check.call("UI_CHOICE_TITLE", UI_CHOICE_TITLE)
	check.call("UI_CHOICE_CAT", UI_CHOICE_CAT)
	check.call("UI_CHOICE_DESC", UI_CHOICE_DESC)
	check.call("UI_CHOICE_MASK", UI_CHOICE_MASK)
	check.call("UI_CHOICE_BTN_BG", UI_CHOICE_BTN_BG)
	check.call("UI_CHOICE_BTN_BG_HOVER", UI_CHOICE_BTN_BG_HOVER)
	check.call("UI_CHOICE_BTN_BORDER", UI_CHOICE_BTN_BORDER)
	check.call("UI_CHOICE_BTN_PRESSED_BORDER", UI_CHOICE_BTN_PRESSED_BORDER)
	check.call("UI_CHOICE_BTN_TEXT", UI_CHOICE_BTN_TEXT)
	# 阶段 11 收尾 · team-lead 裁定 L864 方案 A：BuffHud 文字色常量化
	check.call("UI_BUFF_HUD_TEXT", UI_BUFF_HUD_TEXT)
	return bad


# =============================================================================
# 八·六、UI 主题规范（美术规范 0.7 v1.6 第 5 节，任务 1.6）
# =============================================================================
# 所有色值必须取自 48 色板（上文八·五）；新增 UI 色一律先查色板再落常量。

## 5.2 面板：底 `#0B0D10` @ 85% 透明 + 1px 描边 `#3A424F` + 顶部 1px 高光 `#4E5866`。
## 像素风铁律：**圆角一律 0**（禁圆角）。
const UI_PANEL_BG: Color = Color("0B0D10")
const UI_PANEL_BG_ALPHA: float = 0.85
const UI_PANEL_BORDER: Color = Color("3A424F")
const UI_PANEL_HIGHLIGHT: Color = Color("4E5866")

## 5.2 按钮三态：Normal `#1E232B` / Hover `#2A313B`+描边高光 / Pressed `#14171C`+内阴影；
## 描边 1px；禁用态透明度降 40%。
const UI_BTN_NORMAL: Color = Color("1E232B")
const UI_BTN_HOVER: Color = Color("2A313B")
const UI_BTN_PRESSED: Color = Color("14171C")
const UI_BTN_BORDER: Color = Color("3A424F")
const UI_BTN_HOVER_BORDER: Color = Color("4E5866")
const UI_BTN_DISABLED_ALPHA: float = 0.40

## 5.2 物品格：48×48（背包）/ 64×64（装备槽），格底 `#14171C`，边框按稀有度着色。
const UI_SLOT_BG: Color = Color("14171C")
const UI_SLOT_SIZE_BAG: int = 48
const UI_SLOT_SIZE_EQUIP: int = 64

## 5.4 血条：玩家 16px / 怪物 8px；底槽 `#14171C`；血量 `#C42B2B`→`#8C1A1F` 渐变；
## 1px `#0B0D10` 描边；护盾叠 `#3A5FB0`。
const UI_HP_BAR_HEIGHT_PLAYER: int = 16
const UI_HP_BAR_HEIGHT_MONSTER: int = 8
const UI_HP_BAR_BG: Color = Color("14171C")
const UI_HP_BAR_GRADIENT_FROM: Color = Color("C42B2B")
const UI_HP_BAR_GRADIENT_TO: Color = Color("8C1A1F")
const UI_HP_BAR_OUTLINE: Color = Color("0B0D10")
const UI_SHIELD_COLOR: Color = Color("3A5FB0")
## 法力条渐变（步骤 6 · 取色板 B 系「魔法/冰」阶：亮蓝 → 中蓝）
const UI_MP_BAR_GRADIENT_FROM: Color = Color("3A5FB0")
const UI_MP_BAR_GRADIENT_TO: Color = Color("1F3468")

## 5.4 伤害数字：普通 12px `#DCE2E8`；暴击 24px `#F5D77A` + 抖动 + 上浮；
## 元素伤害用对应色系亮色；**必须带 1px 深描边**。
const UI_DMG_NORMAL_SIZE: int = 12
const UI_DMG_CRIT_SIZE: int = 24
const UI_DMG_NORMAL_COLOR: Color = Color("DCE2E8")
const UI_DMG_CRIT_COLOR: Color = Color("F5D77A")
const UI_DMG_OUTLINE: Color = Color("0B0D10")

## 5.3 信息层级用「亮度差」：常规 / 高亮 / 禁用三档
const UI_TEXT_NORMAL: Color = Color("B3BCC9")
const UI_TEXT_BRIGHT: Color = Color("DCE2E8")
const UI_TEXT_DISABLED: Color = Color("6B7688")

## 5.4 状态图标：24×24，置于血条下方；剩余时间用顺时针环。
const UI_STATUS_ICON_SIZE: int = 24

## 5.3 天赋节点：已点亮 `#D9A521` / 可点 `#3A424F` / 锁定 `#1E232B`。
const UI_TALENT_LIT: Color = Color("D9A521")
const UI_TALENT_AVAILABLE: Color = Color("3A424F")
const UI_TALENT_LOCKED: Color = Color("1E232B")

## 5.3 / 2.5 布局与字体：
##   · 8px 栅格；信息层级用「亮度差」而非「颜色差」。
##   · 像素字体只用整数尺寸（11/12/16/22/32px），关闭抗锯齿与 hinting。
##   · UI 逻辑基准 1920×1080，挂 CanvasLayer，锚点 + 容器自适应，不随游戏视口缩放。
const UI_GRID: int = 8
const UI_FONT_SIZES: Array[int] = [11, 12, 16, 22, 32]

## 5.1 字体（SIL OFL 1.1，免费商用）：
##   · 正文：Cubic-11（俐方体11号）11px —— 首选正文
##   · 标题/大字号：ChillBitmap（寒蝉点阵体）16px
##   数字/英文可搭配 m5x7 / Silkscreen（OFL）保持像素统一（暂未纳入）。
const UI_FONT_CUBIC11_PATH: String = "res://assets/fonts/Cubic_11.ttf"
const UI_FONT_CHILL_PATH: String = "res://assets/fonts/ChillBitmap_16px.ttf"
const UI_FONT_FALLBACK_SIZES: Array[int] = [11, 16] ## 缺失时回退到默认字体的尺寸


# =============================================================================
# 八·六·补、局内三选一面板（ChoicePanel）语义色 —— 阶段 11（2026-09-18）
# =============================================================================
#
# 为什么要单独一节：`choice_panel.gd` 是**手工建卡**的面板，不走 `UITheme` 的
# Panel / Button 变体，所以它的每个色值都绕过了「主题 → 色板常量」这条唯一色源链路。
#
# 2026-09-18 真渲染审计实测：该文件里 7 个色值**全是 `Color(...)` 字面量**、
# 其中 6 个不在 48 色板内（卡填充 `#171921`、三类描边、三种字色）——
# 而 108 项自检 + 43 个 verify **全绿**。机制原因：`ui_colors_not_in_palette()`
# 只扫**已登记的常量**，扫不到没登记的字面量。这正是「逻辑对 ≠ 画面对 ≠ 配色对」。
#
# 修法（两道）：
#   ① 色值收进本节常量，并在 `ui_colors_not_in_palette()` 的清单里登记 ⇒ 纳入自检；
#   ② `tools/verify_choice_panel.gd` 做「源码级（禁止裸 Color 字面量）+ 值级（∈色板）」断言，
#      永久拦截同类复发（新增 panel 忘了走主题时立刻报红）。
#
# 设计依据（WCAG 对比度均为真渲染像素实测，详见
# `deliverables/gstack/design-visual-audit-choice-panel-2026-09-18.md`）：
#   · 卡填充 `#1E232B`（§1.3「面板底」）：原 `#171921` 对**纯黑**也只有 1.20:1
#     ⇒ 根因是「底色本身太暗」，**抬填充是必须的，加遮罩替代不了**。
#   · 三类描边取三个语义色系的**辉光阶**（同层级 ⇒ 三类卡片视觉等重），
#     且对遮罩后地面的对比度 5.47 / 6.97 / 13.8，全部 ≥ 3:1（WCAG 非文本组件）。
#   · 按钮金 `#D9A521`（金/光·亮）：是色板里唯一能同时满足
#     「按钮底 vs 卡面 ≥ 3:1」与「按钮字 vs 按钮底 ≥ 4.5:1」的色族（金 = 确认/收益语义）。
#   · 遮罩 `#0B0D10` @ 0.55：**价值是「模态感 + 压掉背景运动与光斑」，不是为了提亮稿面**
#     —— 实测叠 45% 纯黑后「卡面 vs 地面」只从 1.03:1 升到 1.09:1，几乎没用。
#     **不要因为「加了遮罩对比度没变好」就把它删掉。**
const UI_CHOICE_CARD_BG: Color = Color("1E232B")          ## 卡填充（§1.3 面板底）
const UI_CHOICE_CARD_HIGHLIGHT: Color = Color("4E5866")   ## 卡顶部 1px 高光（§5.2）
const UI_CHOICE_BORDER_ATTACK: Color = Color("E8573F")    ## 分类描边·攻击（血/危险·辉光）
const UI_CHOICE_BORDER_DEFENSE: Color = Color("6E9BE8")   ## 分类描边·防御（魔法/冰·辉光）
const UI_CHOICE_BORDER_RESOURCE: Color = Color("F5D77A")  ## 分类描边·资源（金/光·辉光）
const UI_CHOICE_TITLE: Color = Color("DCE2E8")            ## 卡名（亮白）
const UI_CHOICE_CAT: Color = Color("8C97A8")              ## 【分类】副标题（浅灰）
const UI_CHOICE_DESC: Color = Color("B3BCC9")             ## 效果描述（正文）
const UI_CHOICE_MASK: Color = Color("0B0D10")             ## 全屏遮罩底色
## ⚠️ **标称 alpha ≠ 线性不透明度**（2026-09-18 真渲染实测，调参前必读）：
## `ColorRect` 在 **linear 空间**混合 ⇒ `0.55` 实际只把 sRGB 背景压到约 **60~70%**
## （实测 `#191C24 → #111419`、`#292933 → #181920`，暗化约 30~40%，而非 55%）。
## **按 sRGB 直觉推算会白调**；想让背景再暗一档需提到 **0.70+**。当前值与理由见
## `choice_panel.gd` 类头 ③（team-lead 裁定值，"够不够暗" 列为试玩观测点）。
const UI_CHOICE_MASK_ALPHA: float = 0.55                  ## 全屏遮罩不透明度（标称值，非线性）
const UI_CHOICE_BTN_BG: Color = Color("D9A521")           ## 「选择」按钮 Normal（金/光·亮）
const UI_CHOICE_BTN_BG_HOVER: Color = Color("F5D77A")     ## Hover（金/光·辉光）
const UI_CHOICE_BTN_BORDER: Color = Color("0B0D10")       ## 按钮 1px 深描边（像素风铁律）
const UI_CHOICE_BTN_PRESSED_BORDER: Color = Color("4A3208") ## Pressed 2px 描边（金/光·暗）
const UI_CHOICE_BTN_TEXT: Color = Color("0B0D10")         ## 按钮文字（压在金底上）

## 局内 BuffHud 文字色（阶段 11 收尾 · team-lead 裁定 L864 方案 A）
## `#DBC85` ≈ RGB(219,204,133)：与 `UI_CHOICE_BTN_BG_HOVER = F5D77A` 同属「金/光·亮」色族
## （只是饱和度/亮度都低一档，避免在战斗中抢焦点）。原 `level_scene.gd:_build_buff_hud()`
## 用了硬编码 `Color(0.86, 0.80, 0.52)`，本次常量化视觉零变化。
const UI_BUFF_HUD_TEXT: Color = Color("DBCC85")


# =============================================================================
# 八·七、攻击与技能（任务 2.2）
# =============================================================================
#
# 数值锚点（sim-report §7 输出乘子 / GDD 0.6 节 6.2 / 6.6）：
#   · 攻速基线 L1 = 1.0 次/秒 → L20 = 1.6 次/秒（装备 / 天赋乘区阶段 3 接入）
#   · 技能综合倍率 SkillMult L1 = 1.8 → L20 = 2.8（单技能个体倍率见 data/skills/*.json）
#   · 玩家裸装 AD L1 = 12（GDD 6.2）；2.2 伤害 = AD × 技能倍率（原始值，2.3 接完整公式）

## 法力：上限 / 自然回复（每秒）/ 普攻命中回复。资源词缀乘区（+最大资源等）阶段 3 接入。
const MANA_BASE_MAX: float = 100.0
const MANA_REGEN_PER_SEC: float = 4.0
const MANA_ON_HIT: float = 2.0

## 普攻：基础攻速（次/秒）与基础倍率（100% AD）。
## 假连段约定：按住攻击键 → 按此间隔连续挥击（同一段 8 帧动画循环，视觉像连击）；
## 美术规范只有 4 方向 × 8 帧攻击动画，**无连段动画**，故不设连段状态机。
const ATTACK_BASE_RATE: float = 1.0
const ATTACK_BASE_MULTIPLIER: float = 1.0

## 普攻近战判定距离（px）。取 48px ≈ 1.5 tile，略长于手部锚点张距（44px），
## 给「够得着」留一点容错；2.5 碰撞与命中判定会替换为精确几何。
const ATTACK_RANGE: float = 48.0

## 普攻扇区半角（度）：只命中朝向前方 60° 扇区内的目标（dot > cos(60°) = 0.5）。
const ATTACK_ARC_DEG: float = 60.0

## 攻击输入动作（project.godot [input]，1.3 已配：鼠标左键 + 手柄 X）
const ACTION_ATTACK: StringName = &"attack_primary"

## 主动技能槽位动作（1/2/3 键 + 手柄；与 data/skills/ 的条目一一对应）
const SKILL_BAR_ACTIONS: Array[String] = ["skill_1", "skill_2", "skill_3"]

## 技能施放前摇（秒）。像素风铁律下不做复杂蓄力，统一 0.12s 出伤害，靠动画帧表现。
const SKILL_CAST_WINDUP: float = 0.12

## 玩家裸装基础攻击力（GDD 6.2：Base1 = 12，成长 g = 0.10）。
## 2.2 用基础值；2.3 起由属性管线（等级成长 × 装备 × 词缀）替换。
const PLAYER_BASE_ATTACK_AT_L1: float = 12.0


# =============================================================================
# 八·八、伤害计算（任务 2.3 · 用户拍板）
# =============================================================================
#
# 完整伤害公式（用户 2.3 拍板；GDD 6.6 为 DPS 期望口径）：
#   基础伤害 raw = AD × 技能倍率
#   暴击 roll   ：CR 概率 × CD 倍率（CD 为百分数，150 = ×1.5）
#   期望倍率     = 1 + CR × (CD - 1)        —— GDD 6.6 DPS_exp 使用
#   元素加成     = ×(1 + 元素伤害%)          —— 词缀/套装阶段 3 接入
#   减伤         = 护甲 DR（物理）/ 元素抗性 DR（元素），再 ×(1 - 减伤%)
#   最终伤害     = raw × 暴击倍率 × 元素加成 × (1 - 减伤)
#   减伤顺序（用户拍板）：护甲/抗性 → 减伤% 乘算 → 概率判定（闪避/格挡，2.5/2.6）

## 暴击基准（用户 2.3 拍板）：基础 5% / 暴击伤害 150% / 上限 75%。
## 百分数存储（5 = 5%）。词缀 / 局内天赋（致命 +8%、撕裂 +25%）阶段 3 接入。
const CRIT_CHANCE_BASE: float = 5.0
const CRIT_DAMAGE_BASE: float = 150.0
const CRIT_CHANCE_CAP: float = 75.0

## 元素体系（用户 2.3 拍板）：物理 + 火 / 冰 / 雷 / 毒 5 类。
## 键与 STAT_*_RESIST 一一对应；抗性减伤与护甲同构：resist / (resist + 50 × L)。
const ELEMENT_PHYSICAL: String = "physical"
const ELEMENT_FIRE: String = "fire"
const ELEMENT_COLD: String = "cold"
const ELEMENT_LIGHTNING: String = "lightning"
const ELEMENT_POISON: String = "poison"
const ELEMENT_SHADOW: String = "shadow"
const ELEMENTS: Array[String] = [
	ELEMENT_PHYSICAL, ELEMENT_FIRE, ELEMENT_COLD, ELEMENT_LIGHTNING, ELEMENT_POISON,
	ELEMENT_SHADOW,
]

## 元素抗性减伤系数：与护甲 `ARMOR_DR_CONSTANT_PER_LEVEL`（50）同构，直觉统一。
const RESIST_DR_CONSTANT_PER_LEVEL: float = 50.0

## 元素抗性减伤上限（0–1）：75%（与暴击率上限同值，直觉统一）。
const RESIST_DR_CAP: float = 0.75


# =============================================================================
# 八·九、敌人 AI（任务 2.4）
# =============================================================================
#
# 状态机（数据驱动，攻击距离读怪物表 attack_range）：
#   PATROL  玩家距离 ≥ AGGRO 时，出生点附近小幅游走（半径 PATROL_RADIUS）
#   CHASE   玩家进入 AGGRO → 朝玩家移动（move_speed）
#   ATTACK  玩家进入 attack_range → 停下按 attack_interval 攻击
#   丢失    玩家距离 > LOSE_RANGE → 回 PATROL
# 说明：AGGRO / LOSE / PATROL 为 AI 通用手感参数（GDD 未定义，工程侧自定，
#       阶段 3 手感调优时一并迁移确认）；attack_range / move_speed / attack_interval
#       由 `MonsterData` 每只怪各自定义，不在此处。

## 追击触发距离（px）。160 = 5 tile：足够让玩家在屏上「看到怪追过来」再反应。
const ENEMY_AGGRO_RANGE: float = 160.0

## 丢失追击距离（px）。240 = 7.5 tile：比 AGGRO 大 50%，防止贴脸反复横跳。
const ENEMY_LOSE_RANGE: float = 240.0

## 巡逻半径（px）。48 = 1.5 tile：杂兵在出生点附近小幅游走，不走远。
const ENEMY_PATROL_RADIUS: float = 48.0

## 巡逻停留时间区间 [min, max]（秒）：走到目标点后歇一下再换点。
const ENEMY_PATROL_WAIT_MIN: float = 0.8
const ENEMY_PATROL_WAIT_MAX: float = 2.0

## 巡逻目标点到达容忍（px）：距离 < 该值即视为到达（避免来回抖动）。
const ENEMY_PATROL_ARRIVE_TOLERANCE: float = 4.0

## 敌人近战攻击判定弧宽（度）：以朝玩家方向为中轴、左右各 60°。
## 120° 比玩家普攻的 60° 宽——杂兵挥击更「松」，玩家走位更依赖距离而非贴背。
const ENEMY_ATTACK_ARC_DEG: float = 120.0


# =============================================================================
# 八·十、2D 物理层（任务 2.5 · README 第七节约定落盘）
# =============================================================================
#
# 位掩码值：world=1 / player=2 / enemy=3 / player_hitbox=4 / enemy_hitbox=5 /
#           projectile=6 / pickup=7 / interactable=8 / trigger=9
# 现状：玩家 layer=2 mask=1；敌人 layer=3 mask=3（world+player）。
# hitbox 层（4/5）为 2.6+ 命中框节点预留；.tscn 内因序列化限制保持字面量，
# 本常量供运行时创建节点 / 自检锚点使用。

const LAYER_WORLD: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ENEMY: int = 3
const LAYER_PLAYER_HITBOX: int = 4
const LAYER_ENEMY_HITBOX: int = 5
const LAYER_PROJECTILE: int = 6
const LAYER_PICKUP: int = 7
const LAYER_INTERACTABLE: int = 8
const LAYER_TRIGGER: int = 9

## 全部物理层值（自检用：9 个值必须唯一且落在 1–9）
const ALL_LAYERS: Array[int] = [
	LAYER_WORLD, LAYER_PLAYER, LAYER_ENEMY, LAYER_PLAYER_HITBOX, LAYER_ENEMY_HITBOX,
	LAYER_PROJECTILE, LAYER_PICKUP, LAYER_INTERACTABLE, LAYER_TRIGGER,
]


# =============================================================================
# 八·十一、生命与异常状态（任务 2.6）
# =============================================================================
#
# 减伤链（用户 2.3 拍板顺序）：护甲（物理）/ 抗性（元素）→ 减伤% 乘算 → 概率判定（闪避/格挡）。
#   闪避成功 = 本次伤害免疫；格挡成功 = 减伤后再 ×(1 - BLOCK_DAMAGE_REDUCTION)。
# 玩家基础 HP / 护甲在「六·关卡与角色成长」（BASE_HP_AT_L1=150 / BASE_ARMOR_AT_L1=6）；
# 本节是生命组件（HealthComponent）与异常状态的配套常量。
# 异常来源（阶段 3 前）：敌人按怪物表 element 攻击附加（毒→中毒 / 火→燃烧 / 冰→冰冻）；
# 雷电暂无异常（接口预留）；物理无异常。

## 玩家基础闪避率 / 格挡率（%）。基础 0；阶段 3 词缀（+闪避 / +格挡率）与套装写入。
const PLAYER_BASE_DODGE_CHANCE: float = 0.0
const PLAYER_BASE_BLOCK_CHANCE: float = 0.0

## 格挡成功减伤比例（0–1）：50%。暗黑类常见 30–50%，取中值；用户可调。
const BLOCK_DAMAGE_REDUCTION: float = 0.5

## 基础生命回复（/s）。0；阶段 3 词缀（+生命回复）与局内天赋「再生」（1.5% 最大生命/s）写入。
const PLAYER_BASE_REGENERATION: float = 0.0

## 异常状态类型（2.6 实现 3 种；雷电异常接口预留）
const AILMENT_POISON: String = "poison"   ## 中毒：持续伤害（dot）
const AILMENT_BURN: String = "burn"       ## 燃烧：持续伤害（dot）
const AILMENT_SLOW: String = "slow"       ## 冰冻：移动减速
const AILMENTS: Array[String] = [AILMENT_POISON, AILMENT_BURN, AILMENT_SLOW]

## dot 每秒伤害 = 来源攻击力 × DPS_RATIO（来源 = 施加方；无攻击力接口的异常源按 1/s）。
## 工程侧默认（GDD 未给统一数值，阶段 3 手感调优可调）：
##   中毒 20% AD/s、燃烧 25% AD/s —— 敌人 AD 基线 L1=5.61，故怪毒 ≈1.1/s，对 150 HP 温和。
const AILMENT_POISON_DPS_RATIO: float = 0.20
const AILMENT_BURN_DPS_RATIO: float = 0.25

## 异常持续时长（秒）。冰冻 2s 有 GDD 依据（霜噬套装「减速 40%，持续 2 秒」）；毒/燃工程侧自定。
const AILMENT_POISON_DURATION: float = 3.0
const AILMENT_BURN_DURATION: float = 2.0
const AILMENT_SLOW_DURATION: float = 2.0

## 冰冻减速乘区（0–1）：生效期间移动速度 × 0.6（= 减速 40%，GDD 霜噬套装）。
const AILMENT_SLOW_SPEED_FACTOR: float = 0.6

## 元素 → 异常映射：毒→中毒 / 火→燃烧 / 冰→冰冻；物理 / 雷电无异常（返回空串）。
const AILMENT_ELEMENT_MAP: Dictionary = {
	ELEMENT_POISON: AILMENT_POISON,
	ELEMENT_FIRE: AILMENT_BURN,
	ELEMENT_COLD: AILMENT_SLOW,
}

## 异常类型 → 每秒伤害比例（dot 用；slow 无伤害返回 0）
static func ailment_dps_ratio(ailment: String) -> float:
	match ailment:
		AILMENT_POISON: return AILMENT_POISON_DPS_RATIO
		AILMENT_BURN: return AILMENT_BURN_DPS_RATIO
	return 0.0


## 异常类型 → 持续时长（秒）
static func ailment_duration(ailment: String) -> float:
	match ailment:
		AILMENT_POISON: return AILMENT_POISON_DURATION
		AILMENT_BURN: return AILMENT_BURN_DURATION
		AILMENT_SLOW: return AILMENT_SLOW_DURATION
	return 0.0


## 元素 → 异常类型（无异常返回空串）
static func ailment_from_element(element: String) -> String:
	return AILMENT_ELEMENT_MAP.get(element, "")


# =============================================================================
# 八·十二、掉落与拾取（任务 2.7）
# =============================================================================
#
# 掉落表数据在 `game/data/loot_tables/monster_loot_tables.json`（普通 8% / 精英 60% /
# BOSS 100%·2–4 件），稀有度权重与难度修正规则见 GDD 6.1（8 档掉落率曲线）。
# 本段只放「机制常量」；表数据归 ConfigLoader（只读）。

## 玩家拾取半径（px）：掉落物与玩家距离 ≤ 此值自动拾取
const PICKUP_RADIUS: float = 24.0

## 地面掉落物存活时长（秒），超时消失（防刷宝场景堆积）
const LOOT_DROP_LIFETIME: float = 60.0

## 死亡后掉落弹出延迟（秒）——先出死亡表现再弹装备，视觉节奏
const LOOT_POP_DELAY: float = 0.25

## 金币量 = round(GOLD_BASE_AT_L1 × (1+GOLD_GROWTH)^(L-1) × randf_range(0.8, 1.2))
## 工程侧默认（阶段 3 货币系统调优可改）
const GOLD_BASE_AT_L1: float = 4.0
const GOLD_GROWTH: float = 1.12

## 材料掉落数量（魔石，强化材料占位）= 1 + (L-1)/5（取整，至少 1）
const MATERIAL_BASE_AT_L1: int = 1
const MATERIAL_LEVEL_STEP: int = 5

## 装备掉落物地面物件的色块边长（px）；金币/材料为 8px 小物件
const LOOT_EQUIPMENT_ICON_SIZE: int = 12

## GDD 6.1 难度修正规则（上一层时权重乘数；归一化后生效）：
##   白 ×0.85 / 黄 ×1.15 / 紫、橙 ×1.30 / 绿 ×1.10 / 红 ×1.50（且仅梦魇 II 及以上掉落）/ 彩不变
const RARITY_WHITE_DIFF_FACTOR: float = 0.85
const RARITY_RARE_DIFF_FACTOR: float = 1.15
const RARITY_EPIC_LEGENDARY_DIFF_FACTOR: float = 1.30
const RARITY_SET_DIFF_FACTOR: float = 1.10
const RARITY_MYTHIC_DIFF_FACTOR: float = 1.50
const RARITY_MYTHIC_MIN_DIFF_TIER: int = DifficultyTier.NM2

## GDD 6.1 越级惩罚：玩家等级 < 关卡等级 - 3 时，紫/橙/红 概率 ×0.5
const UNDERPOWERED_LEVEL_GAP: int = 3
const UNDERPOWERED_RARITY_FACTOR: float = 0.5

## 难度修正：把稀有度权重数组按难度档位修正（GDD 6.1）
static func adjust_rarity_weights_by_difficulty(
		weights: Array, difficulty: int, player_level: int, monster_level: int) -> Array:
	var out: Array = weights.duplicate()
	if out.size() != RARITY_KEYS.size():
		return out
	# 红装：仅梦魇 II 及以上掉落（NM1 权重清零）
	if difficulty < RARITY_MYTHIC_MIN_DIFF_TIER:
		out[Rarity.MYTHIC] = 0.0
	else:
		out[Rarity.MYTHIC] = float(out[Rarity.MYTHIC]) * RARITY_MYTHIC_DIFF_FACTOR
	# 白 ×0.85、黄 ×1.15、紫/橙 ×1.30、绿 ×1.10（普通怪口径上每层修正）
	out[Rarity.COMMON] = float(out[Rarity.COMMON]) * RARITY_WHITE_DIFF_FACTOR
	out[Rarity.RARE] = float(out[Rarity.RARE]) * RARITY_RARE_DIFF_FACTOR
	out[Rarity.EPIC] = float(out[Rarity.EPIC]) * RARITY_EPIC_LEGENDARY_DIFF_FACTOR
	out[Rarity.LEGENDARY] = float(out[Rarity.LEGENDARY]) * RARITY_EPIC_LEGENDARY_DIFF_FACTOR
	out[Rarity.SET] = float(out[Rarity.SET]) * RARITY_SET_DIFF_FACTOR
	# 越级惩罚：玩家等级 < 关卡等级 - 3 时紫/橙/红 ×0.5
	if player_level > 0 and monster_level - player_level > UNDERPOWERED_LEVEL_GAP:
		out[Rarity.EPIC] = float(out[Rarity.EPIC]) * UNDERPOWERED_RARITY_FACTOR
		out[Rarity.LEGENDARY] = float(out[Rarity.LEGENDARY]) * UNDERPOWERED_RARITY_FACTOR
		out[Rarity.MYTHIC] = float(out[Rarity.MYTHIC]) * UNDERPOWERED_RARITY_FACTOR
	return out


# =============================================================================
# 八·十三、打击感（任务 2.8）
# =============================================================================
#
# 视觉打击感（像素风自绘、零新资产）：伤害飘字 / 受击闪白 / 死亡粒子 / 震屏 / 顿帧。
# 音效反馈不在此段——`assets/audio/` 阶段 6 才有资产，届时由 JuiceFX 接 AudioStream。
# 数值为工程侧手感默认（暗黑类常规区间），阶段 8 手感调优可改。

## 伤害飘字存活时长（秒）
const DAMAGE_NUMBER_LIFETIME: float = 0.6

## 飘字上飘速度（px/s）
const DAMAGE_NUMBER_RISE_SPEED: float = 26.0

## 飘字横向随机偏移（px，避免叠字）
const DAMAGE_NUMBER_SCATTER: float = 6.0

## 飘字头顶基准高度（px）
const DAMAGE_NUMBER_OFFSET_Y: float = -18.0

## 飘字字号：普通 11px（主题正文）/ 暴击 15px
const DAMAGE_NUMBER_FONT_SIZE: int = 11
const DAMAGE_NUMBER_CRIT_FONT_SIZE: int = 15

## 飘字颜色：普通亮白 / 暴击橙红（与元素着色区分开，保持可读性）
const COLOR_DAMAGE_NORMAL: Color = Color("DCE2E8")
const COLOR_DAMAGE_CRIT: Color = Color("FF7A3D")

## 受击闪白时长（秒）；敌人占位同样式（_flash_hit）
const HIT_FLASH_DURATION: float = 0.08

## 顿帧（hit-stop）：命中瞬间把 Engine.time_scale 压到 HIT_STOP_TIME_SCALE，
## 持续 HIT_STOP_DURATION（真实时间，忽略 time_scale）后恢复。仅暴击触发（避免高频顿帧卡手感）。
const HIT_STOP_DURATION: float = 0.03
const HIT_STOP_TIME_SCALE: float = 0.05

## 震屏：命中强度 1.5px / 暴击 3.0px，每秒衰减 SHAKE_DECAY
const SHAKE_HIT_STRENGTH: float = 1.5
const SHAKE_CRIT_STRENGTH: float = 3.0
const SHAKE_DECAY_PER_SEC: float = 40.0

## 死亡粒子（PixelBurst）：碎片数量 / 存活时长 / 初速范围 / 重力
const DEATH_BURST_PARTS: int = 8
const DEATH_BURST_DURATION: float = 0.35
const DEATH_BURST_SPEED_MIN: float = 30.0
const DEATH_BURST_SPEED_MAX: float = 70.0
const DEATH_BURST_GRAVITY: float = 60.0


# =============================================================================
# 八·十四、锻造与洗练（任务 3.4）
# =============================================================================
#
# GDD 0.3 节 3.4「品质与升级」+ 6.5「经济闭环」（v1.8）：
#   强化上限：橙/绿/彩 +10、红 +12（每级 +5% 基础属性，线性叠加）
#   成功率：+1~+5 100% / +6 80% / +7 65% / +8 50% / +9 40% / +10 25% /
#           +11 20% / +12 15%（红装）
#   失败惩罚：+1~+8 不降级仅耗材料；+9 起失败降 1 级；+11/+12 额外耗 1 神话结晶
#   金币：强化第 k 级 = 100 × 1.35^k；洗练第 n 次 = 500 × 1.15^n
#   魔石：+1~+10 见 FORGE_STONE_COST（合计 106，GDD 6.5 v1.8 定稿）；
#         +11/+12 各 30（GDD 未给，工程侧按 +10 末档 25 上浮 20% 定）
#   洗练：保持词缀类型、重掷数值，消耗 1 秘银尘/次

## 强化成功率（索引 = 目标等级 - 1；+1 → index 0）
const FORGE_SUCCESS_CHANCE: Array[float] = [
	1.00, 1.00, 1.00, 1.00, 1.00, # +1 ~ +5
	0.80, 0.65, 0.50,             # +6 / +7 / +8
	0.40, 0.25,                   # +9 / +10
	0.20, 0.15,                   # +11 / +12（红装）
]

## 失败降级起点：目标等级 ≥ 此值时失败降 1 级（+1~+8 只耗材料）
const FORGE_FAIL_DOWNGRADE_FROM: int = 9

## 强化金币成本：round(100 × 1.35^k)，k = 目标等级（GDD 6.5：+1→135、+10→1779）
const FORGE_GOLD_COST_BASE: float = 100.0
const FORGE_GOLD_COST_GROWTH: float = 1.35

## 红装 +11/+12 的魔石消耗（每级 30，GDD 未给、工程侧定）与神话结晶消耗（每次 1）
const FORGE_STONE_COST_EXT: Array[int] = [30, 30]
const FORGE_CRYSTAL_COST_PER_TRY: int = 1

## 洗练成本：第 n 次（n 从 0 起）= round(500 × 1.15^n) 金币 + 1 秘银尘
const REROLL_GOLD_COST_BASE: float = 500.0
const REROLL_GOLD_COST_GROWTH: float = 1.15
const REROLL_DUST_COST: int = 1

## 洗练时保留词缀类型重掷数值；不可洗练词缀（can_reroll=false）原值保留
static func forge_gold_cost(target_level: int) -> int:
	return maxi(1, int(round(FORGE_GOLD_COST_BASE * pow(FORGE_GOLD_COST_GROWTH, float(target_level)))))


static func reroll_gold_cost(n: int) -> int:
	return maxi(1, int(round(REROLL_GOLD_COST_BASE * pow(REROLL_GOLD_COST_GROWTH, float(n)))))


## 某目标等级的魔石消耗（+1~+10 走 GDD 106 明细；+11/+12 走工程侧 30）
static func forge_stone_cost(target_level: int) -> int:
	if target_level <= 0:
		return 0
	if target_level <= FORGE_MAX_LEVEL:
		return FORGE_STONE_COST[target_level - 1]
	var ext_index := target_level - FORGE_MAX_LEVEL - 1
	if ext_index >= 0 and ext_index < FORGE_STONE_COST_EXT.size():
		return FORGE_STONE_COST_EXT[ext_index]
	return 0


## 强化成功率（目标等级 1..12；越界返回 0）
static func forge_success_chance(target_level: int) -> float:
	if target_level < 1 or target_level > FORGE_SUCCESS_CHANCE.size():
		return 0.0
	return FORGE_SUCCESS_CHANCE[target_level - 1]


# =============================================================================
# 九、存档
# =============================================================================
## 默认职业 ID（旧档 / 未选职业时使用）
const CLASS_DEFAULT: String = "warrior"

## 技能 id → 图标逻辑名（UISkin.texture 用）。以 data/skills/skills.json 的真实 id 为准。
## 原定义在 level_scene.gd，2026-09-22 上移共享：角色选择面板（技能展示）与局内技能栏同源，
## 避免两处映射漂移。
const SKILL_ICON: Dictionary = {
	"cleave": "skill_icon_slash",
	"spin_slash": "skill_icon_slash",
	"dash_strike": "skill_icon_shadowdash",
	"fireball": "skill_icon_fireburst",
	"frost_nova": "skill_icon_frostnova",
	"lightning_chain": "skill_icon_lightning_chain",
	"poison_cloud": "skill_icon_poison_cloud",
	"shadow_blink": "skill_icon_shadowdash",
	"power_strike": "skill_icon_slash",
	"piercing_shot": "skill_icon_piercing_shot",
	"arrow_rain": "skill_icon_arrow_rain",
	"venom_shot": "skill_icon_poison_cloud",
}

const SAVE_VERSION: int = 3
const SAVE_DIR: String = "user://saves"
const SAVE_MAX_SLOTS: int = 8
const SAVE_BACKUP_ROTATION: int = 3 ## 每槽保留的备份份数


# =============================================================================
# 九·五、属性键（StatKey）
# =============================================================================
#
# 用途：装备基础属性、词缀效果、角色面板统一用**字符串键**索引，便于数据文件扩展。
# 约定：`flat_*` 为固定值加法，`pct_*` 为百分比乘法。百分比一律以 **百分数** 存
#       （如 12.5 表示 +12.5%），显示层不再换算。
#
# ⚠️ 禁止在业务脚本里硬编码这些字符串，一律引用本类常量。
const STAT_FLAT_HP: String = "flat_hp"                     ## 固定生命
const STAT_PCT_HP: String = "pct_hp"                       ## 生命 %
const STAT_FLAT_ATTACK: String = "flat_attack"             ## 固定攻击力
const STAT_PCT_ATTACK: String = "pct_attack"               ## 攻击力 %
const STAT_FLAT_ARMOR: String = "flat_armor"               ## 固定护甲
const STAT_PCT_ARMOR: String = "pct_armor"                 ## 护甲 %
const STAT_ATTACK_SPEED: String = "attack_speed"           ## 攻击速度 %
const STAT_CRIT_CHANCE: String = "crit_chance"             ## 暴击率 %
const STAT_CRIT_DAMAGE: String = "crit_damage"             ## 暴击伤害 %
const STAT_MOVE_SPEED: String = "move_speed"               ## 移动速度 %
const STAT_MAX_RESOURCE: String = "max_resource"           ## 最大资源
const STAT_RESOURCE_REGEN: String = "resource_regen"       ## 资源回复 %
const STAT_COOLDOWN_REDUCTION: String = "cooldown_reduction" ## 冷却缩减 %
const STAT_SKILL_COST_REDUCTION: String = "skill_cost_reduction" ## 技能减耗 %
const STAT_PICKUP_RADIUS: String = "pickup_radius"         ## 拾取范围
const STAT_DODGE: String = "dodge"                         ## 闪避 %
const STAT_BLOCK_CHANCE: String = "block_chance"           ## 格挡率 %
const STAT_LIFE_ON_HIT: String = "life_on_hit"             ## 生命偷取 %
const STAT_LIFE_REGEN: String = "life_regen"               ## 生命回复/秒
const STAT_THORNS: String = "thorns"                       ## 荆棘反伤
const STAT_ARMOR_PENETRATION: String = "armor_penetration" ## 护甲穿透 %
const STAT_ELEMENTAL_DAMAGE: String = "elemental_damage"   ## 元素伤害 %
const STAT_SKILL_LEVEL: String = "skill_level"             ## 技能等级（固定值）
const STAT_MAGIC_FIND: String = "magic_find"               ## 掉落幸运 %
const STAT_XP_GAIN: String = "xp_gain"                     ## 经验获取 %
const STAT_GOLD_GAIN: String = "gold_gain"                 ## 金币获取 %
const STAT_KILL_HEAL: String = "kill_heal"                 ## 击杀回复
const STAT_FIRE_RESIST: String = "fire_resist"             ## 火焰抗性 %
const STAT_COLD_RESIST: String = "cold_resist"             ## 冰霜抗性 %
const STAT_POISON_RESIST: String = "poison_resist"         ## 毒素抗性 %
const STAT_LIGHTNING_RESIST: String = "lightning_resist"   ## 闪电抗性 %
## 全属性 %（神话词缀专用，GDD 0.3 节 3.2.2：神话装必含 1 条「全属性 +X%」）
const STAT_ALL_ATTRIBUTES: String = "all_attributes"

## 全部属性键（顺序即角色面板显示顺序）
const ALL_STAT_KEYS: Array[String] = [
	STAT_FLAT_HP, STAT_PCT_HP,
	STAT_FLAT_ATTACK, STAT_PCT_ATTACK,
	STAT_FLAT_ARMOR, STAT_PCT_ARMOR,
	STAT_ATTACK_SPEED, STAT_CRIT_CHANCE, STAT_CRIT_DAMAGE,
	STAT_MOVE_SPEED,
	STAT_MAX_RESOURCE, STAT_RESOURCE_REGEN,
	STAT_COOLDOWN_REDUCTION, STAT_SKILL_COST_REDUCTION, STAT_PICKUP_RADIUS,
	STAT_DODGE, STAT_BLOCK_CHANCE, STAT_LIFE_ON_HIT, STAT_LIFE_REGEN, STAT_THORNS,
	STAT_ARMOR_PENETRATION, STAT_ELEMENTAL_DAMAGE, STAT_SKILL_LEVEL,
	STAT_MAGIC_FIND, STAT_XP_GAIN, STAT_GOLD_GAIN, STAT_KILL_HEAL,
	STAT_FIRE_RESIST, STAT_COLD_RESIST, STAT_POISON_RESIST, STAT_LIGHTNING_RESIST,
	STAT_ALL_ATTRIBUTES,
]

## 属性键的中文显示名（角色面板用）
const STAT_DISPLAY_NAMES: Dictionary = {
	STAT_FLAT_HP: "生命值",
	STAT_PCT_HP: "生命值",
	STAT_FLAT_ATTACK: "攻击力",
	STAT_PCT_ATTACK: "攻击力",
	STAT_FLAT_ARMOR: "护甲",
	STAT_PCT_ARMOR: "护甲",
	STAT_ATTACK_SPEED: "攻击速度",
	STAT_CRIT_CHANCE: "暴击率",
	STAT_CRIT_DAMAGE: "暴击伤害",
	STAT_MOVE_SPEED: "移动速度",
	STAT_MAX_RESOURCE: "最大资源",
	STAT_RESOURCE_REGEN: "资源回复速度",
	STAT_COOLDOWN_REDUCTION: "冷却缩减",
	STAT_SKILL_COST_REDUCTION: "技能减耗",
	STAT_PICKUP_RADIUS: "拾取范围",
	STAT_DODGE: "闪避",
	STAT_BLOCK_CHANCE: "格挡率",
	STAT_LIFE_ON_HIT: "生命偷取",
	STAT_LIFE_REGEN: "生命回复",
	STAT_THORNS: "荆棘反伤",
	STAT_ARMOR_PENETRATION: "护甲穿透",
	STAT_ELEMENTAL_DAMAGE: "元素伤害",
	STAT_SKILL_LEVEL: "技能等级",
	STAT_MAGIC_FIND: "掉落幸运",
	STAT_XP_GAIN: "经验获取",
	STAT_GOLD_GAIN: "金币获取",
	STAT_KILL_HEAL: "击杀回复",
	STAT_FIRE_RESIST: "火焰抗性",
	STAT_COLD_RESIST: "冰霜抗性",
	STAT_POISON_RESIST: "毒素抗性",
	STAT_LIGHTNING_RESIST: "闪电抗性",
	STAT_ALL_ATTRIBUTES: "全属性",
}


# =============================================================================
# 十、辅助函数（只读查询，不承载业务逻辑）
# =============================================================================

## 取稀有度文字色；越界返回白色，避免 UI 崩溃
static func rarity_color(rarity: int) -> Color:
	if rarity < 0 or rarity >= RARITY_COLORS.size():
		return Color.WHITE
	return RARITY_COLORS[rarity]


## 取稀有度中文名
static func rarity_name(rarity: int) -> String:
	if rarity < 0 or rarity >= RARITY_NAMES.size():
		return "未知"
	return RARITY_NAMES[rarity]


## 取稀有度英文键名（存档 / 数据文件用）
static func rarity_key(rarity: int) -> String:
	if rarity < 0 or rarity >= RARITY_KEYS.size():
		return "unknown"
	return RARITY_KEYS[rarity]


## 由英文键名反查稀有度枚举；失败返回 COMMON
static func rarity_from_key(key: String) -> int:
	var idx := RARITY_KEYS.find(key.to_lower())
	return idx if idx >= 0 else Rarity.COMMON


## 取稀有度所属类别（线性 / 正交套装 / 彩蛋）—— 美术规范 1.4 节「两级判断」用
static func rarity_category(rarity: int) -> int:
	if rarity < 0 or rarity >= RARITY_CATEGORIES.size():
		return RarityCategory.LINEAR
	return RARITY_CATEGORIES[rarity]


## 是否为线性强度阶梯档（白/蓝/黄/紫/橙/红）
static func is_linear_rarity(rarity: int) -> bool:
	return rarity_category(rarity) == RarityCategory.LINEAR


## 取地面光柱形状
static func rarity_beam_shape(rarity: int) -> int:
	if rarity < 0 or rarity >= RARITY_BEAM_SHAPES.size():
		return BeamShape.NONE
	return RARITY_BEAM_SHAPES[rarity]


## 取物品框线样式
static func rarity_frame_style(rarity: int) -> int:
	if rarity < 0 or rarity >= RARITY_FRAME_STYLES.size():
		return FrameStyle.SOLID
	return RARITY_FRAME_STYLES[rarity]


## 取该稀有度的强化上限（神话 +12，其余 +10）
static func forge_max_level_for(rarity: int) -> int:
	return FORGE_MAX_LEVEL_MYTHIC if rarity >= Rarity.MYTHIC and rarity <= Rarity.MYTHIC else FORGE_MAX_LEVEL


## 该稀有度能否在指定难度层级掉落（神话红仅梦魇 II 及以上）
static func can_drop_at_difficulty(rarity: int, difficulty_tier: int) -> bool:
	if rarity == Rarity.MYTHIC:
		return difficulty_tier >= MYTHIC_MIN_DIFFICULTY_TIER
	return true


## 已装备的套装件数 → 已解锁的最高套装阈值（0 / 2 / 4 / 6）
static func highest_set_threshold_reached(equipped_piece_count: int) -> int:
	var reached := 0
	for threshold in SET_THRESHOLDS:
		if equipped_piece_count >= threshold:
			reached = threshold
	return reached


## 取装备部位中文名
static func equip_slot_name(slot: int) -> String:
	if slot < 0 or slot >= EQUIP_SLOT_NAMES.size():
		return "未知"
	return EQUIP_SLOT_NAMES[slot]


## 取装备部位英文键名
static func equip_slot_key(slot: int) -> String:
	if slot < 0 or slot >= EQUIP_SLOT_KEYS.size():
		return "unknown"
	return EQUIP_SLOT_KEYS[slot]


## 由英文键名反查装备部位；失败返回 -1
static func equip_slot_from_key(key: String) -> int:
	return EQUIP_SLOT_KEYS.find(key.to_lower())


## 取武器原型中文名
static func weapon_archetype_name(archetype: int) -> String:
	if archetype < 0 or archetype >= WEAPON_ARCHETYPE_NAMES.size():
		return "未知"
	return WEAPON_ARCHETYPE_NAMES[archetype]


## 由英文键名反查武器原型；失败返回 -1
static func weapon_archetype_from_key(key: String) -> int:
	return WEAPON_ARCHETYPE_KEYS.find(key.to_lower())


## 该原型是否为副手专用（副手 4 个：盾 / 法器 / 箭袋 / 副刃）
static func is_off_hand_archetype(archetype: int) -> bool:
	return OFF_HAND_ARCHETYPES.has(archetype)


## 该原型是否为「复用别的原型出图」（如副刃复用匕首）。
## 返回 -1 表示自己出图；否则返回被复用的原型。
static func weapon_archetype_sprite_source(archetype: int) -> int:
	if archetype < 0 or archetype >= WEAPON_ARCHETYPE_SPRITE_SOURCE.size():
		return -1
	return WEAPON_ARCHETYPE_SPRITE_SOURCE[archetype]


## 该原型需要新画的帧数（复用他者出图的返回 0）
static func weapon_archetype_frames(archetype: int) -> int:
	if archetype < 0 or archetype >= WEAPON_ARCHETYPE_FRAMES.size():
		return 0
	return WEAPON_ARCHETYPE_FRAMES[archetype]


## 武器层美术总帧数（供阶段 6 排期核对；当前 244 帧）
static func weapon_layer_total_frames() -> int:
	var total := 0
	for n in WEAPON_ARCHETYPE_FRAMES:
		total += n
	return total


## 由英文键名反查难度层级；失败返回 NM1
static func difficulty_from_key(key: String) -> int:
	var idx := DIFFICULTY_TIER_KEYS.find(key.to_lower())
	return idx if idx >= 0 else DifficultyTier.NM1


## 升级所需经验：100 × L^1.6
static func xp_to_next(account_level: int) -> float:
	var l := maxi(account_level, 1)
	return XP_CURVE_BASE * pow(float(l), XP_CURVE_EXPONENT)


## 裸装基础属性：Base1 × (1+g)^(L-1)
static func base_stat_at_level(base_at_l1: float, growth: float, level: int) -> float:
	var l := maxi(level, 1)
	return base_at_l1 * pow(1.0 + growth, float(l - 1))


## 词缀数值随物品等级的缩放系数
static func affix_ilvl_scale(item_level: int) -> float:
	return 1.0 + AFFIX_ILVL_SCALE_PER_LEVEL * float(maxi(item_level, 1) - 1)


## 装备主属性随物品等级的缩放系数
static func item_stat_ilvl_scale(item_level: int) -> float:
	return 1.0 + ITEM_STAT_ILVL_SCALE_PER_LEVEL * float(maxi(item_level, 1) - 1)


## 装备需求等级
static func required_level_for(item_level: int) -> int:
	return maxi(1, item_level - ITEM_REQ_LEVEL_OFFSET)


## 护甲减伤率（0–1）
static func armor_damage_reduction(armor: float, level: int) -> float:
	var denom := armor + ARMOR_DR_CONSTANT_PER_LEVEL * float(maxi(level, 1))
	if denom <= 0.0:
		return 0.0
	return clampf(armor / denom, 0.0, 0.95)


## 元素抗性减伤率（0–1）：与护甲同构 resist / (resist + 50 × L)，上限 75%。
## 用户 2.3 拍板：护甲管物理、抗性管元素，公式统一便于直觉理解。
static func element_damage_reduction(resist: float, level: int) -> float:
	var denom := resist + RESIST_DR_CONSTANT_PER_LEVEL * float(maxi(level, 1))
	if denom <= 0.0:
		return 0.0
	return clampf(resist / denom, 0.0, RESIST_DR_CAP)


## 难度层级 HP 系数：1.08^tier（梦魇 I = 1.00 → 梦魇 V = ×1.36）
static func difficulty_hp_multiplier(tier: int) -> float:
	return pow(DIFFICULTY_HP_FACTOR_BASE, float(clampi(tier, 0, DIFFICULTY_TIER_COUNT - 1)))


## 难度层级 DMG 系数：1.23^tier（梦魇 I = 1.00 → 梦魇 V = ×2.29，主导轴）
static func difficulty_dmg_multiplier(tier: int) -> float:
	return pow(DIFFICULTY_DMG_FACTOR_BASE, float(clampi(tier, 0, DIFFICULTY_TIER_COUNT - 1)))
