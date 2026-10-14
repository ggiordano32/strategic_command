# Battle kit (walls, towers and gates are in the game since 2026-10-14)

Modular top-down battle-map pieces (walls, towers, gates, palisade, bastion,
houses, church, temple, props, trees, rocks, cliffs) built procedurally in
Blender and rendered as G-buffer passes, plus a numpy compositor that lights
them (NW key, soft cast shadow from the height field, AO, rim, outline) and
mocks up scenes on battle screenshots. The game uses the wall / tower / gate / palisade pieces
(see below); houses, trees, rocks and cliffs are still mockup only.

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

## In the game (Level 1, phase 1)

```
blender -b --factory-startup -P tools/battlekit/build.py -- --ppm 8 --out tools/battlekit/_frames \
    --pieces wall_8_2,wall_10_2,wall_12_2,wall_12_4,wall_14_4,pal_8,pal_10,pal_12,tower_round,tower_sq,\
tower_timber,gate_c,gate_o,gate_b,pgate_c,pgate_o,pgate_b,bastion
python3 tools/battlekit/pack.py      # -> assets/battlekit/atlas_{albedo,nrm,low}.png, game/battlekit_atlas.gd
godot --headless --path . --import   # writes the .import files' uids
```

Wall pieces are built to the sim's geometry (thickness t, parapet pp, a 4 m walkway), outer face up.
Gate pieces have the passage (hw 4) and depth 11 m and are scaled to the gate. The atlases are
`atlas_albedo` (RGBA), `atlas_nrm` (R,G normal xy, B height / 20 m, A mask class 1.0 none / 0.7 roof /
0.4 plaster / 0.1 accent; never 0) and `atlas_low` (pre-lit, 4 px/m, Graphics Low). Texture memory:
about 4.5 MB (2 + 2 + 0.5) plus the baked shadow (one RGBA8 texture at 2 cells/m over the city).
Design note: docs/DESIGN.md "Battle kit walls, towers and gates".
