extends Node3D
## The 3D battle view's stones, balls, chips, shadows and dust (2026-11-07; docs/design/art_pipeline.md "Men on the walk surface and
## stones with depth"; the owner: "The exploding rocks look good, except they are drawn over the houses, so when they fall between the
## houses and you are viewing from the side, it looks odd as it floats over the houses and hits the floor (which we can't see) and
## disappears" and "The boulders are actually drawn over everything, so landing and rolling in an enemy army is a bit odd"). View only:
## it reads what the overlay's _draw_impacts and _draw_fx drew over the scene (the sim's fx_* ring of landed stones and balls, the
## overlay's aged blasts, dust and chips) and draws it in the 3D scene, as game/fx3d.gd does the smoke, so depth hides it behind a house
## or a line of men:
## - the stones, balls and chips: one MultiMesh of little spheres (game/fx_stone3d.gdshader), a stone at its place on its run, its
##   chips falling to the foot, a sinking one lower and darker;
## - the shadows and the dust rings: one MultiMesh of ground discs (game/fx_disc3d.gdshader): the blob under a stone in the air (the
##   projectile layer's flying stones too) and the ring where one came down;
## - the dust, the blast's flash and smoke: billboards with depth, appended to the smoke's MultiMesh (Fx3D takes `puffs`).
## While this node is alive the overlay draws none of these (Overlay.impacts3d). No node per stone.

const STONE_SHADER := preload("res://game/fx_stone3d.gdshader")
const DISC_SHADER := preload("res://game/fx_disc3d.gdshader")
const BoardView := preload("res://game/board_view.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Overlay := preload("res://game/overlay.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")

const SPH_MAX := 360
const DISC_MAX := 300
const PUFF_MAX := 140
const PUFF_STRIDE := 6
const COL_STONE := Color(0.5, 0.47, 0.42)
const COL_IRON := Color(0.17, 0.16, 0.16)
const COL_SMOKE := Color(0.5, 0.5, 0.52)

var view
var ov
var ppm := 10.0
var sph_mmi: MultiMeshInstance3D
var sph_mat: ShaderMaterial
var disc_mmi: MultiMeshInstance3D
var disc_mat: ShaderMaterial
var _sph := PackedFloat32Array()
var _disc := PackedFloat32Array()
## The puffs of the frame for Fx3D: PUFF_STRIDE floats each (x, y, z m; radius m; alpha; the smoke atlas's code).
var puffs := PackedFloat32Array()
## What the last frame drew (the tests and the build line).
var n_sph := 0
var n_disc := 0
var n_puff := 0
var n_fly := 0
var us_total := 0


func setup(p_view) -> void:
	view = p_view
	ov = view.battle.overlay
	ppm = view.ppm
	if ov == null:
		return
	var aabb := AABB(Vector3(-60.0, view.ground_lo - 20.0, -60.0), Vector3(view.field_m.x + 120.0, view.ground_hi - view.ground_lo + 80.0, view.field_m.y + 120.0))
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	sph_mat = ShaderMaterial.new()
	sph_mat.shader = STONE_SHADER
	view.mesh_mats.append(sph_mat)   # (the world lamp's key_dir follows it, View3D.set_lamp)
	_sph = PackedFloat32Array()
	_sph.resize(SPH_MAX * 16)
	sph_mmi = _mmi(sm, SPH_MAX, true, false, sph_mat, aabb)
	var dq := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	dq.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	dq.custom_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 2, 16))
	disc_mat = ShaderMaterial.new()
	disc_mat.shader = DISC_SHADER
	_disc = PackedFloat32Array()
	_disc.resize(DISC_MAX * 20)
	disc_mmi = _mmi(dq, DISC_MAX, true, true, disc_mat, aabb)
	puffs.resize(PUFF_MAX * PUFF_STRIDE)
	ov.impacts3d = true


func _mmi(mesh: Mesh, n: int, colors: bool, custom: bool, mat: ShaderMaterial, aabb: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = n
	mm.custom_aabb = aabb
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _exit_tree() -> void:
	if ov != null and is_instance_valid(ov):
		ov.impacts3d = false


# ------------------------------------------------------------------------------------------------ the writers

func _gm(x: float, z: float) -> float:
	return BoardView.ground_m(Vector2(x * ppm, z * ppm))


## A sphere of radius r (metres; sy the height's share of it) at c, painted `col` (alpha its fade).
func _ball(c: Vector3, r: float, col: Color, sy := 1.0) -> void:
	if n_sph >= SPH_MAX or col.a <= 0.01:
		return
	var o := n_sph * 16
	_sph[o] = r
	_sph[o + 1] = 0.0
	_sph[o + 2] = 0.0
	_sph[o + 3] = c.x
	_sph[o + 4] = 0.0
	_sph[o + 5] = r * sy
	_sph[o + 6] = 0.0
	_sph[o + 7] = c.y
	_sph[o + 8] = 0.0
	_sph[o + 9] = 0.0
	_sph[o + 10] = r
	_sph[o + 11] = c.z
	_sph[o + 12] = col.r
	_sph[o + 13] = col.g
	_sph[o + 14] = col.b
	_sph[o + 15] = col.a
	n_sph += 1


## A ground disc of radius r at c (ring: the ring shape), painted `col`.
func _plate(c: Vector3, r: float, col: Color, ring := false) -> void:
	if n_disc >= DISC_MAX or col.a <= 0.01:
		return
	var o := n_disc * 20
	_disc[o] = r
	_disc[o + 1] = 0.0
	_disc[o + 2] = 0.0
	_disc[o + 3] = c.x
	_disc[o + 4] = 0.0
	_disc[o + 5] = 1.0
	_disc[o + 6] = 0.0
	_disc[o + 7] = c.y + 0.08
	_disc[o + 8] = 0.0
	_disc[o + 9] = 0.0
	_disc[o + 10] = r
	_disc[o + 11] = c.z
	_disc[o + 12] = col.r
	_disc[o + 13] = col.g
	_disc[o + 14] = col.b
	_disc[o + 15] = col.a
	_disc[o + 16] = 1.0 if ring else 0.0
	_disc[o + 17] = 0.0
	_disc[o + 18] = 0.0
	_disc[o + 19] = 0.0
	n_disc += 1


## A billboard puff: code 0-3 a smoke tile, 4-7 a dust tile, 8 a soft glow (fx_smoke3d.gdshader).
func _puff(c: Vector3, r: float, a: float, code: float) -> void:
	if n_puff >= PUFF_MAX or a <= 0.01:
		return
	var o := n_puff * PUFF_STRIDE
	puffs[o] = c.x
	puffs[o + 1] = c.y
	puffs[o + 2] = c.z
	puffs[o + 3] = r
	puffs[o + 4] = a
	puffs[o + 5] = code
	n_puff += 1


# ------------------------------------------------------------------------------------------------ the frame

## Every frame before Fx3D fills its smoke buffer (Fx3D.update).
func update() -> void:
	if ov == null or sph_mmi == null:
		return
	var t0 := Time.get_ticks_usec()
	n_sph = 0
	n_disc = 0
	n_puff = 0
	n_fly = 0
	var sim = ov.sim
	var sl = view.battle.soldiers
	var now := float(sim.tick)
	if sl != null:
		now = float(sim.tick) - 1.0 + float(sl.alpha)
	var vr: Rect2 = ov._view_rect()
	_landed(sim, now, vr)
	_effects(vr)
	if sl != null:
		_flights(sim, sl, now)
	var m := sph_mmi.multimesh
	if n_sph > 0 or m.visible_instance_count > 0:
		m.buffer = _sph
		m.visible_instance_count = n_sph
	var d := disc_mmi.multimesh
	if n_disc > 0 or d.visible_instance_count > 0:
		d.buffer = _disc
		d.visible_instance_count = n_disc
	us_total += Time.get_ticks_usec() - t0


## The stones in the air (the projectile layer draws them as cards with depth): their shadows on the ground under them.
func _flights(sim, sl, now: float) -> void:
	var hi: int = mini(sl._pr_hi, sim.pr_t1.size())
	for i in hi:
		var t1: int = sim.pr_t1[i]
		if t1 < 0:
			continue
		var t0: int = sim.pr_t0[i]
		if now < float(t0) or now > float(t1) or t1 <= t0 or i >= sl._pr_code.size():
			continue
		if ((int(sl._pr_code[i]) & 15) >> 1) != 3:
			continue
		var f := (now - float(t0)) / float(t1 - t0)
		var sp := Vector2(sim.pr_sx[i], sim.pr_sy[i]) / 1024.0
		var ep := Vector2(sim.pr_x[i], sim.pr_y[i]) / 1024.0
		var g := sp.lerp(ep, f)
		var h := lerpf(float(sl._pr_hs[i]), float(sl._pr_he[i]), f) * 0.1 + 0.28 * sp.distance_to(ep) * 4.0 * f * (1.0 - f)
		_plate(Vector3(g.x, _gm(g.x, g.y), g.y), 0.5 + 0.03 * h, Color(0.0, 0.0, 0.0, 0.42 / (1.0 + 0.06 * h)))
		n_fly += 1


## The landed stones, balls and strikes of the sim's fx ring (Overlay._draw_impacts, drawn here in the scene).
func _landed(sim, now: float, vr: Rect2) -> void:
	var has_k: bool = sim.fx_k.size() == sim.fx_t.size()
	for k in sim.fx_t.size():
		var age: float = now - sim.fx_t[k]
		if age < 0.0 or age > Overlay.FX_ROLL_LIFE:
			continue
		var run_m: float = float(sim.fx_r[k]) / 1024.0 if has_k else 0.0
		var p := Vector2(sim.fx_x[k], sim.fx_y[k]) / 1024.0
		if not vr.grow(run_m * ppm).has_point(p * ppm):
			continue
		var dir := Vector2(sim.fx_dx[k], sim.fx_dy[k]) / 4096.0
		var kind: int = sim.fx_k[k] if has_k else BattleSim.FXK_STONE
		var sd: int = (sim.fx_x[k] >> 10) * 7 + (sim.fx_y[k] >> 10) * 13
		var land_dm := 0
		if sim.obs_on != 0 and (kind == BattleSim.FXK_STONE or kind == BattleSim.FXK_BURST):
			land_dm = SoldierLayer.point_dm(sim, sim.fx_x[k], sim.fx_y[k])
		if age <= Overlay.FX_TICKS and kind != BattleSim.FXK_STRIKE and kind != BattleSim.FXK_BALL_STRIKE:
			_ring(p, age / Overlay.FX_TICKS, land_dm)
		match kind:
			BattleSim.FXK_STONE:
				if land_dm > 0:
					_shatter(p, dir, float(land_dm) * 0.1, age, sd, false)
				else:
					_stone_run(p, dir, run_m, age, sd, false)
			BattleSim.FXK_BALL:
				_stone_run(p, dir, run_m, age, sd, true)
			BattleSim.FXK_STRIKE:
				_shatter(p, dir, float(sim.fx_h[k]) * 0.1, age, sd, false)
			BattleSim.FXK_BALL_STRIKE:
				_shatter(p, dir, float(sim.fx_h[k]) * 0.1, age, sd, true)


## The dust where a stone or ball came down (f 0-1 of FX_TICKS): a ring and a soft blot on the ground (or the walk it landed on)
## and a few puffs rising.
func _ring(p: Vector2, f: float, land_dm: int) -> void:
	var a := 0.85 * (1.0 - f)
	var y := _gm(p.x, p.y) + float(land_dm) * 0.1
	_plate(Vector3(p.x, y, p.y), 0.6 + 1.8 * f, Color(0.55, 0.45, 0.32, a * 0.55))
	_plate(Vector3(p.x, y, p.y), 1.0 + 2.5 * f, Color(0.85, 0.75, 0.55, a), true)
	for j in 3:
		var ang := float(j) * 2.1 + p.x
		var o := Vector2(cos(ang), sin(ang)) * (0.5 + 1.6 * f)
		_puff(Vector3(p.x + o.x, y + 0.5 + 0.9 * f, p.y + o.y), 0.7 + 1.1 * f, 0.5 * (1.0 - f), 4.0 + float(j))


## A landed stone's (ball's) run (Overlay._stone_run in the scene).
func _stone_run(p: Vector2, dir: Vector2, run_m: float, age: float, sd: int, ball: bool) -> void:
	var r := maxf(0.4 if ball else 0.45, 1.6 / (ov.zoom * ppm))
	var hop_m := run_m * 0.4 if ball and run_m > 1.25 else 0.0
	var st: Vector3 = Overlay.stone_run_at(run_m, age, ball)
	var rest_t := st.z
	var g := p + dir * st.x
	var gy := _gm(g.x, g.y)
	var hop_t := clampf(hop_m / 3.0, 2.0, 5.0) if hop_m > 0.0 else 0.0
	if ball and hop_t > 0.0 and age >= hop_t and age < hop_t + 6.0:
		var pf := (age - hop_t) / 6.0
		var f0 := p + dir * hop_m
		_puff(Vector3(f0.x, _gm(f0.x, f0.y) + 0.4 + 0.4 * pf, f0.y), 0.4 + 1.0 * pf, 0.45 * (1.0 - pf), 5.0)
	if rest_t <= 0.0:
		_plate(Vector3(g.x, gy, g.y), r * (1.3 + 0.12 * st.y), Color(0.0, 0.0, 0.0, 0.4 / (1.0 + 0.3 * st.y)))
		_ball(Vector3(g.x, gy + st.y + r, g.y), r, COL_IRON if ball else COL_STONE)
		ov.impact_stats[0] += 1
		return
	var breaks := not ball and posmod(sd, 3) != 0
	if breaks:
		if rest_t > Overlay.FX_BREAK_T:
			return
		ov.impact_stats[1] += 1
		var bf := rest_t / Overlay.FX_BREAK_T
		var a := 0.95 * clampf((1.0 - bf) * 1.6, 0.0, 1.0)
		for j in 3:
			var ang := atan2(dir.y, dir.x) + (float(j) - 1.0) * 1.1 + float(posmod(sd + j * 5, 7)) * 0.12
			var out := Vector2(cos(ang), sin(ang)) * (0.5 + 0.5 * float(j % 2)) * (0.3 + 1.6 * bf)
			var fh := 0.7 * sin(PI * minf(bf * 1.4, 1.0)) * (0.6 + 0.2 * j)
			var q := g + out
			var rr := r * (0.8 - 0.15 * j) * 0.7
			_ball(Vector3(q.x, _gm(q.x, q.y) + fh + rr, q.y), rr, Color(COL_STONE, a), 0.7)
		if rest_t < 3.0:
			_puff(Vector3(g.x, gy + r, g.y), r * (1.6 + rest_t), 0.4 * (1.0 - rest_t / 3.0), 4.0)
		return
	if rest_t > Overlay.FX_SINK_T:
		return
	ov.impact_stats[2] += 1
	var sf := rest_t / Overlay.FX_SINK_T
	var col := (COL_IRON if ball else COL_STONE).lerp(Color(0.33, 0.27, 0.2), sf * 0.7)
	col.a = 0.95 * (1.0 - sf * sf)
	var rs := r * (1.0 - 0.55 * sf)
	_ball(Vector3(g.x, gy - 0.35 * sf + rs, g.y), rs, col)


## A stone that struck a work at h metres up its face (Overlay._shatter in the scene): a burst of pale dust at the face as billboards
## (the wall in front of them hides what is behind it) and chips falling to the foot; a ball drops and rests.
func _shatter(p: Vector2, dir: Vector2, h_m: float, age: float, sd: int, ball: bool) -> void:
	if age > 30.0:
		return
	ov.impact_stats[3] += 1
	var gy := _gm(p.x, p.y)
	var r := maxf(0.45, 1.6 / (ov.zoom * ppm))
	var side := Vector2(-dir.y, dir.x)
	if age < 18.0:
		var f := age / 18.0
		var cy := gy + h_m + 0.8 * f
		var cx := p.x
		var cz := p.y
		if age < 2.0:
			_puff(Vector3(cx, cy, cz), 1.4 * (1.0 + age * 0.6), 0.85 * (1.0 - age / 2.0), 8.0)
		var fa := 1.0 - f * f
		var a1 := p - dir * 1.6 * f
		_puff(Vector3(a1.x, cy, a1.y), 1.6 + 2.6 * f, 0.7 * fa, 4.0)
		var a2 := p + side * 1.6 * f - dir * 0.9 * f
		_puff(Vector3(a2.x, cy, a2.y), 1.2 + 2.0 * f, 0.65 * fa, 6.0)
		var a3 := p - side * 1.4 * f
		_puff(Vector3(a3.x, cy + 1.5 * f, a3.y), 1.0 + 1.8 * f, 0.6 * fa, 7.0)
	var n := 3 if ball else 4
	for j in n:
		var fall_t := sqrt(maxf(2.0 * h_m / Overlay.FX_G, 0.0))
		var tt := minf(age, fall_t)
		var hz := maxf(h_m + 0.15 * tt - 0.5 * Overlay.FX_G * tt * tt, 0.0)
		var sp := 0.25 + 0.1 * float(posmod(sd + j * 3, 4))
		var lat := (float(j) - (n - 1) * 0.5) * 0.18
		var off := (-dir * sp + side * lat * 1.5) * minf(age, fall_t + 2.0)
		var a := 0.95 * clampf((30.0 - age) / 12.0, 0.0, 1.0)
		var rr := r * ((0.3 if ball else 0.62) - 0.08 * (j % 3)) * 0.8
		var q := p + off
		_ball(Vector3(q.x, _gm(q.x, q.y) + hz + rr, q.y), rr, Color(COL_STONE if not ball else Color(0.62, 0.56, 0.47), a), 0.8)
	if ball:
		var bt := sqrt(maxf(2.0 * h_m / Overlay.FX_G, 0.0))
		var hz2 := maxf(h_m - 0.5 * Overlay.FX_G * age * age, 0.0)
		var g := p - dir * 0.6 * minf(age / maxf(bt, 1.0), 1.0)
		var rb := maxf(0.4, 1.6 / (ov.zoom * ppm))
		_ball(Vector3(g.x, _gm(g.x, g.y) + hz2 + rb, g.y), rb, Color(COL_IRON, 0.95 * clampf((30.0 - age) / 10.0, 0.0, 1.0)))


## The overlay's aged effects that are dust and blast (Overlay._draw_fx's Overlay.FX_BLAST, Overlay.FX_DUST, Overlay.FX_RUIN, Overlay.FX_CHIP) as billboards with
## depth; the flames of a fire arrow stay the overlay's.
func _effects(vr: Rect2) -> void:
	for i in ov._fx_kind.size():
		var kind: int = ov._fx_kind[i]
		if kind == Overlay.FX_FIRE:
			continue
		var pp: Vector2 = ov._fx_pos[i]
		if not vr.has_point(pp):
			continue
		var p := pp / ppm
		var a: float = ov._fx_age[i]
		var gy := _gm(p.x, p.y)
		var sd := int(absf(pp.x) * 7.0 + absf(pp.y) * 13.0)
		match kind:
			Overlay.FX_BLAST:
				var rr := maxf(float(ov._fx_rad[i]), ppm * 1.5) / ppm
				if a < 0.15:
					_puff(Vector3(p.x, gy + rr * 0.4, p.y), rr * 0.95, 0.9 * (1.0 - a / 0.15), 8.0)
				if a < 0.5:
					var f := a / 0.5
					_plate(Vector3(p.x, gy, p.y), rr * (0.35 + 0.9 * f), Color(0.8, 0.7, 0.55, 0.85 * (1.0 - f)), true)
					_puff(Vector3(p.x, gy + rr * (0.3 + 0.3 * f), p.y), rr * (0.45 + 1.2 * f), 0.6 * (1.0 - f), 4.0 + float(sd % 4))
				var s := a / 3.0
				for k in 4:
					var ang := float(sd % 5) + k * 1.57
					var o := Vector2(cos(ang) * rr * 0.4 * (0.4 + s) + s, sin(ang) * rr * 0.3)
					_puff(Vector3(p.x + o.x, gy + rr * (0.3 + 1.2 * s), p.y + o.y), rr * (0.45 + 0.5 * s) * 1.1,
						0.55 * clampf(1.0 - s, 0.0, 1.0) * minf(1.0, a * 5.0), float((sd + k) % 4))
			Overlay.FX_RUIN:
				var f := a / 10.0
				var rr2 := float(ov._fx_rad[i]) / ppm
				for k in 3:
					var ang2 := float((sd + k * 5) % 9) * 0.7
					_puff(Vector3(p.x + cos(ang2) * rr2 * 0.35 + 1.5 * f * k, gy + rr2 * (0.3 + 0.3 * f), p.y + sin(ang2) * rr2 * 0.25),
						rr2 * (0.7 + 0.5 * f) * 1.1, 0.5 * (1.0 - f) * minf(1.0, a * 3.0), 4.0 + float(k))
			Overlay.FX_DUST:
				var f := a / 0.8
				_puff(Vector3(p.x, gy + 0.2 + 0.5 * f, p.y), 0.35 + 0.9 * f, 0.5 * (1.0 - f), 4.0 + float(sd % 4))
			Overlay.FX_CHIP:
				var f := a / 1.6
				var r0 := 1.0
				_puff(Vector3(p.x, gy + 0.3 + 0.6 * f, p.y), (0.6 + 1.2 * f) * r0, 0.7 * (1.0 - f), 4.0 + float(sd % 4))
				if a < 0.5:
					for k in 3:
						var ang := float((sd + k * 7) % 11) * 0.57
						var o := Vector2(cos(ang), sin(ang)) * r0 * (0.4 + 2.2 * minf(a * 3.0, 1.0))
						_ball(Vector3(p.x + o.x, gy + 0.3 + 0.5 * (1.0 - minf(a * 3.0, 1.0)), p.y + o.y), 0.12, Color(0.35, 0.3, 0.24, 0.9 * (1.0 - a / 0.5)))
