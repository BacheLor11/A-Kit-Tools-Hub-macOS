#!/usr/bin/env python3
"""
生成 A-Kit Tools Hub 的 App 图标（.icns）。

设计来源：A宝工具箱 / LivePhotoLab 的 AppIcon.icon
  - 底色：icon.json 里的 automatic-gradient，extended-srgb 1.00000,0.23137,0.18824（#FF3B30）
    竖向 start(0.5,0) → stop(0.5,0.7)
  - 字标：Assets/画框.png（白色 "A." 字标，透明底）

用法：
  python3 Scripts/make_app_icon.py <源字标png> <输出目录>

输出：
  <输出目录>/AppIcon.iconset/*.png
  <输出目录>/AppIcon.icns
"""

import sys, os, subprocess, math
from PIL import Image

CANVAS = 1024
INSET = 100                 # macOS 图标网格：1024 画布内 824 内容区
BOX = CANVAS - INSET * 2    # 824
RADIUS = 185                # 内容区圆角
MARK_RATIO = 0.60           # 字标占内容区宽度比例


def rounded_mask(size: int, radius: int) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        # 0 → 0.7 完成 90% 变化，末端趋于稳定，贴近 icon.json 的 stop 位置
        tt = min(1.0, t / 0.7) * 0.92 + t * 0.08
        img.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * tt) for i in range(3)))
    return img.resize((size, size), Image.BICUBIC)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    mark_path, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)

    mark = Image.open(mark_path).convert("RGBA")
    # 裁到 alpha 边界
    bbox = mark.getchannel("A").getbbox()
    if bbox:
        mark = mark.crop(bbox)
    # 源字标带半透明玻璃感（alpha 有大量中间值），图标里统一压成实心白，
    # 否则缩放后右笔画会发灰、像糊了一样
    alpha = mark.getchannel("A")
    alpha = alpha.point(lambda v: 0 if v < 30 else min(255, int(v * 1.6)))
    solid = Image.new("RGBA", mark.size, (255, 255, 255, 255))
    solid.putalpha(alpha)
    mark = solid

    # 底色：#FF3B30 系渐变（上端提亮、下端压深，模拟 icon.json 的 automatic-gradient）
    top = (255, 92, 78)
    bottom = (224, 28, 22)
    bg = vertical_gradient(BOX, top, bottom).convert("RGBA")

    # 字标等比缩放，纵向居中
    target_w = int(BOX * MARK_RATIO)
    ratio = target_w / mark.width
    target_h = int(mark.height * ratio)
    mark_s = mark.resize((target_w, max(1, target_h)), Image.LANCZOS)

    layer = Image.new("RGBA", (BOX, BOX), (0, 0, 0, 0))
    layer.alpha_composite(bg, (0, 0))
    layer.alpha_composite(mark_s, ((BOX - target_w) // 2, (BOX - target_h) // 2))

    mask = rounded_mask(BOX, RADIUS)
    layer.putalpha(mask)

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.alpha_composite(layer, (INSET, INSET))

    iconset = os.path.join(outdir, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    specs = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
             (256, 1), (256, 2), (512, 1), (512, 2)]
    for base, scale in specs:
        px = base * scale
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        icon.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
    icon.save(os.path.join(outdir, "AppIcon-1024.png"))

    icns = os.path.join(outdir, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    print("✓", icns)
    return 0


if __name__ == "__main__":
    sys.exit(main())
