# `game/tools/` 殘骸清理報告（2026-09-28）

> **先講結論**：66 個「零引用」裡，**只有 12 個值得動**。
> 第一級 6 個 stem（16 檔）已隔離；第二級 6 個待柳絮確認；第三級 54 個是**手動執行工具，一律保留**。

## 一、判定方法（這一輪才修對，前兩輪都是錯的）

| 坑 | 現象 | 修正 |
|---|---|---|
| **glob 動態發現** | `run_regression.py::discover_scripts` 用 `glob("verify_*.tscn")` 找腳本 ⇒ 檔名 grep 永遠是「零引用」，但**它們全是活的** | 用 `fnmatch` 把每個 stem 去比對所有 glob 模式，命中即視為活 |
| **清單文件自我引用** | 我上輪寫的 `cleanup_oneoff_tools.py` 與 `素材開發/README.md` **把候選檔名列了出來** ⇒ 反而把它們「引用」活，第一級一度變成 **0 個**（假陰性） | 語料庫**排除清單文件本身** |

語料庫範圍：`game/scripts`、`game/data`、`game/scenes`、`game/tools`、`game/project.godot`、
`deliverables/gstack/素材開發`、`deliverables/gstack/策划案`（排除上述兩份清單文件）。

## 二、第三級 · 手動執行工具 —— **54 個，一律保留**

`*_preview`（34）、`capture_*`（12）、`probe_*`（4）、`tiles_credits/preview/diag/search/verify`、
`pack_ui_gen.py`、**`package_demo.py`**（官方打包腳本，誤判是最危險的）。

> 這些工具**本來就不該被任何程式引用** —— 它們是給人執行的（真渲染取證、預覽、探針）。
> 用「零引用」判死它們，等於把整套驗證工具砍掉。

## 三、第一級 · 除錯/臨時殘骸 —— **已隔離 16 檔**

| 隔離檔 | 說明 |
|---|---|
| `_diag_kb.gd` / `.tscn` / `.gd.uid` | 除錯探針（底線前綴＝臨時） |
| `debug_screenshot.gd` / `.gd.uid` | 除錯截圖 |
| `debug_skill.gd` / `.tscn` / `.gd.uid` | 除錯技能 |
| `diag_aoe.gd` / `.tscn` / `.gd.uid` | 除錯 AoE |
| `diag_player_children.gd` / `.tscn` / `.gd.uid` | 除錯玩家子節點 |
| `sample_pixels.gd` / `.gd.uid` | 一次性取樣 |

- 落點：`deliverables/_quarantine_2026-09-24/game__tools__oneoff/`（附 `_READ_ME.txt`）
- 另清：`game/tools/__pycache__/`
- **回復方式**：把檔案搬回 `game/tools/` 即可
- **不移除 `.tscn.uid`**：這幾個檔本來就沒有

**驗證**：`parse_all` 由 226 → **220 個 `.gd` 全部可解析**；全套回歸 65 腳本照跑，結果與基線一致。

## 四、第二級 · 一次性工具 —— **6 個，待確認**

| 工具 | 我的判斷 | 建議 |
|---|---|---|
| `icons_quantize.py` | 圖標量化，是**像素圖標產線的前身**（功能已被本輪的「索引畫布」法取代，但可能還有參考價值） | **保留**（便宜，且是產線歷史） |
| `gen_ui_theme.gd/.tscn` | UI 主題生成器 | 可隔離（主題已成型） |
| `tiles_assemble_dcss.py` | 從 **DCSS**（Dungeon Crawl Stone Soup）素材組裝 tileset，一次性匯入腳本 | 可隔離 |
| `tiles_audit.py` | tileset 稽核；`tiles_verify` / `tiles_diag` 仍在第三級**保留**，功能可能重疊 | 可隔離（重疊） |
| `gif_slice.py` | GIF 切幀工具 | 可隔離 |
| `fix_equipment_icons.py` | 一次性修裝備圖標（那次修完了） | 可隔離 |

**我的建議**：只隔離 `fix_equipment_icons.py`、`gen_ui_theme.*`、`gif_slice.py`、`tiles_assemble_dcss.py`、`tiles_audit.py`（5 個），
保留 `icons_quantize.py`。但這需要你確認，因為我無法證明它們「絕不會再用」。
