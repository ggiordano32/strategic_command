"""Projection bake on a fitted mesh (Blender, CPU): the second half of paint_render.build_texture, started from the
committed `assets/characters/NAME/mesh.glb` (the silfit.py result) instead of a raw.glb.

    ~/.local/bin/blender -b --factory-startup -P tools/hunyuan/silfit_bake.py -- NAME --work W --out WORK_OUT

W/NAME/{front,left,right,back}.png: the sheet crops.  The mesh keeps its vertices and triangle order; it gets
a new atlas (texture.assign_views / build_atlas on the fitted geometry, so the charts follow the fitted shape) and
the bake of texture.py (same rules and thresholds as paint_render), written to WORK_OUT/NAME/{albedo,labels}.png
(+ the crops, linked, so WORK_OUT can be used as `--work` of hy_paint.py bake / hybrid) and exported over
assets/characters/NAME/mesh.glb with the albedo embedded.  The per-view fit printed ("fit front|left|right|back")
should now read scale ~1.0 / offset ~0.
"""
import os
import shutil
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hy_paint  # noqa: E402  (import-safe: its main is guarded)

REPO = hy_paint.REPO


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    name = argv[0]
    a = {"work": None, "out": None}
    for i, k in enumerate(argv):
        if k in ("--work", "--out"):
            a[k[2:]] = argv[i + 1]
    ns, texture = hy_paint.load_lib()
    cfg = ns["CHARS"][name]
    names = list(cfg["palette"].keys())
    pal_rgb = np.array([ns["hex_rgb"](cfg["palette"][n][0]) for n in names])
    rgb_to_lab, hex_rgb = ns["rgb_to_lab"], ns["hex_rgb"]
    wd = os.path.join(a["out"], name)
    os.makedirs(wd, exist_ok=True)
    for k in ns["VIEWS"]:
        dst = os.path.join(wd, k + ".png")
        if not os.path.exists(dst):
            os.symlink(os.path.join(a["work"], name, k + ".png"), dst)
    mesh_path = os.path.join(REPO, "assets", "characters", name, "mesh.glb")
    t0 = time.time()
    ob = ns["import_glb"](mesh_path)
    me = ob.data
    me.calc_loop_triangles()
    v_s, tri_s, _e, _n = ns["mesh_arrays"](me)           # split at the old UV seams
    key = np.round(v_s / 1e-5).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.ravel()
    v = v_s[first]
    tri = inv[tri_s]                                      # welded topology, same triangle order
    fn = np.cross(v[tri[:, 1]] - v[tri[:, 0]], v[tri[:, 2]] - v[tri[:, 0]])
    nrm = np.zeros_like(v)
    for k in range(3):
        np.add.at(nrm, tri[:, k], fn)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
    zmin, zmax = v[:, 2].min(), v[:, 2].max()
    H = zmax - zmin
    views = {k: ns["View"](k, ns["load_view"](os.path.join(wd, k + ".png"))) for k in ns["VIEWS"]}
    head_z = cfg.get("head_z", 0.82)
    T = 1024
    ucen = {k: ns["silhouette_ucen"](vw, v, zmin, H) for k, vw in views.items()}
    for k, vw in views.items():
        ns["fit_view"](vw, v, zmin, H, ucen[k])
    own, vis = texture.assign_views(v, tri, nrm, views, ucen, zmin, H, head_z)
    uvc, scale = texture.build_atlas(v, tri, own, views, zmin, H, head_z, T, cfg.get("head_density", 2.0))
    print("  atlas: views owning %s tris, body %.0f px per figure height" % (np.bincount(own, minlength=4).tolist(), scale * H))
    ns["set_uv"](me, uvc)
    order = np.concatenate([np.nonzero(~vis)[0], np.nonzero(vis)[0]])
    valid, pos, nr, tid = texture.rasterize(uvc, v[tri], nrm[tri], T, order)
    vid = np.where(valid, own[np.maximum(tid, 0)], 0)
    print("  rasterised %d texels" % valid.sum())
    ANCHORS, ZBAND = ns["ANCHORS"], ns["ZBAND"]
    anc = [(i, hx) for i, n in enumerate(names) for hx in ([ANCHORS[name][n]] if isinstance(ANCHORS[name][n], str) else ANCHORS[name][n])]
    owner = np.array([i for i, _ in anc])
    pal_lab = rgb_to_lab(np.array([hex_rgb(hx) for _, hx in anc]))
    bands = {names.index(k): b for k, b in ZBAND[name].items() if k in names}
    head_ids = [names.index(n) for n in cfg["head_labels"] if n in names]
    detail_ids = [names.index(n) for n in ("skin", "hair") if n in names]
    alias = {names.index(a_): names.index(b_) for a_, b_ in cfg.get("head_alias", {}).items() if a_ in names and b_ in names}
    lock = cfg.get("hat_lock", False)
    rules = {"hat_z": cfg.get("hat_z", 2.0) if lock else 2.0,
             "zone_ids": [names.index(n) for n in cfg.get("hat_zone", []) if n in names] if lock else [],
             "hat_ids": [names.index(n) for n in cfg.get("hat_labels", []) if n in names] if lock else [],
             "mouth": cfg.get("mouth_fix", False), "skin_prune": cfg.get("skin_prune", False)}
    stats = {}
    albedo, labels, _ = texture.bake(valid, pos, nr, vid, views, ucen, zmin, H, pal_rgb, pal_lab, owner, bands, names,
                                     rgb_to_lab, ns["srgb_to_lin"], ns["lin_to_srgb"], shift=cfg.get("shift"),
                                     debug=bool(os.environ.get("HY_DEBUG")), head_ids=head_ids,
                                     face_z=cfg.get("face_z", 0.87), head_z=head_z, alias=alias, rules=rules,
                                     detail_ids=detail_ids, stats=stats)
    print("  label components removed: %d; ink texels: %d; hat strays %d; mouth specks %d; skin pruned %d" % (
        stats.get("removed", 0), stats.get("ink_texels", 0), stats.get("hat_stray", 0), stats.get("mouth", 0), stats.get("skin_pruned", 0)))
    albedo, _c = texture.dilate_into(albedo, valid, 8)
    labels = texture.dilate_labels(labels, valid, 8)
    ap = os.path.join(wd, "albedo.png")
    ns["write_vup"](ap, albedo)
    ns["write_vup"](os.path.join(wd, "labels.png"), np.stack([labels / 255.0] * 3, -1))
    ns["write_vup"](os.path.join(wd, "maskmap.png"), ns["mask_image"](labels, names, cfg))
    ns["export_mesh"](ob, ap, mesh_path)
    print("[%s] fitted-mesh bake done in %.1fs; mesh.glb %.2f MB" % (name, time.time() - t0, os.path.getsize(mesh_path) / 2 ** 20))


main()
