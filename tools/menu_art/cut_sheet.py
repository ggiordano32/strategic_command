#!/usr/bin/env python3
"""Cut a hand-cleaned two-emblem sheet (left = west, right = rome, flat brown ground) into transparent emblems.
  python3 -I cut_sheet.py SHEET.png OUT_DIR     -> OUT_DIR/west.png rome.png (512), west_128.png rome_128.png
Colour-keys the ground (median of the border, soft edge, spill removed), splits at the emptiest column near the middle,
trims, centres on a square with 6 % padding. PIL + numpy + scipy."""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

im = Image.open(sys.argv[1]).convert("RGB"); out = sys.argv[2]; os.makedirs(out, exist_ok=True)
a = np.asarray(im).astype(float)
border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
bg = np.median(border, axis=0)
d = np.sqrt(((a - bg) ** 2).sum(2))
alpha = np.clip((d - 12) / (34 - 12), 0, 1)
al = alpha[..., None]
col = np.where(al > 0.01, (a - (1 - al) * bg) / np.maximum(al, 1e-3), a)
col = np.clip(col, 0, 255)
rgba = np.dstack([col, alpha * 255]).astype(np.uint8)
# drop specks
keep, n = ndi.label(alpha > 0.5)
sizes = ndi.sum(alpha > 0.5, keep, range(1, n + 1))
rgba[..., 3] = np.where(np.isin(keep, [i + 1 for i, s in enumerate(sizes) if s >= 150]) | (ndi.binary_dilation(np.isin(keep, [i + 1 for i, s in enumerate(sizes) if s >= 150]), iterations=2)), rgba[..., 3], 0)
w = rgba.shape[1]
cols = (rgba[..., 3] > 30).sum(0)
lo, hi = int(w * 0.4), int(w * 0.6)
cut = lo + int(np.argmin(cols[lo:hi]))
print("split column", cut, "of", w, "ink in that column", cols[cut])
for name, part in (("west", rgba[:, :cut]), ("rome", rgba[:, cut:])):
    o = Image.fromarray(part, "RGBA"); o = o.crop(o.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
    side = round(max(o.size) / 0.88)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0)); sq.paste(o, ((side - o.width) // 2, (side - o.height) // 2))
    for px, fn in ((512, name + ".png"), (128, name + "_128.png")):
        sq.resize((px, px), Image.LANCZOS).save(os.path.join(out, fn), optimize=True)
    print(name, o.size, "->", side)
