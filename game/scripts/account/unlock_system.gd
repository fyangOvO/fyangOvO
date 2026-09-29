## 解锁系统（任务 5.3 · class_name 纯静态）
##
## GDD 5.4：关卡 L2–L20 顺序通关；梦魇 I–V 全 20 关通关后逐层递进；
##   天赋分支 2/3 L15/L30；仓库页 2/3/4 累计通关 5/10/15 关。
class_name UnlockSystem
extends RefCounted

const LEVEL_COUNT := 20
const STASH_PAGE_UNLOCKS := {2: 5, 3: 10, 4: 15} # 页数 -> 累计通关数


## 关卡已解锁：L1 恒开，其余 = 前一关已通关（顺序）
static func is_level_unlocked(level: int, cleared_count: int) -> bool:
	if level <= 1:
		return true
	return level - 1 <= cleared_count and level <= LEVEL_COUNT


## 梦魇层级已解锁：全 20 关通关后逐层递进（梦魇 I = 通关后解锁，V = 再通关 4 次）
## 简化口径（GDD 5.4「逐层递进」）：cleared_count ≥ 20 开 I，每再通 5 关 +1 层
static func is_difficulty_unlocked(tier: int, cleared_count: int) -> bool:
	if tier <= 0:
		return true
	if tier == 1:
		return cleared_count >= LEVEL_COUNT
	return cleared_count >= LEVEL_COUNT + (tier - 1) * 5


## 天赋分支解锁（GDD 5.4：武力 L1 / 守护 L15 / 秘法 L30）
static func is_talent_branch_unlocked(branch: String, account_level: int) -> bool:
	return TalentTree.is_branch_unlocked(branch, account_level)


## 仓库页已解锁（累计通关 5/10/15 关）
static func stash_pages_unlocked(cleared_count: int) -> int:
	var pages := 1
	for p in STASH_PAGE_UNLOCKS:
		if cleared_count >= int(STASH_PAGE_UNLOCKS[p]):
			pages = maxi(pages, p)
	return pages


# =============================================================================
# 技能解锁（第一步 · 工单 1-L11；见 `01-技能体系.md` §9）
# =============================================================================
#
# 双轨：① 成长轨 = 账号等级（`skill.unlock_level`）
#       ② 进度轨 = 章节 BOSS 首通（`skill.unlock_boss` 落在 `cleared_levels` 里）
#
# ⚠️ **不新增存档字段**：解锁状态完全由「账号等级 + 已通关关卡」**推导** ——
#    两者均已在存档中。这也意味着**解锁不会自动改动出战栏**（§9.3）：
#    出战栏仍由 `SaveData.skill_bar` 决定，本模块只回答「能不能装」。

## 单个技能是否已解锁。
##
## `skill_id` 未注册 ⇒ false（防拼错 id 静默放行）。
## 两条门槛都满足才算解锁（`unlock_level <= 0` = 无等级门槛；`unlock_boss` 空串 = 无 BOSS 门槛）。
static func is_skill_unlocked(skill_id: String, account_level: int,
		cleared_levels: Array) -> bool:
	var sd := ConfigLoader.get_skill(skill_id)
	if sd == null:
		return false
	if sd.unlock_level > 0 and account_level < sd.unlock_level:
		return false
	if not sd.unlock_boss.is_empty() and not (sd.unlock_boss in cleared_levels):
		return false
	return true


## 某职业**已解锁**的技能 id 列表（保持 `class_skill_ids` 的原始顺序）。
##
## 供技能面板 / 图鉴过滤；未解锁技能在 UI 中灰显（而非从列表移除，便于玩家看到目标）。
static func unlocked_skill_ids(class_id: String, account_level: int,
		cleared_levels: Array) -> Array[String]:
	var out: Array[String] = []
	for sid in ConfigLoader.class_skill_ids(class_id):
		if is_skill_unlocked(sid, account_level, cleared_levels):
			out.append(sid)
	return out


## 技能未解锁时的原因文案（供 UI 提示）；已解锁返回空串。
static func skill_lock_reason(skill_id: String, account_level: int,
		cleared_levels: Array) -> String:
	var sd := ConfigLoader.get_skill(skill_id)
	if sd == null:
		return "技能不存在"
	if sd.unlock_level > 0 and account_level < sd.unlock_level:
		return "账号等级 %d 解锁" % sd.unlock_level
	if not sd.unlock_boss.is_empty() and not (sd.unlock_boss in cleared_levels):
		return "通关 %s 解锁" % sd.unlock_boss
	return ""
