extends RefCounted
## The overworld overlay's drawing in a few draw calls (overworld overlay cost, 2026-10-29; view only).
## Godot's GL Compatibility renderer gives every circle, polygon and polyline its own draw call (an antialiased
## polyline or arc three), and the overlay's markers, standards and roundels were about 1000 of them a frame. A batch
## takes the same calls (the CanvasItem drawing methods the overlay's painters use, by the same names: a painter
## draws on a batch or on a CanvasItem alike) and makes, on the CPU, exactly the triangles Godot makes for them
## (servers/rendering/renderer_canvas_cull.cpp and scene/main/canvas_item.cpp, 4.7: circles as 64-triangle fans,
## the antialiased polyline's middle strip and feather strips, a line's quad and its eight feather quads, a rect's
## quad and feathers, polygons by Geometry2D.triangulate_polygon) with the same colours, in drawing order. Text is
## drawn as before (TextLine / Font glyph rects, which the renderer batches by glyph texture).
## `flush` emits the ops in batches: all the triangles of a batch as ONE `canvas_item_add_triangle_array`, the text
## of a batch together. Ops are moved into an earlier batch only when nothing drawn between overlaps them (a grid of
## 48 px cells keeps, per cell, the last batch drawn over it), so the picture is the one of the calls it replaces:
## names over markers, a later marker over an earlier name, all as before.
## Repeated shapes are kept as glyphs (`glyph`: a marker drawn once round (0, 0) and stamped at each place, keyed by
## what it depends on). With `ink` set (an InkLines batch; ink_lines.gd) antialiased multilines (the sea lanes'
## dashes) are left to its vertex shader, as codes in the same triangle array: `flush` then sets the node's material.
## Typical use:
##   var b := OvBatch.new()
##   b.begin()
##   painter(b, ...)        # b.draw_circle(...), b.draw_arc(...), b.text_line(...)
##   b.flush(node)          # in node's _draw

const FEATHER := 1.25
const CMP_EPS := 0.00001
const CELL := 48.0
const BIG_CELLS := 40   # an op over more grid cells than this is checked by its rectangle (a short list)
const GEO := "g"
const CACHE_VERTS := 400000   # the arc and glyph caches are emptied past this many vertices (about 10 MB)
const InkLines := preload("res://game/campaign/ink_lines.gd")

static var _fan := PackedVector2Array()     # a unit circle as 64 triangles (centre, i, i + 1): Godot's ellipse
static var _arc_cache := {}                 # [r, a0, a1, n, colour, width, aa] -> [triangles round (0, 0), colours, rect]
static var _glyphs := {}                    # glyph key -> its ops round (0, 0) (see `glyph`)
static var _cached := 0                     # vertices held by the two caches (keys hold the zoom: a zoom fills them anew)

var _key: Array = []        # per batch: GEO or a text key
var _bv: Array = []         # per batch: PackedVector2Array (GEO) or null
var _bc: Array = []         # per batch: PackedColorArray (GEO) or null
var _bt: Array = []         # per batch: text ops (else null)
var _by_key := {}           # key -> batch indices, ascending
var _grid := {}             # Vector2i cell -> the last batch drawn over it
var _big: Array = []        # [Rect2, batch] of the ops too big for the grid
# geometry drawn since the last op of another kind, placed as one op (the arrays as given: never written to, the glyphs'
# and arcs' cached arrays among them; packed arrays held in variables are shared, not copied)
var _pv: Array = []
var _pc: Array = []
var _pr := Rect2()
var _pn := false
var ops := 0                # (profiling) ops placed since begin
var ink: InkLines = null    # set before drawing: multilines go to its shader (when the device draws it: InkLines.state)
var _ink_used := false
var _cap: Array = []        # the glyph being captured: ["g", verts, colours, rect] / ["t", key, rect, op]
var _capturing := false
var _cap_native := false


func begin() -> void:
	_key.clear()
	_bv.clear()
	_bc.clear()
	_bt.clear()
	_by_key.clear()
	_grid.clear()
	_big.clear()
	_pv = []
	_pc = []
	_pn = false
	ops = 0
	_ink_used = false


## Emit everything recorded since `begin` on ci (in its _draw) and start empty.
func flush(ci: CanvasItem) -> void:
	_flush_geo()
	var rid := ci.get_canvas_item()
	if _ink_used:
		ink.commit()
		ink.material.set_shader_parameter("lw", 1.0)
		ink.material.set_shader_parameter("ls", 1.0)
		if ci.material != ink.material:
			ci.material = ink.material
		InkLines.no_cull(ci)
	elif ci.material != null:
		ci.material = null
	for b in _key.size():
		if _key[b] == GEO:
			var v: PackedVector2Array = _bv[b]
			if v.size() >= 3:
				RenderingServer.canvas_item_add_triangle_array(rid, PackedInt32Array(), v, _bc[b])
		else:
			for op in _bt[b]:
				_text_op(ci, rid, op)
	begin()


## Number of batches (a geometry batch is one draw call; a text batch one or two).
func batch_count() -> int:
	return _key.size() + (1 if _pn else 0)


# ------------------------------------------------------------ placement ---

## The batch an op of `key` covering rectangle r goes into: the earliest batch of that key after the last batch
## drawn over r (a new one at the end if none).
func _place(key: String, r: Rect2) -> int:
	ops += 1
	var x0 := int(floor(r.position.x / CELL))
	var y0 := int(floor(r.position.y / CELL))
	var x1 := int(floor(r.end.x / CELL))
	var y1 := int(floor(r.end.y / CELL))
	var big := (x1 - x0 + 1) * (y1 - y0 + 1) > BIG_CELLS
	var dep := -1
	if big:
		dep = _key.size() - 1   # (conservative: after everything)
	else:
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				var c: int = _grid.get(Vector2i(x, y), -1)
				if c > dep:
					dep = c
		for e in _big:
			if int(e[1]) > dep and (e[0] as Rect2).intersects(r):
				dep = int(e[1])
	var b := -1
	var lst: Array = _by_key.get(key, [])
	for i in range(lst.size() - 1, -1, -1):
		if int(lst[i]) > dep:
			b = int(lst[i])
		else:
			break
	if b < 0:
		b = _key.size()
		_key.append(key)
		if key == GEO:
			_bv.append(PackedVector2Array())
			_bc.append(PackedColorArray())
			_bt.append(null)
		else:
			_bv.append(null)
			_bc.append(null)
			_bt.append([])
		lst.append(b)
		_by_key[key] = lst
	if big:
		_big.append([r, b])
	else:
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				_grid[Vector2i(x, y)] = b
	return b


## Geometry (a triangle list) with its bounding rectangle: joined to the pending geometry while that stays small.
func _geo(v: PackedVector2Array, c: PackedColorArray, r: Rect2) -> void:
	if v.is_empty():
		return
	if _pn:
		var u := _pr.merge(r)
		if u.size.x <= CELL * 3.0 and u.size.y <= CELL * 3.0:
			_pv.append(v)
			_pc.append(c)
			_pr = u
			return
		_flush_geo()
	_pv = [v]
	_pc = [c]
	_pr = r
	_pn = true


func _flush_geo() -> void:
	if not _pn:
		return
	_pn = false
	if _capturing:
		var cv := PackedVector2Array()
		var cc := PackedColorArray()
		for k in _pv.size():
			cv.append_array(_pv[k])
			cc.append_array(_pc[k])
		_cap.append(["g", cv, cc, _pr])
		return
	var b := _place(GEO, _pr)
	# (an Array element read as a packed array is a copy: take the batch's arrays out, grow them, put them back)
	var v: PackedVector2Array = _bv[b]
	var c: PackedColorArray = _bc[b]
	_bv[b] = null
	_bc[b] = null
	for k in _pv.size():
		v.append_array(_pv[k])
		c.append_array(_pc[k])
	_bv[b] = v
	_bc[b] = c


func _text(key: String, r: Rect2, op: Array) -> void:
	_flush_geo()
	if _capturing:
		_cap.append(["t", key, r, op])
		if int(op[0]) == 4:
			_cap_native = true
		return
	var b := _place(key, r)
	(_bt[b] as Array).append(op)


static func _keep_small() -> void:
	if _cached > CACHE_VERTS:
		_cached = 0
		_glyphs.clear()
		_arc_cache.clear()


## A glyph: what f(batch, p) draws at p, drawn once at (0, 0) and kept under `key` (everything the drawing depends on
## but the place), then stamped at `at` (its triangles moved, its text placed). A drawing with a call the batch
## cannot move (a hairline) is not kept.
func glyph(key: Array, at: Vector2, f: Callable) -> void:
	var g: Array = _glyphs.get(key, [])
	if g.is_empty():
		if _capturing:
			f.call(self, at)   # (a glyph inside a glyph: drawn in place)
			return
		_flush_geo()
		_capturing = true
		_cap_native = false
		_cap = []
		f.call(self, Vector2.ZERO)
		_flush_geo()
		_capturing = false
		g = _cap
		_cap = []
		if _cap_native:
			f.call(self, at)
			return
		for e in g:
			if e[0] == "g":
				_cached += (e[1] as PackedVector2Array).size()
		_keep_small()
		_glyphs[key] = g
	var t := Transform2D(0.0, at)
	for e in g:
		if e[0] == "g":
			var gr: Rect2 = e[3]
			_geo(t * (e[1] as PackedVector2Array), e[2], Rect2(gr.position + at, gr.size))
		else:
			var tr_: Rect2 = e[2]
			var op: Array = (e[3] as Array).duplicate()
			op[2] = (op[2] as Vector2) + at
			_text(e[1], Rect2(tr_.position + at, tr_.size), op)


# --------------------------------------------------------------- text ---

## TextLine tl with its top left at `top` (the overlay's `put`): the outline (width ow, 0 none) then the fill.
func text_line(tl: TextLine, top: Vector2, col: Color, ow: int, oc: Color, fs: int, display: bool) -> void:
	var r := Rect2(top, tl.get_size()).grow(2.0 + ow)
	if ow > 0:
		_text("o%d_%d_%d" % [fs, ow, 1 if display else 0], r, [0, tl, top, ow, oc])
	_text("f%d_%d" % [fs, 1 if display else 0], r, [1, tl, top, col])


func draw_string(font: Font, pos: Vector2, text: String, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, fs := 16,
		col := Color.WHITE) -> void:
	var sz := font.get_string_size(text, align, width, fs)
	var r := Rect2(pos - Vector2(0.0, font.get_ascent(fs)), sz).grow(2.0)
	_text("f%d_0" % fs, r, [2, font, pos, text, align, width, fs, col])


func draw_string_outline(font: Font, pos: Vector2, text: String, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0,
		fs := 16, size := 1, col := Color.WHITE) -> void:
	var sz := font.get_string_size(text, align, width, fs)
	var r := Rect2(pos - Vector2(0.0, font.get_ascent(fs)), sz).grow(2.0 + size)
	_text("o%d_%d_0" % [fs, size], r, [3, font, pos, text, align, width, fs, size, col])


func _text_op(ci: CanvasItem, rid: RID, op: Array) -> void:
	match int(op[0]):
		0:
			(op[1] as TextLine).draw_outline(rid, op[2], int(op[3]), op[4])
		1:
			(op[1] as TextLine).draw(rid, op[2], op[3])
		2:
			ci.draw_string(op[1], op[2], op[3], op[4], op[5], op[6], op[7])
		3:
			ci.draw_string_outline(op[1], op[2], op[3], op[4], op[5], op[6], op[7], op[8])
		4:   # (a call with no triangles of its own: a hairline, width < 0)
			(op[1] as Callable).call(ci)


# ---------------------------------------------------------- the shapes ---

func draw_circle(p: Vector2, radius: float, col: Color, filled := true, width := -1.0, aa := false) -> void:
	_ellipse_call(p, radius, radius, col, filled, width, aa)


func _ellipse_call(p: Vector2, major: float, minor: float, col: Color, filled: bool, width: float, aa: bool) -> void:
	if filled:
		_ellipse(p, major, minor, col, aa)
	elif width >= 2.0 * maxf(major, minor):
		_ellipse(p, major + 0.5 * width, minor + 0.5 * width, col, aa)
	else:
		var pts := PackedVector2Array()
		pts.resize(65)
		for i in 64:
			var a := float(i) * (TAU / 64.0)
			pts[i] = p + Vector2(cos(a) * major, sin(a) * minor)
		pts[64] = pts[0]
		draw_polyline(pts, col, width, aa)


func _ellipse(p: Vector2, major: float, minor: float, col: Color, aa: bool) -> void:
	if aa:
		major = maxf(0.0, major - FEATHER * 0.25)
		minor = maxf(0.0, minor - FEATHER * 0.25)
	if _fan.is_empty():
		var u := PackedVector2Array()
		for i in 65:
			var a := float(i) * (TAU / 64.0)
			u.append(Vector2(cos(a), sin(a)))
		for i in 64:
			_fan.append(Vector2.ZERO)
			_fan.append(u[i])
			_fan.append(u[i + 1])
	var v: PackedVector2Array = Transform2D(0.0, Vector2(major, minor), 0.0, p) * _fan
	var c := PackedColorArray()
	c.resize(v.size())
	c.fill(col)
	var r := Rect2(p - Vector2(major, minor), Vector2(major, minor) * 2.0)
	if not aa:
		_geo(v, c, r)
		return
	var bs := FEATHER
	var mx := maxf(major, minor) * 2.0
	if 0.0 <= mx and mx < 1.0:
		bs *= mx * 0.5
	var sp := PackedVector2Array()
	var sc := PackedColorArray()
	var tc := Color(col, 0.0)
	for i in 65:
		var a := float(i) * (TAU / 64.0)
		var ca := cos(a)
		var sa := sin(a)
		sp.append(p + Vector2(ca * major, sa * minor))
		sp.append(p + Vector2(ca * (major + bs), sa * (minor + bs)))
		sc.append(col)
		sc.append(tc)
	_strip(sp, sc, v, c)
	_geo(v, c, r.grow(bs + 1.0))


func draw_arc(center: Vector2, radius: float, a0: float, a1: float, n: int, col: Color, width := -1.0, aa := false) -> void:
	if width < 0.0:
		_native(func(ci: CanvasItem): ci.draw_arc(center, radius, a0, a1, n, col, width, aa), Rect2(center, Vector2.ZERO).grow(radius + 2.0))
		return
	var key := [radius, a0, a1, n, col, width, aa]
	var e: Array = _arc_cache.get(key, [])
	if e.is_empty():
		var pts := PackedVector2Array()
		pts.resize(n)
		var da := clampf(a1 - a0, -TAU, TAU)
		for i in n:
			var th := (float(i) / (n - 1.0)) * da + a0
			pts[i] = Vector2(radius * cos(th), radius * sin(th))
		var v := PackedVector2Array()
		var c := PackedColorArray()
		_polyline_tris(pts, col, width, aa, v, c)
		e = [v, c, Rect2(-radius, -radius, radius * 2.0, radius * 2.0).grow(width * 0.5 + FEATHER * 3.0 + 1.0)]
		_cached += v.size()
		_keep_small()
		_arc_cache[key] = e
	var r: Rect2 = e[2]
	_geo(Transform2D(0.0, center) * (e[0] as PackedVector2Array), e[1], Rect2(r.position + center, r.size))


func draw_polyline(pts: PackedVector2Array, col: Color, width := -1.0, aa := false) -> void:
	if pts.size() < 2:
		return
	if width < 0.0:
		_native(func(ci: CanvasItem): ci.draw_polyline(pts, col, width, aa), _bounds(pts, 2.0))
		return
	var v := PackedVector2Array()
	var c := PackedColorArray()
	_polyline_tris(pts, col, width, aa, v, c)
	_geo(v, c, _bounds(pts, width * 0.5 * 3.0 + FEATHER * 3.0 + 1.0))


func draw_line(a: Vector2, b: Vector2, col: Color, width := -1.0, aa := false) -> void:
	if width < 0.0:
		_native(func(ci: CanvasItem): ci.draw_line(a, b, col, width, aa), Rect2(a, Vector2.ZERO).expand(b).grow(2.0))
		return
	var v := PackedVector2Array()
	var c := PackedColorArray()
	_line_tris(a, b, col, width, aa, v, c)
	_geo(v, c, Rect2(a, Vector2.ZERO).expand(b).grow(width * 0.5 + FEATHER * 2.0 + 1.0))


func draw_multiline(pts: PackedVector2Array, col: Color, width := -1.0, aa := false) -> void:
	if pts.size() < 2 or pts.size() % 2 != 0:
		return
	if width < 0.0:
		_native(func(ci: CanvasItem): ci.draw_multiline(pts, col, width, aa), _bounds(pts, 2.0))
		return
	if ink != null and aa and InkLines.state == 1 and not _capturing:
		# (the ink shader builds each segment's quad and feathers from the points: one code vertex per corner here)
		var codes := ink.multiline_tris(pts, col, width)
		var wc := PackedColorArray()
		wc.resize(codes.size())
		wc.fill(Color.WHITE)
		_ink_used = true
		_geo(codes, wc, _bounds(pts, width * 0.5 + FEATHER * 2.0 + 1.0))
		return
	# (one op per run of segments that stays small, so the grid keeps them apart from what they do not touch)
	var v := PackedVector2Array()
	var c := PackedColorArray()
	var g := width * 0.5 + FEATHER * 2.0 + 1.0
	var r := Rect2()
	for i in range(0, pts.size(), 2):
		var sr := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(g)
		if not v.is_empty():
			var u := r.merge(sr)
			if u.size.x > CELL * 3.0 or u.size.y > CELL * 3.0:
				_geo(v, c, r)
				v = PackedVector2Array()
				c = PackedColorArray()
			else:
				sr = u
		r = sr
		_line_tris(pts[i], pts[i + 1], col, width, aa, v, c)
	_geo(v, c, r)


func draw_dashed_line(a: Vector2, b: Vector2, col: Color, width := -1.0, dash := 2.0, aligned := true, aa := false) -> void:
	if dash <= 0.0:
		return
	var length := (b - a).length()
	var step := dash * (b - a).normalized()
	if length < dash or step == Vector2.ZERO:
		draw_line(a, b, col, width, aa)
		return
	var steps := int(ceil(length / dash)) if aligned else int(floor(length / dash))
	if steps % 2 == 0:
		steps -= 1
	var off := a
	if aligned:
		off += (b - a).normalized() * (length - steps * dash) / 2.0
	var pts := PackedVector2Array()
	pts.resize(steps + 1)
	var i := 0
	while i < steps:
		pts[i] = a if i == 0 else off
		pts[i + 1] = b if (aligned and i == steps - 1) else (off + step)
		off += step * 2.0
		i += 2
	draw_multiline(pts, col, width, aa)


func draw_rect(rect: Rect2, col: Color, filled := true, width := -1.0, aa := false) -> void:
	var rc := rect.abs()
	if filled:
		_rect(rc, col, aa)
	elif width >= rc.size.x or width >= rc.size.y:
		_rect(rc.grow(0.5 * width), col, aa)
	else:
		draw_polyline(PackedVector2Array([rc.position, rc.position + Vector2(rc.size.x, 0), rc.end,
			rc.position + Vector2(0, rc.size.y), rc.position]), col, width, aa)


func draw_colored_polygon(pts: PackedVector2Array, col: Color, _uvs := PackedVector2Array(), _tex: Texture2D = null) -> void:
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var v := PackedVector2Array()
	v.resize(idx.size())
	for i in idx.size():
		v[i] = pts[idx[i]]
	var c := PackedColorArray()
	c.resize(v.size())
	c.fill(col)
	_geo(v, c, _bounds(pts, 1.0))


## A call the batch has no triangles for, drawn as itself (in order) at flush.
func _native(f: Callable, r: Rect2) -> void:
	_text("x%d" % _key.size(), r, [4, f])


# ---------------------------------------------------------- tessellation ---

static func _bounds(pts: PackedVector2Array, g: float) -> Rect2:
	var lo := pts[0]
	var hi := pts[0]
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo).grow(g)


static func _comp(w: float) -> float:
	if w > 0.0:
		if w <= FEATHER * 2.0 + CMP_EPS:
			return w * 0.5
		elif w <= FEATHER * 4.0 + CMP_EPS:
			return remap(w, FEATHER * 2.0, FEATHER * 4.0, w * 0.5, w - FEATHER * 0.5)
		return w - FEATHER * 0.5
	return w


## A triangle strip as triangles (v[i], v[i + 1], v[i + 2]), appended to ov / oc.
static func _strip(v: PackedVector2Array, c: PackedColorArray, ov: PackedVector2Array, oc: PackedColorArray) -> void:
	var n := v.size() - 2
	if n <= 0:
		return
	var b := ov.size()
	ov.resize(b + n * 3)
	oc.resize(b + n * 3)
	for i in n:
		var k := b + i * 3
		ov[k] = v[i]
		ov[k + 1] = v[i + 1]
		ov[k + 2] = v[i + 2]
		oc[k] = c[i]
		oc[k + 1] = c[i + 1]
		oc[k + 2] = c[i + 2]


## A quad (0, 1, 2, 3) as Godot draws a 4-point primitive: (0, 1, 2), (0, 2, 3).
static func _quad(ov: PackedVector2Array, oc: PackedColorArray, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	ov.append(p0)
	ov.append(p1)
	ov.append(p2)
	ov.append(p0)
	ov.append(p2)
	ov.append(p3)
	oc.append(c0)
	oc.append(c1)
	oc.append(c2)
	oc.append(c0)
	oc.append(c2)
	oc.append(c3)


## canvas_item_add_rect (filled; antialiased: shrunk by a quarter feather, and eight feather quads).
static func _rect_tris(rect: Rect2, col: Color, aa: bool, ov: PackedVector2Array, oc: PackedColorArray) -> void:
	var ra := rect.grow(-FEATHER * 0.25) if aa else rect
	var p := ra.position
	var e := ra.end
	_quad(ov, oc, p, Vector2(e.x, p.y), e, Vector2(p.x, e.y), col, col, col, col)
	if not aa:
		return
	var bs := FEATHER
	var sz := minf(ra.size.x, ra.size.y)
	if 0.0 <= sz and sz < 1.0:
		bs *= sz
	var down := Vector2(0.0, ra.size.y)
	var right := Vector2(ra.size.x, 0.0)
	var bl := p
	var br := p + down
	var el := p + right
	var er := p + ra.size
	var bd := Vector2(0.0, -1.0) * bs
	var bd2 := Vector2(-1.0, 0.0) * bs
	var t := Color(col, 0.0)
	_quad(ov, oc, bl, bl + bd, el + bd, el, col, t, t, col)
	_quad(ov, oc, br, br - bd, er - bd, er, col, t, t, col)
	_quad(ov, oc, bl, bl + bd2, br + bd2, br, col, t, t, col)
	_quad(ov, oc, el, el - bd2, er - bd2, er, col, t, t, col)
	_quad(ov, oc, bl, bl + bd2, bl + bd + bd2, bl + bd, col, t, t, t)
	_quad(ov, oc, br, br + bd2, br - bd + bd2, br - bd, col, t, t, t)
	_quad(ov, oc, el, el - bd2, el + bd - bd2, el + bd, col, t, t, t)
	_quad(ov, oc, er, er - bd2, er - bd - bd2, er - bd, col, t, t, t)


func _rect(rect: Rect2, col: Color, aa: bool) -> void:
	var v := PackedVector2Array()
	var c := PackedColorArray()
	_rect_tris(rect, col, aa, v, c)
	_geo(v, c, rect.grow(FEATHER + 1.0))


## canvas_item_add_line (width >= 0).
static func _line_tris(from: Vector2, to: Vector2, col: Color, width: float, aa: bool, ov: PackedVector2Array, oc: PackedColorArray) -> void:
	var diff := from - to
	var dir := diff.orthogonal().normalized()
	if aa:
		width = _comp(width)
	var t := dir * width * 0.5
	var bl := from + t
	var br := from - t
	var el := to + t
	var er := to - t
	_quad(ov, oc, bl, br, er, el, col, col, col, col)
	if not aa:
		return
	var bs := FEATHER
	if 0.0 <= width and width < 1.0:
		bs *= width
	var dir2 := diff.normalized()
	var bd := dir * bs
	var bd2 := dir2 * bs
	var tc := Color(col, 0.0)
	_quad(ov, oc, bl, bl + bd, el + bd, el, col, tc, tc, col)
	_quad(ov, oc, br, br - bd, er - bd, er, col, tc, tc, col)
	_quad(ov, oc, bl, bl + bd2, br + bd2, br, col, tc, tc, col)
	_quad(ov, oc, el, el - bd2, er - bd2, er, col, tc, tc, col)
	_quad(ov, oc, bl, bl + bd2, bl + bd + bd2, bl + bd, col, tc, tc, tc)
	_quad(ov, oc, br, br + bd2, br - bd + bd2, br - bd, col, tc, tc, tc)
	_quad(ov, oc, el, el - bd2, el + bd - bd2, el + bd, col, tc, tc, tc)
	_quad(ov, oc, er, er - bd2, er - bd - bd2, er - bd, col, tc, tc, tc)


static func _seg_dir(pts: PackedVector2Array, i: int, prev: Vector2) -> Vector2:
	if i == pts.size() - 1:
		return prev
	var d := (pts[i + 1] - pts[i]).normalized()
	if d.is_zero_approx():
		return prev
	return d


static func _clamped(sd: Vector2, pd: Vector2) -> Vector2:
	var length := 1.0
	var bis := (pd * sd.length() - sd * pd.length()).normalized()
	var ang := atan2(bis.cross(pd), bis.dot(pd))
	var sa := sin(ang)
	if not is_zero_approx(sa) and not sd.is_equal_approx(pd):
		length = clampf(1.0 / sa, -3.0, 3.0)
	else:
		bis = sd.orthogonal()
	if bis.is_zero_approx():
		bis = sd.orthogonal()
	return bis * length


## canvas_item_add_polyline (width >= 0, one colour): the middle strip, then (antialiased) the left and right
## feather strips, as triangles appended to ov / oc.
static func _polyline_tris(pts: PackedVector2Array, col: Color, width: float, aa: bool, ov: PackedVector2Array, oc: PackedColorArray) -> void:
	var n := pts.size()
	if aa:
		width = _comp(width)
	var loop := pts[0].is_equal_approx(pts[n - 1])
	var first_dir := Vector2.ZERO
	for i in range(1, n):
		first_dir = (pts[i] - pts[i - 1]).normalized()
		if not first_dir.is_zero_approx():
			break
	var last_dir := Vector2.ZERO
	for i in range(n - 1, 0, -1):
		last_dir = (pts[i] - pts[i - 1]).normalized()
		if not last_dir.is_zero_approx():
			break
	var cap := aa and not loop
	var m := PackedVector2Array()
	var mc := PackedColorArray()
	m.resize(n * 2 + (4 if cap else 0))
	mc.resize(m.size())
	var lf := PackedVector2Array()
	var lc := PackedColorArray()
	var rt := PackedVector2Array()
	var rc := PackedColorArray()
	var bs := FEATHER
	if width < 1.0:
		bs *= width
	var c2 := Color(col, 0.0)
	if aa:
		lf.resize(n * 2 + (0 if loop else 5))
		lc.resize(lf.size())
		rt.resize(lf.size())
		rc.resize(lf.size())
	var prev := Vector2.ZERO
	var hw := width * 0.5
	for i in n:
		var first := i == 0
		var last := i == n - 1
		var sd := _seg_dir(pts, i, prev)
		if first and loop:
			prev = last_dir
		elif last and loop:
			prev = first_dir
		var beo: Vector2
		if first and not loop:
			beo = first_dir.orthogonal()
		elif last and not loop:
			beo = last_dir.orthogonal()
		else:
			beo = _clamped(sd, prev)
		var eo := beo * hw
		var pos := pts[i]
		if not aa:
			m[i * 2] = pos + eo
			m[i * 2 + 1] = pos - eo
			mc[i * 2] = col
			mc[i * 2 + 1] = col
			prev = sd
			continue
		var bo := beo * bs
		var j := i * 2 + (0 if loop else 2)
		m[j] = pos + eo
		m[j + 1] = pos - eo
		mc[j] = col
		mc[j + 1] = col
		lf[j] = pos + eo
		lf[j + 1] = pos + eo + bo
		rt[j] = pos - eo
		rt[j + 1] = pos - eo - bo
		lc[j] = col
		lc[j + 1] = c2
		rc[j] = col
		rc[j + 1] = c2
		if first and not loop:
			var bb := -sd * bs
			m[0] = pos + eo + bb
			m[1] = pos - eo + bb
			mc[0] = c2
			mc[1] = c2
			lf[0] = pos + eo + bb
			lf[1] = pos + eo + bb + bo
			lc[0] = c2
			lc[1] = c2
			rt[0] = pos - eo + bb
			rt[1] = pos - eo + bb - bo
			rc[0] = c2
			rc[1] = c2
		if last and not loop:
			var eb := prev * bs
			var ei := n * 2 + 2
			m[ei] = pos + eo + eb
			m[ei + 1] = pos - eo + eb
			mc[ei] = c2
			mc[ei + 1] = c2
			lf[ei] = pos + eo
			lf[ei + 1] = pos + eo + eb + bo
			lf[ei + 2] = pos + eo + eb
			lc[ei] = col
			lc[ei + 1] = c2
			lc[ei + 2] = c2
			rt[ei] = pos - eo
			rt[ei + 1] = pos - eo + eb - bo
			rt[ei + 2] = pos - eo + eb
			rc[ei] = col
			rc[ei + 1] = c2
			rc[ei + 2] = c2
		prev = sd
	_strip(m, mc, ov, oc)
	if aa:
		_strip(lf, lc, ov, oc)
		_strip(rt, rc, ov, oc)
