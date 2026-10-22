#!/usr/bin/env python3
"""Faction crests: FLUX.2 Klein 4B (distilled, Apache-2.0) edits our drawn mark into a painted crest. Stdlib only.

  godot --resolution 512x512 --script res://tools/menu_art/render_refs.gd -- --out=REF_DIR      # the references
  python3 tools/menu_art/crests.py REF_DIR OUT_DIR [--only west/england,rome/rome] [--seeds 1,2,3,4] [--port 8076]

Graph = ComfyUI's template image_flux2_klein_image_edit_4b_distilled (reference-image edit): the reference goes through
ImageScaleToTotalPixels (1 MP) and VAEEncode into a ReferenceLatent on the positive and the (zeroed) negative
conditioning, 4 steps, CFG 1, euler. Writes OUT_DIR/<pack>_<key>_<seed>.png (1024 px). ComfyUI must be running on PORT.
"""
import argparse, json, os, shutil, time, urllib.request, uuid

COMFY = os.path.expanduser("~/Applications/ComfyUI")
STYLE = "flat vector heraldry, gold and %s on white, clean edges, bold simple shapes, no text"
# pack/key -> (name, character, colour word); the prompt is "heraldic crest of <name>, <character>, STYLE"
CRESTS = {
    "west/new_spain": ("New Spain", "Spanish crown over a galleon and a red saltire", "red"),
    "west/tierra_firme": ("Tierra Firme", "a gold castle over a silver coast and a red saltire", "silver and red"),
    "west/england": ("England", "a crowned shield with the red cross of St George and a lion", "red"),
    "west/france": ("France", "three golden fleurs-de-lis under a crown", "blue"),
    "west/dutch": ("the Dutch", "a golden lion rampant over an orange, white and blue banner", "orange and blue"),
    "west/brethren": ("the Brethren of the Coast", "black flag, skull and crossed cutlasses", "black"),
    "west/itza": ("the Maya Itza", "Maya sun disc and jaguar with jade", "jade green"),
    "west/miskito": ("the Miskito", "a green turtle with feathers", "blue"),
    "rome/rome": ("Rome", "Roman eagle and laurel", "red"),
    "rome/carthage": ("Carthage", "a war elephant and the sacred palm", "purple"),
    "rome/macedon": ("Macedon", "the Vergina sunburst and a Macedonian helmet", "gold"),
    "rome/epirus": ("Epirus", "an eagle with spread wings over a Molossian hound", "orange"),
    "rome/greeks": ("the Greek League", "a hoplite shield and a Corinthian helmet", "blue"),
    "rome/syracuse": ("Syracuse", "Arethusa head ringed by dolphins and a trireme", "teal"),
    "rome/iberians": ("the Iberian tribes", "a falcata sword and a round caetra shield", "brown"),
    "rome/gauls": ("the Gallic tribes", "a carnyx war horn and a boar", "green"),
}


def req(port, path, data=None, headers=None):
    h = headers or ({"Content-Type": "application/json"} if data else {})
    return urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:%d%s" % (port, path), data=data, headers=h), timeout=120).read()


def upload(port, path, name):
    b = uuid.uuid4().hex
    body = (("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\nContent-Type: image/png\r\n\r\n" % (b, name)).encode()
            + open(path, "rb").read() + ("\r\n--%s\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--%s--\r\n" % (b, b)).encode())
    return json.loads(req(port, "/upload/image", body, {"Content-Type": "multipart/form-data; boundary=" + b}))["name"]


def graph(prompt, image, seed, prefix):
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux-2-klein-4b-fp8.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "flux2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "5": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
        "20": {"class_type": "LoadImage", "inputs": {"image": image}},
        "21": {"class_type": "ImageScaleToTotalPixels", "inputs": {"image": ["20", 0], "upscale_method": "nearest-exact", "megapixels": 1.0, "resolution_steps": 1}},
        "22": {"class_type": "VAEEncode", "inputs": {"pixels": ["21", 0], "vae": ["3", 0]}},
        "23": {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["4", 0], "latent": ["22", 0]}},
        "24": {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["5", 0], "latent": ["22", 0]}},
        "25": {"class_type": "GetImageSize", "inputs": {"image": ["21", 0]}},
        "6": {"class_type": "CFGGuider", "inputs": {"model": ["1", 0], "positive": ["23", 0], "negative": ["24", 0], "cfg": 1.0}},
        "7": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "8": {"class_type": "Flux2Scheduler", "inputs": {"steps": 4, "width": ["25", 0], "height": ["25", 1]}},
        "9": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": ["25", 0], "height": ["25", 1], "batch_size": 1}},
        "10": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "11": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["10", 0], "guider": ["6", 0], "sampler": ["7", 0],
                                                                 "sigmas": ["8", 0], "latent_image": ["9", 0]}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("ref"); p.add_argument("out"); p.add_argument("--only"); p.add_argument("--seeds", default="1,2,3,4")
    p.add_argument("--port", type=int, default=8076); p.add_argument("--extra", default="", help="appended to every prompt")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    keys = a.only.split(",") if a.only else list(CRESTS)
    for k in keys:
        name, char, col = CRESTS[k]
        prompt = "heraldic crest of %s, %s, %s%s" % (name, char, STYLE % col, a.extra)
        img = upload(a.port, os.path.join(a.ref, k + ".png"), k.replace("/", "_") + ".png")
        for seed in [int(s) for s in a.seeds.split(",")]:
            tag = "%s_%d" % (k.replace("/", "_"), seed)
            t0 = time.time()
            pid = json.loads(req(a.port, "/prompt", json.dumps({"prompt": graph(prompt, img, seed, "crests/" + tag)}).encode()))["prompt_id"]
            while True:
                time.sleep(0.5)
                hist = json.loads(req(a.port, "/history/" + pid))
                if pid in hist and hist[pid]["status"].get("completed") is not None:
                    break
            st = hist[pid]["status"]
            if st.get("status_str") == "error":
                raise SystemExit("ERROR " + json.dumps(st["messages"][-2:])[:1500])
            im = hist[pid]["outputs"]["13"]["images"][0]
            shutil.copy(os.path.join(COMFY, "output", im.get("subfolder", ""), im["filename"]), os.path.join(a.out, tag + ".png"))
            print(tag, "ok %.1f s" % (time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
