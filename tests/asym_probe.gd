extends SceneTree
## The asymmetry probe (roles step 2; docs/design/battle_sim.md "Roles, step 2 (as built)"): the
## scenarios asym_woods and asym_field (a Spanish army, side 0, against a native war party of equal
## cost, both AI Average) over seeds; prints each battle and the side-0 (Spanish) win count.
##   godot --headless --script res://tests/asym_probe.gd -- --scen=asym_woods --seeds=16 [--seed0=0] [--plays=MASK]
## play_field (docs/AI.md 44.1): the Spanish against an English army on open
## ground (the English with England's campaign plays, the countermarch's
## bit only). --plays=MASK sets the Spanish side's ai_plays (sim/plays.gd
## bits; default every play), e.g. --plays=0 without the tercio. Each battle
## prints whether the Spanish formed a tercio, and the line of sight's
## reveals, hidden checks and sight lingers (the summary: per battle).
## The native ambush (docs/AI.md 44.5): --plays1=MASK sets the natives' (side
## 1) bits (e.g. --plays1=0 without the ambush, 4 with it only);
## ambush_field (the Spanish column between two woods). Each battle prints
## the ambush's counters (laid, springs, melts) and the sim's ambush strikes;
## the summary the natives' losses and the battle's length (means) too.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const AP := preload("res://sim/ai_profile.gd")


func _init() -> void:
	var scen := "asym_woods"
	var seeds := 16
	var seed0 := 0
	var plays := -2  # (-2: the scenario's own; else side 0's ai_plays)
	var plays1 := -2  # (... side 1's)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scen="):
			scen = a.substr(7)
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed0="):
			seed0 = int(a.substr(8))
		elif a.begins_with("--plays="):
			plays = int(a.substr(8))
		elif a.begins_with("--plays1="):
			plays1 = int(a.substr(9))
	var w := [0, 0, 0]
	var rv := 0
	var hd := 0
	var lg := 0
	var nl := 0
	var ln := 0
	var amb := [0, 0, 0, 0]
	for k in seeds:
		var sd := 5000 + seed0 + k
		var sim := BattleSim.new()
		var sc := Scenarios.make(scen)
		if plays != -2 or plays1 != -2:
			var pl: Array = sc.get("ai_plays", [-1, -1])
			sc["ai_plays"] = [plays if plays != -2 else pl[0], plays1 if plays1 != -2 else pl[1]]
		sim.setup(sc, sd)
		var n1_0 := 0
		for u in sim.n_units:
			if sim.u_side[u] == 1:
				n1_0 += sim.u_alive[u]
		while sim.tick < 12000 and sim.winner < 0:
			sim.step()
		var r: int = sim.winner if sim.winner == 0 or sim.winner == 1 else 2
		w[r] += 1
		print("BATTLE %s seed %d winner %d tick %d alive %d/%d pistols %d car %d drift %d parley %d/%d pris %d,%d" % [scen, sd, r, sim.tick,
			sim.alive_count(0), sim.alive_count(1), sim.stat_pis_shots if "stat_pis_shots" in sim else -1,
			sim.stat_car_volleys if "stat_car_volleys" in sim else -1, sim.stat_skd_men if "stat_skd_men" in sim else -1,
			sim.stat_parley_ok, sim.stat_parley_ok + sim.stat_parley_fail, sim.ch_pris[0], sim.ch_pris[1]])
		var lin: int = sim.get("stat_lingers") if "stat_lingers" in sim else 0
		var na := AP.N_COUNTERS
		var lost1: int = n1_0 - sim.alive_count(1)
		print("  tercio %d reveals %d hidden %d lingers %d ambush %d springs %d melts %d strikes %d natives_lost %d" % [
			sim.stat_aic[AP.C_PLAY_TERCIO], sim.stat_reveals, sim.stat_hidden, lin, sim.stat_aic[na + AP.C_PLAY_AMBUSH],
			sim.stat_aic[na + AP.C_AMB_SPRING], sim.stat_aic[na + AP.C_AMB_MELT], sim.stat_ambush, lost1])
		amb[0] += sim.stat_aic[na + AP.C_PLAY_AMBUSH]
		amb[1] += sim.stat_aic[na + AP.C_AMB_SPRING]
		amb[2] += sim.stat_aic[na + AP.C_AMB_MELT]
		amb[3] += sim.stat_ambush
		nl += lost1
		ln += sim.tick
		lg += lin
		rv += sim.stat_reveals
		hd += sim.stat_hidden
	print("SUMMARY %s seeds %d spanish %d natives %d draws %d reveals/battle %.1f hidden/battle %.1f lingers/battle %.1f" % [scen, seeds, w[0], w[1], w[2],
		float(rv) / maxi(seeds, 1), float(hd) / maxi(seeds, 1), float(lg) / maxi(seeds, 1)])
	var sn := float(maxi(seeds, 1))
	print("AMBUSH %s natives_lost/battle %.1f length_s %.1f laid %d springs/battle %.2f melts/battle %.2f strikes/battle %.2f" % [scen,
		nl / sn, ln / sn / 10.0, amb[0], amb[1] / sn, amb[2] / sn, amb[3] / sn])
	quit()
