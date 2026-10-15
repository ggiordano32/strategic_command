#!/usr/bin/env python3
"""Generates the structure layers of spec.json (style D miniatures for the
overworld). Run:  python3 tools/structures/gen_spec.py

Reads materials, bands, light, palettes and the small `defs` of the existing
spec.json, adds the new defs and writes the structure entries. Every entry is
one sprite layer named <group>__<layer>; the layers of a group share the
group's `frame` (ground rectangle [x0 y0 x1 y1] in metres + height) so they
overlay exactly when drawn at the same anchor (ground origin 0,0,0).

Groups (West, ground R = 29 m): town_s / town_m / town_l (colonial), native,
maya, haven; add-ons for all of them: port (harbour), yard (slipway), walls1
(palisade), walls2 (stone wall with towers), walls3 (star fort), the walls
in a back and a front half (back is drawn before the base, front after).
Rome: rtown_s / rtown_m / rtown_l and rwalls1 / 2 / 3 (square). Ships:
ship_<kind>__h<0..7> (heading k * 45 deg, 0 = east, anticlockwise on the map).
"""
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC_PATH = os.path.join(HERE, "spec.json")
OLD = json.load(open(SPEC_PATH))
MAT = OLD["materials"]
DEFS = OLD["defs"]
R = 29.0          # base tile radius (m)
WR = 25.5         # wall ring radius
ZEX = 1.7         # height exaggeration of everything not on the ground

MAT.update({
    "ochre": [0.9, 0.7, 0.36], "pastel_blue": [0.62, 0.76, 0.84], "pastel_green": [0.68, 0.82, 0.62],
    "glass": [0.98, 0.9, 0.55], "brick": [0.72, 0.38, 0.28], "cobble": [0.72, 0.68, 0.6],
    "palisade": [0.62, 0.45, 0.26], "sail_dark": [0.84, 0.8, 0.68], "hull_dk": [0.3, 0.2, 0.13],
    "hull_lt": [0.62, 0.42, 0.24], "ship_gold": [0.95, 0.78, 0.22], "canoe": [0.52, 0.33, 0.18],
})


def part(s, p=None, m="whitewash", **k):
    d = {"s": s, "m": m}
    if p is not None:
        d["p"] = [round(v, 3) for v in p]
    d.update(k)
    return d


def box(p, sz, m="whitewash", **k):
    return part("box", p, m, sz=list(sz), **k)


def cyl(p, rad, h, m, n=8, rad2=None, **k):
    d = part("cyl", p, m, rad=rad, h=h, n=n, **k)
    if rad2 is not None:
        d["rad2"] = rad2
    return d


def cone(p, rad, h, m, n=8, **k):
    return part("cone", p, m, rad=rad, h=h, n=n, **k)


def roof(p, sz, m="primary", ridge=1.0, **k):
    return part("roof", p, m, sz=list(sz), ridge=ridge, **k)


def sph(p, sz, m, n=6, **k):
    return part("sph", p, m, sz=list(sz), n=n, **k)


def use(name, p, r=0, sc=None, map=None, **k):
    d = {"use": name, "p": [round(v, 3) for v in p], "r": r}
    if sc is not None:
        d["sc"] = sc
    if map:
        d["map"] = map
    d.update(k)
    return d


def circle(n, r, jit=0.0, seed=1, a0=0, a1=360):
    return {"circle": [n, r, jit, seed, a0, a1]}


def pol(r, deg):
    a = math.radians(deg)
    return (r * math.cos(a), r * math.sin(a))


# ---------------------------------------------------------------- defs

DEFS.update({
    "house": [
        box([0, 0, 0], [5, 4, 3.8], "whitewash"),
        roof([0, 0, 3.8], [6.4, 5.4, 4.6], "primary"),
        box([0, -2.02, 0], [1.1, 0.1, 1.8], "dark_wood", ol=0),
        box([-1.5, -2.02, 1.2], [0.9, 0.1, 0.9], "dark_wood", ol=0),
        box([1.4, -2.02, 1.2], [0.9, 0.1, 0.9], "dark_wood", ol=0),
    ],
    "house_tall": [
        box([0, 0, 0], [4.6, 4, 7], "whitewash"),
        roof([0, 0, 7], [5.8, 5, 4.6], "primary"),
        box([0, -2.02, 0], [1.1, 0.1, 1.8], "dark_wood", ol=0),
        box([0, -2.02, 4.4], [1.0, 0.1, 1.2], "secondary", ol=0),
        box([-1.4, -2.02, 2.2], [0.8, 0.1, 0.9], "dark_wood", ol=0),
    ],
    "mansion": [
        box([0, 0, 0], [9, 6, 5], "coquina"),
        box([0, 0, 5], [9.6, 6.6, 0.5], "secondary"),
        roof([0, 0, 5.5], [10.4, 7.4, 4.2], "primary", ridge=0.55),
        box([0, -3.02, 0], [1.6, 0.1, 2.4], "dark_wood", ol=0),
        box([-3, -3.02, 1.6], [1.0, 0.1, 1.2], "dark_wood", ol=0),
        box([3, -3.02, 1.6], [1.0, 0.1, 1.2], "dark_wood", ol=0),
        box([0, -3.3, 0], [3.2, 1.0, 0.5], "stone_lt", ol=0),
    ],
    "chapel": [
        box([0, 0, 0], [6, 9, 5], "whitewash"),
        roof([0, 0, 5], [10, 7, 3.6], "primary", r=90),
        box([0, -6.5, 0], [4, 4, 11], "whitewash"),
        cone([0, -6.5, 11], 3.3, 4.8, "primary", n=4),
        box([0, -6.5, 15.6], [0.5, 0.5, 2.6], "gold"),
        box([0, -6.5, 17.0], [1.8, 0.5, 0.5], "gold"),
        box([0, -8.52, 0], [1.4, 0.1, 2.6], "dark_wood", ol=0),
    ],
    "church": [
        box([0, 0, 0], [11, 17, 8], "whitewash"),
        roof([0, 0, 8], [19, 12.4, 4.6], "primary", r=90),
        box([0, -11, 0], [7, 7, 21], "whitewash"),
        box([0, -11, 21], [8, 8, 1.2], "secondary"),
        box([0, -14.52, 14], [1.2, 0.1, 2.6], "dark_wood", ol=0),
        box([0, -14.52, 0], [2.4, 0.1, 3.6], "dark_wood", ol=0),
        cone([0, -11, 22.2], 5.8, 9.5, "primary", n=4),
        box([0, -11, 31.5], [0.7, 0.7, 4], "gold"),
        box([0, -11, 33.3], [2.6, 0.7, 0.7], "gold"),
    ],
    "cathedral": [
        box([0, 0, 0], [14, 22, 11], "whitewash"),
        roof([0, 0, 11], [24, 16, 6], "primary", r=90),
        box([-5.2, -14, 0], [6, 7, 25], "whitewash"),
        box([5.2, -14, 0], [6, 7, 25], "whitewash"),
        box([-5.2, -14, 25], [7, 8, 1.2], "secondary"),
        box([5.2, -14, 25], [7, 8, 1.2], "secondary"),
        cone([-5.2, -14, 26.2], 5.2, 8.5, "primary", n=4),
        cone([5.2, -14, 26.2], 5.2, 8.5, "primary", n=4),
        box([-5.2, -14, 34.5], [0.6, 0.6, 3.4], "gold"),
        box([-5.2, -14, 36.2], [2.2, 0.6, 0.6], "gold"),
        box([5.2, -14, 34.5], [0.6, 0.6, 3.4], "gold"),
        box([5.2, -14, 36.2], [2.2, 0.6, 0.6], "gold"),
        box([0, -14.3, 0], [4.6, 0.7, 14], "whitewash"),
        box([0, -17.52, 0], [3, 0.1, 5.4], "dark_wood", ol=0),
        cyl([0, 1, 11], 4.6, 5.0, "whitewash", n=8),
        sph([0, 1, 16], [4.9, 4.9, 3.8], "primary", n=8),
        box([0, 1, 19.4], [0.5, 0.5, 3], "gold"),
    ],
    "fountain": [
        cyl([0, 0, 0], 3.0, 0.9, "stone_lt", n=8),
        cyl([0, 0, 0.9], 2.5, 0.2, "water_dk", n=8, ol=0),
        cyl([0, 0, 0.9], 0.6, 2.6, "stone_lt", n=6),
        sph([0, 0, 3.6], [1.4, 1.4, 0.8], "stone_lt", n=6),
    ],
    "well": [
        cyl([0, 0, 0], 1.3, 1.2, "stone", n=8),
        box([-1.1, 0, 1.2], [0.3, 0.3, 2.2], "dark_wood"),
        box([1.1, 0, 1.2], [0.3, 0.3, 2.2], "dark_wood"),
        roof([0, 0, 3.2], [3.2, 3.0, 1.4], "primary", ridge=1.0),
    ],
    "tree": [
        cyl([0, 0, 0], 0.45, 3.4, "wood", n=6, rad2=0.35),
        sph([0, 0, 4.4], [3.1, 3.1, 3.1], "grass_dk", n=7),
        sph([0.6, 0.4, 6.0], [2.0, 2.0, 1.8], "leaf", n=6, ol=0),
    ],
    "totem": [
        cyl([0, 0, 0], 0.9, 14, "wood", n=6),
        box([0, -0.5, 4], [2.6, 0.5, 2.0], "primary"),
        sph([0, -0.6, 8], [1.5, 0.9, 1.5], "jade", n=6),
        box([0, -0.5, 10.5], [3.4, 0.5, 1.0], "secondary"),
        cone([0, 0, 14], 1.0, 2.6, "accent", n=6),
    ],
    "stela": [box([0, 0, 0], [1.8, 0.8, 6.0], "stone_lt"), box([0, -0.42, 3.2], [1.0, 0.1, 1.6], "jade", ol=0)],
    "tent": [roof([0, 0, 0], [5.0, 4.2, 3.6], "sail", ridge=1.0), box([0, -2.12, 0], [1.2, 0.1, 1.9], "dark_wood", ol=0)],
    "pennant": [
        cyl([0, 0, 0], 0.28, 12, "dark_wood", n=6),
        box([-2.6, 0, 8.4], [5.2, 0.16, 3.2], "primary"),
        box([-2.6, 0, 9.3], [5.22, 0.18, 1.0], "secondary", ol=0),
    ],
    "crate": [box([0, 0, 0], [1.8, 1.8, 1.6], "plank"), box([0, 0, 1.6], [1.9, 1.9, 0.2], "dark_wood", ol=0)],
    "post": [cyl([0, 0, -1.5], 0.45, 4.5, "dark_wood", n=6)],
    "rock_big": [sph([0, 0, 0], [3.6, 3.0, 2.4], "rock", n=7), sph([1.6, 1.0, 0.6], [1.8, 1.6, 1.4], "rock_dk", n=6)],
    "roman_house": [
        box([0, 0, 0], [5.2, 4.4, 3.4], "marble"),
        roof([0, 0, 3.4], [6.4, 5.6, 3.0], "primary", ridge=0.7),
        box([0, -2.22, 0], [1.1, 0.1, 1.9], "dark_wood", ol=0),
    ],
    "hovel": [
        box([0, 0, 0], [4.4, 3.6, 2.4], "mud"),
        roof([0, 0, 2.4], [5.6, 4.8, 3.2], "thatch", ridge=0.85),
        box([0, -1.82, 0], [0.9, 0.1, 1.5], "dark_wood", ol=0),
    ],
    "shrine": [
        box([0, 0, 0], [6, 6, 0.9], "marble"),
        cyl([-2.1, -2.1, 0.9], 0.5, 5.2, "marble", n=8, ol=0), cyl([2.1, -2.1, 0.9], 0.5, 5.2, "marble", n=8, ol=0),
        cyl([-2.1, 2.1, 0.9], 0.5, 5.2, "marble", n=8, ol=0), cyl([2.1, 2.1, 0.9], 0.5, 5.2, "marble", n=8, ol=0),
        roof([0, 0, 6.1], [7.0, 7.0, 3.2], "primary", ridge=0.0),
    ],
    "temple_front": [
        box([0, 0, 0], [20, 12, 1.2], "marble"),
    ] + [cyl([-8.1 + 3.24 * i, -4.2, 1.2], 0.72, 9.6, "marble", n=8, ol=0) for i in range(6)] + [
        box([0, -0.4, 10.8], [19, 11, 1.1], "marble"),
        roof([0, -0.4, 11.9], [19.6, 12, 5.6], "marble", ridge=1.0),
        box([0, -4.75, 12.4], [8, 0.3, 3.0], "primary", ol=0),
        box([0, 0.6, 1.2], [14, 7.2, 9.6], "stone_lt", ol=0),
    ],
    "basilica": [
        box([0, 0, 0], [16, 8, 7], "marble"),
        roof([0, 0, 7], [17, 9.4, 4.6], "primary", ridge=1.0),
        box([0, -4.02, 0], [3, 0.1, 4.2], "dark_wood", ol=0),
    ],
    "tower_rome": [
        cyl([0, 0, 0], 3.2, 11, "stone_lt", n=10, rad2=2.9),
        cyl([0, 0, 10.4], 3.8, 1.3, "stone_lt", n=10),
        cone([0, 0, 11.7], 4.2, 5.0, "primary", n=10),
    ],
})
OLD["defs"] = DEFS

# ---------------------------------------------------------------- helpers

def scatter(n, rmin, rmax, seed, avoid, sep=7.0, tries=4000, ymax=None, ymin=None):
    rng = random.Random(seed)
    out = []
    t = 0
    while len(out) < n and t < tries:
        t += 1
        r = rmin + (rmax - rmin) * math.sqrt(rng.random())
        a = rng.random() * 2 * math.pi
        x, y = r * math.cos(a), r * math.sin(a)
        if ymax is not None and y > ymax:
            continue
        if ymin is not None and y < ymin:
            continue
        if abs(y) < 3.4:       # the main street
            continue
        if abs(x) < 3.4 and y > 0:
            continue
        if any((x - ax) ** 2 + (y - ay) ** 2 < ar * ar for ax, ay, ar in avoid):
            continue
        if any((x - qx) ** 2 + (y - qy) ** 2 < sep * sep for qx, qy, _ in out):
            continue
        out.append((x, y, rng.uniform(-9, 9)))
    return out


def streets(r_in=20.0):
    return [
        part("poly", None, "dirt", pts=circle(16, 19.5, 0.07, 6), z0=0, z1=0.18, ol=0),
        box([0, 0, 0], [58, 5.2, 0.34], "dirt", ol=0),
        box([0, 14, 0], [5.2, 28, 0.34], "dirt", ol=0),
    ]


def tile(top="grass", n=20, seed=5, rr=R, jit=0.035):
    return part("poly", None, top, pts=circle(n, rr, jit, seed), z0=-0.3, z1=0.0, ground=1)


def tile_rect(half=R * 0.93, top="grass"):
    return part("poly", None, top, pts={"rect": [-half, -half, half, half]}, z0=-0.3, z1=0.0, ground=1)


WALL_COLS = ["whitewash", "coquina", "ochre", "pastel_blue", "whitewash", "pastel_green", "whitewash", "coquina"]


def houses(positions, tall_every=4, seed=1, mansion_at=None):
    out = []
    rng = random.Random(seed)
    for i, (x, y, r) in enumerate(positions):
        name = "house_tall" if (i % tall_every == tall_every - 1) else "house"
        out.append(use(name, [x, y, 0], r, map={"whitewash": WALL_COLS[(i * 3 + rng.randint(0, 7)) % len(WALL_COLS)]}))
    return out


def trees(positions, palm_every=3):
    out = []
    for i, (x, y, _) in enumerate(positions):
        out.append(use("palm" if i % palm_every == 0 else "tree", [x, y, 0], i * 47 % 360))
    return out


def rim_trees(n, seed, rr=R - 3.2, skip=None):
    rng = random.Random(seed)
    out = []
    for i in range(n):
        a = 360.0 * i / n + rng.uniform(-8, 8)
        if skip and skip(a):
            continue
        x, y = pol(rr * rng.uniform(0.94, 1.0), a)
        out.append((x, y, 0))
    return out


# ---------------------------------------------------------------- bases (West)

S = {}   # struct name -> entry


def add(name, parts, frame, zex=ZEX, nm=None):
    S[name] = {"name": nm or name, "zex": zex, "frame": frame, "parts": parts}


FRAME_W = [-36, -66, 62, 36, 40]       # West ground groups: tile + harbour + yard
FRAME_R = [-36, -36, 36, 36, 34]


def colonial(size):
    p = [tile("grass", 22, 5)] + streets()
    if size == "s":
        church = [use("chapel", [-1, 14.5, 0], 0, sc=1.0)]
        n_h, rmax = 7, 21
        avoid = [(-1, 14.5, 8.5), (0, 0, 5.5)]
        extra = [use("well", [7.5, 0.0, 0.35], 0)]
    elif size == "m":
        church = [use("church", [-2, 14.5, 0], 0, sc=0.92)]
        n_h, rmax = 13, 22
        avoid = [(-2, 15, 11.5), (0, 0, 6)]
        extra = [use("fountain", [0, 0, 0.3], 0, sc=0.8)]
    else:
        church = [use("cathedral", [-2, 16, 0], 0, sc=0.9), use("mansion", [14.5, 11, 0], -8, sc=0.86)]
        n_h, rmax = 18, 23
        avoid = [(-2, 15, 13), (14.5, 11, 8), (0, 0, 6)]
        extra = [use("fountain", [0, 0, 0.3], 0, sc=1.0)]
    pos = scatter(n_h, 8.5, rmax, 11 + len(size), avoid, sep=6.4 if size != "l" else 6.0)
    p += church + extra + houses(pos, 4, 7)
    tp = rim_trees(7 if size == "s" else 5, 3 + len(size), skip=lambda a: 40 < a < 140 and size != "s" or 280 < a < 340)
    p += trees(tp)
    return p


for sz in "sml":
    add("town_%s__base" % sz, colonial(sz), FRAME_W, nm="Colonial town " + sz.upper())


def native():
    p = [tile("grass", 20, 2), part("poly", None, "dirt", pts=circle(14, 21, 0.07, 9), z0=0, z1=0.2, ol=0)]
    huts = [(-11, -8, 10), (-14, 4, 70), (-3.5, 12, 30), (10, 10, 50), (9, -10.5, 20), (-17, -13, 40), (16.5, -1, 0), (-5, 19, 60)]
    for i, (x, y, r) in enumerate(huts):
        p.append(use("hut", [x, y, 0], r, sc=1.15))
    p += [use("hut", [-1.2, -4.0, 0], 0, sc=1.9, map={"thatch": "primary"}),
          use("palapa", [3, -15, 0], -5, sc=1.2), use("palapa", [-20, -2, 0], 80, sc=1.2), use("palapa", [14, 15, 0], 30, sc=1.2),
          cyl([6.4, 3.4, 0], 1.9, 0.5, "rock", n=8), cyl([6.4, 3.4, 0.3], 1.1, 0.6, "black", n=6, ol=0),
          use("smoke", [6.4, 3.4, 0.4], 0, sc=1.6),
          use("totem", [-9.5, -17, 0], 0, sc=1.0),
          use("pennant", [19, -11, 0], 0, sc=0.9)]
    p += trees(rim_trees(8, 9), 2)
    p += [use("crate", [-6, -13, 0], 20, sc=0.8), use("crate", [-4.5, -14.5, 0], 0, sc=0.6)]
    return p


add("native__base", native(), FRAME_W, nm="Native village")


def maya():
    p = [tile("grass", 22, 12, rr=R, jit=0.04)]
    p.append(part("poly", None, "stone_lt", pts={"rect": [-22, -22, 22, 22]}, z0=0, z1=0.5, ol=0))
    levels = [(27, 4.4, "stone_lt"), (22.6, 4.4, "stone"), (18, 4.4, "stone_lt"), (13.6, 4.4, "stone"), (9.4, 4.4, "stone_lt")]
    z = 0.5
    for w, h, m in levels:
        p.append(box([0, 0, z], [w, w, h], m))
        z += h
    p.append(box([0, 0, z], [6.4, 6.4, 5.2], "stone_lt"))
    p.append(box([0, -3.22, z + 0.2], [2.0, 0.1, 3.2], "black", ol=0))
    p.append(box([0, 0, z + 5.2], [7.4, 7.4, 0.9], "secondary"))
    p.append(box([0, 0, z + 6.1], [3.2, 1.2, 7.6], "stone_lt"))
    p.append(box([0, 0, z + 13.7], [4.2, 1.4, 1.0], "primary"))
    # the stair, in the primary colour
    p.append(part("wedge", [0, -10.05, 0.5], "primary", sz=[12.5, 5.0, 22.0], r=-90))
    for sx in (-4.6, 4.6):
        p.append(cyl([sx, -5, z + 5.2], 0.3, 9.5, "dark_wood", n=6))
        p.append(box([sx, -5, z + 11], [0.2, 2.8, 3.2], "jade"))
    p += [use("maya_house", [-24, -9, 0], 80, sc=1.1), use("maya_house", [-21, 8, 0], 15, sc=1.1),
          use("maya_house", [23, 6, 0], -20, sc=1.1), use("maya_house", [20, -12, 0], 75, sc=1.1),
          use("maya_house", [0, 24, 0], 0, sc=1.1),
          use("stela", [-14, -22, 0], 0), use("stela", [14, -22, 0], 0), use("stela", [-22, 17, 0], 90)]
    p += trees(rim_trees(9, 4, skip=lambda a: 250 < a < 290), 2)
    return p


add("maya__base", maya(), FRAME_W, nm="Maya temple town")


def haven():
    p = [tile("sand", 20, 13, jit=0.05),
         part("poly", None, "grass_dk", pts=circle(14, 17.5, 0.12, 14), z0=0, z1=0.18, ol=0)]
    sh = [(-8, 12, 15), (6, 13, -10), (-17, 2, 70), (16, 2, -50), (10, -9, 5), (-10, -11, -20), (0, -16, 10), (-21, 12, 30)]
    for i, (x, y, r) in enumerate(sh):
        p.append(use("shack", [x, y, 0], r, sc=1.15, map={"primary": "primary" if i % 2 == 0 else "dark_wood"}))
    p += [use("tent", [4, 3, 0], 10, sc=1.2),
          use("skull_rock", [-19, 19, 0], 0, sc=1.45),
          use("pole_flag_black", [11, 7, 0], 0, sc=1.2),
          use("hullframe", [-6, -2, 0], 12, sc=1.3),
          use("cannon", [17, -9, 0], 120, sc=1.2), use("cannon", [-22, -5, 0], 200, sc=1.2),
          use("barrel", [2, -10, 0], 0, sc=1.4), use("barrel", [3.6, -10.8, 0], 0, sc=1.4), use("barrel", [1, -11.6, 0], 0, sc=1.4),
          use("rock_big", [22, 10, 0], 0, sc=1.2),
          cyl([-1, 6, 0], 1.5, 0.4, "rock", n=8), use("smoke", [-1, 6, 0.3], 0, sc=1.3)]
    p += trees(rim_trees(7, 6, skip=lambda a: 60 < a < 130), 2)
    return p


add("haven__base", haven(), FRAME_W, nm="Pirate haven")


# ---------------------------------------------------------------- add-ons (West)

def pier():
    p = []
    # planks from the tile rim out to sea, along a diagonal to the south-east
    pts = []
    base_a = -52
    for k in range(4):
        r = 21.0 + 7.0 * k
        pts.append(pol(r, base_a))
    # deck as one rotated box
    ang = base_a
    mid = pol(33.0, ang)
    p.append(box([mid[0], mid[1], 0.2], [30, 8.0, 0.8], "plank", r=ang, ol=1))
    for k in range(6):
        c = pol(22.0 + 5.4 * k, ang)
        for sd in (-1, 1):
            px = c[0] + sd * 3.6 * math.cos(math.radians(ang + 90))
            py = c[1] + sd * 3.6 * math.sin(math.radians(ang + 90))
            p.append(use("post", [px, py, 0], 0))
    end = pol(46.5, ang)
    p.append(use("crane", [end[0] - 1.0, end[1] + 1.0, 1.0], ang + 20, sc=1.2))
    p.append(use("crate", [pol(38.5, ang)[0] + 2.4, pol(38.5, ang)[1] + 1.5, 1.0], 20, sc=1.1))
    p.append(use("crate", [pol(36.5, ang)[0] - 2.2, pol(36.5, ang)[1] - 1.0, 1.0], -15, sc=0.9))
    p.append(use("barrel", [pol(41.5, ang)[0] - 1.6, pol(41.5, ang)[1] + 2.4, 1.0], 0, sc=1.4))
    p.append(use("barrel", [pol(40.5, ang)[0] - 2.8, pol(40.5, ang)[1] + 1.2, 1.0], 0, sc=1.4))
    # a warehouse on the tile rim and a rowboat
    wp = pol(30.5, -8)
    p.append(use("warehouse", [wp[0], wp[1], 0], 90 + 8, sc=0.95))
    p.append(use("lighthouse_l", [27.5, 14.5, 0], 0, sc=1.0))
    p.append(use("rowboat", [pol(31.5, -80)[0], pol(31.5, -80)[1], -0.4], 20, sc=1.0))
    return p


DEFS["lighthouse_l"] = [
    cyl([0, 0, 0], 5.2, 2.2, "rock", n=8),
    cyl([0, 0, 2.2], 3.7, 6.0, "whitewash", n=8, rad2=3.3),
    cyl([0, 0, 8.2], 3.3, 5.5, "primary", n=8, rad2=2.95),
    cyl([0, 0, 13.7], 2.95, 5.5, "whitewash", n=8, rad2=2.6),
    cyl([0, 0, 19.2], 2.6, 4.5, "primary", n=8, rad2=2.3),
    cyl([0, 0, 23.7], 3.6, 0.9, "stone", n=8),
    cyl([0, 0, 24.6], 1.9, 3.0, "glass", n=8, ol=0),
    cone([0, 0, 27.6], 3.0, 3.4, "primary", n=8),
    cyl([0, 0, 31.0], 0.2, 2.2, "dark_wood", n=6),
    box([0.9, 0, 32.2], [1.8, 0.1, 1.0], "secondary", ol=0),
]
DEFS["rowboat"] = [
    part("poly", None, "plank", pts=[[-3.2, -1.2], [1.2, -1.6], [3.6, 0], [1.2, 1.6], [-3.2, 1.2]], z0=-0.2, z1=0.9, sc0=0.6, sc1=1.0),
    box([0, 0, 0.9], [2.2, 0.3, 0.2], "dark_wood", ol=0),
]
DEFS["warehouse"] = [
    box([0, 0, 0], [12, 7.4, 5.2], "plank"),
    roof([0, 0, 5.2], [13.2, 8.6, 4.8], "primary"),
    box([0, -3.77, 0], [3.0, 0.12, 3.2], "dark_wood", ol=0),
    box([4.2, -3.77, 1.8], [1.2, 0.12, 1.2], "dark_wood", ol=0),
    box([-4.2, -3.77, 1.8], [1.2, 0.12, 1.2], "dark_wood", ol=0),
]
DEFS["crane"] = [
    box([0, 0, 0], [2.6, 2.6, 0.6], "stone"),
    box([0, 0, 0.6], [1.4, 1.4, 11.5], "wood"),
    box([3.6, 0, 11.0], [9.0, 0.8, 0.8], "dark_wood"),
    box([-2.2, 0, 10.6], [2.6, 1.6, 1.6], "iron"),
    box([0, 0, 12.2], [1.2, 1.2, 1.2], "secondary"),
    cyl([6.9, 0, 5.6], 0.08, 5.4, "rope", n=4, ol=0),
    box([6.9, 0, 5.0], [1.0, 1.0, 0.8], "iron"),
]


def yard():
    p = []
    ang = -128
    c0 = pol(21, ang)
    # slipway: a wedge running down to the sea (high end at the tile)
    mid = pol(33.5, ang)
    p.append(part("wedge", [mid[0], mid[1], 0.1], "plank", sz=[26, 9.4, 2.4], r=ang + 180))
    # the hull on the stocks: a few ribs
    hp = pol(32.0, ang)
    p.append(use("hullframe", [hp[0], hp[1], 1.8], ang + 180 + 0, sc=1.0))
    # shed and crane and logs
    sp = pol(21.8, -168)
    p.append(use("warehouse", [sp[0], sp[1], 0], 180 + 16, sc=0.8, map={"primary": "secondary"}))
    cp = pol(37.5, -100)
    p.append(use("crane", [cp[0], cp[1], 0], 0, sc=1.0))
    for k, (rr, aa) in enumerate([(30, -158), (31.4, -153), (29.5, -150)]):
        q = pol(rr, aa)
        p.append(use("log", [q[0], q[1], 0], 70 + 8 * k, sc=1.3))
    p.append(use("pennant", [pol(21, -178)[0], pol(21, -178)[1], 0], 0, sc=0.7))
    return p


add("port__harbour", pier(), FRAME_W, nm="Harbour")
add("yard__slipway", yard(), FRAME_W, nm="Shipyard slipway")


# walls: back (y >= 0) and front (y < 0) halves

def palisade(half, r=WR):
    p = []
    n = 44
    for k in range(n):
        a = 360.0 * (k + 0.5) / n
        s = math.sin(math.radians(a))
        if (half == "back") != (s >= 0):
            continue
        x, y = pol(r, a)
        p.append(cyl([x, y, 0], 0.95, 5.2, "palisade", n=6, rad2=0.85))
        p.append(cone([x, y, 5.2], 0.95, 1.8, "palisade", n=6))
    a0, a1 = (0, 180) if half == "back" else (180, 360)
    p.append(part("wall", None, "dark_wood", pts=circle(22, r, 0.0, 1, a0, a1), closed=False, t=0.9, t2=0.9, h=3.4, z0=0.8))
    # a gate post pair in the south front
    if half == "front":
        for sx in (-3.2, 3.2):
            p.append(cyl([sx, -r, 0], 1.1, 8.0, "dark_wood", n=6))
        p.append(box([0, -r, 6.6], [8.4, 1.2, 1.1], "secondary"))
    return p


def stone_wall(half, r=WR):
    p = []
    a0, a1 = (0, 180) if half == "back" else (180, 360)
    p.append(part("wall", None, "stone_lt", pts=circle(20, r, 0.0, 1, a0, a1), closed=False, t=3.2, t2=2.4, h=4.4))
    p.append(part("wall", None, "stone", pts=circle(20, r, 0.0, 1, a0, a1), closed=False, t=3.4, t2=3.4, h=0.7, z0=4.4, ol=0))
    for k in range(8):
        a = 45.0 * k
        s = math.sin(math.radians(a))
        if abs(s) < 1e-6:
            if half == "back":
                continue   # the east / west towers belong to the front half
        elif (half == "back") != (s > 0):
            continue
        x, y = pol(r, a)
        p.append(cyl([x, y, 0], 2.9, 7.4, "stone_lt", n=8, rad2=2.6))
        p.append(cyl([x, y, 7.0], 3.4, 1.0, "stone", n=8))
        p.append(cone([x, y, 8.0], 3.5, 3.6, "primary", n=8))
    if half == "front":
        # the gate: an arch between two squat towers
        p.append(box([0, -r, 0], [9.0, 4.4, 7.6], "stone_lt"))
        p.append(box([0, -r - 2.22, 0], [3.6, 0.1, 5.0], "black", ol=0))
        p.append(box([0, -r, 7.6], [10, 5.2, 0.9], "stone"))
        p.append(box([0, -r, 8.5], [3.2, 0.7, 4.4], "primary"))
    return p


def star_pts(n=8, ro=27.4, ri=21.6):
    pts = []
    for i in range(n * 2):
        a = 180.0 * i / n
        pts.append(pol(ro if i % 2 == 0 else ri, a))
    return pts


def star_fort(half):
    p = []
    pts = star_pts()
    n = len(pts)
    idx = list(range(0, n // 2 + 1)) if half == "back" else list(range(n // 2, n + 1))
    path = [list(pts[i % n]) for i in idx]
    p.append(part("wall", None, "sand", pts=path, closed=False, t=9.5, t2=7.8, h=0.7, ol=0))
    p.append(part("wall", None, "coquina", pts=path, closed=False, t=3.4, t2=2.2, h=4.0, z0=0.2))
    p.append(part("wall", None, "stone_lt", pts=path, closed=False, t=2.8, t2=2.8, h=0.6, z0=4.2, ol=0))
    for i in range(0, n, 2):
        a = 180.0 * i / (n // 2)
        s = math.sin(math.radians(a))
        if abs(s) < 1e-6:
            if half == "back":
                continue
        elif (half == "back") != (s > 0):
            continue
        x, y = pol(ro_ := 25.6, a)
        p.append(use("cannon", [x, y, 4.9], a, sc=0.95))
        pass
    if half == "front":
        p.append(use("pennant", [pol(21.5, 270)[0], pol(21.5, 270)[1], 0], 0, sc=1.2))
    return p


for half in ("back", "front"):
    add("walls1__%s" % half, palisade(half), FRAME_W, zex=ZEX, nm="Palisade " + half)
    add("walls2__%s" % half, stone_wall(half), FRAME_W, zex=ZEX, nm="Stone wall " + half)
    add("walls3__%s" % half, star_fort(half), FRAME_W, zex=ZEX, nm="Star fort " + half)


# ---------------------------------------------------------------- Rome

def rome_base(size):
    p = [tile_rect(R * 0.93, "grass")]
    p.append(part("poly", None, "cobble", pts={"rect": [-22, -22, 22, 22]}, z0=0, z1=0.22, ol=0))
    p.append(box([0, 0, 0], [50, 4.8, 0.3], "dirt", ol=0))
    p.append(box([0, 0, 0], [4.8, 50, 0.3], "dirt", ol=0))
    avoid = [(0, 0, 8)]
    if size == "s":
        p.append(use("shrine", [0, 11, 0], 0, sc=0.9))
        pos = scatter(8, 8, 20, 21, avoid + [(0, 11, 6)], sep=6.2)
        p += [use("hovel", [x, y, 0], r) for (x, y, r) in pos]
        p += trees(rim_trees(5, 3, rr=R * 0.8), 9)
    elif size == "m":
        p.append(use("temple_front", [0, 12, 0], 0, sc=0.75))
        pos = scatter(14, 8, 21, 22, avoid + [(0, 12, 11)], sep=6.2)
        p += [use("roman_house", [x, y, 0], r) for (x, y, r) in pos]
        p.append(use("fountain", [0, 0, 0.3], 0, sc=0.7))
        p += trees(rim_trees(4, 4, rr=R * 0.8), 9)
    else:
        p.append(use("temple_front", [0, 14, 0], 0, sc=0.9))
        p.append(use("basilica", [-14, -4, 0], 0, sc=0.85))
        p.append(use("tower_rome", [-19, 19, 0], 0, sc=0.7))
        p.append(use("tower_rome", [19, 19, 0], 0, sc=0.7))
        pos = scatter(15, 9, 22, 23, avoid + [(0, 14, 13), (-14, -4, 10), (-19, 19, 4), (19, 19, 4)], sep=6.0)
        p += [use("roman_house", [x, y, 0], r, sc=0.98) for (x, y, r) in pos]
        p.append(use("fountain", [3, -2, 0.3], 0, sc=0.8))
    return p


for sz in "sml":
    add("rtown_%s__base" % sz, rome_base(sz), FRAME_R, nm="Roman " + sz)


def rome_walls(level, half):
    h = 25.0
    p = []
    if half == "back":
        path = [[h, 0], [h, h], [-h, h], [-h, 0]]
    else:
        path = [[-h, 0], [-h, -h], [h, -h], [h, 0]]
    if level == 1:
        p.append(part("wall", None, "dark_wood", pts=path, closed=False, t=1.0, t2=1.0, h=4.6))
        for (x, y) in ([(h, h), (-h, h)] if half == "back" else [(-h, -h), (h, -h), (-h, 0), (h, 0)]):
            p.append(cyl([x, y, 0], 1.3, 8.0, "dark_wood", n=6))
        return p
    th, ht = (3.4, 7.0) if level == 2 else (4.0, 9.0)
    p.append(part("wall", None, "stone_lt", pts=path, closed=False, t=th, t2=th * 0.78, h=ht))
    p.append(part("wall", None, "stone", pts=path, closed=False, t=th + 0.3, t2=th + 0.3, h=0.7, z0=ht, ol=0))
    corners = [(h, h), (-h, h)] if half == "back" else [(-h, -h), (h, -h), (-h, 0), (h, 0)]
    for (x, y) in corners:
        if y == 0:
            continue
        p.append(cyl([x, y, 0], 3.5, ht + 3.5, "stone_lt", n=10, rad2=3.1))
        p.append(cyl([x, y, ht + 3.0], 4.1, 1.2, "stone", n=10))
        p.append(cone([x, y, ht + 4.2], 4.3, 5.0, "primary", n=10))
    if level == 3:
        mids = [(0, h)] if half == "back" else [(0, -h)]
        for (x, y) in mids:
            p.append(box([x, y, 0], [8, 6, ht + 3.0], "stone_lt"))
            p.append(box([x, y, ht + 3.0], [9, 7, 1.0], "stone"))
    if half == "front":
        p.append(box([0, -h, 0], [8, 5, ht + 3.0], "stone_lt"))
        p.append(box([0, -h - 2.52, 0], [3.4, 0.1, 5.2], "black", ol=0))
        p.append(box([0, -h, ht + 3.0], [9, 6, 1.0], "stone"))
        p.append(box([0, -h - 2.7, ht + 1.6], [3.0, 0.5, 2.6], "primary", ol=0))
    return [q for q in p if q]


for lv in (1, 2, 3):
    for half in ("back", "front"):
        add("rwalls%d__%s" % (lv, half), rome_walls(lv, half), FRAME_R, nm="Roman walls %d %s" % (lv, half))


# ---------------------------------------------------------------- ships

def sail(x, z, w, h, m="sail", lean=40.0, band=True):
    """A square sail as two panels in a shallow V (so it reads from every heading)."""
    out = []
    for sd in (-1, 1):
        y = sd * w * 0.22
        out.append(box([x, y, z], [0.24, w * 0.58, h], m, r=[0, 0, sd * lean]))
        if band:
            out.append(box([x, y, z + h * 0.5 - 0.5], [0.3, w * 0.58 + 0.02, 0.9], "primary", r=[0, 0, sd * lean], ol=0))
    return out


def hull_poly(L, Bm, stern=0.84, bow=0.66):
    # a keel-line plan, bow +x
    return [[-L * 0.5, -Bm * stern * 0.5], [-L * 0.28, -Bm * 0.5], [L * 0.12, -Bm * 0.5], [L * 0.5, 0], [L * 0.12, Bm * 0.5], [-L * 0.28, Bm * 0.5], [-L * 0.5, Bm * stern * 0.5]]


def ship_parts(kind):
    p = []
    if kind == "sloop":
        L, B, H = 17, 6.6, 3.4
        pts = hull_poly(L, B)
        p += [part("poly", None, "hull_lt", pts=pts, z0=-0.8, z1=H, sc0=0.5, sc1=1.0),
              part("wall", None, "secondary", pts=pts, closed=True, t=0.6, h=0.8, z0=H),
              box([-5.5, 0, H], [4.2, 4.4, 1.8], "hull_dk"),
              cyl([1.0, 0, H], 0.4, 17, "dark_wood", n=6)]
        p += sail(-2.8, 10.5, 7.0, 11.0, lean=40)       # mainsail (fore-aft drawn broad)
        p += sail(5.2, 8.0, 4.4, 8.0, lean=40, band=False)
        p += [cyl([8.0, 0, H - 0.2], 0.28, 8.0, "dark_wood", n=6, r=[0, 66, 0])]
        p += [box([-4.2, 0, 8.0], [3.2, 0.14, 2.0], "primary"), cyl([-4.2, 0, H + 1.8], 0.15, 6, "dark_wood", n=4, ol=0)]
        return p, 10.0, 22
    if kind == "brigantine":
        L, B, H = 22, 7.6, 3.8
        pts = hull_poly(L, B)
        p += [part("poly", None, "hull_lt", pts=pts, z0=-0.9, z1=H, sc0=0.5, sc1=1.0),
              part("wall", None, "secondary", pts=pts, closed=True, t=0.6, h=0.8, z0=H),
              box([-7.5, 0, H], [5.0, 5.2, 2.2], "hull_dk"),
              box([-7.5, 0, H + 2.2], [5.2, 5.4, 0.4], "secondary"),
              cyl([-1.8, 0, H], 0.42, 19, "dark_wood", n=6), cyl([5.0, 0, H], 0.36, 16, "dark_wood", n=6)]
        p += sail(-2.0, 11.0, 8.2, 8.0) + sail(-2.0, 18.6, 6.0, 5.4) + sail(5.4, 10.0, 7.2, 7.0)
        p += [cyl([10.0, 0, H - 0.3], 0.3, 9.0, "dark_wood", n=6, r=[0, 68, 0])]
        p += [box([-9.4, 0, 9.2], [3.2, 0.14, 2.0], "primary"), cyl([-9.4, 0, H + 2.6], 0.15, 7, "dark_wood", n=4, ol=0)]
        return p, 12.0, 26
    if kind == "frigate":
        L, B, H = 30, 9.6, 4.6
        pts = hull_poly(L, B)
        p += [part("poly", None, "hull_lt", pts=pts, z0=-1.1, z1=H, sc0=0.5, sc1=1.0),
              part("wall", None, "secondary", pts=pts, closed=True, t=0.7, h=0.9, z0=H),
              box([-9.5, 0, H], [6.6, 7.0, 2.8], "hull_dk"), box([-9.5, 0, H + 2.8], [6.8, 7.2, 0.5], "secondary"),
              box([12.0, 0, H], [4.0, 5.0, 1.4], "hull_dk")]
        for gx in (-3, 0.5, 4):
            for sd in (-1, 1):
                p.append(box([gx, sd * (B * 0.5 + 0.04), H * 0.5], [1.0, 0.1, 0.9], "black", ol=0))
        for mx, mh in ((-4.0, 24), (3.6, 27), (10.2, 19)):
            p.append(cyl([mx, 0, H], 0.46, mh, "dark_wood", n=6))
        p += sail(-4.4, 11.0, 10.5, 9.0) + sail(-4.4, 20.0, 8.2, 6.4) + sail(3.2, 12.0, 11.5, 10.0) + sail(3.2, 22.0, 8.6, 7.0) + sail(9.8, 10.0, 8.0, 7.0)
        p += [cyl([14.0, 0, H + 0.2], 0.3, 10.0, "dark_wood", n=6, r=[0, 68, 0])]
        p += [box([-11.5, 0, 12.0], [3.6, 0.14, 2.2], "primary"), cyl([-11.5, 0, H + 3.3], 0.16, 8.5, "dark_wood", n=4, ol=0)]
        return p, 15.0, 36
    if kind == "galleon":
        L, B, H = 36, 13.2, 5.6
        pts = hull_poly(L, B, 0.78, 0.6)
        p += [part("poly", None, "hull_lt", pts=pts, z0=-1.4, z1=H, sc0=0.5, sc1=1.0),
              part("wall", None, "secondary", pts=pts, closed=True, t=0.8, h=1.0, z0=H),
              box([-11.5, 0, H], [9.0, 9.4, 4.4], "hull_dk"), box([-11.5, 0, H + 4.4], [9.4, 9.8, 0.6], "secondary"),
              box([-13.4, 0, H + 1.2], [0.3, 7.4, 1.6], "gold", ol=0), box([-13.7, 0, H + 3.4], [0.3, 5.0, 1.2], "gold", ol=0),
              box([13.0, 0, H], [5.2, 6.4, 2.4], "hull_dk"), box([13.0, 0, H + 2.4], [5.4, 6.6, 0.4], "secondary")]
        for gx in (-3.5, 0, 3.5):
            for sd in (-1, 1):
                p.append(box([gx, sd * (B * 0.5 + 0.04), H * 0.45], [1.2, 0.1, 1.1], "black", ol=0))
                p.append(box([gx, sd * (B * 0.5 + 0.04), H * 0.45 + 1.5], [1.2, 0.1, 1.1], "ship_gold", ol=0))
        for mx, mh in ((-5.0, 31), (3.0, 35), (9.8, 24)):
            p.append(cyl([mx, 0, H], 0.55, mh, "dark_wood", n=6))
        p += sail(-5.3, 12.5, 12.5, 11.0) + sail(-5.3, 23.5, 10.0, 8.0) + sail(2.7, 13.5, 13.5, 12.5) + sail(2.7, 26.0, 10.5, 9.0) + sail(9.5, 12.5, 9.2, 8.0)
        p += [cyl([17.0, 0, H + 1.8], 0.38, 12.0, "dark_wood", n=6, r=[0, 70, 0])]
        p += [box([-13.0, 0, 15.5], [4.2, 0.16, 2.8], "primary"), cyl([-13.0, 0, H + 5.0], 0.2, 10.5, "dark_wood", n=4, ol=0)]
        p += [box([3.0, 0, 38.0], [3.4, 0.14, 2.2], "primary"), cyl([3.0, 0, 34.0], 0.16, 5.0, "dark_wood", n=4, ol=0)]
        return p, 18.0, 42
    if kind == "ship_of_the_line":
        L, B, H = 40, 13.4, 6.0
        pts = hull_poly(L, B, 0.8, 0.62)
        p += [part("poly", None, "hull_dk", pts=pts, z0=-1.4, z1=H, sc0=0.5, sc1=1.0),
              part("wall", None, "secondary", pts=pts, closed=True, t=0.8, h=1.0, z0=H),
              box([-13.5, 0, H], [9.0, 9.2, 3.6], "hull_lt"), box([-13.5, 0, H + 3.6], [9.4, 9.6, 0.5], "secondary"),
              box([14.0, 0, H], [5.0, 6.4, 1.8], "hull_lt")]
        for gx in (-5, -1.8, 1.4, 4.6, 7.8):
            for sd in (-1, 1):
                p.append(box([gx, sd * (B * 0.5 + 0.04), H * 0.3], [1.1, 0.1, 1.0], "black", ol=0))
                p.append(box([gx, sd * (B * 0.5 + 0.04), H * 0.3 + 1.6], [1.1, 0.1, 1.0], "black", ol=0))
        p.append(part("wall", None, "ship_gold", pts=pts, closed=True, t=0.7, h=0.5, z0=H * 0.32, ol=0))
        for mx, mh in ((-6.2, 33), (2.2, 38), (10.6, 27)):
            p.append(cyl([mx, 0, H], 0.6, mh, "dark_wood", n=6))
        p += sail(-6.5, 13.0, 13.5, 12.0) + sail(-6.5, 25.0, 11.0, 9.0) + sail(1.9, 14.0, 14.5, 13.5) + sail(1.9, 27.5, 11.5, 10.0) + sail(10.3, 13.0, 10.0, 9.0) + sail(10.3, 23.0, 7.5, 6.0)
        p += [cyl([18.5, 0, H + 1.4], 0.4, 12.0, "dark_wood", n=6, r=[0, 70, 0])]
        p += [box([-14.0, 0, 16.5], [4.8, 0.16, 3.0], "primary"), cyl([-14.0, 0, H + 4.1], 0.2, 12, "dark_wood", n=4, ol=0)]
        return p, 20.0, 46
    # war canoe
    L, B, H = 20, 3.8, 1.2
    pts = [[-L * 0.5, -B * 0.32], [-L * 0.2, -B * 0.5], [L * 0.2, -B * 0.5], [L * 0.5, -0.1], [L * 0.5, 0.1], [L * 0.2, B * 0.5], [-L * 0.2, B * 0.5], [-L * 0.5, B * 0.32]]
    p += [part("poly", None, "canoe", pts=pts, z0=-0.6, z1=H, sc0=0.55, sc1=1.0),
          part("wall", None, "secondary", pts=pts, closed=True, t=0.5, h=0.5, z0=H),
          box([L * 0.5 + 0.3, 0, 1.5], [0.8, 0.9, 2.2], "canoe"),
          sph([L * 0.5 - 0.9, 1.0, 0.9], [0.6, 0.15, 0.6], "bone", ol=0), sph([L * 0.5 - 0.9, -1.0, 0.9], [0.6, 0.15, 0.6], "bone", ol=0),
          sph([L * 0.5 - 0.9, 1.0, 0.9], [0.25, 0.18, 0.25], "black", ol=0), sph([L * 0.5 - 0.9, -1.0, 0.9], [0.25, 0.18, 0.25], "black", ol=0)]
    for k in range(7):
        x = -L * 0.38 + k * 2.3
        for sd in (-1, 1):
            p.append(sph([x, sd * 1.0, H + 0.9], [0.55, 0.55, 0.9], "primary" if k % 2 == 0 else "accent", ol=0))
            p.append(cyl([x + 0.3, sd * 2.0, H + 0.4], 0.14, 3.2, "dark_wood", n=4, r=[sd * 38, 0, 0], ol=0))
    p += [cyl([-1.0, 0, H], 0.22, 11, "dark_wood", n=6), box([-1.0, 0, 11.0], [3.4, 0.14, 2.6], "primary"),
          box([-2.4, 0, 12.7], [0.2, 0.2, 1.6], "jade", ol=0), box([-0.4, 0, 12.9], [0.2, 0.2, 1.8], "secondary", ol=0)]
    return p, 8.0, 15


SHIPS = ["sloop", "brigantine", "frigate", "galleon", "ship_of_the_line", "war_canoe"]
for kind in SHIPS:
    parts, hw, zmax = ship_parts(kind)
    for hd in range(8):
        add("ship_%s__h%d" % (kind, hd), [{"use": "ship_%s_def" % kind, "p": [0, 0, 0], "r": 45.0 * hd}],
            [-hw * 1.2, -hw * 1.2, hw * 1.2, hw * 1.2, zmax], zex=1.45, nm="%s h%d" % (kind, hd))
    DEFS["ship_%s_def" % kind] = parts


# ---------------------------------------------------------------- pieces (the overworld kit, 2026-10-15)
# Single pieces for game/campaign/town_plan.gd / town_layer.gd: houses, churches, walls, quays ... each at
# 8 yaws (k * 45 deg anticlockwise from "front towards south (-y)"; pieces symmetric under a half turn have 4,
# round ones 1). Names p_<piece>__y<k>; the frame is "auto" (tight bounds, a fixed scale).
MAT.update({
    "tree_g1": [0.07, 0.17, 0.06], "tree_g2": [0.10, 0.22, 0.08], "tree_dry": [0.25, 0.28, 0.12], "palm_leaf": [0.10, 0.25, 0.08],
    "orange": [0.16, 0.32, 0.10], "fruit": [0.95, 0.55, 0.15], "wall_ochre": [0.86, 0.72, 0.45],
})
PIECES = []     # (name, yaws, def name)


def piece(name, parts, yaws=8):
    DEFS["pc_" + name] = parts
    PIECES.append((name, yaws))


def house_colour(base, colour, tall=False):
    return [dict(q, m=colour) if q.get("m") == "whitewash" else q for q in DEFS[base]]


for cname, col in (("wh", "whitewash"), ("oc", "ochre"), ("bl", "pastel_blue"), ("co", "coquina")):
    piece("house_s_" + cname, house_colour("house", col))
    piece("house_m_" + cname, house_colour("house_tall", col))
for cname, col in (("sa", "wall_ochre"), ("wh", "whitewash")):
    piece("adobe_" + cname, [
        box([0, 0, 0], [5.4, 4.6, 3.2], col),
        box([0, 0, 3.2], [5.8, 5.0, 0.5], "secondary"),
        box([0, 0.2, 3.7], [4.2, 3.6, 0.3], "stone"),
        box([0, -2.32, 0], [1.1, 0.1, 1.9], "dark_wood", ol=0),
        box([-1.7, -2.32, 1.1], [0.9, 0.1, 0.9], "dark_wood", ol=0),
        box([1.7, -2.32, 1.1], [0.9, 0.1, 0.9], "dark_wood", ol=0),
    ])
Y4 = [0, 2, 4, 6]
for nm, k in (("chapel", 0.9), ("church", 0.78), ("cathedral", 0.66), ("mansion", 0.85)):
    piece(nm, [use(nm, [0, 0, 0], 0, sc=k)], Y4)
DEFS["pc_fort_raw"] = ([
    box([0, 0, 0], [22, 22, 4.2], "coquina"),
    box([0, 0, 4.2], [22.6, 22.6, 0.7], "stone_lt"),
    box([0, 0, 4.9], [11, 11, 4.0], "stone_lt"),
    box([0, 0, 8.9], [11.8, 11.8, 0.8], "stone"),
    box([0, -11.02, 0], [4.4, 0.1, 3.0], "black", ol=0),
] + [cyl([sx * 11, sy * 11, 0], 3.6, 8.0, "coquina", n=8, rad2=3.3) for sx in (-1, 1) for sy in (-1, 1)] + [
    cyl([sx * 11, sy * 11, 8.0], 4.1, 0.8, "stone", n=8) for sx in (-1, 1) for sy in (-1, 1)] + [
    cone([sx * 11, sy * 11, 8.8], 4.0, 3.4, "primary", n=8) for sx in (-1, 1) for sy in (-1, 1)] + [
    cyl([0, 0, 9.7], 0.22, 7.0, "dark_wood", n=6, ol=0), box([1.3, 0, 14.6], [2.6, 0.12, 1.6], "primary", ol=0),
])
piece("fort", [use("pc_fort_raw", [0, 0, 0], 0, sc=0.72)], [0])
piece("fountain", DEFS["fountain"], 1)
piece("well", DEFS["well"], 1)
piece("hut", DEFS["hut"])
piece("hut_big", [use("hut", [0, 0, 0], 0, sc=1.6, map={"thatch": "primary"})])
piece("palapa", DEFS["palapa"])
piece("totem", DEFS["totem"], 1)
piece("maya_house", DEFS["maya_house"])
_pyr = []
_z = 0.0
for _w, _h, _m in [(27, 4.4, "stone_lt"), (22.6, 4.4, "stone"), (18, 4.4, "stone_lt"), (13.6, 4.4, "stone"), (9.4, 4.4, "stone_lt")]:
    _pyr.append(box([0, 0, _z], [_w, _w, _h], _m))
    _z += _h
_pyr += [box([0, 0, _z], [6.4, 6.4, 5.2], "stone_lt"), box([0, -3.22, _z + 0.2], [2.0, 0.1, 3.2], "black", ol=0),
         box([0, 0, _z + 5.2], [7.4, 7.4, 0.9], "secondary"), box([0, 0, _z + 6.1], [3.2, 1.2, 7.6], "stone_lt"),
         box([0, 0, _z + 13.7], [4.2, 1.4, 1.0], "primary"),
         part("wedge", [0, -10.05, 0.0], "primary", sz=[12.5, 5.0, 22.0], r=-90)]
DEFS["pc_pyr_raw"] = _pyr
piece("maya_pyramid", [use("pc_pyr_raw", [0, 0, 0], 0, sc=0.72)], [0])
piece("stela", DEFS["stela"], 1)
piece("shack_a", DEFS["shack"])
piece("shack_b", [dict(q, m="dark_wood") if q.get("m") == "primary" else q for q in DEFS["shack"]])
piece("tent", DEFS["tent"])
piece("cannon", DEFS["cannon"])
piece("barrels", [use("barrel", [0, 0, 0], 0, sc=1.4), use("barrel", [1.6, -0.8, 0], 0, sc=1.4), use("barrel", [-0.8, -1.6, 0], 0, sc=1.4)], 1)
piece("hullframe", [use("hullframe", [0, 0, 1.2], 0, sc=1.1)])
piece("rowboat", DEFS["rowboat"])
piece("skull_rock", [use("skull_rock", [0, 0, 0], 0, sc=1.3)], 1)
piece("flagpole", DEFS["pole_flag_black"], 1)
piece("roman_house", DEFS["roman_house"])
piece("hovel", DEFS["hovel"])
piece("shrine", DEFS["shrine"], 1)
piece("temple", [use("temple_front", [0, 0, 0], 0, sc=0.62)], Y4)
piece("basilica", [use("basilica", [0, 0, 0], 0, sc=0.8)], Y4)
piece("tower_rome", DEFS["tower_rome"], 1)
# walls: along local x, 6 m long, a half turn symmetric
piece("pal_wall", [cyl([x, 0, 0], 0.7, 4.8, "palisade", n=6, rad2=0.62) for x in (-2.5, -1.5, -0.5, 0.5, 1.5, 2.5)] +
      [cone([x, 0, 4.8], 0.7, 1.4, "palisade", n=6) for x in (-2.5, -1.5, -0.5, 0.5, 1.5, 2.5)] +
      [box([0, 0.55, 2.2], [6, 0.35, 0.4], "dark_wood", ol=0), box([0, 0.55, 3.6], [6, 0.35, 0.4], "dark_wood", ol=0)], 4)
piece("pal_post", [cyl([0, 0, 0], 1.0, 7.0, "dark_wood", n=6, rad2=0.85), cone([0, 0, 7.0], 1.0, 2.4, "dark_wood", n=6),
                   box([0, 0, 5.4], [0.2, 0.2, 0.2], "secondary", ol=0)], 1)
piece("pal_gate", [cyl([sx, 0, 0], 1.05, 7.4, "dark_wood", n=6) for sx in (-3.4, 3.4)] +
      [box([0, 0, 6.0], [8.6, 1.3, 1.1], "secondary"), box([0, 0, 0], [5.0, 0.4, 5.2], "plank", ol=0),
       box([0, 0, 6.2], [0.2, 0.2, 0.2], "primary", ol=0)], 4)
piece("stone_wall", [box([0, 0, 0], [6.1, 3.0, 4.4], "stone_lt"), box([0, 0, 4.4], [6.1, 3.4, 0.7], "stone")] +
      [box([x, 0, 5.1], [1.1, 3.4, 0.6], "stone") for x in (-2.4, 0, 2.4)], 4)
piece("stone_tower", [cyl([0, 0, 0], 2.9, 7.4, "stone_lt", n=8, rad2=2.6), cyl([0, 0, 7.0], 3.4, 1.0, "stone", n=8),
                      cone([0, 0, 8.0], 3.5, 3.6, "primary", n=8)], 1)
piece("stone_gate", [box([0, 0, 0], [9.0, 4.4, 7.6], "stone_lt"), box([0, -2.22, 0], [3.6, 0.1, 5.0], "black", ol=0),
                     box([0, 0, 7.6], [10, 5.2, 0.9], "stone"), box([0, -2.4, 8.5], [3.2, 0.7, 4.4], "primary")], 4)
piece("bast_wall", [box([0, 0, 0], [6.1, 4.4, 3.6], "coquina"), box([0, 0, 3.6], [6.1, 4.8, 0.6], "stone_lt")], 4)
piece("bast_point", [part("poly", None, "coquina", pts=[[-4.5, -4.2], [3.5, -4.2], [7.4, 0], [3.5, 4.2], [-4.5, 4.2]], z0=0, z1=4.0, sc0=1.0, sc1=0.96),
                     part("poly", None, "stone_lt", pts=[[-4.5, -4.2], [3.5, -4.2], [7.4, 0], [3.5, 4.2], [-4.5, 4.2]], z0=4.0, z1=4.6, sc0=1.0, sc1=1.0, ol=0),
                     use("cannon", [3.2, 0, 4.6], 0, sc=0.8)])
piece("bast_gate", [box([0, 0, 0], [9.0, 5.2, 6.2], "coquina"), box([0, -2.62, 0], [3.8, 0.1, 4.6], "black", ol=0),
                    box([0, 0, 6.2], [9.6, 5.8, 0.8], "stone_lt"), box([0, -2.8, 7.0], [3.0, 0.6, 3.6], "primary", ol=0)], 4)
# harbour
piece("quay", [box([0, 0, 0], [6.1, 3.6, 0.9], "stone_lt"), box([0, -1.75, 0], [6.1, 0.2, 0.9], "stone", ol=0),
               cyl([-2.2, -1.2, 0.9], 0.3, 0.7, "dark_wood", n=6, ol=0), cyl([2.2, -1.2, 0.9], 0.3, 0.7, "dark_wood", n=6, ol=0)])
piece("pier", [box([0, -6.0, 0.35], [3.8, 13.0, 0.5], "plank")] +
      [cyl([sx * 2.0, y, -1.5], 0.35, 2.5, "dark_wood", n=6, ol=0) for sx in (-1, 1) for y in (-1.5, -4.5, -7.5, -10.5)] +
      [use("crate", [1.0, -8.5, 0.6], 20, sc=0.9), use("barrel", [-1.0, -9.5, 0.6], 0, sc=1.2)])
piece("crane", DEFS["crane"])
piece("warehouse", DEFS["warehouse"])
piece("shed", [dict(q, m="secondary") if q.get("m") == "primary" else q for q in DEFS["warehouse"]])
piece("slipway", [part("wedge", [0, -8.0, 0.1], "plank", sz=[18, 8.4, 2.2], r=-90),
                  use("hullframe", [0, -7.0, 1.6], 90, sc=0.9)])
piece("lighthouse", [use("lighthouse_l", [0, 0, 0], 0, sc=0.8)], 1)
piece("canoe", [part("poly", None, "canoe", pts=[[-4.5, -0.9], [-1.8, -1.3], [2.2, -1.3], [4.5, -0.1], [4.5, 0.1], [2.2, 1.3], [-1.8, 1.3], [-4.5, 0.9]], z0=-0.2, z1=0.8, sc0=0.6, sc1=1.0)])
# trees (the map's palette)
piece("tree_b1", [cyl([0, 0, 0], 0.4, 3.0, "wood", n=6, rad2=0.3), sph([0, 0, 4.2], [2.7, 2.7, 2.3], "tree_g1", n=7),
                  sph([-0.6, -0.5, 5.0], [1.4, 1.4, 1.2], "tree_g2", n=6, ol=0)], 1)
piece("tree_b2", [cyl([0, 0, 0], 0.4, 2.6, "wood", n=6, rad2=0.3), sph([0, 0, 3.8], [3.2, 3.2, 2.7], "tree_g2", n=7),
                  sph([-0.7, -0.6, 4.8], [1.6, 1.6, 1.3], "tree_g1", n=6, ol=0)], 1)
DEFS["pc_palm"] = [dict(q, m="palm_leaf") if q.get("m") == "leaf" else q for q in DEFS["palm"]]
piece("palm_a", DEFS["pc_palm"], 1)
piece("palm_b", [use("pc_palm", [0, 0, 0], 140, sc=1.15)], 1)
piece("orange", [cyl([0, 0, 0], 0.3, 1.6, "wood", n=6), sph([0, 0, 2.7], [1.9, 1.9, 1.7], "orange", n=7),
                 sph([0.7, -0.9, 3.0], [0.28, 0.28, 0.28], "fruit", n=4, ol=0), sph([-0.8, -0.4, 2.4], [0.28, 0.28, 0.28], "fruit", n=4, ol=0)], 1)

# native village kit (2026-10-15): council longhouse, drying rack, stilt house, Maya temple platform
piece("longhouse", [box([0, 0, 0], [11.0, 4.6, 2.2], "mud"), roof([0, 0, 2.2], [12.4, 6.0, 3.6], "thatch", ridge=0.85),
                    box([-3.0, -2.32, 0], [1.0, 0.1, 1.5], "dark_wood", ol=0), box([3.0, -2.32, 0], [1.0, 0.1, 1.5], "dark_wood", ol=0),
                    box([5.7, 0, 0.5], [0.3, 1.6, 1.6], "dark_wood", ol=0)])
piece("rack", [cyl([sx, sy, 0], 0.22, 3.4, "dark_wood", n=5) for sx in (-1.9, 1.9) for sy in (-0.7, 0.7)] +
      [box([0, 0.7, 2.6], [4.2, 0.2, 0.2], "dark_wood", ol=0), box([0, -0.7, 2.6], [4.2, 0.2, 0.2], "dark_wood", ol=0),
       box([0, 0, 1.2], [4.0, 1.2, 0.15], "plank", ol=0)] +
      [box([x, 0, 1.4], [0.45, 0.9, 0.3], "fruit", ol=0) for x in (-1.4, -0.4, 0.6, 1.5)] +
      [box([x, 0.75, 1.9], [0.25, 0.1, 0.9], "wall_ochre", ol=0) for x in (-1.5, -0.5, 0.5, 1.5)])
piece("stilt_house", [cyl([sx, sy, 0], 0.28, 2.4, "dark_wood", n=5) for sx in (-1.8, 1.8) for sy in (-1.5, 1.5)] +
      [box([0, 0, 2.3], [4.6, 3.8, 0.3], "plank"), box([0, 0, 2.6], [3.8, 3.0, 1.7], "plank"),
       roof([0, 0, 4.3], [5.8, 4.8, 3.0], "thatch", ridge=0.85), box([0, -1.52, 2.6], [1.0, 0.1, 1.3], "dark_wood", ol=0),
       box([0, -2.6, 0.6], [0.9, 0.12, 2.2], "dark_wood", ol=0, r=[-25, 0, 0])])
piece("maya_platform", [box([0, 0, 0], [12.0, 12.0, 1.4], "stone_lt"), box([0, 0, 1.4], [9.6, 9.6, 1.4], "stone"),
                        box([0, -6.8, 0], [3.4, 1.6, 0.7], "stone"), box([0, -5.9, 0.7], [3.0, 1.4, 0.7], "stone_lt"),
                        box([0, -5.2, 1.4], [2.6, 1.2, 0.7], "stone"),
                        box([0, 0.6, 2.8], [5.0, 4.2, 2.6], "stone_lt"), box([0, -1.52, 2.8], [1.6, 0.1, 1.8], "black", ol=0),
                        roof([0, 0.6, 5.4], [6.0, 5.2, 2.4], "thatch", ridge=0.8), box([-3.6, -3.4, 2.8], [0.9, 0.6, 3.0], "primary"),
                        box([3.6, -3.4, 2.8], [0.9, 0.6, 3.0], "primary")], Y4)
# landscape trees and rocks (game/campaign/landtrees.gd): crowns and rock bodies are the primary colour (tinted per tree by the map palette), highlights the secondary, shadow sides the accent
MAT.update({"primary": [0.55, 0.64, 0.50], "secondary": [0.70, 0.78, 0.60], "primary": [0.46, 0.58, 0.48], "secondary": [0.56, 0.68, 0.54],
            "primary": [0.62, 0.64, 0.46], "primary": [0.55, 0.68, 0.45], "primary": [0.74, 0.72, 0.68], "accent": [0.58, 0.56, 0.52]})
piece("lt_b1", [cyl([0, 0, 0], 0.4, 2.6, "wood", n=6, rad2=0.3), sph([0, 0, 3.8], [3.0, 3.0, 2.6], "primary", n=7),
                sph([-0.8, -0.7, 4.9], [1.6, 1.6, 1.3], "secondary", n=6, ol=0)], 1)
piece("lt_b2", [cyl([0, 0, 0], 0.4, 2.4, "wood", n=6, rad2=0.3), sph([-0.4, 0, 3.4], [2.7, 2.6, 2.3], "primary", n=7),
                sph([1.2, 0.8, 4.0], [2.0, 2.0, 1.8], "primary", n=6), sph([-1.0, -0.9, 4.6], [1.4, 1.4, 1.2], "secondary", n=6, ol=0)], 1)
piece("lt_b3", [cyl([0, 0, 0], 0.45, 2.0, "wood", n=6, rad2=0.35), sph([0, 0, 3.1], [3.4, 3.2, 2.0], "primary", n=7),
                sph([-1.0, -0.8, 4.0], [1.7, 1.7, 1.1], "secondary", n=6, ol=0)], 1)
for _i, (_h, _r) in enumerate([(1.0, 1.0), (1.25, 0.88), (0.85, 1.12)]):
    piece("lt_pine%d" % (_i + 1), [cyl([0, 0, 0], 0.35, 1.6 * _h, "wood", n=6),
                                   cone([0, 0, 1.2 * _h], 2.7 * _r, 3.4 * _h, "primary", n=7), cone([0, 0, 3.2 * _h], 2.2 * _r, 3.1 * _h, "secondary", n=7),
                                   cone([0, 0, 5.0 * _h], 1.5 * _r, 3.0 * _h, "primary", n=7)], 1)
piece("lt_scrub1", [sph([0, 0, 1.1], [2.3, 2.1, 1.7], "primary", n=6), sph([-0.5, -0.5, 1.8], [1.2, 1.1, 0.9], "secondary", n=5, ol=0)], 1)
piece("lt_scrub2", [sph([-0.8, 0, 1.0], [1.7, 1.6, 1.4], "primary", n=6), sph([1.0, 0.5, 0.9], [1.5, 1.4, 1.2], "primary", n=6)], 1)
piece("lt_cypress", [cyl([0, 0, 0], 0.3, 1.0, "wood", n=6), cone([0, 0, 0.8], 1.5, 9.0, "primary", n=7)], 1)
piece("lt_palm1", [cyl([0, 0, 0], 0.38, 6.5, "wood", n=6, rad2=0.22, r=[0, 6, 0]), sph([0.6, 0, 6.4], [3.2, 3.2, 1.0], "primary", n=6), sph([0.6, 0, 7.1], [1.8, 1.8, 0.8], "primary", n=6)], 1)
piece("lt_palm2", [use("pc_palm_lt", [0, 0, 0], 140, sc=1.1)], 1) if False else None
DEFS["pc_palm_lt"] = [cyl([0, 0, 0], 0.38, 6.5, "wood", n=6, rad2=0.22, r=[0, -8, 0]), sph([-0.7, 0, 6.3], [3.0, 3.0, 1.0], "primary", n=6), sph([-0.7, 0, 7.0], [1.7, 1.7, 0.8], "primary", n=6)]
piece("lt_palm2", DEFS["pc_palm_lt"], 1)
piece("lt_rock1", [sph([0, 0, 0.2], [1.6, 1.4, 1.2], "primary", n=6), sph([1.0, 0.6, 0], [0.8, 0.7, 0.6], "accent", n=5)], 1)
piece("accent", [sph([0, 0, 0.1], [1.3, 1.5, 1.0], "primary", n=6), sph([-0.9, -0.5, 0], [0.7, 0.7, 0.5], "accent", n=5)], 1)
piece("lt_rock3", [sph([0, 0, 0.2], [1.9, 1.3, 0.9], "primary", n=6)], 1)
piece("lt_crag", [box([0, 0, 0], [2.4, 2.0, 3.0], "accent", r=18), box([0.8, 0.6, 0], [1.6, 1.4, 2.2], "primary", r=-25), box([-0.9, -0.6, 0], [1.2, 1.2, 1.6], "primary", r=40)], 1)

# ---------------------------------------------------------------- landmarks and growth (step 2, 2026-10-15)
# Rule of cool mixed with reality: slightly exaggerated, recognisable silhouettes. Heights are stretched by ZEX.
def rock_slab(r, h=1.2, z0=-1.0, seed=3, m="rock", n=12, jit=0.12):
    return part("poly", None, m, pts=circle(n, r, jit, seed), z0=z0, z1=h, sc0=1.08, sc1=0.94)


def poly_up(pts, z0, z1, m, sc0=1.0, sc1=1.0, **k):
    return part("poly", None, m, pts=pts, z0=z0, z1=z1, sc0=sc0, sc1=sc1, **k)


def tri(cx, cy, r, a0=-90.0):
    return [[cx + r * math.cos(math.radians(a0 + 120 * i)), cy + r * math.sin(math.radians(a0 + 120 * i))] for i in range(3)]


def diamond(cx, cy, r):
    return [[cx - r, cy], [cx, cy + r], [cx + r, cy], [cx, cy - r]]


# 1 El Morro (Havana): a triangular fortress on the headland with its lighthouse, the town side to the south
_morro = [rock_slab(17.5, 1.4, -1.2, 5, n=14, jit=0.16)]
_tr = [[-12.5, -8.0], [12.5, -8.0], [0.0, 13.5]]
_morro += [poly_up(_tr, 0.8, 6.2, "coquina", 1.0, 0.94), poly_up([[-11.0, -6.6], [11.0, -6.6], [0.0, 11.0]], 6.2, 6.9, "stone_lt", 1.0, 1.0, ol=0)]
for _x, _y in ((-12.5, -8.0), (12.5, -8.0), (0.0, 13.5)):
    _morro += [cyl([_x, _y, 0.8], 3.1, 7.2, "coquina", n=8, rad2=2.9), cyl([_x, _y, 8.0], 3.5, 0.7, "stone", n=8), cone([_x, _y, 8.7], 3.4, 3.0, "primary", n=8)]
_morro += [box([0, -8.02, 0.8], [4.2, 0.1, 3.4], "black", ol=0), box([0, 0.5, 6.9], [9.0, 7.0, 4.0], "stone_lt"), box([0, 0.5, 10.9], [9.8, 7.8, 0.8], "stone"),
           box([-2.5, -3.02, 7.6], [1.2, 0.1, 1.4], "dark_wood", ol=0), box([2.5, -3.02, 7.6], [1.2, 0.1, 1.4], "dark_wood", ol=0)]
_morro += [cyl([0, 6.2, 10.9], 2.1, 12.5, "stone_lt", n=8, rad2=1.5), cyl([0, 6.2, 23.2], 2.6, 0.8, "stone", n=8), cyl([0, 6.2, 24.0], 1.3, 2.6, "glass", n=8, ol=0),
           cone([0, 6.2, 26.6], 1.9, 2.4, "primary", n=8), cyl([-5.5, 1.0, 10.9], 0.18, 6.5, "dark_wood", n=4, ol=0), box([-4.4, 1.0, 15.2], [2.2, 0.12, 1.4], "primary", ol=0)]
_morro += [use("cannon", [-2.4, 9.8, 6.9], 0, sc=0.85), use("cannon", [2.4, 9.8, 6.9], 0, sc=0.85), use("cannon", [-8.5, -4.6, 6.9], 0, sc=0.85), use("cannon", [8.5, -4.6, 6.9], 0, sc=0.85)]
piece("morro", _morro, Y4)

# 2 La Fuerza (Havana): the old square castle with its corner bastions and the bell tower
piece("fuerza", [box([0, 0, 0], [16, 16, 5.2], "coquina"), box([0, 0, 5.2], [16.6, 16.6, 0.7], "stone_lt"), box([0, 0, 5.9], [9, 9, 3.4], "stone_lt"), box([0, 0, 9.3], [9.8, 9.8, 0.7], "stone"),
                 box([0, -8.02, 0], [3.6, 0.1, 3.0], "black", ol=0)] +
      [poly_up(diamond(sx * 8.0, sy * 8.0, 4.2), 0, 5.0, "coquina", 1.0, 0.94) for sx in (-1, 1) for sy in (-1, 1)] +
      [box([-3.0, 3.0, 10.0], [3.0, 3.0, 5.0], "stone_lt"), cone([-3.0, 3.0, 15.0], 2.5, 3.4, "primary", n=4), cyl([-3.0, 3.0, 18.2], 0.16, 3.0, "gold", n=4, ol=0),
       cyl([3.0, 0, 10.0], 0.18, 7.0, "dark_wood", n=4, ol=0), box([4.1, 0, 15.4], [2.2, 0.12, 1.4], "primary", ol=0)], [0])

# 3 Castillo San Felipe de Barajas (Cartagena): terraced bastions climbing its hill
_sf = [rock_slab(16.5, 3.2, -1.0, 7, n=12, jit=0.14, m="rock_dk"), poly_up(tri(0, 1, 14.0, 90), 2.0, 7.0, "coquina", 1.0, 0.9), poly_up(tri(0, 1, 11.5, 90), 7.0, 11.8, "stone_lt", 1.0, 0.92),
       poly_up(tri(0, 1.5, 8.5, 90), 11.8, 16.0, "coquina", 1.0, 0.92), poly_up(tri(0, 1.5, 7.2, 90), 16.0, 16.7, "stone", 1.0, 1.0, ol=0)]
_sf += [box([0, 2.0, 16.7], [5.0, 4.4, 4.0], "stone_lt"), box([0, 2.0, 20.7], [5.8, 5.2, 0.7], "stone"), box([0, -0.22, 17.4], [1.4, 0.1, 1.8], "black", ol=0),
        cyl([0, 2.0, 21.4], 0.2, 8.0, "dark_wood", n=4, ol=0), box([1.5, 2.0, 27.0], [3.0, 0.14, 1.8], "primary", ol=0)]
_sf += [use("cannon", [x, y, 7.0], 0, sc=0.8) for x, y in ((-6.0, -6.0), (6.0, -6.0), (0, -9.0))]
_sf += [part("wedge", [0, -13.5, 0.0], "stone", sz=[7.0, 3.2, 3.2], r=-90)]
piece("san_felipe", _sf, [0])

# 4 El Morro of San Juan: six tiers on the point, sentry boxes, the flag
_mj = [rock_slab(17.5, 1.4, -1.2, 9, n=14, jit=0.12)]
_mj += [box([0, 0, 0.6], [26, 14, 6.4], "coquina"), box([0, 0, 7.0], [26.8, 14.8, 0.8], "stone_lt"), box([-1.5, 1.0, 7.8], [19, 9.6, 5.0], "coquina"), box([-1.5, 1.0, 12.8], [19.8, 10.4, 0.8], "stone_lt"),
        box([-2.5, 2.0, 13.6], [11.5, 6.0, 4.6], "stone_lt"), box([-2.5, 2.0, 18.2], [12.3, 6.8, 0.8], "stone"), box([0, -7.02, 0.6], [4.4, 0.1, 3.6], "black", ol=0)]
_mj += [box([x, -7.02, 3.2], [1.0, 0.1, 1.6], "black", ol=0) for x in (-8, -4.5, 4.5, 8)] + [box([x, -5.02, 9.4], [1.0, 0.1, 1.5], "black", ol=0) for x in (-8, -4, 0, 4)]
_mj += [cyl([x, y, 7.8], 0.9, 3.0, "stone_lt", n=6) for x, y in ((-12.0, -6.4), (12.0, -6.4), (-9.5, -4.4), (9.5, -4.4))] + [cone([x, y, 10.8], 1.1, 1.2, "primary", n=6) for x, y in ((-12.0, -6.4), (12.0, -6.4), (-9.5, -4.4), (9.5, -4.4))]
_mj += [cyl([9.0, 4.4, 13.6], 1.9, 8.5, "coquina", n=8, rad2=1.6), cyl([9.0, 4.4, 22.0], 2.3, 0.7, "stone", n=8), cyl([9.0, 4.4, 22.7], 1.1, 2.0, "glass", n=8, ol=0), cone([9.0, 4.4, 24.7], 1.6, 1.8, "primary", n=8),
        cyl([-7.5, 3.0, 18.2], 0.2, 8.0, "dark_wood", n=4, ol=0), box([-6.2, 3.0, 24.0], [2.6, 0.12, 1.6], "primary", ol=0)]
_mj += [use("cannon", [x, -5.5, 7.8], 0, sc=0.85) for x in (-6.0, -2.0, 2.0, 6.0)]
piece("morro_sj", _mj, Y4)

# 5 Harbour fort (Portobelo's San Jeronimo / Santiago; every West port's first fort): square, four towers, a sea battery
piece("harbour_fort", [rock_slab(11.5, 0.9, -0.8, 11, n=12, jit=0.1, m="rock_dk"), box([0, 0, 0.5], [13, 11, 4.4], "coquina"), box([0, 0, 4.9], [13.6, 11.6, 0.7], "stone_lt"), box([0, 0.5, 5.6], [6.4, 5.4, 3.0], "stone_lt"),
                       box([0, 0.5, 8.6], [7.0, 6.0, 0.6], "stone"), box([0, -5.52, 0.5], [3.0, 0.1, 2.8], "black", ol=0)] +
      [cyl([sx * 6.5, sy * 5.5, 0.5], 2.3, 7.4, "coquina", n=8, rad2=2.1) for sx in (-1, 1) for sy in (-1, 1)] +
      [cyl([sx * 6.5, sy * 5.5, 7.9], 2.7, 0.6, "stone", n=8) for sx in (-1, 1) for sy in (-1, 1)] +
      [cone([sx * 6.5, sy * 5.5, 8.5], 2.6, 2.4, "primary", n=8) for sx in (-1, 1) for sy in (-1, 1)] +
      [cyl([0, 1.0, 9.2], 0.18, 6.0, "dark_wood", n=4, ol=0), box([1.2, 1.0, 13.4], [2.4, 0.12, 1.4], "primary", ol=0)] +
      [use("cannon", [x, -3.2, 5.6], 0, sc=0.8) for x in (-3.0, 0.0, 3.0)], [0])

# 6 Castillo de San Marcos (St Augustine): the square star fort of coquina in its moat
_sm = [box([0, 0, -0.1], [34, 34, 0.5], "water_dk", ol=0), box([0, 0, 0.3], [21, 21, 5.4], "coquina"), box([0, 0, 5.7], [21.8, 21.8, 0.8], "stone_lt"), box([0, 0, 6.5], [13.0, 13.0, 3.6], "stone_lt"), box([0, 0, 10.1], [13.8, 13.8, 0.8], "stone")]
for _sx in (-1, 1):
    for _sy in (-1, 1):
        _cx, _cy = _sx * 12.2, _sy * 12.2
        _sm += [poly_up(diamond(_cx, _cy, 6.6), 0.3, 5.2, "coquina", 1.0, 0.95), poly_up(diamond(_cx, _cy, 5.8), 5.2, 5.9, "stone_lt", 1.0, 1.0, ol=0),
                cyl([_cx, _cy, 5.9], 0.9, 2.6, "stone_lt", n=6), cone([_cx, _cy, 8.5], 1.1, 1.2, "primary", n=6)]
_sm += [box([0, -10.52, 0.3], [4.4, 0.1, 3.4], "black", ol=0), box([0, -14.0, 0.1], [3.6, 6.0, 0.4], "plank", ol=0), cyl([0, 0, 10.9], 0.22, 8.0, "dark_wood", n=4, ol=0), box([1.5, 0, 17.0], [3.0, 0.14, 1.8], "primary", ol=0)]
piece("san_marcos", _sm, [0])

# 7 Alcazar de Colon (Santo Domingo): the admiral's palace, a long arcaded block with loggias and corner towers
_ac = [box([0, 0, 0], [22, 10, 7.0], "coquina"), box([0, 0, 7.0], [22.8, 10.8, 0.7], "stone_lt"), box([0, -0.5, 7.7], [16, 8.6, 4.4], "coquina"), box([0, -0.5, 12.1], [16.8, 9.4, 0.7], "stone_lt")]
_ac += [box([x, -5.02, 0.0], [1.7, 0.1, 3.2], "black", ol=0) for x in (-8.5, -5.1, -1.7, 1.7, 5.1, 8.5)] + [box([x, -5.02, 3.4], [1.2, 0.1, 0.5], "stone", ol=0) for x in (-8.5, -5.1, -1.7, 1.7, 5.1, 8.5)]
_ac += [box([x, -4.82, 8.7], [1.0, 0.1, 1.6], "dark_wood", ol=0) for x in (-6.0, -3.0, 0, 3.0, 6.0)]
_ac += [box([sx * 11.0, 0, 0], [3.8, 7.0, 11.0], "coquina") for sx in (-1, 1)] + [box([sx * 11.0, 0, 11.0], [4.4, 7.6, 0.8], "stone_lt") for sx in (-1, 1)] + [roof([sx * 11.0, 0, 11.8], [4.6, 7.8, 2.6], "primary", ridge=0.4) for sx in (-1, 1)]
_ac += [box([0, 0.5, 12.8], [8.0, 5.0, 2.0], "stone_lt"), roof([0, 0.5, 14.8], [8.8, 5.8, 2.6], "primary", ridge=0.6)]
piece("alcazar", _ac, Y4)

# 8 San Juan de Ulua (Veracruz): the fortress on its rock island
_ul = [rock_slab(17.5, 1.2, -1.6, 13, n=14, jit=0.14), box([0, 0, 0.4], [21, 15, 4.2], "coquina"), box([0, 0, 4.6], [21.8, 15.8, 0.7], "stone_lt")]
_ul += [poly_up([[-8.0, -4.5], [4.0, -4.5], [6.0, 0], [4.0, 4.5], [-8.0, 4.5]], 5.3, 8.3, "stone_lt", 1.0, 0.96), box([-1.5, 0.8, 8.3], [9.0, 7.0, 3.8], "coquina"), box([-1.5, 0.8, 12.1], [9.8, 7.8, 0.7], "stone"), box([0, -7.52, 0.4], [3.6, 0.1, 3.0], "black", ol=0)]
_ul += [poly_up(diamond(sx * 10.5, sy * 7.5, 3.8), 0.4, 4.9, "coquina", 1.0, 0.95) for sx in (-1, 1) for sy in (-1, 1)]
_ul += [cyl([sx * 10.5, sy * 7.5, 4.9], 1.2, 3.2, "stone_lt", n=6) for sx in (-1, 1) for sy in (-1, 1)] + [cone([sx * 10.5, sy * 7.5, 8.1], 1.4, 1.4, "primary", n=6) for sx in (-1, 1) for sy in (-1, 1)]
_ul += [cyl([6.0, -0.5, 8.3], 1.7, 8.0, "stone_lt", n=8, rad2=1.4), cyl([6.0, -0.5, 16.3], 2.1, 0.7, "stone", n=8), cone([6.0, -0.5, 17.0], 1.9, 2.2, "primary", n=8),
        cyl([-5.0, 0.8, 12.8], 0.2, 7.0, "dark_wood", n=4, ol=0), box([-3.8, 0.8, 18.0], [2.6, 0.12, 1.6], "primary", ol=0),
        box([-14.0, -11.0, -0.2], [3.0, 8.0, 0.4], "plank", r=-35, ol=0)]
piece("ulua", _ul, [0])

# 9 The great Itza temple (Tayasal): a tall stepped pyramid with the roof-comb temple and its stair
_it = []
_z = 0.0
for _w, _h, _m in [(26, 4.6, "stone_lt"), (22, 4.6, "stone"), (18.4, 4.6, "stone_lt"), (15, 4.6, "stone"), (11.8, 4.6, "stone_lt"), (9.0, 4.6, "stone")]:
    _it.append(box([0, 0, _z], [_w, _w, _h], _m))
    _z += _h
_it += [box([0, 0, _z], [7.4, 6.0, 5.6], "stone_lt"), box([0, -3.02, _z + 0.1], [2.2, 0.1, 3.4], "black", ol=0), box([0, 0, _z + 5.6], [8.4, 7.0, 0.9], "primary"),
        box([0, 0.5, _z + 6.5], [4.0, 1.0, 7.0], "stone_lt"), box([0, 0.5, _z + 13.5], [5.0, 1.2, 0.9], "secondary"), box([0, -1.0, _z + 6.5], [1.2, 0.5, 1.2], "jade", ol=0),
        part("wedge", [0, -12.0, 0.0], "stone", sz=[14.0, 5.6, _z], r=-90)]
_it += [box([sx * 3.4, -4.4, _z + 0.0], [0.8, 0.8, 1.6], "jade", ol=0) for sx in (-1, 1)]
DEFS["pc_itza_raw"] = _it
piece("itza_temple", [use("pc_itza_raw", [0, 0, 0], 0, sc=0.82)], [0])

# 10 Port Royal: Fort Charles (low brick fort with a gun deck), a tavern, a gallows
piece("fort_charles", [rock_slab(12.5, 0.7, -0.8, 15, n=12, jit=0.1, m="sand"), box([0, 0, 0.2], [18, 12, 4.4], "brick"), box([0, 0, 4.6], [18.6, 12.6, 0.6], "stone_lt"), box([-3.5, 1.5, 5.2], [7.0, 6.0, 3.8], "brick"),
                      box([-3.5, 1.5, 9.0], [7.8, 6.8, 0.6], "stone_lt"), roof([-3.5, 1.5, 9.6], [8.0, 7.0, 2.8], "primary", ridge=0.5), box([0, -6.02, 0.2], [3.0, 0.1, 2.8], "black", ol=0),
                      cyl([7.2, -3.6, 0.2], 2.0, 6.4, "brick", n=8, rad2=1.9), cone([7.2, -3.6, 6.6], 2.2, 2.2, "primary", n=8), cyl([-7.0, 4.0, 4.6], 0.2, 8.0, "dark_wood", n=4, ol=0), box([-5.8, 4.0, 11.0], [2.4, 0.12, 1.5], "primary", ol=0)] +
      [use("cannon", [x, -4.4, 5.2], 0, sc=0.85) for x in (-6.5, -3.5, 0.5, 3.5)], [0])
piece("tavern", [box([0, 0, 0], [8.0, 5.6, 5.2], "wood"), box([0, 0, 5.2], [8.4, 6.0, 0.4], "dark_wood"), roof([0, 0, 5.6], [9.2, 6.8, 3.6], "primary", ridge=0.9),
                 box([0, -2.82, 0], [1.2, 0.1, 2.0], "dark_wood", ol=0), box([-2.4, -2.82, 1.2], [1.2, 0.1, 1.0], "glass", ol=0), box([2.4, -2.82, 1.2], [1.2, 0.1, 1.0], "glass", ol=0),
                 box([-2.4, -2.82, 3.4], [1.0, 0.1, 1.0], "glass", ol=0), box([2.4, -2.82, 3.4], [1.0, 0.1, 1.0], "glass", ol=0), box([0, -2.82, 3.4], [1.0, 0.1, 1.0], "glass", ol=0),
                 box([3.0, 2.0, 5.6], [1.0, 1.0, 3.6], "stone"), cyl([-4.6, -3.2, 0], 0.16, 4.8, "dark_wood", n=4, ol=0), box([-4.6, -3.2, 3.4], [0.2, 1.4, 0.9], "secondary", ol=0)] +
      [cyl([x, -3.6, 0], 0.5, 0.9, "wood", n=6) for x in (2.8, 3.8)], Y4)
piece("gallows", [box([0, 0, 0], [5.0, 4.0, 0.9], "stone"), box([0, 0, 0.9], [4.0, 3.0, 0.4], "plank"), cyl([-1.2, 0, 1.3], 0.28, 7.0, "dark_wood", n=5), box([0.2, 0, 8.0], [3.2, 0.3, 0.3], "dark_wood"),
                   box([-0.8, 0, 7.0], [0.2, 0.2, 1.5], "dark_wood", ol=0, r=[0, 30, 0]), cyl([1.4, 0, 6.2], 0.07, 1.8, "rope", n=4, ol=0), sph([1.4, 0, 5.9], [0.3, 0.3, 0.5], "black", n=5, ol=0),
                   box([1.2, 0.2, 1.3], [0.8, 0.8, 0.5], "dark_wood", ol=0)], 1)

# 11 Port-de-Paix: the rock fort on its crag; a careened ship on the beach
_rf = [poly_up(circle(9, 6.5, 0.18, 21), -0.8, 9.0, "rock_dk", 1.2, 0.78), poly_up(circle(9, 5.2, 0.15, 23), 9.0, 12.0, "rock", 1.0, 0.9),
       poly_up(circle(8, 8.4, 0.22, 25), -0.8, 2.6, "rock", 1.05, 0.9)]
_rf += [box([0, 0, 12.0], [8.0, 7.0, 2.8], "stone_lt"), box([0, 0, 14.8], [8.8, 7.8, 0.6], "stone"), box([0, -3.52, 12.0], [2.0, 0.1, 2.0], "black", ol=0), cyl([-2.8, 2.5, 14.8], 1.6, 5.0, "stone_lt", n=8, rad2=1.4),
        cone([-2.8, 2.5, 19.8], 1.9, 2.4, "primary", n=8), cyl([2.5, 1.0, 14.8], 0.16, 9.0, "dark_wood", n=4, ol=0), box([3.6, 1.0, 22.0], [2.4, 0.12, 1.6], "black", ol=0)]
_rf += [use("cannon", [x, -3.3, 14.8], 0, sc=0.7) for x in (-2.5, 0.5, 3.0)]
piece("rock_fort", _rf, [0])
_hp = hull_poly(15.0, 5.2)
piece("careened", [part("poly", None, "hull_lt", pts=_hp, z0=-1.0, z1=3.2, sc0=0.45, sc1=1.0, r=[32, 0, 0]), part("wall", None, "secondary", pts=_hp, closed=True, t=0.5, h=0.6, z0=3.2, r=[32, 0, 0]),
                   cyl([-1.0, 3.0, 2.6], 0.22, 9.0, "dark_wood", n=5, r=[-72, 0, 0]), cyl([-5.5, -2.8, 0], 0.2, 4.0, "dark_wood", n=4, r=[28, 0, 12], ol=0), cyl([4.0, -3.0, 0], 0.2, 4.0, "dark_wood", n=4, r=[28, 0, -12], ol=0),
                   box([-2.0, -3.2, 0.1], [3.0, 1.6, 0.5], "plank", ol=0), use("barrel", [3.0, -4.6, 0], 0, sc=1.2), use("crate", [5.0, -4.4, 0], 20, sc=0.9)], Y4)

# 12 Campeche's baluarte and Merida's twin-towered cathedral
_bp = [[-5.0, -4.8], [4.0, -4.8], [8.4, 0], [4.0, 4.8], [-5.0, 4.8]]
piece("baluarte", [poly_up(_bp, 0, 4.6, "coquina", 1.0, 0.96), poly_up(_bp, 4.6, 5.3, "stone_lt", 1.0, 1.0, ol=0),
                   cyl([7.0, 0, 5.3], 0.95, 2.6, "stone_lt", n=6), cone([7.0, 0, 7.9], 1.2, 1.3, "primary", n=6), use("cannon", [2.6, 0, 5.3], 0, sc=0.8), cyl([-2.0, 0, 5.3], 0.1, 5.5, "dark_wood", n=4, ol=0)], Y4)
_tc = [box([0, 0, 0], [15, 23, 11.5], "whitewash"), roof([0, 0, 11.5], [25, 16.4, 6], "primary", r=90)]
for _sx in (-1, 1):
    _tc += [box([_sx * 5.4, -14.5, 0], [6, 7, 26], "whitewash"), box([_sx * 5.4, -14.5, 26], [7, 8, 1.2], "secondary"), cone([_sx * 5.4, -14.5, 27.2], 5.2, 9.0, "primary", n=4),
            box([_sx * 5.4, -14.5, 36.0], [0.6, 0.6, 3.4], "gold"), box([_sx * 5.4, -14.5, 37.7], [2.2, 0.6, 0.6], "gold"), box([_sx * 5.4, -18.02, 14.0], [1.2, 0.1, 2.8], "dark_wood", ol=0)]
_tc += [box([0, -14.5, 0], [4.6, 7.0, 15], "whitewash"), box([0, -18.02, 0], [3.2, 0.1, 5.6], "dark_wood", ol=0), box([0, -18.0, 8.0], [3.0, 0.5, 5.0], "stone_lt", ol=0)]
DEFS["pc_tc_raw"] = _tc
piece("twin_cathedral", [use("pc_tc_raw", [0, 0, 0], 0, sc=0.78)], Y4)

# 13 Rome: Capitoline temple, Byrsa, the Cothon, Euryalus, the Acropolis, a Greek temple
_cp = [box([0, 0, 0], [26, 20, 3.2], "marble"), part("wedge", [0, -12.5, 0.0], "marble", sz=[6.0, 11.0, 3.2], r=-90), box([0, 0, 3.2], [22, 15, 1.0], "marble")]
_cp += [cyl([-9.0 + 3.6 * i, -5.6, 4.2], 0.85, 10.4, "marble", n=8, ol=0) for i in range(6)] + [cyl([-9.0 + 3.6 * i, 5.6, 4.2], 0.85, 10.4, "marble", n=8, ol=0) for i in range(6)]
_cp += [box([0, 0, 14.6], [21.5, 14, 1.3], "marble"), roof([0, 0, 15.9], [22.2, 14.8, 6.4], "marble", ridge=1.0), box([0, -5.75, 16.2], [10, 0.3, 3.6], "primary", ol=0), box([0, 0, 4.2], [14.5, 8.4, 10.4], "stone_lt", ol=0)]
_cp += [box([0, -6.0, 22.0], [3.2, 0.5, 1.4], "gold", ol=0), cyl([0, -6.0, 23.3], 0.3, 1.2, "gold", n=4, ol=0)]
DEFS["pc_cp_raw"] = _cp
piece("capitol", [use("pc_cp_raw", [0, 0, 0], 0, sc=0.72)], Y4)

_by = [poly_up(circle(16, 17.0, 0.04, 31), -0.6, 0.6, "sand", 1.04, 1.0, ol=0)]
for _i, (_r, _h, _m) in enumerate([(14.5, 4.4, "stone_lt"), (11.2, 4.4, "sand"), (8.0, 4.4, "stone_lt")]):
    _z0 = _i * 4.4
    _by += [cyl([0, 0, _z0], _r, _h, _m, n=14, rad2=_r * 0.96), cyl([0, 0, _z0 + _h - 0.1], _r + 0.5, 0.7, "stone", n=14)]
_by += [cyl([14.5 * math.cos(math.radians(a)), 14.5 * math.sin(math.radians(a)), 0], 1.5, 7.4, "stone_lt", n=8) for a in (35, 145, 215, 325)]
_by += [cone([14.5 * math.cos(math.radians(a)), 14.5 * math.sin(math.radians(a)), 7.4], 1.8, 2.4, "primary", n=8) for a in (35, 145, 215, 325)]
_by += [box([0, 0, 13.2], [8, 7, 4.2], "marble"), box([0, -3.52, 13.2], [3.0, 0.1, 3.0], "black", ol=0), roof([0, 0, 17.4], [9, 8, 3.4], "primary", ridge=0.7), part("wedge", [0, -16.0, 0.0], "stone", sz=[8.0, 4.4, 9.0], r=-90)]
piece("byrsa", _by, [0])

_ct = [cyl([0, 0, 0], 14.5, 1.0, "stone_lt", n=20), cyl([0, 0, 1.0], 11.4, 0.25, "water_dk", n=20, ol=0), cyl([0, 0, 1.0], 3.6, 1.0, "stone_lt", n=12), box([0, 0, 2.0], [3.6, 3.6, 2.8], "marble"), roof([0, 0, 4.8], [4.4, 4.4, 2.2], "primary", ridge=0.0)]
for _k in range(10):
    _a = math.radians(_k * 36 + 8)
    _ct += [box([13.4 * math.cos(_a), 13.4 * math.sin(_a), 0.2], [4.6, 3.0, 3.0], "marble", r=math.degrees(_a)), roof([13.4 * math.cos(_a), 13.4 * math.sin(_a), 3.2], [5.0, 3.6, 1.8], "primary", ridge=0.9, r=math.degrees(_a))]
for _a0 in (20, 140, 260):
    _a = math.radians(_a0)
    _ct += [part("poly", [7.4 * math.cos(_a), 7.4 * math.sin(_a), 0.0], "hull_dk", pts=hull_poly(8.0, 2.2), z0=1.0, z1=1.9, sc0=0.6, sc1=1.0, r=_a0 + 90)]
_ct += [cyl([-3.0, -14.0, 0], 1.0, 8.0, "stone_lt", n=8), cone([-3.0, -14.0, 8.0], 1.3, 1.6, "primary", n=8), cyl([3.0, -14.0, 0], 1.0, 8.0, "stone_lt", n=8), cone([3.0, -14.0, 8.0], 1.3, 1.6, "primary", n=8)]
piece("cothon", _ct, [0])

_eu = [rock_slab(17.0, 1.2, -1.0, 41, n=12, jit=0.14, m="rock"), poly_up([[-14.0, -7.0], [14.0, -7.0], [0.0, 12.0]], 1.0, 5.0, "stone_lt", 1.0, 0.96), poly_up([[-14.0, -7.0], [14.0, -7.0], [0.0, 12.0]], 5.0, 5.8, "stone", 1.04, 1.0, ol=0)]
_eu += [box([x, y, 0.4], [5.4, 5.4, 12.0], "stone_lt") for x, y in ((-14.0, -7.0), (14.0, -7.0), (0.0, 12.0))] + [box([x, y, 12.4], [6.2, 6.2, 1.0], "stone") for x, y in ((-14.0, -7.0), (14.0, -7.0), (0.0, 12.0))]
_eu += [box([x + dx, y + dy, 13.4], [1.4, 1.4, 1.2], "stone") for x, y in ((-14.0, -7.0), (14.0, -7.0), (0.0, 12.0)) for dx, dy in ((-2.0, -2.0), (2.0, -2.0), (-2.0, 2.0), (2.0, 2.0))]
_eu += [box([0, -7.02, 1.0], [4.4, 0.1, 3.6], "black", ol=0), box([0, -1.5, 5.8], [6, 5, 5.0], "stone_lt"), roof([0, -1.5, 10.8], [6.8, 5.8, 2.4], "primary", ridge=0.6), cyl([-6, 0, 5.8], 0.18, 7.0, "dark_wood", n=4, ol=0), box([-4.8, 0, 11.4], [2.4, 0.12, 1.5], "primary", ol=0)]
piece("euryalus", _eu, [0])

_ap = [poly_up(circle(14, 16.0, 0.12, 51), -1.0, 9.0, "rock", 1.1, 0.8), poly_up(circle(14, 12.6, 0.06, 52), 9.0, 9.8, "stone_lt", 1.0, 1.0, ol=0)]
_ap += [use("temple_front", [-1.0, 1.0, 9.8], 0, sc=0.62), box([8.0, -8.5, 9.8], [5.6, 3.6, 5.0], "marble"), roof([8.0, -8.5, 14.8], [6.2, 4.2, 2.2], "primary", ridge=0.9),
        part("wedge", [-3.0, -14.5, 0.0], "stone_lt", sz=[11.0, 4.0, 9.8], r=-90)]
_ap += [cyl([-11.0 * math.cos(math.radians(a)), 11.0 * math.sin(math.radians(a)), 9.8], 0.9, 3.0, "stone_lt", n=6) for a in (20, 80, 140, 200)]
piece("acropolis", _ap, [0])
piece("greek_temple", [box([0, 0, 0], [16, 11, 1.2], "stone_lt"), box([0, 0, 1.2], [14, 9, 0.8], "marble"), box([0, 0.4, 2.0], [10, 6, 7.4], "stone_lt", ol=0)] +
      [cyl([-5.4 + 2.16 * i, -3.6, 2.0], 0.55, 7.4, "marble", n=8, ol=0) for i in range(6)] + [box([0, 0, 9.4], [14, 9, 0.9], "marble"), roof([0, 0, 10.3], [14.6, 9.8, 4.0], "marble", ridge=1.0), box([0, -4.0, 10.6], [6.0, 0.3, 2.2], "primary", ol=0)], [0])

# 14 growth: burnt houses (a sack), a besieger's camp
piece("burnt", [box([0, 0, 0], [5.0, 4.0, 2.4], "black"), box([-1.2, 0.6, 2.4], [2.2, 0.3, 1.8], "dark_wood", ol=0), box([1.6, -0.8, 2.4], [0.3, 1.8, 1.2], "black", ol=0),
                box([-0.4, 0, 0.4], [3.6, 2.8, 0.5], "rock_dk", ol=0), cyl([1.8, 1.4, 0], 0.18, 3.2, "dark_wood", n=4, r=[14, 6, 0], ol=0),
                sph([0.6, 0.4, 4.0], [1.6, 1.5, 1.2], "smoke", n=5, ol=0), sph([1.0, 0.7, 6.0], [1.9, 1.7, 1.5], "smoke", n=5, ol=0), sph([1.5, 1.2, 8.3], [2.2, 2.0, 1.7], "smoke", n=5, ol=0)], Y4)
piece("camp_tent", [roof([0, 0, 0], [5.6, 4.4, 3.4], "sail", ridge=1.0), box([0, -2.25, 0], [1.3, 0.12, 2.0], "dark_wood", ol=0),
                    box([0, -2.2, 2.3], [1.5, 0.1, 0.5], "primary", ol=0), cyl([3.0, 0, 0], 0.1, 5.2, "dark_wood", n=4, ol=0),
                    box([3.0, 0, 4.0], [0.1, 1.3, 0.8], "primary", ol=0), box([3.0, 0.9, 4.0], [0.1, 0.9, 0.5], "secondary", ol=0)], Y4)
MAT.update({"flame": [1.0, 0.62, 0.15], "earth": [0.46, 0.34, 0.2], "ash": [0.18, 0.16, 0.15]})
piece("camp_fire", [cyl([0, 0, 0], 1.3, 0.4, "rock_dk", n=7), cyl([0, 0, 0.3], 0.9, 0.2, "ash", n=7, ol=0),
                    box([0, 0, 0.5], [1.8, 0.35, 0.35], "dark_wood", ol=0, r=[0, 0, 40]), box([0, 0, 0.7], [1.8, 0.35, 0.35], "dark_wood", ol=0, r=[0, 0, -40]),
                    cone([0, 0, 0.6], 0.8, 2.4, "flame", n=5, ol=0)], 1)
piece("camp_stakes", [cyl([x * 1.1, 0.2 * ((x % 2) * 2 - 1), 0], 0.28, 3.2, "palisade", n=4, r=[0, 0, 0]) for x in range(-3, 4)] +
      [box([0, 0, 0.5], [7.6, 0.25, 0.25], "dark_wood", ol=0)], Y4)
piece("camp_earth", [box([0, 0, 0], [7.0, 2.4, 1.2], "earth"), box([0, 0.4, 1.2], [7.0, 1.2, 0.5], "earth", ol=0),
                     cyl([-2.6, -1.5, 0], 0.7, 1.9, "palisade", n=6), cyl([0, -1.5, 0], 0.7, 1.9, "palisade", n=6), cyl([2.6, -1.5, 0], 0.7, 1.9, "palisade", n=6)], Y4)
piece("camp_flag", [cyl([0, 0, 0], 0.28, 11, "dark_wood", n=6), box([-3.0, 0, 6.8], [6.0, 0.16, 3.8], "primary"), box([-3.0, 0, 8.6], [6.02, 0.18, 1.2], "secondary", ol=0)], 1)

for _nm, _yaws in PIECES:
    for _k in (range(_yaws) if isinstance(_yaws, int) else _yaws):
        S["p_%s__y%d" % (_nm, _k)] = {"name": "p_%s y%d" % (_nm, _k), "zex": ZEX, "frame": "auto",
                                      "parts": [{"use": "pc_" + _nm, "p": [0, 0, 0], "r": 45.0 * _k}]}
json.dump({"pieces": PIECES}, open(os.path.join(HERE, "pieces.json"), "w"))

OLD["defs"] = DEFS
OLD["structures"] = S
json.dump(OLD, open(SPEC_PATH, "w"), separators=(",", ":"))
print("structures:", len(S), "defs:", len(DEFS))
