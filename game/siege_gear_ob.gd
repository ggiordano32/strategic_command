extends RefCounted
## Siege equipment standing up in the oblique view (docs/design/art_pipeline.md "(2026-11-01) Siege equipment in oblique"):
## ladder bundles and planted ladders, scaling poles, the ram, the siege tower, mantlets and the wagon, drawn as
## small solids projected with the board's own oblique constants (BoardView.OBLIQUE_COS for ground depth, OBLIQUE_SIN
## for height) as upright items (BoardView.up_xf) round the piece's ground point, in the overlay's world px. View only: it
## reads the sim and writes nothing. The top view keeps overlay.gd's flat drawing.
## The 3D view (game/view3d.gd, `build_mesh`): the same pieces as real solids, every box, bar, quad and disc emitted into a
## SurfaceTool in world metres (the ground under the piece's anchor its foot), lit by the lamp and casting shadows; the
## overlay then skips them.

const BattleSim := preload("res://sim/battle_sim.gd")
const BoardView := preload("res://game/board_view.gd")
const UT := preload("res://sim/unit_types.gd")

const WOOD := Color(0.62, 0.43, 0.22)
const WOOD_LIGHT := Color(0.78, 0.58, 0.32)
const WOOD_DARK := Color(0.30, 0.19, 0.09)
const WRECK := Color(0.26, 0.21, 0.16)
const LINE := Color(0.14, 0.08, 0.03, 0.95)
const LADDER_LEAN_M := 1.2    # how far toward the wall a planted ladder leans
const RAM_H_M := 2.3
const MANTLET_H_M := 1.9
const LIGHT := Vector2(-0.6, -0.8)   # toward the key light on the ground (from the top left of the screen)

var ci: CanvasItem
var sim
var ppm := 10.0
var lw := 1.5
func _walk_m() -> float:
	return maxf(float(sim.wall_h) / 1024.0, 5.0)   # the walkway's height (a field battle has none: 5 m for the picture)


var _a := Vector2.ZERO      # the anchor (world px)
var st3: SurfaceTool = null   # the 3D view: geometry goes here (metres), not to the canvas
var _a3 := Vector3.ZERO       # the anchor's ground point (3D, metres)
var ground_m: Callable        # the 3D view: the ground's height (m) at a world point (px)


## The 3D view: every piece as solids into a new mesh (null when there is none).
func build_mesh(p_sim, p_ppm: float, gear_angle: Callable, p_ground: Callable) -> ArrayMesh:
	sim = p_sim
	ppm = p_ppm
	lw = 1.0
	ground_m = p_ground
	st3 = SurfaceTool.new()
	st3.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for q in sim.n_eq:
		if BattleSim.EQ_FW[sim.q_kind[q]] != 0:
			continue
		var ang: float = gear_angle.call(q)
		if is_nan(ang):
			continue
		_piece(q, ang)
		n += 1
	var mesh: ArrayMesh = null
	if n > 0:
		mesh = st3.commit()
	st3 = null
	return mesh


## A point off metres from the anchor (x east, y south) h metres up, in 3D (metres).
func _p3(off: Vector2, h: float) -> Vector3:
	return _a3 + Vector3(off.x, h, off.y)


func _tri3(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	for v in [a, b, c]:
		st3.set_color(col)
		st3.set_normal(n)
		st3.add_vertex(v)


func _quad3(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri3(a, b, c, col)
	_tri3(a, c, d, col)


## A quad given as [offset, height] pairs (the 2D views: projected and drawn; the 3D view: a real quad).
func _quad_oh(pts: Array, col: Color) -> void:
	if st3 != null:
		_quad3(_p3(pts[0][0], pts[0][1]), _p3(pts[1][0], pts[1][1]), _p3(pts[2][0], pts[2][1]), _p3(pts[3][0], pts[3][1]), col)
		return
	var v: Array = []
	for pp in pts:
		v.append(_pt(pp[0], pp[1]))
	_quad(v, col)


## A round knob (a wheel, the ram's head, a horse's head): a disc on the canvas, a small box in 3D.
func _disc(off: Vector2, h: float, r_px: float, col: Color) -> void:
	if st3 != null:
		var r := r_px / ppm
		var c := _p3(off, h)
		_cube3(c, r, col)
		return
	ci.draw_circle(_pt(off, h), r_px, col)


func _cube3(c: Vector3, r: float, col: Color) -> void:
	var x := Vector3(r, 0, 0)
	var y := Vector3(0, r, 0)
	var z := Vector3(0, 0, r)
	_quad3(c - x - y + z, c + x - y + z, c + x + y + z, c - x + y + z, col)
	_quad3(c + x - y - z, c - x - y - z, c - x + y - z, c + x + y - z, col)
	_quad3(c + x - y + z, c + x - y - z, c + x + y - z, c + x + y + z, col)
	_quad3(c - x - y - z, c - x - y + z, c - x + y + z, c - x + y - z, col)
	_quad3(c - x + y + z, c + x + y + z, c + x + y - z, c - x + y - z, col)


## A point `off` metres from the anchor on the ground (x east, y south) and h metres up, in the upright group's px.
func _pt(off: Vector2, h: float) -> Vector2:
	return _a + Vector2(off.x * ppm, off.y * ppm * BoardView.OBLIQUE_COS - h * ppm * BoardView.OBLIQUE_SIN)


func _begin(anchor: Vector2) -> void:
	_a = anchor
	if st3 != null:
		_a3 = Vector3(anchor.x / ppm, float(ground_m.call(anchor)), anchor.y / ppm)
		return
	ci.draw_set_transform_matrix(BoardView.up_xf(anchor))


func _end() -> void:
	if st3 != null:
		return
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func _bar(p0: Vector2, h0: float, p1: Vector2, h1: float, col: Color, w: float) -> void:
	if st3 != null:
		# (a beam: a square timber about w x 0.09 m thick)
		var a3 := _p3(p0, h0)
		var b3 := _p3(p1, h1)
		var d := b3 - a3
		if d.length_squared() < 1e-8:
			return
		var t := maxf(0.06, w * 0.06)
		var side := d.cross(Vector3.UP)
		if side.length_squared() < 1e-8:
			side = Vector3.RIGHT
		side = side.normalized() * t
		var up := side.cross(d).normalized() * t
		_quad3(a3 - side + up, b3 - side + up, b3 + side + up, a3 + side + up, col)
		_quad3(a3 + side - up, b3 + side - up, b3 - side - up, a3 - side - up, _tint(col, 0.7))
		_quad3(a3 + side + up, b3 + side + up, b3 + side - up, a3 + side - up, _tint(col, 0.85))
		_quad3(a3 - side - up, b3 - side - up, b3 - side + up, a3 - side + up, _tint(col, 0.85))
		return
	var a := _pt(p0, h0)
	var b := _pt(p1, h1)
	ci.draw_line(a, b, LINE, w + maxf(1.0, lw * 0.9))
	ci.draw_line(a, b, col, w)


func _quad(pts: Array, col: Color) -> void:
	var v := PackedVector2Array(pts)
	ci.draw_colored_polygon(v, col)
	v.append(v[0])
	ci.draw_polyline(v, LINE, maxf(1.0, lw * 0.8))


func _tint(col: Color, k: float) -> Color:
	return Color(col.r * k, col.g * k, col.b * k, col.a)


## A box: ground centre `c` (metres from the anchor), half sizes along fwd (f) and side (s) unit vectors, from height
## h0 to h1. Its standing faces far first, shaded by the key light, then its top.
func _box(c: Vector2, f: Vector2, s: Vector2, hf: float, hs: float, h0: float, h1: float, col: Color) -> void:
	var cs := [c + f * hf + s * hs, c + f * hf - s * hs, c - f * hf - s * hs, c - f * hf + s * hs]
	if st3 != null:
		# (every face: the depth buffer hides the far ones)
		for i in 4:
			var p: Vector2 = cs[i]
			var q: Vector2 = cs[(i + 1) % 4]
			var n := ((p + q) * 0.5 - c).normalized()
			var k3 := 0.62 + 0.38 * clampf(n.dot(LIGHT.normalized()) * 0.5 + 0.5, 0.0, 1.0)
			_quad3(_p3(p, h0), _p3(q, h0), _p3(q, h1), _p3(p, h1), _tint(col, k3))
		_quad3(_p3(cs[3], h1), _p3(cs[2], h1), _p3(cs[1], h1), _p3(cs[0], h1), _tint(col, 1.12))
		return
	var faces: Array = []
	for i in 4:
		var p: Vector2 = cs[i]
		var q: Vector2 = cs[(i + 1) % 4]
		var mid := (p + q) * 0.5
		var n := (mid - c).normalized()
		faces.append([mid.y, p, q, n])
	faces.sort_custom(func(x, y): return x[0] < y[0])
	for fc in faces:
		var n: Vector2 = fc[3]
		if n.y <= -0.35:
			continue   # (a face turned away from the camera is hidden behind the box)
		var k := 0.62 + 0.38 * clampf(n.dot(LIGHT.normalized()) * 0.5 + 0.5, 0.0, 1.0)
		var p: Vector2 = fc[1]
		var q: Vector2 = fc[2]
		_quad([_pt(p, h0), _pt(q, h0), _pt(q, h1), _pt(p, h1)], _tint(col, k))
	_quad([_pt(cs[0], h1), _pt(cs[1], h1), _pt(cs[2], h1), _pt(cs[3], h1)], _tint(col, 1.12))


func _cross(c: Vector2, f: Vector2, s: Vector2, hf: float, hs: float, h: float) -> void:
	_bar(c + f * hf + s * hs, h, c - f * hf - s * hs, h, WRECK, lw * 1.2)
	_bar(c + f * hf - s * hs, h, c - f * hf + s * hs, h, WRECK, lw * 1.2)


## All of the sim's siege equipment (everything the overlay's _draw_siege_gear draws).
func draw_all(p_ci: CanvasItem, p_sim, p_ppm: float, p_lw: float, gear_angle: Callable) -> void:
	ci = p_ci
	sim = p_sim
	ppm = p_ppm
	lw = p_lw
	var order: Array = []
	for q in sim.n_eq:
		if BattleSim.EQ_FW[sim.q_kind[q]] != 0:
			continue
		var ang: float = gear_angle.call(q)
		if is_nan(ang):
			continue
		order.append([float(sim.q_y[q]), q, ang])
	order.sort_custom(func(x, y): return x[0] < y[0])   # far to near
	for it in order:
		_piece(int(it[1]), float(it[2]))


func _piece(q: int, ang: float) -> void:
	var k: int = sim.q_kind[q]
	var st: int = sim.q_state[q]
	var at := Vector2(sim.q_x[q], sim.q_y[q]) * (ppm / 1024.0)
	var f := Vector2(cos(ang), sin(ang))
	var s := Vector2(-f.y, f.x)
	var wrecked := st == BattleSim.Q_WRECKED
	if k == BattleSim.EQ_WAGON:
		_wagon(q, at, f, s, st)
	elif BattleSim.EQ_EXPOSED[k] != 0:
		_tower(q, at, f, s, st)
	elif BattleSim.EQ_SCREEN[k] != 0:
		_mantlet(q, at, st)
	elif k == BattleSim.EQ_RAM:
		_begin(at)
		var c := Vector2.ZERO
		if st == BattleSim.Q_CARRIED:
			c = -f * 2.0
		var col := WRECK if wrecked else WOOD
		var h1 := RAM_H_M * (0.35 if wrecked else 1.0)
		var mid := c + f * 0.25
		_box(mid, f, s, 3.25, 1.4, 0.35, h1, col)
		if wrecked:
			_cross(mid, f, s, 3.25, 1.4, h1)
		else:
			# the hanging beam, its iron head out of the front, and the pitched roof's ridge
			_bar(c - f * 3.0, 1.0, c + f * 4.6, 1.0, WOOD_DARK, lw * 2.2)
			_disc(c + f * 4.6, 1.0, maxf(lw * 1.6, ppm * 0.22), Color(0.3, 0.3, 0.33))
			_bar(mid - f * 3.25, h1 + 0.5, mid + f * 3.25, h1 + 0.5, WOOD_LIGHT, lw * 1.2)
		_end()
	elif st == BattleSim.Q_PLANTED:
		_planted(q)
	else:
		_bundle(q, at, f, s, st)


## Five ladders (or two poles) lying on the ground or on the carriers' shoulders.
func _bundle(q: int, at: Vector2, f: Vector2, s: Vector2, st: int) -> void:
	_begin(at)
	var c := Vector2.ZERO
	var h := 0.2
	var wrecked := st == BattleSim.Q_WRECKED
	if st == BattleSim.Q_CARRIED:
		c = -f * 1.5
		h = 1.7
	var col := WRECK if wrecked else WOOD
	if sim.q_kind[q] == BattleSim.EQ_POLES:
		for i in 2:
			var o := s * (float(i) - 0.5) * 0.6
			_bar(c - f * 3.6 + o, h, c + f * 3.6 + o, h + (0.15 if st == BattleSim.Q_CARRIED else 0.0), col, lw * 1.5)
		_end()
		return
	# Three rails with rungs across, the near rail drawn last.
	var rails: Array = [-1.0, 0.0, 1.0]
	rails.sort_custom(func(x, y): return (s * float(x)).y < (s * float(y)).y)
	for r in 6:
		var rq := c + f * (-2.6 + r * 1.04)
		_bar(rq - s * 0.9, h, rq + s * 0.9, h, col, lw * 0.8)
	for v in rails:
		var o: Vector2 = s * float(v) * 0.7
		_bar(c - f * 3.0 + o, h, c + f * 3.0 + o, h, col, lw * 1.4)
	_end()


## A planted set: each ladder or pole leans from its foot toward the wall.
func _planted(q: int) -> void:
	var dir: float = sim.ws_dir[sim.q_seg[q]] * TAU / 1024.0
	var inw := -Vector2(cos(dir), sin(dir))
	var sd := Vector2(-sin(dir), cos(dir))
	var poles: bool = sim.q_kind[q] == BattleSim.EQ_POLES
	var feet: Array = []
	for k in BattleSim.EQ_LANES[sim.q_kind[q]]:
		var fo: Vector2i = sim.set_ladder_foot(q, k)
		feet.append(Vector2(fo.x, fo.y) * (ppm / 1024.0))
	feet.sort_custom(func(x, y): return x.y < y.y)
	for fp in feet:
		_begin(fp)
		var top := inw * LADDER_LEAN_M
		var th := _walk_m() + (1.6 if poles else 0.9)
		if poles:
			_bar(Vector2.ZERO, 0.0, top, th, WOOD, lw * 1.8)
			for r in 6:
				var t := 0.12 + 0.15 * r
				_bar(top * t - sd * 0.25, th * t, top * t + sd * 0.25, th * t, WOOD_LIGHT, lw * 0.8)
		else:
			for r in 7:
				var t := 0.1 + 0.13 * r
				_bar(top * t - sd * 0.45, th * t, top * t + sd * 0.45, th * t, WOOD_LIGHT, lw * 0.8)
			for rail in [-1.0, 1.0]:
				_bar(sd * 0.45 * rail, 0.0, top + sd * 0.45 * rail, th, WOOD, lw * 1.3)
		_end()


func _tower(q: int, at: Vector2, f: Vector2, s: Vector2, st: int) -> void:
	var h := float(BattleSim.EQ_DEPTH2[sim.q_kind[q]]) / 1024.0
	var wrecked := st == BattleSim.Q_WRECKED
	if st == BattleSim.Q_PLANTED:
		var dir: float = sim.ws_dir[sim.q_seg[q]] * TAU / 1024.0
		var qc: Vector2i = sim.eq_centre(q)
		at = Vector2(qc.x, qc.y) * (ppm / 1024.0)
		f = -Vector2(cos(dir), sin(dir))
		s = Vector2(-f.y, f.x)
	_begin(at)
	var c := Vector2.ZERO
	if st == BattleSim.Q_CARRIED:
		c = f
	var top := (_walk_m() + 2.6) * (0.3 if wrecked else 1.0)
	_box(c, f, s, h, h, 0.0, top, WRECK if wrecked else Color(0.55, 0.37, 0.19))
	if wrecked:
		_cross(c, f, s, h, h, top)
		_end()
		return
	# Storey lines and loopholes on the faces that show, the platform's rail, the drawbridge.
	for sh in [top * 0.33, top * 0.66]:
		_bar(c + f * h + s * h, sh, c + f * h - s * h, sh, WOOD_DARK, lw * 1.0)
		_bar(c + f * h + s * h, sh, c - f * h + s * h, sh, WOOD_DARK, lw * 1.0)
		_bar(c + f * h - s * h, sh, c - f * h - s * h, sh, WOOD_DARK, lw * 1.0)
		_bar(c - f * h - s * h, sh, c - f * h + s * h, sh, WOOD_DARK, lw * 1.0)
	for e in [1.0, -1.0]:
		_bar(c + f * h + s * h * e, top, c + f * h + s * h * e, top + 0.9, WOOD_DARK, lw * 1.2)
	var rl := 3.5 if st == BattleSim.Q_PLANTED else 1.0
	var r0 := c + f * h
	var rh := _walk_m()
	if st == BattleSim.Q_PLANTED:
		_quad_oh([[r0 + s * h * 0.7, rh], [r0 - s * h * 0.7, rh],
			[r0 + f * rl - s * h * 0.7, rh - 0.8], [r0 + f * rl + s * h * 0.7, rh - 0.8]], WOOD_LIGHT)
	else:
		# raised: a flap standing against the face
		_quad_oh([[r0 + s * h * 0.7, rh], [r0 - s * h * 0.7, rh],
			[r0 - s * h * 0.7 + f * 0.3, rh + 1.6], [r0 + s * h * 0.7 + f * 0.3, rh + 1.6]], WOOD_LIGHT)
	_end()


func _mantlet(q: int, at: Vector2, st: int) -> void:
	var f: Vector2
	var wrecked := st == BattleSim.Q_WRECKED
	var a: float
	var c := Vector2.ZERO
	if st != BattleSim.Q_CARRIED:
		a = sim.q_face[q] * TAU / 1024.0
		f = Vector2(cos(a), sin(a))
	else:
		var u: int = sim.q_unit[q]
		a = (sim.u_face[u] if u >= 0 else 0) * TAU / 1024.0
		f = Vector2(cos(a), sin(a))
		c = f * 0.8
	var s := Vector2(-f.y, f.x)
	var ln: int = sim.q_len[q] if sim.q_len[q] > 0 else BattleSim.EQ_SCREEN_W[sim.q_kind[q]]
	var hw := float(ln) / 1024.0 / 2.0
	_begin(at)
	var top := MANTLET_H_M * (0.3 if wrecked else 1.0)
	_box(c, f, s, 0.3, hw, 0.0, top, WRECK if wrecked else Color(0.5, 0.34, 0.17))
	if wrecked:
		_cross(c, f, s, 0.3, hw, top)
	else:
		# plank seams on the front face and two props behind it
		for i in range(1, 6):
			var o := s * hw * (-1.0 + 0.4 * i)
			_bar(c + f * 0.31 + o, 0.1, c + f * 0.31 + o, top - 0.05, WOOD_DARK, lw * 0.6)
		for sg in [-1.0, 1.0]:
			_bar(c - f * 0.3 + s * hw * 0.7 * sg, top * 0.9, c - f * 1.3 + s * hw * 0.7 * sg, 0.0, WOOD_DARK, lw * 1.2)
	_end()


func _wagon(q: int, at: Vector2, f: Vector2, s: Vector2, st: int) -> void:
	var wrecked := st == BattleSim.Q_WRECKED
	_begin(at)
	var body := WRECK if wrecked else Color(0.66, 0.54, 0.34)
	var h1 := 0.9 if wrecked else 1.4
	_box(Vector2.ZERO, f, s, 2.2, 1.1, 0.5, h1, body)
	if not wrecked:
		# the canvas hoops over the load
		for i in 4:
			var o := f * (-1.5 + i * 1.0)
			_bar(o - s * 0.9, h1, o, h1 + 0.8, Color(0.9, 0.85, 0.7), lw * 0.9)
			_bar(o, h1 + 0.8, o + s * 0.9, h1, Color(0.9, 0.85, 0.7), lw * 0.9)
		for sg in [-1.0, 1.0]:
			for w in [-1.0, 1.0]:
				_disc(s * 1.2 * sg + f * 1.3 * w, 0.5, maxf(lw * 1.6, ppm * 0.42), WOOD_DARK)
		var horses := UT.wagon_stat(sim.q_tier[q], "horses")
		for hh in horses:
			var hp := f * 3.9 + s * (0.0 if horses == 1 else (hh - 0.5) * 1.05)
			if hh < int(sim.q_hn[q]):
				_box(hp, f, s, 0.9, 0.3, 0.4, 1.5, Color(0.45, 0.3, 0.2))
				_disc(hp + f * 1.0, 1.7, maxf(lw * 1.4, ppm * 0.3), Color(0.4, 0.27, 0.17))
	_end()
