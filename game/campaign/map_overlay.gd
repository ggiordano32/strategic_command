extends Node2D
## Campaign map, screen layer: settlements (size by level, a wall ring with
## towers per wall level,
## gold dot for the key cities), names, pending battles, sieges (a ring of
## tents round the settlement in the besieger's colour), army markers
## (faction colour, unit count, strength bar), planned moves as arrows (red
## an assault, orange a siege), and hit tests for taps. Positions come from map_geo.gd through `xform` (map
## pixels -> screen), set by the campaign screen every frame.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Geo := preload("res://game/campaign/map_geo.gd")

const ARMY_W := 30.0
const ARMY_H := 26.0
const ARMY_GAP := 4.0
const SITE_R := [5.0, 7.0, 9.5]
const FONT := 13

var state: Dictionary = {}
var xform := Transform2D.IDENTITY
var zoom := 1.0
var selected_army := -1
var player := -1
## Planned moves of the player planning now: [[army id, to region], ...].
var moves: Array = []
var attack_moves: Array[int] = []  # army ids whose move is an attack
var siege_moves: Array[int] = []   # ... of which these lay siege (or join one)
var pulse := 0.0


func to_screen(p: Vector2) -> Vector2:
	return xform * p


## Marker scale: full size from zoom 0.7 up, down to half when zoomed out.
func mk() -> float:
	return clampf(zoom / 0.7, 0.5, 1.0)


## Screen position of each army marker: {id: Vector2}.
func army_positions() -> Dictionary:
	var out := {}
	if state.is_empty():
		return out
	var by_region := {}
	for a in state["armies"]:
		var r := int(a["r"])
		if not by_region.has(r):
			by_region[r] = []
		by_region[r].append(a)
	for r in by_region:
		var list: Array = by_region[r]
		var m := mk()
		var c := to_screen(Geo.site(r)) + Vector2(0, (ARMY_H * 0.5 + 12.0) * m)
		var n := list.size()
		var step := (ARMY_W + ARMY_GAP) * m * (0.8 if m < 0.8 else 1.0)
		for k in n:
			var off := (k - (n - 1) * 0.5) * step
			out[int(list[k]["id"])] = c + Vector2(off, 0)
	return out


func army_at(p: Vector2) -> int:
	var pos := army_positions()
	var best := -1
	var best_d := 1e9
	for id in pos:
		var q: Vector2 = pos[id]
		var d := q.distance_to(p)
		var hit := absf(p.x - q.x) <= ARMY_W * 0.5 * mk() + 6.0 and absf(p.y - q.y) <= ARMY_H * 0.5 * mk() + 8.0
		if hit and d < best_d:
			best = int(id)
			best_d = d
	return best


func settlement_at(p: Vector2) -> int:
	for r in CData.region_count():
		if to_screen(Geo.site(r)).distance_to(p) <= 16.0:
			return r
	return -1


func _draw() -> void:
	if state.is_empty():
		return
	var font := ThemeDB.fallback_font
	var pos := army_positions()
	# Planned moves (under the markers).
	for m in moves:
		var id := int(m[0])
		if not pos.has(id):
			continue
		var from: Vector2 = pos[id]
		var to := to_screen(Geo.site(int(m[1]))) + Vector2(0, 8)
		var col := Color(1, 1, 1)
		if siege_moves.has(id):
			col = Color(1.0, 0.7, 0.25)
		elif attack_moves.has(id):
			col = Color(1.0, 0.45, 0.35)
		_arrow(from, to, col)
	# Settlements and names.
	var show_names := zoom >= 0.5
	for r in CData.region_count():
		var p := to_screen(Geo.site(r))
		var rs: Dictionary = state["regions"][r]
		var lvl := int(rs["level"])
		var rad: float = SITE_R[lvl] * mk()
		var o := int(rs["owner"])
		var fill := CData.faction_color(o).darkened(0.35)
		var w := CState.walls(state, r)
		if w > 0:
			_wall_ring(p, rad, w)
		draw_circle(p, rad + 1.5, Color(1, 1, 1, 0.95))
		draw_circle(p, rad, fill)
		var sg := CState.siege_at(state, r)
		if not sg.is_empty():
			_siege_ring(p, rad + (6.0 + 1.2 * w) * mk(), int(sg["f"]))
		if CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"])):
			draw_circle(p, rad * 0.4, Color(1.0, 0.85, 0.3))
		if show_names or lvl == CData.CITY:
			var nm := str(CData.REGIONS[r]["city"])
			var fs := int(round(FONT * (0.85 + 0.15 * mk())))
			var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp := p + Vector2(-tw * 0.5, -rad - 5.0)
			draw_string_outline(font, tp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.75))
			draw_string(font, tp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 0.95))
	# Pending battles.
	for b in state["battles"]:
		var p := to_screen(Geo.site(int(b["r"]))) + Vector2(16, -14)
		draw_circle(p, 11.0, Color(0.75, 0.1, 0.08, 0.95))
		draw_arc(p, 11.0, 0, TAU, 20, Color(1, 1, 1), 1.5, true)
		draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), Color.WHITE, 2.2, true)
		draw_line(p + Vector2(5, -5), p + Vector2(-5, 5), Color.WHITE, 2.2, true)
	# Armies.
	for a in state["armies"]:
		var id := int(a["id"])
		if not pos.has(id):
			continue
		_army_marker(pos[id], a, font)


## Walls: a stone ring round the settlement with towers on it, thicker and
## with more towers per wall level (1-3).
func _wall_ring(p: Vector2, rad: float, w: int) -> void:
	var m := mk()
	var rr := rad + (3.0 + 1.2 * w) * m
	var th := (1.6 + 0.9 * w) * m
	draw_arc(p, rr, 0, TAU, 32, Color(0.12, 0.11, 0.09, 0.95), th + 1.6, true)
	draw_arc(p, rr, 0, TAU, 32, Color(0.78, 0.74, 0.64), th, true)
	var n := 4 + 2 * w
	var ts := (2.0 + 0.7 * w) * m
	for k in n:
		var a := TAU * k / n - PI * 0.5
		var c := p + Vector2(cos(a), sin(a)) * rr
		draw_rect(Rect2(c - Vector2(ts, ts) - Vector2(0.8, 0.8), Vector2(ts, ts) * 2.0 + Vector2(1.6, 1.6)), Color(0.12, 0.11, 0.09, 0.95))
		draw_rect(Rect2(c - Vector2(ts, ts), Vector2(ts, ts) * 2.0), Color(0.84, 0.80, 0.70))


## Siege: a dashed ring in the besieger's colour with tents on its upper
## half (the army banners stand below the settlement).
func _siege_ring(p: Vector2, rad: float, f: int) -> void:
	var m := mk()
	var rr := rad + 6.0 * m
	var col := CData.faction_color(f)
	var n := 12
	for k in n:
		var a0 := TAU * k / n
		draw_arc(p, rr, a0, a0 + TAU / n * 0.6, 6, Color(0, 0, 0, 0.75), 5.0 * m, true)
		draw_arc(p, rr, a0, a0 + TAU / n * 0.6, 6, col.lightened(0.25), 3.0 * m, true)
	var ts := 5.5 * m
	for k in 5:
		var a := PI + PI * (k + 0.5) / 5  # left, over the top, to the right
		var c := p + Vector2(cos(a), sin(a)) * rr
		var tri := PackedVector2Array([c + Vector2(0, -ts), c + Vector2(ts, ts * 0.8), c + Vector2(-ts, ts * 0.8)])
		draw_colored_polygon(tri, col)
		var o := tri.duplicate()
		o.append(tri[0])
		draw_polyline(o, Color(1, 1, 1, 0.9), 1.2, true)


func _army_marker(c: Vector2, a: Dictionary, font: Font) -> void:
	var f := int(a["f"])
	var col := CData.faction_color(f)
	var m := mk()
	var rect := Rect2(c - Vector2(ARMY_W, ARMY_H) * 0.5 * m, Vector2(ARMY_W, ARMY_H) * m)
	var sel := int(a["id"]) == selected_army
	if sel:
		var g := 3.0 + 1.5 * sin(pulse * 5.0)
		draw_rect(rect.grow(g), Color(1, 0.95, 0.4, 0.95))
	# Banner: a shield shape (rect with a pointed foot).
	var pts := PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0),
		rect.position + Vector2(rect.size.x, rect.size.y - 6 * m), c + Vector2(0, rect.size.y * 0.5 + 3 * m),
		rect.position + Vector2(0, rect.size.y - 6 * m)])
	draw_colored_polygon(pts, col.darkened(0.15))
	var outline := pts.duplicate()
	outline.append(pts[0])
	var human := CState.is_human(state, f)
	draw_polyline(outline, Color(1, 1, 1) if human else Color(0.05, 0.05, 0.05), 2.0 if human else 1.5, true)
	var n := str(CState.unit_count(a))
	var afs := int(round(15 * maxf(m, 0.75)))
	var tw := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x
	draw_string(font, c + Vector2(-tw * 0.5, afs * 0.3), n, HORIZONTAL_ALIGNMENT_LEFT, -1, afs, Color.WHITE)
	# Strength bar: men / full strength.
	var men := 0
	var full := 0
	for u in a["units"]:
		men += int(u["n"])
		full += preload("res://sim/unit_types.gd").size_of(CState.unit_type(u))
	var frac := clampf(float(men) / maxf(full, 1), 0.0, 1.0)
	var by := rect.end.y + 5.0 * m
	draw_rect(Rect2(rect.position.x, by, rect.size.x, 4 * m), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(rect.position.x, by, rect.size.x * frac, 4 * m), Color(0.5, 1.0, 0.5) if frac > 0.6 else Color(1.0, 0.8, 0.3))
	if int(a["moved"]) != 0 and human:
		draw_circle(rect.position + Vector2(rect.size.x, 0), 3.5, Color(0.6, 0.6, 0.6))


func _arrow(from: Vector2, to: Vector2, col: Color) -> void:
	var d := to - from
	var ln := d.length()
	if ln < 4.0:
		return
	var u := d / ln
	var tip := to - u * 14.0
	var start := from + u * 14.0
	var nrm := Vector2(-u.y, u.x)
	draw_line(start, tip, Color(0, 0, 0, 0.6), 7.0, true)
	draw_line(start, tip, col, 4.0, true)
	var head := PackedVector2Array([tip + u * 12.0, tip + nrm * 8.0, tip - nrm * 8.0])
	draw_colored_polygon(head, col)
	var ho := head.duplicate()
	ho.append(head[0])
	draw_polyline(ho, Color(0, 0, 0, 0.6), 1.5, true)
