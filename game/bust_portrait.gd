extends RefCounted
## The painted busts of the Hunyuan characters (assets/portraits/NAME.png, 256 px, transparent background) as story
## portraits: StoryPortrait's frame in the character's colour with the bust fitted inside, the same outer square as
## StoryPortrait.make_control so the layouts do not move. View only. `BUSTS` maps a story CHARS key to its bust;
## `crop` (a fraction rect of the PNG) is for a bust that reads too small at 36 px (none needed so far).

const StoryPortrait := preload("res://game/story_portrait.gd")

const BUSTS := {
	"captain": {"png": "res://assets/portraits/captain.png", "crop": Rect2(0.0, 0.0, 1.0, 1.0)},
	"partner": {"png": "res://assets/portraits/rook.png", "crop": Rect2(0.0, 0.0, 1.0, 1.0)},
	"mercy": {"png": "res://assets/portraits/mercy.png", "crop": Rect2(0.0, 0.0, 1.0, 1.0)},
}

static var _tex := {}   # key -> Texture2D, loaded once


static func has(key: String) -> bool:
	return BUSTS.has(key)


static func texture(key: String) -> Texture2D:
	if not _tex.has(key):
		_tex[key] = load(str(BUSTS[key]["png"])) as Texture2D if BUSTS.has(key) else null
	return _tex[key]


static func make_control(key: String, size: float) -> Control:
	var m := Bust.new()
	m.key = key
	m.custom_minimum_size = Vector2(size, size)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


class Bust extends Control:
	var key := ""
	func _draw() -> void:
		var side := minf(size.x, size.y)
		var r := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		StoryPortrait.draw_frame(self, key, r)
		var tex := (load("res://game/bust_portrait.gd") as Script).call("texture", key) as Texture2D
		if tex == null:
			return
		var cr: Rect2 = BUSTS[key]["crop"]
		var src := Rect2(cr.position * tex.get_size(), cr.size * tex.get_size())
		var inner := r.grow(-side * 0.04)   # inside the frame's ink line
		var k := minf(inner.size.x / src.size.x, inner.size.y / src.size.y)
		var dst := Rect2(Vector2.ZERO, src.size * k)
		dst.position = Vector2(inner.get_center().x - dst.size.x * 0.5, inner.end.y - dst.size.y)
		draw_texture_rect_region(tex, dst, src)
