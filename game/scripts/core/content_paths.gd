## 内容替换层（Content Replacement Layer）· 统一解析链
##
## 用户诉求：「我可以自己換場地地圖任務特效等」——即**不改代码**替换内容。
##
## 问题（2026-09-20 调研结论）
## --------------------------
## 项目此前**没有任何覆盖机制**：无 mods 目录、无 `user://` 素材路径、无 sprite 覆盖链。
## 每一类内容各写各的路径拼接（如 `EnemyBase.PACK_CREATURE_ROOT`、`TileAtlas` 的
## `res://assets/tilesets/<biome>`），且散落在不同文件里，没有统一入口。
## 于是「替换」只能靠改代码 —— 与用户诉求正相反。
##
## 本类提供**唯一**的解析入口，语义固定为三级优先：
##
##     ① `user://content/<类别>/<相对路径>`   用户覆盖（最高优先）
##     ② 调用方给出的内置 `res://` 候选        随包内置
##     ③ 调用方的程序化占位                    永不失败（由调用方实现）
##
## 为什么用户层放 `user://` 而不是仓库内目录
## ----------------------------------------
## `user://` 在 Windows 上是 `%APPDATA%\Godot\app_userdata\七傳說\`，与项目目录分离：
##   · 游戏更新/重新导出**不会覆盖**用户内容；
##   · 不污染仓库，也不会被 git 误提交（仓库里的用户内容必然会被提交）；
##   · 是 Godot 对「用户数据」的惯用位置，与现有 `saves/` `logs/` `settings` 一致。
##
## 注意：本类只做**路径解析**，不负责加载。调用方拿路径后自行
## `ResourceLoader.load` / `Image.load`，以便各类资产用各自合适的加载方式。
class_name ContentPaths
extends RefCounted

## 用户内容根目录（对应 `%APPDATA%\Godot\app_userdata\七傳說\content\`）
const USER_ROOT := "user://content"

## 资产类别（即 `user://content/` 下的子目录名）
const CLASS_CHARACTERS := "characters"   ## 角色/敌人动画帧
const CLASS_FX := "fx"                   ## 特效贴图
const CLASS_TILESETS := "tilesets"       ## 地图图集
const CLASS_LEVELS := "levels"           ## 关卡数据覆盖
const CLASS_ICONS := "icons"             ## 装备/物品图标
const CLASS_MUSIC := "music"             ## 背景音乐 BGM
const CLASS_UI := "ui"               ## UI 皮肤贴图（面板/按钮/边框）

const ALL_CLASSES: Array[String] = [
	CLASS_CHARACTERS, CLASS_FX, CLASS_TILESETS, CLASS_LEVELS,
	CLASS_ICONS, CLASS_MUSIC, CLASS_UI,
]


## 路径是否存在。`res://` 走 ResourceLoader（受导入系统管辖），
## `user://` 走 FileAccess（用户直接放文件，不经导入）。
static func exists(path: String) -> bool:
	if path.is_empty():
		return false
	if path.begins_with("user://"):
		return FileAccess.file_exists(path)
	return ResourceLoader.exists(path)


## 依次返回第一个存在的候选路径；都不存在返回 `""`。
## 调用方约定：拿到 `""` 即走程序化占位。
static func resolve(candidates: Array) -> String:
	for c in candidates:
		var p := str(c)
		if exists(p):
			return p
	return ""


## 用户覆盖路径。`relative` 用 `/` 分隔，可含子目录。
## 例：`user_path(CLASS_FX, "hit_spark.png")` → `user://content/fx/hit_spark.png`
static func user_path(klass: String, relative: String) -> String:
	return "%s/%s/%s" % [USER_ROOT, klass, relative]


## 用户**类别目录**（不含尾部斜杠）。例：`class_dir(CLASS_FX)` → `user://content/fx`
##
## 与 `user_path` 的分工：`user_path` 定位**单个文件**，本函数用于
## 「**扫描整个类别目录**」的场景（如按关卡 id 覆盖关卡 JSON、按生态名覆盖图集）。
## 用 `path_join()` 拼接子项，避免手写 `"%s/%s"` 时多一个或少一个斜杠。
static func class_dir(klass: String) -> String:
	return "%s/%s" % [USER_ROOT, klass]


## **推荐入口**：用户覆盖优先，其次内置。
## `bundled` 为随包路径（`res://...`）；返回实际可用路径，全无则 `""`。
static func resolve_with_user(klass: String, relative: String, bundled: String) -> String:
	return resolve([user_path(klass, relative), bundled])


## 内置候选列表 + 用户覆盖的完整解析（用户优先，再按内置顺序）。
## `relatives` 与 `bundleds` 应一一对应；允许 `bundleds` 比 `relatives` 长（末尾视为无用户槽位）。
static func resolve_list(klass: String, relatives: Array, bundleds: Array) -> String:
	var cands: Array[String] = []
	for i in range(maxi(relatives.size(), bundleds.size())):
		if i < relatives.size():
			cands.append(user_path(klass, str(relatives[i])))
		if i < bundleds.size():
			cands.append(str(bundleds[i]))
	return resolve(cands)


## 确保用户内容目录存在（首次运行/打开「内容目录」入口时调用）。
## 返回实际创建/确认的目录列表，便于日志与自检断言。
static func ensure_user_dirs() -> Array[String]:
	var made: Array[String] = []
	for klass in ALL_CLASSES:
		var dir := "%s/%s" % [USER_ROOT, klass]
		if not DirAccess.dir_exists_absolute(dir):
			var err := DirAccess.make_dir_recursive_absolute(dir)
			if err != OK:
				push_warning("ContentPaths: 无法创建用户内容目录 %s (err=%d)" % [dir, err])
				continue
		made.append(dir)
	return made


## 用户内容根目录的**真实磁盘路径**，供 UI 展示 / 「打开文件夹」/ 启动日志用。
##
## ⚠️ `user://` 的根**随启动方式变化**，不能假定就是 `%APPDATA%`：
##   · 正常启动游戏 → `%APPDATA%\Godot\app_userdata\七傳說\content`
##   · 无头 / 便携（self-contained）模式 → `<项目目录>\Godot\app_userdata\七傳說\content`
##     （`game/.gitignore` 里 `/Godot/` 那条就是为这个运行残留准备的）
## 更糟的是这种模式下 `globalize_path()` 返回的是**相对路径**（`./Godot/...`），
## 直接交给用户等于给了一条没法用的路径。所以这里把相对路径补成绝对路径。
static func user_root_absolute() -> String:
	var p := ProjectSettings.globalize_path(USER_ROOT)
	if not p.is_absolute_path():
		p = ProjectSettings.globalize_path("res://").path_join(p)
	return p.simplify_path()
