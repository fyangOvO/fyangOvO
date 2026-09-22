# -*- coding: utf-8 -*-
"""史莱姆挤压弹跳动画（程序化形变，脚底对齐，最近邻保持像素感）。

4帧循环：正常 -> 压扁(着地) -> 拉长(跳起顶点) -> 正常。
用法：python slime_squash.py <idle.png> <out_dir> <prefix>
"""
import sys
from pathlib import Path
from PIL import Image


def main():
    src, out_dir, prefix = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    out_dir.mkdir(parents=True, exist_ok=True)
    im = Image.open(src).convert("RGBA")
    W, H = im.size
    bb = im.getbbox()
    body = im.crop(bb)
    bw, bh = bb[2] - bb[0], bb[3] - bb[1]
    base_x = bb[0]          # 原图身体左下角
    base_y = bb[3]
    # (x缩放, y缩放)
    poses = [(1.0, 1.0), (1.16, 0.82), (0.86, 1.14), (1.0, 1.0)]
    for i, (sx, sy) in enumerate(poses):
        nw, nh = max(1, round(bw * sx)), max(1, round(bh * sy))
        squashed = body.resize((nw, nh), Image.NEAREST)
        frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        # 水平居中于原身体中心，脚底对齐原基线
        cx = (bb[0] + bb[2]) // 2
        ox = cx - nw // 2
        oy = base_y - nh
        frame.paste(squashed, (ox, oy), squashed)
        out = out_dir / f"{prefix}_{i + 1:02d}.png"
        frame.save(out)
        print(f"  帧{i+1}: {nw}x{nh} -> {out.name}")
    print(f"[完成] -> {out_dir}")


if __name__ == "__main__":
    main()
