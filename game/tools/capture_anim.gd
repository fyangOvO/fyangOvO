## 角色動畫真渲染抓圖（開發用，不屬於遊戲玩法）
##
## 用法（**必須去掉 `--headless`** —— 無頭模式下沒有渲染，抓不到畫面）：
##   godot --path "D:/七傳說/game" res://tools/capture_anim.tscn
##
## 為什麼需要它：
##   `verify_anim` 能證明「狀態機切對了 clip」，但**證明不了畫面上真的在動** ——
##   貼圖換了卻沒重繪、縮放算錯、方向取到同一幀，這些都只有真渲染看得見。
##
## 做法：把「用戶自帶素材」真的寫進 `user://content/characters/`，
##   讓**生產代碼路徑**（`EnemyBase.resolve_character_set` → `dnf_load_user_dir`）去載，
##   再逐格抓圖。生成的測試幀**每個像素都在 PALETTE_ALL 內**（色板鐵律）。
##   跑完自動清掉用戶目錄（不會污染真實用戶內容）。
##
## 產出（`deliverables/gstack/`）：
##   `screenshot-anim-matrix.png`       5 動作 × 4 方向 = 20 格全渲染
##   `screenshot-anim-live-walk-01/02.png`  真實移動 → WALK，連兩幀證明真的在動
##   `screenshot-anim-live-attack.png`  真實 `_attack_player()` → ATTACK
##   `screenshot-anim-live-hurt.png`    真實 `take_damage()` → HURT
##   `screenshot-anim-live-die.png`     真實死亡 → DIE 鬼影
##   `screenshot-anim-player.png`       玩家（走 user 覆蓋）
extends Node2D

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

const OUT_DIR: String = "D:/七傳說/deliverables/gstack"
## 測試用的覆蓋對象：用真實 monster_id，才會走完整生產鏈
const ENEMY_ID: String = "spider_cave"
const PLAYER_ID: String = "player"

## 每個動作一個色板色（肉眼可分辨「現在播的是哪個動作」）
const ACTION_COLORS: Dictionary = {
	"idle": 2,    ## PALETTE_ACCENT[2]  紅
	"walk": 6,    ## 綠
	"attack": 10, ## 藍
	"hurt": 14,   ## 金
	"die": 18,    ## 紫
}
const ACTION_ORDER: Array[String] = ["idle", "walk", "attack", "hurt", "die"]
const DIR_ORDER: Array[String] = ["s", "n", "e", "w"]
## 每組動作的幀數（生成素材用；不必等於真實素材的幀數）
const FRAMES_PER_CLIP: int = 6
## 畫布：256 × 0.25 = 螢幕 64px（夠大看得出格內細節）
const CANVAS: int = 256

var _fail: int = 0
var _arena: Node2D = null
var _camera: Camera2D = null
var _wrote_dirs: Array[String] = []


func _ready() -> void:
	VerifyWatchdog.arm(get_tree(), 180.0)
	_run()


func _run() -> void:
	print("===== 角色動畫真渲染抓圖 =====")
	_ok("渲染驅動不是 headless（否則抓不到畫面）",
		DisplayServer.get_name() != "headless")
	_arena = Node2D.new()
	_arena.name = "Arena"
	add_child(_arena)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.6, 1.6)
	_arena.add_child(_camera)
	_camera.make_current()

	_ok("用戶素材已寫入 user://content/characters/", _write_user_content())

	await _capture_matrix()
	await _capture_live()
	await _capture_player()

	_cleanup_user_content()
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# 生成「用戶自帶素材」（色板合規）
# =============================================================================

## 一幀的畫法：動作底色 + 方向標記（白，貼在對應邊）+ 幀號進度條（近黑，底部）
## 這樣一張圖同時可讀出「動作 / 方向 / 第幾幀」三個維度。
func _make_frame(action: String, d: String, frame: int) -> Image:
	var img := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	img.fill(GameConstants.PALETTE_ACCENT[int(ACTION_COLORS[action])])
	var ink: Color = GameConstants.PALETTE_NEUTRAL[0]      ## 近黑
	var mark: Color = GameConstants.PALETTE_NEUTRAL[9]     ## 亮白
	# 方向標記：貼在對應邊的一條粗帶（n 上 / e 右 / s 下 / w 左）
	var band := 22
	var span := 96
	match d:
		"n":
			_fill_rect(img, CANVAS / 2 - span / 2, 8, span, band, mark)
		"e":
			_fill_rect(img, CANVAS - band - 8, CANVAS / 2 - span / 2, band, span, mark)
		"w":
			_fill_rect(img, 8, CANVAS / 2 - span / 2, band, span, mark)
		_:
			_fill_rect(img, CANVAS / 2 - span / 2, CANVAS - band - 8, span, band, mark)
	# 幀號進度條：底部 (frame+1) 段黑格
	var cell := 26
	var x0 := 16
	for i in range(frame + 1):
		_fill_rect(img, x0 + i * (cell + 6), CANVAS - 70, cell, 26, ink)
	return img


func _fill_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, mini(y + h, img.get_height())):
		for xx in range(x, mini(x + w, img.get_width())):
			if xx >= 0 and yy >= 0:
				img.set_pixel(xx, yy, c)


## 把 5 動作 × 4 方向 × FRAMES_PER_CLIP 幀寫進 user://content/characters/<id>/
func _write_user_content() -> bool:
	var all_ok := true
	for id in [ENEMY_ID, PLAYER_ID]:
		var dir := ContentPaths.user_path(ContentPaths.CLASS_CHARACTERS, id)
		if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
			all_ok = false
			continue
		_wrote_dirs.append(dir)
		for action in ACTION_ORDER:
			for d in DIR_ORDER:
				for i in FRAMES_PER_CLIP:
					var fname := "char_%s_%s_%s_%02d.png" % [id, action, d, i + 1]
					if _make_frame(action, d, i).save_png("%s/%s" % [dir, fname]) != OK:
						all_ok = false
	return all_ok


func _cleanup_user_content() -> void:
	for dir in _wrote_dirs:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var cur := d.get_next()
		var files: Array[String] = []
		while cur != "":
			if not d.current_is_dir():
				files.append(cur)
			cur = d.get_next()
		d.list_dir_end()
		for fn in files:
			DirAccess.remove_absolute("%s/%s" % [dir, fn])
		DirAccess.remove_absolute(dir)
	_wrote_dirs.clear()


# =============================================================================
# ① 動作 × 方向 全矩陣
# =============================================================================

func _capture_matrix() -> void:
	print("--- ① 動作 × 方向 全矩陣 ---")
	var spawned: Array[Node] = []
	var total := 0
	for r in ACTION_ORDER.size():
		for c in DIR_ORDER.size():
			var e := ENEMY_SCENE.instantiate() as EnemyBase
			e.monster_id = ENEMY_ID
			e.level = 1
			_arena.add_child(e)
			# 列間距 140、起始 -260：5 列剛好落在 zoom 1.6 的可視範圍內（±337）
			e.global_position = Vector2(-330 + c * 220, -260 + r * 140)
			await get_tree().process_frame
			_force_clip(e, ACTION_ORDER[r], DIR_ORDER[c], 2)
			spawned.append(e)
			total += 1
	_ok("矩陣生成 %d 隻（5 動作 × 4 方向）" % total, total == 20)
	# 抽一格做數值自證：idle/s 的第 3 幀（frame index 2）必須是**該組第 3 張**紋理
	var probe := _find_enemy(Vector2(-330, -260))
	if probe != null:
		_ok("idle/s 的 clip 幀數 = %d" % FRAMES_PER_CLIP, probe._clip.size() == FRAMES_PER_CLIP)
		_ok("矩陣格真的取到第 3 幀（_anim_i = 2）", probe._anim_i == 2)
	_camera.global_position = Vector2(0, 0)
	await _frames(6)
	await _shot("screenshot-anim-matrix.png")
	# 收掉矩陣，避免與「真實事件」那組重疊（重疊會讓截圖無法判讀）
	for n in spawned:
		n.queue_free()
	await _frames(3)


# =============================================================================
# ② 真實事件驅動（walk / attack / hurt / die）
# =============================================================================

func _capture_live() -> void:
	print("--- ② 真實事件驅動 ---")
	var live := ENEMY_SCENE.instantiate() as EnemyBase
	live.monster_id = ENEMY_ID
	live.level = 1
	_arena.add_child(live)
	live.global_position = Vector2(0, 0)
	await get_tree().process_frame
	_camera.global_position = Vector2(0, 0)
	await _frames(4)

	# WALK：關掉 AI（否則蜘蛛自己追擊會覆寫 velocity），只留動畫狀態機
	# （動畫狀態機在 `_process`，AI 在 `_physics_process` —— 只關後者）
	live.set_physics_process(false)
	live.velocity = Vector2(60, 0)
	live.facing = Vector2.RIGHT
	await _frames(3)
	_ok("velocity 非零 → 狀態機推導出 WALK/e",
		live._anim_state == EnemyBase.AnimState.WALK and live._anim_dir == EnemyBase.DIR_E)
	var f0: Texture2D = live._body.texture
	await _shot("screenshot-anim-live-walk-01.png")
	await _frames(8)
	var f1: Texture2D = live._body.texture
	await _shot("screenshot-anim-live-walk-02.png")
	_ok("連兩幀抓到的貼圖**不同** ⇒ 逐幀動畫真的在跑（非靜止圖）", f0 != null and f1 != null and f0 != f1)
	_ok("本體貼圖 ∈ walk 幀集（%d 幀）" % live._clip.size(),
		not live._clip.is_empty() and live._clip.has(live._body.texture))

	# ATTACK：真實攻擊入口
	live.velocity = Vector2.ZERO
	live.facing = Vector2.DOWN
	var dummy := PLAYER_SCENE.instantiate() as PlayerController
	_arena.add_child(dummy)
	dummy.global_position = Vector2(0, 30)
	await get_tree().process_frame
	live._player = dummy
	live._attack_player()
	await _frames(2)
	_ok("真實 _attack_player() → ATTACK/s",
		live._anim_state == EnemyBase.AnimState.ATTACK and live._anim_dir == EnemyBase.DIR_S)
	# 數值自證「畫面上那張圖就是 attack 組的幀」——只斷言狀態變數不足以證明真的換圖
	_ok("本體貼圖 ∈ attack 幀集（%d 幀）" % live._clip.size(),
		not live._clip.is_empty() and live._clip.has(live._body.texture))
	await _shot("screenshot-anim-live-attack.png")

	# HURT：真實受擊入口
	live._player = dummy
	live.current_hp = 100.0
	live.take_damage(10.0, dummy)
	await _frames(2)
	_ok("真實 take_damage() → HURT", live._anim_state == EnemyBase.AnimState.HURT)
	_ok("本體貼圖 ∈ hurt 幀集（%d 幀）" % live._clip.size(),
		not live._clip.is_empty() and live._clip.has(live._body.texture))
	await _shot("screenshot-anim-live-hurt.png")

	# DIE：真實死亡 → 鬼影（本體當幀移除）
	# 先取「die 動作應有的幀集」當對照，本體一 free 就拿不到了
	var die_frames: Array = EnemyBase.resolve_clip(
		live._clips, EnemyBase.ANIM_DIE, EnemyBase.DIR_S, live._real_frames)["frames"]
	_ok("素材含 die/s 動作（%d 幀）" % die_frames.size(), die_frames.size() > 1)
	live.current_hp = 5.0
	live.take_damage(100.0, dummy)
	await _frames(3)
	var ghost := _arena.get_node_or_null("DeathAnim")
	_ok("真實死亡 → 死亡鬼影已生成並在播 die 幀", ghost != null)
	if ghost != null:
		_ok("鬼影貼圖 ∈ die 幀集（非 idle 冒充）",
			die_frames.has((ghost as Sprite2D).texture))
	await _shot("screenshot-anim-live-die.png")
	# 鬼影靠 tween 播完自毀（約 0.5s），不主動收掉會飄進下一組截圖（實測污染過玩家那張）
	if ghost != null:
		ghost.queue_free()
	dummy.queue_free()
	await _frames(3)


# =============================================================================
# ③ 玩家（user 覆蓋）
# =============================================================================

func _capture_player() -> void:
	print("--- ③ 玩家 ---")
	var p := PLAYER_SCENE.instantiate() as PlayerController
	_arena.add_child(p)
	p.global_position = Vector2(0, 0)
	await get_tree().process_frame
	_ok("玩家載入 user 覆蓋素材（clips 非空）", not p._clips.is_empty())
	_ok("玩家縮放由 CHARACTER_SPRITE_SIZE 反推 = %d / 畫布 %d"
			% [GameConstants.CHARACTER_SPRITE_SIZE, CANVAS],
		p.body_sprite != null and is_equal_approx(p.body_sprite.scale.x,
			float(GameConstants.CHARACTER_SPRITE_SIZE) / float(CANVAS)))
	# 與敵人同一招：關掉 `_physics_process`（那裡每幀從輸入重算 velocity，
	# 無輸入時以 1600px/s² 衰減 → 注入的 60px/s 兩三幀內歸零 → 抓成 IDLE）。
	# 動畫狀態機在 `_process`，只關物理不影響待測行為。
	p.set_physics_process(false)
	p.velocity = Vector2(0, 60)
	p.set_facing(PlayerController.Facing8.DOWN)
	await _frames(4)
	_ok("玩家移動 → WALK 狀態且方向 = s",
		p._anim_state == EnemyBase.AnimState.WALK and p._anim_dir == EnemyBase.DIR_S)
	await _shot("screenshot-anim-player.png")


# =============================================================================
# 工具
# =============================================================================

## 凍結狀態機與 AI 並強制顯示某動作 / 方向 / 幀（矩陣用）。
## `_physics_process` 也要關：否則蜘蛛會自己追擊，把矩陣格挪出畫面。
func _force_clip(e: EnemyBase, action: String, d: String, frame: int) -> void:
	e.set_process(false)
	e.set_physics_process(false)
	e._anim_action = action
	e._anim_dir = d
	e._clip_key = ""
	e._refresh_clip()
	if e._clip.is_empty():
		return
	e._anim_i = clampi(frame, 0, e._clip.size() - 1)
	e._body.texture = e._clip[e._anim_i]


func _find_enemy(pos: Vector2) -> EnemyBase:
	for c in _arena.get_children():
		if c is EnemyBase and (c as EnemyBase).global_position.is_equal_approx(pos):
			return c
	return null


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, fname]
	var err := img.save_png(path)
	_ok("抓圖 %s → %d×%d（err=%d）" % [fname, img.get_width(), img.get_height(), err],
		err == OK and img.get_width() > 0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])
