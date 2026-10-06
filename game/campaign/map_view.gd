extends Node2D
## Campaign map, world layer (map pixels; the camera pans and zooms it):
## sea, land, territories tinted by owner, borders, land routes and sea lanes,
## and the highlighted destinations of the selected army. Markers and text
## are drawn by map_overlay.gd in screen space so they stay crisp and sized
## for touch at any zoom.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const GroundPalette := preload("res://game/ground_palette.gd")

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
var selected_region := -1
var pulse := 0.0


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
	# Destinations of the selected army.
	var a := 0.25 + 0.15 * sin(pulse * 4.0)
	for r in targets:
		var hc := Color(1, 1, 1, a) if not attack_targets.has(r) else Color(1.0, 0.35, 0.25, a + 0.1)
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
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, Color(1, 1, 1, 0.9) if not attack_targets.has(r) else Color(1, 0.5, 0.4, 0.95), 2.5 * lw, true)
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
	for pair in CData.ROUTES:
		var p0 := Geo.site(CData.region_index(pair[0]))
		var p1 := Geo.site(CData.region_index(pair[1]))
		draw_dashed_line(p0, p1, Color(0.25, 0.18, 0.1, 0.55), 1.6 * lw, 7.0 * lw, true)
	for pair in CData.SEA_LANES:
		var p0 := Geo.site(CData.region_index(pair[0]))
		var p1 := Geo.site(CData.region_index(pair[1]))
		draw_dashed_line(p0, p1, Color(0.75, 0.9, 1.0, 0.6), 1.6 * lw, 3.0 * lw, true)
