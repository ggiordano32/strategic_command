#!/usr/bin/env python3
"""Packs the style D renders into the game's miniature atlases.

    python3 tools/structures/pack.py [--frames DIR] [--out assets/minis]

Two sets, "big" (kit pieces rendered at 300, ships at 128) and "small" (pieces 140,
ships 64); each is a shade atlas (RGBA, lit colours, faction parts white) and
a mask atlas (R primary, G secondary, B accent; A always 255). Sprites are
cropped to their alpha box; the anchor is where the ground origin (0,0,0) of
the structure lies inside the crop. Writes game/minis_atlas.gd (generated):
SETS {set: {sprite name: [x, y, w, h, anchor_x, anchor_y, px_per_metre]}}.
Recolour in the game's minis shader (game/campaign/minis.gdshader).
"""
import json, math, os, sys
import numpy as np
import compose as C

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SETS = {"big": (300, 128), "small": (140, 64)}   # sizes: (kit pieces "p_*", ships)
GUT = 2
W = 2048


def arg(n, d):
    a = sys.argv
    return a[a.index(n) + 1] if n in a else d


# ---------------------------------------------------------------- painted kit (the cities pass, as pass 4 did the figures)

PAINTED = "--no-painted" not in sys.argv   # --no-painted packs the committed atlases byte for byte
PAINT = {
    "contrast": 1.10, "saturation": 1.10,   # the shade lifted off the board
    "line": {"big": 0.55, "small": 0.68},   # interior black-line: the local colour x this (the small atlas is 2 px a metre: lighter)
    "edge": 1.35,          # edge highlight: the local colour x this, warmed
    "warm": (1.05, 1.0, 0.90),
    "varnish": 0.0,        # roofs and walls stay matte: the lobe is on metal and water / glass only
    "varnish_metal": 0.65, "varnish_water": 0.45,
    "lobe_lo": 0.90,       # n.h where the varnish starts (1 = the mirror direction)
    "team_head": 0.08,     # team parts (shade white, multiplied by the faction) lose this much so the highlights have headroom
    "crease": 0.30,        # a lit facet next to a facet this much less lit: its edge is highlighted
}
# toward the key in camera space for tilt 52 (build.py KEY_TO = (-0.55, 0.45, 0.70)): x right, y up the screen, z at the camera
_T = math.radians(52.0)
_LT = (-0.55, 0.45 * math.cos(_T) + 0.70 * math.sin(_T), -0.45 * math.sin(_T) + 0.70 * math.cos(_T))
_n = math.sqrt(sum(c * c for c in _LT))
LIGHT = np.array([c / _n for c in _LT], np.float32)
_hv = np.array([LIGHT[0], LIGHT[1], LIGHT[2] + 1.0], np.float32)
HALF = _hv / np.linalg.norm(_hv)


def _shift(a, dx, dy, fill):
    """a[y + dy, x + dx] as an array (fill outside the frame)."""
    h, w = a.shape[:2]
    out = np.full_like(a, fill)
    ys = slice(max(0, -dy), min(h, h - dy)); yd = slice(max(0, dy), min(h, h + dy))
    xs = slice(max(0, -dx), min(w, w - dx)); xd = slice(max(0, dx), min(w, w + dx))
    out[ys, xs] = a[yd, xd]
    return out


def paint_frame(sh, mk, nrm, idp, sname):
    """The painter's pass on one cropped frame (sh, mk, nrm, idp: float RGBA 0..1; sh is changed in place), inside the
    silhouette only: contrast and saturation, the varnish lobe on metal / water, black-lines where the part id steps
    (on the farther part), warm edge highlights on the near side of a step, the top of the silhouette and lit creases."""
    P = PAINT
    solid = sh[..., 3] > 0.0
    rgb = sh[..., :3]
    lum = (rgb * np.array([0.299, 0.587, 0.114], np.float32)).sum(-1, keepdims=True)
    rgb = lum + (rgb - lum) * P["saturation"]
    rgb = (rgb - 0.5) * P["contrast"] + 0.5
    tw = np.clip(mk[..., :3].sum(-1, keepdims=True), 0.0, 1.0)
    rgb = rgb * (1.0 - P["team_head"] * tw)
    known = solid & (idp[..., 3] > 0.5) & (idp[..., 0] > 0.0)
    pid = np.where(known, np.rint(idp[..., 0] * 255.0), 0).astype(np.int16)
    dep = np.rint(idp[..., 2] * 255.0).astype(np.int16)
    n = nrm[..., :3] * 2.0 - 1.0
    nl = (n * LIGHT).sum(-1)
    d = (n * HALF).sum(-1)
    lo = P["lobe_lo"]
    spec = np.where(d > lo, ((d - lo) / (1.0 - lo)) ** 2, 0.0)
    spec = np.where(known, spec, 0.0)[..., None]
    gl = idp[..., 1:2]
    metal = (gl > 0.8) & known[..., None]
    water = (gl > 0.4) & (gl <= 0.8) & known[..., None]
    gain = np.where(metal, 1.0 + P["varnish_metal"] * spec, np.where(water, 1.0 + P["varnish_water"] * spec, 1.0 + P["varnish"] * spec))
    lift = np.where(metal, 0.16 * spec, 0.0)
    rgb = rgb * gain + lift
    line = np.zeros(pid.shape, bool)
    edge = np.zeros(pid.shape, bool)
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        sj = _shift(solid, dx, dy, False)
        qj = _shift(pid, dx, dy, 0)
        depj = _shift(dep, dx, dy, 0)
        nlj = _shift(nl, dx, dy, 0.0)
        if dy == -1:
            edge |= known & ~sj                     # the top of the silhouette
        both = known & sj & (qj > 0)
        diff = both & (qj != pid)
        dd = dep - depj
        behind = diff & ((dd > 0) | ((dd == 0) & (pid < qj)))
        line |= behind
        if dx < 0 or dy < 0:
            edge |= diff & ~behind & (nl > 0.2)     # the near part's left / top rim, facing the key
            edge |= both & (qj == pid) & (nl > 0.55) & (nlj < nl - P["crease"])
        else:
            pass
    edge &= ~line
    fl = P["line"][sname]
    rgb = np.where(line[..., None], rgb * fl, rgb)
    wr = np.array(P["warm"], np.float32)
    rgb = np.where(edge[..., None], rgb * P["edge"] * wr, rgb)
    sh[..., :3] = np.where(solid[..., None], np.clip(rgb, 0.0, 1.0), sh[..., :3])
    return sh


def main_oblique():
    """Pass 3 (tabletop): pack the oblique kit (build.py --oblique, 40 degrees
    elevation, 8 px / m) into assets/kit_ob/: atlas_shade.png + atlas_mask.png
    (the same two passes as the minis atlases) and manifest.json. Each piece
    keeps its top-down key (p_<piece>__y0 and, where it has one, __y4, the 180
    degree flip); anchor = the footprint's centre on the ground, in px from the
    sprite's top-left; footprint_m = the footprint rectangle in metres relative
    to the anchor (x east, y north; at yaw 0 the front is south, -y)."""
    frames = os.path.join(arg("--frames", os.path.join(HERE, "_frames_ob")), "D")
    out = arg("--out", os.path.join(ROOT, "assets", "kit_ob"))
    os.makedirs(out, exist_ok=True)
    names = sorted({f.rsplit("_", 2)[0] for f in os.listdir(frames) if f.endswith("_shade.png")})
    elev = 40.0
    sprites = []
    for key in names:
        base = os.path.join(frames, "%s_256" % key)
        sh = C.load(base + "_shade.png"); mk = C.load(base + "_mask.png")
        info = json.load(open(base + ".json"))
        ys, xs = np.where(sh[..., 3] > 0.03)
        if len(xs) == 0:
            continue
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        sh_c = sh[y0:y1, x0:x1].copy(); mk_c = mk[y0:y1, x0:x1].copy()
        mk_c[..., 3] = 1.0
        sh_c[..., :3] *= (sh_c[..., 3:4] > 0.0)
        ppm = info["ppm"]
        ox, oy = info["origin_px"]
        fp = info.get("footprint_m")
        if fp is None:
            g = info["ground_m"] / 2.0
            fp = [-g, -g, g, g]
        cx, cy = (fp[0] + fp[2]) / 2.0, (fp[1] + fp[3]) / 2.0
        # ground (x, y) -> screen: right = x, down = -y * sin(elevation)
        ax = ox + cx * ppm - x0
        ay = oy - cy * math.sin(math.radians(elev)) * ppm - y0
        rel = [round(fp[0] - cx, 3), round(fp[1] - cy, 3), round(fp[2] - cx, 3), round(fp[3] - cy, 3)]
        sprites.append((key, sh_c, mk_c, ax, ay, ppm, rel, info.get("height_m", 0.0)))
    wsh = np.ones((8, 8, 4), np.float32)
    wmk = np.zeros((8, 8, 4), np.float32)
    wmk[..., 0] = 1.0; wmk[..., 3] = 1.0
    sprites.append(("white", wsh, wmk, 4.0, 4.0, 1.0, [0, 0, 0, 0], 0.0))
    order = sorted(sprites, key=lambda s: -s[1].shape[0])
    x = y = rowh = 0
    place = []
    for s in order:
        h, w = s[1].shape[:2]
        if x + w + GUT > W:
            x, y, rowh = 0, y + rowh + GUT, 0
        place.append((s, x, y))
        x += w + GUT
        rowh = max(rowh, h)
    H = 64 * ((y + rowh + GUT + 63) // 64)
    shade = np.zeros((H, W, 4), np.float32)
    mask = np.zeros((H, W, 4), np.float32)
    mask[..., 3] = 1.0
    pieces = {}
    for (key, sh_c, mk_c, ax, ay, ppm, rel, hm), px, py in place:
        h, w = sh_c.shape[:2]
        shade[py:py + h, px:px + w] = sh_c
        mask[py:py + h, px:px + w] = mk_c
        pieces[key] = {"rect": [px, py, w, h], "anchor": [round(float(ax), 2), round(float(ay), 2)],
                       "px_per_m": round(float(ppm), 4), "footprint_m": rel,
                       "size_m": [round(rel[2] - rel[0], 3), round(rel[3] - rel[1], 3)],
                       "height_m": hm}
    C.save(os.path.join(out, "atlas_shade.png"), shade)
    C.save(os.path.join(out, "atlas_mask.png"), mask[..., :3])
    man = {"version": 1, "view": "oblique", "elevation_deg": 40, "px_per_m": 8,
           "doc": "Kit pieces at 40 degrees elevation (camera looking north from the south), upright, true heights. Keys as the top-down kit (p_<piece>__y0, and __y4 = the 180 degree flip where the piece has one). rect: [x, y, w, h] px in atlas_shade.png / atlas_mask.png (mask: R primary, G secondary, B accent, A 255); anchor: px from the rect's top-left to the footprint's centre on the ground; footprint_m: [x0, y0, x1, y1] metres relative to the anchor (x east, y north); the ground plane's vertical scale on screen is sin(elevation) x px_per_m. Recolour as the minis shader.",
           "shade": "atlas_shade.png", "mask": "atlas_mask.png", "size": [W, H], "pieces": pieces}
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    print("kit_ob", len(pieces), "sprites", W, "x", H)


def main():
    if "--oblique" in sys.argv:
        return main_oblique()
    frames = os.path.join(arg("--frames", os.path.join(HERE, "_frames")), "D")
    out = arg("--out", os.path.join(ROOT, "assets", "minis"))
    os.makedirs(out, exist_ok=True)
    names = sorted({f.rsplit("_", 2)[0] for f in os.listdir(frames) if f.endswith("_shade.png")})
    tables = {}
    for sname, (bs, ss) in SETS.items():
        sprites = []
        for key in names:
            if not (key.startswith("p_") or key.startswith("ship_")):
                continue   # the older whole-town sprites are not packed any more
            size = ss if key.startswith("ship_") else bs
            base = os.path.join(frames, "%s_%d" % (key, size))
            if not os.path.exists(base + "_shade.png"):
                continue
            sh = C.load(base + "_shade.png"); mk = C.load(base + "_mask.png")
            info = json.load(open(base + ".json"))
            a = sh[..., 3]
            ys, xs = np.where(a > 0.03)
            if len(xs) == 0:
                continue
            x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            sh_c = sh[y0:y1, x0:x1].copy(); mk_c = mk[y0:y1, x0:x1].copy()
            mk_c[..., 3] = 1.0
            sh_c[..., :3] *= (sh_c[..., 3:4] > 0.0)
            if PAINTED and os.path.exists(base + "_nrm.png") and os.path.exists(base + "_id.png"):
                nr = C.load(base + "_nrm.png")[y0:y1, x0:x1]; ip = C.load(base + "_id.png")[y0:y1, x0:x1]
                sh_c = paint_frame(sh_c, mk_c, nr, ip, sname)
            ox, oy = info["origin_px"]
            sprites.append((key, sh_c, mk_c, ox - x0, oy - y0, info["ppm"]))
        # a white, primary-masked block: untextured shapes (the map trees round a town) draw through the same shader
        wsh = np.ones((8, 8, 4), np.float32)
        wmk = np.zeros((8, 8, 4), np.float32)
        wmk[..., 0] = 1.0
        wmk[..., 3] = 1.0
        sprites.append(("white", wsh, wmk, 4.0, 4.0, 1.0))
        # shelf packing, tallest first
        order = sorted(sprites, key=lambda s: -s[1].shape[0])
        x = y = rowh = 0
        place = []
        for s in order:
            h, w = s[1].shape[:2]
            if x + w + GUT > W:
                x, y, rowh = 0, y + rowh + GUT, 0
            place.append((s, x, y))
            x += w + GUT
            rowh = max(rowh, h)
        H = 64 * ((y + rowh + GUT + 63) // 64)   # multiples of 64 (not a power of two): the atlas only grows as needed
        shade = np.zeros((H, W, 4), np.float32)
        mask = np.zeros((H, W, 4), np.float32)
        mask[..., 3] = 1.0
        tab = {}
        for (key, sh_c, mk_c, ax, ay, ppm), px, py in place:
            h, w = sh_c.shape[:2]
            shade[py:py + h, px:px + w] = sh_c
            mask[py:py + h, px:px + w] = mk_c
            tab[key] = [px, py, w, h, round(float(ax), 1), round(float(ay), 1), round(float(ppm), 4)]
        C.save(os.path.join(out, "atlas_%s_shade.png" % sname), shade)
        C.save(os.path.join(out, "atlas_%s_mask.png" % sname), mask[..., :3])
        tables[sname] = tab
        print(sname, len(tab), "sprites", W, "x", H)
    with open(os.path.join(ROOT, "game", "minis_atlas.gd"), "w") as f:
        f.write("# Generated by tools/structures/pack.py: do not edit.\nextends RefCounted\n\n")
        f.write("## {set: {sprite: [x, y, w, h, anchor_x, anchor_y, px_per_metre]}}\n")
        f.write("const SETS := " + json.dumps(tables, separators=(",", ":")) + "\n")


main()
