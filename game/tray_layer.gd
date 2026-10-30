extends Node2D
## Movement trays (tabletop pass 1, docs/design/art_pipeline.md "Pass 1, trays
## and bases"): a thin card tray under every visible unit's formation, drawn
## between the works and the men. Dark card edge, a faint lighter bevel inside,
## a translucent fill so the ground reads through; it follows the formation
## each frame (the anchor and facing are interpolated between ticks like the
## men), turns with the facing and shrinks with the alive count as the
## footprint does. A routed unit's tray is lifted off (not drawn) until it
## rallies; an enemy we do not see has none. `quad(u)` is also what the
## overlay puts the standard and the tokens on. View only: reads the sim.

const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const SHADER := preload("res://game/tray.gdshader")
const BoardView := preload("res://game/board_view.gd")
const M := 1024.0
const MARGIN_M := 0.6          # card beyond the outermost bases, metres
const JUMP_PX := 14.0          # a move this big in a tick is a placement, not a walk: no interpolation

var sim
var px_per_m := 10.0
var zoom := 1.0
var player_side := 0
var soldiers   # SoldierLayer (the interpolation, set_alpha)
var _tick := -1
var _lx := PackedInt32Array()   # anchor at the last frame
var _ly := PackedInt32Array()
var _lf := PackedInt32Array()
var _px := PackedInt32Array()   # anchor one tick before
var _py := PackedInt32Array()
var _pf := PackedInt32Array()
var draw_us := 0
var _mm: MultiMesh
var _mat: ShaderMaterial
## Per unit, this frame: its tray's four corners (see quad), or an empty array when it has none or is far off screen.
var quads: Array = []
var _fsp := PackedFloat32Array()   # per unit: file / rank spacing (units of 1/1024 m)
var _rsp := PackedFloat32Array()


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	_lx = sim.u_ax.duplicate()
	_ly = sim.u_ay.duplicate()
	_lf = sim.u_face.duplicate()
	_px = _lx.duplicate()
	_py = _ly.duplicate()
	_pf = _lf.duplicate()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mm.mesh = mesh
	_mm.instance_count = maxi(sim.n_units, 1)
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3(-1000.0, -1000.0, -1.0), Vector3(px_per_m * sim.field_w / M + 2000.0, px_per_m * sim.field_h / M + 2000.0, 2.0))
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	BoardView.apply(_mat)
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = _mm
	mmi.material = _mat
	add_child(mmi)
	_fsp.resize(sim.n_units)
	_rsp.resize(sim.n_units)
	for u in sim.n_units:
		_fsp[u] = UT.stat(sim.u_type[u], "file_sp")
		_rsp[u] = UT.stat(sim.u_type[u], "rank_sp")


## The oblique view: how far (board px) a unit standing on a wall walk is lifted by it (0 on the ground and in the top view):
## its tray, standard, tokens and marker go up with the men.
static func wall_lift(p_sim, u: int) -> float:
	if not BoardView.oblique or p_sim.u_wall[u] <= 0:
		return 0.0
	return float(p_sim.wall_h) / 1024.0 * BoardView.px_per_m * BoardView.OBLIQUE_SIN


func _process(_d: float) -> void:
	if sim == null:
		return
	if sim.tick != _tick:
		_tick = sim.tick
		_px = _lx.duplicate()
		_py = _ly.duplicate()
		_pf = _lf.duplicate()
	_lx = sim.u_ax.duplicate()
	_ly = sim.u_ay.duplicate()
	_lf = sim.u_face.duplicate()
	var t0 := Time.get_ticks_usec()
	var ct := get_canvas_transform()
	var vr := BoardView.world_rect(Rect2(ct.affine_inverse() * Vector2.ZERO, get_viewport_rect().size / ct.get_scale())).grow(px_per_m * 100.0)
	var k := px_per_m / M
	quads.resize(sim.n_units)
	for u in sim.n_units:
		if shows(u) and vr.has_point(Vector2(_lx[u], _ly[u]) * k):
			quads[u] = quad(u)
		else:
			quads[u] = PackedVector2Array()
	var n := 0
	for u in sim.n_units:
		var q: PackedVector2Array = quads[u]
		if q.is_empty():
			continue
		var ex := q[1] - q[0]
		var ey := q[3] - q[0]
		_mm.set_instance_transform_2d(n, Transform2D(ex, ey, (q[0] + q[2]) * 0.5))
		_mm.set_instance_custom_data(n, Color(ex.length(), ey.length(), wall_lift(sim, u), 0.0))
		n += 1
	_mm.visible_instance_count = n
	_mat.set_shader_parameter("w", 1.0 / zoom)
	draw_us = Time.get_ticks_usec() - t0


## True when unit u has a tray (and a standard) to show: on the field, not routed, not an enemy we do not see.
func shows(u: int) -> bool:
	if sim.u_state[u] != BattleSim.U_READY:
		return false
	if (sim.ch_on != 0 or sim.vis_on != 0) and sim.hidden_from(u, player_side):
		return false
	return sim.u_alive[u] > 0


## The tray of unit u as its four corners in world pixels: front left, front right, rear right, rear left (the unit's own
## left and right), the anchor and facing interpolated like the men.
func quad(u: int) -> PackedVector2Array:
	var k := px_per_m / M
	var a: float = 1.0 if soldiers == null or sim.phase == BattleSim.PHASE_DEPLOY else soldiers.alpha
	var x := float(_lx[u])
	var y := float(_ly[u])
	var f := float(_lf[u])
	if a < 1.0:
		var dx := float(_px[u]) - x
		var dy := float(_py[u]) - y
		if sqrt(dx * dx + dy * dy) * k < JUMP_PX:
			x += dx * (1.0 - a)
			y += dy * (1.0 - a)
			var df := fposmod(float(_pf[u]) - f + 512.0, 1024.0) - 512.0
			f += df * (1.0 - a)
	var alive: int = sim.u_alive[u]
	var files := clampi(sim.u_files[u], 1, maxi(alive, 1))
	var ranks := (alive + files - 1) / files
	var ang := f * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var mg := px_per_m * MARGIN_M
	var hw := (files - 1) * _fsp[u] * 0.5 * k + mg
	var depth := (ranks - 1) * _rsp[u] * k + 2.0 * mg
	var front := Vector2(x, y) * k + fwd * mg
	return PackedVector2Array([front - right * hw, front + right * hw, front + right * hw - fwd * depth,
		front - right * hw - fwd * depth])
