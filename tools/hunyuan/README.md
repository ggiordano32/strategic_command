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
is a separate non-commercial licence too. The UltraTex route adds the FLUX non-commercial licence: the UltraTex
weights are MIT, but the base model (FLUX.2 Klein base 9B) is under the FLUX non-commercial licence (its outputs may be
used, production use of the model may not). The owner chose to ship the UltraTex textures anyway and to settle the
licence later (recorded 2026-10-21). Nothing here is wired into the game.

**Recommended route (2026-10-21): `gen` -> `silfit` -> UltraTex (ComfyUI, `tools/ultratex/run.py`) -> `hy_paint.py ultratex
--assets`** (section "UltraTex raw (the shipped texture)" below). The hybrid route stays documented as the fallback when
the GPU route is unavailable.

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
has the same triangles in the same order, so the match is exact (centroid distance 0, one to one). `bake` matches **by triangle index** when the committed mesh and the painted mesh have the same triangle count (after `silfit` the committed vertices have moved, so centroids no longer agree): the corner order of each painted face is recovered through `silfit_map.npz` (fitted -> unfitted positions, written by `silfit.py` into `W/NAME/` or `OUT/NAME/`, or `--map PATH`) and the barycentric lookup is done on the fitted triangle. Different counts fall back to the centroid match.
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

### UltraTex raw (the shipped texture)

UltraTex (FLUX.2 Klein base 9B Q4_K_M, ComfyUI-UltraTex, `keep_existing` UVs) paints the fitted mesh from the front crop
at 1536 px views into a 2048 atlas in the committed mesh's own UV layout; its raw albedo is shipped with no palette snap
(the look of the hand-painted source, faces, lacing, belts). Run order:

```sh
S=~/scratch/hunyuan
# 1. (GPU, ComfyUI on port 8075, see tools/ultratex/run.py's header) paint the fitted committed mesh
python3 -I tools/ultratex/run.py assets/characters/NAME/mesh.glb $S/work/NAME/front.png $U/NAME_fit --res 1536 --tex 2048 --tag NAME_fit --memfac 120
# 2. (Blender, CPU, about 35 s a character) albedo + label map + mask map + renders, writes assets/ with --assets
~/.local/bin/blender -b --factory-startup -P tools/hunyuan/hy_paint.py -- ultratex NAME --albedo $U/NAME_fit/albedo_raw.png --out $O [--work $S/work] --assets
```

`ultratex` treats the committed mesh as the painted mesh (same triangles and UVs, so the reprojection into the 1024 layout
is exact, 8 px bleed past the charts), runs the `bake` stage's rules on it only to get the label map (R = coat, G = sash
of the mask map; coverage printed: captain R 24.5 / G 6.7 %, Mercy R 36.0 / G 0, Rook R 13.5 / G 1.2 %), and renders with
paint_render's rig (toon-D ramp, ink hull, no glint / dry-brush): `assets/characters/NAME/mesh.glb` (2.3-2.8 MB, albedo
1024 px embedded), the minis (96 / 48 + masks + json), the 256 px bust, and `OUT/NAME/ultratex/preview_NAME.png`. Without
`--assets` everything goes under `OUT/NAME/ultratex`. The mesh must be the one the UltraTex run painted (re-run UltraTex
after every `silfit`).

### Hybrid (face from the sheet bake, body from the paint): the fallback route

**Route: `gen` -> `silfit` -> `bake` -> `hybrid --assets`** (`silfit` and its re-bake are the next section; without them: `gen` -> `bake` -> `hybrid --assets`) (the shipped assets of captain, Mercy and Rook; the paint bake's ink applies to the head only, below `head_z` the skin is flat colour plus detail; `bake` itself writes nothing to `assets/`, `hybrid --assets` writes mesh, minis and bust, the preview goes to `--out`).

The paint route's faces are soft (the captain loses his eyes, Rook his smile) while its cloth and colour are better,
so `hy_paint.py hybrid NAME --work W --out O --hy HYPAINT_OUT [--hat hypaint]` merges the two albedos in the shared
1024 chart layout (same UVs, so no resampling): texels above the collar (`head_z`, 0.82 by default: `face_z` 0.87
would cut through the mouth and chin) whose sheet-bake label is skin, hair, hat, headscarf or sash take the bake's
albedo and label, everything else the paint route's; the albedo is blended over about 6 texels at the boundary,
labels are not. `--hat hypaint` keeps the paint route's hat, trim and plume (only skin and hair from the bake; chosen
for the captain, whose bake hat plus paint plume mix to brown). It writes mesh, minis, bust and preview into
`O/NAME/hybrid` (and `hypaint` for comparison) through paint_render's own main with its asset paths redirected:
nothing is written to `assets/`. `hybrid_compare NAME --out O` makes the [bake | paint | hybrid] image.

## Silhouette fit (`silfit.py`)

The Hunyuan meshes have good silhouettes but not the sheet's exactly (hat brim, crown, plume, hem), so the sheet colours
and the paint model's colours land in the wrong places (captain's hat trim, hem blotches). `silfit.py` deforms each mesh
to the sheet's four silhouettes once; then the whole texture route lines up. numpy / scipy / PIL only (the venv python),
CPU, about 75 s a character.

```sh
S=~/scratch/hunyuan; SF=~/scratch/silfit      # S/work = crops, SF = tables, overlays, orig/ (the input kept for re-runs)
~/.venvs/hunyuan/bin/python tools/hunyuan/silfit.py captain mercy rook --work $S/work --out $SF --assets
# then, per character: projection bake on the fitted mesh (new atlas), paint bake by triangle index, hybrid
mkdir -p $SF/work/NAME $SF/hy/NAME; ln -s $S/work/NAME/silfit_map.npz $SF/work/NAME/       # and hy_mesh.npz, hy_raw.png into $SF/hy/NAME
~/.local/bin/blender -b --factory-startup -P tools/hunyuan/silfit_bake.py -- NAME --work $S/work --out $SF/work
~/.local/bin/blender -b --factory-startup -P tools/hunyuan/hy_paint.py -- bake NAME --work $SF/work --out $SF/hy
~/.local/bin/blender -b --factory-startup -P tools/hunyuan/hy_paint.py -- hybrid NAME --work $SF/work --out $SF/hybrid --hy $SF/hy --skip-hy --assets [--hat hypaint]
```

Without `--assets` the fitted glb goes to `OUT/fitted/NAME.glb` and the committed mesh is untouched. The input mesh is the
first `mesh.glb` seen, copied to `OUT/orig/NAME.glb`; a re-run starts from that copy (delete it to start from the
current `assets/` mesh).

1. **Frames.** The four views of `paint_render.View`, at the sheet's own scale (figure height = mesh height, the same px
   per metre in every view) with one common centre per axis pair (front / back share x, left / right share y) from a
   translation-only fit of the left / right extents at the five height bands. `texture.py`'s per-view scale / offset
   fit of the *input* meshes read 0.85-1.06 (the Hunyuan depth is up to 10 % off the sheet's), so fitting to these
   frames also fixes that; the table reports the fit before and after.
2. **Metrics.** Per view: the mesh silhouette (all triangles, PIL polygons at the sheet's 1024 px) against the sheet's
   alpha > 0.5: IoU and the mean symmetric boundary distance (px and cm, 1.80-2.00 m figure = sheet height).
3. **Correspondences** (every 2 px, 4 passes): per image row the span ends of the mesh silhouette and of the sheet are
   paired when both have the same span count (weight 1 / count, pairs further apart than 20 px, about 3.7 cm, are another
   feature and skipped); the mesh vertices within 1.5 px of the mesh's end point (3 at most) become soft handles whose
   target moves the span end onto the sheet's, along the view's horizontal axis only; targets are smoothed over a 5-row
   window along each span end. **Extension to the brief:** the same pairing along image columns gives vertical handles
   (z) for the crown, brim and hem; they are what moves the hat's top and the coat hem. Depth is never a handle.
4. **Solve.** On the position-welded mesh, with the cotangent Laplacian L and lumped areas M: minimise the displacement
   field's `d'(L M^-1 L)d + 10 d'Ld + 1e-4 d'Md + 100 sum_handles w (d_i - t_i)^2`, one sparse LU per axis (front / back
   handles constrain x, left / right y, the column handles z), the same displacement on duplicated (UV-seam) vertices,
   each step capped at 3 cm a vertex, 4 outer iterations with fresh correspondences. **Self-intersection guard:** the
   triangle-triangle crossings of the mesh (edge-through-triangle tests of the pairs the centroid tree finds, triangles
   sharing a vertex excluded) are counted before and after every step; where a step makes triangles cross, the vertices
   of those triangles and their ring take half the step (a smooth fall-off), repeated up to 8 times, then the whole step
   shrinks. The input meshes have 0 crossings and the results keep 0. Topology, vertex and triangle order and the UVs
   are unchanged: only the glb's POSITION (min / max) and NORMAL accessors are rewritten, the embedded texture stays.
5. **Re-bake.** `silfit_bake.py` (Blender, CPU, 30-60 s): the second half of `paint_render.build_texture` on the fitted
   committed mesh (new atlas on the fitted geometry, the texture.py bake with `CHARS` rules, albedo / labels to
   `OUT/NAME/`, `mesh.glb` exported with the new UVs; its `fit front|left|right|back` lines read 0.93-1.02 scale and
   at most 6 px offset now). Then `hy_paint.py bake` (reprojection by triangle index, 30 s) and `hybrid --assets` as before.

Numbers (mean boundary distance, front / left / right / back in cm; IoU front / left / right / back):

| character | before cm | after cm | before IoU | after IoU |
|---|---|---|---|---|
| captain | 1.25 / 1.88 / 2.11 / 1.36 | 0.85 / 0.68 / 0.72 / 0.86 | .885 / .831 / .818 / .876 | .920 / .937 / .935 / .919 |
| mercy | 1.04 / 2.32 / 2.37 / 1.14 | 0.51 / 1.66 / 1.58 / 0.71 | .898 / .831 / .818 / .890 | .947 / .873 / .865 / .928 |
| rook | 2.18 / 2.24 / 1.85 / 1.80 | 0.69 / 1.14 / 1.03 / 0.82 | .760 / .814 / .840 / .797 | .918 / .893 / .900 / .895 |

Limits: horizontal and vertical span ends only, so what does not reach a silhouette end (interior), arms apart from the
body or hair strands with another span count are untouched; the captain's front hat left edge and plume tip, Mercy's
and Rook's side views (the sheet's side silhouettes and the Hunyuan depth disagree most) keep 1-2 cm; the
paint model's hem blotches are colour, not shape, and stay.
