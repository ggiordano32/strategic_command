#!/usr/bin/env python3
"""EXPERIMENT: Hunyuan3D-2's own paint model on the committed character meshes.

Two stages, nothing is written to assets/:

  gen   (venv python, GPU)   mesh.glb + front crop -> painted mesh (xatlas UVs) + raw texture
      ~/.venvs/hunyuan/bin/python tools/hunyuan/hy_paint.py gen NAME --work W --out O [--variant turbo|full] [--offload]
  render (Blender, CPU)      quantise to the palette, render bust + mini for three variants
      blender -b --factory-startup -P tools/hunyuan/hy_paint.py -- render NAME --work W --out O

Needs the texgen CUDA extensions (custom_rasterizer, mesh_processor) built in the venv, with an
nvcc >= 12.8 (gcc 14 host) from a user-level CUDA redist tree (CUDA_HOME), see the experiment notes.
Licence: Tencent Hunyuan non-commercial licence, as for the shape model.
"""
import os
import sys
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


# ================================================================== stage 1: paint (venv python)
def gen(a):
    import numpy as np
    import torch
    import trimesh
    from PIL import Image
    from hy3dgen.texgen import Hunyuan3DPaintPipeline

    name = a["name"]
    d = os.path.join(a["out"], name)
    os.makedirs(d, exist_ok=True)
    m = trimesh.load(os.path.join(REPO, "assets", "characters", name, "mesh.glb"), force="mesh", process=False)
    mesh = trimesh.Trimesh(np.asarray(m.vertices), np.asarray(m.faces), process=False)
    mesh.merge_vertices()
    print("mesh", len(mesh.vertices), "verts", len(mesh.faces), "faces, extents", mesh.extents)
    img = Image.open(os.path.join(a["work"], name, "front.png")).convert("RGBA")
    sub = "hunyuan3d-paint-v2-0-turbo" if a["variant"] == "turbo" else "hunyuan3d-paint-v2-0"
    torch.cuda.reset_peak_memory_stats()
    t0 = time.time()
    if a["offload"]:
        # both pipelines do .to('cuda') in their constructors, which does not fit 8 GB next to the desktop:
        # load them on the CPU, then let accelerate move one sub-model at a time
        from diffusers import DiffusionPipeline
        orig_to = DiffusionPipeline.to
        DiffusionPipeline.to = lambda self, *args, **kw: self
        try:
            pipe = Hunyuan3DPaintPipeline.from_pretrained("tencent/Hunyuan3D-2", subfolder=sub)
        finally:
            DiffusionPipeline.to = orig_to
        pipe.enable_model_cpu_offload()
    else:
        pipe = Hunyuan3DPaintPipeline.from_pretrained("tencent/Hunyuan3D-2", subfolder=sub)
    t1 = time.time()
    out = pipe(mesh, image=img)
    t2 = time.time()
    print("[%s] %s load %.1fs paint %.1fs peak VRAM %.2f GiB" % (
        name, sub, t1 - t0, t2 - t1, torch.cuda.max_memory_allocated() / 2 ** 30))
    tex = np.asarray(out.visual.material.image.convert("RGB"))
    Image.fromarray(tex).save(os.path.join(d, "hy_raw.png"))
    v = np.asarray(out.vertices, np.float64)
    v_bl = np.stack([v[:, 0], -v[:, 2], v[:, 1]], 1)          # glTF Y-up -> Blender Z-up
    np.savez(os.path.join(d, "hy_mesh.npz"), v=v_bl, f=np.asarray(out.faces, np.int32),
             uv=np.asarray(out.visual.uv, np.float64))
    open(os.path.join(d, "hy_stats.txt"), "w").write(
        "%s load %.1fs paint %.1fs peak VRAM %.2f GiB\n" % (sub, t1 - t0, t2 - t1, torch.cuda.max_memory_allocated() / 2 ** 30))


def load_lib():
    """paint_render.py's helpers (main() not run) and texture.py, for the Blender stages."""
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, here)
    import texture
    src = open(os.path.join(here, "paint_render.py")).read()
    k = src.rindex("\nmain()")
    ns = {"__file__": os.path.join(here, "paint_render.py"), "__name__": "paint_render_lib"}
    exec(compile(src[:k], ns["__file__"], "exec"), ns)
    return ns, texture


# ================================================================== stage 2: quantise + render (Blender)
def render(a):
    import numpy as np
    import bpy                                                # noqa: F401  (Blender python only)
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, here)
    import texture
    src = open(os.path.join(here, "paint_render.py")).read()
    k = src.rindex("\nmain()")
    ns = {"__file__": os.path.join(here, "paint_render.py"), "__name__": "paint_render_lib"}
    exec(compile(src[:k], ns["__file__"], "exec"), ns)        # helpers only: main() is not run
    name = a["name"]
    cfg = ns["CHARS"][name]
    names = list(cfg["palette"].keys())
    hex_rgb, rgb_to_lab = ns["hex_rgb"], ns["rgb_to_lab"]
    pal_rgb = np.array([hex_rgb(cfg["palette"][n][0]) for n in names])
    d = os.path.join(a["out"], name)
    os.makedirs(d, exist_ok=True)
    os.environ.setdefault("SC_DBG", "nogloss,nobev")
    lib = ns["load_structures"]()
    imgs = {}

    def make(tag, v, tri, uvc, albedo, labels):
        ap = os.path.join(d, "albedo_%s.png" % tag)
        mp = os.path.join(d, "mask_%s.png" % tag)
        ns["write_vup"](ap, albedo)
        ns["write_vup"](mp, ns["mask_image"](labels, names, cfg))
        rig = ns["Rig"](lib, cfg, v, tri, uvc, labels, ap, mp, cfg["height_m"], names)
        out = {}
        out["mini"] = render_mini(rig, os.path.join(d, "mini_%s.png" % tag))
        out["bust"] = render_bust(rig, os.path.join(d, "bust_%s.png" % tag))
        return out

    def render_mini(rig, path):
        from mathutils import Vector
        import math
        v = rig.v
        tilt = 52.0
        t = math.radians(tilt)
        ys = v[:, 1] * math.cos(t) + v[:, 2] * math.sin(t)
        hpx = 96
        ppm = hpx / (ys.max() - ys.min() + 0.2)
        pad_m = 0.35
        rx = int(math.ceil(((v[:, 0].max() - v[:, 0].min()) + 2 * pad_m) * ppm))
        ry = int(math.ceil(((ys.max() - ys.min()) + 2 * pad_m) * ppm))
        rig.pose(0)
        cen = Vector(((v[:, 0].max() + v[:, 0].min()) / 2, 0, 0))
        ymid = (ys.max() + ys.min()) / 2
        rig.camera(tilt, Vector((cen.x, ymid * math.cos(t), ymid * math.sin(t))), max(rx, ry) / ppm, rx, ry)
        rig.outline(max(0.9, 1.2 * max(0.55, hpx * 2 / 256.0)) / ppm)
        for o in list(bpy.data.objects):
            if o.type == "LIGHT":
                bpy.data.objects.remove(o)
        rig.lights()
        rig.render(path)
        return path

    def render_bust(rig, path):
        from mathutils import Vector
        import math
        v, lab2 = rig.v, rig.lab
        lib["HEIGHT"]["D"] = None
        rig.materials("bust")
        sk = (lab2 == names.index("skin")) & (v[:, 2] > 0.75 * cfg["height_m"])
        skin_top = np.percentile(v[sk, 2], 99.0)
        above, win = cfg["bust"]
        win = win * 1.3
        zt = skin_top + above
        zb = zt - win
        yaw = math.radians(-32)
        zsel = (v[:, 2] > zb) & (v[:, 2] < zt)
        xr = v[zsel, 0] * math.cos(yaw) - v[zsel, 1] * math.sin(yaw)
        yr = v[zsel, 0] * math.sin(yaw) + v[zsel, 1] * math.cos(yaw)
        xm = (np.percentile(xr, 0.5) + np.percentile(xr, 99.5)) / 2
        ym = yr.mean()
        zc = (zt + zb) / 2
        span = max(win * 1.08, (np.percentile(xr, 99.5) - np.percentile(xr, 0.5)) * 1.06)
        rig.pose(-32)
        t = math.radians(80.0)
        rig.camera(80.0, Vector((xm, 0, 0)), span, 256, 256)
        rig.outline(1.3 / (256 / span))
        for o in list(bpy.data.objects):
            if o.type == "LIGHT":
                bpy.data.objects.remove(o)
        rig.lights()
        rig.pose(-32)
        view = Vector((0, math.sin(t), -math.cos(t)))
        rig.sc.camera.location = Vector((xm, ym, zc)) - view * 150.0
        rig.render(path)
        lib["HEIGHT"]["D"] = (1.2, 0.80, 1.0)
        rig.materials("D2")
        return path

    # ---- column 1: the committed projection-bake mesh, re-rendered here (nothing written to assets/)
    ob = ns["import_glb"](os.path.join(REPO, "assets", "characters", name, "mesh.glb"))
    me = ob.data
    me.calc_loop_triangles()
    img = [nd.image for mat in me.materials for nd in mat.node_tree.nodes if nd.type == "TEX_IMAGE"][-1]
    img.colorspace_settings.name = "Non-Color"
    w_, h_ = img.size
    alb0 = np.array(img.pixels[:], np.float32).reshape(h_, w_, 4)[..., :3].astype(np.float64)
    v0, tri0, _, _ = ns["mesh_arrays"](me)
    uv0 = ns["uv_corners"](me)
    lab0 = rgb_to_lab(alb0.reshape(-1, 3))
    dd = ((lab0[:, None, :] - rgb_to_lab(pal_rgb)[None]) ** 2).sum(-1)
    labels0 = dd.argmin(1).reshape(h_, w_)
    wl = os.path.join(a["work"], name, "labels.png")
    if os.path.exists(wl):
        labels0 = np.rint(ns["read_vup"](wl)[..., 0] * 255).astype(np.int32)
    imgs["bake"] = make("bake", v0, tri0, uv0, alb0, labels0)

    # ---- columns 2, 3: Hunyuan paint, raw and quantised
    z = np.load(os.path.join(d, "hy_mesh.npz"))
    v, f, uv = z["v"], z["f"], z["uv"]
    raw_vup = ns["read_vup"](os.path.join(d, "hy_raw.png"))[..., :3].astype(np.float64)
    T = raw_vup.shape[0]
    uvc = uv[f].reshape(-1, 2)                                  # per-corner, triangle order
    uvc3 = uv[f]                                                # (n,3,2)
    print("  hy mesh: %d verts %d tris, texture %d" % (len(v), len(f), T))
    labels, alb_q = quantise(a, name, cfg, names, pal_rgb, texture, ns, v, f, uvc3, raw_vup, T)
    imgs["raw"] = make("raw", v, f, uvc3, raw_vup, labels)
    imgs["quant"] = make("quant", v, f, uvc3, alb_q, labels)
    import json
    json.dump(imgs, open(os.path.join(d, 'renders.json'), 'w'))


def quantise(a, name, cfg, names, pal_rgb, texture, ns, v, f, uvc3, raw, T):
    """Snap the painted texture to the palette like texture.bake: nearest anchor in Lab with the ZBAND
    priors, head / hat zone restrictions, majority + small-component clean-up, flat colour per label,
    detail layer on skin and hair only, ink for the dark features of the skin."""
    import numpy as np
    rgb_to_lab, hex_rgb = ns["rgb_to_lab"], ns["hex_rgb"]
    ANCH, ZB = ns["ANCHORS"][name], ns["ZBAND"][name]
    anc = [(i, hx) for i, n in enumerate(names) for hx in ([ANCH[n]] if isinstance(ANCH[n], str) else ANCH[n])]
    owner = np.array([i for i, _ in anc])
    pal_lab = rgb_to_lab(np.array([hex_rgb(hx) for _, hx in anc]))
    bands = {names.index(k): b for k, b in ZB.items() if k in names}
    ncol = len(names)
    zmin, zmax = v[:, 2].min(), v[:, 2].max()
    H = zmax - zmin
    # per texel height fraction by rasterising the UV layout (texture.rasterize: v-up, as the bake does)
    valid, pos, _nr, _tid = texture.rasterize(uvc3, v[f], np.zeros_like(v[f]), T, None)
    zf_img = np.where(valid, (pos[..., 2] - zmin) / H, 0.0)
    idx = np.nonzero(valid.reshape(-1))[0]
    zf = zf_img.reshape(-1)[idx]
    col = raw.reshape(-1, 3)[idx]
    # light blur of the colour like the sheet's 3 px blur
    blur = texture.box_mean(raw, 1).reshape(-1, 3)[idx]
    head_ids = [names.index(n) for n in cfg["head_labels"] if n in names]
    alias = {names.index(a_): names.index(b_) for a_, b_ in cfg.get("head_alias", {}).items() if a_ in names and b_ in names}
    lab = texture.classify(blur, pal_lab, owner, ncol, rgb_to_lab, zf, bands)
    face_z = cfg.get("face_z", 0.87)
    face = zf >= face_z
    own2 = np.array([alias.get(o, o) for o in owner])
    if face.any():
        lab[face] = texture.classify_restricted(blur[face], pal_lab, own2, ncol, rgb_to_lab, sorted(head_ids), zf[face], bands)
    if cfg.get("hat_lock"):
        zone = zf >= cfg.get("hat_z", 2.0)
        zids = [names.index(n) for n in cfg.get("hat_zone", []) if n in names]
        if zone.any() and zids:
            lab[zone] = texture.classify_restricted(blur[zone], pal_lab, owner, ncol, rgb_to_lab, sorted(zids), zf[zone], bands)
    lab_img = np.zeros(T * T, np.int32)
    lab_img[idx] = lab
    lab_img = lab_img.reshape(T, T)
    lab_img = texture.majority(lab_img, valid, ncol, 2)
    # the UV islands of the paint model are tiny and many: scale the small-blob thresholds to its texel density
    thr = np.where(zf_img >= 0.82, 80, 120)
    thr = np.where(zf_img >= cfg.get("hat_z", 2.0), 400, thr) if cfg.get("hat_lock") else thr
    for _ in range(2):
        lab_img, _r = texture.remove_small(lab_img, valid, thr, ncol)
    lab_img = texture.majority(lab_img, valid, ncol, 1, r=2)
    lab = lab_img.reshape(-1)[idx]
    # detail layer: luma against the local mean of the same label (skin, hair only)
    L = texture.luma(raw)
    det_ids = [names.index(n) for n in ("skin", "hair") if n in names]
    det = np.zeros((T, T))
    for l in det_ids:
        m = (lab_img == l) & valid
        w = texture.box_mean(m.astype(np.float64), 12)
        mean = texture.box_mean(np.where(m, L, 0.0), 12) / np.maximum(w, 1e-6)
        det = np.where(m, (L - mean) / np.maximum(mean, 0.30), det)
    det_raw = det.reshape(-1)[idx]
    use = np.isin(lab, det_ids)
    det_c = np.clip(np.where(use, det_raw, 0.0), texture.DETAIL_LO, texture.DETAIL_HI)
    base = ns["srgb_to_lin"](pal_rgb[lab]) * (1 + det_c)[:, None]
    out_col = ns["lin_to_srgb"](np.clip(base, 0, 1))
    skin_m = (lab == names.index("skin")) if "skin" in names else np.zeros(len(lab), bool)
    Lf = L.reshape(-1)[idx]
    ink = np.zeros(len(lab), bool)
    if skin_m.any():
        med = np.median(Lf[skin_m])
        ink = skin_m & (det_raw < texture.INK_FROM) & (Lf < texture.INK_LUMA * med)
        ink &= zf >= head_z                         # ink is a face rule: the body's skin keeps the flat colour + detail
    ii = np.zeros(T * T, bool)
    ii[idx] = ink
    ii = ii.reshape(T, T)
    cc = texture.components(ii.astype(np.int32), ii)
    cf = cc.ravel()
    sizes = np.bincount(cf[cf >= 0], minlength=T * T)
    keep = (cf >= 0) & (sizes[np.maximum(cf, 0)] >= 6)
    ink = keep.reshape(T, T).ravel()[idx]
    out_col = np.where(ink[:, None], texture.INK, out_col)
    print("  quantised: labels %s, ink texels %d" % (
        {names[i]: int((lab == i).sum()) for i in range(ncol)}, int(ink.sum())))
    out = np.zeros((T * T, 3))
    out[idx] = out_col
    out = out.reshape(T, T, 3)
    out, _c = texture.dilate_into(out, valid, 8)
    lab_d = texture.dilate_labels(lab_img, valid, 8)
    return lab_d, out


def compare(a):
    """[projection bake | raw Hunyuan paint | quantised Hunyuan paint], each bust + mini, 2x."""
    import json
    from PIL import Image
    name = a["name"]
    imgs = json.load(open(os.path.join(a["out"], name, "renders.json")))
    cols = []
    for tag in ("bake", "raw", "quant"):
        bust = Image.open(imgs[tag]["bust"]).convert("RGBA")
        mini = Image.open(imgs[tag]["mini"]).convert("RGBA")
        bust = bust.resize((bust.width * 2, bust.height * 2), Image.NEAREST)
        mini = mini.resize((mini.width * 2, mini.height * 2), Image.NEAREST)
        W = max(bust.width, mini.width)
        c = Image.new("RGBA", (W, bust.height + mini.height + 8), (140, 158, 128, 255))
        c.alpha_composite(bust, ((W - bust.width) // 2, 0))
        c.alpha_composite(mini, ((W - mini.width) // 2, bust.height + 8))
        cols.append(c)
    Wt = sum(c.width for c in cols) + 8 * (len(cols) - 1)
    Ht = max(c.height for c in cols)
    out = Image.new("RGBA", (Wt, Ht), (140, 158, 128, 255))
    x = 0
    for c in cols:
        out.alpha_composite(c, (x, 0))
        x += c.width + 8
    p = os.path.join(a["out"], "compare_%s.png" % name)
    out.convert("RGB").save(p)
    print("compare:", p)


# ================================================================== stage 3: bake into our own atlas (Blender)
# rule switches for this route (paint_render.CHARS has the sheet bake's): the paint's face has soft lips
# and red cloth next to the mouth, so the mouth rule is on for the captain too
BAKE_RULES = {"captain": {"mouth_fix": True, "mouth_max": 300}, "mercy": {"mouth_max": 600}}
# height priors added to paint_render.ZBAND: the paint model lights Rook's green jacket to a grey that
# the neutral metal anchor would take; metal (the pistol, the blade's fittings) lives at the hip and below
BAKE_BANDS = {"rook": {"metal": (0.0, 0.60)}, "mercy": {"brass": (0.0, 0.62)}}


def lab_to_lch(lab):
    import numpy as np
    return lab[..., 0], np.hypot(lab[..., 1], lab[..., 2]), np.arctan2(lab[..., 2], lab[..., 1])


def kmeans(x, k, w=None, iters=40, seed=7):
    """Plain k-means (k-means++ start, seeded) on (n,3) points."""
    import numpy as np
    rng = np.random.RandomState(seed)
    n = len(x)
    c = [x[rng.randint(n)]]
    d2 = ((x - c[0]) ** 2).sum(1)
    for _ in range(1, k):
        c.append(x[rng.choice(n, p=d2 / d2.sum())])
        d2 = np.minimum(d2, ((x - c[-1]) ** 2).sum(1))
    c = np.array(c)
    for _ in range(iters):
        d = ((x[:, None, :] - c[None]) ** 2).sum(2)
        a = d.argmin(1)
        nc = np.array([x[a == j].mean(0) if (a == j).any() else c[j] for j in range(k)])
        if np.allclose(nc, c, atol=1e-3):
            c = nc
            break
        c = nc
    d = ((x[:, None, :] - c[None]) ** 2).sum(2)
    return c, d.argmin(1)


def apply_lift(lab, lift):
    """Affine lift of L and chroma (hue kept): L' = aL*L + bL, C' = max(0, aC*C + bC)."""
    import numpy as np
    aL, bL, aC, bC = lift[:4]
    L, C, h = lab_to_lch(lab)
    L2 = np.clip(aL * L + bL, 0, 100)
    C2 = np.maximum(0.0, aC * C + bC)
    if len(lift) > 4:                                   # hue-dependent chroma gain, 36 bins of 10 degrees
        g = lift[4]
        x = (np.degrees(h) % 360.0) / 10.0
        i0 = np.floor(x).astype(int) % 36
        f = x - np.floor(x)
        C2 = C2 * (g[i0] * (1 - f) + g[(i0 + 1) % 36] * f)
    return np.stack([L2, C2 * np.cos(h), C2 * np.sin(h)], -1)


def classify_lab(lab, pal_lab, owner, ncol, zf, bands, allowed=None):
    """texture.classify / classify_restricted on Lab input (lightness counted 0.6)."""
    import numpy as np
    dd = np.full((len(lab), ncol), 1e9)
    for j, o in enumerate(owner):
        if allowed is not None and o not in allowed:
            continue
        dl = (lab[:, 0] - pal_lab[j, 0]) * 0.6
        dist = dl * dl + (lab[:, 1] - pal_lab[j, 1]) ** 2 + (lab[:, 2] - pal_lab[j, 2]) ** 2
        dd[:, o] = np.minimum(dd[:, o], dist)
    for i, (lo, hi) in (bands or {}).items():
        dd[(zf < lo) | (zf > hi), i] += 1e5
    return dd.argmin(1)


def reproject(a, ns, texture, name):
    """The raw paint resampled into the committed mesh's 1024 chart layout.  Returns a dict of arrays."""
    import numpy as np
    from mathutils import kdtree
    d = os.path.join(a["out"], name)
    ob = ns["import_glb"](os.path.join(REPO, "assets", "characters", name, "mesh.glb"))
    me = ob.data
    me.calc_loop_triangles()
    v0, tri0, _, _ = ns["mesh_arrays"](me)
    uv0 = ns["uv_corners"](me)
    img = [nd.image for mat in me.materials for nd in mat.node_tree.nodes if nd.type == "TEX_IMAGE"][-1]
    img.colorspace_settings.name = "Non-Color"
    w_, h_ = img.size
    alb0 = np.array(img.pixels[:], np.float32).reshape(h_, w_, 4)[..., :3].astype(np.float64)
    T = w_
    z = np.load(os.path.join(d, "hy_mesh.npz"))
    hv, hf, huv = z["v"], z["f"], z["uv"]
    raw = ns["read_vup"](os.path.join(d, "hy_raw.png"))[..., :3].astype(np.float64)
    Tr = raw.shape[0]
    H = v0[:, 2].max() - v0[:, 2].min()
    if len(hf) == len(tri0):
        # same triangle count: the committed mesh is the painted mesh in the same order (also after silfit.py moved its
        # vertices), so triangle i is triangle i.  The corner order of the paint model's faces is found through the
        # unfitted positions silfit.py stored (fitted -> original), else the corners are taken as they are.
        match = np.arange(len(tri0))
        tp = v0[tri0]
        mpath = a.get("map") or next((q for q in (os.path.join(a["work"], name, "silfit_map.npz"),
                                                   os.path.join(d, "silfit_map.npz")) if os.path.exists(q)), None)
        hpos = hv[hf]                                              # (ntri,3,3) the paint model's corners
        perm = np.tile(np.arange(3), (len(tri0), 1))
        if mpath:
            mp = np.load(mpath)
            fp = mp["fitted"]
            kt = kdtree.KDTree(len(fp))
            for i, p in enumerate(fp):
                kt.insert(p, i)
            kt.balance()
            q = [kt.find(p) for p in tp.reshape(-1, 3)]
            ik = np.array([t[1] for t in q])
            dk = np.array([t[2] for t in q])
            orig = mp["orig"][ik].reshape(-1, 3, 3)
            print("  silfit map: fitted -> original corner distance max %.2g (figure %.3g)" % (dk.max(), H))
            dd3 = np.linalg.norm(orig[:, :, None, :] - hpos[:, None, :, :], axis=3)      # (ntri, mesh corner, hy corner)
            perm = dd3.argmin(2)
            cdist = dd3.min(2).max(1)
            ok_perm = np.array([len(set(r)) == 3 for r in perm])
            print("  triangle match by index: %d / %d, corner distance to the unfitted mesh max %.2g, corner permutation not one-to-one %d" % (
                len(tri0), len(hf), cdist.max(), int((~ok_perm).sum())))
            dist = np.where(ok_perm, cdist, 1e9)
        else:
            dist = np.linalg.norm(tp.mean(1) - hpos.mean(1), axis=1)
            print("  triangle match by index (no silfit map): centroid distance median %.2g max %.2g (figure %.3g)" % (
                np.median(dist), dist.max(), H))
        tuv = huv[hf][np.arange(len(tri0))[:, None], perm]          # uv of the paint model's corner matching each mesh corner
    else:
        # triangle match by centroid (same frame: the paint pipeline keeps the mesh's coordinates)
        c0 = v0[tri0].mean(1)
        c1 = hv[hf].mean(1)
        kd = kdtree.KDTree(len(c1))
        for i, p in enumerate(c1):
            kd.insert(p, i)
        kd.balance()
        match = np.empty(len(c0), np.int64)
        dist = np.empty(len(c0))
        for i, p in enumerate(c0):
            _co, j, dd_ = kd.find(p)
            match[i], dist[i] = j, dd_
        print("  triangle match: %d / %d, centroid distance median %.2g max %.2g (figure %.3g), one-to-one %d" % (
            len(c0), len(c1), np.median(dist), dist.max(), H, len(np.unique(match))))
        tp = hv[hf[match]]
        tuv = huv[hf[match]]
    good_tri = dist < 2e-3 * H
    valid, pos, _nr, tid = texture.rasterize(uv0, v0[tri0], np.zeros_like(v0[tri0]), T, None)
    idx = np.nonzero(valid.reshape(-1))[0]
    P = pos.reshape(-1, 3)[idx]
    ti = tid.reshape(-1)[idx]
    mj = match[ti]
    A, B, C = tp[mj, 0], tp[mj, 1], tp[mj, 2]
    e0, e1, e2 = B - A, C - A, P - A
    d00, d01, d11 = (e0 * e0).sum(1), (e0 * e1).sum(1), (e1 * e1).sum(1)
    d20, d21 = (e2 * e0).sum(1), (e2 * e1).sum(1)
    den = np.maximum(d00 * d11 - d01 * d01, 1e-18)
    l1 = (d11 * d20 - d01 * d21) / den
    l2 = (d00 * d21 - d01 * d20) / den
    l0 = 1 - l1 - l2
    bc = np.clip(np.stack([l0, l1, l2], 1), 0, None)
    bc /= np.maximum(bc.sum(1, keepdims=True), 1e-9)
    uv = bc[:, 0:1] * tuv[mj, 0] + bc[:, 1:2] * tuv[mj, 1] + bc[:, 2:3] * tuv[mj, 2]
    col = texture.bilinear(raw, uv[:, 0] * Tr - 0.5, uv[:, 1] * Tr - 0.5)
    cov = good_tri[ti]
    print("  reprojected %d texels (%d of the layout's valid), uncovered (no triangle match) %d" % (
        len(idx), int(valid.sum()), int((~cov).sum())))
    return dict(T=T, valid=valid, idx=idx, pos=P, col=col, cov=cov, alb0=alb0, v0=v0)


def bake(a):
    import numpy as np
    ns, texture = load_lib()
    name = a["name"]
    cfg = dict(ns["CHARS"][name])
    cfg.update(BAKE_RULES.get(name, {}))
    names = list(cfg["palette"].keys())
    rgb_to_lab, hex_rgb = ns["rgb_to_lab"], ns["hex_rgb"]
    t0 = time.time()
    r = reproject(a, ns, texture, name)
    T, valid, idx, col, cov, P = r["T"], r["valid"], r["idx"], r["col"], r["cov"], r["pos"]
    v0 = r["v0"]
    zmin, H = v0[:, 2].min(), v0[:, 2].max() - v0[:, 2].min()
    zf = (P[:, 2] - zmin) / H
    lab = rgb_to_lab(col)
    print("  [%.1fs] reprojection done" % (time.time() - t0))
    rp = np.zeros((T * T, 3))
    rp[idx] = col
    rp, _m = texture.dilate_into(rp.reshape(T, T, 3), valid, 8)
    ns["write_vup"](os.path.join(a["out"], name, "albedo_reproj.png"), rp)
    rng = np.random.RandomState(3)
    sel = rng.choice(len(lab), min(len(lab), 120000), replace=False)
    cen, _ = kmeans(lab[sel], a.get("k", 11))
    asg = ((lab[:, None, :] - cen[None]) ** 2).sum(2).argmin(1)
    share = np.bincount(asg, minlength=len(cen)) / len(asg)
    zmean = np.array([zf[asg == j].mean() if (asg == j).any() else 0.5 for j in range(len(cen))])
    # ---- anchors and priors
    ANCH, ZB = ns["ANCHORS"][name], dict(ns["ZBAND"][name], **BAKE_BANDS.get(name, {}))
    anc = [(i, hx) for i, n in enumerate(names) for hx in ([ANCH[n]] if isinstance(ANCH[n], str) else ANCH[n])]
    owner = np.array([i for i, _ in anc])
    pal_lab = rgb_to_lab(np.array([hex_rgb(hx) for _, hx in anc]))
    bands = {names.index(k_): b for k_, b in ZB.items() if k_ in names}
    ncol = len(names)
    aL_, aC_, ah_ = lab_to_lch(pal_lab)
    cL, cC, ch = lab_to_lch(cen)
    lift = a_lift = (1.0, 0.0, 1.5, 0.0)

    def band_ok(label, z):
        lo, hi = bands.get(label, (0.0, 1.01))
        return lo <= z <= hi

    for it in range(8):
        lc = apply_lift(cen, lift)
        lL, lC, lh = lab_to_lch(lc)
        match = []
        for j in range(len(cen)):
            best, bj = 1e9, -1
            for q in range(len(anc)):
                if not band_ok(owner[q], zmean[j]):
                    continue
                wh = min(1.0, min(lC[j], aC_[q]) / 20.0)
                dh = abs((np.degrees(lh[j] - ah_[q]) + 180) % 360 - 180) / 25.0
                cost = wh * dh * dh * 2 + ((lL[j] - aL_[q]) / 25.0) ** 2 + ((lC[j] - aC_[q]) / 20.0) ** 2
                if cost < best:
                    best, bj = cost, q
            match.append(bj)
        match = np.array(match)
        w = np.sqrt(share)
        rel = (cC >= 12) | (cL >= 30)                     # dark, grey clusters match the anchors ambiguously: no vote
        if rel.sum() < 3:
            rel[:] = True
        keep = rel.copy()
        for _pass in range(2):                           # trimmed fit: pairs off by > 12 L are outliers
            X = np.stack([cL, np.ones(len(cL))], 1) * (w * keep)[:, None]
            (aL, bL), *_ = np.linalg.lstsq(X, aL_[match] * w * keep, rcond=None)
            keep = np.abs(aL_[match] - (aL * cL + bL)) < 12
            keep &= rel
            if keep.sum() < 3:
                keep = rel.copy()
        ch_m = (cC > 4) & (aC_[match] > 8) & rel
        if ch_m.sum() >= 2:                              # chroma: a slope only (the offset is a hue gain's job)
            aC = (w[ch_m] * cC[ch_m] * aC_[match][ch_m]).sum() / (w[ch_m] * cC[ch_m] ** 2).sum()
        else:
            aC = lift[2]
        bC = 0.0
        new = (float(np.clip(aL, 0.9, 3.0)), float(np.clip(bL, -6, 8)), float(np.clip(aC, 1.0, 1.3)), float(np.clip(bC, -3, 8)))
        # residual chroma per hue: the red cloth is far paler than the sheet, the skin is not, so the
        # remaining chroma ratio of the matched chromatic clusters is smoothed over hue (sigma 18 deg)
        pre = apply_lift(cen, new)
        _l, pC, _h = lab_to_lch(pre)
        okc = (pC > 6) & (aC_[match] > 8) & rel
        rho = np.clip(aC_[match] / np.maximum(pC, 1e-6), 0.7, 2.2)
        hb = np.arange(36) * 10.0
        gain = np.ones(36)
        for bi in range(36):
            dh = np.abs((hb[bi] - np.degrees(ch) + 180) % 360 - 180)
            wg = np.where(okc, np.sqrt(share) * np.exp(-(dh / 18.0) ** 2), 0.0)
            gain[bi] = (wg * rho).sum() + 0.03 * 1.0
            gain[bi] /= wg.sum() + 0.03
        new = new + (gain,)
        if it > 0 and np.allclose(new[:4], lift[:4], atol=1e-4) and np.allclose(gain, lift[4], atol=1e-3):
            lift = new
            break
        lift = new
    print("  fitted lift: L' = %.3f L %+.2f ; C' = %.3f C %+.2f, then hue gain (hue kept)" % lift[:4])
    print("  chroma gain by hue (deg: gain): " + " ".join("%d:%.2f" % (hb[i], lift[4][i]) for i in range(0, 36, 3)))
    lc = apply_lift(cen, lift)
    lL, lC, lh = lab_to_lch(lc)
    print("  k-means clusters: share, mean height, raw L/C/h -> lifted L/C -> matched anchor (label hex)")
    for j in np.argsort(-share):
        q = match[j]
        print("   %2d %5.1f%%  z %.2f  raw L %5.1f C %5.1f h %6.1f -> L %5.1f C %5.1f  => %-9s %s" % (
            j, 100 * share[j], zmean[j], cL[j], cC[j], np.degrees(ch[j]), lL[j], lC[j], names[owner[q]], anc[q][1]))

    # ---- classification, before / after the lift, with the texture.bake rules
    lab_l = apply_lift(lab, lift)
    uncov = ~cov
    res = {}
    for tag, lb in (("before", lab), ("after", lab_l)):
        res[tag] = postprocess(a, ns, texture, cfg, names, name, r, lb, zf, cov, pal_lab, owner, bands, col, tag == "after")
        lab_img = res[tag][1]
        print("  label shares %-6s: %s" % (tag, ", ".join(
            "%s %.1f%%" % (names[i], 100.0 * (lab_img[valid] == i).mean()) for i in range(ncol))))
    bake_lab_p = os.path.join(a["work"], name, "labels.png")
    if os.path.exists(bake_lab_p):
        bl = np.rint(ns["read_vup"](bake_lab_p)[..., 0] * 255).astype(np.int32)
        print("  label shares bake  : %s" % ", ".join("%s %.1f%%" % (names[i], 100.0 * (bl[valid] == i).mean()) for i in range(ncol)))
    albedo, lab_img = res["after"]
    # ---- write: new work files, the glb and (for the renders) paint_render --only mini,bust,turn
    wd = os.path.join(a["out"], "work", name)
    os.makedirs(wd, exist_ok=True)
    ap = os.path.join(wd, "albedo.png")
    ns["write_vup"](ap, albedo)
    ns["write_vup"](os.path.join(wd, "labels.png"), np.stack([lab_img / 255.0] * 3, -1))
    ns["write_vup"](os.path.join(wd, "maskmap.png"), ns["mask_image"](lab_img, names, cfg))
    print("  total %.1fs (assets untouched: they are written by `hybrid --assets`)" % (time.time() - t0))


def bpy_objects():
    import bpy
    return list(bpy.data.objects)


def postprocess(a, ns, texture, cfg, names, name, r, lab, zf, cov, pal_lab, owner, bands, rawcol, final):
    """texture.bake's label rules on the reprojected Lab colours.  Returns (albedo, label image)."""
    import numpy as np
    T, valid, idx = r["T"], r["valid"], r["idx"]
    hex_rgb = ns["hex_rgb"]
    pal_rgb = np.array([hex_rgb(cfg["palette"][n][0]) for n in names])
    ncol = len(names)
    n = len(idx)
    head_ids = [names.index(x) for x in cfg["head_labels"] if x in names]
    alias = {names.index(a_): names.index(b_) for a_, b_ in cfg.get("head_alias", {}).items() if a_ in names and b_ in names}
    # light masked blur of the Lab colours (the sheet bake blurs 3 px)
    img = np.zeros((T * T, 3))
    img[idx] = lab
    img = img.reshape(T, T, 3)
    wv = valid.astype(np.float64)
    blur = (texture.box_mean(img * wv[..., None], 2) / np.maximum(texture.box_mean(wv, 2), 1e-6)[..., None]).reshape(-1, 3)[idx]
    head_z = cfg.get("head_z", 0.82)
    L0 = cfg.get("face_z", 0.87)
    lock = cfg.get("hat_lock", False)
    hat_z = cfg.get("hat_z", 2.0) if lock else 2.0
    lb = classify_lab(blur, pal_lab, owner, ncol, zf, bands)
    face = zf >= L0
    own2 = np.array([alias.get(o, o) for o in owner])
    if face.any():
        lb[face] = classify_lab(blur[face], pal_lab, own2, ncol, zf[face], bands, set(head_ids))
    zone = zf >= hat_z
    zone_ids = [names.index(x) for x in cfg.get("hat_zone", []) if x in names] if lock else []
    if zone.any() and zone_ids:
        lb[zone] = classify_lab(blur[zone], pal_lab, owner, ncol, zf[zone], bands, set(zone_ids))
    lab_img = np.zeros(T * T, np.int32)
    lab_img[idx] = lb
    lab_img = lab_img.reshape(T, T)
    lab_img = texture.majority(lab_img, valid, ncol, 2)
    zf_img = np.zeros(T * T)
    zf_img[idx] = zf
    zf_img = zf_img.reshape(T, T)
    thr = np.where(zf_img >= head_z, 80, 120)
    thr = np.where(zf_img >= hat_z, 400, thr)
    removed = 0
    for _ in range(2):
        lab_img, rr = texture.remove_small(lab_img, valid, thr, ncol)
        removed += rr
    lab_img = texture.majority(lab_img, valid, ncol, 1, r=2)
    nm = list(names)
    L_img = np.zeros(T * T)
    L_img[idx] = texture.luma(rawcol)
    L_img = L_img.reshape(T, T)
    col_img = np.zeros((T * T, 3))
    col_img[idx] = blur
    col_img = col_img.reshape(T, T, 3)
    force_ink = np.zeros((T, T), bool)
    st = {}
    hat_ids = [names.index(x) for x in cfg.get("hat_labels", []) if x in names] if lock else []
    if hat_ids and zone.any():
        keep_set = list(set(hat_ids) | set(zone_ids))
        m = np.isin(lab_img, keep_set) & valid
        ids = texture.components(m.astype(np.int32), m)
        f = ids.ravel()
        touch = np.zeros(T * T, bool)
        touch[np.unique(f[((zf_img >= hat_z) & m).ravel()])] = True
        stray = m & ~touch[np.maximum(ids, 0)] & np.isin(lab_img, hat_ids)
        if stray.any():
            tgt = [nm.index(x) for x in ("skin", "hair") if x in nm]
            ys, xs = np.nonzero(stray)
            lab_img[ys, xs] = classify_lab(col_img[ys, xs], pal_lab, owner, ncol, zf_img[ys, xs], bands, set(tgt))
        st["hat_stray"] = int(stray.sum())
    if "skin" in nm and cfg.get("mouth_fix"):
        cl = [nm.index(x) for x in ("coat", "sash") if x in nm]
        face_m = (zf_img >= head_z) & (zf_img < hat_z) & valid
        sk = face_m & (lab_img == nm.index("skin"))
        sk_med = np.median(L_img[sk]) if sk.any() else 1.0
        m = np.isin(lab_img, cl) & face_m
        ids = texture.components(np.where(m, lab_img, -1).astype(np.int32), m)
        f = ids.ravel()
        sz = np.bincount(f[f >= 0], minlength=T * T)
        small = m & (sz[np.maximum(ids, 0)] < cfg.get("mouth_max", 150))
        lab_img[small] = nm.index("skin")
        force_ink |= small & (sz[np.maximum(ids, 0)] < 150) & (L_img < sk_med)
        st["mouth"] = int(small.sum())
    if cfg.get("skin_prune") and "skin" in nm and "coat" in nm:
        m = (lab_img == nm.index("skin")) & valid
        ids = texture.components(m.astype(np.int32), m)
        f = ids.ravel()
        good = np.zeros(T * T, bool)
        good[np.unique(f[(m & ((zf_img >= 0.80) | (zf_img < 0.55))).ravel()])] = True
        bad = m & ~good[np.maximum(ids, 0)]
        lab_img[bad] = nm.index("coat")
        st["skin_pruned"] = int(bad.sum())
    # uncovered texels keep the bake's label (and colour)
    if (~cov).any():
        bl = os.path.join(a["work"], name, "labels.png")
        if os.path.exists(bl):
            b_lab = np.rint(ns["read_vup"](bl)[..., 0] * 255).astype(np.int32)
            uc = np.zeros(T * T, bool)
            uc[idx[~cov]] = True
            lab_img = np.where(uc.reshape(T, T), b_lab, lab_img)
    if not final:
        return None, lab_img
    # colour: flat palette, detail layer (luma against the local mean of the label) on skin and hair, ink on skin
    lab_f = lab_img.reshape(-1)[idx]
    Lr = L_img
    det_ids = [names.index(x) for x in ("skin", "hair") if x in names]
    det = np.zeros((T, T))
    for l in det_ids:
        m = (lab_img == l) & valid
        w_ = texture.box_mean(m.astype(np.float64), 12)
        mean = texture.box_mean(np.where(m, Lr, 0.0), 12) / np.maximum(w_, 1e-6)
        det = np.where(m, (Lr - mean) / np.maximum(mean, 0.30), det)
    det_raw = det.reshape(-1)[idx]
    use = np.isin(lab_f, det_ids)
    det_c = np.clip(np.where(use, det_raw, 0.0), texture.DETAIL_LO, texture.DETAIL_HI)
    base = ns["srgb_to_lin"](pal_rgb[lab_f]) * (1 + det_c)[:, None]
    out_col = ns["lin_to_srgb"](np.clip(base, 0, 1))
    skin_m = (lab_f == names.index("skin")) if "skin" in names else np.zeros(n, bool)
    Lf = Lr.reshape(-1)[idx]
    ink = np.zeros(n, bool)
    if skin_m.any():
        med = np.median(Lf[skin_m])
        ink = skin_m & (det_raw < texture.INK_FROM) & (Lf < texture.INK_LUMA * med)
        ink &= zf >= head_z                         # ink is a face rule: the body's skin keeps the flat colour + detail
    ii = np.zeros(T * T, bool)
    ii[idx] = ink
    ii = ii.reshape(T, T)
    cc = texture.components(ii.astype(np.int32), ii)
    cf = cc.ravel()
    sizes = np.bincount(cf[cf >= 0], minlength=T * T)
    ink = ((cf >= 0) & (sizes[np.maximum(cf, 0)] >= 6)).reshape(T, T).ravel()[idx]
    ink = ink | force_ink.reshape(-1)[idx]
    out_col = np.where(ink[:, None], texture.INK, out_col)
    out_col = np.where(cov[:, None], out_col, r["alb0"].reshape(-1, 3)[idx])
    print("  rules: removed %d components, ink texels %d, hat strays %d, mouth specks %d, skin pruned %d" % (
        removed, int(ink.sum()), st.get("hat_stray", 0), st.get("mouth", 0), st.get("skin_pruned", 0)))
    out = np.zeros((T * T, 3))
    out[idx] = out_col
    out = out.reshape(T, T, 3)
    out, _c = texture.dilate_into(out, valid, 8)
    return out, texture.dilate_labels(lab_img, valid, 8)


# ================================================================== stage 4: hybrid (Blender)
HEAD_LABELS = ("skin", "hair", "hat", "headscarf", "sash")


def render_set(a, tag, name, albedo, labels, only, real=False):
    """Export mesh.glb with `albedo` (committed UVs) and run paint_render's own main on it, with its asset
    paths redirected into OUT/tag (nothing is written to assets/)."""
    import numpy as np
    here = os.path.dirname(os.path.abspath(__file__))
    ns, texture = load_lib()
    d = os.path.join(a["out"], name, tag)
    wd = os.path.join(a["out"], "work_" + tag)
    os.makedirs(os.path.join(wd, name), exist_ok=True)
    os.makedirs(d, exist_ok=True)
    ap = os.path.join(wd, name, "albedo.png")
    ns["write_vup"](ap, albedo)
    ns["write_vup"](os.path.join(wd, name, "labels.png"), np.stack([labels / 255.0] * 3, -1))
    ob = ns["import_glb"](os.path.join(REPO, "assets", "characters", name, "mesh.glb"))
    mesh_path = os.path.join(d, "mesh.glb")
    if real:
        mesh_path = os.path.join(REPO, "assets", "characters", name, "mesh.glb")
    ns["export_mesh"](ob, ap, mesh_path)
    src = open(os.path.join(here, "paint_render.py")).read()
    for old, new_ in () if real else (('os.path.join(REPO, "assets", "characters", name, "mesh.glb")', repr(mesh_path)),
                      ('os.path.join(REPO, "assets", "minis", "characters")', repr(os.path.join(d, "minis"))),
                      ('os.path.join(REPO, "assets", "portraits", name + ".png")', repr(os.path.join(d, name + "_bust.png")))):
        assert old in src, old
        src = src.replace(old, new_)
    saved = sys.argv
    sys.argv = ["x", "--", name, "--work", wd, "--preview", d, "--only", only]
    try:
        exec(compile(src, os.path.join(here, "paint_render.py"), "exec"), {"__file__": os.path.join(here, "paint_render.py"), "__name__": "paint_render_run"})
    finally:
        sys.argv = saved
    return mesh_path


def hybrid(a):
    import numpy as np
    ns, texture = load_lib()
    name = a["name"]
    cfg = ns["CHARS"][name]
    names = list(cfg["palette"].keys())
    ob = ns["import_glb"](os.path.join(REPO, "assets", "characters", name, "mesh.glb"))
    me = ob.data
    me.calc_loop_triangles()
    v0, tri0, _, _ = ns["mesh_arrays"](me)
    uv0 = ns["uv_corners"](me)
    T = 1024
    valid, pos, _nr, _tid = texture.rasterize(uv0, v0[tri0], np.zeros_like(v0[tri0]), T, None)
    zmin, H = v0[:, 2].min(), v0[:, 2].max() - v0[:, 2].min()
    zf = np.where(valid, (pos[..., 2] - zmin) / H, 0.0)
    b_alb = ns["read_vup"](os.path.join(a["work"], name, "albedo.png"))[..., :3].astype(np.float64)
    b_lab = np.rint(ns["read_vup"](os.path.join(a["work"], name, "labels.png"))[..., 0] * 255).astype(np.int32)
    hyd = a.get("hy") or os.path.join(a["out"], "..", "hypaint")
    h_alb = ns["read_vup"](os.path.join(hyd, "work", name, "albedo.png"))[..., :3].astype(np.float64)
    h_lab = np.rint(ns["read_vup"](os.path.join(hyd, "work", name, "labels.png"))[..., 0] * 255).astype(np.int32)
    # the face runs below paint_render face_z (0.87: eyes and nose above, mouth and chin below), so the cut is the
    # head chart split (0.82), the collar
    face_z = cfg.get("head_z", 0.82)
    allowed = [names.index(n) for n in HEAD_LABELS if n in names]
    if a.get("hat") == "hypaint":      # the hat / plume / trim of the paint route, the face and hair of the bake
        allowed = [i for i in allowed if names[i] in ("skin", "hair")]
    sel = valid & (zf > face_z) & np.isin(b_lab, allowed)
    w = sel.astype(np.float64)
    vw = valid.astype(np.float64)
    wb = texture.box_mean(w * vw, 3) / np.maximum(texture.box_mean(vw, 3), 1e-6)
    wb = np.where(sel, np.maximum(wb, 0.5), wb)                  # inside the head selection never fades below half
    wb = np.where(valid, wb, 0.0)
    alb = wb[..., None] * b_alb + (1 - wb[..., None]) * h_alb
    lab = np.where(sel, b_lab, h_lab)
    alb, _m = texture.dilate_into(alb, valid, 8)
    lab = texture.dilate_labels(lab, valid, 8)
    print("  [%s] head texels from the bake: %d of %d (%.1f%%), hat = %s" % (
        name, int(sel.sum()), int(valid.sum()), 100.0 * sel.sum() / valid.sum(), a.get("hat", "bake")))
    tag = "hybrid"
    if a.get("hat") == "hypaint":
        tag = "hybrid_hh"
    out = a["out"]
    sets = [(tag, alb, lab, "mini,bust,turn")]
    if not a.get("skip_hy"):
        sets.insert(0, ("hypaint", h_alb, h_lab, "mini,bust"))
    for t, al, lb, only in sets:
        render_set(a, t, name, al, lb, only, real=bool(a.get("assets")) and t.startswith("hybrid"))
    import bpy  # noqa: F401


def hybrid_compare(a):
    from PIL import Image
    name = a["name"]
    S = os.path.dirname(a["out"].rstrip("/"))
    cols = []
    srcs = [(os.path.join(S, "bake_final", "portraits", name + ".png"), os.path.join(S, "bake_final", "minis", name + ".png"))]
    for t in a.get("tags", ["hypaint", "hybrid"]):
        d = os.path.join(a["out"], name, t)
        if t == "assets":
            srcs.append((os.path.join(REPO, "assets", "portraits", name + ".png"), os.path.join(REPO, "assets", "minis", "characters", name + ".png")))
        else:
            srcs.append((os.path.join(d, name + "_bust.png"), os.path.join(d, "minis", name + ".png")))
    for bp, mp in srcs:
        bust = Image.open(bp).convert("RGBA")
        mini = Image.open(mp).convert("RGBA")
        bust = bust.resize((bust.width * 2, bust.height * 2), Image.NEAREST)
        mini = mini.resize((mini.width * 2, mini.height * 2), Image.NEAREST)
        W = max(bust.width, mini.width)
        c = Image.new("RGBA", (W, bust.height + mini.height + 8), (140, 158, 128, 255))
        c.alpha_composite(bust, ((W - bust.width) // 2, 0))
        c.alpha_composite(mini, ((W - mini.width) // 2, bust.height + 8))
        cols.append(c)
    out = Image.new("RGBA", (sum(c.width for c in cols) + 8 * (len(cols) - 1), max(c.height for c in cols)), (140, 158, 128, 255))
    x = 0
    for c in cols:
        out.alpha_composite(c, (x, 0))
        x += c.width + 8
    p = os.path.join(a["out"], "compare_%s.png" % a.get("cmpname", name))
    out.convert("RGB").save(p)
    print("compare:", p)


def parse():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    a = {"stage": argv[0], "name": argv[1], "work": None, "out": None, "variant": "turbo", "offload": False}
    i = 2
    while i < len(argv):
        k = argv[i]
        if k in ("--work", "--out", "--variant", "--k"):
            a[k[2:]] = int(argv[i + 1]) if k == "--k" else argv[i + 1]; i += 1
        elif k in ("--hy", "--hat", "--map"):
            a[k[2:]] = argv[i + 1]; i += 1
        elif k == "--tag":
            a.setdefault("tags", []).append(argv[i + 1]); i += 1
        elif k == "--cmpname":
            a["cmpname"] = argv[i + 1]; i += 1
        elif k == "--assets":
            a["assets"] = True
        elif k == "--skip-hy":
            a["skip_hy"] = True
        elif k == "--offload":
            a["offload"] = True
        i += 1
    return a


if __name__ == "__main__":
    A = parse()
    {"gen": gen, "render": render, "compare": compare, "bake": bake, "hybrid": hybrid, "hybrid_compare": hybrid_compare}[A["stage"]](A)
