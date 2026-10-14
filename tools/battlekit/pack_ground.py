#!/usr/bin/env python3
"""The battle ground's tiling textures for game/terrain.gdshader (splatted ground): grass, dry grass,
dirt, rock, sand, plough from kitlib.make_ground, 256 px each (one tile = 64 m in the game), written
to assets/battlekit/ground/<name>.png (RGBA8, opaque). Prints each tile's mean colour (the shader
divides by it so a tile modulates the palette's colour instead of replacing it)."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import kitlib  # noqa: E402

out = os.path.join(ROOT, "assets", "battlekit", "ground")
os.makedirs(out, exist_ok=True)
tiles = kitlib.make_ground(3)
for name in ("grass", "dry", "dirt", "rock", "sand", "plough"):
    a = tiles[name][0]
    n = a.shape[0] // 2
    a = a.reshape(n, 2, n, 2, 3).mean((1, 3))      # 512 -> 256
    mean = a.reshape(-1, 3).mean(0)
    kitlib.save_png(os.path.join(out, name + ".png"), a)
    print("%s vec3(%.3f, %.3f, %.3f)" % (name, *mean))
