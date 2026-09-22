#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""裝備圖標接線工具（一次/可重複執行）。

問題
----
`data/equipment/*.json` 共 62 件裝備，`icon_path` 全部指向
`res://assets/sprites/items/*.png` —— **這些檔案不存在**（`game/assets/sprites/` 只有
`.gitkeep`，是留給玩家替換的空槽位）。於是 `ContentLoader.load_icon()` 永遠回傳 null
（`equip_panel.gd:119`），裝備欄卡片只有文字沒有圖標。

真實存在的 12 枚圖標躺在 `game/assets/icons/equipment/equip_*_48.png`（本輪素材包）。

本工具把每件裝備的 `icon_path` 改到**真實存在**的 `res://assets/icons/equipment/<icon>_48.png`，
映射口徑見下方兩張表（缺口以註釋標明）。

做法（為何不改寫整份 JSON）
--------------------------
直接 `json.dump` 會重排/重格式化整份資料檔，產生巨大的無意義 diff，也讓 review 失去焦點。
本工具只**逐行替換** `"icon_path": "..."` 的值，其餘位元組原樣保留 —— diff 只有 icon_path 一行。

用法
----
    python game/tools/fix_equipment_icons.py            # 執行（寫回）
    python game/tools/fix_equipment_icons.py --dry-run  # 只印出將要做的改動
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

GAME_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_GLOB = os.path.join(GAME_DIR, "data", "equipment", "*.json")
ICON_DIR = os.path.join(GAME_DIR, "assets", "icons", "equipment")
ICON_PREFIX = "res://assets/icons/equipment"

# ── 映射口徑 ────────────────────────────────────────────────────────────────
# 身體部位槽 → 圖標名（不含 _48 後綴）
SLOT_ICON = {
    "helm": "equip_helmet",
    "chest": "equip_chest",
    "gloves": "equip_gauntlet",
    "legs": "equip_chest",     # ⚠️ 缺口：素材未提供腿甲圖標，暫借胸甲
    "boots": "equip_boots",
    "amulet": "equip_amulet",
    "ring_a": "equip_ring",
    "ring_b": "equip_ring",
}

# 武器原型（weapon_archetype 欄位）→ 圖標名
ARCH_ICON = {
    "sword": "equip_sword",
    "axe": "equip_axe",
    "hammer": "equip_axe",     # ⚠️ 缺口：素材未提供戰鎚圖標，暫借戰斧
    "dagger": "equip_dagger",
    "staff": "equip_staff",
    "longbow": "equip_bow",
    "shield": "equip_shield",
}


def icon_for(item: dict) -> str:
    """回傳該裝備應指向的圖標名（含 `equip_` 前綴，不含 `_48.png`）。"""
    slot = str(item.get("slot", ""))
    if slot == "main_hand":
        return ARCH_ICON.get(str(item.get("weapon_archetype", "")), "equip_sword")
    if slot == "off_hand":
        return ARCH_ICON.get(str(item.get("weapon_archetype", "")), "equip_shield")
    return SLOT_ICON.get(slot, "equip_chest")


_ICON_RE = re.compile(r'("icon_path"\s*:\s*)"[^"]*"')


def process_file(path: str, dry: bool) -> int:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    items = json.loads(text)

    # 依序計算每件裝備的新路徑；順序 == 檔案中 icon_path 出現的順序
    new_paths = ["%s/%s_48.png" % (ICON_PREFIX, icon_for(it)) for it in items]

    # 逐一驗證目標圖標檔真實存在（缺檔就中止，不寫半套）
    missing = []
    for p in new_paths:
        rel = p.replace("res://", "")
        if not os.path.isfile(os.path.join(GAME_DIR, rel)):
            missing.append(p)
    if missing:
        print("[FAIL] %s：目標圖標不存在：%s" % (os.path.basename(path), sorted(set(missing))))
        return 1

    matches = list(_ICON_RE.finditer(text))
    if len(matches) != len(items):
        print("[FAIL] %s：icon_path 數量(%d) != 裝備數(%d)"
              % (os.path.basename(path), len(matches), len(items)))
        return 1

    # 由後往前替換，避免位移
    out = text
    changed = 0
    for m, newp in reversed(list(zip(matches, new_paths))):
        old_line = m.group(0)
        new_line = '%s"%s"' % (m.group(1), newp)
        if old_line != new_line:
            changed += 1
        out = out[:m.start()] + new_line + out[m.end():]

    print("  %-28s 裝備 %2d 件，改動 %2d 條" % (os.path.basename(path), len(items), changed))
    if not dry and changed:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(out)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    files = sorted(glob.glob(DATA_GLOB))
    if not files:
        print("[FAIL] 找不到 %s" % DATA_GLOB)
        return 1

    print("=== 裝備圖標接線%s ===" % ("（dry-run）" if args.dry_run else ""))
    rc = 0
    for f in files:
        rc |= process_file(f, args.dry_run)

    # 全域覆核：所有 icon_path 現在都必須指向存在的檔
    total = 0
    bad = 0
    for f in files:
        for it in json.load(open(f, encoding="utf-8")):
            total += 1
            p = str(it.get("icon_path", "")).replace("res://", "")
            if not os.path.isfile(os.path.join(GAME_DIR, p)):
                bad += 1
                print("[BAD] %s -> %s" % (it.get("id"), it.get("icon_path")))
    print("=== 覆核：%d/%d 件 icon_path 指向存在的圖標 ===" % (total - bad, total))
    return rc if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
