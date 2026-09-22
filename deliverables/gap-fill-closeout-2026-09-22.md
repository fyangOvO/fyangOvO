# 缺口補齊輪 · 驗收與收口（2026-09-22）

> 對象：`deliverables/pixel_pack_2026-09-21/` 缺口補齊輪（16 怪物單張 + 3 稀有度框 + 2 技能圖標 + 6 裝備圖標 + 3 套裝徽章 + 代碼接線）。
> 主理人游承峰執行驗收、兩項裁定落地與全量回歸收口。

## 一、驗收結果（逐條對帳）

| 驗收項 | 預期 | 實測 | 判定 |
|---|---|---|---|
| 怪物 bundled 單張 | 14 小怪 128² + 2 BOSS 256² = 16 | `assets/sprites/enemies/` 16 `.png` 全在 | ✅ |
| `.import` 元數據 | 全數生成（`.gitignore` 要求入庫） | 抽查 4 檔全 OK | ✅ |
| 稀有度框 3 | `slot_{mythic,set,hidden}_48.png` | `ui_skin.gd` TEX +3、`RARITY_SLOT` 5/6/7 指向專屬框 | ✅ |
| 技能圖標 2 | lightning_chain / poison_cloud | `level_scene.gd::SKILL_ICON` 已補兩條 | ✅ |
| 裝備圖標 6 | legs / ring_b / hammer / orb / quiver / offblade | `armor/jewelry/set_pieces/weapons.json` 已改指；legs 5 件、ring_b 3 件不再借圖 | ✅ |
| 套裝徽章 3 | `set_emblem_*.png` | `sprites/items/` 3 檔在位（尚無 UI 消費） | ✅ |
| 數據層 `res://` 引用 | 全部可解析 | 87 條，僅 6 條 `scene_path` 懸空（本輪處理） | ✅ |
| `verify_ui_assets.gd` 斷言 | 同步更新 | `EXPECT_TEX` +5、唯一圖標 12→15、腿甲「0 借胸甲」 | ✅ |
| pixel_pack 歸檔 | 副本 + 可重現腳本 | enemies 16 / icons 6 / items 3 / ui 26 / previews 9 + 13 支腳本 | ✅ |

## 二、裁定的兩項落地

### 1. `verify_anim` E 段回歸契約收口（B 方案）

**紅因**：16 隻怪補上第②級 bundled 單張後，四級優先鏈「先命中先返回」使活體敵人取得單幀集
（`clips = {idle: {s: [tex]}}`、1 幀），E 段原斷言 DNF 多幀（idle 13 / walk 16 / attack 10）隨之失效 → `FAIL=3`。

**處理**（`tools/verify_anim.gd`）：

| 改動 | 內容 |
|---|---|
| 幀數斷言 | 改鎖 bundled 契約：三處 `_clip.size() == 1`；idle 保留 `_clip_exact`，walk/attack 因沿 `ANIM_FALLBACK` 回退故 `exact=false`（斷言不含 exact） |
| 新增哨兵 1 | `resolve_character_set("pyromancer_cultist")` → `source == "bundled"` |
| 新增哨兵 2 | `dnf_load_set("pyromancer_cultist")` 的 `idle/s` 仍為 **13 幀**（僅被遮蔽、**未刪除**）——防止日後誤刪 DNF 素材無人發現 |
| tier③ 多幀覆蓋 | 由 B 段保留（`dnf_load_set` 直測 5 隻 × 動作 × 四方向），**未減損** |
| 狀態機斷言 | IDLE / WALK / ATTACK / HURT 切換與「受擊期間攻擊不搶播」全數未動 |

> ⚠️ **方案修正**：原提的 `resolve_character_set(id, "")` **不能**繞過第②級 —— 空字串會被還原成
> `BUNDLED_SPRITE_DIR/<id>.png`（`enemy_base.gd:443-445`），仍命中 bundled。直測 tier③ 須用 `dnf_load_set(id)`。

**實測**：`[OK] 第②級內建單張命中（source=bundled）` / `[OK] 第③級 DNF 多幀仍在（idle s = 13 幀）` / `[OK] idle·walk·ATTACK 均為 bundled 單幀（1）` → **0 項失敗**。

### 2. 刪除 6 條 `scene_path` 懸空欄位

`data/levels/chapter1.json` 移除 `ch1_l01..l06` 的 `scene_path`（指向不存在的 `.tscn`）。

- **保留**：`LevelData.scene_path` 欄位、`scene_manager.gd::change_to_level()` 的三級解析邏輯 —— 將來某關要做專屬場景時直接填即可。
- **等價性**：刪前「有值但檔案不存在 ⇒ 回退通用容器」，刪後「為空 ⇒ 命名約定兜底後同樣回退」；行為一致，僅少一行診斷打印。
- **驗證**：JSON 合法、6 關全數無殘留、`scene_path` 全項目引用（僅 `level_data.gd` / `config_loader.gd` / `scene_manager.gd`）皆已確認無斷言依賴。

## 三、全量回歸

```
python game/tools/run_regression.py
→ 耗時 111.4s，55 個腳本，全部全綠（exit=0）
  （改動前：verify_anim FAIL=3；其餘 54 支已先全綠）
```

## 四、文檔同步

- `assets/PACK_OVERVIEW.md` §10.7 **訂正**：`scene_path` **並非死字段**（`scene_manager.gd:124` 確實會讀），原判斷為「從未讀取」有誤；已補記刪除處置。
- `assets/PACK_OVERVIEW.md` §10.9 **新增**：本輪回歸契約收口與 `resolve_character_set(id,"")` 陷阱實作註記。

## 五、待辦（未拍板）

| # | 項 | 歸屬 |
|---|---|---|
| 1 | `equip_orb / quiver / offblade / hammer` **圖等數據**：法器、箭袋、副刃尚無裝備條目；錘已接圖但數值平衡未定 | 設計 / 設計師 |
| 2 | `game/README.md` 待辦 #1 已過時（寫「assets 全空、圖標徽記未產出」，實際已產出 12+6 圖標與 3 徽章）；改動涉及編號，須先全域 grep 引用 | 工程 |
| 3 | 怪物多幀 × 8 方向（walk/attack/受擊/死亡）擴充：沿用 `pixel_pipeline.py` + `sprite_sheet_cut.py`，可放 `dnf/normalized/<id>/` 或擴充 bundled 為多幀 | 美術 / 工程 |
