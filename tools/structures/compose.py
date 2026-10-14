"""Recolour the structure renders with faction palettes and make the boards.

    python3 tools/structures/compose.py boards [--frames DIR] [--out DIR]
    python3 tools/structures/compose.py mockup SHOTS_DIR [--style D] [--out DIR]

numpy for the maths, ImageMagick (`convert`) only for PNG in / out, resize
and text (no PIL needed). `boards` writes board_<style>.png (all structures,
96 and 256 px, two palettes) and compare.png (styles side by side).
`mockup` pastes sprites onto overworld screenshots made by the harness
(positions in SHOTS_DIR/pos.json).
"""
import json
import os
import subprocess
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = json.load(open(os.path.join(HERE, "spec.json")))
PAL = {k: {c: np.array(v, np.float32) for c, v in p.items()} for k, p in SPEC["palettes"].items()}


def arg(name, default):
    a = sys.argv
    return a[a.index(name) + 1] if name in a else default


def load(path):
    w, h = subprocess.check_output(["identify", "-format", "%w %h", path + "[0]"]).split()
    w, h = int(w), int(h)
    raw = subprocess.check_output(["convert", path + "[0]", "-depth", "8", "-alpha", "on", "rgba:-"])
    return np.frombuffer(raw, np.uint8).reshape(h, w, 4).astype(np.float32) / 255.0


def save(path, arr):
    a = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, c = a.shape
    fmt = "rgba" if c == 4 else "rgb"
    subprocess.run(["convert", "-size", "%dx%d" % (w, h), "-depth", "8", fmt + ":-", path],
                   input=a.tobytes(), check=True)


def resize(arr, w, h):
    a = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    hh, ww, _ = a.shape
    raw = subprocess.run(["convert", "-size", "%dx%d" % (ww, hh), "-depth", "8", "rgba:-",
                          "-filter", "Lanczos", "-resize", "%dx%d!" % (w, h), "-depth", "8", "rgba:-"],
                         input=a.tobytes(), check=True, stdout=subprocess.PIPE).stdout
    return np.frombuffer(raw, np.uint8).reshape(h, w, 4).astype(np.float32) / 255.0


def recolour(shade, mask, pal):
    w = mask[..., :3]
    P = PAL[pal]
    tint = w[..., :1] * P["primary"] + w[..., 1:2] * P["secondary"] + w[..., 2:3] * P["accent"]
    tint = tint + (1.0 - np.clip(w.sum(-1, keepdims=True), 0, 1))
    out = shade.copy()
    out[..., :3] = np.clip(shade[..., :3] * tint, 0, 1)
    return out


def over(bg, spr, x, y):
    """Alpha-composite spr (straight alpha) onto bg (RGB or RGBA) at top-left x, y."""
    H, W = bg.shape[:2]
    h, w = spr.shape[:2]
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + w, W), min(y + h, H)
    if x1 <= x0 or y1 <= y0:
        return
    s = spr[y0 - y:y1 - y, x0 - x:x1 - x]
    a = s[..., 3:4]
    d = bg[y0:y1, x0:x1]
    d[..., :3] = d[..., :3] * (1 - a) + s[..., :3] * a


def sprite(frames, style, key, size, pal):
    base = os.path.join(frames, style, "%s_%d" % (key, size))
    sh = load(base + "_shade.png")
    mk = load(base + "_mask.png")
    info = json.load(open(base + ".json"))
    return recolour(sh, mk, pal), info


def texts(img_path, items):
    """items: (x, y, text, pointsize, colour)"""
    cmd = ["convert", img_path, "-font", "DejaVu-Sans-Bold"]
    for x, y, t, ps, col in items:
        cmd += ["-fill", col, "-pointsize", str(ps), "-annotate", "+%d+%d" % (x, y), t]
    cmd += [img_path]
    subprocess.run(cmd, check=True)


def backdrop(w, h):
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    c0 = np.array([0.55, 0.49, 0.37], np.float32)
    c1 = np.array([0.47, 0.42, 0.33], np.float32)
    return np.ones((h, w, 3), np.float32) * (c0 * (1 - y) + c1 * y)


def boards(frames, out):
    keys = list(SPEC["structures"].keys())
    styles = [s for s in "ABCD" if os.path.isdir(os.path.join(frames, s))]
    names = {"A": "A: 2-band cel, ink outline", "B": "B: 3-band warm/cool, coloured outline, AO",
             "C": "C: flat painted, no outline", "D": "D: painted miniature on a base"}
    for style in styles:
        gw = 270 * 2 + 112 * 2 + 20
        rows = 4
        rh = 284
        W, H = gw * 2 + 30, rows * rh + 56
        img = backdrop(W, H)
        tx = [(14, 34, "Style " + names[style] + "   (columns: 256 px Spain, 256 px England, 96 px Spain, 96 px England)", 22, "white")]
        for i, key in enumerate(keys):
            gx = 15 + (i // rows) * (gw + 0)
            gy = 56 + (i % rows) * rh
            x = gx
            for size, pal in ((256, "spain"), (256, "england"), (96, "spain"), (96, "england")):
                if not os.path.exists(os.path.join(frames, style, "%s_%d_shade.png" % (key, size))):
                    continue
                spr, info = sprite(frames, style, key, size, pal)
                cw = 270 if size == 256 else 112
                ch = 270 if size == 256 else 112
                yb = gy + (270 - ch) // 2 + (ch - spr.shape[0]) // 2 if size == 96 else gy + (270 - spr.shape[0]) // 2
                over(img, spr, x + (cw - spr.shape[1]) // 2, yb)
                x += cw
            tx.append((gx + 4, gy + 18, SPEC["structures"][key]["name"], 17, "white"))
        p = os.path.join(out, "board_%s.png" % style)
        save(p, img)
        texts(p, tx)
        print("wrote", p)
    # compare: rows structures, columns styles (256 px, Spain)
    if len(styles) > 1:
        cw = 230
        W, H = cw * len(styles) + 20, cw * len(keys) + 56
        img = backdrop(W, H)
        tx = [(10 + i * cw, 34, "Style " + s, 22, "white") for i, s in enumerate(styles)]
        for r, key in enumerate(keys):
            for c, style in enumerate(styles):
                spr, info = sprite(frames, style, key, 256, "spain")
                k = cw / 256.0 * 0.96
                spr2 = resize(spr, max(1, int(spr.shape[1] * k)), max(1, int(spr.shape[0] * k)))
                over(img, spr2, 10 + c * cw + (cw - spr2.shape[1]) // 2, 50 + r * cw + (cw - spr2.shape[0]) // 2)
        p = os.path.join(out, "compare.png")
        save(p, img)
        texts(p, tx)
        print("wrote", p)


SITES = [  # settlement key, structure, palette, overview width px, caption
    ("havana", "star_fort", "spain", 150, "La Habana: star fort"),
    ("port_royal", "port", "england", 150, "Port Royal: harbour"),
    ("bluefields", "native_village", "native", 115, "Bluefields: native village"),
    ("port_de_paix", "pirate_haven", "pirates", 125, "Port-de-Paix: pirate haven"),
    ("tayasal", "maya_temple", "native", 135, "Tayasal: Maya temple"),
]
UI_SCALE = 1.875  # the harness prints canvas px; screenshots are 1920 wide on a 1024 canvas


def parse_pos(shots):
    out = {}
    for line in open(os.path.join(shots, "pos.txt")):
        parts = line.split()
        if parts[0] != "POS":
            continue
        d = {}
        for tok in parts[3:]:
            k, v = tok.split("=")
            x, y = v.split(",")
            d[k] = (float(x) * UI_SCALE, float(y) * UI_SCALE)
        out[parts[1]] = d
    return out


def pick_sprite(frames, style, key, pal, want_w):
    sizes = sorted(int(f.split("_")[-2]) for f in os.listdir(os.path.join(frames, style))
                   if f.startswith(key + "_") and f.endswith("_shade.png"))
    spr = info = None
    for sz in sizes:
        spr, info = sprite(frames, style, key, sz, pal)
        if spr.shape[1] >= want_w:
            break
    k = want_w / spr.shape[1]
    r = resize(spr, want_w, max(1, int(round(spr.shape[0] * k))))
    ox, oy = info["origin_px"]
    return r, (ox * k, oy * k)


def blur_alpha(a, r):
    h, w = a.shape
    small = resize(np.dstack([a, a, a, np.ones_like(a)]), max(1, w // r), max(1, h // r))
    big = resize(small, w, h)
    return big[..., 0]


def paste(img, frames, style, key, pal, anchor, want_w, shadow=True):
    spr, (ox, oy) = pick_sprite(frames, style, key, pal, want_w)
    x, y = int(round(anchor[0] - ox)), int(round(anchor[1] - oy))
    if shadow:
        pad = 24
        a = np.zeros((spr.shape[0] + 2 * pad, spr.shape[1] + 2 * pad), np.float32)
        a[pad:-pad, pad:-pad] = spr[..., 3]
        sh = blur_alpha(a, 6) * 0.45
        sh = np.roll(np.roll(sh, int(want_w * 0.03), 1), int(want_w * 0.04), 0)
        layer = np.zeros(a.shape + (4,), np.float32)
        layer[..., 3] = sh
        layer[..., :3] = (0.05, 0.06, 0.1)
        over(img, layer, x - pad, y - pad)
    over(img, spr, x, y)


def mockups(frames, shots, out, style, terrain=False):
    pos = parse_pos(shots)
    base = load(os.path.join(shots, "all.png"))[..., :3]
    tag = style + ("_terrain" if terrain else "")
    img = stylise(base) if terrain else base.copy()
    for key, struct, pal, w, cap in SITES:
        if key in pos["all"]:
            paste(img, frames, style, struct, pal, pos["all"][key], w)
    p = os.path.join(out, "mockup_%s_overview.png" % tag)
    save(p, img)
    print("wrote", p)
    # close-ups: crops around each site at zoom 1.8
    cw, ch = 640, 520
    sheet = backdrop(cw * 3, ch * 2 + 0)
    items = []
    for i, (key, struct, pal, w, cap) in enumerate(SITES):
        shot = load(os.path.join(shots, key + ".png"))[..., :3]
        im = stylise(shot) if terrain else shot.copy()
        anc = pos[key][key]
        paste(im, frames, style, struct, pal, anc, int(w * 2.5))
        cx, cy = int(anc[0]) - cw // 2, int(anc[1]) - ch // 2 - 40
        cx = min(max(cx, 0), im.shape[1] - cw)
        cy = min(max(cy, 0), im.shape[0] - ch)
        sheet[(i // 3) * ch:(i // 3 + 1) * ch, (i % 3) * cw:(i % 3 + 1) * cw] = im[cy:cy + ch, cx:cx + cw]
        items.append(((i % 3) * cw + 10, (i // 3) * ch + 28, cap, 20, "white"))
    p = os.path.join(out, "mockup_%s_close.png" % tag)
    save(p, sheet)
    texts(p, items)
    print("wrote", p)


def gauss_img(img, sigma):
    a = np.dstack([img, np.ones(img.shape[:2], np.float32)])
    a8 = (np.clip(a, 0, 1) * 255 + .5).astype(np.uint8)
    h, w, _ = a8.shape
    raw = subprocess.run(["convert", "-size", "%dx%d" % (w, h), "-depth", "8", "rgba:-", "-blur", "0x%g" % sigma,
                          "-depth", "8", "rgba:-"], input=a8.tobytes(), check=True, stdout=subprocess.PIPE).stdout
    return np.frombuffer(raw, np.uint8).reshape(h, w, 4)[..., :3].astype(np.float32) / 255.0


def stylise(img):
    """Fake the restyled terrain: stepped relief (posterised
    luminance with ink contours), richer palette, tilt-shift blur, parchment
    border. Post-processing only: a mock of the look, not the real renderer."""
    img = img.copy()
    H, W, _ = img.shape
    img = gauss_img(img, 0.8)
    L = img @ np.array([0.30, 0.59, 0.11], np.float32)
    K = 8.0
    q = np.floor(L * 1.9 * K) / K / 1.9  # map is dark: spread over its range
    gain = (q + 0.02) / (L + 0.02)
    out = img * (0.45 + 0.55 * gain[..., None])
    # richer, brighter palette
    mean = out.mean(-1, keepdims=True)
    out = mean + (out - mean) * 1.8
    sea = (out[..., 2] > out[..., 0] * 1.1)[..., None]
    out = np.where(sea, out * np.array([0.9, 1.5, 1.7], np.float32), out * np.array([1.55, 1.35, 1.0], np.float32))
    out = 1 - np.exp(-out * 1.6)
    # ink contour where the band changes
    dq = np.abs(q - np.roll(q, 1, 0)) + np.abs(q - np.roll(q, 1, 1))
    edge = (dq > 0.001)[..., None]
    edge = np.clip(gauss_img(np.repeat(edge.astype(np.float32), 3, -1), 0.6)[..., :1] * 2.2, 0, 1)
    out = out * (1 - 0.30 * edge)
    # tilt-shift: blur far from a focus band
    yy = np.abs(np.linspace(-1, 1, H, dtype=np.float32) + 0.1)[:, None, None]
    m = np.clip((yy - 0.35) * 1.8, 0, 1)
    out = out * (1 - m) + gauss_img(out, 4.0) * m
    # parchment border + vignette
    fr = 54
    rng = np.random.RandomState(3)
    paper = np.array([0.88, 0.80, 0.60], np.float32) + rng.normal(0, 0.02, (H, W, 1)).astype(np.float32)
    paper = gauss_img(np.clip(paper, 0, 1), 0.7)
    d = np.minimum(np.minimum(np.arange(W)[None, :], W - 1 - np.arange(W)[None, :]),
                   np.minimum(np.arange(H)[:, None], H - 1 - np.arange(H)[:, None])).astype(np.float32)
    vig = np.clip(d / 160.0, 0, 1)[..., None]
    out = out * (0.72 + 0.28 * vig)
    inside = (d >= fr)[..., None]
    line = ((d >= fr) & (d < fr + 3))[..., None]
    shadow = np.clip(1 - (d - fr) / 26.0, 0, 1)[..., None] * (d >= fr)[..., None]
    out = np.where(inside, out * (1 - 0.35 * shadow), paper * (0.9 + 0.1 * np.clip(d / fr, 0, 1)[..., None]))
    out = np.where(line, np.array([0.30, 0.18, 0.08], np.float32), out)
    return np.clip(out, 0, 1)


if __name__ == "__main__":
    cmd = sys.argv[1]
    frames = arg("--frames", os.path.join(HERE, "_frames"))
    out = arg("--out", frames)
    os.makedirs(out, exist_ok=True)
    if cmd == "boards":
        boards(frames, out)
    elif cmd == "mockup":
        shots = sys.argv[2]
        for st in arg("--styles", "A,B,C,D").split(","):
            mockups(frames, shots, out, st)
            if st == "D":
                mockups(frames, shots, out, st, terrain=True)
