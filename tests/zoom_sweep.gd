extends SceneTree
## Overworld zoom / pan frame-time sweep (windowed, vsync off): prints the worst frames with the zoom they happened at.
## godot --path . --resolution 1600x900 -s tests/zoom_sweep.gd -- --pack=west|rome [--style=table|relief] [--shots=DIR] [--quick]
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const ZProf := preload("res://game/campaign/zprof.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
var cs
var frame := 0
var pack := "west"
var style := "table"
var shots := ""
var rec: Array = []      # [ms, zoom, phase, frame]
var last := 0
var plan: Array = []   # per measured frame: [phase, zoom factor, pan dx, pan dy]
var step := 0
var focus := ""
var shot_zooms := [0.5, 1.2, 2.4]
var shot_i := 0
var select_army := false
var dump_from := -1
var off_list: PackedStringArray = []
var phase_name := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--style="):
			style = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
	ZProf.on = true
	var off := ""
	for a in OS.get_cmdline_user_args():
		if a == "--select":
			select_army = true
		if a.begins_with("--dump="):
			dump_from = int(a.get_slice("=", 1))
		if a.begins_with("--off="):
			off = a.get_slice("=", 1)
	off_list = off.split(",", false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	MapView.load_view_pref()
	MapView.set_style(style, false)
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("england" if pack == "west" else "rome")]
	var st: Dictionary = CState.new_campaign("Z", 3, humans, {}, [], pack)
	st["humans"] = humans
	focus = "havana" if pack == "west" else "roma"
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "zoom_sweep")
	root.add_child(cs)
	# the script: zoom in on the focus (wheel steps of 4 %), out again, then pans at three zooms
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	# phases: [name, zoom factor (or -zoom to refocus there), pan dx, pan dy]; "refocus" frames jump the zoom (not a gesture)
	for z in [0.5, 1.2, 2.4]:
		plan.append(["refocus", -z, 0.0, 0.0])
		for i in 60:
			plan.append(["steady@%.1f" % z, 1.0, 0.0, 0.0])
	plan.append(["refocus", -0.3, 0.0, 0.0])
	for i in 120:       # a wheel notch (x1.15) every 5th frame, in then out
		plan.append(["wheel_in", 1.15 if i % 5 == 0 else 1.0, 0.0, 0.0])
	for i in 120:
		plan.append(["wheel_out", (1.0 / 1.15) if i % 5 == 0 else 1.0, 0.0, 0.0])
	for i in 100:       # a pinch / smooth zoom, x1.025 a frame
		plan.append(["pinch_in", 1.025, 0.0, 0.0])
	for i in 100:
		plan.append(["pinch_out", 1.0 / 1.025, 0.0, 0.0])
	for i in 24:        # stress: x1.25 every frame (not a real gesture)
		plan.append(["stress_x1.25", 1.25 if (i / 4) % 2 == 0 else 0.8, 0.0, 0.0])
	for z in [0.5, 1.2, 2.4]:
		plan.append(["refocus", -z, 0.0, 0.0])
		for i in 90:
			plan.append(["pan@%.1f" % z, 1.0, 14.0 * (1.0 if (i / 30) % 2 == 0 else -1.0), 9.0 * (1.0 if (i / 45) % 2 == 0 else -1.0)])

func _process(_d: float) -> bool:
	frame += 1
	if frame < 40:
		return false
	var r := CData.region_index(focus)
	if frame == 40:
		cs.dialog.visible = false
		cs.cover.visible = false
		cs.focus_region(r, 0.3)
		if select_army:
			var mine: Array = CState.armies_of(cs.ps, cs.f)
			if not mine.is_empty():
				cs.select_army(int(mine[0]["id"]))
		for o in off_list:
			match o:
				"towns": cs.town_layer.visible = false; cs.town_layer.set_process(false)
				"trees": cs.land_trees.visible = false; cs.land_trees.set_process(false)
				"minis": cs.minis.visible = false; cs.minis.set_process(false)
				"overlay": cs.overlay.visible = false
				"mapview": cs.map_view.visible = false
				"ui": cs.ui.visible = false
				"pulse": cs.map_view._pulse_node.visible = false
				"edges": cs.map_view._edges.visible = false
				"coast": cs.map_view._coast_node.visible = false
				"beach": cs.map_view._beach_node.visible = false
				"water": cs.map_view._water.visible = false
				"table": cs.map_view._table.visible = false
		last = Time.get_ticks_usec()
		return false
	if shots != "":
		return _shots()
	var now := Time.get_ticks_usec()
	var ms := float(now - last) / 1000.0
	last = now
	if step > 0:
		var rid := root.get_viewport_rid()
		rec.append([ms, cs.zoom, phase_name, step, RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_gpu(rid), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, ZProf.us.duplicate()])
	if step >= plan.size():
		_report()
		return true
	ZProf.us = {}
	var s: Array = plan[step]
	phase_name = s[0]
	var vp: Vector2 = cs._vp()
	if float(s[1]) < 0.0:
		cs.focus_region(r, -float(s[1]))
	elif float(s[1]) != 1.0:
		cs._zoom_at(vp * 0.5, float(s[1]))
	if s[2] != 0.0 or s[3] != 0.0:
		cs.offset += Vector2(float(s[2]), float(s[3]))
		cs._clamp_view()
	step += 1
	return false

var shot_t0 := 0

func _shots() -> bool:
	# a screenshot at three fixed zooms, 0.8 s after each jump (the staged redraws have all happened by then)
	var r := CData.region_index(focus)
	if shot_t0 == 0:
		cs.focus_region(r, shot_zooms[shot_i])
		shot_t0 = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - shot_t0 > 800:
		var img := root.get_texture().get_image()
		img.save_png("%s/%s_%s_z%.1f.png" % [shots, pack, style, shot_zooms[shot_i]])
		shot_i += 1
		shot_t0 = 0
		if shot_i >= 3:
			quit(0)
			return true
	return false

func _report() -> void:
	if dump_from >= 0:
		for e in rec:
			if int(e[3]) >= dump_from and int(e[3]) < dump_from + 40:
				var ls := ""
				for k in e[7]:
					ls += " %s=%.1f" % [k, float(e[7][k]) / 1000.0]
				print("  D %.1f ms (rcpu %.1f gpu %.1f) z %.3f %s |%s" % [e[0], e[4], e[5], e[1], e[2], ls])
	var over := 0
	var sum := 0.0
	var arr := rec.duplicate()
	for e in rec:
		sum += float(e[0])
		if float(e[0]) > 16.0:
			over += 1
	arr.sort_custom(func(a, b): return a[0] > b[0])
	print("SWEEP pack=", pack, " style=", style, " frames=", rec.size(), " mean=%.2f" % (sum / rec.size()), " over16=", over)
	for i in mini(14, arr.size()):
		var e: Array = arr[i]
		var ls := ""
		for k in e[7]:
			if float(e[7][k]) > 800.0:
				ls += " %s=%.1f" % [k, float(e[7][k]) / 1000.0]
		print("  %.1f ms (rcpu %.1f gpu %.1f proc %.1f) zoom %.3f %s step %d |%s" % [e[0], e[4], e[5], e[6], e[1], e[2], e[3], ls])
	var per := {}
	for e in rec:
		var k: String = e[2]
		if not per.has(k):
			per[k] = [0.0, 0, 0.0]
		per[k][0] = maxf(per[k][0], float(e[0]))
		per[k][1] += 1 if float(e[0]) > 16.0 else 0
		per[k][2] += float(e[0])
	var lsum := {}
	for e in rec:
		for k in e[7]:
			lsum[k] = float(lsum.get(k, 0.0)) + float(e[7][k]) / 1000.0
	for k in lsum:
		print("  layer %s mean %.2f ms/frame" % [k, lsum[k] / rec.size()])
	for k in per:
		var ms_arr: Array = rec.filter(func(x): return x[2] == k).map(func(x): return x[0])
		ms_arr.sort()
		print("  phase %s median %.1f p90 %.1f" % [k, ms_arr[ms_arr.size() / 2], ms_arr[ms_arr.size() * 9 / 10]])
		print("  phase %s max %.1f over16 %d mean %.2f" % [k, per[k][0], per[k][1], per[k][2] / maxf(1.0, float(rec.filter(func(x): return x[2] == k).size()))])
	quit(0)
