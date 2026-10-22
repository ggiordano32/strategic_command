# Menu art

Painted emblems, key art, wordmark and the display font for the main menu (assets/ui/).

Re-run:

    cd ~/Applications/ComfyUI && .venv/bin/python main.py --port 8076 --listen 127.0.0.1
    python3 tools/menu_art/gen.py OUT --kind emblem --side west --seeds 1,2,3,4,5,6     # 1024 px candidates
    python3 tools/menu_art/gen.py OUT --kind keyart --side rome --seeds 1,2,3,4         # 1344x768 candidates
    python3 tools/menu_art/flatten.py OUT/emblem_west_2.png assets/ui/emblems/west.png assets/ui/emblems/west_128.png
    python3 tools/menu_art/finish.py keyart OUT/keyart_west_3.png assets/ui/keyart/west.jpg
    python3 tools/menu_art/finish.py wordmark assets/ui/fonts/Cinzel-Bold.ttf assets/ui/wordmark.png

flatten.py / finish.py need PIL (+ numpy, scipy for flatten); the hunyuan venv has them. Stop ComfyUI afterwards.

Kept (FLUX.2 Klein 4B distilled, 4 steps, CFG 1, euler):

- emblems/west.png: seed 2, rome.png: seed 3 (of 1-6), prompts in gen.py. Flattened to gold b08a40 / ink 1a1410 / bone e8dcb0 on transparent, 512 px (+ 128 px).
- keyart/west.jpg: seed 57 (of 51-58), "a Caribbean pirate harbour at dusk from the sea, 1650: a stone fort on the headland, palms, a frigate at anchor, fishing boats and a crowded quay, oil painting, loose brushwork, warm light, wide shot, no text, no modern buildings" (matches the Rome painting; the first, glossier version used the brief's plain "painted" prompt). keyart/rome.jpg: seed 24 (subject a, of 21-24) with "a Roman harbour at dawn, 280 BC: stone quays, a trireme fleet with oars and square sails, a marble temple on the hill, a legion camp with tents on the shore, oil painting, loose brushwork, warm light, wide shot, no text, no modern buildings". (The brief's "Bay of Naples" prompt and a Naples/Vesuvius variant both gave photographic modern-looking towns. Alternative tried: Carthage cothon harbour at dusk, seeds 31-34.) 1344x768 centre-cropped to 16:9, Lanczos to 1920x1080 (no upscale model installed), JPEG q85.
- wordmark.png: PIL, Cinzel Bold, gold with 2 px ink outline, 1600 px wide.
- fonts: Cinzel Regular / Bold, static instances (wght 400 / 700, fontTools instancer) of the Google Fonts variable file ofl/cinzel/Cinzel[wght].ttf.

## Models and licences

| Item | Source | Licence |
|---|---|---|
| FLUX.2 Klein 4B (flux-2-klein-4b-fp8.safetensors) | https://huggingface.co/black-forest-labs/FLUX.2-klein-4B (Comfy-Org repack: https://huggingface.co/Comfy-Org/flux2-klein) | Apache-2.0 (the 9B and FLUX.2 dev are non-commercial and are not used) |
| Qwen3 4B text encoder (qwen_3_4b.safetensors) | https://huggingface.co/Qwen/Qwen3-4B | Apache-2.0 per its model card |
| FLUX.2 VAE (flux2-vae.safetensors) | https://huggingface.co/Comfy-Org/flux2-dev (split_files/vae) | Taken from the FLUX.2 dev repack; its licence on the card was not re-checked here (check before release) |
| Cinzel | https://github.com/google/fonts/tree/main/ofl/cinzel (OFL.txt copied to assets/ui/fonts/) | SIL Open Font Licence 1.1 |

Timings (RTX, 8 GB, distilled 4 steps): about 5 s per 1344x768 image, about 6 s per 1024x1024 image; the first image after starting ComfyUI took 11 s (about 6 s model load).

## Faction crests (assets/ui/crests/<pack>/<key>.png 256 px + <key>_64.png)

Painted crests for the 16 factions (West: new_spain, tierra_firme, england, france, dutch, brethren, itza, miskito; Rome: rome, carthage, macedon, epirus, greeks, syracuse, iberians, gauls), made from our drawn marks as the reference image so the composition stays ours:

    godot --resolution 512x512 --script res://tools/menu_art/render_refs.gd -- --out=REF      # West: game/faction_emblem.gd at 512 px; Rome (no drawn emblem): a shield in the faction colour with a gold rim
    python3 tools/menu_art/crests.py REF CAND [--only west/england] [--seeds 1,2,3,4]         # Klein 4B edit, 4 candidates each (prompts in crests.py)
    ~/Applications/ComfyUI/.venv/bin/python tools/menu_art/crest_flatten.py CAND/west_england_1.png c8402f assets/ui/crests/west/england.png assets/ui/crests/west/england_64.png

crests.py is ComfyUI's template image_flux2_klein_image_edit_4b_distilled as an API graph (reference through ImageScaleToTotalPixels 1 MP, VAEEncode, ReferenceLatent on the positive and the zeroed negative; 4 steps, CFG 1, euler; same three model files as the table above, so the licence table is unchanged). Prompt: "heraldic crest of <name>, <character>, flat vector heraldry, gold and <colour> on white, clean edges, bold simple shapes, no text". crest_flatten.py: background flood-filled to transparent, every other pixel to the nearest of gold b08a40 / ink 1a1410 / the faction colour (CData) / bone e8dcb0 (enclosed light fields, as in the emblems), median-smoothed, 4x supersampled to 256 and 64 px. Wiring: `Kit.faction_mark` (game/faction_crest.gd) under `[menu] emblems = painted`; test and gallery: tests/crest_gallery.gd -> docs/screenshots/crests.png.

Kept (seed of 1-4): new_spain 2, tierra_firme 2, england 1, france 2, dutch 1, brethren 1, itza 1, miskito 1; rome 1, carthage 4, macedon 2, epirus 3, greeks 4, syracuse 1, iberians 2, gauls 4. About 10.5 s per 1024 px edit (64 images, about 11.5 min; first 18.6 s).
