extends RefCounted
## The settlement miniatures' footprint painted into the overworld land (map-table style, view only):
## around each town a feathered clearing (lawn / packed earth / sand), a street cross, soft contact shadow
## and AO under the buildings (north-west light, so the shadow falls south-east), a few furrowed fields
## and an orchard radiating outward, tracks out to the nearest roads, and for harbour towns a sand apron
## and a stone quay where the land meets the sea. Fields and orchards stay on land (the coast field).
## The sprites (tools/structures) have no ground of their own. Drawn by map_view.gd on the map item
## (world pixels) after the trees and before the roads; sizes follow the miniatures (minis_layer.gd):
## screen width about 88 px x sqrt(zoom) for 58 m. Quality Low: one feather ring, 2 fields, no furrows.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CSea := preload("res://campaign/csea.gd")
const MapGen := preload("res://sim/mapgen.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const GeoFields := preload("res://game/campaign/geo_fields.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const Quality := preload("res://game/quality.gd")

const MIN_ZOOM := 0.55
const TILE_M := 58.0
const LEVEL_K := [0.9, 1.0, 1.14]
const SHADOW := Color(0.16, 0.10, 0.04)
const DIRT := Color(0.78, 0.66, 0.44)
const LAWN := Color(0.60, 0.74, 0.34)
const LAWN_DK := Color(0.45, 0.62, 0.27)
const SANDC := Color(0.93, 0.85, 0.62)
const STONE := Color(0.80, 0.75, 0.62)
const CROPS := [Color(0.88, 0.77, 0.38), Color(0.66, 0.78, 0.34), Color(0.69, 0.52, 0.31), Color(0.80, 0.70, 0.36)]

static var _coast := PackedByteArray()
static var _cw := 0
static var _ch := 0
static var _spx := 1.0


static func _sync() -> void:
	if _cw == GeoFields.fine_width() and _coast.size() > 0:
		return
	_coast = GeoFields.coast()
	_cw = GeoFields.fine_width()
	_ch = GeoFields.fine_height()
	_spx = GeoFields.sample_px()


## Signed distance to the coast in km at world point p (sea positive).
static func _d(p: Vector2) -> float:
	var ix := clampi(int(p.x / _spx), 0, _cw - 1)
	var iy := clampi(int(p.y / _spx), 0, _ch - 1)
	return float(_coast[iy * _cw + ix]) - 128.0


static func _land(p: Vector2, margin := 1.0) -> bool:
	return _d(p) < -margin


static func tile_px(zoom: float) -> float:
	return 88.0 * sqrt(maxf(zoom, 0.05))


static func kind_of(st: Dictionary, r: int) -> String:
	var lvl := int(st["regions"][r]["level"])
	var cul := CState.owner_culture(st, r)
	if CData.pack == "west":
		if CSea.haven(st, r):
			return "haven"
		if cul == MapGen.CUL_CELTIC:
			return "maya" if str(CData.REGIONS[r]["key"]) == "tayasal" else "native"
		return "town_" + "sml"[clampi(lvl, 0, 2)]
	return "rtown_" + "sml"[clampi(lvl, 0, 2)]


static func site_point(r: int, grid: bool) -> Vector2:
	if grid:
		var c := CGrid.site(r)
		var px := float(CGrid.cell_px())
		return Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px)
	return Geo.site(r)


## An irregular closed outline: radius rx / ry (squashed) with a smooth wobble, vertices pulled in until
## they are on land.
static func _blob(rng: RandomNumberGenerator, c: Vector2, rx: float, ky: float, n: int, wob: float, on_land := true) -> PackedVector2Array:
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		var k := 1.0 + wob * (sin(a * 2.0 + ph1) * 0.6 + sin(a * 3.0 + ph2) * 0.4)
		var q := Vector2(cos(a) * rx * k, sin(a) * rx * k * ky)
		var tries := 0
		while on_land and tries < 6 and not _land(c + q, 0.0):
			q *= 0.82
			tries += 1
		pts.append(c + q)
	return pts


static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
		ci.draw_colored_polygon(pts, col)


static func _scaled(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var o := PackedVector2Array()
	for p in pts:
		o.append(c + (p - c) * k)
	return o


## A soft blob: feather rings (outer faint to the core), each a scaled copy of the outline.
static func _soft(ci: CanvasItem, pts: PackedVector2Array, c: Vector2, col: Color, rings: int, spread: float) -> void:
	for i in rings:
		var f := float(i) / float(maxi(rings, 1))
		var k := 1.0 + spread * (1.0 - f)
		var cc := col
		cc.a = col.a * (0.5 if rings > 1 else 1.0)
		_poly(ci, _scaled(pts, c, k), cc)


static func _soft_ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, rings: int) -> void:
	for i in rings:
		var f := float(rings - i) / float(rings)
		var pts := PackedVector2Array()
		for j in 20:
			var a := TAU * float(j) / 20.0
			pts.append(c + Vector2(cos(a) * rx * (0.55 + 0.45 * f), sin(a) * ry * (0.55 + 0.45 * f)))
		var cc := col
		cc.a = col.a / float(rings)
		_poly(ci, pts, cc)


static func _quad(c: Vector2, along: Vector2, hl: float, hw: float, rng: RandomNumberGenerator, jit: float) -> PackedVector2Array:
	var nrm := Vector2(-along.y, along.x)
	var pts := PackedVector2Array()
	for sgn in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		var q: Vector2 = c + along * hl * float(sgn[0]) + nrm * hw * float(sgn[1])
		q += Vector2(rng.randf_range(-jit, jit), rng.randf_range(-jit, jit)) * hw
		pts.append(q)
	return pts


static func _lane(ci: CanvasItem, pts: PackedVector2Array, w: float, col: Color, lw: float) -> void:
	var edge := col
	edge.a *= 0.35
	ci.draw_polyline(pts, edge, w * 1.9 + lw, true)
	ci.draw_polyline(pts, col, w, true)


## Draws every settlement's footprint (those within `area`, world px, when it is set). roads: the map's road polylines (world px).
static func draw(ci: CanvasItem, st: Dictionary, zoom: float, grid: bool, roads: Array, lw: float, area := Rect2()) -> void:
	if zoom < MIN_ZOOM or st.is_empty():
		return
	_sync()
	var low := Quality.is_low()
	var base := tile_px(zoom) / zoom / TILE_M   # world px a metre
	for r in CData.region_count():
		var c := site_point(r, grid)
		if area.size.x > 0.0 and not area.grow(70.0 * base).has_point(c):
			continue
		var u := base * float(LEVEL_K[clampi(int(st["regions"][r]["level"]), 0, 2)])
		_site(ci, st, r, c, u, low, roads, lw)


static func _site(ci: CanvasItem, st: Dictionary, r: int, c: Vector2, u: float, low: bool, roads: Array, lw: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (r + 3)
	var kind := kind_of(st, r)
	var lvl := int(st["regions"][r]["level"])
	var native := kind == "native" or kind == "maya"
	var haven := kind == "haven"
	var ky := 0.74
	var rings := 1 if low else 3
	# Sea direction (nearest shore within 80 m) for the quay.
	var sea_dir := Vector2.ZERO
	var sea_hit := 1e9
	if CData.pack == "west" and (haven or CFleet.harbour(r) >= 0):
		for i in 16:
			var a := TAU * float(i) / 16.0
			var dv := Vector2(cos(a), sin(a))
			for s in range(8, 90, 6):
				if not _land(c + dv * float(s) * u, -0.2):
					if float(s) < sea_hit:
						sea_hit = float(s)
						sea_dir = dv
					break
	# Fields and orchard first (so the clearing is over their inner ends).
	var spots: Array = []   # [centre, radius m]
	var nf := (2 if lvl == 0 else (3 if lvl == 1 else 4))
	if native:
		nf = 2 if kind == "native" else 3
	if haven:
		nf = 1
	if low:
		nf = mini(nf, 2)
	var n_orch := 0 if (haven or low or native) else (1 if lvl < 2 else 2)
	var a0 := rng.randf() * TAU
	var placed := 0
	var tries := 0
	var crop_i := rng.randi() % 4
	var made: Array = []
	while placed < nf + n_orch and tries < 28:
		tries += 1
		var a := a0 + float(tries) * 2.399 + rng.randf_range(-0.3, 0.3)   # golden angle
		var dist := rng.randf_range(37.0, 48.0)
		var along := Vector2(cos(a), sin(a))
		if sea_dir != Vector2.ZERO and along.dot(sea_dir) > 0.55:
			continue
		var hl := rng.randf_range(11.0, 15.0)
		var hw := rng.randf_range(7.0, 10.0)
		var ctr := c + Vector2(cos(a), sin(a) * 0.86) * dist * u
		var ok := true
		for o in spots:
			if ctr.distance_to(o[0]) < (hl + o[1]) * 1.05 * u:
				ok = false
				break
		if not ok:
			continue
		var rot := Vector2(cos(a + PI * 0.5 + rng.randf_range(-0.5, 0.5)), sin(a + PI * 0.5) * 0.86)
		rot = rot.normalized()
		var quad := _quad(ctr, rot * u, hl, hw, rng, 0.10)
		var corners_ok := true
		for q in quad:
			if not _land(q, 0.2):
				corners_ok = false
		if not corners_ok or not _land(ctr, 0.2):
			continue
		spots.append([ctr, hl])
		made.append([quad, ctr, rot, hl, hw, placed >= nf])
		placed += 1
	# Tracks (under the clearing): to the nearest road points, and a lane to each field.
	var track := Color(0.70, 0.58, 0.38, 0.85)
	var picked: Array = []
	if not roads.is_empty():
		var best: Array = []
		for ln in roads:
			var pl: PackedVector2Array = ln
			var bd := 1e9
			var bp := Vector2.ZERO
			for p in pl:
				var dd := p.distance_to(c)
				if dd > 30.0 * u and dd < bd:
					bd = dd
					bp = p
			if bd < 150.0 * u:
				best.append([bd, bp])
		best.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for b in best:
			var dv: Vector2 = (b[1] - c).normalized()
			var fine := true
			for q in picked:
				if dv.dot(q) > 0.5:
					fine = false
			if fine:
				picked.append(dv)
				var mid: Vector2 = c + (b[1] - c) * 0.5 + Vector2(-dv.y, dv.x) * rng.randf_range(-5.0, 5.0) * u
				_lane(ci, PackedVector2Array([c, mid, b[1]]), 2.1 * u, track, lw)
			if picked.size() >= 2:
				break
	for m in made:
		var ctr: Vector2 = m[1]
		_lane(ci, PackedVector2Array([c, c.lerp(ctr, 0.55) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)) * u, ctr]), 1.3 * u, track, lw)
	# Fields and orchards.
	for m in made:
		var quad: PackedVector2Array = m[0]
		var ctr: Vector2 = m[1]
		var rot: Vector2 = m[2]
		var hl: float = m[3]
		var hw: float = m[4]
		var shadow := SHADOW
		shadow.a = 0.14
		var qs := PackedVector2Array()
		for q in quad:
			qs.append(q + Vector2(1.3, 1.3) * u)
		_poly(ci, qs, shadow)
		if m[5]:
			# orchard: lawn, a grid of trees with tiny shadows
			_poly(ci, quad, Color(0.55, 0.70, 0.32))
			var nrm := Vector2(-rot.y, rot.x)
			var rows := 3
			var cols := 4
			for i in cols:
				for j in rows:
					var tp := ctr + rot * ((float(i) - (cols - 1) * 0.5) * hl * 0.48) * u + nrm * ((float(j) - (rows - 1) * 0.5) * hw * 0.62) * u
					var sh := SHADOW
					sh.a = 0.22
					ci.draw_circle(tp + Vector2(1.0, 1.1) * u, 1.9 * u, sh)
					ci.draw_circle(tp, 1.9 * u, Color(0.30, 0.52, 0.22))
					ci.draw_circle(tp + Vector2(-0.5, -0.6) * u, 1.0 * u, Color(0.46, 0.68, 0.30))
		else:
			var col: Color = CROPS[(crop_i + int(ctr.x * 0.37)) & 3]
			_poly(ci, quad, col)
			if not low:
				var fur := col.darkened(0.22)
				fur.a = 0.55
				var nrm := Vector2(-rot.y, rot.x)
				var nline := 7
				for k in nline:
					var off := (float(k) + 0.5) / float(nline) * 2.0 - 1.0
					var p0: Vector2 = ctr + nrm * off * hw * u * 0.9 - rot * hl * u * 0.92
					var p1: Vector2 = ctr + nrm * off * hw * u * 0.9 + rot * hl * u * 0.92
					ci.draw_line(p0, p1, fur, maxf(0.7 * u, lw * 0.9))
		var hedge := Color(0.28, 0.40, 0.18, 0.55)
		var closed := quad.duplicate()
		closed.append(quad[0])
		ci.draw_polyline(closed, hedge, maxf(0.6 * u, lw * 0.8), true)
	# Quay: sand apron and a stone slab where the land meets the sea.
	if sea_dir != Vector2.ZERO:
		var nrm := Vector2(-sea_dir.y, sea_dir.x)
		var sh := sea_hit * u
		var ap := PackedVector2Array([c + sea_dir * 12.0 * u + nrm * 11.0 * u, c + sea_dir * (sh - 0.8 * u) + nrm * 15.0 * u,
			c + sea_dir * (sh - 0.8 * u) - nrm * 15.0 * u, c + sea_dir * 12.0 * u - nrm * 11.0 * u])
		var sc := SANDC
		sc.a = 0.85
		_soft(ci, ap, c + sea_dir * sh * 0.5, sc, rings, 0.18)
		var quay := _quad(c + sea_dir * (sh - 3.2 * u), sea_dir * u, 3.0, 9.0, rng, 0.04)
		_poly(ci, quay, STONE)
		var qe := quay.duplicate()
		qe.append(quay[0])
		ci.draw_polyline(qe, Color(0.35, 0.28, 0.18, 0.5), maxf(0.6 * u, lw * 0.8), true)
	# The clearing: feathered lawn (sand for a haven), packed earth under the town, the street cross.
	var rad := 41.0 if not native else 37.0
	var blob := _blob(rng, c, rad * u, ky, 18, 0.10)
	var ground := SANDC if haven else (DIRT if native else LAWN)
	ground.a = 0.9
	_soft(ci, blob, c, ground, rings, 0.20)
	var earth := _blob(rng, c, (26.0 if kind != "maya" else 20.0) * u, ky, 16, 0.12)
	var ec := STONE if kind == "maya" else DIRT
	ec.a = 0.95
	_soft(ci, earth, c, ec, rings, 0.16)
	if kind.begins_with("town") or kind.begins_with("rtown"):
		var cob := DIRT.lightened(0.12) if not kind.begins_with("rtown") else STONE
		cob.a = 0.9
		var w := 5.0 * u
		var street := PackedVector2Array([c + Vector2(-30.0, 0.0) * u, c + Vector2(30.0, 0.0) * u])
		ci.draw_polyline(street, cob, w * (1.0 if low else 1.0), true)
		ci.draw_polyline(PackedVector2Array([c, c + Vector2(0.0, 14.0) * u * ky]), cob, w * 0.9, true)
	# Contact shadow and AO under the buildings, cast to the south-east (north-west light).
	var shc := SHADOW
	shc.a = 0.42
	_soft_ellipse(ci, c + Vector2(5.0, 3.5) * u, 24.0 * u, 14.0 * u, shc, rings + 1)
	var ao := SHADOW
	ao.a = 0.30
	_soft_ellipse(ci, c + Vector2(0.0, 1.0) * u, 19.0 * u, 11.0 * u, ao, rings)
	var w_lv := CState.walls(st, r)
	if w_lv > 0:
		var ring := PackedVector2Array()
		for j in 25:
			var a := TAU * float(j) / 24.0
			ring.append(c + Vector2(cos(a) * 25.5 * u, sin(a) * 25.5 * u * 0.62 + 1.0 * u))
		var rc := SHADOW
		for i in rings:
			rc.a = 0.16
			ci.draw_polyline(ring, rc, (6.5 - 1.8 * float(i)) * u, true)
