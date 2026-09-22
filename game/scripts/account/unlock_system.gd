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
