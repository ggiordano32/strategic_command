extends RefCounted
## The oblique view's kit sheet (tabletop pass 3; the contract with the art pass): assets/kit_ob/atlas.png (plus
## atlas_nrm.png when the kit's lighting pass is rendered too) and manifest.json with the battle kit's piece keys, each
## piece rendered once at 40 degrees: per piece its rect in the atlas ([x, y, w, h] px, "rect" or "frame"), its anchor
## at the footprint's centre on the ground ([ax, ay] px from the rect's top left) and its ground footprint in metres
## ("foot": [w, d]); "px_per_m" (24) and "elevation_deg" (40) at the top. Pieces the sheet lacks keep the stand-in
## (the top-down piece stood up). Until the sheet exists, `ok()` is false and the kit draws the stand-in. View only.

const Atlas := preload("res://game/battlekit_atlas.gd")
const DIR := "res://assets/kit_ob/"

static var _done := false
static var _ok := false
static var tex: Texture2D
static var nrm: Texture2D
static var ppm := 24.0
static var rects := PackedVector4Array()    # per battle kit piece: uv rect in the atlas (0: not in the sheet)
static var anch := PackedVector4Array()     # per piece: size px, anchor px


static func ok() -> bool:
	if not _done:
		_done = true
		_ok = _load()
	return _ok


## The sheet's folder: assets/kit_ob, or --kit-ob-dir=PATH (a testing aid: a folder of the same layout).
static func _dir() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--kit-ob-dir="):
			return str(a).get_slice("=", 1).trim_suffix("/") + "/"
	return DIR


static func _load() -> bool:
	var dir := _dir()
	if not FileAccess.file_exists(dir + "manifest.json"):
		return false
	var man = JSON.parse_string(FileAccess.get_file_as_string(dir + "manifest.json"))
	if not (man is Dictionary):
		return false
	tex = _tex(dir + "atlas.png")
	if tex == null:
		tex = _tex(dir + "atlas_albedo.png")
	if tex == null:
		push_warning("oblique view: assets/kit_ob/manifest.json without its atlas; the stand-in kit")
		return false
	nrm = _tex(dir + "atlas_nrm.png")
	ppm = float((man as Dictionary).get("px_per_m", 24.0))
	var pieces: Dictionary = (man as Dictionary).get("pieces", man)
	rects.resize(64)
	rects.fill(Vector4.ZERO)
	anch.resize(64)
	anch.fill(Vector4.ZERO)
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var any := false
	for p in Atlas.NAMES.size():
		var key: String = Atlas.NAMES[p]
		if p >= 64 or not pieces.has(key) or not (pieces[key] is Dictionary):
			continue
		var d: Dictionary = pieces[key]
		var r = d.get("rect", d.get("frame", []))
		var a = d.get("anchor", [])
		if not (r is Array) or (r as Array).size() < 4 or not (a is Array) or (a as Array).size() < 2:
			continue
		rects[p] = Vector4(float(r[0]) / tw, float(r[1]) / th, float(r[2]) / tw, float(r[3]) / th)
		anch[p] = Vector4(float(r[2]), float(r[3]), float(a[0]), float(a[1]))
		any = true
	return any


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The kit material's oblique-kit uniforms (battlekit.gdshader): the sheet's texture, rects and anchors when present.
static func apply(mat: ShaderMaterial) -> void:
	if not ok():
		mat.set_shader_parameter("ob_kit", 0.0)
		return
	mat.set_shader_parameter("ob_kit", 1.0)
	mat.set_shader_parameter("ob_ktex", tex)
	mat.set_shader_parameter("ob_krect", rects)
	mat.set_shader_parameter("ob_kanch", anch)
	mat.set_shader_parameter("ob_kk", float(mat.get_shader_parameter("ob_ppm")) / ppm if mat.get_shader_parameter("ob_ppm") != null else 10.0 / ppm)
