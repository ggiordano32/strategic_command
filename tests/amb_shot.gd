extends SceneTree
## The ambush deployment (docs/design/campaign_rules.md "Ambush battles"): a West field battle with the Spanish
## column caught on a forced march, the deployment phase on the battle screen, saved as a PNG (windowed):
##   godot --path . --resolution 1280x720 -s tests/amb_shot.gd -- --out=FILE.png [--battle-view=oblique] [--app=4]
const Battle := preload("res://game/battle.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const UT := preload("res://sim/unit_types.gd")

var battle: Battle
var out := "user://ambush_deploy.png"
var app := 4
var frame := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--app="):
			app = int(a.get_slice("=", 1))
	CData.use_pack("west")
	var ns := CData.faction_index("new_spain")
	var iz := CData.faction_index("itza")
	var st := CState.new_campaign("t", 91, [iz], {}, [], "west")
	st["armies"] = []
	st["settings"]["deploy_time"] = 60
	var site := CGrid.site(CData.region_index("havana"))
	var dc := -1
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var k := CGrid.at(CGrid.cx(site) + dx, CGrid.cy(site) + dy)
			if dc < 0 and k >= 0 and CGrid.passable(k) and CGrid.cheb(k, site) == 4 and CGrid.site_region(k) < 0:
				dc = k
	var d := _put(st, ns, dc, ["lancers", "musketeers", "musketeers", "pikemen", "pikemen", "cutlass", "wagon", "general", "pikemen"])
	d["stance"] = CData.ST_FORCED
	var a := _put(st, iz, dc, ["warriors", "warriors", "holcan", "native_bowmen", "native_bowmen", "warriors"])
	var b := CRules.start_field_battle(st, int(d["r"]), [a], [d])
	b["x"] = CGrid.cx(dc)
	b["y"] = CGrid.cy(dc)
	b["app"] = app
	var built := CBattle.build(st, b, iz)
	battle = Battle.new()
	battle.custom_scenario = built["scenario"]
	battle.seed_value = int(built["seed"])
	root.add_child(battle)


func _put(st: Dictionary, f: int, c: int, units: Array) -> Dictionary:
	var id := CRules.new_army_id(st, f)
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	var us: Array = []
	for t in units:
		us.append({"t": t, "n": UT.size_of(UT.index_of(t))})
	var ar := {"id": id, "f": f, "r": CGrid.region(c), "units": us, "from": -1, "moved": 0, "busy": 0}
	CState.place(ar, c)
	CRules._insert_army(st, ar)
	return CState.army(st, id)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 10:
		battle.paused = true
		var sc: Dictionary = battle.custom_scenario
		var z := Vector2(float(sc["width_m"]) / 2.0, float(sc["height_m"]) / 2.0)
		battle._cam_to(z * Battle.PX_PER_M)
		battle.camera.zoom = Vector2.ONE * minf(1240.0 / (float(sc["width_m"]) * Battle.PX_PER_M), 600.0 / (float(sc["height_m"]) * Battle.PX_PER_M))
	elif frame == 20:
		var dir := out.get_base_dir()
		DirAccess.make_dir_recursive_absolute(dir)
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		quit(0)
	return false
