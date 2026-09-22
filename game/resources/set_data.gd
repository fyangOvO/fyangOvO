## 套装定义（数据驱动 · 自定义 Resource）
##
## 定位：描述「一组 6 件套装叫什么、由哪 6 件底材组成、2/4/6 件分别给什么加成」。
##
## 设计依据（GDD 0.3 节 3.2.1「套装机制」）：
##   - 每组套装 **6 件**，覆盖 6 个固定部位槽
##   - 同时最多装备 1 套，其余部位穿散件
##   - 三档触发：**2 件 / 4 件 / 6 件** 逐级解锁
##   - 单件强度弱于紫装；集齐 6 件后 ≈ 红装单件满强化（「不是更高一档，而是另一条路」）
##
## 与 EquipmentData 的关系：
##   `EquipmentData.set_id` 指向本类的 `id`；本类的 `piece_template_ids` 反向列出 6 件底材。
##   二者必须双向一致 —— `ConfigLoader` 在加载完成后会做交叉校验。
##
## 数据来源：`game/data/sets/*.json`
class_name SetData
extends Resource

## 唯一标识（如 "oathkeeper"）
@export var id: String = ""

## UI 显示名（如 "守誓者"）
@export var display_name: String = ""

## 套装风格标签（如 "坦克流" / "冰霜流" / "火伤流"），用于 UI 副标题
@export var style_tag: String = ""

## 徽记图标路径（16×16，嵌在物品框右上角；全项目约 6 个，可复用）
@export_file("*.png") var emblem_path: String = ""

## 组成该套装的 6 件底材 ID（对应 EquipmentData.id）。
## 顺序建议按部位排列：头 / 胸 / 手 / 腿 / 脚 / 第 6 件（主手或副手或项链）。
@export var piece_template_ids: Array[String] = []

## 三档加成。每项结构：
##   {
##     "pieces": 2,                          // 触发所需件数（2 / 4 / 6）
##     "description": "＋15% 护甲",           // UI 展示文本
##     "stats": { "pct_armor": 15.0 },       // 数值加成（键为 GameConstants.STAT_*）
##     "effect_id": ""                       // 可选：机制型特效的 ID（如减速、霜爆）
##   }
@export var tier_bonuses: Array[Dictionary] = []


## 取指定件数下已激活的全部加成条目
func get_active_bonuses(equipped_piece_count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bonus in tier_bonuses:
		if equipped_piece_count >= int(bonus.get("pieces", 999)):
			out.append(bonus)
	return out


## 取已激活的最高档位（0 / 2 / 4 / 6）
func get_highest_active_tier(equipped_piece_count: int) -> int:
	var highest := 0
	for bonus in tier_bonuses:
		var p := int(bonus.get("pieces", 0))
		if equipped_piece_count >= p and p > highest:
			highest = p
	return highest


## 汇总已激活的数值加成（同键累加）
func get_total_stats(equipped_piece_count: int) -> Dictionary:
	var out := {}
	for bonus in get_active_bonuses(equipped_piece_count):
		var stats: Variant = bonus.get("stats", {})
		if not (stats is Dictionary):
			continue
		for key in stats:
			out[String(key)] = float(out.get(String(key), 0.0)) + float(stats[key])
	return out


## 该底材是否属于本套装
func contains_template(template_id: String) -> bool:
	return piece_template_ids.has(template_id)


## 校验数据完整性，返回错误信息数组（空数组 = 通过）
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("SetData.id 为空")
	if display_name.is_empty():
		errors.append("套装 '%s' 缺少 display_name" % id)
	if piece_template_ids.size() != GameConstants.SET_PIECE_COUNT:
		errors.append("套装 '%s' 应有 %d 件，实际列出 %d 件"
			% [id, GameConstants.SET_PIECE_COUNT, piece_template_ids.size()])

	var thresholds: Array[int] = []
	for bonus in tier_bonuses:
		var p := int(bonus.get("pieces", 0))
		if not GameConstants.SET_THRESHOLDS.has(p):
			errors.append("套装 '%s' 的加成档位 %d 不在 %s 中"
				% [id, p, str(GameConstants.SET_THRESHOLDS)])
		thresholds.append(p)

	for required in GameConstants.SET_THRESHOLDS:
		if not thresholds.has(required):
			errors.append("套装 '%s' 缺少 %d 件档位的加成" % [id, required])
	return errors
