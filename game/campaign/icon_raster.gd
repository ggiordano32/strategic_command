extends RefCounted
## Raster cache of the vector UI icons (game/ui_icons.gd) for the campaign's controls (overworld tap latency,
## 2026-10-16). A vector icon is a few dozen antialiased strokes and dots recorded by GDScript every time its
## control draws: the command bar's ~50 icons cost ~6 ms of a tap's frame on a desktop (several times that on a
## tablet's browser). Here each icon is drawn once, in white, into an atlas (a SubViewport that renders only when
## an icon is added) at the screen's physical pixel size, and a control then draws one textured quad tinted with
## its colour. Until the atlas frame holding an icon has rendered (the first frame it is asked for) the icon is
## drawn as vectors, as before, so nothing is ever missing.
##
## The atlas holds straight-alpha white (its items draw with premultiplied blending and a shader that keeps the
## colour white while the coverage goes to alpha), so a tint is exact. Off when `enabled` is false (a testing aid
## to compare) or past MAX_PX; a full atlas falls back to vectors.

const UiIcons := preload("res://game/ui_icons.gd")

const ATLAS_W := 1024
const ATLAS_H := 1024
const PAD := 2                 # empty pixels round each icon (no bleeding when sampled with a linear filter)
const MAX_PX := 128            # bigger icons stay vectors

static var enabled := true
static var _vp: SubViewport = null
static var _mat: ShaderMaterial = null
static var _slots := {}        # "icon@px" -> Rect2 (atlas pixels)
static var _ready := {}        # keys whose atlas frame has rendered
static var _queued: Array = [] # [key, icon, px, Rect2] waiting for _flush (this frame's end)
static var _rendering: Array = []  # keys drawn in the update in flight (ready after frame_post_draw)
static var _x := 0
static var _y := 0
static var _row_h := 0
static var _full := false
static var _flush_on := false
static var _hooked := false

const SHADER := """
shader_type canvas_item;
render_mode blend_premul_alpha;
void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, COLOR.a);
}
"""


## The physical pixels per logical pixel of the main window's canvas (canvas_items stretch).
static func screen_scale() -> float:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null or ml.root == null:
		return 1.0
	var s := ml.root.get_final_transform().get_scale()
	return maxf(minf(absf(s.x), absf(s.y)), 0.25)


## Draw `icon` filling the square centred in rect on the canvas item rid, tinted col (as UiIcons.draw_rid).
static func draw_rid(rid: RID, icon: String, rect: Rect2, col: Color) -> void:
	var side := minf(rect.size.x, rect.size.y)
	var px := ceili(side * screen_scale() - 0.01)
	if not enabled or px < 4 or px > MAX_PX or icon == "":
		UiIcons.draw_rid(rid, icon, rect, col)
		return
	var key := "%s@%d" % [icon, px]
	if not _ready.has(key):
		if not _slots.has(key):
			_request(key, icon, px)
		UiIcons.draw_rid(rid, icon, rect, col)
		return
	var reg: Rect2 = _slots[key]
	var dst := Rect2(rect.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	RenderingServer.canvas_item_add_texture_rect_region(rid, dst, _vp.get_texture().get_rid(), reg, col)


static func draw_icon(ci: CanvasItem, icon: String, rect: Rect2, col: Color) -> void:
	draw_rid(ci.get_canvas_item(), icon, rect, col)


## The icon as a texture of px x px logical pixels for a Button / TextureRect (drawn from the atlas once ready).
static func tex(icon: String, px: int = 19) -> Texture2D:
	var t := RasterIcon.new()
	t.drawer = load("res://game/campaign/icon_raster.gd")
	t.icon = icon
	t.px = px
	return t


## Ask for the icons ahead (e.g. the command bar's actions when the campaign opens): they are drawn into the
## atlas at the end of this frame, so the first bar already uses them.
static func warm(icons: Array, logical_px: Array) -> void:
	if not enabled:
		return
	var sc := screen_scale()
	for p in logical_px:
		var px := ceili(float(p) * sc - 0.01)
		if px < 4 or px > MAX_PX:
			continue
		for ic in icons:
			var key := "%s@%d" % [str(ic), px]
			if not _slots.has(key):
				_request(key, str(ic), px)


static func _request(key: String, icon: String, px: int) -> void:
	if _full:
		return
	var w := px + 2 * PAD
	if _x + w > ATLAS_W:
		_x = 0
		_y += _row_h
		_row_h = 0
	if _y + w > ATLAS_H:
		_full = true
		return
	var reg := Rect2(_x + PAD, _y + PAD, px, px)
	_x += w
	_row_h = maxi(_row_h, w)
	_slots[key] = reg
	_queued.append([key, icon, px, reg])
	if not _flush_on:
		_flush_on = true
		_flush.call_deferred()


static func _flush() -> void:
	_flush_on = false
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null or _queued.is_empty():
		return
	if _vp == null or not is_instance_valid(_vp):
		_vp = SubViewport.new()
		_vp.name = "icon_raster"
		_vp.size = Vector2i(ATLAS_W, ATLAS_H)
		_vp.transparent_bg = true
		_vp.disable_3d = true
		_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		ml.root.add_child(_vp)
		_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		_mat.shader = sh
		# (a scene change frees the viewport with the old tree: everything is asked again)
		_vp.tree_exiting.connect(_forget)
	if not _hooked:
		_hooked = true
		RenderingServer.frame_post_draw.connect(_rendered)
	for q in _queued:
		var nd := Node2D.new()
		nd.material = _mat
		var ic: String = q[1]
		var reg: Rect2 = q[3]
		nd.draw.connect(func(): UiIcons.draw_rid(nd.get_canvas_item(), ic, reg, Color.WHITE))
		_vp.add_child(nd)
		_rendering.append(q[0])
	_queued = []
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


static func _rendered() -> void:
	if _rendering.is_empty() or _vp == null or not is_instance_valid(_vp):
		return
	# (the atlas update was asked in this frame's process, so this frame drew it)
	for k in _rendering:
		_ready[k] = true
	_rendering = []


static func _forget() -> void:
	_vp = null
	_slots = {}
	_ready = {}
	_queued = []
	_rendering = []
	_x = 0
	_y = 0
	_row_h = 0
	_full = false


## A Texture2D drawing its icon from the atlas (vectors until it is there).
class RasterIcon extends Texture2D:
	var icon := ""
	var px := 19
	var drawer: Script  # this file (an inner class cannot call its outer class)

	func _get_width() -> int:
		return px

	func _get_height() -> int:
		return px

	func _has_alpha() -> bool:
		return true

	func _is_pixel_opaque(_x: int, _y: int) -> bool:
		return false

	func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, _transpose: bool) -> void:
		drawer.call("draw_rid", to_canvas_item, icon, Rect2(pos, Vector2(px, px)), modulate)

	func _draw_rect(to_canvas_item: RID, rect: Rect2, _tile: bool, modulate: Color, _transpose: bool) -> void:
		drawer.call("draw_rid", to_canvas_item, icon, rect, modulate)

	func _draw_rect_region(to_canvas_item: RID, rect: Rect2, _src_rect: Rect2, modulate: Color, _transpose: bool, _clip_uv: bool) -> void:
		drawer.call("draw_rid", to_canvas_item, icon, rect, modulate)
