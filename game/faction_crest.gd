extends Control
## A faction's painted crest (assets/ui/crests/<pack>/<key>.png 256 px, <key>_64.png 64 px; tools/menu_art/crests.py
## makes them from the drawn marks through FLUX.2 Klein 4B). Kit.faction_mark returns one when the [menu] emblems
## setting is painted and the files exist, else the drawn mark (game/faction_emblem.gd) or the colour swatch.
## View only. At 64 px and below the small file is drawn.

const MenuPrefs := preload("res://game/menu/menu_prefs.gd")
const DIR := "res://assets/ui/crests/"
const SMALL_PX := 64.0

static var _tex := {}   # path -> Texture2D or null (missing)

var key := ""
var pack := "rome"
var small := false


## The crest of faction `key` in `pack` at the size the control will have (px), null when the file is missing.
static func texture(p_pack: String, p_key: String, px: float) -> Texture2D:
	var path := DIR + p_pack + "/" + p_key + ("_64" if px <= SMALL_PX else "") + ".png"
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)   # (not imported yet: still readable from the project folder)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_tex[path] = t
	return t


static func has(p_pack: String, p_key: String) -> bool:
	return texture(p_pack, p_key, 256.0) != null and texture(p_pack, p_key, SMALL_PX) != null


## True when the painted style is on and the crest exists.
static func wanted(p_pack: String, p_key: String) -> bool:
	return MenuPrefs.emblems_pref() == "painted" and has(p_pack, p_key)


static func mark(p_pack: String, p_key: String, px: float) -> Control:
	var m = (load("res://game/faction_crest.gd") as GDScript).new()
	m.pack = p_pack
	m.key = p_key
	m.small = px <= SMALL_PX
	m.custom_minimum_size = Vector2(px, px)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


func _draw() -> void:
	var side := minf(size.x, size.y)
	var t := texture(pack, key, SMALL_PX if small else 256.0)
	if t == null:
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	draw_texture_rect(t, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), false)
