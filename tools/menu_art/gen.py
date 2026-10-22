#!/usr/bin/env python3
"""Text-to-image through a local ComfyUI HTTP API with FLUX.2 Klein 4B (distilled, Apache-2.0). Stdlib only.

  python3 tools/menu_art/gen.py OUT_DIR --kind emblem|keyart --side west|rome --seeds 1,2,3 [--port 8076]

ComfyUI must be running: cd ~/Applications/ComfyUI && .venv/bin/python main.py --port 8076 --listen 127.0.0.1
Models: diffusion_models/flux-2-klein-4b-fp8.safetensors, text_encoders/qwen_3_4b.safetensors, vae/flux2-vae.safetensors.
Graph = ComfyUI's template image_flux2_klein_text_to_image (distilled branch: 4 steps, CFG 1, zeroed negative).
Writes OUT_DIR/<kind>_<side>_<seed>.png.
"""
import argparse, json, os, shutil, time, urllib.request

COMFY = os.path.expanduser("~/Applications/ComfyUI")
PROMPTS = {
    ("emblem", "west"): "emblem of a pirate brotherhood, black flag, compass rose, crossed cutlasses, flat vector heraldry, two colours, white background",
    ("emblem", "rome"): "Roman legion emblem, eagle aquila over a laurel wreath, flat vector heraldry, two colours, white background",
    ("keyart", "west"): "a pirate harbour town at dusk from the sea, palms, a fort on the headland, a frigate at anchor, painted, warm light, wide shot, no text",
    ("keyart", "rome"): "the Bay of Naples from the sea at dawn, a Roman city on the shore, galleys, painted, cool light, wide shot, no text",
}
SIZE = {"emblem": (1024, 1024), "keyart": (1344, 768)}


def req(port, path, data=None):
    h = {"Content-Type": "application/json"} if data else {}
    return urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:%d%s" % (port, path), data=data, headers=h), timeout=60).read()


def graph(prompt, w, h, seed, prefix):
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux-2-klein-4b-fp8.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "flux2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "5": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
        "6": {"class_type": "CFGGuider", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0], "cfg": 1.0}},
        "7": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "8": {"class_type": "Flux2Scheduler", "inputs": {"steps": 4, "width": w, "height": h}},
        "9": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "10": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "11": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["10", 0], "guider": ["6", 0], "sampler": ["7", 0],
                                                                 "sigmas": ["8", 0], "latent_image": ["9", 0]}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("out"); p.add_argument("--kind", required=True, choices=["emblem", "keyart"])
    p.add_argument("--side", required=True, choices=["west", "rome"]); p.add_argument("--seeds", required=True)
    p.add_argument("--port", type=int, default=8076); p.add_argument("--prompt")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    w, h = SIZE[a.kind]
    prompt = a.prompt or PROMPTS[(a.kind, a.side)]
    for seed in [int(s) for s in a.seeds.split(",")]:
        name = "%s_%s_%d" % (a.kind, a.side, seed)
        t0 = time.time()
        pid = json.loads(req(a.port, "/prompt", json.dumps({"prompt": graph(prompt, w, h, seed, "menu_art/" + name)}).encode()))["prompt_id"]
        while True:
            time.sleep(1)
            hist = json.loads(req(a.port, "/history/" + pid))
            if pid in hist and hist[pid]["status"].get("completed") is not None:
                break
        st = hist[pid]["status"]
        if st.get("status_str") == "error":
            raise SystemExit("ERROR " + json.dumps(st["messages"][-2:])[:1500])
        im = hist[pid]["outputs"]["13"]["images"][0]
        shutil.copy(os.path.join(COMFY, "output", im.get("subfolder", ""), im["filename"]), os.path.join(a.out, name + ".png"))
        print(name, "ok %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main()
