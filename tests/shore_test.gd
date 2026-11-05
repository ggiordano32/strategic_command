extends SceneTree
## A fleet at the shore (docs/design/battle_sim.md "A fleet at the shore (as built, 2026-11-05)"; the ships' AI,
## docs/AI.md 62), headless:
##   godot --headless --path . -s tests/shore_test.gd
## On Scenarios.shore_battle (west_port's map, a West port at walls 1): the ships lie on the water off the shore (the
## defenders' by the quay, the attackers' at the far end), never move, cannot be attacked by foot, their guns fire;
## ORDER_LAND sends a party ashore once (it paddles to its landing and lands), a party aboard is no reserve; Easy
## never lands, Average does; a native fleet has no guns; a map without water takes no ships (the result says so);
## snapshot / restore across a landing and two runs give the same hash; a battle without ships hashes as before
## (the units' kill table keeps its width). Exits 0 on success, 1 on failure.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")
const AP := preload("res://sim/ai_profile.gd")

const M := 1024
var failures := 0


func _check(c: bool, what: String) -> void:
	if c:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _init() -> void:
	_test_place()
	_test_land()
	_test_ai()
	_test_native()
	_test_no_water()
	_test_repeat()
	print("%s shore_test: %d failure(s)" % ["RESULT: PASS" if failures == 0 else "RESULT: FAIL", failures])
	quit(0 if failures == 0 else 1)


func _sim(sc: Dictionary, sd: int = 8100) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(sc, sd)
	return sim


func _test_place() -> void:
	print("placement, the fixed hull, no blows from the land")
	var sim := _sim(Scenarios.shore_battle(1, 1, []))
	_check(sim.shp_on == 1 and sim.sh_side.size() == 6, "six ships on the map (%d)" % sim.sh_side.size())
	var water := true
	var gap_ok := true
	for s in sim.sh_side.size():
		var u: int = sim.sh_unit[s]
		if sim.obs_kind(sim.sh_x[s], sim.sh_y[s]) != MapGen.C_WATER:
			water = false
		for t in range(s + 1, sim.sh_side.size()):
			var d: int = absi(sim.sh_x[s] - sim.sh_x[t]) + absi(sim.sh_y[s] - sim.sh_y[t])
			if d < (sim.sh_len[s] + sim.sh_len[t]) / 2 * M:
				gap_ok = false
		_check(sim.is_ship(u) and UT.stat(sim.u_type[u], "fixed") != 0, "ship %d is a fixed hull unit (%s)" % [s, UT.key_of(sim.u_type[u])])
	_check(water, "every hull lies on water")
	_check(gap_ok, "the hulls keep clear of each other")
	var d0 := Vector2i(sim.sh_x[3], sim.sh_y[3])
	_check(sim.quay.size() >= 2 and absi(d0.x - sim.quay[0]) < 60 * M, "the defenders' frigate lies off the quay")
	_check(sim.sh_x[0] < 120 * M or sim.sh_x[0] > sim.field_w - 120 * M, "the attackers' frigate lies at the end of the shore (x %d m)" % (sim.sh_x[0] / M))
	_check(sim.u_neng[sim.sh_unit[0]] == 4 and sim.u_neng[sim.sh_unit[1]] == 1, "a frigate works 4 guns, a sloop 1")
	_check(sim.reserves_left(1) == 0 and sim.u_state[sim.sh_party[3]] == BattleSim.U_RESERVE, "a party aboard waits off the field and is no reserve")
	# A move order to the hull is refused; foot ordered at it are refused; a musket line may shoot at it.
	var h: int = sim.sh_unit[3]
	sim.queue_order({"tick": 0, "type": BattleSim.ORDER_MOVE, "unit": h, "x": sim.u_ax[h] + 30 * M, "y": sim.u_ay[h],
		"facing": 0, "width": 10 * M})
	var foot := -1
	var musk := -1
	for u in sim.n_units:
		if sim.u_side[u] == 0 and sim.u_state[u] == BattleSim.U_READY and not sim.is_ship(u):
			if UT.stat(sim.u_type[u], "m_range") <= 0 and foot < 0:
				foot = u
			elif UT.key_of(sim.u_type[u]) == "musketeers" and musk < 0:
				musk = u
	sim.queue_order({"tick": 0, "type": BattleSim.ORDER_ATTACK, "unit": foot, "target": h, "run": 1})
	sim.queue_order({"tick": 0, "type": BattleSim.ORDER_ATTACK, "unit": musk, "target": h, "run": 0})
	var ax: int = sim.u_ax[h]
	for t in 5:
		sim.step()
	_check(sim.u_ax[h] == ax and sim.u_order[h] != BattleSim.O_MOVE, "the hull does not move")
	_check(sim.u_target[foot] != h, "foot are not sent at a hull on the water")
	_check(sim.u_target[musk] == h, "a musket line may be ordered to shoot at her")


func _test_land() -> void:
	print("the Land order, the party ashore")
	var sc := Scenarios.shore_battle(1, 0, [0])
	var sim := _sim(sc)
	var h: int = sim.sh_unit[0]
	var s: int = sim.u_ship[h]
	var p: int = sim.sh_party[s]
	_check(BattleSim.land_refusal(sim, h) == "", "she may land her party (%s)" % BattleSim.land_refusal(sim, h))
	_check(BattleSim.land_refusal(sim, p) != "", "a party is no ship")
	sim.queue_order({"tick": 0, "type": BattleSim.ORDER_LAND, "unit": h})
	sim.step()
	_check(sim.sh_land[s] == 0 and sim.u_state[p] == BattleSim.U_READY and sim.u_alive[p] == sim.u_count0[p],
		"ORDER_LAND: the party (%d men) is on the field" % sim.u_count0[p])
	_check(sim.u_wet[p] > 0 and sim.u_order[p] == BattleSim.O_MOVE, "it starts on the water, paddling to its landing")
	_check(BattleSim.land_refusal(sim, h) != "", "a second Land is refused (%s)" % BattleSim.land_refusal(sim, h))
	var landed := -1
	for t in 900:
		sim.step()
		if sim.u_wet[p] == 0 and absi(sim.u_ax[p] - sim.sh_lx[s]) + absi(sim.u_ay[p] - sim.sh_ly[s]) < 30 * M:
			landed = sim.tick
			break
	_check(landed > 0, "it lands at its landing, the quay (tick %d)" % landed)
	var res: Dictionary = sim.result()
	var rs: Array = res.get("ships", [])
	_check(rs.size() == 3 and int(rs[0]["landed"]) == sim.u_count0[p] and int(rs[0]["src"]) == 0, "the result's ships: the party landed")


## Both fleets, both sides AI at the skill: [shots, parties landed, the hulls' kills].
func _ai_run(skill: int, ticks: int) -> Array:
	var sc := Scenarios.shore_battle(1, 1)
	sc["ai_skill"] = [skill, skill]
	var sim := _sim(sc)
	for t in ticks:
		sim.step()
		if sim.ended != 0:
			break
	var shots := 0
	var landed := 0
	var kills := 0
	for s in sim.sh_side.size():
		shots += sim.sh_shots[s]
		if sim.sh_land[s] >= 0:
			landed += 1
		kills += sim.u_kills[sim.sh_unit[s]]
	return [shots, landed, kills]


func _test_ai() -> void:
	print("the AI's ships")
	var av := _ai_run(AP.AVERAGE, 2400)
	_check(int(av[0]) > 0, "Average: the guns fire (%d shots, %d killed)" % [int(av[0]), int(av[2])])
	_check(int(av[1]) >= 4, "Average: the parties go ashore (%d of 6)" % int(av[1]))
	var ez := _ai_run(AP.EASY, 1200)
	_check(int(ez[1]) == 0, "Easy: no party goes ashore (%d)" % int(ez[1]))


func _test_native() -> void:
	print("a native fleet")
	var sim := _sim(Scenarios.shore_battle(2, 0, [0]))
	var guns := 0
	var raiders := 0
	for s in sim.sh_side.size():
		guns += sim.u_neng[sim.sh_unit[s]]
		if UT.key_of(sim.u_type[sim.sh_party[s]]) == "canoe_raiders":
			raiders += sim.u_count0[sim.sh_party[s]]
	_check(sim.sh_side.size() == 3 and guns == 0, "a piragua and two war canoes: no guns to fire on the land")
	_check(raiders == 15 + 10 + 10, "their parties are canoe raiders, a quarter of each crew (%d)" % raiders)


func _test_no_water() -> void:
	print("a map without water")
	var sc := Scenarios.make("skirmish")
	sc["ships"] = [Scenarios.ship_entry(0, "frigate", 30, 200, 100, 0)]
	var sim := _sim(sc)
	_check(sim.shp_on == 0 and sim.shp_none == 1, "no ships on a field without water")
	_check(int(sim.result().get("ships_none", 0)) == 1, "the result says so (ships_none)")


func _test_repeat() -> void:
	print("determinism")
	var sc := Scenarios.shore_battle(1, 1)
	var a := _sim(sc, 4242)
	var b := _sim(sc, 4242)
	var snap := PackedByteArray()
	var at := -1
	for t in 900:
		a.step()
		b.step()
		if at < 0 and a.sh_land[0] >= 0 and a.tick > a.sh_land[0] + 10:
			snap = a.snapshot()
			at = a.tick
	_check(a.state_hash() == b.state_hash(), "two runs, the same hash")
	var c := _sim(sc, 4242)
	_check(at > 0 and c.restore(snap), "restored from a snapshot after a landing (tick %d)" % at)
	while c.tick < a.tick:
		c.step()
	_check(c.state_hash() == a.state_hash(), "... and runs on with the same hash")
	# Without ships the unit kill table keeps its old width (West battles hash as before).
	var w := _sim(Scenarios.shore_battle(0, 0))
	_check(w.shp_on == 0 and w.kty_n == UT.SHIP_GUNS, "a battle without ships: kty_n %d (the rows before the ships')" % w.kty_n)
