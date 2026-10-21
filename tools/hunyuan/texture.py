"""Projection texture bake for the Hunyuan character meshes (numpy only, no bpy).

Used by paint_render.py.  For every texel of the mesh's UV layout it finds the
sheet view that sees the surface best, takes the sheet colour there, snaps it to
the character's toon palette (label) and adds a detail layer (sheet luminance
against the local mean of the same label), so eyes, brows, mouth, buttons, belt
and lace survive while the colours stay the game's flat palette.
"""
import numpy as np

INK = np.array([0x1a, 0x14, 0x10]) / 255.0
DETAIL_LO, DETAIL_HI = -0.35, 0.25
INK_LUMA = 0.55                           # ink only where sheet luma < this x the face's median
INK_FROM, INK_TO = -0.20, -0.32          # raw detail at which the ink starts / is complete


# ------------------------------------------------------------------ small image helpers
def box_mean(a, r):
    """Mean over a (2r+1)^2 window, edge-clamped, via cumulative sums (a: HxW or HxWxC)."""
    a = np.asarray(a, np.float64)
    pad = [(r + 1, r), (r + 1, r)] + [(0, 0)] * (a.ndim - 2)
    p = np.pad(a, pad, mode="edge")
    c = np.cumsum(np.cumsum(p, 0), 1)
    k = 2 * r + 1
    H, W = a.shape[:2]
    s = c[k:k + H, k:k + W] - c[0:H, k:k + W] - c[k:k + H, 0:W] + c[0:H, 0:W]
    return s / (k * k)


def luma(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def bilinear(img, x, y):
    """img HxWxC (or HxW); x, y pixel coordinates (centres at +0.5 are NOT assumed: pixel i is at i)."""
    H, W = img.shape[:2]
    x = np.clip(x, 0, W - 1.001)
    y = np.clip(y, 0, H - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    if img.ndim == 3:
        fx, fy = fx[:, None], fy[:, None]
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def classify(rgb, pal_lab, owner, ncol, rgb_to_lab, zf=None, bands=None):
    """Nearest palette entry of every colour (any leading shape), lightness counted little."""
    sh = rgb.shape[:-1]
    lab = rgb_to_lab(rgb.reshape(-1, 3))
    dist = np.empty((len(lab), len(pal_lab)))
    for j in range(len(pal_lab)):
        dl = (lab[:, 0] - pal_lab[j, 0]) * 0.6
        da, db = lab[:, 1] - pal_lab[j, 1], lab[:, 2] - pal_lab[j, 2]
        dist[:, j] = dl * dl + da * da + db * db
    dd = np.full((len(lab), ncol), 1e9)
    for j, o in enumerate(owner):
        dd[:, o] = np.minimum(dd[:, o], dist[:, j])
    if bands:
        zff = zf.reshape(-1)
        for i, (lo, hi) in bands.items():
            dd[(zff < lo) | (zff > hi), i] += 1e5
    return dd.argmin(1).reshape(sh)


def majority(lab, valid, ncol, passes=1, r=1):
    """3x3 majority filter of an index image; only valid texels vote and change."""
    for _ in range(passes):
        best = np.full(lab.shape, -1.0, np.float32)
        out = lab.copy()
        for l in range(ncol):
            c = np.zeros(lab.shape, np.float32)
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    m = np.roll(np.roll((lab == l) & valid, dy, 0), dx, 1)
                    c += m * (1.5 if (dy == 0 and dx == 0) else 1.0)
            better = c > best
            out[better] = l
            best[better] = c[better]
        lab = np.where(valid, out, lab)
    return lab


def components(lab, valid):
    """4-connected components of equal label among valid texels: (id image, count), ids -1 outside."""
    T = lab.shape
    ids = np.where(valid, np.arange(lab.size).reshape(T), -1)
    for _ in range(400):
        old = ids
        new = ids.copy()
        for ax, sh in ((0, 1), (0, -1), (1, 1), (1, -1)):
            nb_ids = np.roll(ids, sh, ax)
            nb_lab = np.roll(lab, sh, ax)
            nb_val = np.roll(valid, sh, ax)
            m = valid & nb_val & (nb_lab == lab) & (nb_ids >= 0) & (nb_ids < new)
            new = np.where(m, nb_ids, new)
        flat = new.ravel()
        jump = np.where(flat >= 0, flat[np.maximum(flat, 0)], -1).reshape(T)   # pointer jumping
        new = np.where(valid, np.minimum(new, jump), -1)
        if (new == old).all():
            break
        ids = new
    return ids


def remove_small(lab, valid, small_thresh, ncol):
    """Reassign every component smaller than its threshold (per texel array) to the label of its
    longest shared border.  Returns (labels, number of components removed)."""
    ids = components(lab, valid)
    flat = ids.ravel()
    cnt = np.bincount(flat[flat >= 0], minlength=lab.size)
    thr = small_thresh.ravel()
    small = (flat >= 0) & (cnt[np.maximum(flat, 0)] < thr)
    comps = np.unique(flat[small])
    if len(comps) == 0:
        return lab, 0
    cmap = {c: i for i, c in enumerate(comps)}
    lut = np.full(lab.size, -1, np.int64)
    lut[comps] = np.arange(len(comps))
    border = np.zeros((len(comps), ncol))
    sm = small.reshape(lab.shape)
    for ax, sh in ((0, 1), (0, -1), (1, 1), (1, -1)):
        nl = np.roll(lab, sh, ax)
        nv = np.roll(valid, sh, ax)
        m = sm & nv & (nl != lab)
        np.add.at(border, (lut[ids[m]], nl[m]), 1.0)
    new_lab = border.argmax(1)
    has = border.max(1) > 0
    out = lab.copy()
    sel = np.nonzero(small)[0]
    li = lut[flat[sel]]
    ok = has[li]
    out.ravel()[sel[ok]] = new_lab[li[ok]]
    return out, int(has.sum())


def dilate_into(img, valid, passes):
    """Spread colours of valid texels into the empty neighbourhood (island bleed)."""
    m = valid.copy()
    c = img.copy()
    for _ in range(passes):
        acc = np.zeros_like(c)
        cnt = np.zeros(m.shape, np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                mm = np.roll(np.roll(m, dy, 0), dx, 1)
                acc += np.roll(np.roll(c, dy, 0), dx, 1) * mm[..., None]
                cnt += mm
        new = (~m) & (cnt > 0)
        c[new] = acc[new] / cnt[new][:, None]
        m = m | new
    return c, m


def dilate_labels(lab, valid, passes):
    m = valid.copy()
    c = lab.copy()
    for _ in range(passes):
        new_c, new_m = c.copy(), m.copy()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            mm = np.roll(np.roll(m, dy, 0), dx, 1)
            cc = np.roll(np.roll(c, dy, 0), dx, 1)
            take = mm & ~new_m
            new_c[take] = cc[take]
            new_m |= take
        c, m = new_c, new_m
    return c


# ------------------------------------------------------------------ UV rasteriser
def rasterize(uv, tri_pos, tri_nrm, T, order=None):
    """uv: (ntri,3,2) in 0..1 (v up); tri_pos / tri_nrm: (ntri,3,3); order: draw order (later wins).
    Returns (valid TxT bool, pos TxTx3, nrm TxTx3, tri id TxT), row index = v * T (v up)."""
    valid = np.zeros((T, T), bool)
    tid = np.full((T, T), -1, np.int32)
    pos = np.zeros((T, T, 3))
    nrm = np.zeros((T, T, 3))
    p = uv * T
    eps = 0.03
    for i in (range(len(uv)) if order is None else order):
        a, b, c = p[i]
        x0 = int(np.floor(min(a[0], b[0], c[0]) - 0.5))
        x1 = int(np.ceil(max(a[0], b[0], c[0]) + 0.5))
        y0 = int(np.floor(min(a[1], b[1], c[1]) - 0.5))
        y1 = int(np.ceil(max(a[1], b[1], c[1]) + 0.5))
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, T - 1), min(y1, T - 1)
        if x1 < x0 or y1 < y0:
            continue
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        xs = np.arange(x0, x1 + 1) + 0.5
        ys = np.arange(y0, y1 + 1) + 0.5
        X, Y = np.meshgrid(xs, ys)
        l0 = ((b[1] - c[1]) * (X - c[0]) + (c[0] - b[0]) * (Y - c[1])) / den
        l1 = ((c[1] - a[1]) * (X - c[0]) + (a[0] - c[0]) * (Y - c[1])) / den
        l2 = 1 - l0 - l1
        m = (l0 >= -eps) & (l1 >= -eps) & (l2 >= -eps)
        if not m.any():
            continue
        yy, xx = np.nonzero(m)
        L0, L1, L2 = l0[m][:, None], l1[m][:, None], l2[m][:, None]
        pos[yy + y0, xx + x0] = L0 * tri_pos[i, 0] + L1 * tri_pos[i, 1] + L2 * tri_pos[i, 2]
        nrm[yy + y0, xx + x0] = L0 * tri_nrm[i, 0] + L1 * tri_nrm[i, 1] + L2 * tri_nrm[i, 2]
        valid[yy + y0, xx + x0] = True
        tid[yy + y0, xx + x0] = i
    n = np.linalg.norm(nrm, axis=-1, keepdims=True)
    nrm = nrm / np.maximum(n, 1e-9)
    return valid, pos, nrm, tid


# ------------------------------------------------------------------ the bake
def bake(valid, pos, nrm, vid, views, ucen, zmin, H, pal_rgb, pal_lab, owner, bands, names,
         rgb_to_lab, srgb_to_lin, lin_to_srgb, blur_label=3, detail_r=12, shift=None, debug=False,
         head_ids=(), face_z=0.87, head_z=0.82, detail_ids=(), stats=None, alias=None, rules=None):
    """vid: (T,T) index into list(views) of the chart's view per texel.  Returns (albedo TxTx3 sRGB,
    labels TxT int, covered texels).  Arrays are v-up."""
    T = valid.shape[0]
    ncol = len(names)
    idx = np.nonzero(valid.reshape(-1))[0]
    P = pos.reshape(-1, 3)[idx]
    V = vid.reshape(-1)[idx]
    zf = (P[:, 2] - zmin) / H
    n = len(idx)
    smp_col = np.zeros((n, 3))     # blurred colour (classification)
    smp_det = np.zeros((n, ncol))  # detail against each label's local mean
    smp_L = np.zeros(n)
    covered = np.zeros(n, bool)
    for ki, (k, vw) in enumerate(views.items()):
        t = np.nonzero(V == ki)[0]
        if len(t) == 0:
            continue
        px, py, depth, sc = vw.project(P[t], zmin, H, ucen[k])
        if shift and k in shift:
            px = px + shift[k][0]
            py = py + shift[k][1]
        view_means(vw, pal_lab, owner, ncol, bands, names, rgb_to_lab, blur_label, detail_r)
        means = vw._means
        smp_col[t] = bilinear(vw.col_lab, px, py)
        L = bilinear(vw.luma, px, py)
        smp_L[t] = L
        for l in range(ncol):
            m = bilinear(means[l], px, py)
            smp_det[t, l] = (L - m) / np.maximum(m, 0.30)
        G = vw.alpha.shape[0]
        covered[t] = vw.alpha[np.clip(py.astype(int), 0, G - 1), np.clip(px.astype(int), 0, G - 1)] > 0.5
    # the head band only knows the head's labels (nearest of them in Lab)
    hb = dict(bands or {})
    allowed = set(head_ids)
    dd_bands = dict(hb)
    lab = classify(smp_col, pal_lab, owner, ncol, rgb_to_lab, zf, bands)
    if len(allowed):
        face = zf >= face_z
        forb = [i for i in range(ncol) if i not in allowed]
        own2 = np.array([(alias or {}).get(o, o) for o in owner])
        lab2 = classify_restricted(smp_col[face], pal_lab, own2, ncol, rgb_to_lab, sorted(allowed), zf[face], bands)
        lab[face] = lab2
    rules = rules or {}
    hat_z = rules.get("hat_z", 2.0)
    zone = zf >= hat_z
    if zone.any() and rules.get("zone_ids"):
        lab[zone] = classify_restricted(smp_col[zone], pal_lab, owner, ncol, rgb_to_lab, sorted(rules["zone_ids"]), zf[zone], bands)
    # grazing texels (up / down facing surfaces no side view sees): the sheet colour there is the
    # silhouette's edge smeared across them, so they take the label of the nearest well-seen texel
    keys = list(views.keys())
    facing = np.array([vw.to_cam for vw in views.values()])[V]
    facing = (nrm.reshape(-1, 3)[idx] * facing).sum(1)
    g = np.clip((facing - 0.30) / 0.30, 0, 1)
    weak = np.nonzero(g <= 0)[0]
    strong = np.nonzero(g >= 1)[0][::6]
    big = [i for i, nm in enumerate(names) if nm in ("coat", "leather", "trousers", "hat", "boots", "headscarf")]
    for body in (True, False):
        # below the head the donors are cloth only (the neck's skin must not creep over the shoulders)
        w_all = weak[(zf[weak] < 0.80) == body]
        st = strong[np.isin(lab[strong], big)] if body else strong
        if len(w_all) and len(st):
            for c0 in range(0, len(w_all), 1000):
                w = w_all[c0:c0 + 1000]
                d = ((P[w][:, None, :] - P[st][None, :, :]) ** 2).sum(-1)
                lab[w] = lab[st[d.argmin(1)]]
    lab_img = np.zeros((T * T,), np.int32)
    lab_img[idx] = lab
    lab_img = lab_img.reshape(T, T)
    lab_img = majority(lab_img, valid, ncol, 2)
    # connected-component clean-up per texture island: small blobs join their longest border neighbour
    zf_img = np.zeros(T * T)
    zf_img[idx] = zf
    zf_img = zf_img.reshape(T, T)
    thr = np.where(zf_img >= head_z, 80, 120)
    thr = np.where(zf_img >= hat_z, 400, thr)
    removed = 0
    for _ in range(2):
        lab_img, r = remove_small(lab_img, valid, thr, ncol)
        removed += r
    lab_img = majority(lab_img, valid, ncol, 1, r=2)
    # a hat character's skin is one face per view: stray skin-coloured trim in the head charts goes to the hat
    names_l = list(names)
    if "skin" in names_l and "hat" in names_l and "hat" in [names_l[i] for i in head_ids]:
        si, hi = names_l.index("skin"), names_l.index("hat")
        vid_img = np.zeros(T * T, np.int32)
        vid_img[idx] = V
        vid_img = vid_img.reshape(T, T)
        sk = (lab_img == si) & valid & (zf_img >= head_z)
        ids = components(np.where(sk, 1, 0).astype(np.int32), sk)
        f = ids.ravel()
        sz = np.bincount(f[f >= 0], minlength=T * T)
        for k in range(len(views)):
            m = sk & (vid_img == k)
            if not m.any():
                continue
            big = sz[f[m.ravel()]].max()
            stray = m & (sz[np.maximum(ids, 0)] < 0.35 * big)
            lab_img[stray] = hi
            if stats is not None:
                stats["stray_skin"] = stats.get("stray_skin", 0) + int(stray.sum())
    force_ink = np.zeros((T, T), bool)
    L_img = np.zeros(T * T)
    L_img[idx] = smp_L
    L_img = L_img.reshape(T, T)
    col_img = np.zeros((T * T, 3))
    col_img[idx] = smp_col
    col_img = col_img.reshape(T, T, 3)
    nm = list(names)
    # rule 2: hat / headscarf pieces below the hat zone that are not connected to it are skin or hair
    if rules.get("hat_ids") and zone.any():
        hat_ids = rules["hat_ids"]
        keep_set = list(set(hat_ids) | set(rules.get("zone_ids", [])))
        m = np.isin(lab_img, keep_set) & valid
        ids = components(m.astype(np.int32), m)
        f = ids.ravel()
        touch = np.zeros(T * T, bool)
        zone_img = zf_img >= hat_z
        touch[np.unique(f[(zone_img & m).ravel()])] = True
        stray = m & ~touch[np.maximum(ids, 0)] & np.isin(lab_img, hat_ids)
        if stray.any():
            tgt = [nm.index(x) for x in ("skin", "hair") if x in nm]
            ys, xs = np.nonzero(stray)
            lab_img[ys, xs] = classify_restricted(col_img[ys, xs], pal_lab, owner, ncol, rgb_to_lab, tgt, zf_img[ys, xs], bands)
        if stats is not None:
            stats["hat_stray"] = int(stray.sum())
    # rule 3: red / coat specks in the face band are the lips: a line (ink) if dark, else skin
    if "skin" in nm and rules.get("mouth"):
        cl = [nm.index(x) for x in ("coat", "sash") if x in nm]
        face_m = (zf_img >= head_z) & (zf_img < hat_z) & valid
        sk_med = np.median(L_img[face_m & (lab_img == nm.index("skin"))]) if (face_m & (lab_img == nm.index("skin"))).any() else 1.0
        m = np.isin(lab_img, cl) & face_m
        ids = components(np.where(m, lab_img, -1).astype(np.int32), m)
        f = ids.ravel()
        sz = np.bincount(f[f >= 0], minlength=T * T)
        small = m & (sz[np.maximum(ids, 0)] < 150)
        lab_img[small] = nm.index("skin")
        force_ink |= small & (L_img < sk_med)
        if stats is not None:
            stats["mouth"] = int(small.sum())
    # rule 4: skin below the face that is not joined to the face or to the hands is coat
    if rules.get("skin_prune") and "skin" in nm and "coat" in nm:
        si = nm.index("skin")
        m = (lab_img == si) & valid
        ids = components(m.astype(np.int32), m)
        f = ids.ravel()
        good = np.zeros(T * T, bool)
        ok_px = m & ((zf_img >= 0.80) | (zf_img < 0.55))
        good[np.unique(f[ok_px.ravel()])] = True
        bad = m & ~good[np.maximum(ids, 0)]
        lab_img[bad] = nm.index("coat")
        if stats is not None:
            stats["skin_pruned"] = int(bad.sum())
    lab = lab_img.reshape(-1)[idx]
    if stats is not None:
        stats["removed"] = removed
    det_raw = smp_det[np.arange(n), lab] * g
    # detail and ink only on skin / hair: cloth, leather, metal and hats keep the flat palette colour
    use = np.isin(lab, list(detail_ids))
    det_raw = np.where(use, det_raw, 0.0)
    det = np.clip(det_raw, DETAIL_LO, DETAIL_HI)
    base = srgb_to_lin(pal_rgb[lab]) * (1 + det)[:, None]
    col = lin_to_srgb(np.clip(base, 0, 1))
    # ink: only dark texels (luma < 0.35 x the face's median) in blobs of >= 6 texels
    ink_ids = [i for i in detail_ids if names[i] == "skin"]
    skin_m = np.isin(lab, ink_ids) & (g > 0)
    inkm = np.zeros(n, bool)
    if skin_m.any():
        med = np.median(smp_L[skin_m])
        inkm = skin_m & (det_raw < INK_FROM) & (smp_L < INK_LUMA * med)
    ink_img = np.zeros(T * T, bool)
    ink_img[idx] = inkm
    ink_img = ink_img.reshape(T, T)
    cc = components(ink_img.astype(np.int32), ink_img)
    cf = cc.ravel()
    sizes = np.bincount(cf[cf >= 0], minlength=T * T)
    keep = (cf >= 0) & (sizes[np.maximum(cf, 0)] >= 6)
    inkm = keep.reshape(T, T).ravel()[idx]
    if stats is not None:
        stats["ink_texels"] = int(inkm.sum())
    inkm = inkm | force_ink.reshape(-1)[idx]
    col = np.where(inkm[:, None], INK, col)
    col = np.where(covered[:, None], col, pal_rgb[lab])        # no view saw it: palette colour only
    out = np.zeros((T * T, 3))
    out[idx] = col
    out = out.reshape(T, T, 3)
    if debug:
        for i in range(ncol):
            print("  label %-9s %6d texels" % (names[i], int((lab == i).sum())))
        print("  uncovered texels: %d of %d" % (int((~covered).sum()), n))
    return out, lab_img, valid


def classify_restricted(rgb, pal_lab, owner, ncol, rgb_to_lab, allowed, zf, bands):
    sh = rgb.shape[:-1]
    lab = rgb_to_lab(rgb.reshape(-1, 3))
    dd = np.full((len(lab), ncol), 1e9)
    for j, o in enumerate(owner):
        if o not in allowed:
            continue
        dl = (lab[:, 0] - pal_lab[j, 0]) * 0.6
        dist = dl * dl + (lab[:, 1] - pal_lab[j, 1]) ** 2 + (lab[:, 2] - pal_lab[j, 2]) ** 2
        dd[:, o] = np.minimum(dd[:, o], dist)
    for i, (lo, hi) in (bands or {}).items():
        dd[(zf < lo) | (zf > hi), i] += 1e5
    return dd.argmin(1)


# ------------------------------------------------------------------ atlas from the sheet views
def adjacency(tri):
    """(ntri,3) neighbour triangle across each edge, -1 where open / non-manifold ignored."""
    n = len(tri)
    e = np.stack([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]], 1).reshape(-1, 2)
    key = np.minimum(e[:, 0], e[:, 1]).astype(np.int64) * (tri.max() + 1) + np.maximum(e[:, 0], e[:, 1])
    order = np.argsort(key, kind="stable")
    ks = key[order]
    nb = np.full(n * 3, -1, np.int64)
    same = ks[1:] == ks[:-1]
    i0 = order[:-1][same]
    i1 = order[1:][same]
    nb[i0] = i1 // 3
    nb[i1] = i0 // 3
    return nb.reshape(n, 3)


def assign_views(v, tri, vnrm, views, ucen, zmin, H, head_z, smooth=8, report=None):
    """The sheet view that owns each triangle: best facing among the views that see it, the head's
    front owned by the front view; neighbour vote so the charts are not speckled.
    Returns (view index per tri, visible-in-its-view flag per tri)."""
    keys = list(views.keys())
    cen = v[tri].mean(1)
    fn = vnrm[tri].sum(1)
    fn = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    zf = (cen[:, 2] - zmin) / H
    head = zf >= head_z
    W = np.zeros((len(tri), len(keys)))
    VIS = np.zeros((len(tri), len(keys)), bool)
    for ki, k in enumerate(keys):
        vw = views[k]
        # z-buffer from the vertices and the triangle centres
        pts = np.concatenate([v, cen])
        px, py, depth, sc = vw.project(pts, zmin, H, ucen[k])
        G = vw.alpha.shape[0]
        gx = np.clip(np.round(px).astype(int), 0, G - 1)
        gy = np.clip(np.round(py).astype(int), 0, G - 1)
        zb = np.full(G * G, 1e9)
        np.minimum.at(zb, gy * G + gx, depth)
        zb = zb.reshape(G, G)
        zn = zb.copy()
        for dy in (-2, -1, 0, 1, 2):
            for dx in (-2, -1, 0, 1, 2):
                zn = np.minimum(zn, np.roll(np.roll(zb, dy, 0), dx, 1))
        nv = len(v)
        cd = depth[nv:]
        vis = cd <= zn[gy[nv:], gx[nv:]] + 0.015 * H
        facing = fn @ vw.to_cam
        w = np.where(vis, np.maximum(facing, 0) + 1.0, np.maximum(facing, 0) * 0.2)
        if k == "front":
            w = w + np.where(head & (facing > 0.5), 5.0, 0.0)
        elif k in ("left", "right"):
            w = w - np.where(head & (fn @ np.array([0.0, -1.0, 0.0]) > 0.5), 5.0, 0.0)
        W[:, ki] = w
        VIS[:, ki] = vis
    own = W.argmax(1)
    nb = adjacency(tri)
    for _ in range(smooth):
        cnt = np.zeros((len(tri), len(keys)))
        cnt[np.arange(len(tri)), own] += 1.5
        for j in range(3):
            g = nb[:, j]
            ok = g >= 0
            np.add.at(cnt, (np.nonzero(ok)[0], own[g[ok]]), 1.0)
        # a triangle may only move to a view that has some claim on it (facing at all)
        cnt = cnt * (W > 0.15)
        own = np.where(cnt.max(1) > 0, cnt.argmax(1), own)
    return own, VIS[np.arange(len(tri)), own]


def build_atlas(v, tri, own, views, zmin, H, head_z, T=1024, head_density=2.0, pad=14):
    """Planar chart per (view, body / head): UV = the view's own (u, z) scaled and shelf-packed.
    Returns uv (ntri,3,2) in 0..1."""
    keys = list(views.keys())
    cz = (v[tri, 2].mean(1) - zmin) / H
    head = cz >= head_z
    charts = []
    for ki, k in enumerate(keys):
        vw = views[k]
        for part in (0, 1):
            sel = np.nonzero((own == ki) & (head == bool(part)))[0]
            if len(sel) == 0:
                continue
            pts = v[tri[sel]].reshape(-1, 3)
            u = pts @ vw.u
            z = pts[:, 2]
            charts.append(dict(ki=ki, part=part, sel=sel, u0=u.min(), z0=z.min(), du=u.max() - u.min(), dz=z.max() - z.min()))

    def pack(s):
        items = [(c["du"] * s * (head_density if c["part"] else 1) + 2 * pad,
                  c["dz"] * s * (head_density if c["part"] else 1) + 2 * pad, i) for i, c in enumerate(charts)]
        items.sort(key=lambda t: -t[1])
        x = y = rowh = 0
        place = {}
        for w, h, i in items:
            if x + w > T:
                x, y, rowh = 0, y + rowh, 0
            if rowh == 0:
                rowh = h
            place[i] = (x, y)
            x += w
        return y + rowh <= T and all(p[0] + 1 <= T for p in place.values()), place

    lo, hi = 1e-3, 1.0
    for c in charts:
        pass
    hi = 4.0 * T / H
    for _ in range(40):
        mid = (lo + hi) / 2
        ok, _p = pack(mid)
        if ok:
            lo = mid
        else:
            hi = mid
    ok, place = pack(lo)
    uv = np.zeros((len(tri), 3, 2))
    for i, c in enumerate(charts):
        vw = views[keys[c["ki"]]]
        f = lo * (head_density if c["part"] else 1)
        ox, oy = place[i]
        t = tri[c["sel"]]
        pts = v[t]                                  # (m,3,3)
        uu = pts @ vw.u
        uv[c["sel"], :, 0] = ((uu - c["u0"]) * f + ox + pad) / T
        uv[c["sel"], :, 1] = ((pts[..., 2] - c["z0"]) * f + oy + pad) / T
    return uv, lo


def view_means(vw, pal_lab, owner, ncol, bands, names, rgb_to_lab, blur_label, detail_r):
    """Per-view cache: blurred Lab image, luma and, per label, the local mean luma of that label."""
    if getattr(vw, "_means", None) is not None:
        return vw._lab_img, vw._means
    H, W = vw.alpha.shape
    col = box_mean(vw.col_src, blur_label)
    vw.col_lab = col
    vw.luma = luma(vw.rgb_bled)
    yy = np.arange(H)[:, None] * np.ones((1, W))
    zf = (vw.y1 - yy) / max(vw.h_px, 1)
    lab_img = classify(col, pal_lab, owner, ncol, rgb_to_lab, zf, bands)
    al = (vw.alpha > 0.5)
    means = []
    for l in range(ncol):
        m = (lab_img == l) & al
        num = box_mean(vw.luma * m, detail_r)
        den = box_mean(m.astype(np.float64), detail_r)
        glob = vw.luma[m].mean() if m.any() else 0.5
        # blend towards the global mean where the label is scarce in the window
        wgt = np.clip(den * (2 * detail_r + 1) ** 2 / 40.0, 0, 1)
        loc = num / np.maximum(den, 1e-6)
        means.append(loc * wgt + glob * (1 - wgt))
    vw._lab_img, vw._means = lab_img, means
    return lab_img, means
