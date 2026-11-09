extends SceneTree
## The sea battle's 3D view (game/sea_view3d.gd, stage D1; docs/design/sea.md "The sea battle in 3D"), headless:
##   godot --headless --script res://tests/sea3d_test.gd
## The camera's projection of the sea plane round-trips at 0 px for 4 yaws x 3 tilts; a tap orders the selected ship to the tapped
## point at yaws 0, 120 and 240; picking by projected distance and the box select; the broadside arcs against shot_range; the map
## camera and the turn's pivot; the clamp; the 2D screen is still the default; Graphics Low builds; a sunk hull lowers and goes, a
## dismasted rig has fewer parts, a furled one fewer still; the rebind (a co-op session replacing the sim) rebuilds the sails; a frame
## of the view leaves sim.state_hash() unchanged; the layout at 844 x 390 keeps the fleets clear of the cards and the bar.

const SeaBattle := preload("res://game/sea_battle.gd")
const SeaSim := preload("res://sim/sea_sim.gd")
const Checks := preload("res://tests/sea_checks.gd")
const Quality := preload("res://game/quality.gd")

var _ok := true
var _frame := 0
var _step := 0
var sb: SeaBattle = null
var sb2: SeaBattle = null


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _make(key: String, view3d: bool, seed_v := 5) -> SeaBattle:
	var b := SeaBattle.new()
	var scn := Checks.scenario(key)
	scn["ai_sides"] = [0, 1]
	b.scenario = scn
	b.seed_value = seed_v
	b.view_3d = view3d
	b.speed_q = 0
	root.add_child(b)
	return b


func _initialize() -> void:
	sb = _make("sloops_galleon", true)


func _live_side(b: SeaBattle, side: int) -> Array[int]:
	var out: Array[int] = []
	for s in b.sim.n_units:
		if b.sim.u_side[s] == side:
			out.append(s)
	return out


func _rig_size(b: SeaBattle, s: int) -> int:
	var m: ArrayMesh = ((b.v3.ships[s]["rig"] as MeshInstance3D).mesh as ArrayMesh)
	if m.get_surface_count() == 0:
		return 0
	return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	match _step:
		0:
			_part_camera()
			_step = 1
		1:
			_part_input()
			_step = 2
		2:
			_part_ships()
			_step = 3
		3:
			_part_misc()
			root.size = Vector2i(844, 390)
			_step = 4
			_frame = 0
		4:
			if _frame < 4:
				return false
			_part_layout()
			print("RESULT: ", "PASS" if _ok else "FAIL")
			quit(0 if _ok else 1)
			return true
	return false


func _part_camera() -> void:
	var v = sb.v3
	_check(v != null and sb.camera == null and v is Node3D, "the flag builds the 3D view and no Camera2D")
	_check(v.cam != null and v.cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "an orthographic Camera3D of its own")
	_check(v.ships.size() == sb.sim.n_units, "one node set per ship (%d)" % v.ships.size())
	# The sea plane's projection round-trips at 0 px for 4 yaws x 3 tilts.
	var worst := 0.0
	var vp: Vector2 = v.vp_size()
	for yd in [0.0, 90.0, 200.0, 310.0]:
		for tl in [25.0, 45.0, 60.0]:
			v.yaw = deg_to_rad(yd)
			v.tilt = tl
			v.size = 500.0
			v.sync_camera()
			for k in 6:
				var scr := Vector2(vp.x * (0.1 + 0.15 * k), vp.y * (0.15 + 0.12 * k))
				var w: Vector2 = v.world_at(scr)
				worst = maxf(worst, scr.distance_to(v.project(w)))
	_check(worst < 0.001, "the sea plane projection round-trips (worst %.4f px)" % worst)
	# The projection agrees with the Camera3D itself.
	var wp := Vector2(1300, 800)
	var a: Vector2 = v.project(wp)
	var c3: Vector2 = v.cam.unproject_position(Vector3(wp.x, 0.0, wp.y))
	_check(a.distance_to(c3) < 0.5, "project() agrees with Camera3D.unproject_position (%.3f px)" % a.distance_to(c3))
	# The turn keeps the pivot's sea point under the finger.
	v.yaw = 0.0
	v.tilt = 45.0
	v.size = 400.0
	v.target = Vector2(1200, 800)
	v.sync_camera()
	var piv := Vector2(vp.x * 0.7, vp.y * 0.4)
	var g0: Vector2 = v.world_at(piv)
	v.turn(1.1, 0.0, piv)
	_check(v.world_at(piv).distance_to(g0) < 0.05 and absf(v.yaw - 1.1) < 0.001, "a turn about a point keeps it under the finger (%.3f m)" % v.world_at(piv).distance_to(g0))
	v.turn(0.0, 100.0, piv)
	_check(v.tilt == 60.0, "the tilt clamps at 60 degrees (%.1f)" % v.tilt)
	v.turn(0.0, -100.0, piv)
	_check(v.tilt == 25.0, "... and at 25 (%.1f)" % v.tilt)
	# Zoom: from 60 m to the whole field and margin; a zoom keeps the point under the finger.
	v.zoom_at(piv, 1e6)
	_check(is_equal_approx(v.size, 60.0), "the closest view is 60 m (%.1f)" % v.size)
	v.zoom_at(piv, 1e-6)
	_check(is_equal_approx(v.size, v.size_max()) and v.size_max() >= maxf(v.field.x, v.field.y) + 600.0 - 0.1, "the widest view is the field and its margin (%.0f m)" % v.size)
	v.size = 300.0
	v.sync_camera()
	var g1: Vector2 = v.world_at(piv)
	v.zoom_at(piv, 1.5)
	_check(v.world_at(piv).distance_to(g1) < 0.05, "zoom about a point keeps it under the finger")
	# The clamp: the field plus 300 m.
	v.target = Vector2(-9000, 9000)
	v.clamp_target()
	_check(v.target.x == -300.0 and v.target.y == v.field.y + 300.0, "the camera's target clamps to the field plus 300 m")
	v.pan_px(Vector2(-4000, 4000))
	_check(v.target.x <= v.field.x + 300.0 and v.target.y >= -300.0, "a pan is clamped too")
	# The map camera: yaw 0, tilt 85, the field; again: the camera it replaced; a turn leaves it.
	v.yaw = 2.0
	v.tilt = 33.0
	v.size = 321.0
	v.target = Vector2(900, 700)
	v.sync_camera()
	sb._map_toggle()
	_check(v.map_view and v.yaw == 0.0 and v.tilt == 85.0, "the map camera: yaw 0, tilt 85")
	var corners_in := true
	for pt in [Vector2(0, 0), Vector2(v.field.x, 0), Vector2(0, v.field.y), v.field]:
		corners_in = corners_in and Rect2(Vector2.ZERO, vp).has_point(v.project(pt))
	_check(corners_in, "the map camera shows the whole field")
	_check(sb._map_btn.button_pressed, "the compass chit is pressed in the map camera")
	sb._map_toggle()
	_check(not v.map_view and is_equal_approx(v.yaw, 2.0) and v.tilt == 33.0 and is_equal_approx(v.size, 321.0) and v.target.is_equal_approx(Vector2(900, 700)),
		"again: the camera comes back exactly")
	sb._map_toggle()
	sb._v3_turn(0.0, 10.0, vp * 0.5)
	_check(v.map_view and v.tilt == 85.0, "a tilt up does nothing in the map camera")
	sb._v3_turn(0.3, 0.0, vp * 0.5)
	_check(not v.map_view and v.tilt == 60.0 and absf(v.yaw - 0.3) < 0.001, "a turn leaves the map camera (tilt 60, yaw kept)")
	# Follow: the chit and the camera.
	var mine := _live_side(sb, 0)
	sb.selection = [mine[0]]
	sb._follow_toggle()
	_check(v.follow == mine[0] and sb._follow_btn.button_pressed, "follow the selected ship (the chit)")
	v.update(0.016)
	_check(v.target.distance_to(sb._pos(mine[0])) < v.field.length(), "the camera heads for the followed ship")
	v.pan_px(Vector2(30, 0))
	_check(v.follow == -1, "a drag lets the follow go")
	sb._center_on_ship(mine[1], true)
	_check(v.follow == mine[1], "a double tap on a card follows her")
	v.follow = -1
	# The opening camera: the player's fleet nearest the viewer, both fleets in the free part of the screen.
	v.open()
	var pm := Vector2.ZERO
	var pf := Vector2.ZERO
	for s in sb.sim.n_units:
		var sp: Vector2 = v.project(sb._pos(s))
		if sb.sim.u_side[s] == 0:
			pm += sp
		else:
			pf += sp
	pm /= 3.0
	pf /= 1.0
	_check(pm.y > pf.y, "the opening camera puts the player's fleet nearest the viewer (screen y %.0f vs %.0f)" % [pm.y, pf.y])
	var safe: Rect2 = v.safe_rect()
	var all_in := true
	for s in sb.sim.n_units:
		all_in = all_in and safe.grow(2.0).has_point(v.project(sb._pos(s), 3.0))
	_check(all_in, "both fleets are inside the free part of the screen at the opening")


func _part_input() -> void:
	var v = sb.v3
	var sim = sb.sim
	var mine := _live_side(sb, 0)
	v.map_leave(false)
	# Taps order the ship to the tapped point at yaws 0, 120 and 240 degrees.
	for yd in [0.0, 120.0, 240.0]:
		v.yaw = deg_to_rad(yd)
		v.tilt = 45.0
		v.size = 700.0
		v.target = v.field * 0.5
		v.sync_camera()
		var s0: int = mine[0]
		sb.selection = [s0]
		# A sea point in the field, away from every ship.
		var want := Vector2(1100, 760)
		var scr: Vector2 = v.project(want)
		var clear := true
		for s in sim.n_units:
			if v.ship_at(scr) != -1:
				clear = false
		if not clear:
			want = Vector2(1500, 1200)
			scr = v.project(want)
		sim.s_mode[s0] = SeaSim.M_FREE
		sb._tap(scr)
		sim.step()
		var g := Vector2(sim.s_tx[s0], sim.s_ty[s0]) / 1024.0
		_check(sim.s_mode[s0] == SeaSim.M_GOTO and g.distance_to(want) < 1.5,
			"a tap at yaw %d orders the ship to the tapped point (%.2f m off)" % [int(yd), g.distance_to(want)])
		sb._last_tap_t = -10.0
	# Picking: the ship's projected centre, within 22 px or her hull; the sea elsewhere.
	v.yaw = 0.0
	v.size = 500.0
	v.target = sb._pos(mine[0])
	v.sync_camera()
	var ok := true
	for s in sim.n_units:
		if sim.u_state[s] == SeaSim.S_SAIL:
			var c: Vector2 = v.project(sb._pos(s), 3.0)
			ok = ok and v.ship_at(c) == s and v.ship_at(c + Vector2(12, 4)) == s
	_check(ok, "ship_at picks each ship by her projected centre")
	_check(v.ship_at(Vector2(30, 600)) == -1, "... and nothing on open water")
	v.tilt = 25.0
	v.yaw = deg_to_rad(120.0)
	v.size = 1800.0
	v.target = v.field * 0.5
	v.sync_camera()
	ok = true
	for s in sim.n_units:
		var c2: Vector2 = v.project(sb._pos(s), 3.0)
		ok = ok and v.ship_at(c2) == s
	_check(ok, "a far ship is pickable on a turned, low camera")
	# The box select: a screen rectangle over projected centres.
	var box := Rect2(v.project(sb._pos(mine[0]), 3.0), Vector2.ZERO)
	for s in mine:
		box = box.expand(v.project(sb._pos(s), 3.0))
	sb._box_a = box.position - Vector2(6, 6)
	sb._box_b = box.end + Vector2(6, 6)
	sb.selection.clear()
	sb._box_select()
	var got: Array = sb.selection.duplicate()
	got.sort()
	_check(got == mine, "the box selects the player's ships inside the screen rectangle (%s)" % str(got))
	sb._box_a = Vector2(2, 2)
	sb._box_b = Vector2(10, 10)
	sb.selection = [mine[0]]
	sb._box_select()
	_check(sb.selection == [mine[0]], "an empty box keeps the selection")
	# The arcs' geometry against shot_range.
	sb.selection = [mine[0]]
	v.update(0.016)
	var arcs: Array = v.broadside_arcs(mine[0])
	var gok := arcs.size() == 2
	var hd: float = sim.heading(mine[0]) * TAU / 1024.0
	for k in arcs.size():
		var a: Dictionary = arcs[k]
		gok = gok and absf(float(a["range"]) - float(sim.shot_range(mine[0], sim.s_ld[mine[0] * 2 + k]))) < 0.01
		gok = gok and absf(float(a["half"]) - SeaSim.ARC * TAU / 1024.0) < 1e-6
		var dd := wrapf(float(a["ctr"]) - hd - (-PI * 0.5 if k == 0 else PI * 0.5), -PI, PI)
		gok = gok and absf(dd) < 1e-4
	_check(gok, "the arcs: port and starboard, perpendicular to the keel, reach = shot_range")
	var mesh := v._orders_mesh as ImmediateMesh
	var near_range := false
	if mesh.get_surface_count() > 0:
		var vs: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var pc := sb._pos(mine[0])
		var rng := float((arcs[0] as Dictionary)["range"])
		for q in vs:
			if absf(Vector2(q.x, q.z).distance_to(pc) - rng) < 6.0:
				near_range = true
				break
		_check(vs.size() >= 30 and near_range, "the order mesh carries the selected ring and arcs at the shot's reach (%d vertices)" % vs.size())
	else:
		_check(false, "the order mesh has a surface")
	var tri_y_ok := true
	if mesh.get_surface_count() > 0:
		for q in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			tri_y_ok = tri_y_ok and absf(q.y - v.ORDER_Y) < 0.001
	_check(tri_y_ok, "the order ribbons lie a little over the water")


func _part_ships() -> void:
	var v = sb.v3
	var sim = sb.sim
	var s: int = _live_side(sb, 0)[0]
	var root3: Node3D = v.ships[s]["root"]
	v.update(0.016)
	var p: Vector2 = sb._draw_pos(s)
	_check(root3.visible and absf(root3.position.x - p.x) < 0.01 and absf(root3.position.z - p.y) < 0.01 and root3.position.y > -0.5,
		"a ship's node stands at her interpolated place")
	var fwd := root3.global_transform.basis.x
	var hd: float = sb._head(s)
	_check(Vector2(fwd.x, fwd.z).normalized().distance_to(Vector2(cos(hd), sin(hd))) < 0.05, "... turned to her heading")
	var full := _rig_size(sb, s)
	_check(full > 0, "she has sails (%d vertices)" % full)
	var rig0: int = sim.s_rig[s]
	var rig_full: int = rig0
	sim.s_rig[s] = int(sim.s_rig0[s] * 0.2)
	sb.v3._clock += 1.0
	v.update(0.016)
	var torn := _rig_size(sb, s)
	_check(torn < full, "a rigging at 20 %% is fewer parts (%d < %d)" % [torn, full])
	sim.s_rig[s] = rig_full
	var sail0: int = sim.s_sail[s]
	sim.s_sail[s] = 0
	sb.v3._clock += 1.0
	v.update(0.016)
	var furled := _rig_size(sb, s)
	_check(furled < full, "hove to: the sails are furled (%d < %d)" % [furled, full])
	sim.s_sail[s] = sail0
	# A sinking hull lowers over six seconds and is gone.
	var st0: int = sim.u_state[s]
	var end0: int = sim.s_end_t[s]
	var tick0: int = sim.tick
	sim.u_state[s] = SeaSim.S_SUNK
	sim.s_end_t[s] = tick0
	sim.tick = tick0 + 30
	v.update(0.016)
	var y_half := root3.position.y
	sim.tick = tick0 + 80
	v.update(0.016)
	_check(y_half < -1.0 and not root3.visible, "a sinking hull lowers (y %.1f) and is gone after six seconds" % y_half)
	sim.tick = tick0
	sim.u_state[s] = st0
	sim.s_end_t[s] = end0
	# The ensign: white when struck.
	sim.u_state[s] = SeaSim.S_STRUCK
	v.update(0.016)
	var cols: PackedColorArray = ((v.ships[s]["flags"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var white := false
	for c in cols:
		white = white or (c.r > 0.95 and c.g > 0.95 and c.b > 0.95)
	_check(white, "a struck ship flies white")
	sim.u_state[s] = st0
	# The flags' downwind direction: the ensign streams the way the wind blows.
	v.update(0.016)
	var vs: PackedVector3Array = ((v.ships[s]["flags"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var xs := 0.0
	for q in vs:
		xs = minf(xs, q.x)
	_check(vs.size() > 0, "the flags are built (%d vertices)" % vs.size())
	# The rebind: a fresh sim (a co-op session's) rebuilds the sails.
	var ns := SeaSim.new()
	ns.setup(sb.scenario, 5)
	for i in 40:
		ns.step()
	sb._rebind(ns)
	_check(sb.sim == ns and int(v.ships[s]["sig"]) == -1, "a rebind makes the sails stale")
	sb._process(0.016)
	_check(int(v.ships[s]["sig"]) != -1 and absf((v.ships[s]["root"] as Node3D).position.x - sb._draw_pos(s).x) < 0.01,
		"the next frame rebuilds them from the new sim and stands the ships at its places")
	# A frame of the view leaves the sim's hash as it was.
	var h0: int = ns.state_hash()
	for i in 6:
		sb._process(0.016)
		sb.v3.update(0.016)
	_check(ns.state_hash() == h0 and ns.tick == 40, "a frame of the view leaves sim.state_hash() unchanged (tick %d)" % ns.tick)
	# ... and a running battle's frames only step it by the sim's own clock.
	sb.speed_q = 4
	sb.sim.ai_sides = [1, 1]
	for i in 30:
		sb._process(0.1)
	_check(ns.tick > 40, "the battle runs under the 3D view (tick %d)" % ns.tick)
	var twin := SeaSim.new()
	twin.setup(sb.scenario, 5)
	for i in 40:
		twin.step()
	twin.ai_sides = [1, 1]
	for i in ns.tick - 40:
		twin.step()
	_check(twin.state_hash() == ns.state_hash(), "the sim a 3D view ran equals one run without any view (tick %d)" % ns.tick)
	sb.speed_q = 0


func _part_misc() -> void:
	# The 2D screen is the default: no flag, no 3D.
	sb2 = _make("frigates", false)
	_check(sb2.v3 == null and sb2.camera != null, "without the flag the 2D screen is built (Camera2D, no 3D view)")
	var w2: Vector2 = sb2.world_to_screen(Vector2(100, 100))
	_check(sb2._world(w2).distance_to(Vector2(100, 100)) < 0.01, "the 2D world <-> screen helpers round-trip")
	sb2.queue_free()
	# Graphics Low builds, with the still water.
	Quality.session_low = true
	var lo := _make("coast", true)
	_check(lo.v3 != null and (lo._look.low or Quality.load_pref() == "high") and (Quality.load_pref() == "high" or float(lo._look.water3d_mat.get_shader_parameter("hi")) == 0.0), "Graphics Low builds the 3D view with the still water")
	lo._process(0.016)
	lo.v3.update(0.016)
	_check(lo.v3.water_mi.visible and (lo.v3.land_mi == null or lo.v3.land_mi.visible), "... and draws")
	lo.queue_free()
	Quality.session_low = false
	# The shore holds in the 3D view's baked fields too: water over sim land, never the reverse.
	var co := _make("coast", true)
	_check(co._look.shore_ok() and co._look.water3d_mat.get_shader_parameter("fld") != null and co._look.land3d_mat.get_shader_parameter("cells") != null,
		"the 3D materials carry the baked fields and the shore holds (shore_ok)")
	co.queue_free()
	_part_coast()
	_part_bob()
	_part_models_oars()


func _part_layout() -> void:
	# 844 x 390: the camera's chits fit the bar, and a line battle's opening fit keeps the ships out from under the cards and the bar.
	var b := SeaBattle.new()
	var scn := preload("res://tests/sea_shot.gd").line_scenario()
	scn["ai_sides"] = [0, 1]
	b.scenario = scn
	b.seed_value = 9
	b.view_3d = true
	b.speed_q = 0
	root.add_child(b)
	b.v3.open()
	var vp: Vector2 = b.get_viewport_rect().size
	var ins: Vector4 = b.hud_insets()
	var bad := 0
	for s in b.sim.n_units:
		var p: Vector2 = b.world_to_screen(b._pos(s), 3.0)
		if p.x < ins.x - 1.0 or p.y < ins.y - 1.0 or p.x > vp.x - ins.z + 1.0 or p.y > vp.y - ins.w + 1.0:
			bad += 1
	_check(bad == 0, "at %dx%d no ship of the opening fit lies under the cards, the top bar or the orders bar" % [int(vp.x), int(vp.y)])
	var yaws_ok := true
	for yd in [60.0, 130.0, 250.0]:
		b.v3.yaw = deg_to_rad(yd)
		b.v3.open_fit()
		for s in b.sim.n_units:
			var p2: Vector2 = b.world_to_screen(b._pos(s), 3.0)
			yaws_ok = yaws_ok and Rect2(Vector2(ins.x - 2.0, ins.y - 2.0), vp - Vector2(ins.x + ins.z - 4.0, ins.y + ins.w - 4.0)).has_point(p2)
	_check(yaws_ok, "... at turned yaws too")
	b.queue_free()


## D2 part 1: the coast mesh and its props.
func _part_coast() -> void:
	Quality.session_low = false
	var hi := _make("coast", true)
	var cs = hi.v3.coast
	_check(cs != null and hi.v3.land_mi != null and hi.v3.land_mi.mesh == cs.mesh, "the island scenario stands a coast mesh (land_mi)")
	_check(cs.verts > 500 and cs.verts <= cs.VERT_MAX, "the coast mesh keeps its vertex budget (%d of %d)" % [cs.verts, cs.VERT_MAX])
	# The relief rises only inland of the drawn shore, and no triangle stands over open sea (the water is never drawn over sim land
	# and the land never over sim sea: shore_ok plus the mesh's cells).
	var look = hi._look
	var arr: Array = cs.mesh.surface_get_arrays(0)
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var bad := 0
	var raised := 0
	var top := 0.0
	for i in pv.size():
		if col[i].r > 0.5:
			continue
		var p := Vector2(pv[i].x, pv[i].z)
		top = maxf(top, pv[i].y)
		if pv[i].y > cs.SHORE_Y + 0.5:
			raised += 1
			if look.sdf_at(p) > -6.0:
				bad += 1
	_check(look.shore_ok() and bad == 0 and raised > 100, "the shore holds and the relief rises only inland (%d raised, %d outside; top %.1f m)" % [raised, bad, top])
	var far_sea := 0
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for t in idx.size() / 3:
		var c := (pv[idx[t * 3]] + pv[idx[t * 3 + 1]] + pv[idx[t * 3 + 2]]) / 3.0
		if col[idx[t * 3]].r < 0.5 and look.sdf_at(Vector2(c.x, c.z)) > 25.0:
			far_sea += 1
	_check(far_sea == 0, "no land triangle stands over open sea (%d)" % far_sea)
	_check(cs.trees > 0 and cs.trees <= 600 and cs.tree_mi != null, "trees stand as cards (%d, at most 600)" % cs.trees)
	var h0: int = hi.sim.state_hash()
	hi._process(0.016)
	hi.v3.update(0.016)
	_check(hi.sim.state_hash() == h0, "the coast leaves the sim's hash unchanged")
	hi.queue_free()
	# Graphics Low: a coarser mesh and 200 trees at most (under --quality=high the session's downgrade is overridden: skipped).
	var base_low: bool = Quality.is_low()
	if base_low:
		_check(cs.trees <= 200, "Low (this run's quality): at most 200 trees (%d)" % cs.trees)
	if Quality.load_pref() != "high":
		Quality.session_low = true
		var lo := _make("coast", true)
		var cl = lo.v3.coast
		_check(cl != null and (base_low or cl.verts < cs.verts) and cl.trees <= 200, "Low: a coarser coast (%d v) and at most 200 trees (%d)" % [cl.verts, cl.trees])
		lo.queue_free()
		Quality.session_low = false
	# An open sea has no land mesh.
	var op := _make("frigates", true)
	_check(op.v3.land_mi == null, "an open sea builds no land mesh")
	op.queue_free()


## D2 part 2: the bob, the foam rings and the wakes (view only; none on Low).
func _part_bob() -> void:
	const Swell := preload("res://game/sea_swell3d.gd")
	Quality.session_low = false
	var worst_h := 0.0
	var worst_t := 0.0
	var moved := false
	var last := -99.0
	for k in 400:
		var v: Vector3 = Swell.ride(Vector2(900.0 + k * 3.7, 700.0 + k * 1.3), 0.4 + k * 0.01, k * 0.37, Vector2(1, 0.3), 0.8, 300.0)
		worst_h = maxf(worst_h, absf(v.x))
		worst_t = maxf(worst_t, maxf(absf(v.y), absf(v.z)))
		if absf(v.x - last) > 0.05:
			moved = true
		last = v.x
	_check(worst_h <= 1.5 and worst_t <= Swell.TILT_MAX + 1e-6 and moved, "the swell lifts gently (at most %.2f m, tilt %.3f rad) and moves" % [worst_h, worst_t])
	_check(Swell.ride(Vector2(100, 100), 1.0, 5.0, Vector2(1, 0), 0.8, 300.0) == Swell.ride(Vector2(100, 100), 1.0, 5.0, Vector2(1, 0), 0.8, 300.0),
		"the swell twin is a pure function of its inputs")
	var b := _make("frigates", true)
	var v3 = b.v3
	var h0: int = b.sim.state_hash()
	var ring_ok: bool = v3.bob_on == (not b._look.low)
	for s in v3.ships.size():
		if (v3.ships[s]["ring"] != null) != v3.bob_on:
			ring_ok = false
	_check(ring_ok, "a foam ring under every hull, and none on Low")
	_check(v3.water_mi.mesh is ArrayMesh == v3.bob_on and (v3.bob_on == false or (v3.water_mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 10000),
		"High: the water is a displaced grid (a flat quad on Low)")
	b.speed_q = 4
	var ymax := 0.0
	for k in 160:
		b._process(0.1)
		v3.update(0.1)
		for s in v3.ships.size():
			ymax = maxf(ymax, absf((v3.ships[s]["root"] as Node3D).position.y))
	_check(b.sim.tick > 40 and (ymax > 0.0) == v3.bob_on and ymax <= 1.5 + 0.01 and (v3.wake_quads > 0) == v3.bob_on,
		"under way the hulls bob within the limit (%.2f m) and the wakes draw (%d strips; Low: none)" % [ymax, v3.wake_quads])
	# A run under the view equals a view-less run (the bob and the wakes never touch the sim).
	var plain := _make("frigates", false)
	plain.speed_q = 4
	for k in 160:
		plain._process(0.1)
	_check(plain.sim.state_hash() == b.sim.state_hash() and h0 != b.sim.state_hash(), "the bob and the wakes leave the sim's hash as a view-less run's")
	plain.queue_free()
	b.queue_free()
	Quality.session_low = true
	var lo := _make("frigates", true)
	_check(Quality.load_pref() == "high" or (lo.v3.foam_mat == null and lo.v3.wakes_mi == null and not lo.v3.bob_on), "Low: no bob, no foam ring, no wakes")
	lo.queue_free()
	Quality.session_low = false


## D2 parts 3 and 4: the ship models and Rome's galleys' oars, ram and corvus.
func _part_models_oars() -> void:
	const SeaShip := preload("res://game/sea_ship3d.gd")
	const Oars := preload("res://game/sea_oars3d.gd")
	const ST := preload("res://sim/sea_types.gd")
	var want := ["sloop", "brigantine", "frigate", "galleon", "ship_of_the_line", "war_canoe", "lembos", "trireme", "quinquereme", "quinquereme_p"]
	var ok := SeaShip.models_ok()
	var trn := 0
	for ty in ST.ROWS.size():
		var key := SeaShip.model_key(ty)
		if key in want:
			ok = ok and SeaShip.has_model(key) and SeaShip.model(key) != null and SeaShip.model_tris(key) >= 800 and SeaShip.model_tris(key) <= 3000
			trn += SeaShip.model_tris(key)
		else:
			ok = ok and not SeaShip.has_model(key)
	_check(ok, "the ship models load for every modelled row (10, %d triangles, 800-3000 each) and the other rows keep the procedural solid" % trn)
	_check(not SeaShip.model_flat("frigate").is_empty() and (SeaShip.model_flat("frigate")["c"] as PackedColorArray).size() == SeaShip.model_tris("frigate"),
		"the land battle's shore ships read the same model (one colour a triangle)")
	Quality.session_low = false
	var b := _make("galleys", true)
	var v3 = b.v3
	var galley := -1
	for s in v3.ships.size():
		if v3.ships[s]["oars"] != null:
			galley = s
	_check(galley >= 0, "a galley has an oar bank (one MultiMesh) and the corvus ships a corvus mesh")
	var mm: MultiMesh = (v3.ships[galley]["oars"] as MultiMeshInstance3D).multimesh
	var ty: int = b.sim.s_type[galley]
	Oars.sweep(mm, ty, 2.0, 2.8, 0.0)
	var a0 := Oars.oar_transform(ty, 2.0, 2.8, 0.0, 0, 0)
	var a1 := Oars.oar_transform(ty, 2.0, 2.8, 0.4, 0, 0)
	var r0 := Oars.oar_transform(ty, 2.0, 0.0, 0.0, 0, 0)
	var r1 := Oars.oar_transform(ty, 2.0, 0.0, 7.7, 0, 0)
	_check(a0 != a1 and r0 == r1, "the oars sweep under way and are still at rest")
	var h0: int = b.sim.state_hash()
	b._process(0.016)
	v3.update(0.016)
	_check(h0 == b.sim.state_hash() and Oars.rate(b.sim, galley) >= 0.0, "the oars never touch the sim")
	var cs := -1
	for s in v3.ships.size():
		if v3.ships[s]["corvus"] != null:
			cs = s
	var stowed := Oars.corvus_mesh(b.sim.s_type[maxi(cs, 0)], 2.0, 0.0, 0.5).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var dropped := Oars.corvus_mesh(b.sim.s_type[maxi(cs, 0)], 2.0, 1.0, 0.5).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	_check(cs >= 0 and stowed.size() == dropped.size() and stowed != dropped, "the corvus is raised and drops across (different meshes)")
	v3.on_ram(0, 1)
	v3._update_splinters(0.05)
	_check(v3._splinters.size() > 0 and v3.splinters_mi.multimesh.visible_instance_count > 0, "a ram blow throws splinters")
	b.queue_free()
