extends RefCounted
## The overworld towns' plans (map-table style, view only, nothing here touches the campaign state).
## A town is assembled from kit pieces (tools/structures: pieces "p_<name>__y<k>" in the minis atlas) placed
## on the real terrain: site(r) is the static layout of region r's town (the footprint that fits its land, the
## streets, the house slots, the harbour shore, the fields), deterministic from the region index; plan(st, r)
## is what the state shows of it (size by level, walls, harbour, shipyard, the owner's culture). World
## coordinates are map pixels (y down); one metre of the pieces is K = 1.2 px, the same at every zoom, so a
## town is a part of the map: it scales with it and never outgrows its land (the footprint is cut by the
## coast, the neighbours' half way line and steep ground).
## Pieces face south (yaw 0, the door towards +y on the screen); yaw k turns them k * 45 degrees
## anticlockwise on the map (the same convention as the ships' headings).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CSea := preload("res://campaign/csea.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const MapGen := preload("res://sim/mapgen.gd")
const GeoFields := preload("res://game/campaign/geo_fields.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const Atlas := preload("res://game/minis_atlas.gd")

const K := 1.2               # world px a metre
const NA := 24               # footprint radii (angles)
const R_FULL_M := 38.0       # the footprint of a level 2 town, metres
const LVL_S := [0.62, 0.8, 1.0]
const SHADOW_DIR := Vector2(0.62, 0.78)   # the light is north-west: shadows fall south-east

## Collision radius (m), half width and depth (m) of the shadow, height (m, as drawn) per piece.
const PD := {
	"house_s": [3.0, 3.2, 2.7, 13.0], "house_m": [3.0, 2.9, 2.5, 20.0], "adobe": [3.2, 2.9, 2.4, 6.0],
	"chapel": [4.7, 2.9, 4.5, 21.6], "church": [6.6, 4.4, 7.0, 31.2], "cathedral": [7.6, 5.0, 7.9, 34.3], "mansion": [4.9, 4.5, 3.2, 12.8],
	"fort": [9.4, 8.6, 8.6, 15.8], "fountain": [3.2, 3.0, 3.0, 6.0], "well": [1.6, 1.4, 1.4, 5.5],
	"hut": [2.6, 2.4, 2.4, 11.0], "hut_big": [3.6, 3.4, 3.4, 14.0], "palapa": [2.6, 2.6, 2.2, 8.0], "totem": [1.2, 1.0, 1.0, 24.0],
	"maya_house": [3.0, 2.8, 2.2, 8.0], "maya_pyramid": [10.8, 9.7, 9.7, 28.8], "stela": [1.0, 1.0, 0.5, 10.0],
	"shack_a": [3.0, 2.8, 2.2, 10.0], "shack_b": [3.0, 2.8, 2.2, 10.0], "tent": [2.8, 2.6, 2.1, 6.0], "cannon": [1.4, 1.4, 0.9, 2.5],
	"barrels": [2.0, 1.8, 1.8, 2.5], "hullframe": [6.0, 6.0, 1.8, 10.0], "rowboat": [2.8, 3.0, 1.6, 2.0], "skull_rock": [4.0, 4.0, 3.5, 14.0],
	"flagpole": [0.6, 0.5, 0.5, 18.0], "roman_house": [3.2, 3.0, 2.6, 10.0], "hovel": [2.8, 2.6, 2.2, 9.0], "shrine": [3.8, 3.4, 3.4, 12.0],
	"temple": [6.6, 6.6, 4.6, 21.6], "basilica": [6.8, 6.4, 3.4, 14.4], "tower_rome": [3.4, 3.2, 3.2, 28.0],
	"pal_wall": [0.0, 3.0, 0.8, 8.0], "pal_post": [0.0, 1.0, 1.0, 13.0], "pal_gate": [0.0, 4.4, 1.0, 13.0],
	"stone_wall": [0.0, 3.0, 1.6, 9.0], "stone_tower": [0.0, 3.0, 2.9, 20.0], "stone_gate": [0.0, 4.6, 2.4, 22.0],
	"bast_wall": [0.0, 3.0, 2.2, 8.0], "bast_point": [0.0, 4.4, 4.2, 11.0], "bast_gate": [0.0, 4.6, 2.6, 18.0],
	"quay": [0.0, 3.0, 1.8, 1.5], "pier": [0.0, 2.0, 1.9, 2.0], "crane": [2.0, 1.4, 1.4, 22.0], "warehouse": [6.0, 6.6, 3.8, 15.0],
	"shed": [5.0, 6.0, 3.6, 14.0], "slipway": [0.0, 9.0, 4.2, 4.0], "lighthouse": [3.2, 3.5, 3.5, 44.0], "canoe": [2.4, 2.4, 0.9, 1.5],
	"tree_b1": [1.8, 2.6, 2.3, 10.0], "tree_b2": [2.0, 3.0, 2.6, 10.0], "palm_a": [1.0, 1.6, 1.4, 13.0], "palm_b": [1.0, 1.6, 1.4, 14.0],
	"orange": [1.2, 1.9, 1.7, 7.0],
	"longhouse": [6.2, 6.2, 3.0, 9.0], "rack": [2.3, 2.1, 0.9, 4.0], "stilt_house": [3.0, 2.8, 2.4, 10.0], "maya_platform": [6.4, 6.0, 6.0, 8.0],
}

const WALL_COLS := ["wh", "oc", "bl", "co", "wh", "bl", "oc", "co"]

static var _gen := -1
static var _sites := {}
static var _plans := {}
static var _kmpx := 1.0       # px a km on the coast field
static var _coast := PackedByteArray()
static var _cw := 0
static var _ch := 0
static var _spx := 1.0
static var _neigh := {}       # grid flag -> Array of site points


static func _sync() -> void:
	if _gen == Geo.gen and _cw == GeoFields.fine_width() and _coast.size() > 0:
		return
	_gen = Geo.gen
	_sites = {}
	_plans = {}
	_neigh = {}
	GeoFields.ensure()
	_coast = GeoFields.coast()
	_cw = GeoFields.fine_width()
	_ch = GeoFields.fine_height()
	_spx = GeoFields.sample_px()
	_kmpx = Geo.PX_LAT / 111.32


## Land depth in px at world point p (negative: sea), from the coast field (nearest sample).
static func depth(p: Vector2) -> float:
	var ix := clampi(int(p.x / _spx), 0, _cw - 1)
	var iy := clampi(int(p.y / _spx), 0, _ch - 1)
	return (128.0 - float(_coast[iy * _cw + ix])) * _kmpx


## The same, bilinear (the shore line itself).
static func depth_f(p: Vector2) -> float:
	return -GeoFields.coast_km(p) * _kmpx


static func site_point(r: int, grid: bool) -> Vector2:
	if grid:
		var c := CGrid.site(r)
		var px := float(CGrid.cell_px())
		return Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px)
	return Geo.site(r)


static func _neighbours(grid: bool) -> Array:
	if not _neigh.has(grid):
		var a: Array = []
		for r in CData.region_count():
			a.append(site_point(r, grid))
		_neigh[grid] = a
	return _neigh[grid]


## Kit piece kind of the town in the state: "town" (colonial), "native", "maya", "haven" or "roman".
static func style_of(st: Dictionary, r: int) -> String:
	if CData.pack == "west":
		if CSea.haven(st, r):
			return "haven"
		if CState.owner_culture(st, r) == MapGen.CUL_CELTIC:
			return "maya" if str(CData.REGIONS[r]["key"]) == "tayasal" else "native"
		return "town"
	return "roman"


## The PD row of a piece (the colour variants share one), [] when unknown.
static func pd_of(name: String) -> Array:
	if PD.has(name):
		return PD[name] as Array
	if name.begins_with("house_s"):
		return PD["house_s"] as Array
	if name.begins_with("house_m"):
		return PD["house_m"] as Array
	if name.begins_with("adobe"):
		return PD["adobe"] as Array
	return [1.0, 1.0, 1.0, 1.0] if not name.is_empty() else []


static func yaw_facing(d: Vector2) -> int:
	## The yaw whose front (south at yaw 0) faces map direction d (y down).
	var phi := atan2(-d.y, d.x)
	return posmod(int(round((phi + PI * 0.5) / (PI * 0.25))), 8)


static func yaw_along(d: Vector2) -> int:
	## Wall-like pieces (long along local x, a half turn symmetric): 0..3.
	var phi := atan2(-d.y, d.x)
	return posmod(int(round(phi / (PI * 0.25))), 4)


static func _dir8(k: int) -> Vector2:
	var a := float(k) * PI * 0.25
	return Vector2(cos(a), -sin(a))


## Footprint radius (px) towards angle a (radians, y down) of site s, linear between the NA samples.
static func rad_at(rad: PackedFloat32Array, a: float) -> float:
	var f := fposmod(a, TAU) / TAU * float(NA)
	var i := int(f) % NA
	var t := f - floorf(f)
	return lerpf(rad[i], rad[(i + 1) % NA], t)


## True when world point p lies inside the footprint of site s at the size factor `sc` (1: the full one).
static func inside(s: Dictionary, p: Vector2, sc: float = 1.0) -> bool:
	var d: Vector2 = p - (s["c"] as Vector2)
	var l := d.length()
	if l < 0.01:
		return true
	return l <= rad_at(s["rad"], atan2(d.y, d.x)) * sc * _lvl_dir(s, d / l, sc)


## The footprint scale in direction u (unit): the full size towards the harbour, `sc` elsewhere.
static func _lvl_dir(s: Dictionary, u: Vector2, sc: float) -> float:
	if sc >= 0.999:
		return 1.0
	var cd: Vector2 = s["cdir"]
	if cd == Vector2.ZERO or not bool(s["near_sea"]):
		return 1.0
	var w := clampf(u.dot(cd), 0.0, 1.0)
	return lerpf(1.0, 1.0 / sc, w * w)


static func _seed_rng(r: int, salt: int) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = 7919 * (r + 3) + 104729 * salt
	return g


static func _elev(p: Vector2) -> float:
	return GeoFields.elev_m(p)


static func _slope(p: Vector2) -> float:
	return GeoFields.slope_pct(p)


## The ray (unit u from p0) that stays on land (depth >= margin) and under the slope limit: the px it reaches.
static func _reach(p0: Vector2, u: Vector2, maxd: float, margin: float, slope_max: float) -> float:
	var d := 0.0
	var step := 2.0
	while d + step <= maxd:
		var q := p0 + u * (d + step)
		if depth(q) < margin or _slope(q) > slope_max:
			return d
		d += step
	return maxd


# ------------------------------------------------------------------ the static layout of a site

static func site(r: int, grid: bool) -> Dictionary:
	_sync()
	var key := r * 2 + (1 if grid else 0)
	if not _sites.has(key):
		_sites[key] = _make_site(r, grid)
	return _sites[key]


static func _make_site(r: int, grid: bool) -> Dictionary:
	var rng := _seed_rng(r, 1)
	var p0 := site_point(r, grid)
	var neigh := _neighbours(grid)
	var rfull := R_FULL_M * K
	# The Voronoi half way line to the neighbours caps the radius in their direction.
	var near_pts: Array = []
	for q in range(neigh.size()):
		if q != r and p0.distance_to(neigh[q] as Vector2) < rfull * 3.2:
			near_pts.append(neigh[q])
	var best_c := p0
	var best_score := -1e9
	var best_rad := PackedFloat32Array()
	var offs: Array = [Vector2.ZERO]
	for oy in [-8.0, 0.0, 8.0]:
		for ox in [-8.0, 0.0, 8.0]:
			if ox != 0.0 or oy != 0.0:
				offs.append(Vector2(ox, oy))
	for off in offs:
		var oc: Vector2 = p0 + (off as Vector2)
		if depth(oc) < 2.5 and off != Vector2.ZERO:
			continue
		var orad := _radii(oc, rfull, near_pts)
		var tot := 0.0
		for v in orad:
			tot += v
		var score := tot - 0.9 * (off as Vector2).length() - 0.12 * _slope(oc)
		for q in near_pts:   # crowded neighbours: stand apart (the plaza and main buildings move off the shared line)
			var dq0 := p0.distance_to(q as Vector2)
			if dq0 < rfull * 1.3:
				score += 1.6 * minf((oc.distance_to(q as Vector2) - dq0), 8.0)
		if score > best_score:
			best_score = score
			best_c = oc
			best_rad = orad
	var c := best_c
	var rad := best_rad
	# smooth (never wider than the land allows), a little irregular
	var sm := PackedFloat32Array()
	sm.resize(NA)
	for i in NA:
		var a: float = rad[(i + NA - 1) % NA]
		var b: float = rad[i]
		var d: float = rad[(i + 1) % NA]
		sm[i] = minf(b, (a + 2.0 * b + d) * 0.25 + 1.0) * rng.randf_range(0.93, 1.0)
	rad = sm
	var s := {"r": r, "c": c, "p0": p0, "rad": rad}
	# the sea: the nearest direction (24 rays on the coast field)
	var sea_d := 1e9
	var sea_u := Vector2.ZERO
	for i in 24:
		var a := TAU * float(i) / 24.0
		var u := Vector2(cos(a), sin(a))
		var d := 2.0
		while d < rfull * 1.6:
			if depth(c + u * d) < 0.0:
				break
			d += 2.0
		if d < rfull * 1.6 and d < sea_d:
			sea_d = d
			sea_u = u
	# refine the direction by the gradient of the depth field there
	if sea_u != Vector2.ZERO:
		var q := c + sea_u * sea_d
		var gx := depth_f(q + Vector2(3, 0)) - depth_f(q - Vector2(3, 0))
		var gy := depth_f(q + Vector2(0, 3)) - depth_f(q - Vector2(0, 3))
		var gv := Vector2(-gx, -gy)
		if gv.length() > 0.001:
			sea_u = (sea_u * 0.5 + gv.normalized() * 0.5).normalized()
	s["cdir"] = sea_u
	s["cdist"] = sea_d if sea_u != Vector2.ZERO else 1e9
	s["near_sea"] = sea_u != Vector2.ZERO and sea_d <= rfull * 1.12
	# ground: slope, the way up
	var gv2 := Vector2(_elev(c + Vector2(7, 0)) - _elev(c - Vector2(7, 0)), _elev(c + Vector2(0, 7)) - _elev(c - Vector2(0, 7)))
	var slope := _slope(c)
	var hi := -1e9
	var lo := 1e9
	for i in 16:
		var a := TAU * float(i) / 16.0
		var q := c + Vector2(cos(a), sin(a)) * rfull * 0.7
		if depth(q) < 2.0:
			continue
		var e := _elev(q)
		hi = maxf(hi, e)
		lo = minf(lo, e)
	var hill := slope >= 6.0 or (hi - lo) > 70.0
	s["hill"] = hill and gv2.length() > 0.5
	s["up"] = gv2.normalized() if gv2.length() > 0.001 else Vector2.ZERO
	# the street axis: along the contour on a hill, along the shore at a harbour, else seeded
	var axis := Vector2.RIGHT.rotated(rng.randf() * PI)
	if bool(s["hill"]):
		var up: Vector2 = s["up"]
		axis = Vector2(-up.y, up.x)
	elif bool(s["near_sea"]):
		axis = Vector2(-sea_u.y, sea_u.x)
	s["axis"] = axis
	_streets(s, rng)
	_shore(s, rng)
	_fields(s, rng)
	_slots(s, rng)
	# the area where map trees are cleared / drawn with the town, in world px
	s["clear_r"] = _max_rad(rad) * 1.16 + 6.0
	return s


static func _max_rad(rad: PackedFloat32Array) -> float:
	var m := 0.0
	for v in rad:
		m = maxf(m, v)
	return m


## The 24 footprint radii of a town centred at c.
static func _radii(c: Vector2, rfull: float, near_pts: Array) -> PackedFloat32Array:
	var rad := PackedFloat32Array()
	rad.resize(NA)
	for i in NA:
		var a := TAU * float(i) / float(NA)
		var u := Vector2(cos(a), sin(a))
		var cap := rfull
		for q in near_pts:
			var dq: Vector2 = (q as Vector2) - c
			var along := dq.dot(u)
			if along > 0.5:
				cap = minf(cap, 0.47 * dq.length_squared() / along)
		cap = maxf(cap, 11.0)
		rad[i] = maxf(_reach(c, u, cap, 1.8, 62.0) - 1.0, 5.0)
	return rad


## 2 to 4 streets: a main one through the plaza, cross streets (up the slope on a hill, down to the quay at a port).
static func _streets(s: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = s["c"]
	var axis: Vector2 = s["axis"]
	var lines: Array = []
	var main := _walk(s, c, axis, rng)
	lines.append(main)
	var cross_n := 3
	var main_len := 0.0
	for i in range(main.size() - 1):
		main_len += (main[i] as Vector2).distance_to(main[i + 1])
	var nrm := Vector2(-axis.y, axis.x)
	if bool(s["near_sea"]):
		var cd: Vector2 = s["cdir"]
		if cd.dot(nrm) < 0.0:
			nrm = -nrm
	elif bool(s["hill"]):
		if (s["up"] as Vector2).dot(nrm) < 0.0:
			nrm = -nrm
	for k in cross_n:
		var t := rng.randf_range(0.2, 0.8)
		if k == 0:
			t = 0.5
		var base := _along(main, main_len * t)
		var dirs: Array = [nrm] if k == 0 else [nrm, -nrm]
		if k == 0:
			dirs = [nrm, -nrm]
		for dv in dirs:
			if k >= 2 and (dv as Vector2) == -nrm:
				continue
			var seg := _walk_one(s, base, dv as Vector2, rng)
			if seg.size() >= 3:
				lines.append(seg)
	s["streets"] = lines
	s["plaza"] = c


static func _along(line: PackedVector2Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in range(line.size() - 1):
		var d := line[i].distance_to(line[i + 1])
		if acc + d >= dist:
			return line[i].lerp(line[i + 1], (dist - acc) / maxf(d, 0.01))
		acc += d
	return line[line.size() - 1]


## A street through c both ways along dir (curving with the contour on a hill).
static func _walk(s: Dictionary, c: Vector2, dir: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var a := _walk_one(s, c, -dir, rng)
	var b := _walk_one(s, c, dir, rng)
	var out := PackedVector2Array()
	for i in range(a.size() - 1, 0, -1):
		out.append(a[i])
	for i in b.size():
		out.append(b[i])
	return out


static func _walk_one(s: Dictionary, from: Vector2, dir: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(from)
	var p := from
	var d := dir
	var ph := rng.randf() * TAU
	var step := 4.0
	var hill := bool(s["hill"])
	for i in 40:
		var nd := d
		if hill:
			var e1 := _elev(p + Vector2(5, 0)) - _elev(p - Vector2(5, 0))
			var e2 := _elev(p + Vector2(0, 5)) - _elev(p - Vector2(0, 5))
			var g := Vector2(e1, e2)
			if g.length() > 0.8:
				var tang := Vector2(-g.y, g.x).normalized()
				if tang.dot(d) < 0.0:
					tang = -tang
				# along a contour when the street runs across the slope, straight up it otherwise
				var across := absf(d.dot(g.normalized()))
				nd = (d * (0.55 + 0.4 * across) + tang * (0.45 - 0.4 * across)).normalized()
		nd = nd.rotated(sin(ph + float(i) * 0.35) * 0.05)
		d = d.lerp(nd, 0.6).normalized()
		p += d * step
		if not inside(s, p, 1.0) or depth(p) < 2.0 or _slope(p) > 55.0:
			break
		pts.append(p)
	return pts


## The shore beside the town (for a harbour): points along the shoreline, each [shore point, unit normal to the sea].
static func _shore(s: Dictionary, _rng: RandomNumberGenerator) -> void:
	var out: Array = []
	var cd: Vector2 = s["cdir"]
	if bool(s["near_sea"]):
		var c: Vector2 = s["c"]
		var tg := Vector2(-cd.y, cd.x)
		for t in range(-7, 8):
			var q0 := c + tg * float(t) * 6.0 * K * 0.78
			# find the shore along the normal: walk from inland to the sea
			var start := q0 - cd * 30.0
			var d := 0.0
			var hit := -1.0
			while d < 110.0:
				var q := start + cd * d
				if depth_f(q) < 0.0:
					hit = d
					break
				d += 1.5
			if hit < 0.0:
				continue
			# a hit that starts in the sea is no shore
			if depth_f(start) < 0.0:
				continue
			var sp := start + cd * (hit - 0.4)
			var gx := depth_f(sp + Vector2(2, 0)) - depth_f(sp - Vector2(2, 0))
			var gy := depth_f(sp + Vector2(0, 2)) - depth_f(sp - Vector2(0, 2))
			var nv := Vector2(-gx, -gy)
			nv = nv.normalized() if nv.length() > 0.001 else cd
			out.append([sp, nv, t])
	s["shore"] = out


## Field and orchard sites outside the streets, on gentle ground, rows along the contours.
static func _fields(s: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = s["c"]
	var rad: PackedFloat32Array = s["rad"]
	var out: Array = []
	var a0 := rng.randf() * TAU
	var tries := 0
	var rm := _max_rad(rad)
	var cd: Vector2 = s["cdir"]
	var sea_bias := bool(s["near_sea"])
	while out.size() < 5 and tries < 60:
		tries += 1
		var a := a0 + float(tries) * 2.399
		var u := Vector2(cos(a), sin(a))
		if sea_bias and u.dot(cd) > 0.35:
			continue
		var dist := rad_at(rad, a) * rng.randf_range(0.98, 1.2) + 10.0 * K * 0.5
		var hl := rng.randf_range(8.0, 11.0) * K
		var hw := rng.randf_range(5.5, 7.5) * K
		var ctr := c + u * (dist + hw * 0.6)
		var row: Vector2
		if bool(s["hill"]) and (s["up"] as Vector2) != Vector2.ZERO:
			var up: Vector2 = s["up"]
			row = Vector2(-up.y, up.x)
		else:
			row = u.rotated(PI * 0.5 + rng.randf_range(-0.4, 0.4))
		var nrm := Vector2(-row.y, row.x)
		var quad := PackedVector2Array([ctr - row * hl - nrm * hw, ctr + row * hl - nrm * hw, ctr + row * hl + nrm * hw, ctr - row * hl + nrm * hw])
		var ok := true
		for q in quad:
			if depth(q) < 3.0 or _slope(q) > 22.0:
				ok = false
		if depth(ctr) < 3.0 or _slope(ctr) > 18.0:
			ok = false
		for o in out:
			if ctr.distance_to((o as Dictionary)["ctr"] as Vector2) < (hl + float((o as Dictionary)["hl"])) * 0.95:
				ok = false
		if ctr.distance_to(c) < rm * 0.9:
			ok = false
		if not ok:
			continue
		out.append({"ctr": ctr, "row": row, "hl": hl, "hw": hw, "quad": quad, "orchard": out.size() % 3 == 2})
	s["fields"] = out


## House slots along the streets (growth order: nearest the plaza first), ring slots for round villages, the civic spots.
static func _slots(s: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = s["c"]
	var slots: Array = []
	var occ: Array = []
	var civ_dir: Vector2 = (s["axis"] as Vector2)
	var nrm0 := Vector2(-civ_dir.y, civ_dir.x)
	if bool(s["near_sea"]):
		nrm0 = -(s["cdir"] as Vector2)    # the church inland of the plaza
	elif bool(s["hill"]):
		nrm0 = s["up"]                     # on the high side
	var church_pos := c + nrm0 * 12.5 * K
	var tries := 0
	while tries < 6 and not (inside(s, church_pos, 1.0) and depth(church_pos) > 3.0):
		tries += 1
		church_pos = c + nrm0.rotated(float(tries) * 0.5 * (1.0 if tries % 2 == 0 else -1.0)) * (12.5 - float(tries) * 1.2) * K
	s["church"] = church_pos
	s["church_dir"] = (c - church_pos).normalized()
	occ.append([c, 3.4 * K])
	occ.append([church_pos, 7.5 * K])
	# the citadel: the highest ground in the outer half of the footprint
	var best := -1e9
	var fort_pos := Vector2.ZERO
	for i in 12:
		var a := TAU * float(i) / 12.0 + 0.2
		for f: float in [0.55, 0.72]:
			var q: Vector2 = c + Vector2(cos(a), sin(a)) * rad_at(s["rad"], a) * f
			if depth(q) < 6.0 or q.distance_to(church_pos) < 14.0 * K:
				continue
			if bool(s["near_sea"]) and (q - c).normalized().dot(s["cdir"]) > 0.6:
				continue
			var sc := _elev(q) - 0.3 * _slope(q) + rng.randf() * 1.5
			if sc > best:
				best = sc
				fort_pos = q
	s["fort"] = fort_pos
	if fort_pos != Vector2.ZERO:
		occ.append([fort_pos, 13.0 * K])
	# street slots
	var gstep := 6.4 * K
	var cand: Array = []
	for line in s["streets"]:
		var pl: PackedVector2Array = line
		var plen := 0.0
		for i in range(pl.size() - 1):
			plen += pl[i].distance_to(pl[i + 1])
		var t := gstep * 0.7
		while t < plen:
			var q := _along(pl, t)
			var q2 := _along(pl, minf(t + 2.0, plen))
			var q1 := _along(pl, maxf(t - 2.0, 0.0))
			var tv := (q2 - q1)
			if tv.length() > 0.01:
				tv = tv.normalized()
				var nv := Vector2(-tv.y, tv.x)
				for side in [-1.0, 1.0]:
					for rank in [0, 1]:
						var off: float = (3.2 + 2.2 + 0.3) * K * 0.92 + float(rank) * 6.4 * K * 0.92
						var pos: Vector2 = q + nv * side * off + tv * rng.randf_range(-0.6, 0.6) * K
						cand.append([pos, (-nv * side).rotated(rng.randf_range(-0.12, 0.12)), q.distance_to(c) + float(rank) * 5.0 * K + rng.randf() * 3.0 * K])
			t += gstep * rng.randf_range(0.92, 1.1)
	cand.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	for cd in cand:
		var pos: Vector2 = cd[0]
		if not inside(s, pos, 1.0) or depth(pos) < 3.5 or _slope(pos) > 40.0:
			continue
		var ok := true
		for o in occ:
			if pos.distance_to((o as Array)[0] as Vector2) < float((o as Array)[1]) + 3.0 * K:
				ok = false
				break
		if not ok:
			continue
		# keep the streets clear
		for line in s["streets"]:
			if _near_line(line, pos, 2.6 * K):
				ok = false
				break
		if not ok:
			continue
		occ.append([pos, 3.0 * K])
		slots.append([pos, cd[1], slots.size()])
		if slots.size() >= 34:
			break
	# infill: when the streets leave room, houses on the free ground facing the nearest street (or the plaza)
	var want := 30
	var guard := 0
	while slots.size() < want and guard < 260:
		guard += 1
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * rad_at(s["rad"], a) * 0.95
		var pos := c + Vector2(cos(a), sin(a)) * rr
		if not inside(s, pos, 1.0) or depth(pos) < 3.5 or _slope(pos) > 40.0 or rr < 5.0 * K:
			continue
		var ok := true
		for o in occ:
			if pos.distance_to((o as Array)[0] as Vector2) < float((o as Array)[1]) + 3.0 * K:
				ok = false
				break
		if not ok:
			continue
		var face := c - pos
		var nd := 1e9
		for line in s["streets"]:
			var pl: PackedVector2Array = line
			for i in range(pl.size() - 1):
				var cp := Geometry2D.get_closest_point_to_segment(pos, pl[i], pl[i + 1])
				var dd := cp.distance_to(pos)
				if dd < nd:
					nd = dd
					face = cp - pos
		if nd < 2.6 * K:
			continue
		occ.append([pos, 3.0 * K])
		slots.append([pos, face.normalized(), slots.size(), ])
	slots.sort_custom(func(a, b): return (a[0] as Vector2).distance_to(c) + (0.0 if int(a[2]) < 0 else 0.0) < (b[0] as Vector2).distance_to(c))
	s["slots"] = slots
	# ring slots (huts, shacks): rings round the centre
	var ring: Array = []
	var rocc: Array = [[c, 6.0 * K]]
	var attempt := 0
	while ring.size() < 22 and attempt < 120:
		attempt += 1
		var ringi := 1 + ring.size() / 7
		var a := rng.randf() * TAU
		var rr := (7.0 + 6.0 * float(ringi) + rng.randf_range(-1.5, 1.5)) * K
		var pos := c + Vector2(cos(a), sin(a)) * rr
		if not inside(s, pos, 1.0) or depth(pos) < 3.5 or _slope(pos) > 40.0:
			continue
		var ok := true
		for o in rocc:
			if pos.distance_to((o as Array)[0] as Vector2) < float((o as Array)[1]) + 1.0:
				ok = false
				break
		if not ok:
			continue
		rocc.append([pos, 4.4 * K])
		ring.append([pos, (c - pos).normalized().rotated(rng.randf_range(-0.5, 0.5)), ring.size()])
	ring.sort_custom(func(a, b): return (a[0] as Vector2).distance_to(c) < (b[0] as Vector2).distance_to(c))
	s["ring"] = ring
	s["occ"] = occ


static func _near_line(line: PackedVector2Array, p: Vector2, d: float) -> bool:
	for i in range(line.size() - 1):
		var cp := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		if cp.distance_to(p) < d:
			return true
	return false


# ------------------------------------------------------------------ the tree clearing (for landscape.gd)

## True when a map tree at p is inside the cleared ground of site s (footprint + margin, or a field).
static func clears(s: Dictionary, p: Vector2) -> bool:
	var d: Vector2 = p - (s["c"] as Vector2)
	var l := d.length()
	if l > float(s["clear_r"]) + 40.0:
		return false
	if l <= rad_at(s["rad"], atan2(d.y, d.x)) * 1.16 + 5.0:
		return true
	for f in s["fields"]:
		var fd: Dictionary = f
		if p.distance_to(fd["ctr"] as Vector2) < (float(fd["hl"]) + 6.0) * 1.2 and Geometry2D.is_point_in_polygon(p, fd["quad"]):
			return true
	return false


## True for a tree in the ring just outside the cleared ground (drawn with the town, sorted with its pieces).
static func in_ring(s: Dictionary, p: Vector2) -> bool:
	var d: Vector2 = p - (s["c"] as Vector2)
	var l := d.length()
	return l <= rad_at(s["rad"], atan2(d.y, d.x)) * 1.16 + 5.0 + 30.0


# ------------------------------------------------------------------ the plan the state shows

static func plan(st: Dictionary, r: int, grid: bool) -> Dictionary:
	var lvl := clampi(int(st["regions"][r]["level"]), 0, 2)
	var walls := CState.walls(st, r)
	var style := style_of(st, r)
	var west := CData.pack == "west"
	var port := false
	var yard := false
	if west and CData.ships_on():
		port = style == "haven" or CFleet.harbour(r) >= 0
		yard = CState.building(st, r, CData.SHIPYARD) > 0
	var key := "%d_%d_%d_%d_%d_%s_%d" % [r, lvl, walls, 1 if port else 0, 1 if yard else 0, style, 1 if grid else 0]
	_sync()
	if _plans.has(key):
		return _plans[key]
	var s := site(r, grid)
	var p := _build(s, r, lvl, walls, style, port, yard)
	_plans[key] = p
	return p


static func _item(items: Array, pos: Vector2, name: String, yaw: int) -> void:
	items.append([pos, name, yaw])


static func _build(s: Dictionary, r: int, lvl: int, walls: int, style: String, port: bool, yard: bool) -> Dictionary:
	var rng := _seed_rng(r, 7)
	var c: Vector2 = s["c"]
	var sc: float = float(LVL_S[lvl])
	if style == "maya" or style == "native" or style == "haven":
		sc *= 0.92
	var items: Array = []
	var paint_shadows: Array = []
	var streets_out: Array = []
	var cd: Vector2 = s["cdir"]
	var harbour := port and bool(s["near_sea"]) and (s["shore"] as Array).size() >= 3
	var wet_native := (style == "native" or style == "maya") and bool(s["near_sea"])
	# streets inside the (level) footprint
	for line in s["streets"]:
		var pl: PackedVector2Array = line
		var cut := PackedVector2Array()
		for q in pl:
			if inside(s, q, sc):
				cut.append(q)
			else:
				break
		if cut.size() >= 2:
			streets_out.append(cut)
	var ring_style := style == "native" or style == "maya" or style == "haven"
	# the centre and civic pieces
	var church_pos: Vector2 = s["church"]
	var cdirv: Vector2 = s["church_dir"]
	match style:
		"town":
			var cname := "chapel" if lvl == 0 else ("church" if lvl == 1 else "cathedral")
			if inside(s, church_pos, maxf(sc, 0.75)) or lvl == 0:
				_item(items, church_pos, cname, _yaw4(yaw_facing(cdirv)))
			_item(items, c, "well" if lvl == 0 else "fountain", 0)
			if lvl == 2:
				var mp := c + Vector2(-cdirv.y, cdirv.x) * 12.0 * K + cdirv * 3.0 * K
				if inside(s, mp, 1.0) and depth(mp) > 4.0 and mp.distance_to(church_pos) > 9.0 * K:
					_item(items, mp, "mansion", yaw_facing(-Vector2(-cdirv.y, cdirv.x) + cdirv * 0.5))
			var fp: Vector2 = s["fort"]
			if lvl == 2 and fp != Vector2.ZERO and fp.distance_to(church_pos) > 14.0 * K:
				_item(items, fp, "fort", 0)
		"roman":
			var tn := "shrine" if lvl == 0 else ("temple" if lvl == 1 else "temple")
			_item(items, church_pos, tn, _yaw4(yaw_facing(cdirv)) if tn != "shrine" else 0)
			_item(items, c, "fountain" if lvl > 0 else "well", 0)
			if lvl == 2:
				var bp := c + Vector2(-cdirv.y, cdirv.x) * 14.0 * K
				if inside(s, bp, 1.0) and depth(bp) > 4.0:
					_item(items, bp, "basilica", _yaw4(yaw_facing(Vector2(cdirv.y, -cdirv.x))))
				var fp2: Vector2 = s["fort"]
				if fp2 != Vector2.ZERO and fp2.distance_to(church_pos) > 14.0 * K:
					_item(items, fp2, "tower_rome", 0)
		"maya":
			_item(items, c, "maya_pyramid", 0)
			# stone temple platforms on the plaza's sides
			var px_n := 0
			for k in 6:
				if px_n >= (lvl + 1) / 2 + (1 if lvl == 2 else 0):
					break
				var pa := (s["axis"] as Vector2).angle() + PI * (0.5 if k % 2 == 0 else -0.5) + float(k / 2) * 0.9 * (1.0 if k % 2 == 0 else -1.0)
				var pq := c + Vector2(cos(pa), sin(pa)) * 20.0 * K
				if inside(s, pq, 1.0) and depth(pq) > 4.0 and _free(items, pq, 8.0 * K):
					_item(items, pq, "maya_platform", _yaw4(yaw_facing((c - pq).normalized())))
					px_n += 1
			for k in 3:
				var a := TAU * float(k) / 3.0 + 0.6
				var q := c + Vector2(cos(a), sin(a)) * 17.0 * K
				if inside(s, q, 1.0) and depth(q) > 4.0:
					_item(items, q, "stela", 0)
		"native":
			# the council house (longhouse, lvl 0 a big hut), the totem, drying racks round the fire
			if lvl >= 1:
				_item(items, c, "longhouse", yaw_along(s["axis"]))
				_item(items, c + Vector2(0.0, 8.0) * K, "totem", 0)
			else:
				_item(items, c, "hut_big", 0)
				_item(items, c + Vector2(5.5, 4.0) * K, "totem", 0)
			for k in (1 if lvl == 0 else 3):
				var ra := (s["axis"] as Vector2).angle() + 2.4 + float(k) * 1.7
				var rq := c + Vector2(cos(ra), sin(ra)) * (10.0 + float(k) * 2.0) * K
				if inside(s, rq, 1.0) and depth(rq) > 3.0 and _free(items, rq, 3.0 * K):
					_item(items, rq, "rack", yaw_along(Vector2(cos(ra + 1.57), sin(ra + 1.57))))
		"haven":
			var fl := c + Vector2(4.0, 2.0) * K
			_item(items, fl, "flagpole", 0)
			var fp3: Vector2 = s["fort"]
			if lvl >= 1 and fp3 != Vector2.ZERO:
				_item(items, fp3, "skull_rock", 0)
	# houses
	var n_houses := 0
	match style:
		"town": n_houses = [8, 15, 24][lvl]
		"roman": n_houses = [9, 15, 22][lvl]
		"native": n_houses = [11, 17, 22][lvl]
		"maya": n_houses = [7, 11, 14][lvl]
		"haven": n_houses = [7, 11, 15][lvl]
	var placed := 0
	var slots: Array = (s["ring"] if ring_style else s["slots"]) as Array
	for sl in slots:
		if placed >= n_houses:
			break
		var pos: Vector2 = sl[0]
		if not inside(s, pos, sc):
			continue
		if style == "maya" and pos.distance_to(c) < 14.0 * K:
			continue
		var ok := true
		for o in items:
			var oo: Array = o
			var pd: Array = pd_of(str(oo[1]))
			if pos.distance_to(oo[0] as Vector2) < (float(pd[0]) + 2.6) * K:
				ok = false
				break
		if not ok:
			continue
		var idx: int = int(sl[2])
		var nm := _house_name(style, idx, lvl, rng, pos, s)
		_item(items, pos, nm, yaw_facing(sl[1] as Vector2))
		placed += 1
	# the harbour
	var water := Vector2.ZERO
	var quay_line := PackedVector2Array()
	if harbour:
		var shore: Array = s["shore"]
		# quays along the shore (the middle of it), a pier or two, warehouses behind
		var n := shore.size()
		var mid := n / 2
		var q_from := maxi(0, mid - 3)
		var q_to := mini(n - 1, mid + 3)
		for i in range(q_from, q_to + 1):
			var sp: Vector2 = (shore[i] as Array)[0]
			var nv: Vector2 = (shore[i] as Array)[1]
			var qp := sp - nv * 2.2 * K
			if style == "haven" or style == "native" or style == "maya":
				continue
			if depth(qp) < 0.8:
				continue
			quay_line.append(qp)
			if i % 1 == 0:
				_item(items, qp, "quay", yaw_facing(nv))
		var nsel := (shore[mid] as Array)
		water = (nsel[0] as Vector2) + (nsel[1] as Vector2) * 17.0 * K
		if style == "town" or style == "roman":
			var pi1 := clampi(mid + 4, 0, n - 1)
			var psp: Vector2 = (shore[pi1] as Array)[0]
			var pnv: Vector2 = (shore[pi1] as Array)[1]
			if pi1 != mid and depth(psp - pnv * 1.2 * K) > 0.5:
				_item(items, psp - pnv * 1.2 * K, "pier", yaw_facing(pnv))
			if lvl >= 1:
				var pi2 := clampi(mid - 4, 0, n - 1)
				var ssp: Vector2 = (shore[pi2] as Array)[0]
				var snv: Vector2 = (shore[pi2] as Array)[1]
				if pi2 != mid and depth(ssp - snv * 1.2 * K) > 0.5 and lvl >= 1:
					_item(items, ssp - snv * 1.2 * K, "pier", yaw_facing(snv))
			# warehouses behind the quay
			var wn := 1 if lvl == 0 else (2 if lvl == 1 else 3)
			for k in wn:
				var wi := clampi(mid + (k - wn / 2) * 3 - (1 if wn == 2 else 0), 0, n - 1)
				var wsp: Vector2 = (shore[wi] as Array)[0]
				var wnv: Vector2 = (shore[wi] as Array)[1]
				var wp := wsp - wnv * 9.5 * K
				if depth(wp) > 3.0 and inside(s, wp, 1.15) and _free(items, wp, 6.5 * K):
					_item(items, wp, "warehouse", yaw_facing(wnv))
			# the lighthouse on the point: the most seaward shore sample
			if lvl >= 1:
				var bi := -1
				var bs := -1e9
				for i in n:
					var sp2: Vector2 = (shore[i] as Array)[0]
					var sc2 := (sp2 - c).dot(cd) + 0.35 * absf(float(int((shore[i] as Array)[2])))
					if i < mid - 5 or i > mid + 5:
						continue
					if sc2 > bs:
						bs = sc2
						bi = i
				if bi >= 0:
					var lsp: Vector2 = (shore[bi] as Array)[0]
					var lnv: Vector2 = (shore[bi] as Array)[1]
					var lp := lsp - lnv * 3.4 * K
					if depth(lp) > 1.5 and _free(items, lp, 5.0 * K):
						_item(items, lp, "lighthouse", 0)
		if yard:
			var yi := clampi(mid - 6, 0, n - 1)
			var ysp: Vector2 = (shore[yi] as Array)[0]
			var ynv: Vector2 = (shore[yi] as Array)[1]
			var yp := ysp - ynv * 5.5 * K
			if depth(yp) > 2.0:
				_item(items, yp, "slipway", yaw_facing(ynv))
			var sp3 := yp - ynv * 10.0 * K + Vector2(-ynv.y, ynv.x) * 6.5 * K
			if depth(sp3) > 2.0 and _free(items, sp3, 6.0 * K):
				_item(items, sp3, "shed", yaw_facing(ynv))
			var cp3 := yp + Vector2(-ynv.y, ynv.x) * -7.0 * K - ynv * 2.0 * K
			if depth(cp3) > 2.0 and _free(items, cp3, 3.0 * K):
				_item(items, cp3, "crane", 0)
		# beached boats on the shore beside the quay
		for k in (1 if lvl == 0 else 2):
			var bi2 := clampi(mid + (-6 if k == 0 else 6), 0, n - 1)
			var bsp: Vector2 = (shore[bi2] as Array)[0]
			var bnv: Vector2 = (shore[bi2] as Array)[1]
			var bp := bsp - bnv * 1.4 * K
			var bn := "rowboat" if style == "town" or style == "roman" else "canoe"
			if depth(bp) > 0.6 and _free(items, bp, 3.0 * K):
				_item(items, bp, bn, (yaw_facing(bnv) + k * 3) & 7)
	elif wet_native or style == "haven" or style == "maya" or style == "native":
		# a lake or beach beside the village: canoes pulled up
		if bool(s["near_sea"]) and (s["shore"] as Array).size() >= 3:
			var shore2: Array = s["shore"]
			var n2 := shore2.size()
			if style == "native":   # stilt houses over the shallows at the water's edge (Miskito)
				for k in (2 if lvl == 0 else 4):
					var si := clampi(n2 / 2 + (k - 2) * 2 + (1 if k >= 2 else 0), 0, n2 - 1)
					var ssp2: Vector2 = (shore2[si] as Array)[0]
					var snv2: Vector2 = (shore2[si] as Array)[1]
					var stp := ssp2 - snv2 * 3.4 * K
					if depth(stp) > 0.6 and inside(s, stp, 1.05) and _free(items, stp, 4.0 * K):
						_item(items, stp, "stilt_house", yaw_facing(snv2))
			for k in (2 if style != "native" else 3):
				var bi3 := clampi(n2 / 2 + (-2 if k == 0 else 3), 0, n2 - 1)
				var bsp2: Vector2 = (shore2[bi3] as Array)[0]
				var bnv2: Vector2 = (shore2[bi3] as Array)[1]
				var bp2 := bsp2 - bnv2 * 1.4 * K
				if depth(bp2) > 0.6 and _free(items, bp2, 3.0 * K):
					_item(items, bp2, "canoe", yaw_facing(bnv2 + Vector2(-bnv2.y, bnv2.x) * 0.4))
			if style == "haven":
				var hi := n2 / 2 + 3
				var hsp: Vector2 = (shore2[clampi(hi, 0, n2 - 1)] as Array)[0]
				var hnv: Vector2 = (shore2[clampi(hi, 0, n2 - 1)] as Array)[1]
				var hp := hsp - hnv * 5.0 * K
				if depth(hp) > 2.0 and _free(items, hp, 6.0 * K):
					_item(items, hp, "hullframe", yaw_facing(Vector2(-hnv.y, hnv.x)))
				var pp := (shore2[n2 / 2] as Array)[0] as Vector2
				var pn: Vector2 = (shore2[n2 / 2] as Array)[1]
				if depth(pp - pn * 1.2 * K) > 0.5:
					_item(items, pp - pn * 1.2 * K, "pier", yaw_facing(pn))
	if water == Vector2.ZERO and (port or style == "haven") and bool(s["near_sea"]) and (s["shore"] as Array).size() > 0:
		var sh0: Array = (s["shore"] as Array)[(s["shore"] as Array).size() / 2]
		water = (sh0[0] as Vector2) + (sh0[1] as Vector2) * 17.0 * K
	# the walls
	var wall_items: Array = []
	if walls > 0:
		_walls(s, sc, walls, style, port and harbour, items, wall_items)
	# palms along the shore, orchard trees on the fields, a few broadleaf trees on the edge
	var fields: Array = s["fields"]
	var n_f := 1 + lvl + (1 if lvl == 2 else 0)
	if style == "haven":
		n_f = 0
	if style == "native" or style == "maya":
		n_f = 2 + lvl
	var fields_out: Array = []
	for i in mini(n_f, fields.size()):
		fields_out.append(fields[i])
	for fd in s["fields"]:
		var fdd: Dictionary = fd
		var idx := (s["fields"] as Array).find(fd)
		if bool(fdd["orchard"]) and idx < n_f and style != "native" and style != "maya" and style != "haven":
			var ctr: Vector2 = fdd["ctr"]
			var row: Vector2 = fdd["row"]
			var nrm := Vector2(-row.y, row.x)
			var hl: float = fdd["hl"]
			var hw: float = fdd["hw"]
			var cols := 4
			var rows := 3
			for i in cols:
				for j in rows:
					var tp := ctr + row * (float(i) - float(cols - 1) * 0.5) * hl * 0.5 + nrm * (float(j) - float(rows - 1) * 0.5) * hw * 0.62
					_item(items, tp, "orange", 0)
	var trng := _seed_rng(r, 11)
	var tropic := style != "roman"
	for k in 14:
		var a := trng.randf() * TAU
		var rr := rad_at(s["rad"], a) * sc * trng.randf_range(0.55, 0.98)
		var q := c + Vector2(cos(a), sin(a)) * rr
		if not inside(s, q, sc) or depth(q) < 2.5 or not _free(items, q, 2.8 * K):
			continue
		for st2 in s["streets"]:
			if _near_line(st2, q, 3.0 * K):
				q = Vector2.ZERO
				break
		if q == Vector2.ZERO:
			continue
		var tname := "palm_a" if (tropic and k % 3 == 0) else ("palm_b" if (tropic and k % 3 == 1) else ("tree_b1" if k % 2 == 0 else "tree_b2"))
		_item(items, q, tname, 0)
	# size on screen (world px): width and the height above the anchor of the tallest piece
	var half_w := 14.0
	var top := 18.0
	var bottom := 12.0
	var tab: Dictionary = Atlas.SETS["small"]
	for it in items:
		var ii: Array = it
		var d2 := (ii[0] as Vector2) - c
		half_w = maxf(half_w, absf(d2.x) + 5.0 * K)
		var sk := sprite(tab, str(ii[1]), int(ii[2]))
		var hpx := 6.0 * K
		if sk != "":
			var te: Array = tab[sk]
			hpx = float(te[5]) / float(te[6]) * K
			half_w = maxf(half_w, absf(d2.x) + float(te[2]) * 0.5 / float(te[6]) * K)
		top = maxf(top, -d2.y + hpx)
		bottom = maxf(bottom, d2.y + 3.0 * K)
	items.sort_custom(func(a, b): return (a[0] as Vector2).y < (b[0] as Vector2).y)
	for it in items:
		var ii2: Array = it
		var nm3: String = ii2[1]
		var pd3: Array = pd_of(nm3)
		if pd3.is_empty():
			continue
		if float(pd3[3]) >= 5.0 and not nm3.begins_with("quay") and not nm3.begins_with("pier") and not nm3.begins_with("slipway"):
			paint_shadows.append([ii2[0], nm3, ii2[2]])
	return {"c": c, "items": items, "walls": wall_items, "streets": streets_out, "fields": fields_out, "sc": sc,
		"quay": quay_line, "water": water, "harbour": harbour, "half_w": half_w, "top": top, "bottom": bottom,
		"shadows": paint_shadows, "style": style, "lvl": lvl, "ring": ring_style}


static func _yaw4(k: int) -> int:
	return (int(round(float(k) * 0.5)) * 2) & 7


static func _free(items: Array, p: Vector2, rad: float) -> bool:
	for o in items:
		var oo: Array = o
		var pd: Array = pd_of(str(oo[1]))
		if p.distance_to(oo[0] as Vector2) < rad + float(pd[0]) * K * 0.6:
			return false
	return true


static func _house_name(style: String, idx: int, lvl: int, _rng: RandomNumberGenerator, pos: Vector2, s: Dictionary) -> String:
	var h := absi(int(pos.x * 7.0 + pos.y * 13.0) + idx * 31)
	match style:
		"town":
			var col: String = WALL_COLS[h % WALL_COLS.size()]
			var tall := (lvl >= 1 and h % 4 == 3) or (lvl == 2 and h % 3 == 0)
			var dry := false
			if h % 5 == 0 and lvl >= 1 and not bool(s["hill"]):
				dry = true
			if dry:
				return "adobe_sa" if h % 2 == 0 else "adobe_wh"
			return ("house_m_" if tall else "house_s_") + col
		"roman":
			return "roman_house" if lvl >= 1 else "hovel"
		"native":
			return "palapa" if h % 5 == 0 else "hut"
		"maya":
			return "maya_house" if h % 3 != 0 else "palapa"
		"haven":
			return ["shack_a", "shack_b", "tent", "shack_a", "shack_b", "barrels", "cannon"][h % 7]
	return "hut"


## The wall loop round the town: pieces in 8 directions walked along the footprint (a lattice path), towers,
## a gate where the main street leaves it, the harbour side left open.
static func _walls(s: Dictionary, sc: float, walls: int, style: String, harbour: bool, items: Array, out: Array) -> void:
	var c: Vector2 = s["c"]
	var rad: PackedFloat32Array = s["rad"]
	var kind := "pal"
	if style == "town" or style == "roman":
		kind = "pal" if walls == 1 else ("stone" if walls == 2 else "bast")
	var L := 6.0 * K
	var cd: Vector2 = s["cdir"]
	var wsc := 0.93
	# the gate: where the main street's far end leaves the town, on the land side
	var ga := 0.0
	var best := -1e9
	var main: PackedVector2Array = (s["streets"] as Array)[0]
	for end in [main[0], main[main.size() - 1]]:
		var dv: Vector2 = (end as Vector2) - c
		var sco := dv.length()
		if harbour and dv.length() > 0.1:
			sco -= 200.0 * maxf(0.0, dv.normalized().dot(cd))
		if sco > best:
			best = sco
			ga = atan2(dv.y, dv.x)
	var gate_u := Vector2(cos(ga), sin(ga))
	# start on the loop at the gate
	var rg := rad_at(rad, ga) * sc * _lvl_dir(s, gate_u, sc) * wsc
	var pos := c + gate_u * rg
	var heading := _snap8(Vector2(-gate_u.y, gate_u.x))
	var acc := 0.0
	var prev_a := ga
	var pieces: Array = []   # [pos, dir index, skip]
	var guard := 0
	while guard < 90:
		guard += 1
		var d: Vector2 = pos - c
		var a := atan2(d.y, d.x)
		var da := fposmod(a - prev_a + PI, TAU) - PI
		acc += da
		prev_a = a
		if acc >= TAU - 0.05 and guard > 6:
			break
		# the target: a point on the loop a little ahead
		var ta := a + L * 1.05 / maxf(d.length(), 8.0)
		var tu := Vector2(cos(ta), sin(ta))
		var tgt := c + tu * (rad_at(rad, ta) * sc * _lvl_dir(s, tu, sc) * wsc)
		var want := (tgt - pos)
		var bestk := heading
		var bd := -2.0
		for k in 8:
			var dv2 := _dir8(k)
			var sco2 := dv2.dot(want.normalized()) + (0.12 if k == heading else 0.0)
			if sco2 > bd:
				bd = sco2
				bestk = k
		heading = bestk
		var dvec := _dir8(heading)
		var mid := pos + dvec * L * 0.5
		var skip := false
		if harbour:
			var md := (mid - c)
			if md.length() > 0.1 and md.normalized().dot(cd) > 0.78:
				skip = true
		if depth(mid) < 1.5:
			skip = true
		pieces.append([mid, heading, skip])
		pos += dvec * L
	var np := pieces.size()
	var gate_i := 0
	var tower_every := 5 if kind != "pal" else 4
	for i in np:
		var pc: Array = pieces[i]
		var mid2: Vector2 = pc[0]
		var hd: int = pc[1]
		if bool(pc[2]):
			continue
		var wname := kind + "_wall" if kind != "bast" else "bast_wall"
		if kind == "pal":
			wname = "pal_wall"
		elif kind == "stone":
			wname = "stone_wall"
		if i == gate_i:
			var gname := "pal_gate" if kind == "pal" else ("stone_gate" if kind == "stone" else "bast_gate")
			out.append([mid2, gname, hd & 3])
			continue
		if i == np - 1 and np > 8:
			continue   # the closing piece is hidden by the gate
		out.append([mid2, wname, hd & 3])
		if i % tower_every == 2:
			var vtx := mid2 + _dir8(hd) * L * 0.5
			var tname := "pal_post" if kind == "pal" else ("stone_tower" if kind == "stone" else "bast_point")
			if kind == "bast":
				out.append([vtx, tname, yaw_facing(vtx - c)])
			else:
				out.append([vtx, tname, 0])
	# the wall pieces and the town share one y order
	for o in out:
		items.append(o)


static func _snap8(d: Vector2) -> int:
	var phi := atan2(-d.y, d.x)
	return posmod(int(round(phi / (PI * 0.25))), 8)


## Atlas sprite name of a piece at a yaw, falling back to the nearest yaw that was rendered.
static func sprite(table: Dictionary, name: String, yaw: int) -> String:
	for off in [0, 1, -1, 2, -2, 3, -3, 4]:
		var k := posmod(yaw + off, 8)
		var key := "p_%s__y%d" % [name, k]
		if table.has(key):
			return key
	return ""
