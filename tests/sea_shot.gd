extends SceneTree
## The sea battle screen's shots and frame cost (docs/design/sea.md "The sea battle in 3D"; needs a window):
##   godot --script res://tests/sea_shot.gd -- --out=PNG [--sc=frigates|coast|line|havana|fireship|galleys] [--view=3d|2d]
##     [--size=1280x720] [--ticks=N] [--yaw=DEG] [--tilt=DEG] [--map] [--follow] [--select=all|none] [--size-m=METRES]
##     [--quality=high|low] [--bench=SECONDS] ("SEA_BENCH {...}": the mean / p95 frame time and the draw calls over that many seconds
##     after a 3 s warm-up, the battle running at 1 x)
const SeaBattle := preload("res://game/sea_battle.gd")
const Quality := preload("res://game/quality.gd")
const Checks := preload("res://tests/sea_checks.gd")
const UiScale := preload("res://game/ui_scale.gd")
const CData := preload("res://campaign/cdata.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const PackView := preload("res://game/campaign/pack_view.gd")

var out := ""
var sc := "frigates"
var view := "3d"
var size := Vector2i(1280, 720)
var ticks := 0
var yaw := -999.0
var tilt := -1.0
var size_m := 0.0
var map := false
var follow := false
var select := ""
var bench := 0.0
var at := Vector2(-1, -1)
var hide_hud := false
var quality := ""
var run_frames := 0
var at_ship := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v
		elif a.begins_with("--sc="): sc = v
		elif a.begins_with("--view="): view = v
		elif a.begins_with("--size="): size = Vector2i(int(v.get_slice("x", 0)), int(v.get_slice("x", 1)))
		elif a.begins_with("--ticks="): ticks = int(v)
		elif a.begins_with("--yaw="): yaw = float(v)
		elif a.begins_with("--tilt="): tilt = float(v)
		elif a.begins_with("--size-m="): size_m = float(v)
		elif a == "--map": map = true
		elif a == "--follow": follow = true
		elif a.begins_with("--select="): select = v
		elif a.begins_with("--bench="): bench = float(v)
		elif a.begins_with("--at="): at = Vector2(float(v.get_slice(",", 0)), float(v.get_slice(",", 1)))
		elif a == "--no-hud": hide_hud = true
		elif a.begins_with("--run="): run_frames = int(v)
		elif a.begins_with("--atship="): at_ship = int(v)
		elif a.begins_with("--quality="): quality = v
	_run.call_deferred()


func _f(n: int) -> void:
	for i in n:
		await process_frame


## A line battle by a coast: four ships a side, the land on the west.
static func line_scenario() -> Dictionary:
	var scn := Checks.scenario("coast")
	var u: Array = []
	for i in 4:
		u.append({"side": 0, "t": "galleon" if i == 0 else "frigate" if i < 3 else "brigantine"})
		u.append({"side": 1, "t": "ship_of_the_line" if i == 0 else "frigate" if i < 3 else "sloop"})
	scn["units"] = u
	return scn


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
	if quality == "low":
		Quality.session_low = true
	var b = SeaBattle.new()
	var cell := Vector2i(-1, -1)
	var region := -1
	match sc:
		"line":
			b.scenario = line_scenario()
		"havana":
			PackView.use_pack("west")
			for i in CData.REGIONS.size():
				if str(CData.REGIONS[i]["key"]) == "havana":
					region = i
			var c := CFleet.dock(region)
			cell = Vector2i(CGrid.cx(c), CGrid.cy(c))
			var scn := line_scenario()
			scn["land"] = {"kind": 2, "dirs": 6, "mseed": 69729}
			b.scenario = scn
		_:
			b.scenario = Checks.scenario(sc)
	b.scenario["ai_sides"] = [0, 1]
	b.seed_value = 7
	b.look_cell = cell
	b.look_region = region
	b.view_3d = view == "3d"
	b.speed_q = 0
	root.add_child(b)
	await _f(6)
	if b.v3 != null and b.v3.coast != null:
		var cs = b.v3.coast
		print("COAST verts %d tris %d trees %d kit_instances %d kit_tris %d forts %d" % [cs.verts, cs.tris, cs.trees, cs.kit_instances, cs.kit_tris, b._look.forts.size()])
		print("FORTS ", b._look.forts)
	b.sim.ai_sides[0] = 1
	for t in ticks:
		b.sim.step()
	b._snap_prev()
	if b.v3 != null:
		if yaw > -998.0:
			b.v3.yaw = deg_to_rad(yaw)
			b.v3.set_lamp(b.v3.yaw)
			b.v3.open_fit()
		if tilt > 0.0:
			b.v3.tilt = tilt
		if size_m > 0.0:
			b.v3.size = size_m
		if at.x >= 0.0:
			b.v3.target = at
		b.v3.sync_camera()
		if map:
			b._map_toggle()
		if follow:
			b._follow_toggle()
	if select == "all":
		b.selection.clear()
		for s in b.sim.n_units:
			if b.sim.u_side[s] == b.player_side:
				b.selection.append(s)
	elif select == "none":
		b.selection.clear()
	b._refresh_bar()
	if bench > 0.0:
		b.speed_q = 4
	if run_frames > 0:
		b.speed_q = 4
		await _f(run_frames)
		b.speed_q = 0
	if b.v3 != null and run_frames > 0:
		print("WAKE quads ", b.v3.wake_quads, " pts ", b.v3.ships[0]["wake"].size(), " ", "", " tick ", b.sim.tick)
	if at_ship >= 0 and b.v3 != null:
		b.v3.target = b._pos(at_ship)
		b.v3.size = size_m if size_m > 0.0 else 160.0
		b.v3.sync_camera()
	if hide_hud:
		for ch in b.get_children():
			if ch is CanvasLayer or ch is Control:
				ch.visible = false
	await _f(20)
	if out != "":
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
	if bench > 0.0:
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
		frames.sort()
		var mean := 0.0
		for f in frames:
			mean += f
		mean /= maxf(frames.size(), 1)
		var res := {"sc": sc, "view": view, "size": "%dx%d" % [size.x, size.y], "frames": frames.size(), "mean_ms": snappedf(mean, 0.01),
			"p95_ms": snappedf(frames[int(frames.size() * 0.95)] if frames.size() > 0 else 0.0, 0.01),
			"gpu_ms": snappedf(gpu / maxf(ng, 1), 0.01), "draws": draws, "ships": b.sim.n_units}
		print("SEA_BENCH ", JSON.stringify(res))
	quit(0)
