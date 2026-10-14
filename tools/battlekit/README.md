# Battle kit (style mockup, not integrated)

Modular top-down battle-map pieces (walls, towers, gates, palisade, bastion,
houses, church, temple, props, trees, rocks, cliffs) built procedurally in
Blender and rendered as G-buffer passes, plus a numpy compositor that lights
them (NW key, soft cast shadow from the height field, AO, rim, outline) and
mocks up scenes on battle screenshots. Nothing here is used by the game yet.

```
~/.local/bin/blender -b --factory-startup -P tools/battlekit/build.py -- \
    [--pieces wall_m,tower_round] [--ppm 8] [--tilt 0] --out DIR     # --tilt 40 = iso option
python3 tools/battlekit/mockup.py board    --frames DIR --out OUT    # kit boards A and B
python3 tools/battlekit/mockup.py cultures --frames DIR --out OUT    # recolour through the mask pass
python3 tools/battlekit/mockup.py ground   --out OUT                 # ground tiles + slope / height splat demo
python3 tools/battlekit/mockup.py iso      --frames ISO_DIR --out OUT
python3 tools/battlekit/mockup.py scene hill|coast|close|valley --style A,B --shots SHOTS --frames DIR --out OUT
```

Per piece: `_albedo` (masked parts grey), `_normal`, `_height` (16 bit, z / 20 m),
`_mask` (R roof / awning, G plaster, B accent) and `.json`. Pieces are rendered
unrotated and lit afterwards, so any rotation or light direction works.
Close view scenes need pieces rendered with `--ppm 12` (dir `<frames>12`).
Style A: grounded painterly. Style B: tabletop diorama. `kitlib.py` holds the
ground textures (tileable numpy), placement, lighting and shadow code.
