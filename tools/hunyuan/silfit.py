#!/usr/bin/env python3
"""Silhouette fit: deform a character mesh to the four silhouettes of its turnaround sheet.

numpy / scipy / PIL only (venv python, no Blender, no GPU):

    ~/.venvs/hunyuan/bin/python tools/hunyuan/silfit.py NAME... --work W --out OUT [--iters 4] [--assets]

W/NAME/{front,left,right,back}.png are the sheet crops (alpha = silhouette).  The input is the first
mesh.glb seen (kept in OUT/orig/NAME.glb, so a re-run starts from the same mesh); the result is written to
OUT/fitted/NAME.glb, or over assets/characters/NAME/mesh.glb with --assets.  Topology, vertex and triangle
order and UVs are unchanged: only the POSITION (and NORMAL) accessors of the glb are rewritten, the embedded
texture stays.  OUT also gets before / after tables, overlays (sheet alpha red, mesh blue, overlap purple)
and W/NAME/silfit_map.npz (orig -> fitted positions) that hy_paint.py bake uses to match triangles by index.

Method (README "Silhouette fit"): the views are the frames texture.py / paint_render.py use (per-view
horizontal scale / offset least squares, frozen from the input mesh).  Per view and image row (every 2 px)
the extreme left / right pixels of each silhouette span of the mesh and of the sheet are paired (rows whose
span counts differ are skipped); the mesh vertices nearest the mesh's extreme point become soft handles
whose target is the horizontal displacement that brings the mesh span end onto the sheet's.  The
displacement field is the minimiser of a biharmonic (cotangent) smoothness energy plus soft handle terms,
one sparse solve per axis (front / back constrain x, left / right constrain y, z is never moved), repeated
with fresh correspondences, each step capped at 3 cm per vertex.
"""
import json
import os
import struct
import sys
import time

import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spl
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
HEIGHT_M = {"captain": 1.85, "mercy": 1.8, "rook": 2.0}
VIEWS = ["front", "left", "right", "back"]
# image-right axis (u) per view for a figure facing -y (as paint_render.VDEF)
VU = {"front": (1, 0, 0), "back": (-1, 0, 0), "left": (0, 1, 0), "right": (0, -1, 0)}
STEP_CM = 3.0
MAX_PX = 20          # a row whose span ends are further apart than this is another feature, not a gap to close
LAP = 10.0
VW = 1.0             # weight of the vertical (column) correspondences against the horizontal ones
VERTICAL = True
ROW_STEP = 2


# ------------------------------------------------------------------ glb io (only the accessors we change)
def read_glb(path):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    js = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", b[off:off + 4])[0]
    binb = bytearray(b[off + 8:off + 8 + bl])
    return js, binb


def accessor(js, binb, i, dtype, ncomp):
    acc = js["accessors"][i]
    bv = js["bufferViews"][acc["bufferView"]]
    o = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return np.frombuffer(binb, dtype=dtype, count=acc["count"] * ncomp, offset=o).reshape(-1, ncomp)


def load_mesh(path):
    """Blender-frame positions (z up, facing -y), triangle indices, the glb parts for writing back."""
    js, binb = read_glb(path)
    prim = js["meshes"][0]["primitives"][0]
    pos = accessor(js, binb, prim["attributes"]["POSITION"], np.float32, 3).astype(np.float64)
    idt = {5123: np.uint16, 5125: np.uint32}[js["accessors"][prim["indices"]]["componentType"]]
    tri = accessor(js, binb, prim["indices"], idt, 1).reshape(-1, 3).astype(np.int64)
    v = np.stack([pos[:, 0], -pos[:, 2], pos[:, 1]], 1)
    return v, tri, (js, binb, prim)


def save_mesh(src, dst, v, tri):
    """Copy the glb at `src` to `dst` with new positions (Blender frame) and recomputed normals."""
    js, binb, prim = load_mesh(src)[2]
    pos = np.stack([v[:, 0], v[:, 2], -v[:, 1]], 1).astype(np.float32)
    pa = prim["attributes"]["POSITION"]
    accessor(js, binb, pa, np.float32, 3)[:] = pos
    js["accessors"][pa]["min"] = [float(x) for x in pos.min(0)]
    js["accessors"][pa]["max"] = [float(x) for x in pos.max(0)]
    if "NORMAL" in prim["attributes"]:
        nrm = accessor(js, binb, prim["attributes"]["NORMAL"], np.float32, 3)
        wi, inv = weld(v)
        fn = np.cross(v[tri[:, 1]] - v[tri[:, 0]], v[tri[:, 2]] - v[tri[:, 0]])
        acc = np.zeros((len(wi), 3))
        for k in range(3):
            np.add.at(acc, inv[tri[:, k]], fn)
        acc /= np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-12)
        a = acc[inv]
        nrm[:] = np.stack([a[:, 0], a[:, 2], -a[:, 1]], 1).astype(np.float32)
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * (-len(jb) % 4)
    bb = bytes(binb) + b"\0" * (-len(binb) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(bb), 0x004E4942) + bb)


def weld(v, tol=1e-5):
    key = np.round(v / tol).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return first, inv.ravel()


# ------------------------------------------------------------------ views (the frames of paint_render.View / fit_view)
class View:
    def __init__(self, key, path):
        a = np.asarray(Image.open(path).convert("RGBA"), np.float32) / 255.0
        self.key = key
        self.alpha = a[..., 3]
        self.mask = self.alpha > 0.5
        ys, xs = np.nonzero(self.mask)
        self.x0, self.x1, self.y0, self.y1 = xs.min(), xs.max(), ys.min(), ys.max()
        self.h_px = self.y1 - self.y0
        self.cx = xs.mean()
        self.u = np.array(VU[key], float)
        self.fit = None
        self.fit_report = ""

    def project(self, v):
        a, b, c, d = self.fit
        return a * (v @ self.u) + b, c * v[:, 2] + d


def silhouette_ucen(vw, v, zmin, H):
    sc = vw.h_px / H
    u = v @ vw.u
    G = 256
    s = G / vw.alpha.shape[0]
    gx = np.clip(((u - u.mean()) * sc * s + G / 2).astype(int), 0, G - 1)
    gy = np.clip(((v[:, 2] - zmin) * sc * s).astype(int), 0, G - 1)
    occ = np.zeros((G, G), bool)
    occ[gy, gx] = True
    ys, xs = np.nonzero(occ)
    return (xs.mean() - G / 2) / (sc * s) + u.mean()


def fit_view(vw, v, zmin, H, bands=(0.10, 0.30, 0.50, 0.70, 0.90)):
    """texture.py's per-view fit (paint_render.fit_view): px = a*u + b, py = c*z + d."""
    ucen = silhouette_ucen(vw, v, zmin, H)
    sc = vw.h_px / H
    c, d = -sc, vw.y1 + zmin * sc
    nom = (sc, vw.cx - ucen * sc, c, d)
    u = v @ vw.u
    al = vw.mask
    xs_m, xs_s = [], []
    for f in bands:
        zlo, zhi = zmin + (f - 0.04) * H, zmin + (f + 0.04) * H
        sel = (v[:, 2] >= zlo) & (v[:, 2] <= zhi)
        r0, r1 = int(c * zhi + d), int(c * zlo + d)
        if sel.sum() < 20 or r1 <= r0:
            continue
        cols = np.nonzero(al[max(r0, 0):r1 + 1].any(0))[0]
        if len(cols) == 0:
            continue
        xs_m += [u[sel].min(), u[sel].max()]
        xs_s += [cols.min(), cols.max()]
    vw.fit = nom
    vw.fit_report = "nominal"
    if len(xs_m) >= 6:
        A = np.stack([xs_m, np.ones(len(xs_m))], 1)
        (a, b), *_ = np.linalg.lstsq(A, np.array(xs_s, float), rcond=None)
        res = np.abs(A @ np.array([a, b]) - xs_s)
        ok = 0.88 < a / sc < 1.12 and res.mean() < 0.03 * vw.alpha.shape[1]
        vw.fit_report = "scale x %.3f offset %+.1f px residual %.1f px %s" % (
            a / sc, a * ucen + b - vw.cx, res.mean(), "applied" if ok else "UNSTABLE, nominal kept")
        if ok:
            vw.fit = (a, b, c, d)
    return vw.fit


def set_frames(views, v, zmin, H, bands=(0.10, 0.30, 0.50, 0.70, 0.90)):
    """The frames the mesh is fitted to: the sheet's own scale in all four views (figure height = mesh height,
    same px per unit everywhere) and one common centre per axis pair (front / back share x, left / right
    share y), from a translation-only fit of the left / right extents at five height bands.  This is the
    frame texture.py's fit reports scale 1.0 / offset 0 against once the mesh matches the sheet."""
    cen = {}
    for k, vw in views.items():
        sc = vw.h_px / H
        c, d = -sc, vw.y1 + zmin * sc
        u = v @ vw.u
        est = []
        for f in bands:
            zlo, zhi = zmin + (f - 0.04) * H, zmin + (f + 0.04) * H
            sel = (v[:, 2] >= zlo) & (v[:, 2] <= zhi)
            r0, r1 = int(c * zhi + d), int(c * zlo + d)
            cols = np.nonzero(vw.mask[max(r0, 0):r1 + 1].any(0))[0]
            if sel.sum() < 20 or len(cols) == 0:
                continue
            est += [(cols.min() - sc * u[sel].min()), (cols.max() - sc * u[sel].max())]
        vw.b0 = float(np.median(est))
        cen[k] = vw
    for pair, ax in ((("front", "back"), 0), (("left", "right"), 1)):
        # image centre column = u s; the world coordinate at the image centre is s for the +axis view, -s for the other
        ws = []
        for k in pair:
            vw = views[k]
            sc = vw.h_px / H
            ws.append(((vw.alpha.shape[1] / 2 - vw.b0) / sc) * (1.0 if vw.u[ax] > 0 else -1.0))
        x0 = float(np.mean(ws))
        for k in pair:
            vw = views[k]
            sc = vw.h_px / H
            s_k = x0 * (1.0 if vw.u[ax] > 0 else -1.0)
            vw.fit = (sc, vw.alpha.shape[1] / 2 - sc * s_k, -sc, vw.y1 + zmin * sc)
            vw.fit_report = "scale 1.000 (nominal) centre %.4f (views differ by %.2f cm)" % (x0, abs(ws[0] - ws[1]) * 100 * 1.85 / H)


# ------------------------------------------------------------------ silhouettes and metrics
def raster(vw, v, tri):
    px, py = vw.project(v)
    im = Image.new("L", vw.alpha.shape[::-1], 0)
    dr = ImageDraw.Draw(im)
    pts = np.stack([px, py], 1)[tri]
    for t in pts:
        dr.polygon([tuple(t[0]), tuple(t[1]), tuple(t[2])], fill=255)
    return np.asarray(im) > 127


def boundary(m):
    return m & ~ndimage.binary_erosion(m, border_value=0)


def metrics(vw, M, cm_px):
    S = vw.mask
    iou = (M & S).sum() / max(1, (M | S).sum())
    bm, bs = boundary(M), boundary(S)
    d_to_s = ndimage.distance_transform_edt(~bs)
    d_to_m = ndimage.distance_transform_edt(~bm)
    dd = np.concatenate([d_to_s[bm], d_to_m[bs]])
    return iou, dd.mean(), dd.mean() * cm_px


def spans(row):
    """(left, right) pixel index pairs of the runs of True in a 1-D bool array."""
    d = np.diff(np.concatenate([[0], row.astype(np.int8), [0]]))
    return list(zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0] - 1))


# ------------------------------------------------------------------ correspondences
def correspondences(vw, v, tri, M, max_px=None, vertical=False):
    """List of (vertex index, displacement (mesh units along the view's u, or along z when vertical), weight)
    soft handles.  vertical: the same pairing along image columns (top / bottom ends of the spans)."""
    max_px = max_px or MAX_PX
    px, py = vw.project(v)
    S = vw.mask
    if vertical:
        tree = cKDTree(np.stack([py, px], 1))
        M, S = M.T, S.T
        a = vw.fit[2]
        rows = list(range(vw.x0 + 1, vw.x1, ROW_STEP))
    else:
        tree = cKDTree(np.stack([px, py], 1))
        a = vw.fit[0]
        rows = list(range(vw.y0 + 1, vw.y1, ROW_STEP))
    # per (side, span index): sequences of (row, x_mesh, x_sheet, weight)
    seq = {}
    for y in rows:
        sm, ss = spans(M[y]), spans(S[y])
        if len(sm) != len(ss) or len(sm) == 0:
            continue
        for i, ((ml, mr), (sl, sr)) in enumerate(zip(sm, ss)):
            w = (VW if vertical else 1.0) / len(sm)
            for side, xm, xs in ((0, ml, sl), (1, mr, sr)):
                if abs(xs - xm) > max_px:
                    continue
                seq.setdefault((side, i), []).append((y, xm, xs - xm, w))
    acc = {}
    for (side, i), s in seq.items():
        s = np.array(s, float)
        # runs of consecutive rows; the targets are smoothed over a 5-row window inside a run
        brk = np.nonzero(np.diff(s[:, 0]) > ROW_STEP * 2)[0] + 1
        for run in np.split(np.arange(len(s)), brk):
            r = s[run]
            gap = r[:, 2]
            if len(r) >= 3:
                k = np.ones(5) / 5
                pad = np.pad(gap, 2, mode="edge")
                gap = np.convolve(pad, k, mode="valid")
            for (y, xm, _g, w), g in zip(r, gap):
                # vertices within 1.5 px of the extreme point of the mesh span (nearest 3 at most)
                dist, idx = tree.query([xm, y], k=3, distance_upper_bound=1.5)
                ok = np.isfinite(dist)
                if not ok.any():
                    dist, idx = tree.query([xm, y], k=1)
                    dist, idx, ok = np.array([dist]), np.array([idx]), np.array([True])
                for dj, j in zip(dist[ok], idx[ok]):
                    e = acc.setdefault(int(j), [0.0, 0.0])
                    ww = w / (1.0 + dj)
                    e[0] += ww
                    e[1] += ww * g
    out = []
    for j, (w, gw) in acc.items():
        out.append((j, (gw / w) / a, w))
    return out


# ------------------------------------------------------------------ deformation
def cot_laplacian(v, tri, n):
    """Cotangent stiffness matrix (PSD, positive off-diagonal negated) and lumped vertex areas."""
    i0, i1, i2 = tri[:, 0], tri[:, 1], tri[:, 2]
    p0, p1, p2 = v[i0], v[i1], v[i2]
    e0, e1, e2 = p2 - p1, p0 - p2, p1 - p0           # opposite edges of vertex 0, 1, 2
    area = 0.5 * np.linalg.norm(np.cross(e2, -e1), axis=1)
    ok = area > 1e-14
    cot = np.stack([
        -(e1 * e2).sum(1), -(e2 * e0).sum(1), -(e0 * e1).sum(1)], 1) / (2 * np.maximum(area, 1e-14))[:, None]
    cot = np.clip(cot, 0.02, 20.0) * ok[:, None]
    I = np.concatenate([i1, i2, i2, i0, i0, i1])
    J = np.concatenate([i2, i1, i0, i2, i1, i0])
    Wv = np.concatenate([cot[:, 0], cot[:, 0], cot[:, 1], cot[:, 1], cot[:, 2], cot[:, 2]]) * 0.5
    W = sp.coo_matrix((Wv, (I, J)), shape=(n, n)).tocsr()
    L = sp.diags(np.asarray(W.sum(1)).ravel()) - W
    mass = np.zeros(n)
    for k in range(3):
        np.add.at(mass, tri[:, k], area / 3.0)
    return L.tocsr(), np.maximum(mass, 1e-12)


def solve_axis(L, M, handles, n, w_h, bi=1.0, lap=None, damp=1e-4):
    lap = LAP if lap is None else lap
    """argmin  bi d'(L M^-1 L)d + lap d'L d + damp d'Md + w_h sum h (d_i - t_i)^2   (M normalised to mean 1)."""
    Mi = sp.diags(1.0 / M)
    Q = bi * (L @ Mi @ L) + lap * L + damp * sp.diags(M)
    hd = np.zeros(n)
    rhs = np.zeros(n)
    for j, t, w in handles:
        hd[j] += w
        rhs[j] += w * t
    A = (Q + sp.diags(w_h * hd)).tocsc()
    d = spl.splu(A).solve(w_h * rhs)
    return d


def count_intersections(v, tri, wid, ids=False):
    """Triangle-triangle crossings between triangles sharing no (welded) vertex (edge-through-triangle tests)."""
    t = wid[tri]
    P = v[tri]
    cen = P.mean(1)
    rad = np.linalg.norm(P - cen[:, None, :], axis=2).max(1)
    tree = cKDTree(cen)
    pairs = tree.query_pairs(2.0 * rad.max(), output_type="ndarray")
    i, j = pairs[:, 0], pairs[:, 1]
    keep = np.linalg.norm(cen[i] - cen[j], axis=1) <= rad[i] + rad[j]
    i, j = i[keep], j[keep]
    share = (t[i][:, :, None] == t[j][:, None, :]).any(axis=(1, 2))
    i, j = i[~share], j[~share]

    def seg_tri(A, B, T):          # segments A->B against triangles T (m,3,3)
        e1, e2 = T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
        dvec = B - A
        h = np.cross(dvec, e2)
        a = (e1 * h).sum(1)
        ok = np.abs(a) > 1e-14
        f = 1.0 / np.where(ok, a, 1.0)
        s = A - T[:, 0]
        u = f * (s * h).sum(1)
        q = np.cross(s, e1)
        w = f * (dvec * q).sum(1)
        tt = f * (e2 * q).sum(1)
        return ok & (u >= 0) & (w >= 0) & (u + w <= 1) & (tt >= 0) & (tt <= 1)

    hit = np.zeros(len(i), bool)
    for c0 in range(0, len(i), 400000):
        a, b = i[c0:c0 + 400000], j[c0:c0 + 400000]
        h = np.zeros(len(a), bool)
        for k in range(3):
            h |= seg_tri(P[a][:, k], P[a][:, (k + 1) % 3], P[b])
            h |= seg_tri(P[b][:, k], P[b][:, (k + 1) % 3], P[a])
        hit[c0:c0 + 400000] = h
    if ids:
        return np.unique(np.concatenate([i[hit], j[hit]]))
    return int(hit.sum())


def fit(v0, tri, views, height_m, iters=4, w_h=100.0, log=print):
    first, inv = weld(v0)
    nw = len(first)
    wtri = inv[tri]
    okt = (wtri[:, 0] != wtri[:, 1]) & (wtri[:, 1] != wtri[:, 2]) & (wtri[:, 0] != wtri[:, 2])
    wtri = wtri[okt]
    units_per_cm = (v0[:, 2].max() - v0[:, 2].min()) / (height_m * 100.0)
    cap = STEP_CM * units_per_cm
    v = v0.copy()
    A = sp.coo_matrix((np.ones(len(wtri) * 6), (np.concatenate([wtri[:, 0], wtri[:, 1], wtri[:, 2], wtri[:, 1], wtri[:, 2], wtri[:, 0]]),
                                              np.concatenate([wtri[:, 1], wtri[:, 2], wtri[:, 0], wtri[:, 0], wtri[:, 1], wtri[:, 2]]))), shape=(nw, nw)).tocsr()
    A.data[:] = 1.0
    deg = np.asarray(A.sum(1)).ravel()
    base_x = count_intersections(v0, tri, inv)
    for it in range(iters):
        t0 = time.time()
        vw_pos = np.zeros((nw, 3))
        vw_pos[inv] = v
        L, M = cot_laplacian(vw_pos, wtri, nw)
        M = M / M.mean()
        # a view's handles are on the (duplicated) glb vertices: map them to welded ids
        hx, hy, hz = {}, {}, {}
        nh = 0
        for k, vw in views.items():
            Msk = raster(vw, v, tri)
            for j, du, w in correspondences(vw, v, tri, Msk):
                e = vw.u
                ax = 0 if abs(e[0]) > 0.5 else 1
                tgt = du * e[ax]
                dst = hx if ax == 0 else hy
                g = int(inv[j])
                cur = dst.setdefault(g, [0.0, 0.0])
                cur[0] += w
                cur[1] += w * tgt
                nh += 1
            if VERTICAL:
                for j, dz, w in correspondences(vw, v, tri, Msk, vertical=True):
                    g = int(inv[j])
                    cur = hz.setdefault(g, [0.0, 0.0])
                    cur[0] += w
                    cur[1] += w * dz
                    nh += 1
        d = np.zeros((nw, 3))
        for ax, hd in ((0, hx), (1, hy), (2, hz)):
            if not hd:
                continue
            hs = [(g, s / w, w) for g, (w, s) in hd.items()]
            d[:, ax] = solve_axis(L, M, hs, nw, w_h)
        mag = np.linalg.norm(d, axis=1)
        scale = np.minimum(1.0, cap / np.maximum(mag, 1e-12))
        d *= scale[:, None]
        # local backtracking: where the step makes triangles cross, the vertices of those triangles (and their
        # neighbours) take half the step, until the step crosses nothing that did not already cross
        base_ids = set(count_intersections(v, tri, inv, ids=True).tolist()) if base_x else set()
        s = np.ones(nw)
        nb_rounds = 0
        vn = v
        for _r in range(14):
            vn = v + (d * s[:, None])[inv]
            ids = count_intersections(vn, tri, inv, ids=True)
            ids = np.array([t for t in ids if t not in base_ids], int)
            if len(ids) == 0:
                break
            nb_rounds += 1
            bad = np.zeros(nw, bool)
            bad[inv[tri[ids]].ravel()] = True
            bad = (A @ bad.astype(float) > 0) | bad
            if _r < 8:
                s[bad] *= 0.5
                for _k in range(2):                  # a step field that falls off smoothly, never frozen next to moving
                    s = np.minimum(s, 0.5 * s + 0.5 * (A @ s) / np.maximum(deg, 1))
            else:
                s *= 0.6                             # last resort: the whole step shrinks
        else:
            vn = v
        v = vn
        log("  iter %d: %d handle hits, %d x / %d y / %d z handles, max step %.2f cm, mean %.2f cm, %d backtracks, scaled %d vertices (%.1fs)" % (
            it + 1, nh, len(hx), len(hy), len(hz), mag.max() / units_per_cm, mag.mean() / units_per_cm, nb_rounds, int((s < 1).sum()), time.time() - t0))
    return v


# ------------------------------------------------------------------ report
def table(name, views, v, tri, height_m, tag):
    rows = []
    for k in VIEWS:
        vw = views[k]
        M = raster(vw, v, tri)
        cm_px = height_m * 100.0 / vw.h_px
        iou, bpx, bcm = metrics(vw, M, cm_px)
        rows.append((k, iou, bpx, bcm))
    print("  %-8s %-6s %8s %10s %10s" % (name, tag, "IoU", "bdist px", "bdist cm"))
    for k, iou, bpx, bcm in rows:
        print("  %-8s %-6s %8.4f %10.2f %10.2f" % ("", k, iou, bpx, bcm))
    return rows


def overlay(vw, M):
    img = np.full(vw.mask.shape + (3,), 255, np.uint8)
    S = vw.mask
    img[S & ~M] = (225, 40, 40)
    img[M & ~S] = (40, 60, 230)
    img[S & M] = (150, 60, 190)
    return img


def save_overlays(name, views, vb, va, tri, out):
    os.makedirs(out, exist_ok=True)
    tiles = []
    for k in VIEWS:
        vw = views[k]
        b, a = overlay(vw, raster(vw, vb, tri)), overlay(vw, raster(vw, va, tri))
        y0, y1 = max(vw.y0 - 12, 0), min(vw.y1 + 12, vw.mask.shape[0])
        x0, x1 = max(vw.x0 - 12, 0), min(vw.x1 + 12, vw.mask.shape[1])
        pair = np.concatenate([b[y0:y1, x0:x1], np.full((y1 - y0, 6, 3), 0, np.uint8), a[y0:y1, x0:x1]], 1)
        Image.fromarray(pair).save(os.path.join(out, "overlay_%s_%s.png" % (name, k)))
        tiles.append((b, a))
    G = 512
    rowb = np.concatenate([np.asarray(Image.fromarray(t[0]).resize((G, G), Image.BILINEAR)) for t in tiles], 1)
    rowa = np.concatenate([np.asarray(Image.fromarray(t[1]).resize((G, G), Image.BILINEAR)) for t in tiles], 1)
    Image.fromarray(np.concatenate([rowb, np.zeros((6, rowb.shape[1], 3), np.uint8), rowa], 0)).save(
        os.path.join(out, "overlay_%s.png" % name))


def main():
    argv = sys.argv[1:]
    names, a = [], {"work": None, "out": None, "iters": 4, "assets": False, "w": 100.0}
    i = 0
    while i < len(argv):
        k = argv[i]
        if k in ("--work", "--out"):
            a[k[2:]] = argv[i + 1]; i += 1
        elif k == "--iters":
            a["iters"] = int(argv[i + 1]); i += 1
        elif k == "--w":
            a["w"] = float(argv[i + 1]); i += 1
        elif k == "--maxpx":
            global MAX_PX
            MAX_PX = int(argv[i + 1]); i += 1
        elif k == "--vw":
            global VW
            VW = float(argv[i + 1]); i += 1
        elif k == "--novert":
            global VERTICAL
            VERTICAL = False
        elif k == "--lap":
            global LAP
            LAP = float(argv[i + 1]); i += 1
        elif k == "--step":
            global STEP_CM
            STEP_CM = float(argv[i + 1]); i += 1
        elif k == "--assets":
            a["assets"] = True
        else:
            names.append(k)
        i += 1
    for name in names:
        t0 = time.time()
        orig = os.path.join(a["out"], "orig", name + ".glb")
        cur = os.path.join(REPO, "assets", "characters", name, "mesh.glb")
        if not os.path.exists(orig):
            os.makedirs(os.path.dirname(orig), exist_ok=True)
            open(orig, "wb").write(open(cur, "rb").read())
        v0, tri, _ = load_mesh(orig)
        hm = HEIGHT_M[name]
        zmin, H = v0[:, 2].min(), v0[:, 2].max() - v0[:, 2].min()
        views = {k: View(k, os.path.join(a["work"], name, k + ".png")) for k in VIEWS}
        print("[%s] %d vertices, %d triangles, height %.3f units = %.2f m" % (name, len(v0), len(tri), H, hm))
        for k, vw in views.items():
            fit_view(vw, v0, zmin, H)
            print("  texture.py fit of the input mesh %-5s %s" % (k, vw.fit_report))
        set_frames(views, v0, zmin, H)
        wid = weld(v0)[1]
        before = table(name, views, v0, tri, hm, "before")
        x0 = count_intersections(v0, tri, wid)
        v1 = fit(v0, tri, views, hm, a["iters"], a["w"])
        after = table(name, views, v1, tri, hm, "after")
        x1 = count_intersections(v1, tri, wid)
        disp = np.linalg.norm(v1 - v0, axis=1) * hm * 100.0 / H
        print("  displacement cm: mean %.2f  p95 %.2f  max %.2f; triangle crossings %d -> %d" % (
            disp.mean(), np.percentile(disp, 95), disp.max(), x0, x1))
        # triangle flips
        n0 = np.cross(v0[tri[:, 1]] - v0[tri[:, 0]], v0[tri[:, 2]] - v0[tri[:, 0]])
        n1 = np.cross(v1[tri[:, 1]] - v1[tri[:, 0]], v1[tri[:, 2]] - v1[tri[:, 0]])
        cs = (n0 * n1).sum(1) / np.maximum(np.linalg.norm(n0, axis=1) * np.linalg.norm(n1, axis=1), 1e-18)
        print("  triangles flipped (normal dot < 0): %d" % int((cs < 0).sum()))
        # refit frames on the result: texture.py's fit should now read ~1.0 / ~0
        for k, vw in views.items():
            fit_view(vw, v1, v1[:, 2].min(), v1[:, 2].max() - v1[:, 2].min())
            print("  refit %-5s %s" % (k, vw.fit_report))
        # (the overlays and tables above used the frozen frames)
        set_frames(views, v0, zmin, H)
        save_overlays(name, views, v0, v1, tri, a["out"])
        dst = cur if a["assets"] else os.path.join(a["out"], "fitted", name + ".glb")
        save_mesh(orig, dst, v1, tri)
        wd = os.path.join(a["work"], name)
        first = weld(v0)[0]
        np.savez(os.path.join(wd, "silfit_map.npz"), orig=v0[first], fitted=v1[first])
        json.dump({"before": before, "after": after, "crossings": [x0, x1]},
                  open(os.path.join(a["out"], "silfit_%s.json" % name), "w"))
        print("  wrote %s (%.1fs)" % (dst, time.time() - t0))


if __name__ == "__main__":
    main()
