extends Node
## Footprints (view only; docs/design/art_pipeline.md "Footprints"): a boot print per man per stride and hoof prints behind
## horses, on the board near the camera. Two parts, both owned here:
##  * the PRINT RING: a capped ring (CAP entries, the oldest overwritten) of prints, four floats each (x m, y m, a code =
##    heading + 8 * (type + 4 * ground kind), the sim second it was made). Filled from the sim's soldier arrays, a tenth of
##    the men every sim tick (so each man once a sim second, the cost spread over the frames): the distance he walked since
##    his last print is the accumulator; a print every STRIDE_M, the feet alternating FOOT_OFF_M left and right of his path;
##    a rider's four hooves every HOOF_STRIDE_M. Nothing is done for a man who did not walk a stride.
##  * the DETAIL WINDOW: a SubViewport (WIN_PX square at WIN_PPM texels a metre, 2048 at 8 on High, 1024 at 4 on Low; RGBA8
##    because a SubViewport has no single-channel format: R the print's second modulo 256, G its darkness) covering a window
##    of WIN_M metres round the camera's look-at point. A stamp batch (once a sim second) draws the new prints into it as one
##    MultiMesh whose vertex shader reads the ring from a float texture (so a print costs four float writes on the CPU and
##    one instance on the GPU, no node, no per-print transform); the window re-stamps in full from the ring (cleared first)
##    when the look-at point leaves the middle quarter of its width, and every RESTAMP_S sim seconds (R wraps at 256 s).
##    The board shaders (game/prints.gdshaderinc, in terrain_body.gdshaderinc) fade a print by its age (FADE_S); nothing is
##    cleared or redrawn to fade.
## The sim is only read. A renderer-less (headless) run keeps no textures but counts (`total`, `by_type`, `window_stamps`,
## `restamps`) so the tests can follow a march.

const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const Quality := preload("res://game/quality.gd")
const BoardView := preload("res://game/board_view.gd")

const CAP := 49152            # ring entries
const RING_W := 256           # the ring texture's width (CAP / RING_W rows)
const STRIDE_M := 0.7         # a man's print every this far (the feet alternate: one stride, one print)
const FOOT_OFF_M := 0.22      # to the left / right of his path
const HOOF_STRIDE_M := 1.6    # a horse's four hoof prints per this far
const MAX_JUMP_M := 25.0      # a man that moved further since his last print (teleported) restarts
const SLICES := 10            # men are processed in this many slices a sim second
const FADE_S := 90.0          # a print is gone this many sim seconds after it was made
const RESTAMP_S := 100        # a full re-stamp this often (sim seconds), the window's time channel wraps at 256 s
const WIN_M := 256.0
const T_LEFT := 0
const T_RIGHT := 1
const T_HOOF := 2
const FOOT_MUL := 1.0         # (a print's darkness: the layer's GROUND_ROWS foot / hoof strength, times the weather)

var tl                         # the TrackLayer (ground kinds, the weather multiplier, the camera)
var sim
var px_per_m := 10.0
var viewer_side := -1
var ring := PackedFloat32Array()
var head := 0                  # next entry
var count := 0                 # entries valid (<= CAP)
var total := 0                 # prints made
var by_type := Vector3i.ZERO   # left, right, hoof
var window_stamps := 0         # stamp batches drawn into the window (headless: counted)
var restamps := 0              # full re-stamps
var win_org := Vector2.ZERO    # the window's top-left, metres
var win_px := 2048
var win_ppm := 8.0
var us_last := 0               # the last slice's cost (microseconds), benchmarks
var us_max := 0
var us_flush_max := 0
var vp: SubViewport = null
var _lx := PackedInt32Array()   # per man: sim position of his last print (x, y interleaved; x -1 none)
var _foot := PackedByteArray()
var _skip := PackedByteArray()  # per unit: 1 no prints (artillery crew, ship crew, hidden, destroyed)
var _cav := PackedByteArray()
var _slice := 0
var _last_tick := -1
var _flushed := 0               # `total` at the last stamp batch
var _restamp := true
var _last_restamp_sec := -1
var _last_restamp_ms := -10000
var _look := Vector2.ZERO
var _look_n := 0
var _mats: Array[ShaderMaterial] = []
var _mm_mat: ShaderMaterial = null
var _flush_frame := -1
var _batch_from := 0
var _batch_all := false
var _mmi: MultiMeshInstance2D = null
var _ring_tex: ImageTexture = null
var off := false               # the compatible 3D path: the stamp (a vertex texture read) cannot run, nothing is made or drawn
var _ring_img: Image = null
var _have_win := false


func setup(p_tl, p_sim, p_px_per_m: float, mat: ShaderMaterial, p_viewer_side := -1) -> void:
	tl = p_tl
	sim = p_sim
	px_per_m = p_px_per_m
	viewer_side = p_viewer_side
	ring.resize(CAP * 4)
	_lx.resize(sim.n * 2)
	_lx.fill(-1)
	_foot.resize(sim.n)
	_skip.resize(sim.n_units)
	_cav.resize(sim.n_units)
	if DisplayServer.get_name() == "headless":
		return
	var low: bool = Quality.is_low()
	win_px = 1024 if low else 2048
	win_ppm = float(win_px) / WIN_M
	vp = SubViewport.new()
	vp.size = Vector2i(win_px, win_px)
	vp.transparent_bg = true   # (cleared to 0, not the project's clear colour)
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.mesh = QuadMesh.new()
	mm.custom_aabb = AABB(Vector3(-1.0e5, -1.0e5, -1.0), Vector3(2.0e5, 2.0e5, 2.0))   # (the 2D canvas culls by it: the quads are placed by the shader)
	# (every instance's own transform is the identity: the vertex shader places the quad from the ring)
	var one := PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0])
	var buf := one
	for i in 16:
		buf.append_array(buf)
	buf = buf.slice(0, CAP * 8)
	mm.instance_count = CAP
	mm.buffer = buf.slice(0, CAP * 8)
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance2D.new()
	_mmi.multimesh = mm
	_mm_mat = ShaderMaterial.new()
	_mm_mat.shader = load("res://game/prints_stamp.gdshader")
	_mmi.material = _mm_mat
	vp.add_child(_mmi)
	add_child(vp)
	_ring_img = Image.create(RING_W, CAP / RING_W, false, Image.FORMAT_RGBAF)
	_ring_tex = ImageTexture.create_from_image(_ring_img)
	_mm_mat.set_shader_parameter("ring", _ring_tex)
	_mm_mat.set_shader_parameter("cap", CAP)
	_mm_mat.set_shader_parameter("grow", pow(8.0 / win_ppm, 0.6))
	_add_mat(mat)
	for m in _mats:
		m.set_shader_parameter("prints_tex", vp.get_texture())


func _add_mat(m: ShaderMaterial) -> void:
	if m != null and not _mats.has(m):
		_mats.append(m)
		if vp != null:
			m.set_shader_parameter("prints_tex", vp.get_texture())
			_apply_win(m)


func _apply_win(m: ShaderMaterial) -> void:
	m.set_shader_parameter("prints_win", Vector3(win_org.x, win_org.y, WIN_M if _have_win else 0.0))
	m.set_shader_parameter("prints_now", float(sim.tick) / BattleSim.TICKS_PER_SECOND)


## Called every frame by the TrackLayer: a slice of the men per sim tick, the batch landing once a sim second, the window
## following the camera.
func process(battle) -> void:
	if BoardView.v3d and BoardView.vtf_off:
		# The compatible 3D path (this device cannot read a texture in a vertex stage, which the stamp does): no prints, no cost.
		if not off:
			off = true
			if vp != null:
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var tick: int = sim.tick
	if tick < _last_tick:
		_last_tick = -1   # (a restore went back in time)
	if tick != _last_tick:
		_last_tick = tick
		if _slice == 0:
			_skips()
		var t0 := Time.get_ticks_usec()
		var a: int = _slice * sim.n / SLICES
		var b: int = (_slice + 1) * sim.n / SLICES
		_men(a, b)
		us_last = Time.get_ticks_usec() - t0
		us_max = maxi(us_max, us_last)
		_slice += 1
		if _slice >= SLICES:
			_slice = 0
			flush()
	if vp == null:
		return
	var v3 = battle.get("view3d") if battle != null else null
	if v3 != null and v3.get("terrain_mat") != null:
		_add_mat(v3.terrain_mat)
	_look_n += 1
	if battle != null and battle.camera != null and (_look_n % 6 == 1 or not _have_win):
		# (the ground point under the screen's centre in every view: the oblique and 3D views' Camera2D is not in ground px)
		battle.camera.force_update_scroll()
		_look = battle._screen_to_world(battle.get_viewport_rect().size * 0.5) / px_per_m
		var ctr := win_org + Vector2(WIN_M, WIN_M) * 0.5
		if not _have_win or maxf(absf(_look.x - ctr.x), absf(_look.y - ctr.y)) > WIN_M * 0.25:
			if Time.get_ticks_msec() - _last_restamp_ms > 250:
				_restamp = true
				if count > 0 or not _have_win:
					flush()


## Per-unit skip flags (once a sim second): who leaves no prints.
func _skips() -> void:
	for u in sim.n_units:
		var ty: int = sim.u_type[u]
		var cls: int = sim.t_cls[ty]
		var skip: bool = sim.u_state[u] >= BattleSim.U_DESTROYED or sim.u_alive[u] <= 0 or cls == UT.CLS_ART \
				or (sim.shp_on != 0 and sim.u_ship[u] >= 0)
		if not skip and viewer_side >= 0 and sim.hidden_from(u, viewer_side):
			skip = true
		_skip[u] = 1 if skip else 0
		_cav[u] = 1 if cls == UT.CLS_CAV else 0


## Men a..b-1: a print for every stride walked since the last.
func _men(a: int, b: int) -> void:
	var xs: PackedInt32Array = sim.pos_x
	var ys: PackedInt32Array = sim.pos_y
	var sts: PackedInt32Array = sim.state
	var uof: PackedInt32Array = sim.unit_of
	var M := float(BattleSim.M)
	var s_step := int(STRIDE_M * M)
	var s2 := s_step * s_step
	var jump2 := int(MAX_JUMP_M * M) * int(MAX_JUMP_M * M)
	var secs := float(sim.tick) / BattleSim.TICKS_PER_SECOND - 1.0
	for i in range(a, b):
		if sts[i] >= BattleSim.S_DEAD:
			continue
		var u: int = uof[i]
		if _skip[u] != 0:
			_lx[i * 2] = -1
			continue
		var x: int = xs[i]
		var y: int = ys[i]
		var lx: int = _lx[i * 2]
		if lx < 0:
			_lx[i * 2] = x
			_lx[i * 2 + 1] = y
			continue
		var dx: int = x - lx
		var ly: int = _lx[i * 2 + 1]
		var dy: int = y - ly
		var d2: int = dx * dx + dy * dy
		if _cav[u] != 0:
			if d2 < int(HOOF_STRIDE_M * M) * int(HOOF_STRIDE_M * M):
				continue
		elif d2 < s2:
			continue
		if d2 > jump2:
			_lx[i * 2] = x
			_lx[i * 2 + 1] = y
			continue
		var d := sqrt(float(d2))
		var ang := atan2(float(dy), float(dx))
		var ux := float(dx) / d
		var uy := float(dy) / d
		var kind: int = tl.kind_at_sim(x, y)
		if kind == tl.K_WATER:
			_lx[i * 2] = x
			_lx[i * 2 + 1] = y
			continue
		if _cav[u] != 0:
			var n := int(d / (HOOF_STRIDE_M * M))
			for k in n:
				var along := (float(k) + 0.5) * HOOF_STRIDE_M * M
				var cx := float(lx) + ux * along
				var cy := float(ly) + uy * along
				# (a walking gait's pattern: the near hooves lead, the far ones follow, staggered along and across)
				_hoof(cx, cy, ux, uy, 0.0, 0.3 * M, ang, kind, secs)
				_hoof(cx, cy, ux, uy, 0.38 * M, -0.3 * M, ang, kind, secs)
				_hoof(cx, cy, ux, uy, -0.85 * M, 0.3 * M, ang, kind, secs)
				_hoof(cx, cy, ux, uy, -0.47 * M, -0.3 * M, ang, kind, secs)
			var used := float(n) * HOOF_STRIDE_M * M / d
			_lx[i * 2] = lx + int(float(dx) * used)
			_lx[i * 2 + 1] = ly + int(float(dy) * used)
		else:
			var n2 := int(d / float(s_step))
			var f: int = _foot[i]
			var sd := FOOT_OFF_M * M
			for k in n2:
				var along := float(k + 1) * float(s_step)
				var jh := (head * 7919) % 13 - 6   # (a little scatter along and across, so a column is not a grid)
				along += float(jh) * 0.012 * M
				var side := (sd if f == 0 else -sd) + float((head * 104729) % 11 - 5) * 0.012 * M
				var o := head * 4
				ring[o] = (float(lx) + ux * along - uy * side) / M
				ring[o + 1] = (float(ly) + uy * along + ux * side) / M
				ring[o + 2] = ang + 8.0 * float(T_LEFT + f + 4 * kind)
				ring[o + 3] = secs
				head = head + 1 if head + 1 < CAP else 0
				f = 1 - f
			_foot[i] = f
			total += n2
			count = mini(count + n2, CAP)
			if f == 0:
				by_type.x += n2 / 2
				by_type.y += n2 / 2
			else:
				by_type.x += (n2 + 1) / 2
				by_type.y += n2 / 2
			var used2 := float(n2 * s_step) / d
			_lx[i * 2] = lx + int(float(dx) * used2)
			_lx[i * 2 + 1] = ly + int(float(dy) * used2)


func _hoof(cx: float, cy: float, ux: float, uy: float, al: float, sd: float, ang: float, kind: int, secs: float) -> void:
	var o := head * 4
	var M := float(BattleSim.M)
	var j := float((head * 7919) % 13 - 6) * 0.012 * M   # (a little scatter, so the pattern is not a grid)
	ring[o] = (cx + ux * (al + j) - uy * (sd - j)) / M
	ring[o + 1] = (cy + uy * (al + j) + ux * (sd - j)) / M
	ring[o + 2] = ang + 8.0 * float(T_HOOF + 4 * kind)
	ring[o + 3] = secs
	head = head + 1 if head + 1 < CAP else 0
	total += 1
	by_type.z += 1
	count = mini(count + 1, CAP)


## Every man now (tests; a sweep of the whole army in one go).
func sweep() -> void:
	_skips()
	_men(0, sim.n)


## The stamp batch: the prints made since the last batch (or, after a window move, the whole ring) are drawn into the window.
func flush() -> void:
	var t0 := Time.get_ticks_usec()
	var sec: int = sim.tick / BattleSim.TICKS_PER_SECOND
	if _last_restamp_sec >= 0 and sec - _last_restamp_sec >= RESTAMP_S:
		_restamp = true
	var fresh: int = total - _flushed
	if fresh <= 0 and not _restamp:
		return
	_flushed = total
	window_stamps += 1
	if vp == null:
		if _restamp:
			restamps += 1
			_restamp = false
			_last_restamp_sec = sec
		return
	# (two flushes in one frame share one render: the second must carry the first's prints, and its clear)
	var frame := Engine.get_process_frames()
	if frame == _flush_frame:
		fresh = total - _batch_from
	else:
		_batch_from = total - fresh
		_batch_all = false
	_flush_frame = frame
	var all := _restamp or fresh >= CAP or _batch_all
	_batch_all = all
	if all:
		restamps += 1
		_restamp = false
		_last_restamp_sec = sec
		_last_restamp_ms = Time.get_ticks_msec()
		var org := (_look - Vector2(WIN_M, WIN_M) * 0.5).snapped(Vector2.ONE)
		win_org = org
		_have_win = true
		vp.canvas_transform = Transform2D(Vector2(win_ppm, 0.0), Vector2(0.0, win_ppm), -org * win_ppm)
		fresh = count
	# (the ring to the texture: only the stamped part changed, but one upload of 0.8 MB is cheaper than the bookkeeping)
	_ring_img.set_data(RING_W, CAP / RING_W, false, Image.FORMAT_RGBAF, ring.to_byte_array())
	_ring_tex.update(_ring_img)
	var first: int = posmod(head - fresh, CAP)
	_mm_mat.set_shader_parameter("first", first)
	_mmi.multimesh.visible_instance_count = fresh
	_mm_mat.set_shader_parameter("now", float(sim.tick) / BattleSim.TICKS_PER_SECOND)
	var rows := PackedVector2Array()
	for k in 5:
		var r: Vector3 = (tl.GROUND_ROWS[k] as Vector3) * tl.weather_mul
		rows.append(Vector2(r.x, r.z))
	_mm_mat.set_shader_parameter("rows", rows)
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS if all else SubViewport.CLEAR_MODE_NEVER
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	for m in _mats:
		_apply_win(m)
	us_flush_max = maxi(us_flush_max, Time.get_ticks_usec() - t0)


func _process(_delta: float) -> void:
	# (the shaders' clock follows the sim tick every frame)
	for m in _mats:
		m.set_shader_parameter("prints_now", float(sim.tick) / BattleSim.TICKS_PER_SECOND)
