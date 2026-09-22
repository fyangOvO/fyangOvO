## 性能优化：通用对象池（任务 8.3 · class_name ObjectPool 纯静态）
##
## 高频创建/销毁的对象（敌人/掉落/飘字）走池复用：
##   - acquire(场景, 工厂): 池里有 → 复用；没有 → 工厂创建
##   - release(obj): 归还池（隐藏 + 移出活跃树）；池满 → queue_free 兜底
##   - 统计：hits / misses / reuse_rate / pool_sizes，供性能报告与 verify 断言
## 线程安全：不涉及（同帧单线程）。
class_name ObjectPool

## 池容量上限（每场景），超限释放走 queue_free
const DEFAULT_CAPACITY := 64

static var _pools: Dictionary = {}          # 场景路径 -> Array[Node]
static var _hit: Dictionary = {}            # 场景路径 -> int
static var _miss: Dictionary = {}           # 场景路径 -> int
static var _live: Dictionary = {}           # 场景路径 -> int（活跃数）
static var _capacity: Dictionary = {}       # 场景路径 -> int


static func register(key: String, capacity: int = DEFAULT_CAPACITY) -> void:
	if not _pools.has(key):
		_pools[key] = []
		_capacity[key] = capacity
		_hit[key] = 0
		_miss[key] = 0
		_live[key] = 0


## 取一个节点；key 未注册自动注册（容量默认）。
## factory 在 miss 时调用生成新实例（lambda 或 Callable）。
static func acquire(key: String, factory: Callable) -> Node:
	if not _pools.has(key):
		register(key)
	var pool: Array = _pools[key]
	if pool.size() > 0:
		_hit[key] += 1
		var node: Node = pool.pop_back()
		if node is CanvasItem:
			node.visible = true
		node.set_process(true)
		_live[key] += 1
		return node
	_miss[key] += 1
	_live[key] += 1
	return factory.call()


## 归还池；容量已满 → queue_free 兜底（不泄漏）
static func release(key: String, node: Node) -> void:
	if node == null:
		return
	if not _pools.has(key):
		register(key)
	var pool: Array = _pools[key]
	if pool.size() < int(_capacity[key]):
		_live[key] -= 1
		if node is CanvasItem:
			node.visible = false
		node.set_process(false)
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		pool.append(node)
	else:
		_live[key] -= 1
		node.queue_free()


static func hits(key: String) -> int:
	return int(_hit.get(key, 0))


static func misses(key: String) -> int:
	return int(_miss.get(key, 0))


## 复用率 = hits / (hits + misses)；从未请求 → 0
static func reuse_rate(key: String) -> float:
	var h := hits(key)
	var m := misses(key)
	if h + m == 0:
		return 0.0
	return float(h) / float(h + m)


static func live(key: String) -> int:
	return int(_live.get(key, 0))


static func pool_size(key: String) -> int:
	return int(_pools.get(key, []).size())


static func clear() -> void:
	_pools.clear()
	_hit.clear()
	_miss.clear()
	_live.clear()
	_capacity.clear()


## 释放全部池内节点（进程退出前清理，避免 headless 泄漏告警）
static func drain() -> void:
	for key in _pools:
		for node in _pools[key]:
			if is_instance_valid(node):
				node.queue_free()
		_pools[key] = []
	clear()


## 报告（供 verify_perf83 / 优化报告输出）
static func report() -> String:
	var out := "ObjectPool 报告：\n"
	for key in _pools:
		out += "  %-20s hit=%d miss=%d 复用率=%.0f%% 池=%d 活跃=%d\n" % [
			key, hits(key), misses(key), reuse_rate(key) * 100.0,
			pool_size(key), live(key)]
	return out
