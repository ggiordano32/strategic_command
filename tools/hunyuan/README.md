# Hunyuan3D character pipeline (close-up models)

Turnaround sheet -> 3D mesh -> projection-textured in the game's palette -> renders.
For close-up characters only (overworld captain / hero miniatures, story
portraits). Shape generation only: the paint / texture model is not used or
downloaded; the mesh is painted by projecting the sheet's colours and snapping
them to a 7-8 colour palette (the code-drawn portraits' colours in
`game/story_portrait.gd`), which is what gives the toon look.

**Licence: the Tencent Hunyuan 3D licence is non-commercial and excludes the
EU, UK and South Korea.** Check it (https://github.com/Tencent/Hunyuan3D-2/blob/main/LICENSE)
before shipping anything it generated, and before any build that is distributed
in those territories. The background remover (rembg default model, BRIA RMBG)
is a separate non-commercial licence too. Nothing here is wired into the game.

## Setup (once)

```sh
uv venv ~/.venvs/hunyuan --python 3.11          # outside the repo
source ~/.venvs/hunyuan/bin/activate
uv pip install torch==2.6.0 torchvision==0.21.0 --index-url https://download.pytorch.org/whl/cu124
git clone https://github.com/Tencent/Hunyuan3D-2 ~/.venvs/src && git -C ~/.venvs/src checkout f8db630
uv pip install -r tools/hunyuan/requirements.txt  # exact versions used
uv pip install --no-deps -e ~/.venvs/src
```

Weights come from Hugging Face on first run into `~/.cache/huggingface`:
`tencent/Hunyuan3D-2mv` `hunyuan3d-dit-v2-mv-turbo` (4.9 GB fp16) and the turbo
VAE from `tencent/Hunyuan3D-2`. The rembg model (~1 GB) goes to `~/.rembg`.
`transformers` must be 4.46.x (5.x cannot load the conditioner).

## Model

`Hunyuan3D-2mv-turbo` (1.1B, multi-view, step-distilled, FlashVDM decoder),
fed front + left + back (it takes no right view; the crops include right for
checking). Fits the RTX 3070: **peak 5.5 GiB VRAM** (the desktop holds ~2 GiB
more), **~22-33 s to load, 5.5 s to generate** (5 steps, octree 380) per
character, seed 12345. `--mini` uses `Hunyuan3D-2mini-turbo` (0.6B, front only)
as a fallback.

## Run

```sh
S=~/scratch/hunyuan     # any working dir (raw meshes and crops are not committed)
~/.venvs/hunyuan/bin/python tools/hunyuan/gen.py "SHEET.png" NAME --work $S/work
~/.local/bin/blender -b --factory-startup -P tools/hunyuan/paint_render.py -- NAME --work $S/work --preview $S
```

`gen.py`: cuts the top row into four figures (background removal over the
strip, split at the empty column gaps; verify `work/NAME/{front,left,right,back}.png`),
generates `work/NAME/raw.glb` (600k-800k faces).
`paint_render.py` (60-130 s a character with the bake, 4-14 s to re-render) orients the mesh by silhouette overlap,
decimates it to ~50k tris and bakes a **1024x1024 projection texture** (`texture.py`, numpy only):

1. **Alignment.** Each sheet view is fitted to the mesh silhouette: vertical = feet / crown extents, horizontal =
   least squares of the left / right extents at the 10 / 30 / 50 / 70 / 90 % height bands, giving a scale and offset
   per view (printed as `fit front|left|right|back`; a fit outside +-12 % scale keeps the nominal projection).
2. **Atlas.** Every triangle is owned by the sheet view that sees it best (z-buffered, the head's front owned by
   the front view, neighbour vote against speckle). Each (view, body / head) is a planar chart (the view's own
   u, z), shelf-packed; head charts get `head_density` (2x) the texel density; the split is at `head_z`. Smart UV
   Project was tried and rejected: the noisy Hunyuan surface shatters into thousands of islands (1-6 % texture use).
3. **Label layer.** Each texel takes the sheet colour of its chart's view (3 px blur), snapped to the nearest
   `ANCHORS` colour (`ZBAND` height priors), then:
   - grazing texels (facing < 0.3: up / down surfaces no side view sees) take the label of the nearest well-seen
     texel (cloth only below the head);
   - above `face_z` only the `head_labels` are allowed (nearest in Lab; `head_alias` maps e.g. gold -> hat);
   - above `hat_z` only the `hat_zone` labels are allowed (captain hat + gold trim + sash plume, Mercy hat,
     Rook headscarf + hair);
   - 3x3 majority, then components smaller than 120 texels (80 in head charts, 400 in the hat zone) join the label
     of their longest border, then a 5x5 majority;
   - stray skin components in a hat character's head charts (< 35 % of the view's face) become hat;
   - `hat_labels` pieces below the hat zone that do not connect to it become skin / hair (Mercy's blue streak);
   - `mouth_fix`: coat / sash specks under 150 texels in the face band become skin, or ink where darker than the face;
   - `skin_prune` (captain): skin below the neck that does not connect to the head or the hands (z < 0.55)
     becomes coat.
   Per-rule texel counts and the number of components removed are printed.
4. **Colour.** Flat palette colour per label. The detail layer (sheet luma against the local mean of the same label,
   r = 12 px, clamped to [-0.35, +0.25]) applies **only to skin and hair**. Ink `1a1410` only on skin: texels with
   raw detail below -0.20..-0.32, sheet luma < 0.55 x the face median, in blobs of >= 6 texels (eyes, brows, mouth
   line, not pores). Bleed 8 px past each chart.
5. **Mask.** `CHARS[..]["mask"]` lists the labels that go to R (coat tint) and G (sash / plume tint); the mini's R / G
   coverage is printed. Rook's R is small (7.8 %) because the sheet shows only the teal jacket's shoulders and sleeves.
6. **Render.** One textured object with the structures' toon-D material (the albedo as colour, a hue / saturation
   node standing in for style D's lift) and an ink hull round the welded mesh.

Outputs:

- `assets/characters/NAME/mesh.glb` (~1.5 MB, albedo embedded as baseColorTexture, no vertex colours, feet at the
  origin facing -Y once scaled)
- `assets/minis/characters/NAME.png`, `NAME_mask.png`, `NAME_small.png` (96 / 48 px tall), `NAME_small_mask.png`,
  `NAME.json`. Camera (ortho, tilt 52 from vertical, from the south), key + fill sun, toon-D ramp and ink hull as
  `tools/structures/build.py` (loaded as a library); glint and dry-brush edge off (`SC_DBG=nogloss,nobev`). The
  figure is 1.8-2 m tall at 96 px (rule of cool).
- `assets/portraits/NAME.png`: 256 px bust, yaw -32, window 1.3x the old one so the hat and the far shoulder fit.
- `PREVIEW/preview_NAME.png`: 8 headings x (miniature view, eye-level view).
- `work/NAME/`: `raw.glb`, the crops `front|left|right|back.png`, `albedo.png`, `labels.png` (label index in all
  channels), `maskmap.png` (R / G), `_turn/`.

Flags: `--only mesh,mini,bust,turn` (without `mesh` the committed textured `mesh.glb` is re-rendered; labels come from
`work/NAME/labels.png` if present, else the nearest palette colour of the albedo), `--tris N`, `--work`, `--preview`.
`gen.py --crops-only` regenerates the crops (rembg on CPU; no model, no CUDA). `HY_DEBUG=1` prints label statistics.

Timings (CPU Blender, no GPU): captain 114-131 s, Mercy 78-84 s, Rook 60-71 s for the full run (bake about 50-60 s,
of which the grazing-texel search is the slowest step); re-render only 4-14 s.

## Add a character

1. Put the sheet (four views in the top row: front, left, right, back) in the working dir; add its name and
   view-row height (px above the labels) to `CHARS` in `gen.py`. Run `gen.py` (or `--crops-only` plus an existing
   `raw.glb`) and look at the four crops.
2. In `paint_render.py` add to `CHARS`: `palette` (label -> game hex, mask channel), `height_m`, `bust`
   (head-room above the skin top, window height), `head_labels`, `mask` ({"R": [labels], "G": [labels]}), `face_z`
   (height fraction above which only head labels exist, ~0.87), `hat_z` (hat / headscarf zone start, 0.90-0.93; used only with `hat_lock`),
   `hat_zone` (labels allowed there), `hat_labels` (labels that must connect to the zone), optional `head_alias`, and three switches, default off: `hat_lock` (hat-zone label lock + 400-texel threshold +
   connectivity rule), `mouth_fix` (lip speck rule), `skin_prune` (skin not joined to head or hands becomes coat).
   Current settings: Mercy lock + mouth on; captain lock only; Rook all off (his iteration-2 look).
   `head_z` (head chart split, 0.82), `head_density` (2.0).
   Also add `ANCHORS` (what each label looks like on the sheet: sample the sheet; use several hex values per label
   where it varies) and `ZBAND` height priors.
3. Run it, read the label counts and the albedo (`work/NAME/albedo.png`) and the preview, and adjust the anchors.
