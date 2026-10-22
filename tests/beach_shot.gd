extends SceneTree
## One screenshot of the overworld's coast (beaches and cliffs; the lit landing reach with --load).
## godot --path . --resolution 1600x900 -s tests/beach_shot.gd -- --pack=west|rome --style=table|relief --focus=havana --zoom=1.2 [--load] --out=FILE.png
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
var cs
var frame := 0
var pack := "west"
var style := "table"
var focus := "havana"
var zoom := 1.2
var load_fleet := false
var show_key := false
var out := ""
var t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.get_slice("=", 1)
		elif a.begins_with("--style="):
			style = a.get_slice("=", 1)
		elif a.begins_with("--focus="):
			focus = a.get_slice("=", 1)
		elif a.begins_with("--zoom="):
			zoom = float(a.get_slice("=", 1))
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a == "--key":
			show_key = true
		elif a == "--load":
			load_fleet = true
	FogView.all_seeing = true
	MapView.load_view_pref()
	MapView.set_style(style, false)
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("new_spain" if pack == "west" else "rome")]
	var st: Dictionary = CState.new_campaign("S", 3, humans, {}, [], pack)
	st["humans"] = humans
	if load_fleet:
		var mine: Array = CFleet.fleets_of(st, humans[0])
		var fl: Dictionary = mine[0]
		var armies: Array = st["armies"]
		for i in armies.size():
			if int(armies[i]["f"]) == humans[0]:
				(fl["carry"] as Array).append(armies[i])
				armies.remove_at(i)
				break
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "beach_shot")
	root.add_child(cs)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 40:
		cs.close_dialog()
		cs.cover.visible = false
		cs.focus_region(CData.region_index(focus), zoom)
		if load_fleet:
			cs.select_fleet(int(CFleet.fleets_of(cs.ps, cs.f)[0]["id"]))
			cs.focus_region(CData.region_index(focus), zoom)
		if show_key:
			cs.map_key.persist = false   # (the pref `ui/map_key` stays as the player left it)
			cs.map_key.set_expanded(true)
		t0 = Time.get_ticks_msec()
	elif show_key and frame == 80:
		cs.map_key.scroll.scroll_vertical = 100000
	elif frame > 40 and Time.get_ticks_msec() - t0 > 1500:
		root.get_texture().get_image().save_png(out)
		quit(0)
		return true
	return false
