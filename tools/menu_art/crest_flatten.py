#!/usr/bin/env python3
"""Flatten a generated crest to gold / ink / the faction colour (+ bone for enclosed light fields) on transparent.
Needs PIL + numpy + scipy (ComfyUI's venv has them).
  python3 crest_flatten.py IN.png FACTION_HEX OUT_256.png OUT_64.png
Background = near-white connected to the border (flood fill, the light fringe eaten); every other pixel takes the
nearest of the palette (gold b08a40, ink 1a1410, faction colour, bone e8dcb0) in a luma-weighted RGB distance; the
crest is cropped to its box, centred in a square with a margin, and shrunk with Lanczos (4x supersampled)."""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

GOLD, INK, BONE = (0xb0, 0x8a, 0x40), (0x1a, 0x14, 0x10), (0xe8, 0xdc, 0xb0)
fac = tuple(int(sys.argv[2][i:i + 2], 16) for i in (0, 2, 4))
pal = np.array([GOLD, INK, fac, BONE], float)
im = Image.open(sys.argv[1]).convert("RGB").resize((1024, 1024), Image.LANCZOS)
a = np.asarray(im).astype(int)
luma = (a[..., 0] * 299 + a[..., 1] * 587 + a[..., 2] * 114) // 1000
chroma = a.max(2) - a.min(2)
white = (luma > 225) & (chroma < 30)
lab, _ = ndi.label(white)
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bg = np.isin(lab, list(border))
bg = ndi.binary_dilation(bg, iterations=2) & (luma > 150)
w = np.array([0.30, 0.59, 0.11])
d = (((a[:, :, None, :] - pal[None, None, :, :]) ** 2) * w).sum(3)
idx = d.argmin(2)
idx = ndi.median_filter(idx.astype(np.uint8), size=3)          # smooth jaggies
rgb = pal.astype(np.uint8)[idx]
alpha = ~bg
alpha = ndi.binary_opening(alpha, iterations=1)
keep, n = ndi.label(alpha)
sizes = ndi.sum(alpha, keep, range(1, n + 1))
alpha = np.isin(keep, [i + 1 for i, s in enumerate(sizes) if s > 400])
alpha = ndi.binary_fill_holes(alpha) | alpha
# colour under the transparent pixels = nearest opaque pixel (no dark / light halo when shrinking)
_, (iy, ix) = ndi.distance_transform_edt(~alpha, return_indices=True)
rgb = rgb[iy, ix]
o = Image.fromarray(np.dstack([rgb, alpha.astype(np.uint8) * 255]), "RGBA")
o = o.crop(o.getchannel("A").getbbox())
side = int(max(o.size) * 1.06)
sq = Image.new("RGBA", (side, side), (0, 0, 0, 0)); sq.paste(o, ((side - o.width) // 2, (side - o.height) // 2))
for path, px in ((sys.argv[3], 256), (sys.argv[4], 64)):
    sq.resize((px * 4, px * 4), Image.LANCZOS).resize((px, px), Image.LANCZOS).save(path, optimize=True)
