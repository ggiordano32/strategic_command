"""The sea battle's ship models for the 3D view (stage D2 part 3, 2026-11-09; docs/design/art_pipeline.md "The ship models and the one
ship look"). Runs inside Blender: builds each row's hull, deck, castles, gunports and (for the galleys) the outrigger frame, bow
ram and stern post from the same plans gen_spec.py's ship_parts and galley_parts draw for the overworld's ships (the sloop's low
hull and raked mast, the frigate's gun deck, the galleon's high stern castle, the line's three decks, the war canoe's dugout; the
galleys' long narrow hulls) but as lofted hulls with real sections and sheer, at the sea screen's own size (the sim's length and beam
times VIS 1.5, the freeboard and mast height of game/sea_ship3d.gd `dims`). Masts, yards and sails are NOT in the model (the rig is
dynamic: game/sea_ship3d.gd), nor are a galley's oars and corvus (the oars' MultiMesh, part 4).

Per model: one mesh in the ship's frame as the game wants it (x forward, y up, z to starboard, metres, waterline y 0), the corners
carry an atlas UV, the mask class in UV2.x (1.0 none, 0.7 the faction's colour, 0.4 gilding the treasure galleon's gold replaces) and a
baked ambient occlusion in UV2.y (rays against the model itself, mathutils BVH). One shared albedo atlas of painted swatches
(planks, deck, pale wood, gold, bronze, dark, window) is painted here with numpy.

    ~/.local/bin/blender -b --factory-startup -P tools/battlekit/export_ships.py -- [--out DIR] [--only a,b]
    godot --headless --path . --script res://tools/battlekit/ships3d_res.gd [-- --frames=DIR]
"""
import bpy
import json
import math
import os
import sys

import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
VIS = 2.0
# row: key -> (len, beam, kind) from sim/sea_types.gd (metres at 1 x)
ROWS = {
    "sloop": (20, 6, "sloop"), "brigantine": (26, 7, "brigantine"), "frigate": (40, 10, "frigate"), "galleon": (44, 13, "galleon"),
    "ship_of_the_line": (54, 15, "line"), "war_canoe": (13, 3, "canoe"), "lembos": (20, 4, "galley"), "trireme": (37, 6, "galley"),
    "quinquereme": (45, 7, "galley"), "quinquereme_p": (45, 7, "galley"),
}
GUNS = {"sloop": 4, "brigantine": 6, "frigate": 28, "galleon": 30, "ship_of_the_line": 74}
# the atlas: 4 x 4 swatches of 64 px; (column, row)
REG = {"hull_lo": 0, "hull": 1, "deck": 2, "mask": 3, "dark": 4, "gold": 5, "pale": 6, "window": 7, "bronze": 8, "canoe": 9, "bone": 10,
       "wood_dk": 11, "wale": 12}
MASK_FACTION, MASK_GILT, MASK_NONE = 0.7, 0.4, 1.0


def clamp(v, a, b):
    return max(a, min(b, v))


def dims(key):
    ln, bm, kind = ROWS[key]
    ln *= VIS
    bm *= VIS
    return ln, bm, clamp(bm * 0.28, 0.9, 3.6), clamp(ln * 0.46, 8.0, 27.0)


class M:
    """A mesh in the ship's frame: corners (position, atlas uv, mask, group) and triangles; normals smoothed over shared corners."""

    def __init__(self):
        self.p, self.uv, self.mk, self.f = [], [], [], []

    def v(self, pos, reg, u, w, mask=MASK_NONE):
        c, r = REG[reg] % 4, REG[reg] // 4
        self.p.append(Vector(pos))
        self.uv.append(((c + 0.06 + 0.88 * clamp(u, 0, 1)) / 4.0, (r + 0.06 + 0.88 * clamp(w, 0, 1)) / 4.0))
        self.mk.append(mask)
        return len(self.p) - 1

    def tri(self, a, b, c):
        self.f.append((a, b, c))

    def quad(self, a, b, c, d):
        self.f.append((a, b, c))
        self.f.append((a, c, d))

    def box(self, ctr, sz, reg="pale", mask=MASK_NONE, taper=1.0):
        """An axis box; faces not shared (flat). `taper` narrows the top (z) of the box."""
        hx, hy, hz = sz[0] / 2, sz[1] / 2, sz[2] / 2
        x0, x1, y0, y1, z0, z1 = ctr[0] - hx, ctr[0] + hx, ctr[1] - hy, ctr[1] + hy, ctr[2] - hz, ctr[2] + hz
        tz = hz * taper
        faces = [
            ([x0, y1, ctr[2] - tz], [x1, y1, ctr[2] - tz], [x1, y1, ctr[2] + tz], [x0, y1, ctr[2] + tz]),   # top
            ([x0, y0, z1], [x1, y0, z1], [x1, y1, ctr[2] + tz], [x0, y1, ctr[2] + tz]),                     # starboard
            ([x1, y0, z0], [x0, y0, z0], [x0, y1, ctr[2] - tz], [x1, y1, ctr[2] - tz]),                     # port
            ([x1, y0, z1], [x1, y0, z0], [x1, y1, ctr[2] - tz], [x1, y1, ctr[2] + tz]),                     # bow end
            ([x0, y0, z0], [x0, y0, z1], [x0, y1, ctr[2] + tz], [x0, y1, ctr[2] - tz]),                     # stern end
        ]
        for fi, f in enumerate(faces):
            r = "deck" if fi == 0 and reg == "pale" else reg
            ids = [self.v(q, r, (q[0] - x0) / max(x1 - x0, 0.01), (q[2] - z0) / max(z1 - z0, 0.01) if fi == 0 else (q[1] - y0) / max(y1 - y0, 0.01), mask)
                   for q in f]
            # winding: counter-clockwise seen from outside (checked by the normal against the face's centre)
            self._outward(ids, ctr)

    def _outward(self, ids, ctr):
        a, b, c, d = [self.p[i] for i in ids]
        n = (b - a).cross(c - a)
        cen = (a + b + c + d) / 4.0
        if n.dot(cen - Vector(ctr)) < 0:
            ids = ids[::-1]
        self.quad(*ids)

    def bar(self, p0, p1, w, reg="wood_dk", mask=MASK_NONE, sides=5):
        a, b = Vector(p0), Vector(p1)
        d = (b - a)
        if d.length < 1e-6:
            return
        d.normalize()
        up = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
        s = d.cross(up).normalized()
        t = d.cross(s).normalized()
        ring = []
        for k in range(sides):
            ang = 2 * math.pi * k / sides
            off = (s * math.cos(ang) + t * math.sin(ang)) * w / 2
            ring.append((a + off, b + off))
        ia = [self.v(r[0], reg, k / sides, 0.0, mask) for k, r in enumerate(ring)] + [self.v(ring[0][0], reg, 1.0, 0.0, mask)]
        ib = [self.v(r[1], reg, k / sides, 1.0, mask) for k, r in enumerate(ring)] + [self.v(ring[0][1], reg, 1.0, 1.0, mask)]
        for k in range(sides):
            self.quad(ia[k + 1], ia[k], ib[k], ib[k + 1])
        ca = self.v(a, reg, 0.5, 0.5, mask)
        cb = self.v(b, reg, 0.5, 0.5, mask)
        for k in range(sides):
            self.tri(ca, ia[k], ia[k + 1])
            self.tri(cb, ib[k + 1], ib[k])

    def cone(self, base, tip, rad, reg="bronze", mask=MASK_NONE, sides=6):
        a, b = Vector(base), Vector(tip)
        d = (b - a).normalized()
        up = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
        s = d.cross(up).normalized()
        t = d.cross(s).normalized()
        ring = [self.v(a + (s * math.cos(2 * math.pi * k / sides) + t * math.sin(2 * math.pi * k / sides)) * rad, reg, k / sides, 0, mask)
                for k in range(sides + 1)]
        tp = self.v(b, reg, 0.5, 1.0, mask)
        for k in range(sides):
            self.tri(ring[k], ring[k + 1], tp)
        cb = self.v(a, reg, 0.5, 0.0, mask)
        for k in range(sides):
            self.tri(cb, ring[k + 1], ring[k])

    def finish(self):
        """Triangles' normals (area weighted, smoothed over shared corners), the baked AO, the export arrays."""
        n = len(self.p)
        nrm = [Vector((0, 0, 0)) for _ in range(n)]
        for a, b, c in self.f:
            fn = (self.p[b] - self.p[a]).cross(self.p[c] - self.p[a])
            for i in (a, b, c):
                nrm[i] += fn
        nrm = [q.normalized() if q.length > 1e-9 else Vector((0, 1, 0)) for q in nrm]
        bvh = BVHTree.FromPolygons([tuple(q) for q in self.p], self.f)
        ao = []
        rng = np.random.default_rng(7)
        dirs = []
        for _ in range(14):
            v = rng.normal(size=3)
            dirs.append(Vector(v / np.linalg.norm(v)))
        for i in range(n):
            o = self.p[i] + nrm[i] * 0.05
            hits = 0
            for d in dirs:
                if d.dot(nrm[i]) < 0:
                    d = -d
                if bvh.ray_cast(o, d, 5.0)[0] is not None:
                    hits += 1
            ao.append(1.0 - hits / len(dirs))
        # Below the waterline the paint darkens (wet), the keel more.
        return nrm, ao


def station_profile(u, key, ln, bm, fb):
    """Half breadth and sheer (rail height) at u (0 stern .. 1 bow)."""
    kind = ROWS[key][2]
    tab = {"galley": [(0, 0.55), (0.06, 0.82), (0.2, 1.0), (0.62, 1.0), (0.82, 0.8), (0.94, 0.42), (1.0, 0.04)],
           "canoe": [(0, 0.2), (0.08, 0.6), (0.25, 0.95), (0.6, 1.0), (0.82, 0.7), (0.94, 0.3), (1.0, 0.06)],
           }.get(kind, [(0, 0.66), (0.07, 0.86), (0.18, 0.98), (0.55, 1.0), (0.78, 0.84), (0.92, 0.5), (1.0, 0.05)])
    hb = tab[-1][1]
    for i in range(len(tab) - 1):
        if tab[i][0] <= u <= tab[i + 1][0]:
            t = (u - tab[i][0]) / (tab[i + 1][0] - tab[i][0])
            hb = tab[i][1] + (tab[i + 1][1] - tab[i][1]) * t
    sheer = 1.0 + (0.34 if kind != "galley" else 0.18) * (abs(u - 0.45) * 2) ** 2 * (1.15 if u > 0.45 else 0.8)
    if kind == "canoe":
        sheer = 1.0 + 0.9 * max(0.0, abs(u - 0.5) * 2 - 0.55) ** 1.4 * 2.2
    return hb * bm / 2.0, fb * sheer


def build(key):
    ln, bm, fb, mh = dims(key)
    kind = ROWS[key][2]
    m = M()
    draft = min(1.5, bm * 0.2)
    if kind == "canoe":
        draft = 0.5
    N = 26
    tumble = {"galleon": 0.84, "line": 0.86, "frigate": 0.9}.get(kind, 0.96)
    # profile rows (y fraction of fb, z fraction of the half breadth, region)
    if kind == "canoe":
        prof = [(-draft, 0.15), (-draft * 0.5, 0.65), (0.0, 0.95), (fb * 0.6, 1.0), (fb, 0.96)]
    else:
        prof = [(-draft, 0.14), (-draft * 0.55, 0.66), (0.0, 0.93), (fb * 0.22, 1.0), (("r", -0.55), 0.99 * tumble + 0.01), (("r", 0.0), tumble)]   # ("r", d): the rail's height plus d
    secs = []
    for i in range(N + 1):
        u = i / N
        hb, rail = station_profile(u, key, ln, bm, fb)
        x = (u - 0.5) * ln
        rows = []
        for j, (y, zf) in enumerate(prof):
            yy = rail + y[1] if isinstance(y, tuple) else y
            if kind == "canoe" and j == 4:
                yy = rail
            if kind == "canoe" and j == 3:
                yy = min(rail * 0.7, fb * 0.6 + (rail - fb) * 0.5)
            rows.append((x, yy, hb * zf))
        secs.append(rows)
    nrows = len(prof)
    # --- the hull shell: bands (j, j+1) per side
    for sd in (1.0, -1.0):
        for j in range(nrows - 1):
            if kind == "canoe":
                reg, mask = "canoe", MASK_NONE
            else:
                reg = "hull_lo" if j < 2 else ("wale" if j == 2 else "hull")
                mask = MASK_NONE
                if j == nrows - 2:
                    reg, mask = "mask", MASK_FACTION
            ids = {}
            for i in range(N + 1):
                for jj in (j, j + 1):
                    x, y, z = secs[i][jj]
                    ids[(i, jj)] = m.v((x, y, z * sd), reg, i / N, (y + draft) / (fb * 2.2 + draft), mask)
            for i in range(N):
                a, b, c, d = ids[(i, j)], ids[(i + 1, j)], ids[(i + 1, j + 1)], ids[(i, j + 1)]
                m.quad(a, b, c, d) if sd > 0 else m.quad(a, d, c, b)
    # keel line closing the bottom (the section's lowest points meet on the centreline)
    ids = [m.v((secs[i][0][0], secs[i][0][1], 0.0), "hull_lo", i / N, 0.0) for i in range(N + 1)]
    for sd in (1.0, -1.0):
        row = [m.v((secs[i][0][0], secs[i][0][1], secs[i][0][2] * sd), "hull_lo", i / N, 0.0) for i in range(N + 1)]
        for i in range(N):
            m.quad(ids[i], ids[i + 1], row[i + 1], row[i]) if sd > 0 else m.quad(ids[i], row[i], row[i + 1], ids[i + 1])
    # --- the deck (a strip between the inner rails) and the bulwark's inner wall
    inner = 0.93
    dz = []
    for i in range(N + 1):
        x, y, z = secs[i][nrows - 1]
        dz.append((x, y - 0.32, z * inner))
    dv = [(m.v((x, y, zz), "deck", i / N, 0.0), m.v((x, y, -zz), "deck", i / N, 1.0)) for i, (x, y, zz) in enumerate(dz)]
    for i in range(N):
        a, b = dv[i], dv[i + 1]
        m.quad(a[0], a[1], b[1], b[0])
    for sd in (1.0, -1.0):
        w0 = [m.v((secs[i][nrows - 1][0], secs[i][nrows - 1][1], secs[i][nrows - 1][2] * sd), "wood_dk", i / N, 1.0) for i in range(N + 1)]
        w1 = [m.v((dz[i][0], dz[i][1], dz[i][2] * sd), "wood_dk", i / N, 0.0) for i in range(N + 1)]
        for i in range(N):
            m.quad(w0[i], w1[i], w1[i + 1], w0[i + 1]) if sd > 0 else m.quad(w0[i], w0[i + 1], w1[i + 1], w1[i])
        # the rail's top: a strip of the faction colour
        rt0 = [m.v((secs[i][nrows - 1][0], secs[i][nrows - 1][1] + 0.02, secs[i][nrows - 1][2] * sd), "mask", i / N, 0.0, MASK_FACTION) for i in range(N + 1)]
        rt1 = [m.v((dz[i][0], dz[i][1] + 0.34, dz[i][2] * sd), "mask", i / N, 1.0, MASK_FACTION) for i in range(N + 1)]
        for i in range(N):
            m.quad(rt0[i], rt1[i], rt1[i + 1], rt0[i + 1]) if sd > 0 else m.quad(rt0[i], rt0[i + 1], rt1[i + 1], rt1[i])
    # --- the transom: the stern section's polygon (a fan)
    ring = []
    for sd in (1.0, -1.0):
        order = range(nrows) if sd > 0 else range(nrows - 1, -1, -1)
        for j in order:
            x, y, z = secs[0][j]
            ring.append(m.v((x, y, z * sd), "pale" if kind != "canoe" else "canoe", 0.5 + 0.5 * z * sd / max(bm, 1), (y + draft) / (fb * 2.2 + draft)))
    cc = m.v((secs[0][0][0], (secs[0][nrows - 1][1] - draft) / 2.0, 0.0), "pale" if kind != "canoe" else "canoe", 0.5, 0.5)
    for k in range(len(ring)):
        m.tri(cc, ring[(k + 1) % len(ring)], ring[k])
    # --- the bow's stem post (a bar from the keel up to the rail), the bowsprit and the galley's ram
    xb = ln * 0.5
    if kind in ("sloop", "brigantine", "frigate", "galleon", "line"):
        m.bar((xb - 0.4, fb * 0.8, 0), (xb + ln * 0.2, fb + ln * 0.05, 0), max(0.5, bm * 0.05), "wood_dk")
    if kind in ("galleon", "line"):
        m.box((xb - 0.8, fb * 0.5, 0), (2.4, fb * 0.9, bm * 0.12), "pale")   # the beakhead's knee
    # --- gunports (dark quads on the hull side) and rows
    gun_total = GUNS.get(key, 0)
    rows_n = 3 if kind == "line" else (2 if kind == "galleon" else 1)
    if gun_total > 0:
        per_row = max(2, min(9, gun_total // 2 // rows_n))
        for r in range(rows_n):
            yr = fb * (0.2 + 0.28 * r) if rows_n > 1 else fb * 0.2
            for k in range(per_row):
                f = (k + 0.5) / per_row
                u = 0.2 + 0.58 * f
                hb, rail = station_profile(u, key, ln, bm, fb)
                # the half breadth of the hull at height yr: between the wale rows
                zr = hb * 1.0 * (0.99 if yr > fb * 0.38 else 0.96)
                pw = max(bm * 0.05, 0.45)
                ph = pw * 1.15
                x = (u - 0.5) * ln
                for sd in (1.0, -1.0):
                    z = zr * sd * 1.012
                    a = m.v((x - pw, yr, z), "dark", 0, 0)
                    b = m.v((x + pw, yr, z), "dark", 1, 0)
                    c = m.v((x + pw, yr + ph, z), "dark", 1, 1)
                    d = m.v((x - pw, yr + ph, z), "dark", 0, 1)
                    m.quad(a, b, c, d) if sd > 0 else m.quad(a, d, c, b)
                    # the gun's muzzle run out of the port: a short dark barrel
                    m.bar((x, yr + ph * 0.5, z * 0.985), (x, yr + ph * 0.5, z * 1.0 + sd * 0.7), pw * 1.1, "dark", sides=6)
    # --- castles and the class's features
    xs = -ln * 0.5
    if kind == "sloop":
        m.box((xs + ln * 0.14, fb + 0.2, 0), (ln * 0.2, 0.7, bm * 0.5), "wood_dk")
    elif kind == "brigantine":
        m.box((xs + ln * 0.15, fb + 0.45, 0), (ln * 0.22, 1.1, bm * 0.62), "pale")
    elif kind == "frigate":
        m.box((xs + ln * 0.14, fb + 0.7, 0), (ln * 0.24, 1.5, bm * 0.7), "pale", taper=0.92)
        m.box((xs + ln * 0.14, fb + 1.33, 0), (ln * 0.25, 0.2, bm * 0.74), "mask", MASK_FACTION)
        m.box((xb - ln * 0.1, fb + 0.35, 0), (ln * 0.14, 0.8, bm * 0.55), "pale")
    elif kind == "galleon":
        m.box((xs + ln * 0.17, fb + 1.1, 0), (ln * 0.3, 2.4, bm * 0.76), "pale", MASK_GILT, taper=0.9)
        m.box((xs + ln * 0.15, fb + 2.8, 0), (ln * 0.22, 1.7, bm * 0.62), "pale", MASK_GILT, taper=0.9)
        m.box((xs + ln * 0.15, fb + 3.5, 0), (ln * 0.25, 0.2, bm * 0.66), "mask", MASK_FACTION)
        m.box((xs + 0.2, fb + 1.2, 0), (0.4, 0.5, bm * 0.7), "gold")
        m.box((xs + 0.2, fb + 2.6, 0), (0.4, 0.4, bm * 0.55), "gold")
        m.box((xb - ln * 0.09, fb + 0.55, 0), (ln * 0.16, 1.2, bm * 0.55), "pale")
        for k in range(-2, 3):   # the stern windows
            m.box((xs - 0.05, fb + 1.2, k * bm * 0.12), (0.2, 0.7, bm * 0.07), "window")
    elif kind == "line":
        m.box((xs + ln * 0.17, fb + 1.3, 0), (ln * 0.3, 2.6, bm * 0.78), "pale", taper=0.92)
        m.box((xs + ln * 0.15, fb + 3.1, 0), (ln * 0.22, 1.2, bm * 0.64), "pale", taper=0.92)
        m.box((xs + ln * 0.15, fb + 3.55, 0), (ln * 0.25, 0.2, bm * 0.7), "mask", MASK_FACTION)
        m.box((xs + 0.2, fb * 0.9, 0), (0.4, 0.5, bm * 0.76), "gold", MASK_GILT)
        m.box((xs + 0.2, fb * 1.6, 0), (0.4, 0.4, bm * 0.7), "gold", MASK_GILT)
        m.box((xb - ln * 0.09, fb + 0.7, 0), (ln * 0.17, 1.5, bm * 0.58), "pale")
        for k in range(-2, 3):
            m.box((xs - 0.05, fb + 1.3, k * bm * 0.13), (0.2, 0.8, bm * 0.08), "window")
        # the gilt stripes along the sides between the gun decks
        for sd in (1.0, -1.0):
            ids = []
            for i in range(N + 1):
                hb, rail = station_profile(i / N, key, ln, bm, fb)
                x = (i / N - 0.5) * ln
                ids.append((m.v((x, fb * 0.5, hb * 1.013 * sd), "gold", i / N, 0, MASK_GILT), m.v((x, fb * 0.5 + 0.36, hb * 1.013 * sd), "gold", i / N, 1, MASK_GILT)))
            for i in range(N):
                a, b = ids[i], ids[i + 1]
                m.quad(a[0], b[0], b[1], a[1]) if sd > 0 else m.quad(a[0], a[1], b[1], b[0])
    elif kind == "galley":
        # the outrigger: a rail either side of the hull carrying the oar ports
        for sd in (1.0, -1.0):
            ids = []
            for i in range(2, N - 1):
                hb, rail = station_profile(i / N, key, ln, bm, fb)
                x = (i / N - 0.5) * ln
                ids.append((m.v((x, fb * 0.55, hb * 0.98 * sd), "wood_dk", i / N, 0), m.v((x, fb * 0.8, (hb + 0.8) * sd), "pale", i / N, 1),
                            m.v((x, fb * 0.55, (hb + 0.8) * sd), "wood_dk", i / N, 0.5)))
            for k in range(len(ids) - 1):
                a, b = ids[k], ids[k + 1]
                m.quad(a[0], b[0], b[1], a[1]) if sd > 0 else m.quad(a[0], a[1], b[1], b[0])
                m.quad(a[1], b[1], b[2], a[2]) if sd > 0 else m.quad(a[1], a[2], b[2], b[1])
            # oar ports along it
            pairs = {"lembos": 5, "trireme": 8, "quinquereme": 9, "quinquereme_p": 9}[key]
            for k in range(pairs):
                u = 0.18 + 0.58 * (k + 0.5) / pairs
                hb, rail = station_profile(u, key, ln, bm, fb)
                x = (u - 0.5) * ln
                z = (hb + 0.8) * sd
                m.box((x, fb * 0.67, z), (0.5, 0.4, 0.14), "dark")
        # the stern post curving up and forward; the stern cabin; the bronze ram and the painted eye
        pts = [(xs + 0.2, fb, 0), (xs - 0.4, fb + 1.3, 0), (xs - 0.3, fb + 2.4, 0), (xs + 0.6, fb + 3.2, 0), (xs + 1.5, fb + 3.5, 0)]
        for k in range(len(pts) - 1):
            m.bar(pts[k], pts[k + 1], 0.55, "pale")
        m.box((xs + 1.7, fb + 3.5, 0), (1.4, 0.4, 0.5), "gold", MASK_GILT)
        m.box((xs + ln * 0.12, fb + 0.8, 0), (ln * 0.16, 1.6, bm * 0.55), "pale")
        m.box((xs + ln * 0.12, fb + 1.45, 0), (ln * 0.19, 0.2, bm * 0.6), "mask", MASK_FACTION)
        if ROWS[key][0] >= 37:
            m.box((0, fb + 0.2, 0), (ln * 0.5, 0.4, bm * 0.18), "deck")   # the gangway
        if key != "lembos":
            m.box((xb - ln * 0.08, fb + 0.7, 0), (ln * 0.1, 1.2, bm * 0.4), "pale")
        m.cone((xb - 0.2, 0.15, 0), (xb + bm * 0.55 + 1.2, -0.25, 0), 0.5 + bm * 0.05, "bronze")
        m.cone((xb - 0.6, 0.55, bm * 0.2), (xb + 0.7, 0.45, bm * 0.2), 0.14, "bronze")
        m.cone((xb - 0.6, 0.55, -bm * 0.2), (xb + 0.7, 0.45, -bm * 0.2), 0.14, "bronze")
        for sd in (1.0, -1.0):
            m.box((xb - ln * 0.07, fb * 0.8, (station_profile(0.93, key, ln, bm, fb)[0] + 0.02) * sd), (0.9, 0.7, 0.1), "bone")
    elif kind == "canoe":
        # thwarts across, the high prow and stern, and the inner floor
        for k in range(5):
            x = -ln * 0.3 + k * ln * 0.15
            hb, rail = station_profile(0.2 + 0.15 * k + 0.1, key, ln, bm, fb)
            m.box((x, fb * 0.55, 0), (0.28, 0.12, hb * 1.8), "wood_dk")
        m.box((xb - 0.3, fb * 1.9, 0), (0.7, 1.7, 0.5), "canoe")
        m.box((xs + 0.3, fb * 1.5, 0), (0.6, 1.2, 0.45), "canoe")
        m.box((xb - 0.5, fb * 1.1, 0), (0.5, 0.5, bm * 0.5), "mask", MASK_FACTION)
    # a hatch and a capstan on deck for the sailing ships
    if kind in ("frigate", "galleon", "line"):
        m.box((ln * 0.02, fb + 0.1, 0), (ln * 0.12, 0.35, bm * 0.34), "wood_dk")
        m.bar((ln * 0.2, fb - 0.2, 0), (ln * 0.2, fb + 0.9, 0), 0.7, "wood_dk", sides=6)
    return m, (ln, bm, fb, mh)


def paint_atlas(path):
    rng = np.random.default_rng(11)
    S = 64
    img = np.zeros((S * 4, S * 4, 4), np.float32)
    img[..., 3] = 1.0

    def planks(base, vert=False, n=7, jitter=0.07, joint=0.0):
        t = np.zeros((S, S, 3), np.float32)
        for k in range(n):
            a, b = int(k * S / n), int((k + 1) * S / n)
            tone = 1.0 + rng.uniform(-jitter, jitter)
            t[a:b] = np.array(base) * tone
            t[a:a + 1] *= 0.62   # the seam
            grain = rng.normal(0, 0.025, (b - a, S, 1))
            t[a:b] += grain
            if joint > 0:
                x = int(rng.uniform(0.1, 0.9) * S)
                t[a:b, x:x + 1] *= 0.7
        return np.clip(t.swapaxes(0, 1) if vert else t, 0, 1)

    def put(reg, arr):
        c, r = REG[reg] % 4, REG[reg] // 4
        img[r * S:(r + 1) * S, c * S:(c + 1) * S, :3] = arr
    put("hull_lo", planks((0.36, 0.16, 0.10), n=9))   # the reference kits' mahogany below the wale (OcCre Endeavour, Santa Maria)
    put("wale", planks((0.07, 0.08, 0.08), n=3, jitter=0.02))
    put("hull", planks((0.78, 0.56, 0.22), n=9, joint=1))   # the yellow-ochre topsides of the Endeavour
    put("deck", planks((0.74, 0.60, 0.40), vert=True, n=8, joint=1))
    put("mask", planks((0.60, 0.60, 0.60), n=6, jitter=0.03))
    put("dark", np.full((S, S, 3), 0.05, np.float32) + rng.normal(0, 0.01, (S, S, 3)))
    g = np.full((S, S, 3), (0.92, 0.72, 0.22), np.float32)
    g *= (0.9 + 0.1 * np.sin(np.arange(S) * 0.7))[None, :, None]
    put("gold", g)
    put("pale", planks((0.66, 0.52, 0.34), n=6, jitter=0.05))
    win = np.full((S, S, 3), (0.95, 0.85, 0.5), np.float32)
    win[:4] = 0.1
    win[-4:] = 0.1
    win[:, :4] = 0.1
    win[:, -4:] = 0.1
    win[:, S // 2 - 2:S // 2 + 2] = 0.1
    put("window", win)
    put("bronze", np.clip(np.full((S, S, 3), (0.72, 0.48, 0.22), np.float32) + rng.normal(0, 0.03, (S, S, 3)), 0, 1))
    put("canoe", planks((0.46, 0.29, 0.15), vert=True, n=5, jitter=0.1))
    put("bone", np.full((S, S, 3), (0.92, 0.9, 0.82), np.float32))
    put("wood_dk", planks((0.28, 0.19, 0.11), n=5))
    im = bpy.data.images.new("ships3d", S * 4, S * 4, alpha=True)
    im.colorspace_settings.name = "Non-Color"
    im.pixels[:] = img[::-1].ravel()   # (Blender's rows run bottom up)
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()


def export(key, out):
    m, (ln, bm, fb, mh) = build(key)
    nrm, ao = m.finish()
    V, Nn, UV, C, A = [], [], [], [], []
    for i, p in enumerate(m.p):
        V += [round(p.x, 3), round(p.y, 3), round(p.z, 3)]
        Nn += [round(nrm[i].x, 3), round(nrm[i].y, 3), round(nrm[i].z, 3)]
        UV += [round(m.uv[i][0], 4), round(m.uv[i][1], 4)]
        C.append(m.mk[i])
        # the keel wet and dark below the waterline, the occlusion's contrast eased
        wet = 0.75 if p.y < -0.05 else 1.0
        A.append(round((0.55 + 0.45 * ao[i]) * wet, 3))
    I = []
    for a, b, c in m.f:
        I += [a, c, b]   # (Godot winds front faces clockwise)
    info = {"name": key, "len": round(ln, 3), "beam": round(bm, 3), "fb": round(fb, 3), "tris": len(I) // 3, "verts": len(V) // 3,
            "v": V, "n": Nn, "uv": UV, "c": C, "ao": A, "i": I}
    with open(os.path.join(out, key + ".json"), "w") as f:
        json.dump(info, f, separators=(",", ":"))
    return info


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.join(HERE, "_frames_ships")
    only = list(ROWS)
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out = os.path.abspath(argv[i + 1])
            i += 1
        elif argv[i] == "--only":
            only = argv[i + 1].split(",")
            i += 1
        i += 1
    os.makedirs(out, exist_ok=True)
    paint_atlas(os.path.join(out, "ships3d_albedo.png"))
    tot = 0
    for k in only:
        info = export(k, out)
        tot += info["tris"]
        print("SHIP3D %s tris=%d verts=%d" % (k, info["tris"], info["verts"]))
    print("SHIP3D total tris=%d" % tot)


main()
