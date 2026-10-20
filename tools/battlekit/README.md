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

## West town pieces (phase W, 2026-10-16)

```
blender -b --factory-startup -P tools/battlekit/build.py -- --ppm 8 --out tools/battlekit/_frames \
    --pieces tavern,shop,store,warehouse,chandler,shack,leanto,governor,lowwall,stakes,crates,pier
python3 tools/battlekit/pack.py && godot --headless --path . --import
```

`PIECES_W` in `build.py`: the West open towns' buildings (street front at +y, the piece's outer side,
so `game/battlekit.gd` `_build_west` turns porches, awnings and goods to the road), yard walls, the
stake palisade, crates and jetties. `pack.py` appends them after the older pieces (the older crops are
pixel-identical after a repack; only their places in the atlas move). The kit shader holds 64 rects
(`game/battlekit.gdshader`): 61 are used.

## The harbour fort's magazine (slice 2c, 2026-10-16)

```
blender -b --factory-startup -P tools/battlekit/build.py -- --ppm 8 --out tools/battlekit/_frames --pieces magazine
python3 tools/battlekit/pack.py && godot --headless --path . --import
```

`b_magazine`: a low stone vault, buttressed, an iron-banded door at +y (the parade). Packed last (62 of the
shader's 64 rects). The fort's walls are the existing `wall_10_2` pieces laid along its bastioned trace.

## Landmark and civic pieces, block 2 (same-city work, phase B, 2026-10-20)

The overworld's landmark and civic pieces as battle kit pieces, built from the minis' own geometry
(`tools/structures/spec.json` parts lists through `tools/battlekit/spec_pieces.py`, which reuses the
structures builder's expansion and part meshes; nothing is modelled twice). Each piece is turned 180 degrees
(the minis' front is south, the kit's is image up = +y, like the West pieces), `zex` is not applied
(true heights; a piece taller than the kit's 20 m range is squashed to 19.5 m, noted in its `.json` `info`)
and the minis' materials map to kit materials (`primary` -> roof R, whitewash / marble -> plaster G,
secondary / accent -> trim B; coquina, gold, black, brick, jade are new kit colours). The canvas is sized from
the geometry. Names: `lm_*` landmarks (morro, morro_sj, fuerza, san_felipe, harbour_fort, san_marcos, alcazar,
ulua, fort_charles, rock_fort, gallows, tavern, careened, byrsa, cothon, euryalus, acropolis, greek_temple,
baluarte, bast_wall; the town's sea wall is `bast_wall` runs with a `baluarte` at intervals), `cv_*` civic
(temple, basilica, chapel, church, cathedral, twin_cathedral, mansion, capitol, tower_rome, itza_temple,
maya_pyramid, fort). `magazine` is in the main atlas already; barracks has no minis piece (drawn as `longhouse`).

```
L=$(python3 -c "import re;s=open('tools/battlekit/build.py').read();print(','.join(re.findall(r'\"((?:lm|cv)_\w+)\":',re.search(r'LANDMARK_SRC = \{(.*?)\n\}',s,re.S).group(1))))")
blender -b --factory-startup -P tools/battlekit/build.py -- --ppm 8  --out tools/battlekit/_frames --pieces $L
blender -b --factory-startup -P tools/battlekit/build.py -- --ppm 12 --out DIR12 --pieces $L   # close view / mockup only
python3 tools/battlekit/pack.py --block 2 && godot --headless --path . --import
python3 tools/battlekit/mockup.py board --set landmarks --ppm 7 --frames DIR12 --out OUT      # the sheet
```

`pack.py --block 2` writes `assets/battlekit/atlas2_{albedo,nrm,low}.png` (2048x1024 at 8 px/m; the main
atlas stays 1024x1024 and the shader's 64 rects are untouched) and `game/battlekit_atlas2.gd` (RECT, ANCHOR
as the main table, and `FOOT` [x0, y0, x1, y1, height] in metres, y down, the front at y0). 12 px/m renders are
not packed. In the game: `BattleKit.draw_piece(canvas, name, pos_m, yaw, tint, px_per_m)` (static; the pre-lit
4 px/m atlas, any CanvasItem inside `_draw`, no shader), `BattleKit.has_piece(name)`, `BattleKit.piece_foot(name)`.
Used by nothing yet: the map builder (phase C) will add the shaded MultiMesh path.
