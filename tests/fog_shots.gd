extends SceneTree
## Fog of war screenshots (windowed): godot --path . --resolution 1600x900 -s tests/fog_shots.gd -- --pack=west|rome
## --out=DIR [--turns=N] [--fog=0] [--select]. N turns are played with the player's faction holding (empty plans) so the
## memory has markers; shots: the whole map, zoomed on the player's border, and with an army selected.
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")

var cs
var out := "/tmp"
var tag := ""
var n := 0
var _fr := 0


func _initialize() -> void:
	var pack := "west"
	var turns := 4
	var fog := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--turns="):
			turns = int(a.get_slice("=", 1))
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--fog="):
			fog = int(a.get_slice("=", 1))
	tag = "%s_t%d%s" % [pack, turns, "" if fog == 1 else "_nofog"]
	MapView.load_view_pref()
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("england" if pack == "west" else "rome")]
	var st := CState.new_campaign("T", 3, humans, {"fog": fog}, [], pack)
	for t in turns:
		st = CTurn.resolve_turn(st, [])
		while not (st["battles"] as Array).is_empty():
			var b: Dictionary = st["battles"][0]
			st = CTurn.apply_battle(st, int(b["id"]), CBattle.formula(st, b))
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {"%d" % humans[0]: int(st["turn"])}}}, "fog_shots")
	root.add_child(cs)


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var p := "%s/%s_%s.png" % [out, tag, name]
	img.save_png(p)
	print("saved ", p)


func _process(_d: float) -> bool:
	_fr += 1
	if _fr == 40:
		cs.close_dialog()
		cs.zoom = 0.45
		cs.focus_region(CData.region_index(str(CData.FACTIONS[cs.f]["capital"])), 0.45)
	elif _fr == 80:
		_shot("whole")
		cs.focus_region(CData.region_index(str(CData.FACTIONS[cs.f]["capital"])), 1.3)
	elif _fr == 120:
		_shot("zoom")
		var mine: Array = CState.armies_of(cs.ps, cs.f)
		if not mine.is_empty():
			cs.select_army(int(mine[0]["id"]))
	elif _fr == 160:
		_shot("selected")
		return true
	return false
