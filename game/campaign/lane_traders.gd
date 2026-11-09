extends Node2D
## Small merchant sails on the sea lanes that carry trade this turn (view only; docs/design/overworld_view.md "Lane
## traders, the ambient ships retired"). Reads the campaign state as the lane rules define it (CLanes.lane_state):
## a lane whose ports both pay gets two sails, one each way along its curve; a lane paying one end only gets one,
## sailing towards that end (one owner and an unowned port: an independent's town, never paid); a raided lane gets
## one; a blockaded or besieged end, a lane between ports at war, a lane between ports of two owners with no trade
## agreement or alliance (2026-11-09, lanes trade by agreement: mere peace pays nothing in a format 10 campaign;
## CLanes.trades), an exit lane (the flota's: its token stays) get none. One owner at both ends, or one team, trades
## as always. sails() is the count, read from lane_state alone. The sails move by the frames' time from a per-lane phase, on a
## constant speed in map px, looping with a fade at each port. One node between the sea part and the fleets, drawn
## in screen space from the overlay's current transform every frame (so nothing lags or pops while panning) and as
## ONE triangle array (no node, no draw call per ship). Dead simple to delete: remove this file, its three lines in
## map_overlay.gd (`_ready`) and nothing else refers to it.

const CData := preload("res://campaign/cdata.gd")
const CLanes := preload("res://campaign/clanes.gd")
const MapView := preload("res://game/campaign/map_view.gd")

const SPEED := 10.0        # map px a second
const FADE_ZOOM_A := 0.28  # below this zoom no sail is drawn, fully drawn from FADE_ZOOM_B
const FADE_ZOOM_B := 0.42
const ENDS_FADE := 0.06    # share of the lane's length faded in / out at a port
const HULL := Color(0.09, 0.13, 0.2, 0.9)
const SAIL := Color(0.97, 0.95, 0.88, 0.96)
const JIB := Color(0.88, 0.9, 0.9, 0.94)

var overlay = null            # the MapOverlay (state, xform, zoom, mk())
var _epoch := -1              # the overlay's state redraw the lanes below are of
var _lanes: Array = []        # [[poly, cum, length, [[dir, phase], ...]], ...]
var _metrics := {}            # lane id -> [poly, cum]
var _t := 0.0
var count := 0                # sails drawn in the last frame (tests)


func _process(delta: float) -> void:
	_t += delta
	if overlay == null or overlay.state.is_empty() or not is_visible_in_tree():
		return
	if overlay._epoch != _epoch:
		_epoch = overlay._epoch
		_rebuild()
	if not _lanes.is_empty() and float(overlay.zoom) >= FADE_ZOOM_A:
		queue_redraw()
	elif count > 0:
		count = 0
		queue_redraw()


## Which lanes carry trade now, and which way: [lane id, direction] pairs by the lane rules (state only).
func _rebuild() -> void:
	_lanes.clear()
	var st: Dictionary = overlay.state
	if CData.SEA_LANES.is_empty() or not st.has("regions"):
		return
	var rt := CLanes.raiders(st)
	for id in CLanes.count():
		if CLanes.is_exit(id):
			continue
		var poly := MapView.lane_poly(id)
		if poly.size() < 2:
			continue
		var ls := CLanes.lane_state(st, id, rt)
		var pa := int(ls["pa"])
		var pb := int(ls["pb"])
		var n := sails(ls)
		if n == 0:
			continue   # a blockaded or besieged end, no trade (at war, or no agreement), or a lane worth nothing
		var met := _metric(id, poly)
		var cum: PackedFloat32Array = met[1]
		var e: Array = CLanes.ends(id)
		# which way the curve runs: poly[0] at end a's port or at end b's
		var pt_a: Vector2 = overlay.site_point(int(e[0]))
		var pt_b: Vector2 = overlay.site_point(int(e[1]))
		var fwd := poly[0].distance_squared_to(pt_a) + poly[poly.size() - 1].distance_squared_to(pt_b) \
				<= poly[0].distance_squared_to(pt_b) + poly[poly.size() - 1].distance_squared_to(pt_a)
		var a_to_b := 1 if fwd else -1   # +1: towards the curve's end, -1: towards its start
		var ships: Array = []
		var ph := float((id * 37 + 11) % 100) / 100.0   # per-lane phase, so the lanes do not move as one
		if n == 2:
			ships.append([a_to_b, ph])
			ships.append([-a_to_b, fmod(ph + 0.37, 1.0)])
		elif pa > 0 and pb > 0:
			ships.append([a_to_b if (id & 1) == 0 else -a_to_b, ph])   # a raided lane: one sail
		else:
			ships.append([-a_to_b if pa > 0 else a_to_b, ph])   # goods flow to the end that is paid
		_lanes.append([poly, cum, float(cum[cum.size() - 1]), ships])


## The sails a port lane carries, from its CLanes.lane_state `ls` alone: 0 (a blockaded or besieged end, or nothing paid:
## at war, no trade agreement, a lane worth nothing), 2 (both ends paid, not raided), else 1.
static func sails(ls: Dictionary) -> int:
	var pa := int(ls["pa"])
	var pb := int(ls["pb"])
	if int(ls["la"]) > 0 or int(ls["lb"]) > 0 or pa + pb <= 0:
		return 0
	if pa > 0 and pb > 0 and int(ls["cuta"]) + int(ls["cutb"]) == 0:
		return 2
	return 1


func _metric(id: int, poly: PackedVector2Array) -> Array:
	if _metrics.has(id):
		var m: Array = _metrics[id]
		var p0: PackedVector2Array = m[0]
		if p0.size() == poly.size() and p0[0] == poly[0] and p0[p0.size() - 1] == poly[poly.size() - 1]:
			return m
	var cum := PackedFloat32Array()
	cum.resize(poly.size())
	var acc := 0.0
	for i in poly.size():
		if i > 0:
			acc += poly[i].distance_to(poly[i - 1])
		cum[i] = acc
	var out := [poly, cum]
	_metrics[id] = out
	return out


func _draw() -> void:
	count = 0
	if overlay == null or _lanes.is_empty():
		return
	var z := float(overlay.zoom)
	var za := clampf((z - FADE_ZOOM_A) / (FADE_ZOOM_B - FADE_ZOOM_A), 0.0, 1.0)
	if za <= 0.0:
		return
	var u := float(overlay.mk())
	var xf: Transform2D = overlay.xform
	var vp := get_viewport_rect().grow(20.0)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for ln in _lanes:
		var poly: PackedVector2Array = ln[0]
		var cum: PackedFloat32Array = ln[1]
		var lane_len := float(ln[2])
		if lane_len < 1.0:
			continue
		for sh in ln[3]:
			var dir := int(sh[0])
			var f := fposmod(float(sh[1]) + _t * SPEED / lane_len, 1.0)
			var s := (f if dir > 0 else 1.0 - f) * lane_len
			# the segment holding s (binary search on the cumulative lengths)
			var lo := 0
			var hi := cum.size() - 1
			while hi - lo > 1:
				var mid := (lo + hi) >> 1
				if cum[mid] <= s:
					lo = mid
				else:
					hi = mid
			var seg := cum[hi] - cum[lo]
			var w := (s - cum[lo]) / seg if seg > 0.0 else 0.0
			var mp := poly[lo].lerp(poly[hi], w)
			var tng: Vector2 = (poly[hi] - poly[lo]) * float(dir)
			var p := xf * mp
			if not vp.has_point(p):
				continue
			var a := za * minf(minf(f / ENDS_FADE, (1.0 - f) / ENDS_FADE), 1.0)
			if a <= 0.02:
				continue
			p.y += sin(_t * 1.7 + float(sh[1]) * 9.0) * 0.45 * u   # a little bob
			var sx := -u if (xf.basis_xform(tng).x < 0.0) else u   # the hull points the way it sails
			_sail(pts, cols, idx, p, sx, u, a)
			count += 1
	if idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)


## One merchant at p (hull length along x, flipped by the sign of sx; sail height ~u * 7): a dark hull, a main sail
## and a jib, appended as triangles.
static func _sail(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, p: Vector2, sx: float, u: float, a: float) -> void:
	var k := pts.size()
	# (hull quad, main sail, jib) in local units: x along the hull, y up is negative
	var loc := [Vector2(-3.4, 0.0), Vector2(3.8, 0.0), Vector2(2.6, 2.0), Vector2(-2.4, 2.0),
			Vector2(0.3, -0.6), Vector2(0.3, -7.0), Vector2(3.1, -0.9),
			Vector2(-0.3, -0.6), Vector2(-0.3, -5.4), Vector2(-3.0, -0.9)]
	var col := [HULL, HULL, HULL, HULL, SAIL, SAIL, SAIL, JIB, JIB, JIB]
	for i in loc.size():
		var l: Vector2 = loc[i]
		pts.append(p + Vector2(l.x * sx, l.y * u))
		var c: Color = col[i]
		c.a *= a
		cols.append(c)
	idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3, k + 4, k + 5, k + 6, k + 7, k + 8, k + 9])
