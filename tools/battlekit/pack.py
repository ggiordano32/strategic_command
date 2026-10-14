#!/usr/bin/env python3
"""Pack the battle kit's wall / tower / gate / palisade / bastion pieces for the game's
battle view (game/battlekit.gd, game/battlekit_atlas.gd). numpy + ImageMagick, like kitlib.

    python3 tools/battlekit/pack.py [--frames tools/battlekit/_frames] [--out assets/battlekit]
        [--gd game/battlekit_atlas.gd]

Reads the G-buffer passes written by build.py (8 px/m), crops every piece tight to its
alpha, and writes
  atlas_albedo.png   RGBA: albedo (masked parts grey), alpha = coverage; colour bled 2 px
                     into the transparent gutter so linear filtering has no dark fringe.
  atlas_nrm.png      RGBA: R,G = normal x,y (*0.5+0.5, piece space, y up), B = height
                     (z / 20 m), A = mask class (1.0 none, 0.7 roof R, 0.4 plaster G, 0.1 accent B);
                     alpha is never 0 so no importer can touch the data.
  atlas_low.png      RGBA, 4 px/m, pre-lit (NW key, AO from the height pass, Roman palette): the
                     Graphics Low / CPU-path atlas, no normal shader needed.
and the generated GDScript table: per piece name, the crop's size / anchor in metres (the piece
origin is the canvas centre), the rects in the three atlases (px), the atlas sizes.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import kitlib  # noqa: E402

PIECES = ["wall_8_2", "wall_10_2", "wall_12_2", "wall_12_4", "wall_14_4", "pal_8", "pal_10", "pal_12",
          "tower_round", "tower_sq", "tower_timber", "gate_c", "gate_o", "gate_b", "pgate_c", "pgate_o",
          "pgate_b", "bastion",
          "house_gable_s", "house_gable_m", "house_gable_l", "house_hip_s", "house_hip_m", "longhouse", "house_L",
          "hut_round", "hut_thatch", "church", "temple", "stall", "well", "cart", "barrels",
          "tree_broad_a", "tree_broad_b", "tree_broad_c", "tree_pine_a", "tree_pine_b", "tree_palm_a",
          "tree_palm_b", "bush_a", "bush_b", "rock_a", "rock_b", "rock_c", "cliff_m", "cliff_l"]
GUTTER = 4
LIGHT = np.array([-0.55, 0.50, 0.67], np.float32)
AMB, KEY = 0.66, 0.55          # style A (tools/battlekit/mockup.py)
ROMAN = {"R": (0.78, 0.34, 0.22), "G": (0.90, 0.83, 0.68), "B": (0.70, 0.18, 0.16)}


def bleed(rgb, a, n):
    """Extend colour n px into alpha-0 texels (4-neighbour dilation)."""
    rgb = rgb.copy()
    have = a > 0.001
    for _ in range(n):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(have.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            h = np.roll(have, (dy, dx), (0, 1))
            c = np.roll(rgb, (dy, dx), (0, 1))
            acc += c * h[..., None]
            cnt += h
        new = (~have) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][..., None]
        have = have | new
    return rgb


def prelit(alb, nrm, hgt, msk, zmax, ppm):
    a = alb[..., 3:4]
    c = alb[..., :3]
    m = msk[..., :3] * (msk[..., 3:4] > 0.5)
    tint = (m[..., 0:1] * np.array(ROMAN["R"], np.float32) + m[..., 1:2] * np.array(ROMAN["G"], np.float32) +
            m[..., 2:3] * np.array(ROMAN["B"], np.float32)) / 0.85 + (1 - np.clip(m.sum(-1, keepdims=True), 0, 1))
    c = np.clip(c * tint, 0, 1)
    n = nrm[..., :3] * 2 - 1
    n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-6
    L = LIGHT / np.linalg.norm(LIGHT)
    # Rotation-tolerant for the Low path: half of the directional term (instances are rotated
    # without re-lighting there), full ambient and the AO of the height field.
    diff = np.clip(n @ L, 0, 1)
    hemi = 0.5 + 0.5 * n[..., 2]
    lf = (AMB * (0.7 + 0.3 * hemi) + KEY * (0.5 * diff + 0.5 * 0.6)) / (AMB + KEY * L[2] * 0.5 + KEY * 0.3)
    h = hgt[..., 0] * zmax
    ao = kitlib.ambient_occ(h, ppm)
    col = c * lf[..., None] * (1 - 0.35 * ao[..., None])
    return np.clip(col, 0, 1), a


def main():
    args = sys.argv[1:]

    def opt(k, d):
        return args[args.index(k) + 1] if k in args else d
    frames = os.path.abspath(opt("--frames", os.path.join(HERE, "_frames")))
    out = os.path.abspath(opt("--out", os.path.join(ROOT, "assets", "battlekit")))
    gd = os.path.abspath(opt("--gd", os.path.join(ROOT, "game", "battlekit_atlas.gd")))
    os.makedirs(out, exist_ok=True)
    items = []
    for name in PIECES:
        meta = json.load(open(os.path.join(frames, name + ".json")))
        alb = kitlib.load_png(os.path.join(frames, name + "_albedo.png"))
        nrm = kitlib.load_png(os.path.join(frames, name + "_normal.png"))
        hgt = kitlib.load_png(os.path.join(frames, name + "_height.png"), 16)
        msk = kitlib.load_png(os.path.join(frames, name + "_mask.png"))
        N = meta["px"]
        ys, xs = np.nonzero(alb[..., 3] > 0.02)
        # crop to an even box so the 4 px/m set is an exact half
        x0, x1 = int(xs.min()) - 1, int(xs.max()) + 2
        y0, y1 = int(ys.min()) - 1, int(ys.max()) + 2
        x0 -= x0 % 2
        y0 -= y0 % 2
        x1 += x1 % 2
        y1 += y1 % 2
        sl = (slice(y0, y1), slice(x0, x1))
        lit, a = prelit(alb, nrm, hgt, msk, meta["zmax"], meta["ppm"])
        m = msk[..., :3] * (msk[..., 3:4] > 0.5)
        mcls = np.where(m[..., 0] > 0.5, 0.7, np.where(m[..., 1] > 0.5, 0.4, np.where(m[..., 2] > 0.5, 0.1, 1.0)))
        items.append({"name": name, "meta": meta,
                      "alb": alb[sl], "nrm": nrm[sl], "hgt": hgt[..., 0][sl], "mcls": mcls[sl].astype(np.float32),
                      "lit": np.concatenate([lit, a], -1)[sl],
                      "w": x1 - x0, "h": y1 - y0,
                      "cx": ((x0 + x1) / 2 - N / 2) / meta["ppm"], "cy": ((y0 + y1) / 2 - N / 2) / meta["ppm"]})
    # shelf packing, tallest first
    order = sorted(items, key=lambda it: -it["h"])
    W = 1024
    x = y = rowh = 0
    for it in order:
        w, h = it["w"] + GUTTER * 2, it["h"] + GUTTER * 2
        if x + w > W:
            x, y, rowh = 0, y + rowh, 0
        it["px"], it["py"] = x + GUTTER, y + GUTTER
        x += w
        rowh = max(rowh, h)
    H = 1
    while H < y + rowh:
        H *= 2
    ALB = np.zeros((H, W, 4), np.float32)
    NRM = np.zeros((H, W, 4), np.float32)
    NRM[..., :2] = 0.5
    NRM[..., 3] = 1.0
    LOW = np.zeros((H // 2, W // 2, 4), np.float32)
    for it in items:
        px, py, w, h = it["px"], it["py"], it["w"], it["h"]
        ALB[py:py + h, px:px + w] = it["alb"]
        NRM[py:py + h, px:px + w, 0:2] = it["nrm"][..., 0:2]
        NRM[py:py + h, px:px + w, 2] = it["hgt"]
        NRM[py:py + h, px:px + w, 3] = it["mcls"]
        # alpha-0 texels inside the piece's box: keep neutral normal data
        a = it["alb"][..., 3] < 0.02
        sub = NRM[py:py + h, px:px + w]
        sub[a, 0:2] = 0.5
        sub[a, 2] = 0.0
        sub[a, 3] = 1.0
        lit = it["lit"]
        pl = lit[..., :3] * lit[..., 3:4]
        pl = pl.reshape(h // 2, 2, w // 2, 2, 3).mean((1, 3))
        pa = lit[..., 3].reshape(h // 2, 2, w // 2, 2).mean((1, 3))
        low = np.concatenate([pl / np.maximum(pa[..., None], 1e-4), pa[..., None]], -1)
        LOW[py // 2:py // 2 + h // 2, px // 2:px // 2 + w // 2] = low
    ALB[..., :3] = bleed(ALB[..., :3], ALB[..., 3], GUTTER)
    LOW[..., :3] = bleed(LOW[..., :3], LOW[..., 3], 2)
    kitlib.save_png(os.path.join(out, "atlas_albedo.png"), ALB)
    kitlib.save_png(os.path.join(out, "atlas_nrm.png"), NRM)
    kitlib.save_png(os.path.join(out, "atlas_low.png"), LOW)
    lines = ["extends RefCounted",
             "## GENERATED by tools/battlekit/pack.py: do not edit. The battle kit's walls, towers and gates",
             "## (game/battlekit.gd): per piece the crop's size and anchor in metres (the piece origin is",
             "## the canvas centre; +x right, +y DOWN in the image, the piece's outer side is image up) and",
             "## its rect in pixels in the atlases (atlas_albedo / atlas_nrm at PPM px/m, atlas_low at",
             "## LOW_PPM px/m, the same layout halved).", "",
             "const PPM := 8.0", "const LOW_PPM := 4.0", "const ATLAS_W := %d" % W, "const ATLAS_H := %d" % H,
             "const NAMES: Array[String] = [%s]" % ", ".join('"%s"' % it["name"] for it in items), "",
             "## [x, y, w, h] px in atlas_albedo / atlas_nrm (halve for atlas_low).", "const RECT: Array = ["]
    for it in items:
        lines.append("\t[%d, %d, %d, %d],  # %s" % (it["px"], it["py"], it["w"], it["h"], it["name"]))
    lines += ["]", "", "## [cx, cy, w, h] metres: the crop's centre relative to the piece origin, and its size.",
              "const ANCHOR: Array = ["]
    for it in items:
        lines.append("\t[%.4f, %.4f, %.4f, %.4f],  # %s" % (it["cx"], it["cy"], it["w"] / 8.0, it["h"] / 8.0, it["name"]))
    lines += ["]", ""]
    for i, it in enumerate(items):
        lines.append("const %s := %d" % (it["name"].upper(), i))
    open(gd, "w").write("\n".join(lines) + "\n")
    print("atlas %dx%d, %d pieces, %.1f KB gd" % (W, H, len(items), os.path.getsize(gd) / 1024))


main()
