## 角色動畫狀態機 + 四方向 + 用戶可替換槽位實測（開發用，不屬於遊戲玩法）
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/verify_anim.tscn
##   退出碼 0 = 全部通過；1 = 有失敗項
##
## 為什麼需要它（2026-09-20 調研結論）：
##   接入多幀素材後，「動作」與「方向」若接錯都是**靜默失效**的 ——
##     · 每個實體只播一組動畫，attack / hurt / die 永遠不播；
##     · 多方向素材只載入 1 向，其餘是死資源；
##     · 檔名 who 與目錄名不符會把多個方向混成同一組循環。
##   這些事都不會報錯、不會讓任何既有 verify 變紅，只能靠本腳本盯死。
##
## 美術全部為豆包原創像素（`assets/pack/creatures/`）：16 怪 idle4/walk4/attack4/
## hurt3/die6 × 四方向（n/e/s/w）；玩家 walk/attack 八方向各 4、idle/hurt/death 朝南。
##
## 覆蓋範圍：
##   A. 檔名解析：who 可含底線（最後三段反推）
##   B. 怪物 pack：五動作 × 四方向各自成組，幀數正確（16 隻全測）
##   C. 玩家 pack：walk/attack 八方向各 4，idle/hurt/death 朝南
##   D. 方向選擇：向量 / 8 向枚舉 → 字母；換方向真的換到不同幀
##   E. 動作狀態機：idle / walk / attack / hurt / die 由真實玩法事件驅動
##   F. 死亡動畫：有 die 動作才放鬼影（本體移除時序不變）
##   G. 用戶覆蓋：user://content/characters/<id>/ 命中且優先於內建
##   H. 快取失效：clear_cache() 後改檔真的生效
##   I. 回退安全：未知 id → ok=false（呼叫方落占位）
##   J. 色板鐵律：本腳本生成的測試幀每個像素都在 PALETTE_ALL 內
extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")

## 用戶覆蓋測試用的假 creature id（不會與真實素材撞名）
const PROBE_ID: String = "zz_anim_probe"

var _fail: int = 0
var _player: PlayerController = null
var _probe_dir: String = ""


func _ok(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("%s %s" % ["[OK]  " if cond else "[FAIL]", label])


func _info(label: String) -> void:
	print("       %s" % label)


func _ready() -> void:
	# 失敗兜底看門狗：中途異常不得讓進程掛死（否則 CI 上是「卡滿超時」而非「失敗」）
	VerifyWatchdog.arm(get_tree())
	print("===== 角色動畫狀態機 + 四方向 + 用戶可替換 實測 =====")
	_player = get_node_or_null("/root/VerifyAnim/Player") as PlayerController
	_ok("場景就緒：玩家", _player != null)
	await _test_parse()
	await _test_four_dirs()
	await _test_player_pack()
	await _test_dir_selection()
	await _test_state_machine()
	await _test_death_ghost()
	await _test_user_override()
	await _test_cache_invalidation()
	await _test_fallback()
	_test_palette_law()
	_finish()


func _finish() -> void:
	_cleanup_probe()
	print("===== 结果：%d 项失败 =====" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
# A. 檔名解析
# =============================================================================

func _test_parse() -> void:
	print("--- A. 檔名解析（who 可含底線）---")
	var r := EnemyBase.dnf_parse_names([
		"char_boss_bone_tyrant_idle_w_07.png",
		"char_skeleton_warrior_walk_e_01.png",
		"char_player_idle_s_01.png",
		"not_a_char_file.png",
	])
	_ok("who 取「最後三段之前」全部 → boss_bone_tyrant",
		String(r["who"]) == "boss_bone_tyrant")
	var g: Dictionary = r["groups"]
	_ok("切成 2 個動作（idle / walk），非 char_ 前綴者被忽略",
		g.size() == 2 and g.has("idle") and g.has("walk"))
	_ok("action / dir / frame 三段切對（idle→w→7）",
		(g["idle"] as Dictionary).has("w")
		and ((g["idle"] as Dictionary)["w"] as Dictionary).has(7))
	_ok("同一 action 不同 dir 不會混在一起",
		(g["idle"] as Dictionary).has("w") and (g["idle"] as Dictionary).has("s"))


# =============================================================================
# B. 四方向載入
# =============================================================================

const MONSTER_IDS: Array[String] = [
	"spider_cave", "bat_swarm", "slime_acid", "skeleton_warrior", "mushroom_spore",
	"warg_dark", "imp_hellfire", "golem_ember", "brute_butcher", "frozen_husk",
	"pyromancer_cultist", "hound_ash", "wraith_frost", "ice_wraith",
	"boss_bone_tyrant", "boss_ember_lord"]

## 怪物 pack 統一契約：五動作幀數（idle4 / walk4 / attack4 / hurt3 / die6）。
const MONSTER_WANT_FRAMES: Dictionary = {
	"idle": 4, "walk": 4, "attack": 4, "hurt": 3, "die": 6,
}
const MONSTER_DIRS: Array[String] = ["n", "e", "s", "w"]


func _test_four_dirs() -> void:
	print("--- B. 豆包 pack 怪物：五動作 × 四方向（16 隻全測）---")
	var bad: Array[String] = []
	for who in MONSTER_IDS:
		var s := EnemyBase.pack_load_set(who)
		if not bool(s["ok"]):
			bad.append("%s(載入失敗)" % who)
			continue
		var clips: Dictionary = s["clips"]
		for action in MONSTER_WANT_FRAMES:
			if not clips.has(action):
				bad.append("%s.%s(缺動作)" % [who, action])
				continue
			var by_dir: Dictionary = clips[action]
			for d in MONSTER_DIRS:
				if not by_dir.has(d):
					bad.append("%s.%s.%s(缺方向)" % [who, action, d])
					continue
				var n: int = (by_dir[d] as Array).size()
				var want: int = int(MONSTER_WANT_FRAMES[action])
				if n != want:
					bad.append("%s.%s.%s(幀數 %d≠%d)" % [who, action, d, n, want])
	_ok("16 隻怪 pack 五動作 × 四方向幀數全對（idle4/walk4/attack4/hurt3/die6）",
		bad.is_empty())
	if not bad.is_empty():
		_info("異常：%s" % ", ".join(bad))


# =============================================================================
# C. 玩家 pack 八方向契約
# =============================================================================

const PLAYER_DIRS8: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]


func _test_player_pack() -> void:
	print("--- C. 玩家 pack（walk/attack 八方向各 4，idle/hurt/death 朝南）---")
	var s := EnemyBase.pack_load_set("player")
	_ok("玩家 pack 載入成功", bool(s["ok"]))
	var clips: Dictionary = s["clips"]
	var bad: Array[String] = []
	for action in ["walk", "attack"]:
		if not clips.has(action):
			bad.append("%s(缺動作)" % action)
			continue
		var by_dir: Dictionary = clips[action]
		for d in PLAYER_DIRS8:
			if not by_dir.has(d):
				bad.append("%s.%s(缺方向)" % [action, d])
			elif (by_dir[d] as Array).size() != 4:
				bad.append("%s.%s=%d幀" % [action, d, (by_dir[d] as Array).size()])
	_ok("walk/attack 八方向各 4 幀（共 64 幀）", bad.is_empty())
	if not bad.is_empty():
		_info(", ".join(bad))
	# 朝南單向動作：idle 1 / hurt 2 / death 4。⚠️ 玩家死亡動作名是 `death`（非怪物的 die）。
	_ok("idle_s 1 幀", (clips.get("idle", {}).get("s", []) as Array).size() == 1)
	_ok("hurt_s 2 幀", (clips.get("hurt", {}).get("s", []) as Array).size() == 2)
	_ok("death_s 4 幀（玩家死亡動作名 death）",
		(clips.get("death", {}).get("s", []) as Array).size() == 4)
	_ok("玩家無 die 動作（死亡統一用 death）", not clips.has(EnemyBase.ANIM_DIE))


# =============================================================================
# D. 方向選擇
# =============================================================================

func _test_dir_selection() -> void:
	print("--- D. 方向選擇 ---")
	_ok("向量 (0,+1) → s", EnemyBase.dir_from_vector(Vector2(0, 1)) == EnemyBase.DIR_S)
	_ok("向量 (0,-1) → n", EnemyBase.dir_from_vector(Vector2(0, -1)) == EnemyBase.DIR_N)
	_ok("向量 (+1,0) → e", EnemyBase.dir_from_vector(Vector2(1, 0)) == EnemyBase.DIR_E)
	_ok("向量 (-1,0) → w", EnemyBase.dir_from_vector(Vector2(-1, 0)) == EnemyBase.DIR_W)
	_ok("零向量回退 s", EnemyBase.dir_from_vector(Vector2.ZERO) == EnemyBase.DIR_S)
	_ok("斜向取主軸（(-0.9,+0.1) → w）",
		EnemyBase.dir_from_vector(Vector2(-0.9, 0.1)) == EnemyBase.DIR_W)

	var F := PlayerController.Facing8
	var pairs := [
		[F.DOWN, EnemyBase.DIR_S], [F.DOWN_LEFT, EnemyBase.DIR_S],
		[F.DOWN_RIGHT, EnemyBase.DIR_S], [F.LEFT, EnemyBase.DIR_W],
		[F.UP_LEFT, EnemyBase.DIR_W], [F.UP, EnemyBase.DIR_N],
		[F.RIGHT, EnemyBase.DIR_E], [F.UP_RIGHT, EnemyBase.DIR_E],
	]
	var bad: Array[String] = []
	for p in pairs:
		var got := PlayerController.facing_to_dir_letter(int(p[0]))
		if got != String(p[1]):
			bad.append("facing %d → %s(期望 %s)" % [int(p[0]), got, String(p[1])])
	_ok("8 向朝向 → 4 向字母全部正確", bad.is_empty())
	if not bad.is_empty():
		_info(", ".join(bad))

	# 換方向必須真的換到**不同的幀**（用豆包 pack 的 skeleton_warrior 四方向）
	var s := EnemyBase.pack_load_set("skeleton_warrior")
	var south := EnemyBase.resolve_clip(s["clips"], EnemyBase.ANIM_WALK, EnemyBase.DIR_S, [])
	var north := EnemyBase.resolve_clip(s["clips"], EnemyBase.ANIM_WALK, EnemyBase.DIR_N, [])
	_ok("s 向與 n 向取到不同紋理（方向真的生效，非只靠 flip_h）",
		(south["frames"] as Array)[0] != (north["frames"] as Array)[0])
	_ok("兩者都標記 exact=true", bool(south["exact"]) and bool(north["exact"]))


# =============================================================================
# E. 動作狀態機
# =============================================================================

func _spawn(monster_id: String) -> EnemyBase:
	var e := ENEMY_SCENE.instantiate() as EnemyBase
	e.monster_id = monster_id
	e.level = 1
	e.difficulty_tier = GameConstants.DifficultyTier.NM1
	add_child(e)
	e.global_position = Vector2(400, 400)
	return e


## 立即移除掛在測試節點下的死亡鬼影（鬼影掛在 parent 而非本體，queue_free 會跨幀殘留）。
func _clear_ghosts() -> void:
	for c in get_children():
		if c is Sprite2D and c.name == "DeathAnim":
			remove_child(c)
			c.free()


func _test_state_machine() -> void:
	print("--- E. 動作狀態機（pyromancer_cultist：狀態切換 + pack 多幀契約）---")
	var e := _spawn("pyromancer_cultist")
	await get_tree().process_frame
	_ok("真素材已載入（clips 非空）", not e._clips.is_empty())

	# 2026-09-22 多幀輪：16 隻怪在 `assets/pack/creatures/<id>/` 提供自有 idle/walk/attack/hurt/die
	# × 四方向多幀（resolver 第①·五級 pack，**優先於**第②級單張）。活體敵人現在拿到多幀集。
	# 第三方 DNF 多幀已於版權清理移除：解析鏈第③級現在是「空集回退」（見 I 段），不再有素材。
	var res := EnemyBase.resolve_character_set("pyromancer_cultist")
	_ok("第①·五級 pack 多幀命中（source=%s）" % res["source"], String(res["source"]) == "pack")
	var b_tex := EnemyBase.dnf_load_png_texture("res://assets/sprites/enemies/pyromancer_cultist.png")
	_ok("第②級 bundled 單張仍在（未刪除，僅被遮蔽）", b_tex != null)

	# 五動作 × 四方向齊全，幀數 idle4 / walk4 / attack4 / hurt3 / die6。
	var want_frames := {
		EnemyBase.ANIM_IDLE: 4, EnemyBase.ANIM_WALK: 4, EnemyBase.ANIM_ATTACK: 4,
		EnemyBase.ANIM_HURT: 3, EnemyBase.ANIM_DIE: 6,
	}
	var bad: Array[String] = []
	for a in want_frames:
		var by_dir: Dictionary = (res["clips"] as Dictionary).get(a, {})
		for d in [EnemyBase.DIR_S, EnemyBase.DIR_E, EnemyBase.DIR_W, EnemyBase.DIR_N]:
			if not by_dir.has(d):
				bad.append("%s.%s 缺方向" % [a, d])
			elif (by_dir[d] as Array).size() != int(want_frames[a]):
				bad.append("%s.%s=%d幀" % [a, d, (by_dir[d] as Array).size()])
	_ok("pack 五動作 × 四方向幀數正確（idle4/walk4/attack4/hurt3/die6）", bad.is_empty())
	if not bad.is_empty():
		_info("  ".join(bad))

	# idle：不動
	e.velocity = Vector2.ZERO
	e.facing = Vector2.DOWN
	e._tick_anim_state(0.0)
	e._refresh_clip()
	_ok("靜止 → IDLE 且動作 = idle、方向 = s",
		e._anim_state == EnemyBase.AnimState.IDLE and e._anim_action == EnemyBase.ANIM_IDLE
		and e._anim_dir == EnemyBase.DIR_S)
	_ok("idle 的 clip 為 pack 4 幀、exact=true（%d）" % e._clip.size(),
		e._clip.size() == 4 and e._clip_exact)

	# walk：移動中 + 朝右
	e.velocity = Vector2(60, 0)
	e.facing = Vector2.RIGHT
	e._tick_anim_state(0.0)
	e._refresh_clip()
	_ok("移動中 → WALK 且方向 = e",
		e._anim_state == EnemyBase.AnimState.WALK and e._anim_action == EnemyBase.ANIM_WALK
		and e._anim_dir == EnemyBase.DIR_E)
	_ok("walk 的 clip 為 pack 4 幀、exact=true（%d）" % e._clip.size(),
		e._clip.size() == 4 and e._clip_exact)

	# attack：真實攻擊路徑（_attack_player）
	e.velocity = Vector2.ZERO
	e._player = _player
	e._attack_player()
	e._tick_anim_state(0.0)
	e._refresh_clip()
	_ok("呼叫 _attack_player() → ATTACK 動作（pack 4 幀，%d）" % e._clip.size(),
		e._anim_state == EnemyBase.AnimState.ATTACK and e._clip.size() == 4 and e._clip_exact)

	# hurt：真實受擊路徑（take_damage 且真的掉血）
	e.current_hp = 100.0
	e.take_damage(10.0, _player)
	_ok("take_damage 真的掉血 → 觸發 hurt", e._anim_oneshot == EnemyBase.ANIM_HURT)
	e._tick_anim_state(0.0)
	_ok("受擊中 → HURT 動作",
		e._anim_state == EnemyBase.AnimState.HURT and e._anim_action == EnemyBase.ANIM_HURT)

	# 受擊期間攻擊不搶播
	e._play_anim_oneshot(EnemyBase.ANIM_ATTACK, 0.3)
	_ok("受擊期間攻擊不搶播（仍為 hurt）", e._anim_oneshot == EnemyBase.ANIM_HURT)

	# 受擊 / 攻擊不影響戰鬥計時
	_ok("動畫不碰 _attack_timer（仍為 attack_interval 量級）",
		e._attack_timer <= e.data.attack_interval + 0.001)

	# die：走**真實死亡路徑**（take_damage 打到 HP≤0 → HealthComponent._die）。
	e.current_hp = 5.0
	e.take_damage(100.0, _player)
	_ok("真實死亡（take_damage 致死）→ is_dead", e.is_dead)
	e._tick_anim_state(0.0)
	_ok("死亡 → DIE 狀態且請求 die 動作",
		e._anim_state == EnemyBase.AnimState.DIE and e._anim_action == EnemyBase.ANIM_DIE)
	var r := EnemyBase.resolve_clip(e._clips, EnemyBase.ANIM_DIE, EnemyBase.DIR_S, e._real_frames)
	_ok("pack 有 die 動作 → exact=true（%d 幀）" % (r["frames"] as Array).size(),
		bool(r["exact"]) and (r["frames"] as Array).size() == 6)
	await get_tree().process_frame
	_clear_ghosts()
	e.queue_free()
	await get_tree().process_frame


# =============================================================================
# F. 死亡動畫（鬼影）
# =============================================================================

func _test_death_ghost() -> void:
	print("--- F. 死亡動畫（鬼影）---")
	_clear_ghosts()
	var e := _spawn("spider_cave")
	await get_tree().process_frame
	e.facing = Vector2.DOWN

	# 用「移除 die 的 clips 副本」驗證守衛：無 die 動作 → 不放鬼影（行為與接入前一致）。
	# 不直接依賴素材本身有無 die（pack 多幀輪後蜘蛛自帶 die），讓測試與素材解耦。
	var saved := e._clips
	var no_die := e._clips.duplicate(true)
	no_die.erase(EnemyBase.ANIM_DIE)
	e._clips = no_die
	e._spawn_death_anim()
	_ok("無 die 動作 → 不生成死亡鬼影", e.get_parent().get_node_or_null("DeathAnim") == null)

	# 恢復真實 clips（自帶 die 6 幀）→ 應生成鬼影（脫離本體，本體移除時序不變）。
	e._clips = saved
	e._spawn_death_anim()
	var ghost := e.get_parent().get_node_or_null("DeathAnim")
	_ok("有 die 動作 → 生成死亡鬼影（脫離本體，本體移除時序不變）", ghost != null)
	if ghost != null:
		_ok("鬼影沿用本體的縮放 / 位移 / 最近鄰",
			(ghost as Sprite2D).scale.is_equal_approx(e._body.scale)
			and (ghost as Sprite2D).texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
		_ok("鬼影世界位置對齊本體 Body",
			(ghost as Sprite2D).global_position.is_equal_approx(e.global_position + e._body.position))
		(ghost as Sprite2D).queue_free()
	e.queue_free()
	await get_tree().process_frame
	_clear_ghosts()


# =============================================================================
# G. 用戶覆蓋
# =============================================================================

func _test_user_override() -> void:
	print("--- G. 用戶覆蓋 user://content/characters/<id>/ ---")
	_cleanup_probe()
	_probe_dir = ContentPaths.user_path(ContentPaths.CLASS_CHARACTERS, PROBE_ID)
	DirAccess.make_dir_recursive_absolute(_probe_dir)
	var err_s := _write_png("%s/char_%s_idle_s_01.png" % [_probe_dir, PROBE_ID], 6, 6,
		GameConstants.PALETTE_NEUTRAL[2])
	var err_s2 := _write_png("%s/char_%s_idle_s_02.png" % [_probe_dir, PROBE_ID], 6, 6,
		GameConstants.PALETTE_NEUTRAL[3])
	var err_n := _write_png("%s/char_%s_idle_n_01.png" % [_probe_dir, PROBE_ID], 6, 6,
		GameConstants.PALETTE_ACCENT[8])
	_ok("測試幀寫入 user:// 成功", err_s == OK and err_s2 == OK and err_n == OK)

	EnemyBase.clear_cache()
	var s := EnemyBase.resolve_character_set(PROBE_ID)
	_ok("resolve_character_set 命中用戶覆蓋", bool(s["ok"]) and String(s["source"]) == "user")
	var clips: Dictionary = s["clips"]
	_ok("用戶素材切成 idle 一個動作、兩個方向",
		clips.size() == 1 and (clips["idle"] as Dictionary).size() == 2)
	_ok("用戶素材 s 向 2 幀 / n 向 1 幀",
		((clips["idle"] as Dictionary)["s"] as Array).size() == 2
		and ((clips["idle"] as Dictionary)["n"] as Array).size() == 1)
	_ok("用戶素材的 canvas 由紋理實測兜底（6）", is_equal_approx(float(s["canvas"]), 6.0))

	# 用戶素材永遠不會被 Godot import ⇒ 走 Image.load_from_file 分支
	var t: Texture2D = ((clips["idle"] as Dictionary)["s"] as Array)[0]
	_ok("未 import 的 user:// PNG 仍能解成 Texture2D",
		t != null and t.get_width() == 6 and t.get_height() == 6)

	# 畫布一律由紋理實測（第三方 manifest 已隨版權清理移除，dnf_load_dir 不再有
	# use_manifest 參數）：這個 6×6 目錄解析出的 canvas 必須等於紋理高 6，不得借用
	# 任何內建畫布值（舊版 manifest 的 192 曾把用戶 256 畫布蓋掉 → 縮放算錯）。
	var local := EnemyBase.dnf_load_dir("player", _probe_dir)
	_ok("dnf_load_dir 畫布由紋理實測（6，實測 %d）" % int(local["canvas"]),
		int(local["canvas"]) == 6)


func _test_cache_invalidation() -> void:
	print("--- H. 快取失效 clear_cache() ---")
	# 追加一幀後，未清快取 → 舊結果（2 幀）；清快取 → 新結果（3 幀）
	_write_png("%s/char_%s_idle_s_03.png" % [_probe_dir, PROBE_ID], 6, 6,
		GameConstants.PALETTE_NEUTRAL[4])
	var stale := EnemyBase.resolve_character_set(PROBE_ID)
	var stale_n: int = ((stale["clips"] as Dictionary)["idle"] as Dictionary)["s"].size()
	_ok("未清快取 → 仍是舊的 2 幀（快取生效中）", stale_n == 2)
	EnemyBase.clear_cache()
	var fresh := EnemyBase.resolve_character_set(PROBE_ID)
	var fresh_n: int = ((fresh["clips"] as Dictionary)["idle"] as Dictionary)["s"].size()
	_ok("clear_cache() 後 → 新的 3 幀（改了檔案真的生效）", fresh_n == 3)


# =============================================================================
# I. 回退安全
# =============================================================================

func _test_fallback() -> void:
	print("--- I. 回退安全 ---")
	var s := EnemyBase.resolve_character_set("__no_such_creature__")
	_ok("未知 id → ok=false（呼叫方落占位色塊，不拋錯）", not bool(s["ok"]))
	_ok("未知 id → frames 為空", (s["frames"] as Array).is_empty())
	_ok("未知 id → clips 為空", (s["clips"] as Dictionary).is_empty())
	var u := EnemyBase.dnf_load_user_dir("__no_such_creature__")
	_ok("未覆蓋的 id → user 級不命中且不報錯", not bool(u["ok"]))


# =============================================================================
# J. 色板鐵律
# =============================================================================

func _test_palette_law() -> void:
	print("--- J. 色板鐵律（本腳本生成的幀）---")
	var img := _make_image(6, 6, GameConstants.PALETTE_ACCENT[8])
	var off := 0
	for y in img.get_height():
		for x in img.get_width():
			if not GameConstants.palette_contains(img.get_pixel(x, y)):
				off += 1
	_ok("生成的測試幀離板像素數 = 0（實測 %d）" % off, off == 0)
	_ok("PALETTE_ALL 為 44 色（實測 %d）" % GameConstants.PALETTE_ALL.size(),
		GameConstants.PALETTE_ALL.size() == 44)


# =============================================================================
# 工具
# =============================================================================

func _make_image(w: int, h: int, color: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img


func _make_texture(w: int, h: int, color: Color) -> ImageTexture:
	return ImageTexture.create_from_image(_make_image(w, h, color))


func _write_png(path: String, w: int, h: int, color: Color) -> int:
	return _make_image(w, h, color).save_png(path)


func _cleanup_probe() -> void:
	if _probe_dir.is_empty():
		return
	var d := DirAccess.open(_probe_dir)
	if d == null:
		return
	d.list_dir_begin()
	var cur := d.get_next()
	var files: Array[String] = []
	while cur != "":
		if not d.current_is_dir():
			files.append(cur)
		cur = d.get_next()
	d.list_dir_end()
	for fn in files:
		DirAccess.remove_absolute("%s/%s" % [_probe_dir, fn])
	DirAccess.remove_absolute(_probe_dir)
	# 一併清掉空的 characters 目錄（只在它確實為空時）
	var parent := ContentPaths.user_path(ContentPaths.CLASS_CHARACTERS, "").trim_suffix("/")
	var pd := DirAccess.open(parent)
	if pd != null:
		pd.list_dir_begin()
		var any := false
		var e := pd.get_next()
		while e != "":
			if not e.begins_with("."):
				any = true
			e = pd.get_next()
		pd.list_dir_end()
		if not any:
			DirAccess.remove_absolute(parent)
	EnemyBase.clear_cache()
