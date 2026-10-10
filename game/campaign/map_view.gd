extends Node2D
## Campaign map, world layer (map pixels; the camera pans and zooms it):
## sea, land, territories tinted by owner, borders, land routes and sea lanes,
## and the highlighted destinations of the selected army. Markers and text
## are drawn by map_overlay.gd in screen space so they stay crisp and sized
## for touch at any zoom.
##
## State version 6: the selected army's reach this turn is a filled
## translucent area with a smoothed outline (cells from CRules.reach6; next
## turn's a dashed outline); land routes are gone (armies walk the grid),
## sea lanes join the port cells. Roads, rivers and hills (2026-10-09, from
## the grid the rules read): hill / ridge cells a faint chevron each (two
## for a ridge), rivers blue lines (map_geo.gd's lines: an orthogonal step
## is a river edge exactly when it crosses one), a ford stepping stones
## across the river and a bridge a deck over it, both where the crossing's
## step meets the line, roads thin tan lines through their cells' centres.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const GroundPalette := preload("res://game/ground_palette.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const Landscape := preload("res://game/campaign/landscape.gd")
const GeoFields := preload("res://game/campaign/geo_fields.gd")
const WATER_SHADER := preload("res://game/campaign/water.gdshader")

const SEA := Color(0.13, 0.25, 0.34)
const SEA_SHALLOW := Color(0.22, 0.38, 0.47)
const LAND := Color(0.80, 0.76, 0.62)
const COAST := Color(0.16, 0.18, 0.16, 0.75)
const TINT := 0.55         # owner colour over the region's ground
const GROUND_LIFT := 0.36  # the battle palettes are darker than a map should be
## Lines and highlights, shared with the map key (map_key.gd draws its
## samples with the painters below). Widths are screen px (times lw).
const COL_SEA_LANE := Color(0.75, 0.9, 1.0, 0.6)
const SEA_LANE_DASH := 3.0
const COL_ROUTE := Color(0.25, 0.18, 0.1, 0.55)   # versions 1-5: land routes
const ROUTE_DASH := 7.0
const LANE_W := 1.6
const COL_REACH := Color(1.0, 0.98, 0.85, 0.36)    # version 6: reach this turn (fill)
const COL_REACH_EDGE := Color(1, 0.95, 0.6, 0.95)
const COL_REACH_NEXT := Color(1, 1, 0.9, 0.7)     # ... next turn (dashed outline)
const REACH_NEXT_W := 2.0
const REACH_NEXT_DASH := 7.0                       # dash and gap, screen px
const OWNER_EDGE_A := 0.85                         # owner band inside each territory
const OWNER_EDGE_W := 3.5
const COL_BLOCKED := Color(0.1, 0.1, 0.1, 0.32)    # version 5: a neighbour it cannot enter
const COL_BLOCKED_EDGE := Color(0.15, 0.15, 0.15, 0.85)
## Roads, rivers and hills (version 6). Widths are screen px (times lw).
const COL_RIVER := Color(0.22, 0.46, 0.78, 0.95)
const RIVER_W := 2.4
const COL_ROAD := Color(0.55, 0.4, 0.22, 0.85)
const ROAD_W := 1.7
const COL_HILL := Color(0.25, 0.18, 0.08, 0.2)
const COL_RIDGE := Color(0.2, 0.13, 0.05, 0.3)
## Relief shading (2026-10-10): an elevation field from the grid (ridge 2,
## hill 1, else 0), blurred, lit from the north-west, baked once into an
## image of the grid's size and drawn bilinear over the land fill.
const SHADE_BLUR := 2          # box blur radius in cells, applied twice
const SHADE_SLOPE := 3.0       # slope gain
const SHADE_ALPHA := 0.5       # opacity of the shade at full slope
const SHADE_HEIGHT_A := 0.10   # opacity of the warm height tint per elevation unit
const SHADE_LIGHT := Color(1.0, 0.96, 0.8)
const SHADE_DARK := Color(0.12, 0.08, 0.1)
const SHADE_TINT := Color(1.0, 0.9, 0.62)
const HILL_W := 1.2
const COL_FORD := Color(0.93, 0.9, 0.8, 1.0)
const COL_BRIDGE := Color(0.45, 0.3, 0.15, 1.0)

## Terrain view (2026-10-10): the land is its ground (landscape.gd: palette
## texture, peaks, domes, trees, speckles) with the owner a translucent tint;
## Political is the older look (region fills in owner colour, hatch marks).
## A view preference in user://settings.cfg [map] terrain (never in the
## state); "--map-view=political|terrain" on the command line overrides it
## for the session without saving.
const SETTINGS := "user://settings.cfg"
const TERRAIN_TINT := 0.30   # owner colour alpha over the ground
const COL_BANK_GREEN := Color(0.30, 0.52, 0.26, 0.30)
const BANK_GREEN_W := 11.0
const BANK_W := 4.8
static var terrain_view := true
## The sea (2026-10-10, water.gdshader): a depth tint, waves, currents and
## foam from the coast distance field; "low" keeps the depth tint and foam
## only. A view preference in user://settings.cfg [map] water = low | high
## ("--map-water=low|high" overrides it for the session).
static var water_high := true
static var _land_meshes: Array = []   # triangulated once: the polygons are fine now
static var _land_sz := Vector2.ZERO
static var _cell_meshes: Dictionary = {}   # region -> Array of ArrayMesh
var _water: Node2D = null
static var _pref_loaded := false
static var instance: Node2D = null

## Built once from the grid (view only): hatch segments per kind, road
## polylines, river polylines, crossing glyphs [point, step direction, kind].
static var _hill_segs: Array = []
static var _shade_tex: ImageTexture = null
static var _shade_ms := -1.0   # bake time, ms (for the record)
static var _road_lines: Array = []
static var _river_lines: Array = []
static var _cross_marks: Array = []

var state: Dictionary = {}
var zoom := 1.0
## Regions to highlight as move destinations, and the hovered / selected region.
var targets: Array[int] = []
var attack_targets: Array[int] = []
## Neighbours the selected army cannot enter (muted, crossed out).
var blocked_targets: Array[int] = []
## State version 5: the turn the selected army reaches each target (0 this
## turn: bright; 1 next turn: dimmer; later: outline only).
var target_turns: Dictionary = {}
var selected_region := -1
var pulse := 0.0
## Version 6 reach: cells (map-pixel squares) and smoothed outlines.
var grid := false
var reach_rects: Array = []      # Rect2 per reachable cell this turn (fallback fill)
var reach_fill: Array = []       # outer outlines that triangulate (the fill)
var reach_loops: Array = []      # PackedVector2Array outlines (this turn)
var next_loops: Array = []       # ... within two turns (dashed)
var _next_dashes: Array = []     # next_loops cut into dashes (PackedVector2Array of segment pairs)
var _next_dashes_lw := -1.0      # ... for this line scale


## Set the reach (per cell: 0 this turn, 1 next turn, -1 not), or clear it
## (empty array).
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	load_view_pref()
	instance = self
	_make_water()


## The sea: one quad behind this node's own drawing (the land polygons cover
## it), with water.gdshader reading the coast distance field.
func _make_water() -> void:
	_water = Node2D.new()
	_water.show_behind_parent = true
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	var f := GeoFields.coast()
	var img := Image.create_from_data(GeoFields.fine_width(), GeoFields.fine_height(), false, Image.FORMAT_L8, f)
	m.set_shader_parameter("coast", ImageTexture.create_from_image(img))
	m.set_shader_parameter("field_px", Vector2(GeoFields.fine_width(), GeoFields.fine_height()) * GeoFields.sample_px())
	m.set_shader_parameter("hi", 1.0 if water_high else 0.0)
	_water.material = m
	_water.draw.connect(func(): _water.draw_rect(Rect2(Vector2(-4000, -4000), Geo.SIZE + Vector2(8000, 8000)), SEA))
	add_child(_water)


## Water quality (saved): high = waves, currents and foam, low = depth tint and foam.
static func set_water_high(on: bool, save := true) -> void:
	water_high = on
	if save:
		var cf := ConfigFile.new()
		cf.load(SETTINGS)
		cf.set_value("map", "water", "high" if on else "low")
		cf.save(SETTINGS)
	if instance != null and is_instance_valid(instance):
		var w: Node2D = instance.get("_water")
		if w != null:
			(w.material as ShaderMaterial).set_shader_parameter("hi", 1.0 if on else 0.0)


static func load_view_pref() -> void:
	if _pref_loaded:
		return
	_pref_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		terrain_view = int(cf.get_value("map", "terrain", 1)) != 0
		water_high = str(cf.get_value("map", "water", "high")) != "low"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map-view="):
			terrain_view = a.substr(11) != "political"
		elif a.begins_with("--map-water="):
			water_high = a.substr(12) != "low"


## Switch the view (saved) and redraw the map.
static func set_terrain_view(on: bool, save := true) -> void:
	terrain_view = on
	if save:
		var cf := ConfigFile.new()
		cf.load(SETTINGS)
		cf.set_value("map", "terrain", 1 if on else 0)
		cf.save(SETTINGS)
	if instance != null and is_instance_valid(instance):
		instance.queue_redraw()


func set_reach(rt: PackedInt32Array) -> void:
	reach_rects = []
	reach_loops = []
	next_loops = []
	reach_fill = []
	_next_dashes = []
	_next_dashes_lw = -1.0
	if rt.size() != CGrid.count():
		queue_redraw()
		return
	var px := float(CGrid.cell_px())
	var now := PackedByteArray()
	var two := PackedByteArray()
	now.resize(rt.size())
	two.resize(rt.size())
	for c in rt.size():
		if rt[c] == 0:
			now[c] = 1
			reach_rects.append(Rect2(CGrid.cx(c) * px, CGrid.cy(c) * px, px, px))
		if rt[c] >= 0:
			two[c] = 1
	reach_loops = outline(now)
	next_loops = outline(two)
	reach_fill = []
	var ok := true
	for lp in reach_loops:
		if _area(lp) > 0.0:
			if Geometry2D.triangulate_polygon(lp).is_empty():
				ok = false
			else:
				reach_fill.append(lp)
	if ok:
		reach_rects = []  # the smooth shapes fill it
	queue_redraw()


## Outlines of a set of cells (1 in `on`): the boundary edges chained into
## loops (map pixels), corners cut twice (Chaikin) so they read smooth.
static func outline(on: PackedByteArray) -> Array:
	var w := CGrid.width()
	var h := CGrid.height()
	var px := float(CGrid.cell_px())
	var nxt := {}  # start vertex key -> Array of end vertex keys
	var vw := w + 1
	for c in on.size():
		if on[c] == 0:
			continue
		var x := c % w
		var y := c / w
		# Clockwise edges (screen y down); only those facing outside.
		if y == 0 or on[c - w] == 0:
			_edge(nxt, y * vw + x, y * vw + x + 1)
		if x == w - 1 or on[c + 1] == 0:
			_edge(nxt, y * vw + x + 1, (y + 1) * vw + x + 1)
		if y == h - 1 or on[c + w] == 0:
			_edge(nxt, (y + 1) * vw + x + 1, (y + 1) * vw + x)
		if x == 0 or on[c - 1] == 0:
			_edge(nxt, (y + 1) * vw + x, y * vw + x)
	var loops: Array = []
	var starts := nxt.keys()
	starts.sort()
	for s0 in starts:
		while nxt.has(s0) and not (nxt[s0] as Array).is_empty():
			var pts := PackedVector2Array()
			var v: int = s0
			for guard in 100000:
				pts.append(Vector2((v % vw) * px, (v / vw) * px))
				var outs: Array = nxt.get(v, [])
				if outs.is_empty():
					break
				var nv: int = outs.pop_back()
				v = nv
				if v == s0:
					break
			if pts.size() >= 3:
				# Edge midpoints turn the cells' staircases into diagonals;
				# then two rounds of corner cutting.
				var mids := PackedVector2Array()
				for i in pts.size():
					mids.append((pts[i] + pts[(i + 1) % pts.size()]) * 0.5)
				loops.append(_smooth(_smooth(mids)))
	return loops


static func _edge(nxt: Dictionary, a: int, b: int) -> void:
	if not nxt.has(a):
		nxt[a] = []
	(nxt[a] as Array).append(b)


## Shoelace sum (positive: an outer outline, negative: a hole).
static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return a


## One Chaikin pass over a closed polygon.
static func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


## Land colour of region r owned by o: its ground palette, then the owner.
static func region_color(r: int, o: int) -> Color:
	var g := GroundPalette.land_color(int(CData.REGIONS[r]["ground"])).lightened(GROUND_LIFT)
	if o < 0:
		return g.lerp(Color(0.55, 0.55, 0.52), 0.25)
	return g.lerp(CData.faction_color(o), TINT)


## A polygon as a mesh (triangulated once, with uv = point / sz), or null.
static func _poly_mesh(poly: PackedVector2Array, sz: Vector2) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return null
	var uv := PackedVector2Array()
	uv.resize(poly.size())
	for i in poly.size():
		uv[i] = poly[i] / sz
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = poly
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## The land and island polygons as meshes, uv over the grid's size sz.
static func land_meshes(sz: Vector2) -> Array:
	if _land_meshes.is_empty() or _land_sz != sz:
		_land_meshes = []
		_land_sz = sz
		for poly in Geo.lands() + Geo.islands():
			var m := _poly_mesh(poly, sz)
			if m != null:
				_land_meshes.append(m)
	return _land_meshes


## Fill region r's territory with col (cached meshes: the territory polygons
## follow the fine coast and are too big to triangulate at every redraw).
func _fill_cell(r: int, col: Color) -> void:
	for m in cell_meshes(r):
		draw_mesh(m, null, Transform2D.IDENTITY, col)


static func cell_meshes(r: int) -> Array:
	if not _cell_meshes.has(r):
		var ms: Array = []
		for piece in Geo.cell(r):
			var m := _poly_mesh(piece, Vector2.ONE)
			if m != null:
				ms.append(m)
		_cell_meshes[r] = ms
	return _cell_meshes[r]


func _draw() -> void:
	var lw := 1.0 / maxf(zoom, 0.05)
	var land_view := terrain_view and grid and not state.is_empty()
	if land_view:
		_terrain_geometry()
	# (The sea is the water node behind this one.)
	var lsz := Vector2(CGrid.width(), CGrid.height()) * float(CGrid.cell_px())
	var lmeshes := land_meshes(lsz)
	for m in lmeshes:
		draw_mesh(m, null, Transform2D.IDENTITY, LAND)
	if state.is_empty():
		return
	# Territories.
	# Each region's land is its ground palette (the colour of its battle
	# maps: arid, dry, green, rocky), tinted by its owner.
	if land_view:
		# Terrain view: the ground texture over the land, the owner a
		# translucent tint over it.
		for m in lmeshes:
			draw_mesh(m, Landscape.ground_tex)
		for r in CData.region_count():
			var o := CState.owner(state, r)
			if o >= 0:
				var tc := CData.faction_color(o)
				tc.a = TERRAIN_TINT
				_fill_cell(r, tc)
		# Rivers: a faint green and a pale bank under the blue line.
		for ln in _river_lines:
			draw_polyline(ln, COL_BANK_GREEN, BANK_GREEN_W * lw, true)
			draw_polyline(ln, Landscape.COL_BANK, (RIVER_W + BANK_W) * lw, true)
	else:
		for r in CData.region_count():
			var o := CState.owner(state, r)
			var col := region_color(r, o)
			_fill_cell(r, col)
	if grid:
		_terrain_geometry()
		var rtex: Texture2D = Landscape.relief_tex if land_view else _shade_tex
		if rtex != null:
			for m in lmeshes:
				draw_mesh(m, rtex)
		if land_view:
			draw_mesh(Landscape.mesh, null)
		else:
			draw_hills(self, _hill_segs[0], 0, lw)
			draw_hills(self, _hill_segs[1], 1, lw)
		_draw_reach(lw)
	# Destinations of the selected army.
	var a := 0.25 + 0.15 * sin(pulse * 4.0)
	for r in targets:
		var tt := int(target_turns.get(r, 0))
		if tt >= 2:
			continue
		var hc := target_fill(attack_targets.has(r), tt, a)
		_fill_cell(r, hc)
	for r in blocked_targets:
		_fill_cell(r, COL_BLOCKED)
	if selected_region >= 0:
		_fill_cell(selected_region, Color(1, 1, 0.8, 0.22))
	# Owner edge: a band of the owner's colour inside each territory, so the
	# owner reads at once whatever the ground.
	for r in CData.region_count():
		var o := CState.owner(state, r)
		if o < 0:
			continue
		var ec := CData.faction_color(o)
		ec.a = OWNER_EDGE_A
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, ec, OWNER_EDGE_W * lw, true)
	# Borders between territories (darker where owners differ is implied by
	# the tint; one thin line everywhere keeps it light).
	for r in CData.region_count():
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, Color(0.1, 0.1, 0.08, 0.45), 1.2 * lw, true)
	for r in targets:
		var te := target_edge(attack_targets.has(r), int(target_turns.get(r, 0)))
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, te[0], float(te[1]) * lw, true)
	for r in blocked_targets:
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, COL_BLOCKED_EDGE, 2.0 * lw, true)
		# A small cross on the settlement: "not this turn".
		draw_blocked_cross(self, Geo.site(r), lw)
	if selected_region >= 0:
		for piece in Geo.cell(selected_region):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, Color(1, 1, 0.75, 1.0), 3.0 * lw, true)
	# Coastline.
	for poly in Geo.lands() + Geo.islands():
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, COAST, 1.3 * lw, true)
	# Land routes (dashed) and sea lanes (dotted, light blue).
	if grid:
		# Roads, rivers and the crossings over them.
		for ln in _road_lines:
			draw_road(self, ln, lw)
		for ln in _river_lines:
			draw_river(self, ln, lw)
		for cm in _cross_marks:
			if int(cm[2]) == 0:
				draw_ford(self, cm[0], cm[1], lw)
			else:
				draw_bridge(self, cm[0], cm[1], lw)
		# Version 6: armies walk the grid; sea lanes join the port cells.
		var px := float(CGrid.cell_px())
		for pair in CData.SEA_LANES:
			var c0 := CGrid.port(CData.region_index(pair[0]))
			var c1 := CGrid.port(CData.region_index(pair[1]))
			var p0 := Vector2((CGrid.cx(c0) + 0.5) * px, (CGrid.cy(c0) + 0.5) * px)
			var p1 := Vector2((CGrid.cx(c1) + 0.5) * px, (CGrid.cy(c1) + 0.5) * px)
			draw_sea_lane(self, p0, p1, lw)
		return
	for pair in CData.ROUTES:
		var p0 := Geo.site(CData.region_index(pair[0]))
		var p1 := Geo.site(CData.region_index(pair[1]))
		draw_route(self, p0, p1, lw)
	for pair in CData.SEA_LANES:
		var p0 := Geo.site(CData.region_index(pair[0]))
		var p1 := Geo.site(CData.region_index(pair[1]))
		draw_sea_lane(self, p0, p1, lw)


## The steps of preparing the campaign map for the loading panel:
## [[label, Callable], ...] (each is cheap once done).
static func prepare_steps() -> Array:
	return [["Building the map", geometry_lines],
		["Shading the relief (first time only)" if not Landscape.relief_cached() else "Loading the relief", Landscape.bake_relief],
		["Painting the landscape", Landscape.bake_land]]


## The roads, rivers and hills geometry from the grid (once).
static func _terrain_geometry() -> void:
	if not _hill_segs.is_empty():
		return
	Landscape.bake()
	geometry_lines()


## The map's own geometry without the landscape bake: the territory and land
## meshes, hills, the shade, roads, rivers and crossings (once). The loading
## panel runs it as its own step.
static func geometry_lines() -> void:
	if not _hill_segs.is_empty():
		return
	var gsz := Vector2(CGrid.width(), CGrid.height()) * float(CGrid.cell_px())
	land_meshes(gsz)
	for r in CData.region_count():
		cell_meshes(r)
	var px := float(CGrid.cell_px())
	var hills := PackedVector2Array()
	var ridges := PackedVector2Array()  # (packed arrays are values: one variable each)
	for c in CGrid.count():
		var ov := CGrid.terrain_override(c)
		if ov < 0:
			continue
		var ctr := Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px)
		if ov == CData.RIDGE:
			ridges.append_array(hill_mark(ctr, px, 1))
		else:
			hills.append_array(hill_mark(ctr, px, 0))
	_hill_segs = [hills, ridges]
	var t0 := Time.get_ticks_usec()
	var elev := PackedFloat32Array()
	elev.resize(CGrid.count())
	for c in CGrid.count():
		var ov2 := CGrid.terrain_override(c)
		elev[c] = 2.0 if ov2 == CData.RIDGE else (1.0 if ov2 >= 0 else 0.0)
	_shade_tex = ImageTexture.create_from_image(shade_image(elev, CGrid.width(), CGrid.height()))
	_shade_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var w := CGrid.width()
	for ri in Geo.ROADS.size():
		var cells := Geo.line_cells(Geo.road_line(ri), px, w, CGrid.height())
		var pts := PackedVector2Array()
		for k in cells.size():
			var c := cells[k]
			# Leave out the corner cells a diagonal run steps through (the
			# line reads straighter); keep both ends.
			if k > 0 and k < cells.size() - 1:
				var p0 := cells[k - 1]
				var p1 := cells[k + 1]
				if absi(p0 % w - p1 % w) == 1 and absi(p0 / w - p1 / w) == 1:
					continue
			pts.append(Vector2((c % w + 0.5) * px, (c / w + 0.5) * px))
		if pts.size() >= 2:
			_road_lines.append(_smooth_open(_smooth_open(pts)))
	for vi in Geo.RIVERS.size():
		_river_lines.append(Geo.river_line(vi))
	var info := Geo.crossings()
	for id in CGrid.crossing_count():
		var cr := CGrid.crossing(id)
		var a := Vector2((CGrid.cx(int(cr[0])) + 0.5) * px, (CGrid.cy(int(cr[0])) + 0.5) * px)
		var b := Vector2((CGrid.cx(int(cr[1])) + 0.5) * px, (CGrid.cy(int(cr[1])) + 0.5) * px)
		var at := (a + b) * 0.5
		if id < info.size():
			var line: PackedVector2Array = _river_lines[int(info[id]["river"])]
			for k in line.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, line[k], line[k + 1])
				if hit != null:
					at = hit
					break
		_cross_marks.append([at, (b - a).normalized(), int(cr[2])])


## Crossing id at map point p (within `rad` map px of its glyph), -1 none.
static func crossing_near(p: Vector2, rad: float) -> int:
	_terrain_geometry()
	var best := -1
	var bd := rad
	for id in _cross_marks.size():
		var d := p.distance_to(_cross_marks[id][0])
		if d <= bd:
			bd = d
			best = id
	return best


## One Chaikin pass over an open polyline (ends kept).
static func _smooth_open(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out


## Relief image of an elevation field (w x h floats): blurred, lit from the
## north-west; transparent on flat ground, dark on south-east slopes, light
## on north-west ones, a faint warm tint with height.
static func shade_image(elev: PackedFloat32Array, w: int, h: int) -> Image:
	var e := elev
	for _pass in 2:
		for horiz in 2:
			var o := PackedFloat32Array()
			o.resize(w * h)
			for y in h:
				for x in w:
					var sum := 0.0
					var n := 0
					for d in range(-SHADE_BLUR, SHADE_BLUR + 1):
						var xx := x + d if horiz == 0 else x
						var yy := y if horiz == 0 else y + d
						if xx >= 0 and yy >= 0 and xx < w and yy < h:
							sum += e[yy * w + xx]
							n += 1
					o[y * w + x] = sum / n
			e = o
	var light := Vector3(-1.0, -1.0, 1.1).normalized()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (e[y * w + mini(x + 1, w - 1)] - e[y * w + maxi(x - 1, 0)]) * 0.5
			var dy := (e[mini(y + 1, h - 1) * w + x] - e[maxi(y - 1, 0) * w + x]) * 0.5
			var nrm := Vector3(-dx * SHADE_SLOPE, -dy * SHADE_SLOPE, 1.0).normalized()
			var sh := clampf((nrm.dot(light) - light.z) * 2.2, -1.0, 1.0)
			var ht := clampf(e[y * w + x], 0.0, 2.0)
			var col := SHADE_LIGHT if sh > 0.0 else SHADE_DARK
			var a := absf(sh) * SHADE_ALPHA
			# warm tint with height: composite under the shade
			var ta := ht * SHADE_HEIGHT_A
			var oa := a + ta * (1.0 - a)
			var rgb := Color(col.r * a + SHADE_TINT.r * ta * (1.0 - a), col.g * a + SHADE_TINT.g * ta * (1.0 - a),
				col.b * a + SHADE_TINT.b * ta * (1.0 - a)) / maxf(oa, 0.001)
			img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, oa))
	return img


static var _sample_tex: ImageTexture = null

## The key's hills row: a hill and a ridge shaded as on the map.
static func draw_shade_sample(ci: CanvasItem, rc: Rect2) -> void:
	if _sample_tex == null:
		var w := 16
		var h := 6
		var el := PackedFloat32Array()
		el.resize(w * h)
		for y in h:
			for x in w:
				el[y * w + x] = (1.0 if x >= 3 and x <= 5 and y >= 1 and y <= 4 else 0.0) \
					+ (2.0 if x >= 10 and x <= 12 and y >= 1 and y <= 4 else 0.0)
		_sample_tex = ImageTexture.create_from_image(shade_image(el, w, h))
	ci.draw_texture_rect(_sample_tex, rc, false)


## Hatch of a hill (kind 0: one chevron) or ridge (1: two) cell of size
## `px` centred on ctr: segment pairs for draw_multiline.
static func hill_mark(ctr: Vector2, px: float, kind: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var hw := px * (0.22 if kind == 0 else 0.26)
	var hh := px * (0.16 if kind == 0 else 0.22)
	var offs: Array = [Vector2(0, px * 0.08)] if kind == 0 else [Vector2(-px * 0.18, px * 0.12), Vector2(px * 0.18, px * 0.12)]
	for o in offs:
		var base: Vector2 = ctr + o
		out.append_array(PackedVector2Array([base + Vector2(-hw, 0), base + Vector2(0, -hh),
			base + Vector2(0, -hh), base + Vector2(hw, 0)]))
	return out


static func draw_hills(ci: CanvasItem, segs: PackedVector2Array, kind: int, lw: float) -> void:
	if segs.size() >= 2:
		ci.draw_multiline(segs, COL_HILL if kind == 0 else COL_RIDGE, HILL_W * lw, true)


static func draw_river(ci: CanvasItem, pts: PackedVector2Array, lw: float) -> void:
	ci.draw_polyline(pts, COL_RIVER, RIVER_W * lw, true)


static func draw_road(ci: CanvasItem, pts: PackedVector2Array, lw: float) -> void:
	ci.draw_polyline(pts, COL_ROAD, ROAD_W * lw, true)


## A ford: the river broken by three pale stepping stones along the step.
static func draw_ford(ci: CanvasItem, p: Vector2, dir: Vector2, lw: float) -> void:
	ci.draw_circle(p, 5.2 * lw, Color(0.2, 0.15, 0.08, 0.6))
	for k in [-1, 0, 1]:
		ci.draw_circle(p + dir * (3.1 * lw * k), 1.4 * lw, COL_FORD)


## A bridge: a short deck over the river along the step, dark edged.
static func draw_bridge(ci: CanvasItem, p: Vector2, dir: Vector2, lw: float) -> void:
	var half := dir * (6.5 * lw)
	ci.draw_line(p - half, p + half, Color(0.1, 0.07, 0.03, 0.9), 5.4 * lw, true)
	ci.draw_line(p - half, p + half, COL_BRIDGE.lightened(0.3), 3.2 * lw, true)


## A sea lane (dotted, light blue) between two ports.
static func draw_sea_lane(ci: CanvasItem, p0: Vector2, p1: Vector2, lw: float) -> void:
	ci.draw_dashed_line(p0, p1, COL_SEA_LANE, LANE_W * lw, SEA_LANE_DASH * lw, true)


## Versions 1-5: a land route (dashed, brown) between two settlements.
static func draw_route(ci: CanvasItem, p0: Vector2, p1: Vector2, lw: float) -> void:
	ci.draw_dashed_line(p0, p1, COL_ROUTE, LANE_W * lw, ROUTE_DASH * lw, true)


## Version 6: an outline of this turn's reach (closed polyline).
static func draw_reach_edge(ci: CanvasItem, closed: PackedVector2Array, lw: float) -> void:
	ci.draw_polyline(closed, Color(0, 0, 0, 0.5), 4.5 * lw, true)
	ci.draw_polyline(closed, COL_REACH_EDGE, 2.4 * lw, true)


## Version 6: an outline of next turn's reach: dashed, light over a dark
## shadow (clearly visible on light land, unlike this turn's solid bright
## edge).
static func draw_next_edge(ci: CanvasItem, closed: PackedVector2Array, lw: float) -> void:
	draw_next_dashes(ci, next_dashes(closed, lw), lw)


## The dashes of a closed outline (dash and gap REACH_NEXT_DASH screen px,
## running on round the corners): segment pairs for draw_multiline.
static func next_dashes(closed: PackedVector2Array, lw: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var dash := REACH_NEXT_DASH * lw
	var t := 0.0  # position in the dash + gap period
	for i in closed.size() - 1:
		var a := closed[i]
		var b := closed[i + 1]
		var ln := a.distance_to(b)
		var s := 0.0
		while s < ln:
			var left := maxf((dash - t) if t < dash else (2.0 * dash - t), 0.01)
			var e := minf(s + left, ln)
			if t < dash:
				out.append(a.lerp(b, s / ln))
				out.append(a.lerp(b, e / ln))
			t = fmod(t + (e - s), 2.0 * dash)
			s = e
	return out


static func draw_next_dashes(ci: CanvasItem, segs: PackedVector2Array, lw: float) -> void:
	if segs.size() < 2:
		return
	ci.draw_multiline(segs, Color(0, 0, 0, 0.45), (REACH_NEXT_W + 2.0) * lw, true)
	ci.draw_multiline(segs, COL_REACH_NEXT, REACH_NEXT_W * lw, true)


## Version 5: a destination's fill (turns 0 this turn, 1 next; attack: an
## enemy region) at pulse phase a (0.1 - 0.4).
static func target_fill(attack: bool, turns: int, a: float) -> Color:
	var hc := Color(1, 1, 1, a) if not attack else Color(1.0, 0.35, 0.25, a + 0.1)
	if turns == 1:
		hc.a *= 0.4
	return hc


## Version 5: a destination's outline [colour, width (times lw)].
static func target_edge(attack: bool, turns: int) -> Array:
	var oc := Color(1, 1, 1, 0.9) if not attack else Color(1, 0.5, 0.4, 0.95)
	if turns >= 1:
		oc.a = 0.55 if turns == 1 else 0.3
	return [oc, 2.5 if turns == 0 else 1.6]


## Version 5: a neighbour the army cannot enter: a cross on its settlement.
static func draw_blocked_cross(ci: CanvasItem, c: Vector2, lw: float) -> void:
	var k := 9.0 * lw
	ci.draw_line(c + Vector2(-k, -k), c + Vector2(k, k), Color(0.1, 0.1, 0.1, 0.9), 2.5 * lw, true)
	ci.draw_line(c + Vector2(k, -k), c + Vector2(-k, k), Color(0.1, 0.1, 0.1, 0.9), 2.5 * lw, true)


## Version 6: the selected army's reach (this turn filled, next turn a
## dashed outline).
func _draw_reach(lw: float) -> void:
	if reach_loops.is_empty():
		return
	if reach_rects.is_empty():
		for lp in reach_fill:
			draw_colored_polygon(lp, COL_REACH)
	for rc in reach_rects:
		draw_rect(rc, COL_REACH)
	if not is_equal_approx(_next_dashes_lw, lw):
		# Map redraws every frame while an army is selected: cut the dashes
		# again only when the zoom changes.
		_next_dashes = []
		_next_dashes_lw = lw
		for lp in next_loops:
			var closed: PackedVector2Array = (lp as PackedVector2Array).duplicate()
			closed.append(lp[0])
			_next_dashes.append(next_dashes(closed, lw))
	for segs in _next_dashes:
		draw_next_dashes(self, segs, lw)
	for lp in reach_loops:
		var closed2: PackedVector2Array = (lp as PackedVector2Array).duplicate()
		closed2.append(lp[0])
		draw_reach_edge(self, closed2, lw)
