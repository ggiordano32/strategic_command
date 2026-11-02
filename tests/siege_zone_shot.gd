extends SceneTree
## The defenders' deployment zone and a fort gun's line of fire on Portobelo (the owner's 2026-11-02 phone reports;
## docs/design/siege_and_towns.md "Deploying anywhere in the town", docs/design/battle_sim.md "Guns on a tower fire
## over their own parapet"): windowed, view only.
##   godot --path . --resolution 1280x720 -s tests/siege_zone_shot.gd -- --out=FILE.png [--view=top|oblique]
##       [--walls=2] [--mode=zone|gun] [--zoom=0.9]
## zone: the deployment phase, the player the defender (the AI attacks), the camera on the town and its fort.
## gun: the battle paused at its start, the fort gun nearest the attackers selected with an attack order on the
## nearest attacker in its sector, the camera on the fort (the order line, red "NO LINE OF FIRE" when blocked).
const Battle := preload("res://game/battle.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTown := preload("res://campaign/ctown.gd")
const UT := preload("res://sim/unit_types.gd")
const FM := preload("res://sim/fixed_math.gd")
var b
var out := "user://siege_zone.png"
var walls := 2
var mode := "zone"
var zoom := 0.9


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	BoardView.force = "top"
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v
		elif a.begins_with("--view="): BoardView.force = v
		elif a.begins_with("--walls="): walls = int(v)
		elif a.begins_with("--mode="): mode = v
		elif a.begins_with("--zoom="): zoom = float(v)
	_run.call_deferred()


func _scenario() -> Dictionary:
	CData.use_pack("west")
	var key := "portobelo"
	var r := CData.region_index(key)
	var st := CState.new_campaign("shot", 5, [], {}, [], "west")
	var level := maxi(1, int(st["regions"][r]["level"]))
	st["regions"][r]["level"] = level
	var got := false
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == CData.WALLS:
			sl[1] = walls
			got = true
	if not got:
		st["regions"][r]["slots"].append([CData.WALLS, walls])
	var rd: Dictionary = CData.REGIONS[r]
	var cseed := 0
	for ch in key.to_utf8_buffer():
		cseed = (cseed * 31 + int(ch)) % 100000
	var att: Array = []
	for e in Scenarios.WEST_ATT:
		att.append([UT.index_of(str(e[0])), int(e[1])])
	var cul := CData.region_culture(r)
	var terr := {"kind": int(rd["terrain"]), "seed": cseed * 7 + 3, "forest": int(rd["forest"]), "ground": int(rd["ground"])}
	var city := {"seed": cseed, "level": level, "walls": walls, "bld": [1, 2, 4], "plan": cul, "coast": 1, "founder": cul,
		"west": 1, "tp": CTown.battle_plan(st, r)}
	var sc: Dictionary = Scenarios.settlement(city, terr, att, att.duplicate(true), 1, [0], {"ladders": 3, "ram": 1})["scenario"]
	if mode == "zone":
		sc["deploy_time"] = 600
	return sc


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await _frames(4)
	b = Battle.new()
	b.custom_scenario = _scenario()
	b.player_side = 1
	b.seed_value = 4711
	root.add_child(b)
	await _frames(10)
	b._set_paused(true)
	var s = b.sim
	var focus := Vector2(s.cit_x, s.cit_y) / 1024.0
	if mode == "zone":
		print("phase ", s.phase, " zones ", s.dep_z)
		var zx0: int = s.field_w
		var zx1 := 0
		var zy0: int = s.field_h
		var ay0: int = s.field_h
		for k in range(0, s.dep_z.size(), 6):
			if s.dep_z[k] != s.city_def:
				ay0 = s.dep_z[k + 3]
				continue
			zx0 = mini(zx0, s.dep_z[k + 2])
			zx1 = maxi(zx1, s.dep_z[k + 4])
			zy0 = mini(zy0, s.dep_z[k + 3])
		focus = Vector2((zx0 + zx1) / 2, (zy0 + ay0) / 2) / 1024.0
	else:
		var best_g := -1
		var best_t := -1
		var bd := 1 << 40
		for g in s.n_units:
			if s.u_type[g] != UT.FORT_GUN:
				continue
			for t in s.n_units:
				if s.u_side[t] == s.u_side[g] or s.u_state[t] != 0:
					continue
				var out_a := FM.atan2_a(s.u_cy[g] - s.cit_y, s.u_cx[g] - s.cit_x)
				var bear := FM.atan2_a(s.u_cy[t] - s.u_cy[g], s.u_cx[t] - s.u_cx[g])
				if absi(FM.angle_diff(bear, out_a)) > BattleSim.FORT_GUN_SECTOR:
					continue
				var d := FM.approx_len(s.u_cx[t] - s.u_cx[g], s.u_cy[t] - s.u_cy[g])
				if d < bd:
					bd = d
					best_g = g
					best_t = t
		print("gun ", best_g, " target ", best_t, " at ", bd / 1024, " m, lof ", s.lof_units(best_g, best_t))
		s.u_order[best_g] = BattleSim.O_ATTACK
		s.u_target[best_g] = best_t
		b._select(best_g)
		focus = (Vector2(s.u_cx[best_g], s.u_cy[best_g]) * 0.7 + Vector2(s.u_cx[best_t], s.u_cy[best_t]) * 0.3) / 1024.0
	b.camera.zoom = Vector2.ONE * zoom
	b._cam_to(focus * Battle.PX_PER_M)
	await _frames(12)
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
