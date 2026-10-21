"""Blender: raw Hunyuan mesh -> decimated, flat-painted mesh -> renders.

    ~/.local/bin/blender -b --factory-startup -P tools/hunyuan/paint_render.py -- \
        NAME [--work DIR] [--preview DIR] [--tris 50000] [--only mesh,mini,bust,turn]

Inputs : DIR/NAME/raw.glb and the four crops (front/left/right/back .png) that
         gen.py wrote.  Without raw.glb the committed assets/characters/NAME/mesh.glb
         is re-rendered (its vertex colours are snapped back to the palette).
Outputs: assets/characters/NAME/mesh.glb         decimated, vertex-coloured (palette colours)
         assets/minis/characters/NAME.png (+ _mask.png, _small.png, _small_mask.png, .json)
         assets/portraits/NAME.png
         PREVIEW/preview_NAME.png                turntable sheet (8 angles, two views)

Painting: every vertex samples the sheet view that faces it best (and sees it:
a z-buffer per view), the colour is snapped to the character's palette
(the game's portrait colours, game/story_portrait.gd), labels are smoothed by a
neighbour vote.  Palette entries with a mask channel (R = coat, G = sash /
plume / headscarf) go to the mask pass.

The miniature uses the structures' camera, light, toon-D material and outline
(tools/structures/build.py is executed as a library, so the look stays in sync).
"""
import colorsys
import json
import math
import os
import sys
import time

import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# ------------------------------------------------------------------ palettes
# name: (hex, mask channel or None).  Colours are the code-drawn portraits'.
CHARS = {
    "mercy": {
        "bust": (0.16, 0.56), "height_m": 1.8, "head_labels": ["hat", "hair", "skin"],
        "palette": {
            "coat": ("b8432f", "R"), "skin": ("c98f60", None), "hair": ("2a1a14", None),
            "hat": ("2c2a38", None), "shirt": ("e8c8b0", None), "leather": ("6a4a2e", None),
            "boots": ("3a281c", None), "brass": ("e2b84a", None),
        },
    },
    "rook": {
        "bust": (0.14, 0.52), "height_m": 2.0, "head_labels": ["skin", "hair", "headscarf"],
        "palette": {
            "coat": ("2f7f6f", "R"), "skin": ("a8704a", None), "hair": ("1c1412", None),
            "headscarf": ("e8dcb8", None), "sash": ("d9302a", "G"), "leather": ("7a5a34", None),
            "metal": ("cfd6dc", None), "trousers": ("c8b890", None),
        },
    },
    "captain": {
        "bust": (0.26, 0.64), "height_m": 1.85, "head_labels": ["hat", "plume", "hair", "skin"],
        "palette": {
            "coat": ("4a4a52", "R"), "sash": ("d9302a", "G"), "gold": ("d9a31f", None),
            "skin": ("d9a67a", None), "hair": ("7a6a5a", None), "hat": ("16161a", None),
            "leather": ("4a3c34", None), "shirt": ("ecd0bc", None),
        },
    },
}
# the plume is the sash colour on the captain: same entry, so alias
CHARS["captain"]["palette"]["plume"] = ("d9302a", "G")
CHARS["captain"]["palette"].pop("plume")
CHARS["captain"]["head_labels"] = ["hat", "sash", "hair", "skin"]


# palette entries only allowed in a height band (fraction of the figure's height)
ZBAND = {"mercy": {"hat": (0.80, 1.01), "boots": (0.0, 0.33)},
         "rook": {"headscarf": (0.85, 1.01)},
         "captain": {"hat": (0.78, 1.01)}}
ANCHORS = {'mercy': {'coat': '7a2a20', 'skin': 'b88a6a', 'hair': '2e2018', 'hat': '2a2824', 'shirt': 'd8c8b0', 'leather': '5a4030', 'boots': '2e2218', 'brass': 'a8843a'}, 'rook': {'coat': ['457080', '2d5560', '5a8a96', '1f3d48'], 'skin': '9a6a4a', 'hair': '20181a', 'headscarf': 'e0d8c0', 'sash': 'c03028', 'leather': '6a4a2e', 'metal': '8a8a8a', 'trousers': 'cfc3a6'}, 'captain': {'coat': '2a3040', 'sash': 'b02828', 'gold': 'b08a40', 'skin': 'c09878', 'hair': '7a6a60', 'hat': '2a2a2e', 'leather': '4a3828', 'shirt': 'd8c8b0'}}


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)


def rgb_to_lab(rgb):
    lin = srgb_to_lin(rgb)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = lin @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


# ------------------------------------------------------------------ args
def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"name": argv[0], "work": os.path.join(REPO, "hunyuan_work"), "preview": None,
         "tris": 50000, "only": "mesh,mini,bust,turn"}
    i = 1
    while i < len(argv):
        k = argv[i]
        if k in ("--work", "--preview", "--only"):
            a[k[2:]] = argv[i + 1]; i += 1
        elif k == "--tris":
            a["tris"] = int(argv[i + 1]); i += 1
        i += 1
    a["only"] = a["only"].split(",")
    return a


# ------------------------------------------------------------------ build.py as a library
def load_structures():
    p = os.path.join(REPO, "tools", "structures", "build.py")
    src = open(p).read()
    k = src.rindex("\nmain()")
    ns = {"__file__": p, "__name__": "structures_build"}
    exec(compile(src[:k], p, "exec"), ns)
    return ns


# ------------------------------------------------------------------ mesh io
def import_glb(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    ob = obs[0]
    if len(obs) > 1:
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.join()
    me = ob.data
    me.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    return ob


def mesh_arrays(me):
    n = len(me.vertices)
    v = np.empty(n * 3, np.float32)
    me.vertices.foreach_get("co", v)
    f = np.empty(len(me.polygons) * 3, np.int32)
    me.loops.foreach_get("vertex_index", f) if False else None
    tri = np.empty(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get("vertices", tri)
    e = np.empty(len(me.edges) * 2, np.int32)
    me.edges.foreach_get("vertices", e)
    nr = np.empty(n * 3, np.float32)
    me.vertex_normals.foreach_get("vector", nr)
    return v.reshape(-1, 3).astype(np.float64), tri.reshape(-1, 3), e.reshape(-1, 2), nr.reshape(-1, 3).astype(np.float64)


# ------------------------------------------------------------------ sheet views
VIEWS = ["front", "left", "right", "back"]
# image-right axis (u), depth (smaller = nearer the camera) and the direction towards the camera,
# for a figure facing -y (Blender's front)
VDEF = {
    "front": ((1, 0, 0), (0, 1, 0), (0, -1, 0)),
    "back": ((-1, 0, 0), (0, -1, 0), (0, 1, 0)),
    "left": ((0, 1, 0), (-1, 0, 0), (1, 0, 0)),
    "right": ((0, -1, 0), (1, 0, 0), (-1, 0, 0)),
}


def load_view(path):
    im = bpy.data.images.load(path)
    im.colorspace_settings.name = "Non-Color"
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]   # top-down
    bpy.data.images.remove(im)
    return px


def bleed(rgb, alpha, passes=40):
    """Spread opaque colours into the transparent margin so edge samples are never background."""
    m = alpha > 0.5
    c = rgb.copy()
    for _ in range(passes):
        if m.all():
            break
        acc = np.zeros_like(c)
        cnt = np.zeros(m.shape, np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                mm = np.roll(np.roll(m, dy, 0), dx, 1)
                cc = np.roll(np.roll(c, dy, 0), dx, 1)
                acc += cc * mm[..., None]
                cnt += mm
        new = (~m) & (cnt > 0)
        c[new] = acc[new] / cnt[new][:, None]
        m = m | new
    return c


def box_blur(c, r):
    out = np.zeros_like(c)
    k = 0
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out += np.roll(np.roll(c, dy, 0), dx, 1)
            k += 1
    return out / k


class View:
    def __init__(self, key, px):
        self.key = key
        self.rgb = px[..., :3]
        self.alpha = px[..., 3]
        ys, xs = np.nonzero(self.alpha > 0.5)
        self.x0, self.x1, self.y0, self.y1 = xs.min(), xs.max(), ys.min(), ys.max()
        self.h_px = self.y1 - self.y0
        self.col = box_blur(bleed(self.rgb, self.alpha), 2)
        yy, xx = np.nonzero(self.alpha > 0.5)
        self.cx = xx.mean()   # centroid of the silhouette, px
        self.u, self.d, self.to_cam = (np.array(t, float) for t in VDEF[key])

    def project(self, v, zmin, H, ucen):
        sc = self.h_px / H
        u = v @ self.u
        px = self.cx + (u - ucen) * sc
        py = self.y1 - (v[:, 2] - zmin) * sc
        return px, py, v @ self.d, sc


def silhouette_ucen(view, v, zmin, H):
    """Mesh u-centroid so that its silhouette centroid sits on the image's."""
    sc = view.h_px / H
    u = v @ view.u
    G = 256
    s = G / view.alpha.shape[0]
    gx = np.clip(((u - u.mean()) * sc * s + G / 2).astype(int), 0, G - 1)
    gy = np.clip(((v[:, 2] - zmin) * sc * s).astype(int), 0, G - 1)
    occ = np.zeros((G, G), bool)
    occ[gy, gx] = True
    ys, xs = np.nonzero(occ)
    cen = (xs.mean() - G / 2) / (sc * s) + u.mean()
    return cen


def sil_score(view, v, zmin, H):
    sc = view.h_px / H
    ucen = silhouette_ucen(view, v, zmin, H)
    px, py, _, _ = view.project(v, zmin, H, ucen)
    G = 256
    s = G / view.alpha.shape[0]
    occ = np.zeros((G, G), bool)
    gx = np.clip((px * s).astype(int), 0, G - 1)
    gy = np.clip((py * s).astype(int), 0, G - 1)
    occ[gy, gx] = True
    # close small holes between splats
    for _ in range(2):
        occ = occ | np.roll(occ, 1, 0) | np.roll(occ, -1, 0) | np.roll(occ, 1, 1) | np.roll(occ, -1, 1)
    a = view.alpha[::4, ::4] > 0.5
    return (occ & a).sum() / max(1, (occ | a).sum())


def orient(v, views, zmin, H):
    """Rotation about z (k * 90 deg) that makes the mesh face -y, by silhouette overlap with all four views."""
    best = None
    for k in range(4):
        th = k * math.pi / 2
        R = np.array([[math.cos(th), -math.sin(th), 0], [math.sin(th), math.cos(th), 0], [0, 0, 1]])
        vr = v @ R.T
        sc = sum(sil_score(vw, vr, zmin, H) for vw in views.values())
        print("  orientation %3d deg: IoU sum %.3f" % (k * 90, sc))
        if best is None or sc > best[0]:
            best = (sc, k, R)
    return best[1], best[2]


def paint_labels(v, nrm, edges, views, pal_lab, ncol, zmin, H, bands=None, owner=None):
    N = len(v)
    best_w = np.full(N, -1.0)
    rgb = np.zeros((N, 3))
    ucen = {k: silhouette_ucen(vw, v, zmin, H) for k, vw in views.items()}
    for k, vw in views.items():
        px, py, depth, sc = vw.project(v, zmin, H, ucen[k])
        # z-buffer on a 512 grid
        G = 512
        s = G / vw.alpha.shape[0]
        gx = np.clip((px * s).astype(int), 0, G - 1)
        gy = np.clip((py * s).astype(int), 0, G - 1)
        zb = np.full(G * G, 1e9)
        np.minimum.at(zb, gy * G + gx, depth)
        zb = zb.reshape(G, G)
        zn = zb.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                zn = np.minimum(zn, np.roll(np.roll(zb, dy, 0), dx, 1))
        vis = depth <= zn[gy, gx] + 0.04
        facing = np.maximum(nrm @ vw.to_cam, 0.0)
        w = facing * (0.25 + 0.75 * vis)
        w = np.where(vis, facing + 1.0, facing * 0.2)      # visible beats hidden
        ix = np.clip(np.round(px).astype(int), 0, vw.rgb.shape[1] - 1)
        iy = np.clip(np.round(py).astype(int), 0, vw.rgb.shape[0] - 1)
        take = w > best_w
        rgb[take] = vw.col[iy[take], ix[take]]
        best_w[take] = w[take]
    lab = rgb_to_lab(rgb)
    # lightness counts little: the sheets are shaded, the palette is flat
    d = np.stack([(lab[:, None, 0] - pal_lab[None, :, 0]) * 0.6,
                  lab[:, None, 1] - pal_lab[None, :, 1], lab[:, None, 2] - pal_lab[None, :, 2]], -1)
    dist = (d ** 2).sum(-1)
    if owner is not None:      # several anchors per palette entry: nearest of each
        dd = np.full((len(dist), ncol), 1e9)
        for j, o in enumerate(owner):
            dd[:, o] = np.minimum(dd[:, o], dist[:, j])
        dist = dd
    zf = (v[:, 2] - zmin) / H
    for i, (lo, hi) in (bands or {}).items():
        dist[(zf < lo) | (zf > hi), i] += 1e5
    lab_idx = dist.argmin(1)
    # neighbour vote smoothing
    a, b = edges[:, 0], edges[:, 1]
    for _ in range(12):
        cnt = np.zeros((N, ncol))
        np.add.at(cnt, (a, lab_idx[b]), 1.0)
        np.add.at(cnt, (b, lab_idx[a]), 1.0)
        cnt[np.arange(N), lab_idx] += 1.5
        lab_idx = cnt.argmax(1)
    if os.environ.get("HY_DEBUG"):
        for i in range(ncol):
            m = lab_idx == i
            print("  label %d: %6d verts, mean sampled rgb %s" % (i, m.sum(), np.round(rgb[m].mean(0), 2) if m.any() else "-"))
    return lab_idx, rgb


# ------------------------------------------------------------------ mesh cleanup
def decimate(ob, target_tris):
    me = ob.data
    me.calc_loop_triangles()
    ntri = len(me.loop_triangles)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=1e-5)
    bpy.ops.object.mode_set(mode="OBJECT")
    md = ob.modifiers.new("dec", "DECIMATE")
    md.ratio = min(1.0, target_tris / max(1, ntri))
    bpy.ops.object.modifier_apply(modifier="dec")
    # drop small floating islands
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    seen = {}
    comps = []
    for v0 in bm.verts:
        if v0.index in seen:
            continue
        stack, comp = [v0], []
        seen[v0.index] = True
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen[y.index] = True
                    stack.append(y)
        comps.append(comp)
    big = max(len(c) for c in comps)
    kill = [x for c in comps if len(c) < big * 0.02 for x in c]
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        print("  removed %d floating vertices (%d islands)" % (len(kill), sum(1 for c in comps if len(c) < big * 0.02)))
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    for p in ob.data.polygons:
        p.use_smooth = True


def set_vertex_colors(me, rgb_lin):
    if "Col" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["Col"])
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    flat = np.concatenate([rgb_lin, np.ones((len(rgb_lin), 1))], 1).astype(np.float32).ravel()
    ca.data.foreach_set("color", flat)
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = list(me.color_attributes.keys()).index("Col")


def get_vertex_colors(me):
    ca = me.color_attributes[0]
    n = len(me.vertices)
    arr = np.empty(len(ca.data) * 4, np.float32)
    ca.data.foreach_get("color", arr)
    arr = arr.reshape(-1, 4)[:, :3]
    if ca.domain == "CORNER":
        out = np.zeros((n, 3))
        idx = np.empty(len(me.loops), np.int32)
        me.loops.foreach_get("vertex_index", idx)
        out[idx] = arr
        return out
    return arr.astype(np.float64)


def export_mesh(ob, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
              export_normals=True, export_texcoords=False, export_materials="NONE")
    for extra in ({"export_vertex_color": "ACTIVE"}, {"export_active_vertex_color_when_no_material": True}, {}):
        try:
            bpy.ops.export_scene.gltf(**kw, **extra)
            return
        except TypeError:
            continue


# ------------------------------------------------------------------ rendering
class Rig:
    """The character as one object per palette colour, with the structures' materials."""

    def __init__(self, ns, cfg, names, labels, mesh_ob, H_m, style="D"):
        self.ns = ns
        me = mesh_ob.data
        v = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", v)
        v = v.reshape(-1, 3).astype(np.float64)
        zmin, zmax = v[:, 2].min(), v[:, 2].max()
        k = H_m / (zmax - zmin)
        cx = (v[:, 0].min() + v[:, 0].max()) / 2
        cy = (v[:, 1].min() + v[:, 1].max()) / 2
        self.v = (v - np.array([cx, cy, zmin])) * k      # feet at z = 0, facing -y
        tri = np.empty(len(me.loop_triangles) * 3, np.int32)
        me.calc_loop_triangles()
        me.loop_triangles.foreach_get("vertices", tri)
        self.tri = tri.reshape(-1, 3)
        self.sc = ns["reset_scene"]()     # clears the imported mesh: arrays are copied above
        self.labels = labels
        self.names = names
        self.cfg = cfg
        self.objs = []
        self.H = H_m
        self.mat_cache = {}
        # face label = label of its first vertex that agrees with another, else the first
        l0, l1, l2 = labels[self.tri[:, 0]], labels[self.tri[:, 1]], labels[self.tri[:, 2]]
        fl = np.where(l1 == l2, l1, l0)
        self.fl = fl
        pal = cfg["palette"]
        self.pivot = Vector((0, 0, 0))
        for i, nm in enumerate(names):
            sel = np.nonzero(fl == i)[0]
            if len(sel) == 0:
                continue
            hexc, ch = pal[nm]
            idx = self.tri[sel]
            used, inv = np.unique(idx.ravel(), return_inverse=True)
            m = bpy.data.meshes.new("c_" + nm)
            m.from_pydata(self.v[used].tolist(), [], inv.reshape(-1, 3).tolist())
            m.update()
            for p in m.polygons:
                p.use_smooth = True
            ob = bpy.data.objects.new("c_" + nm, m)
            self.sc.collection.objects.link(ob)
            ob["sc_mask"] = list({"R": (1, 0, 0), "G": (0, 1, 0), "B": (0, 0, 1)}.get(ch, (0, 0, 0))) + [1.0]
            rgb = ns["adjust"](hex_rgb(hexc), style)
            ob.data.materials.append(ns["shade_material"]("s_" + nm, style, rgb, False))
            ob.rotation_mode = "XYZ"
            self.objs.append((ob, nm, rgb))
        self.outlines = []

    def pose(self, yaw_deg):
        for ob, _, _ in self.objs:
            ob.rotation_euler = (0, 0, math.radians(yaw_deg))
        for o in self.outlines:
            o.rotation_euler = (0, 0, math.radians(yaw_deg))

    def outline(self, thick):
        """One inverted hull round the whole figure (per-part hulls spike at the seams)."""
        ns = self.ns
        for o in self.outlines:
            bpy.data.objects.remove(o)
        self.outlines = []
        col = (0.10, 0.06, 0.05)
        m = bpy.data.meshes.new("ol")
        m.from_pydata(self.v.tolist(), [], self.tri.tolist())
        m.update()
        for p in m.polygons:
            p.use_smooth = True
        o2 = bpy.data.objects.new("ol", m)
        self.sc.collection.objects.link(o2)
        o2.data.materials.append(ns["flat_material"]("ol_ink", col, cull=True))
        md = o2.modifiers.new("sol", "SOLIDIFY")
        md.thickness = thick
        md.offset = 1.0
        md.use_flip_normals = True
        md.use_even_offset = False
        try:
            o2.visible_shadow = False
        except Exception:
            pass
        self.outlines.append(o2)

    def lights(self):
        ns = self.ns
        ns["add_sun"]("key", ns["KEY_TO"], ns["SPEC"]["light"]["key"], True)
        ns["add_sun"]("fill", ns["FILL_TO"], ns["SPEC"]["light"]["fill"], False, 20.0)

    def camera(self, tilt_deg, centre_world, ortho_m, res_x, res_y):
        """Same convention as structures/build.py: looks north from the south, tilted from vertical."""
        t = math.radians(tilt_deg)
        right = Vector((1, 0, 0))
        up = Vector((0, math.cos(t), math.sin(t)))
        view = Vector((0, math.sin(t), -math.cos(t)))
        for o in list(bpy.data.objects):
            if o.type == "CAMERA":
                bpy.data.objects.remove(o)
        cd = bpy.data.cameras.new("cam")
        cd.type = "ORTHO"
        cd.ortho_scale = ortho_m
        cd.clip_start, cd.clip_end = 0.1, 400.0
        cam = bpy.data.objects.new("cam", cd)
        self.sc.collection.objects.link(cam)
        self.sc.camera = cam
        cx = centre_world.dot(right)
        cy = centre_world.dot(up)
        cam.location = right * cx + up * cy - view * 150.0
        cam.rotation_euler = (t, 0, 0)
        self.sc.render.resolution_x, self.sc.render.resolution_y = res_x, res_y

    def render(self, path, mask=False):
        vl = bpy.context.view_layer
        for o in self.outlines:
            o.hide_render = mask
        vl.material_override = self.ns["mask_material"]() if mask else None
        self.sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        vl.material_override = None


def read_png(path):
    im = bpy.data.images.load(path)
    im.colorspace_settings.name = "Non-Color"
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1].copy()
    bpy.data.images.remove(im)
    return a


def write_png(path, arr):
    arr = np.clip(arr, 0, 1).astype(np.float32)
    h, w = arr.shape[:2]
    im = bpy.data.images.new("o", w, h, alpha=True, float_buffer=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(arr[::-1].ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


# ------------------------------------------------------------------ main
def main():
    a = parse_args()
    name = a["name"]
    cfg = CHARS[name]
    names = list(cfg["palette"].keys())
    pal_rgb = np.array([hex_rgb(cfg["palette"][n][0]) for n in names])
    anc = [(i, hx) for i, n in enumerate(names) for hx in ([ANCHORS[name][n]] if isinstance(ANCHORS[name][n], str) else ANCHORS[name][n])]
    anc_owner = np.array([i for i, _ in anc])
    pal_lab = rgb_to_lab(np.array([hex_rgb(hx) for _, hx in anc]))   # classify against the sheet colours
    wd = os.path.join(a["work"], name)
    raw = os.path.join(wd, "raw.glb")
    mesh_path = os.path.join(REPO, "assets", "characters", name, "mesh.glb")
    mini_dir = os.path.join(REPO, "assets", "minis", "characters")
    port_path = os.path.join(REPO, "assets", "portraits", name + ".png")
    prev_dir = a["preview"] or a["work"]
    t0 = time.time()
    os.environ.setdefault("SC_DBG", "nogloss,nobev")   # organic meshes: no glint / dry-brush edge (noisy)
    ns = load_structures()

    # ---- mesh: decimate + paint, or reload
    if os.path.exists(raw):
        print("[%s] importing %s" % (name, raw))
        ob = import_glb(raw)
        me = ob.data
        me.calc_loop_triangles()
        v, tri, edges, nrm = mesh_arrays(me)
        zmin, zmax = v[:, 2].min(), v[:, 2].max()
        H = zmax - zmin
        views = {k: View(k, load_view(os.path.join(wd, k + ".png"))) for k in VIEWS}
        kk, R = orient(v, views, zmin, H)
        v = v @ R.T
        nrm = nrm @ R.T
        print("  rotated %d deg to face -y" % (kk * 90))
        bands = {names.index(k): b for k, b in ZBAND[name].items() if k in names}
        labels, _ = paint_labels(v, nrm, edges, views, pal_lab, len(names), zmin, H, bands, anc_owner)
        # move the rotated dense positions back into the mesh
        me.vertices.foreach_set("co", v.astype(np.float32).ravel())
        me.update()
        # transfer labels through a decimated copy
        kd = kdtree.KDTree(len(v))
        for i, p in enumerate(v):
            kd.insert(Vector(p), i)
        kd.balance()
        decimate(ob, a["tris"])
        me = ob.data
        v2, tri2, edges2, _ = mesh_arrays(me)
        lab2 = np.empty(len(v2), np.int32)
        for i, p in enumerate(v2):
            lab2[i] = labels[kd.find(Vector(p))[1]]
        n2 = len(v2)
        for _ in range(4):
            cnt = np.zeros((n2, len(names)))
            np.add.at(cnt, (edges2[:, 0], lab2[edges2[:, 1]]), 1.0)
            np.add.at(cnt, (edges2[:, 1], lab2[edges2[:, 0]]), 1.0)
            cnt[np.arange(n2), lab2] += 1.5
            lab2 = cnt.argmax(1)
        set_vertex_colors(me, srgb_to_lin(pal_rgb[lab2]))
        export_mesh(ob, mesh_path)
        print("  mesh.glb: %d verts, %d tris, %.2f MB" % (n2, len(tri2), os.path.getsize(mesh_path) / 2 ** 20))
    else:
        print("[%s] re-rendering %s" % (name, mesh_path))
        ob = import_glb(mesh_path)
        me = ob.data
        cols = lin_to_srgb(get_vertex_colors(me))
        lab2 = rgb_to_lab(cols)
        d = ((lab2[:, None, :] - pal_lab[None]) ** 2).sum(-1)
        lab2 = d.argmin(1)
        me.calc_loop_triangles()
    # the Rig works on the mesh's own vertex positions (feet to z=0, scaled to metres)
    rig = Rig(ns, cfg, names, lab2, ob, cfg["height_m"])
    v = rig.v
    head_ids = [names.index(n) for n in cfg["head_labels"] if n in names]
    hm = np.isin(lab2, head_ids)
    head_top = v[hm, 2].max()

    # ---- overworld miniature: structures' camera (tilt 52), light, toon D, ink outline
    tilt = 52.0
    if "mini" in a["only"]:
        os.makedirs(mini_dir, exist_ok=True)
        t = math.radians(tilt)
        ys = v[:, 1] * math.cos(t) + v[:, 2] * math.sin(t)
        info = {}
        for tag, hpx in (("", 96), ("_small", 48)):
            ppm = hpx / (ys.max() - ys.min() + 0.2)
            pad_m = 0.35
            w_m = (v[:, 0].max() - v[:, 0].min()) + 2 * pad_m
            h_m = (ys.max() - ys.min()) + 2 * pad_m
            rx, ry = int(math.ceil(w_m * ppm)), int(math.ceil(h_m * ppm))
            rig.pose(0)
            cen = Vector(((v[:, 0].max() + v[:, 0].min()) / 2, 0, 0))
            # centre of the projected box: up coordinate midpoint
            ymid = (ys.max() + ys.min()) / 2
            centre = Vector((cen.x, ymid * math.cos(t), ymid * math.sin(t)))
            rig.camera(tilt, centre, max(rx, ry) / ppm, rx, ry)
            rig.outline(max(0.9, 1.2 * max(0.55, hpx * 2 / 256.0)) / ppm)
            for o in list(bpy.data.objects):
                if o.type == "LIGHT":
                    bpy.data.objects.remove(o)
            rig.lights()
            base = os.path.join(mini_dir, name + tag)
            rig.render(base + ".png")
            rig.render(base + "_mask.png", mask=True)
            info[tag or "big"] = {"w": rx, "h": ry, "ppm": ppm, "m_per_px": 1.0 / ppm, "tilt": tilt,
                                  "origin_px": [rx / 2 - cen.x * ppm, ry / 2 + ymid * ppm],
                                  "height_m": cfg["height_m"]}
        json.dump(info, open(os.path.join(mini_dir, name + ".json"), "w"))

    # ---- portrait bust: three-quarter, head and shoulders, 256 px, no height gradient
    if "bust" in a["only"]:
        ns["HEIGHT"]["D"] = None
        # shade materials were built with the gradient: rebuild the rig's materials
        for ob_, nm, rgb in rig.objs:
            ob_.data.materials.clear()
            ob_.data.materials.append(ns["shade_material"]("sb_" + nm, "D", rgb, False))
        sk = (lab2 == names.index("skin")) & (v[:, 2] > 0.75 * cfg["height_m"])
        skin_top = np.percentile(v[sk, 2], 99.0)
        above, win = cfg["bust"]
        zt = skin_top + above
        zb = zt - win
        sel = sk & (v[:, 2] > skin_top - 0.25)
        yaw = math.radians(-32)
        hx, hy = v[sel, 0].mean(), v[sel, 1].mean()
        xm = hx * math.cos(yaw) - hy * math.sin(yaw)      # head centre after the figure's yaw
        ym = hx * math.sin(yaw) + hy * math.cos(yaw)
        zc = (zt + zb) / 2
        rig.pose(-32)
        t = math.radians(80.0)
        rig.camera(80.0, Vector((xm, 0, 0)), (zt - zb) * 1.08, 256, 256)
        rig.outline(1.3 / (256 / ((zt - zb) * 1.08)))
        for o in list(bpy.data.objects):
            if o.type == "LIGHT":
                bpy.data.objects.remove(o)
        rig.lights()
        rig.pose(-32)
        view = Vector((0, math.sin(t), -math.cos(t)))
        rig.sc.camera.location = Vector((xm, ym, zc)) - view * 150.0
        os.makedirs(os.path.dirname(port_path), exist_ok=True)
        rig.render(port_path)
        ns["HEIGHT"]["D"] = (1.2, 0.80, 1.0)
        for ob_, nm, rgb in rig.objs:
            ob_.data.materials.clear()
            ob_.data.materials.append(ns["shade_material"]("s2_" + nm, "D", rgb, False))

    # ---- turntable: 8 headings, miniature view and a low (eye-level) view
    if "turn" in a["only"]:
        os.makedirs(prev_dir, exist_ok=True)
        rows = []
        tmp = os.path.join(a["work"], name, "_turn")
        os.makedirs(tmp, exist_ok=True)
        for tl, hpx in ((tilt, 200), (86.0, 300)):
            t = math.radians(tl)
            ys = v[:, 1] * math.cos(t) + v[:, 2] * math.sin(t)
            ppm = hpx / (ys.max() - ys.min())
            wm = max(v[:, 0].max() - v[:, 0].min(), v[:, 1].max() - v[:, 1].min()) + 0.4
            rx, ry = int(wm * ppm), int((ys.max() - ys.min() + 0.2) * ppm)
            ymid = (ys.max() + ys.min()) / 2
            frames = []
            for k in range(8):
                rig.pose(45.0 * k)
                # eye-level: centre on the figure; miniature: as above
                rig.camera(tl, Vector((0, ymid * math.cos(t), ymid * math.sin(t))), max(rx, ry) / ppm, rx, ry)
                rig.outline(1.2 / ppm * (1.0 if tl < 80 else 1.5))
                for o in list(bpy.data.objects):
                    if o.type == "LIGHT":
                        bpy.data.objects.remove(o)
                rig.lights()
                rig.pose(45.0 * k)
                p = os.path.join(tmp, "t_%d_%d.png" % (int(tl), k))
                rig.render(p)
                frames.append(read_png(p))
            rows.append(np.concatenate(frames, 1))
        W = max(r.shape[1] for r in rows)
        Hh = sum(r.shape[0] for r in rows)
        bg = np.zeros((Hh, W, 4), np.float32)
        bg[..., :3] = (0.55, 0.62, 0.50)
        bg[..., 3] = 1
        y = 0
        for r in rows:
            al = r[..., 3:4]
            bg[y:y + r.shape[0], :r.shape[1], :3] = r[..., :3] * al + bg[y:y + r.shape[0], :r.shape[1], :3] * (1 - al)
            y += r.shape[0]
        write_png(os.path.join(prev_dir, "preview_%s.png" % name), bg)
    print("[%s] done in %.1fs" % (name, time.time() - t0))


main()
