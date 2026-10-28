extends RefCounted
## Vector UI icons baked once into small white textures (tabletop pass 1): `game/ui_icons.gd` strokes an icon from GDScript
## on every draw (about 200 microseconds), too dear for the counters the battle overlay draws every frame. The first
## request renders the icon in a one-shot SubViewport; until it is back (two frames) or where there is no renderer (headless)
## `get_tex` returns null and the caller draws its plain stand-in. Tinted by the draw call's modulate.

const UIIcons := preload("res://game/ui_icons.gd")
const PX := 48
static var _tex := {}
static var _pending := {}


class Ctl extends Control:
	var drawer := Callable()

	func _draw() -> void:
		drawer.call(self)


## The vector icon `icon` as a white PX x PX texture (null while it bakes).
static func get_tex(icon: String) -> Texture2D:
	return bake("icon:" + icon, Vector2i(PX, PX), func(ci: Control) -> void:
		UIIcons.draw_icon(ci, icon, Rect2(Vector2.ZERO, Vector2(PX, PX)), Color.WHITE))


## Anything drawn by `drawer(control)` into a px-sized texture, once per key (null while it bakes, and in headless runs).
static func bake(icon: String, px: Vector2i, drawer: Callable) -> Texture2D:
	var t: Texture2D = _tex.get(icon)
	if t != null or _pending.has(icon) or DisplayServer.get_name() == "headless":
		return t
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_pending[icon] = true
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Ctl.new()
	c.drawer = drawer
	c.size = Vector2(px)
	vp.add_child(c)
	tree.root.add_child(vp)
	_collect.call_deferred(vp, icon, 0)
	return null


static func _collect(vp: SubViewport, icon: String, n: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		if n < 3:
			_collect.call_deferred(vp, icon, n + 1)
			return
	else:
		img.generate_mipmaps()
		_tex[icon] = ImageTexture.create_from_image(img)
	_pending.erase(icon)
	vp.queue_free()
