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

static var _cells: Array = []
static var _anchors: Array = []
static var _lands: Array = []
static var _islands: Array = []


## TODO (West slice, step 4b): campaign_screen.gd must call Geo.use_pack(<pack of
## the state>) before building MapView / Landscape (via CData.use_state(st)).
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
	_cells = []
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
	for r in CData.region_count():
		for piece in cell(r):
			if Geometry2D.is_point_in_polygon(p, piece):
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
