extends Node2D
## World-space overlay: unit markers, the selected unit's formation and orders,
## and the live preview while the player draws a destination line.

const BattleSim := preload("res://sim/battle_sim.gd")
const M := 1024.0

var sim
var px_per_m: float = 10.0
var selected_unit: int = -1
var zoom: float = 1.0
var show_all_orders := false   # draw every friendly unit's order footprint
var player_side := 0
var orders  # OrderPreview: predicted order state including not-yet-applied orders

# Drag preview (world pixels), active when preview_on.
var preview_on := false
var preview_a := Vector2.ZERO
var preview_b := Vector2.ZERO
var preview_ok := false  # long enough to be a formation line

const COL_SIDE := [Color(0.35, 0.6, 1.0), Color(1.0, 0.36, 0.28)]


## Unit order field as the player last ordered it (pending orders included).
func _v(u: int, key: String) -> int:
	if orders != null:
		return orders.value(u, key)
	return (sim.get("u_" + key) as PackedInt32Array)[u]


func to_px(x: int, y: int) -> Vector2:
	return Vector2(x, y) * (px_per_m / M)


func _draw() -> void:
	if sim == null:
		return
	var lw := maxf(1.5, 2.0 / zoom)
	var r := maxf(5.0, 9.0 / zoom)
	if show_all_orders:
		_draw_all_orders()
	# Unit markers at the centroid: side colour, white ring when selected,
	# yellow when routing.
	for u in sim.n_units:
		if sim.u_state[u] == BattleSim.U_DESTROYED:
			continue
		var c := to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(0, -r * 2.2)
		var col: Color = COL_SIDE[sim.u_side[u]]
		if sim.u_state[u] == BattleSim.U_ROUTING:
			col = Color(1.0, 0.9, 0.3)
		draw_circle(c, r, col)
		draw_arc(c, r, 0, TAU, 16, Color(0, 0, 0, 0.6), lw * 0.6)
		if u == selected_unit:
			draw_arc(c, r * 1.6, 0, TAU, 20, Color.WHITE, lw)

	if selected_unit >= 0 and selected_unit < sim.n_units and sim.u_state[selected_unit] != BattleSim.U_DESTROYED:
		var u := selected_unit
		var files := mini(_v(u, "files"), sim.u_alive[u])
		var half := (files - 1) * BattleSim.FILE_SPACING / 2
		var a := to_px(_v(u, "ax"), _v(u, "ay"))
		var ang: float = _v(u, "face") * TAU / 1024.0
		var fwd := Vector2(cos(ang), sin(ang))
		var right := Vector2(-fwd.y, fwd.x)
		var hw := half * px_per_m / M
		draw_line(a - right * hw, a + right * hw, Color(1, 1, 1, 0.8), lw)
		draw_line(a, a + fwd * px_per_m * 3.0, Color(1, 1, 1, 0.8), lw)
		if _v(u, "order") == BattleSim.O_MOVE:
			var d := to_px(_v(u, "dx"), _v(u, "dy"))
			var dang: float = _v(u, "dface") * TAU / 1024.0
			var dfwd := Vector2(cos(dang), sin(dang))
			var dright := Vector2(-dfwd.y, dfwd.x)
			draw_dashed_line(a, d, Color(0.6, 1.0, 0.6, 0.7), lw, 8.0 / zoom)
			draw_line(d - dright * hw, d + dright * hw, Color(0.6, 1.0, 0.6, 0.9), lw * 1.5)
			draw_line(d, d + dfwd * px_per_m * 3.0, Color(0.6, 1.0, 0.6, 0.9), lw)
		elif _v(u, "order") == BattleSim.O_ATTACK and _v(u, "target") >= 0:
			var t: int = _v(u, "target")
			draw_dashed_line(a, to_px(sim.u_cx[t], sim.u_cy[t]), Color(1, 0.3, 0.2, 0.85), lw, 8.0 / zoom)
		if _v(u, "run") != 0:
			draw_string(ThemeDB.fallback_font, a + Vector2(r, -r * 3.5), "RUN",
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(10.0, 14.0 / zoom)), Color.WHITE)

	if preview_on:
		var col := Color(1, 1, 1, 0.9) if preview_ok else Color(1, 1, 1, 0.4)
		draw_line(preview_a, preview_b, col, lw * 1.5)
		if preview_ok and selected_unit >= 0:
			var p := preview_formation()
			var face: int = p["facing"]
			var centre: Vector2 = p["centre"]
			var offs := BattleSim.formation_offsets(sim.u_alive[selected_unit], p["files"], face)
			var dot_r := maxf(1.5, px_per_m * 0.25)
			for k in range(0, offs.size(), 2):
				draw_circle(centre + Vector2(offs[k], offs[k + 1]) * (px_per_m / M), dot_r, Color(1, 1, 1, 0.55))
			var ang := face * TAU / 1024.0
			var fwd := Vector2(cos(ang), sin(ang))
			draw_line(centre, centre + fwd * px_per_m * 5.0, Color(1, 1, 0.6, 0.9), lw * 1.5)


## Footprint of a formation: rectangle from the front line back through the
## last rank, at the real frontage and rank count, plus a facing tick.
func _draw_footprint(front: Vector2, face: int, files: int, alive: int, edge: Color,
		fill: Color, w: float) -> void:
	files = clampi(files, 1, maxi(alive, 1))
	var ranks := (alive + files - 1) / files
	var ang := face * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var k := px_per_m / M
	var hw := (files - 1) * BattleSim.FILE_SPACING * 0.5 * k + px_per_m * 0.45
	var depth := (ranks - 1) * BattleSim.RANK_SPACING * k + px_per_m * 0.45
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
## 20 units stay readable on a phone; the selected unit is skipped here and
## drawn on top by the normal selection code.
func _draw_all_orders() -> void:
	var w := 1.2 / zoom
	var col_move := Color(0.65, 1.0, 0.65, 0.55)
	var fill_move := Color(0.65, 1.0, 0.65, 0.08)
	var col_still := Color(1, 1, 1, 0.35)
	var col_attack := Color(1.0, 0.45, 0.35, 0.45)
	for u in sim.n_units:
		if u == selected_unit or sim.u_side[u] != player_side or sim.u_state[u] != BattleSim.U_READY:
			continue
		var alive: int = sim.u_alive[u]
		var anchor := to_px(_v(u, "ax"), _v(u, "ay"))
		var order: int = _v(u, "order")
		if order == BattleSim.O_MOVE:
			var dest := to_px(_v(u, "dx"), _v(u, "dy"))
			draw_line(to_px(sim.u_cx[u], sim.u_cy[u]), dest, Color(col_move, 0.3), w)
			_draw_footprint(dest, _v(u, "dface"), _v(u, "files"), alive, col_move, fill_move, w)
		elif order == BattleSim.O_ATTACK and _v(u, "target") >= 0:
			var t: int = _v(u, "target")
			draw_dashed_line(anchor, to_px(sim.u_cx[t], sim.u_cy[t]), col_attack, w, 6.0 / zoom)
			_draw_footprint(anchor, _v(u, "face"), _v(u, "files"), alive, Color(col_attack, 0.3), Color(0, 0, 0, 0), w)
		else:
			_draw_footprint(anchor, _v(u, "face"), _v(u, "files"), alive, col_still, Color(0, 0, 0, 0), w)


## Formation implied by the current preview line. The line is the front rank:
## its midpoint is the front centre, its length the frontage, and the unit
## faces 90 degrees anticlockwise (on screen) from the drag direction, so a
## left-to-right drag faces up the screen.
func preview_formation() -> Dictionary:
	var centre := (preview_a + preview_b) * 0.5
	var d := preview_b - preview_a
	var len_m := d.length() / px_per_m
	var drag_ang := atan2(d.y, d.x)
	var face_ang := drag_ang - PI * 0.5
	var face := int(round(face_ang * 1024.0 / TAU)) & 1023
	var files: int = BattleSim.width_to_files(int(len_m * M), sim.u_alive[selected_unit])
	return {"centre": centre, "facing": face, "width": int(len_m * M), "files": files}
