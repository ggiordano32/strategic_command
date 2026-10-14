# Overworld structures (style exploration)

Structures are written as data in `spec.json` (parts lists); `build.py`
(Blender 5.2, EEVEE, background mode) builds low-poly meshes from code and
renders pre-baked 3/4-view sprites (the game stays 2D). `compose.py`
recolours with faction palettes and makes style boards and map mockups.
Nothing here is wired into the game yet.

```
spec.json    materials, toon band thresholds, light, palettes, defs (reusable
             sub-assemblies), structures (parts + zex height exaggeration)
build.py     Blender: meshes, toon materials, outline, camera, 2 passes
compose.py   numpy + ImageMagick `convert`: recolour, boards, mockups
_frames/     renders (git-ignored, .gdignore'd)
```

## Run

```sh
~/.local/bin/blender -b --factory-startup -P tools/structures/build.py -- \
    [--structs star_fort,port] [--styles A,B,C,D] [--sizes 256,96] [--tilt 40] [--out DIR]
python3 tools/structures/compose.py boards [--frames DIR] [--out DIR]
python3 tools/structures/compose.py mockup SHOTS_DIR [--styles D]   # SHOTS_DIR: all.png, <site>.png, pos.txt
```

Output per style, structure and size: `<style>/<key>_<px>_shade.png` (lit
colours, faction parts white), `_mask.png` (R primary = roofs / flags,
G secondary = trim / banners, B accent; unlit) and `.json` (pixel size, ground
origin in px, metres per px). `<px>` is the longest side. Recolour:
`shade x (R P + G S + B A + (1 - mask))`.

## Camera and light

Orthographic, looking north from the south, tilted `--tilt` (40) degrees from
vertical, transparent background, Raw view transform. Key sun from the north-west
(like the map's hillshade) with shadows; a weak camera-side fill so south faces
read as a mid band. Fixed EEVEE samples, no randomness.

## Styles

- A: 2-band cel (Shader-to-RGB + constant ramp), ink outline (inverted hull), saturated.
- B: 3 bands, warm lit / cool shadow, outline in a darkened hue, darker bases (AO by height).
- C: flat painted, 2 gentle tones, no outline, edge highlight (Bevel node), desaturated toward the map tan.
- D: painted miniature: 3 bands, glossy specular glint, dry-brush edge highlight, thin dark-hue
  outline, saturated paint, every `ground` part becomes a thick bevelled tile (a base).

## Add a structure (spec only)

Under `structures` add `{name, zex, parts}`. `zex` stretches the heights of
everything except `ground` parts (rule of cool: tall towers, masts, flags).
A part: `s` shape, `p` [x y z] (x east, y north, z up; for box / cyl / cone /
roof / wedge / steps it is the centre of the base), `r` degrees (a number =
about z, or [rx ry rz]), `m` material (a key of `materials`, or `primary` /
`secondary` / `accent` for faction colours), `ol` 0 = no outline, `ground` 1 =
the base land slab. Shapes:

- `box` sz [x y z]; `cyl` / `cone` rad, rad2, h, n; `sph` sz = radii, n
- `roof` sz, `ridge` 0..1 (1 gable, 0 pyramid; ridge along x)
- `wedge` sz, high end at -x (ramps, slipways)
- `poly` pts, z0, z1, sc0 / sc1 (scale of the bottom / top ring: tapered hulls, sloped bastions)
- `wall` pts, closed, t / t2 (bottom / top thickness), h, z0 (sloped walls along a path)
- `steps` sz, n, shrink (stepped pyramid)
- `pts` may be a list, `{"star": [n, r_out, r_in, rot]}`, `{"circle": [n, r, jitter, seed, a0, a1]}` or `{"rect": [x0 y0 x1 y1]}`
- `{"use": "name", "p", "r", "sc", "map": {"primary": "secondary"}, "polar": [n, radius, start_deg]}`
  places a def from `defs` (nesting allowed); `polar` repeats it round a circle, facing out.

`gen_spec.py` (the generator used for the first pass) is not kept: edit
`spec.json` directly.
