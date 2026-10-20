"""Landmark and civic pieces for the battle kit, built from the overworld minis' geometry
(tools/structures/spec.json, the same parts lists: nothing is modelled twice). Loaded by
tools/battlekit/build.py inside Blender (not a stand-alone script).

The spec expansion and the part meshes come from tools/structures/build.py itself: its source up to
the materials section is exec'd here (that file runs its renderer at import, so it cannot be imported).
Each part is built, turned 180 degrees about z (the minis' front is south, the kit's front is image
up = +y), its heights squashed when the piece passes the kit's 20 m height range, and appended to the
kit Piece under a kit material (MAP below: the masked kinds stay masked, so primary -> roof R,
whitewash / marble -> plaster G, secondary / accent -> trim B).
"""
import json
import math
import os

from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
STRUCT = os.path.join(os.path.dirname(HERE), "structures")

_ns = {"__file__": os.path.join(STRUCT, "build.py"), "__name__": "structures_build"}
_src = open(os.path.join(STRUCT, "build.py")).read()
_src = _src.split("# ---------------------------------------------------------------- materials")[0]
exec(compile(_src, os.path.join(STRUCT, "build.py"), "exec"), _ns)
SPEC = _ns["SPEC"]
expand = _ns["expand"]
build_part_mesh = _ns["build_part_mesh"]

# spec material -> kit material key (tools/battlekit/build.py MATS)
MAP = {
    "primary": "roof", "secondary": "trim", "accent": "trim",
    "whitewash": "plaster", "marble": "plaster", "wall_ochre": "plaster", "ochre": "plaster",
    "pastel_blue": "plaster", "pastel_green": "plaster", "bone": "plaster",
    "coquina": "coquina", "stone_lt": "stone_l", "stone": "stone", "cobble": "cobble",
    "rock": "rock", "rock_dk": "rock_d", "sand": "earth", "dirt": "earth", "mud": "earth", "earth": "earth",
    "wood": "timber", "plank": "timber", "palisade": "timber", "canoe": "timber", "hull_lt": "timber",
    "dark_wood": "timber_d", "hull_dk": "timber_d", "tile_edge": "timber_d",
    "thatch": "thatch", "rope": "hay", "iron": "metal", "black": "black",
    "gold": "gold", "glass": "gold", "brick": "brick", "jade": "jade",
    "water_dk": "water", "grass": "turf", "grass_dk": "turf", "leaf": "leaf_a", "palm_leaf": "palm",
    "red_cloth": "cloth", "sail": "cloth",
}
GROUND_PAINT = ("dirt", "cobble", "grass_dk", "grass", "sand")
HMAX = 19.5


def _ground(p, mk):
    if p.get("ground"):
        return True
    if mk not in GROUND_PAINT:
        return False
    if p["s"] == "box":
        return p["sz"][2] <= 0.4
    return p["s"] == "poly" and p.get("z1", 0.0) <= 0.3


def build(P, struct):
    """Add the minis piece `p_<struct>__y0` to the kit Piece P; returns the canvas size (m) and
    fills P.info with the bounds in the kit frame."""
    st = SPEC["structures"]["p_%s__y0" % struct]
    flat = expand(st["parts"], Matrix.Identity(4), {}, [])
    rot = Matrix.Rotation(math.pi, 4, "Z")
    built = []
    zmax = 0.0
    for p, M, mp in flat:
        mk = mp.get(p["m"], p["m"])
        if _ground(p, mk):
            continue
        bm = build_part_mesh(p, rot @ M)
        for v in bm.verts:
            zmax = max(zmax, v.co.z)
        built.append((MAP.get(mk, "stone") if p["s"] != "cone" or mk != "primary" else "roof_s", bm))
    zs = min(1.0, HMAX / zmax) if zmax > 0 else 1.0
    xs, ys = [], []
    for key, bm in built:
        verts = []
        idx = {}
        for v in bm.verts:
            idx[v.index] = len(verts)
            verts.append((v.co.x, v.co.y, v.co.z * zs))
            xs.append(v.co.x)
            ys.append(v.co.y)
        faces = [[idx[v.index] for v in f.verts] for f in bm.faces]
        P.mesh(key, verts, faces)
        bm.free()
    ext = max(max(abs(x) for x in xs), max(abs(y) for y in ys))
    S = int(math.ceil(2 * ext + 3))
    S += S % 2
    P.info = {"src": struct, "x0": min(xs), "x1": max(xs), "y0": min(ys), "y1": max(ys),
              "zmax": zmax * zs, "zsrc": zmax, "zscale": zs}
    return S
