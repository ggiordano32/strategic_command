#!/usr/bin/env python3
"""Drive a local ComfyUI (port 8075) through UltraTex: mesh (GLB, keep_existing UVs) + front crop -> albedo.

  python3 tools/ultratex/run.py MESH.glb FRONT.png OUT_DIR [--res 1024] [--tex 2048] [--steps 25] [--seed 12345]
         [--unet flux-2-klein-base-9b-Q4_K_M.gguf] [--port 8075] [--tag NAME]

Stdlib only.  ComfyUI must be running (python main.py --port 8075 --listen 127.0.0.1) with ComfyUI-UltraTex,
ComfyUI-GGUF, models/unet/<gguf>, models/loras/ultratex_flux2.safetensors, models/ultratex/ultratex_flux2_decoder.pt,
models/vae/flux2-vae.safetensors, models/text_encoders/qwen_3_8b_fp8mixed.safetensors.
Writes OUT_DIR/albedo_raw.png (the bake's albedo), OUT_DIR/views.png (the six views), OUT_DIR/out.glb,
OUT_DIR/stats.txt (time, peak VRAM by nvidia-smi polling).
"""
import argparse, json, os, shutil, subprocess, sys, threading, time, urllib.request, uuid

COMFY = os.path.expanduser("~/Applications/ComfyUI")


def req(port, path, data=None, headers=None):
    r = urllib.request.Request("http://127.0.0.1:%d%s" % (port, path), data=data, headers=headers or {})
    return urllib.request.urlopen(r, timeout=60).read()


def upload(port, path, name):
    b = uuid.uuid4().hex
    body = (("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\nContent-Type: image/png\r\n\r\n" % (b, name)).encode()
            + open(path, "rb").read() + ("\r\n--%s\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--%s--\r\n" % (b, b)).encode())
    return json.loads(req(port, "/upload/image", body, {"Content-Type": "multipart/form-data; boundary=" + b}))["name"]


def workflow(a, ref_name, mesh):
    w = {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": a.unet}},
        "2": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "3": {"class_type": "UltraTexLoraLoader", "inputs": {"model": ["1", 0], "lora_name": "ultratex_flux2.safetensors", "strength": 1.0}},
        "4": {"class_type": "UltraTexForegroundDecoder", "inputs": {"vae": ["2", 0], "decoder_name": "ultratex_flux2_decoder.pt"}},
        "5": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_8b_fp8mixed.safetensors", "type": "flux2", "device": "default"}},
        "6": {"class_type": "UltraTexTextEncode", "inputs": {"clip": ["5", 0], "text": ""}},
        "7": {"class_type": "LoadImage", "inputs": {"image": ref_name}},
        "8": {"class_type": "UltraTexPrep", "inputs": {
            "reference_image": ["7", 0], "reference_mask": ["7", 1], "mesh_path": mesh, "render_size": a.render,
            "atlas_size": a.tex, "uv_mode": "keep_existing", "reference_alignment": "fit_front_silhouette",
            "mask_meaning": "background (LoadImage)"}},
        "9": {"class_type": "UltraTexSampler", "inputs": {
            "model": ["3", 0], "vae": ["4", 0], "positive": ["6", 0], "prep": ["8", 0], "resolution": a.res,
            "steps": a.steps, "seed": a.seed, "guidance": 2.0, "drop_background_tokens": True, "memory_factor": a.memfac,
            "attention": a.attention, "sparse_topk": 0.2, "token_chunk": 8192, "denoise": 1.0}},
        "10": {"class_type": "UltraTexBake", "inputs": {
            "prep": ["8", 0], "albedo_views": ["9", 0], "texture_size": a.tex, "filename_prefix": "ultratex_run/" + a.tag,
            "view_weight_power": 4.0, "best_view_mix": 0.5, "edge_feather_px": 6.0}},
        "11": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": "ultratex_run/" + a.tag + "_views"}},
        "12": {"class_type": "SaveImage", "inputs": {"images": ["10", 1], "filename_prefix": "ultratex_run/" + a.tag + "_albedo"}},
    }
    return w


def poll_vram(stop, out):
    while not stop.is_set():
        try:
            v = int(subprocess.check_output(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"]).split()[0])
            out.append(v)
        except Exception:
            pass
        time.sleep(0.5)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mesh"); p.add_argument("front"); p.add_argument("out")
    p.add_argument("--res", type=int, default=1024); p.add_argument("--tex", type=int, default=2048)
    p.add_argument("--render", type=int, default=2048); p.add_argument("--steps", type=int, default=25)
    p.add_argument("--seed", type=int, default=12345); p.add_argument("--port", type=int, default=8075)
    p.add_argument("--unet", default="flux-2-klein-base-9b-Q4_K_M.gguf"); p.add_argument("--tag", default="run")
    p.add_argument("--attention", default="ultratex_sparse"); p.add_argument("--memfac", type=float, default=0.0)
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    ref = upload(a.port, a.front, a.tag + "_front.png")
    w = workflow(a, ref, os.path.abspath(a.mesh))
    vr, stop = [], threading.Event()
    base = None
    try:
        base = int(subprocess.check_output(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"]).split()[0])
    except Exception:
        pass
    th = threading.Thread(target=poll_vram, args=(stop, vr), daemon=True); th.start()
    t0 = time.time()
    pid = json.loads(req(a.port, "/prompt", json.dumps({"prompt": w}).encode(), {"Content-Type": "application/json"}))["prompt_id"]
    print("queued", pid)
    hist = None
    while True:
        time.sleep(2)
        h = json.loads(req(a.port, "/history/" + pid))
        if pid in h and h[pid].get("status", {}).get("completed") is not None and (h[pid]["status"]["completed"] or h[pid]["status"].get("status_str") == "error"):
            hist = h[pid]; break
    stop.set(); th.join()
    dt = time.time() - t0
    st = hist["status"]
    msgs = json.dumps(st.get("messages", [])[-3:])[:1500]
    if st.get("status_str") == "error":
        print("ERROR", msgs); sys.exit(1)
    outs = hist["outputs"]
    out_dir = os.path.join(COMFY, "output")
    for nid, key, dst in (("11", "images", "views.png"), ("12", "images", "albedo_raw.png")):
        for im in outs.get(nid, {}).get(key, [])[:1]:
            shutil.copy(os.path.join(out_dir, im.get("subfolder", ""), im["filename"]), os.path.join(a.out, dst))
    glb = [f for f in os.listdir(os.path.join(out_dir, "ultratex_run")) if f.startswith(a.tag + "_") and f.endswith(".glb")]
    if glb:
        glb.sort(); shutil.copy(os.path.join(out_dir, "ultratex_run", glb[-1]), os.path.join(a.out, "out.glb"))
    peak = max(vr) if vr else -1
    s = "%s res %d tex %d steps %d: %.1f s total, peak VRAM %d MiB (baseline %s MiB)\n" % (a.tag, a.res, a.tex, a.steps, dt, peak, base)
    open(os.path.join(a.out, "stats.txt"), "a").write(s); print(s)


if __name__ == "__main__":
    main()
