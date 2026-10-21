#!/usr/bin/env python3
"""Turnaround sheet -> crops -> background removal -> Hunyuan3D-2mv shape -> GLB.

Run with the venv python (see README.md):
    ~/.venvs/hunyuan/bin/python tools/hunyuan/gen.py SHEET.png NAME [--work DIR]
        [--seed 12345] [--steps 5] [--octree 380] [--view-h PX] [--mini]

Writes DIR/<name>/{front,left,back,right}.png (the crops, RGBA, kept for
checking) and DIR/<name>/raw.glb (undecimated); tools/hunyuan/paint_render.py
decimates and paints. Shape only: no texture / paint model is loaded.

Sheet layout: 1536x1024, four views in the top row in equal columns (front,
left, right, back as labelled). The sheet's Left panel faces image-left,
which is Hunyuan's "left" convention (checked against its example images).
"""
import argparse, os, sys, time

CHARS = {  # name -> (view-row height in px: above the panel labels)
    "captain": 690, "mercy": 650, "rook": 620,
}


def crop_views(sheet, view_h, remover):
    """Cut the top row into four figures. Panels are not equal columns (arms
    and coat tails cross the quarter lines), so remove the background over the
    whole strip and split at the four widest empty column gaps."""
    from PIL import Image
    import numpy as np
    im = Image.open(sheet).convert("RGB")
    strip = im.crop((0, 0, im.width, view_h))
    rgba = remover(strip)
    occ = (np.array(rgba)[..., 3] > 40).sum(axis=0) > 2
    # runs of occupied columns, merged when the gap is small (< 24 px)
    runs, start = [], None
    for x, o in enumerate(list(occ) + [False]):
        if o and start is None:
            start = x
        elif not o and start is not None:
            runs.append([start, x]); start = None
    merged = [runs[0]]
    for r in runs[1:]:
        if r[0] - merged[-1][1] < 24:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    merged = [r for r in merged if r[1] - r[0] > 60]
    if len(merged) != 4:
        sys.exit(f"expected 4 figures in the top row, found {len(merged)}: {merged}; "
                 "adjust --view-h or the sheet")
    out = {}
    for key, (x0, x1) in zip(["front", "sheet_left", "sheet_right", "back"], merged):
        out[key] = (strip.crop((x0 - 8, 0, x1 + 8, view_h)), rgba.crop((x0 - 8, 0, x1 + 8, view_h)))
    return out


def cutout(pair):
    from PIL import Image
    import numpy as np
    img, rgba = pair
    a = np.array(rgba)[..., 3]
    ys, xs = np.nonzero(a > 40)
    pad = 12
    box = (max(xs.min() - pad, 0), max(ys.min() - pad, 0),
           min(xs.max() + pad, rgba.width), min(ys.max() + pad, rgba.height))
    rgba = rgba.crop(box)
    s = max(rgba.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(rgba, ((s - rgba.width) // 2, (s - rgba.height) // 2))
    return sq.resize((1024, 1024), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("name")
    ap.add_argument("--work", default="hunyuan_work")
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--steps", type=int, default=5)
    ap.add_argument("--octree", type=int, default=380)
    ap.add_argument("--view-h", type=int, default=0)
    ap.add_argument("--mini", action="store_true", help="front view only, 2mini (fallback)")
    ap.add_argument("--crops-only", action="store_true")
    a = ap.parse_args()
    view_h = a.view_h or CHARS.get(a.name, 650)
    d = os.path.join(a.work, a.name)
    os.makedirs(d, exist_ok=True)

    from hy3dgen.rembg import BackgroundRemover
    rm = BackgroundRemover()
    views = crop_views(a.sheet, view_h, rm)
    imgs = {}
    for k, v in views.items():
        v[0].save(os.path.join(d, f"raw_{k}.png"))
        imgs[k] = cutout(v)
    imgs["left"] = imgs.pop("sheet_left")    # faces image-left = Hunyuan "left"
    imgs["right"] = imgs.pop("sheet_right")
    for k, v in imgs.items():
        v.save(os.path.join(d, f"{k}.png"))
    if a.crops_only:
        return

    import torch
    from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline
    torch.cuda.reset_peak_memory_stats()
    t0 = time.time()
    if a.mini:
        pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
            "tencent/Hunyuan3D-2mini", subfolder="hunyuan3d-dit-v2-mini-turbo", variant="fp16")
        cond = imgs["front"]
    else:
        pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
            "tencent/Hunyuan3D-2mv", subfolder="hunyuan3d-dit-v2-mv-turbo", variant="fp16")
        cond = {"front": imgs["front"], "left": imgs["left"], "back": imgs["back"]}
    pipe.enable_flashvdm()
    t1 = time.time()
    mesh = pipe(image=cond, num_inference_steps=a.steps, octree_resolution=a.octree,
                num_chunks=20000, generator=torch.manual_seed(a.seed),
                output_type="trimesh")[0]
    t2 = time.time()
    mesh.export(os.path.join(d, "raw.glb"))
    print(f"[{a.name}] load {t1-t0:.1f}s generate {t2-t1:.1f}s peak VRAM "
          f"{torch.cuda.max_memory_allocated()/2**30:.2f} GiB, {len(mesh.faces)} faces")


if __name__ == "__main__":
    main()
