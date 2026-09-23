## 启动分流（集成层阶段 1）
##
## 本脚本只决定「这次启动是跑自检、跑冒烟，还是进游戏」，不再包含任何检查项：
##   `--verify` → 实例化 `tools/self_check.tscn`（打印 108 项报告，退出码 0/1，CI 契约）
##   `--smoke`  → 切到 `tools/verify_e2e.tscn`（导出包内跑完整流程，退出码 0/1）
##   正常启动   → 切到主菜单 `scenes/main/main_menu.tscn`
##
## 自检逻辑（原 1.x–9.x 全部断言）已整段迁到 `tools/self_check.gd`，
## 这样「双击 exe 进游戏」与「CI 跑 --verify」共用同一个入口，互不干扰。
extends Node2D

## 自检场景（仅 `--verify` 时实例化）
const SELF_CHECK_SCENE: String = "res://tools/self_check.tscn"

## 端到端冒烟场景（仅 `--smoke` 时切换过去）
##
## 为什么需要它：`--verify` 只证明**自检资源**被打包，**不证明游戏流程资源**被打包。
## 编辑器里 `verify_e2e` 通过 ≠ 导出包能玩 —— 资源打包 / remap / 依赖裁剪都可能出问题，
## 而这些在编辑器里永远看不到。导出后跑一次 `七傳說.exe --smoke` 才算验证过「demo 能玩」。
const E2E_SCENE: String = "res://tools/verify_e2e.tscn"


func _ready() -> void:
	# 允许两种写法：`godot --path . -- --verify` 与 `godot --path . --verify`
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	var verify_only := args.has("--verify")
	var smoke_only := args.has("--smoke")

	# 任务 1.6：像素风 UI 主题已通过 project.godot `gui/theme/custom` 注册为项目默认
	# （正文 Cubic-11 / 标题 ChillBitmap，色值全取自 48 色板），全窗口控件自动套用。

	print("[Main] 「七傳說」骨架启动")
	print("[Main] 存档目录：%s" % ProjectSettings.globalize_path(GameConstants.SAVE_DIR))
	# 任务 9.3：启动日志（崩溃后可定位）
	GameLog.info("游戏启动：引擎 %s / 自检 %s / 冒烟 %s"
		% [Engine.get_version_info().get("string", "?"), str(verify_only), str(smoke_only)])
	# 8.2 设置持久化：启动即加载并应用（音量 / 垂直同步 / 全屏）
	SettingsStore.load()

	if verify_only:
		# 自检面板自己负责「打印报告 + 按退出码 quit」，这里只把它挂上来
		add_child((load(SELF_CHECK_SCENE) as PackedScene).instantiate())
		return

	if smoke_only:
		# ⚠️ 必须走 `change_scene_to_file` 而**不是** `add_child`：
		#    `verify_e2e` 内部会走真实的 `SceneManager.change_scene`（主菜单 → 据点 → 关卡），
		#    若把它挂在 main.tscn 下，第一次场景切换就会把它连根拔掉，测试静默中断。
		#    用 change_scene_to_file 让它成为 current_scene，与编辑器里
		#    `godot res://tools/verify_e2e.tscn` 的行为完全一致。
		# ⚠️ 还要再延迟一层：`_ready()` 期间 root 正在把 main.tscn 挂成子节点，
		#    此刻切场景会触发 `remove_child` 并报
		#    "Parent node is busy adding/removing children"（2026-09-18 导出包实测）。
		#    流程虽仍能跑通，但会留一条 ERROR —— 不允许「吵但无害」的问题留在包里。
		print("[Main] 冒烟模式：切到端到端验证场景（导出包内跑完整流程）")
		_change_to_e2e.call_deferred()
		return

	# 正常启动：进主菜单（延迟一帧，避免在 _ready 里换场景）
	SceneManager.change_scene.call_deferred(SceneManager.SCENE_MAIN_MENU)


## 切到端到端场景（仅 `--smoke` 用，见 `_ready()` 里的说明）
func _change_to_e2e() -> void:
	var err := get_tree().change_scene_to_file(E2E_SCENE)
	if err != OK:
		push_error("[Main] 无法加载端到端场景 %s（err=%d）—— 检查它是否被打包" % [E2E_SCENE, err])
		get_tree().quit(1)


## 接收 SceneManager 递过来的载荷（本场景只作启动分流，通常为空）
func on_scene_entered(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	print("[Main] 收到载荷：", payload)
