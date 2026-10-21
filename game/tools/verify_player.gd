## 玩家控制器 + 输入系统实测（开发用，不属于游戏玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_player.tscn
##   退出码 0 = 全部通过；1 = 有失败项
##
## 覆盖范围（任务 1.3 + 2.1）：
##   A. 输入映射：每个动作都有「≥1 键 + ≥1 手柄事件」
##   B. 移动：8 方向速度向量正确；**对角线必须归一化**（不能是 √2 倍速度）
##   C. 闪避：位移距离 ≈ dodge_distance；无敌帧时长 ≈ dodge_iframe_duration；
##            冷却 ≈ dodge_cooldown；无敌帧长于冲刺时长
##   D. 锚点结构：Body → Weapon → Fx 层级顺序；主/副手锚点存在且归 WeaponLayer 管辖
##   E. 锚点随朝向变化（8 方向偏移表）
##   F. 重绑定：rebind 只替换同设备类别 / reset_to_default / save+load 往返
##
## ⚠️ F 段会**真实读写** `user://input_bindings.json`。脚本会在开跑前备份该文件、
##    结束时还原（原本不存在则删除），不会破坏玩家已有的按键设置。
extends Node

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"

var _fail: int = 0
var _player: PlayerController = null
var _bindings_backup: String = ""
var _bindings_existed: bool = false


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _await_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	# 失败兜底看门狗：中途异常不得让进程挂死（否则 CI 上是「卡满超时」而非「失败」）
	VerifyWatchdog.arm(get_tree())
	print("===== 玩家控制器 + 输入系统实测 =====")
	_backup_bindings()

	var packed: PackedScene = load(PLAYER_SCENE)
	_ok("player.tscn 可加载", packed != null)
	if packed == null:
		_finish()
		return
	_player = packed.instantiate() as PlayerController
	_ok("根节点是 PlayerController", _player != null)
	if _player == null:
		_finish()
		return
	add_child(_player)
	await _await_frames(2)

	await _test_input_map()
	await _test_anchors()
	await _test_movement()
	await _test_dodge()
	await _test_anchor_follows_facing()
	await _test_weapon_mount()
	await _test_visual_tier()
	await _test_armor_piece()
	await _test_rebind()

	_finish()


# =============================================================================
# A. 输入映射
# =============================================================================

func _test_input_map() -> void:
	print("--- A. 输入映射（每个动作需 ≥1 键 + ≥1 手柄事件）---")
	var missing: PackedStringArray = []
	for action in InputRemapper.MANAGED_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(String(action))
			continue
		var keys := 0
		var pads := 0
		for e in InputMap.action_get_events(action):
			if e is InputEventKey or e is InputEventMouseButton:
				keys += 1
			elif e is InputEventJoypadButton or e is InputEventJoypadMotion:
				pads += 1
		if keys == 0 or pads == 0:
			missing.append("%s(键%d/柄%d)" % [action, keys, pads])
	_ok("全部 %d 个动作均有键 + 手柄双映射" % InputRemapper.MANAGED_ACTIONS.size(), missing.is_empty())
	if not missing.is_empty():
		_info("缺映射：%s" % ", ".join(missing))

	# 旧的 Godot 3 风格动作名应已清除，避免与新手感方案并存造成歧义
	var legacy := [&"skill_primary", &"skill_secondary", &"skill_ultimate", &"ui_pause"]
	var leftovers: PackedStringArray = []
	for a in legacy:
		if InputMap.has_action(a):
			leftovers.append(String(a))
	_ok("旧的 skill_primary/secondary/ultimate/ui_pause 已移除", leftovers.is_empty())
	if not leftovers.is_empty():
		_info("残留：%s" % ", ".join(leftovers))


# =============================================================================
# D. 锚点结构
# =============================================================================

func _test_anchors() -> void:
	print("--- D. 武器层三层结构与锚点 ---")
	var main_anchor := _player.get_node_or_null(NodePath("WeaponLayer/MainHandAnchor"))
	var off_anchor := _player.get_node_or_null(NodePath("WeaponLayer/OffHandAnchor"))
	_ok("MainHandAnchor 存在", main_anchor != null)
	_ok("OffHandAnchor 存在", off_anchor != null)
	_ok("MainHandAnchor 是 Marker2D", main_anchor is Marker2D)
	_ok("OffHandAnchor 是 Marker2D", off_anchor is Marker2D)

	var body := _player.get_node_or_null(NodePath("BodySprite"))
	var weapon := _player.get_node_or_null(NodePath("WeaponLayer"))
	var fx := _player.get_node_or_null(NodePath("FxLayer"))
	_ok("BodySprite / WeaponLayer / FxLayer 均存在", body != null and weapon != null and fx != null)
	if body != null and weapon != null and fx != null:
		_ok("绘制层级顺序为 Body → Weapon → Fx",
			body.get_index() < weapon.get_index() and weapon.get_index() < fx.get_index())
		_info("兄弟序号：Body=%d Weapon=%d Fx=%d" % [body.get_index(), weapon.get_index(), fx.get_index()])
		_ok("WeaponLayer 是独立容器（不挂在 BodySprite 下）", weapon.get_parent() == _player)
		_ok("锚点归 WeaponLayer 管辖",
			main_anchor != null and main_anchor.get_parent() == weapon)

	# 占位武器精灵必须挂在锚点上（阶段 3 换成真实装备精灵时位置不变）
	var ph_main := main_anchor.get_node_or_null(NodePath("PlaceholderMainWeapon")) if main_anchor != null else null
	var ph_off := off_anchor.get_node_or_null(NodePath("PlaceholderOffWeapon")) if off_anchor != null else null
	_ok("主手锚点下挂有占位武器 Sprite2D", ph_main is Sprite2D)
	_ok("副手锚点下挂有占位武器 Sprite2D", ph_off is Sprite2D)
	_ok("主手占位武器为 32×8 条状（便于肉眼看出朝向翻转）",
		ph_main is Sprite2D and (ph_main as Sprite2D).texture != null
		and (ph_main as Sprite2D).texture.get_width() == 32
		and (ph_main as Sprite2D).texture.get_height() == 8)


# =============================================================================
# B. 移动
# =============================================================================

func _test_movement() -> void:
	print("--- B. 8 方向移动与对角线归一化 ---")
	var cases := [
		{"name": "上", "acts": [&"move_up"], "expect": Vector2(0, -1)},
		{"name": "下", "acts": [&"move_down"], "expect": Vector2(0, 1)},
		{"name": "左", "acts": [&"move_left"], "expect": Vector2(-1, 0)},
		{"name": "右", "acts": [&"move_right"], "expect": Vector2(1, 0)},
		{"name": "左上", "acts": [&"move_left", &"move_up"], "expect": Vector2(-1, -1).normalized()},
		{"name": "右上", "acts": [&"move_right", &"move_up"], "expect": Vector2(1, -1).normalized()},
		{"name": "左下", "acts": [&"move_left", &"move_down"], "expect": Vector2(-1, 1).normalized()},
		{"name": "右下", "acts": [&"move_right", &"move_down"], "expect": Vector2(1, 1).normalized()},
	]
	var speed: float = PlayerController.LOCAL_MOVE_SPEED
	var bad: PackedStringArray = []
	for c in cases:
		_player.global_position = Vector2.ZERO
		_player.velocity = Vector2.ZERO
		# 先减速到静止，避免上一轮的残余速度污染
		await _await_frames(12)

		for a in c["acts"]:
			Input.action_press(a)
		await _await_frames(20) # 20 帧 = 0.33s，远超加速到满速所需的 0.12s

		var v: Vector2 = _player.velocity
		var want: Vector2 = (c["expect"] as Vector2) * speed
		var dir_ok: bool = v.normalized().dot(want.normalized()) > 0.999
		var mag_ok: bool = absf(v.length() - speed) < 1.0
		if not (dir_ok and mag_ok):
			bad.append("%s(实际 %s / 期望 %s)" % [c["name"], v, want])

		for a in c["acts"]:
			Input.action_release(a)
		await _await_frames(12)

	_ok("8 个方向的速度向量方向与模长均正确", bad.is_empty())
	if not bad.is_empty():
		_info("异常：%s" % ", ".join(bad))

	# 对角线归一化：单独断言，因为「√2 倍速度」是这类控制器的经典 bug
	_player.global_position = Vector2.ZERO
	Input.action_press(&"move_right")
	Input.action_press(&"move_down")
	await _await_frames(20)
	var diag: float = _player.velocity.length()
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	await _await_frames(12)
	_ok("对角线速度已归一化（≈%.1f，不是 %.1f）" % [speed, speed * sqrt(2.0)],
		absf(diag - speed) < 1.0)
	_info("实测对角线速度 = %.2f px/s" % diag)

	# 松手后应减速滑行而非瞬停
	_player.global_position = Vector2.ZERO
	Input.action_press(&"move_right")
	await _await_frames(20)
	Input.action_release(&"move_right")
	await _await_frames(2)
	var coasting: float = _player.velocity.length()
	await _await_frames(20)
	_ok("松手后先滑行再停下（非瞬停）", coasting > 1.0 and coasting < speed)
	_info("松手 2 帧后残余速度 = %.2f px/s，最终 = %.2f" % [coasting, _player.velocity.length()])


# =============================================================================
# C. 闪避
# =============================================================================

func _test_dodge() -> void:
	print("--- C. 闪避（冲刺距离 / 无敌帧 / 冷却）---")
	# 先跑掉上一次测试可能残留的冷却
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	await _await_frames(60)

	# 优先走**真实输入路径**（InputEventAction → _unhandled_input）；
	# 若无头环境下事件投递不可用，退回直接调用并如实标注。
	var used_real_input: bool = true
	var ev := InputEventAction.new()
	ev.action = &"dodge"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _await_frames(1)
	if not _player.is_dodging():
		used_real_input = false
		_player.try_dodge()
		await _await_frames(1)
	_info("触发方式：%s" % ("InputEventAction 真实输入链路" if used_real_input else "直接调用 try_dodge()（无头下事件未投递）"))
	_ok("闪避已触发", _player.is_dodging())
	_ok("冲刺期间处于无敌帧", _player.is_invulnerable())

	var start: Vector2 = _player.global_position

	# ⚠️ 计时口径：三个计时器（冲刺 / 无敌帧 / 冷却）都是**从闪避触发瞬间**开始跑的，
	#    所以必须用同一个「已过帧数」计数器连续量三段，不能各段各自重新起算 ——
	#    否则会把冲刺那段时长从后两段里漏掉（这正是本脚本第一版踩的坑）。
	var elapsed: int = 0
	while _player.is_dodging() and elapsed < 120:
		await _await_frames(1)
		elapsed += 1
	var dash_frames: int = elapsed
	var travelled: float = _player.global_position.distance_to(start)
	_ok("冲刺位移 ≈ dodge_distance（%.1f px）" % _player.dodge_distance,
		absf(travelled - _player.dodge_distance) < 8.0)
	_info("实测位移 = %.2f px，冲刺用时 %d 帧（期望 %.0f 帧）"
		% [travelled, dash_frames, _player.dodge_duration * 60.0])

	# 冲刺结束后无敌帧应当仍然有效（iframes 0.30 > duration 0.18）
	_ok("冲刺结束后无敌帧仍在（i-frames 长于冲刺时长）", _player.is_invulnerable())

	while _player.is_invulnerable() and elapsed < 240:
		await _await_frames(1)
		elapsed += 1
	var iframe_frames: int = elapsed
	var expected_iframe_frames: float = _player.dodge_iframe_duration * 60.0
	_ok("无敌帧总时长 ≈ %.2fs（自闪避触发起算）" % _player.dodge_iframe_duration,
		absf(float(iframe_frames) - expected_iframe_frames) <= 4.0)
	_info("实测无敌帧 = %d 帧（期望 %.0f 帧）" % [iframe_frames, expected_iframe_frames])

	_ok("无敌帧结束时仍在冷却中", _player.get_dodge_cooldown_remaining() > 0.0)
	while _player.get_dodge_cooldown_remaining() > 0.0 and elapsed < 400:
		await _await_frames(1)
		elapsed += 1
	var cd_frames: int = elapsed
	_ok("冷却总时长 ≈ %.2fs（自闪避触发起算）" % _player.dodge_cooldown,
		absf(float(cd_frames) - _player.dodge_cooldown * 60.0) <= 6.0)
	_info("实测冷却 = %d 帧（期望 %.0f 帧）" % [cd_frames, _player.dodge_cooldown * 60.0])

	# 冷却结束后应能再次闪避
	_ok("冷却结束后可再次闪避", _player.try_dodge())
	await _await_frames(30)
	while _player.is_dodging():
		await _await_frames(1)
	await _await_frames(60)


# =============================================================================
# E. 锚点随朝向变化
# =============================================================================

func _test_anchor_follows_facing() -> void:
	print("--- E. 锚点随 8 方向朝向变化 ---")
	var seen: Dictionary = {}
	var names := ["下", "左下", "左", "左上", "上", "右上", "右", "右下"]
	for f in PlayerController.FACING_COUNT:
		_player.set_facing(f)
		await _await_frames(1)
		var mp: Vector2 = _player.main_hand_anchor.position
		var op: Vector2 = _player.off_hand_anchor.position
		seen[mp] = true
		_info("%s：主手 %s / 副手 %s" % [names[f], mp, op])

	_ok("8 个朝向产生 8 组不同的主手锚点位置", seen.size() == PlayerController.FACING_COUNT)

	# 镜像校验：朝下与朝上时，主手应分居中线两侧
	_player.set_facing(PlayerController.Facing8.DOWN)
	await _await_frames(1)
	var down_x: float = _player.main_hand_anchor.position.x
	_player.set_facing(PlayerController.Facing8.UP)
	await _await_frames(1)
	var up_x: float = _player.main_hand_anchor.position.x
	_ok("朝下与朝上的主手锚点分居中线两侧（右手镜像）", down_x * up_x < 0.0)
	_info("朝下 x=%.1f / 朝上 x=%.1f" % [down_x, up_x])

	# 全局坐标应随角色位移同步（阶段 3 装备上身依赖这一点）
	_player.global_position = Vector2(500, 300)
	await _await_frames(1)
	var gp: Vector2 = _player.get_main_hand_global_position()
	_ok("主手全局坐标随角色位移同步",
		absf(gp.x - (500.0 + _player.main_hand_anchor.position.x)) < 0.01)
	_player.global_position = Vector2.ZERO
	await _await_frames(1)


# =============================================================================
# G. 装备可视化第1期：武器层挂载
# =============================================================================

## 覆盖装备可视化子批2：apply_equipment_visual 挂载主手武器 → RealWeapon
## 生成 / 可见 / 纹理非空 / 朝向刷新 / 卸下隐藏；占位节点必须原样保留。
func _test_weapon_mount() -> void:
	print("--- G. 装备可视化：武器层挂载 ---")
	var main_anchor := _player.get_node_or_null(NodePath("WeaponLayer/MainHandAnchor"))
	var off_anchor := _player.get_node_or_null(NodePath("WeaponLayer/OffHandAnchor"))
	var tpl: EquipmentData = ConfigLoader.get_equipment_template("sword_flame")
	_ok("sword_flame 模板存在（武器层挂载测试源）", tpl != null)
	if tpl == null or main_anchor == null or off_anchor == null:
		return

	var inst := EquipmentInstance.new()
	inst.template = tpl
	_player.apply_equipment_visual([inst])
	await _await_frames(2)
	var rw := main_anchor.get_node_or_null(NodePath("RealWeapon")) as Sprite2D
	_ok("挂载后主手锚点下生成 RealWeapon", rw != null)
	_ok("RealWeapon 直接挂在 MainHandAnchor 下", rw != null and rw.get_parent() == main_anchor)
	_ok("RealWeapon 可见", rw != null and rw.visible)
	_ok("RealWeapon 已加载武器纹理", rw != null and rw.texture != null)
	_ok("RealWeapon 纹理过滤为 Nearest（像素铁律）",
		rw != null and rw.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)

	var ph := main_anchor.get_node_or_null(NodePath("PlaceholderMainWeapon"))
	_ok("占位武器节点未被挂载破坏", ph is Sprite2D)
	_ok("占位武器纹理仍是 32×8（既有契约）",
		ph is Sprite2D and (ph as Sprite2D).texture != null
		and (ph as Sprite2D).texture.get_width() == 32
		and (ph as Sprite2D).texture.get_height() == 8)

	var tex_s: Texture2D = rw.texture if rw != null else null
	_player.set_facing(PlayerController.Facing8.RIGHT)
	# 转向去抖：_anim_dir 需稳定保持 TURN_HOLD 秒才切换，等 12 帧（0.2s > 0.08s）越过窗口
	await _await_frames(12)
	var tex_e: Texture2D = rw.texture if rw != null else null
	_ok("朝向右后武器纹理切换（s→e 不同文件）", tex_s != null and tex_e != null and tex_s != tex_e)

	_player.apply_equipment_visual([])
	await _await_frames(1)
	_ok("卸下后 RealWeapon 隐藏", rw != null and not rw.visible)


# =============================================================================
# H. 装备可视化第1期：防具换色（外观档）
# =============================================================================

## 覆盖装备可视化子批3：防具槽最高稀有度 → 外观档 → 预烘换色帧集切换；
## 普通防具 / 卸下后必须回到默认职业色。
func _test_visual_tier() -> void:
	print("--- H. 装备可视化：防具换色（外观档） ---")
	var chest_tpl: EquipmentData = ConfigLoader.get_equipment_template("chest_chainmail")
	_ok("chest_chainmail 模板存在（外观档测试源）", chest_tpl != null)
	if chest_tpl == null:
		return
	# 玩家游戏内 art_id 由职业驱动（warrior / archer / mage）；测试统一用 warrior 外观基准。
	# 注：set_visual_tier(-1) 首调因 _visual_tier_rarity 初值即 -1 会早退，须手动应用基准。
	_player.art_id = "warrior"
	var art_w := EnemyBase.resolve_character_set("warrior")
	_player._apply_real_art(art_w)
	_player._apply_facing()
	await _await_frames(2)
	var base_tex: Texture2D = _player.body_sprite.texture
	_ok("默认外观帧已加载（warrior 金色）", base_tex != null)
	var inst := EquipmentInstance.create_from_template(
		chest_tpl, 1, GameConstants.Rarity.MAGIC)
	_player.apply_equipment_visual([inst])
	await _await_frames(2)
	var tint_tex: Texture2D = _player.body_sprite.texture
	_ok("穿魔法防具后角色帧切换为换色档（纹理改变）",
		tint_tex != null and base_tex != null and tint_tex != base_tex)
	_player.apply_equipment_visual([])
	await _await_frames(4)
	_ok("卸下后回到默认职业色（warrior 素材，非换色档）",
		_player.body_sprite.texture.resource_path.begins_with("res://assets/pack/creatures/warrior/"))
	var inst_c := EquipmentInstance.create_from_template(
		chest_tpl, 1, GameConstants.Rarity.COMMON)
	_player.apply_equipment_visual([inst_c])
	await _await_frames(4)
	_ok("普通防具保持默认职业色（warrior 素材，非换色档）",
		_player.body_sprite.texture.resource_path.begins_with("res://assets/pack/creatures/warrior/"))
	_player.apply_equipment_visual([])


# =============================================================================
# I. 装备可视化第2期：防具外观分件层（头盔 / 胸甲）
# =============================================================================

## 覆盖装备可视化子批4：穿 helm / chest → HeadAnchor / ChestAnchor 下各挂
## RealArmorPiece 可见、纹理非空、Nearest、帧名目录前缀正确；换稀有度走
## tint 目录；卸下隐藏。
func _test_armor_piece() -> void:
	print("--- I. 装备可视化：防具外观分件层 ---")
	var head := _player.get_node_or_null(NodePath("ArmorLayer/HeadAnchor")) as Marker2D
	var chest := _player.get_node_or_null(NodePath("ArmorLayer/ChestAnchor")) as Marker2D
	_ok("ArmorLayer 锚点存在（HeadAnchor/ChestAnchor）", head != null and chest != null)
	if head == null or chest == null:
		return
	var helm_tpl: EquipmentData = ConfigLoader.get_equipment_template("helm_hide")
	var chest_tpl: EquipmentData = ConfigLoader.get_equipment_template("chest_chainmail")
	_ok("分件模板存在（helm_hide / chest_chainmail）", helm_tpl != null and chest_tpl != null)
	if helm_tpl == null or chest_tpl == null:
		return
	_player.art_id = "warrior"
	var art_w := EnemyBase.resolve_character_set("warrior")
	_player._apply_real_art(art_w)
	_player._apply_facing()
	await _await_frames(2)

	var helm_inst := EquipmentInstance.create_from_template(helm_tpl, 1, GameConstants.Rarity.COMMON)
	var chest_inst := EquipmentInstance.create_from_template(chest_tpl, 1, GameConstants.Rarity.COMMON)
	_player.apply_equipment_visual([helm_inst, chest_inst])
	await _await_frames(2)
	var head_sp := head.get_node_or_null(NodePath("RealArmorPiece")) as Sprite2D
	var chest_sp := chest.get_node_or_null(NodePath("RealArmorPiece")) as Sprite2D
	_ok("挂载后 HeadAnchor/ChestAnchor 下生成 RealArmorPiece", head_sp != null and chest_sp != null)
	_ok("分件可见且纹理非空", head_sp != null and head_sp.visible and head_sp.texture != null
		and chest_sp != null and chest_sp.visible and chest_sp.texture != null)
	_ok("分件纹理过滤为 Nearest（像素铁律）",
		head_sp != null and head_sp.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	_ok("分件帧来自 armor 素材目录（helmet idle）",
		head_sp != null and head_sp.texture != null
		and head_sp.texture.resource_path.contains("armor_helm_hide_idle_"))
	_ok("胸甲分件帧来自 chest_chainmail 素材目录",
		chest_sp != null and chest_sp.texture != null
		and chest_sp.texture.resource_path.contains("armor_chest_chainmail_idle_"))

	# 换稀有度 → 部件走 tint 目录（与角色外观档同稀有度）
	var leg_inst := EquipmentInstance.create_from_template(chest_tpl, 1, GameConstants.Rarity.LEGENDARY)
	_player.apply_equipment_visual([helm_inst, leg_inst])
	await _await_frames(2)
	_ok("传说档胸甲分件切到 tint_legendary 目录",
		chest_sp != null and chest_sp.texture != null
		and chest_sp.texture.resource_path.contains("chest_chainmail_tint_legendary"))

	# 卸下 → 隐藏
	_player.apply_equipment_visual([])
	await _await_frames(1)
	_ok("卸下后分件隐藏", head_sp != null and not head_sp.visible and chest_sp != null and not chest_sp.visible)


# =============================================================================
# F. 重绑定
# =============================================================================

func _test_rebind() -> void:
	print("--- F. 输入重绑定 ---")
	var before := InputRemapper.get_action_events(&"dodge")
	var keys_before: int = _count_class(before, "key")
	var pads_before: int = _count_class(before, "pad")

	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	_ok("rebind 返回成功", InputRemapper.rebind(&"dodge", shift))
	var after := InputRemapper.get_action_events(&"dodge")
	_ok("改绑后 dodge 含 Shift", _has_physical_key(after, KEY_SHIFT))
	_ok("改绑后 dodge 不再含 Space", not _has_physical_key(after, KEY_SPACE))
	_ok("改绑**不影响**手柄绑定（同设备类别才替换）",
		_count_class(after, "pad") == pads_before)
	_info("键事件 %d → %d，手柄事件 %d → %d"
		% [keys_before, _count_class(after, "key"), pads_before, _count_class(after, "pad")])
	_ok("is_modified 正确识别已改动", InputRemapper.is_modified(&"dodge"))

	_ok("reset_to_default 返回成功", InputRemapper.reset_to_default(&"dodge"))
	var restored := InputRemapper.get_action_events(&"dodge")
	_ok("恢复默认后重新含 Space", _has_physical_key(restored, KEY_SPACE))
	_ok("恢复默认后 is_modified 为假", not InputRemapper.is_modified(&"dodge"))

	# 落盘 / 读盘往返
	InputRemapper.rebind(&"dodge", shift)
	_ok("save_bindings 落盘成功", InputRemapper.save_bindings())
	InputRemapper.reset_all_to_default()
	_ok("读盘前已恢复默认（Space 存在）", _has_physical_key(
		InputRemapper.get_action_events(&"dodge"), KEY_SPACE))
	_ok("load_bindings 读盘成功", InputRemapper.load_bindings())
	_ok("读盘后自定义绑定生效（Shift 回归）",
		_has_physical_key(InputRemapper.get_action_events(&"dodge"), KEY_SHIFT))

	InputRemapper.reset_all_to_default()


func _count_class(events: Array[InputEvent], cls: String) -> int:
	var n := 0
	for e in events:
		if cls == "key" and (e is InputEventKey or e is InputEventMouseButton):
			n += 1
		elif cls == "pad" and (e is InputEventJoypadButton or e is InputEventJoypadMotion):
			n += 1
	return n


func _has_physical_key(events: Array[InputEvent], code: int) -> bool:
	for e in events:
		if e is InputEventKey and int((e as InputEventKey).physical_keycode) == code:
			return true
	return false


# =============================================================================
# 收尾
# =============================================================================

## 备份玩家已有的按键设置，避免本脚本污染真实配置
func _backup_bindings() -> void:
	_bindings_existed = FileAccess.file_exists(InputRemapper.BINDINGS_PATH)
	if not _bindings_existed:
		return
	var f := FileAccess.open(InputRemapper.BINDINGS_PATH, FileAccess.READ)
	if f != null:
		_bindings_backup = f.get_as_text()
		f.close()


func _restore_bindings() -> void:
	if _bindings_existed:
		var f := FileAccess.open(InputRemapper.BINDINGS_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_bindings_backup)
			f.close()
	elif FileAccess.file_exists(InputRemapper.BINDINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(InputRemapper.BINDINGS_PATH))


func _finish() -> void:
	_restore_bindings()
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
