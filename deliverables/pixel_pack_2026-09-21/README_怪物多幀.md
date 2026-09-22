# 七傳說 · 怪物多幀像素素材包（2026-09-22）

嚴謹 2D 像素風（DNF 暗黑地下城），純單機 Godot 4 專用。把 16 隻怪從「單張靜態立繪」升級為
**idle / walk / attack / hurt / die × 四方向** 的多幀動畫，**不改遊戲邏輯**即可生效。

## 一、內容

| 項 | 值 |
|---|---|
| 怪物數 | 16（含 2 BOSS） |
| 每怪幀數 | idle 4 / walk 4 / attack 4 / hurt 3 / die 6 = 21 唯一幀 × 4 方向 = **84 幀** |
| 總幀數 | **1344 PNG**（`creatures/`） |
| 方向 | s / e / w / n（怪物側只產四向，無對角） |
| 畫布 | 小怪 128×128；BOSS（boss_bone_tyrant / boss_ember_lord）256×256 |
| 播放 | fps 12；腳底中心錨定；最近鄰（Nearest），無濾波 |
| 檔名 | `char_<id>_<action>_<dir>_<NN>.png`（NN 從 01 起） |

16 怪 id：spider_cave、bat_swarm、slime_acid、skeleton_warrior、mushroom_spore、warg_dark、
imp_hellfire、golem_ember、brute_butcher、frozen_husk、pyromancer_cultist、hound_ash、
wraith_frost、ice_wraith、boss_bone_tyrant、boss_ember_lord。

## 二、怎麼接進遊戲（已完成，此處為遷移說明）

整個 `creatures/<id>/` 目錄放到工程的 **`game/assets/pack/creatures/<id>/`**。
運行時解析優先鏈為：

```
① user://content/characters  →  ①·五 res://assets/pack/creatures/<id>  →  ② bundled 單張  →  ③ dnf/normalized 多幀  →  占位
```

本包命中第 ①·五級（`source=pack`），**優先於**單張立繪，無需改任何 `.gd`。
放入後執行一次 `godot --headless --import --path "D:/七傳說/game"` 生成 `.import`（本工程的
`.gitignore` 要求 `.import` 一併入庫）。

第 ② 級單張（`assets/sprites/enemies/`）與第 ③ 級 `dnf/normalized` 多幀均**保留、未刪除**，僅被遮蔽。

## 三、運動分型

- `slime`（slime_acid）：squash & stretch 擠壓拉伸。
- `float`（bat_swarm、wraith_frost、ice_wraith）：上下浮動，無步態。
- `biped`（其餘 13，含 2 BOSS）：步態 bob + 重心起伏。
- 方向：s 為形變正面，e / n 複製正面，w 為水平鏡像。
- hurt：朝白 lerp 閃白（3 幀）；die：壓扁 + 淡出（6 幀，死亡時由鬼影邏輯脫離本體播放）。

以上輪 16 張自有像素立繪為唯一基準，**程序化形變**（NEAREST 縮放 / 整數像素平移 / 鏡像 / 閃白 /
壓扁），保證跨幀造型、錨點、配色 100% 同源，不抖動。非 AI 逐幀。

## 四、目錄

```
creatures/                 16 個 <id> 目錄，共 1344 PNG（遊戲素材本體）
previews/
  creatures_anim_overview.png   16 行 × 21 幀（s 向）靜態總覽
  anim_walk_slime.gif 等 6 個    walk / float / combat 動圖預覽
creature_anim_gen.py       生成腳本（全量；`sheet` 出聯繫表）
anim_preview.py            生成 GIF + 總覽
```

## 五、復現 / 微調

```powershell
python creature_anim_gen.py            # 以 game/assets/sprites/enemies 立繪為基準全量重生成
python creature_anim_gen.py sheet spider_cave   # 只出某隻的聯繫表
godot --headless --import --path "D:/七傳說/game"
```

改動作節奏 / 幅度：編輯 `creature_anim_gen.py` 的 `frames_for()`（分型常量 `SLIME` / `FLOAT`、
`ACTIONS` / `DIRS`），重跑後重新 import。

## 六、驗證

- 臨時場景實測 16 怪全部 `source=pack`，5 動作 × 4 方向幀數 4/4/4/3/6 全對。
- `verify_anim` 0 項失敗（E/F 段已同步為 pack 多幀契約）。
- **全量回歸 55 腳本 + self_check（111 項）全部全綠（85.1s，2026-09-22）**。

## 七、已知邊界

- 目前為四方向（s 正面形變、e/n 正面、w 鏡像），**無真側身 / 真背面、無對角 8 向**（怪物側代碼不消费 8 向）。
- 為程序化微動，非像素畫師逐幀肢體動畫；要更精細的逐幀肢體需手繪或骨骼方案。
- 法師 / 弓手等其他職業、更多怪物與 BOSS、其餘裝備部位資料條目為後續待辦。

> 清單中另 5 類（地磚 3 套、技能圖標、UI 皮膚、裝備圖標、特效）經反向對帳**均已存在且合格**，
> 本輪無需補；詳見 `game/assets/PACK_OVERVIEW.md` 第十一章。
