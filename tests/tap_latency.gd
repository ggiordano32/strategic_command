extends SceneTree
## Overworld tap latency on a desktop (windowed, vsync off): game/campaign/tap_prof.gd drives the taps and
## prints the table (lines "TAPPROF ...").
## godot --path . --resolution 1600x900 -s tests/tap_latency.gd -- --pack=west|rome [--turns=10] [--prof-tap=5] [--prof-tap-ablate]
## --turns=N: N turns played by the AI first (no human), then the player's faction takes over.
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const TapProf := preload("res://game/campaign/tap_prof.gd")

var cs


func _initialize() -> void:
	var pack := "west"
	var turns := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--turns="):
			turns = int(a.get_slice("=", 1))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	MapView.load_view_pref()
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("england" if pack == "west" else "rome")]
	var st: Dictionary
	if turns > 0:
		st = CState.new_campaign("T", 3, [], {}, [], pack)
		for t in turns:
			st = CTurn.resolve_turn(st, [])
	else:
		st = CState.new_campaign("T", 3, humans, {}, [], pack)
	st["humans"] = humans
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "tap_latency")
	root.add_child(cs)   # (its _ready, at the first frame, adds the driver when --prof-tap is given)
	if TapProf.wanted() == "":
		var tp := TapProf.new(cs, "5")
		cs.add_child(tp)


func _process(_d: float) -> bool:
	var tp: Node = cs.get_node_or_null("tap_prof")
	return tp != null and not tp.is_processing() and tp.frame > 0
