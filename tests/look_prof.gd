extends SceneTree
## Overworld frame-time attribution (windowed, vsync off): at each look_bench zoom, the steady frame with
## everything, then with one layer hidden at a time; the difference is that layer's cost. Also the draw calls,
## primitives and the process time per frame.
##   DISPLAY=:0 godot --path . --disable-vsync --resolution 2000x923 -s tests/look_prof.gd -- --pack=west|rome --style=table|relief [--zooms=1.2,0.6,0] [--n=150] [--parts] [--fog]
## --parts: the overlay by part instead of the map's layers (markers, names, standards, last-seen, fleet markers,
## lanes; the overlay's nodes; the ships and their wakes; the fog; `sel`: an army of the player selected, its cost
## is negative: the frame with it minus the frame without; `sel+X`: selected and X hidden, also printed as X's cost
## with the army selected). --fog: the fog of war on (default: all seeing). Each zoom starts with an unreported warm-up.
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")
var cs
var frame := 0
var pack := "west"
var style := "table"
var zooms := [1.2, 0.6, 0.0]
var n := 150
var warm := 25
var plan: Array = []   # [zoom index, layer name] steps
var pi_ := 0
var f := 0
var ts: Array = []
var dc := 0
var prim := 0
var proc := 0.0
var last := 0
var base := {}
var rows: Array = []
var parts := false
var rg: Array = []   # ... and on the GPU
var rc: Array = []   # the viewport's measured render time on the CPU, ms (less hurt by other processes than the frame)
var fog := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--style="):
			style = a.get_slice("=", 1)
		elif a.begins_with("--n="):
			n = int(a.get_slice("=", 1))
		elif a == "--parts":
			parts = true
		elif a == "--fog":
			fog = true
		elif a.begins_with("--zooms="):
			zooms = []
			for z in a.get_slice("=", 1).split(","):
				zooms.append(float(z))
	FogView.all_seeing = not fog
	MapView.load_view_pref()
	MapView.set_style(style, false)
	MapView.set_terrain_view(true, false)
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("brethren" if pack == "west" else "rome")]
	var st: Dictionary = CState.new_campaign("Z", 3, humans, {}, [], pack)
	st["humans"] = humans
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "look_prof")
	root.add_child(cs)
	for zi in zooms.size():
		plan.append([zi, "warm"])   # (not reported: the first frames after a zoom or the screen's opening)
		if parts:
			for l in ["all", "overlay", "ovx_markers", "ovx_names", "ovx_standards", "ovx_lastseen", "ovx_fleets", "ovx_lanes",
					"ov_paths", "ov_sites", "ov_fleets", "ov_armies", "minis", "wakes", "fog", "all2", "sel", "sel+overlay",
					"sel+reach_pulse_sel", "sel+ui"]:
				plan.append([zi, l])
			continue
		for l in ["all", "water", "table_land", "map_own", "edges", "coast", "beach", "reach_pulse_sel",
				"land_trees", "towns", "fog", "minis", "overlay", "ov_paths", "ov_sites", "ov_fleets", "ov_armies", "frame", "ui",
				"all2", "only_bg"]:
			plan.append([zi, l])

func _nodes(l: String) -> Array:
	var mv = cs.map_view
	match l:
		"water": return [mv._water]
		"table_land": return [mv._table]
		"edges": return [mv._edges]
		"coast": return [mv._coast_node]
		"beach": return [mv._beach_node]
		"reach_pulse_sel": return [mv._reach_node, mv._pulse_node, mv._sel_node]
		"land_trees": return [cs.land_trees]
		"towns": return [cs.town_layer]
		"fog": return [cs.fog_layer]
		"minis": return [cs.minis]
		"overlay": return [cs.overlay]
		"ov_paths": return _parts(["P_PATHS", "P_TIPS"])
		"ov_sites": return _parts(["P_SITES"])
		"ov_fleets": return _parts(["P_REACH", "P_SEA", "P_FLEETS"])
		"ov_armies": return _parts(["P_GLOW", "P_ARMIES"])
		"frame": return [cs.table_frame]
		"ui": return [cs.ui]
		"wakes": return [cs.minis._under]
		"only_bg": return [cs.world, cs.minis, cs.overlay, cs.table_frame, cs.ui]
	return []

## The overlay's part nodes of these names (those the overlay has).
func _parts(names: Array) -> Array:
	var cm: Dictionary = cs.overlay.get_script().get_script_constant_map()
	var out: Array = []
	for nm in names:
		if cm.has(nm):
			out.append(cs.overlay._nodes[int(cm[nm])])
	return out


func _toggle(l: String, on: bool) -> void:
	if "+" in l:   # (several at once: "sel+overlay" an army selected and the overlay hidden)
		for part in l.split("+"):
			_toggle(part, on)
		return
	if l.begins_with("ovx_"):
		if on:
			MapOverlay.prof_off.erase(l.substr(4))
		else:
			MapOverlay.prof_off[l.substr(4)] = true
		cs.overlay.queue_redraw()
		return
	if l == "sel":
		if on:
			cs.deselect_all()
		else:
			var me: int = int(cs.st["humans"][0])
			for a in cs.st["armies"]:
				if int(a["f"]) == me:
					cs.select_army(int(a["id"]))
					break
		return
	if l == "map_own":
		if on:
			cs.map_view.queue_redraw()
		else:
			RenderingServer.canvas_item_clear(cs.map_view.get_canvas_item())
		return
	for nd in _nodes(l):
		if nd != null:
			nd.visible = on

func _process(_d: float) -> bool:
	frame += 1
	if frame == 30:
		cs.close_dialog()
		cs.cover.visible = false
	if frame < 30:
		return false
	if pi_ >= plan.size():
		_report()
		quit(0)
		return false
	var step: Array = plan[pi_]
	if f == 0:
		var z: float = zooms[step[0]]
		if pi_ == 0 or int(plan[pi_ - 1][0]) != int(step[0]):
			cs._zoom_at(cs._vp() * 0.5, 0.001 if z == 0.0 else z / cs.zoom)
		_toggle(step[1], false)
		ts = []
		rc = []
		rg = []
		dc = 0
		prim = 0
		proc = 0.0
	var now := Time.get_ticks_usec()
	if f >= warm and last > 0:
		ts.append(float(now - last) / 1000.0)
		rg.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		rc.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
		dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	last = now
	f += 1
	if f == warm + n:
		ts.sort()
		var sum := 0.0
		for t in ts:
			sum += t
		var mean := sum / ts.size()
		var med: float = ts[ts.size() / 2]
		rc.sort()
		var rmed: float = rc[rc.size() / 2]
		rg.sort()
		var gmed: float = rg[rg.size() / 2]
		if step[1] != "warm":
			rows.append([cs.zoom, step[1], mean, med, dc / ts.size(), prim / ts.size(), proc / ts.size(), rmed, gmed])
		print("%s %s zoom=%.3f %-16s mean=%.2f med=%.2f dc=%d prim=%d proc=%.2f rcpu=%.2f rgpu=%.2f" % [pack, style, cs.zoom, step[1], mean, med, dc / ts.size(), prim / ts.size(), proc / ts.size(), rmed, gmed])
		_toggle(step[1], true)
		f = 0
		pi_ += 1
	return false

func _report() -> void:
	print("--- layer cost (ms: frame with all minus frame without; median based) ---")
	var allm := {}
	var allr := {}
	var allg := {}
	var alld := {}
	for r in rows:
		if r[1] == "all" or r[1] == "all2":
			allm[r[0]] = float(allm.get(r[0], 0.0)) + float(r[3]) * 0.5
			allr[r[0]] = float(allr.get(r[0], 0.0)) + float(r[7]) * 0.5
			allg[r[0]] = float(allg.get(r[0], 0.0)) + float(r[8]) * 0.5
			alld[r[0]] = int(r[4])
	var selm := {}
	for r in rows:
		if r[1] == "sel":
			selm[r[0]] = float(r[3])
	for r in rows:
		if str(r[1]).begins_with("sel+"):
			print("%s %s zoom=%.3f %-16s %+.2f ms with an army selected" % [pack, style, r[0], str(r[1]).substr(4), float(selm[r[0]]) - float(r[3])])
	for r in rows:
		if r[1] != "all" and r[1] != "all2":
			print("%s %s zoom=%.3f %-16s %+.2f ms  render cpu %+.2f ms  gpu %+.2f ms  (dc %d, %+d)" % [pack, style, r[0], r[1], float(allm[r[0]]) - float(r[3]),
				float(allr[r[0]]) - float(r[7]), float(allg[r[0]]) - float(r[8]), r[4], int(alld[r[0]]) - int(r[4])])
