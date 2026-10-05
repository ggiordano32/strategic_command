extends SceneTree
## Headless determinism test.
##   godot --headless --script res://tests/determinism_test.gd
## Runs the same scenario + seed + scripted orders twice and asserts the state
## hash matches at every tick, then checks a different seed diverges.
## Exits 0 on success, 1 on failure.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")

const TICKS := 1500
const M := 1024


func _init() -> void:
	var ok := true
	for scen in ["skirmish", "battle_2000"]:
		var a := _run(scen, 12345)
		var b := _run(scen, 12345)
		var first_bad := -1
		for t in a.size():
			if a[t] != b[t]:
				first_bad = t
				break
		if first_bad >= 0 or a.size() != b.size():
			printerr("FAIL %s: same seed diverged at tick %d" % [scen, first_bad])
			ok = false
		else:
			print("PASS %s: %d ticks identical, final hash %08x" % [scen, a.size(), a[a.size() - 1]])
		var c := _run(scen, 999)
		var diverge := -1
		for t in mini(a.size(), c.size()):
			if a[t] != c[t]:
				diverge = t
				break
		if diverge < 0:
			printerr("FAIL %s: different seed did not diverge" % scen)
			ok = false
		else:
			print("PASS %s: different seed diverges from tick %d" % [scen, diverge])
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


## Scripted player orders for side 0 (side 1 is AI in both scenarios).
func _script_orders(sim) -> void:
	var nu: int = sim.n_units
	var player_units: Array = []
	var enemy_units: Array = []
	for u in nu:
		if sim.u_side[u] == 0:
			player_units.append(u)
		else:
			enemy_units.append(u)
	# Tick 5: first unit reforms wider and advances; tick 20: second unit
	# attacks running; tick 60: halt + run toggle; tick 80: move with new
	# facing; tick 120: everyone attacks the matching enemy.
	var u0: int = player_units[0]
	var u1: int = player_units[1]
	sim.queue_order(BattleSim.make_move_order(5, u0, sim.u_ax[u0], sim.u_ay[u0] - 30 * M, 768, 34 * M, 0))
	sim.queue_order(BattleSim.make_attack_order(20, u1, enemy_units[0], 1))
	sim.queue_order(BattleSim.make_halt_order(60, u0))
	sim.queue_order(BattleSim.make_run_order(61, u0, 1))
	sim.queue_order(BattleSim.make_move_order(80, u0, sim.u_ax[u0] + 20 * M, sim.u_ay[u0] - 40 * M, 700, 20 * M, 1))
	for k in player_units.size():
		var tgt: int = enemy_units[k % enemy_units.size()]
		sim.queue_order(BattleSim.make_attack_order(120 + k, player_units[k], tgt, 0))


func _run(scen: String, p_seed: int) -> PackedInt64Array:
	var sim := BattleSim.new()
	sim.setup(Scenarios.make(scen), p_seed)
	_script_orders(sim)
	var hashes := PackedInt64Array()
	hashes.append(sim.state_hash())
	for t in TICKS:
		sim.step()
		hashes.append(sim.state_hash())
	print("  %s seed %d: alive %d/%d after %d ticks, winner %d" % [scen, p_seed,
		sim.alive_count(0), sim.alive_count(1), TICKS, sim.winner])
	return hashes
