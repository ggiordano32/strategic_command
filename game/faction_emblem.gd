extends RefCounted
## Faction emblems for the West pack, drawn in code (no textures): a square
## flag-like badge per faction key, multi-colour, clean from 16 px (swatches)
## to 128 px (the picker, banners). View only: the mapping is keyed by the
## FACTIONS row's "key", so nothing in campaign/ changes; a faction without an
## emblem (Rome's pack) keeps its plain colour swatch (Kit.faction_mark) and
## its colour-only banner. draw(ci, key, rect) draws it on any CanvasItem,
## mark(key, px) makes a Control. tests/emblem_gallery.gd renders the sheet.

const KEYS: Array[String] = ["new_spain", "tierra_firme", "england", "france", "dutch", "brethren", "itza", "miskito"]
const INK := Color(0.07, 0.06, 0.06)

static var _ci: CanvasItem
static var _c := Vector2.ZERO
static var _s := 1.0


static func has(key: String) -> bool:
	return KEYS.has(key)


## A Control of px x px showing the emblem (the swatch's replacement).
static func mark(key: String, px: float, col: Color = Color(0, 0, 0, 0)) -> Control:
	var m := Mark.new()
	m.key = key
	m.col = col
	m.custom_minimum_size = Vector2(px, px)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


class Mark extends Control:
	var key := ""
	var col := Color(0, 0, 0, 0)  # the faction colour, a frame round the emblem (from 18 px)
	func _draw() -> void:
		var side := minf(size.x, size.y)
		var r := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		if col.a > 0.0 and side >= 18.0:
			draw_rect(r, col)
			r = r.grow(-2.0)
		(load("res://game/faction_emblem.gd") as Script).call("draw", self, key, r)


## Draw the emblem filling the square centred in rect (a thin dark edge
## included). Does nothing for an unknown key.
static func draw(ci: CanvasItem, key: String, rect: Rect2) -> void:
	if not has(key):
		return
	var side := minf(rect.size.x, rect.size.y)
	_ci = ci
	_c = rect.get_center()
	_s = side * 0.5 - (0.5 if side < 40.0 else 1.0)
	var simple := side < 22.0  # fewer details when tiny
	match key:
		"new_spain": _saltire(Color("f1e2b4"), Color("b3262b"), false)
		"tierra_firme": _saltire(Color("dfe5ea"), Color("b3262b"), true)
		"england": _england()
		"france": _france(simple)
		"dutch": _dutch()
		"brethren": _jolly(simple)
		"itza": _itza(simple)
		"miskito": _miskito(simple)
	_ci = null


# ---------------------------------------------------------------- pen ---

static func _p(x: float, y: float) -> Vector2:
	return _c + Vector2(x, y) * _s


static func _pts(xy: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		out.append(_p(float(xy[i]), float(xy[i + 1])))
	return out


## Filled polygon (convex or simple); fill.a == 0 with edge = true draws the
## dark outline only.
static func _poly(xy: Array, fill: Color, edge: bool = false, lw: float = 0.08) -> void:
	var pts := _pts(xy)
	if fill.a > 0.0:
		var tri := Geometry2D.triangulate_polygon(pts)
		if tri.is_empty():
			tri = Geometry2D.triangulate_polygon(_rev(pts))
			pts = _rev(pts)
		if not tri.is_empty():
			_ci.draw_colored_polygon(pts, fill)
	if edge:
		var o := pts.duplicate()
		o.append(pts[0])
		_ci.draw_polyline(o, INK, maxf(lw * _s, 1.0), true)


static func _rev(p: PackedVector2Array) -> PackedVector2Array:
	var o := p.duplicate()
	o.reverse()
	return o


static func _rect(x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	_ci.draw_rect(Rect2(_p(x0, y0), Vector2(x1 - x0, y1 - y0) * _s), col)


static func _disc(x: float, y: float, r: float, col: Color) -> void:
	_ci.draw_circle(_p(x, y), r * _s, col)


static func _line(ax: float, ay: float, bx: float, by: float, w: float, col: Color) -> void:
	_ci.draw_line(_p(ax, ay), _p(bx, by), col, maxf(w * _s, 1.0), true)


## An ellipse as a polygon (rotation rot).
static func _ell(x: float, y: float, rx: float, ry: float, col: Color, rot: float = 0.0, edge: bool = false) -> void:
	var xy := []
	for i in 20:
		var a := TAU * i / 20.0
		var v := Vector2(cos(a) * rx, sin(a) * ry).rotated(rot)
		xy.append(x + v.x)
		xy.append(y + v.y)
	_poly(xy, col, edge, 0.06)


# ------------------------------------------------------------ emblems ---

## Cross of Burgundy: a ragged saltire (stubs of the cut branches) on a pale
## field; the Spanish Main variant adds a gold castle on a silver field.
static func _saltire(field: Color, red: Color, castle: bool) -> void:
	_rect(-1, -1, 1, 1, field)
	var w := 0.27
	for sgn in [1.0, -1.0]:
		var d := 1.0 if sgn > 0 else -1.0
		# diagonal band clipped to the square
		if d > 0:
			_poly([-1, -1, -1 + w, -1, 1, 1 - w, 1, 1, 1 - w, 1, -1, -1 + w], red)
		else:
			_poly([1, -1, 1, -1 + w, -1 + w, 1, -1, 1, -1, 1 - w, 1 - w, -1], red)
		# knots: short stubs across the branch
		for t in [-0.4, 0.3]:
			var cx: float = t
			var cy: float = t * d
			var n := Vector2(-d, 1.0).normalized()
			var a := Vector2(cx, cy) + n * 0.22
			var b := Vector2(cx, cy) - n * 0.22
			_line(a.x, a.y, a.x + 0.07 * d, a.y + 0.1, 0.1, red)
			_line(b.x, b.y, b.x - 0.07 * d, b.y - 0.1, 0.1, red)
	if castle:
		var gold := Color("e3b53a")
		_poly([-0.46, 0.5, -0.46, -0.1, -0.32, -0.1, -0.32, -0.3, -0.18, -0.3, -0.18, -0.1, -0.06, -0.1, -0.06, -0.3, 0.06, -0.3, 0.06, -0.1,
			0.18, -0.1, 0.18, -0.3, 0.32, -0.3, 0.32, -0.1, 0.46, -0.1, 0.46, 0.5], gold, true, 0.07)
		_poly([-0.12, 0.5, -0.12, 0.2, 0.0, 0.1, 0.12, 0.2, 0.12, 0.5], INK)
	_ci.draw_rect(Rect2(_p(-1, -1), Vector2(2, 2) * _s), INK, false, maxf(0.08 * _s, 1.0))


static func _england() -> void:
	_rect(-1, -1, 1, 1, Color("f6f2ea"))
	_rect(-0.2, -1, 0.2, 1, Color("c8202c"))
	_rect(-1, -0.2, 1, 0.2, Color("c8202c"))
	_ci.draw_rect(Rect2(_p(-1, -1), Vector2(2, 2) * _s), INK, false, maxf(0.08 * _s, 1.0))


static func _fleur(x: float, y: float, k: float, gold: Color, simple: bool) -> void:
	var e := not simple
	# centre petal
	_poly(_sc([0.0, -0.62, 0.2, -0.2, 0.14, 0.25, -0.14, 0.25, -0.2, -0.2], x, y, k), gold, e, 0.06)
	# side petals curling out
	for sg in [1.0, -1.0]:
		_poly(_sc([sg * 0.12, 0.1, sg * 0.38, -0.18, sg * 0.68, -0.16, sg * 0.62, 0.14, sg * 0.4, 0.28, sg * 0.15, 0.3], x, y, k), gold, e, 0.06)
	# band and foot
	_poly(_sc([-0.42, 0.26, 0.42, 0.26, 0.42, 0.4, -0.42, 0.4], x, y, k), gold, e, 0.06)
	_poly(_sc([-0.12, 0.4, 0.12, 0.4, 0.26, 0.68, 0.0, 0.56, -0.26, 0.68], x, y, k), gold, e, 0.06)


## Flat xy scaled by k and moved to (x, y).
static func _sc(xy: Array, x: float, y: float, k: float) -> Array:
	var o := []
	for i in range(0, xy.size(), 2):
		o.append(x + float(xy[i]) * k)
		o.append(y + float(xy[i + 1]) * k)
	return o


static func _france(simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("f4f1e6"))
	var gold := Color("d9a21b")
	_fleur(-0.5, -0.38, 0.62, gold, simple)
	_fleur(0.5, -0.38, 0.62, gold, simple)
	_fleur(0.0, 0.42, 0.62, gold, simple)
	_ci.draw_rect(Rect2(_p(-1, -1), Vector2(2, 2) * _s), INK, false, maxf(0.08 * _s, 1.0))


static func _dutch() -> void:
	_rect(-1, -1, 1, -0.34, Color("e8731a"))
	_rect(-1, -0.34, 1, 0.34, Color("f6f2ea"))
	_rect(-1, 0.34, 1, 1, Color("21468b"))
	_ci.draw_rect(Rect2(_p(-1, -1), Vector2(2, 2) * _s), INK, false, maxf(0.08 * _s, 1.0))


## Jolly Roger: skull over crossed cutlasses, in a tricorne, a red heart to
## one side; white on black.
static func _jolly(simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("14141a"))
	var bone := Color("f2eee2")
	# crossed cutlasses / bones behind the skull
	_line(-0.78, -0.42, 0.78, 0.78, 0.17, bone)
	_line(0.78, -0.42, -0.78, 0.78, 0.17, bone)
	for p in [[-0.78, -0.42], [0.78, -0.42], [-0.78, 0.78], [0.78, 0.78]]:
		_disc(p[0], p[1], 0.14, bone)
	# skull: cranium, jaw
	_disc(0.0, -0.02, 0.5, bone)
	_poly([-0.3, 0.3, 0.3, 0.3, 0.26, 0.62, -0.26, 0.62], bone)
	_ell(-0.2, -0.02, 0.15, 0.17, Color("14141a"), 0.0)
	_ell(0.2, -0.02, 0.15, 0.17, Color("14141a"), 0.0)
	_poly([0.0, 0.14, 0.07, 0.3, -0.07, 0.3], Color("14141a"))
	if not simple:
		for t in [-0.14, 0.0, 0.14]:
			_line(t, 0.44, t, 0.62, 0.05, Color("14141a"))
	# tricorne: a dark hat with a pale rim and a red feather's worth of cockade
	var rim := Color("d9a21b")
	_poly([-0.62, -0.38, -0.3, -0.5, -0.12, -0.9, 0.12, -0.9, 0.3, -0.5, 0.62, -0.38, 0.3, -0.3, -0.3, -0.3], Color("2b2b36"), false)
	_line(-0.62, -0.38, -0.3, -0.3, 0.07, rim)
	_line(-0.3, -0.3, 0.3, -0.3, 0.07, rim)
	_line(0.3, -0.3, 0.62, -0.38, 0.07, rim)
	_line(-0.62, -0.38, -0.3, -0.5, 0.06, rim)
	_line(0.62, -0.38, 0.3, -0.5, 0.06, rim)
	_disc(0.0, -0.6, 0.08, Color("c8202c"))


## Itza: a gold sun-and-jaguar disc (rosette spots, rays) over a stepped band,
## on jade. An original stylisation, not a copy of any Maya glyph.
static func _itza(simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("1f6b57"))
	var gold := Color("e3b53a")
	var dark := Color("123d33")
	# stepped band at the foot (a stair-fret)
	_poly([-1, 1, -1, 0.62, -0.6, 0.62, -0.6, 0.78, -0.2, 0.78, -0.2, 0.62, 0.2, 0.62, 0.2, 0.78, 0.6, 0.78, 0.6, 0.62, 1, 0.62, 1, 1], dark)
	# rays
	var n := 12
	for i in n:
		var a := TAU * i / n - PI / 2
		var u := Vector2(cos(a), sin(a))
		var v := Vector2(-u.y, u.x)
		var p0 := u * 0.52 + Vector2(0, -0.1)
		var tip := u * 0.9 + Vector2(0, -0.1)
		var l := p0 + v * 0.11
		var r := p0 - v * 0.11
		_poly([l.x, l.y, tip.x, tip.y, r.x, r.y], gold)
	_disc(0.0, -0.1, 0.5, gold)
	_disc(0.0, -0.1, 0.5, gold)
	# jaguar rosettes: rings of dark with a gold heart
	for q in [[-0.2, -0.28], [0.22, -0.2], [0.0, 0.08], [-0.26, 0.04], [0.3, 0.1]]:
		_disc(q[0], q[1], 0.11 if not simple else 0.13, dark)
		if not simple:
			_disc(q[0], q[1], 0.045, gold)
	_ci.draw_rect(Rect2(_p(-1, -1), Vector2(2, 2) * _s), INK, false, maxf(0.08 * _s, 1.0))


## Miskito: a green sea turtle (top view) on the lagoon blue, with a feather
## tuft at the head.
static func _miskito(simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("1e5f8c"))
	var shell := Color("5e9a3c")
	var skin := Color("a8c46a")
	# flippers
	_ell(-0.62, -0.32, 0.4, 0.15, skin, -0.55, true)
	_ell(0.62, -0.32, 0.4, 0.15, skin, 0.55, true)
	_ell(-0.5, 0.52, 0.3, 0.13, skin, 0.7, true)
	_ell(0.5, 0.52, 0.3, 0.13, skin, -0.7, true)
	# tail and head
	_poly([-0.07, 0.62, 0.07, 0.62, 0.0, 0.92], skin, true, 0.06)
	_ell(0.0, -0.64, 0.17, 0.2, skin, 0.0, true)
	if not simple:
		_disc(-0.07, -0.68, 0.035, INK)
		_disc(0.07, -0.68, 0.035, INK)
	# shell and scutes
	_ell(0.0, 0.0, 0.48, 0.62, shell, 0.0, true)
	if not simple:
		var dk := Color("2f5f1f")
		_line(-0.2, -0.3, 0.2, -0.3, 0.05, dk)
		_line(-0.34, 0.05, 0.34, 0.05, 0.05, dk)
		_line(-0.2, 0.4, 0.2, 0.4, 0.05, dk)
		_line(0.0, -0.3, 0.0, 0.4, 0.05, dk)
		_line(-0.2, -0.3, -0.34, 0.05, 0.05, dk)
		_line(0.2, -0.3, 0.34, 0.05, 0.05, dk)
		_line(-0.34, 0.05, -0.2, 0.4, 0.05, dk)
		_line(0.34, 0.05, 0.2, 0.4, 0.05, dk)
	# feathers in the corner
	for i in 3:
		var a := -0.35 + 0.35 * i
		var base := Vector2(0.78, 0.86)
		var tip := base + Vector2(sin(a), -cos(a)) * 0.55 + Vector2(-0.15, 0.0)
		_line(base.x, base.y, tip.x, tip.y, 0.1, [Color("c8202c"), Color("f6f2ea"), Color("e3b53a")][i])
	_ci.draw_rect(Rect2(_p(-1, -1), Vector2(2, 2) * _s), INK, false, maxf(0.08 * _s, 1.0))
