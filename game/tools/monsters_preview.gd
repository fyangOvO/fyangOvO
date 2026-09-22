## 怪物全览 + 精英词缀怪渲染预览（任务 6.2 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/monsters_preview.tscn
##   输出 build/monsters_preview.png：
##     左区 = 16 种怪物色块全览（普通暗红 / 精英紫 / BOSS 金，档位色）
##     右区 = 精英词缀演示（急速/吸血/爆炸/回响/荆棘/闪现 → 词缀怪色块 + 标签）
extends Node2D

var _frame := 0

## 档位色（占位美术同款：普通 暗红 / 精英 紫 / BOSS 金）
const TIER_COLORS := {
	"normal": Color(0.55, 0.18, 0.18),
	"elite": Color(0.49, 0.27, 0.72),
	"boss": Color(0.85, 0.65, 0.13),
}

## 新 8 种怪物（6.2 追加）高亮色
const NEW_MONSTERS := ["mushroom_spore", "warg_dark", "golem_ember", "imp_hellfire",
	"hound_ash", "pyromancer_cultist", "frozen_husk", "ice_wraith"]


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "怪物扩充 + 精英词缀怪预览（任务 6.2 · 16 种 / 6 词缀）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 8)
	add_child(title)

	# ---- 左区：16 种怪物全览（网格 4×4） ----
	var ids: Array = ConfigLoader.monsters.keys()
	ids.sort()
	var cell := 108.0
	var x0 := 24.0
	var y0 := 56.0
	for i in ids.size():
		var m: MonsterData = ConfigLoader.monsters[ids[i]]
		var cx := x0 + float(i % 4) * cell
		var cy := y0 + float(i / 4) * cell
		var block := ColorRect.new()
		block.color = TIER_COLORS.get(str(m.tier), Color(0.5, 0.5, 0.5))
		if ids[i] in NEW_MONSTERS:
			block.color = block.color.lightened(0.25)
		block.position = Vector2(cx, cy)
		block.size = Vector2(28, 28)
		add_child(block)
		var name_l := Label.new()
		name_l.text = "%s\n%s · L%d–%d%s" % [m.display_name, m.tier, m.level_min, m.level_max,
			"  ★新增" if ids[i] in NEW_MONSTERS else ""]
		name_l.add_theme_font_size_override("font_size", 10)
		name_l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		name_l.position = Vector2(cx + 34, cy - 2)
		name_l.size = Vector2(150, 34)
		add_child(name_l)

	# ---- 右区：精英词缀演示 ----
	var ax := 560.0
	var ay := 60.0
	var affix_note := Label.new()
	affix_note.text = "词缀怪（精英生成时按权重 1–2 条）："
	affix_note.add_theme_font_size_override("font_size", 12)
	affix_note.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	affix_note.position = Vector2(ax, ay)
	add_child(affix_note)

	var affixes := [
		["haste", "急速：移速 ×1.35，高速贴脸"],
		["lifesteal", "吸血：攻击回复自身 HP（20%）"],
		["explosive", "爆炸：死亡时 40px 内 80% 伤害"],
		["echo", "回响：攻击 30% 概率二连击"],
		["thorn", "荆棘：受击反弹 15% 伤害"],
		["phasing", "闪现：每 6 秒瞬移到玩家附近"],
	]
	for i in affixes.size():
		var cy := ay + 30.0 + float(i) * 36.0
		var block := ColorRect.new()
		block.color = TIER_COLORS["elite"]
		block.position = Vector2(ax, cy)
		block.size = Vector2(24, 24)
		add_child(block)
		var tip := Label.new()
		tip.text = "词缀「%s」  %s" % [affixes[i][0], affixes[i][1]]
		tip.add_theme_font_size_override("font_size", 11)
		tip.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		tip.position = Vector2(ax + 30, cy - 2)
		tip.size = Vector2(430, 30)
		add_child(tip)

	var foot := Label.new()
	foot.text = "占位色块美术（普通 暗红 / 精英 紫 / BOSS 金）· 新增 8 种亮色调 · AffixController 纯静态词缀池 · EnemyBase 集成移速/闪现/吸血/回响/荆棘/爆炸"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 690)
	add_child(foot)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/monsters_preview.png")
		print("monsters_preview saved: err=%d" % err)
		get_tree().quit(0)
