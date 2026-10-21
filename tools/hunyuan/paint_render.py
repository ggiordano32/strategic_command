"""Blender: raw Hunyuan mesh -> decimated, projection-textured mesh -> renders.

    ~/.local/bin/blender -b --factory-startup -P tools/hunyuan/paint_render.py -- \
        NAME [--work DIR] [--preview DIR] [--tris 50000] [--only mesh,mini,bust,turn]

Inputs : DIR/NAME/raw.glb and the four crops (front/left/right/back .png) that
         gen.py wrote.  Without raw.glb the committed assets/characters/NAME/mesh.glb
         is re-rendered (texture embedded).
Outputs: assets/characters/NAME/mesh.glb         decimated, textured (embedded 1024 albedo)
         assets/minis/characters/NAME.png (+ _mask.png, _small.png, _small_mask.png, .json)
         assets/portraits/NAME.png
         PREVIEW/preview_NAME.png                turntable sheet (8 angles, two views)

Texture: see texture.py and README (atlas of view charts, palette label + detail layer, baked 1024 albedo).
Palette entries with a mask channel (R = coat, G = sash / plume / headscarf) go to the mask pass.

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
sys.path.insert(0, HERE)
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# ------------------------------------------------------------------ palettes
# name: (hex, mask channel or None).  Colours are the code-drawn portraits'.
CHARS = {
    "mercy": {
        "bust": (0.16, 0.56), "height_m": 1.8, "head_labels": ["hat", "hair", "skin"],
        "mask": {"R": ["coat"], "G": []}, "face_z": 0.87, "hat_z": 0.93, "hat_zone": ["hat"], "hat_labels": ["hat"],
        "hat_lock": True, "skin_prune": False, "mouth_fix": True,
        "palette": {
            "coat": ("b8432f", "R"), "skin": ("c98f60", None), "hair": ("2a1a14", None),
            "hat": ("2c2a38", None), "shirt": ("e8c8b0", None), "leather": ("6a4a2e", None),
            "boots": ("3a281c", None), "brass": ("e2b84a", None),
        },
    },
    "rook": {
        "bust": (0.14, 0.52), "height_m": 2.0, "head_labels": ["skin", "hair", "headscarf"],
        "mask": {"R": ["coat"], "G": ["sash"]}, "face_z": 0.87, "hat_z": 0.90,
        "hat_zone": ["headscarf", "hair"], "hat_labels": ["headscarf"],
        "hat_lock": False, "skin_prune": False, "mouth_fix": False,
        "palette": {
            "coat": ("2f7f6f", "R"), "skin": ("a8704a", None), "hair": ("1c1412", None),
            "headscarf": ("e8dcb8", None), "sash": ("d9302a", "G"), "leather": ("7a5a34", None),
            "metal": ("cfd6dc", None), "trousers": ("c8b890", None),
        },
    },
    "captain": {
        "bust": (0.26, 0.64), "height_m": 1.85, "head_labels": ["hat", "plume", "hair", "skin"],
        "mask": {"R": ["coat"], "G": ["sash"]}, "face_z": 0.87, "head_alias": {"gold": "hat"},
        "hat_z": 0.93, "hat_zone": ["hat", "gold", "sash"], "hat_labels": ["hat"],
        "hat_lock": True, "skin_prune": False, "mouth_fix": False,
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
ANCHORS = {'mercy': {'coat': '7a2a20', 'skin': 'b88a6a', 'hair': '2e2018', 'hat': '2a2824', 'shirt': 'd8c8b0', 'leather': '5a4030', 'boots': '2e2218', 'brass': 'a8843a'}, 'rook': {'coat': ['457080', '2d5560', '5a8a96', '1f3d48'], 'skin': '9a6a4a', 'hair': '20181a', 'headscarf': 'e0d8c0', 'sash': 'c03028', 'leather': '6a4a2e', 'metal': '8a8a8a', 'trousers': 'cfc3a6'}, 'captain': {'coat': ['2a2826', '38302c', '262320'], 'sash': 'b02828', 'gold': 'b08a40', 'skin': 'c09878', 'hair': '7a6a60', 'hat': '2a2a2e', 'leather': ['593c2b', '3e2c1d', '322115'], 'shirt': 'd8c8b0'}}


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
        self.rgb_bled = bleed(self.rgb, self.alpha)
        self.col_src = self.rgb_bled
        self.col = box_blur(self.rgb_bled, 2)
        yy, xx = np.nonzero(self.alpha > 0.5)
        self.cx = xx.mean()   # centroid of the silhouette, px
        self.u, self.d, self.to_cam = (np.array(t, float) for t in VDEF[key])

    fit = None      # (a, b, c, d): px = a*u + b, py = c*z + d, set by fit_view

    def project(self, v, zmin, H, ucen):
        sc = self.h_px / H
        u = v @ self.u
        if self.fit is not None:
            a, b, c, d = self.fit
            return a * u + b, c * v[:, 2] + d, v @ self.d, sc
        px = self.cx + (u - ucen) * sc
        py = self.y1 - (v[:, 2] - zmin) * sc
        return px, py, v @ self.d, sc


def fit_view(vw, v, zmin, H, ucen, bands=(0.10, 0.30, 0.50, 0.70, 0.90)):
    """Least-squares fit of the mesh silhouette to the sheet silhouette: vertical = feet / crown extents,
    horizontal = the left / right extents at five height bands (10 / 30 / 50 / 70 / 90 %).
    Gives px = a*u + b, py = c*z + d.  Falls back to the nominal projection when unstable."""
    vw.fit = None
    sc = vw.h_px / H
    c = -sc
    d = vw.y1 + zmin * sc
    u = v @ vw.u
    al = vw.alpha > 0.5
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
    nom_a = sc
    nom_b = vw.cx - ucen * sc
    if len(xs_m) >= 6:
        A = np.stack([xs_m, np.ones(len(xs_m))], 1)
        (a, b), *_ = np.linalg.lstsq(A, np.array(xs_s, float), rcond=None)
        res = np.abs(A @ np.array([a, b]) - xs_s)
        ok = 0.88 < a / nom_a < 1.12 and res.mean() < 0.03 * vw.alpha.shape[1]
        print("  fit %-5s scale x %.3f (nominal 1.000)  offset %+.1f px  vertical scale 1.000 offset %+.1f px  "
              "mean residual %.1f px  %s" % (vw.key, a / nom_a, a * ucen + b - vw.cx, 0.0, res.mean(), "applied" if ok else "UNSTABLE: nominal kept"))
        if ok:
            vw.fit = (a, b, c, d)
    return vw.fit


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


# ------------------------------------------------------------------ UV + texture
def set_uv(me, uvc):
    """Write per-corner uvs (ntri,3,2) into the mesh's first uv layer (loop-triangle order)."""
    me.calc_loop_triangles()
    lt = np.empty(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get("loops", lt)
    for name in list(me.uv_layers.keys()):
        me.uv_layers.remove(me.uv_layers[name])
    me.uv_layers.new(name="UVMap")
    uv = np.zeros((len(me.loops), 2))
    uv[lt] = uvc.reshape(-1, 2)
    me.uv_layers[0].data.foreach_set("uv", uv.ravel())
    me.update()


def uv_corners(me):
    """(ntri,3,2) uv of every loop-triangle corner, in the triangles' own order."""
    me.calc_loop_triangles()
    lt = np.empty(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get("loops", lt)
    uv = np.empty(len(me.loops) * 2, np.float64)
    me.uv_layers[0].data.foreach_get("uv", uv)
    return uv.reshape(-1, 2)[lt.reshape(-1, 3)]


def read_vup(path):
    """Image file -> (H,W,4) float array in Blender's pixel order (row 0 = bottom = v 0), raw values."""
    im = bpy.data.images.load(path)
    im.colorspace_settings.name = "Non-Color"
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4).copy()
    bpy.data.images.remove(im)
    return a


def write_vup(path, rgb, alpha=1.0):
    h, w = rgb.shape[:2]
    arr = np.ones((h, w, 4), np.float32)
    arr[..., :3] = np.clip(rgb, 0, 1)
    arr[..., 3] = alpha
    im = bpy.data.images.new("o", w, h, alpha=True, float_buffer=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(arr.ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def export_mesh(ob, albedo_path, path):
    """GLB with the albedo texture embedded (glTF baseColorTexture), no vertex colours."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    me = ob.data
    for n in list(me.color_attributes.keys()):
        me.color_attributes.remove(me.color_attributes[n])
    im = bpy.data.images.load(albedo_path)
    im.colorspace_settings.name = "sRGB"
    m = bpy.data.materials.new("character")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = im
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    me.materials.clear()
    me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
              export_normals=True, export_texcoords=True, export_materials="EXPORT",
              export_image_format="AUTO")
    for extra in ({"export_vertex_color": "NONE"}, {"export_active_vertex_color_when_no_material": False}, {}):
        try:
            bpy.ops.export_scene.gltf(**kw, **extra)
            return
        except TypeError as e:
            print("  gltf export option rejected:", e)
    raise RuntimeError("glb export failed")


# ------------------------------------------------------------------ rendering
def tex_node(nt, ns, path, closest=False):
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color"      # the look is "Raw": values pass straight through
    t = ns["node"](nt, "ShaderNodeTexImage")
    t.image = img
    t.interpolation = "Closest" if closest else "Linear"
    t.extension = "EXTEND"
    return t


def textured_shade(ns, name, albedo_path, style="D"):
    """The structures' toon material (ramp * colour * height gradient) with the albedo texture as colour."""
    m = ns["shade_material"](name, style, (1.0, 1.0, 1.0), False)
    nt = m.node_tree
    mx = None
    for nd in nt.nodes:
        if nd.bl_idname == "ShaderNodeMix" and nd.blend_type == "MULTIPLY":
            a = ns["sock"](nd, "A_Color")
            b = ns["sock"](nd, "B_Color")
            if a.is_linked and not b.is_linked:
                mx = nd
                break
    t = tex_node(nt, ns, albedo_path)
    hs = nt.nodes.new("ShaderNodeHueSaturation")      # style D's saturation / value lift
    hs.inputs["Saturation"].default_value = 1.3
    hs.inputs["Value"].default_value = 1.06
    nt.links.new(t.outputs["Color"], hs.inputs["Color"])
    nt.links.new(hs.outputs["Color"], ns["sock"](mx, "B_Color"))
    return m


def mask_texture_material(ns, mask_path):
    m, nt = ns["new_material"]("pass_mask_tex")
    t = tex_node(nt, ns, mask_path, closest=True)
    em = ns["node"](nt, "ShaderNodeEmission")
    nt.links.new(t.outputs["Color"], em.inputs["Color"])
    out = ns["node"](nt, "ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


class Rig:
    """The character as one textured object with the structures' toon material, plus the mask pass."""

    def __init__(self, ns, cfg, v_raw, tri, uvc, lab_img, albedo_path, mask_path, H_m, names):
        self.ns = ns
        zmin, zmax = v_raw[:, 2].min(), v_raw[:, 2].max()
        k = H_m / (zmax - zmin)
        cx = (v_raw[:, 0].min() + v_raw[:, 0].max()) / 2
        cy = (v_raw[:, 1].min() + v_raw[:, 1].max()) / 2
        vs = (v_raw - np.array([cx, cy, zmin])) * k          # feet at z = 0, facing -y
        # weld by position (UV seams split vertices in an imported glb): smooth normals + a closed hull
        key = np.round(vs / 1e-5).astype(np.int64)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inv = inv.ravel()
        self.v = vs[first]
        t2 = inv[tri]
        ok = (t2[:, 0] != t2[:, 1]) & (t2[:, 1] != t2[:, 2]) & (t2[:, 0] != t2[:, 2])
        self.tri = t2[ok]
        uvc = uvc[ok]
        T = lab_img.shape[0]
        cu = np.clip((uvc[..., 0] * T).astype(int), 0, T - 1)
        cv = np.clip((uvc[..., 1] * T).astype(int), 0, T - 1)
        self.lab = np.zeros(len(self.v), np.int32)
        self.lab[self.tri.ravel()] = lab_img[cv, cu].ravel()      # a label per vertex (head / skin lookups)
        self.names = names
        self.cfg = cfg
        self.H = H_m
        self.albedo_path = albedo_path
        self.sc = ns["reset_scene"]()
        m = bpy.data.meshes.new("figure")
        m.from_pydata(self.v.tolist(), [], self.tri.tolist())
        m.update()
        m.uv_layers.new(name="UVMap")
        m.uv_layers[0].data.foreach_set("uv", uvc.reshape(-1, 2).ravel())
        for p in m.polygons:
            p.use_smooth = True
        self.ob = bpy.data.objects.new("figure", m)
        self.sc.collection.objects.link(self.ob)
        self.mask_mat = mask_texture_material(ns, mask_path)
        self.outlines = []
        self.materials("D")

    def materials(self, tag):
        self.ob.data.materials.clear()
        self.ob.data.materials.append(textured_shade(self.ns, "sh_" + tag, self.albedo_path))

    def pose(self, yaw_deg):
        self.ob.rotation_euler = (0, 0, math.radians(yaw_deg))
        for o in self.outlines:
            o.rotation_euler = (0, 0, math.radians(yaw_deg))

    def outline(self, thick):
        """One inverted hull round the whole figure."""
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
        vl.material_override = self.mask_mat if mask else None
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
def build_texture(name, cfg, names, pal_rgb, wd, tris, debug):
    """raw.glb -> oriented, decimated, UV-unwrapped mesh + baked albedo / label textures."""
    import texture
    ob = import_glb(os.path.join(wd, "raw.glb"))
    me = ob.data
    me.calc_loop_triangles()
    v, tri, edges, nrm = mesh_arrays(me)
    zmin, zmax = v[:, 2].min(), v[:, 2].max()
    H = zmax - zmin
    views = {k: View(k, load_view(os.path.join(wd, k + ".png"))) for k in VIEWS}
    kk, R = orient(v, views, zmin, H)
    v = v @ R.T
    me.vertices.foreach_set("co", v.astype(np.float32).ravel())
    me.update()
    print("  rotated %d deg to face -y" % (kk * 90))
    decimate(ob, tris)
    me = ob.data
    me.calc_loop_triangles()
    v, tri, edges, nrm = mesh_arrays(me)
    zmin, zmax = v[:, 2].min(), v[:, 2].max()
    H = zmax - zmin
    head_z = cfg.get("head_z", 0.82)
    T = 1024
    ucen = {k: silhouette_ucen(vw, v, zmin, H) for k, vw in views.items()}
    for k, vw in views.items():
        fit_view(vw, v, zmin, H, ucen[k])
    t1 = time.time()
    own, vis = texture.assign_views(v, tri, nrm, views, ucen, zmin, H, head_z)
    uvc, scale = texture.build_atlas(v, tri, own, views, zmin, H, head_z, T, cfg.get("head_density", 2.0))
    print("  atlas: views owning %s tris, body %.0f px per figure height (%.1fs)" % (
        np.bincount(own, minlength=4).tolist(), scale * H, time.time() - t1))
    set_uv(me, uvc)
    t1 = time.time()
    order = np.concatenate([np.nonzero(~vis)[0], np.nonzero(vis)[0]])      # occluded triangles first: visible ones win
    valid, pos, nr, tid = texture.rasterize(uvc, v[tri], nrm[tri], T, order)
    vid = np.where(valid, own[np.maximum(tid, 0)], 0)
    print("  rasterised %d texels (%.1fs)" % (valid.sum(), time.time() - t1))
    anc = [(i, hx) for i, n in enumerate(names) for hx in ([ANCHORS[name][n]] if isinstance(ANCHORS[name][n], str) else ANCHORS[name][n])]
    owner = np.array([i for i, _ in anc])
    pal_lab = rgb_to_lab(np.array([hex_rgb(hx) for _, hx in anc]))
    bands = {names.index(k): b for k, b in ZBAND[name].items() if k in names}
    # captain's head_labels name 'sash' (the plume) and 'hat'; only labels that exist count
    head_ids = [names.index(n) for n in cfg["head_labels"] if n in names]
    detail_ids = [names.index(n) for n in ("skin", "hair") if n in names]
    alias = {names.index(a_): names.index(b_) for a_, b_ in cfg.get("head_alias", {}).items() if a_ in names and b_ in names}
    lock = cfg.get("hat_lock", False)
    rules = {"hat_z": cfg.get("hat_z", 2.0) if lock else 2.0,
             "zone_ids": [names.index(n) for n in cfg.get("hat_zone", []) if n in names] if lock else [],
             "hat_ids": [names.index(n) for n in cfg.get("hat_labels", []) if n in names] if lock else [],
             "mouth": cfg.get("mouth_fix", False), "skin_prune": cfg.get("skin_prune", False)}
    stats = {}
    t1 = time.time()
    albedo, labels, _ = texture.bake(valid, pos, nr, vid, views, ucen, zmin, H, pal_rgb, pal_lab, owner, bands, names, rgb_to_lab, srgb_to_lin, lin_to_srgb,
                                     shift=cfg.get("shift"), debug=debug, head_ids=head_ids,
                                     face_z=cfg.get("face_z", 0.87), head_z=head_z, alias=alias, rules=rules, detail_ids=detail_ids, stats=stats)
    print("  label components removed: %d; ink texels: %d; hat strays %d; mouth specks %d; skin pruned %d" % (
        stats.get("removed", 0), stats.get("ink_texels", 0), stats.get("hat_stray", 0), stats.get("mouth", 0), stats.get("skin_pruned", 0)))
    print("  baked (%.1fs)" % (time.time() - t1))
    albedo, cover = texture.dilate_into(albedo, valid, 8)
    labels = texture.dilate_labels(labels, valid, 8)
    return ob, albedo, labels, uvc, v, tri


def mask_image(labels, names, cfg):
    m = np.zeros(labels.shape + (3,))
    for ch, lst in cfg["mask"].items():
        for nm in lst:
            m[labels == names.index(nm), {"R": 0, "G": 1, "B": 2}[ch]] = 1.0
    return m


def main():
    a = parse_args()
    name = a["name"]
    cfg = CHARS[name]
    names = list(cfg["palette"].keys())
    pal_rgb = np.array([hex_rgb(cfg["palette"][n][0]) for n in names])
    wd = os.path.join(a["work"], name)
    raw = os.path.join(wd, "raw.glb")
    mesh_path = os.path.join(REPO, "assets", "characters", name, "mesh.glb")
    mini_dir = os.path.join(REPO, "assets", "minis", "characters")
    port_path = os.path.join(REPO, "assets", "portraits", name + ".png")
    prev_dir = a["preview"] or a["work"]
    albedo_path = os.path.join(wd, "albedo.png")
    labels_path = os.path.join(wd, "labels.png")
    mask_path = os.path.join(wd, "maskmap.png")
    t0 = time.time()
    os.environ.setdefault("SC_DBG", "nogloss,nobev")   # organic meshes: no glint / dry-brush edge (noisy)
    ns = load_structures()
    os.makedirs(wd, exist_ok=True)

    # ---- mesh: decimate + unwrap + bake the texture, or reload the committed glb
    if os.path.exists(raw) and "mesh" in a["only"]:
        print("[%s] importing %s" % (name, raw))
        ob, albedo, labels, uvc, v_raw, tri = build_texture(name, cfg, names, pal_rgb, wd, a["tris"], bool(os.environ.get("HY_DEBUG")))
        write_vup(albedo_path, albedo)
        write_vup(labels_path, np.stack([labels / 255.0] * 3, -1))
        export_mesh(ob, albedo_path, mesh_path)
        print("  mesh.glb: %d verts, %d tris, %.2f MB; albedo.png %.2f MB" % (
            len(v_raw), len(tri), os.path.getsize(mesh_path) / 2 ** 20, os.path.getsize(albedo_path) / 2 ** 20))
    else:
        print("[%s] re-rendering %s" % (name, mesh_path))
        ob = import_glb(mesh_path)
        me = ob.data
        me.calc_loop_triangles()
        img = None
        for mat in me.materials:
            for nd in mat.node_tree.nodes:
                if nd.type == "TEX_IMAGE":
                    img = nd.image
        img.colorspace_settings.name = "Non-Color"
        w_, h_ = img.size
        albedo = np.array(img.pixels[:], np.float32).reshape(h_, w_, 4)[..., :3].astype(np.float64)
        v_raw, tri, _, _ = mesh_arrays(me)
        uvc = uv_corners(me)
        if os.path.exists(labels_path):
            labels = np.rint(read_vup(labels_path)[..., 0] * 255).astype(np.int32)
        else:
            lab_a = rgb_to_lab(albedo.reshape(-1, 3))
            d = ((lab_a[:, None, :] - rgb_to_lab(pal_rgb)[None]) ** 2).sum(-1)
            labels = d.argmin(1).reshape(h_, w_)
        write_vup(albedo_path, albedo)
    write_vup(mask_path, mask_image(labels, names, cfg))
    rig = Rig(ns, cfg, v_raw, tri, uvc, labels, albedo_path, mask_path, cfg["height_m"], names)
    lab2 = rig.lab
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
            mk = read_png(base + "_mask.png")
            body = mk[..., 3] > 0.5
            print("  mask coverage %s: R %.1f%%  G %.1f%% of the figure" % (
                tag or "big", 100.0 * (mk[..., 0][body] > 0.5).mean(), 100.0 * (mk[..., 1][body] > 0.5).mean()))
            info[tag or "big"] = {"w": rx, "h": ry, "ppm": ppm, "m_per_px": 1.0 / ppm, "tilt": tilt,
                                  "origin_px": [rx / 2 - cen.x * ppm, ry / 2 + ymid * ppm],
                                  "height_m": cfg["height_m"]}
        json.dump(info, open(os.path.join(mini_dir, name + ".json"), "w"))

    # ---- portrait bust: three-quarter, head and shoulders, 256 px, no height gradient
    if "bust" in a["only"]:
        ns["HEIGHT"]["D"] = None
        # shade materials were built with the gradient: rebuild the rig's materials
        rig.materials("bust")
        sk = (lab2 == names.index("skin")) & (v[:, 2] > 0.75 * cfg["height_m"])
        skin_top = np.percentile(v[sk, 2], 99.0)
        above, win = cfg["bust"]
        win = win * 1.3                                   # wider window: hat, plume and the far shoulder
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
        os.makedirs(os.path.dirname(port_path), exist_ok=True)
        rig.render(port_path)
        ns["HEIGHT"]["D"] = (1.2, 0.80, 1.0)
        rig.materials("D2")

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
