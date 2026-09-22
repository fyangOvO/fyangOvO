# -*- coding: utf-8 -*-
"""角色/怪物素材「摊平入 committed 根」——把包内多目录帧集变成引擎可解析的一层。

为什么需要它
------------
`assets/characters/` 里包的多帧图是**按「动作_方向」分子目录**存放的
（`walk_n/` `attack_se/` …，每个目录里混着 warrior / mage / archer 三职业）。
而引擎的解析器 `EnemyBase.dnf_load_dir()` **只列一层目录**（`DirAccess.get_next()`
不递归），且靠**文件名** `char_<who>_<action>_<dir>_<NN>.png` 反推动作/方向。
所以「一个 who 的帧」必须落在**同一层目录**里。

本脚本把某个职业的 71 档摊平到 `assets/pack/creatures/<id>/`，并把
`char_<class>_` 前缀改成 `char_<id>_`（who 段 = 引擎里的 id，避免解析器
「目录名 ≠ 文件名 who」告警，也和使用者覆盖目录名 `user://content/characters/<id>/` 对齐）。

为什么不放 `assets/dnf/`：那是 gitignored（个人素材物理隔离）。本根是 **committed** 的。

用法
----
    python game/tools/pixel_pipeline/stage_creatures.py --class warrior --id player
    python game/tools/pixel_pipeline/stage_creatures.py --class warrior --id player --dry-run
"""
from __future__ import annotations

import argparse
import os
import shutil
import glob

GAME_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_ROOT = os.path.join(GAME_DIR, "assets", "characters")
DST_ROOT = os.path.join(GAME_DIR, "assets", "pack", "creatures")


def stage(cls: str, who: str, dry: bool) -> int:
    src_glob = os.path.join(SRC_ROOT, "**", "char_%s_*.png" % cls)
    files = sorted(glob.glob(src_glob, recursive=True))
    if not files:
        print("!! 源目录找不到 char_%s_*.png（%s）" % (cls, SRC_ROOT))
        return 2
    dst_dir = os.path.join(DST_ROOT, who)
    if not dry:
        os.makedirs(dst_dir, exist_ok=True)
    prefix = "char_%s_" % cls
    new_prefix = "char_%s_" % who
    n = 0
    for f in files:
        base = os.path.basename(f)
        if not base.startswith(prefix):
            continue
        out = os.path.join(dst_dir, new_prefix + base[len(prefix):])
        if not dry:
            shutil.copy2(f, out)
        n += 1
    print("%s %d 档：%s -> %s（前缀 %s -> %s）"
          % ("[DRY]" if dry else "[OK] ", n, SRC_ROOT, dst_dir, prefix, new_prefix))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--class", dest="cls", required=True, help="源职业名（warrior/mage/archer）")
    ap.add_argument("--id", required=True, help="目标 who/id（引擎解析用的目录名）")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    return stage(a.cls, a.id, a.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
