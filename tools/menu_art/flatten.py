#!/usr/bin/env python3
"""Flatten a generated emblem to gold / ink / bone on transparent. Needs PIL + numpy + scipy (the hunyuan venv has them).
  python3 flatten.py IN.png OUT_512.png OUT_128.png
Background = near-white connected to the border (flood fill); enclosed near-white becomes bone; dark low-chroma = ink; the rest gold."""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

GOLD, INK, BONE = (0xb0, 0x8a, 0x40), (0x1a, 0x14, 0x10), (0xe8, 0xdc, 0xb0)
im = Image.open(sys.argv[1]).convert("RGB").resize((1024, 1024), Image.LANCZOS)
a = np.asarray(im).astype(int)
luma = (a[..., 0] * 299 + a[..., 1] * 587 + a[..., 2] * 114) // 1000
chroma = a.max(2) - a.min(2)
white = (luma > 225) & (chroma < 30)
lab, _ = ndi.label(white)
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bg = np.isin(lab, list(border))
bg = ndi.binary_dilation(bg, iterations=1) & (luma > 170)   # eat the light fringe
dark = ((luma < 60) | ((luma < 100) & (chroma < 22)))
out = np.zeros(a.shape[:2] + (4,), np.uint8)
out[...] = GOLD + (255,)
out[white & ~bg, :3] = BONE
out[dark, :3] = INK
out[bg, 3] = 0
# drop specks, close pinholes
alpha = ndi.binary_opening(out[..., 3] > 0, iterations=1)
keep, n = ndi.label(alpha)
sizes = ndi.sum(alpha, keep, range(1, n + 1))
alpha = np.isin(keep, [i + 1 for i, s in enumerate(sizes) if s > 400])
out[..., 3] = alpha * 255
o = Image.fromarray(out, "RGBA")
bb = o.getchannel("A").getbbox()
o = o.crop(bb)
side = max(o.size) + 40
sq = Image.new("RGBA", (side, side), (0, 0, 0, 0)); sq.paste(o, ((side - o.width) // 2, (side - o.height) // 2))
big = sq.resize((2048, 2048), Image.NEAREST) if False else sq
for path, px in ((sys.argv[2], 512), (sys.argv[3], 128)):
    r = big.resize((px * 4, px * 4), Image.LANCZOS).resize((px, px), Image.LANCZOS)
    r.save(path, optimize=True)
