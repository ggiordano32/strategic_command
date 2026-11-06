"""The battle kit's pieces as low-poly meshes for the 3D battle view (step two, 2026-11-06; docs/design/art_pipeline.md
"The 3D battle view, step two: houses as geometry"). Runs inside Blender and builds every piece with build.py's own
builders (nothing is modelled twice; P.detail3d adds the doors, windows and shutters the sprites never had), then per piece:

- joins its parts (one Blender object per kit material) into one mesh, drops the faces under the ground (the bottoms),
  pushes the foot down SKIRT m (so a house on a slope never floats), triangulates, and collapses it to its budget when
  over (TRIS_HOUSE / TRIS_ROCK / TRIS_BIG);
- unwraps it (smart project) at DENSITY px per metre of surface and bakes its painted albedo (the kit's own emission
  materials: noise, courses, tiles, planks, the masked parts grey for the culture's palette) times a soft ambient
  occlusion (a ground plane under it: the darker foot, the eaves' shade) into a small texture;
- writes <out>/<piece>.json (the Godot frame: x the piece's right, y up, z = -its +y (the outer / street side is -z);
  positions in the piece's own frame, metres; per vertex normal, uv in its texture, the mask class 1.0 none / 0.7 roof /
  0.4 plaster / 0.1 accent as the kit's atlases carry it; the footprint's centre as the oblique sheet takes it (the
  bounds of the vertices up to 1 m high), the height, the triangle count) and <out>/<piece>.png.

tools/battlekit/kit3d_res.gd then packs the textures into one atlas and the meshes into one resource
(assets/battlekit_ob/kit3d.res, kit3d_albedo.png).

    ~/.local/bin/blender -b --factory-startup -P tools/battlekit/export3d.py -- [--pieces a,b] [--out DIR]
    godot --headless --path . --script res://tools/battlekit/kit3d_res.gd [-- --frames DIR]
"""
import bpy
import bmesh
import importlib.util
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
_sp = importlib.util.spec_from_file_location("bk_build", os.path.join(HERE, "build.py"))
B = importlib.util.module_from_spec(_sp)
_sp.loader.exec_module(B)

DENSITY = 7.0       # texture px per metre of surface (the sprites are 8 px per metre)
DENSITY_BIG = 3.5   # the landmarks and civic pieces (40 to 90 m across, one or two in a town)
SKIRT = 1.2         # metres the foot goes on down into the board
TRIS_HOUSE = 1400
TRIS_ROCK = 260
TRIS_BIG = 3000     # landmarks, civic pieces, the governor's house
TEX_MIN, TEX_MAX = 32, 512

# Every piece the 3D view drew as a card (step one) and now draws as a mesh: the block 1 pieces the kit places
# (houses, huts, the West town's buildings, towers, the bastion, the props, the rocks) and the block 2 landmarks.
# Not here: the walls (rows), the gates (rows in the 3D view), the trees and bushes (cards: they read alike round),
# the cliffs (no battle places them), the mockup-only pieces.
BLOCK1 = ["tower_round", "tower_sq", "tower_timber", "bastion",
          "house_gable_s", "house_gable_m", "house_gable_l", "house_hip_s", "house_hip_m", "longhouse", "house_L",
          "hut_round", "hut_thatch", "house_flat_s", "house_flat_m", "church", "temple", "stall", "well", "cart",
          "barrels", "rock_a", "rock_b", "rock_c",
          "tavern", "shop", "store", "warehouse", "chandler", "shack", "leanto", "governor", "lowwall", "stakes",
          "crates", "pier", "magazine"]
ROCKS = ("rock_a", "rock_b", "rock_c")


def mask_class(key):
    mc = B.MATS[key][2]
    return 1.0 if mc is None else (0.7, 0.4, 0.1)[mc]


def lookup(name):
    for tab in (B.PIECES, B.PIECES_W, B.PIECES_L):
        if name in tab:
            return tab[name]
    raise KeyError(name)


def budget(name):
    if name in ROCKS:
        return TRIS_ROCK
    if name.startswith("lm_") or name.startswith("cv_") or name in ("governor", "temple", "church", "bastion"):
        return TRIS_BIG
    return TRIS_HOUSE


def export_piece(name, out):
    S, fn = lookup(name)
    sc = B.reset()
    P = B.Piece()
    P.info = None
    P.detail3d = True
    fn(P)
    objs = P.finish(sc)
    if not objs:
        return None
    # The footprint's centre as the oblique sheet's anchor (build.py render_ob: the vertices up to 1 m high).
    pts = [v.co.copy() for ob in objs for v in ob.data.vertices]
    low = [p for p in pts if p.z <= 1.0] or pts
    foot = [min(p.x for p in low), min(p.y for p in low), max(p.x for p in low), max(p.y for p in low)]
    height = max(p.z for p in pts)
    keys = {}
    for ob in objs:
        keys[ob.material_slots[0].material.name] = ob["bk_key"]
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
    # the bottoms (faces looking down at the ground) never show
    gone = [f for f in bm.faces if f.normal.z < -0.95 and f.calc_center_median().z < 0.25]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    if name not in ROCKS:
        for v in bm.verts:
            if v.co.z < 0.03:
                v.co.z = -SKIRT
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    tris = len(me.polygons)
    lim = budget(name)
    print("MESH3D_RAW %s %d" % (name, tris))
    if tris > lim:
        md = ob.modifiers.new("dec", "DECIMATE")
        md.ratio = lim / float(tris)
        md.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=md.name)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
    # (the skirt below the ground counts a tenth: it shows only where the board falls away)
    area = sum(p.area * (0.1 if max(me.vertices[v].co.z for v in p.vertices) < 0.05 else 1.0) for p in me.polygons)
    dens = DENSITY_BIG if (name.startswith("lm_") or name.startswith("cv_")) else DENSITY
    side = int(math.ceil(math.sqrt(area) * dens / 0.72 / 8.0)) * 8
    side = max(TEX_MIN, min(TEX_MAX, side))
    # unwrap
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=2.5 / side, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, rotate_method="ANY", scale=True,
                            merge_overlap=False, margin_method="FRACTION", margin=2.5 / side, shape_method="AABB")
    bpy.ops.object.mode_set(mode="OBJECT")
    # bake: emission (the painted albedo) and ambient occlusion against a ground plane
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16
    sc.render.bake.margin = 3
    sc.render.bake.margin_type = "EXTEND"
    imgs = {}
    for kind in ("emit", "ao"):
        img = bpy.data.images.new("%s_%s" % (name, kind), side, side, alpha=True, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        imgs[kind] = img
    plane = None
    for kind in ("emit", "ao"):
        for slot in ob.material_slots:
            nt = slot.material.node_tree
            n = nt.nodes.get("bake_img") or nt.nodes.new("ShaderNodeTexImage")
            n.name = "bake_img"
            n.image = imgs[kind]
            nt.nodes.active = n
        if kind == "ao":
            bpy.ops.mesh.primitive_plane_add(size=400.0, location=(0, 0, 0.0))
            plane = bpy.context.active_object
            bpy.ops.object.select_all(action="DESELECT")
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            sc.world = sc.world or bpy.data.worlds.new("w")
            sc.cycles.samples = 64
            sc.world.light_settings.distance = 4.0
        bpy.ops.object.bake(type="EMIT" if kind == "emit" else "AO", margin=3, use_clear=True)
    emit = np.array(imgs["emit"].pixels[:], dtype=np.float32).reshape(side, side, 4)
    ao = np.array(imgs["ao"].pixels[:], dtype=np.float32).reshape(side, side, 4)[..., 0]
    col = emit[..., :3] * (0.62 + 0.38 * np.clip(ao, 0.0, 1.0))[..., None]
    rgba = np.concatenate([np.clip(col, 0, 1), np.ones((side, side, 1), np.float32)], -1)
    out_img = bpy.data.images.new(name + "_out", side, side, alpha=True)
    out_img.colorspace_settings.name = "Non-Color"
    out_img.pixels[:] = rgba.ravel()
    out_img.filepath_raw = os.path.join(out, name + ".png")
    out_img.file_format = "PNG"
    out_img.save()
    # the arrays: unique corners (position, normal, uv, class)
    me = ob.data
    uvl = me.uv_layers.active.data
    cn = me.corner_normals
    mats = [keys.get(s.material.name, "stone") for s in ob.material_slots]
    vid = {}
    V, Nn, UV, C, I = [], [], [], [], []
    for p in me.polygons:
        cls = mask_class(mats[p.material_index])
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            nn = cn[li].vector
            uv = uvl[li].uv
            k = (round(co.x, 3), round(co.y, 3), round(co.z, 3), round(nn.x, 2), round(nn.y, 2), round(nn.z, 2),
                 round(uv.x, 4), round(uv.y, 4), cls)
            q = vid.get(k)
            if q is None:
                q = len(V) // 3
                vid[k] = q
                V += [k[0], k[2], -k[1]]
                Nn += [k[3], k[5], -k[4]]
                UV += [k[6], 1.0 - k[7]]
                C.append(cls)
            I.append(q)
    # (Godot winds front faces clockwise: turn every triangle round)
    for t in range(0, len(I), 3):
        I[t + 1], I[t + 2] = I[t + 2], I[t + 1]
    fc = [(foot[0] + foot[2]) * 0.5, (foot[1] + foot[3]) * 0.5]
    info = {"name": name, "foot_m": [round(v, 3) for v in foot], "fc": [round(fc[0], 3), round(fc[1], 3)],
            "height_m": round(height, 3), "tris": len(I) // 3, "verts": len(V) // 3, "tex": side,
            "v": V, "n": Nn, "uv": UV, "c": C, "i": I}
    with open(os.path.join(out, name + ".json"), "w") as f:
        json.dump(info, f, separators=(",", ":"))
    if plane is not None:
        bpy.data.objects.remove(plane)
    return info


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    pieces = BLOCK1 + list(B.LANDMARK_SRC)
    out = os.path.join(HERE, "_frames3d")
    i = 0
    while i < len(argv):
        if argv[i] == "--pieces":
            pieces = argv[i + 1].split(",")
            i += 1
        elif argv[i] == "--out":
            out = os.path.abspath(argv[i + 1])
            i += 1
        i += 1
    os.makedirs(out, exist_ok=True)
    tot_t = 0
    tot_px = 0
    for n in pieces:
        info = export_piece(n, out)
        if info:
            tot_t += info["tris"]
            tot_px += info["tex"] ** 2
            print("MESH3D %s tris=%d verts=%d tex=%d" % (n, info["tris"], info["verts"], info["tex"]))
    print("MESH3D total tris=%d tex_px=%d" % (tot_t, tot_px))


main()
