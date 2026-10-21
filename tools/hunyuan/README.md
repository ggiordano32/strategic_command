# Hunyuan3D character pipeline (close-up models)

Turnaround sheet -> 3D mesh -> flat-painted in the game's palette -> renders.
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
`paint_render.py` (~20 s a character): orients the mesh by silhouette overlap,
paints (z-buffered projection from the best-facing view, nearest palette
colour against per-character sheet anchors, height-band priors, neighbour-vote
smoothing), decimates to ~50k tris, and writes:

- `assets/characters/NAME/mesh.glb` (~1 MB, vertex colours = palette colours, feet at the origin facing -Y once scaled)
- `assets/minis/characters/NAME.png`, `NAME_mask.png`, `NAME_small.png` (96 / 48 px tall), `NAME_small_mask.png`, `NAME.json`
  (size, ground origin px, m/px). Same camera (ortho, tilt 52 from vertical, from the south), key + fill sun,
  toon-D ramp and ink hull as `tools/structures/build.py` (loaded as a library). The glint and dry-brush edge are
  off (`SC_DBG=nogloss,nobev`): they are noisy on an organic mesh. Shade has the real paint colours;
  the mask is R = coat, G = sash / plume, black elsewhere. The figure is drawn 1.8-2 m tall at 96 px
  (far larger than the 3.6 px/m of the structures: rule of cool).
- `assets/portraits/NAME.png`: 256 px bust, three-quarter (yaw -32), transparent background.
- `PREVIEW/preview_NAME.png`: 8 headings x (miniature view, eye-level view).

Without `raw.glb` the committed `mesh.glb` is re-rendered (colours snapped back to the palette).
`HY_DEBUG=1` prints the label statistics.

## Add a character

1. Put the sheet (four views in the top row: front, left, right, back) in the working dir; add
   its name and view-row height (px above the labels) to `CHARS` in `gen.py`.
2. Run `gen.py` and look at the four crops.
3. In `paint_render.py` add a `CHARS` entry (palette name -> game hex, mask channel), `ANCHORS`
   (what each region looks like on the sheet), `ZBAND` priors, `height_m`, `bust`
   (head-room above the skin top, window height). Run it and judge the preview; adjust the anchors.
