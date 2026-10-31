extends Control
## The title menu's background, one of MenuPrefs.BACKGROUNDS (the selector at the bottom of the title screen): the
## live overworld (diorama.gd) of one setting, built a step a frame; the setting's placeholder gradient (a dark wood
## for the West, a cool stone for Rome: MenuPrefs.PLACEHOLDER, no picture) stands in until it is ready, behind it,
## and where it is not built at all (a test run). Switching drops the table and builds the other (0.5 s cross-fade).
## On the campaign pages the placeholder follows the hovered setting card while no table shows.
## A gradient darkens the left side under the entries. View only.

const MenuPrefs := preload("res://game/menu/menu_prefs.gd")
const Diorama := preload("res://game/menu/diorama.gd")
const PackView := preload("res://game/campaign/pack_view.gd")

signal diorama_built(ms: float)

var choice := "diorama_rome"  # the background in force (one of MenuPrefs.BACKGROUNDS)
var pack := "rome"            # the setting the placeholder shows (the choice's, or the hovered card's)
var mode := "diorama"         # always the live table (kept for the callers)
var diorama: Node = null
var _holder: SubViewportContainer
var _vp: SubViewport
var _art := {}                # pack -> ArtLayer
var _tw := {}                 # pack -> its fade tween
var _dim: ColorRect
var _shade: TextureRect
var _building := false


class ArtLayer extends Control:
	var cols: Array = []
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var g := PackedColorArray([cols[0], cols[0], cols[1], cols[1]])
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), g)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for p in ["west", "rome"]:
		var a := ArtLayer.new()
		a.cols = MenuPrefs.PLACEHOLDER[p]
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		a.modulate.a = 0.0
		add_child(a)
		_art[p] = a
	_holder = SubViewportContainer.new()
	_holder.stretch = true
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.modulate.a = 0.0
	_holder.visible = false
	add_child(_holder)
	_vp = SubViewport.new()
	_vp.handle_input_locally = false
	_vp.disable_3d = true
	_holder.add_child(_vp)
	# A gradient under the entries (left) and a flat dim for the pages.
	_shade = TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.02, 0.03, 0.03, 0.92), Color(0.02, 0.03, 0.03, 0.72), Color(0.02, 0.03, 0.03, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.4, 0.8])
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	gt.width = 256
	gt.height = 4
	_shade.texture = gt
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.03, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	resized.connect(_on_resized)


func _on_resized() -> void:
	if diorama != null and is_instance_valid(diorama) and diorama.ready_flag:
		diorama.resize(size)


## Dim the picture for a sub-page (a = 0 on the title screen).
func set_dim(a: float, shade: bool) -> void:
	_dim.color.a = a
	_shade.visible = shade


func _fade_art(p: String) -> void:
	for k in _art:
		var a: Control = _art[k]
		if _tw.has(k) and (_tw[k] as Tween).is_valid():
			(_tw[k] as Tween).kill()
		var tw := create_tween()
		tw.tween_property(a, "modulate:a", 1.0 if k == p else 0.0, 0.5)
		_tw[k] = tw


## Show the setting's placeholder (cross-fade); a table that is up stays.
func show_pack(p: String) -> void:
	if not _art.has(p) or p == pack and (_art[p] as Control).modulate.a > 0.5:
		pack = p
		return
	pack = p
	if diorama == null:
		_fade_art(p)


## Start / refresh the background for `c` (one of MenuPrefs.BACKGROUNDS) at once. Called when the menu shows.
func activate(c: String) -> void:
	choice = c
	mode = MenuPrefs.kind(c)
	pack = MenuPrefs.pack_of(c)
	_drop_diorama()
	_holder.visible = false
	for k in _tw:
		if (_tw[k] as Tween).is_valid():
			(_tw[k] as Tween).kill()
	_tw.clear()
	# (the setting's placeholder is the stand-in until the table is ready)
	for k in _art:
		(_art[k] as Control).modulate.a = 1.0 if k == pack else 0.0
	if not MenuPrefs.skip_live():
		_start_diorama.call_deferred()


## Change to `c` with a cross-fade; the diorama is dropped and, if chosen, built anew for its setting.
func switch_to(c: String) -> void:
	if c == choice and diorama != null:
		return
	choice = c
	mode = MenuPrefs.kind(c)
	pack = MenuPrefs.pack_of(c)
	_drop_diorama()
	_holder.visible = false
	_fade_art(pack)
	if not MenuPrefs.skip_live():
		_start_diorama.call_deferred()


func deactivate() -> void:
	_drop_diorama()


func _start_diorama() -> void:
	if _building or not is_visible_in_tree():
		return
	if diorama != null and is_instance_valid(diorama):
		return
	_building = true
	var d := Diorama.new()
	diorama = d
	_vp.add_child(d)
	d.built.connect(func(ms):
		_building = false
		_holder.visible = true
		create_tween().tween_property(_holder, "modulate:a", 1.0, 0.5)
		diorama_built.emit(ms)
		if "--menu-log" in OS.get_cmdline_user_args():
			print("DIORAMA ", choice, " built in ", snappedf(ms, 0.1), " ms: ", d.steps_ms), CONNECT_ONE_SHOT)
	d.build(MenuPrefs.pack_of(choice), size)


func _drop_diorama() -> void:
	if diorama != null and is_instance_valid(diorama):
		diorama.release()
	diorama = null
	_building = false
	if _holder != null:
		_holder.modulate.a = 0.0
