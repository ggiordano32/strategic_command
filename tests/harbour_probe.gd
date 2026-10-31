extends SceneTree
## The harbour assault's and the lake of Tayasal's balance probe (docs/AI.md 50; docs/design/battle_sim.md
## "Amphibious units and the sea gate (as built)"): the scenario with the battle AI on both sides at --skill=
## (default Average, both sides), over seeds; prints each battle (the winner, the time, when the first amphibious
## unit landed through the sea gate or on its sortie's shore, gates unbarred) and the attacker's win count.
##   godot --headless --path . -s tests/harbour_probe.gd -- [--id=west_harbour_assault|tayasal] [--seeds=8]
##       [--skill=1] [--gar=100] [--seed0=8100] [--walls=2 --att=100 (tayasal: the Spanish companies' %)]
##       [--knob=ID:VALUE] [--verbose]
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")
const UT := preload("res://sim/unit_types.gd")
const AP := preload("res://sim/ai_profile.gd")


func _init() -> void:
	var seeds := 8
	var skill := 1
	var gar := 100
	var id := "west_harbour_assault"
	var verbose := false
	var seed0 := 8100
	var walls := 2
	var att_pct := 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--skill="):
			skill = int(a.substr(8))
		elif a.begins_with("--gar="):
			gar = int(a.substr(6))
		elif a.begins_with("--id="):
			id = a.substr(5)
		elif a.begins_with("--att="):
			att_pct = int(a.substr(6))
		elif a.begins_with("--walls="):
			walls = int(a.substr(8))
		elif a.begins_with("--seed0="):
			seed0 = int(a.substr(8))
		elif a == "--verbose":
			verbose = true
		elif a.begins_with("--knob="):
			# (--knob=ID:VALUE: every profile row's knob ID set to VALUE, as tests/asym_probe.gd; repeatable)
			var kv := a.substr(7).split(":")
			AP.row(0, 0)
			for i in AP._tab.size():
				var p: PackedInt32Array = AP._tab[i]
				p[int(kv[0])] = int(kv[1])
				AP._tab[i] = p
	var won := 0
	var total_t := 0
	for k in seeds:
		var sd := seed0 + k
		var sc := Scenarios.harbour_assault(gar) if id == "west_harbour_assault" else Scenarios.tayasal(gar, [0, 1], walls, att_pct)
		sc["ai_skill"] = [skill, skill]
		var sim := BattleSim.new()
		sim.setup(sc, sd)
		var att := 1 - sim.city_def
		if k == 0:
			for u in sim.n_units:
				print("  unit %d side %d %s men %d amph %d" % [u, sim.u_side[u], UT.key_of(sim.u_otype[u]), sim.u_alive[u],
					1 if sim.amphib(u) else 0])
			print("  gates %d walls %d amph_on %d harb %s" % [sim.n_gates, sim.city_walls, sim.amph_on,
				str(Array(sim.harb).map(func(v): return v / 1024))])
		var landed := -1
		var sortie := -1
		var quay := -1
		var gate_open := -1
		while sim.tick < 20 * 60 * BattleSim.TICKS_PER_SECOND and sim.winner < 0:
			sim.step()
			if sim.tick % 10 != 0:
				continue
			for u in sim.n_units:
				if sim.u_state[u] != 0:
					continue
				if landed < 0 and sim.u_side[u] == att and sim.u_ai[u] == SiegeAI.A_HARB and sim.u_ai_x[u] == 3:
					landed = sim.tick
				if sortie < 0 and sim.u_side[u] != att and sim.u_ai[u] == SiegeAI.A_HSORTIE and sim.u_ai_x[u] >= 2:
					sortie = sim.tick
				if quay < 0 and sim.u_side[u] != att and sim.u_ai[u] == SiegeAI.A_HQUAY:
					quay = sim.tick
			if gate_open < 0:
				for g in sim.n_gates:
					if sim.g_cit[g] == 0 and sim.g_state[g] != BattleSim.GATE_CLOSED:
						gate_open = sim.tick
			if verbose and sim.tick % 300 == 0:
				var row := "    t %d:" % (sim.tick / 10)
				for u in sim.n_units:
					if sim.amphib(u):
						row += " u%d(s%d m%d x%d wet%d alive%d at %d,%d)" % [u, sim.u_side[u], sim.u_ai[u], sim.u_ai_x[u],
							sim.u_wet[u], sim.u_alive[u], sim.u_ax[u] / 1024, sim.u_ay[u] / 1024]
				print(row)
		if sim.winner == att:
			won += 1
		total_t += sim.tick
		var tps := BattleSim.TICKS_PER_SECOND
		print("BATTLE seed %d winner %d (attacker %d) t %d s alive att %d def %d landed %d s quay %d s sortie %d s gate open %d s unbarred %d" % [
			sd, sim.winner, att, sim.tick / tps, sim.alive_count(att), sim.alive_count(1 - att),
			landed / tps if landed >= 0 else -1, quay / tps if quay >= 0 else -1, sortie / tps if sortie >= 0 else -1,
			gate_open / tps if gate_open >= 0 else -1, sim.stat_unbar])
	print("RESULT %s skill %d gar %d: attacker won %d of %d (mean %d s)" % [id, skill, gar, won, seeds,
		total_t / maxi(seeds, 1) / BattleSim.TICKS_PER_SECOND])
	quit(0)
