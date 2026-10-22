#!/usr/bin/env python3
"""Key art: 1344x768 PNG -> 1920x1080 JPEG (Lanczos; no upscale model installed), quality 85, size-checked.
   Wordmark: STRATEGIC COMMAND in Cinzel Bold, gold with a 2 px ink outline, 1600 px wide, transparent.
  python3 finish.py keyart IN.png OUT.jpg | wordmark FONT.ttf OUT.png      (PIL)"""
import sys
from PIL import Image, ImageDraw, ImageFont

if sys.argv[1] == "keyart":
    im = Image.open(sys.argv[2]).convert("RGB")
    w, h = im.size
    if w * 9 != h * 16:                       # centre-crop to 16:9 first
        nh = w * 9 // 16; y = (h - nh) // 2; im = im.crop((0, y, w, y + nh))
    im = im.resize((1920, 1080), Image.LANCZOS)
    im.save(sys.argv[3], quality=85, optimize=True, progressive=True)
else:
    text, W, pad = "STRATEGIC COMMAND", 1600, 8
    size = 200
    while True:
        f = ImageFont.truetype(sys.argv[2], size)
        bb = f.getbbox(text, stroke_width=2)
        if bb[2] - bb[0] <= W - 2 * pad or size < 20: break
        size -= 2
    im = Image.new("RGBA", (W, bb[3] - bb[1] + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(im).text(((W - (bb[2] - bb[0])) // 2 - bb[0], pad - bb[1]), text, font=f, fill=(0xb0, 0x8a, 0x40, 255),
                            stroke_width=2, stroke_fill=(0x1a, 0x14, 0x10, 255))
    im.save(sys.argv[3], optimize=True)
