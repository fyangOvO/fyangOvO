## 音效清单 + 波形渲染预览（任务 6.6 · 第 10 帧自截图）
## 用法：godot --path "D:/七傳說/game" res://tools/audio_preview.tscn
##   输出 build/audio_preview.png：8 条合成音效卡片（用途 + 时长 + 波形）
extends Node2D

var _frame := 0

const META := {
	"hit_melee": ["打击 · 普攻命中", "方波 200Hz + 噪声 · 0.12s"],
	"hit_crit": ["暴击 · 高亮命中", "方波 340Hz + 泛音 · 0.18s"],
	"enemy_die": ["死亡 · 怪物阵亡", "正弦 600→150Hz 扫频 · 0.25s"],
	"pickup_gold": ["拾取金币/材料", "正弦 1200→1800Hz · 0.09s"],
	"pickup_item": ["拾取装备", "三角波 700→1100Hz · 0.14s"],
	"levelup": ["升级 · 局内升等", "琶音 523/659/784Hz · 0.42s"],
	"boss_phase": ["BOSS 阶段切换", "锯齿 160→55Hz 低吼 · 0.5s"],
	"ui_click": ["UI 点击", "短方波 1000Hz · 0.04s"],
}

const BAR_COLORS := [
	Color(0.9, 0.5, 0.3), Color(0.95, 0.78, 0.3), Color(0.6, 0.4, 0.85),
	Color(0.95, 0.65, 0.2), Color(0.4, 0.7, 0.9), Color(0.45, 0.8, 0.4),
	Color(0.85, 0.35, 0.35), Color(0.6, 0.75, 0.9),
]


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "音效/音乐预览（任务 6.6 · 8 条程序化合成占位音效 + 播放管线）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
	title.position = Vector2(16, 8)
	add_child(title)

	var y0 := 64.0
	var row_h := 74.0
	var ids := AudioManager.ids()
	for i in ids.size():
		var id: String = ids[i]
		var meta: Dictionary = AudioManager.SFX_REGISTRY[id]
		var cy := y0 + float(i) * row_h
		# 卡片
		var card := ColorRect.new()
		card.color = Color(0.09, 0.09, 0.12)
		card.position = Vector2(24, cy)
		card.size = Vector2(1870, 64)
		add_child(card)
		# 色条
		var bar := ColorRect.new()
		bar.color = BAR_COLORS[i % BAR_COLORS.size()]
		bar.position = Vector2(24, cy)
		bar.size = Vector2(6, 64)
		add_child(bar)
		# 名称 + 用途
		var nm := Label.new()
		nm.text = "%s  ·  %s" % [id, META.get(id, ["", ""])[0]]
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
		nm.position = Vector2(44, cy + 6)
		add_child(nm)
		var spec := Label.new()
		spec.text = "%s  ·  音量 %d dB" % [META.get(id, ["", ""])[1],
			int(meta.get("volume_db", 0.0))]
		spec.add_theme_font_size_override("font_size", 11)
		spec.add_theme_color_override("font_color", Color(0.72, 0.76, 0.8))
		spec.position = Vector2(44, cy + 28)
		add_child(spec)
		# 波形（AudioStreamWAV.data 为 16-bit PCM，缩放绘制）
		var stream := AudioManager._stream_for(id) as AudioStreamWAV
		if stream != null and not stream.data.is_empty():
			var samples := stream.data
			var total := int(samples.size() / 2)
			var pts: PackedVector2Array = []
			var w := 900.0
			var h := 50.0
			var x0 := 880.0
			var yc := cy + 32.0
			var step := maxi(1, int(total / 240))
			for k in range(0, total, step):
				var idx := k * 2
				var lo := samples[idx]
				var hi := samples[idx + 1]
				var s16: int = hi << 8 | lo
				if s16 > 32767:
					s16 -= 65536
				var x := x0 + float(k) / float(total) * w
				var y := yc + float(s16) / 32768.0 * h * 0.9
				pts.append(Vector2(x, y))
			if pts.size() > 2:
				var poly := Line2D.new()
				poly.points = pts
				poly.width = 1.5
				poly.default_color = Color(0.9, 0.9, 0.6, 0.9)
				add_child(poly)

	var foot := Label.new()
	foot.text = "占位合成（22050Hz 16-bit mono，Python wave 生成）· 真音频可直接替换 data/audio/*.wav · 播放即焚管线 AudioManager.play(id)"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	foot.position = Vector2(16, 690)
	add_child(foot)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("res://build/audio_preview.png")
		print("audio_preview saved: err=%d" % err)
		get_tree().quit(0)
