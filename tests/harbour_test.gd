extends SceneTree
## Amphibious units and the sea gate (docs/design/battle_sim.md "Amphibious units and the sea gate (as built)";
## the siege AI's R_HARBOUR, docs/AI.md 50), headless:
##   godot --headless --path . -s tests/harbour_test.gd
## On the harbour assault's map (west_harbour_assault: a walled West port with a sea gate): canoe raiders ordered
## onto the water paddle at AMPHIB_PCT of their pace on land, foot refuse the water; the sea gate's passage is water
## only amphibious units use; raiders landed on the quay inside; the AI with R_HARBOUR sends them by water and a
## defender holds the quay (Easy does neither); the lake of Tayasal's sortie lands on the attackers' flank;
## snapshot / restore across a water move and two runs give the same hash. Exits 0 on success, 1 on failure.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")

const M := 1024
var failures := 0


func _check(c: bool, what: String) -> void:
	if c:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _init() -> void:
	_test_moves()
	_test_ai_harbour()
	_test_ai_easy()
	_test_tayasal()
	_test_quay()
	_test_snapshot()
	print("%s harbour_test: %d failure(s)" % ["RESULT: PASS" if failures == 0 else "RESULT: FAIL", failures])
	quit(0 if failures == 0 else 1)


## The harbour map with no AI: raider 0 afloat where the scenario puts it, raider 1 and a warriors company moved
## ashore beside the left shore.
func _quiet() -> Dictionary:
	var sc := Scenarios.harbour_assault(100, [])
	var shore := 9999
	var raiders: Array = []
	var war := -1
	for k in (sc["units"] as Array).size():
		var ud: Dictionary = sc["units"][k]
		if int(ud["side"]) != 0:
			continue
		var key := UT.key_of(int(ud["type"]))
		if key == "canoe_raiders":
			raiders.append(k)
			shore = mini(shore, int(ud["y_m"]))
		elif key == "native_warriors" and war < 0:
			war = k
	var r1: Dictionary = sc["units"][raiders[1]]
	r1["x_m"] = 30
	r1["y_m"] = shore + 26 + 40
	r1["facing"] = Scenarios.FACE_RIGHT
	var wu: Dictionary = sc["units"][war]
	wu["x_m"] = 30
	wu["y_m"] = shore + 26 + 70
	wu["facing"] = Scenarios.FACE_UP
	return {"sc": sc, "r0": raiders[0], "r1": raiders[1], "war": war}


func _move(sim, u: int, x: int, y: int, run: int = 0) -> void:
	sim.queue_order({"tick": sim.tick, "type": 1, "unit": u, "x": x, "y": y, "facing": sim.u_face[u],
		"width": 10 * M, "run": run})


func _test_moves() -> void:
	print("moves, the sea gate, the landing")
	var q := _quiet()
	var sim := BattleSim.new()
	sim.setup(q["sc"], 5)
	var r0: int = q["r0"]
	var r1: int = q["r1"]
	var war: int = q["war"]
	_check(sim.amph_on == 1, "amph_on with canoe raiders on a map with water")
	_check(sim.harb.size() == 6, "the sea gate's passage carved (harb)")
	_check(sim.on_water(sim.u_ax[r0], sim.u_ay[r0]), "raider 0 starts afloat")
	_check(not sim.on_water(sim.u_ax[r1], sim.u_ay[r1]), "raider 1 starts ashore")
	# The pace: raider 0 east along the water, raider 1 east along the shore, the same distance.
	var a0 := Vector2i(sim.u_ax[r0], sim.u_ay[r0])
	var a1 := Vector2i(sim.u_ax[r1], sim.u_ay[r1])
	_move(sim, r0, a0.x + 120 * M, a0.y)
	_move(sim, r1, a1.x + 120 * M, a1.y)
	# The warriors told onto the water off the shore.
	_move(sim, war, sim.u_ax[war], a0.y)
	for t in 30:
		sim.step()
	var b0 := Vector2i(sim.u_ax[r0], sim.u_ay[r0])
	var b1 := Vector2i(sim.u_ax[r1], sim.u_ay[r1])
	var wet_war := 0
	for t in 200:
		sim.step()
		if sim.on_water(sim.u_ax[war], sim.u_ay[war]):
			wet_war += 1
		var base: int = sim.u_slot_base[war]
		for s in sim.u_alive[war]:
			var i: int = sim.slot_soldier[base + s]
			if sim.on_water(sim.pos_x[i], sim.pos_y[i]):
				wet_war += 1
	var d0: int = sim.u_ax[r0] - b0.x
	var d1: int = sim.u_ax[r1] - b1.x
	print("    raider afloat %d m, ashore %d m in 20 s (%d %%)" % [d0 / M, d1 / M, d0 * 100 / maxi(d1, 1)])
	_check(sim.u_wet[r0] * 2 > sim.u_alive[r0], "raider 0 is still afloat (u_wet %d of %d)" % [sim.u_wet[r0], sim.u_alive[r0]])
	_check(d1 > 0 and absi(d0 * 100 / d1 - BattleSim.AMPHIB_PCT) <= 8, "afloat at AMPHIB_PCT of the pace ashore")
	_check(wet_war == 0, "foot ordered onto the water stay ashore (no man on a water cell)")
	# The sea gate: water for the raiders, nothing for the foot.
	var gx: int = sim.harb[4]
	var gy: int = sim.harb[5]
	_check((sim.nav_at(gx, gy) & sim._ground_mask(r0)) != 0, "the sea gate's passage is ground for the raiders")
	_check((sim.nav_at(gx, gy) & sim._ground_mask(war)) == 0, "... and closed to the foot")
	_check(sim.reach_u(r0, sim.u_ax[r0], sim.u_ay[r0]) == sim.reach_u(r0, sim.harb[2], sim.harb[3]),
		"the quay inside is within the raiders' reach by water")
	_check(sim.reach_u(war, sim.u_ax[war], sim.u_ay[war]) != sim.reach_u(war, sim.harb[2], sim.harb[3]),
		"... and not within the foot's (the walls between)")
	var rw: PackedInt32Array = sim.route_to(sim.u_ax[r0], sim.u_ay[r0], sim.harb[2], sim.harb[3], sim._ground_mask(r0))
	var via_gate := false
	for k in range(0, rw.size(), 2):
		if absi(rw[k] - gx) <= 4 * M and absi(rw[k + 1] - gy) <= 4 * M:
			via_gate = true
	_check(rw.size() >= 4 and via_gate, "the raiders' way to the quay goes through the sea gate")
	# The landing: raider 0 in through the sea gate to the quay.
	var lp := SiegeAI._harb_in(sim)
	_move(sim, r0, lp.x, lp.y, 1)
	var ri: int = sim.reach_at(sim.harb[2], sim.harb[3])
	var landed := -1
	for t in 2400:
		sim.step()
		if landed < 0 and sim.reach_at(sim.u_ax[r0], sim.u_ay[r0]) == ri and not sim.afloat(r0) and sim.u_order[r0] == 0:
			landed = sim.tick
			break
	_check(landed > 0, "raider 0 landed on the quay inside the walls (tick %d)" % landed)
	var ashore := 0
	var base0: int = sim.u_slot_base[r0]
	for s in sim.u_alive[r0]:
		var i: int = sim.slot_soldier[base0 + s]
		if sim.reach_at(sim.pos_x[i], sim.pos_y[i]) == ri:
			ashore += 1
	_check(ashore * 2 > sim.u_alive[r0], "... most of its men on the quay (%d of %d)" % [ashore, sim.u_alive[r0]])


func _ai_run(skill: int, ticks: int) -> Dictionary:
	var sc := Scenarios.harbour_assault(100)
	sc["ai_skill"] = [skill, skill]
	var sim := BattleSim.new()
	sim.setup(sc, 11)
	var went := 0
	var harb_x := 0
	var quay := 0
	for t in ticks:
		sim.step()
		if sim.tick % 10 != 0:
			continue
		for u in sim.n_units:
			if sim.u_side[u] == 0 and sim.u_ai[u] == SiegeAI.A_HARB:
				went = maxi(went, 1)
				harb_x = maxi(harb_x, sim.u_ai_x[u])
			if sim.u_side[u] == 1 and sim.u_ai[u] == SiegeAI.A_HQUAY:
				quay = 1
	return {"went": went, "x": harb_x, "quay": quay}


func _test_ai_harbour() -> void:
	print("the AI at Average (R_HARBOUR)")
	var r := _ai_run(1, 2400)
	_check(int(r["went"]) == 1, "the raiders go by water (A_HARB)")
	_check(int(r["x"]) >= 2, "... in through the sea gate (phase %d)" % int(r["x"]))
	_check(int(r["quay"]) == 1, "a defender holds the quay against them (A_HQUAY)")


func _test_ai_easy() -> void:
	print("the AI at Easy (no R_HARBOUR)")
	var r := _ai_run(0, 1500)
	_check(int(r["went"]) == 0, "Easy's raiders do not go by water")
	_check(int(r["quay"]) == 0, "Easy's garrison does not hold the quay")


func _test_tayasal() -> void:
	print("the lake of Tayasal: the Itza's sortie")
	var sc := Scenarios.tayasal()
	sc["ai_skill"] = [1, 1]
	var sim := BattleSim.new()
	sim.setup(sc, 3)
	var ri: int = sim.reach_at(sim.harb[2], sim.harb[3])
	var landed := -1
	var flank := false
	var afloat_seen := false
	for t in 3000:
		sim.step()
		if sim.tick % 10 != 0:
			continue
		for u in sim.n_units:
			if sim.u_side[u] != sim.city_def or sim.u_ai[u] != SiegeAI.A_HSORTIE:
				continue
			if sim.afloat(u):
				afloat_seen = true
			if landed < 0 and sim.u_ai_x[u] >= 2:
				landed = sim.tick
				var ra: int = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
				var att_piece := -1
				for o in sim.n_units:
					if sim.u_side[o] != sim.city_def and sim.u_state[o] == 0:
						att_piece = sim.reach_at(sim.u_ax[o], sim.u_ay[o])
						if att_piece >= 0:
							break
				flank = ra >= 0 and ra != ri and ra == att_piece
		if landed > 0:
			break
	_check(afloat_seen, "the sortie paddles out of the sea gate")
	_check(landed > 0, "it lands (tick %d)" % landed)
	_check(flank, "... on the attackers' ground outside the walls")


func _test_quay() -> void:
	print("the open quay (west_port's map, R_HARBOUR at Average)")
	var sc := Scenarios.quay_raid()
	var sim := BattleSim.new()
	sim.setup(sc, 21)
	_check(sim.harb.is_empty() and sim.quay.size() == 4, "a West open town: no sea gate, a quay landing (BattleSim.quay)")
	var fo: Vector3i = sim._quay_fort()
	_check(fo.z > 0 and _len(sim.quay[0] - fo.x, sim.quay[1] - fo.y) >= fo.z + BattleSim.QUAY_FORT_R,
		"the landing beyond the harbour fort's bastions by QUAY_FORT_R")
	var went := false
	var landed := -1
	var quay := false
	for t in 2400:
		sim.step()
		if sim.tick % 10 != 0:
			continue
		for u in sim.n_units:
			if sim.u_state[u] != 0:
				continue
			if sim.u_side[u] == 0 and sim.u_ai[u] == SiegeAI.A_HARB:
				went = true
			if went and landed < 0 and sim.amphib(u) and sim.u_side[u] == 0 and not sim.afloat(u) \
					and _len(sim.u_ax[u] - sim.quay[0], sim.u_ay[u] - sim.quay[1]) <= SiegeAI.QUAY_LANDED:
				landed = sim.tick
			if sim.u_side[u] == 1 and sim.u_ai[u] == SiegeAI.A_HQUAY:
				quay = true
		if landed > 0 and quay:
			break
	_check(went, "the raiders go round by water for the quay (A_HARB)")
	_check(landed > 0, "they land on the quay (tick %d)" % landed)
	_check(quay, "a defender holds the quay (A_HQUAY)")


static func _len(dx: int, dy: int) -> int:
	return int(sqrt(float(dx) * float(dx) + float(dy) * float(dy)))


func _test_snapshot() -> void:
	print("snapshot / restore across a water move; two runs")
	var q := _quiet()
	var a := BattleSim.new()
	a.setup(q["sc"], 7)
	var r0: int = q["r0"]
	_move(a, r0, a.harb[0], a.harb[1], 1)
	for t in 150:
		a.step()
	_check(a.afloat(r0), "mid-paddle at the snapshot")
	var blob: PackedByteArray = a.snapshot()
	var b := BattleSim.new()
	b.setup(q["sc"], 7)
	_check(b.restore(blob), "restore accepted")
	_check(b.state_hash() == a.state_hash(), "the same hash after restore")
	for t in 300:
		a.step()
		b.step()
	_check(b.state_hash() == a.state_hash(), "the same hash 30 s on")
	var c := BattleSim.new()
	c.setup(q["sc"], 7)
	_move(c, r0, c.harb[0], c.harb[1], 1)
	for t in 450:
		c.step()
	_check(c.state_hash() == a.state_hash(), "a second run from the start gives the same hash")
