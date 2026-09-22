# -*- coding: utf-8 -*-
"""GIF 切幀工具（DNF 素材接入 P-B/P-C 用）。

⚠️⚠️ 已廢棄（DEPRECATED）—— 請改用 `game/tools/dnf_normalize.py` ⚠️⚠️
================================================================================
本腳本已被 `dnf_normalize.py`（GStack T2 產出）取代。**新素材請勿再用本腳本**。
保留原因：僅供歷史可追溯（早期鷹架），不得再作為產線入口。

已知兩項缺陷（實測於 2026-09-18，詳見
`deliverables/gstack/dnf-normalize-2026-09-18.log` 附錄 A）：

  1. **不做底色摳除（→ 白底原樣保留）**：
     本腳本完全沒有背景摳除。更關鍵的是，來源 GIF 的「透明索引」可能是**假的**
     —— 例如 pvz_zombies_0000.gif 宣告 transparency=0，但 palette[0]=(0,0,0) 黑，
     實際底色用的是 palette[1]=(255,255,255) 白，索引 0 全圖根本沒被用到。
     因此 Pillow 忠實地把索引 0 摳成透明（等於摳掉 0 個像素），白底原樣留下。
     → **就算本腳本正確 honor GIF 透明度，白底依然會在**，必須做「明確底色摳除」。

  2. **`alpha_composite` 累積造成幀間殘影（ghosting）**：
     Pillow 的 GIF `seek()` 本來就回傳「已依 disposal 合成好的整張畫布」；本腳本卻
     再把每幀 `alpha_composite` 疊到累積 canvas 上 → 後幀的透明區不會清除前幀內容，
     角色邊動邊拖影（實測 6 幀的透明區由 66.8% 漸進被填到 41.2%，末幀差 421 像素）。
     正解＝逐幀直接輸出 `img.convert("RGBA")`，不要自行累積。

`dnf_normalize.py` 已同時修掉上述兩點，並提供去底（邊界泛洪 + 抗鋸齒過渡）、
包圍盒並集裁切、按 tier 統一畫布、最近鄰縮放、dry-run 與自證統計。
================================================================================

用 Pillow 拆解 GIF 為 PNG 序列幀，輸出到 staging 目錄。
配合 dnf_asset_pipeline.py 完成重命名 + 寫清單。

用法
----
::

    python game/tools/gif_slice.py \\
        --input assets/dnf/raw/pvz_zombies/pvz_zombies_0000.gif \\
        --out-staging C:/temp/staging_pvz_01/ \\
        --label pvz_01

    # 批量：掃描 raw/ 下一個子目錄，拆解所有 GIF
    python game/tools/gif_slice.py --batch-raw

設計約束
--------
* **幀透明背景保留**：Pillow 的 GIF 解碼會把透明幀疊成 RGB（丟透明通道）。
  本腳本對每幀合成到第一幀上，再以原圖透明色為 key 重建 alpha。
* **拆分後尺寸不變**：保留原始像素大小（不做 nearest resize）。
* **冪等**：同一輸入已拆過則跳過（比對檔案大小 + 幀數）。
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path
from typing import Iterable, List

from PIL import Image

__version__ = "0.1.0-2026-09-18"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="gif_slice",
        description="GIF 切幀（PNG 序列）",
    )
    p.add_argument("--input", type=str, default=None,
                   help="單一 GIF 輸入路徑")
    p.add_argument("--out-staging", type=str, default=None,
                   help="staging 輸出目錄（dnf_asset_pipeline.py 會掃這裡）")
    p.add_argument("--label", type=str, default=None,
                   help="幀名前綴（例：pvz_01）")
    p.add_argument("--batch-raw", action="store_true",
                   help="掃描 assets/dnf/raw/ 下所有 GIF 並逐個拆解到 staging_dnf/<dir>/<label>/")
    p.add_argument("--raw-root", type=str, default="assets/dnf/raw",
                   help="batch 模式的 raw 根目錄（相對於專案根 D:/七傳說）")
    p.add_argument("--staging-root", type=str, default="D:/_staging_dnf",
                   help="batch 模式的 staging 根目錄")
    p.add_argument("--project-root", type=str, default="D:/七傳說",
                   help="專案根目錄")
    p.add_argument("--max-frames", type=int, default=12,
                   help="單個 GIF 最多拆多少幀（DNF 風格多為 4-12 幀）")
    p.add_argument("--dry-run", action="store_true",
                   help="只列印將要做的操作")
    p.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return p.parse_args(argv)


def slice_one(gif_path: Path, out_dir: Path, label: str,
              max_frames: int = 12, dry_run: bool = False) -> int:
    """拆單一 GIF；回傳實際輸出幀數。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    if not gif_path.is_file():
        print(f"!! 找不到 GIF：{gif_path}", file=sys.stderr)
        return 0

    img = Image.open(gif_path)
    n_total = getattr(img, "n_frames", 1)
    n_use = min(n_total, max_frames)
    print(f"  [{label}] {gif_path.name}: {n_total} 幀（用前 {n_use}）")

    if dry_run:
        return n_use

    extracted = 0
    # GIF 解碼：把每幀 paste 回原 canvas（RGBA），保留 alpha 通道
    canvas_rgba = None
    try:
        for frame_idx in range(n_use):
            img.seek(frame_idx)
            # duration_ms = img.info.get("duration", 100)
            frame = img.convert("RGBA")
            if canvas_rgba is None:
                canvas_rgba = frame.copy()
            else:
                # GIF 的「replace」模式：先清 canvas，再 paste
                # 但大多數 DNF 動圖是「combine」，直接 paste 即可
                canvas_rgba.alpha_composite(frame)

            # 寫出單幀
            out_path = out_dir / f"{frame_idx + 1:04d}.png"
            canvas_rgba.save(out_path, "PNG")
            extracted += 1
    except EOFError:
        # GIF 幀讀取完
        pass
    except Exception as e:
        print(f"  ! 拆幀錯誤：{e}", file=sys.stderr)
        return extracted

    return extracted


def batch_slice(raw_root: Path, staging_root: Path,
                max_frames: int = 12, dry_run: bool = False,
                per_dir_limit: int | None = None) -> dict[str, int]:
    """掃 raw_root 下所有子目錄，逐個拆 GIF。回傳每子目錄的拆幀總數。"""
    if not raw_root.is_dir():
        print(f"!! raw 目錄不存在：{raw_root}", file=sys.stderr)
        return {}

    results = {}
    subdirs = sorted(p for p in raw_root.iterdir() if p.is_dir())
    for sub in subdirs:
        # 每子目錄建同名 staging
        out_dir = staging_root / sub.name
        # 取所有 GIF
        gifs = sorted(sub.glob("*.gif"))
        if not gifs:
            continue
        print(f"\n=== {sub.name}/ ({len(gifs)} GIFs) ===")
        total = 0
        limit = per_dir_limit if per_dir_limit is not None else len(gifs)
        for i, gif in enumerate(gifs[:limit]):
            label = f"{sub.name}_{i:03d}"
            n = slice_one(gif, out_dir / label, label, max_frames, dry_run)
            total += n
        results[sub.name] = total
    return results


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.batch_raw:
        raw_root = Path(args.project_root) / args.raw_root
        staging_root = Path(args.staging_root)
        results = batch_slice(raw_root, staging_root, args.max_frames, args.dry_run)
        print("\n=== 拆幀結果彙總 ===")
        total_all = 0
        for name, n in sorted(results.items(), key=lambda kv: -kv[1]):
            print(f"  {name:<32} {n:>4} 幀")
            total_all += n
        print(f"  {'─' * 40}")
        print(f"  {'總計':<32} {total_all:>4} 幀")
        return 0

    if not args.input or not args.out_staging or not args.label:
        print("!! 單一模式需要 --input / --out-staging / --label", file=sys.stderr)
        return 1

    gif_path = Path(args.input)
    out_dir = Path(args.out_staging) / args.label
    n = slice_one(gif_path, out_dir, args.label, args.max_frames, args.dry_run)
    print(f"✓ {args.label}: {n} 幀寫入 {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())