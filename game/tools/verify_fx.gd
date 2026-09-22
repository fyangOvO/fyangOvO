## 特效贴图层验证（`fx_table.gd` + `fx_sprite.gd` + `data/fx.json` + `assets/fx/*.png`）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_fx.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 背景：本层是「用户不改代码换特效贴图」的唯一接口。它有三个容易**静默**坏掉的地方，
## 本脚本就是来盯死它们的：
##   ① 贴图丢了 → `FxTable.spawn` 返回 null → 游戏退回代码绘制、**不报错**（手感变弱但全绿）；
##   ② 色板铁律（`game_constants.gd:607`）说烘焙图像资产必须全落在 `PALETTE_ALL`，
##      而运行时 `Texture2D.get_image()` 在无头下不保证可用 ⇒ 必须在**文件层**验；
##   ③ 用户塞一张尺寸不匹配的 PNG（`frames` 写多了）→ 必须夹到装得下的帧数且不崩。
##
## 覆盖范围：
##   A. 表与资产：fx.json 可加载 / 7 条必需 id 齐全 / 每条贴图可解析 / spec 字段合法 /
##      frame_w×frames ≤ 贴图宽
##   B. 色板铁律：每张 PNG 的不透明像素 100% ∈ PALETTE_ALL，且 alpha 二值
##   C. FxSprite：帧号随时间前进 / loop=false 播完自释放 / loop=true 不自释放 /
##      帧数超宽时夹取 / 三种 anchor 的目标矩形 / fade 让 alpha 递减
##   D. 健壮性：未知 id 返回 null 不崩 / clear_cache 后可重载
extends Node2D

const FX_DIR := "res://assets/fx"
const REQUIRED_IDS: Array[String] = [
	"hit_spark", "slash_arc", "level_up_burst", "pickup_glow", "death_puff",
	"ember_lord_aura", "pyromancer_cast",
]
const VALID_ANCHORS: Array[String] = ["center", "top_left", "bottom_center"]
const VALID_Z: Array[String] = ["above_actors", "below_actors"]

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	VerifyWatchdog.arm(get_tree())
	print("===== 特效贴图层验证 =====")
	await _run()
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _run() -> void:
	_check_table_and_assets()
	_check_palette_iron_law()
	await _check_fx_sprite()
	_check_robustness()


# =============================================================================
# A. 表与资产
# =============================================================================

func _check_table_and_assets() -> void:
	print("--- A. 特效表与贴图资产 ---")
	_ok("fx.json 已加载（%d 条）" % FxTable.all_ids().size(), FxTable.is_loaded())

	var ids := FxTable.all_ids()
	for want in REQUIRED_IDS:
		_ok("必需特效 id 存在：%s" % want, ids.has(want))

	var bad_spec: Array[String] = []
	var missing: Array[String] = []
	var too_narrow: Array[String] = []
	for id in ids:
		var sp := FxTable.spec(id)
		var fw := int(sp.get("frame_w", 0))
		var fh := int(sp.get("frame_h", 0))
		var n := int(sp.get("frames", 0))
		var fps := float(sp.get("fps", 0.0))
		var anchor := str(sp.get("anchor", ""))
		var z := str(sp.get("z", ""))
		if fw <= 0 or fh <= 0 or n <= 0 or fps <= 0.0 \
				or not VALID_ANCHORS.has(anchor) or not VALID_Z.has(z):
			bad_spec.append(id)
		var tex := FxTable.texture_for(id)
		if tex == null:
			missing.append(id)
			continue
		if tex.get_width() < fw * n or tex.get_height() < fh:
			too_narrow.append("%s(%d<%d)" % [id, tex.get_width(), fw * n])

	_ok("全部 spec 字段合法（frame_w/h>0 · frames>0 · fps>0 · anchor/z 取值合法）",
		bad_spec.is_empty())
	_ok("全部贴图可解析（缺：%s）" % ("无" if missing.is_empty() else ", ".join(missing)),
		missing.is_empty())
	_ok("frame_w×frames ≤ 贴图宽（不合法：%s）"
			% ("无" if too_narrow.is_empty() else ", ".join(too_narrow)),
		too_narrow.is_empty())
	_ok("has_texture 与 texture_for 口径一致",
		FxTable.has_texture("hit_spark") and not FxTable.has_texture("__no_such_effect__"))


# =============================================================================
# B. 色板铁律（在**文件层**验，不依赖渲染器）
# =============================================================================

func _check_palette_iron_law() -> void:
	print("--- B. 色板铁律（PALETTE_ALL）---")
	_ok("PALETTE_ALL = %d 色" % GameConstants.PALETTE_ALL.size(),
		GameConstants.PALETTE_ALL.size() == 44)

	var ids := FxTable.all_ids()
	var checked := 0
	for id in ids:
		var rel := str(FxTable.spec(id).get("texture", ""))
		if rel.is_empty():
			continue
		var path := "%s/%s" % [FX_DIR, rel]
		var img := _load_image_for_check(path)
		if img == null:
			_ok("可读取贴图文件 %s" % rel, false)
			continue
		checked += 1

		# `Image.convert()` 原地改格式并返回 void（Godot 4），不能接返回值。
		img.convert(Image.FORMAT_RGBA8)
		var raw := img.get_data()
		var off_palette := 0
		var semi_alpha := 0
		var opaque := 0
		var i := 0
		while i < raw.size():
			var a := raw[i + 3]
			if a == 0:
				i += 4
				continue
			if a != 255:
				semi_alpha += 1
			opaque += 1
			var c := Color8(raw[i], raw[i + 1], raw[i + 2], 255)
			if not GameConstants.palette_contains(c):
				off_palette += 1
			i += 4

		_ok("%s：不透明像素 %d 个，色板外 %d 个，半透明 %d 个"
				% [rel, opaque, off_palette, semi_alpha],
			opaque > 0 and off_palette == 0 and semi_alpha == 0)

	_ok("全部 %d 张特效贴图已逐像素校验" % checked, checked == ids.size())


## 读贴图做逐像素校验。
## 优先资源系统（已导入 ⇒ **导出后仍可用**）；`tile_atlas.gd:184` 记录过
## 「headless 下 `Texture2D.get_image()` 不保证可用」，所以失败时退回裸文件解码
## （裸解码只适用于编辑器内 —— 它读不到导出后的 .ctex）。
func _load_image_for_check(path: String) -> Image:
	if ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path)
		if res is Texture2D:
			var img := (res as Texture2D).get_image()
			if img != null and not img.is_empty():
				return img
	var raw := Image.new()
	if raw.load(path) == OK:
		return raw
	return null


# =============================================================================
# C. FxSprite 行为
# =============================================================================

func _check_fx_sprite() -> void:
	print("--- C. FxSprite 播放行为 ---")

	# ① 帧数超出贴图宽度 → 夹取，不崩
	var tex := FxTable.texture_for("hit_spark")
	if tex == null:
		_ok("hit_spark 贴图可用（后续 C 段前置）", false)
		return
	var probe := FxSprite.new()
	var ok_setup := probe.setup({
		"frame_w": 32, "frame_h": 32, "frames": 999, "fps": 18.0,
		"loop": false, "anchor": "center", "z": "above_actors",
	}, tex)
	_ok("setup() 成功且把超宽帧数夹到装得下的帧数（999 → %d）" % probe.frame_count,
		ok_setup and probe.frame_count == tex.get_width() / 32)
	probe.free()

	# ② 三种 anchor 的目标矩形
	var a := FxSprite.new()
	a.frame_w = 40
	a.frame_h = 20
	_ok("anchor=center 矩形以原点为中心",
		a._dest_rect() == Rect2(-20.0, -10.0, 40.0, 20.0))
	a.anchor = "top_left"
	_ok("anchor=top_left 矩形左上角在原点",
		a._dest_rect() == Rect2(0.0, 0.0, 40.0, 20.0))
	a.anchor = "bottom_center"
	_ok("anchor=bottom_center 矩形底边贴原点",
		a._dest_rect() == Rect2(-20.0, -20.0, 40.0, 20.0))
	a.free()

	# ③ 帧号随 `delta` 前进 —— **不入树**、手动喂 delta。
	#    为什么不 await 真实帧：无头下帧间隔由引擎自由决定（首帧可能一次跳过好几帧），
	#    用真实帧计时去数「观察到的不同帧数」是 flaky 的。手动喂 delta 才是确定性的。
	var adv := FxSprite.new()
	adv.setup({"frame_w": 32, "frame_h": 32, "frames": 4, "fps": 10.0,
		"loop": false, "anchor": "center", "z": "above_actors"}, tex)
	var seen: Array[int] = []
	for _i in 4:
		adv._process(0.1)          # 0.1s × 10fps = 每步正好一帧
		seen.append(adv._frame)
	var distinct := {}
	for v in seen:
		distinct[v] = true
	var monotonic := true
	for i in range(1, seen.size()):
		if seen[i] < seen[i - 1]:
			monotonic = false
	_ok("帧号随 delta 前进（%s）" % str(seen),
		distinct.size() >= 3 and monotonic and seen[0] >= 1)
	adv.free()

	# ④ loop=false：总时长走完后 `queue_free()`（入树，让引擎真的处理释放）
	var once := FxSprite.new()
	add_child(once)
	_ok("FxSprite 入树即挂进 fx_sprites 组（工具/自检可数）",
		once.is_in_group(&"fx_sprites"))
	once.setup({"frame_w": 32, "frame_h": 32, "frames": 2, "fps": 120.0,
		"loop": false, "anchor": "center", "z": "above_actors"}, tex)
	var freed := false
	for _i in 120:
		await get_tree().process_frame
		if not is_instance_valid(once) or once.is_queued_for_deletion():
			freed = true
			break
	_ok("loop=false 播完自动释放（总时长 %.4fs）" % (2.0 / 120.0), freed)

	# ⑤ loop=true：同样时长下**不**释放
	var rep := FxSprite.new()
	add_child(rep)
	rep.setup({"frame_w": 32, "frame_h": 32, "frames": 2, "fps": 0.5,
		"loop": true, "anchor": "center", "z": "above_actors"}, tex)
	for _i in 30:
		await get_tree().process_frame
	_ok("loop=true 循环播放且不自动释放", is_instance_valid(rep) and not rep.is_queued_for_deletion())
	_ok("loop=true 帧号被夹在 [0, frames)（当前 %d）" % rep._frame,
		rep._frame >= 0 and rep._frame < rep.frame_count)
	rep.queue_free()

	# ⑥ fade：alpha 递减
	var f := FxSprite.new()
	add_child(f)
	f.setup({"frame_w": 32, "frame_h": 32, "frames": 4, "fps": 0.5,
		"loop": true, "anchor": "center", "z": "above_actors", "fade": true}, tex)
	var a0 := f.modulate.a
	for _i in 20:
		await get_tree().process_frame
	_ok("fade=true 期间 modulate.a 递减（%.2f → %.2f）" % [a0, f.modulate.a],
		f.modulate.a < a0 and f.modulate.a >= 0.0)
	f.queue_free()


# =============================================================================
# D. 健壮性
# =============================================================================

func _check_robustness() -> void:
	print("--- D. 健壮性 ---")
	_ok("未知 id：has_texture = false", not FxTable.has_texture("__no_such_effect__"))
	_ok("未知 id：spawn 返回 null 而不崩", FxTable.spawn("__no_such_effect__", Vector2.ZERO) == null)

	# 贴图缺失的 id（表里有、文件没有）→ spawn 返回 null（走调用方兜底），不崩
	_ok("表里没有的 id：spec 为空字典", FxTable.spec("__no_such_effect__").is_empty())

	# z 语义映射
	_ok("z 常量：above_actors > 0 > below_actors",
		FxTable.Z_ABOVE_ACTORS > 0 and FxTable.Z_BELOW_ACTORS < 0)

	# clear_cache 后可重载
	var before := FxTable.all_ids().size()
	FxTable.clear_cache()
	var after := FxTable.all_ids().size()
	_ok("clear_cache() 后可重新加载（%d → %d 条）" % [before, after], after == before)
	_ok("重载后贴图仍可解析", FxTable.texture_for("hit_spark") != null)
