extends Node2D
## World-space overlay: unit markers, the selected units' formations and
## orders, missile ranges and targets, and the live preview while the player
## draws a destination line (for one unit or a group).

const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")
## Marker radius in screen pixels (never below MARKER_MIN_R world pixels).
const MARKER_SCREEN_R := 11.0
const MARKER_MIN_R := 5.5
const M := 1024.0
const GROUP_GAP_M := 2.0   # metres left between units lined up by a drag

var sim
var px_per_m: float = 10.0
var selected_units: Array[int] = []   # first = primary
var zoom: float = 1.0
var show_all_orders := false   # draw every friendly unit's order footprint
var player_side := 0
var orders  # OrderPreview: predicted order state including not-yet-applied orders

# Drag preview (world pixels), active when preview_on.
var preview_on := false
var preview_a := Vector2.ZERO
var preview_b := Vector2.ZERO
var preview_ok := false  # long enough to be a formation line
var _icon := PackedInt32Array()  # unit -> symbol id

const COL_SIDE := [Color(0.35, 0.6, 1.0), Color(1.0, 0.36, 0.28)]
const COL_FIRE := Color(1.0, 0.75, 0.25, 0.8)
const COL_ARC := Color(1.0, 0.85, 0.4, 0.5)
const FX_TICKS := 15.0   # stone impact marks last this many ticks
const COL_WITHDRAW := Color(0.85, 0.85, 1.0, 0.8)
const COL_BLOCKED := Color(1.0, 0.25, 0.2, 0.9)
const COL_UPHILL := Color(1.0, 0.62, 0.35)
const COL_DOWNHILL := Color(0.6, 1.0, 0.6)
const HINT_GRADE := 164   # slopes under 4% get no uphill / downhill hint
const RANGE_STEPS := 72   # height-adjusted range ring: points round the circle
const COL_WOODS := Color(0.85, 1.0, 0.35)
const COL_BLOCK_CELL := Color(1.0, 0.35, 0.3, 0.7)
const FLASH_MS := 2500


## Unit order field as the player last ordered it (pending orders included).
## Group move (three fingers / Alt+drag): destination footprints, each
## {unit, front (world px), face, files}; and a short label.
var ghosts: Array = []
var ghost_hint := ""
## Box select (mouse drag on empty ground): corners in world px.
var box_on := false
var box_a := Vector2.ZERO
var box_b := Vector2.ZERO
## A short message at a world point (gate taps): text, where, until (ms).
var _flash_text := ""
var _flash_at := Vector2.ZERO
var _flash_until := 0


## Show `text` at world point `at` for a couple of seconds.
func flash(text: String, at: Vector2) -> void:
	_flash_text = text
	_flash_at = at
	_flash_until = Time.get_ticks_msec() + FLASH_MS


func _v(u: int, key: String) -> int:
	if orders != null:
		return orders.value(u, key)
	return (sim.get("u_" + key) as PackedInt32Array)[u]


func to_px(x: int, y: int) -> Vector2:
	return Vector2(x, y) * (px_per_m / M)


func _font_size(base: float) -> int:
	return int(maxf(10.0, base / zoom))


func _draw() -> void:
	if sim == null:
		return
	var lw := maxf(1.5, 2.0 / zoom)
	var r := maxf(MARKER_MIN_R, MARKER_SCREEN_R / zoom)
	if _icon.size() != sim.n_units:
		_icon.resize(sim.n_units)
		for u in sim.n_units:
			_icon[u] = Icons.icon_of(sim.u_type[u])
	if sim.city_on != 0:
		_draw_city_marks(lw)
	if show_all_orders:
		_draw_all_orders()
	if sim.n_eng > 0:
		_draw_impacts(lw)
	_draw_markers(r, lw)
	var primary := selected_units[0] if not selected_units.is_empty() else -1
	for u in selected_units:
		if u >= 0 and u < sim.n_units and sim.u_state[u] < BattleSim.U_DESTROYED:
			_draw_selected(u, lw, r, u == primary)
	if preview_on:
		_draw_preview(lw)
	for g in ghosts:
		var u: int = g["unit"]
		_draw_footprint(u, g["front"], g["face"], g["files"], sim.u_alive[u],
			Color(0.6, 1.0, 1.0, 0.95), Color(0.6, 1.0, 1.0, 0.16), lw)
	if ghost_hint != "" and not ghosts.is_empty():
		var at: Vector2 = ghosts[0]["front"]
		var fs := _font_size(15.0)
		draw_string(ThemeDB.fallback_font, at + Vector2(0, -fs * 1.2), ghost_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 1, 1))
	if box_on:
		var rect := Rect2(box_a, box_b - box_a).abs()
		draw_rect(rect, Color(1, 1, 1, 0.12))
		draw_rect(rect, Color(1, 1, 1, 0.8), false, lw)
	if _flash_text != "" and Time.get_ticks_msec() < _flash_until:
		var ffs := _font_size(14.0)
		var tw := ThemeDB.fallback_font.get_string_size(_flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ffs).x
		var at := _flash_at + Vector2(-tw * 0.5, -ffs * 1.6)
		draw_rect(Rect2(at + Vector2(-ffs * 0.4, -ffs * 1.05), Vector2(tw + ffs * 0.8, ffs * 1.45)), Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, at, _flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ffs, Color(1, 0.95, 0.8))


## Settlement: hit points over each closed gate (a word over an open or a
## broken one), and the capture ring with "Plaza held N / 60 s" while the
## attackers hold the plaza.
func _draw_city_marks(lw: float) -> void:
	var lay: Dictionary = sim.map_info.get("city", {})
	if lay.is_empty():
		return
	var k := px_per_m
	for g in sim.n_gates:
		var gd: Dictionary = lay["gates"][g]
		var ang: float = int(gd["dir"]) * TAU / 1024.0
		var n := Vector2(cos(ang), sin(ang))
		var c := Vector2(gd["x"], gd["y"]) * k + n * (float(lay["t"]) * 0.5 + 3.0) * k
		var st: int = sim.g_state[g]
		var bw := maxf(10.0 * k, 46.0 / zoom)
		var bh := maxf(1.0 * k, 6.0 / zoom)
		if st == BattleSim.GATE_CLOSED:
			var f := float(sim.g_hp[g]) / maxf(float(sim.g_hp0[g]), 1.0)
			draw_rect(Rect2(c - Vector2(bw * 0.5, bh * 0.5), Vector2(bw, bh)), Color(0, 0, 0, 0.65))
			var col := Color(0.95, 0.75, 0.3) if f > 0.35 else Color(1.0, 0.35, 0.25)
			draw_rect(Rect2(c - Vector2(bw * 0.5, bh * 0.5), Vector2(bw * f, bh)), col)
		elif zoom > 0.35:
			var txt := "BROKEN" if st == BattleSim.GATE_BROKEN else "OPEN"
			draw_string(ThemeDB.fallback_font, c + Vector2(-bw * 0.3, bh), txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
				_font_size(12.0), Color(1, 0.85, 0.5) if st == BattleSim.GATE_BROKEN else Color(0.75, 1, 0.75))
	if sim.cap_t > 0:
		var pl: Array = lay["plaza"]
		var pc := Vector2(pl[0], pl[1]) * k
		var r := float(pl[3]) * k
		var frac := clampf(float(sim.cap_t) / BattleSim.CAPTURE_TICKS, 0.0, 1.0)
		var att: int = 1 - sim.city_def
		var col2: Color = COL_SIDE[att]
		draw_arc(pc, r, 0, TAU, 48, Color(0, 0, 0, 0.5), lw * 3.0)
		draw_arc(pc, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, col2, lw * 3.0)
		var fs := _font_size(15.0)
		var txt2 := "Plaza held %d / %d s" % [sim.cap_t / 10, BattleSim.CAPTURE_TICKS / 10]
		var tw2 := ThemeDB.fallback_font.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(ThemeDB.fallback_font, pc + Vector2(-tw2 * 0.5, -r - fs * 0.5), txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col2.lightened(0.3))


## Unit markers at the centroid: side colour, white ring when selected,
## yellow when routing, plus small state signs.
func _draw_markers(r: float, lw: float) -> void:
	var tick: int = sim.tick
	for u in sim.n_units:
		if sim.u_state[u] >= BattleSim.U_DESTROYED:
			continue
		var c := to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(0, -r * 2.2)
		var col: Color = COL_SIDE[sim.u_side[u]]
		if sim.u_state[u] == BattleSim.U_ROUTING:
			col = Color(1.0, 0.9, 0.3)
		# Unit type symbol on a disc in the side colour (yellow when broken,
		# with a dark glyph for contrast).
		var glyph := Color(0.12, 0.1, 0.05) if sim.u_state[u] == BattleSim.U_ROUTING else Color.WHITE
		Icons.draw_marker(self, _icon[u], c, r, col, glyph)
		if selected_units.has(u):
			draw_arc(c, r * 1.6, 0, TAU, 20, Color.WHITE, lw)
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		# Under missile fire: orange ring for a second after each wound.
		if tick - sim.u_hit_t[u] < 10:
			draw_arc(c, r * 1.25, 0, TAU, 16, Color(1.0, 0.6, 0.1, 0.9), lw)
		# Hit by a charge: red flash.
		if tick - sim.u_charged_t[u] < 15:
			draw_arc(c, r * 1.45, 0, TAU, 16, Color(1, 0.15, 0.1, 0.95), lw * 1.3)
		# Charging cavalry: chevron ahead of the marker.
		if sim.u_mom[u] >= BattleSim.CHARGE_MIN:
			var ang: float = sim.u_face[u] * TAU / 1024.0
			var f := Vector2(cos(ang), sin(ang))
			var s := Vector2(-f.y, f.x)
			var tip := c + f * r * 2.2
			draw_polyline(PackedVector2Array([tip - f * r * 0.8 + s * r * 0.7, tip,
				tip - f * r * 0.8 - s * r * 0.7]), Color.WHITE, lw * 1.2)
		# Artillery: a ring under the marker filling up while the battery
		# sets up (full = ready to shoot); empty while packed.
		if sim.u_neng[u] > 0:
			var full: int = UT.stat(sim.u_type[u], "deploy")
			var frac: float = float(sim.u_depl[u]) / maxf(full, 1.0)
			var rcol := Color(1, 0.9, 0.5, 0.95)
			if sim.u_rprog[u] > 0 or sim.u_refill[u] != 0:
				# Refilling: the ring shows how full the engines are (blue),
				# dashed while the battery gets into or out of it.
				var full_ammo: int = sim.u_neng[u] * UT.stat(sim.u_type[u], "m_ammo")
				frac = float(maxi(sim.u_ammo[u], 0)) / maxf(full_ammo, 1.0)
				rcol = Color(0.45, 0.8, 1.0, 0.95 if sim.u_rprog[u] >= BattleSim.REFILL_FULL else 0.5)
			var rc := c + Vector2(0, r * 1.9)
			draw_arc(rc, r * 0.45, 0, TAU, 12, Color(0, 0, 0, 0.6), lw)
			if frac > 0.0:
				draw_arc(rc, r * 0.45, -PI * 0.5, -PI * 0.5 + TAU * frac, 12, rcol, lw)
		# Braced spears / formed pikes: bar under the marker.
		if sim.u_braced[u] != 0:
			draw_line(c + Vector2(-r, r * 1.35), c + Vector2(r, r * 1.35), Color(1, 1, 1, 0.9), lw * 1.2)
		if sim.u_order[u] == BattleSim.O_WITHDRAW:
			var down := 1.0 if sim.u_side[u] == 0 else -1.0
			var b := c + Vector2(0, down * r * 2.0)
			draw_line(c + Vector2(0, down * r), b, COL_WITHDRAW, lw)
			draw_line(b, b + Vector2(-r * 0.5, -down * r * 0.5), COL_WITHDRAW, lw)
			draw_line(b, b + Vector2(r * 0.5, -down * r * 0.5), COL_WITHDRAW, lw)


func _draw_selected(u: int, lw: float, r: float, primary: bool) -> void:
	var ty: int = sim.u_type[u]
	var files := mini(_v(u, "files"), sim.u_alive[u])
	var half := (files - 1) * UT.stat(ty, "file_sp") / 2
	var a := to_px(_v(u, "ax"), _v(u, "ay"))
	var ang: float = _v(u, "face") * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var hw := half * px_per_m / M
	draw_line(a - right * hw, a + right * hw, Color(1, 1, 1, 0.8), lw)
	draw_line(a, a + fwd * px_per_m * 3.0, Color(1, 1, 1, 0.8), lw)
	var order: int = _v(u, "order")
	if order == BattleSim.O_MOVE:
		var d := to_px(_v(u, "dx"), _v(u, "dy"))
		var dang: float = _v(u, "dface") * TAU / 1024.0
		var dfwd := Vector2(cos(dang), sin(dang))
		var dright := Vector2(-dfwd.y, dfwd.x)
		_dash_outlined(a, d, Color(0.6, 1.0, 0.6, 0.85), lw, 8.0 / zoom)
		_draw_woods_along(_v(u, "ax"), _v(u, "ay"), _v(u, "dx"), _v(u, "dy"), lw)
		draw_line(d - dright * hw, d + dright * hw, Color(0, 0, 0, 0.4), lw * 3.0)
		draw_line(d - dright * hw, d + dright * hw, Color(0.6, 1.0, 0.6, 0.9), lw * 1.5)
		draw_line(d, d + dfwd * px_per_m * 3.0, Color(0.6, 1.0, 0.6, 0.9), lw)
		if primary:
			_draw_slope_hint(sim.u_h[u], sim.height_at(_v(u, "dx"), _v(u, "dy")),
				_v(u, "dx") - sim.u_cx[u], _v(u, "dy") - sim.u_cy[u], d + Vector2(r, r * 1.2),
				sim.u_cx[u], sim.u_cy[u])
			if _v(u, "gtarget") >= 0:
				draw_string(ThemeDB.fallback_font, d + Vector2(r, -r * 1.5), "BREAK THE GATE",
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), Color(1.0, 0.8, 0.45))
	elif order == BattleSim.O_ATTACK and _v(u, "target") >= 0:
		var t: int = _v(u, "target")
		var tcol := Color(1, 0.3, 0.2, 0.85)
		var shooter: bool = UT.stat(ty, "m_ammo") > 0 and sim.u_ammo[u] > 0
		if shooter:
			tcol = COL_FIRE
		var tp := to_px(sim.u_cx[t], sim.u_cy[t])
		if not (shooter and _draw_blocked(u, t, lw)):
			_dash_outlined(a, tp, tcol, lw, 8.0 / zoom)
		if primary and not shooter:
			_draw_slope_hint(sim.u_h[u], sim.u_h[t], sim.u_cx[t] - sim.u_cx[u],
				sim.u_cy[t] - sim.u_cy[u], (a + tp) * 0.5, sim.u_cx[u], sim.u_cy[u])
	elif order == BattleSim.O_ATTACK and _v(u, "gtarget") >= 0 and sim.n_gates > _v(u, "gtarget"):
		# A battery shooting at a gate.
		var gf: Vector2i = sim.gate_face(_v(u, "gtarget"))
		draw_dashed_line(a, to_px(gf.x, gf.y), COL_FIRE, lw, 8.0 / zoom)
		if primary:
			draw_string(ThemeDB.fallback_font, to_px(gf.x, gf.y) + Vector2(r, r), "SHOOT THE GATE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), COL_FIRE)
	elif order == BattleSim.O_WITHDRAW:
		_draw_withdraw(u, a, COL_WITHDRAW, lw)
	# Artillery: firing arc between minimum and maximum range (and the full
	# range faintly, since the battery can turn), and its current target.
	if UT.cls(ty) == UT.CLS_ART:
		_draw_art_range(u, lw)
		_draw_fire_line(u, lw)
	# Missile troops: range circle (stretched where the ground falls away,
	# shortened uphill) and what they are shooting at now.
	if UT.cls(ty) == UT.CLS_MISSILE:
		var rcol := Color(1.0, 0.85, 0.4, 0.45) if sim.u_ammo[u] > 0 else Color(0.6, 0.6, 0.6, 0.3)
		_draw_range(u, 0.0, TAU, rcol, lw)
		_draw_fire_line(u, lw)
	if primary and _v(u, "run") != 0:
		draw_string(ThemeDB.fallback_font, a + Vector2(r, -r * 3.5), "RUN",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(14.0), Color.WHITE)


## Firing arc of battery u: an annular sector from minimum to maximum range,
## +-arc about its facing (the facing it is turning to, if pending), plus the
## whole maximum-range circle faintly.
func _draw_art_range(u: int, lw: float) -> void:
	var ty: int = sim.u_type[u]
	var c := to_px(sim.u_cx[u], sim.u_cy[u])
	var k := px_per_m / M
	var rmin := UT.stat(ty, "m_min") * k
	var ok: bool = sim.u_ammo[u] > 0
	var col := COL_ARC if ok else Color(0.6, 0.6, 0.6, 0.3)
	_draw_range(u, 0.0, TAU, Color(col, col.a * 0.35), lw)
	if rmin > 0.0:
		draw_arc(c, rmin, 0, TAU, 48, Color(col, col.a * 0.35), lw)
	var face: float = _v(u, "dface") * TAU / 1024.0
	var half: float = UT.stat(ty, "arc") * TAU / 1024.0
	var a0 := face - half
	var a1 := face + half
	var ends := _draw_range(u, a0, a1, col, lw * 1.6)
	draw_arc(c, maxf(rmin, px_per_m), a0, a1, 12, col, lw * 1.6)
	for e in 2:
		var a: float = [a0, a1][e]
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * maxf(rmin, px_per_m), ends[e], col, lw)


## Stone impacts in the last FX_TICKS ticks: a dust ring that spreads and
## fades, and the furrow the stone ploughed on along its flight.
func _draw_impacts(lw: float) -> void:
	var now: float = sim.tick
	for k in sim.fx_t.size():
		var age: float = now - sim.fx_t[k]
		if age < 0.0 or age > FX_TICKS:
			continue
		var f := age / FX_TICKS
		var p := to_px(sim.fx_x[k], sim.fx_y[k])
		var dir := Vector2(sim.fx_dx[k], sim.fx_dy[k]) / 4096.0
		var a := 0.85 * (1.0 - f)
		draw_circle(p, px_per_m * (0.6 + 1.8 * f), Color(0.55, 0.45, 0.32, a * 0.55))
		draw_arc(p, px_per_m * (1.0 + 2.5 * f), 0, TAU, 16, Color(0.85, 0.75, 0.55, a), lw)
		draw_line(p, p + dir * px_per_m * 8.0, Color(0.35, 0.27, 0.18, a), maxf(lw * 1.5, px_per_m * 0.5))


## A dashed order line over a faint dark underlay, so it reads on light and
## dark ground alike.
func _dash_outlined(a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	draw_line(a, b, Color(0, 0, 0, 0.32), w * 2.6)
	draw_dashed_line(a, b, col, w, dash)


func _draw_fire_line(u: int, w: float) -> void:
	var t: int = sim.u_ftarget[u]
	if t < 0 or sim.u_state[t] >= BattleSim.U_DESTROYED:
		return
	draw_dashed_line(to_px(sim.u_cx[u], sim.u_cy[u]), to_px(sim.u_cx[t], sim.u_cy[t]),
		COL_FIRE, w, 4.0 / zoom)


## Missile range of unit u from angle a0 to a1 (radians): on hilly ground
## each point is the type's range against the ground under that point
## (two refinements of radius -> ground height -> range), so the ring
## bulges out where the ground falls away and pulls in uphill. Returns the
## end points (for the artillery sector edges).
func _draw_range(u: int, a0: float, a1: float, col: Color, w: float) -> Array:
	var ty: int = sim.u_type[u]
	var cx: int = sim.u_cx[u]
	var cy: int = sim.u_cy[u]
	var rng: int = UT.stat(ty, "m_range")
	var c := to_px(cx, cy)
	var full := a1 - a0 >= TAU - 0.001
	var steps := RANGE_STEPS if full else maxi(int(RANGE_STEPS * (a1 - a0) / TAU) + 2, 4)
	var pts := PackedVector2Array()
	for k in steps + 1:
		var ang := a0 + (a1 - a0) * k / steps
		var dir := Vector2(cos(ang), sin(ang))
		var r := rng
		if sim.ter_on != 0 or sim.obs_on != 0:
			for it in 2:
				var px := cx + int(dir.x * r)
				var py := cy + int(dir.y * r)
				r = sim.range_h(ty, sim.u_h[u], sim.height_at(px, py))
		pts.append(c + dir * (r * px_per_m / M))
	draw_polyline(pts, col, w)
	return [pts[0], pts[pts.size() - 1]]


## Flat weapons on hilly ground: if the line of fire from u to t is blocked
## by a crest, draw it broken and red up to the crest with a cross there,
## and faintly beyond. Returns true if it was blocked (and drawn).
func _draw_blocked(u: int, t: int, w: float) -> bool:
	var ty: int = sim.u_type[u]
	if (sim.ter_on == 0 and sim.map_on == 0) or UT.stat(ty, "m_arc") != 0 or sim.lof_units(u, t):
		return false
	var x0: int = sim.u_cx[u]
	var y0: int = sim.u_cy[u]
	var x1: int = sim.u_cx[t]
	var y1: int = sim.u_cy[t]
	var dist := maxf(Vector2(x1 - x0, y1 - y0).length(), 1.0)
	var apex: int = int(dist) * UT.stat(ty, "m_apex") / 100
	var blk: int = sim.lof_block(x0, y0, sim.u_h[u] + BattleSim.LOF_EYE, x1, y1,
		sim.u_h[t] + BattleSim.LOF_BODY, apex, 0, BattleSim.LOF_STEP)
	var a := to_px(x0, y0)
	var b := to_px(x1, y1)
	var crest := a.lerp(b, clampf(blk / dist, 0.05, 0.95)) if blk >= 0 else (a + b) * 0.5
	draw_dashed_line(a, crest, COL_BLOCKED, w * 1.3, 10.0 / zoom, false)
	draw_dashed_line(crest, b, Color(COL_BLOCKED, 0.3), w, 4.0 / zoom)
	var s := 9.0 / zoom
	draw_line(crest + Vector2(-s, -s), crest + Vector2(s, s), COL_BLOCKED, w * 2.0)
	draw_line(crest + Vector2(-s, s), crest + Vector2(s, -s), COL_BLOCKED, w * 2.0)
	draw_string(ThemeDB.fallback_font, crest + Vector2(s * 1.4, -s * 0.6), "NO LINE OF FIRE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(12.0), COL_BLOCKED)
	return true


## "uphill 12%" / "downhill 9%" from ground height ha to hb over (dx, dy)
## (sim units), at `at` (world pixels); nothing on gentle ground. "woods"
## (or "dense woods") when the way from (x0, y0) runs through trees.
func _draw_slope_hint(ha: int, hb: int, dx: int, dy: int, at: Vector2, x0: int = -1, y0: int = -1) -> void:
	var parts: Array[String] = []
	var col := COL_WOODS
	if sim.ter_on != 0:
		var d := maxf(Vector2(dx, dy).length(), 1.0)
		var g := int((hb - ha) * 4096.0 / maxf(d, 1024.0))
		if absi(g) >= HINT_GRADE:
			var pct := absi(g) * 100 / 4096
			parts.append(("uphill %d%%" % pct) if g > 0 else ("downhill %d%%" % pct))
			col = COL_UPHILL if g > 0 else COL_DOWNHILL
	if sim.veg_on != 0 and x0 >= 0:
		var w := _woods_on(x0, y0, x0 + dx, y0 + dy)
		if w > 0:
			parts.append("dense woods" if w >= 3 else "woods")
	if parts.is_empty():
		return
	draw_string(ThemeDB.fallback_font, at, ", ".join(parts), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), col)


## Densest woods on the line (sim units), sampled every 4 m (0 none).
func _woods_on(x0: int, y0: int, x1: int, y1: int) -> int:
	var l := Vector2(x1 - x0, y1 - y0).length()
	var n := int(l / 4096.0) + 1
	var best := 0
	for q in n + 1:
		var x := x0 + int((x1 - x0) * q / float(n))
		var y := y0 + int((y1 - y0) * q / float(n))
		best = maxi(best, sim.veg_d(x, y))
	return best


## Where a move line runs through woods: drawn over in green (stronger for
## denser woods), with a dot where it enters or leaves the trees.
func _draw_woods_along(x0: int, y0: int, x1: int, y1: int, lw: float) -> void:
	if sim.veg_on == 0:
		return
	var l := Vector2(x1 - x0, y1 - y0).length()
	var n := int(l / 4096.0) + 1
	var prev: int = sim.veg_d(x0, y0)
	var pa := to_px(x0, y0)
	for q in range(1, n + 1):
		var x := x0 + int((x1 - x0) * q / float(n))
		var y := y0 + int((y1 - y0) * q / float(n))
		var d: int = sim.veg_d(x, y)
		var pb := to_px(x, y)
		if prev > 0:
			draw_line(pa, pb, Color(COL_WOODS, 0.45 + 0.18 * prev), lw * (1.5 + 0.5 * prev))
		if (d > 0) != (prev > 0):
			draw_circle(pb, maxf(lw * 2.8, px_per_m * 0.75), Color(0, 0, 0, 0.5))
			draw_circle(pb, maxf(lw * 2.2, px_per_m * 0.6), COL_WOODS)
		prev = d
		pa = pb


func _draw_withdraw(u: int, from: Vector2, col: Color, w: float) -> void:
	var edge: float = (sim.field_h if sim.u_side[u] == 0 else 0) * px_per_m / M
	var to := Vector2(from.x, edge)
	draw_dashed_line(from, to, col, w, 10.0 / zoom)
	var dir := signf(to.y - from.y)
	var s := 12.0 / zoom
	draw_line(to, to + Vector2(-s, -dir * s), col, w * 1.5)
	draw_line(to, to + Vector2(s, -dir * s), col, w * 1.5)
	draw_string(ThemeDB.fallback_font, from + Vector2(s, dir * s * 2.0), "WITHDRAW",
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(12.0), col)


func _draw_preview(lw: float) -> void:
	var col := Color(1, 1, 1, 0.9) if preview_ok else Color(1, 1, 1, 0.4)
	draw_line(preview_a, preview_b, Color(0, 0, 0, 0.35), lw * 3.5)
	draw_line(preview_a, preview_b, col, lw * 1.5)
	if not preview_ok or selected_units.is_empty():
		return
	var dot_r := maxf(1.5, px_per_m * 0.25)
	for p in preview_group():
		var u: int = p["unit"]
		var face: int = p["facing"]
		var centre: Vector2 = p["centre"]
		var offs := BattleSim.formation_offsets(sim.u_alive[u], p["files"], face, sim.u_type[u])
		var feat: bool = sim.map_on != 0
		for k in range(0, offs.size(), 2):
			var dp := centre + Vector2(offs[k], offs[k + 1]) * (px_per_m / M)
			var dc := Color(1, 1, 1, 0.55)
			if feat:
				# Men who would stand in woods (green) or in a wall / house (red).
				var sx := int(dp.x / px_per_m * M)
				var sy := int(dp.y / px_per_m * M)
				if sim.obs_on != 0 and (sim.nav_at(sx, sy) & 1) == 0:
					dc = COL_BLOCK_CELL
				elif sim.veg_d(sx, sy) > 0:
					dc = Color(COL_WOODS, 0.8)
			draw_circle(dp, dot_r, dc)
		if sim.u_wall[u] > 0:
			draw_string(ThemeDB.fallback_font, centre + Vector2(0, -px_per_m * 4.0), "holds its stretch of wall",
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(12.0), Color(1, 0.9, 0.6))
		var ang := face * TAU / 1024.0
		var fwd := Vector2(cos(ang), sin(ang))
		draw_line(centre, centre + fwd * px_per_m * 5.0, Color(1, 1, 0.6, 0.9), lw * 1.5)


## Footprint of a formation: rectangle from the front line back through the
## last rank, at the real frontage and rank count, plus a facing tick.
func _draw_footprint(u: int, front: Vector2, face: int, files: int, alive: int, edge: Color,
		fill: Color, w: float) -> void:
	var ty: int = sim.u_type[u]
	files = clampi(files, 1, maxi(alive, 1))
	var ranks := (alive + files - 1) / files
	var ang := face * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var k := px_per_m / M
	var hw := (files - 1) * UT.stat(ty, "file_sp") * 0.5 * k + px_per_m * 0.45
	var depth := (ranks - 1) * UT.stat(ty, "rank_sp") * k + px_per_m * 0.45
	var a := front - right * hw + fwd * px_per_m * 0.45
	var b := front + right * hw + fwd * px_per_m * 0.45
	var c := b - fwd * (depth + px_per_m * 0.45)
	var d := a - fwd * (depth + px_per_m * 0.45)
	if fill.a > 0.0:
		draw_colored_polygon(PackedVector2Array([a, b, c, d]), fill)
	draw_polyline(PackedVector2Array([b, c, d, a]), Color(edge, edge.a * 0.6), w)
	draw_line(a, b, edge, w * 1.6)  # front rank, stronger
	draw_line(front, front + fwd * px_per_m * 2.5, edge, w)


## Every friendly unit's order at once (toggle in the HUD). Thin and faint so
## 20 units stay readable on a phone; selected units are skipped here and
## drawn on top by the normal selection code.
func _draw_all_orders() -> void:
	var w := 1.2 / zoom
	var col_move := Color(0.65, 1.0, 0.65, 0.55)
	var fill_move := Color(0.65, 1.0, 0.65, 0.08)
	var col_still := Color(1, 1, 1, 0.35)
	var col_attack := Color(1.0, 0.45, 0.35, 0.45)
	for u in sim.n_units:
		if selected_units.has(u) or sim.u_side[u] != player_side or sim.u_state[u] != BattleSim.U_READY:
			continue
		var alive: int = sim.u_alive[u]
		var anchor := to_px(_v(u, "ax"), _v(u, "ay"))
		var order: int = _v(u, "order")
		if order == BattleSim.O_MOVE:
			var dest := to_px(_v(u, "dx"), _v(u, "dy"))
			draw_line(to_px(sim.u_cx[u], sim.u_cy[u]), dest, Color(col_move, 0.3), w)
			_draw_footprint(u, dest, _v(u, "dface"), _v(u, "files"), alive, col_move, fill_move, w)
		elif order == BattleSim.O_ATTACK and _v(u, "target") >= 0:
			var t: int = _v(u, "target")
			if not (sim.u_ammo[u] > 0 and _draw_blocked(u, t, w)):
				draw_dashed_line(anchor, to_px(sim.u_cx[t], sim.u_cy[t]), col_attack, w, 6.0 / zoom)
			_draw_footprint(u, anchor, _v(u, "face"), _v(u, "files"), alive, Color(col_attack, 0.3), Color(0, 0, 0, 0), w)
		elif order == BattleSim.O_WITHDRAW:
			_draw_withdraw(u, anchor, Color(COL_WITHDRAW, 0.5), w)
		else:
			_draw_footprint(u, anchor, _v(u, "face"), _v(u, "files"), alive, col_still, Color(0, 0, 0, 0), w)
		var ucls := UT.cls(sim.u_type[u])
		if ucls == UT.CLS_MISSILE or ucls == UT.CLS_ART:
			_draw_fire_line(u, w)
			if _v(u, "fire") == 0 and sim.u_ammo[u] > 0:
				draw_string(ThemeDB.fallback_font, to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(10, 18) / zoom,
					"HOLD FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(11.0), Color(1, 0.85, 0.5, 0.8))
			if ucls == UT.CLS_ART and (_v(u, "refill") != 0 or sim.u_rprog[u] > 0):
				var full_ammo: int = sim.u_neng[u] * UT.stat(sim.u_type[u], "m_ammo")
				draw_string(ThemeDB.fallback_font, to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(10, 46) / zoom,
					"REFILLING %d%%" % (maxi(sim.u_ammo[u], 0) * 100 / maxi(full_ammo, 1)),
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(11.0), Color(0.55, 0.85, 1.0, 0.9))
			if ucls == UT.CLS_ART and _v(u, "deploy") == 0:
				draw_string(ThemeDB.fallback_font, to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(10, 32) / zoom,
					"PACKED UP", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(11.0), Color(0.85, 0.9, 1.0, 0.8))


## Formations implied by the current preview line. The line is the front
## rank: it faces 90 degrees anticlockwise (on screen) from the drag
## direction, so a left-to-right drag faces up the screen. One unit takes
## the whole line; a group is laid out side by side along it, keeping the
## units' current left-to-right order, each getting frontage in proportion to
## its soldiers. Entries: {unit, centre (world px), facing, width, files}.
func preview_group() -> Array:
	var out: Array = []
	var d := preview_b - preview_a
	var len_px := d.length()
	if len_px <= 0.0:
		return out
	var dir := d / len_px
	var face_ang := atan2(d.y, d.x) - PI * 0.5
	var face := int(round(face_ang * 1024.0 / TAU)) & 1023
	var units: Array[int] = []
	for u in selected_units:
		if sim.u_state[u] == BattleSim.U_READY:
			units.append(u)
	if units.is_empty():
		return out
	# Left-to-right along the drag direction, by current position.
	units.sort_custom(func(a: int, b: int) -> bool:
		var pa := to_px(sim.u_cx[a], sim.u_cy[a]).dot(dir)
		var pb := to_px(sim.u_cx[b], sim.u_cy[b]).dot(dir)
		return pa < pb or (pa == pb and a < b))
	var len_m := len_px / px_per_m
	var gaps := GROUP_GAP_M * (units.size() - 1)
	var usable := maxf(len_m - gaps, 1.0)
	var total_w := 0.0
	for u in units:
		total_w += _line_weight(u)
	var x := 0.0
	for u in units:
		var share: float = usable * _line_weight(u) / total_w
		if units.size() == 1:
			share = len_m
		var width := int(share * M)
		var files: int = BattleSim.width_to_files(width, sim.u_alive[u], sim.u_type[u])
		if sim.u_neng[u] > 0:
			files = sim.u_neng[u]  # a battery's frontage is its engines
		var centre: Vector2 = preview_a + dir * (x + share * 0.5) * px_per_m
		if units.size() == 1:
			centre = (preview_a + preview_b) * 0.5
		out.append({"unit": u, "centre": centre, "facing": face, "width": width, "files": files})
		x += share + GROUP_GAP_M
	return out


## Share of a drawn line a unit gets: its soldiers' file width (a battery:
## its engines' frontage, weighted like a four-rank unit).
func _line_weight(u: int) -> float:
	var fsp := float(UT.stat(sim.u_type[u], "file_sp"))
	if sim.u_neng[u] > 0:
		return sim.u_neng[u] * fsp * 4.0
	return sim.u_alive[u] * fsp


## Single-unit form of preview_group (kept for callers and tests).
func preview_formation() -> Dictionary:
	var g := preview_group()
	if g.is_empty():
		return {"centre": (preview_a + preview_b) * 0.5, "facing": 0, "width": 0, "files": 1}
	return g[0]
