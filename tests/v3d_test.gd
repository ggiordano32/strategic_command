extends SceneTree
## The 3D battle view (docs/design/art_pipeline.md "The 3D battle view, step one"; ui.md "The 3D battle view's camera"):
##   godot --script res://tests/v3d_test.gd            (a window: the probe and the taps through the real input path)
##   godot --headless --script res://tests/v3d_test.gd (the same checks but the probe)
## 1. The board transform at yaws and tilts round-trips (a ground point's board point taken back to the ground and forward
##    again lands on the same board point, over a hill map, within 0.5 px: a point hidden behind a crest comes back as the crest,
##    which the camera sees there).
## 2. The 3D camera projects the ground where the board transform says (Camera3D.unproject_position against the canvas
##    transform x to_board, within 1 px), at three yaws, two tilts and three zooms: the overlay lies on the 3D board.
## 3. A turn keeps the ground point under its pivot (within 1 px) and the clamp holds the board in view.
## 4. Taps land where tapped: in skirmish at yaws 0, 120 and 240 (and a tilt of 30), a tap on a unit's marker selects it and a
##    tap on the ground 14 m away orders it there (the drawn destination within 1 m of the tapped ground point).
## 4b. The drag box is the screen's (2026-11-06): in skirmish at yaws 0, 120 and 240 a mouse drag draws its rectangle from the
##    screen points pressed and dragged to, and selects exactly the player's units whose marker, centre or any man projects inside
##    that screen rectangle (the men projected by the Camera3D itself), at least one inside and one outside.
## 4c. The world lamp: it stands at the opening yaw and stays as the table turns (its transform the same at yaws 0 / 90 / 200).
## 5. The layers are fed: the men's MultiMesh carries every man (12 floats each), the missiles' follows the slots in use, a West
##    town's kit rows are copied (and re-picked when the camera turns a quarter), a fort storm's poles and ram are built as a mesh.
## 6. (a window) The 3D probe sees the men drawn.
## 7. Step two (game/kit3d.gd): in a West town and a Rome city every kit piece that stood as a card is a mesh instance (as
##    many as the plan's pieces, every building the kit places among them), its card left out of the rows, and a quarter
##    turn leaves the meshes' transforms as they were (they turn with the table: no swap); every gate is rows.
## 8. The flashes and the smoke (game/fx3d.gd): billboards with depth, a billboard flash for each flash alive, at most 8 pooled
##    lights (none on Low), the overlay's own flash and smoke off.
## Exits 0 / 1.

const Battle := preload("res://game/battle.gd")
const BoardView := preload("res://game/board_view.gd")
const ConfirmOrders := preload("res://game/confirm_orders.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UiScale := preload("res://game/ui_scale.gd")
const Kit3D := preload("res://game/kit3d.gd")
const KitAtlas := preload("res://game/battlekit_atlas.gd")

var ok := true
var battle: Battle


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		ok = false


func _initialize() -> void:
	Input.use_accumulated_input = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	UiScale.load_settings()
	UiScale.size_idx = 1
	ConfirmOrders.force = "off"
	BoardView.force = "3d"
	_run.call_deferred()


func _f(n: int) -> void:
	for i in n:
		await process_frame


func _open(sc: String) -> void:
	if battle != null:
		battle.queue_free()
		await _f(2)
	battle = Battle.new()
	battle.scenario_id = sc
	battle.seed_value = 7
	battle.dive = false
	root.add_child(battle)
	await _f(4)


func _run() -> void:
	await _f(3)
	# --- 1-3 on a hill map (battle_2000's ridge)
	await _open("battle_2000")
	_check(battle.view3d != null and BoardView.v3d and BoardView.oblique, "battle_2000 opens in the 3D view")
	_check(battle.soldiers.cpu_fed and battle.soldiers.v3d_mm != null, "the men are fed from the CPU-fed buffer into the 3D MultiMesh")
	var mm: MultiMesh = battle.soldiers.v3d_mm
	_check(mm.instance_count == battle.soldiers._n_inst and mm.buffer.size() == mm.instance_count * 12,
		"the men's MultiMesh carries every man (%d instances, %d floats)" % [mm.instance_count, mm.buffer.size()])
	var worst_rt := 0.0
	var worst_px := 0.0
	var worst_piv := 0.0
	var fw: Vector2 = BoardView.field_px
	var pts: Array = []
	for j in 5:
		for i in 5:
			pts.append(Vector2(fw.x * (0.1 + 0.2 * i), fw.y * (0.1 + 0.2 * j)))
	var vp: Vector2 = battle.get_viewport_rect().size
	for yaw in [0.0, 37.0, 120.0, 240.0]:
		for tilt in [40.0, 28.0, 58.0]:
			BoardView.set_view(deg_to_rad(yaw), tilt)
			for w in pts:
				var bp := BoardView.to_board(w)
				worst_rt = maxf(worst_rt, BoardView.to_board(BoardView.to_world(bp)).distance_to(bp))
			for z in [0.3, 1.0, 3.0]:
				battle.camera.zoom = Vector2.ONE * z
				battle._cam_to(fw * 0.5)
				battle.view3d.sync_camera()
				var ct := battle.get_viewport().canvas_transform
				var cam: Camera3D = battle.view3d.cam
				for w in pts:
					var s2: Vector2 = ct * BoardView.to_board(w)
					if s2.x < 0.0 or s2.y < 0.0 or s2.x > vp.x or s2.y > vp.y:
						continue
					var p3 := Vector3(w.x / Battle.PX_PER_M, BoardView.ground_m(w), w.y / Battle.PX_PER_M)
					var s3 := cam.unproject_position(p3)   # (the viewport's canvas units, as the canvas transform's)
					worst_px = maxf(worst_px, s3.distance_to(s2))
	_check(worst_rt < 0.5, "to_world -> to_board round-trips at 4 yaws x 3 tilts over the ridge (worst %.3f board px)" % worst_rt)
	_check(worst_px < 1.0, "the 3D camera projects the ground where the board transform does (worst %.2f px over 4 yaws, 3 tilts, 3 zooms)" % worst_px)
	for k in 6:
		BoardView.set_view(0.0, 40.0)
		battle.camera.zoom = Vector2.ONE * 2.0
		battle._cam_to(fw * 0.5)
		battle.camera.force_update_scroll()
		var pv := vp * 0.5 + Vector2(vp.x * (-0.15 + 0.06 * k), vp.y * (0.1 - 0.04 * k))
		var g0: Vector2 = battle._screen_to_world(pv)
		battle._v3d_turn(deg_to_rad(23.0 + 31.0 * k), -3.0 + 2.0 * k, pv)
		battle.camera.force_update_scroll()
		var s := battle.get_viewport().canvas_transform * BoardView.to_board(g0)
		worst_piv = maxf(worst_piv, s.distance_to(pv))
	_check(worst_piv < 1.0, "a turn and a tilt keep the ground under the pivot (worst %.2f px)" % worst_piv)
	_check(BoardView.board_field().has_point(battle.camera.position), "the clamp keeps the camera over the turned board")
	# --- 4 taps in skirmish
	await _open("skirmish")
	battle._set_paused(true)
	var u := -1
	for k in battle.sim.n_units:
		if battle.sim.u_side[k] == battle.player_side and battle.sim.u_state[k] == BattleSim.U_READY:
			u = k
			break
	_check(u >= 0, "a player unit in skirmish")
	var cases := [[0.0, 40.0], [120.0, 40.0], [240.0, 30.0]]
	for cse in cases:
		BoardView.set_view(deg_to_rad(float(cse[0])), float(cse[1]))
		var c := Vector2(battle.sim.u_cx[u], battle.sim.u_cy[u]) / 1024.0 * Battle.PX_PER_M
		battle.camera.zoom = Vector2.ONE * 1.5
		battle._cam_to(c)
		battle.camera.force_update_scroll()
		await _f(2)
		battle._select(-1)
		battle._last_tap_time = -10.0
		var mp: Vector2 = root.get_final_transform() * battle.marker_screen(u)
		_tap(mp)
		await _f(3)
		_check(battle.selected == u, "yaw %d tilt %d: a tap on the unit's marker selects it" % [int(cse[0]), int(cse[1])])
		battle._last_tap_time = -10.0
		var ang := deg_to_rad(float(cse[0]) * 0.7 + 30.0)
		var gw := c + Vector2(cos(ang), sin(ang)) * 14.0 * Battle.PX_PER_M
		var gp: Vector2 = root.get_final_transform() * battle.world_to_screen(gw)
		_tap(gp)
		await _f(3)
		var ov = battle.overlay
		var dx := float(ov._v(u, "dx"))
		var dy := float(ov._v(u, "dy"))
		var want := gw / Battle.PX_PER_M * 1024.0
		var miss := Vector2(dx, dy).distance_to(want) / 1024.0
		_check(int(ov._v(u, "order")) == BattleSim.O_MOVE and miss < 1.0,
			"yaw %d tilt %d: a tap on the ground 14 m off orders the unit there (%.2f m off)" % [int(cse[0]), int(cse[1]), miss])
	await _check_box(u)
	# --- 4c the lamp stands still
	var v3 = battle.view3d
	var lt0: Transform3D = v3.lamp.transform
	var still: bool = v3.lamp_yaw > -999.0
	for yaw in [0.0, 90.0, 200.0]:
		BoardView.set_view(deg_to_rad(yaw), 40.0)
		await _f(2)
		still = still and v3.lamp.transform.is_equal_approx(lt0)
	_check(still, "the lamp stands still as the table turns (at the opening yaw %.0f)" % rad_to_deg(v3.lamp_yaw))
	# --- 5 a West town's kit and a siege's gear
	await _open("west_town")
	var kits: Array = battle.view3d.kits
	_check(kits.size() >= 1, "west_town: the kit is in the 3D view (%d kits)" % kits.size())
	if kits.size() >= 1:
		var kmm: MultiMesh = (kits[0][1] as MultiMeshInstance3D).multimesh
		var src: MultiMesh = kits[0][0].ob_mm
		_check(kmm.instance_count == src.instance_count and kmm.instance_count > 100,
			"west_town: the kit's rows copied (%d rows)" % kmm.instance_count)
		var b0 := kmm.buffer
		BoardView.set_view(deg_to_rad(90.0), 40.0)
		battle.view3d.refresh_kit()
		var b1 := kmm.buffer
		var changed := 0
		for r in kmm.instance_count:
			if b0[r * 12 + 8] != b1[r * 12 + 8]:
				changed += 1
		if not Kit3D.ok():
			_check(changed > 0, "west_town: a quarter turn re-picks the houses' renders (%d rows)" % changed)
	if Kit3D.ok():
		_check_meshes("west_town")
		await _open("siege_city")
		_check_meshes("siege_city")
	else:
		_check(false, "the kit's meshes are in assets/battlekit_ob (kit3d.res)")
	await _open("west_fort_storm")
	for t in 300:
		battle.sim.step()
	battle.view3d.refresh_kit(true)
	_check(battle.sim.n_eq > 0 and battle.view3d.gear_mi.mesh != null and battle.view3d.gear_mi.mesh.get_surface_count() > 0,
		"west_fort_storm: the siege gear is built as solids (%d pieces)" % battle.sim.n_eq)
	# --- 6 the probe
	if DisplayServer.get_name() != "headless":
		await _open("battle_2000")
		await _f(battle.view3d.PROBE_FRAMES + 12)
		_check(battle.view3d.probe_drawn > 50, "the 3D probe sees the men drawn (%d px)" % battle.view3d.probe_drawn)
	# --- 8 the flashes and the smoke (game/fx3d.gd; the flash and smoke pass)
	await _open("bench_west_muskets")
	var ov8 = battle.overlay
	var fx8 = battle.view3d.fx
	_check(fx8 != null and ov8.fx3d, "the flash and smoke layer is built and the overlay's own flash and smoke are off")
	if fx8 != null:
		var shown := -1
		var most_lit := 0
		for t in 1200:
			battle.sim.step()
			ov8._process(0.1)
			if ov8.flashes_live > 0 and shown < 0:
				fx8.update()
				shown = ov8.flashes_live
				_check(fx8.flash_drawn == shown, "bench_west_muskets: a billboard flash for each flash alive (%d of %d)" % [fx8.flash_drawn, shown])
			if shown >= 0:
				fx8.update()
				most_lit = maxi(most_lit, fx8.lights_on)
			if shown >= 0 and ov8._gs.age.size() > 60 and t > 200:
				break
		_check(shown > 0, "bench_west_muskets: the musket lines fired (%d flashes at the first volley)" % shown)
		_check(fx8.smoke_drawn > 0 and fx8.smoke_drawn == mini(fx8.smoke_drawn, fx8.SMOKE_MAX), "the smoke is drawn as billboards (%d sprites)" % fx8.smoke_drawn)
		var want_lights: bool = fx8.lights.size() > 0
		_check(most_lit <= fx8.MAX_LIGHTS and (most_lit > 0) == want_lights,
			"the pooled lights: %d at most live of %d pooled (none on Graphics Low)" % [most_lit, fx8.lights.size()])
		var spent := 0
		ov8._mf_age.fill(2000.0)
		ov8._process(0.1)
		fx8.update()
		spent = fx8.flash_drawn
		_check(spent == 0, "no flash billboard once the flashes are spent (%d)" % spent)
	BoardView.force = ""
	ConfirmOrders.force = ""
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


## 4b: a box around unit u's men (and whatever else falls in it) dragged with the mouse at three yaws.
func _check_box(u: int) -> void:
	var sim = battle.sim
	var cam: Camera3D = battle.view3d.cam
	var ft: Transform2D = root.get_final_transform()
	for cse in [[0.0, 40.0], [120.0, 40.0], [240.0, 30.0]]:
		BoardView.set_view(deg_to_rad(float(cse[0])), float(cse[1]))
		battle.camera.zoom = Vector2.ONE * 1.0
		battle._cam_to(Vector2(sim.u_cx[u], sim.u_cy[u]) / 1024.0 * Battle.PX_PER_M)
		battle.camera.force_update_scroll()
		await _f(2)
		battle._select(-1)
		battle._last_tap_time = -10.0
		# Each man where the 3D camera draws his feet (viewport px).
		var men_s := {}
		for i in sim.n:
			if sim.state[i] == BattleSim.S_DEAD or sim.state[i] == BattleSim.S_OFF:
				continue
			var w := Vector2(sim.pos_x[i], sim.pos_y[i]) / 1024.0 * Battle.PX_PER_M
			var p := cam.unproject_position(Vector3(w.x / Battle.PX_PER_M, BoardView.ground_m(w), w.y / Battle.PX_PER_M))
			var arr: PackedVector2Array = men_s.get(sim.unit_of[i], PackedVector2Array())
			arr.append(p)
			men_s[sim.unit_of[i]] = arr   # (a packed array is a value: stored back)
		var r := Rect2((men_s[u] as PackedVector2Array)[0], Vector2.ZERO)
		for p in men_s[u]:
			r = r.expand(p)
		r = r.grow(4.0)
		var want := {}
		var outside := 0
		for k in sim.n_units:
			if sim.u_side[k] != battle.player_side or sim.u_state[k] != BattleSim.U_READY:
				continue
			var c := Vector2(sim.u_cx[k], sim.u_cy[k]) / 1024.0 * Battle.PX_PER_M
			var inside := r.has_point(battle.marker_screen(k)) or r.has_point(battle.world_to_screen(c))
			for p in men_s.get(k, PackedVector2Array()):
				inside = inside or r.has_point(p)
			if inside:
				want[k] = true
			else:
				outside += 1
		_mouse(ft * r.position, true)
		await _f(1)
		for k in range(1, 6):
			_mouse_move(ft * r.position.lerp(r.end, k / 5.0))
			await _f(1)
		var ov = battle.overlay
		var drawn: bool = ov.box_on and ov.box_sa.distance_to(r.position) < 1.0 and ov.box_sb.distance_to(r.end) < 1.0
		_mouse(ft * r.end, false)
		await _f(2)
		var got := {}
		for k in battle.selection:
			got[k] = true
		var same := got.size() == want.size()
		for k in want:
			same = same and got.has(k)
		_check(drawn, "yaw %d tilt %d: the drag box is the screen's rectangle as dragged" % [int(cse[0]), int(cse[1])])
		_check(same and want.has(u) and outside > 0,
			"yaw %d tilt %d: the drag box selects the units projecting inside the screen rectangle (%d selected, %d wanted, %d outside)" % [int(cse[0]), int(cse[1]), got.size(), want.size(), outside])
	battle._select(-1)


func _mouse(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)


func _mouse_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _check_meshes(sc: String) -> void:
	var v3 = battle.view3d
	BoardView.set_view(0.0, 40.0)
	v3.refresh_kit(true)
	var want := 0
	var blds := {}
	var lms := 0
	for e in v3.kits:
		var k = e[0]
		for i in k.i_piece.size():
			if i < k._ob_slot.size() and k._ob_slot[i] >= 0 and not k.fallen(i):
				want += 1
				if k.i_bld[i] >= 0:
					blds[k.i_bld[i]] = 1
		for lm in k._ob_lm:
			if (lm as Array).size() >= 6:
				lms += 1
	var got := 0
	var got_b := {}
	var hidden := true
	for km in v3.kit_meshes:
		var k = km["kit"]
		for i in km["inst"]:
			if not k.fallen(i):
				got += 1
				if k.i_bld[i] >= 0:
					got_b[k.i_bld[i]] = 1
		var mm: MultiMesh = null
		for e in v3.kits:
			if e[0] == k:
				mm = (e[1] as MultiMeshInstance3D).multimesh
		for i in km["inst"]:
			var sl: int = k._ob_slot[i]
			if mm != null and sl >= 0 and mm.buffer[sl * 12 + 8] != 0.0:
				hidden = false
		got += (km["lm"] as Array).size()
	_check(want + lms > 20 and got == want + lms and v3.mesh_instances == want + lms,
		"%s: every card piece is a mesh (%d meshes drawn, %d instances, the plan's %d pieces + %d landmarks)" % [sc, v3.mesh_instances, got, want, lms])
	_check(got_b.size() == blds.size() and blds.size() > 10, "%s: every building the kit places is a mesh (%d of %d)" % [sc, got_b.size(), blds.size()])
	_check(hidden, "%s: the meshed pieces' cards are left out of the kit's rows" % sc)
	var gates_rows := true
	for e in v3.kits:
		var k = e[0]
		for i in k.i_piece.size():
			if k.i_gate[i] >= 0 and i < k._ob_slot.size() and k._ob_slot[i] >= 0:
				gates_rows = false
	_check(gates_rows, "%s: every gate is real geometry (no gate card)" % sc)
	# a house turns with the table: its transform is the same at every yaw, its mesh the same (no swap)
	var mi: MultiMeshInstance3D = null
	for km in v3.kit_meshes:
		for nm in km["mmis"]:
			var m: MultiMeshInstance3D = km["mmis"][nm]
			if m.multimesh.instance_count > 0 and (str(nm).begins_with("house") or str(nm) in ["tavern", "shop", "store", "warehouse"]):
				mi = m
				break
		if mi != null:
			break
	_check(mi != null, "%s: a house kind drawn as a MultiMesh of meshes" % sc)
	if mi == null:
		return
	var t0 := mi.multimesh.get_instance_transform(0)
	var mesh0 := mi.multimesh.mesh
	var tris := mesh0.get_faces().size() / 3
	var same := true
	for yaw in [37.0, 90.0, 180.0, 271.0]:
		BoardView.set_view(deg_to_rad(yaw), 40.0)
		v3.sync_camera()
		v3.refresh_kit()
		if not mi.multimesh.get_instance_transform(0).is_equal_approx(t0) or mi.multimesh.mesh != mesh0:
			same = false
	_check(same, "%s: %s turns with the table (its transform and mesh unchanged at yaws 37 / 90 / 180 / 271; %d triangles)" % [sc, mi.name, tris])
	_check(tris >= 12 and tris <= 3000, "%s: %s is low poly (%d triangles)" % [sc, mi.name, tris])
	BoardView.set_view(0.0, 40.0)


func _tap(p: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = p
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventScreenTouch.new()
	r.index = 0
	r.position = p
	r.pressed = false
	Input.parse_input_event(r)
