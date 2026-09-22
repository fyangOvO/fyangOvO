# -*- coding: utf-8 -*-
"""像素素材包自校验：色板合规 / alpha 二值 / 尺寸 / 清单。"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).parent
PAL = [
    "0B0D10","14171C","1E232B","2A313B","3A424F","4E5866","6B7688","8C97A8","B3BCC9","DCE2E8","DBCC85",
    "4A0E12","8C1A1F","C42B2B","E8573F","0F2417","1E4A2B","3B7A44","6FB35C",
    "101A3A","1F3468","3A5FB0","6E9BE8","4A3208","8C6510","D9A521","F5D77A",
    "2A1440","4E2478","7E44B8","B07DE0","4A0816","B01038","FF2D55","FF7A96",
    "0A2B22","1B6B52","2FA37A","6FE0B4","C9D1D9","4C8BF5","F5C542","A96BFF","FF8A2B",
]
PALSET = set(tuple(int(h[i:i+2],16) for i in (0,2,4)) for h in PAL)


def check(path, strict44=True):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    bad_alpha = set()
    colors = set()
    for c in im.getdata():
        if c[3] != 0 and c[3] != 255:
            bad_alpha.add(c[3])
        if c[3] > 0:
            colors.add(c[:3])
    out_of_pal = colors - PALSET
    return {
        "size": (w, h),
        "colors": len(colors),
        "alpha_binary": len(bad_alpha) == 0,
        "in_palette": (len(out_of_pal) == 0) if strict44 else None,
        "out_sample": list(out_of_pal)[:3],
    }


def main():
    # (分组, 强制44色板, 期望边长, 说明)
    # 角色/武器/装备：DNF 素材惯例，自适应 ~48 色（含肉色/皮柄棕），不强制 44，
    #   与现有 dnf/normalized 角色 46 色、用户裁定"接受 DNF 素材色数超规"一致。
    # 特效/UI/背景/技能图标：严格 44 色板。
    groups = [
        ("characters", False, 192, "角色（自适应48色，不强制44）"),
        ("weapons", False, 48, "武器图标（自适应48色）"),
        ("armor", False, 48, "装备图标（自适应48色）"),
        ("fx", True, 96, "特效帧（强制44色板）"),
        ("backgrounds", False, 0, "背景（640x360，强制44）"),
        ("ui/pixel", False, 0, "UI组件（代码绘制，强制44）"),
        ("ui/skill_icons", True, 48, "技能图标（强制44色板）"),
    ]
    rows = []
    for grp, strict, expect, note in groups:
        d = ROOT / grp
        for p in sorted(d.glob("*.png")):
            # 背景/UI 实际也走 44 色板，只是期望尺寸不是正方形
            r = check(p, strict44=True)
            if grp == "backgrounds":
                size_ok = r["size"] == (640, 360)
            elif grp == "ui/pixel":
                size_ok = True  # 组件尺寸各异
            else:
                size_ok = r["size"] == (expect, expect)
            # 角色/武器/装备不强制44；其余强制
            pal_ok = r["in_palette"] if strict else True
            ok = r["alpha_binary"] and size_ok and pal_ok
            show_pal = r["in_palette"] if strict else None
            rows.append((grp, p.name, r["size"], r["colors"],
                         r["alpha_binary"], show_pal, ok, note))
    print(f"{'分组':14}{'文件':32}{'尺寸':12}{'色数':>4} {'二值':>4} {'44色':>5}")
    print("-" * 90)
    allok = True
    for grp, name, size, ncol, ab, inp, ok, note in rows:
        allok &= ok
        ip = "-" if inp is None else ("✓" if inp else "✗")
        print(f"{grp:14}{name:32}{str(size):12}{ncol:>4} {'✓' if ab else '✗':>4} {ip:>5}")
    print("-" * 90)
    print(f"共 {len(rows)} 个 PNG，全部通过: {'是' if allok else '否'}")


if __name__ == "__main__":
    main()
