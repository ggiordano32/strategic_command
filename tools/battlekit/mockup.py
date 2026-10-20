"""Style mockups for the battle map: kit board and scene composites.

    python3 tools/battlekit/mockup.py board  --frames DIR --out DIR
    python3 tools/battlekit/mockup.py scene NAME [--style A|B] --shots DIR --frames DIR --out DIR

Scenes: hill, coast, close, valley (composited on the landforms screenshots;
units and the HUD are lifted from the original screenshot).
"""
import math
import os
import subprocess
import sys
import numpy as np
from kitlib import *

PAL = {
    "roman": {"R": (0.78, 0.34, 0.22), "G": (0.90, 0.83, 0.68), "B": (0.70, 0.18, 0.16)},
    "spanish": {"R": (0.84, 0.48, 0.28), "G": (0.95, 0.92, 0.82), "B": (0.88, 0.68, 0.20)},
    "north": {"R": (0.40, 0.45, 0.52), "G": (0.80, 0.72, 0.58), "B": (0.25, 0.35, 0.65)},
    "adobe": {"R": (0.62, 0.48, 0.36), "G": (0.78, 0.60, 0.42), "B": (0.20, 0.55, 0.55)},
}
STYLE = {
    "A": dict(amb=0.66, key=0.55, sh_elev=40, sh_tint=(0.62, 0.66, 0.76), sh_str=0.95, ao=0.40, rim=0.05, ol=0.24,
              ol_w=1, sat=0.86, contrast=1.04, lift=0.0, spec=0.0, bump=1.0, exag=1.3, sh_len=30.0, ground_sat=0.9),
    "B": dict(amb=0.50, key=0.88, sh_elev=30, sh_tint=(0.50, 0.54, 0.80), sh_str=0.9, ao=0.55, rim=0.22, ol=0.55,
              ol_w=1, sat=1.22, contrast=1.12, lift=0.035, spec=0.16, bump=1.6, exag=1.6, sh_len=44.0, ground_sat=0.98),
}


def arg(name, default=None):
    a = sys.argv
    return a[a.index(name) + 1] if name in a else default


def sat(c, s):
    lum = (c * np.array([0.3, 0.59, 0.11], np.float32)).sum(-1, keepdims=True)
    return np.clip(lum + (c - lum) * s, 0, 1)


class Ground:
    def __init__(self, seed=3):
        self.tex = make_ground(seed)
        rng = np.random.default_rng(seed + 1)
        self.warp = pnoise(256, 2.6, rng)

    def sample(self, name, W, H, ppm, ang=0.0, off=(0, 0)):
        """world-aligned (rotated by ang for fields), two scales blended to hide the tiling."""
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        X = (xx + off[0]) / ppm / TEXM
        Y = (yy + off[1]) / ppm / TEXM
        c, s = math.cos(ang), math.sin(ang)
        U = X * c + Y * s
        V = -X * s + Y * c
        alb, bmp = self.tex[name]
        a1 = sample_tex(alb, U, V)
        b1 = sample_tex(bmp[..., None], U, V)[..., 0]
        if name in ("plough", "crop", "wheat"):
            return a1, b1
        a2 = sample_tex(alb, U * 0.71 + 0.37, V * 0.71 + 0.11)
        b2 = sample_tex(bmp[..., None], U * 0.71 + 0.37, V * 0.71 + 0.11)[..., 0]
        k = smoothstep(-0.6, 0.6, sample_tex(self.warp[..., None], X * 0.31, Y * 0.31)[..., 0])[..., None]
        return a1 * k + a2 * (1 - k), (b1 * k[..., 0] + b2 * (1 - k[..., 0]))


def splat(g, sc, weights, style, ang_fields=None):
    """weights: dict name -> (H,W) weight; adds painterly irregular edges and
    fills sc.alb / sc.bump."""
    H, W, ppm = sc.H, sc.W, sc.ppm
    rng = np.random.default_rng(11)
    nz = pnoise(256, 2.0, rng)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    jit = sample_tex(nz[..., None], xx / ppm / 120.0, yy / ppm / 120.0)[..., 0]
    names = list(weights)
    ws = []
    for nme in names:
        w = weights[nme] + 0.08 * jit * (weights[nme] > 0.02) * (weights[nme] < 0.98)
        ws.append(np.clip(w, 0, 1) ** 1.7)
    tot = np.maximum(sum(ws), 1e-4)
    alb = np.zeros((H, W, 3), np.float32)
    bump = np.zeros((H, W), np.float32)
    for nme, w in zip(names, ws):
        w = w / tot
        if w.max() < 0.003:
            continue
        ang = (ang_fields or {}).get(nme, 0.0)
        a, b = g.sample(nme, W, H, ppm, ang)
        alb += a * w[..., None]
        bump += b * w
    sc.alb[:] = sat(alb, style["ground_sat"])
    sc.bump[:] = bump * 0.8


def label_cmd(p, labels, size=12):
    cmd = ["convert", p, "-font", "DejaVu-Sans", "-pointsize", str(size), "-strokewidth", "3", "-stroke", "#000c", "-fill", "#000c"]
    for n, x, yy in labels:
        cmd += ["-annotate", "+%d+%d" % (x - 3.4 * len(n), yy), n]
    cmd += ["-stroke", "none", "-fill", "white"]
    for n, x, yy in labels:
        cmd += ["-annotate", "+%d+%d" % (x - 3.4 * len(n), yy), n]
    subprocess.run(cmd + [p], check=True)


GROUPS = [
    ["wall_s", "wall_m", "wall_l", "wall_corner", "tower_round", "tower_round_roof", "tower_sq", "tower_sq_roof", "gate_closed", "gate_open"],
    ["palisade_s", "palisade_m", "palisade_gate", "bastion", "fence", "well", "stall", "cart", "barrels"],
    ["house_gable_s", "house_gable_m", "house_gable_l", "house_hip_s", "house_hip_m", "longhouse", "house_L", "hut_round", "hut_thatch"],
    ["church", "temple"],
    ["tree_broad_a", "tree_broad_b", "tree_broad_c", "tree_pine_a", "tree_pine_b", "tree_palm_a", "tree_palm_b", "bush_a", "bush_b",
     "rock_a", "rock_b", "rock_c", "cliff_m"],
]


# Landmark and civic pieces (spec_pieces.py): `board --set landmarks`.
GROUPS_NEW = [
    ["lm_morro", "lm_morro_sj", "lm_san_felipe", "lm_san_marcos", "lm_ulua"],
    ["lm_fuerza", "lm_harbour_fort", "lm_fort_charles", "lm_rock_fort", "cv_fort", "lm_baluarte", "lm_bast_wall"],
    ["lm_byrsa", "lm_euryalus", "lm_acropolis", "lm_cothon", "lm_greek_temple"],
    ["lm_alcazar", "cv_capitol", "cv_temple", "cv_basilica", "cv_tower_rome", "cv_mansion"],
    ["cv_cathedral", "cv_twin_cathedral", "cv_church", "cv_chapel", "cv_itza_temple", "cv_maya_pyramid"],
    ["lm_careened", "lm_tavern", "lm_gallows"],
]


def pal_for(n):
    if n.startswith(("lm_", "cv_")):
        return PAL["spanish"] if n in ("lm_alcazar", "cv_cathedral", "cv_twin_cathedral", "cv_church", "cv_chapel", "lm_morro",
                                       "lm_morro_sj", "lm_san_felipe", "lm_san_marcos", "lm_ulua", "lm_fuerza", "lm_harbour_fort",
                                       "lm_rock_fort", "lm_fort_charles", "cv_fort", "lm_baluarte", "lm_bast_wall") else PAL["roman"]
    if n.startswith(("house_hip", "church", "tower_sq")):
        return PAL["spanish"]
    if n in ("house_gable_m", "longhouse", "stall"):
        return PAL["north"]
    if n in ("house_L", "hut_round"):
        return PAL["adobe"]
    return PAL["roman"]


def board(frames, out, style_name, ppm=6.0, groups=None, tag=""):
    st = STYLE[style_name]
    kit = Kit(frames)
    g = Ground()
    W_ = 1900
    rows = []
    for gr in (groups or GROUPS):
        row, x, y_h = [], 16, 0
        for n in gr:
            meta, _ = kit.piece(n, PAL["roman"])
            ext = 2 * meta["rad"] / meta["ppm"] * ppm + 16
            if x + ext > W_ - 16:
                rows.append((row, y_h)); row, x, y_h = [], 16, 0
            row.append((n, x + ext / 2, ext)); x += ext; y_h = max(y_h, ext)
        rows.append((row, y_h))
    H_ = int(sum(r[1] for r in rows) + 26 * len(rows) + 30)
    sc = Scene(W_, H_, ppm)
    splat(g, sc, {"grass": np.ones((H_, W_), np.float32)}, st)
    y = 14
    labels = []
    for row, hh in rows:
        for n, cx, ext in row:
            sc.place(kit, n, cx, y + hh / 2, 0, pal=pal_for(n))
            labels.append((n, cx, y + hh + 14))
        y += hh + 26
    img, sh, ao = light_scene(sc, st)
    os.makedirs(out, exist_ok=True)
    p = os.path.join(out, "kit_board_%s%s.png" % (tag, style_name))
    save_png(p, img)
    label_cmd(p, labels)
    print("board", p, W_, H_)


def cultures(frames, out, style_name, ppm=6.0):
    st = STYLE[style_name]
    kit = Kit(frames)
    g = Ground()
    names = ["tower_sq_roof", "house_gable_m", "house_hip_m", "house_L", "church", "stall", "temple"]
    pals = ["roman", "spanish", "north", "adobe"]
    cell = 150
    W_, H_ = cell * len(names) + 20, cell * len(pals) + 20
    sc = Scene(W_, H_, ppm)
    splat(g, sc, {"dirt": np.ones((H_, W_), np.float32)}, st)
    labels = []
    for r, pn in enumerate(pals):
        for c, n in enumerate(names):
            sc.place(kit, n, 10 + c * cell + cell / 2, 10 + r * cell + cell / 2, 0.25, pal=PAL[pn], scale=0.8 if n in ("church", "temple") else 1.0)
        labels.append((pn, 36, 10 + r * cell + 14))
    img, sh, ao = light_scene(sc, st)
    p = os.path.join(out, "cultures_%s.png" % style_name)
    save_png(p, img)
    label_cmd(p, labels + [(n, 10 + c * cell + cell / 2, H_ - 3) for c, n in enumerate(names)], 11)
    print("cultures", p)


def ground_sheet(out, style_name):
    st = STYLE[style_name]
    g = Ground()
    names = ["grass", "dry", "dirt", "rock", "sand", "plough", "crop", "wheat"]
    cell = 300
    W_, H_ = cell * 4, cell * 2
    ppm = 4.2
    sc = Scene(W_, H_, ppm)
    yy, xx = np.mgrid[0:H_, 0:W_]
    labels = []
    for i, n in enumerate(names):
        cx, cy = (i % 4) * cell, (i // 4) * cell
        a, b = g.sample(n, W_, H_, ppm * 1.6, 0.0, off=(cx, cy))
        m = np.zeros((H_, W_), bool)
        m[cy:cy + cell - 4, cx:cx + cell - 4] = True
        sc.alb[m] = sat(a, st["ground_sat"])[m]
        sc.bump[m] = b[m] * 0.8
        labels.append((n, cx + cell / 2, cy + cell - 12))
    img, sh, ao = light_scene(sc, st)
    p = os.path.join(out, "ground_tiles_%s.png" % style_name)
    save_png(p, img)
    label_cmd(p, labels, 13)


def splat_demo(out, style_name):
    st = STYLE[style_name]
    g = Ground()
    Wd, Hd, ppm = 1400, 560, 4.2
    sc = Scene(Wd, Hd, ppm)
    rng = np.random.default_rng(7)
    yy, xx = np.mgrid[0:Hd, 0:Wd].astype(np.float32)
    hill = 26 * np.exp(-((xx - 560) ** 2 / (2 * 190 ** 2) + (yy - 250) ** 2 / (2 * 150 ** 2)))
    ridge = 18 * np.exp(-((xx - 1070) ** 2 / (2 * 70 ** 2))) * smoothstep(60, 160, yy) * (1 - smoothstep(380, 520, yy))
    Hm = hill + ridge + 1.2 * smooth_noise(rng, Wd, Hd, ppm, 40, 2.2) + 2.0 * smoothstep(300, 560, yy) * 0 - 4.0 * smoothstep(430, 560, yy)
    Hm = np.maximum(Hm, -0.5)
    sc.terrain = Hm.astype(np.float32)
    sc.hg = sc.terrain.copy()
    sc.nrm = terrain_normals(Hm, ppm, st["exag"])
    sl = slope_of(Hm, ppm)
    low = 1 - smoothstep(1.0, 9.0, Hm)
    high = smoothstep(9.0, 20.0, Hm)
    rockw = smoothstep(0.42, 0.78, sl)
    nz = smooth_noise(rng, Wd, Hd, ppm, 20, 2.0)
    beach = smoothstep(0.6, 0.2, Hm) * (yy > 380)
    d, w = road_weight(sc, [(0, 500), (300, 470), (700, 420), (1000, 450), (1400, 380)], 3.6)
    track = 1 - smoothstep(w * 0.75, w * 1.1, d)
    fieldm = poly_mask([(150, 90), (330, 70), (350, 190), (170, 210)], (Hd, Wd)).astype(np.float32)
    dryw = smoothstep(6.0, 15.0, Hm + 2.5 * nz)
    weights = {"grass": (0.15 + 0.85 * (1 - dryw)) * (1 - rockw), "dry": dryw * (1 - rockw),
              "dirt": np.clip(track, 0, 1), "rock": rockw, "sand": beach, "plough": gblur(fieldm, 1)}
    for k in ("grass", "dry", "dirt", "rock", "sand"):
        weights[k] = weights[k] * (1 - weights["plough"])
    splat(g, sc, weights, st)
    img, sh, ao = light_scene(sc, st)
    p = os.path.join(out, "splat_demo_%s.png" % style_name)
    save_png(p, img)
    # weights visualisation: grass green, dry yellow, dirt brown, rock grey, sand cream, field dark
    cols = {"grass": (0.2, 0.7, 0.2), "dry": (0.9, 0.85, 0.2), "dirt": (0.6, 0.35, 0.15), "rock": (0.5, 0.5, 0.55), "sand": (1, 0.95, 0.7), "plough": (0.35, 0.1, 0.1)}
    ws = {k: np.clip(weights[k], 0, 1) ** 1.7 for k in weights}
    tot = np.maximum(sum(ws.values()), 1e-4)
    vis = sum(ws[k][..., None] / tot[..., None] * np.array(cols[k], np.float32) for k in ws)
    save_png(os.path.join(out, "splat_weights.png"), vis)
    save_png(os.path.join(out, "splat_slope_height.png"), np.stack([np.clip(sl / 1.2, 0, 1), np.clip(Hm / 30, 0, 1), np.zeros_like(Hm)], -1))
    subprocess.run(["convert", p, os.path.join(out, "splat_weights.png"), "-append", os.path.join(out, "splat_demo_%s_stack.png" % style_name)], check=True)


def iso_board(frames_iso, out, style_name):
    st = STYLE[style_name]
    names = ["wall_m", "tower_round", "tower_sq_roof", "gate_open", "house_gable_m", "house_hip_m", "church", "tree_broad_b", "tree_pine_a", "tree_palm_a", "rock_b", "bastion"]
    kit = Kit(frames_iso)
    ppm = 6.0
    cell = 170
    W_, H_ = cell * 6, cell * 2
    img = np.zeros((H_, W_, 3), np.float32) + np.array([0.40, 0.5, 0.27], np.float32)
    Ln = LIGHT / np.linalg.norm(LIGHT)
    labels = []
    for i, n in enumerate(names):
        meta, stk = kit.piece(n, pal_for(n))
        N = meta["px"]
        k = meta["ppm"] / ppm
        cx, cy = (i % 6) * cell + cell / 2, (i // 6) * cell + cell / 2
        yy, xx = np.mgrid[0:cell, 0:cell].astype(np.float32)
        u = (xx - cell / 2) * k + N / 2
        v = (yy - cell / 2) * k + N / 2 - 6
        ok = (u >= 0) & (u < N - 1) & (v >= 0) & (v < N - 1)
        iu, iv = np.clip(u, 0, N - 2).astype(int), np.clip(v, 0, N - 2).astype(int)
        px_ = stk[iv, iu]
        a = px_[..., 3] * ok
        alb = px_[..., 0:3] / np.maximum(px_[..., 3:4], 1e-3)
        nn = px_[..., 4:7] / np.maximum(px_[..., 3:4], 1e-3)
        lf = (st["amb"] * (0.7 + 0.3 * (0.5 + 0.5 * nn[..., 2])) + st["key"] * np.clip(nn @ Ln, 0, 1)) / (st["amb"] + st["key"] * Ln[2])
        lit = np.clip(alb * lf[..., None], 0, 1)
        x0, y0 = int(cx - cell / 2), int(cy - cell / 2)
        sub = img[y0:y0 + cell, x0:x0 + cell]
        sub[:] = sub * (1 - a[..., None]) + lit * a[..., None]
        labels.append((n, cx, y0 + cell - 6))
    p = os.path.join(out, "iso_board_%s.png" % style_name)
    save_png(p, img)
    label_cmd(p, labels, 12)


# ================================================================== scenes
W, H = 1600, 1000


def rot_to(dx, dy):
    """rotation (screen ccw) whose local +x points along image vector (dx, dy)."""
    return math.atan2(-dy, dx)


def out_side(rot, outward):
    """True if local +y (image dir (-sin, -cos)) points to `outward` (image vector)."""
    return (-math.sin(rot)) * outward[0] + (-math.cos(rot)) * outward[1] > 0


def orient(dx, dy, outward):
    r = rot_to(dx, dy)
    if not out_side(r, outward):
        r += math.pi
    return r


def wall_run(sc, kit, nodes, centre, pal, closed=True, ppm=4.2, wscale=1.1, piece="wall_m", gate_half=None):
    """nodes: (x, y, kind) kind 'tower' | 'gate'; edges drawn between nodes, trimmed at gates."""
    n = len(nodes)
    seq = nodes + ([nodes[0]] if closed else [])
    for i in range(len(seq) - 1):
        a, b = seq[i], seq[i + 1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy)
        ux, uy = dx / L, dy / L
        ta = (gate_half or 50) * (a[3] if len(a) > 3 else 1) if a[2] == "gate" else 0
        tb = (gate_half or 50) * (b[3] if len(b) > 3 else 1) if b[2] == "gate" else 0
        p0 = (a[0] + ux * ta, a[1] + uy * ta)
        p1 = (b[0] - ux * tb, b[1] - uy * tb)
        Lc = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        if Lc < 6:
            continue
        plen = {"wall_m": 16, "wall_s": 8, "wall_l": 24}[piece] * ppm
        k = max(1, round(Lc / plen))
        mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
        outward = (mid[0] - centre[0], mid[1] - centre[1])
        rot = orient(dx, dy, outward)
        for j in range(k):
            t = (j + 0.5) / k
            cx = p0[0] + (p1[0] - p0[0]) * t
            cy = p0[1] + (p1[1] - p0[1]) * t
            sc.place(kit, piece, cx, cy, rot, sx=Lc / k / plen * 1.02, sy=wscale, pal=pal)


def node_dirs(nodes, closed=True):
    n = len(nodes)
    out = []
    for i in range(n):
        a = nodes[(i - 1) % n]
        b = nodes[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) + 1e-9
        out.append((dx / L, dy / L))
    return out


def place_nodes(sc, kit, nodes, centre, pal, towers, gates, tscale=1.0, seed=0, roof_every=0):
    dirs = node_dirs(nodes)
    rr = np.random.default_rng(seed)
    for i, nd in enumerate(nodes):
        x, y, kind = nd[:3]
        dx, dy = dirs[i]
        if kind == "gate":
            gs = nd[3] if len(nd) > 3 else 1.0
            outward = (x - centre[0], y - centre[1])
            rot = orient(dx, dy, outward)
            sc.place(kit, gates[0] if nd[4:5] != ("open",) else gates[1], x, y, rot, scale=gs, pal=pal)
        else:
            name = towers[0]
            if roof_every and i % roof_every == 0:
                name = towers[1]
            rot = rot_to(dx, dy) if "sq" in name else float(rr.uniform(0, 6.28))
            sc.place(kit, name, x, y, rot, scale=tscale, pal=pal)


def hex_dilate(m, r):
    return box_blur(m.astype(np.float32), r) > 0.02


def erode(m, r):
    return box_blur(m.astype(np.float32), r) > 0.98


def lift_units(orig, extra_cand=None, radius=60, tan=True, excl=(), thr=0.17, dark_d=0.05, dens_min=0.05):
    """returns (alpha (H,W) unit-ness, bg estimate of original) using icon colours."""
    o = orig[..., :3]
    r, g, b = o[..., 0], o[..., 1], o[..., 2]
    red = (r > 0.92) & (g < 0.5) & (b < 0.45)
    blue = (b > 0.95) & (r < 0.42) & (g < 0.65)
    ic = red | blue
    icc = erode(hex_dilate(ic, 6), 4) | ic
    icc = box_blur(icc.astype(np.float32), 1) > 0.3
    # candidate region: around icons, extending downward (formations sit below)
    cm = box_blur(ic.astype(np.float32), radius) > 0.0005
    cm = np.roll(cm, 22, axis=0)
    valid = ~icc
    bg = o.copy()
    lum = (o * np.array([0.3, 0.59, 0.11], np.float32)).sum(-1)
    unit = icc.copy()
    for it in range(3):
        wv = valid.astype(np.float32)[..., None]
        bg = box_blur(o * wv, 9) / np.maximum(box_blur(wv, 9), 1e-3)
        diff = np.abs(o - bg).max(-1)
        dark = (lum < (bg * np.array([0.3, 0.59, 0.11], np.float32)).sum(-1) - dark_d) & (lum < 0.56)
        cand = cm & (diff > thr) & dark & ~((g > r + 0.07) & (g > b + 0.07))
        if tan:
            cand = cm & (diff > 0.10) & (b >= r - 0.03) & (lum < 0.62) & ~blue
        cand &= box_blur(cand.astype(np.float32), 4) > dens_min
        unit = hex_dilate(cand, 1) | icc
        valid = ~hex_dilate(unit, 2)
    alpha = box_blur(hex_dilate(cand, 1).astype(np.float32), 1)
    alpha = np.maximum(alpha, icc.astype(np.float32))
    for (x0, y0, x1, y1) in excl:
        alpha[y0:y1, x0:x1] = 0
    return alpha, bg, icc


def finish(orig, img, alpha, bg, out_path):
    o = orig[..., :3]
    a = alpha[..., None]
    sel = np.clip(a * 6, 0, 1)
    res = img * (1 - sel) + (o + (1 - a) * (img - bg)) * sel
    for (x0, y0, x1, y1) in HUD:
        res[y0:y1, x0:x1] = o[y0:y1, x0:x1]
    res = np.clip(res, 0, 1)
    save_png(out_path, res)
    return res


HUD = [(0, 0, 105, 42), (1115, 0, 1600, 46), (0, 924, 306, 1000), (0, 962, 1600, 1000)]


def road_weight(sc, pts, width_m, closed=False):
    d = poly_dist(spline(pts) if len(pts) > 2 else pts, (sc.H, sc.W))
    w = width_m * sc.ppm / 2
    return d, w


def rect_components(mask, min_area=1500, min_fill=0.92, cell=4):
    """keep rectangle-like blobs (fields) of a boolean mask; labeling on a coarse grid."""
    Hh, Ww = mask.shape
    sm = mask[:Hh // cell * cell, :Ww // cell * cell].reshape(Hh // cell, cell, Ww // cell, cell).mean((1, 3)) > 0.5
    lab = np.zeros(sm.shape, np.int32)
    out = np.zeros(sm.shape, bool)
    n = 0
    for y0 in range(sm.shape[0]):
        for x0 in range(sm.shape[1]):
            if sm[y0, x0] and not lab[y0, x0]:
                n += 1
                st_ = [(y0, x0)]
                lab[y0, x0] = n
                cells = []
                while st_:
                    y, x = st_.pop()
                    cells.append((y, x))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        yy_, xx_ = y + dy, x + dx
                        if 0 <= yy_ < sm.shape[0] and 0 <= xx_ < sm.shape[1] and sm[yy_, xx_] and not lab[yy_, xx_]:
                            lab[yy_, xx_] = n
                            st_.append((yy_, xx_))
                ys = [c[0] for c in cells]
                xs = [c[1] for c in cells]
                bb = (max(ys) - min(ys) + 1) * (max(xs) - min(xs) + 1)
                if len(cells) * cell * cell >= min_area and len(cells) / bb >= min_fill and bb * cell * cell < 40000 and min(max(ys) - min(ys), max(xs) - min(xs)) >= 10:
                    for (y, x) in cells:
                        out[y, x] = True
    up = np.kron(out, np.ones((cell, cell), bool))
    full = np.zeros(mask.shape, bool)
    full[:up.shape[0], :up.shape[1]] = up
    return full


def field_masks(orig):
    o = (orig[..., :3] * 255)
    refs = {"crop": (122, 145, 70), "wheat": (174, 156, 94), "plough": (109, 83, 54), "crop2": (139, 159, 94), "wheat2": (180, 164, 107)}
    out = {}
    for k, ref in refs.items():
        m = (np.abs(o - np.array(ref, np.float32)).max(-1) < 6).astype(np.float32)
        m = box_blur(m, 3) > 0.45
        m = hex_dilate(m, 2)
        key = k.rstrip("2")
        out[key] = out.get(key, np.zeros_like(m)) | m
    # remove tiny speckle
    for k in list(out):
        out[k] = out[k].astype(np.float32)
    return out


def ttint(rng):
    v = rng.uniform(0.78, 1.14)
    return (v * rng.uniform(0.94, 1.08), v, v * rng.uniform(0.9, 1.04))


def tree_sites(rng, dens, step, jitter, thr, avoid=None, rect_avoid=None, scale_rng=(0.8, 1.2)):
    H_, W_ = dens.shape
    sites = []
    for y in np.arange(step / 2, H_, step):
        for x in np.arange(step / 2, W_, step):
            xx = x + rng.uniform(-jitter, jitter)
            yy = y + rng.uniform(-jitter, jitter)
            ix, iy = int(min(W_ - 1, max(0, xx))), int(min(H_ - 1, max(0, yy)))
            if dens[iy, ix] < thr + rng.uniform(-0.1, 0.1):
                continue
            if avoid is not None and avoid[iy, ix]:
                continue
            sites.append((xx, yy, rng.uniform(*scale_rng)))
    sites.sort(key=lambda s: s[1])
    return sites


def smooth_noise(rng, W_, H_, ppm, metres, beta=2.0):
    nz = pnoise(256, beta, rng)
    yy, xx = np.mgrid[0:H_, 0:W_].astype(np.float32)
    return sample_tex(nz[..., None], xx / ppm / (metres * 6.0), yy / ppm / (metres * 6.0))[..., 0]


def base_scene(orig, ppm, Hm, style, exag):
    sc = Scene(W, H, ppm)
    sc.terrain = Hm.astype(np.float32)
    sc.hg = sc.terrain.copy()
    sc.nrm = terrain_normals(sc.terrain, ppm, exag)
    return sc


def slope_of(Hm, ppm):
    gy, gx = np.gradient(Hm)
    return np.hypot(gx, gy) * ppm


def scene_hill(shots, kit, g, st, sname):
    ppm = 4.2
    orig = load_png(os.path.join(shots, "hill_town_citadel_after.png"), 8)
    rng = np.random.default_rng(21)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    rho = np.hypot((xx - 790) / 530, (yy - 430) / 430)
    Hm = 18 * (1 - smoothstep(0.74, 1.0, rho)) + 7 * np.exp(-((xx - 825) ** 2 + (yy - 205) ** 2) / (2 * 95 ** 2))
    Hm += 0.9 * smooth_noise(rng, W, H, ppm, 60, 2.2)
    sc = base_scene(orig, ppm, Hm, st, st["exag"])
    sl = slope_of(Hm, ppm)
    outer = [(604, 80), (706, 62), (830, 38), (1109, 133), (1165, 250), (1237, 400), (1037, 623), (916, 628), (812, 633), (527, 692),
             (462, 522), (376, 314)]
    inner_pm = poly_mask(outer, (H, W))
    inner = gblur(inner_pm.astype(np.float32), 6)
    cit = [(810, 122), (892, 144), (906, 220), (822, 272), (759, 185)]
    cit_m = gblur(poly_mask(cit, (H, W)).astype(np.float32), 5)
    plaza = np.zeros((H, W), np.float32)
    plaza[330:480, 676:828] = 1
    plaza = gblur(plaza, 8)
    roads = [[(706, 62), (702, 30), (698, 0)], [(1165, 250), (1260, 222), (1400, 150), (1600, 62)],
             [(462, 524), (400, 545), (300, 592), (150, 662), (0, 745)], [(916, 632), (912, 700), (905, 800), (900, 1000)]]
    track = np.zeros((H, W), np.float32)
    rut = np.zeros((H, W), np.float32)
    for r in roads:
        d, w = road_weight(sc, r, 3.6)
        track = np.maximum(track, 1 - smoothstep(w * 0.75, w * 1.1, d))
        rut = np.maximum(rut, np.exp(-((d - w * 0.4) / 1.3) ** 2) * (d < w * 1.2))
    fm = field_masks(orig)
    outside = 1 - inner
    rockw = smoothstep(0.75, 1.1, sl) * 0.8
    plateau = 1 - smoothstep(0.55, 0.82, rho)
    weights = {
        "grass": np.clip(outside * (1 - 0.8 * plateau) + 0.2, 0, 1),
        "dry": np.clip(plateau * 0.9 + 0.1 * inner, 0, 1) * (1 - rockw),
        "dirt": np.clip(track + 0.55 * inner * (1 - cit_m * 0) + plaza * 0.9 + 0.5 * cit_m, 0, 1) * (1 - rockw * 0.5),
        "rock": rockw,
        "plough": gblur(fm["plough"], 1), "crop": gblur(fm["crop"], 1), "wheat": gblur(fm["wheat"], 1),
    }
    # fields override
    fsum = np.clip(weights["plough"] + weights["crop"] + weights["wheat"], 0, 1)
    for k in ("grass", "dry", "dirt", "rock"):
        weights[k] = weights[k] * (1 - fsum)
    splat(g, sc, weights, st)
    sc.alb *= (1 - 0.14 * rut)[..., None]
    pal = PAL["roman"]
    centre = (790, 380)
    nodes = [(604, 80, "tower"), (706, 62, "gate", 1.15), (830, 38, "tower"), (1109, 133, "tower"), (1165, 250, "gate", 1.15),
             (1237, 400, "tower"), (1037, 623, "tower"), (916, 628, "gate", 1.15), (812, 633, "tower"), (527, 692, "tower"),
             (462, 522, "gate", 1.15), (376, 314, "tower")]
    wall_run(sc, kit, nodes, centre, pal, wscale=1.12, gate_half=0.5 * 20 * ppm * 1.15 * 0.95)
    place_nodes(sc, kit, nodes, centre, pal, ("tower_round", "tower_round_roof"), ("gate_closed", "gate_open"), 1.0, 2, roof_every=5)
    cn = [(810, 122, "tower"), (892, 144, "tower"), (906, 220, "tower"), (822, 272, "gate", 0.72, "open"), (759, 185, "tower")]
    wall_run(sc, kit, cn, (830, 195), pal, wscale=1.0, gate_half=0.5 * 20 * ppm * 0.72 * 0.95)
    place_nodes(sc, kit, cn, (830, 195), pal, ("tower_sq_roof", "tower_sq_roof"), ("gate_closed", "gate_open"), 0.62, 3)
    # units' footprints: avoid placing houses under them
    alpha, bg, icc = lift_units(orig, excl=[(795, 288, 840, 308)], thr=0.2, dark_d=0.04, dens_min=0.07)
    unitzone = hex_dilate(alpha > 0.5, 14)
    unitzone = hex_dilate(box_blur(icc.astype(np.float32), 40) > 0.001, 0) | unitzone
    # houses
    dwall = poly_dist(outer, (H, W), closed=True)
    dcit = poly_dist(cit, (H, W), closed=True)
    cit_in = poly_mask(cit, (H, W))
    keep_out = (dwall < 40) | (dcit < 36) | cit_in | (plaza > 0.2) | unitzone
    keep_out |= hex_dilate(sl > 0.5, 3)
    keep_out[:, :] |= ~inner_pm
    placed = []
    cand = [(rng.uniform(380, 1240), rng.uniform(80, 690)) for _ in range(9000)]
    kinds = [("house_gable_s", 21, 1.0), ("house_gable_m", 25, 0.85), ("house_gable_l", 29, 0.7), ("house_hip_s", 20, 1.0),
             ("house_hip_m", 24, 0.8), ("house_L", 27, 0.62), ("longhouse", 30, 0.55)]
    wts = np.array([3, 3, 1.2, 2.5, 1.5, 0.8, 0.5])
    wts = wts / wts.sum()
    for (x, y) in cand:
        ix, iy = int(x), int(y)
        if keep_out[iy, ix]:
            continue
        ki = int(rng.choice(len(kinds), p=wts))
        r_ = kinds[ki][1] * 0.78
        if any((x - px) ** 2 + (y - py) ** 2 < (r_ + pr + 2) ** 2 for px, py, pr, _ in placed):
            continue
        placed.append((x, y, r_, ki))
    pals = [PAL["roman"], PAL["roman"], PAL["spanish"], PAL["adobe"], PAL["north"]]
    for (x, y, r_, ki) in placed:
        name, _, sc_ = kinds[ki]
        ang = math.radians(12 + 90 * int(rng.integers(0, 2)) + rng.uniform(-9, 9))
        base = pals[int(rng.choice(len(pals), p=[0.38, 0.22, 0.2, 0.1, 0.1]))]
        j = rng.uniform(0.88, 1.1)
        pj = {k: tuple(np.clip(np.array(v) * j, 0, 1)) for k, v in base.items()}
        sc.place(kit, name, x, y, ang, pal=pj, scale=sc_)
    # plaza: well + stalls, temple (replaces the long hall)
    sc.place(kit, "well", 752, 405, 0.0, pal=pal, scale=1.0)
    for (x, y, a) in [(690, 345, 0.2), (800, 340, -0.1), (690, 465, 0.0), (810, 462, 0.15), (720, 342, 0.0), (780, 468, 0.0)]:
        sc.place(kit, "stall", x, y, a, pal=PAL["spanish"] if (x + y) % 2 else PAL["north"], scale=0.9)
    sc.place(kit, "temple", 965, 522, math.pi / 2, pal=pal, scale=0.80)
    for (x, y, k, a) in [(876, 512, "cart", 0.5), (610, 600, "barrels", 0.2), (1004, 340, "barrels", 0.3), (560, 330, "cart", 1.2)]:
        sc.place(kit, k, x, y, a, pal=pal, scale=0.9)
    # trees outside the walls and bushes on the slope
    dens = smooth_noise(rng, W, H, ppm, 35, 2.0)
    outzone = (~hex_dilate(inner_pm, 24)) & (sl < 0.55)
    fieldz = hex_dilate(fsum > 0.05, 8) | (track > 0.05) | unitzone
    dens2 = (dens > 0.5).astype(np.float32)
    for (x, y, s) in tree_sites(rng, dens2 * outzone * (~fieldz), 26, 10, 0.5, scale_rng=(0.9, 1.2)):
        k = ["tree_broad_a", "tree_broad_b", "tree_broad_c", "tree_pine_a"][int(rng.integers(0, 4))]
        sc.place(kit, k, x, y, float(rng.uniform(0, 6.28)), pal=pal, scale=0.5 * s, tint=ttint(rng))
    for i in range(60):
        x, y = rng.uniform(0, W), rng.uniform(40, 900)
        if outzone[int(y), int(x)] and not fieldz[int(y), int(x)]:
            sc.place(kit, ["bush_a", "bush_b"][i % 2], x, y, float(rng.uniform(0, 6)), pal=pal, scale=0.5)
    for (x, y, k, a) in [(172, 777, "rock_a", 1), (690, 845, "rock_b", 2), (1440, 40, "rock_a", 3), (1437, 840, "rock_a", 4)]:
        sc.place(kit, k, x, y, a, pal=pal, scale=0.55)
    sc.place(kit, "cliff_m", 312, 118, orient(55, -110, (1, 0)) - 0.0, pal=pal, scale=0.9)
    img, sh, ao = light_scene(sc, st)
    return orig, img, sh, ao, alpha, bg



def water_pass(sc, orig, st, rng):
    o = orig[..., :3]
    water = ((o[..., 2] > o[..., 0] + 0.12) & (o[..., 2] > o[..., 1])).astype(np.float32)
    water = (box_blur(water, 4) > 0.5).astype(np.float32)
    water[:, :] = water
    ds = gblur(water, 22)
    depth = smoothstep(0.5, 1.0, ds)
    shallow = np.array([0.22, 0.50, 0.55], np.float32)
    deep = np.array([0.08, 0.21, 0.33], np.float32)
    col = shallow + (deep - shallow) * depth[..., None]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    wv = pnoise(256, 1.7, rng, 8, 4.0)
    wvs = sample_tex(wv[..., None], xx / sc.ppm / 28.0, yy / sc.ppm / 28.0)[..., 0]
    hi = pnoise(256, 1.0, rng, 8, 6.0)
    his = sample_tex(hi[..., None], xx / sc.ppm / 14.0, yy / sc.ppm / 14.0)[..., 0]
    col = col * (1 + 0.10 * wvs)[..., None]
    col = col + (smoothstep(1.5, 2.4, his) * 0.35)[..., None] * np.array([0.8, 0.95, 1.0], np.float32)
    near = gblur(water, 3)
    foam = smoothstep(0.62, 0.30, near) * water * (0.55 + 0.45 * smoothstep(-0.5, 0.8, wvs))
    foam2 = smoothstep(0.78, 0.5, near) * water * smoothstep(0.2, 1.2, wvs) * 0.4
    col = col + (foam + foam2)[..., None] * (np.array([0.92, 0.96, 0.95], np.float32) - col) * 0.8
    return water, col, 0.10 * wvs


def scene_coast(shots, kit, g, st, sname):
    ppm = 4.2
    orig = load_png(os.path.join(shots, "coastal_town_after.png"), 8)
    rng = np.random.default_rng(31)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    water, wcol, wbump = water_pass(None if False else type("S", (), {"ppm": ppm})(), orig, st, rng)
    rho = np.hypot((xx - 810) / 520, (yy - 470) / 430)
    Hm = 9 * (1 - smoothstep(0.72, 1.0, rho)) + 5 * np.exp(-((xx - 975) ** 2 + (yy - 455) ** 2) / (2 * 80 ** 2))
    Hm += 0.7 * smooth_noise(rng, W, H, ppm, 60, 2.2)
    Hm = np.where(water > 0.5, -0.9, Hm)
    Hm = gblur(Hm, 2)
    sc = base_scene(orig, ppm, Hm, st, st["exag"])
    sl = slope_of(Hm, ppm)
    outer = [(537, 203), (788, 213), (1082, 228), (1237, 417), (1168, 523), (1085, 617), (981, 698), (813, 706), (650, 712), (547, 632),
             (458, 533), (378, 418), (441, 298)]
    inner_pm = poly_mask(outer, (H, W))
    inner = gblur(inner_pm.astype(np.float32), 6)
    keep = [(1037, 383), (1058, 457), (1003, 521), (937, 490), (918, 408)]
    keep_pm = poly_mask(keep, (H, W))
    plaza = np.zeros((H, W), np.float32)
    plaza[303:455, 683:835] = 1
    plaza = gblur(plaza, 8)
    d, w = road_weight(sc, [(813, 710), (810, 800), (806, 1000)], 3.6)
    track = 1 - smoothstep(w * 0.75, w * 1.1, d)
    d2, w2 = road_weight(sc, [(1082, 232), (1200, 250), (1300, 222)], 3.6)
    track = np.maximum(track, 1 - smoothstep(w2 * 0.75, w2 * 1.1, d2))
    fm = field_masks(orig)
    fsum = np.clip(fm["plough"] + fm["crop"] + fm["wheat"], 0, 1)
    rockw = smoothstep(0.75, 1.1, sl) * 0.8
    shore = smoothstep(0.08, 0.42, gblur(water, 12)) * (1 - water)
    patch = smoothstep(0.2, 0.9, smooth_noise(rng, W, H, ppm, 45, 2.2)) * (1 - inner)
    weights = {
        "dry": np.clip(1 - 0.6 * patch, 0, 1) * (1 - rockw) * (1 - shore),
        "grass": 0.55 * patch * (1 - rockw) * (1 - shore),
        "sand": shore * 1.2,
        "dirt": np.clip(track + 0.6 * inner + plaza + 0.3, 0, 1) * (1 - rockw * 0.4) * 0.8,
        "rock": rockw,
        "plough": gblur(fm["plough"], 1), "crop": gblur(fm["crop"], 1), "wheat": gblur(fm["wheat"], 1),
    }
    for k in ("dry", "grass", "dirt", "rock", "sand"):
        weights[k] = weights[k] * (1 - fsum)
    splat(g, sc, weights, st)
    wm = water[..., None]
    sc.alb = sc.alb * (1 - wm) + wcol * wm * (st["ground_sat"] ** 0.5)
    sc.bump = sc.bump * (1 - water) + wbump * water
    pal = PAL["spanish"]
    centre = (810, 420)
    nodes = [(537, 203, "bast"), (788, 213, "gate", 1.0, "open"), (1082, 228, "tower"), (1237, 417, "bast"), (1168, 523, "tower"), (1085, 617, "tower"),
             (981, 698, "bast"), (813, 706, "gate", 1.0), (650, 712, "tower"), (547, 632, "tower"), (458, 533, "tower"), (378, 418, "bast"), (441, 298, "tower")]
    wall_run(sc, kit, nodes, centre, pal, wscale=1.12, gate_half=0.5 * 20 * ppm * 0.95)
    dirs = node_dirs(nodes)
    for i, nd in enumerate(nodes):
        x, y, kind = nd[:3]
        dx, dy = dirs[i]
        outward = (x - centre[0], y - centre[1])
        if kind == "gate":
            rot = orient(dx, dy, outward)
            sc.place(kit, "gate_open" if len(nd) > 4 else "gate_closed", x, y, rot, scale=nd[3], pal=pal)
        elif kind == "bast":
            # tip (local +y) points outward
            ang = math.atan2(-outward[1], outward[0]) - math.pi / 2
            sc.place(kit, "bastion", x - outward[0] * 0.0, y, ang, scale=0.72, pal=pal)
        else:
            sc.place(kit, "tower_sq", x, y, rot_to(dx, dy), scale=0.88, pal=pal)
    ck = [(x, y, "tower") for x, y in keep[:4]] + [(918, 408, "gate", 0.7, "open")]
    wall_run(sc, kit, ck, (985, 450), pal, wscale=0.95, gate_half=0.5 * 20 * ppm * 0.7 * 0.95)
    dirs2 = node_dirs(ck)
    for i, nd in enumerate(ck):
        x, y, kind = nd[:3]
        dx, dy = dirs2[i]
        if kind == "gate":
            sc.place(kit, "gate_open", x, y, orient(dx, dy, (x - 985, y - 450)), scale=0.7, pal=pal)
        else:
            sc.place(kit, "tower_sq_roof", x, y, rot_to(dx, dy), scale=0.58, pal=pal)
    alpha, bg, icc = lift_units(orig, thr=0.2, dark_d=0.04, dens_min=0.07)
    unitzone = hex_dilate(alpha > 0.5, 9)
    dwall = poly_dist(outer, (H, W), closed=True)
    dkeep = poly_dist(keep, (H, W), closed=True)
    keep_out = (dwall < 46) | (dkeep < 38) | keep_pm | (plaza > 0.2) | unitzone | ~inner_pm
    keep_out |= hex_dilate(box_blur((np.abs(orig[..., :3] - np.array([0.84, 0.64, 0.5])).max(-1) < 0.0).astype(np.float32), 1) > 0, 0)
    ch = [(860, 595)]
    for x, y in ch:
        keep_out[y - 50:y + 50, x - 36:x + 36] = True
    sites = []
    for gy in np.arange(228, 700, 40):
        for gx in np.arange(400, 1230, 40):
            x = gx + rng.uniform(-4, 4)
            y = gy + rng.uniform(-4, 4)
            if keep_out[int(y), int(x)] or rng.uniform() < 0.13:
                continue
            sites.append((x, y))
    kinds = ["house_gable_s", "house_hip_s", "house_gable_m", "house_hip_m", "house_gable_s"]
    for (x, y) in sites:
        k = kinds[int(rng.integers(0, len(kinds)))]
        ang = math.radians(90 * int(rng.integers(0, 2)) + rng.uniform(-3, 3))
        pj = PAL["spanish"] if rng.uniform() < 0.78 else PAL["adobe"]
        j = rng.uniform(0.9, 1.08)
        pj = {kk: tuple(np.clip(np.array(v) * j, 0, 1)) for kk, v in pj.items()}
        sc.place(kit, k, x, y, ang, pal=pj, scale=0.78)
    sc.place(kit, "church", 860, 598, math.pi / 2, pal=pal, scale=0.62)
    sc.place(kit, "well", 760, 380, 0, pal=pal)
    for (x, y, a) in [(700, 320, 0.0), (815, 318, 0.1), (700, 440, 0.0), (818, 440, 0.0)]:
        sc.place(kit, "stall", x, y, a, pal=PAL["spanish"], scale=0.9)
    for (x, y, k, a) in [(657, 592, "cart", 0.3), (1120, 360, "barrels", 0.4), (620, 300, "barrels", 0.0)]:
        sc.place(kit, k, x, y, a, pal=pal, scale=0.9)
    # pier (planks) over the water
    for (x0, y0, x1, y1) in [(776, 70, 803, 200), (741, 44, 793, 74)]:
        yy2, xx2 = np.mgrid[y0:y1, x0:x1]
        pl = 0.5 + 0.12 * np.sin(yy2 * 1.9) + 0.04 * np.sin(xx2 * 0.7)
        base = np.array([0.46, 0.33, 0.21], np.float32)
        sc.alb[y0:y1, x0:x1] = base * pl[..., None] * 1.2
        sc.hg[y0:y1, x0:x1] = 0.8
        sc.nrm[y0:y1, x0:x1] = (0, 0, 1)
        sc.bump[y0:y1, x0:x1] = 0.0
        sc.cov[y0:y1, x0:x1] = 1.0
    # sea cliffs and rocks
    sc.place(kit, "cliff_m", 55, 130, orient(110, 80, (-60, 80)), scale=0.7, pal=pal)
    sc.place(kit, "cliff_m", 1555, 205, orient(-70, 30, (30, 70)), scale=0.7, pal=pal)
    for (x, y, k) in [(1527, 540, "rock_a"), (273, 845, "rock_a"), (1020, 920, "rock_b"), (245, 705, "rock_a")]:
        sc.place(kit, k, x, y, float(rng.uniform(0, 6)), pal=pal, scale=0.55)
    # palms along the shore and scrub
    fieldz = hex_dilate(fsum > 0.05, 10) | (track > 0.05) | unitzone
    outzone = (~hex_dilate(inner_pm, 28)) & (water < 0.5) & (sl < 0.5) & (~fieldz)
    pier_rect = np.zeros((H, W), bool)
    pier_rect[30:215, 720:830] = True
    shorez = (shore > 0.2) & outzone & (gblur(water, 5) < 0.03) & ~pier_rect
    nz = smooth_noise(rng, W, H, ppm, 30, 2.0)
    for (x, y, s) in tree_sites(rng, (nz > -0.3).astype(np.float32) * shorez, 30, 12, 0.5, scale_rng=(0.9, 1.15)):
        sc.place(kit, ["tree_palm_a", "tree_palm_b"][int(rng.integers(0, 2))], x, y, float(rng.uniform(0, 6.28)), pal=pal, scale=0.95 * s)
    for (x, y, s) in tree_sites(rng, (nz > 0.45).astype(np.float32) * outzone, 40, 14, 0.5, scale_rng=(0.8, 1.2)):
        sc.place(kit, ["bush_a", "bush_b", "tree_broad_a"][int(rng.integers(0, 3))], x, y, float(rng.uniform(0, 6.28)), pal=pal, scale=0.5 * s)
    img, sh, ao = light_scene(sc, st)
    return orig, img, sh, ao, alpha, bg


def scene_close(shots, kit, g, st, sname):
    ppm = 10.0
    orig = load_png(os.path.join(shots, "ridge_cliffs_close.png"), 8)
    rng = np.random.default_rng(41)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    p0, p1 = np.array([435.0, 355.0]), np.array([940.0, 548.0])
    dvec = (p1 - p0) / np.linalg.norm(p1 - p0)
    nvec = np.array([dvec[1], -dvec[0]])       # towards the north-east (up-right in the image)
    sd = (xx - p0[0]) * nvec[0] + (yy - p0[1]) * nvec[1]
    Hm = 5.5 * smoothstep(-330, 320, sd) + 0.5 * smooth_noise(rng, W, H, ppm, 15, 2.2)
    sc = base_scene(orig, ppm, Hm, st, st["exag"] * 0.8)
    sl = slope_of(Hm, ppm)
    o = orig[..., :3]
    green = ((o[..., 1] > o[..., 0] + 0.06) & (o[..., 1] > o[..., 2] + 0.08)).astype(np.float32)
    dens = gblur(green, 16)
    patch = smoothstep(0.2, 0.9, smooth_noise(rng, W, H, ppm, 18, 2.2))
    weights = {"grass": 1 - 0.55 * patch, "dry": 0.55 * patch * smoothstep(0, 4, Hm), "dirt": 0.25 * smoothstep(0.5, 1.0, smooth_noise(rng, W, H, ppm, 9, 2.0))}
    splat(g, sc, weights, st)
    pal = PAL["roman"]
    L = np.linalg.norm(p1 - p0)
    ang = rot_to(*dvec)
    if not out_side(ang, (nvec[0], nvec[1])):
        ang += math.pi
    # note: cliff local +y is the high (plateau) side
    for t in (0.3, 0.72):
        c = p0 + (p1 - p0) * t
        sc.place(kit, "cliff_l", c[0], c[1], ang, sx=0.93 * L * 0.62 / (36 * ppm) * 1.0, pal=pal)
    sc.place(kit, "cliff_l", 1610, 905, ang, sx=1.1, pal=pal)
    sc.place(kit, "rock_a", 1300, 845, 1.0, pal=pal, scale=0.9)
    alpha, bg, icc = lift_units(orig, tan=False, thr=0.12)
    alpha[:, :62] = 1.0
    unitzone = hex_dilate(box_blur(icc.astype(np.float32), 40) > 0.001, 0)
    cliffz = poly_dist([tuple(p0 - dvec * 20), tuple(p1 + dvec * 20)], (H, W)) < 80
    for (x, y, s) in tree_sites(rng, (dens > 0.18).astype(np.float32), 38, 14, 0.5, avoid=cliffz | unitzone | (np.arange(W)[None, :] < 66), scale_rng=(0.8, 1.25)):
        k = ["tree_broad_a", "tree_broad_b", "tree_broad_c", "tree_broad_b"][int(rng.integers(0, 4))]
        sc.place(kit, k, x, y, float(rng.uniform(0, 6.28)), pal=pal, scale=0.62 * s, tint=ttint(rng))
    for i in range(45):
        x, y = rng.uniform(70, W), rng.uniform(40, 900)
        if not cliffz[int(y), int(x)] and dens[int(y), int(x)] < 0.18:
            sc.place(kit, ["bush_a", "bush_b"][i % 2], x, y, float(rng.uniform(0, 6)), pal=pal, scale=0.6)
    img, sh, ao = light_scene(sc, st)
    return orig, img, sh, ao, alpha, bg


def scene_valley(shots, kit, g, st, sname):
    ppm = 4.2
    orig = load_png(os.path.join(shots, "valley_forest_bands.png"), 8)
    rng = np.random.default_rng(51)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    Hm = 9 * smoothstep(120, 430, np.abs(yy - 430)) + 1.0 * smooth_noise(rng, W, H, ppm, 50, 2.2)
    sc = base_scene(orig, ppm, Hm, st, st["exag"])
    sl = slope_of(Hm, ppm)
    o = orig[..., :3]
    dens = smoothstep(0.55, 0.30, gblur(o[..., 1], 8)) * 1.0
    patch = smoothstep(0.15, 0.85, smooth_noise(rng, W, H, ppm, 40, 2.2))
    weights = {"grass": 1 - 0.5 * patch, "dry": 0.5 * patch, "dirt": 0.12 * smoothstep(0.5, 1.0, smooth_noise(rng, W, H, ppm, 12, 2.0))}
    splat(g, sc, weights, st)
    pal = PAL["roman"]
    sc.place(kit, "cliff_m", 1053, 346, rot_to(1, -0.07) + 0.0, sx=0.9, pal=pal, scale=0.9)
    sc.place(kit, "cliff_m", 1305, 358, rot_to(1, -0.19), sx=0.9, pal=pal, scale=0.9)
    alpha, bg, icc = lift_units(orig, tan=False, radius=70, thr=0.07, dark_d=0.015, dens_min=0.05)
    unitzone = hex_dilate(alpha > 0.5, 6) | hex_dilate(box_blur(icc.astype(np.float32), 40) > 0.0004, 0)
    cl = (poly_dist([(960, 352), (1145, 335)], (H, W)) < 14) | (poly_dist([(1215, 378), (1395, 340)], (H, W)) < 14)
    sites = tree_sites(rng, dens, 13, 6, 0.30, avoid=unitzone | cl, scale_rng=(0.8, 1.25))
    # sparse trees outside the forest
    sparse = tree_sites(rng, (dens < 0.30).astype(np.float32) * 0.0 + (smooth_noise(rng, W, H, ppm, 25, 2.0) > 0.9), 60, 20, 0.5, avoid=unitzone | cl)
    for (x, y, s) in sites + sparse:
        k = ["tree_broad_a", "tree_broad_b", "tree_broad_c", "tree_broad_b", "tree_broad_a"][int(rng.integers(0, 5))]
        sc.place(kit, k, x, y, float(rng.uniform(0, 6.28)), pal=pal, scale=0.40 * s, tint=ttint(rng))
    for (x, y) in [(762, 366), (143, 407), (245, 395)]:
        sc.place(kit, "rock_a", x, y, 1.0, pal=pal, scale=0.45)
    img, sh, ao = light_scene(sc, st)
    return orig, img, sh, ao, alpha, bg


def run_scene(name, style_name, shots, frames, out):
    frames12 = frames + "12"
    st = STYLE[style_name]
    kit = Kit(frames12 if name == "close" else frames)
    g = Ground()
    fn = {"hill": scene_hill}.get(name)
    if name == "coast":
        fn = scene_coast
    elif name == "close":
        fn = scene_close
    elif name == "valley":
        fn = scene_valley
    orig, img, sh, ao, alpha, bg = fn(shots, kit, g, st, style_name)
    os.makedirs(out, exist_ok=True)
    fin = finish(orig, img, alpha, bg, os.path.join(out, "%s_%s.png" % (name, style_name)))
    save_png(os.path.join(out, "%s_%s_shadow.png" % (name, style_name)), np.repeat((1 - sh * 0.8)[..., None], 3, -1))
    return fin


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "scene":
        for sname in arg("--style", "A,B").split(","):
            run_scene(sys.argv[2], sname, arg("--shots"), arg("--frames"), arg("--out"))
            print("done", sys.argv[2], sname)
    elif cmd == "board":
        for s in ("A", "B"):
            if arg("--set") == "landmarks":
                board(arg("--frames"), arg("--out"), s, float(arg("--ppm", "6")), GROUPS_NEW, "landmarks_")
            else:
                board(arg("--frames"), arg("--out"), s)
    elif cmd == "cultures":
        for s in ("A", "B"):
            cultures(arg("--frames"), arg("--out"), s)
    elif cmd == "ground":
        for s in ("A", "B"):
            ground_sheet(arg("--out"), s)
            splat_demo(arg("--out"), s)
    elif cmd == "iso":
        for s in ("A", "B"):
            iso_board(arg("--frames"), arg("--out"), s)


