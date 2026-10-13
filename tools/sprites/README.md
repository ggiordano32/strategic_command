# Sprite pipeline (step 1a)

Units are written as data in `spec.json`; Blender builds them from code and
renders the frames; `pack.py` makes the sheets and the manifest the game
reads. No hand modelling, no downloaded models.

```
spec.json          units (parts lists), rigs, bodies, materials, palettes, iso test
build.py           Blender script: meshes, armature, actions, renders (3 passes a frame)
pack.py            stdlib Python: outline, crop, sheets, manifest (+ --contact preview)
preview/           Godot scene: sheets recoloured per palette at 3 zooms, iso 8 directions
_frames/           raw renders (git-ignored, .gdignore'd)
../../assets/sprites/   <unit>_shade.png, <unit>_mask.png, iso_*.png, manifest.json
```

## Run

```sh
# all units + the iso test (about 14 s on the RTX 3070, EEVEE; the first run
# after a driver / Blender update adds ~10 s of shader compiling)
~/.local/bin/blender -b --factory-startup -P tools/sprites/build.py 2>&1 | grep -v Saved:
#   options after --: --units heavy_swords,spearmen   --no-iso   --iso-only   --out DIR
python3 tools/sprites/pack.py            # ~1 s; --contact /tmp/x.png for a quick look
godot --path . --resolution 2400x1350 res://tools/sprites/preview/preview.tscn
#   -- --shot=/tmp/top.png [--scroll=520]   screenshot and quit
```

Render times (2026-10-13): heavy_swords 2.3 s, spearmen 1.9 s,
shock_cavalry 2.1 s (14 frames x 3 passes each), iso 8 directions x 6
frames x 3 passes 7.0 s. Output 184 KB in all.

## Add a unit (spec only)

1. Under `units`, add an entry: `rig` (`humanoid` or `horse`), `body` (the
   shared parts list under `bodies` the unit wears), `render_box` (metres
   around the man's feet, x0 x1 y0 y1, multiples of 0.25 m; generous: the
   packer trims per action), and `parts`. A mounted unit adds `rider`
   (`rig`, `body`, `seat`, `parent_bone`) and `rider_parts`.
2. A part: `n` name, `bone` it follows, `mat` (a fixed colour from
   `materials`, or `primary` / `secondary` / `accent` for faction-coloured
   parts), `shape` and its sizes:
   - `box`: `pos`, `size` [x y z], optional `bevel`, `rot`
   - `sphere`: `pos`, `r`, optional `scale`, `verts`
   - `cyl`: `pos`, `r`, `len` (along local Z; `rot` [0, 90, 0] faces it forward), `verts`
   - `limb`: `a`, `b` end points, `t` thickness (or [width, depth])
   - `cone`: `a` base, `b` tip, `r`
   - `scutum`: `pos`, `size` [thickness, width, height], `bend` radius
   Coordinates are the rig's rest pose in metres: +X forward, +Y the man's
   left, Z up (the man stands at the origin, hands at about 1.1 m: left
   hand 0.38, 0.28; right hand 0.34, -0.29). `rot` is Euler XYZ in degrees
   (about Y, positive tips the top forward: a shield tilted back to show
   its face is negative). `mirror: 1` adds the right-side twin.
   `pattern: 1` marks cloth that carries a faction's check.
3. Run build (with `--units yourunit --no-iso` while iterating) and pack.

Animations are code, shared: `humanoid_pose` and `horse_pose` in
`build.py` (idle 1, walk 6, attack 4, death 3 frames; frame counts and fps
in `spec.json` `actions`). Palettes are `spec.json` `palettes` (copied into
the manifest).

## Outputs and conventions

- 24 px per metre (`ATLAS_PX_PER_M` in `game/soldier_layer.gd`), 0.0417 m a
  pixel; an infantry man fills about 1.2 m (29 px) at 1x.
- Top view: the man faces image right (+x forward); his left is image up
  (the game's local y "to the right" is image down). The anchor in the
  manifest is the man's feet (the unit's origin) in px from a frame's
  top-left; each action has one frame size and one anchor.
- Shade sheet: lit colours, faction parts lit white, a 1 px dark outline,
  hard alpha. Mask sheet (same layout): R primary, G secondary, B accent,
  A = 255 - 128 x check; recolour in `preview/recolor.gdshader`.
- Determinism: fixed EEVEE samples (16), no random; the same Blender and
  GPU give the same bytes.
- `assets/sprites/.gdignore` keeps Godot from importing / exporting the
  sheets until step 1b wires them in (the preview reads the PNGs directly).
