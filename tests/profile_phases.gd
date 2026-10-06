extends SceneTree
## Per-phase timing of BattleSim.step() for the 4,000 AI vs AI scenario.
##   godot --headless --script res://tests/profile_phases.gd [-- --scen=bench_4000_city --ticks=N --from=T]
## (--from: only ticks from T on are counted, e.g. a city's breach fight.)
## (Mirrors step(): keep it in step with it.)

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BattleAI := preload("res://sim/battle_ai.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")


func _init() -> void:
	var scen := "bench_4000"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scen="):
			scen = a.get_slice("=", 1)
	var sim := BattleSim.new()
	sim.setup(Scenarios.make(scen), 42)
	var names := ["orders+ai", "prev copy", "units", "contacts", "grid", "soldiers", "artillery", "missiles", "offsets", "morale+winner"]
	var tot := PackedFloat64Array()
	tot.resize(names.size())
	var mx := PackedFloat64Array()
	mx.resize(names.size())
	var mx_t := PackedInt32Array()
	mx_t.resize(names.size())
	var ticks := 2000
	var from := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ticks="):
			ticks = int(a.get_slice("=", 1))
		elif a.begins_with("--from="):
			from = int(a.get_slice("=", 1))
	var counted := 0
	for t in ticks:
		var ts := [Time.get_ticks_usec()]
		sim._dist_new = 0
		sim._apply_orders()
		if sim.city_on != 0:
			SiegeAI.think(sim)
		else:
			BattleAI.think(sim)
		sim._apply_orders(); ts.append(Time.get_ticks_usec())
		sim.prev_x = sim.pos_x.duplicate(); sim.prev_y = sim.pos_y.duplicate(); ts.append(Time.get_ticks_usec())
		sim._update_units(); ts.append(Time.get_ticks_usec())
		sim._update_contacts(); ts.append(Time.get_ticks_usec())
		sim._build_grid(); ts.append(Time.get_ticks_usec())
		sim._update_soldiers()
		if sim.n_gates > 0:
			sim._update_gates()
		ts.append(Time.get_ticks_usec())
		if sim.n_eng > 0:
			sim.e_px = sim.e_x.duplicate(); sim.e_py = sim.e_y.duplicate()
			sim._update_artillery()
		ts.append(Time.get_ticks_usec())
		sim._update_missiles(); ts.append(Time.get_ticks_usec())
		sim._refresh_offsets(); ts.append(Time.get_ticks_usec())
		sim._update_morale()
		if sim.city_on != 0:
			sim._update_capture()
		sim._check_winner(); sim.tick += 1; ts.append(Time.get_ticks_usec())
		if t < from:
			continue
		counted += 1
		for k in names.size():
			var dt: float = ts[k + 1] - ts[k]
			tot[k] += dt
			if dt > mx[k]:
				mx[k] = dt
				mx_t[k] = sim.tick - 1
	print(scen)
	for k in names.size():
		print("%-14s %.3f ms/tick  max %.2f ms (tick %d)" % [names[k], tot[k] / 1000.0 / maxi(counted, 1), mx[k] / 1000.0, mx_t[k]])
	print("searches %d, attacks %d, shots %d, impacts %d" % [sim.stat_searches, sim.stat_attacks, sim.stat_shots, sim.stat_impacts])
	quit(0)
