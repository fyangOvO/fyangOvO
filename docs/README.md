# 文檔總索引（docs/README.md）

> **v2.0 ｜ 2026-10-14**
>
> 本檔是「七傳說」**全庫文檔的唯一導航頁**。任何文檔若不在下表，即為**未登記**（請補登或歸檔）。
>
> **時效標記**：🟢 現行（可信）｜ 🟡 需對照代碼｜ 🔴 歷史（已凍結，勿據以行動）

---

## 一、該從哪裡開始讀？

| 你的角色 | 閱讀順序 |
|---|---|
| **接手開發的 AI** | `AGENTS.md` → `IRON-RULES.md`（鐵律區）→ `MEMORY.md`（遺留）→ 動手 |
| **新加入的人** | `AGENTS.md` → `game/README.md` → `Playground開發描述.md` |
| **策劃 / 數值** | `Playground開發描述.md` → `deliverables/gstack/策划案/README.md` → 對應的 `0N-*.md` |
| **美術 / 素材** | `game/CONTENT_GUIDE.md` → `deliverables/gstack/素材開發/README.md` |
| **想知道某個功能怎麼做的** | `game/README.md` 對應章節 → 該功能的 `verify_*.tscn`（**斷言即規格**） |

> 💡 **斷言即規格**：本專案最準的「功能規格書」其實是 `game/tools/verify_*.tscn` ——
> 它們是可執行、每次回歸都會被驗證的契約。文檔與斷言衝突時，**以斷言（＝代碼）為準**。

---

## 二、入口層

| 時效 | 文檔 | 路徑 | 用途 |
|---|---|---|---|
| 🟢 | **AI 接手入口** | [`../AGENTS.md`](../AGENTS.md) | **先讀這個**：現狀 / 命令 / 地圖 / 鐵律 / 工作流 / 遺留 |
| 🟢 | **文檔總索引** | 本檔 | 全庫文檔導航 |

## 三、工程層（`game/`）

| 時效 | 文檔 | 路徑 | 用途 |
|---|---|---|---|
| 🟢 | **工程說明書** | [`../game/README.md`](../game/README.md) | 概況 / 怎麼跑 / 目錄 / 核心約定 / 驗證方法 / **怎麼加內容（§八）** |
| 🟢 | 素材替換指南 | [`../game/CONTENT_GUIDE.md`](../game/CONTENT_GUIDE.md) | 不碰代碼換素材（使用者內容目錄 `content/`） |
| 🟡 | 像素管線工具 | [`../game/tools/pixel_pipeline/README.md`](../game/tools/pixel_pipeline/README.md) | 素材生成管線的內部說明 |

## 四、設計層

| 時效 | 文檔 | 路徑 | 用途 |
|---|---|---|---|
| 🟢 | **玩法設計總綱** | [`../Playground開發描述.md`](../Playground開發描述.md) | 對標爆款暗黑向：割草 / 打擊感 / Build 聚變 / 像素動效 |
| 🟢 | 策劃案總索引 | [`../deliverables/gstack/策划案/README.md`](../deliverables/gstack/策划案/README.md) | 01–07 七步策劃案的入口 |
| 🟢 | 01 技能體系 | `../deliverables/gstack/策划案/01-技能体系.md` | 技能 / 符文 / 分支（+ `01-*.json`） |
| 🟢 | 02 裝備屬性 | `../deliverables/gstack/策划案/02-装备属性.md` | 詞綴 / 詞綴池（+ `02-*.json`） |
| 🟢 | 03 裝備特色玩法 | `../deliverables/gstack/策划案/03-装备特色玩法.md` | 元素 / 套裝 / 傳奇 / 協同（+ `03-*.json`） |
| 🟡 | 04 數值與數據模型 | `../deliverables/gstack/策划案/04-数值与数据模型.md` | XP 曲線 / 經濟 / 預算 —— ⚠️ **仍持「上限 20」口徑**，見 `AGENTS.md` §6.1 #1 |
| 🟡 | 05 怪物關卡 BOSS | `../deliverables/gstack/策划案/05-怪物关卡BOSS.md` | 等級帶 / 關卡 / BOSS（+ `05-*.json`） |
| 🟢 | 06 特色玩法 | `../deliverables/gstack/策划案/06-特色玩法.md` | 深淵 / 高塔 / 特殊稀有度（+ `06-*.json`） |
| 🟢 | 07 開發總表 | `../deliverables/gstack/策划案/07-开发总表.md` | 180 工單總表（+ `07-dev-tasks.json`） |
| 🟢 | **7 個校驗器** | `../deliverables/gstack/策划案/0N-check_*.py` | 可執行的策劃契約，回歸時一併跑 |

## 五、素材層

| 時效 | 文檔 | 路徑 | 用途 |
|---|---|---|---|
| 🟢 | 素材清單 | [`../deliverables/gstack/素材開發/ASSET_MANIFEST.json`](../deliverables/gstack/素材開發/ASSET_MANIFEST.json) | v7：done 25 / BLOCKED 0 |
| 🟡 | 素材開發說明 | [`../deliverables/gstack/素材開發/README.md`](../deliverables/gstack/素材開發/README.md) | 生成腳本與管線 |
| 🔴 | 工具清理報告 | `../deliverables/gstack/素材開發/TOOLS_CLEANUP_REPORT.md` | 一次性清理的留痕 |

## 六、記憶層（`.workbuddy-ai/memory/`，**AI 專用**）

| 時效 | 文檔 | 路徑 | 用途 |
|---|---|---|---|
| 🟢 | **鐵律與坑分冊** | [`../.workbuddy-ai/memory/IRON-RULES.md`](../.workbuddy-ai/memory/IRON-RULES.md) | **60+ 條坑**（含踩坑現場與修法）—— 動代碼前必讀 |
| 🟢 | **專案長期記憶** | [`../.workbuddy-ai/memory/MEMORY.md`](../.workbuddy-ai/memory/MEMORY.md) | 當前位置 / 未結遺留 / 基線約定 / git 鐵律 / 環境速查 |
| 🟢 | 逐日工作誌 | `../.workbuddy-ai/memory/YYYY-MM-DD.md` | 每個批次的完整復盤（**append-only**） |
| 🔴 | HANDOFF-B5 / B5-4 | `../.workbuddy-ai/memory/HANDOFF-B5*.md` | B5 批次的交接單（歷史） |

## 七、歸檔區（`docs/archive/`，**已凍結**）

| 時效 | 文檔 | 說明 |
|---|---|---|
| 🔴 | `HANDOFF-C.md` | UI 視覺打磨復盤（2026-09-30） |
| 🔴 | `HANDOFF-D.md` | 符文圖標 v2 高精細重製（2026-09-30） |
| 🔴 | `HANDOFF-E.md` | 符文掉落接線 3 輪（2026-09-30） |

> 這些是**一次性交接單**：任務已完成，內容已被 `IRON-RULES.md` / `MEMORY.md` / 逐日誌吸收。
> 保留是為了可追溯「當時為什麼這樣做」，**不要據以行動**。

## 八、歷史產物（未歸檔，但已凍結）

| 時效 | 路徑 | 說明 |
|---|---|---|
| 🔴 | `../deliverables/*.md`（2026-09-21/22） | 素材缺口審計 / 換裝規格 / 代碼審查報告 —— **一次性分析，已執行完畢** |
| 🔴 | `../deliverables/gstack/上线前全检报告-2026-09-23.md` | 上線前全檢 —— ⚠️ 前提已變（2026-09-23 裁定**不上線**） |
| 🔴 | `../deliverables/gstack/*_shot/` | 各批次的真渲染截圖 —— ⚠️ **素材一改舊圖即失效**，只作歷史留痕 |

---

## 九、維護約定

1. **新增文檔必須登記到本表**，並標明時效。
2. **一次性交接單**完成後移入 `docs/archive/`（用 `mv`，不要 `rm`）。
3. **發現文檔與代碼不符** ⇒ **以代碼為準，回來改文檔**，並在 `IRON-RULES.md` 記一筆
   （本專案已發生過多次「記憶寫接入、代碼沒接」的漂移）。
4. 產物命名：`<場景類型>-<主題簡稱>-<YYYY-MM-DD>.md`，統一放 `deliverables/gstack/`。
