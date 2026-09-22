## 全项目 GDScript 解析预检（纯静态工具，不属于游戏玩法）
##
## 用法
## ----
##     godot --headless --path <项目目录> res://tools/parse_all.tscn
##
## 退出码：0 = 全部可解析；1 = 有文件解析失败（出错位置已在 stdout）。
##
## ---------------------------------------------------------------------------
## 为什么需要（真实事故 · 2026-09-20）
## ---------------------------------------------------------------------------
## 队友在编辑 `tools/verify_level_gen.gd` 中途被中断，留下 4 处解析错误。
## 后果不是「报错」，而是**静默挂死**：
##
##   1. 主场景脚本解析失败 ⇒ 场景根本不会实例化；
##   2. `VerifyWatchdog.arm()` 写在 `_ready()` 里 ⇒ 永远到不了 `_ready()`，
##      看门狗从未被武装 ⇒ **看门狗对解析错误结构性失明**；
##   3. 进程既不报错也不退出，只能耗到 `run_regression.py` 的 120s 墙钟兜底，
##      表现为 exit=124 —— 被误读成「基础设施问题」而不是「代码红了」。
##
## 实测：解析错误在**进程启动的头 0.1 秒**就打印完了，剩下 120 秒全在空转。
## 所以把「能不能加载」提前到跑测试之前，一次性问完（184 个 .gd 约 2 秒）。
##
## ---------------------------------------------------------------------------
## 为什么必须是**场景**而不是 `--script`（踩过的坑，别改回去）
## ---------------------------------------------------------------------------
## `--script res://tools/parse_all.gd` 走的是自定义 MainLoop，**autoload 不会被注册**。
## 于是任何引用 `EventBus` / `ConfigLoader` 这类单例名的脚本都会编译失败：
##
##     SCRIPT ERROR: Compile Error: Identifier not found: EventBus
##
## 实测这样会把 184 个文件里的**约 90 个**误报成「解析失败」—— 一个只会喊狼来了的
## 预检比没有预检更糟。走普通场景则 autoload 正常就位，与 `verify_*.tscn` 环境一致。
##
## ---------------------------------------------------------------------------
## 定位：这是**预检**，不是替代品
## ---------------------------------------------------------------------------
## 它只回答「能不能加载」，不回答「逻辑对不对」。断言仍然归 `verify_*.tscn`。
extends Node

## 不扫的目录（第三方插件 / 引擎缓存）。
const SKIP_DIRS := ["res://addons"]

## 不扫自己的脚本：正在执行的脚本没必要（也不该）再 load 一次。
const SELF := "res://tools/parse_all.gd"


func _ready() -> void:
	var all: Array[String] = []
	_walk("res://", all)
	all.sort()

	var broken: Array[String] = []
	for path in all:
		# **必须用默认缓存模式（REUSE），不能 CACHE_MODE_IGNORE。**（踩过的坑，别改）
		# IGNORE 会**重新解析已经在用的脚本** —— 包括各个 autoload 单例和本工具自己。
		# 后果是运行中的脚本对象被就地换掉，VM 状态损坏，接下来连
		#   SCRIPT ERROR: Cannot call method 'load' on a null value.
		# 这种莫名其妙、且完全指错方向的错误都会冒出来。
		#
		# REUSE 的安全性来自一个事实：**已经加载成功的脚本必然解析通过**，
		# 所以「复用缓存」不会漏掉任何解析错误；尚未加载过的脚本仍会真解析一遍。
		# 解析失败时 load() 返回 null，并把
		#   SCRIPT ERROR: Parse Error: ...
		#      at: GDScript::reload (res://tools/x.gd:356)
		# 打到 stdout —— 那行 `at:` 就是出错位置。
		var res: Variant = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_REUSE)
		# **不能用 `res == null` 判失败**（实测踩过，会产生假绿）：
		# 解析失败时 Godot 仍然返回一个**非 null 的 Script 对象**，
		# 只是 can_instantiate() == false、get_instance_base_type() == ""。
		# 实测对照：坏脚本 false/''，好脚本 true/'RefCounted'。
		#
		# 注意 can_instantiate() 对 `@abstract` 类也会返回 false —— 本仓库目前
		# 零处使用 @abstract（grep 过），若将来引入，需要在这里放行。
		if res == null or not (res as Script).can_instantiate():
			broken.append(path)

	print("[parse_all] 扫描 %d 个 .gd 文件" % all.size())
	if broken.is_empty():
		print("[parse_all] 结果：全部可解析")
		get_tree().quit(0)
		return

	print("[parse_all] 结果：%d 个文件解析失败" % broken.size())
	print("[parse_all] 出错位置见上方 `at: GDScript::reload (<文件>:<行>)`；失败文件清单：")
	for b in broken:
		print("[parse_all]   x %s" % b)
	get_tree().quit(1)


## 递归收集 `dir` 下的全部 `.gd`（跳过隐藏目录与 SKIP_DIRS）。
func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := dir.path_join(entry)
		if d.current_is_dir():
			if not entry.begins_with(".") and not SKIP_DIRS.has(full):
				_walk(full, out)
		elif entry.ends_with(".gd") and full != SELF:
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()
