## 内容加载器（统一用户覆盖入口）
##
## 给玩家留的"自己换素材"口子：所有美术/音乐资源都走这里，
## 用户把文件丢进 user://content/<类别>/ 即可覆盖内置，不用碰代码、不用重新打包。
##
## 三级优先（与 ContentPaths 一致）：
##   ① user://content/<类别>/<相对路径>   玩家覆盖（最高）
##   ② 内置 res://assets/...             随包
##   ③ 程序化占位                         永不黑屏
##
## 用法：
##   var tex := ContentLoader.load_icon("res://assets/.../sword.png")
##   var bgm := ContentLoader.load_bgm("res://assets/audio/forest_bgm.ogg")
class_name ContentLoader
extends RefCounted

static var _icon_cache: Dictionary = {}
static var _bgm_cache: Dictionary = {}


## 加载装备/物品图标贴图。
## `bundled` 为内置路径（通常来自 EquipmentData.icon_path）；
## 用户覆盖：把同名文件放到 `user://content/icons/<basename>`。
## 找不到返回 null（调用方用色块占位）。
static func load_icon(bundled: String) -> Texture2D:
	if bundled.is_empty():
		return null
	if _icon_cache.has(bundled):
		return _icon_cache[bundled]
	var base := bundled.get_file()  # 取文件名（含扩展名）
	var user_path := ContentPaths.user_path(ContentPaths.CLASS_ICONS, base)
	var p := ContentPaths.resolve([user_path, bundled])
	var tex := _load_any(p) if not p.is_empty() else null
	_icon_cache[bundled] = tex
	return tex


## 加载 BGM 音频流。
## `bundled` 为内置路径；用户覆盖：`user://content/music/<basename>`。
static func load_bgm(bundled: String) -> AudioStream:
	if bundled.is_empty():
		return null
	if _bgm_cache.has(bundled):
		return _bgm_cache[bundled]
	var base := bundled.get_file()
	var user_path := ContentPaths.user_path(ContentPaths.CLASS_MUSIC, base)
	var p := ContentPaths.resolve([user_path, bundled])
	var s: AudioStream = null
	if not p.is_empty():
		if p.begins_with("user://"):
			# 用户直接放的文件，用 AudioStreamWAV / OggVorbis 手动加载
			s = _load_raw_audio(p)
		else:
			s = ResourceLoader.load(p) as AudioStream
	_bgm_cache[bundled] = s
	return s


## 通用贴图加载（res:// 走 ResourceLoader，user:// 走 Image 手动加载）
static func _load_any(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("user://"):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
		return null
	if ResourceLoader.exists(path):
		var r := ResourceLoader.load(path)
		if r is Texture2D:
			return r
	return null


## 用户目录里的音频（未经导入系统），按扩展名选解码器
static func _load_raw_audio(path: String) -> AudioStream:
	var ext := path.get_extension().to_lower()
	match ext:
		"wav":
			var s := AudioStreamWAV.new()
			if s.load(path) == OK:
				return s
		"ogg":
			var s := AudioStreamOggVorbis.new()
			if s.load(path) == OK:
				return s
		"mp3":
			var s := AudioStreamMP3.new()
			if s.load(path) == OK:
				return s
	return null


## 清缓存（用户在运行时替换文件后可调用）
static func clear_cache() -> void:
	_icon_cache.clear()
	_bgm_cache.clear()
