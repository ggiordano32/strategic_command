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
	ci.draw_rect(pr, Color(0.3, 0.27, 0.22, 0.55), false, maxf(k * 0.35, 1.0))
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
	var sh := Vector2(0.9, 1.1) * k
	for b in lay["buildings"]:
		var a: Array = b
		var shape := int(a[6]) if a.size() > 6 else MapGen.SH_RECT
		if shape == MapGen.SH_ROUND:
			ci.draw_circle(_p(o, k, a[7], a[8]) + sh, float(a[9]) * k, SHADOW)
		elif shape == MapGen.SH_QUAD:
			var pts := PackedVector2Array()
			for q in 4:
				pts.append(_p(o, k, a[7 + q * 2], a[8 + q * 2]) + sh)
			ci.draw_colored_polygon(pts, SHADOW)
		else:
			ci.draw_rect(Rect2(_p(o, k, a[0], a[1]) + sh, Vector2(int(a[2]) - int(a[0]), int(a[3]) - int(a[1])) * k), SHADOW)
	var ag: Array = lay.get("agora", lay["plaza"])
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
	if fine:
		ci.draw_line(m0, m1, col.darkened(0.35), maxf(k * 0.25, 1.0))
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
	if hit:
		ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			Color(1.0, 0.65, 0.2, 0.9), maxf(k * 0.4, 1.5))
