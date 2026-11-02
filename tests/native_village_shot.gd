extends SceneTree
## The native lesson's village (docs/design/siege_and_towns.md "The native lesson's village"): the tutorial_native
## scenario's deployment on the battle screen as main.gd starts it (the West pack, seed 1671), the camera on the
## village, saved as a PNG (windowed):
##   godot --path . --resolution 1280x720 -s tests/native_village_shot.gd -- --out=FILE.png [--view=top|oblique]
##       [--zoom=1.6] [--dx=0] [--dy=0] [--whole] [--id=tutorial_native (another scenario, to compare)]
const Battle := preload("res://game/battle.gd")
const BoardView := preload("res://game/board_view.gd")
const CData := preload("res://campaign/cdata.gd")
var battle: Battle
var out := "user://native_village.png"
var zoom := 1.6
var dx := 0.0
var dy := 0.0
var whole := false
var id := "tutorial_native"
var frame := 0


func _initialize() -> void:
	BoardView.force = "top"
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v
		elif a.begins_with("--view="): BoardView.force = v
		elif a.begins_with("--zoom="): zoom = float(v)
		elif a.begins_with("--dx="): dx = float(v)
		elif a.begins_with("--dy="): dy = float(v)
		elif a == "--whole": whole = true
		elif a.begins_with("--id="): id = v
	CData.use_pack("west")
	battle = Battle.new()
	battle.scenario_id = id
	battle.seed_value = 1671
	battle.terrain_kind = -1
	battle.ai_skill = -1
	battle.side_name_fkeys = ["miskito", "new_spain"]
	root.add_child(battle)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 10:
		battle.paused = true
		var lay: Dictionary = battle.sim.map_info["city"]
		var c := Vector2(float(int(lay["cx"])) + dx, float(int(lay["cy"])) + dy)
		if whole:
			var w := float(battle.sim.field_w) / 1024.0
			var h := float(battle.sim.field_h) / 1024.0
			c = Vector2(w / 2.0, h / 2.0)
			zoom = minf(1240.0 / (w * Battle.PX_PER_M), 700.0 / (h * Battle.PX_PER_M))
		if "--print" in OS.get_cmdline_user_args():
			print("CITY c=", Vector2(int(lay["cx"]), int(lay["cy"])), " t=", lay["t"], " walls=", lay["walls"], " pal=", lay.get("palisade", 0))
			print("POLY ", lay["poly"])
			print("FIELDS ", lay["fields"])
			for u in battle.sim.n_units:
				print("UNIT ", u, " side ", battle.sim.u_side[u], " at ", Vector2(battle.sim.u_cx[u], battle.sim.u_cy[u]) / 1024.0)
		battle._cam_to(c * Battle.PX_PER_M)
		battle.camera.zoom = Vector2.ONE * zoom
	elif frame == 60:
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		quit(0)
	return false
