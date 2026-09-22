## 一条**已 roll 出**的词缀（模板引用 + 实际数值 + roll 品质）
##
## 为什么与 AffixData 分开：
##   `AffixData` 是**共享模板**（一个词缀只有一份），而 `AffixRoll` 是**装备实例上的一条具体词缀**。
##   装备要能被序列化进存档，存档里只存 `affix_id` + `value` + `quality`（不存模板），
##   读档时由 ConfigLoader 依据 `affix_id` 回填 `template` 引用。
class_name AffixRoll
extends Resource

## 模板 ID（对应 AffixData.id）
@export var affix_id: String = ""

## 实际数值（已应用 iLvl 缩放与 roll 品质）
@export var value: float = 0.0

## roll 品质系数（通常为 GameConstants.AFFIX_ROLL_QUALITY_TIERS 之一：0.60/0.75/0.90/1.00/1.15）
@export var quality: float = 1.0

## 是否为史诗档「强化词缀」（数值 ×1.5，GDD 0.3 节 3.2）
@export var is_empowered: bool = false

## 运行时模板引用。**不序列化**，读档后由 ConfigLoader 注入。
var template: AffixData = null


## 构造一条 roll
static func create(p_affix_id: String, p_value: float, p_quality: float = 1.0, p_empowered: bool = false) -> AffixRoll:
	var roll := AffixRoll.new()
	roll.affix_id = p_affix_id
	roll.value = p_value
	roll.quality = p_quality
	roll.is_empowered = p_empowered
	return roll


## 品质对应的 UI 染色（灰/绿/蓝/黄/橙）
func quality_color() -> Color:
	var idx := GameConstants.AFFIX_ROLL_QUALITY_TIERS.find(quality)
	if idx < 0:
		# 非标准品质：按比例线性映射到 5 阶
		idx = clampi(int(round(quality * 4.0)) - 2, 0, GameConstants.AFFIX_ROLL_QUALITY_COLORS.size() - 1)
	return GameConstants.AFFIX_ROLL_QUALITY_COLORS[idx]


## 生成显示文本（需要 template 已注入；未注入时退化为调试格式）
func to_text() -> String:
	if template == null:
		return "[%s +%s]" % [affix_id, _format_number(value)]
	var text := template.description_template
	text = text.replace("{value}", _format_number(value))
	text = text.replace("{value_pct}", _format_number(value * 100.0))
	return text


func _format_number(v: float) -> String:
	var places := template.decimal_places if template != null else 0
	return String.num(v, places)


func to_dict() -> Dictionary:
	return {
		"affix_id": affix_id,
		"value": value,
		"quality": quality,
		"is_empowered": is_empowered,
	}


static func from_dict(data: Dictionary) -> AffixRoll:
	return AffixRoll.create(
		String(data.get("affix_id", "")),
		float(data.get("value", 0.0)),
		float(data.get("quality", 1.0)),
		bool(data.get("is_empowered", false))
	)
