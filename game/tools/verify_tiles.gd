## 生物群系瓦片渲染验证（`tile_atlas.gd` + `level_view.gd` 的 `set_biome` 路径）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_tiles.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 背景：地图原先只有三种硬编码纯色矩形。本脚本守住「生物群系瓦片渲染」这条链路的
## 不变量 —— 尤其是**任务 8.3 的批处理前提**（整张地图一个 CanvasItem、无子节点），
## 防止后来者为了「好看」退化成每格一个 Sprite2D。
##
## 覆盖范围：
##   A. 20 关全部映射到非空 biome，且与章节（1/2/3 → 森林/火山/霜渊）一致；
##      章节越界时按 ambient_color 推断
##   B. 三个 biome 的占位图集可用（有贴图 / 三类 tile 各有变体 / 地面多变体 /
##      三类取到**不同**的图集格）
##   C. 占位图集确定性：同一 biome 重复生成 → 像素逐字节一致（跨运行可复现）
##   D. region_for 变体取模安全（越界 / 负数不越界）
##   E. LevelView：未设 biome 走纯色回退；设 biome 后 tile_count 不变、
##      仍是单节点（子节点 0）；清空 biome 能退回纯色且不崩
##   F. 出生点金色标记默认关闭（真实游戏不该出现），setter 可显式打开
extends Node2D

var _fail: int = 0


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 生物群系瓦片渲染验证 =====")
	await _run()
	_finish()


func _finish() -> void:
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _run() -> void:
	await _check_biome_mapping()
	_check_placeholder_atlas()
	_check_determinism()
	await _check_level_view()


# =============================================================================
# A. biome 映射
# =============================================================================

func _check_biome_mapping() -> void:
	var levels: Array[LevelData] = ConfigLoader.get_levels_sorted()
	_ok("关卡表读到 20 关", levels.size() == 20)

	var expect := {
		1: TileAtlas.BIOME_FOREST,
		2: TileAtlas.BIOME_VOLCANIC,
		3: TileAtlas.BIOME_FROST,
	}
	var bad: Array[String] = []
	for lv in levels:
		var b := TileAtlas.biome_for_level(lv)
		if b.is_empty() or b != expect.get(lv.chapter, b):
			bad.append("%s(ch%d→%s)" % [lv.id, lv.chapter, b])
	_ok("全部 %d 关 biome 非空且与章节一致（异常 %d 个）" % [levels.size(), bad.size()],
		levels.size() == 20 and bad.is_empty())
	if not bad.is_empty():
		print("      ", ", ".join(bad))

	# 章节缺失 / 越界 → 按 ambient_color 推断（LevelData 默认 chapter = 1，
	# 所以这里显式塞一个越界值来走推断分支）
	var probe := LevelData.new()
	probe.chapter = 9
	probe.ambient_color = Color(0.118, 0.180, 0.243)   # #1E2E3E 蓝主导
	_ok("章节越界 + 蓝主导 ambient → frost",
		TileAtlas.biome_for_level(probe) == TileAtlas.BIOME_FROST)
	probe.ambient_color = Color(0.353, 0.118, 0.055)   # #5A1E0E 红主导
	_ok("章节越界 + 红主导 ambient → volcanic",
		TileAtlas.biome_for_level(probe) == TileAtlas.BIOME_VOLCANIC)
	probe.ambient_color = Color(0.165, 0.227, 0.180)   # #2A3A2E 绿主导
	_ok("章节越界 + 绿主导 ambient → forest",
		TileAtlas.biome_for_level(probe) == TileAtlas.BIOME_FOREST)
	probe.ambient_color = Color(0, 0, 0, 0)            # 未设（alpha = 0）
	_ok("章节越界 + ambient 未设 → 兜底 forest",
		TileAtlas.biome_for_level(probe) == TileAtlas.BIOME_FOREST)
	_ok("null 关卡也不返回空 biome",
		not TileAtlas.biome_for_level(null).is_empty())


# =============================================================================
# B / D. 占位图集可用性 + 取模安全
# =============================================================================

func _check_placeholder_atlas() -> void:
	for biome in [TileAtlas.BIOME_FOREST, TileAtlas.BIOME_VOLCANIC, TileAtlas.BIOME_FROST]:
		var at := TileAtlas.for_biome(biome)
		_ok("%s：图集贴图可用" % biome, at.texture() != null)
		_ok("%s：同一 biome 二次取用命中缓存（同一实例）" % biome,
			TileAtlas.for_biome(biome) == at)

		var ng := at.variant_count(LevelGenerator.TILE_GROUND)
		var nw := at.variant_count(LevelGenerator.TILE_WALL)
		var no := at.variant_count(LevelGenerator.TILE_OBSTACLE)
		_ok("%s：三类 tile 都有变体（地面 %d / 墙 %d / 障碍 %d）" % [biome, ng, nw, no],
			ng >= 2 and nw >= 1 and no >= 1)

		var rg := at.region_for(LevelGenerator.TILE_GROUND, 0)
		var rw := at.region_for(LevelGenerator.TILE_WALL, 0)
		var ro := at.region_for(LevelGenerator.TILE_OBSTACLE, 0)
		_ok("%s：地面/墙/障碍取到不同图集格（%s / %s / %s）"
				% [biome, str(rg.position), str(rw.position), str(ro.position)],
			rg.position != rw.position and rw.position != ro.position
			and rg.position != ro.position)

		# 地面多变体必须落在**不同**格，否则「多变体」是假的
		var distinct := {}
		for i in ng:
			distinct[at.region_for(LevelGenerator.TILE_GROUND, i).position] = true
		_ok("%s：地面 %d 个变体互不相同" % [biome, ng], distinct.size() == ng)

		# 取模安全：越界回绕、负数不越界
		_ok("%s：region_for 越界回绕（%d 变体：%d+2 ≡ 2）" % [biome, ng, ng],
			at.region_for(LevelGenerator.TILE_GROUND, ng + 2)
			== at.region_for(LevelGenerator.TILE_GROUND, 2))
		_ok("%s：region_for 负数取模安全（-1 ≡ 末位）" % biome,
			at.region_for(LevelGenerator.TILE_GROUND, -1)
			== at.region_for(LevelGenerator.TILE_GROUND, ng - 1))

		# 真实美术集成：磁盘上摆了 atlas.png+atlas.json 就必须**真的被吃进去**，
		# 不能静默退回占位图（那种「看着没报错其实没生效」最难查）。
		var json_path := "res://assets/tilesets/%s/atlas.json" % biome
		if FileAccess.file_exists(json_path):
			_ok("%s：磁盘有 atlas.json ⇒ 确实加载了真实美术（未静默退回占位图）" % biome,
				at.has_real_art())
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
			var want_g := 0
			if parsed is Dictionary:
				want_g = (parsed.get("tiles", {}).get("ground", []) as Array).size()
			_ok("%s：地面变体数与 atlas.json 清单一致（清单 %d / 实际 %d）"
					% [biome, want_g, ng],
				want_g > 0 and ng == want_g)
		else:
			_ok("%s：无 atlas.json ⇒ 走程序化占位图集（地面变体 %d）" % [biome, ng],
				not at.has_real_art() and ng >= 2)


# =============================================================================
# C. 确定性
# =============================================================================

func _check_determinism() -> void:
	for biome in [TileAtlas.BIOME_FOREST, TileAtlas.BIOME_VOLCANIC, TileAtlas.BIOME_FROST]:
		var a := TileAtlas.build_placeholder_image(biome)
		var b := TileAtlas.build_placeholder_image(biome)
		_ok("%s：占位图集重复生成像素逐字节一致（%d×%d）"
				% [biome, a.get_width(), a.get_height()],
			a.get_width() == TileAtlas.COLS * TileAtlas.TILE_SIZE
			and a.get_height() == 3 * TileAtlas.TILE_SIZE
			and a.get_data() == b.get_data())

	# 三个 biome 必须真的长得不一样（否则「分生物群系」是假的）
	var imgs := {}
	for biome in [TileAtlas.BIOME_FOREST, TileAtlas.BIOME_VOLCANIC, TileAtlas.BIOME_FROST]:
		imgs[biome] = TileAtlas.build_placeholder_image(biome).get_data()
	var all_distinct := true
	var keys := imgs.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if imgs[keys[i]] == imgs[keys[j]]:
				all_distinct = false
	_ok("三个 biome 的占位图集互不相同", all_distinct)

	# 同一个 biome 内，各变体之间也必须不同（否则「变体」是假的）
	var one := TileAtlas.build_placeholder_image(TileAtlas.BIOME_FOREST)
	var v0 := one.get_region(Rect2i(0, 0, TileAtlas.TILE_SIZE, TileAtlas.TILE_SIZE)).get_data()
	var v1 := one.get_region(Rect2i(TileAtlas.TILE_SIZE, 0, TileAtlas.TILE_SIZE,
		TileAtlas.TILE_SIZE)).get_data()
	_ok("地面变体 0 与变体 1 像素不同（地板不会「盖章」重复）", v0 != v1)


# =============================================================================
# E / F. LevelView 两种分支 + 批处理前提
# =============================================================================

func _check_level_view() -> void:
	var lv := LevelView.new()
	_ok("出生点金色标记默认关闭", lv.show_spawn_marker == false)
	lv.show_spawn_marker = true
	_ok("setter 可显式打开出生点标记", lv.show_spawn_marker == true)
	lv.show_spawn_marker = false

	var level_def: LevelData = ConfigLoader.get_level("ch1_l01")
	_ok("取到关卡定义 ch1_l01", level_def != null)
	# 固定 seed：布局可复现，断言不 flaky
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260920
	var layout := LevelGenerator.generate(level_def, rng)
	var total: int = int(layout["cells"].size())

	# —— 未设 biome：纯色回退分支（既有预览工具 / verify 依赖的行为）——
	lv.set_layout(layout)
	_ok("未设 biome：纯色回退，tile_count = 全格数（%d）" % lv.tile_count(),
		lv.tile_count() == total and lv.biome().is_empty())

	# 真正进树跑一帧 _draw，把两个分支都执行到（崩溃会打印到日志）
	add_child(lv)
	await get_tree().process_frame
	_ok("纯色分支 _draw 执行后仍单节点（子节点 %d）" % lv.get_child_count(),
		lv.get_child_count() == 0)

	# —— 设 biome：图集分支 ——
	lv.set_biome(TileAtlas.biome_for_level(level_def), level_def.tileset_path)
	_ok("biome 回读 = forest", lv.biome() == TileAtlas.BIOME_FOREST)
	_ok("设 biome 后 tile_count 不变（%d）" % lv.tile_count(), lv.tile_count() == total)
	await get_tree().process_frame
	_ok("图集分支 _draw 执行后仍是单节点承载全图（子节点 %d）" % lv.get_child_count(),
		lv.get_child_count() == 0)
	_ok("设 biome 后无子节点 ⇒ draw call 未被拆成每格一个节点", lv.get_child_count() == 0)

	# —— 清空 biome：退回纯色，不崩 ——
	lv.set_biome("")
	await get_tree().process_frame
	_ok("清空 biome → 退回纯色分支且 tile_count 不变（%d）" % lv.tile_count(),
		lv.biome().is_empty() and lv.tile_count() == total)

	# —— 三个 biome 轮流设一遍，确认都不崩且 tile_count 稳定 ——
	var stable := true
	for biome in [TileAtlas.BIOME_FOREST, TileAtlas.BIOME_VOLCANIC, TileAtlas.BIOME_FROST]:
		lv.set_biome(biome)
		await get_tree().process_frame
		if lv.tile_count() != total or lv.get_child_count() != 0:
			stable = false
	_ok("三个 biome 轮设：tile_count 稳定 + 始终单节点", stable)

	lv.queue_free()
	await get_tree().process_frame
