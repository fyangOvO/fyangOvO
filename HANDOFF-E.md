# 交接文件 HANDOFF-E（符文掉落接線批次 · B6 `2-L12` / `2-V12`）

> 日期：2026-09-30 ｜ 分支：`main` ｜ 前置：HANDOFF-D（符文圖標 v2）
> 本批把「**符文從哪來**」接上 —— 在此之前 `roll_rune_drop()` **零呼叫方**、
> `unlocked_runes` 在真實遊玩路徑**零寫入方** ⇒ 剛打磨好的符文圖鑑實機永遠 **0 / 24**。

---

## 1. 本批次做了什麼

| # | 改動 | 檔案 |
|---|---|---|
| 1 | `LootTable` 新增 `rune_drop_chance`（+ `validate()` 範圍檢查） | `resources/loot_table.gd` |
| 2 | `ConfigLoader` 補讀 `rune_drop_chance`（**原本沒讀 ⇒ 靜默脫鉤**） | `scripts/autoload/config_loader.gd` |
| 3 | 重寫 `roll_rune_drop()`：改讀表、收 `MonsterData`、加 `all_rune_ids()` / `rune_duplicate_material_amount()` | `scripts/loot/loot_roller.gd` |
| 4 | 怪物死亡接上符文桶（抽 `_spawn_loot_drop()` 消除重複落地邏輯） | `scripts/enemies/enemy_base.gd` |
| 5 | 地面符文物件：紫罗兰光柱 + **真实符文图标**（20px 世界尺寸） | `scripts/loot/loot_drop.gd` |
| 6 | 玩家拾取：**首获永久解锁** / **重复转魔石** | `scripts/player/player_controller.gd` |
| 7 | 拾取提示条：`解锁符文：X` / `重复符文 X → 魔石 +N` | `scripts/ui/pickup_toast.gd` |
| 8 | 校驗：`verify_loot_tables` F 段（2-V12）+ `verify_loot` H/I 段 | `tools/verify_loot_tables.gd`、`tools/verify_loot.gd` |
| 9 | 掉落预览工具：符文行 + **修好「所有掉落物在画面外」的既有 bug** | `tools/loot_preview.gd/.tscn` |

---

## 2. 符文掉落全链路（本批后的真实数据流）

```
怪物死亡
  └ EnemyBase._drop_loot()
      ├ LootRoller.roll_loot(...)        ← 主掉落（金币/材料/消耗品/装备），受 drop_chance 触发
      └ LootRoller.roll_rune_drop(data, level)  ← 【本批新增】第二次**独立** randf，读表 rune_drop_chance
      └ _spawn_loot_drop(entry) × N      ← 统一落地（instantiate / setup / 撒点 ±14px / rare emit）
            └ LootDrop._draw()  "rune" 分支：紫罗兰光柱(28) + UISkin.rune_icon(item_id) 缩到 20×20
                  └ 玩家走近 ≤ PICKUP_RADIUS(24) 且 age ≥ LOOT_POP_DELAY(0.25)
                        └ PlayerController.pickup_loot(entry) → _pickup_rune(entry)
                              ├ 未解锁 → data.unlocked_runes.append(rid)   ← **永久**，分解/死亡不回收
                              └ 已解锁 → materials += rune_duplicate_material_amount(item_level)
                              └ 结果写回 entry：rune_new / material_amount
                        └ EventBus.loot_picked_up.emit(payload)   ← 与上面**同一个 Dictionary 引用**
                              └ PickupToastHUD.spawn()  "rune" 分支读 rune_new 组文案
```

**存档持久化**：写入的是 `SaveManager.current_data.unlocked_runes`，与 `obtain_unique()` 同路径 ——
由关卡结束时 `level_scene.gd:1703` 的 `SaveManager.save_to_slot()` 落盘，**无需额外调用**。

---

## 3. 三个已拍板的设计口径

### 3.1 三档全接（读表，不写死）
`rune_drop_chance`：**普通 0.02 / 精英 0.08 / BOSS 0.25**（深渊表 `abyss_loot_tables.json` 另为 0.05 / 0.30，随表读）。
符文是**第二次独立 roll** —— 命中**不会**挤掉金币/材料/装备那一次判定，两者可同时出现（「双响」）。
> ⚠️ 旧实现的 `RUNE_DROP_CHANCE := {"elite": 0.08, "boss": 0.25}` 已删除：它收 `tier: String`，
> 而调用侧只有 `MonsterData.Tier`（int）⇒ 即使接上也会恒取 0（见铁律 ㊽）。

### 3.2 拾取端判定「首次解锁 / 重复转魔石」
**roll 端不做任何过滤**（重复符文照常掉出）。理由：
- 忠于策划 §11.4「首次获得即永久解锁，之后重复掉落自动转化为魔石（避免垃圾堆积）」；
- 符文桶**永远有效** —— 24 个全解锁后仍持续产出魔石，不会退化成空桶（若在 roll 端过滤未解锁，后期会变成「掉空」）。

**转化量口径 = 与材料掉落完全一致**（`1 + (L-1)/5`，至少 1）⇒ 一颗重复符文 ≈ 一次材料掉落。
不另立一套数值，避免两处常量各自漂移（铁律 ㊺）。实现为 `LootRoller.rune_duplicate_material_amount(level)`。

### 3.3 地面用真图标（20px）
`UISkin.rune_icon(item_id)` 就是图鉴那张 `rune_icon_*_48.png`，缩到 **20px** 世界尺寸
（装备方块是 12px，金/材料 8px ⇒ 20 是同一视觉量级的上限；再大会盖住光柱、密集掉落时糊成一团）。
缺档时兜底成紫方块（`UISkin` 缺档静默回 null，不兜底就只剩一根光柱）。

---

## 4. 验收

| 项 | 结果 |
|---|---|
| 全量回归 `run_regression.py` | **77 脚本全绿 / 189.9s / exit 0** |
| `verify_loot_tables` F 段（2-V12） | 三表逐位 `0.02/0.08/0.25` + 全表 `[0,1]` + `validate()` 通过 |
| `verify_loot` H 段 | 4000 次/档实测命中率 **0.021 / 0.079 / 0.246**（期望 0.02/0.08/0.25）；条目字段合法；四象限独立性 |
| `verify_loot` I 段 | 首获写入 1 枚 / 不产魔石；重复不重写 + 转魔石 ×2；载荷写回两态；提示条消费 rune |
| `verify_loot` F 段实测 | BOSS 秒杀后地面 **主掉落 2 件 + 符文 1 枚**，走近拾取 → `[Loot] 解锁符文 rune_swift（图鉴 1 枚）` |
| 掉落预览抓图 | `game/build/loot_preview.png` + `loot_preview_runes_4x.png`（4× 最近邻放大逐像素目视） |
| 策划侧 | `02-check_affix_pool.py` 14/0 ｜ `07-check_dev_tasks.py --repo` 212/0 |

---

## 5. 附帶修復：掉落预览工具「拍不到东西」

`tools/loot_preview.tscn` 原本把 **10 个掉落物全摆在 `y = -80`**，而相机 `zoom = 2.5` + 视口 640×360
⇒ **可见世界范围只有 256×144（`y ∈ [-72, 72]`）**，那一排从头顶出画。
它被当成「掉落视觉验收依据」沿用了好几批 —— 因为 PNG 有产出、`err=0`、没人**数过图里有几个目标**。

本批重排为两行（都在可见范围内）：装备/金币/魔石行 `y = 0`（x 从 -117 到 117，步长 26），
符文行 `y = 50`。**改 zoom 时必须重算可见世界矩形再摆位**（见铁律 ㊾）。

---

## 6. 遗留（**不在本批范围**，但已定位）

| 项 | 说明 | 归属 |
|---|---|---|
| `material_sub_weights` / `item_level_spread` | JSON 有、`LootTable` **没有字段**、`ConfigLoader` **没读** ⇒ 两个死字段 | `2-D6` 剩余部分 |
| `item_level_spread` 与实现矛盾 | 代码 `_roll_item_level()` 用硬编码 `ITEM_LEVEL_JITTER = 2`（±2）给**所有档位**；而 JSON 写 BOSS 是 `min_mod 3 / mode_mod 5 / max_mod 8` ⇒ BOSS 本应掉 iLvl+5 左右 | `2-L13` / `2-V13` |
| 深渊表的 `rune_drop_chance`（0.05/0.30）**当前不会被消费** | `roll_rune_drop` 与 `roll_loot` 一样只走 `ConfigLoader.LOOT_TABLE_BY_TIER`（按 `MonsterData.Tier`），深渊表要经 `LevelData.loot_table_id` 才用得上（只有 `roll_guaranteed_equipment` 支持） | 待裁定 |
| 符文图鉴**不会在局内实时刷新** | 图鉴在据点，`hub.gd` 每次进入重新 `bind(data.unlocked_runes)` ⇒ 回据点即更新，无需信号 | 无（设计如此） |
