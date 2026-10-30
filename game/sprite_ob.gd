extends RefCounted
## The oblique view's figure sheets (tabletop pass 3, docs/design/art_pipeline.md "Pass 3, the oblique view"): the
## soldier layer's upright figures read their frames from here. View only.
##
## Source, the first that loads:
##  1. assets/sprites_ob (the contract with the art pass): atlas_shade.png, atlas_mask.png, manifest.json with the
##     top-down sheets' unit keys, actions, fps, loop and palettes; per action "frames": {"S": [[x, y, w, h], ...],
##     "SW": ..., "W", "NW", "N", "NE", "E", "SE"} (S faces the camera, which looks north from the south; clockwise),
##     "anchor" at the figure's feet ([ax, ay], or per direction {"S": [ax, ay], ...}), "elevation_deg": 40,
##     "px_per_m": 24 on the ground plane; "mirror": true when only S, SW, W, NW, N are rendered (E, NE, SE are W, NW,
##     SW flipped).
##  2. the stand-in: tools/sprites/iso's iso_heavy_swords sheet (32 degrees, 8 directions, the walk only; d0 faces
##     east, counter-clockwise) for every set but the engines, loaded from the file (it is not imported: desktop runs
##     from the project only). Idle is its first walk frame, attack and the steps its walk; no death (a dead man is
##     drawn flat, the top-down death frame on the ground).
##  3. none: every figure flat (the top-down sprite squashed onto the board).
## A warning is printed once when the real sheets are missing.
##
## The table (`tab`, RGBA float, filter nearest; read in the fragment stage): row = sprite set (SpriteAtlas.SETS index
## + 1), per (action a, direction d, frame f) two texels at column ((a * 8 + d) * max_frames + f) * 2: (x0, y0, w, h) in the
## sheet, (anchor x, anchor y, mirrored, 0). `cells[set]` (a uniform array, read in the vertex stage): the set's
## quad round the feet in sheet px (half width, above, below) and its frame counts per action, 4 bits each
## (idle + 16 walk + 256 attack + 4096 death + 65536 sidestep + 1048576 backstep; 0 = draw that action flat).

const SpriteAtlas := preload("res://game/sprite_atlas.gd")
const OB_DIR := "res://assets/sprites_ob/"
const STANDIN_MANIFEST := "res://assets/sprites/manifest.json"
const DIRS: Array[String] = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
const ACTIONS: Array[String] = ["idle", "walk", "attack", "death", "sidestep", "backstep"]
const ENGINES: Array[String] = ["bolt_thrower", "stone_thrower", "scorpion", "cannon", "mortar", "naval_gun"]
const SETS := 64

static var _done := false
static var source := ""            # "sprites_ob", "standin" or "" (flat)
static var shade: Texture2D
static var mask: Texture2D
static var tab: ImageTexture
static var cells := PackedVector4Array()
static var max_frames := 8
static var ppm := 24.0
static var elevation := 40.0
static var sheet := Vector2(1.0, 1.0)


## Loads the sheets once per session; true when upright figures are available.
static func ensure() -> bool:
	if _done:
		return source != ""
	_done = true
	cells.resize(SETS)
	cells.fill(Vector4.ZERO)
	if _load_ob():
		source = "sprites_ob"
	elif _load_standin():
		source = "standin"
		print("oblique view: no assets/sprites_ob: the stand-in figures (tools/sprites/iso)")
	else:
		print("oblique view: no assets/sprites_ob (the web export leaves it out): the figures are drawn flat")
	return source != ""


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var gp := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(gp):
		return null
	var img := Image.load_from_file(gp)
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## entries[set][action][dir] = {"frames": [[x, y, w, h], ...], "anchor": Vector2, "flip": bool}
static func _build(entries: Dictionary) -> void:
	max_frames = 1
	for s in entries:
		for a in entries[s]:
			for d in entries[s][a]:
				max_frames = maxi(max_frames, (entries[s][a][d]["frames"] as Array).size())
	max_frames = mini(max_frames, 15)
	var w := ACTIONS.size() * 8 * max_frames * 2
	var img := Image.create(w, SETS, false, Image.FORMAT_RGBAF)
	for s in entries:
		var hw := 0.0
		var top := 0.0
		var bot := 0.0
		var packed := 0
		for a in entries[s]:
			var nmin := 99
			for d in entries[s][a]:
				var e: Dictionary = entries[s][a][d]
				var fr: Array = e["frames"]
				var an: Vector2 = e["anchor"]
				nmin = mini(nmin, mini(fr.size(), max_frames))
				for f in mini(fr.size(), max_frames):
					var r: Array = fr[f]
					var col := ((int(a) * 8 + int(d)) * max_frames + f) * 2
					img.set_pixel(col, int(s), Color(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
					img.set_pixel(col + 1, int(s), Color(an.x, an.y, 1.0 if bool(e["flip"]) else 0.0, 0.0))
					hw = maxf(hw, maxf(an.x, float(r[2]) - an.x))
					top = maxf(top, an.y)
					bot = maxf(bot, float(r[3]) - an.y)
			if (entries[s][a] as Dictionary).size() == 8 and nmin > 0 and nmin < 99:
				packed += nmin * [1, 16, 256, 4096, 65536, 1048576][int(a)]
		cells[int(s)] = Vector4(ceilf(hw) + 1.0, ceilf(top) + 1.0, ceilf(bot) + 1.0, float(packed))
	tab = ImageTexture.create_from_image(img)


## The sheets' folder: assets/sprites_ob, or --sprites-ob-dir=PATH (a testing aid: a folder of the same layout).
static func _dir() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--sprites-ob-dir="):
			return str(a).get_slice("=", 1).trim_suffix("/") + "/"
	return OB_DIR


static func _load_ob() -> bool:
	var dir := _dir()
	var man := _json(dir + "manifest.json")
	if man.is_empty():
		return false
	var at: Dictionary = man.get("atlas", {})
	shade = _tex(dir + str(at.get("shade", "atlas_shade.png")))
	mask = _tex(dir + str(at.get("mask", "atlas_mask.png")))
	if shade == null or mask == null:
		return false
	sheet = Vector2(shade.get_width(), shade.get_height())
	ppm = float(man.get("px_per_m", 24.0))
	elevation = float(man.get("elevation_deg", 40.0))
	if absf(elevation - 40.0) > 0.5:
		push_warning("oblique view: assets/sprites_ob is rendered at %.1f degrees, the board at 40" % elevation)
	var mirror := bool(man.get("mirror", false))
	var units: Dictionary = man.get("units", {})
	var entries := {}
	for si in SpriteAtlas.SETS.size():
		var key: String = SpriteAtlas.SETS[si]
		if not units.has(key):
			continue
		var acts: Dictionary = (units[key] as Dictionary).get("actions", {})
		var per_a := {}
		for a in ACTIONS.size():
			var ad: Dictionary = acts.get(ACTIONS[a], {})
			var frames = ad.get("frames", {})
			if not (frames is Dictionary):
				continue
			var per_d := {}
			for d in 8:
				var dn: String = DIRS[d]
				var src := dn
				# A mirrored sheet lists SE, E, NE with the SW, W, NW frames, to be drawn flipped about the anchor.
				var flip := mirror and dn in ["SE", "E", "NE"]
				if not (frames as Dictionary).has(dn):
					# Mirrored sheets ("mirror": true): E, NE, SE are W, NW, SW flipped.
					var m := {"E": "W", "NE": "NW", "SE": "SW"}
					if m.has(dn) and (frames as Dictionary).has(m[dn]):
						src = m[dn]
						flip = true
					else:
						continue
				var anc = ad.get("anchor", [0.0, 0.0])
				if anc is Dictionary:
					anc = (anc as Dictionary).get(src, [0.0, 0.0])
				per_d[d] = {"frames": frames[src], "anchor": Vector2(float(anc[0]), float(anc[1])), "flip": flip}
			if not per_d.is_empty():
				per_a[a] = per_d
		if not per_a.is_empty():
			entries[si + 1] = per_a
	if entries.is_empty():
		return false
	_build(entries)
	return true


static func _load_standin() -> bool:
	var man := _json(STANDIN_MANIFEST)
	var iso: Dictionary = man.get("iso", {})
	if iso.is_empty():
		return false
	shade = _tex(str(iso["shade"]))
	mask = _tex(str(iso["mask"]))
	if shade == null or mask == null:
		return false
	sheet = Vector2(shade.get_width(), shade.get_height())
	ppm = float(man.get("px_per_m", 24.0))
	elevation = float(iso.get("elevation_deg", 32.0))
	var dirs: Dictionary = iso["directions"]
	# Contract direction d (0 S, clockwise) <- the iso sheet's (d0 east, counter-clockwise): (6 - d) mod 8.
	var walk := {}
	var idle := {}
	for d in 8:
		var e: Dictionary = dirs["d%d" % posmod(6 - d, 8)]
		var an: Array = e["anchor"]
		walk[d] = {"frames": e["frames"], "anchor": Vector2(float(an[0]), float(an[1])), "flip": false}
		idle[d] = {"frames": [e["frames"][0]], "anchor": Vector2(float(an[0]), float(an[1])), "flip": false}
	var entries := {}
	for si in SpriteAtlas.SETS.size():
		if SpriteAtlas.SETS[si] in ENGINES:
			continue
		entries[si + 1] = {0: idle, 1: walk, 2: walk, 4: walk, 5: walk}
	_build(entries)
	return true
