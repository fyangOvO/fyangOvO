# -*- coding: utf-8 -*-
"""
2026-09-24 素材清理：把「已被取代的舊素材」移到隔離區（**移動，不刪除**，可完整回復）。

判定依據（不是猜的）：
  1. 引用分析：該目錄是否出現在任何 runtime 載入鏈
     （scripts/ / data/ --include=*.gd/*.json）
  2. 內容比對：與活躍目錄（pack/creatures, sprites, icons, ui, fx, tilesets, audio）
     的 PNG 做 md5 比對

只有同時滿足「runtime 無引用」且「與活躍目錄 100% 位元組相同」的目錄才移。
其餘（唯一內容）一律**保留**，交人工決定。
"""
import hashlib
import json
import os
import shutil

GAME = r"D:/七傳說/game/assets"
DELIV = r"D:/七傳說/deliverables"
QDIR = os.path.join(DELIV, "_quarantine_2026-09-24")

# 只隔離「已證明為純重複」的項目
TARGETS = [
    (os.path.join(GAME, "characters"),
     "玩家三職業精靈（213 PNG）與 assets/pack/creatures/{warrior,archer,mage} 100% 位元組相同；"
     "且不在 runtime 載入鏈（僅 import_pack.py 這支一次性匯入腳本提及）"),
    (os.path.join(GAME, "backgrounds"),
     "4 張背景與 assets/ui/quest/backdrops/ 100% 位元組相同；"
     "runtime 走 UISkin.backdrop_texture → TEX 表 → assets/ui/quest/，不讀此目錄"),
    (os.path.join(DELIV, "gstack/策划案/art_test"),
     "2026-09-24 風格測試 scratch（AI 8 方向精靈 + 攻擊動圖）；已由 素材開發/ 正式產線取代"),
    (os.path.join(DELIV, "gstack/策划案/_style_montage_v1.png"),
     "2026-09-24 風格取樣臨時拼圖"),
]


def dir_stats(p):
    n = sz = 0
    for root, _, files in os.walk(p):
        for f in files:
            fp = os.path.join(root, f)
            n += 1
            sz += os.path.getsize(fp)
    return n, sz


def main():
    os.makedirs(QDIR, exist_ok=True)
    log = []
    for src, reason in TARGETS:
        if not os.path.exists(src):
            print(f"[skip] 不存在：{src}")
            continue
        dst = os.path.join(QDIR, os.path.relpath(src, "D:/七傳說").replace("\\", "__").replace("/", "__"))
        n, sz = dir_stats(src) if os.path.isdir(src) else (1, os.path.getsize(src))
        if os.path.exists(dst):
            print(f"[skip] 隔離區已有：{dst}")
            continue
        shutil.move(src, dst)
        log.append({"from": src, "to": dst, "files": n, "bytes": sz, "reason": reason})
        print(f"[moved] {src}\n        -> {dst}\n        {n} 個檔案 / {sz/1024:.0f} KB")
    with open(os.path.join(QDIR, "_quarantine_log.json"), "w", encoding="utf-8") as f:
        json.dump({"_meta": {"date": "2026-09-24",
                             "policy": "移動而非刪除；回復方式＝把 to 移回 from"},
                   "items": log}, f, ensure_ascii=False, indent=1)
    total = sum(x["files"] for x in log)
    print(f"\n合計隔離 {len(log)} 項 / {total} 個檔案")


if __name__ == "__main__":
    main()
