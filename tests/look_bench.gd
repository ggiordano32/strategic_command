extends SceneTree
## Overworld frame-time bench (windowed, vsync off): steady frames at fixed zooms, mean and p95 of the frame time.
##   DISPLAY=:0 godot --path . --disable-vsync --resolution 2000x923 -s tests/look_bench.gd -- --pack=west|rome --style=table|relief
## Zooms: 1.2, 0.6, then the minimum (0.226 West, 0.4 Rome fit). 240 frames each after 40 warm-up frames.
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
var step := 0
var ts: Array = []
var last := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--style="):
			style = a.get_slice("=", 1)
	FogView.all_seeing = true
	MapView.load_view_pref()
	MapView.set_style(style, false)
	MapView.set_terrain_view(true, false)
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("brethren" if pack == "west" else "rome")]
	var st: Dictionary = CState.new_campaign("Z", 3, humans, {}, [], pack)
	st["humans"] = humans
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "look_bench")
	root.add_child(cs)

func _process(_d: float) -> bool:
	frame += 1
	if frame == 30:
		cs.close_dialog()
		cs.cover.visible = false
	if frame < 30:
		return false
	var f := (frame - 30) % 280
	var idx := (frame - 30) / 280
	if idx >= zooms.size():
		quit(0)
		return false
	if f == 0:
		var z: float = zooms[idx]
		cs._zoom_at(cs._vp() * 0.5, 0.001 if z == 0.0 else z / cs.zoom)
		ts = []
	var now := Time.get_ticks_usec()
	if f >= 40 and last > 0:
		ts.append(float(now - last) / 1000.0)
	last = now
	if f == 279:
		ts.sort()
		var sum := 0.0
		for t in ts:
			sum += t
		print("%s %s zoom=%.3f mean=%.2f ms p95=%.2f max=%.2f (n=%d)" % [pack, style, cs.zoom, sum / ts.size(), ts[int(ts.size() * 0.95)], ts[-1], ts.size()])
	return false
