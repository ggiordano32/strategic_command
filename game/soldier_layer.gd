extends Node2D
## Renders all soldiers with two MultiMeshInstance2D nodes (corpses below,
## living above) that share one MultiMesh, and missiles in flight with one
## more MultiMesh. Artillery engines are extra instances of the soldier
## MultiMesh (after the soldiers, state 6 = working, 7 = wrecked or
## abandoned), so they cost no extra draw call. Per tick the sim's packed
## int arrays reach the GPU with native calls only, by one of two paths:
##
## - texture (the default, cheapest): the arrays are copied as raw bytes
##   into a data texture that the vertex shaders read (soldiers.gdshader,
##   projectiles.gdshader);
## - CPU-fed (the compatible fallback): the arrays are converted to floats
##   and interleaved into the MultiMesh buffers, one bulk upload per tick
##   (soldiers_cpu.gdshader, projectiles_cpu.gdshader), for devices whose
##   WebGL draws nothing from a texture read in the vertex stage (Chrome on
##   an Adreno 650 tablet, 2026-10-08).
##
## Both draw the same pixels (see soldiers.gdshaderinc). The battle's
## self-check (`_probe`) switches to the CPU-fed path when the texture path
## draws nothing and remembers it in user://settings.cfg [video] soldiers.

const SHADER := preload("res://game/soldiers.gdshader")
const PR_SHADER := preload("res://game/projectiles.gdshader")
const SHADER_CPU := preload("res://game/soldiers_cpu.gdshader")
const PR_SHADER_CPU := preload("res://game/projectiles_cpu.gdshader")
const UT := preload("res://sim/unit_types.gd")
const TEX_W := 1024
const BLOCKS := 8
const PR_BLOCKS := 8
## CPU-fed MultiMesh buffer: floats per instance (2D transform 8, custom 4)
## and where each field goes (the shaders read them through MODEL_MATRIX:
## [3].xy = floats 3, 7; [0].xy = 0, 4; [1].xy = 1, 5; INSTANCE_CUSTOM = 8-11).
const STRIDE := 12
const C_CUR_X := 3
const C_CUR_Y := 7
const C_PREV_X := 0
const C_PREV_Y := 4
const C_A := 1     # facing (soldiers), t0 (missiles)
const C_B := 5     # state (soldiers), t1 (missiles)
const C_SPRITE := 8
const C_FLAGS := 9
const PR_STEP := 256

const SETTINGS := "user://settings.cfg"

## Sprite cells (see soldiers.gdshaderinc): local box x -1.6..4.4 m forward,
## y -1.25..1.25 m to the right, ATLAS_PX_PER_M pixels per metre.
const SPRITES := 9
const CELL_X0 := -1.6
const CELL_W := 6.0
const CELL_Y0 := -1.25
const CELL_H := 2.5
const ATLAS_PX_PER_M := 24
## Quad drawn per sprite: xmin, xmax, ymin, ymax (metres). The CPU-fed
## shader has the same table as constants (soldiers.gdshaderinc sprite_rect).
const SPR_RECT: Array[Vector4] = [
	Vector4(-0.6, 0.85, -0.6, 0.6),   # 0 sword and shield
	Vector4(-0.6, 2.35, -0.6, 0.6),   # 1 spear
	Vector4(-0.75, 4.45, -0.6, 0.6),  # 2 pike
	Vector4(-0.6, 0.75, -0.62, 0.62), # 3 bow
	Vector4(-0.6, 1.5, -0.62, 0.62),  # 4 javelins
	Vector4(-1.45, 1.7, -0.62, 0.62), # 5 horse and rider
	Vector4(-0.55, 0.6, -0.55, 0.55), # 6 artillery crew
	Vector4(-1.2, 1.45, -1.05, 1.05), # 7 bolt thrower (engine)
	Vector4(-1.6, 1.75, -1.0, 1.0),   # 8 stone thrower (engine)
]
const ENGINE_OK := 6
const ENGINE_OUT := 7

## Self-check (probe): PROBE_FRAMES frames into a battle (and again after a
## switch of path), only the soldier layers are drawn into a small offscreen
## viewport around the biggest unit and the drawn pixels are counted;
## `probed` reports them with the path ("gpu" texture or "cpu" fed;
## telemetry, console "SOLDIER_PROBE", server/cmd/webcheck). Zero pixels
## with men alive means this device draws no soldiers on that path.
signal probed(drawn: int, men: int, path: String)
const PROBE_LAYER := 1 << 19   # visibility layer only the probe viewport draws
const PROBE_PX := 128          # probe viewport size (px), 2 px a metre
const PROBE_FRAMES := 30

## Built once per page session (procedural, ~30k pixels).
static var _atlas_cache: ImageTexture = null

var px_per_m: float = 10.0
var sim  # BattleSim (untyped to keep the view decoupled)
## Units drawn highlighted (selection).
var selected_units: Dictionary = {}
## The path in use: false = texture, true = CPU-fed (see set_cpu_fed).
var cpu_fed := false
## Switch to the CPU-fed path (and remember it) when the probe sees no
## soldiers drawn; off when --soldiers= forces a path.
var auto_fallback := true

var _layers: Array[MultiMeshInstance2D] = []
var _pr_layer: MultiMeshInstance2D
var _materials: Array[ShaderMaterial] = []   # the soldier materials in use
var _pr_mat: ShaderMaterial                  # the missile material in use
var _atlas: ImageTexture
var _aabb: AABB
var _n_inst := 0
var _pr_cap := 0
var _flags := PackedInt32Array()
var _unit_sprite := PackedInt32Array()
var _unit_engine := PackedInt32Array()  # engine sprite per unit (0 = none)
var _e_state := PackedInt32Array()
var _pr_flags := PackedInt32Array()
var _pr_was_active := true
var _probe_frames := 0
var _probe_fail := false

# Texture path (built on first use).
var _gpu_built := false
var _mm: MultiMesh
var _gpu_mats: Array[ShaderMaterial] = []
var _image: Image
var _tex: ImageTexture
var _rows: int = 1
var _pr_mm: MultiMesh
var _pr_gpu_mat: ShaderMaterial
var _pr_image: Image
var _pr_tex: ImageTexture
var _pr_rows: int = 1

# CPU-fed path (built on first use): the MultiMesh buffers as images
# (FORMAT_RF, STRIDE floats wide, one row per instance) that whole columns
# are blitted into, and a one-column scratch image.
var _cpu_built := false
var _mm_cpu: MultiMesh
var _cpu_mats: Array[ShaderMaterial] = []
var _cbuf: Image
var _ccol: Image
var _runs := PackedInt32Array()   # [first instance, count, unit] per run of one unit
var _pr_mm_cpu: MultiMesh
var _pr_cpu_mat: ShaderMaterial
var _pr_cbuf: Image
var _pr_ccol: Image
var _pr_n := 0                            # missile slots in the MultiMesh
var _pr_code := PackedFloat32Array()
var _pr_unit_seen := PackedInt32Array()
var _pr_t0_seen := PackedInt32Array()
var _pr_t1_seen := PackedInt32Array()
var _pr_free_tail := PackedInt32Array()   # cap x -1 (t1 of free slots)
## Microseconds the last upload() took (both paths; for benchmarks).
var upload_us := 0


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	_n_inst = sim.n + sim.n_eng
	_pr_cap = sim.pr_t1.size()
	_flags.resize(sim.n_units)
	_unit_sprite.resize(sim.n_units)
	_unit_engine.resize(sim.n_units)
	_e_state.resize(sim.n_eng)
	_pr_flags.resize(sim.n_units)
	for u in sim.n_units:
		var ty: int = sim.u_type[u]
		_unit_sprite[u] = UT.stat(ty, "sprite")
		var kind := UT.stat(ty, "m_kind") if UT.cls(ty) == UT.CLS_ART else 0
		_unit_engine[u] = 7 if kind == 1 else (8 if kind == 2 else 0)
		# Missiles: bit 0 side, bits 1-2: 0 arrow, 1 javelin, 2 bolt, 3 stone.
		var mk := 0 if UT.stat(ty, "m_arc") != 0 else 1
		if UT.cls(ty) == UT.CLS_ART:
			mk = 2 if UT.stat(ty, "m_kind") == 1 else 3
		_pr_flags[u] = (sim.u_side[u] & 1) | (mk << 1)

	var fw: float = sim.field_w / 1024.0 * px_per_m
	var fh: float = sim.field_h / 1024.0 * px_per_m
	var pad := px_per_m * 6.0
	# The shaders place everything, so give the MultiMeshes bounds covering
	# the whole field to avoid culling.
	_aabb = AABB(Vector3(-pad, -pad, -1.0), Vector3(fw + 2.0 * pad, fh + 2.0 * pad, 2.0))
	_atlas = _make_atlas()
	for pass_id in 2:
		var mmi := MultiMeshInstance2D.new()
		mmi.texture = _atlas
		add_child(mmi)
		_layers.append(mmi)
	_pr_layer = MultiMeshInstance2D.new()
	add_child(_pr_layer)

	var forced := forced_path()
	auto_fallback = forced == ""
	# Testing aid: the texture path's probe reports nothing drawn, as on the
	# devices it fails on (exercises the automatic switch).
	_probe_fail = "--soldier-probe-fail" in _launch_args() or "--soldier-probe-fail=1" in _launch_args()
	set_cpu_fed(forced == "cpu" or (forced == "" and load_pref() == "cpu"))


## Use the CPU-fed path (true) or the texture path (false) from now on.
func set_cpu_fed(on: bool) -> void:
	cpu_fed = on
	if on:
		_build_cpu()
	else:
		_build_gpu()
	_materials = _cpu_mats if on else _gpu_mats
	for k in 2:
		_layers[k].multimesh = _mm_cpu if on else _mm
		_layers[k].material = _materials[k]
	_pr_layer.multimesh = _pr_mm_cpu if on else _pr_mm
	_pr_mat = _pr_cpu_mat if on else _pr_gpu_mat
	_pr_layer.material = _pr_mat
	_pr_was_active = true
	_pr_t0_seen = PackedInt32Array()  # upload the missiles again
	if sim != null:
		upload()
		set_alpha(1.0)


func _soldier_material(shader: Shader, pass_id: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("px_per_unit", px_per_m / 1024.0)
	mat.set_shader_parameter("layer_pass", pass_id)
	return mat


func _missile_material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("px_per_unit", px_per_m / 1024.0)
	return mat


func _build_gpu() -> void:
	if _gpu_built:
		return
	_gpu_built = true
	_rows = maxi(1, (maxi(_n_inst, sim.n_units) + TEX_W - 1) / TEX_W)
	var bytes := PackedByteArray()
	bytes.resize(BLOCKS * _rows * TEX_W * 4)
	_image = Image.create_from_data(TEX_W, BLOCKS * _rows, false, Image.FORMAT_RGBA8, bytes)
	_tex = ImageTexture.create_from_image(_image)
	_mm = _index_multimesh(_n_inst)
	var rects: Array = []
	for r in SPR_RECT:
		rects.append(r)
	for pass_id in 2:
		var mat := _soldier_material(SHADER, pass_id)
		mat.set_shader_parameter("data_tex", _tex)
		mat.set_shader_parameter("rows_per_block", _rows)
		mat.set_shader_parameter("tex_width", TEX_W)
		mat.set_shader_parameter("spr_rect", rects)
		_gpu_mats.append(mat)
	# Projectiles: one instance per sim projectile slot.
	_pr_rows = maxi(1, (maxi(_pr_cap, sim.n_units) + TEX_W - 1) / TEX_W)
	var pbytes := PackedByteArray()
	pbytes.resize(PR_BLOCKS * _pr_rows * TEX_W * 4)
	_pr_image = Image.create_from_data(TEX_W, PR_BLOCKS * _pr_rows, false, Image.FORMAT_RGBA8, pbytes)
	_pr_tex = ImageTexture.create_from_image(_pr_image)
	_pr_mm = _index_multimesh(_pr_cap)
	_pr_gpu_mat = _missile_material(PR_SHADER)
	_pr_gpu_mat.set_shader_parameter("data_tex", _pr_tex)
	_pr_gpu_mat.set_shader_parameter("rows_per_block", _pr_rows)
	_pr_gpu_mat.set_shader_parameter("tex_width", TEX_W)


## A MultiMesh of `count` unit quads at identity carrying their index in
## INSTANCE_CUSTOM (texture path).
func _index_multimesh(count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _make_quad()
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
		mm.set_instance_custom_data(i, _index_data(i))
	mm.custom_aabb = _aabb
	return mm


func _build_cpu() -> void:
	if _cpu_built:
		return
	_cpu_built = true
	_mm_cpu = _cpu_multimesh(_n_inst)
	_cbuf = Image.create(STRIDE, maxi(_n_inst, 1), false, Image.FORMAT_RF)
	_ccol = Image.create(1, maxi(_n_inst, 1), false, Image.FORMAT_RF)
	# Runs of consecutive instances of one unit (soldiers, then engines):
	# the per-unit columns are filled a run at a time. unit_of / e_unit never
	# change after the sim's setup.
	_runs.clear()
	var units: PackedInt32Array = sim.unit_of + sim.e_unit
	var i := 0
	while i < _n_inst:
		var j := i + 1
		while j < _n_inst and units[j] == units[i]:
			j += 1
		_runs.append_array(PackedInt32Array([i, j - i, units[i]]))
		i = j
	# Sprites never change: soldiers their unit's, engines the engine's.
	for r in range(0, _runs.size(), 3):
		var u := _runs[r + 2]
		var spr := _unit_sprite[u] if _runs[r] < sim.n else _unit_engine[u]
		_cbuf.fill_rect(Rect2i(C_SPRITE, _runs[r], 1, _runs[r + 1]), Color(float(spr), 0.0, 0.0))
	for pass_id in 2:
		_cpu_mats.append(_soldier_material(SHADER_CPU, pass_id))
	_pr_mm_cpu = _cpu_multimesh(0)
	_pr_n = 0
	_pr_free_tail.resize(_pr_cap)
	_pr_free_tail.fill(-1)
	_pr_cpu_mat = _missile_material(PR_SHADER_CPU)


func _cpu_multimesh(count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _make_quad()
	mm.instance_count = count
	mm.custom_aabb = _aabb
	return mm


func _process(_delta: float) -> void:
	if _probe_frames < 0 or sim == null:
		return
	_probe_frames += 1
	if _probe_frames >= PROBE_FRAMES:
		_probe_frames = -1
		if DisplayServer.get_name() != "headless":
			_probe()


func _probe() -> void:
	# The biggest unit on the field, framed at 2 px a metre.
	var best := -1
	for u in sim.n_units:
		if sim.u_alive[u] > 0 and (best < 0 or sim.u_alive[u] > sim.u_alive[best]):
			best = u
	if best < 0:
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(PROBE_PX, PROBE_PX)
	vp.transparent_bg = true
	vp.world_2d = get_viewport().world_2d
	vp.canvas_cull_mask = PROBE_LAYER
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# The soldier layers and every canvas item above them carry the probe's
	# layer (a hidden parent hides its children in a viewport too); nothing
	# else does, so the probe sees soldiers on a transparent background.
	var n: Node = self
	while n is CanvasItem:
		(n as CanvasItem).visibility_layer |= PROBE_LAYER
		n = n.get_parent()
	for mmi in _layers:
		mmi.visibility_layer |= PROBE_LAYER
	add_child(vp)
	var k := 2.0 / px_per_m
	var c := Vector2(sim.u_cx[best], sim.u_cy[best]) / 1024.0 * px_per_m
	vp.canvas_transform = Transform2D(0.0, Vector2(k, k), 0.0, Vector2(PROBE_PX, PROBE_PX) * 0.5 - c * k)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var drawn := 0
	var img := vp.get_texture().get_image()
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
		var px := img.get_data()
		for i in range(3, px.size(), 4):
			if px[i] > 64:
				drawn += 1
	vp.queue_free()
	if _probe_fail and not cpu_fed:
		drawn = 0
	var men := int(sim.u_alive[best])
	probed.emit(drawn, men, "cpu" if cpu_fed else "gpu")
	if drawn == 0 and men > 0 and not cpu_fed and auto_fallback:
		# This device draws nothing from the texture path: switch now, for
		# later battles too, and check the fallback the same way.
		set_cpu_fed(true)
		save_pref("cpu")
		_probe_frames = 0


## Copy the sim arrays to the GPU (the path in use). Call once after each tick.
func upload() -> void:
	var t0 := Time.get_ticks_usec()
	var nu: int = sim.n_units
	var tick: int = sim.tick
	for u in nu:
		var under_fire := 4 if tick - sim.u_hit_t[u] < 10 else 0
		_flags[u] = (sim.u_side[u] & 1) | (2 if selected_units.has(u) else 0) | under_fire
	# Engines follow the soldiers in every array.
	var xs: PackedInt32Array = sim.pos_x
	var ys: PackedInt32Array = sim.pos_y
	var pxs: PackedInt32Array = sim.prev_x
	var pys: PackedInt32Array = sim.prev_y
	var fs: PackedInt32Array = sim.facing
	var sts: PackedInt32Array = sim.state
	if sim.n_eng > 0:
		for e in sim.n_eng:
			_e_state[e] = ENGINE_OK if sim.e_state[e] == 0 else ENGINE_OUT
		xs = xs + sim.e_x
		ys = ys + sim.e_y
		pxs = pxs + sim.e_px
		pys = pys + sim.e_py
		fs = fs + sim.e_face
		sts = sts + _e_state
	var active: bool = sim.pr_count > 0
	var missiles := active or _pr_was_active  # skip while nothing flies (and nothing flew)
	_pr_was_active = active
	if cpu_fed:
		_upload_cpu(xs, ys, pxs, pys, fs, sts, missiles)
	else:
		_upload_gpu(xs, ys, pxs, pys, fs, sts, missiles)
	upload_us = Time.get_ticks_usec() - t0


func _upload_gpu(xs: PackedInt32Array, ys: PackedInt32Array, pxs: PackedInt32Array, pys: PackedInt32Array,
		fs: PackedInt32Array, sts: PackedInt32Array, missiles: bool) -> void:
	var gflags := _flags.duplicate()
	for u in sim.n_units:
		gflags[u] |= (_unit_sprite[u] << 4) | (_unit_engine[u] << 8)
	var block := _rows * TEX_W * 4
	_image.set_data(TEX_W, BLOCKS * _rows, false, Image.FORMAT_RGBA8, _pack([xs, ys, pxs, pys, fs, sts,
		sim.unit_of + sim.e_unit if sim.n_eng > 0 else sim.unit_of, gflags], block))
	_tex.update(_image)
	if missiles:
		var pblock := _pr_rows * TEX_W * 4
		_pr_image.set_data(TEX_W, PR_BLOCKS * _pr_rows, false, Image.FORMAT_RGBA8, _pack([
			sim.pr_sx, sim.pr_sy, sim.pr_x, sim.pr_y, sim.pr_t0, sim.pr_t1, sim.pr_unit,
			_pr_flags], pblock))
		_pr_tex.update(_pr_image)


func _upload_cpu(xs: PackedInt32Array, ys: PackedInt32Array, pxs: PackedInt32Array, pys: PackedInt32Array,
		fs: PackedInt32Array, sts: PackedInt32Array, missiles: bool) -> void:
	if _n_inst > 0:
		_column(_cbuf, _ccol, C_CUR_X, xs, _n_inst)
		_column(_cbuf, _ccol, C_CUR_Y, ys, _n_inst)
		_column(_cbuf, _ccol, C_PREV_X, pxs, _n_inst)
		_column(_cbuf, _ccol, C_PREV_Y, pys, _n_inst)
		_column(_cbuf, _ccol, C_A, fs, _n_inst)
		_column(_cbuf, _ccol, C_B, sts, _n_inst)
		for r in range(0, _runs.size(), 3):
			_cbuf.fill_rect(Rect2i(C_FLAGS, _runs[r], 1, _runs[r + 1]), Color(float(_flags[_runs[r + 2]]), 0.0, 0.0))
		_mm_cpu.buffer = _cbuf.get_data().to_float32_array()
	# Missiles: a slot's data is fixed from firing to landing (the shader
	# interpolates), so upload only when a missile was fired or landed.
	if missiles and _pr_cap > 0 and (sim.pr_t0 != _pr_t0_seen or sim.pr_t1 != _pr_t1_seen):
		_pr_t0_seen = sim.pr_t0.duplicate()
		_pr_t1_seen = sim.pr_t1.duplicate()
		_pr_fit()
		var m := _pr_n
		if m == 0:
			return
		_column(_pr_cbuf, _pr_ccol, C_CUR_X, sim.pr_sx, m)
		_column(_pr_cbuf, _pr_ccol, C_CUR_Y, sim.pr_sy, m)
		_column(_pr_cbuf, _pr_ccol, C_PREV_X, sim.pr_x, m)
		_column(_pr_cbuf, _pr_ccol, C_PREV_Y, sim.pr_y, m)
		_column(_pr_cbuf, _pr_ccol, C_A, sim.pr_t0, m)
		_column(_pr_cbuf, _pr_ccol, C_B, sim.pr_t1, m)
		var pu: PackedInt32Array = sim.pr_unit.slice(0, m)
		if pu != _pr_unit_seen:
			# The shooters' flags (side + 2 x kind) per slot; slots change
			# hands only when missiles are fired.
			var nu: int = _pr_flags.size()
			for i in m:
				var u := pu[i]
				_pr_code[i] = float(_pr_flags[u]) if u >= 0 and u < nu else 0.0
			_pr_unit_seen = pu
			_pr_ccol.set_data(1, m, false, Image.FORMAT_RF, _pr_code.to_byte_array())
			_pr_cbuf.blit_rect(_pr_ccol, Rect2i(0, 0, 1, m), Vector2i(C_SPRITE, 0))
		_pr_mm_cpu.buffer = _pr_cbuf.get_data().to_float32_array()


## CPU path: the missile MultiMesh covers the slots in use so far, in steps
## of PR_STEP (the sim's free list is last in, first out, so the slots in
## use stay at the bottom; a battle rarely needs more than a few hundred).
func _pr_fit() -> void:
	var t1: PackedInt32Array = sim.pr_t1
	if _pr_n >= _pr_cap or t1.slice(_pr_n) == _pr_free_tail.slice(_pr_n):
		return
	var top := _pr_cap - 1
	while top >= _pr_n and t1[top] < 0:
		top -= 1
	_pr_n = mini(_pr_cap, (top / PR_STEP + 1) * PR_STEP)
	_pr_mm_cpu.instance_count = _pr_n
	_pr_cbuf = Image.create(STRIDE, _pr_n, false, Image.FORMAT_RF)
	_pr_ccol = Image.create(1, _pr_n, false, Image.FORMAT_RF)
	_pr_code.resize(_pr_n)
	_pr_unit_seen = PackedInt32Array()


## Column c of the buffer image `buf` = the ints of `a` as floats (exact
## below 2^24 in magnitude), with native calls only.
static func _column(buf: Image, col: Image, c: int, a: PackedInt32Array, count: int) -> void:
	if a.size() != count:
		a = a.slice(0, count)
		a.resize(count)
	col.set_data(1, count, false, Image.FORMAT_RF, PackedFloat32Array(Array(a)).to_byte_array())
	buf.blit_rect(col, Rect2i(0, 0, 1, count), Vector2i(c, 0))


static func _pack(arrays: Array, block: int) -> PackedByteArray:
	var out := PackedByteArray()
	for a in arrays:
		var b: PackedByteArray = (a as PackedInt32Array).to_byte_array()
		out.append_array(b)
		if b.size() < block:
			var pad := PackedByteArray()
			pad.resize(block - b.size())
			out.append_array(pad)
	return out


## Instance i's index for the texture path's shaders (INSTANCE_CUSTOM: i =
## x + 2048 * y, each part exact even at half precision). The shaders avoid
## INSTANCE_ID (gl_InstanceID) and uint / bitwise maths: an Android tablet's
## Chrome drew no soldiers at all with them (2026-10-07) while other devices
## did (that alone did not fix it; see the CPU-fed path).
static func _index_data(i: int) -> Color:
	return Color(float(i % 2048), float(i / 2048), 0.0, 0.0)


## alpha: interpolation between the previous and the current tick.
func set_alpha(a: float) -> void:
	for m in _materials:
		m.set_shader_parameter("alpha", a)
	# Positions on screen are those of tick (sim.tick - 1) + alpha.
	_pr_mat.set_shader_parameter("now", float(sim.tick) - 1.0 + a)


## The command line's user args plus, on the web, the page URL's query
## ("?soldiers=cpu" reads as "--soldiers=cpu").
static func _launch_args() -> Array:
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			for kv in (q as String).substr(1).split("&"):
				args.append("--" + kv)
	return args


## "cpu" or "gpu" when --soldiers= forces a path, else "".
static func forced_path() -> String:
	for a in _launch_args():
		if str(a).begins_with("--soldiers="):
			var v := str(a).get_slice("=", 1).to_lower()
			if v == "cpu" or v == "gpu":
				return v
	return ""


## The remembered choice: "cpu" (compatible, CPU-fed) or "auto" (texture
## path, falling back by itself).
static func load_pref() -> String:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return "auto"
	return "cpu" if str(cf.get_value("video", "soldiers", "auto")) == "cpu" else "auto"


static func save_pref(v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("video", "soldiers", v)
	cf.save(SETTINGS)


## Unit quad; the shaders place and size it (UV carries the corner).
func _make_quad() -> ArrayMesh:
	var verts := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Top-down placeholder sprites facing +x, greyscale so the shader can tint
## them per side and state: sword and shield, spear, long pike, bow,
## javelins, horse and rider, artillery crew, bolt thrower, stone thrower.
static func _make_atlas() -> ImageTexture:
	if _atlas_cache != null:
		return _atlas_cache
	var cw := int(CELL_W * ATLAS_PX_PER_M)
	var ch := int(CELL_H * ATLAS_PX_PER_M)
	var img := Image.create(cw * SPRITES, ch, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for spr in SPRITES:
		for py in ch:
			for px in cw:
				var p := Vector2(CELL_X0 + (px + 0.5) / ATLAS_PX_PER_M,
					CELL_Y0 + (py + 0.5) / ATLAS_PX_PER_M)
				var col := _sprite_pixel(spr, p)
				if col.a > 0.0:
					img.set_pixel(spr * cw + px, py, col)
	_atlas_cache = ImageTexture.create_from_image(img)
	return _atlas_cache


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Colour of sprite `spr` at local point p (metres, x forward, y right).
static func _sprite_pixel(spr: int, p: Vector2) -> Color:
	var col := Color(0, 0, 0, 0)
	var light := Color(0.72, 0.72, 0.72)
	var dark := Color(0.18, 0.18, 0.18)
	var white := Color(1, 1, 1)
	var metal := Color(0.92, 0.92, 0.92)
	var wood := Color(0.55, 0.55, 0.55)
	if spr == 7:
		return _bolt_thrower_pixel(p)
	if spr == 8:
		return _stone_thrower_pixel(p)
	# Body: shoulders (or the horse first) and head.
	if spr == 5:
		var hb := Vector2(p.x / 1.15, p.y / 0.36).length()
		if hb <= 1.0:
			col = Color(0.5, 0.5, 0.5) if hb < 0.86 else dark
		var nk := Vector2((p.x - 1.25) / 0.38, p.y / 0.15).length()
		if nk <= 1.0:
			col = Color(0.5, 0.5, 0.5) if nk < 0.75 else dark
		var rider := Vector2((p.x + 0.1) / 0.22, p.y / 0.36).length()
		if rider <= 1.0:
			col = light if rider < 0.8 else dark
		var hd := p.distance_to(Vector2(-0.07, 0.0))
		if hd <= 0.15:
			col = white if hd < 0.11 else dark
		# Lance held along the right side.
		if _seg_dist(p, Vector2(-0.6, 0.42), Vector2(1.65, 0.42)) < 0.04:
			col = metal
		return col
	var e := Vector2(p.x / 0.27, p.y / 0.44).length()
	if e <= 1.0:
		col = light if e < 0.82 else dark
	var hd2 := p.distance_to(Vector2(0.03, 0.0))
	if hd2 <= 0.17:
		col = white if hd2 < 0.13 else dark
	match spr:
		0:  # big shield across the front, sword on the right
			if p.x >= 0.3 and p.x <= 0.42 and p.y >= -0.47 and p.y <= 0.4:
				var edge := p.x < 0.34 or p.x > 0.38 or p.y < -0.43 or p.y > 0.36
				col = dark if edge else white
			if _seg_dist(p, Vector2(0.1, 0.45), Vector2(0.78, 0.45)) < 0.04:
				col = metal
		1:  # shield on the left, spear forward on the right
			if Vector2((p.x - 0.3) / 0.1, (p.y + 0.22) / 0.27).length() <= 1.0:
				col = white
			if _seg_dist(p, Vector2(-0.4, 0.32), Vector2(2.1, 0.32)) < 0.035:
				col = wood
			if _seg_dist(p, Vector2(2.0, 0.32), Vector2(2.3, 0.32)) < 0.06:
				col = metal
		2:  # long pike levelled forward, small shield
			if p.distance_to(Vector2(0.22, -0.18)) <= 0.18:
				col = white
			if _seg_dist(p, Vector2(-0.7, 0.16), Vector2(4.2, 0.16)) < 0.035:
				col = wood
			if _seg_dist(p, Vector2(4.1, 0.16), Vector2(4.42, 0.16)) < 0.06:
				col = metal
		3:  # bow arc in front, quiver on the back
			var bd := p.distance_to(Vector2(0.05, 0.0))
			if absf(bd - 0.55) < 0.045 and p.x > 0.28:
				col = wood
			if absf(p.x - 0.32) < 0.015 and absf(p.y) < 0.47:
				col = metal
			if p.x >= -0.36 and p.x <= -0.22 and p.y >= 0.1 and p.y <= 0.4:
				col = dark
		4:  # small round shield, two javelins
			if p.distance_to(Vector2(0.25, -0.3)) <= 0.2:
				col = white
			for off in [0.33, 0.43]:
				if _seg_dist(p, Vector2(-0.3, off), Vector2(1.35, off)) < 0.03:
					col = wood
				if _seg_dist(p, Vector2(1.3, off), Vector2(1.48, off)) < 0.045:
					col = metal
		6:  # gun crew: a handspike carried across the body
			if _seg_dist(p, Vector2(0.15, -0.5), Vector2(0.35, 0.5)) < 0.04:
				col = wood
	return col


## Bolt thrower (scorpion) from above, shooting along +x: stock and slider,
## two torsion springs, bow arms swept back, a bolt in the groove, three legs.
static func _bolt_thrower_pixel(p: Vector2) -> Color:
	var col := Color(0, 0, 0, 0)
	var wood := Color(0.62, 0.62, 0.62)
	var dark := Color(0.2, 0.2, 0.2)
	var metal := Color(0.95, 0.95, 0.95)
	for leg in [Vector2(-1.1, -0.75), Vector2(-1.1, 0.75), Vector2(0.9, 0.0)]:
		if _seg_dist(p, Vector2(-0.2, 0.0), leg) < 0.05:
			col = dark
	if p.x >= -1.0 and p.x <= 1.05 and absf(p.y) <= 0.13:
		col = wood if absf(p.y) < 0.09 else dark
	for sgn in [-1.0, 1.0]:
		var spring := Vector2(0.45, 0.28 * sgn)
		if Vector2((p.x - spring.x) / 0.16, (p.y - spring.y) / 0.13).length() <= 1.0:
			col = dark
		if _seg_dist(p, spring, Vector2(0.15, 0.95 * sgn)) < 0.055:
			col = wood
	if _seg_dist(p, Vector2(0.15, -0.95), Vector2(-0.55, 0.0)) < 0.018 \
			or _seg_dist(p, Vector2(0.15, 0.95), Vector2(-0.55, 0.0)) < 0.018:
		col = Color(0.85, 0.85, 0.85)
	if _seg_dist(p, Vector2(-0.5, 0.0), Vector2(1.3, 0.0)) < 0.035:
		col = metal if p.x > 1.1 else Color(0.8, 0.8, 0.8)
	return col


## Stone thrower (onager) from above, throwing along +x: a long low frame,
## the throwing arm lying back in it with the sling and a stone, the
## buffer beam across the front and the winch at the back.
static func _stone_thrower_pixel(p: Vector2) -> Color:
	var col := Color(0, 0, 0, 0)
	var wood := Color(0.6, 0.6, 0.6)
	var dark := Color(0.2, 0.2, 0.2)
	for sgn in [-1.0, 1.0]:
		if p.x >= -1.5 and p.x <= 1.55 and absf(p.y - 0.72 * sgn) <= 0.13:
			col = wood if absf(p.y - 0.72 * sgn) < 0.09 else dark
	for bx in [-1.4, 0.0, 1.45]:
		if absf(p.x - bx) <= 0.12 and absf(p.y) <= 0.85:
			col = wood if absf(p.x - bx) < 0.08 else dark
	# Buffer beam (padded) across the front uprights.
	if absf(p.x - 0.75) <= 0.16 and absf(p.y) <= 0.95:
		col = Color(0.75, 0.75, 0.75) if absf(p.x - 0.75) < 0.11 else dark
	# Throwing arm lying back, sling and stone at its end.
	if _seg_dist(p, Vector2(0.55, 0.0), Vector2(-1.2, 0.0)) < 0.08:
		col = Color(0.82, 0.82, 0.82)
	if p.distance_to(Vector2(-1.35, 0.0)) <= 0.2:
		col = Color(0.45, 0.45, 0.45) if p.distance_to(Vector2(-1.35, 0.0)) < 0.16 else dark
	# Torsion bundle and winch drum.
	if Vector2(p.x / 0.2, p.y / 0.45).length() <= 1.0:
		col = dark
	if absf(p.x + 1.4) <= 0.1 and absf(p.y) <= 0.6:
		col = dark
	return col
