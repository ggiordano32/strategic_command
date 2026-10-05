extends RefCounted
## Campaign map geometry (view only, floats allowed): hand-authored low-
## polygon coastlines of the western and central Mediterranean in [lon, lat]
## degrees, an equirectangular projection to map pixels, and each region's
## territory: the Voronoi cell of its settlement among the settlements on the
## same landmass, clipped to that landmass. Built once and cached.

const CData := preload("res://campaign/cdata.gd")

const LON0 := -10.5
const LAT0 := 47.0
const PX_LAT := 100.0          # map pixels per degree of latitude
const PX_LON := 76.6           # ... per degree of longitude (cos 40 deg)
const SIZE := Vector2(36.0 * PX_LON, 14.0 * PX_LAT)

## Landmasses that hold regions (index = CData region "land").
## 0 Europe (Iberia, Gaul, Italy, the Balkans; the north edge of the map
## closes it), 1 North Africa (the south edge closes it), 2 Sicily,
## 3 Sardinia, 4 Corsica.
const LANDS := [
	# 0 Europe: from the Bay of Biscay along the top edge, down the east
	# edge to the Aegean, round Greece, up the Adriatic, round Italy, along
	# the coasts of Gaul and Spain, round Iberia and back up to Biscay.
	[[-2.2, 47.0], [25.5, 47.0], [25.5, 40.9], [24.4, 40.95], [23.9, 40.7], [23.35, 40.2],
	[23.0, 40.5], [22.9, 40.62], [22.55, 40.3], [22.65, 39.95], [22.95, 39.55], [23.2, 39.15],
	[22.85, 38.85], [23.35, 38.45], [23.75, 38.3], [24.05, 38.0], [24.02, 37.65], [23.6, 37.94],
	[23.35, 38.0], [23.0, 37.88], [23.15, 37.55], [23.45, 37.4], [22.75, 37.5], [22.95, 36.95],
	[23.2, 36.44], [22.75, 36.75], [22.48, 36.38], [22.1, 36.95], [21.88, 36.72], [21.6, 37.2],
	[21.3, 37.65], [21.37, 38.15], [22.1, 38.05], [22.88, 37.93], [22.6, 38.22], [22.0, 38.35],
	[21.77, 38.33], [21.43, 38.37], [21.1, 38.5], [20.95, 38.75], [20.75, 38.96], [20.35, 39.3],
	[20.1, 39.65], [20.0, 39.85], [19.48, 40.45], [19.45, 41.3], [19.4, 41.85], [18.7, 42.4],
	[18.1, 42.65], [16.45, 43.5], [15.2, 44.1], [14.4, 45.33], [13.9, 44.8], [13.75, 45.65],
	[12.35, 45.45], [12.5, 44.95], [12.25, 44.4], [12.6, 44.05], [13.52, 43.62], [13.9, 42.9],
	[14.2, 42.46], [15.0, 42.0], [16.1, 41.9], [16.0, 41.65], [16.87, 41.12], [17.95, 40.64],
	[18.5, 40.15], [18.35, 39.8], [17.97, 40.05], [17.24, 40.47], [16.5, 39.75], [17.13, 39.08],
	[17.1, 38.9], [16.55, 38.7], [16.4, 38.3], [16.06, 37.92], [15.64, 38.1], [15.72, 38.25],
	[15.9, 38.7], [16.1, 39.1], [15.8, 39.6], [15.5, 40.05], [15.27, 40.0], [14.98, 40.35],
	[14.76, 40.68], [14.35, 40.6], [14.25, 40.85], [13.57, 41.2], [13.05, 41.22], [12.62, 41.45],
	[12.28, 41.73], [11.8, 42.1], [11.2, 42.45], [10.5, 42.93], [10.3, 43.55], [9.83, 44.1],
	[8.93, 44.4], [8.48, 44.3], [7.77, 43.8], [7.27, 43.7], [7.0, 43.55], [5.93, 43.1],
	[5.37, 43.3], [4.8, 43.35], [4.4, 43.45], [3.9, 43.5], [3.15, 43.15], [3.05, 42.7],
	[3.32, 42.32], [3.15, 42.1], [2.18, 41.38], [1.25, 41.1], [0.85, 40.7], [0.4, 40.35],
	[-0.32, 39.47], [0.23, 38.73], [-0.48, 38.34], [-0.7, 37.63], [-0.98, 37.6], [-2.19, 36.72],
	[-2.46, 36.83], [-4.42, 36.72], [-5.35, 36.13], [-5.6, 36.01], [-6.29, 36.53], [-7.0, 37.2],
	[-7.9, 37.0], [-8.99, 37.02], [-8.87, 37.95], [-9.45, 38.7], [-9.5, 38.78], [-9.4, 39.36],
	[-8.65, 41.15], [-8.85, 42.2], [-9.27, 42.9], [-8.4, 43.37], [-7.87, 43.77], [-5.65, 43.55],
	[-3.8, 43.46], [-2.9, 43.33], [-1.98, 43.32], [-1.56, 43.48], [-1.25, 44.65], [-1.1, 45.6],
	[-1.15, 46.15], [-2.0, 46.7]],
	# 1 North Africa: up the Atlantic coast of Morocco, east along the coast
	# to Tunisia, down to the south edge.
	[[-8.6, 33.0], [-8.5, 33.25], [-7.6, 33.6], [-6.85, 34.0], [-6.6, 34.26], [-6.15, 35.2],
	[-5.92, 35.79], [-5.8, 35.78], [-5.3, 35.9], [-5.2, 35.6], [-4.3, 35.2], [-3.93, 35.25],
	[-2.95, 35.3], [-1.9, 35.1], [-0.65, 35.7], [0.08, 35.93], [1.3, 36.5], [3.06, 36.77],
	[3.9, 36.92], [5.08, 36.75], [5.77, 36.82], [6.57, 37.0], [6.9, 36.88], [7.77, 36.9],
	[8.25, 36.95], [8.75, 36.95], [9.87, 37.27], [10.33, 36.86], [10.2, 36.8], [10.55, 36.95],
	[11.05, 37.08], [11.1, 36.85], [10.6, 36.4], [10.64, 35.83], [10.83, 35.77], [11.07, 35.5],
	[10.76, 34.74], [10.1, 33.88], [10.9, 33.8], [11.4, 33.0]],
	# 2 Sicily.
	[[15.65, 38.27], [15.29, 37.85], [15.09, 37.5], [15.22, 37.23], [15.29, 37.07], [15.13, 36.69],
	[14.85, 36.73], [14.25, 37.07], [13.94, 37.1], [13.58, 37.28], [13.08, 37.5], [12.59, 37.65],
	[12.43, 37.8], [12.51, 38.02], [12.73, 38.18], [13.36, 38.12], [14.02, 38.04], [15.24, 38.27]],
	# 3 Sardinia.
	[[9.15, 41.24], [9.55, 41.1], [9.5, 40.92], [9.73, 40.38], [9.71, 39.94], [9.52, 39.1],
	[9.1, 39.2], [8.85, 38.88], [8.4, 39.05], [8.45, 39.75], [8.52, 39.9], [8.48, 40.3],
	[8.31, 40.56], [8.14, 40.73], [8.22, 40.95], [8.4, 40.84], [8.71, 40.92]],
	# 4 Corsica.
	[[9.42, 43.0], [9.45, 42.7], [9.51, 42.1], [9.28, 41.6], [9.16, 41.39], [8.9, 41.67],
	[8.73, 41.92], [8.69, 42.27], [8.75, 42.57], [9.3, 42.68], [9.35, 42.95]],
]

## Islands without regions (drawn only).
const ISLANDS := [
	# Mallorca, Menorca, Ibiza.
	[[2.35, 39.55], [2.95, 39.95], [3.45, 39.75], [3.25, 39.35], [2.75, 39.4]],
	[[3.8, 39.95], [4.3, 40.05], [4.3, 39.85], [3.85, 39.9]],
	[[1.2, 38.95], [1.5, 39.1], [1.6, 38.95], [1.35, 38.85]],
	# Crete.
	[[23.5, 35.3], [24.3, 35.6], [25.4, 35.35], [25.5, 35.05], [24.6, 35.1], [23.6, 35.2]],
	# Euboea.
	[[22.9, 38.95], [23.35, 38.7], [24.1, 38.2], [24.55, 38.0], [24.1, 38.0], [23.5, 38.45], [22.85, 38.85]],
	# Corfu, Kefalonia, Zakynthos.
	[[19.65, 39.8], [19.95, 39.75], [20.1, 39.4], [19.9, 39.5]],
	[[20.35, 38.45], [20.65, 38.3], [20.55, 38.1], [20.35, 38.2]],
	[[20.65, 37.85], [20.95, 37.75], [20.85, 37.65], [20.65, 37.7]],
	# Elba, Malta.
	[[10.1, 42.82], [10.45, 42.85], [10.4, 42.72], [10.1, 42.75]],
	[[14.2, 36.05], [14.55, 35.9], [14.45, 35.8], [14.25, 35.9]],
]


## Unclaimed land: extra Voronoi sites that belong to no region, so the
## regions' territories do not spill over the Adriatic onto Dalmatia or across
## the whole Sahara. [lon, lat, landmass]. Their cells stay plain land.
const PHANTOMS := [
	[16.6, 43.6, 0], [15.0, 44.8, 0], [18.3, 44.1, 0], [17.5, 46.2, 0], [21.0, 45.5, 0],
	[22.5, 43.3, 0], [24.6, 42.2, 0], [20.6, 42.3, 0], [24.5, 44.5, 0],
	[0.2, 45.6, 0], [-0.8, 44.3, 0], [7.0, 46.6, 0], [10.5, 46.6, 0], [13.5, 46.6, 0],
	[2.0, 34.4, 1], [6.5, 34.2, 1], [-3.0, 34.0, 1], [-5.5, 33.6, 1], [9.0, 33.6, 1],
]

static var _cells: Array = []
static var _anchors: Array = []
static var _lands: Array = []
static var _islands: Array = []


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
			if not Geometry2D.is_polygon_clockwise(piece) and piece.size() >= 3:
				pieces.append(piece)
			elif piece.size() >= 3:
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
