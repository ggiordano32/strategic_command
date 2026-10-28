extends SceneTree
## Overworld frame-time attribution (windowed, vsync off): at each look_bench zoom, the steady frame with
## everything, then with one layer hidden at a time; the difference is that layer's cost. Also the draw calls,
## primitives and the process time per frame.
##   DISPLAY=:0 godot --path . --disable-vsync --resolution 2000x923 -s tests/look_prof.gd -- --pack=west|rome --style=table|relief [--zooms=1.2,0.6,0] [--n=150]
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
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

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--style="):
			style = a.get_slice("=", 1)
		elif a.begins_with("--n="):
			n = int(a.get_slice("=", 1))
		elif a.begins_with("--zooms="):
			zooms = []
			for z in a.get_slice("=", 1).split(","):
				zooms.append(float(z))
	FogView.all_seeing = true
	MapView.load_view_pref()
	MapView.set_style(style, false)
	MapView.set_terrain_view(true, false)
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("brethren" if pack == "west" else "rome")]
	var st: Dictionary = CState.new_campaign("Z", 3, humans, {}, [], pack)
	st["humans"] = humans
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "look_prof")
	root.add_child(cs)
	for zi in zooms.size():
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
		"ov_paths": return [cs.overlay._nodes[0], cs.overlay._nodes[5]]
		"ov_sites": return [cs.overlay._nodes[1]]
		"ov_fleets": return [cs.overlay._nodes[2]]
		"ov_armies": return [cs.overlay._nodes[3], cs.overlay._nodes[4]]
		"frame": return [cs.table_frame]
		"ui": return [cs.ui]
		"only_bg": return [cs.world, cs.minis, cs.overlay, cs.table_frame, cs.ui]
	return []

func _toggle(l: String, on: bool) -> void:
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
		dc = 0
		prim = 0
		proc = 0.0
	var now := Time.get_ticks_usec()
	if f >= warm and last > 0:
		ts.append(float(now - last) / 1000.0)
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
		rows.append([cs.zoom, step[1], mean, med, dc / ts.size(), prim / ts.size(), proc / ts.size()])
		print("%s %s zoom=%.3f %-16s mean=%.2f med=%.2f dc=%d prim=%d proc=%.2f" % [pack, style, cs.zoom, step[1], mean, med, dc / ts.size(), prim / ts.size(), proc / ts.size()])
		_toggle(step[1], true)
		f = 0
		pi_ += 1
	return false

func _report() -> void:
	print("--- layer cost (ms: frame with all minus frame without; median based) ---")
	var allm := {}
	for r in rows:
		if r[1] == "all" or r[1] == "all2":
			allm[r[0]] = float(allm.get(r[0], 0.0)) + float(r[3]) * 0.5
	for r in rows:
		if r[1] != "all" and r[1] != "all2":
			print("%s %s zoom=%.3f %-16s %+.2f ms  (dc %d)" % [pack, style, r[0], r[1], float(allm[r[0]]) - float(r[3]), r[4]])
