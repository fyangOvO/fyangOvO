# -*- coding: utf-8 -*-
"""七傳說 · 素材包歸位匯入（純整理，不改遊戲邏輯）

把 `deliverables/七傳說_像素素材包_YYYY-MM-DD.zip` 內的素材，按工程既有目錄約定
歸位到 `game/assets/` 之下；管線腳本與包 README 歸到 `game/tools/pixel_pipeline/`。

對應關係（zip 頂層目錄 → 目的）
--------------------------------
    characters/  -> assets/characters/      三職業 8 方向 walk/attack + hurt/death(南)
    monsters/    -> assets/monsters/        4 小怪 + BOSS 惡魔領主
    weapons/     -> assets/weapons/         主手 6 + 副手 4
    armor/       -> assets/armor/           頭/胸/手/鞋/項鍊/戒指
    fx/          -> assets/fx/              （併入既有目錄；檔名不衝突）
    anim/        -> assets/anim/            4 技能序列幀 + 預覽 gif
    backgrounds/ -> assets/backgrounds/     森林/寒霜/火山/主選單
    ui/pixel/    -> assets/ui/pixel/        面板/按鈕/血藍條/槽/稀有度
    ui/skill_icons/ -> assets/ui/skill_icons/
    previews/ + 根目錄 3 張預覽 PNG -> assets/previews/
    根目錄 *.py + README.md -> tools/pixel_pipeline/
    PACK_OVERVIEW.png       -> assets/previews/PACK_OVERVIEW.png

安全約定
--------
· **預設不覆蓋**既有檔案；衝突者列為 CONFLICT 並跳過，需 `--force` 才覆蓋。
· 只寫入 `assets/` 與 `tools/pixel_pipeline/`，不觸碰任何 `.gd` / `.tscn` / `.json`。
· 不刪除任何既有檔案。

用法
----
    python game/tools/pixel_pipeline/import_pack.py                 # 乾跑（只報告）
    python game/tools/pixel_pipeline/import_pack.py --apply         # 實際歸位
    python game/tools/pixel_pipeline/import_pack.py --apply --force # 覆蓋既有同名檔
"""
from __future__ import annotations

import argparse
import os
import struct
import sys
import zipfile

GAME_DIR = r"D:\七傳說\game"
ASSETS_DIR = os.path.join(GAME_DIR, "assets")
TOOLS_DIR = os.path.join(GAME_DIR, "tools", "pixel_pipeline")
DEFAULT_ZIP = r"D:\七傳說\deliverables\七傳說_像素素材包_2026-09-21.zip"

# zip 頂層目錄 -> assets/ 下的相對路徑
DIR_MAP = {
    "characters": "characters",
    "monsters": "monsters",
    "weapons": "weapons",
    "armor": "armor",
    "fx": "fx",
    "anim": "anim",
    "backgrounds": "backgrounds",
    "ui": "ui",
    "previews": "previews",
}
# 根目錄預覽圖 -> assets/previews/
ROOT_IMG_TO_PREVIEWS = {
    "PACK_OVERVIEW.png", "scene_preview_640x360.png", "scene_preview_2x.png",
}


def png_size(data: bytes):
    """從 PNG IHDR 讀 (w, h)，失敗回 (0, 0)。"""
    if len(data) >= 24 and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        w, h = struct.unpack(">II", data[16:24])
        return w, h
    return 0, 0


def dest_for(name: str):
    """回傳 (dest_abs, category)。category 用於彙總。"""
    if "/" not in name:
        if name in ROOT_IMG_TO_PREVIEWS:
            return os.path.join(ASSETS_DIR, "previews", name), "previews"
        if name.lower().endswith(".py") or name == "README.md":
            return os.path.join(TOOLS_DIR, name), "pipeline"
        return None, None
    top = name.split("/", 1)[0]
    if top in DIR_MAP:
        rel = name
        # zip 內已是 <top>/... ，直接映射到 assets/<DIR_MAP[top]>/...
        tail = name.split("/", 1)[1]
        return os.path.join(ASSETS_DIR, DIR_MAP[top], *tail.split("/")), DIR_MAP[top]
    return None, None


def main() -> int:
    ap = argparse.ArgumentParser(description="七傳說素材包歸位匯入")
    ap.add_argument("zip", nargs="?", default=DEFAULT_ZIP, help="素材包 zip 路徑")
    ap.add_argument("--apply", action="store_true", help="實際寫入（預設為乾跑）")
    ap.add_argument("--force", action="store_true", help="覆蓋既有同名檔")
    args = ap.parse_args()

    if not os.path.isfile(args.zip):
        print("!! 找不到素材包：%s" % args.zip)
        return 2

    z = zipfile.ZipFile(args.zip)
    plan, skipped_dirs, unknown = [], 0, []
    for info in z.infolist():
        name = info.filename
        if name.endswith("/"):
            skipped_dirs += 1
            continue
        dest, cat = dest_for(name)
        if dest is None:
            unknown.append(name)
            continue
        plan.append((name, dest, cat, info.file_size))

    # 衝突檢查
    conflicts = [p for p in plan if os.path.exists(p[1])]

    if args.apply:
        os.makedirs(TOOLS_DIR, exist_ok=True)
        written = 0
        for name, dest, cat, _size in plan:
            if os.path.exists(dest) and not args.force:
                continue
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(name) as src, open(dest, "wb") as out:
                out.write(src.read())
            written += 1
        print("已寫入 %d 個檔案（略過衝突 %d 個）" % (written, 0 if args.force else len(conflicts)))
    else:
        print("[乾跑] 計畫歸位 %d 個檔案；衝突 %d 個" % (len(plan), len(conflicts)))

    # 彙總
    by_cat = {}
    for name, dest, cat, size in plan:
        c = by_cat.setdefault(cat, {"n": 0, "bytes": 0, "dims": set()})
        c["n"] += 1
        c["bytes"] += size
        c["dims"].add(png_size(z.read(name)))

    print("\n類別彙總：")
    for cat in sorted(by_cat):
        c = by_cat[cat]
        dims = ", ".join("%dx%d" % d for d in sorted(c["dims"]) if d != (0, 0)) or "—"
        print("  %-12s %3d 檔  %8.1f KB  %s" % (cat, c["n"], c["bytes"] / 1024.0, dims))

    if conflicts:
        print("\n衝突（既有同名檔）：")
        for name, dest, cat, _ in conflicts:
            print("  %s  <-  %s" % (os.path.relpath(dest, GAME_DIR), name))
    if unknown:
        print("\n未配對（未歸位）：")
        for n in unknown:
            print("  %s" % n)

    # 目的目錄是否存在，供首次建立參考
    print("\n目的根目錄：%s" % ASSETS_DIR)
    return 0


if __name__ == "__main__":
    sys.exit(main())
