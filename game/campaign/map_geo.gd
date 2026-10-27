extends RefCounted
## Campaign map geometry (view only, floats allowed): hand-authored low-
## polygon coastlines of the western and central Mediterranean in [lon, lat]
## degrees, an equirectangular projection to map pixels, and each region's
## territory: the Voronoi cell of its settlement among the settlements on the
## same landmass, clipped to that landmass. Built once and cached.

const CData := preload("res://campaign/cdata.gd")
const GeoFields := preload("res://game/campaign/geo_fields.gd")
const RomeGeo := preload("res://game/campaign/geo_rome.gd")

## Active geometry (set by use_pack; Rome until told otherwise). Same names as
## the geo_<key>.gd data files.
static var pack_key := "rome"
static var gen := 0       # bumped by use_pack: view caches rebuild when it changes
static var LON0: float = RomeGeo.LON0
static var LAT0: float = RomeGeo.LAT0
static var PX_LAT: float = RomeGeo.PX_LAT
static var PX_LON: float = RomeGeo.PX_LON
static var SIZE: Vector2 = RomeGeo.SIZE
static var LANDS: Array = RomeGeo.LANDS
static var ISLANDS: Array = RomeGeo.ISLANDS
static var PHANTOMS: Array = RomeGeo.PHANTOMS
static var RIVERS: Array = RomeGeo.RIVERS
static var ROADS: Array = RomeGeo.ROADS
static var CHART: Array = RomeGeo.CHART   # open-ocean polygons [lon, lat] the chart sea covers (view only)

static var _cells: Array = []
static var _smooth: Array = []   # per region: the territory's pieces with the shared edges smoothed (see smooth_cell)
static var _boxes: Array = []   # bounding Rect2 of each cell piece (region_at skips the polygon test outside it)
static var _boxes_gen := -1
static var _anchors: Array = []
static var _lands: Array = []
static var _islands: Array = []


## (The view calls it through pack_view.gd, with CData.use_pack, before any
## MapView / Landscape is prepared.)
## Switch the active geometry (and the relief fields) to pack `key`
## ("rome", "west", ...): loads res://game/campaign/geo_<key>.gd. Fails loudly
## if that file is missing. Clears every cache here and bumps `gen`.
static func use_pack(key: String) -> void:
	if key == pack_key:
		return
	var path := "res://game/campaign/geo_%s.gd" % key
	assert(ResourceLoader.exists(path), "map_geo.use_pack: no geometry file " + path)
	var g = load(path)
	if g == null:
		push_error("map_geo.use_pack: cannot load " + path)
		return
	pack_key = key
	LON0 = g.LON0
	LAT0 = g.LAT0
	PX_LAT = g.PX_LAT
	PX_LON = g.PX_LON
	SIZE = g.SIZE
	LANDS = g.LANDS
	ISLANDS = g.ISLANDS
	PHANTOMS = g.PHANTOMS
	RIVERS = g.RIVERS
	ROADS = g.ROADS
	CHART = g.CHART
	_cells = []
	_smooth = []
	_anchors = []
	_lands = []
	_islands = []
	gen += 1
	GeoFields.use_pack(key)


static func project(lon: float, lat: float) -> Vector2:
	return Vector2((lon - LON0) * PX_LON, (LAT0 - lat) * PX_LAT)


static func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(project(float(p[0]), float(p[1])))
	return out


## Land polygons in map pixels.
static func lands() -> Array:
	if _lands.is_empty():
		for l in LANDS:
			_lands.append(_poly(l))
	return _lands


static func islands() -> Array:
	if _islands.is_empty():
		for l in ISLANDS:
			_islands.append(_poly(l))
	return _islands


## Settlement position of region r in map pixels.
static func site(r: int) -> Vector2:
	var rd: Dictionary = CData.REGIONS[r]
	return project(int(rd["lon"]) / 100.0, int(rd["lat"]) / 100.0)


## Territory of region r: Array of polygons (map pixels).
static func cell(r: int) -> Array:
	if _cells.is_empty():
		_build_cells()
	return _cells[r]


const SMOOTH_ROUNDS := 2        # Chaikin rounds on a shared edge
const RIVER_SNAP := 12.0        # map px: a border vertex this near a river moves onto it
const SNAP_STEP := 10.0         # map px: a shared edge near a river is cut into pieces this long before the snap
const BORDER_STEP := 24.0        # map px: a straight shared edge is cut into pieces this long, then waved
const BORDER_WAVER := 4.0        # map px: the most a border vertex is moved sideways
const JOIN_TOL := 2.0           # map px: two runs with ends this close are the same shared edge


## Territory of region r for drawing (map pixels): the same pieces as `cell`, but each edge shared with another
## region is a smoothed curve (two Chaikin rounds, junctions fixed; a vertex within RIVER_SNAP of a river is moved
## onto it first). Both neighbours draw the identical curve, so no slivers open between them. Coast edges (against
## the sea) are the real coastline, untouched. Built once per pack for all regions.
static func smooth_cell(r: int) -> Array:
	if _cells.is_empty():
		_build_cells()
	if _smooth.is_empty():
		_build_smooth()
	return _smooth[r]


static func _build_smooth() -> void:
	var n := CData.region_count()
	var rivers: Array = []
	for i in RIVERS.size():
		rivers.append(river_line(i))
	var joined := {}   # "lo:hi" -> Array of smoothed runs already made for that pair of regions
	_smooth = []
	for r in n:
		var pieces: Array = []
		for piece in _cells[r]:
			pieces.append(_smooth_piece(r, piece, rivers, joined))
		_smooth.append(pieces)


static func _smooth_piece(r: int, piece: PackedVector2Array, rivers: Array, joined: Dictionary) -> PackedVector2Array:
	var cnt := piece.size()
	var ring := piece
	# Label each segment: the neighbouring region it runs along, or -1 for the coast (the sea, or nothing).
	var lab := PackedInt32Array()
	lab.resize(cnt)
	for i in cnt:
		var a := ring[i]
		var b := ring[(i + 1) % cnt]
		var d := b - a
		var m := (a + b) * 0.5
		var nrm := Vector2(d.y, -d.x).normalized()
		if Geometry2D.is_point_in_polygon(m + nrm * 0.6, piece):
			nrm = -nrm   # (point it outward)
		var q := region_at(m + nrm * 0.6)
		if q == r:
			q = -1   # (a sliver: treat as coast, left alone)
		lab[i] = q
	var start := -1
	for i in cnt:
		if lab[i] != lab[(i + cnt - 1) % cnt]:
			start = i
			break
	if start < 0:
		return piece   # one label all round (an island, or an odd enclave): as it is
	var out := PackedVector2Array()
	var i := 0
	while i < cnt:
		var k0 := (start + i) % cnt
		var q := lab[k0]
		var j := i
		while j + 1 < cnt and lab[(start + j + 1) % cnt] == q:
			j += 1
		var run := PackedVector2Array()
		for t in range(i, j + 2):
			run.append(ring[(start + t) % cnt])
		var done := run
		if q >= 0 and run.size() >= 2:
			done = _smooth_run(r, q, run, rivers, joined)
		# (each run starts at the previous run's last point: leave that one out)
		for t in done.size() - 1:
			out.append(done[t])
		i = j + 1
	return out


static func _smooth_run(r: int, q: int, run: PackedVector2Array, rivers: Array, joined: Dictionary) -> PackedVector2Array:
	var key := "%d:%d" % [mini(r, q), maxi(r, q)]
	var made: Array = joined.get(key, [])
	for m in made:
		var mm: PackedVector2Array = m
		if mm[0].distance_to(run[0]) <= JOIN_TOL and mm[mm.size() - 1].distance_to(run[run.size() - 1]) <= JOIN_TOL:
			return mm
		if mm[0].distance_to(run[run.size() - 1]) <= JOIN_TOL and mm[mm.size() - 1].distance_to(run[0]) <= JOIN_TOL:
			var rev := PackedVector2Array()
			for t in range(mm.size() - 1, -1, -1):
				rev.append(mm[t])
			return rev
	var pts := run
	# Near a river: cut the edge into short pieces so there are vertices to snap, then snap the inner ones.
	var near_river := false
	for rl in rivers:
		for k in pts.size() - 1:
			if _seg_near_polyline(pts[k], pts[k + 1], rl, RIVER_SNAP):
				near_river = true
				break
		if near_river:
			break
	if near_river:
		var cut := PackedVector2Array([pts[0]])
		for k in pts.size() - 1:
			var seg := pts[k].distance_to(pts[k + 1])
			var pieces := maxi(int(ceil(seg / SNAP_STEP)), 1)
			for t in range(1, pieces + 1):
				cut.append(pts[k].lerp(pts[k + 1], float(t) / pieces))
		for k in range(1, cut.size() - 1):
			var best := RIVER_SNAP
			var at := cut[k]
			for rl in rivers:
				for s in (rl as PackedVector2Array).size() - 1:
					var c := Geometry2D.get_closest_point_to_segment(cut[k], rl[s], rl[s + 1])
					var dd := c.distance_to(cut[k])
					if dd < best:
						best = dd
						at = c
			cut[k] = at
		pts = cut
	# A hand-drawn meander: the Voronoi bisectors are ruler-straight between junctions, so each long shared edge
	# is cut into BORDER_STEP pieces and its inner vertices moved sideways by up to BORDER_WAVER (hash of the two
	# regions and the vertex index; the river snap above has priority: a snapped vertex stays on the river).
	if not near_river:
		var cut2 := PackedVector2Array([pts[0]])
		for k in pts.size() - 1:
			var seg2 := pts[k].distance_to(pts[k + 1])
			var pc := maxi(int(round(seg2 / BORDER_STEP)), 1)
			for t in range(1, pc + 1):
				cut2.append(pts[k].lerp(pts[k + 1], float(t) / pc))
		var wseed := mini(r, q) * 977 + maxi(r, q)
		for k in range(1, cut2.size() - 1):
			var dir := (cut2[k + 1] - cut2[k - 1]).normalized()
			var u := _hash01(wseed, k) * 2.0 - 1.0
			cut2[k] += Vector2(-dir.y, dir.x) * (u * BORDER_WAVER)
		pts = cut2
	for _round in SMOOTH_ROUNDS:
		pts = chaikin_open(pts)
	made.append(pts)
	joined[key] = made
	return pts


static func _hash01(a: int, b: int) -> float:
	var x := (a * 73856093) ^ (b * 19349663)
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF
	x = (x ^ (x >> 16)) & 0xFFFFFF
	return float(x & 0xFFFF) / 65536.0


static func _seg_near_polyline(a: Vector2, b: Vector2, line: PackedVector2Array, d: float) -> bool:
	for s in line.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(a, line[s], line[s + 1])
		if c.distance_to(a) < d:
			return true
		c = Geometry2D.get_closest_point_to_segment(b, line[s], line[s + 1])
		if c.distance_to(b) < d:
			return true
		c = Geometry2D.get_closest_point_to_segment((a + b) * 0.5, line[s], line[s + 1])
		if c.distance_to((a + b) * 0.5) < d:
			return true
	return false


## One Chaikin corner-cutting round over an open polyline (both ends kept).
static func chaikin_open(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if i > 0:
			out.append(a.lerp(b, 0.25))
		if i < pts.size() - 2:
			out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out


## A Catmull-Rom curve (centripetal-free, uniform) through `pts`, `per` samples a span, ends kept.
static func catmull(pts: PackedVector2Array, per: int) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for s in range(1, per + 1):
			var t := float(s) / per
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return out


## Where a region's armies are drawn: inside its territory, a little
## away from the settlement towards the territory's centre.
static func anchor(r: int) -> Vector2:
	if _cells.is_empty():
		_build_cells()
	return _anchors[r]


static func _build_cells() -> void:
	var n := CData.region_count()
	var land_polys := lands()
	_cells.resize(n)
	_anchors.resize(n)
	var big := PackedVector2Array([Vector2(-200, -200), Vector2(SIZE.x + 200, -200),
		Vector2(SIZE.x + 200, SIZE.y + 200), Vector2(-200, SIZE.y + 200)])
	for r in n:
		var p := site(r)
		var land := int(CData.REGIONS[r]["land"])
		var poly := big
		for q in n:
			if q == r or int(CData.REGIONS[q]["land"]) != land:
				continue
			poly = _clip_half(poly, p, site(q))
			if poly.size() < 3:
				break
		for ph in PHANTOMS:
			if int(ph[2]) == land and poly.size() >= 3:
				poly = _clip_half(poly, p, project(float(ph[0]), float(ph[1])))
		var pieces: Array = []
		for piece in Geometry2D.intersect_polygons(poly, land_polys[land]):
			# (Slivers the real coasts leave, with no area, cannot be drawn.)
			if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
				pieces.append(piece)
		_cells[r] = pieces
		# Anchor: centroid of the piece holding the settlement, pulled half
		# way to the settlement, nudged below it if they nearly coincide.
		var best: PackedVector2Array = PackedVector2Array()
		for piece in pieces:
			if Geometry2D.is_point_in_polygon(p, piece):
				best = piece
		if best.is_empty() and not pieces.is_empty():
			best = pieces[0]
		var c := _centroid(best) if not best.is_empty() else p
		var a := p.lerp(c, 0.55)
		if a.distance_to(p) < 22.0:
			a = p + Vector2(0, 24)
		if not best.is_empty() and not Geometry2D.is_point_in_polygon(a, best):
			a = p + Vector2(0, 24)
		_anchors[r] = a


## Keep the half of polygon `poly` closer to a than to b (Sutherland-Hodgman
## against the perpendicular bisector).
static func _clip_half(poly: PackedVector2Array, a: Vector2, b: Vector2) -> PackedVector2Array:
	var mid := (a + b) * 0.5
	var nrm := b - a
	var out := PackedVector2Array()
	var cnt := poly.size()
	for i in cnt:
		var s := poly[i]
		var e := poly[(i + 1) % cnt]
		var ds := (s - mid).dot(nrm)
		var de := (e - mid).dot(nrm)
		if ds <= 0.0:
			out.append(s)
		if (ds <= 0.0) != (de <= 0.0):
			var t := ds / (ds - de)
			out.append(s.lerp(e, t))
	return out


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var area := 0.0
	var c := Vector2.ZERO
	var cnt := poly.size()
	for i in cnt:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % cnt]
		var cr := p0.cross(p1)
		area += cr
		c += (p0 + p1) * cr
	if absf(area) < 1e-3:
		return poly[0]
	return c / (3.0 * area)


## Region whose territory contains map point p (-1 for the sea).
static func region_at(p: Vector2) -> int:
	var n := CData.region_count()
	if _cells.is_empty():
		_build_cells()
	if _boxes.size() != n or _boxes_gen != gen:
		_boxes = []
		for r in n:
			var bs: Array = []
			for piece in _cells[r]:
				var pp: PackedVector2Array = piece
				var rc := Rect2(pp[0], Vector2.ZERO) if pp.size() > 0 else Rect2()
				for q in pp:
					rc = rc.expand(q)
				bs.append(rc)
			_boxes.append(bs)
		_boxes_gen = gen
	for r in n:
		var bs: Array = _boxes[r]
		var pcs: Array = _cells[r]
		for i in pcs.size():
			if (bs[i] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, pcs[i]):
				return r
	return -1


## Every river crossing in id order: {id, name, kind (0 ford, 1 bridge),
## river (index in RIVERS), p (map pixels)}.
static func crossings() -> Array:
	var out: Array = []
	for i in RIVERS.size():
		for c in RIVERS[i]["cross"]:
			out.append({"id": out.size(), "name": str(c[0]), "kind": int(c[1]), "river": i,
				"p": project(float(c[2]), float(c[3]))})
	return out


## River i's line in map pixels (source to mouth, as authored).
static func river_line(i: int) -> PackedVector2Array:
	return _poly(RIVERS[i]["pts"])


## Road i's line in map pixels.
static func road_line(i: int) -> PackedVector2Array:
	return _poly(ROADS[i][1])


## The cells (index y * w + x of a grid of `cpx` px cells, w wide) a
## polyline runs through, in order and 4-connected (a diagonal move gets
## the orthogonal cell nearer the line in between). Shared by the grid tool
## (road cells) and the map view (the road drawn through them).
static func line_cells(line: PackedVector2Array, cpx: float, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var last := Vector2i(-1, -1)
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var n := maxi(int(ceil(a.distance_to(b) / (cpx * 0.1))), 1)
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var q := Vector2i(clampi(int(p.x / cpx), 0, w - 1), clampi(int(p.y / cpx), 0, h - 1))
			if q == last:
				continue
			if last.x >= 0 and q.x != last.x and q.y != last.y:
				# Diagonal: the orthogonal cell whose centre is nearer the line.
				var o1 := Vector2i(q.x, last.y)
				var o2 := Vector2i(last.x, q.y)
				var c1 := (Vector2(o1) + Vector2(0.5, 0.5)) * cpx
				var c2 := (Vector2(o2) + Vector2(0.5, 0.5)) * cpx
				var d1 := c1.distance_to(Geometry2D.get_closest_point_to_segment(c1, a, b))
				var d2 := c2.distance_to(Geometry2D.get_closest_point_to_segment(c2, a, b))
				var o := o1 if d1 <= d2 else o2
				out.append(o.y * w + o.x)
			out.append(q.y * w + q.x)
			last = q
	return out
