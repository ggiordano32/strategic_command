"""Battle kit compositor library (style mockup): numpy only, ImageMagick for
PNG in / out. Loads the G-buffer pieces made by build.py, rotates / scales
them into a scene G-buffer (albedo, normal, height), and lights the scene:
Lambert from the north-west, cast shadow (height-field ray march, a separate
soft long pass), ambient occlusion from the height field, rim / outline
finish, recolour from the mask pass. Also procedural tiling ground textures.
"""
import json
import math
import os
import subprocess
import numpy as np

# ------------------------------------------------------------------ png io


def load_png(path, depth=8):
    w, h = map(int, subprocess.check_output(["identify", "-format", "%w %h", path + "[0]"]).split())
    raw = subprocess.check_output(["convert", path + "[0]", "-depth", str(depth), "-endian", "MSB", "-alpha", "on", "rgba:-"])
    if depth == 16:
        a = np.frombuffer(raw, ">u2").reshape(h, w, 4).astype(np.float32) / 65535.0
    else:
        a = np.frombuffer(raw, np.uint8).reshape(h, w, 4).astype(np.float32) / 255.0
    return a


def save_png(path, arr):
    a = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, c = a.shape
    subprocess.run(["convert", "-size", "%dx%d" % (w, h), "-depth", "8", ("rgba" if c == 4 else "rgb") + ":-", path],
                   input=a.tobytes(), check=True)


# ------------------------------------------------------------------ filters


def box_blur(a, r):
    """separable box blur radius r (pixels), edge replicated; a is 2D or 3D."""
    r = int(max(0, r))
    if r == 0:
        return a
    out = a
    for ax in (0, 1):
        pad = [(0, 0)] * out.ndim
        pad[ax] = (r + 1, r)
        p = np.pad(out, pad, mode="edge")
        c = np.cumsum(p, axis=ax, dtype=np.float64)
        n = 2 * r + 1
        sl_hi = [slice(None)] * out.ndim
        sl_lo = [slice(None)] * out.ndim
        sl_hi[ax] = slice(n, n + out.shape[ax])
        sl_lo[ax] = slice(0, out.shape[ax])
        out = ((c[tuple(sl_hi)] - c[tuple(sl_lo)]) / n).astype(np.float32)
    return out


def gblur(a, r):
    """cheap gaussian-ish: three box passes."""
    r = max(1, int(r))
    k = max(1, int(round(r * 0.58)))
    for _ in range(3):
        a = box_blur(a, k)
    return a


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ noise / textures


def pnoise(n, beta, rng, angle=0.0, stretch=1.0):
    """tileable noise, 1/f^beta, optionally stretched along `angle` (degrees)."""
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    t = math.radians(angle)
    fu = fx * math.cos(t) + fy * math.sin(t)
    fv = -fx * math.sin(t) + fy * math.cos(t)
    fr = np.sqrt((fu * stretch) ** 2 + fv ** 2)
    fr[0, 0] = 1.0
    amp = fr ** (-beta)
    amp[0, 0] = 0.0
    sp = np.fft.fft2(rng.normal(size=(n, n))) * amp
    z = np.real(np.fft.ifft2(sp))
    z -= z.mean()
    return (z / (z.std() + 1e-9)).astype(np.float32)


def lerp3(c0, c1, t):
    c0 = np.array(c0, np.float32)
    c1 = np.array(c1, np.float32)
    return c0 + (c1 - c0) * t[..., None]


TEXN = 512
TEXM = 96.0     # metres per tile


def make_ground(seed=3):
    """returns {name: (albedo (n,n,3), bump metres (n,n))}"""
    rng = np.random.default_rng(seed)
    n = TEXN
    out = {}
    uu = (np.arange(n) / n)[None, :].repeat(n, 0)
    vv = (np.arange(n) / n)[:, None].repeat(n, 1)

    def grassy(name, dark, light, strokes=0.07, ang=65, tuft=0.1, patches=0.2):
        lo = pnoise(n, 2.6, rng)
        mid = pnoise(n, 1.7, rng)
        st = np.tanh(1.2 * pnoise(n, 1.0, rng, ang, 7.0))
        st2 = np.tanh(1.2 * pnoise(n, 1.0, rng, ang + 80, 5.0))
        t = np.clip(0.5 + patches * lo + 0.07 * mid, 0, 1)
        c = lerp3(dark, light, t)
        c *= (1 + strokes * st - 0.6 * strokes * st2)[..., None]
        tf = pnoise(n, 0.3, rng)
        c *= np.where(tf > 1.9, 1 - tuft, np.where(tf < -2.0, 1 + tuft * 0.7, 1.0))[..., None]
        out[name] = (c.astype(np.float32), (0.05 * mid + 0.04 * st).astype(np.float32))

    grassy("grass", (0.33, 0.43, 0.20), (0.45, 0.55, 0.27), strokes=0.045, tuft=0.07)
    grassy("dry", (0.55, 0.50, 0.29), (0.69, 0.63, 0.38), strokes=0.05, ang=20, patches=0.22, tuft=0.07)
    # dirt: pebbles + dust patches
    lo = pnoise(n, 2.4, rng)
    mid = pnoise(n, 1.4, rng)
    c = lerp3((0.42, 0.33, 0.23), (0.55, 0.45, 0.32), np.clip(0.5 + 0.2 * lo + 0.08 * mid, 0, 1))
    peb = np.zeros((n, n), np.float32)
    for _ in range(1100):
        x, y = rng.integers(0, n, 2)
        r = rng.uniform(0.7, 1.9)
        k = int(r * 2) + 2
        ys = np.arange(-k, k + 1)
        g = np.exp(-(ys[:, None] ** 2 + ys[None, :] ** 2) / (r * r))
        yy = (y + ys) % n
        xx = (x + ys) % n
        peb[np.ix_(yy, xx)] = np.maximum(peb[np.ix_(yy, xx)], g * rng.uniform(0.4, 1.0))
    c = c * (1 + 0.22 * peb[..., None]) * (1 - 0.0 * peb[..., None])
    out["dirt"] = (c.astype(np.float32), (0.15 * peb + 0.05 * mid).astype(np.float32))
    # rock ground: strata + cracks
    lo = pnoise(n, 2.2, rng)
    wp = pnoise(n, 2.0, rng)
    band = np.sin(2 * np.pi * (5 * vv + 0.9 * wp + 0.3 * lo))
    rid = 1.0 - np.abs(pnoise(n, 1.6, rng))
    crack = smoothstep(0.84, 0.99, rid) * 0.6
    c = lerp3((0.46, 0.42, 0.37), (0.64, 0.59, 0.51), np.clip(0.5 + 0.18 * lo + 0.1 * band, 0, 1))
    c *= (1 - 0.45 * crack)[..., None]
    out["rock"] = (c.astype(np.float32), (0.25 * band * 0.3 - 0.4 * crack + 0.1 * lo).astype(np.float32))
    # sand: ripples
    wp = pnoise(n, 2.0, rng)
    rip = np.sin(2 * np.pi * (16 * (0.8 * uu + 0.6 * vv) + 1.4 * wp))
    lo = pnoise(n, 2.4, rng)
    c = lerp3((0.70, 0.62, 0.43), (0.82, 0.75, 0.55), np.clip(0.5 + 0.18 * lo + 0.08 * rip, 0, 1))
    c *= (1 + 0.03 * pnoise(n, 0.2, rng))[..., None]
    out["sand"] = (c.astype(np.float32), (0.05 * rip).astype(np.float32))
    # ploughed field: furrows along x
    wp = pnoise(n, 2.6, rng)
    fur = np.sin(2 * np.pi * (48 * vv + 0.35 * wp))
    clod = pnoise(n, 0.6, rng)
    c = lerp3((0.30, 0.21, 0.14), (0.47, 0.34, 0.22), np.clip(0.5 + 0.38 * fur + 0.07 * clod, 0, 1))
    out["plough"] = (c.astype(np.float32), (0.22 * fur + 0.04 * clod).astype(np.float32))
    # crop rows (green) and stubble / wheat (gold)
    for name, c0, c1 in (("crop", (0.28, 0.42, 0.14), (0.45, 0.60, 0.22)), ("wheat", (0.62, 0.52, 0.26), (0.80, 0.69, 0.36))):
        wp = pnoise(n, 2.6, rng)
        fur = np.sin(2 * np.pi * (96 * vv + 0.3 * wp))
        lo = pnoise(n, 2.2, rng)
        c = lerp3(c0, c1, np.clip(0.5 + 0.15 * lo + 0.3 * fur, 0, 1))
        c *= (1 + 0.05 * pnoise(n, 0.4, rng))[..., None]
        out[name] = (c.astype(np.float32), (0.08 * fur).astype(np.float32))
    return out


def sample_tex(tex, X, Y, idx=None):
    """tileable bilinear sample; X, Y in tile units (tile = 1.0); arrays of any shape"""
    n = tex.shape[0]
    u = X * n - 0.5
    v = Y * n - 0.5
    x0 = np.floor(u).astype(np.int64)
    y0 = np.floor(v).astype(np.int64)
    fx = (u - x0)[..., None].astype(np.float32)
    fy = (v - y0)[..., None].astype(np.float32)
    x0 %= n
    y0 %= n
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    return (tex[y0, x0] * (1 - fx) * (1 - fy) + tex[y0, x1] * fx * (1 - fy) +
            tex[y1, x0] * (1 - fx) * fy + tex[y1, x1] * fx * fy)


# ------------------------------------------------------------------ geometry helpers


def poly_mask(pts, shape):
    H, W = shape
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1 = max(0, int(min(xs))), min(W, int(max(xs)) + 2)
    y0, y1 = max(0, int(min(ys))), min(H, int(max(ys)) + 2)
    m = np.zeros(shape, bool)
    if x1 <= x0 or y1 <= y0:
        return m
    yy, xx = np.mgrid[y0:y1, x0:x1]
    inside = np.zeros(yy.shape, bool)
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        if ay == by:
            continue
        cond = ((ay <= yy) & (yy < by)) | ((by <= yy) & (yy < ay))
        xi = ax + (yy - ay) * (bx - ax) / (by - ay)
        inside ^= cond & (xx < xi)
    m[y0:y1, x0:x1] = inside
    return m


def poly_dist(pts, shape, closed=False):
    """distance in px to a polyline."""
    H, W = shape
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.full(shape, 1e9, np.float32)
    segs = list(zip(pts[:-1], pts[1:])) + ([(pts[-1], pts[0])] if closed else [])
    for (ax, ay), (bx, by) in segs:
        vx, vy = bx - ax, by - ay
        L2 = vx * vx + vy * vy + 1e-9
        t = np.clip(((xx - ax) * vx + (yy - ay) * vy) / L2, 0, 1)
        d = np.minimum(d, np.hypot(xx - (ax + t * vx), yy - (ay + t * vy)))
    return d


def spline(pts, n=14):
    """Catmull-Rom through pts."""
    out = []
    P = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t +
                                    (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in (0, 1)))
    out.append(tuple(pts[-1]))
    return out


# ------------------------------------------------------------------ pieces


class Kit:
    def __init__(self, frames):
        self.dir = frames
        self.cache = {}
        self.raw = {}

    def raw_piece(self, name):
        if name in self.raw:
            return self.raw[name]
        base = os.path.join(self.dir, name)
        meta = json.load(open(base + ".json"))
        alb = load_png(base + "_albedo.png", 8)
        nrm = load_png(base + "_normal.png", 8)
        hgt = load_png(base + "_height.png", 16)
        msk = load_png(base + "_mask.png", 8)
        self.raw[name] = (meta, alb, nrm, hgt, msk)
        return self.raw[name]

    def piece(self, name, pal):
        """premultiplied stack (N,N,8): albedo3, alpha, normal3 (-1..1), height m; recoloured."""
        key = (name, tuple(sorted((k, tuple(v)) for k, v in pal.items())))
        if key in self.cache:
            return self.cache[key]
        meta, alb, nrm, hgt, msk = self.raw_piece(name)
        a = alb[..., 3:4]
        c = alb[..., :3]
        m = msk[..., :3] * (msk[..., 3:4] > 0.5)
        tint = (m[..., 0:1] * np.array(pal["R"], np.float32) + m[..., 1:2] * np.array(pal["G"], np.float32) +
                m[..., 2:3] * np.array(pal["B"], np.float32)) / 0.85 + (1 - np.clip(m.sum(-1, keepdims=True), 0, 1))
        c = np.clip(c * tint, 0, 1)
        n = nrm[..., :3] * 2 - 1
        n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-6
        h = (hgt[..., 0:1] * meta["zmax"])
        st = np.concatenate([c * a, a, n * a, h * a], -1).astype(np.float32)
        N = meta["px"]
        yy, xx = np.nonzero(a[..., 0] > 0.02)
        meta = dict(meta)
        meta["rad"] = float(np.hypot(xx - N / 2, yy - N / 2).max()) + 2 if len(xx) else 4.0
        self.cache[key] = (meta, st)
        return self.cache[key]


class Scene:
    def __init__(self, W, H, ppm):
        self.W, self.H, self.ppm = W, H, ppm
        self.alb = np.zeros((H, W, 3), np.float32)
        self.nrm = np.zeros((H, W, 3), np.float32)
        self.nrm[..., 2] = 1
        self.hg = np.zeros((H, W), np.float32)
        self.terrain = np.zeros((H, W), np.float32)
        self.cov = np.zeros((H, W), np.float32)
        self.bump = np.zeros((H, W), np.float32)
        self.gloss = np.zeros((H, W), np.float32)

    def place(self, kit, name, cx, cy, rot=0.0, sx=1.0, sy=1.0, pal=None, scale=1.0, zb=None, ss=2, tint=None):
        """cx, cy in px (image), rot radians counter-clockwise on screen."""
        meta, st = kit.piece(name, pal)
        N = meta["px"]
        k = meta["ppm"] / (self.ppm * scale)          # source px per scene px
        half = meta["rad"] / k * max(sx, sy) + 2
        x0, x1 = max(0, int(cx - half)), min(self.W, int(cx + half) + 1)
        y0, y1 = max(0, int(cy - half)), min(self.H, int(cy + half) + 1)
        if x1 <= x0 or y1 <= y0:
            return
        if zb is None:
            zb = float(self.terrain[min(self.H - 1, max(0, int(cy))), min(self.W - 1, max(0, int(cx)))])
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        c, s = math.cos(rot), math.sin(rot)
        acc = np.zeros((y1 - y0, x1 - x0, 8), np.float32)
        offs = [(0.5, 0.5)] if ss == 1 else [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
        for ox, oy in offs:
            X = xx + ox - cx
            Y = -(yy + oy - cy)
            lx = (X * c + Y * s) / sx
            ly = (-X * s + Y * c) / sy
            u = N / 2 + lx * k - 0.5
            v = N / 2 - ly * k - 0.5
            inb = (u >= 0) & (u < N - 1) & (v >= 0) & (v < N - 1)
            u = np.clip(u, 0, N - 1.001)
            v = np.clip(v, 0, N - 1.001)
            ix = u.astype(np.int32)
            iy = v.astype(np.int32)
            fx = (u - ix)[..., None]
            fy = (v - iy)[..., None]
            val = (st[iy, ix] * (1 - fx) * (1 - fy) + st[iy, ix + 1] * fx * (1 - fy) +
                   st[iy + 1, ix] * (1 - fx) * fy + st[iy + 1, ix + 1] * fx * fy)
            acc += val * inb[..., None]
        acc /= len(offs)
        a = acc[..., 3]
        sel = a > 1e-3
        if not sel.any():
            return
        inv = 1.0 / np.maximum(a, 1e-4)
        alb = acc[..., 0:3] * inv[..., None]
        if tint is not None:
            alb = np.clip(alb * np.array(tint, np.float32), 0, 1)
        nl = acc[..., 4:7] * inv[..., None]
        hh = acc[..., 7] * inv + zb
        # rotate normal xy into the scene frame (world, y up)
        nx = nl[..., 0] * c * 1.0 - nl[..., 1] * s
        ny = nl[..., 0] * s + nl[..., 1] * c
        nn = np.stack([nx, ny, nl[..., 2]], -1)
        nn /= np.linalg.norm(nn, axis=-1, keepdims=True) + 1e-6
        sub_h = self.hg[y0:y1, x0:x1]
        win = a * smoothstep(-0.25, 0.1, hh - sub_h)
        w = win[..., None]
        self.alb[y0:y1, x0:x1] = self.alb[y0:y1, x0:x1] * (1 - w) + alb * w
        self.nrm[y0:y1, x0:x1] = self.nrm[y0:y1, x0:x1] * (1 - w) + nn * w
        self.hg[y0:y1, x0:x1] = sub_h * (1 - win) + hh * win
        self.cov[y0:y1, x0:x1] = np.maximum(self.cov[y0:y1, x0:x1], win)
        self.bump[y0:y1, x0:x1] *= (1 - win)


# ------------------------------------------------------------------ lighting

LIGHT = np.array([-0.55, 0.50, 0.67], np.float32)


def terrain_normals(Hm, ppm, exag):
    gy, gx = np.gradient(Hm)         # per pixel, rows down
    gx = gx * ppm
    gy = gy * ppm
    gx = gx * 1.0
    n = np.stack([-gx * exag / ppm * ppm, gy * exag, np.ones_like(Hm)], -1)   # world y up: dH/dy_up = -gy
    n[..., 0] = -(np.gradient(Hm, axis=1) * ppm) * exag
    n[..., 1] = (np.gradient(Hm, axis=0) * ppm) * exag
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n.astype(np.float32)


def bump_normals(nrm, bump, ppm, k=1.0):
    gx = np.gradient(bump, axis=1) * ppm * k
    gy = np.gradient(bump, axis=0) * ppm * k
    n = nrm.copy()
    n[..., 0] -= gx
    n[..., 1] += gy
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n


def cast_shadow(hg, ppm, elev_deg=34.0, azim_to_light=(-0.74, -0.67), maxlen_m=34.0, soft=(0.35, 0.22)):
    """soft long shadow from the height field: 0 lit .. 1 shadow. Light azimuth is
    given in image coordinates (towards the light, y down)."""
    H, W = hg.shape
    t = math.tan(math.radians(elev_deg))
    dx, dy = azim_to_light
    nrm = math.hypot(dx, dy)
    dx, dy = dx / nrm, dy / nrm
    maxd = int(maxlen_m * ppm)
    pad = maxd + 2
    hp = np.pad(hg, pad, mode="edge")
    out = np.zeros_like(hg)
    d = 1.0
    while d <= maxd:
        sx = int(round(dx * d))
        sy = int(round(dy * d))
        hs = hp[pad + sy:pad + sy + H, pad + sx:pad + sx + W]
        dm = d / ppm
        e = hs - (hg + dm * t)
        out = np.maximum(out, np.clip(e / (soft[0] + soft[1] * dm * t * 3), 0, 1))
        d += 1.0 if d < 24 else 1.8
    return gblur(out, 1)


def ambient_occ(hg, ppm):
    a1 = np.clip((gblur(hg, int(1.6 * ppm)) - hg) / 3.0, 0, 1)
    a2 = np.clip((gblur(hg, int(5.0 * ppm)) - hg) / 7.0, 0, 1)
    return np.clip(0.62 * a1 + 0.4 * a2, 0, 1)


def light_scene(sc, style):
    """style: dict of look parameters. Returns (final rgb, shadow layer, ao layer)."""
    nrm = bump_normals(sc.nrm, sc.bump, sc.ppm, style.get("bump", 1.0))
    a, b = style["amb"], style["key"]
    Ln = LIGHT / np.linalg.norm(LIGHT)
    diff = np.clip(nrm @ Ln, 0, 1)
    hemi = 0.5 + 0.5 * nrm[..., 2]
    lf = (a * (0.7 + 0.3 * hemi) + b * diff) / (a + b * Ln[2])
    col = sc.alb * lf[..., None]
    hs = sc.hg - 0.8 * sc.terrain
    sh = cast_shadow(hs, sc.ppm, style["sh_elev"], maxlen_m=style.get("sh_len", 34.0))
    tint = np.array(style["sh_tint"], np.float32)
    col = col * (1 - sh[..., None] * style["sh_str"] * (1 - tint))
    ao = ambient_occ(hs, sc.ppm)
    col = col * (1 - style["ao"] * ao[..., None] * (1 - 0.1 * tint))
    # rim: convex edges catch the light (dry-brush), only on pieces
    pc = np.clip(sc.cov * 1.0, 0, 1)
    rim = np.clip((hs - gblur(hs, 2)) * 1.4, 0, 1) * pc
    col = col + style["rim"] * rim[..., None] * np.array([1.0, 0.95, 0.8], np.float32)
    # outline where the piece ends against the ground
    er = pc.copy()
    for _ in range(max(1, int(style["ol_w"]))):
        p = np.pad(er, 1, mode="edge")
        er = np.minimum.reduce([p[1:-1, 1:-1], p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]])
    edge = np.clip(pc - er, 0, 1)
    col = col * (1 - style["ol"] * edge[..., None])
    # glossy glint (diorama)
    if style.get("spec", 0) > 0:
        hv = Ln + np.array([0, 0, 1], np.float32)
        hv /= np.linalg.norm(hv)
        sp = np.clip(nrm @ hv, 0, 1) ** 24 * pc * (1 - sh)
        col = col + style["spec"] * sp[..., None]
    # grade
    lum = (col * np.array([0.3, 0.59, 0.11], np.float32)).sum(-1, keepdims=True)
    col = lum + (col - lum) * style["sat"]
    col = (col - 0.5) * style.get("contrast", 1.0) + 0.5 + style.get("lift", 0.0)
    return np.clip(col, 0, 1), sh, ao
