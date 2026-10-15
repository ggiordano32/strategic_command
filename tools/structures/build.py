"""Overworld structure pipeline: builds structures from spec.json in Blender
and renders pre-baked 3/4-view sprites (orthographic, tilted from vertical,
sun from the north-west, transparent background) in four toon styles.

    ~/.local/bin/blender -b --factory-startup -P tools/structures/build.py -- \
        [--structs star_fort,port] [--styles A,B,C,D] [--sizes 256,96] \
        [--tilt 35] [--out tools/structures/_frames]

Output: <out>/<style>/<struct>_<size>_shade.png  (lit colours, faction parts
white), <struct>_<size>_mask.png (R primary, G secondary, B accent, unlit)
and <struct>_<size>.json (pixel size, ground origin in px, metres per px).
`python3 tools/structures/compose.py` recolours with palettes and makes the
boards. Deterministic: fixed EEVEE samples, no random.

Spec reference: README.md. World axes: +X east, +Y north (image up), +Z up;
the camera looks north from the south, tilted `tilt` degrees from vertical.
"""
import bpy
import bmesh
import colorsys
import json
import math
import os
import random
import sys
import time
import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
from mathutils import Matrix, Vector, Euler

PPM_256 = 3.6        # pixels per metre at size 256 (the group frames' scale)
TILE_DEPTH = 2.4     # thickness of a base tile (style D)
HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = json.load(open(os.path.join(HERE, "spec.json")))
TEAM = {"primary": (1, 0, 0), "secondary": (0, 1, 0), "accent": (0, 0, 1)}
# Light direction (towards the light): key from the north-west, fill from the
# camera side so south faces read as a mid band instead of black.
KEY_TO = Vector((-0.55, 0.45, 0.70)).normalized()
FILL_TO = Vector((0.25, -0.60, 0.76)).normalized()


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"structs": list(SPEC["structures"].keys()), "styles": ["D"],
         "sizes": [256, 96], "tilt": 52.0, "out": os.path.join(HERE, "_frames")}
    i = 0
    while i < len(argv):
        k = argv[i]
        if k == "--structs": a["structs"] = argv[i + 1].split(","); i += 1
        elif k == "--styles": a["styles"] = argv[i + 1].split(","); i += 1
        elif k == "--sizes": a["sizes"] = [int(x) for x in argv[i + 1].split(",")]; i += 1
        elif k == "--tilt": a["tilt"] = float(argv[i + 1]); i += 1
        elif k == "--out": a["out"] = os.path.abspath(argv[i + 1]); i += 1
        i += 1
    return a


# ---------------------------------------------------------------- spec expansion

def rot_matrix(r):
    if r is None:
        return Matrix.Identity(4)
    if isinstance(r, (int, float)):
        r = [0, 0, r]
    return Euler([math.radians(v) for v in r], "XYZ").to_matrix().to_4x4()


def scale_matrix(s):
    if s is None:
        return Matrix.Identity(4)
    if isinstance(s, (int, float)):
        s = [s, s, s]
    return Matrix.Diagonal((s[0], s[1], s[2], 1.0))


def expand(parts, M, mp, out, depth=0):
    """Flatten `use` references into (part, matrix, material-map) triples."""
    for p in parts:
        if "use" in p:
            if depth > 6:
                raise RuntimeError("use nesting too deep")
            sub = SPEC["defs"][p["use"]]
            cmap = dict(mp)
            for k, v in p.get("map", {}).items():
                cmap[k] = mp.get(v, v)
            pos = p.get("p", [0, 0, 0])
            if "polar" in p:
                n, rad, start = p["polar"]
                for k in range(int(n)):
                    ang = math.radians(start + 360.0 * k / n)
                    q = Matrix.Translation((rad * math.cos(ang), rad * math.sin(ang), pos[2]))
                    q = q @ rot_matrix([0, 0, start + 360.0 * k / n]) @ rot_matrix(p.get("r")) @ scale_matrix(p.get("sc"))
                    expand(sub, M @ q, cmap, out, depth + 1)
            else:
                q = Matrix.Translation(pos) @ rot_matrix(p.get("r")) @ scale_matrix(p.get("sc"))
                expand(sub, M @ q, cmap, out, depth + 1)
        else:
            out.append((p, M, mp))
    return out


def poly_points(spec):
    if isinstance(spec, list):
        return [tuple(v) for v in spec]
    if "star" in spec:
        n, ro, ri, rot = spec["star"]
        pts = []
        for i in range(n * 2):
            a = math.radians(rot + 180.0 * i / n)
            r = ro if i % 2 == 0 else ri
            pts.append((r * math.cos(a), r * math.sin(a)))
        return pts
    if "circle" in spec:
        c = spec["circle"]
        n, r = int(c[0]), c[1]
        jit = c[2] if len(c) > 2 else 0.0
        seed = int(c[3]) if len(c) > 3 else 1
        a0 = c[4] if len(c) > 4 else 0.0
        a1 = c[5] if len(c) > 5 else 360.0
        rng = random.Random(seed)
        span = a1 - a0
        cnt = n if (a1 - a0) >= 360 else n + 1
        pts = []
        for i in range(cnt):
            a = math.radians(a0 + span * i / n)
            rr = r * (1.0 + jit * (rng.random() * 2 - 1))
            pts.append((rr * math.cos(a), rr * math.sin(a)))
        return pts
    if "rect" in spec:
        x0, y0, x1, y1 = spec["rect"]
        return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    raise KeyError(spec)


# ---------------------------------------------------------------- meshes

def scale_pts(pts, s):
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    return [(cx + (x - cx) * s, cy + (y - cy) * s) for x, y in pts]


def mesh_poly(bm, pts, z0, z1, sc0, sc1):
    lo = scale_pts(pts, sc0)
    hi = scale_pts(pts, sc1)
    bv = [bm.verts.new((x, y, z0)) for x, y in lo]
    tv = [bm.verts.new((x, y, z1)) for x, y in hi]
    n = len(pts)
    bm.faces.new(list(reversed(bv)))
    bm.faces.new(tv)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bv[i], bv[j], tv[j], tv[i]))


def mesh_wall(bm, pts, closed, t0, t1, h, z0):
    n = len(pts)
    P = [Vector((x, y)) for x, y in pts]

    def offs(i, half):
        a = P[(i - 1) % n] if (closed or i > 0) else None
        b = P[(i + 1) % n] if (closed or i < n - 1) else None
        d1 = (P[i] - a).normalized() if a is not None else None
        d2 = (b - P[i]).normalized() if b is not None else None
        n1 = Vector((-d1.y, d1.x)) if d1 is not None else None
        n2 = Vector((-d2.y, d2.x)) if d2 is not None else None
        if n1 is None: nn = n2
        elif n2 is None: nn = n1
        else:
            nn = (n1 + n2)
            ln = nn.length
            nn = nn / ln if ln > 1e-6 else n1
            c = max(0.55, nn.dot(n1))  # mitre, limited
            nn = nn / c
        return P[i] + nn * half, P[i] - nn * half

    rings = []
    for (half, z) in ((t0 / 2, z0), (t1 / 2, z0 + h)):
        L, R = [], []
        for i in range(n):
            l, r = offs(i, half)
            L.append(bm.verts.new((l.x, l.y, z)))
            R.append(bm.verts.new((r.x, r.y, z)))
        rings.append((L, R))
    (bL, bR), (tL, tR) = rings
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        j = (i + 1) % n
        bm.faces.new((bL[i], bL[j], tL[j], tL[i]))
        bm.faces.new((bR[j], bR[i], tR[i], tR[j]))
        bm.faces.new((tL[i], tL[j], tR[j], tR[i]))
        bm.faces.new((bL[j], bL[i], bR[i], bR[j]))
    if not closed:
        bm.faces.new((bR[0], bL[0], tL[0], tR[0]))
        bm.faces.new((bL[-1], bR[-1], tR[-1], tL[-1]))


def mesh_roof(bm, sx, sy, sz, ridge):
    hx, hy = sx / 2, sy / 2
    rl = hx * ridge
    b = [bm.verts.new(v) for v in ((-hx, -hy, 0), (hx, -hy, 0), (hx, hy, 0), (-hx, hy, 0))]
    t0 = bm.verts.new((-rl, 0, sz))
    t1 = bm.verts.new((rl, 0, sz))
    bm.faces.new((b[3], b[2], b[1], b[0]))
    bm.faces.new((b[0], b[1], t1, t0))      # south slope
    bm.faces.new((b[2], b[3], t0, t1))      # north slope
    if ridge > 0.0:
        bm.faces.new((b[1], b[2], t1))      # east gable
        bm.faces.new((b[3], b[0], t0))      # west gable
    else:
        bm.faces.new((b[1], b[2], t1))
        bm.faces.new((b[3], b[0], t0))


def mesh_wedge(bm, sx, sy, sz):
    hx, hy = sx / 2, sy / 2
    v = [bm.verts.new(p) for p in ((-hx, -hy, 0), (hx, -hy, 0), (hx, hy, 0), (-hx, hy, 0),
                                   (-hx, -hy, sz), (-hx, hy, sz))]
    bm.faces.new((v[3], v[2], v[1], v[0]))
    bm.faces.new((v[0], v[4], v[5], v[3]))  # high end (west)
    bm.faces.new((v[0], v[1], v[4]))
    bm.faces.new((v[2], v[3], v[5]))
    bm.faces.new((v[1], v[2], v[5], v[4]))  # slope


def build_part_mesh(p, M):
    s = p["s"]
    bm = bmesh.new()
    pos = Vector(p.get("p", [0, 0, 0]))
    pm = Matrix.Translation(pos) @ rot_matrix(p.get("r"))
    if s == "box":
        sx, sy, sz = p["sz"]
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector(((v.co.x) * sx, (v.co.y) * sy, (v.co.z + 0.5) * sz))
    elif s in ("cyl", "cone"):
        r1 = p.get("rad", 1.0)
        r2 = p.get("rad2", 0.0 if s == "cone" else r1)
        h = p["h"]
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=p.get("n", 8),
                              radius1=r1, radius2=r2, depth=h)
        for v in bm.verts:
            v.co.z += h / 2
        if p.get("n", 8) % 2 == 0:
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                             matrix=Matrix.Rotation(math.pi / p.get("n", 8), 3, "Z"))
    elif s == "sph":
        rx, ry, rz = p["sz"]
        n = p.get("n", 7)
        bmesh.ops.create_uvsphere(bm, u_segments=n, v_segments=max(4, n // 2 + 1), radius=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * rx, v.co.y * ry, v.co.z * rz))
    elif s == "roof":
        sx, sy, sz = p["sz"]
        mesh_roof(bm, sx, sy, sz, p.get("ridge", 1.0))
    elif s == "wedge":
        sx, sy, sz = p["sz"]
        mesh_wedge(bm, sx, sy, sz)
    elif s == "poly":
        mesh_poly(bm, poly_points(p["pts"]), p.get("z0", 0.0), p.get("z1", 1.0),
                  p.get("sc0", 1.0), p.get("sc1", 1.0))
    elif s == "wall":
        mesh_wall(bm, poly_points(p["pts"]), p.get("closed", True), p["t"],
                  p.get("t2", p["t"]), p["h"], p.get("z0", 0.0))
    elif s == "steps":
        bx, by, ht = p["sz"]
        n = p["n"]
        sh = p.get("shrink", 0.1)
        for i in range(n):
            k = max(0.05, 1.0 - sh * i)
            sx, sy = bx * k, by * k
            h0, h1 = ht * i / n, ht * (i + 1) / n
            vs = [bm.verts.new(v) for v in ((-sx / 2, -sy / 2, h0), (sx / 2, -sy / 2, h0),
                                            (sx / 2, sy / 2, h0), (-sx / 2, sy / 2, h0),
                                            (-sx / 2, -sy / 2, h1), (sx / 2, -sy / 2, h1),
                                            (sx / 2, sy / 2, h1), (-sx / 2, sy / 2, h1))]
            for f in ((3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
                bm.faces.new([vs[i2] for i2 in f])
    else:
        raise KeyError("shape " + s)
    full = M @ pm
    bmesh.ops.transform(bm, matrix=full, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ---------------------------------------------------------------- materials

def node(nt, kind, **props):
    n = nt.nodes.new(kind)
    for k, v in props.items():
        setattr(n, k, v)
    return n


def sock(n, ident, out=False):
    for s in (n.outputs if out else n.inputs):
        if s.identifier == ident or s.name == ident:
            if not out and not s.enabled:
                continue
            return s
    raise KeyError(ident)


def new_material(name):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    return m, nt


def mix(nt, blend, a, b, fac=1.0):
    mx = node(nt, "ShaderNodeMix", data_type="RGBA", blend_type=blend)
    if isinstance(fac, (int, float)):
        sock(mx, "Factor_Float").default_value = fac
    else:
        nt.links.new(fac, sock(mx, "Factor_Float"))
    for key, v in (("A_Color", a), ("B_Color", b)):
        if isinstance(v, (tuple, list)):
            sock(mx, key).default_value = (v[0], v[1], v[2], 1.0)
        else:
            nt.links.new(v, sock(mx, key))
    return sock(mx, "Result_Color", out=True)


def adjust(rgb, style):
    h, s, v = colorsys.rgb_to_hsv(*rgb)
    if style == "A":
        s, v = min(1, s * 1.18), min(1, v * 1.02)
    elif style == "B":
        s, v = min(1, s * 1.0), v
    elif style == "C":
        s, v = s * 0.78, min(1, v * 1.05)
    else:  # D: saturated paint
        s, v = min(1, s * 1.3), min(1, v * 1.06)
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    if style == "C":  # a little of the map's tan
        r, g, b = (r * 0.88 + 0.55 * 0.12, g * 0.88 + 0.50 * 0.12, b * 0.88 + 0.40 * 0.12)
    return (r, g, b)


RAMPS = {
    "A": [(0.0, (0.60, 0.58, 0.66)), (SPEC["bands"]["A"][0], (1.0, 1.0, 1.0))],
    "B": [(0.0, (0.55, 0.62, 0.86)), (SPEC["bands"]["B"][0], (0.86, 0.87, 0.92)),
          (SPEC["bands"]["B"][1], (1.0, 0.96, 0.84))],
    "C": [(0.0, (0.80, 0.82, 0.90)), (SPEC["bands"]["C"][0], (1.0, 1.0, 0.98))],
    "D": [(0.0, (0.58, 0.60, 0.80)), (SPEC["bands"]["D"][0], (0.84, 0.85, 0.92)),
          (SPEC["bands"]["D"][1], (1.0, 0.97, 0.88))],
}
HEIGHT = {"A": None, "B": (1.6, 0.74, 1.0), "C": (2.5, 0.93, 1.0), "D": (1.2, 0.80, 1.0)}


def shade_material(name, style, rgb, matte=False):
    dbg = os.environ.get("SC_DBG", "")
    m, nt = new_material(name)
    dif = node(nt, "ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = node(nt, "ShaderNodeShaderToRGB")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    bw = node(nt, "ShaderNodeRGBToBW")
    nt.links.new(s2r.outputs["Color"], bw.inputs[0])
    ramp = node(nt, "ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.interpolation = "CONSTANT"
    stops = RAMPS[style]
    while len(cr.elements) < len(stops):
        cr.elements.new(0.5)
    for el, (pos, col) in zip(cr.elements, stops):
        el.position = pos
        el.color = (col[0], col[1], col[2], 1.0)
    nt.links.new(bw.outputs[0], ramp.inputs[0])
    col = mix(nt, "MULTIPLY", ramp.outputs["Color"], rgb)
    ht = HEIGHT[style]
    if ht and not matte:
        geo = node(nt, "ShaderNodeNewGeometry")
        sep = node(nt, "ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        mr = node(nt, "ShaderNodeMapRange", clamp=True)
        nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
        mr.inputs["From Min"].default_value = 0.0
        mr.inputs["From Max"].default_value = ht[0]
        mr.inputs["To Min"].default_value = ht[1]
        mr.inputs["To Max"].default_value = ht[2]
        v = sock(mr, "Result", out=True)
        col = mix(nt, "MULTIPLY", col, _gray(nt, v))
    if style in ("C", "D") and not matte and "nobev" not in dbg:
        # edge highlight (C) / dry-brush edge (D): bevel normal vs true normal
        try:
            bev = node(nt, "ShaderNodeBevel")
            bev.inputs["Radius"].default_value = 0.35 if style == "D" else 0.25
            geo2 = node(nt, "ShaderNodeNewGeometry")
            dot = node(nt, "ShaderNodeVectorMath", operation="DOT_PRODUCT")
            nt.links.new(bev.outputs["Normal"], dot.inputs[0])
            nt.links.new(geo2.outputs["Normal"], dot.inputs[1])
            mr2 = node(nt, "ShaderNodeMapRange", clamp=True)
            nt.links.new(dot.outputs["Value"], mr2.inputs["Value"])
            mr2.inputs["From Min"].default_value = 0.985
            mr2.inputs["From Max"].default_value = 0.90
            mr2.inputs["To Min"].default_value = 0.0
            mr2.inputs["To Max"].default_value = 0.28 if style == "C" else 0.38
            col = mix(nt, "SCREEN", col, (1.0, 0.97, 0.88), fac=sock(mr2, "Result", out=True))
        except Exception as e:
            print("bevel node unavailable:", e)
    if style == "D" and not matte and "nogloss" not in dbg:
        # glossy paint: a hard specular glint
        gl = node(nt, "ShaderNodeBsdfGlossy")
        gl.inputs["Roughness"].default_value = 0.28
        s2 = node(nt, "ShaderNodeShaderToRGB")
        nt.links.new(gl.outputs[0], s2.inputs[0])
        bw2 = node(nt, "ShaderNodeRGBToBW")
        nt.links.new(s2.outputs["Color"], bw2.inputs[0])
        r2 = node(nt, "ShaderNodeValToRGB")
        r2.color_ramp.interpolation = "CONSTANT"
        r2.color_ramp.elements[0].color = (0, 0, 0, 1)
        r2.color_ramp.elements[1].position = 0.5
        r2.color_ramp.elements[1].color = (0.30, 0.29, 0.27, 1)
        nt.links.new(bw2.outputs[0], r2.inputs[0])
        col = mix(nt, "ADD", col, r2.outputs["Color"])
    em = node(nt, "ShaderNodeEmission")
    nt.links.new(col, em.inputs["Color"])
    out = node(nt, "ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def _gray(nt, v):
    c = node(nt, "ShaderNodeCombineColor")
    for ch in ("Red", "Green", "Blue"):
        nt.links.new(v, c.inputs[ch])
    return c.outputs["Color"]


def flat_material(name, rgb, cull=False):
    m, nt = new_material(name)
    em = node(nt, "ShaderNodeEmission")
    em.inputs["Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    out = node(nt, "ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    if cull:
        m.use_backface_culling = True
    return m


def mask_material():
    m, nt = new_material("pass_mask")
    at = node(nt, "ShaderNodeAttribute", attribute_type="OBJECT", attribute_name="sc_mask")
    em = node(nt, "ShaderNodeEmission")
    nt.links.new(at.outputs["Color"], em.inputs["Color"])
    out = node(nt, "ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


# ---------------------------------------------------------------- scene

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    r = sc.render
    r.engine = "BLENDER_EEVEE"
    r.film_transparent = True
    r.filter_size = 1.0
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    r.image_settings.color_depth = "8"
    r.image_settings.compression = 15
    sc.display_settings.display_device = "sRGB"
    try:
        sc.view_settings.view_transform = "Raw"
    except TypeError:
        sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.eevee.taa_render_samples = 24
    for attr, val in (("use_shadows", True), ("use_gtao", False), ("use_raytracing", False)):
        if hasattr(sc.eevee, attr):
            setattr(sc.eevee, attr, val)
    w = bpy.data.worlds.new("world")
    sc.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0, 0, 0, 1)
        bg.inputs["Strength"].default_value = 0.0
    return sc


def add_sun(name, to_light, energy, shadow, angle=6.0):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = energy
    ld.angle = math.radians(angle)
    ld.use_shadow = shadow
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    travel = -to_light
    ob.rotation_euler = travel.to_track_quat("-Z", "Y").to_euler()
    return ob


# ---------------------------------------------------------------- structure

def _is_ground_paint(p, mp):
    """Ground tiles and flat ground paint (dirt / cobble / grass patches, streets): left out of the sprites
    (set SC_BASES=1 to bring the bevelled base tiles back)."""
    if os.environ.get("SC_BASES"):
        return False
    if p.get("ground"):
        return True
    mk = mp.get(p["m"], p["m"])
    if mk not in ("dirt", "cobble", "grass_dk", "grass", "sand"):
        return False
    if p["s"] == "box":
        return p["sz"][2] <= 0.4
    return p["s"] == "poly" and p.get("z1", 0.0) <= 0.3


def build_structure(key, style, sizepx, tilt):
    """Returns (scene, objs, outline_objs) and the projected bounds."""
    st = SPEC["structures"][key]
    sc = reset_scene()
    flat = expand(st["parts"], Matrix.Identity(4), {}, [])
    mat_cache = {}
    ol_cache = {}
    objs, outlines = [], []
    pal = SPEC["materials"]
    ol_px = {"A": 2.3, "B": 1.5, "C": 0.0, "D": 1.2}[style] * max(0.55, sizepx / 256.0) if style != "C" else 0.0
    ol_px = max(ol_px, 0.9) if ol_px > 0 else 0.0
    # metres per pixel is known only after framing; two passes: build meshes,
    # frame, then set the solidify thickness.
    allv = []
    d_tile = style == "D"
    zex = st.get("zex", 1.0)
    for p, M, mp in flat:
        if d_tile and _is_ground_paint(p, mp):
            continue   # no bases: the overworld paints the settlement's ground itself (game/campaign/footprint.gd)
        if not p.get("ground") and zex != 1.0:
            M = Matrix.Diagonal((1.0, 1.0, zex, 1.0)) @ M
        mkey = mp.get(p["m"], p["m"])
        if p.get("ground") and d_tile:
            # painted base tile: thick bevelled side + the top as the ground
            side = dict(p)
            side.update({"ol": 0, "z0": -TILE_DEPTH, "z1": -0.05, "sc0": 1.0, "sc1": 0.975, "m": "tile_edge", "ground": 0})
            top = dict(p)
            top.update({"ol": 0, "z0": -0.06, "z1": 0.0 + p.get("z1", 0.0), "sc0": 0.975, "sc1": 0.975})
            pieces = [(side, "tile_edge"), (top, mkey)]
        elif p.get("ground"):
            q = dict(p)
            q.update({"z0": p.get("z0", -0.3), "z1": p.get("z1", 0.0)})
            pieces = [(q, mkey)]
        else:
            pieces = [(p, mkey)]
        for pp, mk in pieces:
            bm = build_part_mesh(pp, M)
            for v in bm.verts:
                allv.append(v.co.copy())
            me = bpy.data.meshes.new("m")
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new("o", me)
            sc.collection.objects.link(ob)
            ob["sc_mask"] = list(TEAM.get(mk, (0.0, 0.0, 0.0))) + [1.0]
            matte = bool(pp.get("ground"))
            ck = (mk, matte)
            if ck not in mat_cache:
                rgb = (1.0, 1.0, 1.0) if mk in TEAM else adjust(tuple(pal[mk]), style)
                mat_cache[ck] = shade_material("s_%s_%d" % (mk, matte), style, rgb, matte)
            ob.data.materials.append(mat_cache[ck])
            objs.append((ob, mk, pp))
    # projection
    t = math.radians(tilt)
    right = Vector((1, 0, 0))
    up = Vector((0, math.cos(t), math.sin(t)))
    view = Vector((0, math.sin(t), -math.cos(t)))
    xs = [v.dot(right) for v in allv]
    ys = [v.dot(up) for v in allv]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    w, h = x1 - x0, y1 - y0
    pad = 1.05
    ortho = max(w, h) * pad
    if w >= h:
        rx, ry = sizepx, max(8, int(round(sizepx * h / w)))
    else:
        rx, ry = max(8, int(round(sizepx * w / h))), sizepx
    ppm = sizepx / ortho
    if st.get("frame") == "auto":
        # A single piece (tools/structures/gen_spec.py pieces): the scale is fixed like a frame's, the box is its own bounds.
        pad = 0.8
        ppm = PPM_256 * sizepx / 256.0
        rx = int(math.ceil((x1 - x0 + 2 * pad) * ppm)) + 4
        ry = int(math.ceil((y1 - y0 + 2 * pad) * ppm)) + 4
        x0, x1, y0, y1 = x0 - pad, x1 + pad, y0 - pad, y1 + pad
        ortho = max(rx, ry) / ppm
        w, h = rx / ppm, ry / ppm
    elif "frame" in st:
        # A fixed frame (ground rectangle + height): every layer of a group
        # shares it, so the sprites overlay exactly; the scale is PPM_256
        # pixels a metre at "256", proportionally less at the smaller sizes.
        fx0, fy0, fx1, fy1, fz = st["frame"]
        fz = fz * zex
        pts = [(x, y, z) for x in (fx0, fx1) for y in (fy0, fy1) for z in (-TILE_DEPTH, fz)]
        xs = [p[0] for p in pts]
        ys = [p[1] * math.cos(t) + p[2] * math.sin(t) for p in pts]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        ppm = PPM_256 * sizepx / 256.0
        rx = int(math.ceil((x1 - x0) * ppm)) + 4
        ry = int(math.ceil((y1 - y0) * ppm)) + 4
        ortho = max(rx, ry) / ppm
        w, h = rx / ppm, ry / ppm
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho
    cd.clip_start, cd.clip_end = 0.1, 400.0
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    centre = right * cx + up * cy
    cam.location = centre - view * 150.0
    cam.rotation_euler = (t, 0, 0)
    # outlines (inverted hulls)
    thick = ol_px / ppm if ol_px else 0.0
    if thick > 0:
        for ob, mk, pp in objs:
            if pp.get("ol", 1) == 0 or ("noolg" in os.environ.get("SC_DBG", "") and pp.get("ground")):
                continue
            if style == "A":
                col = SPEC["ink"]
            else:
                if mk in TEAM:
                    base = (0.62, 0.22, 0.18)
                else:
                    base = adjust(tuple(pal[mk]), style)
                h_, s_, v_ = colorsys.rgb_to_hsv(*base)
                col = colorsys.hsv_to_rgb(h_, min(1.0, s_ * 1.1 + 0.1), v_ * (0.38 if style == "B" else 0.45))
            ck = tuple(round(c, 2) for c in col)
            if ck not in ol_cache:
                ol_cache[ck] = flat_material("ol_%s_%s_%s" % ck, col, cull=True)
            o2 = bpy.data.objects.new("ol", ob.data.copy())
            sc.collection.objects.link(o2)
            o2.data.materials.clear()
            o2.data.materials.append(ol_cache[ck])
            md = o2.modifiers.new("sol", "SOLIDIFY")
            md.thickness = thick * pp.get("olw", 1.0)
            md.offset = 1.0
            md.use_flip_normals = True
            md.use_even_offset = True
            try:
                o2.visible_shadow = False
            except Exception:
                pass
            outlines.append(o2)
    add_sun("key", KEY_TO, SPEC["light"]["key"], "noshadow" not in os.environ.get("SC_DBG", ""))
    add_sun("fill", FILL_TO, SPEC["light"]["fill"], False, 20.0)
    info = {"w": rx, "h": ry, "ppm": ppm, "m_per_px": 1.0 / ppm, "tilt": tilt,
            "origin_px": [(0 - cx) * ppm + rx / 2, ry / 2 - (0 * math.cos(t) - cy) * ppm],
            "name": st.get("name", key), "ground_m": st.get("ground_m", w)}
    return sc, outlines, info


def render_structure(key, style, sizepx, tilt, outdir):
    t0 = time.time()
    sc, outlines, info = build_structure(key, style, sizepx, tilt)
    os.makedirs(outdir, exist_ok=True)
    base = os.path.join(outdir, "%s_%d" % (key, sizepx))
    vl = bpy.context.view_layer
    for pname, mo, hide in (("shade", None, False), ("mask", mask_material(), True)):
        for o in outlines:
            o.hide_render = hide
        vl.material_override = mo
        sc.render.filepath = base + "_" + pname + ".png"
        bpy.ops.render.render(write_still=True)
    vl.material_override = None
    json.dump(info, open(base + ".json", "w"))
    return time.time() - t0


def main():
    a = parse_args()
    for style in a["styles"]:
        for key in a["structs"]:
            tm = []
            for size in a["sizes"]:
                tm.append(render_structure(key, style, size, a["tilt"], os.path.join(a["out"], style)))
            print("TIME %s %s %s" % (style, key, " ".join("%d:%.2fs" % (s, t) for s, t in zip(a["sizes"], tm))))


main()
