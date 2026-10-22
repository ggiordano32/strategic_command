extends Control
## The title menu's background, one of MenuPrefs.BACKGROUNDS (the selector at the bottom of the title screen): the
## live overworld (diorama.gd) or painted key art (assets/ui/keyart/<pack>.jpg, a dark placeholder until the file
## exists) of one setting, fitted cover-style with a 1 % parallax. Switching cross-fades the pictures (0.5 s); a
## diorama is built for the chosen setting (a step a frame; the setting's key art stands in until it is ready). On
## the campaign pages the key art follows the hovered setting card.
## A gradient darkens the left side under the entries. View only.

const MenuPrefs := preload("res://game/menu/menu_prefs.gd")
const Diorama := preload("res://game/menu/diorama.gd")
const PackView := preload("res://game/campaign/pack_view.gd")

const KEYART := "res://assets/ui/keyart/%s.jpg"
const PLACEHOLDER := {"west": [Color(0.05, 0.12, 0.14), Color(0.22, 0.16, 0.08)], "rome": [Color(0.07, 0.09, 0.14), Color(0.17, 0.2, 0.22)]}

signal diorama_built(ms: float)

var choice := "art_rome"      # the background in force (one of MenuPrefs.BACKGROUNDS)
var pack := "rome"            # the setting the key art shows (the choice's, or the hovered card's)
var mode := "art"             # what is in force: diorama / art
var diorama: Node = null
var _holder: SubViewportContainer
var _vp: SubViewport
var _art := {}                # pack -> ArtLayer
var _tw := {}                 # pack -> its fade tween
var _dim: ColorRect
var _shade: TextureRect
var _building := false
var par := Vector2.ZERO


class ArtLayer extends Control:
	var tex: Texture2D = null
	var cols: Array = []
	var par := Vector2.ZERO
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if tex == null:
			# no painted file yet: a dark vertical gradient
			var g := PackedColorArray([cols[0], cols[0], cols[1], cols[1]])
			draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), g)
			return
		var ts := tex.get_size()
		var k := maxf(size.x / ts.x, size.y / ts.y) * 1.03
		var dr := Rect2((size - ts * k) * 0.5 + par * size, ts * k)
		draw_texture_rect(tex, dr, false)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for p in ["west", "rome"]:
		var a := ArtLayer.new()
		a.cols = PLACEHOLDER[p]
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		a.modulate.a = 0.0
		add_child(a)
		_art[p] = a
		var path: String = KEYART % p
		if ResourceLoader.exists(path):
			a.tex = load(path) as Texture2D
		elif FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				a.tex = ImageTexture.create_from_image(img)
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
	set_process(false)


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


## Show the setting's key art (cross-fade); a diorama in force stays.
func show_pack(p: String) -> void:
	if not _art.has(p) or p == pack and (_art[p] as Control).modulate.a > 0.5:
		pack = p
		return
	pack = p
	if mode == "art":
		_fade_art(p)


## Start / refresh the background for `c` (one of MenuPrefs.BACKGROUNDS) at once. Called when the menu shows.
func activate(c: String) -> void:
	choice = c
	mode = MenuPrefs.kind(c)
	pack = MenuPrefs.pack_of(c)
	set_process(true)
	_drop_diorama()
	_holder.visible = false
	for k in _tw:
		if (_tw[k] as Tween).is_valid():
			(_tw[k] as Tween).kill()
	_tw.clear()
	# (the setting's key art is the stand-in until a diorama is ready)
	for k in _art:
		(_art[k] as Control).modulate.a = 1.0 if k == pack else 0.0
	if mode == "diorama":
		_start_diorama.call_deferred()


## Change to `c` with a cross-fade; the diorama is dropped and, if chosen, built anew for its setting.
func switch_to(c: String) -> void:
	if c == choice and (mode == "art" or diorama != null):
		return
	choice = c
	mode = MenuPrefs.kind(c)
	pack = MenuPrefs.pack_of(c)
	_drop_diorama()
	_holder.visible = false
	_fade_art(pack)
	if mode == "diorama":
		_start_diorama.call_deferred()


func deactivate() -> void:
	_drop_diorama()
	set_process(false)


func _start_diorama() -> void:
	if mode != "diorama" or _building or not is_visible_in_tree():
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


func _process(_delta: float) -> void:
	# a 1 % parallax with the pointer (tilt on a phone)
	var want := Vector2.ZERO
	var g := Input.get_gravity()
	if g.length() > 1.0 and DisplayServer.is_touchscreen_available() and OS.has_feature("mobile"):
		want = Vector2(clampf(g.x / 9.8, -0.5, 0.5), clampf(g.y / 9.8, -0.5, 0.5)) * 2.0
	elif size.x > 0.0 and size.y > 0.0:
		var m := get_local_mouse_position()
		want = Vector2(clampf(m.x / size.x, 0.0, 1.0), clampf(m.y / size.y, 0.0, 1.0)) * 2.0 - Vector2.ONE
	var np := par.lerp(want * 0.01, 0.05)
	if np.distance_to(par) < 0.00002:
		return
	par = np
	for k in _art:
		(_art[k] as ArtLayer).par = par
		(_art[k] as Control).queue_redraw()
