extends SceneTree
## The native way's balance probe (docs/design/campaign_rules.md "The native way (as built)"): the tutorial_native
## scenario with the battle AI on both sides (the attacker's side 0 at --skill=, default Average; the garrison on
## Easy as the scenario sets it), over seeds; prints each battle and the attacker's win count.
##   godot --headless --path . -s tests/native_lesson_probe.gd -- [--seeds=8] [--skill=1]
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")


func _init() -> void:
	var seeds := 8
	var skill := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--skill="):
			skill = int(a.substr(8))
	var won := 0
	for k in seeds:
		var sd := 7000 + k
		var sc := Scenarios.native_lesson([0, 1])
		sc.erase("deploy_time")
		sc["ai_skill"] = [skill, 0]
		var sim := BattleSim.new()
		sim.setup(sc, sd)
		if k == 0:
			for u in sim.n_units:
				print("  unit %d side %d %s men %d sk %d" % [u, sim.u_side[u], UT.key_of(sim.u_otype[u]), sim.u_alive[u], sim.u_sk[u]])
			print("  gates %d walls %d" % [sim.n_gates, sim.city_walls])
		var burnt := -1
		while sim.tick < 20 * 60 * BattleSim.TICKS_PER_SECOND and sim.winner < 0:
			sim.step()
			if burnt < 0:
				for g in sim.n_gates:
					if sim.g_state[g] == BattleSim.GATE_BROKEN:
						burnt = sim.tick
		if sim.winner == 0:
			won += 1
		var pois := 0
		print("BATTLE seed %d winner %d t %d s alive %d/%d gate broken at %d s fire_dmg %d burnt %d" % [sd, sim.winner,
			sim.tick / BattleSim.TICKS_PER_SECOND, sim.alive_count(0), sim.alive_count(1),
			burnt / BattleSim.TICKS_PER_SECOND if burnt >= 0 else -1, sim.stat_fire_dmg, sim.stat_burnt])
	print("RESULT attacker won %d of %d" % [won, seeds])
	quit(0)
