extends SceneTree
## The asymmetry probe (roles step 2; docs/design/battle_sim.md "Roles, step 2 (as built)"): the
## scenarios asym_woods and asym_field (a Spanish army, side 0, against a native war party of equal
## cost, both AI Average) over seeds; prints each battle and the side-0 (Spanish) win count.
##   godot --headless --script res://tests/asym_probe.gd -- --scen=asym_woods --seeds=16 [--seed0=0]

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")


func _init() -> void:
	var scen := "asym_woods"
	var seeds := 16
	var seed0 := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scen="):
			scen = a.substr(7)
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed0="):
			seed0 = int(a.substr(8))
	var w := [0, 0, 0]
	for k in seeds:
		var sd := 5000 + seed0 + k
		var sim := BattleSim.new()
		sim.setup(Scenarios.make(scen), sd)
		while sim.tick < 12000 and sim.winner < 0:
			sim.step()
		var r: int = sim.winner if sim.winner == 0 or sim.winner == 1 else 2
		w[r] += 1
		print("BATTLE %s seed %d winner %d tick %d alive %d/%d pistols %d car %d drift %d" % [scen, sd, r, sim.tick,
			sim.alive_count(0), sim.alive_count(1), sim.stat_pis_shots if "stat_pis_shots" in sim else -1,
			sim.stat_car_volleys if "stat_car_volleys" in sim else -1, sim.stat_skd_men if "stat_skd_men" in sim else -1])
	print("SUMMARY %s seeds %d spanish %d natives %d draws %d" % [scen, seeds, w[0], w[1], w[2]])
	quit()
