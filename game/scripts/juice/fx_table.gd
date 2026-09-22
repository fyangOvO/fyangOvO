## 特效表（class_name FxTable extends RefCounted）· 数据驱动特效层
##
## 解决什么问题（2026-09-20 调研结论）
## ----------------------------------
## 项目此前的特效**全部是代码绘制**（`pixel_burst.gd` 的 `_draw()`、`loot_drop.gd` 的
## 色块、`screen_shake.gd` 的相机偏移……），`.tscn` 里连一个 `Texture2D` 外部资源都没有。
## 于是用户**没有任何接口**把自己的特效贴图换进来 —— 与「我可以自己換特效」的诉求正相反。
##
## 本类提供那个缺失的接口：
##   1. 读 `data/fx.json`（**用户可覆盖**，见下）拿到「特效 id → 序列帧 spec」；
##   2. 贴图按三级优先解析（`ContentPaths`）：`user://content/fx/` → `res://assets/fx/`；
##   3. `spawn(id, pos)` 生成一个 `FxSprite`；未知 id 只警告 + 返回 null，**不崩**。
##
## 用户怎么替换（不改代码）
## ------------------------
##   · 换贴图：覆盖 `game/assets/fx/<id>.png`，或放一份到
##     `%APPDATA%\Godot\app_userdata\七傳說\content\fx\<id>.png`（优先，且不被游戏更新覆盖）；
##   · 加特效：往 `content/fx/fx.json` 写一份带新 id 的表即可整表覆盖内置表。
##
## 缓存与失效（踩过的坑）
## ----------------------
## 本项目已被「静态缓存无法失效」咬过（`tile_atlas.gd:41` 的 `_cache` 换图后不重建）。
## 所以这里显式提供 `clear_cache()`，并且**贴图与表分开缓存**：换图后可只清贴图。
class_name FxTable
extends RefCounted

## 内置表路径（用户可用 `user://content/fx/fx.json` 整表覆盖）
const TABLE_BUNDLED := "res://data/fx.json"
const TABLE_RELATIVE := "fx.json"

## 内置贴图目录（`ContentPaths.resolve_with_user` 的 bundled 侧）
const TEX_BUNDLED_DIR := "res://assets/fx"

const DEFAULT_ANCHOR := "center"
const DEFAULT_Z := "above_actors"

## z 语义 → z_index。`pixel_burst.gd` 用 5、`damage_number.gd` 用 10，
## 特效压在敌人之上但低于飘字，所以取 6。
const Z_ABOVE_ACTORS := 6
const Z_BELOW_ACTORS := -1

## 静态缓存：整表解析结果（所有 FxTable 实例共享）
static var _effects: Dictionary = {}
static var _table_loaded: bool = false
## 静态缓存：解析后的贴图路径 → Texture2D
static var _tex_cache: Dictionary = {}
## 已警告过的 id（避免同一个坏 id 每帧刷屏）
static var _warned: Dictionary = {}


## 清空全部静态缓存。换贴图 / 改 fx.json 后调用可强制重建。
static func clear_cache() -> void:
	_effects.clear()
	_table_loaded = false
	_tex_cache.clear()
	_warned.clear()


## 只清贴图缓存（表结构不变时够用）
static func clear_texture_cache() -> void:
	_tex_cache.clear()


# =============================================================================
# 表加载
# =============================================================================

static func _ensure_table() -> void:
	if _table_loaded:
		return
	_table_loaded = true
	_effects.clear()

	var path := ContentPaths.resolve_with_user(
		ContentPaths.CLASS_FX, TABLE_RELATIVE, TABLE_BUNDLED)
	if path.is_empty():
		push_warning("FxTable: 找不到特效表（%s），全部特效退回调用方的代码绘制路径" % TABLE_BUNDLED)
		return

	var parsed: Variant = _read_json(path)
	if not parsed is Dictionary:
		push_warning("FxTable: 特效表 '%s' 不是 JSON 对象，已忽略" % path)
		return
	var doc: Dictionary = parsed
	var raw: Variant = doc.get("effects", {})
	if not raw is Dictionary:
		push_warning("FxTable: 特效表 '%s' 缺少 effects 对象，已忽略" % path)
		return
	_effects = raw
	print("[FxTable] 特效表已加载：%d 条（%s）" % [_effects.size(), path])


static func _read_json(path: String) -> Variant:
	# 与 `config_loader.gd:815-840` 同口径：先试已导入的 JSON 资源，再退回裸文本。
	# 用户放在 `user://` 的表**不会被导入**，所以文本回退是必需路径，不是兜底。
	if ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path)
		if res is JSON:
			return (res as JSON).data
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("FxTable: 无法打开 '%s'（错误码 %d）" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("FxTable: '%s' 第 %d 行 JSON 解析失败：%s"
			% [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


# =============================================================================
# 贴图解析
# =============================================================================

## 某特效的 spec（无则空字典）
static func spec(id: String) -> Dictionary:
	_ensure_table()
	var s: Variant = _effects.get(id, {})
	return s if s is Dictionary else {}


## 该特效是否**真的有贴图可用**。
## 调用方用它决定「走贴图分支」还是「退回代码绘制分支」——
## 这是「没有贴图时游戏手感不变」的关键判据。
static func has_texture(id: String) -> bool:
	return texture_for(id) != null


static func texture_for(id: String) -> Texture2D:
	var s := spec(id)
	if s.is_empty():
		_warn_once(id, "特效表里没有 id '%s'" % id)
		return null
	var rel := str(s.get("texture", ""))
	if rel.is_empty():
		_warn_once(id, "特效 '%s' 的 texture 字段为空" % id)
		return null
	if _tex_cache.has(rel):
		var cached: Variant = _tex_cache[rel]
		return cached as Texture2D

	# 三级优先：user://content/fx/<rel> → res://assets/fx/<rel>
	var path := ContentPaths.resolve_with_user(
		ContentPaths.CLASS_FX, rel, "%s/%s" % [TEX_BUNDLED_DIR, rel])
	if path.is_empty():
		_warn_once(id, "特效 '%s' 的贴图不存在（%s 与 %s/%s 都没有）"
			% [id, ContentPaths.user_path(ContentPaths.CLASS_FX, rel), TEX_BUNDLED_DIR, rel])
		_tex_cache[rel] = null
		return null

	var tex := _load_texture(path)
	_tex_cache[rel] = tex
	return tex


## 载入贴图。先走资源系统（已导入），再退回裸 PNG 解码 ——
## 用户刚丢进 `user://content/fx/` 的 PNG 不经导入，必须走后者。
## 与 `tile_atlas.gd:166-175` 同一策略。
static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path)
		if res is Texture2D:
			return res as Texture2D
	var img := Image.new()
	if img.load(path) != OK:
		push_warning("FxTable: 贴图解码失败 '%s'" % path)
		return null
	return ImageTexture.create_from_image(img)


static func _warn_once(id: String, msg: String) -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	push_warning("FxTable: " + msg)


# =============================================================================
# 生成
# =============================================================================

## 生成一个特效实例并挂到场景里。返回 `FxSprite`（调用方可再改属性），
## 失败（未知 id / 无贴图 / 无宿主）返回 `null` —— 由调用方决定要不要走代码绘制兜底。
##
## `opts` 可选键：
##   `host: Node`  —— 挂载父节点（默认取当前场景根）
##   `flip_h: bool`、`rotation: float`、`scale: Vector2` —— 朝向 / 旋转 / 缩放
static func spawn(id: String, global_pos: Vector2, opts: Dictionary = {}) -> Node2D:
	var tex := texture_for(id)
	if tex == null:
		return null

	var host: Node = opts.get("host", null)
	if host == null or not is_instance_valid(host):
		var loop := Engine.get_main_loop()
		host = (loop as SceneTree).current_scene if loop is SceneTree else null
	if host == null or not is_instance_valid(host):
		_warn_once(id, "生成特效 '%s' 时没有可用的宿主节点" % id)
		return null

	var s := spec(id)
	var fx := FxSprite.new()
	fx.z_index = Z_BELOW_ACTORS if str(s.get("z", DEFAULT_Z)) == "below_actors" \
		else Z_ABOVE_ACTORS
	if not fx.setup(s, tex):
		# 尚未入树 ⇒ 用 free() 而不是 queue_free()（后者要求节点在树内）
		fx.free()
		return null
	host.add_child(fx)
	fx.global_position = global_pos
	if opts.has("flip_h"):
		fx.scale.x = -1.0 if bool(opts["flip_h"]) else 1.0
	if opts.has("rotation"):
		fx.rotation = float(opts["rotation"])
	if opts.has("scale"):
		var sv: Variant = opts["scale"]
		if sv is Vector2:
			fx.scale = sv
	return fx


# =============================================================================
# 查询（自检 / 工具用）
# =============================================================================

## 表里全部特效 id（升序）
static func all_ids() -> Array[String]:
	_ensure_table()
	var out: Array[String] = []
	for k in _effects.keys():
		out.append(str(k))
	out.sort()
	return out


## 表是否成功加载（自检用）
static func is_loaded() -> bool:
	_ensure_table()
	return not _effects.is_empty()


## 用户覆盖用的贴图绝对路径（UI「打开内容目录」提示用）
static func user_texture_path(rel: String) -> String:
	return ProjectSettings.globalize_path(
		ContentPaths.user_path(ContentPaths.CLASS_FX, rel))
