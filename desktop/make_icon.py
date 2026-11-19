"""Draws the app's icon (the green mark of the page header) as a multi-size .ico. Usage: python make_icon.py out.ico"""
import sys

from PIL import Image, ImageDraw

S = 256
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle((8, 8, S - 8, S - 8), radius=48, fill=(20, 83, 45, 255))
for y, w in ((72, 150), (112, 150), (152, 150), (192, 96)):  # lines of a page, the last one short
    d.rounded_rectangle((S - 53 - w, y - 9, S - 53, y + 9), radius=9, fill=(255, 255, 255, 255))
img.save(sys.argv[1], sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
