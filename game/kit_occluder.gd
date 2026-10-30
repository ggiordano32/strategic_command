extends Node
## The oblique view's kit nearness (tabletop pass 3, docs/design/art_pipeline.md "Pass 3, the oblique view"): the
## soldiers are drawn after the kit, so a man in front of a house covers it; a man behind one must not. This draws the
## kit's sorted MultiMeshes (game/battlekit.gd ob_mm) a second time, every frame, into a screen-sized SubViewport of its
## own world with the main view's canvas transform, each opaque pixel coloured with its nearness (16 bits in R, G;
## battlekit.gdshader ob_depth): the nearest piece's, since the MultiMesh is sorted farther first. The soldier and
## base shaders read it at SCREEN_UV and drop a fragment where a nearer piece is (soldiers.gdshaderinc). View only.
## Not on Graphics Low (the kit has no MultiMesh there: the men draw over it).

const BoardView := preload("res://game/board_view.gd")

var vp: SubViewport
var near_r := Vector2(0.0, 1.0)     # the encoding: origin, span (world px)
var _kits: Array = []
var _mmis: Array = []
var _hooked := false


## Builds the pass for the kits that have a sorted MultiMesh; false when none has (nothing to occlude).
func setup(kits: Array, field_h_px: float) -> bool:
	for k in kits:
		if k != null and k.ob_mm != null and k.ob_mat != null:
			_kits.append(k)
	if _kits.is_empty():
		return false
	near_r = Vector2(-BoardView.px_per_m * 300.0, field_h_px * BoardView.OBLIQUE_SIN + BoardView.px_per_m * 700.0)
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(vp)
	for k in _kits:
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = k.ob_mm
		mmi.material = _depth_mat(k.ob_mat)
		vp.add_child(mmi)
		_mmis.append(mmi)
	RenderingServer.frame_pre_draw.connect(_sync)
	_hooked = true
	_sync()
	return true


func _depth_mat(m: ShaderMaterial) -> ShaderMaterial:
	var d := m.duplicate() as ShaderMaterial
	d.set_shader_parameter("ob_depth", 1.0)
	d.set_shader_parameter("ob_near_r", near_r)
	return d


func texture() -> Texture2D:
	return vp.get_texture()


## Before every frame is drawn: the main view's size and canvas transform; a kit rebuilt (a Graphics switch) is
## followed.
func _sync() -> void:
	if not is_inside_tree():
		return
	var main := get_viewport()
	var sz := Vector2i(main.get_visible_rect().size.round())
	if vp.size != sz:
		vp.size = sz
	vp.canvas_transform = main.canvas_transform
	for q in _kits.size():
		var k = _kits[q]
		var mmi: MultiMeshInstance2D = _mmis[q]
		if mmi.multimesh != k.ob_mm:
			mmi.multimesh = k.ob_mm
			if k.ob_mat != null:
				mmi.material = _depth_mat(k.ob_mat)


func _exit_tree() -> void:
	if _hooked and RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)
		_hooked = false
