extends RefCounted
## Many antialiased polylines and lines drawn as ONE mesh (overworld frame time, 2026-10-27; view only).
## Godot's GL Compatibility renderer gives every antialiased draw_polyline three draw calls (the middle strip and
## two feather strips): the West map's edges, coast and beaches were about 5000 draw calls a frame, most of the
## frame. A batch collects the same polylines (and draw_multiline segments) in drawing order; `commit` makes one
## triangle-strip mesh whose vertices are only codes, and ink_lines.gdshader rebuilds Godot's own geometry for
## each vertex from the points (a float texture), the width scale `lw` and the offset scale `ls` (uniforms). So the
## picture is the one of the draw calls it replaces, a zoom only sets a uniform, and a colour can change without
## a rebuild (`set_color`). Typical use:
##   var b := InkLines.new()
##   b.polyline(pts, col, 2.4)          # 2.4 screen px wide at lw = 1 / zoom (map px per screen px)
##   b.commit()
##   b.draw(node, lw)                   # in node's _draw (it sets node.material)
## `off` (optional) moves each point by off[i] * ls (the beaches: one mesh for every zoom band).
## The mesh needs a texture read in the vertex stage, which some WebGL devices draw nothing from (Chrome on the
## Adreno 650 of the Tab S7, see soldier_layer.gd). `probe` checks it once (a 16 px SubViewport read back); until
## it passes, or where it fails, `draw` replays the recorded calls as the draw_polyline / draw_multiline they
## stand for (the old cost, the same picture). `--ink=0|1` (on the web `?ink=0|1`) forces either.
const SHADER := preload("res://game/campaign/ink_lines.gdshader")
const TW := 1024
const Y0 := -1000000.0
const FLAG_LOOP := 1
const FLAG_OFF := 2
const FLAG_LINE := 4

static var _tmpl := {}   # "p<n>:<loop>" / "l1" -> PackedVector2Array of codes (y 0)
## -1 not known yet (draw replays the calls), 0 replay (the probe drew nothing), 1 the mesh.
static var state := -1
static var _probing := false
const SETTINGS := "user://settings.cfg"
const PROBE_PX := 16

var _pts := PackedVector2Array()
var _off := PackedVector2Array()
var _par := PackedFloat32Array()
var _verts := PackedVector2Array()
var _n := 0
var mesh: ArrayMesh = null
var material: ShaderMaterial = null
var _par_tex: ImageTexture = null
var _par_dirty := false
var _rec: Array = []          # per id: [line?, points, offsets, colour, k] (the replay)
var _rec_ls := NAN            # the offset scale _rec_pts was made for
var _rec_pts: Array = []      # per id: the points moved by their offsets (replay)


## Number of polylines and lines added (ids are 0..count - 1 in order).
func count() -> int:
	return _n


## A polyline as draw_polyline(pts, col, k * lw, true) draws it; returns its id.
func polyline(pts: PackedVector2Array, col: Color, k: float, off := PackedVector2Array()) -> int:
	var n := pts.size()
	if n < 2:
		return -1
	var has_off := off.size() == n
	var loop := pts[0].is_equal_approx(pts[n - 1]) and (not has_off or off[0].is_equal_approx(off[n - 1]))
	return _add(pts, off if has_off else PackedVector2Array(), col, k,
		(FLAG_LOOP if loop else 0) | (FLAG_OFF if has_off else 0), "p%d:%d" % [n, 1 if loop else 0], n)


## Segments (point pairs) as draw_multiline(segs, col, k * lw, true) draws them; returns its id.
func multiline(segs: PackedVector2Array, col: Color, k: float, off := PackedVector2Array()) -> int:
	var n := segs.size()
	if n < 2 or n % 2 != 0:
		return -1
	var has_off := off.size() == n
	return _add(segs, off if has_off else PackedVector2Array(), col, k, FLAG_LINE | (FLAG_OFF if has_off else 0),
		"l%d" % (n / 2), n)


func _add(pts: PackedVector2Array, off: PackedVector2Array, col: Color, k: float, flags: int, key: String, n: int) -> int:
	var id := _n
	_n += 1
	_rec.append([flags & FLAG_LINE != 0, pts, off, col, k])
	var first := _pts.size()
	_pts.append_array(pts)
	if off.is_empty():
		_off.resize(_off.size() + n)   # (zeros)
	else:
		_off.append_array(off)
	_par.append_array(PackedFloat32Array([col.r, col.g, col.b, col.a, k, float(first), float(n), float(flags)]))
	if flags & FLAG_LINE:
		# (a line template is one segment's, shifted by 64 codes a segment: not cached per count)
		if not _tmpl.has("l1"):
			_tmpl["l1"] = _line_template(1)
		var t1: PackedVector2Array = _tmpl["l1"]
		for sg in n / 2:
			_verts.append_array(Transform2D(0.0, Vector2.ONE, 0.0, Vector2(float(sg * 64), Y0 - float(id))) * t1)
		return id
	if not _tmpl.has(key):
		_tmpl[key] = _poly_template(n, flags & FLAG_LOOP != 0)
	_verts.append_array(Transform2D(0.0, Vector2.ONE, 0.0, Vector2(0.0, Y0 - float(id))) * (_tmpl[key] as PackedVector2Array))
	return id


## Change polyline id's colour (no rebuild; uploaded at the next draw).
func set_color(id: int, col: Color) -> void:
	_rec[id][3] = col
	var o := id * 8
	if _par[o] != col.r or _par[o + 1] != col.g or _par[o + 2] != col.b or _par[o + 3] != col.a:
		_par[o] = col.r
		_par[o + 1] = col.g
		_par[o + 2] = col.b
		_par[o + 3] = col.a
		_par_dirty = true


## Build the mesh and the textures (call once after adding).
func commit() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("tex_w", TW)
	material.set_shader_parameter("ink_p", _float_tex(_pts.to_byte_array(), 2))
	material.set_shader_parameter("ink_o", _float_tex(_off.to_byte_array(), 2))
	_par_tex = _float_tex(_par.to_byte_array(), 4)
	material.set_shader_parameter("ink_par", _par_tex)
	mesh = null
	if _verts.size() >= 3:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = _verts
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arr)
	_verts = PackedVector2Array()


## Draw the batch on ci at width scale lw and offset scale ls (it sets ci's material: what else ci draws passes
## through the shader unchanged).
func draw(ci: CanvasItem, lw: float, ls := 1.0) -> void:
	if state != 1:
		if ci.material != null:
			ci.material = null
		_replay(ci, lw, ls)
		return
	if ci.material != material:
		ci.material = material
	if mesh == null:
		return
	if _par_dirty:
		_par_dirty = false
		_par_tex.update(_float_image(_par.to_byte_array(), 4))
	material.set_shader_parameter("lw", lw)
	material.set_shader_parameter("ls", ls)
	ci.draw_mesh(mesh, null)


## The calls the batch stands for (a device without vertex texture reads, or before the probe).
func _replay(ci: CanvasItem, lw: float, ls: float) -> void:
	if _rec_ls != ls:
		_rec_ls = ls
		_rec_pts = []
		for r in _rec:
			var pts: PackedVector2Array = r[1]
			var off: PackedVector2Array = r[2]
			if off.is_empty():
				_rec_pts.append(pts)
			else:
				var moved := PackedVector2Array()
				moved.resize(pts.size())
				for i in pts.size():
					moved[i] = pts[i] + off[i] * ls
				_rec_pts.append(moved)
	for id in _rec.size():
		var r: Array = _rec[id]
		if r[0]:
			ci.draw_multiline(_rec_pts[id], r[3], float(r[4]) * lw, true)
		else:
			ci.draw_polyline(_rec_pts[id], r[3], float(r[4]) * lw, true)


## Find out once whether this device draws the mesh (state 1) or not (0): a thick line drawn by the shader into a
## 16 px SubViewport under `host`, read back after two frames (callers watch `state`). A device the battle's
## soldier probe sent to its CPU path ([video] soldiers = cpu) is not probed (no vertex texture reads there either).
static func probe(host: Node) -> void:
	if state >= 0 or _probing:
		return
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)   # (on the web: ?ink=0 or ?ink=1)
		if q is String:
			for kv in (q as String).trim_prefix("?").split("&"):
				args.append("--" + kv)
	for a in args:
		if str(a) == "--ink=0" or str(a) == "--ink=1":
			state = 1 if str(a) == "--ink=1" else 0
			return
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK and str(cf.get_value("video", "soldiers", "auto")) == "cpu":
		state = 0
		return
	if DisplayServer.get_name() == "headless":
		state = 0
		return
	var b := new()
	b.polyline(PackedVector2Array([Vector2(-4, PROBE_PX * 0.5), Vector2(PROBE_PX + 4, PROBE_PX * 0.5)]), Color.WHITE, 8.0)
	b.commit()
	var vp := SubViewport.new()
	vp.size = Vector2i(PROBE_PX, PROBE_PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var nd := Node2D.new()
	no_cull(nd)
	nd.material = b.material
	nd.draw.connect(func(): nd.draw_mesh(b.mesh, null))
	vp.add_child(nd)
	host.add_child(vp)
	_probing = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_probing = false
	if not is_instance_valid(vp):
		return   # (the map closed meanwhile: probe again next time)
	var drawn := 0
	var img := vp.get_texture().get_image()
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
		var px := img.get_data()
		for i in range(3, px.size(), 4):
			if px[i] > 64:
				drawn += 1
	vp.queue_free()
	state = 1 if drawn >= PROBE_PX * 2 else 0
	print("INK_PROBE drawn=%d state=%d" % [drawn, state])


## The node's canvas item is never culled by the codes' bounds (the mesh's vertices are not positions).
static func no_cull(ci: CanvasItem) -> void:
	RenderingServer.canvas_item_set_custom_rect(ci.get_canvas_item(), true, Rect2(-1e6, -1e6, 2e6, 2e6))


static func _float_image(bytes: PackedByteArray, ch: int) -> Image:
	var texel := ch * 4
	var n := bytes.size() / texel
	var h := maxi(1, (n + TW - 1) / TW)
	bytes.resize(TW * h * texel)
	return Image.create_from_data(TW, h, false, Image.FORMAT_RGF if ch == 2 else Image.FORMAT_RGBAF, bytes)


static func _float_tex(bytes: PackedByteArray, ch: int) -> ImageTexture:
	return ImageTexture.create_from_image(_float_image(bytes, ch))


## Codes of one polyline of n points: the middle strip, the left and right feather strips (Godot's vertex order),
## joined by repeated vertices (degenerate triangles), the first and last vertex repeated so templates chain.
static func _poly_template(n: int, loop: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for side in 3:
		var strip := PackedVector2Array()
		var s0 := 1 if side != 2 else 0   # the S bit of the edge side: + for middle-first and left, - for right
		if side == 0:
			if not loop:
				strip.append(Vector2(0 * 16 + 1 + 4, 0))
				strip.append(Vector2(0 * 16 + 0 + 4, 0))
			for i in n:
				strip.append(Vector2(i * 16 + 1, 0))
				strip.append(Vector2(i * 16 + 0, 0))
			if not loop:
				strip.append(Vector2((n - 1) * 16 + 1 + 8, 0))
				strip.append(Vector2((n - 1) * 16 + 0 + 8, 0))
		else:
			if not loop:
				strip.append(Vector2(0 * 16 + s0 + 4, 0))
				strip.append(Vector2(0 * 16 + s0 + 2 + 4, 0))
			for i in n:
				strip.append(Vector2(i * 16 + s0, 0))
				strip.append(Vector2(i * 16 + s0 + 2, 0))
			if not loop:
				strip.append(Vector2((n - 1) * 16 + s0, 0))
				strip.append(Vector2((n - 1) * 16 + s0 + 2 + 8, 0))
				strip.append(Vector2((n - 1) * 16 + s0 + 8, 0))
		out.append(strip[0])
		out.append_array(strip)
		out.append(strip[strip.size() - 1])
	return out


## Codes of `segs` lines: per segment the quad and its eight feather quads (Godot's order), each quad [a, b, c, d]
## drawn as the triangles (a, b, c), (a, c, d): the strip b, a, c, d.
static func _line_template(segs: int) -> PackedVector2Array:
	# [E, U(+1/-1), sv, sw] per corner of each quad
	var quads := [
		[[0, 1, 0, 0], [0, -1, 0, 0], [1, -1, 0, 0], [1, 1, 0, 0]],
		[[0, 1, 0, 0], [0, 1, 1, 0], [1, 1, 1, 0], [1, 1, 0, 0]],
		[[0, -1, 0, 0], [0, -1, -1, 0], [1, -1, -1, 0], [1, -1, 0, 0]],
		[[0, 1, 0, 0], [0, 1, 0, 1], [0, -1, 0, 1], [0, -1, 0, 0]],
		[[1, 1, 0, 0], [1, 1, 0, -1], [1, -1, 0, -1], [1, -1, 0, 0]],
		[[0, 1, 0, 0], [0, 1, 0, 1], [0, 1, 1, 1], [0, 1, 1, 0]],
		[[0, -1, 0, 0], [0, -1, 0, 1], [0, -1, -1, 1], [0, -1, -1, 0]],
		[[1, 1, 0, 0], [1, 1, 0, -1], [1, 1, 1, -1], [1, 1, 1, 0]],
		[[1, -1, 0, 0], [1, -1, 0, -1], [1, -1, -1, -1], [1, -1, -1, 0]],
	]
	var out := PackedVector2Array()
	for sg in segs:
		for q in quads:
			var c := PackedVector2Array()
			for k in [1, 0, 2, 3]:
				var e: Array = q[k]
				c.append(Vector2(sg * 64 + int(e[0]) + (2 if int(e[1]) > 0 else 0) + 4 * (int(e[2]) + 1) + 12 * (int(e[3]) + 1), 0))
			out.append(c[0])
			out.append_array(c)
			out.append(c[3])
	return out
