extends SceneTree
## The 3D battle view's shots and frame cost (docs/design/art_pipeline.md "The 3D battle view, step one"; needs a window):
##   godot --script res://tests/v3d_shot.gd -- --out=/tmp/a.png [--view=3d|oblique|top] [--sc=battle_2000] [--seed=7]
##     [--ticks=300] [--z=ZOOM|fit] [--yaw=DEG] [--tilt=DEG] [--size=1280x720] [--nohud] [--cu=UNIT] [--cam=x_m,y_m]
##     [--bench=SECONDS] (the mean / p95 frame time and the draw calls over that many seconds after a 3 s warm-up, the battle
##     running at 1 x; one JSON line "V3D_BENCH {...}") [--run] (the battle unpaused while shooting) [--quality=high|low]
##     [--shore] (a port town with three ships off its shore instead of --sc) [--town[=dx,dy]] (the camera on the town)
const Battle := preload("res://game/battle.gd")
const BoardView := preload("res://game/board_view.gd")
const UiScale := preload("res://game/ui_scale.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const CData := preload("res://campaign/cdata.gd")

var out := ""
var sc := "battle_2000"
var seed_v := 7
var ticks := 300
var zoom := 0.0
var hud := true
var cu := -1
var cam := Vector2(-1, -1)
var view := "3d"
var yaw := -999.0
var tilt := -1.0
var size := Vector2i(1280, 720)
var bench := 0.0
var run := false
var shore := false
var siege := ""
var town := Vector2(-1, -1)   # --town[=dx,dy]: the camera on the town's buildings' middle (+ an offset, m)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v
		elif a.begins_with("--sc="): sc = v
		elif a.begins_with("--seed="): seed_v = int(v)
		elif a.begins_with("--ticks="): ticks = int(v)
		elif a.begins_with("--z="): zoom = float(v) if v != "fit" else 0.0
		elif a == "--nohud": hud = false
		elif a.begins_with("--cu="): cu = int(v)
		elif a.begins_with("--cam="): cam = Vector2(float(v.get_slice(",", 0)), float(v.get_slice(",", 1)))
		elif a.begins_with("--view="): view = v
		elif a.begins_with("--yaw="): yaw = float(v)
		elif a.begins_with("--tilt="): tilt = float(v)
		elif a.begins_with("--size="): size = Vector2i(int(v.get_slice("x", 0)), int(v.get_slice("x", 1)))
		elif a.begins_with("--bench="): bench = float(v)
		elif a == "--run": run = true
		elif a == "--town": town = Vector2.ZERO
		elif a.begins_with("--town="): town = Vector2(float(v.get_slice(",", 0)), float(v.get_slice(",", 1)))
		elif a == "--shore": shore = true   # (a port town with a fleet off its shore: Scenarios.shore_battle)
	BoardView.force = view
	_run.call_deferred()


func _f(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var phone := size.x < 1000 or size.y < 500
	UiScale._dpr_override = 3.0 if phone else 1.0
	UiScale._touch_override = 1 if phone else 0
	DisplayServer.window_set_size(size)
	root.size = size
	await _f(4)
	UiScale.apply(root)
	if bench > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _f(4)
	var b = Battle.new()
	b.scenario_id = sc
	b.seed_value = seed_v
	if shore:
		CData.use_pack("west")
		b.custom_scenario = Scenarios.shore_battle(1, 0, [0])
		b.player_side = 1
	b.dive = false
	root.add_child(b)
	await _f(6)
	b.sim.ai_sides[0] = 1
	b._set_paused(true)
	for t in ticks:
		b.sim.step()
	b.soldiers.upload()
	b.soldiers.set_alpha(1.0)
	b._view_tick()
	if b.view3d != null:
		if yaw > -998.0 or tilt > 0.0:
			BoardView.set_view(deg_to_rad(yaw) if yaw > -998.0 else BoardView.yaw, tilt if tilt > 0.0 else BoardView.elev_deg)
		b._fit_camera()
	if zoom > 0.0:
		var c := b.get_viewport_rect().size * 0.5
		b._zoom_at(c, zoom / b.camera.zoom.x)
	if shore and cu < 0 and cam.x < 0.0 and b.sim.shp_on != 0:
		b._cam_to(Vector2(b.sim.sh_x[0], b.sim.sh_y[0]) / 1024.0 * Battle.PX_PER_M)
	elif town.x > -1.0 and b.sim.map_info is Dictionary and (b.sim.map_info as Dictionary).has("city"):
		var bl: Array = (b.sim.map_info["city"] as Dictionary).get("buildings", [])
		var mid := Vector2.ZERO
		for r in bl:
			mid += Vector2(float(int(r[0]) + int(r[2])), float(int(r[1]) + int(r[3]))) * 0.5
		mid /= maxf(float(bl.size()), 1.0)
		b._cam_to((mid + town) * Battle.PX_PER_M)
	elif cu >= 0:
		b._cam_to(Vector2(b.sim.u_cx[cu], b.sim.u_cy[cu]) / 1024.0 * Battle.PX_PER_M)
	elif cam.x >= 0.0:
		b._cam_to(cam * Battle.PX_PER_M)
	b.hud.visible = hud
	if run:
		b._set_paused(false)
	await _f(20)
	if out != "":
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
	if bench > 0.0:
		b._set_paused(false)
		var vp := root.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3000:
			await process_frame
		var frames := PackedFloat64Array()
		var gpu := 0.0
		var ng := 0
		var last := Time.get_ticks_usec()
		var t1 := Time.get_ticks_msec()
		var draws := 0
		var prims := 0
		while Time.get_ticks_msec() - t1 < int(bench * 1000.0):
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
			var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
			if g > 0.0:
				gpu += g
				ng += 1
			draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			prims = maxi(prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		var s := frames.duplicate()
		s.sort()
		var tot := 0.0
		for x in s:
			tot += x
		var men := 0
		for u in b.sim.n_units:
			men += int(b.sim.u_alive[u])
		var res := {"view": view, "sc": sc, "w": size.x, "h": size.y, "frames": s.size(), "avg_ms": snappedf(tot / maxf(s.size(), 1), 0.01),
			"p95_ms": snappedf(s[mini(s.size() - 1, int(s.size() * 0.95))] if s.size() > 0 else 0.0, 0.01),
			"gpu_ms": snappedf(gpu / maxf(ng, 1), 0.01), "draws": draws, "prims": prims, "men": men,
			"zoom": snappedf(b.camera.zoom.x, 0.001), "tick": b.sim.tick}
		print("V3D_BENCH ", JSON.stringify(res))
	quit(0)
