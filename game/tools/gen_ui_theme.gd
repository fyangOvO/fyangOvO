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
## ⚠️ 改过 UITheme / GameConstants 的样式后，**必须重跑本生成器**再提交 theme.tres，
##    否则运行中看到的仍是旧主题（theme.tres 是构建产物，不是手写文件）。
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

	# 回读校验：保存后能原样加载，且关键项齐全
	var loaded := load(THEME_PATH)
	if not (loaded is Theme):
		printerr("[gen_ui_theme] 回读失败：%s 不是 Theme" % THEME_PATH)
		get_tree().quit(1)
		return
	var lt := loaded as Theme
	var ok := lt.default_font_size == 11 \
		and lt.has_stylebox(&"panel", "PanelContainer") \
		and lt.has_stylebox(&"normal", "Button") \
		and lt.has_stylebox(&"fill", "ProgressBar")
	if not ok:
		printerr("[gen_ui_theme] 回读校验未通过：样式/字号缺失")
		get_tree().quit(1)
		return

	print("[gen_ui_theme] 回读校验通过，退出码 0")
	get_tree().quit(0)
