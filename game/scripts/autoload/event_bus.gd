## 全局事件总线（Autoload · 单例名 `EventBus`）
##
## 定位：**用信号解耦模块**。掉落系统不需要认识 UI，UI 也不需要认识角色 ——
##       双方只依赖本总线的信号契约。
##
## 铁律（阶段 1 定死，后续阶段必须遵守）：
##   1. 本文件**只声明信号 + 转发**，禁止写任何业务逻辑。
##   2. 信号名一经发布即为**公开契约**，重命名必须全局搜索调用点并同步改。
##   3. 携带 Resource 的信号（如 equipment_changed）传**引用**，监听方不得修改入参。
##   4. 需要「谁触发的」时用 `source` 参数，不要新增平行信号。
##
## 命名约定：
##   - 过去式 / 已发生事件（`_changed` / `_gained` / `_died`）→ 通知用，监听方不应产生副作用
##   - 祈使式请求（`request_*`）→ 意图用，由唯一处理方响应
extends Node

# =============================================================================
# 一、装备与物品
# =============================================================================

## 装备变更（穿上 / 脱下 / 替换）。slot 为 GameConstants.EquipSlot。
signal equipment_changed(slot: int, new_item: EquipmentInstance, old_item: EquipmentInstance)

## 装备被强化（+N 提升）
signal equipment_forged(item: EquipmentInstance, old_level: int, new_level: int)

## 装备被洗练（词缀数值重掷）
signal equipment_rerolled(item: EquipmentInstance)

## 装备被分解
signal equipment_dismantled(item: EquipmentInstance, materials: Dictionary)

## 物品进入背包
signal item_added(item: EquipmentInstance, is_new: bool)

## 物品离开背包（出售 / 分解 / 丢弃）
signal item_removed(item: EquipmentInstance, reason: String)

## 背包已满，有物品被拒绝入包（UI 应给出提示）
signal inventory_full(rejected_item: EquipmentInstance)

## 金币变动（delta 可正可负）
signal gold_changed(new_amount: int, delta: int)

## 材料变动。materials 为 {材料ID: 数量} 的增量字典。
signal materials_changed(materials: Dictionary, reason: String)

## 消耗品变动（步骤 8A · 药水）。consumables 为 {ID: 数量} 全量快照。
signal consumables_changed(consumables: Dictionary, reason: String)

# =============================================================================
# 二、成长（局外：账号等级 / 经验）
# =============================================================================

## 获得经验。source 为来源标识（"monster" / "level_clear" / "quest"）。
signal xp_gained(amount: float, source: String)

## 等级提升（局外账号等级）
signal level_up(new_level: int, old_level: int)

## 天赋点变动
signal talent_points_changed(available_points: int)

## 天赋节点被点亮
signal talent_node_unlocked(node_id: String)

## 局外属性重算完成（装备 / 天赋 / 等级任一变化后触发，UI 与战斗侧据此刷新）
signal stats_recalculated(final_stats: Dictionary)

# =============================================================================
# 三、成长（局内：单局临时成长，出关清零）
# =============================================================================

## 局内等级提升，应弹出三选一
signal run_level_up(new_run_level: int, choices: Array)

## 局内增益被选择（三选一 / 祭坛）
signal run_buff_selected(buff_id: String, stacks: int)

## 某属性类已达局内上限，三选一池应切换为功能性选项（GDD 0.4 节 4.4）
signal run_buff_cap_reached(stat_key: String)

## 连杀数变化（GDD 0.4 节 4.3）
signal kill_streak_changed(streak: int, bonus_attack_pct: float)

# =============================================================================
# 四、战斗
# =============================================================================

## 造成伤害（damage 为最终结算值，is_crit 标记暴击）
signal damage_dealt(target: Node, amount: float, is_crit: bool, element: String)

## 受到伤害
signal damage_taken(source: Node, amount: float, element: String)

## 单位死亡
signal unit_died(unit: Node, killer: Node)

## 任务 6.3：BOSS 阶段切换（阈值 75% / 50% / 25% → 阶段 2 / 3 / 4）
signal boss_phase_changed(enemy: Node, phase: int, skills: Array)

## 玩家角色死亡（触发结算损失流程，GDD 0.2 节死亡方案 B）
signal player_died(reason: String)

## 玩家复活（回到存档点）
signal player_respawned()

## 生命值变化（UI 血条监听）
signal health_changed(current: float, maximum: float)

## 资源值变化（UI 资源条监听）
signal resource_changed(current: float, maximum: float)

# =============================================================================
# 五、掉落与拾取
# =============================================================================

## 生成一件掉落物（掉落系统 → 地面表现层）
signal loot_dropped(item: EquipmentInstance, position: Vector2)

## 掉落物被拾取（步骤 6 起真正广播）。
## 载荷契约：LootDrop 拾取 payload（{type, amount, item_id, rarity, item_level, instance?}）。
## 消费点：PickupToastHUD（局内拾取提示）。
signal loot_picked_up(entry: Dictionary)

## 稀有掉落出现（稀有度 ≥ 史诗时触发，用于光柱 / 音效 / 镜头反馈）
signal rare_loot_spawned(item: EquipmentInstance, position: Vector2)

## 拾取范围变化
signal pickup_radius_changed(radius: float)

# =============================================================================
# 六、关卡与流程
# =============================================================================

## 请求切换场景（由 SceneManager 响应，其他模块只发这个信号）
signal request_scene_change(scene_path: String, payload: Dictionary)

## 请求开始一个关卡
signal request_start_level(level_id: String, difficulty_tier: int)

## 关卡开始
signal level_started(level_id: String, difficulty_tier: int)

## 关卡目标进度更新（current / required）
signal level_objective_updated(current: float, required: float, description: String)

## 关卡完成
signal level_completed(level_id: String, difficulty_tier: int, summary: Dictionary)

## 关卡失败（玩家死亡退出）
signal level_failed(level_id: String, reason: String)

## 场景切换开始 / 结束（用于显示过场遮罩）
signal scene_transition_started(scene_path: String)
signal scene_transition_finished(scene_path: String)

## 关卡解锁（GDD 0.5 节 5.4）
signal level_unlocked(level_id: String)

## 难度层级解锁
signal difficulty_tier_unlocked(tier: int)

# =============================================================================
# 七、存档
# =============================================================================

## 存档写入完成
signal game_saved(slot: int, success: bool, error: String)

## 存档读取完成
signal game_loaded(slot: int, success: bool, error: String)

## 存档损坏并已自动回滚到备份
signal save_corrupted_recovered(slot: int, backup_index: int)

## 存档槽列表变化（新建 / 删除）
signal save_slots_changed()

# =============================================================================
# 八、UI 与输入
# =============================================================================

## 请求打开 / 关闭某个面板（"inventory" / "character" / "talent" / "forge" ...）
signal request_panel_toggle(panel_id: String, visible: bool)

## 面板可见性变化（供输入屏蔽逻辑使用）
signal panel_visibility_changed(panel_id: String, visible: bool)

## 请求显示提示文本（飘字 / Toast）
signal notification_requested(message: String, color: Color)

## 请求暂停 / 恢复
signal pause_requested(paused: bool)

## 某个输入动作的绑定被改动（InputRemapper 发出，设置界面据此刷新）
signal input_binding_changed(action: StringName)

## 玩家自定义绑定已从磁盘载入完成（count 为生效的动作数）
signal input_bindings_loaded(count: int)

## 手柄热插拔（InputRemapper 转发 Input.joy_connection_changed）。
## 监听方据此决定是否弹「已连接手柄 / 手柄已拔出」提示并切换按键图标。
signal joypad_connection_changed(device: int, connected: bool)

# =============================================================================
# 九、配置与初始化
# =============================================================================

## 配置加载完成（ConfigLoader 加载完 `game/data/` 后发出）
signal config_loaded(entry_counts: Dictionary)

## 配置加载失败（数据文件缺失 / 格式错误）
signal config_load_failed(path: String, error: String)

## 全部 Autoload 就绪（供 main 场景判断可以开始游戏）
signal game_ready()


# =============================================================================
# 辅助：统一通知入口（避免各模块各自拼字符串）
# =============================================================================

## 发一条 UI 提示。color 默认用常规文本色。
func notify(message: String, color: Color = GameConstants.COLOR_TEXT_NORMAL) -> void:
	notification_requested.emit(message, color)


## 发一条稀有度染色的提示（掉落 / 鉴定结果用）
func notify_rarity(message: String, rarity: int) -> void:
	notification_requested.emit(message, GameConstants.rarity_color(rarity))
