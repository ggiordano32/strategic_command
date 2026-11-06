extends Node2D
## Ships lying off the shore in a land battle (docs/design/art_pipeline.md "(2026-11-05) The ship on the board";
## docs/design/battle_sim.md "A fleet at the shore (as built, 2026-11-05)"): each of the sim's ships (BattleSim sh_*)
## as a hull on the water under the men, in the tabletop's language. The top view draws the sea battle's hull outline
## (game/sea_battle.gd _draw_ship: the same seven-point hull, a canoe's pointed ends) flat: the waterline's foam, the
## hull, the deck, the rail in the owner's colour, the gunports, the masts with their sails furled on the yards. The
## oblique view stands the same hull up as a small solid in the siege gear's way (game/siege_gear_ob.gd: drawn in the
## lifted node's upright groups, BoardView.up_xf, with the board's oblique constants): the hull's sides and its deck
## a little above the water, the masts, the furled sails and a pennant. A ship whose guns are all silenced is drawn
## dark and low with her masts shot away; one gone from the fight (her crew lost) fades. Below the soldiers, so her
## gun crews stand on her deck and her guns (the engines' own sprites) on top of it. View only: it reads the sim.

const SiegeGearOb := preload("res://game/siege_gear_ob.gd")
const BoardView := preload("res://game/board_view.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const CData := preload("res://campaign/cdata.gd")

const COL_SAIL := Color(0.96, 0.94, 0.86)     # (game/sea_battle.gd's colours)
const COL_HULL := Color(0.42, 0.27, 0.16)
const COL_DECK := Color(0.68, 0.55, 0.37)
const COL_MAST := Color(0.25, 0.17, 0.10)
const COL_FOAM := Color(0.9, 0.97, 1.0, 0.35)
const COL_SIDE := [Color(0.35, 0.6, 1.0), Color(1.0, 0.36, 0.28)]

var sim
var px_per_m := 10.0
## Per ship (the sim's ship order): her rail and pennant colour (the owner faction's, else her side's).
var colors: Array[Color] = []
var _ob := Solid.new()
var _sig := -1


## p_ships: the scenario's "ships" (each may carry "f", the campaign faction: her colours).
func setup(p_sim, p_px_per_m: float, p_ships: Array = []) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	colors = []
	if sim == null or sim.shp_on == 0:
		visible = false
		return
	for s in sim.sh_side.size():
		var col: Color = COL_SIDE[clampi(int(sim.sh_side[s]), 0, 1)]
		var src: int = sim.sh_src[s]
		if src >= 0 and src < p_ships.size() and int((p_ships[src] as Dictionary).get("f", -1)) >= 0:
			col = CData.faction_color(int(p_ships[src]["f"]))
		colors.append(col)
	visible = true
	_sig = -1
	refresh()


## Redraw when a ship's state changed (a gun silenced, her crew gone, her party landed).
func refresh() -> void:
	if sim == null or sim.shp_on == 0:
		return
	var h := 23
	for s in sim.sh_side.size():
		h = (h * 31 + _state(s) * 7 + sim.sh_land[s] + 3) & 0x3FFFFFFF
	if h != _sig:
		_sig = h
		queue_redraw()


## Ship s: 0 fighting, 1 silenced (every gun wrecked), 2 out of the fight (her hull unit gone).
func _state(s: int) -> int:
	var u: int = sim.sh_unit[s]
	if u < 0 or sim.u_state[u] >= BattleSim.U_DESTROYED or sim.u_alive[u] <= 0:
		return 2
	if sim.u_neng[u] > 0 and not sim._ship_guns_ok(u):
		return 1
	return 0


## The hull outline in metres along the keel (x) and across it (y): the sea battle's (a canoe's pointed both ends).
static func hull_shape(ln: float, bm: float, canoe: bool) -> PackedVector2Array:
	if canoe:
		return PackedVector2Array([Vector2(ln * 0.5, 0), Vector2(ln * 0.25, bm * 0.5), Vector2(-ln * 0.3, bm * 0.5),
			Vector2(-ln * 0.5, 0), Vector2(-ln * 0.3, -bm * 0.5), Vector2(ln * 0.25, -bm * 0.5)])
	return PackedVector2Array([Vector2(ln * 0.5, 0), Vector2(ln * 0.3, bm * 0.5), Vector2(-ln * 0.38, bm * 0.5),
		Vector2(-ln * 0.5, bm * 0.36), Vector2(-ln * 0.5, -bm * 0.36), Vector2(-ln * 0.38, -bm * 0.5), Vector2(ln * 0.3, -bm * 0.5)])


## Masts along the keel (fractions of the length): a sloop or a canoe one, a brigantine two, the rest three.
static func masts_of(key: String, ln: int) -> Array:
	if key == "war_canoe" or key == "great_canoe" or key == "fire_canoe":
		return []
	if key == "sloop" or key == "piragua" or ln < 22:
		return [0.12]
	if key == "brigantine" or ln < 30:
		return [0.22, -0.12]
	return [0.3, 0.02, -0.25]


func _draw() -> void:
	if sim == null or sim.shp_on == 0:
		return
	var lw := maxf(1.0, px_per_m * 0.1)
	# Far to near (the oblique view's solids overlap that way; the top view does not mind).
	var order: Array = []
	for s in sim.sh_side.size():
		order.append([int(sim.sh_y[s]), s])
	order.sort_custom(func(a, b): return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	for it in order:
		var s: int = it[1]
		if BoardView.oblique:
			_draw_oblique(s, lw)
		else:
			_draw_top(s, lw)


func _draw_top(s: int, lw: float) -> void:
	var st := _state(s)
	var key: String = sim.sh_key[s]
	var ln := float(sim.sh_len[s])
	var bm := float(sim.sh_beam[s])
	var canoe := masts_of(key, int(ln)).is_empty() or key == "piragua"
	var hd := float(sim.sh_head[s]) * TAU / 1024.0
	var fwd := Vector2(cos(hd), sin(hd))
	var sd := Vector2(-fwd.y, fwd.x)
	var at := Vector2(sim.sh_x[s], sim.sh_y[s]) * (px_per_m / 1024.0)
	var xf := Transform2D(fwd * px_per_m, sd * px_per_m, at)
	var fade := 0.55 if st == 2 else 1.0
	var shape := hull_shape(ln, bm, canoe)
	var foam := PackedVector2Array()
	var hull := PackedVector2Array()
	var deck := PackedVector2Array()
	for v in shape:
		foam.append(xf * (v * 1.14))
		hull.append(xf * v)
		deck.append(xf * (v * 0.78))
	draw_colored_polygon(foam, Color(COL_FOAM, COL_FOAM.a * fade))
	draw_colored_polygon(hull, Color(COL_HULL.darkened(0.45 if st > 0 else 0.0), fade))
	draw_colored_polygon(deck, Color(COL_DECK.darkened(0.3 if st > 0 else 0.0), fade))
	var rail := hull.duplicate()
	rail.append(hull[0])
	draw_polyline(rail, Color(colors[s], 0.95 * fade), maxf(1.2, px_per_m * 0.35), true)
	var u: int = sim.sh_unit[s]
	var ports: int = clampi(sim.u_neng[u] * 2, 0, 9) if u >= 0 else 0
	for i in ports:
		var f := (float(i) + 0.5) / ports - 0.5
		for sg in [-1.0, 1.0]:
			draw_circle(xf * Vector2(f * ln * 0.66, sg * bm * 0.44), maxf(px_per_m * 0.3, 0.6), Color(0.08, 0.06, 0.05, fade))
	if canoe and key != "piragua":
		# Paddles shipped along both sides.
		for i in 5:
			var f2 := (float(i) + 0.5) / 5.0 - 0.5
			for sg2 in [-1.0, 1.0]:
				draw_line(xf * Vector2(f2 * ln * 0.7, sg2 * bm * 0.5), xf * Vector2(f2 * ln * 0.7 - bm * 0.3, sg2 * bm * 1.1),
					Color(0.3, 0.2, 0.1, fade), maxf(0.8, px_per_m * 0.3))
		return
	for m in masts_of(key, int(ln)):
		var mp: Vector2 = xf * Vector2(float(m) * ln, 0)
		if st == 1 and float(m) < 0.25:
			draw_circle(mp, px_per_m * 0.6, COL_MAST)  # (shot away: a stump)
			continue
		# The sail furled on its yard across the hull.
		var ya: Vector2 = xf * Vector2(float(m) * ln, -bm * 0.8)
		var yb: Vector2 = xf * Vector2(float(m) * ln, bm * 0.8)
		draw_line(ya, yb, COL_MAST, maxf(1.0, px_per_m * 0.25))
		draw_line(xf * Vector2(float(m) * ln - 0.35, -bm * 0.72), xf * Vector2(float(m) * ln - 0.35, bm * 0.72),
			Color(COL_SAIL, 0.95 * fade), maxf(1.2, px_per_m * 0.55))
		draw_circle(mp, px_per_m * 0.55, COL_MAST)
	# The ensign at the stern.
	var fp: Vector2 = xf * Vector2(-ln * 0.5, 0)
	var fl := maxf(ln * px_per_m * 0.16, 5.0)
	var flag := PackedVector2Array([fp, fp - fwd * fl, fp - fwd * fl + sd * fl * 0.55, fp + sd * fl * 0.55])
	draw_colored_polygon(flag, Color(colors[s], fade))
	draw_polyline(flag, Color(0, 0, 0, 0.5), 0.6 * lw, true)


func _draw_oblique(s: int, lw: float) -> void:
	var st := _state(s)
	var key: String = sim.sh_key[s]
	var ln := float(sim.sh_len[s])
	var bm := float(sim.sh_beam[s])
	var canoe := masts_of(key, int(ln)).is_empty() or key == "piragua"
	var hd := float(sim.sh_head[s]) * TAU / 1024.0
	var fwd := Vector2(cos(hd), sin(hd))
	var sd := Vector2(-fwd.y, fwd.x)
	var at := Vector2(sim.sh_x[s], sim.sh_y[s]) * (px_per_m / 1024.0)
	var fade := 0.55 if st == 2 else 1.0
	var shape := hull_shape(ln, bm, canoe)
	# The waterline's foam flat on the water (the node's own lift places it), then the hull standing up.
	var foam := PackedVector2Array()
	for v in shape:
		var w := v * 1.14
		foam.append(at + (fwd * w.x + sd * w.y) * px_per_m)
	draw_colored_polygon(foam, Color(COL_FOAM, COL_FOAM.a * fade))
	var ob := _ob
	ob.ci = self
	ob.sim = sim
	ob.ppm = px_per_m
	ob.lw = lw
	ob.begin_at(at)
	var fb := clampf(bm * 0.22, 0.5, 2.6) * (0.6 if st == 1 else 1.0)  # freeboard (m)
	var pts: Array = []
	for v in shape:
		pts.append(fwd * v.x + sd * v.y)
	var hull_col := Color(COL_HULL.darkened(0.45 if st > 0 else 0.0), fade)
	ob.prism(pts, 0.0, fb, hull_col, Color(COL_DECK.darkened(0.3 if st > 0 else 0.0), fade))
	# The rail in the owner's colour round the deck.
	for i in pts.size():
		var p: Vector2 = pts[i] * 0.97
		var q: Vector2 = pts[(i + 1) % pts.size()] * 0.97
		ob.bar(p, fb + 0.15, q, fb + 0.15, Color(colors[s], 0.95 * fade), maxf(1.0, lw * 0.9))
	if canoe and key != "piragua":
		for i in 5:
			var f2 := (float(i) + 0.5) / 5.0 - 0.5
			for sg2 in [-1.0, 1.0]:
				var a: Vector2 = fwd * (f2 * ln * 0.7) + sd * (sg2 * bm * 0.5)
				ob.bar(a, fb * 0.8, a + sd * (sg2 * bm * 0.7) - fwd * (bm * 0.3), 0.1, Color(0.3, 0.2, 0.1, fade), maxf(1.0, lw * 0.8))
		ob.end_at()
		return
	# Gunports along her side toward the camera.
	var u: int = sim.sh_unit[s]
	var ports: int = clampi(sim.u_neng[u] * 2, 0, 9) if u >= 0 else 0
	var near_sg := 1.0 if sd.y >= 0.0 else -1.0
	for i in ports:
		var f := (float(i) + 0.5) / ports - 0.5
		var gp: Vector2 = fwd * (f * ln * 0.66) + sd * (near_sg * bm * 0.5)
		draw_circle(ob.pt(gp, fb * 0.55), maxf(px_per_m * 0.28, 1.0), Color(0.08, 0.06, 0.05, fade))
	var mh := clampf(ln * 0.42, 7.0, 18.0)   # (a miniature's mast: well under her length)
	var masts := masts_of(key, int(ln))
	# The yards braced round a little, so the furled sails show from the table's side.
	var yd := (sd * cos(0.4) + fwd * sin(0.4)).normalized()
	for i in masts.size():
		var mp: Vector2 = fwd * (float(masts[i]) * ln)
		var top := mh * (1.0 if i == 0 or masts.size() == 1 else (0.92 if i == 1 else 0.8))
		if st == 1 and i > 0:
			ob.bar(mp, fb, mp + sd * 1.2, fb + top * 0.25, COL_MAST, lw * 1.8)  # (shot away: a stump leaning over)
			continue
		ob.bar(mp, fb, mp, fb + top, COL_MAST, maxf(2.0, px_per_m * 0.4))
		# Two yards with their sails furled on them (a pale roll along each).
		for yk in 2:
			var yh: float = fb + top * (0.5 if yk == 0 else 0.82)
			var half := bm * (0.7 if yk == 0 else 0.5)
			ob.bar(mp - yd * half, yh, mp + yd * half, yh, COL_MAST, maxf(1.2, px_per_m * 0.22))
			ob.bar(mp - yd * half * 0.9, yh - 0.45, mp + yd * half * 0.9, yh - 0.45, Color(COL_SAIL, 0.97 * fade), maxf(2.5, px_per_m * 0.75))
		if i == 0:
			# A pennant at the masthead in her colours.
			var pt := ob.pt(mp, fb + top)
			var pl := maxf(px_per_m * 2.6, 6.0)
			var tip := pt + Vector2(pl, pl * 0.18)
			ci_poly([pt, tip, pt + Vector2(0, pl * 0.36)], Color(colors[s], fade))
	ob.end_at()


## The 3D view (game/view3d.gd): every ship as solids in one mesh, the oblique view's hull, rail, oars, masts, yards and furled
## sails (the waterline's foam, the gunports and the pennant stay flat details of the 2D views); null when there is none.
## `sig` tells the view when to build it again (a gun silenced, her crew gone, her party landed).
func sig() -> int:
	return _sig


func build_mesh3d() -> ArrayMesh:
	if sim == null or sim.shp_on == 0 or sim.sh_side.size() == 0:
		return null
	var ob := _ob
	ob.sim = sim
	ob.ppm = px_per_m
	ob.lw = 1.0
	ob.ground_m = func(w: Vector2) -> float: return BoardView.ground_m(w)
	ob.st3 = SurfaceTool.new()
	ob.st3.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in sim.sh_side.size():
		_ship3d(s)
	var m := ob.st3.commit()
	ob.st3 = null
	return m


func _ship3d(s: int) -> void:
	var ob := _ob
	var st := _state(s)
	var key: String = sim.sh_key[s]
	var ln := float(sim.sh_len[s])
	var bm := float(sim.sh_beam[s])
	var canoe := masts_of(key, int(ln)).is_empty() or key == "piragua"
	var hd := float(sim.sh_head[s]) * TAU / 1024.0
	var fwd := Vector2(cos(hd), sin(hd))
	var sd := Vector2(-fwd.y, fwd.x)
	var at := Vector2(sim.sh_x[s], sim.sh_y[s]) * (px_per_m / 1024.0)
	ob.begin_at(at)
	var fb := clampf(bm * 0.22, 0.5, 2.6) * (0.6 if st == 1 else 1.0)
	var pts: Array = []
	for v in hull_shape(ln, bm, canoe):
		pts.append(fwd * v.x + sd * v.y)
	ob.prism(pts, -0.3, fb, COL_HULL.darkened(0.45 if st > 0 else 0.0), COL_DECK.darkened(0.3 if st > 0 else 0.0))
	for i in pts.size():
		var p: Vector2 = pts[i] * 0.97
		var q: Vector2 = pts[(i + 1) % pts.size()] * 0.97
		ob.bar(p, fb + 0.15, q, fb + 0.15, colors[s], 1.0)
	if canoe and key != "piragua":
		for i in 5:
			var f2 := (float(i) + 0.5) / 5.0 - 0.5
			for sg2 in [-1.0, 1.0]:
				var a: Vector2 = fwd * (f2 * ln * 0.7) + sd * (sg2 * bm * 0.5)
				ob.bar(a, fb * 0.8, a + sd * (sg2 * bm * 0.7) - fwd * (bm * 0.3), 0.1, Color(0.3, 0.2, 0.1), 0.8)
		ob.end_at()
		return
	var mh := clampf(ln * 0.42, 7.0, 18.0)
	var masts := masts_of(key, int(ln))
	var yd := (sd * cos(0.4) + fwd * sin(0.4)).normalized()
	for i in masts.size():
		var mp: Vector2 = fwd * (float(masts[i]) * ln)
		var top := mh * (1.0 if i == 0 or masts.size() == 1 else (0.92 if i == 1 else 0.8))
		if st == 1 and i > 0:
			ob.bar(mp, fb, mp + sd * 1.2, fb + top * 0.25, COL_MAST, 1.8)
			continue
		ob.bar(mp, fb, mp, fb + top, COL_MAST, 3.0)
		for yk in 2:
			var yh: float = fb + top * (0.5 if yk == 0 else 0.82)
			var half := bm * (0.7 if yk == 0 else 0.5)
			ob.bar(mp - yd * half, yh, mp + yd * half, yh, COL_MAST, 1.6)
			ob.bar(mp - yd * half * 0.9, yh - 0.45, mp + yd * half * 0.9, yh - 0.45, COL_SAIL, 5.0)
	ob.end_at()


func ci_poly(p: Array, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array(p), col)


## The siege gear's oblique solids with a hull's prism added (the upright group's helpers made callable here).
class Solid extends SiegeGearOb:
	func begin_at(anchor: Vector2) -> void:
		_begin(anchor)

	func end_at() -> void:
		_end()

	func pt(off: Vector2, h: float) -> Vector2:
		return _pt(off, h)

	func bar(p0: Vector2, h0: float, p1: Vector2, h1: float, col: Color, w: float) -> void:
		_bar(p0, h0, p1, h1, col, w)

	## A prism over the polygon `poly` (metres from the anchor) from h0 to h1: its sides facing the camera, far
	## first, shaded by the key light, then its top (`top_col`).
	func prism(poly: Array, h0: float, h1: float, col: Color, top_col: Color) -> void:
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= maxf(poly.size(), 1)
		if st3 != null:
			# (the 3D view: every side and the deck as a fan; the depth buffer hides the far sides)
			for i in poly.size():
				var p3: Vector2 = poly[i]
				var q3: Vector2 = poly[(i + 1) % poly.size()]
				var e3 := q3 - p3
				var n3 := Vector2(e3.y, -e3.x).normalized()
				if n3.dot((p3 + q3) * 0.5 - c) < 0.0:
					n3 = -n3
				var k3 := 0.62 + 0.38 * clampf(n3.dot(LIGHT.normalized()) * 0.5 + 0.5, 0.0, 1.0)
				_quad3(_p3(p3, h0), _p3(q3, h0), _p3(q3, h1), _p3(p3, h1), _tint(col, k3))
			for i in poly.size():
				_tri3(_p3(c, h1), _p3(poly[(i + 1) % poly.size()], h1), _p3(poly[i], h1), top_col)
			return
		var faces: Array = []
		for i in poly.size():
			var p: Vector2 = poly[i]
			var q: Vector2 = poly[(i + 1) % poly.size()]
			var mid := (p + q) * 0.5
			var e := q - p
			var n := Vector2(e.y, -e.x).normalized()
			if n.dot(mid - c) < 0.0:
				n = -n
			faces.append([mid.y, p, q, n])
		faces.sort_custom(func(x, y): return x[0] < y[0])
		for fc in faces:
			var n: Vector2 = fc[3]
			if n.y <= -0.2:
				continue
			var k := 0.62 + 0.38 * clampf(n.dot(LIGHT.normalized()) * 0.5 + 0.5, 0.0, 1.0)
			_quad([_pt(fc[1], h0), _pt(fc[2], h0), _pt(fc[2], h1), _pt(fc[1], h1)], _tint(col, k))
		var top: Array = []
		for p in poly:
			top.append(_pt(p, h1))
		_quad(top, top_col)
