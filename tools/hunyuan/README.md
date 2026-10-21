# Hunyuan3D character pipeline (close-up models)

Turnaround sheet -> 3D mesh -> painted in the game's palette -> renders.
For close-up characters only (overworld captain / hero miniatures, story
portraits). Two ways to paint the mesh: the **projection bake** (`texture.py`,
sheet colours projected and snapped to a 7-8 colour palette, the code-drawn
portraits' colours in `game/story_portrait.gd`) and the **Hunyuan paint route**
(section below, the shipped texture of the three characters: Hunyuan3D-2's own
paint model colours the mesh, `hy_paint.py bake` reprojects that into our atlas,
calibrates and snaps it to the same palette). Both end in flat palette colours
and the same renders, which is what gives the toon look.

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


## Hunyuan paint route (the shipped texture)

The projection bake reads the sheet; the paint model (`Hunyuan3D-2` `hunyuan3d-paint-v2-0-turbo`: multi-view
diffusion from the front crop, then back-projection into xatlas UVs) paints the mesh itself, so faces, cloth
structure and the hidden sides are better. Its raw texture is dark and desaturated, so `hy_paint.py bake` lifts it
back onto the sheet's anchor colours before the palette snap. Licence: the same Tencent non-commercial licence as
the shape model (not for the EU, UK, South Korea; check before shipping). Nothing is wired into the game.

### CUDA extensions (once)

The paint pipeline needs two compiled extensions from the Hunyuan checkout: `custom_rasterizer`
(`~/.venvs/src/hy3dgen/texgen/custom_rasterizer`) and `differentiable_renderer` (`mesh_processor`). The machine has
no CUDA toolkit (the driver is 615.71, torch is the cu124 wheel) and Debian 13's gcc is 14, which nvcc 12.4 rejects,
so a user-level toolkit from NVIDIA's redistributable tarballs is used, nothing is installed system-wide:

```sh
# 12.8 nvcc (accepts gcc 14), cudart and cccl headers from https://developer.download.nvidia.com/compute/cuda/redist/
mkdir -p ~/.venvs/cuda124/n128 && cd ~/.venvs/cuda124/n128
for p in cuda_nvcc/linux-x86_64/cuda_nvcc-linux-x86_64-12.8.93 cuda_cudart/linux-x86_64/cuda_cudart-linux-x86_64-12.8.90 \
         cuda_cccl/linux-x86_64/cuda_cccl-linux-x86_64-12.8.90; do
  curl -LO https://developer.download.nvidia.com/compute/cuda/redist/$p-archive.tar.xz; tar xf $(basename $p)-archive.tar.xz; done
# nvcc looks for bin/ include/ lib64/ nvvm/ under CUDA_HOME: ~/.venvs/cuda124/home2 symlinks (or copies) the nvcc
# bin/ nvvm/ and the merged include/ (nvcc + cudart + cccl) and lib64/ (cudart) of the three archives.
# Patch: crt/math_functions.h declares sinpi / cospi (and the float versions) without noexcept, glibc 2.41 declares
# them noexcept (true) and the compile stops on the mismatch: the copy under home2/include/crt carries noexcept (true).
export CUDA_HOME=~/.venvs/cuda124/home2 PATH=$CUDA_HOME/bin:$PATH TORCH_CUDA_ARCH_LIST=8.6   # RTX 3070
export CC=gcc-14 CXX=g++-14
source ~/.venvs/hunyuan/bin/activate
uv pip install diffusers==0.32.2 accelerate xatlas pybind11 omegaconf einops opencv-python-headless pymeshlab
cd ~/.venvs/src/hy3dgen/texgen/custom_rasterizer && python setup.py install
cd ../differentiable_renderer && python setup.py install
```

Run the venv python with `LD_LIBRARY_PATH` including torch's lib dir (`site-packages/torch/lib`) or `import
custom_rasterizer` fails with `libc10.so: cannot open shared object file`. The weights (`hunyuan3d-paint-v2-0-turbo`,
the delight and multiview models) come from Hugging Face on first run (~10 GB).

### Stages

```sh
S=~/scratch/hunyuan     # work (crops, labels) as for the sheet bake; OUT = any folder for the paint results
# 1. paint (GPU, venv python): committed mesh.glb + front crop -> OUT/NAME/hy_raw.png (2048) + hy_mesh.npz
~/.venvs/hunyuan/bin/python tools/hunyuan/hy_paint.py gen NAME --work $S/work --out $OUT --offload
# 2. bake (Blender, CPU): reprojection, calibration, palette, writes assets/characters/NAME/mesh.glb
~/.local/bin/blender -b --factory-startup -P tools/hunyuan/hy_paint.py -- bake NAME --work $S/work --out $OUT
# 3. renders: the bake wrote OUT/work/NAME/{albedo,labels,maskmap}.png; paint_render re-renders mesh.glb with them
~/.local/bin/blender -b --factory-startup -P tools/hunyuan/paint_render.py -- NAME --work $OUT/work --preview $OUT --only mini,bust,turn
```

`gen --offload` loads both diffusion pipelines on the CPU and lets accelerate move one sub-model to the GPU at a
time: **peak 4.07 GiB VRAM, about 95 s a character at 2048** (load 36 s). Without it the pipelines do `.to('cuda')`
in their constructors and do not fit 8 GB next to the desktop. `--variant full` uses the non-turbo model.
`gen` paints the committed `mesh.glb` (mesh, UVs of the sheet bake) and writes new xatlas UVs: the painted mesh
has the same triangles in the same order, so the match is exact (centroid distance 0, one to one).
The stage `render` and `compare` of the experiment (raw / quantised variants next to the sheet bake) remain.

`bake` does, per character (about 45 s, Blender CPU):

1. **Reprojection.** Texels of the committed 1024 chart layout (`texture.rasterize`: triangle and world position
   per texel) take the raw paint by barycentric lookup in the matching triangle's xatlas UV (bilinear). Texels of a
   triangle without a match (none in practice) keep the sheet bake's colour and label.
2. **Calibration.** k-means (k = 11, Lab, seeded) over the reprojected colours; the table (share, mean height,
   raw L / C / hue, lifted L / C, matched anchor) is printed. An iterative fit matches each cluster to an anchor
   (hue distance weighted by chroma, lightness, chroma, `ZBAND` priors by the cluster's height) and fits
   L' = aL L + bL (aL 0.9-3, bL -6..8) and C' = aC C (aC 1-1.3), trimmed (pairs off by > 12 L dropped) and only
   from clusters with chroma >= 12 or L >= 30 (dark grey clusters match the anchors ambiguously). The remaining
   chroma ratio of the matched clusters is smoothed over hue (10 degree bins, sigma 18) into a **hue gain**: the
   paint model drains red cloth far more than skin or leather, and one global slope cannot do both (captain's plume
   needs about x1.8 at hue 20-30, skin x1.0-1.2); hue is kept.
3. **Rules** (ported from `texture.bake`, same thresholds, switches from `paint_render.CHARS`): classification in
   Lab with lightness x0.6 and the `ZBAND` priors, head labels above `face_z`, hat-zone lock above `hat_z`, 3x3
   majority, small components (120 / 80 head / 400 hat zone) merged, 5x5 majority, hat connectivity, mouth rule,
   skin prune; flat palette colour; detail layer and ink (`#1a1410`, blobs >= 6 texels) on skin and hair only; mask
   map R = coat, G = sash. `hy_paint.BAKE_RULES` / `BAKE_BANDS` hold this route's overrides (captain mouth rule on,
   mouth specks up to 300 / 600 texels, Rook's metal below 60 % height, Mercy's brass below 62 %).
   Label shares before / after the lift and for the sheet bake are printed.
4. **Export.** `paint_render.export_mesh`: `assets/characters/NAME/mesh.glb` (committed UVs, albedo embedded, no
   vertex colours, 1.5-1.6 MB). Then `paint_render.py --only mini,bust,turn` writes the minis (96 / 48 px, masks,
   json), the 256 px bust (yaw -32) and `preview_NAME.png`.

### Files

- `OUT/NAME/hy_raw.png`, `hy_mesh.npz`, `hy_stats.txt`: the paint model's output (not committed)
- `OUT/NAME/albedo_reproj.png`: the raw paint in our atlas (look at it first when a colour is wrong)
- `OUT/work/NAME/albedo.png`, `labels.png`, `maskmap.png`: the baked texture and label index
- `assets/characters/NAME/mesh.glb`, `assets/minis/characters/NAME*.png|json`, `assets/portraits/NAME.png`: as before

### Hybrid (face from the sheet bake, body from the paint): the recommended route

**Route: `gen` -> `bake` -> `hybrid --assets`** (the shipped assets of captain, Mercy and Rook; the paint bake's ink applies to the head only, below `head_z` the skin is flat colour plus detail; `bake` itself writes nothing to `assets/`, `hybrid --assets` writes mesh, minis and bust, the preview goes to `--out`).

The paint route's faces are soft (the captain loses his eyes, Rook his smile) while its cloth and colour are better,
so `hy_paint.py hybrid NAME --work W --out O --hy HYPAINT_OUT [--hat hypaint]` merges the two albedos in the shared
1024 chart layout (same UVs, so no resampling): texels above the collar (`head_z`, 0.82 by default: `face_z` 0.87
would cut through the mouth and chin) whose sheet-bake label is skin, hair, hat, headscarf or sash take the bake's
albedo and label, everything else the paint route's; the albedo is blended over about 6 texels at the boundary,
labels are not. `--hat hypaint` keeps the paint route's hat, trim and plume (only skin and hair from the bake; chosen
for the captain, whose bake hat plus paint plume mix to brown). It writes mesh, minis, bust and preview into
`O/NAME/hybrid` (and `hypaint` for comparison) through paint_render's own main with its asset paths redirected:
nothing is written to `assets/`. `hybrid_compare NAME --out O` makes the [bake | paint | hybrid] image.
