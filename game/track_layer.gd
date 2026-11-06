extends Node
## Tracks on the board (view only; docs/design/art_pipeline.md "Tracks on the board"): the ground-marks texture. One
## SubViewport per battle, RGBA8, about 2 px per metre (at most MAX_PX a side), cleared at the start and stamped once per
## sim second where men, riders, guns and wagons moved; a slow subtraction fades it (FADE_S seconds from full). The board
## shaders (terrain_body.gdshaderinc, so the top, oblique and 3D views alike) sample it and darken the ground:
##   R  foot wear (a column's worn path), G ruts (two lines behind guns, wagons, a siege tower; the furrow of a stone),
##   B  hoof churn (cavalry).
## Strength by ground kind is the one small table GROUND_ROWS below; `weather_mul` is the hook for the weather pass (snow
## and mud will scale or recolour the rows). The sim is only read: nothing here is hashed or fed back. A renderer-less
## (headless) run keeps no texture but counts its stamps (`stamps`) so the tests can follow a march.

const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")

const TEX_PPM := 2.0           # texels per metre (1 px per 0.5 m)
const MAX_PX := 2048           # the texture's longest side (a big field gets fewer texels per metre)
const FADE_PER_S := 0.9 / 255.0  # the fade a second (full strength gone in about 280 s; the marks read for about two minutes)
const MIN_MOVE_M := 1.0        # a unit or engine that moved less than this since its last stamp leaves none
const MAX_JUMP_M := 25.0       # ... and one that moved further (arrived, teleported) restarts its trail
const FURROW_M := 8.0          # a furrow's length when the sim gives no run
const FURROW_DELAY := 20       # ticks after a landing before its furrow is stamped (the longest run is 2 s)

## Ground kinds (_kind_at) and, for each, the stamp strength 0..1 per channel: foot, wheel, hoof. Roads and the town's
## beaten ground take the most, ploughland nearly as much, grass half (faint), woods little. Weather (snow, mud) scales
## the whole table through `weather_mul`.
enum { K_GRASS, K_ROAD, K_FIELD, K_WOODS, K_WATER }
const GROUND_ROWS := [
	Vector3(0.80, 0.80, 0.75),   # grass
	Vector3(1.00, 1.00, 0.95),   # road, street, plaza, settlement ground
	Vector3(0.95, 0.95, 0.90),   # ploughland
	Vector3(0.50, 0.50, 0.45),   # woods
	Vector3(0.0, 0.0, 0.0),      # water
]
static var weather_mul := Vector3.ONE   # (the weather pass: snow would set this above 1 and tint the shader's dark)

var sim
var px_per_m := 10.0
var viewer_side := -1
var vp: SubViewport = null
var stamps := 0                # stamps made (foot, hoof, wheel, furrow), tests
var passes := 0                # texture updates
var by_channel := Vector3i.ZERO   # foot, wheel, hoof stamps
var furrows := 0
var _sc := 1.0                 # texels per world px
var _size_px := Vector2.ONE    # the field in world px
var _decay: _Decay = null
var _draw: _Stamp = null
var _last_sec := -1
var _last_fx_tick := -1
var _flush_frame := -1
var _decay_acc := 0.0   # the fade owed (carried between passes)
var _pending := 0.0     # the fade to draw in the coming update
var _ulast := PackedInt32Array()   # per unit: the centroid at its last stamp (x, y; -1: none)
var _elast := PackedInt32Array()   # per engine
var _qlast := PackedInt32Array()   # per piece of equipment
var _verts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()


func setup(p_sim, p_px_per_m: float, mat: ShaderMaterial, p_viewer_side := -1) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	viewer_side = p_viewer_side
	_size_px = Vector2(sim.field_w, sim.field_h) / float(BattleSim.M) * px_per_m
	var fm := _size_px / px_per_m
	_sc = minf(TEX_PPM, float(MAX_PX) / maxf(fm.x, fm.y)) / px_per_m
	_ulast.resize(sim.n_units * 2)
	_ulast.fill(-1)
	_elast.resize(sim.n_eng * 2)
	_elast.fill(-1)
	if DisplayServer.get_name() == "headless":
		return
	vp = SubViewport.new()
	vp.size = Vector2i(maxi(int(_size_px.x * _sc), 1), maxi(int(_size_px.y * _sc), 1))
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE   # (the first update clears it to black: no marks)
	_decay = _Decay.new()
	_decay.size = _size_px
	vp.add_child(_decay)
	_draw = _Stamp.new()
	vp.add_child(_draw)
	add_child(vp)
	vp.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(_sc, _sc))
	if mat != null:
		mat.set_shader_parameter("marks_tex", vp.get_texture())
		mat.set_shader_parameter("marks_size_px", _size_px)


func _process(_delta: float) -> void:
	var sec: int = sim.tick / BattleSim.TICKS_PER_SECOND
	if sec == _last_sec:
		return
	if sec < _last_sec:
		_last_sec = -1
	stamp(maxi(sec - _last_sec, 1) if _last_sec >= 0 else 1)
	_last_sec = sec


## One stamping pass (once per sim second; tests call it by hand): the marks of what moved since the last, then a texture
## update that first subtracts `secs` seconds of fade.
func stamp(secs := 1) -> void:
	var frame := Engine.get_process_frames()
	if frame != _flush_frame:
		# (a new frame: the last update has drawn its list; two passes in one frame share one update and one list)
		_verts.clear()
		_cols.clear()
		_idx.clear()
		_pending = 0.0
	_units()
	_engines()
	_equipment()
	_furrows()
	passes += 1
	if vp == null:
		return
	_flush_frame = frame
	# (an 8-bit target takes whole steps: the fraction is carried to the next pass)
	_decay_acc += FADE_PER_S * secs
	var steps := floorf(_decay_acc * 255.0)
	_pending += steps / 255.0
	_decay.amount = clampf(_pending, 0.0, 1.0)
	_decay_acc -= steps / 255.0
	_decay.queue_redraw()
	_draw.set_mesh(_verts, _cols, _idx)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _hidden(u: int) -> bool:
	return viewer_side >= 0 and u >= 0 and sim.hidden_from(u, viewer_side)


func _row(p: Vector2) -> Vector3:
	# p in world px
	var k := _kind_at(p)
	return (GROUND_ROWS[k] as Vector3) * weather_mul


## The ground kind under world point p (px): the sim's 4 m vegetation cells.
func _kind_at(p: Vector2) -> int:
	if sim.map_on == 0 or sim.veg_w <= 0:
		return K_GRASS
	var cx := clampi(int(p.x / px_per_m / 4.0), 0, sim.veg_w - 1)
	var cy := clampi(int(p.y / px_per_m / 4.0), 0, sim.veg_h - 1)
	var b: int = sim.veg[cy * sim.veg_w + cx]
	if (b & MapGen.V_WATER) != 0:
		return K_WATER
	if (b & (MapGen.V_ROAD | MapGen.V_PLAZA | MapGen.V_URBAN)) != 0:
		return K_ROAD
	if (b & MapGen.V_FIELD) != 0:
		return K_FIELD
	if (b & MapGen.V_DENS) >= 2:
		return K_WOODS
	return K_GRASS


func _w(x: int, y: int) -> Vector2:
	return Vector2(x, y) / float(BattleSim.M) * px_per_m


func _units() -> void:
	for u in sim.n_units:
		if sim.u_state[u] >= BattleSim.U_DESTROYED or sim.u_alive[u] <= 0:
			continue
		var ty: int = sim.u_type[u]
		var cls: int = sim.t_cls[ty]
		if cls == UT.CLS_ART or (sim.shp_on != 0 and sim.u_ship[u] >= 0):
			continue   # (gun crews walk beside the engines, which leave the ruts; a ship's crew is aboard)
		var cx: int = sim.u_cx[u]
		var cy: int = sim.u_cy[u]
		var lx: int = _ulast[u * 2]
		var ly: int = _ulast[u * 2 + 1]
		if lx < 0:
			_ulast[u * 2] = cx
			_ulast[u * 2 + 1] = cy
			continue
		var a := _w(lx, ly)
		var b := _w(cx, cy)
		var d := (b - a).length() / px_per_m
		if d < MIN_MOVE_M:
			continue   # (not moved enough: the older point stays, so a slow walk still adds up)
		_ulast[u * 2] = cx
		_ulast[u * 2 + 1] = cy
		if d > MAX_JUMP_M or _hidden(u):
			continue
		var row := _row(b)
		var wm := clampf(float(sim.u_files[u] * UT.stat(ty, "file_sp")) / float(BattleSim.M), 2.0, 60.0)
		var hw := wm * 0.5 * px_per_m
		var d0 := 2.2 * px_per_m
		if cls == UT.CLS_CAV:
			_strip(a, b, hw, d0, Color(0, 0, row.z, 1))
			by_channel.z += 1
		else:
			_strip(a, b, hw, d0, Color(row.x, 0, 0, 1))
			by_channel.x += 1
		stamps += 1


## Wheeled ground: the guns (engines) and, on equipment, wagons, rams and siege towers: two ruts in G.
func _engines() -> void:
	if sim.n_eng <= 0:
		return
	if _elast.size() < sim.n_eng * 2:
		var n0 := _elast.size()
		_elast.resize(sim.n_eng * 2)
		for i in range(n0, _elast.size()):
			_elast[i] = -1
	for e in sim.n_eng:
		var x: int = sim.e_x[e]
		var y: int = sim.e_y[e]
		var lx: int = _elast[e * 2]
		var ly: int = _elast[e * 2 + 1]
		if sim.e_state[e] == BattleSim.E_WRECKED or sim.e_state[e] == BattleSim.E_RESERVE:
			continue
		if lx >= 0 and _moved(lx, ly, x, y):
			_ruts(_w(lx, ly), _w(x, y), 1.6, sim.e_unit[e])
		if lx < 0 or _moved(lx, ly, x, y):
			_elast[e * 2] = x
			_elast[e * 2 + 1] = y


func _equipment() -> void:
	if sim.n_eq <= 0:
		return
	if _qlast.size() < sim.n_eq * 2:
		var n0 := _qlast.size()
		_qlast.resize(sim.n_eq * 2)
		for i in range(n0, _qlast.size()):
			_qlast[i] = -1
	for q in sim.n_eq:
		var k: int = sim.q_kind[q]
		if k != BattleSim.EQ_WAGON and k != BattleSim.EQ_TOWER and k != BattleSim.EQ_RAM:
			continue
		var x: int = sim.q_x[q]
		var y: int = sim.q_y[q]
		var lx: int = _qlast[q * 2]
		var ly: int = _qlast[q * 2 + 1]
		if lx >= 0 and _moved(lx, ly, x, y):
			_ruts(_w(lx, ly), _w(x, y), 1.8 if k == BattleSim.EQ_WAGON else 3.0, sim.q_unit[q])
		if lx < 0 or _moved(lx, ly, x, y):
			_qlast[q * 2] = x
			_qlast[q * 2 + 1] = y


func _moved(lx: int, ly: int, x: int, y: int) -> bool:
	var dm := Vector2(x - lx, y - ly).length() / float(BattleSim.M)
	return dm >= MIN_MOVE_M and dm <= MAX_JUMP_M


func _ruts(a: Vector2, b: Vector2, gauge_m: float, unit: int) -> void:
	if unit >= 0 and _hidden(unit):
		return
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x) * gauge_m * px_per_m * 0.5
	var g: float = _row(b).y
	if g <= 0.0:
		return
	for s in [-1.0, 1.0]:
		_strip(a + side * s, b + side * s, 0.32 * px_per_m, 2.0 * px_per_m, Color(0, g, 0, 1))
	by_channel.y += 1
	stamps += 1


## A stone's (ball's) furrow, stamped once the run is over (FURROW_DELAY ticks after it came down, the longest run): along
## its flight from where it first ran on the ground (a ball's first 40 % is its bounce) for the sim's own run (`fx_r`), and
## a scuff where it landed. Strikes on a work leave none.
func _furrows() -> void:
	var newest := _last_fx_tick
	var has_k: bool = sim.fx_k.size() == sim.fx_t.size()
	for k in sim.fx_t.size():
		var t: int = sim.fx_t[k]
		if t <= _last_fx_tick or t < 0 or t > sim.tick - FURROW_DELAY:
			continue
		newest = maxi(newest, t)
		var kind: int = sim.fx_k[k] if has_k else BattleSim.FXK_STONE
		if kind == BattleSim.FXK_STRIKE or kind == BattleSim.FXK_BALL_STRIKE:
			continue
		var p := _w(sim.fx_x[k], sim.fx_y[k])
		var dir := Vector2(sim.fx_dx[k], sim.fx_dy[k]) / 4096.0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var row := _row(p)
		if row.y <= 0.0:
			continue
		var run_m: float = float(sim.fx_r[k]) / float(BattleSim.M) if has_k else FURROW_M
		var hop_m := run_m * 0.4 if kind == BattleSim.FXK_BALL and run_m > 1.25 else 0.0
		if run_m - hop_m > 0.5:
			_strip(p + dir * hop_m * px_per_m, p + dir * run_m * px_per_m, 0.5 * px_per_m, 0.4 * px_per_m, Color(0, minf(row.y * 1.2, 1.0), 0, 1))
		_strip(p - dir * px_per_m, p + dir * px_per_m, 1.6 * px_per_m, 1.0 * px_per_m, Color(minf(row.x * 0.9, 1.0), 0, 0, 1))
		furrows += 1
		stamps += 1
	_last_fx_tick = newest


## A soft band from a to b (world px), `hw` the half-width, `d0` the ramp length: the strength `col` rises over a..a+d and
## falls over b..b+d (d at most the band's length), so the next second's band (which starts at this one's end) adds up to an
## even strength along a trail whatever the speed. Sides ramp to 0 over the outer part of the half-width.
func _strip(a: Vector2, b: Vector2, hw: float, d0: float, col: Color) -> void:
	var dir := b - a
	var seg := dir.length()
	if seg < 0.001:
		return
	dir /= seg
	var d := minf(d0, seg)
	var nrm := Vector2(-dir.y, dir.x)
	var along := [a, a + dir * d, b, b + dir * d]
	var ak := [0.0, 1.0, 1.0, 0.0]
	var lat := [-1.0, -0.45, 0.45, 1.0]
	var lk := [0.0, 1.0, 1.0, 0.0]
	var base := _verts.size()
	for i in 4:
		for j in 4:
			_verts.append(along[i] + nrm * (hw * lat[j]))
			var s: float = ak[i] * lk[j]
			_cols.append(Color(col.r * s, col.g * s, col.b * s, 1.0))
	for i in 3:
		for j in 3:
			var q := base + i * 4 + j
			_idx.append_array(PackedInt32Array([q, q + 1, q + 4, q + 1, q + 5, q + 4]))


## The fade: subtract `amount` from every channel (blend_sub), then the stamps are added on top.
class _Decay extends Node2D:
	var size := Vector2.ONE
	var amount := 0.0

	func _init() -> void:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nrender_mode blend_sub;\nvoid fragment() { COLOR = vec4(COLOR.rgb, 1.0); }\n"
		var m := ShaderMaterial.new()
		m.shader = sh
		material = m

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(amount, amount, amount, 1.0))


class _Stamp extends Node2D:
	var _mesh: ArrayMesh = null

	func _init() -> void:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nrender_mode blend_add;\nvoid fragment() { COLOR = vec4(COLOR.rgb, 1.0); }\n"
		var m := ShaderMaterial.new()
		m.shader = sh
		material = m

	func set_mesh(v: PackedVector2Array, c: PackedColorArray, i: PackedInt32Array) -> void:
		_mesh = null
		if not v.is_empty():
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = v
			arr[Mesh.ARRAY_COLOR] = c
			arr[Mesh.ARRAY_INDEX] = i
			_mesh = ArrayMesh.new()
			_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		queue_redraw()

	func _draw() -> void:
		if _mesh != null:
			draw_mesh(_mesh, null)
