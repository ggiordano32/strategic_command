extends Node2D
## The diorama look's board (view only): the battlefield is a sculpted tabletop board, a bevelled edge round
## the field with a soft shadow on a wooden table that fills the screen beyond it. Under the ground
## (z -3). Off in the painterly look and with --no-board.

const MARGIN := 900.0      # metres of table beyond the field
const BEVEL := 6.0         # metres, the board edge's width
const LIGHT_EDGE := Color(0.80, 0.70, 0.52)
const DARK_EDGE := Color(0.34, 0.25, 0.16)
const TABLE := Color(0.31, 0.215, 0.14)

var fw := 0.0
var fh := 0.0
var k := 10.0


func setup(sim, px_per_m: float) -> void:
	k = px_per_m
	fw = sim.field_w / 1024.0 * k
	fh = sim.field_h / 1024.0 * k
	z_index = -3
	queue_redraw()


func _draw() -> void:
	var m := MARGIN * k
	var bv := BEVEL * k
	_hrect(-m, -bv, TABLE)
	_hrect(fh + bv, fh + m, TABLE)
	_hrect(-bv, fh + bv, TABLE)
	# Table planks (25 m wide, running along x), each a little different, with a seam and grain strokes.
	var pm := minf(m, 450.0 * k)   # plank detail only 450 m out (the table beyond is plain)
	var py := -pm
	var pi := 0
	_gl.clear()
	_gc.clear()
	while py < fh + pm:
		var ph := (22.0 + float((pi * 53) % 11)) * k
		var tone := float((pi * 7919) % 97) / 97.0
		_hrect(py, py + ph, Color(0.42, 0.29, 0.18, 0.12 + 0.2 * tone) if tone > 0.45 else Color(0, 0, 0, 0.14 * (1.0 - tone)))
		_hline(-pm, fw + pm, py, Color(0, 0, 0, 0.5))
		var gy := py + 3.0 * k
		var gi := 0
		while gy < py + ph - 2.0 * k:
			var gh := float(((pi * 31 + gi) * 7919) % 97) / 97.0
			var x0 := -pm + gh * 300.0 * k
			_hline(x0, x0 + (160.0 + gh * 400.0) * k, gy, Color(0, 0, 0, 0.06 + 0.07 * gh))
			gy += (2.2 + gh * 4.0) * k
			gi += 1
		py += ph
		pi += 1
	draw_multiline_colors(_gl, _gc, maxf(k * 0.18, 1.5))
	var b := BEVEL * k
	# Soft shadow of the board on the table: a falloff of expanding layers, offset to the south-east.
	for s in 28:
		var d := b * (0.2 + 0.25 * s)
		var sr := Rect2(-b + b * 0.5 - d, -b + b * 0.8 - d, fw + 2.0 * b + 2.0 * d, fh + 2.0 * b + 2.0 * d)
		var sc := Color(0, 0, 0, 0.022)
		# a ring: the part of the layer outside the board (the board and ground cover the rest)
		draw_rect(Rect2(sr.position.x, sr.position.y, sr.size.x, -b - sr.position.y), sc)
		draw_rect(Rect2(sr.position.x, fh + b, sr.size.x, sr.end.y - fh - b), sc)
		draw_rect(Rect2(sr.position.x, -b, -b - sr.position.x, fh + 2.0 * b), sc)
		draw_rect(Rect2(fw + b, -b, sr.end.x - fw - b, fh + 2.0 * b), sc)
	# The bevel in two bands lit from the north-west: the outer face (a gradient from the table edge up) and
	# a thin flat lip along the field, plus a pale rim catching the light on the north and west.
	var o := Rect2(-b, -b, fw + 2.0 * b, fh + 2.0 * b)
	var lip := b * 0.16
	var tl := o.position
	var ntr := Vector2(o.end.x, o.position.y)
	var br := o.end
	var bl := Vector2(o.position.x, o.end.y)
	var itl := Vector2(-lip, -lip)
	var itr := Vector2(fw + lip, -lip)
	var ibr := Vector2(fw + lip, fh + lip)
	var ibl := Vector2(-lip, fh + lip)
	var cn := LIGHT_EDGE.lerp(DARK_EDGE, 0.2)
	var cw := LIGHT_EDGE
	var cs := DARK_EDGE.lerp(LIGHT_EDGE, 0.25)
	var ce := DARK_EDGE
	_face(tl, ntr, itr, itl, cn)
	_face(tl, itl, ibl, bl, cw)
	_face(bl, ibl, ibr, br, cs)
	_face(ntr, br, ibr, itr, ce)
	# The flat lip: a paler, even strip.
	var lc := LIGHT_EDGE.lightened(0.12)
	draw_rect(Rect2(-lip, -lip, fw + 2.0 * lip, lip), lc)
	draw_rect(Rect2(-lip, -lip, lip, fh + 2.0 * lip), lc)
	draw_rect(Rect2(-lip, fh, fw + 2.0 * lip, lip), lc.darkened(0.25))
	draw_rect(Rect2(fw, -lip, lip, fh + 2.0 * lip), lc.darkened(0.35))
	# Grain along the bevel faces.
	for gi2 in 8:
		var fr := (float(gi2) + 0.5) / 8.0
		var gcol := Color(0.2, 0.12, 0.05, 0.16)
		var inset := b * (0.12 + 0.75 * fr)
		draw_line(Vector2(-b + inset, -b + inset), Vector2(fw + b - inset, -b + inset), gcol, maxf(k * 0.07, 1.0))
		draw_line(Vector2(-b + inset, -b + inset), Vector2(-b + inset, fh + b - inset), gcol, maxf(k * 0.07, 1.0))
		draw_line(Vector2(-b + inset, fh + b - inset), Vector2(fw + b - inset, fh + b - inset), gcol, maxf(k * 0.07, 1.0))
		draw_line(Vector2(fw + b - inset, -b + inset), Vector2(fw + b - inset, fh + b - inset), gcol, maxf(k * 0.07, 1.0))
	# Mitre lines at the corners, the pale rim, and the dark joint along the field.
	for pr in [[tl, itl], [ntr, itr], [br, ibr], [bl, ibl]]:
		draw_line(pr[0], pr[1], Color(0.1, 0.06, 0.03, 0.4), maxf(k * 0.1, 1.0))
	draw_polyline(PackedVector2Array([bl, tl, ntr]), LIGHT_EDGE.lightened(0.35), maxf(k * 0.22, 1.5))
	draw_polyline(PackedVector2Array([ntr, br, bl]), Color(0.05, 0.03, 0.02, 0.65), maxf(k * 0.2, 1.0))
	draw_rect(Rect2(Vector2(-lip, -lip), Vector2(fw + 2.0 * lip, fh + 2.0 * lip)), Color(0.05, 0.03, 0.02, 0.55), false, maxf(k * 0.2, 1.0))


## A bevel face: a quad from its outer edge (a, b: the table side) to its inner edge (c, d), the outer
## edge a little darker, the inner edge as given (so the face reads as a rounded slope).
func _face(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	var dk := col.darkened(0.3)
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([dk, dk, col.lightened(0.05), col.lightened(0.05)]), PackedVector2Array())


## A full-width band y0..y1 of the table, leaving out the board's own span (it is under the board).
func _hrect(y0: float, y1: float, col: Color) -> void:
	var m := MARGIN * k
	var b := BEVEL * k
	if y1 <= y0:
		return
	var lo := maxf(y0, -b)
	var hi := minf(y1, fh + b)
	if hi > lo:
		draw_rect(Rect2(-m, lo, m - b, hi - lo), col)
		draw_rect(Rect2(fw + b, lo, m - b, hi - lo), col)
	if y0 < -b:
		draw_rect(Rect2(-m, y0, fw + 2.0 * m, minf(y1, -b) - y0), col)
	if y1 > fh + b:
		var t := maxf(y0, fh + b)
		draw_rect(Rect2(-m, t, fw + 2.0 * m, y1 - t), col)


var _gl := PackedVector2Array()
var _gc := PackedColorArray()


## A table line (batched into one multiline call), leaving out the board's own span.
func _hline(x0: float, x1: float, y: float, col: Color) -> void:
	var b := BEVEL * k
	var segs: Array = []
	if y > -b and y < fh + b:
		if x0 < -b:
			segs.append([x0, minf(x1, -b)])
		if x1 > fw + b:
			segs.append([maxf(x0, fw + b), x1])
	else:
		segs.append([x0, x1])
	for sg in segs:
		_gl.append(Vector2(sg[0], y))
		_gl.append(Vector2(sg[1], y))
		_gc.append(col)
