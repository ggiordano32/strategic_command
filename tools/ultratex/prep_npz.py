#!/usr/bin/env python3
"""hunyuan-venv python: UltraTex output GLB (same mesh, keep_existing UVs) -> OUT/NAME/hy_mesh.npz + hy_raw.png in the
form tools/hunyuan/hy_paint.py bake / render read (Blender Z-up vertices, v-up uv, image as the glTF stores it).
  ~/.venvs/hunyuan/bin/python -I tools/ultratex/prep_npz.py NAME OUT.glb OUT_DIR"""
import os, sys
import numpy as np, trimesh
from PIL import Image
name, glb, out = sys.argv[1:4]
m = trimesh.load(glb, force="mesh", process=False)
d = os.path.join(out, name); os.makedirs(d, exist_ok=True)
v = np.asarray(m.vertices, np.float64)
np.savez(os.path.join(d, "hy_mesh.npz"), v=np.stack([v[:, 0], -v[:, 2], v[:, 1]], 1),
         f=np.asarray(m.faces, np.int32), uv=np.asarray(m.visual.uv, np.float64))
m.visual.material.baseColorTexture.convert("RGB").save(os.path.join(d, "hy_raw.png"))
print("ok", len(m.faces), "faces")
