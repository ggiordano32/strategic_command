extends RefCounted
## The oblique view's kit sheet (tabletop pass 3; docs/design/art_pipeline.md "Pass 3, the oblique sheets"):
## assets/battlekit_ob, the battle's own kit (tools/battlekit) rendered at 40 degrees elevation, 8 px/m, true heights:
## per piece `<piece>__y0` (as the top-down kit: its outer face +y, away from the camera) and `<piece>__y4` (turned 180
## degrees: the flip the kit's hash uses), each with its rect in atlas_albedo / atlas_nrm (the top-down passes'
## channels: the world normal, height / 20 m, the mask class; halved in atlas_low, pre-lit at 4 px/m) and its anchor at
## the footprint's centre on the ground. Every piece the battle uses is in it (the 62 block 1 pieces, walls to trees and
## rocks, and the 32 landmark and civic pieces of block 2), so the structures kit (assets/kit_ob, the overworld's minis
## at 40 degrees) is not needed here. Missing (the web export leaves the folder out): `ok()` is false and the kit draws
## the stand-in (the top-down piece stood up). View only.

const Atlas := preload("res://game/battlekit_atlas.gd")
const DIR := "res://assets/battlekit_ob/"
const BASE := 100            # a MultiMesh row's piece code: BASE + the sprite's index (battlekit.gdshader)
const MAX := 192             # sprites the shader's tables hold

static var _done := false
static var _ok := false
static var alb: Texture2D
static var nrm: Texture2D
static var low: Texture2D
static var ppm := 8.0
static var rects := PackedVector4Array()    # per sprite: uv rect in the atlas
static var anch := PackedVector4Array()     # per sprite: size px, anchor px
static var _idx := {}                       # "<piece>__y0" / "__y4" -> sprite index
static var _px := []                        # per sprite: [x, y, w, h, ax, ay] px (the Low path)


## Forgets a failed decision so the next `ok` looks again (game/oblique_pack.gd mounted the pack).
static func reset() -> void:
	if not _ok:
		_done = false


static func ok() -> bool:
	if not _done:
		_done = true
		_ok = _load()
		if not _ok:
			print("oblique view: no assets/battlekit_ob (the web export leaves it out): the stand-in kit")
	return _ok


## The folder: assets/battlekit_ob, or --kit-ob-dir=PATH (a testing aid: a folder of the same layout).
static func _dir() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--kit-ob-dir="):
			return str(a).get_slice("=", 1).trim_suffix("/") + "/"
	return DIR


static func _load() -> bool:
	var dir := _dir()
	if not ResourceLoader.exists(dir + "atlas_albedo.png") and not FileAccess.file_exists(dir + "atlas_albedo.png"):
		return false
	if not FileAccess.file_exists(dir + "manifest.json"):
		return false
	var man = JSON.parse_string(FileAccess.get_file_as_string(dir + "manifest.json"))
	if not (man is Dictionary):
		return false
	alb = _tex(dir + str((man as Dictionary).get("albedo", "atlas_albedo.png")))
	nrm = _tex(dir + str((man as Dictionary).get("nrm", "atlas_nrm.png")))
	low = _tex(dir + str((man as Dictionary).get("low", "atlas_low.png")))
	if alb == null or nrm == null:
		return false
	ppm = float((man as Dictionary).get("px_per_m", 8.0))
	var pieces: Dictionary = (man as Dictionary).get("pieces", {})
	rects.resize(MAX)
	rects.fill(Vector4.ZERO)
	anch.resize(MAX)
	anch.fill(Vector4.ZERO)
	_idx.clear()
	_px.clear()
	var tw := float(alb.get_width())
	var th := float(alb.get_height())
	var keys := pieces.keys()
	keys.sort()
	for key in keys:
		if _px.size() >= MAX:
			push_warning("oblique view: battlekit_ob has more than %d sprites; the rest are stand-ins" % MAX)
			break
		var d: Dictionary = pieces[key]
		var r: Array = d.get("rect", [])
		var a: Array = d.get("anchor", [])
		if r.size() < 4 or a.size() < 2:
			continue
		var q := _px.size()
		rects[q] = Vector4(float(r[0]) / tw, float(r[1]) / th, float(r[2]) / tw, float(r[3]) / th)
		anch[q] = Vector4(float(r[2]), float(r[3]), float(a[0]), float(a[1]))
		_px.append([float(r[0]), float(r[1]), float(r[2]), float(r[3]), float(a[0]), float(a[1])])
		_idx[str(key)] = q
	return not _idx.is_empty()


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## The sprite of piece `name` seen from the south (`toward`: its outer face turned to the camera, the y4 render), or -1.
static func index(name: String, toward: bool) -> int:
	if not ok():
		return -1
	var k := name + ("__y4" if toward else "__y0")
	if _idx.has(k):
		return int(_idx[k])
	return int(_idx.get(name + "__y0", -1))


## [x, y, w, h, anchor x, anchor y] px of sprite q in the full-size atlas.
static func px(q: int) -> Array:
	return _px[q]


## The kit material's uniforms (battlekit.gdshader ob_k*): the sheet's passes, rects and anchors, its scale.
static func apply(mat: ShaderMaterial, board_ppm: float) -> void:
	if not ok():
		mat.set_shader_parameter("ob_kit", 0.0)
		return
	mat.set_shader_parameter("ob_kit", 1.0)
	mat.set_shader_parameter("ob_kalb", alb)
	mat.set_shader_parameter("ob_knrm", nrm)
	mat.set_shader_parameter("ob_krect", rects)
	mat.set_shader_parameter("ob_kanch", anch)
	mat.set_shader_parameter("ob_kk", board_ppm / ppm)
