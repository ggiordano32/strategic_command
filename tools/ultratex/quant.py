#!/usr/bin/env python3
"""Blender (CPU): quantise an UltraTex albedo with hy_paint.py's bake and render raw + quantised (bust + mini).
  blender -b --factory-startup -P tools/ultratex/quant.py -- NAME MESH.glb OUT_DIR WORK_DIR
MESH.glb = the mesh the UltraTex run used (fake repo tree under OUT_DIR so hy_paint never reads assets/).
OUT_DIR/NAME/{hy_mesh.npz,hy_raw.png} from prep_npz.py.  WORK_DIR/NAME/labels.png (optional, the old bake's)."""
import importlib.util, os, sys
argv = sys.argv[sys.argv.index("--") + 1:]
name, mesh, out, work = argv[:4]
here = os.path.dirname(os.path.abspath(__file__))
hy = os.path.abspath(os.path.join(here, "..", "hunyuan", "hy_paint.py"))
sys.path.insert(0, os.path.dirname(hy))
spec = importlib.util.spec_from_file_location("hy_paint_lib", hy)
hp = importlib.util.module_from_spec(spec); spec.loader.exec_module(hp)
fake = os.path.join(out, "fakerepo")
os.makedirs(os.path.join(fake, "assets", "characters", name), exist_ok=True)
dst = os.path.join(fake, "assets", "characters", name, "mesh.glb")
if os.path.lexists(dst):
    os.remove(dst)
os.symlink(os.path.abspath(mesh), dst)
hp.REPO = fake
a = {"stage": "bake", "name": name, "work": work, "out": out, "variant": "turbo", "offload": False}
hp.bake(a)
import numpy as np
ns, _t = hp.load_lib()
wd = os.path.join(out, "work", name)
lab = np.rint(ns["read_vup"](os.path.join(wd, "labels.png"))[..., 0] * 255).astype(np.int32)
alb = ns["read_vup"](os.path.join(wd, "albedo.png"))[..., :3].astype(np.float64)
raw = ns["read_vup"](os.path.join(out, name, "albedo_reproj.png"))[..., :3].astype(np.float64)
hp.render_set(a, "raw", name, raw, lab, "mini,bust")
hp.render_set(a, "quant", name, alb, lab, "mini,bust")
print("done")
