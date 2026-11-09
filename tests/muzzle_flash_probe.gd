extends SceneTree
## The muzzle flash against the sim (docs/design/art_pipeline.md "The muzzle flash is the man's own"): a musket line, a pistol
## brace of cavalry, a bow line and a field gun fire at a standing target; after every tick the sim's shots (missiles started this
## tick by a gun man, from the sim's arrays) are compared with the flashes the view shows, and with the men the old unit-wide
## flag would have lit (alive men of a gun unit that fired in the last FLASH_TICKS ticks). Prints a table; exit 1 on a failure.
##   godot --path . [--headless] -s tests/muzzle_flash_probe.gd -- [--cpu] [--oblique] [--shots=DIR] [--ticks=700]
const Battle := preload("res://game/battle.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const UT := preload("res://sim/unit_types.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
var cpu := false
var shots := ""
var ticks := 700
var fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	cpu = "--cpu" in args
	BoardView.force = "oblique" if "--oblique" in args else ("top" if "--top" in args else "3d")   # (3D by default; the flat views are a developer aid)
	for a in args:
		if a.begins_with("--shots="): shots = a.get_slice("=", 1)
		if a.begins_with("--ticks="): ticks = int(a.get_slice("=", 1))
	_run.call_deferred()


func _u(side: int, key: String, n: int, x: int, y: int, face: int, extra := {}) -> Dictionary:
	var d := Scenarios.unit(side, UT.index_of(key), n, x, y, face)
	for k in extra:
		d[k] = extra[k]
	return d


func _case(name: String, units: Array, orders: Array) -> void:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units, "orders": orders}
	var b := Battle.new()
	b.custom_scenario = sc
	b.seed_value = 3
	root.add_child(b)
	for i in 6:
		await process_frame
	b.paused = true
	b.hud.visible = false
	if b.dive_t >= 0.0:
		b.dive_finish()
	b.soldiers.set_cpu_fed(cpu)
	var s = b.sim
	var ov = b.overlay
	var fire_ticks := 0
	var max_fire := 0
	var max_flash := 0
	var max_before := 0
	var bad := 0          # ticks where the flashes shown differ from the sim's shots
	var stale := 0        # flash-lit units, men on a unit flag, left over (must stay 0)
	var arrows := 0       # missiles of men without powder, started in the run
	for t in ticks:
		s.step()
		b.soldiers.upload()
		ov._process(0.13)   # (a tick is 0.1 s: last tick's flash has faded)
		var fired := 0
		for p in s.pr_t1.size():
			if s.pr_t1[p] >= 0 and s.pr_t0[p] == s.tick - 1 and s.t_m_gun[s.pr_ty[p]] != 0 and s.t_cls[s.pr_ty[p]] != UT.CLS_ART:
				fired += 1
		for p in s.pr_t1.size():
			if s.pr_t1[p] >= 0 and s.pr_t0[p] == s.tick - 1 and s.t_m_gun[s.pr_ty[p]] == 0:
				arrows += 1
		var art := 0
		for p in s.pr_t1.size():
			if s.pr_t1[p] >= 0 and s.pr_t0[p] == s.tick - 1 and s.t_cls[s.pr_ty[p]] == UT.CLS_ART:
				art += 1
		var shown: int = ov.flashes_live
		for k in ov._gs.age.size():
			if ov._gs.fl[k] != 0 and ov._gs.age[k] < 0.09:
				shown += 1
		fired += art
		var before := 0   # the old rule: the unit flag
		for u in s.n_units:
			var ty: int = s.u_type[u]
			if s.t_m_gun[ty] != 0 and s.t_cls[ty] != UT.CLS_ART and s.tick - ov.shot_t[u] < SoldierLayer.FLASH_TICKS if ov.shot_t.size() > u else false:
				before += s.u_alive[u]
		for u in s.n_units:
			if b.soldiers._flags[u] & SoldierLayer.F_FIRED != 0:
				stale += 1
		if fired > 0:
			fire_ticks += 1
			if fired > max_fire:
				max_fire = fired
				max_flash = shown
				max_before = before
		if shown != fired:
			bad += 1
		if fired > 0 and shots != "" and fire_ticks == 2:
			await _shoot(b, name, "fire")
	# a second later: nothing left
	for i in 10:
		ov._process(0.1)
	var left: int = ov.flashes_live
	print("%-10s %s %s fire ticks %3d | shots in the sim on the biggest tick %3d | flashes shown %3d | before (unit flag) %4d | ticks with shown != shots %d | a second later %d | F_FIRED units %d" % [name, "cpu" if cpu else "gpu", BoardView.force, fire_ticks, max_fire, max_flash, max_before, bad, left, stale])
	if bad > 0 or left != 0 or stale > 0:
		fails += 1
	if name == "bows":
		print("  bows: %d arrows loosed, %d flashes made" % [arrows, ov.flashes_made])
	if name == "bows" and (arrows == 0 or ov.flashes_made != 0):
		fails += 1
	elif name != "bows" and fire_ticks == 0:
		fails += 1
	b.queue_free()
	await process_frame


func _shoot(b, name: String, tag: String) -> void:
	if not DisplayServer.get_name() != "headless":
		return
	b.soldiers.set_alpha(1.0)
	b._view_tick()
	b.camera.zoom = Vector2.ONE * 7.0
	var s = b.sim
	var c := Vector2.ZERO
	var n := 0
	for u in s.n_units:
		if s.u_side[u] == 0:
			c += Vector2(s.u_cx[u], s.u_cy[u]) / 1024.0
			n += 1
	b._cam_to((c / maxf(n, 1.0) + Vector2(0, -3.0)) * Battle.PX_PER_M)
	b.camera.force_update_scroll()
	b.overlay._mf_age.fill(0.0)   # (the flash held at full strength for the shot: it is a still of the fire tick)
	b.overlay._mf_life.fill(1000.0)
	for i in 3:
		b.overlay.queue_redraw()
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s_%s.png" % [shots, name, tag, "cpu" if cpu else "gpu", BoardView.force])
	b.overlay._mf_age.fill(2000.0)   # (spent: the next tick's aging drops them)


func _run() -> void:
	await _case("musket", [_u(0, "musketeers", 100, 150, 200, 768), _u(1, "heavy", 100, 150, 130, 256)],
		[Scenarios.attack(0, 0, 1, 0)])
	await _case("pistol", [_u(0, "pistoleers", 60, 150, 250, 768, {"ammo_pct": 100}), _u(1, "heavy", 100, 150, 130, 256)],
		[Scenarios.attack(0, 0, 1, 1)])
	await _case("bows", [_u(0, "archer", 80, 150, 200, 768), _u(1, "heavy", 100, 150, 140, 256)],
		[Scenarios.attack(0, 0, 1, 0)])
	await _case("gun", [_u(0, "field_gun", 12, 150, 230, 768), _u(1, "heavy", 100, 150, 130, 256)],
		[Scenarios.attack(0, 0, 1, 0)])
	print("muzzle_flash_probe: ", "FAIL" if fails > 0 else "PASS")
	quit(1 if fails > 0 else 0)
