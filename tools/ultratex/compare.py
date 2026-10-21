#!/usr/bin/env python3
"""hunyuan-venv python: [committed hybrid | UltraTex raw | UltraTex quantised], bust over mini, 2x.
  compare.py NAME OUT_DIR COMMITTED_DIR(portraits/NAME.png, minis/NAME.png) DEST.png"""
import os, sys
from PIL import Image
name, out, com, dest = sys.argv[1:5]
srcs = [(os.path.join(com, "portraits", name + ".png"), os.path.join(com, "minis", name + ".png"))]
for t in ("raw", "quant"):
    d = os.path.join(out, name, t)
    srcs.append((os.path.join(d, name + "_bust.png"), os.path.join(d, "minis", name + ".png")))
cols = []
for bp, mp in srcs:
    bust = Image.open(bp).convert("RGBA"); mini = Image.open(mp).convert("RGBA")
    bust = bust.resize((bust.width * 2, bust.height * 2), Image.NEAREST)
    mini = mini.resize((mini.width * 2, mini.height * 2), Image.NEAREST)
    W = max(bust.width, mini.width)
    c = Image.new("RGBA", (W, bust.height + mini.height + 8), (140, 158, 128, 255))
    c.alpha_composite(bust, ((W - bust.width) // 2, 0)); c.alpha_composite(mini, ((W - mini.width) // 2, bust.height + 8))
    cols.append(c)
o = Image.new("RGBA", (sum(c.width for c in cols) + 8 * 2, max(c.height for c in cols)), (140, 158, 128, 255))
x = 0
for c in cols:
    o.alpha_composite(c, (x, 0)); x += c.width + 8
o.convert("RGB").save(dest); print(dest)
