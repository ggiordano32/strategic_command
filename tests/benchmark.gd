extends SceneTree
## Headless sim benchmark.
##   godot --headless --script res://tests/benchmark.gd [-- --max-ticks=6000]
## Runs the AI vs AI scenarios through a full engagement and reports ms per
## tick (mean, p95, max), split into march (no unit in contact) and
## engagement phases.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")


func _init() -> void:
	var max_ticks := 6000
	var scens := ["bench_2000", "bench_4000"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--max-ticks="):
			max_ticks = int(a.get_slice("=", 1))
		elif a.begins_with("--scen="):
			scens = a.get_slice("=", 1).split(",")
	print("CPU: %s, %d threads, %s" % [OS.get_processor_name(), OS.get_processor_count(), OS.get_name()])
	for scen in scens:
		_bench(scen, max_ticks)
	quit(0)


func _bench(scen: String, max_ticks: int) -> void:
	var sim := BattleSim.new()
	var t0 := Time.get_ticks_usec()
	sim.setup(Scenarios.make(scen), 42)
	var setup_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var all := PackedFloat64Array()
	var march := PackedFloat64Array()
	var fight := PackedFloat64Array()
	var first_contact := -1
	var end_tick := -1
	var start_alive := sim.alive_count()
	var peak_grid := 0
	var hash_us := 0
	for t in max_ticks:
		var s := Time.get_ticks_usec()
		sim.step()
		var ms := (Time.get_ticks_usec() - s) / 1000.0
		all.append(ms)
		var contact := false
		for u in sim.n_units:
			if sim.u_contact[u] != 0:
				contact = true
				break
		if contact:
			fight.append(ms)
			if first_contact < 0:
				first_contact = sim.tick
		else:
			march.append(ms)
		peak_grid = maxi(peak_grid, sim.stat_grid_soldiers)
		if t % 10 == 0:
			var hs := Time.get_ticks_usec()
			sim.state_hash()
			hash_us += Time.get_ticks_usec() - hs
		if sim.winner >= 0 and end_tick < 0:
			end_tick = sim.tick
		# Run 30 s past the decision so the rout/pursuit phase is measured.
		if end_tick >= 0 and sim.tick >= end_tick + 300:
			break
	print("\n== %s: %d soldiers, %d units (setup %.1f ms)" % [scen, start_alive, sim.n_units, setup_ms])
	print("ticks run %d (%.0f s sim time); first contact tick %d; decided tick %d, winner %d" % [
		sim.tick, sim.tick / 10.0, first_contact, end_tick, sim.winner])
	print("alive at end: side0 %d, side1 %d; attacks %d; peak soldiers in grid %d" % [
		sim.alive_count(0), sim.alive_count(1), sim.stat_attacks, peak_grid])
	print("  all ticks   : %s" % _stats(all))
	print("  march ticks : %s" % _stats(march))
	print("  engaged     : %s" % _stats(fight))
	print("  state_hash(): %.2f ms each" % (hash_us / 1000.0 / maxf(1.0, ceil(sim.tick / 10.0))))


func _stats(a: PackedFloat64Array) -> String:
	if a.is_empty():
		return "n/a"
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	var p95: float = s[mini(s.size() - 1, int(s.size() * 0.95))]
	return "n=%d mean %.2f ms, p95 %.2f ms, max %.2f ms" % [s.size(), sum / s.size(), p95, s[s.size() - 1]]
