extends SceneTree
## Overworld town shots (windowed): the campaign screen on a new campaign of a pack, every listed town focused at every listed zoom
## and saved as <dir>/<pack>_<key>_z<zoom>.png (the towns layer settles for 0.9 s after each jump).
##   godot --path . --resolution 1600x900 -s tests/cities_shots.gd -- --pack=west|rome --focus=havana,cartagena --zooms=0.5,1.2,2.4 \
##       [--walls=3] [--level=2] [--yard=2] [--quality=low] --shots=DIR
## --walls / --level / --yard set those on the listed towns before the first frame (the plan shows them); everything is in sight.
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
var cs
var pack := "west"
var focus: PackedStringArray = []
var zooms: PackedStringArray = ["0.5", "1.2", "2.4"]
var shots := ""
var walls := -1
var level := -1
var yard := -1
var frame := 0
var ti := 0
var zi := 0
var t0 := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--pack="):
			pack = v
		elif a.begins_with("--focus="):
			focus = v.split(",", false)
		elif a.begins_with("--zooms="):
			zooms = v.split(",", false)
		elif a.begins_with("--shots="):
			shots = v
		elif a.begins_with("--walls="):
			walls = int(v)
		elif a.begins_with("--level="):
			level = int(v)
		elif a.begins_with("--yard="):
			yard = int(v)
	FogView.all_seeing = true
	MapView.load_view_pref()
	MapView.set_style("table", false)
	MapView.set_terrain_view(true, false)
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("england" if pack == "west" else "rome")]
	var st: Dictionary = CState.new_campaign("Z", 3, humans, {}, [], pack)
	st["humans"] = humans
	if focus.is_empty():
		focus = ["havana"] if pack == "west" else ["roma"]
	for k in focus:
		var r := CData.region_index(k)
		var rs: Dictionary = st["regions"][r]
		if level >= 0:
			rs["level"] = level
		for pr in [[CData.WALLS, walls], [CData.SHIPYARD, yard]]:
			if int(pr[1]) < 0:
				continue
			var found := false
			for s in rs["slots"]:
				if int(s[0]) == int(pr[0]):
					s[1] = int(pr[1])
					found = true
			if not found:
				(rs["slots"] as Array).append([int(pr[0]), int(pr[1])])
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "cities_shots")
	root.add_child(cs)

func _process(_d: float) -> bool:
	frame += 1
	if frame == 30:
		cs.close_dialog()
		cs.cover.visible = false
	if frame < 30:
		return false
	if t0 == 0:
		cs.focus_region(CData.region_index(focus[ti]), float(zooms[zi]))
		t0 = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - t0 > 900:
		var img := root.get_texture().get_image()
		img.save_png("%s/%s_%s_z%s.png" % [shots, pack, focus[ti], zooms[zi]])
		t0 = 0
		zi += 1
		if zi >= zooms.size():
			zi = 0
			ti += 1
			if ti >= focus.size():
				quit(0)
	return false
