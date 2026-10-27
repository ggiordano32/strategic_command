extends SceneTree
## The asymmetry probe (roles step 2; docs/design/battle_sim.md "Roles, step 2 (as built)"): the
## scenarios asym_woods and asym_field (a Spanish army, side 0, against a native war party of equal
## cost, both AI Average) over seeds; prints each battle and the side-0 (Spanish) win count.
##   godot --headless --script res://tests/asym_probe.gd -- --scen=asym_woods --seeds=16 [--seed0=0] [--plays=MASK]
## play_field (docs/AI.md 44.1): the Spanish against an English army on open
## ground (the English with England's campaign plays, the countermarch's
## bit only). --plays=MASK sets the Spanish side's ai_plays (sim/plays.gd
## bits; default every play), e.g. --plays=0 without the tercio. Each battle
## prints whether the Spanish formed a tercio.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const AP := preload("res://sim/ai_profile.gd")


func _init() -> void:
	var scen := "asym_woods"
	var seeds := 16
	var seed0 := 0
	var plays := -2  # (-2: the scenario's own; else side 0's ai_plays)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scen="):
			scen = a.substr(7)
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed0="):
			seed0 = int(a.substr(8))
		elif a.begins_with("--plays="):
			plays = int(a.substr(8))
	var w := [0, 0, 0]
	for k in seeds:
		var sd := 5000 + seed0 + k
		var sim := BattleSim.new()
		var sc := Scenarios.make(scen)
		if plays != -2:
			var pl: Array = sc.get("ai_plays", [-1, -1])
			sc["ai_plays"] = [plays, pl[1]]
		sim.setup(sc, sd)
		while sim.tick < 12000 and sim.winner < 0:
			sim.step()
		var r: int = sim.winner if sim.winner == 0 or sim.winner == 1 else 2
		w[r] += 1
		print("BATTLE %s seed %d winner %d tick %d alive %d/%d pistols %d car %d drift %d parley %d/%d pris %d,%d" % [scen, sd, r, sim.tick,
			sim.alive_count(0), sim.alive_count(1), sim.stat_pis_shots if "stat_pis_shots" in sim else -1,
			sim.stat_car_volleys if "stat_car_volleys" in sim else -1, sim.stat_skd_men if "stat_skd_men" in sim else -1,
			sim.stat_parley_ok, sim.stat_parley_ok + sim.stat_parley_fail, sim.ch_pris[0], sim.ch_pris[1]])
		print("  tercio %d" % sim.stat_aic[AP.C_PLAY_TERCIO])
	print("SUMMARY %s seeds %d spanish %d natives %d draws %d" % [scen, seeds, w[0], w[1], w[2]])
	quit()
