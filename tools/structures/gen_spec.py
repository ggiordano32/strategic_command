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

OLD["defs"] = DEFS
OLD["structures"] = S
json.dump(OLD, open(SPEC_PATH, "w"), separators=(",", ":"))
print("structures:", len(S), "defs:", len(DEFS))
