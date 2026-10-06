extends Node2D
## Campaign map, screen layer: settlements (size by level, a wall ring with
## towers per wall level,
## gold dot for the key cities), names, pending battles, sieges (a ring of
## tents round the settlement in the besieger's colour), army markers
## (faction colour, unit count, strength bar; a small tower: inside the
## walls), planned moves as arrows (red an assault, orange a siege; state
## version 5: the path, solid this turn, dotted after), and hit tests for
## taps. Positions come from map_geo.gd through `xform` (map
## pixels -> screen), set by the campaign screen every frame.
##
## State version 6 (the continuous overworld, CState.grid_on): settlements
## stand on their grid cell and armies on theirs (several on one cell side
## by side; armies inside the walls under their settlement), pending battles
## on their cell; planned paths run along cell centres (solid this turn,
## dashed beyond, a ring where this turn ends, the intent at the end:
## swords an attack or assault, a tent a siege, a tower going inside);
## for the selected army the enemies' zones of control (red circles) and
## its support (yellow) and attack (red) lines; during a turn replay armies
## slide along their step log (replay_pos) and battles pop up (markers).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CRules := preload("res://campaign/crules.gd")

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
## State version 5: planned and stored marches [{army, pts [map points from
## the army's region], now (segments walked this turn)}]: solid this turn,
## dotted after.
var paths: Array = []
var pulse := 0.0
## Version 6: planned paths [{army, pts [map points: the army's cell then
## each step], now (index of the last point reached this turn), kind
## (CRules.move_aim kind)}], also the drag preview (army -1 never: drag
## holds the dragged army's preview, {} none); enemy zones [[map centre,
## radius in map px]]; links [[army id, other id, 0 support | 1 attack]];
## replay_pos {army id: map point} during a replay; markers [[map point,
## seconds left]] (battles popping up).
var grid := false
var paths6: Array = []
var drag: Dictionary = {}
var zones: Array = []
var links: Array = []
var replay_pos := {}
var replay_trail := {}  # army id -> map points passed so far in the replay
var markers: Array = []
## The selected army's merge and gift candidates [[army id, 0 merge | 1 gift
## | 2 too many units]] (a small glyph on their banners) and the one tapped
## once (merge_tap: its glyph rings).
var merge_marks: Array = []
var merge_tap := -1
var _tips: Array = []  # intents to draw over the banners: [point, kind, colour, caption]


## Map point (map pixels) of the centre of grid cell c.
static func cell_point(c: int) -> Vector2:
	var px := float(CGrid.cell_px())
	return Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px)


## The grid cell under map point p (-1 off the grid).
static func cell_of_point(p: Vector2) -> int:
	var px := float(CGrid.cell_px())
	return CGrid.at(int(floor(p.x / px)), int(floor(p.y / px)))


## Where settlement r is drawn (map pixels): its grid cell in version 6.
func site_point(r: int) -> Vector2:
	return cell_point(CGrid.site(r)) if grid else Geo.site(r)


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
	if grid:
		return _army_positions6()
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
		if to_screen(site_point(r)).distance_to(p) <= 16.0:
			return r
	return -1


## Version 6: armies at their cells; armies sharing a cell side by side;
## armies inside the walls under their settlement (as version 5 draws a
## region's armies); during a replay at replay_pos.
func _army_positions6() -> Dictionary:
	var out := {}
	var groups := {}
	var order: Array = []
	var m := mk()
	for a in state["armies"]:
		var id := int(a["id"])
		var key := ""
		var c := Vector2.ZERO
		if replay_pos.has(id):
			c = to_screen(replay_pos[id])
			key = "p%d_%d" % [int(c.x / 6.0), int(c.y / 6.0)]
		elif CRules.inside(state, a):
			var r := CGrid.site_region(CState.cell(a))
			c = to_screen(site_point(r)) + Vector2(0, (ARMY_H * 0.5 + 12.0) * m)
			key = "s%d" % r
		else:
			c = to_screen(cell_point(CState.cell(a)))
			key = "c%d" % CState.cell(a)
		if not groups.has(key):
			groups[key] = [c, []]
			order.append(key)
		(groups[key][1] as Array).append(id)
	var step := (ARMY_W + ARMY_GAP) * m * (0.8 if m < 0.8 else 1.0)
	for key in order:
		var g: Array = groups[key]
		var ids: Array = g[1]
		var n := ids.size()
		for k in n:
			out[int(ids[k])] = (g[0] as Vector2) + Vector2((k - (n - 1) * 0.5) * step, 0)
	return out


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
	for pth in paths:
		_path(pth, pos)
	_tips = []
	if grid:
		_draw_trails()
		_draw_zones()
		_draw_links(pos)
		for pth in paths6:
			_path6(pth, pos)
		if not drag.is_empty():
			_path6(drag, pos)
	# Settlements and names.
	var show_names := zoom >= 0.5
	for r in CData.region_count():
		var p := to_screen(site_point(r))
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
			var sr := rad + (6.0 + 1.2 * w) * mk()
			if grid:
				sr = maxf(sr, CGrid.cell_px() * 1.1 * zoom)  # round the ring the besiegers stand on
			_siege_ring(p, sr, int(sg["f"]))
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
		if grid and b.has("x"):
			p = to_screen(cell_point(CGrid.at(int(b["x"]), int(b["y"])))) + Vector2(0, -16)
		_battle_mark(p, 1.0)
	for mkr in markers:
		_battle_mark(to_screen(mkr[0]) + Vector2(0, -16), clampf(float(mkr[1]), 0.0, 1.0))
	# Armies.
	for a in state["armies"]:
		var id := int(a["id"])
		if not pos.has(id):
			continue
		_army_marker(pos[id], a, font)
	for mm in merge_marks:
		if pos.has(int(mm[0])):
			_merge_glyph(pos[int(mm[0])], int(mm[1]), int(mm[0]) == merge_tap)
	for tp in _tips:
		_intent(tp[0], str(tp[1]), tp[2])
		if (tp as Array).size() > 3 and str(tp[3]) != "":
			_caption(tp[0], str(tp[3]), tp[2])


## A battle: a red disc with crossed swords (alpha fades a popped marker).
func _battle_mark(p: Vector2, alpha: float) -> void:
	draw_circle(p, 11.0, Color(0.75, 0.1, 0.08, 0.95 * alpha))
	draw_arc(p, 11.0, 0, TAU, 20, Color(1, 1, 1, alpha), 1.5, true)
	draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), Color(1, 1, 1, alpha), 2.2, true)
	draw_line(p + Vector2(5, -5), p + Vector2(-5, 5), Color(1, 1, 1, alpha), 2.2, true)


## Version 6 replay: a faint line behind each army on its way.
func _draw_trails() -> void:
	for a in state["armies"]:
		var id := int(a["id"])
		if not replay_trail.has(id) or not replay_pos.has(id):
			continue
		var pts := PackedVector2Array()
		for q in replay_trail[id]:
			pts.append(to_screen(q))
		pts.append(to_screen(replay_pos[id]))
		if pts.size() >= 2:
			var col := CData.faction_color(int(a["f"])).lightened(0.3)
			col.a = 0.8
			draw_polyline(pts, Color(0, 0, 0, 0.5), 6.0, true)
			draw_polyline(pts, col, 3.5, true)


## Version 6: the enemies' zones of control (red circles).
func _draw_zones() -> void:
	for z in zones:
		var c := to_screen(z[0])
		var rad: float = float(z[1]) * zoom
		draw_circle(c, rad, Color(0.85, 0.15, 0.1, 0.12))
		draw_arc(c, rad, 0, TAU, 40, Color(0.0, 0.0, 0.0, 0.45), 3.0, true)
		draw_arc(c, rad, 0, TAU, 40, Color(1.0, 0.35, 0.25, 0.85), 1.6, true)


## Version 6: support (yellow) and attack (red) lines of the selected army.
func _draw_links(pos: Dictionary) -> void:
	for ln in links:
		if not pos.has(int(ln[0])) or not pos.has(int(ln[1])):
			continue
		var a: Vector2 = pos[int(ln[0])]
		var b: Vector2 = pos[int(ln[1])]
		var col := Color(1.0, 0.85, 0.2, 0.9) if int(ln[2]) == 0 else Color(1.0, 0.25, 0.2, 0.9)
		draw_line(a, b, Color(0, 0, 0, 0.5), 5.0, true)
		draw_dashed_line(a, b, col, 3.0, 10.0, true)


## Version 6: a planned path along cell centres: solid this turn, dashed
## beyond, a ring where this turn ends, the intent at the end.
func _path6(pth: Dictionary, pos: Dictionary) -> void:
	var pts: Array = pth["pts"]
	if pts.size() < 2:
		return
	var id := int(pth["army"])
	var kind := str(pth.get("kind", "move"))
	var col := Color(0.95, 0.95, 0.9)
	if kind in ["attack", "assault", "relief", "sally"]:
		col = Color(1.0, 0.45, 0.35)
	elif kind in ["siege", "join"]:
		col = Color(1.0, 0.7, 0.25)
	elif kind == "merge":
		col = Color(0.55, 0.95, 0.6) if not str(pth.get("caption", "")).begins_with("Too many") else Color(0.7, 0.7, 0.68)
	var m := mk()
	var sp: Array = []
	for k in pts.size():
		sp.append(to_screen(pts[k]))
	if pos.has(id) and not pth.has("drag"):
		sp[0] = pos[id]
	var now := int(pth["now"])
	for k in pts.size() - 1:
		var a: Vector2 = sp[k]
		var b: Vector2 = sp[k + 1]
		if a.distance_to(b) < 1.0:
			continue
		if k < now:
			draw_line(a, b, Color(0, 0, 0, 0.6), 7.0 * m, true)
			draw_line(a, b, col, 4.0 * m, true)
		else:
			draw_dashed_line(a, b, Color(0, 0, 0, 0.5), 6.0 * m, 8.0, true)
			draw_dashed_line(a, b, col.darkened(0.05), 3.0 * m, 8.0, true)
	if now > 0 and now < pts.size() - 1:
		# Where this turn's march ends.
		var e: Vector2 = sp[now]
		draw_circle(e, 7.0 * m, Color(0, 0, 0, 0.55))
		draw_arc(e, 7.0 * m, 0, TAU, 20, col, 3.0 * m, true)
	_tips.append([sp[-1], kind, col, str(pth.get("caption", ""))])


## The intent at a path's end: a small badge.
func _intent(p: Vector2, kind: String, col: Color) -> void:
	var m := mk()
	var r := 9.0 * m
	draw_circle(p, r + 1.5, Color(0, 0, 0, 0.75))
	draw_circle(p, r, col.darkened(0.35))
	var w := Color(1, 1, 1, 0.95)
	match kind:
		"attack", "assault", "relief", "sally":
			draw_line(p + Vector2(-5, -5) * m, p + Vector2(5, 5) * m, w, 2.2, true)
			draw_line(p + Vector2(5, -5) * m, p + Vector2(-5, 5) * m, w, 2.2, true)
		"siege", "join":
			var ts := 5.5 * m
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -ts), p + Vector2(ts, ts * 0.8), p + Vector2(-ts, ts * 0.8)]), w)
		"merge":
			draw_line(p + Vector2(-5, 0) * m, p + Vector2(5, 0) * m, w, 2.4, true)
			draw_line(p + Vector2(0, -5) * m, p + Vector2(0, 5) * m, w, 2.4, true)
		"inside":
			draw_rect(Rect2(p - Vector2(4, 3) * m, Vector2(8, 8) * m), w)
			for k in 3:
				draw_rect(Rect2(p + Vector2(-4 + 3.0 * k, -6) * m, Vector2(2, 3) * m), w)
		_:
			draw_circle(p, 3.0 * m, w)


## A path's caption ("Merge into army (5 units)") above its end.
func _caption(p: Vector2, text: String, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var fs := 14
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := p + Vector2(-tw * 0.5, -ARMY_H * mk() - 6.0)
	draw_rect(Rect2(tp + Vector2(-5, -fs), Vector2(tw + 10, fs + 7)), Color(0, 0, 0, 0.7))
	draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.3))


## On a banner the selected army can merge into (a green plus), give units
## to (an allied player's army: a gold gift box) or not merge with (too
## many units: a grey plus); the one tapped once gets a ring.
func _merge_glyph(c: Vector2, kind: int, tapped: bool) -> void:
	var m := mk()
	var p := c + Vector2(-ARMY_W * 0.5, ARMY_H * 0.5) * m
	var r := 7.0 * m
	var col: Color = [Color(0.3, 0.75, 0.35), Color(0.9, 0.7, 0.2), Color(0.5, 0.5, 0.48)][clampi(kind, 0, 2)]
	if tapped:
		draw_arc(p, r + 4.0 + 1.5 * sin(pulse * 6.0), 0, TAU, 20, Color(1, 1, 1, 0.9), 2.0, true)
	draw_circle(p, r + 1.2, Color(0, 0, 0, 0.85))
	draw_circle(p, r, col)
	var w := Color(1, 1, 1)
	if kind == 1:
		draw_rect(Rect2(p - Vector2(4, 3) * m, Vector2(8, 7) * m), w, false, 1.5)
		draw_line(p + Vector2(0, -4) * m, p + Vector2(0, 4) * m, w, 1.5)
		draw_line(p + Vector2(-4, 0) * m, p + Vector2(4, 0) * m, w, 1.5)
	else:
		draw_line(p + Vector2(-4, 0) * m, p + Vector2(4, 0) * m, w, 2.0, true)
		draw_line(p + Vector2(0, -4) * m, p + Vector2(0, 4) * m, w, 2.0, true)


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
	if grid:
		_stance_badge(rect, a)
	if (not grid and int(a.get("stance", 0)) == CData.STANCE_GARRISON) or (grid and CRules.inside(state, a)):
		# Inside the walls: a small crenellated tower on the banner's corner.
		var tw2 := 8.0 * m
		var tp := rect.position + Vector2(-tw2 * 0.6, -tw2 * 0.4)
		var stone := Color(0.85, 0.8, 0.7)
		draw_rect(Rect2(tp - Vector2(1, 1), Vector2(tw2, tw2 * 1.1) + Vector2(2, 2)), Color(0.05, 0.05, 0.05))
		draw_rect(Rect2(tp, Vector2(tw2, tw2 * 1.1)), stone)
		for k in 3:
			draw_rect(Rect2(tp + Vector2(tw2 * 0.38 * k, -tw2 * 0.25), Vector2(tw2 * 0.24, tw2 * 0.25)), stone)


## Version 6: a letter on the banner's top right for a stance other than
## the default (F forced march, D fortified, R raiding).
func _stance_badge(rect: Rect2, a: Dictionary) -> void:
	var st_v := CState.stance(a)
	if st_v == CData.ST_DEFAULT:
		return
	var txt: String = {CData.ST_FORCED: "F", CData.ST_FORTIFY: "D", CData.ST_RAID: "R"}.get(st_v, "")
	var col: Color = {CData.ST_FORCED: Color(0.3, 0.6, 1.0), CData.ST_FORTIFY: Color(0.55, 0.55, 0.5), CData.ST_RAID: Color(0.95, 0.55, 0.15)}.get(st_v, Color.WHITE)
	var c := rect.position + Vector2(rect.size.x, 0)
	draw_circle(c, 7.0, Color(0, 0, 0, 0.85))
	draw_circle(c, 6.0, col)
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(str(txt), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, c + Vector2(-tw * 0.5, 4), str(txt), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## A march: from the army's banner along the region sites; this turn's
## hops solid, later ones dotted, an arrowhead at the destination.
func _path(pth: Dictionary, pos: Dictionary) -> void:
	var id := int(pth["army"])
	var pts: Array = pth["pts"]
	if pts.size() < 2:
		return
	var col := Color(0.95, 0.95, 0.9)
	if siege_moves.has(id):
		col = Color(1.0, 0.7, 0.25)
	elif attack_moves.has(id):
		col = Color(1.0, 0.45, 0.35)
	var sp: Array = []
	for k in pts.size():
		sp.append(to_screen(pts[k]) + Vector2(0, 8))
	if pos.has(id):
		sp[0] = pos[id]
	var now := int(pth["now"])
	var m := mk()
	for k in pts.size() - 1:
		var a: Vector2 = sp[k]
		var b: Vector2 = sp[k + 1]
		var last := k == pts.size() - 2
		var d := b - a
		var ln := d.length()
		if ln < 4.0:
			continue
		var u := d / ln
		var s0 := a + u * (14.0 if k == 0 else 6.0)
		var e0 := b - u * (14.0 if last else 6.0)
		if k < now:
			draw_line(s0, e0, Color(0, 0, 0, 0.6), 7.0 * m, true)
			draw_line(s0, e0, col, 4.0 * m, true)
		else:
			draw_dashed_line(s0, e0, Color(0, 0, 0, 0.55), 6.0 * m, 9.0, true)
			draw_dashed_line(s0, e0, col.darkened(0.05), 3.0 * m, 9.0, true)
		if not last:
			draw_circle(b, 3.5 * m, col if k < now else Color(col, 0.6))
		else:
			var tip := e0
			var nrm := Vector2(-u.y, u.x)
			var head := PackedVector2Array([tip + u * 10.0, tip + nrm * 7.0 - u * 2.0, tip - nrm * 7.0 - u * 2.0])
			draw_colored_polygon(head, col)


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
