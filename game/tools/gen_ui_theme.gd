## UI 主题生成器（任务 1.6 · 开发用，不属于游戏玩法）
##
## 把 `UITheme.build()` 的运行时构建结果**落盘**为 `res://scenes/ui/theme/theme.tres`，
## 并注册为项目默认主题（project.godot `gui/theme/custom`）——
## 这是 Godot 唯一可靠的「全窗口所有控件自动套用主题」机制
## （`Window.theme` 在无头/运行时并不向子控件传播）。
##
## 用法：
##   godot --headless --path "D:/七傳說/game" res://tools/gen_ui_theme.tscn
##   退出码 0 = 生成成功；非 0 = 失败（已打印原因）
##
## ⚠️ 改过 `UITheme` / `GameConstants` / `UISkin` 的样式后，**必须重跑本生成器**
##    再提交 `theme.tres`，否则运行中看到的仍是旧主题（`theme.tres` 是构建产物，
##    不是手写文件）。
##
## ⚠️⚠️ 为什么这个生成器必须留在 `tools/`（2026-09-30 复盘教训）：
##    本批把「金色按鈕九宮格」写进了 `UITheme.build()`，但**没有任何运行时代码**
##    调用 `build()` —— 游戏挂的是 `theme.tres`。而生成器当时被移出了 `tools/`，
##    于是「代码看起来改了、verify_ui 也绿、游戏里按钮毫无变化」。
##    本脚本的回读校验现在会**比对产物与代码的 Button/normal 型别**，
##    生成器没重跑（产物还是 StyleBoxFlat 而代码已是 StyleBoxTexture）会直接报错退出。
extends Node

const THEME_PATH: String = "res://scenes/ui/theme/theme.tres"


func _ready() -> void:
	print("===== 生成 UI 主题 theme.tres =====")
	var t := UITheme.build()
	if t == null:
		printerr("[gen_ui_theme] UITheme.build() 返回 null，中止")
		get_tree().quit(1)
		return

	var err := ResourceSaver.save(t, THEME_PATH)
	if err != OK:
		printerr("[gen_ui_theme] 保存失败：%s（Error %d）" % [THEME_PATH, err])
		get_tree().quit(1)
		return

	print("[gen_ui_theme] 已生成 %s" % THEME_PATH)
	print("[gen_ui_theme] 请在 project.godot 确认 gui/theme/custom=\"%s\"" % THEME_PATH)

	# 回读校验：保存后能原样加载，且**与 build() 一致**（防「改了代码忘了重跑」）。
	# ⚠️ 必须用 `CACHE_MODE_IGNORE` 绕过资源缓存 —— 否则 `load()` 会命中**保存前**
	#    就已在缓存里的旧 theme.tres，回读永远是旧值（假阴性，2026-09-30 踩到）。
	var loaded := ResourceLoader.load(THEME_PATH, "Theme", ResourceLoader.CACHE_MODE_IGNORE)
	if not (loaded is Theme):
		printerr("[gen_ui_theme] 回读失败：%s 不是 Theme" % THEME_PATH)
		get_tree().quit(1)
		return
	var lt := loaded as Theme
	var problems: Array[String] = []
	if lt.default_font_size != t.default_font_size:
		problems.append("default_font_size 产物=%d 代码=%d"
			% [lt.default_font_size, t.default_font_size])
	if not lt.has_stylebox(&"panel", "PanelContainer"):
		problems.append("缺 PanelContainer/panel")
	if not lt.has_stylebox(&"normal", "Button"):
		problems.append("缺 Button/normal")
	if not lt.has_stylebox(&"fill", "ProgressBar"):
		problems.append("缺 ProgressBar/fill")
	# 关键：产物与代码的 Button/normal 必须**同类**
	# （金九宫格 = StyleBoxTexture；回退 = StyleBoxFlat）。不同类 ⇒ 生成器没重跑。
	var want_sb := t.get_stylebox(&"normal", "Button")
	var got_sb := lt.get_stylebox(&"normal", "Button")
	if want_sb != null and got_sb != null and want_sb.get_class() != got_sb.get_class():
		problems.append("Button/normal 型别不一致：产物=%s 代码=%s"
			% [got_sb.get_class(), want_sb.get_class()])
	if not problems.is_empty():
		printerr("[gen_ui_theme] 回读校验未通过：%s" % ", ".join(problems))
		get_tree().quit(1)
		return

	print("[gen_ui_theme] 回读校验通过（Button/normal = %s），退出码 0"
		% (got_sb.get_class() if got_sb != null else "null"))
	get_tree().quit(0)
