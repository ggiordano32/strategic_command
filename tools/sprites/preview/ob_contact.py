#!/usr/bin/env python3
"""Contact sheet of the oblique sheets (tabletop pass 3): a few units in the 8
directions (walk frame 2, recoloured, a green board under them with the feet
anchor marked by a red dot and the 1 m x 1 m ground cell foreshortened by the
camera) and kit pieces (houses, walls, a tower, a gate) with their footprint
rectangle and anchor drawn on the ground.

    python3 tools/sprites/preview/ob_contact.py OUT.png [--scale 3]
        [--units heavy_swords,shock_cavalry,...] [--pieces p_house_s_wh__y0,...]
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.dirname(HERE))
import pack  # noqa: E402

GRASS = (96, 132, 66)
DIRS = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]


def arg(n, d):
    a = sys.argv
    return a[a.index(n) + 1] if n in a else d


def put(img, x, y, c):
    if 0 <= x < img.w and 0 <= y < img.h:
        img.put(x, y, c)


def line_rect(img, x0, y0, x1, y1, c, scale):
    for x in range(int(x0), int(x1) + 1):
        for k in range(scale // 2 + 1):
            put(img, x, int(y0) + k, c); put(img, x, int(y1) - k, c)
    for y in range(int(y0), int(y1) + 1):
        for k in range(scale // 2 + 1):
            put(img, int(x0) + k, y, c); put(img, int(x1) - k, y, c)


def blit(img, sh, mk, f, ax, ay, ox, oy, pal, scale, flip=False):
    """draw frame f (rect) with its anchor at canvas (ox, oy) (already scaled)"""
    fx, fy, fw, fh = f
    for yy in range(fh):
        for xx in range(fw):
            s = sh.get(fx + xx, fy + yy)
            if s[3] == 0:
                continue
            m = mk.get(fx + xx, fy + yy)
            c = pack.recolor(s, m, pal) if pal else [s[0], s[1], s[2]]
            if c is None:
                continue
            for dy in range(scale):
                for dx in range(scale):
                    put(img, int(ox + ((ax - xx) if flip else (xx - ax)) * scale + dx), int(oy + (yy - ay) * scale + dy), c + [255])


def main():
    out = sys.argv[1]
    scale = int(arg("--scale", 3))
    units = arg("--units", "heavy_swords,pikemen,shock_cavalry,musketeers,elephant,cannon").split(",")
    pieces = arg("--pieces", "p_house_s_wh__y0,p_house_s_wh__y4,p_house_m_oc__y0,p_church__y0,p_pal_wall__y0,"
                 "p_stone_wall__y0,p_stone_tower__y0,p_stone_gate__y0,p_palm_a__y0").split(",")
    man = json.load(open(os.path.join(ROOT, "assets", "sprites_ob", "manifest.json")))
    ppm = man["px_per_m"]
    sinE = math.sin(math.radians(man["elevation_deg"]))
    sh = pack.Img.load(os.path.join(ROOT, "assets", "sprites_ob", "atlas_shade.png"))
    mk = pack.Img.load(os.path.join(ROOT, "assets", "sprites_ob", "atlas_mask.png"))
    pal = man["palettes"]["rome"]
    # cell size from the largest frame
    cw = ch = 0
    for u in units:
        a = man["units"][u]["actions"]["walk"]
        r = a["frames"]["S"][0]
        cw, ch = max(cw, r[2]), max(ch, r[3])
    cw += 10; ch += 10
    kit = json.load(open(os.path.join(ROOT, "assets", "kit_ob", "manifest.json")))
    ksh = pack.Img.load(os.path.join(ROOT, "assets", "kit_ob", "atlas_shade.png"))
    kmk = pack.Img.load(os.path.join(ROOT, "assets", "kit_ob", "atlas_mask.png"))
    kr = ppm // kit["px_per_m"]          # the kit's texels are drawn kr times larger: the same metres as the men
    kcw = max(kit["pieces"][k]["rect"][2] for k in pieces) * kr + 10
    kch = max(kit["pieces"][k]["rect"][3] for k in pieces) * kr + 10
    W = max(8 * cw, len(pieces) * kcw)
    H = len(units) * ch + kch + 40
    img = pack.Img(W * scale, H * scale, fill=GRASS + (255,))
    # units
    for row, u in enumerate(units):
        act = man["units"][u]["actions"]["walk"]
        ax, ay = act["anchor"]
        for k, dn in enumerate(DIRS):
            fr = act["frames"][dn][2 % len(act["frames"][dn])]
            ox = (k * cw + cw / 2) * scale
            oy = (row * ch + ch - 5 - 4) * scale
            # one metre of ground, foreshortened: 24 px wide, 24 sin(e) tall, centred on the feet
            gx0, gx1 = ox - 0.5 * ppm * scale, ox + 0.5 * ppm * scale
            gy0, gy1 = oy - 0.5 * ppm * sinE * scale, oy + 0.5 * ppm * sinE * scale
            line_rect(img, gx0, gy0, gx1, gy1, (70, 100, 50, 255), scale)
            blit(img, sh, mk, fr, ax, ay, ox, oy, pal, scale, man.get("mirror") and dn in ("NE", "E", "SE"))
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    put(img, int(ox) + dx, int(oy) + dy, (230, 30, 30, 255))
    # kit pieces, footprint rectangles
    y0 = len(units) * ch
    for n, key in enumerate(pieces):
        p = kit["pieces"][key]
        ax, ay = p["anchor"]
        ox = (n * kcw + kcw / 2) * scale
        oy = (y0 + kch - 12 + 30) * scale
        x0, yb, x1, yt = p["footprint_m"]
        ppm_k = ppm
        fx0, fx1 = ox + x0 * ppm_k * scale, ox + x1 * ppm_k * scale
        fy0, fy1 = oy - yt * sinE * ppm_k * scale, oy - yb * sinE * ppm_k * scale
        line_rect(img, fx0, fy0, fx1, fy1, (230, 200, 40, 255), scale)
        blit(img, ksh, kmk, p["rect"], ax, ay, ox, oy, pal, scale * kr)
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                put(img, int(ox) + dx, int(oy) + dy, (230, 30, 30, 255))
    img.save(out)
    print("contact sheet", out, img.w, "x", img.h)


main()
