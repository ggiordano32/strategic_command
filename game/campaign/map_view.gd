extends Node2D
## Campaign map, world layer (map pixels; the camera pans and zooms it):
## sea, land, territories tinted by owner, borders, land routes and sea lanes,
## and the highlighted destinations of the selected army. Markers and text
## are drawn by map_overlay.gd in screen space so they stay crisp and sized
## for touch at any zoom.
##
## State version 6: the selected army's reach this turn is a filled
## translucent area with a smoothed outline (cells from CRules.reach6; next
## turn's a dimmer outline); land routes are gone (armies walk the grid),
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
var next_loops: Array = []       # ... within two turns (dimmer)
var reach_hostile := false


## Set the reach (per cell: 0 this turn, 1 next turn, -1 not), or clear it
## (empty array).
func set_reach(rt: PackedInt32Array) -> void:
	reach_rects = []
	reach_loops = []
	next_loops = []
	reach_fill = []
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
		var hc := Color(1, 1, 1, a) if not attack_targets.has(r) else Color(1.0, 0.35, 0.25, a + 0.1)
		var tt := int(target_turns.get(r, 0))
		if tt >= 2:
			continue
		if tt == 1:
			hc.a *= 0.4
		for piece in Geo.cell(r):
			draw_colored_polygon(piece, hc)
	for r in blocked_targets:
		for piece in Geo.cell(r):
			draw_colored_polygon(piece, Color(0.1, 0.1, 0.1, 0.32))
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
		ec.a = 0.85
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, ec, 3.5 * lw, true)
	# Borders between territories (darker where owners differ is implied by
	# the tint; one thin line everywhere keeps it light).
	for r in CData.region_count():
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, Color(0.1, 0.1, 0.08, 0.45), 1.2 * lw, true)
	for r in targets:
		var tt := int(target_turns.get(r, 0))
		var oc := Color(1, 1, 1, 0.9) if not attack_targets.has(r) else Color(1, 0.5, 0.4, 0.95)
		if tt >= 1:
			oc.a = 0.55 if tt == 1 else 0.3
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, oc, (2.5 if tt == 0 else 1.6) * lw, true)
	for r in blocked_targets:
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, Color(0.15, 0.15, 0.15, 0.85), 2.0 * lw, true)
		# A small cross on the settlement: "not this turn".
		var c := Geo.site(r)
		var k := 9.0 * lw
		draw_line(c + Vector2(-k, -k), c + Vector2(k, k), Color(0.1, 0.1, 0.1, 0.9), 2.5 * lw, true)
		draw_line(c + Vector2(k, -k), c + Vector2(-k, k), Color(0.1, 0.1, 0.1, 0.9), 2.5 * lw, true)
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
			draw_dashed_line(p0, p1, Color(0.75, 0.9, 1.0, 0.6), 1.6 * lw, 3.0 * lw, true)
		return
	for pair in CData.ROUTES:
		var p0 := Geo.site(CData.region_index(pair[0]))
		var p1 := Geo.site(CData.region_index(pair[1]))
		draw_dashed_line(p0, p1, Color(0.25, 0.18, 0.1, 0.55), 1.6 * lw, 7.0 * lw, true)
	for pair in CData.SEA_LANES:
		var p0 := Geo.site(CData.region_index(pair[0]))
		var p1 := Geo.site(CData.region_index(pair[1]))
		draw_dashed_line(p0, p1, Color(0.75, 0.9, 1.0, 0.6), 1.6 * lw, 3.0 * lw, true)


## Version 6: the selected army's reach (this turn filled, next turn a
## dim outline).
func _draw_reach(lw: float) -> void:
	if reach_loops.is_empty():
		return
	var col := Color(1.0, 0.98, 0.85, 0.36) if not reach_hostile else Color(1.0, 0.6, 0.45, 0.36)
	if reach_rects.is_empty():
		for lp in reach_fill:
			draw_colored_polygon(lp, col)
	for rc in reach_rects:
		draw_rect(rc, col)
	for lp in next_loops:
		var closed: PackedVector2Array = (lp as PackedVector2Array).duplicate()
		closed.append(lp[0])
		draw_polyline(closed, Color(1, 1, 0.85, 0.35), 1.5 * lw, true)
	for lp in reach_loops:
		var closed2: PackedVector2Array = (lp as PackedVector2Array).duplicate()
		closed2.append(lp[0])
		draw_polyline(closed2, Color(0, 0, 0, 0.5), 4.5 * lw, true)
		draw_polyline(closed2, Color(1, 0.95, 0.6, 0.95), 2.4 * lw, true)
