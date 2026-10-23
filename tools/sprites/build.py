"""Sprite pipeline, step 1a: build units from tools/sprites/spec.json in
Blender and render their frames (top-down orthographic, plus one unit's walk
in 8 iso directions).

Run headless (Blender 5.2, EEVEE on the GPU):

    ~/.local/bin/blender -b --factory-startup -P tools/sprites/build.py -- \
        [--units heavy_swords,spearmen] [--no-iso] [--out tools/sprites/_frames]

Then `python3 tools/sprites/pack.py` makes the sheets and manifest.

Per unit, every part in the spec becomes a low-poly mesh (bmesh, flat
shaded, bevelled boxes), rigidly parented to a bone of the unit's rig (no
skinning); the four actions are keyframed on the armature (one timeline:
idle 1, walk 11-16, attack 21-24, death 31-33), by pose functions shared by
every humanoid (and one set for horses). Each frame renders three passes
with a transparent background and the Raw view transform (bytes = values):

  shade  toon lighting x albedo; team parts (primary / secondary / accent)
         are white here, so the pixel holds only their lighting;
  mask   R = primary, G = secondary, B = accent weight (unlit emission);
  pat    the cloth check of `pattern` parts (unlit, R channel).

Frames are written as <out>/<unit>/<action>_<i>_<pass>.png (and
<out>/iso_<unit>/d<dir>_<i>_<pass>.png), with <out>/<unit>/info.json holding
the camera box so pack.py can place the anchor (the man's feet, the unit's
origin) exactly. Deterministic: fixed EEVEE samples, no noise or random.
"""

import bpy
import bmesh
import json
import math
import os
import sys
import time
import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
from mathutils import Matrix, Vector, Euler, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = json.load(open(os.path.join(HERE, "spec.json")))
PPM = SPEC["px_per_m"]

# Timeline: action -> first frame (frames are consecutive).
ACT_START = {"idle": 1, "walk": 11, "attack": 21, "death": 31, "sidestep": 41, "backstep": 51}


CUR_UID = [""]


def action_for(act, uid):
    """Actions with a "units" list in the spec are rendered for those units
    only (the others alias their walk in pack.py)."""
    us = SPEC["actions"][act].get("units")
    return us is None or uid in us


# ---------------------------------------------------------------- arguments

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"units": list(SPEC["units"].keys()), "iso": True,
         "out": os.path.join(HERE, "_frames")}
    i = 0
    while i < len(argv):
        k = argv[i]
        if k == "--units":
            a["units"] = argv[i + 1].split(","); i += 1
        elif k == "--no-iso":
            a["iso"] = False
        elif k == "--iso-only":
            a["units"] = []
        elif k == "--out":
            a["out"] = os.path.abspath(argv[i + 1]); i += 1
        i += 1
    return a


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
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    ee = sc.eevee
    ee.taa_render_samples = 16
    for attr, val in (("use_shadows", True), ("use_gtao", False),
                      ("use_bloom", False), ("use_raytracing", False)):
        if hasattr(ee, attr):
            setattr(ee, attr, val)
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


def link_obj(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


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


def mix_mul(nt, a, b):
    mx = node(nt, "ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    sock(mx, "Factor_Float").default_value = 1.0
    nt.links.new(a, sock(mx, "A_Color"))
    if isinstance(b, (tuple, list)):
        sock(mx, "B_Color").default_value = (b[0], b[1], b[2], 1.0)
    else:
        nt.links.new(b, sock(mx, "B_Color"))
    return sock(mx, "Result_Color", out=True)


def shade_material(name, rgb):
    """Toon-ish: diffuse light -> 3 flat bands (ambient floor so dark
    colours still read) x albedo x a mild height term (higher = lighter,
    a top-down depth cue), as emission."""
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
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0.60, 0.60, 0.60, 1)
    cr.elements[1].position = 0.22
    cr.elements[1].color = (0.82, 0.82, 0.82, 1)
    e = cr.elements.new(0.52)
    e.color = (1.0, 1.0, 1.0, 1)
    nt.links.new(bw.outputs[0], ramp.inputs[0])
    lit = mix_mul(nt, ramp.outputs["Color"], rgb)
    geo = node(nt, "ShaderNodeNewGeometry")
    sep = node(nt, "ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    mr = node(nt, "ShaderNodeMapRange", clamp=True)
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = 1.9
    mr.inputs["To Min"].default_value = 0.84
    mr.inputs["To Max"].default_value = 1.04
    out_col = mix_mul(nt, lit, mr.outputs["Result"])
    em = node(nt, "ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(out_col, em.inputs["Color"])
    out = node(nt, "ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def mask_material():
    m, nt = new_material("pass_mask")
    at = node(nt, "ShaderNodeAttribute", attribute_type="OBJECT",
              attribute_name="sc_mask")
    em = node(nt, "ShaderNodeEmission")
    nt.links.new(at.outputs["Color"], em.inputs["Color"])
    out = node(nt, "ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def pattern_material():
    m, nt = new_material("pass_pat")
    at = node(nt, "ShaderNodeAttribute", attribute_type="OBJECT",
              attribute_name="sc_pat")
    tc = node(nt, "ShaderNodeTexCoord")
    ck = node(nt, "ShaderNodeTexChecker")
    ck.inputs["Color1"].default_value = (1, 1, 1, 1)
    ck.inputs["Color2"].default_value = (0, 0, 0, 1)
    # Blender's checker squares are 1 / scale wide (object space, metres).
    ck.inputs["Scale"].default_value = 1.0 / SPEC["check_size_m"]
    nt.links.new(tc.outputs["Object"], ck.inputs["Vector"])
    mx = mix_mul(nt, ck.outputs["Color"], at.outputs["Color"])
    em = node(nt, "ShaderNodeEmission")
    nt.links.new(mx, em.inputs["Color"])
    out = node(nt, "ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


TEAM = {"primary": (1, 0, 0), "secondary": (0, 1, 0), "accent": (0, 0, 1)}
_mats = {}


def material_for(key):
    if key not in _mats:
        rgb = (1.0, 1.0, 1.0) if key in TEAM else tuple(SPEC["materials"][key])
        _mats[key] = shade_material("m_" + key, rgb)
    return _mats[key]


# ---------------------------------------------------------------- meshes

def bevel_all(bm, off):
    if off > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=off, segments=1,
                        affect="EDGES", profile=0.5, clamp_overlap=True)


def mesh_box(bm, sx, sy, sz, bevel=0.0):
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    bevel_all(bm, min(bevel, 0.45 * min(sx, sy, sz)))


def mesh_scutum(bm, t, w, h, bend):
    """A box of thickness t (X), width w (Y), height h (Z) curved round the
    bearer: the vertical edges sit further back than the middle."""
    segs = 6
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=segs, size=0.5)
    # grid lies in XY: x in [-.5,.5] -> height (Z), y -> width (Y)
    for v in bm.verts:
        z = v.co.x * h
        y = v.co.y * w
        v.co = Vector((-(y * y) / (2.0 * bend), y, z))
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    vs = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(-t, 0, 0), verts=vs)
    bmesh.ops.translate(bm, vec=(t * 0.5, 0, 0), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def build_part_mesh(p):
    bm = bmesh.new()
    shape = p["shape"]
    mw = Matrix.Identity(4)
    if shape == "box":
        s = p["size"]
        mesh_box(bm, s[0], s[1], s[2], p.get("bevel", 0.0))
    elif shape == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=p.get("verts", 10),
                                  v_segments=6, radius=p["r"])
        sc = p.get("scale", [1, 1, 1])
        bmesh.ops.scale(bm, vec=sc, verts=bm.verts)
    elif shape == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False,
                              segments=p.get("verts", 8), radius1=p["r"],
                              radius2=p["r"], depth=p["len"])
    elif shape == "scutum":
        s = p["size"]
        mesh_scutum(bm, s[0], s[1], s[2], p["bend"])
    elif shape in ("limb", "cone"):
        a = Vector(p["a"]); b = Vector(p["b"])
        d = b - a
        L = d.length
        if shape == "limb":
            t = p["t"]
            tw, th = (t, t) if not isinstance(t, list) else (t[0], t[1])
            mesh_box(bm, tw, th, L, p.get("bevel", min(tw, th) * 0.18))
        else:
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False,
                                  segments=6, radius1=p["r"], radius2=0.0,
                                  depth=L)
        # local Z axis -> a..b, centred at the midpoint
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        mw = Matrix.Translation((a + b) * 0.5) @ q.to_matrix().to_4x4()
    else:
        raise ValueError("unknown shape " + shape)
    if shape not in ("limb", "cone"):
        rot = p.get("rot", [0, 0, 0])
        e = Euler([math.radians(x) for x in rot], "XYZ")
        mw = Matrix.Translation(Vector(p["pos"])) @ e.to_matrix().to_4x4()
    bm.transform(mw)
    me = bpy.data.meshes.new(p["n"])
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = False
    return me


def right_of(name):
    """The right-side twin of a left-side name: x.L -> x.R, and the horse's
    legs leg.FL -> leg.FR, shin.BL -> shin.BR; None if not a left name."""
    if name.endswith(".L"):
        return name[:-2] + ".R"
    if len(name) > 3 and name[-3] == "." and name[-2] in "FB" and name[-1] == "L":
        return name[:-1] + "R"
    return None


def mirrored(p):
    q = json.loads(json.dumps(p))
    q["n"] = right_of(p["n"]) or (p["n"].replace(".L", ".R") if ".L" in p["n"] else p["n"] + ".R")
    rb = right_of(q.get("bone", ""))
    if rb:
        # (step 1a built the horse's right legs on the left legs' bones:
        # they moved as one pair; 1b: each leg on its own bone)
        q["bone"] = rb
    for k in ("pos", "a", "b"):
        if k in q:
            q[k][1] = -q[k][1]
    if "rot" in q:
        q["rot"][0] = -q["rot"][0]
        q["rot"][2] = -q["rot"][2]
    q.pop("mirror", None)
    return q


def expand_parts(parts):
    out = []
    for p in parts:
        out.append(p)
        if p.get("mirror"):
            out.append(mirrored(p))
    return out


# ---------------------------------------------------------------- rigs

def rig_bones(rig, prefix="", offset=(0, 0, 0), root_parent=""):
    """The spec rig's bones, renamed with `prefix`, moved by `offset`; its
    root bone hangs from `root_parent` (a rider's rig inside the horse's)."""
    off = Vector(offset)
    out = []
    for bname, parent, head, tail in rig["bones"]:
        par = prefix + parent if parent else root_parent
        out.append((prefix + bname, par, Vector(head) + off, Vector(tail) + off))
    return out


def build_armature(name, bones):
    ad = bpy.data.armatures.new(name)
    ob = link_obj(bpy.data.objects.new(name, ad))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, parent, head, tail in bones:
        eb = ad.edit_bones.new(bname)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent:
            eb.parent = ad.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


DYN = []        # cords re-aimed every frame (see update_dynamic)
VIS = []        # (object, show, hide): per action frame lists (see set_visibility)


def attach_parts(arm, parts, tag, prefix="", offset=(0, 0, 0), skip=()):
    bpy.context.view_layer.update()
    for p in expand_parts([q for q in parts if q["n"] not in skip]):
        if p["shape"] == "cord":
            add_cord(arm, p, tag, prefix, offset)
            continue
        me = build_part_mesh(p)
        me.transform(Matrix.Translation(Vector(offset)))
        me.materials.append(material_for(p["mat"]))
        ob = link_obj(bpy.data.objects.new(tag + "_" + p["n"], me))
        ob["sc_mask"] = list(TEAM.get(p["mat"], (0.0, 0.0, 0.0)))
        ob["sc_pat"] = [float(p.get("pattern", 0))] * 3
        ob.parent = arm
        ob.parent_type = "BONE"
        ob.parent_bone = prefix + p["bone"]
        bpy.context.view_layer.update()
        ob.matrix_world = arm.matrix_world.copy()
        if p.get("show") or p.get("hide"):
            VIS.append((ob, p.get("show"), p.get("hide")))


def add_cord(arm, p, tag, prefix, offset):
    """A bow string / sling cord: two thin boxes between points that follow
    bones (a, b on p.bone; optional `via` = a point on another bone, used
    in the frames listed in via.show, making a V). Re-aimed by
    update_dynamic after every frame_set."""
    objs = []
    for k in range(2):
        bm = bmesh.new()
        mesh_box(bm, 1.0, 1.0, 1.0)
        me = bpy.data.meshes.new(p["n"] + str(k))
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = False
        me.materials.append(material_for(p["mat"]))
        ob = link_obj(bpy.data.objects.new("%s_%s%d" % (tag, p["n"], k), me))
        ob["sc_mask"] = [0.0, 0.0, 0.0]
        ob["sc_pat"] = [0.0, 0.0, 0.0]
        objs.append(ob)
    DYN.append({"arm": arm, "p": p, "prefix": prefix, "off": Vector(offset), "objs": objs})


def bone_point(arm_eval, bname, pt):
    pb = arm_eval.pose.bones[bname]
    return arm_eval.matrix_world @ (pb.matrix @ (pb.bone.matrix_local.inverted() @ Vector(pt)))


def place_box(ob, a, b, t):
    d = b - a
    L = max(d.length, 1e-4)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    ob.matrix_world = (Matrix.Translation((a + b) * 0.5) @ q.to_matrix().to_4x4()
                       @ Matrix.Diagonal((t, t, L, 1.0)))


def update_dynamic(act, i):
    """After frame_set: per-frame visibility of show / hide parts and the
    cords' end points."""
    for ob, show, hide in VIS:
        vis = True
        if show is not None:
            vis = i in show.get(act, [])
        if hide is not None and i in hide.get(act, []):
            vis = False
        ob.hide_render = not vis
    if not DYN:
        return
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    for d in DYN:
        p = d["p"]
        ev = d["arm"].evaluated_get(dg)
        bn = d["prefix"] + p["bone"]
        a = bone_point(ev, d["prefix"] + p.get("a_bone", p["bone"]), Vector(p["a"]) + d["off"])
        b = bone_point(ev, d["prefix"] + p.get("b_bone", p["bone"]), Vector(p["b"]) + d["off"])
        if "frames" in p and i not in p["frames"].get(act, []):
            for o in d["objs"]:
                o.hide_render = True
            continue
        via = p.get("via")
        c = None
        if via and ("show" not in via or i in via["show"].get(act, [])):
            c = bone_point(ev, d["prefix"] + via["bone"], Vector(via["pos"]) + d["off"])
        t = p.get("t", 0.02)
        o0, o1 = d["objs"]
        o0.hide_render = False
        if c is None:
            place_box(o0, a, b, t)
            o1.hide_render = True
        else:
            place_box(o0, a, c, t)
            place_box(o1, c, b, t)
            o1.hide_render = False


# ---------------------------------------------------------------- poses
#
# A pose: {bone: [(axis, degrees), ...], "loc": (x, y, z) root offset};
# merged poses (several rigs in one armature) carry "_loc": {bone: offset}.
# Axes are the rig's rest axes (armature space): "x" forward, "y" left,
# "z" up. Rotation about "y" by +a swings a hanging limb backward (its foot
# toward -X) and dips a forward-pointing one; about "z" by +a turns the
# right shoulder forward; about "x" by +a lifts a left limb outward.

def apply_pose(arm, pose, frame):
    for pb in arm.pose.bones:
        rest = pb.bone.matrix_local.to_3x3()
        inv = rest.inverted()
        q = Quaternion()
        for axis, deg in pose.get(pb.name, []):
            w = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)),
                 "z": Vector((0, 0, 1))}[axis]
            q = Quaternion(inv @ w, math.radians(deg)) @ q
        pb.rotation_quaternion = q
        if pb.name in pose.get("_loc", {}):
            pb.location = inv @ Vector(pose["_loc"][pb.name])
        else:
            pb.location = (0, 0, 0)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


# Missile troops (step 1c): per-unit pose variants (spec unit "pose") that
# replace the shared attack and tint the idle / walk arms. MISSILE_ATTACK
# fills `add` for frame i and returns the root offset; MISSILE_CARRY adds
# to the shared idle / walk.

def archer_attack(i, add):
    """Draw, full draw, release, recover: bow arm out, string hand to the face."""
    add("spine", "z", [-18, -26, -26, -14][i])
    add("head", "z", [18, 26, 26, 14][i])
    add("upper_arm.L", "y", [-60, -82, -82, -55][i])
    add("upper_arm.L", "z", [0, -6, -6, 0][i])
    add("forearm.L", "y", [60, 82, 80, 50][i])
    add("forearm.L", "x", [55, 60, 60, 55][i])
    add("upper_arm.R", "y", [-60, -85, -80, -40][i])
    add("upper_arm.R", "z", [-15, -25, -30, -10][i])
    add("forearm.R", "y", [60, 84, 84, 40][i])
    add("forearm.R", "x", [70, 100, 90, 40][i])
    add("thigh.L", "y", [-8, -12, -12, -6][i])
    add("thigh.R", "y", [8, 10, 10, 5][i])
    return [[0, 0, 0], [-0.03, 0, 0], [0, 0, 0], [0, 0, 0]][i]


def archer_carry(action, i, s, c, add):
    add("forearm.L", "x", 55)
    add("upper_arm.R", "y", 12)


def belly_attack(i, add):
    """Gastraphetes: stock braced forward in both hands, a lean and a kick."""
    add("forearm.L", "z", -35)
    add("forearm.R", "z", 35)
    add("spine", "y", [8, 14, -4, 0][i])
    add("upper_arm.L", "y", [-8, -12, -6, -8][i])
    add("upper_arm.R", "y", [-10, -16, -10, -10][i])
    add("forearm.R", "y", [4, 8, 2, 4][i])
    add("thigh.L", "y", [-8, -10, -8, -6][i])
    add("thigh.R", "y", [8, 8, 8, 4][i])
    return [[0, 0, 0], [0, 0, 0], [-0.06, 0, 0], [0, 0, 0]][i]


def belly_carry(action, i, s, c, add):
    add("forearm.L", "z", -35)
    add("forearm.R", "z", 35)


def javelin_attack(i, add):
    """Wind-up behind the head, step, release, follow-through."""
    add("spine", "z", [-14, -6, 28, 10][i])
    add("spine", "y", [-6, -2, 10, 4][i])
    add("head", "z", [10, 4, -10, -4][i])
    add("upper_arm.R", "y", [100, 75, -60, -20][i])
    add("forearm.R", "y", [-100, -75, 10, 10][i])
    add("upper_arm.L", "y", [-10, -20, -35, -15][i])
    add("thigh.L", "y", [-6, -26, -30, -12][i])
    add("thigh.R", "y", [8, 14, 18, 8][i])
    add("shin.R", "y", [8, 14, 22, 10][i])
    return [[-0.06, 0, 0], [0.04, 0, 0], [0.18, 0, 0], [0.08, 0, 0]][i]


def javelin_carry(action, i, s, c, add):
    add("upper_arm.R", "y", -10)
    add("forearm.R", "y", 8)


def sling_attack(i, add):
    """Whirl overhead (the cord sweeps round `weapon.R`), release, follow."""
    add("spine", "z", [-12, 4, 24, 10][i])
    add("upper_arm.R", "y", [-150, -165, -120, -40][i])
    add("forearm.R", "y", [-10, -10, -10, 20][i])
    add("weapon.R", "z", [200, 290, 20, 0][i])
    add("upper_arm.L", "y", [-10, -30, -50, -20][i])
    add("thigh.L", "y", [-8, -16, -22, -10][i])
    add("thigh.R", "y", [8, 10, 14, 6][i])
    return [[0, 0, 0], [0.0, 0, 0], [0.1, 0, 0], [0.04, 0, 0]][i]


def sling_carry(action, i, s, c, add):
    add("weapon.R", "y", 80)


def musket_attack(i, add):
    """West musketeers (step 2): the long gun held across the body in both
    hands (it hangs on the spine, the forearms are turned in to it), levelled,
    fired with a kick, brought down. Frame 1 is the shot (muzzle flash)."""
    add("forearm.L", "z", -40)
    add("forearm.R", "z", 40)
    add("spine", "z", [-8, -10, -8, -4][i])
    add("spine", "y", [4, 6, -3, 0][i])
    add("upper_arm.L", "y", [-8, -12, -6, -8][i])
    add("upper_arm.R", "y", [-10, -14, -8, -10][i])
    add("thigh.L", "y", [-8, -10, -8, -6][i])
    add("thigh.R", "y", [8, 8, 8, 4][i])
    return [[0, 0, 0], [-0.08, 0, 0], [-0.03, 0, 0], [0, 0, 0]][i]


def musket_carry(action, i, s, c, add):
    add("forearm.L", "z", -40)
    add("forearm.R", "z", 40)


def pistol_attack(i, add):
    """Mounted pistoleer: both arms thrown out level, a pistol in each hand,
    shot at frame 1 with a kick, then lowered."""
    for arm, sg in (("L", 1), ("R", -1)):
        add("upper_arm." + arm, "y", [-55, -88, -80, -35][i])
        add("forearm." + arm, "y", [55, 88, 90, 40][i])
        add("upper_arm." + arm, "z", sg * [-8, -14, -14, -6][i] * -1)
    add("spine", "y", [0, -4, 4, 0][i])
    return [[0, 0, 0], [-0.03, 0, 0], [-0.01, 0, 0], [0, 0, 0]][i]


def pistol_carry(action, i, s, c, add):
    pass


def crew_attack(i, add):
    """Engine crew (step 1d): bent over the winch, both hands on a spoke,
    cranking it round (arms circle forward and down)."""
    add("spine", "y", [22, 28, 22, 16][i])
    add("head", "y", [-14, -18, -14, -10][i])
    for arm, sg in (("L", 1), ("R", -1)):
        add("upper_arm." + arm, "y", [-35, -10, 15, -10][i] if sg > 0 else [15, -10, -35, -10][i])
        add("forearm." + arm, "y", [20, 5, -10, 5][i] if sg > 0 else [-10, 5, 20, 5][i])
        add("forearm." + arm, "z", -25 * sg)
    add("thigh.L", "y", -18)
    add("thigh.R", "y", 12)
    add("shin.R", "y", 16)
    return [0, 0, -0.04]


def crew_carry(action, i, s, c, add):
    add("upper_arm.L", "y", 10)
    add("upper_arm.R", "y", 10)
    add("forearm.L", "y", 25)
    add("forearm.R", "y", 25)


MISSILE_ATTACK = {"musket": musket_attack, "pistol": pistol_attack, "archer": archer_attack, "belly": belly_attack,
                  "javelin": javelin_attack, "sling": sling_attack, "crew": crew_attack}
MISSILE_CARRY = {"musket": musket_carry, "pistol": pistol_carry, "archer": archer_carry, "belly": belly_carry,
                 "javelin": javelin_carry, "sling": sling_carry, "crew": crew_carry}


def humanoid_pose(action, i, n, mounted=False, variant="", stand=False, fall="thrown"):
    """mounted: a rider (no leg walk, no lunge); stand: a mounted man on his
    feet (an elephant's crew in the howdah: legs straight); fall "roll":
    in the death he stays where he is (rolls with the beast he rides)."""
    P = {}

    def add(b, axis, deg):
        P.setdefault(b, []).append((axis, deg))

    ph = 2.0 * math.pi * i / max(n, 1)
    s, c = math.sin(ph), math.cos(ph)
    loc = [0.0, 0.0, 0.0]
    k = 0.45 if mounted else 1.0
    if action == "idle":
        add("spine", "y", 3)
        add("head", "y", -4)
    elif action == "walk":
        if not mounted:
            add("thigh.L", "y", -30 * s)
            add("shin.L", "y", 34 * max(0.0, c))
            add("thigh.R", "y", 30 * s)
            add("shin.R", "y", 34 * max(0.0, -c))
            add("hips", "z", -5 * s)
            loc[2] = 0.025 * math.cos(2 * ph)
        else:
            loc[2] = 0.03 * math.cos(2 * ph)
        add("upper_arm.R", "y", -18 * s * k)
        add("upper_arm.L", "y", 8 * s * k)
        add("forearm.L", "y", 6 * math.cos(2 * ph))
        add("spine", "z", 6 * s * k)
    elif action == "sidestep":
        # A shuffle to the man's left (the shader mirrors it for the right):
        # feet apart and together along y, guard held to the front.
        lead = 14.0 + 14.0 * math.sin(ph)
        trail = 14.0 + 14.0 * math.sin(ph - 1.3)
        add("thigh.L", "x", lead)
        add("thigh.R", "x", trail)
        add("shin.L", "y", 16 * max(0.0, math.cos(ph)))
        add("shin.R", "y", 16 * max(0.0, math.cos(ph - 1.3)))
        add("spine", "x", -3 * math.sin(ph))
        add("spine", "z", 2 * s)
        add("forearm.L", "y", 3 * math.cos(2 * ph))
        loc[1] = 0.04 * math.sin(ph)
        loc[2] = 0.02 * math.cos(2 * ph)
    elif action == "backstep":
        # Short steps backwards, shield tucked, weapon raised.
        add("thigh.L", "y", 22 * s)
        add("shin.L", "y", 26 * max(0.0, -c))
        add("thigh.R", "y", -22 * s)
        add("shin.R", "y", 26 * max(0.0, c))
        add("hips", "z", 4 * s)
        add("spine", "y", -5)
        add("upper_arm.R", "y", -14 + 3 * s)
        add("forearm.R", "y", -34)
        add("upper_arm.L", "y", -6)
        add("forearm.L", "y", 5 * math.cos(2 * ph))
        loc[2] = 0.02 * math.cos(2 * ph)
    elif action == "attack":
        spine = [-22, 14, 26, 6][i]
        arm = [26, -34, -58, -14][i]
        fore = [-14, 30, 52, 12][i]
        lunge = [-0.05, 0.10, 0.20, 0.05][i]
        add("spine", "z", spine)
        add("spine", "y", [-4, 4, 8, 2][i])
        add("upper_arm.R", "y", arm)
        add("forearm.R", "y", fore)
        add("upper_arm.L", "y", [4, -8, -12, -4][i])
        if not mounted:
            loc[0] = lunge
            add("thigh.L", "y", [-10, -25, -30, -12][i])
            add("thigh.R", "y", [10, 15, 18, 8][i])
            add("shin.R", "y", [10, 20, 25, 10][i])
    elif action == "death":
        add("root", "y", [-14, -52, -86][i])
        add("spine", "y", [-10, -12, 0][i])
        add("head", "y", [-18, -10, 0][i])
        add("head", "x", [0, 12, 25][i])
        add("upper_arm.L", "x", [20, 50, 70][i])
        add("upper_arm.R", "x", [-20, -50, -75][i])
        add("upper_arm.L", "y", [15, 0, -20][i])
        add("forearm.L", "y", [10, 20, 30][i])
        if not mounted:
            add("thigh.L", "y", [0, -32, -6][i])
            add("thigh.R", "y", [0, -26, 4][i])
            add("shin.L", "y", [0, 40, 8][i])
            add("shin.R", "y", [0, 34, 0][i])
            loc = [[-0.02, 0, 0], [-0.08, 0, 0.04], [0.05, 0, 0.16]][i]
        elif fall == "roll":
            loc = [0.0, 0.0, 0.0]
        else:
            # Thrown off to the right, clear of the horse lying flat (his
            # root hangs from the horse's body, which sinks 0.86 m).
            loc = [[0, -0.2, 0.25], [-0.2, -0.8, 0.45], [-0.3, -1.25, 0.95]][i]
    if variant and action == "attack":
        P = {}
        loc = list(MISSILE_ATTACK[variant](i, add))
    elif variant and action in ("idle", "walk"):
        MISSILE_CARRY[variant](action, i, s, c, add)
    if mounted and stand:
        pass
    elif mounted:
        if action != "death" or i == 0 or fall == "roll":
            add("thigh.L", "y", -78); add("thigh.L", "x", 16)
            add("thigh.R", "y", -78); add("thigh.R", "x", -16)
            add("shin.L", "y", 82); add("shin.R", "y", 82)
        else:
            add("thigh.L", "y", -40); add("thigh.R", "y", -30)
            add("shin.L", "y", 30); add("shin.R", "y", 20)
    P["loc"] = tuple(loc)
    return P


def horse_pose(action, i, n):
    P = {}

    def add(b, axis, deg):
        P.setdefault(b, []).append((axis, deg))

    ph = 2.0 * math.pi * i / max(n, 1)
    s, c = math.sin(ph), math.cos(ph)
    loc = [0.0, 0.0, 0.0]
    if action == "idle":
        add("neck", "y", 14)
        add("tail", "x", 6)
    elif action == "walk":
        for leg, sg in (("FL", 1), ("BR", 1), ("FR", -1), ("BL", -1)):
            add("leg." + leg, "y", -34 * s * sg)
            front = leg[0] == "F"
            bend = max(0.0, c * sg)
            add("shin." + leg, "y", (40 if front else -28) * bend)
            # Splay outward as the leg swings (seen from above the hooves
            # show beside the barrel; +x lifts a left limb outward).
            out = 10 + 14 * bend
            add("leg." + leg, "x", out if leg[1] == "L" else -out)
        add("neck", "y", 5 * math.cos(2 * ph))
        add("tail", "x", 10 * s)
        loc[2] = 0.035 * math.cos(2 * ph)
    elif action == "attack":
        pitch = [-5, -12, -8, -2][i]
        add("body", "y", pitch)
        add("leg.FL", "y", [-25, -50, -35, -10][i])
        add("shin.FL", "y", [30, 60, 45, 10][i])
        add("leg.FR", "y", [-10, -35, -45, -15][i])
        add("shin.FR", "y", [15, 50, 55, 15][i])
        add("leg.BL", "y", [8, 12, 10, 4][i])
        add("leg.BR", "y", [4, 10, 12, 2][i])
        add("neck", "y", [-6, -14, -8, 0][i])
        loc[0] = [0.0, 0.12, 0.22, 0.08][i]
    elif action == "death":
        # Sinks to the ground on its belly, legs splayed out to the sides,
        # neck and head laid down on their side: from above a horse lying
        # flat, never a profile.
        add("root", "x", [-4, -8, -10][i])
        add("neck", "y", [10, 22, 30][i])
        # Neck and head follow the body down and lie on their (left) side:
        # from above the cheek shows, not the mane and the top of the head.
        # (the head is the neck's child: it rolls with it, no turn of its own)
        add("neck", "x", [15, 45, 72][i])
        add("head", "y", [0, 8, 14][i])
        for leg in ("FL", "FR", "BL", "BR"):
            sp = [25, 55, 80][i]
            add("leg." + leg, "x", sp if leg[1] == "L" else -sp)
            add("leg." + leg, "y", ([-20, -30, -40] if leg[0] == "F" else [20, 30, 40])[i])
        add("tail", "y", [10, 30, 55][i])
        loc = [[0, 0, -0.25], [0, 0, -0.6], [0, 0, -0.86]][i]
    P["loc"] = tuple(loc)
    return P


def elephant_pose(action, i, n):
    """War elephant (step 1d). Walk: a slow amble (lateral pairs, small
    swing), body roll and bob, head nod, ears flapping, trunk and tail
    swaying. Attack: trunk raised and swung across, head down for the tusk
    gore with a lunge. Death: the whole beast (body, head, trunk: all
    children of the root) rolls onto its right side and lies flat, legs out
    toward its left (image up), the crew rolled off with the howdah."""
    P = {}

    def add(b, axis, deg):
        P.setdefault(b, []).append((axis, deg))

    ph = 2.0 * math.pi * i / max(n, 1)
    s, c = math.sin(ph), math.cos(ph)
    loc = [0.0, 0.0, 0.0]
    if action == "idle":
        add("ear.L", "z", 8)
        add("ear.R", "z", -8)
        add("trunk2", "y", -10)
        add("tail", "x", 6)
    elif action == "walk":
        # Lateral gait: both left legs swing together, then both right.
        for leg, sg in (("FL", 1), ("BL", 1), ("FR", -1), ("BR", -1)):
            add("leg." + leg, "y", -18 * s * sg)
            bend = max(0.0, c * sg)
            add("shin." + leg, "y", (22 if leg[0] == "F" else -16) * bend)
        add("body", "x", 3.0 * s)
        add("body", "z", 2.5 * s)
        add("head", "y", 4 * math.cos(2 * ph))
        flap = 16 * s
        add("ear.L", "z", 10 + flap)
        add("ear.R", "z", -10 - flap)
        add("ear.L", "x", 8 + 6 * c)
        add("ear.R", "x", -8 - 6 * c)
        add("trunk1", "z", 9 * s)
        add("trunk2", "z", 10 * s)
        add("trunk3", "y", 12 * c)
        add("tail", "x", 12 * s)
        loc[2] = 0.04 * math.cos(2 * ph)
    elif action == "attack":
        # 0 wind-up (trunk up and across to the left), 1 swing to the
        # right, 2 head down: the tusk gore, lunging, 3 recover.
        add("head", "y", [-12, 4, 18, 4][i])
        add("head", "z", [10, -12, -4, 0][i])
        add("trunk1", "y", [-55, -20, 10, -10][i])
        add("trunk1", "z", [35, -40, -10, 5][i])
        add("trunk2", "y", [-35, -25, 20, 0][i])
        add("trunk3", "y", [-30, -20, 25, 5][i])
        add("ear.L", "z", [30, 25, 15, 10][i])
        add("ear.R", "z", [-30, -25, -15, -10][i])
        add("ear.L", "x", [20, 20, 10, 5][i])
        add("ear.R", "x", [-20, -20, -10, -5][i])
        add("body", "y", [-4, 0, 4, 1][i])
        add("leg.FL", "y", [-20, -8, 6, -4][i])
        add("leg.FR", "y", [-6, -18, 6, -2][i])
        add("tail", "x", [10, -10, 15, 0][i])
        loc[0] = [-0.05, 0.15, 0.35, 0.1][i]
    elif action == "death":
        add("root", "x", [18, 52, 88][i])
        for leg in ("FL", "FR", "BL", "BR"):
            add("leg." + leg, "y", ([-10, -20, -25] if leg[0] == "F" else [10, 20, 25])[i])
            add("leg." + leg, "x", [-4, -8, -10][i])
        add("head", "y", [6, 12, 10][i])
        add("trunk1", "y", [10, 25, 30][i])
        add("trunk2", "y", [5, 10, -20][i])
        add("trunk3", "y", [0, -10, -30][i])
        add("ear.L", "z", [10, 20, 25][i])
        add("ear.R", "z", [-5, -5, 0][i])
        add("tail", "x", [10, 20, 25][i])
        loc = [[0, 0.15, 0.1], [0, 0.55, 0.42], [0, 1.0, 0.72]][i]
    P["loc"] = tuple(loc)
    return P


def engine_pose(kind, action, i, n):
    """Engines and props (step 1d). bolt / scorpion (bones stand, frame,
    arm.L, arm.R, slide): idle = drawn and loaded; attack = 0 loaded, 1
    released (arms forward, string straight, bolt gone), 2 slide run
    forward to catch the string, 3 winched half back (the game picks the
    attack frame from the engine's reload, not the clock); walk = packed
    (arms forward, frame tipped; the scorpion carried, raised); death =
    smashed and toppled. onager (frame, arm, winch): idle = arm wound down,
    stone in the sling; attack 1 the arm up against the buffer, 2 / 3
    winched down; death = arm snapped, frame askew. cart / wagon (body and
    wheels): a bob on the move, the wreck tipped with a wheel off."""
    P = {}

    def add(b, axis, deg):
        P.setdefault(b, []).append((axis, deg))

    locs = {}
    ph = 2.0 * math.pi * i / max(n, 1)
    s = math.sin(ph)
    loc = [0.0, 0.0, 0.0]
    if kind in ("bolt", "scorpion"):
        sc = 0.6 if kind == "scorpion" else 1.0
        if action == "attack":
            fwd = [0, 1, 1, 0.5][i]
            add("arm.L", "z", -40 * fwd)
            add("arm.R", "z", 40 * fwd)
            locs["slide"] = [[0, 0, 0], [0, 0, 0], [0.45 * sc, 0, 0], [0.22 * sc, 0, 0]][i]
            loc[0] = [0, -0.04, 0, 0][i] * sc
        elif action == "walk":
            add("arm.L", "z", -40)
            add("arm.R", "z", 40)
            if kind == "scorpion":
                # Carried shoulder high by its two men (poles front and back).
                loc = [0.0, 0.0, 0.42 + 0.03 * math.cos(2 * ph)]
                add("frame", "x", 3 * s)
            else:
                add("frame", "y", -10 + 2 * s)
                add("stand", "z", 3 * s)
                loc[2] = 0.02 * math.cos(2 * ph)
        elif action == "death":
            add("stand", "x", [12, 38, 70][i])
            add("frame", "y", [8, 18, 22][i])
            add("frame", "z", [6, 14, 18][i])
            add("arm.L", "y", [-20, -45, -60][i])
            add("arm.L", "z", [20, 55, 70][i])
            add("arm.R", "z", [10, 30, 45][i])
            locs["slide"] = [[0.1 * sc, 0, 0], [0.3 * sc, 0, -0.05], [0.4 * sc, 0, -0.1]][i]
            loc = [[0, 0, -0.05], [0, 0.1, -0.25 * sc], [0, 0.25 * sc, -0.5 * sc]][i]
    elif kind == "onager":
        if action == "attack":
            add("arm", "y", [0, 95, 45, 8][i])
            add("winch", "y", [0, 0, 120, 240][i])
        elif action == "walk":
            add("frame", "y", 1.5 * s)
            loc[2] = 0.02 * math.cos(2 * ph)
        elif action == "death":
            add("frame", "x", [5, 11, 14][i])
            add("frame", "y", [2, 4, 5][i])
            add("arm", "z", [15, 45, 65][i])
            add("arm", "y", [10, 30, 12][i])
            add("winch", "y", [20, 40, 40][i])
            loc = [[0, 0, -0.03], [0, 0.05, -0.1], [0, 0.1, -0.14]][i]
    elif kind == "cannon":
        # frame (carriage + wheels), barrel (slides in the carriage). attack
        # 0 loaded, 1 fired (gun and carriage thrown back, barrel kicked up),
        # 2 / 3 run out again (the game picks the frame from the reload);
        # walk = hauled (a bob); death = barrel thrown off, wheel broken.
        if action == "attack":
            loc[0] = [0, -0.3, -0.14, -0.04][i]
            locs["barrel"] = [[0, 0, 0], [-0.1, 0, 0.02], [-0.05, 0, 0], [0, 0, 0]][i]
            add("barrel", "y", [0, -5, -2, 0][i])
        elif action == "walk":
            add("frame", "z", 1.5 * s)
            add("frame", "y", 1.0 * math.cos(ph))
            loc[2] = 0.015 * math.cos(2 * ph)
        elif action == "death":
            add("frame", "x", [4, 9, 12][i])
            add("barrel", "z", [12, 38, 62][i])
            add("barrel", "y", [4, 14, 8][i])
            locs["barrel"] = [[0, 0, -0.02], [-0.15, 0.4, -0.22], [-0.3, 0.8, -0.42]][i]
            add("wheel.R", "x", [-20, -60, -88][i])
            locs["wheel.R"] = [[0, -0.08, -0.04], [0, -0.5, -0.2], [0, -0.95, -0.32]][i]
            loc = [[0, 0, -0.02], [0, 0.04, -0.08], [0, 0.08, -0.13]][i]
    elif kind in ("cart", "wagon"):
        if action == "walk":
            add("body", "x", 1.5 * s)
            add("body", "y", 1.0 * math.cos(ph))
            loc[2] = 0.015 * math.cos(2 * ph)
        elif action == "death":
            add("root", "x", [6, 14, 18][i])
            add("body", "y", [3, 7, 9][i])
            add("wheel.R", "x", [-20, -55, -82][i])
            locs["wheel.R"] = [[0, -0.1, -0.05], [0, -0.4, -0.25], [0, -0.75, -0.35]][i]
            loc = [[0, 0, -0.03], [0, 0.04, -0.1], [0, 0.08, -0.14]][i]
    P["loc"] = tuple(loc)
    if locs:
        P["locs"] = locs
    return P


def prefixed(pose, prefix):
    out = {prefix + k: v for k, v in pose.items() if k not in ("loc", "locs")}
    out["_loc"] = {prefix + "root": pose.get("loc", (0, 0, 0))}
    for b, v in pose.get("locs", {}).items():
        out["_loc"][prefix + b] = v
    return out


def riders_of(u):
    """A unit's riders: [{prefix, rig, body, seat, parent_bone, parts,
    pose, stand, fall, skip}]; step 1b's single `rider` + `rider_parts`
    is the first, prefix "r."."""
    out = []
    if u.get("rider"):
        r = dict(u["rider"])
        r["prefix"] = "r."
        r["parts"] = u.get("rider_parts", [])
        out.append(r)
    for k, r in enumerate(u.get("riders", [])):
        r = dict(r)
        r.setdefault("prefix", "r%d." % k)
        out.append(r)
    return out


def keyframe_actions(arm, u):
    """The unit's own rig by its animation set (rig "anim": humanoid,
    horse, elephant, or an engine / prop kind), plus its riders (mounted
    humanoids whose bones live in the same armature)."""
    anim = SPEC["rigs"][u["rig"]].get("anim", u["rig"])
    riders = riders_of(u)
    for act, info in SPEC["actions"].items():
        n = info["frames"]
        if not action_for(act, CUR_UID[0]):
            continue
        for i in range(n):
            if anim == "horse":
                pose = prefixed(horse_pose(act, i, n), "")
            elif anim == "elephant":
                pose = prefixed(elephant_pose(act, i, n), "")
            elif anim == "humanoid":
                pose = prefixed(humanoid_pose(act, i, n, variant=u.get("pose", "")), "")
            else:
                pose = prefixed(engine_pose(anim, act, i, n), "")
            for r in riders:
                rp = prefixed(humanoid_pose(act, i, n, mounted=True, variant=r.get("pose", ""),
                                            stand=bool(r.get("stand", 0)), fall=r.get("fall", "thrown")),
                              r["prefix"])
                pose["_loc"].update(rp.pop("_loc"))
                pose.update(rp)
            apply_pose(arm, pose, ACT_START[act] + i)


# ---------------------------------------------------------------- unit

def build_unit(uid):
    """One armature per unit; a rider's humanoid bones live in the horse's
    armature (prefix "r.", root parented to the horse's body bone, moved to
    the seat), so the rider follows the horse with no object parenting."""
    u = SPEC["units"][uid]
    CUR_UID[0] = uid
    _mats.clear()
    DYN.clear()
    VIS.clear()
    bones = rig_bones(SPEC["rigs"][u["rig"]])
    riders = riders_of(u)
    for r in riders:
        bones += rig_bones(SPEC["rigs"][r["rig"]], r["prefix"], r["seat"], r["parent_bone"])
    arm = build_armature(uid, bones)
    attach_parts(arm, SPEC["bodies"].get(u.get("body", ""), []) + u["parts"], uid,
                 skip=u.get("skip", ()))
    for r in riders:
        parts = SPEC["bodies"].get(r.get("body", ""), []) + r["parts"]
        tag = uid + "_r" if r["prefix"] == "r." else uid + "_" + r["prefix"].rstrip(".")
        attach_parts(arm, parts, tag, r["prefix"], r["seat"], skip=r.get("skip", ()))
    keyframe_actions(arm, u)
    return arm


# ---------------------------------------------------------------- camera

def setup_camera_light(sc, kind, box, elev_deg=90.0):
    """Top-down: box = [x0, x1, y0, y1] metres on the ground, image right =
    +X, image up = +Y (the man's left). Iso: box = [w, h] metres in the
    image, the camera looks north (+Y) from elev_deg above the horizon,
    centred on (0, 0, 0.8). The key light is fixed in camera space (from
    the top left, a little toward the viewer)."""
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cam = link_obj(bpy.data.objects.new("cam", cd))
    sc.camera = cam
    if kind == "top":
        x0, x1, y0, y1 = box
        w, h = x1 - x0, y1 - y0
        cam.location = ((x0 + x1) / 2, (y0 + y1) / 2, 30.0)
        cam.rotation_euler = (0, 0, 0)
    else:
        w, h = box
        e = math.radians(elev_deg)
        tgt = Vector((0, 0, 0.8))
        d = Vector((0, math.cos(e), -math.sin(e)))  # view direction
        cam.location = tgt - d * 30.0
        cam.rotation_euler = (math.pi / 2 - e, 0, 0)
    cd.ortho_scale = max(w, h)
    cd.clip_start = 0.1
    cd.clip_end = 100.0
    sc.render.resolution_x = int(round(w * PPM))
    sc.render.resolution_y = int(round(h * PPM))
    ld = bpy.data.lights.new("sun", "SUN")
    ld.energy = math.pi
    ld.angle = math.radians(8)
    sun = link_obj(bpy.data.objects.new("sun", ld))
    bpy.context.view_layer.update()
    travel_cam = Vector((0.55, -0.6, -0.75)).normalized()
    travel = cam.matrix_world.to_3x3() @ travel_cam
    sun.rotation_euler = travel.to_track_quat("-Z", "Y").to_euler()
    return cam


def render_passes(sc, path_base, mats):
    vl = bpy.context.view_layer
    for pname, mo in (("shade", None), ("mask", mats["mask"]), ("pat", mats["pat"])):
        vl.material_override = mo
        sc.render.filepath = path_base + "_" + pname + ".png"
        bpy.ops.render.render(write_still=True)
    vl.material_override = None


def render_unit(uid, out):
    t0 = time.time()
    sc = reset_scene()
    arm = build_unit(uid)
    mats = {"mask": mask_material(), "pat": pattern_material()}
    box = SPEC["units"][uid]["render_box"]
    setup_camera_light(sc, "top", box)
    d = os.path.join(out, uid)
    os.makedirs(d, exist_ok=True)
    count = 0
    for act, info in SPEC["actions"].items():
        if not action_for(act, uid):
            continue
        for i in range(info["frames"]):
            sc.frame_set(ACT_START[act] + i)
            update_dynamic(act, i)
            render_passes(sc, os.path.join(d, "%s_%d" % (act, i)), mats)
            count += 1
    info = {"view": "top", "box": box, "px_per_m": PPM,
            "size": [sc.render.resolution_x, sc.render.resolution_y],
            "anchor": [(0 - box[0]) * PPM, (box[3] - 0) * PPM]}
    json.dump(info, open(os.path.join(d, "info.json"), "w"), indent=1)
    dt = time.time() - t0
    print("SPRITES unit %s: %d frames x 3 passes in %.1f s" % (uid, count, dt))
    return dt


def render_iso(out):
    from bpy_extras.object_utils import world_to_camera_view
    t0 = time.time()
    iso = SPEC["iso"]
    uid = iso["unit"]
    sc = reset_scene()
    arm = build_unit(uid)
    mats = {"mask": mask_material(), "pat": pattern_material()}
    cam = setup_camera_light(sc, "iso", iso["box"], iso["elevation_deg"])
    d = os.path.join(out, "iso_" + uid)
    os.makedirs(d, exist_ok=True)
    act = iso["action"]
    n = SPEC["actions"][act]["frames"]
    for k in range(iso["directions"]):
        arm.rotation_euler = (0, 0, 2.0 * math.pi * k / iso["directions"])
        for i in range(n):
            sc.frame_set(ACT_START[act] + i)
            update_dynamic(act, i)
            render_passes(sc, os.path.join(d, "d%d_%d" % (k, i)), mats)
    bpy.context.view_layer.update()
    p = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
    W, H = sc.render.resolution_x, sc.render.resolution_y
    info = {"view": "iso", "elevation_deg": iso["elevation_deg"],
            "directions": iso["directions"], "action": act,
            "px_per_m": PPM, "size": [W, H],
            "anchor": [p.x * W, (1.0 - p.y) * H],
            "dir_doc": "d0 faces east (+X, image right), then counter-clockwise in 45 degree steps (d2 faces north, away from the camera)"}
    json.dump(info, open(os.path.join(d, "info.json"), "w"), indent=1)
    dt = time.time() - t0
    print("SPRITES iso %s: %d directions x %d frames x 3 passes in %.1f s"
          % (uid, iso["directions"], n, dt))
    return dt


def main():
    a = parse_args()
    os.makedirs(a["out"], exist_ok=True)
    open(os.path.join(a["out"], ".gdignore"), "w").close()
    times = {}
    for uid in a["units"]:
        times[uid] = render_unit(uid, a["out"])
    if a["iso"]:
        times["iso"] = render_iso(a["out"])
    print("SPRITES done:", json.dumps({k: round(v, 1) for k, v in times.items()}))


main()
