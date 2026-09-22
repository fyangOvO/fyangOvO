#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
package_demo.py — 七傳說 一鍵打包（清數據 → 刪舊包 → 導出 → 驗證 → 可選啟動）

用戶鐵律（柳絮 2026-09-22）：
    「以後每次打包都需要清除之前的數據資料」
因此本腳本 **預設** 會先清空 user:// 下的 saves\\ 與 content\\（存檔 + 用戶替換素材），
再刪除舊的 build\\七傳說.exe / *.pck，然後用 Godot CLI 重新導出 release。

用法（在工程根目錄，或用絕對路徑皆可）：
    python tools/package_demo.py              # 清數據 + 刪舊包 + 導出 + 驗證
    python tools/package_demo.py --backup     # 不刪：先把舊包/存檔移入 build/_prev/<時間戳>/
    python tools/package_demo.py --keep-data  # 保留存檔（僅刪舊包 + 導出）
    python tools/package_demo.py --run        # 導出後順便啟動遊戲
    python tools/package_demo.py --no-export  # 只清數據 + 刪舊包，不導出

可回滾（opt-in，預設仍為刪除）：
    --backup 會在清除前，把 build\\七傳說.exe / *.pck 與 user:// 的 saves\\ / content\\
    **移動**到 build\\_prev\\<YYYYMMDD-HHMMSS>\\（同碟 rename，瞬間完成），而非刪除。
    build\\ 已在 .gitignore 內，備份不會污染版本庫。

環境變數：
    GODOT_BIN   覆蓋 Godot 可執行檔路徑（預設見下方 DEFAULT_GODOT）

安全邊界（硬約束，絕不越界 —— 刪除僅限三類）：
    (1) user:// 下的 saves\\ 與 content\\（%APPDATA%\\Godot\\app_userdata\\七傳說\\ 及工程內鏡像）
    (2) build\\七傳說.exe
    (3) build\\*.pck
絕對不碰：*_preview.png、*.import、assets\\、deliverables\\、任何其它檔案。

為什麼用 .py 而不是 .ps1：本工程路徑含非 ASCII（七傳說），PowerShell 腳本在
不同代碼頁下容易把中文路徑編碼成亂碼；Python 走 Unicode API 穩定可靠。
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

# ── 讓 Windows 控制台也能正確輸出中文（避免 UnicodeEncodeError / 亂碼）──────
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
except Exception:
    pass

# ── 常數 ────────────────────────────────────────────────────────────────
PRODUCT = "七傳說"
PRESET = "Windows Desktop"
EXE_NAME = f"{PRODUCT}.exe"

# 腳本位在 <project>/tools/package_demo.py → 工程根 = 上一層
PROJECT_DIR = Path(__file__).resolve().parent.parent
BUILD_DIR = PROJECT_DIR / "build"
EXE_PATH = BUILD_DIR / EXE_NAME

DEFAULT_GODOT = (
    r"C:\Users\11265\AppData\Local\Microsoft\WinGet\Packages"
    r"\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
    r"\Godot_v4.7.2-stable_win64_console.exe"
)
GODOT_BIN = os.environ.get("GODOT_BIN", DEFAULT_GODOT)

# user:// 的兩個可能落腳點：標準 %APPDATA%，以及 Godot 以相對路徑解析時
# 落在工程內的鏡像（見 game/.gitignore 註釋）。存為 (標籤, 路徑)——
# 標籤用於備份目錄命名，避免兩個 root 的同名子目錄互相覆蓋。
USERDATA_ROOTS: list[tuple[str, Path]] = []
_appdata = os.environ.get("APPDATA")
if _appdata:
    USERDATA_ROOTS.append(("appdata", Path(_appdata) / "Godot" / "app_userdata" / PRODUCT))
USERDATA_ROOTS.append(("project", PROJECT_DIR / "Godot" / "app_userdata" / PRODUCT))

CLEAN_SUBDIRS = ["saves", "content"]

# --backup：把要清除的產物「移到」這個父目錄下的時間戳子目錄，而非刪除。
BACKUP_PARENT = BUILD_DIR / "_prev"

# 刪除白名單守衛：這些字樣絕不出現在任何被刪路徑中
FORBIDDEN_SUBSTRINGS = ("_preview", ".import")


def human_size(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}GB"


def _assert_safe(p: Path) -> None:
    """硬約束守衛：任何被刪路徑都不得命中 preview / import 等禁區。"""
    s = str(p).lower()
    for bad in FORBIDDEN_SUBSTRINGS:
        if bad in s:
            raise SystemExit(f"[安全中止] 拒絕刪除疑似受保護檔案：{p}")


def _scan_tree(target: Path) -> tuple[int, int]:
    """回傳 (檔案數, 總位元組)。"""
    count = 0
    total = 0
    for root, _dirs, files in os.walk(target):
        for f in files:
            fp = Path(root) / f
            try:
                total += fp.stat().st_size
                count += 1
            except OSError:
                pass
    return count, total


def backup_root() -> Path:
    """本次備份的時間戳目錄：build/_prev/<YYYYMMDD-HHMMSS>/。"""
    return BACKUP_PARENT / time.strftime("%Y%m%d-%H%M%S")


def _move_to_backup(src: Path, bk_root: Path, label: str) -> tuple[int, int]:
    """把 src（檔案或目錄）**移動**到 bk_root/label（同名不覆蓋，自動加序號）。

    回傳 (檔數, 位元組)。同碟 _prev 內移動＝rename，瞬間完成、可逆。
    """
    bk_root.mkdir(parents=True, exist_ok=True)
    dest = bk_root / label
    i = 1
    while dest.exists():
        i += 1
        dest = bk_root / f"{label}.{i}"
    if src.is_file():
        files, total = 1, src.stat().st_size
    else:
        files, total = _scan_tree(src)
    _assert_safe(dest)
    shutil.move(str(src), str(dest))
    return files, total


def clean_data(dry: bool = False, bk_root: Path | None = None) -> int:
    print("\n" + "=" * 68)
    print("【步驟 1】清空 user:// 數據（存檔 saves\\ + 用戶內容 content\\）"
          + (" [備份模式]" if bk_root else ""))
    print("=" * 68)
    grand_files = 0
    grand_bytes = 0
    for label, root in USERDATA_ROOTS:
        for sub in CLEAN_SUBDIRS:
            target = root / sub
            if not target.exists():
                print(f"  · [跳過] 不存在：{target}")
                continue
            _assert_safe(target)
            n, b = _scan_tree(target)
            grand_files += n
            grand_bytes += b
            print(f"  · {target}")
            print(f"      → {'將備份/清除' if bk_root else '將清除'} {n} 個檔案，共 {human_size(b)}")
            if n:
                # 印出清單（最多 20 行，避免刷屏）
                shown = 0
                for r, _d, files in os.walk(target):
                    for f in sorted(files):
                        fp = Path(r) / f
                        try:
                            rel = fp.relative_to(target)
                        except ValueError:
                            rel = fp
                        print(f"        - {rel}  ({fp.stat().st_size}B)")
                        shown += 1
                        if shown >= 20:
                            break
                    if shown >= 20:
                        break
                if n > shown:
                    print(f"        … 其餘 {n - shown} 個省略")
                # 保留頂層骨架：先記下 content 的一級子目錄，清除後重建
                skeleton = []
                if sub == "content":
                    skeleton = [d.name for d in sorted(target.iterdir()) if d.is_dir()]
            else:
                skeleton = []
            if dry:
                if bk_root is not None:
                    print(f"      (dry-run，未移動；備份落點將為 {bk_root / (label + '_' + sub)})")
                else:
                    print("      (dry-run，未實際刪除)")
                continue
            try:
                if bk_root is not None:
                    files, total = _move_to_backup(target, bk_root, f"{label}_{sub}")
                    target.mkdir(parents=True, exist_ok=True)
                    for name in skeleton:
                        (target / name).mkdir(parents=True, exist_ok=True)
                    print(f"      ✓ 已備份 {files} 檔（{human_size(total)}）並重建骨架：{target}")
                else:
                    if target.exists():
                        shutil.rmtree(target)
                    target.mkdir(parents=True, exist_ok=True)
                    for name in skeleton:
                        (target / name).mkdir(parents=True, exist_ok=True)
                    print(f"      ✓ 已清空並保留骨架：{target}")
            except OSError as e:
                raise SystemExit(
                    f"[失敗] 無法清除 {target}：{e}\n"
                    f"        → 可能遊戲仍在執行、檔案被鎖定。請先關閉遊戲，勿暴力終止未知行程。"
                )
    print(f"  ── 合計 {grand_files} 個檔案 / {human_size(grand_bytes)}"
          + ("（已備份）" if bk_root else "（已清除）"))
    return grand_files


def delete_old(dry: bool = False, bk_root: Path | None = None) -> int:
    verb = "備份" if bk_root else "刪除"
    print("\n" + "=" * 68)
    print(f"【步驟 2】{verb}舊打包產物（build\\七傳說.exe / *.pck）"
          + (" [備份模式]" if bk_root else ""))
    print("=" * 68)
    if not BUILD_DIR.exists():
        print(f"  · [跳過] build 目錄不存在：{BUILD_DIR}")
        return 0
    targets: list[Path] = []
    exe = BUILD_DIR / EXE_NAME
    if exe.exists():
        targets.append(exe)
    for pck in sorted(BUILD_DIR.glob("*.pck")):
        targets.append(pck)
    if not targets:
        print("  · [無] 沒有既有 exe / pck 產物")
        return 0
    old_size = 0
    for t in targets:
        _assert_safe(t)
        sz = t.stat().st_size
        old_size = sz if t.name == EXE_NAME else old_size
        print(f"  · {verb} {t.name}  ({human_size(sz)})")
        if dry:
            if bk_root is not None:
                print(f"      (dry-run，未移動；落點將為 {bk_root / t.name})")
            continue
        try:
            if bk_root is not None:
                _move_to_backup(t, bk_root, t.name)
            else:
                t.unlink()
        except OSError as e:
            raise SystemExit(
                f"[失敗] 無法{verb} {t}：{e}\n"
                f"        → 可能遊戲仍在執行、檔案被鎖定。請先關閉遊戲。"
            )
    # 保險：確認 preview 圖仍在
    previews = list(BUILD_DIR.glob("*_preview.png"))
    print(f"  ✓ 已{verb} {len(targets)} 個產物；保留 {len(previews)} 張 *_preview.png（渲染證據，不動）")
    return old_size


def run_export() -> None:
    print("\n" + "=" * 68)
    print("【步驟 3】Godot CLI 導出 release")
    print("=" * 68)
    godot = Path(GODOT_BIN)
    if not godot.exists():
        raise SystemExit(f"[失敗] 找不到 Godot 可執行檔：{godot}\n        → 可用環境變數 GODOT_BIN 覆蓋。")
    if not PROJECT_DIR.joinpath("project.godot").exists():
        raise SystemExit(f"[失敗] 找不到工程：{PROJECT_DIR}")
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(godot),
        "--headless",
        "--path", str(PROJECT_DIR),
        "--export-release", PRESET,
        str(EXE_PATH),
    ]
    print("  命令：")
    print("    " + " ".join(f'"{c}"' if " " in c else c for c in cmd))
    t0 = time.time()
    proc = subprocess.run(cmd, cwd=str(PROJECT_DIR))
    dt = time.time() - t0
    print(f"  · Godot 退出碼 = {proc.returncode}（耗時 {dt:.1f}s）")
    if proc.returncode != 0:
        raise SystemExit(
            f"[失敗] Godot 導出返回非零（{proc.returncode}）。\n"
            f"        → 未自動降級為 --export-debug（避免默默產出 debug 包）；請人工判定後再重跑。"
        )


def verify(started_at: float) -> None:
    print("\n" + "=" * 68)
    print("【步驟 4】驗證新產物")
    print("=" * 68)
    if not EXE_PATH.exists():
        raise SystemExit(f"[失敗] 導出後找不到 exe：{EXE_PATH}")
    st = EXE_PATH.stat()
    if st.st_size <= 0:
        raise SystemExit(f"[失敗] exe 為 0 byte：{EXE_PATH}")
    if st.st_mtime < started_at - 5:
        raise SystemExit(
            f"[失敗] exe 時間戳疑似未更新（mtime={time.ctime(st.st_mtime)}，導出開始={time.ctime(started_at)}）"
        )
    with EXE_PATH.open("rb") as fh:
        magic = fh.read(2)
    if magic != b"MZ":
        raise SystemExit(f"[失敗] exe 缺少 PE 標頭（magic={magic!r}），檔案可能損壞")
    print(f"  · 路徑：{EXE_PATH}")
    print(f"  · 大小：{st.st_size} bytes ({human_size(st.st_size)})")
    print(f"  · 時間：{time.ctime(st.st_mtime)}")
    print(f"  · PE 標頭：OK")
    print("  ✓ 產物驗證通過")


def launch() -> None:
    print("\n" + "=" * 68)
    print("【步驟 5】啟動剛導出的遊戲")
    print("=" * 68)
    if not EXE_PATH.exists():
        raise SystemExit(f"[失敗] 找不到 exe：{EXE_PATH}")
    try:
        subprocess.Popen([str(EXE_PATH)], cwd=str(BUILD_DIR))
        print(f"  ✓ 已啟動：{EXE_PATH}")
    except OSError as e:
        raise SystemExit(f"[失敗] 啟動失敗：{e}")


def main() -> int:
    ap = argparse.ArgumentParser(description="七傳說 一鍵打包（清數據→刪舊包→導出→驗證→可選啟動）")
    ap.add_argument("--clean-data", dest="clean_data", action="store_true", default=True,
                    help="清空 user:// saves/content（預設開）")
    ap.add_argument("--keep-data", dest="clean_data", action="store_false",
                    help="保留存檔，跳過清數據")
    ap.add_argument("--no-export", dest="do_export", action="store_false", default=True,
                    help="只清數據 + 刪舊包，不導出")
    ap.add_argument("--backup", dest="backup", action="store_true", default=False,
                    help="可回滾：清除前把舊包/存檔『移到』build/_prev/<時間戳>/，而非刪除（預設關）")
    ap.add_argument("--run", dest="run", action="store_true", default=False,
                    help="導出後啟動遊戲")
    ap.add_argument("--dry-run", dest="dry", action="store_true", default=False,
                    help="只列印將要做的事，不實際刪除/導出")
    args = ap.parse_args()

    print("╔" + "═" * 66 + "╗")
    print("║  七傳說 · 一鍵打包（package_demo.py）" + " " * 28 + "║")
    print("╚" + "═" * 66 + "╝")
    print(f"  工程目錄：{PROJECT_DIR}")
    print(f"  導出目標：{EXE_PATH}")
    print(f"  Godot   ：{GODOT_BIN}")
    print(f"  清數據  ：{'是（預設鐵律）' if args.clean_data else '否（--keep-data）'}")
    bk_root = backup_root() if args.backup else None
    print(f"  舊產物  ：{'備份到 build/_prev/<時間戳>/（--backup，可回滾）' if args.backup else '直接刪除（--backup 可保留）'}")

    started_at = time.time()
    old_size = None

    if args.clean_data:
        clean_data(dry=args.dry, bk_root=bk_root)
    else:
        print("\n【步驟 1】清數據：已由 --keep-data 跳過")

    old_size = delete_old(dry=args.dry, bk_root=bk_root)

    if args.do_export and not args.dry:
        run_export()
        verify(started_at)
        if old_size:
            print(f"  ℹ️ 舊包大小 {old_size} bytes（{human_size(old_size)}）→ 新包對比見上一步")
    else:
        print("\n【步驟 3/4】導出：已跳過（--no-export 或 --dry-run）")

    if args.run and args.do_export and not args.dry:
        launch()

    if bk_root is not None and not args.dry and bk_root.exists():
        n, b = _scan_tree(bk_root)
        print("\n" + "=" * 68)
        print(f"🗂  備份落點：{bk_root}")
        print(f"   共 {n} 個檔案 / {human_size(b)}（同名自動加序號，不覆蓋既有備份）")
        print("=" * 68)

    print("\n" + "=" * 68)
    print("完成 ✓")
    print("=" * 68)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\n[中斷] 使用者取消", file=sys.stderr)
        raise SystemExit(130)
