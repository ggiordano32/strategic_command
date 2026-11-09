extends Node3D
## The 3D battle view's flashes and smoke (the flash and smoke pass, 2026-11-06; docs/design/art_pipeline.md "The flash and the smoke").
## View only: it reads the overlay's live flashes and GunSmoke's puffs (the overlay keeps them, ages them and stays the one source for
## the three views and the tests) and draws them in the 3D scene:
## - the smoke: one MultiMesh of billboards (game/fx_smoke3d.gdshader), the cotton tiles of game/gun_smoke.gd, depth-tested: a puff
##   behind a house is hidden. The same sprites as the 2D views (GunSmoke.collect), the long-fire haze as big soft billboards;
## - the flash: one MultiMesh of additive billboards, three layers a flash (halo, glow, core: game/fx_flash3d.gdshader);
## - the light: the live flashes gathered into at most 8 clusters (one per 6 m cell: one light per unit's volley position, not per
##   man), each an OmniLight3D from a pool (not on Graphics Low) lighting the ground, the bases and the houses, and the same clusters
##   as the `flash_pts` uniform of the men's and the smoke's unshaded shaders (a real light does not reach those).
## No node per puff, no node per flash. While this node is alive the overlay draws neither (Overlay.fx3d).

const GunSmoke := preload("res://game/gun_smoke.gd")
const SMOKE_SHADER := preload("res://game/fx_smoke3d.gdshader")
const FLASH_SHADER := preload("res://game/fx_flash3d.gdshader")
const BattleLook := preload("res://game/battle_look.gd")
const BoardView := preload("res://game/board_view.gd")
const Quality := preload("res://game/quality.gd")

const MAX_LIGHTS := 8
const CELL_M := 6.0
const Impacts3D := preload("res://game/impacts3d.gd")
const SMOKE_MAX := 280 * 3 + 40 + Impacts3D.PUFF_MAX   # (the overlay's cap is 280 puffs of three sprites, plus the haze, plus the impacts' dust)
const FLASH_MAX := 3 * 420

var view
var ov
var ppm := 10.0
var smoke_mmi: MultiMeshInstance3D
var smoke_mat: ShaderMaterial
var flash_mmi: MultiMeshInstance3D
var flash_mat: ShaderMaterial
var lights: Array[OmniLight3D] = []
var imp: Node3D                  # the stones, balls, chips, shadows and dust of the landings (game/impacts3d.gd)
var _sbuf := PackedFloat32Array()
var _fbuf := PackedFloat32Array()
var _pts := PackedVector4Array()
var _pts_n := -1
## For the tests and the build line: what the last frame drew.
var smoke_drawn := 0
var flash_drawn := 0
var lights_on := 0
var us_smoke := 0
var us_flash := 0
var us_collect := 0
var us_total := 0           # microseconds spent in update() (the CPU side of this layer, for the benchmarks)


func setup(p_view) -> void:
	view = p_view
	ov = view.battle.overlay
	ppm = view.ppm
	if ov == null:
		return
	var aabb := AABB(Vector3(-60.0, view.ground_lo - 20.0, -60.0), Vector3(view.field_m.x + 120.0, view.ground_hi - view.ground_lo + 80.0, view.field_m.y + 120.0))
	var tex := GunSmoke.texture()
	smoke_mat = ShaderMaterial.new()
	smoke_mat.shader = SMOKE_SHADER
	smoke_mat.set_shader_parameter("tex", tex)
	var dio := BattleLook.is_diorama()
	smoke_mat.set_shader_parameter("tint", Vector3(1.0, 1.0, 0.99) if dio else Vector3(0.8, 0.82, 0.86))
	_sbuf = _init_buf(SMOKE_MAX)
	_fbuf = _init_buf(FLASH_MAX)
	smoke_mmi = _make_mmi(SMOKE_MAX, smoke_mat, aabb)
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = FLASH_SHADER
	flash_mat.set_shader_parameter("tex", tex)
	flash_mmi = _make_mmi(FLASH_MAX, flash_mat, aabb)
	view.card_mats.append(smoke_mat)
	view.card_mats.append(flash_mat)
	if not Quality.is_low():
		for i in MAX_LIGHTS:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.64, 0.32)
			l.light_specular = 0.0
			l.shadow_enabled = false
			l.omni_attenuation = 1.3
			l.visible = false
			add_child(l)
			lights.append(l)
	_pts.resize(MAX_LIGHTS)
	ov.fx3d = true
	imp = Impacts3D.new()
	add_child(imp)
	imp.setup(view)


## Graphics went Low mid-battle: the pooled flash lights go (none on Low).
func drop_lights() -> void:
	for l in lights:
		l.queue_free()
	lights.clear()
	lights_on = 0


func _make_mmi(n: int, mat: ShaderMaterial, aabb: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = view.card_quad()
	mm.instance_count = n
	mm.custom_aabb = aabb
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _init_buf(n: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n * 16)
	for i in n:   # (the basis stays the identity: only the place and the custom data are written each frame)
		buf[i * 16] = 1.0
		buf[i * 16 + 5] = 1.0
		buf[i * 16 + 10] = 1.0
	return buf


func _exit_tree() -> void:
	if ov != null and is_instance_valid(ov):
		ov.fx3d = false


## Every frame after the camera has moved (View3D._process).
func update() -> void:
	if ov == null or smoke_mmi == null:
		return
	var t0 := Time.get_ticks_usec()
	if imp != null:
		imp.update()
	_update_smoke()
	var t1 := Time.get_ticks_usec()
	us_smoke += t1 - t0
	_update_flashes()
	us_flash += Time.get_ticks_usec() - t1
	us_total += Time.get_ticks_usec() - t0


func _put(buf: PackedFloat32Array, i: int, c: Vector3, r: float, a: float, code: float, w: float) -> void:
	var o := i * 16
	buf[o + 3] = c.x
	buf[o + 7] = c.y
	buf[o + 11] = c.z
	buf[o + 12] = r
	buf[o + 13] = a
	buf[o + 14] = code
	buf[o + 15] = w


func _update_smoke() -> void:
	var tc := Time.get_ticks_usec()
	var n: int = ov.smoke_sprites()
	us_collect += Time.get_ticks_usec() - tc
	var sb: PackedFloat32Array = ov.smoke_buf()
	var cb: Basis = view.cam.global_transform.basis
	var inv := 1.0 / ppm
	var rx := cb.x.x * inv
	var ry := cb.x.y * inv
	var rz := cb.x.z * inv
	var ux := cb.y.x * inv
	var uy := cb.y.y * inv
	var uz := cb.y.z * inv
	var k := 0
	var kmax := SMOKE_MAX - 20 - Impacts3D.PUFF_MAX
	for i in mini(n, kmax):
		var o := i * GunSmoke.STRIDE
		var ox := sb[o + 3]
		var oy := sb[o + 4]
		var q := k * 16
		_sbuf[q + 3] = sb[o] * inv + rx * ox - ux * oy
		_sbuf[q + 7] = sb[o + 2] * inv + ry * ox - uy * oy
		_sbuf[q + 11] = sb[o + 1] * inv + rz * ox - uz * oy
		_sbuf[q + 12] = sb[o + 5] * inv
		_sbuf[q + 13] = sb[o + 6]
		_sbuf[q + 14] = sb[o + 7]
		k += 1
	if imp != null:
		var ip: PackedFloat32Array = imp.puffs
		for i in imp.n_puff:
			var o: int = i * Impacts3D.PUFF_STRIDE
			_put(_sbuf, k, Vector3(ip[o], ip[o + 1], ip[o + 2]), ip[o + 3], ip[o + 4], ip[o + 5], 0.0)
			k += 1
	var hz: Array = ov.haze_data()
	if hz[2]:
		var hp: PackedVector2Array = hz[0]
		var ha: PackedFloat32Array = hz[1]
		for h in hp.size():
			if k >= SMOKE_MAX:
				break
			var c := Vector3(hp[h].x / ppm, BoardView.ground_m(hp[h]) + 2.0, hp[h].y / ppm)
			_put(_sbuf, k, c, 12.0 * 0.8, 0.2 * minf(1.0, ha[h]), 8.0, 0.0)
			k += 1
	smoke_drawn = k
	var mm := smoke_mmi.multimesh
	if k > 0 or mm.visible_instance_count > 0:
		mm.buffer = _sbuf
		mm.visible_instance_count = k


func _update_flashes() -> void:
	var d: Dictionary = ov.flash_data()
	var pos: PackedVector2Array = d["pos"]
	var szs: PackedFloat32Array = d["sz"]
	var fas: PackedFloat32Array = d["fa"]
	var eng: PackedFloat32Array = d["eng"]
	var k := 0
	var cells := {}
	var cl_pos: Array = []   # per cluster: [sum x, sum y (px), weight, strength, height m]
	for i in pos.size():
		var fa := fas[i]
		if fa <= 0.0 or k + 3 > FLASH_MAX:
			continue
		var p := pos[i]
		var s := fa * fa
		var c := Vector3(p.x / ppm, BoardView.ground_m(p) + 1.1, p.y / ppm)
		var r := szs[i] * 6.0 / ppm
		_put(_fbuf, k, c, r, 0.26 * s, 0.0, 0.0)
		_put(_fbuf, k + 1, c, r * 0.42, 0.5 * s, 0.0, 1.0)
		_put(_fbuf, k + 2, c, r * 0.15, s, 0.0, 2.0)
		k += 3
		var key := int(p.x / (ppm * CELL_M)) * 65536 + int(p.y / (ppm * CELL_M))
		if cells.has(key):
			var cc: Array = cl_pos[cells[key]]
			cc[0] += p.x * s
			cc[1] += p.y * s
			cc[2] += s
			cc[3] = maxf(cc[3], s)
			cc[4] += 1.0
		else:
			cells[key] = cl_pos.size()
			cl_pos.append([p.x * s, p.y * s, s, s, 1.0, 1.0])
	for i in eng.size() / 6:
		var fa := eng[i * 6 + 5]
		if k + 3 > FLASH_MAX or fa <= 0.0:
			continue
		var p := Vector2(eng[i * 6], eng[i * 6 + 1])
		var s := fa * fa
		var c := Vector3(p.x / ppm, BoardView.ground_m(p) + 1.8, p.y / ppm)
		var r := eng[i * 6 + 4] * 1.4 / ppm
		_put(_fbuf, k, c, r, 0.26 * s, 0.0, 0.0)
		_put(_fbuf, k + 1, c, r * 0.42, 0.5 * s, 0.0, 1.0)
		_put(_fbuf, k + 2, c, r * 0.15, s, 0.0, 2.0)
		k += 3
		cl_pos.append([p.x * s, p.y * s, s, 2.0 * s, 8.0, 2.0])   # (an engine: a light of its own, a bigger reach)
	flash_drawn = k / 3
	var mm := flash_mmi.multimesh
	if k > 0 or mm.visible_instance_count > 0:
		mm.buffer = _fbuf
		mm.visible_instance_count = k
	# The pooled lights: the strongest clusters, at most MAX_LIGHTS.
	cl_pos.sort_custom(func(a, b): return a[3] > b[3])
	var n := mini(cl_pos.size(), MAX_LIGHTS)
	for i in n:
		var cc: Array = cl_pos[i]
		var w: float = cc[2]
		var p := Vector2(cc[0], cc[1]) / maxf(w, 0.0001)
		var st: float = minf(cc[3] * (0.7 + 0.1 * minf(cc[4], 6.0)), 2.0)
		var wp := Vector3(p.x / ppm, BoardView.ground_m(p) + (1.8 if cc[5] > 1.5 else 1.2), p.y / ppm)
		_pts[i] = Vector4(wp.x, wp.y, wp.z, st)
		if i < lights.size():
			var l := lights[i]
			l.visible = true
			l.position = wp
			l.omni_range = 22.0 if cc[5] > 1.5 else 9.0
			l.light_energy = 2.4 * st
	for i in range(n, lights.size()):
		lights[i].visible = false
	lights_on = n if not lights.is_empty() else 0
	if n > 0 or _pts_n != 0:
		_pts_n = n
		for m in [view.men_mat, smoke_mat]:
			if m != null:
				m.set_shader_parameter("flash_pts", _pts)
				m.set_shader_parameter("flash_n", n)
