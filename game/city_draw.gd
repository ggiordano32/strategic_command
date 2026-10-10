extends RefCounted
## Drawing of a settlement's layout (sim/mapgen.gd, metres, final frame),
## shared by the battle map (game/city_layer.gd), the campaign's "View
## battle map" (game/campaign/city_preview.gd) and tools/city_dump.gd. A
## point (x, y) in metres is drawn at o + (x, y) * k. View only.
##
## Roofs by the culture that built them (Roman red tile, Greek pale tile,
## Punic flat white roofs with a parapet, Celtic thatch: round houses), the
## owner's shrine on the agora in the owner's style (Roman podium temple,
## Greek colonnaded temple, Punic walled precinct, Celtic sacred
## enclosure), stone walls (a timber palisade for a village), round or
## square towers, the citadel's ring, stairs at the ends of each walkway
## stretch, the sea gate and moles, and banners in the owner's colour on
## the gate towers, the citadel and the agora.
##
## Round the settlement (plan_surround / draw_surround, battle map only):
## dirt tracks from each outer gate to the map edge and ploughed fields,
## stubble, crops and orchard patches in the clear ground beyond the walls
## (never on streets, the ditch, woods, water, the deployment zones, the
## attackers' approach or the siege equipment), laid out once per battle
## from a hash of the map; the tree layer plants the orchards' rows.

const MapGen := preload("res://sim/mapgen.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const CData := preload("res://campaign/cdata.gd")

const STONE := Color(0.46, 0.43, 0.39)
const STONE_DARK := Color(0.28, 0.26, 0.24)
const WALK := Color(0.62, 0.59, 0.53)
const TIMBER := Color(0.42, 0.29, 0.17)
const TIMBER_DARK := Color(0.25, 0.17, 0.10)
const SHADOW := Color(0, 0, 0, 0.3)
## Roof colour by culture: latin red tile, greek pale tile, punic flat
## white, celtic thatch.
const ROOF_STYLE: Array[Color] = [Color(0.70, 0.36, 0.24), Color(0.84, 0.70, 0.54),
	Color(0.90, 0.88, 0.82), Color(0.70, 0.58, 0.36)]
## Other landmarks keep a colour of their own, tinted by the style.
const KIND_COL := {MapGen.B_MARKET: Color(0.78, 0.72, 0.6), MapGen.B_BARRACKS: Color(0.52, 0.32, 0.24),
	MapGen.B_STABLES: Color(0.55, 0.45, 0.32), MapGen.B_WORKSHOP: Color(0.46, 0.43, 0.39),
	MapGen.B_RANGE: Color(0.62, 0.5, 0.34)}
const SIDE_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.36, 0.28)]


## Banner colour: the owner faction's, grey for independents, else (no
## campaign) the defending side's.
static func banner_color(lay: Dictionary) -> Color:
	var b := int(lay.get("banner", -2))
	if b >= 0 and b < CData.FACTIONS.size():
		return Color(str(CData.FACTIONS[b]["color"]))
	if b == -1:
		return Color(CData.INDEPENDENT_COLOR)
	return SIDE_COLORS[clampi(int(lay.get("def", 1)), 0, 1)]


## Everything static. `fine`: details for close views (merlons, stairs,
## roof ridges); `gates`: draw the gates too, closed (the preview; the
## battle draws them per tick with draw_gate).
static func draw_static(ci: CanvasItem, lay: Dictionary, k: float, o: Vector2, fine: bool, gates: bool) -> void:
	var banner := banner_color(lay)
	_draw_squares(ci, lay, k, o)
	var sea: Dictionary = lay.get("sea", {})
	if not sea.is_empty():
		for mo in sea["moles"]:
			var mp: PackedInt32Array = mo
			var pts := PackedVector2Array()
			for q in 4:
				pts.append(o + Vector2(mp[q * 2], mp[q * 2 + 1]) * k)
			ci.draw_colored_polygon(pts, STONE.lightened(0.1))
			pts.append(pts[0])
			ci.draw_polyline(pts, STONE_DARK, maxf(k * 0.4, 1.0))
	_draw_buildings(ci, lay, k, o, fine)
	if int(lay["walls"]) > 0:
		var pal := int(lay.get("palisade", 0)) != 0
		_draw_ring(ci, lay, lay["poly"], k, o, fine, pal)
		var cit: Dictionary = lay.get("cit", {})
		if not cit.is_empty():
			_draw_ring(ci, lay, cit["poly"], k, o, fine, false)
		for tw in lay["towers"]:
			_draw_tower(ci, tw, k, o, pal)
		if fine:
			_draw_stairs(ci, lay, k, o)
		if not sea.is_empty() and not (sea["gate"] as Array).is_empty():
			_draw_sea_gate(ci, lay, sea["gate"], k, o)
		if gates:
			for g in (lay["gates"] as Array).size():
				draw_gate(ci, lay, g, BattleSim.GATE_CLOSED, false, 0, k, o)
	_draw_banners(ci, lay, k, o, banner)


static func _p(o: Vector2, k: float, x: float, y: float) -> Vector2:
	return o + Vector2(x, y) * k


## The agora (paving edge and a fountain) and, inside a citadel, its court.
static func _draw_squares(ci: CanvasItem, lay: Dictionary, k: float, o: Vector2) -> void:
	var ag: Array = lay.get("agora", lay["plaza"])
	var hs: float = ag[2]
	var pr := Rect2(_p(o, k, ag[0] - hs, ag[1] - hs), Vector2(hs, hs) * 2.0 * k)
	ci.draw_rect(pr, Color(0.95, 0.92, 0.82, 0.18))
	# Worn ground: scuffed patches, a path of use round the fountain, paving
	# joints in the middle of the square.
	var ax := float(ag[0])
	var ay := float(ag[1])
	for q in 16:
		var h1 := float(((q * 7919 + int(ax) * 31 + int(ay) * 17) * 2654435761) & 1023) / 1023.0
		var h2 := float(((q * 104729 + int(ax) * 13 + int(ay) * 29) * 2246822519) & 1023) / 1023.0
		var h3 := float(((q * 15485863 + int(ay) * 7) * 3266489917) & 1023) / 1023.0
		var wc := _p(o, k, ax + (h1 * 2.0 - 1.0) * hs * 0.85, ay + (h2 * 2.0 - 1.0) * hs * 0.85)
		ci.draw_circle(wc, (1.2 + h3 * 2.4) * k, Color(0.25, 0.20, 0.14, 0.07) if q % 2 == 0 else Color(1.0, 0.97, 0.88, 0.07))
	ci.draw_circle(_p(o, k, ax, ay), hs * 0.55 * k, Color(0.2, 0.16, 0.11, 0.08))
	if hs * k > 22.0:
		var jc := Color(0.25, 0.22, 0.17, 0.1)
		var jy := -hs * 0.8
		while jy <= hs * 0.81:
			ci.draw_line(_p(o, k, ax - hs * 0.8, ay + jy), _p(o, k, ax + hs * 0.8, ay + jy), jc, 1.0)
			ci.draw_line(_p(o, k, ax + jy, ay - hs * 0.8), _p(o, k, ax + jy, ay + hs * 0.8), jc, 1.0)
			jy += 3.0
	ci.draw_rect(pr, Color(0.3, 0.27, 0.22, 0.55), false, maxf(k * 0.35, 1.0))
	ci.draw_circle(_p(o, k, ag[0], ag[1]), k * 2.6, Color(0.30, 0.27, 0.22, 0.5))
	ci.draw_circle(_p(o, k, ag[0], ag[1]), k * 2.2, Color(0.55, 0.52, 0.47))
	ci.draw_circle(_p(o, k, ag[0], ag[1]), k * 1.6, Color(0.42, 0.58, 0.68))
	var cit: Dictionary = lay.get("cit", {})
	if not cit.is_empty():
		var pts := _poly_pts(cit["poly"], k, o)
		ci.draw_colored_polygon(pts, Color(0.86, 0.82, 0.72, 0.35))


static func _poly_pts(poly: PackedInt32Array, k: float, o: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for q in poly.size() / 2:
		pts.append(o + Vector2(poly[q * 2], poly[q * 2 + 1]) * k)
	return pts


# -------------------------------------------------------------- houses ----

static func _draw_buildings(ci: CanvasItem, lay: Dictionary, k: float, o: Vector2, fine: bool) -> void:
	var sh := Vector2(1.0, 1.25) * k
	# Contact shadow (small, dark) then the long soft one, cast to the lower
	# right by the light at the upper left.
	for pass_i in 2:
		var off := sh if pass_i == 1 else sh * 0.45
		var scol := Color(0, 0, 0, 0.24) if pass_i == 1 else Color(0, 0, 0, 0.2)
		if pass_i == 0 and not fine:
			continue
		_house_shadows(ci, lay, k, o, off, scol)
	var ag: Array = lay.get("agora", lay["plaza"])
	_house_roofs(ci, lay, k, o, fine, ag)


static func _house_shadows(ci: CanvasItem, lay: Dictionary, k: float, o: Vector2, sh: Vector2, scol: Color) -> void:
	for b in lay["buildings"]:
		var a: Array = b
		var shape := int(a[6]) if a.size() > 6 else MapGen.SH_RECT
		if shape == MapGen.SH_ROUND:
			ci.draw_circle(_p(o, k, a[7], a[8]) + sh, float(a[9]) * k, scol)
		elif shape == MapGen.SH_QUAD:
			var pts := PackedVector2Array()
			for q in 4:
				pts.append(_p(o, k, a[7 + q * 2], a[8 + q * 2]) + sh)
			ci.draw_colored_polygon(pts, scol)
		else:
			ci.draw_rect(Rect2(_p(o, k, a[0], a[1]) + sh, Vector2(int(a[2]) - int(a[0]), int(a[3]) - int(a[1])) * k), scol)


static func _house_roofs(ci: CanvasItem, lay: Dictionary, k: float, o: Vector2, fine: bool, ag: Array) -> void:
	for b in lay["buildings"]:
		var a: Array = b
		var kind: int = a[4]
		var style := clampi(int(a[5]) if a.size() > 5 else 0, 0, 3)
		var shape := int(a[6]) if a.size() > 6 else MapGen.SH_RECT
		if kind == MapGen.B_TEMPLE:
			_draw_shrine(ci, a, style, k, o, Vector2(ag[0], ag[1]), fine)
			continue
		var h := (int(a[0]) * 73 + int(a[1]) * 151) % 100
		var col: Color = ROOF_STYLE[style]
		if kind != MapGen.B_HOUSE:
			col = (KIND_COL.get(kind, col) as Color).lerp(col, 0.35)
		col = col.lerp(col.lightened(0.15) if h < 50 else col.darkened(0.15), (h % 50) / 100.0)
		if shape == MapGen.SH_ROUND:
			_round_roof(ci, _p(o, k, a[7], a[8]), float(a[9]) * k, col, fine)
			continue
		var pts := PackedVector2Array()
		if shape == MapGen.SH_QUAD:
			for q in 4:
				pts.append(_p(o, k, a[7 + q * 2], a[8 + q * 2]))
		else:
			var r0 := _p(o, k, a[0], a[1])
			var r1 := _p(o, k, a[2], a[3])
			pts = PackedVector2Array([r0, Vector2(r1.x, r0.y), r1, Vector2(r0.x, r1.y)])
		if style == MapGen.CUL_PUNIC:
			_flat_roof(ci, pts, col, k, fine)
		else:
			_gable_roof(ci, pts, col, k, fine)


## A gabled roof on a quad: two halves either side of the ridge, which runs
## along the longer sides.
static func _gable_roof(ci: CanvasItem, pts: PackedVector2Array, col: Color, k: float, fine: bool) -> void:
	ci.draw_colored_polygon(pts, col.darkened(0.12))
	var long01 := pts[0].distance_to(pts[1]) >= pts[1].distance_to(pts[2])
	var m0: Vector2
	var m1: Vector2
	var half: PackedVector2Array
	if long01:
		m0 = (pts[0] + pts[3]) * 0.5
		m1 = (pts[1] + pts[2]) * 0.5
		half = PackedVector2Array([pts[0], pts[1], m1, m0])
	else:
		m0 = (pts[0] + pts[1]) * 0.5
		m1 = (pts[3] + pts[2]) * 0.5
		half = PackedVector2Array([pts[0], m0, m1, pts[3]])
	ci.draw_colored_polygon(half, col.lightened(0.08))
	# Ridge: a dark line with a light edge on the lit side; tile courses
	# across each slope when close.
	var rw := maxf(k * 0.25, 1.0)
	var lit := (half[0] + half[1] + half[2] + half[3]) * 0.25 - (m0 + m1) * 0.5
	var lit_n := lit.normalized()
	ci.draw_line(m0, m1, col.darkened(0.4), rw)
	ci.draw_line(m0 + lit_n * rw * 0.8, m1 + lit_n * rw * 0.8, col.lightened(0.28), maxf(rw * 0.6, 1.0))
	if fine:
		var cc := Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 0.45)
		var along := (m1 - m0)
		if along.length() > 0.0:
			var acr := lit_n * lit.length()
			for f in [0.33, 0.66]:
				var q0: Vector2 = m0 + acr * f
				ci.draw_line(q0, q0 + along, cc, maxf(k * 0.08, 1.0))
				var q1: Vector2 = m0 - acr * f
				ci.draw_line(q1, q1 + along, cc, maxf(k * 0.08, 1.0))
	var ring := pts.duplicate()
	ring.append(pts[0])
	ci.draw_polyline(ring, col.darkened(0.45), maxf(k * 0.15, 1.0))


## A flat roof with a low parapet (Punic houses).
static func _flat_roof(ci: CanvasItem, pts: PackedVector2Array, col: Color, k: float, fine: bool) -> void:
	ci.draw_colored_polygon(pts, col.darkened(0.06))
	if fine:
		var c := (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25
		var inner := PackedVector2Array()
		for q in 4:
			inner.append(c + (pts[q] - c) * 0.72)
		ci.draw_colored_polygon(inner, col.lightened(0.06))
	var ring := pts.duplicate()
	ring.append(pts[0])
	ci.draw_polyline(ring, col.darkened(0.3), maxf(k * 0.3, 1.0))


## A round thatched roof: darker rim, rings, the smoke hole.
static func _round_roof(ci: CanvasItem, c: Vector2, r: float, col: Color, fine: bool) -> void:
	ci.draw_circle(c, r, col.darkened(0.3))
	ci.draw_circle(c, r * 0.86, col)
	if fine:
		ci.draw_arc(c, r * 0.55, 0, TAU, 16, col.darkened(0.15), maxf(r * 0.08, 1.0))
		ci.draw_circle(c, r * 0.16, col.darkened(0.5))


## The owner's shrine in the B_TEMPLE footprint, its front toward the agora.
static func _draw_shrine(ci: CanvasItem, a: Array, style: int, k: float, o: Vector2, ag: Vector2, fine: bool) -> void:
	var r0 := _p(o, k, a[0], a[1])
	var r1 := _p(o, k, a[2], a[3])
	var r := Rect2(r0, r1 - r0)
	var c := r.get_center()
	var agp := o + ag * k
	# Front: the side facing the agora.
	var to := agp - c
	var front := Vector2(0, signf(to.y) if absf(to.y) * r.size.x >= absf(to.x) * r.size.y else 0.0)
	if front == Vector2.ZERO:
		front = Vector2(signf(to.x), 0)
	var lw := maxf(k * 0.25, 1.0)
	var white := Color(0.95, 0.94, 0.9)
	match style:
		MapGen.CUL_LATIN:
			# Podium temple: stone podium, steps and a deep porch in front,
			# the cella under red tile behind.
			ci.draw_rect(r, STONE.lightened(0.25))
			ci.draw_rect(r, STONE_DARK, false, lw)
			var cella := r.grow(-k * 1.2)
			if front.y != 0.0:
				cella.size.y *= 0.6
				if front.y < 0.0:
					cella.position.y = r.end.y - k * 1.2 - cella.size.y
			else:
				cella.size.x *= 0.6
				if front.x < 0.0:
					cella.position.x = r.end.x - k * 1.2 - cella.size.x
			_gable_roof(ci, _rect_pts(cella), ROOF_STYLE[0], k, fine)
			# Porch columns in two rows along the front.
			var fe := c + front * Vector2(r.size.x, r.size.y) * 0.5
			var across := Vector2(absf(front.y), absf(front.x))
			var wide := (r.size.x if front.y != 0.0 else r.size.y) * 0.5 - k
			for row in 2:
				var base := fe - front * k * (1.2 + row * 2.0)
				var s := -wide
				while s <= wide + 0.01:
					ci.draw_circle(base + across * s, k * 0.4, white)
					s += 2.0 * k
			ci.draw_line(fe - across * wide, fe + across * wide, STONE_DARK, lw)
		MapGen.CUL_GREEK:
			# Colonnaded temple: a pale roof ringed by columns.
			ci.draw_rect(r, Color(0.88, 0.86, 0.80))
			_gable_roof(ci, _rect_pts(r.grow(-k * 1.4)), ROOF_STYLE[1].lightened(0.1), k, fine)
			var step := 2.0 * k
			var x := r.position.x + k * 0.7
			while x < r.end.x:
				ci.draw_circle(Vector2(x, r.position.y + k * 0.7), k * 0.38, white)
				ci.draw_circle(Vector2(x, r.end.y - k * 0.7), k * 0.38, white)
				x += step
			var y := r.position.y + k * 0.7 + step
			while y < r.end.y - step * 0.5:
				ci.draw_circle(Vector2(r.position.x + k * 0.7, y), k * 0.38, white)
				ci.draw_circle(Vector2(r.end.x - k * 0.7, y), k * 0.38, white)
				y += step
		MapGen.CUL_PUNIC:
			# Walled precinct (tophet): an open court, the shrine at the
			# back, an altar, a gate in the front wall.
			ci.draw_rect(r, Color(0.86, 0.80, 0.66))
			ci.draw_rect(r, Color(0.92, 0.90, 0.84), false, maxf(k * 0.9, 1.5))
			var back := c - front * Vector2(r.size.x, r.size.y) * 0.3
			var bs := Vector2(r.size.x, r.size.y) * Vector2(0.4 if front.y != 0.0 else 0.25, 0.25 if front.y != 0.0 else 0.4)
			_flat_roof(ci, _rect_pts(Rect2(back - bs * 0.5, bs)), ROOF_STYLE[2], k, fine)
			ci.draw_circle(c + front * Vector2(r.size.x, r.size.y) * 0.12, k * 0.8, Color(0.55, 0.40, 0.30))
			var fe2 := c + front * Vector2(r.size.x, r.size.y) * 0.5
			var across2 := Vector2(absf(front.y), absf(front.x))
			ci.draw_line(fe2 - across2 * k * 1.4, fe2 + across2 * k * 1.4, Color(0.45, 0.30, 0.18), maxf(k * 0.9, 1.5))
		_:
			# Celtic sacred enclosure: a ditched square with a palisade,
			# grass inside, posts and a sacred tree in the middle.
			ci.draw_rect(r, Color(0.40, 0.48, 0.28))
			ci.draw_rect(r, TIMBER_DARK, false, maxf(k * 0.8, 1.5))
			ci.draw_rect(r.grow(-k * 0.8), TIMBER, false, maxf(k * 0.35, 1.0))
			for q in 4:
				var ang := q * TAU / 4.0 + 0.6
				ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * minf(r.size.x, r.size.y) * 0.28, k * 0.45, TIMBER_DARK)
			ci.draw_circle(c, minf(r.size.x, r.size.y) * 0.16, Color(0.22, 0.36, 0.16))


static func _rect_pts(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


# --------------------------------------------------------------- walls ----

## A wall ring along a polygon (outer wall or the citadel's): shadow, stone
## body, dark parapet outside, walkway, merlons (or a timber palisade).
static func _draw_ring(ci: CanvasItem, lay: Dictionary, poly: PackedInt32Array, k: float, o: Vector2, fine: bool,
		palisade: bool) -> void:
	var nv := poly.size() / 2
	var t: float = lay["t"]
	var pp: float = lay["pp"]
	var inner: float = lay["inner"]
	var off: float = (inner - pp) * 0.5
	var area := 0.0
	for e in nv:
		var e2 := (e + 1) % nv
		area += float(poly[e * 2]) * poly[e2 * 2 + 1] - float(poly[e2 * 2]) * poly[e * 2 + 1]
	for e in nv:
		var a := Vector2(poly[e * 2], poly[e * 2 + 1])
		var b := Vector2(poly[((e + 1) % nv) * 2], poly[((e + 1) % nv) * 2 + 1])
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x) if area > 0.0 else Vector2(-d.y, d.x)  # outward
		if palisade:
			# Timber: a band of stakes with a fighting walk behind.
			_band(ci, a, b, n, t * 0.5 + 0.2, t * 0.5 + 1.2, Color(0, 0, 0, 0.25), k, o)
			_band(ci, a, b, n, t * 0.5, t * 0.5 + 0.45, Color(0.13, 0.10, 0.06, 0.5), k, o)
			_band(ci, a, b, n, -t * 0.5, t * 0.5, TIMBER.lightened(0.15), k, o)
			_band(ci, a, b, n, t * 0.5 - maxf(pp, 1.5), t * 0.5, TIMBER_DARK, k, o)
			if fine:
				var l0 := (b - a).length()
				var s0 := 0.6
				while s0 < l0:
					var m0 := a + d * s0 + n * (t * 0.5 - maxf(pp, 1.5) * 0.5)
					ci.draw_circle(o + m0 * k, k * 0.45, TIMBER)
					s0 += 1.2
			continue
		_band(ci, a, b, n, t * 0.5 + 0.2, t * 0.5 + 1.6, Color(0, 0, 0, 0.28), k, o)
		# The footing: a dark line of damp ground and rubble along the base.
		_band(ci, a, b, n, t * 0.5, t * 0.5 + 0.55, Color(0.11, 0.09, 0.07, 0.55), k, o)
		_band(ci, a, b, n, -t * 0.5 - 0.4, -t * 0.5, Color(0.11, 0.09, 0.07, 0.3), k, o)
		_band(ci, a, b, n, -t * 0.5, t * 0.5, STONE, k, o)
		_band(ci, a, b, n, t * 0.5 - pp, t * 0.5, STONE_DARK, k, o)
		_band(ci, a, b, n, off - MapGen.WALK_W * 0.5, off + MapGen.WALK_W * 0.5, WALK, k, o)
		if fine:
			var l := (b - a).length()
			var s := 1.0
			while s < l - 0.5:
				var m := a + d * s + n * (t * 0.5 - pp * 0.5)
				ci.draw_rect(Rect2(o + (m - Vector2(0.45, 0.45)) * k, Vector2(0.9, 0.9) * k), STONE.lightened(0.15))
				s += 2.0


static func _band(ci: CanvasItem, a: Vector2, b: Vector2, n: Vector2, o0: float, o1: float, col: Color, k: float,
		o: Vector2) -> void:
	ci.draw_colored_polygon(PackedVector2Array([o + (a + n * o0) * k, o + (b + n * o0) * k, o + (b + n * o1) * k,
		o + (a + n * o1) * k]), col)


## A tower: round, or square turned to its wall (timber for a palisade).
static func _draw_tower(ci: CanvasItem, tw: Array, k: float, o: Vector2, palisade: bool) -> void:
	var c := _p(o, k, tw[0], tw[1])
	var r: float = float(tw[2]) * k
	var sq := tw.size() > 3 and int(tw[3]) != 0
	var body := TIMBER.lightened(0.1) if palisade else STONE.lightened(0.05)
	var dark := TIMBER_DARK if palisade else STONE_DARK
	if not sq:
		ci.draw_circle(c + Vector2(1.2, 1.5) * k, r, Color(0, 0, 0, 0.3))
		ci.draw_circle(c, r + k * 0.55, Color(0.11, 0.09, 0.07, 0.5))
		ci.draw_circle(c, r, dark)
		ci.draw_circle(c, r * 0.82, body)
		ci.draw_circle(c, r * 0.45, WALK if not palisade else TIMBER)
		return
	var ang := float(int(tw[4])) * TAU / 1024.0 if tw.size() > 4 else 0.0
	var ex := Vector2(cos(ang), sin(ang))
	var ey := Vector2(-ex.y, ex.x)
	var sqp := func(f: float, off: Vector2) -> PackedVector2Array:
		return PackedVector2Array([c + off + (-ex - ey) * r * f, c + off + (ex - ey) * r * f,
			c + off + (ex + ey) * r * f, c + off + (-ex + ey) * r * f])
	ci.draw_colored_polygon(sqp.call(1.0, Vector2(1.2, 1.5) * k), Color(0, 0, 0, 0.3))
	ci.draw_colored_polygon(sqp.call(1.0 + 0.55 * k / maxf(r, 1.0), Vector2.ZERO), Color(0.11, 0.09, 0.07, 0.5))
	ci.draw_colored_polygon(sqp.call(1.0, Vector2.ZERO), dark)
	ci.draw_colored_polygon(sqp.call(0.8, Vector2.ZERO), body)
	ci.draw_colored_polygon(sqp.call(0.42, Vector2.ZERO), WALK if not palisade else TIMBER)


## Stairs at each end of a walkway stretch: a few treads across the wall's
## inner face (at the segment's stair points S).
static func _draw_stairs(ci: CanvasItem, lay: Dictionary, k: float, o: Vector2) -> void:
	var lw := maxf(k * 0.25, 1.0)
	for sg in lay["segs"]:
		var a: Array = sg
		if a.size() < MapGen.SEG_LEN:
			continue
		var d := Vector2(int(a[2]) - int(a[0]), int(a[3]) - int(a[1])).normalized()
		var ang := float(int(a[4])) * TAU / 1024.0
		var n := Vector2(cos(ang), sin(ang))
		for e in 2:
			var s := Vector2(int(a[7 + e * 6]), int(a[8 + e * 6]))
			for q in 4:
				var c := s + n * (float(q) - 1.5) * 0.7
				ci.draw_line(o + (c - d * 1.6) * k, o + (c + d * 1.6) * k, Color(0.78, 0.74, 0.66), lw)


## The sea gate (scenery): an arch across the sea wall, two small towers.
static func _draw_sea_gate(ci: CanvasItem, lay: Dictionary, g: Array, k: float, o: Vector2) -> void:
	var t: float = lay["t"]
	var ang := float(int(g[2])) * TAU / 1024.0
	var n := Vector2(cos(ang), sin(ang))
	var e := Vector2(-n.y, n.x)
	var c := Vector2(g[0], g[1])
	var hw := 3.0
	var pts := PackedVector2Array([o + (c - e * hw - n * t * 0.5) * k, o + (c + e * hw - n * t * 0.5) * k,
		o + (c + e * hw + n * t * 0.5) * k, o + (c - e * hw + n * t * 0.5) * k])
	ci.draw_colored_polygon(pts, Color(0.22, 0.30, 0.36))
	for q in range(-2, 3):
		var a := c + e * (q * hw / 2.5)
		ci.draw_line(o + (a - n * t * 0.3) * k, o + (a + n * t * 0.3) * k, Color(0.12, 0.12, 0.12), maxf(k * 0.2, 1.0))
	for s in [-1.0, 1.0]:
		var tc: Vector2 = c + e * (hw + t * 0.5) * s
		ci.draw_circle(o + tc * k, t * 0.5 * k, STONE_DARK)
		ci.draw_circle(o + tc * k, t * 0.4 * k, STONE.lightened(0.05))


## Banners: on a tower of each outer gate, by the citadel's gate and at a
## corner of the agora.
static func _draw_banners(ci: CanvasItem, lay: Dictionary, k: float, o: Vector2, col: Color) -> void:
	var spots: Array = []
	for gd in lay["gates"]:
		var ang := float(int(gd["dir"])) * TAU / 1024.0
		var e := Vector2(-sin(ang), cos(ang))
		var off := float(int(gd["hw"]) + int(gd["tr"])) if gd.has("hw") else float(MapGen.GATE_HW + int(lay["t"]) / 2 + 1)
		spots.append(Vector2(gd["x"], gd["y"]) + e * off)
	var ag: Array = lay.get("agora", lay["plaza"])
	spots.append(Vector2(int(ag[0]) + int(ag[2]) - 1, int(ag[1]) - int(ag[2]) + 1))
	var cit: Dictionary = lay.get("cit", {})
	if not cit.is_empty():
		spots.append(Vector2(cit["x"], cit["y"]))
	var s := maxf(k, 1.6)
	for sp in spots:
		var base: Vector2 = o + (sp as Vector2) * k
		var top := base + Vector2(0, -3.4) * s
		ci.draw_line(base, top, Color(0.15, 0.12, 0.1), maxf(s * 0.25, 1.0))
		var flag := PackedVector2Array([top, top + Vector2(2.6, 0.5) * s, top + Vector2(0, 1.5) * s])
		ci.draw_colored_polygon(flag, col)
		flag.append(top)
		ci.draw_polyline(flag, col.darkened(0.5), maxf(s * 0.12, 1.0))


# --------------------------------------------------------------- gates ----

## Gate g: passage floor, then closed (timber and iron), open (leaves swung
## in) or broken (splinters and rubble); an outline flash when struck. A
## postern is narrower; the citadel's gate has no towers of its own.
static func draw_gate(ci: CanvasItem, lay: Dictionary, g: int, st: int, hit: bool, _tick: int, k: float,
		o: Vector2) -> void:
	var gd: Dictionary = lay["gates"][g]
	var t: float = lay["t"]
	var hw := float(int(gd.get("hw", MapGen.GATE_HW)))
	var ang: float = int(gd["dir"]) * TAU / 1024.0
	var n := Vector2(cos(ang), sin(ang))
	var e := Vector2(-n.y, n.x)
	var c := Vector2(gd["x"], gd["y"])
	var pts := PackedVector2Array([o + (c - e * hw - n * t * 0.5) * k, o + (c + e * hw - n * t * 0.5) * k,
		o + (c + e * hw + n * t * 0.5) * k, o + (c - e * hw + n * t * 0.5) * k])
	ci.draw_colored_polygon(pts, Color(0.52, 0.48, 0.42))  # passage floor
	# Wheel ruts worn along the passage.
	for rs in [-0.45, 0.45]:
		ci.draw_line(o + (c + e * hw * rs - n * t * 0.5) * k, o + (c + e * hw * rs + n * t * 0.5) * k,
			Color(0.25, 0.2, 0.15, 0.3), maxf(k * 0.5, 1.0))
	if st == BattleSim.GATE_CLOSED:
		var door := PackedVector2Array([o + (c - e * hw - n * 0.9) * k, o + (c + e * hw - n * 0.9) * k,
			o + (c + e * hw + n * 0.9) * k, o + (c - e * hw + n * 0.9) * k])
		ci.draw_colored_polygon(door, Color(0.36, 0.22, 0.12))
		var nb := 3 if hw >= 3.0 else 1
		for q in range(-nb, nb + 1):
			var a := c + e * (q * hw / (nb + 1.0))
			ci.draw_line(o + (a - n * 0.9) * k, o + (a + n * 0.9) * k, Color(0.22, 0.13, 0.07), maxf(k * 0.12, 1.0))
		for q2 in [-0.5, 0.5]:
			ci.draw_line(o + (c - e * hw + n * q2) * k, o + (c + e * hw + n * q2) * k, Color(0.15, 0.15, 0.15), maxf(k * 0.2, 1.0))
		# Planks of alternate shades, studs on the iron straps.
		for q3 in range(-nb, nb):
			var pa := c + e * ((q3 + 0.5) * hw / (nb + 1.0))
			ci.draw_line(o + (pa - n * 0.8) * k, o + (pa + n * 0.8) * k, Color(0.45, 0.29, 0.16, 0.5) if q3 % 2 == 0 else Color(0.28, 0.17, 0.09, 0.4),
				maxf(k * hw / (nb + 1.0) * 0.9, 1.0))
		for q4 in range(-nb, nb + 1):
			for q2b in [-0.5, 0.5]:
				ci.draw_circle(o + (c + e * (q4 * hw / (nb + 1.0)) + n * q2b) * k, maxf(k * 0.14, 0.8), Color(0.55, 0.55, 0.58))
	elif st == BattleSim.GATE_OPEN:
		for s in [-1.0, 1.0]:
			var hinge: Vector2 = c + e * hw * s - n * 0.6
			ci.draw_line(o + hinge * k, o + (hinge - n * hw * 0.9) * k, Color(0.36, 0.22, 0.12), k * 0.6)
	else:
		for q in 14:
			var hx := float((g * 37 + q * 53) % 17) / 17.0 * 2.0 - 1.0
			var hy := float((g * 11 + q * 29) % 13) / 13.0 * 2.0 - 1.0
			var at: Vector2 = c + e * hx * hw * 0.9 + n * hy * (t * 0.5 + 2.0)
			var col := Color(0.36, 0.22, 0.12) if q % 3 != 0 else Color(0.5, 0.48, 0.44)
			var sz := (0.5 + float(q % 4) * 0.25) * k
			ci.draw_rect(Rect2(o + at * k - Vector2(sz, sz * 0.5), Vector2(sz * 2.0, sz)), col)
	# Timber frame: a post either side of the passage and a lintel beam over
	# its outer mouth.
	var post := Color(0.30, 0.20, 0.11)
	for sd in [-1.0, 1.0]:
		for nn in [-1.0, 1.0]:
			var pc: Vector2 = c + e * (hw + 0.4) * sd + n * (t * 0.5 - 0.2) * nn
			ci.draw_rect(Rect2(o + (pc - Vector2(0.45, 0.45)) * k, Vector2(0.9, 0.9) * k), post)
	ci.draw_line(o + (c - e * (hw + 0.4) + n * (t * 0.5 - 0.2)) * k, o + (c + e * (hw + 0.4) + n * (t * 0.5 - 0.2)) * k,
		post.lightened(0.1), maxf(k * 0.7, 1.0))
	if hit:
		ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			Color(1.0, 0.65, 0.2, 0.9), maxf(k * 0.4, 1.5))


# --------------------------------------------------------- surroundings ----

static var _plan_key := -1
static var _plan := {}

## A deterministic hash in 0..1 of up to three integers and a salt.
static func _h01(a: int, b: int, c: int, salt: int) -> float:
	var x := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (salt * 2654435761)
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65535.0


static func _in_poly(poly: PackedInt32Array, x: float, y: float) -> bool:
	var inside := false
	var nv := poly.size() / 2
	var j := nv - 1
	for i in nv:
		var xi := float(poly[i * 2])
		var yi := float(poly[i * 2 + 1])
		var xj := float(poly[j * 2])
		var yj := float(poly[j * 2 + 1])
		if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
			inside = not inside
		j = i
	return inside


## What lies outside a settlement on the battle map (view only, laid out once
## per battle from the map's hash and cached by the sim): "tracks" (polylines
## in metres from each outer gate to the map edge), "fields" ([cx, cy, w, h,
## angle, kind] in metres; kind 0 ploughed, 1 crop, 2 stubble, 3 fallow) and
## "orchards" (Rect2 in metres; the tree layer plants the rows). The sim's
## vegetation grid (sim.veg, 4 m cells) tells where the ground is clear.
static func plan_surround(sim) -> Dictionary:
	var id: int = sim.get_instance_id()
	if id == _plan_key:
		return _plan
	var out := {"tracks": [], "fields": [], "orchards": [], "mask": PackedByteArray()}
	_plan_key = id
	_plan = out
	if sim.city_on == 0 or not sim.map_info.has("city") or sim.veg_w <= 0 or sim.veg.size() < sim.veg_w * sim.veg_h:
		return out
	var lay: Dictionary = sim.map_info["city"]
	var vw: int = sim.veg_w
	var vh: int = sim.veg_h
	var veg: PackedByteArray = sim.veg
	var fw_m: float = sim.field_w / 1024.0
	var fh_m: float = sim.field_h / 1024.0
	var sd0 := int(sim.ter_hash) & 0xFFFFFF
	var poly: PackedInt32Array = lay["poly"]
	var t: float = lay["t"] if lay.has("t") else 4.0
	var taken := PackedByteArray()
	taken.resize(vw * vh)
	out["mask"] = taken  # cells under tracks and fields (the tree layer keeps its cover off them)
	# --- dirt tracks from the outer gates.
	var gi := 0
	for gd in lay["gates"]:
		gi += 1
		var ang := float(int(gd["dir"])) * TAU / 1024.0
		var n := Vector2(cos(ang), sin(ang))
		var c := Vector2(gd["x"], gd["y"])
		if _in_poly(poly, c.x + n.x * (t * 0.5 + 10.0), c.y + n.y * (t * 0.5 + 10.0)):
			continue  # an inner gate (the citadel's)
		var cur := PackedVector2Array()
		var p := c
		var ph := _h01(sd0, gi, 1, 7) * TAU
		for step in 330:
			var env := minf(float(step) / 12.0, 1.0)
			var a := ang + (0.17 * sin(step * 0.078 + ph) + 0.08 * sin(step * 0.19 + ph * 2.0)) * env
			p += Vector2(cos(a), sin(a)) * 3.0
			if p.x < -6.0 or p.y < -6.0 or p.x > fw_m + 6.0 or p.y > fh_m + 6.0:
				break
			var ci_ := clampi(int(p.x / 4.0), 0, vw - 1)
			var cj_ := clampi(int(p.y / 4.0), 0, vh - 1)
			var b: int = veg[cj_ * vw + ci_]
			if (b & MapGen.V_WATER) != 0:
				break
			if (b & MapGen.V_DITCH) != 0:
				if cur.size() >= 2:
					out["tracks"].append(cur)
				cur = PackedVector2Array()
				continue
			if cur.is_empty():
				cur.append(p - Vector2(cos(a), sin(a)) * 3.0)
			cur.append(p)
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ti := ci_ + di
					var tj := cj_ + dj
					if ti >= 0 and tj >= 0 and ti < vw and tj < vh:
						taken[tj * vw + ti] = 1
		if cur.size() >= 2:
			out["tracks"].append(cur)
	# --- clear ground beyond the walls: a window round the settlement.
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for q in poly.size() / 2:
		lo = lo.min(Vector2(poly[q * 2], poly[q * 2 + 1]))
		hi = hi.max(Vector2(poly[q * 2], poly[q * 2 + 1]))
	var i0 := maxi(int((lo.x - 130.0) / 4.0), 0)
	var i1 := mini(int((hi.x + 130.0) / 4.0), vw - 1)
	var j0 := maxi(int((lo.y - 130.0) / 4.0), 0)
	var j1 := mini(int((hi.y + 130.0) / 4.0), vh - 1)
	var ww := i1 - i0 + 1
	var wh := j1 - j0 + 1
	if ww <= 2 or wh <= 2:
		return out
	# Chamfer distance (3 per cell, 4 diagonal) to the nearest settlement or
	# ditch cell.
	const FAR := 9999
	var dist := PackedInt32Array()
	dist.resize(ww * wh)
	for j in wh:
		for i in ww:
			var b2: int = veg[(j0 + j) * vw + i0 + i]
			dist[j * ww + i] = 0 if (b2 & (MapGen.V_URBAN | MapGen.V_DITCH)) != 0 else FAR
	for j in wh:
		for i in ww:
			var d: int = dist[j * ww + i]
			if i > 0:
				d = mini(d, dist[j * ww + i - 1] + 3)
			if j > 0:
				d = mini(d, dist[(j - 1) * ww + i] + 3)
				if i > 0:
					d = mini(d, dist[(j - 1) * ww + i - 1] + 4)
				if i < ww - 1:
					d = mini(d, dist[(j - 1) * ww + i + 1] + 4)
			dist[j * ww + i] = d
	for j in range(wh - 1, -1, -1):
		for i in range(ww - 1, -1, -1):
			var d2: int = dist[j * ww + i]
			if i < ww - 1:
				d2 = mini(d2, dist[j * ww + i + 1] + 3)
			if j < wh - 1:
				d2 = mini(d2, dist[(j + 1) * ww + i] + 3)
				if i < ww - 1:
					d2 = mini(d2, dist[(j + 1) * ww + i + 1] + 4)
				if i > 0:
					d2 = mini(d2, dist[(j + 1) * ww + i - 1] + 4)
			dist[j * ww + i] = d2
	# Exclusions (metres): deployment zones, the attackers' approach, siege
	# equipment.
	var avoid: Array = []  # Rect2
	for z in range(0, sim.dep_z.size(), 6):
		avoid.append(Rect2(sim.dep_z[z + 2] / 1024.0 - 8.0, sim.dep_z[z + 3] / 1024.0 - 8.0,
			(sim.dep_z[z + 4] - sim.dep_z[z + 2]) / 1024.0 + 16.0, (sim.dep_z[z + 5] - sim.dep_z[z + 3]) / 1024.0 + 16.0))
	if lay.has("att_x"):
		avoid.append(Rect2(float(lay["att_x"]) - 45.0, float(lay["att_y"]) - 45.0, 90.0, 90.0))
	for q in sim.n_eq:
		avoid.append(Rect2(sim.q_x[q] / 1024.0 - 16.0, sim.q_y[q] / 1024.0 - 16.0, 32.0, 32.0))
	var cap := mini(14 + (lay["buildings"] as Array).size() / 5, 70)
	var orch_n := 0
	var fields: Array = out["fields"]
	var step_m := 20.0
	var gx0 := floorf(float(i0 * 4) / step_m) * step_m
	var gy0 := floorf(float(j0 * 4) / step_m) * step_m
	var gx := gx0
	while gx <= float(i1 * 4 + 4) and fields.size() + (out["orchards"] as Array).size() < cap:
		var gy := gy0
		while gy <= float(j1 * 4 + 4):
			var ix := int(gx / step_m)
			var iy := int(gy / step_m)
			var cx := gx + _h01(ix, iy, sd0, 11) * step_m
			var cy := gy + _h01(ix, iy, sd0, 12) * step_m
			gy += step_m
			var ci_ := int(cx / 4.0) - i0
			var cj_ := int(cy / 4.0) - j0
			if ci_ < 0 or cj_ < 0 or ci_ >= ww or cj_ >= wh:
				continue
			var dm := float(dist[cj_ * ww + ci_]) / 3.0 * 4.0  # metres from the settlement
			if dm < 26.0 or dm > 120.0:
				continue
			if _h01(ix, iy, sd0, 13) > 0.62 - (dm - 26.0) / 220.0:
				continue
			var w := 16.0 + _h01(ix, iy, sd0, 14) * 18.0
			var h := 10.0 + _h01(ix, iy, sd0, 15) * 12.0
			if _h01(ix, iy, sd0, 16) < 0.4:
				var sw := w
				w = h + 4.0
				h = sw - 4.0
			var rc := Rect2(cx - w * 0.5 - 3.0, cy - h * 0.5 - 3.0, w + 6.0, h + 6.0)
			if rc.position.x < 4.0 or rc.position.y < 4.0 or rc.end.x > fw_m - 4.0 or rc.end.y > fh_m - 4.0:
				continue
			var bad := false
			for av in avoid:
				if (av as Rect2).intersects(rc):
					bad = true
					break
			if bad:
				continue
			var ci0 := int(rc.position.x / 4.0)
			var ci1 := int(rc.end.x / 4.0)
			var cj0 := int(rc.position.y / 4.0)
			var cj1 := int(rc.end.y / 4.0)
			for jj in range(cj0, cj1 + 1):
				if bad:
					break
				for ii in range(ci0, ci1 + 1):
					var bb: int = veg[jj * vw + ii]
					if (bb & (MapGen.V_DENS | MapGen.V_URBAN | MapGen.V_FIELD | MapGen.V_ROAD | MapGen.V_PLAZA | MapGen.V_WATER | MapGen.V_DITCH)) != 0 or taken[jj * vw + ii] != 0:
						bad = true
						break
			if bad:
				continue
			if sim.ter_on != 0:
				var hmin := 1e9
				var hmax := -1e9
				for pt in [Vector2(rc.position.x, rc.position.y), Vector2(rc.end.x, rc.position.y), Vector2(rc.position.x, rc.end.y),
						rc.end, Vector2(cx, cy)]:
					var hh: float = sim.height_at(int((pt as Vector2).x * 1024.0), int((pt as Vector2).y * 1024.0)) / 1024.0
					hmin = minf(hmin, hh)
					hmax = maxf(hmax, hh)
				if hmax - hmin > 2.2:
					continue
			for jj in range(cj0, cj1 + 1):
				for ii in range(ci0, ci1 + 1):
					taken[jj * vw + ii] = 1
			if _h01(ix, iy, sd0, 17) < 0.17 and orch_n < 7 and w >= 18.0 and h >= 12.0:
				orch_n += 1
				(out["orchards"] as Array).append(Rect2(cx - w * 0.5, cy - h * 0.5, w, h))
				continue
			var r := _h01(ix, iy, sd0, 18)
			fields.append([cx, cy, w, h, (_h01(ix, iy, sd0, 19) - 0.5) * 0.3, 0 if r < 0.4 else (1 if r < 0.65 else (2 if r < 0.88 else 3))])
		gx += step_m
	return out


## Draw plan_surround's tracks and fields (and the ground under the orchard
## rows) at scale k px a metre, offset o; `base` is the ground colour.
static func draw_surround(ci: CanvasItem, plan: Dictionary, k: float, o: Vector2, base: Color, _pal_i: int) -> void:
	var earth := base.lerp(Color(0.50, 0.40, 0.27), 0.62)
	for trk in plan.get("tracks", []):
		var pts := PackedVector2Array()
		for q in (trk as PackedVector2Array):
			pts.append(o + q * k)
		ci.draw_polyline(pts, Color(earth.r * 0.8, earth.g * 0.8, earth.b * 0.8, 0.35), 5.2 * k, true)
		ci.draw_polyline(pts, Color(earth.r, earth.g, earth.b, 0.8), 3.6 * k, true)
		ci.draw_polyline(pts, earth.lightened(0.14) * Color(1, 1, 1, 0.5), 1.3 * k, true)
	var plough := Color(0.42, 0.31, 0.20).lerp(base, 0.1)
	var crop := base.lerp(Color(0.46, 0.64, 0.25), 0.55)
	var stub := Color(0.72, 0.64, 0.38).lerp(base, 0.18)
	var fallow := base.lerp(Color(0.56, 0.56, 0.32), 0.4)
	var lw := maxf(k * 0.22, 1.0)
	for f in plan.get("fields", []):
		var fa: Array = f
		var w: float = fa[2]
		var h: float = fa[3]
		var kind := int(fa[5])
		var col: Color = plough if kind == 0 else (crop if kind == 1 else (stub if kind == 2 else fallow))
		ci.draw_set_transform(o + Vector2(fa[0], fa[1]) * k, float(fa[4]), Vector2.ONE)
		var r := Rect2(Vector2(-w, -h) * 0.5 * k, Vector2(w, h) * k)
		ci.draw_rect(r.grow(k * 0.6), Color(col.r * 0.8, col.g * 0.85, col.b * 0.75, 0.45))  # hedge / headland
		ci.draw_rect(r, col)
		var line := col.darkened(0.28) if kind != 2 else col.lightened(0.12)
		if kind == 1:
			line = col.lightened(0.18)
		var yy := -h * 0.5 + 0.9
		while yy < h * 0.5 - 0.3:
			ci.draw_line(Vector2(-w * 0.5, yy) * k, Vector2(w * 0.5, yy) * k, Color(line.r, line.g, line.b, 0.7 if kind != 3 else 0.25), lw)
			yy += 1.5
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for oc in plan.get("orchards", []):
		var rr: Rect2 = oc
		ci.draw_rect(Rect2(o + rr.position * k, rr.size * k), base.darkened(0.07) * Color(1, 1, 1, 0.55))
