## verify 脚本的「失败兜底看门狗」（纯静态工具，不属于游戏玩法）
##
## 用法 —— 放在 `_ready()` 的**第一行**：
##   VerifyWatchdog.arm(get_tree())
##
## ---------------------------------------------------------------------------
## 为什么需要（真实事故 · 2026-09-18）
## ---------------------------------------------------------------------------
## `game/tools/` 下全部 `verify_*.gd` 都把 `get_tree().quit(...)` 放在 `_ready()` 的
## **最后一行**。于是只要中途任何一行抛运行时错误，`_ready()` 会**立即中断**，
## 那行 `quit` 永不执行 ⇒ **进程永久挂起**，只能等外部 `timeout` 杀掉。
##
## 后果是「失败信号完全丢失」：
##   * CI 上「测试失败」表现为「卡满超时」（白占 runner 60~180 秒）；
##   * 退出码是 **124**（外部杀的）而不是 **1**（测试自己判定的失败），
##     任何靠退出码判红的流水线都会把它当成「基础设施问题」而不是「代码红了」。
##
## 触发本次加固的具体链路：
##   两个 agent 并发跑 Godot ⇒ 共享 `%APPDATA%\Godot\app_userdata\七傳說\saves`
##   ⇒ Windows 文件锁 ⇒ `verify_save` 的 `create_new_slot()` 返回 null
##   ⇒ 紧接着 `d.add_gold()` 对 Nil 调方法 ⇒ `SCRIPT ERROR` ⇒ `_ready()` 中断
##   ⇒ 挂死 180s 被 `timeout` 杀（exit=124）。
##
## ---------------------------------------------------------------------------
## 看门狗**兜不住**什么：解析错误（2026-09-20 事故）
## ---------------------------------------------------------------------------
## 队友在编辑 `verify_level_gen.gd` 中途被中断，留下 4 处解析错误。看门狗**完全没反应**，
## 进程挂死到 120s 被外部杀掉（exit=124）。原因是结构性的，不是配置问题：
##
##     `arm()` 写在 `_ready()` 里，而解析失败的脚本**根本到不了 `_ready()`**。
##
## 也就是说，**任何在 `_ready()` 里武装的看门狗，都只能覆盖「加载成功之后」的失败**。
## 加载期失败必须由**脚本之外**的东西兜：
##   * `tools/parse_all.tscn`  —— 开跑前把全部 .gd 解析一遍（183 个约 5 秒），
##   * `tools/run_regression.py` —— 逐个脚本流式读输出，命中 `Parse Error` 就提前杀掉
##     并把 `文件:行` 打出来（坏脚本从 120 秒降到约 2 秒）。
## 两者都已接入全量回归，默认生效。
##
## 定位：这是**最后一道防线**，不是第一道
## ---------------------------------------------------------------------------
## 该判空的地方仍然必须判空（例如 `verify_save.gd` 里 `create_new_slot` 返回 null
## 之后就走失败路径），看门狗只负责兜住「没料到的异常」，不替代码做正确性检查。
##
## 超时值：正常 verify 脚本都在**秒级**完成（全量 50 个脚本合计约 91 秒，
## 单个均值 < 2 秒），默认 60 秒对任何正常脚本都绰绰有余。
class_name VerifyWatchdog
extends RefCounted

## 默认超时（秒）。改大只会让真挂死更晚被发现，除非脚本本身确实要跑很久。
const DEFAULT_SECONDS: float = 60.0


## 装上一次性看门狗：`seconds` 秒后若进程仍未退出，报错并以**退出码 1** 结束。
##
## `tree` 为 null 时静默跳过 —— 兜底工具本身不该成为新的崩溃点。
static func arm(tree: SceneTree, seconds: float = DEFAULT_SECONDS) -> void:
	if tree == null:
		return
	# process_always = true  : 即使场景树被暂停也照常计时
	# process_in_physics     = false
	# ignore_time_scale      = true : 不受 Engine.time_scale 影响
	var timer := tree.create_timer(seconds, true, false, true)
	timer.timeout.connect(func() -> void:
		push_error("[verify] 看门狗超时（%.0f 秒）—— 脚本未正常退出，判定失败。"
			% seconds + "多半是中途抛了运行时错误导致 quit() 没执行，请看上面的 SCRIPT ERROR。")
		tree.quit(1))
