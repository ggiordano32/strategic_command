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
## sea lanes join the port cells.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const GroundPalette := preload("res://game/ground_palette.gd")
const CGrid := preload("res://campaign/cgrid.gd")

const SEA := Color(0.13, 0.25, 0.34)
const SEA_SHALLOW := Color(0.22, 0.38, 0.47)
const LAND := Color(0.80, 0.76, 0.62)
const COAST := Color(0.16, 0.18, 0.16, 0.9)
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


func _draw() -> void:
	var lw := 1.0 / maxf(zoom, 0.05)
	draw_rect(Rect2(Vector2(-4000, -4000), Geo.SIZE + Vector2(8000, 8000)), SEA)
	# Shallow water: a soft band along every coast.
	for poly in Geo.lands() + Geo.islands():
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, SEA_SHALLOW, 14.0, true)
	for poly in Geo.islands():
		draw_colored_polygon(poly, LAND)
	for poly in Geo.lands():
		draw_colored_polygon(poly, LAND)
	if state.is_empty():
		return
	# Territories.
	# Each region's land is its ground palette (the colour of its battle
	# maps: arid, dry, green, rocky), tinted by its owner.
	for r in CData.region_count():
		var o := CState.owner(state, r)
		var col := region_color(r, o)
		for piece in Geo.cell(r):
			draw_colored_polygon(piece, col)
	if grid:
		_draw_reach(lw)
	# Destinations of the selected army.
	var a := 0.25 + 0.15 * sin(pulse * 4.0)
	for r in targets:
		var tt := int(target_turns.get(r, 0))
		if tt >= 2:
			continue
		var hc := target_fill(attack_targets.has(r), tt, a)
		for piece in Geo.cell(r):
			draw_colored_polygon(piece, hc)
	for r in blocked_targets:
		for piece in Geo.cell(r):
			draw_colored_polygon(piece, COL_BLOCKED)
	if selected_region >= 0:
		for piece in Geo.cell(selected_region):
			draw_colored_polygon(piece, Color(1, 1, 0.8, 0.22))
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
		draw_polyline(closed, COAST, 1.6 * lw, true)
	# Land routes (dashed) and sea lanes (dotted, light blue).
	if grid:
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
