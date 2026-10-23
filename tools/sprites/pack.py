#!/usr/bin/env python3
"""Sprite pipeline: pack the frames rendered by build.py into the game's
atlas (step 1b: assets/sprites/atlas_shade.png + atlas_mask.png, see
pack_atlas) and write the manifest and the generated game tables
(game/sprite_atlas.gd, game/sprite_frames.gdshaderinc); the iso test goes
to tools/sprites/iso/. The per-sheet notes below hold for the atlas too. Python 3 standard library only (its own PNG
reader / writer on zlib).

    python3 tools/sprites/pack.py [--frames tools/sprites/_frames]
        [--out assets/sprites] [--contact /path/contact.png]

Per frame: alpha is made hard (>= 50% covered = opaque) and a 1 px dark
outline (spec "outline") is added outside the silhouette (4-neighbours).
Per action, all its frames are cropped to their union box (+1 px for the
outline) so they share one size and one anchor. Per unit two sheets with the
same layout (one row per action, 2 px transparent gutters):

  <unit>_shade.png  RGBA: lit albedo, team parts lit white (multiply by the
                    palette colour), outline dark;
  <unit>_mask.png   RGBA: R primary, G secondary, B accent weights (0-255),
                    A = 255 - 128 * check (cloth check pattern weight); 0,0,0,255
                    outside the figure and on the outline (never alpha 0, so
                    no importer's alpha-border fix can touch it).

Recolour (see tools/sprites/preview/recolor.gdshader):
  pat  = (1 - mask.a) * 2
  team = mask.r * mix(primary, pattern, pat * pattern_k)
         + mask.g * secondary + mask.b * accent
  rgb  = shade.rgb * ((1 - mask.r - mask.g - mask.b) + team)

`--contact` also writes an upscaled preview PNG (all units x palettes x
actions on grass, recoloured here in Python) for a quick look without Godot.
"""

import json
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SPEC = json.load(open(os.path.join(HERE, "spec.json")))
GUTTER = 2


# ---------------------------------------------------------------- PNG I/O

def png_read(path):
    """-> (w, h, bytearray RGBA). 8-bit RGB / RGBA / grey(+alpha), no
    interlace (what Blender writes)."""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos = 8
    idat = b""
    w = h = ctype = 0
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, depth, ctype, _c, _f, inter = struct.unpack(">IIBBBBB", chunk)
            assert depth == 8 and inter == 0, (path, depth, inter)
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    ch = {6: 4, 2: 3, 4: 2, 0: 1}[ctype]
    raw = zlib.decompress(idat)
    stride = w * ch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    if ch == 4:
        return w, h, out
    rgba = bytearray(w * h * 4)
    for i in range(w * h):
        if ch == 3:
            rgba[i * 4:i * 4 + 3] = out[i * 3:i * 3 + 3]; rgba[i * 4 + 3] = 255
        elif ch == 2:
            g = out[i * 2]; rgba[i * 4:i * 4 + 4] = bytes((g, g, g, out[i * 2 + 1]))
        else:
            g = out[i]; rgba[i * 4:i * 4 + 4] = bytes((g, g, g, 255))
    return w, h, rgba


def png_write(path, w, h, rgba):
    stride = w * 4
    raw = bytearray()
    prev = bytes(stride)
    for y in range(h):
        line = rgba[y * stride:(y + 1) * stride]
        # filter Sub for rows (good for flat sprite colours), Up otherwise
        sub = bytearray(stride)
        for i in range(stride):
            sub[i] = (line[i] - (line[i - 4] if i >= 4 else 0)) & 255
        up = bytearray((line[i] - prev[i]) & 255 for i in range(stride))
        if sum(min(b, 256 - b) for b in up) < sum(min(b, 256 - b) for b in sub):
            raw += b"\x02" + up
        else:
            raw += b"\x01" + sub
        prev = line
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


# ---------------------------------------------------------------- images

class Img:
    def __init__(self, w, h, px=None, fill=(0, 0, 0, 0)):
        self.w, self.h = w, h
        self.px = px if px is not None else bytearray(bytes(fill) * (w * h))

    @staticmethod
    def load(path):
        w, h, px = png_read(path)
        return Img(w, h, px)

    def get(self, x, y):
        i = (y * self.w + x) * 4
        return self.px[i:i + 4]

    def put(self, x, y, c):
        i = (y * self.w + x) * 4
        self.px[i:i + 4] = bytes(c)

    def crop(self, x0, y0, w, h, fill=(0, 0, 0, 0)):
        o = Img(w, h, fill=fill)
        for y in range(h):
            for x in range(w):
                sx, sy = x0 + x, y0 + y
                if 0 <= sx < self.w and 0 <= sy < self.h:
                    o.put(x, y, self.get(sx, sy))
        return o

    def blit(self, src, dx, dy):
        for y in range(src.h):
            i = ((dy + y) * self.w + dx) * 4
            self.px[i:i + src.w * 4] = src.px[y * src.w * 4:(y + 1) * src.w * 4]

    def save(self, path):
        png_write(path, self.w, self.h, self.px)


def alpha_box(img, thr=128):
    xs, ys = [], []
    for y in range(img.h):
        for x in range(img.w):
            if img.px[(y * img.w + x) * 4 + 3] >= thr:
                xs.append(x); ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def finish_frame(shade, mask, pat, outline):
    """Hard alpha, 1 px outline; mask alpha carries the pattern."""
    w, h = shade.w, shade.h
    solid = [shade.px[i * 4 + 3] >= 128 for i in range(w * h)]
    s = Img(w, h)
    m = Img(w, h, fill=(0, 0, 0, 255))
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if solid[i]:
                r, g, b, _a = shade.px[i * 4:i * 4 + 4]
                s.put(x, y, (r, g, b, 255))
                mr, mg, mb, _ = mask.px[i * 4:i * 4 + 4]
                tot = mr + mg + mb
                if tot > 255:  # AA blends may overshoot slightly
                    mr, mg, mb = (mr * 255 // tot, mg * 255 // tot, mb * 255 // tot)
                p = pat.px[i * 4]
                m.put(x, y, (mr, mg, mb, 255 - (p * 128 + 127) // 255))
            else:
                edge = ((x > 0 and solid[i - 1]) or (x < w - 1 and solid[i + 1])
                        or (y > 0 and solid[i - w]) or (y < h - 1 and solid[i + w]))
                if edge:
                    s.put(x, y, outline + (255,))
                else:
                    s.put(x, y, outline + (0,))  # dark rgb: mip fringes stay dark
    return s, m


# ---------------------------------------------------------------- packing

def pack_rows(rows, out_dir, name):
    """rows: list of (key, [ (shade, mask) ... ], anchor_in_frame).
    -> manifest entries and writes <name>_shade.png / _mask.png."""
    W = max(GUTTER + len(fr) * (fr[0][0].w + GUTTER) for _k, fr, _a in rows)
    H = GUTTER + sum(fr[0][0].h + GUTTER for _k, fr, _a in rows)
    oc = tuple(int(round(c * 255)) for c in SPEC["outline"])
    sheet_s = Img(W, H, fill=oc + (0,))
    sheet_m = Img(W, H, fill=(0, 0, 0, 255))
    entries = {}
    y = GUTTER
    for key, frames, anchor in rows:
        fw, fh = frames[0][0].w, frames[0][0].h
        rects = []
        x = GUTTER
        for s, m in frames:
            sheet_s.blit(s, x, y)
            sheet_m.blit(m, x, y)
            rects.append([x, y, fw, fh])
            x += fw + GUTTER
        entries[key] = {"frames": rects, "anchor": [round(anchor[0], 2), round(anchor[1], 2)]}
        y += fh + GUTTER
    sheet_s.save(os.path.join(out_dir, name + "_shade.png"))
    sheet_m.save(os.path.join(out_dir, name + "_mask.png"))
    return entries, [W, H]


def pack_atlas(strips, out_dir, align, gutter, oc):
    """One shade + one mask atlas for every unit's actions (the game's).
    A strip = one action's frames side by side; strips go on shelves,
    tallest first. Every frame starts on a multiple of `align` px with at
    least `gutter` px of empty border, so mip levels up to log2(align)
    never mix two frames. -> ({(uid, act): rects, anchor, step}, [W, H])."""
    def up(v):
        return (v + align - 1) // align * align
    W = 512
    while True:
        order = sorted(range(len(strips)), key=lambda i: (-strips[i][2][0][0].h, i))
        pos = {}
        x, y, shelf_h = gutter, gutter, 0
        ok = True
        for i in order:
            fr = strips[i][2]
            fw, fh = fr[0][0].w, fr[0][0].h
            step = up(fw + gutter)
            sw = step * len(fr)
            if x + sw > W:
                x, y = gutter, up(y + shelf_h + gutter)
                shelf_h = 0
                if sw + gutter > W:
                    ok = False
                    break
            x = up(x)
            y = up(y)
            pos[i] = (x, y, step)
            x += sw
            shelf_h = max(shelf_h, fh)
        if ok:
            break
        W *= 2
    H = up(y + shelf_h + gutter)
    sheet_s = Img(W, H, fill=oc + (0,))
    sheet_m = Img(W, H, fill=(0, 0, 0, 255))
    placed = {}
    for i, (uid, act, frames, anchor) in enumerate(strips):
        x0, y0, step = pos[i]
        rects = []
        for k, (sh, mk) in enumerate(frames):
            sheet_s.blit(sh, x0 + k * step, y0)
            sheet_m.blit(mk, x0 + k * step, y0)
            rects.append([x0 + k * step, y0, sh.w, sh.h])
        placed[(uid, act)] = {"rects": rects, "anchor": [round(anchor[0], 2), round(anchor[1], 2)], "step": step}
    sheet_s.save(os.path.join(out_dir, "atlas_shade.png"))
    sheet_m.save(os.path.join(out_dir, "atlas_mask.png"))
    return placed, [W, H]


def _has(act, uid):
    """Actions with a "units" list in the spec exist for those units only;
    the others point their table rows at the walk."""
    us = SPEC["actions"][act].get("units")
    return us is None or uid in us


def load_action(d, prefix, n, oc):
    """Load frames <prefix>_<i>_*.png, crop to their union box (+1 px),
    finish them. -> (list of (shade, mask), crop origin)."""
    raw = []
    box = None
    for i in range(n):
        base = os.path.join(d, "%s_%d_" % (prefix, i))
        sh, mk, pt = (Img.load(base + p + ".png") for p in ("shade", "mask", "pat"))
        raw.append((sh, mk, pt))
        b = alpha_box(sh)
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                         max(box[2], b[2]), max(box[3], b[3]))
    if box is None:
        box = (0, 0, 0, 0)
    x0, y0 = box[0] - 1, box[1] - 1
    w, h = box[2] - box[0] + 3, box[3] - box[1] + 3
    frames = []
    for sh, mk, pt in raw:
        frames.append(finish_frame(sh.crop(x0, y0, w, h), mk.crop(x0, y0, w, h),
                                   pt.crop(x0, y0, w, h), oc))
    return frames, (x0, y0)


def main():
    args = sys.argv[1:]
    frames_dir = os.path.join(HERE, "_frames")
    out_dir = os.path.join(ROOT, "assets", "sprites")
    contact = None
    c_units = c_pals = None
    i = 0
    while i < len(args):
        if args[i] == "--frames":
            frames_dir = os.path.abspath(args[i + 1]); i += 1
        elif args[i] == "--out":
            out_dir = os.path.abspath(args[i + 1]); i += 1
        elif args[i] == "--contact":
            contact = os.path.abspath(args[i + 1]); i += 1
        elif args[i] == "--contact-units":
            c_units = args[i + 1].split(","); i += 1
        elif args[i] == "--contact-palettes":
            c_pals = args[i + 1].split(","); i += 1
        i += 1
    os.makedirs(out_dir, exist_ok=True)
    old_ignore = os.path.join(out_dir, ".gdignore")
    if os.path.exists(old_ignore):
        os.remove(old_ignore)   # step 1b: the game imports the atlas
    for fn in os.listdir(out_dir):
        # step 1a's per-unit sheets and iso sheets no longer live here
        if fn.endswith(".png") and not fn.startswith("atlas_"):
            os.remove(os.path.join(out_dir, fn))
            imp = os.path.join(out_dir, fn + ".import")
            if os.path.exists(imp):
                os.remove(imp)
    iso_dir = os.path.join(HERE, "iso")
    os.makedirs(iso_dir, exist_ok=True)
    open(os.path.join(iso_dir, ".gdignore"), "w").close()
    oc = tuple(int(round(c * 255)) for c in SPEC["outline"])
    ppm = SPEC["px_per_m"]
    atl = SPEC["atlas"]
    man = {
        "version": 2,
        "px_per_m": ppm,
        "m_per_px": round(1.0 / ppm, 6),
        "doc": "Frames: [x, y, w, h] px in the atlas; anchor: px from a frame's top-left to the unit's origin (the man's feet; top view: x forward = image right, the man's left = image up). Top view sprites face +x (right); rotate by facing. Mask: R primary, G secondary, B accent, A = 255 - 128 * check pattern. Recolour: see tools/sprites/pack.py. atlas.table: per sprite set (1 = sets[0]) per action (idle, walk, attack, death, sidestep, backstep) two vec4: (x0, y0, w, h) of frame 0 and (anchor x, anchor y, step, frames); frame k is at x0 + k * step.",
        "outline": SPEC["outline"],
        "palettes": SPEC["palettes"],
        "units": {},
    }
    strips = []   # (uid, act, frames, anchor)
    props = atl.get("props", [])
    for uid in atl["sets"] + props:
        u = SPEC["units"][uid]
        d = os.path.join(frames_dir, uid)
        if not os.path.isdir(d):
            sys.exit("not rendered: " + uid + " (run build.py)")
        info = json.load(open(os.path.join(d, "info.json")))
        for act, a in SPEC["actions"].items():
            if not _has(act, uid):
                continue
            frames, (x0, y0) = load_action(d, act, a["frames"], oc)
            strips.append((uid, act, frames, (info["anchor"][0] - x0, info["anchor"][1] - y0)))
    placed, size = pack_atlas(strips, out_dir, atl["align"], atl["gutter"], oc)
    table = []
    for uid in atl["sets"]:
        acts = {}
        for act, a in SPEC["actions"].items():
            p = placed[(uid, act if _has(act, uid) else "walk")]   # no own frames: the walk
            acts[act] = {"frames": p["rects"], "anchor": p["anchor"], "fps": a["fps"], "loop": a["loop"]}
            r0 = p["rects"][0]
            table.append([r0[0], r0[1], r0[2], r0[3]])
            table.append([p["anchor"][0], p["anchor"][1], p["step"], len(p["rects"])])
        man["units"][uid] = {"name": SPEC["units"][uid]["name"], "view": "top",
                             "set": atl["sets"].index(uid) + 1,
                             "shade": "atlas_shade.png", "mask": "atlas_mask.png",
                             "sheet_size": size, "actions": acts}
    # Props (step 1d): drawn by the overlay straight from the shade sheet
    # (no team parts), not in the shaders' table.
    prop_tab = {}
    for uid in props:
        acts = {}
        rows = []
        for act, a in SPEC["actions"].items():
            p = placed[(uid, act if _has(act, uid) else "walk")]
            acts[act] = {"frames": p["rects"], "anchor": p["anchor"], "fps": a["fps"], "loop": a["loop"]}
            r0 = p["rects"][0]
            rows.append([r0[0], r0[1], r0[2], r0[3]])
            rows.append([p["anchor"][0], p["anchor"][1], p["step"], len(p["rects"])])
        prop_tab[uid] = rows
        man["units"][uid] = {"name": SPEC["units"][uid]["name"], "view": "top", "set": 0, "prop": 1,
                             "shade": "atlas_shade.png", "mask": "atlas_mask.png",
                             "sheet_size": size, "actions": acts}
    man["atlas"] = {"shade": "atlas_shade.png", "mask": "atlas_mask.png", "size": size,
                    "sets": atl["sets"], "props": props, "actions": list(SPEC["actions"].keys()),
                    "fps": [a["fps"] for a in SPEC["actions"].values()],
                    "palettes": list(SPEC["palettes"].keys()), "table": table, "prop_table": prop_tab}
    assert len(atl["sets"]) <= 63, "sprite sets are a 6-bit field (soldiers.gdshaderinc)"
    assert len(SPEC["palettes"]) <= 16, "palettes are a 4-bit field (soldiers.gdshaderinc)"
    print("atlas %dx%d: %d sets + %d props x %d actions" % (size[0], size[1], len(atl["sets"]), len(props), len(SPEC["actions"])))
    write_game_tables(man["atlas"], SPEC["palettes"])
    iso = SPEC.get("iso")
    if iso:
        d = os.path.join(frames_dir, "iso_" + iso["unit"])
        if os.path.isdir(d):
            info = json.load(open(os.path.join(d, "info.json")))
            n = SPEC["actions"][iso["action"]]["frames"]
            # one shared crop for all directions: load each, union the boxes
            allf = []
            box = None
            for k in range(iso["directions"]):
                for j in range(n):
                    b = alpha_box(Img.load(os.path.join(d, "d%d_%d_shade.png" % (k, j))))
                    if b:
                        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                                     max(box[2], b[2]), max(box[3], b[3]))
            x0, y0 = box[0] - 1, box[1] - 1
            w, h = box[2] - box[0] + 3, box[3] - box[1] + 3
            rows = []
            for k in range(iso["directions"]):
                frames = []
                for j in range(n):
                    base = os.path.join(d, "d%d_%d_" % (k, j))
                    sh, mk, pt = (Img.load(base + p + ".png").crop(x0, y0, w, h)
                                  for p in ("shade", "mask", "pat"))
                    frames.append(finish_frame(sh, mk, pt, oc))
                rows.append(("d%d" % k, frames, (info["anchor"][0] - x0, info["anchor"][1] - y0)))
            name = "iso_" + iso["unit"]
            entries, size = pack_rows(rows, iso_dir, name)
            fps = SPEC["actions"][iso["action"]]["fps"]
            for e in entries.values():
                e.update({"fps": fps, "loop": 1})
            man["iso"] = {"unit": iso["unit"], "view": "iso",
                          "elevation_deg": iso["elevation_deg"], "action": iso["action"],
                          "dir_doc": info["dir_doc"],
                          "shade": "res://tools/sprites/iso/" + name + "_shade.png",
                          "mask": "res://tools/sprites/iso/" + name + "_mask.png",
                          "sheet_size": size, "directions": entries}
            print("packed %s: sheet %dx%d" % (name, size[0], size[1]))
    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    total = sum(os.path.getsize(os.path.join(out_dir, f)) for f in os.listdir(out_dir) if not f.endswith(".import"))
    print("assets/sprites total: %.1f KB" % (total / 1024.0))
    if contact:
        write_contact(man, out_dir, contact, only_units=c_units, only_pals=c_pals)


# ---------------------------------------------------------------- game tables

def _f(v):
    return ("%.4f" % v).rstrip("0").rstrip(".") + ("" if "." in ("%.4f" % v).rstrip("0").rstrip(".") else ".0")


def write_game_tables(atlas, palettes):
    """game/sprite_atlas.gd (constants for soldier_layer.gd: the frame table
    for the texture path's uniform array, the palettes) and
    game/sprite_frames.gdshaderinc (the same table as constants for the
    CPU-fed path, which may not index a uniform array in the vertex stage).
    Generated: edit spec.json and re-run pack.py."""
    tab = atlas["table"]
    W, H = atlas["size"]
    g = ["extends RefCounted",
         "## GENERATED by tools/sprites/pack.py from tools/sprites/spec.json: do not edit.",
         "## The soldier atlas (assets/sprites/atlas_*.png): per sprite set s (1..%d) and" % len(atlas["sets"]),
         "## action a (0 idle, 1 walk, 2 attack, 3 death, 4 sidestep, 5 backstep; sets without them repeat the walk)",
         "## two entries at ((s - 1) * %d + a) * 2:" % len(atlas["fps"]),
         "## (x0, y0, w, h) of frame 0 in px, (anchor x, anchor y, step, frames);",
         "## frame k is at x0 + k * step. Palettes in campaign/cdata.gd FACTIONS order.",
         "",
         "const SIZE := Vector2i(%d, %d)" % (W, H),
         "const SETS: Array[String] = [%s]" % ", ".join('"%s"' % k for k in atlas["sets"]),
         "const FPS: Array[int] = [%s]" % ", ".join(str(v) for v in atlas["fps"]),
         "const TABLE: Array[Vector4] = ["]
    for r in tab:
        g.append("\tVector4(%s)," % ", ".join(_f(v) for v in r))
    g.append("]")
    g.append("## Props (game/overlay.gd draws them from the shade sheet): per action the same")
    g.append("## two entries as TABLE, actions in order.")
    g.append("const PROPS: Dictionary = {")
    for k, rows in atlas.get("prop_table", {}).items():
        g.append("\t\"%s\": [%s]," % (k, ", ".join("Vector4(%s)" % ", ".join(_f(v) for v in r) for r in rows)))
    g.append("}")
    g.append("const PALETTE_KEYS: Array[String] = [%s]" % ", ".join('"%s"' % k for k in atlas["palettes"]))
    g.append("## Per palette: primary, secondary, accent, pattern colour (sRGB), pattern_k.")
    g.append("const PALETTES: Array = [")
    for k in atlas["palettes"]:
        p = palettes[k]
        cols = ", ".join("Color(%s)" % ", ".join(_f(c) for c in p[n]) for n in ("primary", "secondary", "accent", "pattern"))
        g.append("\t[%s, %d],  # %s" % (cols, p["pattern_k"], p["name"]))
    g.append("]")
    open(os.path.join(ROOT, "game", "sprite_atlas.gd"), "w").write("\n".join(g) + "\n")
    n = len(tab)
    h = ["// GENERATED by tools/sprites/pack.py from tools/sprites/spec.json: do not edit.",
         "// The soldier atlas frame table (see game/sprite_atlas.gd): entry k =",
         "// ((set - 1) * %d + action) * 2 + j; j 0: (x0, y0, w, h), 1: (anchor x," % len(atlas["fps"]),
         "// anchor y, step, frames). The texture path reads it from a uniform array",
         "// (soldier_layer.gd fills frame_tab from sprite_atlas.gd TABLE), the",
         "// CPU-fed path from these constants: the same numbers.",
         "const vec2 ATLAS_SIZE = vec2(%s, %s);" % (_f(W), _f(H)),
         "const int ATLAS_ENTRIES = %d;" % n,
         "const int ACTIONS = %d;" % len(atlas["fps"]),
         "",
         "float action_fps(int a) {"]
    for a, fps in enumerate(atlas["fps"][:-1]):
        h.append("\tif (a == %d) { return %s; }" % (a, _f(fps)))
    h.append("\treturn %s;" % _f(atlas["fps"][-1]))
    h.append("}")
    h.append("")
    h.append("#ifdef CPU_FED")
    h.append("vec4 frame_entry(int k) {")
    # a two-level if chain (by set, then entry): at most ~12 compares
    per = 2 * len(atlas["fps"])
    nsets = n // per
    for si in range(nsets):
        h.append("\tif (k < %d) {" % ((si + 1) * per))
        for j in range(per):
            k = si * per + j
            vals = ", ".join(_f(v) for v in tab[k])
            if j < per - 1:
                h.append("\t\tif (k == %d) { return vec4(%s); }" % (k, vals))
            else:
                h.append("\t\treturn vec4(%s);" % vals)
        h.append("\t}")
    h.append("\treturn vec4(0.0);")
    h.append("}")
    h.append("#else")
    h.append("uniform vec4 frame_tab[%d];" % n)
    h.append("")
    h.append("vec4 frame_entry(int k) {")
    h.append("\treturn frame_tab[k];")
    h.append("}")
    h.append("#endif")
    open(os.path.join(ROOT, "game", "sprite_frames.gdshaderinc"), "w").write("\n".join(h) + "\n")
    print("wrote game/sprite_atlas.gd, game/sprite_frames.gdshaderinc")


# ---------------------------------------------------------------- contact

def recolor(s, m, pal):
    r, g, b, a = s
    if a == 0:
        return None
    mr, mg, mb, ma = (v / 255.0 for v in m)
    pat = (1.0 - ma) * 2.0 * pal["pattern_k"]
    prim = [pal["primary"][k] * (1 - pat) + pal["pattern"][k] * pat for k in range(3)]
    rest = max(0.0, 1.0 - mr - mg - mb)
    out = []
    for k, v in enumerate((r, g, b)):
        t = rest + mr * prim[k] + mg * pal["secondary"][k] + mb * pal["accent"][k]
        out.append(max(0, min(255, int(v * t))))
    return out


def _file(out_dir, f):
    return os.path.join(ROOT, f[6:]) if f.startswith("res://") else os.path.join(out_dir, f)


def write_contact(man, out_dir, path, scale=3, only_units=None, only_pals=None):
    grass = (96, 132, 66)
    tiles = []  # (img, x, y)
    rows = []
    for uid, u in man["units"].items():
        if only_units and uid not in only_units:
            continue
        sh = Img.load(_file(out_dir, u["shade"]))
        mk = Img.load(_file(out_dir, u["mask"]))
        row = []
        for pk, pal in man["palettes"].items():
            if only_pals and pk not in only_pals:
                continue
            for act in ("idle", "walk", "attack", "death"):
                fr = u["actions"][act]["frames"]
                f = fr[len(fr) // 2] if act != "death" else fr[-1]
                row.append((sh, mk, f, pal))
        rows.append(row)
    if "iso" in man and not only_units:
        u = man["iso"]
        sh = Img.load(_file(out_dir, u["shade"]))
        mk = Img.load(_file(out_dir, u["mask"]))
        row = []
        for k in range(len(u["directions"])):
            row.append((sh, mk, u["directions"]["d%d" % k]["frames"][1], man["palettes"]["rome"]))
        rows.append(row)
    pad = 6
    W = max(sum(f[2] + pad for _s, _m, f, _p in row) for row in rows) + pad
    H = sum(max(f[3] for _s, _m, f, _p in row) + pad for row in rows) + pad
    img = Img(W * scale, H * scale, fill=grass + (255,))
    y = pad
    for row in rows:
        x = pad
        for sh, mk, f, pal in row:
            fx, fy, fw, fh = f
            for yy in range(fh):
                for xx in range(fw):
                    c = recolor(sh.get(fx + xx, fy + yy), mk.get(fx + xx, fy + yy), pal)
                    if c is None:
                        continue
                    for dy in range(scale):
                        for dx in range(scale):
                            img.put((x + xx) * scale + dx, (y + yy) * scale + dy, c + [255])
            x += fw + pad
        y += max(f[3] for _s, _m, f, _p in row) + pad
    img.save(path)
    print("contact sheet:", path)


if __name__ == "__main__":
    main()
