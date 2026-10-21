"""Fort traces: the outer line of each landmark fort piece's rampart, from the overworld minis' geometry
(tools/structures/spec.json, the parts lists the kit pieces are built from: tools/battlekit/spec_pieces.py).

Pure Python (no Blender). For a fort piece it expands the parts (same `use` / p / r / sc rules as the
structures builder, in 2D), takes the rampart's ground-level masonry bodies (boxes and polygons of coquina,
brick or stone standing within 2 m of the ground; else the lowest masonry body: the rock fort's top), unites
their footprints, notes the corner towers (a masonry cylinder standing on a vertex: its radius), and marks the salients (convex vertices standing farther from the centre than both
neighbours: the bastions' points, a triangle's corners, a square's towers). Output in the piece frame of
`BattleKit.piece_foot` (metres, origin = the piece origin, x right, y down on the screen, the piece's front,
where its gate is, toward -y).

  python3 tools/battlekit/fort_trace.py            # writes `trace` into tools/battlekit/_frames/<piece>.json
                                                   # and generates sim/fort_traces.gd
tools/battlekit/build.py calls `add_trace(name, json_path)` after rendering a piece (fort pieces only).
"""
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SPEC_PATH = os.path.join(ROOT, "tools", "structures", "spec.json")
FRAMES = os.path.join(HERE, "_frames")
OUT_GD = os.path.join(ROOT, "sim", "fort_traces.gd")

# kit piece -> (structures source, plan piece name in MapGen.TP_NAMES)
FORTS = {
    "lm_morro": ("morro", "morro"), "lm_morro_sj": ("morro_sj", "morro_sj"), "lm_fuerza": ("fuerza", "fuerza"),
    "lm_san_felipe": ("san_felipe", "san_felipe"), "lm_harbour_fort": ("harbour_fort", "harbour_fort"),
    "lm_san_marcos": ("san_marcos", "san_marcos"), "lm_ulua": ("ulua", "ulua"),
    "lm_fort_charles": ("fort_charles", "fort_charles"), "lm_rock_fort": ("rock_fort", "rock_fort"),
    "cv_fort": ("fort", "fort"),
}
RAMPART = ("coquina", "brick", "stone", "stone_lt")
EPS = 1e-6


# ------------------------------------------------------------------ geometry
def _aff_mul(a, b):
    return [a[0] * b[0] + a[1] * b[3], a[0] * b[1] + a[1] * b[4], a[0] * b[2] + a[1] * b[5] + a[2],
            a[3] * b[0] + a[4] * b[3], a[3] * b[1] + a[4] * b[4], a[3] * b[2] + a[4] * b[5] + a[5]]


def _aff(p, r, sc):
    """2D affine of a part / use: translation p, z rotation r (deg; [rx, ry, rz] -> rz), scale sc."""
    if r is None:
        r = 0.0
    if isinstance(r, (list, tuple)):
        r = r[2]
    if sc is None:
        sc = 1.0
    sx, sy = (sc, sc) if isinstance(sc, (int, float)) else (sc[0], sc[1])
    c, s = math.cos(math.radians(r)), math.sin(math.radians(r))
    rot = [c, -s, p[0], s, c, p[1]]
    return _aff_mul(rot, [sx, 0, 0, 0, sy, 0])


def _apply(M, x, y):
    return (M[0] * x + M[1] * y + M[2], M[3] * x + M[4] * y + M[5])


def _zscale(M):
    return 1.0


def _poly_points(spec):
    if isinstance(spec, list):
        return [tuple(v) for v in spec]
    if "circle" in spec:
        c = spec["circle"]
        n, r = int(c[0]), c[1]
        jit = c[2] if len(c) > 2 else 0.0
        seed = int(c[3]) if len(c) > 3 else 1
        a0 = c[4] if len(c) > 4 else 0.0
        a1 = c[5] if len(c) > 5 else 360.0
        rng = random.Random(seed)
        cnt = n if (a1 - a0) >= 360 else n + 1
        pts = []
        for i in range(cnt):
            a = math.radians(a0 + (a1 - a0) * i / n)
            rr = r * (1.0 + jit * (rng.random() * 2 - 1))
            pts.append((rr * math.cos(a), rr * math.sin(a)))
        return pts
    if "rect" in spec:
        x0, y0, x1, y1 = spec["rect"]
        return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    raise KeyError(spec)


def _expand(spec, parts, M, zoff, scz, out, depth=0):
    for p in parts:
        if "use" in p:
            pos = p.get("p", [0, 0, 0])
            sc = p.get("sc")
            szz = sc if isinstance(sc, (int, float)) else (sc[2] if sc else 1.0)
            if "polar" in p:
                n, rad, start = p["polar"]
                for k in range(int(n)):
                    ang = start + 360.0 * k / n
                    q = _aff_mul(_aff([rad * math.cos(math.radians(ang)), rad * math.sin(math.radians(ang))], ang, None),
                                 _aff([0, 0], p.get("r"), sc))
                    _expand(spec, spec["defs"][p["use"]], _aff_mul(M, q), zoff + pos[2] * scz, scz * szz, out, depth + 1)
            else:
                _expand(spec, spec["defs"][p["use"]], _aff_mul(M, _aff(pos, p.get("r"), sc)), zoff + pos[2] * scz,
                        scz * szz, out, depth + 1)
        else:
            out.append((p, M, zoff, scz))
    return out


def _part_foot(p, M):
    """The part's ground footprint (convex polygon, structure frame) or None."""
    s = p["s"]
    if s == "box":
        sx, sy, _ = p["sz"]
        L = _aff_mul(M, _aff(p.get("p", [0, 0, 0]), p.get("r"), None))
        return [_apply(L, x, y) for x, y in ((-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2))]
    if s == "poly":
        pts = _poly_points(p["pts"])
        sc0 = p.get("sc0", 1.0)
        cx = sum(q[0] for q in pts) / len(pts)
        cy = sum(q[1] for q in pts) / len(pts)
        pts = [(cx + (x - cx) * sc0, cy + (y - cy) * sc0) for x, y in pts]
        L = _aff_mul(M, _aff(p.get("p", [0, 0, 0]), p.get("r"), None))
        return [_apply(L, x, y) for x, y in pts]
    return None


def _area(poly):
    a = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        a += x0 * y1 - x1 * y0
    return a / 2


def _ccw(poly):
    return poly if _area(poly) > 0 else list(reversed(poly))


def _inside_strict(poly, x, y):
    """Strictly inside a convex CCW polygon."""
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        if (x1 - x0) * (y - y0) - (y1 - y0) * (x - x0) <= 1e-7:
            return False
    return True


def _seg_x(a, b, c, d):
    """Parameter t on a-b where it crosses c-d (proper or touching), else None."""
    rx, ry = b[0] - a[0], b[1] - a[1]
    sx, sy = d[0] - c[0], d[1] - c[1]
    den = rx * sy - ry * sx
    if abs(den) < 1e-12:
        return None
    t = ((c[0] - a[0]) * sy - (c[1] - a[1]) * sx) / den
    u = ((c[0] - a[0]) * ry - (c[1] - a[1]) * rx) / den
    if -EPS <= t <= 1 + EPS and -EPS <= u <= 1 + EPS:
        return min(max(t, 0.0), 1.0)
    return None


def union_outline(polys):
    """Outer outline of the union of convex polygons (CCW), collinear points dropped."""
    polys = [_ccw(p) for p in polys]
    kept = []
    for i, P in enumerate(polys):
        for k in range(len(P)):
            a, b = P[k], P[(k + 1) % len(P)]
            ts = {0.0, 1.0}
            for j, Q in enumerate(polys):
                if j == i:
                    continue
                for m in range(len(Q)):
                    t = _seg_x(a, b, Q[m], Q[(m + 1) % len(Q)])
                    if t is not None:
                        ts.add(round(t, 9))
            ts = sorted(ts)
            for q in range(len(ts) - 1):
                if ts[q + 1] - ts[q] < 1e-7:
                    continue
                tm = (ts[q] + ts[q + 1]) / 2
                mx, my = a[0] + (b[0] - a[0]) * tm, a[1] + (b[1] - a[1]) * tm
                if any(_inside_strict(Q, mx, my) for j, Q in enumerate(polys) if j != i):
                    continue
                # (shared collinear edges: keep the first polygon's)
                dup = False
                for j, Q in enumerate(polys):
                    if j >= i:
                        break
                    for m in range(len(Q)):
                        c, d = Q[m], Q[(m + 1) % len(Q)]
                        cr = (d[0] - c[0]) * (my - c[1]) - (d[1] - c[1]) * (mx - c[0])
                        ln = math.hypot(d[0] - c[0], d[1] - c[1])
                        dt = ((mx - c[0]) * (d[0] - c[0]) + (my - c[1]) * (d[1] - c[1])) / max(ln * ln, 1e-12)
                        if abs(cr) / max(ln, 1e-12) < 1e-6 and 0 < dt < 1:
                            dup = True
                if dup:
                    continue
                pa = (a[0] + (b[0] - a[0]) * ts[q], a[1] + (b[1] - a[1]) * ts[q])
                pb = (a[0] + (b[0] - a[0]) * ts[q + 1], a[1] + (b[1] - a[1]) * ts[q + 1])
                kept.append((pa, pb))
    # Chain the pieces.
    loop = [kept[0][0], kept[0][1]]
    used = {0}
    while True:
        end = loop[-1]
        nxt = None
        for q, (pa, pb) in enumerate(kept):
            if q not in used and math.hypot(pa[0] - end[0], pa[1] - end[1]) < 1e-5:
                nxt = q
                break
        if nxt is None:
            break
        used.add(nxt)
        if math.hypot(kept[nxt][1][0] - loop[0][0], kept[nxt][1][1] - loop[0][1]) < 1e-5:
            break
        loop.append(kept[nxt][1])
    # Drop collinear points.
    out = []
    n = len(loop)
    for i in range(n):
        p0, p1, p2 = loop[i - 1], loop[i], loop[(i + 1) % n]
        cr = (p1[0] - p0[0]) * (p2[1] - p1[1]) - (p1[1] - p0[1]) * (p2[0] - p1[0])
        if abs(cr) > 1e-6:
            out.append(p1)
    return out


# ------------------------------------------------------------------ traces
def trace_of(src, spec=None):
    """The trace of structure `src` (piece frame: metres, y down, front at -y): a dict
    {"v": [[x, y], ...] (clockwise on screen), "salient": [0-3], "angle": [interior deg], "tower": [radius m, 0
    none], "gate": edge index,
    "centre": [x, y] (the polygon's centroid: the parade), "area": m2}."""
    spec = spec or json.load(open(SPEC_PATH))
    st = spec["structures"]["p_%s__y0" % src]
    flat = _expand(spec, st["parts"], [1, 0, 0, 0, 1, 0], 0.0, 1.0, [])
    bodies = []
    lowest = None
    towers = []
    for p, M, zoff, scz in flat:
        if p.get("m") not in RAMPART or p.get("ol", 1) == 0:
            continue
        if p["s"] in ("box", "poly"):
            z0 = zoff + scz * ((p.get("p", [0, 0, 0])[2]) if p["s"] == "box" else p.get("z0", 0.0) + p.get("p", [0, 0, 0])[2])
            ft = _part_foot(p, M)
            if ft is None:
                continue
            if z0 <= 2.0 + EPS:
                bodies.append(ft)
            if lowest is None or z0 < lowest[0] - EPS:
                lowest = (z0, [ft])
            elif abs(z0 - lowest[0]) <= EPS:
                lowest[1].append(ft)
        elif p["s"] == "cyl":
            z0 = zoff + scz * p.get("p", [0, 0, 0])[2]
            sc = math.hypot(M[0], M[3])
            if z0 <= 2.0 + EPS and p.get("rad", 1.0) * sc >= 1.5:
                c = _apply(M, p["p"][0], p["p"][1])
                towers.append((c[0], c[1], p.get("rad", 1.0) * sc))
    if not bodies:
        bodies = lowest[1]
    out = union_outline(bodies)
    # Corner towers: a masonry cylinder standing on a vertex (its radius kept with the vertex: the sim's
    # round tower there; the line itself runs through the towers' centres, as the minis' walls do).
    n = len(out)
    trad = [0.0] * n
    for i in range(n):
        for tx, ty, tr in towers:
            if math.hypot(tx - out[i][0], ty - out[i][1]) <= 0.6:
                trad[i] = max(trad[i], tr)
    moved = out
    # Structure frame -> piece frame: the kit turns the minis 180 degrees (front +y, image up) and the
    # screen's y runs down: (x, y) -> (-x, y). That mirrors, so the order is reversed to stay CCW in
    # the structure's sense (clockwise on the screen, y down).
    pf = [(-x, y) for x, y in reversed(moved)]
    trad = list(reversed(trad))
    n = len(pf)
    A = 0.0
    gx = gy = 0.0
    for i in range(n):
        x0, y0 = pf[i]
        x1, y1 = pf[(i + 1) % n]
        c = x0 * y1 - x1 * y0
        A += c
        gx += (x0 + x1) * c
        gy += (y0 + y1) * c
    A /= 2
    gx /= 6 * A
    gy /= 6 * A
    sgn = 1 if A > 0 else -1
    # Interior angles and salients.
    ang = []
    convex = []
    for i in range(n):
        p0, p1, p2 = pf[i - 1], pf[i], pf[(i + 1) % n]
        e0 = (p1[0] - p0[0], p1[1] - p0[1])
        e1 = (p2[0] - p1[0], p2[1] - p1[1])
        cr = (e0[0] * e1[1] - e0[1] * e1[0]) * sgn
        turn = math.degrees(math.atan2(abs(e0[0] * e1[1] - e0[1] * e1[0]), e0[0] * e1[0] + e0[1] * e1[1]))
        ia = 180 - turn if cr > 0 else 180 + turn
        ang.append(int(round(ia)))
        convex.append(cr > 0)
    # Salients: a bastion is a run of convex vertices between reflex ones; its point is the run's middle
    # vertex (1), or with an even run the middle edge (the flat nose of a turned-square bastion: 2 at the
    # edge's first vertex, 3 at its second). With no reflex vertex (a triangle, a towered square) every
    # corner is a salient.
    sal = [0] * n
    if all(convex):
        sal = [1] * n
    else:
        k0 = next(i for i in range(n) if not convex[i])
        i = 1
        while i <= n:
            q = (k0 + i) % n
            if not convex[q]:
                i += 1
                continue
            run = []
            while convex[(k0 + i) % n] and i <= n:
                run.append((k0 + i) % n)
                i += 1
            m = len(run)
            if m % 2 == 1:
                sal[run[m // 2]] = 1
            else:
                sal[run[m // 2 - 1]] = 2
                sal[run[m // 2]] = 3
    # The gate: the longest of the edges facing the front (-y) most (outward normal), edges under a quarter of
    # the longest left out.
    lens = [math.hypot(pf[(i + 1) % n][0] - pf[i][0], pf[(i + 1) % n][1] - pf[i][1]) for i in range(n)]
    best = None
    for i in range(n):
        ex, ey = pf[(i + 1) % n][0] - pf[i][0], pf[(i + 1) % n][1] - pf[i][1]
        nx, ny = (ey, -ex) if sgn > 0 else (-ey, ex)
        ny /= max(lens[i], 1e-9)
        if lens[i] < max(lens) / 4:
            continue
        key = (round(-ny, 3), lens[i])
        if best is None or key > best[0]:
            best = (key, i)
    return {"v": [[round(x, 2), round(y, 2)] for x, y in pf], "salient": sal, "angle": ang, "tower": [round(r, 2) for r in trad],
            "gate": best[1],
            "centre": [round(gx, 2), round(gy, 2)], "area": round(abs(A), 1)}


def add_trace(name, json_path, spec=None):
    """build.py hook: put the fort piece `name`'s trace into its frame .json (no-op for other pieces)."""
    if name not in FORTS or not os.path.exists(json_path):
        return
    d = json.load(open(json_path))
    d["trace"] = trace_of(FORTS[name][0], spec)
    json.dump(d, open(json_path, "w"))


def write_gd(traces):
    lines = [
        "## Fort traces (generated by tools/battlekit/fort_trace.py from tools/structures/spec.json: do not edit).",
        "## The outer line of each landmark fort piece's rampart, in its piece frame (decimetres: origin the piece",
        "## origin, x right, y down, the front with its gate toward -y), by plan piece name (MapGen.TP_NAMES). The",
        "## sim's copy of the kit data (the sim does not read the view); game/battlekit.gd piece_trace reads it too.",
        "##   v        vertices x, y (dm), clockwise on the screen",
        "##   sal      1 at a salient (a bastion's point, a corner tower); 2 / 3 at the ends of a bastion's flat nose",
        "##   ang      interior angle at each vertex (degrees)",
        "##   tw       a corner tower's radius at each vertex (dm; 0 none): the line runs through its centre",
        "##   gate     the edge (from vertex k to k + 1) with the gate, facing the front",
        "##   pc       the parade's centre (the polygon's centroid, dm)",
        "##   area     the polygon's area (m2)",
        "",
        "const T := {",
    ]
    for pn in sorted(traces):
        t = traces[pn]
        v = []
        for x, y in t["v"]:
            v += [int(round(x * 10)), int(round(y * 10))]
        lines.append('\t"%s": {"v": [%s],' % (pn, ", ".join(str(q) for q in v)))
        lines.append('\t\t"sal": [%s], "ang": [%s], "tw": [%s],' % (", ".join(str(q) for q in t["salient"]),
                                                     ", ".join(str(q) for q in t["angle"]),
                                                     ", ".join(str(int(round(q * 10))) for q in t["tower"])))
        lines.append('\t\t"gate": %d, "pc": [%d, %d], "area": %d},' % (t["gate"], int(round(t["centre"][0] * 10)),
                                                                     int(round(t["centre"][1] * 10)), int(round(t["area"]))))
    lines.append("}")
    lines.append("")
    open(OUT_GD, "w").write("\n".join(lines))


def main():
    spec = json.load(open(SPEC_PATH))
    traces = {}
    for name, (src, pn) in FORTS.items():
        t = trace_of(src, spec)
        traces[pn] = t
        add_trace(name, os.path.join(FRAMES, name + ".json"), spec)
        print("%-16s %2d vertices, %d salients, gate edge %d, area %.0f m2, angles %s" % (
            name, len(t["v"]), sum(1 for q in t["salient"] if q in (1, 2)), t["gate"], t["area"], t["angle"]))
    write_gd(traces)
    print("wrote", OUT_GD)


if __name__ == "__main__":
    main()
