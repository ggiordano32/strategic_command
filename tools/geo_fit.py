#!/usr/bin/env python3
"""Fit the campaign overworld to real geography (public-domain data) and bake
the result into the files the game reads. The game never reads the raw data.

  python3 -I tools/geo_fit.py --config tools/geo/med.json --dem DEM --ne NEDIR
         [--repo .] [--dem-lon0 -10.7 --dem-lat0 32.8 --dem-step 0.008333333
          --dem-rows 1729 --dem-cols 4369] [--dry]
  (needs numpy; run it from a venv or system python3 with numpy installed)

Inputs
  --config  JSON: the window and projection (see "PARAMETERS"), the bake
            settings, the region / settlement list ("regions": key, lon, lat,
            land = landmass index) and the rivers (name, Natural Earth names,
            a hand-authored fallback line, crossings). tools/geo/med.json is
            the Mediterranean (the default); any other setting (the Americas)
            is another config of the same shape, the output format is the same.
  --dem     elevation: an OPeNDAP ".dods" response (big-endian float32 grid,
            south row first, as NOAA's ETOPO 2022 30 arc-second server returns
            for z.z[rows][cols]) or a .npy float array (north row first is
            detected by --dem-north-first). Metres; negative = sea.
  --ne      a directory holding Natural Earth 1:10m GeoJSON: ne_10m_land,
            ne_10m_rivers_lake_centerlines, ne_10m_rivers_europe (optional).

PARAMETERS (config keys)
  window: lon0, lat0 (north-west corner, degrees), lon_span, lat_span.
  px_lat, px_lon: map pixels per degree (the projection is equirectangular:
            x = (lon - lon0) * px_lon, y = (lat0 - lat) * px_lat; the
            constants LON0 / LAT0 / PX_LAT / PX_LON / SIZE of
            game/campaign/map_geo.gd must equal them: checked).
  cell_px: grid cell size in map pixels (tools/campaign_grid.gd --cell).
  fine_per_cell: fine elevation samples per cell side (8: 0.025 degrees).
  simplify_deg: Douglas-Peucker tolerance for coasts and rivers (degrees).
  island_min_deg: islands smaller than this across are dropped.
  landmass_clip: {"index": {"lon_max": x}} extra clips of a landmass.
  thresholds: terrain class thresholds (below).
  rivers: [{name, into, ne_names, hand, cross, ne_from?}]: the Natural Earth
            main stem (shortest path along the NE lines from the vertex nearest
            ne_from, default hand[0], to the one nearest the hand mouth); hand
            stretches upstream / at the mouth that NE lacks are kept; with no
            NE name the hand line is used as is. Crossings snap onto the line.
  regions: [{key, lon, lat, land}]: land = index of the landmass the
            settlement must lie on; landmass k is the polygon holding the
            settlements with land == k. A settlement off its land by a hair is
            reported with the suggested point (the tool does not edit CData).

Outputs (written unless --dry)
  game/campaign/map_geo.gd: LANDS, ISLANDS, RIVERS replaced (marked GENERATED).
  campaign/data/elev_data.gd: per grid cell integer arrays (see its header).
  game/campaign/relief_data.gd: the fine fields (see its header).

Fetching the data (once, into a fresh directory; treat it as untrusted data)
  DEM: curl -o z.dods "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/30s/30s_surface_elev_netcdf/ETOPO_2022_v1_30s_N90W180_surface.nc.dods?z.z[r0:r1][c0:c1]"
       rows are south-first from -90 (r = (lat + 90) * 120), columns from -180
       (c = (lon + 180) * 120); the Mediterranean window used r 14736:16464,
       c 20316:24684 (lon -10.7..25.7, lat 32.8..47.2, a margin round the map).
  NE:  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/
       ne_10m_land, ne_10m_rivers_lake_centerlines, ne_10m_rivers_europe (.geojson).

Terrain classes per grid cell (elevation of the cell = land samples only):
  ridge   mean >= ridge_mean, or max >= ridge_max and relief >= ridge_relief
  hill    mean >= hill_mean, or relief >= hill_relief
  valley  mean < valley_mean and the mean of the ring of cells 2 away is at
          least 200 m higher (a low cell between higher ones)
  rolling mean >= 150 or relief >= 120; plain: the rest. Sea: "."
tools/campaign_grid.gd turns hill / ridge into the grid's TERRAIN overrides
where they are rougher than the region's own terrain.

Data (public domain): ETOPO 2022 v1 30 arc-second surface elevation, NOAA NCEI,
doi:10.25921/fd45-gt74 (public domain, US Government work); Natural Earth
1:10m land, rivers + lake centerlines, rivers Europe supplement, v5.1.2
(public domain, naturalearthdata.com).
"""
import argparse
import base64
import json
import math
import os
import re
import sys
import zlib

import numpy as np


# ---------------------------------------------------------------- geometry

class Proj:
    def __init__(self, cfg):
        w = cfg["window"]
        self.lon0, self.lat0 = w["lon0"], w["lat0"]
        self.lon1, self.lat1 = self.lon0 + w["lon_span"], self.lat0 - w["lat_span"]
        self.px_lat, self.px_lon = cfg["px_lat"], cfg["px_lon"]
        self.size = (w["lon_span"] * self.px_lon, w["lat_span"] * self.px_lat)

    def px(self, lon, lat):
        return ((lon - self.lon0) * self.px_lon, (self.lat0 - lat) * self.px_lat)


def clip_ring(ring, xmin, xmax, ymin, ymax):
    """Sutherland-Hodgman against the box; ring = list of (x, y)."""
    def run(pts, inside, inter):
        out = []
        n = len(pts)
        for i in range(n):
            a, b = pts[i - 1], pts[i]
            ia, ib = inside(a), inside(b)
            if ib:
                if not ia:
                    out.append(inter(a, b))
                out.append(b)
            elif ia:
                out.append(inter(a, b))
        return out

    def ix(xc):
        return lambda a, b: (xc, a[1] + (b[1] - a[1]) * (xc - a[0]) / (b[0] - a[0]))

    def iy(yc):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (yc - a[1]) / (b[1] - a[1]), yc)
    pts = ring
    for inside, inter in (
            (lambda p: p[0] >= xmin, ix(xmin)), (lambda p: p[0] <= xmax, ix(xmax)),
            (lambda p: p[1] >= ymin, iy(ymin)), (lambda p: p[1] <= ymax, iy(ymax))):
        if not pts:
            break
        pts = run(pts, inside, inter)
    return pts


def _seg_entry(a, b, box):
    """Point where segment a -> b meets the box boundary (one end outside)."""
    x0, x1, y0, y1 = box
    t0, t1 = 0.0, 1.0
    dx, dy = b[0] - a[0], b[1] - a[1]
    for p, q in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])):
        if p == 0:
            if q < 0:
                return None
            continue
        r = q / p
        if p < 0:
            t0 = max(t0, r)
        else:
            t1 = min(t1, r)
    return t0, t1, dx, dy


def _perim(pt, box):
    """Clockwise perimeter coordinate from the north-west corner."""
    x0, x1, y0, y1 = box   # x0 west, x1 east, y0 south, y1 north
    W, H = x1 - x0, y1 - y0
    eps = 1e-9
    if abs(pt[1] - y1) < eps:
        return pt[0] - x0
    if abs(pt[0] - x1) < eps:
        return W + (y1 - pt[1])
    if abs(pt[1] - y0) < eps:
        return W + H + (x1 - pt[0])
    return 2 * W + H + (pt[1] - y0)


def clip_ring_pieces(ring, box):
    """Pieces of a closed ring inside the box: every run of the ring inside it
    is closed along the box boundary in the ring's own direction (so land that
    the ring leaves and re-enters is not bridged across the sea)."""
    x0, x1, y0, y1 = box
    W, H = x1 - x0, y1 - y0
    total = 2 * (W + H)
    corners = [(0.0, (x0, y1)), (W, (x1, y1)), (W + H, (x1, y0)), (2 * W + H, (x0, y0))]
    inside = lambda p: x0 <= p[0] <= x1 and y0 <= p[1] <= y1
    a = np.array(ring, float)
    area = 0.5 * (np.dot(a[:, 0], np.roll(a[:, 1], -1)) - np.dot(a[:, 1], np.roll(a[:, 0], -1)))
    cw = area < 0
    n = len(ring)
    start = next((i for i in range(n) if not inside(ring[i])), None)
    if start is None:
        return [list(ring)]
    pts = ring[start:] + ring[:start]
    pieces, cur = [], None
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        ip, iq = inside(p), inside(q)
        if iq and not ip:
            r = _seg_entry(p, q, box)
            e = (p[0] + r[2] * r[0], p[1] + r[3] * r[0]) if r else q
            cur = [e]
        if iq:
            if cur is None:
                cur = []
            cur.append(q)
        if ip and not iq and cur is not None:
            r = _seg_entry(p, q, box)
            e = (p[0] + r[2] * r[1], p[1] + r[3] * r[1]) if r else p
            cur.append(e)
            t_exit, t_entry = _perim(e, box), _perim(cur[0], box)
            # walk from the exit to the entry along the boundary
            if cw:
                span = (t_entry - t_exit) % total
                mids = sorted(((c[0] - t_exit) % total, c[1]) for c in corners if 0 < (c[0] - t_exit) % total < span)
            else:
                span = (t_exit - t_entry) % total
                mids = sorted(((t_exit - c[0]) % total, c[1]) for c in corners if 0 < (t_exit - c[0]) % total < span)
            cur += [m[1] for m in mids]
            pieces.append(cur)
            cur = None
    return [c for c in pieces if len(c) >= 3]


def dp_open(pts, tol, force=None):
    """Douglas-Peucker on an (n,2) array; returns kept indices."""
    n = len(pts)
    keep = np.zeros(n, bool)
    keep[0] = keep[-1] = True
    if force is not None:
        keep |= force
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = pts[i], pts[j]
        seg = pts[i + 1:j]
        d = b - a
        L = math.hypot(d[0], d[1])
        if L < 1e-12:
            dist = np.hypot(seg[:, 0] - a[0], seg[:, 1] - a[1])
        else:
            dist = np.abs(d[0] * (seg[:, 1] - a[1]) - d[1] * (seg[:, 0] - a[0])) / L
        if force is not None:
            dist = np.where(force[i + 1:j], 0.0, dist)
        k = int(dist.argmax())
        if dist[k] > tol:
            m = i + 1 + k
            keep[m] = True
            stack.append((i, m))
            stack.append((m, j))
    return np.nonzero(keep)[0]


def simplify_ring(ring, tol, aspect, keep_near=()):
    """Closed ring [(lon, lat)] -> simplified ring (no repeated end point).
    Vertices within 0.12 degrees of a point of keep_near (the settlements) are
    all kept, so a settlement on the real coast stays on land."""
    p = np.array(ring, float)
    q = p * np.array([aspect, 1.0])
    if len(p) <= 4:
        return [tuple(x) for x in p]
    force = np.zeros(len(p), bool)
    for kp in keep_near:
        force |= np.hypot((p[:, 0] - kp[0]) * aspect, p[:, 1] - kp[1]) < 0.12
    d = np.hypot(q[:, 0] - q[0, 0], q[:, 1] - q[0, 1])
    m = int(d.argmax())
    force[0] = force[m] = False
    k1 = dp_open(q[:m + 1], tol, force[:m + 1])
    k2 = dp_open(np.vstack([q[m:], q[:1]]), tol, np.append(force[m:], False)) + m
    idx = list(k1) + [i for i in k2 if i != m]
    idx = [i for i in idx if i < len(p)]
    out = []
    for i in idx:
        if not out or out[-1] != i:
            out.append(i)
    return [tuple(p[i]) for i in out]


def simplify_line(line, tol, aspect):
    p = np.array(line, float)
    if len(p) <= 2:
        return [tuple(x) for x in p]
    q = p * np.array([aspect, 1.0])
    return [tuple(p[i]) for i in dp_open(q, tol)]


def point_in_ring(pt, ring):
    x, y = pt
    r = np.asarray(ring, float)
    x0, y0 = r[:, 0], r[:, 1]
    x1, y1 = np.roll(x0, -1), np.roll(y0, -1)
    cond = (y0 > y) != (y1 > y)
    with np.errstate(divide="ignore", invalid="ignore"):
        xi = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
    return bool(np.count_nonzero(cond & (x < xi)) % 2)


def nearest_on_ring(pt, ring):
    """Closest point on the ring's edges to pt (lon, lat, in plain degrees)."""
    r = np.asarray(ring, float)
    a, b = r, np.roll(r, -1, axis=0)
    d = b - a
    L2 = (d ** 2).sum(1)
    L2[L2 == 0] = 1e-18
    t = np.clip(((pt[0] - a[:, 0]) * d[:, 0] + (pt[1] - a[:, 1]) * d[:, 1]) / L2, 0, 1)
    c = a + d * t[:, None]
    dist = np.hypot(c[:, 0] - pt[0], c[:, 1] - pt[1])
    k = int(dist.argmin())
    return tuple(c[k]), float(dist[k])


def ring_area(r):
    a = np.asarray(r, float)
    return 0.5 * abs(np.dot(a[:, 0], np.roll(a[:, 1], -1)) - np.dot(a[:, 1], np.roll(a[:, 0], -1)))


# ------------------------------------------------------------------ inputs

def load_dem(path, args):
    if path.endswith(".npy"):
        z = np.load(path).astype(np.float32)
        if not args.dem_south_first:
            z = z[::-1]
    else:
        b = open(path, "rb").read()
        i = b.index(b"Data:\n") + 6
        z = np.frombuffer(b[i + 8:i + 8 + args.dem_rows * args.dem_cols * 4], dtype=">f4")
        z = z.reshape(args.dem_rows, args.dem_cols).astype(np.float32)
    z[~np.isfinite(z) | (z < -20000)] = -9999
    return z   # row 0 = southernmost, column 0 = westernmost


class Dem:
    """Land-only box means from integral images; coordinates in degrees."""

    def __init__(self, z, lon0, lat0, step):
        self.z, self.lon0, self.lat0, self.step = z, lon0, lat0, step
        zp = np.maximum(z, 0).astype(np.float64)
        land = (z > 0).astype(np.float64)
        self.I = np.zeros((z.shape[0] + 1, z.shape[1] + 1))
        self.M = np.zeros_like(self.I)
        self.I[1:, 1:] = zp.cumsum(0).cumsum(1)
        self.M[1:, 1:] = land.cumsum(0).cumsum(1)

    def _at(self, J, u, v):
        h, w = J.shape
        u = np.clip(u, 0, w - 1.0001)
        v = np.clip(v, 0, h - 1.0001)
        u0, v0 = np.floor(u).astype(int), np.floor(v).astype(int)
        fu, fv = u - u0, v - v0
        return (J[v0, u0] * (1 - fu) * (1 - fv) + J[v0, u0 + 1] * fu * (1 - fv)
                + J[v0 + 1, u0] * (1 - fu) * fv + J[v0 + 1, u0 + 1] * fu * fv)

    def mean_land(self, lon_a, lon_b, lat_a, lat_b):
        """Mean elevation of the land samples in the boxes (arrays); 0 if none."""
        u0, u1 = (lon_a - self.lon0) / self.step, (lon_b - self.lon0) / self.step
        v0, v1 = (lat_a - self.lat0) / self.step, (lat_b - self.lat0) / self.step
        s = self._at(self.I, u1, v1) - self._at(self.I, u0, v1) - self._at(self.I, u1, v0) + self._at(self.I, u0, v0)
        m = self._at(self.M, u1, v1) - self._at(self.M, u0, v1) - self._at(self.M, u1, v0) + self._at(self.M, u0, v0)
        return np.where(m > 0.05, s / np.maximum(m, 1e-9), 0.0)


def read_geojson(path):
    return json.load(open(path))


def lines_of(g):
    if not g:
        return []
    if g["type"] == "LineString":
        return [g["coordinates"]]
    if g["type"] == "MultiLineString":
        return g["coordinates"]
    return []


# ------------------------------------------------------------- the bake

def build_land(cfg, proj, ne):
    aspect = proj.px_lon / proj.px_lat
    tol = cfg["simplify_deg"]
    d = read_geojson(os.path.join(ne, "ne_10m_land.geojson"))
    x0, x1, y1, y0 = proj.lon0, proj.lon1, proj.lat1, proj.lat0   # ymin = lat1 (south), ymax = lat0
    pieces = []
    for ft in d["features"]:
        g = ft["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for poly in polys:
            ring = [tuple(p[:2]) for p in poly[0]]
            if ring[0] == ring[-1]:
                ring = ring[:-1]
            xs = [p[0] for p in ring]
            ys = [p[1] for p in ring]
            if max(xs) < x0 or min(xs) > x1 or max(ys) < y1 or min(ys) > y0:
                continue
            if min(xs) >= x0 and max(xs) <= x1 and min(ys) >= y1 and max(ys) <= y0:
                pieces.append(ring)
            else:
                pieces += clip_ring_pieces(ring, (x0, x1, y1, y0))
    # Landmass index: the piece holding the settlements of land k.
    lands = {}
    notes = []
    for r in cfg["regions"]:
        k = r["land"]
        pt = (r["lon"], r["lat"])
        hit = [i for i, rg in enumerate(pieces) if point_in_ring(pt, rg)]
        if not hit:
            # nearest piece
            best = None
            for i, rg in enumerate(pieces):
                c, dist = nearest_on_ring(pt, rg)
                if best is None or dist < best[0]:
                    best = (dist, i, c)
            hit = [best[1]]
            notes.append((r["key"], pt, best[2], best[0]))
        if k in lands and lands[k] != hit[0]:
            sys.exit("landmass %d: settlement %s is on another polygon" % (k, r["key"]))
        lands[k] = hit[0]
    keep = [(r["lon"], r["lat"]) for r in cfg["regions"]]
    out_lands = []
    for k in sorted(lands):
        ring = pieces[lands[k]]
        c = cfg.get("landmass_clip", {}).get(str(k))
        if c:
            ring = clip_ring(ring, x0, c.get("lon_max", x1), y1, y0)
        out_lands.append(simplify_ring(ring, tol, aspect, keep))
    for r in cfg["regions"]:
        if not point_in_ring((r["lon"], r["lat"]), out_lands[sorted(lands).index(r["land"])]):
            c, dist = nearest_on_ring((r["lon"], r["lat"]), out_lands[sorted(lands).index(r["land"])])
            notes.append((r["key"], (r["lon"], r["lat"]), c, dist))
    used = set(lands.values())
    islands = []
    dropped = 0
    for i, rg in enumerate(pieces):
        if i in used:
            continue
        xs = [p[0] for p in rg]
        ys = [p[1] for p in rg]
        ext = max((max(xs) - min(xs)) * aspect, max(ys) - min(ys))
        if ext < cfg["island_min_deg"]:
            dropped += 1
            continue
        s = simplify_ring(rg, tol, aspect)
        if len(s) >= 3:
            islands.append(s)
    return out_lands, islands, notes, dropped


def river_path(segs, a, b, aspect):
    """Main stem: the shortest path along the segments' vertices (joined where
    two share a point) from the vertex nearest a (source) to the one nearest b
    (mouth); tributaries are not on it."""
    import heapq
    key = lambda p: (round(p[0], 3), round(p[1], 3))
    adj, pos = {}, {}
    for sg in segs:
        for i in range(len(sg)):
            k = key(sg[i])
            pos[k] = sg[i]
            adj.setdefault(k, [])
            if i > 0:
                k0 = key(sg[i - 1])
                w = math.hypot((sg[i][0] - sg[i - 1][0]) * aspect, sg[i][1] - sg[i - 1][1])
                adj[k].append((k0, w))
                adj[k0].append((k, w))
    near = lambda pt: min(pos, key=lambda k: math.hypot((k[0] - pt[0]) * aspect, k[1] - pt[1]))
    s0, t0 = near(a), near(b)
    dist = {s0: 0.0}
    prev = {}
    pq = [(0.0, s0)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == t0:
            break
        if d > dist.get(u, 1e18):
            continue
        for v, w in adj[u]:
            if d + w < dist.get(v, 1e18):
                dist[v] = d + w
                prev[v] = u
                heapq.heappush(pq, (d + w, v))
    if t0 not in dist:
        return []
    path = [t0]
    while path[-1] != s0:
        path.append(prev[path[-1]])
    return [pos[k] for k in path[::-1]]


def line_len(l):
    return sum(math.dist(l[i], l[i + 1]) for i in range(len(l) - 1))


def clip_line(line, proj):
    """Longest run of the polyline inside the window."""
    def inside(p):
        return proj.lon0 <= p[0] <= proj.lon1 and proj.lat1 <= p[1] <= proj.lat0
    runs, cur = [], []
    for p in line:
        if inside(p):
            cur.append(p)
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    return max(runs, key=line_len) if runs else []


def nearest_on_line(pt, line, aspect):
    p = np.array(line, float) * np.array([aspect, 1.0])
    q = np.array(pt, float) * np.array([aspect, 1.0])
    a, b = p[:-1], p[1:]
    d = b - a
    L2 = np.maximum((d ** 2).sum(1), 1e-18)
    t = np.clip(((q[0] - a[:, 0]) * d[:, 0] + (q[1] - a[:, 1]) * d[:, 1]) / L2, 0, 1)
    c = a + d * t[:, None]
    dist = np.hypot(c[:, 0] - q[0], c[:, 1] - q[1])
    k = int(dist.argmin())
    return (c[k][0] / aspect, c[k][1]), float(dist[k]), k, float(t[k])


def build_rivers(cfg, proj, ne):
    aspect = proj.px_lon / proj.px_lat
    tol = cfg["simplify_deg"]
    feats = []
    for fn in ("ne_10m_rivers_lake_centerlines.geojson", "ne_10m_rivers_europe.geojson"):
        p = os.path.join(ne, fn)
        if os.path.exists(p):
            feats += read_geojson(p)["features"]
    out, report = [], []
    for rv in cfg["rivers"]:
        hand = [tuple(p) for p in rv["hand"]]
        segs = []
        for ft in feats:
            pr = ft["properties"]
            nm = pr.get("name_en") or pr.get("name") or ""
            if nm in rv["ne_names"] or pr.get("name") in rv["ne_names"]:
                segs += [[tuple(p[:2]) for p in l] for l in lines_of(ft["geometry"])]
        src = "hand"
        line = hand
        if segs:
            ch = clip_line(river_path(segs, rv.get("ne_from", hand[0]), hand[-1], aspect), proj)
            if len(ch) >= 2:
                # A missing upstream or mouth stretch comes from the hand line.
                src = "NE"
                if math.dist(ch[0], hand[0]) > 0.25:
                    k = min(range(len(hand)), key=lambda i: math.dist(hand[i], ch[0]))
                    ch = hand[:k] + ch
                    src += " + hand upstream"
                if math.dist(ch[-1], hand[-1]) > 0.25:
                    k = min(range(len(hand)), key=lambda i: math.dist(hand[i], ch[-1]))
                    ch = ch + hand[k + 1:]
                    src += " + hand mouth"
                line = ch
        line = simplify_line(line, tol, aspect)
        line = [(round(a, 3), round(b, 3)) for a, b in line]
        cross = []
        for c in rv["cross"]:
            pt, dist, k, t = nearest_on_line((c[2], c[3]), line, aspect)
            cross.append([c[0], c[1], round(pt[0], 3), round(pt[1], 3)])
            report.append("  %s / %s: moved %.2f deg onto the line" % (rv["name"], c[0], dist))
        out.append({"name": rv["name"], "into": rv["into"], "pts": [list(p) for p in line], "cross": cross})
        report.append("river %s: %s, %d points, %.1f deg long" % (rv["name"], src, len(line), line_len(line)))
    return out, report


def fmt_pts(pts, per=6, indent="\t"):
    items = ["[%s, %s]" % (_n(p[0]), _n(p[1])) for p in pts]
    lines = [", ".join(items[i:i + per]) for i in range(0, len(items), per)]
    return (",\n" + indent).join(lines)


def _n(v):
    s = "%.3f" % v
    s = s.rstrip("0").rstrip(".") if "." in s else s
    if "." not in s:
        s += ".0"
    return s


def replace_const(src, name, new_text):
    m = re.search(r"^const %s := " % name, src, re.M)
    i = m.end()
    j = i
    depth = 0
    while True:
        c = src[j]
        if c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return src[:m.start()] + new_text + src[j + 1:]


def write_map_geo(path, cfg, lands, islands, rivers):
    src = open(path).read()
    ls = "const LANDS := [\n"
    names = {0: "Europe", 1: "North Africa"}
    for k, l in enumerate(lands):
        ls += "\t# %d\n\t[%s]%s\n" % (k, fmt_pts(l), "," if k < len(lands) - 1 else "")
    ls += "]"
    isl = "const ISLANDS := [\n" + "".join("\t[%s],\n" % fmt_pts(l) for l in islands) + "]"
    rs = "const RIVERS := [\n"
    for r in rivers:
        cr = ", ".join('["%s", %d, %s, %s]' % (c[0], c[1], _n(c[2]), _n(c[3])) for c in r["cross"])
        rs += '\t{"name": "%s", "into": %d,\n\t"pts": [%s],\n\t"cross": [%s]},\n' % (
            r["name"], r["into"], fmt_pts(r["pts"]).replace("\n\t", "\n\t"), cr)
    rs += "]"
    src = replace_const(src, "LANDS", ls)
    src = replace_const(src, "ISLANDS", isl)
    src = replace_const(src, "RIVERS", rs)
    open(path, "w").write(src)


def check_projection(path, proj):
    src = open(path).read()
    def val(name):
        return float(re.search(r"^const %s\s*:?=\s*(-?[\d.]+)" % name, src, re.M).group(1))
    for name, v in (("LON0", proj.lon0), ("LAT0", proj.lat0), ("PX_LAT", proj.px_lat), ("PX_LON", proj.px_lon)):
        if abs(val(name) - v) > 1e-9:
            sys.exit("map_geo.gd %s = %s differs from the config's %s" % (name, val(name), v))


# ------------------------------------------------------------ elevation

def classify(mean, mx, relief, land, th, w, h):
    cls = np.full(mean.shape, 255, np.uint8)   # 255 sea
    ring2 = np.zeros(mean.shape)
    pad = np.pad(mean, 2, mode="edge")
    acc = np.zeros(mean.shape)
    cnt = 0
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            if max(abs(dx), abs(dy)) == 2:
                acc += pad[2 + dy:2 + dy + h, 2 + dx:2 + dx + w]
                cnt += 1
    ring2 = acc / cnt
    for c in np.ndindex(mean.shape):
        if not land[c]:
            continue
        m, x, r = mean[c], mx[c], relief[c]
        if m >= th["ridge_mean"] or (x >= th["ridge_max"] and r >= th["ridge_relief"]):
            k = 4
        elif m >= th["hill_mean"] or r >= th["hill_relief"]:
            k = 3
        elif m < th["valley_mean"] and ring2[c] - m >= 200:
            k = 2
        elif m >= 150 or r >= 120:
            k = 1
        else:
            k = 0
        cls[c] = k
    return cls


def b64z(raw):
    return base64.b64encode(zlib.compress(bytes(raw), 9)).decode()


def bake_elevation(cfg, proj, dem, rivers, repo, dry):
    cpx = cfg["cell_px"]
    fs = cfg["fine_per_cell"]
    w = int(math.ceil(proj.size[0] / cpx))
    h = int(math.ceil(proj.size[1] / cpx))
    fw, fh = w * fs, h * fs
    fpx = cpx / fs
    # Fine field: land-only mean over the footprint of each sample.
    fx = np.arange(fw)
    fy = np.arange(fh)
    lon_a = proj.lon0 + fx * fpx / proj.px_lon
    lon_b = lon_a + fpx / proj.px_lon
    lat_a = proj.lat0 - (fy + 1) * fpx / proj.px_lat
    lat_b = proj.lat0 - fy * fpx / proj.px_lat
    fine = np.zeros((fh, fw))
    for y in range(fh):
        fine[y] = dem.mean_land(lon_a, lon_b, np.full(fw, lat_a[y]), np.full(fw, lat_b[y]))
    # Cell statistics from the DEM samples and the fine field.
    mean = np.zeros((h, w), int)
    mx = np.zeros((h, w), int)
    relief = np.zeros((h, w), int)
    land = np.zeros((h, w), bool)
    z = dem.z
    for y in range(h):
        la0 = proj.lat0 - (y + 1) * cpx / proj.px_lat
        la1 = proj.lat0 - y * cpx / proj.px_lat
        r0 = max(int((la0 - dem.lat0) / dem.step), 0)
        r1 = min(int(math.ceil((la1 - dem.lat0) / dem.step)), z.shape[0])
        for x in range(w):
            lo0 = proj.lon0 + x * cpx / proj.px_lon
            lo1 = lo0 + cpx / proj.px_lon
            c0 = max(int((lo0 - dem.lon0) / dem.step), 0)
            c1 = min(int(math.ceil((lo1 - dem.lon0) / dem.step)), z.shape[1])
            blk = z[r0:r1, c0:c1]
            lm = blk > 0
            if lm.any():
                land[y, x] = True
                v = blk[lm]
                mean[y, x] = int(round(v.mean()))
                mx[y, x] = int(v.max())
                f = fine[y * fs:(y + 1) * fs, x * fs:(x + 1) * fs]
                fl = f[f > 0]
                relief[y, x] = int(fl.max() - fl.min()) if fl.size else 0
    if DUMP:
        np.savez(DUMP, mean=mean, mx=mx, relief=relief, land=land)
    cls = classify(mean, mx, relief, land, cfg["thresholds"], w, h)
    # Distance of each cell centre to the nearest river, tenths of a cell.
    segs = []
    for r in rivers:
        pts = [proj.px(p[0], p[1]) for p in r["pts"]]
        for i in range(len(pts) - 1):
            segs.append(pts[i] + pts[i + 1])
    S = np.array(segs)
    cx = (np.arange(w) + 0.5) * cpx
    cy = (np.arange(h) + 0.5) * cpx
    CX, CY = np.meshgrid(cx, cy)
    best = np.full((h, w), 1e9)
    for a in S:
        d = np.array([a[2] - a[0], a[3] - a[1]])
        L2 = max(d @ d, 1e-12)
        t = np.clip(((CX - a[0]) * d[0] + (CY - a[1]) * d[1]) / L2, 0, 1)
        dd = np.hypot(CX - (a[0] + d[0] * t), CY - (a[1] + d[1] * t))
        best = np.minimum(best, dd)
    rdist = np.minimum((best / cpx * 10).round().astype(int), 99)
    # Fine fields as bytes.
    code = np.clip(np.round(np.sqrt(fine) * FINE_K), 0, 255).astype(np.uint8)
    dec = (code.astype(np.float64) / FINE_K) ** 2
    pad = np.pad(dec, 1, mode="edge")
    gx = (pad[1:-1, 2:] - pad[1:-1, :-2]) / 2.0
    gy = (pad[2:, 1:-1] - pad[:-2, 1:-1]) / 2.0
    step_m = fpx / proj.px_lat * 111320.0
    slope = np.clip(np.round(np.hypot(gx, gy) / step_m * 100.0), 0, 255).astype(np.uint8)
    pad2 = np.pad(dec, 2, mode="edge")
    win = np.stack([pad2[2 + dy:2 + dy + fh, 2 + dx:2 + dx + fw] for dy in range(-2, 3) for dx in range(-2, 3)])
    rel = np.clip(np.round((win.max(0) - win.min(0)) / 8.0), 0, 255).astype(np.uint8)
    stats = {"w": w, "h": h, "fw": fw, "fh": fh, "cells_by_class": {k: int((cls == k).sum()) for k in range(5)},
             "max_m": int(mx.max()), "fine_bytes": [len(zlib.compress(code.tobytes(), 9)), len(zlib.compress(slope.tobytes(), 9)),
                                                    len(zlib.compress(rel.tobytes(), 9))]}
    if dry:
        return stats
    ed = ["extends RefCounted",
          "## Real elevation of the campaign grid cells. GENERATED by tools/geo_fit.py from",
          "## ETOPO 2022 (NOAA, public domain) and Natural Earth rivers: do not edit by hand.",
          "## One entry per grid cell, index y * W + x (the cells of grid_data.gd).",
          "## MEAN / MAXH: mean and maximum elevation in metres of the DEM land samples",
          "## inside the cell (0: none). RELIEF: highest minus lowest fine sample in the",
          "## cell, metres. RIVER_DIST: distance of the cell centre to the nearest river",
          "## line, tenths of a cell (0-99, 99: 9.9 cells or more). CLASS: one string per row,",
          "## a character per cell: \".\" sea, \"0\" plain, \"1\" rolling, \"2\" valley, \"3\" hill,",
          "## \"4\" ridge (thresholds in tools/geo_fit.py). tools/campaign_grid.gd turns 3 / 4",
          "## into the TERRAIN overrides. The fine fields are in game/campaign/relief_data.gd.",
          "",
          "const W := %d" % w, "const H := %d" % h,
          "const MEAN: Array[int] = %s" % json.dumps(mean.flatten().tolist()),
          "const MAXH: Array[int] = %s" % json.dumps(mx.flatten().tolist()),
          "const RELIEF: Array[int] = %s" % json.dumps(relief.flatten().tolist()),
          "const RIVER_DIST: Array[int] = %s" % json.dumps(rdist.flatten().tolist()),
          "const CLASS: Array[String] = ["]
    for y in range(h):
        ed.append('\t"%s",' % "".join("." if cls[y, x] == 255 else str(cls[y, x]) for x in range(w)))
    ed.append("]")
    open(os.path.join(repo, "campaign/data/elev_data.gd"), "w").write("\n".join(ed) + "\n")
    rd = ["extends RefCounted",
          "## Fine elevation fields of the campaign map (view only). GENERATED by",
          "## tools/geo_fit.py from ETOPO 2022 (NOAA, public domain): do not edit by hand.",
          "## FS fine samples per grid cell side (FW x FH samples, row 0 = north, each",
          "## 1/FS of a cell: 0.025 degrees of latitude for FS 8 on a 0.2 degree grid).",
          "## Each field is bytes, row-major, deflate-compressed (zlib), base64 text:",
          "## FINE: mean land elevation of the sample's footprint, v = round(sqrt(metres) *",
          "## FINE_K), so metres = (v / FINE_K)^2 (0: sea); SLOPE: gradient in percent (rise",
          "## over run, 0-255); RELIEF_F: highest minus lowest FINE in the 5 x 5 window, in",
          "## units of 8 m. Decode with game/campaign/geo_fields.gd.",
          "",
          "const FS := %d" % fs, "const FW := %d" % fw, "const FH := %d" % fh,
          "const FINE_K := %s" % FINE_K,
          'const FINE := "%s"' % b64z(code.tobytes()),
          'const SLOPE := "%s"' % b64z(slope.tobytes()),
          'const RELIEF_F := "%s"' % b64z(rel.tobytes())]
    open(os.path.join(repo, "game/campaign/relief_data.gd"), "w").write("\n".join(rd) + "\n")
    return stats


FINE_K = 3.8
DUMP = os.environ.get("GEO_FIT_DUMP")   # debugging: dump the cell statistics (npz)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--dem", required=True)
    ap.add_argument("--ne", required=True)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--dem-lon0", type=float, default=-10.7)
    ap.add_argument("--dem-lat0", type=float, default=32.8)
    ap.add_argument("--dem-step", type=float, default=1.0 / 120)
    ap.add_argument("--dem-rows", type=int, default=1729)
    ap.add_argument("--dem-cols", type=int, default=4369)
    ap.add_argument("--dem-south-first", action="store_true")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--skip-geo", action="store_true", help="only the elevation products")
    args = ap.parse_args()
    cfg = json.load(open(args.config))
    proj = Proj(cfg)
    mg = os.path.join(args.repo, "game/campaign/map_geo.gd")
    check_projection(mg, proj)
    lands, islands, notes, dropped = build_land(cfg, proj, args.ne)
    print("landmasses: %s vertices; %d islands kept (%d vertices), %d dropped" % (
        [len(l) for l in lands], len(islands), sum(len(i) for i in islands), dropped))
    for key, pt, c, dist in notes:
        print("settlement %s at %s is off its land by %.3f deg: nearest land point %.3f, %.3f" % (key, pt, dist, c[0], c[1]))
    rivers, rep = build_rivers(cfg, proj, args.ne)
    print("\n".join(rep))
    if not args.dry:
        write_map_geo(mg, cfg, lands, islands, rivers)
    z = load_dem(args.dem, args)
    dem = Dem(z, args.dem_lon0, args.dem_lat0, args.dem_step)
    print(bake_elevation(cfg, proj, dem, rivers, args.repo, args.dry))


if __name__ == "__main__":
    main()
