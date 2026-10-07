extends Node2D
## Renders all soldiers with two MultiMeshInstance2D nodes (corpses below,
## living above) that share one MultiMesh and one data texture, and missiles
## in flight with one more MultiMesh. Artillery engines are extra instances
## of the soldier MultiMesh (after the soldiers, same data blocks, state 6 =
## working, 7 = wrecked or abandoned), so they cost no extra draw call. Per
## tick the sim's packed int arrays are copied into the textures with native
## calls only; the shaders decode and interpolate them (see
## soldiers.gdshader and projectiles.gdshader).

const SHADER := preload("res://game/soldiers.gdshader")
const PR_SHADER := preload("res://game/projectiles.gdshader")
const UT := preload("res://sim/unit_types.gd")
const TEX_W := 1024
const BLOCKS := 8
const PR_BLOCKS := 8

## Sprite cells (see soldiers.gdshader): local box x -1.6..4.4 m forward,
## y -1.25..1.25 m to the right, ATLAS_PX_PER_M pixels per metre.
const SPRITES := 9
const CELL_X0 := -1.6
const CELL_W := 6.0
const CELL_Y0 := -1.25
const CELL_H := 2.5
const ATLAS_PX_PER_M := 24
## Quad drawn per sprite: xmin, xmax, ymin, ymax (metres).
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

## Self-check (probe): once per battle, PROBE_FRAMES frames in, only the
## soldier layers are drawn into a small offscreen viewport around the
## biggest unit and the drawn pixels are counted; `probed` reports them
## (telemetry, console "SOLDIER_PROBE", server/cmd/webcheck). Zero pixels
## with men alive means this device draws no soldiers.
signal probed(drawn: int, men: int)
const PROBE_LAYER := 1 << 19   # visibility layer only the probe viewport draws
const PROBE_PX := 128          # probe viewport size (px), 2 px a metre
const PROBE_FRAMES := 30

## Built once per page session (procedural, ~30k pixels).
static var _atlas_cache: ImageTexture = null

var px_per_m: float = 10.0
var sim  # BattleSim (untyped to keep the view decoupled)
## Units drawn highlighted (selection).
var selected_units: Dictionary = {}

var _mm: MultiMesh
var _layers: Array[MultiMeshInstance2D] = []
var _materials: Array[ShaderMaterial] = []
var _image: Image
var _tex: ImageTexture
var _rows: int = 1
var _flags := PackedInt32Array()
var _unit_sprite := PackedInt32Array()
var _unit_engine := PackedInt32Array()  # engine sprite per unit (0 = none)
var _e_state := PackedInt32Array()
var _n_inst := 0

var _pr_mat: ShaderMaterial
var _pr_image: Image
var _pr_tex: ImageTexture
var _pr_rows: int = 1
var _pr_flags := PackedInt32Array()
var _pr_was_active := true
var _probe_frames := 0


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	var n: int = sim.n
	_n_inst = n + sim.n_eng
	_rows = maxi(1, (maxi(_n_inst, sim.n_units) + TEX_W - 1) / TEX_W)
	var bytes := PackedByteArray()
	bytes.resize(BLOCKS * _rows * TEX_W * 4)
	_image = Image.create_from_data(TEX_W, BLOCKS * _rows, false, Image.FORMAT_RGBA8, bytes)
	_tex = ImageTexture.create_from_image(_image)
	_flags.resize(sim.n_units)
	_unit_sprite.resize(sim.n_units)
	_unit_engine.resize(sim.n_units)
	_e_state.resize(sim.n_eng)
	for u in sim.n_units:
		_unit_sprite[u] = UT.stat(sim.u_type[u], "sprite")
		var kind := UT.stat(sim.u_type[u], "m_kind") if UT.cls(sim.u_type[u]) == UT.CLS_ART else 0
		_unit_engine[u] = 7 if kind == 1 else (8 if kind == 2 else 0)

	var fw: float = sim.field_w / 1024.0 * px_per_m
	var fh: float = sim.field_h / 1024.0 * px_per_m
	var pad := px_per_m * 6.0
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	_mm.mesh = _make_quad()
	_mm.instance_count = _n_inst
	for i in _n_inst:
		_mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
		_mm.set_instance_custom_data(i, _index_data(i))
	# All instance transforms are identity (the shader places soldiers), so
	# give the MultiMesh bounds covering the whole field to avoid culling.
	_mm.custom_aabb = AABB(Vector3(-pad, -pad, -1.0), Vector3(fw + 2.0 * pad, fh + 2.0 * pad, 2.0))

	var atlas := _make_atlas()
	var rects: Array = []
	for r in SPR_RECT:
		rects.append(r)
	for pass_id in 2:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("data_tex", _tex)
		mat.set_shader_parameter("rows_per_block", _rows)
		mat.set_shader_parameter("tex_width", TEX_W)
		mat.set_shader_parameter("px_per_unit", px_per_m / 1024.0)
		mat.set_shader_parameter("layer_pass", pass_id)
		mat.set_shader_parameter("spr_rect", rects)
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = _mm
		mmi.texture = atlas
		mmi.material = mat
		add_child(mmi)
		_layers.append(mmi)
		_materials.append(mat)

	# Projectiles: one instance per sim projectile slot.
	var cap: int = sim.pr_t1.size()
	_pr_rows = maxi(1, (maxi(cap, sim.n_units) + TEX_W - 1) / TEX_W)
	var pbytes := PackedByteArray()
	pbytes.resize(PR_BLOCKS * _pr_rows * TEX_W * 4)
	_pr_image = Image.create_from_data(TEX_W, PR_BLOCKS * _pr_rows, false, Image.FORMAT_RGBA8, pbytes)
	_pr_tex = ImageTexture.create_from_image(_pr_image)
	_pr_flags.resize(sim.n_units)
	for u in sim.n_units:
		# Bits 1-2: 0 arrow, 1 javelin, 2 bolt, 3 stone.
		var ty: int = sim.u_type[u]
		var kind := 0 if UT.stat(ty, "m_arc") != 0 else 1
		if UT.cls(ty) == UT.CLS_ART:
			kind = 2 if UT.stat(ty, "m_kind") == 1 else 3
		_pr_flags[u] = (sim.u_side[u] & 1) | (kind << 1)
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_2D
	pmm.use_custom_data = true
	pmm.mesh = _make_quad()
	pmm.instance_count = cap
	for i in cap:
		pmm.set_instance_transform_2d(i, Transform2D.IDENTITY)
		pmm.set_instance_custom_data(i, _index_data(i))
	pmm.custom_aabb = _mm.custom_aabb
	_pr_mat = ShaderMaterial.new()
	_pr_mat.shader = PR_SHADER
	_pr_mat.set_shader_parameter("data_tex", _pr_tex)
	_pr_mat.set_shader_parameter("rows_per_block", _pr_rows)
	_pr_mat.set_shader_parameter("tex_width", TEX_W)
	_pr_mat.set_shader_parameter("px_per_unit", px_per_m / 1024.0)
	var pmmi := MultiMeshInstance2D.new()
	pmmi.multimesh = pmm
	pmmi.material = _pr_mat
	add_child(pmmi)
	upload()


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
	probed.emit(drawn, int(sim.u_alive[best]))


## Copy the sim arrays into the data textures. Call once after each tick.
func upload() -> void:
	var block := _rows * TEX_W * 4
	var nu: int = sim.n_units
	var tick: int = sim.tick
	for u in nu:
		var under_fire := 4 if tick - sim.u_hit_t[u] < 10 else 0
		_flags[u] = (sim.u_side[u] & 1) | (2 if selected_units.has(u) else 0) | under_fire \
			| (_unit_sprite[u] << 4) | (_unit_engine[u] << 8)
	if sim.n_eng == 0:
		_image.set_data(TEX_W, BLOCKS * _rows, false, Image.FORMAT_RGBA8, _pack([sim.pos_x,
			sim.pos_y, sim.prev_x, sim.prev_y, sim.facing, sim.state, sim.unit_of, _flags], block))
	else:
		# Engines follow the soldiers in every block.
		for e in sim.n_eng:
			_e_state[e] = ENGINE_OK if sim.e_state[e] == 0 else ENGINE_OUT
		_image.set_data(TEX_W, BLOCKS * _rows, false, Image.FORMAT_RGBA8, _pack([
			sim.pos_x + sim.e_x, sim.pos_y + sim.e_y, sim.prev_x + sim.e_px,
			sim.prev_y + sim.e_py, sim.facing + sim.e_face, sim.state + _e_state,
			sim.unit_of + sim.e_unit, _flags], block))
	_tex.update(_image)
	# Projectiles: skip the upload while nothing flies (and nothing flew).
	var active: bool = sim.pr_count > 0
	if active or _pr_was_active:
		var pblock := _pr_rows * TEX_W * 4
		_pr_image.set_data(TEX_W, PR_BLOCKS * _pr_rows, false, Image.FORMAT_RGBA8, _pack([
			sim.pr_sx, sim.pr_sy, sim.pr_x, sim.pr_y, sim.pr_t0, sim.pr_t1, sim.pr_unit,
			_pr_flags], pblock))
		_pr_tex.update(_pr_image)
	_pr_was_active = active


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


## Instance i's index for the shaders (INSTANCE_CUSTOM: i = x + 2048 * y,
## each part exact even at half precision). The shaders avoid INSTANCE_ID
## (gl_InstanceID) and uint / bitwise maths: an Android tablet's Chrome drew
## no soldiers at all with them (2026-10-07) while other devices did.
static func _index_data(i: int) -> Color:
	return Color(float(i % 2048), float(i / 2048), 0.0, 0.0)


## alpha: interpolation between the previous and the current tick.
func set_alpha(a: float) -> void:
	for m in _materials:
		m.set_shader_parameter("alpha", a)
	# Positions on screen are those of tick (sim.tick - 1) + alpha.
	_pr_mat.set_shader_parameter("now", float(sim.tick) - 1.0 + a)


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
