extends RefCounted
## Faction emblems for both packs (the West's and Rome's eight), drawn in code (no textures): a square
## flag-like badge per faction key, multi-colour, clean from 16 px (swatches)
## to 128 px (the picker, banners). View only: the mapping is keyed by the
## FACTIONS row's "key", so nothing in campaign/ changes; a faction without an
## emblem keeps its plain colour swatch (Kit.faction_mark) and its colour-only banner. draw(ci, key, rect) draws it on any CanvasItem,
## mark(key, px) makes a Control. tests/emblem_gallery.gd renders the sheet.

const KEYS: Array[String] = ["new_spain", "tierra_firme", "england", "france", "dutch", "brethren", "itza", "miskito",
		"rome", "carthage", "macedon", "epirus", "greeks", "syracuse", "iberians", "gauls"]
const INK := Color(0.07, 0.06, 0.06)

static var _ci   # a CanvasItem, or anything with its drawing methods (the overworld overlay's OvBatch)
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
static func draw(ci, key: String, rect: Rect2) -> void:
	if not has(key):
		return
	var side := minf(rect.size.x, rect.size.y)
	_ci = ci
	_c = rect.get_center()
	_s = side * 0.5 - (0.5 if side < 40.0 else 1.0)
	var simple := side < 22.0  # fewer details when tiny
	_re = not simple
	match key:
		"new_spain": _saltire(Color("f1e2b4"), Color("b3262b"), false)
		"tierra_firme": _saltire(Color("dfe5ea"), Color("b3262b"), true)
		"england": _england()
		"france": _france(simple)
		"dutch": _dutch()
		"brethren": _jolly(simple)
		"itza": _itza(simple)
		"miskito": _miskito(simple)
		"rome": _rome(simple)
		"carthage": _carthage(simple)
		"macedon": _macedon(simple)
		"epirus": _epirus(simple)
		"greeks": _greeks(simple)
		"syracuse": _syracuse(simple)
		"iberians": _iberians(simple)
		"gauls": _gauls(simple)
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

# ----------------------------------------------------------- Rome pack ---
# Motifs follow the painted crests (assets/ui/crests/rome): Rome the eagle, Carthage the elephant under a palm,
# Macedon the Vergina sun on cream, Epirus the eagle over the Molossian hound, the Greek League a Corinthian helmet,
# Syracuse the dolphin ring round a ship, the Iberians the falcata and round shield, the Gauls the boar under a carnyx.

static var _re := true   # outlines on the Rome pack's shapes (off below 22 px: the frame is enough)
const GOLD := Color("e3b53a")
const CREAM := Color("f6ecd2")


## The spread eagle (head left, wings up, tail down), centred at (x, y), scaled k.
static func _eagle(x: float, y: float, k: float, col: Color, e: bool) -> void:
	_poly(_sc([-0.14, -0.4, 0.14, -0.4, 0.2, 0.1, 0.12, 0.5, 0.24, 0.85, 0.0, 0.72, -0.24, 0.85, -0.12, 0.5, -0.2, 0.1], x, y, k), col, e, 0.07)
	for sg in [1.0, -1.0]:
		_poly(_sc([sg * 0.1, -0.45, sg * 0.5, -0.92, sg * 0.99, -0.78, sg * 0.97, -0.46, sg * 0.84, -0.5, sg * 0.9, -0.18, sg * 0.72, -0.27,
			sg * 0.72, 0.06, sg * 0.55, -0.05, sg * 0.5, 0.24, sg * 0.32, 0.05, sg * 0.14, 0.2], x, y, k), col, e, 0.07)
	_disc2(x, y - 0.5 * k, 0.16 * k, col, e)
	_poly(_sc([-0.1, -0.56, -0.32, -0.46, -0.1, -0.38], x, y, k), col, e, 0.06)


static func _disc2(x: float, y: float, r: float, col: Color, e: bool) -> void:
	if e:
		_disc(x, y, r + 0.03, INK)
	_disc(x, y, r, col)


static func _rome(simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("c8402f"))
	_eagle(0.0, 0.02, 0.95, GOLD, _re)
	if not simple:
		_disc(-0.06, -0.52, 0.035, INK)
	_frame()


static func _frame() -> void:
	_ci.draw_rect(Rect2(_p(-1, -1), Vector2(2, 2) * _s), INK, false, maxf(0.08 * _s, 1.0))


## Carthage: a gold elephant (side view, facing left) with a palm on its back, on purple.
static func _carthage(simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("7a4fc4"))
	var g := GOLD
	# palm
	if not simple:
		_line(0.15, -0.28, 0.15, -0.64, 0.1, g)
	for t in [[-0.3, -0.5], [-0.2, -0.86], [0.15, -0.96], [0.55, -0.86], [0.68, -0.5]]:
		_line(0.15, -0.66, t[0], t[1], 0.1, g)
	# legs, body, head, ear, trunk, tusk
	for lx in [-0.38, -0.12, 0.3, 0.56]:
		_rect(lx - 0.1, 0.4, lx + 0.1, 0.9, g)
	_ell(0.12, 0.08, 0.58, 0.4, g, 0.0, _re)
	_ell(-0.5, 0.04, 0.3, 0.32, g, 0.0, _re)
	_poly([-0.72, 0.1, -0.9, 0.4, -0.86, 0.8, -0.7, 0.78, -0.7, 0.42, -0.56, 0.2], g, _re, 0.06)
	_line(-0.62, 0.3, -0.98, 0.52, 0.09, CREAM)
	if not simple:
		_ell(-0.34, 0.1, 0.12, 0.22, Color("b8862a"), 0.0)
		_disc(-0.6, -0.04, 0.04, INK)
	_frame()


## Macedon: the Vergina sun (16 rays, 8 long and 8 short) on cream.
static func _macedon(simple: bool) -> void:
	_rect(-1, -1, 1, 1, CREAM)
	var gold := Color("e0a21c")
	var brown := Color("6a4510")
	for i in 16:
		var a := TAU * i / 16.0 - PI / 2
		var u := Vector2(cos(a), sin(a))
		var v := Vector2(-u.y, u.x)
		var l := 0.95 if i % 2 == 0 else 0.68
		var w := 0.13 if i % 2 == 0 else 0.1
		var b := u * 0.3
		var t := u * l
		_poly([b.x + v.x * w, b.y + v.y * w, t.x, t.y, b.x - v.x * w, b.y - v.y * w], gold, not simple, 0.05)
	_disc(0.0, 0.0, 0.4, brown)
	_disc(0.0, 0.0, 0.33, gold)
	if not simple:
		_disc(0.0, 0.0, 0.17, brown)
		_disc(0.0, 0.0, 0.1, gold)
	_frame()


## Epirus: the eagle over the Molossian hound, cream on orange.
static func _epirus(_simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("e07a2a"))
	_eagle(0.0, -0.4, 0.58, CREAM, _re)
	var c := CREAM
	for lx in [-0.5, -0.3, 0.3, 0.5]:
		_rect(lx - 0.055, 0.5, lx + 0.055, 0.88, c)
	_ell(0.02, 0.45, 0.56, 0.19, c, 0.0, _re)
	_ell(-0.58, 0.28, 0.2, 0.15, c, 0.0, _re)
	_poly([-0.7, 0.28, -0.92, 0.36, -0.88, 0.46, -0.66, 0.42], c, _re, 0.05)
	_poly([-0.55, 0.12, -0.46, 0.0, -0.4, 0.2], c, _re, 0.05)
	_line(0.52, 0.4, 0.78, 0.08, 0.09, c)
	_line(0.78, 0.08, 0.7, -0.06, 0.09, c)
	_frame()


## The Greek League: a Corinthian helmet in profile (facing left), bronze on blue.
static func _greeks(simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("3f7fd8"))
	var br := Color("d8b070")
	var dk := Color("8a6a30")
	# crest, dome, neck guard, face guard
	_poly([-0.36, -0.62, -0.1, -0.92, 0.35, -0.96, 0.75, -0.55, 0.6, -0.5, 0.3, -0.7, 0.0, -0.66], dk, _re, 0.06)
	_poly([0.4, -0.05, 0.78, 0.15, 0.82, 0.55, 0.5, 0.52, 0.2, 0.3], br, _re, 0.07)
	_ell(0.05, -0.2, 0.58, 0.5, br, 0.0, _re)
	_poly([-0.52, -0.2, -0.46, 0.3, -0.34, 0.74, -0.08, 0.76, -0.1, 0.36, 0.0, 0.1, -0.1, -0.3], br, _re, 0.07)
	# eye slot, nose slit
	_poly([-0.4, -0.12, -0.12, -0.14, -0.1, 0.02, -0.36, 0.06], INK)
	if not simple:
		_line(-0.2, 0.1, -0.2, 0.42, 0.06, INK)
		_line(-0.34, 0.5, -0.12, 0.5, 0.05, dk)
	_frame()


## Syracuse: two dolphins round a ship, gold on teal.
static func _syracuse(_simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("2fa8a0"))
	var g := GOLD
	for sg in [1.0, -1.0]:
		# a dolphin along the ring: head at the top, tail at the foot
		var n := 12
		var prev := Vector2.ZERO
		for i in n + 1:
			var a := deg_to_rad(-82.0 + 164.0 * i / n)
			var q := Vector2(sg * cos(a), sin(a)) * 0.78
			var w := lerpf(0.32, 0.1, float(i) / n)
			_disc(q.x, q.y, w * 0.5, g)
			if i > 0:
				_line(prev.x, prev.y, q.x, q.y, w, g)
			prev = q
		_poly([sg * 0.9, -0.15, sg * 1.02, -0.4, sg * 0.78, -0.35], g, _re, 0.05)
		# tail flukes and head beak
		_poly([sg * 0.0, 0.82, sg * 0.3, 0.98, sg * 0.1, 0.72], g, false)
		_poly([sg * 0.02, -0.7, sg * 0.0, -0.92, sg * 0.22, -0.66], g, false)
	# the ship: hull, mast, sail
	_poly([-0.4, 0.2, 0.4, 0.2, 0.28, 0.48, -0.28, 0.48], g, _re, 0.06)
	_line(0.0, 0.2, 0.0, -0.5, 0.08, g)
	_poly([0.06, -0.46, 0.06, 0.1, 0.4, 0.1], CREAM, _re, 0.05)
	_poly([-0.06, -0.3, -0.06, 0.1, -0.34, 0.1], CREAM, _re, 0.05)
	_frame()


## The Iberians: the falcata (curved blade) beside a round shield, on brown.
static func _iberians(_simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("8a5a2b"))
	var steel := Color("e4dcc6")
	var br := Color("d1a24a")
	# round shield
	_disc(0.3, 0.12, 0.58, INK)
	_disc(0.3, 0.12, 0.52, br)
	_disc(0.3, 0.12, 0.34, Color("a8741f"))
	_disc(0.3, 0.12, 0.16, br)
	# falcata: a blade curving forward, guard, grip, pommel
	_poly([-0.48, 0.5, -0.3, 0.5, -0.2, 0.0, -0.24, -0.5, -0.42, -0.92, -0.52, -0.9, -0.64, -0.5, -0.6, 0.0], steel, _re, 0.06)
	_line(-0.66, 0.52, -0.12, 0.52, 0.12, br)
	_line(-0.39, 0.52, -0.39, 0.86, 0.12, Color("4a2a10"))
	_disc(-0.39, 0.92, 0.1, br)
	_frame()


## The Gauls: a boar with a bristle crest (facing right) under a carnyx, gold on green.
static func _gauls(simple: bool) -> void:
	_rect(-1, -1, 1, 1, Color("3c9a3c"))
	var g := GOLD
	# carnyx: a long tube with a flared boar-head bell
	_line(-0.7, -0.66, 0.7, -0.66, 0.1, CREAM)
	_poly([-0.64, -0.8, -0.95, -0.9, -0.88, -0.56, -0.64, -0.52], CREAM, _re, 0.05)
	for lx in [-0.44, -0.2, 0.34, 0.58]:
		_rect(lx - 0.09, 0.5, lx + 0.09, 0.9, g)
	_ell(0.0, 0.26, 0.62, 0.34, g, 0.0, _re)
	# bristle crest
	_poly([-0.52, 0.12, -0.46, -0.16, -0.32, 0.02, -0.2, -0.26, -0.04, -0.04, 0.1, -0.3, 0.24, -0.04, 0.38, -0.22, 0.46, 0.04, 0.52, 0.2], g, _re, 0.05)
	# head, snout, ear, tusk, eye
	_ell(0.58, 0.34, 0.3, 0.22, g, 0.0, _re)
	_poly([0.78, 0.26, 0.98, 0.4, 0.94, 0.5, 0.76, 0.5], g, _re, 0.05)
	_poly([0.48, 0.14, 0.58, -0.08, 0.66, 0.16], g, _re, 0.05)
	_line(0.8, 0.5, 0.88, 0.32, 0.06, CREAM)
	if not simple:
		_disc(0.62, 0.3, 0.035, INK)
	_frame()
