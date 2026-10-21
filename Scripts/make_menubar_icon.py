#!/usr/bin/env python3
"""
生成菜单栏图标（template image）。

菜单栏图标靠 alpha 通道着色：系统在浅色模式画深色、深色模式画白色、被选中时反色。
所以只需要一张干净的透明底字形，颜色无所谓。

用法：
  python3 Scripts/make_menubar_icon.py <源图 png> <输出目录>

输出：
  <输出目录>/MenuBarIcon.png   36x36 px（18pt @2x）
"""

import sys, os
from PIL import Image


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    src, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)

    im = Image.open(src).convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if bbox:
        im = im.crop(bbox)

    # 源字标带玻璃半透明，缩到 16pt 会糊；菜单栏只要轮廓，统一压成实心
    alpha = im.getchannel("A").point(lambda v: 0 if v < 30 else min(255, int(v * 1.7)))
    solid = Image.new("RGBA", im.size, (0, 0, 0, 255))
    solid.putalpha(alpha)
    im = solid

    # 18pt 的菜单栏图标留 1pt 上下留白 → 字形高度 16pt，@2x = 32px
    target = 32
    ratio = target / im.height
    im = im.resize((max(1, int(im.width * ratio)), target), Image.LANCZOS)

    canvas = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((36 - im.width) // 2, (36 - im.height) // 2))

    # template 只用 alpha，把 RGB 归一成黑色，避免系统取色时偏色
    r, g, b, a = canvas.split()
    black = Image.new("RGBA", canvas.size, (0, 0, 0, 255))
    black.putalpha(a)
    out = os.path.join(outdir, "MenuBarIcon.png")
    black.save(out)
    print("✓", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
