extends RefCounted
## The battle kit's pieces as meshes for the 3D battle view (step two, 2026-11-06; docs/design/art_pipeline.md "The 3D battle
## view, step two: houses as geometry"; the owner: "The houses need more panels or to be switched to 3D models, they rotate
## with the camera and then snap into the next view"). assets/battlekit_ob/kit3d.res (one ArrayMesh, a surface per piece,
## tools/battlekit/export3d.py + kit3d_res.gd) and kit3d_albedo.png (the baked painted textures, one atlas). Lives beside the
## oblique kit sheet, so the web's oblique pack carries it. Missing, or `--no-kit3d` (a testing aid: step one's cards), `ok()`
## is false and the 3D view draws every piece as its card. View only.

const PATH := "res://assets/battlekit_ob/kit3d.res"
const TEX_PATH := "res://assets/battlekit_ob/kit3d_albedo.png"

static var _done := false
static var _ok := false
static var src: ArrayMesh
static var tex: Texture2D
static var _info := {}          # piece -> [surface, footprint centre x, y (m, piece frame, +y its outer side), height m, triangles]
static var _cache := {}         # piece -> its own one-surface ArrayMesh


## Forgets a failed decision so the next `ok` looks again (the web's oblique pack mounted later).
static func reset() -> void:
	if not _ok:
		_done = false


static func ok() -> bool:
	if not _done:
		_done = true
		_ok = _load()
	return _ok


static func _load() -> bool:
	if "--no-kit3d" in OS.get_cmdline_user_args():
		return false
	if not ResourceLoader.exists(PATH) or not ResourceLoader.exists(TEX_PATH):
		return false
	src = load(PATH) as ArrayMesh
	tex = load(TEX_PATH) as Texture2D
	if src == null or tex == null or not src.has_meta("pieces"):
		return false
	_info = src.get_meta("pieces")
	_cache.clear()
	return not _info.is_empty()


static func has(piece: String) -> bool:
	return ok() and _info.has(piece)


## The piece's mesh (a surface of the source, cut out once), or null.
static func mesh(piece: String) -> ArrayMesh:
	if not has(piece):
		return null
	if _cache.has(piece):
		return _cache[piece]
	var am := ArrayMesh.new()
	var s: int = int((_info[piece] as Array)[0])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
	am.surface_set_name(0, piece)
	_cache[piece] = am
	return am


## The footprint's centre in the piece's frame (m; x its right, y its outer side), where the oblique sheet anchors the piece.
static func centre(piece: String) -> Vector2:
	if not has(piece):
		return Vector2.ZERO
	var a: Array = _info[piece]
	return Vector2(float(a[1]), float(a[2]))


static func tris(piece: String) -> int:
	return int((_info[piece] as Array)[4]) if has(piece) else 0


static func pieces() -> Array:
	return _info.keys() if ok() else []
