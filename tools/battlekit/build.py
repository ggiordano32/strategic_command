"""Battle-map modular kit (style mockup): builds pieces procedurally in Blender
and renders straight top-down G-buffer passes (orthographic, camera looking
down -Z, image up = +Y north), unlit and unrotated, so that lighting, cast
shadow, ambient occlusion and recolour are done afterwards (compose.py) for
any piece rotation and any light direction.

    ~/.local/bin/blender -b --factory-startup -P tools/battlekit/build.py -- \
        [--pieces wall_m,tower_round] [--ppm 8] [--tilt 0] [--out DIR]

Per piece: <name>_albedo.png (RGBA, masked parts are grey so recolour
multiplies), _normal.png (world normal * 0.5 + 0.5), _height.png (16 bit,
z / ZMAX), _mask.png (R roof / awning / flag, G plaster / wall, B accent),
<name>.json (canvas metres, px per metre, ZMAX). The piece origin is the
canvas centre. --tilt 40 renders the same passes from an oblique camera (iso
option; no cast shadow from the height pass then).
"""
import bpy
import bmesh
import json
import math
import os
import random
import sys
import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
ZMAX = 20.0

# ------------------------------------------------------------------ colours
# Display-space values (Raw view transform). Masked parts are written as grey
# with detail; compose.py multiplies them by the culture palette.
COL = {
    "stone": (0.60, 0.57, 0.52), "stone_d": (0.46, 0.44, 0.41), "stone_l": (0.70, 0.67, 0.60),
    "cobble": (0.40, 0.36, 0.31), "earth": (0.50, 0.40, 0.28), "timber": (0.46, 0.32, 0.20),
    "timber_d": (0.30, 0.21, 0.14), "thatch": (0.70, 0.58, 0.32), "metal": (0.28, 0.29, 0.31),
    "rock": (0.62, 0.57, 0.50), "rock_d": (0.42, 0.39, 0.36), "water": (0.14, 0.2, 0.24),
    "leaf_a": (0.28, 0.46, 0.20), "leaf_b": (0.22, 0.40, 0.18), "leaf_c": (0.34, 0.50, 0.22),
    "pine": (0.30, 0.50, 0.32), "palm": (0.40, 0.60, 0.26), "trunk": (0.32, 0.22, 0.14),
    "hay": (0.76, 0.64, 0.32), "turf": (0.38, 0.47, 0.24), "grey": (0.85, 0.85, 0.85),
}
# key -> (colour key or rgb, pattern, mask channel, smooth)
MATS = {
    "stone": ("stone", "blocks", None, 0), "stone_d": ("stone_d", "blocks", None, 0),
    "stone_l": ("stone_l", "blocks", None, 0), "cobble": ("cobble", "cobble", None, 0),
    "earth": ("earth", "noise", None, 0), "timber": ("timber", "planks", None, 0),
    "timber_d": ("timber_d", "planks", None, 0), "thatch": ("thatch", "thatch", None, 0),
    "metal": ("metal", "noise", None, 0), "rock": ("rock", "rock", None, 1),
    "rock_d": ("rock_d", "rock", None, 1), "water": ("water", "noise", None, 1),
    "leaf_a": ("leaf_a", "leaf", None, 1), "leaf_b": ("leaf_b", "leaf", None, 1),
    "leaf_c": ("leaf_c", "leaf", None, 1), "pine": ("pine", "leaf", None, 0),
    "palm": ("palm", "leaf", None, 1), "trunk": ("trunk", "planks", None, 1),
    "hay": ("hay", "thatch", None, 1), "turf": ("turf", "leaf", None, 0), "turf_s": ("turf", "leaf", None, 1),
    "roof": ("grey", "tiles", 0, 0),          # R: roof tiles (recoloured)
    "roof_s": ("grey", "tiles", 0, 0),        # roof cones (flat facets)
    "plaster": ("grey", "plaster", 1, 0),     # G: wall plaster / limewash
    "cloth": ("grey", "stripes", 0, 0),       # R: awning / banner
    "trim": ("grey", "noise", 2, 0),          # B: accent
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    r = sc.render
    r.engine = "BLENDER_EEVEE"
    r.film_transparent = True
    r.filter_size = 1.0
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    r.image_settings.color_depth = "16"
    r.image_settings.compression = 15
    sc.display_settings.display_device = "sRGB"
    try:
        sc.view_settings.view_transform = "Raw"
    except TypeError:
        sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.eevee.taa_render_samples = 16
    return sc


# ------------------------------------------------------------------ materials
def N(nt, kind, **kw):
    n = nt.nodes.new(kind)
    for k, v in kw.items():
        setattr(n, k, v)
    return n


def newmat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    return m, nt


def _in(n, name):
    for s in n.inputs:
        if s.name == name or s.identifier == name:
            return s
    raise KeyError(name)


def albedo_material(key):
    colk, pat, mch, _ = MATS[key]
    base = COL[colk]
    m, nt = newmat("alb_" + key)
    L = nt.links
    pos = N(nt, "ShaderNodeNewGeometry")
    sep = N(nt, "ShaderNodeSeparateXYZ")
    L.new(pos.outputs["Position"], sep.inputs[0])
    # fine and broad noise for painterly variation
    nz = N(nt, "ShaderNodeTexNoise", noise_dimensions="3D")
    _in(nz, "Scale").default_value = 1.3
    _in(nz, "Detail").default_value = 3.0
    L.new(pos.outputs["Position"], _in(nz, "Vector"))
    nz2 = N(nt, "ShaderNodeTexNoise", noise_dimensions="3D")
    _in(nz2, "Scale").default_value = 7.0
    _in(nz2, "Detail").default_value = 2.0
    L.new(pos.outputs["Position"], _in(nz2, "Vector"))
    col = N(nt, "ShaderNodeMix", data_type="RGBA", blend_type="MIX")
    _in(col, "Factor").default_value = 1.0
    detail = nz.outputs["Fac"]
    shade = N(nt, "ShaderNodeMapRange")
    L.new(detail, _in(shade, "Value"))
    _in(shade, "From Min").default_value = 0.3
    _in(shade, "From Max").default_value = 0.7
    _in(shade, "To Min").default_value = 0.84
    _in(shade, "To Max").default_value = 1.12
    mul = N(nt, "ShaderNodeVectorMath", operation="SCALE")
    cc = (base[0], base[1], base[2])
    mul.inputs[0].default_value = cc
    L.new(shade.outputs[0], mul.inputs[3])
    out_col = mul.outputs[0]
    pm = None
    if pat in ("blocks", "cobble", "tiles", "planks", "thatch"):
        br = N(nt, "ShaderNodeTexBrick")
        L.new(pos.outputs["Position"], _in(br, "Vector"))
        _in(br, "Color1").default_value = (1.0, 1.0, 1.0, 1)
        _in(br, "Color2").default_value = (0.86, 0.86, 0.86, 1)
        _in(br, "Mortar").default_value = (0.55, 0.55, 0.55, 1)
        if pat == "blocks":
            sc_, mw, bw, rh = 1.0, 0.04, 1.2, 0.55
            br.offset = 0.5
        elif pat == "cobble":
            sc_, mw, bw, rh = 1.0, 0.07, 0.6, 0.5
            br.offset = 0.5
        elif pat == "tiles":
            sc_, mw, bw, rh = 1.0, 0.025, 0.45, 0.55
            br.offset = 0.5
        elif pat == "planks":
            sc_, mw, bw, rh = 1.0, 0.03, 5.0, 0.45
            br.offset = 0.3
        else:
            sc_, mw, bw, rh = 1.0, 0.0, 0.3, 0.3
            br.offset = 0.5
        _in(br, "Scale").default_value = sc_
        _in(br, "Mortar Size").default_value = mw
        _in(br, "Brick Width").default_value = bw
        _in(br, "Row Height").default_value = rh
        _in(br, "Mortar Smooth").default_value = 0.25
        pm = br
        mul2 = N(nt, "ShaderNodeVectorMath", operation="MULTIPLY")
        L.new(out_col, mul2.inputs[0])
        L.new(br.outputs["Color"], mul2.inputs[1])
        out_col = mul2.outputs[0]
    elif pat in ("leaf", "rock"):
        sc2 = 3.0 if pat == "leaf" else 2.2
        n3 = N(nt, "ShaderNodeTexNoise", noise_dimensions="3D")
        _in(n3, "Scale").default_value = 4.5 if pat == "leaf" else 2.0
        _in(n3, "Detail").default_value = 4.0
        L.new(pos.outputs["Position"], _in(n3, "Vector"))
        mr = N(nt, "ShaderNodeMapRange")
        L.new(n3.outputs["Fac"], _in(mr, "Value"))
        _in(mr, "From Min").default_value = 0.25
        _in(mr, "From Max").default_value = 0.75
        _in(mr, "To Min").default_value = 0.72 if pat == "leaf" else 0.8
        _in(mr, "To Max").default_value = 1.22 if pat == "leaf" else 1.15
        mul2 = N(nt, "ShaderNodeVectorMath", operation="SCALE")
        L.new(out_col, mul2.inputs[0])
        L.new(mr.outputs[0], mul2.inputs[3])
        out_col = mul2.outputs[0]
        if pat == "rock":   # strata: stretched wave, darker cracks
            wv = N(nt, "ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
            _in(wv, "Scale").default_value = 2.6
            _in(wv, "Distortion").default_value = 6.0
            _in(wv, "Detail").default_value = 2.0
            L.new(pos.outputs["Position"], _in(wv, "Vector"))
            mr2 = N(nt, "ShaderNodeMapRange")
            L.new(wv.outputs["Fac"], _in(mr2, "Value"))
            _in(mr2, "To Min").default_value = 0.58
            _in(mr2, "To Max").default_value = 1.0
            mul3 = N(nt, "ShaderNodeVectorMath", operation="SCALE")
            L.new(out_col, mul3.inputs[0])
            L.new(mr2.outputs[0], mul3.inputs[3])
            out_col = mul3.outputs[0]
    elif pat == "stripes":
        wv = N(nt, "ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
        _in(wv, "Scale").default_value = 1.1
        _in(wv, "Distortion").default_value = 0.0
        L.new(pos.outputs["Position"], _in(wv, "Vector"))
        cr = N(nt, "ShaderNodeValToRGB")
        cr.color_ramp.interpolation = "CONSTANT"
        cr.color_ramp.elements[0].position = 0.0
        cr.color_ramp.elements[0].color = (0.55, 0.55, 0.55, 1)
        cr.color_ramp.elements[1].position = 0.5
        cr.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1)
        L.new(wv.outputs["Fac"], cr.inputs[0])
        mul2 = N(nt, "ShaderNodeVectorMath", operation="MULTIPLY")
        L.new(out_col, mul2.inputs[0])
        L.new(cr.outputs[0], mul2.inputs[1])
        out_col = mul2.outputs[0]
    # fine speckle
    fn = N(nt, "ShaderNodeVectorMath", operation="SCALE")
    mr3 = N(nt, "ShaderNodeMapRange")
    L.new(nz2.outputs["Fac"], _in(mr3, "Value"))
    _in(mr3, "From Min").default_value = 0.3
    _in(mr3, "From Max").default_value = 0.7
    _in(mr3, "To Min").default_value = 0.93
    _in(mr3, "To Max").default_value = 1.07
    L.new(out_col, fn.inputs[0])
    L.new(mr3.outputs[0], fn.inputs[3])
    em = N(nt, "ShaderNodeEmission")
    L.new(fn.outputs[0], em.inputs["Color"])
    o = N(nt, "ShaderNodeOutputMaterial")
    L.new(em.outputs[0], o.inputs["Surface"])
    return m


def pass_material(kind):
    m, nt = newmat("pass_" + kind)
    L = nt.links
    em = N(nt, "ShaderNodeEmission")
    if kind == "normal":
        g = N(nt, "ShaderNodeNewGeometry")
        v = N(nt, "ShaderNodeVectorMath", operation="MULTIPLY_ADD")
        L.new(g.outputs["Normal"], v.inputs[0])
        v.inputs[1].default_value = (0.5, 0.5, 0.5)
        v.inputs[2].default_value = (0.5, 0.5, 0.5)
        L.new(v.outputs[0], em.inputs["Color"])
    elif kind == "height":
        g = N(nt, "ShaderNodeNewGeometry")
        s = N(nt, "ShaderNodeSeparateXYZ")
        L.new(g.outputs["Position"], s.inputs[0])
        d = N(nt, "ShaderNodeMath", operation="DIVIDE")
        L.new(s.outputs["Z"], d.inputs[0])
        d.inputs[1].default_value = ZMAX
        c = N(nt, "ShaderNodeCombineColor")
        for ch in ("Red", "Green", "Blue"):
            L.new(d.outputs[0], c.inputs[ch])
        L.new(c.outputs["Color"], em.inputs["Color"])
    else:   # mask
        at = N(nt, "ShaderNodeAttribute", attribute_type="OBJECT", attribute_name="bk_mask")
        L.new(at.outputs["Color"], em.inputs["Color"])
    o = N(nt, "ShaderNodeOutputMaterial")
    L.new(em.outputs[0], o.inputs["Surface"])
    return m


# ------------------------------------------------------------------ geometry
class Piece:
    def __init__(self):
        self.bms = {}

    def bm(self, key):
        if key not in self.bms:
            self.bms[key] = bmesh.new()
        return self.bms[key]

    def mesh(self, key, verts, faces):
        bm = self.bm(key)
        vs = [bm.verts.new(v) for v in verts]
        for f in faces:
            try:
                bm.faces.new([vs[i] for i in f])
            except ValueError:
                pass

    def box(self, key, cx, cy, z0, sx, sy, h, rot=0.0):
        c, s = math.cos(rot), math.sin(rot)
        hx, hy = sx / 2, sy / 2
        pts = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
        pts = [(cx + x * c - y * s, cy + x * s + y * c) for x, y in pts]
        self.prism(key, pts, z0, z0 + h)

    def prism(self, key, pts, z0, z1, sc1=1.0, centre=None):
        n = len(pts)
        cx, cy = centre or (sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n)
        top = [(cx + (x - cx) * sc1, cy + (y - cy) * sc1) for x, y in pts]
        v = [(x, y, z0) for x, y in pts] + [(x, y, z1) for x, y in top]
        f = [list(range(n - 1, -1, -1)), list(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            f.append([i, j, n + j, n + i])
        self.mesh(key, v, f)
        # orientation fixed below by recalc normals

    def seg(self, key, p0, p1, w, z0, h, ext=0.0):
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        L = math.hypot(dx, dy)
        a = math.atan2(dy, dx)
        self.box(key, (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, z0, L + ext, w, h, a)

    def cyl(self, key, cx, cy, z0, r, h, n=16, r2=None, rot=0.0, axis="z"):
        r2 = r if r2 is None else r2
        v = []
        for i in range(n):
            a = rot + 2 * math.pi * i / n
            v.append((r * math.cos(a), r * math.sin(a), 0))
        for i in range(n):
            a = rot + 2 * math.pi * i / n
            v.append((r2 * math.cos(a), r2 * math.sin(a), h))
        f = [list(range(n - 1, -1, -1)), list(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            f.append([i, j, n + j, n + i])
        if axis == "x":
            v = [(z, y, x) for x, y, z in v]
        elif axis == "y":
            v = [(x, z, y) for x, y, z in v]
        v = [(cx + x, cy + y, z0 + z) for x, y, z in v]
        self.mesh(key, v, f)

    def star_cone(self, key, cx, cy, z0, r, h, n=12, inner=0.55, rot=0.0, tip=0.12):
        """spiky conifer tier: alternating outer / inner ring, tapering to a tip."""
        v = []
        for i in range(2 * n):
            a = rot + math.pi * i / n
            rr = r if i % 2 == 0 else r * inner
            v.append((cx + rr * math.cos(a), cy + rr * math.sin(a), z0))
        top = len(v)
        v.append((cx, cy, z0 + h))
        f = [list(range(2 * n - 1, -1, -1))]
        for i in range(2 * n):
            f.append([i, (i + 1) % (2 * n), top])
        self.mesh(key, v, f)

    def gable(self, key, cx, cy, z0, sx, sy, h, over=0.5, hip=0.0, rot=0.0, ridge_axis="x"):
        """Roof over a sx x sy footprint; ridge along x (or y); hip 0 = gable,
        1 = full hip (pyramid when square)."""
        ex, ey = sx / 2 + over, sy / 2 + over
        if ridge_axis == "y":
            ex, ey = ey, ex
        # ridge half-length
        rl = max(0.0, (ex if ridge_axis == "x" else ey) - hip * (ey if ridge_axis == "x" else ex))
        if ridge_axis == "x":
            r0, r1 = (-rl, 0, h), (rl, 0, h)
        else:
            r0, r1 = (0, -rl, h), (0, rl, h)
        c = [(-ex, -ey, 0), (ex, -ey, 0), (ex, ey, 0), (-ex, ey, 0)]
        v = c + [r0, r1]
        if ridge_axis == "x":
            f = [[0, 1, 5, 4], [2, 3, 4, 5], [3, 0, 4], [1, 2, 5]]
        else:
            f = [[1, 2, 5, 4], [3, 0, 4, 5], [0, 1, 4], [2, 3, 5]]
        if rl <= 1e-6:
            v = c + [(0, 0, h)]
            f = [[0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]]
        co, si = math.cos(rot), math.sin(rot)
        v = [(cx + x * co - y * si, cy + x * si + y * co, z0 + z) for x, y, z in v]
        self.mesh(key, v, f)
        # soffit so the underside is closed
        if rl > 1e-6 or True:
            self.mesh(key, [(v[i][0], v[i][1], z0) for i in (3, 2, 1, 0)], [[0, 1, 2, 3]])

    def lump(self, key, cx, cy, cz, rx, ry, rz, amp=0.2, seed=0, sub=3, scale=1.0):
        bm = self.bm(key)
        r = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        vs = r["verts"]
        for v in vs:
            d = v.co.copy()
            nz = noise.noise(Vector((d.x * scale + seed * 13.1, d.y * scale + seed * 7.7, d.z * scale + seed * 3.3))) \
                + 0.5 * noise.noise(Vector((d.x * 2.3 * scale + seed, d.y * 2.3 * scale, d.z * 2.3 * scale)))
            k = 1.0 + amp * nz
            v.co = Vector((cx + d.x * rx * k, cy + d.y * ry * k, cz + d.z * rz * k))

    def finish(self, sc):
        objs = []
        for key, bm in self.bms.items():
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            me = bpy.data.meshes.new(key)
            bm.to_mesh(me)
            bm.free()
            smooth = MATS[key][3]
            for p in me.polygons:
                p.use_smooth = bool(smooth)
            me.materials.append(albedo_material(key))
            ob = bpy.data.objects.new(key, me)
            sc.collection.objects.link(ob)
            mc = MATS[key][2]
            mk = [0, 0, 0]
            if mc is not None:
                mk[mc] = 1
            ob["bk_mask"] = mk + [1.0]
            ob["bk_key"] = key
            objs.append(ob)
        return objs


def rng(seed):
    return random.Random(seed)


# ------------------------------------------------------------------ pieces
def merlons(P, key, p0, p1, z, h, w, step=1.9, size=1.1, off=0.0):
    """crenellations along a segment, offset sideways by off."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    nx, ny = -uy, ux
    n = max(1, int(L / step))
    for i in range(n):
        t = (i + 0.5) * L / n
        cx = p0[0] + ux * t + nx * off
        cy = p0[1] + uy * t + ny * off
        P.box(key, cx, cy, z, size, w, h, math.atan2(dy, dx))


def b_wall(P, L, t=3.2, h=5.0):
    P.box("stone", 0, 0, 0, L, t, h)                     # body
    P.box("stone_l", 0, 0, h, L, t - 1.4, 0.25)          # walkway
    merlons(P, "stone", (-L / 2, 0), (L / 2, 0), h, 1.2, 0.9, 1.9, 1.1, t / 2 - 0.45)
    P.box("stone", 0, -t / 2 + 0.3, h, L, 0.6, 0.55)     # inner low parapet
    P.box("stone_d", 0, 0, -0.01, L, t + 0.9, 0.9)       # plinth / batter


def b_tower_round(P, roof=False):
    P.cyl("stone", 0, 0, 0, 5.6, 10.0, 20, r2=5.2)
    P.cyl("stone_d", 0, 0, 0, 6.4, 1.6, 20, r2=5.9)
    P.cyl("stone_l", 0, 0, 10.0, 5.6, 0.4, 20)
    if roof:
        P.cyl("roof_s", 0, 0, 10.0, 6.6, 7.5, 10, r2=0.15)
        P.cyl("trim", 0, 0, 17.4, 0.25, 1.6, 6, r2=0.05)
    else:
        n = 14
        for i in range(n):
            a = 2 * math.pi * (i + 0.5) / n
            P.box("stone", 5.0 * math.cos(a), 5.0 * math.sin(a), 10.4, 1.7, 1.0, 1.3, a)
        P.cyl("stone_d", 0, 0, 10.4, 2.0, 0.5, 12)
        P.cyl("timber", 0, 0, 10.8, 1.1, 0.3, 10)


def b_tower_sq(P, roof=False):
    P.box("stone_d", 0, 0, 0, 12.2, 12.2, 1.5)
    P.box("stone", 0, 0, 0, 10.6, 10.6, 9.5)
    P.box("stone_l", 0, 0, 9.5, 10.6, 10.6, 0.4)
    if roof:
        P.gable("roof", 0, 0, 9.9, 9.8, 9.8, 7.0, over=0.7, hip=1.0)
    else:
        h = 5.3
        for a, b in (((-h, -h), (h, -h)), ((h, -h), (h, h)), ((h, h), (-h, h)), ((-h, h), (-h, -h))):
            merlons(P, "stone", a, b, 9.9, 1.3, 1.0, 2.0, 1.3, -0.45)
        P.box("stone_d", 0, 0, 9.9, 4.2, 4.2, 0.5)


def b_corner(P):
    """L-shaped 90 degree wall corner with a buttress, arms along +x and -y."""
    t, h, L = 3.2, 5.0, 6.0
    P.box("stone", L / 2 - t / 2, 0, 0, L + t, t, h)
    P.box("stone", 0, -L / 2 + t / 2, 0, t, L + t, h)
    P.box("stone_l", L / 2 - t / 2, 0, h, L + t, t - 1.4, 0.25)
    P.box("stone_l", 0, -L / 2 + t / 2, h, t - 1.4, L + t, 0.25)
    merlons(P, "stone", (-t / 2, t / 2 - 0.45), (L, t / 2 - 0.45), h, 1.2, 0.9)
    merlons(P, "stone", (-t / 2 + 0.45, t / 2), (-t / 2 + 0.45, -L), h, 1.2, 0.9)
    P.box("stone_d", 0.4, -0.4, h - 0.2, 4.8, 4.8, 0.6)
    P.cyl("stone_d", 0, 0, 0, 3.2, 1.0, 12)


def b_gatehouse(P, openg=False):
    W, D = 20.0, 8.0     # along x, depth y
    for sx in (-1, 1):
        P.box("stone_d", sx * 6.9, 0, 0, 7.6, D + 1.4, 1.5)
        P.box("stone", sx * 6.9, 0, 0, 6.4, D, 9.5)
        P.box("stone_l", sx * 6.9, 0, 9.5, 6.4, D, 0.4)
        for a, b in (((-3.2, -4), (3.2, -4)), ((-3.2, 4), (3.2, 4))):
            merlons(P, "stone", (a[0] + sx * 6.9, a[1]), (b[0] + sx * 6.9, b[1]), 9.9, 1.2, 0.9, 1.7, 1.0, 0)
        P.gable("roof", sx * 6.9, 0, 9.9, 3.6, 3.6, 3.2, over=0.8, hip=1.0)
    # arch deck behind (south, -y side) and lintel
    P.box("stone", 0, -2.8, 0, 7.4, 2.4, 6.5)
    P.box("stone_l", 0, -2.8, 6.5, 7.4, 2.4, 0.3)
    P.box("stone", 0, 3.4, 0, 7.4, 1.2, 7.0)
    P.box("stone_l", 0, 3.4, 7.0, 7.4, 1.2, 0.3)
    merlons(P, "stone", (-3.7, 3.4), (3.7, 3.4), 7.3, 1.1, 0.9, 1.7, 1.0, 0)
    P.box("cobble", 0, 0, 0.02, 3.8, 9.0, 0.1)        # road through
    P.box("stone_d", -2.0, -0.6, 0.02, 0.01, 0.01, 0.01)
    if openg:     # leaves swung outward (north)
        for sx in (-1, 1):
            P.seg("timber", (sx * 1.9, 4.2), (sx * 1.9, 8.8), 0.35, 0.0, 3.3)
            P.seg("metal", (sx * 1.9, 5.0), (sx * 1.9, 8.8), 0.4, 1.0, 0.25)
    else:
        for sx in (-1, 1):
            P.box("timber", sx * 0.95, 3.4, 0, 1.9, 0.5, 4.8)
            P.box("metal", sx * 0.95, 3.4, 1.0, 1.9, 0.6, 0.25)
        P.box("metal", 0, 3.4, 0, 0.1, 0.65, 4.8)
    P.box("cloth", 0, -4.9, 6.8, 0.12, 0.12, 0.12)


def b_palisade(P, L):
    n = int(L / 0.85)
    r = rng(5)
    for i in range(n):
        x = -L / 2 + (i + 0.5) * L / n
        for row, y in enumerate((-0.28, 0.28)):
            xx = x + (0.42 if row else 0)
            if abs(xx) > L / 2:
                continue
            h = 4.0 + r.uniform(-0.35, 0.35)
            P.cyl("timber", xx, y, 0, 0.42, h, 8, r2=0.3)
            P.cyl("timber", xx, y, h, 0.3, 0.9, 8, r2=0.04)
    P.box("timber_d", 0, 0, 2.6, L, 0.3, 0.25)
    P.box("earth", 0, 0, -0.01, L, 1.8, 0.35)


def b_palisade_gate(P):
    b_palisade(P, 6.0)
    for sx in (-1, 1):
        P.cyl("timber_d", sx * 3.3, 0, 0, 0.55, 6.2, 10, r2=0.5)
        P.cyl("timber_d", sx * 3.3, 0, 6.2, 0.55, 0.6, 10, r2=0.05)
    P.box("timber_d", 0, 0, 5.2, 7.0, 0.5, 0.45)
    P.box("earth", 0, 0, 0.0, 5.0, 1.6, 0.1)


def b_bastion(P):
    pts = [(-9, -10), (-9, 0.5), (0, 13), (9, 0.5), (9, -10)]
    P.prism("turf", pts, 0, 5.0, 0.86, centre=(0, -2))
    top = [(0 + (x - 0) * 0.86, -2 + (y + 2) * 0.86) for x, y in pts]
    P.prism("stone", pts, 0, 2.6, 0.97, centre=(0, -2))      # masonry scarp
    P.prism("stone_l", pts, 0, 0.5, 1.04, centre=(0, -2))
    cx = [(x * 0.86, -2 + (y + 2) * 0.86) for x, y in pts]
    for i in range(len(cx) - 1):
        P.seg("turf", cx[i], cx[i + 1], 1.5, 5.0, 1.0, ext=1.5)
    # sentry box (garita) at the tip
    tip = cx[2]
    P.cyl("stone_l", tip[0], tip[1] - 0.8, 6.0, 1.15, 1.8, 10)
    P.cyl("roof_s", tip[0], tip[1] - 0.8, 7.8, 1.5, 1.6, 10, r2=0.1)
    # cannon embrasure blocks / gun platform
    P.box("timber", 0, 2.0, 5.0, 6.0, 5.0, 0.15, 0.0)
    for sx in (-1, 1):
        P.seg("metal", (sx * 3.0, 3.0), (sx * 3.4, 4.8), 0.5, 5.2, 0.5)


def house(P, sx, sy, wh=3.2, rh=3.0, hip=0.0, thatch=False, over=0.5, chim=True, rot=0.0):
    P.box("plaster", 0, 0, 0, sx, sy, wh)
    P.gable("thatch" if thatch else "roof", 0, 0, wh, sx, sy, rh, over=over, hip=hip,
            ridge_axis="x" if sx >= sy else "y")
    if chim:
        px = sx * 0.28 if sx >= sy else 0
        py = 0 if sx >= sy else sy * 0.28
        P.box("stone_d", px, py + (0.6 if sx < sy else 0), wh + rh * 0.35, 0.9, 0.9, rh * 0.9 + 0.4)


def b_house(P, kind):
    spec = {
        "house_gable_s": (6, 8, 3.0, 2.8, 0.0), "house_gable_m": (7, 10, 3.3, 3.2, 0.0),
        "house_gable_l": (8, 13, 3.6, 3.6, 0.0), "house_hip_s": (7, 7, 3.0, 3.2, 1.0),
        "house_hip_m": (9, 9, 3.4, 3.8, 1.0), "longhouse": (6, 16, 3.0, 2.8, 0.45),
    }
    if kind in spec:
        sx, sy, wh, rh, hip = spec[kind]
        house(P, sx, sy, wh, rh, hip)
    elif kind == "house_L":
        P.box("plaster", 0, -1.5, 0, 12, 6, 3.2)
        P.box("plaster", 3.0, 3.5, 0, 6, 8, 3.2)
        P.gable("roof", 0, -1.5, 3.2, 12, 6, 3.0, over=0.5, ridge_axis="x")
        P.gable("roof", 3.0, 4.0, 3.2, 6, 9.0, 3.0, over=0.5, ridge_axis="y")
        P.box("stone_d", -3, -1.5, 5.0, 0.9, 0.9, 2.2)
    elif kind == "hut_round":
        P.cyl("plaster", 0, 0, 0, 2.8, 2.2, 14)
        P.cyl("thatch", 0, 0, 2.2, 3.5, 3.4, 14, r2=0.1)
    elif kind == "hut_thatch":
        house(P, 5, 7, 2.6, 2.6, 0.0, thatch=True, over=0.7, chim=False)


def b_church(P):
    P.box("plaster", 0, 0, 0, 20, 8.5, 5.0)
    P.gable("roof", 0, 0, 5.0, 20, 8.5, 4.4, over=0.6)
    P.cyl("plaster", 11.2, 0, 0, 4.2, 4.2, 10, rot=0.1)
    P.cyl("roof_s", 11.2, 0, 4.2, 4.6, 3.4, 10, r2=0.2)
    for sx, sy in ((-1, 0),):
        P.box("plaster", -12.2, 0, 0, 6.2, 6.2, 12.0)
        P.box("stone_l", -12.2, 0, 12.0, 6.6, 6.6, 0.4)
        P.gable("roof", -12.2, 0, 12.4, 5.6, 5.6, 6.5, over=0.6, hip=1.0)
        P.box("trim", -12.2, 0, 18.4, 0.5, 0.5, 1.6)
    P.box("stone_d", 0, -4.6, 0, 6, 1.2, 2.2)
    P.box("stone_d", 0, 4.6, 0, 6, 1.2, 2.2)


def b_temple(P):
    P.box("stone_l", 0, 0, 0, 23, 15, 0.8)
    P.box("stone_l", 0, 0, 0.8, 21.4, 13.4, 0.8)
    P.box("stone_l", 0, 0, 1.6, 20, 12, 0.8)
    P.box("plaster", 0, 0, 2.4, 14, 8, 7.0)           # cella
    for i in range(9):
        for sy in (-1, 1):
            P.cyl("stone_l", -9 + i * 2.25, sy * 5.0, 2.4, 0.55, 7.4, 12)
    for sx in (-1, 1):
        for sy in (-1, 1):
            pass
    for i in range(1, 5):
        for sx in (-1, 1):
            P.cyl("stone_l", sx * 9.0, -5.0 + i * 2.0, 2.4, 0.55, 7.4, 12)
    P.box("stone", 0, 0, 9.8, 21, 12.2, 0.9)
    P.gable("roof", 0, 0, 10.7, 20.4, 11.0, 3.0, over=0.4)
    P.box("trim", 0, 0, 13.7, 20.4, 0.5, 0.25)


def b_stall(P):
    P.box("timber", 0, 0, 0, 2.6, 1.4, 0.9)
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.cyl("timber_d", sx * 1.7, sy * 1.5, 0, 0.12, 2.6, 6)
    P.mesh("cloth", [(-2.3, -1.9, 2.3), (2.3, -1.9, 2.3), (2.3, 0.0, 3.1), (-2.3, 0.0, 3.1),
                     (-2.3, 1.9, 2.3), (2.3, 1.9, 2.3)], [[0, 1, 2, 3], [3, 2, 5, 4]])
    P.mesh("cloth", [(-2.3, -1.9, 2.3), (-2.3, 1.9, 2.3), (-2.3, 0, 3.1)], [[0, 2, 1]]) if False else None
    P.box("timber", 2.5, 2.4, 0, 1.0, 0.9, 0.9)
    P.lump("hay", -2.6, -2.6, 0.5, 0.7, 0.7, 0.55, 0.15, 3, 2)


def b_well(P):
    P.cyl("stone", 0, 0, 0, 1.6, 1.1, 14)
    P.cyl("water", 0, 0, 0.5, 1.15, 0.2, 14)
    for sx in (-1, 1):
        P.cyl("timber_d", sx * 1.5, 0, 0, 0.14, 3.3, 6)
    P.gable("roof", 0, 0, 3.0, 3.4, 1.8, 1.0, over=0.2, ridge_axis="y")


def b_cart(P):
    P.box("timber", 0, 0, 0.7, 2.2, 4.2, 0.35)
    for sx in (-1, 1):
        P.box("timber_d", sx * 1.05, 0, 0.9, 0.18, 4.2, 0.8)
        P.cyl("timber_d", sx * 1.25, 1.2, 0.65, 0.65, 0.2, 12, axis="x")
        P.cyl("timber_d", sx * 1.25, -1.2, 0.65, 0.65, 0.2, 12, axis="x")
    P.box("timber_d", 0, -0.0, 0.95, 2.2, 0.18, 0.7)
    P.lump("hay", 0, 0.1, 1.3, 1.0, 1.7, 0.7, 0.1, 5, 2)
    P.seg("timber_d", (0, 2.1), (0, 5.2), 0.2, 0.9, 0.15)


def b_fence(P, L=8.0):
    n = int(L / 2.0)
    for i in range(n + 1):
        x = -L / 2 + i * L / n
        P.box("timber_d", x, 0, 0, 0.26, 0.26, 1.3)
    P.box("timber", 0, 0, 0.45, L, 0.12, 0.14)
    P.box("timber", 0, 0, 0.95, L, 0.12, 0.14)


def b_barrels(P):
    for x, y in ((0, 0), (1.15, 0.2), (0.5, 1.1)):
        P.cyl("timber", x, y, 0, 0.5, 0.95, 10, r2=0.42)
        P.cyl("metal", x, y, 0.2, 0.52, 0.1, 10)
        P.cyl("metal", x, y, 0.65, 0.52, 0.1, 10)
        P.cyl("timber_d", x, y, 0.95, 0.4, 0.04, 10)
    P.box("timber", -1.3, 1.0, 0, 0.9, 0.9, 0.9, 0.3)


def b_broadleaf(P, v):
    r = rng(100 + v)
    R = (3.6, 4.3, 5.0)[v]
    key = ("leaf_a", "leaf_b", "leaf_c")[v]
    P.cyl("trunk", 0.3, -0.2, 0, 0.45, 5.0, 8)
    lumps = []
    for i in range(7 + v * 2):
        a = r.uniform(0, 6.28)
        d = r.uniform(0.15, 0.62) * R
        lumps.append((d * math.cos(a), d * math.sin(a), r.uniform(5.4, 8.0), r.uniform(0.55, 0.78) * R))
    for i, (x, y, z, rr) in enumerate(lumps):
        P.lump(key, x, y, z, rr, rr, rr * 0.85, 0.28, 7 * i + v, 3, 0.9)
    P.lump("leaf_c" if v != 2 else "leaf_a", 0, 0, 8.6, R * 0.55, R * 0.55, R * 0.5, 0.25, v + 40, 3, 0.9)


def b_pine(P, v):
    r = rng(300 + v)
    P.cyl("trunk", 0, 0, 0, 0.4, 3.0, 8)
    n = 5 + v
    for i in range(n):
        f = i / (n - 1)
        rad = (3.3 - 2.6 * f) * (1.0 + 0.1 * v)
        z0 = 1.8 + i * 1.5
        P.star_cone("pine", 0, 0, z0, rad, 2.6, 9 + v, 0.5, r.uniform(0, 1))


def frond(P, ang, L, off, droop, w0, key="palm"):
    n = 6
    prev = (0.0, 0.0, 0.0)
    for i in range(1, n + 1):
        f = i / n
        d = L * f
        z = L * 0.35 * math.sin(f * 1.4) - droop * f * f * L
        cur = (d * math.cos(ang), d * math.sin(ang), z)
        w = w0 * (1.0 - 0.8 * f) + 0.15
        px, py = -math.sin(ang) * w, math.cos(ang) * w
        v = [(prev[0] - px * 0.9, prev[1] - py * 0.9, prev[2]), (prev[0] + px * 0.9, prev[1] + py * 0.9, prev[2]),
             (cur[0] + px, cur[1] + py, cur[2] - 0.15), (cur[0] - px, cur[1] - py, cur[2] - 0.15)]
        v = [(a + off[0], b + off[1], c + off[2]) for a, b, c in v]
        P.mesh(key, v, [[0, 1, 2, 3]])
        prev = cur


def b_palm(P, v):
    r = rng(500 + v)
    lean = (0.8 + 0.4 * v, -0.5)
    h = 7.0 + v * 0.8
    prev = (0, 0, 0)
    for i in range(1, 7):
        f = i / 6
        cur = (lean[0] * f * f * 2, lean[1] * f * f * 2, h * f)
        P.seg("trunk", (prev[0], prev[1]), (cur[0], cur[1]), 0.5 - 0.15 * f, prev[2], cur[2] - prev[2] + 0.2)
        prev = cur
    top = (lean[0] * 2, lean[1] * 2)
    nf = 10
    for i in range(nf):
        ang = 2 * math.pi * i / nf + r.uniform(-0.2, 0.2)
        L = 5.2 + r.uniform(-0.5, 0.8)
        frond(P, ang, L, (top[0], top[1], h), r.uniform(0.5, 1.1), 1.3)
    for i in range(3):
        P.lump("trunk", top[0] + 0.5 * math.cos(i * 2.1), top[1] + 0.5 * math.sin(i * 2.1), h - 0.4, 0.35, 0.35, 0.35, 0.05, i, 1)


def b_bush(P, v):
    r = rng(700 + v)
    for i in range(4):
        P.lump(("leaf_b", "leaf_a")[v % 2], r.uniform(-1, 1), r.uniform(-1, 1), 0.8, 1.3, 1.3, 1.0, 0.3, i + v * 9, 3, 1.0)


def b_rock(P, v):
    r = rng(900 + v)
    R = (2.6, 3.4, 4.4)[v]
    for i in range(3 + v):
        a = r.uniform(0, 6.28)
        d = r.uniform(0.0, 0.5) * R
        rr = R * r.uniform(0.45, 0.8)
        P.lump(("rock", "rock_d")[i % 2 if v == 1 else 0], d * math.cos(a), d * math.sin(a), rr * 0.25,
               rr, rr * r.uniform(0.7, 1.1), rr * r.uniform(0.55, 0.85), 0.42, 11 * i + v, 3, 1.1)


def b_cliff(P, L):
    """Cliff face along x: lip on the plateau side (north, +y, high), the face
    falling to the south, then talus. The plateau itself is the terrain; only a
    4 m turf-capped lip is part of the piece."""
    H = 4.4
    nx, ny = int(L / 0.5) + 1, 34
    y0, y1 = -6.5, 5.0

    def zfun(x, y):
        wob = noise.noise(Vector((x * 0.16, 3.7, 0))) * 1.1 + 0.4 * noise.noise(Vector((x * 0.55, 9.1, 0)))
        u = y - wob
        col = noise.noise(Vector((x * 0.8, 1.3, 0)))
        if u >= 0:
            z = H * (1.0 - min(1.0, u / 4.2) ** 1.5) + 0.05
        else:
            f = min(1.0, -u / 1.9)
            z = H * (1.0 - f ** 0.75) + 0.5 * col * f * (1 - f) * 4
            if -u > 1.9:
                z = max(0.0, 0.8 * math.exp(-(-u - 1.9) / 1.4) * (0.55 + 0.7 * noise.noise(Vector((x * 0.5, y * 0.5, 2)))) - 0.12)
        z += 0.16 * noise.noise(Vector((x * 1.3, y * 1.3, 5))) * (1 if z > 0.2 else 0)
        e = min(1.0, (L / 2 - abs(x)) / 3.5)
        return max(z * max(0.0, e) ** 0.7, 0.0), u

    grid = {}
    for j in range(ny):
        for i in range(nx):
            x = -L / 2 + i * L / (nx - 1)
            y = y0 + j * (y1 - y0) / (ny - 1)
            grid[(i, j)] = (x, y) + zfun(x, y)
    for key in ("rock", "turf_s"):
        bm = P.bm(key)
        vs = {}
        for (i, j), (x, y, z, u) in grid.items():
            vs[(i, j)] = bm.verts.new((x, y, z))
        for j in range(ny - 1):
            for i in range(nx - 1):
                uc = sum(grid[(i + di, j + dj)][3] for di in (0, 1) for dj in (0, 1)) / 4
                zc = sum(grid[(i + di, j + dj)][2] for di in (0, 1) for dj in (0, 1)) / 4
                if max(grid[(i + di, j + dj)][2] for di in (0, 1) for dj in (0, 1)) < 0.07:
                    continue
                cap = uc > 0.9 and zc > 0.12
                if (key == "turf_s") != cap:
                    continue
                try:
                    bm.faces.new([vs[(i, j)], vs[(i + 1, j)], vs[(i + 1, j + 1)], vs[(i, j + 1)]])
                except ValueError:
                    pass
    r = rng(int(L))
    for i in range(int(L / 3)):
        x = r.uniform(-L / 2 + 3, L / 2 - 3)
        P.lump("rock_d", x, y0 + r.uniform(1.5, 3.2), 0.3, r.uniform(0.4, 0.9), r.uniform(0.4, 0.9), 0.4, 0.4, i, 2, 1.2)


# ---- walls / towers / gates sized to the game's sim geometry (battle view, phase 1) ----
WALL_VARIANTS = [(8, 2), (10, 2), (12, 2), (12, 4), (14, 4)]   # (thickness, outer parapet) the sim makes
WALK = 4.0                                                    # walkway width (MapGen.WALK_W)


def b_wall_sim(P, t, pp, L=16, h=5.0):
    """Stone curtain wall of thickness t metres (the sim's wall band), outer face +y: parapet pp
    with merlons on the outside, a 4 m walkway inside it, a lower earth-backed rampart behind."""
    wy1 = t / 2 - pp
    wy0 = wy1 - WALK
    P.box("stone_d", 0, 0, -0.01, L, t + 0.9, 0.9)                         # plinth / batter
    P.box("stone", 0, (wy0 + t / 2) / 2, 0, L, t / 2 - wy0, h)              # outer body (walkway + parapet)
    P.box("stone_d", 0, (wy0 - t / 2) / 2, 0, L, wy0 + t / 2, h - 1.1)      # inner rampart, lower
    P.box("stone_l", 0, (wy0 + wy1) / 2, h, L, WALK, 0.25)                 # walkway
    merlons(P, "stone", (-L / 2, 0), (L / 2, 0), h, 1.2, pp * 0.85, 1.9, 1.1, t / 2 - pp / 2)
    P.box("stone", 0, wy0 + 0.3, h, L, 0.6, 0.5)                            # inner low parapet


def b_pal_sim(P, t, L=12):
    """Timber palisade: stakes along the outer edge, a plank fighting walk on an earth bank."""
    r = rng(5 + int(t))
    P.box("earth", 0, 0, -0.01, L, t + 0.8, 0.5)
    P.box("earth", 0, 0, 0, L, t, 2.5)
    P.box("timber", 0, -0.3, 2.5, L, t - 0.6, 0.2)
    for i in range(int(L / 0.9) + 1):
        x = -L / 2 + 0.45 + i * 0.9
        if abs(x) > L / 2:
            continue
        for row, y in enumerate((t / 2 - 0.55, t / 2 - 1.3)):
            xx = x + (0.45 if row else 0.0)
            if abs(xx) > L / 2 - 0.1:
                continue
            h = 3.6 + r.uniform(-0.3, 0.3)
            P.cyl("timber", xx, y, 2.5, 0.42, h, 8, r2=0.32)
            P.cyl("timber", xx, y, 2.5 + h, 0.32, 0.8, 8, r2=0.04)
    P.box("timber_d", 0, t / 2 - 2.0, 2.7, L, 0.25, 0.3)                    # rail behind the stakes
    for i in range(3):
        P.box("timber_d", -L / 2 + (i + 0.5) * L / 3, -t / 2 + 0.3, 2.5, 0.35, 0.35, 0.9)  # inner posts


def b_tower_timber(P, r=6.0):
    """Round log tower: earth and plank platform ringed by pointed logs."""
    rr = rng(11)
    P.cyl("earth", 0, 0, -0.01, r + 0.5, 0.5, 18)
    P.cyl("timber_d", 0, 0, 0, r, 2.8, 18)
    P.cyl("timber", 0, 0, 2.8, r - 0.3, 0.2, 18)
    n = 22
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        h = 4.4 + rr.uniform(-0.3, 0.3)
        P.cyl("timber", (r - 0.6) * math.cos(a), (r - 0.6) * math.sin(a), 2.8, 0.55, h, 8, r2=0.4)
        P.cyl("timber", (r - 0.6) * math.cos(a), (r - 0.6) * math.sin(a), 2.8 + h, 0.4, 0.9, 8, r2=0.05)
    P.cyl("timber_d", 0, 0, 3.0, 1.6, 0.4, 10)


def b_gate_arch(P, state, timber=False, D=11.0, hw=4.0):
    """The passage of a gate (the towers are separate pieces): jambs, an inner deck and an outer
    lintel over the road; state 'c' closed leaves, 'o' leaves swung in, 'b' broken. Outer side +y."""
    stone = "timber_d" if timber else "stone"
    wood = "timber" if timber else "stone_l"
    r = rng(3)
    P.box("cobble" if not timber else "earth", 0, 0, 0.02, 2 * hw + 0.4, D, 0.1)
    if state == "b":
        for sx in (-1, 1):
            for k in range(3):
                P.box(stone, sx * (hw + 0.7), -D / 2 + 1.7 + k * 3.5, 0, 1.4, 3.2, r.uniform(1.2, 3.4))
        for k in range(14):
            P.box(r.choice(["stone", "stone_d", "timber", "timber_d", "stone_l"]), r.uniform(-hw, hw), r.uniform(-D / 2, D / 2),
                  0.05, r.uniform(0.4, 1.3), r.uniform(0.3, 0.9), r.uniform(0.15, 0.5), r.uniform(0, 3))
        P.seg("timber_d", (-3.0, 3.5), (2.5, 1.4), 0.5, 0.4, 0.45)
        return
    jh = 6.0 if timber else 7.0
    for sx in (-1, 1):
        if timber:
            for yy in (-D / 2 + 0.7, D / 2 - 0.7):
                P.cyl("timber_d", sx * (hw + 0.6), yy, 0, 0.65, jh, 10, r2=0.55)
                P.cyl("timber_d", sx * (hw + 0.6), yy, jh, 0.55, 0.7, 10, r2=0.05)
        else:
            P.box("stone", sx * (hw + 0.7), 0, 0, 1.4, D, jh)
            P.box("stone_l", sx * (hw + 0.7), 0, jh, 1.4, D, 0.3)
    P.box(stone, 0, -D / 2 + 1.5, 0, 2 * hw + 0.2, 3.0, jh - 0.5 if not timber else 0.01)
    if timber:
        P.box("timber", 0, -D / 2 + 1.5, jh - 0.7, 2 * hw + 0.2, 3.0, 0.3)
        P.box("timber_d", 0, D / 2 - 0.7, jh - 0.5, 2 * hw + 1.6, 0.6, 0.55)
    else:
        P.box("stone_l", 0, -D / 2 + 1.5, jh - 0.5, 2 * hw + 0.2, 3.0, 0.3)
        P.box("stone", 0, D / 2 - 0.7, 0, 2 * hw + 0.2, 1.4, jh + 0.3)
        merlons(P, "stone", (-hw, D / 2 - 0.7), (hw, D / 2 - 0.7), jh + 0.3, 1.0, 0.9, 1.7, 1.0, 0)
    if state == "c":
        for sx in (-1, 1):
            P.box("timber", sx * hw / 2, D / 2 - 1.6, 0, hw - 0.1, 0.5, 4.6)
            P.box("metal", sx * hw / 2, D / 2 - 1.6, 1.0, hw - 0.1, 0.6, 0.25)
            P.box("metal", sx * hw / 2, D / 2 - 1.6, 3.2, hw - 0.1, 0.6, 0.25)
        P.box("metal", 0, D / 2 - 1.6, 0, 0.12, 0.65, 4.6)
    else:
        for sx in (-1, 1):
            P.seg("timber", (sx * (hw - 0.3), D / 2 - 1.8), (sx * (hw - 0.3), -D / 2 + 3.0), 0.35, 0.0, 3.4)


PIECES = {
    "tower_timber": (14, b_tower_timber), "gate_c": (14, lambda P: b_gate_arch(P, "c")),
    "gate_o": (14, lambda P: b_gate_arch(P, "o")), "gate_b": (14, lambda P: b_gate_arch(P, "b")),
    "pgate_c": (14, lambda P: b_gate_arch(P, "c", True)), "pgate_o": (14, lambda P: b_gate_arch(P, "o", True)),
    "pgate_b": (14, lambda P: b_gate_arch(P, "b", True)),
    "wall_8_2": (24, lambda P: b_wall_sim(P, 8, 2)),
    "wall_10_2": (24, lambda P: b_wall_sim(P, 10, 2)),
    "wall_12_2": (24, lambda P: b_wall_sim(P, 12, 2)),
    "wall_12_4": (24, lambda P: b_wall_sim(P, 12, 4)),
    "wall_14_4": (24, lambda P: b_wall_sim(P, 14, 4)),
    "pal_8": (20, lambda P: b_pal_sim(P, 8)),
    "pal_10": (20, lambda P: b_pal_sim(P, 10)),
    "pal_12": (20, lambda P: b_pal_sim(P, 12)),
    # name: (canvas metres, builder)
    "wall_s": (16, lambda P: b_wall(P, 8)), "wall_m": (24, lambda P: b_wall(P, 16)),
    "wall_l": (32, lambda P: b_wall(P, 24)), "wall_corner": (16, b_corner),
    "tower_round": (16, lambda P: b_tower_round(P, False)),
    "tower_round_roof": (18, lambda P: b_tower_round(P, True)),
    "tower_sq": (16, lambda P: b_tower_sq(P, False)), "tower_sq_roof": (18, lambda P: b_tower_sq(P, True)),
    "gate_closed": (28, lambda P: b_gatehouse(P, False)), "gate_open": (28, lambda P: b_gatehouse(P, True)),
    "palisade_s": (14, lambda P: b_palisade(P, 6)), "palisade_m": (20, lambda P: b_palisade(P, 12)),
    "palisade_gate": (14, b_palisade_gate), "bastion": (36, b_bastion),
    "house_gable_s": (16, lambda P: b_house(P, "house_gable_s")), "house_gable_m": (18, lambda P: b_house(P, "house_gable_m")),
    "house_gable_l": (22, lambda P: b_house(P, "house_gable_l")), "house_hip_s": (16, lambda P: b_house(P, "house_hip_s")),
    "house_hip_m": (18, lambda P: b_house(P, "house_hip_m")), "longhouse": (26, lambda P: b_house(P, "longhouse")),
    "house_L": (22, lambda P: b_house(P, "house_L")), "hut_round": (12, lambda P: b_house(P, "hut_round")),
    "hut_thatch": (16, lambda P: b_house(P, "hut_thatch")),
    "church": (40, b_church), "temple": (30, b_temple), "stall": (10, b_stall), "well": (8, b_well),
    "cart": (14, b_cart), "fence": (14, b_fence), "barrels": (7, b_barrels),
    "tree_broad_a": (16, lambda P: b_broadleaf(P, 0)), "tree_broad_b": (18, lambda P: b_broadleaf(P, 1)),
    "tree_broad_c": (20, lambda P: b_broadleaf(P, 2)), "tree_pine_a": (14, lambda P: b_pine(P, 0)),
    "tree_pine_b": (14, lambda P: b_pine(P, 1)), "tree_palm_a": (20, lambda P: b_palm(P, 0)),
    "tree_palm_b": (20, lambda P: b_palm(P, 1)), "bush_a": (8, lambda P: b_bush(P, 0)),
    "bush_b": (8, lambda P: b_bush(P, 1)),
    "rock_a": (12, lambda P: b_rock(P, 0)), "rock_b": (14, lambda P: b_rock(P, 1)), "rock_c": (16, lambda P: b_rock(P, 2)),
    "cliff_m": (36, lambda P: b_cliff(P, 24)), "cliff_l": (48, lambda P: b_cliff(P, 36)),
}


# ------------------------------------------------------------------ render
def render(name, ppm, tilt, out):
    S, fn = PIECES[name]
    sc = reset()
    P = Piece()
    fn(P)
    objs = P.finish(sc)
    px = int(S * ppm)
    sc.render.resolution_x = px
    sc.render.resolution_y = px
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = S
    cam.clip_start = 0.1
    cam.clip_end = 500
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    t = math.radians(tilt)
    # looking down; tilt rotates the view towards the north (camera on the south side)
    co.rotation_euler = (t, 0, 0)
    d = Vector((0, math.sin(t) * -1, math.cos(t)))
    co.location = d * 150.0 + Vector((0, 0, 0))
    vl = bpy.context.view_layer
    os.makedirs(out, exist_ok=True)
    base = os.path.join(out, name)
    # albedo (default materials)
    vl.material_override = None
    sc.render.filepath = base + "_albedo.png"
    bpy.ops.render.render(write_still=True)
    for kind in ("normal", "height", "mask"):
        vl.material_override = pass_material(kind)
        sc.render.filepath = "%s_%s.png" % (base, kind)
        bpy.ops.render.render(write_still=True)
    json.dump({"name": name, "canvas_m": S, "ppm": ppm, "px": px, "zmax": ZMAX, "tilt": tilt},
              open(base + ".json", "w"))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"pieces": list(PIECES), "ppm": 8.0, "tilt": 0.0, "out": os.path.join(HERE, "_frames")}
    i = 0
    while i < len(argv):
        k = argv[i]
        if k == "--pieces": a["pieces"] = argv[i + 1].split(","); i += 1
        elif k == "--ppm": a["ppm"] = float(argv[i + 1]); i += 1
        elif k == "--tilt": a["tilt"] = float(argv[i + 1]); i += 1
        elif k == "--out": a["out"] = os.path.abspath(argv[i + 1]); i += 1
        i += 1
    for n in a["pieces"]:
        render(n, a["ppm"], a["tilt"], a["out"])
        print("DONE", n)


main()
