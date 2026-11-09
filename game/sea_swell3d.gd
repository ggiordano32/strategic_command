extends RefCounted
## The sea battle's live swell in 3D (stage D2, the owner's answer of 2026-11-09: "a live 3d swell for the ocean battle view ... moving
## but still has a resin feel, not so much a realistic one"). View only. ONE place for the balance between the resin and the motion:
## the constants below and the dev switch `--sea-swell=<0..2>` (or the web's `?sea-swell=`), a scale on every train's height
## (0 a still resin board, 1 the default, 2 twice as lively).
##
## Two long trains running before the wind (the water fragment's own two big trains, a little taller and longer: the chop is only the
## painted crests). The same formula runs twice and must agree: here on the CPU (a ship's lift, pitch and roll, the foam ring and the
## wakes' height) and in game/sea_water3d.gdshader's vertex stage (the grid's displacement), both with the world position, the water's
## clock `t` (SeaLook._clock), the wind's direction and strength, and the vertex's damping (the grid's COLOR.r, the same
## `damp()` of the signed distance to the coast: calm in the shallows, no vertex texture reads).

const TRAINS := [Vector4(0.0, 64.0, 5.8, 0.85), Vector4(0.28, 36.0, 4.4, 0.45)]   # turn from the wind (rad), wavelength (m), speed (m/s), height (m)
const CREST_LEAN := 0.12     # the second harmonic: sharper crests, flatter troughs
const GLOSS := 0.55          # the resin's highlight (0 matte .. 1 glossy)
const SHININESS := 38.0      # the highlight's tightness
const SHADE := 1.1           # how much the swell's slope lights and darkens the painted water
const CELL := 12.0           # the displaced grid's cell (metres): a fifth of the long train's wave
const TILT_MAX := 0.11       # a hull's pitch and roll never exceed this (radians)

static var k := 1.0          # --sea-swell


static func read_args() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--sea-swell="):
			k = clampf(float(str(a).get_slice("=", 1)), 0.0, 2.0)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			for kv in (q as String).trim_prefix("?").split("&"):
				if kv.begins_with("sea-swell="):
					k = clampf(float(kv.get_slice("=", 1)), 0.0, 2.0)


## Calm in the shallows and near the shore, scaled by the wind: 0.12 .. 1 (the shader's formula).
static func damp(wstr: float, sdf: float) -> float:
	return (0.35 + 0.65 * smoothstep(8.0, 120.0, sdf)) * (0.35 + 0.65 * wstr)


## Height (x) and gradient (y east, z south) of the swell at sea point p: `edge` the vertex's own coast damping smoothstep(8, 120, sdf).
static func sample(p: Vector2, t: float, wdir: Vector2, wstr: float, edge: float) -> Vector3:
	var d := (0.35 + 0.65 * edge) * (0.35 + 0.65 * wstr) * k
	var w := wdir.normalized()
	var h := 0.0
	var g := Vector2.ZERO
	for i in TRAINS.size():
		var trn: Vector4 = TRAINS[i]
		var dir := w.rotated(trn.x)
		var kw := TAU / trn.y
		var ph := p.dot(dir) * kw - t * trn.z * kw + float(i) * 2.1
		h += trn.w * (sin(ph) - CREST_LEAN * cos(2.0 * ph))
		g += dir * (trn.w * kw * (cos(ph) + 2.0 * CREST_LEAN * sin(2.0 * ph)))
	return Vector3(h * d, g.x * d, g.y * d)


## A hull at `p` heading `h`: lift (x), pitch (y, bow up positive), roll (z, starboard down positive).
static func ride(p: Vector2, h: float, t: float, wdir: Vector2, wstr: float, sdf: float) -> Vector3:
	var s := sample(p, t, wdir, wstr, smoothstep(8.0, 120.0, sdf))
	var g := Vector2(s.y, s.z)
	var fwd := Vector2(cos(h), sin(h))
	var side := Vector2(-sin(h), cos(h))
	return Vector3(s.x, clampf(g.dot(fwd), -TILT_MAX, TILT_MAX), clampf(-g.dot(side), -TILT_MAX, TILT_MAX))


## The water material's swell uniforms (the shader's twin of the constants above).
static func apply(mat: ShaderMaterial, on: bool) -> void:
	var turn := PackedFloat32Array()
	var lam := PackedFloat32Array()
	var spd := PackedFloat32Array()
	var amp := PackedFloat32Array()
	for trn in TRAINS:
		turn.append(trn.x)
		lam.append(trn.y)
		spd.append(trn.z)
		amp.append(trn.w)
	mat.set_shader_parameter("sw_turn", turn)
	mat.set_shader_parameter("sw_lam", lam)
	mat.set_shader_parameter("sw_spd", spd)
	mat.set_shader_parameter("sw_amp", amp)
	mat.set_shader_parameter("sw_k", k if on else 0.0)
	mat.set_shader_parameter("sw_lean", CREST_LEAN)
	mat.set_shader_parameter("sw_gloss", GLOSS if on else 0.0)
	mat.set_shader_parameter("sw_shine", SHININESS)
	mat.set_shader_parameter("sw_shade", SHADE if on else 0.0)


## The displaced grid over [x0, x1] x [z0, z1] (world metres), vertex COLOR.r the coast damping of `look` (smoothstep(8, 120, sdf)),
## COLOR.g the board edge's taper (0 at the border, 1 from 60 m in).
static func grid_mesh(look, x0: float, z0: float, x1: float, z1: float) -> ArrayMesh:
	var nx := int(ceil((x1 - x0) / CELL))
	var nz := int(ceil((z1 - z0) / CELL))
	var pv := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for j in nz + 1:
		var z := z0 + (z1 - z0) * float(j) / nz
		for i in nx + 1:
			var x := x0 + (x1 - x0) * float(i) / nx
			pv.append(Vector3(x, 0.0, z))
			var e := minf(minf(x - x0, x1 - x), minf(z - z0, z1 - z))
			col.append(Color(smoothstep(8.0, 120.0, look.sdf_at(Vector2(x, z))), smoothstep(0.0, 60.0, e), 0, 1))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			idx.append_array(PackedInt32Array([a, a + 1, a + nx + 1, a + 1, a + nx + 2, a + nx + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.custom_aabb = AABB(Vector3(x0, -4.0, z0), Vector3(x1 - x0, 8.0, z1 - z0))
	return am
